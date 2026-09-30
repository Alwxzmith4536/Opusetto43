--!strict
--[[
	Eight-Handled Sword Divergent Sila Divine General Mahoraga.

	A 29-stud rig built from parts: Motor6D joints so the client can animate it,
	the eight-handled Dharma wheel floating above its head (its adaptation wheel),
	two pairs of head wings over the eyes, and the Sword of Extermination fused to
	its right forearm.

	Built anchored and facing -Z with `cf` as the ground point under its feet.
	The server unanchors it when the fight starts.
]]

local PartKit = require(script.Parent.PartKit)
local Palette = require(script.Parent.Parent.Palette)

local Mahoraga = {}

Mahoraga.HipHeight = 10.7 -- bottom of HumanoidRootPart above the ground
Mahoraga.RootHeight = 13.2 -- centre of HumanoidRootPart above the ground
Mahoraga.HitRadius = 5.5
Mahoraga.HitHalfHeight = 14

local SKIN = Color3.fromRGB(231, 227, 219)
local SHADE = Color3.fromRGB(212, 205, 196)
local LIPS = Color3.fromRGB(118, 42, 48)
local WING = Color3.fromRGB(247, 246, 242)
local CLOTH = Color3.fromRGB(238, 236, 228)
local CLOTH_FOLD = Color3.fromRGB(214, 211, 202)
local ROPE = Color3.fromRGB(70, 58, 50)
local BLADE = Color3.fromRGB(214, 218, 228)
local GUARD = Color3.fromRGB(150, 118, 64)

type Limb = { name: string, center: Vector3, size: Vector3 }
type Joint = { name: string, part0: string, part1: string, pivot: Vector3 }

local LIMBS: { Limb } = {
	{ name = "LowerTorso", center = Vector3.new(0, 13.0, 0), size = Vector3.new(5.2, 2.8, 3.4) },
	{ name = "UpperTorso", center = Vector3.new(0, 17.5, 0), size = Vector3.new(6.8, 6.2, 3.8) },
	{ name = "Head", center = Vector3.new(0, 23.1, -0.2), size = Vector3.new(2.8, 3.2, 3.0) },
	{ name = "RightUpperArm", center = Vector3.new(4.55, 16.9, 0), size = Vector3.new(2.1, 5.6, 2.1) },
	{ name = "RightLowerArm", center = Vector3.new(4.6, 12.0, 0), size = Vector3.new(1.8, 4.8, 1.8) },
	{ name = "RightHand", center = Vector3.new(4.6, 8.7, -0.1), size = Vector3.new(1.5, 1.9, 1.2) },
	{ name = "LeftUpperArm", center = Vector3.new(-4.55, 16.9, 0), size = Vector3.new(2.1, 5.6, 2.1) },
	{ name = "LeftLowerArm", center = Vector3.new(-4.6, 12.0, 0), size = Vector3.new(1.8, 4.8, 1.8) },
	{ name = "LeftHand", center = Vector3.new(-4.6, 8.7, -0.1), size = Vector3.new(1.5, 1.9, 1.2) },
	{ name = "RightUpperLeg", center = Vector3.new(1.75, 9.3, 0), size = Vector3.new(2.5, 5.8, 2.5) },
	{ name = "RightLowerLeg", center = Vector3.new(1.8, 3.8, 0), size = Vector3.new(2.0, 5.2, 2.0) },
	{ name = "RightFoot", center = Vector3.new(1.8, 0.5, -0.5), size = Vector3.new(1.9, 1.0, 3.2) },
	{ name = "LeftUpperLeg", center = Vector3.new(-1.75, 9.3, 0), size = Vector3.new(2.5, 5.8, 2.5) },
	{ name = "LeftLowerLeg", center = Vector3.new(-1.8, 3.8, 0), size = Vector3.new(2.0, 5.2, 2.0) },
	{ name = "LeftFoot", center = Vector3.new(-1.8, 0.5, -0.5), size = Vector3.new(1.9, 1.0, 3.2) },
}

local JOINTS: { Joint } = {
	{ name = "Root", part0 = "HumanoidRootPart", part1 = "LowerTorso", pivot = Vector3.new(0, 13.0, 0) },
	{ name = "Waist", part0 = "LowerTorso", part1 = "UpperTorso", pivot = Vector3.new(0, 14.4, 0) },
	{ name = "Neck", part0 = "UpperTorso", part1 = "Head", pivot = Vector3.new(0, 21.2, -0.1) },
	{ name = "RightShoulder", part0 = "UpperTorso", part1 = "RightUpperArm", pivot = Vector3.new(4.4, 19.6, 0) },
	{ name = "RightElbow", part0 = "RightUpperArm", part1 = "RightLowerArm", pivot = Vector3.new(4.6, 14.3, 0) },
	{ name = "RightWrist", part0 = "RightLowerArm", part1 = "RightHand", pivot = Vector3.new(4.6, 9.6, -0.05) },
	{ name = "LeftShoulder", part0 = "UpperTorso", part1 = "LeftUpperArm", pivot = Vector3.new(-4.4, 19.6, 0) },
	{ name = "LeftElbow", part0 = "LeftUpperArm", part1 = "LeftLowerArm", pivot = Vector3.new(-4.6, 14.3, 0) },
	{ name = "LeftWrist", part0 = "LeftLowerArm", part1 = "LeftHand", pivot = Vector3.new(-4.6, 9.6, -0.05) },
	{ name = "RightHip", part0 = "LowerTorso", part1 = "RightUpperLeg", pivot = Vector3.new(1.75, 12.1, 0) },
	{ name = "RightKnee", part0 = "RightUpperLeg", part1 = "RightLowerLeg", pivot = Vector3.new(1.8, 6.4, 0) },
	{ name = "RightAnkle", part0 = "RightLowerLeg", part1 = "RightFoot", pivot = Vector3.new(1.8, 1.1, 0) },
	{ name = "LeftHip", part0 = "LowerTorso", part1 = "LeftUpperLeg", pivot = Vector3.new(-1.75, 12.1, 0) },
	{ name = "LeftKnee", part0 = "LeftUpperLeg", part1 = "LeftLowerLeg", pivot = Vector3.new(-1.8, 6.4, 0) },
	{ name = "LeftAnkle", part0 = "LeftLowerLeg", part1 = "LeftFoot", pivot = Vector3.new(-1.8, 1.1, 0) },
	{ name = "Wheel", part0 = "Head", part1 = "WheelCore", pivot = Vector3.new(0, 28.6, 0.2) },
}

Mahoraga.JointNames = {} :: { string }
for _, j in JOINTS do
	table.insert(Mahoraga.JointNames, j.name)
end

-- Adds a welded decoration to `limb`.
local function deco(limb: BasePart, props: PartKit.Props, ellipsoid: boolean?): Part
	props.Parent = limb.Parent
	local p = if ellipsoid then PartKit.ellipsoid(props) else PartKit.part(props)
	PartKit.weld(limb, p)
	return p
end

local function decoSegment(limb: BasePart, props: PartKit.Props, a: Vector3, b: Vector3, thickness: number, depth: number?): Part
	props.Parent = limb.Parent
	local p = PartKit.segment(props, a, b, thickness, depth)
	PartKit.weld(limb, p)
	return p
end

function Mahoraga.build(cf: CFrame): Model
	local model = PartKit.model("Mahoraga")
	local function at(v: Vector3): CFrame
		return cf * CFrame.new(v)
	end
	local function pt(x: number, y: number, z: number): Vector3
		return cf * Vector3.new(x, y, z)
	end

	local parts: { [string]: Part } = {}
	local hrp = PartKit.part({
		Name = "HumanoidRootPart",
		Parent = model,
		CFrame = at(Vector3.new(0, Mahoraga.RootHeight, 0)),
		Size = Vector3.new(5.4, 5, 3.4),
		Transparency = 1,
		CanCollide = true,
	})
	hrp.CustomPhysicalProperties = PhysicalProperties.new(100, 0.3, 0.5)
	parts.HumanoidRootPart = hrp
	model.PrimaryPart = hrp

	for _, limb in LIMBS do
		parts[limb.name] = PartKit.part({
			Name = limb.name,
			Parent = model,
			CFrame = at(limb.center),
			Size = limb.size,
			Color = SKIN,
		})
	end
	-- Round every limb core so the body reads as muscle rather than boxes (feet stay blocky).
	for _, name in {
		"UpperTorso",
		"LowerTorso",
		"RightUpperArm",
		"LeftUpperArm",
		"RightLowerArm",
		"LeftLowerArm",
		"RightHand",
		"LeftHand",
		"RightUpperLeg",
		"LeftUpperLeg",
		"RightLowerLeg",
		"LeftLowerLeg",
	} do
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = parts[name]
	end
	parts.Head.Transparency = 1

	parts.WheelCore = PartKit.part({
		Name = "WheelCore",
		Parent = model,
		CFrame = at(Vector3.new(0, 28.6, 0.2)),
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
	})

	-- Torso musculature ----------------------------------------------------------
	-- V-shaped torso: broad ribcage, narrow waist, defined pecs and a six-pack.
	local chest = parts.UpperTorso
	chest.Size = Vector3.new(6.2, 5.2, 3.5)
	deco(chest, { Name = "Ribcage", CFrame = at(Vector3.new(0, 18.4, 0.1)), Size = Vector3.new(7.0, 4.0, 3.7), Color = SKIN }, true)
	deco(chest, { Name = "Waist", CFrame = at(Vector3.new(0, 15.6, 0.1)), Size = Vector3.new(4.6, 3.6, 3.0), Color = SKIN }, true)
	for _, side in { -1, 1 } do
		deco(chest, {
			Name = "Pec",
			CFrame = at(Vector3.new(side * 1.6, 18.75, -1.55)) * CFrame.Angles(0, math.rad(side * -14), 0),
			Size = Vector3.new(3.1, 2.0, 1.0),
			Color = SHADE,
		}, true)
		deco(chest, { Name = "Lat", CFrame = at(Vector3.new(side * 2.85, 17.4, 0.35)), Size = Vector3.new(1.3, 3.8, 2.6), Color = SKIN }, true)
		deco(chest, { Name = "Oblique", CFrame = at(Vector3.new(side * 1.85, 15.4, -0.9)), Size = Vector3.new(1.0, 2.4, 1.4), Color = SHADE }, true)
		for row, y in { 16.95, 16.05, 15.2 } do
			deco(chest, {
				Name = "Ab",
				CFrame = at(Vector3.new(side * 0.55, y, -1.42 + row * 0.03)),
				Size = Vector3.new(0.95, 0.72, 0.4),
				Color = SHADE,
			}, true)
		end
	end
	deco(chest, { Name = "Traps", CFrame = at(Vector3.new(0, 20.35, 0.45)), Size = Vector3.new(4.2, 1.4, 2.4), Color = SKIN }, true)
	deco(chest, { Name = "NeckMuscle", CFrame = at(Vector3.new(0, 21.0, -0.1)), Size = Vector3.new(1.9, 2.0, 1.9), Color = SKIN }, true)

	-- Head: jaw, lips, nose, and two pairs of wings covering the eyes -------------
	local head = parts.Head
	deco(head, { Name = "Skull", CFrame = at(Vector3.new(0, 23.4, -0.15)), Size = Vector3.new(2.7, 3.0, 2.9), Color = SKIN }, true)
	deco(head, { Name = "Jaw", CFrame = at(Vector3.new(0, 22.3, -0.55)), Size = Vector3.new(2.3, 1.8, 2.3), Color = SKIN }, true)
	deco(head, { Name = "Lips", CFrame = at(Vector3.new(0, 22.05, -1.62)), Size = Vector3.new(1.0, 0.32, 0.3), Color = LIPS }, true)
	local nose = PartKit.wedge({
		Name = "Nose",
		Parent = model,
		CFrame = at(Vector3.new(0, 22.85, -1.55)),
		Size = Vector3.new(0.35, 0.7, 0.45),
		Color = SHADE,
	})
	PartKit.weld(head, nose)
	deco(head, { Name = "WingBand", CFrame = at(Vector3.new(0, 23.45, -1.0)), Size = Vector3.new(2.95, 0.8, 1.3), Color = WING }, true)
	for _, side in { -1, 1 } do
		local eyeRoot = pt(side * 1.25, 23.45, -0.9)
		for k = 0, 2 do
			decoSegment(head, { Name = "EyeWing", Color = WING }, eyeRoot, eyeRoot + cf.Rotation * Vector3.new(side * (2.3 - k * 0.3), 0.35 + k * 0.4, 0.9 + k * 0.35), 0.2, 0.62 - k * 0.1)
		end
		local topRoot = pt(side * 0.85, 24.6, -0.1)
		for k = 0, 2 do
			decoSegment(head, { Name = "CrownWing", Color = WING }, topRoot, topRoot + cf.Rotation * Vector3.new(side * (1.1 + k * 0.35), 1.5 + k * 0.25, 0.7 + k * 0.3), 0.18, 0.55 - k * 0.1)
		end
	end

	-- Arms -------------------------------------------------------------------------
	for _, side in { -1, 1 } do
		local prefix = if side > 0 then "Right" else "Left"
		local upper = parts[prefix .. "UpperArm"]
		local lower = parts[prefix .. "LowerArm"]
		local hand = parts[prefix .. "Hand"]
		deco(upper, { Name = "Deltoid", CFrame = at(Vector3.new(side * 4.4, 19.25, 0)), Size = Vector3.new(2.6, 2.4, 2.5), Color = SKIN }, true)
		deco(upper, { Name = "Bicep", CFrame = at(Vector3.new(side * 4.5, 17.0, -0.4)), Size = Vector3.new(1.8, 2.9, 1.5), Color = SHADE }, true)
		deco(upper, { Name = "Tricep", CFrame = at(Vector3.new(side * 4.6, 17.2, 0.45)), Size = Vector3.new(1.7, 3.3, 1.4), Color = SKIN }, true)
		deco(lower, { Name = "Forearm", CFrame = at(Vector3.new(side * 4.6, 12.9, 0)), Size = Vector3.new(2.0, 3.0, 1.9), Color = SKIN }, true)
		deco(lower, { Name = "Wrist", CFrame = at(Vector3.new(side * 4.6, 10.1, 0)), Size = Vector3.new(1.5, 1.6, 1.5), Color = SKIN }, true)
		for f = 0, 3 do
			deco(hand, {
				Name = "Finger",
				CFrame = at(Vector3.new(side * (4.6 + (f - 1.5) * 0.36), 7.5, -0.2)),
				Size = Vector3.new(0.34, 1.2, 0.45),
				Color = SKIN,
			}, true)
		end
		deco(hand, { Name = "Thumb", CFrame = at(Vector3.new(side * 3.95, 8.3, -0.45)) * CFrame.Angles(0, 0, math.rad(side * -25)), Size = Vector3.new(0.36, 0.9, 0.42), Color = SKIN })
	end

	-- Sword of Extermination fused to the right forearm. Its edge carries positive energy.
	local swordArm = parts.RightLowerArm
	local guard = PartKit.cylinderY({ Name = "SwordGuard", Parent = model, CFrame = at(Vector3.new(4.6, 10.6, -0.2)), Color = GUARD, Material = Enum.Material.Metal }, 0.9, 2.3)
	PartKit.weld(swordArm, guard)
	local bladeTop = 11.2
	local bladeBottom = 1.6
	local segs = 3
	local segLen = (bladeTop - bladeBottom) / segs
	for i = 1, segs do
		local y = bladeTop - segLen * (i - 0.5)
		local width = 1.25 - i * 0.09
		deco(swordArm, {
			Name = "Blade",
			CFrame = at(Vector3.new(4.6, y, -1.35)),
			Size = Vector3.new(0.3, segLen * 1.02, width),
			Color = BLADE,
			Material = Enum.Material.Metal,
			Reflectance = 0.2,
		})
		deco(swordArm, {
			Name = "SwordEdge",
			CFrame = at(Vector3.new(4.6, y, -1.35 - width / 2 - 0.06)),
			Size = Vector3.new(0.14, segLen * 1.02, 0.14),
			Color = Palette.Positive,
			Material = Enum.Material.Neon,
		})
		deco(swordArm, {
			Name = "Fuller",
			CFrame = at(Vector3.new(4.6, y, -1.25)),
			Size = Vector3.new(0.34, segLen * 0.9, 0.12),
			Color = Color3.fromRGB(120, 124, 136),
			Material = Enum.Material.Metal,
		})
	end
	local tip = PartKit.wedge({
		Name = "SwordTip",
		Parent = model,
		CFrame = at(Vector3.new(4.6, bladeBottom - 0.6, -1.35)) * CFrame.Angles(math.rad(180), 0, 0),
		Size = Vector3.new(0.3, 1.2, 0.98),
		Color = BLADE,
		Material = Enum.Material.Metal,
	})
	PartKit.weld(swordArm, tip)
	local glow = Instance.new("Attachment")
	glow.Name = "SwordGlow"
	glow.Position = swordArm.CFrame:PointToObjectSpace(pt(4.6, 6.5, -1.4))
	glow.Parent = swordArm
	PartKit.light(glow, Palette.Positive, 14, 1.5)

	-- Legs, loincloth skirt and rope belt ---------------------------------------------
	for _, side in { -1, 1 } do
		local prefix = if side > 0 then "Right" else "Left"
		deco(parts[prefix .. "UpperLeg"], { Name = "Quad", CFrame = at(Vector3.new(side * 1.75, 9.6, -0.4)), Size = Vector3.new(2.6, 5.2, 2.2), Color = SHADE }, true)
		deco(parts[prefix .. "LowerLeg"], { Name = "Calf", CFrame = at(Vector3.new(side * 1.8, 4.3, 0.4)), Size = Vector3.new(1.9, 3.4, 1.9), Color = SKIN }, true)
		for t = 0, 3 do
			deco(parts[prefix .. "Foot"], {
				Name = "Toe",
				CFrame = at(Vector3.new(side * (1.8 + (t - 1.5) * 0.42), 0.3, -2.1)),
				Size = Vector3.new(0.38, 0.55, 0.6),
				Color = SKIN,
			}, true)
		end
	end
	local pelvis = parts.LowerTorso
	for _, seg in PartKit.ring(model, at(Vector3.new(0, 14.3, 0)), 2.95, 0.5, 0.6, 16, { Color = ROPE, Material = Enum.Material.Fabric }) do
		PartKit.weld(pelvis, seg)
	end
	deco(pelvis, { Name = "Knot", CFrame = at(Vector3.new(0, 14.1, -3.1)), Size = Vector3.new(1.1, 0.9, 0.7), Color = ROPE, Material = Enum.Material.Fabric }, true)
	for _, side in { -1, 1 } do
		decoSegment(pelvis, { Name = "RopeEnd", Color = ROPE, Material = Enum.Material.Fabric }, pt(side * 0.45, 13.7, -3.25), pt(side * 0.55, 10.4, -3.45), 0.28)
	end
	-- Knee-length loincloth: tiled panels flaring gently from the belt, plus a front flap.
	local panels = 16
	for i = 1, panels do
		local a = (i - 0.5) / panels * math.pi * 2
		local dir = Vector3.new(math.sin(a), 0, math.cos(a))
		local top = pt(0, 14.0, 0) + cf.Rotation * (dir * 2.75)
		local bottom = pt(0, 6.4, 0) + cf.Rotation * (dir * 3.45)
		decoSegment(pelvis, {
			Name = "Skirt",
			Color = if i % 2 == 0 then CLOTH else CLOTH_FOLD,
			Material = Enum.Material.Fabric,
		}, top, bottom, 1.5, 0.25)
	end
	decoSegment(pelvis, { Name = "Flap", Color = CLOTH, Material = Enum.Material.Fabric }, pt(0, 13.9, -3.05), pt(0, 5.4, -3.9), 2.4, 0.2)

	-- The Dharma wheel: rim, eight spokes and eight handles -------------------------
	local wheel = parts.WheelCore
	local wheelCF = wheel.CFrame
	local wheelStyle = { Color = Palette.Wheel, Material = Enum.Material.Metal }
	local hub = PartKit.cylinderY({ Name = "Hub", Parent = model, CFrame = wheelCF, Color = Palette.Wheel, Material = Enum.Material.Metal }, 0.7, 1.7)
	PartKit.weld(wheel, hub)
	for _, seg in PartKit.ring(model, wheelCF, 3.6, 0.45, 0.55, 24, wheelStyle) do
		seg.Name = "Rim"
		PartKit.weld(wheel, seg)
	end
	for _, seg in PartKit.ring(model, wheelCF, 2.1, 0.22, 0.3, 16, wheelStyle) do
		seg.Name = "InnerRim"
		PartKit.weld(wheel, seg)
	end
	for _, seg in PartKit.ring(model, wheelCF, 3.6, 0.7, 0.75, 24, { Color = Palette.Positive, Material = Enum.Material.Neon, Transparency = 1 }) do
		seg.Name = "WheelGlow"
		PartKit.weld(wheel, seg)
	end
	for k = 0, 7 do
		local spin = wheelCF * CFrame.Angles(0, k * math.pi / 4, 0)
		deco(wheel, { Name = "Spoke", CFrame = spin * CFrame.new(0, 0, -2.2), Size = Vector3.new(0.34, 0.34, 2.9), Color = Palette.Wheel, Material = Enum.Material.Metal })
		deco(wheel, { Name = "Handle", CFrame = spin * CFrame.new(0, 0, -4.45), Size = Vector3.new(0.3, 0.3, 1.3), Color = Palette.Wheel, Material = Enum.Material.Metal })
		local knob = PartKit.ball(model, spin * CFrame.new(0, 0, -5.25), 0.62, wheelStyle, "Knob")
		PartKit.weld(wheel, knob)
	end

	-- Joints ---------------------------------------------------------------------------
	for _, j in JOINTS do
		local p0 = parts[j.part0]
		local p1 = parts[j.part1]
		local pivot = at(j.pivot)
		local motor = Instance.new("Motor6D")
		motor.Name = j.name
		motor.Part0 = p0
		motor.Part1 = p1
		motor.C0 = p0.CFrame:Inverse() * pivot
		motor.C1 = p1.CFrame:Inverse() * pivot
		motor.Parent = p1
	end

	-- Physics: only the root collides; everything else is visual and massless.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= hrp then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = Mahoraga.HipHeight
	humanoid.AutomaticScalingEnabled = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.WalkSpeed = 19
	humanoid.Parent = model

	model:SetAttribute("JJK_HitRadius", Mahoraga.HitRadius)
	model:SetAttribute("JJK_HitHalfHeight", Mahoraga.HitHalfHeight)
	return model
end

-- Just the wheel, for previews and the summon effect.
function Mahoraga.buildWheel(parent: Instance?, cf: CFrame, scale: number): Model
	local model = PartKit.model("DharmaWheel", parent)
	local style = { Color = Palette.Wheel, Material = Enum.Material.Metal }
	local hub = PartKit.cylinderY({ Name = "Hub", Parent = model, CFrame = cf, Color = Palette.Wheel, Material = Enum.Material.Metal }, 0.7 * scale, 1.7 * scale)
	model.PrimaryPart = hub
	PartKit.ring(model, cf, 3.6 * scale, 0.45 * scale, 0.55 * scale, 24, style)
	PartKit.ring(model, cf, 2.1 * scale, 0.22 * scale, 0.3 * scale, 16, style)
	for k = 0, 7 do
		local spin = cf * CFrame.Angles(0, k * math.pi / 4, 0)
		PartKit.part({ Name = "Spoke", Parent = model, CFrame = spin * CFrame.new(0, 0, -2.2 * scale), Size = Vector3.new(0.34, 0.34, 2.9) * scale, Color = Palette.Wheel, Material = Enum.Material.Metal })
		PartKit.part({ Name = "Handle", Parent = model, CFrame = spin * CFrame.new(0, 0, -4.45 * scale), Size = Vector3.new(0.3, 0.3, 1.3) * scale, Color = Palette.Wheel, Material = Enum.Material.Metal })
		PartKit.ball(model, spin * CFrame.new(0, 0, -5.25 * scale), 0.62 * scale, style, "Knob")
	end
	return model
end

return Mahoraga
