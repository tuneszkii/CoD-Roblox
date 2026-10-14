-- Server side of lethal / tactical equipment, armor plates, projectiles and explosions.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local Config = require(RS:WaitForChild("FPS"):WaitForChild("Config"))
local Damage = require(script.Parent:WaitForChild("DamageService"))
local Hitbox = require(RS.FPS:WaitForChild("Hitbox"))
local PV = Config.PerkValues

local E = {}
local ctx
local Claymores, Projectiles, Zones, C4s = {}, {}, {}, {}
local Followers = {} -- thrown items stuck to a player: they ride along with the posed hitbox they hit
local nextId = 0

local function rootOf(char) return char and char:FindFirstChild("HumanoidRootPart") end
local function headOf(char) return char and (char:FindFirstChild("Head") or rootOf(char)) end
local function slotOf(s, slot)
	if slot == "Lethal" then return s.Lethal end
	if slot == "Tactical" then return s.Tactical end
	return nil
end
local function validVec(v, lo, hi)
	return typeof(v) == "Vector3" and v.Magnitude >= lo and v.Magnitude <= hi
end

-- ---------------------------------------------------------------- explosions
function E.Explode(pos, radius, maxD, minD, attacker, kind)
	if Config.Explosion.Builtin then
		local ex = Instance.new("Explosion")
		ex.BlastPressure, ex.DestroyJointRadiusPercent, ex.BlastRadius = 0, 0, math.min(radius * 0.6, 20)
		ex.ExplosionType = Enum.ExplosionType.NoCraters
		ex.Position = pos
		ex.Parent = workspace
	end
	local seen, hitOther, killedAny = {}, false, false
	local shot = attacker and ctx.Score.NewShotId(attacker)
	-- search wider than the radius: a crouched / downed body sits well away from its (standing) real parts
	for _, part in workspace:GetPartBoundsInRadius(pos, radius + Hitbox.Reach) do
		local model = part:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		if hum and not seen[hum] then
			seen[hum] = true
			local r = rootOf(model)
			local aim = r and (Hitbox.Center(model) or r.Position) -- chest of the posed body
			if aim and (aim - pos).Magnitude <= radius then
				local rp = RaycastParams.new()
				rp.FilterType = Enum.RaycastFilterType.Exclude
				rp.FilterDescendantsInstances = Hitbox.Exclusions({ model })
				rp.RespectCanCollide = true
				local from = pos + Vector3.new(0, 0.5, 0)
				if not workspace:Raycast(from, aim - from, rp) then
					local dist = (aim - pos).Magnitude
					local t = math.clamp(dist / radius, 0, 1)
					local dmg = maxD + (minD - maxD) * t
					local victim = Players:GetPlayerFromCharacter(model)
					if victim and victim == attacker then dmg *= Config.Explosion.SelfDamage end
					local killed = Damage.Apply(hum, dmg, attacker, kind or "Explosive", pos,
						{ Shot = shot, Dist = dist })
					if killed then killedAny = true end
					if victim ~= attacker then hitOther = true end
					if victim then ctx.Remotes.ExplosionFX:FireClient(victim, pos, 1 - t) end
				end
			end
		end
	end
	if hitOther and attacker and attacker.Parent then ctx.Remotes.HitConfirm:FireClient(attacker, false, killedAny) end
end

-- ---------------------------------------------------------------- zones (fire / gas / smoke)
local function makeZone(pos, radius, duration, kind, dps, owner)
	local folder = Instance.new("Folder")
	folder.Name = kind .. "Zone"
	folder.Parent = workspace
	local count = kind == "Smoke" and 3 or 5
	for i = 1, count do
		local a = (i / count) * math.pi * 2
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.Transparency, p.Size = true, false, false, false, 1, Vector3.one
		p.Position = pos + Vector3.new(math.cos(a), 0.5, math.sin(a)) * radius * 0.4
		p.Parent = folder
		local em = Instance.new("ParticleEmitter")
		em.EmissionDirection = Enum.NormalId.Top
		if kind == "Smoke" or kind == "Gas" then
			em.Texture = "rbxasset://textures/particles/smoke_main.dds"
			em.Color = ColorSequence.new(kind == "Gas" and Color3.fromRGB(150, 190, 80) or Color3.fromRGB(190, 192, 196))
			em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 0.5), NumberSequenceKeypoint.new(1, radius * 0.95) })
			em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1) })
			em.Rate, em.Lifetime, em.Speed, em.SpreadAngle = 14, NumberRange.new(5, 8), NumberRange.new(1, 3), Vector2.new(180, 180)
		else
			em.Texture = "rbxasset://textures/particles/fire_main.dds"
			em.Color = ColorSequence.new(Color3.fromRGB(255, 150, 40), Color3.fromRGB(255, 60, 20))
			em.LightEmission = 1
			em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0) })
			em.Rate, em.Lifetime, em.Speed, em.SpreadAngle = 40, NumberRange.new(0.6, 1.1), NumberRange.new(3, 7), Vector2.new(25, 25)
		end
		em.Parent = p
	end
	table.insert(Zones, { Pos = pos, Radius = radius, Expire = os.clock() + duration, Kind = kind, Dps = dps or 0, Owner = owner, Folder = folder, Next = 0 })
end

E.Zone = makeZone -- (pos, radius, duration, "Fire" | "Gas" | "Smoke", dps, owner): also used by the Chemical Strike kill streak

local function tickZone(z, now)
	if z.Dps <= 0 then return end
	for _, pl in Players:GetPlayers() do
		local aim = pl.Character and Hitbox.Center(pl.Character)
		local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
		if aim and hum and (aim - z.Pos).Magnitude <= z.Radius then
			Damage.Apply(hum, z.Dps * 0.5, z.Owner, z.Kind, z.Pos)
		end
	end
end

-- ---------------------------------------------------------------- detonation of a thrown item
local function detonate(rec)
	if rec.Done then return end
	rec.Done = true
	rec.Follow = nil
	local def, owner = rec.Def, rec.Owner
	local pos = rec.Part.Position
	rec.Part:Destroy()
	if C4s[owner] then
		local i = table.find(C4s[owner], rec)
		if i then table.remove(C4s[owner], i) end
		ctx.SyncEquip(owner)
	end
	if def.Damage then E.Explode(pos, def.Radius, def.Damage[1], def.Damage[2], owner, "Explosive") end
	if def.Fire then makeZone(pos, def.Fire.Radius, def.Fire.Duration, "Fire", def.Fire.Dps, owner) end
	local eff = def.Effect
	if eff == "Flash" or eff == "Stun" then
		ctx.Remotes.EquipFX:FireAllClients(eff, pos, def.Radius, def.Duration)
	elseif eff == "Smoke" then
		makeZone(pos, def.Radius, def.Duration, "Smoke")
	elseif eff == "Gas" then
		makeZone(pos, def.Radius, def.Duration, "Gas", def.Dps, owner)
		ctx.Remotes.EquipFX:FireAllClients("Gas", pos, def.Radius, def.Duration)
	end
end

local function spawnThrown(plr, def, name, origin, dir, fuse)
	local char = plr.Character
	local p = Instance.new("Part")
	p.Name = name
	if def.Detonator then p.Size = Vector3.new(0.8, 0.4, 0.6) else p.Shape, p.Size = Enum.PartType.Ball, Vector3.one * 0.7 end
	p.Color, p.Material = def.Color, Enum.Material.Metal
	p.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.6, 0.35, 1, 1)
	p.CFrame = CFrame.new(origin + dir * 2.2)
	p.CanQuery = false
	p.Parent = workspace
	p:SetNetworkOwner(nil)
	p.AssemblyLinearVelocity = dir * def.Speed
	p.AssemblyAngularVelocity = Vector3.new(math.random() * 20 - 10, math.random() * 20 - 10, math.random() * 20 - 10)
	Hitbox.TrackPhysical(p) -- collides with the posed (crouched / prone ...) bodies instead of the standing R6 parts

	local ncs = {}
	local ownParts = char:GetDescendants()
	for _, proxy in Hitbox.ProxyParts(char) do table.insert(ownParts, proxy) end
	for _, d in ownParts do -- do not collide with the thrower right after the throw
		if d:IsA("BasePart") then
			local nc = Instance.new("NoCollisionConstraint")
			nc.Part0, nc.Part1, nc.Parent = p, d, p
			table.insert(ncs, nc)
		end
	end
	task.delay(0.35, function() for _, nc in ncs do nc:Destroy() end end)

	local rec = { Part = p, Def = def, Owner = plr, Done = false }
	rec.Detonate = function() detonate(rec) end
	if def.Sticky or def.Impact then
		p.Touched:Connect(function(hit)
			if rec.Stuck or rec.Impacted or rec.Done or not hit.CanCollide then return end
			local body = Hitbox.ProxyInfo(hit) -- { Char, Name } when we touched a posed hitbox
			if (hit:IsDescendantOf(char) or (body and body.Char == char)) and os.clock() - (rec.T0 or 0) < 0.5 then return end
			if def.Sticky then
				rec.Stuck = true
				p.AssemblyLinearVelocity, p.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
				local box = body and Hitbox.BoxCFrame(body.Char, body.Name)
				if box then -- stuck to a player: ride along with that part of the posed body
					rec.Follow = { Char = body.Char, Name = body.Name, Off = box:ToObjectSpace(p.CFrame) }
					p.Anchored = true
					table.insert(Followers, rec)
				elseif hit.Anchored or body then
					p.Anchored = true
				else
					local w = Instance.new("WeldConstraint")
					w.Part0, w.Part1, w.Parent = p, hit, p
				end
			else
				rec.Impacted = true
				task.delay(def.Delay or 0, rec.Detonate)
			end
		end)
	end
	rec.T0 = os.clock()
	if def.Fuse then task.delay(fuse or def.Fuse, rec.Detonate) end
	if def.Detonator then
		C4s[plr] = C4s[plr] or {}
		table.insert(C4s[plr], rec)
	end
	Debris:AddItem(p, 60)
	return rec
end

-- stuck-on items (Semtex, C4, thermite) are anchored and moved every frame to stay on the body part they hit
local function stepFollowers()
	for i = #Followers, 1, -1 do
		local rec = Followers[i]
		local f = rec.Follow
		local cf = f and not rec.Done and Hitbox.BoxCFrame(f.Char, f.Name)
		if cf and rec.Part.Parent then
			rec.Part.CFrame = cf * f.Off
		else
			table.remove(Followers, i)
			if not rec.Done and rec.Part.Parent then -- the carrier died / left: the item drops
				rec.Follow = nil
				rec.Part.Anchored = false
			end
		end
	end
end

-- ---------------------------------------------------------------- projectiles (analytic path, shared with the client visuals)
function E.Launch(plr, kind, origin, dir, speed, gravity, onHit)
	nextId += 1
	local id = ("%d:%d"):format(plr.UserId, nextId)
	local vel = dir.Unit * speed
	local t0 = workspace:GetServerTimeNow()
	Projectiles[id] = { Id = id, Owner = plr, Kind = kind, Origin = origin, Vel = vel, G = gravity, T0 = t0, Prev = origin, OnHit = onHit }
	ctx.Remotes.ProjectileSpawn:FireAllClients(id, kind, origin, vel, gravity, t0)
end

local function stepProjectiles()
	local now = workspace:GetServerTimeNow()
	for id, pr in Projectiles do
		local t = now - pr.T0
		if t > 10 or not pr.Owner.Parent then
			Projectiles[id] = nil
			ctx.Remotes.ProjectileEnd:FireAllClients(id, pr.Prev, Vector3.yAxis, "Expire")
		else
			local pos = pr.Origin + pr.Vel * t + Vector3.new(0, -0.5 * pr.G * t * t, 0)
			local d = pos - pr.Prev
			if d.Magnitude > 0.01 then
				local ignore = (t < 0.25 and pr.Owner.Character) and { pr.Owner.Character } or {}
				local res = Hitbox.Raycast(pr.Prev, d, ignore, true) -- walls + pose-aware player bodies
				if res then
					Projectiles[id] = nil
					ctx.Remotes.ProjectileEnd:FireAllClients(id, res.Position, res.Normal, pr.Kind)
					pr.OnHit(res.Position, res.Normal, res.Instance)
				else
					pr.Prev = pos
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- claymores
local function claymoreCount(plr)
	local n = 0
	for _, c in Claymores do if c.Owner == plr then n += 1 end end
	return n
end

local function stepClaymores(now)
	for i = #Claymores, 1, -1 do
		local c = Claymores[i]
		if not c.Part.Parent or not c.Owner.Parent then
			c.Part:Destroy()
			table.remove(Claymores, i)
		elseif now >= c.ArmAt and not c.Triggered then
			local cf, def = c.Part.CFrame, c.Def
			for _, pl in Players:GetPlayers() do
				local aim = pl.Character and Hitbox.Center(pl.Character) -- chest of the posed body (a prone player is low)
				local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
				if aim and hum and hum.Health > 0 and pl ~= c.Owner and not Damage.IsFriendly(c.Owner, pl) then
					local to = aim - cf.Position
					if to.Magnitude <= def.Range and math.deg(math.acos(math.clamp(cf.LookVector:Dot(to.Unit), -1, 1))) <= def.Angle then
						local rp = RaycastParams.new()
						rp.FilterType = Enum.RaycastFilterType.Exclude
						rp.FilterDescendantsInstances = Hitbox.Exclusions({ c.Part, pl.Character })
						rp.RespectCanCollide = true
						if not workspace:Raycast(cf.Position, to, rp) then
							c.Triggered = true
							task.delay(0.2, function()
								if not c.Part.Parent then return end
								local pos = c.Part.Position
								c.Part:Destroy()
								E.Explode(pos + Vector3.new(0, 0.5, 0), def.Radius, def.Damage[1], def.Damage[2], c.Owner, "Explosive")
							end)
							break
						end
					end
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- remote handlers
local function stateFor(plr)
	local s = ctx.State[plr]
	if s and s.Ready and not s.Down then return s end -- downed players cannot use equipment or plates
	return nil
end

local function cancelPlating(s)
	if s.Plating then s.Plating = nil end
end

local function onBegin(plr, slot)
	local s = stateFor(plr)
	local e = s and slotOf(s, slot)
	local def = e and Config.Equipment[e.Name]
	if not def or def.Mode ~= "Throw" or e.Count <= 0 or s.Cook then return end
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return end
	cancelPlating(s)
	s.Cook = { Slot = slot, Start = os.clock() }
end

local function onThrow(plr, slot, origin, dir)
	local s = stateFor(plr)
	local cook = s and s.Cook
	if not cook or cook.Slot ~= slot then return end
	s.Cook = nil
	local e = slotOf(s, slot)
	local def = e and Config.Equipment[e.Name]
	local char = plr.Character
	local head = headOf(char)
	if not def or def.Mode ~= "Throw" or e.Count <= 0 or not head then return end
	if typeof(origin) ~= "Vector3" or not validVec(dir, 0.5, 1.5) or (origin - head.Position).Magnitude > 12 then return end
	local C4 = C4s[plr] or {}
	if def.Detonator and #C4 >= def.Max then return end
	local elapsed = os.clock() - cook.Start
	if elapsed < def.PullTime * 0.5 then return end
	local cooked = math.max(0, elapsed - def.PullTime)
	e.Count -= 1
	dir = dir.Unit
	if def.Projectile then
		local pj = def.Projectile
		E.Launch(plr, "Knife", origin, dir, pj.Speed, pj.Gravity, function(pos, normal, inst)
			local model = inst:FindFirstAncestorOfClass("Model")
			local hum = model and model:FindFirstChildOfClass("Humanoid")
			if hum then
				local killed = Damage.Apply(hum, pj.Damage, plr, "Melee", origin,
					{ Head = inst.Name == "Head", Dist = (pos - origin).Magnitude })
				ctx.Remotes.HitConfirm:FireClient(plr, inst.Name == "Head", killed)
			end
		end)
	elseif def.Cook and def.Fuse and cooked >= def.Fuse then
		E.Explode(head.Position, def.Radius, def.Damage[1], def.Damage[2], plr, "Explosive")
	else
		local fuse = nil
		if def.Fuse then fuse = def.Cook and math.max(0.1, def.Fuse - cooked) or def.Fuse end
		spawnThrown(plr, def, e.Name, origin, dir, fuse)
	end
	ctx.SyncEquip(plr)
end

local function onUse(plr, slot)
	local s = stateFor(plr)
	local e = s and slotOf(s, slot)
	local def = e and Config.Equipment[e.Name]
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not def or def.Mode ~= "Use" or e.Count <= 0 or not hum or hum.Health <= 0 then return end
	e.Count -= 1
	if def.Effect == "Stim" then
		hum.Health = math.min(hum.MaxHealth, hum.Health + def.Heal)
		ctx.Remotes.EquipFX:FireClient(plr, "Stim", def.Duration, def.SpeedMult)
	elseif def.Effect == "Sensor" then
		task.spawn(function()
			local elapsed = 0
			while elapsed < def.Duration and plr.Parent do
				local me = rootOf(plr.Character)
				if not me then break end
				local list = {}
				for _, other in Players:GetPlayers() do
					local r = other ~= plr and rootOf(other.Character)
					local os_ = ctx.State[other]
					if r and (r.Position - me.Position).Magnitude <= def.Radius and r.AssemblyLinearVelocity.Magnitude > 2
						and not (os_ and Config.Has(os_.Perks, "Ghost")) then
						table.insert(list, r.Position)
					end
				end
				if #list > 0 then ctx.Remotes.SensorPing:FireClient(plr, list) end
				task.wait(0.7)
				elapsed += 0.7
			end
		end)
	end
	ctx.SyncEquip(plr)
end

local function onPlace(plr, slot, origin, dir)
	local s = stateFor(plr)
	local e = s and slotOf(s, slot)
	local def = e and Config.Equipment[e.Name]
	local char = plr.Character
	local head = headOf(char)
	if not def or def.Mode ~= "Plant" or e.Count <= 0 or not head then return end
	if typeof(origin) ~= "Vector3" or not validVec(dir, 0.5, 1.5) or (origin - head.Position).Magnitude > 12 then return end
	if claymoreCount(plr) >= def.Max then return end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = Hitbox.Exclusions({ char }) -- other players' standing phantom bodies are not walls
	local hit = workspace:Raycast(origin, dir.Unit * 9, rp)
	if not hit then return end
	e.Count -= 1
	local face = Vector3.new(dir.X, 0, dir.Z)
	face = face.Magnitude > 0.05 and face.Unit or Vector3.new(0, 0, -1)
	local pos = hit.Position + hit.Normal * 0.3
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color, p.Material = "Claymore", Vector3.new(1.1, 0.6, 0.25), def.Color, Enum.Material.SmoothPlastic
	p.Anchored, p.CanCollide, p.CanQuery = true, false, false
	p.CFrame = CFrame.lookAt(pos, pos + face)
	p.Parent = workspace
	table.insert(Claymores, { Part = p, Owner = plr, Def = def, ArmAt = os.clock() + def.Arm, Triggered = false })
	ctx.SyncEquip(plr)
end

local function onDetonate(plr)
	local list = C4s[plr]
	if not list then return end
	local copy = table.clone(list)
	for _, rec in copy do rec.Detonate() end
end

local function onPlateStart(plr)
	local s = stateFor(plr)
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not s or s.Plating or s.Cook or s.Plates <= 0 or not hum or hum.Health <= 0 then return end
	local maxArmor = Config.Armor.PlateArmor * Config.Armor.MaxEquipped
	if s.Armor >= maxArmor then return end
	local token = {}
	s.Plating = token
	local dur = Config.Armor.ApplyTime * (Config.Has(s.Perks, "QuickFix") and PV.QuickFixPlate or 1)
	task.delay(dur * 0.92, function()
		if ctx.State[plr] ~= s or s.Plating ~= token then return end
		s.Plating = nil
		if hum.Health <= 0 or s.Plates <= 0 then return end
		s.Plates -= 1
		s.Armor = math.min(maxArmor, s.Armor + Config.Armor.PlateArmor)
		Damage.SyncArmor(plr)
	end)
end

local function onPlateCancel(plr)
	local s = stateFor(plr)
	if s then cancelPlating(s) end
end

function E.CancelActions(s) -- weapon switch etc.
	s.Plating, s.Cook = nil, nil
end

function E.Cleanup(plr)
	C4s[plr] = nil
	for i = #Claymores, 1, -1 do
		if Claymores[i].Owner == plr then
			Claymores[i].Part:Destroy()
			table.remove(Claymores, i)
		end
	end
end

function E.C4Count(plr) return C4s[plr] and #C4s[plr] or 0 end

function E.Init(c)
	ctx = c
	local R = ctx.Remotes
	R.EquipBegin.OnServerEvent:Connect(onBegin)
	R.EquipThrow.OnServerEvent:Connect(onThrow)
	R.EquipUse.OnServerEvent:Connect(onUse)
	R.EquipPlace.OnServerEvent:Connect(onPlace)
	R.Detonate.OnServerEvent:Connect(onDetonate)
	R.PlateStart.OnServerEvent:Connect(onPlateStart)
	R.PlateCancel.OnServerEvent:Connect(onPlateCancel)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		stepProjectiles()
		stepFollowers()
		acc += dt
		local now = os.clock()
		if acc >= 0.1 then
			acc = 0
			stepClaymores(now)
			for i = #Zones, 1, -1 do
				local z = Zones[i]
				if now > z.Expire then
					z.Folder:Destroy()
					table.remove(Zones, i)
				elseif now >= z.Next then
					z.Next = now + 0.5
					tickZone(z, now)
				end
			end
			for plr, s in ctx.State do -- grenade cooked off in the hand
				local cook = s.Cook
				if cook then
					local e = slotOf(s, cook.Slot)
					local def = e and Config.Equipment[e.Name]
					if def and def.Cook and def.Fuse and now - cook.Start - def.PullTime >= def.Fuse + 0.2 then
						s.Cook = nil
						e.Count = math.max(0, e.Count - 1)
						local head = headOf(plr.Character)
						if head then E.Explode(head.Position, def.Radius, def.Damage[1], def.Damage[2], plr, "Explosive") end
						ctx.SyncEquip(plr)
					end
				end
			end
		end
	end)
end

return E
