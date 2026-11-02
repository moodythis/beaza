/// Maps sender IDs to sender families (SRS FR-3.2, FR-2.1).
///
/// A sender family is the set of messages from one bank or wallet that share
/// template structure. The registry is data driven: the real list of sender
/// IDs comes from the collected messages, so nothing is hard-coded here.
class SenderRegistry {
  /// [families] maps a family name to the sender IDs it uses, for example
  /// `{'SomeBank': ['SOMEBANK', 'SOME-BANK']}`.
  ///
  /// Throws [ArgumentError] if one sender ID is claimed by two families.
  SenderRegistry(Map<String, List<String>> families)
      : _familyById = _build(families);

  final Map<String, String> _familyById;

  static final RegExp _ignoredChars = RegExp(r'[\s\-_.]');

  /// Upper-cases a sender ID and removes spaces, hyphens, underscores and dots.
  static String normalizeId(String id) =>
      id.toUpperCase().replaceAll(_ignoredChars, '');

  /// The family of [senderId], or null if the sender is not on the list.
  /// A null result means the message must be ignored (FR-2.1).
  String? familyOf(String senderId) => _familyById[normalizeId(senderId)];

  static Map<String, String> _build(Map<String, List<String>> families) {
    final map = <String, String>{};
    families.forEach((family, ids) {
      for (final id in ids) {
        final key = normalizeId(id);
        if (key.isEmpty) {
          continue;
        }
        final existing = map[key];
        if (existing != null && existing != family) {
          throw ArgumentError(
            'Sender ID "$id" belongs to both $existing and $family',
          );
        }
        map[key] = family;
      }
    });
    return map;
  }
}
