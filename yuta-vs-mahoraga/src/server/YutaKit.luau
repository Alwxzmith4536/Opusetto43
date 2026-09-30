--!strict
--[[
	Yuta Okkotsu's kit, server side. Every player gets it.

	Base techniques
	  M1  Katana combo (cursed-energy swordsmanship)
	  Q   Cursed Dash (dodge window)
	  Z   Rika: Partial Manifestation (arm smash)
	  X   Copy - Cursed Speech: "Don't move" (stun, throat backlash)
	  C   Copy - Cursed Speech: "Blast away" (cone launch, throat backlash)
	  V   Reverse Cursed Technique (heals self and allies)
	  F   Rika: Full Manifestation (damage up, auto claws, shield, unlocks R)
	  R   Pure Love: Jun'ai Ho (beam, needs Full Manifestation)
	  T   Domain Expansion: Authentic Mutual Love (sure-hit copied techniques)
	  G   Copy - Kenjaku's body transplant into Gojo's body (Six Eyes mode)
	  E   Cursed energy guard (hold)
	Six Eyes mode swaps Z/X/C for Blue, Red and Hollow Purple and adds Infinity.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Config = require(Shared:WaitForChild("Config"))
local Palette = require(Shared:WaitForChild("Palette"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Assets = Shared:WaitForChild("Assets")
local Katana = require(Assets:WaitForChild("Katana"))
local SixEyesLook = require(Assets:WaitForChild("SixEyesLook"))

local Combat = require(script.Parent.Combat)
local FX = require(script.Parent.FX)

local Y = Config.Yuta

type Payload = { [string]: any }

type State = {
	Player: Player,
	Character: Model?,
	Humanoid: Humanoid?,
	Root: BasePart?,
	Entity: Combat.Entity?,
	Tool: Tool?,
	Look: Model?,
	SetupFor: Model?,
	Cooldowns: { [string]: number },
	Combo: number,
	LastSlash: number,
	NextSlash: number,
	BusyUntil: number,
	SlowUntil: number,
	RikaUntil: number,
	NextClaw: number,
	SixEyesUntil: number,
	DomainUntil: number,
	DomainCenter: Vector3,
	Blocking: boolean,
	Serial: number,
}

local YutaKit = {}

local states: { [Player]: State } = {}
local handlers: { [string]: (State, Payload) -> () } = {}

-- Helpers ----------------------------------------------------------------------------

local function alive(state: State): boolean
	local e = state.Entity
	return e ~= nil and Combat.isAlive(e)
end

local function entityOf(state: State): Combat.Entity
	return state.Entity :: Combat.Entity
end

local function rootOf(state: State): BasePart
	return state.Root :: BasePart
end

local function nextCast(state: State): string
	state.Serial += 1
	return tostring(state.Player.UserId) .. ":" .. tostring(state.Serial)
end

local function rikaActive(state: State): boolean
	return state.RikaUntil > os.clock()
end

local function sixEyesActive(state: State): boolean
	return state.SixEyesUntil > os.clock()
end

local function inOwnDomain(state: State): boolean
	if state.DomainUntil <= os.clock() or not state.Root then
		return false
	end
	return (rootOf(state).Position - state.DomainCenter).Magnitude <= Y.Domain.Radius
end

local function damageMult(state: State): number
	return if rikaActive(state) then Y.RikaDamageBonus else 1
end

local function ready(state: State, id: string): boolean
	return os.clock() >= (state.Cooldowns[id] or 0)
end

local function startCooldown(state: State, id: string, seconds: number, fixed: boolean?)
	local duration = seconds
	if not fixed then
		if sixEyesActive(state) then
			duration *= Y.SixEyes.CooldownMultiplier
		end
		if inOwnDomain(state) then
			duration *= Y.Domain.CooldownMultiplier
		end
	end
	state.Cooldowns[id] = os.clock() + duration
	FX.to(state.Player, "Cooldown", { id = id, ends = workspace:GetServerTimeNow() + duration, duration = duration })
end

local function stunned(state: State): boolean
	local e = state.Entity
	return e ~= nil and e.StunnedUntil > os.clock()
end

local function canAct(state: State): boolean
	return alive(state) and not stunned(state) and os.clock() >= state.BusyUntil and not state.Blocking
end

local function canCast(state: State, id: string): boolean
	return canAct(state) and ready(state, id)
end

local function notify(state: State, text: string)
	FX.to(state.Player, "Notify", { text = text })
end

local function facing(state: State): CFrame
	local root = rootOf(state)
	return Util.facing(root.Position, root.CFrame.LookVector)
end

-- Flat frame at the root facing the cursor (the client also turns the character,
-- but the aim point is what the server trusts).
local function aimFacing(state: State, payload: Payload): CFrame
	local root = rootOf(state)
	local aim = payload.aim
	local dir = if typeof(aim) == "Vector3" then aim - root.Position else root.CFrame.LookVector
	return Util.facing(root.Position, Util.flatUnit(dir, root.CFrame.LookVector))
end

local function aimPoint(state: State, payload: Payload, range: number): Vector3
	local root = rootOf(state)
	local aim = payload.aim
	if typeof(aim) ~= "Vector3" then
		return root.Position + root.CFrame.LookVector * range
	end
	local offset = aim - root.Position
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	return root.Position + offset
end

-- Aim direction from the chest toward the cursor, with the pitch clamped.
local function aimDir(state: State, payload: Payload, maxPitch: number): Vector3
	local root = rootOf(state)
	local origin = root.Position + Vector3.new(0, 1.5, 0)
	local aim = payload.aim
	local dir = if typeof(aim) == "Vector3" then aim - origin else root.CFrame.LookVector
	if dir.Magnitude < 0.01 then
		dir = root.CFrame.LookVector
	end
	dir = dir.Unit
	local flatDir = Util.flatUnit(dir, root.CFrame.LookVector)
	local limit = math.rad(maxPitch)
	local pitch = math.clamp(math.asin(math.clamp(dir.Y, -1, 1)), -limit, limit)
	return (flatDir * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)).Unit
end

-- Cursed Speech strains the user's throat.
local function backlash(state: State, amount: number)
	local h = state.Humanoid
	if h and h.Health > amount + 1 then
		h.Health -= amount
		local pos = rootOf(state).Position + Vector3.new(0, 3.5, 0)
		FX.near(pos, 200, "Damage", { pos = pos, amount = amount, tag = "backlash" })
	end
end

-- M1: katana combo ----------------------------------------------------------------------

local function slash(state: State)
	local now = os.clock()
	if not canAct(state) or now < state.NextSlash then
		return
	end
	local K = Y.Katana
	if now - state.LastSlash > K.ComboReset then
		state.Combo = 0
	end
	state.Combo = state.Combo % #K.Damage + 1
	state.LastSlash = now
	local combo = state.Combo
	local finisher = combo == #K.Damage
	state.NextSlash = now + (if finisher then K.FinisherLag else K.Interval)

	local tool = state.Tool
	if tool and tool.Parent == state.Character then
		-- The default Animate script plays the tool slash/lunge animation for this value.
		local anim = Instance.new("StringValue")
		anim.Name = "toolanim"
		anim.Value = if finisher then "Lunge" else "Slash"
		anim.Parent = tool
		Debris:AddItem(anim, 1)
		local handle = tool:FindFirstChild("Handle")
		local trail = handle and handle:FindFirstChild("SwingTrail")
		if trail and trail:IsA("Trail") then
			trail.Enabled = true
			task.delay(0.25, function()
				trail.Enabled = false
			end)
		end
	end

	FX.all("Slash", { char = state.Character, combo = combo, cf = rootOf(state).CFrame })
	task.delay(0.07, function()
		if not alive(state) then
			return
		end
		local cf = facing(state) * CFrame.new(0, 0, -K.Reach / 2)
		local size = Vector3.new(if finisher then 11 else 9, 7, K.Reach)
		local look = cf.LookVector
		local mult = damageMult(state)
		local castId = nextCast(state)
		for _, e in Combat.query(entityOf(state), function(e)
			return Combat.inBox(e, cf, size)
		end) do
			Combat.damage(entityOf(state), e, K.Damage[combo] * mult, {
				Type = "Katana",
				CastId = castId,
				Knockback = if finisher then look * 55 + Vector3.new(0, 25, 0) else look * 8,
				KnockbackTime = if finisher then 0.25 else 0.1,
				Stun = if finisher then 0.5 else 0.35,
				Color = Palette.YutaEnergy,
			})
		end
	end)
end

-- Techniques ---------------------------------------------------------------------------

handlers.Dash = function(state, payload)
	if not alive(state) or stunned(state) or not ready(state, "Dash") then
		return
	end
	startCooldown(state, "Dash", Y.Dash.Cooldown, true)
	entityOf(state).DodgeUntil = os.clock() + Config.Player.DashIFrames
	local dir = payload.dir
	if typeof(dir) ~= "Vector3" or dir.Magnitude < 0.1 then
		dir = rootOf(state).CFrame.LookVector
	end
	FX.all("Dash", { char = state.Character, dir = Util.flatUnit(dir) })
end

handlers.RikaStrike = function(state, payload)
	if not canCast(state, "RikaStrike") then
		return
	end
	local cfg = Y.RikaStrike
	startCooldown(state, "RikaStrike", cfg.Cooldown)
	state.BusyUntil = os.clock() + 0.5
	local full = rikaActive(state)
	local scale = if full then 1.3 else 1
	local cf = aimFacing(state, payload)
	FX.all("RikaArm", { char = state.Character, cf = cf, full = full })
	task.delay(cfg.Windup, function()
		if not alive(state) then
			return
		end
		local center = (cf * CFrame.new(0, 0, -10 * scale)).Position
		local ground = Combat.groundAt(center)
		local hitCF = CFrame.new(center.X, ground.Y + 4, center.Z) * cf.Rotation
		local size = Vector3.new(12, 10, 16) * scale
		local castId = nextCast(state)
		for _, e in Combat.query(entityOf(state), function(e)
			return Combat.inBox(e, hitCF, size)
		end) do
			Combat.damage(entityOf(state), e, cfg.Damage * damageMult(state), {
				Type = "Rika",
				CastId = castId,
				Knockback = cf.LookVector * 30 + Vector3.new(0, 45, 0),
				KnockbackTime = 0.3,
				Stun = 0.6,
				Color = Palette.RikaAura,
			})
		end
		FX.all("Impact", { pos = ground, radius = 10 * scale, color = Palette.RikaAura, cracks = true })
		FX.shake(ground, 0.6, 0.35, 120)
	end)
end

handlers.DontMove = function(state, _payload)
	if not canCast(state, "DontMove") then
		return
	end
	local cfg = Y.DontMove
	startCooldown(state, "DontMove", cfg.Cooldown)
	state.BusyUntil = os.clock() + 0.4
	backlash(state, cfg.Backlash)
	FX.all("Speech", { char = state.Character, word = "DontMove", radius = cfg.Radius })
	task.delay(0.18, function()
		if not alive(state) then
			return
		end
		local center = rootOf(state).Position
		local castId = nextCast(state)
		for _, e in Combat.query(entityOf(state), function(e)
			return Combat.inSphere(e, center, cfg.Radius)
		end) do
			Combat.damage(entityOf(state), e, cfg.Damage * damageMult(state), {
				Type = "CursedSpeech",
				CastId = castId,
				Stun = if e.Kind == "Boss" then cfg.BossStun else cfg.Stun,
				Color = Palette.SpeechRing,
			})
		end
	end)
end

handlers.BlastAway = function(state, payload)
	if not canCast(state, "BlastAway") then
		return
	end
	local cfg = Y.BlastAway
	startCooldown(state, "BlastAway", cfg.Cooldown)
	state.BusyUntil = os.clock() + 0.45
	backlash(state, cfg.Backlash)
	local cf = aimFacing(state, payload)
	FX.all("Speech", { char = state.Character, word = "BlastAway", radius = cfg.Range, cone = cfg.ConeDegrees, cf = cf })
	task.delay(0.15, function()
		if not alive(state) then
			return
		end
		local castId = nextCast(state)
		for _, e in Combat.query(entityOf(state), function(e)
			return Combat.inArc(e, cf, cfg.Range, cfg.ConeDegrees, 8)
		end) do
			local away = Util.flatUnit(e.Root.Position - cf.Position, cf.LookVector)
			Combat.damage(entityOf(state), e, cfg.Damage * damageMult(state), {
				Type = "CursedSpeech",
				CastId = castId,
				Knockback = away * cfg.Knockback + Vector3.new(0, 30, 0),
				KnockbackTime = 0.3,
				Stun = if e.Kind == "Boss" then 0.4 else 0.8,
				Color = Palette.SpeechRing,
			})
		end
	end)
end

handlers.RCT = function(state, _payload)
	if not canCast(state, "RCT") then
		return
	end
	local cfg = Y.RCT
	startCooldown(state, "RCT", cfg.Cooldown)
	state.BusyUntil = os.clock() + 0.45
	local me = entityOf(state)
	me.StunnedUntil = 0
	local root = rootOf(state)
	local allies, allyModels = {}, {}
	for _, ally in Combat.alliesOf(me) do
		if (ally.Root.Position - root.Position).Magnitude <= cfg.AllyRadius then
			table.insert(allies, ally)
			table.insert(allyModels, ally.Model)
		end
	end
	FX.all("RCT", { char = state.Character, duration = cfg.Duration, allies = allyModels })
	task.spawn(function()
		local ticks = 4
		for _ = 1, ticks do
			if not alive(state) then
				return
			end
			Combat.heal(me, me.Humanoid.MaxHealth * cfg.SelfHeal / ticks)
			for _, ally in allies do
				Combat.heal(ally, ally.Humanoid.MaxHealth * cfg.AllyHeal / ticks)
			end
			task.wait(cfg.Duration / ticks)
		end
	end)
end

local function endRika(state: State)
	state.RikaUntil = 0
	local char = state.Character
	if char then
		char:SetAttribute("JJK_RikaFull", false)
	end
	FX.all("RikaVanish", { char = char })
	startCooldown(state, "FullManifestation", Y.FullManifestation.Cooldown, true)
end

handlers.FullManifestation = function(state, _payload)
	if rikaActive(state) or not canCast(state, "FullManifestation") then
		return
	end
	local cfg = Y.FullManifestation
	local now = os.clock()
	state.RikaUntil = now + cfg.Duration
	state.NextClaw = now + 1.5
	state.BusyUntil = now + 0.8
	local char = state.Character :: Model
	char:SetAttribute("JJK_RikaEnds", workspace:GetServerTimeNow() + cfg.Duration)
	char:SetAttribute("JJK_RikaFull", true)
	FX.all("RikaManifest", { char = char })
	FX.to(state.Player, "Announce", { title = "里香", sub = "Rika: Full Manifestation", color = Palette.RikaAura })
	FX.shake(rootOf(state).Position, 0.8, 0.6, 120)
end

-- While fully manifested, Rika claws at the nearest enemy on her own.
local function rikaClaw(state: State)
	local cfg = Y.FullManifestation
	local root = rootOf(state)
	local best: Combat.Entity? = nil
	local bestDist = cfg.ClawRange
	for _, e in Combat.enemiesOf(entityOf(state)) do
		local d = (e.Root.Position - root.Position).Magnitude - e.Radius
		if d < bestDist then
			best, bestDist = e, d
		end
	end
	if not best then
		state.NextClaw = os.clock() + 0.5
		return
	end
	local target: Combat.Entity = best
	state.NextClaw = os.clock() + cfg.ClawInterval
	local aim = target.Root.Position
	FX.all("RikaClaw", { char = state.Character, target = aim })
	task.delay(0.35, function()
		if alive(state) and Combat.isAlive(target) and Combat.inSphere(target, aim, 10) then
			Combat.damage(entityOf(state), target, cfg.ClawDamage * damageMult(state), {
				Type = "Rika",
				CastId = nextCast(state),
				Stun = 0.25,
				Color = Palette.RikaAura,
			})
		end
	end)
end

handlers.PureLove = function(state, payload)
	if not alive(state) then
		return
	end
	if not rikaActive(state) then
		notify(state, "Pure Love needs Rika's Full Manifestation (F).")
		return
	end
	if not canCast(state, "PureLove") then
		return
	end
	local cfg = Y.PureLove
	startCooldown(state, "PureLove", cfg.Cooldown)
	local total = cfg.Charge + cfg.Ticks * cfg.TickInterval + 0.3
	state.BusyUntil = os.clock() + total
	state.SlowUntil = os.clock() + total
	local dir = aimDir(state, payload, 20)
	FX.all("PureLoveCharge", { char = state.Character, time = cfg.Charge, dir = dir })
	FX.to(state.Player, "Announce", { title = "純愛砲", sub = "Pure Love: Jun'ai Ho", color = Palette.PureLove })
	task.delay(cfg.Charge, function()
		if not alive(state) then
			return
		end
		local origin = rootOf(state).Position + Vector3.new(0, 1.5, 0) + dir * 5
		local cf = CFrame.lookAt(origin, origin + dir)
		FX.all("PureLoveBeam", { cf = cf, length = cfg.Length, width = cfg.Width, duration = cfg.Ticks * cfg.TickInterval + 0.3 })
		FX.shake(origin, 1.3, 1.1, 260)
		local castId = nextCast(state)
		local box = cf * CFrame.new(0, 0, -cfg.Length / 2)
		local size = Vector3.new(cfg.Width, cfg.Width, cfg.Length)
		for _ = 1, cfg.Ticks do
			if not alive(state) then
				return
			end
			for _, e in Combat.query(entityOf(state), function(e)
				return Combat.inBox(e, box, size)
			end) do
				Combat.damage(entityOf(state), e, cfg.TickDamage * damageMult(state), {
					Type = "PureLove",
					CastId = castId,
					Knockback = dir * 40,
					KnockbackTime = 0.15,
					Stun = 0.25,
					Color = Palette.PureLove,
				})
			end
			task.wait(cfg.TickInterval)
		end
	end)
end

handlers.Domain = function(state, _payload)
	if state.DomainUntil > os.clock() or not canCast(state, "Domain") then
		return
	end
	local cfg = Y.Domain
	startCooldown(state, "Domain", cfg.Cooldown, true)
	state.BusyUntil = os.clock() + cfg.CastTime
	state.SlowUntil = os.clock() + cfg.CastTime
	FX.all("DomainCast", { char = state.Character, time = cfg.CastTime })
	FX.all("Announce", { title = "領域展開", sub = "Domain Expansion", color = Palette.DomainSky, time = cfg.CastTime })
	task.delay(cfg.CastTime, function()
		if not alive(state) then
			return
		end
		local center = Combat.groundAt(rootOf(state).Position)
		local id = "domain-" .. nextCast(state)
		state.DomainCenter = center
		state.DomainUntil = os.clock() + cfg.Duration
		FX.all("DomainExpand", { id = id, center = center, radius = cfg.Radius, duration = cfg.Duration, char = state.Character })
		FX.all("Announce", { title = "真贋相愛", sub = "Domain Expansion: Authentic Mutual Love", color = Palette.PureLove, time = 2.6 })
		FX.shake(center, 1.0, 1.0, 220)

		-- Anyone caught inside when the domain closes cannot walk out of it.
		for _, e in Combat.query(entityOf(state), function(e)
			return Combat.inSphere(e, center, cfg.Radius)
		end) do
			local controller = e.Controller
			if controller then
				controller:Confine(center, cfg.Radius - 8, cfg.Duration)
			end
		end

		-- Sure-hit: every tick each enemy inside is struck by one of the copied techniques
		-- held in the swords (katana rain, Cursed Speech, or Rika).
		local kinds = { "Swords", "Speech", "Rika" }
		local rng = Random.new()
		local elapsed = 0
		while elapsed < cfg.Duration and alive(state) do
			task.wait(cfg.TickInterval)
			elapsed += cfg.TickInterval
			if not alive(state) then
				break
			end
			for _, e in Combat.query(entityOf(state), function(e)
				return Combat.inSphere(e, center, cfg.Radius)
			end) do
				local kind = kinds[rng:NextInteger(1, #kinds)]
				local info: Combat.HitInfo = { Type = "Domain", CastId = nextCast(state), Color = Palette.PureLove }
				local amount = cfg.SwordDamage
				if kind == "Speech" then
					amount = cfg.SpeechDamage
					info.Stun = cfg.SpeechStun
				elseif kind == "Rika" then
					amount = cfg.RikaDamage
				end
				FX.all("DomainHit", { id = id, kind = kind, pos = e.Root.Position, model = e.Model })
				Combat.damage(entityOf(state), e, amount * damageMult(state), info)
			end
		end
		state.DomainUntil = 0
		FX.all("DomainEnd", { id = id })
	end)
end

local HIDDEN_ACCESSORIES = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Unknown] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
}

local function setHeadAccessoriesHidden(char: Model, hidden: boolean)
	for _, accessory in char:GetChildren() do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				if hidden and HIDDEN_ACCESSORIES[accessory.AccessoryType] then
					if handle:GetAttribute("JJK_Transparency") == nil then
						handle:SetAttribute("JJK_Transparency", handle.Transparency)
					end
					handle.Transparency = 1
				elseif not hidden then
					local original = handle:GetAttribute("JJK_Transparency")
					if typeof(original) == "number" then
						handle.Transparency = original
						handle:SetAttribute("JJK_Transparency", nil)
					end
				end
			end
		end
	end
end

local function endSixEyes(state: State)
	state.SixEyesUntil = 0
	local char = state.Character
	if char then
		char:SetAttribute("JJK_Mode", "Base")
		setHeadAccessoriesHidden(char, false)
	end
	if state.Look then
		state.Look:Destroy()
		state.Look = nil
	end
	FX.all("SixEyesEnd", { char = char })
	startCooldown(state, "SixEyes", Y.SixEyes.Cooldown, true)
end

handlers.SixEyes = function(state, _payload)
	if sixEyesActive(state) or not canCast(state, "SixEyes") then
		return
	end
	local cfg = Y.SixEyes
	state.BusyUntil = os.clock() + cfg.CastTime
	state.SlowUntil = os.clock() + cfg.CastTime
	FX.all("SixEyesCast", { char = state.Character, time = cfg.CastTime })
	FX.to(state.Player, "Announce", { title = "六眼", sub = "Copy: Body Transplant - Six Eyes & Limitless", color = Palette.SixEyes })
	task.delay(cfg.CastTime, function()
		if not alive(state) then
			return
		end
		local char = state.Character :: Model
		state.SixEyesUntil = os.clock() + cfg.Duration
		char:SetAttribute("JJK_SixEyesEnds", workspace:GetServerTimeNow() + cfg.Duration)
		char:SetAttribute("JJK_Mode", "SixEyes")
		local head = char:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			local size = head.Size
			local visual = Vector3.new(math.clamp(size.X, 0.9, 1.8), math.clamp(size.Y, 0.9, 1.8), math.clamp(size.Z, 0.9, 1.8))
			if (state.Humanoid :: Humanoid).RigType == Enum.HumanoidRigType.R6 then
				visual = Vector3.new(1.25, 1.25, 1.25)
			end
			local look = SixEyesLook.build(head, visual)
			look.Parent = char
			state.Look = look
			setHeadAccessoriesHidden(char, true)
		end
		FX.all("SixEyesAwaken", { char = char })
	end)
end

handlers.Blue = function(state, payload)
	if not sixEyesActive(state) or not canCast(state, "Blue") then
		return
	end
	local cfg = Y.Blue
	startCooldown(state, "Blue", cfg.Cooldown)
	state.BusyUntil = os.clock() + 0.35
	local point = aimPoint(state, payload, cfg.Range)
	local pos = Combat.groundAt(point) + Vector3.new(0, 5, 0)
	FX.all("Blue", { pos = pos, radius = cfg.Radius, duration = cfg.Duration })
	task.spawn(function()
		local castId = nextCast(state)
		local t = 0
		while t < cfg.Duration and alive(state) do
			for _, e in Combat.query(entityOf(state), function(e)
				return Combat.inSphere(e, pos, cfg.Radius)
			end) do
				local toCenter = pos - e.Root.Position
				Combat.damage(entityOf(state), e, cfg.TickDamage * damageMult(state), {
					Type = "Blue",
					CastId = castId,
					Knockback = if toCenter.Magnitude > 2 then toCenter.Unit * cfg.Pull else nil,
					KnockbackTime = cfg.TickInterval,
					Color = Palette.Blue,
				})
			end
			task.wait(cfg.TickInterval)
			t += cfg.TickInterval
		end
	end)
end

handlers.Red = function(state, payload)
	if not sixEyesActive(state) or not canCast(state, "Red") then
		return
	end
	local cfg = Y.Red
	startCooldown(state, "Red", cfg.Cooldown)
	state.BusyUntil = os.clock() + 0.4
	local dir = aimDir(state, payload, 35)
	local origin = rootOf(state).Position + Vector3.new(0, 1.5, 0) + dir * 2.5
	local id = "red-" .. nextCast(state)
	FX.all("RedFire", { id = id, origin = origin, dir = dir, speed = cfg.Speed, range = cfg.Range })
	task.spawn(function()
		local pos = origin
		local traveled = 0
		local hitPos: Vector3? = nil
		while traveled < cfg.Range do
			local dt = task.wait()
			local step = math.min(cfg.Speed * dt, cfg.Range - traveled)
			local ray = Combat.worldRaycast(pos, dir * step)
			local nextPos = pos + dir * step
			for _, e in Combat.enemiesOf(entityOf(state)) do
				if Combat.inSphere(e, nextPos, cfg.HitRadius) then
					hitPos = nextPos
					break
				end
			end
			if hitPos then
				break
			end
			if ray then
				hitPos = ray.Position
				break
			end
			pos = nextPos
			traveled += step
		end
		local blast = hitPos or pos
		FX.all("RedBoom", { id = id, pos = blast, radius = cfg.BlastRadius })
		FX.shake(blast, 0.9, 0.5, 160)
		if not alive(state) then
			return
		end
		local castId = nextCast(state)
		for _, e in Combat.query(entityOf(state), function(e)
			return Combat.inSphere(e, blast, cfg.BlastRadius)
		end) do
			local away = Util.flatUnit(e.Root.Position - blast, dir)
			Combat.damage(entityOf(state), e, cfg.Damage * damageMult(state), {
				Type = "Red",
				CastId = castId,
				Knockback = away * cfg.Knockback + Vector3.new(0, 35, 0),
				KnockbackTime = 0.3,
				Stun = 0.5,
				Color = Palette.Red,
			})
		end
	end)
end

handlers.HollowPurple = function(state, payload)
	if not sixEyesActive(state) or not canCast(state, "HollowPurple") then
		return
	end
	local cfg = Y.HollowPurple
	startCooldown(state, "HollowPurple", cfg.Cooldown)
	state.BusyUntil = os.clock() + cfg.Charge + 0.5
	state.SlowUntil = os.clock() + cfg.Charge + 0.5
	FX.all("PurpleCharge", { char = state.Character, time = cfg.Charge })
	FX.all("Announce", { title = "虚式「茈」", sub = "Hollow Technique: Purple", color = Palette.Purple, time = 2 })
	task.delay(cfg.Charge, function()
		if not alive(state) then
			return
		end
		local dir = aimDir(state, payload, 25)
		local origin = rootOf(state).Position + Vector3.new(0, 2, 0) + dir * 4
		local id = "purple-" .. nextCast(state)
		FX.all("PurpleFire", { id = id, origin = origin, dir = dir, speed = cfg.Speed, range = cfg.Range, radius = cfg.Radius })
		FX.shake(origin, 1.6, 1.2, 300)
		local castId = nextCast(state)
		local hit: { [Combat.Entity]: boolean } = {}
		local pos = origin
		local traveled = 0
		while traveled < cfg.Range do
			local dt = task.wait()
			local step = cfg.Speed * dt
			pos += dir * step
			traveled += step
			if not alive(state) then
				continue
			end
			for _, e in Combat.query(entityOf(state), function(e)
				return Combat.inSphere(e, pos, cfg.Radius)
			end) do
				if not hit[e] then
					hit[e] = true
					Combat.damage(entityOf(state), e, cfg.Damage * damageMult(state), {
						Type = "HollowPurple",
						CastId = castId,
						Knockback = dir * 90 + Vector3.new(0, 40, 0),
						KnockbackTime = 0.35,
						Stun = 0.8,
						Color = Palette.Purple,
					})
				end
			end
		end
	end)
end

handlers.Block = function(state, payload)
	local on = payload.on == true
	if on and (not alive(state) or stunned(state) or os.clock() < state.BusyUntil) then
		on = false
	end
	state.Blocking = on
	local e = state.Entity
	if e then
		e.Blocking = on
	end
	if state.Character then
		state.Character:SetAttribute("JJK_Blocking", on)
	end
end

-- Character lifecycle ------------------------------------------------------------------

local function setupCharacter(state: State, char: Model)
	if state.SetupFor == char then
		return -- CharacterAdded and the initial check can both fire for the first character
	end
	state.SetupFor = char
	local humanoid = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end
	if state.Player.Character ~= char then
		return
	end

	state.Character = char
	state.Humanoid = humanoid
	state.Root = root
	state.Cooldowns = {}
	state.Combo = 0
	state.NextSlash = 0
	state.BusyUntil = 0
	state.SlowUntil = 0
	state.RikaUntil = 0
	state.SixEyesUntil = 0
	state.DomainUntil = 0
	state.Blocking = false
	state.Look = nil

	humanoid.MaxHealth = Config.Player.MaxHealth
	humanoid.Health = Config.Player.MaxHealth
	humanoid.WalkSpeed = Config.Player.WalkSpeed
	char:SetAttribute("JJK_Yuta", true)
	char:SetAttribute("JJK_Mode", "Base")
	char:SetAttribute("JJK_RikaFull", false)
	char:SetAttribute("JJK_Blocking", false)

	local entity = Combat.register(char, humanoid, root, "Player", state.Player)
	entity.ModifyIncoming = function(amount, info, attacker)
		local dmg = amount
		if rikaActive(state) then
			dmg *= 1 - Y.FullManifestation.Protection
		end
		if sixEyesActive(state) then
			-- Infinity stops most damage, but Mahoraga adapts to it hit by hit.
			local controller = attacker and attacker.Controller
			local adapted = if controller then controller:AdaptFraction("Infinity") else 0
			local reduction = Y.SixEyes.InfinityReduction * (1 - adapted)
			if reduction > 0.01 then
				dmg *= 1 - reduction
				info.Tag = "infinity"
			end
			FX.all("Infinity", { char = char, adapted = adapted })
			if controller then
				controller:RegisterCast("Infinity", "infinity:" .. tostring(os.clock()))
			end
		end
		return dmg
	end
	state.Entity = entity

	humanoid.Died:Connect(function()
		if state.Character ~= char then
			return
		end
		Combat.unregister(entity)
		if state.RikaUntil > 0 then
			char:SetAttribute("JJK_RikaFull", false)
			FX.all("RikaVanish", { char = char })
		end
		state.RikaUntil = 0
		state.SixEyesUntil = 0
		state.DomainUntil = 0
	end)

	-- The Backpack is recreated on every spawn; make sure we use this life's one.
	local backpack = state.Player:FindFirstChildOfClass("Backpack") or state.Player:WaitForChild("Backpack", 5)
	if backpack and state.Player.Character == char then
		local tool = Katana.buildTool()
		tool.Parent = backpack
		state.Tool = tool
		tool.Activated:Connect(function()
			slash(state)
		end)
		task.defer(function()
			if humanoid.Parent and tool.Parent == backpack then
				humanoid:EquipTool(tool)
			end
		end)
	end
	FX.to(state.Player, "Reset", {})
end

local function onPlayerAdded(player: Player)
	local state: State = {
		Player = player,
		Cooldowns = {},
		Combo = 0,
		LastSlash = 0,
		NextSlash = 0,
		BusyUntil = 0,
		SlowUntil = 0,
		RikaUntil = 0,
		NextClaw = 0,
		SixEyesUntil = 0,
		DomainUntil = 0,
		DomainCenter = Vector3.zero,
		Blocking = false,
		Serial = 0,
	}
	states[player] = state
	player.CharacterAdded:Connect(function(char)
		setupCharacter(state, char)
	end)
	if player.Character then
		task.spawn(setupCharacter, state, player.Character)
	end
end

-- Timers and movement, ten times a second.
local function update()
	local now = os.clock()
	for _, state in states do
		if not alive(state) then
			continue
		end
		if state.RikaUntil > 0 and now >= state.RikaUntil then
			endRika(state)
		end
		if state.SixEyesUntil > 0 and now >= state.SixEyesUntil then
			endSixEyes(state)
		end
		if rikaActive(state) and now >= state.NextClaw then
			rikaClaw(state)
		end

		local humanoid = state.Humanoid :: Humanoid
		local isStunned = stunned(state)
		local speed = Config.Player.WalkSpeed
		if isStunned then
			speed = 0
		elseif state.SlowUntil > now then
			speed = Config.Player.CastWalkSpeed
		elseif state.Blocking then
			speed = Config.Player.BlockWalkSpeed
		end
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
		local jumpPower = if isStunned then 0 else Config.Player.JumpPower
		if humanoid.JumpPower ~= jumpPower then
			humanoid.JumpPower = jumpPower
			humanoid.JumpHeight = if isStunned then 0 else Config.Player.JumpHeight
		end
		local char = state.Character :: Model
		if char:GetAttribute("JJK_Stunned") ~= isStunned then
			char:SetAttribute("JJK_Stunned", isStunned)
		end
	end
end

function YutaKit.start()
	local remote = Net.event("Ability")
	remote.OnServerEvent:Connect(function(player: Player, id: any, payload: any)
		if typeof(id) ~= "string" or handlers[id] == nil then
			return
		end
		local state = states[player]
		if not state or not alive(state) then
			return
		end
		local mode = if sixEyesActive(state) then "SixEyes" else "Base"
		if not Abilities.inMode(mode, id) then
			return
		end
		handlers[id](state, if typeof(payload) == "table" then payload else {})
	end)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			update()
		end
	end)
end

return YutaKit
