--[[
	Sukuna Powers — shared configuration.

	Everything that controls balance, timing, keys and sounds lives here so the
	server (damage / hitboxes) and the clients (animation / VFX / camera) always
	agree on the same timeline.
]]

local Config = {}

-- The red cube players click to receive the King of Curses' power.
Config.Cube = {
	Name = "SukunaCube",
	ClickDistance = 32,
}

-- Stats given to the player after the transformation.
Config.Stats = {
	MaxHealth = 300,
	WalkSpeed = 20,
}

Config.RequireR15 = true -- the procedural animations are built for R15 rigs
Config.KeepPowersOnRespawn = true
Config.DamagePlayers = true -- set false for PvE only (dummies / NPCs)
Config.Cinematics = true -- camera cut-scenes for the caster
Config.FaceMarkings = true
Config.BodyMarkings = true

-- Training dummies (R15) spawned in front of the cube so you can test moves.
Config.Dummies = {
	Enabled = true,
	Count = 3,
	Health = 400,
	RespawnTime = 4,
	Distance = 26, -- studs in front of the cube
}

--[[
	Abilities. Order = position on the HUD bar.
	KeyCode / Gamepad = input bindings. The Combo is bound to left click.
]]
Config.Abilities = {
	Combo = {
		Order = 1,
		Name = "Combo",
		Kanji = "拳",
		KeyLabel = "LMB",
		Gamepad = Enum.KeyCode.ButtonR2,
		Cooldown = 0.42,
		FinisherCooldown = 1.1,
		Damage = { 6, 6, 8, 13 },
		Range = 6,
	},
	Dismantle = {
		Order = 2,
		Name = "Dismantle",
		Kanji = "解",
		KeyCode = Enum.KeyCode.Z,
		KeyLabel = "Z",
		Gamepad = Enum.KeyCode.ButtonX,
		Cooldown = 4,
		Damage = 12,
		Speed = 150, -- studs / second
		Range = 90,
		Width = 11,
		Tilts = { -12, 22, -30 }, -- roll of each crescent (degrees)
	},
	Cleave = {
		Order = 3,
		Name = "Cleave",
		Kanji = "捌",
		KeyCode = Enum.KeyCode.X,
		KeyLabel = "X",
		Gamepad = Enum.KeyCode.ButtonY,
		Cooldown = 8,
		WhiffCooldown = 2.5,
		Range = 18,
		Cuts = 7,
		DamagePerCut = 4,
		PercentPerCut = 0.03, -- adapts to the target's toughness (max health)
	},
	Fuga = {
		Order = 4,
		Name = "Fuga",
		Kanji = "開",
		KeyCode = Enum.KeyCode.C,
		KeyLabel = "C",
		Gamepad = Enum.KeyCode.ButtonB,
		Cooldown = 18,
		Damage = 60,
		Radius = 26,
		Speed = 190,
		MaxRange = 320,
		BurnDamage = 3,
		BurnDuration = 4,
	},
	Domain = {
		Order = 5,
		Name = "Malevolent Shrine",
		Kanji = "領域",
		KeyCode = Enum.KeyCode.V,
		KeyLabel = "V",
		Gamepad = Enum.KeyCode.DPadUp,
		Cooldown = 45,
		Radius = 75,
		TickDamage = 3.5,
		TickRate = 0.25,
		SlowSpeed = 6,
	},
	WorldSlash = {
		Order = 6,
		Name = "World Cutting Slash",
		Kanji = "斬",
		KeyCode = Enum.KeyCode.G,
		KeyLabel = "G",
		Gamepad = Enum.KeyCode.DPadDown,
		Cooldown = 60,
		Damage = 80,
		Length = 320,
		Width = 9,
		Height = 140,
	},
}

-- Shared timeline (seconds from the moment the server starts the move).
Config.Timing = {
	Transform = { Duration = 4.0, Burst = 1.6 },
	Combo = { Hit = 0.12, Busy = 0.3 },
	Dismantle = { Duration = 0.85, SlashTimes = { 0.28, 0.44, 0.6 } },
	Cleave = { Duration = 1.15, Arrive = 0.2, CutStart = 0.28, CutInterval = 0.085 },
	Fuga = { Duration = 2.3, Release = 1.55 },
	Domain = { CasterLock = 4.4, Expand = 2.6, SlashStart = 3.3, SlashEnd = 9.3, Collapse = 10.4 },
	WorldSlash = { Duration = 3.6, Slash = 2.35 },
}

--[[
	Sounds. These use sounds that ship with every Roblox client (rbxasset://),
	so they work in any place without uploading anything. Swap any Id for your
	own "rbxassetid://123..." to make it sound even better.
]]
Config.Sounds = {
	Slash = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.8 },
	Swing = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.6 },
	Unsheath = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.7 },
	Whoosh = { Id = "rbxasset://sounds/Rocket whoosh 01.wav", Volume = 0.7 },
	Launch = { Id = "rbxasset://sounds/Rocket shot.wav", Volume = 0.9 },
	Impact = { Id = "rbxasset://sounds/collide.wav", Volume = 0.9 },
	Ping = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5 },
}

--[[
	Optional: if you upload your own R15 animations, paste their ids here
	(e.g. "rbxassetid://1234567890") and they will be used instead of the
	built-in procedural animation for that move. Leave "" to use the built-in.
]]
Config.CustomAnimations = {
	Transform = "",
	Combo1 = "",
	Combo2 = "",
	Combo3 = "",
	Combo4 = "",
	Dismantle = "",
	Cleave = "",
	Fuga = "",
	Domain = "",
	WorldSlash = "",
}

-- Palette used by every effect.
Config.Colors = {
	Curse = Color3.fromRGB(200, 12, 30),
	CurseDark = Color3.fromRGB(70, 0, 8),
	Blood = Color3.fromRGB(120, 0, 10),
	SlashCore = Color3.fromRGB(255, 245, 245),
	SlashGlow = Color3.fromRGB(255, 40, 60),
	Fire = Color3.fromRGB(255, 120, 20),
	FireHot = Color3.fromRGB(255, 220, 120),
	Black = Color3.fromRGB(8, 4, 6),
}

return Config
