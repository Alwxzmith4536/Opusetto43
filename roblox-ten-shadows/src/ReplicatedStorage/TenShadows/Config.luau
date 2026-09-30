-- Ten Shadows Technique: every tunable number lives here (shared by server and client).

local Config = {}

Config.PvP = false -- player techniques hit other players when true

Config.Player = {
	MaxHealth = 250,
	WalkSpeed = 20,
	BlockWalkSpeed = 10,
	RespawnSeconds = 5,
	-- anti one-shot rules (see DamageRules.luau)
	MaxHitFraction = 0.2, -- one hit never removes more than 20% of max health
	LastStandThreshold = 0.35, -- above 35% health a single hit can never kill
	IFrameSeconds = 0.35, -- invulnerability after being hit
	BlockReduction = 0.6, -- holding F removes 60% of incoming damage
}

-- Damage types. Mahoraga adapts to each one separately.
Config.DamageTypes = {
	Slash = { Color = Color3.fromRGB(205, 190, 255), Label = "Slash" },
	Claw = { Color = Color3.fromRGB(240, 240, 240), Label = "Claw" },
	Lightning = { Color = Color3.fromRGB(140, 205, 255), Label = "Lightning" },
	Crush = { Color = Color3.fromRGB(150, 200, 120), Label = "Crush" },
	Bite = { Color = Color3.fromRGB(255, 206, 80), Label = "Bite" },
	Water = { Color = Color3.fromRGB(90, 180, 255), Label = "Water" },
	Pierce = { Color = Color3.fromRGB(255, 120, 80), Label = "Pierce" },
	Rend = { Color = Color3.fromRGB(190, 120, 255), Label = "Rend" },
	Shadow = { Color = Color3.fromRGB(120, 70, 200), Label = "Shadow" },
	Chimera = { Color = Color3.fromRGB(255, 226, 150), Label = "Chimera" },
	Extermination = { Color = Color3.fromRGB(255, 246, 222), Label = "Extermination" },
	Boss = { Color = Color3.fromRGB(255, 70, 70), Label = "Mahoraga" },
}

-- Order in this list = order on the hotbar.
Config.AbilityOrder = {
	"DivineDogs", "Nue", "Toad", "GreatSerpent", "MaxElephant", "RabbitEscape", "RoundDeer",
	"PiercingOx", "TigerFuneral", "Totality", "ShadowStep", "ChimeraShadowGarden", "Agito",
	"Ritual", "TamedMahoraga",
}

Config.Abilities = {
	ShadowBlade = {
		Key = "MouseButton1", Name = "Shadow Blade", Kanji = "影刀",
		Cooldown = 0.38, Damage = 45, FinisherDamage = 90, Range = 9, Angle = 110,
		DamageType = "Slash", ComboReset = 1.1,
	},
	DivineDogs = {
		Key = "One", Name = "Divine Dogs", Kanji = "玉犬",
		Cooldown = 5, Damage = 60, Bites = 2, Range = 60, GuardSeconds = 6, DamageType = "Claw",
	},
	Nue = {
		Key = "Two", Name = "Nue", Kanji = "鵺",
		Cooldown = 7, Damage = 220, Radius = 12, Range = 80, Stun = 0.6, DamageType = "Lightning",
	},
	Toad = {
		Key = "Three", Name = "Toad", Kanji = "蝦蟇",
		Cooldown = 8, Damage = 80, Range = 50, Stun = 1.2, DamageType = "Crush",
	},
	GreatSerpent = {
		Key = "Four", Name = "Great Serpent", Kanji = "大蛇",
		Cooldown = 10, Damage = 300, Radius = 8, Range = 70, Stun = 1.2, DamageType = "Bite",
	},
	MaxElephant = {
		Key = "Five", Name = "Max Elephant", Kanji = "満象",
		Cooldown = 14, Damage = 380, Range = 60, Angle = 70, Knockback = 90, DamageType = "Water",
	},
	RabbitEscape = {
		Key = "Six", Name = "Rabbit Escape", Kanji = "脱兎",
		Cooldown = 16, Duration = 5, Radius = 18,
	},
	RoundDeer = {
		Key = "Seven", Name = "Round Deer", Kanji = "円鹿",
		Cooldown = 22, HealFraction = 0.35, Duration = 3, DamageReduction = 0.3,
	},
	PiercingOx = {
		Key = "Eight", Name = "Piercing Ox", Kanji = "貫牛",
		Cooldown = 12, BaseDamage = 150, DamagePerStud = 6, MaxDistance = 90, Width = 7, Speed = 150,
		DamageType = "Pierce",
	},
	TigerFuneral = {
		Key = "Nine", Name = "Tiger Funeral", Kanji = "虎葬",
		Cooldown = 11, Damage = 120, Hits = 3, Range = 45, DamageType = "Rend",
	},
	Totality = {
		Key = "Zero", Name = "Divine Dog: Totality", Kanji = "玉犬・渾",
		Cooldown = 15, Damage = 110, Hits = 5, Range = 55, DamageType = "Claw",
		Locked = true, UnlockHint = "Unlocks when one of your Divine Dogs is destroyed",
	},
	ShadowStep = {
		Key = "Q", Name = "Shadow Travel", Kanji = "影移動",
		Cooldown = 4, Range = 45, IFrames = 0.45,
	},
	ChimeraShadowGarden = {
		Key = "R", Name = "Domain Expansion: Chimera Shadow Garden", Kanji = "嵌合暗翳庭",
		Cooldown = 60, Duration = 15, Radius = 60, CloneDamage = 70, CloneInterval = 1.2,
		EnemySlow = 0.6, CooldownMultiplier = 0.5, DamageType = "Shadow",
	},
	Agito = {
		Key = "T", Name = "Agito", Kanji = "顎吐",
		Cooldown = 40, Duration = 10, Damage = 140, Interval = 1.2, Range = 50, HealPerStrike = 8,
		DamageType = "Chimera",
	},
	Ritual = {
		Key = "G", Name = "Furube Yura Yura (Dabura Karaba)", Kanji = "布瑠部由良由良",
		Cooldown = 10, HoldSeconds = 1.5, SpawnDistance = 34,
	},
	TamedMahoraga = {
		Key = "H", Name = "Divine General Mahoraga", Kanji = "八握剣異戒神将魔虚羅",
		Cooldown = 90, Duration = 20, Damage = 380, Interval = 1.6, Range = 60, CurseMultiplier = 2,
		DamageType = "Extermination",
		Locked = true, UnlockHint = "Defeat Mahoraga in the ritual to tame it",
	},
	Block = { Key = "F", Name = "Guard", Kanji = "防御" },
}

Config.Boss = {
	Name = "Eight-Handled Sword Divergent Sila Divine General Mahoraga",
	ShortName = "Mahoraga",
	Scale = 1,
	MaxHealth = 16000,
	HealthPerExtraPlayer = 0.6, -- +60% max health for every extra player in the server
	BaseDamageTaken = 0.8, -- takes 80% damage before adaptation
	WalkSpeed = 22,
	Phase2WalkSpeed = 30,
	Phase2Threshold = 0.5,
	Phase2CooldownMultiplier = 0.65,
	AggroRange = 400,
	RespawnSeconds = 60,
	HitRadius = 6,
	KnockbackResist = 0.15,
	OutOfCombatRegen = 0.02, -- fraction per second when nobody is around

	-- Adaptation (the wheel): every HitsPerTurn hits of a type turn the wheel one notch.
	-- After TurnsToAdapt notches Mahoraga is adapted to that type.
	HitsPerTurn = 3,
	TurnsToAdapt = 4,
	ReductionPerTurn = 0.17,
	AdaptedMultiplier = 0.05,
	AdaptHealFraction = 0.06,
	CounterChance = 0.45,
	CounterCooldown = 4,

	-- Attacks (damage is before the anti one-shot cap in Config.Player)
	Attacks = {
		Combo = { Damage = 30, Hits = 3, Range = 16, Angle = 120, Windup = 0.45, Cooldown = 2.2 },
		SwordOfExtermination = { Damage = 55, Range = 26, Angle = 70, Windup = 0.8, Cooldown = 3.2 },
		GroundSlam = { Damage = 45, Radius = 24, Windup = 1.0, Cooldown = 4.5, Knockback = 70 },
		Rush = { Damage = 35, Distance = 70, Width = 10, Windup = 0.5, Cooldown = 3.5, Knockback = 60 },
		Counter = { Damage = 40, Range = 14, Windup = 0.35 },
		WorldSlash = { Damage = 70, Length = 140, Width = 9, Windup = 1.2, Cooldown = 7, MinAdaptations = 1 },
		WheelResonance = { Damage = 20, Radius = 30, Knockback = 80 },
	},
}

Config.Curses = {
	MaxHealth = 1500,
	RespawnSeconds = 5,
	BurstInterval = 4,
	BurstRadius = 10,
	BurstDamage = 8,
	Positions = { Vector3.new(-40, 0, 70), Vector3.new(0, 0, 90), Vector3.new(40, 0, 70) },
}

Config.Arena = {
	Center = Vector3.new(0, 0, 0),
	Radius = 170,
	PlayerSpawn = Vector3.new(0, 0, 120),
	BossAltar = Vector3.new(0, 0, -60),
}

-- Built-in Roblox content only, so the place works with no uploads.
-- Swap in your own rbxassetid:// sounds for better audio.
Config.Sounds = {
	Summon = "rbxasset://sounds/electronicpingshort.wav",
	Slash = "rbxasset://sounds/swordslash.wav",
	Lunge = "rbxasset://sounds/swordlunge.wav",
	Unsheath = "rbxasset://sounds/unsheath.wav",
	Hit = "rbxasset://sounds/swordslash.wav",
}

Config.Textures = {
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Spark = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

return Config
