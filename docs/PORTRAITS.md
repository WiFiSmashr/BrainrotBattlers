# Shop artwork

Characters can show custom artwork in the shop and on the unit info card instead of their 3D model.

- Source PNGs live in `assets/portraits/<unit id>.png` (a place to keep them; the game does not read them).
- The game reads `src/shared/Data/Portraits.luau`, which maps a unit id to a Roblox image id
  (`rbxassetid://123`). See `assets/portraits/README.md` for the upload steps.
- A character with an entry shows its art, cropped to fill the shop slot. Its name, traits and price are
  drawn on dark strips over the art so they stay readable. A character without an entry keeps the model
  portrait (or the coloured tile if it has no model either).
- Images must be uploaded by the account or group that owns the experience.

## Shop highlights

- **Owned:** a teal outline and an "OWNED x2" tag when you already have a copy of that character on the board
  or bench.
- **Star up:** a gold outline and a "STAR UP" tag when buying that slot completes a merge (you own two copies
  at the same star level; or the full-bench double buy of D-54). It reads "STAR UP to 3" when the merge
  would also complete a star 3.
