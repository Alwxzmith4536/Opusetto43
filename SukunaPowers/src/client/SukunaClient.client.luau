--[[
	SukunaClient — input, HUD, aiming and the FX bridge.

	Controls (after clicking the red cube):
	  Left click  Combo (4 hits)          Z  Dismantle (解)
	  X           Cleave (捌)             C  Fuga (開)
	  V           Domain Expansion        G  World Cutting Slash
	Gamepad and touch are supported (tap the HUD buttons).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("SukunaShared")
local Config = require(Shared:WaitForChild("Config"))
local Effects = require(Shared:WaitForChild("Effects"))
local Cine = require(Shared:WaitForChild("Cinematics"))
local Sounds = require(Shared:WaitForChild("Sounds"))
local remote = Shared:WaitForChild("SukunaRemote") :: RemoteEvent

local C = Config.Colors

local cooldownEnd = {}
local cooldownTotal = {}

----------------------------------------------------------------------
-- Aiming
----------------------------------------------------------------------

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function aimPoint(): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	-- Mouse users aim with the cursor; touch / gamepad aim with the screen centre.
	local screen = camera.ViewportSize / 2
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		screen = UserInputService:GetMouseLocation()
	end
	local ray = camera:ViewportPointToRay(screen.X, screen.Y)
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, aimParams)
	return if hit then hit.Position else ray.Origin + ray.Direction * 400
end

local function refreshAimFilter()
	local list = {}
	if player.Character then
		table.insert(list, player.Character)
	end
	local fx = Workspace:FindFirstChild("SukunaFX_Local")
	if fx then
		table.insert(list, fx)
	end
	aimParams.FilterDescendantsInstances = list
end

----------------------------------------------------------------------
-- Casting
----------------------------------------------------------------------

local function powered(): boolean
	return player:GetAttribute("SukunaPowered") == true
end

local function cast(name: string)
	if not powered() or Cine.isPlaying() then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return
	end
	if (cooldownEnd[name] or 0) > os.clock() then
		return
	end
	refreshAimFilter()
	local aim = aimPoint()
	if aim then
		local flat = Vector3.new(aim.X - root.Position.X, 0, aim.Z - root.Position.Z)
		if flat.Magnitude > 1 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
		end
	end
	remote:FireServer("Ability", { name = name, aim = aim })
end

----------------------------------------------------------------------
-- HUD
----------------------------------------------------------------------

local order = {}
for name, ab in Config.Abilities do
	table.insert(order, { name = name, ab = ab })
end
table.sort(order, function(a, b)
	return a.ab.Order < b.ab.Order
end)

local slots = {}

local hud = Instance.new("ScreenGui")
hud.Name = "SukunaHUD"
hud.ResetOnSpawn = false
hud.Enabled = false
hud.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
hud.DisplayOrder = 5
hud.Parent = player:WaitForChild("PlayerGui")

local scale = Instance.new("UIScale")
scale.Parent = hud

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.AnchorPoint = Vector2.new(0.5, 1)
bar.Position = UDim2.new(0.5, 0, 1, -16)
bar.Size = UDim2.fromOffset(#order * 92, 112)
bar.BackgroundTransparency = 1
bar.Parent = hud

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = bar

local title = Instance.new("TextLabel")
title.Name = "Title"
title.AnchorPoint = Vector2.new(0.5, 1)
title.Position = UDim2.new(0.5, 0, 1, -134)
title.Size = UDim2.fromOffset(420, 30)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBlack
title.Text = "両面宿儺  ·  RYOMEN SUKUNA"
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 225, 225)
title.Parent = hud
local titleStroke = Instance.new("UIStroke")
titleStroke.Color = Color3.fromRGB(150, 0, 15)
titleStroke.Thickness = 2
titleStroke.Parent = title

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

for i, entry in order do
	local name, ab = entry.name, entry.ab
	local slot = Instance.new("TextButton")
	slot.Name = name
	slot.LayoutOrder = i
	slot.Size = UDim2.fromOffset(84, 84)
	slot.AutoButtonColor = false
	slot.Text = ""
	slot.BackgroundColor3 = Color3.fromRGB(22, 10, 13)
	slot.BackgroundTransparency = 0.1
	slot.Parent = bar
	corner(slot, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(190, 20, 35)
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = slot
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(120, 20, 30), Color3.fromRGB(20, 6, 8))
	gradient.Rotation = 90
	gradient.Parent = slot

	local kanji = Instance.new("TextLabel")
	kanji.BackgroundTransparency = 1
	kanji.AnchorPoint = Vector2.new(0.5, 0.5)
	kanji.Position = UDim2.fromScale(0.5, 0.45)
	kanji.Size = UDim2.fromScale(0.8, 0.5)
	kanji.Font = Enum.Font.GothamBlack
	kanji.Text = ab.Kanji
	kanji.TextScaled = true
	kanji.TextColor3 = Color3.fromRGB(255, 238, 238)
	kanji.ZIndex = 2
	kanji.Parent = slot
	local ks = Instance.new("UIStroke")
	ks.Color = Color3.fromRGB(120, 0, 10)
	ks.Thickness = 1.5
	ks.Parent = kanji

	local key = Instance.new("TextLabel")
	key.BackgroundColor3 = Color3.fromRGB(190, 20, 35)
	key.Position = UDim2.fromOffset(4, 4)
	key.Size = UDim2.fromOffset(28, 16)
	key.Font = Enum.Font.GothamBold
	key.Text = ab.KeyLabel or ""
	key.TextScaled = true
	key.TextColor3 = Color3.new(1, 1, 1)
	key.ZIndex = 3
	key.Parent = slot
	corner(key, 4)

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -3)
	label.Size = UDim2.new(1, -6, 0, 14)
	label.Font = Enum.Font.GothamBold
	label.Text = string.upper(ab.Name)
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 150, 155)
	label.ZIndex = 2
	label.Parent = slot

	local overlay = Instance.new("Frame")
	overlay.AnchorPoint = Vector2.new(0, 1)
	overlay.Position = UDim2.fromScale(0, 1)
	overlay.Size = UDim2.fromScale(1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.35
	overlay.ZIndex = 4
	overlay.Parent = slot
	corner(overlay, 12)

	local timer = Instance.new("TextLabel")
	timer.BackgroundTransparency = 1
	timer.Size = UDim2.fromScale(1, 1)
	timer.Font = Enum.Font.GothamBlack
	timer.Text = ""
	timer.TextSize = 26
	timer.TextColor3 = Color3.new(1, 1, 1)
	timer.ZIndex = 5
	timer.Parent = slot

	slot.Activated:Connect(function()
		cast(name)
	end)
	slot.MouseEnter:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(255, 80, 90), Thickness = 3 }):Play()
	end)
	slot.MouseLeave:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(190, 20, 35), Thickness = 2 }):Play()
	end)

	slots[name] = { overlay = overlay, timer = timer, stroke = stroke, ready = true }
end

-- Toast notifications
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 70)
toast.Size = UDim2.fromOffset(560, 34)
toast.BackgroundColor3 = Color3.fromRGB(20, 8, 10)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamBold
toast.TextScaled = true
toast.TextColor3 = Color3.fromRGB(255, 220, 220)
toast.TextTransparency = 1
toast.Text = ""
toast.Parent = (function()
	local g = Instance.new("ScreenGui")
	g.Name = "SukunaToast"
	g.ResetOnSpawn = false
	g.DisplayOrder = 30
	g.Parent = player:WaitForChild("PlayerGui")
	return g
end)()
corner(toast, 8)

local toastId = 0
local function notify(text: string, duration: number?)
	toastId += 1
	local my = toastId
	toast.Text = text
	TweenService:Create(toast, TweenInfo.new(0.2), { TextTransparency = 0, BackgroundTransparency = 0.25 }):Play()
	task.delay(duration or 3, function()
		if toastId == my then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end)
end

local function updateScale()
	local camera = Workspace.CurrentCamera
	if camera then
		scale.Scale = math.clamp(camera.ViewportSize.X / 1000, 0.55, 1)
	end
end
updateScale()
if Workspace.CurrentCamera then
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local function showHud()
	if hud.Enabled then
		return
	end
	-- wait for the transformation cut-scene to end
	while Cine.isPlaying() do
		task.wait(0.1)
	end
	hud.Enabled = true
	bar.Position = UDim2.new(0.5, 0, 1, 140)
	TweenService:Create(bar, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 1, -16),
	}):Play()
	notify("Z Dismantle · X Cleave · C Fuga · V Domain · G World Slash · Click: Combo", 6)
end

local function refreshPowered()
	if powered() then
		task.spawn(showHud)
	else
		hud.Enabled = false
	end
end
player:GetAttributeChangedSignal("SukunaPowered"):Connect(refreshPowered)
refreshPowered()

RunService.Heartbeat:Connect(function()
	if not hud.Enabled then
		return
	end
	local now = os.clock()
	for name, slot in slots do
		local remaining = (cooldownEnd[name] or 0) - now
		local total = cooldownTotal[name] or 1
		if remaining > 0 then
			slot.overlay.Size = UDim2.fromScale(1, math.clamp(remaining / total, 0, 1))
			slot.timer.Text = if remaining >= 10 then string.format("%d", math.ceil(remaining)) else string.format("%.1f", remaining)
			slot.ready = false
		else
			if not slot.ready then
				slot.ready = true
				slot.overlay.Size = UDim2.fromScale(1, 0)
				slot.timer.Text = ""
				if total >= 3 then
					slot.stroke.Color = Color3.fromRGB(255, 255, 255)
					TweenService:Create(slot.stroke, TweenInfo.new(0.4), { Color = Color3.fromRGB(190, 20, 35) }):Play()
				end
			end
		end
	end
end)

----------------------------------------------------------------------
-- Input
----------------------------------------------------------------------

local keyMap = {}
for name, ab in Config.Abilities do
	if ab.KeyCode then
		keyMap[ab.KeyCode] = name
	end
	if ab.Gamepad then
		keyMap[ab.Gamepad] = name
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not powered() then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		cast("Combo")
		return
	end
	local name = keyMap[input.KeyCode]
	if name then
		cast(name)
	end
end)

----------------------------------------------------------------------
-- Server → client
----------------------------------------------------------------------

remote.OnClientEvent:Connect(function(kind, a, b)
	if kind == "FX" then
		Effects.handle(a, b)
	elseif kind == "Cooldown" then
		if type(a) == "string" and type(b) == "number" then
			cooldownEnd[a] = os.clock() + b
			cooldownTotal[a] = b
		end
	elseif kind == "Knockback" then
		Effects.knockSelf(a, b)
	elseif kind == "Notify" then
		if type(a) == "string" then
			notify(a)
			Sounds.play("Ping")
		end
	end
end)

----------------------------------------------------------------------
-- The red cube: floating / spinning locally, glows when hovered
----------------------------------------------------------------------

task.spawn(function()
	local cube = Workspace:WaitForChild(Config.Cube.Name, 30)
	if not cube or not cube:IsA("BasePart") then
		return
	end
	local baseCF = cube.CFrame
	local light = cube:WaitForChild("PointLight", 10)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		cube.CFrame = baseCF
			* CFrame.new(0, math.sin(t * 1.7) * 0.4, 0)
			* CFrame.Angles(t * 0.6, t * 0.9, t * 0.35)
	end)
	local detector = cube:FindFirstChildOfClass("ClickDetector") or cube:WaitForChild("ClickDetector", 10)
	if detector and detector:IsA("ClickDetector") and light and light:IsA("PointLight") then
		detector.MouseHoverEnter:Connect(function()
			TweenService:Create(light, TweenInfo.new(0.25), { Brightness = 7, Range = 20 }):Play()
			TweenService:Create(cube, TweenInfo.new(0.25), { Color = Color3.fromRGB(255, 30, 40) }):Play()
		end)
		detector.MouseHoverLeave:Connect(function()
			TweenService:Create(light, TweenInfo.new(0.35), { Brightness = 3, Range = 14 }):Play()
			TweenService:Create(cube, TweenInfo.new(0.35), { Color = C.Curse }):Play()
		end)
	end
end)
