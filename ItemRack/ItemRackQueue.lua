-- exact in-game aura names; equipment changes fail while one is active
ItemRack.QueueBlockingAuras = {
	{ name = "Transporter Malfunction", filter = "HARMFUL" },
}

local function autoQueueBlocked()
	if SpellIsTargeting() or CastingInfo() or ChannelInfo() or ItemRack.NowShooting or ItemRack.NowSwingQueued then
		return true
	end
	local blockers = ItemRack.QueueBlockingAuras
	for i = 1, #blockers do
		if AuraUtil.FindAuraByName(blockers[i].name, "player", blockers[i].filter) then
			return true
		end
	end
end

function ItemRack.PeriodicQueueCheck()
	-- backstop for a missed cast-end event (Aimed Shot is 3s + slack)
	if ItemRack.NowShooting and GetTime() - ItemRack.NowShootingStart > 5 then
		ItemRack.NowShooting = nil
		ItemRack.NowShootingStart = nil
		ItemRack.ProcessCombatQueue()
		if #ItemRack.SetsWaiting > 0 and not ItemRack.AnythingLocked() then
			ItemRack.ProcessSetsWaiting()
		end
	end
	if ItemRackUser.EnableQueues ~= "ON" then return end
	if autoQueueBlocked() then return end
	for slot, enabled in pairs(ItemRack.GetQueuesEnabled()) do
		if enabled == true then
			ItemRack.ProcessAutoQueue(slot)
		end
	end
end

function ItemRack.ItemNearReady(id)
	local start, duration = C_Container.GetItemCooldown(id)
	if not tonumber(start) then return end -- can be nil shortly after a loading screen
	return start == 0 or math.max(start + duration - GetTime(), 0) <= 30
end

-- returns true when the equipped item should be kept (no swap considered)
local function reflectEquippedState(icon, baseID, start, duration)
	local buff = GetItemSpell(baseID)
	if buff and AuraUtil.FindAuraByName(buff, "player") then
		icon:SetDesaturated(true)
		return true
	end
	local cfg = ItemRackItems[baseID]
	if cfg then
		if cfg.keep then
			icon:SetVertexColor(1, .5, .5)
			return true
		end
		if cfg.delay and start > 0 then
			local timeLeft = math.max(start + duration - GetTime(), 0)
			if timeLeft > 30 and timeLeft <= cfg.delay then
				icon:SetDesaturated(true)
				return true
			end
		end
	end
	icon:SetDesaturated(false)
	icon:SetVertexColor(1, 1, 1)
end

function ItemRack.ProcessAutoQueue(slot)
	if IsInventoryItemLocked(slot) then return end

	local start, duration, enable = GetInventoryItemCooldown("player", slot)
	local baseID = ItemRack.GetIRString(GetInventoryItemLink("player", slot), true, true)

	local icon = _G["ItemRackButton" .. slot .. "Queue"]
	if reflectEquippedState(icon, baseID, start, duration) then return end

	local list = ItemRack.GetQueues()[slot]
	if not list then return end

	-- entries without a matching origin (user clicks, set-deferred swaps) are not the auto-queue's to touch
	local queued = ItemRack.CombatQueue[slot]
	local origin = ItemRack.AutoQueueOrigin[slot]
	if queued and queued ~= origin then return end

	-- cancel a stale auto-queue entry once the equipped item is near ready again, else it sits until combat ends
	local ready = ItemRack.ItemNearReady(baseID)
	if ready and queued and queued == origin then
		ItemRack.CombatQueue[slot] = nil
		ItemRack.AutoQueueOrigin[slot] = nil
		ItemRack.UpdateCombatQueue()
	end

	-- queue entries are full IR ids; ranking compares baseIDs
	for i = 1, #list do
		local entry = list[i]
		local candidate = ItemRack.GetIRString(entry, true)
		if ready and candidate == baseID then
			break -- equipped item is already the first ready queue entry
		end
		local cfg = ItemRackItems[candidate]
		local takesPriority = not ready or enable == 0 or (cfg and cfg.priority)
		if takesPriority and ItemRack.ItemNearReady(candidate) then
			local count = GetItemCount(candidate)
			local onlyWornCopy = count == 1 and IsEquippedItem(candidate)
			if count > 0 and not onlyWornCopy and ItemRack.FindItemInBags(entry) then
				if ItemRack.CombatQueue[slot] ~= entry then
					ItemRack.EquipItemByID(entry, slot)
				end
				-- an immediate swap leaves CombatQueue[slot] nil, so origin records only deferred swaps
				if ItemRack.CombatQueue[slot] == entry then
					ItemRack.AutoQueueOrigin[slot] = entry
				end
				break
			end
		end
	end
end

function ItemRack.SetQueue(slot, newQueue)
	if not newQueue then
		ItemRack.GetQueuesEnabled()[slot] = nil
		ItemRack.UpdateCombatQueue()
		return
	end
	if type(newQueue) ~= "table" then return end

	local queues = ItemRack.GetQueues()
	local queue = queues[slot] or {}
	queues[slot] = queue
	wipe(queue)
	for i = 1, #newQueue do
		queue[i] = newQueue[i]
	end

	if ItemRackOptFrame:IsVisible() then
		if ItemRackOptSubFrame6:IsVisible() and ItemRackOpt.SelectedSlot == slot then
			ItemRackOpt.SetupQueue(slot)
		else
			ItemRackOpt.UpdateInv()
		end
	end
	ItemRack.GetQueuesEnabled()[slot] = true
	ItemRack.UpdateCombatQueue()
end
