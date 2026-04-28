-- Animator.lua
-- Disable the Animate LocalScript, kill all tracks, play ours.
-- On any failure, Animate is automatically re-enabled so the character
-- is never left as a statue.

local Animator = {}
Animator.__index = Animator

-- Asset IDs sourced directly from the Roblox catalog API
-- (catalog.roblox.com/v1/bundles/{id}/details) — these are the real
-- animation asset IDs, not catalog page IDs.
Animator.PRESETS = {
	{ name = "None",       id = nil          },
	{ name = "TOY",        id = "973771666"  }, -- bundle 43
	{ name = "Robot",      id = "619521748"  }, -- bundle 82
	{ name = "Superhero",  id = "619528125"  }, -- bundle 81
	{ name = "Zombie",     id = "619535834"  }, -- bundle 80
	{ name = "Levitation", id = "619542203"  }, -- bundle 79
	{ name = "Stylish",    id = "619511648"  }, -- bundle 83
	{ name = "Ninja",      id = "658832408"  }, -- bundle 75
	{ name = "Knight",     id = "734327140"  }, -- bundle 68
	{ name = "Mage",       id = "754637456"  }, -- bundle 63
	{ name = "Pirate",     id = "837024662"  }, -- bundle 55
}

function Animator.presetNames()
	local t = {}
	for _, p in ipairs(Animator.PRESETS) do t[#t + 1] = p.name end
	return t
end

-- Accepts bare number, "rbxassetid://...", or any string containing digits
local function parseId(raw)
	if not raw or raw == "" then return nil end
	local n = tostring(raw):match("%d+")
	return n and ("rbxassetid://" .. n) or nil
end

function Animator.new()
	return setmetatable({
		_track      = nil,
		_anim       = nil,
		_currentId  = nil,
		_animScript = nil,
	}, Animator)
end

-- ── Internal ──────────────────────────────────────────────────────────────────

function Animator:_disableAnimate(character)
	local s = character:FindFirstChild("Animate")
	if s then
		s.Disabled    = true
		self._animScript = s
	end
end

function Animator:_enableAnimate()
	if self._animScript then
		self._animScript.Disabled = false
		self._animScript = nil
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Animator:play(character, rawId)
	self:stop()

	local assetId = parseId(rawId)
	if not assetId then
		warn("[Animator] Invalid ID:", tostring(rawId))
		return
	end

	local humanoid    = character:FindFirstChildOfClass("Humanoid")
	local animatorObj = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animatorObj then
		warn("[Animator] No Animator on character")
		return
	end

	-- 1. Disable Animate LocalScript so it cannot override our track
	self:_disableAnimate(character)

	-- 2. Kill every active track immediately
	for _, t in ipairs(animatorObj:GetPlayingAnimationTracks()) do
		t:Stop(0)
	end

	-- 3. Load animation — wrap in pcall to catch synchronous errors
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId

	local ok, track = pcall(function()
		return animatorObj:LoadAnimation(anim)
	end)

	if not ok or not track then
		warn("[Animator] LoadAnimation error for", rawId, ":", tostring(track))
		anim:Destroy()
		self:_enableAnimate()   -- restore so character is not frozen
		return
	end

	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true
	track:Play(0)

	self._track     = track
	self._anim      = anim
	self._currentId = rawId

	-- 4. Async safety net: AnimationTrack.Length stays 0 when the asset
	--    fails to load from the CDN (wrong/restricted ID). After 2 s, if the
	--    track has no length, it loaded nothing — re-enable Animate so the
	--    character is not left as a statue.
	task.delay(2, function()
		if self._track ~= track then return end   -- animation already changed
		if track.Length == 0 then
			warn("[Animator] Animation has no length after 2s (bad ID?):", rawId)
			self:stop()
		end
	end)
end

function Animator:stop()
	if self._track then
		self._track:Stop(0)
		self._track:Destroy()
		self._track = nil
	end
	if self._anim then
		self._anim:Destroy()
		self._anim = nil
	end
	self:_enableAnimate()
	self._currentId = nil
end

function Animator:replayOn(character)
	if self._currentId then
		local id        = self._currentId
		self._currentId = nil
		self._animScript = nil
		self:play(character, id)
	end
end

function Animator:getCurrentId()
	return self._currentId
end

return Animator
