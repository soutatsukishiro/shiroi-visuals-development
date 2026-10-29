# Shiroi Visuals

A shader pack for Minecraft Java Edition with soft, colourful lighting: a bright sky that changes through the day,
clear water, sharp pixel shadows and gentle fog.

## What you need

- Minecraft 26.3 with Fabric
- Iris 1.11.7 and Sodium 0.9.2 (the versions it was tested with)
- A graphics card with OpenGL 4.3 (compute shaders). It was tuned on an RTX 3050 6 GB.

## How to install

1. Put the ZIP file in your `.minecraft/shaderpacks` folder. Don't unzip it.
2. In game, open Options → Video Settings → Shader Packs and pick Shiroi Visuals.

There is a separate Vitrail edition for Minecraft's Vulkan renderer. Use the one that matches your setup.

## Settings

Start with a preset at the top of the shader menu:

- **Ultra Low**: for integrated or very weak graphics cards.
- **Low**: older entry-level cards.
- **Medium**: the default, and the look the pack was made for.
- **High**: finer fog and reflections. Costs more.

A few settings worth knowing about:

- **Post processing → Internal resolution**: 85% renders fewer pixels and rebuilds the image with TAA. It's faster
  and looks close to native.
- **Post processing → TAA anti-flicker**: stops thin edges, like leaves against the sky, from blinking.
- **Sky and Clouds → Sun halo strength** and **Celestial Bloom Strength**: how much the sun glows.
- **Post processing → Biome colour grading**: snowy biomes look cooler, jungles and deserts warmer.

## Things to know

- Coloured light from torches is always on. Soul torches and soul fire light the area teal, copper torches green
  and redstone torches red. Normal torches and lamps look the same as before.
- Torches and lanterns glow in your hand too, and light up the area around you in their own colour.
- Wet farmland, armour, fallen leaves, petals and metal and ore blocks reflect light in their own way, even
  without a PBR resource pack.
- If you use a PBR resource pack, its material maps are used instead.

### Minecraft 1.21.1 clouds

On 1.21.1 with Sodium, the clouds can disappear while shaders are on. To bring them back, close the game,
open `config/sodium-mixins.properties` in your instance (create it if it doesn't exist), add this line and save:

```
mixin.features.render.world.clouds=false
```

This only changes how Sodium draws clouds. Add the line; don't replace the whole file.

## Mods

The pack recognises some blocks from Create, Mekanism, AE2, Farmer's Delight, Biomes O' Plenty, Immersive
Engineering and Cobblemon (leaves, plants, glass, glowing blocks). See [MOD_SUPPORT.md](MOD_SUPPORT.md). Blocks from
other mods still work; they just use the default material.

## Credits

Made by soutatsukishiro. The source is at https://github.com/soutatsukishiro/shiroi-visuals-development. You
can modify it and make your own packs from it, with credit; see [LICENSE](LICENSE). The ACES tonemap curve is by
Stephen Hill (MIT licence), see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.
