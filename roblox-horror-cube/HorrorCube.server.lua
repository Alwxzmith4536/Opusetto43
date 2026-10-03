--[[
	HorrorCube  (Script)
	Put this in:  ServerScriptService

	A plain white cube sits in the world. Click it and:
	  1. the lights die and the cube convulses in the dark
	  2. the sky slams to crimson, fog rolls in, a bloom/colour-grade "redcore" look fades up
	  3. the corruption spreads outward from the cube - every part bleeds to rotten red,
	     lights turn red and flicker, terrain and water turn to blood
	  4. the cube becomes a levitating, throbbing, bleeding heart with a watching eye above it

	Pair it with HorrorClient (LocalScript, StarterPlayerScripts) for camera shake,
	blood rain, vignette, heartbeat pulse and scare text. This script works without it.

	Tip: any part/model with the attribute  HorrorIgnore = true  is left untouched.
]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local CONFIG = {
	CubePosition = Vector3.new(0, 5, 0),
	CubeSize = Vector3.new(6, 6, 6),
	ClickDistance = 40, -- studs

	BlackoutTime = 1.8, -- seconds of darkness + convulsing before the red slam
	TransitionTime = 9, -- seconds for sky / fog / terrain to rot
	SpreadSpeed = 45, -- studs per second the corruption travels out from the cube
	MaxSpreadTime = 25, -- big maps: never take longer than this to finish spreading

	SlowWalkSpeed = 11, -- players get slower and heavier. Set to nil to disable.

	-- Replace these with your own Creator Store audio ("rbxassetid://123456") for a much
	-- scarier result. The defaults are a built-in Roblox sound pitched way down.
	Sounds = {
		Sting = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 4, Speed = 0.5 },
		Drone = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 1.5, Speed = 0.3 },
	},
}

local COLORS = {
	Blood = Color3.fromRGB(170, 0, 0),
	Ambient = Color3.fromRGB(75, 0, 0),
	OutdoorAmbient = Color3.fromRGB(95, 6, 6),
	LightRed = Color3.fromRGB(255, 20, 20),
}

local TERRAIN_MATERIALS = {
	Enum.Material.Grass, Enum.Material.LeafyGrass, Enum.Material.Sand, Enum.Material.Sandstone,
	Enum.Material.Rock, Enum.Material.Ground, Enum.Material.Mud, Enum.Material.Slate,
	Enum.Material.Basalt, Enum.Material.Limestone, Enum.Material.Pavement, Enum.Material.Asphalt,
	Enum.Material.Cobblestone, Enum.Material.Concrete, Enum.Material.Brick, Enum.Material.WoodPlanks,
	Enum.Material.Snow, Enum.Material.Ice, Enum.Material.Glacier, Enum.Material.Salt,
}

-- Part materials that may randomly turn into something rotten
local ROTTABLE = {
	[Enum.Material.Plastic] = true,
	[Enum.Material.SmoothPlastic] = true,
	[Enum.Material.Grass] = true,
	[Enum.Material.Sand] = true,
	[Enum.Material.Wood] = true,
	[Enum.Material.WoodPlanks] = true,
	[Enum.Material.Fabric] = true,
	[Enum.Material.Ground] = true,
	[Enum.Material.Mud] = true,
}
local ROTTEN_MATERIALS = {
	Enum.Material.Slate, Enum.Material.Basalt, Enum.Material.Concrete, Enum.Material.Granite,
}

local SCARY_RED_DARK = Color3.fromRGB(190, 25, 25)

----------------------------------------------------------------------
-- STATE / REMOTE
----------------------------------------------------------------------
local remote = ReplicatedStorage:FindFirstChild("HorrorCubeEvent")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "HorrorCubeEvent"
	remote.Parent = ReplicatedStorage
end

local state = "idle" -- idle -> blackout -> active
local flickering = {} -- { {light = Light, base = number}, ... }

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function tween(instance, duration, goal, style, direction)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Sine, direction or Enum.EasingDirection.InOut),
		goal
	)
	t:Play()
	return t
end

-- Runs step(alpha) as alpha goes 0 -> 1 (for things TweenService can't tween directly)
local function animate(duration, step)
	local value = Instance.new("NumberValue")
	value.Changed:Connect(step)
	local t = TweenService:Create(value, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = 1 })
	t.Completed:Connect(function()
		value:Destroy()
	end)
	t:Play()
end

local function getEffect(className, name)
	local effect = Lighting:FindFirstChildOfClass(className)
	if not effect then
		effect = Instance.new(className)
		effect.Name = name
		effect.Parent = Lighting
		return effect, true
	end
	return effect, false
end

local function makeSound(settings, looped)
	if not settings or settings.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = settings.Id
	sound.Volume = settings.Volume
	sound.PlaybackSpeed = settings.Speed
	sound.Looped = looped
	sound.Parent = SoundService

	local distortion = Instance.new("DistortionSoundEffect")
	distortion.Level = 0.55
	distortion.Parent = sound

	local reverb = Instance.new("ReverbSoundEffect")
	reverb.DecayTime = 5
	reverb.Density = 1
	reverb.Diffusion = 1
	reverb.DryLevel = -3
	reverb.WetLevel = 2
	reverb.Parent = sound
	return sound
end

----------------------------------------------------------------------
-- THE CUBE
----------------------------------------------------------------------
local cube = Instance.new("Part")
cube.Name = "HorrorCube"
cube.Size = CONFIG.CubeSize
cube.CFrame = CFrame.new(CONFIG.CubePosition)
cube.Anchored = true
cube.Material = Enum.Material.SmoothPlastic
cube.Color = Color3.fromRGB(235, 235, 235)
cube:SetAttribute("HorrorIgnore", true)
cube.Parent = workspace

local click = Instance.new("ClickDetector")
click.MaxActivationDistance = CONFIG.ClickDistance
click.Parent = cube

local cubeLight = Instance.new("PointLight")
cubeLight.Color = Color3.new(1, 1, 1)
cubeLight.Range = 18
cubeLight.Brightness = 1
cubeLight.Parent = cube

-- innocent idle "breathing" glow so people want to click it
local idleGlow = TweenService:Create(
	cubeLight,
	TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
	{ Brightness = 0.2 }
)
idleGlow:Play()

local sounds = {
	Sting = makeSound(CONFIG.Sounds.Sting, false),
	Drone = makeSound(CONFIG.Sounds.Drone, true),
}

----------------------------------------------------------------------
-- THE EYE (floats above the cube once it has transformed)
----------------------------------------------------------------------
local function round(parent, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(radius, 0)
	corner.Parent = parent
end

local function outline(parent, color, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = parent
end

local function buildEye()
	local gui = Instance.new("BillboardGui")
	gui.Name = "WatchingEye"
	gui.Size = UDim2.fromScale(8, 4.8) -- scale = studs for BillboardGui
	gui.StudsOffset = Vector3.new(0, CONFIG.CubeSize.Y * 0.5 + 6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = cube

	local sclera = Instance.new("Frame")
	sclera.AnchorPoint = Vector2.new(0.5, 0.5)
	sclera.Position = UDim2.fromScale(0.5, 0.5)
	sclera.Size = UDim2.fromScale(0, 0)
	sclera.BackgroundColor3 = Color3.fromRGB(235, 215, 205)
	sclera.BorderSizePixel = 0
	sclera.Parent = gui
	round(sclera, 0.5)
	outline(sclera, Color3.fromRGB(40, 0, 0), 4)

	local bloodshot = Instance.new("UIGradient")
	bloodshot.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 10, 10)),
		ColorSequenceKeypoint.new(0.28, Color3.fromRGB(235, 215, 205)),
		ColorSequenceKeypoint.new(0.72, Color3.fromRGB(235, 215, 205)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 10, 10)),
	})
	bloodshot.Parent = sclera

	local iris = Instance.new("Frame")
	iris.AnchorPoint = Vector2.new(0.5, 0.5)
	iris.Position = UDim2.fromScale(0.5, 0.5)
	iris.Size = UDim2.fromScale(0.5, 0.95)
	iris.BackgroundColor3 = Color3.fromRGB(190, 0, 0)
	iris.BorderSizePixel = 0
	iris.Parent = sclera
	round(iris, 0.5)
	outline(iris, Color3.fromRGB(60, 0, 0), 3)
	local irisRatio = Instance.new("UIAspectRatioConstraint")
	irisRatio.AspectRatio = 1
	irisRatio.Parent = iris

	local pupil = Instance.new("Frame")
	pupil.AnchorPoint = Vector2.new(0.5, 0.5)
	pupil.Position = UDim2.fromScale(0.5, 0.5)
	pupil.Size = UDim2.fromScale(0.16, 0.85)
	pupil.BackgroundColor3 = Color3.new(0, 0, 0)
	pupil.BorderSizePixel = 0
	pupil.Parent = iris
	round(pupil, 0.5)

	local shine = Instance.new("Frame")
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.3, 0.26)
	shine.Size = UDim2.fromScale(0.14, 0.14)
	shine.BackgroundColor3 = Color3.fromRGB(255, 235, 235)
	shine.BackgroundTransparency = 0.25
	shine.BorderSizePixel = 0
	shine.Parent = iris
	round(shine, 0.5)
	local shineRatio = Instance.new("UIAspectRatioConstraint")
	shineRatio.AspectRatio = 1
	shineRatio.Parent = shine

	tween(sclera, 1.2, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

	task.spawn(function()
		task.wait(1.5)
		while sclera.Parent do
			task.wait(1.2 + math.random() * 3)
			tween(sclera, 0.07, { Size = UDim2.fromScale(1, 0.05) }).Completed:Wait()
			tween(sclera, 0.12, { Size = UDim2.fromScale(1, 1) }).Completed:Wait()
			if math.random() < 0.5 then
				local drift = (math.random() - 0.5) * 0.14
				tween(iris, 0.08, { Position = UDim2.fromScale(0.5 + drift, 0.5) })
			end
		end
	end)
end

----------------------------------------------------------------------
-- WORLD CORRUPTION
----------------------------------------------------------------------
local function isIgnored(instance)
	local current = instance
	while current and current ~= workspace do
		if current == cube or current:GetAttribute("HorrorIgnore") then
			return true
		end
		-- leave players and NPCs alone
		if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
			return true
		end
		current = current.Parent
	end
	return false
end

local function collectTargets(origin)
	local list = {}
	for _, instance in ipairs(workspace:GetDescendants()) do
		local position = nil
		if instance:IsA("Terrain") then
			position = nil
		elseif instance:IsA("BasePart") then
			if instance.Transparency < 1 then
				position = instance.Position
			end
		elseif instance:IsA("Decal") or instance:IsA("Texture") or instance:IsA("Light") then
			local parent = instance.Parent
			if parent and parent:IsA("BasePart") then
				position = parent.Position
			elseif parent and parent:IsA("Attachment") then
				position = parent.WorldPosition
			end
		end
		if position and not isIgnored(instance) then
			table.insert(list, { instance = instance, dist = (position - origin).Magnitude })
		end
	end
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)
	return list
end

local function corrupt(instance)
	if not instance.Parent then
		return
	end
	if instance:IsA("BasePart") then
		local _, _, value = instance.Color:ToHSV()
		local hue = (0.985 + math.random() * 0.03) % 1
		local goal = Color3.fromHSV(hue, 0.85 + math.random() * 0.15, math.clamp(value * 0.5, 0.07, 0.55))
		tween(instance, 1.6, { Color = goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		if ROTTABLE[instance.Material] and math.random() < 0.45 then
			task.delay(0.8, function()
				if instance.Parent then
					instance.Material = ROTTEN_MATERIALS[math.random(#ROTTEN_MATERIALS)]
				end
			end)
		end
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		tween(instance, 1.6, { Color3 = SCARY_RED_DARK })
	elseif instance:IsA("Light") then
		tween(instance, 1.2, { Color = COLORS.LightRed })
		table.insert(flickering, { light = instance, base = instance.Brightness })
	end
end

local function spreadCorruption(origin)
	local targets = collectTargets(origin)
	local total = #targets
	if total == 0 then
		return
	end
	local speed = math.max(CONFIG.SpreadSpeed, targets[total].dist / CONFIG.MaxSpreadTime)

	task.spawn(function()
		local started = os.clock()
		local index = 1
		while index <= total do
			local radius = (os.clock() - started) * speed
			local processed = 0
			while index <= total and targets[index].dist <= radius and processed < 250 do
				corrupt(targets[index].instance)
				index = index + 1
				processed = processed + 1
			end
			task.wait()
		end
	end)
end

local function corruptTerrain(duration)
	local terrain = workspace.Terrain
	local from, to = {}, {}
	for _, material in ipairs(TERRAIN_MATERIALS) do
		local ok, color = pcall(function()
			return terrain:GetMaterialColor(material)
		end)
		if ok then
			local _, _, value = color:ToHSV()
			from[material] = color
			to[material] = Color3.fromHSV(0.99, 0.85, math.clamp(value * 0.45, 0.08, 0.5))
		end
	end

	local lastStep = -1
	animate(duration, function(alpha)
		-- throttle: terrain recolouring is not free
		if alpha < 1 and alpha - lastStep < 0.05 then
			return
		end
		lastStep = alpha
		for material, color in pairs(from) do
			terrain:SetMaterialColor(material, color:Lerp(to[material], alpha))
		end
	end)

	tween(terrain, duration, {
		WaterColor = Color3.fromRGB(110, 0, 0),
		WaterTransparency = 0.1,
		WaterReflectance = 0.6,
		WaterWaveSize = 0.35,
	})
end

local function startFlicker()
	task.spawn(function()
		while true do
			task.wait(0.05 + math.random() * 0.2)
			for _, entry in ipairs(flickering) do
				local light = entry.light
				if light.Parent then
					local roll = math.random()
					if roll < 0.08 then
						light.Brightness = 0
					elseif roll < 0.2 then
						light.Brightness = entry.base * (0.3 + math.random())
					else
						light.Brightness = entry.base
					end
				end
			end
		end
	end)
end

----------------------------------------------------------------------
-- LIGHTING
----------------------------------------------------------------------
local function blackout()
	Lighting.ClockTime = 0
	Lighting.Brightness = 0
	Lighting.Ambient = Color3.new(0, 0, 0)
	Lighting.OutdoorAmbient = Color3.new(0, 0, 0)
end

local function redSlam(duration)
	Lighting.ClockTime = 18.1 -- blood sunset that never ends

	local atmosphere, newAtmosphere = getEffect("Atmosphere", "HorrorAtmosphere")
	if newAtmosphere then
		atmosphere.Density = 0
		atmosphere.Offset = 0
		atmosphere.Haze = 0
		atmosphere.Glare = 0
	end
	local color, newColor = getEffect("ColorCorrectionEffect", "HorrorColor")
	local bloom, newBloom = getEffect("BloomEffect", "HorrorBloom")
	if newBloom then
		bloom.Intensity = 0
		bloom.Threshold = 2
	end
	local depth, newDepth = getEffect("DepthOfFieldEffect", "HorrorDepth")
	if newDepth then
		depth.FarIntensity = 0
		depth.NearIntensity = 0
	end
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")

	tween(Lighting, 2.5, {
		Ambient = COLORS.Ambient,
		OutdoorAmbient = COLORS.OutdoorAmbient,
		Brightness = 0.3,
		ExposureCompensation = -0.3,
	})
	tween(atmosphere, duration, {
		Density = 0.55,
		Offset = 0.3,
		Haze = 3.2,
		Glare = 0.8,
		Color = Color3.fromRGB(160, 14, 14),
		Decay = Color3.fromRGB(70, 0, 0),
	})
	tween(color, duration, {
		TintColor = Color3.fromRGB(255, 90, 90),
		Contrast = 0.35,
		Saturation = -0.15,
		Brightness = -0.06,
	})
	tween(bloom, duration, { Intensity = 0.8, Size = 40, Threshold = 0.9 })
	tween(depth, duration, { FarIntensity = 0.5, FocusDistance = 25, InFocusRadius = 60 })
	if sunRays then
		tween(sunRays, duration, { Intensity = 0 })
	end
end

----------------------------------------------------------------------
-- THE CUBE'S TRANSFORMATION
----------------------------------------------------------------------
local function convulse(duration)
	local home = cube.CFrame
	cubeLight.Enabled = true
	cubeLight.Color = COLORS.LightRed
	cubeLight.Range = 40

	local started = os.clock()
	while os.clock() - started < duration do
		local ramp = (os.clock() - started) / duration
		local amount = 0.05 + ramp * 0.55
		cube.CFrame = home
			* CFrame.new((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, (math.random() - 0.5) * amount)
			* CFrame.Angles(
				math.rad((math.random() - 0.5) * 8 * ramp),
				math.rad((math.random() - 0.5) * 8 * ramp),
				math.rad((math.random() - 0.5) * 8 * ramp)
			)
		cube.Color = Color3.fromRGB(math.random(0, 120), 0, 0)
		cubeLight.Brightness = math.random() * 4
		task.wait(0.03)
	end
	cube.CFrame = home
	cube.Color = Color3.new(0, 0, 0)
	return home
end

local function transformCube(home)
	idleGlow:Cancel()
	cube.Material = Enum.Material.Neon
	tween(cube, 1, { Color = COLORS.Blood })

	cubeLight.Brightness = 4
	cubeLight.Range = 70
	table.insert(flickering, { light = cubeLight, base = 4 })

	-- slowly rises
	tween(cube, 6, { CFrame = home + Vector3.new(0, 3, 0) })

	-- throbs like a heart
	TweenService:Create(
		cube,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = CONFIG.CubeSize * 1.12 }
	):Play()

	-- bleeds
	local drip = Instance.new("ParticleEmitter")
	drip.Color = ColorSequence.new(Color3.fromRGB(150, 0, 0))
	drip.LightEmission = 0.25
	drip.LightInfluence = 0
	drip.Size = NumberSequence.new(0.35, 0.15)
	drip.Lifetime = NumberRange.new(1.4, 2.2)
	drip.Rate = 22
	drip.Speed = NumberRange.new(0, 1)
	drip.Acceleration = Vector3.new(0, -28, 0)
	drip.EmissionDirection = Enum.NormalId.Bottom
	drip.Parent = cube
end

local function spawnBloodPool()
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { cube }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local result = workspace:Raycast(cube.Position, Vector3.new(0, -200, 0), params)
	if not result then
		return
	end

	local pool = Instance.new("Part")
	pool.Name = "BloodPool"
	pool.Shape = Enum.PartType.Cylinder
	pool.Anchored = true
	pool.CanCollide = false
	pool.CanQuery = false
	pool.CanTouch = false
	pool.CastShadow = false
	pool.Material = Enum.Material.SmoothPlastic
	pool.Reflectance = 0.2
	pool.Color = Color3.fromRGB(120, 0, 0)
	pool.Size = Vector3.new(0.1, 0.5, 0.5)
	pool.CFrame = CFrame.new(result.Position + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90))
	pool:SetAttribute("HorrorIgnore", true)
	pool.Parent = workspace

	tween(pool, 12, { Size = Vector3.new(0.1, 26, 26) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
end

----------------------------------------------------------------------
-- PLAYERS
----------------------------------------------------------------------
local function weigh(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and CONFIG.SlowWalkSpeed then
		humanoid.WalkSpeed = CONFIG.SlowWalkSpeed
	end
end

local function hookPlayer(player)
	player.CharacterAdded:Connect(weigh)
	if player.Character then
		task.spawn(weigh, player.Character)
	end
end

Players.PlayerAdded:Connect(function(player)
	if state ~= "idle" then
		hookPlayer(player)
	end
end)

-- a client announces it is ready; if the nightmare already started, catch it up
remote.OnServerEvent:Connect(function(player, message)
	if message == "Ready" and state == "active" then
		remote:FireClient(player, "Resume")
	end
end)

----------------------------------------------------------------------
-- CLICK!
----------------------------------------------------------------------
click.MouseClick:Connect(function()
	if state ~= "idle" then
		return
	end
	state = "blackout"
	click:Destroy()

	local origin = cube.Position
	remote:FireAllClients("Blackout")
	if sounds.Sting then
		sounds.Sting:Play()
	end

	for _, player in ipairs(Players:GetPlayers()) do
		hookPlayer(player)
	end

	blackout()
	local home = convulse(CONFIG.BlackoutTime)

	-- the slam
	state = "active"
	remote:FireAllClients("Slam")
	if sounds.Drone then
		sounds.Drone:Play()
	end
	redSlam(CONFIG.TransitionTime)
	corruptTerrain(CONFIG.TransitionTime)
	spreadCorruption(origin)
	transformCube(home)
	spawnBloodPool()
	startFlicker()

	task.delay(3, buildEye)
end)
