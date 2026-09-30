--!strict
--[[
	The shrine courtyard where Mahoraga is summoned: stone floor with a shikigami
	seal, torii gate, stone lanterns, sakura trees, broken pillars, the Ten Shadows
	altar guarded by the two Divine Dogs, and a spawn point.
]]

local PartKit = require(script.Parent.PartKit)
local Palette = require(script.Parent.Parent.Palette)

local Arena = {}

export type Info = {
	Model: Model,
	Pedestal: BasePart,
	AltarCFrame: CFrame,
	BossSpawn: CFrame,
	Spawn: CFrame,
}

local STONE = Color3.fromRGB(86, 82, 88)
local STONE_LIGHT = Color3.fromRGB(122, 116, 118)
local COURT = Color3.fromRGB(104, 98, 104)
local TORII = Color3.fromRGB(192, 40, 34)
local TORII_BLACK = Color3.fromRGB(28, 24, 26)
local LANTERN_LIGHT = Color3.fromRGB(255, 176, 96)
local SAKURA = Color3.fromRGB(255, 178, 208)
local SAKURA_DEEP = Color3.fromRGB(240, 132, 172)
local BARK = Color3.fromRGB(70, 46, 40)
local PLASTER = Color3.fromRGB(226, 220, 206)
local ROOF = Color3.fromRGB(52, 56, 66)
local GRAVEL = Color3.fromRGB(118, 114, 120)
local PATH = Color3.fromRGB(104, 98, 104)

local function solid(props: PartKit.Props): Part
	props.CanCollide = true
	props.CastShadow = true
	return PartKit.part(props)
end

function Arena.buildTorii(parent: Instance?, cf: CFrame, s: number): Model
	local m = PartKit.model("Torii", parent)
	for _, side in { -1, 1 } do
		local pillar = PartKit.cylinderY({ Name = "Pillar", Parent = m, CFrame = cf * CFrame.new(side * 5.5 * s, 7 * s, 0), Color = TORII, Material = Enum.Material.Wood, CanCollide = true, CastShadow = true }, 14 * s, 1.3 * s)
		pillar.Name = "Pillar"
		solid({ Name = "Base", Parent = m, CFrame = cf * CFrame.new(side * 5.5 * s, 0.7 * s, 0), Size = Vector3.new(1.9, 1.4, 1.9) * s, Color = TORII_BLACK })
		solid({
			Name = "KasagiEnd",
			Parent = m,
			CFrame = cf * CFrame.new(side * 8.7 * s, 14.25 * s, 0) * CFrame.Angles(0, 0, math.rad(side * 12)),
			Size = Vector3.new(2.6, 0.95, 1.45) * s,
			Color = TORII_BLACK,
		})
	end
	solid({ Name = "Nuki", Parent = m, CFrame = cf * CFrame.new(0, 11 * s, 0), Size = Vector3.new(14.4, 0.9, 0.8) * s, Color = TORII, Material = Enum.Material.Wood })
	solid({ Name = "Shimaki", Parent = m, CFrame = cf * CFrame.new(0, 13.05 * s, 0), Size = Vector3.new(15.6, 0.8, 1.1) * s, Color = TORII, Material = Enum.Material.Wood })
	solid({ Name = "Kasagi", Parent = m, CFrame = cf * CFrame.new(0, 13.9 * s, 0), Size = Vector3.new(15.4, 1.1, 1.45) * s, Color = TORII_BLACK })
	solid({ Name = "Gakuzuka", Parent = m, CFrame = cf * CFrame.new(0, 12.0 * s, 0), Size = Vector3.new(0.9, 2.1, 0.7) * s, Color = TORII, Material = Enum.Material.Wood })
	PartKit.part({ Name = "Plaque", Parent = m, CFrame = cf * CFrame.new(0, 12.05 * s, -0.45 * s), Size = Vector3.new(1.9, 2.4, 0.3) * s, Color = TORII_BLACK })
	PartKit.part({ Name = "PlaqueTrim", Parent = m, CFrame = cf * CFrame.new(0, 12.05 * s, -0.62 * s), Size = Vector3.new(1.4, 1.9, 0.05) * s, Color = Palette.Wheel, Material = Enum.Material.Metal })
	return m
end

function Arena.buildLantern(parent: Instance?, cf: CFrame, s: number): Model
	local m = PartKit.model("Lantern", parent)
	solid({ Name = "Base", Parent = m, CFrame = cf * CFrame.new(0, 0.3 * s, 0), Size = Vector3.new(2.2, 0.6, 2.2) * s, Color = STONE })
	PartKit.cylinderY({ Name = "Pole", Parent = m, CFrame = cf * CFrame.new(0, 2.2 * s, 0), Color = STONE_LIGHT, Material = Enum.Material.Granite, CanCollide = true, CastShadow = true }, 3.2 * s, 0.9 * s)
	solid({ Name = "Platform", Parent = m, CFrame = cf * CFrame.new(0, 4.05 * s, 0), Size = Vector3.new(2.4, 0.5, 2.4) * s, Color = STONE })
	local box = solid({ Name = "Firebox", Parent = m, CFrame = cf * CFrame.new(0, 5.1 * s, 0), Size = Vector3.new(1.8, 1.6, 1.8) * s, Color = STONE_LIGHT, Material = Enum.Material.Granite })
	PartKit.part({ Name = "Window", Parent = m, CFrame = cf * CFrame.new(0, 5.1 * s, 0), Size = Vector3.new(1.1, 0.9, 1.85) * s, Color = LANTERN_LIGHT, Material = Enum.Material.Neon })
	PartKit.part({ Name = "Window", Parent = m, CFrame = cf * CFrame.new(0, 5.1 * s, 0), Size = Vector3.new(1.85, 0.9, 1.1) * s, Color = LANTERN_LIGHT, Material = Enum.Material.Neon })
	solid({ Name = "Roof", Parent = m, CFrame = cf * CFrame.new(0, 6.15 * s, 0), Size = Vector3.new(3.0, 0.45, 3.0) * s, Color = STONE })
	solid({ Name = "RoofTop", Parent = m, CFrame = cf * CFrame.new(0, 6.6 * s, 0), Size = Vector3.new(1.7, 0.5, 1.7) * s, Color = STONE })
	PartKit.ball(m, cf * CFrame.new(0, 7.1 * s, 0), 0.65 * s, { Color = STONE_LIGHT }, "Hoju")
	PartKit.light(box, LANTERN_LIGHT, 24, 1.8)
	return m
end

function Arena.buildSakura(parent: Instance?, cf: CFrame, s: number, rng: Random): Model
	local m = PartKit.model("Sakura", parent)
	local function pt(x: number, y: number, z: number): Vector3
		return cf * (Vector3.new(x, y, z) * s)
	end
	local top = pt(0.6, 7, 0.3)
	PartKit.limb({ Name = "Trunk", Parent = m, Color = BARK, Material = Enum.Material.Wood }, pt(0, -0.5, 0), top, 1.5 * s)
	local crowns = {}
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + rng:NextNumber() * 0.6
		local tip = top + cf.Rotation * (Vector3.new(math.cos(a) * 4.2, 2.2 + rng:NextNumber() * 1.6, math.sin(a) * 4.2) * s)
		PartKit.limb({ Name = "Branch", Parent = m, Color = BARK, Material = Enum.Material.Wood }, top, tip, 0.7 * s)
		table.insert(crowns, tip)
	end
	table.insert(crowns, top + cf.Rotation * (Vector3.new(0, 3.5, 0) * s))
	local blossom: Part? = nil
	for i, c in crowns do
		blossom = PartKit.ball(m, CFrame.new(c), (4.6 + rng:NextNumber() * 1.8) * s, {
			Color = if i % 2 == 0 then SAKURA_DEEP else SAKURA,
			Material = Enum.Material.SmoothPlastic,
		}, "Blossom")
	end
	if blossom then
		PartKit.emitter(blossom, {
			Name = "Petals",
			Texture = PartKit.Textures.Sparkle,
			Color = ColorSequence.new(SAKURA),
			Size = NumberSequence.new(0.35, 0.2),
			Transparency = NumberSequence.new(0.1, 1),
			Lifetime = NumberRange.new(3, 5),
			Rate = 3,
			Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(90, 90),
			Acceleration = Vector3.new(0.6, -1.2, 0.4),
			RotSpeed = NumberRange.new(-90, 90),
		})
	end
	return m
end

-- Roofed temple wall running along cf's X axis (cf = ground point at its centre).
function Arena.buildWall(parent: Instance?, cf: CFrame, length: number): Model
	local m = PartKit.model("TempleWall", parent)
	solid({ Name = "Base", Parent = m, CFrame = cf * CFrame.new(0, 1.2, 0), Size = Vector3.new(length, 2.4, 4.2), Color = STONE, Material = Enum.Material.Slate })
	solid({ Name = "Plaster", Parent = m, CFrame = cf * CFrame.new(0, 6.4, 0), Size = Vector3.new(length, 8, 3), Color = PLASTER })
	solid({ Name = "Beam", Parent = m, CFrame = cf * CFrame.new(0, 10.2, 0), Size = Vector3.new(length, 0.6, 3.3), Color = BARK, Material = Enum.Material.Wood })
	for _, side in { -1, 1 } do
		local roof = PartKit.wedge({
			Name = "Roof",
			Parent = m,
			CFrame = cf * CFrame.new(0, 11.4, side * 1.4) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0),
			Size = Vector3.new(length + 1, 1.8, 2.8),
			Color = ROOF,
			CanCollide = true,
			CastShadow = true,
		})
		roof.Name = "Roof"
	end
	solid({ Name = "Ridge", Parent = m, CFrame = cf * CFrame.new(0, 12.35, 0), Size = Vector3.new(length + 1, 0.5, 0.7), Color = ROOF })
	return m
end

-- Main shrine hall (honden); cf = ground point at its centre, front facing cf's -Z.
function Arena.buildHall(parent: Instance?, cf: CFrame): Model
	local m = PartKit.model("ShrineHall", parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	solid({ Name = "Platform", Parent = m, CFrame = at(0, 1.5, 0), Size = Vector3.new(48, 3, 34), Color = STONE_LIGHT, Material = Enum.Material.Slate })
	for i = 1, 3 do
		solid({ Name = "Step", Parent = m, CFrame = at(0, 1.5 - i * 0.5 + 0.25, -17 - i * 1.4 + 0.7), Size = Vector3.new(22, 3 - i + 0.5, 1.4), Color = STONE, Material = Enum.Material.Slate })
	end
	solid({ Name = "Floor", Parent = m, CFrame = at(0, 3.2, 0), Size = Vector3.new(46, 0.4, 32), Color = Color3.fromRGB(120, 82, 58), Material = Enum.Material.Wood })
	for _, z in { -14, 14 } do
		for _, x in { -20, -10, 0, 10, 20 } do
			if not (z < 0 and x == 0) then
				PartKit.cylinderY({ Name = "Pillar", Parent = m, CFrame = at(x, 9.9, z), Color = TORII, Material = Enum.Material.Wood, CanCollide = true, CastShadow = true }, 13.4, 1.7)
			end
		end
	end
	solid({ Name = "BackWall", Parent = m, CFrame = at(0, 9.6, 15.2), Size = Vector3.new(42, 12.6, 0.8), Color = Color3.fromRGB(78, 52, 40), Material = Enum.Material.Wood })
	for _, side in { -1, 1 } do
		solid({ Name = "SideWall", Parent = m, CFrame = at(side * 21.4, 9.6, 1), Size = Vector3.new(0.8, 12.6, 28), Color = Color3.fromRGB(78, 52, 40), Material = Enum.Material.Wood })
	end
	solid({ Name = "FrontBeam", Parent = m, CFrame = at(0, 16.2, -14), Size = Vector3.new(46, 1.3, 1.3), Color = TORII, Material = Enum.Material.Wood })
	solid({ Name = "BackBeam", Parent = m, CFrame = at(0, 16.2, 14), Size = Vector3.new(46, 1.3, 1.3), Color = TORII, Material = Enum.Material.Wood })
	PartKit.part({ Name = "Plaque", Parent = m, CFrame = at(0, 14.4, -14.8), Size = Vector3.new(6, 2.4, 0.3), Color = Color3.fromRGB(26, 22, 24) })
	PartKit.part({ Name = "PlaqueTrim", Parent = m, CFrame = at(0, 14.4, -14.97), Size = Vector3.new(5.2, 1.7, 0.05), Color = Palette.Wheel, Material = Enum.Material.Metal })
	for _, side in { -1, 1 } do
		PartKit.wedge({
			Name = "Roof",
			Parent = m,
			CFrame = at(0, 20.3, side * 11) * CFrame.Angles(0, if side < 0 then 0 else math.pi, 0),
			Size = Vector3.new(56, 7.2, 22),
			Color = ROOF,
			CanCollide = true,
			CastShadow = true,
		})
	end
	solid({ Name = "Ridge", Parent = m, CFrame = at(0, 24.05, 0), Size = Vector3.new(58, 1.3, 1.8), Color = ROOF })
	for _, side in { -1, 1 } do
		PartKit.ball(m, at(side * 29, 24.4, 0), 1.6, { Color = Palette.Wheel, Material = Enum.Material.Metal }, "RidgeOrnament")
	end
	solid({ Name = "OfferingBox", Parent = m, CFrame = at(0, 4.4, -12), Size = Vector3.new(5, 2, 2.4), Color = Color3.fromRGB(96, 64, 44), Material = Enum.Material.Wood })
	local rope = PartKit.cylinderZ({ Name = "Shimenawa", Parent = m, CFrame = at(0, 13.2, -14.9) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(214, 190, 140), Material = Enum.Material.Fabric }, 18, 1.1)
	rope.Name = "Shimenawa"
	for _, x in { -6, -2, 2, 6 } do
		PartKit.part({ Name = "Shide", Parent = m, CFrame = at(x, 11.8, -15.2), Size = Vector3.new(0.9, 2.2, 0.05), Color = Color3.fromRGB(250, 250, 246) })
	end
	return m
end

function Arena.buildBoulders(parent: Instance?, cf: CFrame, rng: Random): Model
	local m = PartKit.model("Boulders", parent)
	for i = 1, 4 do
		local size = 3 + rng:NextNumber() * 5
		solid({
			Name = "Boulder",
			Parent = m,
			CFrame = cf * CFrame.new(rng:NextNumber(-6, 6), size * 0.3, rng:NextNumber(-6, 6)) * CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber() * 3, rng:NextNumber(-0.5, 0.5)),
			Size = Vector3.new(size, size * 0.7, size * (0.8 + i * 0.1)),
			Color = if i % 2 == 0 then STONE else Color3.fromRGB(98, 104, 88),
			Material = Enum.Material.Slate,
		})
	end
	return m
end

-- One of Megumi's Divine Dogs, sitting on a plinth, facing cf's -Z.
function Arena.buildDivineDog(parent: Instance?, cf: CFrame, color: Color3, eyes: Color3): Model
	local m = PartKit.model("DivineDog", parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function pt(x: number, y: number, z: number): Vector3
		return cf * Vector3.new(x, y, z)
	end
	solid({ Name = "Plinth", Parent = m, CFrame = at(0, 0.6, 0), Size = Vector3.new(3.4, 1.2, 4.4), Color = STONE })
	PartKit.ellipsoid({ Name = "Haunch", Parent = m, CFrame = at(0, 2.8, 0.5) * CFrame.Angles(math.rad(20), 0, 0), Size = Vector3.new(2.3, 3.0, 2.8), Color = color })
	PartKit.ellipsoid({ Name = "Chest", Parent = m, CFrame = at(0, 3.5, -0.55), Size = Vector3.new(1.9, 2.4, 1.7), Color = color })
	for _, side in { -1, 1 } do
		PartKit.ellipsoid({ Name = "HindLeg", Parent = m, CFrame = at(side * 1.0, 1.9, 0.6), Size = Vector3.new(1.0, 1.6, 2.2), Color = color })
		PartKit.limb({ Name = "ForeLeg", Parent = m, Color = color }, pt(side * 0.6, 3.2, -0.95), pt(side * 0.6, 1.3, -1.3), 0.62)
		PartKit.ellipsoid({ Name = "Paw", Parent = m, CFrame = at(side * 0.6, 1.35, -1.55), Size = Vector3.new(0.7, 0.4, 0.9), Color = color })
		PartKit.wedge({ Name = "Ear", Parent = m, CFrame = at(side * 0.55, 6.35, -0.75), Size = Vector3.new(0.35, 1.0, 0.7), Color = color })
		PartKit.ball(m, at(side * 0.45, 5.55, -1.85), 0.28, { Color = eyes, Material = Enum.Material.Neon }, "Eye")
	end
	PartKit.ellipsoid({ Name = "Head", Parent = m, CFrame = at(0, 5.3, -0.9), Size = Vector3.new(1.8, 1.7, 2.0), Color = color })
	PartKit.ellipsoid({ Name = "Snout", Parent = m, CFrame = at(0, 5.0, -2.0), Size = Vector3.new(1.0, 0.8, 1.3), Color = color })
	PartKit.ball(m, at(0, 5.15, -2.65), 0.3, { Color = Palette.Shadow }, "Nose")
	PartKit.limb({ Name = "Tail", Parent = m, Color = color }, pt(0, 1.8, 1.6), pt(0, 3.4, 2.4), 0.5)
	return m
end

function Arena.buildAltar(parent: Instance?, cf: CFrame): (Model, Part)
	local m = PartKit.model("TenShadowsAltar", parent)
	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	solid({ Name = "Tier1", Parent = m, CFrame = at(0, 0.6, 0), Size = Vector3.new(28, 1.2, 22), Color = STONE, Material = Enum.Material.Slate })
	solid({ Name = "Tier2", Parent = m, CFrame = at(0, 1.8, 0.8), Size = Vector3.new(21, 1.2, 16), Color = STONE_LIGHT, Material = Enum.Material.Slate })
	solid({ Name = "Tier3", Parent = m, CFrame = at(0, 2.95, 1.4), Size = Vector3.new(14, 1.1, 11), Color = STONE, Material = Enum.Material.Slate })
	PartKit.cylinderY({ Name = "ShadowPool", Parent = m, CFrame = at(0, 3.52, 1.2), Color = Palette.Shadow }, 0.06, 8.2)
	PartKit.ring(m, at(0, 3.53, 1.2), 4.15, 0.18, 0.06, 28, { Color = Palette.YutaEnergy, Material = Enum.Material.Neon })
	local pedestal = solid({ Name = "Pedestal", Parent = m, CFrame = at(0, 5.0, 5.4), Size = Vector3.new(3.2, 3.0, 1.4), Color = STONE_LIGHT, Material = Enum.Material.Granite })
	PartKit.part({ Name = "Seal", Parent = m, CFrame = at(0, 5.2, 4.65), Size = Vector3.new(1.6, 2.0, 0.08), Color = Color3.fromRGB(236, 226, 196), Material = Enum.Material.Fabric })
	PartKit.part({ Name = "SealMark", Parent = m, CFrame = at(0, 5.3, 4.6), Size = Vector3.new(0.9, 0.9, 0.04), Color = Palette.Danger })
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		local c = at(math.cos(a) * 5.4, 3.5, 1.2 + math.sin(a) * 4.2)
		PartKit.cylinderY({ Name = "Candle", Parent = m, CFrame = c * CFrame.new(0, 0.5, 0), Color = Color3.fromRGB(240, 234, 220) }, 1.0, 0.35)
		local flame = PartKit.ball(m, c * CFrame.new(0, 1.15, 0), 0.26, { Color = LANTERN_LIGHT, Material = Enum.Material.Neon }, "Flame")
		if i % 2 == 0 then
			PartKit.light(flame, LANTERN_LIGHT, 10, 1.2)
		end
	end
	Arena.buildDivineDog(m, at(-8.2, 2.4, -3.2) * CFrame.Angles(0, math.rad(-12), 0), Color3.fromRGB(238, 238, 242), Palette.SixEyes)
	Arena.buildDivineDog(m, at(8.2, 2.4, -3.2) * CFrame.Angles(0, math.rad(12), 0), Color3.fromRGB(30, 30, 36), Palette.Danger)
	return m, pedestal
end

function Arena.buildSeal(parent: Instance?, cf: CFrame): Model
	local m = PartKit.model("ShikigamiSeal", parent)
	local style = { Color = Palette.YutaEnergy, Material = Enum.Material.Neon, Transparency = 0.45 }
	PartKit.ring(m, cf, 34, 0.5, 0.08, 48, style)
	PartKit.ring(m, cf, 56, 0.6, 0.08, 64, style)
	PartKit.ring(m, cf, 20, 0.3, 0.08, 32, style)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		PartKit.part({
			Name = "Spoke",
			Parent = m,
			CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -45),
			Size = Vector3.new(0.45, 0.08, 22),
			Color = style.Color,
			Material = style.Material,
			Transparency = style.Transparency,
		})
		PartKit.part({
			Name = "Rune",
			Parent = m,
			CFrame = cf * CFrame.Angles(0, a + math.pi / 8, 0) * CFrame.new(0, 0, -27) * CFrame.Angles(0, math.rad(45), 0),
			Size = Vector3.new(3, 0.08, 3),
			Color = style.Color,
			Material = style.Material,
			Transparency = 0.6,
		})
	end
	return m
end

function Arena.build(parent: Instance?, center: CFrame, size: number): Info
	local rng = Random.new(7)
	local m = PartKit.model("JJK_Arena", parent)
	local half = size / 2

	solid({ Name = "Floor", Parent = m, CFrame = center * CFrame.new(0, -2, 0), Size = Vector3.new(size, 4, size), Color = GRAVEL, Material = Enum.Material.Pebble })
	PartKit.cylinderY({ Name = "Courtyard", Parent = m, CFrame = center * CFrame.new(0, 0.04, 0), Color = COURT, Material = Enum.Material.Cobblestone }, 0.1, 150)
	Arena.buildSeal(m, center * CFrame.new(0, 0.1, 0))

	-- Stone paths from the courtyard to each wall.
	local pathLength = half - 75
	for k = 0, 3 do
		local dir = center * CFrame.Angles(0, k * math.pi / 2, 0)
		PartKit.part({
			Name = "Path",
			Parent = m,
			CFrame = dir * CFrame.new(0, 0.03, -(75 + pathLength / 2)),
			Size = Vector3.new(18, 0.1, pathLength + 2),
			Color = PATH,
			Material = Enum.Material.Slate,
		})
	end

	-- Roofed temple walls around the grounds, with an invisible boundary above them.
	for k = 0, 3 do
		local side = center * CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, -half)
		Arena.buildWall(m, side, size + 4.2)
		solid({ Name = "Boundary", Parent = m, CFrame = side * CFrame.new(0, 90, 0), Size = Vector3.new(size, 160, 4), Transparency = 1 })
	end

	-- North axis: altar, torii and the main hall behind it.
	local altarCF = center * CFrame.new(0, 0, -half * 0.5) * CFrame.Angles(0, math.pi, 0)
	local _, pedestal = Arena.buildAltar(m, altarCF)
	Arena.buildTorii(m, center * CFrame.new(0, 0, -half * 0.64) * CFrame.Angles(0, math.pi, 0), 1.6)
	Arena.buildHall(m, center * CFrame.new(0, 0, -half * 0.84) * CFrame.Angles(0, math.pi, 0))
	Arena.buildTorii(m, center * CFrame.new(0, 0, half * 0.84), 1.25)

	-- Lanterns: a ring around the courtyard and pairs lining the north/south paths.
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2 + math.pi / 12
		Arena.buildLantern(m, center * CFrame.new(math.cos(a) * 92, 0, math.sin(a) * 92), 1.3)
	end
	for _, z in { -110, 110, 170 } do
		for _, x in { -14, 14 } do
			Arena.buildLantern(m, center * CFrame.new(x, 0, z), 1.2)
		end
	end

	-- Sakura along the east and west walls, boulders in the corners.
	for _, x in { -1, 1 } do
		for z = -190, 190, 76 do
			local jitter = rng:NextNumber(-10, 10)
			Arena.buildSakura(m, center * CFrame.new(x * (half - 30), 0, z + jitter) * CFrame.Angles(0, rng:NextNumber() * 6, 0), 1.4 + rng:NextNumber() * 0.5, rng)
		end
	end
	for _, corner in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		Arena.buildBoulders(m, center * CFrame.new(corner * (half - 26)), rng)
	end

	local spawnCF = center * CFrame.new(0, 0.5, half * 0.62)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "JJK_Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.CFrame = spawnCF
	spawn.Neutral = true
	spawn.Duration = 3
	spawn.Color = STONE_LIGHT
	spawn.Material = Enum.Material.Slate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = m

	return {
		Model = m,
		Pedestal = pedestal,
		AltarCFrame = altarCF,
		BossSpawn = CFrame.lookAt(center.Position, center.Position + Vector3.new(0, 0, 1)),
		Spawn = spawnCF,
	}
end

return Arena
