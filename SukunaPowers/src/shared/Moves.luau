--[[
	Moves — keyframed R15 pose sequences for every Sukuna technique.

	Joint angle convention (degrees, applied in YXZ order on the joint):
	  Shoulders  x+ raise arm forward (90 = straight ahead, 180 = up)
	             z+ raise RIGHT arm out to the side, z- raise LEFT arm out
	             y+ swing a raised arm toward the character's left
	  Elbows     x+ bend the forearm forward / inward
	  Waist/Root x+ lean back, x- bow forward, y+ twist left, z+ tilt left
	  Neck       x+ look up, x- look down, y+ turn left
	  Hips       x+ leg forward, z+ right leg out / z- left leg out
	  Knees      x- bend
	  crouch     solves hips/knees/ankles + root drop with feet planted
	  shake      trembling intensity (degrees) — cursed energy surging
]]

local Moves = {}

local rad = math.rad

local function A(x: number?, y: number?, z: number?): CFrame
	return CFrame.fromEulerAnglesYXZ(rad(x or 0), rad(y or 0), rad(z or 0))
end

local function AP(x: number?, y: number?, z: number?, px: number?, py: number?, pz: number?): CFrame
	return CFrame.new(px or 0, py or 0, pz or 0) * A(x, y, z)
end

local Style = Enum.EasingStyle
local Dir = Enum.EasingDirection

local function K(t: number, pose, style: string?, dir: string?)
	return {
		t = t,
		pose = pose,
		style = Style[style or "Sine"],
		dir = Dir[dir or "InOut"],
	}
end

-- Shallow-merge pose tables (later tables override earlier ones).
local function with(...)
	local out = {}
	for i = 1, select("#", ...) do
		local t = select(i, ...)
		for k, v in t do
			out[k] = v
		end
	end
	return out
end

local relaxed = {
	RightShoulder = A(4, 0, 9),
	LeftShoulder = A(4, 0, -9),
	RightElbow = A(14),
	LeftElbow = A(14),
}

----------------------------------------------------------------------
-- Transformation: clutch head → struggle → cursed energy burst → laugh
----------------------------------------------------------------------
do
	local hunch = {
		Waist = A(-38, 0, 0),
		Neck = A(-26, 0, 0),
		RightShoulder = A(140, 0, 25),
		LeftShoulder = A(140, 0, -25),
		RightElbow = A(122),
		LeftElbow = A(122),
		RightWrist = A(-20),
		LeftWrist = A(-20),
		crouch = 30,
		shake = 2.5,
	}
	local struggle = with(hunch, {
		Waist = A(-30, 9, -7),
		Neck = A(-18, 12, 9),
		RightShoulder = A(132, 0, 34),
		LeftShoulder = A(146, 0, -20),
		crouch = 36,
		shake = 5.5,
	})
	local burst = {
		Root = AP(0, 0, 0, 0, 0.15, 0),
		Waist = A(22, 0, 0),
		Neck = A(32, 0, 0),
		RightShoulder = A(0, 20, 115),
		LeftShoulder = A(0, -20, -115),
		RightElbow = A(25),
		LeftElbow = A(25),
		RightWrist = A(0, 0, 15),
		LeftWrist = A(0, 0, -15),
		RightHip = A(0, 0, 8),
		LeftHip = A(0, 0, -8),
		crouch = 6,
		shake = 1.4,
	}
	local laughUp = with(burst, { Neck = A(40, 0, 0), Waist = A(27, 0, 0), shake = 1.0 })
	local laughDown = with(burst, { Neck = A(24, 0, 0), Waist = A(17, 0, 0), shake = 1.0 })
	local stance = with(relaxed, {
		Waist = A(-4, 12, 0),
		Neck = A(-7, -12, 0),
		crouch = 4,
	})

	Moves.Transform = {
		duration = 3.9,
		blendOut = 0.45,
		keys = {
			K(0.3, hunch, "Quad", "Out"),
			K(1.25, struggle, "Sine", "InOut"),
			K(1.6, burst, "Back", "Out"),
			K(1.95, laughUp),
			K(2.2, laughDown),
			K(2.45, laughUp),
			K(2.7, laughDown),
			K(2.95, laughUp),
			K(3.5, stance, "Quad", "InOut"),
		},
	}
end

----------------------------------------------------------------------
-- Combo: jab → hook → uppercut → roundhouse kick
----------------------------------------------------------------------
do
	local jabWind = {
		Waist = A(0, -18, 0),
		Neck = A(0, 15, 0),
		RightShoulder = A(55, 0, 10),
		RightElbow = A(110),
		LeftShoulder = A(60, 0, -10),
		LeftElbow = A(115),
		crouch = 12,
	}
	local jab = {
		Waist = A(-6, 28, 0),
		Neck = A(0, -24, 0),
		RightShoulder = A(92, 8, 0),
		RightElbow = A(4),
		LeftShoulder = A(55, 0, -15),
		LeftElbow = A(120),
		RightHip = A(10),
		LeftHip = A(-8),
		crouch = 14,
	}
	Moves.Combo1 = {
		duration = 0.36,
		blendOut = 0.22,
		keys = { K(0.07, jabWind, "Quad", "Out"), K(0.14, jab, "Quint", "Out"), K(0.3, jab) },
	}

	local hookWind = {
		Waist = A(0, 22, 0),
		Neck = A(0, -18, 0),
		LeftShoulder = A(0, 12, -78),
		LeftElbow = A(70),
		RightShoulder = A(60, 0, 10),
		RightElbow = A(115),
		crouch = 14,
	}
	local hook = {
		Waist = A(-5, -32, 0),
		Neck = A(0, 28, 0),
		LeftShoulder = A(0, -62, -85),
		LeftElbow = A(88),
		RightShoulder = A(50, 0, 15),
		RightElbow = A(120),
		LeftHip = A(10),
		RightHip = A(-8),
		crouch = 16,
	}
	Moves.Combo2 = {
		duration = 0.38,
		blendOut = 0.22,
		keys = { K(0.08, hookWind, "Quad", "Out"), K(0.16, hook, "Quint", "Out"), K(0.32, hook) },
	}

	local upWind = {
		Waist = A(-18, -14, 0),
		Neck = A(8, 10, 0),
		RightShoulder = A(15, 0, 15),
		RightElbow = A(115),
		LeftShoulder = A(60, 0, -15),
		LeftElbow = A(110),
		crouch = 28,
	}
	local upper = {
		Root = AP(0, 0, 0, 0, 0.25, 0),
		Waist = A(14, 22, 0),
		Neck = A(18, -15, 0),
		RightShoulder = A(155, 10, 0),
		RightElbow = A(55),
		LeftShoulder = A(40, 0, -25),
		LeftElbow = A(100),
		crouch = 2,
	}
	Moves.Combo3 = {
		duration = 0.4,
		blendOut = 0.25,
		keys = { K(0.09, upWind, "Quad", "Out"), K(0.18, upper, "Back", "Out"), K(0.34, upper) },
	}

	local kickWind = {
		Root = A(0, -22, 0),
		Waist = A(-6, -8, 0),
		Neck = A(0, 20, 0),
		RightShoulder = A(20, 0, 40),
		RightElbow = A(40),
		LeftShoulder = A(30, 0, -50),
		LeftElbow = A(60),
		RightHip = A(-25, 0, 10),
		RightKnee = A(-50),
		crouch = 10,
	}
	local kick = {
		Root = A(0, 50, 14),
		Waist = A(0, -12, 8),
		Neck = A(0, -38, -10),
		RightHip = A(10, 0, 82),
		RightKnee = A(-12),
		LeftHip = A(0, 0, -6),
		LeftKnee = A(-20),
		LeftShoulder = A(10, 0, -80),
		LeftElbow = A(35),
		RightShoulder = A(15, 0, 55),
		RightElbow = A(60),
		crouch = 6,
	}
	Moves.Combo4 = {
		duration = 0.48,
		blendOut = 0.3,
		keys = { K(0.09, kickWind, "Quad", "Out"), K(0.19, kick, "Back", "Out"), K(0.38, kick) },
	}
end

----------------------------------------------------------------------
-- Dismantle (解): three casual flicks, each launches a flying slash
----------------------------------------------------------------------
do
	local left = { LeftShoulder = A(8, 0, -12), LeftElbow = A(20) }
	local wind = with(left, {
		Waist = A(0, 32, 0),
		Neck = A(-4, -28, 0),
		RightShoulder = A(90, 75, 0),
		RightElbow = A(35),
		RightWrist = A(0, 0, -20),
		crouch = 8,
	})
	local slash1 = with(left, {
		Waist = A(-4, -28, 0),
		Neck = A(-4, 24, 0),
		RightShoulder = A(88, -65, 0),
		RightElbow = A(5),
		RightWrist = A(0, 0, 15),
		crouch = 10,
	})
	local slash2 = with(left, {
		Waist = A(-4, 14, 0),
		Neck = A(-4, -12, 0),
		RightShoulder = A(104, 35, 0),
		RightElbow = A(22),
		crouch = 10,
	})
	local slash3 = with(left, {
		Waist = A(-6, -24, 0),
		Neck = A(-4, 20, 0),
		RightShoulder = A(80, -50, 0),
		RightElbow = A(4),
		crouch = 12,
	})
	Moves.Dismantle = {
		duration = 0.85,
		blendOut = 0.3,
		keys = {
			K(0.16, wind, "Quad", "Out"),
			K(0.28, slash1, "Quint", "Out"),
			K(0.44, slash2, "Quint", "Out"),
			K(0.6, slash3, "Quint", "Out"),
			K(0.75, slash3),
		},
	}
end

----------------------------------------------------------------------
-- Cleave (捌): dash in, palm on the target, rapid adaptive cuts, sweep out
----------------------------------------------------------------------
do
	local dash = {
		Root = A(-18, 0, 0),
		Waist = A(-10, 0, 0),
		Neck = A(12, 0, 0),
		RightShoulder = A(-35, 0, 10),
		RightElbow = A(25),
		LeftShoulder = A(-30, 0, -10),
		LeftElbow = A(25),
		crouch = 18,
	}
	local reach = {
		Root = A(-6, 0, 0),
		Waist = A(-8, 25, 0),
		Neck = A(0, -22, 0),
		RightShoulder = A(92, -6, 0),
		RightElbow = A(8),
		RightWrist = A(-25),
		LeftShoulder = A(15, 0, -20),
		LeftElbow = A(30),
		RightHip = A(25),
		RightKnee = A(-20),
		LeftHip = A(-20),
		crouch = 14,
	}
	local hold = with(reach, { shake = 1.8 })
	local sweep = {
		Waist = A(-4, -35, 0),
		Neck = A(0, 25, 0),
		RightShoulder = A(85, -75, 0),
		RightElbow = A(5),
		LeftShoulder = A(10, 0, -25),
		LeftElbow = A(20),
		crouch = 10,
	}
	Moves.Cleave = {
		duration = 1.15,
		blendOut = 0.3,
		keys = {
			K(0.08, dash, "Quad", "Out"),
			K(0.22, reach, "Back", "Out"),
			K(0.85, hold),
			K(0.98, sweep, "Quint", "Out"),
			K(1.1, sweep),
		},
	}
end

----------------------------------------------------------------------
-- Fuga (開): flame in the palm → draw the fire bow → release
----------------------------------------------------------------------
do
	local legs = {
		LeftHip = A(22, 0, -8),
		LeftKnee = A(-18),
		RightHip = A(-18, 0, 8),
		RightKnee = A(-12),
	}
	local open = {
		Waist = A(-4, -10, 0),
		Neck = A(-14, 8, 0),
		RightShoulder = A(55, 30, 0),
		RightElbow = A(95),
		RightWrist = A(-30),
		LeftShoulder = A(10, 0, -15),
		LeftElbow = A(20),
		crouch = 10,
	}
	local gaze = with(open, { Neck = A(-20, 10, 0), shake = 1.0 })
	local draw = with(legs, {
		Waist = A(0, -22, 0),
		Neck = A(0, 22, 0),
		LeftShoulder = A(90, 22, 0),
		LeftElbow = A(0),
		LeftWrist = A(10),
		RightShoulder = A(0, -35, 88),
		RightElbow = A(125),
		crouch = 16,
	})
	local tension = with(draw, { RightShoulder = A(0, -46, 88), shake = 1.6 })
	local release = with(legs, {
		Root = A(5, 0, 0),
		Waist = A(6, -30, 0),
		Neck = A(4, 26, 0),
		LeftShoulder = A(90, 22, 0),
		LeftElbow = A(0),
		RightShoulder = A(0, -72, 80),
		RightElbow = A(25),
		crouch = 14,
	})
	Moves.Fuga = {
		duration = 2.3,
		blendOut = 0.4,
		keys = {
			K(0.3, open, "Quad", "Out"),
			K(0.75, gaze),
			K(1.05, draw, "Back", "Out"),
			K(1.5, tension),
			K(1.6, release, "Quint", "Out"),
			K(2.15, release),
		},
	}
end

----------------------------------------------------------------------
-- Domain Expansion: Malevolent Shrine — hand sign, then arms spread
----------------------------------------------------------------------
do
	local sign = {
		Waist = A(-3, 0, 0),
		Neck = A(-8, 0, 0),
		RightShoulder = A(62, 45, 0),
		RightElbow = A(100),
		RightWrist = A(0, -25, 0),
		LeftShoulder = A(62, -45, 0),
		LeftElbow = A(100),
		LeftWrist = A(0, 25, 0),
		crouch = 6,
	}
	local sign2 = with(sign, { Neck = A(-2, 0, 0), shake = 1.4 })
	local reveal = {
		Waist = A(10, 0, 0),
		Neck = A(14, 0, 0),
		RightShoulder = A(0, 18, 72),
		LeftShoulder = A(0, -18, -72),
		RightElbow = A(30),
		LeftElbow = A(30),
		crouch = 0,
		shake = 0.6,
	}
	local stance = with(relaxed, { Waist = A(-2, 8, 0), Neck = A(-8, -8, 0) })
	Moves.Domain = {
		duration = 4.4,
		blendOut = 0.4,
		keys = {
			K(0.35, sign, "Quad", "Out"),
			K(2.2, sign2),
			K(2.6, reveal, "Back", "Out"),
			K(3.8, reveal),
			K(4.3, stance),
		},
	}
end

----------------------------------------------------------------------
-- World Cutting Slash: chant with raised hand → overhead → cleave down
----------------------------------------------------------------------
do
	local chant = {
		Waist = A(-4, 0, 0),
		Neck = A(-6, 0, 0),
		RightShoulder = A(118, 22, 0),
		RightElbow = A(75),
		LeftShoulder = A(55, -35, 0),
		LeftElbow = A(105),
		crouch = 8,
	}
	local chant2 = with(chant, { shake = 2.2 })
	local raise = {
		Root = AP(0, 0, 0, 0, 0.2, 0),
		Waist = A(14, 0, 0),
		Neck = A(12, 0, 0),
		RightShoulder = A(172, 0, 8),
		RightElbow = A(2),
		LeftShoulder = A(35, 0, -30),
		LeftElbow = A(40),
		crouch = 4,
	}
	local slash = {
		Waist = A(-32, 0, 0),
		Neck = A(-6, 0, 0),
		RightShoulder = A(72, -8, 0),
		RightElbow = A(5),
		LeftShoulder = A(-25, 0, -25),
		LeftElbow = A(20),
		RightHip = A(-15),
		LeftHip = A(28),
		LeftKnee = A(-25),
		crouch = 26,
	}
	Moves.WorldSlash = {
		duration = 3.6,
		blendOut = 0.45,
		keys = {
			K(0.35, chant, "Quad", "Out"),
			K(1.9, chant2),
			K(2.2, raise, "Back", "Out"),
			K(2.35, slash, "Quint", "Out"),
			K(3.2, slash),
		},
	}
end

----------------------------------------------------------------------
-- Hit reactions (played on whoever gets hit)
----------------------------------------------------------------------
do
	local flinch = {
		Waist = A(16, 0, 0),
		Neck = A(18, 0, 0),
		RightShoulder = A(25, 0, 20),
		LeftShoulder = A(25, 0, -20),
		RightElbow = A(40),
		LeftElbow = A(40),
		crouch = 8,
	}
	Moves.Flinch = {
		duration = 0.16,
		blendOut = 0.22,
		keys = { K(0.06, flinch, "Quad", "Out") },
	}

	local stagger = {
		Root = A(-10, 0, 0),
		Waist = A(28, 0, 6),
		Neck = A(30, 0, 0),
		RightShoulder = A(40, 0, 50),
		LeftShoulder = A(40, 0, -50),
		RightElbow = A(30),
		LeftElbow = A(30),
		crouch = 14,
	}
	Moves.Stagger = {
		duration = 0.45,
		blendOut = 0.35,
		keys = { K(0.08, stagger, "Back", "Out"), K(0.4, stagger) },
	}
end

return Moves
