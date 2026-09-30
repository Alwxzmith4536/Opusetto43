-- Builds the ritual arena at runtime (so the place file needs no pre-made parts):
-- a dark stone plaza, Mahoraga's altar with a torii gate, lantern pillars, walls and lighting.

local Lighting = game:GetService("Lighting")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("TenShadows").Config)

local Arena = {}

local function part(props, parent)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function lighting()
	Lighting.ClockTime = 18.6
	Lighting.Brightness = 2
	Lighting.Ambient = Color3.fromRGB(40, 34, 60)
	Lighting.OutdoorAmbient = Color3.fromRGB(70, 60, 95)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	local function effect(class, props)
		local e = Lighting:FindFirstChild("TS_" .. class) or Instance.new(class)
		e.Name = "TS_" .. class
		for k, v in pairs(props) do
			e[k] = v
		end
		e.Parent = Lighting
	end
	effect("Atmosphere", { Density = 0.38, Offset = 0.1, Color = Color3.fromRGB(150, 130, 190), Decay = Color3.fromRGB(60, 40, 90), Glare = 0.4, Haze = 1.6 })
	effect("BloomEffect", { Intensity = 0.9, Size = 28, Threshold = 1.4 })
	effect("ColorCorrectionEffect", { Contrast = 0.12, Saturation = -0.08, TintColor = Color3.fromRGB(240, 232, 255) })
	effect("SunRaysEffect", { Intensity = 0.06, Spread = 0.6 })
end

function Arena.Build()
	if workspace:FindFirstChild("TenShadowsArena") then
		return
	end
	local arena = Instance.new("Model")
	arena.Name = "TenShadowsArena"
	local C = Config.Arena
	local R = C.Radius

	-- floor: outer stone disc + inner marble ritual circle
	part({ Name = "Floor", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, R * 2, R * 2), CFrame = CFrame.new(C.Center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(38, 36, 46), Material = Enum.Material.Slate }, arena)
	part({ Name = "RitualCircle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 150, 150), CFrame = CFrame.new(C.Center + Vector3.new(0, 0.05, -20)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(58, 54, 70), Material = Enum.Material.Marble, CanCollide = false }, arena)
	-- glowing ring segments around the ritual circle
	for i = 0, 47 do
		local a = i / 48 * math.pi * 2
		local pos = C.Center + Vector3.new(math.cos(a) * 74, 0.12, -20 + math.sin(a) * 74)
		part({ Name = "Rune", Size = Vector3.new(0.6, 0.1, 8.6), CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))), Color = Color3.fromRGB(120, 70, 200), Material = Enum.Material.Neon, CanCollide = false, CastShadow = false }, arena)
	end
	-- eight spokes, echoing Mahoraga's wheel
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local pos = C.Center + Vector3.new(math.cos(a) * 37, 0.12, -20 + math.sin(a) * 37)
		part({ Name = "Spoke", Size = Vector3.new(0.5, 0.1, 70), CFrame = CFrame.lookAt(pos, pos + Vector3.new(math.cos(a), 0, math.sin(a))), Color = Color3.fromRGB(214, 178, 74), Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CastShadow = false }, arena)
	end

	-- altar + torii gate behind it
	local altar = C.BossAltar
	part({ Name = "Altar", Size = Vector3.new(26, 1.2, 26), CFrame = CFrame.new(altar + Vector3.new(0, 0.6, 0)), Color = Color3.fromRGB(28, 26, 34), Material = Enum.Material.Basalt }, arena)
	local gateZ = altar.Z - 30
	local red = Color3.fromRGB(150, 28, 36)
	for _, x in ipairs({ -16, 16 }) do
		part({ Name = "ToriiPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(40, 3, 3), CFrame = CFrame.new(x, 20, gateZ) * CFrame.Angles(0, 0, math.rad(90)), Color = red, Material = Enum.Material.WoodPlanks }, arena)
	end
	part({ Name = "ToriiKasagi", Size = Vector3.new(46, 2.4, 4), CFrame = CFrame.new(0, 41, gateZ), Color = Color3.fromRGB(24, 20, 24), Material = Enum.Material.Wood }, arena)
	part({ Name = "ToriiNuki", Size = Vector3.new(38, 1.6, 2.4), CFrame = CFrame.new(0, 34, gateZ), Color = red, Material = Enum.Material.WoodPlanks }, arena)
	part({ Name = "ToriiPlaque", Size = Vector3.new(4, 5, 0.6), CFrame = CFrame.new(0, 37.5, gateZ - 1.3), Color = Color3.fromRGB(214, 178, 74), Material = Enum.Material.Metal }, arena)

	-- lantern pillars around the edge
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		local pos = C.Center + Vector3.new(math.cos(a) * (R - 12), 0, math.sin(a) * (R - 12))
		part({ Name = "Pillar", Size = Vector3.new(4, 18, 4), CFrame = CFrame.new(pos + Vector3.new(0, 9, 0)), Color = Color3.fromRGB(50, 48, 58), Material = Enum.Material.Cobblestone }, arena)
		local lantern = part({ Name = "Lantern", Size = Vector3.new(3, 3, 3), CFrame = CFrame.new(pos + Vector3.new(0, 19.5, 0)), Color = Color3.fromRGB(150, 110, 255), Material = Enum.Material.Neon, CastShadow = false }, arena)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 110, 255)
		light.Range = 36
		light.Brightness = 2
		light.Shadows = true
		light.Parent = lantern
	end

	-- invisible boundary
	for i = 0, 35 do
		local a = i / 36 * math.pi * 2
		local pos = C.Center + Vector3.new(math.cos(a) * R, 40, math.sin(a) * R)
		part({ Name = "Wall", Size = Vector3.new(2, 80, 2 * math.pi * R / 36 + 2), CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a))) * CFrame.Angles(0, math.rad(90), 0), Transparency = 1, CanQuery = false }, arena)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(C.PlayerSpawn + Vector3.new(0, 0.5, 0))
	spawn.Color = Color3.fromRGB(60, 50, 80)
	spawn.Material = Enum.Material.Slate
	spawn.Duration = 0
	spawn.Parent = arena

	arena.Parent = workspace
	lighting()
	return arena
end

return Arena
