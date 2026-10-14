-- Procedural mantle / vault poses, shared by the first-person viewmodel (hands), the third-person rig (whole body) and the server hitboxes.
--
-- Movement.luau drives the body along the climb path; this module only answers "what does the body look like at progress t?".
-- Everything is derived from three things that are cheap to replicate: the ledge (a CFrame at the lip, looking into the wall), how deep the
-- obstacle is, and the climb progress t (0..1). Hands and feet are WORLD targets on the ledge, so they stay planted on it while the body moves
-- along the path. Torso lean / drop / roll / yaw are returned as numbers the caller smooths and applies through its own torso maths
-- (ThirdPerson.luau and Hitbox.luau use the same formula, so what players see is what bullets hit). Curves live in Config.Climb.
--
--   Mantle  reach (hands find the lip, body hangs) -> pull (chest to the ledge, rear knee comes up) -> press (hands on top, body rolls over)
--           -> stand (hands let go, feet take the floor)
--   Vault   lean in, support hand plants on the obstacle, torso rolls over that hand while both legs swing out to the other side and tuck,
--           hand lets go, legs reach for the floor
local Config = require(script.Parent.Config)
local Anim = require(script.Parent.Anim)

local CC = Config.Climb
local MC = Config.Movement.Mantle
local S = Anim.SampleScalar
local V3 = Vector3.new
local UP = Vector3.yAxis

local ClimbPose = {}

ClimbPose.Stances = { Mantle = true, Vault = true }

-- Read the climb a character is replicating (server-validated attributes, see FPSServer StateSync).
-- Returns { Kind, T, Ledge, Depth } or nil when the stance is not a climb or the data has not arrived / has gone stale.
function ClimbPose.Read(char, stance)
	if not ClimbPose.Stances[stance] then return nil end
	local ledge, start, dur = char:GetAttribute("ClimbLedge"), char:GetAttribute("ClimbStart"), char:GetAttribute("ClimbDur")
	if typeof(ledge) ~= "CFrame" or type(start) ~= "number" or type(dur) ~= "number" or dur <= 0 then return nil end
	local depth = char:GetAttribute("ClimbDepth")
	return {
		Kind = stance,
		T = math.clamp((workspace:GetServerTimeNow() - start) / dur, 0, 1),
		Ledge = ledge,
		Depth = type(depth) == "number" and depth or 0,
	}
end

local function mantleHand(lp, dir, right, side, slide)
	local lip = lp + right * (side * CC.GripSpread) + dir * 0.05 -- fingers curled over the edge
	local top = lp + right * (side * (CC.GripSpread + 0.05)) + dir * 0.6 -- flat on the top surface, beside the hips
	local pos = lip:Lerp(top, slide) + V3(0, 0.05, 0)
	return CFrame.lookAt(pos, pos + dir)
end

-- s: 0 = foot hanging against the wall face, 1 = foot on the ledge. The foot lifts on the way (the knee comes up first).
local function mantleFoot(rootPos, lp, dir, right, side, s)
	local hang = lp - dir * 0.55 + right * (side * 0.35)
	hang = V3(hang.X, rootPos.Y - 2.6, hang.Z)
	local onLedge = lp + dir * 0.55 + right * (side * 0.35)
	return hang:Lerp(onLedge, s) + V3(0, math.sin(math.pi * s) * 0.7, 0)
end

-- kind: "Mantle" | "Vault"   t: progress 0..1   rootCF: the root as if standing (callers undo their stance RootDrop)
-- ledge: CFrame at the lip, looking into the wall   depth: how far the obstacle's top runs (vault only)
-- Returns {
--   Drop, Fwd, Roll, Yaw      torso targets (studs / rad). Roll is signed so + leans the torso to the left, like CFrame.Angles
--   GunDrop                   0..1, lower the gun out of the way
--   HandW = { R, L }          0..1 how far each hand is on Hand instead of on the gun
--   Hand  = { R, L }          world CFrames (palm down, fingers along the climb direction)
--   FootW                     0..1 how far the feet are on Foot instead of on the floor
--   Foot  = { R, L }          world positions of the soles (callers add their own ankle height)
--   Knee  = { R, L }          world unit vectors the knees point along
-- }
function ClimbPose.Solve(kind, t, rootCF, ledge, depth)
	local root = rootCF.Position
	local lp = ledge.Position
	local look = ledge.LookVector
	local dir = V3(look.X, 0, look.Z)
	dir = dir.Magnitude > 0.01 and dir.Unit or V3(0, 0, -1)
	local right = dir:Cross(UP) -- Roblox: right = look x up

	local P = { HandW = {}, Hand = {}, Foot = {}, Knee = {} }
	local yawW

	if kind == "Mantle" then
		local c = CC.Mantle
		-- key the curves on "climb time" so the hang-over-the-ledge moment sits at 0.55 even if RiseShare is retuned
		local r = math.clamp(MC.RiseShare, 0.05, 0.95)
		local tt = t < r and 0.55 * t / r or 0.55 + 0.45 * (t - r) / (1 - r)
		P.Drop, P.Fwd, P.Roll, P.GunDrop = S(c.Drop, tt), S(c.Fwd, tt), 0, S(c.GunDrop, tt)
		local hw, slide = S(c.HandW, tt), S(c.HandSlide, tt)
		P.HandW.R, P.HandW.L = hw, hw
		P.Hand.R, P.Hand.L = mantleHand(lp, dir, right, 1, slide), mantleHand(lp, dir, right, -1, slide)
		P.FootW = S(c.FootW, tt)
		P.Foot.R = mantleFoot(root, lp, dir, right, 1, S(c.FootR, tt))
		P.Foot.L = mantleFoot(root, lp, dir, right, -1, S(c.FootL, tt))
		local knee = (dir * 0.8 + UP * 0.5).Unit
		P.Knee.R, P.Knee.L = knee, knee
		yawW = 1
	else
		local c = CC.Vault
		local handSide = CC.VaultHand == "R" and 1 or -1 -- the planting hand's side; the legs swing the other way
		P.Drop, P.Fwd, P.GunDrop = S(c.Drop, t), S(c.Fwd, t), S(c.GunDrop, t)
		P.Roll = S(c.Roll, t) * -handSide -- lean toward the planting hand
		local hw = S(c.HandW, t)
		P.HandW.R, P.HandW.L = handSide == 1 and hw or 0, handSide == -1 and hw or 0
		-- the hand plants near the near edge and, on a thick obstacle, slides forward as the body passes over it
		local slide = Anim.Sm(0.2, 0.6, t)
		local reach = depth > 0.8 and (0.35 + (math.min(depth * 0.45, 1.4) - 0.35) * slide) or math.min(0.35, depth * 0.5)
		local plant = lp + dir * reach + right * (handSide * 0.4) + V3(0, 0.05, 0)
		local plantCF = CFrame.lookAt(plant, plant + dir)
		P.Hand.R, P.Hand.L = plantCF, plantCF
		P.FootW = S(c.FootW, t)
		local swing, tuck = S(c.Swing, t), S(c.Tuck, t)
		local hipC = root - V3(0, P.Drop + 1, 0) -- the torso pivots on the hips, so this does not depend on the lean
		local legSide = -handSide
		for _, leg in { { "R", 1, 1 }, { "L", -1, 0.85 } } do -- the right leg leads the swing a little
			local name, side, k = leg[1], leg[2], leg[3]
			local phi = swing * k
			local len = 2 * (1 - 0.35 * tuck)
			local hip = hipC + right * (side * 0.5)
			P.Foot[name] = hip + (right * (legSide * math.sin(phi)) - UP * math.cos(phi)) * len + dir * (0.25 + 0.35 * tuck)
			P.Knee[name] = (dir * 0.7 + UP * 0.6 + right * (legSide * math.sin(phi) * 0.3)).Unit
		end
		yawW = S(c.Yaw, t)
	end

	-- turn the shoulders toward the wall (the player may be facing up to ~60 degrees off it). Positive yaw turns left, like CFrame.Angles.
	local lk = rootCF.LookVector
	local flat = V3(lk.X, 0, lk.Z)
	P.Yaw = 0
	if flat.Magnitude > 0.05 then
		flat = flat.Unit
		P.Yaw = math.clamp(math.atan2(flat:Cross(dir).Y, flat:Dot(dir)), -0.9, 0.9) * yawW
	end
	return P
end

return ClimbPose
