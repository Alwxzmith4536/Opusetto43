--!strict
-- Small math helpers shared by server and client.

local Util = {}

function Util.flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.flatUnit(v: Vector3, fallback: Vector3?): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-4 then
		return fallback or Vector3.new(0, 0, -1)
	end
	return f.Unit
end

function Util.now(): number
	return workspace:GetServerTimeNow()
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

-- Horizontal facing frame at `pos` looking along `dir`.
function Util.facing(pos: Vector3, dir: Vector3): CFrame
	local d = Util.flatUnit(dir)
	return CFrame.lookAt(pos, pos + d)
end

function Util.formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Util.randomBetween(rng: Random, a: number, b: number): number
	return a + (b - a) * rng:NextNumber()
end

-- Picks a key from { key = weight } using `rng`.
function Util.weightedPick(rng: Random, weights: { [string]: number }): string?
	local total = 0
	for _, w in weights do
		total += w
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	local last: string? = nil
	for key, w in weights do
		last = key
		roll -= w
		if roll <= 0 then
			return key
		end
	end
	return last
end

return Util
