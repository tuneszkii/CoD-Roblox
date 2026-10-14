-- BulletService: server side of real (ballistic) bullets.
-- A trigger pull no longer resolves instantly: each pellet becomes a bullet that flies the analytic path from Ballistics.luau
-- (muzzle velocity, gravity, air drag that bleeds speed off with flight time). Every Heartbeat the bullet's new position is computed
-- and a ray is cast over the distance it covered (Hitbox.Raycast: world geometry + the pose-aware player bodies), so a fast bullet can
-- never tunnel through a wall or a player. Damage uses the same falloff tables as before, measured in studs travelled from the muzzle.
-- Bullets do not simply stop on the first thing they hit: Penetration.Trace lets them punch through thin walls (wallbangs) and through
-- several bodies (collateral), each surface costing the bullet Power and damage. Every pellet carries its own state + ignore list.
-- Weapons that are hitscan (Config.Ballistics.Enabled = false, `Hitscan = true`) never get here: FPSServer resolves those instantly.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local FPS = RS:WaitForChild("FPS")
local Config = require(FPS:WaitForChild("Config"))
local Hitbox = require(FPS:WaitForChild("Hitbox"))
local Ballistics = require(FPS:WaitForChild("Ballistics"))
local Penetration = require(FPS:WaitForChild("Penetration"))
local Damage = require(script.Parent:WaitForChild("DamageService"))
local Data = require(script.Parent:WaitForChild("DataService"))

local B = {}
local ctx
local live = {}     -- bullets in flight (array, swap-remove)
local confirms = {} -- [player] = { Head, Kill }: hit markers gathered during one step (a shotgun blast gives one marker, not eight)
local lastCrack = setmetatable({}, { __mode = "k" }) -- [player] = os.clock() of the last Suppress event sent (per-player cooldown)

-- one trigger pull = one record; accuracy stats are written when its last bullet has landed or expired
local function settle(b)
	local rec = b.Rec
	rec.Pending -= 1
	if rec.Pending <= 0 then Data.RecordShot(rec.Plr, rec.Name, rec.Hit, rec.Head) end
end

-- Penetration.Trace body hook: bullet b struck one living body. st = the bullet's penetration state (st.Mult = damage left after the
-- walls / bodies it already went through; st.Walls > 0 = it came through a wall, i.e. a wallbang).
local function hit(b, res, st)
	local plr, cfg, rec = b.Plr, b.Cfg, b.Rec
	local model = res.Instance:FindFirstAncestorOfClass("Model")
	local vh = model and model:FindFirstChildOfClass("Humanoid")
	if not (vh and vh.Health > 0) then return end
	local nm = res.Instance.Name
	local mult = 1
	if nm == "Head" then mult = cfg.HeadMult
	elseif nm:find("Leg") or nm:find("Foot") then mult = 0.9 end
	local dist = (res.Position - b.Origin).Magnitude
	local dead = Damage.Apply(vh, Ballistics.Falloff(cfg.Damage, dist) * mult * st.Mult, plr, "Bullet", b.Origin,
		{ Head = nm == "Head", Dist = dist, Shot = b.Shot, Wallbang = st.Walls > 0, ArmorPierce = cfg.ArmorPierce })
	if not dead and cfg.Burn then Damage.Burn(vh, plr, cfg.Burn, b.Origin) end
	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		b.Struck = b.Struck or {}
		b.Struck[victim] = true -- a bullet that hit you is damage, not a near miss
	end
	if victim and Damage.IsFriendly(plr, victim) then return end
	rec.Hit, rec.Head = true, rec.Head or nm == "Head"
	local c = confirms[plr]
	if not c then
		c = { Head = false, Kill = false }
		confirms[plr] = c
	end
	c.Head = c.Head or nm == "Head"
	c.Kill = c.Kill or not not dead
end

local hooks = { Body = hit }

-- ---------------------------------------------------------------- near misses (suppression)
-- Closest distance from point p to the segment a->b.
local function segDist(a, b, p)
	local ab = b - a
	local len2 = ab:Dot(ab)
	if len2 < 1e-6 then return (p - a).Magnitude end
	local t = math.clamp((p - a):Dot(ab) / len2, 0, 1)
	return (p - (a + ab * t)).Magnitude
end

-- Tell every enemy the segment a->b cracked past (but did not hit) to flinch. Lighter than a hit: the client scales it down.
local function crack(b, a, c, speed)
	local S = Config.Suppression
	if not S or not S.Enabled or speed < S.MinSpeed then return end
	local now = os.clock()
	for _, victim in Players:GetPlayers() do
		if victim == b.Plr or (b.Struck and b.Struck[victim]) or Damage.IsFriendly(b.Plr, victim) then continue end
		if now - (lastCrack[victim] or 0) < S.Cooldown then continue end
		local char = victim.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local head = char and char:FindFirstChild("Head")
		if not hum or hum.Health <= 0 or not head or char:GetAttribute("Down") then continue end
		local d = segDist(a, c, head.Position)
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then d = math.min(d, segDist(a, c, root.Position) + 1) end -- chest passes count a little less than head passes
		if d < S.Radius then
			lastCrack[victim] = now
			ctx.Remotes.Suppress:FireClient(victim, 1 - d / S.Radius, b.Origin)
		end
	end
end

local function step()
	if #live == 0 then return end
	local now = workspace:GetServerTimeNow()
	local void = workspace.FallenPartsDestroyHeight
	for i = #live, 1, -1 do
		local b = live[i]
		local t = now - b.T0
		local done = false
		if t > b.Life or not b.Plr.Parent then
			done = true
		else
			local pos = Ballistics.Pos(b.Origin, b.Vel, b.G, b.K, t)
			local seg = pos - b.Prev
			if seg.Magnitude > 0.01 then
				-- walls + pose-aware bodies along the stretch flown this frame; it may punch through some of them (Penetration.Trace)
				local _, stopped = Penetration.Trace(b.Prev, seg, b.Ignore, b.Pen, hooks, b)
				crack(b, b.Prev, pos, Ballistics.Vel(b.Vel, b.G, b.K, t).Magnitude)
				if stopped then
					done = true
				else
					b.Prev = pos
					if (pos - b.Origin).Magnitude > b.Range or pos.Y < void then done = true end
				end
			end
		end
		if done then
			live[i] = live[#live]
			live[#live] = nil
			settle(b)
		end
	end
	for plr, c in confirms do
		if plr.Parent then ctx.Remotes.HitConfirm:FireClient(plr, c.Head, c.Kill) end
		confirms[plr] = nil
	end
end

-- Spawns one bullet per pellet. origin = shooter's aim origin (validated by the caller), dirs = client aim directions.
-- Returns the muzzle velocities that were actually launched + the launch time (the clients draw the same path from these).
function B.Fire(plr, name, cfg, bal, origin, dirs, shotId)
	local char = plr.Character
	local t0 = workspace:GetServerTimeNow()
	local rec = { Plr = plr, Name = name, Pending = 0, Hit = false, Head = false }
	local vels = {}
	local power = Penetration.PowerOf(cfg)
	for i, d in dirs do
		if i > (cfg.Pellets or 1) then break end
		if typeof(d) == "Vector3" and d.Magnitude > 0.5 and d.Magnitude < 1.5 then
			local v = d.Unit * bal.Speed
			table.insert(vels, v)
			rec.Pending += 1
			table.insert(live, {
				Rec = rec, Plr = plr, Cfg = cfg, Origin = origin, Prev = origin, Vel = v, G = bal.Gravity, K = bal.Drag, T0 = t0,
				Life = bal.Lifetime, Range = cfg.Range, Shot = shotId, Ignore = { char }, Pen = Penetration.New(power),
			})
		end
	end
	if rec.Pending == 0 then Data.RecordShot(plr, name, false, false) end -- nothing valid to launch: still counts as a shot
	while #live > Config.Ballistics.MaxLive do -- safety cap: drop the oldest
		local old = table.remove(live, 1)
		settle(old)
	end
	return vels, t0
end

function B.Init(c)
	ctx = c
	RunService.Heartbeat:Connect(step)
end

return B
