-- Procedural placeholder weapons (one builder per cfg.Model kind) so everything works with zero assets.
-- Your own models need: PrimaryPart "Body", optional parts "Mag" / "Pump" / "Bolt", and Attachments
--   RightGrip, LeftGrip (omit for one-handed), Aim (rear sight / optic eye point), Muzzle, Eject. Barrel points to -Z.
local GunBuilder = {}
local rad = math.rad
local CF = CFrame.new

local function part(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Material = material or Enum.Material.Metal
	if shape then p.Shape = shape end
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end
-- cylinder along Z
local function cyl(model, name, len, dia, cf, color, material)
	return part(model, name, Vector3.new(len, dia, dia), cf * CFrame.Angles(0, rad(90), 0), color, material, Enum.PartType.Cylinder)
end
local function att(parent, name, pos)
	local a = Instance.new("Attachment")
	a.Name, a.Position = name, pos
	a.Parent = parent
end
local function atts(body, rg, lg, aim, muzzle, eject)
	att(body, "RightGrip", rg)
	if lg then att(body, "LeftGrip", lg) end
	att(body, "Aim", aim)
	att(body, "Muzzle", muzzle)
	att(body, "Eject", eject or Vector3.new(0.12, 0.1, 0.2))
end

local B = {}

function B.Rifle(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.22, 0.3, 1.2), CF(), dark)
	part(m, "Handguard", Vector3.new(0.27, 0.27, 1.0), CF(0, -0.01, -1.1), mid)
	part(m, "Barrel", Vector3.new(0.08, 0.08, 0.7), CF(0, 0.03, -1.95), dark)
	part(m, "Brake", Vector3.new(0.13, 0.13, 0.2), CF(0, 0.03, -2.35), mid)
	part(m, "Stock", Vector3.new(0.2, 0.32, 0.9), CF(0, -0.05, 1.0), mid, Enum.Material.SmoothPlastic)
	part(m, "Grip", Vector3.new(0.2, 0.5, 0.22), CF(0, -0.38, 0.32) * CFrame.Angles(rad(-15), 0, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "Mag", Vector3.new(0.16, 0.55, 0.26), CF(0, -0.45, -0.25) * CFrame.Angles(rad(-8), 0, 0), mid)
	part(m, "RearSight", Vector3.new(0.06, 0.14, 0.08), CF(0, 0.22, 0.4), dark)
	part(m, "FrontSight", Vector3.new(0.04, 0.24, 0.04), CF(0, 0.17, -2.0), dark)
	atts(body, Vector3.new(0, -0.42, 0.34), Vector3.new(0, -0.22, -1.1), Vector3.new(0, 0.29, 0.4), Vector3.new(0, 0.03, -2.5))
	return body
end

function B.SMG(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.22, 0.3, 0.95), CF(), dark)
	part(m, "Handguard", Vector3.new(0.25, 0.25, 0.6), CF(0, -0.01, -0.78), mid)
	part(m, "Barrel", Vector3.new(0.09, 0.09, 0.45), CF(0, 0.02, -1.28), dark)
	part(m, "Stock", Vector3.new(0.14, 0.26, 0.6), CF(0, -0.04, 0.75), mid, Enum.Material.SmoothPlastic)
	part(m, "Grip", Vector3.new(0.2, 0.46, 0.22), CF(0, -0.36, 0.28) * CFrame.Angles(rad(-12), 0, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "Mag", Vector3.new(0.14, 0.7, 0.22), CF(0, -0.5, -0.18), mid)
	part(m, "RearSight", Vector3.new(0.06, 0.12, 0.08), CF(0, 0.21, 0.3), dark)
	part(m, "FrontSight", Vector3.new(0.04, 0.2, 0.04), CF(0, 0.15, -1.1), dark)
	atts(body, Vector3.new(0, -0.4, 0.3), Vector3.new(0, -0.2, -0.8), Vector3.new(0, 0.27, 0.3), Vector3.new(0, 0.02, -1.55))
	return body
end

function B.Pistol(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.2, 0.26, 0.85), CF(0, 0.05, -0.1), dark)
	part(m, "Slide", Vector3.new(0.22, 0.2, 0.8), CF(0, 0.2, -0.12), mid)
	part(m, "Barrel", Vector3.new(0.07, 0.07, 0.2), CF(0, 0.2, -0.62), dark)
	part(m, "Grip", Vector3.new(0.2, 0.5, 0.26), CF(0, -0.28, 0.2) * CFrame.Angles(rad(-14), 0, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "Mag", Vector3.new(0.15, 0.5, 0.22), CF(0, -0.32, 0.2) * CFrame.Angles(rad(-14), 0, 0), mid)
	part(m, "RearSight", Vector3.new(0.05, 0.07, 0.06), CF(0, 0.33, 0.2), dark)
	part(m, "FrontSight", Vector3.new(0.03, 0.07, 0.04), CF(0, 0.33, -0.48), dark)
	atts(body, Vector3.new(0, -0.3, 0.22), Vector3.new(0.05, -0.35, 0.18), Vector3.new(0, 0.28, 0.2), Vector3.new(0, 0.2, -0.75))
	return body
end

function B.Revolver(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.2, 0.3, 0.7), CF(0, 0.05, 0), dark)
	cyl(m, "Cylinder", 0.45, 0.34, CF(0, 0.08, -0.15), mid)
	part(m, "Barrel", Vector3.new(0.09, 0.09, 0.9), CF(0, 0.15, -0.8), dark)
	part(m, "Grip", Vector3.new(0.2, 0.55, 0.28), CF(0, -0.3, 0.32) * CFrame.Angles(rad(-18), 0, 0), mid, Enum.Material.Wood)
	part(m, "RearSight", Vector3.new(0.05, 0.08, 0.06), CF(0, 0.26, 0.3), dark)
	part(m, "FrontSight", Vector3.new(0.03, 0.08, 0.04), CF(0, 0.24, -1.2), dark)
	atts(body, Vector3.new(0, -0.32, 0.34), Vector3.new(0.05, -0.3, 0.3), Vector3.new(0, 0.3, 0.3), Vector3.new(0, 0.15, -1.28))
	return body
end

local function shotgun(m, dark, mid, pump, doubleBarrel)
	local body = part(m, "Body", Vector3.new(0.24, 0.3, 1.0), CF(), dark)
	if doubleBarrel then
		part(m, "BarrelL", Vector3.new(0.09, 0.09, 1.7), CF(-0.07, 0.07, -1.35), dark)
		part(m, "BarrelR", Vector3.new(0.09, 0.09, 1.7), CF(0.07, 0.07, -1.35), dark)
		part(m, "Forend", Vector3.new(0.27, 0.16, 0.6), CF(0, -0.05, -0.95), mid, Enum.Material.Wood)
	else
		part(m, "Barrel", Vector3.new(0.1, 0.1, 1.8), CF(0, 0.07, -1.4), dark)
		part(m, "Tube", Vector3.new(0.09, 0.09, 1.3), CF(0, -0.07, -1.15), mid)
		part(m, pump and "Pump" or "Forend", Vector3.new(0.28, 0.2, 0.55), CF(0, -0.07, -1.0), mid, Enum.Material.Wood)
	end
	part(m, "Stock", Vector3.new(0.2, 0.34, 0.95), CF(0, -0.06, 0.95), mid, Enum.Material.Wood)
	part(m, "Grip", Vector3.new(0.2, 0.45, 0.2), CF(0, -0.34, 0.3) * CFrame.Angles(rad(-15), 0, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "FrontSight", Vector3.new(0.04, 0.09, 0.04), CF(0, 0.16, -2.2), dark)
	part(m, "RearSight", Vector3.new(0.06, 0.1, 0.08), CF(0, 0.22, 0.3), dark)
	atts(body, Vector3.new(0, -0.4, 0.32), Vector3.new(0, -0.18, -1.0), Vector3.new(0, 0.28, 0.3), Vector3.new(0, 0.07, -2.3))
	return body
end
function B.Shotgun(m, d, mi) return shotgun(m, d, mi, false, false) end
function B.Pump(m, d, mi) return shotgun(m, d, mi, true, false) end
function B.Break(m, d, mi) return shotgun(m, d, mi, false, true) end

function B.LMG(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.3, 0.38, 1.3), CF(), dark)
	part(m, "Cover", Vector3.new(0.26, 0.1, 0.8), CF(0, 0.24, -0.1), mid)
	part(m, "Handguard", Vector3.new(0.28, 0.28, 0.9), CF(0, -0.02, -1.15), mid)
	part(m, "Barrel", Vector3.new(0.1, 0.1, 0.9), CF(0, 0.04, -2.1), dark)
	part(m, "Bipod", Vector3.new(0.3, 0.04, 0.04), CF(0, -0.2, -2.0), dark)
	part(m, "Stock", Vector3.new(0.22, 0.36, 0.95), CF(0, -0.06, 1.1), mid, Enum.Material.SmoothPlastic)
	part(m, "Grip", Vector3.new(0.22, 0.5, 0.24), CF(0, -0.42, 0.4) * CFrame.Angles(rad(-15), 0, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "Mag", Vector3.new(0.34, 0.5, 0.5), CF(0, -0.45, -0.1), mid)
	part(m, "RearSight", Vector3.new(0.07, 0.14, 0.08), CF(0, 0.3, 0.45), dark)
	part(m, "FrontSight", Vector3.new(0.04, 0.22, 0.04), CF(0, 0.2, -2.45), dark)
	atts(body, Vector3.new(0, -0.5, 0.42), Vector3.new(0, -0.25, -1.15), Vector3.new(0, 0.38, 0.45), Vector3.new(0, 0.04, -2.6))
	return body
end

function B.Marksman(m, dark, mid)
	local body = B.Rifle(m, dark, mid)
	cyl(m, "Scope", 0.9, 0.2, CF(0, 0.38, -0.05), dark)
	part(m, "ScopeMount", Vector3.new(0.1, 0.12, 0.5), CF(0, 0.26, -0.05), dark)
	body:FindFirstChild("Aim").Position = Vector3.new(0, 0.38, 0.4)
	return body
end

function B.Sniper(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.22, 0.3, 1.3), CF(), dark)
	part(m, "Barrel", Vector3.new(0.09, 0.09, 1.9), CF(0, 0.03, -1.6), dark)
	part(m, "Brake", Vector3.new(0.14, 0.14, 0.25), CF(0, 0.03, -2.6), mid)
	part(m, "Stock", Vector3.new(0.22, 0.38, 1.1), CF(0, -0.05, 1.15), mid, Enum.Material.SmoothPlastic)
	part(m, "Grip", Vector3.new(0.2, 0.46, 0.22), CF(0, -0.36, 0.38) * CFrame.Angles(rad(-15), 0, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "Mag", Vector3.new(0.16, 0.4, 0.3), CF(0, -0.33, -0.2), mid)
	cyl(m, "Scope", 1.3, 0.24, CF(0, 0.42, 0), dark)
	cyl(m, "ScopeFront", 0.25, 0.32, CF(0, 0.42, -0.72), mid)
	part(m, "ScopeMount", Vector3.new(0.1, 0.14, 0.7), CF(0, 0.28, 0), dark)
	part(m, "Bolt", Vector3.new(0.2, 0.06, 0.06), CF(0.16, 0.1, 0.25), mid)
	atts(body, Vector3.new(0, -0.42, 0.4), Vector3.new(0, -0.2, -1.3), Vector3.new(0, 0.42, 0.55), Vector3.new(0, 0.03, -2.75))
	return body
end

function B.Launcher(m, dark, mid)
	local body = cyl(m, "Body", 3.2, 0.4, CF(0, 0.05, -0.2), dark)
	cyl(m, "Mag", 0.9, 0.3, CF(0, 0.05, -2.1), mid)           -- the loaded rocket (sticks out of the muzzle)
	part(m, "Warhead", Vector3.new(0.34, 0.34, 0.34), CF(0, 0.05, -2.65), mid, Enum.Material.Metal, Enum.PartType.Ball)
	part(m, "Grip", Vector3.new(0.2, 0.5, 0.22), CF(0, -0.42, 0.35) * CFrame.Angles(rad(-15), 0, 0), dark, Enum.Material.SmoothPlastic)
	part(m, "ForeGrip", Vector3.new(0.18, 0.4, 0.2), CF(0, -0.4, -0.8), dark, Enum.Material.SmoothPlastic)
	part(m, "Sight", Vector3.new(0.06, 0.28, 0.1), CF(0, 0.38, -0.2), dark)
	part(m, "Shroud", Vector3.new(0.5, 0.5, 0.5), CF(0, 0.05, 1.5), mid, Enum.Material.Metal, Enum.PartType.Cylinder)
	atts(body, Vector3.new(0, -0.5, 0.35), Vector3.new(0, -0.5, -0.8), Vector3.new(0, 0.5, 0.5), Vector3.new(0, 0.05, -3.2))
	return body
end

function B.Grenade(m, dark, mid) -- M79 thumper
	local body = part(m, "Body", Vector3.new(0.26, 0.3, 0.9), CF(), dark)
	cyl(m, "Barrel", 1.3, 0.34, CF(0, 0.08, -1.0), dark)
	part(m, "Stock", Vector3.new(0.22, 0.36, 1.1), CF(0, -0.08, 1.0), mid, Enum.Material.Wood)
	part(m, "Grip", Vector3.new(0.2, 0.42, 0.22), CF(0, -0.32, 0.3) * CFrame.Angles(rad(-15), 0, 0), mid, Enum.Material.Wood)
	part(m, "Sight", Vector3.new(0.06, 0.3, 0.06), CF(0, 0.36, 0.1), dark)
	atts(body, Vector3.new(0, -0.38, 0.32), Vector3.new(0, -0.15, -0.9), Vector3.new(0, 0.5, 0.1), Vector3.new(0, 0.08, -1.7))
	return body
end

-- ---- melee: blade points toward -Z
function B.Knife(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.12, 0.2, 0.55), CF(), mid, Enum.Material.SmoothPlastic)
	part(m, "Blade", Vector3.new(0.04, 0.22, 0.9), CF(0, 0.02, -0.72), dark)
	part(m, "Guard", Vector3.new(0.1, 0.3, 0.05), CF(0, 0, -0.3), dark)
	atts(body, Vector3.new(0, 0, 0.05), nil, Vector3.new(0, 0.2, 0), Vector3.new(0, 0, -1.2))
	return body
end
function B.Katana(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.12, 0.14, 0.9), CF(), Color3.fromRGB(26, 26, 30), Enum.Material.Fabric)
	part(m, "Blade", Vector3.new(0.03, 0.2, 2.4), CF(0, 0.02, -1.65), dark)
	part(m, "Tsuba", Vector3.new(0.28, 0.28, 0.05), CF(0, 0, -0.5), mid)
	atts(body, Vector3.new(0, 0, 0.18), Vector3.new(0, 0, 0.55), Vector3.new(0, 0.2, 0), Vector3.new(0, 0, -2.8))
	return body
end
function B.Hammer(m, dark, mid)
	local body = part(m, "Body", Vector3.new(0.14, 0.14, 2.6), CF(0, 0, -0.4), mid, Enum.Material.Wood)
	part(m, "Head", Vector3.new(0.5, 0.45, 0.9), CF(0, 0, -1.8), dark)
	atts(body, Vector3.new(0, 0, 0.6), Vector3.new(0, 0, -0.3), Vector3.new(0, 0.2, 0), Vector3.new(0, 0, -2.3))
	return body
end

function GunBuilder.Build(kind, tint)
	local dark = tint or Color3.fromRGB(38, 38, 42)
	local mid = dark:Lerp(Color3.new(1, 1, 1), 0.14)
	local m = Instance.new("Model")
	m.Name = "Gun"
	local fn = B[kind] or B.Rifle
	m.PrimaryPart = fn(m, dark, mid)
	return m
end

return GunBuilder
