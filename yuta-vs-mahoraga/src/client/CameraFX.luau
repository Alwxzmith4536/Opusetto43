--!strict
-- Camera shake layered on top of the default camera.

local RunService = game:GetService("RunService")

local CameraFX = {}

type Shake = { intensity: number, duration: number, started: number }
local shakes: { Shake } = {}

function CameraFX.shake(intensity: number, duration: number)
	table.insert(shakes, { intensity = intensity, duration = math.max(duration, 0.05), started = os.clock() })
end

function CameraFX.start()
	RunService:BindToRenderStep("JJK_CameraShake", Enum.RenderPriority.Camera.Value + 1, function()
		if #shakes == 0 then
			return
		end
		local now = os.clock()
		local total = 0
		for i = #shakes, 1, -1 do
			local s = shakes[i]
			local t = (now - s.started) / s.duration
			if t >= 1 then
				table.remove(shakes, i)
			else
				total += s.intensity * (1 - t) ^ 2
			end
		end
		if total <= 0 then
			return
		end
		local camera = workspace.CurrentCamera
		local n = now * 38
		local offset = Vector3.new(math.noise(n, 3.1), math.noise(5.2, n), 0) * total * 0.6
		local rx = math.noise(n, 0.3) * total * 0.03
		local ry = math.noise(0.7, n) * total * 0.03
		camera.CFrame = camera.CFrame * CFrame.new(offset) * CFrame.Angles(rx, ry, 0)
	end)
end

return CameraFX
