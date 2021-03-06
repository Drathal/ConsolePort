---------------------------------------------------------------
-- CVar.lua: CVar management 
---------------------------------------------------------------
-- Used to increase convenience during gameplay without 
-- applying permanent changes to global CVars. Allows
-- cvar updates when entering/leaving combat.

local _, db = ...

local CVars = {
	TargetNearestUseNew 	= 	{value = 0},
	autoLootDefault 		= 	{value = true,	isCombatCVar = true, 	event = "AUTO_LOOT_DEFAULT_TEXT"},
	autoInteract 			= 	{value = true, 	isCombatCVar = false,	event = "CLICK_TO_MOVE"},
	mouseInvertPitch 		= 	{value = true, 	isCombatCVar = false, 	event = "INVERT_MOUSE"},
}

function ConsolePort:LoadDefaultCVars()
	for cvar, info in pairs(CVars) do
		if info.default then
			info.protected = true
		else
			info.default = GetCVar(cvar)
		end
	end
	self.LoadDefaultCVars = nil
end

function ConsolePort:UpdateCVars(inCombat, ...)
	local isToggled = db.Settings
	local newCvar, newValue = ...
	for cvar, info in pairs(CVars) do
		if inCombat == nil then
			-- If a specific cvar triggered the update (toggled inside Blizzard interface options), assign it to default value
			if newCvar and info.event == newCvar then
				info.default = newValue
			end
			-- If the cvar is not combat related, toggle it on until logout/disable
			if not info.isCombatCVar and isToggled[cvar] then
				info.default = info.default or GetCVar(cvar)
				SetCVar(cvar, info.value)
			-- If the cvar is not toggled but has a stored default value, then set default
			elseif not isToggled[cvar] and info.default then
				SetCVar(cvar, info.default, info.console)
				if not info.protected then
					info.default = nil
				end
			end
			-- If the cvar is combat related and toggled on
		elseif info.isCombatCVar and isToggled[cvar] then
			if inCombat then
				SetCVar(cvar, info.value)
			else
				SetCVar(cvar, info.default)
			end
		end
	end
end

function ConsolePort:ResetCVars()
	for cvar, info in pairs(CVars) do
		if info.default then
			SetCVar(cvar, info.default)
		end
	end
end
