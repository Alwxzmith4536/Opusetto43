--[[
	Builds preview scenes from the kit's real asset builders (and Mahoraga's real
	animation poses) with Lune, then writes the resulting parts to
	tools/preview/out/scenes.json for render.mjs to draw with three.js.

	Run from the yuta-vs-mahoraga folder:
	  lune run tools/preview/export.luau

	Only the Yuta mannequin is preview-only: in game you play your own avatar.
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")

local roblox = Loader.roblox
local Instance = roblox.Instance
local CFrame = Loader.CFrame -- patched lookAt (see loader.luau)
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3
local Enum = roblox.Enum

-- Stub services so client modules can be required for their pure functions.
local stubService = setmetatable({}, {
	__index = function()
		return function() end
	end,
})
Loader.setGlobal("game", {
	GetService = function()
		return stubService
	end,
})

Loader.init("src")
local function shared(name: string): any
	return Loader.module("src/shared/Assets/" .. name .. ".luau")
end
local PartKit = shared("PartKit")
local Katana = shared("Katana")
local Rika = shared("Rika")
local Mahoraga = shared("Mahoraga")
local Domain = shared("Domain")
local Arena = shared("Arena")
local Effects = shared("Effects")
local SixEyesLook = shared("SixEyesLook")
local Palette = Loader.module("src/shared/Palette.luau")
local BossAnimator = Loader.module("src/client/BossAnimator.luau")

local rng = Loader.Random.new(11)

-- Helpers ------------------------------------------------------------------------------------

local function parts(root: any): { any }
	local list = {}
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- Moves every part of `model` so its PrimaryPart lands on `cf` (Lune has no PivotTo).
local function pivotTo(model: any, cf: any)
	local delta = cf * model.PrimaryPart.CFrame:Inverse()
	for _, p in parts(model) do
		p.CFrame = delta * p.CFrame
	end
end

-- Poses a Motor6D rig the way the engine would: Part1 = Part0 * C0 * Transform * C1^-1.
-- Parts welded to a limb follow it.
local function applyPose(model: any, pose: { [string]: any })
	local motors, welded = {}, {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			table.insert(motors, d)
		elseif d:IsA("WeldConstraint") then
			welded[d.Part0] = welded[d.Part0] or {}
			table.insert(welded[d.Part0], d.Part1)
		end
	end
	local original, placed = {}, {}
	for _, p in parts(model) do
		original[p] = p.CFrame
	end
	placed[model.PrimaryPart] = model.PrimaryPart.CFrame
	local progress = true
	while progress do
		progress = false
		for _, m in motors do
			if placed[m.Part0] and not placed[m.Part1] then
				local t = pose[m.Name] or CFrame.identity
				placed[m.Part1] = placed[m.Part0] * m.C0 * t * m.C1:Inverse()
				progress = true
			end
		end
	end
	for limb, cf in placed do
		local delta = cf * original[limb]:Inverse()
		limb.CFrame = cf
		for _, p in welded[limb] or {} do
			p.CFrame = delta * original[p]
		end
	end
end

-- Preview-only stand-in for the player's avatar, dressed as Yuta (white Jujutsu High uniform).
local function yuta(parent: any, ground: any, opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local m = PartKit.model("YutaStandIn", parent)
	local WHITE = Color3.fromRGB(236, 236, 242)
	local SKIN = Color3.fromRGB(236, 204, 180)
	local HAIR = Color3.fromRGB(22, 20, 28)
	local DARK = Color3.fromRGB(34, 32, 40)
	local function at(x, y, z)
		return ground * CFrame.new(x, y, z)
	end
	local function pt(x, y, z)
		return (ground * CFrame.new(x, y, z)).Position
	end
	PartKit.part({ Name = "Pelvis", Parent = m, CFrame = at(0, 2.25, 0), Size = Vector3.new(1.9, 0.7, 1), Color = WHITE })
	PartKit.part({ Name = "Torso", Parent = m, CFrame = at(0, 3.35, 0), Size = Vector3.new(2, 1.6, 1.05), Color = WHITE })
	PartKit.part({ Name = "Collar", Parent = m, CFrame = at(0, 4.2, 0), Size = Vector3.new(0.9, 0.3, 0.8), Color = WHITE })
	PartKit.ball(m, at(0.25, 3.7, -0.55), 0.22, { Color = Palette.Wheel, Material = Enum.Material.Metal }, "Button")
	PartKit.part({ Name = "Belt", Parent = m, CFrame = at(0, 2.6, 0), Size = Vector3.new(2.02, 0.16, 1.07), Color = DARK })
	local head = PartKit.ellipsoid({ Name = "Head", Parent = m, CFrame = at(0, 4.85, 0), Size = Vector3.new(1.2, 1.3, 1.2), Color = SKIN })
	if not o.sixEyes then
		PartKit.ellipsoid({ Name = "Hair", Parent = m, CFrame = at(0, 5.2, 0.08), Size = Vector3.new(1.32, 0.85, 1.34), Color = HAIR })
		for _, x in { -0.35, -0.12, 0.12, 0.35 } do
			PartKit.limb({ Name = "Fringe", Parent = m, Color = HAIR }, pt(x, 5.35, -0.45), pt(x * 1.1, 4.95, -0.62), 0.22)
		end
		for _, x in { -0.22, 0.22 } do
			PartKit.part({ Name = "Eye", Parent = m, CFrame = at(x, 4.88, -0.6), Size = Vector3.new(0.16, 0.12, 0.04), Color = DARK })
		end
	end
	for _, side in { -1, 1 } do
		PartKit.part({ Name = "Leg", Parent = m, CFrame = at(side * 0.5, 1.0, 0), Size = Vector3.new(0.85, 2.0, 0.9), Color = WHITE })
		PartKit.part({ Name = "Shoe", Parent = m, CFrame = at(side * 0.5, 0.12, -0.1), Size = Vector3.new(0.9, 0.25, 1.1), Color = DARK })
	end
	-- Arms: the right hand holds the katana forward, the left hangs.
	local rShoulder, rHand = pt(1.25, 4.0, 0), pt(1.1, 3.25, -1.25)
	local lShoulder, lHand = pt(-1.25, 4.0, 0), pt(-1.4, 2.4, -0.2)
	if o.cast then
		lHand = pt(-0.9, 4.3, -1.6)
	end
	PartKit.limb({ Name = "Arm", Parent = m, Color = WHITE }, rShoulder, rHand, 0.62)
	PartKit.limb({ Name = "Arm", Parent = m, Color = WHITE }, lShoulder, lHand, 0.62)
	PartKit.ball(m, CFrame.new(rHand), 0.5, { Color = SKIN }, "Hand")
	PartKit.ball(m, CFrame.new(lHand), 0.5, { Color = SKIN }, "Hand")
	if o.katana ~= false then
		local grip = CFrame.new(rHand) * (ground.Rotation * CFrame.Angles(math.rad(-70), 0, 0))
		Katana.buildModel(m, grip * CFrame.new(0, 0.2, 0), 1, "full")
	end
	return { Model = m, Head = head, Root = at(0, 3, 0) }
end

local function floor(parent: any, size: number, color: any)
	PartKit.part({
		Name = "PreviewFloor",
		Parent = parent,
		CFrame = CFrame.new(0, -0.5, 0),
		Size = Vector3.new(size, 1, size),
		Color = color or Color3.fromRGB(72, 68, 76),
		Material = Enum.Material.Slate,
	})
end

-- Export -------------------------------------------------------------------------------------

local function v3(v: any): { number }
	return { v.X, v.Y, v.Z }
end

local function exportScene(root: any): { [string]: any }
	local out = { parts = {}, lights = {}, labels = {} }
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Transparency < 0.995 then
				local shape = "Block"
				if d:IsA("WedgePart") then
					shape = "Wedge"
				elseif d:IsA("Part") then
					if d.Shape == Enum.PartType.Ball then
						shape = "Ball"
					elseif d.Shape == Enum.PartType.Cylinder then
						shape = "Cylinder"
					end
				end
				local mesh = d:FindFirstChildOfClass("SpecialMesh")
				if mesh and mesh.MeshType == Enum.MeshType.Sphere then
					shape = "Ellipsoid"
				end
				table.insert(out.parts, {
					shape = shape,
					size = v3(d.Size),
					cf = { d.CFrame:GetComponents() },
					color = { d.Color.R, d.Color.G, d.Color.B },
					material = d.Material.Name,
					transparency = d.Transparency,
					reflectance = d.Reflectance,
				})
			end
		elseif d:IsA("PointLight") then
			local host = d.Parent
			-- Lune only stores CFrames, so derive positions from them.
			local pos = if host:IsA("Attachment") and host.Parent:IsA("BasePart")
				then host.Parent.CFrame * host.CFrame.Position
				elseif host:IsA("BasePart") then host.CFrame.Position
				else nil
			if pos and d.Brightness > 0 then
				table.insert(out.lights, { pos = v3(pos), color = { d.Color.R, d.Color.G, d.Color.B }, range = d.Range, brightness = d.Brightness })
			end
		elseif d:IsA("BillboardGui") then
			local adornee = d.Adornee or d.Parent
			local label = d:FindFirstChildOfClass("TextLabel")
			if adornee and adornee:IsA("BasePart") and label then
				table.insert(out.labels, {
					pos = v3(adornee.CFrame.Position + d.StudsOffset),
					text = label.Text,
					color = { label.TextColor3.R, label.TextColor3.G, label.TextColor3.B },
					width = d.Size.X.Scale,
					height = d.Size.Y.Scale,
				})
			end
		end
	end
	return out
end

local scenes = {}

local function scene(name: string, title: string, build: (any) -> { [string]: any })
	local root = Instance.new("Folder")
	local settings = build(root)
	local data = exportScene(root)
	data.name = name
	data.title = title
	for k, v in settings do
		data[k] = v
	end
	table.insert(scenes, data)
	print(("%-22s %5d parts  %2d lights  %d labels"):format(name, #data.parts, #data.lights, #data.labels))
end

-- Scenes --------------------------------------------------------------------------------------

scene("01_katana", "Yuta's katana (the M1 weapon / Tool)", function(root)
	Katana.buildModel(root, CFrame.new(0, 0.2, 0) * CFrame.Angles(math.rad(-58), 0, 0), 1, "full")
	return { camera = { pos = { 7.2, 1.2, 0.3 }, target = { 0, 1.1, -0.9 }, fov = 34 }, bg = { "#2a1840", "#07050d" } }
end)

scene("02_rika", "Rika: Full Manifestation, floating behind Yuta", function(root)
	floor(root, 200)
	local y = yuta(root, CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(15), 0))
	local body = y.Root * CFrame.new(0, 6.5, 6.5)
	local rika = Rika.build(root, body, 0.85)
	pivotTo(rika:FindFirstChild("RightArm"), body * CFrame.new(Rika.Shoulders.Right * 0.85) * CFrame.Angles(math.rad(120), 0, math.rad(18)))
	pivotTo(rika:FindFirstChild("LeftArm"), body * CFrame.new(Rika.Shoulders.Left * 0.85) * CFrame.Angles(math.rad(25), 0, math.rad(-20)))
	return { camera = { pos = { -13, 9, -24 }, target = { 0, 8.5, 2 }, fov = 42 }, bg = { "#3a2244", "#0d0812" }, fog = { "#1a1022", 60, 180 } }
end)

scene("03_mahoraga", "Mahoraga, the boss (29 studs tall, animated rig)", function(root)
	floor(root, 300)
	local boss = Mahoraga.build(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(-20), 0))
	boss.Parent = root
	applyPose(boss, BossAnimator.poseFor("Move", 0, 0))
	yuta(root, CFrame.new(9, 0, -12) * CFrame.Angles(0, math.rad(160), 0))
	return { camera = { pos = { -16, 12, -40 }, target = { 1, 14, 0 }, fov = 46 }, bg = { "#e0a080", "#3c2a4a" }, fog = { "#6b4a64", 70, 260 } }
end)

scene("04_wheel", "The eight-handled Dharma wheel turning as Mahoraga adapts", function(root)
	local boss = Mahoraga.build(CFrame.new(0, 0, 0))
	boss.Parent = root
	applyPose(boss, BossAnimator.poseFor("Move", 0, 0))
	for _, p in parts(boss) do
		if p.Name == "WheelGlow" then
			p.Transparency = 0.75
		end
	end
	Effects.kanji(root, CFrame.new(0, 34.5, 0), "ADAPTING: KATANA  2/4", 2.4 * 21 * 1.05, 2.4, Palette.Wheel)
	return { camera = { pos = { -7, 33, -13 }, target = { 0, 27, 0 }, fov = 44 }, bg = { "#2b2238", "#0b0910" } }
end)

scene("05_mahoraga_sweep", "Sword of Extermination sweep with its ground telegraph", function(root)
	floor(root, 300)
	local base = CFrame.new(0, 0, 0)
	local boss = Mahoraga.build(base)
	boss.Parent = root
	applyPose(boss, BossAnimator.poseFor("Sweep", 0, 0))
	Effects.telegraphArc(root, base, 24, 200, Palette.Danger)
	Effects.slash(root, base * CFrame.new(0, 9, 0), 19, 200, 2.8, Palette.Positive, Palette.PositiveCore, 26)
	yuta(root, CFrame.new(-8, 0, -30) * CFrame.Angles(0, math.rad(180), 0))
	return { camera = { pos = { 22, 20, -46 }, target = { 0, 8, -6 }, fov = 46 }, bg = { "#d49a7e", "#35263f" }, fog = { "#5f4460", 80, 260 } }
end)

scene("06_mahoraga_rings", "Enraged: rings of positive energy (jump over them)", function(root)
	floor(root, 300)
	local boss = Mahoraga.build(CFrame.new(0, 0, 0))
	boss.Parent = root
	applyPose(boss, BossAnimator.poseFor("Burst", 0, 0))
	for _, r in { 16, 34, 52 } do
		PartKit.ring(root, CFrame.new(0, 1.6, 0), r, 1.0, 3.2, 56, { Color = Palette.Positive, Material = Enum.Material.Neon, Transparency = 0.15 + r / 150 })
		PartKit.ring(root, CFrame.new(0, 0.25, 0), r, 2.2, 0.4, 56, { Color = Palette.PositiveCore, Material = Enum.Material.Neon, Transparency = 0.3 })
	end
	yuta(root, CFrame.new(-8, 5.5, -34) * CFrame.Angles(0, math.rad(180), 0))
	return { camera = { pos = { 40, 30, -70 }, target = { 0, 8, -10 }, fov = 44 }, bg = { "#b86f6a", "#271c30" }, fog = { "#4f3550", 100, 300 } }
end)

scene("07_domain", "Domain Expansion: Authentic Mutual Love (inside view)", function(root)
	Domain.build(root, CFrame.new(0, 0, 0), 62, 7)
	yuta(root, CFrame.new(0, 0, 8) * CFrame.Angles(0, math.rad(200), 0))
	return { camera = { pos = { 5, 6, 30 }, target = { -2, 17, -40 }, fov = 62 }, bg = { "#000000", "#000000" }, ambient = 0.55 }
end)

scene("08_domain_outside", "The domain from outside: a sealed dome", function(root)
	floor(root, 400, Color3.fromRGB(78, 74, 82))
	Domain.build(root, CFrame.new(0, 0, 0), 62, 7)
	return { camera = { pos = { 120, 60, -130 }, target = { 0, 16, 0 }, fov = 40 }, bg = { "#e6a585", "#3a2a48" } }
end)

scene("09_pure_love", "Pure Love: Jun'ai Ho, with Rika wrapped around Yuta", function(root)
	floor(root, 400)
	local base = CFrame.new(0, 0, 0)
	local y = yuta(root, base, { cast = true })
	local body = y.Root * CFrame.new(0, 4.6, 3.4)
	local rika = Rika.build(root, body, 0.85)
	pivotTo(rika:FindFirstChild("RightArm"), body * CFrame.new(Rika.Shoulders.Right * 0.85) * CFrame.Angles(math.rad(75), 0, math.rad(-22)))
	pivotTo(rika:FindFirstChild("LeftArm"), body * CFrame.new(Rika.Shoulders.Left * 0.85) * CFrame.Angles(math.rad(75), 0, math.rad(22)))
	local origin = Vector3.new(0, 4.5, -5)
	-- (Lune's CFrame.lookAt flips when looking exactly along -Z; an identity rotation already faces -Z.)
	Effects.beam(root, CFrame.new(origin), 180, 14, Palette.PureLove, Palette.PureLove, Palette.PureLoveCore)
	Effects.kanji(root, CFrame.new(0, 17, 4), "純愛砲", 3.6 * 3.15, 3.6, Palette.PureLove)
	return { camera = { pos = { -46, 13, -34 }, target = { 0, 6, -24 }, fov = 55 }, bg = { "#472850", "#0c0710" }, fog = { "#1e1024", 90, 280 } }
end)

scene("10_hollow_purple", "Copy: Six Eyes mode - Hollow Technique: Purple", function(root)
	floor(root, 400)
	yuta(root, CFrame.new(0, 0, 0), { sixEyes = true, cast = true, katana = false })
	local head = nil
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Head" then
			head = p
		end
	end
	SixEyesLook.build(head, Vector3.new(1.2, 1.3, 1.2)).Parent = root
	Effects.purple(root, Vector3.new(0, 6, -40), 7.2, rng)
	for z = -6, -34, -7 do
		PartKit.part({ Name = "Erased", Parent = root, CFrame = CFrame.new(0, 0.06, z), Size = Vector3.new(15, 0.1, 8), Color = Color3.fromRGB(26, 10, 36), Material = Enum.Material.Slate })
		PartKit.part({ Name = "ErasedGlow", Parent = root, CFrame = CFrame.new(0, 0.1, z), Size = Vector3.new(4.5, 0.08, 8), Color = Palette.Purple, Material = Enum.Material.Neon, Transparency = 0.3 })
	end
	Effects.kanji(root, CFrame.new(0, 17, -40), "虚式「茈」", 3 * 5.25, 3, Palette.Purple)
	return { camera = { pos = { -28, 11, 6 }, target = { 0, 5, -28 }, fov = 50 }, bg = { "#2c1a44", "#07050d" }, fog = { "#140a20", 80, 260 } }
end)

scene("11_blue_red", "Six Eyes mode: Lapse Blue (pull) and Reversal Red (blast)", function(root)
	floor(root, 400)
	local y = yuta(root, CFrame.new(0, 0, 0), { sixEyes = true, cast = true, katana = false })
	SixEyesLook.build(y.Head, Vector3.new(1.2, 1.3, 1.2)).Parent = root
	Effects.blue(root, Vector3.new(-16, 6, -22), 16)
	Effects.red(root, Vector3.new(9, 4.5, -14), 1.4, rng)
	local blastPos = Vector3.new(24, 3, -34)
	PartKit.ball(root, CFrame.new(blastPos), 14, { Color = Palette.Red, Material = Enum.Material.Neon, Transparency = 0.55 }, "Blast")
	Effects.spikes(root, blastPos, 12, 9, Palette.Red, rng)
	Effects.infinity(root, Vector3.new(0, 3, 0), 3.2)
	return { camera = { pos = { 2, 9, 22 }, target = { 2, 5, -20 }, fov = 55 }, bg = { "#1d2346", "#06070f" }, fog = { "#0d1024", 70, 220 } }
end)

scene("12_katana_combo", "Katana combo: 4 cursed-energy slashes", function(root)
	floor(root, 200)
	local base = CFrame.new(0, 0, 0)
	yuta(root, base)
	local rootCF = base * CFrame.new(0, 3, 0)
	for combo, roll in { 35, -35, 0, 90 } do
		if combo == 4 then
			roll = 90
		end
		local finisher = combo == 4
		local cf = rootCF * CFrame.new(0, 0.4, -1.2 - combo * 1.4) * CFrame.Angles(0, 0, math.rad(roll))
		Effects.slash(root, cf, if finisher then 7 else 5.2, if finisher then 210 else 165, if finisher then 1.8 else 1.2, Palette.YutaEnergy, Palette.YutaCore)
	end
	return { camera = { pos = { -14, 9, -24 }, target = { 0, 4, -5 }, fov = 46 }, bg = { "#2c1f45", "#08060e" } }
end)

scene("13_rika_strike", "Rika: Partial Manifestation - the arm slam (Z)", function(root)
	floor(root, 200)
	local base = CFrame.new(0, 0, 0)
	yuta(root, base)
	local pivot = base * CFrame.new(1.6, 9.5 * 1.05, 3.2)
	Rika.buildArm(root, pivot * CFrame.Angles(math.rad(52), 0, 0), 1, 1.05)
	PartKit.ring(root, pivot * CFrame.Angles(math.rad(90), 0, 0), 2.5, 0.5, 0.3, 20, { Color = Palette.RikaAura, Material = Enum.Material.Neon })
	PartKit.cylinderZ({ Name = "Void", Parent = root, CFrame = pivot, Color = Palette.Shadow }, 0.15, 4.8)
	local impact = base * CFrame.new(0, 0, -10)
	PartKit.ring(root, impact * CFrame.new(0, 0.3, 0), 7, 0.8, 0.9, 32, { Color = Palette.RikaAura, Material = Enum.Material.Neon, Transparency = 0.2 })
	Effects.cracks(root, impact, 9, 8, rng)
	Effects.rocks(root, impact, 8, 9, rng)
	return { camera = { pos = { -16, 8, -18 }, target = { 0, 4, -3 }, fov = 46 }, bg = { "#3b2346", "#0b0710" } }
end)

scene("14_cursed_speech", "Copied Cursed Speech: \"Blast away\" and \"Don't move\"", function(root)
	floor(root, 200)
	local base = CFrame.new(0, 0, 0)
	local y = yuta(root, base, { katana = false })
	local mouth = CFrame.new(y.Head.CFrame.Position) * CFrame.new(0, -0.2, -0.8)
	Effects.speechWaves(root, mouth, 4, 2.2, 0.8, Palette.SpeechRing)
	Effects.cone(root, base * CFrame.new(0, 3, 0), 30, 80, Palette.SpeechRing)
	PartKit.ring(root, CFrame.new(0, 0.3, 0), 34, 1, 0.6, 48, { Color = Palette.SpeechRing, Material = Enum.Material.Neon, Transparency = 0.35 })
	Effects.kanji(root, CFrame.new(0, 8.4, 0), "吹っ飛べ", 3.2 * 4.2, 3.2, Palette.White)
	return { camera = { pos = { -14, 16, 26 }, target = { 0, 2, -14 }, fov = 52 }, bg = { "#2a2140", "#07060c" } }
end)

scene("15_telegraphs", "Mahoraga's attack telegraphs (they fill up before the hit)", function(root)
	floor(root, 300)
	local circle = Effects.telegraphCircle(root, CFrame.new(-34, 0, 0), 20, Palette.Danger)
	circle.Progress[1].Size = Vector3.new(0.05, 24, 24)
	local rect = Effects.telegraphRect(root, CFrame.new(0, 0, 18), 10, 60, Palette.Positive)
	rect.Progress[1].Size = Vector3.new(10, 0.05, 36)
	rect.Progress[1].CFrame = CFrame.new(0, 0.16, 18 - 18)
	local arc = Effects.telegraphArc(root, CFrame.new(34, 0, 10), 24, 200, Palette.Danger)
	for _, p in arc.Progress do
		local a = p:GetAttribute("Angle")
		p.Size = Vector3.new(p.Size.X, 0.05, 14)
		p.CFrame = CFrame.new(34, 0.16, 10) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -7)
	end
	return { camera = { pos = { 0, 70, 60 }, target = { 0, 0, -10 }, fov = 50 }, bg = { "#bb8a78", "#2b2033" } }
end)

scene("16_altar_summon", "Ten Shadows altar: summoning Mahoraga (hold P)", function(root)
	floor(root, 300)
	Arena.buildAltar(root, CFrame.new(0, 0, 12))
	local poolAt = CFrame.new(0, 0, -16)
	PartKit.cylinderY({ Name = "Pool", Parent = root, CFrame = poolAt * CFrame.new(0, 0.1, 0), Color = Palette.Shadow }, 0.08, 34)
	PartKit.ring(root, poolAt * CFrame.new(0, 0.14, 0), 17, 0.9, 0.1, 40, { Color = Palette.YutaEnergy, Material = Enum.Material.Neon })
	Effects.pillar(root, poolAt, 90, 4, Palette.Wheel)
	Mahoraga.buildWheel(root, poolAt * CFrame.new(0, 18, 0), 1.5)
	Effects.kanji(root, poolAt * CFrame.new(0, 26, 0), "布瑠部由良由良", 3.6 * 6.3, 3.6, Palette.Wheel)
	yuta(root, CFrame.new(-10, 0, -2) * CFrame.Angles(0, math.rad(140), 0))
	return { camera = { pos = { -38, 16, -44 }, target = { 0, 8, -4 }, fov = 46 }, bg = { "#cc8f78", "#2d2236" }, fog = { "#4d3650", 90, 260 } }
end)

scene("17_six_eyes_look", "Six Eyes mode look: white hair, glowing eyes, Kenjaku's stitches", function(root)
	local y = yuta(root, CFrame.new(0, 0, 0), { sixEyes = true, katana = false })
	SixEyesLook.build(y.Head, Vector3.new(1.2, 1.3, 1.2)).Parent = root
	return { camera = { pos = { 1.5, 5.15, -3.6 }, target = { 0, 4.95, 0 }, fov = 30 }, bg = { "#1b2a44", "#05070c" }, ambient = 0.55, bloom = 0.35 }
end)

scene("18_arena", "The arena: shrine courtyard, altar, torii, lanterns, Mahoraga", function(root)
	local info = Arena.build(root, CFrame.new(0, 0, 0), 520)
	local boss = Mahoraga.build(info.BossSpawn)
	boss.Parent = root
	applyPose(boss, BossAnimator.poseFor("Move", 0, 0))
	yuta(root, CFrame.new(0, 0, 150) * CFrame.Angles(0, 0, 0))
	return { camera = { pos = { 150, 95, 215 }, target = { -10, 0, -50 }, fov = 52 }, bg = { "#f0b28a", "#5b3f63" }, fog = { "#c79a8c", 380, 1100 }, sun = true }
end)

-- Background for the HUD preview: third-person view of a fight in progress (no caption).
scene("_hud_bg", "", function(root)
	floor(root, 400)
	local boss = Mahoraga.build(CFrame.new(0, 0, 0))
	boss.Parent = root
	applyPose(boss, BossAnimator.poseFor("SweepWindup", 0, 0))
	Effects.telegraphArc(root, CFrame.new(0, 0, 0), 24, 200, Palette.Danger)
	local y = yuta(root, CFrame.new(3, 0, -34) * CFrame.Angles(0, math.pi, 0))
	local body = y.Root * CFrame.new(0, 6.5, 6.5)
	local rika = Rika.build(root, body, 0.85)
	pivotTo(rika:FindFirstChild("RightArm"), body * CFrame.new(Rika.Shoulders.Right * 0.85) * CFrame.Angles(math.rad(60), 0, math.rad(18)))
	return { camera = { pos = { -26, 15, -66 }, target = { 2, 11, -6 }, fov = 58 }, bg = { "#d9a184", "#3a2a45" }, fog = { "#6a4a64", 90, 300 }, caption = false }
end)

fs.writeDir("tools/preview/out")
fs.writeFile("tools/preview/out/scenes.json", serde.encode("json", { scenes = scenes }))
print("wrote tools/preview/out/scenes.json")
