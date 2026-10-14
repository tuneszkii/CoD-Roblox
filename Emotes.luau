-- Emotes: procedural poses for the third-person rig (ThirdPerson.luau) and the Cosmetics menu preview (RigPreview.luau).
-- Nothing here needs an animation asset. An emote is a function of time that returns a pose:
--   Torso = CFrame offset applied to the torso (lean / twist / bob),   Head = extra head offset,
--   R / L = hand CFrames relative to the chest (studs, character faces -Z). nil = leave the arm at rest.
-- Add an emote: one entry in Emotes.Defs + its id in Emotes.List, then one line in Cosmetics.luau (name / unlock level / rarity).
local Emotes = {}

local CF, A = CFrame.new, CFrame.Angles
local rad, sin, cos, abs = math.rad, math.sin, math.cos, math.abs

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
Emotes.Smooth = smooth

Emotes.BlendTime = 0.25 -- seconds to blend in and out

Emotes.Defs = {
	Wave = { Name = "Wave", Duration = 2.6, Pose = function(t)
		local s = sin(t * 11)
		return { Torso = A(0, rad(8), 0), Head = A(0, rad(-10), rad(4)), R = CF(1.25 + s * 0.12, 1.45, -0.3) * A(0, 0, s * 0.5) }
	end },

	Salute = { Name = "Salute", Duration = 2.2, Pose = function(t)
		return { Torso = A(rad(-3), 0, 0), Head = A(rad(-4), 0, 0), R = CF(0.28, 1.28, -0.62) * A(rad(10), rad(-20), rad(60)) }
	end },

	Point = { Name = "Point", Duration = 2.0, Pose = function(t)
		local s = sin(t * 5)
		return { Torso = A(0, rad(-18), 0), Head = A(0, rad(18), 0), R = CF(0.55, 0.35 + s * 0.03, -2.0) }
	end },

	Shrug = { Name = "Shrug", Duration = 2.0, Pose = function(t)
		local s = sin(t * 5) * 0.08
		return { Torso = CF(0, 0.04, 0), Head = A(rad(-6), 0, rad(10)),
			R = CF(1.7, -0.2 + s, -0.7) * A(0, 0, rad(-20)), L = CF(-1.7, -0.2 + s, -0.7) * A(0, 0, rad(20)) }
	end },

	Flex = { Name = "Flex", Duration = 2.6, Pose = function(t)
		local s = sin(t * 8) * 0.05
		return { Torso = CF(0, 0.04, 0) * A(rad(-8), 0, 0), Head = A(rad(8), 0, 0),
			R = CF(1.6, 0.9 + s, -0.2), L = CF(-1.6, 0.9 - s, -0.2) }
	end },

	Facepalm = { Name = "Facepalm", Duration = 2.4, Pose = function(t)
		return { Torso = A(rad(14), 0, sin(t * 3) * 0.03), Head = A(rad(28), 0, 0), R = CF(0.25, 1.0, -0.65) * A(rad(-30), 0, 0) }
	end },

	Cheer = { Name = "Cheer", Duration = 3.0, Pose = function(t)
		local s = sin(t * 9)
		return { Torso = CF(0, abs(sin(t * 6)) * 0.15, 0) * A(rad(-6), 0, 0), Head = A(rad(-18), 0, 0),
			R = CF(1.0 + s * 0.1, 1.9 + s * 0.15, -0.2), L = CF(-1.0 - s * 0.1, 1.9 - s * 0.15, -0.2) }
	end },

	Dance = { Name = "Dance", Duration = 12.0, Pose = function(t)
		local s, c = sin(t * 7), cos(t * 7)
		return { Torso = CF(0, -abs(s) * 0.35, 0) * A(0, s * 0.45, c * 0.12), Head = A(0, -s * 0.3, -c * 0.08),
			R = CF(1.2 + s * 0.2, 0.9 + c * 0.6, -0.5), L = CF(-1.2 + s * 0.2, 0.9 - c * 0.6, -0.5) }
	end },
}

Emotes.List = { "Wave", "Salute", "Point", "Shrug", "Flex", "Facepalm", "Cheer", "Dance" }

-- pose, weight (0..1 blend). Returns nil when the emote is over (or unknown).
function Emotes.Sample(id, t)
	local d = Emotes.Defs[id]
	if not d or t < 0 or t > d.Duration then return nil end
	local w = smooth(t / Emotes.BlendTime) * smooth((d.Duration - t) / Emotes.BlendTime)
	return d.Pose(t), w
end

return Emotes
