local parent, ns = ...
local oUF = ns.oUF
local CC = select(4, GetBuildInfo()) == 4e4

oUF.colors.health = {49/255, 207/255, 37/255}

local Update = function(self, event, unit, powerType)
	if(self.unit ~= unit or (event == 'UNIT_POWER' and powerType ~= 'HAPPINESS')) then return end
	local health = self.Health

	if(health.PreUpdate) then health:PreUpdate(unit) end

	local min, max = UnitHealth(unit), UnitHealthMax(unit)
	local disconnected = not UnitIsConnected(unit)
	health:SetMinMaxValues(0, max)

	if(disconnected) then
		health:SetValue(max)
	else
		health:SetValue(min)
	end

	health.disconnected = disconnected
	health.unit = unit

	local r, g, b, t
	if(health.colorTapping and UnitIsTapped(unit) and not UnitIsTappedByPlayer(unit)) then
		t = self.colors.tapped
	elseif(health.colorDisconnected and not UnitIsConnected(unit)) then
		t = self.colors.disconnected
	elseif(health.colorHappiness and UnitIsUnit(unit, "pet") and GetPetHappiness()) then
		t = self.colors.happiness[GetPetHappiness()]
	elseif(health.colorClass and UnitIsPlayer(unit)) or
		(health.colorClassNPC and not UnitIsPlayer(unit)) or
		(health.colorClassPet and UnitPlayerControlled(unit) and not UnitIsPlayer(unit)) then
		local _, class = UnitClass(unit)
		t = self.colors.class[class]
	elseif(health.colorReaction and UnitReaction(unit, 'player')) then
		t = self.colors.reaction[UnitReaction(unit, "player")]
	elseif(health.colorSmooth) then
		r, g, b = self.ColorGradient(min / max, unpack(health.smoothGradient or self.colors.smooth))
	elseif(health.colorHealth) then
		t = self.colors.health
	end

	if(t) then
		r, g, b = t[1], t[2], t[3]
	end

	if(b) then
		health:SetStatusBarColor(r, g, b)

		local bg = health.bg
		if(bg) then
			local mu = bg.multiplier or 1
			bg:SetVertexColor(r * mu, g * mu, b * mu)
		end
	end

	if(health.PostUpdate) then
		return health:PostUpdate(unit, min, max)
	end
end

local Path = function(self, ...)
	return (self.Health.Override or Update) (self, ...)
end

local OnHealthUpdate
do
	local UnitHealth = UnitHealth
	OnHealthUpdate = function(self)
		if(self.disconnected) then return end
		local health = UnitHealth(self.unit)

		if(health ~= self.min) then
			self.min = health

			return Path(self:GetParent(), "OnHealthUpdate", self.unit)
		end
	end
end

local Enable = function(self, unit)
	local health = self.Health
	if(health) then
		if(health.frequentUpdates and (unit and not unit:match'%w+target$')) then
			-- TODO 1.5: We should do this regardless of frequentUpdates.
			if(health:GetParent() ~= self) then
				return oUF.error('Element [%s] is incorrectly parented on [%s]. Expected self, got something else.', 'Health', unit)
			end

			health:SetScript('OnUpdate', OnHealthUpdate)

			-- The party frames need this to handle disconnect states correctly.
			if(unit == 'party') then
				self:RegisterEvent("UNIT_HEALTH", Path)
			end
		else
			self:RegisterEvent("UNIT_HEALTH", Path)
		end

		self:RegisterEvent("UNIT_MAXHEALTH", Path)

		if(CC) then
			self:RegisterEvent('UNIT_POWER', Path)
		else
			self:RegisterEvent('UNIT_HAPPINESS', Path)
		end

		-- For tapping.
		self:RegisterEvent('UNIT_FACTION', Path)

		if(not health:GetStatusBarTexture()) then
			health:SetStatusBarTexture[[Interface\TargetingFrame\UI-StatusBar]]
		end

		return true
	end
end

local Disable = function(self)
	local health = self.Health
	if(health) then
		if(health:GetScript'OnUpdate') then
			health:SetScript('OnUpdate', nil)
		end

		self:UnregisterEvent('UNIT_HEALTH', Path)
		self:UnregisterEvent('UNIT_MAXHEALTH', Path)

		if(CC) then
			self:UnregisterEvent('UNIT_POWER', Path)
		else
			self:UnregisterEvent('UNIT_HAPPINESS', Path)
		end

		self:UnregisterEvent('UNIT_FACTION', Path)
	end
end

oUF:AddElement('Health', Path, Enable, Disable)
