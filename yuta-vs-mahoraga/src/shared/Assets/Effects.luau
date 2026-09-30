--!strict
--[[
	Geometry for every visual effect. These functions only build parts; the
	client's VFX module animates them (tweens, reveals, fades).
]]

local PartKit = require(script.Parent.PartKit)
local Palette = require(script.Parent.Parent.Palette)

local Effects = {}

local NEON = Enum.Material.Neon

export type Slash = { Model: Model, Outer: { Part }, Core: { Part } }
export type Telegraph = { Model: Model, Fill: { Part }, Progress: { Part }, Outline: { Part } }

local function randomUnit(rng: Random): Vector3
	local theta = rng:NextNumber() * math.pi * 2
	local z = rng:NextNumber() * 2 - 1
	local r = math.sqrt(1 - z * z)
	return Vector3.new(r * math.cos(theta), z, r * math.sin(theta))
end
Effects.randomUnit = randomUnit

-- Crescent sword arc in cf's XZ plane: a translucent body with a bright leading edge.
function Effects.slash(
	parent: Instance?,
	cf: CFrame,
	radius: number,
	arcDegrees: number,
	thickness: number,
	color: Color3,
	core: Color3,
	segments: number?
): Slash
	local m = PartKit.model("Slash", parent)
	local n = segments or 20
	local outer = PartKit.crescent(m, cf, radius, arcDegrees, thickness, 0.1, n, { Color = color, Material = NEON, Transparency = 0.3 })
	local inner = PartKit.crescent(m, cf * CFrame.new(0, 0.03, 0), radius + thickness * 0.45, arcDegrees * 0.94, thickness * 0.38, 0.12, n, {
		Color = core,
		Material = NEON,
	})
	return { Model = m, Outer = outer, Core = inner }
end

function Effects.orb(parent: Instance?, pos: Vector3, radius: number, core: Color3, shell: Color3): Model
	local m = PartKit.model("Orb", parent)
	local c = PartKit.ball(m, CFrame.new(pos), radius * 1.1, { Color = core, Material = NEON }, "Core")
	PartKit.ball(m, CFrame.new(pos), radius * 2, { Color = shell, Material = Enum.Material.ForceField }, "Shell")
	PartKit.ball(m, CFrame.new(pos), radius * 2.7, { Color = shell, Material = NEON, Transparency = 0.84 }, "Halo")
	PartKit.light(c, shell, math.min(radius * 6, 60), 3)
	m.PrimaryPart = c
	return m
end

-- Beam running from cf along its look vector.
function Effects.beam(parent: Instance?, cf: CFrame, length: number, width: number, outer: Color3, mid: Color3, core: Color3): Model
	local m = PartKit.model("Beam", parent)
	local center = cf * CFrame.new(0, 0, -length / 2)
	PartKit.cylinderZ({ Name = "Outer", Parent = m, CFrame = center, Color = outer, Material = Enum.Material.ForceField }, length, width)
	PartKit.cylinderZ({ Name = "Mid", Parent = m, CFrame = center, Color = mid, Material = NEON, Transparency = 0.35 }, length, width * 0.72)
	PartKit.cylinderZ({ Name = "Core", Parent = m, CFrame = center, Color = core, Material = NEON }, length, width * 0.38)
	local rings = PartKit.model("Rings", m)
	local d = 10
	while d < length do
		PartKit.ring(rings, cf * CFrame.new(0, 0, -d) * CFrame.Angles(math.rad(90), 0, 0), width * 0.6, width * 0.07, width * 0.08, 12, {
			Color = core,
			Material = NEON,
			Transparency = 0.25,
		})
		d += 22
	end
	PartKit.ball(m, cf, width * 0.8, { Color = mid, Material = NEON, Transparency = 0.35 }, "Muzzle")
	return m
end

local function ground(cf: CFrame): CFrame
	return cf * CFrame.new(0, 0.14, 0)
end

function Effects.telegraphCircle(parent: Instance?, cf: CFrame, radius: number, color: Color3): Telegraph
	local m = PartKit.model("Telegraph", parent)
	local base = ground(cf)
	local fill = PartKit.cylinderY({ Name = "Fill", Parent = m, CFrame = base, Color = color, Material = NEON, Transparency = 0.84 }, 0.05, radius * 2)
	local progress = PartKit.cylinderY({ Name = "Progress", Parent = m, CFrame = base * CFrame.new(0, 0.02, 0), Color = color, Material = NEON, Transparency = 0.6 }, 0.05, 0.1)
	local outline = PartKit.ring(m, base * CFrame.new(0, 0.03, 0), radius, 0.4, 0.06, 40, { Color = color, Material = NEON })
	return { Model = m, Fill = { fill }, Progress = { progress }, Outline = outline }
end

-- Rectangle starting at cf and running `length` studs along cf's look vector.
function Effects.telegraphRect(parent: Instance?, cf: CFrame, width: number, length: number, color: Color3): Telegraph
	local m = PartKit.model("Telegraph", parent)
	local base = ground(cf)
	local fill = PartKit.part({ Name = "Fill", Parent = m, CFrame = base * CFrame.new(0, 0, -length / 2), Size = Vector3.new(width, 0.05, length), Color = color, Material = NEON, Transparency = 0.84 })
	local progress = PartKit.part({ Name = "Progress", Parent = m, CFrame = base * CFrame.new(0, 0.02, -0.05), Size = Vector3.new(width, 0.05, 0.1), Color = color, Material = NEON, Transparency = 0.6 })
	local outline: { Part } = {}
	for _, side in { -1, 1 } do
		table.insert(outline, PartKit.part({ Name = "Edge", Parent = m, CFrame = base * CFrame.new(side * width / 2, 0.03, -length / 2), Size = Vector3.new(0.4, 0.06, length), Color = color, Material = NEON }))
	end
	for _, z in { 0, -length } do
		table.insert(outline, PartKit.part({ Name = "Edge", Parent = m, CFrame = base * CFrame.new(0, 0.03, z), Size = Vector3.new(width, 0.06, 0.4), Color = color, Material = NEON }))
	end
	return { Model = m, Fill = { fill }, Progress = { progress }, Outline = outline }
end

-- Pie slice of `arcDegrees` centred on cf's look vector.
function Effects.telegraphArc(parent: Instance?, cf: CFrame, radius: number, arcDegrees: number, color: Color3): Telegraph
	local m = PartKit.model("Telegraph", parent)
	local base = ground(cf)
	local arc = math.rad(arcDegrees)
	local rays = math.max(10, math.floor(arcDegrees / 6))
	local rayWidth = radius * arc / rays * 1.15
	local fill: { Part }, progress: { Part } = {}, {}
	for i = 1, rays do
		local a = -arc / 2 + arc * (i - 0.5) / rays
		local f = PartKit.part({ Name = "Fill", Parent = m, CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius / 2), Size = Vector3.new(rayWidth, 0.05, radius), Color = color, Material = NEON, Transparency = 0.86 })
		f:SetAttribute("Angle", a)
		table.insert(fill, f)
		local p = PartKit.part({ Name = "Progress", Parent = m, CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.02, -0.05), Size = Vector3.new(rayWidth, 0.05, 0.1), Color = color, Material = NEON, Transparency = 0.65 })
		p:SetAttribute("Angle", a)
		table.insert(progress, p)
	end
	local outline = PartKit.crescent(m, base * CFrame.new(0, 0.03, 0), radius - 0.2, arcDegrees, 0.4, 0.06, rays, { Color = color, Material = NEON })
	for _, a in { -arc / 2, arc / 2 } do
		table.insert(outline, PartKit.part({ Name = "Edge", Parent = m, CFrame = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.03, -radius / 2), Size = Vector3.new(0.4, 0.06, radius), Color = color, Material = NEON }))
	end
	return { Model = m, Fill = fill, Progress = progress, Outline = outline }
end

function Effects.cracks(parent: Instance?, cf: CFrame, radius: number, count: number, rng: Random): Model
	local m = PartKit.model("Cracks", parent)
	local base = cf * CFrame.new(0, 0.09, 0)
	for _ = 1, count do
		local a = rng:NextNumber() * math.pi * 2
		local p = base * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius * 0.12)
		local steps = 3
		local len = radius * (0.5 + rng:NextNumber() * 0.5) / steps
		for s = 1, steps do
			local turn = CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0)
			p = p * turn
			PartKit.part({
				Name = "Crack",
				Parent = m,
				CFrame = p * CFrame.new(0, 0, -len / 2),
				Size = Vector3.new(0.5 * (1.2 - s * 0.25), 0.08, len),
				Color = Color3.fromRGB(18, 14, 20),
			})
			p = p * CFrame.new(0, 0, -len)
		end
	end
	return m
end

function Effects.rocks(parent: Instance?, cf: CFrame, radius: number, count: number, rng: Random): Model
	local m = PartKit.model("Rocks", parent)
	for _ = 1, count do
		local a = rng:NextNumber() * math.pi * 2
		local r = radius * (0.4 + rng:NextNumber() * 0.6)
		local size = 0.45 + rng:NextNumber() * 0.9
		local props: PartKit.Props = {
			Name = "Rock",
			Parent = m,
			CFrame = cf * CFrame.new(math.cos(a) * r, size * 0.4, math.sin(a) * r) * CFrame.Angles(rng:NextNumber() * 3, rng:NextNumber() * 3, rng:NextNumber() * 3),
			Size = Vector3.new(size, size * 0.7, size * 1.2),
			Color = Color3.fromRGB(88, 82, 90),
			Material = Enum.Material.Slate,
		}
		if rng:NextNumber() < 0.5 then
			PartKit.wedge(props)
		else
			PartKit.part(props)
		end
	end
	return m
end

function Effects.kanji(parent: Instance?, cf: CFrame, text: string, width: number, height: number, color: Color3): (Part, TextLabel)
	local anchor = PartKit.part({ Name = "KanjiAnchor", Parent = parent, CFrame = cf, Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
	local _, label = PartKit.billboardText(anchor, text, width, height, color)
	return anchor, label
end

-- Burst of glowing needles for hit sparks.
function Effects.spikes(parent: Instance?, pos: Vector3, count: number, length: number, color: Color3, rng: Random): Model
	local m = PartKit.model("Spikes", parent)
	PartKit.ball(m, CFrame.new(pos), length * 0.55, { Color = Palette.White, Material = NEON }, "Flash")
	for _ = 1, count do
		local dir = randomUnit(rng)
		local len = length * (0.6 + rng:NextNumber() * 0.7)
		PartKit.segment({ Name = "Spike", Parent = m, Color = color, Material = NEON }, pos + dir * length * 0.2, pos + dir * len, 0.14 + rng:NextNumber() * 0.08)
	end
	return m
end

-- Three parallel claw arcs, as left by Rika's hand.
function Effects.claws(parent: Instance?, cf: CFrame, size: number, color: Color3): Model
	local m = PartKit.model("Claws", parent)
	for k = -1, 1 do
		Effects.slash(m, cf * CFrame.new(k * size * 0.3, 0, 0) * CFrame.Angles(0, 0, math.rad(72)), size, 80, size * 0.12, color, Palette.White, 10)
	end
	return m
end

function Effects.shadowPool(parent: Instance?, cf: CFrame, radius: number): Model
	local m = PartKit.model("ShadowPool", parent)
	PartKit.cylinderY({ Name = "Pool", Parent = m, CFrame = cf * CFrame.new(0, 0.1, 0), Color = Palette.Shadow }, 0.08, radius * 2)
	PartKit.ring(m, cf * CFrame.new(0, 0.13, 0), radius, 0.7, 0.06, 40, { Color = Palette.YutaEnergy, Material = NEON })
	PartKit.ring(m, cf * CFrame.new(0, 0.13, 0), radius * 0.62, 0.35, 0.06, 32, { Color = Palette.YutaEnergy, Material = NEON, Transparency = 0.5 })
	return m
end

function Effects.pillar(parent: Instance?, cf: CFrame, height: number, radius: number, color: Color3): Model
	local m = PartKit.model("Pillar", parent)
	PartKit.cylinderY({ Name = "Glow", Parent = m, CFrame = cf * CFrame.new(0, height / 2, 0), Color = color, Material = NEON, Transparency = 0.45 }, height, radius * 2)
	PartKit.cylinderY({ Name = "Core", Parent = m, CFrame = cf * CFrame.new(0, height / 2, 0), Color = Palette.White, Material = NEON }, height, radius * 0.7)
	return m
end

-- Rings of sound rippling forward from the speaker's mouth (cf faces forward).
function Effects.speechWaves(parent: Instance?, cf: CFrame, count: number, spacing: number, baseRadius: number, color: Color3): Model
	local m = PartKit.model("SpeechWaves", parent)
	for i = 1, count do
		PartKit.ring(m, cf * CFrame.new(0, 0, -i * spacing) * CFrame.Angles(math.rad(90), 0, 0), baseRadius * (1 + i * 0.55), 0.3, 0.18, 22, {
			Color = color,
			Material = NEON,
			Transparency = math.min(0.85, 0.15 + i * 0.12),
		})
	end
	return m
end

-- Fan of force lines for "Blast Away".
function Effects.cone(parent: Instance?, cf: CFrame, length: number, angleDegrees: number, color: Color3): Model
	local m = PartKit.model("Cone", parent)
	local rays = 9
	local arc = math.rad(angleDegrees)
	for i = 1, rays do
		local a = -arc / 2 + arc * (i - 0.5) / rays
		local dir = (cf * CFrame.Angles(0, a, 0)).LookVector
		PartKit.segment({ Name = "Ray", Parent = m, Color = color, Material = NEON, Transparency = 0.45 }, cf.Position + dir * 2, cf.Position + dir * length, 0.5, 0.12)
	end
	for _, f in { 0.35, 0.65, 0.95 } do
		PartKit.crescent(m, cf, length * f, angleDegrees, 1.1, 0.2, 16, { Color = Palette.White, Material = NEON, Transparency = 0.2 })
	end
	return m
end

function Effects.infinity(parent: Instance?, pos: Vector3, radius: number): Model
	local m = PartKit.model("Infinity", parent)
	PartKit.ball(m, CFrame.new(pos), radius * 2, { Color = Palette.SixEyes, Material = Enum.Material.ForceField }, "Shell")
	for i, tilt in { 0, 60, -60 } do
		PartKit.ring(m, CFrame.new(pos) * CFrame.Angles(math.rad(tilt), math.rad(i * 40), 0), radius * 1.02, 0.12, 0.08, 20, {
			Color = Palette.SixEyes,
			Material = NEON,
			Transparency = 0.35,
		})
	end
	return m
end

-- Curved translucent guard in front of a character (cf = root, facing forward).
function Effects.guard(parent: Instance?, cf: CFrame): Model
	local m = PartKit.model("Guard", parent)
	for i = -3, 3 do
		local a = math.rad(i * 18)
		local panel = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, -2.6)
		PartKit.part({ Name = "Panel", Parent = m, CFrame = panel, Size = Vector3.new(0.86, 5.4, 0.08), Color = Palette.YutaEnergy, Material = NEON, Transparency = 0.72 })
		PartKit.part({ Name = "Line", Parent = m, CFrame = panel * CFrame.new(0, 2.7, 0), Size = Vector3.new(0.86, 0.08, 0.1), Color = Palette.YutaCore, Material = NEON })
	end
	m.PrimaryPart = m:FindFirstChild("Panel") :: BasePart?
	return m
end

-- Imaginary mass: violet orb crackling with arcs of energy.
function Effects.purple(parent: Instance?, pos: Vector3, radius: number, rng: Random): Model
	local m = Effects.orb(parent, pos, radius, Palette.PurpleCore, Palette.Purple)
	m.Name = "HollowPurple"
	for _ = 1, 10 do
		local dir = randomUnit(rng)
		local p = pos + dir * radius * 1.05
		for _ = 1, 4 do
			local q = pos + (dir + randomUnit(rng) * 0.45).Unit * radius * (1.0 + rng:NextNumber() * 0.4)
			PartKit.segment({ Name = "Arc", Parent = m, Color = Palette.PurpleCore, Material = NEON }, p, q, 0.22)
			p = q
		end
	end
	for i, tilt in { 20, -35, 70 } do
		PartKit.ring(m, CFrame.new(pos) * CFrame.Angles(math.rad(tilt), math.rad(i * 55), 0), radius * 1.6, 0.35, 0.2, 30, {
			Color = Palette.Purple,
			Material = NEON,
			Transparency = 0.3,
		})
	end
	return m
end

-- Blue: a crushing point of attraction wrapped in inward spirals.
function Effects.blue(parent: Instance?, pos: Vector3, radius: number): Model
	local m = Effects.orb(parent, pos, radius * 0.18, Palette.BlueCore, Palette.Blue)
	m.Name = "Blue"
	for k = 1, 3 do
		local r = radius * (0.35 + k * 0.2)
		PartKit.ring(m, CFrame.new(pos) * CFrame.Angles(math.rad(-20 + k * 15), math.rad(k * 40), 0), r, 0.3, 0.15, 26, {
			Color = Palette.Blue,
			Material = NEON,
			Transparency = 0.2 + k * 0.15,
		})
	end
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local r = radius * (0.3 + (i % 4) * 0.15)
		local p = pos + Vector3.new(math.cos(a) * r, (i % 3 - 1) * 1.2, math.sin(a) * r)
		local q = pos + Vector3.new(math.cos(a + 0.9) * r * 0.55, (i % 3 - 1) * 0.6, math.sin(a + 0.9) * r * 0.55)
		PartKit.segment({ Name = "Streak", Parent = m, Color = Palette.BlueCore, Material = NEON, Transparency = 0.3 }, p, q, 0.18)
	end
	return m
end

-- Red: an unstable repelling orb ringed with spikes.
function Effects.red(parent: Instance?, pos: Vector3, radius: number, rng: Random): Model
	local m = Effects.orb(parent, pos, radius, Palette.RedCore, Palette.Red)
	m.Name = "Red"
	for _ = 1, 12 do
		local dir = randomUnit(rng)
		PartKit.segment({ Name = "Spike", Parent = m, Color = Palette.Red, Material = NEON }, pos + dir * radius, pos + dir * radius * 2.6, 0.2)
	end
	return m
end

return Effects
