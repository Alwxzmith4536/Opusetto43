-- Server side of the Ten Shadows Technique. Clients only send "I pressed X, aiming at Y";
-- cooldowns, locks, targeting and damage are all decided here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("TenShadows")
local Config = require(Shared.Config)
local DamageRules = require(Shared.DamageRules)
local Combat = require(script.Parent.Combat)
local Mahoraga = require(script.Parent.Mahoraga)

local A = Config.Abilities
local UP = Vector3.new(0, 1, 0)
local flat = Combat.Flat

local Abilities = {}

local playerState = {} -- [player] = state
local guards = {} -- dogs standing guard: { Id, Owner, Pos, Until }
local nextDogId = 0

local function getState(player)
	local st = playerState[player]
	if not st then
		st = {
			Cooldowns = {},
			Unlocked = {},
			DogsDestroyed = false,
			Combo = 0,
			LastSwing = 0,
			ChantStart = nil,
			Domain = nil,
		}
		playerState[player] = st
	end
	return st
end

local function sendState(player)
	local st = getState(player)
	Combat.FXTo(player, "UI_State", { Unlocked = st.Unlocked, DogsDestroyed = st.DogsDestroyed })
end

function Abilities.Unlock(player, abilityName, message)
	local st = getState(player)
	if st.Unlocked[abilityName] then
		return
	end
	st.Unlocked[abilityName] = true
	Combat.FXTo(player, "UI_Unlock", { Ability = abilityName })
	if message then
		Combat.Notice(message, Color3.fromRGB(255, 226, 150), player)
	end
	sendState(player)
end

local function incantation(player, name, toEveryone)
	local cfg = A[name]
	local params = { Title = cfg.Name, Sub = cfg.Kanji }
	if toEveryone then
		Combat.FX("UI_Incantation", params)
	else
		Combat.FXTo(player, "UI_Incantation", params)
	end
end

local function alive(model)
	return model ~= nil and Combat.IsAlive(model)
end

local function inOwnDomain(st, pos)
	local d = st.Domain
	return d ~= nil and time() < d.Until and flat(pos - d.Center).Magnitude <= d.Radius
end

local function flatDir(from, to, fallback)
	local d = flat(to - from)
	if d.Magnitude < 0.1 then
		return fallback
	end
	return d.Unit
end

---------------------------------------------------------------- handlers
-- Each handler receives ctx = { Player, Character, Root, Humanoid, Aim, State } and returns true
-- if the technique was used (starts the cooldown).

local H = {}

function H.ShadowBlade(ctx)
	local cfg = A.ShadowBlade
	local st = ctx.State
	local now = time()
	if now - st.LastSwing > cfg.ComboReset or st.Combo >= 4 then
		st.Combo = 0
	end
	st.Combo += 1
	st.LastSwing = now
	local root = ctx.Root
	local look = flatDir(root.Position, ctx.Aim, flat(root.CFrame.LookVector).Unit)
	Combat.FX("Blade", { CFrame = CFrame.lookAt(root.Position, root.Position + look), Combo = st.Combo })
	local finisher = st.Combo == 4
	local targets = Combat.GetTargets(ctx.Character, "Player", { Type = "Cone", Origin = root.Position, Dir = look, Range = cfg.Range, Angle = cfg.Angle })
	for _, t in ipairs(targets) do
		Combat.Damage(t, finisher and cfg.FinisherDamage or cfg.Damage, cfg.DamageType, {
			Source = ctx.Player, Knockback = finisher and (look * 45 + UP * 20) or nil,
		})
	end
	return true
end

function H.DivineDogs(ctx)
	local cfg = A.DivineDogs
	local st = ctx.State
	if st.DogsDestroyed then
		Combat.Notice("Your Divine Dog was destroyed. Its power lives on in Divine Dog: Totality (0).", nil, ctx.Player)
		return false
	end
	local target, pos = Combat.ResolveTarget(ctx.Character, ctx.Aim, cfg.Range)
	local look = flatDir(ctx.Root.Position, pos, flat(ctx.Root.CFrame.LookVector).Unit)
	local right = look:Cross(UP)
	nextDogId += 2
	local whiteId, blackId = "dog" .. nextDogId - 1, "dog" .. nextDogId
	incantation(ctx.Player, "DivineDogs")
	Combat.FX("DivineDogs", { Origin = ctx.Root.Position, Target = pos, WhiteId = whiteId, BlackId = blackId, Bites = cfg.Bites, Guard = cfg.GuardSeconds })

	local guardUntil = time() + 1 + cfg.Bites * 0.2 + cfg.GuardSeconds
	local base = flat(pos) - look * 3
	table.insert(guards, { Id = whiteId, White = true, Owner = ctx.Player, Pos = base - right * 2 + UP * pos.Y, Until = guardUntil })
	table.insert(guards, { Id = blackId, White = false, Owner = ctx.Player, Pos = base + right * 2 + UP * pos.Y, Until = guardUntil })

	task.delay(0.7, function()
		for _ = 1, cfg.Bites do
			if alive(target) then
				Combat.Damage(target, cfg.Damage, cfg.DamageType, { Source = ctx.Player })
				Combat.Damage(target, cfg.Damage, cfg.DamageType, { Source = ctx.Player, Silent = true })
			end
			task.wait(0.2)
		end
	end)
	return true
end

function H.Nue(ctx)
	local cfg = A.Nue
	local _, pos = Combat.ResolveTarget(ctx.Character, ctx.Aim, cfg.Range)
	incantation(ctx.Player, "Nue")
	Combat.FX("Nue", { Origin = ctx.Root.Position, Target = pos, Radius = cfg.Radius })
	task.delay(0.9, function()
		for _, t in ipairs(Combat.GetTargets(ctx.Character, "Player", { Type = "Circle", Pos = pos, Radius = cfg.Radius })) do
			Combat.Damage(t, cfg.Damage, cfg.DamageType, { Source = ctx.Player, Stun = cfg.Stun })
		end
	end)
	return true
end

function H.Toad(ctx)
	local cfg = A.Toad
	local target, pos = Combat.ResolveTarget(ctx.Character, ctx.Aim, cfg.Range)
	incantation(ctx.Player, "Toad")
	Combat.FX("Toad", { Origin = ctx.Root.Position, Target = pos })
	if not target then
		return true
	end
	task.delay(0.42, function()
		if not alive(target) or not ctx.Root.Parent then
			return
		end
		Combat.Damage(target, cfg.Damage, cfg.DamageType, { Source = ctx.Player, Stun = cfg.Stun })
		local troot = Combat.GetRoot(target)
		local dest = ctx.Root.Position + flatDir(ctx.Root.Position, troot.Position, ctx.Root.CFrame.LookVector) * 7
		if Players:GetPlayerFromCharacter(target) then
			Combat.Knockback(target, (dest - troot.Position) * 3 + UP * 20)
		elseif not target:GetAttribute("IsBoss") then
			-- the tongue drags small curses in; Mahoraga is too heavy and is only staggered
			local start = target:GetPivot()
			local goal = CFrame.new(Vector3.new(dest.X, start.Position.Y, dest.Z)) * start.Rotation
			for i = 1, 8 do
				if not target.Parent then
					break
				end
				target:PivotTo(start:Lerp(goal, i / 8))
				task.wait(0.04)
			end
		end
	end)
	return true
end

function H.GreatSerpent(ctx)
	local cfg = A.GreatSerpent
	local _, pos = Combat.ResolveTarget(ctx.Character, ctx.Aim, cfg.Range)
	local look = flatDir(ctx.Root.Position, pos, flat(ctx.Root.CFrame.LookVector).Unit)
	incantation(ctx.Player, "GreatSerpent")
	Combat.FX("GreatSerpent", { Target = pos, Radius = cfg.Radius, Look = look })
	task.delay(0.55, function()
		for _, t in ipairs(Combat.GetTargets(ctx.Character, "Player", { Type = "Circle", Pos = pos, Radius = cfg.Radius })) do
			local launch = not t:GetAttribute("IsBoss") and UP * 90 or nil
			Combat.Damage(t, cfg.Damage, cfg.DamageType, { Source = ctx.Player, Stun = cfg.Stun, Knockback = launch })
		end
	end)
	return true
end

function H.MaxElephant(ctx)
	local cfg = A.MaxElephant
	local root = ctx.Root
	local look = flatDir(root.Position, ctx.Aim, flat(root.CFrame.LookVector).Unit)
	incantation(ctx.Player, "MaxElephant")
	Combat.FX("MaxElephant", { Origin = root.Position, Dir = look, Range = cfg.Range, Angle = cfg.Angle })
	local origin = root.Position + look * 16
	task.delay(0.6, function()
		for _, t in ipairs(Combat.GetTargets(ctx.Character, "Player", { Type = "Cone", Origin = origin, Dir = look, Range = cfg.Range + 8, Angle = cfg.Angle })) do
			Combat.Damage(t, cfg.Damage, cfg.DamageType, { Source = ctx.Player, Knockback = look * cfg.Knockback + UP * 25, Stun = 0.5 })
		end
		-- the landing itself also crushes anything standing under the elephant
		for _, t in ipairs(Combat.GetTargets(ctx.Character, "Player", { Type = "Circle", Pos = origin, Radius = 10 })) do
			Combat.Damage(t, cfg.Damage * 0.3, cfg.DamageType, { Source = ctx.Player })
		end
	end)
	return true
end

function H.RabbitEscape(ctx)
	local cfg = A.RabbitEscape
	incantation(ctx.Player, "RabbitEscape")
	Combat.FX("RabbitEscape", { Origin = ctx.Root.Position, Duration = cfg.Duration, Radius = cfg.Radius })
	table.insert(Combat.Decoys, { Pos = ctx.Root.Position, Owner = ctx.Player, Until = time() + cfg.Duration })
	ctx.Character:SetAttribute("IFrameUntil", time() + 0.6)
	return true
end

function H.RoundDeer(ctx)
	local cfg = A.RoundDeer
	local char, humanoid = ctx.Character, ctx.Humanoid
	incantation(ctx.Player, "RoundDeer")
	Combat.FX("RoundDeer", { Origin = ctx.Root.Position, Look = ctx.Root.CFrame.LookVector, Duration = cfg.Duration, Character = char })
	char:SetAttribute("Reduction", cfg.DamageReduction)
	char:SetAttribute("ReductionUntil", time() + cfg.Duration)
	task.spawn(function()
		local ticks = 10
		for _ = 1, ticks do
			if humanoid.Health <= 0 then
				return
			end
			humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * cfg.HealFraction / ticks)
			task.wait(cfg.Duration / ticks)
		end
	end)
	return true
end

function H.PiercingOx(ctx)
	local cfg = A.PiercingOx
	local root = ctx.Root
	local look = flatDir(root.Position, ctx.Aim, flat(root.CFrame.LookVector).Unit)
	local from = root.Position - look * 4
	local to = root.Position + look * cfg.MaxDistance
	incantation(ctx.Player, "PiercingOx")
	Combat.FX("PiercingOx", { From = from, To = to, Speed = cfg.Speed })
	local total = (to - from).Magnitude
	local chargeTime = math.max(0.15, total / cfg.Speed)
	for _, t in ipairs(Combat.GetTargets(ctx.Character, "Player", { Type = "Line", From = from, To = to, Width = cfg.Width })) do
		local _, along = Combat.SegmentDistance(Combat.GetRoot(t).Position, from, to)
		local dist = along * total
		-- the ox accelerates (ease-in), so it reaches distance d at T * sqrt(d / total)
		task.delay(0.28 + chargeTime * math.sqrt(along), function()
			if alive(t) then
				Combat.Damage(t, DamageRules.OxDamage(cfg.BaseDamage, cfg.DamagePerStud, dist, cfg.MaxDistance), cfg.DamageType, {
					Source = ctx.Player, Knockback = look * 70 + UP * 30,
				})
			end
		end)
	end
	return true
end

function H.TigerFuneral(ctx)
	local cfg = A.TigerFuneral
	local target, pos = Combat.ResolveTarget(ctx.Character, ctx.Aim, cfg.Range)
	incantation(ctx.Player, "TigerFuneral")
	Combat.FX("TigerFuneral", { Origin = ctx.Root.Position, Target = pos, Hits = cfg.Hits })
	task.delay(0.55, function()
		for _ = 1, cfg.Hits do
			if alive(target) then
				Combat.Damage(target, cfg.Damage, cfg.DamageType, { Source = ctx.Player })
			end
			task.wait(0.14)
		end
	end)
	return true
end

function H.Totality(ctx)
	local cfg = A.Totality
	local target, pos = Combat.ResolveTarget(ctx.Character, ctx.Aim, cfg.Range)
	incantation(ctx.Player, "Totality")
	Combat.FX("Totality", { Origin = ctx.Root.Position, Target = pos, Hits = cfg.Hits })
	task.delay(0.75, function()
		for i = 1, cfg.Hits do
			if alive(target) then
				local kb = i == cfg.Hits and not target:GetAttribute("IsBoss") and (flatDir(ctx.Root.Position, pos, UP) * 60 + UP * 30) or nil
				Combat.Damage(target, cfg.Damage, cfg.DamageType, { Source = ctx.Player, Knockback = kb })
			end
			task.wait(0.13)
		end
	end)
	return true
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

function H.ShadowStep(ctx)
	local cfg = A.ShadowStep
	local root = ctx.Root
	local offset = flat(ctx.Aim - root.Position)
	if offset.Magnitude > cfg.Range then
		offset = offset.Unit * cfg.Range
	end
	local dest = root.Position + offset
	local exclude = { ctx.Character }
	local fx = workspace:FindFirstChild("TenShadowsFX")
	if fx then
		table.insert(exclude, fx)
	end
	for _, model in ipairs(Combat.AllCombatants()) do
		table.insert(exclude, model)
	end
	rayParams.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(dest + UP * 40, -UP * 120, rayParams)
	if not hit then
		return false
	end
	local groundPos = hit.Position
	local look = offset.Magnitude > 0.1 and offset.Unit or flat(root.CFrame.LookVector).Unit
	ctx.Character:SetAttribute("IFrameUntil", time() + cfg.IFrames)
	Combat.FX("ShadowStep", { From = root.Position - UP * 3, To = groundPos })
	task.delay(0.18, function()
		if ctx.Character.Parent then
			ctx.Character:PivotTo(CFrame.lookAt(groundPos + UP * 3.2, groundPos + UP * 3.2 + look))
		end
	end)
	return true
end

function H.ChimeraShadowGarden(ctx)
	local cfg = A.ChimeraShadowGarden
	local st = ctx.State
	local center = ctx.Root.Position - UP * 3
	local untilTime = time() + cfg.Duration
	st.Domain = { Center = center, Radius = cfg.Radius, Until = untilTime }
	table.insert(Combat.SlowZones, { Center = center, Radius = cfg.Radius, Factor = cfg.EnemySlow, Until = untilTime, Owner = ctx.Player })
	incantation(ctx.Player, "ChimeraShadowGarden", true)
	Combat.FX("Domain", { Center = center, Radius = cfg.Radius, Duration = cfg.Duration, Id = tostring(ctx.Player.UserId) .. tostring(untilTime) })
	task.spawn(function()
		task.wait(0.9)
		while time() < untilTime and ctx.Player.Parent and alive(ctx.Character) do
			for _, t in ipairs(Combat.GetTargets(ctx.Character, "Player", { Type = "Circle", Pos = center, Radius = cfg.Radius })) do
				local tpos = Combat.GetRoot(t).Position
				local a = math.random() * math.pi * 2
				local r = (t:GetAttribute("HitRadius") or 2) + 4
				local spawnPos = Vector3.new(tpos.X + math.cos(a) * r, center.Y, tpos.Z + math.sin(a) * r)
				Combat.FX("DomainClone", { Pos = spawnPos, Target = tpos })
				task.delay(0.22, function()
					if alive(t) then
						Combat.Damage(t, cfg.CloneDamage, cfg.DamageType, { Source = ctx.Player })
					end
				end)
			end
			task.wait(cfg.CloneInterval)
		end
		st.Domain = nil
	end)
	return true
end

local function nearestEnemy(ctx, range)
	local best, bestDist = nil, range
	for _, model in ipairs(Combat.AllCombatants()) do
		if Combat.IsEnemy("Player", ctx.Character, model) then
			local d = flat(Combat.GetRoot(model).Position - ctx.Root.Position).Magnitude
			if d < bestDist then
				best, bestDist = model, d
			end
		end
	end
	return best
end

-- Shared loop for summons that fight on their own for a while (Agito, tamed Mahoraga).
local function autoSummon(ctx, cfg, fxName, offset, extra)
	local untilTime = time() + cfg.Duration
	task.spawn(function()
		while time() < untilTime and ctx.Player.Parent and alive(ctx.Character) do
			local target = nearestEnemy(ctx, cfg.Range)
			if target then
				local tpos = Combat.GetRoot(target).Position
				local dir = flatDir(ctx.Root.Position, tpos, flat(ctx.Root.CFrame.LookVector).Unit)
				local spawnPos = Vector3.new(tpos.X, ctx.Root.Position.Y - 3, tpos.Z) - dir * (offset + (target:GetAttribute("HitRadius") or 2))
				Combat.FX(fxName, { Pos = spawnPos, Target = tpos, CasterPos = extra and extra.HealFX and ctx.Root.Position or nil })
				task.delay(0.22, function()
					if alive(target) then
						Combat.Damage(target, cfg.Damage, cfg.DamageType, { Source = ctx.Player, CurseMultiplier = cfg.CurseMultiplier })
					end
					if cfg.HealPerStrike and ctx.Humanoid.Health > 0 then
						ctx.Humanoid.Health = math.min(ctx.Humanoid.MaxHealth, ctx.Humanoid.Health + cfg.HealPerStrike)
					end
				end)
			end
			task.wait(cfg.Interval)
		end
	end)
end

function H.Agito(ctx)
	incantation(ctx.Player, "Agito")
	autoSummon(ctx, A.Agito, "Agito", 6, { HealFX = true })
	return true
end

function H.TamedMahoraga(ctx)
	incantation(ctx.Player, "TamedMahoraga", true)
	autoSummon(ctx, A.TamedMahoraga, "TamedMahoraga", 10)
	return true
end

function H.Ritual(ctx)
	local cfg = A.Ritual
	local st = ctx.State
	local started = st.ChantStart
	st.ChantStart = nil
	if not started or time() - started < cfg.HoldSeconds - 0.25 then
		return false
	end
	if Mahoraga.IsAlive() then
		Combat.Notice("Mahoraga is already manifested.", nil, ctx.Player)
		return false
	end
	local look = flat(ctx.Root.CFrame.LookVector).Unit
	local spawnAt = ctx.Root.Position + look * cfg.SpawnDistance
	Combat.FX("UI_Incantation", { Title = "With this treasure, I summon...", Sub = "布瑠部由良由良", Color = Color3.fromRGB(190, 150, 255) })
	Combat.Notice(ctx.Player.DisplayName .. " began the exorcism ritual. Mahoraga attacks EVERYONE, summoner included.", Color3.fromRGB(255, 120, 120))
	task.spawn(Mahoraga.Spawn, Vector3.new(spawnAt.X, 0, spawnAt.Z), ctx.Player)
	return true
end

---------------------------------------------------------------- special inputs (not cooldown abilities)

local function onRitualStart(ctx)
	local st = ctx.State
	if (st.Cooldowns.Ritual or 0) > time() then
		return
	end
	st.ChantStart = time()
	Combat.FX("Chant", { Pos = ctx.Root.Position - UP * 3 })
	Combat.FX("UI_Incantation", { Title = "Furube Yura Yura", Sub = "布瑠部由良由良", Color = Color3.fromRGB(190, 150, 255) })
end

local function onBlock(ctx, on)
	ctx.Character:SetAttribute("Blocking", on == true)
	ctx.Humanoid.WalkSpeed = on and Config.Player.BlockWalkSpeed or Config.Player.WalkSpeed
end

---------------------------------------------------------------- dispatch

local function isLocked(st, name)
	return A[name] and A[name].Locked and not st.Unlocked[name]
end

local function handle(player, name, aim, extra)
	if typeof(name) ~= "string" then
		return
	end
	if name == "RequestState" then
		sendState(player)
		return
	end
	local char = player.Character
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if typeof(aim) ~= "Vector3" then
		aim = root.Position + root.CFrame.LookVector * 20
	end
	local st = getState(player)
	local ctx = { Player = player, Character = char, Root = root, Humanoid = humanoid, Aim = aim, State = st }

	if name == "Block" then
		onBlock(ctx, extra == true)
		return
	elseif name == "RitualStart" then
		onRitualStart(ctx)
		return
	elseif name == "RitualCancel" then
		st.ChantStart = nil
		return
	end

	local handler = H[name]
	local cfg = A[name]
	if not handler or not cfg then
		return
	end
	local isDomain = name == "ChimeraShadowGarden"
	local canUseWhileBlocking = name == "ShadowStep"
	if char:GetAttribute("Blocking") and not canUseWhileBlocking then
		return
	end
	if isLocked(st, name) then
		Combat.Notice(cfg.Name .. " is locked. " .. (cfg.UnlockHint or ""), nil, player)
		return
	end
	local now = time()
	if (st.Cooldowns[name] or 0) > now then
		return
	end
	-- claim the cooldown before running so spam clicks can't double cast
	st.Cooldowns[name] = now + 999
	local ok, used = pcall(handler, ctx)
	if not ok then
		warn("[TenShadows] " .. name .. " failed: " .. tostring(used))
		used = false
	end
	if used then
		local cd = cfg.Cooldown or 0
		if not isDomain and inOwnDomain(st, root.Position) then
			cd *= A.ChimeraShadowGarden.CooldownMultiplier
		end
		st.Cooldowns[name] = now + cd
		if cd >= 1 then
			Combat.FXTo(player, "UI_Cooldown", { Ability = name, Duration = cd })
		end
	else
		st.Cooldowns[name] = 0
	end
end

function Abilities.Init()
	Combat.AbilityRemote.OnServerEvent:Connect(handle)
	Players.PlayerRemoving:Connect(function(player)
		playerState[player] = nil
	end)

	-- Enemy attacks that cover a guarding Divine Dog destroy it (canon: a destroyed shikigami is
	-- gone for good, and its power passes on - the surviving dog becomes Divine Dog: Totality).
	table.insert(Combat.AreaHitHooks, function(shape)
		local now = time()
		for i = #guards, 1, -1 do
			local g = guards[i]
			if now > g.Until or not g.Owner.Parent then
				table.remove(guards, i)
			elseif Combat.InShape(g.Pos, shape, 1.5) then
				table.remove(guards, i)
				Combat.FX("DogDestroyed", { Id = g.Id, Pos = g.Pos })
				local st = getState(g.Owner)
				if not st.DogsDestroyed then
					st.DogsDestroyed = true
					local which = g.White and "White" or "Black"
					local other = g.White and "Black" or "White"
					Abilities.Unlock(g.Owner, "Totality", "The " .. which .. " Divine Dog was destroyed. Its power passes to the " .. other .. " Dog: DIVINE DOG: TOTALITY unlocked (0).")
				end
			end
		end
	end)
end

function Abilities.ResetCooldowns(player)
	getState(player).Cooldowns = {}
end

return Abilities
