--[[
	PoseAnimator — procedural keyframe animation for R15 characters.

	Works without uploading any animation assets: each client offsets the R15
	Motor6D.C0 joints toward keyframed poses (with easing, blending, crouch
	solving and "power shake"). The player's normal R15 animations keep running
	underneath, so the moves blend in and out of idle/walk naturally.

	Every client animates every character locally, so all players see the
	moves smoothly (C0 changes are never sent over the network).
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local PoseAnimator = {}

-- Motor6D name -> the body part it lives in (standard R15 rig).
local JOINTS = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	LeftElbow = "LeftLowerArm",
	LeftWrist = "LeftHand",
	RightShoulder = "RightUpperArm",
	RightElbow = "RightLowerArm",
	RightWrist = "RightHand",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
}
PoseAnimator.Joints = JOINTS

local IDENTITY = CFrame.identity
local SIDES = { "Left", "Right" }

local rigs = setmetatable({}, { __mode = "k" })
local playing = {}
local connection: RBXScriptConnection? = nil

local function ease(alpha: number, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): number
	if alpha <= 0 then
		return 0
	elseif alpha >= 1 then
		return 1
	end
	return TweenService:GetValue(alpha, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut)
end

local Rig = {}
Rig.__index = Rig

function Rig:isValid(): boolean
	if not self.character.Parent then
		return false
	end
	for _, motor in self.motors do
		if not motor.Parent then
			return false
		end
	end
	return true
end

function Rig:refreshBase()
	for name, motor in self.motors do
		self.base[name] = motor.C0
	end
	self:measureLegs()
	table.clear(self.cache)
end

function Rig:measureLegs()
	local hip, knee, ankle = self.motors.LeftHip, self.motors.LeftKnee, self.motors.LeftAnkle
	if hip and knee then
		self.thigh = math.clamp((hip.C1.Position - knee.C0.Position).Magnitude, 0.3, 5)
	end
	if knee and ankle then
		self.shin = math.clamp((knee.C1.Position - ankle.C0.Position).Magnitude, 0.3, 5)
	end
end

-- Converts a pose description into joint offsets for this specific rig.
-- Supports `crouch` (degrees): bends hips/knees/ankles and lowers the root
-- so the feet stay planted, using this avatar's real leg lengths.
function Rig:resolve(pose)
	local cached = self.cache[pose]
	if cached then
		return cached
	end
	local out = {}
	for key, value in pose do
		if typeof(value) == "CFrame" then
			out[key] = value
		end
	end
	local crouch = pose.crouch
	if crouch and crouch ~= 0 then
		local a = math.rad(crouch)
		local drop = (self.thigh + self.shin) * (1 - math.cos(a))
		out.Root = CFrame.new(0, -drop, 0) * (out.Root or IDENTITY)
		for _, side in SIDES do
			out[side .. "Hip"] = (out[side .. "Hip"] or IDENTITY) * CFrame.Angles(a, 0, 0)
			out[side .. "Knee"] = (out[side .. "Knee"] or IDENTITY) * CFrame.Angles(-2 * a, 0, 0)
			out[side .. "Ankle"] = (out[side .. "Ankle"] or IDENTITY) * CFrame.Angles(a, 0, 0)
		end
	end
	self.cache[pose] = out
	return out
end

function Rig:sample(track, t: number)
	local keys = track.sequence.keys
	local first = keys[1]
	local fromPose, toPose, alpha, fromShake, toShake

	if t < first.t then
		fromPose = track.from
		toPose = self:resolve(first.pose)
		alpha = ease(t / first.t, first.style, first.dir)
		fromShake = track.fromShake
		toShake = first.pose.shake or 0
	else
		local k0, k1 = keys[#keys], nil
		for i = 1, #keys - 1 do
			if t < keys[i + 1].t then
				k0, k1 = keys[i], keys[i + 1]
				break
			end
		end
		fromPose = self:resolve(k0.pose)
		fromShake = k0.pose.shake or 0
		if k1 then
			toPose = self:resolve(k1.pose)
			toShake = k1.pose.shake or 0
			alpha = ease((t - k0.t) / (k1.t - k0.t), k1.style, k1.dir)
		else
			toPose = fromPose
			toShake = fromShake
			alpha = 1
		end
	end

	local out = {}
	for name in self.motors do
		local a = fromPose[name]
		local b = toPose[name]
		if a or b then
			out[name] = (a or IDENTITY):Lerp(b or IDENTITY, alpha)
		end
	end
	local shakeAlpha = math.clamp(alpha, 0, 1)
	return out, fromShake + (toShake - fromShake) * shakeAlpha
end

function Rig:apply(offsets, shake: number, t: number)
	if shake > 0.01 then
		local s = self.seed
		local r = math.rad(shake) * 2
		local n1 = math.noise(t * 17.3, s, 0.5)
		local n2 = math.noise(s, t * 19.1, 1.5)
		local n3 = math.noise(t * 15.7, 2.5, s)
		offsets.Waist = (offsets.Waist or IDENTITY) * CFrame.Angles(n1 * r, n2 * r, n3 * r * 0.6)
		offsets.Neck = (offsets.Neck or IDENTITY) * CFrame.Angles(n2 * r * 0.8, n3 * r, n1 * r * 0.5)
		offsets.RightShoulder = (offsets.RightShoulder or IDENTITY) * CFrame.Angles(n3 * r * 0.5, 0, n1 * r * 0.5)
		offsets.LeftShoulder = (offsets.LeftShoulder or IDENTITY) * CFrame.Angles(n1 * r * 0.5, 0, n2 * r * 0.5)
	end
	for name, motor in self.motors do
		local offset = offsets[name]
		if offset then
			motor.C0 = self.base[name] * offset
		elseif self.current[name] then
			motor.C0 = self.base[name]
		end
	end
	self.current = offsets
end

function Rig:restore()
	for name, motor in self.motors do
		if motor.Parent then
			motor.C0 = self.base[name]
		end
	end
	self.current = {}
end

-- Returns false once the track has fully blended out.
function Rig:step(now: number): boolean
	local track = self.track
	local sequence = track.sequence
	local t = (now - track.start) * track.speed
	local duration = track.cutoff or sequence.duration
	local offsets, shake

	if t < duration then
		offsets, shake = self:sample(track, t)
		track.last = table.clone(offsets)
		track.lastShake = shake
	else
		local blend = track.blendOut or sequence.blendOut or 0.3
		local a = if blend > 0 then (t - duration) / blend else 1
		if a >= 1 then
			self:restore()
			self.track = nil
			return false
		end
		a = ease(a, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		offsets = {}
		for name, cf in track.last or {} do
			offsets[name] = cf:Lerp(IDENTITY, a)
		end
		shake = (track.lastShake or 0) * (1 - a)
	end

	self:apply(offsets, shake, t)
	return true
end

function Rig:play(sequence, options)
	options = options or {}
	if not self.track and next(self.current) == nil then
		self:refreshBase()
	end
	local track = {
		sequence = sequence,
		start = os.clock(),
		speed = options.speed or 1,
		from = table.clone(self.current),
		fromShake = 0,
		last = nil,
		lastShake = 0,
		cutoff = nil,
		blendOut = nil,
	}
	if self.track then
		track.fromShake = self.track.lastShake or 0
	end
	self.track = track
	playing[self] = true
	PoseAnimator._ensureLoop()
	return track
end

-- Ends the current move early, blending back to normal animation.
function Rig:stop(fade: number?)
	local track = self.track
	if not track then
		return
	end
	local t = (os.clock() - track.start) * track.speed
	track.cutoff = math.min(t, track.cutoff or track.sequence.duration)
	track.blendOut = fade or 0.2
end

function Rig:isPlaying(sequence): boolean
	return self.track ~= nil and (sequence == nil or self.track.sequence == sequence)
end

local function onStep()
	local now = os.clock()
	for rig in playing do
		if rig.track and rig:isValid() then
			local ok, alive = pcall(rig.step, rig, now)
			if not ok or not alive then
				if not ok then
					warn("[PoseAnimator]", alive)
					rig:restore()
					rig.track = nil
				end
				playing[rig] = nil
			end
		else
			rig.track = nil
			playing[rig] = nil
		end
	end
	if next(playing) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

function PoseAnimator._ensureLoop()
	if not connection then
		connection = RunService.PreRender:Connect(onStep)
	end
end

-- Returns the rig controller for an R15 character (or nil for R6 / broken rigs).
function PoseAnimator.getRig(character: Model?)
	if not character then
		return nil
	end
	local existing = rigs[character]
	if existing then
		if existing:isValid() then
			return existing
		end
		rigs[character] = nil
		playing[existing] = nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil
	end
	local motors, base = {}, {}
	for jointName, partName in JOINTS do
		local part = character:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(jointName)
		if motor and motor:IsA("Motor6D") then
			motors[jointName] = motor
			base[jointName] = motor.C0
		end
	end
	if not motors.Root or not motors.Waist then
		return nil
	end
	local rig = setmetatable({
		character = character,
		humanoid = humanoid,
		motors = motors,
		base = base,
		current = {},
		track = nil,
		cache = {},
		thigh = 1,
		shin = 1,
		seed = math.random() * 1000,
	}, Rig)
	rig:measureLegs()
	rigs[character] = rig
	return rig
end

-- Convenience: play a sequence on a character. Returns the track or nil.
function PoseAnimator.play(character: Model?, sequence, options)
	if not sequence then
		return nil
	end
	local rig = PoseAnimator.getRig(character)
	if not rig then
		return nil
	end
	return rig:play(sequence, options)
end

function PoseAnimator.stop(character: Model?, fade: number?)
	local rig = character and rigs[character]
	if rig then
		rig:stop(fade)
	end
end

return PoseAnimator
