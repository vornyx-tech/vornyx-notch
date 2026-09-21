<h1 align="center">Vornyx Notch</h1>

<p align="center">A macOS notch companion — media controls, a file shelf, calendar and HUD replacement, in the space around your MacBook's notch.</p>

---

## Build

Requires Xcode 16+ and macOS 14+.

```sh
open VornyxNotch.xcodeproj
```

Then build and run the **VornyxNotch** scheme. Swift Package dependencies resolve automatically on first open.

From the command line:

```sh
xcodebuild -project VornyxNotch.xcodeproj -scheme VornyxNotch -configuration Debug build
```

The built app is `VornyxNotch.app`; it shows up as **Vornyx Notch** in Finder, Spotlight and the menu bar.

## DMG installer

```sh
./Configuration/dmg/build_local_dmg.sh          # version from the project
./Configuration/dmg/build_local_dmg.sh 2.8.0    # or name one
```

This archives a universal Release build and packs it into `build/VornyxNotch-<version>.dmg`. No Apple developer account is needed: the app is signed ad-hoc. Open the DMG and drag **VornyxNotch** into **Applications**.

Because the app is not notarized, macOS blocks the first launch of a copy downloaded from elsewhere. Allow it under **System Settings → Privacy & Security → Open Anyway**, or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/VornyxNotch.app
```

Accessibility and other permissions are tied to the app's signature, and an ad-hoc signature changes with every build: after installing a new build, turn Vornyx Notch off and on again under **Privacy & Security → Accessibility**.

## Layout

| Path | What's in it |
| --- | --- |
| `VornyxNotch/` | The app: views, managers, media controllers, settings |
| `VornyxNotch/components/` | Notch UI — shelf, calendar, music, webcam, HUD, onboarding |
| `VornyxNotch/sizing/` | Notch geometry, including the configurable corner radii |
| `VornyxNotchXPCHelper/` | Privileged helper (XPC service) |
| `mediaremote-adapter/` | Now Playing bridge |

## Settings

Notch shape is configurable under **Settings → Appearance → Notch corner radius**: separate top and bottom radii for the open and closed states, with a live preview. Values larger than the notch can hold are capped automatically when drawing.

## Credits & license

Vornyx Notch began as a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch) by TheBoredTeam, and a large part of this app is still their work. Thanks to Harsh Vardhan Goswami, Alexander Greco, Richard Kunkli and everyone else who built it — the media player, the shelf, the HUDs and the whole idea of living in the notch came from there.

The notch shape traces back to [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) by Kai Azim.

Licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE). Third-party dependency licenses are listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES). Per-file copyright notices name the original authors and are retained.
