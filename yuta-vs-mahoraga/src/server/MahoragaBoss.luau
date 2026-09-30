--!strict
--[[
	Mahoraga, the boss.

	Adaptation (canon): every technique that hits Mahoraga is tracked. After enough
	casts of the same technique the Dharma wheel turns one step, Mahoraga heals a
	little and takes 25% less damage from that technique. Four turns = fully
	adapted (immune). It also adapts to Infinity, so Six Eyes mode protects less
	and less the longer you rely on it. Vary your techniques.

	Attacks (all telegraphed on the ground)
	  Sword of Extermination sweep, overhead cleave with a shockwave line,
	  three-hit fist combo, earth-shaking stomp, leap slam, rush,
	  and below 50% health: rings of positive energy you must jump over.

	Damage to players goes through Combat.damage, which caps every boss hit at a
	fraction of the player's max health (no instant kills).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Config = require(Shared:WaitForChild("Config"))
local Palette = require(Shared:WaitForChild("Palette"))
local Util = require(Shared:WaitForChild("Util"))
local Mahoraga = require(Shared:WaitForChild("Assets"):WaitForChild("Mahoraga"))

local Combat = require(script.Parent.Combat)
local FX = require(script.Parent.FX)

local B = Config.Boss
local A = Config.Adaptation
local D = B.Damage

type AdaptState = { Level: number, Casts: number, Seen: { [string]: boolean } }

type Zone = { Center: Vector3, Radius: number, Until: number }

type BossState = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Entity: Combat.Entity,
	Alive: boolean,
	Busy: boolean,
	Phase: number,
	Anim: string,
	Cooldowns: { [string]: number },
	NextAttack: number,
	Adapt: { [string]: AdaptState },
	WheelTurns: number,
	Threat: { [Player]: number },
	DamageBy: { [Player]: number },
	Target: Combat.Entity?,
	Zone: Zone?,
	IdleTime: number,
	Rng: Random,
	OnEnded: (() -> ())?,
	-- Methods other systems call with ':' (YutaKit uses them for Infinity and the domain).
	AdaptFraction: (any, string) -> number,
	RegisterCast: (any, string, string?) -> (),
	Confine: (any, Vector3, number, number) -> (),
}

local MahoragaBoss = {}

local current: BossState? = nil

-- Helpers ------------------------------------------------------------------------------

local function setAnim(b: BossState, name: string)
	b.Anim = name
	b.Model:SetAttribute("JJK_Anim", name)
	b.Model:SetAttribute("JJK_AnimT", workspace:GetServerTimeNow())
end

local function release(b: BossState)
	b.Root.Anchored = false
	pcall(function()
		b.Root:SetNetworkOwner(nil)
	end)
end

local function groundCF(b: BossState): CFrame
	local ground = Combat.groundAt(b.Root.Position)
	return Util.facing(ground, b.Root.CFrame.LookVector)
end

local function face(b: BossState, pos: Vector3)
	local r = b.Root
	r.CFrame = Util.facing(r.Position, pos - r.Position)
end

local function stop(b: BossState)
	b.Humanoid:MoveTo(b.Root.Position)
end

local function windup(b: BossState, seconds: number): number
	return seconds * (B.WindupScale[b.Phase] or 1)
end

-- Waits, but gives up early if Mahoraga dies or gets stunned (Cursed Speech interrupts attacks).
local function waitFor(b: BossState, seconds: number): boolean
	local t = 0
	while t < seconds do
		t += task.wait(0.05)
		if not b.Alive or b.Entity.StunnedUntil > os.clock() then
			return false
		end
	end
	return true
end

local function inBounds(b: BossState, pos: Vector3): boolean
	if Config.World.BuildArena then
		local c = Config.World.ArenaCenter
		local half = Config.World.ArenaSize / 2 - 14
		if math.abs(pos.X - c.X) > half or math.abs(pos.Z - c.Z) > half then
			return false
		end
	end
	local zone = b.Zone
	if zone and zone.Until > os.clock() and Util.flat(pos - zone.Center).Magnitude > zone.Radius then
		return false
	end
	return true
end

local function clampPoint(b: BossState, pos: Vector3): Vector3
	local p = pos
	if Config.World.BuildArena then
		local c = Config.World.ArenaCenter
		local half = Config.World.ArenaSize / 2 - 14
		p = Vector3.new(math.clamp(p.X, c.X - half, c.X + half), p.Y, math.clamp(p.Z, c.Z - half, c.Z + half))
	end
	local zone = b.Zone
	if zone and zone.Until > os.clock() then
		local offset = Util.flat(p - zone.Center)
		if offset.Magnitude > zone.Radius then
			local edge = zone.Center + offset.Unit * zone.Radius
			p = Vector3.new(edge.X, p.Y, edge.Z)
		end
	end
	return p
end

local function clampLength(b: BossState, cf: CFrame, length: number): number
	local l = length
	while l > 6 and not inBounds(b, (cf * CFrame.new(0, 0, -l)).Position) do
		l -= 4
	end
	return l
end

-- Adaptation -----------------------------------------------------------------------------

local function adaptLevel(b: BossState, kind: string): number
	local a = b.Adapt[kind]
	return if a then a.Level else 0
end

local function resist(b: BossState, kind: string): number
	return math.min(1, adaptLevel(b, kind) * A.ResistPerLevel)
end

local function turnWheel(b: BossState, kind: string, level: number)
	b.WheelTurns += 1
	b.Model:SetAttribute("JJK_WheelTurns", b.WheelTurns)
	local h = b.Humanoid
	local heal = h.MaxHealth * A.HealPerTurn
	h.Health = math.min(h.MaxHealth, h.Health + heal)
	FX.all("WheelTurn", {
		boss = b.Model,
		typeName = A.DisplayNames[kind] or kind,
		level = level,
		maxLevel = A.MaxLevel,
		turns = b.WheelTurns,
		heal = heal,
	})
end

local function registerCast(b: BossState, kind: string, castId: string?)
	local a = b.Adapt[kind]
	if not a then
		a = { Level = 0, Casts = 0, Seen = {} }
		b.Adapt[kind] = a
	end
	local state = a :: AdaptState
	if state.Level >= A.MaxLevel then
		return
	end
	if castId then
		if state.Seen[castId] then
			return
		end
		state.Seen[castId] = true
	end
	state.Casts += 1
	local need = A.CastsPerTurn[kind] or A.CastsPerTurn.Default
	if b.Phase >= 3 then
		need = math.max(1, need - 1)
	end
	if state.Casts >= need then
		state.Casts = 0
		state.Level += 1
		state.Seen = {}
		turnWheel(b, kind, state.Level)
	end
	b.Model:SetAttribute("JJK_Adapt_" .. kind, state.Level + state.Casts / need)
end

-- Phases, threat, death ------------------------------------------------------------------

local function setPhase(b: BossState, phase: number)
	if phase <= b.Phase then
		return
	end
	b.Phase = phase
	b.Model:SetAttribute("JJK_Phase", phase)
	b.Humanoid.WalkSpeed = if phase >= 2 then B.EnragedWalkSpeed else B.WalkSpeed
	if phase == 2 then
		FX.all("Announce", { title = "魔虚羅", sub = "Mahoraga is enraged - watch for the rings!", color = Palette.Danger, time = 2.4 })
	else
		FX.all("Announce", { title = "適応", sub = "Adaptation accelerates", color = Palette.Wheel, time = 2.4 })
	end
end

local function die(b: BossState)
	if not b.Alive then
		return
	end
	b.Alive = false
	b.Busy = true
	Combat.unregister(b.Entity)
	setAnim(b, "Death")
	b.Root.Anchored = true
	local best: Player? = nil
	local bestDamage = 0
	for player, dmg in b.DamageBy do
		if dmg > bestDamage and player.Parent then
			best, bestDamage = player, dmg
		end
	end
	FX.all("BossDeath", { boss = b.Model, pos = b.Root.Position })
	FX.all("Announce", {
		title = "調伏",
		sub = if best then ("Mahoraga has been exorcised!  MVP: %s (%d damage)"):format(best.DisplayName, math.floor(bestDamage)) else "Mahoraga has been exorcised!",
		color = Palette.Wheel,
		time = 4,
	})
	task.delay(4.5, function()
		b.Model:Destroy()
	end)
	if current == b then
		current = nil
	end
	if b.OnEnded then
		b.OnEnded()
	end
end

local function despawn(b: BossState)
	if not b.Alive then
		return
	end
	b.Alive = false
	Combat.unregister(b.Entity)
	FX.all("Summon", { pos = Combat.groundAt(b.Root.Position), time = 1.5, reverse = true })
	FX.all("Announce", { title = "魔虚羅", sub = "Mahoraga sinks back into the shadows", color = Palette.YutaEnergy, time = 2.5 })
	b.Root.Anchored = true
	local tween = TweenService:Create(b.Root, TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = b.Root.CFrame * CFrame.new(0, -34, 0),
	})
	tween:Play()
	task.delay(1.6, function()
		b.Model:Destroy()
	end)
	if current == b then
		current = nil
	end
	if b.OnEnded then
		b.OnEnded()
	end
end

local function pickTarget(b: BossState): Combat.Entity?
	local best: Combat.Entity? = nil
	local bestScore = -math.huge
	for _, e in Combat.enemiesOf(b.Entity) do
		local d = (e.Root.Position - b.Root.Position).Magnitude
		if d < 420 and e.Player then
			local score = (b.Threat[e.Player] or 0) / 150 - d / 40
			if e == b.Target then
				score += 1.5
			end
			if score > bestScore then
				best, bestScore = e, score
			end
		end
	end
	return best
end

-- Attacks ------------------------------------------------------------------------------

local attacks: { [string]: (BossState, Combat.Entity) -> () } = {}

attacks.Sweep = function(b, target)
	face(b, target.Root.Position)
	local cf = groundCF(b)
	local wind = windup(b, 0.8)
	setAnim(b, "SweepWindup")
	FX.all("Telegraph", { shape = "arc", cf = cf, radius = 24, arc = 200, time = wind, color = Palette.Danger })
	if not waitFor(b, wind) then
		return
	end
	setAnim(b, "Sweep")
	FX.all("BossSlash", { cf = cf * CFrame.new(0, 9, 0), radius = 19, arc = 200, kind = "sweep" })
	FX.shake(cf.Position, 0.8, 0.35, 140)
	for _, e in Combat.query(b.Entity, function(e)
		return Combat.inArc(e, cf, 24, 200, 12)
	end) do
		local away = Util.flatUnit(e.Root.Position - cf.Position, cf.LookVector)
		Combat.damage(b.Entity, e, D.Sweep, {
			Type = "Sword",
			Knockback = away * 60 + Vector3.new(0, 30, 0),
			KnockbackTime = 0.25,
			Stun = 0.3,
			Color = Palette.Positive,
		})
	end
	task.wait(0.55)
end

attacks.Cleave = function(b, target)
	face(b, target.Root.Position)
	local cf = groundCF(b)
	local length = clampLength(b, cf, 72)
	local width = 10
	local wind = windup(b, 0.9)
	setAnim(b, "CleaveWindup")
	FX.all("Telegraph", { shape = "rect", cf = cf * CFrame.new(0, 0, -3), width = width, length = length, time = wind, color = Palette.Positive })
	if not waitFor(b, wind) then
		return
	end
	setAnim(b, "Cleave")
	FX.all("BossSlash", { cf = cf * CFrame.new(0, 10, -6) * CFrame.Angles(0, 0, math.rad(90)), radius = 12, arc = 160, kind = "cleave" })
	FX.all("BossWave", { cf = cf * CFrame.new(0, 0, -3), length = length, width = width })
	FX.shake(cf.Position, 1.1, 0.5, 160)
	local box = cf * CFrame.new(0, 4, -3 - length / 2)
	local size = Vector3.new(width, 10, length)
	for _, e in Combat.query(b.Entity, function(e)
		return Combat.inBox(e, box, size)
	end) do
		Combat.damage(b.Entity, e, D.Cleave, {
			Type = "Sword",
			Unblockable = true,
			Knockback = cf.LookVector * 30 + Vector3.new(0, 50, 0),
			KnockbackTime = 0.3,
			Stun = 0.4,
			Color = Palette.Positive,
		})
	end
	task.wait(0.7)
end

attacks.Punch = function(b, target)
	for i = 1, 3 do
		if not Combat.isAlive(target) then
			break
		end
		face(b, target.Root.Position)
		local cf = groundCF(b)
		local point = cf * CFrame.new(0, 0, -10)
		local right = i % 2 == 1
		local wind = windup(b, 0.4)
		setAnim(b, if right then "PunchWindupR" else "PunchWindupL")
		FX.all("Telegraph", { shape = "circle", cf = point, radius = 8, time = wind, color = Palette.Danger })
		if not waitFor(b, wind) then
			return
		end
		setAnim(b, if right then "PunchR" else "PunchL")
		FX.all("Impact", { pos = point.Position, radius = 8, color = Palette.Positive, cracks = i == 3 })
		local strong = i == 3
		for _, e in Combat.query(b.Entity, function(e)
			return Combat.inSphere(e, point.Position + Vector3.new(0, 3, 0), 8)
		end) do
			Combat.damage(b.Entity, e, D.Punch, {
				Type = "Fist",
				Knockback = cf.LookVector * (if strong then 70 else 25) + Vector3.new(0, if strong then 35 else 10, 0),
				KnockbackTime = 0.2,
				Stun = 0.25,
				Color = Palette.Positive,
			})
		end
		task.wait(0.22)
	end
	task.wait(0.4)
end

attacks.Stomp = function(b, _target)
	local cf = groundCF(b)
	local radius = 26
	local wind = windup(b, 0.95)
	setAnim(b, "StompWindup")
	FX.all("Telegraph", { shape = "circle", cf = cf, radius = radius, time = wind, color = Palette.Danger })
	if not waitFor(b, wind) then
		return
	end
	setAnim(b, "Stomp")
	FX.all("Impact", { pos = cf.Position, radius = radius, color = Palette.Positive, cracks = true, big = true })
	FX.shake(cf.Position, 1.4, 0.6, 180)
	for _, e in Combat.query(b.Entity, function(e)
		return Combat.inSphere(e, cf.Position, radius) and Combat.heightAboveGround(e) < 7
	end) do
		local away = Util.flatUnit(e.Root.Position - cf.Position)
		Combat.damage(b.Entity, e, D.Stomp, {
			Type = "Fist",
			Knockback = away * 45 + Vector3.new(0, 55, 0),
			KnockbackTime = 0.3,
			Stun = 0.35,
			Color = Palette.Positive,
		})
	end
	task.wait(0.6)
end

attacks.Leap = function(b, target)
	face(b, target.Root.Position)
	local landing = clampPoint(b, Combat.groundAt(target.Root.Position))
	local radius = 20
	local crouch = windup(b, 0.45)
	local air = 1.05
	setAnim(b, "LeapCrouch")
	FX.all("Telegraph", { shape = "circle", cf = CFrame.new(landing), radius = radius, time = crouch + air, color = Palette.Danger })
	if not waitFor(b, crouch) then
		return
	end
	setAnim(b, "LeapAir")
	b.Root.Anchored = true
	local startPos = b.Root.Position
	local endPos = landing + Vector3.new(0, Mahoraga.RootHeight, 0)
	local dir = Util.flatUnit(endPos - startPos, b.Root.CFrame.LookVector)
	local t0 = os.clock()
	while b.Alive do
		local a = math.min(1, (os.clock() - t0) / air)
		local pos = startPos:Lerp(endPos, a) + Vector3.new(0, 104 * a * (1 - a), 0)
		b.Root.CFrame = CFrame.lookAt(pos, pos + dir)
		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	if not b.Alive then
		return
	end
	release(b)
	setAnim(b, "LeapLand")
	FX.all("Impact", { pos = landing, radius = radius, color = Palette.Positive, cracks = true, big = true, rocks = true })
	FX.shake(landing, 1.8, 0.7, 220)
	for _, e in Combat.query(b.Entity, function(e)
		return Combat.inSphere(e, landing + Vector3.new(0, 3, 0), radius)
	end) do
		local away = Util.flatUnit(e.Root.Position - landing)
		Combat.damage(b.Entity, e, D.Leap, {
			Type = "Fist",
			Knockback = away * 60 + Vector3.new(0, 45, 0),
			KnockbackTime = 0.3,
			Stun = 0.4,
			Color = Palette.Positive,
		})
	end
	task.wait(0.8)
end

attacks.Rush = function(b, target)
	face(b, target.Root.Position)
	local cf = groundCF(b)
	local dist = Util.flat(target.Root.Position - b.Root.Position).Magnitude
	local length = clampLength(b, cf, math.clamp(dist + 14, 20, 70))
	local width = 11
	local wind = windup(b, 0.7)
	setAnim(b, "RushWindup")
	FX.all("Telegraph", { shape = "rect", cf = cf, width = width, length = length + 6, time = wind, color = Palette.Danger })
	if not waitFor(b, wind) then
		return
	end
	setAnim(b, "Rush")
	local startPos = b.Root.Position
	local endPos = startPos + cf.LookVector * length
	FX.all("BossRush", { from = startPos, to = endPos })
	b.Root.Anchored = true
	local duration = 0.45
	local t0 = os.clock()
	local hit: { [Combat.Entity]: boolean } = {}
	while b.Alive do
		local a = math.min(1, (os.clock() - t0) / duration)
		local pos = startPos:Lerp(endPos, a)
		b.Root.CFrame = CFrame.lookAt(pos, pos + cf.LookVector)
		local low = pos - Vector3.new(0, Mahoraga.RootHeight - 3, 0)
		for _, e in Combat.query(b.Entity, function(e)
			return Combat.inSphere(e, low, 7)
		end) do
			if not hit[e] then
				hit[e] = true
				local side = Util.flatUnit(e.Root.Position - low, cf.RightVector)
				Combat.damage(b.Entity, e, D.Rush, {
					Type = "Fist",
					Knockback = cf.LookVector * 55 + side * 25 + Vector3.new(0, 30, 0),
					KnockbackTime = 0.3,
					Stun = 0.35,
					Color = Palette.Positive,
				})
			end
		end
		if a >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	if not b.Alive then
		return
	end
	release(b)
	task.wait(0.6)
end

-- Phase 2+: rings of positive energy roll outward along the ground. Jump over them.
attacks.Rings = function(b, _target)
	local cf = groundCF(b)
	local count = if b.Phase >= 3 then 4 else 3
	local interval, speed, maxRadius = 0.65, 32, 75
	local wind = windup(b, 1.0)
	setAnim(b, "BurstWindup")
	FX.all("Telegraph", { shape = "circle", cf = cf, radius = maxRadius, time = wind, color = Palette.Positive })
	FX.near(cf.Position, 140, "Notify", { text = "Jump over the rings of positive energy!" })
	if not waitFor(b, wind) then
		return
	end
	setAnim(b, "Burst")
	FX.all("BossRings", { center = cf.Position, count = count, interval = interval, speed = speed, maxRadius = maxRadius })
	local t0 = os.clock()
	local hit: { { [Combat.Entity]: boolean } } = {}
	for k = 1, count do
		hit[k] = {}
	end
	local total = (count - 1) * interval + maxRadius / speed
	while b.Alive and os.clock() - t0 < total do
		local elapsed = os.clock() - t0
		for k = 1, count do
			local r = (elapsed - (k - 1) * interval) * speed
			if r > 0 and r < maxRadius then
				for _, e in Combat.enemiesOf(b.Entity) do
					if not hit[k][e] then
						local d = Util.flat(e.Root.Position - cf.Position).Magnitude
						if math.abs(d - r) <= 2.2 + e.Radius * 0.5 and Combat.heightAboveGround(e) < 4.6 then
							hit[k][e] = true
							Combat.damage(b.Entity, e, D.Ring, {
								Type = "Positive",
								Unblockable = true,
								Knockback = Util.flatUnit(e.Root.Position - cf.Position) * 35 + Vector3.new(0, 30, 0),
								KnockbackTime = 0.2,
								Stun = 0.2,
								Color = Palette.Positive,
							})
						end
					end
				end
			end
		end
		RunService.Heartbeat:Wait()
	end
	task.wait(0.3)
end

local function chooseAttack(b: BossState, dist: number): string?
	local now = os.clock()
	local weights: { [string]: number } = {}
	local function add(name: string, weight: number)
		if (b.Cooldowns[name] or 0) <= now then
			weights[name] = weight
		end
	end
	if dist <= 20 then
		add("Sweep", 3)
		add("Punch", 3)
		add("Stomp", 2)
		add("Cleave", 1.5)
	elseif dist <= 60 then
		add("Cleave", 3)
		add("Rush", 3)
		add("Leap", 2)
	else
		add("Leap", 4)
		add("Rush", 1)
	end
	if b.Phase >= 2 and dist <= 70 then
		add("Rings", 2.5)
	end
	return Util.weightedPick(b.Rng, weights)
end

-- AI -----------------------------------------------------------------------------------

local function step(b: BossState, dt: number)
	for player, threat in b.Threat do
		b.Threat[player] = threat * 0.985
	end
	if b.Busy then
		return
	end
	local now = os.clock()
	if b.Entity.StunnedUntil > now then
		stop(b)
		if b.Anim ~= "Stunned" then
			setAnim(b, "Stunned")
		end
		return
	end

	local target = pickTarget(b)
	b.Target = target
	if not target then
		stop(b)
		if b.Anim ~= "Move" then
			setAnim(b, "Move")
		end
		b.IdleTime += dt
		if b.IdleTime > 40 then
			despawn(b)
		end
		return
	end
	b.IdleTime = 0

	local dist = Util.flat(target.Root.Position - b.Root.Position).Magnitude
	if now >= b.NextAttack then
		local attack = chooseAttack(b, dist)
		if attack then
			b.Busy = true
			b.Cooldowns[attack] = now + (B.Cooldowns[attack] or 5)
			stop(b)
			b.Humanoid.AutoRotate = false
			task.spawn(function()
				local ok, err = pcall(function(): string?
					attacks[attack](b, target)
					return nil
				end)
				if not ok then
					warn("[Mahoraga] attack " .. attack .. " failed: " .. tostring(err))
				end
				if b.Alive then
					release(b)
					b.Humanoid.AutoRotate = true
					b.Busy = false
					b.NextAttack = os.clock() + (B.AttackGap[b.Phase] or 0.5)
					setAnim(b, "Move")
				end
			end)
			return
		end
	end

	if b.Anim ~= "Move" then
		setAnim(b, "Move")
	end
	if dist > 11 then
		b.Humanoid:MoveTo(clampPoint(b, target.Root.Position))
	else
		stop(b)
		face(b, target.Root.Position)
	end
end

-- Summoning ----------------------------------------------------------------------------

function MahoragaBoss.isActive(): boolean
	return current ~= nil
end

-- Rises out of the shadows at `spawnCF`. Yields for the summon animation.
function MahoragaBoss.summon(spawnCF: CFrame, onEnded: (() -> ())?): boolean
	if current then
		return false
	end
	local ground = Combat.groundAt(spawnCF.Position + Vector3.new(0, 10, 0))
	local facing = Util.facing(ground, spawnCF.LookVector)

	local model = Mahoraga.build(facing * CFrame.new(0, -34, 0))
	local root = model.PrimaryPart :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			d.Anchored = false
		end
	end
	root.Anchored = true
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	local hp = B.BaseHealth + B.HealthPerExtraPlayer * math.max(0, #Players:GetPlayers() - 1)
	humanoid.MaxHealth = hp
	humanoid.Health = hp
	humanoid.WalkSpeed = B.WalkSpeed
	-- In games with streaming on, stream the whole rig at once so clients can animate it.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("JJK_Boss", true)
	model:SetAttribute("JJK_Title", B.Title)
	model:SetAttribute("JJK_Name", B.Name)
	model:SetAttribute("JJK_Kanji", B.Kanji)
	model:SetAttribute("JJK_Phase", 1)
	model:SetAttribute("JJK_WheelTurns", 0)
	model:SetAttribute("JJK_Anim", "Summon")
	model:SetAttribute("JJK_AnimT", workspace:GetServerTimeNow())
	model.Parent = workspace
	CollectionService:AddTag(model, "JJK_Mahoraga")

	local placeholder = {} -- reserve the slot while rising
	current = placeholder :: any

	FX.all("Summon", { pos = ground, time = B.SummonTime })
	FX.all("Announce", { title = "布瑠部由良由良", sub = "With this treasure, I summon...", color = Palette.Wheel, time = 2.2 })
	local rise = TweenService:Create(root, TweenInfo.new(B.SummonTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = facing * CFrame.new(0, Mahoraga.RootHeight, 0),
	})
	rise:Play()
	rise.Completed:Wait()
	if not model.Parent then
		current = nil
		return false
	end

	local entity = Combat.register(model, humanoid, root, "Boss", nil)
	local b: BossState
	b = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Entity = entity,
		Alive = true,
		Busy = false,
		Phase = 1,
		Anim = "Move",
		Cooldowns = {},
		NextAttack = os.clock() + 1.5,
		Adapt = {},
		WheelTurns = 0,
		Threat = {},
		DamageBy = {},
		Target = nil,
		Zone = nil,
		IdleTime = 0,
		Rng = Random.new(),
		OnEnded = onEnded,
		AdaptFraction = function(_self: any, kind: string): number
			return adaptLevel(b, kind) / A.MaxLevel
		end,
		RegisterCast = function(_self: any, kind: string, castId: string?)
			registerCast(b, kind, castId)
		end,
		Confine = function(_self: any, center: Vector3, radius: number, duration: number)
			b.Zone = { Center = center, Radius = radius, Until = os.clock() + duration }
		end,
	}
	current = b
	entity.Controller = b

	entity.ModifyIncoming = function(amount, info, _attacker)
		local r = resist(b, info.Type)
		registerCast(b, info.Type, info.CastId)
		if r >= 1 then
			info.Tag = "immune"
		elseif r > 0 then
			info.Tag = "adapt"
		end
		return amount * (1 - r)
	end
	entity.ModifyStun = function(duration, info)
		return duration * (1 - resist(b, info.Type))
	end
	entity.OnDamaged = function(amount, _info, attacker)
		local player = attacker and attacker.Player
		if player then
			b.Threat[player] = (b.Threat[player] or 0) + amount
			b.DamageBy[player] = (b.DamageBy[player] or 0) + amount
		end
		local frac = humanoid.Health / humanoid.MaxHealth
		if frac <= B.FinalPhaseAt then
			setPhase(b, 3)
		elseif frac <= B.EnrageAt then
			setPhase(b, 2)
		end
	end
	humanoid.Died:Connect(function()
		die(b)
	end)

	release(b)
	setAnim(b, "Move")
	FX.all("Announce", { title = B.Kanji, sub = B.Title .. " " .. B.Name, color = Palette.Wheel, time = 3 })

	task.spawn(function()
		while b.Alive do
			local dt = task.wait(0.1)
			if not b.Alive then
				break
			end
			if not model.Parent then
				-- Removed by something else (e.g. a map reset): free the altar.
				b.Alive = false
				Combat.unregister(entity)
				if b.OnEnded then
					b.OnEnded()
				end
				break
			end
			local ok, err = pcall(function(): string?
				step(b, dt)
				return nil
			end)
			if not ok then
				warn("[Mahoraga] AI error: " .. tostring(err))
			end
		end
		if current == b then
			current = nil
		end
	end)
	return true
end

return MahoragaBoss
