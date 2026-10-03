--[[
	SukunaServer — authoritative side of the Sukuna powers.

	• Click the red cube → transformation (markings, stats, aura) → powers.
	• Validates every ability request (state, cooldowns), runs hitboxes,
	  damage, stuns and knockback, and broadcasts "FX" events so every client
	  plays the matching R15 animation, VFX and cinematics.
	• Spawns R15 training dummies to test on.
]]

local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("SukunaShared")
local Config = require(Shared:WaitForChild("Config"))

local AB = Config.Abilities
local T = Config.Timing
local C = Config.Colors

----------------------------------------------------------------------
-- Networking
----------------------------------------------------------------------

local remote = Shared:FindFirstChild("SukunaRemote")
if not remote then
	remote = Instance.new("RemoteEvent")
	remote.Name = "SukunaRemote"
	remote.Parent = Shared
end

local function fx(name: string, data)
	remote:FireAllClients("FX", name, data)
end

local function notify(player: Player, text: string)
	remote:FireClient(player, "Notify", text)
end

----------------------------------------------------------------------
-- Collision groups: client debris never trips characters
----------------------------------------------------------------------

pcall(function()
	PhysicsService:RegisterCollisionGroup("SukunaDebris")
	PhysicsService:RegisterCollisionGroup("SukunaCharacters")
	PhysicsService:CollisionGroupSetCollidable("SukunaDebris", "SukunaCharacters", false)
	PhysicsService:CollisionGroupSetCollidable("SukunaDebris", "SukunaDebris", false)
end)

local function setCharacterGroup(character: Model)
	local function apply(d: Instance)
		if d:IsA("BasePart") then
			d.CollisionGroup = "SukunaCharacters"
		end
	end
	for _, d in character:GetDescendants() do
		apply(d)
	end
	character.DescendantAdded:Connect(apply)
end

----------------------------------------------------------------------
-- Character helpers
----------------------------------------------------------------------

local function partsOf(character: Model?)
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

local function alive(character: Model?): boolean
	local humanoid = partsOf(character)
	return humanoid ~= nil and humanoid.Health > 0 and character ~= nil and character.Parent ~= nil
end

local function rootOfHumanoid(humanoid: Humanoid): BasePart?
	local r = humanoid.Parent and humanoid.Parent:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function flatDirection(root: BasePart, aim: Vector3?): Vector3
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.new(0, 0, -1)
	end
	look = look.Unit
	if aim then
		local d = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
		if d.Magnitude > 2 and d.Unit:Dot(look) > 0.3 then
			return d.Unit
		end
	end
	return look
end

----------------------------------------------------------------------
-- Movement locks (stuns / move commitment), stacked safely
----------------------------------------------------------------------

local locks = {}

local function applyLock(humanoid: Humanoid)
	local l = locks[humanoid]
	if not l then
		return
	end
	local speed = math.huge
	for _, s in l.entries do
		speed = math.min(speed, s)
	end
	humanoid.WalkSpeed = speed
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function lock(humanoid: Humanoid, speed: number?): () -> ()
	local l = locks[humanoid]
	if not l then
		l = {
			entries = {},
			walk = humanoid.WalkSpeed,
			jumpPower = humanoid.JumpPower,
			jumpHeight = humanoid.JumpHeight,
		}
		locks[humanoid] = l
	end
	local token = {}
	l.entries[token] = speed or 0
	applyLock(humanoid)
	local released = false
	return function()
		if released then
			return
		end
		released = true
		l.entries[token] = nil
		if next(l.entries) == nil then
			if locks[humanoid] == l then
				locks[humanoid] = nil
			end
			if humanoid.Parent then
				humanoid.WalkSpeed = l.walk
				humanoid.JumpPower = l.jumpPower
				humanoid.JumpHeight = l.jumpHeight
			end
		else
			applyLock(humanoid)
		end
	end
end

local function lockFor(humanoid: Humanoid, duration: number, speed: number?)
	task.delay(duration, lock(humanoid, speed))
end

local function setBaseWalkSpeed(humanoid: Humanoid, speed: number)
	local l = locks[humanoid]
	if l then
		l.walk = speed
	else
		humanoid.WalkSpeed = speed
	end
end

local stunnedUntil = setmetatable({}, { __mode = "k" })

local function stun(humanoid: Humanoid, duration: number, speed: number?)
	local untilTime = os.clock() + duration
	if (speed or 0) == 0 then
		stunnedUntil[humanoid] = math.max(stunnedUntil[humanoid] or 0, untilTime)
	end
	lockFor(humanoid, duration, speed or 0)
end

local function isStunned(humanoid: Humanoid): boolean
	return (stunnedUntil[humanoid] or 0) > os.clock()
end

local function invulnerable(character: Model, duration: number)
	local ff = Instance.new("ForceField")
	ff.Name = "SukunaGuard"
	ff.Visible = false
	ff.Parent = character
	Debris:AddItem(ff, duration)
	return ff
end

----------------------------------------------------------------------
-- Hit detection & damage
----------------------------------------------------------------------

local function overlapParams(exclude: Model?): OverlapParams
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	if exclude then
		table.insert(list, exclude)
	end
	params.FilterDescendantsInstances = list
	return params
end

local function humanoidsFromParts(parts: { BasePart }, exclude: Model?): { Humanoid }
	local found, out = {}, {}
	for _, part in parts do
		local model = part:FindFirstAncestorOfClass("Model")
		while model and not model:FindFirstChildOfClass("Humanoid") do
			model = model:FindFirstAncestorOfClass("Model")
		end
		if model and model ~= exclude then
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not found[humanoid] then
				found[humanoid] = true
				table.insert(out, humanoid)
			end
		end
	end
	return out
end

local function queryBox(cf: CFrame, size: Vector3, exclude: Model?): { Humanoid }
	return humanoidsFromParts(Workspace:GetPartBoundsInBox(cf, size, overlapParams(exclude)), exclude)
end

local function queryRadius(pos: Vector3, radius: number, exclude: Model?): { Humanoid }
	return humanoidsFromParts(Workspace:GetPartBoundsInRadius(pos, radius, overlapParams(exclude)), exclude)
end

local function applyVelocity(root: BasePart, velocity: Vector3, duration: number)
	local att = root:FindFirstChild("RootAttachment")
	if not att or not att:IsA("Attachment") then
		att = Instance.new("Attachment")
		att.Parent = root
	end
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att :: Attachment
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 1e7
	lv.VectorVelocity = velocity
	lv.Parent = root
	Debris:AddItem(lv, duration)
end

local function knockback(character: Model, velocity: Vector3, duration: number?)
	local humanoid, root = partsOf(character)
	if not humanoid or not root then
		return
	end
	local target = Players:GetPlayerFromCharacter(character)
	if target then
		remote:FireClient(target, "Knockback", velocity, duration or 0.2)
	else
		applyVelocity(root, velocity, duration or 0.2)
	end
end

local function tag(humanoid: Humanoid, attacker: Player)
	local old = humanoid:FindFirstChild("creator")
	if old then
		old:Destroy()
	end
	local creator = Instance.new("ObjectValue")
	creator.Name = "creator"
	creator.Value = attacker
	creator.Parent = humanoid
	Debris:AddItem(creator, 3)
end

--[[
	opts: kind ("blunt" | "slash" | "burn"), heavy, knock (Vector3),
	      knockTime, stun (seconds), fx (false = no hit FX), quiet
]]
local function damage(attacker: Player, humanoid: Humanoid, amount: number, opts)
	opts = opts or {}
	local character = humanoid.Parent :: Model?
	if not character or humanoid.Health <= 0 then
		return false
	end
	if not Config.DamagePlayers and Players:GetPlayerFromCharacter(character) then
		return false
	end
	tag(humanoid, attacker)
	humanoid:TakeDamage(amount)
	if opts.stun then
		stun(humanoid, opts.stun, opts.stunSpeed)
	end
	if opts.knock then
		knockback(character, opts.knock, opts.knockTime)
	end
	if opts.fx ~= false then
		fx("Hit", { char = character, kind = opts.kind or "blunt", heavy = opts.heavy, quiet = opts.quiet })
	end
	return true
end

-- Moving hitbox for projectiles such as Dismantle's flying slashes.
local function sweep(origin: CFrame, speed: number, range: number, size: Vector3, exclude: Model?, onHit: (Humanoid) -> ())
	local traveled = 0
	local hit = {}
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function(dt)
		local from = traveled
		traveled = math.min(traveled + speed * dt, range)
		local len = traveled - from + size.Z
		local cf = origin * CFrame.new(0, 0, -(from + traveled) / 2)
		for _, humanoid in queryBox(cf, Vector3.new(size.X, size.Y, len), exclude) do
			if not hit[humanoid] then
				hit[humanoid] = true
				task.spawn(onHit, humanoid)
			end
		end
		if traveled >= range then
			conn:Disconnect()
		end
	end)
end

----------------------------------------------------------------------
-- Sukuna's markings (face lines, extra eyes, arm bands, chest lines)
----------------------------------------------------------------------

local function decor(folder: Folder, parentPart: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
	local p = Instance.new("Part")
	p.Name = "Marking"
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = parentPart.CFrame * offset
	local weld = Instance.new("Weld")
	weld.Part0 = parentPart
	weld.Part1 = p
	weld.C0 = offset
	weld.Parent = p
	p.Parent = folder
	return p
end

local function visualSize(part: BasePart): Vector3
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		if mesh.MeshType == Enum.MeshType.Head then
			return Vector3.new(part.Size.X * mesh.Scale.X * 0.5, part.Size.Y * mesh.Scale.Y, part.Size.Z * mesh.Scale.Z)
		end
		return part.Size * mesh.Scale
	end
	return part.Size
end

local function applyMarkings(character: Model)
	local old = character:FindFirstChild("SukunaMarkings")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SukunaMarkings"
	folder.Parent = character
	local black = C.Black

	local head = character:FindFirstChild("Head")
	if Config.FaceMarkings and head and head:IsA("BasePart") then
		local s = visualSize(head)
		local w, h, dz = s.X, s.Y, s.Z / 2
		local r = w / 2
		-- Place a flat mark on the rounded front of the head.
		local function face(xn: number, yn: number, roll: number, size: Vector3, color: Color3, material: Enum.Material?)
			local x = math.clamp(xn * w, -r * 0.95, r * 0.95)
			local theta = math.asin(x / r)
			local z = -math.cos(theta) * dz
			local offset = CFrame.new(math.sin(theta) * r, yn * h, z + 0.005) * CFrame.Angles(0, -theta, math.rad(roll))
			decor(folder, head, size, offset, color, material)
		end
		for _, side in { -1, 1 } do
			-- glowing red eyes
			face(0.17 * side, 0.1, 0, Vector3.new(w * 0.11, h * 0.05, 0.04), C.Curse, Enum.Material.Neon)
			-- second pair of eyes opening beneath them
			face(0.19 * side, -0.02, -8 * side, Vector3.new(w * 0.14, h * 0.035, 0.04), black)
			face(0.19 * side, -0.02, -8 * side, Vector3.new(w * 0.07, h * 0.018, 0.05), C.Curse, Enum.Material.Neon)
			-- the two cheek lines
			face(0.22 * side, -0.12, 10 * side, Vector3.new(w * 0.26, h * 0.035, 0.04), black)
			face(0.22 * side, -0.2, 10 * side, Vector3.new(w * 0.24, h * 0.035, 0.04), black)
			-- forehead marks
			face(0.08 * side, 0.27, -35 * side, Vector3.new(w * 0.16, h * 0.03, 0.04), black)
		end
		face(0, 0.33, 0, Vector3.new(w * 0.035, h * 0.12, 0.04), black)
	end

	if Config.BodyMarkings then
		-- black bands around the forearms and upper arms
		for _, side in { "Left", "Right" } do
			local lower = character:FindFirstChild(side .. "LowerArm")
			if lower and lower:IsA("BasePart") then
				local s = lower.Size
				for _, y in { -0.22, -0.34 } do
					decor(folder, lower, Vector3.new(s.X + 0.05, 0.07, s.Z + 0.05), CFrame.new(0, y * s.Y, 0), black)
				end
			end
			local upper = character:FindFirstChild(side .. "UpperArm")
			if upper and upper:IsA("BasePart") then
				local s = upper.Size
				decor(folder, upper, Vector3.new(s.X + 0.05, 0.07, s.Z + 0.05), CFrame.new(0, 0.05 * s.Y, 0), black)
			end
		end
		-- chest and abdomen lines
		local torso = character:FindFirstChild("UpperTorso")
		if torso and torso:IsA("BasePart") then
			local s = torso.Size
			local front = -s.Z / 2 - 0.01
			for _, side in { -1, 1 } do
				decor(folder, torso, Vector3.new(s.X * 0.28, 0.06, 0.03), CFrame.new(side * s.X * 0.22, s.Y * 0.12, front) * CFrame.Angles(0, 0, math.rad(-12 * side)), black)
				decor(folder, torso, Vector3.new(s.X * 0.22, 0.06, 0.03), CFrame.new(side * s.X * 0.2, s.Y * 0.01, front) * CFrame.Angles(0, 0, math.rad(-12 * side)), black)
				decor(folder, torso, Vector3.new(s.X * 0.16, 0.06, 0.03), CFrame.new(side * s.X * 0.14, -s.Y * 0.3, front), black)
			end
		end
	end
end

local function applyAura(character: Model)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or root:FindFirstChild("SukunaAura") then
		return
	end
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "SukunaAura"
	aura.Texture = "rbxasset://textures/particles/fire_main.dds"
	aura.Color = ColorSequence.new(C.Curse, C.Black)
	aura.LightEmission = 0.6
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	aura.Lifetime = NumberRange.new(0.5, 0.9)
	aura.Speed = NumberRange.new(1, 2.5)
	aura.Acceleration = Vector3.new(0, 7, 0)
	aura.Rate = 14
	aura.RotSpeed = NumberRange.new(-60, 60)
	aura.Rotation = NumberRange.new(0, 360)
	aura.Parent = root
	local glow = Instance.new("PointLight")
	glow.Name = "SukunaGlow"
	glow.Color = C.Curse
	glow.Range = 7
	glow.Brightness = 0.7
	glow.Parent = root
end

local function applyPowerState(player: Player, character: Model)
	local humanoid = partsOf(character)
	if not humanoid then
		return
	end
	applyMarkings(character)
	applyAura(character)
	humanoid.MaxHealth = Config.Stats.MaxHealth
	humanoid.Health = Config.Stats.MaxHealth
	setBaseWalkSpeed(humanoid, Config.Stats.WalkSpeed)
	character:SetAttribute("SukunaActive", true)
	player:SetAttribute("SukunaPowered", true)
end

----------------------------------------------------------------------
-- Player state
----------------------------------------------------------------------

local states = {}

local function stateOf(player: Player)
	local s = states[player]
	if not s then
		s = {
			busyUntil = 0,
			cooldowns = {},
			combo = 0,
			lastCombo = 0,
			transforming = false,
			domainActive = false,
		}
		states[player] = s
	end
	return s
end

----------------------------------------------------------------------
-- The red cube: transformation
----------------------------------------------------------------------

local cube = Workspace:WaitForChild(Config.Cube.Name, 30)

local function grantPowers(player: Player)
	local character = player.Character
	local humanoid, root = partsOf(character)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if Config.RequireR15 and humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		notify(player, "Sukuna's power needs an R15 avatar (Game Settings → Avatar → R15).")
		return
	end
	local st = stateOf(player)
	if st.transforming then
		return
	end
	if character:GetAttribute("SukunaActive") then
		notify(player, "You already carry the King of Curses.")
		return
	end
	if cube and cube:IsA("BasePart") and (root.Position - cube.Position).Magnitude > Config.Cube.ClickDistance + 10 then
		return
	end

	st.transforming = true
	st.busyUntil = os.clock() + T.Transform.Duration
	local release = lock(humanoid)
	invulnerable(character, T.Transform.Duration)
	fx("Transform", { char = character })

	task.delay(T.Transform.Burst, function()
		if alive(character) then
			applyPowerState(player, character)
			for _, h in queryRadius(root.Position, 14, character) do
				local r = rootOfHumanoid(h)
				if r then
					local away = Vector3.new(r.Position.X - root.Position.X, 0, r.Position.Z - root.Position.Z)
					away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
					knockback(h.Parent :: Model, away * 70 + Vector3.new(0, 35, 0), 0.25)
				end
			end
		end
	end)
	task.delay(T.Transform.Duration, function()
		release()
		st.transforming = false
	end)
end

----------------------------------------------------------------------
-- Abilities
----------------------------------------------------------------------

local Abilities = {}

function Abilities.Combo(player: Player, st, character: Model, humanoid: Humanoid, root: BasePart, aim: Vector3?)
	local ab = AB.Combo
	local now = os.clock()
	if now - st.lastCombo > 0.95 then
		st.combo = 0
	end
	st.combo = st.combo % 4 + 1
	st.lastCombo = now
	local index = st.combo
	lockFor(humanoid, T.Combo.Busy, 4)
	fx("Combo", { char = character, index = index })
	task.delay(T.Combo.Hit, function()
		if not alive(character) then
			return
		end
		local cf = root.CFrame * CFrame.new(0, 0, -ab.Range / 2)
		local look = root.CFrame.LookVector
		for _, h in queryBox(cf, Vector3.new(5.5, 6, ab.Range), character) do
			local finisher = index == 4
			damage(player, h, ab.Damage[index], {
				kind = "blunt",
				heavy = finisher,
				knock = if finisher then look * 60 + Vector3.new(0, 28, 0) else look * 10,
				knockTime = if finisher then 0.25 else 0.12,
				stun = if finisher then 0.7 else 0.4,
			})
		end
	end)
	local cooldown = if index == 4 then ab.FinisherCooldown else ab.Cooldown
	return T.Combo.Busy, cooldown, true
end

function Abilities.Dismantle(player: Player, st, character: Model, humanoid: Humanoid, root: BasePart, aim: Vector3?)
	local ab, Tt = AB.Dismantle, T.Dismantle
	local dir = flatDirection(root, aim)
	local start = root.Position + Vector3.new(0, 0.6, 0) + dir * 2
	local origin = CFrame.lookAt(start, start + dir)
	lockFor(humanoid, Tt.Duration, 2)
	fx("Dismantle", {
		char = character,
		origin = origin,
		speed = ab.Speed,
		range = ab.Range,
		width = ab.Width,
		times = Tt.SlashTimes,
		tilts = ab.Tilts,
	})
	for _, t in Tt.SlashTimes do
		task.delay(t, function()
			if not alive(character) then
				return
			end
			sweep(origin, ab.Speed, ab.Range, Vector3.new(ab.Width, 6, 3), character, function(h)
				damage(player, h, ab.Damage, {
					kind = "slash",
					knock = dir * 14,
					knockTime = 0.1,
					stun = 0.35,
				})
			end)
		end)
	end
	return Tt.Duration, ab.Cooldown
end

function Abilities.Cleave(player: Player, st, character: Model, humanoid: Humanoid, root: BasePart, aim: Vector3?)
	local ab, Tt = AB.Cleave, T.Cleave
	local look = flatDirection(root, aim)
	-- pick the closest target in front of Sukuna
	local best, bestScore = nil, math.huge
	for _, h in queryRadius(root.Position, ab.Range, character) do
		local r = rootOfHumanoid(h)
		if r then
			local offset = r.Position - root.Position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local facing = if flat.Magnitude > 0.1 then flat.Unit:Dot(look) else 1
			if facing > 0.25 then
				local score = flat.Magnitude * (1.6 - facing)
				if score < bestScore then
					best, bestScore = h, score
				end
			end
		end
	end
	lockFor(humanoid, Tt.Duration)
	fx("Cleave", { char = character, target = best and best.Parent })
	if not best then
		return Tt.Duration, ab.WhiffCooldown
	end
	local target = best
	task.delay(Tt.CutStart, function()
		local tr = rootOfHumanoid(target)
		if not alive(character) or target.Health <= 0 or not tr then
			return
		end
		if (tr.Position - root.Position).Magnitude > ab.Range + 8 then
			return
		end
		stun(target, ab.Cuts * Tt.CutInterval + 0.5)
		for i = 1, ab.Cuts do
			task.delay((i - 1) * Tt.CutInterval, function()
				if target.Health <= 0 or not target.Parent then
					return
				end
				local final = i == ab.Cuts
				local amount = ab.DamagePerCut + target.MaxHealth * ab.PercentPerCut
				local away = Vector3.new(tr.Position.X - root.Position.X, 0, tr.Position.Z - root.Position.Z)
				away = if away.Magnitude > 0.1 then away.Unit else look
				damage(player, target, amount, {
					fx = false,
					knock = if final then away * 75 + Vector3.new(0, 30, 0) else nil,
					knockTime = 0.25,
				})
				fx("CleaveCut", { char = character, target = target.Parent, index = i, final = final })
			end)
		end
	end)
	return Tt.Duration, ab.Cooldown
end

local function rayParams(exclude: Model?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list = {}
	if exclude then
		table.insert(list, exclude)
	end
	local fxFolder = Workspace:FindFirstChild("SukunaFX_Local")
	if fxFolder then
		table.insert(list, fxFolder)
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = true
	return params
end

local function fugaExplosion(player: Player, character: Model, pos: Vector3)
	local ab = AB.Fuga
	for _, h in queryRadius(pos, ab.Radius, character) do
		local r = rootOfHumanoid(h)
		local offset = if r then r.Position - pos else Vector3.yAxis
		local dist = offset.Magnitude
		local falloff = 1 - math.clamp(dist / ab.Radius, 0, 1) * 0.5
		local away = Vector3.new(offset.X, 0, offset.Z)
		away = if away.Magnitude > 0.1 then away.Unit else Vector3.xAxis
		damage(player, h, ab.Damage * falloff, {
			kind = "burn",
			heavy = true,
			knock = away * 80 + Vector3.new(0, 50, 0),
			knockTime = 0.3,
			stun = 0.8,
		})
	end
	-- lingering flames
	task.spawn(function()
		local finish = os.clock() + ab.BurnDuration
		while os.clock() < finish do
			task.wait(0.5)
			for _, h in queryRadius(pos, ab.Radius * 0.55, character) do
				damage(player, h, ab.BurnDamage, { kind = "burn", quiet = true })
			end
		end
	end)
end

function Abilities.Fuga(player: Player, st, character: Model, humanoid: Humanoid, root: BasePart, aim: Vector3?)
	local ab, Tt = AB.Fuga, T.Fuga
	lockFor(humanoid, Tt.Duration)
	fx("Fuga", { char = character })
	task.delay(Tt.Release, function()
		if not alive(character) then
			return
		end
		local look = root.CFrame.LookVector
		local origin = (root.CFrame * CFrame.new(0.2, 0.9, -2.4)).Position
		local target = aim or (origin + look * ab.MaxRange)
		local dir = target - origin
		dir = if dir.Magnitude > 1 then dir.Unit else look
		if dir:Dot(look) < 0.2 then
			dir = look
		end
		local result = Workspace:Raycast(origin, dir * ab.MaxRange, rayParams(character))
		local hitPos = if result then result.Position else origin + dir * ab.MaxRange
		local travel = (hitPos - origin).Magnitude / ab.Speed
		fx("FugaRelease", {
			char = character,
			origin = origin,
			hitPos = hitPos,
			travel = travel,
			radius = ab.Radius,
		})
		task.delay(travel, function()
			fugaExplosion(player, character, hitPos)
		end)
	end)
	return Tt.Duration, ab.Cooldown
end

function Abilities.Domain(player: Player, st, character: Model, humanoid: Humanoid, root: BasePart, aim: Vector3?)
	local ab, Td = AB.Domain, T.Domain
	if st.domainActive then
		return nil
	end
	st.domainActive = true
	local look = flatDirection(root, nil)
	local center = root.Position
	local ground = Workspace:Raycast(center, Vector3.new(0, -40, 0), rayParams(character))
	local groundY = if ground then ground.Position.Y else center.Y - 3

	lockFor(humanoid, Td.CasterLock)
	invulnerable(character, Td.CasterLock)
	fx("Domain", {
		char = character,
		center = center,
		look = look,
		ground = groundY,
		radius = ab.Radius,
	})

	task.delay(Td.SlashStart, function()
		local finish = os.clock() + (Td.SlashEnd - Td.SlashStart)
		while os.clock() < finish and alive(character) do
			local hits = {}
			for _, h in queryRadius(center, ab.Radius, character) do
				if damage(player, h, ab.TickDamage, { fx = false, stun = ab.TickRate + 0.05, stunSpeed = ab.SlowSpeed }) then
					table.insert(hits, h.Parent)
				end
			end
			if #hits > 0 then
				fx("DomainHits", { char = character, targets = hits })
			end
			task.wait(ab.TickRate)
		end
		st.domainActive = false
	end)
	-- safety: never leave the flag stuck
	task.delay(Td.Collapse + 1, function()
		st.domainActive = false
	end)
	return Td.CasterLock, ab.Cooldown
end

function Abilities.WorldSlash(player: Player, st, character: Model, humanoid: Humanoid, root: BasePart, aim: Vector3?)
	local ab, Tw = AB.WorldSlash, T.WorldSlash
	local look = flatDirection(root, aim)
	local origin = CFrame.lookAt(root.Position, root.Position + look)
	lockFor(humanoid, Tw.Duration)
	invulnerable(character, Tw.Slash + 0.3)
	fx("WorldSlash", { char = character, origin = origin, length = ab.Length, height = ab.Height })
	task.delay(Tw.Slash, function()
		if not alive(character) then
			return
		end
		local cf = origin * CFrame.new(0, ab.Height / 2 - 6, -ab.Length / 2)
		for _, h in queryBox(cf, Vector3.new(ab.Width, ab.Height, ab.Length), character) do
			local r = rootOfHumanoid(h)
			local side = if r then math.sign(origin.RightVector:Dot(r.Position - origin.Position)) else 1
			if side == 0 then
				side = 1
			end
			damage(player, h, ab.Damage, {
				kind = "slash",
				heavy = true,
				knock = origin.RightVector * side * 60 + Vector3.new(0, 30, 0),
				knockTime = 0.3,
				stun = 1,
			})
		end
	end)
	return Tw.Duration, ab.Cooldown
end

local function useAbility(player: Player, name: string, aim: Vector3?)
	local handler = Abilities[name]
	if not handler or not AB[name] then
		return
	end
	if not player:GetAttribute("SukunaPowered") then
		return
	end
	local character = player.Character
	local humanoid, root = partsOf(character)
	if not character or not humanoid or not root or humanoid.Health <= 0 then
		return
	end
	if not character:GetAttribute("SukunaActive") then
		return
	end
	local st = stateOf(player)
	local now = os.clock()
	if st.transforming or now < st.busyUntil or now < (st.cooldowns[name] or 0) or isStunned(humanoid) then
		return
	end
	local ok, busy, cooldown, silent = pcall(handler, player, st, character, humanoid, root, aim)
	if not ok then
		warn("[SukunaServer] " .. name .. " failed: " .. tostring(busy))
		return
	end
	if not busy then
		return
	end
	st.busyUntil = now + busy
	st.cooldowns[name] = now + cooldown
	if not silent then
		remote:FireClient(player, "Cooldown", name, cooldown)
	end
end

remote.OnServerEvent:Connect(function(player: Player, action, payload)
	if action ~= "Ability" or type(payload) ~= "table" then
		return
	end
	local name = payload.name
	if type(name) ~= "string" then
		return
	end
	local aim = payload.aim
	if typeof(aim) ~= "Vector3" or aim ~= aim or aim.Magnitude > 1e6 then
		aim = nil
	end
	useAbility(player, name, aim)
end)

----------------------------------------------------------------------
-- Players
----------------------------------------------------------------------

local function onCharacter(player: Player, character: Model)
	setCharacterGroup(character)
	local st = stateOf(player)
	st.busyUntil = 0
	st.transforming = false
	st.combo = 0
	if not player:GetAttribute("SukunaPowered") then
		return
	end
	if not Config.KeepPowersOnRespawn then
		player:SetAttribute("SukunaPowered", false)
		return
	end
	-- wait until the avatar's body parts are loaded so markings stick
	local start = os.clock()
	while not player:HasAppearanceLoaded() and os.clock() - start < 6 do
		task.wait(0.2)
	end
	task.wait(0.3)
	if player.Character == character and alive(character) then
		applyPowerState(player, character)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end)
for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
end

Players.PlayerRemoving:Connect(function(player)
	states[player] = nil
end)

----------------------------------------------------------------------
-- Cube setup
----------------------------------------------------------------------

if cube and cube:IsA("BasePart") then
	local detector = cube:FindFirstChildOfClass("ClickDetector")
	if not detector then
		detector = Instance.new("ClickDetector")
		detector.Parent = cube
	end
	detector.MaxActivationDistance = Config.Cube.ClickDistance

	if not cube:FindFirstChild("SukunaLabel") then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SukunaLabel"
		billboard.Size = UDim2.fromOffset(260, 70)
		billboard.StudsOffset = Vector3.new(0, 4.2, 0)
		billboard.MaxDistance = 90
		billboard.LightInfluence = 0
		billboard.Parent = cube

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Size = UDim2.fromScale(1, 0.6)
		title.Font = Enum.Font.GothamBlack
		title.Text = "両面宿儺 · SUKUNA'S FINGER"
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 230, 230)
		title.Parent = billboard
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(150, 0, 15)
		stroke.Thickness = 2
		stroke.Parent = title

		local hint = Instance.new("TextLabel")
		hint.BackgroundTransparency = 1
		hint.Position = UDim2.fromScale(0, 0.6)
		hint.Size = UDim2.fromScale(1, 0.4)
		hint.Font = Enum.Font.GothamBold
		hint.Text = "Click to awaken the King of Curses"
		hint.TextScaled = true
		hint.TextColor3 = Color3.fromRGB(255, 90, 100)
		hint.Parent = billboard
	end

	if not cube:FindFirstChild("CurseParticles") then
		local particles = Instance.new("ParticleEmitter")
		particles.Name = "CurseParticles"
		particles.Color = ColorSequence.new(C.Curse, C.Black)
		particles.LightEmission = 1
		particles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
		particles.Lifetime = NumberRange.new(1, 2)
		particles.Speed = NumberRange.new(1, 3)
		particles.SpreadAngle = Vector2.new(180, 180)
		particles.Acceleration = Vector3.new(0, 2, 0)
		particles.Rate = 25
		particles.Parent = cube
	end
	if not cube:FindFirstChildOfClass("PointLight") then
		local light = Instance.new("PointLight")
		light.Color = C.Curse
		light.Range = 14
		light.Brightness = 3
		light.Parent = cube
	end

	detector.MouseClick:Connect(grantPowers)
else
	warn("[SukunaServer] Could not find a part named '" .. Config.Cube.Name .. "' in Workspace.")
end

----------------------------------------------------------------------
-- Training dummies (R15)
----------------------------------------------------------------------

if Config.Dummies.Enabled then
	local folder = Workspace:FindFirstChild("SukunaDummies") or Instance.new("Folder")
	folder.Name = "SukunaDummies"
	folder.Parent = Workspace

	local basePos = if cube and cube:IsA("BasePart") then cube.Position else Vector3.new(0, 4, 0)
	-- dummies stand on the far side of the cube (the spawn is on its +Z side)
	local baseLook = if cube and cube:IsA("BasePart") then cube.CFrame.LookVector else Vector3.new(0, 0, -1)
	baseLook = Vector3.new(baseLook.X, 0, baseLook.Z).Unit

	local function spawnDummy(slot: number)
		local ok, model = pcall(function()
			local desc = Instance.new("HumanoidDescription")
			local skin = Color3.fromRGB(110, 100, 120)
			desc.HeadColor = skin
			desc.TorsoColor = Color3.fromRGB(60, 50, 70)
			desc.LeftArmColor = skin
			desc.RightArmColor = skin
			desc.LeftLegColor = Color3.fromRGB(45, 40, 55)
			desc.RightLegColor = Color3.fromRGB(45, 40, 55)
			return Players:CreateHumanoidModelFromDescriptionAsync(desc, Enum.HumanoidRigType.R15)
		end)
		if not ok or not model then
			warn("[SukunaServer] Could not create dummy: " .. tostring(model))
			return
		end
		model.Name = "Cursed Spirit Dummy"
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayName = "Cursed Spirit"
			humanoid.MaxHealth = Config.Dummies.Health
			humanoid.Health = Config.Dummies.Health
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
		end
		local count = Config.Dummies.Count
		local right = baseLook:Cross(Vector3.yAxis)
		local spread = (slot - (count + 1) / 2) * 9
		local pos = basePos + baseLook * Config.Dummies.Distance + right * spread
		local ray = Workspace:Raycast(pos + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), rayParams(nil))
		local groundY = if ray then ray.Position.Y else 0
		local hip = if humanoid then humanoid.HipHeight else 2
		local rootPart = model:FindFirstChild("HumanoidRootPart")
		local rootHalf = if rootPart and rootPart:IsA("BasePart") then rootPart.Size.Y / 2 else 1
		local spawnPos = Vector3.new(pos.X, groundY + hip + rootHalf + 0.1, pos.Z)
		model:PivotTo(CFrame.lookAt(spawnPos, spawnPos - baseLook))
		model.Parent = folder
		setCharacterGroup(model)
		if rootPart and rootPart:IsA("BasePart") then
			pcall(function()
				rootPart:SetNetworkOwner(nil)
			end)
		end
		if humanoid then
			humanoid.Died:Connect(function()
				task.wait(Config.Dummies.RespawnTime)
				model:Destroy()
				spawnDummy(slot)
			end)
		end
	end

	task.spawn(function()
		for i = 1, Config.Dummies.Count do
			spawnDummy(i)
		end
	end)
end

print("[SukunaServer] Ready — click the red cube to receive Sukuna's power.")
