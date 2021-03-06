---------------------------------------------------------------
-- Spell helper
---------------------------------------------------------------
-- This frame places cursor pickups on action buttons by
-- reading input and comparing it to controller bindings.
-- Also provides a simple animation framework for that purpose.

local addOn, db = ...
local Helper = CreateFrame('Frame', addOn..'SpellHelperFrame', UIParent)
Helper:SetBackdrop(db.Atlas.Backdrops.Talkbox)
Helper:SetSize(500, 130)
Helper:SetPoint('TOP', 0, -32)
Helper:Hide()

Helper.Border = Helper:CreateTexture(nil, 'OVERLAY')
Helper.Border:SetPoint('TOPLEFT', 32, -32)
Helper.Border:SetSize(64, 64)
Helper.Border:SetTexture('Interface\\AddOns\\ConsolePort\\Textures\\Button\\Normal')

Helper.Icon = Helper:CreateTexture(nil, 'ARTWORK')
Helper.Icon:SetPoint('CENTER', Helper.Border, 0, 0)
Helper.Icon:SetSize(64, 64)
Helper.Icon:SetMask('Interface\\AddOns\\ConsolePort\\Textures\\Button\\Mask')

Helper.Name = Helper:CreateFontString(nil, 'ARTWORK')
Helper.Name:SetFont('Fonts\\MORPHEUS.ttf', 22, '')
Helper.Name:SetTextColor(1, 0.82, 0)
Helper.Name:SetPoint('TOPLEFT', Helper.Border, 'TOPRIGHT', 16, 0)
Helper.Name:SetSize(300, 22)
Helper.Name:SetJustifyH('LEFT')

Helper.Desc = Helper:CreateFontString(nil, 'ARTWORK', 'DialogButtonHighlightText')
Helper.Desc:SetPoint('TOPLEFT', Helper.Name, 'BOTTOMLEFT', 0, 0)
Helper.Desc:SetJustifyH('LEFT')

---------------------------------------------------------------
-- Binding lookups and helper input focus
---------------------------------------------------------------
--[[
	Item: 	_, name, _, _, _, _, _, _, _, _, texture = pcall(GetItemInfo, data)
	EQset: 	_, texture = pcall(GetEquipmentSetInfoByName, data), name = data .. loc.EQSET
	Mount: 	_, name, _, texture = pcall(C_MountJournal.GetMountInfoByID, data)
	Pet: 	_, _, customName, _, _, _, _, _, petName, petIcon = pcall(C_PetJournal.GetPetInfoByPetID, data), name = customName or petName
	Flyout: _, name = pcall(GetFlyoutInfo, data), texture = subType
	Macro:	 _, name, texture = pcall(GetMacroInfo, data)
	Spell: 	if (data ~= 0 and data ~= nil) then
				_, name, _, texture = pcall(GetSpellInfo, data, 'spell') -- or loc.SPELL
			elseif subData then
				_, name, _, texture = pcall(GetSpellInfo, subData)
			end
]]-- 

function Helper:OnShow()
	if db.Settings and db.Settings.disableSmartBind then
		self:UnregisterAllEvents()
		self:Hide()
	else
		self.blockInput = false
		self.cache = db.table.copy(db.Bindings)
		self.manifest = ConsolePort:GetBindings(true)
		local loc = db.TUTORIAL.BIND
		local _type, data, subType, subData = GetCursorInfo()
		local name, texture, customDesc, pcallOK, _
		if _type == 'item' then
			pcallOK, name, link, _, _, _, _, _, _, itemType, texture = pcall(GetItemInfo, data)
			name = name or loc.ITEM
			if itemType == 'INVTYPE_BAG' then
				self:ShowBags()
				self.blockInput = true
				customDesc = db.TUTORIAL.HINTS.HELPER_EQUIP_BAG
			elseif link and not (IsUsableItem(link) and not IsEquippableItem(link)) then
				self:Hide()
				return
			end
		elseif _type == 'macro' then
			pcallOK, name, texture = pcall(GetMacroInfo, data)
			name = (name or '') .. loc.MACRO
		elseif _type == 'spell' and subType == 'spell' then
			if (data ~= 0 and data ~= nil) then
				pcallOK, name, _, texture = pcall(GetSpellInfo, data, 'spell') -- or loc.SPELL
			elseif subData then
				pcallOK, name, _, texture = pcall(GetSpellInfo, subData)
			end
			name = name or loc.SPELL
			texture = texture or 'Interface\\Spellbook\\Spellbook-Icon'
		elseif _type == 'equipmentset' then
			name = (data or '') .. loc.EQSET
			pcallOK, texture = pcall(GetEquipmentSetInfoByName, data)
		elseif _type == 'mount' then
			pcallOK, name, _, texture = pcall(C_MountJournal.GetMountInfoByID, data)
		elseif _type == 'battlepet' then
			local _, _, customName, _, _, _, _, _, petName, petIcon = pcall(C_PetJournal.GetPetInfoByPetID, data) 
			name = customName or petName
			name = (name or '') .. loc.BATTLEPET
			texture = petIcon
		elseif _type == 'flyout' then
			pcallOK, name = pcall(GetFlyoutInfo, data)
			texture = subType
		end
		-- handle game client bug:
		-- function can be triggered when there's actually nothing on the cursor.
		if not pcallOK or not texture or not name then
			self:Hide()
			return
		end
		self.Icon:SetTexture(texture)
		self.Name:SetText(name)
		self.Desc:SetText(customDesc or db.TUTORIAL.HINTS.HELPER_ACTIONBAR)
		self:UpdateWidth()
		db.UIFrameFadeIn(self, 0.2, 0, 1)
	end
end

function Helper:OnHide()
	self.blockInput = nil
	self.pendingBinding = nil
	self.pendingActionID = nil
	self.pendingButton = nil
	self.pendingModifier = nil
	if self.BagFrame then
		self.BagFrame:Hide()
	end
end

function Helper:UpdateWidth()
	self:SetWidth(self.Desc:GetStringWidth() + 155)
end

function Helper:ShowBags()
	if not self.BagFrame then
		local size = 46
		self.BagFrame = CreateFrame('Frame', nil, self)
		self.BagFrame:SetBackdrop(db.Atlas.Backdrops.Talkbox)
		self.BagFrame:SetSize(64 + (4*size), 32 + size)
		self.BagFrame:SetPoint('BOTTOM', 0, -30)
		for i=1, (NUM_BAG_SLOTS) do
			local button = CreateFrame('CheckButton', 'CP_DropInBag' .. (i-1) .. 'Slot', self.BagFrame, 'BagSlotButtonTemplate')
			button:SetPoint('LEFT', ((i-1) * 46) + 32, 16)
			button:SetSize(size * (42/46), size * (42/46))
			button.IconBorder:SetSize(46, 46)
			button:GetNormalTexture():Hide()
		end
	end
	self.BagFrame:Show()
end

function Helper:OnEvent(event, ...)
	if self[event] then
		self[event](self, ...)
	elseif self:IsVisible() then
		self:Hide()
	end
end

function Helper:GetBindingSuggestion()
	local ignoredIndex = {}
	for key, subSet in pairs(self.cache) do
		for mod, binding in pairs(subSet) do
			local actionID = ConsolePort:GetActionID(binding)
			if actionID then
				ignoredIndex[actionID] = true
			end
		end
	end
	for i=1, 12 do
		if not GetActionInfo(i) and not ignoredIndex[i] then
			return i, ConsolePort:GetActionBinding(i)
		end
	end
	for i=25, 72 do
		if not GetActionInfo(i) and not ignoredIndex[i] then
			return i, ConsolePort:GetActionBinding(i)
		end
	end
end

function Helper:OnKeyDown(key)
	local bAction = GetBindingAction(key)
	local set = bAction and self.cache and self.cache[bAction]
	local isControllerButton = bAction and self.manifest and self.manifest[bAction]
	if not self.blockInput and isControllerButton then
		local modifier = ConsolePort:GetCurrentModifier()
		local isPendingActionApproved

		-- a pending binding prompt is approved
		if ( self.pendingButton == bAction and self.pendingModifier == modifier ) then
			local newBindingSet = ConsolePort:GetBindingSet()
			if not newBindingSet[bAction] then
				newBindingSet[bAction] = {}
			end
			-- update the binding set
			newBindingSet[bAction][modifier] = self.pendingBinding
			ConsolePort:LoadBindingSet(newBindingSet)
			ConsolePort:OnNewBindings(newBindingSet)
			-- place the action
			PlaceAction(self.pendingActionID)
			self:OnActionPlaced(self.pendingActionID, self.Icon:GetTexture())
			return
		end

		self.pendingBinding, self.pendingActionID = nil, nil
		self.pendingButton, self.pendingModifier = nil, nil

		if isPendingActionApproved then

		end

		local binding = set and set[modifier]
		local actionID = ConsolePort:GetActionID(binding)
		
		-- if the pressed binding has a corresp. action ID, place the item there and pop any existing item
		if actionID then
			PlaceAction(actionID)
			if 	( not GetCursorInfo() ) and
				( db.Settings and not db.Settings.disableSmartMouse ) and
				( GetMouseFocus() == WorldFrame ) then
				ConsolePortCamera:Start()
			end
			self:OnActionPlaced(actionID)

		-- clear the helper frame if the binding that was pressed is eqv. to Esc
		elseif binding == 'TOGGLEGAMEMENU' then
			ClearCursor()

		-- if the binding is occupied by something unrelated to action bars
		elseif binding then
			local formatted = ConsolePort:GetFormattedBindingOwner(binding, nil, nil, true)
			local bindName =  _G['BINDING_NAME_' .. binding]
			if formatted and bindName then
				self.Desc:SetText(format(db.TUTORIAL.HINTS.HELPER_INVALID_OCCUA, formatted, bindName))
			elseif formatted then
				self.Desc:SetText(format(db.TUTORIAL.HINTS.HELPER_INVALID_OCCUB, formatted))
			end

		-- the binding is free, check for suggestions
		else
			local formatted = ConsolePort:GetFormattedButtonCombination(bAction, modifier, nil, true)
			if formatted then
				local freeActionID, freeBindingID = self:GetBindingSuggestion()
				if freeActionID and freeBindingID then
					self.Desc:SetText(format(db.TUTORIAL.HINTS.HELPER_INVALID_FREE, formatted, _G['BINDING_NAME_' ..freeBindingID], formatted))
					self.pendingBinding, self.pendingActionID = freeBindingID, freeActionID
					self.pendingButton, self.pendingModifier = bAction, modifier
				else
					self.Desc:SetText(format(db.TUTORIAL.HINTS.HELPER_INVALID_ERROR, formatted))
				end
			end
		end
		self:SetPropagateKeyboardInput(false)
	else
		self:SetPropagateKeyboardInput(true)
	end
	self:UpdateWidth()
end

function Helper:PLAYER_REGEN_ENABLED(...)
	self:UnregisterEvent('PLAYER_REGEN_ENABLED')
	self:Show()
end

function Helper:PLAYER_REGEN_DISABLED(...) 
	if self:IsVisible() then 
		self:RegisterEvent('PLAYER_REGEN_ENABLED')
		self:Hide() 
	end
end

function Helper:ACTIONBAR_HIDEGRID(...)
	self:UnregisterEvent('PLAYER_REGEN_ENABLED')
	self.cache = nil
	self.manifest = nil
	self:Hide()
end

function Helper:ACTIONBAR_SHOWGRID(...)
	if not InCombatLockdown() then
		self:Show()
	else
		self:RegisterEvent('PLAYER_REGEN_ENABLED')
	end
end

for _, event in pairs({
	-------------------------
	-- Handled events
	-------------------------
	'ACTIONBAR_SHOWGRID',
	'ACTIONBAR_HIDEGRID',
	'PLAYER_REGEN_DISABLED',
	-------------------------
	-- Disable on ...
	-------------------------
	'DELETE_ITEM_CONFIRM',
	'EQUIP_BIND_CONFIRM',
	'EQUIP_BIND_TRADEABLE_CONFIRM',
	'MERCHANT_CONFIRM_TRADE_TIMER_REMOVAL',
	-------------------------
}) do Helper:RegisterEvent(event) end

Helper:SetPropagateKeyboardInput(true)
Helper:SetScript('OnShow', Helper.OnShow)
Helper:SetScript('OnHide', Helper.OnHide)
Helper:SetScript('OnEvent', Helper.OnEvent)
Helper:SetScript('OnKeyDown', Helper.OnKeyDown)
Helper.GetActionButtons = ConsolePort.GetActionButtons

---------------------------------------------------------------
-- Animations
---------------------------------------------------------------
Helper.iconList = {}

local ANIMSPEED = 1
local TRAILSPEED = 0.6
local MODX, MODY = 4, 2

local function FlyinOnFinished(self)
	local iconFrame = self:GetParent()
	if iconFrame.isBase then
		iconFrame.glow:Play()
		iconFrame.isFree = true
	else 
		iconFrame:SetFrameLevel(1)
	end
end

local function PathCalculateOffset(self, x, y)
	local first, second = self:GetControlPoints()
	first:SetOffset(x / MODX, y / MODY)
	second:SetOffset(x, y)
	self:SetDuration(ANIMSPEED)
end

function Helper:OnActionPlaced(actionID, pushTexture)
	local currentModifier = ConsolePort:GetCurrentModifier()
	local buttons = {}
	for button, ID in self:GetActionButtons() do
		-- filter out cp ab main buttons when animating a modified action binding, 
		-- since they will have the same action ID at this point as the modified buttons.
		-- ignore this restriction if the action was pushed automatically (low level auto-assign)
		if ( ID == actionID ) and ( pushTexture or ( not ( button.isMainButton and currentModifier ~= "" ) ) ) then
			buttons[button] = true
		end
	end

	local texture = pushTexture or GetActionTexture(actionID)
	local x, y = GetScaledCursorPosition()

	for button in pairs(buttons) do
		local freeIcon

		for _, v in pairs(self.iconList) do
			if v.isFree then
				freeIcon = v
				break
			end
		end

		if not freeIcon then
			freeIcon = CreateFrame('FRAME', self:GetName()..'Icon'..(#self.iconList+1), UIParent, 'IconIntroTemplate')
			freeIcon.glow = _G[freeIcon:GetName() .. 'IconGlow']
			freeIcon.paths = {}
			for _, f in pairs({freeIcon:GetChildren()}) do
				f.flyin:SetScript('OnFinished', FlyinOnFinished)
				f.flyin.wait:SetDuration(f.flyin.wait:GetDuration() * TRAILSPEED)
				for _, a in pairs({f.flyin:GetAnimations()}) do
					if a:IsObjectType('Path') then
						freeIcon.paths[a] = true
					else
						a:SetStartDelay(0)
					end
				end
			end
			self.iconList[#self.iconList+1] = freeIcon
		end

		local icon = freeIcon.icon
		local glow = freeIcon.glow

		local bGlow = button:GetHighlightTexture()
		if bGlow then
			glow:ClearAllPoints()
			glow:SetPoint('CENTER', 0, 0)
			glow:SetSize(bGlow:GetSize())
			glow:SetTexture(bGlow:GetTexture())
			glow:SetTexCoord(bGlow:GetTexCoord())
			glow:SetBlendMode(bGlow:GetBlendMode())
		end

		icon.icon:SetTexture(texture)
		icon.action = actionID

		freeIcon:ClearAllPoints()
		freeIcon:SetPoint('CENTER', button, 0, 0)
		freeIcon:SetFrameLevel(button:GetFrameLevel() + 1)

		local tX, tY = button:GetCenter()
		local w = button:GetWidth() or 0
		local oX, oY = (x - ( tX or 0) ) + w, (y - ( tY or 0))

		for path in pairs(freeIcon.paths) do
			PathCalculateOffset(path, oX, oY)
		end

		icon.flyin:Play(1)
		freeIcon.isFree = false
	end
end