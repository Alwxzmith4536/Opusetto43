-- Pure damage math (no Roblox APIs) so it can be unit tested outside Studio.

local DamageRules = {}

--[[
	How much damage a player actually takes from one hit.
	args = {
		Health, MaxHealth, Amount, Now,
		LastHitAt?, IFrameUntil?, Blocking?, Reduction? (0..1),
		Rules = Config.Player,
	}
	Returns damage, reason ("iframe" | "capped" | "laststand" | nil)
]]
function DamageRules.PlayerHit(args)
	local rules = args.Rules
	local now = args.Now

	if args.IFrameUntil and now < args.IFrameUntil then
		return 0, "iframe"
	end
	if args.LastHitAt and now - args.LastHitAt < rules.IFrameSeconds then
		return 0, "iframe"
	end

	local amount = math.max(0, args.Amount)
	if args.Blocking then
		amount *= 1 - rules.BlockReduction
	end
	if args.Reduction and args.Reduction > 0 then
		amount *= 1 - math.clamp(args.Reduction, 0, 1)
	end

	local reason = nil
	local cap = args.MaxHealth * rules.MaxHitFraction
	if amount > cap then
		amount = cap
		reason = "capped"
	end

	-- Last stand: from high health, a single hit always leaves you standing.
	if args.Health > args.MaxHealth * rules.LastStandThreshold and args.Health - amount < 1 then
		amount = math.max(0, args.Health - 1)
		reason = "laststand"
	end

	return math.floor(amount + 0.5), reason
end

-- Piercing Ox: the longer the charge before impact, the harder it hits.
function DamageRules.OxDamage(base, perStud, distance, maxDistance)
	return math.floor(base + perStud * math.clamp(distance, 0, maxDistance) + 0.5)
end

-- Boss max health scales with the number of players in the server.
function DamageRules.BossMaxHealth(baseHealth, perExtraPlayer, playerCount)
	return math.floor(baseHealth * (1 + math.max(0, playerCount - 1) * perExtraPlayer))
end

return DamageRules
