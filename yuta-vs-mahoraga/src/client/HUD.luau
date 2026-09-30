--!strict
--[[
	Heads-up display: hotbar with cooldowns (tap/click the slots on mobile),
	Yuta's health, technique timers, Mahoraga's boss bar with the adaptation
	wheel, announcements and toasts.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("JJKShared")
local Config = require(Shared:WaitForChild("Config"))
local Palette = require(Shared:WaitForChild("Palette"))
local Abilities = require(Shared:WaitForChild("Abilities"))
local Util = require(Shared:WaitForChild("Util"))

local player = Players.LocalPlayer

local HUD = {}

-- Set by Input: called with (abilityId, pressed) when a slot is clicked/tapped.
HUD.onSlot = nil :: ((string, boolean) -> ())?

type Cooldown = { ends: number, duration: number }
type Slot = {
	Frame: Frame,
	Stroke: UIStroke,
	Accent: Frame,
	Key: TextLabel,
	Kanji: TextLabel,
	Label: TextLabel,
	Shade: Frame,
	Timer: TextLabel,
	State: TextLabel,
	Id: string?,
	WasCooling: boolean,
}

local cooldowns: { [string]: Cooldown } = {}
local slots: { Slot } = {}
local currentMode = ""

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(16, 12, 24)
local MUTED = Color3.fromRGB(176, 166, 196)

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

local function corner(parent: Instance, px: number)
	new("UICorner", { CornerRadius = UDim.new(0, px), Parent = parent })
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = parent })
end

local function textStroke(parent: Instance, thickness: number)
	new("UIStroke", { Color = BLACK, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = parent })
end

local gui: ScreenGui
local elements: { [string]: any } = {}

-- Cooldowns -----------------------------------------------------------------------------

function HUD.setCooldown(id: string, ends: number, duration: number)
	cooldowns[id] = { ends = ends, duration = duration }
end

function HUD.cooldownRemaining(id: string): number
	local cd = cooldowns[id]
	if not cd then
		return 0
	end
	return math.max(0, cd.ends - workspace:GetServerTimeNow())
end

function HUD.reset()
	table.clear(cooldowns)
end

-- Hotbar -------------------------------------------------------------------------------

local function makeSlot(parent: Instance, index: number): Slot
	local frame = new("Frame", {
		Name = "Slot" .. index,
		LayoutOrder = index,
		Size = UDim2.fromOffset(68, 76),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.12,
		ClipsDescendants = true,
		Parent = parent,
	})
	corner(frame, 8)
	local slot: Slot = {
		Frame = frame,
		Stroke = stroke(frame, Palette.YutaEnergy, 1.5, 0.25),
		Accent = new("Frame", { Size = UDim2.new(1, 0, 0, 3), BorderSizePixel = 0, BackgroundColor3 = Palette.YutaEnergy, Parent = frame }),
		Kanji = new("TextLabel", {
			Size = UDim2.new(1, -8, 0, 32),
			Position = UDim2.fromOffset(4, 12),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextScaled = true,
			TextColor3 = WHITE,
			Text = "",
			Parent = frame,
		}),
		Key = new("TextLabel", {
			Size = UDim2.fromOffset(18, 16),
			Position = UDim2.fromOffset(4, 6),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.3,
			Font = Enum.Font.GothamBlack,
			TextSize = 12,
			TextColor3 = WHITE,
			Text = "",
			ZIndex = 2,
			Parent = frame,
		}),
		Label = new("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -3),
			Size = UDim2.new(1, -6, 0, 26),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 11,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			TextColor3 = WHITE,
			Text = "",
			Parent = frame,
		}),
		Shade = new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = BLACK,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = frame,
		}),
		Timer = new("TextLabel", {
			Size = UDim2.fromScale(1, 0.7),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextSize = 22,
			TextColor3 = WHITE,
			Text = "",
			ZIndex = 4,
			Parent = frame,
		}),
		State = new("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 6),
			Size = UDim2.fromOffset(44, 14),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextColor3 = WHITE,
			Text = "",
			ZIndex = 4,
			Parent = frame,
		}),
		Id = nil,
		WasCooling = false,
	}
	textStroke(slot.Timer, 1.5)
	local button = new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5, Parent = frame })
	button.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local id = slot.Id
			if id and HUD.onSlot then
				HUD.onSlot(id, true)
			end
		end
	end)
	button.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local id = slot.Id
			if id and HUD.onSlot then
				HUD.onSlot(id, false)
			end
		end
	end)
	return slot
end

local function applySlot(slot: Slot, id: string)
	local def = Abilities.Defs[id]
	slot.Id = id
	slot.Key.Text = def.KeyLabel
	slot.Label.Text = def.Short
	slot.Kanji.Text = def.Kanji or ""
	slot.Kanji.TextColor3 = def.Color
	slot.Accent.BackgroundColor3 = def.Color
	slot.Stroke.Color = def.Color
end

-- Announcements, toasts, flashes -----------------------------------------------------------

local announceSerial = 0
function HUD.announce(title: string, sub: string?, color: Color3?, time: number?)
	if not gui then
		return
	end
	announceSerial += 1
	local serial = announceSerial
	local holder = elements.Announce
	local titleLabel: TextLabel = holder.Title
	local subLabel: TextLabel = holder.Sub
	local line: Frame = holder.Line
	titleLabel.Text = title
	subLabel.Text = sub or ""
	titleLabel.TextColor3 = color or WHITE
	line.BackgroundColor3 = color or WHITE
	titleLabel.TextTransparency = 1
	subLabel.TextTransparency = 1
	line.BackgroundTransparency = 1
	titleLabel.Position = UDim2.new(0.5, 0, 0, 18)
	local info = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(titleLabel, info, { TextTransparency = 0, Position = UDim2.new(0.5, 0, 0, 0) }):Play()
	TweenService:Create(subLabel, info, { TextTransparency = 0 }):Play()
	TweenService:Create(line, info, { BackgroundTransparency = 0.2 }):Play()
	task.delay(time or 2.2, function()
		if serial ~= announceSerial then
			return
		end
		local out = TweenInfo.new(0.45)
		TweenService:Create(titleLabel, out, { TextTransparency = 1 }):Play()
		TweenService:Create(subLabel, out, { TextTransparency = 1 }):Play()
		TweenService:Create(line, out, { BackgroundTransparency = 1 }):Play()
	end)
end

local toastSerial = 0
function HUD.notify(text: string)
	if not gui then
		return
	end
	toastSerial += 1
	local serial = toastSerial
	local toast: TextLabel = elements.Toast
	toast.Text = text
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.3
	task.delay(2.6, function()
		if serial == toastSerial then
			TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end)
end

function HUD.flash(color: Color3, time: number, peak: number?)
	if not gui then
		return
	end
	local overlay: Frame = elements.Flash
	overlay.BackgroundColor3 = color
	overlay.BackgroundTransparency = 1 - (peak or 0.45)
	TweenService:Create(overlay, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
end

function HUD.toggleHelp()
	local help: Frame? = elements.Help
	if help then
		help.Visible = not help.Visible
	end
end

-- Build ------------------------------------------------------------------------------------

local function buildVitals(parent: Instance)
	local vitals = new("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 18, 1, -18),
		Size = UDim2.fromOffset(300, 70),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local name = new("TextLabel", {
		Size = UDim2.fromOffset(300, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = WHITE,
		Text = "YUTA OKKOTSU",
		Parent = vitals,
	})
	textStroke(name, 1.5)
	new("TextLabel", {
		Position = UDim2.fromOffset(0, 21),
		Size = UDim2.fromOffset(300, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = MUTED,
		Text = "SPECIAL GRADE SORCERER  -  COPY / RIKA",
		Parent = vitals,
	})
	local barBack = new("Frame", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.fromOffset(300, 14),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = vitals,
	})
	corner(barBack, 4)
	stroke(barBack, Palette.YutaEnergy, 1, 0.4)
	local ghost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.5, BorderSizePixel = 0, Parent = barBack })
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = barBack })
	new("UIGradient", { Color = ColorSequence.new(Palette.YutaEnergy, Palette.PureLove), Parent = fill })
	local hpText = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextColor3 = WHITE,
		Text = "",
		ZIndex = 3,
		Parent = barBack,
	})
	textStroke(hpText, 1)
	local status = new("TextLabel", {
		Position = UDim2.fromOffset(0, 56),
		Size = UDim2.fromOffset(300, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.SixEyes,
		Text = "",
		Parent = vitals,
	})
	elements.Vitals = { Fill = fill, Ghost = ghost, Text = hpText, Status = status, Shown = 1, GhostShown = 1 }
end

local function buildTimers(parent: Instance)
	local row = new("Frame", {
		Name = "Timers",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -104),
		Size = UDim2.fromOffset(520, 24),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), Parent = row })
	local function chip(color: Color3): TextLabel
		local label = new("TextLabel", {
			Size = UDim2.fromOffset(210, 24),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.15,
			Font = Enum.Font.GothamBlack,
			TextSize = 13,
			TextColor3 = color,
			Text = "",
			Visible = false,
			Parent = row,
		})
		corner(label, 6)
		stroke(label, color, 1.5, 0.2)
		return label
	end
	elements.RikaTimer = chip(Palette.RikaAura)
	elements.SixEyesTimer = chip(Palette.SixEyes)
end

local function buildWheelIcon(parent: Instance, size: number): Frame
	local icon = new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent })
	local ring = new("Frame", { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.15, 0.15), BackgroundTransparency = 1, Parent = icon })
	corner(ring, size)
	stroke(ring, Palette.Wheel, 2.5)
	for k = 0, 3 do
		new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, 2),
			Rotation = k * 45,
			BackgroundColor3 = Palette.Wheel,
			BorderSizePixel = 0,
			Parent = icon,
		})
	end
	return icon
end

local function buildBoss(parent: Instance)
	local boss = new("Frame", {
		Name = "Boss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(640, 118),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = parent,
	})
	local title = new("TextLabel", {
		Size = UDim2.fromOffset(640, 14),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Palette.Wheel,
		Text = string.upper(Config.Boss.Title),
		Parent = boss,
	})
	textStroke(title, 1)
	local name = new("TextLabel", {
		Position = UDim2.fromOffset(0, 12),
		Size = UDim2.fromOffset(640, 34),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 32,
		TextColor3 = WHITE,
		Text = string.upper(Config.Boss.Name),
		Parent = boss,
	})
	textStroke(name, 2)
	local kanji = new("TextLabel", {
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.fromOffset(200, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = MUTED,
		Text = Config.Boss.Kanji,
		Parent = boss,
	})
	textStroke(kanji, 1)
	local wheelHolder = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 12), Size = UDim2.fromOffset(110, 32), BackgroundTransparency = 1, Parent = boss })
	local wheel = buildWheelIcon(wheelHolder, 30)
	local turns = new("TextLabel", {
		Position = UDim2.fromOffset(34, 0),
		Size = UDim2.fromOffset(76, 32),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.Wheel,
		Text = "x0",
		Parent = wheelHolder,
	})
	textStroke(turns, 1.5)

	local barBack = new("Frame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.fromOffset(640, 18),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.05,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Parent = boss,
	})
	corner(barBack, 4)
	stroke(barBack, Palette.Wheel, 1.5, 0.2)
	local ghost = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BackgroundTransparency = 0.45, BorderSizePixel = 0, Parent = barBack })
	local fill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE, BorderSizePixel = 0, Parent = barBack })
	new("UIGradient", { Color = ColorSequence.new(Palette.Danger, Palette.Wheel), Parent = fill })
	for _, at in { Config.Boss.EnrageAt, Config.Boss.FinalPhaseAt } do
		new("Frame", { Position = UDim2.new(at, -1, 0, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = WHITE, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 3, Parent = barBack })
	end
	local hpText = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		TextColor3 = WHITE,
		Text = "",
		ZIndex = 4,
		Parent = barBack,
	})
	textStroke(hpText, 1.2)
	local chips = new("Frame", { Position = UDim2.fromOffset(0, 74), Size = UDim2.fromOffset(640, 44), BackgroundTransparency = 1, Parent = boss })
	new("UIGridLayout", {
		CellSize = UDim2.fromOffset(152, 20),
		CellPadding = UDim2.fromOffset(6, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = chips,
	})
	elements.Boss = {
		Frame = boss,
		Fill = fill,
		Ghost = ghost,
		Text = hpText,
		Turns = turns,
		Wheel = wheel,
		Chips = chips,
		Signature = "",
		Shown = 1,
		GhostShown = 1,
		WheelAngle = 0,
	}
end

local function buildHelp(parent: Instance)
	local lines = {
		"M1 (click)  Katana combo",
		"Q  Cursed Dash",
		"Z  Rika: Partial Manifestation",
		"X  Cursed Speech: Don't Move",
		"C  Cursed Speech: Blast Away",
		"V  Reverse Cursed Technique",
		"F  Rika: Full Manifestation",
		"R  Pure Love beam (needs F)",
		"T  Domain: Authentic Mutual Love",
		"G  Six Eyes (Z Blue, X Red, C Purple)",
		"E  Guard (hold)",
		"P  Summon Mahoraga at the altar",
		"H  Hide / show this panel",
	}
	local help = new("Frame", {
		Name = "Help",
		Position = UDim2.fromOffset(16, 64),
		Size = UDim2.fromOffset(268, 30 + #lines * 17),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.2,
		Parent = parent,
	})
	corner(help, 8)
	stroke(help, Palette.YutaEnergy, 1, 0.4)
	new("TextLabel", {
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Palette.YutaCore,
		Text = "CONTROLS",
		Parent = help,
	})
	for i, line in lines do
		new("TextLabel", {
			Position = UDim2.fromOffset(12, 10 + i * 17),
			Size = UDim2.new(1, -24, 0, 16),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = MUTED,
			Text = line,
			Parent = help,
		})
	end
	elements.Help = help
	task.delay(18, function()
		help.Visible = false
	end)
end

local function build()
	gui = new("ScreenGui", {
		Name = "JJK_HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 5,
	})
	local scale = new("UIScale", { Parent = gui })
	local camera = workspace.CurrentCamera
	local function rescale()
		local vp = camera.ViewportSize
		scale.Scale = math.clamp(math.min(vp.X / 1280, vp.Y / 720), 0.55, 1.2)
	end
	rescale()
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	local bar = new("Frame", {
		Name = "Hotbar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if UserInputService.TouchEnabled then -150 else -16),
		Size = UDim2.fromOffset(10 * 74, 76),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = bar,
	})
	for i = 1, #Abilities.Bars.Base do
		slots[i] = makeSlot(bar, i)
	end

	buildVitals(gui)
	buildTimers(gui)
	buildBoss(gui)
	buildHelp(gui)

	local announce = new("Frame", {
		Name = "Announce",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.24),
		Size = UDim2.fromOffset(900, 130),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local title = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 76),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		TextSize = 64,
		TextColor3 = WHITE,
		TextTransparency = 1,
		Text = "",
		Parent = announce,
	})
	textStroke(title, 3)
	local line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 82),
		Size = UDim2.fromOffset(420, 2),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Parent = announce,
	})
	local sub = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		TextColor3 = WHITE,
		TextTransparency = 1,
		Text = "",
		Parent = announce,
	})
	textStroke(sub, 1.5)
	elements.Announce = { Title = title, Sub = sub, Line = line }

	local toast = new("TextLabel", {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, if UserInputService.TouchEnabled then -268 else -136),
		Size = UDim2.fromOffset(560, 30),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = WHITE,
		TextTransparency = 1,
		Text = "",
		Parent = gui,
	})
	corner(toast, 6)
	elements.Toast = toast

	elements.Flash = new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
		Parent = gui,
	})

	gui.Parent = player:WaitForChild("PlayerGui")
end

-- Per-frame updates ------------------------------------------------------------------------

local function updateSlots(char: Model?)
	local mode = (char and char:GetAttribute("JJK_Mode") or "Base") :: string
	if mode ~= currentMode then
		currentMode = mode
		local bar = Abilities.Bars[mode] or Abilities.Bars.Base
		for i, id in bar do
			applySlot(slots[i], id)
		end
	end
	local now = workspace:GetServerTimeNow()
	local rikaFull = char ~= nil and char:GetAttribute("JJK_RikaFull") == true
	for _, slot in slots do
		local id = slot.Id
		if not id then
			continue
		end
		local cd = cooldowns[id]
		local remaining = if cd then math.max(0, cd.ends - now) else 0
		local fraction = if cd and cd.duration > 0 then remaining / cd.duration else 0
		slot.Shade.Size = UDim2.fromScale(1, fraction)
		slot.Timer.Text = if remaining <= 0 then "" elseif remaining >= 10 then tostring(math.ceil(remaining)) else string.format("%.1f", remaining)
		if slot.WasCooling and remaining <= 0 then
			slot.Stroke.Transparency = 0
			slot.Stroke.Thickness = 4
			TweenService:Create(slot.Stroke, TweenInfo.new(0.4), { Thickness = 1.5, Transparency = 0.25 }):Play()
		end
		slot.WasCooling = remaining > 0

		local state, active, locked = "", false, false
		if id == "FullManifestation" and rikaFull and char then
			active = true
			state = Util.formatTime(((char:GetAttribute("JJK_RikaEnds") or now) :: number) - now)
		elseif id == "SixEyes" and mode == "SixEyes" and char then
			active = true
			state = Util.formatTime(((char:GetAttribute("JJK_SixEyesEnds") or now) :: number) - now)
		elseif id == "PureLove" and not rikaFull then
			locked = true
			state = "NEED F"
		elseif id == "Block" then
			state = if char and char:GetAttribute("JJK_Blocking") then "GUARD" else "HOLD"
		end
		slot.State.Text = state
		slot.Kanji.TextTransparency = if locked then 0.75 else 0.1
		if active then
			slot.Stroke.Thickness = 3
			slot.Stroke.Transparency = 0
		end
	end
end

local function updateVitals(char: Model?, dt: number)
	local v = elements.Vitals
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local frac = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	v.Shown += (frac - v.Shown) * math.min(1, dt * 12)
	if frac < v.GhostShown then
		v.GhostShown = math.max(frac, v.GhostShown - dt * 0.35)
	else
		v.GhostShown = frac
	end
	v.Fill.Size = UDim2.fromScale(v.Shown, 1)
	v.Ghost.Size = UDim2.fromScale(v.GhostShown, 1)
	v.Text.Text = ("%d / %d"):format(math.ceil(humanoid.Health), humanoid.MaxHealth)
	local tags = {}
	if char and char:GetAttribute("JJK_RikaFull") then
		table.insert(tags, "RIKA")
	end
	if char and char:GetAttribute("JJK_Mode") == "SixEyes" then
		table.insert(tags, "INFINITY")
	end
	if char and char:GetAttribute("JJK_Stunned") then
		table.insert(tags, "STUNNED")
	end
	v.Status.Text = table.concat(tags, "  /  ")

	local now = workspace:GetServerTimeNow()
	local rika: TextLabel = elements.RikaTimer
	local rikaOn = char ~= nil and char:GetAttribute("JJK_RikaFull") == true
	rika.Visible = rikaOn
	if rikaOn and char then
		rika.Text = "RIKA: FULL MANIFESTATION  " .. Util.formatTime(((char:GetAttribute("JJK_RikaEnds") or now) :: number) - now)
	end
	local six: TextLabel = elements.SixEyesTimer
	local sixOn = char ~= nil and char:GetAttribute("JJK_Mode") == "SixEyes"
	six.Visible = sixOn
	if sixOn and char then
		six.Text = "SIX EYES / INFINITY  " .. Util.formatTime(((char:GetAttribute("JJK_SixEyesEnds") or now) :: number) - now)
	end
end

local function rebuildChips(b: any, model: Model)
	local entries = {}
	for name, value in model:GetAttributes() do
		local kind = string.match(name, "^JJK_Adapt_(.+)$")
		if kind and typeof(value) == "number" and value > 0 then
			table.insert(entries, { kind = kind, value = value })
		end
	end
	table.sort(entries, function(x, y)
		return x.value > y.value
	end)
	local parts = {}
	for _, e in entries do
		table.insert(parts, e.kind .. string.format("%.2f", e.value))
	end
	local signature = table.concat(parts, ",")
	if signature == b.Signature then
		return
	end
	b.Signature = signature
	for _, child in b.Chips:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local maxLevel = Config.Adaptation.MaxLevel
	for i, e in entries do
		if i > 8 then
			break
		end
		local level = math.floor(e.value)
		local full = level >= maxLevel
		local chip = new("Frame", { LayoutOrder = i, BackgroundColor3 = PANEL, BackgroundTransparency = 0.15, Parent = b.Chips })
		corner(chip, 5)
		stroke(chip, if full then Palette.Danger else Palette.Wheel, 1, 0.3)
		new("TextLabel", {
			Position = UDim2.fromOffset(6, 0),
			Size = UDim2.new(1, -60, 1, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			TextSize = 10,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextColor3 = if full then Palette.Danger else WHITE,
			Text = string.upper((Config.Adaptation.ShortNames :: any)[e.kind] or e.kind),
			Parent = chip,
		})
		for p = 1, maxLevel do
			local filled = p <= level
			local partial = p == level + 1 and e.value - level or 0
			local pip = new("Frame", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -6 - (maxLevel - p) * 12, 0.5, 0),
				Size = UDim2.fromOffset(9, 9),
				Rotation = 45,
				BackgroundColor3 = if filled then (if full then Palette.Danger else Palette.Wheel) else Color3.fromRGB(60, 52, 70),
				BorderSizePixel = 0,
				Parent = chip,
			})
			if partial > 0 then
				new("Frame", {
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 1),
					Size = UDim2.fromScale(1, partial),
					BackgroundColor3 = Palette.Wheel,
					BackgroundTransparency = 0.3,
					BorderSizePixel = 0,
					Parent = pip,
				})
			end
		end
	end
end

local function updateBoss(dt: number)
	local b = elements.Boss
	local model = CollectionService:GetTagged("JJK_Mahoraga")[1]
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not model or not humanoid or not model:IsA("Model") then
		b.Frame.Visible = false
		return
	end
	b.Frame.Visible = true
	local frac = if humanoid.MaxHealth > 0 then math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1) else 0
	b.Shown += (frac - b.Shown) * math.min(1, dt * 10)
	if frac < b.GhostShown then
		b.GhostShown = math.max(frac, b.GhostShown - dt * 0.25)
	else
		b.GhostShown = frac
	end
	b.Fill.Size = UDim2.fromScale(b.Shown, 1)
	b.Ghost.Size = UDim2.fromScale(b.GhostShown, 1)
	b.Text.Text = ("%d / %d"):format(math.ceil(humanoid.Health), humanoid.MaxHealth)
	local turns = (model:GetAttribute("JJK_WheelTurns") or 0) :: number
	b.Turns.Text = "x" .. turns
	b.WheelAngle += (turns * 45 - b.WheelAngle) * math.min(1, dt * 8)
	b.Wheel.Rotation = b.WheelAngle
	rebuildChips(b, model)
end

function HUD.start()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	build()
	RunService.RenderStepped:Connect(function(dt: number)
		local char = player.Character
		updateSlots(char)
		updateVitals(char, dt)
		updateBoss(dt)
	end)
end

return HUD
