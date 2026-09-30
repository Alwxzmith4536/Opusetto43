--!strict
-- Arena, lighting, the Ten Shadows altar that summons Mahoraga, and training dummies.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Config = require(Shared:WaitForChild("Config"))
local Palette = require(Shared:WaitForChild("Palette"))
local Assets = Shared:WaitForChild("Assets")
local Arena = require(Assets:WaitForChild("Arena"))
local PartKit = require(Assets:WaitForChild("PartKit"))

local Combat = require(script.Parent.Combat)
local FX = require(script.Parent.FX)
local MahoragaBoss = require(script.Parent.MahoragaBoss)

local World = {}

local function ensure(className: string, name: string): Instance
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function World.setupLighting()
	Lighting.ClockTime = 17.4
	Lighting.Brightness = 2.4
	Lighting.Ambient = Color3.fromRGB(64, 56, 78)
	Lighting.OutdoorAmbient = Color3.fromRGB(118, 104, 128)
	Lighting.EnvironmentDiffuseScale = 0.5
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.GlobalShadows = true

	local atmosphere = ensure("Atmosphere", "JJK_Atmosphere") :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.15
	atmosphere.Color = Color3.fromRGB(214, 160, 176)
	atmosphere.Decay = Color3.fromRGB(96, 64, 118)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.4

	local bloom = ensure("BloomEffect", "JJK_Bloom") :: BloomEffect
	bloom.Intensity = 1.1
	bloom.Size = 28
	bloom.Threshold = 0.92

	local color = ensure("ColorCorrectionEffect", "JJK_Color") :: ColorCorrectionEffect
	color.Brightness = 0.02
	color.Contrast = 0.12
	color.Saturation = 0.1
	color.TintColor = Color3.fromRGB(255, 242, 246)

	local rays = ensure("SunRaysEffect", "JJK_SunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	rays.Spread = 0.7
end

-- A grade 4 cursed spirit that stands still and soaks hits.
local function buildDummy(cf: CFrame): (Model, Humanoid, BasePart)
	local m = PartKit.model("Cursed Spirit")
	local root = PartKit.part({ Name = "HumanoidRootPart", Parent = m, CFrame = cf * CFrame.new(0, 3, 0), Size = Vector3.new(3.4, 4.4, 2.6), Transparency = 1, CanCollide = true })
	m.PrimaryPart = root
	local skin = Color3.fromRGB(88, 64, 112)
	PartKit.ellipsoid({ Name = "Body", Parent = m, CFrame = cf * CFrame.new(0, 3, 0), Size = Vector3.new(4.4, 4.8, 3.8), Color = skin })
	PartKit.ellipsoid({ Name = "Belly", Parent = m, CFrame = cf * CFrame.new(0, 2.5, -1.2), Size = Vector3.new(3.0, 3.0, 1.8), Color = Color3.fromRGB(128, 100, 150) })
	PartKit.ellipsoid({ Name = "Mouth", Parent = m, CFrame = cf * CFrame.new(0, 2.2, -1.95), Size = Vector3.new(1.9, 0.7, 0.4), Color = Palette.Shadow })
	for i, spec in { { 0, 4.1, 1.0 }, { -1.1, 3.6, 0.6 }, { 1.1, 3.6, 0.6 } } do
		local x, y, d = spec[1], spec[2], spec[3]
		PartKit.ball(m, cf * CFrame.new(x, y, -1.75), d, { Color = Color3.fromRGB(245, 240, 220) }, "Eye" .. i)
		PartKit.ball(m, cf * CFrame.new(x, y, -1.75 - d * 0.42), d * 0.45, { Color = Color3.fromRGB(255, 214, 60), Material = Enum.Material.Neon }, "Pupil")
	end
	for _, side in { -1, 1 } do
		PartKit.limb({ Name = "Arm", Parent = m, Color = skin }, (cf * CFrame.new(side * 2.0, 3.4, -0.3)).Position, (cf * CFrame.new(side * 3.1, 1.6, -1.0)).Position, 0.7)
	end
	PartKit.part({ Name = "Head", Parent = m, CFrame = cf * CFrame.new(0, 5.2, 0), Size = Vector3.new(1, 1, 1), Transparency = 1 })
	local humanoid = Instance.new("Humanoid")
	humanoid.DisplayName = "Grade 4 Cursed Spirit"
	humanoid.MaxHealth = 600
	humanoid.Health = 600
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = 0.8
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 80
	humanoid.HealthDisplayDistance = 80
	humanoid.Parent = m
	m:SetAttribute("JJK_HitRadius", 2.4)
	m:SetAttribute("JJK_HitHalfHeight", 3)
	return m, humanoid, root
end

function World.spawnDummy(cf: CFrame)
	local m, humanoid, root = buildDummy(cf)
	local folder = workspace:FindFirstChild("JJK_Dummies")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "JJK_Dummies"
		folder.Parent = workspace
	end
	m.Parent = folder
	local entity = Combat.register(m, humanoid, root, "Dummy", nil)
	humanoid.Died:Connect(function()
		Combat.unregister(entity)
		FX.all("Impact", { pos = cf.Position, radius = 6, color = Palette.YutaEnergy })
		task.delay(0.4, function()
			m:Destroy()
		end)
		task.delay(5, function()
			World.spawnDummy(cf)
		end)
	end)
end

function World.setupAltar(pedestal: BasePart, bossSpawn: CFrame): (Player?) -> ()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SummonPrompt"
	prompt.ActionText = "Summon Mahoraga"
	prompt.ObjectText = "Ten Shadows Altar"
	prompt.HoldDuration = 1.2
	prompt.KeyboardKeyCode = Enum.KeyCode.P -- E is the block key
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = pedestal

	local readyAt = 0
	local function summon(who: Player?)
		if MahoragaBoss.isActive() or os.clock() < readyAt then
			if who then
				FX.to(who, "Notify", { text = if MahoragaBoss.isActive() then "Mahoraga is already here." else "The shadows are still settling..." })
			end
			return
		end
		prompt.Enabled = false
		task.spawn(function()
			local ok = MahoragaBoss.summon(bossSpawn, function()
				readyAt = os.clock() + Config.Boss.RespawnCooldown
				task.delay(Config.Boss.RespawnCooldown, function()
					prompt.Enabled = true
				end)
			end)
			if not ok then
				prompt.Enabled = true
			end
		end)
	end
	prompt.Triggered:Connect(summon)
	return summon
end

function World.start()
	if Config.World.SetupLighting then
		World.setupLighting()
	end

	local pedestal: BasePart
	local bossSpawn: CFrame
	local dummyBase: CFrame
	if Config.World.BuildArena then
		local center = CFrame.new(Config.World.ArenaCenter)
		local info = Arena.build(workspace, center, Config.World.ArenaSize)
		pedestal = info.Pedestal
		bossSpawn = info.BossSpawn
		dummyBase = center * CFrame.new(0, 0, Config.World.ArenaSize * 0.27)
	else
		local altarPos = Config.World.AltarPosition
		local bossPos = Config.World.BossSpawnPosition
		local altarCF = CFrame.lookAt(altarPos, Vector3.new(bossPos.X, altarPos.Y, bossPos.Z))
		local _, p = Arena.buildAltar(workspace, altarCF)
		pedestal = p
		bossSpawn = CFrame.lookAt(bossPos, Vector3.new(altarPos.X, bossPos.Y, altarPos.Z)) * CFrame.Angles(0, math.pi, 0)
		dummyBase = CFrame.new(bossPos + Vector3.new(0, 0, 50))
	end

	local summon = World.setupAltar(pedestal, bossSpawn)

	if Config.World.SpawnDummies then
		local count = Config.World.DummyCount
		for i = 1, count do
			local x = (i - (count + 1) / 2) * 16
			local spot = dummyBase * CFrame.new(x, 0, 0)
			local ground = Combat.groundAt(spot.Position + Vector3.new(0, 20, 0))
			World.spawnDummy(CFrame.new(ground) * CFrame.Angles(0, math.pi, 0))
		end
	end

	local autoDelay = Config.Rules.AutoSummonDelay
	if autoDelay and autoDelay > 0 then
		local scheduled = false
		local function schedule()
			if scheduled then
				return
			end
			scheduled = true
			task.delay(autoDelay, function()
				if #Players:GetPlayers() > 0 and not MahoragaBoss.isActive() then
					summon(nil)
				end
			end)
		end
		Players.PlayerAdded:Connect(function(player)
			player.CharacterAdded:Connect(schedule)
		end)
		for _, player in Players:GetPlayers() do
			if player.Character then
				schedule()
			end
			player.CharacterAdded:Connect(schedule)
		end
	end
end

return World
