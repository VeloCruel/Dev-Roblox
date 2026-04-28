-- Main.lua (Executor entry point)
-- Loads Controller and Interface directly from GitHub — no local files needed.
-- Replace BASE_URL with your own repo's raw base path.

local BASE_URL = "https://raw.githubusercontent.com/VeloCruel/Dev-Roblox/main/"

local function loadModule(name)
    local url  = BASE_URL .. name .. ".lua"
    local src  = game:HttpGet(url)
    local fn, err = loadstring(src)
    assert(fn, "[FlightSystem] Failed to parse " .. name .. ": " .. tostring(err))
    return fn()
end

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local Controller = loadModule("Controller")
local Interface  = loadModule("Interface")

local player     = Players.LocalPlayer
local controller = Controller.new()
local interface  = Interface.new()

-- ── Toggle flight: F ──────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode ~= Enum.KeyCode.F then return end

	local character = player.Character
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

	local inputVec = Vector3.new(
		(UserInputService:IsKeyDown(Enum.KeyCode.D) and 1 or 0)
		- (UserInputService:IsKeyDown(Enum.KeyCode.A) and 1 or 0),
		0,
		(UserInputService:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
		- (UserInputService:IsKeyDown(Enum.KeyCode.W) and 1 or 0)
	)

	local vertInput =
		(UserInputService:IsKeyDown(Enum.KeyCode.Space)        and 1 or 0)
		- (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) and 1 or 0)

	controller:setInput(inputVec, vertInput)
	interface:update(true, controller:getSpeed(), controller.boosting)
end)

-- ── Cleanup on respawn ────────────────────────────────────────────────────────

player.CharacterRemoving:Connect(function(character)
	controller:disable(character)
end)
