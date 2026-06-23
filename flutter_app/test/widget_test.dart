import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:secret_santa_organizer/pages/landing_page.dart';

void main() {
  testWidgets('Landing page shows title and sign in button', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LandingPage()));

    expect(find.text('Secret Santa Organizer'), findsOneWidget);
    expect(find.text('Sign In / Register'), findsOneWidget);
  });
}
