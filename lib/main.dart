import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yonc_flutter/yonc_flutter.dart';

// Device attestation for this example, from the command line:
//   flutter run --dart-define=YONC_APPLICATION_ID=<issued by YOnC> --dart-define=YONC_REPORTING_ID=<label>
// Both empty: Turbo connects without attestation, which the network admits only while attestation
// is not enforced. A real app passes its signed-in user's opaque label.
const String applicationId = String.fromEnvironment('YONC_APPLICATION_ID');
const String reportingId = String.fromEnvironment('YONC_REPORTING_ID');

bool get attested => applicationId.isNotEmpty && reportingId.isNotEmpty;

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'YOnC example',
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Yonc? _yonc;

  /// Why the SDK is not available: iOS below 26, or a configuration the SDK rejected.
  String? _unavailable;

  StreamSubscription<void>? _showTurbo;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _showTurbo?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    try {
      // Once per process; every later call with the same arguments returns the same handle.
      final Yonc yonc = await Yonc.create(
        name: 'yonc-flutter-example',
        version: '0.5.0',
        attestation: attested
            ? const AttestationConfig(
                applicationId: applicationId,
                externalReportingId: reportingId,
              )
            : null,
        androidNotification: const EngineNotification(
          title: 'YOnC example',
          icon: 'ic_stat_example',
        ),
      );
      // The user tapped Turbo's notification: this screen already shows Turbo.
      _showTurbo = yonc.turbo.showRequested.listen(
        (_) => _say('Opened from the Turbo notification'),
      );
      setState(() => _yonc = yonc);
      // Local files + the catalogue the network offers this device.
      await yonc.models.initialize();
    } on YoncException catch (e) {
      setState(
        () => _unavailable = e.code == YoncErrorCode.unsupportedPlatform
            ? 'YOnC needs iOS 26 or later.'
            : '${e.code.name}: ${e.message}',
      );
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final Yonc? yonc = _yonc;
    return Scaffold(
      appBar: AppBar(title: const Text('YOnC example')),
      body: yonc == null
          ? Center(
              child: _unavailable == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_unavailable!, textAlign: TextAlign.center),
                    ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                ModelCard(models: yonc.models, onError: _say),
                TurboCard(turbo: yonc.turbo, onError: _say),
                if (yonc.backgroundWork case final BackgroundWork work)
                  PromptsCard(work: work, onError: _say),
                if (attested) AccountCard(turbo: yonc.turbo),
              ],
            ),
    );
  }
}

/// The model the network assigns to this phone: download, progress in bytes, delete.
class ModelCard extends StatelessWidget {
  const ModelCard({super.key, required this.models, required this.onError});

  final Models models;
  final void Function(String) onError;

  Future<void> _run(Future<void> Function() call) async {
    try {
      await call();
    } on YoncException catch (e) {
      onError('${e.code.name}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<String?>(
        stream: models.defaultModelId,
        builder: (context, defaultId) => StreamBuilder<List<ModelEntry>>(
          stream: models.entries,
          builder: (context, entries) {
            final List<ModelEntry> all = entries.data ?? <ModelEntry>[];
            final ModelEntry? entry = all
                .where((e) => e.info.id == defaultId.data)
                .firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Model', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (entry == null)
                  const Text('Waiting for the catalogue…')
                else ...<Widget>[
                  Text(entry.info.name),
                  Text(
                    describe(entry.info),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  switch (entry) {
                    ModelNotDownloaded() => FilledButton(
                      // No id: the model the network designates for this device.
                      onPressed: () => _run(models.download),
                      child: const Text('Download'),
                    ),
                    ModelDownloading(
                      :final receivedBytes,
                      :final totalBytes,
                      :final progress,
                    ) =>
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          LinearProgressIndicator(
                            value: totalBytes > 0 ? progress : null,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            totalBytes > 0
                                ? '${formatBytes(receivedBytes)} / ${formatBytes(totalBytes)}'
                                : formatBytes(receivedBytes),
                          ),
                          TextButton(
                            onPressed: () => _run(
                              () => models.cancelDownload(entry.info.id),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ModelLocal() => Row(
                      children: <Widget>[
                        const Expanded(child: Text('On this phone')),
                        TextButton(
                          onPressed: () =>
                              _run(() => models.delete(entry.info.id)),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  },
                ],
                if (all.length > 1)
                  Text(
                    '${all.length - 1} other models in the catalogue',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Turbo Mode: the switch, what it is doing, and what it waits for.
class TurboCard extends StatelessWidget {
  const TurboCard({super.key, required this.turbo, required this.onError});

  final Turbo turbo;
  final void Function(String) onError;

  Future<void> _run(Future<void> Function() call) async {
    try {
      await call();
    } on YoncException catch (e) {
      onError('${e.code.name}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<TurboStatus>(
        stream: turbo.status,
        builder: (context, status) {
          final TurboStatus s = status.data ?? TurboStatus.off;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Turbo Mode'),
                subtitle: Text(statusLabel(s)),
                value: s != TurboStatus.off,
                // Nothing to pass: the network picks which downloaded model runs. Switched on
                // before a download finished, Turbo waits for the first model.
                onChanged: (on) => _run(on ? turbo.start : turbo.stop),
              ),
              if (s == TurboStatus.waitingForSafeState)
                StreamBuilder<SafeState>(
                  stream: turbo.safeState,
                  builder: (context, safe) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Waiting for:'),
                      for (final SafeCondition c
                          in safe.data?.unmet ?? <SafeCondition>[])
                        Text('• ${conditionLabel(c)}'),
                    ],
                  ),
                ),
              StreamBuilder<TurboStats>(
                stream: turbo.stats,
                builder: (context, stats) => Text(
                  '${stats.data?.tasksDone ?? 0} tasks · '
                  '${stats.data?.tokensGenerated ?? 0} tokens',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              StreamBuilder<AttestationState>(
                stream: turbo.attestation,
                builder: (context, attestation) => switch (attestation.data) {
                  AttestationFailed(:final failure, :final retryable) => Row(
                    children: <Widget>[
                      Expanded(child: Text('Not admitted: $failure')),
                      if (retryable)
                        TextButton(
                          onPressed: () => _run(turbo.retryAttestation),
                          child: const Text('Try again'),
                        ),
                    ],
                  ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Android only: what only the user can grant. The SDK reports it; the app asks.
class PromptsCard extends StatelessWidget {
  const PromptsCard({super.key, required this.work, required this.onError});

  final BackgroundWork work;
  final void Function(String) onError;

  Future<void> _run(Future<bool> Function() call) async {
    try {
      await call();
    } on YoncException catch (e) {
      onError('${e.code.name}: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: work.restricted,
    builder: (context, restricted) => StreamBuilder<bool>(
      stream: work.notificationsEnabled,
      builder: (context, notifications) {
        final bool askBackground = restricted.data ?? false;
        final bool askNotifications = notifications.data == false;
        if (!askBackground && !askNotifications) return const SizedBox.shrink();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (askBackground)
                  _Prompt(
                    text:
                        'This phone stops apps in the background. Allow background running '
                        'for Turbo to work.',
                    action: 'Allow',
                    onPressed: () => _run(work.openSettings),
                  ),
                if (askNotifications)
                  _Prompt(
                    text: "Notifications are off, so Turbo can't show what it is doing.",
                    action: 'Allow',
                    onPressed: () => _run(
                      () => work.requestNotifications(fallbackToSettings: true),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.text,
    required this.action,
    required this.onPressed,
  });

  final String text;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(child: Text(text)),
      TextButton(onPressed: onPressed, child: Text(action)),
    ],
  );
}

/// The account the network credits. A real app switches it when its user signs in to another
/// account, and passes the current label to `Yonc.create` on every launch.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key, required this.turbo});

  final Turbo turbo;

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  final TextEditingController _label = TextEditingController(text: reportingId);
  String? _error;

  Future<void> _switch() async {
    try {
      await widget.turbo.setReportingLabel(_label.text);
      setState(() => _error = null);
    } on YoncException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _label,
              decoration: InputDecoration(
                labelText: 'Account label',
                errorText: _error,
              ),
            ),
          ),
          TextButton(onPressed: _switch, child: const Text('Switch')),
        ],
      ),
    ),
  );
}

/// What the user does about each condition.
String conditionLabel(SafeCondition c) => switch (c) {
  SafeCondition.charging => 'Plug in the charger',
  SafeCondition.wifi => 'Connect to Wi-Fi',
  SafeCondition.screenLocked => 'Lock the screen',
  SafeCondition.thermal => 'Let the phone cool down',
  SafeCondition.backgroundWork => 'Allow background running',
};

String statusLabel(TurboStatus s) => switch (s) {
  TurboStatus.off => 'Off',
  TurboStatus.waitingForSafeState => 'Waiting',
  TurboStatus.connecting => 'Connecting',
  TurboStatus.preparing => 'Loading the model',
  TurboStatus.connected => 'Ready for tasks',
  TurboStatus.working => 'Working on a task',
  TurboStatus.error => 'Reconnecting',
  TurboStatus.attestationFailed => 'Not admitted',
};

/// `tier · quant · size`; the SDK hands out bytes, the units are the app's.
String describe(ModelInfo info) => <String>[
  info.tier,
  info.quant,
  if (info.sizeBytes > 0) formatBytes(info.sizeBytes),
].where((s) => s.isNotEmpty).join(' · ');

String formatBytes(int bytes) => bytes >= 1000000000
    ? '${(bytes / 1e9).toStringAsFixed(1)} GB'
    : '${(bytes / 1e6).round()} MB';
