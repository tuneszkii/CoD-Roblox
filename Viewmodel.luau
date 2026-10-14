-- Procedural first-person viewmodel: spring layers (sway, bob, kick, strafe, equip, wall avoidance),
-- state poses (hip / ADS / sprint / tac sprint / slide), keyframed gun animations (reload, bolt, pump, shells),
-- chest-space tracks (equipment, plates, melee) and two-bone IK arms.
local Config = require(script.Parent.Config)
local Spring = require(script.Parent.Spring)
local IK = require(script.Parent.IK)
local GunModel = require(script.Parent.GunModel)
local Anim = require(script.Parent.Anim)
local ClimbPose = require(script.Parent.ClimbPose)
local ItemBuilder = require(script.Parent.ItemBuilder)

local V = Config.Viewmodel
local rad = math.rad
local REACH = V.UpperLen + V.ForeLen

local Viewmodel = {}
Viewmodel.__index = Viewmodel

local function smooth(cur, target, rate, dt)
	return cur + (target - cur) * (1 - math.exp(-rate * dt))
end

local function newPart(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.Parent = parent
	return p
end

local function newArm(model, shoulder, hint)
	return {
		Shoulder = shoulder, Hint = hint,
		Upper = newPart(model, "Upper", Vector3.new(0.38, 0.38, V.UpperLen), V.SleeveColor, Enum.Material.Fabric),
		Fore = newPart(model, "Fore", Vector3.new(0.34, 0.34, V.ForeLen), V.SleeveColor, Enum.Material.Fabric),
		Hand = newPart(model, "Hand", Vector3.new(0.32, 0.28, 0.4), V.GloveColor),
	}
end

function Viewmodel.new()
	local self = setmetatable({}, Viewmodel)
	self.Model = Instance.new("Model")
	self.Model.Name = "FPSViewmodel"
	self.RightArm = newArm(self.Model, V.RightShoulder, V.RightHint)
	self.LeftArm = newArm(self.Model, V.LeftShoulder, V.LeftHint)

	self.SwayRot = Spring.new(14, 0.55)
	self.SwayPos = Spring.new(14, 0.6)
	self.MoveSpring = Spring.new(10, 0.7)
	self.KickPos = Spring.new(26, 0.5)
	self.KickRot = Spring.new(24, 0.45)
	self.EquipSpring = Spring.new(14, 0.55)

	self.BobT, self.Wall, self.FlashToken = 0, 0, 0
	self.Visible, self.Hidden = false, false
	return self
end

function Viewmodel:_parent()
	self.Model.Parent = (self.Visible and not self.Hidden) and workspace.CurrentCamera or nil
end

function Viewmodel:SetCharacter(char)
	self.WallParams = RaycastParams.new()
	self.WallParams.FilterType = Enum.RaycastFilterType.Exclude
	self.WallParams.FilterDescendantsInstances = { char, self.Model }
	self.WallParams.RespectCanCollide = true
	self:SetVisible(true)
end

-- operator colors (Cosmetics.luau): recolor the first-person sleeves and gloves
function Viewmodel:SetColors(sleeve, glove)
	for _, arm in { self.RightArm, self.LeftArm } do
		arm.Upper.Color, arm.Fore.Color, arm.Hand.Color = sleeve or V.SleeveColor, sleeve or V.SleeveColor, glove or V.GloveColor
	end
end

function Viewmodel:SetVisible(v)
	self.Visible = v
	self:_parent()
end

function Viewmodel:SetHidden(h) -- hides gun + arms (scope overlay)
	if self.Hidden == h then return end
	self.Hidden = h
	self:_parent()
end

function Viewmodel:SetGun(name, cfg, attIds)
	if self.G then self.G.Model:Destroy() end
	local G = GunModel.Create(name, cfg, true, attIds)
	self.G, self.Gun, self.Cfg, self.Flash = G, G.Model, cfg, G.Flash
	self.AdsPose = CFrame.new(0, 0, -V.EyeRelief) * G.AimRel:Inverse()
	G.Model.Parent = self.Model
	self.GunAnim = nil
	self:EndTrack()
end

function Viewmodel:PlayEquip()
	self.EquipSpring.Position = Vector3.new(1, 0, 0)
	self.EquipSpring.Velocity = Vector3.zero
end

function Viewmodel:Kick(strength, ads)
	local k = strength * (1 - 0.5 * ads)
	self.KickPos:Impulse(Vector3.new((math.random() - 0.5) * 0.5 * k, 0.3 * k, 3.2 * k))
	self.KickRot:Impulse(Vector3.new(1.3 * k, (math.random() - 0.5) * 0.9 * k, (math.random() - 0.5) * 1.4 * k))
end

function Viewmodel:Land(speed)
	self.KickPos:Impulse(Vector3.new(0, -math.clamp(speed * 0.04, 0, 2.5), 0.4))
end

-- weapon jolt when the player is shot / a bullet cracks past. k = 0..~2 (Config.Flinch scales it), dir = -1 / 1 sideways bias
function Viewmodel:Flinch(k, dir)
	self.KickPos:Impulse(Vector3.new(dir * 0.35 * k, -0.25 * k, 0.9 * k))
	self.KickRot:Impulse(Vector3.new(-0.5 * k, dir * 0.6 * k, dir * 0.8 * k))
end

function Viewmodel:SlideKick()
	self.KickPos:Impulse(Vector3.new(0, -1.2, 0.5))
	self.KickRot:Impulse(Vector3.new(-0.6, 0, 0.8))
end

function Viewmodel:MuzzleFlash()
	if not self.Flash then return end
	self.Flash.Light.Enabled = true
	self.Flash.Emitter:Emit(2)
	self.FlashToken += 1
	local tok, flash = self.FlashToken, self.Flash
	task.delay(0.04, function()
		if self.FlashToken == tok then flash.Light.Enabled = false end
	end)
end

function Viewmodel:GetMuzzleCFrame()
	return (self.GunCF or CFrame.new()) * self.G.MuzzleRel
end

-- ---------------------------------------------------------------- animations
-- anim = result of Anim.Reload / Anim.Cycle / Anim.Shell, with .Kind = "Reload" | "Bolt" | "Pump" | "Shell"
function Viewmodel:PlayGunAnim(anim, duration)
	self.GunAnim = { Anim = anim, T = math.max(duration, 0.05), t = 0 }
end

function Viewmodel:CancelGunAnim()
	self.GunAnim = nil
end

function Viewmodel:IsAnimating()
	return self.GunAnim ~= nil
end

-- name: Anim.Tracks key. duration nil = hold the first key until EndTrack.
function Viewmodel:StartTrack(name, duration, itemKind, itemColor)
	self:EndTrack()
	self.Track = { Name = name, T = duration, t = 0 }
	if itemKind then
		local item = ItemBuilder.Create(itemKind, itemColor)
		item.Model.Parent = self.Model
		self.Item = item
	end
end

function Viewmodel:DropItem() -- item leaves the hand (thrown) but the track keeps playing
	if self.Item then
		self.Item.Model:Destroy()
		self.Item = nil
	end
end

function Viewmodel:EndTrack()
	self.Track = nil
	if self.Item then
		self.Item.Model:Destroy()
		self.Item = nil
	end
end

-- ---------------------------------------------------------------- IK
function Viewmodel:_arm(arm, camCF, handCF)
	local shoulder = camCF:PointToWorldSpace(arm.Shoulder)
	local hint = camCF:PointToWorldSpace(arm.Hint)
	local elbow, wrist = IK.Solve(shoulder, handCF.Position, hint, V.UpperLen, V.ForeLen)
	local up = hint - elbow
	arm.Upper.CFrame = IK.Segment(shoulder, elbow, V.UpperLen, up)
	arm.Fore.CFrame = IK.Segment(elbow, wrist, V.ForeLen, up)
	arm.Hand.CFrame = CFrame.new(wrist) * handCF.Rotation
end

-- ---------------------------------------------------------------- frame
function Viewmodel:Update(dt, camCF, movement, weapons, mouse)
	local G = self.G
	if not G or self.Hidden then return end
	local ads = weapons.AdsEased
	local adsK = 1 - 0.85 * ads

	local mx, my = math.clamp(mouse.X, -50, 50), math.clamp(mouse.Y, -50, 50)
	self.SwayRot.Target = Vector3.new(my * 0.0016, mx * 0.0016, mx * 0.001)
	self.SwayPos.Target = Vector3.new(-mx * 0.0007, my * 0.0007, 0)
	local sr, sp = self.SwayRot:Update(dt), self.SwayPos:Update(dt)

	local lv = camCF:VectorToObjectSpace(movement.Velocity)
	self.MoveSpring.Target = Vector3.new(
		-math.clamp(lv.X, -20, 20) * 0.0035,
		math.clamp(-lv.Y, -60, 60) * 0.0016,
		math.clamp(lv.Z, -30, 30) * 0.0012)
	local mv = self.MoveSpring:Update(dt)
	local strafeRoll = -math.clamp(lv.X, -20, 20) * 0.003

	local speed = movement.Grounded and movement.Speed or 0
	self.BobT += dt * speed * 0.6
	local amp = math.clamp(speed / 12, 0, 1.6) * (1 + movement.Alpha.Sprint * 0.6)
	local bobPos = Vector3.new(math.sin(self.BobT) * 0.03, math.sin(self.BobT * 2) * 0.02, 0) * amp
	local bobRot = Vector3.new(math.sin(self.BobT * 2) * 0.01, math.sin(self.BobT) * 0.015, math.sin(self.BobT) * 0.02) * amp
	local breath = math.sin(os.clock() * 1.7) * 0.004

	local kp, kr = self.KickPos:Update(dt), self.KickRot:Update(dt)
	local e = self.EquipSpring:Update(dt).X
	local equipCF = CFrame.new(0.25 * e, -1.1 * e, 0.5 * e) * CFrame.Angles(rad(-50) * e, rad(20) * e, rad(-12) * e)

	local chestCF = camCF * CFrame.new(V.Chest)

	-- gun animation (reload / cycle / shells)
	local gripL = G.LeftGripRel and G.LeftGripRel.Position or G.RightGripRel.Position
	local gripR = G.RightGripRel.Position
	local leftPos, rightPos = gripL, gripR
	local magOff, pumpOff, boltOff, magVisible, rAlpha = Vector3.zero, nil, nil, true, 0
	local ga = self.GunAnim
	if ga then
		ga.t += dt
		local f = ga.t / ga.T
		if f >= 1 then
			self.GunAnim = nil
		else
			local L, R, state = Anim.SampleKeys(ga.Anim.Keys, f, gripL, gripR)
			leftPos, rightPos = L, R
			local kind = ga.Anim.Kind
			if kind == "Reload" and G.MagRel then
				if state == "carry" then magOff = L - G.MagRel.Position
				elseif state == "hidden" then magVisible = false end
			elseif kind == "Bolt" and G.Movers.Bolt and state == "carry" then
				boltOff = R - G.Movers.Bolt.Rel.Position
			elseif kind == "Pump" then
				pumpOff = L - gripL
			end
			rAlpha = Anim.SampleScalar(ga.Anim.Pose, f)
		end
	end
	if weapons.HideMag and not self.GunAnim then magVisible = false end

	-- chest-space track (equipment / plates / melee)
	local tr = self.Track
	local Rt, Lt, drop, gOff, tw = nil, nil, 0, CFrame.identity, 0
	if tr then
		local f = 0
		if tr.T then
			tr.t += dt
			f = math.min(tr.t / tr.T, 1)
		end
		local R, L, Gx, Dp, W = Anim.SampleTrack(tr.Name, f)
		Rt, Lt = chestCF * Anim.Scale(R, REACH), chestCF * Anim.Scale(L, REACH)
		drop, gOff, tw = Dp, Anim.Scale(Gx, REACH), W
		if tr.T and tr.t >= tr.T then self.Track = nil end
	end

	-- mantle / vault: the same solver the third-person body uses, so your hands grip exactly where other players see them gripping
	local climbPose
	local mantle = movement.Mantle
	if mantle and mantle.Ledge and mantle.Dur > 0 then
		climbPose = ClimbPose.Solve(mantle.Kind, math.clamp(mantle.T / mantle.Dur, 0, 1), movement.Root.CFrame, mantle.Ledge, mantle.Depth or 0)
	end

	-- pose blend
	local A = movement.Alpha
	local pose = V.Hip:Lerp(V.Sprint, A.Sprint):Lerp(V.Tac, A.Tac):Lerp(V.Slide, A.Slide)
	pose = pose:Lerp(V.Down, A.Down * (1 - ads))
	pose = pose:Lerp(V.Prone, A.Prone * (1 - ads))
	pose = pose:Lerp(V.Mantle, A.Mantle * (1 - ads))
	pose = pose:Lerp(self.AdsPose, ads)
	pose = pose:Lerp(V.Drop, drop)

	local hit = workspace:Raycast(camCF.Position, camCF.LookVector * 3.9, self.WallParams)
	local wTarget = hit and math.clamp((3.9 - hit.Distance) / 1.6, 0, 1) or 0
	self.Wall = smooth(self.Wall, wTarget, 14, dt)
	local w = self.Wall
	local wallCF = CFrame.new(-0.15 * w, -0.2 * w, 0.7 * w) * CFrame.Angles(rad(30) * w, rad(18) * w, 0)

	local pos = sp * adsK + mv * adsK + kp + bobPos * adsK + Vector3.new(0, breath * adsK, 0)
	local rot = sr * adsK + kr + bobRot * adsK + Vector3.new(0, 0, strafeRoll * adsK)
	local pivot = G.RightGripRel.Position
	local gunCF = camCF * gOff * equipCF * CFrame.new(pos) * pose * wallCF
		* CFrame.identity:Lerp(V.Reload, rAlpha)
		* CFrame.new(pivot) * CFrame.fromOrientation(rot.X, rot.Y, rot.Z) * CFrame.new(-pivot)
	self.GunCF = gunCF

	GunModel.Pose(G, gunCF, magOff, pumpOff, boltOff, magVisible)

	-- hands
	local rightCF = gunCF * (CFrame.new(rightPos) * G.RightGripRel.Rotation)
	local leftCF
	if G.OneHanded then
		leftCF = chestCF * Anim.Scale(Anim.LeftRest, REACH)
	else
		leftCF = gunCF * (CFrame.new(leftPos) * G.LeftGripRot)
	end
	if Rt then
		rightCF = rightCF:Lerp(Rt, tw)
		leftCF = leftCF:Lerp(Lt, tw)
	end

	if climbPose then -- hands reach for the lip / plant on the obstacle (the gun is already tucked away by V.Mantle)
		if climbPose.HandW.R > 0 then rightCF = rightCF:Lerp(climbPose.Hand.R, climbPose.HandW.R) end
		if climbPose.HandW.L > 0 then leftCF = leftCF:Lerp(climbPose.Hand.L, climbPose.HandW.L) end
	end

	if self.Item then
		local base
		if self.Item.Mid then
			base = rightCF:Lerp(leftCF, 0.5) * CFrame.new(0, 0, -0.35)
		else
			base = rightCF * CFrame.new(0, 0.05, -0.35)
		end
		ItemBuilder.Pose(self.Item, base, 1 - math.clamp(tw * 2, 0, 1))
	end

	self:_arm(self.RightArm, camCF, rightCF)
	self:_arm(self.LeftArm, camCF, leftCF)
end

return Viewmodel
