--[[
	HorrorClient  (LocalScript)
	Put this in:  StarterPlayer > StarterPlayerScripts

	Client-side half of the HorrorCube. It listens for the server and adds what only a
	client can do well: camera shake, blood rain + floating embers, bloody vignette that
	pulses with a heartbeat, light flicker, glitching scare text and the odd jumpscare.

	Everything here is local to each player - nothing is replicated.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local remote = ReplicatedStorage:WaitForChild("HorrorCubeEvent")

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local CONFIG = {
	BaseShake = 0.015, -- constant paranoid camera tremble once the horror starts
	FovPulse = 2, -- degrees the FOV kicks on every heartbeat (0 = leave FOV alone)

	RainEnabled = true,
	RainStopsIndoors = true,

	ScareTextEvery = { 7, 18 }, -- seconds between creepy text flashes
	JumpscareEvery = { 40, 90 }, -- seconds between jumpscares (first one comes sooner)
	JumpscaresEnabled = true,

	-- Optional audio. Leave "" to skip. Use your own ids: "rbxassetid://123456"
	HeartbeatSoundId = "", -- a single thump; played on every "lub" and softer on "dub"
	JumpscareSoundId = "", -- empty = a built-in Roblox sound pitched way down
	JumpscareImageId = "", -- empty = giant scary text instead of an image
}

local SCARES = {
	"IT SEES YOU",
	"DON'T LOOK BEHIND YOU",
	"YOU SHOULD NOT HAVE CLICKED",
	"RUN",
	"IT'S IN THE WALLS",
	"WHY DID YOU TOUCH IT",
	"IT IS WATCHING",
	"THERE IS NO EXIT",
	"IT HEARS YOUR HEART",
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------
local function randomBetween(range)
	return range[1] + math.random() * (range[2] - range[1])
end

local function playLocal(soundId, volume, speed)
	if soundId == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.PlaybackSpeed = speed
	sound.Parent = SoundService
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	sound:Play()
end

----------------------------------------------------------------------
-- UI
----------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "HorrorOverlay"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local flash = Instance.new("Frame")
flash.Size = UDim2.fromScale(1, 1)
flash.BackgroundTransparency = 1
flash.BorderSizePixel = 0
flash.ZIndex = 10
flash.Parent = gui

local function flashScreen(color, startTransparency, duration)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = startTransparency
	TweenService:Create(
		flash,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	):Play()
end

-- vignette = four edge frames with a transparency gradient
local vignette = {}
local function addEdge(anchor, position, size, rotation)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = anchor
	frame.Position = position
	frame.Size = size
	frame.BackgroundColor3 = Color3.fromRGB(35, 0, 0)
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.ZIndex = 2

	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Rotation = rotation
	gradient.Parent = frame

	frame.Parent = gui
	table.insert(vignette, frame)
end
addEdge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(1, 0.3), 90) -- top
addEdge(Vector2.new(0, 1), UDim2.fromScale(0, 1), UDim2.fromScale(1, 0.3), -90) -- bottom
addEdge(Vector2.new(0, 0), UDim2.fromScale(0, 0), UDim2.fromScale(0.25, 1), 0) -- left
addEdge(Vector2.new(1, 0), UDim2.fromScale(1, 0), UDim2.fromScale(0.25, 1), 180) -- right

local scareLabel = Instance.new("TextLabel")
scareLabel.AnchorPoint = Vector2.new(0.5, 0.5)
scareLabel.BackgroundTransparency = 1
scareLabel.Font = Enum.Font.Creepster
scareLabel.TextScaled = true
scareLabel.TextColor3 = Color3.fromRGB(200, 0, 0)
scareLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
scareLabel.TextStrokeTransparency = 0
scareLabel.Visible = false
scareLabel.ZIndex = 5
scareLabel.Parent = gui

local scareImage = Instance.new("ImageLabel")
scareImage.Size = UDim2.fromScale(1, 1)
scareImage.BackgroundColor3 = Color3.new(0, 0, 0)
scareImage.BorderSizePixel = 0
scareImage.ScaleType = Enum.ScaleType.Fit
scareImage.Visible = false
scareImage.ZIndex = 8
scareImage.Parent = gui

----------------------------------------------------------------------
-- STATE
----------------------------------------------------------------------
local active = false
local elapsed = 0
local heartPhase = 0
local lastPhase = 0
local shake = 0
local flickerLeft = 0
local baseFov = 70
local scareBusy = false
local flickerEffect = nil
local rainPart, emberPart, rainEmitter = nil, nil, nil

local function addShake(amount)
	shake = math.max(shake, amount)
end

----------------------------------------------------------------------
-- SCARES
----------------------------------------------------------------------
local function showScare(text, duration, size)
	if scareBusy then
		return
	end
	scareBusy = true
	scareLabel.Text = text
	scareLabel.Size = size or UDim2.fromScale(0.7, 0.16)
	local base = UDim2.fromScale(0.35 + math.random() * 0.3, 0.15 + math.random() * 0.7)
	scareLabel.Visible = true

	local started = os.clock()
	while os.clock() - started < duration do
		scareLabel.Position = base + UDim2.fromOffset(math.random(-6, 6), math.random(-6, 6))
		scareLabel.TextTransparency = (math.random() < 0.2) and 0.7 or 0
		scareLabel.Rotation = math.random(-3, 3)
		task.wait(0.03)
	end
	scareLabel.Visible = false
	scareBusy = false
end

local function jumpscare()
	addShake(3)
	if CONFIG.JumpscareSoundId ~= "" then
		playLocal(CONFIG.JumpscareSoundId, 6, 1)
	else
		playLocal("rbxasset://sounds/uuhhh.mp3", 6, 0.3)
	end

	if CONFIG.JumpscareImageId ~= "" then
		scareImage.Image = CONFIG.JumpscareImageId
		scareImage.Visible = true
		task.wait(0.45)
		scareImage.Visible = false
	else
		flashScreen(Color3.new(0, 0, 0), 0, 0.2)
		showScare("BEHIND YOU", 0.5, UDim2.fromScale(1, 0.6))
	end
	flashScreen(Color3.fromRGB(255, 0, 0), 0.1, 0.8)
end

----------------------------------------------------------------------
-- RAIN + EMBERS (follow the camera)
----------------------------------------------------------------------
local function makeCarrier(name, size)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Parent = workspace
	return part
end

local function startRain()
	rainPart = makeCarrier("HorrorRain", Vector3.new(90, 1, 90))
	rainEmitter = Instance.new("ParticleEmitter")
	rainEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 0, 0))
	rainEmitter.LightEmission = 0.4
	rainEmitter.LightInfluence = 0
	rainEmitter.Size = NumberSequence.new(0.18)
	rainEmitter.Transparency = NumberSequence.new(0.35)
	rainEmitter.Lifetime = NumberRange.new(1.1, 1.5)
	rainEmitter.Rate = 700
	rainEmitter.Speed = NumberRange.new(45, 60)
	rainEmitter.EmissionDirection = Enum.NormalId.Bottom
	rainEmitter.SpreadAngle = Vector2.new(0, 0)
	rainEmitter.Acceleration = Vector3.new(0, -40, 0)
	rainEmitter.Parent = rainPart
end

local function startEmbers()
	emberPart = makeCarrier("HorrorEmbers", Vector3.new(60, 20, 60))
	local embers = Instance.new("ParticleEmitter")
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 70, 20))
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0),
	})
	embers.Lifetime = NumberRange.new(5, 8)
	embers.Rate = 30
	embers.Speed = NumberRange.new(1, 3)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.SpreadAngle = Vector2.new(60, 60)
	embers.Acceleration = Vector3.new(0, 0.5, 0)
	embers.Parent = emberPart
end

local rainCheckTimer = 0
local function updateCarriers(dt, camera)
	local position = camera.CFrame.Position
	if rainPart then
		rainPart.Position = position + Vector3.new(0, 40, 0)
	end
	if emberPart then
		emberPart.Position = position
	end

	-- no rain falling through roofs
	if rainEmitter and CONFIG.RainStopsIndoors then
		rainCheckTimer = rainCheckTimer + dt
		if rainCheckTimer > 0.25 then
			rainCheckTimer = 0
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local ignore = { rainPart, emberPart }
			if player.Character then
				table.insert(ignore, player.Character)
			end
			params.FilterDescendantsInstances = ignore
			local roof = workspace:Raycast(position, Vector3.new(0, 60, 0), params)
			rainEmitter.Enabled = roof == nil
		end
	end
end

----------------------------------------------------------------------
-- PER-FRAME: shake, heartbeat, vignette, flicker
----------------------------------------------------------------------
local function onRender(dt)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	local amount = shake + (active and CONFIG.BaseShake or 0)
	if amount > 0.001 then
		local t = os.clock() * 28
		local x = math.noise(t, 0.31, 0.17) * amount * 2
		local y = math.noise(0.77, t, 0.53) * amount * 2
		local roll = math.noise(0.5, 0.21, t) * amount * 0.12
		camera.CFrame = camera.CFrame * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, roll)
	end
	shake = math.max(0, shake - dt * 2.2)

	if not active then
		return
	end

	elapsed = elapsed + dt

	-- heartbeat: "lub" at phase 0, softer "dub" at phase 0.22. BPM climbs as the night goes on.
	local bpm = 62 + math.min(elapsed, 90) * 0.6
	lastPhase = heartPhase
	heartPhase = (heartPhase + dt * bpm / 60) % 1
	if heartPhase < lastPhase then
		playLocal(CONFIG.HeartbeatSoundId, 2.5, 1)
	elseif lastPhase < 0.22 and heartPhase >= 0.22 then
		playLocal(CONFIG.HeartbeatSoundId, 1.2, 0.9)
	end

	local pulse = math.exp(-heartPhase * 12)
	if heartPhase > 0.22 then
		pulse = math.max(pulse, 0.6 * math.exp(-(heartPhase - 0.22) * 12))
	end

	local strength = math.clamp(math.min(0.45 + elapsed / 120, 0.8) + pulse * 0.2, 0, 1)
	local transparency = 0.35 + (1 - strength) * 0.65
	for _, edge in ipairs(vignette) do
		edge.BackgroundTransparency = transparency
	end

	if CONFIG.FovPulse > 0 then
		camera.FieldOfView = baseFov + pulse * CONFIG.FovPulse
	end

	-- flicker the whole screen in short random bursts
	flickerLeft = flickerLeft - dt
	if flickerLeft > 0 then
		flickerEffect.Brightness = (math.random() - 0.75) * 0.9
	else
		flickerEffect.Brightness = 0
		if math.random() < dt * 0.25 then
			flickerLeft = 0.1 + math.random() * 0.4
		end
	end

	updateCarriers(dt, camera)
end

RunService:BindToRenderStep("HorrorCubeCamera", Enum.RenderPriority.Camera.Value + 1, onRender)

----------------------------------------------------------------------
-- START
----------------------------------------------------------------------
local function activate(resumed)
	if active then
		return
	end
	active = true

	local camera = workspace.CurrentCamera
	if camera then
		baseFov = camera.FieldOfView
	end

	flickerEffect = Instance.new("ColorCorrectionEffect")
	flickerEffect.Name = "HorrorFlicker"
	flickerEffect.Parent = Lighting

	if CONFIG.RainEnabled then
		startRain()
	end
	startEmbers()

	if not resumed then
		flashScreen(Color3.fromRGB(255, 0, 0), 0, 1.2)
		addShake(4)
	end

	-- creepy text, forever
	task.spawn(function()
		while true do
			task.wait(randomBetween(CONFIG.ScareTextEvery))
			addShake(0.6)
			showScare(SCARES[math.random(#SCARES)], 0.15 + math.random() * 0.5)
		end
	end)

	-- the odd jumpscare
	if CONFIG.JumpscaresEnabled then
		task.spawn(function()
			task.wait(resumed and 20 or 25)
			while true do
				jumpscare()
				task.wait(randomBetween(CONFIG.JumpscareEvery))
			end
		end)
	end
end

remote.OnClientEvent:Connect(function(message)
	if message == "Blackout" then
		flashScreen(Color3.new(1, 1, 1), 0, 0.15)
		task.spawn(function()
			for i = 1, 18 do
				addShake(0.3 + i * 0.05)
				task.wait(0.1)
			end
		end)
	elseif message == "Slam" then
		activate(false)
	elseif message == "Resume" then
		activate(true)
	end
end)

-- tell the server we can receive events (so late joiners are caught up)
remote:FireServer("Ready")
