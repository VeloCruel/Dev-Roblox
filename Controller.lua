-- Controller.lua
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local NORMAL_SPEED   = 50
local BOOST_SPEED    = 120
local VERTICAL_SPEED = 30
local ACCELERATION   = 8

local Controller = {}
Controller.__index = Controller

function Controller.new()
	return setmetatable({
		active      = false,
		boosting    = false,
		speed       = 0,
		_inputVec   = Vector3.zero,
		_vertInput  = 0,
		_connection = nil,
		_lv         = nil,
		_ao         = nil,
		_attach     = nil,
	}, Controller)
end

-- ── Constraints ───────────────────────────────────────────────────────────────

function Controller:_attach_create(rootPart)
	local a = Instance.new("Attachment")
	a.Name   = "FlightAttachment"
	a.Parent = rootPart
	self._attach = a

	local lv = Instance.new("LinearVelocity")
	lv.Name                   = "FlightLV"
	lv.Attachment0            = a
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.RelativeTo             = Enum.ActuatorRelativeTo.World
	lv.MaxForce               = math.huge
	lv.VectorVelocity         = Vector3.zero
	lv.Parent                 = rootPart
	self._lv = lv

	local ao = Instance.new("AlignOrientation")
	ao.Name               = "FlightAO"
	ao.Attachment0        = a
	ao.Mode               = Enum.OrientationAlignmentMode.OneAttachment
	ao.MaxTorque          = math.huge
	ao.MaxAngularVelocity = math.huge
	ao.Responsiveness     = 50
	ao.CFrame             = rootPart.CFrame
	ao.Parent             = rootPart
	self._ao = ao
end

function Controller:_attach_destroy()
	if self._lv     then self._lv:Destroy();     self._lv     = nil end
	if self._ao     then self._ao:Destroy();     self._ao     = nil end
	if self._attach then self._attach:Destroy(); self._attach = nil end
end

-- ── Movement math ─────────────────────────────────────────────────────────────

local function cameraVelocity(inputVec, camera, speed)
	-- W/S follow the camera's full 3D pitch (fly where you aim).
	-- A/D strafe stays flat so sideways movement feels grounded.
	local fwd = camera.CFrame.LookVector
	local rgt = Vector3.new(camera.CFrame.RightVector.X, 0, camera.CFrame.RightVector.Z).Unit
	return (fwd * -inputVec.Z + rgt * inputVec.X) * speed
end

-- ── Public API ────────────────────────────────────────────────────────────────

function Controller:enable(character)
	if self.active then return end

	local root     = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end

	humanoid.PlatformStand        = true
	root.AssemblyLinearVelocity   = Vector3.zero
	root.AssemblyAngularVelocity  = Vector3.zero

	self:_attach_create(root)
	self.active = true

	local camera         = Workspace.CurrentCamera
	local smoothVelocity = Vector3.zero

	self._connection = RunService.Heartbeat:Connect(function(dt)
		if not self.active then return end
		if not character.Parent then self:disable(character); return end

		local targetSpeed = self.boosting and BOOST_SPEED or NORMAL_SPEED
		local moveVec     = cameraVelocity(self._inputVec, camera, targetSpeed)
		local addVert     = Vector3.new(0, self._vertInput * VERTICAL_SPEED, 0)
		local target      = moveVec + addVert

		local t = 1 - math.exp(-ACCELERATION * dt)
		smoothVelocity          = smoothVelocity:Lerp(target, t)
		self._lv.VectorVelocity = smoothVelocity

		-- Orient toward actual velocity direction, lean forward -45°.
		-- Negative angle: UpVector tilts forward → character leans toward target.
		if smoothVelocity.Magnitude > 0.5 then
			local lookGoal = CFrame.lookAt(root.Position, root.Position + smoothVelocity.Unit)
			self._ao.CFrame = lookGoal * CFrame.Angles(math.rad(-45), 0, 0)
		else
			-- Hovering: return to upright, preserve last horizontal facing.
			local flatLook = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if flatLook.Magnitude > 0.01 then
				self._ao.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
			end
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

function Controller:setInput(inputVec, vertInput)
	self._inputVec  = inputVec
	self._vertInput = vertInput
end

function Controller:setBoosting(state) self.boosting = state end
function Controller:isActive()         return self.active    end
function Controller:getSpeed()         return self.speed     end

return Controller
