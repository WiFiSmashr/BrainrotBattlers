# Character artwork (shop and unit card)

Drop each character's PNG here, named after its unit id: `noodle_nugget.png`, `sleepy_sock.png`, and so on
(ids are in `src/shared/Data/Units.luau`; `src/shared/Data/Portraits.luau` lists them all).

Roblox cannot read these files directly, and Rojo does not sync images, so this folder is your source copy.
To use one in the game:

1. Upload it to Roblox: in Studio open View > Asset Manager, then Bulk Import (or Create > Decals).
2. Copy the asset id number.
3. In `src/shared/Data/Portraits.luau`, remove the `--` from that character's line and paste the id.

See `docs/PORTRAITS.md` for details.
