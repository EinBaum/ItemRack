local addonName, addon = ...
_G[addonName] = addon

ItemRack.Version = C_AddOns.GetAddOnMetadata(addonName, "Version")

-- [[ Season of Discovery Runes ]]
function ItemRack.IsEngravingActive()
	return C_Engraving and C_Engraving.IsEngravingEnabled()
end

if ItemRack.IsEngravingActive() then
	function ItemRack.AppendRuneID(bag, slot)
		local engravable, rune
		if slot then
			engravable = C_Engraving.IsInventorySlotEngravable(bag, slot)
			rune = engravable and C_Engraving.GetRuneForInventorySlot(bag, slot)
		else
			engravable = C_Engraving.IsEquipmentSlotEngravable(bag)
			rune = engravable and C_Engraving.GetRuneForEquipmentSlot(bag)
		end
		if not engravable then
			return ""
		end
		return ":runeid:" .. (rune and tostring(rune.skillLineAbilityID) or "0")
	end
end

local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

ItemRackUser = {
	Sets = {},
	ItemsUsed = {}, -- used-item ids, drives cooldown notify
	Hidden = {}, -- ids hidden from menus
	Queues = {}, -- [slot] = ordered id list
	QueuesEnabled = {},
	Locked = "OFF", -- buttons locked
	EnableEvents = "ON",
	EnableQueues = "ON",
	EnablePerSetQueues = "OFF",
	ButtonSpacing = 4, -- padding between docked buttons
	Alpha = 1,
	MainScale = 1, -- scale of the dockable buttons
	MenuScale = .85, -- relative to docked buttons
	SetMenuWrap = "OFF", -- user-defined menu wrap point
	SetMenuWrapValue = 3, -- columns before wrapping
}

ItemRackSettings = {
	MenuOnShift = "OFF", -- open menus on shift only
	MenuOnRight = "OFF", -- open menus on right-click only
	HideOOC = "OFF", -- hide dockable buttons out of combat
	Notify = "ON", -- notify when a used item comes off cooldown
	NotifyThirty = "OFF", -- notify when a used item reaches 30 seconds cooldown
	NotifyChatAlso = "OFF",
	ShowTooltips = "ON",
	TinyTooltips = "OFF", -- condense tooltips to most important info
	TooltipFollow = "OFF", -- tooltip follows pointer
	CooldownCount = "OFF", -- cooldowns displayed numerically over buttons
	LargeNumbers = "OFF", -- large font for cooldown numbers
	AllowEmpty = "ON", -- allow empty slot as a choice in menus
	HideTradables = "OFF", -- hide non-soulbound gear in menus
	AllowHidden = "ON", -- allow hiding items/sets in the menu with alt+click
	ShowMinimap = "ON",
	TrinketMenuMode = "OFF", -- merge top/bottom trinkets to one menu (leftclick=top, rightclick=bottom)
	AnchorOther = "OFF", -- dock the merged trinket menu to bottom trinket
	EquipToggle = "OFF", -- toggle equipping a set when choosing to equip it
	ShowHotKeys = "OFF", -- show key bindings on dockable buttons
	Cooldown90 = "OFF", -- count cooldown in seconds at 90 instead of 60
	EquipOnSetPick = "OFF", -- equip a set when picked in the set tab of options
	MinimapTooltip = "ON", -- click-help tooltip on the minimap button
	CharacterSheetMenus = "ON", -- slot menus on mouseover of the character sheet
	DisableAltClick = "OFF", -- disable Alt+click auto queue toggle (to allow self cast through)
	MenuHorizontal = "OFF",
	AlwaysShowOnyxiaCloak = "OFF", -- force Show Cloak on while Onyxia Scale Cloak is in the back slot
	KeepWornIfQueued = "ON", -- in EquipSet, leave a slot alone if its auto queue is enabled and lists the currently-worn item
}

-- default items with non-standard behavior
--   keep = suspend auto queue while equipped
--   priority = equip as it comes off cooldown even if the equipped item is ready and waiting
--   delay = seconds after use before swapping out
ItemRackItems = {
	["11122"] = { keep = 1 }, -- carrot on a stick
	["13209"] = { keep = 1 }, -- seal of the dawn
	["19812"] = { keep = 1 }, -- rune of the dawn
	["12846"] = { keep = 1 }, -- argent dawn commission
}
-- bump to redeploy default entries to existing users (their own edits stay put until the next bump)
ItemRack.ItemsVersion = 1
local defaultItems = ItemRackItems

ItemRack.Menu = {}
ItemRack.LockList = {} -- [-2..10][slot] = already tagged for a swap
ItemRack.BankSlots = { -1, 5, 6, 7, 8, 9, 10 }
ItemRack.KnownItems = {} -- [IR id] = location; worn = -(slot+1), bag = bag*100+slot

ItemRack.SlotInfo = {
	[0] = { name = "AmmoSlot", real = "Ammo", INVTYPE_AMMO = 1 },
	[1] = { name = "HeadSlot", real = "Head", INVTYPE_HEAD = 1 },
	[2] = { name = "NeckSlot", real = "Neck", INVTYPE_NECK = 1 },
	[3] = { name = "ShoulderSlot", real = "Shoulder", INVTYPE_SHOULDER = 1 },
	[4] = { name = "ShirtSlot", real = "Shirt", INVTYPE_BODY = 1 },
	[5] = { name = "ChestSlot", real = "Chest", INVTYPE_CHEST = 1, INVTYPE_ROBE = 1 },
	[6] = { name = "WaistSlot", real = "Waist", INVTYPE_WAIST = 1 },
	[7] = { name = "LegsSlot", real = "Legs", INVTYPE_LEGS = 1 },
	[8] = { name = "FeetSlot", real = "Feet", INVTYPE_FEET = 1 },
	[9] = { name = "WristSlot", real = "Wrist", INVTYPE_WRIST = 1 },
	[10] = { name = "HandsSlot", real = "Hands", INVTYPE_HAND = 1 },
	[11] = { name = "Finger0Slot", real = "Top Finger", INVTYPE_FINGER = 1, other = 12 },
	[12] = { name = "Finger1Slot", real = "Bottom Finger", INVTYPE_FINGER = 1, other = 11 },
	[13] = { name = "Trinket0Slot", real = "Top Trinket", INVTYPE_TRINKET = 1, other = 14 },
	[14] = { name = "Trinket1Slot", real = "Bottom Trinket", INVTYPE_TRINKET = 1, other = 13 },
	[15] = { name = "BackSlot", real = "Cloak", INVTYPE_CLOAK = 1 },
	[16] = { name = "MainHandSlot", real = "Main hand", INVTYPE_WEAPONMAINHAND = 1, INVTYPE_2HWEAPON = 1, INVTYPE_WEAPON = 1, other = 17 },
	[17] = { name = "SecondaryHandSlot", real = "Off hand", INVTYPE_WEAPON = 1, INVTYPE_WEAPONOFFHAND = 1, INVTYPE_SHIELD = 1, INVTYPE_HOLDABLE = 1, other = 16 },
	[18] = { name = "RangedSlot", real = "Ranged", INVTYPE_RANGED = 1, INVTYPE_RANGEDRIGHT = 1, INVTYPE_THROWN = 1, INVTYPE_RELIC = 1 },
	[19] = { name = "TabardSlot", real = "Tabard", INVTYPE_TABARD = 1 },
}

-- corner badges for items sharing the same inventory icon, by base item id
ItemRack.IconBadges = {
	[10588] = "Interface\\Icons\\Ability_Rogue_Sprint", -- Goblin Rocket Helmet (intercept)
	[10506] = "Interface\\Icons\\Spell_Shadow_DemonBreath", -- Deepdive Helmet (water breathing)
	[10726] = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate", -- Gnomish Mind Control Cap
	[15138] = "Interface\\Icons\\INV_Misc_Head_Dragon_Black", -- Onyxia Scale Cloak
	[10518] = "Interface\\Icons\\Spell_Magic_FeatherFall", -- Parachute Cloak (slow fall)
}

ItemRack.DockInfo = {
	LEFT = { xoff = 1, yoff = 0 },
	RIGHT = { xoff = -1, yoff = 0 },
	TOP = { xoff = 0, yoff = -1 },
	BOTTOM = { xoff = 0, yoff = 1 },
	TOPRIGHTTOPLEFT = { xoff = 0, yoff = 8, xdir = 1, ydir = -1, xstart = 8, ystart = -8 },
	BOTTOMRIGHTBOTTOMLEFT = { xoff = 0, yoff = -8, xdir = 1, ydir = 1, xstart = 8, ystart = 44 },
	TOPLEFTTOPRIGHT = { xoff = 0, yoff = 8, xdir = -1, ydir = -1, xstart = -44, ystart = -8 },
	BOTTOMLEFTBOTTOMRIGHT = { xoff = 0, yoff = -8, xdir = -1, ydir = 1, xstart = -44, ystart = 44 },
	TOPRIGHTBOTTOMRIGHT = { xoff = 8, yoff = 0, xdir = -1, ydir = 1, xstart = -44, ystart = 44 },
	BOTTOMRIGHTTOPRIGHT = { xoff = 8, yoff = 0, xdir = -1, ydir = -1, xstart = -44, ystart = -8 },
	TOPLEFTBOTTOMLEFT = { xoff = -8, yoff = 0, xdir = 1, ydir = 1, xstart = 8, ystart = 44 },
	BOTTOMLEFTTOPLEFT = { xoff = -8, yoff = 0, xdir = 1, ydir = -1, xstart = 8, ystart = -8 },
}
ItemRack.OppositeSide = { LEFT = "RIGHT", RIGHT = "LEFT", TOP = "BOTTOM", BOTTOM = "TOP" }

-- frames that keep the menu open on mouseover; AddMouseoverFrame hooks their OnLeave
ItemRack.MenuMouseoverFrames = {}

ItemRack.CombatQueue = {} -- [slot] = id waiting to swap at combat end
-- [slot] = id ProcessAutoQueue queued itself; entries from any other path must survive until combat ends
ItemRack.AutoQueueOrigin = {}
ItemRack.RunAfterCombat = {} -- ItemRack function names to run when combat drops

-- miscellaneous tooltips ElementName, Line1, Line2
ItemRack.TooltipInfo = {
	{ "ItemRackButtonMenuLock", "Lock Buttons", "Toggle locked state to prevent buttons/menus from moving and to hide borders and control buttons.\n\nHold ALT while you open a menu to access these control buttons while locked." },
	{ "ItemRackButtonMenuQueue", "Auto Queue", "Set up the auto queue for this slot.\n\nAlt+click the slot this menu opened from to toggle its auto queue on/off." },
	{ "ItemRackButtonMenuOptions", "Options", "Open Options window to change settings, configure sets or auto queues." },
	{ "ItemRackButtonMenuClose", "Remove", "Remove the slot this menu opened from." },
	{ "ItemRackOptSetsHideCheckButton", "Hide Set", "Check this to make the set hidden in menus." },
	{ "ItemRackOptItemStatsPriority", "Priority", "Check this to make this item auto equip when it comes off cooldown even if the equipped item is off cooldown and waiting to be used." },
	{ "ItemRackOptItemStatsKeepEquipped", "Pause Queue", "Check this to suspend the auto queue for this slot until the item is unequipped. (For instance if you have another mod handling the auto equip of a riding crop." },
	{ "ItemRackOptQueueEnable", "Auto Queue This Slot", "Check this to allow this slot to auto queue.  When an item goes on cooldown, it will swap for an item higher on the list that's off cooldown." },
	{ "ItemRackOptSetsHideCheckButton", "Hide", "Hide this set in menus. (Equivalent of Alt+clicking the set in the menu)" },
	{ "ItemRackOptSetsSaveButton", "Save Set", "Save this set. Some settings like key binding, cloak/helm visibility and whether it's hidden can only be changed to a saved set." },
	{ "ItemRackOptSetsDeleteButton", "Delete Set", "Delete this set definition. If you want to remove it from the menu and may want it again in the future, check 'Hide' to the left." },
	{ "ItemRackOptSetsBindButton", "Bind Key to Set", "This will let you bind a key or key combination to equip a set." },
	{ "ItemRackOptEventNew", "New Event", "Create a new event." },
	{ "ItemRackOptEventEdit", "Edit Event", "Edit this event. Note: if you edit the name and save, it will create a copy of the event with the new name." },
	{ "ItemRackOptEventDelete", "Delete Event", "If this event is enabled or has a set associated with it, it will remove the tags and drop it in the list.  If this is an untagged event, it will delete it entirely." },
	{ "ItemRackOptEventEditSave", "Save Event", "Saves changes to this event.  Note: if you edit the name and save, it will create a copy of the event with the new name." },
	{ "ItemRackOptEventEditCancel", "Cancel Changes", "Cancel any changes just made to this event and return to event list." },
	{ "ItemRackOptEventEditBuffAnyMount", "Any mount", "Checking this will check if any mount is active instead of a specific buff." },
	{ "ItemRackOptEventEditExpand", "Edit in Editor", "This will detach the script edit box above to a resizable text editor." },
	{ "ItemRackFloatingEditorUndo", "Undo", "Revert the text to its last saved state." },
	{ "ItemRackFloatingEditorTest", "Test", "Run the text below as a script to make sure there are no syntax errors. (Script Errors in Interface Options should be enabled to see any)\nNote: This test cannot simulate any condition or test for expected behavior other than the ability to run." },
	{ "ItemRackFloatingEditorSave", "Save Event", "Save changes to this event and return to the event list." },
	{ "ItemRackOptToggleInvAll", "Toggle All", "This will toggle between selecting all slots and selecting no slots." }
}

ItemRack.BankOpen = nil

ItemRack.EventHandlers = {}
ItemRack.ExternalEventHandlers = {}

function ItemRack.InitEventHandlers()
	local handler = ItemRack.EventHandlers
	handler.ITEM_LOCK_CHANGED = ItemRack.OnItemLockChanged
	handler.ACTIONBAR_UPDATE_COOLDOWN = ItemRack.UpdateButtonCooldowns
	handler.UNIT_INVENTORY_CHANGED = ItemRack.OnUnitInventoryChanged
	handler.UPDATE_BINDINGS = ItemRack.KeyBindingsChanged
	handler.PLAYER_REGEN_ENABLED = ItemRack.OnLeavingCombatOrDeath
	handler.PLAYER_UNGHOST = ItemRack.OnLeavingCombatOrDeath
	handler.PLAYER_ALIVE = ItemRack.OnLeavingCombatOrDeath
	handler.PLAYER_REGEN_DISABLED = ItemRack.OnEnteringCombat
	handler.BANKFRAME_CLOSED = ItemRack.OnBankClose
	handler.BANKFRAME_OPENED = ItemRack.OnBankOpen
	handler.BAG_UPDATE = ItemRack.OnBagUpdate
	handler.UNIT_SPELLCAST_START = ItemRack.OnCastingStart
	handler.UNIT_SPELLCAST_STOP = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_SUCCEEDED = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_INTERRUPTED = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_FAILED = ItemRack.OnCastingStop
	handler.UNIT_SPELLCAST_CHANNEL_START = ItemRack.OnCastingStart
	handler.UNIT_SPELLCAST_CHANNEL_STOP = ItemRack.OnCastingStop
	handler.CHARACTER_POINTS_CHANGED = ItemRack.UpdateClassSpecificStuff
	handler.PLAYER_ENTERING_WORLD = ItemRack.OnEnterWorld
	handler.PLAYER_LOGOUT = ItemRack.OnPlayerLogout
	handler.COMBAT_LOG_EVENT_UNFILTERED = ItemRack.OnCombatLogEvent
	handler.PLAYER_EQUIPMENT_CHANGED = ItemRack.OnEquipmentChangedForCloak
	handler.CURRENT_SPELL_CAST_CHANGED = ItemRack.OnCurrentSpellChanged
end

do
	local Masque = LibStub("Masque", true) or (LibMasque and LibMasque("Button"))
	if Masque then
		ItemRack.MasqueGroups = {}
		ItemRack.MasqueGroups[1] = Masque:Group("ItemRack", "On screen panels")
		ItemRack.MasqueGroups[2] = Masque:Group("ItemRack", "On screen menus")
		ItemRack.MasqueGroups[3] = Masque:Group("ItemRack", "Character info menus")
		ItemRack.MasqueGroups[4] = Masque:Group("ItemRack", "Map icon menu")
	end
end

function ItemRack.OnEvent(self, event, ...)
	ItemRack.EventHandlers[event](self, event, ...)
end

--- Allows third-party addons to listen to ItemRack events, like saving and deleting a set.
function ItemRack.RegisterExternalEventListener(self, event, handler)
	local handlers = ItemRack.ExternalEventHandlers[event]
	if handlers == nil then
		handlers = {}
		ItemRack.ExternalEventHandlers[event] = handlers
	end

	table.insert(handlers, handler)
end

function ItemRack.FireItemRackEvent(self, event, ...)
	local handlers = ItemRack.ExternalEventHandlers[event]
	if handlers ~= nil then
		for _, handler in pairs(handlers) do
			handler(event, ...)
		end
	end
end

function ItemRack.OnPlayerLogin()
	-- PLAYER_LOGIN grants a grace period where secure code may run even in combat
	ItemRack.InitBroker()
	ItemRack.InitEventHandlers()
	ItemRack.InitTimers()
	ItemRack.InitCore()
	ItemRack.InitButtons()
	ItemRack.InitEvents()
end

function ItemRack.OnPlayerLogout()
	ItemRack.SetSetBindings()
end

function ItemRack.OnEnterWorld(self, event, ...)
	ItemRack.PlayerGUID = UnitGUID("player") -- cache for combat-log source-GUID compares
	local isLogin, isReload = ...
	if isLogin or isReload then
		ItemRack.BindingsPending = 1
		C_Timer.After(1, function()
			ItemRack.SetSetBindings()
		end)
	end
end

-- no UNIT_SPELLCAST event fires for Aimed Shot / Multi-Shot / wand Shoot, so track them via combat log
function ItemRack.OnCombatLogEvent()
	local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
	if sourceGUID ~= ItemRack.PlayerGUID then return end
	if subEvent == "SPELL_CAST_START" then
		ItemRack.NowShooting = spellID
		ItemRack.NowShootingStart = GetTime()
	elseif ItemRack.NowShooting == spellID and (subEvent == "SPELL_CAST_SUCCESS" or subEvent == "SPELL_CAST_FAILED") then
		ItemRack.NowShooting = nil
		ItemRack.NowShootingStart = nil
		if not ItemRack.inCombat then
			ItemRack.ProcessCombatQueue()
			if #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() then
				ItemRack.ProcessSetsWaiting()
			end
		end
	end
end

-- the game refuses swaps while an on-next-swing ability is queued; CURRENT_SPELL_CAST_CHANGED tracks that state
ItemRack.SwingQueueSpells = { "Heroic Strike", "Cleave", "Maul", "Raptor Strike" }

function ItemRack.OnCurrentSpellChanged()
	local queued
	for i = 1, #ItemRack.SwingQueueSpells do
		local id = select(7, GetSpellInfo(ItemRack.SwingQueueSpells[i]))
		if id and IsCurrentSpell(id) then
			queued = 1
			break
		end
	end
	if queued then
		ItemRack.NowSwingQueued = 1
	elseif ItemRack.NowSwingQueued then
		ItemRack.NowSwingQueued = nil
		if #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() then
			ItemRack.ProcessSetsWaiting()
		end
	end
end

-- Temp frame for PLAYER_LOGIN: ItemRackFrame doesn't exist yet at file load.
local loader = CreateFrame("Frame")

loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", ItemRack.OnPlayerLogin)

function ItemRack.OnCastingStart(self, event, unit)
	if unit == "player" and (CastingInfo() or ChannelInfo()) then
		ItemRack.NowCasting = true
	end
end

function ItemRack.OnCastingStop(self, event, unit, castGUID, spellID)
	if unit ~= "player" then return end

	-- spellID-matched so a concurrent auto-shot or other spell completion can't clear the flag
	if ItemRack.NowShooting and spellID == ItemRack.NowShooting then
		ItemRack.NowShooting = nil
		ItemRack.NowShootingStart = nil
		if event == "UNIT_SPELLCAST_SUCCEEDED" or ItemRack.inCombat then
			ItemRack.OnSpellSucceed() -- 0.1s delayed combat-queue drain
		else
			ItemRack.ProcessCombatQueue()
		end
		if #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() then
			ItemRack.ProcessSetsWaiting() -- drain sets queued via keybind during the cast
		end
	end

	-- ignore stop/success events fired during an active channel (e.g. Eagle Eye)
	if CastingInfo() or ChannelInfo() then return end
	if not ItemRack.NowCasting then return end
	ItemRack.NowCasting = nil
	-- a successful cast can itself put the player in combat
	if event ~= "UNIT_SPELLCAST_SUCCEEDED" and not ItemRack.inCombat then
		ItemRack.ProcessCombatQueue()
	else
		ItemRack.OnSpellSucceed()
	end
	if #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() then
		ItemRack.ProcessSetsWaiting() -- drain sets queued via keybind during the cast
	end
end

function ItemRack.OnItemLockChanged()
	ItemRack.StartTimer("LocksChanged")
end

function ItemRack.OnSpellSucceed()
	ItemRack.StartTimer("DelayedCombatQueue")
end

function ItemRack.DelayedCombatQueue()
	if ItemRack.inCombat or ItemRack.NowCasting or ItemRack.NowShooting then
		return
	end
	ItemRack.ProcessCombatQueue()
end

function ItemRack.OnUnitInventoryChanged(self, event, unit)
	if unit == "player" then
		ItemRack.UpdateButtons() -- sync: docked button icons update immediately
		ItemRack.StartTimer("InvUpdate") -- debounced: KnownItems, menu, Options grid
	end
end

function ItemRack.OnLeavingCombatOrDeath()
	ItemRack.inCombat = InCombatLockdown()
	-- combat ended; clear a shot flag whose resolution never arrived
	ItemRack.NowShooting = nil
	ItemRack.NowShootingStart = nil
	if ItemRack.NowCasting then
		return
	end
	-- a slot still showing its pre-swap item is a swap the game rejected at the combat boundary; retry it
	for slot, p in pairs(ItemRack.PendingSwap) do
		local cur = ItemRack.GetID(slot)
		if not ItemRack.SameID(cur, p.want) and ItemRack.SameID(cur, p.old) then
			ItemRack.CombatQueue[slot] = p.want
			ItemRack.AutoQueueOrigin[slot] = nil
			ItemRack.CombatSet = ItemRack.CombatSet or ItemRackUser.CurrentSet
		end
	end
	wipe(ItemRack.PendingSwap)

	ItemRack.ProcessCombatQueue()
end

function ItemRack.ProcessCombatQueue()
	if not ItemRack.IsPlayerReallyDead() and next(ItemRack.CombatQueue) then
		local combat = ItemRackUser.Sets["~CombatQueue"].equip
		local queue = ItemRack.CombatQueue
		wipe(combat)
		for i in pairs(queue) do
			combat[i] = queue[i]
		end
		wipe(queue)
		wipe(ItemRack.AutoQueueOrigin)
		ItemRackUser.Sets["~CombatQueue"].oldset = ItemRack.CombatSet
		-- consume: a later drain of plain item swaps must not re-assert a stale set as current
		ItemRack.CombatSet = nil
		ItemRack.UpdateCombatQueue()
		ItemRack.EquipSet("~CombatQueue")
	end

	if not InCombatLockdown() then
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOpt.ListScrollFrameUpdate()
			ItemRackOptSetsBindButton:Enable()
		end
		if ItemRack.ReflectHideOOC then
			ItemRack.ReflectHideOOC()
		end
		for i = 1, #ItemRack.RunAfterCombat do
			ItemRack[ItemRack.RunAfterCombat[i]]()
		end
		wipe(ItemRack.RunAfterCombat)
		if ItemRack.BindingsPending then
			ItemRack.SetSetBindings()
		end
	end
end

function ItemRack.OnEnteringCombat()
	ItemRack.inCombat = 1
	if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
		ItemRackOpt.ListScrollFrameUpdate()
		ItemRackOptSetsBindButton:Disable()
	end
	if ItemRack.ReflectHideOOC then
		ItemRack.ReflectHideOOC()
	end
end

function ItemRack.OnBankClose()
	ItemRack.BankOpen = nil
	ItemRackMenuFrame:Hide()
end

function ItemRack.OnBankOpen()
	ItemRack.BankOpen = 1
end

function ItemRack.OnBagUpdate()
	ItemRack.StartTimer("InvUpdate")
end

function ItemRack.InvUpdate()
	ItemRack.PopulateKnownItems()
	if ItemRackMenuFrame:IsVisible() then
		ItemRack.BuildMenu()
	end
	if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
		for i = 0, 19 do
			if not ItemRackOpt.Inv[i].selected then
				ItemRackOpt.Inv[i].id = ItemRack.GetID(i)
			end
		end
		ItemRackOpt.UpdateInv()
	end
end

function ItemRack.UpdateClassSpecificStuff()
	local _, class = UnitClass("player")

	if class == "WARRIOR" or class == "ROGUE" or class == "HUNTER" then
		ItemRack.CanWearOneHandOffHand = 1
	end
end

function ItemRack.OnSetBagItem(tooltip, bag, slot)
	ItemRack.ListSetsHavingItem(tooltip, ItemRack.GetID(bag, slot), true)
end

function ItemRack.OnSetInventoryItem(tooltip, unit, inv_slot)
	ItemRack.ListSetsHavingItem(tooltip, ItemRack.GetID(inv_slot), true)
end

function ItemRack.OnSetHyperlink(tooltip, link)
	ItemRack.ListSetsHavingItem(tooltip, link:match("item:(.+)"))
end

do
	local data = {}

	function ItemRack.ListSetsHavingItem(tooltip, id, exact)
		if ItemRackSettings.ShowSetInTooltip ~= "ON" then
			return
		end
		if not id or id == 0 then return end
		local same_ids = ItemRack.SameID
		for name, set in pairs(ItemRackUser.Sets) do
			for _, item in pairs(set.equip) do
				if exact then
					item = ItemRack.UpdateIRString(item)
					if item == id then
						data[name] = true
					end
				else
					if same_ids(item, id) then
						data[name] = true
					end
				end
			end
		end
		for name in pairs(data) do
			tooltip:AddDoubleLine("ItemRack Set: ", name, 0, .6, 1, 0, .6, 1)
			data[name] = nil
		end
		tooltip:Show()
	end
end

function ItemRack.InitCore()
	ItemRackUser.Sets["~Unequip"] = { equip = {} }
	ItemRackUser.Sets["~CombatQueue"] = { equip = {} }

	-- Nothing empties every slot that loses durability on death; Options blocks Save/Delete for it
	ItemRackUser.Sets["Naked"] = nil -- legacy SavedVariables name for this set
	local nothing = ItemRackUser.Sets["Nothing"] or {}
	nothing.equip = {}
	for _, slot in ipairs({1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17, 18}) do
		nothing.equip[slot] = 0
	end
	nothing.icon = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Tabard"
	ItemRackUser.Sets["Nothing"] = nothing

	ItemRack.UpdateClassSpecificStuff()

	ItemRack.DURABILITY_PATTERN = string.match(DURABILITY_TEMPLATE, "(.+) .+/.+") or ""
	ItemRack.REQUIRES_PATTERN = string.gsub(ITEM_MIN_SKILL, "%%.", ".+")

	-- pattern splitter by Maldivia http://forums.worldofwarcraft.com/thread.html?topicId=6441208576
	local function split(str, t)
		local start, stop, single, plural = str:find("\1244(.-):(.-);")
		if start then
			split(str:sub(1, start - 1) .. single .. str:sub(stop + 1), t)
			split(str:sub(1, start - 1) .. plural .. str:sub(stop + 1), t)
		else
			tinsert(t, (str:gsub("%%d", "%%d+")))
		end
		return t
	end
	ItemRack.CHARGES_PATTERNS = {}
	split(ITEM_SPELL_CHARGES, ItemRack.CHARGES_PATTERNS)
	tinsert(ItemRack.CHARGES_PATTERNS, ITEM_SPELL_CHARGES_NONE)
	-- for enUS, ItemRack.CHARGES_PATTERNS now {"%d+ Charge","%d+ Charges","No Charges"}

	ItemRack.CreateTimer("TooltipUpdate", ItemRack.TooltipUpdate, 1, 1)
	ItemRack.CreateTimer("CooldownUpdate", ItemRack.CooldownUpdate, .5, 1)
	ItemRack.CreateTimer("LocksChanged", ItemRack.LocksChanged, .2)
	ItemRack.CreateTimer("DelayedCombatQueue", ItemRack.DelayedCombatQueue, .1)
	ItemRack.CreateTimer("InvUpdate", ItemRack.InvUpdate, .15)

	-- Indices used: -2 (worn), -1 (main bank), 0-4 (regular bags), 5-10 (bank bags).
	for i = -2, 10 do
		ItemRack.LockList[i] = {}
	end

	hooksecurefunc("UseInventoryItem", ItemRack.newUseInventoryItem)
	hooksecurefunc("UseAction", ItemRack.newUseAction)
	hooksecurefunc("UseItemByName", ItemRack.newUseItemByName)
	hooksecurefunc("PaperDollFrame_OnShow", ItemRack.newPaperDollFrame_OnShow)
	hooksecurefunc(GameTooltip, "SetBagItem", ItemRack.OnSetBagItem)
	hooksecurefunc(GameTooltip, "SetInventoryItem", ItemRack.OnSetInventoryItem)
	hooksecurefunc(GameTooltip, "SetHyperlink", ItemRack.OnSetHyperlink)

	ItemRackFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
	ItemRackFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
	ItemRackFrame:RegisterEvent("PLAYER_UNGHOST")
	ItemRackFrame:RegisterEvent("PLAYER_ALIVE")
	ItemRackFrame:RegisterEvent("BANKFRAME_CLOSED")
	ItemRackFrame:RegisterEvent("BANKFRAME_OPENED")
	ItemRackFrame:RegisterEvent("BAG_UPDATE")
	ItemRackFrame:RegisterEvent("CHARACTER_POINTS_CHANGED")
	ItemRackFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_START")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_STOP")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_FAILED")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
	ItemRackFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
	ItemRackFrame:RegisterEvent("CURRENT_SPELL_CAST_CHANGED")
	ItemRackFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	ItemRack.StartTimer("CooldownUpdate")
	ItemRack.ReflectAlpha()

	ItemRackMenuFrame:HookScript("OnLeave", ItemRack.MenuMouseover)

	SlashCmdList["ItemRack"] = ItemRack.SlashHandler
	SLASH_ItemRack1 = "/itemrack"

	EquipSet = ItemRack.EquipSet -- for convenience in macros/events, shorter names
	ToggleSet = ItemRack.ToggleSet
	UnequipSet = ItemRack.UnequipSet
	IsSetEquipped = ItemRack.IsSetEquipped

	-- defaults for options missing from a user's existing SavedVariables
	ItemRackSettings.Cooldown90 = ItemRackSettings.Cooldown90 or "OFF"
	ItemRackSettings.EquipOnSetPick = ItemRackSettings.EquipOnSetPick or "OFF"
	ItemRackUser.SetMenuWrap = ItemRackUser.SetMenuWrap or "OFF"
	ItemRackUser.SetMenuWrapValue = ItemRackUser.SetMenuWrapValue or 3
	ItemRackSettings.MinimapTooltip = ItemRackSettings.MinimapTooltip or "ON"
	ItemRackSettings.CharacterSheetMenus = ItemRackSettings.CharacterSheetMenus or "ON"
	ItemRackSettings.DisableAltClick = ItemRackSettings.DisableAltClick or "OFF"
	ItemRackSettings.AlwaysShowOnyxiaCloak = ItemRackSettings.AlwaysShowOnyxiaCloak or "OFF"
	ItemRackSettings.KeepWornIfQueued = ItemRackSettings.KeepWornIfQueued or "ON"

	-- a saved ItemRackItems replaces the defaults wholesale, so absent default entries redeploy once per version bump
	if ItemRack.ItemsVersion > (tonumber(ItemRackSettings.ItemsVersion) or 0) then
		ItemRackSettings.ItemsVersion = ItemRack.ItemsVersion
		for id, cfg in pairs(defaultItems) do
			if ItemRackItems[id] == nil then
				ItemRackItems[id] = cfg
			end
		end
	end

	ItemRack.ReflectAlwaysShowOnyxiaCloak()
end

function ItemRack.Print(msg)
	if msg then
		DEFAULT_CHAT_FRAME:AddMessage("|cFFCCCCCCItemRack: |cFFFFFFFF" .. msg)
	end
end

function ItemRack.UpdateCurrentSet()
	local texture = "Interface\\AddOns\\ItemRack\\ItemRackIcon"
	local setname = ItemRackUser.CurrentSet or _G.CUSTOM
	if setname and setname ~= _G.CUSTOM then
		local equipped = ItemRack.IsSetEquipped(setname)
		if equipped then
			texture = ItemRack.GetTextureBySlot(20)
		else
			setname = _G.CUSTOM
		end
	end
	if ItemRackButton20 and ItemRackUser.Buttons[20] then
		ItemRackButton20Icon:SetTexture(texture)
		ItemRackButton20Name:SetText(setname)
	end
	ItemRack.Broker.icon = texture
	ItemRack.Broker.text = setname
end

--[[ Item info gathering ]]

function ItemRack.GetTextureBySlot(slot)
	if slot == 20 then
		if ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet] then
			return ItemRackUser.Sets[ItemRackUser.CurrentSet].icon
		else
			return "Interface\\AddOns\\ItemRack\\ItemRackIcon"
		end
	else
		local texture = GetInventoryItemTexture("player", slot)
		if texture then
			return texture
		end
		return (select(2, GetInventorySlotInfo(ItemRack.SlotInfo[slot].name)))
	end
end

-- (link) -> IR id "62384:0:...:146"; (irID, true) -> baseID of an IR id; (link, true, true) -> baseID of a link; 0 on no match
ItemRack.iSPatternRegularToIR = "item:(.-)\124h" -- itemString sans "item:"
ItemRack.iSPatternBaseIDFromIR = "^(%-?%d+)" -- first field of an IR id
ItemRack.iSPatternBaseIDFromRegular = "item:(%-?%d+)" -- itemID field of a link/itemString
function ItemRack.GetIRString(inputString, baseid, regular)
	return string.match(inputString or "", (baseid and (regular and ItemRack.iSPatternBaseIDFromRegular or ItemRack.iSPatternBaseIDFromIR) or ItemRack.iSPatternRegularToIR)) or 0
end

-- injects the player's current level/spec so an ID saved before a ding still matches the same item
local IR_UPDATE_PATTERN = "^(" .. string.rep("%d+:", 8) .. ")%d+:%d+"
function ItemRack.UpdateIRString(itemRackID)
	-- outer parens discard gsub's 2nd return (substitution count)
	return (string.gsub(itemRackID, IR_UPDATE_PATTERN, "%1" .. UnitLevel("player") .. ":0"))
end

function ItemRack.IRStringToItemString(itemRackID)
	return "item:" .. itemRackID
end

-- returns the slot's IR id, or 0 for none; bag,nil = inventory slot, bag,slot = container slot
function ItemRack.GetID(bag, slot)
	local itemLink
	if slot then
		itemLink = C_Container.GetContainerItemLink(bag, slot)
	elseif bag == INVSLOT_AMMO then -- classic workaround for ammo slot API bugs
		local ammoID = GetInventoryItemID("player", bag)
		if ammoID then
			itemLink = select(2, GetItemInfo(ammoID))
		end
	else
		itemLink = GetInventoryItemLink("player", bag)
	end
	if ItemRack.AppendRuneID then
		local runeSuffix = ItemRack.AppendRuneID(bag, slot)
		if runeSuffix ~= "" then
			return ItemRack.GetIRString(itemLink) .. runeSuffix
		end
	end
	return ItemRack.GetIRString(itemLink)
end

-- true when the two IR ids (or baseIDs) share a base itemID
function ItemRack.SameID(id1, id2)
	return ItemRack.GetIRString(id1, true) == ItemRack.GetIRString(id2, true)
end

-- takes an IR id and returns name, texture, equipslot, quality
function ItemRack.GetInfoByID(id)
	if id and id ~= 0 then
		local name, _, quality, _, _, _, _, _, equip, texture = GetItemInfo(ItemRack.IRStringToItemString(ItemRack.UpdateIRString(id)))
		return name, texture, equip, quality
	end
	return "(empty)", "Interface\\Icons\\INV_Misc_QuestionMark", nil, 0
end

-- baseID count; ignores enchant/suffix differences
function ItemRack.GetCountByID(id)
	return GetItemCount(ItemRack.GetIRString(id, true))
end

-- searches worn equipment + bags (not bank), exact match before baseID match; returns (inv) worn, (nil, bag, slot) bag, nothing on miss
function ItemRack.FindItem(id, lock)
	local locklist, getid, sameid = ItemRack.LockList, ItemRack.GetID, ItemRack.SameID
	id = ItemRack.UpdateIRString(id)
	local known = ItemRack.KnownItems

	-- Pass 1: exact match via cache
	local cached = known[id]
	if cached then
		if cached < 0 then
			-- worn: encoded as -(slot+1) so slot 0 -> -1, slot 19 -> -20
			local inv = -cached - 1
			if (not lock or not locklist[-2][inv]) and id == getid(inv) then
				if lock then locklist[-2][inv] = 1 end
				return inv
			end
		else
			-- bag: encoded as bag*100+slot, slot >= 1
			local bag, slot = math.floor(cached/100), cached%100
			if slot > 0 and (not lock or not locklist[bag][slot]) and id == getid(bag, slot) then
				if lock then locklist[bag][slot] = 1 end
				return nil, bag, slot
			end
		end
	end

	-- Pass 2: exact match via manual scan (cache-miss safety net)
	for i = 4, 0, -1 do
		for j = 1, C_Container.GetContainerNumSlots(i) do
			if (not lock or not locklist[i][j]) and id == getid(i, j) then
				if lock then locklist[i][j] = 1 end
				return nil, i, j
			end
		end
	end
	for i = 0, 19 do
		if (not lock or not locklist[-2][i]) and id == getid(i) then
			if lock then locklist[-2][i] = 1 end
			return i
		end
	end

	-- Pass 3: baseID match via cache iteration (no per-slot API calls)
	for cachedID, location in pairs(known) do
		if sameid(id, cachedID) then
			if location < 0 then
				local inv = -location - 1
				if (not lock or not locklist[-2][inv]) and sameid(id, getid(inv)) then
					if lock then locklist[-2][inv] = 1 end
					return inv
				end
			else
				local bag, slot = math.floor(location/100), location%100
				if slot > 0 and (not lock or not locklist[bag][slot]) and sameid(id, getid(bag, slot)) then
					if lock then locklist[bag][slot] = 1 end
					return nil, bag, slot
				end
			end
		end
	end

	-- Pass 4: baseID match via manual scan (cache-miss safety net)
	for i = 4, 0, -1 do
		for j = 1, C_Container.GetContainerNumSlots(i) do
			if (not lock or not locklist[i][j]) and sameid(id, getid(i, j)) then
				if lock then locklist[i][j] = 1 end
				return nil, i, j
			end
		end
	end
	for i = 0, 19 do
		if (not lock or not locklist[-2][i]) and sameid(id, getid(i)) then
			if lock then locklist[-2][i] = 1 end
			return i
		end
	end
end

-- searches the bank (when open) and returns bag,slot; exact match before baseID match
function ItemRack.FindInBank(id, lock)
	if not ItemRack.BankOpen then return end
	local locklist, getid, sameid = ItemRack.LockList, ItemRack.GetID, ItemRack.SameID
	id = ItemRack.UpdateIRString(id)

	for _, i in pairs(ItemRack.BankSlots) do
		if ItemRack.ValidBag(i) then
			for j = 1, C_Container.GetContainerNumSlots(i) do
				if id == getid(i, j) and (not lock or not locklist[i][j]) then
					if lock then locklist[i][j] = 1 end
					return i, j
				end
			end
		end
	end
	for _, i in pairs(ItemRack.BankSlots) do
		if ItemRack.ValidBag(i) then
			for j = 1, C_Container.GetContainerNumSlots(i) do
				if sameid(id, getid(i, j)) and (not lock or not locklist[i][j]) then
					if lock then locklist[i][j] = 1 end
					return i, j
				end
			end
		end
	end
end

-- true for a normal container, as opposed to quivers and ammo pouches
function ItemRack.ValidBag(bagid)
	if bagid == 0 or bagid == -1 then
		return 1
	end
	local invID = C_Container.ContainerIDToInventoryID(bagid)
	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player", invID), true, true)
	if GetItemFamily(baseID) == 0 then
		return 1
	end
end

function ItemRack.ClearLockList()
	for i = -2, 10 do
		wipe(ItemRack.LockList[i])
	end
end

function ItemRack.FindSpace()
	for i = 4, 0, -1 do
		if ItemRack.ValidBag(i) then
			for j = 1, C_Container.GetContainerNumSlots(i) do
				if not C_Container.GetContainerItemLink(i, j) and not ItemRack.LockList[i][j] then
					ItemRack.LockList[i][j] = 1
					return i, j
				end
			end
		end
	end
end

function ItemRack.FindBankSpace()
	if not ItemRack.BankOpen then return end
	for _, i in pairs(ItemRack.BankSlots) do
		if ItemRack.ValidBag(i) then
			for j = 1, C_Container.GetContainerNumSlots(i) do
				if not C_Container.GetContainerItemLink(i, j) and not ItemRack.LockList[i][j] then
					ItemRack.LockList[i][j] = 1
					return i, j
				end
			end
		end
	end
end

function ItemRack.IsRed(which)
	local r, g, b = _G["ItemRackTooltipText" .. which]:GetTextColor()
	if r > .9 and g < .2 and b < .2 then
		return 1
	end
end

function ItemRack.PlayerCanWear(invslot, bag, slot)
	local i = 1
	while _G["ItemRackTooltipTextLeft" .. i] do
		-- ClearLines doesn't remove colors, manually remove them
		_G["ItemRackTooltipTextLeft" .. i]:SetTextColor(0, 0, 0)
		_G["ItemRackTooltipTextRight" .. i]:SetTextColor(0, 0, 0)
		i = i+1
	end
	ItemRackTooltip:SetBagItem(bag, slot)

	for i = 2, ItemRackTooltip:NumLines() do
		local txt = _G["ItemRackTooltipTextLeft" .. i]:GetText() or ""
		-- red text that isn't a durability or skill-requirement line means unwearable
		if (ItemRack.IsRed("Left" .. i) or ItemRack.IsRed("Right" .. i)) and not string.find(txt, ItemRack.DURABILITY_PATTERN) and not string.match(txt, ItemRack.REQUIRES_PATTERN) then
			return nil
		end
	end

	local _, _, itemType = ItemRack.GetInfoByID(ItemRack.GetID(bag, slot))
	if itemType == "INVTYPE_WEAPON" and invslot == 17 and not ItemRack.CanWearOneHandOffHand then
		return nil
	end

	return 1
end

function ItemRack.IsSoulbound(bag, slot)
	ItemRackTooltip:SetBagItem(bag, slot)
	for i = 2, 5 do
		local text = _G["ItemRackTooltipTextLeft" .. i]:GetText()
		if text == ITEM_SOULBOUND or text == ITEM_BIND_QUEST or text == ITEM_CONJURED then
			return 1
		end
	end
end

-- runs 0.2s after the last ITEM_LOCK_CHANGED
function ItemRack.LocksChanged()
	ItemRack.UpdateButtonLocks()
	if not ItemRack.AnythingLocked() then
		-- once a slot changed, its PendingSwap intent is stale; only game-rejected swaps stay for the combat-end retry
		for slot, p in pairs(ItemRack.PendingSwap) do
			if not ItemRack.SameID(ItemRack.GetID(slot), p.old) then
				ItemRack.PendingSwap[slot] = nil
			end
		end
	end
	if ItemRack.SetSwapping then
		ItemRack.LockChangedDuringSetSwap()
	elseif ItemRackMenuFrame:IsVisible() and ItemRack.BankOpen and not ItemRack.AnythingLocked() then
		ItemRackMenuFrame:Hide()
		ItemRack.BuildMenu()
	elseif #(ItemRack.SetsWaiting) > 0 and not ItemRack.AnythingLocked() then
		ItemRack.ProcessSetsWaiting()
	end
end

function ItemRack.PopulateKnownItems()
	local known = ItemRack.KnownItems
	wipe(known)
	local getid = ItemRack.GetID
	for i = 0, 19 do
		local id = getid(i)
		if id ~= 0 then
			-- -(slot+1) keeps slot 0 (ammo) distinguishable from "no entry"
			known[id] = -(i+1)
		end
	end
	for i = 0, 4 do
		for j = 1, C_Container.GetContainerNumSlots(i) do
			local id = getid(i, j)
			if id ~= 0 and IsEquippableItem(ItemRack.GetIRString(id, true)) then
				known[id] = i*100+j
			end
		end
	end
end

--[[ Timers ]]

function ItemRack.InitTimers()
	ItemRack.TimerPool = {}
	ItemRack.Timers = {}
end

-- rep = repeat until StopTimer; /script ItemRack.TimerDebug() lists timer status
function ItemRack.CreateTimer(name, func, delay, rep)
	ItemRack.TimerPool[name] = { func = func, delay = delay, rep = rep, elapsed = delay }
end

function ItemRack.IsTimerActive(name)
	for i, j in ipairs(ItemRack.Timers) do
		if j == name then
			return i
		end
	end
	return nil
end

function ItemRack.StartTimer(name, delay)
	ItemRack.TimerPool[name].elapsed = delay or ItemRack.TimerPool[name].delay
	if not ItemRack.IsTimerActive(name) then
		table.insert(ItemRack.Timers, name)
		ItemRackFrame:Show()
	end
end

function ItemRack.StopTimer(name)
	local idx = ItemRack.IsTimerActive(name)
	if idx then
		table.remove(ItemRack.Timers, idx)
		if #(ItemRack.Timers) < 1 then
			ItemRackFrame:Hide()
		end
	end
end

function ItemRack.OnUpdate(self, elapsed)
	-- backwards, so StopTimer's table.remove can't shift unvisited indices; timers started by a callback wait a frame
	local timers = ItemRack.Timers
	for i = #timers, 1, -1 do
		local name = timers[i]
		local timer = ItemRack.TimerPool[name]
		if timer then
			timer.elapsed = timer.elapsed - elapsed
			if timer.elapsed < 0 then
				timer.func(elapsed)
				if timer.rep then
					timer.elapsed = timer.delay
				else
					ItemRack.StopTimer(name)
				end
			end
		end
	end
end

function ItemRack.TimerDebug()
	local on = "|cFF00FF00On"
	local off = "|cFFFF0000Off"
	DEFAULT_CHAT_FRAME:AddMessage("|cFF44AAFFItemRackFrame is " .. (ItemRackFrame:IsVisible() and on or off))
	for i in pairs(ItemRack.TimerPool) do
		DEFAULT_CHAT_FRAME:AddMessage(i .. " is " .. (ItemRack.IsTimerActive(i) and on or off))
	end
end

--[[ Menu ]]

function ItemRack.DockWindows(menuDock, relativeTo, mainDock, menuOrient, movable)
	ItemRackMenuFrame:ClearAllPoints()
	ItemRack.currentDock = mainDock .. menuDock
	ItemRackMenuFrame:SetPoint(menuDock, relativeTo, mainDock, ItemRack.DockInfo[ItemRack.currentDock].xoff, ItemRack.DockInfo[ItemRack.currentDock].yoff)
	ItemRackMenuFrame:SetParent(relativeTo)
	ItemRackMenuFrame:SetFrameStrata("HIGH")
	ItemRack.mainDock = mainDock
	ItemRack.menuDock = menuDock
	ItemRack.menuOrient = menuOrient
	ItemRack.menuMovable = movable
	ItemRack.menuDockedTo = relativeTo:GetName()
	ItemRack.AddMouseoverFrame(relativeTo:GetName(), relativeTo)
	ItemRack.ReflectLock(not ItemRack.menuMovable)
	ItemRack.ReflectMenuScale()
end

function ItemRack.AlreadyInMenu(id)
	for i = 1, #(ItemRack.Menu) do
		if ItemRack.Menu[i] == id then
			return 1
		end
	end
end

function ItemRack.AddToMenu(itemID)
	if ItemRackSettings.AllowHidden == "OFF" or (IsAltKeyDown() or not ItemRack.IsHidden(itemID)) then
		table.insert(ItemRack.Menu, itemID)
	end
end

-- adds the item in bag,slot to the menu when it fits menu slot `id` and the player can wear it
local function AddWearableToMenu(id, bag, slot)
	local itemID = ItemRack.GetID(bag, slot)
	local equipSlot = select(3, ItemRack.GetInfoByID(itemID))
	if ItemRack.SlotInfo[id][equipSlot] and ItemRack.PlayerCanWear(id, bag, slot) and (ItemRackSettings.HideTradables == "OFF" or ItemRack.IsSoulbound(bag, slot)) then
		-- the ammo menu (id 0) dedupes stacks of the same ammo
		if id ~= 0 or not ItemRack.AlreadyInMenu(itemID) then
			ItemRack.AddToMenu(itemID)
		end
	end
end

-- id = 0-19 slot menu, 20 set menu, nil = reopen the last menu; menuInclude adds worn item(s); dock via DockWindows first
function ItemRack.BuildMenu(id, menuInclude, masqueGroup)
	if id then
		ItemRack.menuOpen = id
		ItemRack.menuInclude = menuInclude
	else
		id = ItemRack.menuOpen
		menuInclude = ItemRack.menuInclude
	end

	local showButtonMenu = (ItemRackButtonMenu and ItemRack.menuMovable) and (IsAltKeyDown() or ItemRackUser.Locked == "OFF")

	wipe(ItemRack.Menu)

	if id < 20 then
		if menuInclude then
			local itemID = ItemRack.GetID(id)
			if itemID ~= 0 then
				ItemRack.AddToMenu(itemID)
			end
			if ItemRack.SlotInfo[id].other then
				itemID = ItemRack.GetID(ItemRack.SlotInfo[id].other)
				if itemID ~= 0 then
					ItemRack.AddToMenu(itemID)
				end
			end
		end
		for i = 0, 4 do
			for j = 1, C_Container.GetContainerNumSlots(i) do
				AddWearableToMenu(id, i, j)
			end
		end
		if ItemRack.BankOpen then
			for _, i in pairs(ItemRack.BankSlots) do
				for j = 1, C_Container.GetContainerNumSlots(i) do
					AddWearableToMenu(id, i, j)
				end
			end
		elseif ItemRack.GetID(id) ~= 0 and ItemRackSettings.AllowEmpty == "ON" then
			table.insert(ItemRack.Menu, 0)
		end
	else
		for i in pairs(ItemRackUser.Sets) do
			if not string.match(i, "^~") then -- internal sets stay out of the menu
				ItemRack.AddToMenu(i)
			end
		end
		table.sort(ItemRack.Menu)
	end
	if showButtonMenu then
		table.insert(ItemRack.Menu, "MENU")
	end

	if #(ItemRack.Menu) < 1 then
		ItemRackMenuFrame:Hide()
	else
		-- display outward from docking point
		local col, row, xpos, ypos = 0, 0, ItemRack.DockInfo[ItemRack.currentDock].xstart, ItemRack.DockInfo[ItemRack.currentDock].ystart
		local max_cols = 1
		local button, icon

		if ItemRackUser.SetMenuWrap == "ON" then
			max_cols = ItemRackUser.SetMenuWrapValue
		elseif #(ItemRack.Menu) > 24 then
			max_cols = 5
		elseif #(ItemRack.Menu) > 18 then
			max_cols = 4
		elseif #(ItemRack.Menu) > 9 then
			max_cols = 3
		elseif #(ItemRack.Menu) > 4 then
			max_cols = 2
		end

		for i = 1, #(ItemRack.Menu) do
			button = ItemRack.CreateMenuButton(i, ItemRack.Menu[i]) or ItemRackButtonMenu
			button:SetPoint("TOPLEFT", ItemRackMenuFrame, ItemRack.menuDock, xpos, ypos)
			if ItemRack.Menu[i] == "MENU" then
				-- lock/queue/options/close sit above neighboring item cooldown swipes
				button:SetFrameLevel(ItemRackMenuFrame:GetFrameLevel() + 5)
			else
				button:SetFrameLevel(ItemRackMenuFrame:GetFrameLevel() + 1)
			end

			if ItemRack.MasqueGroups then
				for _, group in pairs(ItemRack.MasqueGroups) do
					group:RemoveButton(button)
				end

				if ItemRack.MasqueGroups[masqueGroup] then
					ItemRack.MasqueGroups[masqueGroup]:AddButton(button)
				end
			end

			if ItemRack.Menu[i] ~= "MENU" then
				ItemRack.SetButtonBadge(button, ItemRack.Menu[i])
			end

			if ItemRack.menuOrient == "VERTICAL" then
				xpos = xpos + ItemRack.DockInfo[ItemRack.currentDock].xdir*40
				col = col + 1
				if col == max_cols then
					xpos = ItemRack.DockInfo[ItemRack.currentDock].xstart
					col = 0
					ypos = ypos + ItemRack.DockInfo[ItemRack.currentDock].ydir*40
					row = row + 1
				end
				button:Show()
			else
				ypos = ypos + ItemRack.DockInfo[ItemRack.currentDock].ydir*40
				col = col + 1
				if col == max_cols then
					ypos = ItemRack.DockInfo[ItemRack.currentDock].ystart
					col = 0
					xpos = xpos + ItemRack.DockInfo[ItemRack.currentDock].xdir*40
					row = row + 1
				end
				button:Show()
			end
			icon = _G["ItemRackMenu" .. i .. "Icon"]
			if icon then
				icon:SetDesaturated(false)
				if IsAltKeyDown() and ItemRackSettings.AllowHidden == "ON" and ItemRack.IsHidden(ItemRack.Menu[i]) then
					icon:SetDesaturated(true)
				end
			end
		end
		if showButtonMenu then
			table.remove(ItemRack.Menu)
		else
			ItemRackButtonMenu:Hide()
		end
		local i = #(ItemRack.Menu)+1
		while _G["ItemRackMenu" .. i] do
			_G["ItemRackMenu" .. i]:Hide()
			i = i+1
		end

		if col == 0 then
			row = row-1
		end

		if ItemRack.menuOrient == "VERTICAL" then
			ItemRackMenuFrame:SetWidth(12+(max_cols*40))
			ItemRackMenuFrame:SetHeight(12+((row+1)*40))
		else
			ItemRackMenuFrame:SetWidth(12+((row+1)*40))
			ItemRackMenuFrame:SetHeight(12+(max_cols*40))
		end

		ItemRackMenuFrame:Show()
		ItemRack.UpdateMenuCooldowns()
		local count
		local border
		for i = 1, #(ItemRack.Menu) do
			border = _G["ItemRackMenu" .. i .. "Border"]
			border:Hide()
			if ItemRack.menuOpen == 20 then
				_G["ItemRackMenu" .. i .. "Name"]:SetText(ItemRack.Menu[i])
				local missing = ItemRack.MissingItems(ItemRack.Menu[i])
				if missing == 0 then
					border:SetVertexColor(1, .1, .1)
					border:Show()
				elseif missing == 1 then
					border:SetVertexColor(.3, .5, 1)
					border:Show()
				end
			else
				_G["ItemRackMenu" .. i .. "Name"]:SetText("")
				if ItemRack.Menu[i] ~= 0 and ItemRack.GetCountByID(ItemRack.Menu[i]) == 0 then
					border:SetVertexColor(.3, .5, 1)
					border:Show()
				end
			end
			if ItemRack.menuOpen == 0 then
				count = ItemRack.GetCountByID(ItemRack.Menu[i])
				_G["ItemRackMenu" .. i .. "Count"]:SetText(count > 0 and count or "")
			else
				_G["ItemRackMenu" .. i .. "Count"]:SetText("")
			end
		end
	end
end

function ItemRack.UpdateMenuCooldowns()
	local writeNumbers = ItemRackSettings.CooldownCount == "ON" and ItemRackMenuFrame:IsVisible()
	local menuOpenIsItem = ItemRack.menuOpen < 20
	for i = 1, #ItemRack.Menu do
		local baseID = tonumber(ItemRack.GetIRString(ItemRack.Menu[i], true)) -- nil/0 for set names and the empty-slot entry
		local start, duration, enable
		if baseID and baseID > 0 and menuOpenIsItem then
			start, duration, enable = C_Container.GetItemCooldown(baseID)
			CooldownFrame_Set(_G["ItemRackMenu" .. i .. "Cooldown"], start, duration, enable)
		else
			_G["ItemRackMenu" .. i .. "Cooldown"]:Hide()
		end
		if writeNumbers then
			-- start/duration are nil for set names and the empty-slot entry; WriteCooldown blanks the overlay for those
			ItemRack.WriteCooldown(_G["ItemRackMenu" .. i .. "Time"], start, duration)
		end
	end
end

-- Menu numeric-overlay refresh ticked by the 0.5s CooldownUpdate timer.
function ItemRack.WriteMenuCooldowns()
	if ItemRackSettings.CooldownCount ~= "ON" or not ItemRackMenuFrame:IsVisible() then return end
	for i = 1, #ItemRack.Menu do
		local baseID = tonumber(ItemRack.GetIRString(ItemRack.Menu[i], true)) -- nil/0 for set names and the empty-slot entry
		if baseID and baseID > 0 then
			ItemRack.WriteCooldown(_G["ItemRackMenu" .. i .. "Time"], C_Container.GetItemCooldown(baseID))
		else
			_G["ItemRackMenu" .. i .. "Time"]:SetText("")
		end
	end
end

-- name-only entries still matter: MenuMouseover's fallback loop resolves frames via _G[name]
function ItemRack.AddMouseoverFrame(name, frame)
	if ItemRack.MenuMouseoverFrames[name] then return end
	ItemRack.MenuMouseoverFrames[name] = 1
	if frame then
		frame:HookScript("OnLeave", ItemRack.MenuMouseover)
	end
end

function ItemRack.MenuMouseover()
	if not ItemRackMenuFrame:IsVisible() then return end
	local frame = GetMouseFoci()[1]
	local frameName, frameVisible, IRmouseOverFrame
	if frame then
		frameName = frame:GetName()
		frameVisible = frame:IsVisible()
		if frameName then IRmouseOverFrame = ItemRack.MenuMouseoverFrames[frameName] end
	end
	if MouseIsOver(ItemRackMenuFrame) or (frameVisible and IRmouseOverFrame) then
		return
	end
	for i in pairs(ItemRack.MenuMouseoverFrames) do
		frame = _G[i]
		if frame and frame:IsVisible() and MouseIsOver(frame) then
			return
		end
	end
	ItemRackMenuFrame:Hide()
end

function ItemRack.MenuOnHide()
	ItemRack.menuDockedTo = nil
end

function ItemRack.CreateMenuButton(idx, itemID)
	if itemID == "MENU" then return end
	local button
	if not _G["ItemRackMenu" .. idx] then
		button = CreateFrame("CheckButton", "ItemRackMenu" .. idx, ItemRackMenuFrame, "ActionButtonTemplate")
		button:SetID(idx)
		button:SetFrameStrata("HIGH")
		button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		button:SetScript("OnClick", ItemRack.MenuOnClick)
		button:SetScript("OnEnter", ItemRack.MenuTooltip)
		button:SetScript("OnLeave", ItemRack.ClearTooltip)
		button:HookScript("OnLeave", ItemRack.MenuMouseover) -- close menu the moment cursor leaves a button into empty space
		CreateFrame("Frame", nil, button, "ItemRackTimeTemplate")

		ItemRack.SetFont("ItemRackMenu" .. idx)
	end
	if itemID ~= 0 then
		if ItemRackUser.Sets[itemID] then
			_G["ItemRackMenu" .. idx .. "Icon"]:SetTexture(ItemRackUser.Sets[itemID].icon)
		else
			local _, texture = ItemRack.GetInfoByID(itemID)
			_G["ItemRackMenu" .. idx .. "Icon"]:SetTexture(texture)
		end
	else
		_G["ItemRackMenu" .. idx .. "Icon"]:SetTexture(select(2, GetInventorySlotInfo(ItemRack.SlotInfo[ItemRack.menuOpen].name)))
	end
	return _G["ItemRackMenu" .. idx]
end

-- links the best inventory match into the chat editbox, else a link generated from the stored ID
function ItemRack.ChatLinkID(itemID)
	local inv, bag, slot = ItemRack.FindItem(itemID)
	if bag then
		ChatFrame1EditBox:Insert(C_Container.GetContainerItemLink(bag, slot))
	elseif inv then
		ChatFrame1EditBox:Insert(GetInventoryItemLink("player", inv))
	else
		local _, itemLink = GetItemInfo(ItemRack.IRStringToItemString(ItemRack.UpdateIRString(itemID)))
		if itemLink then
			ChatFrame1EditBox:Insert(itemLink)
		end
	end
end

function ItemRack.MenuOnClick(self, button)
	self:SetChecked(false)
	local item = ItemRack.Menu[self:GetID()]
	ItemRack.ClearLockList()
	if IsAltKeyDown() and ItemRackSettings.AllowHidden == "ON" then
		ItemRack.ToggleHidden(item)
		ItemRack.BuildMenu()
	elseif IsShiftKeyDown() and ChatFrame1EditBox:IsVisible() then
		ItemRack.ChatLinkID(item)
	elseif ItemRack.menuInclude then
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOpt.Inv[ItemRack.menuOpen].id = item
			ItemRackOpt.Inv[ItemRack.menuOpen].selected = 1
			ItemRackOpt.UpdateInv()
			ItemRackMenuFrame:Hide()
		end
	elseif ItemRack.menuOpen < 20 then
		if ItemRack.BankOpen then
			if ItemRack.GetCountByID(item) == 0 then
				local bankBag, bankSlot = ItemRack.FindInBank(item)
				if bankBag then
					local freeBag, freeSlot = ItemRack.FindSpace()
					if freeBag and not SpellIsTargeting() and not GetCursorInfo() then
						C_Container.PickupContainerItem(bankBag, bankSlot)
						C_Container.PickupContainerItem(freeBag, freeSlot)
					else
						ItemRack.Print("Not enough room in bags to pull this item from bank.")
					end
				end
			else
				local bankBag, bankSlot = ItemRack.FindBankSpace()
				if bankBag then
					local _, bag, slot = ItemRack.FindItem(item)
					if bag and not SpellIsTargeting() and not GetCursorInfo() then
						C_Container.PickupContainerItem(bag, slot)
						C_Container.PickupContainerItem(bankBag, bankSlot)
					end
				else
					ItemRack.Print("Not enough room in bank to put this item.")
				end
			end
		else
			if ItemRackSettings.EquipOnSetPick == "ON" and ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
				ItemRackOpt.Inv[ItemRack.menuOpen].id = item
				ItemRackOpt.Inv[ItemRack.menuOpen].selected = 1
				ItemRackOpt.UpdateInv()
			end
			if ItemRack.menuOpen >= 13 and ItemRack.menuOpen <= 14 and ItemRackSettings.TrinketMenuMode == "ON" and ItemRackUser.Buttons[13] and ItemRackUser.Buttons[14] then
				ItemRack.menuOpen = button == "RightButton" and 14 or 13
			end
			ItemRack.EquipItemByID(item, ItemRack.menuOpen)
			ItemRackMenuFrame:Hide()
		end
	elseif ItemRack.menuOpen == 20 then
		if ItemRack.BankOpen then
			if ItemRack.MissingItems(item) == 1 then
				ItemRack.GetBankedSet(item)
			else
				ItemRack.PutBankedSet(item)
			end
		elseif ItemRackSettings.EquipToggle == "ON" or IsShiftKeyDown() then
			ItemRack.ToggleSet(item)
		else
			ItemRack.EquipSet(item)
		end
		if not ItemRack.BankOpen then
			ItemRackMenuFrame:Hide()
		end
	end
end

function ItemRack.EquipItemByID(id, slot)
	if ItemRack.NowCasting or ItemRack.NowShooting or InCombatLockdown() or UnitAffectingCombat("player") or ItemRack.IsPlayerReallyDead() then
		ItemRack.AddToCombatQueue(slot, id)
	elseif not GetCursorInfo() and not SpellIsTargeting() then
		if id ~= 0 then
			local _, b, s = ItemRack.FindItem(id)
			if b then
				local info = C_Container.GetContainerItemInfo(b, s)
				if not (info and info.isLocked) and not IsInventoryItemLocked(slot) then
					local _, _, equipSlot = ItemRack.GetInfoByID(id)
					if equipSlot ~= "INVTYPE_2HWEAPON" or not GetInventoryItemLink("player", 17) then
						C_Container.PickupContainerItem(b, s)
						PickupInventoryItem(slot)
					else
						local bfree, sfree = ItemRack.FindSpace()
						if bfree then
							PickupInventoryItem(17)
							C_Container.PickupContainerItem(bfree, sfree)
							PickupInventoryItem(slot)
							C_Container.PickupContainerItem(b, s)
						else
							ItemRack.Print("Not enough room to perform swap.")
						end
					end
				end
			end
		else
			local b, s = ItemRack.FindSpace()
			if b and not IsInventoryItemLocked(slot) then
				PickupInventoryItem(slot)
				C_Container.PickupContainerItem(b, s)
			else
				ItemRack.Print("Not enough room to perform swap.")
			end
		end
	end
end

--[[ Hooks to capture item use outside the mod ]]

function ItemRack.ReflectItemUse(id)
	if ItemRackUser.Buttons[id] then
		_G["ItemRackButton" .. id]:SetChecked(true)
		ItemRack.ReflectClicked[id] = 1
		ItemRack.StartTimer("ReflectClickedUpdate")
	end
	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player", id), true, true)
	if baseID then
		ItemRackUser.ItemsUsed[baseID] = 1
	end
	-- kick the auto-queue on the same frame as the use; without this, the swap waits up to one CooldownUpdate tick (0.5s)
	ItemRack.PeriodicQueueCheck()
end

function ItemRack.newPaperDollFrame_OnShow()
	ItemRack.UpdateCombatQueue()
	-- AddMouseoverFrame is idempotent, so repeated shows don't stack OnLeave handlers
	ItemRack.AddMouseoverFrame("PaperDollFrame", PaperDollFrame)
	ItemRack.AddMouseoverFrame("CharacterTrinket1Slot", CharacterTrinket1Slot)
end

function ItemRack.newUseInventoryItem(slot)
	ItemRack.ReflectItemUse(slot)
end

function ItemRack.newUseAction(slot, cursor, self)
	if IsEquippedAction(slot) then
		local actionType, actionId = GetActionInfo(slot)
		if actionType == "item" then
			for i = 0, 19 do
				if tonumber(ItemRack.GetIRString(GetInventoryItemLink("player", i), true, true)) == actionId then
					ItemRack.ReflectItemUse(i)
					break
				end
			end
		end
	end
end

function ItemRack.newUseItemByName(name)
	for i = 0, 19 do
		if name == GetItemInfo(GetInventoryItemLink("player", i) or 0) then
			ItemRack.ReflectItemUse(i)
			break
		end
	end
end

--[[ Combat queue ]]

function ItemRack.IsPlayerReallyDead()
	return UnitIsDeadOrGhost("player") and not UnitIsFeignDeath("player")
end

function ItemRack.AddToCombatQueue(slot, id)
	if ItemRack.CombatQueue[slot] == id then
		ItemRack.CombatQueue[slot] = nil
	else
		ItemRack.CombatQueue[slot] = id
	end
	-- entries written here are user/external; ProcessAutoQueue re-asserts origin right after when it's the caller
	ItemRack.AutoQueueOrigin[slot] = nil
	ItemRack.UpdateCombatQueue()
end

-- ActionButtonTemplate pins the cooldown to the button's own level. Unpin and stack:
-- identity badge above the icon but under the swipe; cooldown numbers and the auto-queue
-- wheel above the swipe so the gear is never covered by the cooldown shadow.
function ItemRack.StackButtonLayers(button)
	local cooldown = _G[button:GetName() .. "Cooldown"]
	if cooldown and cooldown.IsUsingParentLevel and cooldown:IsUsingParentLevel() then
		cooldown:SetUsingParentLevel(false)
	end
	local base = button:GetFrameLevel()
	if button.IRBadgeFrame then
		button.IRBadgeFrame:SetFrameLevel(base + 1)
	end
	if cooldown then
		cooldown:SetFrameLevel(base + 2)
	end
	local timeText = _G[button:GetName() .. "Time"]
	if timeText then
		local timeFrame = timeText:GetParent()
		if timeFrame and timeFrame ~= button then
			timeFrame:SetFrameLevel(base + 3)
		end
	end
	local queue = _G[button:GetName() .. "Queue"]
	if queue then
		local queueFrame = queue:GetParent()
		if queueFrame and queueFrame ~= button then
			queueFrame:SetFrameLevel(base + 4)
		end
	end
end

-- Corner badge for the queued item on a slot's queue overlay.
local function SetQueueBadge(queue, id)
	local parent = queue:GetParent()
	local badge = parent.IRBadge
	if not badge then
		badge = parent:CreateTexture(nil, "OVERLAY")
		badge:SetSize(12, 12)
		badge:SetPoint("BOTTOMRIGHT", queue, "BOTTOMRIGHT", 1, -1)
		parent.IRBadge = badge
	end
	local badgeTexture = ItemRack.IconBadges[tonumber(ItemRack.GetIRString(id, true))]
	badge:SetTexture(badgeTexture)
	badge:SetShown(badgeTexture ~= nil)
end

local function raiseQueueAboveCooldown(queue, owner)
	local queueFrame = queue:GetParent()
	if not owner or not queueFrame or queueFrame == owner then return end
	local cooldown = _G[owner:GetName() .. "Cooldown"]
	local above = owner:GetFrameLevel() + 4
	if cooldown then
		above = math.max(above, cooldown:GetFrameLevel() + 1)
	end
	queueFrame:SetFrameLevel(above)
end

function ItemRack.UpdateCombatQueue()
	local queue
	for i in pairs(ItemRackUser.Buttons) do
		local button = _G["ItemRackButton" .. i]
		queue = _G["ItemRackButton" .. i .. "Queue"]
		if ItemRack.CombatQueue[i] then
			queue:SetTexture(select(2, ItemRack.GetInfoByID(ItemRack.CombatQueue[i])))
			queue:SetAlpha(1)
			queue:Show()
			SetQueueBadge(queue, ItemRack.CombatQueue[i])
		elseif ItemRack.GetQueuesEnabled()[i] then
			queue:SetTexture("Interface\\AddOns\\ItemRack\\ItemRackGear")
			queue:SetAlpha(ItemRackUser.EnableQueues == "ON" and 1 or .5)
			queue:Show()
			SetQueueBadge(queue, nil)
		elseif i ~= 20 then
			queue:Hide()
			SetQueueBadge(queue, nil)
		end
		ItemRack.StackButtonLayers(button)
	end

	for i = 1, 19 do
		local slotButton = _G["Character" .. ItemRack.SlotInfo[i].name]
		queue = _G["Character" .. ItemRack.SlotInfo[i].name .. "Queue"]
		if ItemRack.CombatQueue[i] then
			queue:SetTexture(select(2, ItemRack.GetInfoByID(ItemRack.CombatQueue[i])))
			queue:Show()
			SetQueueBadge(queue, ItemRack.CombatQueue[i])
		else
			queue:Hide()
			SetQueueBadge(queue, nil)
		end
		raiseQueueAboveCooldown(queue, slotButton)
	end
end

--[[ Tooltip ]]

-- request a tooltip of an inventory slot
function ItemRack.InventoryTooltip(self)
	local id = self:GetID()
	if id == 20 then
		ItemRack.SetTooltip(self, ItemRackUser.CurrentSet)
	else
		ItemRack.TooltipOwner = self
		ItemRack.TooltipType = "INVENTORY"
		ItemRack.TooltipSlot = id
		-- queued item's name, shown by TooltipUpdate as a "Queued: <name>" line
		ItemRack.TooltipQueued = ItemRack.CombatQueue[id] and ItemRack.GetInfoByID(ItemRack.CombatQueue[id])
		ItemRack.StartTimer("TooltipUpdate", 0)
	end
end

-- tooltip for a popout-menu button
function ItemRack.MenuTooltip(self)
	local id = self:GetID()
	if ItemRack.menuOpen == 20 then
		ItemRack.SetTooltip(self, ItemRack.Menu[id])
	else
		ItemRack.TooltipOwner = self
		ItemRack.TooltipType = "BAG"
		-- worn or missing items leave bag/slot nil and fall through to IDTooltip
		ItemRack.TooltipBag, ItemRack.TooltipSlot = select(2, ItemRack.FindItem(ItemRack.Menu[id]))
		if ItemRack.TooltipBag and ItemRack.TooltipSlot then
			ItemRack.StartTimer("TooltipUpdate", 0)
		else
			ItemRack.IDTooltip(self, ItemRack.Menu[id])
		end
	end
end

-- tooltip from a raw IR id (set items inside the options GUI)
function ItemRack.IDTooltip(self, itemID)
	ItemRack.AnchorTooltip(self)
	local inv, bag, slot = ItemRack.FindItem(itemID)
	if inv then
		GameTooltip:SetInventoryItem("player", inv)
	elseif bag then
		GameTooltip:SetBagItem(bag, slot)
	else
		bag, slot = ItemRack.FindInBank(itemID)
		if bag then
			itemID = C_Container.GetContainerItemLink(bag, slot)
		else
			itemID = ItemRack.IRStringToItemString(ItemRack.UpdateIRString(itemID))
		end
		GameTooltip:SetHyperlink(itemID)
	end
	ItemRack.ShrinkTooltip(self)
	GameTooltip:Show()
end

function ItemRack.ClearTooltip(self)
	GameTooltip:Hide()
	ItemRack.StopTimer("TooltipUpdate")
	ItemRack.TooltipType = nil
end

function ItemRack.AnchorTooltip(owner)
	if string.match(ItemRack.menuDockedTo or "", "^Character") then
		GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	elseif ItemRackSettings.TooltipFollow == "ON" then
		if owner.GetLeft and owner:GetLeft() and owner:GetLeft() < 400 then
			GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
		else
			GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
		end
	else
		GameTooltip_SetDefaultAnchor(GameTooltip, owner)
	end
end

-- re-shown once a second while the item is on cooldown
function ItemRack.TooltipUpdate()
	if ItemRack.TooltipType then
		local cooldown
		ItemRack.AnchorTooltip(ItemRack.TooltipOwner)
		if ItemRack.TooltipType == "BAG" then
			GameTooltip:SetBagItem(ItemRack.TooltipBag, ItemRack.TooltipSlot)
			cooldown = C_Container.GetContainerItemCooldown(ItemRack.TooltipBag, ItemRack.TooltipSlot)
		else
			GameTooltip:SetInventoryItem("player", ItemRack.TooltipSlot)
			cooldown = GetInventoryItemCooldown("player", ItemRack.TooltipSlot)
		end
		ItemRack.ShrinkTooltip(ItemRack.TooltipOwner)
		if ItemRack.TooltipType == "INVENTORY" and ItemRack.TooltipQueued then
			GameTooltip:AddLine("Queued: " .. ItemRack.TooltipQueued)
		end
		GameTooltip:Show()
		if cooldown == 0 then
			ItemRack.StopTimer("TooltipUpdate")
			ItemRack.TooltipType = nil
		end
	end
end

function ItemRack.OnTooltip(self, line1, line2)
	if ItemRackSettings.ShowTooltips == "ON" then
		ItemRack.AnchorTooltip(self)
		if line1 then
			GameTooltip:AddLine(line1)
			GameTooltip:AddLine(line2, .8, .8, .8, 1)
			GameTooltip:Show()
			return
		else
			local name = self:GetName() or ""
			for i = 1, #(ItemRack.TooltipInfo) do
				if ItemRack.TooltipInfo[i][1] == name and ItemRack.TooltipInfo[i][2] then
					GameTooltip:AddLine(ItemRack.TooltipInfo[i][2])
					GameTooltip:AddLine(ItemRack.TooltipInfo[i][3], .8, .8, .8, 1)
					GameTooltip:Show()
					return
				end
			end
		end
	end
end

function ItemRack.ShrinkTooltip(owner)
	if ItemRackSettings.TinyTooltips == "ON" then
		local r, g, b = GameTooltipTextLeft1:GetTextColor()
		local name = GameTooltipTextLeft1:GetText()
		local line, charge, durability, cooldown
		for i = 2, GameTooltip:NumLines() do
			line = _G["GameTooltipTextLeft" .. i]
			if line:IsVisible() then
				line = line:GetText() or ""
				if string.match(line, ItemRack.DURABILITY_PATTERN) then
					durability = line
				end
				if string.match(line, COOLDOWN_REMAINING) then
					cooldown = line
				end
				for j = 1, #ItemRack.CHARGES_PATTERNS do
					if string.find(line, ItemRack.CHARGES_PATTERNS[j]) then
						charge = line
					end
				end
			end
		end
		ItemRack.AnchorTooltip(owner)
		GameTooltip:AddLine(name, r, g, b)
		GameTooltip:AddLine(charge, 1, 1, 1)
		GameTooltip:AddLine(durability, 1, 1, 1)
		GameTooltip:AddLine(cooldown, 1, 1, 1)
	end
end

function ItemRack.SetTooltip(self, setname)
	local set = setname and ItemRackUser.Sets[setname] and ItemRackUser.Sets[setname].equip
	if set then
		local itemName, itemColor
		ItemRack.AnchorTooltip(self)
		GameTooltip:AddLine(setname)
		if ItemRackSettings.TinyTooltips ~= "ON" then
			for i = 0, 19 do
				if set[i] then
					itemName = ItemRack.GetInfoByID(set[i])
					if itemName then
						if itemName ~= "(empty)" and ItemRack.GetCountByID(set[i]) == 0 then
							if not ItemRack.FindInBank(set[i]) then
								itemColor = "FFFF1111"
							else
								itemColor = "FF4C80FF"
							end
						else
							itemColor = "FFAAAAAA"
						end
						GameTooltip:AddLine("|cFFFFFFFF" .. ItemRack.SlotInfo[i].real .. ": |c" .. itemColor .. itemName)
					end
				end
			end
		end
		GameTooltip:Show()
	end
end

--[[ Notify ]]

function ItemRack.Notify(msg)
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
	UIErrorsFrame:AddMessage(msg, .2, .7, .9, 1, UIERRORS_HOLD_TIME)
	if ItemRackSettings.NotifyChatAlso == "ON" then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33b2e5" .. msg)
	end
end

function ItemRack.CooldownUpdate()
	local start, duration, name, remain
	for i in pairs(ItemRackUser.ItemsUsed) do
		start, duration = C_Container.GetItemCooldown(i)
		if start and ItemRackUser.ItemsUsed[i] < 6 then
			ItemRackUser.ItemsUsed[i] = ItemRackUser.ItemsUsed[i] + 1 -- count for ~3 seconds (6 ticks at 0.5s) before seeing if this is a real cooldown
		elseif start then
			if start > 0 then
				remain = duration - (GetTime()-start)
				if ItemRackUser.ItemsUsed[i] < 5 then
					if remain > 29 then
						ItemRackUser.ItemsUsed[i] = 30 -- first actual cooldown greater than 30 seconds, tag it for 30+0 notify
					elseif remain > 5 then
						ItemRackUser.ItemsUsed[i] = 5 -- first actual cooldown less than 30 but greater than 5, tag for 0 notify
					end
				end
			end
			if ItemRackUser.ItemsUsed[i] == 30 and start > 0 and remain < 30 then
				if ItemRackSettings.NotifyThirty == "ON" then
					name = GetItemInfo(i)
					if name then
						ItemRack.Notify(name .. " ready soon!")
					end
				end
				ItemRackUser.ItemsUsed[i] = 5 -- tag for just 0 notify now
			elseif ItemRackUser.ItemsUsed[i] == 5 and start == 0 then
				if ItemRackSettings.Notify == "ON" then
					name = GetItemInfo(i)
					if name then
						ItemRack.Notify(name .. " ready!")
					end
				end
			end
			if start == 0 then
				ItemRackUser.ItemsUsed[i] = nil
			end
		end
	end

	if ItemRackSettings.CooldownCount == "ON" then
		ItemRack.WriteButtonCooldowns()
		ItemRack.WriteMenuCooldowns()
	end

	ItemRack.PeriodicQueueCheck()
end

--[[ Character sheet menus ]]

hooksecurefunc("PaperDollItemSlotButton_OnEnter", function(self)
	if ItemRack.menuDockedTo ~= self:GetName() and (ItemRackSettings.MenuOnShift == "OFF" or IsShiftKeyDown()) and ItemRackSettings.CharacterSheetMenus == "ON" then
		ItemRack.DockMenuToCharacterSheet(self)
	end
end)

function ItemRack.DockMenuToCharacterSheet(self)
	local name = self:GetName()
	local slot
	for i = 0, 19 do
		if name == "Character" .. ItemRack.SlotInfo[i].name then
			slot = i
			break
		end
	end
	if slot then
		if slot == 0 or (slot >= 16 and slot <= 18) then
			ItemRack.DockWindows("TOPLEFT", self, "BOTTOMLEFT", "VERTICAL")
		else
			if slot == 14 and ItemRackSettings.TrinketMenuMode == "ON" then
				self = CharacterTrinket0Slot
			end
			ItemRack.DockWindows("TOPLEFT", self, "TOPRIGHT", "HORIZONTAL")
		end
		ItemRack.BuildMenu(slot, nil, 3)
	end
end

--[[ Minimap button ]]

function ItemRack.InitBroker()
	local texture = [[Interface\AddOns\ItemRack\ItemRackIcon]]
	ItemRack.Broker = LDB:NewDataObject("ItemRack", {
		type = "launcher",
		text = "ItemRack",
		icon = texture,
		OnClick = ItemRack.MinimapOnClick,
		OnTooltipShow = ItemRack.MinimapOnEnter,
	})
	ItemRackSettings.minimap = ItemRackSettings.minimap or { hide = false }
	LDBIcon:Register("ItemRack", ItemRack.Broker, ItemRackSettings.minimap)
	ItemRack.ShowMinimap()
end

function ItemRack.ShowMinimap()
	if ItemRackSettings.ShowMinimap == "ON" then
		LDBIcon:Show("ItemRack")
	else
		LDBIcon:Hide("ItemRack")
	end
end

function ItemRack.MinimapOnClick(self, button)
	if IsShiftKeyDown() then
		if ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet] then
			ItemRack.UnequipSet(ItemRackUser.CurrentSet)
		end
	elseif IsAltKeyDown() and (button == "RightButton" or ItemRackSettings.AllowHidden == "OFF") then
		ItemRack.ToggleEvents()
	elseif button == "LeftButton" then
		if ItemRackMenuFrame:IsVisible() then
			ItemRackMenuFrame:Hide()
		else
			local xpos, ypos = GetCursorPosition()
			if ypos > 400 then
				ItemRack.DockWindows("TOPRIGHT", self, "BOTTOMRIGHT", "VERTICAL")
			else
				ItemRack.DockWindows("BOTTOMRIGHT", self, "TOPRIGHT", "VERTICAL")
			end
			ItemRack.BuildMenu(20, nil, 4)
		end
	else
		ItemRack.ToggleOptions(self)
	end
end

function ItemRack.MinimapOnEnter(tooltip)
	if ItemRackSettings.MinimapTooltip ~= "ON" then return end
	tooltip:AddLine("ItemRack")
	tooltip:AddLine("Left click: Select a set", .8, .8, .8, 1)
	tooltip:AddLine("Right click: Open options", .8, .8, .8, 1)
	tooltip:AddLine("Alt left click: Show hidden sets", .8, .8, .8, 1)
	tooltip:AddLine("Alt right click: Toggle events", .8, .8, .8, 1)
	tooltip:AddLine("Shift click: Unequip this set", .8, .8, .8, 1)
end

--[[ Non-LoD options support ]]

function ItemRack.ToggleOptions(self, tab)
	if not ItemRackOptFrame then
		C_AddOns.EnableAddOn("ItemRackOptions") -- LoD and required; enable in case it was disabled
		C_AddOns.LoadAddOn("ItemRackOptions")
	end
	if ItemRackOptFrame:IsVisible() then
		ItemRackOptFrame:Hide()
	else
		ItemRackOptFrame:Show()
		if tab then
			ItemRackOpt.TabOnClick(self, tab)
		end
	end
end

function ItemRack.ReflectLock(override)
	if BackdropTemplateMixin then
		Mixin(ItemRackMenuFrame, BackdropTemplateMixin)
	end
	ItemRackMenuFrame:SetBackdrop(
		{
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		}
	)
	if ItemRackUser.Locked == "ON" or override then
		ItemRackMenuFrame:EnableMouse(0)
		ItemRackMenuFrame:SetBackdropBorderColor(0, 0, 0, 0)
		ItemRackMenuFrame:SetBackdropColor(0, 0, 0, 0)
	else
		ItemRackMenuFrame:EnableMouse(1)
		ItemRackMenuFrame:SetBackdropBorderColor(.3, .3, .3, 1)
		ItemRackMenuFrame:SetBackdropColor(1, 1, 1, 1)
	end
	if ItemRackOptFrame then
		ItemRackOpt.ListScrollFrameUpdate()
	end
end

function ItemRack.ReflectAlpha()
	if ItemRackButton0 then
		for i = 0, 20 do
			_G["ItemRackButton" .. i]:SetAlpha(ItemRackUser.Alpha)
		end
	end
	ItemRackMenuFrame:SetAlpha(ItemRackUser.Alpha)
end

-- cloaks that force Show Cloak on while in slot 15, overriding the set's ShowCloak choice
ItemRack.AlwaysShowCloakIDs = {
	[15138] = "Onyxia Scale Cloak",
}

local function isFlaggedCloakWorn()
	local id = GetInventoryItemID("player", 15)
	return id and ItemRack.AlwaysShowCloakIDs[id] ~= nil
end

local function syncCloakVisibility()
	if isFlaggedCloakWorn() then
		if not ShowingCloak() then ShowCloak(true) end
		return
	end
	-- follow the set's ShowCloak choice: nil = leave as-is, 1 = show, 0 = hide
	local current = ItemRackUser.CurrentSet
	local set = current and ItemRackUser.Sets[current]
	if not set or set.ShowCloak == nil then return end
	if set.ShowCloak == 1 then
		if not ShowingCloak() then ShowCloak(true) end
	elseif ShowingCloak() then
		ShowCloak(false)
	end
end

function ItemRack.OnEquipmentChangedForCloak(self, event, slot)
	if slot ~= 15 then return end
	syncCloakVisibility()
end

-- PLAYER_EQUIPMENT_CHANGED only registered while ON; the immediate sync covers an already-worn cloak
function ItemRack.ReflectAlwaysShowOnyxiaCloak()
	if ItemRackSettings.AlwaysShowOnyxiaCloak == "ON" then
		ItemRackFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
		syncCloakVisibility()
	else
		ItemRackFrame:UnregisterEvent("PLAYER_EQUIPMENT_CHANGED")
	end
end

function ItemRack.ReflectMenuScale(scale)
	scale = scale or ItemRackUser.MenuScale
	ItemRackMenuFrame:SetScale(scale)
end

function ItemRack.SetFont(button)
	local item = _G[button .. "Time"]
	if not item then
		return
	end
	if ItemRackSettings.LargeNumbers == "ON" then
		item:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
		item:SetTextColor(1, .82, 0, 1)
		item:ClearAllPoints()
		item:SetPoint("CENTER", button, "CENTER")
	else
		item:SetFont("Fonts\\ARIALN.TTF", 14, "OUTLINE")
		item:SetTextColor(1, 1, 1, 1)
		item:ClearAllPoints()
		item:SetPoint("BOTTOM", button, "BOTTOM")
	end
end

function ItemRack.ReflectCooldownFont()
	for i = 0, 20 do
		ItemRack.SetFont("ItemRackButton" .. i)
	end
	local i = 1
	while _G["ItemRackMenu" .. i] do
		ItemRack.SetFont("ItemRackMenu" .. i)
		i = i+1
	end
end

--[[ Hidden menu items ]]

function ItemRack.AddHidden(id)
	if id then
		for i = 1, #(ItemRackUser.Hidden) do
			if ItemRackUser.Hidden[i] == id then
				return
			end
		end
		table.insert(ItemRackUser.Hidden, id)
	end
end

function ItemRack.RemoveHidden(id)
	for i = 1, #(ItemRackUser.Hidden) do
		if ItemRackUser.Hidden[i] == id then
			table.remove(ItemRackUser.Hidden, i)
			break
		end
	end
end

function ItemRack.IsHidden(id)
	for i = 1, #(ItemRackUser.Hidden) do
		if ItemRackUser.Hidden[i] == id then
			return true
		end
	end
	return nil
end

function ItemRack.ToggleHidden(id)
	if ItemRack.IsHidden(id) then
		ItemRack.RemoveHidden(id)
	else
		ItemRack.AddHidden(id)
	end
end

--[[ Key bindings ]]
local retryCount = 0
function ItemRack.SetSetBindings()
	if InCombatLockdown() then
		-- defer: OnLeavingCombatOrDeath retries when PLAYER_REGEN_ENABLED fires
		ItemRack.BindingsPending = 1
		return
	end
	local bindingSet = GetCurrentBindingSet()
	if not bindingSet or not (Enum.BindingSet and tContains(Enum.BindingSet, bindingSet)) then
		if retryCount < 5 then
			retryCount = retryCount + 1
			C_Timer.After(2, function()
				ItemRack.SetSetBindings()
			end)
		else
			retryCount = 0
		end
		return
	end
	retryCount = 0
	for setname, set in pairs(ItemRackUser.Sets) do
		if set.key then
			local buttonName = "ItemRack" .. UnitName("player") .. GetRealmName() .. setname
			local button = _G[buttonName] or CreateFrame("Button", buttonName, nil, "SecureActionButtonTemplate")

			button:RegisterForClicks("AnyDown", "AnyUp")
			button:SetAttribute("type", "macro")
			local macrotext = "/script ItemRack.RunSetBinding(\"" .. setname .. "\")\n"
			for slot = 16, 18 do
				if set.equip[slot] then
					local name = GetItemInfo("item:" .. set.equip[slot])
					if name then
						macrotext = macrotext .. "/equipslot [combat]" .. slot .. " " .. name .. "\n"
					end
				end
			end
			button:SetAttribute("macrotext", macrotext)
			SetBindingClick(set.key, buttonName)
		end
	end
	SaveBindings(bindingSet)
	ItemRack.BindingsPending = nil
end

function ItemRack.RunSetBinding(setname)
	if ItemRackSettings.EquipToggle == "ON" then
		ItemRack.ToggleSet(setname)
	else
		ItemRack.EquipSet(setname)
	end
end

--[[ Slash Handler ]]

function ItemRack.SlashHandler(arg1)
	if arg1 and string.match(arg1, "equip") then
		local set = string.match(arg1, "equip (.+)")
		if not set then
			ItemRack.Print("Usage: /itemrack equip set name")
			ItemRack.Print("ie: /itemrack equip pvp gear")
		else
			ItemRack.EquipSet(set)
		end
		return
	elseif arg1 and string.match(arg1, "toggle") then
		local sets = string.match(arg1, "toggle (.+)")
		if not sets then
			ItemRack.Print("Usage: /itemrack toggle set name[, second set name]")
			ItemRack.Print("ie: /itemrack toggle pvp gear, tanking set")
		else
			local set1, set2 = string.match(sets, "(.+), ?(.+)")
			if not set1 then
				ItemRack.ToggleSet(sets)
			else
				if ItemRack.IsSetEquipped(set1) then
					ItemRack.EquipSet(set2)
				else
					ItemRack.EquipSet(set1)
				end
			end
		end
		return
	end

	arg1 = string.lower(arg1)

	if arg1 == "reset" then
		ItemRack.ResetButtons()
	elseif arg1 == "reset everything" then
		ItemRack.ResetEverything()
	elseif arg1 == "lock" then
		ItemRackUser.Locked = "ON"
		ItemRack.ReflectLock()
	elseif arg1 == "unlock" then
		ItemRackUser.Locked = "OFF"
		ItemRack.ReflectLock()
	elseif arg1 == "opt" or arg1 == "options" or arg1 == "config" then
		ItemRack.ToggleOptions()
	else
		ItemRack.Print("/itemrack opt : summons options window.")
		ItemRack.Print("/itemrack equip set name : equip set 'set name'.")
		ItemRack.Print("/itemrack toggle set name[, second set] : toggles set 'set name'.")
		ItemRack.Print("/itemrack reset : resets buttons and their settings.")
		ItemRack.Print("/itemrack reset everything : wipes ItemRack to default.")
		ItemRack.Print("/itemrack lock/unlock : locks/unlocks the buttons.")
	end
end

--[[ Bank Support ]]

-- returns 1 if the set has a banked item, 0 if there is an item missing entirely, nil if item is on person
function ItemRack.MissingItems(setname)
	local missing
	if not setname or not ItemRackUser.Sets[setname] then return end
	for _, i in pairs(ItemRackUser.Sets[setname].equip) do
		if i ~= 0 and ItemRack.GetCountByID(i) == 0 then
			missing = 0
			if ItemRack.FindInBank(i) then
				return 1
			end
		end
	end
	return missing
end

-- pulls setname from bank to bags
function ItemRack.GetBankedSet(setname)
	if ItemRack.MissingItems(setname) ~= 1 or SpellIsTargeting() or GetCursorInfo() then return end
	local bag, slot, freeBag, freeSlot
	ItemRack.ClearLockList()
	for _, i in pairs(ItemRackUser.Sets[setname].equip) do
		bag, slot = ItemRack.FindInBank(i)
		if bag then
			freeBag, freeSlot = ItemRack.FindSpace()
			if freeBag then
				C_Container.PickupContainerItem(bag, slot)
				C_Container.PickupContainerItem(freeBag, freeSlot)
			else
				ItemRack.Print("Not enough room in bags to pull all items from '" .. setname .. "'.")
				return
			end
		end
	end
end

-- pushes setname from bags/worn to bank
function ItemRack.PutBankedSet(setname)
	if SpellIsTargeting() or GetCursorInfo() then return end
	local inv, bag, slot, freeBag, freeSlot
	ItemRack.ClearLockList()
	for _, i in pairs(ItemRackUser.Sets[setname].equip) do
		if i ~= 0 then
			freeBag, freeSlot = ItemRack.FindBankSpace()
			if freeBag then
				inv, bag, slot = ItemRack.FindItem(i)
				if inv then
					PickupInventoryItem(inv)
				elseif bag then
					C_Container.PickupContainerItem(bag, slot)
				end
				if CursorHasItem() then
					C_Container.PickupContainerItem(freeBag, freeSlot)
				end
			else
				ItemRack.Print("Not enough room in bank to store all items from '" .. setname .. "'.")
				return
			end
		end
	end
end

function ItemRack.ResetEverything()
	StaticPopupDialogs["ItemRackCONFIRMRESET"] = {
		text = "This will restore ItemRack to its default state, wiping all sets, buttons, events and settings.\nThe UI will be reloaded. Continue?",
		button1 = "Yes", button2 = "No", timeout = 0, hideOnEscape = 1, showAlert = 1,
		OnAccept = function() ItemRackUser = nil ItemRackSettings = nil ItemRackItems = nil ItemRackEvents = nil ReloadUI() end
	}
	StaticPopup_Show("ItemRackCONFIRMRESET")
end

-- if cpu profiling on, this will add a page to TinyPad with each ItemRack.func()'s time
function ItemRack.ProfileFuncs()
	if TinyPadPages then
		UpdateAddOnCPUUsage()
		local total = 0
		local t = {}
		local whole, decimal
		for i in pairs(ItemRack) do
			if type(ItemRack[i]) == "function" then
				whole = GetFunctionCPUUsage(ItemRack[i])
				decimal = whole - math.floor(whole)
				whole = math.floor(whole)
				table.insert(t, string.format("%04d.%02d %s", whole, decimal, i))
			end
		end
		table.sort(t)
		local info = "ItemRack profile " .. date() .. " " .. UnitName("player") .. "\n"
		for i = 1, #(t) do
			info = info .. t[i] .. "\n"
		end
		table.insert(TinyPadPages, info)
	end
end

-- current set's table when EnablePerSetQueues is on, otherwise the global one
local function perSetTable(key, global)
	if ItemRackUser.EnablePerSetQueues ~= "ON" then
		return global
	end
	local currentSet = ItemRackUser.CurrentSet and ItemRackUser.Sets[ItemRackUser.CurrentSet]
	if not currentSet then
		return global
	end
	currentSet[key] = currentSet[key] or {}
	return currentSet[key]
end

function ItemRack.GetQueues()
	return perSetTable("Queues", ItemRackUser.Queues)
end

function ItemRack.GetQueuesEnabled()
	return perSetTable("QueuesEnabled", ItemRackUser.QueuesEnabled)
end
