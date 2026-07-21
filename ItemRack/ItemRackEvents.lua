-- seconds of speed==0 a Moving event tolerates; keeps chunked movement from oscillating the swap
ItemRack.MovingStopThrottle = 3

-- bump to redeploy default events to existing users
ItemRack.EventsVersion = 24

ItemRack.DefaultEvents = {
	["PVP"] = {
		Type = "Zone",
		Unequip = 1,
		Zones = {
			["Alterac Valley"] = 1,
			["Arathi Basin"] = 1,
			["Warsong Gulch"] = 1,
		}
	},
	["City"] = {
		Type = "Zone",
		Unequip = 1,
		Zones = {
			["Ironforge"] = 1,
			["Stormwind City"] = 1,
			["Darnassus"] = 1,
			["Orgrimmar"] = 1,
			["Thunder Bluff"] = 1,
			["Undercity"] = 1,
		}
	},
	["Mounted"] = { Type = "Buff", Unequip = 1, Anymount = 1 },
	["Riding + Moving"] = { Type = "Buff", Unequip = 1, Anymount = 1, Moving = 1 },
	["Drinking"] = { Type = "Buff", Unequip = 1, Buff = "Drink" },

	["Evocation"] = { Class = "MAGE", Type = "Buff", Unequip = 1, Buff = "Evocation" },

	["Warrior Battle"] = { Class = "WARRIOR", Type = "Stance", Stance = 1 },
	["Warrior Defensive"] = { Class = "WARRIOR", Type = "Stance", Stance = 2 },
	["Warrior Berserker"] = { Class = "WARRIOR", Type = "Stance", Stance = 3 },

	["Priest Shadowform"] = { Class = "PRIEST", Type = "Stance", Unequip = 1, Stance = 1 },

	["Druid Humanoid"] = { Class = "DRUID", Type = "Stance", Stance = 0 },
	["Druid Bear"] = { Class = "DRUID", Type = "Stance", Stance = 1 },
	["Druid Aquatic"] = { Class = "DRUID", Type = "Stance", Stance = 2 },
	["Druid Cat"] = { Class = "DRUID", Type = "Stance", Stance = 3 },
	["Druid Travel"] = { Class = "DRUID", Type = "Stance", Stance = 4 },
	["Druid Moonkin"] = { Class = "DRUID", Type = "Stance", Stance = "Moonkin Form" },

	["Rogue Stealth"] = { Class = "ROGUE", Type = "Stance", Unequip = 1, Stance = 1 },

	["Shaman Ghostwolf"] = { Class = "SHAMAN", Type = "Stance", Unequip = 1, Stance = 1 },

	["Swimming"] = {
		["Trigger"] = "SPELL_UPDATE_USABLE",
		["Type"] = "Script",
		["Script"] = "local set = \"Name of set\"\nlocal now = IsSwimming()\nif now == IRSwimmingState then return end\nIRSwimmingState = now\nif now and not IsSetEquipped(set) then\n  EquipSet(set)\nelseif not now and IsSetEquipped(set) then\n  UnequipSet(set)\nend\n--[[Equips a set while swimming, unequips on leaving water. Triggered by SPELL_UPDATE_USABLE (fires on water-entry/exit because swim-restricted abilities flip usability). The IRSwimmingState short-circuit drops unrelated fires to one IsSwimming() call.]]",
	},

	["Buffs Gained"] = {
		Type = "Script",
		Trigger = "UNIT_AURA",
		Script = "local unit = ...\nif unit == \"player\" then\n  IRScriptBuffs = IRScriptBuffs or {}\n  local buffs = IRScriptBuffs\n  for name in pairs(buffs) do\n    if not AuraUtil.FindAuraByName(name, \"player\") then\n      buffs[name] = nil\n    end\n  end\n  AuraUtil.ForEachAura(\"player\", \"HELPFUL\", nil, function(name)\n    if name and not buffs[name] then\n      ItemRack.Print(\"Gained buff: \" .. name)\n      buffs[name] = 1\n    end\n  end)\nend\n--[[For script demonstration purposes. Doesn't equip anything just informs when a buff is gained.]]",
	},

	["After Cast"] = {
		Type = "Script",
		Trigger = "UNIT_SPELLCAST_SUCCEEDED",
		Script = "local spell = \"Name of spell\"\nlocal set = \"Name of set\"\nlocal unit, _, spellID = ...\nif unit == \"player\" and spellID and GetSpellInfo(spellID) == spell then\n  EquipSet(set)\nend\n\n--[[This event will equip \"Name of set\" when \"Name of spell\" has finished casting.  Change the names for your own use.]]",
	},

	["Nefarian's Lair"] = {
		Type = "Zone",
		Unequip = 1,
		Zones = {
			["Nefarian's Lair"] = 1,
		}
	},
}

-- resetDefault to reload/update default events, resetAll to wipe all events and recreate them
function ItemRack.LoadEvents(resetDefault, resetAll)
	local _, playerClass = UnitClass("player")
	local version = tonumber(ItemRackSettings.EventsVersion) or 0

	if ItemRack.EventsVersion > version then
		resetDefault = 1 -- custom events stay intact
		ItemRackSettings.EventsVersion = ItemRack.EventsVersion
	end

	if not ItemRackUser.Events or resetAll then
		ItemRackUser.Events = {
			Enabled = {}, -- [eventName] = true
			Set = {} -- [eventName] = setname
		}
	end

	if not ItemRackEvents or resetAll then
		ItemRackEvents = {}
	end

	if resetDefault or resetAll then
		for i in pairs(ItemRack.DefaultEvents) do
			local eventClass = ItemRack.DefaultEvents[i].Class
			if not eventClass or eventClass == playerClass then
				ItemRack.CopyDefaultEvent(i)
			end
		end
	end

	ItemRack.CleanupEvents()
	if ItemRackOpt then
		ItemRackOpt.PopulateEventList()
	end
end

function ItemRack.CopyDefaultEvent(eventName)
	ItemRackEvents[eventName] = {}
	local event = ItemRackEvents[eventName]
	local default = ItemRack.DefaultEvents[eventName]

	for i in pairs(default) do
		if type(default[i]) ~= "table" then
			event[i] = default[i]
		else
			-- events nest at most one table deep (Zones)
			event[i] = {}
			for j in pairs(default[i]) do
				event[i][j] = default[i][j]
			end
		end
	end
end

-- clear sets of deleted events, clear events with deleted sets
function ItemRack.CleanupEvents()
	local event = ItemRackUser.Events

	for i in pairs(event.Set) do
		if not ItemRackEvents[i] then
			event.Set[i] = nil
			event.Enabled[i] = nil
		end
		if not ItemRackUser.Sets[event.Set[i]] then
			event.Set[i] = nil
			event.Enabled[i] = nil
		end
	end

	for i in pairs(event.Enabled) do
		if not ItemRackEvents[i] then
			event.Set[i] = nil
			event.Enabled[i] = nil
		end
		if event.Enabled[i] == false then
			event.Enabled[i] = nil
		end
	end
end

function ItemRack.ResetEvents(resetDefault, resetAll)
	if not resetDefault and not resetAll then
		StaticPopupDialogs["ItemRackConfirmResetEvents"] = {
			text = "Do you want to restore just Default events, or wipe All events and restore to default?",
			button1 = "Default", button2 = "Cancel", button3 = "All", timeout = 0, hideOnEscape = 1, whileDead = 1,
			OnAccept = function() ItemRack.ResetEvents(1) end,
			OnAlt = function() ItemRack.ResetEvents(1, 1) end,
		}
		StaticPopup_Show("ItemRackConfirmResetEvents")
	else
		ItemRack.LoadEvents(resetDefault, resetAll)
	end
end

function ItemRack.InitEvents()
	ItemRack.LoadEvents()

	-- [eventName] = GetTime() when speed first hit 0 while equipped; drives the stop-throttle
	ItemRack.MovingStopPending = {}

	ItemRack.CreateTimer("EventsBuffTimer", ItemRack.ProcessBuffEvent, .15)
	ItemRack.CreateTimer("EventsZoneTimer", ItemRack.ProcessZoneEvent, .16)
	ItemRack.CreateTimer("RepollBuffEvents", ItemRack.RepollBuffEvents, .1, 1)

	-- gear overlay on the set button while any event is active
	ItemRackButton20Queue:SetTexture("Interface\\AddOns\\ItemRack\\ItemRackGear")

	ItemRack.RegisterEvents()
end

local function registerOnce(frame, event)
	if not frame:IsEventRegistered(event) then
		frame:RegisterEvent(event)
	end
end

function ItemRack.RegisterEvents()
	local frame = ItemRackEventProcessingFrame
	frame:UnregisterAllEvents()
	ItemRack.StopTimer("RepollBuffEvents")
	ItemRack.ReflectEventsRunning()
	if ItemRackUser.EnableEvents == "OFF" then
		return
	end
	local events = ItemRackEvents
	for eventName in pairs(ItemRackUser.Events.Enabled) do
		local eventType = events[eventName].Type
		if eventType == "Buff" then
			registerOnce(frame, "UNIT_AURA")
		elseif eventType == "Stance" then
			registerOnce(frame, "UPDATE_SHAPESHIFT_FORM")
		elseif eventType == "Zone" then
			registerOnce(frame, "ZONE_CHANGED_NEW_AREA")
			registerOnce(frame, "ZONE_CHANGED_INDOORS")
		elseif eventType == "Script" then
			registerOnce(frame, events[eventName].Trigger)
		end
	end
	ItemRack.StartTimer("RepollBuffEvents")

	ItemRack.ProcessStanceEvent()
	ItemRack.ProcessZoneEvent()
	ItemRack.ProcessBuffEvent()
end

function ItemRack.ToggleEvents()
	ItemRackUser.EnableEvents = ItemRackUser.EnableEvents == "ON" and "OFF" or "ON"
	UIErrorsFrame:AddMessage("ItemRack events " .. (ItemRackUser.EnableEvents == "ON" and "enabled" or "disabled"), .2, .7, .9, 1, UIERRORS_HOLD_TIME)
	if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
		ItemRackOpt.ListScrollFrameUpdate()
	end
	ItemRack.RegisterEvents()
end

-- false, not nil: the first poll runs before PLAYER_ENTERING_WORLD with IsMounted()==false
local _lastStateMounted = false

function ItemRack.ProcessingFrameOnEvent(self, event, ...)
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	local startBuff, startZone, startStance
	local arg1 = ...

	-- mount changes swap on the same frame instead of waiting out the coalescer or the repoll
	local mountStateChanged = false
	if event == "UNIT_AURA" and arg1 == "player" then
		local isPlayerMounted = IsMounted() and not UnitOnTaxi("player")
		if isPlayerMounted ~= _lastStateMounted then
			_lastStateMounted = isPlayerMounted
			mountStateChanged = true
		end
	end

	for eventName in pairs(enabled) do
		local eventType = events[eventName].Type
		if event == "UNIT_AURA" and eventType == "Buff" and arg1 == "player" then
			startBuff = 1
		elseif event == "UPDATE_SHAPESHIFT_FORM" and eventType == "Stance" then
			startStance = 1
		elseif event == "ZONE_CHANGED_NEW_AREA" and eventType == "Zone" then
			startZone = 1
		-- subzone changes only matter inside raid instances (boss-room transitions)
		elseif event == "ZONE_CHANGED_INDOORS" and eventType == "Zone" and select(2, IsInInstance()) == "raid" then
			startZone = 1
		elseif eventType == "Script" and events[eventName].Trigger == event then
			-- compile once per source change; cached on a session-local table (not the SV)
			ItemRack.ScriptCache = ItemRack.ScriptCache or {}
			local entry = ItemRack.ScriptCache[eventName]
			local src = events[eventName].Script
			if not entry or entry.src ~= src then
				local fn, err = loadstring(src or "")
				entry = { src = src, fn = fn, err = err }
				ItemRack.ScriptCache[eventName] = entry
				if not fn and err then
					UIErrorsFrame:AddMessage("ItemRack script '" .. eventName .. "': " .. err, 1, .2, .2, 1, UIERRORS_HOLD_TIME)
				end
			end
			if entry.fn then
				pcall(entry.fn, ...)
			end
		end
	end
	if mountStateChanged then
		ItemRack.ProcessBuffEvent()
		startBuff = nil -- handled synchronously, skip the 0.15s coalescer
	end
	if startStance then
		ItemRack.ProcessStanceEvent()
	end
	if startBuff then
		ItemRack.StartTimer("EventsBuffTimer")
	end
	if startZone then
		ItemRack.StartTimer("EventsZoneTimer")
	end
end

function ItemRack.GetStanceNumber(name)
	if tonumber(name) then
		return name
	end
	for i = 1, GetNumShapeshiftForms() do
		if name == select(2, GetShapeshiftFormInfo(i)) then
			return i
		end
	end
end

local function eventBlockedByInstance(event)
	if event.NotInPVP then
		local _, instanceType = IsInInstance()
		if instanceType == "arena" or instanceType == "pvp" then
			return true
		end
	end
	if event.NotInPVE then
		local _, instanceType = IsInInstance()
		if instanceType == "party" or instanceType == "raid" then
			return true
		end
	end
end

function ItemRack.ProcessStanceEvent()
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents

	local currentStance = GetShapeshiftForm()
	local setToEquip, setToUnequip

	for eventName in pairs(enabled) do
		local event = events[eventName]
		if event.Type == "Stance" and not eventBlockedByInstance(event) then
			local stance = ItemRack.GetStanceNumber(event.Stance)
			local setname = ItemRackUser.Events.Set[eventName]
			if stance == currentStance and not ItemRack.IsSetEquipped(setname) then
				setToEquip = setname
			end
			if stance ~= currentStance and event.Unequip and ItemRack.IsSetEquipped(setname) then
				setToUnequip = setname
			end
		end
	end
	if setToUnequip then
		ItemRack.UnequipSet(setToUnequip)
	end
	if setToEquip then
		ItemRack.EquipSet(setToEquip)
	end
end

function ItemRack.ProcessZoneEvent()
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents

	local currentZone = GetRealZoneText()
	local currentSubZone = GetSubZoneText()
	local setToEquip, setToUnequip

	for eventName in pairs(enabled) do
		local event = events[eventName]
		if event.Type == "Zone" then
			local setname = ItemRackUser.Events.Set[eventName]
			local inZone = event.Zones[currentZone] or event.Zones[currentSubZone]
			if inZone and not ItemRack.IsSetEquipped(setname) then
				setToEquip = setname
			elseif not inZone and event.Unequip and ItemRack.IsSetEquipped(setname) then
				setToUnequip = setname
			end
		end
	end
	if setToUnequip then
		ItemRack.UnequipSet(setToUnequip)
	end
	if setToEquip then
		ItemRack.EquipSet(setToEquip)
	end
end

-- the 10Hz tick is the sole source of movement state for Moving events; mount on/off stays on the UNIT_AURA path
function ItemRack.RepollBuffEvents()
	if UnitIsDeadOrGhost("player") or ItemRackUser.EnableEvents == "OFF" then
		return
	end

	local pending = ItemRack.MovingStopPending
	local events = ItemRackEvents
	for eventName in pairs(ItemRackUser.Events.Enabled) do
		local ev = events[eventName]
		if ev.Type == "Buff" and (ev.Moving or pending[eventName]) then
			ItemRack.ProcessBuffEvent()
			return
		end
	end
end

function ItemRack.ProcessBuffEvent()
	local enabled = ItemRackUser.Events.Enabled
	local events = ItemRackEvents
	local pending = ItemRack.MovingStopPending

	for eventName in pairs(enabled) do
		local event = events[eventName]
		if event.Type == "Buff" and not eventBlockedByInstance(event) then
			local setname = ItemRackUser.Events.Set[eventName]
			local isSetEquipped = ItemRack.IsSetEquipped(setname)

			local primary
			if event.Anymount then
				primary = IsMounted() and not UnitOnTaxi("player")
			else
				primary = AuraUtil.FindAuraByName(event.Buff, "player")
			end

			local buff
			if event.Moving then
				-- stops shorter than MovingStopThrottle keep the set on; standing still never equips it
				if not primary then
					buff = false
					pending[eventName] = nil
				elseif GetUnitSpeed("player") > 0 then
					buff = true
					pending[eventName] = nil
				elseif isSetEquipped then
					pending[eventName] = pending[eventName] or GetTime()
					buff = (GetTime() - pending[eventName]) < ItemRack.MovingStopThrottle
				else
					buff = false
				end
			else
				buff = primary
				pending[eventName] = nil
			end

			if buff and not isSetEquipped then
				ItemRack.EquipSet(setname)
			-- CurrentSet catches sets with diverged slots (mid-ride queue swaps, keep-worn) that isSetEquipped misses
			elseif not buff and (isSetEquipped or ItemRackUser.CurrentSet == setname) and event.Unequip then
				local set = ItemRackUser.Sets[setname]
				-- without a restore target UnequipSet is a no-op the repoll would re-fire forever
				if (set.old and next(set.old)) or set.oldset then
					ItemRack.UnequipSet(setname)
				end
			end
		end
	end
end

local prevIcon, prevText
function ItemRack.ReflectEventsRunning()
	if ItemRackUser.EnableEvents == "ON" and next(ItemRackUser.Events.Enabled) then
		if ItemRackUser.Buttons[20] then
			ItemRackButton20Queue:Show()
		end
		prevIcon = ItemRack.Broker.icon
		prevText = ItemRack.Broker.text
		ItemRack.Broker.icon = [[Interface\AddOns\ItemRack\ItemRackGear]]
		ItemRack.Broker.text = "..."
	else
		if ItemRackUser.Buttons[20] then
			ItemRackButton20Queue:Hide()
		end
		if prevIcon then
			ItemRack.Broker.icon = prevIcon
			ItemRack.Broker.text = prevText
		end
	end
end
