# Contributing

Thanks for wanting to help. A few things make changes easy to review and keep the pack fast.

## Reporting a bug

Open an issue with:

- what you see, ideally with a screenshot or a short clip;
- Minecraft, Iris (or Vitrail) and Sodium versions, your graphics card and driver;
- the preset and any settings you changed;
- for a crash or a black screen, the part of `logs/latest.log` that mentions shaders.

## Sending a change

1. Fork the repository and make a branch for your change.
2. Test it in game on Iris. If you touch shadows, `lib/common.glsl` or anything under `program/shadow.glsl`,
   also check the Vitrail edition (`python build.py --dev` and load the Vitrail folder).
3. Open a pull request saying what changed and why, with before/after screenshots for anything visual.

## What we care about

- **Speed.** The pack aims at around 120 fps on an RTX 3050 at 1080p. Say how much your change costs; a
  change that looks the same but runs faster is always welcome.
- **The look stays the same unless that's the point.** A fix or an optimisation shouldn't change the picture.
  If it does, mention it.
- **Comments explain why.** Match the style of the file you're in: a header that says what the file does, and
  comments for anything that isn't obvious.
- **Settings.** New options go in `lib/settings.glsl`, the menu in `shaders.properties`, and the text in
  `lang/en_us.lang`.
- **Mod blocks.** Check the registry name in game (F3 for blocks, F3 + H for items) before adding it to
  `block.properties`, and add the mod to `MOD_SUPPORT.md`.

By sending a pull request you agree that your change is released under the [Shiroi Visuals License](LICENSE).
