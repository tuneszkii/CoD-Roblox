-- AttachmentVisuals: draws attachments on a weapon model (code-built placeholders, like GunBuilder).
-- GunModel.Create calls Apply(gunModel, ids) right after cloning the weapon, so first person, third person and the menu preview all show them.
-- Everything is positioned from the model's own Attachments (Aim, Muzzle, LeftGrip) and parts (Stock, Mag, Scope), so your own gun models work
-- too as long as they follow the naming in GunBuilder. Missing pieces are skipped.
-- Visual rules: optics raise the Aim point (so aiming still looks through them), muzzle devices / barrels move the Muzzle point.
local V = {}
local rad = math.rad

local function root(gun) return gun.PrimaryPart or gun:FindFirstChild("Body") end

local function addPart(gun, name, size, cf, color, material, shape, transparency)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Material = material or Enum.Material.Metal
	if shape then p.Shape = shape end
	p.Transparency = transparency or 0
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = gun
	return p
end

-- cylinder along the barrel (Z)
local function cyl(gun, name, len, dia, cf, color, material, transparency)
	return addPart(gun, name, Vector3.new(len, dia, dia), cf * CFrame.Angles(0, rad(90), 0), color, material, Enum.PartType.Cylinder, transparency)
end

local DARK, MID = Color3.fromRGB(28, 28, 32), Color3.fromRGB(58, 60, 66)
local GLASS, RED = Color3.fromRGB(120, 190, 235), Color3.fromRGB(255, 60, 50)

-- where things attach, in the gun's own space (Body at the origin, barrel toward -Z)
local function points(gun)
	local r = root(gun)
	local function rel(name, fallback)
		local a = gun:FindFirstChild(name, true)
		if a and a:IsA("Attachment") then return r.CFrame:ToObjectSpace(a.Parent.CFrame * a.CFrame).Position, a end
		return fallback, nil
	end
	local aim, aimAtt = rel("Aim", Vector3.new(0, 0.3, 0.3))
	local muzzle, muzzleAtt = rel("Muzzle", Vector3.new(0, 0, -2))
	local grip = rel("LeftGrip", nil)
	return { Root = r, Aim = aim, AimAtt = aimAtt, Muzzle = muzzle, MuzzleAtt = muzzleAtt, Grip = grip }
end

local function put(P, off) return P.Root.CFrame * CFrame.new(off) end
local function shiftAtt(att, delta) if att then att.Position += delta end end

local Draw = {}

-- ---------------------------------------------------------------- optics
local function optic(gun, P, name, size, raise, lensLen)
	local c = P.Aim + Vector3.new(0, raise, 0)
	addPart(gun, name .. "Mount", Vector3.new(0.1, raise + 0.02, 0.22), put(P, P.Aim + Vector3.new(0, raise / 2 - 0.02, 0)), DARK)
	addPart(gun, name, size, put(P, c + Vector3.new(0, size.Y / 2, -0.02)), MID)
	if lensLen then
		addPart(gun, name .. "Lens", Vector3.new(size.X * 0.7, size.Y * 0.7, 0.02), put(P, c + Vector3.new(0, size.Y / 2, -size.Z / 2 - 0.02)), GLASS, Enum.Material.Glass, nil, 0.35)
	end
	shiftAtt(P.AimAtt, Vector3.new(0, raise + size.Y / 2 - 0.1, 0))
end

function Draw.RedDot(gun, P) optic(gun, P, "RedDot", Vector3.new(0.12, 0.12, 0.26), 0.06, true) end
function Draw.Holo(gun, P) optic(gun, P, "Holo", Vector3.new(0.17, 0.17, 0.3), 0.07, true) end
function Draw.Hybrid(gun, P)
	optic(gun, P, "Hybrid", Vector3.new(0.16, 0.2, 0.5), 0.08, true)
	addPart(gun, "HybridDot", Vector3.new(0.07, 0.07, 0.12), put(P, P.Aim + Vector3.new(0, 0.34, -0.1)), MID)
end
function Draw.Scope6(gun, P)
	local c = P.Aim + Vector3.new(0, 0.2, -0.02)
	addPart(gun, "ScopeMount", Vector3.new(0.1, 0.18, 0.5), put(P, P.Aim + Vector3.new(0, 0.09, 0)), DARK)
	cyl(gun, "Scope6", 1.0, 0.2, put(P, c + Vector3.new(0, 0.12, 0)), DARK)
	cyl(gun, "Scope6Front", 0.22, 0.3, put(P, c + Vector3.new(0, 0.12, -0.55)), MID)
	cyl(gun, "Scope6Back", 0.2, 0.26, put(P, c + Vector3.new(0, 0.12, 0.5)), MID)
	shiftAtt(P.AimAtt, Vector3.new(0, 0.32, 0))
end
local function resizeScope(gun, mult)
	local s = gun:FindFirstChild("Scope")
	if s and s:IsA("BasePart") then s.Size = Vector3.new(s.Size.X * mult, s.Size.Y, s.Size.Z) end
end
function Draw.SniperShort(gun) resizeScope(gun, 0.7) end
function Draw.SniperLong(gun) resizeScope(gun, 1.3) end

-- ---------------------------------------------------------------- muzzle devices + barrels
local function extend(P, len)
	shiftAtt(P.MuzzleAtt, Vector3.new(0, 0, -len))
	P.Muzzle += Vector3.new(0, 0, -len) -- the next device sits on the end of this one
end

function Draw.Suppressor(gun, P)
	cyl(gun, "Suppressor", 0.95, 0.17, put(P, P.Muzzle + Vector3.new(0, 0, -0.35)), DARK)
	cyl(gun, "SuppressorBand", 0.08, 0.19, put(P, P.Muzzle + Vector3.new(0, 0, -0.1)), MID)
	extend(P, 0.8)
end
function Draw.Compensator(gun, P)
	addPart(gun, "Comp", Vector3.new(0.16, 0.16, 0.3), put(P, P.Muzzle + Vector3.new(0, 0, -0.08)), MID)
	addPart(gun, "CompSlot", Vector3.new(0.18, 0.04, 0.12), put(P, P.Muzzle + Vector3.new(0, 0.08, -0.08)), DARK)
end
function Draw.MuzzleBrake(gun, P)
	cyl(gun, "Brake", 0.3, 0.16, put(P, P.Muzzle + Vector3.new(0, 0, -0.08)), MID)
	for _, side in { -1, 1 } do
		addPart(gun, "BrakeFin", Vector3.new(0.04, 0.16, 0.2), put(P, P.Muzzle + Vector3.new(side * 0.09, 0, -0.08)), DARK)
	end
end
function Draw.Choke(gun, P)
	cyl(gun, "Choke", 0.4, 0.2, put(P, P.Muzzle + Vector3.new(0, 0, -0.1)), DARK)
	extend(P, 0.2)
end
function Draw.LongBarrel(gun, P)
	cyl(gun, "LongBarrel", 0.75, 0.1, put(P, P.Muzzle + Vector3.new(0, 0, -0.3)), DARK)
	extend(P, 0.65)
end
function Draw.Reinforced(gun, P)
	cyl(gun, "BarrelSleeve", 0.6, 0.15, put(P, P.Muzzle + Vector3.new(0, 0, 0.45)), MID)
end

-- ---------------------------------------------------------------- underbarrel
local function under(P)
	-- below the handguard, under the front hand
	local g = P.Grip or (P.Muzzle * 0.45 + Vector3.new(0, -0.2, 0))
	return Vector3.new(g.X, -0.13, g.Z)
end
function Draw.Vertical(gun, P)
	local u = under(P)
	addPart(gun, "VertGrip", Vector3.new(0.1, 0.4, 0.1), put(P, u + Vector3.new(0, -0.2, 0)), DARK, Enum.Material.SmoothPlastic)
end
function Draw.Angled(gun, P)
	local u = under(P)
	addPart(gun, "AngledGrip", Vector3.new(0.1, 0.12, 0.42), P.Root.CFrame * CFrame.new(u + Vector3.new(0, -0.08, -0.12)) * CFrame.Angles(rad(28), 0, 0), DARK, Enum.Material.SmoothPlastic)
end
function Draw.Folding(gun, P)
	local u = under(P)
	addPart(gun, "FoldGrip", Vector3.new(0.09, 0.1, 0.3), put(P, u + Vector3.new(0, -0.05, -0.05)), DARK, Enum.Material.SmoothPlastic)
end
function Draw.Laser(gun, P)
	local u = under(P)
	addPart(gun, "Laser", Vector3.new(0.1, 0.1, 0.24), put(P, u + Vector3.new(0, -0.06, -0.35)), DARK)
	addPart(gun, "LaserLens", Vector3.new(0.05, 0.05, 0.02), put(P, u + Vector3.new(0, -0.06, -0.48)), RED, Enum.Material.Neon)
end
function Draw.Bipod(gun, P)
	local u = under(P)
	for _, side in { -1, 1 } do
		addPart(gun, "BipodLeg", Vector3.new(0.04, 0.4, 0.04),
			P.Root.CFrame * CFrame.new(u + Vector3.new(side * 0.07, -0.18, -0.4)) * CFrame.Angles(rad(-18), 0, rad(side * 14)), DARK)
	end
end

-- ---------------------------------------------------------------- magazines, stocks
function Draw.ExtMag(gun, P)
	local m = gun:FindFirstChild("Mag")
	if m then
		local grow = m.Size.Y * 0.35
		m.Size = Vector3.new(m.Size.X, m.Size.Y + grow, m.Size.Z)
		m.CFrame = m.CFrame * CFrame.new(0, -grow / 2, 0)
	end
end
function Draw.FastMag(gun, P)
	local m = gun:FindFirstChild("Mag")
	if m then
		m.Color = Color3.fromRGB(190, 130, 50)
		addPart(gun, "MagPull", Vector3.new(m.Size.X + 0.02, 0.07, m.Size.Z + 0.02), m.CFrame * CFrame.new(0, -m.Size.Y / 2 + 0.05, 0), DARK)
	end
end
function Draw.Drum(gun, P)
	local m = gun:FindFirstChild("Mag")
	if m then
		m.Size = Vector3.new(m.Size.X + 0.12, m.Size.Y * 0.8, m.Size.Z + 0.3)
		m.CFrame = m.CFrame * CFrame.new(0, -0.05, 0)
	end
end
function Draw.ExtTube(gun, P)
	local u = under(P)
	cyl(gun, "ExtTube", 0.9, 0.1, put(P, u + Vector3.new(0, -0.02, -0.1)), MID)
end
function Draw.Speedloader(gun, P)
	local c = gun:FindFirstChild("Cylinder")
	if c then c.Color = Color3.fromRGB(190, 130, 50) end
end

function Draw.ExtCylinder(gun)
	local c = gun:FindFirstChild("Cylinder")
	if c then c.Size = Vector3.new(c.Size.X, c.Size.Y * 1.12, c.Size.Z * 1.12) end
end
-- The Mag part is moved by the reload animation, so anything that must travel with it is done by resizing / recolouring Mag itself.
function Draw.BoxExt(gun)
	local m = gun:FindFirstChild("Mag")
	if m then
		local grow = m.Size.Y * 0.4
		m.Size = Vector3.new(m.Size.X, m.Size.Y + grow, m.Size.Z + 0.1)
		m.CFrame = m.CFrame * CFrame.new(0, -grow / 2, 0)
	end
end
function Draw.DualMag(gun)
	local m = gun:FindFirstChild("Mag")
	if m then
		m.Size = Vector3.new(m.Size.X * 1.95, m.Size.Y, m.Size.Z)
		m.Color = Color3.fromRGB(70, 74, 60)
	end
end
function Draw.LightMag(gun)
	local m = gun:FindFirstChild("Mag")
	if m then
		m.Color, m.Material = Color3.fromRGB(120, 124, 130), Enum.Material.SmoothPlastic
		m.Size = Vector3.new(m.Size.X, m.Size.Y * 0.9, m.Size.Z)
	end
end
function Draw.StripperClip(gun, P)
	addPart(gun, "StripperClip", Vector3.new(0.05, 0.04, 0.34), put(P, Vector3.new(0.13, 0.1, 0.05)), Color3.fromRGB(190, 150, 70))
end
function Draw.ShellCarrier(gun, P)
	-- four spare shells on a strip along the left side of the receiver
	addPart(gun, "ShellStrip", Vector3.new(0.04, 0.12, 0.62), put(P, Vector3.new(-0.13, 0.02, 0.2)), DARK, Enum.Material.Fabric)
	for i = 0, 3 do
		addPart(gun, "SpareShell", Vector3.new(0.07, 0.1, 0.11), put(P, Vector3.new(-0.15, 0.02, -0.03 + i * 0.15)), Color3.fromRGB(200, 60, 50), Enum.Material.SmoothPlastic)
	end
end
function Draw.Bandolier(gun, P)
	-- a pouch strapped to the side of the receiver
	addPart(gun, "BandolierStrap", Vector3.new(0.04, 0.3, 0.1), put(P, Vector3.new(0.12, -0.05, 0.35)), DARK, Enum.Material.Fabric)
	addPart(gun, "BandolierPouch", Vector3.new(0.09, 0.16, 0.22), put(P, Vector3.new(0.15, -0.14, 0.35)), Color3.fromRGB(78, 86, 62), Enum.Material.Fabric)
end

local function stock(gun) local s = gun:FindFirstChild("Stock") return s end
function Draw.NoStock(gun) local s = stock(gun) if s then s:Destroy() end end
function Draw.Skeleton(gun)
	local s = stock(gun)
	if s then s.Size, s.Transparency = Vector3.new(s.Size.X * 0.6, s.Size.Y * 0.5, s.Size.Z), 0.25 end
end
function Draw.HeavyStock(gun)
	local s = stock(gun)
	if s then s.Size = Vector3.new(s.Size.X * 1.2, s.Size.Y * 1.3, s.Size.Z * 1.1) end
end
function Draw.CheekPad(gun)
	local s = stock(gun)
	if s then addPart(gun, "CheekPad", Vector3.new(s.Size.X + 0.03, 0.08, s.Size.Z * 0.5), s.CFrame * CFrame.new(0, s.Size.Y / 2 + 0.03, 0.1), DARK, Enum.Material.SmoothPlastic) end
end

local BARRELS = { LongBarrel = true, Reinforced = true }

-- ids: list of attachment ids (Armory.Attachments). Safe to call with nil / unknown ids.
function V.Apply(gun, ids)
	if not ids or #ids == 0 then return end
	local r = root(gun)
	if not r then return end
	local P = points(gun)
	for _, pass in { true, false } do -- barrels first, so a muzzle device ends up on the end of a long barrel
		for _, id in ids do
			local fn = Draw[id]
			if fn and (BARRELS[id] == true) == pass then fn(gun, P) end
		end
	end
end

return V
