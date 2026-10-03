--[[
	VFX — client-side effect builders (slashes, shockwaves, lightning, debris,
	craters, particles, auras, afterimages). Every effect is created locally on
	each client so it is smooth, and cleaned up automatically.
]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)
local C = Config.Colors

local VFX = {}

VFX.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
}

local random = Random.new()

----------------------------------------------------------------------
-- Infrastructure
----------------------------------------------------------------------

local folder: Folder? = nil
function VFX.folder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local f = Workspace:FindFirstChild("SukunaFX_Local")
	if not f then
		f = Instance.new("Folder")
		f.Name = "SukunaFX_Local"
		f.Parent = Workspace
	end
	folder = f
	return f
end

-- One Heartbeat loop drives every animated effect.
local updaters = {}
local loop: RBXScriptConnection? = nil
local function runUpdaters(dt: number)
	for fn, data in updaters do
		data.elapsed += dt
		local ok, keep = pcall(fn, dt, data.elapsed)
		if not ok then
			warn("[SukunaVFX]", keep)
			updaters[fn] = nil
		elseif keep == false then
			updaters[fn] = nil
		end
	end
	if next(updaters) == nil and loop then
		loop:Disconnect()
		loop = nil
	end
end

function VFX.addUpdater(fn: (number, number) -> boolean?)
	updaters[fn] = { elapsed = 0 }
	if not loop then
		loop = RunService.Heartbeat:Connect(runUpdaters)
	end
end

function VFX.tween(instance: Instance, time: number, props, style: string?, dir: string?): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(time, (Enum.EasingStyle :: any)[style or "Quad"], (Enum.EasingDirection :: any)[dir or "Out"]),
		props
	)
	tween:Play()
	return tween
end

function VFX.part(props): BasePart
	local className = props.ClassName or "Part"
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "ClassName" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent or VFX.folder()
	return p
end

function VFX.attachmentAt(cf: CFrame | Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Parent = Workspace.Terrain
	if typeof(cf) == "Vector3" then
		a.WorldPosition = cf
	else
		a.WorldCFrame = cf
	end
	return a
end

local function fadeSequence(base: { { number } }, fade: number): NumberSequence
	local points = {}
	for _, kp in base do
		table.insert(points, NumberSequenceKeypoint.new(kp[1], 1 - (1 - kp[2]) * (1 - fade)))
	end
	return NumberSequence.new(points)
end

function VFX.randomUnit(): Vector3
	return random:NextUnitVector()
end

function VFX.rand(a: number, b: number): number
	return random:NextNumber(a, b)
end

----------------------------------------------------------------------
-- Ground helpers
----------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function refreshGroundFilter()
	local list = { VFX.folder() }
	for _, plr in game:GetService("Players"):GetPlayers() do
		if plr.Character then
			table.insert(list, plr.Character)
		end
	end
	local fx = Workspace:FindFirstChild("SukunaFX")
	if fx then
		table.insert(list, fx)
	end
	local dummies = Workspace:FindFirstChild("SukunaDummies")
	if dummies then
		table.insert(list, dummies)
	end
	groundParams.FilterDescendantsInstances = list
end

-- Returns position, normal, color, material of the ground below a point.
function VFX.ground(pos: Vector3, depth: number?)
	refreshGroundFilter()
	local result = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -(depth or 60), 0), groundParams)
	if not result then
		return nil
	end
	local color = Color3.fromRGB(70, 66, 64)
	local material = Enum.Material.Slate
	local inst = result.Instance
	if inst:IsA("BasePart") and not inst:IsA("Terrain") then
		color = inst.Color
		material = inst.Material
	elseif inst:IsA("Terrain") then
		material = result.Material
		local ok, c = pcall(function()
			return Workspace.Terrain:GetMaterialColor(result.Material)
		end)
		if ok then
			color = c
		end
	end
	if material == Enum.Material.Neon or material == Enum.Material.ForceField or material == Enum.Material.Glass then
		material = Enum.Material.Slate
	end
	return {
		Position = result.Position,
		Normal = result.Normal,
		Color = color,
		Material = material,
	}
end

----------------------------------------------------------------------
-- Slashes
----------------------------------------------------------------------

--[[
	Crescent slash made of two curved beams (bright core + red glow).
	opts: width, bulge, thickness, life, velocity (Vector3), color, core
]]
function VFX.crescent(cf: CFrame, opts)
	opts = opts or {}
	local width = opts.width or 10
	local bulge = opts.bulge or width * 0.35
	local thickness = opts.thickness or 0.9
	local life = opts.life or 0.35
	local velocity: Vector3 = opts.velocity or Vector3.zero
	local k = bulge / 0.75

	local function place(frame: CFrame)
		local forward = frame.LookVector
		local up = frame.UpVector
		local leftTip = frame.Position - frame.RightVector * (width / 2)
		local rightTip = frame.Position + frame.RightVector * (width / 2)
		return CFrame.fromMatrix(leftTip, forward, up), CFrame.fromMatrix(rightTip, -forward, up)
	end

	local c0, c1 = place(cf)
	local a0 = VFX.attachmentAt(c0)
	local a1 = VFX.attachmentAt(c1)

	local coreShape = { { 0, 1 }, { 0.18, 0.35 }, { 0.5, 0 }, { 0.82, 0.35 }, { 1, 1 } }
	local glowShape = { { 0, 1 }, { 0.25, 0.55 }, { 0.5, 0.25 }, { 0.75, 0.55 }, { 1, 1 } }

	local function beam(color: Color3, w: number, shape, z: number)
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.CurveSize0 = k
		b.CurveSize1 = k
		b.Width0 = w
		b.Width1 = w
		b.Segments = 24
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = 4
		b.ZOffset = z
		b.Color = ColorSequence.new(color)
		b.Transparency = fadeSequence(shape, 0)
		b.Parent = a0
		return b
	end
	local glow = beam(opts.color or C.SlashGlow, thickness * 2.6, glowShape, 0)
	local core = beam(opts.core or C.SlashCore, thickness, coreShape, 0.5)

	local frame = cf
	VFX.addUpdater(function(dt, t)
		if not a0.Parent then
			return false
		end
		frame = frame + velocity * dt
		local n0, n1 = place(frame)
		a0.WorldCFrame = n0
		a1.WorldCFrame = n1
		local fade = math.clamp((t - life * 0.55) / (life * 0.45), 0, 1)
		core.Transparency = fadeSequence(coreShape, fade)
		glow.Transparency = fadeSequence(glowShape, fade)
		if t >= life then
			a0:Destroy()
			a1:Destroy()
			return false
		end
		return true
	end)
	return frame
end

-- Straight razor-thin cut line that snaps open then fades (Cleave / Domain).
function VFX.cutLine(center: Vector3, direction: Vector3, length: number, opts)
	opts = opts or {}
	local thickness = opts.thickness or 0.18
	local life = opts.life or 0.28
	local cf = CFrame.lookAt(center, center + direction.Unit)
	local core = VFX.part({
		Size = Vector3.new(thickness, thickness, 0.1),
		CFrame = cf,
		Color = opts.core or C.SlashCore,
		Transparency = 0,
	})
	local glow = VFX.part({
		Size = Vector3.new(thickness * 3.2, thickness * 3.2, 0.1),
		CFrame = cf,
		Color = opts.color or C.SlashGlow,
		Transparency = 0.45,
		Material = Enum.Material.ForceField,
	})
	VFX.tween(core, life * 0.3, { Size = Vector3.new(thickness, thickness, length) }, "Quint", "Out")
	VFX.tween(glow, life * 0.3, { Size = Vector3.new(thickness * 3.2, thickness * 3.2, length * 1.05) }, "Quint", "Out")
	task.delay(life * 0.35, function()
		VFX.tween(core, life * 0.65, { Transparency = 1, Size = Vector3.new(0.02, 0.02, length * 1.1) }, "Quad", "In")
		VFX.tween(glow, life * 0.65, { Transparency = 1 }, "Quad", "In")
	end)
	Debris:AddItem(core, life + 0.1)
	Debris:AddItem(glow, life + 0.1)
end

-- Black scar left on the ground by a slash. Fades after a few seconds.
function VFX.groundScar(pos: Vector3, direction: Vector3, length: number, width: number?, life: number?)
	local g = VFX.ground(pos, 20)
	if not g then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local at = g.Position + Vector3.new(0, 0.03, 0)
	local cf = CFrame.lookAt(at, at + flat.Unit)
	local scar = VFX.part({
		Size = Vector3.new(width or 0.35, 0.06, length),
		CFrame = cf,
		Color = C.Black,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.05,
	})
	local glowLine = VFX.part({
		Size = Vector3.new((width or 0.35) * 0.35, 0.07, length * 0.96),
		CFrame = cf,
		Color = C.Curse,
		Transparency = 0.2,
	})
	VFX.tween(glowLine, 0.8, { Transparency = 1 }, "Quad", "In")
	task.delay(life or 3, function()
		VFX.tween(scar, 1.2, { Transparency = 1 })
	end)
	Debris:AddItem(scar, (life or 3) + 1.3)
	Debris:AddItem(glowLine, 1)
end

----------------------------------------------------------------------
-- Shockwaves, rings, flashes
----------------------------------------------------------------------

function VFX.sphere(pos: Vector3, fromSize: number, toSize: number, life: number, opts)
	opts = opts or {}
	local p = VFX.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * fromSize,
		CFrame = CFrame.new(pos),
		Color = opts.color or C.Curse,
		Material = opts.material or Enum.Material.ForceField,
		Transparency = opts.transparency or 0,
	})
	VFX.tween(p, life, { Size = Vector3.one * toSize, Transparency = 1 }, opts.style or "Quart", "Out")
	Debris:AddItem(p, life + 0.05)
	return p
end

-- Flat expanding ring built from segments (crisp on any ground).
function VFX.ring(pos: Vector3, fromRadius: number, toRadius: number, life: number, opts)
	opts = opts or {}
	local count = opts.segments or 22
	local thickness = opts.thickness or 0.6
	local height = opts.height or 0.5
	local color = opts.color or C.Curse
	local tilt = opts.cframe or CFrame.new(pos)
	local parts = {}
	for i = 1, count do
		parts[i] = VFX.part({
			Size = Vector3.new(thickness, height, 1),
			Color = color,
			Transparency = opts.transparency or 0.1,
			Material = opts.material or Enum.Material.Neon,
		})
	end
	VFX.addUpdater(function(_, t)
		local a = math.clamp(t / life, 0, 1)
		local eased = 1 - (1 - a) ^ 3
		local r = fromRadius + (toRadius - fromRadius) * eased
		local seg = 2 * math.pi * r / count * 1.08
		local transparency = (opts.transparency or 0.1) + (1 - (opts.transparency or 0.1)) * a
		for i, p in parts do
			local ang = (i / count) * math.pi * 2
			local offset = Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
			local at = tilt * offset
			p.Size = Vector3.new(thickness * (1 - a * 0.6), height, seg)
			p.CFrame = CFrame.lookAt(at, at + (tilt.Rotation * Vector3.new(-math.sin(ang), 0, math.cos(ang))), tilt.UpVector)
			p.Transparency = transparency
		end
		if a >= 1 then
			for _, p in parts do
				p:Destroy()
			end
			return false
		end
		return true
	end)
end

function VFX.light(pos: Vector3, color: Color3, brightness: number, range: number, life: number)
	local holder = VFX.part({
		Size = Vector3.one * 0.2,
		CFrame = CFrame.new(pos),
		Transparency = 1,
	})
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = holder
	VFX.tween(light, life, { Brightness = 0 }, "Quad", "In")
	Debris:AddItem(holder, life + 0.05)
	return light
end

----------------------------------------------------------------------
-- Particles
----------------------------------------------------------------------

function VFX.emitter(parent: Instance, props): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = VFX.Textures.Sparkle
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- One-shot burst at a world position.
function VFX.burst(pos: Vector3, count: number, props)
	local a = VFX.attachmentAt(pos)
	local e = VFX.emitter(a, props)
	e:Emit(count)
	local maxLife = (props.Lifetime and props.Lifetime.Max) or 1
	Debris:AddItem(a, maxLife + 0.2)
	return e
end

function VFX.sparks(pos: Vector3, count: number?, color: Color3?)
	VFX.burst(pos, count or 18, {
		Color = ColorSequence.new(color or C.SlashGlow, C.SlashCore),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(25, 55),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 6,
		Squash = NumberSequence.new(-1.5),
		Transparency = NumberSequence.new(0),
	})
end

function VFX.bloodMist(pos: Vector3, count: number?)
	VFX.burst(pos, count or 10, {
		Texture = VFX.Textures.Smoke,
		Color = ColorSequence.new(C.Blood, C.CurseDark),
		LightEmission = 0.2,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.35, 0.7),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Acceleration = Vector3.new(0, -12, 0),
	})
end

function VFX.fireBurst(pos: Vector3, count: number, size: number, speed: number)
	VFX.burst(pos, count, {
		Texture = VFX.Textures.Fire,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.FireHot),
			ColorSequenceKeypoint.new(0.4, C.Fire),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 10, 0)),
		}),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(speed * 0.4, speed),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 3,
		Acceleration = Vector3.new(0, 18, 0),
		RotSpeed = NumberRange.new(-120, 120),
		Rotation = NumberRange.new(0, 360),
	})
end

function VFX.smokeBurst(pos: Vector3, count: number, size: number, color: Color3?)
	VFX.burst(pos, count, {
		Texture = VFX.Textures.Smoke,
		Color = ColorSequence.new(color or Color3.fromRGB(40, 30, 30)),
		LightEmission = 0,
		LightInfluence = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 2.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(1.2, 2.4),
		Speed = NumberRange.new(4, 16),
		SpreadAngle = Vector2.new(180, 60),
		Drag = 2,
		Acceleration = Vector3.new(0, 4, 0),
		RotSpeed = NumberRange.new(-40, 40),
		Rotation = NumberRange.new(0, 360),
	})
end

-- Particles pulled inward toward a point (cursed energy gathering).
function VFX.gather(parent: BasePart, duration: number, radius: number?)
	local e = VFX.emitter(parent, {
		Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Color = ColorSequence.new(C.Curse, C.CurseDark),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.1),
		Lifetime = NumberRange.new(0.35, 0.5),
		Speed = NumberRange.new((radius or 9) * 1.6, (radius or 9) * 2.2),
		Rate = 140,
		Squash = NumberSequence.new(-1.2),
		LockedToPart = true,
	})
	-- An inward-facing sphere emitter uses the part size as the shell, so size an invisible shell part.
	local shell = VFX.part({
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * (radius or 9) * 2,
		CFrame = parent.CFrame,
		Transparency = 1,
	})
	e.Parent = shell
	e.Enabled = true
	VFX.addUpdater(function(_, t)
		if not shell.Parent or not parent.Parent then
			return false
		end
		shell.CFrame = parent.CFrame
		if t >= duration then
			e.Enabled = false
			Debris:AddItem(shell, 0.6)
			return false
		end
		return true
	end)
end

----------------------------------------------------------------------
-- Lightning
----------------------------------------------------------------------

function VFX.lightning(p0: Vector3, p1: Vector3, opts)
	opts = opts or {}
	local segments = opts.segments or 7
	local jitter = opts.jitter or ((p1 - p0).Magnitude * 0.12)
	local thickness = opts.thickness or 0.18
	local life = opts.life or 0.14
	local color = opts.color or C.Curse
	local last = p0
	local parts = {}
	for i = 1, segments do
		local a = i / segments
		local point = p0:Lerp(p1, a)
		if i < segments then
			point += VFX.randomUnit() * jitter * random:NextNumber(0.3, 1)
		end
		local len = (point - last).Magnitude
		if len > 0.01 then
			table.insert(parts, VFX.part({
				Size = Vector3.new(thickness, thickness, len),
				CFrame = CFrame.lookAt((last + point) / 2, point),
				Color = color,
			}))
		end
		last = point
	end
	for _, p in parts do
		VFX.tween(p, life, { Transparency = 1, Size = Vector3.new(0.02, 0.02, p.Size.Z) }, "Quad", "In")
		Debris:AddItem(p, life + 0.05)
	end
end

----------------------------------------------------------------------
-- Rocks, debris, craters
----------------------------------------------------------------------

function VFX.debris(pos: Vector3, count: number, power: number?, size: number?)
	local g = VFX.ground(pos, 30)
	local color = g and g.Color or Color3.fromRGB(80, 74, 70)
	local material = g and g.Material or Enum.Material.Slate
	local base = g and g.Position or pos
	for _ = 1, count do
		local s = random:NextNumber(0.5, 1.4) * (size or 1)
		local rock = VFX.part({
			Size = Vector3.new(s, s * random:NextNumber(0.6, 1.1), s),
			CFrame = CFrame.new(base + Vector3.new(random:NextNumber(-2, 2), 0.6, random:NextNumber(-2, 2)))
				* CFrame.Angles(random:NextNumber(0, 6.28), random:NextNumber(0, 6.28), 0),
			Color = color:Lerp(Color3.new(0, 0, 0), random:NextNumber(0, 0.3)),
			Material = material,
			Anchored = false,
			CanCollide = true,
		})
		pcall(function()
			rock.CollisionGroup = "SukunaDebris" -- registered by the server; never trips characters
		end)
		local dir = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(0.9, 1.8), random:NextNumber(-1, 1)).Unit
		rock.AssemblyLinearVelocity = dir * random:NextNumber(25, 55) * (power or 1)
		rock.AssemblyAngularVelocity = VFX.randomUnit() * 15
		task.delay(random:NextNumber(2, 3), function()
			if rock.Parent then
				rock.Anchored = true
				rock.CanCollide = false
				VFX.tween(rock, 0.8, { Transparency = 1, Size = rock.Size * 0.3 })
			end
		end)
		Debris:AddItem(rock, 4)
	end
end

-- Ring of jagged rocks pushed up out of the ground.
function VFX.crater(pos: Vector3, radius: number, count: number?, life: number?)
	local g = VFX.ground(pos, 30)
	if not g then
		return
	end
	local center = g.Position
	local n = count or 14
	for i = 1, n do
		local ang = (i / n) * math.pi * 2 + random:NextNumber(-0.15, 0.15)
		local r = radius * random:NextNumber(0.85, 1.1)
		local s = radius * random:NextNumber(0.22, 0.34)
		local at = center + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
		local outward = (at - center).Unit
		local final = CFrame.lookAt(at, at + outward) * CFrame.Angles(math.rad(random:NextNumber(25, 50)), 0, math.rad(random:NextNumber(-15, 15)))
		local rock = VFX.part({
			Size = Vector3.new(s, s * 0.7, s * 1.1),
			CFrame = final - Vector3.new(0, s, 0),
			Color = g.Color:Lerp(Color3.new(0, 0, 0), random:NextNumber(0.05, 0.3)),
			Material = g.Material,
			CanCollide = false,
		})
		VFX.tween(rock, 0.18, { CFrame = final }, "Back", "Out")
		task.delay(life or 4, function()
			if rock.Parent then
				VFX.tween(rock, 1, { CFrame = final - Vector3.new(0, s * 1.5, 0), Transparency = 1 }, "Quad", "In")
			end
		end)
		Debris:AddItem(rock, (life or 4) + 1.1)
	end
	-- Scorched centre
	local scorch = VFX.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, radius * 2, radius * 2),
		CFrame = CFrame.new(center + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(20, 12, 12),
		Material = Enum.Material.Slate,
		Transparency = 0.15,
	})
	task.delay(life or 4, function()
		VFX.tween(scorch, 1, { Transparency = 1 })
	end)
	Debris:AddItem(scorch, (life or 4) + 1.1)
end

-- Cracks radiating out on the ground.
function VFX.cracks(pos: Vector3, count: number, length: number, life: number?)
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + random:NextNumber(-0.3, 0.3)
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local len = length * random:NextNumber(0.6, 1.2)
		VFX.groundScar(pos + dir * (len / 2 + 1), dir, len, random:NextNumber(0.2, 0.45), life)
	end
end

----------------------------------------------------------------------
-- Character effects
----------------------------------------------------------------------

-- Red/black flaming aura. Returns a function that stops it.
function VFX.aura(character: Model, strength: number?)
	local intensity = strength or 1
	local emitters = {}
	local function addTo(partName: string, rate: number, size: number)
		local part = character:FindFirstChild(partName)
		if not part or not part:IsA("BasePart") then
			return
		end
		table.insert(emitters, VFX.emitter(part, {
			Texture = VFX.Textures.Fire,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 60, 70)),
				ColorSequenceKeypoint.new(0.5, C.Curse),
				ColorSequenceKeypoint.new(1, C.Black),
			}),
			LightEmission = 0.7,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(2, 5),
			Acceleration = Vector3.new(0, 14, 0),
			Rate = rate * intensity,
			SpreadAngle = Vector2.new(25, 25),
			RotSpeed = NumberRange.new(-90, 90),
			Rotation = NumberRange.new(0, 360),
			Enabled = true,
		}))
		table.insert(emitters, VFX.emitter(part, {
			Texture = VFX.Textures.Smoke,
			Color = ColorSequence.new(C.Black),
			LightEmission = 0,
			LightInfluence = 1,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.8), NumberSequenceKeypoint.new(1, size * 1.6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(1, 3),
			Acceleration = Vector3.new(0, 8, 0),
			Rate = rate * 0.4 * intensity,
			Enabled = true,
		}))
	end
	addTo("UpperTorso", 40, 1.6)
	addTo("LowerTorso", 22, 1.3)
	addTo("RightLowerArm", 14, 0.8)
	addTo("LeftLowerArm", 14, 0.8)
	addTo("RightLowerLeg", 10, 0.8)
	addTo("LeftLowerLeg", 10, 0.8)
	return function()
		for _, e in emitters do
			e.Enabled = false
			Debris:AddItem(e, 1.2)
		end
	end
end

function VFX.highlight(character: Model, color: Color3, life: number, fill: number?)
	local h = Instance.new("Highlight")
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = fill or 0.6
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = character
	h.Parent = VFX.folder()
	VFX.tween(h, life, { FillTransparency = 1, OutlineTransparency = 1 }, "Quad", "In")
	Debris:AddItem(h, life + 0.05)
	return h
end

-- Neon ghost copies of the body (dash afterimage).
function VFX.afterimage(character: Model, color: Color3?, life: number?)
	for _, child in character:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" and child.Transparency < 1 then
			local ok, ghost = pcall(function()
				local was = child.Archivable
				child.Archivable = true
				local clone = child:Clone()
				child.Archivable = was
				return clone
			end)
			if ok and ghost then
				ghost:ClearAllChildren()
				ghost.Anchored = true
				ghost.CanCollide = false
				ghost.CanQuery = false
				ghost.CanTouch = false
				ghost.CastShadow = false
				ghost.Massless = true
				ghost.Material = Enum.Material.ForceField
				ghost.Color = color or C.Curse
				ghost.Transparency = 0.1
				ghost.CFrame = child.CFrame
				if ghost:IsA("MeshPart") then
					ghost.TextureID = ""
				end
				ghost.Parent = VFX.folder()
				VFX.tween(ghost, life or 0.35, { Transparency = 1 }, "Quad", "In")
				Debris:AddItem(ghost, (life or 0.35) + 0.05)
			end
		end
	end
end

return VFX
