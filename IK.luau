-- Analytic two-bone IK (law of cosines) with a pole/hint point for the elbow.
local IK = {}

function IK.Solve(shoulder, target, hint, l1, l2)
	local to = target - shoulder
	local dist = math.clamp(to.Magnitude, math.abs(l1 - l2) + 0.01, l1 + l2 - 0.01)
	local dir = to.Magnitude > 1e-4 and to.Unit or Vector3.new(0, 0, -1)

	local cosA = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
	local a = math.acos(math.clamp(cosA, -1, 1))

	local h = hint - shoulder
	local perp = h - dir * h:Dot(dir)
	if perp.Magnitude < 1e-4 then perp = dir:Cross(Vector3.yAxis) end
	if perp.Magnitude < 1e-4 then perp = Vector3.xAxis end
	perp = perp.Unit

	local elbow = shoulder + (dir * math.cos(a) + perp * math.sin(a)) * l1
	return elbow, shoulder + dir * dist
end

-- CFrame for a part of length `len` (Size.Z) stretched from a to b.
function IK.Segment(a, b, len, up)
	local dir = b - a
	if dir.Magnitude < 1e-4 then return CFrame.new(a) end
	if dir.Unit:Cross(up).Magnitude < 1e-3 then up = Vector3.yAxis end
	return CFrame.lookAt(a, b, up) * CFrame.new(0, 0, -len / 2)
end

return IK
