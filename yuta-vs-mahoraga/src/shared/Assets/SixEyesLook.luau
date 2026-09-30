--!strict
--[[
	Yuta after copying Kenjaku's technique and moving into Gojo Satoru's body:
	white hair, glowing Six Eyes, and the stitched scar across the forehead.
	`visual` is the visible size of the head (R6 heads are meshes smaller than their part).
]]

local PartKit = require(script.Parent.PartKit)
local Palette = require(script.Parent.Parent.Palette)

local SixEyesLook = {}

local HAIR = Color3.fromRGB(222, 228, 240)
local STITCH = Color3.fromRGB(58, 30, 36)

function SixEyesLook.build(head: BasePart, visual: Vector3): Model
	local m = PartKit.model("JJK_SixEyesLook")
	local hc = head.CFrame
	local w, h, d = visual.X, visual.Y, visual.Z
	local function at(x: number, y: number, z: number): CFrame
		return hc * CFrame.new(x * w, y * h, z * d)
	end
	local function off(x: number, y: number, z: number): Vector3
		return hc.Rotation * Vector3.new(x * w, y * h, z * d)
	end

	PartKit.ellipsoid({ Name = "HairCap", Parent = m, CFrame = at(0, 0.3, 0.05), Size = Vector3.new(w * 1.06, h * 0.58, d * 1.08), Color = HAIR })
	-- Gojo's spiky white hair: two rings of thin spikes swept up and back.
	for ring = 0, 1 do
		local count = if ring == 0 then 14 else 9
		for i = 1, count do
			local a = math.rad(-160 + (i - 1) * (320 / (count - 1)))
			local lift = 0.4 + ring * 0.14
			local spread = 0.44 - ring * 0.16
			local root = at(math.sin(a) * spread, lift, math.cos(a) * spread * 0.9 + 0.04).Position
			local tip = root + off(math.sin(a) * (0.3 - ring * 0.1), 0.34 + 0.1 * math.cos(i * 1.9) + ring * 0.08, math.cos(a) * 0.26 + 0.14)
			PartKit.limb({ Name = "Spike", Parent = m, Color = HAIR }, root, tip, (0.11 - ring * 0.015) * w)
		end
	end
	for _, x in { -0.3, -0.15, 0, 0.15, 0.3 } do
		local root = at(x, 0.5, -0.3).Position
		PartKit.limb({ Name = "Bang", Parent = m, Color = HAIR }, root, root + off(x * 0.35, -0.1, -0.26), 0.12 * w)
	end
	for _, side in { -1, 1 } do
		PartKit.part({
			Name = "SixEye",
			Parent = m,
			CFrame = at(side * 0.19, 0.05, -0.505),
			Size = Vector3.new(0.11 * w, 0.045 * h, 0.02 * d),
			Color = Palette.SixEyes,
			Material = Enum.Material.Neon,
		})
	end
	-- Kenjaku's stitches across the forehead.
	PartKit.part({ Name = "Stitch", Parent = m, CFrame = at(0, 0.21, -0.505), Size = Vector3.new(0.8 * w, 0.025 * h, 0.015 * d), Color = STITCH })
	for k = -3, 3 do
		PartKit.part({ Name = "StitchMark", Parent = m, CFrame = at(k * 0.1, 0.21, -0.51), Size = Vector3.new(0.018 * w, 0.09 * h, 0.015 * d), Color = STITCH })
	end

	for _, d2 in m:GetDescendants() do
		if d2:IsA("BasePart") then
			d2.Anchored = false
			d2.Massless = true
			PartKit.weld(head, d2)
		end
	end
	return m
end

return SixEyesLook
