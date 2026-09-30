-- Ten Shadows Technique + Mahoraga boss: server bootstrap.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("TenShadows").Config)
local Arena = require(script.Parent.Arena)
local Combat = require(script.Parent.Combat)
local Abilities = require(script.Parent.Abilities)
local Mahoraga = require(script.Parent.Mahoraga)
local Curses = require(script.Parent.Curses)

-- Build the world before anyone spawns into it.
Players.CharacterAutoLoads = false
Arena.Build()
Curses.Start()
Abilities.Init()

local function setupCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid")
	local root = character:WaitForChild("HumanoidRootPart")
	humanoid.MaxHealth = Config.Player.MaxHealth
	humanoid.Health = Config.Player.MaxHealth
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	character:SetAttribute("Faction", "Player")
	character:SetAttribute("HitRadius", 2)

	-- faint shadow aura at the feet: Ten Shadows users stand in their own darkness
	local att = Instance.new("Attachment")
	att.Name = "ShadowAura"
	att.Position = Vector3.new(0, -2.8, 0)
	att.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = Config.Textures.Smoke
	pe.Color = ColorSequence.new(Color3.fromRGB(14, 12, 20), Color3.fromRGB(90, 60, 150))
	pe.Size = NumberSequence.new(1.6, 3)
	pe.Transparency = NumberSequence.new(0.55, 1)
	pe.Lifetime = NumberRange.new(0.8, 1.2)
	pe.Speed = NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = Vector2.new(180, 0)
	pe.Acceleration = Vector3.new(0, 2, 0)
	pe.Rate = 10
	pe.Parent = att

	humanoid.Died:Connect(function()
		task.delay(Config.Player.RespawnSeconds, function()
			if player.Parent then
				player:LoadCharacter()
			end
		end)
	end)
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	player:LoadCharacter()
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

---------------------------------------------------------------- Mahoraga lifecycle

local function spawnAtAltar()
	if not Mahoraga.IsAlive() and #Players:GetPlayers() > 0 then
		Mahoraga.Spawn(Config.Arena.BossAltar)
	end
end

Mahoraga.OnDefeated = function(contributors)
	for _, player in ipairs(contributors) do
		Abilities.Unlock(player, "TamedMahoraga", "You tamed Mahoraga. Summon the Divine General with H.")
	end
	task.delay(Config.Boss.RespawnSeconds, spawnAtAltar)
end

task.spawn(function()
	while #Players:GetPlayers() == 0 do
		Players.PlayerAdded:Wait()
	end
	task.wait(12)
	Combat.Notice("The ritual circle stirs... Mahoraga is coming. (Or chant it yourself: hold G)", Color3.fromRGB(255, 214, 120))
	task.wait(3)
	spawnAtAltar()
end)
