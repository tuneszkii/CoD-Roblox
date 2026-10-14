-- Procedural third-person animation for R6 characters (runs on every client for every OTHER player).
--  * Torso lean / crouch / slide pose and head pitch are driven through the R6 Motor6Ds (computed analytically).
--  * Arms and legs are custom two-bone IK limbs (the default R6 limbs are hidden locally):
--      arms grip the weapon (reload, bolt, pump, equipment, plates, melee all play from the shared Anim data),
--      legs plant feet on the ground with raycasts and step when a foot gets too far from its hip.
--  * State arrives through character attributes set by the server (Stance, AimPitch, AdsAmt, WeaponName, Action*, Plates, Perks).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Config = require(script.Parent.Config)
local IK = require(script.Parent.IK)
local Anim = require(script.Parent.Anim)
local GunModel = require(script.Parent.GunModel)
local ItemBuilder = require(script.Parent.ItemBuilder)
local Emotes = require(script.Parent.Emotes)
local Cosmetics = require(script.Parent.Cosmetics)
local ClimbPose = require(script.Parent.ClimbPose)

local TPc = Config.ThirdPerson
local rad = math.rad
local CF = CFrame.new
local localPlayer = Players.LocalPlayer

local ThirdPerson = {}
ThirdPerson.LocalAllowed = false -- true while your own emote plays (the local body is normally hidden in first person)
local rigs = {}
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local DROP, FWD = TPc.StanceDrop, TPc.StanceFwd -- shared with Hitbox.luau so the server hitboxes follow the same poses
local COL = Config.Movement.Collider -- low stances sink the real root (Movement.luau); the body maths below is written against the standing root
local STAND_ROOT_Y = Config.Movement.Capsule.StandRootY
local SPRINT = { Sprint = 1, TacSprint = 1, Slide = 1 }
local LYING = { Downed = true, Prone = true, Dive = true } -- all use the lying-flat body pose (Prone keeps the normal weapon aim, Downed the crawl pose)
local CHEST_TRACKS = { Pull = true, Hold = true, Throw = true, Use = true, Sensor = true, Plant = true, Plate = true,
	Bash = true, SwingR = true, SwingL = true, Lunge = true, Smash = true }
local ITEM_COLOR = {}
for _, d in Config.Equipment do ITEM_COLOR[d.Item] = ITEM_COLOR[d.Item] or d.Color end
ITEM_COLOR.Plate = Color3.fromRGB(70, 74, 70)

local function refreshFilter()
	local list = { workspace.CurrentCamera }
	for _, p in Players:GetPlayers() do
		if p.Character then table.insert(list, p.Character) end
	end
	rayParams.FilterDescendantsInstances = list
end

local function newPart(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, true, true
	p.Parent = parent
	return p
end

local function limb(folder, upperLen, lowerLen, thick, c1, c2, c3)
	return {
		Upper = newPart(folder, "Upper", Vector3.new(thick, thick, upperLen), c1),
		Lower = newPart(folder, "Lower", Vector3.new(thick * 0.9, thick * 0.9, lowerLen), c1),
		End = newPart(folder, "End", c3.Size, c2),
	}
end

local function groundAt(pos)
	local r = workspace:Raycast(pos + Vector3.new(0, 2.5, 0), Vector3.new(0, -8, 0), rayParams)
	if r then return r.Position, r.Normal, r.Material end
	return pos - Vector3.new(0, 3, 0), Vector3.yAxis, Enum.Material.Plastic
end

local function hasPerk(char, name)
	local p = char:GetAttribute("Perks")
	return p ~= nil and string.find(p, name, 1, true) ~= nil
end

local function footstep(rig, pos, mat, speed)
	if hasPerk(rig.Char, "DeadSilence") then return end
	local id = Config.Footsteps[mat.Name] or Config.Footsteps.Default
	if not id or id == "" then return end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = Config.Footsteps.Volume * math.clamp(speed / 14, 0.3, 1.3)
	s.RollOffMaxDistance = 80
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency, p.Size, p.Position = true, false, false, false, 1, Vector3.one, pos
	p.Parent = workspace.CurrentCamera
	s.Parent = p
	s:Play()
	Debris:AddItem(p, 2)
end

-- ---------------------------------------------------------------- operator colors
-- The server sets the "Operator" character attribute (Cosmetics.luau). Sleeves, pants, boots, hands and the vest are recolored to match.
local function applyOperator(rig)
	local id = rig.Char:GetAttribute("Operator") or ""
	if rig.OperatorId == id then return end
	rig.OperatorId = id
	local op = Cosmetics.Operator(id)
	local sleeve, pants, boots, vest, skin = TPc.Sleeve, TPc.Pants, TPc.Boots, TPc.Vest, nil
	if op and not op.Avatar then
		sleeve, pants, boots, vest, skin = op.Sleeve, op.Pants, op.Boots, op.Vest, op.Skin
	else
		local bc = rig.Char:FindFirstChildOfClass("BodyColors")
		skin = bc and bc.RightArmColor3 or Color3.fromRGB(226, 176, 140)
	end
	for _, side in { "R", "L" } do
		local arm, leg = rig.Arms[side], rig.Legs[side]
		arm.Upper.Color, arm.Lower.Color, arm.End.Color = sleeve, sleeve, skin
		leg.Upper.Color, leg.Lower.Color, leg.End.Color = pants, pants, boots
	end
	rig.Vest.Color = vest
end

-- ---------------------------------------------------------------- rig lifecycle
local function hideDefaultLimbs(char, hide)
	for _, n in { "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local p = char:FindFirstChild(n)
		if p then p.LocalTransparencyModifier = hide and 1 or 0 end
	end
end

local function destroyRig(rig)
	rigs[rig.Char] = nil
	hideDefaultLimbs(rig.Char, false)
	if rig.RootJoint then rig.RootJoint.Transform = CFrame.identity end
	if rig.Neck then rig.Neck.Transform = CFrame.identity end
	rig.Folder:Destroy()
end

local function createRig(char)
	if rigs[char] then return end
	local plr = Players:GetPlayerFromCharacter(char)
	if plr == localPlayer and not TPc.ShowLocal and not ThirdPerson.LocalAllowed then return end
	local hum = char:WaitForChild("Humanoid", 10)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	local torso = char:WaitForChild("Torso", 10)
	local head = char:WaitForChild("Head", 10)
	if not (hum and root and torso and head) or hum.RigType ~= Enum.HumanoidRigType.R6 or rigs[char] then return end
	local rootJoint, neck = root:FindFirstChild("RootJoint"), torso:FindFirstChild("Neck")
	if not (rootJoint and neck) then return end

	local folder = Instance.new("Folder")
	folder.Name = "TP_" .. char.Name
	folder.Parent = workspace.CurrentCamera
	local bc = char:FindFirstChildOfClass("BodyColors")
	local skin = bc and bc.RightArmColor3 or Color3.fromRGB(226, 176, 140)

	local rig = {
		Char = char, Player = plr, Hum = hum, Root = root, Torso = torso, Head = head, RootJoint = rootJoint, Neck = neck, Folder = folder,
		Arms = {
			R = limb(folder, TPc.UpperArm, TPc.ForeArm, 0.7, TPc.Sleeve, skin, { Size = Vector3.new(0.55, 0.5, 0.6) }),
			L = limb(folder, TPc.UpperArm, TPc.ForeArm, 0.7, TPc.Sleeve, skin, { Size = Vector3.new(0.55, 0.5, 0.6) }),
		},
		Legs = {
			R = limb(folder, TPc.Thigh, TPc.Shin, 0.85, TPc.Pants, TPc.Boots, { Size = Vector3.new(0.8, 0.45, 1.1) }),
			L = limb(folder, TPc.Thigh, TPc.Shin, 0.85, TPc.Pants, TPc.Boots, { Size = Vector3.new(0.8, 0.45, 1.1) }),
		},
		Feet = { R = { Side = 1 }, L = { Side = -1 } },
		Vest = newPart(folder, "Vest", Vector3.new(2.1, 1.9, 1.15), TPc.Vest, Enum.Material.Fabric),
		VestFront = newPart(folder, "VestFront", Vector3.new(1.3, 1.1, 0.12), Color3.fromRGB(70, 74, 70), Enum.Material.Metal),
		VestBack = newPart(folder, "VestBack", Vector3.new(1.3, 1.1, 0.12), Color3.fromRGB(70, 74, 70), Enum.Material.Metal),
		Flash = newPart(folder, "Flash", Vector3.new(0.25, 0.25, 0.5), Color3.fromRGB(255, 205, 120), Enum.Material.Neon),
		Drop = 0, Fwd = 0, Roll = 0, Yaw = 0, Pitch = 0, Ads = 0, SprintA = 0, DownA = 0, CrawlA = 0, Peek = 0, FlashT = 0, RootDrop = 0, AnimCache = {},
	}
	rig.Flash.Transparency = 1
	rigs[char] = rig
	refreshFilter()
	hum.Died:Once(function() if rigs[char] == rig then destroyRig(rig) end end)
	char.AncestryChanged:Connect(function(_, parent) if not parent and rigs[char] == rig then destroyRig(rig) end end)
end

-- ---------------------------------------------------------------- per-frame helpers
local function setJoint(joint, parentCF, childCF)
	joint.Transform = (parentCF * joint.C0):Inverse() * childCF * joint.C1
end

-- attStr: comma separated attachment ids from the "WeaponAtt" character attribute (set by the server when a weapon is equipped)
local function ensureGun(rig, name, attStr)
	local key = name .. "|" .. (attStr or "")
	if rig.GunName == key then return end
	if rig.Gun then rig.Gun.Model:Destroy() end
	rig.Gun, rig.GunName, rig.AnimCache = nil, key, {}
	local cfg = Config.Weapons[name]
	if cfg then
		local ids = {}
		for id in string.gmatch(attStr or "", "[^,]+") do table.insert(ids, id) end
		rig.Gun = GunModel.Create(name, cfg, false, ids)
		rig.Gun.Model.Parent = rig.Folder
	end
end

local function ensureItem(rig, kind)
	if rig.ItemKind == kind then return end
	if rig.Item then rig.Item.Model:Destroy() end
	rig.Item, rig.ItemKind = nil, kind
	if kind ~= "" then
		rig.Item = ItemBuilder.Create(kind, ITEM_COLOR[kind])
		rig.Item.Model.Parent = rig.Folder
	end
end

local function cachedAnim(rig, action, cfg)
	local a = rig.AnimCache[action]
	if a then return a end
	local G = rig.Gun
	if action == "Reload" or action == "ReloadEmpty" then
		a = Anim.Reload(G, cfg.ReloadStyle == "None" and "Mag" or cfg.ReloadStyle, action == "ReloadEmpty")
		a.Kind = "Reload"
	elseif action == "ShellStart" or action == "ShellLoad" or action == "ShellEnd" then
		a = Anim.Shell(G, action:sub(6))
		a.Kind = "Shell"
	else
		local kind = action == "Pump" and "Pump" or "Bolt"
		a = Anim.Cycle(G, kind)
		a.Kind = kind
	end
	rig.AnimCache[action] = a
	return a
end

local function armIK(A, shoulder, handCF, hint)
	local elbow, wrist = IK.Solve(shoulder, handCF.Position, hint, TPc.UpperArm, TPc.ForeArm)
	local up = hint - elbow
	A.Upper.CFrame = IK.Segment(shoulder, elbow, TPc.UpperArm, up)
	A.Lower.CFrame = IK.Segment(elbow, wrist, TPc.ForeArm, up)
	A.End.CFrame = CF(wrist) * handCF.Rotation
end

-- ---------------------------------------------------------------- the big update
local function update(rig, dt)
	local char, root, hum = rig.Char, rig.Root, rig.Hum
	if not root.Parent or not rig.Torso.Parent or hum.Health <= 0 then
		destroyRig(rig)
		return
	end
	hideDefaultLimbs(char, true)
	applyOperator(rig)

	local realRootCF = root.CFrame
	local rootCF = realRootCF * CF(0, rig.RootDrop, 0) -- where the root would be if the body were standing: every pose below is relative to it
	local vel = root.AssemblyLinearVelocity
	local hv = Vector3.new(vel.X, 0, vel.Z)
	local spd = hv.Magnitude
	local stance = char:GetAttribute("Stance") or (spd > 1 and "Walk" or "Idle")
	local pitch = char:GetAttribute("AimPitch") or 0
	local adsT = char:GetAttribute("AdsAmt") or 0
	local weapon = char:GetAttribute("WeaponName") or ""
	local action = char:GetAttribute("Action") or ""
	local k = 1 - math.exp(-14 * dt)

	-- mantle / vault (ClimbPose.luau): the replicated ledge + progress give the torso targets and the world spots for hands and feet.
	-- A climb stance whose data has not arrived (or went stale) is drawn as an airborne body.
	local climb = ClimbPose.Read(char, stance)
	if not climb and ClimbPose.Stances[stance] then stance = "Air" end
	local cp = climb and ClimbPose.Solve(climb.Kind, climb.T, rootCF, climb.Ledge, climb.Depth)

	rig.Pitch += (pitch - rig.Pitch) * (1 - math.exp(-20 * dt))
	rig.Ads += (adsT - rig.Ads) * k
	-- how far the real root sits below standing height: the floor under it when standing on something, else the stance's own value
	local colT = COL[stance]
	local dropT = colT and colT.RootDrop or 0
	if stance ~= "Dive" and stance ~= "Air" and not cp then
		local hit = workspace:Raycast(realRootCF.Position, Vector3.new(0, -(STAND_ROOT_Y + 1), 0), rayParams)
		if hit and hit.Distance <= STAND_ROOT_Y + 0.6 then dropT = math.clamp(STAND_ROOT_Y - hit.Distance, 0, 2.6) end
	end
	rig.RootDrop += (dropT - rig.RootDrop) * k
	rig.Drop += ((cp and cp.Drop or DROP[stance] or 0) - rig.Drop) * k
	rig.Fwd += ((cp and cp.Fwd or FWD[stance] or 0) - rig.Fwd) * k
	rig.Yaw += ((cp and cp.Yaw or 0) - rig.Yaw) * k
	rig.SprintA += ((SPRINT[stance] or 0) - rig.SprintA) * k
	rig.DownA += ((LYING[stance] and 1 or 0) - rig.DownA) * k
	rig.CrawlA += ((stance == "Downed" and 1 or 0) - rig.CrawlA) * k -- only a downed player gets the one-handed crawl pose; prone keeps the hip / ADS aim
	local lv = realRootCF:VectorToObjectSpace(vel)
	rig.Roll += (math.clamp(-lv.X * 0.012, -0.22, 0.22) + (cp and cp.Roll or 0) - rig.Roll) * k
	local peekT = char:GetAttribute("PeekAmt")
	rig.Peek += ((type(peekT) == "number" and peekT or 0) - rig.Peek) * (1 - math.exp(-20 * dt)) -- corner peek lean (Q / E while aiming)
	local airborne = stance == "Air"

	-- emote (Emotes.luau): replaces the weapon pose while it plays; the server clears the attribute when it ends or you move
	local emoteId = char:GetAttribute("Emote") or ""
	local em, emW
	if emoteId ~= "" then
		em, emW = Emotes.Sample(emoteId, workspace:GetServerTimeNow() - (char:GetAttribute("EmoteStart") or 0))
		if em then weapon, action = "", "" end
	end
	local emTorso = em and em.Torso and CFrame.identity:Lerp(em.Torso, emW) or CFrame.identity
	local emHead = em and em.Head and CFrame.identity:Lerp(em.Head, emW) or CFrame.identity

	-- torso + head through the R6 joints
	local fwdLean = rig.Fwd - rig.Pitch * 0.35
	local torsoCF = rootCF * CF(0, -rig.Drop - 1, 0) * CFrame.Angles(0, rig.Yaw, 0) * CFrame.Angles(-fwdLean, 0, rig.Roll - rig.Peek * Config.Camera.Peek.Angle) * CF(0, 1, 0) * emTorso
	setJoint(rig.RootJoint, realRootCF, torsoCF)
	local headCF = torsoCF * CF(0, 1, 0) * CFrame.Angles(math.clamp(rig.Pitch * 0.7, -0.9, 0.9) + rig.DownA * 1.0, 0, 0) * emHead * CF(0, 0.5, 0)
	setJoint(rig.Neck, torsoCF, headCF)

	-- vest + plates
	local plates = char:GetAttribute("Plates") or 0
	rig.Vest.Transparency = plates > 0 and 0 or 1
	rig.VestFront.Transparency = plates >= 1 and 0 or 1
	rig.VestBack.Transparency = plates >= 2 and 0 or 1
	rig.Vest.CFrame = torsoCF * CF(0, 0.05, 0)
	rig.VestFront.CFrame = torsoCF * CF(0, 0.2, -0.62)
	rig.VestBack.CFrame = torsoCF * CF(0, 0.2, 0.62)

	-- weapon + action pose ------------------------------------------------
	local chestCF = torsoCF * CF(0, 0.4, 0)
	local aimCF = chestCF * CFrame.Angles(rig.Pitch * 0.65 + rig.DownA * rig.Fwd, 0, 0) -- undo the prone torso tilt so the gun points forward
	local reach = TPc.Reach
	ensureGun(rig, weapon, char:GetAttribute("WeaponAtt"))
	local G, cfg = rig.Gun, Config.Weapons[weapon]
	local shR = torsoCF * CF(0.9, 0.5, 0)
	local shL = torsoCF * CF(-0.9, 0.5, 0)
	local rightW, leftW
	local itemKind = char:GetAttribute("ActionItem") or ""
	ensureItem(rig, CHEST_TRACKS[action] and itemKind or "")

	if G and cfg then
		local gripL = G.LeftGripRel and G.LeftGripRel.Position or G.RightGripRel.Position
		local gripR = G.RightGripRel.Position
		local leftPos, rightPos = gripL, gripR
		local magOff, pumpOff, boltOff, magVisible, rAlpha = Vector3.zero, nil, nil, true, 0
		local dur = char:GetAttribute("ActionDur") or 0
		local start = char:GetAttribute("ActionStart") or 0
		local f = dur > 0 and math.clamp((workspace:GetServerTimeNow() - start) / dur, 0, 1) or 0
		local running = action ~= "" and (dur == 0 or f < 1)

		local Rt, Lt, drop, gOff, tw = nil, nil, 0, CFrame.identity, 0
		if running and CHEST_TRACKS[action] then
			local R, L, Gx, Dp, W = Anim.SampleTrack(action, f)
			Rt, Lt = chestCF * Anim.Scale(R, reach), chestCF * Anim.Scale(L, reach)
			drop, gOff, tw = Dp, Anim.Scale(Gx, reach), W
		elseif running and cfg.ReloadStyle ~= nil and action ~= "" then
			local a = cachedAnim(rig, action, cfg)
			local L, R, state = Anim.SampleKeys(a.Keys, f, gripL, gripR)
			leftPos, rightPos = L, R
			if a.Kind == "Reload" and G.MagRel then
				if state == "carry" then magOff = L - G.MagRel.Position
				elseif state == "hidden" then magVisible = false end
			elseif a.Kind == "Bolt" and G.Movers.Bolt and state == "carry" then
				boltOff = R - G.Movers.Bolt.Rel.Position
			elseif a.Kind == "Pump" then
				pumpOff = L - gripL
			end
			rAlpha = Anim.SampleScalar(a.Pose, f)
		end

		local melee = cfg.Class == "Melee"
		local pose = (melee and TPc.MeleePose or TPc.HipPose):Lerp(TPc.SprintPose, rig.SprintA)
		local adsA = melee and 0 or rig.Ads * (1 - rig.SprintA)
		pose = pose:Lerp(CF(0.1, 1.15, -0.6) * G.AimRel:Inverse(), adsA)
		pose = pose:Lerp(TPc.DownPose, rig.CrawlA)
		pose = pose:Lerp(TPc.DropPose, math.max(drop, cp and cp.GunDrop or 0))
		local gunCF = aimCF * gOff * pose * CFrame.identity:Lerp(TPc.ReloadTilt, rAlpha)
		GunModel.Pose(G, gunCF, magOff, pumpOff, boltOff, magVisible)

		rightW = gunCF * (CF(rightPos) * G.RightGripRel.Rotation)
		if G.OneHanded then
			leftW = chestCF * Anim.Scale(Anim.LeftRest, reach)
		else
			leftW = gunCF * (CF(leftPos) * G.LeftGripRot)
		end
		if Rt then
			rightW = rightW:Lerp(Rt, tw)
			leftW = leftW:Lerp(Lt, tw)
		end

		if rig.Item then
			local base
			if rig.Item.Mid then base = rightW:Lerp(leftW, 0.5) * CF(0, 0, -0.35) else base = rightW * CF(0, 0.05, -0.3) end
			ItemBuilder.Pose(rig.Item, base, 1 - math.clamp(tw * 2, 0, 1))
		end

		-- muzzle flash
		rig.FlashT = math.max(0, rig.FlashT - dt)
		rig.Flash.Transparency = rig.FlashT > 0 and 0.2 or 1
		if rig.FlashT > 0 then rig.Flash.CFrame = gunCF * G.MuzzleRel * CF(0, 0, -0.3) end
		rig.MuzzleCF = gunCF * G.MuzzleRel
	else
		rightW = chestCF * Anim.Scale(CF(0.22, -0.4, -0.2), reach)
		leftW = chestCF * Anim.Scale(CF(-0.22, -0.4, -0.2), reach)
	end

	if cp then -- mantle / vault: hands grip the ledge (the gun hand stays on the gun while the other hand plants)
		if cp.HandW.R > 0 then rightW = rightW:Lerp(cp.Hand.R, cp.HandW.R) end
		if cp.HandW.L > 0 then leftW = leftW:Lerp(cp.Hand.L, cp.HandW.L) end
	end

	if em then -- both hands follow the emote (an arm the pose does not use hangs by the side)
		rightW = rightW:Lerp(chestCF * (em.R or CF(0.98, -1.9, -0.15)), emW)
		leftW = leftW:Lerp(chestCF * (em.L or CF(-0.98, -1.9, -0.15)), emW)
	end

	local right, up = torsoCF.RightVector, torsoCF.UpVector
	local elbowDown = LYING[stance] and -Vector3.yAxis or up -- prone: elbows point up and out
	armIK(rig.Arms.R, shR.Position, rightW, shR.Position + right * 1.4 - elbowDown * 1.1)
	armIK(rig.Arms.L, shL.Position, leftW, shL.Position - right * 1.4 - elbowDown * 1.1)

	-- legs: foot planting ---------------------------------------------------
	local fwdFlat = Vector3.new(rootCF.LookVector.X, 0, rootCF.LookVector.Z).Unit
	local moveDir = spd > 0.5 and hv.Unit or fwdFlat
	local anySwing = rig.Feet.R.Swing or rig.Feet.L.Swing
	for _, name in { "R", "L" } do
		local f = rig.Feet[name]
		local side = f.Side
		local hip = (torsoCF * CF(side * 0.5, -1, 0)).Position
		local base = rootCF.Position + rootCF.RightVector * side * 0.5
		local totalLen = TPc.Thigh + TPc.Shin
		local ankleH = 0.2
		local ground, normal, mat = groundAt(base)
		local hipH = math.max(hip.Y - ground.Y - ankleH, 0.5)
		local maxHoriz = math.sqrt(math.max(0.1, (totalLen - 0.05) ^ 2 - hipH ^ 2))
		local stepHalf = math.min(0.7 + spd * 0.07, maxHoriz * 0.85)
		local target

		if airborne then
			f.Swing, f.Pos = false, nil
			target = hip + Vector3.new(0, -totalLen * 0.78, 0) + fwdFlat * (0.5 * side * -1 + 0.2)
			normal = Vector3.yAxis
		elseif cp then -- mantle / vault: feet follow the climb pose, then hand back to the floor as the body lands
			f.Swing, f.Pos = false, nil
			local gp, gn = groundAt(base)
			target, normal = gp + Vector3.new(0, ankleH, 0), gn
			if cp.FootW > 0 then
				target = target:Lerp(cp.Foot[name] + Vector3.new(0, ankleH, 0), cp.FootW)
				normal = normal:Lerp(Vector3.yAxis, cp.FootW)
			end
		elseif LYING[stance] then -- lying flat, legs trailing behind
			f.Swing, f.Pos = false, nil
			local p = base - fwdFlat * (1.7 + (side == 1 and 0.15 or 0)) + rootCF.RightVector * side * 0.25
			local gp, gn = groundAt(p)
			target, normal = gp + Vector3.new(0, ankleH + 0.05, 0), gn
			if stance == "Dive" then target, normal = Vector3.new(p.X, hip.Y, p.Z), Vector3.yAxis end -- a dive flies: legs trail at hip height
		elseif stance == "Slide" then
			f.Swing, f.Pos = false, nil
			local off = side == 1 and 1.9 or 0.3
			local p = base + fwdFlat * off
			local gp, gn = groundAt(p)
			target, normal = gp + Vector3.new(0, ankleH, 0), gn
			if side == 1 then target += Vector3.new(0, 0.25, 0) end
		else
			local ahead = spd > 0.5 and stepHalf * 0.8 or 0
			local idealGround, idealN, idealMat = groundAt(base + moveDir * ahead)
			if not f.Pos then f.Pos, f.Normal = idealGround, idealN end
			if f.Swing then
				f.T = math.min(1, f.T + dt / f.Dur)
				local e = f.T * f.T * (3 - 2 * f.T)
				local p = f.From:Lerp(idealGround, e)
				f.Pos = p + Vector3.new(0, math.sin(f.T * math.pi) * math.clamp(0.25 + spd * 0.03, 0.25, 0.7), 0)
				f.Normal = idealN
				if f.T >= 1 then
					f.Swing, f.Pos = false, idealGround
					footstep(rig, idealGround, idealMat, spd)
				end
			else
				local d = f.Pos - base
				local behind = -d:Dot(moveDir)
				local lateral = (d - moveDir * d:Dot(moveDir)).Magnitude
				local tooFar = (spd > 0.5 and (behind > stepHalf or lateral > 1.3)) or (spd <= 0.5 and Vector3.new(d.X, 0, d.Z).Magnitude > 1.0)
				tooFar = tooFar or (hip - f.Pos).Magnitude > (totalLen - 0.1) or math.abs(f.Pos.Y - idealGround.Y) > 1.2
				if tooFar and (not anySwing or spd > 14) then
					f.Swing, f.From, f.T = true, f.Pos, 0
					f.Dur = math.clamp(0.3 - spd * 0.008, 0.12, 0.3)
					anySwing = true
				end
			end
			target, normal = f.Pos + Vector3.new(0, ankleH, 0), f.Normal or Vector3.yAxis
		end

		local leg = rig.Legs[name]
		local kneeDir = torsoCF.LookVector
		if cp then kneeDir = kneeDir:Lerp(cp.Knee[name], cp.FootW) end -- tucked knees point where the climb pose says
		local hint = (hip + target) / 2 + (LYING[stance] and Vector3.new(0, 1.2, 0) or (kneeDir * 1.6 + Vector3.new(0, 0.3, 0)))
		local knee, ankle = IK.Solve(hip, target, hint, TPc.Thigh, TPc.Shin)
		local upv = hint - knee
		leg.Upper.CFrame = IK.Segment(hip, knee, TPc.Thigh, upv)
		leg.Lower.CFrame = IK.Segment(knee, ankle, TPc.Shin, upv)
		local fp = ankle + Vector3.new(0, -0.15, 0) + fwdFlat * 0.25
		leg.End.CFrame = CFrame.lookAt(fp, fp + fwdFlat, normal)
	end
end

-- ---------------------------------------------------------------- public
function ThirdPerson.OnFire(player) -- muzzle flash for remote shooters
	local rig = player and player.Character and rigs[player.Character]
	if rig then rig.FlashT = 0.05 end
end

-- your own body is hidden in first person; the emote camera turns it on for the length of the emote
function ThirdPerson.SetLocal(on)
	ThirdPerson.LocalAllowed = on
	local char = localPlayer.Character
	if not char then return end
	if on then
		if not rigs[char] then task.spawn(createRig, char) end
	elseif rigs[char] and not TPc.ShowLocal then
		destroyRig(rigs[char])
	end
end

function ThirdPerson.Start()
	local function watch(plr)
		plr.CharacterAdded:Connect(function(char)
			refreshFilter()
			task.spawn(createRig, char)
		end)
		if plr.Character then task.spawn(createRig, plr.Character) end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do watch(p) end
	Players.PlayerRemoving:Connect(function() task.defer(refreshFilter) end)
	refreshFilter()

	-- after Humanoid/Animator updates and after the camera, so our joint transforms win
	RunService:BindToRenderStep("FPS_ThirdPerson", Enum.RenderPriority.Camera.Value + 2, function(dt)
		for _, rig in rigs do update(rig, dt) end
	end)
end

return ThirdPerson
