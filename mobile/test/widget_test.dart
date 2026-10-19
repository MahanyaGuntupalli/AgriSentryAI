import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:agrisentry_ai/main.dart';

void main() {
  testWidgets('app boots into the splash screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AgriSentryApp());
    expect(find.text('AgriSentry AI'), findsOneWidget);

    // Let the splash timer fire and navigation complete so no timers are
    // left pending when the test ends.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump();
  });
}
