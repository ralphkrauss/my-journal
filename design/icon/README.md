# App icon

The app icon is a handwritten deep-navy "My" on warm paper-white.

## Files

| Path | Contents |
| --- | --- |
| `source/chosen-artwork.png` | The chosen artwork (1024 × 1024, opaque). Everything else is derived from it. |
| `layers/lettering.png` | The lettering alone: navy ink (sRGB 23, 44, 89) with anti-aliased transparency. |
| `layers/background-light.png`, `layers/background-dark.png` | The paper gradients, exactly as the icon draws them. |
| `flattened/AppIcon-light.png`, `-dark.png`, `-tinted.png` | Flat references for the default, dark and tinted appearances. The build does not use them. |
| `AppIcon-AppStore-1024.png` | Opaque square 1024 × 1024 PNG without alpha or rounded corners, for places that need a flat file. App Store Connect takes the icon from the build. |
| `make_icon.py` | Rebuilds all of the above and the Icon Composer bundle. |
| `../../apps/apple/JournalApp/Resources/AppIcon.icon` | The Icon Composer bundle that the iOS and Mac targets compile. |

## How the layers were made

`python3 design/icon/make_icon.py` (needs Pillow and NumPy) does the following:

1. Fits a smooth quadratic surface to the paper around the strokes, then derives each pixel's ink coverage from where it lies between that paper colour and the ink colour. Coverage below 4% or above 95% is snapped to transparent or opaque, which removes the paper grain but keeps the one-to-two-pixel anti-aliased edges; pixels more than 4 px from a stroke are always transparent.
2. Replaces the paper with the two-colour top-to-bottom gradient that best matches the original (sRGB 254, 253, 249 to 253, 243, 233). The recomposed icon differs from the source by 1.8 levels on average.
3. Writes the dark appearance as the same composition on deep navy (31, 51, 95 to 13, 24, 52) with paper-white lettering (246, 240, 229), and the tinted reference as white lettering on black.

Icon Composer in Xcode 26.6 draws the background gradient from 10% to 90% of the height and ignores a gradient orientation on the background, so the script fits and renders only that shape.

## How the icon is built

`AppIcon.icon` has the gradient as its background fill and one layer group with the lettering. Its settings:

- Dark: navy background fill and a paper-white fill for the lettering.
- Tinted (used for the clear and tinted appearances): a white fill for the lettering. Without it, the navy ink almost disappears, because those appearances use the layer's lightness.
- Liquid Glass, specular highlights, shadow and translucency are off for the lettering to keep the flat ink-on-paper look. The system still adds its edge highlight.

`project.yml` sets `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` for both apps. XcodeGen adds the bundle as a single resource, and Xcode compiles the layered icon for iOS 26 and macOS 26, plus flattened images for older systems: default, dark and tinted images for iOS 18, small legacy iOS icons, and the rounded-rectangle Mac icon with margins and shadow for macOS 13 to 15.

To adjust the icon, open `AppIcon.icon` in Icon Composer (Xcode > Open Developer Tool > Icon Composer). Running `make_icon.py` again replaces the bundle, so carry manual changes back into the script. To preview a rendition without building:

```sh
"$(dirname "$(xcode-select -p)")/Applications/Icon Composer.app/Contents/Executables/ictool" \
  apps/apple/JournalApp/Resources/AppIcon.icon --export-image --output-file preview.png \
  --platform iOS --rendition Dark --width 512 --height 512 --scale 2
```

Renditions: `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`; platforms `iOS` and `macOS`.

## References

- [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) (Human Interface Guidelines)
- [Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
- [Configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon)
