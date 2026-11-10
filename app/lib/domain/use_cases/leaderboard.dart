import 'package:beaza_extraction/beaza_extraction.dart' show Day;

/// The four persona titles, lowest tier first. The words are in the ARB
/// files; this is only which one.
enum PersonaTitle { guardian, filsMaster, captain, falcon }

/// The title for a score: it moves up with the points of the last 30 days.
PersonaTitle personaTitle(int points) => points >= 300
    ? PersonaTitle.falcon
    : points >= 200
        ? PersonaTitle.captain
        : points >= 100
            ? PersonaTitle.filsMaster
            : PersonaTitle.guardian;

/// FNV-1a over the UTF-16 code units: the same on every phone and on the
/// server (String.hashCode is not).
int fnv1a(String s) {
  var h = 0x811c9dc5;
  for (final u in s.codeUnits) {
    h ^= u & 0xff;
    h = (h * 0x01000193) & 0xffffffff;
    h ^= u >> 8;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The number after the title, 100 to 999, from the board id.
int personaNumber(String boardId) => 100 + fnv1a(boardId) % 900;

enum NicknameProblem { tooShort, tooLong, notLetters }

final RegExp _lettersAndSpaces = RegExp(r'^[\p{L}\p{M} ]+$', unicode: true);

/// A nickname with its spaces tidied (trimmed, runs of spaces made one).
String tidyNickname(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Why [raw] cannot be a nickname, or null when it can: 3 to 15 characters,
/// letters and spaces only. No digit in any script, no @, dot, dash or
/// other sign, so a phone number, a CPR number, an e-mail address or a
/// social handle cannot be typed in.
NicknameProblem? nicknameProblem(String raw) {
  final n = tidyNickname(raw);
  if (!_lettersAndSpaces.hasMatch(n) && n.isNotEmpty) {
    return NicknameProblem.notLetters;
  }
  final length = n.runes.length;
  if (length < 3) return NicknameProblem.tooShort;
  if (length > 15) return NicknameProblem.tooLong;
  return null;
}

/// One line of the board.
class BoardRow {
  const BoardRow({
    required this.points,
    required this.streak,
    required this.number,
    this.nickname,
    this.me = false,
  });

  /// Points of the last 30 days.
  final int points;
  final int streak;

  /// The persona number (100 to 999).
  final int number;

  /// Shown instead of the persona when the person chose a nickname.
  final String? nickname;
  final bool me;

  PersonaTitle get title => personaTitle(points);

  /// Stable id for the row's place in the list.
  String get id => me ? 'me' : '${nickname ?? ''}#$number';
}

/// Highest points first, then the longer streak, then the number, so the
/// order never depends on chance.
List<BoardRow> rankBoard(Iterable<BoardRow> rows) => rows.toList()
  ..sort((a, b) => a.points != b.points
      ? b.points.compareTo(a.points)
      : a.streak != b.streak
          ? b.streak.compareTo(a.streak)
          : a.number.compareTo(b.number));

/// The practice board: 15 made-up personas to measure against when the
/// online board is off. They are examples written into the app, not
/// people, and the screen says so. Their scores are fixed shapes (a keen
/// saver, an average week, a hard month) that drift a little each week so
/// the board is not frozen.
List<BoardRow> practiceBoard(Day today) {
  const base = <(int, int, int)>[
    // points, streak, number
    (410, 27, 812), (370, 19, 309), (330, 14, 547), (300, 21, 126),
    (270, 9, 688), (240, 12, 451), (220, 6, 935), (190, 8, 204),
    (170, 4, 773), (150, 7, 362), (120, 3, 590), (100, 5, 841),
    (80, 2, 417), (50, 1, 256), (30, 0, 679),
  ];
  final week = DateTime.utc(today.year, today.month, today.day)
          .difference(DateTime.utc(2026, 1, 3))
          .inDays ~/
      7;
  return [
    for (final (points, streak, number) in base)
      BoardRow(
        // Up or down by 0, 10 or 20 points, in tens like real points.
        points: (points + ((fnv1a('$number/$week') % 5) - 2) * 10)
            .clamp(0, 999),
        streak: streak,
        number: number,
      ),
  ];
}
