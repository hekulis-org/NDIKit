# Developing with Simulators

`NDIKit` cannot be used in iOS Simulator builds because the upstream NDI iOS SDK binary does not include simulator slices.  
`NDIKit` depends on `NDIKitC` (a binary XCFramework), so any target that links `NDIKit` must build for real iOS devices, not the simulator.

This guide shows the recommended downstream app setup: keep one device target that links `NDIKit`, and one simulator target that does not.

## Recommended Setup

Use two app targets and two schemes:

- `MyApp` (device target): links `NDIKit`
- `MyApp-Sim` (simulator target): does not link `NDIKit`
- `MyApp-Device` scheme: uses `MyApp`
- `MyApp-Simulator` scheme: uses `MyApp-Sim`

## 1. Duplicate Your App Target

1. In Xcode, right-click your app target and choose `Duplicate`.
2. Rename it to something like `MyApp-Sim`.
3. In `Build Settings`, verify:
- `PRODUCT_NAME`
- `PRODUCT_BUNDLE_IDENTIFIER` (suffix like `.sim` is recommended)
- deployment target and signing settings are correct for local simulator use.

## 2. Remove NDIKit from the Simulator Target

For `MyApp-Sim`:

1. Open `General` > `Frameworks, Libraries, and Embedded Content`.
2. Remove `NDIKit` and `NDIKitMetal` (if present).
3. Open `Build Phases` > `Link Binary With Libraries`.
4. Remove `NDIKit`/`NDIKitMetal` there as well.

Note: keep the package dependency at the project/workspace level. Only unlink it from the simulator app target.

## 3. Duplicate and Configure Schemes

1. Open `Product` > `Scheme` > `Manage Schemes`.
2. Duplicate your existing scheme twice (or duplicate once and rename both):
- `MyApp-Device`
- `MyApp-Simulator`
3. Edit `MyApp-Device`:
- Run/Build/Test actions use `MyApp`
- Archive uses `MyApp`
4. Edit `MyApp-Simulator`:
- Run/Build/Test actions use `MyApp-Sim`
- Archive action can be disabled or left unused.

## 4. Guard NDI Imports and Usage in Code

Wrap NDI imports so simulator compiles without the package:

```swift
#if canImport(NDIKit) && !targetEnvironment(simulator)
import NDIKit
#endif
```

Wrap call sites similarly:

```swift
#if canImport(NDIKit) && !targetEnvironment(simulator)
// NDI-enabled path
#else
// Simulator fallback/no-op path
#endif
```

## 5. Optional: Duplicate and Configure Test Targets / Test Plans

Do this only if your tests are tied to the app target or use UI tests.

### Duplicate test targets when needed

1. Duplicate app-hosted unit test targets and/or UI test targets:
- `MyAppTests` -> `MyAppTests-Sim`
- `MyAppUITests` -> `MyAppUITests-Sim`
2. Repoint the duplicated test targets to `MyApp-Sim` as host/tested app.
3. Ensure their bundle identifiers are unique.

### If you use `.xctestplan` files

1. Duplicate your existing test plan (for example `AppTests.xctestplan` -> `AppTests-Sim.xctestplan`).
2. In the simulator plan, include only simulator-valid test targets.
3. In `MyApp-Simulator` scheme, set the Test action to use `AppTests-Sim.xctestplan`.

## 6. If Source File Membership Gets Out of Sync

If duplication or refactoring causes missing files, fix target membership explicitly:

1. Select a source file in Xcode.
2. Open File Inspector.
3. Under `Target Membership`, check the correct target(s):
- shared files: both `MyApp` and `MyApp-Sim`
- NDI-only files: device target only
- simulator stubs: simulator target only
4. Also verify `Build Phases`:
- `Compile Sources`
- `Copy Bundle Resources`

## 7. Daily Workflow

- Use `MyApp-Simulator` for simulator development and fast iteration.
- Use `MyApp-Device` for NDI feature work, device testing, and archive/distribution.
- Keep simulator behavior explicit in UI (for example, show NDI features as unavailable).
