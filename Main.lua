-- Main.lua (Executor entry point)
-- Loads all modules from GitHub — no local files needed.

local BASE_URL = "https://raw.githubusercontent.com/VeloCruel/Dev-Roblox/main/"

local function loadModule(name)
	local src    = game:HttpGet(BASE_URL .. name .. ".lua")
	local fn, err = loadstring(src)
	assert(fn, "[FlightSystem] Failed to parse " .. name .. ": " .. tostring(err))
	return fn()
end

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")

local Controller = loadModule("Controller")
local Animator   = loadModule("Animator")
local Interface  = loadModule("Interface")

local player     = Players.LocalPlayer
local controller = Controller.new()
local animator   = Animator.new()

-- Build a name → id lookup from presets for the dropdown callback
local presetMap = {}
for _, p in ipairs(Animator.PRESETS) do
	presetMap[p.name] = p.id
end

local interface = Interface.new({
	-- Provide preset names to the dropdown
	presetNames = Animator.presetNames(),

	onFlightToggle = function(val)
		local character = player.Character
		if not character then return end
		if val then controller:enable(character) else controller:disable(character) end
	end,

	onBoostToggle = function(val)
		controller:setBoosting(val)
	end,

	onAnimPreset = function(name)
		local character = player.Character
		if not character then return end
		local id = presetMap[name]
		if id then
			animator:play(character, id)
		else
			animator:stop()
		end
	end,

	onAnimCustom = function(rawId)
		local character = player.Character
		if not character then return end
		animator:play(character, rawId)
	end,

	onAnimReset = function()
		animator:stop()
	end,
})

-- ── Keybinds ──────────────────────────────────────────────────────────────────

-- Toggle flight: F
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

-- Speed boost: Shift hold
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

-- ── Per-frame update ──────────────────────────────────────────────────────────

RunService.Heartbeat:Connect(function()
	local flying    = controller:isActive()
	local boosting  = controller.boosting
	local animName  = animator:getCurrentId() and "Custom" or "None"

	-- Resolve preset name for display
	if animator:getCurrentId() then
		for _, p in ipairs(Animator.PRESETS) do
			if p.id == animator:getCurrentId() then
				animName = p.name
				break
			end
		end
	end

	if not flying then
		interface:update(false, 0, false, animName)
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
	interface:update(true, controller:getSpeed(), boosting, animName)
end)

-- ── Respawn handling ──────────────────────────────────────────────────────────

player.CharacterRemoving:Connect(function(character)
	controller:disable(character)
	animator:stop()
end)

player.CharacterAdded:Connect(function(character)
	-- Wait for character to fully load before replaying animation
	character:WaitForChild("HumanoidRootPart")
	character:WaitForChild("Humanoid")
	animator:replayOn(character)
end)
