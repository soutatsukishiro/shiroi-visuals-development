# Mod support

The pack gives some blocks from these mods the same material as their vanilla counterparts. The names were taken
from each mod's source code. "Partial" means only the blocks listed here are covered; the mods weren't tested
in game.

| Mod | Blocks covered | Status |
|---|---|---|
| Cobblemon 1.8.3 | apricorn and saccharine leaves; apricorn and saccharine saplings; Pokémon use the entity material | Partial |
| Create 6.0.x | experience block (glows); zinc ore and deepslate zinc ore | Partial |
| Mekanism 10.7 | structural glass | Partial |
| Applied Energistics 2 | quartz glass | Partial |
| Farmer's Delight 1.3 | cabbages, onions, tomatoes, rice (and their wild versions); lit stove (glows) | Partial |
| Biomes O' Plenty | fir and redwood leaves; redwood sapling; lavender | Partial |
| Immersive Engineering 12.4 | hemp | Partial |

Not covered yet: Regions Unexplored and Thermal.

Blocks that aren't listed still render normally, with the default material. Machines, screens, fluids and
special renderers from these mods use the default path too.

## Adding a mod

1. In game, press F3 and look at the block to see its name (F3 + H shows item names).
2. In `shaders/block.properties`, add the name to the line of the material you want (leaves, plants, glass,
   glowing...). Keep the vanilla names on that line: if you write a new line with the same number, it replaces
   the old one.
