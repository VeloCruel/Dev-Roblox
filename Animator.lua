-- Animator.lua
-- Fetches real animation asset IDs live from the Roblox catalog API
-- using the bundle ID, patches the character's Animate LocalScript,
-- then restarts it so ALL states (idle/walk/run/jump/fall/climb) change.

local HttpService = game:GetService("HttpService")

-- Roblox assetType numbers → Animate LocalScript folder names
local TYPE_TO_FOLDER = {
    [48] = "climb",
    [50] = "fall",
    [51] = "idle",
    [52] = "jump",
    [53] = "run",
    [54] = "swim",
    [55] = "walk",
}

local Animator = {}
Animator.__index = Animator

-- Bundle IDs come directly from the Roblox catalog URL, e.g.
-- roblox.com/bundles/43/Toy-Animation-Pack  →  bundleId = 43
Animator.PRESETS = {
    { name = "None",       bundleId = nil },
    { name = "TOY",        bundleId = 43  },
    { name = "Pirate",     bundleId = 55  },
    { name = "Mage",       bundleId = 63  },
    { name = "Knight",     bundleId = 68  },
    { name = "Ninja",      bundleId = 75  },
    { name = "Levitation", bundleId = 79  },
    { name = "Zombie",     bundleId = 80  },
    { name = "Superhero",  bundleId = 81  },
    { name = "Robot",      bundleId = 82  },
    { name = "Stylish",    bundleId = 83  },
}

function Animator.presetNames()
    local t = {}
    for _, p in ipairs(Animator.PRESETS) do t[#t + 1] = p.name end
    return t
end

-- ── Catalog API helper ────────────────────────────────────────────────────────

local function fetchBundleAnims(bundleId)
    local url = "https://catalog.roblox.com/v1/bundles/"
                .. tostring(bundleId) .. "/details"

    local ok, raw = pcall(game.HttpGet, game, url)
    if not ok then
        warn("[Animator] HttpGet failed:", raw)
        return nil
    end

    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or not data or not data.items then
        warn("[Animator] JSON parse failed")
        return nil
    end

    local anims = {}
    for _, item in ipairs(data.items) do
        local folder = TYPE_TO_FOLDER[item.assetType]
        if item.type == "Asset" and folder then
            anims[folder] = "rbxassetid://" .. tostring(item.id)
        end
    end
    return anims
end

-- ── Core ──────────────────────────────────────────────────────────────────────

function Animator.new()
    return setmetatable({
        _animScript    = nil,
        _originals     = {},
        _track         = nil,   -- custom single-anim track
        _anim          = nil,
        _currentBundle = nil,
    }, Animator)
end

-- Apply a full animation bundle: patches ALL states then restarts Animate.
function Animator:applyBundle(character, bundleId)
    self:stop()

    local animScript = character:FindFirstChild("Animate")
    if not animScript then
        warn("[Animator] No Animate LocalScript on character")
        return
    end

    -- Fetch real asset IDs from the Roblox catalog API
    local anims = fetchBundleAnims(bundleId)
    if not anims then return end

    -- Save originals so stop() can restore them
    local originals = {}
    for _, desc in ipairs(animScript:GetDescendants()) do
        if desc:IsA("Animation") then
            originals[desc] = desc.AnimationId
        end
    end
    self._originals  = originals
    self._animScript = animScript

    -- Patch every Animation instance in each state folder
    for folder, assetId in pairs(anims) do
        local f = animScript:FindFirstChild(folder)
        if f then
            for _, child in ipairs(f:GetChildren()) do
                if child:IsA("Animation") then
                    child.AnimationId = assetId
                end
            end
        end
    end

    -- Restart Animate so it reloads tracks with the new IDs
    animScript.Disabled = true
    task.wait()
    animScript.Disabled = false

    self._currentBundle = bundleId
end

-- Play a single custom animation ID at Action4 priority (looping).
function Animator:play(character, rawId)
    self:stop()

    local n = tostring(rawId):match("%d+")
    if not n then
        warn("[Animator] Invalid ID:", tostring(rawId))
        return
    end
    local assetId = "rbxassetid://" .. n

    local humanoid    = character:FindFirstChildOfClass("Humanoid")
    local animatorObj = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not animatorObj then return end

    local animScript = character:FindFirstChild("Animate")
    if animScript then
        animScript.Disabled = true
        self._animScript = animScript
    end

    for _, t in ipairs(animatorObj:GetPlayingAnimationTracks()) do
        t:Stop(0)
    end

    local anim  = Instance.new("Animation")
    anim.AnimationId = assetId
    local track = animatorObj:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped   = true
    track:Play(0)

    self._track = track
    self._anim  = anim

    -- If the animation never actually loads (bad ID), recover after 2 s
    task.delay(2, function()
        if self._track ~= track then return end
        if track.Length == 0 then
            warn("[Animator] Animation failed to load (bad ID?):", rawId)
            self:stop()
        end
    end)
end

function Animator:stop()
    -- Clean up custom track
    if self._track then
        pcall(function() self._track:Stop(0) end)
        pcall(function() self._track:Destroy() end)
        self._track = nil
    end
    if self._anim then
        pcall(function() self._anim:Destroy() end)
        self._anim = nil
    end

    -- Restore original Animation IDs and restart Animate
    if self._animScript then
        pcall(function()
            for desc, id in pairs(self._originals) do
                desc.AnimationId = id
            end
            self._animScript.Disabled = true
            task.wait()
            self._animScript.Disabled = false
        end)
        self._animScript = nil
    end

    self._originals     = {}
    self._currentBundle = nil
end

function Animator:getCurrentBundle()
    return self._currentBundle
end

return Animator
