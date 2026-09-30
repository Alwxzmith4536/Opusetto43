--!strict
--[[
	Procedural part helpers. Every model and effect in this kit is built from
	plain Roblox parts at runtime, so there are no meshes to upload and no asset
	ids that can break.

	All builders only construct instances (no services, no tweens), which lets
	tools/preview render them outside Roblox.
]]

local PartKit = {}

export type Props = {
	Name: string?,
	Parent: Instance?,
	CFrame: CFrame?,
	Size: Vector3?,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Reflectance: number?,
	Shape: Enum.PartType?,
	Anchored: boolean?,
	CanCollide: boolean?,
	CastShadow: boolean?,
}

export type Style = {
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
}

PartKit.Textures = {
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
	Spark = "rbxasset://textures/particles/fire_sparks_main.dds",
	Glow = "rbxasset://textures/particles/forcefield_glow_main.dds",
}

local function apply(p: BasePart, props: Props)
	p.Anchored = if props.Anchored == nil then true else props.Anchored
	p.CanCollide = props.CanCollide == true
	if not p.CanCollide then
		p.CanQuery = false
		p.CanTouch = false
	end
	p.CastShadow = props.CastShadow == true
	p.Material = props.Material or Enum.Material.SmoothPlastic
	p.Color = props.Color or Color3.new(1, 1, 1)
	p.Transparency = props.Transparency or 0
	p.Reflectance = props.Reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = props.Size or Vector3.one
	p.CFrame = props.CFrame or CFrame.identity
	p.Name = props.Name or p.ClassName
	if props.Parent then
		p.Parent = props.Parent
	end
end

function PartKit.part(props: Props): Part
	local p = Instance.new("Part")
	if props.Shape then
		p.Shape = props.Shape
	end
	apply(p, props)
	return p
end

function PartKit.wedge(props: Props): WedgePart
	local p = Instance.new("WedgePart")
	apply(p, props)
	return p
end

function PartKit.ball(parent: Instance?, cf: CFrame, diameter: number, style: Style, name: string?): Part
	return PartKit.part({
		Name = name or "Ball",
		Parent = parent,
		CFrame = cf,
		Size = Vector3.new(diameter, diameter, diameter),
		Shape = Enum.PartType.Ball,
		Color = style.Color,
		Material = style.Material,
		Transparency = style.Transparency,
	})
end

-- A block with a sphere SpecialMesh, which renders as an ellipsoid filling the part's size.
function PartKit.ellipsoid(props: Props): Part
	local p = PartKit.part(props)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

-- Roblox cylinders run along X; this one runs along cf's Y axis.
function PartKit.cylinderY(props: Props, height: number, diameter: number): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(height, diameter, diameter)
	props.CFrame = (props.CFrame or CFrame.identity) * CFrame.Angles(0, 0, math.rad(90))
	return PartKit.part(props)
end

-- Cylinder running along cf's look (-Z) axis, centred on cf.
function PartKit.cylinderZ(props: Props, length: number, diameter: number): Part
	props.Shape = Enum.PartType.Cylinder
	props.Size = Vector3.new(length, diameter, diameter)
	props.CFrame = (props.CFrame or CFrame.identity) * CFrame.Angles(0, math.rad(90), 0)
	return PartKit.part(props)
end

-- CFrame.lookAt that survives looking straight up or down.
function PartKit.lookAt(from: Vector3, to: Vector3): CFrame
	local dir = to - from
	if dir.Magnitude < 1e-5 then
		return CFrame.new(from)
	end
	local up = Vector3.new(0, 1, 0)
	if math.abs(dir.Unit:Dot(up)) > 0.995 then
		up = Vector3.new(0, 0, 1)
	end
	return CFrame.lookAt(from, to, up)
end

-- Block stretched from a to b (its Z axis runs along the segment).
function PartKit.segment(props: Props, a: Vector3, b: Vector3, thickness: number, depth: number?): Part
	local len = (b - a).Magnitude
	props.CFrame = PartKit.lookAt((a + b) / 2, b)
	props.Size = Vector3.new(thickness, depth or thickness, math.max(len, 0.05))
	return PartKit.part(props)
end

-- Rounded limb from a to b (ellipsoid that overlaps its joints slightly).
function PartKit.limb(props: Props, a: Vector3, b: Vector3, thickness: number, depth: number?): Part
	local len = (b - a).Magnitude
	props.CFrame = PartKit.lookAt((a + b) / 2, b)
	props.Size = Vector3.new(thickness, depth or thickness, len + thickness * 0.5)
	return PartKit.ellipsoid(props)
end

-- Cylinder from a to b with rounded ends, for organic limbs and fingers. Returns the body.
function PartKit.capsule(props: Props, a: Vector3, b: Vector3, diameter: number): Part
	local style = { Color = props.Color, Material = props.Material, Transparency = props.Transparency }
	local len = (b - a).Magnitude
	props.Shape = Enum.PartType.Cylinder
	props.CFrame = PartKit.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	props.Size = Vector3.new(math.max(len, 0.05), diameter, diameter)
	local body = PartKit.part(props)
	PartKit.ball(props.Parent, CFrame.new(a), diameter, style, "Cap")
	PartKit.ball(props.Parent, CFrame.new(b), diameter, style, "Cap")
	return body
end

-- Flat ring lying in cf's XZ plane.
function PartKit.ring(
	parent: Instance?,
	cf: CFrame,
	radius: number,
	thickness: number,
	height: number,
	segments: number,
	style: Style
): { Part }
	local list = {}
	local segLen = 2 * math.pi * radius / segments * 1.04
	for i = 1, segments do
		local a = (i - 0.5) / segments * math.pi * 2
		list[i] = PartKit.part({
			Name = "RingSeg",
			Parent = parent,
			CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius),
			Size = Vector3.new(segLen, height, thickness),
			Color = style.Color,
			Material = style.Material,
			Transparency = style.Transparency,
		})
	end
	return list
end

-- Crescent in cf's XZ plane around cf's -Z axis; swells in the middle like a sword arc.
-- Segment 1 sits on the right (+X) end.
function PartKit.crescent(
	parent: Instance?,
	cf: CFrame,
	radius: number,
	arcDegrees: number,
	maxThickness: number,
	height: number,
	segments: number,
	style: Style
): { Part }
	local list = {}
	local arc = math.rad(arcDegrees)
	local segLen = radius * arc / segments * 1.1
	for i = 1, segments do
		local t = (i - 0.5) / segments
		local a = -arc / 2 + arc * t
		local thick = math.max(0.06, maxThickness * math.sin(math.pi * t) ^ 0.7)
		list[i] = PartKit.part({
			Name = "ArcSeg",
			Parent = parent,
			CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -(radius + thick * 0.5)),
			Size = Vector3.new(segLen, height, thick),
			Color = style.Color,
			Material = style.Material,
			Transparency = style.Transparency,
		})
	end
	return list
end

function PartKit.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

function PartKit.weld(a: BasePart, b: BasePart): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
	return w
end

-- Turns an anchored build into one physics assembly welded to `root`.
function PartKit.weldAllTo(container: Instance, root: BasePart)
	for _, d in container:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			PartKit.weld(root, d)
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
		end
	end
	root.Anchored = false
end

function PartKit.light(parent: Instance, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

function PartKit.emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

-- Screen-facing text floating over `adornee`. Size is in studs.
function PartKit.billboardText(
	adornee: BasePart,
	text: string,
	width: number,
	height: number,
	color: Color3,
	stroke: Color3?
): (BillboardGui, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Text"
	gui.Size = UDim2.new(width, 0, height, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = color
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = stroke or Color3.new(0, 0, 0)
	label.Parent = gui
	return gui, label
end

return PartKit
