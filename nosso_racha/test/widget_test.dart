import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nosso_racha/screens/matches/components/team_score_control.dart';

void main() {
  testWidgets('score can increase but cannot decrease below zero', (
    tester,
  ) async {
    int? updatedScore;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamScoreControl(
            teamName: 'Time A',
            score: 0,
            onChanged: (score) => updatedScore = score,
            teamsMap: const {},
            tier1PlayerIds: const [],
          ),
        ),
      ),
    );

    expect(find.text('0'), findsOneWidget);
    expect(
      tester.widget<IconButton>(find.byType(IconButton).first).onPressed,
      isNull,
    );
    expect(
      tester.widget<IconButton>(find.byType(IconButton).last).onPressed,
      isNotNull,
    );

    await tester.tap(find.byType(IconButton).last);
    expect(updatedScore, 1);
  });

  testWidgets('score controls are disabled when the control is read-only', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TeamScoreControl(
            teamName: 'Time A',
            score: 2,
            onChanged: (_) {},
            teamsMap: const {},
            tier1PlayerIds: const [],
            enabled: false,
          ),
        ),
      ),
    );

    expect(find.text('2'), findsOneWidget);
    expect(
      tester
          .widgetList<IconButton>(find.byType(IconButton))
          .every((button) => button.onPressed == null),
      isTrue,
    );
  });
}
