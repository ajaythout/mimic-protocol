--!strict
--[[
	Targeting
	Pure target selection shared by every "act on whoever is in front of me"
	ability (Assimilate, Identity Theft, Containment Scanner). The server
	gathers candidate positions and supplies the line-of-sight test; this
	module only does the geometry, so it can be unit-tested with Lune.

	A candidate qualifies when it is within Range and either within
	CloseRange (any direction) or roughly in front: the cosine between the
	horizontal facing and the horizontal direction to it is at least
	FacingDot. The nearest qualifying candidate with line of sight wins.
]]

export type Rules = {
	Range: number,
	FacingDot: number,
	CloseRange: number,
}

export type Candidate<T> = {
	position: Vector3,
	item: T,
}

local Targeting = {}

function Targeting.pick<T>(
	origin: Vector3,
	look: Vector3,
	candidates: { Candidate<T> },
	rules: Rules,
	hasLineOfSight: (from: Vector3, to: Vector3) -> boolean
): T?
	-- Horizontal facing; a straight up/down look counts as facing +Z.
	local fx, fz = look.X, look.Z
	local length = math.sqrt(fx * fx + fz * fz)
	if length < 1e-3 then
		fx, fz, length = 0, 1, 1
	end
	fx, fz = fx / length, fz / length

	local best: T? = nil
	local bestDistance = rules.Range
	for _, candidate in candidates do
		local dx = candidate.position.X - origin.X
		local dy = candidate.position.Y - origin.Y
		local dz = candidate.position.Z - origin.Z
		local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
		if distance <= bestDistance then
			local flat = math.sqrt(dx * dx + dz * dz)
			local inFront = flat > 1e-3 and (fx * dx + fz * dz) / flat >= rules.FacingDot
			if (distance <= rules.CloseRange or inFront) and hasLineOfSight(origin, candidate.position) then
				best = candidate.item
				bestDistance = distance
			end
		end
	end
	return best
end

return Targeting
