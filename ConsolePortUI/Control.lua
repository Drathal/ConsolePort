local CP_UI, UI = ...
local UIParent, assert, pairs = UIParent, assert, pairs
local data = ConsolePort:GetData()
local Registry = UI.FrameRegistry
----------------------------------
local Control = UI:CreateFrame('Button', CP_UI..'Handle', nil, 'SecureHandlerBaseTemplate, SecureHandlerStateTemplate, SecureHandlerAttributeTemplate, SecureActionButtonTemplate', {
	StoredHints = {},
	HintBar = {
		Type = 'Frame',
		Strata = 'DIALOG',
		SetParent = UIParent,
		Hide = true,
		Height = 72,
		Point = {'BOTTOM', 0, 0},
		{
			Gradient = {
				Type = 'Texture',
				Setup = {'BACKGROUND'},
				SetColorTexture = {1, 1, 1},
				Height = 72,
				Points = {
					{'BOTTOMLEFT', UIParent, 'BOTTOMLEFT', 0, 0},
					{'BOTTOMRIGHT', UIParent, 'BOTTOMRIGHT', 0, 0},
				},
			},
			Active = {},
			Frames = {},
		},
	},
})
local Bar, Hint = Control.HintBar, {}
Bar:SetFrameStrata('FULLSCREEN_DIALOG')
----------------------------------

----------------------------------
-- Control input handling
----------------------------------
local secure_functions = {
	SetFocusFrame = [[
		if #stack > 0 then
			focusFrame = stack[1]
			self:SetAttribute('focus', focusFrame)
			self:ClearBindings()
			for binding, identifier in pairs(keys) do
				local key = GetBindingKey(binding)
				if key then
					self:SetBindingClick(true, key, self:GetFrameRef(binding), identifier)
				end
			end
			return true
		else
			focusFrame = nil
			self:SetAttribute('focus', nil)
			self:ClearBindings()
			return false
		end
	]],

	AddFrame = [[
		local added = self:GetAttribute('add')

		local oldStack = stack
		stack = newtable()

		stack[1] = added

		for _, frame in pairs(oldStack) do
			if frame ~= added then
				stack[#stack + 1] = frame
			end
		end
	]],

	RemoveFrame = [[
		local removed = self:GetAttribute('remove')

		local oldStack = stack
		stack = newtable()

		for _, frame in pairs(oldStack) do
			if frame ~= removed then
				stack[#stack + 1] = frame
			end
		end
	]],

	RefreshFocus = [[
		if self:RunAttribute('SetFocusFrame') then
			self:CallMethod('SetHintFocus')
			self:CallMethod('RestoreHints')
			for i=2, #stack do
				self:CallMethod('SetIgnoreFadeFrame', stack[i]:GetName(), false)
			end
			if focusFrame:GetAttribute('hideUI') then
				self:CallMethod('ShowUI')
				self:CallMethod('HideUI',
					focusFrame:GetName(), 
					focusFrame:GetAttribute('hideActionBar'))
			end
		else
			self:CallMethod('SetHintFocus')
			self:CallMethod('ShowUI')
			self:CallMethod('HideHintBar')
		end
	]],

	RefreshStack = [[
		if self:GetAttribute('add') then
			self:RunAttribute('AddFrame')
		end

		if self:GetAttribute('remove') then
			self:RunAttribute('RemoveFrame')
		end

		self:SetAttribute('add', nil)
		self:SetAttribute('remove', nil)
	]],
}

local secure_wrappers = {
	PreClick = [[
		self:SetAttribute('type', nil)
		self:SetAttribute('macrotext', nil)
		self:SetAttribute('clickbutton', nil)
		local frame = stack[1]
		if frame:GetAttribute('useCursor') then
			-- NYI
		elseif frame:GetAttribute('OnInput') then
			local clickType, clickHandler, clickValue = 
				frame:RunAttribute('OnInput', tonumber(button), down)
			if clickType and clickHandler and clickValue then
				self:SetAttribute('type', clickType)
				self:SetAttribute(clickHandler, clickValue)
			end
		else
			frame:CallMethod('OnInput', button, down)
		end
	]],
}

for name, script in pairs(secure_functions) do Control:SetAttribute(name, script) end

--------------------------------------------------------------------
-- Readable variables mixed into each secure environment for comparison with inputs.
-- E.g. button == 8 -> button == CROSS 
local button_identifiers = ''
for readable, identifier in pairs(data.KEY) do
	if type(identifier) == 'string' then
		button_identifiers = button_identifiers..format('%s = "%s" ', readable, identifier)
	elseif type(identifier) == 'number' then
		button_identifiers = button_identifiers..format('%s = %s ', readable, identifier)
	end
end

-- (1) Register the generated variable string.
-- (2) Instantiate a frame stack and a key table for input handling.
-- (3) Forward binding identifiers into the control handle.
-- (4) Create individual input handlers to provide multi-button control.
----------------------------------
Control:Execute(button_identifiers)
Control:Execute([[
	stack, keys = newtable(), newtable()
	Control = self
]])
----------------------------------
for binding in ConsolePort:GetBindings() do
	local UIkey = ConsolePort:GetUIControlKey(binding)
	if UIkey then
		-- keys [string binding] = [integer key]
		Control:Execute(([[ keys.%s = '%s' ]]):format(binding, UIkey))
		local inputHandler = CreateFrame('Button', '$parent_'..binding, Control, 'SecureActionButtonTemplate')
		-- Register for any input, since these will simulate integer keys.
		inputHandler:RegisterForClicks('AnyUp', 'AnyDown')
		-- Assume macro initially; input handler may change between macro/click.
		inputHandler:SetAttribute('type', 'macro')
		-- Reference the handler so it can be bound securely.
		Control:SetFrameRef(binding, inputHandler)
		-- Set up click wrappers for the input handlers.
		for name, script in pairs(secure_wrappers) do
			Control:WrapScript(inputHandler, name, script)
		end
	end
end

----------------------------------
-- Control API
----------------------------------
function UI:GetControlHandle() return Control end
----------------------------------
function UI:RegisterFrame(frame, ID, useCursor, hideUI, hideActionBar) 
	assert(frame, 'Frame handle does not exist.')
	assert(frame:IsProtected(), 'Frame handle is not protected.')
	assert(frame.Execute, 'Frame handle does not have a base template.')
	assert(not InCombatLockdown(), 'Frame handle cannot be registered in combat.')
	assert(ID, 'Frame handle does not have an ID.') 
	Control:RegisterFrame(frame, ID, useCursor, hideUI, hideActionBar)
end
----------------------------------
Control:SetAttribute('type', 'macro')
Control:RegisterForClicks('AnyUp', 'AnyDown')

function Control:RegisterFrame(frame, ID, useCursor, hideUI, hideActionBar)
	frame:Execute(button_identifiers)
	frame:SetAttribute('useCursor', useCursor)
	frame:SetAttribute('hideUI', hideUI)
	frame:SetAttribute('hideActionBar', hideActionBar)
	frame:SetFrameRef('control', self)
	self:SetFrameRef(ID, frame)
	self:WrapScript(frame, 'OnShow', ([[
		Control:SetAttribute('add', self)
		Control:RunAttribute('RefreshStack')
		Control:RunAttribute('RefreshFocus')
	]]):format(ID))
	self:WrapScript(frame, 'OnHide', ([[
		Control:SetAttribute('remove', self)
		Control:CallMethod('ClearHintsForFrame')
		Control:RunAttribute('RefreshStack')
		Control:RunAttribute('RefreshFocus')
	]]):format(ID))
end

----------------------------------
-- UI Fader
----------------------------------
local FadeIn, FadeOut = data.UIFrameFadeIn, data.UIFrameFadeOut
local updateThrottle = 0
local ignoreFrames = {
	[Control] = true,
	[Control.HintBar] = true,
	[ChatFrame1] = true,
	[CastingBarFrame] = true,
	[Minimap] = true,
	[MinimapCluster] = true,
	[GameTooltip] = true,
	[StaticPopup1] = true,
	[StaticPopup2] = true,
	[StaticPopup3] = true,
	[StaticPopup4] = true,
	[SubZoneTextFrame] = true,
	[ShoppingTooltip1] = true,
	[ShoppingTooltip2] = true,
	[OverrideActionBar] = true,
	[ObjectiveTrackerFrame] = true,
	[UIErrorsFrame] = true,
}
local forceFrames = {
	['ConsolePortBar'] = true,
	['MainMenuBar']  = true,
}

local function GetFadeFrames(onlyActionBars)
	local fadeFrames, frameStack = {}
	if onlyActionBars then
		frameStack = {}
		for registeredFrame in pairs(Registry) do
			frameStack[#frameStack + 1] = registeredFrame
		end
		for _, actionBar in ConsolePort:GetActionBars() do
			frameStack[#frameStack + 1] = actionBar
		end
	else
		frameStack = {UIParent:GetChildren()}
	end
	----------------------------------
	local valid, name, forceChild, ignoreChild, isConsolePortFrame
	----------------------------------
	for i, child in pairs(frameStack) do
		if not child:IsForbidden() then -- assert this frame isn't forbidden
			----------------------------------
			valid = false
			name = child:GetName()
			forceChild = name and forceFrames[name]
			ignoreChild = ignoreFrames[child]
			isConsolePortFrame = name and name:match('ConsolePort')
			----------------------------------
			if 	( Registry[child] and not ignoreChild ) or
				-- if the frame is in the UI registry and not set to be ignored,
				-- valid when multiple frames are shown simultaneously to fade out unfocused frames.
				( isConsolePortFrame and forceChild ) or
				-- if the frame belongs to the ConsolePort suite and should be faded regardless
				( ( forceChild ) or ( not isConsolePortFrame and not ignoreChild ) ) then
				-- if the frame is forced (action bars), or if the frame is not explicitly ignored
				valid = true
			end
			if valid then
				fadeFrames[child] = child.fadeInfo and child.fadeInfo.endAlpha or child:GetAlpha()
			end
		end
	end
	return fadeFrames
end

function Control:TrackMouseOver(elapsed)
	updateThrottle = updateThrottle + elapsed
	if updateThrottle > 0.5 then
		if self.fadeFrames then
			for frame, origAlpha in pairs(self.fadeFrames) do
				if frame:IsMouseOver() and frame:IsMouseEnabled() then
					FadeIn(frame, 0.2, frame:GetAlpha(), origAlpha)
				elseif frame:GetAlpha() > 0.1 then
					FadeOut(frame, 0.2, frame:GetAlpha(), 0) 
				end
			end
		else
			self:SetScript('OnUpdate', nil)
		end
		updateThrottle = 0
	end
end

function Control:SetIgnoreFadeFrame(frameName, toggleIgnore, fadeInOnFinish)
	local frame = _G[frameName]
	ignoreFrames[frame] = toggleIgnore
	if toggleIgnore then
		if self.fadeFrames then
			self.fadeFrames[frame] = nil
		end
		if fadeInOnFinish then
			FadeIn(frame, 0.2, frame:GetAlpha(), 1)
		end
	end
end

function Control:HideUI(focusFrame, onlyActionBars)
	if focusFrame then
		self:SetIgnoreFadeFrame(focusFrame, true, true)
	end

	local frames = GetFadeFrames(onlyActionBars)
	for frame in pairs(frames) do
		FadeOut(frame, fadeTime or 0.2, frame:GetAlpha(), 0)
	end
	self.fadeFrames = frames

	updateThrottle = 0
	self:SetScript('OnUpdate', self.TrackMouseOver)
end

function Control:ShowUI()
	if self.fadeFrames then
		for frame, origAlpha in pairs(self.fadeFrames) do
			FadeIn(frame, fadeTime or 0.5, frame:GetAlpha(), origAlpha)
		end
		self.fadeFrames = nil
	end
end

----------------------------------
-- Hint bar
----------------------------------
-- This bar appears at the bottom of the screen and displays
-- button function hints local to the focused frame.
-- Hints are controlled from the UI modules.
-- Although hints are cached for each frame in the stack,
-- the hint control will set a new hint to the current focus
-- frame, regardless of where the function call comes from.
-- Explicitly hiding a stack frame clears its hint cache.

function Bar:Enable()
	local cc = UI.Media.CC
	self.Gradient:SetGradientAlpha('VERTICAL', 0, 0, 0, 1, cc.r / 5, cc.g / 5, cc.b / 5, 0)
	self:Show()
	return self
end

function Bar:AdjustWidth(newWidth)
	self:SetScript('OnUpdate', function(self)
		local width = self:GetWidth()
		local diff = newWidth - width
		if abs(newWidth - width) < 1 then
			self:SetWidth(newWidth)
			self:SetScript('OnUpdate', nil)
		else
			self:SetWidth(width + ( diff / 4 ) )
		end
	end)
end

function Bar:Update()
	local width, previousHint = 0
	for _, hint in pairs(self.Frames) do
		if previousHint then
			hint:SetPoint('LEFT', previousHint.text, 'RIGHT', 16, 0)
		else
			hint:SetPoint('LEFT', self, 'LEFT', 0, 0)
		end
		if hint:IsVisible() then
			width = width + hint:GetWidth()
			previousHint = hint
		end
	end
	self:AdjustWidth(width)
end

function Bar:GetHintFromPool(key)
	if self.focus then
		local hints = self.Active
		local hint = hints[key]
		if not hint then
			for _, poolHint in pairs(self.Frames) do
				if not poolHint.isActive then
					hint = poolHint
					break
				end
			end
		end
		if not hint then
			local id = #self.Frames + 1
			hint = CreateFrame('Frame', '$parentHint'..id, self)
			hint.icon = hint:CreateTexture('$parentIcon', 'ARTWORK')
			hint.icon:SetSize(40, 40)
			hint.icon:SetPoint('LEFT')
			hint.text = hint:CreateFontString('$parentText', 'ARTWORK', 'Game20Font')
			hint.text:SetPoint('LEFT', hint.icon, 'RIGHT', 8, 0)
			hint.text:SetShadowOffset(2, -2)
			hint:SetHeight(64)
			hint:SetID(id)
			hint:Hide()
			hint.bar = self
			hint.pool = self.Frames
			self.Frames[ #self.Frames + 1] = hint
			UI.Utils.Mixin(hint, Hint)
		end
		hint:Show()
		hints[key] = hint

		self:Enable()
		return hint
	end
end

----------------------------------
-- Hint control
----------------------------------
function Control:SetHintFocus()
	self.HintBar.focus = self:GetAttribute('focus')
	self.focus = self.HintBar.focus
end

function Control:ClearHintsForFrame()
	self.StoredHints[self:GetAttribute('remove')] = nil
end

function Control:RestoreHints()
	if self.focus then
		local storedHints = self.StoredHints[self.HintBar.focus]
		if storedHints then
			self:ResetHintBar()
			for key, info in pairs(storedHints) do
				self:AddHint(key, info.text)
				if not info.enabled then
					self:SetHintDisabled(key)
				end
			end
		end
	end
end

function Control:HideHintBar()
	self:ResetHintBar()
	self.HintBar:Hide()
end

function Control:ResetHintBar()
	for _, hint in pairs(self.HintBar.Frames) do
		hint:Hide()
	end
	wipe(self.HintBar.Active)
end

function Control:RegisterHintForFrame(frame, key, text, enabled)
	self.StoredHints[frame] = self.StoredHints[frame] or {}
	self.StoredHints[frame][key] = {text = text, enabled = enabled}
end

function Control:UnregisterHintForFrame(frame, key)
	if self.StoredHints[frame] then
		self.StoredHints[frame][key] = nil
	end
end

function Control:AddHint(key, text)
	local binding = ConsolePort:GetUIControlKeyOwner(key)
	if binding then
		local hint = self.HintBar:GetHintFromPool(key)
		if hint then
			hint:SetData(binding, text)
			hint:SetEnabled()
			self:RegisterHintForFrame(self.focus, key, text, true)
			return hint
		end
	end
end

function Control:RemoveHint(key)
	local hint = self:GetHintForKey(key)
	if hint then
		self.HintBar.Active[key] = nil
		self:UnregisterHintForFrame(self.focus, key)
		hint:Hide()
	end
end

function Control:GetHintForKey(key)
	local hint = self.HintBar.Active[key]
	if hint then
		return hint, hint:GetText()
	end
end

function Control:SetHintDisabled(key)
	local hint = self:GetHintForKey(key)
	if hint then
		hint:SetDisabled()
		self:RegisterHintForFrame(self.focus, key, hint:GetText(), false)
	end
end

function Control:SetHintEnabled(key)
	local hint = self:GetHintForKey(key)
	if hint then
		hint:SetEnabled()
		self:RegisterHintForFrame(self.focus, key, hint:GetText(), true)
	end
end

----------------------------------
-- Hint mixin
----------------------------------
function Hint:UpdateParentWidth()
	self.bar:Update()
end

function Hint:SetEnabled()
	self.icon:SetVertexColor(1, 1, 1)
	self.text:SetVertexColor(1, 1, 1)
end

function Hint:SetDisabled()
	self.icon:SetVertexColor(0.5, 0.5, 0.5)
	self.text:SetVertexColor(0.5, 0.5, 0.5)
end

function Hint:OnShow()
	self.isActive = true
	data.UIFrameFadeIn(self, 0.2, 0, 1)
end

function Hint:OnHide()
	self.isActive = false
	self:SetData(nil, nil)
end

function Hint:GetText()
	return self.text:GetText()
end

function Hint:SetData(icon, text)
	self.icon:SetTexture(data.TEXTURE[icon])
	self.text:SetText(text)
	self:SetWidth(self.text:GetStringWidth() + 64)
	self:UpdateParentWidth()
end