-- Ten Shadows client: input, HUD (hotbar, boss bar, adaptation wheel readout, incantations)
-- and local playback of every visual effect the server broadcasts.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("TenShadows")
local Config = require(Shared.Config)
local VFX = require(Shared.VFX)
local remotes = ReplicatedStorage:WaitForChild("TenShadowsRemotes")
local AbilityRemote = remotes:WaitForChild("Ability")
local FXRemote = remotes:WaitForChild("FX")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

VFX.Init()

local KEY_LABEL = {
	One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9", Zero = "0",
	MouseButton1 = "M1",
}

local GOLD = Color3.fromRGB(255, 214, 120)
local INK = Color3.fromRGB(12, 11, 18)
local PAPER = Color3.fromRGB(238, 234, 226)
local MUTED = Color3.fromRGB(150, 144, 170)
local PURPLE = Color3.fromRGB(120, 70, 200)

---------------------------------------------------------------- UI helpers

local function new(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, r)
	return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, parent)
end

local function stroke(parent, color, thickness, transparency)
	return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, parent)
end

local function label(props, parent)
	local defaults = { BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextColor3 = PAPER, TextSize = 14 }
	for k, v in pairs(props) do
		defaults[k] = v
	end
	return new("TextLabel", defaults, parent)
end

local gui = new("ScreenGui", { Name = "TenShadowsUI", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
local uiScale = new("UIScale", { Scale = 1 }, gui)
local function rescale()
	local cam = workspace.CurrentCamera
	if cam then
		uiScale.Scale = math.clamp(cam.ViewportSize.X / 1100, 0.55, 1)
	end
end
local camera = workspace.CurrentCamera or workspace:GetPropertyChangedSignal("CurrentCamera"):Wait() and workspace.CurrentCamera
rescale()
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

---------------------------------------------------------------- hotbar

local unlocked = {}
local cooldownEnds = {}
local slots = {}

local hotbar = new("Frame", { Name = "Hotbar", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(0, 70), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, gui)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Bottom, SortOrder = Enum.SortOrder.LayoutOrder }, hotbar)

local function shortName(name)
	local map = {
		DivineDogs = "Dogs", Nue = "Nue", Toad = "Toad", GreatSerpent = "Serpent", MaxElephant = "Elephant",
		RabbitEscape = "Rabbits", RoundDeer = "Deer", PiercingOx = "Ox", TigerFuneral = "Tiger", Totality = "Totality",
		ShadowStep = "Shadow", ChimeraShadowGarden = "DOMAIN", Agito = "Agito", Ritual = "Ritual", TamedMahoraga = "Mahoraga",
	}
	return map[name] or name
end

for i, name in ipairs(Config.AbilityOrder) do
	local cfg = Config.Abilities[name]
	local isSpecial = name == "ChimeraShadowGarden" or name == "TamedMahoraga" or name == "Ritual"
	local slot = new("Frame", { Name = name, LayoutOrder = i, Size = UDim2.fromOffset(58, 64), BackgroundColor3 = INK, BackgroundTransparency = 0.15 }, hotbar)
	corner(slot, 8)
	local slotStroke = stroke(slot, isSpecial and GOLD or PURPLE, 1.5, 0.35)
	label({ Text = cfg.Kanji, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 6), Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = isSpecial and GOLD or PAPER }, slot)
	label({ Text = shortName(name), Size = UDim2.new(1, -4, 0, 14), Position = UDim2.fromOffset(2, 34), TextSize = 11, TextColor3 = MUTED, Font = Enum.Font.GothamMedium }, slot)
	local key = cfg.Key
	label({ Text = key == "G" and "hold G" or (KEY_LABEL[key] or key), Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 48), TextSize = 12, TextColor3 = GOLD }, slot)
	local shade = new("Frame", { Name = "Cooldown", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, ZIndex = 3 }, slot)
	corner(shade, 8)
	local cdText = label({ Text = "", Size = UDim2.fromScale(1, 1), TextSize = 20, Font = Enum.Font.GothamBlack, ZIndex = 4 }, slot)
	local lock = label({ Text = "LOCKED", Size = UDim2.fromScale(1, 1), TextSize = 11, BackgroundTransparency = 0.25, BackgroundColor3 = Color3.new(0, 0, 0), TextColor3 = Color3.fromRGB(255, 120, 120), ZIndex = 5, Visible = cfg.Locked == true }, slot)
	corner(lock, 8)
	slots[name] = { Frame = slot, Shade = shade, Text = cdText, Lock = lock, Stroke = slotStroke }
end

local function refreshLocks()
	for name, s in pairs(slots) do
		local cfg = Config.Abilities[name]
		s.Lock.Visible = cfg.Locked == true and not unlocked[name]
	end
end

local function pulseSlot(name)
	local s = slots[name]
	if s then
		s.Stroke.Transparency = 0
		s.Stroke.Thickness = 3
		TweenService:Create(s.Stroke, TweenInfo.new(0.5), { Transparency = 0.35, Thickness = 1.5 }):Play()
	end
end

---------------------------------------------------------------- health, boss bar, notices, incantations

local hp = new("Frame", { Name = "Health", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -92), Size = UDim2.fromOffset(360, 16), BackgroundColor3 = INK, BackgroundTransparency = 0.2 }, gui)
corner(hp, 8)
stroke(hp, Color3.new(1, 1, 1), 1, 0.8)
local hpFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(110, 220, 140) }, hp)
corner(hpFill, 8)
local hpText = label({ Size = UDim2.fromScale(1, 1), TextSize = 12, ZIndex = 2, Text = "" }, hp)

local boss = new("Frame", { Name = "Boss", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(640, 92), BackgroundTransparency = 1, Visible = false }, gui)
label({ Size = UDim2.new(1, 0, 0, 20), Text = Config.Boss.Name, TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = GOLD, TextStrokeTransparency = 0.4 }, boss)
local bossBar = new("Frame", { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 18), BackgroundColor3 = INK, BackgroundTransparency = 0.1 }, boss)
corner(bossBar, 4)
stroke(bossBar, GOLD, 1.5, 0.3)
local bossLag = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 120, 90) }, bossBar)
corner(bossLag, 4)
local bossFill = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(240, 230, 210) }, bossBar)
corner(bossFill, 4)
local bossHp = label({ Size = UDim2.fromScale(1, 1), TextSize = 12, ZIndex = 3, TextColor3 = INK, Text = "" }, bossBar)
local phaseTag = label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(80, 20), Text = "", TextSize = 13, TextColor3 = Color3.fromRGB(255, 110, 110), TextXAlignment = Enum.TextXAlignment.Right }, boss)
local adaptRow = new("Frame", { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, boss)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, Wraps = true }, adaptRow)

local notices = new("Frame", { Name = "Notices", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 150), Size = UDim2.fromOffset(700, 120), BackgroundTransparency = 1 }, gui)
new("UIListLayout", { Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, notices)
local noticeCount = 0

local function notice(text, color)
	noticeCount += 1
	local l = label({ LayoutOrder = noticeCount, Size = UDim2.new(1, 0, 0, 22), Text = text, TextSize = 16, TextColor3 = color or PAPER, TextStrokeTransparency = 0.3, TextWrapped = true }, notices)
	local items = {}
	for _, c in ipairs(notices:GetChildren()) do
		if c:IsA("TextLabel") then
			table.insert(items, c)
		end
	end
	if #items > 4 then
		table.sort(items, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		items[1]:Destroy()
	end
	task.delay(5, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			task.wait(0.6)
			l:Destroy()
		end
	end)
end

local incant = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(900, 130), BackgroundTransparency = 1 }, gui)
local incantKanji = label({ Size = UDim2.new(1, 0, 0, 80), Text = "", Font = Enum.Font.GothamBlack, TextScaled = true, TextColor3 = PAPER, TextStrokeTransparency = 0.2, TextTransparency = 1, TextStrokeColor3 = Color3.fromRGB(40, 20, 70) }, incant)
local incantTitle = label({ Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 30), Text = "", TextSize = 26, Font = Enum.Font.GothamBlack, TextColor3 = GOLD, TextStrokeTransparency = 0.3, TextTransparency = 1 }, incant)
local incantToken = 0

local function showIncantation(title, sub, color)
	incantToken += 1
	local token = incantToken
	incantKanji.Text = sub or ""
	incantTitle.Text = string.upper(title or "")
	incantKanji.TextColor3 = color or PAPER
	incantKanji.TextTransparency = 0
	incantTitle.TextTransparency = 0
	incantKanji.TextStrokeTransparency = 0.2
	incantTitle.TextStrokeTransparency = 0.3
	incant.Position = UDim2.fromScale(0.5, 0.38)
	TweenService:Create(incant, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.36) }):Play()
	task.delay(1.3, function()
		if token == incantToken then
			local info = TweenInfo.new(0.5)
			TweenService:Create(incantKanji, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
			TweenService:Create(incantTitle, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local chantBar = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(300, 10), BackgroundColor3 = INK, Visible = false }, gui)
corner(chantBar, 5)
stroke(chantBar, PURPLE, 1.5)
local chantFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(190, 150, 255) }, chantBar)
corner(chantFill, 5)

local help = label({
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -120), Size = UDim2.fromOffset(300, 150),
	TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, TextSize = 13, TextColor3 = MUTED,
	Font = Enum.Font.GothamMedium, TextWrapped = true, RichText = true,
	Text = "<b>TEN SHADOWS</b>\nM1  Shadow Blade combo\n1-9  Shikigami   0  Totality\nQ  Shadow Travel   F  Guard (hold)\nR  Domain: Chimera Shadow Garden\nT  Agito   H  Tamed Mahoraga\n<b>hold G</b>  Furube Yura Yura — summon Mahoraga",
}, gui)
task.delay(20, function()
	TweenService:Create(help, TweenInfo.new(1), { TextTransparency = 1 }):Play()
end)

---------------------------------------------------------------- boss bar updates

local lastAdapt = nil
local function rebuildAdaptRow(str)
	for _, c in ipairs(adaptRow:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	if str == "" then
		return
	end
	for entry in string.gmatch(str, "[^,]+") do
		local damageType, turns, adapted = string.match(entry, "(%w+):(%d+):(%d)")
		if damageType then
			local info = Config.DamageTypes[damageType] or { Label = damageType, Color = PAPER }
			local isAdapted = adapted == "1"
			local chip = new("Frame", { Size = UDim2.fromOffset(104, 34), BackgroundColor3 = isAdapted and Color3.fromRGB(70, 56, 20) or INK, BackgroundTransparency = 0.15 }, adaptRow)
			corner(chip, 6)
			stroke(chip, isAdapted and GOLD or info.Color, 1, isAdapted and 0 or 0.4)
			label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 2), Text = info.Label, TextSize = 12, TextColor3 = info.Color }, chip)
			local pips = ""
			for i = 1, Config.Boss.TurnsToAdapt do
				pips ..= (i <= tonumber(turns) and "◆" or "◇")
			end
			label({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 18), Text = isAdapted and "ADAPTED" or pips, TextSize = isAdapted and 11 or 12, TextColor3 = isAdapted and GOLD or MUTED, Font = Enum.Font.GothamBlack }, chip)
		end
	end
end

local shownHealth = 1
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	-- player health
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		local f = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
		hpFill.Size = UDim2.fromScale(f, 1)
		hpFill.BackgroundColor3 = f > 0.35 and Color3.fromRGB(110, 220, 140) or Color3.fromRGB(240, 90, 90)
		hpText.Text = string.format("%d / %d%s", math.floor(hum.Health + 0.5), hum.MaxHealth, char:GetAttribute("Blocking") and "   GUARD" or "")
	end

	-- cooldowns
	local now = time()
	for name, s in pairs(slots) do
		local ends = cooldownEnds[name]
		if ends and ends.Finish > now then
			local left = ends.Finish - now
			s.Shade.Size = UDim2.fromScale(1, left / ends.Total)
			s.Text.Text = left >= 10 and tostring(math.floor(left)) or string.format("%.1f", left)
		elseif ends then
			cooldownEnds[name] = nil
			s.Shade.Size = UDim2.fromScale(1, 0)
			s.Text.Text = ""
			pulseSlot(name)
		end
	end

	-- boss (throttled)
	accum += dt
	if accum < 0.05 then
		return
	end
	accum = 0
	local model = workspace:FindFirstChild("Mahoraga")
	local bhum = model and model:GetAttribute("IsBoss") and model:FindFirstChildOfClass("Humanoid")
	if bhum and bhum.Health > 0 then
		boss.Visible = true
		local f = math.clamp(bhum.Health / bhum.MaxHealth, 0, 1)
		bossFill.Size = UDim2.fromScale(f, 1)
		shownHealth += (f - shownHealth) * 0.08
		bossLag.Size = UDim2.fromScale(math.max(f, shownHealth), 1)
		bossHp.Text = string.format("%d / %d", math.floor(bhum.Health), bhum.MaxHealth)
		phaseTag.Text = model:GetAttribute("Phase") == 2 and "PHASE 2" or ""
		local adapt = model:GetAttribute("Adaptations") or ""
		if adapt ~= lastAdapt then
			lastAdapt = adapt
			rebuildAdaptRow(adapt)
		end
	else
		boss.Visible = false
		shownHealth = 1
		lastAdapt = nil
	end
end)

---------------------------------------------------------------- input

local keyToAbility = {}
for name, cfg in pairs(Config.Abilities) do
	keyToAbility[cfg.Key] = name
end

local function fire(name, extra)
	local aim = mouse.Hit and mouse.Hit.Position or Vector3.zero
	AbilityRemote:FireServer(name, aim, extra)
end

local chanting = false
local chantStarted = 0
local function stopChant(completed)
	if not chanting then
		return
	end
	chanting = false
	chantBar.Visible = false
	if not completed then
		fire("RitualCancel")
	end
end

RunService.RenderStepped:Connect(function()
	if chanting then
		local hold = Config.Abilities.Ritual.HoldSeconds
		local a = math.clamp((time() - chantStarted) / hold, 0, 1)
		chantFill.Size = UDim2.fromScale(a, 1)
		if a >= 1 then
			fire("Ritual")
			stopChant(true)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		fire("ShadowBlade")
		return
	end
	local name = keyToAbility[input.KeyCode.Name]
	if not name then
		return
	end
	if name == "Block" then
		fire("Block", true)
	elseif name == "Ritual" then
		if not chanting and not (cooldownEnds.Ritual and cooldownEnds.Ritual.Finish > time()) then
			chanting = true
			chantStarted = time()
			chantFill.Size = UDim2.fromScale(0, 1)
			chantBar.Visible = true
			fire("RitualStart")
		end
	else
		fire(name)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	local name = keyToAbility[input.KeyCode.Name]
	if name == "Block" then
		fire("Block", false)
	elseif name == "Ritual" then
		stopChant(false)
	end
end)

---------------------------------------------------------------- server events

local UI = {}

function UI.UI_Cooldown(p)
	cooldownEnds[p.Ability] = { Finish = time() + p.Duration, Total = p.Duration }
	local s = slots[p.Ability]
	if s then
		s.Shade.Size = UDim2.fromScale(1, 1)
	end
end

function UI.UI_Notice(p)
	notice(p.Text, p.Color)
end

function UI.UI_Incantation(p)
	showIncantation(p.Title, p.Sub, p.Color)
end

function UI.UI_Unlock(p)
	unlocked[p.Ability] = true
	refreshLocks()
	pulseSlot(p.Ability)
	local cfg = Config.Abilities[p.Ability]
	if cfg then
		showIncantation("Unlocked: " .. cfg.Name, cfg.Kanji, GOLD)
	end
end

function UI.UI_State(p)
	unlocked = p.Unlocked or {}
	refreshLocks()
end

function UI.Knockback(p)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum then
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = p.Velocity
		VFX.Shake(0.6, 0.25)
	end
end

FXRemote.OnClientEvent:Connect(function(name, params)
	local effect = VFX.Effects[name]
	if effect then
		task.spawn(effect, params or {})
	elseif UI[name] then
		UI[name](params or {})
	end
end)

AbilityRemote:FireServer("RequestState")
refreshLocks()
