--!strict
--[[
	Domain Expansion: Authentic Mutual Love (Shingan Soai).
	A dome closes over a field of countless katanas stuck in the ground, each one
	holding a technique Yuta has copied, under a crimson sky of giant gears.

	`center` is the ground point in the middle of the domain.
]]

local PartKit = require(script.Parent.PartKit)
local Katana = require(script.Parent.Katana)
local Palette = require(script.Parent.Parent.Palette)

local Domain = {}

local GEAR = Color3.fromRGB(86, 60, 44)
local GROUND = Color3.fromRGB(46, 40, 48)

-- Gear lying in cf's XZ plane (axis = cf's Y axis).
function Domain.buildGear(parent: Instance?, cf: CFrame, radius: number, teeth: number): Model
	local m = PartKit.model("Gear", parent)
	local style = { Color = GEAR, Material = Enum.Material.Metal }
	local hub = PartKit.cylinderY({ Name = "Hub", Parent = m, CFrame = cf, Color = GEAR, Material = Enum.Material.Metal }, radius * 0.14, radius * 0.42)
	m.PrimaryPart = hub
	PartKit.ring(m, cf, radius * 0.84, radius * 0.2, radius * 0.12, 18, style)
	PartKit.ring(m, cf, radius * 0.36, radius * 0.08, radius * 0.1, 10, style)
	PartKit.ring(m, cf * CFrame.new(0, radius * 0.065, 0), radius * 0.84, radius * 0.03, radius * 0.01, 18, {
		Color = Palette.DomainSky,
		Material = Enum.Material.Neon,
	})
	for k = 1, teeth do
		local a = (k - 0.5) / teeth * math.pi * 2
		PartKit.part({
			Name = "Tooth",
			Parent = m,
			CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius * 1.0),
			Size = Vector3.new(radius * 0.15, radius * 0.12, radius * 0.2),
			Color = GEAR,
			Material = Enum.Material.Metal,
		})
	end
	for k = 1, 6 do
		local a = k / 6 * math.pi * 2
		PartKit.part({
			Name = "Spoke",
			Parent = m,
			CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius * 0.58),
			Size = Vector3.new(radius * 0.1, radius * 0.09, radius * 0.5),
			Color = GEAR,
			Material = Enum.Material.Metal,
		})
	end
	return m
end

-- Katana stuck point-first into the ground at `ground`.
function Domain.buildGroundSword(parent: Instance?, ground: CFrame, scale: number, embed: number): Model
	local tipDistance = (0.86 + Katana.BladeLength + 0.36) * scale
	local handleFrame = ground * CFrame.new(0, tipDistance - embed, 0) * CFrame.Angles(math.pi, 0, 0)
	return Katana.buildModel(parent, handleFrame, scale, "lite")
end

-- `onStep` (optional) runs after each sword so the client can spread the build over frames.
function Domain.build(parent: Instance?, center: CFrame, radius: number, seed: number, swordCount: number?, onStep: ((number) -> ())?): Model
	local rng = Random.new(seed)
	local model = PartKit.model("AuthenticMutualLove", parent)

	PartKit.cylinderY({
		Name = "Floor",
		Parent = model,
		CFrame = center * CFrame.new(0, 0.06, 0),
		Color = GROUND,
		Material = Enum.Material.Slate,
	}, 0.12, radius * 2)

	-- Dome: bands of panels facing inward, glowing crimson at the horizon and black overhead.
	local dome = PartKit.model("Dome", model)
	local bands = 6
	local maxLat = math.rad(78)
	local lonSegments = 24
	local centerPos = center.Position
	for b = 0, bands - 1 do
		local lat0 = b / bands * maxLat
		local lat1 = (b + 1) / bands * maxLat
		local lat = (lat0 + lat1) / 2
		local ringRadius = radius * math.cos(lat)
		local height = radius * (lat1 - lat0) * 1.3
		local width = 2 * math.pi * ringRadius / lonSegments * 1.25
		-- Self-lit (Neon) so the dome reads as one sky: crimson horizon fading to black.
		local t = b / (bands - 1)
		local color = Palette.DomainSky:Lerp(Palette.DomainTop, t ^ 0.45)
		for i = 1, lonSegments do
			local lon = (i - 0.5) / lonSegments * math.pi * 2
			local normal = center.Rotation * Vector3.new(math.cos(lat) * math.sin(lon), math.sin(lat), math.cos(lat) * math.cos(lon))
			local pos = centerPos + normal * radius
			PartKit.part({
				Name = "Panel",
				Parent = dome,
				CFrame = PartKit.lookAt(pos, centerPos),
				Size = Vector3.new(width, height, 1.6),
				Color = color,
				Material = Enum.Material.Neon,
			})
		end
	end
	PartKit.cylinderY({
		Name = "Cap",
		Parent = dome,
		CFrame = center * CFrame.new(0, radius * math.sin(maxLat), 0),
		Color = Palette.DomainTop,
		Material = Enum.Material.Neon,
	}, 1, radius * math.cos(maxLat) * 2.25)

	-- From outside, the domain is a sealed black sphere. Parts are only drawn from
	-- the outside, so this shell is invisible to anyone standing inside it.
	PartKit.ball(dome, center, (radius + 2.5) * 2, { Color = Color3.fromRGB(6, 4, 8) }, "Shell")

	-- Gears turning in the sky.
	local gears = PartKit.model("Gears", model)
	local gearSpots = {
		{ at = Vector3.new(-0.48, 0.58, -0.45), size = 0.24 },
		{ at = Vector3.new(0.52, 0.5, -0.36), size = 0.2 },
		{ at = Vector3.new(0.02, 0.72, 0.3), size = 0.26 },
		{ at = Vector3.new(-0.42, 0.45, 0.5), size = 0.18 },
		{ at = Vector3.new(0.45, 0.62, 0.45), size = 0.16 },
	}
	for i, spot in gearSpots do
		local pos = center * (spot.at * radius)
		local cf = PartKit.lookAt(pos, centerPos) * CFrame.Angles(math.rad(-90), 0, 0)
		local gear = Domain.buildGear(gears, cf, radius * spot.size, 12 + i * 2)
		gear.Name = "Gear" .. i
	end

	-- The sword field. Each sword keeps its ground CFrame so the client can raise it out of the floor.
	local swords = PartKit.model("Swords", model)
	for i = 1, swordCount or 56 do
		local dist = math.sqrt(rng:NextNumber()) * (radius - 10) + 6
		local angle = rng:NextNumber() * math.pi * 2
		local ground = center
			* CFrame.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
			* CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0)
			* CFrame.Angles(math.rad(rng:NextNumber(-18, 18)), 0, math.rad(rng:NextNumber(-18, 18)))
		local sword = Domain.buildGroundSword(swords, ground, 1.7 + rng:NextNumber() * 0.7, 1.1)
		sword.Name = "Sword" .. i
		sword:SetAttribute("Ground", ground.Position)
		if onStep then
			onStep(i)
		end
	end

	local glow = PartKit.part({ Name = "Glow", Parent = model, CFrame = center * CFrame.new(0, radius * 0.5, 0), Size = Vector3.one, Transparency = 1 })
	PartKit.light(glow, Palette.DomainSky, math.min(radius, 60), 1.2)
	return model
end

return Domain
