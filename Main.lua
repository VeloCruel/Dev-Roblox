-- Main.lua (Executor entry point)
-- Loads all modules from GitHub — no local files needed.

local BASE_URL = "https://raw.githubusercontent.com/VeloCruel/Dev-Roblox/main/"

local function loadModule(name)
    local src     = game:HttpGet(BASE_URL .. name .. ".lua")
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

local player = Players.LocalPlayer

-- ── Flight controller ─────────────────────────────────────────────────────────

local controller = Controller.new()

-- ── Animation module ──────────────────────────────────────────────────────────
-- Self-contained: owns the Animator instance, preset map, display name, and
-- the bundle ID that survives stop() so respawns replay the last choice.

local AnimModule = (function()
    local animator = Animator.new()

    -- Build name → bundleId lookup from the preset list
    local presetMap = {}
    for _, p in ipairs(Animator.PRESETS) do
        presetMap[p.name] = p.bundleId  -- nil entry for "None" is intentional
    end

    local currentName  = "None"
    local lastBundleId = nil   -- persists across stop() for respawn replay

    local M = {}

    -- Apply a named preset ("None" stops the current animation).
    function M.applyPreset(name, character)
        if not character then return end

        local bundleId = presetMap[name]
        if bundleId then
            animator:applyBundle(character, bundleId)
            lastBundleId = bundleId
            currentName  = name
        else
            animator:stop()
            lastBundleId = nil
            currentName  = "None"
        end
    end

    -- Apply a raw animation ID entered by the user.
    function M.applyCustom(rawId, character)
        if not character then return end
        animator:play(character, rawId)
        lastBundleId = nil
        currentName  = "Custom"
    end

    -- Stop the animation and clear selection.
    function M.reset()
        animator:stop()
        lastBundleId = nil
        currentName  = "None"
    end

    -- Stop animation on character removal (Animate script on old char is gone
    -- anyway, but this keeps animator state clean).
    function M.onCharacterRemoving(character)
        animator:stop()
    end

    -- Replay the last chosen bundle after respawn.
    function M.onCharacterAdded(character)
        character:WaitForChild("HumanoidRootPart")
        character:WaitForChild("Humanoid")
        if lastBundleId then
            animator:applyBundle(character, lastBundleId)
        end
    end

    function M.currentName() return currentName end
    function M.presetNames() return Animator.presetNames() end

    return M
end)()

-- ── Interface ─────────────────────────────────────────────────────────────────

local interface = Interface.new({
    presetNames = AnimModule.presetNames(),

    onFlightToggle = function(val)
        local character = player.Character
        if not character then return end
        if val then controller:enable(character) else controller:disable(character) end
    end,

    onBoostToggle = function(val)
        controller:setBoosting(val)
    end,

    onAnimPreset = function(option)
        local name = type(option) == "table" and option[1] or option
        AnimModule.applyPreset(name, player.Character)
    end,

    onAnimCustom = function(rawId)
        AnimModule.applyCustom(rawId, player.Character)
    end,

    onAnimReset = function()
        AnimModule.reset()
    end,
})

-- ── Keybinds ──────────────────────────────────────────────────────────────────

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
    local flying   = controller:isActive()
    local boosting = controller.boosting

    if not flying then
        interface:update(false, 0, false, AnimModule.currentName())
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
    interface:update(true, controller:getSpeed(), boosting, AnimModule.currentName())
end)

-- ── Respawn handling ──────────────────────────────────────────────────────────

player.CharacterRemoving:Connect(function(character)
    controller:disable(character)
    AnimModule.onCharacterRemoving(character)
end)

player.CharacterAdded:Connect(function(character)
    AnimModule.onCharacterAdded(character)
end)
