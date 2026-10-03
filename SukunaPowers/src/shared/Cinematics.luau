--[[
	Cinematics — client camera cut-scenes, camera shake, letterbox bars,
	title cards, chant captions, screen flashes and colour grading.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Cine = {}

local player = Players.LocalPlayer

local function tween(instance: Instance, time: number, props, style: string?, dir: string?): Tween
	local t = TweenService:Create(
		instance,
		TweenInfo.new(time, (Enum.EasingStyle :: any)[style or "Quad"], (Enum.EasingDirection :: any)[dir or "Out"]),
		props
	)
	t:Play()
	return t
end

----------------------------------------------------------------------
-- Screen GUI
----------------------------------------------------------------------

local gui: ScreenGui? = nil
local bars = {}

function Cine.gui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "SukunaCinematic"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 20
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = player:WaitForChild("PlayerGui")

	for i, name in { "Top", "Bottom" } do
		local bar = Instance.new("Frame")
		bar.Name = name .. "Bar"
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.new(1, 0, 0, 0)
		bar.AnchorPoint = Vector2.new(0, i - 1)
		bar.Position = UDim2.new(0, 0, i - 1, 0)
		bar.ZIndex = 5
		bar.Parent = g
		bars[name] = bar
	end
	gui = g
	return g
end

function Cine.letterbox(on: boolean, time: number?)
	Cine.gui()
	local size = if on then UDim2.new(1, 0, 0.11, 0) else UDim2.new(1, 0, 0, 0)
	for _, bar in bars do
		tween(bar, time or 0.35, { Size = size }, "Quart", "Out")
	end
end

function Cine.flash(color: Color3, peak: number?, fadeIn: number?, hold: number?, fadeOut: number?)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundTransparency = 1
	f.ZIndex = 8
	f.Parent = Cine.gui()
	local p = peak or 0
	tween(f, fadeIn or 0.05, { BackgroundTransparency = p })
	task.delay((fadeIn or 0.05) + (hold or 0.05), function()
		tween(f, fadeOut or 0.4, { BackgroundTransparency = 1 }, "Quad", "In")
		task.delay((fadeOut or 0.4) + 0.05, function()
			f:Destroy()
		end)
	end)
end

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

-- Big centred title card: kanji + English subtitle.
function Cine.title(main: string, sub: string?, duration: number?, opts)
	opts = opts or {}
	duration = duration or 1.6
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = opts.position or UDim2.fromScale(0.5, 0.45)
	holder.Size = UDim2.fromScale(0.9, 0.42)
	holder.ZIndex = 10
	holder.Parent = Cine.gui()

	local scale = Instance.new("UIScale")
	scale.Scale = 1.35
	scale.Parent = holder

	local big = Instance.new("TextLabel")
	big.BackgroundTransparency = 1
	big.Size = UDim2.fromScale(1, 0.68)
	big.Font = Enum.Font.GothamBlack
	big.Text = main
	big.TextScaled = true
	big.TextColor3 = opts.color or Color3.fromRGB(255, 240, 240)
	big.TextTransparency = 1
	big.ZIndex = 11
	big.Parent = holder
	local bigStroke = stroke(big, opts.strokeColor or Color3.fromRGB(170, 0, 20), 3)
	bigStroke.Transparency = 1

	local small: TextLabel? = nil
	if sub then
		local s = Instance.new("TextLabel")
		s.BackgroundTransparency = 1
		s.Position = UDim2.fromScale(0, 0.7)
		s.Size = UDim2.fromScale(1, 0.24)
		s.Font = Enum.Font.GothamBold
		s.Text = sub
		s.TextScaled = true
		s.TextColor3 = Color3.fromRGB(255, 70, 80)
		s.TextTransparency = 1
		s.ZIndex = 11
		s.Parent = holder
		local ss = stroke(s, Color3.new(0, 0, 0), 2)
		ss.Transparency = 1
		small = s
		task.delay(0.12, function()
			tween(s, 0.25, { TextTransparency = 0 })
			tween(ss, 0.25, { Transparency = 0 })
		end)
	end

	tween(scale, 0.35, { Scale = 1 }, "Back", "Out")
	tween(big, 0.2, { TextTransparency = 0 })
	tween(bigStroke, 0.2, { Transparency = 0 })

	task.delay(duration, function()
		tween(scale, 0.4, { Scale = 0.92 }, "Quad", "In")
		tween(big, 0.4, { TextTransparency = 1 })
		tween(bigStroke, 0.4, { Transparency = 1 })
		if small then
			tween(small, 0.3, { TextTransparency = 1 })
			local ss = small:FindFirstChildOfClass("UIStroke")
			if ss then
				tween(ss, 0.3, { Transparency = 1 })
			end
		end
		task.delay(0.45, function()
			holder:Destroy()
		end)
	end)
end

-- Subtitle-style caption (chants, incantations).
function Cine.caption(text: string, duration: number?)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 0.86, 0)
	label.Size = UDim2.new(0.8, 0, 0.055, 0)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 225, 225)
	label.TextTransparency = 1
	label.ZIndex = 12
	label.Parent = Cine.gui()
	local s = stroke(label, Color3.fromRGB(90, 0, 10), 2)
	s.Transparency = 1
	tween(label, 0.18, { TextTransparency = 0 })
	tween(s, 0.18, { Transparency = 0 })
	task.delay(duration or 1.2, function()
		tween(label, 0.3, { TextTransparency = 1 })
		tween(s, 0.3, { Transparency = 1 })
		task.delay(0.35, function()
			label:Destroy()
		end)
	end)
end

----------------------------------------------------------------------
-- Colour grading
----------------------------------------------------------------------

local function grade(): ColorCorrectionEffect
	local g = Lighting:FindFirstChild("SukunaGrade")
	if not g then
		g = Instance.new("ColorCorrectionEffect")
		g.Name = "SukunaGrade"
		g.Parent = Lighting
	end
	return g :: ColorCorrectionEffect
end

function Cine.grade(props, time: number?)
	tween(grade(), time or 0.3, props)
end

function Cine.resetGrade(time: number?)
	tween(grade(), time or 0.6, {
		TintColor = Color3.new(1, 1, 1),
		Saturation = 0,
		Contrast = 0,
		Brightness = 0,
	})
end

-- Manga-style impact frame: harsh contrast + desaturation for an instant.
function Cine.impactFrame(duration: number?)
	local g = grade()
	g.Contrast = 1.4
	g.Saturation = -1
	g.Brightness = 0.12
	task.delay(duration or 0.1, function()
		Cine.resetGrade(0.25)
	end)
end

function Cine.blur(size: number, time: number?)
	local b = Lighting:FindFirstChild("SukunaBlur")
	if not b then
		b = Instance.new("BlurEffect")
		b.Name = "SukunaBlur"
		b.Size = 0
		b.Parent = Lighting
	end
	tween(b, time or 0.25, { Size = size })
end

----------------------------------------------------------------------
-- Camera shake (translation only, so it never drifts the camera)
----------------------------------------------------------------------

local shakeMagnitude = 0
local shakeEnd = 0
local shakeStart = 0
local shakeBound = false

local function onShake()
	local now = os.clock()
	if now >= shakeEnd then
		shakeMagnitude = 0
		return
	end
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local fade = 1 - (now - shakeStart) / math.max(shakeEnd - shakeStart, 0.01)
	local m = shakeMagnitude * fade
	local t = now * 32
	local offset = camera.CFrame.RightVector * (math.noise(t, 1.3) * 2 * m) + camera.CFrame.UpVector * (math.noise(2.7, t) * 2 * m)
	camera.CFrame += offset
end

function Cine.shake(magnitude: number, duration: number)
	if not shakeBound then
		shakeBound = true
		RunService:BindToRenderStep("SukunaShake", Enum.RenderPriority.Camera.Value + 2, onShake)
	end
	local now = os.clock()
	local remaining = if now < shakeEnd then shakeMagnitude * (1 - (now - shakeStart) / math.max(shakeEnd - shakeStart, 0.01)) else 0
	if magnitude >= remaining then
		shakeMagnitude = magnitude
		shakeStart = now
		shakeEnd = now + duration
	end
end

-- Shake scaled by distance from the camera to a world position.
function Cine.shakeAt(pos: Vector3, magnitude: number, duration: number, radius: number)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	local d = (camera.CFrame.Position - pos).Magnitude
	local f = 1 - math.clamp(d / radius, 0, 1)
	if f > 0.02 then
		Cine.shake(magnitude * f, duration)
	end
end

function Cine.fovPunch(amount: number, inTime: number?, outTime: number?)
	local camera = Workspace.CurrentCamera
	if not camera or Cine.isPlaying() then
		return
	end
	local base = 70
	tween(camera, inTime or 0.08, { FieldOfView = base + amount }, "Quad", "Out")
	task.delay(inTime or 0.08, function()
		if not Cine.isPlaying() then
			tween(camera, outTime or 0.35, { FieldOfView = base }, "Quad", "InOut")
		end
	end)
end

----------------------------------------------------------------------
-- Scripted camera shots
----------------------------------------------------------------------
--[[
	shots = {
		{ dur = 1.2, eye = {Vector3 from, Vector3 to}, look = {Vector3 from, Vector3 to},
		  fov = {from, to}, style = "Sine", dir = "InOut" },
	}
	eye / look offsets are in the character's root space at the start of each
	shot (X right, Y up, -Z forward). Returns a cancel function.
]]

local session = 0
local playingShots = false
local savedFov = 70

function Cine.isPlaying(): boolean
	return playingShots
end

local function restoreCamera()
	RunService:UnbindFromRenderStep("SukunaCinematicShot")
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		camera.FieldOfView = savedFov
	end
	playingShots = false
end

function Cine.cancel()
	session += 1
	if playingShots then
		restoreCamera()
		Cine.letterbox(false, 0.3)
	end
end

function Cine.shots(character: Model, shots, opts)
	opts = opts or {}
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local camera = Workspace.CurrentCamera
	if not root or not camera then
		return function() end
	end
	session += 1
	local my = session
	if not playingShots then
		savedFov = camera.FieldOfView
	end
	playingShots = true
	camera.CameraType = Enum.CameraType.Scriptable
	if opts.letterbox ~= false then
		Cine.letterbox(true)
	end

	local index = 1
	local shotStart = os.clock()
	local rootCF = root.CFrame

	RunService:UnbindFromRenderStep("SukunaCinematicShot")
	RunService:BindToRenderStep("SukunaCinematicShot", Enum.RenderPriority.Camera.Value + 1, function()
		if session ~= my then
			return
		end
		local shot = shots[index]
		if not shot or not root.Parent then
			restoreCamera()
			if opts.letterbox ~= false then
				Cine.letterbox(false)
			end
			return
		end
		local t = os.clock() - shotStart
		if t >= shot.dur then
			index += 1
			shotStart = os.clock()
			rootCF = root.CFrame
			shot = shots[index]
			if not shot then
				restoreCamera()
				if opts.letterbox ~= false then
					Cine.letterbox(false)
				end
				return
			end
			t = 0
		end
		local a = TweenService:GetValue(
			math.clamp(t / shot.dur, 0, 1),
			Enum.EasingStyle[shot.style or "Sine"],
			Enum.EasingDirection[shot.dir or "InOut"]
		)
		local eye = rootCF * shot.eye[1]:Lerp(shot.eye[2] or shot.eye[1], a)
		local look = rootCF * shot.look[1]:Lerp(shot.look[2] or shot.look[1], a)
		local cam = Workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
			local roll = shot.roll and math.rad(shot.roll[1] + ((shot.roll[2] or shot.roll[1]) - shot.roll[1]) * a) or 0
			cam.CFrame = CFrame.lookAt(eye, look) * CFrame.Angles(0, 0, roll)
			if shot.fov then
				cam.FieldOfView = shot.fov[1] + ((shot.fov[2] or shot.fov[1]) - shot.fov[1]) * a
			end
		end
	end)

	return function()
		if session == my then
			Cine.cancel()
		end
	end
end

-- Safety: always give the camera back when the character respawns.
player.CharacterAdded:Connect(function()
	Cine.cancel()
	Cine.resetGrade(0.1)
	Cine.blur(0, 0.1)
end)

return Cine
