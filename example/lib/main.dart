import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soundable_proudp/soundable_proudp.dart';

import 'constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Contact dev@soundable.health to get the server configuration.
  SoundableProudp.init(
    apiKey: apiKey,
    serverUrl: serverUrl,
    socketUrl: socketUrl,
  ).catchError((Object e) => debugPrint('[soundable] init: $e'));
  runApp(const SampleApp());
}

class SampleApp extends StatelessWidget {
  const SampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'proudP Flutter Sample',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const RecordScreen(),
    );
  }
}

class RecordScreen extends StatefulWidget {
  const RecordScreen({super.key});

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen> {
  late final AppLifecycleListener _lifecycleListener;
  Gender _gender = Gender.male;
  int _seconds = 0;
  AnalysisResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Recording in the background is not supported. Cancel it when the app is
    // no longer visible.
    _lifecycleListener = AppLifecycleListener(
      onHide: () {
        if (SoundableProudp.isRecording) _cancel();
      },
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await SoundableProudp.requestPermission()) {
      _showMessage('Microphone permission is required.');
      return;
    }
    setState(() {
      _seconds = 0;
      _result = null;
      _error = null;
    });
    try {
      await SoundableProudp.start(
        user: SoundableUser(id: userId, gender: _gender, clinic: clinic),
        onRecording: (seconds) => setState(() => _seconds = seconds),
        // Reached the max recording time. Receive the result with stop().
        onAutoStop: _receiveResult,
        onCallInterrupted: () {
          setState(() => _seconds = 0);
          _showMessage('Recording was cancelled due to an incoming call.');
        },
      );
    } on SoundableProudpException catch (e) {
      _showMessage(e.message);
    }
    setState(() {});
  }

  // Stops recording (if still recording) and waits for the analysis result.
  Future<void> _receiveResult() async {
    final future = SoundableProudp.stop();
    setState(() {});
    try {
      final result = await future;
      debugPrint('[soundable] result $result');
      setState(() => _result = result);
    } on SoundableProudpException catch (e) {
      debugPrint('[soundable] $e');
      if (e.code != SoundableProudpException.cancelled) {
        setState(() => _error = '${e.code}: ${e.message}');
      }
    }
    if (mounted) setState(() => _seconds = 0);
  }

  Future<void> _cancel() async {
    await SoundableProudp.cancel();
    setState(() => _seconds = 0);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = SoundableProudp.state;
    final isRecording = state == SoundableProudpState.recording;
    final isAnalyzing = state == SoundableProudpState.analyzing;

    return Scaffold(
      appBar: AppBar(title: const Text('proudP Flutter Sample')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            SegmentedButton<Gender>(
              segments: const [
                ButtonSegment(value: Gender.male, label: Text('Male')),
                ButtonSegment(value: Gender.female, label: Text('Female')),
              ],
              selected: {_gender},
              onSelectionChanged: state == SoundableProudpState.idle
                  ? (selected) => setState(() => _gender = selected.first)
                  : null,
            ),
            const SizedBox(height: 40),
            Text(
              _formatTime(_seconds),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displayMedium,
            ),
            Text(
              'max ${_formatTime(SoundableProudp.maxRecordingSeconds)}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Center(
              child: SizedBox.square(
                dimension: 110,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: isRecording ? Colors.red : Colors.grey,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isAnalyzing
                      ? null
                      : (isRecording ? _receiveResult : _start),
                  child: Icon(isRecording ? Icons.stop : Icons.mic, size: 48),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (state != SoundableProudpState.idle)
              Center(
                child: TextButton(
                  onPressed: _cancel,
                  child: const Text('Cancel'),
                ),
              ),
            if (isAnalyzing) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              const Text('Analyzing...', textAlign: TextAlign.center),
            ],
            if (_error != null) ...[
              const SizedBox(height: 24),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_result != null) ...[
              const SizedBox(height: 24),
              _ResultCard(result: _result!),
            ],
          ],
        ),
      ),
    );
  }

  static String _formatTime(int seconds) =>
      '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});

  final AnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final rows = {
      'result': result.result,
      'qmax': result.qmax,
      'volume': result.volume,
      'record_date': result.recordDate,
      'available': '${result.available}',
      'url': result.url,
      'flow_list': '${result.flowList.length} values',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Analysis result',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final MapEntry(:key, :value) in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 100, child: Text(key)),
                    Expanded(child: SelectableText(value)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
