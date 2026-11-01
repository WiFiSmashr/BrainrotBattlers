--!strict
-- Shop and unit-card artwork (docs/PORTRAITS.md). Put a character's image here as its Roblox asset id
-- and the shop shows the art instead of its 3D model. A character with no entry keeps the model portrait,
-- so art can be added one character at a time.
--
-- Steps: drop the PNG in assets/portraits/<unit id>.png (your source copy), upload it to Roblox (Studio:
-- View > Asset Manager > Bulk Import, or Create > Decals), then paste the number below:
--
--   noodle_nugget = "rbxassetid://1234567890",
--
-- Keys are unit ids from Shared/Data/Units. Images are shown square-cropped, so about 400 x 400 or larger
-- with the character centred works best.

local Portraits: { [string]: string } = {
	noodle_nugget = "rbxassetid://81378815670511",
	sleepy_sock = "rbxassetid://76841869821796",
	moo_moo_mogul = "rbxassetid://113148391830841",
	zippy_zucchini = "rbxassetid://90405234434818",
	pixel_pup = "rbxassetid://110569174125838",
	rizz_rabbit = "rbxassetid://98071739041805",
	wobble_banana = "rbxassetid://73537248065774",
	mini_mod = "rbxassetid://126066037488262",
	lag_lizard = "rbxassetid://96146199615661",
	pocket_pharaoh = "rbxassetid://94073350187307",
	smooch_snail = "rbxassetid://133120967335916",
	-- newbie_knight = "rbxassetid://",
	-- grumpy_gelato = "rbxassetid://",
	-- auntie_aura = "rbxassetid://",
	-- respawn_rascal = "rbxassetid://",
	-- sniper_sprout = "rbxassetid://",
	-- cash_cat = "rbxassetid://",
	-- sir_slaysalot = "rbxassetid://",
	-- ban_hammer_bear = "rbxassetid://",
	-- spoiled_spaghetti = "rbxassetid://",
	-- lootbox_lemur = "rbxassetid://",
	-- rotzilla_prime = "rbxassetid://",
	-- grand_rizzmaster = "rbxassetid://",
	-- granny_glitchgun = "rbxassetid://",
}

return Portraits
