--[[
	============================================================
	  HORROR CUBE  ·  Server
	============================================================
	Where:  ServerScriptService  ->  Script

	A cursed black cube floats near the spawn. When a player clicks it,
	the world rots into a red nightmare for EVERYONE:
	  • the sun sinks, the sky drowns in thick blood-red fog
	  • a wave of blood spreads out from the cube and stains every part
	  • plastic turns to concrete, grass to mud, metal to rust
	  • terrain darkens and the water turns to blood
	  • every light turns red and starts to flicker
	  • red glows and pools of blood appear around the map

	Pair it with "HorrorClient" (LocalScript in StarterPlayerScripts)
	for sounds, heartbeat, camera shake, the Watcher and jumpscares.

	Tips:
	  • Already have your own cube? Name it "HorrorCube" and put it in
	    Workspace - the script will use it instead of making one.
	  • Tag any part or model with "HorrorIgnore" to keep it untouched.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

------------------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------------------
local CONFIG = {
	CubeSize = 5,
	CubePosition = nil, -- Vector3.new(x, y, z), or nil = automatic (in front of the spawn)
	ClickDistance = 40, -- how close you must be to click the cube
	AllowRevert = false, -- true = click the cube again to bring the normal world back

	TransitionTime = 8, -- seconds for the sky to turn
	WaveSpeed = 70, -- studs per second the blood wave spreads from the cube
	MaxStainedObjects = 8000, -- safety limit for huge maps
	BloodColor = Color3.fromRGB(75, 6, 6),
	BloodStrength = 0.72, -- 0 = keep original colors, 1 = everything becomes BloodColor
	RotMaterials = true, -- plastic -> concrete, grass -> mud, metal -> rust...

	RedLights = 16, -- creepy flickering red lights scattered around
	BloodPools = 24, -- puddles of blood on the ground
	ScatterRadius = 160, -- how far from the cube the lights and pools appear
}

local FLICKER_TAG = "HorrorFlicker" -- lights with this tag flicker on every client
local IGNORE_TAG = "HorrorIgnore" -- tag parts/models with this to protect them

------------------------------------------------------------------------
-- WHAT THE NIGHTMARE LOOKS LIKE
------------------------------------------------------------------------
local NIGHT_LIGHTING = {
	Brightness = 0.4,
	Ambient = Color3.fromRGB(45, 4, 4),
	OutdoorAmbient = Color3.fromRGB(75, 10, 10),
	ColorShift_Top = Color3.fromRGB(150, 10, 10),
	ColorShift_Bottom = Color3.fromRGB(50, 0, 0),
	FogColor = Color3.fromRGB(40, 0, 0),
	FogStart = 0,
	FogEnd = 220,
	ExposureCompensation = -0.2,
	EnvironmentDiffuseScale = 0.15,
	EnvironmentSpecularScale = 0.5,
}

local NIGHT_ATMOSPHERE = {
	Density = 0.6,
	Offset = 0.25,
	Color = Color3.fromRGB(110, 12, 12),
	Decay = Color3.fromRGB(35, 0, 0),
	Glare = 0,
	Haze = 2.5,
}

local NIGHT_WATER = {
	WaterColor = Color3.fromRGB(95, 4, 4),
	WaterTransparency = 0.05,
	WaterReflectance = 0.35,
	WaterWaveSize = 0.08,
	WaterWaveSpeed = 3,
}

local ROTTEN_MATERIAL = {
	[Enum.Material.Plastic] = Enum.Material.Concrete,
	[Enum.Material.SmoothPlastic] = Enum.Material.Concrete,
	[Enum.Material.Grass] = Enum.Material.Mud,
	[Enum.Material.LeafyGrass] = Enum.Material.Mud,
	[Enum.Material.Sand] = Enum.Material.Ground,
	[Enum.Material.Snow] = Enum.Material.Ground,
	[Enum.Material.Marble] = Enum.Material.Slate,
	[Enum.Material.Metal] = Enum.Material.CorrodedMetal,
	[Enum.Material.DiamondPlate] = Enum.Material.CorrodedMetal,
	[Enum.Material.Foil] = Enum.Material.CorrodedMetal,
}

local TERRAIN_MATERIALS = {
	Enum.Material.Grass,
	Enum.Material.LeafyGrass,
	Enum.Material.Ground,
	Enum.Material.Mud,
	Enum.Material.Sand,
	Enum.Material.Sandstone,
	Enum.Material.Rock,
	Enum.Material.Slate,
	Enum.Material.Basalt,
	Enum.Material.Snow,
	Enum.Material.Glacier,
	Enum.Material.Ice,
	Enum.Material.Concrete,
	Enum.Material.Asphalt,
	Enum.Material.Brick,
	Enum.Material.Cobblestone,
	Enum.Material.Pavement,
	Enum.Material.Limestone,
	Enum.Material.Salt,
	Enum.Material.WoodPlanks,
	Enum.Material.CrackedLava,
}

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function tween(instance, seconds, goal, style)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		goal
	)
	t:Play()
	return t
end

-- darken a color, then soak it in blood
local function rot(color)
	return color:Lerp(Color3.new(0, 0, 0), 0.35):Lerp(CONFIG.BloodColor, CONFIG.BloodStrength)
end

-- players, NPCs and anything tagged HorrorIgnore are left alone
local function isProtected(instance)
	local node = instance
	while node and node ~= workspace do
		if CollectionService:HasTag(node, IGNORE_TAG) then
			return true
		end
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then
			return true
		end
		node = node.Parent
	end
	return false
end

local function positionOf(instance)
	if instance:IsA("BasePart") then
		return instance.Position
	end
	local parent = instance.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	return nil
end

local function raycastDown(from, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore or {}
	params.IgnoreWater = true
	return workspace:Raycast(from, Vector3.new(0, -300, 0), params)
end

local function characters()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

------------------------------------------------------------------------
-- THE CUBE
------------------------------------------------------------------------
local function defaultCubePosition()
	if CONFIG.CubePosition then
		return CONFIG.CubePosition
	end
	local spawnCFrame = CFrame.new(0, 0, 0)
	local spawnLocation = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		spawnCFrame = spawnLocation.CFrame
	end
	local forward = spawnCFrame.LookVector * Vector3.new(1, 0, 1)
	forward = if forward.Magnitude > 0.1 then forward.Unit else Vector3.new(0, 0, -1)
	local spot = spawnCFrame.Position + forward * 10
	local hit = raycastDown(spot + Vector3.new(0, 15, 0))
	local groundY = if hit then hit.Position.Y else spawnCFrame.Position.Y
	return Vector3.new(spot.X, groundY + CONFIG.CubeSize / 2 + 2.5, spot.Z)
end

local cube = workspace:FindFirstChild("HorrorCube")
if not (cube and cube:IsA("BasePart")) then
	cube = Instance.new("Part")
	cube.Name = "HorrorCube"
	cube.Size = Vector3.one * CONFIG.CubeSize
	cube.Material = Enum.Material.CrackedLava
	cube.Color = Color3.fromRGB(18, 18, 20)
	cube.CFrame = CFrame.new(defaultCubePosition()) * CFrame.Angles(0, math.rad(45), 0)
	cube.Parent = workspace
end
cube.Anchored = true
-- the client animates the cube (float, spin, tremble, heartbeat) around these values
cube:SetAttribute("BaseCFrame", cube.CFrame)
cube:SetAttribute("BaseSize", cube.Size)
CollectionService:AddTag(cube, IGNORE_TAG)

local CUBE_COLOR = cube.Color
local OUTLINE_COLOR = Color3.fromRGB(110, 0, 0)

local outline = Instance.new("SelectionBox")
outline.Name = "CursedOutline"
outline.Adornee = cube
outline.Color3 = OUTLINE_COLOR
outline.LineThickness = 0.04
outline.SurfaceTransparency = 1
outline.Parent = cube

local glow = Instance.new("PointLight")
glow.Name = "CursedGlow"
glow.Color = Color3.fromRGB(255, 30, 20)
glow.Range = 10
glow.Brightness = 1.5
glow.Shadows = true
glow.Parent = cube

local mist = Instance.new("ParticleEmitter")
mist.Name = "RedMist"
mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
mist.Color = ColorSequence.new(Color3.fromRGB(120, 0, 0), Color3.fromRGB(10, 0, 0))
mist.Size = NumberSequence.new(0.6, 2.4)
mist.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.2, 0.6),
	NumberSequenceKeypoint.new(1, 1),
})
mist.Lifetime = NumberRange.new(2, 3.5)
mist.Speed = NumberRange.new(0.3, 1)
mist.SpreadAngle = Vector2.new(180, 180)
mist.Acceleration = Vector3.new(0, 0.8, 0)
mist.Rotation = NumberRange.new(0, 360)
mist.RotSpeed = NumberRange.new(-30, 30)
mist.LightInfluence = 0.3
mist.Rate = 5
mist.Parent = cube

-- floating label so the cube is easy to find from far away
local marker = Instance.new("BillboardGui")
marker.Name = "Marker"
marker.Size = UDim2.fromOffset(160, 40)
marker.StudsOffset = Vector3.new(0, cube.Size.Y / 2 + 2, 0)
marker.AlwaysOnTop = true
marker.MaxDistance = 500
local markerText = Instance.new("TextLabel")
markerText.Size = UDim2.fromScale(1, 1)
markerText.BackgroundTransparency = 1
markerText.Font = Enum.Font.Creepster
markerText.TextScaled = true
markerText.TextColor3 = Color3.fromRGB(220, 0, 0)
markerText.TextStrokeTransparency = 0
markerText.Text = "DON'T CLICK"
markerText.Parent = marker
marker.Parent = cube

print("[HorrorCube] Cube spawned at", cube.Position)

local click = Instance.new("ClickDetector")
click.MaxActivationDistance = CONFIG.ClickDistance
click.Parent = cube

local function wakeCube()
	tween(cube, 1.5, { Color = Color3.fromRGB(45, 4, 4) })
	tween(outline, 1.5, { Color3 = Color3.fromRGB(255, 0, 0), LineThickness = 0.09 })
	tween(glow, 1.5, { Range = 24, Brightness = 4 })
	mist.Rate = 30

	local fire = Instance.new("Fire")
	fire.Name = "HellFire"
	fire.Color = Color3.fromRGB(150, 0, 0)
	fire.SecondaryColor = Color3.fromRGB(0, 0, 0)
	fire.Heat = 14
	fire.Size = math.clamp(cube.Size.Magnitude * 0.8, 2, 30)
	fire.Parent = cube

	click.MaxActivationDistance = if CONFIG.AllowRevert then CONFIG.ClickDistance else 0
end

local function calmCube()
	tween(cube, 2, { Color = CUBE_COLOR })
	tween(outline, 2, { Color3 = OUTLINE_COLOR, LineThickness = 0.04 })
	tween(glow, 2, { Range = 10, Brightness = 1.5 })
	mist.Rate = 5
	local fire = cube:FindFirstChild("HellFire")
	if fire then
		fire:Destroy()
	end
	click.MaxActivationDistance = CONFIG.ClickDistance
end

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local active = false
local busy = false
local wave = 0 -- bumps every time the world changes state, which stops old loops
local fxFolder = nil
local saved = nil -- everything we changed, so the world can be restored

------------------------------------------------------------------------
-- THE SKY DIES
------------------------------------------------------------------------
local function darkenSky()
	local seconds = CONFIG.TransitionTime

	-- sink the sun: forward through sunset in the afternoon, back through dawn in the morning
	local goal = table.clone(NIGHT_LIGHTING)
	for property in pairs(NIGHT_LIGHTING) do
		saved.lighting[property] = Lighting[property]
	end
	saved.lighting.ClockTime = Lighting.ClockTime
	goal.ClockTime = if Lighting.ClockTime >= 12 then 24 else 0
	tween(Lighting, seconds, goal)

	-- thick blood fog
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		saved.atmosphere = {}
		for property in pairs(NIGHT_ATMOSPHERE) do
			saved.atmosphere[property] = atmosphere[property]
		end
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "HorrorAtmosphere"
		atmosphere.Density = 0
		atmosphere.Haze = 0
		atmosphere.Glare = 0
		atmosphere.Parent = Lighting
		saved.createdAtmosphere = true
	end
	saved.atmosphereInstance = atmosphere
	tween(atmosphere, seconds, NIGHT_ATMOSPHERE)

	-- no stars, a swollen moon
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		saved.sky = { instance = sky, StarCount = sky.StarCount, MoonAngularSize = sky.MoonAngularSize }
		sky.StarCount = 0
		tween(sky, seconds, { MoonAngularSize = 30 })
	end

	-- film look: drained colors, red tint, glowing lights, blurry distance
	local function effect(className, name, neutral, goalProps)
		local instance = Instance.new(className)
		instance.Name = name
		for property, value in pairs(neutral) do
			instance[property] = value
		end
		instance.Parent = Lighting
		saved.effects[instance] = neutral
		tween(instance, seconds, goalProps)
	end
	effect(
		"ColorCorrectionEffect",
		"HorrorGrade",
		{ TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 },
		{ TintColor = Color3.fromRGB(255, 165, 160), Saturation = -0.45, Contrast = 0.35, Brightness = -0.03 }
	)
	effect("BloomEffect", "HorrorBloom", { Intensity = 0, Size = 40, Threshold = 0.9 }, { Intensity = 1.2 })
	effect(
		"DepthOfFieldEffect",
		"HorrorDepth",
		{ FarIntensity = 0, FocusDistance = 25, InFocusRadius = 45, NearIntensity = 0 },
		{ FarIntensity = 0.35 }
	)
end

------------------------------------------------------------------------
-- THE BLOOD WAVE
------------------------------------------------------------------------
local function stain(object)
	if not object.Parent then
		return
	end

	if object:IsA("BasePart") then
		if saved.parts[object] then
			return
		end
		local original = { Color = object.Color, Material = object.Material }
		saved.parts[object] = original
		local goal = if object.Material == Enum.Material.Neon then Color3.fromRGB(255, 20, 10) else rot(object.Color)
		tween(object, 1.8, { Color = goal })

		local rotten = CONFIG.RotMaterials and ROTTEN_MATERIAL[object.Material]
		if rotten then
			task.delay(0.9, function()
				if saved and saved.parts[object] == original then
					object.Material = rotten
				end
			end)
		end
	elseif object:IsA("Decal") then -- Textures too
		if saved.decals[object] then
			return
		end
		local color = object.Color3
		saved.decals[object] = color
		tween(object, 1.8, { Color3 = Color3.new(color.R * 0.65, color.G * 0.12, color.B * 0.12) })
	elseif object:IsA("Light") then
		if saved.lights[object] then
			return
		end
		saved.lights[object] = { Color = object.Color, Brightness = object.Brightness }
		object:SetAttribute("BaseBrightness", object.Brightness)
		tween(object, 1.2, { Color = Color3.fromRGB(255, 35, 25) })
		CollectionService:AddTag(object, FLICKER_TAG)
	end
end

local function bloodWave(myWave)
	local origin = cube.Position
	local targets = {}
	for _, object in ipairs(workspace:GetDescendants()) do
		local wanted = false
		if object:IsA("BasePart") then
			wanted = not object:IsA("Terrain") and object.Transparency < 1 and not isProtected(object)
		elseif object:IsA("Decal") or object:IsA("Light") then
			wanted = not isProtected(object)
		end
		if wanted then
			local position = positionOf(object)
			if position then
				table.insert(targets, { object = object, distance = (position - origin).Magnitude })
			end
		end
	end
	table.sort(targets, function(a, b)
		return a.distance < b.distance
	end)

	-- spread outwards from the cube like a ripple
	local count = math.min(#targets, CONFIG.MaxStainedObjects)
	local started = os.clock()
	local index = 1
	while index <= count and wave == myWave do
		local reach = (os.clock() - started) * CONFIG.WaveSpeed
		while index <= count and targets[index].distance <= reach do
			stain(targets[index].object)
			index += 1
		end
		task.wait()
	end
end

local function stainTerrain(myWave)
	local terrain = workspace.Terrain
	local originals = {}
	for _, material in ipairs(TERRAIN_MATERIALS) do
		local ok, color = pcall(terrain.GetMaterialColor, terrain, material)
		if ok then
			originals[material] = color
		end
	end
	saved.terrain = originals
	saved.water = {}
	for property in pairs(NIGHT_WATER) do
		saved.water[property] = terrain[property]
	end
	tween(terrain, CONFIG.TransitionTime, NIGHT_WATER)

	local steps = 40
	for step = 1, steps do
		task.wait(CONFIG.TransitionTime / steps)
		if wave ~= myWave then
			return
		end
		local alpha = step / steps
		for material, color in pairs(originals) do
			pcall(terrain.SetMaterialColor, terrain, material, color:Lerp(rot(color), alpha))
		end
	end
end

------------------------------------------------------------------------
-- RED LIGHTS AND BLOOD POOLS
------------------------------------------------------------------------
local function makeRedLight(position)
	local holder = Instance.new("Part")
	holder.Name = "RedGlow"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CFrame = CFrame.new(position + Vector3.new(0, 5 + math.random() * 4, 0))

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 25, 15)
	light.Range = 14 + math.random() * 12
	light.Brightness = 2.2
	light.Shadows = true
	light:SetAttribute("BaseBrightness", 2.2)
	light.Parent = holder

	holder.Parent = fxFolder
	CollectionService:AddTag(light, FLICKER_TAG)
end

local function makeBloodPool(position)
	local size = 3 + math.random() * 6
	local pool = Instance.new("Part")
	pool.Name = "BloodPool"
	pool.Shape = Enum.PartType.Cylinder
	pool.Size = Vector3.new(0.05, 0.2, 0.2)
	-- a cylinder lies along X: tip it up so it becomes a flat disc
	pool.CFrame = CFrame.new(position + Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, math.random() * math.pi, math.rad(90))
	pool.Color = Color3.fromRGB(95, 0, 0)
	pool.Material = Enum.Material.Glass
	pool.Reflectance = 0.25
	pool.Anchored = true
	pool.CanCollide = false
	pool.CanQuery = false
	pool.CanTouch = false
	pool.CastShadow = false
	pool.Parent = fxFolder
	tween(pool, 4, { Size = Vector3.new(0.05, size, size) }, Enum.EasingStyle.Quad)
end

local function scatterHorrors(myWave)
	local origin = cube.Position
	local ignore = characters()
	table.insert(ignore, cube)
	table.insert(ignore, fxFolder)

	for i = 1, CONFIG.RedLights + CONFIG.BloodPools do
		local angle = math.random() * math.pi * 2
		local distance = 10 + math.random() * CONFIG.ScatterRadius
		local spot = origin + Vector3.new(math.cos(angle), 0, math.sin(angle)) * distance
		local hit = raycastDown(spot + Vector3.new(0, 60, 0), ignore)
		if hit and hit.Normal.Y > 0.7 then
			local isLight = i <= CONFIG.RedLights
			local groundPosition = hit.Position
			-- appear when the blood wave reaches them
			task.delay(distance / CONFIG.WaveSpeed, function()
				if wave ~= myWave or not fxFolder then
					return
				end
				if isLight then
					makeRedLight(groundPosition)
				else
					makeBloodPool(groundPosition)
				end
			end)
		end
	end
end

------------------------------------------------------------------------
-- AWAKEN / RESTORE
------------------------------------------------------------------------
local function awaken(player)
	busy = true
	active = true
	wave += 1
	local myWave = wave
	saved = { lighting = {}, effects = {}, parts = {}, decals = {}, lights = {}, terrain = {} }

	fxFolder = Instance.new("Folder")
	fxFolder.Name = "HorrorFX"
	CollectionService:AddTag(fxFolder, IGNORE_TAG)
	fxFolder.Parent = workspace

	-- clients watch this attribute and start their screen effects, sounds and scares
	ReplicatedStorage:SetAttribute("HorrorTriggeredBy", player.DisplayName)
	ReplicatedStorage:SetAttribute("HorrorTriggeredById", player.UserId)
	ReplicatedStorage:SetAttribute("HorrorActive", true)

	wakeCube()
	task.wait(0.8) -- let the scream hit before the sky turns
	darkenSky()
	task.spawn(bloodWave, myWave)
	task.spawn(stainTerrain, myWave)
	task.spawn(scatterHorrors, myWave)

	task.wait(2)
	busy = false
end

local function restoreWorld()
	busy = true
	wave += 1
	ReplicatedStorage:SetAttribute("HorrorActive", false)

	local seconds = 3
	local data = saved
	saved = nil

	if data then
		tween(Lighting, seconds, data.lighting)

		local atmosphere = data.atmosphereInstance
		if atmosphere and atmosphere.Parent then
			if data.createdAtmosphere then
				tween(atmosphere, seconds, { Density = 0, Haze = 0 })
				task.delay(seconds, function()
					atmosphere:Destroy()
				end)
			elseif data.atmosphere then
				tween(atmosphere, seconds, data.atmosphere)
			end
		end

		if data.sky and data.sky.instance.Parent then
			data.sky.instance.StarCount = data.sky.StarCount
			tween(data.sky.instance, seconds, { MoonAngularSize = data.sky.MoonAngularSize })
		end

		for effect, neutral in pairs(data.effects) do
			tween(effect, seconds, neutral)
			task.delay(seconds, function()
				effect:Destroy()
			end)
		end

		for part, original in pairs(data.parts) do
			if part.Parent then
				part.Material = original.Material
				tween(part, seconds, { Color = original.Color })
			end
		end

		for decal, color in pairs(data.decals) do
			if decal.Parent then
				tween(decal, seconds, { Color3 = color })
			end
		end

		for light, original in pairs(data.lights) do
			CollectionService:RemoveTag(light, FLICKER_TAG)
			light:SetAttribute("BaseBrightness", nil)
			if light.Parent then
				light.Brightness = original.Brightness
				tween(light, seconds, { Color = original.Color })
			end
		end

		local terrain = workspace.Terrain
		for material, color in pairs(data.terrain) do
			pcall(terrain.SetMaterialColor, terrain, material, color)
		end
		if data.water then
			tween(terrain, seconds, data.water)
		end
	end

	if fxFolder then
		fxFolder:Destroy()
		fxFolder = nil
	end
	calmCube()

	task.wait(seconds)
	active = false
	busy = false
end

click.MouseClick:Connect(function(player)
	if busy then
		return
	end
	if not active then
		awaken(player)
	elseif CONFIG.AllowRevert then
		restoreWorld()
	end
end)

ReplicatedStorage:SetAttribute("HorrorActive", false)
