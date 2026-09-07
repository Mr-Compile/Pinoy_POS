import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Revision counter for catalog data (products, categories, stock).
///
/// Catalog screens live inside the app shell's keep-alive `PageView`, so
/// their `initState` only runs once per app session. Mutation sites bump
/// this counter after a successful write; listening screens reload so a
/// product created in Product Management becomes sellable in the POS
/// without an app restart.
final catalogRevisionProvider = StateProvider<int>((ref) => 0);

/// Bumps [catalogRevisionProvider] so every listening screen reloads its
/// catalog data. Call after any successful product/category/stock mutation:
/// create, update, delete, restore, stock change, sale, or backup restore.
void bumpCatalogRevision(WidgetRef ref) {
  ref.read(catalogRevisionProvider.notifier).state++;
}
