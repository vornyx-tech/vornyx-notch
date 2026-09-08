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

Vornyx Notch is a fork of [boring.notch](https://github.com/TheBoredTeam/boring.notch) by The Bored Team and its contributors, and would not exist without their work.

Licensed under the **GNU General Public License v3.0** — see [LICENSE](LICENSE). Third-party dependency licenses are listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES). Per-file copyright notices name the original authors and are retained.
