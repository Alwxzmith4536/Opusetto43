--[[
	Builds the real HUD (src/client/HUD.luau) headlessly with stubbed services,
	feeds it a mid-fight state, and writes the resulting ScreenGui tree to
	tools/preview/out/hud.json for hud.html to draw.

	Run from the yuta-vs-mahoraga folder:  lune run tools/preview/hud_export.luau
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Loader = require("./loader")
local roblox = Loader.roblox
local Instance = roblox.Instance
local Vector2 = roblox.Vector2

Loader.init("src")

local function signal()
	return {
		Connect = function()
			return { Disconnect = function() end }
		end,
		Wait = function() end,
	}
end

local NOW = 1000
local frame: ((number) -> ())? = nil
local playerGui = Instance.new("Folder")
playerGui.Name = "PlayerGui"

local char = Instance.new("Model")
char.Name = "Yuta"
local humanoid = Instance.new("Humanoid")
humanoid.MaxHealth = 300
humanoid.Health = 214
humanoid.Parent = char
char:SetAttribute("JJK_Mode", "Base")
char:SetAttribute("JJK_RikaFull", true)
char:SetAttribute("JJK_RikaEnds", NOW + 42)
char:SetAttribute("JJK_Blocking", false)

local boss = Instance.new("Model")
boss.Name = "Mahoraga"
local bossHumanoid = Instance.new("Humanoid")
bossHumanoid.MaxHealth = 11500
bossHumanoid.Health = 6120
bossHumanoid.Parent = boss
boss:SetAttribute("JJK_WheelTurns", 9)
boss:SetAttribute("JJK_Adapt_Katana", 2.5)
boss:SetAttribute("JJK_Adapt_CursedSpeech", 1.33)
boss:SetAttribute("JJK_Adapt_Rika", 0.67)
boss:SetAttribute("JJK_Adapt_Infinity", 4)
boss:SetAttribute("JJK_Adapt_Domain", 0.5)

local services = {
	CollectionService = {
		GetTagged = function()
			return { boss }
		end,
	},
	Players = {
		LocalPlayer = {
			Character = char,
			CharacterAdded = signal(),
			WaitForChild = function()
				return playerGui
			end,
		},
	},
	ReplicatedStorage = {
		WaitForChild = function()
			return Loader.folder("src/shared")
		end,
	},
	RunService = {
		RenderStepped = {
			Connect = function(_, fn)
				frame = fn
				return { Disconnect = function() end }
			end,
		},
	},
	StarterGui = { SetCoreGuiEnabled = function() end },
	TweenService = {
		Create = function(_, inst, _info, props)
			return {
				Play = function()
					for k, v in props do
						inst[k] = v
					end
				end,
			}
		end,
	},
	UserInputService = { TouchEnabled = false },
}
Loader.setGlobal("game", {
	GetService = function(_, name)
		return services[name]
	end,
})
Loader.setGlobal("workspace", {
	CurrentCamera = { ViewportSize = Vector2.new(1600, 900), GetPropertyChangedSignal = signal },
	GetServerTimeNow = function()
		return NOW
	end,
})
Loader.setGlobal("TweenInfo", {
	new = function()
		return {}
	end,
})
Loader.setGlobal("task", {
	delay = function() end,
	defer = function() end,
	spawn = function(f, ...)
		f(...)
	end,
	wait = function()
		return 0
	end,
})

-- Lune instances have no events, so HUD instances are wrapped: event members
-- (button.InputBegan etc.) return inert signals, everything else passes through
-- to the real instance (which still validates every property name).
local EVENTS = { InputBegan = true, InputEnded = true, Activated = true, MouseButton1Click = true }
local realOf = setmetatable({}, { __mode = "k" })
local function unwrap(v)
	return realOf[v] or v
end
local function wrap(inst)
	local proxy = {}
	realOf[proxy] = inst
	return setmetatable(proxy, {
		__index = function(_, key)
			if EVENTS[key] then
				return signal()
			end
			local v = inst[key]
			if type(v) == "function" then
				return function(_, ...)
					local args = table.pack(...)
					for i = 1, args.n do
						args[i] = unwrap(args[i])
					end
					return v(inst, table.unpack(args, 1, args.n))
				end
			end
			return v
		end,
		__newindex = function(_, key, v)
			inst[key] = unwrap(v)
		end,
	})
end
Loader.setGlobal("Instance", {
	new = function(className)
		return wrap(roblox.Instance.new(className))
	end,
})

local Palette = Loader.module("src/shared/Palette.luau")
local HUD = Loader.module("src/client/HUD.luau")
HUD.start()
HUD.setCooldown("RikaStrike", NOW + 2.1, 7)
HUD.setCooldown("DontMove", NOW + 7.4, 12)
HUD.setCooldown("RCT", NOW + 15, 22)
HUD.setCooldown("Domain", NOW + 51, 75)
HUD.setCooldown("SixEyes", NOW + 64, 110)
HUD.announce("真贋相愛", "Domain Expansion: Authentic Mutual Love", Palette.PureLove, 3)
HUD.notify("Mahoraga has fully adapted to Infinity. Switch techniques!")
assert(frame, "HUD did not bind RenderStepped")
frame(1)
frame(1)

local function udim2(u)
	return { u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset }
end
local function color(c)
	return { c.R, c.G, c.B }
end

local function node(inst): { [string]: any }
	local n: { [string]: any } = { class = inst.ClassName, name = inst.Name, children = {} }
	if inst:IsA("GuiObject") then
		n.pos = udim2(inst.Position)
		n.size = udim2(inst.Size)
		n.anchor = { inst.AnchorPoint.X, inst.AnchorPoint.Y }
		n.bg = color(inst.BackgroundColor3)
		n.bgT = inst.BackgroundTransparency
		n.visible = inst.Visible
		n.z = inst.ZIndex
		n.order = inst.LayoutOrder
		n.rotation = inst.Rotation
		n.clip = inst.ClipsDescendants
		if inst:IsA("TextLabel") or inst:IsA("TextButton") then
			n.text = inst.Text
			n.textColor = color(inst.TextColor3)
			n.textT = inst.TextTransparency
			n.textSize = inst.TextSize
			n.scaled = inst.TextScaled
			local ok, font = pcall(function()
				return inst.Font.Name
			end)
			n.font = if ok then font else "GothamBold"
			n.xAlign = inst.TextXAlignment.Name
			n.yAlign = inst.TextYAlignment.Name
			n.wrapped = inst.TextWrapped
		end
	elseif inst:IsA("UICorner") then
		n.radius = inst.CornerRadius.Offset
	elseif inst:IsA("UIStroke") then
		n.color = color(inst.Color)
		n.thickness = inst.Thickness
		n.t = inst.Transparency
		n.mode = inst.ApplyStrokeMode.Name
	elseif inst:IsA("UIGradient") then
		n.keys = {}
		for _, kp in inst.Color.Keypoints do
			table.insert(n.keys, { kp.Time, color(kp.Value) })
		end
	elseif inst:IsA("UIListLayout") then
		n.dir = inst.FillDirection.Name
		n.hAlign = inst.HorizontalAlignment.Name
		n.padding = inst.Padding.Offset
	elseif inst:IsA("UIGridLayout") then
		n.cell = udim2(inst.CellSize)
		n.cellPad = udim2(inst.CellPadding)
		n.hAlign = inst.HorizontalAlignment.Name
	elseif inst:IsA("UIScale") then
		n.scale = inst.Scale
	end
	for _, c in inst:GetChildren() do
		table.insert(n.children, node(c))
	end
	return n
end

local screen = playerGui:FindFirstChild("JJK_HUD")
assert(screen, "HUD ScreenGui missing")
fs.writeDir("tools/preview/out")
fs.writeFile("tools/preview/out/hud.json", serde.encode("json", node(screen)))
print("wrote tools/preview/out/hud.json")
