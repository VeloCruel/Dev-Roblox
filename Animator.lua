-- Animator.lua
-- Fetches the real idle animation ID from the Roblox catalog API at runtime.
-- Uses Animator.AnimationPlayed to intercept and stop every track the game
-- tries to play, so ours can never be overridden.

local HttpService = game:GetService("HttpService")

local Animator = {}
Animator.__index = Animator

-- Only the bundle ID is stored — the real animation asset ID is fetched live
-- from catalog.roblox.com so it is always correct and up to date.
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

-- assetType 51 = Idle in Roblox's animation bundle schema
local function fetchIdleId(bundleId)
    local ok, raw = pcall(game.HttpGet, game,
        "https://catalog.roblox.com/v1/bundles/" .. bundleId .. "/details")
    if not ok then warn("[Animator] HttpGet failed:", raw); return nil end

    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or not data or not data.items then warn("[Animator] Bad JSON"); return nil end

    for _, item in ipairs(data.items) do
        -- assetType may be a plain number or a nested table {id, name} depending on API version
        local assetTypeId = type(item.assetType) == "table" and item.assetType.id or item.assetType
        if item.type == "Asset" and assetTypeId == 51 then
            return tostring(item.id)
        end
    end
    warn("[Animator] No idle animation found in bundle", bundleId)
    return nil
end

function Animator.new()
    return setmetatable({
        _track      = nil,
        _anim       = nil,
        _connection = nil,
    }, Animator)
end

-- Internal: load and lock an animation by its numeric asset ID string
function Animator:_lock(character, numericId)
    self:stop()

    local humanoid    = character:FindFirstChildOfClass("Humanoid")
    local animatorObj = humanoid and humanoid:FindFirstChildOfClass("Animator")
    if not humanoid or not animatorObj then
        warn("[Animator] No Humanoid/Animator")
        return
    end

    -- Kill every currently-playing track
    for _, t in ipairs(animatorObj:GetPlayingAnimationTracks()) do
        t:Stop(0)
    end

    -- Build and load our track
    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. numericId

    local track = animatorObj:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped   = true

    self._track = track
    self._anim  = anim

    -- Capture track by value so the closure is correct even if self._track
    -- changes (e.g. stop() is called) before a deferred AnimationPlayed fires.
    local ownTrack = track
    self._connection = animatorObj.AnimationPlayed:Connect(function(t)
        if t ~= ownTrack then
            t:Stop(0)
        end
    end)

    track:Play(0)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Animator:applyBundle(character, bundleId)
    local idleId = fetchIdleId(bundleId)
    if not idleId then return end
    self:_lock(character, idleId)
end

function Animator:play(character, rawId)
    local n = tostring(rawId):match("%d+")
    if not n then warn("[Animator] Invalid ID:", rawId); return end
    self:_lock(character, n)
end

function Animator:stop()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
    if self._track then
        pcall(function() self._track:Stop(0) end)
        pcall(function() self._track:Destroy() end)
        self._track = nil
    end
    if self._anim then
        pcall(function() self._anim:Destroy() end)
        self._anim = nil
    end
end

return Animator
