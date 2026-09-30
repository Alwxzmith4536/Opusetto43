--!strict
--[[
	Yuta's katana. The blade runs along the handle's +Y axis with the edge facing
	-Z and a slight curve (sori) toward the spine, like a real katana.

	buildParts: anchored parts around a handle frame (previews, the domain's sword field).
	buildTool: the equippable Tool with welded parts and a swing trail.
]]

local PartKit = require(script.Parent.PartKit)
local Palette = require(script.Parent.Parent.Palette)

local Katana = {}

local STEEL = Color3.fromRGB(198, 204, 216)
local EDGE = Color3.fromRGB(242, 245, 252)
local WRAP = Color3.fromRGB(20, 18, 26)
local SAME = Color3.fromRGB(206, 200, 214)
local GUARD = Color3.fromRGB(40, 38, 46)
local GOLD = Color3.fromRGB(214, 176, 92)

Katana.BladeLength = 3.4

-- detail "full" = tool / close-up, "lite" = sword field (fewer parts).
function Katana.buildParts(parent: Instance, h: CFrame, scale: number, detail: string): Part
	local s = scale
	local full = detail == "full"

	local handle = PartKit.part({
		Name = "Handle",
		Parent = parent,
		CFrame = h,
		Size = Vector3.new(0.24, 1.2, 0.32) * s,
		Color = WRAP,
		Material = Enum.Material.Fabric,
	})
	PartKit.part({
		Name = "Kashira",
		Parent = parent,
		CFrame = h * CFrame.new(0, -0.64 * s, 0),
		Size = Vector3.new(0.27, 0.12, 0.36) * s,
		Color = GUARD,
		Material = Enum.Material.Metal,
	})
	PartKit.cylinderY({
		Name = "Tsuba",
		Parent = parent,
		CFrame = h * CFrame.new(0, 0.64 * s, 0),
		Color = GUARD,
		Material = Enum.Material.Metal,
	}, 0.08 * s, 0.8 * s)
	PartKit.part({
		Name = "Habaki",
		Parent = parent,
		CFrame = h * CFrame.new(0, 0.77 * s, 0.01 * s),
		Size = Vector3.new(0.12, 0.18, 0.28) * s,
		Color = GOLD,
		Material = Enum.Material.Metal,
	})

	if full then
		-- Diamond pattern of the handle wrap (tsuka-ito over ray skin).
		for i = 0, 4 do
			local y = (-0.44 + i * 0.22) * s
			for _, side in { -1, 1 } do
				PartKit.part({
					Name = "Ito",
					Parent = parent,
					CFrame = h * CFrame.new(side * 0.121 * s, y, 0) * CFrame.Angles(math.rad(45), 0, 0),
					Size = Vector3.new(0.02, 0.11, 0.11) * s,
					Color = SAME,
				})
			end
		end
	end

	local segments = if full then 6 else 3
	local segLen = Katana.BladeLength * s / segments
	local bend = math.rad(if full then 1.7 else 3.4)
	local cursor = h * CFrame.new(0, 0.86 * s, 0)
	local width = 0.25 * s
	for i = 1, segments do
		width = (0.25 - 0.012 * i) * s
		local center = cursor * CFrame.new(0, segLen / 2, 0)
		PartKit.part({
			Name = "Blade",
			Parent = parent,
			CFrame = center,
			Size = Vector3.new(0.07 * s, segLen * 1.02, width),
			Color = STEEL,
			Material = Enum.Material.Metal,
			Reflectance = 0.15,
		})
		if full then
			PartKit.part({
				Name = "Edge",
				Parent = parent,
				CFrame = center * CFrame.new(0, 0, -width / 2 - 0.012 * s),
				Size = Vector3.new(0.04 * s, segLen * 1.02, 0.03 * s),
				Color = EDGE,
			})
		end
		cursor = cursor * CFrame.new(0, segLen, 0) * CFrame.Angles(bend, 0, 0)
	end
	-- Kissaki: the wedge's high edge sits on the spine side, so the point curves like a real tip.
	PartKit.wedge({
		Name = "Kissaki",
		Parent = parent,
		CFrame = cursor * CFrame.new(0, 0.18 * s, 0),
		Size = Vector3.new(0.07 * s, 0.36 * s, width),
		Color = STEEL,
		Material = Enum.Material.Metal,
		Reflectance = 0.15,
	})
	return handle
end

function Katana.buildModel(parent: Instance?, h: CFrame, scale: number, detail: string): Model
	local model = PartKit.model("Katana", parent)
	local handle = Katana.buildParts(model, h, scale, detail)
	model.PrimaryPart = handle
	return model
end

function Katana.buildTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Katana"
	tool.ToolTip = "Yuta's katana - click to slash"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- With an identity-rotation grip the handle's +Y points up while the arm is raised,
	-- so the blade stands upright in the default tool pose.
	tool.Grip = CFrame.new(0, -0.2, 0)

	local handle = Katana.buildParts(tool, CFrame.identity, 1, "full")
	for _, d in tool:GetChildren() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
			if d ~= handle then
				PartKit.weld(handle, d)
			end
		end
	end

	-- Swing trail along the blade, switched on by the server during slashes.
	local base = Instance.new("Attachment")
	base.Name = "BladeBase"
	base.Position = Vector3.new(0, 0.95, 0)
	base.Parent = handle
	local tip = Instance.new("Attachment")
	tip.Name = "BladeTip"
	tip.Position = Vector3.new(0, 4.2, 0.22)
	tip.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.Lifetime = 0.16
	trail.LightEmission = 1
	trail.FaceCamera = false
	trail.Color = ColorSequence.new(Palette.YutaCore, Palette.YutaEnergy)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Enabled = false
	trail.Parent = handle

	-- Faint cursed energy wisps on the blade.
	local aura = Instance.new("Attachment")
	aura.Name = "Aura"
	aura.Position = Vector3.new(0, 2.6, 0.1)
	aura.Parent = handle
	PartKit.emitter(aura, {
		Name = "CursedWisps",
		Texture = PartKit.Textures.Sparkle,
		Color = ColorSequence.new(Palette.YutaEnergy),
		LightEmission = 1,
		Size = NumberSequence.new(0.25, 0),
		Transparency = NumberSequence.new(0.3, 1),
		Lifetime = NumberRange.new(0.3, 0.6),
		Rate = 8,
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
	})
	return tool
end

return Katana
