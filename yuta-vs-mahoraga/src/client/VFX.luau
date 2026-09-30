--!strict
--[[
	Client effects for Yuta's techniques and the dispatcher for every FX event
	the server sends. Mahoraga's effects live in BossVFX.
]]

local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Palette = require(Shared:WaitForChild("Palette"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Assets = Shared:WaitForChild("Assets")
local PartKit = require(Assets:WaitForChild("PartKit"))
local Effects = require(Assets:WaitForChild("Effects"))
local Katana = require(Assets:WaitForChild("Katana"))
local Rika = require(Assets:WaitForChild("Rika"))
local Domain = require(Assets:WaitForChild("Domain"))

local VfxUtil = require(script.Parent.VfxUtil)
local HUD = require(script.Parent.HUD)
local CameraFX = require(script.Parent.CameraFX)
local RikaFollower = require(script.Parent.RikaFollower)
local BossVFX = require(script.Parent.BossVFX)

local NEON = Enum.Material.Neon
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer
local rng = VfxUtil.rng

local VFX = {}
local handlers: { [string]: (any) -> () } = {}

local function near(pos: Vector3, radius: number): boolean
	local root = VfxUtil.root(player.Character)
	return root ~= nil and (root.Position - pos).Magnitude <= radius
end

local function isMe(char: any): boolean
	return char ~= nil and char == player.Character
end

-- HUD / camera events -------------------------------------------------------------------

handlers.Cooldown = function(d)
	HUD.setCooldown(d.id, d.ends, d.duration)
end
handlers.Announce = function(d)
	HUD.announce(d.title, d.sub, d.color, d.time)
end
handlers.Notify = function(d)
	HUD.notify(d.text)
end
handlers.Shake = function(d)
	CameraFX.shake(d.intensity or 1, d.duration or 0.4)
end
handlers.Reset = function()
	HUD.reset()
end

-- Generic hit feedback ----------------------------------------------------------------------

handlers.Hit = function(d)
	local pos: Vector3 = d.pos
	local color: Color3 = d.color or Palette.YutaEnergy
	local big = d.big == true
	local m = Effects.spikes(VfxUtil.folder(), pos, if big then 10 else 6, if big then 4.2 else 2.6, color, rng)
	local flash = m:FindFirstChild("Flash")
	if flash and flash:IsA("BasePart") then
		VfxUtil.tween(flash, 0.18, { Size = Vector3.one * (if big then 5 else 3), Transparency = 1 })
	end
	VfxUtil.fade(m, 0.2, 0.05)
	VfxUtil.burst(pos, {
		Texture = PartKit.Textures.Spark,
		Color = ColorSequence.new(color),
		LightEmission = 1,
		Size = NumberSequence.new(0.4, 0),
		Lifetime = NumberRange.new(0.2, 0.45),
		Speed = NumberRange.new(18, 34),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
	}, if big then 18 else 8)
end

local DAMAGE_COLORS: { [string]: Color3 } = {
	immune = Palette.Wheel,
	adapt = Color3.fromRGB(255, 200, 110),
	infinity = Palette.SixEyes,
	block = Color3.fromRGB(190, 190, 205),
	dodge = Color3.fromRGB(235, 235, 255),
	player = Color3.fromRGB(255, 82, 82),
	heal = Color3.fromRGB(120, 255, 160),
	backlash = Color3.fromRGB(190, 40, 60),
}

handlers.Damage = function(d)
	local pos: Vector3 = d.pos
	local amount: number = d.amount or 0
	local tag: string? = d.tag
	local text = tostring(math.floor(amount + 0.5))
	if tag == "immune" then
		text = "ADAPTED"
	elseif tag == "dodge" then
		text = "DODGE"
	elseif tag == "heal" then
		text = "+" .. text
	elseif tag == "infinity" then
		text = "INFINITY " .. text
	elseif tag == "block" then
		text = text .. " GUARD"
	end
	local color = if tag then DAMAGE_COLORS[tag] or WHITE else WHITE
	local size = math.clamp(1.3 + amount / 70, 1.3, 3)
	local anchor = PartKit.part({
		Name = "DamageNumber",
		Parent = VfxUtil.folder(),
		CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-1.5, 1.5), rng:NextNumber(0, 1.5), rng:NextNumber(-1.5, 1.5))),
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
	})
	local gui = PartKit.billboardText(anchor, text, size * math.max(2, #text * 0.6), size, color)
	gui.MaxDistance = 260
	VfxUtil.tween(anchor, 0.8, { CFrame = anchor.CFrame + Vector3.new(0, 3.2, 0) })
	VfxUtil.fade(anchor, 0.3, 0.55)
end

handlers.Impact = function(d)
	local pos: Vector3 = d.pos
	local radius: number = d.radius or 8
	local color: Color3 = d.color or Palette.YutaEnergy
	local big = d.big == true
	local folder = VfxUtil.folder()
	local base = CFrame.new(pos + Vector3.new(0, 0.3, 0))
	local ring = VfxUtil.liveRing(folder, base, 32, if big then 1.6 else 0.9, if big then 1.4 else 0.8, color)
	VfxUtil.animate(0.45, function(a)
		local eased = 1 - (1 - a) ^ 3
		ring.set(radius * (0.2 + 0.9 * eased), 0.1 + 0.9 * a)
	end, function()
		for _, p in ring.parts do
			p:Destroy()
		end
	end)
	local dome = PartKit.ball(folder, base, radius * 0.6, { Color = color, Material = NEON, Transparency = 0.45 }, "Dome")
	VfxUtil.tween(dome, 0.3, { Size = Vector3.one * radius * 1.4, Transparency = 1 })
	Debris:AddItem(dome, 0.35)
	VfxUtil.burst(pos + Vector3.new(0, 1, 0), {
		Texture = PartKit.Textures.Smoke,
		Color = ColorSequence.new(Color3.fromRGB(128, 118, 128)),
		Size = NumberSequence.new(radius * 0.2, radius * 0.45),
		Transparency = NumberSequence.new(0.35, 1),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(radius * 1.2, radius * 2),
		SpreadAngle = Vector2.new(85, 85),
		Drag = 3,
		Acceleration = Vector3.new(0, 4, 0),
	}, if big then 28 else 12)
	if d.cracks then
		local cracks = Effects.cracks(folder, CFrame.new(pos), radius * 0.9, if big then 10 else 6, rng)
		VfxUtil.fade(cracks, 1, 2.5)
	end
	if d.rocks then
		local rocks = Effects.rocks(folder, CFrame.new(pos), radius * 0.8, 10, rng)
		for _, rock in rocks:GetChildren() do
			if rock:IsA("BasePart") then
				local out = Util.flatUnit(rock.Position - pos)
				local up = rock.CFrame + out * rng:NextNumber(3, 8) + Vector3.new(0, rng:NextNumber(4, 9), 0)
				VfxUtil.tween(rock, 0.35, { CFrame = up * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0) })
				task.delay(0.35, function()
					VfxUtil.tween(rock, 0.5, { CFrame = rock.CFrame - Vector3.new(0, 9, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end)
			end
		end
		VfxUtil.fade(rocks, 0.5, 1.1)
	end
	if near(pos, radius * 4) then
		CameraFX.shake(if big then 0.9 else 0.35, 0.3)
	end
	VfxUtil.sound("Impact", pos, if big then 1 else 0.6)
end

handlers.Stun = function(d)
	BossVFX.stunRing(d.model, d.duration or 1)
end

-- Katana ------------------------------------------------------------------------------------

local SLASH_ROLL = { 35, -35, 0, 90 }

handlers.Slash = function(d)
	local root = VfxUtil.root(d.char)
	local base: CFrame = if root then root.CFrame else d.cf
	local combo: number = d.combo or 1
	local finisher = combo == 4
	local cf = base * CFrame.new(0, 0.4, -1.2) * CFrame.Angles(0, 0, math.rad(SLASH_ROLL[combo] or 0))
	local slash = Effects.slash(VfxUtil.folder(), cf, if finisher then 7 else 5.2, if finisher then 210 else 165, if finisher then 1.8 else 1.2, Palette.YutaEnergy, Palette.YutaCore)
	local n = #slash.Outer
	local outerBase, coreBase = {}, {}
	for i = 1, n do
		outerBase[i] = slash.Outer[i].Transparency
		coreBase[i] = slash.Core[i].Transparency
		slash.Outer[i].Transparency = 1
		slash.Core[i].Transparency = 1
	end
	local reverse = combo % 2 == 0
	VfxUtil.animate(0.08, function(a)
		local shown = math.floor(a * n + 0.5)
		for k = 1, shown do
			local i = if reverse then n - k + 1 else k
			slash.Outer[i].Transparency = outerBase[i]
			slash.Core[i].Transparency = coreBase[i]
		end
	end, function()
		VfxUtil.fade(slash.Model, 0.22)
	end)
	VfxUtil.sound(if finisher then "Lunge" else "Slash", root)
end

handlers.Dash = function(d)
	local char = d.char
	local root = VfxUtil.root(char)
	if not root then
		return
	end
	local folder = VfxUtil.folder()
	VfxUtil.burst(root.Position - Vector3.new(0, 2.5, 0), {
		Texture = PartKit.Textures.Smoke,
		Color = ColorSequence.new(Palette.YutaEnergy),
		LightEmission = 0.4,
		Size = NumberSequence.new(1.2, 2.6),
		Transparency = NumberSequence.new(0.4, 1),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(6, 12),
		SpreadAngle = Vector2.new(80, 80),
	}, 10)
	for k = 0, 2 do
		task.delay(k * 0.06, function()
			if not char.Parent then
				return
			end
			local ghost = PartKit.model("Afterimage", folder)
			for _, p in char:GetChildren() do
				if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 1 then
					PartKit.part({ Name = "Ghost", Parent = ghost, CFrame = p.CFrame, Size = p.Size, Color = Palette.YutaEnergy, Material = NEON, Transparency = 0.55 })
				end
			end
			VfxUtil.fade(ghost, 0.3)
		end)
	end
	VfxUtil.sound("Lunge", root, 0.5)
end

-- Rika ------------------------------------------------------------------------------------

handlers.RikaArm = function(d)
	local root = VfxUtil.root(d.char)
	local base: CFrame = d.cf or (if root then root.CFrame else CFrame.identity)
	local scale = if d.full then 1.35 else 1.05
	local ground = VfxUtil.ground(base.Position)
	local folder = VfxUtil.folder()
	local pivot = CFrame.new(ground) * base.Rotation * CFrame.new(1.6, 9.5 * scale, 3.2)
	local arm = Rika.buildArm(folder, pivot * CFrame.Angles(math.rad(200), 0, 0), 1, scale)
	local fader = VfxUtil.fader(arm)
	fader.set(0)

	local portal = PartKit.model("Portal", folder)
	PartKit.ring(portal, pivot * CFrame.Angles(math.rad(90), 0, 0), 2.4 * scale, 0.5, 0.3, 20, { Color = Palette.RikaAura, Material = NEON })
	PartKit.cylinderZ({ Name = "Void", Parent = portal, CFrame = pivot, Color = Palette.Shadow }, 0.15, 4.6 * scale)
	VfxUtil.fade(portal, 0.4, 0.55)
	VfxUtil.burst(pivot.Position, {
		Texture = PartKit.Textures.Smoke,
		Color = ColorSequence.new(Palette.YutaDark, Palette.RikaAura),
		Size = NumberSequence.new(1.5, 3.5),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(180, 180),
	}, 16)

	VfxUtil.animate(0.42, function(a)
		local t = math.clamp((a - 0.1) / 0.9, 0, 1)
		local pitch = 200 - 152 * t * t * t
		arm:PivotTo(pivot * CFrame.Angles(math.rad(pitch), 0, 0))
		fader.set(math.min(1, a * 4))
	end, function()
		VfxUtil.fade(arm, 0.35, 0.25)
	end)
end

handlers.RikaManifest = function(d)
	local root = VfxUtil.root(d.char)
	if not root then
		return
	end
	local folder = VfxUtil.folder()
	local base = root.CFrame * CFrame.new(0, 4, 6)
	local portal = PartKit.model("RikaPortal", folder)
	PartKit.ring(portal, base * CFrame.Angles(math.rad(90), 0, 0), 5.5, 0.9, 0.5, 28, { Color = Palette.RikaAura, Material = NEON })
	PartKit.cylinderZ({ Name = "Void", Parent = portal, CFrame = base, Color = Palette.Shadow }, 0.2, 10.5)
	VfxUtil.fade(portal, 0.6, 1.2)
	VfxUtil.burst(base.Position, {
		Texture = PartKit.Textures.Smoke,
		Color = ColorSequence.new(Palette.YutaDark, Palette.RikaAura),
		Size = NumberSequence.new(3, 7),
		Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(180, 180),
	}, 30)
	local ground = VfxUtil.ground(root.Position)
	local ring = VfxUtil.liveRing(folder, CFrame.new(ground + Vector3.new(0, 0.3, 0)), 36, 1.2, 1.2, Palette.RikaAura)
	VfxUtil.animate(0.6, function(a)
		ring.set(4 + 30 * (1 - (1 - a) ^ 3), a)
	end, function()
		for _, p in ring.parts do
			p:Destroy()
		end
	end)
	VfxUtil.kanji(root.Position + Vector3.new(0, 11, 0), "里香", 4, Palette.RikaAura, 1.4, 0.3)
	if near(root.Position, 90) then
		CameraFX.shake(0.6, 0.5)
	end
end

handlers.RikaVanish = function(d)
	local model = if typeof(d.char) == "Instance" and d.char:IsA("Model") then RikaFollower.get(d.char) else nil
	local pos = if model and model.PrimaryPart then model.PrimaryPart.Position else nil
	if pos then
		VfxUtil.burst(pos, {
			Texture = PartKit.Textures.Smoke,
			Color = ColorSequence.new(Palette.YutaDark, Palette.RikaAura),
			Size = NumberSequence.new(3, 6),
			Transparency = NumberSequence.new(0.3, 1),
			Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(3, 8),
			SpreadAngle = Vector2.new(180, 180),
		}, 24)
	end
end

handlers.RikaClaw = function(d)
	if typeof(d.char) ~= "Instance" or not d.char:IsA("Model") then
		return
	end
	local char: Model = d.char
	local target: Vector3 = d.target
	RikaFollower.claw(char, target)
	task.delay(0.3, function()
		local root = VfxUtil.root(char)
		local from = if root then root.Position else target + Vector3.new(0, 0, 6)
		local dir = Util.flatUnit(target - from)
		local claws = Effects.claws(VfxUtil.folder(), Util.facing(target - dir * 4 + Vector3.new(0, 2, 0), dir), 5, Palette.RikaAura)
		VfxUtil.fade(claws, 0.3, 0.15)
	end)
end

-- Cursed Speech & RCT ---------------------------------------------------------------------

handlers.Speech = function(d)
	local head = VfxUtil.head(d.char)
	local root = VfxUtil.root(d.char)
	if not head or not root then
		return
	end
	local folder = VfxUtil.folder()
	local blast = d.word == "BlastAway"
	VfxUtil.kanji(head.Position + Vector3.new(0, 3.2, 0), if blast then "吹っ飛べ" else "動くな", 3.2, WHITE, 1.1, 0.25)
	local facing: CFrame = d.cf or Util.facing(root.Position, root.CFrame.LookVector)
	local mouth = CFrame.new(head.Position) * facing.Rotation * CFrame.new(0, -0.2, -0.8)
	local waves = Effects.speechWaves(folder, mouth, 4, 2.2, 0.8, Palette.SpeechRing)
	VfxUtil.fade(waves, 0.45, 0.15)
	local radius: number = d.radius or 30
	if blast then
		local cone = Effects.cone(folder, CFrame.new(root.Position) * facing.Rotation, radius, d.cone or 80, Palette.SpeechRing)
		local fader = VfxUtil.fader(cone)
		fader.set(0)
		VfxUtil.animate(0.12, function(a)
			fader.set(a)
		end, function()
			VfxUtil.fade(cone, 0.35, 0.1)
		end)
	else
		local shell = PartKit.ball(folder, CFrame.new(root.Position), 2, { Color = Palette.SpeechRing, Material = Enum.Material.ForceField }, "Shell")
		VfxUtil.tween(shell, 0.35, { Size = Vector3.one * radius * 2 })
		VfxUtil.fade(shell, 0.4, 0.3)
		local ground = VfxUtil.ground(root.Position)
		local ring = VfxUtil.liveRing(folder, CFrame.new(ground + Vector3.new(0, 0.3, 0)), 40, 0.6, 1, Palette.SpeechRing)
		VfxUtil.animate(0.4, function(a)
			ring.set(2 + (radius - 2) * (1 - (1 - a) ^ 2), a * 0.9)
		end, function()
			for _, p in ring.parts do
				p:Destroy()
			end
		end)
	end
	-- The words tear Yuta's throat.
	VfxUtil.burst(mouth.Position, {
		Texture = PartKit.Textures.Sparkle,
		Color = ColorSequence.new(Color3.fromRGB(160, 20, 30)),
		Size = NumberSequence.new(0.2, 0),
		Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, -25, 0),
	}, 8)
	if near(root.Position, radius + 20) then
		CameraFX.shake(0.4, 0.35)
	end
	VfxUtil.sound("Speech", head)
end

local function healAura(model: Model, duration: number, size: number)
	local root = VfxUtil.root(model)
	if not root then
		return
	end
	local folder = VfxUtil.folder()
	local aura = PartKit.ball(folder, root.CFrame, size, { Color = Palette.RCT, Material = Enum.Material.ForceField }, "Aura")
	local ringModel = PartKit.model("HealRing", folder)
	PartKit.ring(ringModel, CFrame.new(), size * 0.5, 0.3, 0.1, 20, { Color = Palette.RCT, Material = NEON })
	ringModel.WorldPivot = CFrame.new()
	VfxUtil.animate(duration, function(a)
		if not root.Parent then
			return false
		end
		aura.CFrame = root.CFrame
		aura.Transparency = 0.1 + 0.8 * a
		ringModel:PivotTo(CFrame.new(root.Position - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, a * 8, 0))
		return true
	end, function()
		aura:Destroy()
		ringModel:Destroy()
	end)
	local att = Instance.new("Attachment")
	att.Parent = root
	PartKit.emitter(att, {
		Texture = PartKit.Textures.Sparkle,
		Color = ColorSequence.new(Palette.RCT),
		LightEmission = 1,
		Size = NumberSequence.new(0.35, 0),
		Lifetime = NumberRange.new(0.8, 1.3),
		Rate = 30,
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(60, 60),
		Acceleration = Vector3.new(0, 6, 0),
	})
	Debris:AddItem(att, duration)
end

handlers.RCT = function(d)
	local root = VfxUtil.root(d.char)
	if not root then
		return
	end
	local duration: number = d.duration or 2
	healAura(d.char, duration, 7)
	for _, ally in d.allies or {} do
		if typeof(ally) == "Instance" and ally:IsA("Model") then
			healAura(ally, duration, 5)
		end
	end
	VfxUtil.kanji(root.Position + Vector3.new(0, 5, 0), "反転術式", 2, Palette.RCT, 1.2)
end

-- Pure Love ---------------------------------------------------------------------------------

handlers.PureLoveCharge = function(d)
	if typeof(d.char) ~= "Instance" or not d.char:IsA("Model") then
		return
	end
	local char: Model = d.char
	local root = VfxUtil.root(char)
	if not root then
		return
	end
	local time: number = d.time or 1.35
	RikaFollower.charge(char, time)
	local dir: Vector3 = d.dir or root.CFrame.LookVector
	local folder = VfxUtil.folder()
	local function focus(): Vector3
		return root.Position + Vector3.new(0, 1.5, 0) + dir * 3
	end
	local core = PartKit.ball(folder, CFrame.new(focus()), 0.5, { Color = Palette.PureLoveCore, Material = NEON }, "Core")
	local glow = PartKit.ball(folder, CFrame.new(focus()), 1, { Color = Palette.PureLove, Material = NEON, Transparency = 0.5 }, "Glow")
	PartKit.light(core, Palette.PureLove, 24, 3)
	type Mote = { part: Part, from: Vector3, delay: number }
	local motes: { Mote } = {}
	for i = 1, 18 do
		local p = PartKit.ball(folder, CFrame.new(focus() + Effects.randomUnit(rng) * rng:NextNumber(7, 14)), rng:NextNumber(0.3, 0.7), {
			Color = if i % 2 == 0 then Palette.PureLove else Palette.PureLoveCore,
			Material = NEON,
		}, "Mote")
		table.insert(motes, { part = p, from = p.Position, delay = rng:NextNumber(0, time * 0.4) })
	end
	local ground = VfxUtil.ground(root.Position)
	local ring = VfxUtil.liveRing(folder, CFrame.new(ground + Vector3.new(0, 0.3, 0)), 30, 0.5, 0.8, Palette.PureLove)
	VfxUtil.animate(time, function(a)
		local f = focus()
		core.CFrame = CFrame.new(f)
		glow.CFrame = CFrame.new(f)
		core.Size = Vector3.one * (0.5 + a * 3.2)
		glow.Size = Vector3.one * (1 + a * 6)
		for _, m in motes do
			local t = math.clamp((a * time - m.delay) / math.max(0.05, time - m.delay), 0, 1)
			m.part.Position = m.from:Lerp(f, t * t)
			m.part.Transparency = t * 0.8
		end
		ring.set(9 - 6 * a, 0.2 + 0.6 * a)
	end, function()
		for _, m in motes do
			m.part:Destroy()
		end
		for _, p in ring.parts do
			p:Destroy()
		end
		VfxUtil.fade(core, 0.2)
		VfxUtil.fade(glow, 0.2)
	end)
	VfxUtil.kanji(root.Position + Vector3.new(0, 8, 0), "純愛砲", 3.6, Palette.PureLove, time + 0.4, 0.2)
	VfxUtil.sound("Beam", root)
end

handlers.PureLoveBeam = function(d)
	local cf: CFrame = d.cf
	local length: number = d.length or 180
	local width: number = d.width or 14
	local duration: number = d.duration or 1.3
	local folder = VfxUtil.folder()
	local beam = Effects.beam(folder, cf, length, width, Palette.PureLove, Palette.PureLove, Palette.PureLoveCore)
	local layers: { { part: BasePart, scale: number } } = {}
	for _, spec in { { name = "Outer", scale = 1 }, { name = "Mid", scale = 0.72 }, { name = "Core", scale = 0.38 } } do
		local p = beam:FindFirstChild(spec.name)
		if p and p:IsA("BasePart") then
			table.insert(layers, { part = p, scale = spec.scale })
		end
	end
	local function set(l: number, w: number)
		for _, layer in layers do
			local dia = math.max(0.05, width * layer.scale * w)
			layer.part.Size = Vector3.new(math.max(0.1, l), dia, dia)
			layer.part.CFrame = cf * CFrame.new(0, 0, -l / 2) * CFrame.Angles(0, math.rad(90), 0)
		end
	end
	set(0.5, 1)
	VfxUtil.animate(0.14, function(a)
		set(length * a, 1)
	end, function()
		VfxUtil.animate(duration, function(a)
			set(length, 1 + math.sin(a * 40) * 0.06)
		end, function()
			VfxUtil.animate(0.3, function(a)
				set(length, 1 - a)
			end, function()
				beam:Destroy()
			end)
		end)
	end)
	-- Scorched line on the ground under the beam.
	local ground = VfxUtil.ground(cf.Position)
	if cf.Position.Y - ground.Y < width then
		local flatDir = Util.flatUnit(cf.LookVector)
		local scar = PartKit.part({
			Name = "Scorch",
			Parent = folder,
			CFrame = Util.facing(ground + Vector3.new(0, 0.07, 0), flatDir) * CFrame.new(0, 0, -length / 2),
			Size = Vector3.new(width * 0.8, 0.1, length),
			Color = Color3.fromRGB(40, 12, 34),
			Material = Enum.Material.Slate,
		})
		VfxUtil.fade(scar, 2, 4)
	end
	if near(cf.Position, 140) then
		HUD.flash(Palette.PureLove, 0.5, 0.35)
	end
	VfxUtil.sound("Beam", cf.Position)
end

-- Domain Expansion: Authentic Mutual Love ------------------------------------------------------

type DomainRecord = { Model: Model?, Conn: RBXScriptConnection?, Tint: ColorCorrectionEffect?, Center: Vector3, Radius: number }
local domains: { [string]: DomainRecord } = {}

handlers.DomainCast = function(d)
	local root = VfxUtil.root(d.char)
	if not root then
		return
	end
	local time: number = d.time or 1.6
	local folder = VfxUtil.folder()
	local ground = VfxUtil.ground(root.Position)
	local column = PartKit.cylinderY({ Name = "Column", Parent = folder, CFrame = CFrame.new(ground + Vector3.new(0, 20, 0)), Color = Palette.Shadow, Material = NEON, Transparency = 1 }, 40, 7)
	VfxUtil.tween(column, time * 0.6, { Transparency = 0.35 })
	VfxUtil.fade(column, 0.3, time)
	local ring = VfxUtil.liveRing(folder, CFrame.new(ground + Vector3.new(0, 0.3, 0)), 32, 0.4, 0.7, Palette.DomainSky)
	VfxUtil.animate(time, function(a)
		ring.set(3 + a * 6, 0.2)
	end, function()
		for _, p in ring.parts do
			p:Destroy()
		end
	end)
	VfxUtil.kanji(root.Position + Vector3.new(0, 6, 0), "領域展開", 3, WHITE, time, 0.15)
	if isMe(d.char) then
		HUD.flash(Color3.new(0, 0, 0), time, 0.25)
	end
end

local function endDomain(id: string)
	local record = domains[id]
	if not record then
		return
	end
	domains[id] = nil
	if record.Conn then
		record.Conn:Disconnect()
	end
	if record.Tint then
		record.Tint:Destroy()
	end
	local model = record.Model
	if not model then
		return
	end
	local dome = model:FindFirstChild("Dome")
	if dome then
		for _, panel in dome:GetChildren() do
			if panel:IsA("BasePart") then
				VfxUtil.tween(panel, 0.9, { CFrame = panel.CFrame * CFrame.new(0, 0, rng:NextNumber(4, 10)), Transparency = 1 })
			end
		end
	end
	VfxUtil.fade(model, 0.9, 0.1)
end

handlers.DomainExpand = function(d)
	local id: string = d.id
	local center: Vector3 = d.center
	local radius: number = d.radius or 62
	local duration: number = d.duration or 14
	local folder = VfxUtil.folder()
	local record: DomainRecord = { Center = center, Radius = radius }
	domains[id] = record

	-- The domain closes like a black sphere first.
	local void = PartKit.ball(folder, CFrame.new(center), 2, { Color = Palette.Shadow }, "Void")
	VfxUtil.tween(void, 0.45, { Size = Vector3.one * radius * 2.05 }, Enum.EasingStyle.Quart)
	if near(center, radius + 30) then
		CameraFX.shake(1, 0.8)
		HUD.flash(Color3.new(0, 0, 0), 0.8, 0.8)
	end

	task.spawn(function()
		local seed = math.floor(math.abs(center.X * 7 + center.Z * 13)) % 9973 + 1
		local model = Domain.build(nil, CFrame.new(center), radius, seed, 48, function(i: number)
			if i % 12 == 0 then
				RunService.Heartbeat:Wait()
			end
		end)
		if domains[id] ~= record then
			model:Destroy()
			return
		end
		record.Model = model

		-- Swords start buried and rise out of the ground.
		type Rising = { model: Model, final: CFrame, delay: number }
		local rising: { Rising } = {}
		local swords = model:FindFirstChild("Swords")
		if swords then
			for _, sword in swords:GetChildren() do
				if sword:IsA("Model") then
					local final = sword:GetPivot()
					sword:PivotTo(final * CFrame.new(0, 9, 0))
					table.insert(rising, { model = sword, final = final, delay = rng:NextNumber(0, 0.5) })
				end
			end
		end
		model.Parent = folder
		VfxUtil.tween(void, 0.5, { Transparency = 1 })
		Debris:AddItem(void, 0.6)
		VfxUtil.animate(1.1, function(a)
			local t = a * 1.1
			for _, r in rising do
				local k = math.clamp((t - r.delay) / 0.5, 0, 1)
				local eased = 1 - (1 - k) ^ 3
				r.model:PivotTo(r.final * CFrame.new(0, 9 * (1 - eased), 0))
			end
		end)

		type Gear = { model: Model, base: CFrame, speed: number }
		local gears: { Gear } = {}
		local gearFolder = model:FindFirstChild("Gears")
		if gearFolder then
			for i, gear in gearFolder:GetChildren() do
				if gear:IsA("Model") then
					table.insert(gears, { model = gear, base = gear:GetPivot(), speed = (if i % 2 == 0 then 1 else -1) * (0.15 + i * 0.04) })
				end
			end
		end
		local started = os.clock()
		record.Conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - started
			for _, g in gears do
				g.model:PivotTo(g.base * CFrame.Angles(t * g.speed, 0, 0))
			end
			local inside = near(center, radius)
			if inside and not record.Tint then
				local tint = Instance.new("ColorCorrectionEffect")
				tint.Name = "JJK_DomainTint"
				tint.TintColor = Color3.fromRGB(255, 196, 204)
				tint.Contrast = 0.18
				tint.Saturation = -0.12
				tint.Parent = Lighting
				record.Tint = tint
			elseif not inside and record.Tint then
				record.Tint:Destroy()
				record.Tint = nil
			end
		end)
	end)

	-- Safety net if the end event is missed.
	task.delay(duration + 4, function()
		endDomain(id)
	end)
	VfxUtil.sound("Domain", center)
end

handlers.DomainHit = function(d)
	local pos: Vector3 = d.pos
	local folder = VfxUtil.folder()
	if d.kind == "Swords" then
		for i = 1, 4 do
			task.delay((i - 1) * 0.05, function()
				local target = pos + Vector3.new(rng:NextNumber(-2.5, 2.5), rng:NextNumber(-1, 1), rng:NextNumber(-2.5, 2.5))
				local start = target + Vector3.new(rng:NextNumber(-7, 7), 24, rng:NextNumber(-7, 7))
				local aim = PartKit.lookAt(start, target) * CFrame.Angles(math.rad(-90), 0, 0)
				local sword = Katana.buildModel(folder, aim, 1.4, "lite")
				local offset = target - start
				VfxUtil.animate(0.16, function(a)
					sword:PivotTo(aim + offset * (a * a))
				end, function()
					handlers.Hit({ pos = target, color = Palette.PureLove, big = false })
					VfxUtil.fade(sword, 0.3, 0.4)
				end)
			end)
		end
	elseif d.kind == "Speech" then
		VfxUtil.kanji(pos + Vector3.new(0, 6, 0), "動くな", 3, WHITE, 0.8, 0.3)
		local ring = VfxUtil.liveRing(folder, CFrame.new(pos), 24, 0.4, 0.5, Palette.SpeechRing)
		VfxUtil.animate(0.35, function(a)
			ring.set(1 + a * 8, a)
		end, function()
			for _, p in ring.parts do
				p:Destroy()
			end
		end)
	else
		local claws = Effects.claws(folder, CFrame.new(pos + Vector3.new(0, 1, 3)), 5, Palette.RikaAura)
		VfxUtil.fade(claws, 0.3, 0.2)
	end
end

handlers.DomainEnd = function(d)
	endDomain(d.id)
end

-- Six Eyes / Limitless -----------------------------------------------------------------------

handlers.SixEyesCast = function(d)
	local head = VfxUtil.head(d.char)
	local root = VfxUtil.root(d.char)
	if not head or not root then
		return
	end
	local time: number = d.time or 1.4
	local folder = VfxUtil.folder()
	for _, side in { -1, 1 } do
		local eye = PartKit.ball(folder, head.CFrame * CFrame.new(side * 0.22, 0.08, -0.62), 0.2, { Color = Palette.SixEyes, Material = NEON }, "Eye")
		VfxUtil.tween(eye, time, { Size = Vector3.one * 1.2 })
		VfxUtil.fade(eye, 0.2, time)
	end
	local ring = VfxUtil.liveRing(folder, head.CFrame * CFrame.Angles(math.rad(90), 0, 0), 24, 0.12, 0.2, Palette.SixEyes)
	VfxUtil.animate(time, function(a)
		ring.set(1 + a * 3, 0.2 + a * 0.6)
	end, function()
		for _, p in ring.parts do
			p:Destroy()
		end
	end)
	VfxUtil.kanji(head.Position + Vector3.new(0, 3.2, 0), "六眼", 2.6, Palette.SixEyes, time, 0.1)
	local att = Instance.new("Attachment")
	att.Parent = root
	PartKit.emitter(att, {
		Texture = PartKit.Textures.Sparkle,
		Color = ColorSequence.new(Palette.SixEyes, WHITE),
		LightEmission = 1,
		Size = NumberSequence.new(0.3, 0),
		Lifetime = NumberRange.new(0.6, 1),
		Rate = 40,
		Speed = NumberRange.new(3, 6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 8, 0),
	})
	Debris:AddItem(att, time)
end

handlers.SixEyesAwaken = function(d)
	local root = VfxUtil.root(d.char)
	if not root then
		return
	end
	local folder = VfxUtil.folder()
	local flash = PartKit.ball(folder, root.CFrame, 2, { Color = WHITE, Material = NEON, Transparency = 0.2 }, "Flash")
	VfxUtil.tween(flash, 0.35, { Size = Vector3.one * 26, Transparency = 1, Color = Palette.SixEyes })
	Debris:AddItem(flash, 0.4)
	local shell = Effects.infinity(folder, root.Position, 4)
	VfxUtil.fade(shell, 0.6, 0.3)
	if isMe(d.char) then
		HUD.flash(Palette.SixEyes, 0.6, 0.5)
	end
	if near(root.Position, 90) then
		CameraFX.shake(0.7, 0.5)
	end
end

handlers.SixEyesEnd = function(d)
	local root = VfxUtil.root(d.char)
	if root then
		VfxUtil.burst(root.Position + Vector3.new(0, 2, 0), {
			Texture = PartKit.Textures.Sparkle,
			Color = ColorSequence.new(Palette.SixEyes),
			LightEmission = 1,
			Size = NumberSequence.new(0.4, 0),
			Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(4, 9),
			SpreadAngle = Vector2.new(180, 180),
		}, 20)
	end
end

local lastInfinity: { [Instance]: number } = {}
handlers.Infinity = function(d)
	local char = d.char
	local root = VfxUtil.root(char)
	if not root then
		return
	end
	local now = os.clock()
	if (lastInfinity[char] or 0) > now - 0.15 then
		return
	end
	lastInfinity[char] = now
	local adapted: number = d.adapted or 0
	local shell = Effects.infinity(VfxUtil.folder(), root.Position, 3.2)
	local color = Palette.SixEyes:Lerp(Palette.Danger, adapted)
	for _, p in VfxUtil.parts(shell) do
		p.Color = color
	end
	VfxUtil.fade(shell, 0.35, 0.05)
end

handlers.Blue = function(d)
	local pos: Vector3 = d.pos
	local radius: number = d.radius or 16
	local duration: number = d.duration or 1.6
	local folder = VfxUtil.folder()
	local m = Effects.blue(folder, pos, radius)
	m.WorldPivot = CFrame.new(pos)
	local shellPart = PartKit.ball(folder, CFrame.new(pos), radius * 1.6, { Transparency = 1 }, "Pull")
	local emitter = PartKit.emitter(shellPart, {
		Texture = PartKit.Textures.Sparkle,
		Color = ColorSequence.new(Palette.BlueCore, Palette.Blue),
		LightEmission = 1,
		Size = NumberSequence.new(0.5, 0.1),
		Lifetime = NumberRange.new(0.4, 0.6),
		Rate = 90,
		Speed = NumberRange.new(20, 28),
	})
	pcall(function()
		emitter.Shape = Enum.ParticleEmitterShape.Sphere
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		emitter.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	end)
	local core = m:FindFirstChild("Core")
	VfxUtil.animate(duration, function(a)
		m:PivotTo(CFrame.new(pos) * CFrame.Angles(0, a * duration * 7, 0))
		if core and core:IsA("BasePart") then
			core.Size = Vector3.one * radius * 0.2 * (1 + math.sin(a * 60) * 0.15)
		end
	end, function()
		emitter.Enabled = false
		Debris:AddItem(shellPart, 0.7)
		local flash = PartKit.ball(folder, CFrame.new(pos), radius * 0.5, { Color = Palette.BlueCore, Material = NEON, Transparency = 0.2 }, "Implode")
		VfxUtil.tween(flash, 0.18, { Size = Vector3.one * 0.2, Transparency = 1 })
		Debris:AddItem(flash, 0.2)
		VfxUtil.fade(m, 0.15)
	end)
	VfxUtil.kanji(pos + Vector3.new(0, radius * 0.5 + 3, 0), "蒼", 3, Palette.Blue, 0.9)
	VfxUtil.sound("Blue", pos)
end

type Projectile = { Model: Model, Alive: boolean }
local projectiles: { [string]: Projectile } = {}

handlers.RedFire = function(d)
	local id: string = d.id
	local origin: Vector3 = d.origin
	local dir: Vector3 = d.dir
	local speed: number = d.speed or 150
	local range: number = d.range or 95
	local m = Effects.red(VfxUtil.folder(), origin, 1.4, rng)
	m.WorldPivot = CFrame.new(origin)
	local record: Projectile = { Model = m, Alive = true }
	projectiles[id] = record
	local core = m:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.8, 0)
		a0.Parent = core
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.8, 0)
		a1.Parent = core
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(Palette.RedCore, Palette.Red)
		trail.Transparency = NumberSequence.new(0.1, 1)
		trail.WidthScale = NumberSequence.new(1, 0.2)
		trail.Parent = core
	end
	local start = os.clock()
	VfxUtil.animate(range / speed + 0.6, function()
		if not record.Alive then
			return false
		end
		local t = os.clock() - start
		m:PivotTo(CFrame.new(origin + dir * math.min(range, t * speed)) * CFrame.Angles(t * 9, t * 7, 0))
		return true
	end, function()
		if record.Alive then
			record.Alive = false
			m:Destroy()
			projectiles[id] = nil
		end
	end)
	VfxUtil.sound("Red", origin)
end

handlers.RedBoom = function(d)
	local record = projectiles[d.id]
	if record then
		record.Alive = false
		record.Model:Destroy()
		projectiles[d.id] = nil
	end
	local pos: Vector3 = d.pos
	local radius: number = d.radius or 15
	local folder = VfxUtil.folder()
	local blast = PartKit.ball(folder, CFrame.new(pos), 2, { Color = Palette.Red, Material = NEON, Transparency = 0.1 }, "Blast")
	VfxUtil.tween(blast, 0.25, { Size = Vector3.one * radius * 2, Transparency = 1 })
	Debris:AddItem(blast, 0.3)
	local core = PartKit.ball(folder, CFrame.new(pos), 1, { Color = Palette.RedCore, Material = NEON }, "BlastCore")
	VfxUtil.tween(core, 0.2, { Size = Vector3.one * radius * 0.8, Transparency = 1 })
	Debris:AddItem(core, 0.25)
	local spikes = Effects.spikes(folder, pos, 12, radius * 0.7, Palette.Red, rng)
	VfxUtil.fade(spikes, 0.25, 0.05)
	handlers.Impact({ pos = VfxUtil.ground(pos), radius = radius, color = Palette.Red, cracks = true })
	VfxUtil.kanji(pos + Vector3.new(0, 5, 0), "赫", 3, Palette.Red, 0.8)
	if near(pos, 60) then
		HUD.flash(Palette.Red, 0.3, 0.25)
	end
end

handlers.PurpleCharge = function(d)
	local root = VfxUtil.root(d.char)
	if not root then
		return
	end
	local time: number = d.time or 1.6
	local folder = VfxUtil.folder()
	local blue = Effects.orb(folder, root.Position, 1.1, Palette.BlueCore, Palette.Blue)
	local red = Effects.orb(folder, root.Position, 1.1, Palette.RedCore, Palette.Red)
	blue.WorldPivot = CFrame.new(root.Position)
	red.WorldPivot = CFrame.new(root.Position)
	local mergePoint = root.Position
	VfxUtil.animate(time, function(a)
		if not root.Parent then
			return false
		end
		local cf = root.CFrame
		local spread = 3.4 * (1 - a) ^ 1.4 + 0.1
		local forward = -1.5 - a * 1.8
		local wobble = math.sin(a * math.pi * 6) * 0.3 * (1 - a)
		blue:PivotTo(CFrame.new((cf * CFrame.new(-spread, 2 + wobble, forward)).Position))
		red:PivotTo(CFrame.new((cf * CFrame.new(spread, 2 - wobble, forward)).Position))
		mergePoint = (cf * CFrame.new(0, 2, forward)).Position
		return true
	end, function()
		blue:Destroy()
		red:Destroy()
		local flash = PartKit.ball(folder, CFrame.new(mergePoint), 1, { Color = Palette.PurpleCore, Material = NEON }, "Merge")
		VfxUtil.tween(flash, 0.25, { Size = Vector3.one * 12, Transparency = 1, Color = Palette.Purple })
		Debris:AddItem(flash, 0.3)
	end)
	VfxUtil.kanji(root.Position + Vector3.new(0, 7, 0), "虚式「茈」", 3, Palette.Purple, time + 0.3, 0.1)
	if isMe(d.char) then
		HUD.flash(Palette.Purple, time, 0.15)
	end
	VfxUtil.sound("Purple", root)
end

handlers.PurpleFire = function(d)
	local origin: Vector3 = d.origin
	local dir: Vector3 = d.dir
	local speed: number = d.speed or 115
	local range: number = d.range or 230
	local radius: number = d.radius or 9
	local folder = VfxUtil.folder()
	local m = Effects.purple(folder, origin, radius * 0.8, rng)
	m.WorldPivot = CFrame.new(origin)
	local start = os.clock()
	local lastScar = 0
	VfxUtil.animate(range / speed, function()
		local t = os.clock() - start
		local dist = math.min(range, t * speed)
		local pos = origin + dir * dist
		m:PivotTo(CFrame.new(pos) * CFrame.Angles(t * 4, t * 6, t * 2))
		if dist - lastScar > 7 then
			lastScar = dist
			local ground = VfxUtil.ground(pos)
			if pos.Y - ground.Y < radius * 1.5 then
				local scar = PartKit.part({
					Name = "Erased",
					Parent = folder,
					CFrame = Util.facing(ground + Vector3.new(0, 0.06, 0), dir),
					Size = Vector3.new(radius * 1.7, 0.1, 8),
					Color = Color3.fromRGB(26, 10, 36),
					Material = Enum.Material.Slate,
				})
				VfxUtil.fade(scar, 1.5, 3)
				local glow = PartKit.part({
					Name = "ErasedGlow",
					Parent = folder,
					CFrame = Util.facing(ground + Vector3.new(0, 0.1, 0), dir),
					Size = Vector3.new(radius * 0.5, 0.08, 8),
					Color = Palette.Purple,
					Material = NEON,
				})
				VfxUtil.fade(glow, 0.8, 0.4)
			end
		end
	end, function()
		VfxUtil.fade(m, 0.4)
	end)
	if near(origin, 160) then
		HUD.flash(Palette.Purple, 0.5, 0.35)
	end
	VfxUtil.sound("Purple", origin)
end

-- Dispatcher ---------------------------------------------------------------------------------

function VFX.start()
	for name, handler in BossVFX.handlers do
		if not handlers[name] then
			handlers[name] = handler
		end
	end
	local remote = Net.event("FX")
	remote.OnClientEvent:Connect(function(name: any, data: any)
		if typeof(name) ~= "string" then
			return
		end
		local handler = handlers[name]
		if not handler then
			return
		end
		task.spawn(function()
			xpcall(handler, function(err)
				warn(("[JJK FX] %s failed: %s"):format(name, tostring(err)))
			end, if typeof(data) == "table" then data else {})
		end)
	end)
end

return VFX
