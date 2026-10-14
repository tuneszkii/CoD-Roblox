-- Warzone / MW2019-style movement: walk, crouch, prone, sprint, tactical sprint (double-tap), slide, slide-hop, slide cancel,
-- dive to prone and drop shot, plus air strafing and mantling / vaulting.
--   * Slide: Crouch while sprinting. Press Crouch again (after Config.SlideCancelDelay) to cancel it into a crouch; Prone ends it into a prone skid.
--   * Prone: Prone key, or hold Crouch for Config.ProneHoldTime. Jump / Sprint stand you up, Crouch drops you to a crouch.
--   * Dive: Prone while sprinting. Short hop, lands prone and skids.
--   * Drop shot: going prone while aiming / firing (self.Engaged, set by the weapon controller). The gun stays up and the eye drops fast;
--     WeaponController tightens spread while self.DropShot > 0.
--   * Air strafe: in the air your own velocity is accelerated Quake-style (Config.AirStrafe) instead of the Humanoid's air control. Strafe + turn
--     the camera the same way to gain speed; holding Jump while landing keeps it (bunny hop).
--   * Mantle / vault: Jump (or hold it) facing a ledge. Ledges are climbed (Config.Mantle), low thin obstacles are hopped over without stopping
--     when moving. The body is driven along a path with collisions off for the duration; the destination is checked for room first.
--   * Ladder: stand near a tagged ladder (Config.Movement.Ladder), face it and press Interact. W / S (stick up / down) climb, Jump lets go,
--     aiming or firing (self.Engaged) pauses the climb while WeaponController draws the pistol. The view is limited to 180 degrees around the ladder.
--   * Collision: crouch / slide / prone / dive swap the standing R6 body for one smaller box (Config.Movement.Collider), so you fit under
--     low geometry. Standing back up is refused while something is in the way (_resolveHeadroom) and happens as soon as there is room.
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Config = require(script.Parent.Config).Movement
local AS, MC, LC = Config.AirStrafe, Config.Mantle, Config.Ladder
local Settings = require(script.Parent.Settings)
local InputMap = require(script.Parent.InputMap)
local player = Players.LocalPlayer

local Movement = {}
Movement.__index = Movement

local function approach(cur, target, step)
	if cur < target then return math.min(cur + step, target) end
	return math.max(cur - step, target)
end
local function smooth(cur, target, rate, dt)
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

function Movement.new()
	local self = setmetatable({}, Movement)
	self.Active = false
	self.State = "Idle" -- Idle Walk Crouch Prone Sprint TacSprint Slide Air Mantle Vault Dive Downed
	self.Speed, self.Velocity, self.Grounded, self.AirTime = 0, Vector3.zero, true, 0
	self.EyeHeight = Config.Eye.Stand
	self.Alpha = { Sprint = 0, Tac = 0, Slide = 0, Crouch = 0, Prone = 0, Down = 0, Mantle = 0, Ladder = 0 } -- smoothed blend values for animation
	self.IsSprinting, self.SprintBlocked, self.WantsSprint = false, false, false
	self.Crouched, self.Tac, self.TacTimer, self.TacArmedUntil, self.LastShiftTap = false, false, 0, 0, 0
	self.Sliding, self.SlideSpeed, self.SlideDir, self.SlideCooldown, self.SlideTime = false, 0, Vector3.zero, 0, 0
	self.Prone, self.ProneSlide, self.DropShot, self.Engaged = false, 0, 0, false -- Engaged = aiming or firing (set by WeaponController)
	self.Diving, self.DiveAir, self.DiveTime, self.DivePending, self.DiveCooldown = false, false, 0, false, 0
	self.CrouchHeldAt, self.JumpSuppress = nil, false
	self.Applied, self.PendingWant, self.RootDrop = "Stand", nil, 0 -- collider in use, taller stance wanted but blocked, smoothed root drop (camera)
	self.Carry, self.CurWalk, self.LastVy = 0, Config.WalkSpeed, 0
	self.GlobalMult, self.TacTimeMult = 1, 1 -- set by perks / stim / stun
	self.Downed = false -- set by the weapon controller when the server downs the player
	self.Mantle, self.MantleCooldown, self.JumpBuffer = nil, 0, 0 -- Mantle = the path being followed (mantle or vault), nil when not climbing
	self.AirAcc, self.BhopT, self.GlideT = 0, 0, 0 -- air-strafe step accumulator, post-landing no-brake window, post-vault reduced-brake window
	self.Ladder, self.LadderCooldown, self.LadderCand, self.LadderPrompt, self.LadderScanT, self.LadderPhase = nil, 0, nil, false, 0, 0
	self.LadderBlocked, self.LadderHold, self.LastYaw = false, false, 0 -- set by WeaponController: hands busy / gun in use (pauses the climb)
	self.OnLadder, self.OnLadderEnd = nil, nil -- callbacks
	self.OnLand, self.OnSlide, self.OnDive, self.OnMantle, self.OnMantleEnd = nil, nil, nil, nil, nil -- callbacks
	self:_bindInput()
	return self
end

function Movement:SetCharacter(char)
	self.Char = char
	self.Humanoid = char:WaitForChild("Humanoid")
	self.Root = char:WaitForChild("HumanoidRootPart")
	self.Humanoid.AutoRotate = false
	self.Humanoid.UseJumpPower = false
	self.Humanoid.JumpHeight = Config.JumpHeight

	local att = Instance.new("Attachment")
	att.Name = "FPSAlign"
	att.Parent = self.Root
	local align = Instance.new("AlignOrientation")
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.MaxTorque = math.huge
	align.Responsiveness = 200
	align.RigidityEnabled = false
	align.Parent = self.Root
	self.Align = align

	self.RayParams = RaycastParams.new()
	self.RayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.RayParams.FilterDescendantsInstances = { char }

	-- remember the standing body so _applyCollider can swap to a lowered box and back
	self.StandSize, self.StandHip = self.Root.Size, self.Humanoid.HipHeight
	self.PartCollide = {}
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then self.PartCollide[d] = d.CanCollide end
	end
	local leg = char:FindFirstChild("Left Leg")
	self.LegHeight = leg and leg.Size.Y or Config.Capsule.LegHeight
	self.Applied, self.PendingWant, self.RootDrop = "Stand", nil, 0

	local PlayerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
	self.Controls = require(PlayerModule):GetControls()
	self.Controls:Disable() -- InputMap supplies movement + jump for keyboard, gamepad and touch

	self.Sliding, self.IsSprinting, self.Tac, self.Crouched = false, false, false, false
	self.Carry, self.CurWalk, self.SlideCooldown = 0, Config.WalkSpeed, 0
	self.Prone, self.ProneSlide, self.DropShot, self.Diving, self.DiveAir, self.DivePending, self.DiveCooldown = false, 0, 0, false, false, false, 0
	self.CrouchHeldAt, self.JumpSuppress = nil, false
	self.Mantle, self.MantleCooldown, self.JumpBuffer, self.AirAcc, self.BhopT, self.GlideT = nil, 0, 0, 0, 0, 0
	self.Ladder, self.LadderCooldown, self.LadderCand, self.LadderPrompt = nil, 0, nil, false
	self.Active = true
end

function Movement:_bindInput()
	InputMap.OnBegan("Sprint", function()
		if not self.Active then return end
		local now = os.clock()
		if self.Prone then self.Prone = false end -- sprint stands you up
		if now - self.LastShiftTap < Config.TacDoubleTap then self.TacArmedUntil = now + 0.6 end
		self.LastShiftTap = now
		if Settings.Get("Gameplay.SprintMode") == "Toggle" then self.WantsSprint = not self.WantsSprint else self.WantsSprint = true end
	end)
	InputMap.OnEnded("Sprint", function()
		if Settings.Get("Gameplay.SprintMode") ~= "Toggle" then self.WantsSprint = false end
	end)
	InputMap.OnBegan("Crouch", function()
		if not self.Active then return end
		self.CrouchHeldAt = nil
		if self.Sliding then self:_cancelSlide(); return end -- a second press while sliding cancels the slide (both Toggle and Hold modes)
		local wasProne = self.Prone
		if Settings.Get("Gameplay.CrouchMode") == "Hold" then
			if not self.Crouched or wasProne then self:_crouchPressed() end
		else
			self:_crouchPressed()
		end
		-- holding Crouch for ProneHoldTime goes prone (this is also how a controller gets prone: there is no spare button)
		if self.Crouched and not wasProne and not self.Sliding and not self.Downed then self.CrouchHeldAt = os.clock() end
	end)
	InputMap.OnEnded("Crouch", function()
		self.CrouchHeldAt = nil
		if Settings.Get("Gameplay.CrouchMode") == "Hold" and self.Crouched and not self.Sliding then self.Crouched = false end
	end)
	InputMap.OnBegan("Prone", function()
		if not self.Active or self.Downed then return end
		self:_pronePressed()
	end)
	InputMap.OnBegan("Jump", function()
		if not self.Active or self.Diving then return end
		if self.Ladder then self:_endLadder("Jump") return end -- jumping lets go of the ladder and you fall
		self.JumpBuffer = MC.Buffer -- a press a hair before the ledge still mantles
		if self.Mantle then return end
		if self.Sliding then self:_endSlide(true)
		elseif self.Prone then self.Prone, self.JumpSuppress = false, true -- jump from prone = stand up (no hop)
		else self.Crouched = false end
	end)
	InputMap.OnEnded("Jump", function() self.JumpSuppress = false end)
	InputMap.OnBegan("Interact", function() -- grab the ladder you are being offered
		if not self.Active or self.Ladder or self.Mantle or self.Downed or self.Diving or self.Sliding or self.Prone or self.Engaged or self.LadderBlocked
			or self.Applied ~= "Stand" or self.LadderCooldown > 0 then return end
		if self.InteractTaken then return end -- a downed player is in reach: Interact means revive / finish
		local cand = self:_scanLadder(self.LastYaw)
		if cand then self:_startLadder(cand) end
	end)
end

function Movement:_crouchPressed()
	self.PendingWant = nil -- a fresh press is a new decision
	if self.Sliding then return end
	if self.Prone then -- Crouch from prone: up onto your knees
		self.Prone, self.ProneSlide = false, 0
		self.Crouched = true
		return
	end
	local canSlide = self.IsSprinting and self.Grounded and self.Speed >= Config.SlideMinSpeed and self.SlideCooldown <= 0
	if canSlide then self:_startSlide() else self.Crouched = not self.Crouched end
end

function Movement:_startSlide()
	local v = Vector3.new(self.Velocity.X, 0, self.Velocity.Z)
	local look = self.Root.CFrame.LookVector
	self.SlideDir = v.Magnitude > 0.1 and v.Unit or Vector3.new(look.X, 0, look.Z).Unit
	self.SlideSpeed = math.min(math.max(v.Magnitude * Config.SlideBoost, Config.SlideSpeed), Config.SlideMax)
	self.Sliding, self.Crouched, self.Tac, self.IsSprinting = true, true, false, false
	self.SlideTime, self.Prone = 0, false
	if self.OnSlide then self.OnSlide() end
end

-- second crouch press while sliding: drop out of the slide into a crouch (momentum is not kept, unlike a slide-hop)
function Movement:_cancelSlide()
	if not self.Sliding or self.SlideTime < Config.SlideCancelDelay then return end
	self:_endSlide(false)
	self.Crouched = true
	self.CurWalk = math.min(self.CurWalk, Config.WalkSpeed) -- skip the long decel from slide speed so the cancel feels instant
end

function Movement:_pronePressed()
	self.PendingWant = nil
	if self.Prone then -- Prone again: stand up
		self.Prone, self.ProneSlide, self.Crouched = false, 0, false
		return
	end
	if self.Sliding then -- slide into prone: keep some of the slide as a skid
		local skid = math.min(self.SlideSpeed, Config.ProneSlideSpeed)
		self:_endSlide(false)
		self:_goProne(skid)
		return
	end
	local canDive = self.IsSprinting and self.Grounded and self.Speed >= Config.DiveMinSpeed and self.DiveCooldown <= 0
	if canDive then self:_dive() elseif self.Grounded then self:_goProne() end
end

-- skid: optional forward skid speed (dive landing / slide to prone). Drop shot = going prone while aiming or firing.
function Movement:_goProne(skid)
	if self.Downed then return end
	local dropShot = self.Engaged and not self.Diving and not self.Prone
	self.Prone, self.Crouched, self.IsSprinting, self.Tac = true, false, false, false
	self.CrouchHeldAt = nil
	if Settings.Get("Gameplay.SprintMode") == "Toggle" then self.WantsSprint = false end
	self.ProneSlide = skid or 0
	if dropShot then self.DropShot = Config.DropShotTime end
end

function Movement:_dive()
	local v = Vector3.new(self.Velocity.X, 0, self.Velocity.Z)
	local look = self.Root.CFrame.LookVector
	self.SlideDir = v.Magnitude > 0.1 and v.Unit or Vector3.new(look.X, 0, look.Z).Unit
	self.Diving, self.DiveAir, self.DiveTime, self.DivePending = true, false, 0, true -- before _goProne so a dive never counts as a drop shot
	self:_goProne()
	self.DiveCooldown = Config.DiveCooldown
	if self.OnDive then self.OnDive() end
end

function Movement:_endSlide(jumped)
	if not self.Sliding then return end
	self.Sliding = false
	self.SlideCooldown = Config.SlideCooldown
	if Settings.Get("Gameplay.CrouchMode") == "Hold" and not InputMap.IsDown("Crouch") then self.Crouched = false end
	if jumped then
		self.Crouched = false
		self.Carry = self.SlideSpeed * 0.9 -- slide-hop keeps momentum
	end
end

function Movement:_floorNormal()
	local r = workspace:Raycast(self.Root.Position, Vector3.new(0, -6, 0), self.RayParams)
	return r and r.Normal or Vector3.yAxis
end

-- ---------------------------------------------------------------- collision capsule
local COL = Config.Collider
local GROW = { "Stand", "Crouch", "Prone" } -- tall to short: what a blocked stance falls back through

-- the stance the intent flags ask for
function Movement:_wantedCollider()
	if self.Downed then return "Downed" end
	if self.Sliding then return "Slide" end
	if self.Diving then return "Dive" end
	if self.Prone then return "Prone" end
	if self.Crouched then return "Crouch" end
	return "Stand"
end

-- Is there room for collider `name` standing with its feet at `feet` (yaw = box orientation)? Players' own bodies do not count (nobody pins you down).
function Movement:_boxFree(feet, yaw, name)
	local col = COL[name]
	local ignore = { self.Char }
	for _, plr in Players:GetPlayers() do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local bottom, top = feet.Y + 0.15, feet.Y + col.Height - 0.05 -- skip the floor itself, stay just under the collider's top
	local cf = CFrame.new(feet.X, (bottom + top) / 2, feet.Z) * CFrame.Angles(0, yaw, 0)
	local size = Vector3.new(col.Size.X - 0.1, top - bottom, col.Size.Z - 0.1)
	return #workspace:GetPartBoundsInBox(cf, size, params) == 0
end

-- Is there room for collider `name` where the character is now?
function Movement:_fits(name)
	local cur = COL[self.Applied]
	local pos = self.Root.Position
	local _, yaw = self.Root.CFrame:ToEulerAnglesYXZ()
	return self:_boxFree(Vector3.new(pos.X, pos.Y - cur.RootY, pos.Z), yaw, name)
end

-- make the intent flags describe collider `name`
function Movement:_setFlagsFor(name)
	if name == "Prone" then
		self.Prone, self.Crouched, self.IsSprinting, self.Tac = true, false, false, false
	elseif name == "Crouch" then
		self.Prone, self.Crouched, self.IsSprinting, self.Tac = false, true, false, false
	elseif name == "Stand" then
		self.Prone, self.Crouched = false, false
	end
end

-- Growing taller (stand up from prone / crouch, end a slide, get revived) only happens if it fits. Otherwise the tallest stance that does
-- fit is kept (stand -> crouch -> prone) and the wish is remembered, so you rise by yourself once you are out from under the low part.
function Movement:_resolveHeadroom()
	local want = self:_wantedCollider()
	if self.PendingWant then
		if COL[want].Height < COL[self.Applied].Height - 0.01 then self.PendingWant = nil -- the player went lower: forget the old wish
		else want = self.PendingWant end
	end
	local cur = COL[self.Applied]
	if COL[want].Height <= cur.Height + 0.01 or self.AirTime > 0.1 then return end -- not growing (or not on the floor to measure from)

	local wantH = COL[want].Height
	local result = "Prone" -- nothing else fits: lowest stance
	for _, name in GROW do
		if COL[name].Height <= wantH + 0.01 and self:_fits(name) then
			result = name
			break
		end
	end
	self:_setFlagsFor(result)
	self.PendingWant = (result ~= want) and want or nil
end

-- Swap the physical body. Standing = default R6 (torso, head and limbs collide). Anything lower = only the HumanoidRootPart, resized,
-- with HipHeight lowered by the leg length the Humanoid adds on top, so the box rests on the floor.
function Movement:_applyCollider(name)
	if name == self.Applied then return end
	local root, hum = self.Root, self.Humanoid
	self.Applied = name
	if name == "Stand" then
		root.Size, hum.HipHeight = self.StandSize, self.StandHip
		for part, canCollide in self.PartCollide do
			if part.Parent then part.CanCollide = canCollide end
		end
	else
		root.Size, hum.HipHeight = COL[name].Size, self.StandHip - self.LegHeight
		for part in self.PartCollide do
			if part.Parent then part.CanCollide = false end
		end
		root.CanCollide = true
	end
end

-- ---------------------------------------------------------------- mantle / vault
local STAND_ROOT_Y = Config.Capsule.StandRootY
local HEIGHTS = { 5.2, 4.0, 2.8, 1.6, 0.5 } -- wall probes, feet-relative, highest first (the first one that leads to a usable ledge wins)

function Movement:_worldParams()
	local ignore = { self.Char }
	for _, plr in Players:GetPlayers() do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = ignore
	p.RespectCanCollide = true
	return p
end

local function rootAt(feet) return feet + Vector3.new(0, STAND_ROOT_Y, 0) end

-- try to turn the wall hit into a vault or a mantle. feetY = current feet height, face = point on the wall face, dir = flat direction into the wall
function Movement:_evalLedge(params, yaw, feetY, hit, dir, entrySpeed)
	local face = hit.Position
	-- top surface: a ray down just inside the face, from above the highest ledge that could still be reached
	local startY = feetY + MC.MaxHeight + 1
	local p = face + dir * 0.2
	local top = workspace:Raycast(Vector3.new(p.X, startY, p.Z), Vector3.new(0, -(startY - (feetY + MC.MinHeight - 0.5)), 0), params)
	if not top or top.Normal.Y < 0.7 then return nil end
	local topY = top.Position.Y
	local h = topY - feetY
	if h < MC.MinHeight or h > MC.MaxHeight then return nil end
	-- the lip, looking into the wall: this is all the pose code (ClimbPose.luau) needs to plant hands and feet on the ledge
	local lip = Vector3.new(face.X, topY, face.Z)
	local ledgeCF = CFrame.lookAt(lip, lip + dir)

	-- vault: a low obstacle that ends within VaultMaxDepth, with floor and room on the far side, taken while moving toward it
	if h <= MC.VaultMaxHeight and entrySpeed >= MC.VaultMinSpeed then
		local endD
		local d = 0.5
		while d <= MC.VaultMaxDepth + 0.4 do
			local o = face + dir * d
			local r = workspace:Raycast(Vector3.new(o.X, topY + 1, o.Z), Vector3.new(0, -2.2, 0), params)
			if not r or r.Position.Y < topY - 1.2 then endD = d break end
			d += 0.4
		end
		if endD and endD <= MC.VaultMaxDepth + 0.4 then
			local land = face + dir * (endD + 1.2)
			local fl = workspace:Raycast(Vector3.new(land.X, topY + 1, land.Z), Vector3.new(0, -(1 + MC.VaultMaxDrop + 0.5), 0), params)
			if fl and fl.Normal.Y >= 0.7 and fl.Position.Y <= feetY + 1.2 then
				local landFeet = Vector3.new(land.X, fl.Position.Y, land.Z)
				local mid = face + dir * (endD / 2)
				local peakFeet = Vector3.new(mid.X, topY + MC.VaultArc, mid.Z)
				if self:_boxFree(landFeet, yaw, "Stand") and self:_boxFree(peakFeet, yaw, "Stand") then
					local startFeet = Vector3.new(self.Root.Position.X, feetY, self.Root.Position.Z)
					-- a quadratic bezier peaks at (A + 2 Ctrl + C) / 4 in height, so push the control point up to make the peak hit peakFeet
					local ctrl = Vector3.new(mid.X, 2 * peakFeet.Y - (startFeet.Y + landFeet.Y) / 2, mid.Z)
					local len = (landFeet - startFeet).Magnitude
					local speed = math.max(entrySpeed, MC.VaultExitSpeed)
					return {
						Kind = "Vault", A = rootAt(startFeet), Ctrl = rootAt(ctrl), C = rootAt(landFeet), Dir = dir,
						Dur = math.clamp(len / speed, MC.VaultTime.Min, MC.VaultTime.Max), ExitSpeed = speed, EndName = "Stand", Height = h,
						Ledge = ledgeCF, Depth = endD,
					}
				end
			end
		end
	end

	-- mantle: climb onto the ledge, standing (or crouched if the ceiling is low) EndInset studs in from the face
	local c = face + dir * MC.EndInset
	local surf = workspace:Raycast(Vector3.new(c.X, topY + 1, c.Z), Vector3.new(0, -2, 0), params)
	if not surf or surf.Normal.Y < 0.7 or math.abs(surf.Position.Y - topY) > 0.6 then return nil end
	local endFeet = Vector3.new(c.X, surf.Position.Y, c.Z)
	local endName = self:_boxFree(endFeet, yaw, "Stand") and "Stand" or (self:_boxFree(endFeet, yaw, "Crouch") and "Crouch" or nil)
	if not endName then return nil end
	local b = face - dir * 0.95
	local hoverFeet = Vector3.new(b.X, topY + 0.5, b.Z)
	if not self:_boxFree(hoverFeet, yaw, "Stand") then return nil end
	local pos = self.Root.Position
	local hoverRoot = rootAt(hoverFeet)
	if workspace:Raycast(pos, hoverRoot - pos, params) then return nil end -- something in the way of the pull-up
	return {
		Kind = "Mantle", A = pos, B = hoverRoot, C = rootAt(endFeet), Dir = dir,
		Dur = math.clamp(MC.MantleTime.Base + h * MC.MantleTime.PerStud, MC.MantleTime.Min, MC.MantleTime.Max), EndName = endName, Height = h,
		Ledge = ledgeCF, Depth = 0,
	}
end

-- look in front of the player for something to climb / hop over. Only called while standing (Applied == "Stand").
function Movement:_findLedge(yaw)
	local pos = self.Root.Position
	local feetY = pos.Y - STAND_ROOT_Y
	local fwd = CFrame.Angles(0, yaw, 0).LookVector
	local params = self:_worldParams()
	local lastDist
	for _, hh in HEIGHTS do
		local hit = workspace:Raycast(Vector3.new(pos.X, feetY + hh, pos.Z), fwd * MC.Reach, params)
		if hit and math.abs(hit.Normal.Y) < 0.35 and not (lastDist and math.abs(hit.Distance - lastDist) < 0.05) then
			lastDist = hit.Distance
			local n = Vector3.new(hit.Normal.X, 0, hit.Normal.Z)
			if n.Magnitude > 0.01 then
				local dir = -n.Unit
				if dir:Dot(fwd) >= MC.Angle then
					local entry = math.max(0, Vector3.new(self.Velocity.X, 0, self.Velocity.Z):Dot(dir))
					local m = self:_evalLedge(params, yaw, feetY, hit, dir, entry)
					if m then return m end
				end
			end
		end
	end
	return nil
end

function Movement:_startMantle(m)
	if self.Sliding then self:_endSlide(false) end
	self.Mantle, m.T = m, 0
	self.IsSprinting, self.Tac, self.Crouched, self.Prone = false, false, false, false
	self.JumpBuffer = 0
	for part in self.PartCollide do -- the body passes through the geometry it is climbing; the destination was checked for room
		if part.Parent then part.CanCollide = false end
	end
	self.Root.AssemblyLinearVelocity = Vector3.zero
	if self.OnMantle then self.OnMantle(m.Kind, m.Height) end
end

function Movement:_endMantle()
	local m = self.Mantle
	if not m then return end
	self.Mantle = nil
	for part, canCollide in self.PartCollide do
		if part.Parent then part.CanCollide = canCollide end
	end
	self.MantleCooldown = MC.Cooldown
	self.JumpSuppress = InputMap.IsDown("Jump") -- holding Jump through a mantle must not hop you straight off the ledge
	if m.Kind == "Vault" then
		self.Root.AssemblyLinearVelocity = m.Dir * m.ExitSpeed
		self.CurWalk, self.GlideT = m.ExitSpeed, MC.ExitGlide
	else
		self.Root.AssemblyLinearVelocity = Vector3.zero
		self.CurWalk = math.min(self.CurWalk, Config.WalkSpeed)
	end
	if m.EndName == "Crouch" then self.Crouched = true end
	self.LastVy, self.AirTime, self.Grounded = 0, 0, true -- no landing thud for the climb
	if self.OnMantleEnd then self.OnMantleEnd(m.Kind) end
end

function Movement:_stepMantle(dt)
	local m = self.Mantle
	local root = self.Root
	if self.Downed then self:_endMantle() return end
	m.T += dt
	local t = math.min(m.T / m.Dur, 1)
	local pos
	if m.Kind == "Vault" then
		local u = t * 0.65 + t * t * (3 - 2 * t) * 0.35 -- mostly linear: no slowing at the top of the hop
		local a, b, c = m.A, m.Ctrl, m.C
		pos = a * (1 - u) ^ 2 + b * (2 * (1 - u) * u) + c * (u * u)
	else
		local R = MC.RiseShare
		if t < R then
			local u = t / R
			pos = m.A:Lerp(m.B, 1 - (1 - u) ^ 2) -- fast pull, easing out as the chest reaches the ledge
		else
			local u = (t - R) / (1 - R)
			pos = m.B:Lerp(m.C, u * u * (3 - 2 * u)) -- roll over the edge and settle
		end
	end
	root.CFrame = CFrame.new(pos) * root.CFrame.Rotation
	root.AssemblyLinearVelocity = Vector3.zero
	self.Humanoid:Move(Vector3.zero, false)
	self.Humanoid.Jump = false
	if t >= 1 then self:_endMantle() end
end

-- ---------------------------------------------------------------- ladder
local function wrapAngle(a) return (a + math.pi) % (2 * math.pi) - math.pi end

-- ladder parts near `pos`: everything tagged Config.Ladder.Tag (a tagged Model counts all its parts) plus TrussParts in reach
function Movement:_ladderParts(pos)
	local list = {}
	for _, inst in CollectionService:GetTagged(LC.Tag) do
		if inst:IsA("BasePart") then
			table.insert(list, inst)
		elseif inst:IsA("Model") or inst:IsA("Folder") then
			for _, d in inst:GetDescendants() do
				if d:IsA("BasePart") then table.insert(list, d) end
			end
		end
	end
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { self.Char }
	for _, part in workspace:GetPartBoundsInRadius(pos, LC.Reach + 6, params) do
		if part:IsA("TrussPart") then table.insert(list, part) end
	end
	return list
end

-- Where is `pos` relative to this ladder part? Returns the climb geometry when it is close enough to grab, else nil.
local function ladderGeometry(part, pos)
	local cf, half = part.CFrame, part.Size / 2
	if math.abs(cf.UpVector.Y) < 0.7 then return nil end -- ladders stand upright
	local lp = cf:PointToObjectSpace(pos)
	local ox, oz = math.abs(lp.X) - half.X, math.abs(lp.Z) - half.Z
	local localN, dist, lat, halfW, latAxis
	if oz >= ox then
		localN, dist, lat, halfW, latAxis = Vector3.new(0, 0, lp.Z >= 0 and 1 or -1), oz, lp.X, half.X, Vector3.xAxis
	else
		localN, dist, lat, halfW, latAxis = Vector3.new(lp.X >= 0 and 1 or -1, 0, 0), ox, lp.Z, half.Z, Vector3.zAxis
	end
	local normal = cf:VectorToWorldSpace(localN)
	normal = Vector3.new(normal.X, 0, normal.Z)
	local lateral = cf:VectorToWorldSpace(latAxis)
	lateral = Vector3.new(lateral.X, 0, lateral.Z)
	if normal.Magnitude < 0.1 or lateral.Magnitude < 0.1 then return nil end
	local faceCenter = cf:PointToWorldSpace(localN * Vector3.new(half.X, 0, half.Z))
	local ext = half.Y * math.abs(cf.UpVector.Y) + half.X * math.abs(cf.RightVector.Y) + half.Z * math.abs(cf.LookVector.Y)
	return {
		Part = part, Normal = normal.Unit, Lateral = lateral.Unit, FaceCenter = faceCenter, Dist = dist, Lat = lat, HalfW = halfW,
		YMin = cf.Position.Y - ext, YMax = cf.Position.Y + ext,
	}
end

-- best ladder to grab from where the player stands and looks, or nil
function Movement:_scanLadder(yaw)
	if not LC.Enabled or not self.Root then return nil end
	local pos = self.Root.Position
	local feetY = pos.Y - STAND_ROOT_Y
	local fwd = CFrame.Angles(0, yaw, 0).LookVector
	local best, bestScore
	for _, part in self:_ladderParts(pos) do
		local g = ladderGeometry(part, pos)
		if g and g.Dist >= -0.6 and g.Dist <= LC.Reach and math.abs(g.Lat) <= g.HalfW + LC.SideSlack
			and feetY + 0.8 >= g.YMin and feetY <= g.YMax - LC.TopGrab - 0.3 and fwd:Dot(-g.Normal) >= LC.FaceDot then
			local score = g.Dist + math.abs(g.Lat) * 0.25
			if not bestScore or score < bestScore then best, bestScore = g, score end
		end
	end
	return best
end

function Movement:_startLadder(g)
	local pos = self.Root.Position
	local _, bodyYaw = self.Root.CFrame:ToEulerAnglesYXZ()
	local maxLat = math.max(g.HalfW - 0.5, 0)
	local lat = math.clamp((pos - g.FaceCenter):Dot(g.Lateral), -maxLat, maxLat)
	local base = g.FaceCenter + g.Lateral * lat + g.Normal * LC.MountDist
	local facing = -g.Normal
	self.Ladder = {
		Part = g.Part, Normal = g.Normal, YMin = g.YMin, YMax = g.YMax, Lateral = g.Lateral, FaceCenter = g.FaceCenter, Lat = lat,
		Base = Vector3.new(base.X, 0, base.Z), Start = Vector3.new(pos.X, 0, pos.Z),
		FacingYaw = math.atan2(-facing.X, -facing.Z), BodyYaw = bodyYaw, T = 0, Vy = 0,
	}
	self.LadderCand, self.LadderPrompt = nil, false
	self.Crouched, self.IsSprinting, self.Tac, self.Prone = false, false, false, false
	self.JumpBuffer = 0
	for part in self.PartCollide do
		if part.Parent then part.CanCollide = false end
	end
	self.Root.AssemblyLinearVelocity = Vector3.zero
	if self.OnLadder then self.OnLadder() end
end

-- reason: "Jump" (let go and fall), "Bottom", "Top" (a mantle takes over, so collisions stay off), "Lost" (died / ladder gone)
function Movement:_endLadder(reason)
	local L = self.Ladder
	if not L then return end
	self.Ladder = nil
	if reason ~= "Top" then
		for part, canCollide in self.PartCollide do
			if part.Parent then part.CanCollide = canCollide end
		end
	end
	self.LadderCooldown = LC.Cooldown
	self.MantleCooldown = math.max(self.MantleCooldown, LC.Cooldown) -- letting go must not turn into a mantle of the wall behind the ladder
	self.LastVy, self.AirTime = 0, 0
	if reason == "Jump" then
		self.Root.AssemblyLinearVelocity = L.Normal * LC.JumpOffSpeed + Vector3.new(0, LC.JumpOffUp, 0)
		self.JumpSuppress, self.JumpBuffer = true, 0 -- the press that let go must not also be a floor jump
	elseif reason == "Bottom" then
		self.Root.AssemblyLinearVelocity = Vector3.zero
	end
	if self.OnLadderEnd then self.OnLadderEnd(reason) end
end

-- the view may only swing LC.YawLimit either side of the ladder (the window closes smoothly while you step onto it)
function Movement:ClampYaw(yaw)
	local L = self.Ladder
	if not L then return yaw end
	local k = math.clamp(L.T / LC.MountTime, 0, 1)
	local half = math.pi + (LC.YawLimit - math.pi) * (k * k * (3 - 2 * k))
	local d = wrapAngle(yaw - L.FacingYaw)
	if math.abs(d) <= half then return yaw end
	return L.FacingYaw + math.clamp(d, -half, half)
end

-- pull-up over the top: a mantle path onto the floor just past the top of the ladder, or nil when there is none
function Movement:_ladderTopExit(L, yaw)
	local dir = -L.Normal
	local pos = self.Root.Position
	local topY = L.YMax
	local params = self:_worldParams()
	local ignore = params.FilterDescendantsInstances
	table.insert(ignore, L.Part)
	params.FilterDescendantsInstances = ignore
	local face = L.FaceCenter + L.Lateral * L.Lat
	local c = face + dir * LC.TopInset
	local surf = workspace:Raycast(Vector3.new(c.X, topY + LC.TopRise, c.Z), Vector3.new(0, -(LC.TopRise + LC.TopDrop), 0), params)
	if not surf or surf.Normal.Y < 0.7 then return nil end
	local endFeet = Vector3.new(c.X, surf.Position.Y, c.Z)
	local endName = self:_boxFree(endFeet, yaw, "Stand") and "Stand" or (self:_boxFree(endFeet, yaw, "Crouch") and "Crouch" or nil)
	if not endName then return nil end
	local feetY = pos.Y - STAND_ROOT_Y
	local h = math.max(surf.Position.Y - feetY, 0.3)
	local hoverFeet = Vector3.new(pos.X, math.max(surf.Position.Y, topY) + 0.5, pos.Z)
	local lip = Vector3.new(face.X, surf.Position.Y, face.Z)
	return {
		Kind = "Mantle", A = pos, B = rootAt(hoverFeet), C = rootAt(endFeet), Dir = dir,
		Dur = math.clamp(MC.MantleTime.Base + h * MC.MantleTime.PerStud, MC.MantleTime.Min, MC.MantleTime.Max), EndName = endName, Height = h,
		Ledge = CFrame.lookAt(lip, lip + dir), Depth = 0,
	}
end

function Movement:_stepLadder(dt, yaw)
	local L = self.Ladder
	local root, hum = self.Root, self.Humanoid
	if self.Downed or not L.Part.Parent or hum.Health <= 0 then self:_endLadder("Lost") return end
	L.T += dt
	local mountK = math.clamp(L.T / LC.MountTime, 0, 1)
	local ease = mountK * mountK * (3 - 2 * mountK)
	local paused = self.Engaged or self.LadderHold -- aiming / firing / working the pistol: both hands are busy, so no climbing
	local input = -InputMap.GetMoveVector().Z -- W / stick up climbs, S / stick down descends
	if math.abs(input) < LC.Deadzone then input = 0 end
	local target = (paused or mountK < 1) and 0 or input * LC.ClimbSpeed
	L.Vy = approach(L.Vy, target, LC.Accel * dt)

	local pos = root.Position
	local feetY = pos.Y - STAND_ROOT_Y
	local newFeet = feetY + L.Vy * dt
	if newFeet >= L.YMax - LC.TopGrab then -- top: pull up onto the platform if there is one, otherwise stop
		newFeet = L.YMax - LC.TopGrab
		if input > 0 and not paused and mountK >= 1 then
			local m = self:_ladderTopExit(L, yaw)
			if m then
				self:_endLadder("Top")
				self:_startMantle(m)
				return
			end
		end
		L.Vy = math.min(L.Vy, 0)
	end
	if input < 0 and not paused and mountK >= 1 then -- bottom: floor under the feet (or the end of the ladder) steps you off
		local hit = workspace:Raycast(pos, Vector3.new(0, -(STAND_ROOT_Y + 0.2), 0), self:_worldParams())
		if hit or newFeet <= L.YMin then
			root.CFrame = CFrame.new(pos.X, hit and (hit.Position.Y + STAND_ROOT_Y) or pos.Y, pos.Z) * root.CFrame.Rotation
			self:_endLadder("Bottom")
			return
		end
	end

	-- the body faces the ladder; while aiming it follows the (limited) view instead
	local want = paused and self:ClampYaw(yaw) or L.FacingYaw
	L.BodyYaw += wrapAngle(want - L.BodyYaw) * (1 - math.exp(-12 * dt))
	local h = L.Start:Lerp(L.Base, ease)
	root.CFrame = CFrame.new(h.X, newFeet + STAND_ROOT_Y, h.Z) * CFrame.Angles(0, L.BodyYaw, 0)
	root.AssemblyLinearVelocity = Vector3.zero
	self.Align.CFrame = CFrame.Angles(0, L.BodyYaw, 0)
	hum:Move(Vector3.zero, false)
	hum.Jump = false
	self.LadderPhase += L.Vy * dt
end

-- ---------------------------------------------------------------- air strafe
-- Quake-style air acceleration on the root's own velocity. Returns the new horizontal velocity.
-- A direction only adds speed along itself up to WishCap, so going faster than WishCap forward gains nothing, but a direction at an angle to
-- your velocity (strafing while the camera turns the same way) keeps adding a little every step.
function Movement:_airStrafe(dt, moveDir, base)
	local vel = self.Root.AssemblyLinearVelocity
	local v = Vector3.new(vel.X, 0, vel.Z)
	local before = v.Magnitude
	if moveDir.Magnitude > 0.1 then
		local wish = moveDir.Unit
		local cap = math.min(AS.WishCap, base) * math.min(moveDir.Magnitude, 1)
		self.AirAcc = math.min(self.AirAcc + dt, AS.Step * 6)
		while self.AirAcc >= AS.Step do
			self.AirAcc -= AS.Step
			local add = cap - v:Dot(wish)
			if add > 0 then v += wish * math.min(AS.Accel * base * AS.Step, add) end
		end
		local after = v.Magnitude
		if after > AS.MaxSpeed and after > before then v = v.Unit * math.max(before, AS.MaxSpeed) end
	else
		self.AirAcc = 0
	end
	self.Root.AssemblyLinearVelocity = Vector3.new(v.X, vel.Y, v.Z)
	return v
end

-- speedMult: weapon/ADS multiplier applied to walk/crouch speeds
function Movement:Update(dt, yaw, speedMult)
	if not self.Active then return end
	local hum, root = self.Humanoid, self.Root
	local vel = root.AssemblyLinearVelocity
	self.Velocity = vel
	self.Speed = Vector3.new(vel.X, 0, vel.Z).Magnitude

	if self.Downed then -- crawling: no sprint / slide / crouch / prone / dive / jump
		self.Crouched, self.Prone, self.Diving, self.DivePending, self.ProneSlide, self.DropShot = false, false, false, false, 0, 0
		if self.Sliding then self:_endSlide(false) end
	end
	hum.JumpHeight = self.Downed and 0 or (self.DivePending and Config.DiveHeight or Config.JumpHeight)

	local grounded = hum.FloorMaterial ~= Enum.Material.Air
	if grounded and not self.Grounded and self.LastVy < -22 and self.OnLand then self.OnLand(-self.LastVy) end
	self.AirTime = grounded and 0 or self.AirTime + dt
	if grounded and not self.Grounded and AS.Enabled and AS.Bhop and not self.Mantle -- landing with Jump held: keep the speed (bunny hop)
		and (self.JumpBuffer > 0 or (InputMap.IsDown("Jump") and not self.JumpSuppress)) then
		self.BhopT = AS.BhopWindow
		self.CurWalk = math.min(math.max(self.CurWalk, self.Speed), AS.MaxSpeed) * (1 - AS.BhopLoss)
	end
	self.Grounded = grounded
	self.LastVy = vel.Y
	self.SlideCooldown = math.max(0, self.SlideCooldown - dt)
	self.MantleCooldown = math.max(0, self.MantleCooldown - dt)
	self.LadderCooldown = math.max(0, self.LadderCooldown - dt)
	self.LastYaw = yaw
	self.JumpBuffer = math.max(0, self.JumpBuffer - dt)
	self.BhopT, self.GlideT = math.max(0, self.BhopT - dt), math.max(0, self.GlideT - dt)
	self.DiveCooldown = math.max(0, self.DiveCooldown - dt)
	self.DropShot = math.max(0, self.DropShot - dt)
	if self.Sliding then self.SlideTime += dt end

	-- dive: hop (DivePending drives one Humanoid jump at DiveHeight), fly on SlideDir, then land prone with a short skid
	if self.Diving then
		self.DiveTime += dt
		if not grounded then self.DiveAir, self.DivePending = true, false end
		if self.DiveTime > 0.15 then self.DivePending = false end
		if (self.DiveAir and grounded) or self.DiveTime > 1.2 then
			self.Diving, self.DiveAir, self.DivePending = false, false, false
			self.ProneSlide = math.min(self.Speed, Config.ProneSlideSpeed)
		end
	end
	-- prone skid bleeds off; falling off a ledge while prone stands you up
	if self.ProneSlide > 0 then
		self.ProneSlide = (self.Prone and grounded) and math.max(0, self.ProneSlide - Config.ProneSlideFriction * dt) or 0
	end
	if self.Prone and not self.Diving and self.AirTime > 0.3 then self.Prone = false end

	-- hold Crouch long enough = prone
	if self.CrouchHeldAt then
		if not InputMap.IsDown("Crouch") or self.Sliding or self.Downed then
			self.CrouchHeldAt = nil
		elseif os.clock() - self.CrouchHeldAt >= Config.ProneHoldTime then
			self.CrouchHeldAt = nil
			if grounded then self:_goProne() end
		end
	end
	if not (self.Mantle or self.Ladder) then self:_resolveHeadroom() end -- mid-climb the body is deliberately inside geometry
	self.Align.CFrame = CFrame.Angles(0, yaw, 0)

	-- raw input (x = right, z = back) -> world direction on the yaw plane
	local iv = InputMap.GetMoveVector()
	local yawCF = CFrame.Angles(0, yaw, 0)
	local moveDir = yawCF:VectorToWorldSpace(Vector3.new(iv.X, 0, iv.Z))
	local forwardness = iv.Magnitude > 0.1 and (-iv.Z / iv.Magnitude) or 0

	-- ladder: on one, the body is driven along it; otherwise look for one to offer (prompt) while standing or falling past it
	if self.Ladder then
		self:_stepLadder(dt, yaw)
		self:_blend(dt, grounded)
		return
	end
	if LC.Enabled and not self.Mantle and self.LadderCooldown <= 0 and self.Applied == "Stand" and not (self.Downed or self.Prone or self.Diving or self.Sliding) then
		self.LadderScanT -= dt
		if self.LadderScanT <= 0 then
			self.LadderScanT = 0.08
			self.LadderCand = self:_scanLadder(yaw)
		end
	else
		self.LadderCand = nil
	end
	self.LadderPrompt = self.LadderCand ~= nil and not self.Engaged and not self.LadderBlocked and not self.InteractTaken

	-- mantle / vault: Jump (pressed a moment ago, or held) while standing and facing a ledge. Takes over the body until it is done.
	if MC.Enabled and not self.Mantle and self.MantleCooldown <= 0 and self.Applied == "Stand" and not self.PendingWant
		and not (self.Downed or self.Prone or self.Diving or self.Sliding or self.Crouched)
		and (self.JumpBuffer > 0 or (InputMap.IsDown("Jump") and not self.JumpSuppress)) and vel.Y > -MC.MaxFallSpeed then
		local m = self:_findLedge(yaw)
		if m then self:_startMantle(m) end
	end
	if self.Mantle then
		self:_stepMantle(dt)
		self:_blend(dt, grounded)
		return
	end

	-- sprint / tactical sprint
	local wantsSprint = self.WantsSprint or Settings.Get("Gameplay.SprintMode") == "Auto"
	local canSprint = wantsSprint and not self.SprintBlocked and not self.Sliding and not self.Downed and not self.Prone and not self.Diving and not self.PendingWant -- PendingWant: standing is blocked overhead
		and (grounded or self.IsSprinting) and forwardness > 0.5
	if canSprint then
		if not self.IsSprinting then
			self.IsSprinting, self.Crouched = true, false
			if os.clock() < self.TacArmedUntil then
				self.Tac, self.TacTimer, self.TacArmedUntil = true, Config.TacTime * self.TacTimeMult, 0
			end
		end
		if self.Tac then
			self.TacTimer -= dt
			if self.TacTimer <= 0 then self.Tac = false end
		end
	else
		self.IsSprinting, self.Tac = false, false
	end

	-- slide
	if self.Sliding then
		local n = self:_floorNormal()
		local downhill = Vector3.new(0, -1, 0) + n * n.Y -- gravity projected on the surface
		local accel = downhill:Dot(self.SlideDir) * Config.SlideSlope
		self.SlideSpeed = math.clamp(self.SlideSpeed - Config.SlideFriction * dt + accel * dt, 0, Config.SlideMax)
		if moveDir.Magnitude > 0.1 then
			local d = self.SlideDir:Lerp(moveDir.Unit, math.clamp(Config.SlideSteer * dt, 0, 1))
			if d.Magnitude > 0.05 then self.SlideDir = d.Unit end
		end
		if self.AirTime > 0.2 then
			self.Carry = self.SlideSpeed
			self:_endSlide(false)
		elseif self.SlideSpeed < Config.SlideEndSpeed then
			self:_endSlide(false)
		end
	end

	-- target speed
	local base
	local gm = self.GlobalMult
	if self.Downed then base = Config.CrawlSpeed * gm
	elseif self.Tac then base = Config.TacSpeed * gm
	elseif self.IsSprinting then base = Config.SprintSpeed * gm
	elseif self.Prone then base = Config.ProneSpeed * speedMult * gm
	elseif self.Crouched then base = Config.CrouchSpeed * speedMult * gm
	else base = Config.WalkSpeed * speedMult * gm end

	local airStrafe = AS.Enabled and not grounded and self.AirTime > AS.Grace and not (self.Sliding or self.Diving or self.Downed)
	if airStrafe then
		-- the root's own velocity is steered (see _airStrafe); the Humanoid is told to move at exactly that velocity so it adds nothing of its own
		local v = self:_airStrafe(dt, moveDir, base)
		self.Carry, self.CurWalk = 0, v.Magnitude
		hum.WalkSpeed = v.Magnitude
		hum:Move(v.Magnitude > 0.5 and v.Unit or Vector3.zero, false)
	else
		self.AirAcc = 0
		local target
		if self.Sliding then
			target = self.SlideSpeed
		elseif self.Diving then
			target = Config.DiveSpeed
		elseif not grounded then
			self.Carry = math.max(0, self.Carry - 3 * dt)
			target = math.max(base, self.Carry)
		else
			self.Carry = 0
			target = math.max(base, self.ProneSlide)
		end

		if self.Sliding or self.Diving or self.ProneSlide > 0 then
			self.CurWalk = target
		else
			local rate = target > self.CurWalk and Config.Accel or Config.Decel
			if grounded and target <= self.CurWalk then
				if self.BhopT > 0 then rate = 0 -- bunny hop: the floor does not brake you right after a landing
				elseif self.GlideT > 0 then rate = MC.ExitDecel end -- coming out of a vault: bleed speed off gently
			end
			self.CurWalk = approach(self.CurWalk, target, rate * dt)
		end
		hum.WalkSpeed = self.CurWalk
		local committed = self.Sliding or self.Diving or self.ProneSlide > 0 -- no steering while sliding, diving or skidding
		hum:Move(committed and self.SlideDir or moveDir, false)
	end
	hum.Jump = self.DivePending or (InputMap.IsDown("Jump") and not self.Downed and not self.Prone and not self.JumpSuppress)

	self:_blend(dt, grounded)
end

-- state + blend alphas + eye height + collider; shared by the normal update and the mantle update
function Movement:_blend(dt, grounded)
	local hum = self.Humanoid
	-- state + blend alphas used by camera / viewmodel
	if self.Downed then self.State = "Downed"
	elseif self.Sliding then self.State = "Slide"
	elseif self.Diving then self.State = "Dive" -- replicated as its own pose (other players see a flying dive, not a jump)
	elseif self.Mantle then self.State = self.Mantle.Kind -- "Mantle" / "Vault": replicated as its own pose (ClimbPose.luau draws it)
	elseif self.Ladder then self.State = "Ladder" -- WeaponController replicates it as "Air"
	elseif not grounded then self.State = "Air"
	elseif self.Tac then self.State = "TacSprint"
	elseif self.IsSprinting then self.State = "Sprint"
	elseif self.Prone then self.State = "Prone"
	elseif self.Crouched then self.State = "Crouch"
	elseif self.Speed > 1 then self.State = "Walk"
	else self.State = "Idle" end

	local A = self.Alpha
	A.Sprint = smooth(A.Sprint, self.IsSprinting and 1 or 0, 10, dt)
	A.Tac = smooth(A.Tac, self.Tac and 1 or 0, 8, dt)
	A.Slide = smooth(A.Slide, self.Sliding and 1 or 0, 12, dt)
	local tuck = self.Mantle ~= nil or (self.Ladder ~= nil and not (self.Engaged or self.LadderHold)) -- gun tucked away while the hands are on the ladder
	A.Mantle = smooth(A.Mantle, tuck and 1 or 0, 12, dt)
	A.Ladder = smooth(A.Ladder, (self.Ladder and not (self.Engaged or self.LadderHold)) and 1 or 0, 8, dt)
	A.Down = smooth(A.Down, self.Downed and 1 or 0, 6, dt)
	A.Crouch = smooth(A.Crouch, (self.Crouched and not self.Sliding and not self.Prone) and 1 or 0, 10, dt)
	A.Prone = smooth(A.Prone, (self.Prone and not self.Downed) and 1 or 0, 10, dt)

	local eye = Config.Eye
	local eyeT = self.Downed and eye.Down or (self.Sliding and eye.Slide or (self.Prone and eye.Prone or (self.Crouched and eye.Crouch or eye.Stand)))
	local eyeRate = (self.Prone and self.DropShot > 0) and Config.DropShotEyeRate or 14 -- drop shot: the eye (and hitbox) falls fast
	self.EyeHeight = smooth(self.EyeHeight, eyeT, eyeRate, dt)

	-- physical body: follow the stance, and tell the camera how far the root has sunk (it adds RootDrop to EyeHeight, so the view
	-- stays where the eye height says even though the root itself is now lower)
	self:_applyCollider(self:_wantedCollider())
	self.RootDrop = smooth(self.RootDrop, COL[self.Applied].RootDrop, eyeRate, dt)
end

return Movement
