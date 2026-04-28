-- Animator.lua
-- Two-pronged animation replacement so changes are immediate and persistent:
--   1. Stops every currently-playing track (clears the slate).
--   2. Patches the character's Animate LocalScript so idle/walk/run
--      all use the selected animation — this is what makes it replicate.
--   3. Plays an Action4-priority track directly for instant visual effect.

local Animator = {}
Animator.__index = Animator

Animator.PRESETS = {
	{ name = "None",      id = nil           },
	{ name = "TOY",       id = "782841498"   },
	{ name = "Robot",     id = "313382498"   },
	{ name = "Ninja",     id = "656118852"   },
	{ name = "Superhero", id = "616072382"   },
	{ name = "Zombie",    id = "616163890"   },
	{ name = "Astronaut", id = "891836989"   },
	{ name = "Mage",      id = "707855543"   },
	{ name = "Knight",    id = "657564596"   },
	{ name = "Pirate",    id = "750711522"   },
	{ name = "Werewolf",  id = "1083216690"  },
}

function Animator.presetNames()
	local t = {}
	for _, p in ipairs(Animator.PRESETS) do t[#t + 1] = p.name end
	return t
end

-- Accepts: "782841498", "rbxassetid://782841498", any URL containing digits
local function parseId(raw)
	if not raw or raw == "" then return nil end
	local n = tostring(raw):match("%d+")
	return n and ("rbxassetid://" .. n) or nil
end

function Animator.new()
	return setmetatable({
		_track     = nil,
		_anim      = nil,
		_currentId = nil,
		_originals = {},   -- original AnimationId values keyed by Animation instance
	}, Animator)
end

-- ── Animate LocalScript patching ──────────────────────────────────────────────

function Animator:_patch(character, assetId)
	local animScript = character:FindFirstChild("Animate")
	if not animScript then return end

	for _, desc in ipairs(animScript:GetDescendants()) do
		if desc:IsA("Animation") then
			-- Save original only once per instance
			if not self._originals[desc] then
				self._originals[desc] = desc.AnimationId
			end
			desc.AnimationId = assetId
		end
	end
end

function Animator:_restore()
	for desc, id in pairs(self._originals) do
		-- Guard against instances that no longer exist after respawn
		local ok = pcall(function() desc.AnimationId = id end)
		if not ok then self._originals[desc] = nil end
	end
	self._originals = {}
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
		warn("[Animator] No Animator found on character")
		return
	end

	-- 1. Kill every currently-playing track with no fade delay
	for _, t in ipairs(animatorObj:GetPlayingAnimationTracks()) do
		t:Stop(0)
	end

	-- 2. Patch Animate LocalScript so the animation persists in all movement states
	self:_patch(character, assetId)

	-- 3. Play a direct Action4 track for immediate replication to other clients
	local anim = Instance.new("Animation")
	anim.AnimationId = assetId

	local track = animatorObj:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped   = true
	track:Play(0)   -- 0 = instant start, no crossfade

	self._track     = track
	self._anim      = anim
	self._currentId = rawId
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
	self._currentId = nil
	self:_restore()
end

function Animator:replayOn(character)
	if self._currentId then
		local id = self._currentId
		self._currentId = nil   -- clear so stop() doesn't try to restore stale refs
		self._originals = {}
		self:play(character, id)
	end
end

function Animator:getCurrentId()
	return self._currentId
end

return Animator
