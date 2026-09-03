import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Query-side mirror of the Go indexer in
/// `functions/loans/utils/search/tokenizer.go`, `phone.go` and `entities.go`.
///
/// These two implementations must agree exactly. Drift breaks search silently:
/// no error surfaces, a client simply stops being findable. The shared golden
/// vectors at `functions/loans/utils/search/testdata/golden_tokens.json` are
/// asserted from both languages so drift fails CI instead of production.
///
/// Only what the query path runs lives here. The app never writes
/// `search_tokens`, so the four token *producers* the golden file names
/// (`Tokenize`, `PhoneTokens`, `UserTokens`, `ProductViewTokens`) are mirrored
/// in `test/support/search_tokenizer_producers.dart`, where the golden test
/// exercises them. They are built from the same [normalize], [wordForms],
/// [canonicalPhone] and [capFullValue] the query uses, so there is one
/// splitting rule on the Dart side.
abstract final class SearchTokenizer {
  /// Shortest prefix emitted. Two, not three, because two-letter Filipino
  /// surnames (Go, Ty, Uy, Sy, Co) are common and would otherwise be
  /// unsearchable.
  static const int minPrefix = 2;

  /// Longest prefix emitted. Queries longer than this match on the first
  /// [maxPrefix] runes and are refined in Dart against the full term.
  static const int maxPrefix = 12;

  /// Longest full-value token. Not a prefix bound: the full value is exempt
  /// from [maxPrefix], but exempt is not unbounded. Go's `capFullValue`
  /// truncates it because `search_tokens` is automatically single-field
  /// indexed and Firestore rejects a write whose index entry is oversized —
  /// which would make that document permanently unwritable.
  static const int maxFullValue = 256;

  /// Words one composition prefix-expands, counted across its values in order.
  /// Full-value tokens are exempt. `MaxWords` in `Tokenize`.
  static const int maxWords = 64;

  /// Hard ceiling on the emitted array; the sorted set is truncated to it.
  /// `MaxTokens` in `capCount`.
  static const int maxTokens = 2000;

  /// Last-4 tail token length. Deliberately NOT in the golden `limits` block:
  /// the value comes from the `paths.phone_tokens` prose and `PhoneTokens`.
  ///
  /// Public because the query side needs it too: a 4-digit term is the one
  /// case that must be sent raw as well as canonicalized, since
  /// `canonicalPhone('0142')` is `'142'` and no token set contains that.
  static const int lastDigits = 4;

  /// Go splits words on `!unicode.IsLetter(r) && !unicode.IsDigit(r)`
  /// (`Tokenize`), which is Unicode-aware — an ASCII-only class emits no
  /// prefixes at all for a non-Latin name.
  ///
  /// `\p{Nd}`, not `\p{N}`: `\p{N}` is Nd+Nl+No while `unicode.IsDigit` is Nd
  /// only, so `\p{N}` would keep "2½" where Go keeps "2".
  ///
  /// `unicode: true` is load-bearing, not decorative: without it Dart does not
  /// throw, it parses `\p{L}` as a literal character class and every split
  /// returns empty parts.
  static final RegExp _nonAlphanumeric = RegExp(
    r'[^\p{L}\p{Nd}]+',
    unicode: true,
  );

  /// Every Unicode nonspacing mark, matching `runes.In(unicode.Mn)` in the Go
  /// fold. Not the U+0300-U+036F block: Go strips the whole category.
  static final RegExp _combiningMark = RegExp(r'\p{Mn}', unicode: true);

  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _nonDigit = RegExp('[^0-9]');

  /// Lowercases, folds diacritics, trims the ends, AND collapses every
  /// internal run of whitespace to a single space. Both indexing and querying
  /// apply it, so it must match `Normalize`.
  ///
  /// The fold is Go's exact chain — NFD, remove every Mn, NFC, then lowercase
  /// — rather than a lookup table, because a table covers only the characters
  /// someone thought to list: "Nguyễn", "Māori" and a decomposed "Peña" all
  /// fold in Go and all survive a Latin-1 table unchanged, producing a query
  /// token no document contains. Note what this does NOT fold: "ß" and "ø"
  /// have no canonical decomposition, so Go leaves them alone and so must we.
  ///
  /// Collapsing internal whitespace, not merely trimming: on the Go side that
  /// makes "Juan  Carlos" index the same full-value token as "Juan Carlos".
  /// Dart never writes tokens, so nothing here is wrong at runtime — but the
  /// shared golden vectors assert the collapse from both languages. Do not
  /// "fix" a failure there by editing the golden file.
  static String normalize(String value) {
    final folded = unorm.nfc(unorm.nfd(value).replaceAll(_combiningMark, ''));
    return folded
        .toLowerCase()
        .split(_whitespaceRun)
        .where((part) => part.isNotEmpty)
        .join(' ');
  }

  /// The forms `Tokenize` prefix-expands for ONE whitespace-separated word of
  /// a normalized value: the joined form first, then the parts the word splits
  /// into on runs of non-alphanumerics. `dela-cruz` →
  /// `{delacruz, dela, cruz}`, `o'brien` → `{obrien, o, brien}`, `cruz` →
  /// `{cruz}`.
  ///
  /// This is the one splitting rule on the Dart side. `SearchRequest` sends
  /// the joined form's prefix and `FirestoreSearchIndex` refines against the
  /// same forms, so a document Firestore returned for `cruz` is not then
  /// dropped because `'dela-cruz'.startsWith('cruz')` is false.
  static Set<String> wordForms(String word) {
    final parts = word.split(_nonAlphanumeric).where((part) => part.isNotEmpty);

    return <String>{parts.join(), ...parts}..remove('');
  }

  /// The first [maxPrefix] runes of [token] — the longest prefix the index
  /// holds for it, matching `addPrefixes`. Runes, not code units: slicing code
  /// units would send an unpaired surrogate for a non-BMP character, a token
  /// Go can never have written.
  static String prefixOf(String token) =>
      String.fromCharCodes(token.runes.take(maxPrefix));

  /// Reduces a phone number to its national significant digits, so that
  /// `09175550142`, `+639175550142`, `639175550142` and `00639175550142` all
  /// collapse to one token.
  ///
  /// Deliberately not E.164 parsing: search needs consistency, not validity,
  /// and the E.164 path requires a country the query side does not have.
  static String canonicalPhone(String raw) {
    var digits = raw.replaceAll(_nonDigit, '');
    // A loop, not two ifs: `CanonicalPhone` repeats until neither prefix
    // remains, and an international access code stacks them — 0639… needs two
    // passes, 00639… needs three. Terminates because every branch strictly
    // shortens the string and '' starts with neither prefix.
    while (true) {
      if (digits.startsWith('63')) {
        digits = digits.substring(2);
      } else if (digits.startsWith('0')) {
        digits = digits.substring(1);
      } else {
        return digits;
      }
    }
  }

  /// Truncates the full-value token to [maxFullValue] RUNES, never code units
  /// — Go's `capFullValue`: "Runes, not bytes, so the cap means the same
  /// thing in Dart."
  static String capFullValue(String normalized) {
    final runes = normalized.runes.toList();
    if (runes.length <= maxFullValue) return normalized;
    return String.fromCharCodes(runes.take(maxFullValue));
  }
}
