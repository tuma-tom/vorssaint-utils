# Vorssaint Audio

Local build of main plus PR #3136, extended with an optional virtual output for native macOS volume UI and concurrent per-app controls.

## Use

Build/install the separate development app with `./build.sh --dev --install`. The normal mixer needs no driver. Enabling **Software volume fallback** in Mixer > Options offers the optional Vorssaint Audio driver installer only when it is missing. Cancel leaves the option off; successful installation enables it. The administrator installer adds only `/Library/Audio/Plug-Ins/HAL/VorssaintAudio.driver` and restarts Core Audio, briefly interrupting audio.

With **Software volume fallback** enabled, the app uses writable native device volume first: AirPods and built-in speakers remain native. For a fixed-volume physical device such as a Samsung DisplayPort monitor, it selects **Vorssaint Audio** as the system output and forwards the final mixed stream to the selected physical device. Volume and mute remain normal macOS controls. Per-app sliders remain available. Per-app routes explicitly sent to a different physical device follow native semantics: default-output master volume does not control another device.

Select outputs in the mixer or macOS. Returning to a native-volume output removes the virtual path; returning to a fixed-volume output recreates it. If a connection, format, rendering or owner heartbeat fails, the app/driver gives control back to available physical output. Quitting or disabling normally restores the previous output and alert-sound route. A fixed-volume physical output regains its unattenuated path when software processing stops.

The Sound output switcher package and audio output priority use the underlying physical destination while fallback is active. Vorssaint's internal driver and loopback devices are excluded from their choices; other vendors' virtual outputs remain selectable. Existing switcher selections containing Vorssaint Audio migrate to its remembered physical output. Repeated shortcut presses track the latest requested destination and discard superseded queued changes.

The public device is output-only. A separate hidden virtual loopback input feeds the bridge and is not offered in Vorssaint’s microphone selector. It remains an audio input visible to other suitably authorized Core Audio clients. macOS may request audio-input permission for opening that virtual input and System Audio Recording permission for per-app taps. Before playback starts, physical input streams are disabled with a verified HAL mask. The new local bridge/component does not save or upload audio; the existing recorder and explicitly selected AirPlay routes retain separate behavior. See [microphone boundaries and verification](SOFTWARE-VOLUME-PRIVACY.md).

The app has separate preferences/permissions under `com.vorssaint.utils.dev`; it does not replace the official app and does not auto-update from official releases.

## Remove component

Open Settings > Volume mixer > Options and choose **Remove audio driver**. **Audio privacy** is available in the same settings section. These management actions do not appear in the menu-bar or notch quick controls. The app turns fallback off, restores physical playback, requests administrator approval, removes the dedicated HAL bundle and package receipt, and clears its saved fallback device/levels. Cancelling authorization leaves the component installed and fallback off. **Uninstall Vorssaint completely** also removes the component before deleting the app.

For removal without launching the app, quit Vorssaint and run `./Tools/uninstall-software-volume-driver.sh` in Terminal. A copy is also bundled at `Vorssaint.app/Contents/Resources/uninstall-software-volume-driver.sh`. It requests administrator authorization, verifies the exact bundle identity, removes only the dedicated driver and restarts Core Audio. The official application is untouched.

## Verify

- `./Tools/test-software-volume.sh`: driver, bridge/policy and isolated uninstaller filesystem checks.
- `./Tools/build-software-volume-driver.sh`: driver-interface, ownership, native control and actual loopback DSP checks.
- `swiftc Sources/Vorssaint/Services/QuickTools/MicMuteSupport.swift Sources/Vorssaint/Services/Audio/VirtualOutputSupport.swift Tests/SoftwareVolume/BridgeTests.swift -o build/software-volume-bridge-tests && build/software-volume-bridge-tests`: hardware-first policy, restore policy, microphone/channel isolation and progress checks.
- `./build.sh --test`, built app `--selftest`, and `codesign --verify --deep --strict` on app/driver.

Third-party source, pin and modifications are recorded in `ThirdParty/BlackHole/UPSTREAM.md` with its GPL license. This is a local build, not an official release.

## License and release packaging

BlackHole source at the recorded pin is GPLv3; Vorssaint is GPL-3.0-or-later, so this distribution uses the compatible GPLv3 terms. The package contains our own build of the source, uses Vorssaint Audio branding, preserves upstream notices and includes the exact driver Corresponding Source and build script inside the driver bundle. It does not include upstream's proprietary official installer/binaries or artwork. See `ThirdParty/BlackHole/UPSTREAM.md` and `LICENSE` for the applicable notices and redistribution requirements.

Local signatures are not Developer ID distribution signatures. Official packaging must configure `VORSSAINT_DRIVER_SIGN_IDENTITY` and `VORSSAINT_INSTALLER_SIGN_IDENTITY`, complete its notarization/release review, and retain matching source access.
