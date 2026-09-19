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

local function CollectJunk()
	local list = {}
	if not db.sellJunk then return list end
	local exclude = db.excludeIds or {}
	for bag = 0, MaxBagIndex() do
		for slot = 1, BagSlotCount(bag) do
			if #list >= SELL_CAP then return list end
			local info = BagItemInfo(bag, slot)
			local id = SlotItemID(bag, slot)
			local link = SlotLink(bag, slot, info)
			if not id and link then id = tonumber(tostring(link):match("item:(%d+)")) end
			if id and not exclude[id] and not (info and info.isLocked) then
				local quality = info and info.quality
				if IsPoorQuality(id, link, quality) then
					if not (info and info.hasNoValue) then
						local price = info and info.sellPrice
						if price == nil then price = ItemSellPrice(id, link) end
						if price == nil or price > 0 then
							local stacks = (info and info.stackCount) or 1
							list[#list + 1] = { bag = bag, slot = slot, copper = (price or 0) * stacks }
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

local function AcceptJunkPopup()
	if not db or not db.sellJunk then return false end
	for i = 1, (STATICPOPUP_NUMDIALOGS or 4) do
		local popup = _G["StaticPopup" .. i]
		if popup and popup.IsShown and popup:IsShown() then
			local text
			if popup.text and popup.text.GetText then
				text = popup.text:GetText()
			elseif popup.GetText then
				text = popup:GetText()
			end
			if PopupLooksLikeJunk(text) then
				local btn = popup.button1 or _G["StaticPopup" .. i .. "Button1"]
				if btn and btn.Click then
					btn:Click()
					return true
				end
				if type(StaticPopup_OnClick) == "function" then
					pcall(StaticPopup_OnClick, popup, 1)
					return true
				end
			end
		end
	end
	return false
end

local function ClickBlizzardSellJunk()
	local btn = MerchantFrameSellAllJunkButton
		or (MerchantFrame and (MerchantFrame.SellAllJunkButton or MerchantFrame.sellAllJunkButton))
	if btn and btn.Click then
		pcall(function() btn:Click() end)
		return true
	end
	if type(MerchantFrame_OnSellAllJunkButtonClicked) == "function" then
		return SafeCall(MerchantFrame_OnSellAllJunkButtonClicked, btn)
	end
	return false
end

local function BulkSellJunk()
	if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
		return SafeCall(C_MerchantFrame.SellAllJunkItems)
	end
	return false
end
