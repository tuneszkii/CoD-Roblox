-- Loads a weapon model (your template in ReplicatedStorage.FPS.Weapons or the procedural placeholder) and
-- extracts everything animation needs: parts relative to the Body, grips, aim/muzzle/eject points.
local RS = game:GetService("ReplicatedStorage")
local GunBuilder = require(script.Parent.GunBuilder)
local AttachmentVisuals = require(script.Parent.AttachmentVisuals)

local GunModel = {}

local MOVERS = { Mag = true, Pump = true, Bolt = true } -- parts driven separately by animation

-- cfg: Config.Weapons entry (or Armory.Build result). fx: add muzzle light/particles (first person only). attIds: attachments to draw (optional)
function GunModel.Create(name, cfg, fx, attIds)
	local folder = RS:FindFirstChild("FPS") and RS.FPS:FindFirstChild("Weapons")
	local template = folder and folder:FindFirstChild(name)
	local gun = template and template:Clone() or GunBuilder.Build(cfg.Model, cfg.Color)
	gun.Name = "Gun"
	local root = gun.PrimaryPart or gun:FindFirstChild("Body")
	gun.PrimaryPart = root
	AttachmentVisuals.Apply(gun, attIds) -- before the part list is built, so attachments move with the gun

	local G = { Model = gun, Root = root, Parts = {}, Movers = {} }
	for _, d in gun:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
			local rel = root.CFrame:ToObjectSpace(d.CFrame)
			if MOVERS[d.Name] then
				G.Movers[d.Name] = { Part = d, Rel = rel }
			else
				table.insert(G.Parts, { Part = d, Rel = rel })
			end
		end
	end
	if G.Movers.Mag then G.MagPart, G.MagRel = G.Movers.Mag.Part, G.Movers.Mag.Rel end

	local function attRel(n, fallback)
		local a = gun:FindFirstChild(n, true)
		if not (a and a:IsA("Attachment")) then return fallback, nil end
		return root.CFrame:ToObjectSpace(a.Parent.CFrame * a.CFrame), a
	end
	G.RightGripRel = attRel("RightGrip", CFrame.new(0, -0.4, 0.3))
	G.LeftGripRel = attRel("LeftGrip", nil) -- nil = one-handed
	G.AimRel = attRel("Aim", CFrame.new(0, 0.3, 0.3))
	local muzzleAtt
	G.MuzzleRel, muzzleAtt = attRel("Muzzle", CFrame.new(0, 0, -2))
	G.EjectRel = attRel("Eject", CFrame.new(0.12, 0.1, 0.2))
	G.LeftGripRot = G.LeftGripRel and G.LeftGripRel.Rotation or CFrame.identity
	G.OneHanded = G.LeftGripRel == nil or cfg.OneHanded == true

	if fx and muzzleAtt then
		local light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness, light.Enabled = Color3.fromRGB(255, 190, 110), 9, 3, false
		light.Parent = muzzleAtt
		local em = Instance.new("ParticleEmitter")
		em.Rate, em.Lifetime, em.Speed = 0, NumberRange.new(0.04, 0.08), NumberRange.new(6, 14)
		em.SpreadAngle, em.EmissionDirection = Vector2.new(25, 25), Enum.NormalId.Front
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(Color3.fromRGB(255, 205, 120))
		em.LightEmission = 1
		em.Parent = muzzleAtt
		G.Flash = { Light = light, Emitter = em }
	end
	return G
end

-- Place every part for a gun root CFrame. mover offsets are gun-space Vector3 deltas (optional)
function GunModel.Pose(G, gunCF, magOff, pumpOff, boltOff, magVisible)
	for _, p in G.Parts do p.Part.CFrame = gunCF * p.Rel end
	local mv = G.Movers
	if mv.Mag then
		mv.Mag.Part.CFrame = gunCF * CFrame.new(magOff or Vector3.zero) * mv.Mag.Rel
		mv.Mag.Part.Transparency = (magVisible == false) and 1 or 0
	end
	if mv.Pump then mv.Pump.Part.CFrame = gunCF * CFrame.new(pumpOff or Vector3.zero) * mv.Pump.Rel end
	if mv.Bolt then mv.Bolt.Part.CFrame = gunCF * CFrame.new(boltOff or Vector3.zero) * mv.Bolt.Rel end
end

return GunModel
