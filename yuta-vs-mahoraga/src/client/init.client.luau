--!strict
-- Yuta Okkotsu vs Mahoraga: client entry point.

local HUD = require(script:WaitForChild("HUD"))
local CameraFX = require(script:WaitForChild("CameraFX"))
local VFX = require(script:WaitForChild("VFX"))
local Input = require(script:WaitForChild("Input"))
local BossAnimator = require(script:WaitForChild("BossAnimator"))
local RikaFollower = require(script:WaitForChild("RikaFollower"))

HUD.start()
CameraFX.start()
VFX.start()
Input.start()
BossAnimator.start()
RikaFollower.start()
