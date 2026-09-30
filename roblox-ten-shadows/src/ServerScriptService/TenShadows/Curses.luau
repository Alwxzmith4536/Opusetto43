-- Training cursed spirits: stationary targets for testing techniques away from Mahoraga.
-- They pulse a weak cursed burst when players are close (which can also destroy guarding dogs).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("TenShadows")
local Config = require(Shared.Config)
local ModelFactory = require(Shared.ModelFactory)
local Combat = require(script.Parent.Combat)

local Curses = {}

local function spawnCurse(home)
	local cfg = Config.Curses
	local groundCF = CFrame.lookAt(home, home + Vector3.new(-home.X, 0, -home.Z + 1))
	local model = ModelFactory.Build("CursedSpirit", { Anchored = true, Humanoid = true, CFrame = groundCF })
	model.Name = "Cursed Spirit"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth = cfg.MaxHealth
	humanoid.Health = cfg.MaxHealth
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.WalkSpeed = 0
	model:SetAttribute("Faction", "Curse")
	model:SetAttribute("IsCurse", true)
	model:SetAttribute("HitRadius", 3)
	model.Parent = workspace
	Combat.Register(model)

	local root = model.PrimaryPart
	local homeCF = root.CFrame
	local dead = false
	humanoid.HealthChanged:Connect(function(h)
		if h <= 0 and not dead then
			dead = true
			Combat.FX("CurseBurst", { Pos = root.Position, Radius = 14 })
			task.delay(0.3, function()
				model:Destroy()
			end)
			task.delay(cfg.RespawnSeconds, spawnCurse, home)
		end
	end)

	task.spawn(function()
		local nextBurst = time() + cfg.BurstInterval
		while not dead and model.Parent do
			task.wait(0.25)
			-- drift back home after being pulled by Toad
			if (root.Position - homeCF.Position).Magnitude > 0.5 and not Combat.IsStunned(model) then
				model:PivotTo(root.CFrame:Lerp(homeCF, 0.15))
			end
			if time() >= nextBurst and not Combat.IsStunned(model) then
				nextBurst = time() + cfg.BurstInterval
				local near = false
				for _, player in ipairs(Players:GetPlayers()) do
					local r = player.Character and Combat.GetRoot(player.Character)
					if r and (r.Position - root.Position).Magnitude < cfg.BurstRadius * 2.5 then
						near = true
					end
				end
				if near then
					local shape = { Type = "Circle", Pos = root.Position, Radius = cfg.BurstRadius }
					Combat.FX("CurseBurst", { Pos = root.Position, Radius = cfg.BurstRadius })
					for _, t in ipairs(Combat.GetTargets(model, "Curse", shape)) do
						Combat.Damage(t, cfg.BurstDamage, "Boss", { SourceModel = model })
					end
				end
			end
		end
	end)
end

function Curses.Start()
	for _, pos in ipairs(Config.Curses.Positions) do
		spawnCurse(pos)
	end
end

return Curses
