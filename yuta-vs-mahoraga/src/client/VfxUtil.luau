--!strict
-- Shared helpers for client effects: local folder, tweens, per-frame animations,
-- fades, expanding rings, particles, sounds and floating kanji.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Config = require(Shared:WaitForChild("Config"))
local Assets = Shared:WaitForChild("Assets")
local PartKit = require(Assets:WaitForChild("PartKit"))

local VfxUtil = {}

VfxUtil.rng = Random.new()

-- Local-only folder for effects (never replicated).
function VfxUtil.folder(): Folder
	local existing = workspace:FindFirstChild("JJK_FX")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "JJK_FX"
	folder.Parent = workspace
	return folder
end

function VfxUtil.tween(inst: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

-- Calls step(alpha) every frame for `duration` seconds, alpha going 0 -> 1.
-- Returning false from step ends the animation early. `done` always runs once.
function VfxUtil.animate(duration: number, step: (number) -> ...any, done: (() -> ())?)
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = if duration <= 0 then 1 else math.clamp((os.clock() - start) / duration, 0, 1)
		local ok, keep = pcall(step, a)
		if not ok then
			warn("[JJK FX] animation error: " .. tostring(keep))
		end
		if not ok or keep == false or a >= 1 then
			conn:Disconnect()
			if done then
				done()
			end
		end
	end)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude

-- Ground point below `pos`, ignoring characters, bosses, dummies and effects.
function VfxUtil.ground(pos: Vector3): Vector3
	local ignore: { Instance } = { VfxUtil.folder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	for _, m in CollectionService:GetTagged("JJK_Mahoraga") do
		table.insert(ignore, m)
	end
	local dummies = workspace:FindFirstChild("JJK_Dummies")
	if dummies then
		table.insert(ignore, dummies)
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -80, 0), groundParams)
	return if hit then hit.Position else pos - Vector3.new(0, 3, 0)
end

function VfxUtil.parts(inst: Instance): { BasePart }
	local list = {}
	if inst:IsA("BasePart") then
		table.insert(list, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- Fades every part, light, emitter and label under `inst`, then destroys it.
function VfxUtil.fade(inst: Instance, time: number, delay: number?)
	local function run()
		for _, p in VfxUtil.parts(inst) do
			VfxUtil.tween(p, time, { Transparency = 1 })
		end
		for _, d in inst:GetDescendants() do
			if d:IsA("PointLight") then
				VfxUtil.tween(d, time, { Brightness = 0 })
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
			elseif d:IsA("TextLabel") then
				VfxUtil.tween(d, time, { TextTransparency = 1, TextStrokeTransparency = 1 })
			end
		end
		Debris:AddItem(inst, time + 0.1)
	end
	if delay and delay > 0 then
		task.delay(delay, run)
	else
		run()
	end
end

-- Sets transparency on a group of parts, remembering each part's own base value.
export type Fader = { set: (number) -> () }
function VfxUtil.fader(inst: Instance): Fader
	local base: { [BasePart]: number } = {}
	for _, p in VfxUtil.parts(inst) do
		base[p] = p.Transparency
	end
	return {
		set = function(visibility: number)
			for p, t in base do
				p.Transparency = 1 - (1 - t) * visibility
			end
		end,
	}
end

-- A flat ring of segments that can be resized every frame (shockwaves).
export type LiveRing = { parts: { Part }, set: (radius: number, transparency: number?) -> () }
function VfxUtil.liveRing(parent: Instance, cf: CFrame, segments: number, height: number, thickness: number, color: Color3, material: Enum.Material?): LiveRing
	local parts: { Part } = {}
	for i = 1, segments do
		parts[i] = PartKit.part({
			Name = "Ring",
			Parent = parent,
			CFrame = cf,
			Size = Vector3.new(0.1, height, thickness),
			Color = color,
			Material = material or Enum.Material.Neon,
		})
	end
	return {
		parts = parts,
		set = function(radius: number, transparency: number?)
			local segLen = math.max(0.05, 2 * math.pi * radius / segments * 1.05)
			for i, p in parts do
				local a = (i - 0.5) / segments * math.pi * 2
				p.CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius)
				p.Size = Vector3.new(segLen, height, thickness)
				if transparency then
					p.Transparency = transparency
				end
			end
		end,
	}
end

-- One-shot particle burst at a world position.
function VfxUtil.burst(pos: Vector3, props: { [string]: any }, count: number)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = workspace.Terrain
	local emitter = PartKit.emitter(a, props)
	emitter.Enabled = false
	emitter:Emit(count)
	Debris:AddItem(a, emitter.Lifetime.Max + 0.5)
end

function VfxUtil.sound(name: string, at: (Instance | Vector3)?, volume: number?)
	local spec = (Config.Sounds :: any)[name]
	if not spec or spec.Id == "" then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = spec.Id
	sound.Volume = spec.Volume * (volume or 1)
	sound.PlaybackSpeed = spec.Speed
	sound.RollOffMinDistance = 15
	sound.RollOffMaxDistance = 450
	if typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		sound.Parent = a
		Debris:AddItem(a, 10)
	elseif typeof(at) == "Instance" then
		sound.Parent = at
		Debris:AddItem(sound, 10)
	else
		sound.Parent = SoundService
		Debris:AddItem(sound, 10)
	end
	sound:Play()
end

function VfxUtil.root(char: any): BasePart?
	if typeof(char) ~= "Instance" or not char:IsA("Model") then
		return nil
	end
	local r = char:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

function VfxUtil.head(char: any): BasePart?
	if typeof(char) ~= "Instance" or not char:IsA("Model") then
		return nil
	end
	local h = char:FindFirstChild("Head")
	return if h and h:IsA("BasePart") then h else nil
end

-- Big floating text (kanji call-outs). Pops in, shakes, fades.
function VfxUtil.kanji(pos: Vector3, text: string, size: number, color: Color3, life: number, shake: number?)
	local anchor = PartKit.part({ Name = "Kanji", Parent = VfxUtil.folder(), CFrame = CFrame.new(pos), Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
	local chars = utf8.len(text) or #text
	local width = size * math.max(1, chars) * 1.05
	local gui, label = PartKit.billboardText(anchor, text, width, size, color)
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	gui.Size = UDim2.new(width * 0.6, 0, size * 0.6, 0)
	VfxUtil.tween(gui, 0.18, { Size = UDim2.new(width, 0, size, 0) }, Enum.EasingStyle.Back)
	local amount = shake or 0
	if amount > 0 then
		VfxUtil.animate(life, function()
			gui.StudsOffset = Vector3.new(VfxUtil.rng:NextNumber(-1, 1), VfxUtil.rng:NextNumber(-1, 1), 0) * amount
		end)
	end
	VfxUtil.fade(anchor, 0.35, life)
end

return VfxUtil
