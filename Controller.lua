-- Controller.lua (ModuleScript)
-- Flight physics via LinearVelocity + AlignOrientation.
-- All math is camera-relative; vertical input is world-space.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NORMAL_SPEED    = 50
local BOOST_SPEED     = 120
local VERTICAL_SPEED  = 30
local ACCELERATION    = 8   -- lerp factor (units/s feel)

local Controller = {}
Controller.__index = Controller

function Controller.new()
	local self = setmetatable({}, Controller)
	self.active       = false
	self.boosting     = false
	self.speed        = 0
	self._inputVec    = Vector3.zero
	self._vertInput   = 0
	self._connection  = nil
	self._lv          = nil   -- LinearVelocity
	self._ao          = nil   -- AlignOrientation
	self._attach      = nil   -- Attachment
	return self
end

-- ── Constraint lifecycle ──────────────────────────────────────────────────────

function Controller:_attach_create(rootPart)
	local a = Instance.new("Attachment")
	a.Name   = "FlightAttachment"
	a.Parent = rootPart
	self._attach = a

	local lv = Instance.new("LinearVelocity")
	lv.Name                  = "FlightLV"
	lv.Attachment0           = a
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo            = Enum.ActuatorRelativeTo.World
	lv.MaxForce              = math.huge
	lv.VectorVelocity        = Vector3.zero
	lv.Parent                = rootPart
	self._lv = lv

	local ao = Instance.new("AlignOrientation")
	ao.Name                  = "FlightAO"
	ao.Attachment0           = a
	ao.Mode                  = Enum.OrientationAlignmentMode.OneAttachment
	ao.MaxTorque             = math.huge
	ao.MaxAngularVelocity    = math.huge
	ao.Responsiveness        = 50
	ao.CFrame                = rootPart.CFrame
	ao.Parent                = rootPart
	self._ao = ao
end

function Controller:_attach_destroy()
	if self._lv     then self._lv:Destroy();     self._lv     = nil end
	if self._ao     then self._ao:Destroy();     self._ao     = nil end
	if self._attach then self._attach:Destroy(); self._attach = nil end
end

-- ── Camera-relative horizontal velocity ──────────────────────────────────────

local function camRelativeVelocity(inputVec, camera, speed)
	local look  = camera.CFrame.LookVector
	local right = camera.CFrame.RightVector
	local fwd   = Vector3.new(look.X,  0, look.Z).Unit
	local rgt   = Vector3.new(right.X, 0, right.Z).Unit
	-- inputVec.Z < 0 = W (forward), inputVec.X > 0 = D (right)
	return (fwd * -inputVec.Z + rgt * inputVec.X) * speed
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Controller:enable(character)
	if self.active then return end

	local root     = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end

	humanoid.PlatformStand             = true
	root.AssemblyLinearVelocity        = Vector3.zero
	root.AssemblyAngularVelocity       = Vector3.zero

	self:_attach_create(root)
	self.active = true

	local camera          = Workspace.CurrentCamera
	local smoothVelocity  = Vector3.zero

	self._connection = RunService.Heartbeat:Connect(function(dt)
		if not self.active then return end
		if not character.Parent then self:disable(character); return end

		local targetSpeed = self.boosting and BOOST_SPEED or NORMAL_SPEED
		local horizontal  = camRelativeVelocity(self._inputVec, camera, targetSpeed)
		local vertical    = Vector3.new(0, self._vertInput * VERTICAL_SPEED, 0)
		local target      = horizontal + vertical

		-- Exponential lerp for smooth acceleration/deceleration
		local t = 1 - math.exp(-ACCELERATION * dt)
		smoothVelocity       = smoothVelocity:Lerp(target, t)
		self._lv.VectorVelocity = smoothVelocity

		-- Face movement direction (horizontal only, no tilt)
		if horizontal.Magnitude > 0.5 then
			self._ao.CFrame = CFrame.lookAt(root.Position, root.Position + horizontal.Unit)
		end

		self.speed = smoothVelocity.Magnitude
	end)
end

function Controller:disable(character)
	if not self.active then return end
	self.active = false
	self.speed  = 0

	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end

	self:_attach_destroy()

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then humanoid.PlatformStand = false end
end

-- Called each frame from Main with the current input state
function Controller:setInput(inputVec, vertInput)
	self._inputVec  = inputVec
	self._vertInput = vertInput
end

function Controller:setBoosting(state)
	self.boosting = state
end

function Controller:isActive()
	return self.active
end

function Controller:getSpeed()
	return self.speed
end

return Controller
