--[[
	Sounds — tiny helper for one-shot 3D / 2D sounds defined in Config.Sounds.
]]

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(script.Parent.Config)

local Sounds = {}

--[[
	where: BasePart / Attachment (3D, follows it), Vector3 (3D at a point) or nil (2D)
	opts: { pitch = number, volume = number (multiplier), rolloff = number }
]]
function Sounds.play(name: string, where: (Instance | Vector3)?, opts)
	local def = Config.Sounds[name]
	if not def or def.Id == "" then
		return nil
	end
	opts = opts or {}
	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = (def.Volume or 0.7) * (opts.volume or 1)
	sound.PlaybackSpeed = opts.pitch or 1
	sound.RollOffMaxDistance = opts.rolloff or 220
	sound.RollOffMinDistance = 12

	local holder: Instance? = nil
	if typeof(where) == "Vector3" then
		local a = Instance.new("Attachment")
		a.Parent = Workspace.Terrain
		a.WorldPosition = where
		holder = a
		sound.Parent = a
	elseif typeof(where) == "Instance" then
		sound.Parent = where
	else
		sound.Parent = SoundService
	end

	sound:Play()
	local lifetime = 6 / math.max(sound.PlaybackSpeed, 0.1)
	Debris:AddItem(holder or sound, lifetime)
	return sound
end

return Sounds
