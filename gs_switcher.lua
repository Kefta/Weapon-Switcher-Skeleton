--[[------------------------------------]]--
-- Config

local MAX_SLOTS = 6
local CACHE_TIME = 1
local MOVE_SOUND = "Player.WeaponSelectionMoveSlot"
local SELECT_SOUND = "Player.WeaponSelected"

--[[------------------------------------]]--
-- Instance variables

local iCurSlot = 0 -- Currently selected slot. 0 = no selection
local iCurPos = 1 -- Current position in that slot
local flNextPrecache = 0 -- Time until next precache
local flSelectTime = 0 -- Time the weapon selection changed slot/visibility states
local iWeaponCount = 0 -- Total number of weapons on the player

-- Weapon cache; table of tables. tCache[Slot + 1] contains a table containing that slot's weapons. Table's length is tCacheLength[Slot + 1]
local tCache = {}

-- Weapon cache length. tCacheLength[Slot + 1] will contain the number of weapons that slot has
local tCacheLength = {}

--[[------------------------------------]]--
-- Weapon switcher

local function DrawWeaponHUD()
	-- Draw here!
end

--[[------------------------------------]]--
-- Implementation

local cl_drawhud = GetConVar("cl_drawhud")

-- Initialize tables with slot number
for i = 1, MAX_SLOTS do
	tCache[i] = {}
	tCacheLength[i] = 0
end

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

hook.Add("HUDPaint", "GS-Weapon Selector", function()
	if (iCurSlot == 0 or not cl_drawhud:GetBool()) then
		return
	end
	
	local pPlayer = LocalPlayer()
	
	-- Don't draw in vehicles unless weapons are allowed to be used
	-- Also, don't draw while dead!
	if (not (pPlayer:IsValid() and pPlayer:Alive()) or pPlayer:InVehicle() and not pPlayer:GetAllowWeaponsInVehicle()) then
		iCurSlot = 0

		return
	end
	
	if (flNextPrecache <= RealTime()) then
		PrecacheWeps()
	end
	
	DrawWeaponHUD()
end)

hook.Add("PlayerBindPress", "GS-Weapon Selector", function(pPlayer, sBind, bPressed)
	-- Close the menu
	if (sBind == "cancelselect") then
		iCurSlot = 0

		return true
	end
	
	-- Move to the weapon after the current
	-- Binds are mixed up. Next goes to the previous and vice-versa
	if (sBind == "invprev") then
		if (not (pPlayer:IsValid() and pPlayer:Alive()) or pPlayer:InVehicle() and not pPlayer:GetAllowWeaponsInVehicle()) then
			iCurSlot = 0
			
			return true
		end
		
		-- Don't use the bind unless it was activated
		if (not bPressed) then
			return true
		end
		
		PrecacheWeps()
		
		-- Block the action if there aren't any weapons available
		if (iWeaponCount == 0) then
			return true
		end
		
		-- goto substitute :/
		local bLoop = false
		
		-- Weapon selection isn't currently open, move based on the active weapon's position
		if (iCurSlot == 0) then
			local pActiveWeapon = pPlayer:GetActiveWeapon()
			
			if (pActiveWeapon:IsValid()) then
				local iSlot = pActiveWeapon:GetSlot() + 1
				local iLen = tCacheLength[iSlot]
				local tSlotCache = tCache[iSlot]
				
				-- At the end of a slot, move to the next one
				if (tSlotCache[iLen] == pActiveWeapon) then
					iCurSlot = iSlot
					bLoop = true
				-- Bump up a position from the active weapon
				else
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
			else
				-- NULL weapon will just start at the first available slot/position
				bLoop = true
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
	
	-- Move to the weapon before the current
	-- Backwards of invprev
	if (sBind == "invnext") then
		if (not (pPlayer:IsValid() and pPlayer:Alive()) or pPlayer:InVehicle() and not pPlayer:GetAllowWeaponsInVehicle()) then
			iCurSlot = 0
			
			return true
		end
		
		if (not bPressed) then
			return true
		end
		
		PrecacheWeps()
		
		if (iWeaponCount == 0) then
			return true
		end
		
		local bLoop = false
		
		if (iCurSlot == 0) then
			local pActiveWeapon = pPlayer:GetActiveWeapon()
			
			if (pActiveWeapon:IsValid()) then
				local iSlot = pActiveWeapon:GetSlot() + 1
				local tSlotCache = tCache[iSlot]
				
				if (tSlotCache[1] == pActiveWeapon) then
					iCurSlot = iSlot
					bLoop = true
				else
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
			else
				bLoop = true
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
	
	-- Keys 1-6
	if (sBind:sub(1, 4) == "slot") then
		if (not (pPlayer:IsValid() and pPlayer:Alive()) or pPlayer:InVehicle() and not pPlayer:GetAllowWeaponsInVehicle()) then
			iCurSlot = 0
			
			return true
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
		
		local iSlot = tonumber(sBind:sub(5, 6))
		
		-- If the command is slot# or slot##, use it for the weapon HUD
		-- Otherwise, let it pass through to prevent false positives
		if (iSlot) then
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
	end
	
	-- If the weapon selection is currently open
	if (iCurSlot ~= 0) then
		if (not (pPlayer:IsValid() and pPlayer:Alive()) or pPlayer:InVehicle() and not pPlayer:GetAllowWeaponsInVehicle()) then
			iCurSlot = 0
			
			return
		end
		
		if (sBind == "+attack") then
			if (not bPressed) then
				return true
			end
			
			-- Hide the selection
			iCurSlot = 0
			local pWeapon = tCache[iCurSlot][iCurPos]
			
			-- If the weapon still exists and isn't the player's active weapon
			if (pWeapon:IsValid() and pWeapon ~= pPlayer:GetActiveWeapon()) then
				-- SelectWeapon might not work the first time; keep trying
				hook.Add("CreateMove", "GS-Weapon Selector", function(cmd)
					if (pWeapon:IsValid() and pPlayer:IsValid() and pWeapon ~= pPlayer:GetActiveWeapon()) then
						cmd:SelectWeapon(pWeapon)
					else
						hook.Remove("CreateMove", "GS-Weapon Selector")
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
	
	-- TODO: Add LastWeapon? Should the weapon switcher handle that?
end)
