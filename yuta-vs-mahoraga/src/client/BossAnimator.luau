--!strict
--[[
	Animates Mahoraga on every client by driving its Motor6D transforms from the
	server's animation state (the JJK_Anim / JJK_AnimT attributes). No animation
	assets needed: every pose is procedural and blended with springs.

	Angles are in degrees: P(pitch, yaw, roll). For a hanging limb, +pitch swings
	it forward, +roll swings it toward +X (the rig's right).
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local BossAnimator = {}

type Pose = { [string]: CFrame }
type Rig = {
	Model: Model,
	Root: BasePart?,
	Motors: { [string]: Motor6D },
	MotorCount: number,
	Current: { [string]: CFrame },
	WalkPhase: number,
	WheelAngle: number,
	WheelFrom: number,
	WheelTo: number,
	WheelT0: number,
	Turns: number,
	AdaptT0: number,
}

local rigs: { [Model]: Rig } = {}

local function P(pitch: number, yaw: number?, roll: number?): CFrame
	return CFrame.Angles(0, math.rad(yaw or 0), 0) * CFrame.Angles(math.rad(pitch), 0, 0) * CFrame.Angles(0, 0, math.rad(roll or 0))
end

local function T(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

local function merge(base: Pose, over: Pose): Pose
	for k, v in over do
		base[k] = v
	end
	return base
end

local function stance(now: number): Pose
	local b = math.sin(now * 1.6)
	return {
		Root = T(0, -0.35 + b * 0.08, 0),
		Waist = P(-4 + b * 1.2),
		Neck = P(3),
		RightShoulder = P(14, 0, 12),
		RightElbow = P(40),
		RightWrist = P(-8),
		LeftShoulder = P(8, 0, -12),
		LeftElbow = P(22),
		LeftWrist = P(0),
		RightHip = P(8, 0, 3),
		RightKnee = P(-14),
		RightAnkle = P(6),
		LeftHip = P(8, 0, -3),
		LeftKnee = P(-14),
		LeftAnkle = P(6),
	}
end

-- k = stride strength (0 idle .. ~1.6 sprint)
local function walk(now: number, phase: number, k: number): Pose
	local s, c = math.sin(phase), math.cos(phase)
	local amp = 28 * k
	local pose = stance(now)
	return merge(pose, {
		Root = T(0, -0.35 - 0.4 * k + math.abs(c) * 0.7 * k, 0) * P(0, s * 5 * k),
		Waist = P(-4 - 6 * k, -s * 9 * k),
		Neck = P(3 + 2 * k, s * 5 * k),
		RightShoulder = P(14 - s * amp * 0.7, 0, 12),
		RightElbow = P(40 + math.max(0, -s) * 15 * k),
		LeftShoulder = P(8 + s * amp * 0.7, 0, -12),
		LeftElbow = P(22 + math.max(0, s) * 15 * k),
		RightHip = P(8 + s * amp, 0, 3),
		RightKnee = P(-14 - math.max(0, c) * 45 * k),
		RightAnkle = P(6 + math.max(0, c) * 10 * k),
		LeftHip = P(8 - s * amp, 0, -3),
		LeftKnee = P(-14 - math.max(0, -c) * 45 * k),
		LeftAnkle = P(6 + math.max(0, -c) * 10 * k),
	})
end

-- Each attack state returns its target pose (layered over the stance) and a blend rate.
local STATES: { [string]: (number, number) -> (Pose, number) } = {
	SweepWindup = function()
		return {
			Root = T(0, -1.2, 0),
			Waist = P(-6, 32),
			Neck = P(0, -20),
			RightShoulder = P(85, 75, 0),
			RightElbow = P(30),
			LeftShoulder = P(30, 0, -35),
			LeftElbow = P(40),
			RightHip = P(20, 0, 6),
			RightKnee = P(-30),
			LeftHip = P(-5, 0, -6),
			LeftKnee = P(-20),
		},
			9
	end,
	Sweep = function()
		return {
			Root = T(0, -1.4, 0),
			Waist = P(-10, -38),
			Neck = P(0, 15),
			RightShoulder = P(85, -95, 0),
			RightElbow = P(5),
			LeftShoulder = P(20, 0, -45),
			RightHip = P(-5, 0, 6),
			RightKnee = P(-20),
			LeftHip = P(20, 0, -6),
			LeftKnee = P(-30),
		},
			24
	end,
	CleaveWindup = function()
		return {
			Root = T(0, -0.6, 0),
			Waist = P(12, 8),
			Neck = P(10),
			RightShoulder = P(170, 5, 12),
			RightElbow = P(45),
			LeftShoulder = P(60, 0, -25),
			LeftElbow = P(50),
			RightHip = P(-5),
			LeftHip = P(25),
			LeftKnee = P(-30),
		},
			9
	end,
	Cleave = function()
		return {
			Root = T(0, -2.2, 0),
			Waist = P(-32),
			Neck = P(-12),
			RightShoulder = P(35, 0, 6),
			RightElbow = P(0),
			LeftShoulder = P(-10, 0, -30),
			RightHip = P(35),
			RightKnee = P(-55),
			LeftHip = P(-10),
			LeftKnee = P(-25),
		},
			26
	end,
	PunchWindupR = function()
		return { Root = T(0, -0.9, 0), Waist = P(-6, -28), RightShoulder = P(25, 0, 30), RightElbow = P(115), LeftShoulder = P(55, 0, -10), LeftElbow = P(70) }, 12
	end,
	PunchR = function()
		return {
			Root = T(0, -1.1, 0),
			Waist = P(-12, 26),
			RightShoulder = P(90, 12, 0),
			RightElbow = P(4),
			LeftShoulder = P(20, 0, -18),
			LeftElbow = P(90),
			RightHip = P(-8),
			LeftHip = P(22),
			LeftKnee = P(-25),
		},
			28
	end,
	PunchWindupL = function()
		return { Root = T(0, -0.9, 0), Waist = P(-6, 28), LeftShoulder = P(25, 0, -30), LeftElbow = P(115), RightShoulder = P(55, 0, 10), RightElbow = P(70) }, 12
	end,
	PunchL = function()
		return {
			Root = T(0, -1.1, 0),
			Waist = P(-12, -26),
			LeftShoulder = P(90, -12, 0),
			LeftElbow = P(4),
			RightShoulder = P(20, 0, 18),
			RightElbow = P(90),
			LeftHip = P(-8),
			RightHip = P(22),
			RightKnee = P(-25),
		},
			28
	end,
	StompWindup = function()
		return {
			Root = T(0, 0.2, 0),
			Waist = P(6),
			RightHip = P(78, 0, 6),
			RightKnee = P(-88),
			RightAnkle = P(20),
			LeftKnee = P(-8),
			RightShoulder = P(35, 0, 45),
			LeftShoulder = P(35, 0, -45),
			RightElbow = P(50),
			LeftElbow = P(50),
		},
			7
	end,
	Stomp = function()
		return {
			Root = T(0, -1.8, 0),
			Waist = P(-18),
			RightHip = P(10, 0, 6),
			RightKnee = P(-12),
			LeftHip = P(20),
			LeftKnee = P(-38),
			RightShoulder = P(25, 0, 30),
			LeftShoulder = P(25, 0, -30),
		},
			28
	end,
	LeapCrouch = function()
		return {
			Root = T(0, -3, 0),
			Waist = P(-26),
			Neck = P(10),
			RightHip = P(58, 0, 5),
			LeftHip = P(58, 0, -5),
			RightKnee = P(-100),
			LeftKnee = P(-100),
			RightAnkle = P(40),
			LeftAnkle = P(40),
			RightShoulder = P(-45, 0, 22),
			LeftShoulder = P(-45, 0, -22),
		},
			10
	end,
	LeapAir = function()
		return {
			Root = T(0, 0, 0),
			Waist = P(10),
			Neck = P(8),
			RightShoulder = P(165, 0, 22),
			LeftShoulder = P(155, 0, -22),
			RightElbow = P(20),
			LeftElbow = P(25),
			RightHip = P(35),
			RightKnee = P(-70),
			LeftHip = P(-12),
			LeftKnee = P(-30),
		},
			7
	end,
	LeapLand = function()
		return {
			Root = T(0, -2.8, 0),
			Waist = P(-30),
			Neck = P(-8),
			RightShoulder = P(45, 0, 16),
			RightElbow = P(10),
			LeftShoulder = P(10, 0, -40),
			RightHip = P(50, 0, 6),
			LeftHip = P(10, 0, -8),
			RightKnee = P(-85),
			LeftKnee = P(-60),
		},
			22
	end,
	RushWindup = function()
		return {
			Root = T(0, -1.6, 0),
			Waist = P(-30),
			Neck = P(14),
			RightShoulder = P(-35, 0, 25),
			LeftShoulder = P(-35, 0, -25),
			RightHip = P(45),
			RightKnee = P(-65),
			LeftHip = P(-12),
			LeftKnee = P(-32),
		},
			9
	end,
	Rush = function(e, now)
		return merge(walk(now, e * 16, 1.6), {
			Waist = P(-36),
			Neck = P(16),
			RightShoulder = P(-55, 0, 22),
			LeftShoulder = P(-55, 0, -22),
		}),
			16
	end,
	BurstWindup = function()
		return {
			Root = T(0, -1.2, 0),
			Waist = P(-16),
			Neck = P(-12),
			RightShoulder = P(72, 48),
			LeftShoulder = P(72, -48),
			RightElbow = P(70),
			LeftElbow = P(70),
			RightKnee = P(-30),
			LeftKnee = P(-30),
		},
			8
	end,
	Burst = function()
		return {
			Root = T(0, -0.4, 0),
			Waist = P(14),
			Neck = P(22),
			RightShoulder = P(10, 0, 105),
			LeftShoulder = P(10, 0, -105),
			RightElbow = P(5),
			LeftElbow = P(5),
		},
			18
	end,
	Stunned = function(_e, now)
		local shiver = math.sin(now * 40) * 1.5
		return {
			Root = T(0, -1.2, 0),
			Waist = P(-20 + shiver, 0, 6),
			Neck = P(-28, 10),
			RightShoulder = P(4, 0, 6),
			LeftShoulder = P(4, 0, -6),
			RightElbow = P(10),
			LeftElbow = P(10),
			RightKnee = P(-30),
			LeftKnee = P(-24),
		},
			6
	end,
	Summon = function()
		return {
			Root = T(0, -1, 0),
			Waist = P(-12),
			Neck = P(-22),
			RightShoulder = P(45, 62),
			LeftShoulder = P(45, -62),
			RightElbow = P(105),
			LeftElbow = P(105),
		},
			5
	end,
	Death = function()
		return {
			Root = T(0, -6.2, 0) * P(-8),
			Waist = P(-42),
			Neck = P(-32),
			RightHip = P(82, 0, 6),
			LeftHip = P(82, 0, -6),
			RightKnee = P(-105),
			LeftKnee = P(-105),
			RightAnkle = P(30),
			LeftAnkle = P(30),
			RightShoulder = P(8, 0, 10),
			LeftShoulder = P(8, 0, -10),
			RightElbow = P(12),
			LeftElbow = P(12),
		},
			2.5
	end,
}

local function backOut(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- Target joint transforms for an animation state (also used by tools/preview).
function BossAnimator.poseFor(state: string, elapsed: number, now: number): Pose
	local fn = STATES[state]
	if fn then
		local over = fn(elapsed, now)
		return merge(stance(now), over)
	end
	return stance(now)
end

local function refreshMotors(rig: Rig)
	if rig.MotorCount >= 16 then
		return
	end
	local count = 0
	for _, d in rig.Model:GetDescendants() do
		if d:IsA("Motor6D") then
			rig.Motors[d.Name] = d
			count += 1
		end
	end
	rig.MotorCount = count
	local root = rig.Model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		rig.Root = root
	end
end

local function step(dt: number)
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	for model, rig in rigs do
		if not model.Parent then
			rigs[model] = nil
			continue
		end
		refreshMotors(rig)

		local state = (model:GetAttribute("JJK_Anim") or "Move") :: string
		local elapsed = serverNow - ((model:GetAttribute("JJK_AnimT") or serverNow) :: number)
		local pose: Pose
		local rate: number
		if state == "Move" then
			local root = rig.Root
			local vel = if root then root.AssemblyLinearVelocity else Vector3.zero
			local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
			local k = math.clamp(speed / 20, 0, 1.3)
			if k < 0.08 then
				pose = stance(now)
				rate = 6
			else
				rig.WalkPhase += dt * speed * 0.45
				pose = walk(now, rig.WalkPhase, k)
				rate = 10
			end
			if now - rig.AdaptT0 < 0.9 then
				pose.Neck = P(22)
				pose.Waist = P(8)
			end
		else
			local fn = STATES[state]
			if fn then
				local over, r = fn(elapsed, now)
				pose = merge(stance(now), over)
				rate = r
			else
				pose = stance(now)
				rate = 6
			end
		end

		local alpha = 1 - math.exp(-rate * dt)
		for name, motor in rig.Motors do
			if name ~= "Wheel" then
				local target = pose[name] or CFrame.identity
				local current = (rig.Current[name] or CFrame.identity):Lerp(target, alpha)
				rig.Current[name] = current
				motor.Transform = current
			end
		end

		-- The Dharma wheel clicks round 45 degrees per adaptation step.
		local turns = (model:GetAttribute("JJK_WheelTurns") or 0) :: number
		if rig.Turns < 0 then
			rig.Turns = turns
			rig.WheelAngle = turns * math.pi / 4
			rig.WheelFrom, rig.WheelTo = rig.WheelAngle, rig.WheelAngle
		elseif turns ~= rig.Turns then
			rig.Turns = turns
			rig.WheelFrom = rig.WheelAngle
			rig.WheelTo = turns * math.pi / 4
			rig.WheelT0 = now
			rig.AdaptT0 = now
		end
		local a = math.clamp((now - rig.WheelT0) / 0.45, 0, 1)
		rig.WheelAngle = rig.WheelFrom + (rig.WheelTo - rig.WheelFrom) * backOut(a)
		local wheel = rig.Motors.Wheel
		if wheel then
			wheel.Transform = CFrame.new(0, math.sin(now * 2) * 0.15, 0)
				* CFrame.Angles(0, rig.WheelAngle, 0)
				* CFrame.Angles(math.rad(math.sin(now * 0.9) * 2), 0, math.rad(math.cos(now * 0.7) * 2))
		end
	end
end

local function track(inst: Instance)
	if not inst:IsA("Model") or rigs[inst] then
		return
	end
	rigs[inst] = {
		Model = inst,
		Root = nil,
		Motors = {},
		MotorCount = 0,
		Current = {},
		WalkPhase = 0,
		WheelAngle = 0,
		WheelFrom = 0,
		WheelTo = 0,
		WheelT0 = 0,
		Turns = -1,
		AdaptT0 = -10,
	}
end

function BossAnimator.start()
	CollectionService:GetInstanceAddedSignal("JJK_Mahoraga"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("JJK_Mahoraga"):Connect(function(inst)
		if inst:IsA("Model") then
			rigs[inst] = nil
		end
	end)
	for _, inst in CollectionService:GetTagged("JJK_Mahoraga") do
		track(inst)
	end
	RunService.Stepped:Connect(function(_time: number, dt: number)
		step(dt)
	end)
end

return BossAnimator
