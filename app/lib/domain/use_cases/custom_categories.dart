import 'package:beaza_extraction/beaza_extraction.dart';

/// A category the person made up ("Gifts", "Car"). Stored on the
/// transaction as `custom:<name>`, so it syncs with the transaction and
/// needs no other storage. The server only knows the fixed list, so a
/// custom category goes to the AI as "other".
const String kCustomCategoryPrefix = 'custom:';

/// The longest name a custom category can have.
const int kCustomCategoryMaxLength = 24;

bool isCustomCategory(String bucket) => bucket.startsWith(kCustomCategoryPrefix);

/// The bucket for a typed name, or null when the name is empty after
/// trimming. Control characters are taken out and the name is cut to
/// [kCustomCategoryMaxLength].
String? customCategory(String typed) {
  var name = typed.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
  name = name.replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty) return null;
  if (name.length > kCustomCategoryMaxLength) {
    name = name.substring(0, kCustomCategoryMaxLength).trim();
  }
  return '$kCustomCategoryPrefix$name';
}

/// The name shown for a custom bucket.
String customCategoryName(String bucket) =>
    bucket.substring(kCustomCategoryPrefix.length);

/// The category the server and the AI know: a custom one counts as
/// "other".
String sharedBucket(String bucket) => isCustomCategory(bucket) ? 'other' : bucket;

/// The custom categories already used in the ledger, sorted by name.
List<String> customCategoriesIn(Iterable<LedgerEntry> entries) {
  final found = <String>{};
  for (final e in entries) {
    final c = e.result.category;
    if (c != null && isCustomCategory(c)) found.add(c);
  }
  return found.toList()..sort();
}
