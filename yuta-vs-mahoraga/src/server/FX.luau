--!strict
-- Sends visual-effect events to clients. The server decides what happens; each
-- client builds and animates the effect locally, so nothing heavy replicates.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("JJKShared"):WaitForChild("Net"))

local remote = Net.event("FX")

local FX = {}

function FX.all(name: string, data: { [string]: any })
	remote:FireAllClients(name, data)
end

function FX.to(player: Player, name: string, data: { [string]: any })
	remote:FireClient(player, name, data)
end

-- Only players whose character is within `radius` of `pos`.
function FX.near(pos: Vector3, radius: number, name: string, data: { [string]: any })
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - pos).Magnitude <= radius then
			remote:FireClient(player, name, data)
		end
	end
end

function FX.shake(pos: Vector3, intensity: number, duration: number, radius: number)
	FX.near(pos, radius, "Shake", { intensity = intensity, duration = duration })
end

return FX
