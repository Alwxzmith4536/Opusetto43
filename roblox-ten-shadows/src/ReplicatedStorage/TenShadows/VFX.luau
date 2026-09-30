-- Client-side visual effects. The server fires FX("<Effect>", params) and every client runs
-- VFX.Effects[<Effect>](params) locally, so tweens and particles are smooth and never cost
-- server bandwidth. Damage and timing stay on the server.

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(script.Parent.Config)
local ModelFactory = require(script.Parent.ModelFactory)

local VFX = {}
VFX.Effects = {}

local TEX = Config.Textures
local UP = Vector3.new(0, 1, 0)
local SHADOW = Color3.fromRGB(14, 12, 20)
local SHADOW_RIM = Color3.fromRGB(120, 70, 200)
local GOLD = Color3.fromRGB(255, 214, 120)
local BLADE = Color3.fromRGB(255, 246, 222)
local RED = Color3.fromRGB(255, 60, 60)

---------------------------------------------------------------- helpers

local fxFolder
local function folder()
	if not fxFolder or not fxFolder.Parent then
		fxFolder = Instance.new("Folder")
		fxFolder.Name = "TenShadowsFX"
		fxFolder.Parent = workspace
	end
	return fxFolder
end

local function tween(inst, t, props, style, dir)
	local tw = TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function newPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = folder()
	return p
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function dirTo(a, b)
	local d = flat(b - a)
	if d.Magnitude < 0.01 then
		return Vector3.new(0, 0, -1)
	end
	return d.Unit
end

-- A flat disc lying on the ground (Roblox cylinders run along X, so turn it up).
local function discCFrame(pos)
	return CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
end

local function sound(id, pos, volume, speed)
	if not id then
		return
	end
	local holder = newPart({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(pos) })
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.8
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 300
	s.Parent = holder
	s:Play()
	Debris:AddItem(holder, 4)
end
VFX.Sound = sound

-- One-shot particle burst at a position.
local function burst(pos, opts)
	local holder = newPart({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = opts.CFrame or CFrame.new(pos) })
	local att = Instance.new("Attachment")
	att.Parent = holder
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = opts.Texture or TEX.Spark
	pe.Color = ColorSequence.new(opts.Color or Color3.new(1, 1, 1), opts.Color2 or opts.Color or Color3.new(1, 1, 1))
	pe.LightEmission = opts.LightEmission or 1
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, opts.Size or 1),
		NumberSequenceKeypoint.new(1, opts.EndSize or 0),
	})
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, opts.Transparency or 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Lifetime = NumberRange.new(opts.Lifetime or 0.4, (opts.Lifetime or 0.4) * 1.6)
	pe.Speed = NumberRange.new(opts.Speed or 20, (opts.Speed or 20) * 1.8)
	pe.SpreadAngle = Vector2.new(opts.Spread or 180, opts.Spread or 180)
	pe.Acceleration = opts.Acceleration or Vector3.zero
	pe.Drag = opts.Drag or 3
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-180, 180)
	pe.EmissionDirection = opts.Direction or Enum.NormalId.Top
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(opts.Count or 20)
	Debris:AddItem(holder, (opts.Lifetime or 0.4) * 2 + 0.5)
	return pe
end
VFX.Burst = burst

local function smoke(pos, color, count, size, speed)
	return burst(pos, {
		Texture = TEX.Smoke, Color = color or SHADOW, Count = count or 16, Size = size or 4, EndSize = (size or 4) * 1.8,
		Lifetime = 0.9, Speed = speed or 6, LightEmission = 0, Transparency = 0.15,
		Acceleration = Vector3.new(0, 4, 0),
	})
end

local function sparks(pos, color, count, speed)
	return burst(pos, { Texture = TEX.Spark, Color = color, Count = count or 24, Size = 0.9, Lifetime = 0.35, Speed = speed or 40 })
end

local function flashSphere(pos, color, size, t)
	local p = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one, CFrame = CFrame.new(pos), Color = color, Transparency = 0.1 })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = size * 2
	light.Brightness = 4
	light.Parent = p
	tween(p, t or 0.35, { Size = Vector3.one * size, Transparency = 1 })
	tween(light, t or 0.35, { Brightness = 0 })
	Debris:AddItem(p, (t or 0.35) + 0.1)
end
VFX.Flash = flashSphere

-- Ring of shards flying outward: reads as a shockwave from any camera angle.
local function shockRing(pos, radius, color, t, segments, height)
	segments = segments or 28
	t = t or 0.5
	for i = 1, segments do
		local a = (i / segments) * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local startCF = CFrame.lookAt(pos + dir * 1.5 + UP * 0.4, pos + dir * 3 + UP * 0.4)
		local p = newPart({
			Size = Vector3.new(radius * 0.18, height or 0.6, 0.6), CFrame = startCF, Color = color, Transparency = 0.05,
		})
		tween(p, t, { CFrame = startCF + dir * radius, Transparency = 1, Size = Vector3.new(radius * 0.12, 0.15, 0.3) })
		Debris:AddItem(p, t + 0.1)
	end
	local disc = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2, 2), CFrame = discCFrame(pos + UP * 0.1), Color = color, Transparency = 0.45 })
	tween(disc, t, { Size = Vector3.new(0.15, radius * 2, radius * 2), Transparency = 1 })
	Debris:AddItem(disc, t + 0.1)
end
VFX.ShockRing = shockRing

local function rocks(pos, count, spread, color)
	for _ = 1, count do
		local s = math.random(6, 16) / 10
		local p = newPart({
			Size = Vector3.new(s, s, s), CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = color or Color3.fromRGB(58, 54, 66), Material = Enum.Material.Slate,
		})
		local out = Vector3.new(math.random(-100, 100), 0, math.random(-100, 100)).Unit * (spread * (0.4 + math.random() * 0.6))
		local peak = pos + out * 0.5 + UP * math.random(6, 14)
		tween(p, 0.3, { CFrame = CFrame.new(peak) * CFrame.Angles(math.random() * 6, 0, math.random() * 6) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.3, function()
			tween(p, 0.35, { CFrame = CFrame.new(pos + out - UP * 0.2), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		Debris:AddItem(p, 0.8)
	end
end

-- Jagged lightning bolt between two points.
local function bolt(p0, p1, color, width, t)
	local segments = math.max(4, math.floor((p1 - p0).Magnitude / 5))
	local last = p0
	for i = 1, segments do
		local alpha = i / segments
		local target = p0:Lerp(p1, alpha)
		if i < segments then
			target += Vector3.new(math.random(-20, 20) / 10, math.random(-20, 20) / 10, math.random(-20, 20) / 10)
		end
		local len = (target - last).Magnitude
		local p = newPart({
			Size = Vector3.new(width, width, len), CFrame = CFrame.lookAt((last + target) / 2, target), Color = color, Transparency = 0,
		})
		tween(p, t or 0.25, { Transparency = 1, Size = Vector3.new(width * 0.2, width * 0.2, len) })
		Debris:AddItem(p, (t or 0.25) + 0.1)
		last = target
	end
end
VFX.Bolt = bolt

-- Crescent slash arc. cf = center + facing; the arc sweeps across cf's X axis.
local function slashArc(cf, radius, color, span, t, thickness, tilt)
	span = span or 150
	t = t or 0.25
	local pieces = 14
	local base = cf * CFrame.Angles(0, 0, math.rad(tilt or 0))
	for i = 0, pieces do
		local a = math.rad(-span / 2 + span * (i / pieces))
		local mid = 1 - math.abs(i / pieces - 0.5) * 2 -- thick in the middle, thin at the tips
		local pos = (base * CFrame.new(math.sin(a) * radius, 0, -math.cos(a) * radius)).Position
		local tangent = (base * CFrame.new(math.sin(a + 0.1) * radius, 0, -math.cos(a + 0.1) * radius)).Position
		local seg = (2 * math.pi * radius) * (span / 360) / pieces * 1.25
		local p = newPart({
			Size = Vector3.new((thickness or 0.5) * (0.3 + mid), 0.12 + mid * 0.5, seg),
			CFrame = CFrame.lookAt(pos, tangent, base.UpVector),
			Color = color, Transparency = 1,
		})
		task.delay(t * 0.35 * (i / pieces), function()
			p.Transparency = 0
			tween(p, t, { Transparency = 1, CFrame = p.CFrame + (pos - base.Position).Unit * radius * 0.15 })
		end)
		Debris:AddItem(p, t * 1.5 + 0.2)
	end
end
VFX.SlashArc = slashArc

-- Smoothly moves an anchored model. Returns the tween.
local function moveModel(model, toCF, t, style, dir)
	local value = Instance.new("CFrameValue")
	value.Value = model:GetPivot()
	value.Changed:Connect(function(cf)
		if model.Parent then
			model:PivotTo(cf)
		end
	end)
	local tw = tween(value, t, { Value = toCF }, style, dir)
	tw.Completed:Connect(function()
		value:Destroy()
	end)
	return tw
end
VFX.MoveModel = moveModel

local function fadeModel(model, t)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			tween(d, t, { Transparency = 1 })
		end
	end
	Debris:AddItem(model, t + 0.1)
end

-- Shadow puddle: every shikigami enters and leaves the world through Megumi's shadow.
local function puddle(pos, radius, life)
	life = life or 1.2
	local ground = pos * Vector3.new(1, 0, 1) + Vector3.new(0, pos.Y + 0.08, 0)
	local rim = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.5, 0.5), CFrame = discCFrame(ground), Color = SHADOW_RIM, Transparency = 0.35 })
	local disc = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 0.4, 0.4), CFrame = discCFrame(ground + UP * 0.02), Color = SHADOW, Material = Enum.Material.SmoothPlastic, Reflectance = 0.2 })
	tween(rim, 0.25, { Size = Vector3.new(0.12, radius * 2 + 1.2, radius * 2 + 1.2) }, Enum.EasingStyle.Back)
	tween(disc, 0.25, { Size = Vector3.new(0.16, radius * 2, radius * 2) }, Enum.EasingStyle.Back)
	burst(ground, {
		Texture = TEX.Smoke, Color = SHADOW, Color2 = SHADOW_RIM, Count = 10, Size = radius * 0.7, EndSize = radius * 1.2,
		Lifetime = 0.8, Speed = 4, LightEmission = 0, Transparency = 0.2, Acceleration = Vector3.new(0, 6, 0), Spread = 30,
	})
	task.delay(life, function()
		tween(rim, 0.3, { Size = Vector3.new(0.12, 0.1, 0.1), Transparency = 1 })
		tween(disc, 0.3, { Size = Vector3.new(0.16, 0.1, 0.1), Transparency = 1 })
		Debris:AddItem(rim, 0.4)
		Debris:AddItem(disc, 0.4)
	end)
end
VFX.Puddle = puddle

-- Spawns a model under the ground and rises it out of a shadow puddle.
local function emerge(name, groundCF, opts)
	opts = opts or {}
	local scale = opts.Scale or 1
	local height = ModelFactory.Height(name) * scale
	local model = ModelFactory.Build(name, { CFrame = groundCF - UP * (height + 0.5), Scale = scale, Parent = folder() })
	puddle(groundCF.Position, opts.PuddleRadius or math.max(3, height * 0.45), opts.PuddleLife or 1)
	moveModel(model, groundCF, opts.Time or 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	return model, height
end

local function sink(model, height, t)
	if not model.Parent then
		return
	end
	t = t or 0.35
	local cf = model:GetPivot()
	puddle(cf.Position * Vector3.new(1, 0, 1) + Vector3.new(0, cf.Position.Y, 0), math.max(3, height * 0.45), t + 0.1)
	moveModel(model, cf - UP * (height + 1), t, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(model, t + 0.05)
end

-- Hop along an arc (for dogs, tiger, etc).
local function leap(model, toCF, t, height)
	local fromCF = model:GetPivot()
	local value = Instance.new("NumberValue")
	value.Changed:Connect(function(a)
		if model.Parent then
			local cf = fromCF:Lerp(toCF, a)
			model:PivotTo(cf + UP * (math.sin(a * math.pi) * height))
		end
	end)
	local tw = tween(value, t, { Value = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	tw.Completed:Connect(function()
		value:Destroy()
	end)
	return tw
end

local function ground(pos)
	return Vector3.new(pos.X, 0, pos.Z)
end

---------------------------------------------------------------- camera shake / screen flash

local shakes = {}
function VFX.Shake(intensity, duration, pos)
	if pos then
		local cam = workspace.CurrentCamera
		local dist = cam and (cam.CFrame.Position - pos).Magnitude or 0
		intensity *= math.clamp(1 - dist / 220, 0, 1)
	end
	if intensity > 0.02 then
		table.insert(shakes, { I = intensity, T = duration, Start = time() })
	end
end

local colorCorrection
function VFX.ScreenFlash(color, strength, t)
	if not colorCorrection or not colorCorrection.Parent then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "TenShadowsFlash"
		colorCorrection.Parent = Lighting
	end
	colorCorrection.TintColor = color
	colorCorrection.Brightness = strength or 0.3
	tween(colorCorrection, t or 0.4, { TintColor = Color3.new(1, 1, 1), Brightness = 0 })
end

local started = false
function VFX.Init()
	if started or not RunService:IsClient() then
		return
	end
	started = true
	RunService:BindToRenderStep("TenShadowsShake", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		if not cam or #shakes == 0 then
			return
		end
		local now = time()
		local total = 0
		for i = #shakes, 1, -1 do
			local s = shakes[i]
			local a = (now - s.Start) / s.T
			if a >= 1 then
				table.remove(shakes, i)
			else
				total += s.I * (1 - a)
			end
		end
		if total > 0 then
			total = math.min(total, 3)
			cam.CFrame *= CFrame.new(
				(math.random() - 0.5) * total, (math.random() - 0.5) * total, 0
			) * CFrame.Angles(0, 0, (math.random() - 0.5) * total * 0.02)
		end
	end)
end

---------------------------------------------------------------- generic effects

local E = VFX.Effects

function E.Summon(p)
	puddle(p.Pos, p.Radius or 4, p.Life or 1)
	sound(Config.Sounds.Summon, p.Pos, 0.4, 0.6)
end

function E.Hit(p)
	local color = p.Color or Color3.new(1, 1, 1)
	sparks(p.Pos, color, p.Big and 40 or 18, p.Big and 60 or 35)
	flashSphere(p.Pos, color, p.Big and 9 or 4, 0.2)
	if p.Big then
		VFX.Shake(0.5, 0.25, p.Pos)
	end
end

function E.DamageNumber(p)
	local holder = newPart({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(p.Pos + Vector3.new(math.random(-15, 15) / 10, 1, 0)) })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(160, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = p.Color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = (p.Amount and tostring(p.Amount) or "") .. (p.Note and (" " .. p.Note) or "")
	label.Parent = gui
	tween(holder, 0.9, { CFrame = holder.CFrame + UP * 5 })
	tween(label, 0.9, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(holder, 1)
end

function E.Heal(p)
	burst(p.Pos, { Color = Color3.fromRGB(150, 255, 170), Color2 = GOLD, Count = 30, Size = 0.8, Lifetime = 0.9, Speed = 8, Acceleration = Vector3.new(0, 12, 0) })
end

function E.Blade(p)
	local cf = p.CFrame
	local finisher = p.Combo == 4
	local tilt = ({ -20, 20, -60, 0 })[p.Combo] or 0
	slashArc(cf * CFrame.new(0, 0, -1), finisher and 8 or 6, Color3.fromRGB(205, 190, 255), finisher and 200 or 140, 0.22, finisher and 0.9 or 0.5, tilt)
	sound(Config.Sounds.Slash, cf.Position, 0.5, 0.9 + p.Combo * 0.08)
	if finisher then
		smoke(cf.Position + cf.LookVector * 5, SHADOW, 8, 3, 10)
	end
end

function E.ShadowStep(p)
	puddle(p.From, 4, 0.6)
	smoke(p.From + UP * 2, SHADOW, 20, 3.5, 10)
	task.delay(0.18, function()
		puddle(p.To, 4, 0.6)
		smoke(p.To + UP * 2, SHADOW, 16, 3, 8)
		burst(p.To + UP, { Color = SHADOW_RIM, Count = 18, Size = 0.6, Speed = 25, Lifetime = 0.3 })
	end)
end

function E.Chant(p)
	-- dark spiral climbing around the summoner while they chant
	for i = 1, 16 do
		task.delay(i * 0.06, function()
			local a = i * 0.8
			local pos = p.Pos + Vector3.new(math.cos(a) * 4, i * 0.5, math.sin(a) * 4)
			burst(pos, { Texture = TEX.Smoke, Color = SHADOW, Color2 = SHADOW_RIM, Count = 3, Size = 2, EndSize = 3, Lifetime = 0.7, Speed = 2, LightEmission = 0.2 })
		end)
	end
	puddle(p.Pos, 7, 1.4)
end

---------------------------------------------------------------- shikigami

local activeDogs = {}

function E.DivineDogs(p)
	local look = dirTo(p.Origin, p.Target)
	local right = look:Cross(UP)
	local dogs = {
		{ Name = "DivineDogWhite", Side = -1, Id = p.WhiteId },
		{ Name = "DivineDogBlack", Side = 1, Id = p.BlackId },
	}
	for i, d in ipairs(dogs) do
		if d.Id then
			task.spawn(function()
				local start = ground(p.Origin) + right * d.Side * 4
				local dog, h = emerge(d.Name, CFrame.lookAt(start, start + look), { Time = 0.25 })
				activeDogs[d.Id] = { Model = dog, Height = h }
				task.wait(0.28 + i * 0.05)
				local land = ground(p.Target) - look * 3 + right * d.Side * 2
				leap(dog, CFrame.lookAt(land, land + look), 0.32, 4)
				task.wait(0.32)
				for bite = 1, p.Bites or 2 do
					slashArc(CFrame.lookAt(land + UP * 3, p.Target + UP * 3), 3, d.Side < 0 and Color3.new(1, 1, 1) or SHADOW_RIM, 120, 0.18, 0.4, d.Side * 40)
					sparks(p.Target + UP * 2, Color3.new(1, 1, 1), 12, 30)
					sound(Config.Sounds.Hit, p.Target, 0.4, 1.3)
					if bite == 1 then
						moveModel(dog, dog:GetPivot() * CFrame.new(0, 0, 1.2), 0.12)
					end
					task.wait(0.2)
				end
				-- guard: stay beside the target until the guard time ends or the dog is destroyed
				task.wait(p.Guard or 6)
				if activeDogs[d.Id] and activeDogs[d.Id].Model == dog then
					activeDogs[d.Id] = nil
					sink(dog, h)
				end
			end)
		end
	end
end

function E.DogDestroyed(p)
	local entry = activeDogs[p.Id]
	local pos = p.Pos
	if entry then
		activeDogs[p.Id] = nil
		pos = entry.Model:GetPivot().Position
		for _, part in ipairs(entry.Model:GetDescendants()) do
			if part:IsA("BasePart") and part.Transparency < 1 then
				part.Anchored = true
				local out = (part.Position - pos + Vector3.new(0, 1, 0)).Unit
				tween(part, 0.6, { CFrame = part.CFrame + out * math.random(4, 9), Transparency = 1 })
			end
		end
		Debris:AddItem(entry.Model, 0.7)
	end
	smoke(pos + UP * 2, Color3.fromRGB(230, 230, 235), 18, 3, 10)
	sparks(pos + UP * 2, Color3.new(1, 1, 1), 30, 40)
end

function E.Nue(p)
	local look = dirTo(p.Origin, p.Target)
	local start = ground(p.Origin) - look * 3
	local nue = emerge("Nue", CFrame.lookAt(start, start + look), { Time = 0.25 })
	task.wait(0.25)
	local high = p.Target + UP * 28 - look * 10
	moveModel(nue, CFrame.lookAt(high, high + look), 0.45, Enum.EasingStyle.Sine)
	for _ = 1, 3 do
		bolt(p.Origin + UP * 4, high + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3)), Config.DamageTypes.Lightning.Color, 0.25, 0.3)
	end
	task.wait(0.45)
	local dive = p.Target + UP * 3
	moveModel(nue, CFrame.lookAt(dive, dive + look) * CFrame.Angles(math.rad(-35), 0, 0), 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.18)
	local c = Config.DamageTypes.Lightning.Color
	for _ = 1, 6 do
		bolt(p.Target + Vector3.new(math.random(-12, 12), 70, math.random(-12, 12)), p.Target, c, 0.6, 0.35)
	end
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2
		bolt(p.Target + UP, p.Target + Vector3.new(math.cos(a), 0.2, math.sin(a)) * (p.Radius or 12), c, 0.35, 0.3)
	end
	flashSphere(p.Target + UP * 2, c, (p.Radius or 12) * 1.6, 0.35)
	shockRing(p.Target, (p.Radius or 12) * 1.3, c, 0.45)
	sparks(p.Target + UP * 2, c, 50, 70)
	VFX.ScreenFlash(Color3.fromRGB(200, 230, 255), 0.35, 0.35)
	VFX.Shake(0.9, 0.35, p.Target)
	sound(Config.Sounds.Summon, p.Target, 1, 0.35)
	task.wait(0.15)
	local away = p.Target + UP * 40 + look * 30
	moveModel(nue, CFrame.lookAt(away, away + look), 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	fadeModel(nue, 0.6)
end

function E.Toad(p)
	local look = dirTo(p.Origin, p.Target)
	local spot = ground(p.Origin) + look * 5
	local toadModel, h = emerge("Toad", CFrame.lookAt(spot, spot + look), { Time = 0.22 })
	task.wait(0.25)
	local mouth = spot + look * 3.4 + UP * 2.8
	local tongue = newPart({ Size = Vector3.new(0.8, 0.8, 0.2), Color = Color3.fromRGB(220, 110, 140), Material = Enum.Material.SmoothPlastic })
	local function place(tip)
		local len = (tip - mouth).Magnitude
		tongue.Size = Vector3.new(0.8, 0.8, math.max(0.2, len))
		tongue.CFrame = CFrame.lookAt((mouth + tip) / 2, tip)
	end
	local value = Instance.new("Vector3Value")
	value.Value = mouth
	value.Changed:Connect(place)
	tween(value, 0.14, { Value = p.Target + UP * 2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	task.wait(0.16)
	sparks(p.Target + UP * 2, Color3.fromRGB(220, 110, 140), 16, 25)
	sound(Config.Sounds.Lunge, p.Target, 0.6, 0.8)
	task.wait(0.08)
	tween(value, 0.35, { Value = mouth }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.36)
	tongue:Destroy()
	value:Destroy()
	task.wait(0.3)
	sink(toadModel, h)
end

function E.GreatSerpent(p)
	local target = ground(p.Target)
	puddle(target, (p.Radius or 8) + 1, 1.6)
	VFX.Shake(0.35, 0.4, target)
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		bolt(target, target + Vector3.new(math.cos(a), 0.1, math.sin(a)) * (p.Radius or 8) * 1.2, SHADOW_RIM, 0.3, 0.5)
	end
	task.wait(0.35)
	local look = p.Look or Vector3.new(0, 0, -1)
	local serpent = ModelFactory.Build("GreatSerpent", { CFrame = CFrame.lookAt(target + look * 3 - UP * 26, target + look * 3 - UP * 26 - look), Parent = folder() })
	local topCF = CFrame.lookAt(target + look * 3 - UP * 3, target + look * 3 - UP * 3 - look)
	moveModel(serpent, topCF, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	rocks(target, 14, p.Radius or 8)
	smoke(target + UP, Color3.fromRGB(70, 62, 80), 22, 5, 14)
	task.wait(0.2)
	sparks(target + UP * 10, Config.DamageTypes.Bite.Color, 40, 50)
	flashSphere(target + UP * 8, Config.DamageTypes.Bite.Color, 14, 0.25)
	VFX.Shake(1.0, 0.4, target)
	sound(Config.Sounds.Hit, target, 1, 0.6)
	task.wait(0.8)
	moveModel(serpent, topCF - UP * 26, 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	puddle(target, (p.Radius or 8) + 1, 0.5)
	Debris:AddItem(serpent, 0.6)
end

function E.MaxElephant(p)
	local look = flat(p.Dir).Unit
	local drop = ground(p.Origin) + look * 16
	local elephant = ModelFactory.Build("MaxElephant", { CFrame = CFrame.lookAt(drop + UP * 60, drop + UP * 60 + look), Parent = folder() })
	puddle(drop + UP * 60, 10, 0.6)
	moveModel(elephant, CFrame.lookAt(drop, drop + look), 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(0.5)
	VFX.Shake(1.4, 0.6, drop)
	shockRing(drop, 26, Color3.fromRGB(150, 200, 255), 0.5)
	rocks(drop, 16, 16)
	sound(Config.Sounds.Hit, drop, 1, 0.4)
	-- the flood: a cone of water that races forward
	local water = Config.DamageTypes.Water.Color
	local range = p.Range or 60
	local half = math.rad((p.Angle or 70) / 2)
	for wave = 0, 2 do
		task.delay(wave * 0.12, function()
			for i = -6, 6 do
				local a = half * (i / 6)
				local dir = CFrame.fromAxisAngle(UP, a):VectorToWorldSpace(look)
				local start = drop + look * 8 + UP * 2
				local block = newPart({
					Size = Vector3.new(7, 5, 5), CFrame = CFrame.lookAt(start, start + dir),
					Color = water, Material = Enum.Material.Glass, Transparency = 0.25,
				})
				tween(block, 0.75, {
					CFrame = CFrame.lookAt(start + dir * range, start + dir * (range + 1)) + UP * (math.random(-10, 10) / 10),
					Size = Vector3.new(12, 1, 8), Transparency = 1,
				}, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				Debris:AddItem(block, 0.8)
			end
			local spray = drop + look * 10 + UP * 3
			burst(spray, {
				Texture = TEX.Smoke, Color = Color3.fromRGB(200, 230, 255), Count = 30, Size = 4, EndSize = 7,
				Lifetime = 0.8, Speed = 60, LightEmission = 0.3, Transparency = 0.3, Spread = 35, Direction = Enum.NormalId.Front,
				CFrame = CFrame.lookAt(spray, spray + look),
			})
		end)
	end
	sparks(drop + UP * 8, water, 60, 60)
	task.wait(1.4)
	sink(elephant, ModelFactory.Height("MaxElephant"), 0.6)
end

function E.RabbitEscape(p)
	local center = ground(p.Origin)
	puddle(center, 6, 0.8)
	smoke(center + UP * 2, Color3.fromRGB(240, 240, 240), 25, 3, 18)
	local radius = p.Radius or 18
	for _ = 1, 36 do
		task.spawn(function()
			local a = math.random() * math.pi * 2
			local start = center + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(1, 3)
			local rabbitModel = ModelFactory.Build("Rabbit", { CFrame = CFrame.new(start) * CFrame.Angles(0, -a, 0), Scale = 1.2, Parent = folder() })
			local stop = time() + (p.Duration or 5)
			while time() < stop and rabbitModel.Parent do
				local b = math.random() * math.pi * 2
				local dest = center + Vector3.new(math.cos(b), 0, math.sin(b)) * math.random(2, radius)
				local from = rabbitModel:GetPivot().Position
				local d = dirTo(from, dest)
				local step = from + d * math.min(6, (dest - from).Magnitude)
				local t = 0.22 + math.random() * 0.1
				leap(rabbitModel, CFrame.lookAt(step, step + d), t, 1.5)
				task.wait(t + math.random() * 0.15)
			end
			smoke(rabbitModel:GetPivot().Position + UP, Color3.fromRGB(240, 240, 240), 3, 1.5, 4)
			rabbitModel:Destroy()
		end)
	end
end

function E.RoundDeer(p)
	local look = flat(p.Look or Vector3.new(0, 0, -1)).Unit
	local spot = ground(p.Origin) - look * 6
	local deer, h = emerge("RoundDeer", CFrame.lookAt(spot, spot + look), { Time = 0.35 })
	flashSphere(spot + UP * 5.2 - look * 1.6, GOLD, 10, 0.6)
	local duration = p.Duration or 3
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local att = Instance.new("Attachment")
		att.Parent = root
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = TEX.Spark
		pe.Color = ColorSequence.new(Color3.fromRGB(160, 255, 180), GOLD)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new(0.6, 0)
		pe.Lifetime = NumberRange.new(0.8, 1.2)
		pe.Speed = NumberRange.new(2, 5)
		pe.Acceleration = Vector3.new(0, 8, 0)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Rate = 45
		pe.Parent = att
		local light = Instance.new("PointLight")
		light.Color = GOLD
		light.Range = 12
		light.Brightness = 2
		light.Parent = root
		task.delay(duration, function()
			pe.Enabled = false
			light:Destroy()
			Debris:AddItem(att, 1.5)
		end)
	end
	for i = 1, math.floor(duration / 0.5) do
		task.delay(i * 0.5, function()
			shockRing(spot + UP * 0.2, 8, GOLD, 0.6, 16, 0.3)
		end)
	end
	task.wait(duration)
	sink(deer, h, 0.5)
end

function E.PiercingOx(p)
	local look = dirTo(p.From, p.To)
	local start = ground(p.From) - look * 4
	local ox, h = emerge("PiercingOx", CFrame.lookAt(start, start + look), { Time = 0.22 })
	task.wait(0.28)
	local stop = ground(p.To)
	local dist = (stop - start).Magnitude
	local t = math.max(0.15, dist / (p.Speed or 150))
	moveModel(ox, CFrame.lookAt(stop, stop + look), t, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- dust trail + speed lines while charging
	local steps = math.floor(t / 0.04)
	for i = 1, steps do
		task.delay(i * 0.04, function()
			local pos = start:Lerp(stop, (i / steps) ^ 2)
			smoke(pos + UP, Color3.fromRGB(90, 80, 70), 3, 3, 4)
			local line = newPart({ Size = Vector3.new(0.2, 0.2, 10), CFrame = CFrame.lookAt(pos + UP * math.random(2, 7) + look:Cross(UP) * math.random(-4, 4), pos + look * 20 + UP * 4), Color = Color3.new(1, 1, 1), Transparency = 0.3 })
			tween(line, 0.25, { Transparency = 1, Size = Vector3.new(0.05, 0.05, 20) })
			Debris:AddItem(line, 0.3)
		end)
	end
	task.wait(t)
	local c = Config.DamageTypes.Pierce.Color
	flashSphere(stop + UP * 4, c, 16, 0.3)
	shockRing(stop, 18, c, 0.4)
	rocks(stop, 12, 10)
	sparks(stop + UP * 3, c, 45, 60)
	VFX.Shake(1.1, 0.4, stop)
	sound(Config.Sounds.Hit, stop, 1, 0.5)
	task.wait(0.4)
	sink(ox, h)
end

local function clawCombo(model, height, target, hits, color, interval, size)
	for i = 1, hits do
		local side = (i % 2 == 0) and 1 or -1
		for k = -1, 1 do
			slashArc(CFrame.lookAt(target + UP * (3 + k * 0.9), target + UP * 3 + model:GetPivot().LookVector * 2), size, color, 70, 0.2, 0.35, side * 55)
		end
		sparks(target + UP * 2, color, 20, 40)
		sound(Config.Sounds.Slash, target, 0.6, 0.8 + i * 0.05)
		VFX.Shake(0.25, 0.15, target)
		task.wait(interval)
	end
end

function E.TigerFuneral(p)
	local look = dirTo(p.Origin, p.Target)
	local start = ground(p.Origin) + look * 3
	local tiger, h = emerge("TigerFuneral", CFrame.lookAt(start, start + look), { Time = 0.22 })
	task.wait(0.25)
	local land = ground(p.Target) - look * 4
	leap(tiger, CFrame.lookAt(land, land + look), 0.3, 7)
	task.wait(0.3)
	clawCombo(tiger, h, p.Target, p.Hits or 3, Config.DamageTypes.Rend.Color, 0.14, 5)
	task.wait(0.3)
	sink(tiger, h)
end

function E.Totality(p)
	local look = dirTo(p.Origin, p.Target)
	local start = ground(p.Origin) - look * 2
	local dog, h = emerge("DivineDogTotality", CFrame.lookAt(start, start + look), { Time = 0.35 })
	smoke(start + UP * 4, SHADOW, 30, 6, 12)
	VFX.Shake(0.6, 0.5, start)
	sound(Config.Sounds.Summon, start, 1, 0.3)
	task.wait(0.4)
	local land = ground(p.Target) - look * 7
	leap(dog, CFrame.lookAt(land, land + look), 0.32, 8)
	task.wait(0.32)
	shockRing(land, 14, SHADOW_RIM, 0.4)
	clawCombo(dog, h, p.Target, p.Hits or 5, Color3.fromRGB(210, 190, 255), 0.13, 8)
	flashSphere(p.Target + UP * 3, Color3.fromRGB(210, 190, 255), 14, 0.3)
	task.wait(0.3)
	sink(dog, h, 0.5)
end

-- Short-lived strikers used by the domain, Agito and tamed Mahoraga: rise next to the target,
-- strike once, sink again.
local function strikeFromShadow(name, pos, target, scale, color, arcRadius, big)
	local look = dirTo(pos, target)
	local model, h = emerge(name, CFrame.lookAt(ground(pos), ground(pos) + look), { Time = 0.18, Scale = scale })
	task.wait(0.2)
	local tilt = math.random(-50, 50)
	slashArc(CFrame.lookAt(target + UP * 3, target + UP * 3 + look), arcRadius, color, big and 190 or 130, 0.25, big and 1.2 or 0.5, tilt)
	sparks(target + UP * 2, color, big and 50 or 20, big and 60 or 35)
	if big then
		flashSphere(target + UP * 4, color, 18, 0.3)
		shockRing(ground(target), 20, color, 0.45)
		VFX.Shake(0.9, 0.35, target)
		VFX.ScreenFlash(Color3.fromRGB(255, 250, 230), 0.2, 0.3)
	end
	sound(Config.Sounds.Slash, target, big and 1 or 0.5, big and 0.6 or 1.1)
	task.wait(big and 0.45 or 0.25)
	sink(model, h, 0.3)
end

function E.DomainClone(p)
	strikeFromShadow("DivineDogBlack", p.Pos, p.Target, 0.9, SHADOW_RIM, 3.5, false)
end

function E.Agito(p)
	strikeFromShadow("Agito", p.Pos, p.Target, 1, Config.DamageTypes.Chimera.Color, 6, false)
	if p.CasterPos then
		E.Heal({ Pos = p.CasterPos })
	end
end

function E.TamedMahoraga(p)
	strikeFromShadow("MahoragaTamed", p.Pos, p.Target, 1, BLADE, 14, true)
end

local domainParts = {}
function E.Domain(p)
	local center = ground(p.Center)
	local radius = p.Radius or 60
	local duration = p.Duration or 15
	-- 1) the barrier snaps shut
	local shell = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4, CFrame = CFrame.new(center), Color = SHADOW, Material = Enum.Material.SmoothPlastic, Transparency = 0.05 })
	tween(shell, 0.5, { Size = Vector3.one * radius * 2.2, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(shell, 0.6)
	VFX.ScreenFlash(Color3.fromRGB(90, 60, 140), 0.1, 1.2)
	VFX.Shake(1.2, 0.6, center)
	-- 2) the floor turns into liquid shadow
	local floor = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2), CFrame = discCFrame(center + UP * 0.12), Color = Color3.fromRGB(8, 6, 14), Material = Enum.Material.Glass, Reflectance = 0.35, Transparency = 0.05 })
	local rim = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 2, 2), CFrame = discCFrame(center + UP * 0.1), Color = SHADOW_RIM, Transparency = 0.2 })
	tween(floor, 0.8, { Size = Vector3.new(0.2, radius * 2, radius * 2) }, Enum.EasingStyle.Quart)
	tween(rim, 0.8, { Size = Vector3.new(0.15, radius * 2 + 3, radius * 2 + 3) }, Enum.EasingStyle.Quart)
	local parts = { floor, rim }
	-- 3) shadow spires and bubbling smoke across the garden
	for i = 1, 22 do
		local a = math.random() * math.pi * 2
		local r = math.sqrt(math.random()) * radius * 0.95
		local pos = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local height = math.random(4, 14)
		local spire = newPart({ Size = Vector3.new(1.2, 0.2, 1.2), CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * 6, math.rad(math.random(-15, 15))), Color = SHADOW, Material = Enum.Material.SmoothPlastic, Transparency = 0 })
		tween(spire, 0.6 + math.random() * 0.4, { Size = Vector3.new(0.7, height, 0.7), CFrame = spire.CFrame + UP * height / 2 }, Enum.EasingStyle.Back)
		table.insert(parts, spire)
	end
	local holder = newPart({ Size = Vector3.new(radius * 1.6, 0.2, radius * 1.6), CFrame = CFrame.new(center + UP * 0.3), Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = TEX.Smoke
	pe.Color = ColorSequence.new(SHADOW, SHADOW_RIM)
	pe.Size = NumberSequence.new(3, 6)
	pe.Transparency = NumberSequence.new(0.4, 1)
	pe.Lifetime = NumberRange.new(1.5, 2.5)
	pe.Speed = NumberRange.new(1, 3)
	pe.Acceleration = Vector3.new(0, 3, 0)
	pe.Rate = 60
	pe.LightEmission = 0.1
	pe.Parent = holder
	table.insert(parts, holder)
	local id = p.Id or tostring(time())
	domainParts[id] = parts
	task.delay(duration, function()
		pe.Enabled = false
		for _, part in ipairs(parts) do
			tween(part, 0.8, { Transparency = 1 })
			Debris:AddItem(part, 2.6)
		end
		domainParts[id] = nil
	end)
end

---------------------------------------------------------------- Mahoraga

function E.TelegraphCircle(p)
	local pos = ground(p.Pos) + UP * 0.15
	local d = p.Radius * 2
	local outer = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, d, d), CFrame = discCFrame(pos), Color = RED, Transparency = 0.7 })
	local inner = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.5, 0.5), CFrame = discCFrame(pos + UP * 0.02), Color = RED, Transparency = 0.45 })
	tween(inner, p.Duration, { Size = Vector3.new(0.12, d, d) }, Enum.EasingStyle.Linear)
	Debris:AddItem(outer, p.Duration + 0.05)
	Debris:AddItem(inner, p.Duration + 0.05)
end

function E.TelegraphLine(p)
	local a, b = ground(p.From) + UP * 0.15, ground(p.To) + UP * 0.15
	local len = (b - a).Magnitude
	local outer = newPart({ Size = Vector3.new(p.Width, 0.1, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RED, Transparency = 0.7 })
	local inner = newPart({ Size = Vector3.new(p.Width, 0.12, 0.2), CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0.02, -0.1), Color = RED, Transparency = 0.45 })
	local value = Instance.new("NumberValue")
	value.Changed:Connect(function(v)
		local l = math.max(0.2, len * v)
		inner.Size = Vector3.new(p.Width, 0.12, l)
		inner.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0.02, -l / 2)
	end)
	tween(value, p.Duration, { Value = 1 }, Enum.EasingStyle.Linear)
	Debris:AddItem(outer, p.Duration + 0.05)
	Debris:AddItem(inner, p.Duration + 0.05)
	Debris:AddItem(value, p.Duration + 0.05)
end

function E.TelegraphCone(p)
	-- cone drawn as a fan of thin lines
	local origin = ground(p.Origin) + UP * 0.15
	local look = flat(p.Dir).Unit
	for i = -4, 4 do
		local a = math.rad(p.Angle / 2) * (i / 4)
		local dir = CFrame.fromAxisAngle(UP, a):VectorToWorldSpace(look)
		local b = origin + dir * p.Range
		local line = newPart({ Size = Vector3.new(i == 0 and 1.2 or 0.6, 0.1, p.Range), CFrame = CFrame.lookAt((origin + b) / 2, b), Color = RED, Transparency = 0.55 })
		tween(line, p.Duration, { Transparency = 0.2 }, Enum.EasingStyle.Linear)
		Debris:AddItem(line, p.Duration + 0.05)
	end
end

function E.BossSlash(p)
	local cf = p.CFrame
	local radius = p.Radius or 24
	for k = 0, 2 do
		slashArc(cf * CFrame.new(0, k * 1.2 - 1, 0), radius * (0.7 + k * 0.15), k == 1 and BLADE or GOLD, p.Span or 120, 0.35, 1.4 - k * 0.3, p.Tilt or -25)
	end
	sparks(cf.Position + cf.LookVector * radius * 0.6, BLADE, 50, 70)
	VFX.Shake(0.9, 0.3, cf.Position)
	sound(Config.Sounds.Slash, cf.Position, 1, 0.55)
end

function E.BossSlam(p)
	local pos = ground(p.Pos)
	flashSphere(pos + UP * 2, GOLD, p.Radius * 1.2, 0.3)
	shockRing(pos, p.Radius * 1.2, Color3.fromRGB(255, 230, 200), 0.5, 36, 1)
	shockRing(pos, p.Radius * 0.7, GOLD, 0.35)
	rocks(pos, 24, p.Radius * 0.8)
	smoke(pos + UP * 2, Color3.fromRGB(80, 74, 84), 30, 6, 20)
	VFX.Shake(1.8, 0.6, pos)
	sound(Config.Sounds.Hit, pos, 1, 0.35)
end

function E.BossDash(p)
	local a, b = p.From, p.To
	local dir = dirTo(a, b)
	for i = 0, 8 do
		local pos = a:Lerp(b, i / 8)
		local ghost = newPart({ Size = Vector3.new(6, 16, 3), CFrame = CFrame.lookAt(pos, pos + dir), Color = Color3.fromRGB(236, 233, 225), Transparency = 0.5 + i * 0.04, Material = Enum.Material.SmoothPlastic })
		tween(ghost, 0.4, { Transparency = 1, Size = Vector3.new(2, 14, 1) })
		Debris:AddItem(ghost, 0.45)
	end
	smoke(ground(a) + UP, Color3.fromRGB(90, 84, 96), 16, 4, 16)
	sound(Config.Sounds.Lunge, a, 1, 0.5)
end

function E.WorldSlash(p)
	local a, b = p.From, p.To
	local dir = dirTo(a, b)
	local len = (ground(b) - ground(a)).Magnitude
	local mid = (ground(a) + ground(b)) / 2 + UP * 12
	-- space itself splits: a white line, then the black cut
	local white = newPart({ Size = Vector3.new(0.3, 40, len), CFrame = CFrame.lookAt(mid, mid + dir), Color = Color3.new(1, 1, 1), Transparency = 0 })
	local black = newPart({ Size = Vector3.new(0.6, 40, len), CFrame = CFrame.lookAt(mid, mid + dir), Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic, Transparency = 1 })
	VFX.ScreenFlash(Color3.fromRGB(255, 255, 255), 0.5, 0.25)
	task.delay(0.08, function()
		white.Transparency = 1
		black.Transparency = 0
		tween(black, 0.6, { Size = Vector3.new(0.05, 40, len), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end)
	Debris:AddItem(white, 0.2)
	Debris:AddItem(black, 0.8)
	for i = 0, 10 do
		local pos = ground(a):Lerp(ground(b), i / 10)
		task.delay(i * 0.02, function()
			sparks(pos + UP * 2, BLADE, 14, 50)
			smoke(pos + UP, Color3.fromRGB(70, 66, 76), 5, 4, 12)
		end)
	end
	VFX.Shake(2.2, 0.8, mid)
	sound(Config.Sounds.Slash, mid, 1, 0.3)
end

function E.WheelTurn(p)
	local pos = p.Pos
	shockRing(pos, p.Completed and 16 or 7, GOLD, 0.45, 20, 0.3)
	flashSphere(pos, GOLD, p.Completed and 14 or 6, 0.3)
	sparks(pos, GOLD, p.Completed and 60 or 20, p.Completed and 60 or 25)
	sound(Config.Sounds.Unsheath, pos, 1, p.Completed and 0.5 or 0.8)
	if p.Completed then
		VFX.ScreenFlash(Color3.fromRGB(255, 236, 170), 0.25, 0.5)
		VFX.Shake(0.8, 0.4, pos)
	end
end

function E.BossSpawn(p)
	local pos = ground(p.Pos)
	puddle(pos, 16, 2.4)
	for i = 1, 5 do
		task.delay(i * 0.18, function()
			smoke(pos + UP * (i * 4), SHADOW, 24, 8, 12)
		end)
	end
	shockRing(pos, 40, SHADOW_RIM, 0.7, 36, 1)
	VFX.Shake(1.6, 1.2, pos)
	VFX.ScreenFlash(Color3.fromRGB(120, 90, 180), 0.2, 1)
	sound(Config.Sounds.Summon, pos, 1, 0.25)
	task.delay(1.1, function()
		flashSphere(pos + UP * 22, GOLD, 26, 0.6)
		shockRing(pos, 55, GOLD, 0.8, 40, 1)
	end)
end

function E.BossRoar(p)
	shockRing(ground(p.Pos), 45, Color3.fromRGB(255, 240, 220), 0.6, 36, 2)
	shockRing(ground(p.Pos), 30, GOLD, 0.45)
	VFX.Shake(1.4, 0.7, p.Pos)
end

function E.BossDefeated(p)
	local pos = p.Pos
	for i = 0, 4 do
		task.delay(i * 0.15, function()
			flashSphere(pos + UP * (4 + i * 3), GOLD, 20 + i * 6, 0.5)
			sparks(pos + UP * (4 + i * 3), BLADE, 40, 80)
		end)
	end
	shockRing(ground(pos), 70, GOLD, 1, 48, 1.5)
	smoke(pos + UP * 6, SHADOW, 40, 10, 16)
	VFX.ScreenFlash(Color3.fromRGB(255, 240, 200), 0.5, 1.2)
	VFX.Shake(2, 1, pos)
end

function E.CurseBurst(p)
	local pos = ground(p.Pos)
	shockRing(pos, p.Radius, Color3.fromRGB(200, 60, 120), 0.4, 18, 0.4)
	smoke(pos + UP * 2, Color3.fromRGB(80, 30, 70), 10, 4, 10)
end

return VFX
