import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinoy_pos/ui/screens/settings/appearance_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('AppearanceSettingsPage builds and toggles theme',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AppearanceSettingsPage(),
        ),
      ),
    );

    // Wait for the async theme preference load to complete.
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Choose how the app looks.'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);

    // Light should be selected (check circle), Dark not (radio unchecked).
    expect(find.widgetWithIcon(ListTile, Icons.check_circle), findsOneWidget);
    expect(
      find.widgetWithIcon(ListTile, Icons.radio_button_unchecked),
      findsOneWidget,
    );

    // Toggle to Dark.
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();

    // Dark should now be selected.
    final darkTile = tester.widget<ListTile>(
      find.ancestor(
        of: find.text('Dark'),
        matching: find.byType(ListTile),
      ),
    );
    final darkTrailing = darkTile.trailing as Icon;
    expect(darkTrailing.icon, Icons.check_circle);
  });
}
