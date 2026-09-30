--[[
	Loads the kit's ModuleScripts outside Roblox with Lune, so the procedural
	asset builders can be run headless (tools/preview/export.luau).

	Emulates just enough of Roblox: `script`/`script.Parent` navigation over the
	src/ folder and `require` on those proxies. Instances and datatypes come from
	Lune's @lune/roblox, which validates every property name against the real
	Roblox API database, so a typo in a builder fails here.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

-- Deterministic stand-in for Roblox's Random.
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed: number?)
	local self = setmetatable({ state = (seed or 1) % 2147483647 }, RandomShim)
	if self.state <= 0 then
		self.state += 2147483646
	end
	return self
end
function RandomShim:_next(): number
	self.state = (self.state * 48271) % 2147483647
	return self.state / 2147483647
end
function RandomShim:NextNumber(a: number?, b: number?): number
	local r = self:_next()
	if a and b then
		return a + (b - a) * r
	end
	return r
end
function RandomShim:NextInteger(a: number, b: number): number
	return a + math.floor(self:_next() * (b - a + 1))
end

local proxies: { [string]: any } = {}
local cache: { [string]: any } = {}
-- Filled by Loader.init: Lune's fs calls yield, which is not allowed inside
-- the proxies' __index metamethods, so the tree is scanned up front.
local known: { [string]: string } = {}
local sources: { [string]: string } = {}

local function scan(dir: string)
	known[dir] = "dir"
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		elseif string.match(name, "%.luau?$") then
			known[path] = "file"
			sources[path] = fs.readFile(path)
		end
	end
end

function Loader.init(rootDir: string)
	scan(rootDir)
end

local makeProxy

local function childProxy(dir: string, name: string): any
	for _, ext in { ".luau", ".lua" } do
		local file = dir .. "/" .. name .. ext
		if known[file] == "file" then
			return makeProxy(file, false)
		end
	end
	local sub = dir .. "/" .. name
	if known[sub] == "dir" then
		return makeProxy(sub, true)
	end
	return nil
end

function makeProxy(path: string, dir: boolean): any
	if proxies[path] then
		return proxies[path]
	end
	local proxy = setmetatable({}, {
		__index = function(_, key)
			if key == "Parent" then
				local parent = string.match(path, "^(.*)/[^/]+$")
				return parent and makeProxy(parent, true)
			elseif key == "Name" then
				local base = string.match(path, "([^/]+)$") or path
				return (string.gsub(base, "%.luau?$", ""))
			elseif key == "__path" then
				return path
			elseif key == "WaitForChild" or key == "FindFirstChild" then
				return function(self, name)
					return self[name]
				end
			end
			if dir then
				local child = childProxy(path, key)
				if child then
					return child
				end
			end
			error(("%s is not a valid member of %s"):format(tostring(key), path))
		end,
		__tostring = function()
			return path
		end,
	})
	proxies[path] = proxy
	return proxy
end

-- Lune 0.10's CFrame.lookAt returns a wrong rotation for most directions, so
-- modules get a CFrame table with a correct lookAt (Roblox semantics: -Z faces
-- the target, X = look x up) built on fromMatrix, which Lune gets right.
local function lookAt(from: any, to: any, up: any?): any
	local look = (to - from).Unit
	local right = look:Cross(up or roblox.Vector3.new(0, 1, 0)).Unit
	return roblox.CFrame.fromMatrix(from, right, right:Cross(look), -look)
end
local CFrame = setmetatable({ lookAt = lookAt }, { __index = roblox.CFrame })
Loader.CFrame = CFrame

local globals: { [string]: any } = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = roblox.Enum,
	PhysicalProperties = roblox.PhysicalProperties,
	BrickColor = roblox.BrickColor,
	Random = RandomShim,
}

-- Extra globals (e.g. a stub `game`) for modules that touch services at load time.
function Loader.setGlobal(name: string, value: any)
	globals[name] = value
end

function Loader.require(proxy: any): any
	local path = proxy.__path
	if cache[path] ~= nil then
		return cache[path]
	end
	local source = sources[path] or fs.readFile(path)
	local env = table.clone(globals)
	env.script = proxy
	env.require = Loader.require
	local fn = luau.load(source, { debugName = path, environment = env, injectGlobals = true })
	local result = fn()
	cache[path] = result
	return result
end

function Loader.module(path: string): any
	return Loader.require(makeProxy(path, false))
end

-- Proxy for a folder (e.g. "src/shared"), as `script.Parent` would return it.
function Loader.folder(path: string): any
	return makeProxy(path, true)
end

Loader.Random = RandomShim
Loader.roblox = roblox

return Loader
