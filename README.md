# YOnC SDK — Flutter sample

A small Flutter app that integrates the YOnC SDK through the `yonc_flutter` plugin the way a
partner app does: download the model the network assigns to the phone, chat with it **on the
device**, and switch on **Turbo Mode** — the phone contributes its idle compute to the YOnC
network while it charges, and the network reports what each of your users earned. Android and iOS
from one Dart file.

The app takes the plugin from the YOnC Pub repository, and the plugin resolves the native SDKs
(an Android library and an iOS Swift package) from the YOnC artifact server when the app builds.
This sample is on plugin 0.6.1, which embeds SDK 0.6.1.

One screen, `lib/main.dart`:

- **Model**: the model the network assigns to this phone (`Models.defaultModelId`), its size, the
  download with progress in bytes, cancel and delete.
- **On-device chat**: a conversation with the downloaded model (`Yonc.localChat`): availability,
  the streamed reply, stop, and the close that unloads the model. Chat runs only while Turbo is
  off, and a chat turn sends nothing to the network.
- **Turbo Mode**: the switch, what Turbo is doing, the conditions it waits for
  (`SafeState.unmet`), task and token counters, a retry after an attestation refusal.
- **Android prompts**: allow background running and notifications when the SDK reports they are
  needed.
- **Account** (with attestation only): switch the account the network credits
  (`Turbo.setReportingLabel`).

The plugin's own README documents the whole Dart API; it ships inside the package, under
`.pub-cache/hosted/ymm.jfrog.io%47artifactory%47api%47pub%47flutter-yonc-pub/yonc_flutter-<version>/`
after the first `flutter pub get`.

## What's new in 0.6.0

- On-device chat: `yonc.localChat` (section 4), with the names the Kotlin and Swift SDK use:
  `session(model)`, `LocalChatSession`, `TokenEvent` with its `GenerationMetrics`,
  `GenerationTokenCounts`.
- `ModelInfo.licenseUrl` links each model's licence terms.
- `BackgroundWork.vendorManagerPackage`, as in the Android SDK.
- `Models.models` is the model list's name on every platform; `Models.entries`, the 0.5.0 name,
  still works and is deprecated.
- **Breaking:** `BackgroundWork.requestNotifications()` no longer opens the app's notification
  settings unless you pass `fallbackToSettings: true` (the Android SDK's default). `YoncErrorCode`
  gains `chatUnavailable`, so an exhaustive `switch` over it without a default needs one more case.

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

## 4. On-device chat

`yonc.localChat` runs conversations on the phone's own engine with a model already on the device.
Nothing the user types and nothing the model answers leaves the phone: a chat turn sends nothing to
the network. This app's *On-device chat* card is a complete example.

```dart
yonc.localChat.availability                 // Stream<ChatAvailability>: ready, noModel, turboOn; the current value first

final local = yonc.models.current!.whereType<ModelLocal>().first;
final session = await yonc.localChat.session(local);   // a new, empty conversation
await for (final event in session.send('Salom!')) {    // Stream<TokenEvent>, cold: listening runs the turn
  if (!event.thinking) answer.write(event.text);        // reasoning (models that think) is flagged, the answer is plain text
}
session.model                               // the ModelLocal it runs on
await session.history();                    // List<ChatMessage>: the committed exchanges, answer text only
await session.lastTokenCounts();            // GenerationTokenCounts?: engine-counted tokens of the last completed turn
await session.reset();                      // start over in place
await session.close();                      // end the conversation: history discarded, model unloaded
```

- **Availability.** `ready`, `noModel` (nothing downloaded yet) or `turboOn`. Read it before
  showing the chat entry. Chat does not gate on battery, charging or temperature, needs no
  attestation and no YOnC consent — only a downloaded model.
- **Chat and Turbo share the device's one engine, so chat runs only while Turbo is off.** A message
  sent while Turbo is on fails with a `YoncException` whose `code` is `chatUnavailable` and whose
  `chatUnavailable` is `turboOn`, before it reaches the engine; switching Turbo on stops a turn in
  flight the same way. After Turbo is switched off, chat is available again within seconds. Chat
  never interrupts a network task, so it does not touch earnings, Turbo statistics or attestation.
- **One conversation at a time.** `session(model)` starts a new, empty conversation. It keeps its
  own history and builds every prompt from it; you pass only the next message. The engine holds one
  conversation: switching between two sessions rebuilds the other's context on its next message.
- **`send` is cold.** Listening starts the turn; cancelling the subscription stops the generation,
  and the cancel completes once the partial answer is in the history, so the next message can
  follow at once. The first message loads the model, which takes seconds on a large model. One turn
  at a time per session. Every `TokenEvent` carries the engine's running metrics
  (`metrics.ttftMs`, `metrics.decodeTokenCount`, `metrics.decodeTokS`). A stopped or failed turn
  keeps its partial answer in the history, and the next message continues.
- **Errors** end the stream as a `YoncException`: `chatUnavailable` (Turbo on, also mid-turn; or a
  model no longer on the device when the session starts, reason `noModel`) or `sdkFailure` (the
  model could not be loaded or is damaged — delete and download it again —, the engine stopped, or a
  turn was already streaming in this session). The next message retries. Any call on a closed
  session throws a `StateError`.
- **Lifecycle.** While a chat is in use, the engine keeps the model loaded (on Android in its own
  process, with the engine notification showing). `close()` ends the conversation for good: a turn
  in flight stops, the history is discarded and the model is unloaded, unless Turbo is on or
  another session's turn is streaming. The next conversation is a new `session(model)`, whose first
  message loads the model again. Call it when your chat screen closes. Sessions also close when
  their Flutter engine goes, and after a hot restart. Chat adds no permission and no
  foreground-service type to what the SDK declares for Turbo.
- **Limits.** The context window and what happens when a conversation outgrows it are not
  specified in this release: keep conversations short and start over with `reset()` or a new
  session.
- **Models and languages.** Any downloaded catalogue model can open a conversation. Gemma 3 1B, the
  model the network assigns by default, is the one chat is checked with; the others are possible
  but not the default. Gemma 3 1B is a small general model: it has not been measured in Uzbek or
  Russian, and a model of this size is not expected to hold a conversation in Uzbek well.
- **Generation options.** None in this release: a model's catalogue temperature sets its sampling,
  and every chat reply runs under a repetition penalty (1.1 over the last 64 tokens, the same on
  Android and iOS) so a small model escapes verbatim loops. A system prompt, temperature and output
  length per conversation are planned; tell YOnC which you need and in which chat scenarios.
- **Privacy.** The user's messages and the model's replies stay on the phone. The SDK uses the
  network for the model catalogue, model downloads, Turbo, and on Android a report when the engine
  fails to load a model (the model, accelerator, reason and memory; never text). The SDK applies no
  content filtering of its own; any filtering your app needs is on your side.
- **Testing the states.** Delete the downloaded model and availability is `noModel`; switch Turbo
  on and it is `turboOn`; with a model on the phone and Turbo off it is `ready`. Engine failures and
  thermal limits cannot be forced from the app. The smallest model in the catalogue is Gemma 3 1B;
  there is no smaller test model. To test against the YOnC test or UAT Router, pass its address as
  `environment` to `Yonc.create` with the application id issued for it.

## 5. Reporting a problem

The SDK has no debug flag. With a bug report send YOnC:

- the steps to reproduce;
- the plugin version and `yonc.sdkVersion`;
- the device model and OS version;
- the log around the failure. Android: a logcat capture (`adb logcat -d > logcat.txt` right after
  it happens). iOS: the Xcode console of a run from Xcode, or a Console.app capture with the phone
  selected.

## 6. Building against a plugin checkout

To build this app against a local copy of the plugin instead of the Pub repository, add a
`pubspec_overrides.yaml` next to `pubspec.yaml` (it is git-ignored):

```yaml
dependency_overrides:
  yonc_flutter:
    path: ../path/to/yonc_flutter
```
