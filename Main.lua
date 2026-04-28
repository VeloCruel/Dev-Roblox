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

local player     = Players.LocalPlayer
local controller = Controller.new()
local animator   = Animator.new()

-- name → bundleId  (nil for "None")
local presetMap = {}
for _, p in ipairs(Animator.PRESETS) do
    presetMap[p.name] = p.bundleId
end

-- Track what is currently playing for HUD display and respawn replay
local currentAnimName   = "None"
local lastBundleId      = nil   -- survives stop(), used for respawn replay

local interface = Interface.new({
    presetNames = Animator.presetNames(),

    onFlightToggle = function(val)
        local character = player.Character
        if not character then return end
        if val then controller:enable(character) else controller:disable(character) end
    end,

    onBoostToggle = function(val)
        controller:setBoosting(val)
    end,

    onAnimPreset = function(option)
        local name      = type(option) == "table" and option[1] or option
        local bundleId  = presetMap[name]
        local character = player.Character
        if not character then return end

        if bundleId then
            animator:applyBundle(character, bundleId)
            lastBundleId    = bundleId
            currentAnimName = name
        else
            animator:stop()
            lastBundleId    = nil
            currentAnimName = "None"
        end
    end,

    onAnimCustom = function(rawId)
        local character = player.Character
        if not character then return end
        animator:play(character, rawId)
        lastBundleId    = nil
        currentAnimName = "Custom"
    end,

    onAnimReset = function()
        animator:stop()
        lastBundleId    = nil
        currentAnimName = "None"
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
        interface:update(false, 0, false, currentAnimName)
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
    interface:update(true, controller:getSpeed(), boosting, currentAnimName)
end)

-- ── Respawn handling ──────────────────────────────────────────────────────────

player.CharacterRemoving:Connect(function(character)
    controller:disable(character)
    -- Don't call animator:stop() here — it would clear lastBundleId.
    -- The old character's Animate script gets destroyed anyway.
    animator._animScript    = nil
    animator._originals     = {}
    animator._currentBundle = nil
    if animator._track then
        pcall(function() animator._track:Stop(0) end)
        animator._track = nil
    end
end)

player.CharacterAdded:Connect(function(character)
    character:WaitForChild("HumanoidRootPart")
    character:WaitForChild("Humanoid")
    -- Replay last selected bundle after respawn
    if lastBundleId then
        animator:applyBundle(character, lastBundleId)
    end
end)
