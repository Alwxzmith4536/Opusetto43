-- Builds shikigami / Mahoraga models out of Parts from ModelData (generated from assets/models.json).
--
-- ModelFactory.Build(name, {
--     CFrame = CFrame,      -- where the model's feet go (ground point), facing its LookVector
--     Scale = number,       -- default 1
--     Anchored = bool,      -- default true (client FX models). false = welded physics rig
--     Humanoid = bool,      -- adds a Humanoid + HumanoidRootPart (bosses / dummies)
--     Parent = Instance,
-- })
-- Unanchored rigs get Motor6D joints named after ModelData joints (Wheel, RightArm, LeftArm)
-- so the server can animate them by changing Motor6D.C0.

local ModelData = require(script.Parent.ModelData)

local ModelFactory = {}

local function vec(t, scale)
	return Vector3.new(t[1] * scale, t[2] * scale, t[3] * scale)
end

local function makePart(def, scale)
	local name, shape, size, pos, rot, color, material, _group, transparency = table.unpack(def)
	local part
	if shape == "Wedge" then
		part = Instance.new("WedgePart")
	else
		part = Instance.new("Part")
		part.Shape = Enum.PartType[shape]
	end
	part.Name = name
	part.Size = vec(size, scale)
	part.CFrame = CFrame.new(vec(pos, scale)) * CFrame.Angles(math.rad(rot[1]), math.rad(rot[2]), math.rad(rot[3]))
	part.Color = Color3.fromRGB(color[1], color[2], color[3])
	part.Material = Enum.Material[material]
	part.Transparency = transparency
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = material ~= "Neon"
	part.Massless = true
	return part
end

function ModelFactory.Exists(name)
	return ModelData[name] ~= nil
end

function ModelFactory.Build(name, opts)
	opts = opts or {}
	local data = ModelData[name]
	assert(data, "ModelFactory: unknown model " .. tostring(name))

	local scale = opts.Scale or 1
	local anchored = opts.Anchored ~= false
	local model = Instance.new("Model")
	model.Name = opts.Name or name

	local root = Instance.new("Part")
	root.Name = opts.Humanoid and "HumanoidRootPart" or "Root"
	root.Transparency = 1
	root.Anchored = anchored
	root.CanCollide = opts.Humanoid == true
	root.CanQuery = opts.Humanoid == true
	root.CanTouch = false
	local rootOffset = Vector3.zero
	if data.Root then
		root.Size = vec(data.Root.Size, scale)
		rootOffset = vec(data.Root.Pos, scale)
	else
		root.Size = Vector3.new(1, 1, 1)
	end
	root.CFrame = CFrame.new(rootOffset)
	root.Parent = model
	model.PrimaryPart = root

	local pivots = {}
	for jointName, joint in pairs(data.Joints) do
		local pivot = Instance.new("Part")
		pivot.Name = jointName .. "Pivot"
		pivot.Size = Vector3.new(0.2, 0.2, 0.2)
		pivot.Transparency = 1
		pivot.CanCollide = false
		pivot.CanQuery = false
		pivot.CanTouch = false
		pivot.Massless = true
		pivot.Anchored = anchored
		pivot.CFrame = CFrame.new(vec(joint.Pivot, scale))
		pivot.Parent = model
		pivots[jointName] = pivot
	end

	local parts = {}
	for _, def in ipairs(data.Parts) do
		local part = makePart(def, scale)
		part.Anchored = anchored
		part.Parent = model
		parts[part.Name] = part
		if not anchored then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = pivots[def[8]] or root
			weld.Part1 = part
			weld.Parent = part
		end
	end

	if not anchored then
		root.Massless = false
		for jointName, joint in pairs(data.Joints) do
			local part0 = parts[joint.Part0] or root
			local pivot = pivots[jointName]
			local motor = Instance.new("Motor6D")
			motor.Name = jointName
			motor.Part0 = part0
			motor.Part1 = pivot
			motor.C0 = part0.CFrame:ToObjectSpace(pivot.CFrame)
			motor.C1 = CFrame.new()
			motor.Parent = part0
		end
	end

	if opts.Humanoid then
		local humanoid = Instance.new("Humanoid")
		humanoid.HipHeight = (data.HipHeight or 2) * scale
		humanoid.BreakJointsOnDeath = false
		humanoid.RequiresNeck = false -- custom rigs have no Neck joint
		humanoid.AutomaticScalingEnabled = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.Parent = model
	end

	local ground = opts.CFrame or CFrame.new()
	model:PivotTo(ground * CFrame.new(rootOffset))
	if opts.Parent then
		model.Parent = opts.Parent
	end
	return model
end

-- Height of the model at scale 1 (for emerge / sink animations).
function ModelFactory.Height(name)
	local data = ModelData[name]
	return data and data.Height or 5
end

return ModelFactory
