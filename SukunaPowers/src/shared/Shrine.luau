--[[
	Shrine — builds Sukuna's Malevolent Shrine (伏魔御厨子) out of parts:
	stone base, red lacquer pillars, a fanged maw glowing from within,
	two tiers of temple roofs, horns on the ridge, lanterns and piles of skulls.

	Local space: origin = ground centre, -Z = the front of the shrine.
]]

local Shrine = {}

local COL = {
	stone = Color3.fromRGB(44, 38, 40),
	stoneDark = Color3.fromRGB(28, 24, 26),
	wood = Color3.fromRGB(56, 20, 18),
	lacquer = Color3.fromRGB(125, 16, 20),
	roof = Color3.fromRGB(24, 20, 22),
	trim = Color3.fromRGB(165, 122, 62),
	bone = Color3.fromRGB(228, 216, 192),
	flesh = Color3.fromRGB(96, 24, 30),
	maw = Color3.fromRGB(80, 0, 4),
	black = Color3.fromRGB(10, 6, 6),
}

local M = Enum.Material

function Shrine.build(origin: CFrame, scale: number?)
	local s = scale or 1
	local rng = Random.new()
	local model = Instance.new("Model")
	model.Name = "MalevolentShrine"

	local function P(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, className: string?)
		local p = Instance.new(className or "Part") :: BasePart
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Size = size * s
		p.CFrame = origin * (CFrame.new(cf.Position * s) * cf.Rotation)
		p.Color = color
		p.Material = material or M.SmoothPlastic
		p.Parent = model
		return p
	end

	local function cylinder(a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local p = P(Vector3.new(len, d, d), CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0), color, material)
		p.Shape = Enum.PartType.Cylinder
		return p
	end

	local function ball(pos: Vector3, d: number, color: Color3, material: Enum.Material?)
		local p = P(Vector3.one * d, CFrame.new(pos), color, material)
		p.Shape = Enum.PartType.Ball
		return p
	end

	local VERTICAL = CFrame.Angles(0, 0, math.pi / 2)

	------------------------------------------------------------------
	-- Stone base + stairs
	------------------------------------------------------------------
	local base = P(Vector3.new(46, 2, 36), CFrame.new(0, 1, 0), COL.stoneDark, M.Slate)
	P(Vector3.new(40, 2, 30), CFrame.new(0, 3, 0), COL.stone, M.Slate)
	P(Vector3.new(34, 1.4, 24), CFrame.new(0, 4.7, 0), COL.wood, M.WoodPlanks)
	P(Vector3.new(12, 0.7, 2), CFrame.new(0, 0.35, -19), COL.stone, M.Slate)
	P(Vector3.new(12, 1, 2), CFrame.new(0, 2.5, -16), COL.stone, M.Slate)
	P(Vector3.new(12, 0.7, 2), CFrame.new(0, 4.35, -13), COL.stone, M.Slate)

	------------------------------------------------------------------
	-- Pillars and walls
	------------------------------------------------------------------
	for _, x in { -14, -6, 6, 14 } do
		for _, z in { -10, 10 } do
			local pillar = P(Vector3.new(15, 1.8, 1.8), CFrame.new(x, 12.9, z) * VERTICAL, COL.lacquer, M.SmoothPlastic)
			pillar.Shape = Enum.PartType.Cylinder
			P(Vector3.new(2.6, 0.8, 2.6), CFrame.new(x, 5.8, z), COL.stone, M.Slate)
			P(Vector3.new(2.6, 0.6, 2.6), CFrame.new(x, 20.1, z), COL.trim, M.Metal)
		end
	end
	P(Vector3.new(28, 15, 0.8), CFrame.new(0, 12.9, 10.4), COL.wood, M.WoodPlanks)
	P(Vector3.new(0.8, 15, 20), CFrame.new(-14.4, 12.9, 0), COL.wood, M.WoodPlanks)
	P(Vector3.new(0.8, 15, 20), CFrame.new(14.4, 12.9, 0), COL.wood, M.WoodPlanks)
	for _, x in { -10, 10 } do
		P(Vector3.new(7, 15, 0.6), CFrame.new(x, 12.9, -10.2), COL.wood, M.WoodPlanks)
		for _, y in { 8.5, 12.9, 17.3 } do
			P(Vector3.new(7.2, 0.4, 0.8), CFrame.new(x, y, -10.4), COL.lacquer)
		end
		for _, dx in { -1.8, 0, 1.8 } do
			P(Vector3.new(0.3, 14, 0.75), CFrame.new(x + dx, 12.9, -10.4), COL.stoneDark)
		end
	end
	P(Vector3.new(32, 1.2, 1.4), CFrame.new(0, 20.1, -10.2), COL.lacquer)
	P(Vector3.new(32, 1.2, 1.4), CFrame.new(0, 20.1, 10.2), COL.lacquer)

	------------------------------------------------------------------
	-- The maw: glowing throat, gums and fangs
	------------------------------------------------------------------
	local maw = P(Vector3.new(10.4, 14, 0.4), CFrame.new(0, 12.6, -8.6), COL.maw, M.Neon)
	local mawLight = Instance.new("PointLight")
	mawLight.Color = Color3.fromRGB(255, 30, 30)
	mawLight.Range = 34 * s
	mawLight.Brightness = 5
	mawLight.Parent = maw
	P(Vector3.new(11, 2.4, 1.8), CFrame.new(0, 18.8, -10.2), COL.flesh)
	P(Vector3.new(11, 1.6, 1.8), CFrame.new(0, 6.2, -10.2), COL.flesh)
	local diamond = CFrame.Angles(0, 0, math.rad(45))
	for _, x in { -4.5, -3, -1.5, 0, 1.5, 3, 4.5 } do
		local size = if math.abs(x) == 3 then 1.9 else 1.1
		P(Vector3.new(size, size, 0.7), CFrame.new(x, 17.6, -10.2) * diamond, COL.bone)
	end
	for _, x in { -3.75, -2.25, -0.75, 0.75, 2.25, 3.75 } do
		local size = if math.abs(x) == 2.25 then 1.6 else 1.0
		P(Vector3.new(size, size, 0.7), CFrame.new(x, 7.0, -10.2) * diamond, COL.bone)
	end

	------------------------------------------------------------------
	-- Lower roof (solid gable from two wedges) + eaves, rafters, upturns
	------------------------------------------------------------------
	P(Vector3.new(42, 6, 15), CFrame.new(0, 23.4, -7.5), COL.roof, M.Slate, "WedgePart")
	P(Vector3.new(42, 6, 15), CFrame.new(0, 23.4, 7.5) * CFrame.Angles(0, math.pi, 0), COL.roof, M.Slate, "WedgePart")
	P(Vector3.new(42, 0.5, 0.6), CFrame.new(0, 20.4, -15), COL.lacquer)
	P(Vector3.new(42, 0.5, 0.6), CFrame.new(0, 20.4, 15), COL.lacquer)
	P(Vector3.new(44, 1, 1), CFrame.new(0, 26.6, 0), COL.roof, M.Slate)
	for _, x in { -22.3, 22.3 } do
		P(Vector3.new(1.2, 1.4, 1.4), CFrame.new(x, 26.8, 0), COL.trim, M.Metal)
	end
	for x = -20, 20, 2.5 do
		P(Vector3.new(0.4, 0.4, 2.6), CFrame.new(x, 20.05, -13.6), COL.wood)
		P(Vector3.new(0.4, 0.4, 2.6), CFrame.new(x, 20.05, 13.6), COL.wood)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = Vector3.new(21 * sx, 20.6, 15 * sz)
			P(Vector3.new(0.7, 0.7, 3.2), CFrame.lookAt(corner, corner + Vector3.new(sx, 0.9, sz)), COL.trim, M.Metal)
		end
	end

	------------------------------------------------------------------
	-- Upper hall + nameplate + upper roof
	------------------------------------------------------------------
	P(Vector3.new(18, 5, 12), CFrame.new(0, 26.6, 0), COL.wood, M.WoodPlanks)
	for _, x in { -8.6, 8.6 } do
		for _, z in { -5.6, 5.6 } do
			local post = P(Vector3.new(5, 0.9, 0.9), CFrame.new(x, 26.6, z) * VERTICAL, COL.lacquer)
			post.Shape = Enum.PartType.Cylinder
		end
	end
	P(Vector3.new(20, 0.4, 0.4), CFrame.new(0, 25, -6.6), COL.lacquer)
	local plaque = P(Vector3.new(7, 1.8, 0.3), CFrame.new(0, 26.8, -6.2), COL.black)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	surface.Parent = plaque
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.GothamBlack
	text.Text = "伏魔御厨子"
	text.TextScaled = true
	text.TextColor3 = COL.trim
	text.Parent = surface

	P(Vector3.new(30, 5, 11), CFrame.new(0, 31.6, -5.5), COL.roof, M.Slate, "WedgePart")
	P(Vector3.new(30, 5, 11), CFrame.new(0, 31.6, 5.5) * CFrame.Angles(0, math.pi, 0), COL.roof, M.Slate, "WedgePart")
	P(Vector3.new(30, 0.4, 0.5), CFrame.new(0, 29.1, -11), COL.lacquer)
	P(Vector3.new(30, 0.4, 0.5), CFrame.new(0, 29.1, 11), COL.lacquer)
	P(Vector3.new(31, 0.9, 0.9), CFrame.new(0, 34.2, 0), COL.roof, M.Slate)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = Vector3.new(15 * sx, 29.3, 11 * sz)
			P(Vector3.new(0.6, 0.6, 2.6), CFrame.lookAt(corner, corner + Vector3.new(sx, 0.9, sz)), COL.trim, M.Metal)
		end
	end

	------------------------------------------------------------------
	-- Horns on the ridge
	------------------------------------------------------------------
	for _, sx in { -1, 1 } do
		local pts = {
			Vector3.new(3 * sx, 34.4, 0),
			Vector3.new(6.5 * sx, 37, 0),
			Vector3.new(8 * sx, 40.5, 0),
			Vector3.new(7.2 * sx, 43.5, 0),
		}
		local widths = { 1.4, 1.05, 0.65 }
		for i = 1, 3 do
			cylinder(pts[i], pts[i + 1], widths[i], COL.bone)
			ball(pts[i + 1], widths[i] * 0.95, COL.bone)
		end
		ball(pts[1], 1.6, COL.bone)
	end

	------------------------------------------------------------------
	-- Lanterns
	------------------------------------------------------------------
	for _, x in { -9, 9 } do
		local z = -24
		P(Vector3.new(1.6, 0.6, 1.6), CFrame.new(x, 0.3, z), COL.stone, M.Slate)
		P(Vector3.new(0.7, 3, 0.7), CFrame.new(x, 2.1, z), COL.stone, M.Slate)
		local lamp = P(Vector3.new(1.4, 1.4, 1.4), CFrame.new(x, 4.3, z), Color3.fromRGB(255, 70, 40), M.Neon)
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 60, 40)
		l.Range = 14 * s
		l.Brightness = 2
		l.Parent = lamp
		P(Vector3.new(2.2, 0.4, 2.2), CFrame.new(x, 5.2, z), COL.stone, M.Slate)
		P(Vector3.new(0.8, 0.6, 0.8), CFrame.new(x, 5.7, z), COL.stone, M.Slate)
	end

	------------------------------------------------------------------
	-- Skulls and bones scattered around the shrine
	------------------------------------------------------------------
	local function skull(pos: Vector3, facing: Vector3, size: number)
		local cf = CFrame.lookAt(pos, pos + facing) * CFrame.Angles(math.rad(rng:NextNumber(-20, 20)), 0, math.rad(rng:NextNumber(-25, 25)))
		local function at(offset: Vector3)
			return (cf * (offset * size))
		end
		ball(pos, 1.7 * size, COL.bone)
		ball(at(Vector3.new(0.33, 0.1, -0.68)), 0.5 * size, COL.black)
		ball(at(Vector3.new(-0.33, 0.1, -0.68)), 0.5 * size, COL.black)
		ball(at(Vector3.new(0, -0.2, -0.8)), 0.28 * size, COL.black)
		P(Vector3.new(1.0, 0.45, 0.8) * size, cf * CFrame.new(Vector3.new(0, -0.62, -0.28) * size), COL.bone)
	end
	for _ = 1, 34 do
		local ang = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(1.0, 1.35)
		local pos = Vector3.new(math.cos(ang) * 24 * r, 0.6, math.sin(ang) * 19 * r)
		if not (math.abs(pos.X) < 7 and pos.Z < -17) then -- keep the stairs clear
			skull(pos, Vector3.new(pos.X, 0, pos.Z).Unit, rng:NextNumber(0.8, 1.25))
		end
	end
	for i = 1, 6 do
		local x = (i % 2 == 0 and 1 or -1) * rng:NextNumber(8, 14)
		skull(Vector3.new(x, 2.7, -16.3), Vector3.new(0, 0, -1), 0.75)
	end
	for _ = 1, 12 do
		local ang = rng:NextNumber(0, math.pi * 2)
		local center = Vector3.new(math.cos(ang) * rng:NextNumber(24, 32), 0.3, math.sin(ang) * rng:NextNumber(20, 27))
		local dir = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)).Unit * 1.5
		cylinder(center - dir, center + dir, 0.35, COL.bone)
		ball(center - dir, 0.6, COL.bone)
		ball(center + dir, 0.6, COL.bone)
	end

	------------------------------------------------------------------
	-- Embers rising from the roof and smoke at the base
	------------------------------------------------------------------
	local emberHolder = P(Vector3.new(36, 1, 26), CFrame.new(0, 24, 0), COL.black)
	emberHolder.Transparency = 1
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 70, 60), Color3.fromRGB(150, 0, 10))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(2, 4)
	embers.Speed = NumberRange.new(2, 7)
	embers.SpreadAngle = Vector2.new(60, 60)
	embers.Acceleration = Vector3.new(0, 4, 0)
	embers.Rate = 40
	embers.Parent = emberHolder

	local smokeHolder = P(Vector3.new(46, 1, 36), CFrame.new(0, 1, 0), COL.black)
	smokeHolder.Transparency = 1
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(30, 8, 10))
	smoke.LightInfluence = 1
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 9) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(3, 5)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.Rate = 8
	smoke.Parent = smokeHolder

	model.PrimaryPart = base
	model.WorldPivot = origin
	return model, 44 * s
end

return Shrine
