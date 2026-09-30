--!strict
--[[
	Rika's full manifestation, drawn locally on every client: she floats behind
	Yuta, sways, claws at enemies on her own and wraps around him while he
	charges Pure Love. Driven by the character's JJK_RikaFull attribute.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Rika = require(Shared:WaitForChild("Assets"):WaitForChild("Rika"))
local VfxUtil = require(script.Parent.VfxUtil)

local RikaFollower = {}

local SCALE = 0.85
local OFFSET = CFrame.new(0, 6.5, 6.5) -- behind and above Yuta's root

type Follower = {
	Model: Model,
	Body: Model,
	Left: Model,
	Right: Model,
	CF: CFrame,
	Fader: VfxUtil.Fader,
	Visible: number,
	Leaving: boolean,
	Action: string?,
	ActionStart: number,
	ActionTime: number,
	Target: Vector3?,
}

local followers: { [Model]: Follower } = {}

local function spawnFor(char: Model)
	local existing = followers[char]
	if existing then
		if not existing.Leaving then
			return
		end
		existing.Model:Destroy()
		followers[char] = nil
	end
	local root = VfxUtil.root(char)
	if not root then
		return
	end
	local start = root.CFrame * OFFSET * CFrame.new(0, -12, 2)
	local model = Rika.build(VfxUtil.folder(), start, SCALE)
	local fader = VfxUtil.fader(model)
	fader.set(0)
	followers[char] = {
		Model = model,
		Body = model:FindFirstChild("Body") :: Model,
		Left = model:FindFirstChild("LeftArm") :: Model,
		Right = model:FindFirstChild("RightArm") :: Model,
		CF = start,
		Fader = fader,
		Visible = 0,
		Leaving = false,
		Action = nil,
		ActionStart = 0,
		ActionTime = 0,
		Target = nil,
	}
end

function RikaFollower.get(char: Model): Model?
	local f = followers[char]
	return if f then f.Model else nil
end

function RikaFollower.claw(char: Model, target: Vector3)
	local f = followers[char]
	if f then
		f.Action = "claw"
		f.ActionStart = os.clock()
		f.ActionTime = 0.6
		f.Target = target
	end
end

function RikaFollower.charge(char: Model, time: number)
	local f = followers[char]
	if f then
		f.Action = "charge"
		f.ActionStart = os.clock()
		f.ActionTime = time + 1.3
		f.Target = nil
	end
end

local function idleArm(now: number, side: number): CFrame
	return CFrame.Angles(math.rad(10 + math.sin(now * 1.3 + side) * 8), 0, math.rad(side * (12 + math.sin(now * 1.7) * 5)))
end

local function update(dt: number)
	local now = os.clock()
	for char, f in followers do
		local root = VfxUtil.root(char)
		if not root or not char.Parent or char:GetAttribute("JJK_RikaFull") ~= true then
			f.Leaving = true
		end
		local goalVisible = if f.Leaving then 0 else 1
		f.Visible += (goalVisible - f.Visible) * math.min(1, dt * (if f.Leaving then 5 else 3))
		if f.Leaving and f.Visible < 0.03 then
			f.Model:Destroy()
			followers[char] = nil
			continue
		end
		f.Fader.set(f.Visible)
		if not root then
			continue
		end

		local action = f.Action
		if action and now - f.ActionStart > f.ActionTime then
			f.Action = nil
			action = nil
		end
		local goal = root.CFrame * OFFSET * CFrame.new(0, math.sin(now * 1.8) * 0.5, 0)
		if action == "charge" then
			goal = root.CFrame * CFrame.new(0, 4.6, 3.4)
		elseif action == "claw" and f.Target then
			local pos = goal.Position
			local target = f.Target :: Vector3
			local flat = Vector3.new(target.X, pos.Y, target.Z)
			if (flat - pos).Magnitude > 1 then
				goal = CFrame.lookAt(pos, flat) * CFrame.new(0, 0, -1.5)
			end
		end
		f.CF = f.CF:Lerp(goal, 1 - math.exp(-dt * 7))
		f.Body:PivotTo(f.CF)

		local left = idleArm(now, -1)
		local right = idleArm(now, 1)
		if action == "claw" then
			local a = (now - f.ActionStart) / 0.6
			local pitch = if a < 0.35 then 10 + a / 0.35 * 140 elseif a < 0.55 then 150 - (a - 0.35) / 0.2 * 120 else 30
			right = CFrame.Angles(math.rad(pitch), 0, math.rad(18))
		elseif action == "charge" then
			left = CFrame.Angles(math.rad(75), 0, math.rad(22))
			right = CFrame.Angles(math.rad(75), 0, math.rad(-22))
		end
		f.Left:PivotTo(f.CF * CFrame.new(Rika.Shoulders.Left * SCALE) * left)
		f.Right:PivotTo(f.CF * CFrame.new(Rika.Shoulders.Right * SCALE) * right)
	end
end

local function watch(char: Model)
	local function refresh()
		if char:GetAttribute("JJK_RikaFull") == true then
			spawnFor(char)
		end
	end
	char:GetAttributeChangedSignal("JJK_RikaFull"):Connect(refresh)
	refresh()
end

local function onPlayer(p: Player)
	p.CharacterAdded:Connect(watch)
	if p.Character then
		watch(p.Character)
	end
end

function RikaFollower.start()
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	RunService.RenderStepped:Connect(update)
end

return RikaFollower
