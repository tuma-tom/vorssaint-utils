# Personal legacy Intel build

Goal: a signed, transferable x86_64 app for a 2018 MacBook Pro running macOS Sequoia 15.8.1.

Constraints: use feature/legacy-intel-support only; no upstream push, PR, or official release. Preserve the existing checkout and running Audio Fork app. Keep macOS 14 deployment support and use the existing private developer app identity, which disables official self-updates. Use the existing stable local signing certificate; Apple notarization is unavailable without Developer ID credentials.

- [x] Allow arm64 (default) or x86_64 throughout the app, helper, adapter, GIF codec, and optional audio driver; keep compiler objects separated by architecture.
- [x] Add a reproducible private Intel entry point and document transfer and first launch.
- [x] Compile the optimized Intel app, run available native tests, verify architectures, deployment versions, nested signatures, and packaged driver. Cross-target execution requires Rosetta and must be reported if unavailable.
- [ ] Commit only scoped changes locally; deliver a ZIP and installation instructions with checksums. Remove this task's reproducible intermediate build outputs after packaging and verification, retaining final artifacts and source.

Intel CPU/GPU sensor discovery was added for display only. The focused sensor regression test failed before implementation and now passes; no verified Intel CPU fan mapping is enabled. Independent review found no actionable issues. Intel SDK smoke compilation passes; destination runtime remains unverified because Rosetta is unavailable here.

Final clean Intel build passed. Four native binaries and all signatures verified; packaged driver targets Intel with macOS 14.4. Metrics/updates/repository: 2,114 passing checks. Full suite: 2 of 123,117 assertions failed in unrelated QuitAppsRuntimeTests; isolated utilities rerun: 553 checks passed. These limits are recorded in LEGACY-INTEL.md.
