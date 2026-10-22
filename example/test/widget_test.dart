import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soundable_proudp/soundable_proudp.dart';
import 'package:soundable_proudp_example/main.dart';

void main() {
  testWidgets('shows timer and record button', (WidgetTester tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SoundableProudp.channel,
          (call) async => null,
        );

    await tester.pumpWidget(const SampleApp());

    expect(find.text('00:00'), findsOneWidget);
    expect(find.byIcon(Icons.mic), findsOneWidget);
  });
}
