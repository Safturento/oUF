local parent, ns = ...
local global = GetAddOnMetadata(parent, 'X-oUF')
local _VERSION = GetAddOnMetadata(parent, 'version')

local function argcheck(value, num, ...)
	assert(type(num) == 'number', "Bad argument #2 to 'argcheck' (number expected, got "..type(num)..")")

	for i=1,select("#", ...) do
		if type(value) == select(i, ...) then return end
	end

	local types = strjoin(", ", ...)
	local name = string.match(debugstack(2,2,0), ": in function [`<](.-)['>]")
	error(("Bad argument #%d to '%s' (%s expected, got %s"):format(num, name, types, type(value)), 3)
end

local print = function(...) print("|cff33ff99oUF:|r", ...) end
local error = function(...) print("|cffff0000Error:|r "..string.format(...)) end
local dummy = function() end

local function SetManyAttributes(self, ...)
	for i=1,select("#", ...),2 do
		local att,val = select(i, ...)
		if not att then return end
		self:SetAttribute(att,val)
	end
end

-- Colors
local colors = {
	happiness = {
		[1] = {1, 0, 0}, -- need.... | unhappy
		[2] = {1, 1, 0}, -- new..... | content
		[3] = {0, 1, 0}, -- colors.. | happy
	},
	smooth = {
		1, 0, 0,
		1, 1, 0,
		0, 1, 0
	},
	disconnected = {.6, .6, .6},
	tapped = {.6,.6,.6},
	class = {},
	reaction = {},
}

-- We do this because people edit the vars directly, and changing the default
-- globals makes SPICE FLOW!
if(IsAddOnLoaded'!ClassColors' and CUSTOM_CLASS_COLORS) then
	local updateColors = function()
		for eclass, color in next, CUSTOM_CLASS_COLORS do
			colors.class[eclass] = {color.r, color.g, color.b}
		end

		local oUF = ns.oUF or _G[parent]
		if(oUF) then
			for _, obj in next, oUF.objects do
				obj:PLAYER_ENTERING_WORLD"PLAYER_ENTERING_WORLD"
			end
		end
	end

	updateColors()
	CUSTOM_CLASS_COLORS:RegisterCallback(updateColors)
else
	for eclass, color in next, RAID_CLASS_COLORS do
		colors.class[eclass] = {color.r, color.g, color.b}
	end
end

for eclass, color in next, FACTION_BAR_COLORS do
	colors.reaction[eclass] = {color.r, color.g, color.b}
end

local _STATEFORMAT = [[
local header = self:GetFrameRef('%s')
if(newstate == 'party') then
	if(header:GetAttribute'visibleParty') then
		header:Show()
	else
		header:Hide()
	end
elseif(newstate == 'raid') then
	if(header:GetAttribute'visibleRaid') then
		header:Show()
	else
		header:Hide()
	end
elseif(newstate == 'solo') then
	if(header:GetAttribute'visibleSolo') then
		header:Show()
	else
		header:Hide()
	end
end
]]

-- add-on object
local _STATE = CreateFrame("Frame", nil, nil, "SecureHandlerStateTemplate")
local oUF = {}
local event_metatable = {
	__call = function(funcs, self, ...)
		for _, func in next, funcs do
			func(self, ...)
		end
	end,
}

local styles, style = {}
local callback, units, objects = {}, {}, {}

local select  = select
local UnitExists = UnitExists

local conv = {
	['playerpet'] = 'pet',
	['playertarget'] = 'target',
}
local elements = {}

local enableTargetUpdate = function(object)
	-- updating of "invalid" units.
	local OnTargetUpdate
	do
		local timer = 0
		OnTargetUpdate = function(self, elapsed)
			if(not self.unit) then
				return
			elseif(timer >= .5) then
				self:PLAYER_ENTERING_WORLD'OnTargetUpdate'
				timer = 0
			end

			timer = timer + elapsed
		end
	end

	object:SetScript("OnUpdate", OnTargetUpdate)
end

-- Events
local OnEvent = function(self, event, ...)
	if(not self:IsShown()) then return end
	return self[event](self, event, ...)
end

local iterateChildren = function(...)
	for l = 1, select("#", ...) do
		local obj = select(l, ...)

		if(type(obj) == 'table' and obj.isChild) then
			local unit = SecureButton_GetModifiedUnit(obj)
			local subUnit = conv[unit] or unit
			units[subUnit] = obj
			obj.unit = subUnit
			obj:PLAYER_ENTERING_WORLD"PLAYER_ENTERING_WORLD"
		end
	end
end

local OnAttributeChanged = function(self, name, value)
	if(name == "unit" and value) then
		units[value] = self

		if(self.unit and self.unit == value) then
			return
		else
			if(self.hasChildren) then
				iterateChildren(self:GetChildren())
			end

			self.unit = SecureButton_GetModifiedUnit(self)
			self.id = value:match"^.-(%d+)"
			self:PLAYER_ENTERING_WORLD"PLAYER_ENTERING_WORLD"
		end
	end
end

do
	local HandleFrame = function(baseName)
		local frame = _G[baseName]
		if(frame) then
			frame:UnregisterAllEvents()
			frame.Show = dummy
			frame:Hide()

			local health = frame.healthbar
			if(health) then
				health:UnregisterAllEvents()
			end

			local power = frame.manabar
			if(power) then
				power:UnregisterAllEvents()
			end

			local spell = frame.spellbar
			if(spell) then
				spell:UnregisterAllEvents()
			end
		end
	end

	function oUF:DisableBlizzard(unit, object)
		if(not unit) then return end

		local baseName
		if(unit == 'player') then
			baseName = 'PlayerFrame'
		elseif(unit == 'pet') then
			baseName = 'PetFrame'
		elseif(unit == 'target') then
			if(object) then
				object:RegisterEvent('PLAYER_TARGET_CHANGED', 'PLAYER_ENTERING_WORLD')
			end

			HandleFrame'TargetFrame'
			return HandleFrame'ComboFrame'
		elseif(unit == 'mouseover') then
			if(object) then
				return object:RegisterEvent('UPDATE_MOUSEOVER_UNIT', 'PLAYER_ENTERING_WORLD')
			end
		elseif(unit == 'focus') then
			if(object) then
				object:RegisterEvent('PLAYER_FOCUS_CHANGED', 'PLAYER_ENTERING_WORLD')
			end

			baseName = 'FocusFrame'
		elseif(unit:match'%w+target') then
			if(unit == 'targettarget') then
				baseName = 'TargetFrameToTManaBar'
			end

			enableTargetUpdate(object)
		elseif(unit:match'(boss)%d?$' == 'boss') then
			enableTargetUpdate(object)

			local id = unit:match'boss(%d)'
			if(id) then
				baseName = 'Boss' .. id .. 'TargetFrame'
			else
				HandleFrame'Boss1TargetFrame'
				HandleFrame'Boss2TargetFrame'
				return HandleFrame'Boss3TargetFrame'
			end
		elseif(unit:match'(party)%d?$' == 'party') then
			local id = unit:match'party(%d)'
			if(id) then
				baseName = 'PartyMemberFrame' .. id
			else
				HandleFrame'PartyMemberFrame1'
				HandleFrame'PartyMemberFrame2'
				HandleFrame'PartyMemberFrame3'
				return HandleFrame'PartyMemberFrame4'
			end
		end

		if(baseName) then
			return HandleFrame(baseName)
		end
	end
end

local frame_metatable = {
	__index = CreateFrame"Button"
}

for k, v in pairs{
	colors = colors;

	EnableElement = function(self, name, unit)
		argcheck(name, 2, 'string')
		argcheck(unit, 3, 'string', 'nil')

		local element = elements[name]
		if(not element) then return end

		if(element.enable(self, unit or self.unit)) then
			table.insert(self.__elements, element.update)
		end
	end,

	DisableElement = function(self, name)
		argcheck(name, 2, 'string')
		local element = elements[name]
		if(not element) then return end

		for k, update in next, self.__elements do
			if(update == element.update) then
				table.remove(self.__elements, k)

				-- We need to run a new update cycle incase we knocked ourself out of sync.
				-- The main reason we do this is to make sure the full update is completed
				-- if an element for some reason removes itself _during_ the update
				-- progress.
				self:PLAYER_ENTERING_WORLD('DisableElement', name)
				break
			end
		end

		return element.disable(self)
	end,

	UpdateElement = function(self, name)
		argcheck(name, 2, 'string')
		local element = elements[name]
		if(not element) then return end

		element.update(self, 'UpdateElement', self.unit)
	end,

	Enable = RegisterUnitWatch,
	Disable = function(self)
		UnregisterUnitWatch(self)
		self:Hide()
	end,

	--[[
	--:PLAYER_ENTERING_WORLD()
	--	Notes:
	--		- Does a full update of all elements on the object.
	--]]
	PLAYER_ENTERING_WORLD = function(self, event)
		local unit = self.unit
		if(not UnitExists(unit)) then return end

		for _, func in next, self.__elements do
			func(self, event, unit)
		end
	end,
} do
	frame_metatable.__index[k] = v
end

do
	local RegisterEvent = frame_metatable.__index.RegisterEvent
	function frame_metatable.__index:RegisterEvent(event, func)
		argcheck(event, 2, 'string')

		if(type(func) == 'string' and type(self[func]) == 'function') then
			func = self[func]
		end

		local curev = self[event]
		if(curev and func) then
			if(type(curev) == 'function') then
				self[event] = setmetatable({curev, func}, event_metatable)
			else
				for _, infunc in next, curev do
					if(infunc == func) then return end
				end

				table.insert(curev, func)
			end
		elseif(self:IsEventRegistered(event)) then
			return
		else
			if(func) then
				self[event] = func
			elseif(not self[event]) then
				return error("Handler for event [%s] on unit [%s] does not exist.", event, self.unit or 'unknown')
			end

			RegisterEvent(self, event)
		end
	end
end

do
	local UnregisterEvent = frame_metatable.__index.UnregisterEvent
	function frame_metatable.__index:UnregisterEvent(event, func)
		argcheck(event, 2, 'string')

		local curev = self[event]
		if(type(curev) == 'table' and func) then
			for k, infunc in next, curev do
				if(infunc == func) then
					curev[k] = nil

					if(#curev == 0) then
						table.remove(curev, k)
						UnregisterEvent(self, event)
					end

					break
				end
			end
		else
			self[event] = nil
			UnregisterEvent(self, event)
		end
	end
end

do
	local inf = math.huge
	-- http://www.wowwiki.com/ColorGradient
	function frame_metatable.__index.ColorGradient(perc, ...)
		if perc >= 1 then
			local r, g, b = select(select('#', ...) - 2, ...)
			return r, g, b
		elseif perc <= 0 then
			local r, g, b = ...
			return r, g, b
		end

		local num = select('#', ...) / 3

		-- Translate divison by zeros into 0, so we don't blow select.
		-- We check perc against itself because we rely on the fact that NaN can't equal NaN.
		if(perc ~= perc or perc == inf) then perc = 0 end
		local segment, relperc = math.modf(perc*(num-1))
		local r1, g1, b1, r2, g2, b2 = select((segment*3)+1, ...)

		return r1 + (r2-r1)*relperc, g1 + (g2-g1)*relperc, b1 + (b2-b1)*relperc
	end
end

local initObject = function(unit, style, styleFunc, ...)
	local num = select('#', ...)
	for i=1, num do
		local object = select(i, ...)

		object.__elements = {}

		object = setmetatable(object, frame_metatable)
		styleFunc(object, unit)

		local mt = type(styleFunc) == 'table'
		local height = object:GetAttribute'initial-height' or (mt and styleFunc['initial-height'])
		local width = object:GetAttribute'initial-width' or (mt and styleFunc['initial-width'])
		local scale = object:GetAttribute'initial-scale' or (mt and styleFunc['initial-scale'])
		local suffix = object:GetAttribute'unitsuffix'

		if(height) then
			object:SetAttribute('initial-height', height)
			if(unit) then object:SetHeight(height) end
		end

		if(width) then
			object:SetAttribute("initial-width", width)
			if(unit) then object:SetWidth(width) end
		end

		if(scale) then
			object:SetAttribute("initial-scale", scale)
			if(unit) then object:SetScale(scale) end
		end

		local parent = (i == 1) and object:GetParent()
		local showPlayer
		if(parent) then
			showPlayer = parent:GetAttribute'showPlayer' or parent:GetAttribute'showSolo'
		end

		if(num > 1) then
			if(i == 1) then
				object.hasChildren = true
			else
				object.isChild = true
			end
		end

		object.style = style

		if(suffix and suffix:match'target' and (i ~= 1 and not showPlayer)) then
			enableTargetUpdate(object)
		else
			object:SetScript("OnEvent", OnEvent)
		end

		object:SetAttribute("*type1", "target")
		object:SetScript("OnAttributeChanged", OnAttributeChanged)
		object:SetScript("OnShow",  object.PLAYER_ENTERING_WORLD)

		object:RegisterEvent"PLAYER_ENTERING_WORLD"

		for element in next, elements do
			object:EnableElement(element, unit)
		end

		for _, func in next, callback do
			func(object)
		end

		-- We could use ClickCastFrames only, but it will probably contain frames that
		-- we don't care about.
		table.insert(objects, object)
		_G.ClickCastFrames = ClickCastFrames or {}
		ClickCastFrames[object] = true
	end
end

local walkObject = function(object, unit)
	local style = object:GetParent().style or style
	local styleFunc = styles[style] or styles[style]

	initObject(unit, style, styleFunc, object, object:GetChildren())
end

function oUF:RegisterInitCallback(func)
	table.insert(callback, func)
end

function oUF:RegisterStyle(name, func)
	argcheck(name, 2, 'string')
	argcheck(func, 3, 'function', 'table')

	if(styles[name]) then return error("Style [%s] already registered.", name) end
	if(not style) then style = name end

	styles[name] = func
end

function oUF:SetActiveStyle(name)
	argcheck(name, 2, 'string')
	if(not styles[name]) then return error("Style [%s] does not exist.", name) end

	style = name
end

function oUF:SpawnHeader(overrideName, template, showSolo, showParty, showRaid)
	if(not style) then return error("Unable to create frame. No styles have been registered.") end

	template = (template or 'SecureGroupHeaderTemplate')

	local name = overrideName
	local header = CreateFrame('Frame', name, UIParent, template)
	header.initialConfigFunction = walkObject
	header.style = style
	header.SetManyAttributes = SetManyAttributes

	header:SetAttribute("template", "SecureUnitButtonTemplate")

	if(showSolo) then
		header:SetAttribute('visibleSolo', true)
	end

	if(showParty) then
		header:SetAttribute('visibleParty', true)
		self:DisableBlizzard'party'
	end

	if(showRaid) then
		header:SetAttribute('visibleRaid', true)
	end

	local state = 'oUF:' .. style .. '-' .. name
	_STATE:SetFrameRef(state, header)
	_STATE:SetAttribute('_onstate-' .. state, _STATEFORMAT:format(state))
	RegisterStateDriver(_STATE, state, '[group:raid] raid; [group:party] party; solo')

	return header
end

function oUF:Spawn(unit, overrideName)
	argcheck(unit, 2, 'string')
	if(not style) then return error("Unable to create frame. No styles have been registered.") end

	unit = unit:lower()

	local name = overrideName
	local object = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
	object.unit = unit
	object.id = unit:match"^.-(%d+)"

	units[unit] = object
	walkObject(object, unit)

	object:SetAttribute("unit", unit)
	RegisterUnitWatch(object)

	self:DisableBlizzard(unit, object)

	return object
end

function oUF:AddElement(name, update, enable, disable)
	argcheck(name, 2, 'string')
	argcheck(update, 3, 'function', 'nil')
	argcheck(enable, 4, 'function', 'nil')
	argcheck(disable, 5, 'function', 'nil')

	if(elements[name]) then return error('Element [%s] is already registered.', name) end
	elements[name] = {
		update = update;
		enable = enable;
		disable = disable;
	}
end

oUF.version = _VERSION
oUF.units = units
oUF.objects = objects
oUF.colors = colors

-- Temporary stuff, hopefully
oUF.frame_metatable = frame_metatable
oUF.ColorGradient = frame_metatable.__index.ColorGradient

if(global) then
	if(parent ~= 'oUF' and global == 'oUF' and IsAddOnLoaded'oUF') then
		error("%s attempted to override oUF's default global with its internal oUF.", parent)
	else
		_G[global] = oUF
	end
end
ns.oUF = oUF
