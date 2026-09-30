--!strict
-- Hotbar definitions shared by the server (validation) and the client (input + HUD).

local Palette = require(script.Parent.Palette)

export type Def = {
	Id: string,
	Name: string,
	Short: string,
	Key: Enum.KeyCode,
	KeyLabel: string,
	Color: Color3,
	Kanji: string?,
	Hold: boolean?,
	Description: string,
}

local Abilities = {}

local defs: { [string]: Def } = {
	Dash = {
		Id = "Dash",
		Name = "Cursed Dash",
		Short = "Dash",
		Key = Enum.KeyCode.Q,
		KeyLabel = "Q",
		Color = Palette.YutaEnergy,
		Description = "Burst of cursed energy. Brief dodge window.",
	},
	RikaStrike = {
		Id = "RikaStrike",
		Name = "Rika: Partial Manifestation",
		Short = "Rika Strike",
		Key = Enum.KeyCode.Z,
		KeyLabel = "Z",
		Color = Palette.RikaAura,
		Kanji = "里香",
		Description = "Rika's arm tears out of the air behind Yuta and crushes the ground ahead.",
	},
	DontMove = {
		Id = "DontMove",
		Name = "Cursed Speech: Don't Move",
		Short = "Don't Move",
		Key = Enum.KeyCode.X,
		KeyLabel = "X",
		Color = Palette.SpeechRing,
		Kanji = "動くな",
		Description = "Copied from Toge Inumaki. Freezes every enemy nearby. Hurts Yuta's throat.",
	},
	BlastAway = {
		Id = "BlastAway",
		Name = "Cursed Speech: Blast Away",
		Short = "Blast Away",
		Key = Enum.KeyCode.C,
		KeyLabel = "C",
		Color = Palette.SpeechRing,
		Kanji = "吹っ飛べ",
		Description = "Copied from Toge Inumaki. A cone of words that launches enemies.",
	},
	RCT = {
		Id = "RCT",
		Name = "Reverse Cursed Technique",
		Short = "RCT Heal",
		Key = Enum.KeyCode.V,
		KeyLabel = "V",
		Color = Palette.RCT,
		Kanji = "反転術式",
		Description = "Positive energy heals Yuta and nearby allies. Clears stuns.",
	},
	FullManifestation = {
		Id = "FullManifestation",
		Name = "Rika: Full Manifestation",
		Short = "Full Rika",
		Key = Enum.KeyCode.F,
		KeyLabel = "F",
		Color = Palette.RikaAura,
		Kanji = "完全顕現",
		Description = "Rika manifests completely: +25% damage, auto claws, shields Yuta, unlocks Pure Love.",
	},
	PureLove = {
		Id = "PureLove",
		Name = "Pure Love: Jun'ai Ho",
		Short = "Pure Love",
		Key = Enum.KeyCode.R,
		KeyLabel = "R",
		Color = Palette.PureLove,
		Kanji = "純愛砲",
		Description = "Needs Full Manifestation. Yuta and Rika fire a colossal beam of cursed energy.",
	},
	Domain = {
		Id = "Domain",
		Name = "Domain Expansion: Authentic Mutual Love",
		Short = "Domain",
		Key = Enum.KeyCode.T,
		KeyLabel = "T",
		Color = Palette.DomainSky,
		Kanji = "真贋相愛",
		Description = "A field of countless katanas, each holding a copied technique. Sure-hit on everyone inside.",
	},
	SixEyes = {
		Id = "SixEyes",
		Name = "Copy: Body Transplant (Six Eyes)",
		Short = "Six Eyes",
		Key = Enum.KeyCode.G,
		KeyLabel = "G",
		Color = Palette.SixEyes,
		Kanji = "六眼",
		Description = "Kenjaku's copied technique moves Yuta into Gojo's body: Infinity, Blue, Red and Hollow Purple.",
	},
	Block = {
		Id = "Block",
		Name = "Cursed Energy Guard",
		Short = "Block",
		Key = Enum.KeyCode.E,
		KeyLabel = "E",
		Color = Palette.YutaCore,
		Hold = true,
		Description = "Hold to guard. Cuts blockable damage by 55%.",
	},
	Blue = {
		Id = "Blue",
		Name = "Cursed Technique Lapse: Blue",
		Short = "Blue",
		Key = Enum.KeyCode.Z,
		KeyLabel = "Z",
		Color = Palette.Blue,
		Kanji = "蒼",
		Description = "A point of attraction at your cursor that drags and crushes enemies.",
	},
	Red = {
		Id = "Red",
		Name = "Cursed Technique Reversal: Red",
		Short = "Red",
		Key = Enum.KeyCode.X,
		KeyLabel = "X",
		Color = Palette.Red,
		Kanji = "赫",
		Description = "A repelling blast fired at your cursor.",
	},
	HollowPurple = {
		Id = "HollowPurple",
		Name = "Hollow Technique: Purple",
		Short = "Purple",
		Key = Enum.KeyCode.C,
		KeyLabel = "C",
		Color = Palette.Purple,
		Kanji = "茈",
		Description = "Blue and Red collide into imaginary mass that erases everything in its path.",
	},
}

Abilities.Defs = defs

-- Hotbar layout per mode. Keys are read from the defs, so Z/X/C swap to
-- Blue/Red/Purple while Yuta is in Gojo's body.
Abilities.Bars = {
	Base = { "Dash", "RikaStrike", "DontMove", "BlastAway", "RCT", "FullManifestation", "PureLove", "Domain", "SixEyes", "Block" },
	SixEyes = { "Dash", "Blue", "Red", "HollowPurple", "RCT", "FullManifestation", "PureLove", "Domain", "SixEyes", "Block" },
}

function Abilities.forKey(mode: string, key: Enum.KeyCode): Def?
	local bar = Abilities.Bars[mode] or Abilities.Bars.Base
	for _, id in bar do
		local def = defs[id]
		if def and def.Key == key then
			return def
		end
	end
	return nil
end

function Abilities.inMode(mode: string, id: string): boolean
	local bar = Abilities.Bars[mode] or Abilities.Bars.Base
	return table.find(bar, id) ~= nil
end

return Abilities
