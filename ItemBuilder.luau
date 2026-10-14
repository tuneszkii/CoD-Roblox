-- Small procedural models for equipment, plates and syringes (held in first and third person).
local ItemBuilder = {}
local rad = math.rad

local function part(model, name, size, cf, color, material, shape)
	local p = Instance.new("Part")
	p.Name, p.Size, p.Color = name, size, color
	p.Material = material or Enum.Material.Metal
	if shape then p.Shape = shape end
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.Parent = model
	return p
end

-- returns { Model, Parts = {{Part, Rel}}, Mid = bool } ; Rel is relative to the item's origin
function ItemBuilder.Create(kind, color)
	color = color or Color3.fromRGB(80, 80, 80)
	local dark = Color3.fromRGB(30, 30, 32)
	local m = Instance.new("Model")
	m.Name = "Item"
	local I = { Model = m, Parts = {}, Mid = false }
	local function add(name, size, rel, c, mat, shape)
		local p = part(m, name, size, rel, c or color, mat, shape)
		table.insert(I.Parts, { Part = p, Rel = rel })
	end
	local cylRot = CFrame.Angles(0, 0, rad(90)) -- Cylinder parts run along X; this stands them up along Y
	if kind == "Grenade" then
		add("Body", Vector3.new(0.5, 0.5, 0.5), CFrame.new(), color, Enum.Material.Metal, Enum.PartType.Ball)
		add("Lever", Vector3.new(0.08, 0.5, 0.14), CFrame.new(0.2, 0.05, 0), dark)
		add("Top", Vector3.new(0.16, 0.16, 0.16), CFrame.new(0, 0.28, 0), dark)
	elseif kind == "Semtex" then
		add("Brick", Vector3.new(0.5, 0.2, 0.4), CFrame.new(), color, Enum.Material.SmoothPlastic)
		add("Wire", Vector3.new(0.05, 0.05, 0.3), CFrame.new(0, 0.14, 0), dark)
	elseif kind == "Canister" then
		add("Can", Vector3.new(0.7, 0.4, 0.4), CFrame.new() * cylRot, color, Enum.Material.Metal, Enum.PartType.Cylinder)
		add("Cap", Vector3.new(0.12, 0.42, 0.42), CFrame.new(0, 0.38, 0) * cylRot, dark, Enum.Material.Metal, Enum.PartType.Cylinder)
		add("Lever", Vector3.new(0.07, 0.5, 0.12), CFrame.new(0.22, 0.1, 0), dark)
	elseif kind == "Claymore" then
		add("Body", Vector3.new(0.9, 0.5, 0.2), CFrame.new() * CFrame.Angles(rad(-8), 0, 0), color, Enum.Material.SmoothPlastic)
		add("Eye", Vector3.new(0.1, 0.1, 0.1), CFrame.new(0, 0.3, 0), dark)
	elseif kind == "C4" then
		add("Brick", Vector3.new(0.6, 0.3, 0.5), CFrame.new(), color, Enum.Material.SmoothPlastic)
		add("Antenna", Vector3.new(0.04, 0.4, 0.04), CFrame.new(0.2, 0.3, 0), dark)
		add("Led", Vector3.new(0.08, 0.04, 0.08), CFrame.new(-0.15, 0.17, 0), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	elseif kind == "Knife" then
		add("Handle", Vector3.new(0.1, 0.1, 0.35), CFrame.new(0, 0, 0.2), dark, Enum.Material.SmoothPlastic)
		add("Blade", Vector3.new(0.03, 0.18, 0.6), CFrame.new(0, 0, -0.28), color)
	elseif kind == "Syringe" then
		add("Barrel", Vector3.new(0.5, 0.16, 0.16), CFrame.new() * CFrame.Angles(0, rad(90), 0), color, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		add("Needle", Vector3.new(0.04, 0.04, 0.3), CFrame.new(0, 0, -0.4), Color3.fromRGB(200, 200, 205))
		add("Plunger", Vector3.new(0.2, 0.2, 0.05), CFrame.new(0, 0, 0.3), dark)
	elseif kind == "Sensor" then
		add("Body", Vector3.new(0.4, 0.7, 0.12), CFrame.new(), color, Enum.Material.SmoothPlastic)
		add("Screen", Vector3.new(0.32, 0.4, 0.02), CFrame.new(0, 0.08, -0.07), Color3.fromRGB(60, 255, 120), Enum.Material.Neon)
	elseif kind == "Plate" then
		I.Mid = true
		add("Plate", Vector3.new(0.9, 1.1, 0.12), CFrame.new(), Color3.fromRGB(70, 74, 70), Enum.Material.Metal)
		add("Trim", Vector3.new(0.7, 0.9, 0.14), CFrame.new(), Color3.fromRGB(40, 42, 40), Enum.Material.SmoothPlastic)
	end
	return I
end

function ItemBuilder.Pose(I, cf, transparency)
	for _, p in I.Parts do
		p.Part.CFrame = cf * p.Rel
		p.Part.Transparency = transparency or 0
	end
end

return ItemBuilder
