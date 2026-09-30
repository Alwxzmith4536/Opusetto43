-- Unit tests for the pure modules. run_tests.mjs prepends Config, DamageRules and Adaptation.

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  pass  " .. name)
	else
		failed += 1
		print("  FAIL  " .. name .. "\n        " .. tostring(err))
	end
end
local function eq(a, b, msg)
	if a ~= b then
		error((msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a), 2)
	end
end

local P = Config.Player
local B = Config.Boss

local function hit(health, amount, extra)
	local args = { Health = health, MaxHealth = P.MaxHealth, Amount = amount, Now = 100, Rules = P }
	for k, v in pairs(extra or {}) do
		args[k] = v
	end
	return DamageRules.PlayerHit(args)
end

---------------------------------------------------------------- anti one-shot

test("a heavy Mahoraga hit is capped at 20% of max health", function()
	local dmg, reason = hit(250, B.Attacks.WorldSlash.Damage)
	eq(dmg, 50)
	eq(reason, "capped")
end)

test("no single hit can kill a player above 35% health, whatever the damage", function()
	for _, health in ipairs({ 250, 200, 150, 100, 88 }) do
		for _, amount in ipairs({ 1, 50, 300, 1e6, 1e12 }) do
			local dmg = hit(health, amount)
			assert(health - dmg >= 1, ("health %d amount %d dealt %d"):format(health, amount, dmg))
		end
	end
end)

test("from full health it takes at least 5 of Mahoraga's strongest hits to go down", function()
	local strongest = 0
	for _, a in pairs(B.Attacks) do
		strongest = math.max(strongest, a.Damage)
	end
	local health, hits, now = P.MaxHealth, 0, 0
	while health > 0 do
		local dmg = DamageRules.PlayerHit({ Health = health, MaxHealth = P.MaxHealth, Amount = strongest, Now = now, LastHitAt = now - 1, Rules = P })
		health -= dmg
		hits += 1
		now += 1
		assert(hits < 100, "never died")
	end
	assert(hits >= 5, "died in " .. hits .. " hits")
end)

test("i-frames: a second hit right after the first does nothing", function()
	local dmg, reason = hit(250, 40, { LastHitAt = 100 - P.IFrameSeconds / 2 })
	eq(dmg, 0)
	eq(reason, "iframe")
	eq(hit(250, 40, { LastHitAt = 100 - P.IFrameSeconds - 0.01 }), 40)
end)

test("Shadow Travel / Rabbit Escape i-frames ignore damage", function()
	eq(hit(250, 40, { IFrameUntil = 101 }), 0)
end)

test("guard (F) removes 60% of the damage", function()
	eq(hit(250, 40, { Blocking = true }), 16)
end)

test("Round Deer damage reduction stacks with guard", function()
	eq(hit(250, 40, { Blocking = true, Reduction = 0.3 }), 11) -- 40 * 0.4 * 0.7 = 11.2
end)

test("below the last-stand threshold hits can finish you (the boss still matters)", function()
	local dmg = hit(40, 45)
	assert(40 - dmg <= 0, "a low-health player should be finishable, dealt " .. dmg)
end)

---------------------------------------------------------------- adaptation

test("first hits of a new technique land at full strength", function()
	local a = Adaptation.new(B)
	local m = a:RegisterHit("Lightning")
	eq(m, 1)
end)

test("the wheel turns every HitsPerTurn hits and adapts after TurnsToAdapt turns", function()
	local a = Adaptation.new(B)
	local turns, completedAt = 0, nil
	for i = 1, B.HitsPerTurn * B.TurnsToAdapt do
		local _, turned, completed = a:RegisterHit("Water")
		if turned then
			turns += 1
		end
		if completed then
			completedAt = i
		end
	end
	eq(turns, B.TurnsToAdapt)
	eq(completedAt, B.HitsPerTurn * B.TurnsToAdapt)
	assert(a:IsAdapted("Water"))
	eq(a:Multiplier("Water"), B.AdaptedMultiplier)
	eq(a.TotalTurns, B.TurnsToAdapt)
end)

test("damage falls off turn by turn", function()
	local a = Adaptation.new(B)
	local last = 2
	for _ = 1, B.TurnsToAdapt do
		local m = a:Multiplier("Claw")
		assert(m < last, "multiplier did not fall")
		last = m
		for _ = 1, B.HitsPerTurn do
			a:RegisterHit("Claw")
		end
	end
	eq(a:Multiplier("Claw"), B.AdaptedMultiplier)
end)

test("adaptation is per technique", function()
	local a = Adaptation.new(B)
	for _ = 1, B.HitsPerTurn * B.TurnsToAdapt do
		a:RegisterHit("Claw")
	end
	eq(a:Multiplier("Lightning"), 1)
	eq(a:AdaptedCount(), 1)
	eq(a.Order[1], "Claw")
end)

test("rotating techniques beats spamming one (the intended way to win)", function()
	local function fight(pattern)
		local a = Adaptation.new(B)
		local total = 0
		for i = 1, 60 do
			local t = pattern[(i - 1) % #pattern + 1]
			local m = a:RegisterHit(t)
			total += 200 * B.BaseDamageTaken * m
		end
		return total
	end
	local spam = fight({ "Claw" })
	local rotate = fight({ "Claw", "Lightning", "Bite", "Water", "Pierce", "Rend" })
	assert(rotate > spam * 2, ("rotate %d vs spam %d"):format(rotate, spam))
end)

---------------------------------------------------------------- misc math

test("Piercing Ox hits harder the longer it charges", function()
	local ox = Config.Abilities.PiercingOx
	eq(DamageRules.OxDamage(ox.BaseDamage, ox.DamagePerStud, 0, ox.MaxDistance), 150)
	eq(DamageRules.OxDamage(ox.BaseDamage, ox.DamagePerStud, 90, ox.MaxDistance), 690)
	eq(DamageRules.OxDamage(ox.BaseDamage, ox.DamagePerStud, 500, ox.MaxDistance), 690)
end)

test("Mahoraga's health scales with the server size", function()
	eq(DamageRules.BossMaxHealth(B.MaxHealth, B.HealthPerExtraPlayer, 1), 16000)
	eq(DamageRules.BossMaxHealth(B.MaxHealth, B.HealthPerExtraPlayer, 3), 35200)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("unit tests failed")
end
