import 'package:blind_way/src/models/models.dart';
import 'package:blind_way/src/ui/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scene cue parsing clamps confidence and accepts known risk', () {
    final cue = SceneCue.fromJson({
      'cue': 'Move left',
      'risk': 'danger',
      'confidence': 1.4,
    });

    expect(cue.cue, 'Move left');
    expect(cue.risk, RiskLevel.danger);
    expect(cue.confidence, 1);
  });

  testWidgets('SOS requires a two second hold', (tester) async {
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SosHoldButton(onActivated: () => activations++)),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SosHoldButton)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(activations, 0);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(activations, 1);
    await gesture.up();
  });
}
