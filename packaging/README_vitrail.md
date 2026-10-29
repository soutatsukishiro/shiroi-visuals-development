# Shiroi Visuals (Vitrail edition)

A shader pack for Minecraft Java Edition with soft, colourful lighting: a bright sky that changes through the day,
clear water, sharp pixel shadows and gentle fog. This edition is for Vitrail, which runs shader packs on
Minecraft's Vulkan renderer.

## What you need

- Minecraft 26.3 with Fabric
- Vitrail 0.13.0-beta (for Minecraft 26.3) and Sodium 0.9.2
- A graphics card that Vitrail supports

Vitrail is still in beta, so other Vitrail or Minecraft versions may not work.

## How to install

1. Put the ZIP file in your `shaderpacks` folder. Don't unzip it.
2. Pick Shiroi Visuals in Vitrail's shader menu and reload the shader pack.

If you use Iris (OpenGL), get the Iris edition instead.

## How this edition differs

Vitrail doesn't run the extra shader stage that the Iris edition uses to split the shadow map into several
detail levels. So this edition uses one shadow map for the whole view. Shadows close to you look the same;
far away they have less detail, and small gaps between leaves can blur together.

Everything else works the same, including the settings, see the Iris edition's notes below.

## Settings

Start with a preset at the top of the shader menu:

- **Ultra Low**: for integrated or very weak graphics cards.
- **Low**: older entry-level cards.
- **Medium**: the default, and the look the pack was made for.
- **High**: finer fog and reflections. Costs more.

A few settings worth knowing about:

- **Post processing → Internal resolution**: 85% renders fewer pixels and rebuilds the image with TAA.
- **Post processing → TAA anti-flicker**: stops thin edges, like leaves against the sky, from blinking.
- **Sky and Clouds → Sun halo strength** and **Celestial Bloom Strength**: how much the sun glows.
- **Post processing → Biome colour grading**: snowy biomes look cooler, jungles and deserts warmer.

## Things to know

- Coloured light from torches is always on. Soul torches and soul fire light the area teal, copper torches green
  and redstone torches red. Normal torches and lamps look the same as before.
- Torches and lanterns glow in your hand too, just like when they're placed.
- Wet farmland, armour, fallen leaves, petals and metal and ore blocks reflect light in their own way, even
  without a PBR resource pack.

## Mods

See [MOD_SUPPORT.md](MOD_SUPPORT.md).

## Credits

Made by soutatsukishiro. The source is at https://github.com/soutatsukishiro/shiroi-visuals-development. You
can modify it and make your own packs from it, with credit; see [LICENSE](LICENSE). The ACES tonemap curve is by
Stephen Hill (MIT licence), see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.
