--!strict
-- Keyboard + hotbar input. Aimed techniques send the cursor's world position;
-- the dash moves the character locally for instant response.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Config = require(Shared:WaitForChild("Config"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))

local HUD = require(script.Parent.HUD)

local player = Players.LocalPlayer
local remote = Net.event("Ability")

local Input = {}

local AIMED = {
	RikaStrike = true,
	BlastAway = true,
	PureLove = true,
	Blue = true,
	Red = true,
	HollowPurple = true,
}

local blocking = false
local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

local function character(): (Model?, BasePart?, Humanoid?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local root = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not (root and root:IsA("BasePart") and humanoid and humanoid.Health > 0) then
		return nil, nil, nil
	end
	return char, root, humanoid
end

local function mode(): string
	local char = player.Character
	return (char and char:GetAttribute("JJK_Mode") or "Base") :: string
end

-- World point under the cursor (screen centre on touch-only devices).
local function aimPosition(): Vector3
	local camera = workspace.CurrentCamera
	local screen = UserInputService:GetMouseLocation()
	if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
		screen = camera.ViewportSize / 2
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local ignore: { Instance } = {}
	if player.Character then
		table.insert(ignore, player.Character)
	end
	local fx = workspace:FindFirstChild("JJK_FX")
	if fx then
		table.insert(ignore, fx)
	end
	aimParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 800, aimParams)
	return if hit then hit.Position else ray.Origin + ray.Direction * 300
end

local function face(root: BasePart, aim: Vector3)
	local flat = Vector3.new(aim.X, root.Position.Y, aim.Z)
	if (flat - root.Position).Magnitude > 1 then
		root.CFrame = CFrame.lookAt(root.Position, flat)
	end
end

local function dash()
	local char, root, humanoid = character()
	if not (char and root and humanoid) or char:GetAttribute("JJK_Stunned") then
		return
	end
	if HUD.cooldownRemaining("Dash") > 0.05 then
		return
	end
	local cooldown = Config.Yuta.Dash.Cooldown
	HUD.setCooldown("Dash", workspace:GetServerTimeNow() + cooldown, cooldown)
	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.1 then
		dir = workspace.CurrentCamera.CFrame.LookVector
	end
	dir = Util.flatUnit(dir, root.CFrame.LookVector)
	local attachment = root:FindFirstChild("JJK_DashAttachment") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "JJK_DashAttachment"
		a.Parent = root
		attachment = a
	end
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "JJK_Dash"
	velocity.Attachment0 = attachment
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.MaxForce = 1e6
	velocity.VectorVelocity = dir * (Config.Player.DashDistance / Config.Player.DashTime)
	velocity.Parent = root
	Debris:AddItem(velocity, Config.Player.DashTime)
	remote:FireServer("Dash", { dir = dir })
end

local function setBlock(on: boolean)
	if blocking == on then
		return
	end
	blocking = on
	remote:FireServer("Block", { on = on })
end

function Input.use(id: string)
	if id == "Dash" then
		dash()
		return
	end
	if id == "Block" then
		return
	end
	local char, root = character()
	if not (char and root) or char:GetAttribute("JJK_Stunned") then
		return
	end
	if HUD.cooldownRemaining(id) > 0.05 then
		return
	end
	local aim = aimPosition()
	if AIMED[id] then
		face(root, aim)
	end
	remote:FireServer(id, { aim = aim })
end

function Input.start()
	HUD.onSlot = function(id: string, pressed: boolean)
		if id == "Block" then
			setBlock(pressed)
		elseif pressed then
			Input.use(id)
		end
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.H then
			HUD.toggleHelp()
			return
		end
		if key == Enum.KeyCode.E then
			setBlock(true)
			return
		end
		local def = Abilities.forKey(mode(), key)
		if def then
			Input.use(def.Id)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.E then
			setBlock(false)
		end
	end)
	player.CharacterAdded:Connect(function()
		blocking = false
	end)
end

return Input
