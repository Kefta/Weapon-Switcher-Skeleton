--[[ Config ]]--

local MAX_SLOTS = 6	 -- Max number of weapon slots. Expects Integer [0, inf)
local CACHE_TIME = 1 -- Time in seconds between updating the weapon cache. RealTime is used for comparisons. Expects Decimal [0, inf]. 0 = update every frame, inf = never update
local MOVE_SOUND = "Player.WeaponSelectionMoveSlot" -- Sound to play when the player moves between weapon slots. Expects String soundscape or sound file path. "" = no sound
local SELECT_SOUND = "Player.WeaponSelected" -- Sound to play when the player selects a weapon. Expects String soundscape or sound file path. "" = no sound
local CANCEL_SOUND = "" -- Sound to play when the player cancels the weapon selection. Expects String soundscape or sound file path. "" = no sound

--[[ Instance variables - do not edit ]]--

local iCurSlot = 0 -- Currently selected slot. Will be an Integer [0, MAX_SLOTS]. 0 = no selection
local iCurPos = 1 -- Current position in that slot. Will be an Integer [0, inf)
local flNextPrecache = 0 -- Time until next precache. Will be a Decimal [0, inf) representing a RealTime
local flSelectTime = 0 -- Time the weapon selection changed slot/visibility states. Can be used to close the weapon selector after a certain amount of idle time. Will be a Decimal [0, inf) representing a RealTime
local iWeaponCount = 0 -- Total number of weapons on the player. Will be an Integer [0, inf)

-- Weapon cache; table of tables. tCache[Slot + 1] contains a table containing that slot's weapons. Table's length is tCacheLength[Slot + 1]
local tCache = {}

-- Weapon cache length. tCacheLength[Slot + 1] will contain the number of weapons that slot has
local tCacheLength = {}

--[[ Weapon switcher ]]--

--[[ Guarentees when this function is called:
	- cl_drawhud != 0
	- uCurSlot >= 1
	- iCurPos >= 1
	- iWeaponCount >= 1
	- LocalPlayer():IsValid()
	- LocalPlayer():Alive()
	- not LocalPlayer():InVehicle() or LocalPlayer():GetAllowWeaponsInVehicle()
]]
local function DrawWeaponHUD()
	-- Draw here!
end

--[[ Implementation - do not edit ]]--

-- Initialize tables with slot number
for i = 1, MAX_SLOTS do
	tCache[i] = {}
	tCacheLength[i] = 0
end

local pairs = pairs
local tonumber = tonumber
local RealTime = RealTime
local hook_Add = hook.Add
local math_floor = math.floor
local LocalPlayer = LocalPlayer
local string_lower = string.lower
local input_SelectWeapon = input.SelectWeapon

-- Hide the default weapon selection
hook_Add("HUDShouldDraw", "GS_WeaponSelector", function(sName)
	if (sName == "CHudWeaponSelection") then
		return false
	end
end)

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

	local tWeapons = LocalPlayer():GetWeapons()
	iWeaponCount = #tWeapons

	if (iWeaponCount == 0) then
		iCurSlot = 0
		iCurPos = 1
	else
		for i = 1, iWeaponCount do
			local pWeapon = tWeapons[i]

			-- Weapon slots start internally at 0
			-- Here, we will start at 1 to match the slot binds
			local iSlot = pWeapon:GetSlot() + 1

			if (iSlot <= MAX_SLOTS) then
				-- Cache number of weapons in each slot
				local iLen = tCacheLength[iSlot] + 1
				tCacheLength[iSlot] = iLen
				tCache[iSlot][iLen] = pWeapon
			end
		end
	end

	-- Make sure we're not pointing out of bounds
	if (iCurSlot ~= 0) then
		local iLen = tCacheLength[iCurSlot]

		if (iLen == 0) then
			iCurSlot = 0
			iCurPos = 1
		elseif (iLen < iCurPos) then
			iCurPos = iLen
		end
	end
end

local function CheckBounds()
	if (iCurSlot < 0 or iCurSlot > MAX_SLOTS) then
		iCurSlot = 0
	else
		iCurSlot = math_floor(iCurSlot)
	end

	if (iCurPos < 1) then
		iCurPos = 1
	else
		iCurPos = math_floor(iCurPos)
	end

	if (iWeaponCount < 0) then
		iWeaponCount = 0
	else
		iWeaponCount = math_floor(iWeaponCount)
	end
end

local cl_drawhud = GetConVar("cl_drawhud")

hook_Add("HUDPaint", "GS_WeaponSelector", function()
	CheckBounds()

	if (iCurSlot == 0 or not cl_drawhud:GetBool()) then
		return
	end

	local pPlayer = LocalPlayer()

	-- Don't draw in vehicles unless weapons are allowed to be used
	-- Or while dead!
	if (pPlayer:IsValid() and pPlayer:Alive() and (not pPlayer:InVehicle() or pPlayer:GetAllowWeaponsInVehicle())) then
		if (flNextPrecache <= RealTime()) then
			PrecacheWeps()
		end

		if (iCurSlot ~= 0) then
			DrawWeaponHUD()
		end
	else
		iCurSlot = 0
		iCurPos = 1
	end
end)

hook_Add("PlayerBindPress", "GS_WeaponSelector", function(pPlayer, sBind, bPressed)
	if (not pPlayer:Alive() or pPlayer:InVehicle() and not pPlayer:GetAllowWeaponsInVehicle()) then
		return
	end

	CheckBounds()
	sBind = string_lower(sBind)

	-- Last weapon switch
	if (sBind == "lastinv") then
		if (bPressed) then
			local pLastWeapon = pPlayer:GetInternalVariable("m_hLastWeapon")

			if (pLastWeapon ~= nil and pLastWeapon:IsWeapon()) then
				input_SelectWeapon(pLastWeapon)
			end
		end

		return true
	end

	-- Close the menu
	if (sBind == "cancelselect") then
		if (bPressed and iCurSlot ~= 0) then
			iCurSlot = 0
			iCurPos = 1

			flSelectTime = RealTime()
			pPlayer:EmitSound(CANCEL_SOUND)
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
			iCurPos = 1

			-- If the weapon still exists and isn't the player's active weapon
			if (pWeapon:IsValid() and pWeapon ~= pPlayer:GetActiveWeapon()) then
				input_SelectWeapon(pWeapon)
			end

			flSelectTime = RealTime()
			pPlayer:EmitSound(SELECT_SOUND)

			return true
		end

		-- Another shortcut for closing the selection
		if (sBind == "+attack2") then
			flSelectTime = RealTime()
			pPlayer:EmitSound(CANCEL_SOUND)

			iCurSlot = 0
			iCurPos = 1

			return true
		end
	end
end)
