--!strict
-- Spell Sponge (GDD 9.4): negate the first instance of ability damage taken each fight (a generic
-- negate charge that SimEvents consumes); after that, gain mana per ability hit (with a cooldown).

local Types = require(game:GetService("ReplicatedStorage").Shared.Types)

local module: Types.EffectModule = {
	id = "spell_sponge",
	attach = function(ctx)
		ctx.owner.counters.negateAbility = 1
		ctx.state.nextAt = 0
	end,
	detach = function(ctx)
		ctx.owner.counters.negateAbility = nil
	end,
	hooks = {
		OnDamageTaken = function(ctx, event)
			local owner = ctx.owner
			if event.target ~= owner or not event.isAbility or (owner.counters.negateAbility or 0) > 0 then
				return
			end
			if ctx.sim.time + 1e-6 >= ctx.state.nextAt then
				ctx.state.nextAt = ctx.sim.time + ctx.params.cooldown
				owner.mana = math.min(owner.mana + ctx.params.mana, owner.maxMana)
			end
		end,
	},
}

return module
