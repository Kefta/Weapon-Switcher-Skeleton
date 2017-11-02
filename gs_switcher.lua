--[[ Config ]]--

local MAX_SLOTS = 6
local CACHE_TIME = 1
local MOVE_SOUND = "Player.WeaponSelectionMoveSlot"
local SELECT_SOUND = "Player.WeaponSelected"

--[[ Instance variables ]]--

local iCurSlot = 0 -- Currently selected slot. 0 = no selection
local iCurPos = 1 -- Current position in that slot
local flNextPrecache = 0 -- Time until next precache
local flSelectTime = 0 -- Time the weapon selection changed slot/visibility states. Can be used to close the weapon selector after a certain amount of idle time
local iWeaponCount = 0 -- Total number of weapons on the player

-- Weapon cache; table of tables. tCache[Slot + 1] contains a table containing that slot's weapons. Table's length is tCacheLength[Slot + 1]
local tCache = {}

-- Weapon cache length. tCacheLength[Slot + 1] will contain the number of weapons that slot has
local tCacheLength = {}

--[[ Weapon switcher ]]--

local function DrawWeaponHUD()
	-- Draw here!
end

--[[ Implementation ]]--

-- Initialize tables with slot number
for i = 1, MAX_SLOTS do
	tCache[i] = {}
	tCacheLength[i] = 0
end

local pairs = pairs
local RealTime = RealTime
local LocalPlayer = LocalPlayer

local function PrecacheWeps()
	-- Reset all table values
	for i = 1, MAX_SLOTS do
		for j = 1, tCacheLength[i] do
			tCache[i][j] = nil
		end

		tCacheLength[i] = 0
	end

	-- Update the cache time
	flNextPrecache = RealTime() + CACHE_TIME
	iWeaponCount = 0

	-- Discontinuous table
	for _, pWeapon in pairs(LocalPlayer():GetWeapons()) do
		iWeaponCount = iWeaponCount + 1

		-- Weapon slots start internally at "0"
		-- Here, we will start at "1" to match the slot binds
		local iSlot = pWeapon:GetSlot() + 1

		if (iSlot <= MAX_SLOTS) then
			-- Cache number of weapons in each slot
			local iLen = tCacheLength[iSlot] + 1
			tCacheLength[iSlot] = iLen
			tCache[iSlot][iLen] = pWeapon
		end
	end

	-- Make sure we're not pointing out of bounds
	if (iCurSlot ~= 0) then
		local iLen = tCacheLength[iCurSlot]

		if (iLen < iCurPos) then
			if (iLen == 0) then
				iCurSlot = 0
			else
				iCurPos = iLen
			end
		end
	end
end

local cl_drawhud = GetConVar("cl_drawhud")

hook.Add("HUDPaint", "GS_WeaponSelector", function()
	if (iCurSlot == 0 or not cl_drawhud:GetBool()) then
		return
	end

	local pPlayer = LocalPlayer()

	-- Don't draw in vehicles unless weapons are allowed to be used
	-- Also, don't draw while dead!
	if (pPlayer:IsValid() and pPlayer:Alive() and (not pPlayer:InVehicle() or pPlayer:GetAllowWeaponsInVehicle())) then
		if (flNextPrecache <= RealTime()) then
			PrecacheWeps()
		end

		DrawWeaponHUD()
	else
		iCurSlot = 0
	end
end)

local tonumber = tonumber
local string_lower = string.lower

hook.Add("PlayerBindPress", "GS_WeaponSelector", function(pPlayer, sBind, bPressed)
	if (not pPlayer:Alive() or pPlayer:InVehicle() and not pPlayer:GetAllowWeaponsInVehicle()) then
		return
	end

	sBind = string_lower(sBind)

	-- Close the menu
	if (sBind == "cancelselect") then
		if (bPressed) then
			iCurSlot = 0
		end

		return true
	end

	-- Move to the weapon before the current
	if (sBind == "invprev") then
		if (not bPressed) then
			return true
		end

		PrecacheWeps()

		if (iWeaponCount == 0) then
			return true
		end

		local bLoop = iCurSlot == 0

		if (bLoop) then
			local pActiveWeapon = pPlayer:GetActiveWeapon()

			if (pActiveWeapon:IsValid()) then
				local iSlot = pActiveWeapon:GetSlot() + 1
				local tSlotCache = tCache[iSlot]

				if (tSlotCache[1] ~= pActiveWeapon) then
					iCurSlot = iSlot
					iCurPos = 1

					for i = 2, tCacheLength[iSlot] do
						if (tSlotCache[i] == pActiveWeapon) then
							iCurPos = i - 1

							break
						end
					end

					flSelectTime = RealTime()
					pPlayer:EmitSound(MOVE_SOUND)

					return true
				end

				iCurSlot = iSlot
			end
		end

		if (bLoop or iCurPos == 1) then
			repeat
				if (iCurSlot <= 1) then
					iCurSlot = MAX_SLOTS
				else
					iCurSlot = iCurSlot - 1
				end
			until(tCacheLength[iCurSlot] ~= 0)

			iCurPos = tCacheLength[iCurSlot]
		else
			iCurPos = iCurPos - 1
		end

		flSelectTime = RealTime()
		pPlayer:EmitSound(MOVE_SOUND)

		return true
	end

	-- Move to the weapon after the current
	if (sBind == "invnext") then
		if (not bPressed) then
			return true
		end

		PrecacheWeps()

		-- Block the action if there aren't any weapons available
		if (iWeaponCount == 0) then
			return true
		end

		-- Lua's goto can't jump between child scopes
		local bLoop = iCurSlot == 0

		-- Weapon selection isn't currently open, move based on the active weapon's position
		if (bLoop) then
			local pActiveWeapon = pPlayer:GetActiveWeapon()

			if (pActiveWeapon:IsValid()) then
				local iSlot = pActiveWeapon:GetSlot() + 1
				local iLen = tCacheLength[iSlot]
				local tSlotCache = tCache[iSlot]

				if (tSlotCache[iLen] ~= pActiveWeapon) then
					iCurSlot = iSlot
					iCurPos = 1

					for i = 1, iLen - 1 do
						if (tSlotCache[i] == pActiveWeapon) then
							iCurPos = i + 1

							break
						end
					end

					flSelectTime = RealTime()
					pPlayer:EmitSound(MOVE_SOUND)

					return true
				end

				-- At the end of a slot, move to the next one
				iCurSlot = iSlot
			end
		end

		if (bLoop or iCurPos == tCacheLength[iCurSlot]) then
			-- Loop through the slots until one has weapons
			repeat
				if (iCurSlot == MAX_SLOTS) then
					iCurSlot = 1
				else
					iCurSlot = iCurSlot + 1
				end
			until(tCacheLength[iCurSlot] ~= 0)

			-- Start at the beginning of the new slot
			iCurPos = 1
		else
			-- Bump up the position
			iCurPos = iCurPos + 1
		end

		flSelectTime = RealTime()
		pPlayer:EmitSound(MOVE_SOUND)

		return true
	end

	-- Keys 1-6
	if (sBind:sub(1, 4) == "slot") then
		local iSlot = tonumber(sBind:sub(5))

		-- If the command is slot#, use it for the weapon HUD
		-- Otherwise, let it pass through to prevent false positives
		if (iSlot == nil) then
			return
		end

		if (not bPressed) then
			return true
		end

		PrecacheWeps()

		-- Play a sound even if there aren't any weapons in that slot for "haptic" (really auditory) feedback
		if (iWeaponCount == 0) then
			pPlayer:EmitSound(MOVE_SOUND)

			return true
		end

		-- If the slot number is in the bounds
		if (iSlot <= MAX_SLOTS) then
			-- If the slot is already open
			if (iSlot == iCurSlot) then
				-- Start back at the beginning
				if (iCurPos == tCacheLength[iCurSlot]) then
					iCurPos = 1
				-- Move one up
				else
					iCurPos = iCurPos + 1
				end
			-- If there are weapons in this slot, display them
			elseif (tCacheLength[iSlot] ~= 0) then
				iCurSlot = iSlot
				iCurPos = 1
			end

			flSelectTime = RealTime()
			pPlayer:EmitSound(MOVE_SOUND)
		end

		return true
	end

	-- If the weapon selection is currently open
	if (iCurSlot ~= 0) then
		if (sBind == "+attack") then
			-- Hide the selection
			local pWeapon = tCache[iCurSlot][iCurPos]
			iCurSlot = 0

			-- If the weapon still exists and isn't the player's active weapon
			if (pWeapon:IsValid() and pWeapon ~= pPlayer:GetActiveWeapon()) then
				-- SelectWeapon might not work the first time; keep trying
				hook.Add("CreateMove", "GS_WeaponSelector", function(cmd)
					if (pWeapon:IsValid() and pPlayer:IsValid() and pWeapon ~= pPlayer:GetActiveWeapon()) then
						cmd:SelectWeapon(pWeapon)
					else
						hook.Remove("CreateMove", "GS_WeaponSelector")
					end
				end)
			end

			flSelectTime = RealTime()
			pPlayer:EmitSound(SELECT_SOUND)

			return true
		end

		-- Another shortcut for closing the selection
		if (sBind == "+attack2") then
			flSelectTime = RealTime()
			iCurSlot = 0

			return true
		end
	end
end)
