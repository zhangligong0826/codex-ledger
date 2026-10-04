# Native app icon

The original ice-blue bars and silver plate are authored as an editable Apple Icon Composer document: [`Assets/AppIcon.icon`](Assets/AppIcon.icon). All artwork is original and covered by this repository's MIT license.

Three plain SVG layers form the ascending bars. They contain no baked lighting, shadows, blur, enclosure or bevels. The document supplies the background gradient, glass material, translucency, individual lighting, specular highlights and shadows. A separate dark appearance uses a slate plate and brighter ice-blue bars. Clear and tinted appearances are produced by Apple's renderer. The monochrome menu bar silhouette remains readable at 18 points.

## Edit and render

Install [Apple Icon Composer](https://developer.apple.com/icon-composer/) and open `Assets/AppIcon.icon`, or edit the SVG layers and material settings in that document. Run:

```sh
zsh make-native-icon.sh
```

This uses Icon Composer's `ictool` to regenerate four 1024-pixel previews and the compatible, checked-in `AppIcon.icns`. `make-icon.sh` is an alias. Set `CODEX_LEDGER_ICTOOL` when the tool is installed elsewhere. Icon Composer is needed only when changing artwork, not when installing or building the app.

| Preview | File |
| --- | --- |
| Silver / ice blue | `Assets/AppIcon-1024.png` |
| Dark | `Assets/AppIcon-Native-Dark.png` |
| Clear light | `Assets/AppIcon-Native-ClearLight.png` |
| Example tint | `Assets/AppIcon-Native-TintedDark.png` |

## Compile and verify

Select an initialized Xcode 26 or later without changing the global toolchain:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer CODEX_LEDGER_NATIVE_ICON=required zsh build.sh
zsh verify-native-icon.sh "dist/Codex Ledger.app"
```

`actool` compiles the `.icon` into `Assets.car`, emits the compatible ICNS and supplies `CFBundleIconName` through its partial Info.plist. The catalog retains vector layers, glass lighting and light/dark/tintable icon stacks. The verification script checks structural integrity, layered icon resources and bundle metadata. This is distinct from exporting a flat PNG.

`CODEX_LEDGER_NATIVE_ICON` accepts `auto` (default), `required` and `off`. `auto` compiles a native icon when selected Xcode is new enough; Command Line Tools and older Xcode builds use the checked-in ICNS. A failure in an available native compiler is reported rather than silently falling back. Release packaging requires the native build. Full Xcode and Icon Composer are not required on users' Macs.

Supported macOS versions choose their own icon rendering; older systems use the compatible flattened representation. App window appearance settings do not override the system's app icon appearance. Preview images are static exports; they do not demonstrate a Finder or Dock interaction. See [Apple's integration guidance](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer).
