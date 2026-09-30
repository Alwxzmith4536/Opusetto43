--!strict
--[[
	Client effects for Mahoraga: ground telegraphs, Sword of Extermination arcs,
	shockwaves, positive-energy rings, the adaptation wheel, summoning and death.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Palette = require(Shared:WaitForChild("Palette"))
local Util = require(Shared:WaitForChild("Util"))
local Assets = Shared:WaitForChild("Assets")
local PartKit = require(Assets:WaitForChild("PartKit"))
local Effects = require(Assets:WaitForChild("Effects"))
local Mahoraga = require(Assets:WaitForChild("Mahoraga"))

local VfxUtil = require(script.Parent.VfxUtil)
local HUD = require(script.Parent.HUD)
local CameraFX = require(script.Parent.CameraFX)

local NEON = Enum.Material.Neon
local WHITE = Color3.new(1, 1, 1)

local player = Players.LocalPlayer
local rng = VfxUtil.rng

local BossVFX = {}
local handlers: { [string]: (any) -> () } = {}
BossVFX.handlers = handlers

local function near(pos: Vector3, radius: number): boolean
	local root = VfxUtil.root(player.Character)
	return root ~= nil and (root.Position - pos).Magnitude <= radius
end

local function clearRing(ring: VfxUtil.LiveRing)
	for _, p in ring.parts do
		p:Destroy()
	end
end

-- Ground warning that fills up until the attack lands.
handlers.Telegraph = function(d)
	local folder = VfxUtil.folder()
	local color: Color3 = d.color or Palette.Danger
	local time: number = d.time or 0.8
	local cf: CFrame = d.cf
	local shape: string = d.shape or "circle"
	local t: Effects.Telegraph
	if shape == "circle" then
		t = Effects.telegraphCircle(folder, cf, d.radius, color)
	elseif shape == "rect" then
		t = Effects.telegraphRect(folder, cf, d.width, d.length, color)
	else
		t = Effects.telegraphArc(folder, cf, d.radius, d.arc, color)
	end
	local base = cf * CFrame.new(0, 0.16, 0)
	VfxUtil.animate(time, function(a)
		if shape == "circle" then
			local dia = math.max(0.1, d.radius * 2 * a)
			t.Progress[1].Size = Vector3.new(0.05, dia, dia)
		elseif shape == "rect" then
			local len = math.max(0.1, d.length * a)
			t.Progress[1].Size = Vector3.new(d.width, 0.05, len)
			t.Progress[1].CFrame = base * CFrame.new(0, 0, -len / 2)
		else
			local len = math.max(0.1, d.radius * a)
			for _, p in t.Progress do
				local angle = (p:GetAttribute("Angle") or 0) :: number
				p.Size = Vector3.new(p.Size.X, 0.05, len)
				p.CFrame = base * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -len / 2)
			end
		end
		local pulse = 0.15 + 0.35 * math.abs(math.sin(a * math.pi * 5))
		for _, p in t.Outline do
			p.Transparency = pulse
		end
	end, function()
		for _, p in t.Outline do
			p.Transparency = 0
		end
		VfxUtil.fade(t.Model, 0.18)
	end)
end

-- Sword of Extermination: a wide crescent of positive energy.
handlers.BossSlash = function(d)
	local cf: CFrame = d.cf
	local cleave = d.kind == "cleave"
	local slash = Effects.slash(VfxUtil.folder(), cf, d.radius or 19, d.arc or 200, if cleave then 3.2 else 2.8, Palette.Positive, Palette.PositiveCore, 26)
	local n = #slash.Outer
	local outerBase, coreBase = {}, {}
	for i = 1, n do
		outerBase[i] = slash.Outer[i].Transparency
		coreBase[i] = slash.Core[i].Transparency
		slash.Outer[i].Transparency = 1
		slash.Core[i].Transparency = 1
	end
	VfxUtil.animate(0.1, function(a)
		local shown = math.floor(a * n + 0.5)
		for k = 1, shown do
			local i = n - k + 1 -- Mahoraga swings from its left to its right
			slash.Outer[i].Transparency = outerBase[i]
			slash.Core[i].Transparency = coreBase[i]
		end
	end, function()
		VfxUtil.fade(slash.Model, 0.35)
	end)
	for i = 1, n, 4 do
		VfxUtil.burst(slash.Core[i].Position, {
			Texture = PartKit.Textures.Spark,
			Color = ColorSequence.new(Palette.PositiveCore, Palette.Positive),
			LightEmission = 1,
			Size = NumberSequence.new(0.6, 0),
			Lifetime = NumberRange.new(0.25, 0.5),
			Speed = NumberRange.new(10, 22),
			SpreadAngle = Vector2.new(60, 60),
		}, 4)
	end
	VfxUtil.sound("BossSlash", cf.Position)
end

-- Shockwave racing along the cleave line: rock spikes and a bright scar.
handlers.BossWave = function(d)
	local cf: CFrame = d.cf
	local length: number = d.length or 70
	local width: number = d.width or 10
	local folder = VfxUtil.folder()
	local steps = math.floor(length / 5)
	for i = 1, steps do
		task.delay(i * 0.022, function()
			local p = cf * CFrame.new(rng:NextNumber(-width * 0.3, width * 0.3), 0, -i * 5)
			local size = rng:NextNumber(0.7, 1.3)
			local final = p * CFrame.new(0, 1.4 * size, 0) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), rng:NextNumber(-0.4, 0.4))
			local spike = PartKit.part({
				Name = "Spike",
				Parent = folder,
				CFrame = final * CFrame.new(0, -4, 0),
				Size = Vector3.new(2.2, 4.5, 2.2) * size,
				Color = Color3.fromRGB(96, 90, 98),
				Material = Enum.Material.Slate,
			})
			VfxUtil.tween(spike, 0.12, { CFrame = final })
			VfxUtil.fade(spike, 0.5, 0.8)
			local glow = PartKit.part({ Name = "Scar", Parent = folder, CFrame = p * CFrame.new(0, 0.2, 0), Size = Vector3.new(width * 0.7, 0.2, 5.4), Color = Palette.Positive, Material = NEON, Transparency = 0.15 })
			VfxUtil.fade(glow, 0.5, 0.2)
		end)
	end
	local cracks = Effects.cracks(folder, cf * CFrame.new(0, 0, -length * 0.5), length * 0.45, 7, rng)
	VfxUtil.fade(cracks, 1, 2)
end

handlers.BossRush = function(d)
	local from: Vector3 = d.from
	local to: Vector3 = d.to
	local folder = VfxUtil.folder()
	local frame = CFrame.lookAt(from, Vector3.new(to.X, from.Y, to.Z))
	for _ = 1, 12 do
		local x, y = rng:NextNumber(-7, 7), rng:NextNumber(-10, 12)
		local a = (frame * CFrame.new(x, y, 0)).Position
		local b = (frame * CFrame.new(x, y, -(to - from).Magnitude)).Position
		local line = PartKit.segment({ Name = "Wind", Parent = folder, Color = WHITE, Material = NEON, Transparency = 0.35 }, a, b, 0.22)
		VfxUtil.fade(line, 0.35, 0.1)
	end
	for k = 0, 2 do
		local p = from:Lerp(to, k / 2)
		VfxUtil.burst(VfxUtil.ground(p) + Vector3.new(0, 1, 0), {
			Texture = PartKit.Textures.Smoke,
			Color = ColorSequence.new(Color3.fromRGB(130, 122, 132)),
			Size = NumberSequence.new(3, 6),
			Transparency = NumberSequence.new(0.4, 1),
			Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(6, 12),
			SpreadAngle = Vector2.new(85, 85),
		}, 10)
	end
end

-- Rings of positive energy rolling outward (jump to avoid them).
handlers.BossRings = function(d)
	local center: Vector3 = d.center
	local count: number = d.count or 3
	local interval: number = d.interval or 0.65
	local speed: number = d.speed or 32
	local maxRadius: number = d.maxRadius or 75
	local folder = VfxUtil.folder()
	for k = 1, count do
		task.delay((k - 1) * interval, function()
			local wall = VfxUtil.liveRing(folder, CFrame.new(center + Vector3.new(0, 1.6, 0)), 56, 3.2, 1.0, Palette.Positive)
			local core = VfxUtil.liveRing(folder, CFrame.new(center + Vector3.new(0, 0.25, 0)), 56, 0.4, 2.2, Palette.PositiveCore)
			VfxUtil.animate(maxRadius / speed, function(a)
				local r = math.max(0.5, maxRadius * a)
				wall.set(r, 0.15 + 0.6 * a ^ 3)
				core.set(r, 0.3 + 0.6 * a ^ 3)
			end, function()
				clearRing(wall)
				clearRing(core)
			end)
			if near(center, maxRadius + 20) then
				CameraFX.shake(0.35, 0.3)
			end
		end)
	end
end

-- The Dharma wheel turns: flash it, burst a golden ring, and call out what it adapted to.
handlers.WheelTurn = function(d)
	local model = d.boss
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "WheelGlow" then
			p.Transparency = 0.05
			VfxUtil.tween(p, 0.9, { Transparency = 1 })
		end
	end
	local core = model:FindFirstChild("WheelCore")
	local pos = if core and core:IsA("BasePart") then core.Position else (model:GetPivot().Position + Vector3.new(0, 28, 0))
	local folder = VfxUtil.folder()
	local ring = VfxUtil.liveRing(folder, CFrame.new(pos), 32, 0.4, 0.5, Palette.Positive)
	VfxUtil.animate(0.6, function(a)
		ring.set(3.6 + a * 16, a)
	end, function()
		clearRing(ring)
	end)
	local level: number = d.level or 1
	local maxLevel: number = d.maxLevel or 4
	local name = string.upper(tostring(d.typeName or "?"))
	local full = level >= maxLevel
	local text = if full then ("FULLY ADAPTED: %s"):format(name) else ("ADAPTING: %s  %d/%d"):format(name, level, maxLevel)
	VfxUtil.kanji(pos + Vector3.new(0, 4.5, 0), text, 2.4, if full then Palette.Danger else Palette.Wheel, 1.8)
	if full and near(pos, 200) then
		HUD.notify(("Mahoraga has fully adapted to %s. Switch techniques!"):format(tostring(d.typeName)))
	end
	VfxUtil.sound("WheelTurn", pos)
end

-- Ten Shadows summoning: a pool of shadow, a pillar of light, and the wheel rising first.
handlers.Summon = function(d)
	local pos: Vector3 = d.pos
	local time: number = d.time or 3
	local folder = VfxUtil.folder()
	local pool = PartKit.cylinderY({ Name = "Pool", Parent = folder, CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)), Color = Palette.Shadow }, 0.08, 1)
	VfxUtil.tween(pool, 0.6, { Size = Vector3.new(0.08, 34, 34) })
	local edge = VfxUtil.liveRing(folder, CFrame.new(pos + Vector3.new(0, 0.14, 0)), 40, 0.1, 0.9, Palette.YutaEnergy)
	VfxUtil.animate(0.6, function(a)
		edge.set(0.5 + 16.5 * (1 - (1 - a) ^ 3))
	end)
	local smoke = PartKit.emitter(pool, {
		Texture = PartKit.Textures.Smoke,
		Color = ColorSequence.new(Palette.Shadow, Palette.YutaDark),
		Size = NumberSequence.new(3, 6),
		Transparency = NumberSequence.new(0.2, 1),
		Lifetime = NumberRange.new(1, 1.6),
		Rate = 40,
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(30, 30),
		EmissionDirection = Enum.NormalId.Right, -- cylinder's local +X points up
	})
	if not d.reverse then
		local pillar = Effects.pillar(folder, CFrame.new(pos), 90, 4, Palette.Wheel)
		local pillarFade = VfxUtil.fader(pillar)
		pillarFade.set(0)
		VfxUtil.animate(0.5, function(a)
			pillarFade.set(a)
		end)
		VfxUtil.fade(pillar, 0.6, time - 0.4)
		local wheel = Mahoraga.buildWheel(folder, CFrame.new(pos + Vector3.new(0, 1, 0)), 1.5)
		wheel.WorldPivot = CFrame.new(pos + Vector3.new(0, 1, 0))
		VfxUtil.animate(time, function(a)
			local eased = 1 - (1 - a) ^ 2
			wheel:PivotTo(CFrame.new(pos + Vector3.new(0, 1 + 30 * eased, 0)) * CFrame.Angles(0, a * math.pi * 3, 0))
		end, function()
			VfxUtil.fade(wheel, 0.4)
		end)
		VfxUtil.kanji(pos + Vector3.new(0, 12, 0), "布瑠部由良由良", 3.6, Palette.Wheel, time, 0.1)
		if near(pos, 250) then
			CameraFX.shake(0.5, time)
		end
	end
	task.delay(time, function()
		smoke.Enabled = false
		clearRing(edge)
		VfxUtil.fade(pool, 0.8)
	end)
	VfxUtil.sound("Summon", pos)
end

-- Exorcised: the body bleaches to white and dissolves; the wheel shatters.
handlers.BossDeath = function(d)
	local model = d.boss
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local folder = VfxUtil.folder()
	local wheelCore = model:FindFirstChild("WheelCore")
	if wheelCore and wheelCore:IsA("BasePart") then
		local shards = Mahoraga.buildWheel(folder, wheelCore.CFrame, 1)
		for _, p in model:GetDescendants() do
			if p:IsA("BasePart") and (p.Name == "Rim" or p.Name == "InnerRim" or p.Name == "Spoke" or p.Name == "Handle" or p.Name == "Knob" or p.Name == "Hub") then
				p.Transparency = 1
			end
		end
		task.delay(0.6, function()
			for _, shard in shards:GetChildren() do
				if shard:IsA("BasePart") then
					local out = Util.flatUnit(shard.Position - wheelCore.Position, Vector3.new(1, 0, 0))
					VfxUtil.tween(shard, 1.4, {
						CFrame = shard.CFrame + out * rng:NextNumber(6, 14) + Vector3.new(0, rng:NextNumber(-8, 6), 0),
						Transparency = 1,
					})
				end
			end
			Debris:AddItem(shards, 1.5)
		end)
	end
	for _, p in VfxUtil.parts(model) do
		if p.Transparency < 1 then
			task.delay(rng:NextNumber(0.4, 2.4), function()
				VfxUtil.tween(p, 1.2, { Color = WHITE })
				VfxUtil.tween(p, 1.4, { Transparency = 1 })
			end)
		end
	end
	local pos: Vector3 = d.pos
	local pillar = Effects.pillar(folder, CFrame.new(VfxUtil.ground(pos)), 120, 6, WHITE)
	VfxUtil.fade(pillar, 1.2, 2.5)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = workspace.Terrain
	PartKit.emitter(a, {
		Texture = PartKit.Textures.Sparkle,
		Color = ColorSequence.new(WHITE, Palette.Wheel),
		LightEmission = 1,
		Size = NumberSequence.new(0.8, 0),
		Lifetime = NumberRange.new(1.5, 2.5),
		Rate = 80,
		Speed = NumberRange.new(4, 10),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 10, 0),
	})
	Debris:AddItem(a, 4)
	if near(pos, 300) then
		HUD.flash(WHITE, 1.2, 0.6)
		CameraFX.shake(1.2, 1)
	end
end

-- Spinning ring over a stunned target's head.
function BossVFX.stunRing(model: any, duration: number)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local head = model:FindFirstChild("Head")
	local anchorPart = if head and head:IsA("BasePart") then head else model.PrimaryPart
	if not anchorPart then
		return
	end
	local big = anchorPart.Size.Magnitude > 4
	local radius = if big then 3.5 else 1.3
	local lift = if big then 3.5 else 1.8
	local folder = VfxUtil.folder()
	local ringModel = PartKit.model("StunRing", folder)
	PartKit.ring(ringModel, CFrame.new(), radius, 0.16, 0.12, 18, { Color = Palette.SpeechRing, Material = NEON })
	for k = 0, 2 do
		PartKit.ball(ringModel, CFrame.Angles(0, k * math.pi * 2 / 3, 0) * CFrame.new(0, 0, -radius), 0.35 * (if big then 2 else 1), { Color = WHITE, Material = NEON }, "Star")
	end
	ringModel.WorldPivot = CFrame.new()
	VfxUtil.animate(duration, function(a)
		if not anchorPart.Parent then
			return false
		end
		ringModel:PivotTo(CFrame.new(anchorPart.Position + Vector3.new(0, lift, 0)) * CFrame.Angles(0, a * duration * 6, 0))
		return true
	end, function()
		ringModel:Destroy()
	end)
end

return BossVFX
