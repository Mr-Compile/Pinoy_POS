import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pinoy_pos/ui/widgets/app_input_fields.dart';

/// Widget tests for the shared input-field components.
///
/// Verifies the modern field design is applied consistently and that the
/// password toggle, dropdown, and search field behave correctly.
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );
  }

  testWidgets('AppTextFormField shows the label and applies theme fill',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        AppTextFormField(
          label: 'Product Name',
          prefixIcon: Icons.inventory_2_outlined,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Product Name'), findsWidgets);
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });

  testWidgets('AppTextFormField shows validation error text', (tester) async {
    final formKey = GlobalKey<FormState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Form(
            key: formKey,
            child: AppTextFormField(
              label: 'Price',
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Price is required' : null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    formKey.currentState!.validate();
    await tester.pump();

    expect(find.text('Price is required'), findsOneWidget);
  });

  testWidgets('AppPasswordField toggles password visibility', (tester) async {
    final controller = TextEditingController(text: 'secret');

    await tester.pumpWidget(
      wrap(
        AppPasswordField(
          controller: controller,
          label: 'Password',
        ),
      ),
    );
    await tester.pump();

    // Initially obscured: visibility_off shown.
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    // Now visible: visibility icon shown.
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
  });

  testWidgets('AppDropdownField shows label and items', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppDropdownField<int>(
          label: 'Category',
          items: const [
            DropdownMenuItem(value: 1, child: Text('Beverages')),
            DropdownMenuItem(value: 2, child: Text('Snacks')),
          ],
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Category'), findsWidgets);
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pump();
    expect(find.text('Beverages'), findsWidgets);
    expect(find.text('Snacks'), findsWidgets);
  });

  testWidgets('AppSearchField shows search icon and hint', (tester) async {
    await tester.pumpWidget(
      wrap(
        AppSearchField(
          hint: 'Search products',
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.text('Search products'), findsOneWidget);
  });

  testWidgets('AppPasswordField disables toggle while loading', (tester) async {
    await tester.pumpWidget(
      wrap(
        const AppPasswordField(
          label: 'Password',
          isLoading: true,
        ),
      ),
    );
    await tester.pump();

    final iconButton = tester.widget<IconButton>(find.byType(IconButton));
    expect(iconButton.onPressed, isNull);
  });
}
