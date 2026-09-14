import 'package:pinoy_pos/core/currency_utils.dart';
import 'package:pinoy_pos/data/models/ai_response.dart';
import 'package:pinoy_pos/data/models/category.dart';
import 'package:pinoy_pos/data/models/product.dart';
import 'package:pinoy_pos/services/category_service.dart';
import 'package:pinoy_pos/services/product_service.dart';

/// Result of an AI-requested product creation.
class AIProductActionResult {
  final bool success;
  final String message;

  const AIProductActionResult({required this.success, required this.message});
}

/// Result of extracting a model-emitted `ACTION:create_product` block from
/// a Groq reply. [cleanedText] is the reply with the block removed;
/// [notice] is a plain-text line appended when the block could not be used.
class AIExtractedProductAction {
  final String cleanedText;
  final AIAction? action;
  final String? notice;

  const AIExtractedProductAction({
    required this.cleanedText,
    this.action,
    this.notice,
  });
}

/// Parsed key=value fields (internal).
class _ProductFields {
  String? name;
  double? price;
  int? stock;
  int? minStock;
  String? categoryName;
  String? description;
}

class _ActionBuild {
  final AIAction? action;
  final String? failure;
  final List<AIAction> extraActions;
  final Category? category;

  const _ActionBuild({
    this.action,
    this.failure,
    this.extraActions = const [],
    this.category,
  });
}

/// Local product-creation assistant for the AI Advisor.
///
/// Handles two paths with one validation pipeline:
/// 1. Deterministic commands typed or pasted by the owner:
///      add product: name=Pastil; price=80; stock=20; category=Meals
///    These run entirely offline and never consume the daily AI quota.
/// 2. `ACTION:create_product` blocks emitted by the model for natural-
///    language requests ("create a product called Pastil at 80 pesos").
///    The block is parsed out of the raw reply before sanitization.
///
/// In both paths the service only PREPARES a confirmed [AIAction]. The
/// actual write goes through [ProductService.createProduct] when the user
/// taps the Create Product chip, so permission checks, field validation,
/// duplicate rules, and the activity log are identical to the manual form.
class AIProductActionService {
  AIProductActionService._();

  /// Registry destination id used for create-product actions.
  static const String destinationId = 'create_product';

  static ProductService _productService = ProductService();
  static CategoryService _categoryService = CategoryService();

  /// Test hooks — mirror the AINavigationService.salesService pattern.
  static set productService(ProductService service) =>
      _productService = service;
  static set categoryService(CategoryService service) =>
      _categoryService = service;

  static void resetForTest() {
    _productService = ProductService();
    _categoryService = CategoryService();
  }

  // ── Detection ────────────────────────────────────────────────────────

  static final _productWord =
      RegExp(r'\b(product|item)\b', caseSensitive: false);

  static final _howToPattern = RegExp(
    r'(how\s+(do|can|to)\b.{0,50}\b(add|create|new|register)\b.{0,20}\b(product|item)\b)|'
    r'((help|guide|teach|steps)\b.{0,40}\b(add|create|new|register)\b.{0,20}\b(product|item)\b)|'
    r'(\b(add|create|new|register)\b.{0,20}\b(product|item)\b.{0,40}\b(how|help|guide|teach|steps)\b)',
    caseSensitive: false,
  );

  static final _explicitCommandPattern = RegExp(
    r'\b(?:add|create|new|register)\s+(?:a\s+|an\s+)?product\s*:',
    caseSensitive: false,
  );

  static final _createIntentPattern = RegExp(
    r'\b(add|create|new|register)\b.{0,15}\b(product|item)\b',
    caseSensitive: false,
  );

  /// key=value / key:value pairs. A value ends at `;`, a newline, end of
  /// text, or a separator that introduces another key (so comma-separated
  /// single-line input works while names containing commas stay intact).
  static final _fieldPattern = RegExp(
    r'\b(name|price|stock|qty|quantity|min[_\s-]?stock|category|description|desc)\s*[:=]\s*'
    r'(.+?)'
    r'(?=\s*[,;\n]\s*(?:name|price|stock|qty|quantity|min[_\s-]?stock|category|description|desc)\s*[:=]|\s*[;\n]|\s*$)',
    caseSensitive: false,
    multiLine: true,
  );

  /// Model-emitted action block: `ACTION:create_product ... END_ACTION`.
  static final _modelActionPattern = RegExp(
    r'ACTION\s*:\s*create_product([\s\S]*?)(?:END_ACTION|\Z)',
    caseSensitive: false,
  );

  // ── Local command resolution ─────────────────────────────────────────

  /// Resolves a user query to a structured [AIResponse] for product
  /// creation flows: how-to guide, confirmation card, or error card.
  /// Returns null when the query is not product-creation related so the
  /// caller can fall through to navigation and the Groq pipeline.
  static Future<AIResponse?> resolveCommand(
    String query, {
    required bool Function(String) hasPermission,
  }) async {
    final lower = query.toLowerCase().trim();
    final mentionsProduct = _productWord.hasMatch(lower);
    final canEdit = hasPermission('edit_products');
    final fields = _parseFields(query);
    final hasFields = fields.name != null ||
        fields.price != null ||
        fields.stock != null ||
        fields.categoryName != null;

    // "How do I add a product?" → teaching card (owner only; other roles
    // fall through to the navigation assistant for the Products screen).
    if (mentionsProduct && _howToPattern.hasMatch(lower)) {
      return canEdit ? _guideResponse() : null;
    }

    // Explicit "add product: ..." command or pasted field list.
    final isExplicit = _explicitCommandPattern.hasMatch(query);
    final isFieldPaste = hasFields &&
        (mentionsProduct || (fields.name != null && fields.price != null));
    if (isExplicit || isFieldPaste) {
      if (!canEdit) return _deniedResponse();
      return _confirmationOrFix(fields);
    }

    // Bare intent: "create a product", "I want to add an item".
    if (mentionsProduct && _createIntentPattern.hasMatch(lower)) {
      return canEdit ? _guideResponse() : _deniedResponse();
    }

    return null;
  }

  // ── Model action extraction (Groq path) ─────────────────────────────

  /// Extracts an `ACTION:create_product` block from [rawContent].
  /// Returns null when no block is present. When a block exists, the
  /// returned [AIExtractedProductAction] always has the block stripped;
  /// [action] is set only when every validation passes, otherwise
  /// [notice] carries a plain-text reason to show the owner.
  static Future<AIExtractedProductAction?> extractModelAction(
    String rawContent, {
    required bool Function(String) hasPermission,
  }) async {
    final match = _modelActionPattern.firstMatch(rawContent);
    if (match == null) return null;

    final cleaned =
        rawContent.replaceRange(match.start, match.end, '').trim();

    if (!hasPermission('edit_products')) {
      return AIExtractedProductAction(
        cleanedText: cleaned,
        notice: 'Only the Owner account can create products.',
      );
    }

    final fields = _parseFields(match.group(1)!);
    final build = await _buildAction(fields);

    return AIExtractedProductAction(
      cleanedText: cleaned,
      action: build.action,
      notice: build.action == null
          ? 'I could not prepare that product: ${build.failure}'
          : null,
    );
  }

  // ── Execution ────────────────────────────────────────────────────────

  /// Validates the parameters carried by a `createProduct` action chip.
  static bool hasValidParameters(AIAction action) {
    final p = action.parameters;
    final name = p['name'];
    final price = p['price'];
    final stock = p['stock'];
    final minStock = p['minStock'];
    final categoryId = p['categoryId'];
    return name is String &&
        name.trim().isNotEmpty &&
        price is num &&
        price > 0 &&
        stock is num &&
        stock >= 0 &&
        categoryId is num &&
        categoryId > 0 &&
        (minStock == null || (minStock is num && minStock >= 0));
  }

  /// Executes a confirmed create-product action. Re-runs every check so a
  /// stale chip (duplicate created meanwhile, category removed, session
  /// changed) can never write invalid data.
  static Future<AIProductActionResult> createProduct(
    AIAction action, {
    required bool Function(String) hasPermission,
  }) async {
    if (!hasPermission('edit_products')) {
      return const AIProductActionResult(
        success: false,
        message: 'Only the Owner account can create products.',
      );
    }
    if (!hasValidParameters(action)) {
      return const AIProductActionResult(
        success: false,
        message:
            'The product details are incomplete or invalid. Please ask the advisor to prepare it again.',
      );
    }

    final p = action.parameters;
    final name = (p['name'] as String).trim();
    final price = (p['price'] as num).toDouble();
    final stock = (p['stock'] as num).toInt();
    final minStock = (p['minStock'] as num?)?.toInt() ?? 10;
    final categoryId = (p['categoryId'] as num).toInt();
    final categoryName =
        p['categoryName'] as String? ?? 'the selected category';
    final description = p['description'] as String?;

    // Duplicate rule mirrors the product dialog: same name + same category.
    final existing = await _productService.getProductByName(name);
    if (existing != null && existing.categoryId == categoryId) {
      return AIProductActionResult(
        success: false,
        message: 'A product named "$name" already exists in $categoryName.',
      );
    }

    try {
      final created = await _productService.createProduct(
        Product(
          name: name,
          price: price,
          stock: stock,
          minStock: minStock,
          categoryId: categoryId,
          description: description,
          createdAt: DateTime.now(),
        ),
      );
      if (created) {
        return AIProductActionResult(
          success: true,
          message:
              '"$name" was added to $categoryName with $stock in stock at '
              '${CurrencyUtils.symbol()}${price.toStringAsFixed(2)}.',
        );
      }
      return const AIProductActionResult(
        success: false,
        message:
            'The product could not be saved. Check that the category still exists and try again.',
      );
    } catch (_) {
      return const AIProductActionResult(
        success: false,
        message: 'The product could not be saved. Please try again.',
      );
    }
  }

  // ── Response builders ────────────────────────────────────────────────

  static Future<AIResponse> _guideResponse() async {
    final categories = await _activeCategories();
    final exampleCategory =
        categories.isNotEmpty ? categories.first.name : 'Meals';
    final example =
        'add product: name=Pastil; price=80; stock=20; category=$exampleCategory';
    final categoryLine = categories.isEmpty
        ? 'category=(create a category first — every product needs one)'
        : 'category=(one of: ${categories.map((c) => c.name).join(', ')})';

    return AIResponse(
      message: 'I can create the product for you. Send the details in this '
          'format, or open Products and tap Add Product to do it manually.',
      instructions: [
        const AIInstruction(text: 'add product:'),
        const AIInstruction(text: 'name=(product name)'),
        const AIInstruction(text: 'price=(selling price, e.g. 80)'),
        const AIInstruction(text: 'stock=(quantity on hand, e.g. 20)'),
        AIInstruction(text: categoryLine),
        const AIInstruction(
            text: 'min_stock=(optional low-stock alert level, default 10)'),
        const AIInstruction(text: 'description=(optional)'),
      ],
      actions: [
        if (categories.isEmpty)
          const AIAction(
            type: AIActionType.navigate,
            destination: 'categories',
            label: 'Create Category',
          ),
        const AIAction(
          type: AIActionType.navigate,
          destination: 'products',
          label: 'Open Products',
        ),
      ],
      suggestions: [example],
    );
  }

  static Future<AIResponse> _confirmationOrFix(_ProductFields fields) async {
    final build = await _buildAction(fields);

    if (build.action == null) {
      final categories = await _activeCategories();
      final exampleCategory =
          categories.isNotEmpty ? categories.first.name : 'Meals';
      final example =
          'add product: name=Pastil; price=80; stock=20; category=$exampleCategory';
      return AIResponse(
        message: 'I could not prepare that product. ${build.failure}\n\n'
            'Send the details like this: $example',
        actions: build.extraActions,
        suggestions: [example],
      );
    }

    final minStock = fields.minStock ?? 10;
    final desc = (fields.description != null && fields.description!.isNotEmpty)
        ? '\nDescription: ${fields.description}'
        : '';
    return AIResponse(
      message: 'I can create this product:\n'
          'Name: ${fields.name}\n'
          'Price: ${CurrencyUtils.symbol()}${fields.price!.toStringAsFixed(2)}\n'
          'Stock: ${fields.stock}\n'
          'Category: ${build.category!.name}\n'
          'Min stock: $minStock$desc\n\n'
          'Tap Create Product to confirm.',
      actions: [build.action!],
      suggestions: const ['Open Products', 'Add another product'],
    );
  }

  static AIResponse _deniedResponse() => const AIResponse(
        message: 'Only the Owner account can create products. You can still '
            'browse the product list.',
        actions: [
          AIAction(
            type: AIActionType.navigate,
            destination: 'products',
            label: 'Open Products',
          ),
        ],
        suggestions: [
          'Which products are low on stock?',
          'Show my sales today',
        ],
      );

  // ── Shared validation pipeline ───────────────────────────────────────

  static Future<_ActionBuild> _buildAction(_ProductFields f) async {
    final missing = <String>[
      if (f.name == null || f.name!.isEmpty) 'name',
      if (f.price == null) 'price',
      if (f.stock == null) 'stock',
      if (f.categoryName == null || f.categoryName!.isEmpty) 'category',
    ];
    if (missing.isNotEmpty) {
      return _ActionBuild(failure: 'Missing: ${missing.join(', ')}.');
    }

    final errors = <String>[
      if (f.price! <= 0) 'price must be greater than 0',
      if (f.stock! < 0) 'stock cannot be negative',
      if (f.minStock != null && f.minStock! < 0)
        'min_stock cannot be negative',
    ];
    if (errors.isNotEmpty) {
      return _ActionBuild(failure: 'Invalid: ${errors.join('; ')}.');
    }

    final categories = await _activeCategories();
    if (categories.isEmpty) {
      return const _ActionBuild(
        failure: 'There are no active categories yet. Create a category '
            'first — every product needs one.',
        extraActions: [
          AIAction(
            type: AIActionType.navigate,
            destination: 'categories',
            label: 'Open Categories',
          ),
        ],
      );
    }

    final category = _matchCategory(f.categoryName!, categories);
    if (category == null) {
      return _ActionBuild(
        failure: "I couldn't find a category called '${f.categoryName}'. "
            'Available: ${categories.map((c) => c.name).join(', ')}.',
      );
    }

    final existing = await _productService.getProductByName(f.name!);
    if (existing != null && existing.categoryId == category.id) {
      return _ActionBuild(
        failure:
            'A product named "${f.name}" already exists in ${category.name}.',
      );
    }

    return _ActionBuild(
      category: category,
      action: AIAction(
        type: AIActionType.createProduct,
        destination: destinationId,
        label: 'Create Product',
        parameters: {
          'name': f.name!,
          'price': f.price!,
          'stock': f.stock!,
          'minStock': f.minStock ?? 10,
          'categoryId': category.id!,
          'categoryName': category.name,
          if (f.description != null && f.description!.isNotEmpty)
            'description': f.description,
        },
      ),
    );
  }

  static Future<List<Category>> _activeCategories() async {
    try {
      return await _categoryService.getActiveCategories();
    } catch (_) {
      return const [];
    }
  }

  static Category? _matchCategory(String input, List<Category> categories) {
    final q = input.trim().toLowerCase();
    final asId = int.tryParse(input.trim());
    for (final c in categories) {
      if (c.name.toLowerCase() == q) return c;
      if (asId != null && c.id == asId) return c;
    }
    final partial =
        categories.where((c) => c.name.toLowerCase().startsWith(q)).toList();
    return partial.length == 1 ? partial.first : null;
  }

  static _ProductFields _parseFields(String text) {
    final f = _ProductFields();
    for (final m in _fieldPattern.allMatches(text)) {
      final key = m.group(1)!.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
      final raw = m.group(2)!.trim();
      final value = _stripQuotes(raw.replaceAll(RegExp(r'[,;\s]+$'), ''));
      switch (key) {
        case 'name':
          f.name = value;
        case 'price':
          f.price =
              double.tryParse(value.replaceAll(RegExp(r'[^\d.\-]'), ''));
        case 'stock':
        case 'qty':
        case 'quantity':
          f.stock = int.tryParse(value.replaceAll(RegExp(r'[^\d\-]'), ''));
        case 'minstock':
          f.minStock =
              int.tryParse(value.replaceAll(RegExp(r'[^\d\-]'), ''));
        case 'category':
          f.categoryName = value;
        case 'description':
        case 'desc':
          f.description = value;
      }
    }
    return f;
  }

  static String _stripQuotes(String value) {
    if (value.length >= 2) {
      final first = value[0];
      final last = value[value.length - 1];
      if ((first == '"' && last == '"') || (first == "'" && last == "'")) {
        return value.substring(1, value.length - 1).trim();
      }
    }
    return value;
  }
}
