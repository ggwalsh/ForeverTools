-- ForeverTools 1.1.1. Forever beta Interface 16001; 120105 kept for Midnight-family clients.

local ADDON_NAME = "ForeverTools"
local SELL_CAP, LOOT_TICK_MAX, TICK = 11, 40, 0.05

local db, optionsFrame
local sellGeneration, lootGeneration = 0, 0
local merchantOpen, sellBusy = false, false
local junkHooked = false
local lootAttempted, lootTicking = {}, false
local snapshot, sharedInLog, pendingFromParty, shareQueued, shareAttempts = {}, {}, {}, {}, {}

local defaults = {
	enabled = true,
	fastLoot = true,
	fastLootCVarOnly = true,
	sellJunk = true,
	repair = true,
	guildRepair = false,
	summary = true,
	excludeIds = {},
	autoAccept = true,
	autoShare = true,
	autoTurnin = true,
	announce = true,
}

local frame = CreateFrame("Frame", "ForeverToolsFrame")

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				CopyDefaults(dst[k], v)
			else
				dst[k] = v
			end
		end
	end
end

local function After(delay, fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(delay, fn)
		return true
	end
	fn()
	return false
end

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return false end
	return true, a, b, c, d
end

local function Plain(v)
	if v == nil then return nil end
	if issecretvalue then
		local ok, secret = pcall(issecretvalue, v)
		if ok and secret then return nil end
	end
	return v
end

local function AsNumber(v)
	v = Plain(v)
	if v == nil then return nil end
	local ok, n = pcall(tonumber, v)
	if ok then return n end
end

local function CoinString(copper)
	copper = AsNumber(copper) or 0
	if type(GetCoinTextureString) == "function" then
		local ok, s = pcall(GetCoinTextureString, copper)
		if ok and s then return s end
	end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "g" end
	if s > 0 then parts[#parts + 1] = s .. "s" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
	return table.concat(parts, " ")
end

local function Chat(msg)
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("|cffc41e3aForeverTools|r: " .. msg)
	end
end

local function PlayCheckSound(checked)
	if type(PlaySound) ~= "function" then return end
	local id = SOUNDKIT and (checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
	if id then pcall(PlaySound, id) return end
	pcall(PlaySound, checked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
end

local function BagSlotCount(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		local ok, n = pcall(C_Container.GetContainerNumSlots, bag)
		if ok then return AsNumber(n) or 0 end
	end
	if type(GetContainerNumSlots) == "function" then
		local ok, n = pcall(GetContainerNumSlots, bag)
		if ok then return AsNumber(n) or 0 end
	end
	return 0
end

local function BagItemInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(info) == "table" then
			return {
				itemID = Plain(info.itemID),
				quality = Plain(info.quality),
				isLocked = Plain(info.isLocked),
				hyperlink = Plain(info.hyperlink),
				stackCount = AsNumber(info.stackCount) or 1,
				hasNoValue = Plain(info.hasNoValue),
				sellPrice = AsNumber(info.sellPrice),
			}
		end
	end
	if type(GetContainerItemInfo) == "function" then
		local ok, texture, itemCount, locked, quality, _, _, itemLink, _, noValue, itemID = pcall(GetContainerItemInfo, bag, slot)
		if ok and texture then
			return {
				itemID = Plain(itemID),
				quality = Plain(quality),
				isLocked = Plain(locked),
				hyperlink = Plain(itemLink),
				stackCount = AsNumber(itemCount) or 1,
				hasNoValue = Plain(noValue),
			}
		end
	end
end

local function SlotItemID(bag, slot, info)
	if C_Container and C_Container.GetContainerItemID then
		local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
		if ok and Plain(id) then return Plain(id) end
	end
	if info and info.itemID then return info.itemID end
	if info and info.hyperlink then return tonumber(tostring(info.hyperlink):match("item:(%d+)")) end
end

local function SlotLink(bag, slot, info)
	if info and info.hyperlink then return info.hyperlink end
	if C_Container and C_Container.GetContainerItemLink then
		local ok, link = pcall(C_Container.GetContainerItemLink, bag, slot)
		if ok then return Plain(link) end
	end
end

local function UseBagItem(bag, slot)
	if C_Container and C_Container.UseContainerItem then
		return SafeCall(C_Container.UseContainerItem, bag, slot)
	end
	if type(UseContainerItem) == "function" then
		return SafeCall(UseContainerItem, bag, slot)
	end
	return false
end

local function UnpackSellPrice(fn, arg)
	if type(fn) ~= "function" or arg == nil then return end
	-- GetItemInfo / C_Item.GetItemInfo: sell price is the 11th return, not a table field.
	local ok, a, _, _, _, _, _, _, _, _, _, sellPrice = pcall(fn, arg)
	if not ok or a == nil then return end
	if type(a) == "table" then return AsNumber(a.sellPrice or a.vendorPrice) end
	return AsNumber(sellPrice)
end

local function ItemSellPrice(itemID, link)
	local cget = C_Item and C_Item.GetItemInfo
	local price = UnpackSellPrice(cget, link or itemID) or UnpackSellPrice(cget, itemID)
	if price ~= nil then return price end
	price = UnpackSellPrice(GetItemInfo, link or itemID) or UnpackSellPrice(GetItemInfo, itemID)
	return price
end

local function TooltipStackPrice(bag, slot)
	if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return end
	local ok, data = pcall(C_TooltipInfo.GetBagItem, bag, slot)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return end
	local sellType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
	for i = 1, #data.lines do
		local line = data.lines[i]
		if line and (not sellType or line.type == sellType) then
			local price = AsNumber(line.price)
			if price and price > 0 then return price end
		end
	end
end

local function IsPoorQuality(id, link, reported)
	local q = AsNumber(reported)
	if q == nil and C_Item and C_Item.GetItemQualityByID and id then
		local ok, v = pcall(C_Item.GetItemQualityByID, id)
		if ok then q = AsNumber(v) end
	end
	if q == nil and type(GetItemInfo) == "function" then
		local ok, v = pcall(function() return select(3, GetItemInfo(id or link)) end)
		if ok then q = AsNumber(v) end
	end
	if q == nil and type(link) == "string" then
		local color = link:match("|c(%x%x%x%x%x%x%x%x)")
		if color and color:lower() == "ff9d9d9d" then return true end
	end
	return q == 0
end

local function MaxBagIndex()
	local n = NUM_BAG_SLOTS or 4
	if NUM_REAGENTBAG_SLOTS and NUM_REAGENTBAG_SLOTS > 0 then
		n = n + NUM_REAGENTBAG_SLOTS
	end
	return n
end

local function MerchantType()
	local t = Enum and Enum.PlayerInteractionType
	return t and (t.Merchant or t.Vendor)
end

local function MerchantIsOpen()
	if merchantOpen then return true end
	if C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType then
		local kind = MerchantType()
		if kind then
			local ok, v = pcall(C_PlayerInteractionManager.IsInteractingWithNpcOfType, kind)
			if ok and v then return true end
		end
	end
	return false
end

local function IsMerchantArg(arg)
	local kind = MerchantType()
	if kind and arg == kind then return true end
	return false
end

local function MoneyNow()
	if type(GetMoney) ~= "function" then return end
	local ok, m = pcall(GetMoney)
	if not ok or m == nil then return end
	if issecretvalue then
		local okS, secret = pcall(issecretvalue, m)
		if okS and secret then return end
	end
	local n = tonumber(m)
	if n and n >= 0 then return n end
end

local function PlayerMoney()
	return MoneyNow() or 0
end

local function HasExcludeIds()
	return type(db.excludeIds) == "table" and next(db.excludeIds) ~= nil
end

local FEATURE_EVENTS = {
	"LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "UI_ERROR_MESSAGE",
	"MERCHANT_SHOW", "MERCHANT_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
	"QUEST_DETAIL", "QUEST_ACCEPT_CONFIRM", "GOSSIP_SHOW", "QUEST_GREETING",
	"QUEST_ACCEPTED", "QUEST_PROGRESS", "QUEST_COMPLETE",
	"QUEST_WATCH_UPDATE", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
}

local function ApplyEventRegistration()
	for i = 1, #FEATURE_EVENTS do pcall(frame.UnregisterEvent, frame, FEATURE_EVENTS[i]) end
	if not db or not db.enabled then return end
	local function reg(name) pcall(frame.RegisterEvent, frame, name) end
	if db.fastLoot then reg("LOOT_READY") reg("LOOT_OPENED") reg("LOOT_CLOSED") reg("UI_ERROR_MESSAGE") end
	if db.sellJunk or db.repair then
		reg("MERCHANT_SHOW") reg("MERCHANT_CLOSED")
		reg("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
		reg("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
	end
	if db.autoAccept or db.autoShare or db.autoTurnin or db.announce then
		reg("QUEST_DETAIL") reg("QUEST_ACCEPT_CONFIRM") reg("GOSSIP_SHOW") reg("QUEST_GREETING")
		reg("QUEST_ACCEPTED") reg("QUEST_PROGRESS") reg("QUEST_COMPLETE")
		reg("QUEST_WATCH_UPDATE") reg("QUEST_LOG_UPDATE") reg("UNIT_QUEST_LOG_CHANGED")
	end
end

local function CVarAutoLootOn()
	if type(GetCVar) ~= "function" then return false end
	local ok, v = pcall(GetCVar, "autoLootDefault")
	return ok and (v == "1" or v == 1 or v == true)
end

local function LootModifierHeld()
	if type(IsModifiedClick) == "function" then
		local ok, held = pcall(IsModifiedClick, "AUTOLOOTTOGGLE")
		if ok then return not not held end
	end
	return false
end

local function WouldAutoLoot()
	local cvarOn, modHeld = CVarAutoLootOn(), LootModifierHeld()
	local would = (cvarOn and not modHeld) or ((not cvarOn) and modHeld)
	if db.fastLootCVarOnly then return would and cvarOn end
	return would
end

local function PlayerIsMasterLooter()
	if type(GetLootMethod) ~= "function" then return false, false end
	local ok, method, partyML, raidML = pcall(GetLootMethod)
	if not ok or method ~= "master" then return false, method == "master" end
	if partyML == 0 then return true, true end
	if raidML and type(GetRaidRosterInfo) == "function" and type(UnitName) == "function" then
		local ok2, name = pcall(GetRaidRosterInfo, raidML)
		if ok2 and name and UnitName("player") == name then return true, true end
	end
	return false, true
end

local function SlotEligible(index)
	if type(GetLootSlotInfo) ~= "function" then return false end
	local ok, texture, _, _, _, quality, locked = pcall(GetLootSlotInfo, index)
	if not ok or not texture then
		if type(LootSlotHasItem) ~= "function" then return false end
		local ok2, has = pcall(LootSlotHasItem, index)
		if not ok2 or not has then return false end
	end
	if locked then return false end
	local isML, isMasterMethod = PlayerIsMasterLooter()
	if isMasterMethod and not isML and type(GetLootThreshold) == "function" then
		local okT, threshold = pcall(GetLootThreshold)
		if okT and threshold and quality and AsNumber(quality) and AsNumber(quality) >= AsNumber(threshold) then
			return false
		end
	end
	return true
end

local function NextLootSlot()
	if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then return false end
	for i = GetNumLootItems() or 0, 1, -1 do
		if not lootAttempted[i] and SlotEligible(i) then
			lootAttempted[i] = true
			pcall(LootSlot, i)
			return true
		end
	end
	return false
end

local function ResetLoot()
	lootGeneration = lootGeneration + 1
	lootTicking = false
	lootAttempted = {}
end

local function OnLoot()
	if not db or not db.enabled or not db.fastLoot then return end
	if IsShiftKeyDown and IsShiftKeyDown() then return end
	if not WouldAutoLoot() or lootTicking then return end
	if not (C_Timer and C_Timer.After) then while NextLootSlot() do end return end
	lootGeneration = lootGeneration + 1
	local gen = lootGeneration
	lootTicking = true
	local ticks = 0
	local function step()
		if gen ~= lootGeneration then lootTicking = false return end
		ticks = ticks + 1
		if ticks <= LOOT_TICK_MAX and NextLootSlot() then After(TICK, step) else lootTicking = false end
	end
	step()
end

local function DoRepair()
	local result = { copper = 0, unaffordable = false }
	if not db.repair then return result end
	if type(CanMerchantRepair) == "function" then
		local ok, can = pcall(CanMerchantRepair)
		if not ok or not can then return result end
	end
	local cost
	if type(GetRepairAllCost) == "function" then
		local ok, c = pcall(GetRepairAllCost)
		if ok then cost = AsNumber(c) end
	end
	if not cost or cost == 0 then return result end
	if db.guildRepair and type(CanGuildBankRepair) == "function" then
		local ok, canGuild = pcall(CanGuildBankRepair)
		if ok and canGuild then
			SafeCall(RepairAllItems, true)
			if type(GetRepairAllCost) == "function" then
				local ok2, remain = pcall(GetRepairAllCost)
				if ok2 then
					remain = AsNumber(remain)
					if not remain or remain == 0 then
						result.copper = cost
						return result
					end
					result.copper = cost - remain
					cost = remain
				end
			end
		end
	end
	if PlayerMoney() >= cost then
		if not SafeCall(RepairAllItems, false) then SafeCall(RepairAllItems) end
		result.copper = result.copper + cost
	else
		result.unaffordable = true
	end
	return result
end

local function CollectJunk(cap)
	local list = {}
	if not db.sellJunk then return list end
	local exclude = db.excludeIds or {}
	cap = cap or SELL_CAP
	for bag = 0, MaxBagIndex() do
		for slot = 1, BagSlotCount(bag) do
			if #list >= cap then return list end
			local info = BagItemInfo(bag, slot)
			local id = SlotItemID(bag, slot, info)
			local link = SlotLink(bag, slot, info)
			if not id and link then id = tonumber(tostring(link):match("item:(%d+)")) end
			if id and not exclude[id] and not (info and info.isLocked) then
				if IsPoorQuality(id, link, info and info.quality) then
					if not (info and info.hasNoValue) then
						local stacks = (info and info.stackCount) or 1
						local unit = info and info.sellPrice
						if unit == nil or unit <= 0 then
							local looked = ItemSellPrice(id, link)
							if looked ~= nil then unit = looked end
						end
						local copper, priced, noValue
						if unit ~= nil and unit <= 0 then noValue = true end
						if unit and unit > 0 then copper, priced = unit * stacks, true end
						if not priced then
							local stackPrice = TooltipStackPrice(bag, slot)
							if stackPrice and stackPrice > 0 then
								copper, priced, noValue = stackPrice, true, false
							end
						end
						if not noValue then
							if not priced and C_Item and C_Item.RequestLoadItemDataByID then
								pcall(C_Item.RequestLoadItemDataByID, id)
							end
							list[#list + 1] = {
								bag = bag, slot = slot, id = id, link = link,
								stacks = stacks, copper = copper or 0, priced = priced,
							}
						end
					end
				end
			end
		end
	end
	return list
end

local function FillJunkPrices(list)
	local missing = false
	for i = 1, #list do
		local item = list[i]
		if not item.priced then
			local unit = ItemSellPrice(item.id, item.link)
			if unit and unit > 0 then
				item.copper = unit * (item.stacks or 1)
				item.priced = true
			else
				local stackPrice = TooltipStackPrice(item.bag, item.slot)
				if stackPrice and stackPrice > 0 then
					item.copper = stackPrice
					item.priced = true
				else
					if C_Item and C_Item.RequestLoadItemDataByID and item.id then
						pcall(C_Item.RequestLoadItemDataByID, item.id)
					end
					missing = true
				end
			end
		end
	end
	return not missing
end

local function JunkNum()
	if C_MerchantFrame and C_MerchantFrame.GetNumJunkItems then
		local ok, n = pcall(C_MerchantFrame.GetNumJunkItems)
		if ok then return AsNumber(n) end
	end
end

local function SlotStill(item)
	local info = BagItemInfo(item.bag, item.slot)
	return SlotItemID(item.bag, item.slot, info) == item.id
end

local function TallySold(list, moneyBefore, junkBefore)
	local count, copper, unpriced = 0, 0, 0
	for i = 1, #list do
		local item = list[i]
		if not SlotStill(item) then
			count = count + 1
			if not item.priced then
				local unit = ItemSellPrice(item.id, item.link)
				if unit and unit > 0 then
					item.copper = unit * (item.stacks or 1)
					item.priced = true
				end
			end
			if item.priced and item.copper > 0 then
				copper = copper + item.copper
			else
				unpriced = unpriced + 1
			end
		end
	end
	if count == 0 and junkBefore then
		local now = JunkNum()
		if now and junkBefore > now then count = junkBefore - now end
	end
	if unpriced > 0 or copper <= 0 then
		local after = MoneyNow()
		if moneyBefore and after and after > moneyBefore then
			copper = after - moneyBefore
		end
	end
	return count, copper
end

local function PrintSummary(repairedCopper, soldCount, soldCopper, unaffordable)
	if not db.summary then return end
	if soldCount <= 0 and repairedCopper <= 0 and not unaffordable then return end
	local parts = {}
	if repairedCopper > 0 then
		parts[#parts + 1] = "Repaired for " .. CoinString(repairedCopper)
	elseif unaffordable then
		parts[#parts + 1] = "cannot afford repair"
	end
	if soldCount > 0 then
		if soldCopper and soldCopper > 0 then
			parts[#parts + 1] = "Sold " .. soldCount .. " junk for " .. CoinString(soldCopper)
		else
			parts[#parts + 1] = "Sold " .. soldCount .. " junk"
		end
	end
	Chat(table.concat(parts, ". ") .. ".")
end

local function PopupLooksLikeJunk(text)
	if type(text) ~= "string" or text == "" then return false end
	local lower = text:lower()
	if lower:find("junk", 1, true) then return true end
	local gs = _G.SELL_ALL_JUNK_ITEMS_POPUP or _G.SELL_ALL_JUNK_ITEMS
	return gs and text == gs
end

local function HideJunkPopup()
	if type(StaticPopup_Hide) == "function" then
		pcall(StaticPopup_Hide, "GENERIC_CONFIRMATION")
		pcall(StaticPopup_Hide, "SELL_ALL_JUNK_ITEMS")
	end
end

local function SellAllJunkNow()
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
		if SafeCall(C_MerchantFrame.SellAllJunkItems) then return true end
	end
	return SafeCall(MerchantFrame_OnSellAllJunkButtonConfirmed)
end

local function AcceptJunkPopup()
	if not db or not db.sellJunk then return false end
	SellAllJunkNow()
	HideJunkPopup()
	return true
end

local function ShouldAutoJunk()
	if not db or not db.enabled or not db.sellJunk or not merchantOpen then return false end
	if IsShiftKeyDown and IsShiftKeyDown() then return false end
	return true
end

local function HookJunkConfirm()
	if junkHooked or type(hooksecurefunc) ~= "function" then return end
	if type(StaticPopup_ShowCustomGenericConfirmation) == "function" then
		pcall(hooksecurefunc, "StaticPopup_ShowCustomGenericConfirmation", function(data)
			if not ShouldAutoJunk() or type(data) ~= "table" then return end
			if not PopupLooksLikeJunk(data.text) then return end
			After(0, function()
				if type(data.callback) == "function" then pcall(data.callback) end
				AcceptJunkPopup()
			end)
		end)
		junkHooked = true
	end
	if type(MerchantFrame_OnSellAllJunkButtonClicked) == "function" then
		pcall(hooksecurefunc, "MerchantFrame_OnSellAllJunkButtonClicked", function()
			if ShouldAutoJunk() then After(0, AcceptJunkPopup) end
		end)
		junkHooked = true
	end
end

local function OnMerchantShow()
	if not db or not db.enabled then return end
	if merchantOpen and sellBusy then return end
	merchantOpen = true
	HookJunkConfirm()
	if IsShiftKeyDown and IsShiftKeyDown() then return end
	sellGeneration = sellGeneration + 1
	local gen = sellGeneration
	sellBusy = true
	local repairInfo = DoRepair()

	local function finish(count, copper)
		if gen ~= sellGeneration then return end
		sellBusy = false
		PrintSummary(repairInfo.copper, count or 0, copper or 0, repairInfo.unaffordable)
	end

	local function sellPerItem(list, moneyBefore, junkBefore)
		local function take(item)
			return UseBagItem(item.bag, item.slot)
		end
		local function afterItems(tries)
			tries = tries or 1
			After(0.2, function()
				if gen ~= sellGeneration then return end
				FillJunkPrices(list)
				local count, copper = TallySold(list, moneyBefore, junkBefore)
				if count > 0 and copper <= 0 and tries < 3 then
					After(0.35, function() afterItems(tries + 1) end)
					return
				end
				finish(count, copper)
			end)
		end
		if #list == 0 then
			finish(0, 0)
			return
		end
		local function sellOne(i)
			if gen ~= sellGeneration or not MerchantIsOpen() then
				sellBusy = false
				return
			end
			if not list[i] then afterItems() return end
			take(list[i])
			if i >= #list then afterItems() return end
			After(TICK, function() sellOne(i + 1) end)
		end
		After(TICK, function() sellOne(1) end)
	end

	local function runSell(attempt)
		if gen ~= sellGeneration or not merchantOpen then
			sellBusy = false
			return
		end
		if not db.sellJunk then
			finish(0, 0)
			return
		end
		local useAll = not HasExcludeIds()
		local list = CollectJunk(useAll and 999 or SELL_CAP)
		if not FillJunkPrices(list) and attempt < 3 then
			After(0.35, function() runSell(attempt + 1) end)
			return
		end
		local moneyBefore = MoneyNow()
		local junkBefore = JunkNum()
		local function summarize(tries)
			tries = tries or 1
			if gen ~= sellGeneration then return end
			FillJunkPrices(list)
			local count, copper = TallySold(list, moneyBefore, junkBefore)
			if count > 0 and copper <= 0 and tries < 3 then
				After(0.35, function() summarize(tries + 1) end)
				return
			end
			finish(count, copper)
		end
		if useAll and SellAllJunkNow() then
			After(0.35, summarize)
			return
		end
		sellPerItem(list, moneyBefore, junkBefore)
	end

	After(0.25, function() runSell(1) end)
end

local function OnMerchantClosed()
	merchantOpen = false
	sellBusy = false
	sellGeneration = sellGeneration + 1
end

local function ShiftSkip()
	return IsShiftKeyDown and IsShiftKeyDown()
end

local function InGroup()
	return IsInGroup and IsInGroup()
end

local function PartyChannel()
	if IsInRaid and IsInRaid() then return "RAID" end
	if InGroup() then return "PARTY" end
end

local function Say(msg)
	if not msg or msg == "" then return end
	local ch = PartyChannel()
	if not ch then return end
	local ok = pcall(function()
		if C_ChatInfo and C_ChatInfo.SendChatMessage then
			C_ChatInfo.SendChatMessage(msg, ch)
		elseif SendChatMessage then
			SendChatMessage(msg, ch)
		end
	end)
	if not ok then Chat(msg) end
end

local function CurrentQuestID()
	if type(GetQuestID) ~= "function" then return end
	local ok, id = pcall(GetQuestID)
	id = AsNumber(id)
	if id and id > 0 then return id end
end

local function IsOnQuest(questID)
	if not questID then return false end
	if C_QuestLog and C_QuestLog.IsOnQuest then
		local ok, v = pcall(C_QuestLog.IsOnQuest, questID)
		return ok and v and true or false
	end
	if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
		local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, questID)
		return ok and idx and idx > 0
	end
	return false
end

local function QuestLogIsFull()
	if not (C_QuestLog and C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
		return false
	end
	local okM, maxAccept = pcall(C_QuestLog.GetMaxNumQuestsCanAccept)
	maxAccept = AsNumber(maxAccept)
	if not okM or not maxAccept or maxAccept <= 0 then return false end
	local okN, num = pcall(C_QuestLog.GetNumQuestLogEntries)
	num = AsNumber(num) or 0
	local n = 0
	for i = 1, num do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and info and not info.isHeader then n = n + 1 end
	end
	return n >= maxAccept
end

local function QuestTitle(questID)
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then
		local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
		if ok and title and title ~= "" then return title end
	end
	return "Quest"
end

local function QuestReady(questID)
	if not questID then return false end
	if C_QuestLog and C_QuestLog.ReadyForTurnIn then
		local ok, v = pcall(C_QuestLog.ReadyForTurnIn, questID)
		if ok then return not not v end
	end
	if C_QuestLog and C_QuestLog.IsComplete then
		local ok, v = pcall(C_QuestLog.IsComplete, questID)
		if ok then return not not v end
	end
	return false
end

local function ObjectiveFull(obj)
	if not obj then return false end
	if Plain(obj.finished) then return true end
	local filled, need = AsNumber(obj.numFulfilled), AsNumber(obj.numRequired)
	if filled and need and need > 0 and filled >= need then return true end
	local text = obj.text
	if type(text) == "string" then
		local a, b = text:match("(%d+)%s*/%s*(%d+)")
		if a and b then
			a, b = tonumber(a), tonumber(b)
			if b and b > 0 and a and a >= b then return true end
		end
	end
	return false
end

local function AcceptCurrentQuest()
	if not db.autoAccept or ShiftSkip() then return end
	local qid = CurrentQuestID()
	if qid and IsOnQuest(qid) then return end
	if QuestLogIsFull() then return end
	if type(QuestGetAutoAccept) == "function" then
		local ok, auto = pcall(QuestGetAutoAccept)
		if ok and auto then
			if CloseQuest then pcall(CloseQuest) end
			return
		end
	end
	if AcceptQuest then pcall(AcceptQuest) end
end

local function GossipPickAvailable()
	if not db.autoAccept or ShiftSkip() or QuestLogIsFull() then return end
	if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests and C_GossipInfo.SelectAvailableQuest) then return end
	local ok, available = pcall(C_GossipInfo.GetAvailableQuests)
	if not ok or not available or not available[1] then return end
	local pick
	for i = 1, #available do
		local q = available[i]
		local questID = q and (q.questID or q.questId)
		if not questID or not IsOnQuest(questID) then pick = q break end
	end
	if not pick then return end
	local questID = pick.questID or pick.questId
	if questID then
		if not pcall(C_GossipInfo.SelectAvailableQuest, questID) then
			pcall(C_GossipInfo.SelectAvailableQuest, 1)
		end
	else
		pcall(C_GossipInfo.SelectAvailableQuest, 1)
	end
end

local function GreetingPickAvailable()
	if not db.autoAccept or ShiftSkip() or QuestLogIsFull() then return end
	local n = GetNumAvailableQuests and GetNumAvailableQuests() or 0
	if n > 0 and SelectAvailableQuest then pcall(SelectAvailableQuest, 1) end
end

local function GossipPickComplete()
	if not db.autoTurnin or ShiftSkip() then return false end
	if not (C_GossipInfo and C_GossipInfo.GetActiveQuests and C_GossipInfo.SelectActiveQuest) then return false end
	local ok, active = pcall(C_GossipInfo.GetActiveQuests)
	if not ok or not active then return false end
	for i = 1, #active do
		local q = active[i]
		if q then
			local questID = q.questID or q.questId
			if Plain(q.isComplete) or Plain(q.IsComplete) or QuestReady(questID) then
				if questID then
					if not pcall(C_GossipInfo.SelectActiveQuest, questID) then
						pcall(C_GossipInfo.SelectActiveQuest, i)
					end
				else
					pcall(C_GossipInfo.SelectActiveQuest, i)
				end
				return true
			end
		end
	end
	return false
end

local function GreetingPickComplete()
	if not db.autoTurnin or ShiftSkip() then return false end
	local n = GetNumActiveQuests and GetNumActiveQuests() or 0
	if n <= 0 or not SelectActiveQuest then return false end
	for i = 1, n do
		local isComplete
		if GetActiveTitle then
			local okT, _, complete = pcall(GetActiveTitle, i)
			if okT then isComplete = Plain(complete) end
		end
		if not isComplete and GetActiveQuestID then
			local okQ, qid = pcall(GetActiveQuestID, i)
			if okQ then isComplete = QuestReady(AsNumber(qid) or qid) end
		end
		if isComplete then
			pcall(SelectActiveQuest, i)
			return true
		end
	end
	return false
end

local function ProgressTurnin()
	if not db.autoTurnin or ShiftSkip() then return end
	if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then pcall(CompleteQuest) end
end

local function CompleteTurnin()
	if not db.autoTurnin or ShiftSkip() then return end
	local choices = GetNumQuestChoices and GetNumQuestChoices() or 0
	if choices > 1 or not GetQuestReward then return end
	pcall(GetQuestReward, choices == 1 and 1 or 0)
end

local function ShareQuestID(questID)
	shareQueued[questID] = nil
	if not db.autoShare or not questID then return end
	if sharedInLog[questID] then return end
	if pendingFromParty[questID] then
		pendingFromParty[questID] = nil
		sharedInLog[questID] = true
		return
	end
	if not InGroup() then sharedInLog[questID] = true return end
	if not IsOnQuest(questID) then
		local n = (shareAttempts[questID] or 0) + 1
		shareAttempts[questID] = n
		if n <= 4 then
			shareQueued[questID] = true
			After(0.4, function() ShareQuestID(questID) end)
			return
		end
		sharedInLog[questID] = true
		shareAttempts[questID] = nil
		return
	end
	if C_QuestLog and C_QuestLog.IsPushableQuest then
		local ok, push = pcall(C_QuestLog.IsPushableQuest, questID)
		if ok and not push then
			sharedInLog[questID] = true
			shareAttempts[questID] = nil
			return
		end
	end
	sharedInLog[questID] = true
	shareAttempts[questID] = nil
	if C_QuestLog and C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, questID) end
	if QuestLogPushQuest then pcall(QuestLogPushQuest) end
end

local function ScanAndAnnounce()
	if not db or not C_QuestLog or not C_QuestLog.GetNumQuestLogEntries or not C_QuestLog.GetInfo then return end
	local okN, num = pcall(C_QuestLog.GetNumQuestLogEntries)
	num = AsNumber(num) or 0
	if not okN then return end
	local seen = {}
	for i = 1, num do
		local ok, info = pcall(C_QuestLog.GetInfo, i)
		if ok and info and not info.isHeader and info.questID then
			local qid = info.questID
			seen[qid] = true
			local objectives
			if C_QuestLog.GetQuestObjectives then
				local okO, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
				if okO then objectives = objs end
			end
			if objectives then
				local prev = snapshot[qid] or {}
				local nextSnap = {}
				for idx, obj in ipairs(objectives) do
					local full = ObjectiveFull(obj)
					nextSnap[idx] = { full = full, text = Plain(obj.text) or obj.text }
					local was = prev[idx]
					if db.announce and full and was and not was.full and InGroup() then
						local text = Plain(obj.text)
						if type(text) ~= "string" or text == "" then text = "Objective complete" end
						Say(string.format("[%s] %s", QuestTitle(qid), text))
					end
				end
				snapshot[qid] = nextSnap
			end
		end
	end
	for qid in pairs(snapshot) do
		if not seen[qid] then
			snapshot[qid], sharedInLog[qid], pendingFromParty[qid] = nil, nil, nil
			shareQueued[qid], shareAttempts[qid] = nil, nil
		end
	end
	for qid in pairs(sharedInLog) do
		if not seen[qid] then sharedInLog[qid] = nil end
	end
end

local function OnQuestEvent(event, arg1, arg2)
	if not db or not db.enabled then return end
	if event == "QUEST_DETAIL" then
		local qid = CurrentQuestID()
		if qid and QuestIsFromParty and QuestIsFromParty() then pendingFromParty[qid] = true end
		AcceptCurrentQuest()
	elseif event == "QUEST_ACCEPT_CONFIRM" then
		if db.autoAccept and not ShiftSkip() and ConfirmAcceptQuest then pcall(ConfirmAcceptQuest) end
	elseif event == "GOSSIP_SHOW" then
		if not GossipPickComplete() then GossipPickAvailable() end
	elseif event == "QUEST_GREETING" then
		if not GreetingPickComplete() then GreetingPickAvailable() end
	elseif event == "QUEST_PROGRESS" then
		ProgressTurnin()
	elseif event == "QUEST_COMPLETE" then
		CompleteTurnin()
	elseif event == "QUEST_ACCEPTED" then
		local questID = AsNumber(arg2) or AsNumber(arg1)
		if not questID then return end
		if sharedInLog[questID] or shareQueued[questID] then return end
		if pendingFromParty[questID] then
			pendingFromParty[questID] = nil
			sharedInLog[questID] = true
			return
		end
		shareQueued[questID] = true
		After(0.6, function() ShareQuestID(questID) end)
	elseif event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_UPDATE" then
		ScanAndAnnounce()
	elseif event == "UNIT_QUEST_LOG_CHANGED" and arg1 == "player" then
		ScanAndAnnounce()
	end
end

local function ExcludeToText(map)
	local ids = {}
	if type(map) == "table" then
		for id in pairs(map) do ids[#ids + 1] = tonumber(id) or id end
		table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
	end
	return table.concat(ids, ", ")
end

local function TextToExclude(text)
	local map = {}
	if type(text) ~= "string" then return map end
	for id in text:gmatch("%d+") do map[tonumber(id)] = true end
	return map
end

local function SetTooltip(widget, text)
	widget:SetScript("OnEnter", function(self)
		if not GameTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(text, nil, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	widget:SetScript("OnLeave", function()
		if GameTooltip then GameTooltip:Hide() end
	end)
end

local function CreateOptions()
	if optionsFrame then return optionsFrame end
	local template = BackdropTemplateMixin and "BackdropTemplate" or nil
	local panel = CreateFrame("Frame", "ForeverToolsOptions", UIParent, template)
	panel:SetSize(420, 480)
	panel:SetPoint("CENTER", UIParent, "CENTER")
	panel:SetFrameStrata("HIGH")
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:Hide()
	if panel.SetBackdrop then
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 11, top = 11, bottom = 11 },
		})
	end

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("ForeverTools")

	CreateFrame("Button", nil, panel, "UIPanelCloseButton"):SetPoint("TOPRIGHT", -4, -4)
	if UISpecialFrames then tinsert(UISpecialFrames, "ForeverToolsOptions") end

	local scroll = CreateFrame("ScrollFrame", "ForeverToolsOptionsScroll", panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 16, -40)
	scroll:SetPoint("BOTTOMRIGHT", -36, 16)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(360, 400)
	scroll:SetScrollChild(child)

	local y = -8
	local function TryCheck(parent)
		local ok, btn = pcall(CreateFrame, "CheckButton", nil, parent, "InterfaceOptionsCheckButtonTemplate")
		if ok and btn then return btn end
		ok, btn = pcall(CreateFrame, "CheckButton", nil, parent, "UICheckButtonTemplate")
		if ok and btn then return btn end
		return CreateFrame("CheckButton", nil, parent)
	end

	local function AddHeader(text)
		y = y - 8
		local fs = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		fs:SetPoint("TOPLEFT", 16, y)
		fs:SetText(text)
		y = y - 28
	end

	local function AddCheck(label, key, tip)
		local btn = TryCheck(child)
		btn:SetPoint("TOPLEFT", 16, y)
		local fs = btn.Text or btn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		if not btn.Text then
			fs:SetPoint("LEFT", btn, "RIGHT", 2, 1)
			btn.Text = fs
		end
		fs:SetText(label)
		btn:SetChecked(not not db[key])
		btn:SetScript("OnClick", function(self)
			local checked = self:GetChecked()
			db[key] = not not checked
			PlayCheckSound(checked)
			ApplyEventRegistration()
		end)
		SetTooltip(btn, tip)
		btn._dbKey = key
		y = y - 28
		return btn
	end

	AddHeader("Loot")
	local cFast = AddCheck("Fast loot", "fastLoot", "When Auto Loot would fire, take all eligible slots immediately. Hold Shift to show the loot window.")
	local cCVar = AddCheck("Require Auto Loot setting", "fastLootCVarOnly", "Only fast-loot when the game Auto Loot option is enabled.")
	AddHeader("Vendors")
	local cSell = AddCheck("Sell junk (poor quality)", "sellJunk", "Sell poor-quality items with a vendor price. Stops at 11 items to preserve buyback. Hold Shift to skip.")
	local cRepair = AddCheck("Repair gear", "repair", "Repair equipped and bag items at a repair merchant. Hold Shift to skip.")
	local cGuild = AddCheck("Prefer guild funds", "guildRepair", "Use guild bank repair when allowed, then your gold.")
	local cSum = AddCheck("Print summary in chat", "summary", "One chat line with repair cost and junk sold.")

	local excludeLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	excludeLabel:SetPoint("TOPLEFT", 16, y)
	excludeLabel:SetText("Exclude item IDs (comma separated)")
	y = y - 22

	local edit
	local okEdit, made = pcall(CreateFrame, "EditBox", "ForeverToolsExcludeBox", child, "InputBoxTemplate")
	if okEdit and made then
		edit = made
	else
		edit = CreateFrame("EditBox", "ForeverToolsExcludeBox", child)
		if edit.SetBackdrop then
			edit:SetBackdrop({
				bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 8,
				insets = { left = 2, right = 2, top = 2, bottom = 2 },
			})
			edit:SetBackdropColor(0, 0, 0, 0.5)
		end
	end
	edit:SetAutoFocus(false)
	edit:SetSize(320, 20)
	edit:SetPoint("TOPLEFT", 20, y)
	edit:SetFontObject(ChatFontNormal or GameFontHighlight)
	edit:SetTextInsets(4, 4, 0, 0)
	local function CommitExclude(self)
		db.excludeIds = TextToExclude(self:GetText() or "")
		self:SetText(ExcludeToText(db.excludeIds))
		self:ClearFocus()
	end
	edit:SetScript("OnEnterPressed", CommitExclude)
	edit:SetScript("OnEditFocusLost", CommitExclude)
	edit:SetScript("OnEscapePressed", function(self)
		self:SetText(ExcludeToText(db.excludeIds))
		self:ClearFocus()
	end)
	y = y - 36

	AddHeader("Party")
	local cAccept = AddCheck("Auto-accept quests", "autoAccept", "Accept quests from NPCs and party shares. Hold Shift at the NPC to skip.")
	local cShare = AddCheck("Share quests with party", "autoShare", "Push a quest once when you pick it up from an NPC. Does not re-share party quests.")
	local cTurn = AddCheck("Auto-turn-in quests", "autoTurnin", "Turn in completed quests. Stops if you must choose a reward. Hold Shift to skip.")
	local cAnn = AddCheck("Announce objectives", "announce", "Print in party or raid chat when a quest objective is full.")

	AddHeader("General")
	local cEnable = AddCheck("Enable ForeverTools", "enabled", "Master switch. Turns off all events when unchecked.")

	local footer = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("TOPLEFT", 16, y - 4)
	footer:SetPoint("RIGHT", child, "RIGHT", -8, 0)
	footer:SetJustifyH("LEFT")
	if footer.SetWordWrap then footer:SetWordWrap(true) end
	footer:SetText("Hold Shift when opening a vendor, corpse, or quest NPC to skip once.")
	y = y - 40
	child:SetHeight(math.max(400, -y + 16))

	local checks = { cFast, cCVar, cSell, cRepair, cGuild, cSum, cAccept, cShare, cTurn, cAnn, cEnable }
	panel:SetScript("OnShow", function()
		for i = 1, #checks do
			local c = checks[i]
			if c and c._dbKey then c:SetChecked(not not db[c._dbKey]) end
		end
		edit:SetText(ExcludeToText(db.excludeIds))
	end)

	optionsFrame = panel
	return panel
end

local function ToggleOptions()
	local panel = CreateOptions()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end

local PARTY_SLASH = {
	accept = { "autoAccept", "auto-accept" },
	share = { "autoShare", "auto-share" },
	turnin = { "autoTurnin", "auto-turn-in" },
	turn = { "autoTurnin", "auto-turn-in" },
	announce = { "announce", "objective announce" },
	say = { "announce", "objective announce" },
}

local function PartyStatus()
	if not db then return end
	Chat(string.format("accept %s   share %s   turnin %s   announce %s",
		db.autoAccept and "on" or "off",
		db.autoShare and "on" or "off",
		db.autoTurnin and "on" or "off",
		db.announce and "on" or "off"))
end

local function OnSlash(msg)
	msg = string.lower((msg or ""):gsub("^%s+", ""):gsub("%s+$", ""))
	if msg == "status" or msg == "help" then
		PartyStatus()
		return
	end
	local spec = PARTY_SLASH[msg]
	if spec and db then
		local key = spec[1]
		db[key] = not db[key]
		PlayCheckSound(db[key])
		ApplyEventRegistration()
		Chat(spec[2] .. " " .. (db[key] and "on" or "off"))
		return
	end
	ToggleOptions()
end

local function ForeverPartyLoaded()
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		local ok, v = pcall(C_AddOns.IsAddOnLoaded, "ForeverParty")
		if ok and v then return true end
	end
	if type(IsAddOnLoaded) == "function" then
		local ok, v = pcall(IsAddOnLoaded, "ForeverParty")
		if ok and v then return true end
	end
	return false
end

local function OnAddonLoaded(name)
	if name ~= ADDON_NAME then return end
	if type(ForeverToolsDB) ~= "table" then ForeverToolsDB = {} end
	if type(ForeverPartyDB) == "table" then
		local keys = { "autoAccept", "autoShare", "autoTurnin", "announce" }
		for i = 1, #keys do
			local k = keys[i]
			if ForeverToolsDB[k] == nil and ForeverPartyDB[k] ~= nil then
				ForeverToolsDB[k] = not not ForeverPartyDB[k]
			end
		end
	end
	CopyDefaults(ForeverToolsDB, defaults)
	if type(ForeverToolsDB.excludeIds) ~= "table" then ForeverToolsDB.excludeIds = {} end
	db = ForeverToolsDB
	ApplyEventRegistration()
	HookJunkConfirm()
	SLASH_FOREVERTOOLS1 = "/ft"
	SLASH_FOREVERTOOLS2 = "/forevertools"
	SLASH_FOREVERTOOLS3 = "/fp"
	SLASH_FOREVERTOOLS4 = "/foreverparty"
	SlashCmdList["FOREVERTOOLS"] = OnSlash
	if ForeverPartyLoaded() then
		Chat("Disable the ForeverParty addon folder — those features now live here.")
	end
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "ADDON_LOADED" then
		OnAddonLoaded(arg1)
		if arg1 == "Blizzard_UIPanels_Game" then HookJunkConfirm() end
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		OnLoot()
	elseif event == "LOOT_CLOSED" then
		ResetLoot()
	elseif event == "UI_ERROR_MESSAGE" and lootTicking and arg2 == ERR_INV_FULL then
		lootGeneration = lootGeneration + 1
		lootTicking = false
		if type(GetNumLootItems) == "function" then
			for i = 1, GetNumLootItems() or 0 do lootAttempted[i] = true end
		end
	elseif event == "MERCHANT_SHOW" then
		OnMerchantShow()
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		if IsMerchantArg(arg1) then OnMerchantShow() end
	elseif event == "MERCHANT_CLOSED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		if event == "MERCHANT_CLOSED" or IsMerchantArg(arg1) then OnMerchantClosed() end
	elseif event == "QUEST_DETAIL" or event == "QUEST_ACCEPT_CONFIRM" or event == "GOSSIP_SHOW"
		or event == "QUEST_GREETING" or event == "QUEST_ACCEPTED" or event == "QUEST_PROGRESS"
		or event == "QUEST_COMPLETE" or event == "QUEST_WATCH_UPDATE" or event == "QUEST_LOG_UPDATE"
		or event == "UNIT_QUEST_LOG_CHANGED" then
		OnQuestEvent(event, arg1, arg2)
	end
end)
