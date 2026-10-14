-- Damped spring on Vector3. Use .X for scalar springs.
-- speed = natural frequency (rad/s), ratio = damping ratio (1 = critical, <1 = bouncy)
local Spring = {}
Spring.__index = Spring

function Spring.new(speed, ratio, initial)
	local p = initial or Vector3.zero
	return setmetatable({
		Speed = speed, Ratio = ratio,
		Position = p, Velocity = Vector3.zero, Target = p,
	}, Spring)
end

function Spring:Impulse(v)
	self.Velocity += v
end

function Spring:Update(dt)
	dt = math.min(dt, 1 / 20)
	local steps = 4
	local h = dt / steps
	local k, d = self.Speed ^ 2, 2 * self.Ratio * self.Speed
	for _ = 1, steps do
		local acc = (self.Target - self.Position) * k - self.Velocity * d
		self.Velocity += acc * h
		self.Position += self.Velocity * h
	end
	return self.Position
end

return Spring
