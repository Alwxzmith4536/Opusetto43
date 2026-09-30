-- Boss: Eight-Handled Sword Divergent Sila Divine General Mahoraga.
--
-- * Adapts to every damage type separately (the wheel turns, damage from that type drops,
--   Mahoraga heals when an adaptation completes and can counter adapted techniques).
-- * Much stronger than a normal enemy (high health, reduced damage taken, fast attacks),
--   but every hit on a player goes through DamageRules, so it can never one-shot anyone.
-- * Every attack is telegraphed on the ground so it can be dodged.
-- * Defeating it tames it: everyone who fought gets the "Divine General Mahoraga" summon.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("TenShadows")
local Config = require(Shared.Config)
local Adaptation = require(Shared.Adaptation)
local DamageRules = require(Shared.DamageRules)
local ModelFactory = require(Shared.ModelFactory)
local Combat = require(script.Parent.Combat)

local BOSS = Config.Boss
local ATK = BOSS.Attacks
local UP = Vector3.new(0, 1, 0)

local Mahoraga = {}
Mahoraga.OnDefeated = nil -- set by Main: function(contributors: {Player})

local current = nil -- state of the live boss

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local spawning = false

function Mahoraga.IsAlive()
	return spawning or (current ~= nil and current.Alive)
end

function Mahoraga.GetModel()
	return current and current.Model
end

---------------------------------------------------------------- animation helpers

local function poseMotor(state, jointName, angles, t, style)
	local motor = state.Motors[jointName]
	if not motor then
		return
	end
	local goal = state.BaseC0[jointName] * CFrame.Angles(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
	TweenService:Create(motor, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = goal }):Play()
end

local function restPose(state, t)
	poseMotor(state, "RightArm", Vector3.zero, t or 0.25)
	poseMotor(state, "LeftArm", Vector3.zero, t or 0.25)
end

local function wheelPosition(state)
	local pivot = state.Model:FindFirstChild("WheelPivot")
	return pivot and pivot.Position or state.Root.Position + UP * 12
end

local function turnWheel(state, completed, damageType)
	local motor = state.Motors.Wheel
	if motor then
		local goal = state.BaseC0.Wheel * CFrame.Angles(0, math.rad(45 * state.Adapt.TotalTurns), 0)
		TweenService:Create(motor, TweenInfo.new(0.35, Enum.EasingStyle.Back), { C0 = goal }):Play()
	end
	Combat.FX("WheelTurn", { Pos = wheelPosition(state), Completed = completed, DamageType = damageType })
end

local function face(state, pos)
	local root = state.Root
	local look = flat(pos - root.Position)
	if look.Magnitude > 0.1 then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
	end
end

local function stop(state)
	state.Humanoid:MoveTo(state.Root.Position)
end

-- Waits, then returns false if the boss died meanwhile.
local function pause(state, t)
	task.wait(t)
	return state.Alive
end

---------------------------------------------------------------- attribute sync for the client UI

local function syncAttributes(state)
	local model = state.Model
	local list = {}
	for _, damageType in ipairs(state.Adapt.Order) do
		table.insert(list, damageType .. ":" .. state.Adapt:Progress(damageType) .. ":" .. (state.Adapt:IsAdapted(damageType) and 1 or 0))
	end
	model:SetAttribute("Adaptations", table.concat(list, ","))
	model:SetAttribute("Phase", state.Phase)
end

---------------------------------------------------------------- damage in

local function onDamaged(state, amount, damageType, info)
	if not state.Alive then
		return 0
	end
	local multiplier, turned, completed = state.Adapt:RegisterHit(damageType)
	local dealt = math.floor(amount * BOSS.BaseDamageTaken * multiplier + 0.5)
	local humanoid = state.Humanoid
	humanoid.Health = math.max(0, humanoid.Health - dealt)
	state.LastDamaged = time()

	if info.Source then
		state.Contributors[info.Source] = (state.Contributors[info.Source] or 0) + dealt
	end

	local note = nil
	if state.Adapt:IsAdapted(damageType) and not completed then
		note = "ADAPTED"
		-- canon: once adapted, Mahoraga answers that technique immediately
		if info.Source and time() >= state.NextCounter and math.random() < BOSS.CounterChance then
			state.NextCounter = time() + BOSS.CounterCooldown
			state.CounterTarget = info.Source
		end
	elseif multiplier < 1 then
		note = string.format("-%d%%", math.floor((1 - multiplier) * 100 + 0.5))
	end

	if turned then
		turnWheel(state, completed, damageType)
		if completed then
			local label = (Config.DamageTypes[damageType] or {}).Label or damageType
			Combat.Notice("The wheel turns... Mahoraga has ADAPTED to " .. label .. "!", Color3.fromRGB(255, 214, 120))
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * BOSS.AdaptHealFraction)
			state.PendingResonance = true
		end
		syncAttributes(state)
	end
	return dealt, note
end

---------------------------------------------------------------- targets

local function pickTarget(state)
	local root = state.Root
	local now = time()
	-- Rabbit Escape decoys draw Mahoraga's attention first
	for i = #Combat.Decoys, 1, -1 do
		local d = Combat.Decoys[i]
		if now > d.Until then
			table.remove(Combat.Decoys, i)
		elseif flat(d.Pos - root.Position).Magnitude < 90 then
			return nil, d.Pos
		end
	end
	local best, bestDist = nil, BOSS.AggroRange
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and Combat.IsAlive(char) then
			local r = Combat.GetRoot(char)
			local dist = r and (r.Position - root.Position).Magnitude
			if dist and dist < bestDist then
				best, bestDist = char, dist
			end
		end
	end
	if best then
		return best, Combat.GetRoot(best).Position
	end
	return nil, nil
end

local function hitPlayers(state, shape, damage, knockback, stun)
	local targets = Combat.GetTargets(state.Model, "Curse", shape)
	for _, model in ipairs(targets) do
		local kb = nil
		if knockback then
			local dir = flat(Combat.GetRoot(model).Position - state.Root.Position)
			dir = dir.Magnitude > 0.1 and dir.Unit or state.Root.CFrame.LookVector
			kb = dir * knockback + UP * knockback * 0.45
		end
		Combat.Damage(model, damage, "Boss", { SourceModel = state.Model, Knockback = kb, Stun = stun })
	end
	return #targets
end

---------------------------------------------------------------- attacks

local Attacks = {}

function Attacks.Combo(state, targetPos)
	local a = ATK.Combo
	for i = 1, a.Hits do
		face(state, targetPos)
		local root = state.Root
		local look = root.CFrame.LookVector
		Combat.FX("TelegraphCone", { Origin = root.Position, Dir = look, Range = a.Range, Angle = a.Angle, Duration = a.Windup * 0.8 })
		local arm = i % 2 == 1 and "RightArm" or "LeftArm"
		poseMotor(state, arm, Vector3.new(110, 0, i % 2 == 1 and 30 or -30), a.Windup * 0.8)
		if not pause(state, a.Windup) then
			return
		end
		poseMotor(state, arm, Vector3.new(-20, 0, 0), 0.1)
		Combat.FX("BossSlash", { CFrame = root.CFrame, Radius = a.Range * 0.8, Span = a.Angle, Tilt = i % 2 == 1 and -30 or 30 })
		hitPlayers(state, { Type = "Cone", Origin = root.Position, Dir = look, Range = a.Range, Angle = a.Angle }, a.Damage, i == a.Hits and 45 or 15)
		if not pause(state, 0.15) then
			return
		end
	end
	restPose(state)
end

function Attacks.SwordOfExtermination(state, targetPos)
	local a = ATK.SwordOfExtermination
	face(state, targetPos)
	local root = state.Root
	local look = root.CFrame.LookVector
	Combat.FX("TelegraphCone", { Origin = root.Position, Dir = look, Range = a.Range, Angle = a.Angle, Duration = a.Windup })
	poseMotor(state, "RightArm", Vector3.new(170, 0, 10), a.Windup * 0.9, Enum.EasingStyle.Back)
	if not pause(state, a.Windup) then
		return
	end
	poseMotor(state, "RightArm", Vector3.new(-10, 0, 0), 0.12)
	Combat.FX("BossSlash", { CFrame = root.CFrame * CFrame.Angles(0, 0, math.rad(80)), Radius = a.Range, Span = 90, Tilt = 0 })
	hitPlayers(state, { Type = "Cone", Origin = root.Position, Dir = look, Range = a.Range, Angle = a.Angle }, a.Damage, 40)
	pause(state, 0.35)
	restPose(state)
end

function Attacks.GroundSlam(state, targetPos)
	local a = ATK.GroundSlam
	local root = state.Root
	local landing = flat(targetPos) + UP * root.Position.Y
	Combat.FX("TelegraphCircle", { Pos = flat(targetPos), Radius = a.Radius, Duration = a.Windup })
	poseMotor(state, "RightArm", Vector3.new(160, 0, 20), 0.4)
	poseMotor(state, "LeftArm", Vector3.new(160, 0, -20), 0.4)
	face(state, targetPos)
	-- leap: anchor briefly and arc over to the target
	root.Anchored = true
	local start = root.CFrame
	local look = flat(landing - start.Position)
	local goal = CFrame.lookAt(landing, landing + (look.Magnitude > 0.1 and look or start.LookVector))
	local steps = 20
	for i = 1, steps do
		if not state.Alive then
			root.Anchored = false
			return
		end
		local t = i / steps
		root.CFrame = start:Lerp(goal, t) + UP * math.sin(t * math.pi) * 22
		task.wait(a.Windup / steps)
	end
	root.CFrame = goal
	root.Anchored = false
	poseMotor(state, "RightArm", Vector3.new(40, 0, 0), 0.08)
	poseMotor(state, "LeftArm", Vector3.new(40, 0, 0), 0.08)
	Combat.FX("BossSlam", { Pos = flat(landing), Radius = a.Radius })
	hitPlayers(state, { Type = "Circle", Pos = flat(landing) + UP * landing.Y, Radius = a.Radius }, a.Damage, a.Knockback)
	pause(state, 0.5)
	restPose(state)
end

function Attacks.Rush(state, targetPos)
	local a = ATK.Rush
	face(state, targetPos)
	local root = state.Root
	local from = root.Position
	local dir = flat(targetPos - from)
	dir = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector
	local to = from + dir * a.Distance
	-- stay inside the arena wall
	local limit = Config.Arena.Radius - 15
	local offset = flat(to - Config.Arena.Center)
	if offset.Magnitude > limit then
		to = Config.Arena.Center + offset.Unit * limit + UP * from.Y
	end
	Combat.FX("TelegraphLine", { From = from, To = to, Width = a.Width, Duration = a.Windup })
	poseMotor(state, "RightArm", Vector3.new(70, 0, 20), a.Windup)
	if not pause(state, a.Windup) then
		return
	end
	Combat.FX("BossDash", { From = from, To = to })
	root.CFrame = CFrame.lookAt(to, to + dir)
	hitPlayers(state, { Type = "Line", From = from, To = to, Width = a.Width }, a.Damage, a.Knockback)
	pause(state, 0.3)
	restPose(state)
end

function Attacks.WorldSlash(state, targetPos)
	local a = ATK.WorldSlash
	face(state, targetPos)
	local root = state.Root
	local dir = flat(targetPos - root.Position)
	dir = dir.Magnitude > 0.1 and dir.Unit or root.CFrame.LookVector
	local from = root.Position - dir * 10
	local to = root.Position + dir * a.Length
	Combat.Notice("Mahoraga turns an adapted technique back on you: WORLD-CUTTING SLASH", Color3.fromRGB(255, 120, 120))
	Combat.FX("TelegraphLine", { From = from, To = to, Width = a.Width, Duration = a.Windup })
	poseMotor(state, "RightArm", Vector3.new(175, 0, 0), a.Windup * 0.8, Enum.EasingStyle.Back)
	if not pause(state, a.Windup) then
		return
	end
	poseMotor(state, "RightArm", Vector3.new(-15, 0, 0), 0.1)
	Combat.FX("WorldSlash", { From = from, To = to })
	hitPlayers(state, { Type = "Line", From = from, To = to, Width = a.Width }, a.Damage, 30)
	pause(state, 0.6)
	restPose(state)
end

function Attacks.Counter(state, player)
	local a = ATK.Counter
	local char = player.Character
	local targetRoot = char and Combat.GetRoot(char)
	if not targetRoot or not Combat.IsAlive(char) then
		return
	end
	local behind = targetRoot.Position - flat(targetRoot.CFrame.LookVector) * 9
	local root = state.Root
	Combat.FX("BossDash", { From = root.Position, To = behind })
	root.CFrame = CFrame.lookAt(behind, Vector3.new(targetRoot.Position.X, behind.Y, targetRoot.Position.Z))
	Combat.FX("TelegraphCircle", { Pos = targetRoot.Position, Radius = a.Range * 0.6, Duration = a.Windup })
	poseMotor(state, "RightArm", Vector3.new(120, 0, 40), a.Windup)
	if not pause(state, a.Windup) then
		return
	end
	poseMotor(state, "RightArm", Vector3.new(-10, 0, -20), 0.08)
	Combat.FX("BossSlash", { CFrame = root.CFrame, Radius = a.Range, Span = 160, Tilt = -40 })
	hitPlayers(state, { Type = "Circle", Pos = root.Position + root.CFrame.LookVector * 5, Radius = a.Range * 0.7 }, a.Damage, 50)
	pause(state, 0.3)
	restPose(state)
end

function Attacks.WheelResonance(state)
	local a = ATK.WheelResonance
	Combat.FX("BossRoar", { Pos = state.Root.Position })
	hitPlayers(state, { Type = "Circle", Pos = state.Root.Position, Radius = a.Radius }, a.Damage, a.Knockback)
end

local function chooseAttack(state, dist)
	local options = {}
	local function add(name, weight)
		for _ = 1, weight do
			table.insert(options, name)
		end
	end
	if dist < ATK.Combo.Range + 4 then
		add("Combo", 3)
		add("SwordOfExtermination", 2)
	elseif dist < ATK.SwordOfExtermination.Range then
		add("SwordOfExtermination", 3)
		add("GroundSlam", 2)
		add("Rush", 1)
	else
		add("Rush", 3)
		add("GroundSlam", 2)
	end
	if state.Phase == 2 and state.Adapt:AdaptedCount() >= ATK.WorldSlash.MinAdaptations and time() >= state.NextWorldSlash then
		add("WorldSlash", 3)
	end
	return options[math.random(1, #options)]
end

---------------------------------------------------------------- lifecycle

local function aiLoop(state)
	local humanoid = state.Humanoid
	while state.Alive do
		task.wait(0.1)
		if not state.Alive then
			break
		end
		local now = time()

		-- phase 2
		if state.Phase == 1 and humanoid.Health <= humanoid.MaxHealth * BOSS.Phase2Threshold then
			state.Phase = 2
			syncAttributes(state)
			Combat.Notice("Mahoraga's wheel spins faster. PHASE 2", Color3.fromRGB(255, 120, 120))
			Attacks.WheelResonance(state)
		end

		local slow = Combat.GetSlowFactor(state.Root.Position, "Curse")
		humanoid.WalkSpeed = (state.Phase == 2 and BOSS.Phase2WalkSpeed or BOSS.WalkSpeed) * slow

		if Combat.IsStunned(state.Model) then
			stop(state)
			continue
		end

		if state.PendingResonance then
			state.PendingResonance = false
			stop(state)
			Attacks.WheelResonance(state)
			continue
		end

		if state.CounterTarget then
			local player = state.CounterTarget
			state.CounterTarget = nil
			stop(state)
			Attacks.Counter(state, player)
			state.NextAttack = time() + 0.8
			continue
		end

		local _, targetPos = pickTarget(state)
		if not targetPos then
			-- nobody around: walk home and regenerate
			humanoid:MoveTo(Config.Arena.BossAltar)
			if now - state.LastDamaged > 8 then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * BOSS.OutOfCombatRegen * 0.1)
			end
			continue
		end

		local dist = flat(targetPos - state.Root.Position).Magnitude
		if now >= state.NextAttack and dist < 90 then
			stop(state)
			local name = chooseAttack(state, dist)
			if name == "WorldSlash" then
				state.NextWorldSlash = time() + ATK.WorldSlash.Cooldown
			end
			Attacks[name](state, targetPos)
			local cd = ATK[name].Cooldown or 2
			state.NextAttack = time() + cd * (state.Phase == 2 and BOSS.Phase2CooldownMultiplier or 1)
		elseif dist > ATK.Combo.Range * 0.6 then
			humanoid:MoveTo(targetPos)
		else
			stop(state)
			face(state, targetPos)
		end
	end
end

local function onDied(state)
	if not state.Alive then
		return
	end
	state.Alive = false
	local model = state.Model
	local pos = state.Root.Position
	Combat.FX("BossDefeated", { Pos = pos })
	Combat.Notice("Mahoraga has been defeated. The ritual is complete: it is TAMED.", Color3.fromRGB(255, 226, 150))

	local contributors = {}
	for player, dmg in pairs(state.Contributors) do
		if player.Parent and dmg > 0 then
			table.insert(contributors, player)
		end
	end
	if Mahoraga.OnDefeated then
		Mahoraga.OnDefeated(contributors)
	end

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			TweenService:Create(part, TweenInfo.new(2), { Transparency = 1 }):Play()
		end
	end
	task.delay(2.2, function()
		model:Destroy()
		if current == state then
			current = nil
		end
	end)
end

-- Spawns Mahoraga at a ground position. summoner (optional) is who chanted.
function Mahoraga.Spawn(groundPos, summoner)
	if Mahoraga.IsAlive() then
		return nil
	end
	local lookAt = summoner and summoner.Character and Combat.GetRoot(summoner.Character)
	local facing = lookAt and flat(lookAt.Position - groundPos) or Vector3.new(0, 0, 1)
	if facing.Magnitude < 0.1 then
		facing = Vector3.new(0, 0, 1)
	end
	local groundCF = CFrame.lookAt(flat(groundPos), flat(groundPos) + facing.Unit)

	spawning = true
	Combat.FX("BossSpawn", { Pos = flat(groundPos) })
	task.wait(1.1)
	spawning = false

	local model = ModelFactory.Build("Mahoraga", { Anchored = false, Humanoid = true, CFrame = groundCF, Scale = BOSS.Scale })
	model.Name = "Mahoraga"
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.PrimaryPart
	local maxHealth = DamageRules.BossMaxHealth(BOSS.MaxHealth, BOSS.HealthPerExtraPlayer, #Players:GetPlayers())
	humanoid.MaxHealth = maxHealth
	humanoid.Health = maxHealth
	humanoid.WalkSpeed = BOSS.WalkSpeed
	humanoid.JumpPower = 0
	for _, s in ipairs({ Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Seated, Enum.HumanoidStateType.Climbing, Enum.HumanoidStateType.Swimming }) do
		humanoid:SetStateEnabled(s, false)
	end
	model:SetAttribute("Faction", "Curse")
	model:SetAttribute("IsBoss", true)
	model:SetAttribute("BossName", BOSS.Name)
	model:SetAttribute("HitRadius", BOSS.HitRadius)
	model:SetAttribute("KnockbackResist", BOSS.KnockbackResist)
	model.Parent = workspace
	root:SetNetworkOwner(nil)

	local state = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Alive = true,
		Phase = 1,
		Adapt = Adaptation.new(BOSS),
		Motors = {},
		BaseC0 = {},
		Contributors = {},
		NextAttack = time() + 2.2,
		NextCounter = 0,
		NextWorldSlash = 0,
		LastDamaged = time(),
		PendingResonance = false,
		CounterTarget = nil,
	}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			state.Motors[d.Name] = d
			state.BaseC0[d.Name] = d.C0
		end
	end
	current = state
	syncAttributes(state)

	Combat.Register(model)
	Combat.Handlers[model] = function(amount, damageType, info)
		return onDamaged(state, amount, damageType, info)
	end
	humanoid.Died:Connect(function()
		onDied(state)
	end)
	humanoid.HealthChanged:Connect(function(h)
		if h <= 0 then
			onDied(state)
		end
	end)

	-- entrance: roar with both arms raised
	root.Anchored = true
	poseMotor(state, "RightArm", Vector3.new(150, 0, 30), 0.5, Enum.EasingStyle.Back)
	poseMotor(state, "LeftArm", Vector3.new(150, 0, -30), 0.5, Enum.EasingStyle.Back)
	Combat.FX("BossRoar", { Pos = root.Position })
	Combat.FX("UI_Incantation", { Title = BOSS.Name, Sub = "八握剣異戒神将魔虚羅", Color = Color3.fromRGB(255, 226, 150) })
	task.delay(1.2, function()
		if state.Alive then
			root.Anchored = false
			restPose(state, 0.4)
			task.spawn(aiLoop, state)
		end
	end)
	return model
end

function Mahoraga.Despawn()
	if current then
		current.Alive = false
		if current.Model then
			current.Model:Destroy()
		end
		current = nil
	end
end

return Mahoraga
