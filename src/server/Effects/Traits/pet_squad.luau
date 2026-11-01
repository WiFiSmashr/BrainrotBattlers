--!strict
-- Pet Squad (GDD 8.3): at combat start summon Pets with a share of the members' average Health and
-- AD; the top tier makes Pets explode on death. Pets are tokens (D-25).

local Shared = game:GetService("ReplicatedStorage").Shared
local Types = require(Shared.Types)
local StatBlock = require(script.Parent.Parent.Parent.Combat.StatBlock)
local Targeting = require(script.Parent.Parent.Parent.Combat.Targeting)

local module: Types.EffectModule = {
	id = "pet_squad",
	attach = function(ctx, p)
		local count = #ctx.members
		if count == 0 then
			return
		end
		local health, ad = 0, 0
		for _, u in ctx.members do
			health += StatBlock.get(u.stats.maxHealth)
			ad += StatBlock.get(u.stats.ad)
		end
		local def = {
			name = "Pet", health = health / count * p.statPct, ad = ad / count * p.statPct,
			onSpawn = function(_, pet)
				pet.counters.pet = 1
			end,
		}
		for i = 1, p.pets do
			ctx.summon(ctx.members[(i - 1) % count + 1], def)
		end
	end,
	detach = function() end,
	hooks = {
		OnDeath = function(ctx, event)
			local pet = event.victim
			if pet.counters.pet ~= 1 or pet.team ~= ctx.team or ctx.params.explosion <= 0 then
				return
			end
			for _, enemy in Targeting.enemiesWithin(ctx.sim, pet, pet.cell, 1) do
				ctx.queueDamage(nil, enemy, ctx.params.explosion, "Magic", { isAbility = true })
			end
		end,
	},
}

return module
