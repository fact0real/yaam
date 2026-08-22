# YAAM App Icon

`YAAM-AppIcon-1024.png` is the production master for the flattened macOS icon set.
The previous artwork and its original asset metadata are preserved in `Legacy-v1`.

## Xcode asset slots

| Slot | Pixel dimensions | File |
| --- | ---: | --- |
| 16 pt @1x | 16 x 16 | `icon_16x16.png` |
| 16 pt @2x | 32 x 32 | `icon_16x16@2x.png` |
| 32 pt @1x | 32 x 32 | `icon_32x32.png` |
| 32 pt @2x | 64 x 64 | `icon_32x32@2x.png` |
| 128 pt @1x | 128 x 128 | `icon_128x128.png` |
| 128 pt @2x | 256 x 256 | `icon_128x128@2x.png` |
| 256 pt @1x | 256 x 256 | `icon_256x256.png` |
| 256 pt @2x | 512 x 512 | `icon_256x256@2x.png` |
| 512 pt @1x | 512 x 512 | `icon_512x512.png` |
| 512 pt @2x | 1024 x 1024 | `icon_512x512@2x.png` |

Keep every file referenced by `Contents.json` inside `AppIcon.appiconset`. Store source,
legacy, or `.icns` files outside the asset set so Xcode does not report unassigned children.

For a fully dynamic Liquid Glass icon, open Xcode > Open Developer Tool > Icon Composer
on macOS 26.4 or later and recreate this mark as separate background, logbook, antenna,
and signal layers. Keep the asset catalog as the compatibility icon for older macOS releases.
