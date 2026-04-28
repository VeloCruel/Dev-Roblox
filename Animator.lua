-- Animator.lua
-- Applies a custom looped animation by disabling the character's built-in
-- Animate script and playing the chosen track at the highest priority.
-- Bundle presets: idle animation ID is fetched once from the catalog API
-- and cached so repeated selects skip the HTTP round-trip.

local HttpService = game:GetService("HttpService")

local Animator   = {}
Animator.__index = Animator

-- ── Presets ───────────────────────────────────────────────────────────────────

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

-- ── Idle-ID fetch (cached) ────────────────────────────────────────────────────

local _cache = {}

-- Catalog API: assetType 51 = IdleAnimation (Enum.AssetType value).
-- Older endpoint versions return assetType as a plain integer; newer ones
-- return an object { id = 51, name = "IdleAnimation" }.  Both are handled.
local function fetchIdleId(bundleId)
    if _cache[bundleId] then return _cache[bundleId] end

    local ok, raw = pcall(game.HttpGet, game,
        "https://catalog.roblox.com/v1/bundles/" .. bundleId .. "/details")
    if not ok then
        warn("[Animator] HTTP request failed for bundle", bundleId, "–", raw)
        return nil
    end

    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" or type(data.items) ~= "table" then
        warn("[Animator] Unexpected response format for bundle", bundleId)
        return nil
    end

    for _, item in ipairs(data.items) do
        local typeId = type(item.assetType) == "table" and item.assetType.id or item.assetType
        if item.type == "Asset" and typeId == 51 then
            local id = tostring(item.id)
            _cache[bundleId] = id
            return id
        end
    end

    warn("[Animator] No idle animation found in bundle", bundleId)
    return nil
end

-- ── Character helpers ─────────────────────────────────────────────────────────

local function getAnimObj(character)
    local hum = character:FindFirstChildOfClass("Humanoid")
    return hum and hum:FindFirstChildOfClass("Animator")
end

-- Disable the Animate script and stop every track so our animation plays clean.
local function suppressAnimate(character)
    local animScript = character:FindFirstChild("Animate")
    if animScript then animScript.Disabled = true end

    local animObj = getAnimObj(character)
    if animObj then
        for _, t in ipairs(animObj:GetPlayingAnimationTracks()) do
            t:Stop(0)
        end
    end

    return animObj
end

-- Re-enable the Animate script so normal character animations resume.
local function restoreAnimate(character)
    if not character or not character.Parent then return end
    local animScript = character:FindFirstChild("Animate")
    if animScript then animScript.Disabled = false end
end

-- ── Animator class ────────────────────────────────────────────────────────────

function Animator.new()
    return setmetatable({
        _track = nil,
        _anim  = nil,
        _char  = nil,
    }, Animator)
end

-- Internal: disable Animate, load, and play the given asset ID on character.
function Animator:_apply(character, assetId)
    self:stop()

    local animObj = suppressAnimate(character)
    if not animObj then
        warn("[Animator] Character has no Animator object")
        return
    end

    local anim = Instance.new("Animation")
    anim.AnimationId = "rbxassetid://" .. assetId

    local track = animObj:LoadAnimation(anim)
    track.Priority = Enum.AnimationPriority.Action4
    track.Looped   = true
    track:Play(0)

    self._track = track
    self._anim  = anim
    self._char  = character
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Apply the idle animation from a catalog bundle.
function Animator:applyBundle(character, bundleId)
    local id = fetchIdleId(bundleId)
    if id then self:_apply(character, id) end
end

-- Apply an animation by raw asset ID or full rbxassetid:// URL.
function Animator:play(character, rawId)
    local id = tostring(rawId):match("%d+")
    if not id then warn("[Animator] Invalid animation ID:", rawId); return end
    self:_apply(character, id)
end

-- Stop the custom animation and restore normal character animations.
function Animator:stop()
    if self._track then
        pcall(function() self._track:Stop(0) end)
        pcall(function() self._track:Destroy() end)
        self._track = nil
    end
    if self._anim then
        pcall(function() self._anim:Destroy() end)
        self._anim = nil
    end
    if self._char then
        restoreAnimate(self._char)
        self._char = nil
    end
end

return Animator
