-- CurrentSet still names the previous set during EquipSet, so queues resolve from the set being equipped
local function setQueueSources(setname)
	if ItemRackUser.EnablePerSetQueues == "ON" and setname and ItemRackUser.Sets[setname] then
		local set = ItemRackUser.Sets[setname]
		return set.Queues, set.QueuesEnabled
	end
	return ItemRackUser.Queues, ItemRackUser.QueuesEnabled
end

-- a keep flag suspends the auto queue, so a slot involving a keep item is not queue-managed
local function keepFlagged(id)
	local cfg = id and ItemRackItems[ItemRack.GetIRString(id, true)]
	return cfg and cfg.keep
end

local function wornIsValidQueueAlternative(setname, slot)
	if ItemRackSettings.KeepWornIfQueued ~= "ON" then return end
	if ItemRackUser.EnableQueues ~= "ON" then return end
	-- internal sets carry forced restores; keep-worn must not suppress them
	if string.match(setname, "^~") then return end
	if keepFlagged(ItemRackUser.Sets[setname].equip[slot]) then return end
	local queues, enabled = setQueueSources(setname)
	if not queues or not enabled then return end
	if enabled[slot] ~= true then return end
	local list = queues[slot]
	if not list then return end
	local worn = ItemRack.GetID(slot)
	if not worn or worn == 0 then return end
	if keepFlagged(worn) then return end
	for i = 1, #list do
		-- UpdateIRString normalizes only level/spec, so a different enchant still fails the match
		if list[i] ~= 0 and worn == ItemRack.UpdateIRString(list[i]) then
			return true
		end
	end
end

-- exact compare treats trailing-colon variants as different items; the resulting self-swap corrupts the set's restore pointer
local function wornIsIntendedItem(worn, wanted)
	if worn == wanted then return true end
	if type(worn) ~= "string" or type(wanted) ~= "string" then return false end
	return (ItemRack.UpdateIRString(worn):gsub(":+$", "")) == (ItemRack.UpdateIRString(wanted):gsub(":+$", ""))
end

ItemRack.SwapList = {} -- [slot] = IR id to swap in (0 = empty the slot)
ItemRack.PendingSwap = {} -- [slot] = {want,old}; read at combat end to catch a swap the game silently rejected
ItemRack.AbortSwap = nil -- index into AbortReasons
ItemRack.AbortReasons = { "Not enough room.", "Something is on the cursor.", "In spell targeting mode.", "Another swap is in progress." }

ItemRack.SetsWaiting = {} -- { {setname, equipFunc}, ... }

function ItemRack.ProcessSetsWaiting()
	local entry = table.remove(ItemRack.SetsWaiting, 1)
	entry[2](entry[1])
end

function ItemRack.AddSetToSetsWaiting(setwaiting, whichequip)
	local wait = ItemRack.SetsWaiting
	for i = 1, #wait do
		if wait[i][1] == setwaiting and wait[i][2] == whichequip then
			return
		end
	end
	wait[#wait + 1] = { setwaiting, whichequip }
end

function ItemRack.EquipSet(setname)
	if not setname or not ItemRackUser.Sets[setname] then
		ItemRack.Print("Set \"" .. tostring(setname) .. "\" doesn't exist.")
		return
	end
	if ItemRack.NowCasting or ItemRack.NowShooting or ItemRack.NowSwingQueued or ItemRack.AnythingLocked() then
		ItemRack.AddSetToSetsWaiting(setname, ItemRack.EquipSet)
		return
	end
	local set = ItemRackUser.Sets[setname]
	local swap = ItemRack.SwapList
	wipe(swap)
	local couldntFind
	for i in pairs(set.equip) do
		-- this pass's decision for the slot supersedes any pending rejected-swap intent
		ItemRack.PendingSwap[i] = nil
		if not wornIsIntendedItem(ItemRack.GetID(i), set.equip[i]) and not wornIsValidQueueAlternative(setname, i) then
			local inv, bag = ItemRack.FindItem(set.equip[i])
			if not inv and not bag then
				couldntFind = (couldntFind or "Could not find: ") .. "[" .. tostring(ItemRack.GetInfoByID(set.equip[i])) .. "] "
			elseif inv ~= i then
				swap[i] = set.equip[i]
			end
		end
	end
	ItemRack.Print(couldntFind) -- Print(nil) is a no-op

	if not next(swap) then
		-- nothing to move, but UnequipSet still needs a handback target
		if not string.match(setname, "^~") and ItemRackUser.CurrentSet ~= setname then
			set.oldset = ItemRackUser.CurrentSet
		end
		ItemRack.EndSetSwap(setname)
		return
	end

	-- a repair pass on the current set must keep restore entries for slots it doesn't touch
	if set.old and not string.match(setname, "^~") and ItemRackUser.CurrentSet ~= setname then
		wipe(set.old)
		set.oldset = ItemRackUser.CurrentSet
	end

	-- UnitAffectingCombat flips before InCombatLockdown; a swap in that window hits ADDON_ACTION_BLOCKED
	if InCombatLockdown() or UnitAffectingCombat("player") or ItemRack.IsPlayerReallyDead() then
		for i in pairs(swap) do
			-- direct assign: AddToCombatQueue's toggle would drop the entry on event re-evaluation
			ItemRack.CombatQueue[i] = swap[i]
			-- no origin: ProcessAutoQueue must not cancel set-deferred entries
			ItemRack.AutoQueueOrigin[i] = nil
			swap[i] = nil
			if set.old then
				set.old[i] = ItemRack.GetID(i)
				ItemRack.CombatSet = setname
			elseif set.oldset then
				ItemRack.CombatSet = set.oldset
			end
		end
		ItemRack.UpdateCombatQueue()
	end
	if not next(swap) then
		return
	end

	if set.ShowHelm ~= nil then
		ShowHelm(set.ShowHelm == 1)
	end
	if set.ShowCloak ~= nil then
		ShowCloak(set.ShowCloak == 1)
	end

	-- snapshot worn items so combat-end can tell a rejected swap from a later manual change
	wipe(ItemRack.PendingSwap)
	for i in pairs(swap) do
		if swap[i] ~= 0 then
			ItemRack.PendingSwap[i] = { want = swap[i], old = ItemRack.GetID(i) }
		end
	end

	ItemRack.IterateSwapList(setname)
	if not next(swap) then
		ItemRack.EndSetSwap(setname)
		return
	end

	-- ITEM_LOCK_CHANGED drives the remaining swaps via LockChangedDuringSetSwap
	ItemRack.SetSwapping = setname
end

function ItemRack.AnythingLocked()
	for i = 0, 19 do
		if IsInventoryItemLocked(i) then
			return 1
		end
	end
	for i = 0, 4 do
		for j = 1, C_Container.GetContainerNumSlots(i) do
			local info = C_Container.GetContainerItemInfo(i, j)
			if info and info.isLocked then
				return 1
			end
		end
	end
end

function ItemRack.LockChangedDuringSetSwap()
	if not ItemRack.AnythingLocked() then
		local setname = ItemRack.SetSwapping
		ItemRack.SetSwapping = nil
		ItemRack.IterateSwapList(setname)
		ItemRack.EndSetSwap(setname)
	end
end

local function recordOld(set, slot)
	if set.old then
		set.old[slot] = ItemRack.GetID(slot)
	end
end

function ItemRack.IterateSwapList(setname)
	local set = ItemRackUser.Sets[setname]
	local swap = ItemRack.SwapList

	ItemRack.AbortSwap = nil
	ItemRack.ClearLockList()

	local skip
	for i = 0, 19 do
		if skip or ItemRack.AbortSwap then
			skip = nil
		elseif swap[i] then
			if swap[i] == 0 then
				local bag, slot = ItemRack.FindSpace()
				if bag then
					recordOld(set, i)
					ItemRack.MoveItem(i, nil, bag, slot)
					swap[i] = nil
				else
					ItemRack.AbortSwap = 1
				end
			else
				local inv, bag, slot = ItemRack.FindItem(swap[i], 1)
				if bag then
					if select(3, ItemRack.GetInfoByID(swap[i])) == "INVTYPE_2HWEAPON" then
						recordOld(set, i)
						recordOld(set, i+1)
						local stashed = true
						if GetInventoryItemLink("player", 17) then
							local freeBag, freeSlot = ItemRack.FindSpace()
							if freeBag then
								ItemRack.MoveItem(17, nil, freeBag, freeSlot)
							else
								ItemRack.AbortSwap = 1
								stashed = false
							end
						end
						if stashed then
							ItemRack.MoveItem(bag, slot, 16, nil)
							-- equipping a 2H empties the off-hand too; drop its pending entry
							swap[i] = nil
							swap[i+1] = nil
							skip = 1
						end
					else
						recordOld(set, i)
						ItemRack.MoveItem(bag, slot, i, nil)
						swap[i] = nil
					end
				elseif inv == (i+1) and ItemRack.SameID(swap[i+1], ItemRack.GetID(i)) then
					-- the two slots hold each other's wanted items; one move settles both
					recordOld(set, i)
					recordOld(set, i+1)
					ItemRack.MoveItem(i, nil, i+1, nil)
					swap[i] = nil
					swap[i+1] = nil
					skip = 1
				end
			end
		end
	end
	if ItemRack.AbortSwap then
		ItemRack.ClearLockList()
		if ItemRack.AbortSwap == 1 then
			UIErrorsFrame:AddMessage("ItemRack: bags full, swap stopped", 1, .3, .3, 1, UIERRORS_HOLD_TIME)
		else
			ItemRack.Print("Swap stopped. " .. (ItemRack.AbortReasons[ItemRack.AbortSwap] or ""))
		end
	end
	if CursorHasItem() then
		ClearCursor()
	end
end

function ItemRack.EndSetSwap(setname)
	ItemRack.SetSwapping = nil
	if setname then
		if not string.match(setname, "^~") then
			ItemRackUser.CurrentSet = setname
			ItemRack.UpdateCurrentSet()
		elseif ItemRackUser.Sets[setname].oldset then
			ItemRackUser.CurrentSet = ItemRackUser.Sets[setname].oldset
			ItemRackUser.Sets[setname].oldset = nil
			ItemRack.UpdateCurrentSet()
		end
		if ItemRackOptFrame and ItemRackOptFrame:IsVisible() then
			ItemRackOpt.ChangeEditingSet()
		end
		ItemRack.UpdateCombatQueue() -- per-set queues tie the button gear icon to the set
	end
end

-- a nil slot means the bag argument is an inventory slot id
function ItemRack.MoveItem(fromBag, fromSlot, toBag, toSlot)
	local fromInfo = fromSlot and C_Container.GetContainerItemInfo(fromBag, fromSlot)
	local toInfo = toSlot and C_Container.GetContainerItemInfo(toBag, toSlot)
	local abort
	if CursorHasItem() then
		abort = 2
	elseif SpellIsTargeting() then
		abort = 3
	elseif (not fromSlot and IsInventoryItemLocked(fromBag)) or (not toSlot and IsInventoryItemLocked(toBag)) then
		abort = 4
	elseif (fromInfo and fromInfo.isLocked) or (toInfo and toInfo.isLocked) then
		abort = 4
	end
	if abort then
		ItemRack.AbortSwap = abort
		return
	end
	if fromSlot then
		C_Container.PickupContainerItem(fromBag, fromSlot)
	else
		PickupInventoryItem(fromBag)
	end
	if toSlot then
		C_Container.PickupContainerItem(toBag, toSlot)
	else
		if toBag == INVSLOT_AMMO then -- workaround for classic ammo slot weirdness
			toBag = INVSLOT_RANGED
		end
		PickupInventoryItem(toBag)
	end
	-- Displaced item sits on the cursor after the two pickups; put it back in the source slot.
	if CursorHasItem() then
		if fromSlot then
			C_Container.PickupContainerItem(fromBag, fromSlot)
		else
			PickupInventoryItem(fromBag)
		end
	end
	-- Cursor still holding means the swap did not complete (lock, GCD, full bag).
	if CursorHasItem() then
		ClearCursor()
		ItemRack.AbortSwap = 4
	end
end

function ItemRack.IsSetEquipped(setname, exact)
	if setname and ItemRackUser.Sets[setname] then
		local set = ItemRackUser.Sets[setname].equip
		for i in pairs(set) do
			local id = ItemRack.GetID(i)
			if (exact and set[i] ~= id) or (not exact and not ItemRack.SameID(set[i], id)) then
				return false
			end
		end
		return true
	end
end

function ItemRack.UnequipSet(setname)
	if not (setname and ItemRackUser.Sets[setname]) then return end
	local set = ItemRackUser.Sets[setname]
	local hasOld = set.old and next(set.old)
	if not hasOld and not set.oldset then
		return
	end
	if ItemRack.NowCasting or ItemRack.NowShooting or ItemRack.NowSwingQueued or ItemRack.AnythingLocked() then
		ItemRack.AddSetToSetsWaiting(setname, ItemRack.UnequipSet)
		return
	end
	-- consume the restore target upfront, else the buff-event gate re-fires UnequipSet every repoll tick
	local prevSet = set.oldset
	set.oldset = nil
	if hasOld then
		local unequip = ItemRackUser.Sets["~Unequip"].equip
		wipe(unequip)
		for i in pairs(set.old) do
			unequip[i] = set.old[i]
		end
		ItemRackUser.Sets["~Unequip"].oldset = prevSet
		wipe(set.old)
		ItemRack.EquipSet("~Unequip")
	else
		-- no per-slot record (items were already worn); hand control back to the previous set
		ItemRack.EquipSet(prevSet)
	end
end

function ItemRack.ToggleSet(setname, exact)
	if ItemRack.IsSetEquipped(setname, exact) then
		ItemRack.UnequipSet(setname)
	else
		ItemRack.EquipSet(setname)
	end
end
