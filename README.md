# Editing the level

- Open `Main.tscn`. Coins, wallets, safes, platforms, pits and portals are editable instances under `Level/Coins`, `Wallets`, `Safes`, `Platforms`, `Pits` and `Portals`; move them independently.
- Add or remove an item by duplicating its matching reusable scene (for example `CoinBlue.tscn` or `Wallet_Flying.tscn`) into its container. Coins are not children of platforms.
- Resize platforms with `width_tiles`. Resize pits with `width_tiles`; keep their left and right linked ground segments. The pit width also sets its fire and death area.
- The level alternates flat stretches and platform stretches. Move the `Flat_1`, `Platforms_1`, `Flat_2` and following markers under `Level/StretchMarkers` to plan the order; editor-placed items remain independent.
- Move `Level/StartPoint` to change where the opening swim ends. The intro lasts 1.25 seconds by default; adjust `INTRO_DURATION` in `scripts/game_config.gd`.
- Platforms use whole 64-pixel grid units through `width_tiles`. Their 50-pixel visual layer and one-way collision share `GROUND_TOP_THICKNESS` with the ground in `scripts/game_config.gd`; edit the shared ground top-layer drawing to keep its bands and pixel pattern consistent.
- The map has 19 coins, including one blue and one red special. Keep `MAP_COIN_COUNT`, `MAP_GOLD_COIN_COUNT`, and special coin counts in `scripts/game_config.gd` aligned with the editor-placed instances. The final ground stretch has ten coins for the $70 goal.
- Safes show editor warnings if their collision bounds overlap another object or if the final portal clearance is too small.
- Ground runs are single continuous segments between pits. Each pit uses even whole 64-pixel units so both ground edges stay on the level grid; its editor warning reports any edge mismatch.
- Grid snap is enabled at 4 pixels in the 2D editor for this scene. Toggle it with **Shift+G**. Use the scene’s group tags and readable names when adding instances.
- Leave the locked `Level` manager, `Ground`, `GroundDecorations`, `Hero`, `Camera2D`, `BackgroundLayers` and `UI` nodes in place. The manager provides their running visuals; object behavior and shared gameplay values live in each reusable scene and `scripts/game_config.gd`.
