-- Main.lua (LocalScript)
-- Entry point: wires UserInputService keybinds to Controller + Interface.
-- Place this LocalScript inside StarterPlayerScripts (or StarterCharacterScripts).
-- Controller.lua and Interface.lua must be siblings of this script.

local Players         = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService      = game:GetService("RunService")

local Controller = require(script.Parent.Controller)
local Interface  = require(script.Parent.Interface)

local player     = Players.LocalPlayer
local controller = Controller.new()
local interface  = Interface.new()

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getCharacter()
	return player.Character
end

-- ── Toggle flight: F ──────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.F then return end

	local character = getCharacter()
	if not character then return end

	if controller:isActive() then
		controller:disable(character)
	else
		controller:enable(character)
	end
end)

-- ── Speed boost: Shift (hold) ─────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.LeftShift
	or input.KeyCode == Enum.KeyCode.RightShift then
		controller:setBoosting(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift
	or input.KeyCode == Enum.KeyCode.RightShift then
		controller:setBoosting(false)
	end
end)

-- ── Per-frame input polling ───────────────────────────────────────────────────
-- Polled here so Controller stays input-agnostic and testable independently.

RunService.Heartbeat:Connect(function()
	if not controller:isActive() then
		interface:update(false, 0, false)
		return
	end

	local isDown = UserInputService.IsKeyDown

	-- Horizontal (camera-relative, fed as local X/Z)
	local inputVec = Vector3.new(
		(isDown(UserInputService, Enum.KeyCode.D) and 1 or 0)
		- (isDown(UserInputService, Enum.KeyCode.A) and 1 or 0),
		0,
		(isDown(UserInputService, Enum.KeyCode.S) and 1 or 0)
		- (isDown(UserInputService, Enum.KeyCode.W) and 1 or 0)
	)

	-- Vertical (world Y)
	local vertInput =
		(isDown(UserInputService, Enum.KeyCode.Space)       and 1 or 0)
		- (isDown(UserInputService, Enum.KeyCode.LeftControl) and 1 or 0)

	controller:setInput(inputVec, vertInput)
	interface:update(true, controller:getSpeed(), controller.boosting)
end)

-- ── Cleanup on respawn ────────────────────────────────────────────────────────

player.CharacterRemoving:Connect(function(character)
	controller:disable(character)
end)
