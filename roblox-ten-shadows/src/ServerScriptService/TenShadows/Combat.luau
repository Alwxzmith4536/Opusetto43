-- Server combat core: remotes, targeting shapes, damage (with the anti one-shot rules),
-- knockback, stuns and FX broadcasting.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("TenShadows")
local Config = require(Shared.Config)
local DamageRules = require(Shared.DamageRules)

local Combat = {}

Combat.Handlers = {} -- [model] = function(amount, damageType, info) -> dealt  (custom damage, e.g. Mahoraga)
Combat.AreaHitHooks = {} -- functions(shape, attackerFaction) called when an enemy attack covers an area
Combat.Decoys = {} -- { Pos, Owner, Until } rabbits that Mahoraga chases instead of players
Combat.SlowZones = {} -- { Center, Radius, Factor, Until, Owner }
Combat.Npcs = {} -- [model] = true, registered non-player combatants

---------------------------------------------------------------- remotes

local remotes = ReplicatedStorage:FindFirstChild("TenShadowsRemotes") or Instance.new("Folder")
remotes.Name = "TenShadowsRemotes"
remotes.Parent = ReplicatedStorage

local function remote(name)
	local r = remotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

Combat.AbilityRemote = remote("Ability") -- client -> server: (abilityName, aimPosition, extra)
Combat.FXRemote = remote("FX") -- server -> client: (effectName, params)

function Combat.FX(name, params)
	Combat.FXRemote:FireAllClients(name, params)
end

function Combat.FXTo(player, name, params)
	Combat.FXRemote:FireClient(player, name, params)
end

function Combat.Notice(text, color, player)
	local params = { Text = text, Color = color }
	if player then
		Combat.FXTo(player, "UI_Notice", params)
	else
		Combat.FX("UI_Notice", params)
	end
end

---------------------------------------------------------------- combatants

function Combat.Register(model)
	Combat.Npcs[model] = true
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			Combat.Npcs[model] = nil
			Combat.Handlers[model] = nil
		end
	end)
end

function Combat.GetRoot(model)
	return model and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
end

function Combat.IsAlive(model)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and model.Parent ~= nil
end

function Combat.AllCombatants()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and Combat.IsAlive(char) and Combat.GetRoot(char) then
			table.insert(list, char)
		end
	end
	for model in pairs(Combat.Npcs) do
		if Combat.IsAlive(model) and Combat.GetRoot(model) then
			table.insert(list, model)
		end
	end
	return list
end

function Combat.IsEnemy(attackerFaction, attackerModel, target)
	if target == attackerModel then
		return false
	end
	local faction = target:GetAttribute("Faction")
	if attackerFaction == "Player" then
		return faction == "Curse" or (Config.PvP and faction == "Player")
	elseif attackerFaction == "Curse" then
		return faction == "Player"
	end
	return false
end

---------------------------------------------------------------- shapes

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end
Combat.Flat = flat

local function segmentDistance(p, a, b)
	local ab = flat(b - a)
	local ap = flat(p - a)
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp(ap:Dot(ab) / len2, 0, 1) or 0
	return (ap - ab * t).Magnitude, t
end
Combat.SegmentDistance = segmentDistance

-- shape = { Type = "Circle", Pos, Radius } | { Type = "Cone", Origin, Dir, Range, Angle }
--       | { Type = "Line", From, To, Width }
function Combat.InShape(pos, shape, pad)
	pad = pad or 0
	if shape.Type == "Circle" then
		return flat(pos - shape.Pos).Magnitude <= shape.Radius + pad and math.abs(pos.Y - shape.Pos.Y) < shape.Radius + 12
	elseif shape.Type == "Cone" then
		local offset = flat(pos - shape.Origin)
		local dist = offset.Magnitude
		if dist > shape.Range + pad then
			return false
		end
		if dist < 3 + pad then
			return true
		end
		local dir = flat(shape.Dir)
		if dir.Magnitude < 0.01 then
			return true
		end
		local angle = math.deg(math.acos(math.clamp(offset.Unit:Dot(dir.Unit), -1, 1)))
		return angle <= shape.Angle / 2 + math.deg(math.atan2(pad, math.max(dist, 1)))
	elseif shape.Type == "Line" then
		local d = segmentDistance(pos, shape.From, shape.To)
		return d <= shape.Width / 2 + pad
	end
	return false
end

-- Returns every enemy model whose root is inside the shape.
function Combat.GetTargets(attackerModel, attackerFaction, shape)
	local found = {}
	for _, model in ipairs(Combat.AllCombatants()) do
		if Combat.IsEnemy(attackerFaction, attackerModel, model) then
			local root = Combat.GetRoot(model)
			local pad = model:GetAttribute("HitRadius") or 2
			if Combat.InShape(root.Position, shape, pad) then
				table.insert(found, model)
			end
		end
	end
	if attackerFaction == "Curse" then
		for _, hook in ipairs(Combat.AreaHitHooks) do
			hook(shape)
		end
	end
	return found
end

-- Picks the enemy the player most likely meant: close to the mouse, else nearest in front.
function Combat.ResolveTarget(character, aimPos, range)
	local root = Combat.GetRoot(character)
	if not root then
		return nil, aimPos
	end
	local best, bestScore = nil, math.huge
	for _, model in ipairs(Combat.AllCombatants()) do
		if Combat.IsEnemy("Player", character, model) then
			local pos = Combat.GetRoot(model).Position
			local fromMe = flat(pos - root.Position).Magnitude
			if fromMe <= range then
				local fromAim = flat(pos - aimPos).Magnitude
				local score = fromAim < 14 and fromAim or 1000 + fromMe
				if score < bestScore then
					best, bestScore = model, score
				end
			end
		end
	end
	if best then
		return best, Combat.GetRoot(best).Position
	end
	local offset = flat(aimPos - root.Position)
	if offset.Magnitude > range then
		offset = offset.Unit * range
	end
	return nil, Vector3.new(root.Position.X + offset.X, root.Position.Y - 3, root.Position.Z + offset.Z)
end

---------------------------------------------------------------- effects on targets

function Combat.IsStunned(model)
	return (model:GetAttribute("StunnedUntil") or 0) > time()
end

function Combat.Stun(model, seconds)
	local untilTime = time() + seconds
	if (model:GetAttribute("StunnedUntil") or 0) < untilTime then
		model:SetAttribute("StunnedUntil", untilTime)
	end
end

function Combat.Knockback(model, velocity)
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		Combat.FXTo(player, "Knockback", { Velocity = velocity })
		return
	end
	local root = Combat.GetRoot(model)
	if root and not root.Anchored then
		local resist = model:GetAttribute("KnockbackResist") or 1
		root.AssemblyLinearVelocity += velocity * resist
	end
end

function Combat.GetSlowFactor(pos, victimFaction)
	local factor = 1
	local now = time()
	for i = #Combat.SlowZones, 1, -1 do
		local z = Combat.SlowZones[i]
		if now > z.Until then
			table.remove(Combat.SlowZones, i)
		elseif victimFaction == "Curse" and flat(pos - z.Center).Magnitude <= z.Radius then
			factor = math.min(factor, z.Factor)
		end
	end
	return factor
end

---------------------------------------------------------------- damage

-- info = { Source = Player?, SourceModel = Model?, Knockback = Vector3?, Stun = number?, Silent = bool? }
function Combat.Damage(target, amount, damageType, info)
	info = info or {}
	local humanoid = target and target:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end
	local root = Combat.GetRoot(target)
	local now = time()
	local dealt
	local note = nil

	local handler = Combat.Handlers[target]
	if handler then
		dealt, note = handler(amount, damageType, info)
	elseif Players:GetPlayerFromCharacter(target) then
		local reduction = 0
		if (target:GetAttribute("ReductionUntil") or 0) > now then
			reduction = target:GetAttribute("Reduction") or 0
		end
		local reason
		dealt, reason = DamageRules.PlayerHit({
			Health = humanoid.Health,
			MaxHealth = humanoid.MaxHealth,
			Amount = amount,
			Now = now,
			LastHitAt = target:GetAttribute("LastHitAt"),
			IFrameUntil = target:GetAttribute("IFrameUntil"),
			Blocking = target:GetAttribute("Blocking") == true,
			Reduction = reduction,
			Rules = Config.Player,
		})
		if reason == "iframe" then
			return 0
		end
		target:SetAttribute("LastHitAt", now)
		if target:GetAttribute("Blocking") then
			note = "BLOCK"
		elseif reason == "laststand" then
			note = "ENDURE"
		end
		humanoid.Health = math.max(0, humanoid.Health - dealt)
	else
		if target:GetAttribute("IsCurse") and info.CurseMultiplier then
			amount *= info.CurseMultiplier
		end
		dealt = math.floor(amount + 0.5)
		humanoid.Health = math.max(0, humanoid.Health - dealt)
	end

	if dealt and dealt > 0 then
		if info.Source then
			target:SetAttribute("LastAttacker", info.Source.UserId)
		end
		if info.Knockback then
			Combat.Knockback(target, info.Knockback)
		end
		if info.Stun then
			Combat.Stun(target, info.Stun)
		end
	end

	if root and not info.Silent then
		local typeInfo = Config.DamageTypes[damageType] or Config.DamageTypes.Boss
		Combat.FX("DamageNumber", { Pos = root.Position + Vector3.new(0, 4, 0), Amount = dealt, Color = typeInfo.Color, Note = note })
		if dealt and dealt > 0 then
			Combat.FX("Hit", { Pos = root.Position, Color = typeInfo.Color, Big = dealt >= 200 })
		end
	end
	return dealt or 0
end

return Combat
