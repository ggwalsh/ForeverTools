-- ForeverTools 1.0.2. Forever beta Interface 16001; 120105 kept for Midnight-family clients.

local ADDON_NAME = "ForeverTools"
local SELL_CAP, LOOT_TICK_MAX, TICK = 11, 40, 0.05

local db, optionsFrame
local sellGeneration, lootGeneration = 0, 0
local merchantOpen, sellBusy = false, false
local junkHooked = false

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

local function ItemSellPrice(itemID, link)
	if C_Item and C_Item.GetItemInfo then
		local ok, info = pcall(C_Item.GetItemInfo, itemID or link)
		if ok and type(info) == "table" then
			local p = AsNumber(info.sellPrice)
			if p then return p end
		end
	end
	if type(GetItemInfo) == "function" then
		local ok, price = pcall(function() return select(11, GetItemInfo(itemID or link)) end)
		if ok then return AsNumber(price) end
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

local function PlayerMoney()
	if type(GetMoney) == "function" then
		local ok, m = pcall(GetMoney)
		if ok then return AsNumber(m) or 0 end
	end
	return 0
end

local function HasExcludeIds()
	return type(db.excludeIds) == "table" and next(db.excludeIds) ~= nil
end

local FEATURE_EVENTS = {
	"LOOT_READY", "LOOT_OPENED", "MERCHANT_SHOW", "MERCHANT_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}

local function ApplyEventRegistration()
	for i = 1, #FEATURE_EVENTS do pcall(frame.UnregisterEvent, frame, FEATURE_EVENTS[i]) end
	if not db or not db.enabled then return end
	local function reg(name) pcall(frame.RegisterEvent, frame, name) end
	if db.fastLoot then reg("LOOT_READY") reg("LOOT_OPENED") end
	if db.sellJunk or db.repair then
		reg("MERCHANT_SHOW") reg("MERCHANT_CLOSED")
		reg("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
		reg("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
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

local function CollectJunk()
	local list = {}
	if not db.sellJunk then return list end
	local exclude = db.excludeIds or {}
	for bag = 0, MaxBagIndex() do
		for slot = 1, BagSlotCount(bag) do
			if #list >= SELL_CAP then return list end
			local info = BagItemInfo(bag, slot)
			local id = SlotItemID(bag, slot, info)
			local link = SlotLink(bag, slot, info)
			if not id and link then id = tonumber(tostring(link):match("item:(%d+)")) end
			if id and not exclude[id] and not (info and info.isLocked) then
				if IsPoorQuality(id, link, info and info.quality) then
					if not (info and info.hasNoValue) then
						local price = info and info.sellPrice
						if price == nil then price = ItemSellPrice(id, link) end
						if price == nil or price > 0 then
							local stacks = (info and info.stackCount) or 1
							list[#list + 1] = {
								bag = bag,
								slot = slot,
								copper = (price or 0) * stacks,
							}
						end
					end
				end
			end
		end
	end
	return list
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
		parts[#parts + 1] = "Sold " .. soldCount .. " junk for " .. CoinString(soldCopper)
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
	local moneyBefore = PlayerMoney()

	local function finish(count, copper)
		if gen ~= sellGeneration then return end
		sellBusy = false
		PrintSummary(repairInfo.copper, count or 0, copper or 0, repairInfo.unaffordable)
	end

	local function finishFromMoney(hint)
		local gained = math.max(0, PlayerMoney() - moneyBefore)
		local n = hint or 0
		if n <= 0 and gained > 0 then n = 1 end
		finish(n, gained)
	end

	local function sellPerItem(list)
		local soldCount, soldCopper = 0, 0
		local function take(item)
			if UseBagItem(item.bag, item.slot) then
				soldCount = soldCount + 1
				soldCopper = soldCopper + (item.copper or 0)
			end
		end
		if #list == 0 then
			if not HasExcludeIds() and SellAllJunkNow() then
				After(0.35, function() finishFromMoney(1) end)
				return
			end
			finish(0, 0)
			return
		end
		local function afterItems()
			if merchantOpen and soldCount == 0 and not HasExcludeIds() and SellAllJunkNow() then
				After(0.35, function() finishFromMoney(#list) end)
				return
			end
			finish(soldCount, soldCopper)
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

	local function runSell()
		if gen ~= sellGeneration or not merchantOpen then
			sellBusy = false
			return
		end
		if not db.sellJunk then
			finish(0, 0)
			return
		end
		if not HasExcludeIds() and SellAllJunkNow() then
			After(0.35, function()
				if gen ~= sellGeneration then return end
				if PlayerMoney() > moneyBefore then
					finishFromMoney(1)
					return
				end
				sellPerItem(CollectJunk())
			end)
			return
		end
		sellPerItem(CollectJunk())
	end

	After(0.25, runSell)
end

local function OnMerchantClosed()
	merchantOpen = false
	sellBusy = false
	sellGeneration = sellGeneration + 1
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

	AddHeader("General")
	local cEnable = AddCheck("Enable ForeverTools", "enabled", "Master switch. Turns off all events when unchecked.")

	local footer = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	footer:SetPoint("TOPLEFT", 16, y - 4)
	footer:SetPoint("RIGHT", child, "RIGHT", -8, 0)
	footer:SetJustifyH("LEFT")
	if footer.SetWordWrap then footer:SetWordWrap(true) end
	footer:SetText("Hold Shift when opening a vendor or corpse to skip once.")
	y = y - 40
	child:SetHeight(math.max(400, -y + 16))

	local checks = { cFast, cCVar, cSell, cRepair, cGuild, cSum, cEnable }
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

local function OnAddonLoaded(name)
	if name ~= ADDON_NAME then return end
	if type(ForeverToolsDB) ~= "table" then ForeverToolsDB = {} end
	CopyDefaults(ForeverToolsDB, defaults)
	if type(ForeverToolsDB.excludeIds) ~= "table" then ForeverToolsDB.excludeIds = {} end
	db = ForeverToolsDB
	ApplyEventRegistration()
	HookJunkConfirm()
	SLASH_FOREVERTOOLS1 = "/ft"
	SLASH_FOREVERTOOLS2 = "/forevertools"
	SlashCmdList["FOREVERTOOLS"] = ToggleOptions
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		OnAddonLoaded(arg1)
		if arg1 == "Blizzard_UIPanels_Game" then HookJunkConfirm() end
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		OnLoot()
	elseif event == "MERCHANT_SHOW" then
		OnMerchantShow()
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		if IsMerchantArg(arg1) then OnMerchantShow() end
	elseif event == "MERCHANT_CLOSED" or event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		if event == "MERCHANT_CLOSED" or IsMerchantArg(arg1) then OnMerchantClosed() end
	end
end)
