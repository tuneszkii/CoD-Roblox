-- RigPreview: a small R6-proportioned mannequin inside a ViewportFrame. The Cosmetics menu uses it to show operators (colors) and to play emotes.
-- It uses the same IK limbs and the same emote poses as the real third-person rig, so what you preview is what other players see.
--   local rig = RigPreview.new(viewportFrame)
--   rig:SetOperator(operatorDef)        -- colors (Cosmetics.Operator(id))
--   rig:Update(yaw, pose, weight)       -- every frame; pose / weight come from Emotes.Sample (nil pose = standing)
--   rig:Destroy()
local IK = require(script.Parent.IK)
local Config = require(script.Parent.Config)

local TPc = Config.ThirdPerson
local CF = CFrame.new
local ARM, LEG = 1.1, 1.1

local RigPreview = {}
RigPreview.__index = RigPreview

local function part(parent, name, size, color, material)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color, p.Anchored = name, size, color, true
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function limb(model, thick, upLen, lowLen, endSize)
	return {
		Upper = part(model, "Upper", Vector3.new(thick, thick, upLen), Color3.new(1, 1, 1)),
		Lower = part(model, "Lower", Vector3.new(thick * 0.9, thick * 0.9, lowLen), Color3.new(1, 1, 1)),
		End = part(model, "End", endSize, Color3.new(1, 1, 1)),
	}
end

function RigPreview.new(viewport)
	local self = setmetatable({}, RigPreview)
	viewport.Ambient = Color3.fromRGB(150, 150, 160)
	viewport.LightColor = Color3.fromRGB(255, 244, 230)
	viewport.LightDirection = Vector3.new(-0.5, -0.7, 0.6)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 34
	cam.CFrame = CFrame.lookAt(Vector3.new(2.2, 4.4, -12.5), Vector3.new(0, 3.1, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam

	local model = Instance.new("Model")
	model.Name = "Preview"
	model.Parent = viewport
	self.Model = model

	self.Pad = part(model, "Pad", Vector3.new(0.25, 6.5, 6.5), Color3.fromRGB(255, 178, 64), Enum.Material.Neon)
	self.Pad.Shape, self.Pad.Transparency = Enum.PartType.Cylinder, 0.7
	self.Pad.CFrame = CF(0, -0.15, 0) * CFrame.Angles(0, 0, math.pi / 2)

	self.Torso = part(model, "Torso", Vector3.new(2, 2, 1), Color3.new(1, 1, 1))
	self.Head = part(model, "Head", Vector3.new(2, 1, 1), Color3.new(1, 1, 1))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType, mesh.Scale = Enum.MeshType.Head, Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = self.Head
	self.Band = part(model, "Band", Vector3.new(1.32, 0.2, 1.32), Color3.new(1, 1, 1), Enum.Material.Neon)
	self.Vest = part(model, "Vest", Vector3.new(2.1, 1.9, 1.15), Color3.new(1, 1, 1), Enum.Material.Fabric)
	self.Arms = { R = limb(model, 0.7, ARM, ARM, Vector3.new(0.55, 0.5, 0.6)), L = limb(model, 0.7, ARM, ARM, Vector3.new(0.55, 0.5, 0.6)) }
	self.Legs = { R = limb(model, 0.85, LEG, LEG, Vector3.new(0.8, 0.45, 1.1)), L = limb(model, 0.85, LEG, LEG, Vector3.new(0.8, 0.45, 1.1)) }
	self.Face = Instance.new("Decal") -- a plain face so you can tell which way it looks
	self.Face.Face, self.Face.Texture = Enum.NormalId.Front, "rbxasset://textures/face.png"
	self.Face.Parent = self.Head
	return self
end

function RigPreview:SetOperator(op)
	if not op then return end
	local m = self
	m.Torso.Color, m.Head.Color = op.Torso, op.Head or op.Skin
	m.Vest.Color, m.Band.Color, m.Pad.Color = op.Vest, op.Accent, op.Accent
	for _, side in { "R", "L" } do
		m.Arms[side].Upper.Color, m.Arms[side].Lower.Color, m.Arms[side].End.Color = op.Sleeve, op.Sleeve, op.Skin
		m.Legs[side].Upper.Color, m.Legs[side].Lower.Color, m.Legs[side].End.Color = op.Pants, op.Pants, op.Boots
	end
	m.Band.Transparency = op.Avatar and 1 or 0
	m.Vest.Transparency = op.Avatar and 1 or 0
end

local function lerpCF(a, b, w)
	return a:Lerp(b, w)
end

function RigPreview:Update(yaw, pose, w)
	w = pose and w or 0
	local base = CFrame.Angles(0, yaw, 0)
	local off = pose and pose.Torso and lerpCF(CFrame.identity, pose.Torso, w) or CFrame.identity
	local torsoCF = base * CF(0, 3, 0) * off
	local right, up = torsoCF.RightVector, torsoCF.UpVector
	self.Torso.CFrame = torsoCF
	self.Vest.CFrame = torsoCF * CF(0, 0.05, 0)

	local headOff = pose and pose.Head and lerpCF(CFrame.identity, pose.Head, w) or CFrame.identity
	local headCF = torsoCF * CF(0, 1, 0) * headOff * CF(0, 0.5, 0)
	self.Head.CFrame = headCF
	self.Band.CFrame = headCF * CF(0, 0.36, 0)

	-- arms: rest hands hang by the sides, emote hands blend in on top
	local chest = torsoCF * CF(0, 0.4, 0)
	for _, side in { "R", "L" } do
		local sgn = side == "R" and 1 or -1
		local shoulder = (torsoCF * CF(sgn * 0.9, 0.5, 0)).Position
		local rest = chest * CF(sgn * 0.98, -1.9, -0.15)
		local target = rest
		local want = pose and pose[side]
		if want then target = rest:Lerp(chest * want, w) end
		local hint = shoulder + right * (sgn * 1.4) - up * 1.1
		local elbow, wrist = IK.Solve(shoulder, target.Position, hint, ARM, ARM)
		local a = self.Arms[side]
		local upv = hint - elbow
		a.Upper.CFrame = IK.Segment(shoulder, elbow, ARM, upv)
		a.Lower.CFrame = IK.Segment(elbow, wrist, ARM, upv)
		a.End.CFrame = CF(wrist) * target.Rotation
	end

	-- legs: feet stay planted, the knees bend when the torso drops
	local fwd = base.LookVector
	for _, side in { "R", "L" } do
		local sgn = side == "R" and 1 or -1
		local hip = (torsoCF * CF(sgn * 0.5, -1, 0)).Position
		local ankle = (base * CF(sgn * 0.55, 0.45, 0)).Position
		local hint = (hip + ankle) / 2 + torsoCF.LookVector * 1.6 + Vector3.new(0, 0.3, 0)
		local knee, a2 = IK.Solve(hip, ankle, hint, LEG, LEG)
		local lg = self.Legs[side]
		local upv = hint - knee
		lg.Upper.CFrame = IK.Segment(hip, knee, LEG, upv)
		lg.Lower.CFrame = IK.Segment(knee, a2, LEG, upv)
		local fp = a2 + Vector3.new(0, -0.15, 0) + fwd * 0.25
		lg.End.CFrame = CFrame.lookAt(fp, fp + fwd)
	end
end

function RigPreview:Destroy()
	self.Model:Destroy()
end

return RigPreview
