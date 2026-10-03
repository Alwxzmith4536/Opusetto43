--[[
	Effects — client-side presentation of every Sukuna technique.

	The server decides *what* happens (hitboxes, damage, cooldowns) and fires
	"FX" events to all clients. This module turns each event into R15
	animation + VFX + sounds, and plays camera cinematics for the caster.
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = script.Parent
local Config = require(Shared.Config)
local PoseAnimator = require(Shared.PoseAnimator)
local Moves = require(Shared.Moves)
local VFX = require(Shared.VFX)
local Cine = require(Shared.Cinematics)
local Sounds = require(Shared.Sounds)
local Shrine = require(Shared.Shrine)

local Effects = {}
local H = {}

local player = Players.LocalPlayer
local C = Config.Colors
local T = Config.Timing
local UP = Vector3.yAxis

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------

local function rootOf(character: Instance?): BasePart?
	if typeof(character) ~= "Instance" then
		return nil
	end
	local r = (character :: Instance):FindFirstChild("HumanoidRootPart")
	if r and r:IsA("BasePart") then
		return r
	end
	return nil
end

local function alive(character: Model?): boolean
	if not character or not character.Parent then
		return false
	end
	local h = character:FindFirstChildOfClass("Humanoid")
	return h ~= nil and h.Health > 0
end

local function isMine(character: Instance?): boolean
	return character ~= nil and character == player.Character
end

local function cinematic(character: Instance?): boolean
	return Config.Cinematics and isMine(character)
end

local function cameraNear(pos: Vector3, radius: number): boolean
	local cam = Workspace.CurrentCamera
	return cam ~= nil and (cam.CFrame.Position - pos).Magnitude <= radius
end

-- Plays a move: custom uploaded animation if configured, else procedural.
local function playMove(character: Model, moveName: string)
	local custom = Config.CustomAnimations[moveName]
	if custom and custom ~= "" then
		if isMine(character) then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
			if animator then
				local anim = Instance.new("Animation")
				anim.AnimationId = custom
				local ok, track = pcall(function()
					return animator:LoadAnimation(anim)
				end)
				if ok and track then
					track.Priority = Enum.AnimationPriority.Action4
					track:Play(0.1)
				end
			end
		end
		return
	end
	PoseAnimator.play(character, Moves[moveName])
end

local function react(character: Model, heavy: boolean?)
	local rig = PoseAnimator.getRig(character)
	if not rig then
		return
	end
	local current = rig.track and rig.track.sequence
	if current == nil or current == Moves.Flinch or current == Moves.Stagger then
		rig:play(if heavy then Moves.Stagger else Moves.Flinch)
	end
end

local function groundY(pos: Vector3): number
	local g = VFX.ground(pos, 40)
	return if g then g.Position.Y else pos.Y - 3
end

----------------------------------------------------------------------
-- Local movement (dash / knockback on your own character)
----------------------------------------------------------------------

local function makeVelocity(hrp: BasePart, velocity: Vector3): LinearVelocity
	local att = hrp:FindFirstChild("RootAttachment")
	if not att or not att:IsA("Attachment") then
		att = Instance.new("Attachment")
		att.Name = "SukunaAttachment"
		att.Parent = hrp
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SukunaVelocity"
	lv.Attachment0 = att :: Attachment
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 1e7
	lv.VectorVelocity = velocity
	lv.Parent = hrp
	return lv
end

function Effects.dashSelf(dest: Vector3, time: number)
	local hrp = rootOf(player.Character)
	if not hrp then
		return
	end
	local flatDest = Vector3.new(dest.X, hrp.Position.Y, dest.Z)
	if (flatDest - hrp.Position).Magnitude > 0.5 then
		hrp.CFrame = CFrame.lookAt(hrp.Position, flatDest)
	end
	local lv = makeVelocity(hrp, (flatDest - hrp.Position) / time)
	VFX.addUpdater(function(_, t)
		if not lv.Parent or not hrp.Parent then
			return false
		end
		local remaining = flatDest - hrp.Position
		remaining = Vector3.new(remaining.X, 0, remaining.Z)
		if t >= time + 0.05 or remaining.Magnitude < 1 then
			lv:Destroy()
			hrp.AssemblyLinearVelocity = Vector3.new(0, hrp.AssemblyLinearVelocity.Y, 0)
			return false
		end
		lv.VectorVelocity = remaining.Unit * math.max(remaining.Magnitude / math.max(time - t, 0.04), 30)
		return true
	end)
end

function Effects.knockSelf(velocity: Vector3, duration: number?)
	local hrp = rootOf(player.Character)
	if typeof(velocity) ~= "Vector3" or not hrp then
		return
	end
	local d = math.clamp(duration or 0.2, 0.05, 1)
	local lv = makeVelocity(hrp, velocity)
	VFX.addUpdater(function(_, t)
		if not lv.Parent then
			return false
		end
		if t >= d then
			lv:Destroy()
			return false
		end
		lv.VectorVelocity = velocity * (1 - (t / d) * 0.5)
		return true
	end)
end

----------------------------------------------------------------------
-- Transformation
----------------------------------------------------------------------

function H.Transform(d)
	local char = d.char
	local hrp = rootOf(char)
	if not hrp then
		return
	end
	local Tt = T.Transform
	local mine = isMine(char)
	playMove(char, "Transform")

	-- Cursed energy torn out of the cube into the body
	local cube = Workspace:FindFirstChild(Config.Cube.Name)
	if cube and cube:IsA("BasePart") then
		VFX.sphere(cube.Position, 4, 14, 0.6, { color = C.Curse })
		VFX.light(cube.Position, C.Curse, 6, 30, 1.4)
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < Tt.Burst - 0.15 and hrp.Parent and cube.Parent do
				VFX.lightning(cube.Position, hrp.Position + Vector3.new(0, 0.6, 0), {
					color = if math.random() < 0.7 then C.Curse else C.Black,
					thickness = 0.24,
					segments = 10,
					life = 0.12,
				})
				task.wait(0.08)
			end
		end)
	end

	VFX.gather(hrp, Tt.Burst, 10)
	local stopAura = VFX.aura(char, 0.6)
	Sounds.play("Whoosh", hrp, { pitch = 0.45, volume = 1.2 })
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < Tt.Burst and hrp.Parent do
			local p = hrp.Position + VFX.randomUnit() * VFX.rand(1.5, 3.5)
			VFX.lightning(p, p + VFX.randomUnit() * VFX.rand(2, 4), {
				color = if math.random() < 0.5 then C.Curse else C.Black,
				thickness = 0.12,
				segments = 4,
				life = 0.1,
			})
			task.wait(0.05)
		end
	end)
	local gp0 = Vector3.new(hrp.Position.X, groundY(hrp.Position), hrp.Position.Z)
	VFX.cracks(gp0, 8, 6, 5)

	if cinematic(char) then
		Cine.grade({ TintColor = Color3.fromRGB(255, 205, 205), Saturation = -0.3, Contrast = 0.25 }, 0.6)
		Cine.shots(char, {
			{ dur = 1.55, eye = { Vector3.new(-3.2, 1.6, -5.2), Vector3.new(2.6, 1.0, -4.6) }, look = { Vector3.new(0, 1.2, 0), Vector3.new(0, 1.0, 0) }, fov = { 45, 38 } },
			{ dur = 0.5, eye = { Vector3.new(0, 2.5, -16), Vector3.new(0, 2.2, -12) }, look = { Vector3.new(0, 1.5, 0) }, fov = { 82, 62 }, style = "Quart", dir = "Out" },
			{ dur = 1.5, eye = { Vector3.new(1.5, 2.2, -7), Vector3.new(0.6, 1.95, -4.2) }, look = { Vector3.new(0, 1.85, 0), Vector3.new(0, 1.8, 0) }, fov = { 55, 42 } },
			{ dur = 0.45, eye = { Vector3.new(0.6, 1.95, -4.2), Vector3.new(3, 4, 9) }, look = { Vector3.new(0, 1.6, 0) }, fov = { 42, 70 }, style = "Quad", dir = "InOut" },
		})
		task.delay(0.35, function()
			Cine.caption("...Finally. A body of my own.", 1.0)
		end)
		task.delay(Tt.Duration - 0.2, function()
			Cine.resetGrade(0.8)
		end)
	end

	task.delay(Tt.Burst, function()
		if not hrp.Parent then
			return
		end
		stopAura()
		local pos = hrp.Position
		local gp = Vector3.new(pos.X, groundY(pos), pos.Z)
		VFX.sphere(pos, 2, 36, 0.75, { color = C.Curse })
		VFX.sphere(pos, 1, 16, 0.4, { color = C.SlashCore, material = Enum.Material.Neon, transparency = 0.2 })
		VFX.ring(gp + Vector3.new(0, 0.3, 0), 2, 42, 0.85, { color = C.Curse, thickness = 1.2 })
		VFX.ring(gp + Vector3.new(0, 0.4, 0), 1, 26, 0.6, { color = C.Black, thickness = 0.8 })
		VFX.crater(gp, 9, 16, 5)
		VFX.cracks(gp, 12, 10, 5)
		VFX.debris(gp, 14, 1.1)
		VFX.light(pos, C.Curse, 8, 50, 1.2)
		VFX.sparks(pos, 40)
		VFX.smokeBurst(gp, 18, 4, C.Black)
		VFX.highlight(char, C.Curse, 1.6, 0.4)
		Sounds.play("Launch", pos, { pitch = 0.5, volume = 1.3, rolloff = 400 })
		Sounds.play("Impact", pos, { pitch = 0.6 })
		Cine.shakeAt(pos, 1.2, 0.8, 120)
		local strong = VFX.aura(char, 1.6)
		task.delay(2.2, strong)
		if mine then
			Cine.flash(Color3.fromRGB(255, 40, 50), 0.3, 0.03, 0.05, 0.5)
			task.delay(0.35, function()
				Cine.title("両面宿儺", "RYOMEN SUKUNA — KING OF CURSES", 1.8)
			end)
		end
	end)
end

----------------------------------------------------------------------
-- Combo
----------------------------------------------------------------------

local COMBO_ROLL = { -20, 25, 80, -6 }

function H.Combo(d)
	local char = d.char
	local hrp = rootOf(char)
	local i = tonumber(d.index) or 1
	if not hrp then
		return
	end
	playMove(char, "Combo" .. i)
	Sounds.play("Swing", hrp, { pitch = 1.05 + i * 0.08, volume = 0.8 })
	task.delay(T.Combo.Hit - 0.03, function()
		if not hrp.Parent then
			return
		end
		local cf = hrp.CFrame * CFrame.new(0, 0.4, -2.4)
		VFX.crescent(cf * CFrame.Angles(0, 0, math.rad(COMBO_ROLL[i] or 0)), {
			width = if i == 4 then 7 else 4.5,
			thickness = 0.35,
			life = 0.18,
			velocity = hrp.CFrame.LookVector * 22,
			core = Color3.new(1, 1, 1),
			color = C.Curse,
		})
		if i == 4 then
			VFX.sphere(cf.Position, 1, 7, 0.25, { color = C.Curse })
		end
	end)
end

----------------------------------------------------------------------
-- Generic hit reaction
----------------------------------------------------------------------

function H.Hit(d)
	local char = d.char
	local hrp = rootOf(char)
	if not hrp then
		return
	end
	local pos = hrp.Position + VFX.randomUnit() * 0.6
	local kind = d.kind or "blunt"
	if kind == "slash" then
		VFX.cutLine(pos, VFX.randomUnit(), VFX.rand(5, 8), { thickness = 0.14, life = 0.25 })
		VFX.bloodMist(pos, 8)
		VFX.sparks(pos, 12)
		Sounds.play("Slash", pos, { pitch = VFX.rand(0.9, 1.25), volume = 0.7 })
	elseif kind == "burn" then
		VFX.fireBurst(pos, 8, 1.2, 10)
		Sounds.play("Impact", pos, { pitch = 0.7, volume = 0.6 })
	else
		VFX.sphere(pos, 0.5, if d.heavy then 9 else 5, 0.22, { color = C.SlashCore, material = Enum.Material.Neon, transparency = 0.3 })
		VFX.sparks(pos, if d.heavy then 28 else 14)
		Sounds.play("Impact", pos, { pitch = VFX.rand(0.9, 1.15) })
	end
	if not d.quiet then
		VFX.highlight(char, Color3.new(1, 1, 1), 0.18, 0.2)
	end
	react(char, d.heavy)
	Cine.shakeAt(pos, if d.heavy then 0.6 else 0.25, if d.heavy then 0.3 else 0.15, 60)
end

----------------------------------------------------------------------
-- Dismantle (解)
----------------------------------------------------------------------

function H.Dismantle(d)
	local char = d.char
	if not rootOf(char) then
		return
	end
	playMove(char, "Dismantle")
	local origin: CFrame = d.origin
	local life = d.range / d.speed
	for i, t in d.times do
		task.delay(t, function()
			local tilt = d.tilts[i] or 0
			VFX.crescent(origin * CFrame.Angles(0, 0, math.rad(tilt)), {
				width = d.width,
				bulge = d.width * 0.3,
				thickness = 0.8,
				life = life,
				velocity = origin.LookVector * d.speed,
			})
			Sounds.play("Slash", origin.Position, { pitch = VFX.rand(0.7, 0.85), volume = 1.0 })
			Sounds.play("Whoosh", origin.Position, { pitch = 1.6, volume = 0.5 })
			if i == 2 then
				for k = 1, 8 do
					task.delay(life * (k - 1) / 8, function()
						local p = origin.Position + origin.LookVector * (d.range * (k - 0.5) / 8)
						VFX.groundScar(p, origin.LookVector, d.range / 8 * 0.9, 0.3, 2.5)
					end)
				end
			end
			if i == 1 and isMine(char) then
				Cine.fovPunch(5)
			end
		end)
	end
end

----------------------------------------------------------------------
-- Cleave (捌)
----------------------------------------------------------------------

function H.Cleave(d)
	local char = d.char
	local hrp = rootOf(char)
	if not hrp then
		return
	end
	playMove(char, "Cleave")
	Sounds.play("Unsheath", hrp, { pitch = 0.8 })
	Sounds.play("Swing", hrp, { pitch = 0.7 })
	local thrp = rootOf(d.target)
	if isMine(char) then
		local dest
		if thrp then
			local offset = hrp.Position - thrp.Position
			offset = Vector3.new(offset.X, 0, offset.Z)
			if offset.Magnitude < 0.1 then
				offset = -hrp.CFrame.LookVector
			end
			dest = thrp.Position + offset.Unit * 3.2
		else
			dest = hrp.Position + hrp.CFrame.LookVector * 9
		end
		Effects.dashSelf(dest, T.Cleave.Arrive)
	end
	for k = 0, 3 do
		task.delay(k * 0.05, function()
			if char.Parent then
				VFX.afterimage(char, C.Curse, 0.3)
			end
		end)
	end
end

function H.CleaveCut(d)
	local thrp = rootOf(d.target)
	if not thrp then
		return
	end
	local pos = thrp.Position + Vector3.new(VFX.rand(-0.8, 0.8), VFX.rand(-1, 1.2), VFX.rand(-0.8, 0.8))
	local dir = VFX.randomUnit()
	VFX.cutLine(pos, dir, VFX.rand(5, 7.5), { thickness = 0.12, life = 0.22 })
	VFX.cutLine(pos, dir:Cross(VFX.randomUnit()), VFX.rand(4, 6), { thickness = 0.08, life = 0.2 })
	VFX.sparks(pos, 10)
	VFX.bloodMist(pos, 6)
	Sounds.play("Slash", pos, { pitch = VFX.rand(1.0, 1.4), volume = 0.6 })
	react(d.target, d.final)
	Cine.shakeAt(pos, 0.25, 0.1, 40)
	if d.final then
		local c = thrp.Position
		local cam = Workspace.CurrentCamera
		local right = if cam then cam.CFrame.RightVector else Vector3.xAxis
		VFX.cutLine(c, (right + UP).Unit, 11, { thickness = 0.3, life = 0.45 })
		VFX.cutLine(c, (right - UP).Unit, 11, { thickness = 0.3, life = 0.45 })
		VFX.sphere(c, 1, 12, 0.35, { color = C.Curse })
		VFX.bloodMist(c, 20)
		Sounds.play("Slash", c, { pitch = 0.6, volume = 1.2 })
		Cine.shakeAt(c, 0.8, 0.35, 70)
		if isMine(d.char) then
			Cine.impactFrame(0.08)
		end
	end
end

----------------------------------------------------------------------
-- Fuga (開)
----------------------------------------------------------------------

local fugaCleanup = setmetatable({}, { __mode = "k" })

function H.Fuga(d)
	local char = d.char
	local hrp = rootOf(char)
	if not hrp then
		return
	end
	local Tf = T.Fuga
	playMove(char, "Fuga")
	Sounds.play("Whoosh", hrp, { pitch = 0.6, volume = 1.1 })

	local rhand = char:FindFirstChild("RightHand")
	local lhand = char:FindFirstChild("LeftHand")
	local pieces = {}
	local function cleanup()
		for _, p in pieces do
			if typeof(p) == "Instance" then
				p:Destroy()
			end
		end
		table.clear(pieces)
	end
	fugaCleanup[char] = cleanup
	task.delay(Tf.Release + 0.6, cleanup)

	-- Flame gathering in the right palm
	if rhand and rhand:IsA("BasePart") then
		local flame = VFX.emitter(rhand, {
			Texture = VFX.Textures.Fire,
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, C.FireHot),
				ColorSequenceKeypoint.new(0.5, C.Fire),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 10, 0)),
			}),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.25, 0.5),
			Speed = NumberRange.new(1, 3),
			Acceleration = Vector3.new(0, 10, 0),
			Rate = 90,
			RotSpeed = NumberRange.new(-180, 180),
			Rotation = NumberRange.new(0, 360),
			Enabled = true,
		})
		local light = Instance.new("PointLight")
		light.Color = C.Fire
		light.Range = 12
		light.Brightness = 3
		light.Parent = rhand
		table.insert(pieces, flame)
		table.insert(pieces, light)
	end

	-- The fire bow + arrow form between the hands
	task.delay(1.0, function()
		if not (rhand and lhand and rhand:IsA("BasePart") and lhand:IsA("BasePart")) or fugaCleanup[char] ~= cleanup then
			return
		end
		local shaft = VFX.part({ Size = Vector3.new(0.35, 0.35, 4), Color = C.FireHot })
		local shaftGlow = VFX.part({ Size = Vector3.new(1, 1, 4.4), Color = C.Fire, Material = Enum.Material.ForceField })
		local top = VFX.attachmentAt(lhand.Position)
		local bottom = VFX.attachmentAt(lhand.Position)
		local bow = Instance.new("Beam")
		bow.Attachment0 = top
		bow.Attachment1 = bottom
		bow.Width0 = 0.5
		bow.Width1 = 0.5
		bow.Segments = 20
		bow.FaceCamera = true
		bow.LightEmission = 1
		bow.LightInfluence = 0
		bow.Brightness = 4
		bow.Color = ColorSequence.new(C.FireHot, C.Fire)
		bow.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.6),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(1, 0.6),
		})
		bow.CurveSize0 = 1.6
		bow.CurveSize1 = 1.6
		bow.Parent = top
		for _, p in { shaft, shaftGlow, top, bottom } do
			table.insert(pieces, p)
		end
		Sounds.play("Unsheath", lhand, { pitch = 0.6 })
		VFX.fireBurst(lhand.Position, 14, 0.8, 8)
		VFX.addUpdater(function()
			if not shaft.Parent or not lhand.Parent or not rhand.Parent then
				return false
			end
			local axis = lhand.Position - rhand.Position
			if axis.Magnitude < 0.2 then
				axis = hrp.CFrame.LookVector
			end
			axis = axis.Unit
			local tail = rhand.Position
			local tip = lhand.Position + axis * 1.6
			local len = (tip - tail).Magnitude
			local mid = (tip + tail) / 2
			shaft.Size = Vector3.new(0.35, 0.35, len)
			shaft.CFrame = CFrame.lookAt(mid, tip)
			shaftGlow.Size = Vector3.new(1, 1, len * 1.08)
			shaftGlow.CFrame = shaft.CFrame
			local side = axis:Cross(UP)
			if side.Magnitude < 0.1 then
				side = Vector3.xAxis
			end
			local up = side.Unit:Cross(axis).Unit
			local center = lhand.Position
			top.WorldCFrame = CFrame.fromMatrix(center + up * 2.6 - axis * 0.9, axis, up)
			bottom.WorldCFrame = CFrame.fromMatrix(center - up * 2.6 - axis * 0.9, -axis, up)
			return true
		end)
	end)

	if cinematic(char) then
		Cine.shots(char, {
			{ dur = 0.95, eye = { Vector3.new(2.2, 1.6, -3.4), Vector3.new(1.6, 1.3, -2.8) }, look = { Vector3.new(0.6, 0.6, -0.8) }, fov = { 50, 42 } },
			{ dur = 0.6, eye = { Vector3.new(1.7, 2.1, 4.8), Vector3.new(1.5, 2.0, 4.3) }, look = { Vector3.new(0, 1.2, -25) }, fov = { 60, 52 } },
			{ dur = 0.45, eye = { Vector3.new(1.4, 1.9, 4.2), Vector3.new(1.1, 1.8, 3.4) }, look = { Vector3.new(0, 1.2, -30) }, fov = { 52, 40 }, style = "Quart", dir = "In" },
			{ dur = 0.5, eye = { Vector3.new(1.1, 1.8, 3.4), Vector3.new(2.5, 3.5, 9) }, look = { Vector3.new(0, 1.2, -30) }, fov = { 40, 70 }, style = "Quad", dir = "Out" },
		})
		task.delay(0.15, function()
			Cine.title("開", "FUGA", 0.9)
		end)
		task.delay(1.0, function()
			Cine.caption("「開」 — Furnace, Open.", 0.9)
		end)
	end
end

function Effects.fugaExplosion(pos: Vector3, radius: number)
	local gy = groundY(pos)
	local gp = Vector3.new(pos.X, math.min(gy, pos.Y), pos.Z)
	VFX.light(pos, C.Fire, 10, radius * 3, 1.6)
	VFX.sphere(pos, 2, radius * 2.2, 0.9, { color = C.Fire, material = Enum.Material.Neon, transparency = 0.05, style = "Quint" })
	VFX.sphere(pos, 2, radius * 1.3, 0.6, { color = C.FireHot, material = Enum.Material.Neon })
	VFX.sphere(pos, radius, radius * 3.2, 1.0, { color = C.Fire })

	local pillar = VFX.part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(4, radius * 0.8, radius * 0.8),
		CFrame = CFrame.new(gp + Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C.Fire,
		Transparency = 0.1,
	})
	VFX.tween(pillar, 1.2, {
		Size = Vector3.new(90, radius * 0.4, radius * 0.4),
		CFrame = CFrame.new(gp + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 1,
	}, "Quart", "Out")
	Debris:AddItem(pillar, 1.3)

	VFX.ring(gp + Vector3.new(0, 0.5, 0), 2, radius * 2.4, 1.0, { color = C.Fire, thickness = 2 })
	VFX.ring(gp + Vector3.new(0, 0.6, 0), 1, radius * 1.6, 0.8, { color = C.FireHot, thickness = 1 })
	VFX.fireBurst(pos, 60, 4, 45)
	VFX.smokeBurst(gp, 30, 6)
	VFX.sparks(pos, 50, C.Fire)
	VFX.crater(gp, radius * 0.55, 18, 6)
	VFX.debris(gp, 22, 1.4, 1.3)

	local boom = Instance.new("Explosion")
	boom.Position = pos
	boom.BlastPressure = 0
	boom.BlastRadius = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Visible = false
	boom.Parent = Workspace

	Sounds.play("Launch", pos, { pitch = 0.35, volume = 1.5, rolloff = 600 })
	Sounds.play("Impact", pos, { pitch = 0.4, volume = 1.5, rolloff = 600 })
	Cine.shakeAt(pos, 2.0, 1.1, radius * 9)
	if cameraNear(pos, radius * 5) then
		Cine.flash(Color3.fromRGB(255, 170, 80), 0.35, 0.03, 0.05, 0.6)
	end

	-- Lingering flames
	local burn = Config.Abilities.Fuga.BurnDuration
	local holder = VFX.part({
		Size = Vector3.new(radius * 1.1, 1, radius * 1.1),
		CFrame = CFrame.new(gp + Vector3.new(0, 0.5, 0)),
		Transparency = 1,
	})
	local flames = VFX.emitter(holder, {
		Texture = VFX.Textures.Fire,
		Color = ColorSequence.new(C.FireHot, C.Fire),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(2, 6),
		Acceleration = Vector3.new(0, 10, 0),
		Rate = 80,
		Rotation = NumberRange.new(0, 360),
		Enabled = true,
	})
	local glow = Instance.new("PointLight")
	glow.Color = C.Fire
	glow.Range = radius * 1.5
	glow.Brightness = 2
	glow.Parent = holder
	task.delay(burn, function()
		flames.Enabled = false
		VFX.tween(glow, 1, { Brightness = 0 })
	end)
	Debris:AddItem(holder, burn + 1.5)
end

function H.FugaRelease(d)
	local origin: Vector3 = d.origin
	local hitPos: Vector3 = d.hitPos
	local travel = math.max(tonumber(d.travel) or 0.1, 0.05)
	local cleanup = d.char and fugaCleanup[d.char]
	if cleanup then
		cleanup()
	end
	Sounds.play("Launch", origin, { pitch = 0.8, volume = 1.2 })
	if d.char and rootOf(d.char) then
		VFX.fireBurst(origin, 20, 1.2, 18)
	end

	local dir = hitPos - origin
	dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local arrow = VFX.part({ Size = Vector3.new(0.6, 0.6, 5), CFrame = CFrame.lookAt(origin, origin + dir), Color = C.FireHot })
	local glow = VFX.part({ Size = Vector3.new(1.8, 1.8, 7), CFrame = arrow.CFrame, Color = C.Fire, Material = Enum.Material.ForceField })
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0.5, 0, 0)
	a0.Parent = arrow
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-0.5, 0, 0)
	a1.Parent = arrow
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 0) })
	trail.Color = ColorSequence.new(C.FireHot, C.Fire)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Parent = arrow
	VFX.emitter(arrow, {
		Texture = VFX.Textures.Fire,
		Color = ColorSequence.new(C.FireHot, C.Fire),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.25, 0.45),
		Speed = NumberRange.new(1, 3),
		Rate = 220,
		Rotation = NumberRange.new(0, 360),
		Enabled = true,
	})
	local light = Instance.new("PointLight")
	light.Color = C.Fire
	light.Range = 22
	light.Brightness = 4
	light.Parent = arrow

	VFX.addUpdater(function(_, t)
		local a = math.clamp(t / travel, 0, 1)
		local p = origin:Lerp(hitPos, a)
		local cf = CFrame.lookAt(p, p + dir)
		arrow.CFrame = cf
		glow.CFrame = cf
		if a >= 1 then
			arrow:Destroy()
			glow:Destroy()
			Effects.fugaExplosion(hitPos, d.radius or 26)
			return false
		end
		return true
	end)
end

----------------------------------------------------------------------
-- Domain Expansion: Malevolent Shrine
----------------------------------------------------------------------

local domainCount = 0
local savedLighting = nil

function Effects.domainLighting(on: boolean)
	if on then
		domainCount += 1
		if domainCount > 1 then
			return
		end
		savedLighting = {
			Ambient = Lighting.Ambient,
			OutdoorAmbient = Lighting.OutdoorAmbient,
			Brightness = Lighting.Brightness,
			ClockTime = Lighting.ClockTime,
			ExposureCompensation = Lighting.ExposureCompensation,
			FogColor = Lighting.FogColor,
			FogEnd = Lighting.FogEnd,
			FogStart = Lighting.FogStart,
		}
		local atm = Lighting:FindFirstChildOfClass("Atmosphere")
		if atm then
			savedLighting.atm = atm
			savedLighting.atmProps = {
				Density = atm.Density,
				Color = atm.Color,
				Decay = atm.Decay,
				Haze = atm.Haze,
				Glare = atm.Glare,
			}
			VFX.tween(atm, 0.4, {
				Density = 0.45,
				Color = Color3.fromRGB(150, 20, 25),
				Decay = Color3.fromRGB(90, 0, 10),
				Haze = 2.6,
				Glare = 0.4,
			})
		end
		VFX.tween(Lighting, 0.4, {
			Ambient = Color3.fromRGB(90, 10, 15),
			OutdoorAmbient = Color3.fromRGB(120, 25, 30),
			Brightness = 1.4,
			ClockTime = 18.3,
			ExposureCompensation = -0.2,
			FogColor = Color3.fromRGB(70, 0, 5),
			FogEnd = 400,
			FogStart = 40,
		})
		Cine.grade({ TintColor = Color3.fromRGB(255, 205, 205), Saturation = 0.1, Contrast = 0.2 }, 0.4)
	else
		domainCount = math.max(domainCount - 1, 0)
		if domainCount > 0 or not savedLighting then
			return
		end
		local saved = savedLighting
		savedLighting = nil
		if saved.atm and saved.atm.Parent then
			VFX.tween(saved.atm, 1.2, saved.atmProps)
		end
		VFX.tween(Lighting, 1.2, {
			Ambient = saved.Ambient,
			OutdoorAmbient = saved.OutdoorAmbient,
			Brightness = saved.Brightness,
			ClockTime = saved.ClockTime,
			ExposureCompensation = saved.ExposureCompensation,
			FogColor = saved.FogColor,
			FogEnd = saved.FogEnd,
			FogStart = saved.FogStart,
		})
		Cine.resetGrade(1.2)
	end
end

local function spawnDomainSlash(center: Vector3, gy: number, radius: number)
	local r = radius * math.sqrt(math.random())
	local ang = math.random() * math.pi * 2
	local p = Vector3.new(center.X + math.cos(ang) * r, gy + VFX.rand(0.8, 10), center.Z + math.sin(ang) * r)
	if math.random() < 0.6 then
		local dir = Vector3.new(VFX.rand(-1, 1), VFX.rand(-0.6, 0.6), VFX.rand(-1, 1))
		if dir.Magnitude < 0.1 then
			dir = Vector3.xAxis
		end
		VFX.cutLine(p, dir, VFX.rand(6, 15), { thickness = VFX.rand(0.08, 0.2), life = VFX.rand(0.18, 0.3) })
	else
		local cf = CFrame.new(p) * CFrame.Angles(VFX.rand(-0.6, 0.6), VFX.rand(0, 6.28), VFX.rand(-1.2, 1.2))
		VFX.crescent(cf, { width = VFX.rand(5, 11), thickness = 0.5, life = 0.25, velocity = cf.LookVector * VFX.rand(20, 50) })
	end
	if math.random() < 0.25 then
		VFX.groundScar(Vector3.new(p.X, gy + 1, p.Z), VFX.randomUnit(), VFX.rand(3, 8), 0.25, 2)
	end
end

function H.Domain(d)
	local char = d.char
	local hrp = rootOf(char)
	if not hrp then
		return
	end
	local Td = T.Domain
	local center: Vector3 = d.center
	local look: Vector3 = d.look
	local radius: number = d.radius
	local gy: number = d.ground or groundY(center)
	local inRange = function()
		return cameraNear(center, radius * 2.2)
	end

	playMove(char, "Domain")
	local stopAura = VFX.aura(char, 1.2)
	task.delay(Td.Expand + 0.8, stopAura)
	Sounds.play("Whoosh", hrp, { pitch = 0.35, volume = 1.4 })
	VFX.gather(hrp, Td.Expand, 12)

	if cinematic(char) then
		Cine.shots(char, {
			{ dur = 1.25, eye = { Vector3.new(0.4, 0.8, -3.6), Vector3.new(0.2, 0.75, -2.9) }, look = { Vector3.new(0, 0.6, -0.6) }, fov = { 42, 36 } },
			{ dur = 1.2, eye = { Vector3.new(-1.2, 1.0, -3.4), Vector3.new(-0.6, 1.3, -2.7) }, look = { Vector3.new(0, 1.65, 0) }, fov = { 46, 34 } },
			{ dur = 1.7, eye = { Vector3.new(14, 6, -22), Vector3.new(22, 14, -34) }, look = { Vector3.new(0, 12, 22), Vector3.new(0, 14, 24) }, fov = { 65, 72 }, style = "Quad", dir = "Out" },
			{ dur = 0.6, eye = { Vector3.new(22, 14, -34), Vector3.new(4, 5, 12) }, look = { Vector3.new(0, 14, 24), Vector3.new(0, 2, -6) }, fov = { 72, 70 } },
		})
		task.delay(0.25, function()
			Cine.title("領域展開", "DOMAIN EXPANSION", 1.0)
		end)
		task.delay(1.4, function()
			Cine.title("伏魔御厨子", "MALEVOLENT SHRINE", 1.2)
		end)
	end

	-- The world blinks to black just before the shrine appears.
	task.delay(Td.Expand - 0.35, function()
		if inRange() and alive(char) then
			Cine.flash(Color3.new(0, 0, 0), 0, 0.12, 0.25, 0.45)
		end
	end)

	task.delay(Td.Expand, function()
		if not alive(char) then
			return
		end
		local shrinePos = Vector3.new(center.X, gy, center.Z) - look * 30
		local shrineCF = CFrame.lookAt(shrinePos, shrinePos + look)
		local model, height = Shrine.build(shrineCF)
		model:PivotTo(shrineCF * CFrame.new(0, -height - 2, 0))
		model.Parent = VFX.folder()

		local pool = VFX.part({
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.3, 4, 4),
			CFrame = CFrame.new(center.X, gy + 0.06, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(85, 0, 6),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.25,
			Transparency = 0.05,
		})
		VFX.tween(pool, 1.3, { Size = Vector3.new(0.3, radius * 2, radius * 2) }, "Quart", "Out")

		local lit = inRange()
		if lit then
			Effects.domainLighting(true)
		end
		Sounds.play("Launch", shrinePos, { pitch = 0.3, volume = 1.6, rolloff = 500 })
		Sounds.play("Whoosh", shrinePos, { pitch = 0.25, volume = 1.4, rolloff = 500 })
		Cine.shakeAt(center, 1.4, 1.4, radius * 2.5)
		local gp = Vector3.new(center.X, gy, center.Z)
		VFX.ring(gp + Vector3.new(0, 0.3, 0), 4, radius, 1.2, { color = C.Curse, thickness = 1.5 })
		VFX.smokeBurst(shrinePos, 30, 8, C.Black)
		VFX.debris(shrinePos, 20, 1.6, 1.5)
		VFX.cracks(gp, 14, 14, 7)

		local collapsed = false
		local function collapse()
			if collapsed then
				return
			end
			collapsed = true
			local fromCF = model:GetPivot()
			VFX.addUpdater(function(_, t)
				local a = math.clamp(t / 1.0, 0, 1)
				if model.Parent then
					model:PivotTo(fromCF * CFrame.new(0, -(height + 2) * a * a, 0))
				end
				if a >= 1 then
					model:Destroy()
					return false
				end
				return true
			end)
			VFX.tween(pool, 1, { Size = Vector3.new(0.3, 4, 4), Transparency = 1 }, "Quad", "In")
			Debris:AddItem(pool, 1.1)
			VFX.smokeBurst(shrinePos, 20, 8, C.Black)
			if lit then
				Effects.domainLighting(false)
			end
		end

		-- Shrine rises out of the ground
		VFX.addUpdater(function(_, t)
			if collapsed or not model.Parent then
				return false
			end
			local a = math.clamp(t / 1.3, 0, 1)
			local e = 1 - (1 - a) ^ 4
			local jitter = (1 - a) * 0.4
			model:PivotTo(shrineCF * CFrame.new(VFX.rand(-jitter, jitter), -(height + 2) * (1 - e), VFX.rand(-jitter, jitter)))
			return a < 1
		end)

		-- Lifecycle + endless slashing
		local stormStart = Td.SlashStart - Td.Expand
		local stormEnd = Td.SlashEnd - Td.Expand
		local collapseAt = Td.Collapse - Td.Expand
		local acc, soundAcc = 0, 0
		VFX.addUpdater(function(dt, t)
			if collapsed then
				return false
			end
			if t >= collapseAt or not alive(char) then
				collapse()
				return false
			end
			if t >= stormStart and t < stormEnd then
				acc += dt * 20
				while acc >= 1 do
					acc -= 1
					spawnDomainSlash(center, gy, radius)
				end
				soundAcc += dt
				if soundAcc >= 0.11 then
					soundAcc = 0
					local cam = Workspace.CurrentCamera
					if cam and inRange() then
						local p = cam.CFrame.Position + VFX.randomUnit() * 10
						Sounds.play("Slash", p, { pitch = VFX.rand(0.8, 1.5), volume = 0.45 })
					end
				end
				if cameraNear(center, radius) then
					Cine.shake(0.22, 0.15)
				end
			end
			return true
		end)
	end)
end

function H.DomainHits(d)
	if type(d.targets) ~= "table" then
		return
	end
	for i, char in d.targets do
		local hrp = rootOf(char)
		if hrp then
			local pos = hrp.Position + VFX.randomUnit()
			VFX.cutLine(pos, VFX.randomUnit(), VFX.rand(4, 7), { thickness = 0.12, life = 0.2 })
			VFX.bloodMist(pos, 4)
			react(char, false)
			if i == 1 then
				Sounds.play("Slash", pos, { pitch = VFX.rand(1, 1.3), volume = 0.6 })
			end
		end
	end
end

----------------------------------------------------------------------
-- World Cutting Slash
----------------------------------------------------------------------

function Effects.worldRift(origin: CFrame, length: number, height: number, mine: boolean)
	local look = Vector3.new(origin.LookVector.X, 0, origin.LookVector.Z).Unit
	local right = look:Cross(UP).Unit
	local gy = groundY(origin.Position)
	local base = Vector3.new(origin.Position.X, gy, origin.Position.Z)
	local h = height * 0.5
	local lift = Vector3.new(0, h / 2 - 2, 0)
	local center = base + look * (length / 2 + 2) + lift
	local cf = CFrame.fromMatrix(center, right, UP)

	-- 1) A white line races out across the world
	local line = VFX.part({ Size = Vector3.new(0.15, h, 0.2), CFrame = CFrame.fromMatrix(base + look * 2 + lift, right, UP), Color = C.SlashCore })
	VFX.addUpdater(function(_, t)
		if not line.Parent then
			return false
		end
		local a = math.clamp(t / 0.12, 0, 1)
		local L = math.max(length * a, 0.2)
		line.Size = Vector3.new(0.15, h, L)
		line.CFrame = CFrame.fromMatrix(base + look * (2 + L / 2) + lift, right, UP)
		return a < 1
	end)
	if mine then
		Cine.impactFrame(0.12)
	end
	if cameraNear(center, length) then
		Cine.flash(Color3.new(1, 1, 1), 0.2, 0.02, 0.06, 0.5)
	end
	Sounds.play("Slash", origin.Position, { pitch = 0.35, volume = 2, rolloff = 800 })
	Sounds.play("Launch", origin.Position, { pitch = 0.45, volume = 1.4, rolloff = 800 })
	Cine.shakeAt(center, 2.2, 1.2, length * 1.2)

	-- 2) Space itself splits open
	task.delay(0.14, function()
		VFX.tween(line, 0.3, { Transparency = 1 })
		Debris:AddItem(line, 0.35)
		local rift = VFX.part({ Size = Vector3.new(0.2, h, length), CFrame = cf, Color = C.Black, Material = Enum.Material.SmoothPlastic })
		local edgeL = VFX.part({ Size = Vector3.new(0.14, h, length), CFrame = cf * CFrame.new(-0.25, 0, 0), Color = C.SlashCore })
		local edgeR = VFX.part({ Size = Vector3.new(0.14, h, length), CFrame = cf * CFrame.new(0.25, 0, 0), Color = C.SlashCore })
		local glow = VFX.part({ Size = Vector3.new(3, h * 1.02, length * 1.01), CFrame = cf, Color = C.SlashGlow, Material = Enum.Material.ForceField, Transparency = 0.3 })
		VFX.tween(rift, 0.35, { Size = Vector3.new(2.2, h, length) }, "Quint", "Out")
		VFX.tween(edgeL, 0.35, { CFrame = cf * CFrame.new(-1.2, 0, 0) }, "Quint", "Out")
		VFX.tween(edgeR, 0.35, { CFrame = cf * CFrame.new(1.2, 0, 0) }, "Quint", "Out")
		task.delay(1.5, function()
			for _, p in { rift, edgeL, edgeR, glow } do
				VFX.tween(p, 0.9, { Transparency = 1 }, "Quad", "In")
				Debris:AddItem(p, 1)
			end
		end)

		-- Ground fissure + rocks thrown up along the cut
		local fissureCF = CFrame.fromMatrix(base + look * (length / 2 + 2) + Vector3.new(0, 0.05, 0), right, UP)
		local fissure = VFX.part({ Size = Vector3.new(2.6, 0.1, length), CFrame = fissureCF, Color = C.Black, Material = Enum.Material.SmoothPlastic })
		local ember = VFX.part({ Size = Vector3.new(0.6, 0.12, length), CFrame = fissureCF, Color = C.Curse })
		task.delay(5, function()
			VFX.tween(fissure, 1.5, { Transparency = 1 })
			VFX.tween(ember, 1.5, { Transparency = 1 })
		end)
		Debris:AddItem(fissure, 6.6)
		Debris:AddItem(ember, 6.6)
		for k = 1, 10 do
			task.delay(k * 0.02, function()
				local p = base + look * (length * k / 11)
				VFX.debris(p, 4, 1.2)
				VFX.smokeBurst(p, 4, 4)
			end)
		end
		for k = 1, 16 do
			local along = base + look * (length * k / 17)
			for _, side in { -1, 1 } do
				local at = along + right * side * VFX.rand(2.2, 3.4)
				local s = VFX.rand(1.6, 3)
				local final = CFrame.lookAt(at, at + right * side) * CFrame.Angles(math.rad(VFX.rand(30, 55)), 0, 0)
				local rock = VFX.part({
					Size = Vector3.new(s, s * 0.6, s * 1.2),
					CFrame = final - Vector3.new(0, s, 0),
					Color = Color3.fromRGB(60, 54, 52),
					Material = Enum.Material.Slate,
				})
				VFX.tween(rock, 0.2, { CFrame = final }, "Back", "Out")
				task.delay(5, function()
					VFX.tween(rock, 1, { CFrame = final - Vector3.new(0, s * 1.5, 0), Transparency = 1 }, "Quad", "In")
				end)
				Debris:AddItem(rock, 6.1)
			end
		end
	end)
end

function H.WorldSlash(d)
	local char = d.char
	local hrp = rootOf(char)
	if not hrp then
		return
	end
	local Tw = T.WorldSlash
	local mine = isMine(char)
	playMove(char, "WorldSlash")
	local stopAura = VFX.aura(char, 1.0)
	task.delay(Tw.Slash + 0.6, stopAura)
	Sounds.play("Whoosh", hrp, { pitch = 0.4, volume = 1.2 })

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < Tw.Slash and hrp.Parent do
			local rh = char:FindFirstChild("RightHand")
			if rh and rh:IsA("BasePart") then
				local p = rh.Position
				VFX.lightning(p, p + VFX.randomUnit() * VFX.rand(1.5, 3), {
					thickness = 0.08,
					segments = 4,
					life = 0.08,
					color = if math.random() < 0.5 then C.SlashCore else C.Curse,
				})
			end
			task.wait(0.06)
		end
	end)

	if cinematic(char) then
		Cine.grade({ Saturation = -0.4, Contrast = 0.3, TintColor = Color3.fromRGB(255, 225, 225) }, 0.8)
		Cine.shots(char, {
			{ dur = 2.15, eye = { Vector3.new(1.2, 1.9, -4.2), Vector3.new(0.5, 1.8, -3.0) }, look = { Vector3.new(0.2, 1.7, 0) }, fov = { 48, 34 } },
			{ dur = 0.35, eye = { Vector3.new(9, 3, 4), Vector3.new(10, 3.5, 5) }, look = { Vector3.new(0, 3, -12) }, fov = { 60, 64 } },
			{ dur = 1.1, eye = { Vector3.new(26, 18, -10), Vector3.new(34, 26, -30) }, look = { Vector3.new(0, 5, -60), Vector3.new(0, 4, -110) }, fov = { 70, 75 }, style = "Quad", dir = "Out" },
		})
		task.delay(0.2, function()
			Cine.caption("竜鱗 — Dragon Scale", 0.55)
		end)
		task.delay(0.8, function()
			Cine.caption("反発 — Recoil", 0.55)
		end)
		task.delay(1.4, function()
			Cine.caption("番いの流星 — Twin Meteors", 0.6)
		end)
		task.delay(Tw.Slash + 0.05, function()
			Cine.title("世界を断つ斬撃", "WORLD CUTTING SLASH", 1.1)
		end)
		task.delay(Tw.Duration, function()
			Cine.resetGrade(0.8)
		end)
	end

	task.delay(Tw.Slash, function()
		Effects.worldRift(d.origin, d.length, d.height, mine)
	end)
end

----------------------------------------------------------------------
-- Dispatcher
----------------------------------------------------------------------

function Effects.handle(name: string, data)
	local handler = H[name]
	if not handler or type(data) ~= "table" then
		return
	end
	task.spawn(function()
		local ok, err = pcall(handler, data)
		if not ok then
			warn("[SukunaFX] " .. tostring(name) .. ": " .. tostring(err))
		end
	end)
end

return Effects
