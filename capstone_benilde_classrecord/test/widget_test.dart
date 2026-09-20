// Basic smoke test: the app builds and the login screen appears.
//
// The default test Flutter creates refers to a `MyApp` class and a counter
// screen, neither of which this project has — that is why it failed to
// analyse. This one matches the real app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capstone_benilde_classrecord/main.dart';

void main() {
  testWidgets('App starts on the login screen when signed out',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ClassRecordApp(startSignedIn: false));
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}