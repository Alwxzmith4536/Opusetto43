-- Mahoraga's wheel. Pure logic (no Roblox APIs) so it can be unit tested outside Studio.
--
-- Canon behaviour modelled here:
--   * The first hits of a new phenomenon land at full strength.
--   * Each time the wheel turns, Mahoraga takes less damage from that phenomenon.
--   * Once fully adapted it barely takes damage from it, heals, and can counter it.
--   * Adaptation is per phenomenon, so switching techniques is the way to win.

local Adaptation = {}
Adaptation.__index = Adaptation

-- cfg needs HitsPerTurn, TurnsToAdapt, ReductionPerTurn, AdaptedMultiplier
function Adaptation.new(cfg)
	local self = setmetatable({}, Adaptation)
	self.Config = cfg
	self.Hits = {} -- [type] = hits since last turn
	self.Turns = {} -- [type] = wheel turns so far
	self.Adapted = {} -- [type] = true
	self.TotalTurns = 0 -- used to rotate the wheel model
	self.Order = {} -- types in the order they were first seen (for the UI)
	return self
end

function Adaptation:Multiplier(damageType)
	if self.Adapted[damageType] then
		return self.Config.AdaptedMultiplier
	end
	local turns = self.Turns[damageType] or 0
	return math.max(self.Config.AdaptedMultiplier, 1 - turns * self.Config.ReductionPerTurn)
end

function Adaptation:IsAdapted(damageType)
	return self.Adapted[damageType] == true
end

function Adaptation:AdaptedCount()
	local n = 0
	for _ in pairs(self.Adapted) do
		n += 1
	end
	return n
end

-- Registers one hit. Returns:
--   multiplier (to apply to THIS hit), turned (wheel turned), completed (just became adapted)
function Adaptation:RegisterHit(damageType)
	local multiplier = self:Multiplier(damageType)
	if self.Adapted[damageType] then
		return multiplier, false, false
	end
	if self.Turns[damageType] == nil then
		self.Turns[damageType] = 0
		table.insert(self.Order, damageType)
	end

	local hits = (self.Hits[damageType] or 0) + 1
	local turned, completed = false, false
	if hits >= self.Config.HitsPerTurn then
		hits = 0
		turned = true
		self.TotalTurns += 1
		self.Turns[damageType] += 1
		if self.Turns[damageType] >= self.Config.TurnsToAdapt then
			self.Adapted[damageType] = true
			completed = true
		end
	end
	self.Hits[damageType] = hits
	return multiplier, turned, completed
end

-- 0..TurnsToAdapt for the UI
function Adaptation:Progress(damageType)
	return self.Turns[damageType] or 0
end

return Adaptation
