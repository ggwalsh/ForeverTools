-- ForeverTools 1.0.0
-- TOC Interface 120105 may need bumping for the Forever beta client.

local ADDON_NAME = "ForeverTools"
local SELL_CAP, LOOT_TICK_MAX, TICK = 11, 40, 0.05

local db, optionsFrame
local sellGeneration, lootGeneration = 0, 0

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
	if type(GetItemInfo) ~= "function" then return nil end
	local ok, price = pcall(function() return select(11, GetItemInfo(itemID or link)) end)
	if ok then return price end
end

local function MaxBagIndex()
	local n = NUM_BAG_SLOTS or 4
	if NUM_REAGENTBAG_SLOTS and NUM_REAGENTBAG_SLOTS > 0 then
		n = n + NUM_REAGENTBAG_SLOTS
	end
	return n
end

local function MerchantIsOpen()
	if MerchantFrame and MerchantFrame.IsShown then
		return MerchantFrame:IsShown()
	end
	return true
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
	local money = 0
	if type(GetMoney) == "function" then
		local ok, m = pcall(GetMoney)
		if ok and m then money = m end
	end
	if money >= cost then
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
			if info and not info.isLocked and info.quality == 0 and not info.hasNoValue then
				local id = info.itemID
				if not id and info.hyperlink then
					id = tonumber(tostring(info.hyperlink):match("item:(%d+)"))
				end
				if id and not exclude[id] then
					local price = info.sellPrice
					if price == nil then price = ItemSellPrice(id, info.hyperlink) end
					if price and price > 0 then
						list[#list + 1] = { bag = bag, slot = slot, copper = price * (info.stackCount or 1) }
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

local function OnMerchantShow()
	if not db or not db.enabled then return end
	if IsShiftKeyDown and IsShiftKeyDown() then return end
	sellGeneration = sellGeneration + 1
	local gen = sellGeneration
	local repairInfo = DoRepair()
	local junk = CollectJunk()
	local soldCount, soldCopper = 0, 0
	local function finish()
		PrintSummary(repairInfo.copper, soldCount, soldCopper, repairInfo.unaffordable)
	end
	local function take(item)
		if UseBagItem(item.bag, item.slot) then
			soldCount = soldCount + 1
			soldCopper = soldCopper + (item.copper or 0)
		end
	end
	if #junk == 0 then finish() return end
	local function sellOne(i)
		if gen ~= sellGeneration or not MerchantIsOpen() then return end
		local item = junk[i]
		if not item then finish() return end
		take(item)
		if i >= #junk then finish() return end
		if not After(TICK, function() sellOne(i + 1) end) then
			for j = i + 1, #junk do
				if gen ~= sellGeneration or not MerchantIsOpen() then break end
				take(junk[j])
			end
			finish()
		end
	end
	if After(TICK, function() sellOne(1) end) then return end
	for i = 1, #junk do
		if not MerchantIsOpen() then break end
		take(junk[i])
	end
	finish()
end

local function OnMerchantClosed()
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

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
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
	SLASH_FOREVERTOOLS1 = "/ft"
	SLASH_FOREVERTOOLS2 = "/forevertools"
	SlashCmdList["FOREVERTOOLS"] = ToggleOptions
end

frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		OnAddonLoaded(arg1)
	elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
		OnLoot()
	elseif event == "MERCHANT_SHOW" then
		OnMerchantShow()
	elseif event == "MERCHANT_CLOSED" then
		OnMerchantClosed()
	end
end)
