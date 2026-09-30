--!strict
-- Yuta Okkotsu vs Mahoraga: server entry point.
-- Builds the arena first (so nobody spawns into the void), then starts the kit and the altar.

local World = require(script:WaitForChild("World"))
local YutaKit = require(script:WaitForChild("YutaKit"))

World.start()
YutaKit.start()

print("[JJK] Yuta Okkotsu vs Mahoraga is ready. Hold P at the altar to summon Mahoraga.")
