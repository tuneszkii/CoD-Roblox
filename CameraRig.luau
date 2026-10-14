-- Scriptable first-person camera: mouse look, pattern recoil, shake, bob, strafe/slide roll, FOV.
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Config = require(script.Parent.Config)
local Spring = require(script.Parent.Spring)
local Settings = require(script.Parent.Settings)
local InputMap = require(script.Parent.InputMap)
local C = Config.Camera

local CameraRig = {}
CameraRig.__index = CameraRig

function CameraRig.new()
	local self = setmetatable({}, CameraRig)
	self.Camera = workspace.CurrentCamera
	self.Active = false
	self.Yaw, self.Pitch = 0, 0
	self.Recoil, self.RecoilTarget, self.LastShot = Vector2.zero, Vector2.zero, 0 -- degrees (pitch, yaw)
	self.Shake = Spring.new(16, 0.5) -- euler kicks in radians
	self.Roll, self.BobT = 0, 0
	self.Fov = C.HipFov
	self.CFrame = CFrame.new()
	self.MouseDelta = Vector2.zero
	self.Parts = {}
	self.PeekFrac = 1 -- how much of the peek the wall in front of the camera allows (1 = all of it)
	self.ShowBody = false -- CineCam shots that look at your operator (end of match) show the body even in first person
	self.OrbitOn, self.Orbit = false, 0 -- emote camera: swings round in front of your character (EmoteClient sets OrbitOn)
	return self
end

function CameraRig:SetCharacter(char)
	self.Root = char:WaitForChild("HumanoidRootPart")
	InputMap.SetCharacter(char)
	local look = self.Root.CFrame.LookVector
	self.Yaw, self.Pitch = math.atan2(-look.X, -look.Z), 0
	self.Recoil, self.RecoilTarget = Vector2.zero, Vector2.zero
	self.Parts = {}
	self.PeekFrac = 1
	self.PeekParams = RaycastParams.new() -- the lean stops short of walls so the camera never clips through a corner
	self.PeekParams.FilterType = Enum.RaycastFilterType.Exclude
	self.PeekParams.FilterDescendantsInstances = { char }
	self.PeekParams.RespectCanCollide = true
	local function add(d) if d:IsA("BasePart") then table.insert(self.Parts, d) end end
	for _, d in char:GetDescendants() do add(d) end
	char.DescendantAdded:Connect(add)
	self.Camera.CameraType = Enum.CameraType.Scriptable
	UIS.MouseIconEnabled = false
	self.Active = true
end

-- re-read the facing of the character (it may have been moved to a spawn point after SetCharacter)
function CameraRig:Realign()
	if not self.Root then return end
	local look = self.Root.CFrame.LookVector
	self.Yaw, self.Pitch = math.atan2(-look.X, -look.Z), 0
end

function CameraRig:Release(humanoid)
	self.Active = false
	self.Camera.CameraType = Enum.CameraType.Custom
	if humanoid then self.Camera.CameraSubject = humanoid end
	UIS.MouseBehavior = Enum.MouseBehavior.Default
	UIS.MouseIconEnabled = true
end

-- degrees; pitch up, yaw right
function CameraRig:AddRecoil(pitch, yaw)
	self.RecoilTarget += Vector2.new(pitch, yaw)
	self.LastShot = os.clock()
	self.Shake:Impulse(Vector3.new(0.25, (math.random() - 0.5) * 0.15, (math.random() - 0.5) * 0.2))
end

function CameraRig:AddShake(v) self.Shake:Impulse(v) end

-- Flinch: a quick head snap through the Shake spring (so it recovers on its own and obeys the "Camera shake" setting).
--   def      = Config.Flinch.Hit or Config.Flinch.Suppress
--   strength = 1 is a full-size kick for that def
--   side     = -1 / 1: which way the head turns (away from where the shot came from); 0 = random
-- Pitch kicks the view UP-and-back-down (negative X = nose up here, matching the landing shake); yaw and roll go to `side`.
function CameraRig:Flinch(def, strength, side, ads)
	local F = Config.Flinch
	local k = strength * (1 - (1 - F.AdsScale) * math.clamp(ads or 0, 0, 1))
	if side == nil or side == 0 then side = math.random() < 0.5 and -1 or 1 end
	local jitter = 0.8 + math.random() * 0.4
	self.Shake:Impulse(Vector3.new(-def.Pitch * k * jitter, side * def.Yaw * k, side * def.Roll * k) * 14)
end

function CameraRig:Update(dt, movement, weapons)
	if not self.Active then return end
	local cam = self.Camera
	local hip = Settings.Get("Graphics.Fov")

	local delta = Vector2.zero
	if not GuiService.MenuIsOpen and not self.Suspended then
		UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
		delta = UIS:GetMouseDelta()
		if delta.Magnitude > 200 then delta = Vector2.zero end
	end
	self.MouseDelta = delta

	-- FOV (ADS zoom + sprint kick)
	local ads = weapons.AdsEased or 0
	local adsFov = weapons.Cfg and weapons.Cfg.AdsFov or hip
	local fov = hip + (adsFov - hip) * ads
	fov += movement.Alpha.Sprint * C.SprintFov + movement.Alpha.Tac * C.TacFov
	self.Fov += (fov - self.Fov) * (1 - math.exp(-14 * dt))

	-- look: mouse, gamepad stick and touch drag all come from InputMap (sensitivity scales with zoom)
	local zoom = math.tan(math.rad(self.Fov / 2)) / math.tan(math.rad(hip / 2))
	local look = InputMap.GetLook(dt, zoom, ads > 0.5, delta)
	self.Yaw = movement:ClampYaw(self.Yaw - look.X) -- on a ladder the view is limited to 180 degrees around it
	self.Pitch = math.clamp(self.Pitch - look.Y, -1.5, 1.5)

	-- recoil: target recovers after a delay, current chases target quickly
	if os.clock() - self.LastShot > C.RecoilDelay then
		self.RecoilTarget *= math.exp(-C.RecoilRecover * dt)
	end
	self.Recoil = self.Recoil:Lerp(self.RecoilTarget, 1 - math.exp(-30 * dt))

	-- strafe / slide roll
	local lv = CFrame.Angles(0, self.Yaw, 0):VectorToObjectSpace(movement.Velocity)
	local rollT = -math.clamp(lv.X, -20, 20) * 0.0016 + movement.Alpha.Slide * math.rad(-3) + movement.Alpha.Down * math.rad(7)
	self.Roll += (rollT - self.Roll) * (1 - math.exp(-8 * dt))

	-- head bob
	local amp = movement.Grounded and math.clamp(movement.Speed / 14, 0, 1.4) or 0
	self.BobT += dt * movement.Speed * 0.55
	local adsK = 1 - 0.9 * ads
	local bobK = Settings.Get("Graphics.HeadBob") / 100
	local bobY = math.sin(self.BobT * 2) * 0.03 * amp * adsK * bobK
	local bobRoll = math.sin(self.BobT) * 0.004 * amp * adsK * bobK

	local LC = Config.Movement.Ladder
	bobRoll += math.sin(movement.LadderPhase * LC.SwayFreq * 2 * math.pi) * math.rad(LC.SwayRoll) * movement.Alpha.Ladder -- hand over hand sway while climbing
	local sh = self.Shake:Update(dt) * (Settings.Get("Graphics.CameraShake") / 100)
	local pitch = math.clamp(self.Pitch + math.rad(self.Recoil.X), -1.55, 1.55)
	local yaw = self.Yaw - math.rad(self.Recoil.Y)
	if weapons.Scoped then -- scope sway; holding breath freezes it
		local t = os.clock()
		local amp = weapons.HoldingBreath and 0.02 or C.ScopeSway
		pitch += math.rad(math.cos(t * 1.9) * amp * 0.8 * weapons.AdsEased)
		yaw += math.rad(math.sin(t * 1.3) * amp * weapons.AdsEased)
	end
	local pos = self.Root.Position + Vector3.new(0, movement.EyeHeight + movement.RootDrop + bobY, 0) -- RootDrop: the collider sinks the root in low stances

	-- corner peek (Q / E while aiming): lean about the hip, camera swings out sideways and rolls into the lean.
	-- Positive = right. The roll sign matches the strafe roll above (negative roll = tilts right).
	local leanRoll = 0
	local peek = weapons.PeekAmt or 0
	local P = C.Peek
	if math.abs(peek) > 0.001 then
		local right = CFrame.fromOrientation(0, yaw, 0).RightVector
		local want = P.Lever * math.sin(P.Angle * math.abs(peek)) -- sideways reach with a free lean
		local reach = want + P.Clearance
		local hit = workspace:Raycast(pos, right * (peek < 0 and -reach or reach), self.PeekParams)
		local frac = hit and math.clamp((hit.Distance - P.Clearance) / math.max(want, 0.01), 0, 1) or 1
		self.PeekFrac += (frac - self.PeekFrac) * (1 - math.exp(-(frac < self.PeekFrac and 40 or 14) * dt)) -- ease back out slowly, slam in fast
		local angle = P.Angle * peek * self.PeekFrac
		pos += right * (P.Lever * math.sin(angle)) - Vector3.new(0, P.Lever * (1 - math.cos(angle)), 0)
		leanRoll = -angle
	else
		self.PeekFrac = 1
	end

	local cf = CFrame.new(pos) * CFrame.fromOrientation(pitch, yaw, 0)
		* CFrame.fromOrientation(sh.X, sh.Y, sh.Z + self.Roll + bobRoll + leanRoll)
	self.CFrame = cf
	self.Orbit += ((self.OrbitOn and 1 or 0) - self.Orbit) * (1 - math.exp(-9 * dt))
	if self.Orbit > 0.002 then
		local ease = self.Orbit * self.Orbit * (3 - 2 * self.Orbit)
		local focus = self.Root.Position + Vector3.new(0, 0.6, 0)
		local front = CFrame.fromOrientation(0, yaw, 0)
		local camPos = focus + front.LookVector * 7.5 + front.RightVector * 2.2 + Vector3.new(0, 1.4, 0)
		cf = cf:Lerp(CFrame.lookAt(camPos, focus + Vector3.new(0, 0.4, 0)), ease)
	end
	cam.CFrame = cf
	cam.FieldOfView = self.Fov

	local hide = self.Orbit < 0.5 and not self.ShowBody
	for _, p in self.Parts do p.LocalTransparencyModifier = hide and 1 or 0 end -- hide own body in first person
end

return CameraRig
