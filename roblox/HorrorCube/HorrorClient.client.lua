--[[
	============================================================
	  HORROR CUBE  ·  Client
	============================================================
	Where:  StarterPlayer  ->  StarterPlayerScripts  ->  LocalScript

	Everything each player sees, hears and feels once the cube wakes up:
	  • glitching screen, a scream, camera shake and creepy intro text
	  • the Watcher jumpscare at the end of the intro
	  • a heartbeat that gets faster the closer you are to the cube
	  • red pulsing vignette, VHS tracking line, falling ash and embers
	  • flickering red lights, every sound echoes like in a cave
	  • random scares: the Watcher standing in the fog (it vanishes when
	    you look at it), red lightning, whispers behind you,
	    subliminal messages, blackouts with something in the dark
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer

------------------------------------------------------------------------
-- SETTINGS
------------------------------------------------------------------------
local CONFIG = {
	Jumpscare = true, -- the Watcher lunges at your face at the end of the intro
	ShadowFigure = true, -- the Watcher appears in the fog / in blackouts
	RandomEventMin = 10, -- seconds between random scares
	RandomEventMax = 22,
	HorrorFOV = 60, -- the world feels tighter
	IntroText = "YOU SHOULDN'T HAVE TOUCHED IT",
	Whispers = {
		"IT SEES YOU",
		"DON'T LOOK BEHIND YOU",
		"YOU ARE NOT ALONE",
		"IT'S GETTING CLOSER",
		"RUN",
		"WHY DID YOU WAKE IT",
		"NO ONE IS COMING",
	},
}

-- Best result: paste your own horror audio here (Creator Store -> Audio -> copy the ID),
-- e.g.  Drone = "rbxassetid://1234567890"
-- Left empty = built-in Roblox sounds pitched way down (works with zero setup).
local SOUND_IDS = {
	Drone = "", -- long dark ambience (looped)
	Heartbeat = "", -- ONE heartbeat thump
	Scream = "", -- jumpscare scream
	Sting = "", -- short scary hit
	Thunder = "", -- thunder / boom
	Whisper = "", -- creepy whisper or groan
}

local FALLBACK_SOUNDS = {
	Drone = {
		id = "rbxasset://sounds/action_falling.mp3",
		speed = 0.2,
		volume = 1.6,
		customVolume = 0.6,
		looped = true,
		bass = true,
		reverb = true,
	},
	Heartbeat = { id = "rbxasset://sounds/action_jump_land.mp3", speed = 0.45, volume = 2.5, customVolume = 1, bass = true },
	Scream = { id = "rbxasset://sounds/uuhhh.mp3", speed = 0.6, volume = 3, customVolume = 1, distortion = 0.6, reverb = true },
	Sting = {
		id = "rbxasset://sounds/action_jump_land.mp3",
		speed = 0.28,
		volume = 3,
		customVolume = 0.8,
		distortion = 0.5,
		bass = true,
		reverb = true,
	},
	Thunder = {
		id = "rbxasset://sounds/action_jump_land.mp3",
		speed = 0.15,
		volume = 4,
		customVolume = 1,
		distortion = 0.35,
		bass = true,
		reverb = true,
	},
	Whisper = { id = "rbxasset://sounds/uuhhh.mp3", speed = 0.32, volume = 1.5, customVolume = 0.8, reverb = true },
}

local FLICKER_TAG = "HorrorFlicker"
local VIGNETTE_BASE = 0.3
local TINT_BASE = 0.92
local BLOOD_RED = Color3.fromRGB(200, 0, 0)
local WATCHER_BLACK = Color3.fromRGB(6, 6, 6)

------------------------------------------------------------------------
-- STATE
------------------------------------------------------------------------
local session = nil -- the running nightmare (nil while the world is normal)
local shake = 0 -- camera shake strength, fades by itself
local sway = 0 -- slow, sick camera sway while the nightmare runs
local cubeJitter = 0 -- how violently the cube trembles
local cubePulse = 0 -- heartbeat swell of the cube
local flickerBase = {} -- [light] = its normal brightness

------------------------------------------------------------------------
-- HELPERS
------------------------------------------------------------------------
local function tween(instance, seconds, goal, style)
	local t = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Sine), goal)
	t:Play()
	return t
end

local function addShake(amount)
	shake = math.max(shake, amount)
end

local function getRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function flatLook(cframe)
	local look = cframe.LookVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return look.Unit
end

local function closenessToCube()
	local root = getRoot()
	local cube = workspace:FindFirstChild("HorrorCube")
	if not (root and cube) then
		return 0
	end
	local distance = (root.Position - cube.Position).Magnitude
	return math.clamp(1 - (distance - 8) / 110, 0, 1)
end

local function findGround(position, fallbackY, s)
	local ignore = { s.folder, workspace.CurrentCamera }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(position + Vector3.new(0, 30, 0), Vector3.new(0, -120, 0), params)
	return if hit then hit.Position else Vector3.new(position.X, fallbackY, position.Z)
end

------------------------------------------------------------------------
-- SOUND
------------------------------------------------------------------------
local function createSound(kind, parent)
	local recipe = FALLBACK_SOUNDS[kind]
	local custom = SOUND_IDS[kind]
	local sound = Instance.new("Sound")
	sound.Name = kind
	sound.Looped = recipe.looped == true

	if custom and custom ~= "" then
		sound.SoundId = custom
		sound.Volume = recipe.customVolume
	else
		-- built-in sounds slowed down = deep, monstrous versions of themselves
		sound.SoundId = recipe.id
		sound.PlaybackSpeed = recipe.speed
		sound.Volume = recipe.volume
		if recipe.distortion then
			local distortion = Instance.new("DistortionSoundEffect")
			distortion.Level = recipe.distortion
			distortion.Parent = sound
		end
		if recipe.bass then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain = 8
			eq.MidGain = -3
			eq.HighGain = -15
			eq.Parent = sound
		end
	end

	if recipe.reverb then
		local reverb = Instance.new("ReverbSoundEffect")
		reverb.DecayTime = 3.5
		reverb.Density = 1
		reverb.Diffusion = 1
		reverb.DryLevel = -2
		reverb.WetLevel = -1
		reverb.Parent = sound
	end

	sound.Parent = parent
	return sound
end

------------------------------------------------------------------------
-- THE WATCHER  (tall black figure with glowing red eyes, built from parts)
------------------------------------------------------------------------
local function buildWatcher()
	local model = Instance.new("Model")
	model.Name = "Watcher"

	local function piece(name, size, cframe, color, material)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.CFrame = cframe
		part.Color = color or WATCHER_BLACK
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = model
		return part
	end

	-- pivot at the feet
	local root = piece("Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new())
	root.Transparency = 1
	model.PrimaryPart = root

	piece("LeftLeg", Vector3.new(0.5, 4.2, 0.5), CFrame.new(-0.45, 2.1, 0))
	piece("RightLeg", Vector3.new(0.5, 4.2, 0.5), CFrame.new(0.45, 2.1, 0))
	local torso = piece("Torso", Vector3.new(1.7, 3.4, 0.8), CFrame.new(0, 5.9, 0))
	piece("LeftArm", Vector3.new(0.38, 5.6, 0.38), CFrame.new(-1.12, 4.8, 0) * CFrame.Angles(0, 0, math.rad(-5)))
	piece("RightArm", Vector3.new(0.38, 5.6, 0.38), CFrame.new(1.12, 4.8, 0) * CFrame.Angles(0, 0, math.rad(5)))
	piece("Neck", Vector3.new(0.35, 0.7, 0.35), CFrame.new(0, 7.9, 0))
	-- head tilted to the side
	local head = piece("Head", Vector3.new(1.3, 1.6, 1.2), CFrame.new(0, 8.85, 0) * CFrame.Angles(0, 0, math.rad(9)))

	local eyeColor = Color3.fromRGB(255, 0, 0)
	piece("LeftEye", Vector3.new(0.3, 0.14, 0.08), head.CFrame * CFrame.new(-0.3, 0.18, -0.6), eyeColor, Enum.Material.Neon)
	piece("RightEye", Vector3.new(0.3, 0.14, 0.08), head.CFrame * CFrame.new(0.3, 0.18, -0.6), eyeColor, Enum.Material.Neon)
	piece(
		"Mouth",
		Vector3.new(0.75, 0.06, 0.06),
		head.CFrame * CFrame.new(0, -0.42, -0.6) * CFrame.Angles(0, 0, math.rad(-4)),
		Color3.fromRGB(120, 0, 0),
		Enum.Material.Neon
	)

	local eyeLight = Instance.new("PointLight")
	eyeLight.Color = eyeColor
	eyeLight.Range = 7
	eyeLight.Brightness = 3
	eyeLight.Parent = head

	-- black smoke bleeding off its body
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.new(0, 0, 0))
	smoke.Size = NumberSequence.new(1.5, 3.5)
	smoke.Transparency = NumberSequence.new(0.45, 1)
	smoke.Lifetime = NumberRange.new(1, 2)
	smoke.Rate = 18
	smoke.Speed = NumberRange.new(0.3, 1)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-40, 40)
	smoke.LightInfluence = 0
	smoke.Parent = torso

	return model
end

local function placeWatcher(watcher, feet, lookAt)
	watcher:PivotTo(CFrame.lookAt(feet, Vector3.new(lookAt.X, feet.Y, lookAt.Z)))
end

-- body melts away first, the eyes linger a moment longer
local function fadeWatcher(watcher)
	for _, object in ipairs(watcher:GetDescendants()) do
		if object:IsA("BasePart") and object.Name ~= "Root" then
			local delay = if object.Name:find("Eye") then 0.35 else 0
			task.delay(delay, function()
				if object.Parent then
					tween(object, 0.35, { Transparency = 1 })
				end
			end)
		elseif object:IsA("ParticleEmitter") then
			object.Enabled = false
		elseif object:IsA("PointLight") then
			tween(object, 0.7, { Brightness = 0 })
		end
	end
	Debris:AddItem(watcher, 1.2)
end

------------------------------------------------------------------------
-- SCREEN
------------------------------------------------------------------------
local function buildGui(s)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HorrorGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local function frame(name, zIndex, size, position, color, transparency)
		local f = Instance.new("Frame")
		f.Name = name
		f.BorderSizePixel = 0
		f.ZIndex = zIndex
		f.Size = size
		f.Position = position
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency
		f.Parent = gui
		return f
	end

	local function label(name, zIndex, font)
		local l = Instance.new("TextLabel")
		l.Name = name
		l.ZIndex = zIndex
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.BackgroundTransparency = 1
		l.Font = font
		l.TextScaled = true
		l.TextColor3 = BLOOD_RED
		l.TextStrokeColor3 = Color3.new(0, 0, 0)
		l.TextTransparency = 1
		l.TextStrokeTransparency = 1
		l.Parent = gui
		return l
	end

	-- faint red film over everything
	s.tint = frame("BloodTint", 1, UDim2.fromScale(1, 1), UDim2.new(), Color3.fromRGB(110, 0, 0), 1)

	-- dark-red vignette made of 4 gradient edges (no image assets needed)
	s.edges = {}
	local function edge(name, size, position, rotation)
		local f = frame(name, 2, size, position, Color3.new(1, 1, 1), 1)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation
		gradient.Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromRGB(60, 0, 0))
		gradient.Transparency = NumberSequence.new(0, 1)
		gradient.Parent = f
		table.insert(s.edges, f)
	end
	edge("VignetteLeft", UDim2.fromScale(0.3, 1), UDim2.fromScale(0, 0), 0)
	edge("VignetteRight", UDim2.fromScale(0.3, 1), UDim2.fromScale(0.7, 0), 180)
	edge("VignetteTop", UDim2.fromScale(1, 0.35), UDim2.fromScale(0, 0), 90)
	edge("VignetteBottom", UDim2.fromScale(1, 0.35), UDim2.fromScale(0, 0.65), 270)

	-- old VHS tape tracking line rolling down the screen
	s.band = frame("TrackingLine", 3, UDim2.fromScale(1, 0.1), UDim2.fromScale(0, -0.2), Color3.fromRGB(255, 220, 220), 0)
	local bandGradient = Instance.new("UIGradient")
	bandGradient.Rotation = 90
	bandGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.93),
		NumberSequenceKeypoint.new(1, 1),
	})
	bandGradient.Parent = s.band

	s.title = label("Title", 8, Enum.Font.Creepster)
	s.title.Size = UDim2.fromScale(0.85, 0.16)
	s.title.Position = UDim2.fromScale(0.5, 0.45)
	local maxSize = Instance.new("UITextSizeConstraint")
	maxSize.MaxTextSize = 110
	maxSize.Parent = s.title

	s.subtitle = label("Subtitle", 8, Enum.Font.SpecialElite)
	s.subtitle.Size = UDim2.fromScale(0.5, 0.05)
	s.subtitle.Position = UDim2.fromScale(0.5, 0.56)
	s.subtitle.TextColor3 = Color3.fromRGB(170, 150, 150)

	s.whisper = label("Whisper", 7, Enum.Font.Creepster)
	s.whisper.Size = UDim2.fromScale(0.5, 0.1)

	s.flash = frame("Flash", 10, UDim2.fromScale(1, 1), UDim2.new(), Color3.new(0, 0, 0), 1)

	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

local function setFlash(s, color, transparency, fadeSeconds)
	if s.flashTween then
		s.flashTween:Cancel()
	end
	s.flash.BackgroundColor3 = color
	s.flash.BackgroundTransparency = transparency
	if fadeSeconds then
		s.flashTween = tween(s.flash, fadeSeconds, { BackgroundTransparency = 1 })
	end
end

local function fadeInOverlays(s, seconds)
	for _, edge in ipairs(s.edges) do
		tween(edge, seconds, { BackgroundTransparency = VIGNETTE_BASE })
	end
	tween(s.tint, seconds, { BackgroundTransparency = TINT_BASE })
end

local function pulseVignette(s, strength)
	for _, edge in ipairs(s.edges) do
		edge.BackgroundTransparency = math.max(0, VIGNETTE_BASE - 0.3 * strength)
		tween(edge, 0.6, { BackgroundTransparency = VIGNETTE_BASE }, Enum.EasingStyle.Quad)
	end
	s.tint.BackgroundTransparency = TINT_BASE - 0.06 * strength
	tween(s.tint, 0.6, { BackgroundTransparency = TINT_BASE }, Enum.EasingStyle.Quad)
end

local function glitch(s, seconds)
	local stopAt = os.clock() + seconds
	while s.alive and os.clock() < stopAt do
		local color = if math.random() < 0.6 then Color3.fromRGB(150, 0, 0) else Color3.new(0, 0, 0)
		setFlash(s, color, 0.05 + math.random() * 0.5)
		task.wait(0.03 + math.random() * 0.05)
		setFlash(s, color, 1)
		task.wait(0.02 + math.random() * 0.08)
	end
end

local function showCreepyText(s, text, subtitle, hold)
	local title, sub = s.title, s.subtitle
	local home = title.Position
	title.Text = text
	title.MaxVisibleGraphemes = 0
	title.TextTransparency = 0
	title.TextStrokeTransparency = 0.15
	sub.Text = subtitle or ""

	-- letters tremble and flicker
	local jitter = RunService.RenderStepped:Connect(function()
		title.Position = home + UDim2.fromOffset(math.random(-3, 3), math.random(-3, 3))
		title.Rotation = (math.random() - 0.5) * 2.5
		title.TextTransparency = if math.random() < 0.07 then 0.75 else 0
	end)
	table.insert(s.cleanup, jitter)

	for i = 1, utf8.len(text) or #text do
		if not s.alive then
			break
		end
		title.MaxVisibleGraphemes = i
		task.wait(0.045)
	end
	if subtitle then
		tween(sub, 0.8, { TextTransparency = 0, TextStrokeTransparency = 0.5 })
	end
	task.wait(hold)

	jitter:Disconnect()
	title.Position = home
	title.Rotation = 0
	tween(title, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
	tween(sub, 0.6, { TextTransparency = 1, TextStrokeTransparency = 1 })
	task.wait(0.6)
end

------------------------------------------------------------------------
-- AMBIENCE
------------------------------------------------------------------------
local function makeAmbience(s)
	-- an invisible box that follows the camera and fills the air with ash and embers
	local volume = Instance.new("Part")
	volume.Name = "AshVolume"
	volume.Size = Vector3.new(90, 40, 90)
	volume.Transparency = 1
	volume.Anchored = true
	volume.CanCollide = false
	volume.CanQuery = false
	volume.CanTouch = false
	volume.CastShadow = false
	volume.Parent = s.folder

	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 80, 30), Color3.fromRGB(150, 0, 0))
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new(0.18, 0)
	embers.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	embers.Lifetime = NumberRange.new(4, 7)
	embers.Rate = 30
	embers.Speed = NumberRange.new(0.5, 2)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Acceleration = Vector3.new(0, 1.2, 0)
	embers.Drag = 0.5
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	embers.Parent = volume

	local ash = Instance.new("ParticleEmitter")
	ash.Name = "Ash"
	ash.Texture = "rbxasset://textures/particles/smoke_main.dds"
	ash.Color = ColorSequence.new(Color3.fromRGB(70, 62, 62))
	ash.LightInfluence = 1
	ash.Size = NumberSequence.new(0.25, 0.15)
	ash.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.1, 0.2),
		NumberSequenceKeypoint.new(0.85, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	ash.Lifetime = NumberRange.new(6, 10)
	ash.Rate = 45
	ash.Speed = NumberRange.new(0.2, 1)
	ash.SpreadAngle = Vector2.new(180, 180)
	ash.Acceleration = Vector3.new(0.3, -1, 0)
	ash.Rotation = NumberRange.new(0, 360)
	ash.RotSpeed = NumberRange.new(-120, 120)
	ash.Shape = Enum.ParticleEmitterShape.Box
	ash.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	ash.Parent = volume

	table.insert(
		s.cleanup,
		RunService.RenderStepped:Connect(function()
			local camera = workspace.CurrentCamera
			if camera then
				volume.CFrame = CFrame.new(camera.CFrame.Position)
			end
		end)
	)
end

local function restoreFlicker()
	for light, base in pairs(flickerBase) do
		if light.Parent then
			light.Brightness = base
		end
	end
	table.clear(flickerBase)
end

local function flickerLoop(s)
	while s.alive do
		for _, light in ipairs(CollectionService:GetTagged(FLICKER_TAG)) do
			if light:IsA("Light") then
				local base = flickerBase[light]
				if not base then
					base = light:GetAttribute("BaseBrightness") or light.Brightness
					flickerBase[light] = base
				end
				local roll = math.random()
				if s.blackout or roll < 0.05 then
					light.Brightness = 0
				elseif roll < 0.15 then
					light.Brightness = base * (0.2 + math.random() * 0.5)
				else
					light.Brightness = base * (0.9 + math.random() * 0.2)
				end
			end
		end
		task.wait(0.06 + math.random() * 0.1)
	end
end

local function heartbeatLoop(s)
	while s.alive do
		local near = closenessToCube()
		local interval = 60 / (60 + near * 75) -- 60 bpm far away, 135 bpm at the cube
		local loudness = 0.7 + near * 0.6

		s.sounds.Lub.Volume = s.lubVolume * loudness
		s.sounds.Lub:Play()
		pulseVignette(s, 0.6 + near * 0.6)
		cubePulse = 1
		task.wait(0.26)
		if not s.alive then
			break
		end

		s.sounds.Dub.Volume = s.dubVolume * loudness
		s.sounds.Dub:Play()
		pulseVignette(s, 0.35 + near * 0.4)
		cubePulse = math.max(cubePulse, 0.6)
		task.wait(math.max(0.15, interval - 0.26))
	end
end

local function vhsLoop(s)
	while s.alive do
		local seconds = 4 + math.random() * 4
		s.band.Position = UDim2.fromScale(0, -0.12)
		tween(s.band, seconds, { Position = UDim2.fromScale(0, 1.02) }, Enum.EasingStyle.Linear)
		task.wait(seconds + math.random() * 3)
	end
end

------------------------------------------------------------------------
-- SCARES
------------------------------------------------------------------------

-- The Watcher stands far away in the fog, staring. Look straight at it and it's gone.
local function stalk(s)
	local root = getRoot()
	if not root then
		return
	end
	local camera = workspace.CurrentCamera
	local side = if math.random() < 0.5 then -1 else 1
	local direction = CFrame.Angles(0, math.rad(math.random(70, 160)) * side, 0) * flatLook(camera.CFrame)
	local feet = findGround(root.Position + direction * math.random(30, 48), root.Position.Y - 3, s)

	local watcher = buildWatcher()
	placeWatcher(watcher, feet, root.Position)
	watcher.Parent = s.folder

	local born = os.clock()
	local seenAt = nil
	while s.alive and watcher.Parent do
		local currentRoot = getRoot()
		if currentRoot then
			placeWatcher(watcher, feet, currentRoot.Position) -- always facing you
		end
		local cameraCFrame = workspace.CurrentCamera.CFrame
		local toWatcher = (feet + Vector3.new(0, 7, 0) - cameraCFrame.Position).Unit
		if not seenAt and cameraCFrame.LookVector:Dot(toWatcher) > 0.94 then
			seenAt = os.clock()
			s.sounds.Sting:Play()
			addShake(0.8)
			pulseVignette(s, 1.5)
		end
		if (seenAt and os.clock() - seenAt > 0.7) or os.clock() - born > 10 then
			break
		end
		task.wait()
	end
	if watcher.Parent then
		fadeWatcher(watcher)
	end
end

local function lightning(s)
	for _ = 1, math.random(1, 3) do
		s.flashCC.Brightness = 0.5
		s.flashCC.TintColor = Color3.fromRGB(255, 120, 120)
		tween(s.flashCC, 0.15, { Brightness = 0, TintColor = Color3.new(1, 1, 1) })
		task.wait(0.08 + math.random() * 0.18)
	end
	task.wait(0.3 + math.random() * 0.9)
	if s.alive then
		s.sounds.Thunder:Play()
		addShake(1.5)
	end
end

-- a whisper right behind your back
local function whisperBehind(s)
	local root = getRoot()
	if not root then
		return
	end
	local cameraCFrame = workspace.CurrentCamera.CFrame
	local behind = -flatLook(cameraCFrame) * 6
	local side = cameraCFrame.RightVector * (math.random() - 0.5) * 8

	local source = Instance.new("Part")
	source.Name = "WhisperSource"
	source.Size = Vector3.new(0.2, 0.2, 0.2)
	source.Transparency = 1
	source.Anchored = true
	source.CanCollide = false
	source.CanQuery = false
	source.CanTouch = false
	source.Position = root.Position + behind + side + Vector3.new(0, 1.5, 0)
	source.Parent = s.folder

	local sound = createSound("Whisper", source)
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = 60
	sound:Play()
	Debris:AddItem(source, 15)
end

-- words flashing on screen for a split second
local function subliminal(s)
	for _ = 1, math.random(2, 4) do
		if not s.alive then
			return
		end
		local label = s.whisper
		label.Text = CONFIG.Whispers[math.random(#CONFIG.Whispers)]
		label.Position = UDim2.fromScale(0.2 + math.random() * 0.6, 0.2 + math.random() * 0.6)
		label.Rotation = math.random(-12, 12)
		label.TextTransparency = 0
		label.TextStrokeTransparency = 0.3
		setFlash(s, Color3.fromRGB(90, 0, 0), 0.6, 0.15)
		addShake(0.6)
		task.wait(0.07 + math.random() * 0.08)
		label.TextTransparency = 1
		label.TextStrokeTransparency = 1
		task.wait(0.05 + math.random() * 0.25)
	end
end

-- every light dies... and something is standing right in front of you
local function blackout(s)
	s.blackout = true
	tween(s.darkCC, 0.15, { Brightness = -0.4, Contrast = 0.2 })
	s.sounds.Sting:Play()

	local watcher = nil
	local root = getRoot()
	if CONFIG.ShadowFigure and root then
		local look = flatLook(workspace.CurrentCamera.CFrame)
		local feet = findGround(root.Position + look * 18, root.Position.Y - 3, s)
		watcher = buildWatcher()
		placeWatcher(watcher, feet, root.Position)
		watcher.Parent = s.folder
	end

	task.wait(1.6 + math.random() * 0.8)
	s.blackout = false
	tween(s.darkCC, 0.5, { Brightness = 0, Contrast = 0 })
	if watcher then
		watcher:Destroy()
	end
end

local function jumpscare(s)
	local camera = workspace.CurrentCamera
	local watcher = buildWatcher()
	watcher.Parent = s.folder

	s.sounds.Scream:Play()
	setFlash(s, Color3.fromRGB(200, 0, 0), 0.2, 0.25)
	addShake(5)

	-- it lunges from the fog straight into your face
	local started = os.clock()
	local duration = 0.55
	while s.alive and os.clock() - started < duration do
		local alpha = (os.clock() - started) / duration
		local distance = 9 - 6.4 * (1 - (1 - alpha) ^ 3)
		local cameraCFrame = camera.CFrame
		local look = flatLook(cameraCFrame)
		local feet = cameraCFrame.Position + look * distance - Vector3.new(0, 8.45, 0)
		watcher:PivotTo(CFrame.lookAt(feet, feet - look))
		RunService.RenderStepped:Wait()
	end

	setFlash(s, Color3.new(0, 0, 0), 0)
	watcher:Destroy()
	task.wait(0.35)
	setFlash(s, Color3.new(0, 0, 0), 0, 1.2)
end

local SCARES = {
	{ weight = 30, run = stalk, needsFigure = true },
	{ weight = 20, run = lightning },
	{ weight = 18, run = whisperBehind },
	{ weight = 17, run = subliminal },
	{ weight = 15, run = blackout },
}

local function randomEvents(s)
	while s.alive and not s.introDone do
		task.wait(0.5)
	end
	while s.alive do
		task.wait(CONFIG.RandomEventMin + math.random() * (CONFIG.RandomEventMax - CONFIG.RandomEventMin))
		if not s.alive then
			break
		end

		local pool, total = {}, 0
		for _, scare in ipairs(SCARES) do
			if CONFIG.ShadowFigure or not scare.needsFigure then
				table.insert(pool, scare)
				total += scare.weight
			end
		end
		local roll = math.random() * total
		for _, scare in ipairs(pool) do
			roll -= scare.weight
			if roll <= 0 then
				local ok, err = pcall(scare.run, s)
				if not ok then
					warn("[HorrorCube] scare failed:", err)
				end
				break
			end
		end
	end
end

------------------------------------------------------------------------
-- START / STOP
------------------------------------------------------------------------
local function playIntro(s)
	cubeJitter = 1.6
	s.sounds.Sting:Play()
	s.sounds.Thunder:Play()
	addShake(3.5)
	tween(workspace.CurrentCamera, 7, { FieldOfView = CONFIG.HorrorFOV })
	glitch(s, 0.9)
	if not s.alive then
		return
	end

	fadeInOverlays(s, 2.5)
	task.spawn(heartbeatLoop, s)
	sway = 1.1

	local subtitle = nil
	local who = ReplicatedStorage:GetAttribute("HorrorTriggeredBy")
	if ReplicatedStorage:GetAttribute("HorrorTriggeredById") == player.UserId then
		subtitle = "You woke it up."
	elseif type(who) == "string" then
		subtitle = who .. " woke it up."
	end
	showCreepyText(s, CONFIG.IntroText, subtitle, 2.4)
	if not s.alive then
		return
	end

	task.wait(0.6)
	if CONFIG.Jumpscare and s.alive then
		jumpscare(s)
	end
	s.introDone = true
end

local function startHorror(withIntro)
	if session then
		return
	end
	local s = { alive = true, cleanup = {}, blackout = false, introDone = not withIntro }
	session = s

	local function own(item)
		table.insert(s.cleanup, item)
		return item
	end

	local camera = workspace.CurrentCamera
	local normalFOV = camera.FieldOfView
	local normalReverb = SoundService.AmbientReverb

	s.folder = own(Instance.new("Folder"))
	s.folder.Name = "HorrorLocalFX"
	s.folder.Parent = workspace

	own(buildGui(s))

	local soundFolder = own(Instance.new("Folder"))
	soundFolder.Name = "HorrorSounds"
	soundFolder.Parent = SoundService
	s.sounds = {}
	for _, kind in ipairs({ "Drone", "Scream", "Sting", "Thunder" }) do
		s.sounds[kind] = createSound(kind, soundFolder)
	end
	s.sounds.Lub = createSound("Heartbeat", soundFolder)
	s.sounds.Dub = createSound("Heartbeat", soundFolder)
	s.sounds.Dub.PlaybackSpeed *= 1.15
	s.lubVolume = s.sounds.Lub.Volume
	s.dubVolume = s.sounds.Dub.Volume * 0.7

	s.flashCC = own(Instance.new("ColorCorrectionEffect"))
	s.flashCC.Name = "HorrorLightning"
	s.flashCC.Parent = Lighting
	s.darkCC = own(Instance.new("ColorCorrectionEffect"))
	s.darkCC.Name = "HorrorBlackout"
	s.darkCC.Parent = Lighting

	makeAmbience(s)

	SoundService.AmbientReverb = Enum.ReverbType.Cave
	own(function()
		SoundService.AmbientReverb = normalReverb
		sway = 0
		restoreFlicker()
		local currentCamera = workspace.CurrentCamera
		if currentCamera then
			tween(currentCamera, 2, { FieldOfView = normalFOV })
		end
	end)

	local drone = s.sounds.Drone
	local droneVolume = drone.Volume
	drone.Volume = 0
	drone:Play()
	tween(drone, if withIntro then 6 else 2, { Volume = droneVolume })

	task.spawn(flickerLoop, s)
	task.spawn(vhsLoop, s)
	task.spawn(randomEvents, s)

	if withIntro then
		task.spawn(playIntro, s)
	else
		-- joined while the nightmare was already running: skip the intro
		sway = 1.1
		tween(camera, 2, { FieldOfView = CONFIG.HorrorFOV })
		fadeInOverlays(s, 2)
		task.spawn(heartbeatLoop, s)
	end
end

local function stopHorror()
	local s = session
	if not s then
		return
	end
	session = nil
	s.alive = false
	for i = #s.cleanup, 1, -1 do
		local item = s.cleanup[i]
		if typeof(item) == "RBXScriptConnection" then
			item:Disconnect()
		elseif typeof(item) == "Instance" then
			item:Destroy()
		elseif type(item) == "function" then
			task.spawn(item)
		end
	end
end

------------------------------------------------------------------------
-- ALWAYS ON: camera shake and the living cube
------------------------------------------------------------------------
RunService:BindToRenderStep("HorrorCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	shake *= math.exp(-2.5 * dt)
	if shake < 0.005 then
		shake = 0
	end
	if shake == 0 and sway == 0 then
		return
	end
	local camera = workspace.CurrentCamera
	local t = os.clock()
	local rx = math.noise(t * 18, 1.3) * shake * 2 + math.noise(t * 0.35, 7.7) * sway
	local ry = math.noise(t * 18, 4.9) * shake * 2 + math.noise(t * 0.3, 15.2) * sway
	local rz = math.noise(t * 18, 9.1) * shake + math.noise(t * 0.25, 31.4) * sway * 1.6
	camera.CFrame *= CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end)

local cubeClock = 0
local cubeSpin = 0
RunService.RenderStepped:Connect(function(dt)
	cubeClock += dt
	cubeJitter *= math.exp(-1.2 * dt)
	cubePulse *= math.exp(-7 * dt)

	local cube = workspace:FindFirstChild("HorrorCube")
	if not cube then
		return
	end
	local base = cube:GetAttribute("BaseCFrame")
	if typeof(base) ~= "CFrame" then
		return
	end

	-- idle: floats and slowly turns. awake: spins faster and never stops trembling
	local awake = session ~= nil
	cubeSpin += dt * (if awake then 0.8 else 0.3)
	local j = cubeJitter + (if awake then 0.05 else 0)
	local tremble = CFrame.new((math.random() - 0.5) * j, (math.random() - 0.5) * j, (math.random() - 0.5) * j)
	cube.CFrame = base
		* CFrame.new(0, math.sin(cubeClock * 1.3) * 0.6, 0)
		* tremble
		* CFrame.Angles(math.sin(cubeClock * 0.7) * 0.25, cubeSpin, math.cos(cubeClock * 0.55) * 0.2)

	local baseSize = cube:GetAttribute("BaseSize")
	if typeof(baseSize) == "Vector3" then
		local size = baseSize * (1 + cubePulse * 0.1)
		if (cube.Size - size).Magnitude > 0.001 then
			cube.Size = size
		end
	end
end)

------------------------------------------------------------------------
-- LISTEN TO THE SERVER
------------------------------------------------------------------------
ReplicatedStorage:GetAttributeChangedSignal("HorrorActive"):Connect(function()
	if ReplicatedStorage:GetAttribute("HorrorActive") then
		startHorror(true)
	else
		stopHorror()
	end
end)

if ReplicatedStorage:GetAttribute("HorrorActive") then
	startHorror(false)
end
