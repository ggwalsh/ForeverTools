-- ForeverTools 1.0.1
-- TOC Interface 120105 may need bumping for the Forever beta client.

local ADDON_NAME = "ForeverTools"
local SELL_CAP, LOOT_TICK_MAX, TICK = 11, 40, 0.05

local db, optionsFrame
local sellGeneration, lootGeneration = 0, 0
local merchantOpen = false

local defaults = {
	enabled = true,
	fastLoot = true,
	fastLootCVarOnly = true,
	sellJunk = true,
	repair = true,
	guildRepair = false,
	summary = true,
	excludeIds = {},
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
	return false
end

local function SafeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, a, b, c, d = pcall(fn, ...)
	if not ok then return false end
	return true, a, b, c, d
end

local function CoinString(copper)
	copper = tonumber(copper) or 0
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
		if ok then return n or 0 end
	end
	if type(GetContainerNumSlots) == "function" then
		local ok, n = pcall(GetContainerNumSlots, bag)
		if ok then return n or 0 end
	end
	return 0
end

local function BagItemInfo(bag, slot)
	if C_Container and C_Container.GetContainerItemInfo then
		local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
		if ok and type(info) == "table" then
			return {
				itemID = info.itemID,
				quality = info.quality,
				isLocked = info.isLocked,
				hyperlink = info.hyperlink,
				stackCount = info.stackCount or 1,
				hasNoValue = info.hasNoValue,
				sellPrice = info.sellPrice,
			}
		end
	end
	if type(GetContainerItemInfo) == "function" then
		local ok, texture, itemCount, locked, quality, _, _, itemLink, _, noValue, itemID = pcall(GetContainerItemInfo, bag, slot)
		if ok and texture then
			return {
				itemID = itemID,
				quality = quality,
				isLocked = locked,
				hyperlink = itemLink,
				stackCount = itemCount or 1,
				hasNoValue = noValue,
			}
		end
	end
end

local function SlotItemID(bag, slot)
	if C_Container and C_Container.GetContainerItemID then
		local ok, id = pcall(C_Container.GetContainerItemID, bag, slot)
		if ok and id then return id end
	end
	if type(GetContainerItemID) == "function" then
		local ok, id = pcall(GetContainerItemID, bag, slot)
		if ok and id then return id end
	end
	local info = BagItemInfo(bag, slot)
	if info and info.itemID then return info.itemID end
	if info and info.hyperlink then return tonumber(tostring(info.hyperlink):match("item:(%d+)")) end
end

local function SlotLink(bag, slot, info)
	if info and info.hyperlink then return info.hyperlink end
	if C_Container and C_Container.GetContainerItemLink then
		local ok, link = pcall(C_Container.GetContainerItemLink, bag, slot)
		if ok then return link end
	end
	if type(GetContainerItemLink) == "function" then
		local ok, link = pcall(GetContainerItemLink, bag, slot)
		if ok then return link end
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

local function ItemSellPrice(itemID, link)
	if C_Item and C_Item.GetItemInfo then
		local ok, info = pcall(C_Item.GetItemInfo, itemID or link)
		if ok and type(info) == "table" and info.sellPrice then return info.sellPrice end
	end
	if type(GetItemInfo) == "function" then
		local ok, price = pcall(function() return select(11, GetItemInfo(itemID or link)) end)
		if ok and price then return price end
	end
end

local function IsPoorQuality(id, link, reported)
	local q = tonumber(reported)
	if q == nil and C_Item and C_Item.GetItemQualityByID and id then
		local ok, v = pcall(C_Item.GetItemQualityByID, id)
		if ok then q = tonumber(v) end
	end
	if q == nil and type(GetItemInfo) == "function" then
		local ok, v = pcall(function() return select(3, GetItemInfo(id or link)) end)
		if ok then q = tonumber(v) end
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

local function MerchantIsOpen()
	if merchantOpen then return true end
	if C_PlayerInteractionManager and C_PlayerInteractionManager.IsInteractingWithNpcOfType then
		local t = Enum and Enum.PlayerInteractionType
		local kind = t and (t.Merchant or t.Vendor)
		if kind then
			local ok, v = pcall(C_PlayerInteractionManager.IsInteractingWithNpcOfType, kind)
			if ok and v then return true end
		end
	end
	return false
end

local function PlayerMoney()
	if type(GetMoney) == "function" then
		local ok, m = pcall(GetMoney)
		if ok then return m or 0 end
	end
	return 0
end

local function NumJunkItems()
	if C_MerchantFrame and C_MerchantFrame.GetNumJunkItems then
		local ok, n = pcall(C_MerchantFrame.GetNumJunkItems)
		if ok and n then return n end
	end
	return 0
end

local function HasExcludeIds()
	if type(db.excludeIds) ~= "table" then return false end
	return next(db.excludeIds) ~= nil
end

local function ApplyEventRegistration()
	frame:UnregisterEvent("LOOT_READY")
	frame:UnregisterEvent("LOOT_OPENED")
	frame:UnregisterEvent("MERCHANT_SHOW")
	frame:UnregisterEvent("MERCHANT_CLOSED")
	if not db or not db.enabled then return end
	if db.fastLoot then
		frame:RegisterEvent("LOOT_READY")
		frame:RegisterEvent("LOOT_OPENED")
	end
	if db.sellJunk or db.repair then
		frame:RegisterEvent("MERCHANT_SHOW")
		frame:RegisterEvent("MERCHANT_CLOSED")
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
		if okT and threshold and quality and quality >= threshold then return false end
	end
	return true
end

local function NextLootSlot()
	if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then return false end
	for i = GetNumLootItems() or 0, 1, -1 do
		if SlotEligible(i) then
			pcall(LootSlot, i)
			return true
		end
	end
	return false
end

local function LootAllNow()
	if type(GetNumLootItems) ~= "function" or type(LootSlot) ~= "function" then return end
	for i = GetNumLootItems() or 0, 1, -1 do
		if SlotEligible(i) then pcall(LootSlot, i) end
	end
end

local function OnLoot()
	if not db or not db.enabled or not db.fastLoot then return end
	if IsShiftKeyDown and IsShiftKeyDown() then return end
	if not WouldAutoLoot() then return end
	lootGeneration = lootGeneration + 1
	local gen = lootGeneration
	if not (C_Timer and C_Timer.After) then
		LootAllNow()
		return
	end
	local ticks = 0
	local function step()
		if gen ~= lootGeneration then return end
		ticks = ticks + 1
		if ticks > LOOT_TICK_MAX then return end
		if NextLootSlot() and ticks < LOOT_TICK_MAX then After(TICK, step) end
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
		if ok then cost = c end
	end
	if not cost or cost == 0 then return result end
	if db.guildRepair and type(CanGuildBankRepair) == "function" then
		local ok, canGuild = pcall(CanGuildBankRepair)
		if ok and canGuild then
			SafeCall(RepairAllItems, true)
			if type(GetRepairAllCost) == "function" then
				local ok2, remain = pcall(GetRepairAllCost)
				if ok2 then
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
	local money = PlayerMoney()
	if money >= cost then
		if not SafeCall(RepairAllItems, false) then SafeCall(RepairAllItems) end
		result.copper = result.copper + cost
	else
		result.unaffordable = true
	end
	return result
end
