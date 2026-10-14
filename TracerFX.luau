-- TracerFX: draws a bullet tracer in the equipped style. Used by WeaponController for your own shots and for everybody else's (FireFX).
-- The style id comes from the shooter's "CosTracer" player attribute (set by CosmeticsService). Styles are in Cosmetics.luau.
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Cosmetics = require(script.Parent.Cosmetics)

local TracerFX = {}

function TracerFX.Def(id)
	return Cosmetics.Get("Tracer", id) or Cosmetics.Get("Tracer", "Classic")
end

local function pickColor(d)
	if d.Rainbow then return Color3.fromHSV((os.clock() * 0.7 + math.random() * 0.25) % 1, 0.85, 1) end
	return d.Color
end

-- color used for impact sparks and previews
function TracerFX.Color(id)
	return pickColor(TracerFX.Def(id))
end

-- builds the glowing streak (part + optional trail + optional sparks). The caller positions it.
local function makeStreak(d, color, len)
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material, p.Color, p.Transparency = Enum.Material.Neon, color, 0.15
	p.Size = Vector3.new(d.Width, d.Width, len)
	p.Parent = workspace.CurrentCamera

	local a0, a1
	if d.Trail then -- glowing ribbon that follows the streak
		a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, d.Width * 2.2, -len / 2), Vector3.new(0, -d.Width * 2.2, -len / 2)
		a0.Parent, a1.Parent = p, p
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Lifetime, tr.LightEmission, tr.FaceCamera = 0.16, 1, true
		tr.Color = d.Rainbow and ColorSequence.new({
			ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(1, Color3.fromHSV((select(1, color:ToHSV()) + 0.35) % 1, 0.85, 1)),
		}) or ColorSequence.new(color)
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		tr.Parent = p
	end

	local sparks
	if d.Sparks then
		sparks = Instance.new("ParticleEmitter")
		sparks.Rate, sparks.Lifetime, sparks.Speed = 140, NumberRange.new(0.15, 0.3), NumberRange.new(2, 6)
		sparks.SpreadAngle, sparks.LightEmission, sparks.Color = Vector2.new(180, 180), 1, ColorSequence.new(color)
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		sparks.Parent = p
	end
	return p, sparks, a0, a1
end

-- Hitscan tracer: a streak that flies from a to b at the style's visual speed (the shot itself already landed).
function TracerFX.Spawn(a, b, id)
	local d = TracerFX.Def(id)
	local delta = b - a
	local dist = delta.Magnitude
	if dist < 6 then return end
	local dir = delta.Unit
	local len = math.min(d.Length, dist)

	local p, sparks = makeStreak(d, pickColor(d), len)
	p.CFrame = CFrame.lookAt(a + dir * (len / 2), b)

	local tw = TweenService:Create(p, TweenInfo.new(math.clamp(dist / d.Speed, 0.03, 0.45), Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(b - dir * (len / 2), b) })
	tw.Completed:Once(function()
		p.Transparency = 1 -- keep the part a moment so the trail / sparks can fade out
		if sparks then sparks.Enabled = false end
		Debris:AddItem(p, 0.35)
	end)
	tw:Play()
end

-- ---- moving bullets (BulletFX) -------------------------------------------------------------------------------------------
-- Begin -> Place every frame -> Finish. The caller moves the streak along the real bullet path instead of a canned tween.
function TracerFX.Begin(id, len)
	local d = TracerFX.Def(id)
	len = math.max(len or d.Length, d.Length)
	local p, sparks, a0, a1 = makeStreak(d, pickColor(d), len)
	return { Part = p, Sparks = sparks, A0 = a0, A1 = a1, Width = d.Width, Len = len, MinLen = d.Length }
end

-- head = leading edge of the streak, dir = unit travel direction, len = streak length (stretches with speed so fast bullets stay a line)
function TracerFX.Place(h, head, dir, len)
	len = math.max(len or h.MinLen, h.MinLen)
	if math.abs(len - h.Len) > 0.05 then
		h.Len = len
		h.Part.Size = Vector3.new(h.Width, h.Width, len)
		if h.A0 then
			h.A0.Position = Vector3.new(0, h.Width * 2.2, -len / 2)
			h.A1.Position = Vector3.new(0, -h.Width * 2.2, -len / 2)
		end
	end
	local center = head - dir * (h.Len / 2)
	h.Part.CFrame = CFrame.lookAt(center, center + dir)
end

-- bullet is gone: let the trail / sparks fade, then clean up
function TracerFX.Finish(h)
	h.Part.Transparency = 1
	if h.Sparks then h.Sparks.Enabled = false end
	Debris:AddItem(h.Part, 0.35)
end

function TracerFX.Destroy(h) h.Part:Destroy() end

return TracerFX
