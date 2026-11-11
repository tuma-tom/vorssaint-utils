# Personal Legacy Intel build

This branch is for a personal 2018 MacBook Pro running macOS Sequoia 15.8.1. It is not an official Vorssaint release. No upstream PR or release is part of this work.

## Ownership and maintenance

- Maintain this variant in [tuma-tom/vorssaint-utils](https://github.com/tuma-tom/vorssaint-utils/tree/feature/legacy-intel-support), on `feature/legacy-intel-support`.
- Push this branch only to the `fork` remote. Do not open a PR, push changes to the official repository, or publish an official release for this work.
- Bring upstream fixes into this branch as needed, preserve the Intel build entry point and developer identity, then rebuild and test on the 2018 MacBook before updating the personal build.
- Keep signing keys and credentials local. Build outputs remain outside Git; retain the final signed transfer package.

The local branch tracks `fork/feature/legacy-intel-support`, and its push destination is explicitly set to `fork`.

## Rebuild

With Xcode or the Command Line Tools installed:

```sh
./Tools/build-legacy-intel.sh
```

The optimized app is written to `build/stage.noindex/Vorssaint (Legacy Intel).app`. The app, fan helper, Now Playing adapter, GIF codec, and bundled optional software-volume driver target x86_64. The app requires macOS 14.0 or newer; the optional audio driver requires 14.4 or newer. The arm64 build remains the default for `./build.sh`.

This uses the existing developer identity (`com.vorssaint.utils.dev`), including its separate permissions and preferences. It does not install updates from official GitHub releases. It shares preferences with any other developer build on the destination Mac, so use only one such build at a time.

The build prefers Developer ID when available and otherwise uses the existing stable local signing identity. The delivered personal build uses `Vorssaint Utils Signing`. A local signature protects integrity but is not Apple notarization. No private key or signing credentials are included.

## Transfer and launch

1. Copy the ZIP to the Intel Mac and extract it there.
2. Move `Vorssaint (Legacy Intel).app` to Applications.
3. Open it. If macOS blocks it because the developer is unverified, use System Settings → Privacy & Security → Open Anyway, then confirm the app's name. [Apple's instructions](https://support.apple.com/en-gb/102445).
4. Grant Accessibility, Screen Recording, and other permissions only as the features you use request them.

The optional audio driver is included as an installer, not installed automatically. There is no need to install or trust a root certificate, disable Gatekeeper, or disable SIP.

## Verification

```sh
./build.sh --test
VORSSAINT_ARCH=x86_64 ./Tests/SDKBuildTests.sh
codesign --verify --deep --strict 'build/stage.noindex/Vorssaint (Legacy Intel).app'
lipo -archs 'build/stage.noindex/Vorssaint (Legacy Intel).app/Contents/MacOS/VorssaintDeveloper'
```

If the build host cannot execute x86_64 programs, the fan helper's execution test is explicitly skipped. The Intel helper can be checked on the destination without starting the app or controlling fans:

```sh
'/Applications/Vorssaint (Legacy Intel).app/Contents/Library/LaunchServices/com.vorssaint.utils.dev.fan-control' --selftest
```

Compilation and signature checks do not validate the destination's T2/SMC sensors, graphics, audio routing, or permissions. Those need a test on the actual MacBook. Features depending on unavailable hardware readings may remain unavailable.

Intel temperature discovery includes CPU core/package/proximity sensors and Intel/AMD GPU sensors, based on the sensor names documented in [Stats](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift). These readings are for display. Intel does not opt into verified CPU core mappings for automatic fan curves; unsupported fan control continues to fail closed.

## Verification results (2026-11-11)

- Clean optimized x86_64 compilation completed. App, fan helper, Now Playing dylib, and the driver extracted from the bundled installer are x86_64.
- App/helper/adapter deployment targets are macOS 14.0; the driver's Mach-O deployment target is 14.4.
- All four signatures passed strict verification and share the stable local certificate (SHA-256 `b8b375be5e336a3dc76db63f3efc480cc6b7f428d7b4e1ca85e9be118ff3d5a6`).
- Native metrics/update/repository suites: 2,114 checks passed. Intel sensor regression, Intel SDK smoke compilation, and developer install isolation passed.
- Full native suite: 123,117 checks, two failures in `QuitAppsRuntimeTests.swift` (lines 182 and 197: all-apps exception preservation and disabled-feature batch behavior). Its `utilities` suite passed all 553 checks when repeated alone. This is a limitation of the full verification run; no unrelated Quit Apps code was changed.
- Software audio driver/bridge/uninstall/PCM/playback tests passed. Intel helper execution and actual destination hardware remain unverified because the build host cannot execute x86_64 programs.
- After transferring the build, the owner reported on 2026-11-11 that the expected features appear to work on the destination MacBook Pro 2018 with macOS Sequoia 15.8.1. This is a successful personal smoke test, rather than an exhaustive hardware compatibility test.
