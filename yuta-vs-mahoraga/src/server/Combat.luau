--!strict
--[[
	Server combat core: who can hit whom, hit shapes, damage, stuns, knockback,
	blocking and damage numbers.

	No instant kills from the boss: every Mahoraga hit on a player is capped at
	Config.Boss.MaxHitFraction of the player's max health, and each hit grants a
	short immunity window (Config.Boss.HitInvulnerability) so multi-hit attacks
	cannot stack into a one-shot.
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Config = require(Shared:WaitForChild("Config"))
local Palette = require(Shared:WaitForChild("Palette"))
local FX = require(script.Parent.FX)

export type Kind = "Player" | "Boss" | "Dummy"

export type HitInfo = {
	Type: string, -- adaptation category, e.g. "Katana"
	CastId: string?, -- shared by every tick of one cast
	Knockback: Vector3?,
	KnockbackTime: number?,
	Stun: number?,
	Unblockable: boolean?,
	Color: Color3?,
	Tag: string?, -- set by ModifyIncoming: "adapt", "immune", "infinity"
}

export type Entity = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Kind: Kind,
	Player: Player?,
	Radius: number,
	HalfHeight: number,
	StunnedUntil: number,
	ImmuneUntil: number,
	DodgeUntil: number,
	Blocking: boolean,
	ModifyIncoming: ((amount: number, info: HitInfo, attacker: Entity?) -> number)?,
	ModifyStun: ((duration: number, info: HitInfo) -> number)?,
	OnDamaged: ((amount: number, info: HitInfo, attacker: Entity?) -> ())?,
	Controller: any?, -- the boss object, for adaptation queries
}

local Combat = {}

local entities: { [Model]: Entity } = {}

function Combat.register(model: Model, humanoid: Humanoid, root: BasePart, kind: Kind, player: Player?): Entity
	local entity: Entity = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Kind = kind,
		Player = player,
		Radius = (model:GetAttribute("JJK_HitRadius") :: number?) or 1.8,
		HalfHeight = (model:GetAttribute("JJK_HitHalfHeight") :: number?) or 3,
		StunnedUntil = 0,
		ImmuneUntil = 0,
		DodgeUntil = 0,
		Blocking = false,
	}
	entities[model] = entity
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil and entities[model] == entity then
			entities[model] = nil
		end
	end)
	return entity
end

function Combat.unregister(entity: Entity)
	if entities[entity.Model] == entity then
		entities[entity.Model] = nil
	end
end

function Combat.get(model: Model): Entity?
	return entities[model]
end

function Combat.isAlive(e: Entity): boolean
	return entities[e.Model] == e and e.Humanoid.Health > 0 and e.Model.Parent ~= nil and e.Root.Parent ~= nil
end

function Combat.isEnemy(a: Entity, b: Entity): boolean
	if a == b then
		return false
	end
	if a.Kind == "Player" then
		if b.Kind == "Player" then
			return Config.Rules.PvP
		end
		return true
	elseif a.Kind == "Boss" then
		return b.Kind == "Player"
	end
	return false
end

function Combat.enemiesOf(attacker: Entity): { Entity }
	local list = {}
	for _, e in entities do
		if Combat.isEnemy(attacker, e) and Combat.isAlive(e) then
			table.insert(list, e)
		end
	end
	return list
end

function Combat.alliesOf(entity: Entity): { Entity }
	local list = {}
	for _, e in entities do
		if e ~= entity and e.Kind == entity.Kind and Combat.isAlive(e) then
			table.insert(list, e)
		end
	end
	return list
end

function Combat.query(attacker: Entity, test: (Entity) -> boolean): { Entity }
	local list = {}
	for _, e in Combat.enemiesOf(attacker) do
		if test(e) then
			table.insert(list, e)
		end
	end
	return list
end

-- Hit shapes treat every target as an upright cylinder (Radius, HalfHeight) around its root.

function Combat.inBox(e: Entity, cf: CFrame, size: Vector3): boolean
	local p = cf:PointToObjectSpace(e.Root.Position)
	return math.abs(p.X) <= size.X / 2 + e.Radius and math.abs(p.Y) <= size.Y / 2 + e.HalfHeight and math.abs(p.Z) <= size.Z / 2 + e.Radius
end

function Combat.inSphere(e: Entity, center: Vector3, radius: number): boolean
	local d = e.Root.Position - center
	local flat = Vector3.new(d.X, 0, d.Z).Magnitude
	return flat <= radius + e.Radius and math.abs(d.Y) <= radius + e.HalfHeight
end

-- Pie slice centred on cf's look vector; `height` is how far above/below cf it reaches.
function Combat.inArc(e: Entity, cf: CFrame, radius: number, arcDegrees: number, height: number): boolean
	local p = cf:PointToObjectSpace(e.Root.Position)
	if math.abs(p.Y) > height + e.HalfHeight then
		return false
	end
	local flat = Vector3.new(p.X, 0, p.Z)
	local dist = flat.Magnitude
	if dist > radius + e.Radius then
		return false
	end
	if dist <= e.Radius + 1 then
		return true
	end
	local angle = math.deg(math.atan2(p.X, -p.Z))
	local slack = math.deg(math.atan(e.Radius / dist))
	return math.abs(angle) <= arcDegrees / 2 + slack
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

local function refreshGroundFilter()
	local list: { Instance } = {}
	for model in entities do
		table.insert(list, model)
	end
	local fxFolder = workspace:FindFirstChild("JJK_FX")
	if fxFolder then
		table.insert(list, fxFolder)
	end
	groundParams.FilterDescendantsInstances = list
end

-- Point on the ground below `pos` (ignores characters and bosses).
function Combat.groundAt(pos: Vector3): Vector3
	refreshGroundFilter()
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -120, 0), groundParams)
	if hit then
		return hit.Position
	end
	return Vector3.new(pos.X, Config.World.ArenaCenter.Y, pos.Z)
end

-- Height of the root above the ground; used for "jump over the shockwave" checks.
function Combat.heightAboveGround(e: Entity): number
	return e.Root.Position.Y - Combat.groundAt(e.Root.Position).Y
end

function Combat.worldRaycast(origin: Vector3, direction: Vector3): RaycastResult?
	refreshGroundFilter()
	return workspace:Raycast(origin, direction, groundParams)
end

function Combat.knockback(target: Entity, velocity: Vector3, duration: number)
	if target.Kind == "Boss" or target.Root.Anchored then
		return
	end
	local root = target.Root
	for _, child in root:GetChildren() do
		if child.Name == "JJK_Knockback" then
			child:Destroy()
		end
	end
	local attachment = root:FindFirstChild("JJK_KnockbackAttachment") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "JJK_KnockbackAttachment"
		a.Parent = root
		attachment = a
	end
	local force = Instance.new("LinearVelocity")
	force.Name = "JJK_Knockback"
	force.Attachment0 = attachment
	force.RelativeTo = Enum.ActuatorRelativeTo.World
	force.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	force.MaxForce = 1e6
	force.VectorVelocity = velocity
	force.Parent = root
	Debris:AddItem(force, duration)
end

function Combat.stun(target: Entity, duration: number, info: HitInfo?)
	if target.ModifyStun and info then
		duration = target.ModifyStun(duration, info)
	end
	if duration <= 0.05 then
		return
	end
	target.StunnedUntil = math.max(target.StunnedUntil, os.clock() + duration)
	FX.all("Stun", { model = target.Model, duration = duration })
end

local function numberFx(target: Entity, amount: number, tag: string?, color: Color3?)
	local pos = target.Root.Position + Vector3.new(0, target.HalfHeight * 0.6 + 1.5, 0)
	FX.near(pos, 250, "Damage", { pos = pos, amount = amount, tag = tag, color = color })
end

-- Applies a hit. Returns the damage actually dealt.
function Combat.damage(attacker: Entity?, target: Entity, amount: number, info: HitInfo): number
	if not Combat.isAlive(target) then
		return 0
	end
	local now = os.clock()
	local fromBoss = attacker ~= nil and attacker.Kind == "Boss" and target.Kind == "Player"

	if fromBoss and target.DodgeUntil > now then
		numberFx(target, 0, "dodge")
		return 0
	end
	if fromBoss and target.ImmuneUntil > now then
		return 0
	end

	local dmg = amount
	if target.ModifyIncoming then
		dmg = target.ModifyIncoming(dmg, info, attacker)
	end
	if target.Blocking and not info.Unblockable then
		dmg *= 1 - Config.Player.BlockReduction
		info.Tag = info.Tag or "block"
	end
	if fromBoss then
		dmg = math.min(dmg, target.Humanoid.MaxHealth * Config.Boss.MaxHitFraction)
		target.ImmuneUntil = now + Config.Boss.HitInvulnerability
	end
	dmg = math.max(0, dmg)

	if dmg > 0 then
		target.Humanoid:TakeDamage(dmg)
	end
	local stillResisted = info.Tag == "immune"
	if not stillResisted then
		if info.Knockback then
			Combat.knockback(target, info.Knockback, info.KnockbackTime or 0.2)
		end
		if info.Stun then
			Combat.stun(target, info.Stun, info)
		end
	end
	if target.OnDamaged then
		target.OnDamaged(dmg, info, attacker)
	end

	numberFx(target, dmg, info.Tag or (if target.Kind == "Player" then "player" else nil), info.Color)
	if dmg > 0 then
		FX.near(target.Root.Position, 250, "Hit", { pos = target.Root.Position, color = info.Color or Palette.YutaEnergy, big = dmg >= 40 })
	end
	return dmg
end

function Combat.heal(target: Entity, amount: number)
	if not Combat.isAlive(target) then
		return
	end
	local h = target.Humanoid
	local before = h.Health
	h.Health = math.min(h.MaxHealth, h.Health + amount)
	local healed = h.Health - before
	if healed > 0.5 then
		numberFx(target, healed, "heal")
	end
end

return Combat
