# YOnC SDK — Flutter sample

A small Flutter app that integrates the YOnC SDK through the `yonc_flutter` plugin the way a
partner app does: download the model the network assigns to the phone, then switch on **Turbo
Mode** — the phone contributes its idle compute to the YOnC network while it charges, and the
network reports what each of your users earned. Android and iOS from one Dart file.

The app takes the plugin from the YOnC Pub repository, and the plugin resolves the native SDKs
(an Android library and an iOS Swift package) from the YOnC artifact server when the app builds.
This sample is on plugin 0.5.0, which embeds SDK 0.5.0.

One screen, `lib/main.dart`:

- **Model**: the model the network assigns to this phone (`Models.defaultModelId`), its size, the
  download with progress in bytes, cancel and delete.
- **Turbo Mode**: the switch, what Turbo is doing, the conditions it waits for
  (`SafeState.unmet`), task and token counters, a retry after an attestation refusal.
- **Android prompts**: allow background running and notifications when the SDK reports they are
  needed.
- **Account** (with attestation only): switch the account the network credits
  (`Turbo.setReportingLabel`).

The plugin's own README documents the whole Dart API; it ships inside the package, under
`.pub-cache/hosted/ymm.jfrog.io%47artifactory%47api%47pub%47flutter-yonc-pub/yonc_flutter-<version>/`
after the first `flutter pub get`.

## Requirements

- Flutter 3.44 or newer (this sample was built with 3.47.2).
- Read-only credentials issued by YOnC: one user and token for the Pub repository, the Android
  Maven repository and the iOS Swift package registry.
- **Android:** an arm64 phone on Android 8.0 or newer. The on-device inference runtime ships no
  other ABI and does not run on the standard emulator.
- **iOS:** the SDK runs on iOS 26 or newer. A phone, or an Apple-silicon Mac with Xcode 26 for the
  simulator. Below iOS 26 the app shows a notice instead of the screen.

## 1. Credentials, once per machine

**Pub repository** (the plugin itself):

```sh
dart pub token add https://ymm.jfrog.io/artifactory/api/pub/flutter-yonc-pub
```

**Android Maven repository** (the Android SDK), in `~/.gradle/gradle.properties`:

```properties
yoncRepoUser=<user>
yoncRepoToken=<token>
```

or in the environment as `YONC_REPO_USER` and `YONC_REPO_TOKEN`. The plugin adds the YOnC Maven
repository to the build itself.

**Swift package registry** (the iOS SDK), on the Mac:

```sh
swift package-registry set --global --scope yonc https://ymm.jfrog.io/artifactory/api/swift/ios-yonc-swift
swift package-registry login https://ymm.jfrog.io/artifactory/api/swift/ios-yonc-swift --username <user> --password <token>
```

`flutter build ios` runs `xcodebuild`, which reads that credential from the login keychain. On the
first build macOS asks whether it may: choose *Always Allow*.

## 2. Run it

```sh
flutter pub get

# Android, an arm64 phone
flutter run

# iOS: a phone, or an Apple-silicon simulator on iOS 26 or later
FLUTTER_XCODE_ARCHS=arm64 flutter run
```

Device attestation is off unless you pass the two values YOnC issued for this app:

```sh
flutter run --dart-define=YONC_APPLICATION_ID=<application id> --dart-define=YONC_REPORTING_ID=<label>
```

Without them Turbo connects unattested, which the network admits only while attestation is not
enforced. Attestation needs a physical device: simulators report it unavailable. On an iPhone the
Runner needs your own signing team with the App Attest capability.

## 3. What this app sets up that yours needs too

**Android** (`android/`)

- `minSdk = 26` and `ndk { abiFilters += "arm64-v8a" }` in `app/build.gradle.kts`, with
  `disable-abi-filtering=true` in `gradle.properties`: Flutter's Gradle plugin otherwise replaces
  the app's filters with its own three-ABI list.
- The notification icon `res/drawable/ic_stat_example.xml`, named from Dart, and
  `res/raw/keep.xml` so the release build's resource shrinker keeps it.
- No shrinker rules: the SDK ships its own.

**iOS** (`ios/Runner/`)

- `BGTaskSchedulerPermittedIdentifiers` with `$(PRODUCT_BUNDLE_IDENTIFIER).yonc.turbo.*` in
  `Info.plist`, for Turbo under a locked screen.
- `Runner.entitlements` with the App Attest environment, for device attestation.
- The Runner's minimum is iOS 15.0, so the app installs on older systems and shows the notice there.

## 4. Building against a plugin checkout

To build this app against a local copy of the plugin instead of the Pub repository, add a
`pubspec_overrides.yaml` next to `pubspec.yaml` (it is git-ignored):

```yaml
dependency_overrides:
  yonc_flutter:
    path: ../path/to/yonc_flutter
```
