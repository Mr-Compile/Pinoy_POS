import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/ui/widgets/responsive_create_action.dart';

/// Harness that wires [ResponsiveCreateAction] exactly like a CRUD screen:
/// FAB in the Scaffold slot and the content action inside a [CrudToolbar].
Widget _harness({VoidCallback? onPressed}) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        final action = ResponsiveCreateAction(
          label: 'Add Product',
          icon: Icons.add,
          onPressed: onPressed ?? () {},
        );
        return Scaffold(
          floatingActionButton: action.fab(context),
          body: Column(
            children: [
              CrudToolbar(
                search: const TextField(
                  decoration: InputDecoration(hintText: 'Search products'),
                ),
                controls: const [
                  FilterChip(
                    label: Text('All'),
                    selected: true,
                    onSelected: null,
                  ),
                ],
                primaryAction: action.contentAction(context),
              ),
              Text('clearance:${action.contentBottomClearance(context)}'),
            ],
          ),
        );
      },
    ),
  );
}

void _setView(
  WidgetTester tester,
  double width,
  double height,
) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('compact portrait: icon-only FAB, no toolbar button',
      (tester) async {
    _setView(tester, 390, 800);
    await tester.pumpWidget(_harness());

    expect(find.byType(FloatingActionButton), findsOneWidget);
    // Icon-only FAB: the label lives in the tooltip, not inside the button.
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('Add Product'),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Add Product'), findsOneWidget);
    expect(find.text('Add Product'), findsNothing);
    expect(find.text('clearance:88.0'), findsOneWidget);
  });

  testWidgets('very narrow portrait: compact circular FAB', (tester) async {
    _setView(tester, 320, 640);
    await tester.pumpWidget(_harness());

    expect(find.byType(FloatingActionButton), findsOneWidget);
    // Icon-only FAB: no label text inside, tooltip provides the name.
    expect(
      find.descendant(
        of: find.byType(FloatingActionButton),
        matching: find.text('Add Product'),
      ),
      findsNothing,
    );
    expect(find.byTooltip('Add Product'), findsOneWidget);
  });

  testWidgets('compact landscape: toolbar button, no FAB', (tester) async {
    _setView(tester, 560, 320);
    await tester.pumpWidget(_harness());

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Add Product'),
      findsOneWidget,
    );
    expect(find.text('clearance:0.0'), findsOneWidget);

    // The action sits below the search field in the stacked compact layout.
    final searchRect = tester.getRect(find.byType(TextField));
    final actionRect =
        tester.getRect(find.widgetWithText(FilledButton, 'Add Product'));
    expect(actionRect.top, greaterThanOrEqualTo(searchRect.bottom));
  });

  testWidgets('medium tablet: toolbar button beside search, no FAB',
      (tester) async {
    _setView(tester, 800, 600);
    await tester.pumpWidget(_harness());

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Add Product'),
      findsOneWidget,
    );

    // Same row: the action is to the right of the search field.
    final searchRect = tester.getRect(find.byType(TextField));
    final actionRect =
        tester.getRect(find.widgetWithText(FilledButton, 'Add Product'));
    expect(actionRect.left, greaterThan(searchRect.right));
  });

  testWidgets('expanded desktop: in-content button, no FAB', (tester) async {
    _setView(tester, 1280, 800);
    await tester.pumpWidget(_harness());

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      find.widgetWithText(FilledButton, 'Add Product'),
      findsOneWidget,
    );
    expect(find.text('clearance:0.0'), findsOneWidget);
  });

  testWidgets('toolbar button fires the callback', (tester) async {
    var tapped = 0;
    _setView(tester, 800, 600);
    await tester.pumpWidget(_harness(onPressed: () => tapped++));

    await tester.tap(find.widgetWithText(FilledButton, 'Add Product'));
    expect(tapped, 1);
  });
}
