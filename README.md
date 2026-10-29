# Shiroi Visuals

A shader pack for Minecraft Java Edition with soft, colourful lighting: a bright sky that changes through the day,
clear water, sharp pixel shadows and gentle fog. It runs on Iris, and there's a separate edition for Vitrail
(Minecraft's Vulkan renderer).

This repository is the source of the pack. If you just want to play with it, grab a ZIP from
[Releases](https://github.com/soutatsukishiro/shiroi-visuals-development/releases) and see
[packaging/README_iris.md](packaging/README_iris.md) for how to install it.

You're welcome to change it and to make your own shader packs from it. See [License](#license) for the few rules.

## Requirements

- Minecraft 26.3 with Fabric
- Iris 1.11.7 and Sodium 0.9.2, or Vitrail 0.13.0-beta for the Vitrail edition
- A graphics card with OpenGL 4.3 (compute shaders). It was tuned on an RTX 3050 6 GB.

## Working on the pack

The fastest way to work is to load the `shaders/` folder straight from the game:

1. Copy or link this whole repository folder into `.minecraft/shaderpacks/`. Iris loads any folder that has a
   `shaders/` folder inside.
2. Pick it in the shader menu. After editing a file, press **R** in game (Iris' reload key) to see the change.

Iris shows compile errors in the chat and writes the details to `logs/latest.log`.

On Windows you can link instead of copying, so your edits are live:

```
mklink /J "%APPDATA%\.minecraft\shaderpacks\Shiroi Visuals dev" "C:\path\to\shiroi-visuals-development"
```

## Building the ZIPs

```
python build.py
```

This writes `dist/Shiroi Visuals <version>.zip` and `dist/Shiroi Visuals <version> for Vitrail.zip`. You only need
Python 3.8 or newer, nothing else. The version comes from the `VERSION` file. `python build.py --dev` also unpacks
both editions into `dist/` as folders.

Both editions come from the same `shaders/` folder. For Vitrail, `build.py` turns on
`SHIROI_VITRAIL_SINGLE_CASCADE` in `lib/common.glsl` and leaves out the shadow geometry shaders (`*.gsh`), which
Vitrail can't run. So the Vitrail edition uses one shadow map for the whole view instead of four cascades.

## Repository layout

| Path | What's there |
|---|---|
| `shaders/` | The shader pack itself (this is what goes in the ZIP) |
| `shaders/shaders.properties` | Pipeline setup: passes, render targets, custom images and buffers, the settings menu |
| `shaders/lib/settings.glsl` | Every user setting and its default |
| `shaders/lib/look.glsl` | The numbers that define the look: sky colours, sun and moon, fog |
| `shaders/block.properties`, `item.properties` | Which blocks and items get which material |
| `shaders/lang/en_us.lang` | Names and descriptions shown in the settings menu |
| `shaders/program/` | The body of each pass. The small `.vsh`/`.fsh`/`.csh` files at the top level only set a few defines and include one of these |
| `shaders/lib/` | Shared code: lighting, shadows, sky, clouds, TAA, materials and more |
| `shaders/world-1/`, `shaders/world1/` | Nether and End versions of the passes |
| `packaging/` | The README that goes inside each ZIP |
| `docs/ARCHITECTURE.md` | How a frame is drawn, pass by pass |
| `build.py` | Builds the two ZIPs |

Each file starts with a comment explaining what it does, and most of the code says why it's written that way.
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) is a good place to start.

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Shiroi Visuals uses its own license, the [Shiroi Visuals License](LICENSE). In short:

- You can use it, modify it, and make and share your own shader packs based on it, for free.
- Give credit with a link to this repository, keep the license file, and release your version under the same
  license.
- Don't re-upload the unchanged pack as your own, don't sell it or put it behind a paywall, and don't call your
  version "Shiroi Visuals".

The ACES tonemap curve comes from Stephen Hill and MJP's BakingLab under the MIT licence; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT.
