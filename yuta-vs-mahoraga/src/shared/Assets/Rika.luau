--!strict
--[[
	Rika Orimoto, Queen of Curses, as Yuta's fully manifested cursed spirit.

	Built as three anchored sub-models so the client can animate her:
	  Body      pivot = chest centre, facing -Z
	  LeftArm   pivot = left shoulder (arm hangs along -Y)
	  RightArm  pivot = right shoulder
]]

local PartKit = require(script.Parent.PartKit)
local Palette = require(script.Parent.Parent.Palette)

local Rika = {}

local SKIN = Palette.RikaSkin
local SKIN_DARK = Color3.fromRGB(150, 142, 166)
local TAIL = Color3.fromRGB(96, 70, 120)
local HAIR = Color3.fromRGB(26, 20, 36)
local MOUTH = Color3.fromRGB(34, 8, 20)
local TOOTH = Color3.fromRGB(244, 240, 230)
local EYE = Color3.fromRGB(10, 8, 14)
local CLAW = Color3.fromRGB(22, 14, 28)

-- Shoulder pivots relative to the body pivot (multiply by scale).
Rika.Shoulders = {
	Left = Vector3.new(-3.1, 1.3, 0.2),
	Right = Vector3.new(3.1, 1.3, 0.2),
}

-- side: -1 = left arm, 1 = right arm.
function Rika.buildArm(parent: Instance?, pivot: CFrame, side: number, scale: number): Model
	local s = scale
	local arm = PartKit.model(if side < 0 then "LeftArm" else "RightArm", parent)
	local root = PartKit.part({
		Name = "Pivot",
		Parent = arm,
		CFrame = pivot,
		Size = Vector3.new(0.4, 0.4, 0.4) * s,
		Transparency = 1,
	})
	arm.PrimaryPart = root

	local function pt(x: number, y: number, z: number): Vector3
		return pivot * (Vector3.new(x, y, z) * s)
	end
	local function dir(x: number, y: number, z: number): Vector3
		return pivot.Rotation * (Vector3.new(x, y, z) * s)
	end

	local shoulder = pt(0, 0, 0)
	local elbow = pt(side * 0.55, -4.6, 0.3)
	local wrist = pt(side * 0.7, -8.8, -0.4)

	PartKit.ellipsoid({ Name = "Deltoid", Parent = arm, CFrame = CFrame.new(shoulder), Size = Vector3.new(2.4, 2.3, 2.3) * s, Color = SKIN })
	PartKit.limb({ Name = "UpperArm", Parent = arm, Color = SKIN }, shoulder, elbow, 1.75 * s)
	PartKit.ball(arm, CFrame.new(elbow), 1.45 * s, { Color = SKIN_DARK }, "Elbow")
	PartKit.limb({ Name = "Forearm", Parent = arm, Color = SKIN }, elbow, wrist, 1.6 * s)
	PartKit.ball(arm, CFrame.new(wrist), 1.2 * s, { Color = SKIN }, "Wrist")

	-- Huge hand with long black claws; fingers curl forward (-Z).
	local palm = wrist + dir(0, -1.3, -0.3)
	PartKit.ellipsoid({ Name = "Palm", Parent = arm, CFrame = CFrame.new(palm) * pivot.Rotation, Size = Vector3.new(2.7, 2.9, 1.2) * s, Color = SKIN })
	for i, fx in { -0.9, -0.3, 0.3, 0.9 } do
		local len = if i == 2 or i == 3 then 1.0 else 0.85
		local base = palm + dir(side * 0 + fx, -1.3, -0.1)
		local knuckle = base + dir(0, -1.6 * len, -0.35)
		local tipBase = knuckle + dir(0, -1.3 * len, -0.7)
		local tip = tipBase + dir(0, -0.9 * len, -1.3)
		PartKit.limb({ Name = "Finger", Parent = arm, Color = SKIN }, base, knuckle, 0.62 * s)
		PartKit.ball(arm, CFrame.new(knuckle), 0.5 * s, { Color = SKIN_DARK }, "Knuckle")
		PartKit.limb({ Name = "Finger", Parent = arm, Color = SKIN }, knuckle, tipBase, 0.52 * s)
		PartKit.limb({ Name = "Claw", Parent = arm, Color = CLAW, Material = Enum.Material.Glass }, tipBase, tip, 0.34 * s)
	end
	local thumbBase = palm + dir(-side * 1.2, -0.4, -0.3)
	local thumbMid = thumbBase + dir(-side * 0.8, -1.1, -0.6)
	local thumbTip = thumbMid + dir(-side * 0.3, -0.8, -1.0)
	PartKit.limb({ Name = "Thumb", Parent = arm, Color = SKIN }, thumbBase, thumbMid, 0.66 * s)
	PartKit.limb({ Name = "Claw", Parent = arm, Color = CLAW, Material = Enum.Material.Glass }, thumbMid, thumbTip, 0.36 * s)
	return arm
end

function Rika.build(parent: Instance?, cf: CFrame, scale: number): Model
	local s = scale
	local model = PartKit.model("Rika", parent)
	local body = PartKit.model("Body", model)
	local root = PartKit.part({
		Name = "Pivot",
		Parent = body,
		CFrame = cf,
		Size = Vector3.new(0.5, 0.5, 0.5) * s,
		Transparency = 1,
	})
	body.PrimaryPart = root
	model.PrimaryPart = root

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x * s, y * s, z * s)
	end
	local function pt(x: number, y: number, z: number): Vector3
		return cf * (Vector3.new(x, y, z) * s)
	end

	-- Torso
	PartKit.ellipsoid({ Name = "Chest", Parent = body, CFrame = at(0, 0, 0), Size = Vector3.new(5.9, 5.1, 4.1) * s, Color = SKIN })
	PartKit.ellipsoid({ Name = "Traps", Parent = body, CFrame = at(0, 1.8, 0.3), Size = Vector3.new(7.0, 2.3, 3.3) * s, Color = SKIN })
	PartKit.ellipsoid({ Name = "Back", Parent = body, CFrame = at(0, 0.3, 1.1), Size = Vector3.new(5.2, 4.8, 2.6) * s, Color = SKIN_DARK })
	PartKit.ellipsoid({ Name = "Belly", Parent = body, CFrame = at(0, -2.7, 0.3), Size = Vector3.new(4.9, 4.2, 3.7) * s, Color = SKIN })
	PartKit.part({ Name = "Sternum", Parent = body, CFrame = at(0, 0.1, -1.86), Size = Vector3.new(0.18, 2.6, 0.2) * s, Color = SKIN_DARK })
	for _, y in { 0.9, 0.05, -0.8 } do
		for _, side in { -1, 1 } do
			PartKit.part({
				Name = "Rib",
				Parent = body,
				CFrame = at(side * 1.25, y, -1.78) * CFrame.Angles(0, 0, math.rad(side * -14)),
				Size = Vector3.new(1.7, 0.16, 0.25) * s,
				Color = SKIN_DARK,
			})
		end
	end

	-- Wispy tail instead of legs; she floats.
	local tail = {
		{ at = Vector3.new(0, -5.0, 0.9), size = Vector3.new(3.9, 3.6, 3.1), color = SKIN_DARK, fade = 0 },
		{ at = Vector3.new(0, -6.9, 1.9), size = Vector3.new(2.8, 3.2, 2.4), color = TAIL, fade = 0.05 },
		{ at = Vector3.new(0, -8.6, 3.0), size = Vector3.new(1.9, 2.8, 1.8), color = TAIL, fade = 0.2 },
		{ at = Vector3.new(0, -10.1, 4.2), size = Vector3.new(1.1, 2.2, 1.1), color = TAIL, fade = 0.4 },
	}
	local tailEnd: Part? = nil
	for i, t in tail do
		tailEnd = PartKit.ellipsoid({
			Name = "Tail" .. i,
			Parent = body,
			CFrame = at(t.at.X, t.at.Y, t.at.Z),
			Size = t.size * s,
			Color = t.color,
			Transparency = t.fade,
		})
	end

	-- Head
	PartKit.ellipsoid({ Name = "Neck", Parent = body, CFrame = at(0, 3.0, -0.2), Size = Vector3.new(2.6, 2.4, 2.6) * s, Color = SKIN })
	local hd = at(0, 5.3, -0.7) * CFrame.Angles(math.rad(-8), 0, 0)
	local function h(x: number, y: number, z: number): CFrame
		return hd * CFrame.new(x * s, y * s, z * s)
	end
	PartKit.ellipsoid({ Name = "Head", Parent = body, CFrame = hd, Size = Vector3.new(5.6, 5.0, 4.8) * s, Color = SKIN })
	PartKit.ellipsoid({ Name = "Brow", Parent = body, CFrame = h(0, 1.55, -1.75), Size = Vector3.new(4.4, 0.75, 1.3) * s, Color = SKIN_DARK })
	for _, side in { -1, 1 } do
		PartKit.ellipsoid({ Name = "Eye", Parent = body, CFrame = h(side * 1.25, 0.75, -2.15), Size = Vector3.new(1.4, 1.8, 0.8) * s, Color = EYE, Reflectance = 0.3 })
		PartKit.ball(body, h(side * 1.2, 0.95, -2.55), 0.3 * s, { Color = Palette.White, Material = Enum.Material.Neon }, "Pupil")
		PartKit.ellipsoid({ Name = "Cheek", Parent = body, CFrame = h(side * 2.2, -0.6, -1.4), Size = Vector3.new(1.4, 1.8, 1.6) * s, Color = SKIN })
	end

	-- The grin: dark mouth, lips and two rows of teeth.
	PartKit.ellipsoid({ Name = "Mouth", Parent = body, CFrame = h(0, -1.05, -2.1), Size = Vector3.new(4.1, 1.6, 1.0) * s, Color = MOUTH })
	PartKit.ellipsoid({ Name = "UpperLip", Parent = body, CFrame = h(0, -0.3, -2.2), Size = Vector3.new(4.4, 0.5, 0.9) * s, Color = SKIN })
	PartKit.ellipsoid({ Name = "LowerLip", Parent = body, CFrame = h(0, -1.8, -2.15), Size = Vector3.new(3.9, 0.55, 0.9) * s, Color = SKIN })
	for i = 1, 9 do
		PartKit.part({
			Name = "Tooth",
			Parent = body,
			CFrame = h(-1.6 + (i - 1) * 0.4, -0.58, -2.55) * CFrame.Angles(0, 0, math.rad(45)),
			Size = Vector3.new(0.3, 0.3, 0.14) * s,
			Color = TOOTH,
		})
	end
	for i = 1, 8 do
		PartKit.part({
			Name = "Tooth",
			Parent = body,
			CFrame = h(-1.4 + (i - 1) * 0.4, -1.52, -2.5) * CFrame.Angles(0, 0, math.rad(45)),
			Size = Vector3.new(0.3, 0.3, 0.14) * s,
			Color = TOOTH,
		})
	end

	-- Crown of horns.
	for _, x in { -1.6, -0.8, 0, 0.8, 1.6 } do
		PartKit.limb({ Name = "Horn", Parent = body, Color = SKIN_DARK }, pt(x, 7.3, -0.8), pt(x * 1.3, 8.9 - 0.25 * math.abs(x), -0.4), 0.45 * s)
	end

	-- Long strands of hair flowing down her back.
	for i = 1, 14 do
		local a = math.rad(-120 + (i - 1) * (240 / 13))
		local root0 = pt(math.sin(a) * 2.3, 7.0 - 0.3 * math.abs(math.sin(a)), -0.2 + math.cos(a) * 1.8)
		local p1 = root0 + cf.Rotation * (Vector3.new(math.sin(a) * 0.9, -2.2, 1.1) * s)
		local p2 = p1 + cf.Rotation * (Vector3.new(math.sin(a) * 0.5, -2.6, 0.8) * s)
		local p3 = p2 + cf.Rotation * (Vector3.new(math.sin(a) * 0.3, -2.4, 0.5) * s)
		PartKit.limb({ Name = "Hair", Parent = body, Color = HAIR }, root0, p1, 0.6 * s)
		PartKit.limb({ Name = "Hair", Parent = body, Color = HAIR }, p1, p2, 0.48 * s)
		PartKit.limb({ Name = "Hair", Parent = body, Color = HAIR }, p2, p3, 0.32 * s)
	end

	PartKit.light(root, Palette.RikaAura, 22 * s, 2)
	if tailEnd then
		PartKit.emitter(tailEnd, {
			Name = "CurseSmoke",
			Texture = PartKit.Textures.Smoke,
			Color = ColorSequence.new(Palette.YutaDark, Palette.RikaAura),
			LightEmission = 0.3,
			Size = NumberSequence.new(2 * s, 4 * s),
			Transparency = NumberSequence.new(0.5, 1),
			Lifetime = NumberRange.new(0.8, 1.4),
			Rate = 14,
			Speed = NumberRange.new(1, 3),
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0, -2, 0),
		})
	end

	for _, side in { -1, 1 } do
		local offset = if side < 0 then Rika.Shoulders.Left else Rika.Shoulders.Right
		Rika.buildArm(model, cf * CFrame.new(offset * s), side, s)
	end
	return model
end

return Rika
