ItemRack.Docking = {} -- in-progress docking candidate (Side/From/To)

-- cx, cy, left, right, top, bottom
ItemRack.BracketInfo = {
	["TOP"] = { 36, 12, .25, .75, 0, .25 },
	["BOTTOM"] = { 36, 12, .25, .75, .75, 1 },
	["LEFT"] = { 12, 36, 0, .25, .25, .75 },
	["RIGHT"] = { 12, 36, .75, 1, .25, .75 },
	["TOPLEFT"] = { 12, 12, 0, .25, 0, .25 },
	["TOPRIGHT"] = { 12, 12, .75, 1, 0, .25 },
	["BOTTOMLEFT"] = { 12, 12, 0, .25, .75, 1 },
	["BOTTOMRIGHT"] = { 12, 12, .75, 1, .75, 1 },
}

ItemRack.ReflectClicked = {} -- [id] = seconds the button stays checked
ItemRack.LockedButtons = {} -- [id] = icon currently desaturated

ItemRack.NewAnchor = nil

-- corner-relative in UIParent units: survives window resizes and per-bar scale changes
local function saveButtonPosition(id, button)
	local ls = button:GetScale()
	local bx, by = button:GetCenter()
	local cx, cy = bx * ls, by * ls
	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local hEdge = cx > w / 2 and "RIGHT" or "LEFT"
	local vEdge = cy > h / 2 and "TOP" or "BOTTOM"
	local cfg = ItemRackUser.Buttons[id]
	cfg.Corner = vEdge .. hEdge
	cfg.X = hEdge == "RIGHT" and cx - w or cx
	cfg.Y = vEdge == "TOP" and cy - h or cy
	cfg.Anchor = nil
	cfg.Left = nil
	cfg.Top = nil
end

-- converts the stored UIParent-unit offset back to button-local units
local function applyCornerPosition(button, cfg)
	local ls = button:GetScale()
	button:SetPoint("CENTER", UIParent, cfg.Corner, cfg.X / ls, cfg.Y / ls)
end

-- legacy saves (Anchor / Left+Top) are placed by their old interpretation once, then rewritten to the corner scheme
local function applyButtonPosition(id, button)
	local cfg = ItemRackUser.Buttons[id]
	button:ClearAllPoints()
	if not cfg.Corner then
		if cfg.Anchor then
			button:SetPoint(cfg.Anchor, UIParent, cfg.Anchor, cfg.X, cfg.Y)
		elseif cfg.Left then
			button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cfg.Left, cfg.Top)
		else
			button:SetPoint("CENTER", UIParent, "CENTER")
			return
		end
		saveButtonPosition(id, button)
		button:ClearAllPoints()
	end
	applyCornerPosition(button, cfg)
end

function ItemRack.InitButtons()
	ItemRackUser.Buttons = ItemRackUser.Buttons or {}

	hooksecurefunc("PaperDollItemSlotButton_OnModifiedClick", function(self, button)
		if IsAltKeyDown() then
			ItemRack.ToggleButton(self:GetID())
		end
	end)

	if CharacterAmmoSlot then
		-- own the OnClick so RightButton on the ammo slot doesn't fire UseInventoryItem(0)
		ItemRack.oldCharacterAmmoSlot_OnClick = CharacterAmmoSlot:GetScript("OnClick")
		CharacterAmmoSlot:SetScript("OnClick", ItemRack.newCharacterAmmoSlot_OnClick)
	end

	local characterModel = CharacterModelFrame or CharacterModelScene
	if characterModel then
		characterModel:HookScript("OnMouseUp", function(self, button)
			if IsAltKeyDown() then
				ItemRack.ToggleButton(20)
			end
		end)
	end

	for i = 0, 20 do
		local button = _G["ItemRackButton" .. i]
		if i < 20 then
			button:SetAttribute("type", "item")
			button:SetAttribute("slot", i)
		else
			button:SetAttribute("shift-slot*", ATTRIBUTE_NOOP)
			button:SetAttribute("alt-slot*", ATTRIBUTE_NOOP)
		end
		button:RegisterForDrag("LeftButton", "RightButton")
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		ItemRack.AddMouseoverFrame("ItemRackButton" .. i, button)

		if ItemRack.MasqueGroups and ItemRack.MasqueGroups[1] then
			ItemRack.MasqueGroups[1]:AddButton(button)
		end
	end

	ItemRack.CreateTimer("ButtonsDocking", ItemRack.ButtonsDocking, .2, 1)
	ItemRack.CreateTimer("MenuDocking", ItemRack.MenuDocking, .2, 1)

	ItemRackMenuFrame:SetScript("OnMouseDown", ItemRack.MenuFrameOnMouseDown)
	ItemRackMenuFrame:SetScript("OnMouseUp", ItemRack.MenuFrameOnMouseUp)
	ItemRackMenuFrame:EnableMouse(true)

	-- the control bar sits inside the menu's bounds, so its OnLeave must drive the menu close check
	for _, name in ipairs({ "ItemRackButtonMenuLock", "ItemRackButtonMenuQueue", "ItemRackButtonMenuOptions", "ItemRackButtonMenuClose" }) do
		_G[name]:HookScript("OnLeave", ItemRack.MenuMouseover)
	end

	ItemRack.CreateTimer("ReflectClickedUpdate", ItemRack.ReflectClickedUpdate, .2, 1)

	ItemRackFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
	ItemRackFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	ItemRackFrame:RegisterEvent("ITEM_LOCK_CHANGED")
	ItemRackFrame:RegisterEvent("UPDATE_BINDINGS")
	ItemRack.ReflectMainScale()
	ItemRack.ReflectMenuOnRight()
	ItemRack.ConstructLayout()
	ItemRack.UpdateButtonCooldowns()
	ItemRack.ReflectHideOOC()
	ItemRack.ReflectCooldownFont()
	ItemRack.UpdateCombatQueue()
	ItemRack.KeyBindingsChanged()
	ItemRack.UpdateDisableAltClick()
end

-- alt+click is a secure no-op while DisableAltClick is OFF, so PostClick can toggle the queue
function ItemRack.UpdateDisableAltClick()
	if InCombatLockdown() then return end
	local noop = ItemRackSettings.DisableAltClick == "OFF" and ATTRIBUTE_NOOP or nil
	for i = 0, 19 do
		_G["ItemRackButton" .. i]:SetAttribute("alt-slot*", noop)
	end
end

function ItemRack.newCharacterAmmoSlot_OnClick(self, button)
	if IsAltKeyDown() then
		ItemRack.ToggleButton(self:GetID())
	elseif button == "LeftButton" then
		ItemRack.oldCharacterAmmoSlot_OnClick(self, button)
	end
end

function ItemRack.AddButton(id)
	ItemRackUser.Buttons[id] = {}
	local button = _G["ItemRackButton" .. id]
	button:ClearAllPoints()
	if ItemRack.NewAnchor and ItemRackUser.Buttons[ItemRack.NewAnchor] then
		ItemRackUser.Buttons[id].Side = "LEFT"
		ItemRackUser.Buttons[id].DockTo = ItemRack.NewAnchor
		local dockinfo = ItemRack.DockInfo[ItemRackUser.Buttons[id].Side]
		button:SetPoint("LEFT", "ItemRackButton" .. ItemRack.NewAnchor, "RIGHT", dockinfo.xoff*(ItemRackUser.ButtonSpacing or 4), dockinfo.yoff*(ItemRackUser.ButtonSpacing or 4))
	else
		button:SetPoint("CENTER", UIParent, "CENTER")
	end
	ItemRack.NewAnchor = id
	_G["ItemRackButton" .. id .. "Icon"]:SetTexture(ItemRack.GetTextureBySlot(id))
	if id < 20 then
		ItemRack.SetButtonBadge(button, ItemRack.GetID(id))
	end
	button:Show()
	ItemRack.UpdateButtonCooldowns()
	if id == 20 then
		ItemRack.UpdateCurrentSet()
		if ItemRack.ReflectEventsRunning then
			ItemRack.ReflectEventsRunning()
		end
	end
end

function ItemRack.RemoveButton(id)
	if InCombatLockdown() then
		ItemRack.Print("Sorry, you can't add or remove buttons during combat.")
		return
	end
	for i in pairs(ItemRackUser.Buttons) do
		if ItemRackUser.Buttons[i].DockTo == id then
			ItemRackUser.Buttons[i].DockTo = nil
			ItemRackUser.Buttons[i].Side = nil
			local child = _G["ItemRackButton" .. i]
			local xpos, ypos = child:GetLeft(), child:GetTop()
			child:ClearAllPoints()
			child:SetPoint("TOPLEFT", "UIParent", "BOTTOMLEFT", xpos, ypos)
			saveButtonPosition(i, child)
		end
	end
	ItemRack.NewAnchor = nil
	ItemRackUser.Buttons[id] = nil
	_G["ItemRackButton" .. id]:Hide()
end

function ItemRack.ToggleButton(id)
	if InCombatLockdown() then
		ItemRack.Print("Sorry, you can't add or remove buttons during combat.")
	elseif ItemRackUser.Buttons[id] then
		ItemRack.RemoveButton(id)
	else
		ItemRack.AddButton(id)
	end
end

--[[ Button Movement ]]

function ItemRack.Near(v1, v2)
	if v1 and v2 and math.abs(v1-v2) < 12 then
		return 1
	end
end

-- shapes ItemRack<which>Bracket ("Main"/"Menu") to a side and anchors it at corner of relativeTo
function ItemRack.MoveBracket(which, side, relativeTo, corner)
	local bracket = _G["ItemRack" .. which .. "Bracket"]
	if bracket then
		local texture = _G["ItemRack" .. which .. "BracketTexture"]
		local info = ItemRack.BracketInfo[side]
		bracket:SetWidth(info[1])
		bracket:SetHeight(info[2])
		texture:SetTexCoord(info[3], info[4], info[5], info[6])
		bracket:ClearAllPoints()
		bracket:SetPoint(corner, relativeTo, corner)
		bracket:SetParent(relativeTo)
		bracket:SetAlpha(1)
		bracket:Show()
	end
end

function ItemRack.HideBrackets()
	ItemRackMainBracket:Hide()
	ItemRackMenuBracket:Hide()
	ItemRack.Docking.Side = nil
	ItemRack.Docking.From = nil
	ItemRack.Docking.To = nil
end

-- true if candidate is not already docked to button somewhere in its docking chain
function ItemRack.LegalDock(button, candidate)
	while ItemRackUser.Buttons[candidate].DockTo do
		if ItemRackUser.Buttons[candidate].DockTo == button then
			return nil
		end
		candidate = ItemRackUser.Buttons[candidate].DockTo
	end
	return 1
end

-- return button if it's not docked, or the original button of dock chain if docked
function ItemRack.FindParent(button)
	while ItemRackUser.Buttons[button].DockTo do
		button = ItemRackUser.Buttons[button].DockTo
	end
	return button
end

-- while a button drags, periodically lights up docking possibilities
function ItemRack.ButtonsDocking()
	local button = ItemRack.ButtonMoving
	if not button then
		ItemRack.StopTimer("ButtonsDocking")
		return
	end
	local dock
	local buttonID = button:GetID()
	local near = ItemRack.Near

	ItemRack.HideBrackets()

	for i in pairs(ItemRackUser.Buttons) do
		dock = _G["ItemRackButton" .. i]
		if near(button:GetLeft(), dock:GetRight()) and (near(button:GetTop(), dock:GetTop()) or near(button:GetBottom(), dock:GetBottom())) and ItemRack.LegalDock(buttonID, i) then
			ItemRack.MoveBracket("Main", "LEFT", button, "TOPLEFT")
			ItemRack.MoveBracket("Menu", "RIGHT", dock, "TOPRIGHT")
			ItemRack.Docking.Side = "LEFT"
		elseif near(button:GetRight(), dock:GetLeft()) and (near(button:GetTop(), dock:GetTop()) or near(button:GetBottom(), dock:GetBottom())) and ItemRack.LegalDock(buttonID, i) then
			ItemRack.MoveBracket("Main", "LEFT", dock, "TOPLEFT")
			ItemRack.MoveBracket("Menu", "RIGHT", button, "TOPRIGHT")
			ItemRack.Docking.Side = "RIGHT"
		elseif near(button:GetTop(), dock:GetBottom()) and (near(button:GetLeft(), dock:GetLeft()) or near(button:GetRight(), dock:GetRight())) and ItemRack.LegalDock(buttonID, i) then
			ItemRack.MoveBracket("Main", "TOP", button, "TOPLEFT")
			ItemRack.MoveBracket("Menu", "BOTTOM", dock, "BOTTOMLEFT")
			ItemRack.Docking.Side = "TOP"
		elseif near(button:GetBottom(), dock:GetTop()) and (near(button:GetLeft(), dock:GetLeft()) or near(button:GetRight(), dock:GetRight())) and ItemRack.LegalDock(buttonID, i) then
			ItemRack.MoveBracket("Main", "TOP", dock, "TOPLEFT")
			ItemRack.MoveBracket("Menu", "BOTTOM", button, "BOTTOMLEFT")
			ItemRack.Docking.Side = "BOTTOM"
		end

		if ItemRack.Docking.Side then
			ItemRack.Docking.From = buttonID
			ItemRack.Docking.To = i
			break
		end
	end
end

function ItemRack.StartMovingButton(self)
	if ItemRackUser.Locked == "ON" then return end
	if IsShiftKeyDown() then
		ItemRack.ButtonMoving = self
	else
		ItemRack.ButtonMoving = _G["ItemRackButton" .. ItemRack.FindParent(self:GetID())]
	end
	for i in pairs(ItemRackUser.Buttons) do -- highlight parent buttons
		if not ItemRackUser.Buttons[i].DockTo then
			_G["ItemRackButton" .. i]:LockHighlight()
		end
	end
	ItemRack.ButtonMoving:StartMoving()
	ItemRack.StartTimer("ButtonsDocking")
end

function ItemRack.StopMovingButton(self)
	if ItemRackUser.Locked == "ON" then return end
	ItemRack.StopTimer("ButtonsDocking")
	ItemRack.ButtonMoving:StopMovingOrSizing()
	ItemRack.NewAnchor = nil
	local buttonID = ItemRack.ButtonMoving:GetID()
	if ItemRack.Docking.Side then
		ItemRack.ButtonMoving:ClearAllPoints()
		local dockinfo = ItemRack.DockInfo[ItemRack.Docking.Side]
		ItemRack.ButtonMoving:SetPoint(ItemRack.Docking.Side, "ItemRackButton" .. ItemRack.Docking.To, ItemRack.OppositeSide[ItemRack.Docking.Side], dockinfo.xoff*(ItemRackUser.ButtonSpacing or 4), dockinfo.yoff*(ItemRackUser.ButtonSpacing or 4))
		ItemRackUser.Buttons[buttonID].DockTo = ItemRack.Docking.To
		ItemRackUser.Buttons[buttonID].Side = ItemRack.Docking.Side
		ItemRackUser.Buttons[buttonID].Corner = nil
		ItemRackUser.Buttons[buttonID].Anchor = nil
		ItemRackUser.Buttons[buttonID].X = nil
		ItemRackUser.Buttons[buttonID].Y = nil
		ItemRackUser.Buttons[buttonID].Left = nil
		ItemRackUser.Buttons[buttonID].Top = nil
	else
		ItemRackUser.Buttons[buttonID].DockTo = nil
		ItemRackUser.Buttons[buttonID].Side = nil
		saveButtonPosition(buttonID, ItemRack.ButtonMoving)
	end
	for i in pairs(ItemRackUser.Buttons) do
		_G["ItemRackButton" .. i]:UnlockHighlight()
	end
	ItemRack.HideBrackets()
end

function ItemRack.ConstructLayout()
	if InCombatLockdown() then
		table.insert(ItemRack.RunAfterCombat, "ConstructLayout")
		return
	end

	for i in pairs(ItemRackUser.Buttons) do
		ItemRackUser.Buttons[i].needsDrawn = 1
	end

	-- draw undocked buttons first
	for i in pairs(ItemRackUser.Buttons) do
		if ItemRackUser.Buttons[i].needsDrawn and not ItemRackUser.Buttons[i].DockTo then
			local button = _G["ItemRackButton" .. i]
			ItemRackUser.Buttons[i].needsDrawn = nil
			applyButtonPosition(i, button)
			button:Show()
		end
	end
	local done
	-- draw docked buttons in the order they're docked
	while not done do
		done = 1
		for i in pairs(ItemRackUser.Buttons) do
			if ItemRackUser.Buttons[i].needsDrawn and not ItemRackUser.Buttons[ItemRackUser.Buttons[i].DockTo].needsDrawn then
				local button = _G["ItemRackButton" .. i]
				ItemRackUser.Buttons[i].needsDrawn = nil
				button:ClearAllPoints()
				local dockinfo = ItemRack.DockInfo[ItemRackUser.Buttons[i].Side]
				button:SetPoint(ItemRackUser.Buttons[i].Side, "ItemRackButton" .. ItemRackUser.Buttons[i].DockTo, ItemRack.OppositeSide[ItemRackUser.Buttons[i].Side], dockinfo.xoff*(ItemRackUser.ButtonSpacing or 4), dockinfo.yoff*(ItemRackUser.ButtonSpacing or 4))
				button:Show()
				done = nil
			end
		end
	end
	ItemRack.UpdateButtons()
end

-- corner badge for the button's slot, on a child frame above the button's border
function ItemRack.SetButtonBadge(button, id)
	local frame = button.IRBadgeFrame
	if not frame then
		frame = CreateFrame("Frame", nil, button)
		frame:SetSize(14, 14)
		frame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
		frame.texture = frame:CreateTexture(nil, "OVERLAY")
		frame.texture:SetAllPoints(frame)
		button.IRBadgeFrame = frame
	end
	frame:SetFrameLevel(_G[button:GetName() .. "Cooldown"]:GetFrameLevel() - 1)
	local badgeTexture = ItemRack.IconBadges[tonumber(ItemRack.GetIRString(id, true))]
	frame.texture:SetTexture(badgeTexture)
	frame.texture:SetShown(badgeTexture ~= nil)
end

function ItemRack.UpdateButtons()
	for i in pairs(ItemRackUser.Buttons) do
		if i < 20 then
			_G["ItemRackButton" .. i .. "Icon"]:SetTexture(ItemRack.GetTextureBySlot(i))
			ItemRack.SetButtonBadge(_G["ItemRackButton" .. i], ItemRack.GetID(i))
		end
		if i == 0 then -- ammo slot overlays the bag count of the equipped ammo
			local baseID = ItemRack.GetIRString(ItemRack.GetID(0), true)
			if baseID ~= 0 then
				ItemRackButton0Count:SetText(GetItemCount(baseID))
			else
				ItemRackButton0Count:SetText("")
			end
		end
	end
	ItemRack.UpdateCurrentSet()
	ItemRack.UpdateButtonCooldowns()
end

--[[ Menu ]]

function ItemRack.DockMenuToButton(button)
	if (button == 13 or button == 14) and ItemRackSettings.TrinketMenuMode == "ON" and ItemRackUser.Buttons[13] and ItemRackUser.Buttons[14] then
		button = 13 + (ItemRackSettings.AnchorOther == "ON" and 1 or 0)
	end

	local parent = ItemRack.FindParent(button)
	local menuDock = ItemRackUser.Buttons[parent].MenuDock or "BOTTOMLEFT"
	local mainDock = ItemRackUser.Buttons[parent].MainDock or "TOPLEFT"
	local menuOrient = (ItemRackSettings.MenuHorizontal == "ON") and "HORIZONTAL" or "VERTICAL"
	ItemRack.DockWindows(menuDock, _G["ItemRackButton" .. button], mainDock, menuOrient, button)
end

function ItemRack.OnEnterButton(self)
	ItemRack.InventoryTooltip(self)
	if ItemRack.IsTimerActive("ButtonsDocking") or (not IsShiftKeyDown() and ItemRackSettings.MenuOnShift == "ON") or ItemRackSettings.MenuOnRight == "ON" then
		return
	end
	local button = self:GetID()
	ItemRack.DockMenuToButton(button)
	ItemRack.BuildMenu(button)
end

--[[ Menu Docking ]]

function ItemRack.MenuFrameOnMouseDown(self, button)
	if button == "LeftButton" then
		ItemRack.MenuDockingTo = ItemRack.menuMovable
		if ItemRack.MenuDockingTo then
			for i in pairs(ItemRackUser.Buttons) do
				if i ~= ItemRack.MenuDockingTo then
					_G["ItemRackButton" .. i]:SetAlpha(ItemRackUser.Alpha/3)
				end
			end
			ItemRackMenuFrame:StartMoving()
			ItemRack.StartTimer("MenuDocking")
		end
	end
end

function ItemRack.MenuFrameOnMouseUp(self, button)
	if button == "LeftButton" and ItemRack.MenuDockingTo then
		ItemRack.StopTimer("MenuDocking")
		for i in pairs(ItemRackUser.Buttons) do
			_G["ItemRackButton" .. i]:SetAlpha(ItemRackUser.Alpha)
		end
		local parent = ItemRack.FindParent(ItemRack.MenuDockingTo)
		ItemRackUser.Buttons[parent].MenuDock = ItemRack.menuDock
		ItemRackUser.Buttons[parent].MainDock = ItemRack.mainDock
		ItemRack.DockMenuToButton(ItemRack.MenuDockingTo)
		ItemRack.BuildMenu()
		ItemRack.MenuDockingTo = nil
		ItemRackMenuFrame:StopMovingOrSizing()
		ItemRack.HideBrackets()
	end
end

function ItemRack.MenuDocking()
	local main = _G["ItemRackButton" .. ItemRack.MenuDockingTo]
	local menu = ItemRackMenuFrame
	local mainscale = main:GetEffectiveScale()
	local menuscale = menu:GetEffectiveScale()
	local near = ItemRack.Near

	if near(main:GetRight()*mainscale, menu:GetLeft()*menuscale) then
		if near(main:GetTop()*mainscale, menu:GetTop()*menuscale) then
			ItemRack.mainDock = "TOPRIGHT"
			ItemRack.menuDock = "TOPLEFT"
		elseif near(main:GetBottom()*mainscale, menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "BOTTOMRIGHT"
			ItemRack.menuDock = "BOTTOMLEFT"
		end
	elseif near(main:GetLeft()*mainscale, menu:GetRight()*menuscale) then
		if near(main:GetTop()*mainscale, menu:GetTop()*menuscale) then
			ItemRack.mainDock = "TOPLEFT"
			ItemRack.menuDock = "TOPRIGHT"
		elseif near(main:GetBottom()*mainscale, menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "BOTTOMLEFT"
			ItemRack.menuDock = "BOTTOMRIGHT"
		end
	elseif near(main:GetRight()*mainscale, menu:GetRight()*menuscale) then
		if near(main:GetTop()*mainscale, menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "TOPRIGHT"
			ItemRack.menuDock = "BOTTOMRIGHT"
		elseif near(main:GetBottom()*mainscale, menu:GetTop()*menuscale) then
			ItemRack.mainDock = "BOTTOMRIGHT"
			ItemRack.menuDock = "TOPRIGHT"
		end
	elseif near(main:GetLeft()*mainscale, menu:GetLeft()*menuscale) then
		if near(main:GetTop()*mainscale, menu:GetBottom()*menuscale) then
			ItemRack.mainDock = "TOPLEFT"
			ItemRack.menuDock = "BOTTOMLEFT"
		elseif near(main:GetBottom()*mainscale, menu:GetTop()*menuscale) then
			ItemRack.mainDock = "BOTTOMLEFT"
			ItemRack.menuDock = "TOPLEFT"
		end
	end
	ItemRack.MoveBracket("Main", ItemRack.mainDock, main, ItemRack.mainDock)
	ItemRack.MoveBracket("Menu", ItemRack.menuDock, menu, ItemRack.menuDock)
end

--[[ Using buttons ]]

function ItemRack.ButtonPostClick(self, button)
	self:SetChecked(false)
	local id = self:GetID()
	if button == "RightButton" and ItemRackSettings.MenuOnRight == "ON" then
		if ItemRackMenuFrame:IsVisible() and ItemRack.menuOpen == id then
			ItemRackMenuFrame:Hide()
		else
			ItemRack.DockMenuToButton(id)
			ItemRack.BuildMenu(id, nil, 2)
		end
	elseif IsShiftKeyDown() then
		if id < 20 then
			if ChatFrame1EditBox:IsVisible() then
				ChatFrame1EditBox:Insert(GetInventoryItemLink("player", id))
			end
		elseif ItemRackUser.CurrentSet then
			ItemRack.UnequipSet(ItemRackUser.CurrentSet)
		end
	elseif IsAltKeyDown() then
		if id < 20 and ItemRackSettings.DisableAltClick == "OFF" then
			if not ItemRack.GetQueues()[id] then
				C_AddOns.LoadAddOn("ItemRackOptions")
				ItemRackOptFrame:Show()
				ItemRackOpt.TabOnClick(self, 4)
				ItemRackOpt.SetupQueue(id)
			end
			ItemRack.GetQueuesEnabled()[id] = not ItemRack.GetQueuesEnabled()[id]
			if ItemRackOptSubFrame7 and ItemRackOptSubFrame7:IsVisible() and ItemRackOpt.SelectedSlot == id then
				ItemRackOptQueueEnable:SetChecked(ItemRack.GetQueuesEnabled()[id])
			end
			ItemRack.UpdateCombatQueue()
		elseif id == 20 then
			ItemRack.ToggleEvents()
		end
	elseif id < 20 then
		ItemRack.ReflectItemUse(id)
	elseif id == 20 then
		if button == "LeftButton" and ItemRackUser.CurrentSet then
			if ItemRackSettings.EquipToggle == "ON" then
				ItemRack.ToggleSet(ItemRackUser.CurrentSet)
			else
				ItemRack.EquipSet(ItemRackUser.CurrentSet)
			end
		else
			ItemRack.ToggleOptions(self, 2) -- tab 2 = sets
		end
	end
end

function ItemRack.ReflectClickedUpdate()
	local reflect = ItemRack.ReflectClicked
	local found
	for i in pairs(reflect) do
		reflect[i] = reflect[i] - .2
		if reflect[i] < 0 then
			_G["ItemRackButton" .. i]:SetChecked(false)
			reflect[i] = nil
		end
		found = 1
	end
	if not found then
		ItemRack.StopTimer("ReflectClickedUpdate")
	end
end

function ItemRack.UpdateButtonCooldowns()
	local writeNumbers = ItemRackSettings.CooldownCount == "ON"
	for i in pairs(ItemRackUser.Buttons) do
		if i < 20 then
			local start, duration, enable = GetInventoryItemCooldown("player", i)
			CooldownFrame_Set(_G["ItemRackButton" .. i .. "Cooldown"], start, duration, enable)
			if writeNumbers then
				ItemRack.WriteCooldown(_G["ItemRackButton" .. i .. "Time"], start, duration, enable)
			end
		end
	end
end

function ItemRack.WriteButtonCooldowns()
	if ItemRackSettings.CooldownCount ~= "ON" then return end
	for i in pairs(ItemRackUser.Buttons) do
		ItemRack.WriteCooldown(_G["ItemRackButton" .. i .. "Time"], GetInventoryItemCooldown("player", i))
	end
end

function ItemRack.UpdateButtonLocks()
	for i in pairs(ItemRackUser.Buttons) do
		if i < 20 then
			local isLocked = IsInventoryItemLocked(i)
			local alreadyLocked = ItemRack.LockedButtons[i]
			if isLocked and not alreadyLocked then
				_G["ItemRackButton" .. i .. "Icon"]:SetDesaturated(true)
				ItemRack.LockedButtons[i] = 1
			elseif not isLocked and alreadyLocked then
				_G["ItemRackButton" .. i .. "Icon"]:SetDesaturated(false)
				ItemRack.LockedButtons[i] = nil
			end
		end
	end
end

--[[ Button menu ]]

function ItemRack.ButtonMenuOnClick(self)
	if self == ItemRackButtonMenuClose then
		ItemRack.RemoveButton(ItemRack.menuOpen)
	elseif self == ItemRackButtonMenuOptions then
		ItemRack.ToggleOptions(self)
	elseif self == ItemRackButtonMenuLock then
		ItemRackUser.Locked = ItemRackUser.Locked == "ON" and "OFF" or "ON"
		ItemRack.ReflectLock()
	elseif self == ItemRackButtonMenuQueue then
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOptFrame:Hide()
		else
			C_AddOns.LoadAddOn("ItemRackOptions")
			ItemRackOptFrame:Show()
			if ItemRack.menuOpen < 20 then
				ItemRackOpt.TabOnClick(self, 4)
				ItemRackOpt.SetupQueue(ItemRack.menuOpen)
			else
				ItemRackOpt.TabOnClick(self, 3)
			end
		end
	end
end

function ItemRack.ReflectMainScale(changing)
	if InCombatLockdown() then
		table.insert(ItemRack.RunAfterCombat, "ReflectMainScale")
		return
	end
	local scale = ItemRackUser.MainScale or 1
	for i = 0, 20 do
		local cfg = ItemRackUser.Buttons[i]
		if not changing or not cfg or not (cfg.Corner or cfg.Anchor or cfg.Left) then
			_G["ItemRackButton" .. i]:SetScale(scale)
		else
			local frame = _G["ItemRackButton" .. i]
			local oldscale = frame:GetScale() or 1
			local framex = frame:GetLeft()*oldscale
			local framey = frame:GetTop()*oldscale
			frame:SetScale(scale)
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", framex/scale, framey/scale)
			saveButtonPosition(i, frame)
		end
	end
end

function ItemRack.ReflectMenuOnRight()
	for i = 0, 20 do
		_G["ItemRackButton" .. i]:SetAttribute("slot2", ItemRackSettings.MenuOnRight == "ON" and ATTRIBUTE_NOOP or nil)
	end
end

function ItemRack.ReflectHideOOC()
	for i in pairs(ItemRackUser.Buttons) do
		if ItemRackSettings.HideOOC == "ON" and not ItemRack.inCombat then
			_G["ItemRackButton" .. i]:Hide()
		else
			_G["ItemRackButton" .. i]:Show()
		end
	end
end

--[[ Cooldowns ]]

function ItemRack.WriteCooldown(where, start, duration)
	-- the cooldown APIs return nil for a few frames after a loading screen; treat as no cooldown
	if not start or not duration or start == 0 or ItemRackSettings.CooldownCount == "OFF" then
		where:SetText("")
		return
	end
	local cooldown = duration - (GetTime()-start)
	-- under 3s with no text already showing is a global cooldown; don't display it
	if cooldown >= 3 or where:GetText() then
		where:SetText((cooldown < (ItemRackSettings.Cooldown90 == "ON" and 90 or 60) and math.floor(cooldown+.5) .. " s") or (cooldown < 3600 and math.ceil(cooldown/60) .. " m") or math.ceil(cooldown/3600) .. " h")
	end
end

--[[ Key binding display ]]

function ItemRack.KeyBindingsChanged()
	for i in pairs(ItemRackUser.Buttons) do
		if ItemRackSettings.ShowHotKeys == "ON" then
			local key = GetBindingKey("CLICK ItemRackButton" .. i .. ":LeftButton")
			_G["ItemRackButton" .. i .. "HotKey"]:SetText(GetBindingText(key or "", nil, 1))
		else
			_G["ItemRackButton" .. i .. "HotKey"]:SetText("")
		end
	end
end

function ItemRack.ResetButtons()
	for i in pairs(ItemRackUser.Buttons) do
		ItemRack.RemoveButton(i)
	end
	ItemRackUser.Alpha = 1
	ItemRackUser.Locked = "OFF"
	ItemRackUser.MainScale = 1
	ItemRackUser.MenuScale = .85
	if ItemRackOpt then
		ItemRackOpt.UpdateSlider("Alpha")
		ItemRackOpt.UpdateSlider("MenuScale")
		ItemRackOpt.UpdateSlider("MainScale")
	end
end
