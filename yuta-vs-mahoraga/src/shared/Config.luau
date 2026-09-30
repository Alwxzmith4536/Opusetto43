--!strict
--[[
	Yuta Okkotsu vs Mahoraga: every tunable number lives here.

	Canon notes:
	  * Rika's full manifestation and the copied Kenjaku technique (moving into
	    Gojo's body) are both limited to 5 minutes in the manga. Durations here are
	    shorter so the fight stays fast; set them to 300 for manga-accurate timers.
	  * Mahoraga adapts to anything that hits it. Each wheel turn is one step of
	    adaptation; four turns means it is fully adapted (immune) to that technique.
]]

local Config = {}

Config.World = {
	BuildArena = true, -- build the shrine arena, altar and spawn at runtime (turn off to use your own map)
	SetupLighting = true, -- sunset lighting + bloom so the neon effects glow
	ArenaCenter = Vector3.new(0, 0, 0), -- top surface of the arena floor
	ArenaSize = 520,
	SpawnDummies = true, -- cursed-spirit training dummies to test moves on
	DummyCount = 3,
	-- Used when BuildArena is false: where the altar and boss go.
	AltarPosition = Vector3.new(0, 0, -150),
	BossSpawnPosition = Vector3.new(0, 0, -60),
}

Config.Rules = {
	PvP = false, -- true lets players damage each other with the kit
	AutoSummonDelay = 25, -- seconds after the first player spawns; 0 disables auto-summon
}

Config.Player = {
	MaxHealth = 300,
	WalkSpeed = 20,
	BlockWalkSpeed = 9,
	CastWalkSpeed = 5,
	JumpPower = 50,
	JumpHeight = 7.2,
	BlockReduction = 0.55, -- blocking removes 55% of blockable damage
	DashDistance = 32,
	DashTime = 0.22,
	DashIFrames = 0.28, -- dash gives a short dodge window
}

Config.Yuta = {
	RikaDamageBonus = 1.25, -- all damage x1.25 while Rika is fully manifested

	Katana = {
		Damage = { 10, 10, 12, 20 },
		Interval = 0.3,
		FinisherLag = 0.8,
		ComboReset = 1.2,
		Reach = 9,
	},
	Dash = { Cooldown = 2.2 },
	RikaStrike = { Cooldown = 7, Damage = 38, Windup = 0.42 },
	DontMove = { Cooldown = 12, Damage = 8, Radius = 34, Stun = 1.6, BossStun = 1.3, Backlash = 5 },
	BlastAway = { Cooldown = 10, Damage = 34, Range = 32, ConeDegrees = 80, Knockback = 90, Backlash = 7 },
	RCT = { Cooldown = 22, SelfHeal = 0.32, AllyHeal = 0.18, AllyRadius = 24, Duration = 2 },
	FullManifestation = {
		Cooldown = 45,
		Duration = 60, -- canon: 300
		ClawDamage = 22,
		ClawInterval = 2.2,
		ClawRange = 45,
		Protection = 0.25, -- Rika absorbs 25% of incoming damage
	},
	PureLove = { Cooldown = 25, Charge = 1.35, Length = 180, Width = 14, Ticks = 6, TickInterval = 0.18, TickDamage = 42 },
	Domain = {
		Cooldown = 75,
		CastTime = 1.6,
		Duration = 14,
		Radius = 62,
		TickInterval = 1.1,
		CooldownMultiplier = 0.6, -- copied techniques come back faster inside the domain
		SwordDamage = 24,
		SpeechDamage = 10,
		SpeechStun = 0.7,
		RikaDamage = 30,
	},
	SixEyes = {
		Cooldown = 110,
		CastTime = 1.4,
		Duration = 45, -- canon: 300
		InfinityReduction = 0.85, -- Infinity stops 85% of damage until Mahoraga adapts to it
		CooldownMultiplier = 0.7, -- Six Eyes efficiency
	},
	Blue = { Cooldown = 6, Range = 70, Radius = 16, Duration = 1.6, TickInterval = 0.2, TickDamage = 7, Pull = 38 },
	Red = { Cooldown = 8, Speed = 150, Range = 95, HitRadius = 5, BlastRadius = 15, Damage = 75, Knockback = 110 },
	HollowPurple = { Cooldown = 30, Charge = 1.6, Speed = 115, Range = 230, Radius = 9, Damage = 300 },
}

Config.Boss = {
	Title = "Eight-Handled Sword Divergent Sila Divine General",
	Name = "Mahoraga",
	Kanji = "八握剣異戒神将魔虚羅",
	BaseHealth = 7500,
	HealthPerExtraPlayer = 4000,
	WalkSpeed = 19,
	EnragedWalkSpeed = 25,
	RespawnCooldown = 12,
	SummonTime = 3.2,

	-- No instant kills: a single Mahoraga hit can never deal more than this share
	-- of a player's max health, and each hit grants a short immunity window.
	MaxHitFraction = 0.25,
	HitInvulnerability = 0.45,

	Damage = {
		Sweep = 80,
		Cleave = 95,
		Punch = 30,
		Stomp = 55,
		Leap = 70,
		Rush = 60,
		Ring = 35,
	},
	Cooldowns = {
		Sweep = 4,
		Punch = 3,
		Stomp = 6,
		Cleave = 5,
		Rush = 7,
		Leap = 8,
		Rings = 14,
	},
	AttackGap = { 0.7, 0.4, 0.3 }, -- pause between attacks per phase
	WindupScale = { 1, 0.85, 0.72 }, -- telegraph length multiplier per phase
	EnrageAt = 0.5, -- phase 2 below 50% health
	FinalPhaseAt = 0.2, -- phase 3 below 20% health
}

Config.Adaptation = {
	MaxLevel = 4, -- four turns of the wheel = fully adapted
	ResistPerLevel = 0.25, -- 25% less damage from that technique per turn
	HealPerTurn = 0.015, -- Mahoraga regenerates when it adapts
	CastsPerTurn = {
		Default = 3,
		Katana = 6,
		Domain = 4,
		Infinity = 2,
	},
	-- Short labels for the boss bar's adaptation chips.
	ShortNames = {
		Katana = "Katana",
		Rika = "Rika",
		CursedSpeech = "Cursed Speech",
		PureLove = "Pure Love",
		Domain = "Domain",
		Blue = "Blue",
		Red = "Red",
		HollowPurple = "Purple",
		Infinity = "Infinity",
	},
	DisplayNames = {
		Katana = "Katana",
		Rika = "Rika",
		CursedSpeech = "Cursed Speech",
		PureLove = "Pure Love Beam",
		Domain = "Authentic Mutual Love",
		Blue = "Lapse: Blue",
		Red = "Reversal: Red",
		HollowPurple = "Hollow Purple",
		Infinity = "Infinity",
	},
}

--[[
	Sounds. The three katana sounds ship with Roblox. For the big techniques paste
	any audio id you like from the Creator Store, e.g. "rbxassetid://1234567890".
	Empty strings are skipped.
]]
Config.Sounds = {
	Slash = { Id = "rbxasset://sounds/swordslash.wav", Volume = 0.6, Speed = 1.1 },
	Lunge = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 0.7, Speed = 1 },
	Unsheath = { Id = "rbxasset://sounds/unsheath.wav", Volume = 0.6, Speed = 1 },
	WheelTurn = { Id = "rbxasset://sounds/unsheath.wav", Volume = 1, Speed = 0.42 },
	BossSlash = { Id = "rbxasset://sounds/swordlunge.wav", Volume = 1, Speed = 0.55 },
	Impact = { Id = "", Volume = 1, Speed = 1 },
	Beam = { Id = "", Volume = 1, Speed = 1 },
	Speech = { Id = "", Volume = 1, Speed = 1 },
	Domain = { Id = "", Volume = 1, Speed = 1 },
	Blue = { Id = "", Volume = 1, Speed = 1 },
	Red = { Id = "", Volume = 1, Speed = 1 },
	Purple = { Id = "", Volume = 1, Speed = 1 },
	Summon = { Id = "", Volume = 1, Speed = 1 },
}

return Config
