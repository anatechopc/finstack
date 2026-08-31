import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Query-side mirror of the Go indexer in
/// `functions/loans/utils/search/tokenizer.go`, `phone.go` and `entities.go`.
///
/// These two implementations must agree exactly. Drift breaks search silently:
/// no error surfaces, a client simply stops being findable. The shared golden
/// vectors at `functions/loans/utils/search/testdata/golden_tokens.json` are
/// asserted from both languages so drift fails CI instead of production.
///
/// The app never writes `search_tokens` — it builds one query token — so
/// [tokenize], [phoneTokens], [userTokens] and [productViewTokens] look like
/// dead code from the app's side. They are not: they are the four producers
/// the golden file names in its `paths` block, and they exist so that file can
/// be asserted from Dart at all. Deleting them unpins the contract.
abstract final class SearchTokenizer {
  /// Shortest prefix emitted. Two, not three, because two-letter Filipino
  /// surnames (Go, Ty, Uy, Sy, Co) are common and would otherwise be
  /// unsearchable.
  static const int minPrefix = 2;

  /// Longest prefix emitted. Queries longer than this match on the first
  /// [maxPrefix] characters and are refined in Dart against the full term.
  static const int maxPrefix = 12;

  /// Longest full-value token. Not a prefix bound: the full value is exempt
  /// from [maxPrefix], but exempt is not unbounded. Go truncates it at
  /// `tokenizer.go:180` because `search_tokens` is automatically single-field
  /// indexed and Firestore rejects a write whose index entry is oversized —
  /// which would make that document permanently unwritable.
  static const int maxFullValue = 256;

  /// Words one composition prefix-expands, counted across its values in order.
  /// Full-value tokens are exempt. `tokenizer.go:57, :90, :108-112`.
  static const int maxWords = 64;

  /// Hard ceiling on the emitted array; the sorted set is truncated to it.
  /// `tokenizer.go:72, :168-173`.
  static const int maxTokens = 2000;

  /// Last-4 tail token length. Deliberately NOT in the golden `limits` block:
  /// the value comes from the `paths.phone_tokens` prose and `phone.go:9`.
  ///
  /// Public because the query side needs it too: a 4-digit term is the one
  /// case that must be sent raw as well as canonicalized, since
  /// `canonicalPhone('0142')` is `'142'` and no token set contains that.
  static const int lastDigits = 4;

  /// Go splits words on `!unicode.IsLetter(r) && !unicode.IsDigit(r)`
  /// (`tokenizer.go:114-116`), which is Unicode-aware — an ASCII-only class
  /// emits no prefixes at all for a non-Latin name.
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
  /// apply it, so it must match `Normalize` (`tokenizer.go:141-152`).
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

  /// Returns the sorted, deduplicated token set for [values] — the mirror of
  /// `Tokenize` (`tokenizer.go:88-129`), applied to name and email fields.
  ///
  /// Only the first [maxWords] words are prefix-expanded, counted across all
  /// values in order; every non-empty value still contributes its full-value
  /// token regardless of the budget.
  static List<String> tokenize(List<String> values) {
    final tokens = <String>{};
    // Declared outside the values loop: one budget per composition, not per
    // value (tokenizer.go:90).
    var budget = maxWords;

    for (final value in values) {
      final normalized = normalize(value);
      if (normalized.isEmpty) continue;

      // The whole value — exempt from maxPrefix, which is what makes a pasted
      // email or phone number match: the word split consumes "@" and "." long
      // before prefixes are taken. Exempt is not unbounded, and truncated is
      // not dropped: a truncated token still matches a query truncated the
      // same way, a dropped one turns a paste into a silent miss.
      tokens.add(capFullValue(normalized));

      for (final word in normalized.split(_whitespaceRun)) {
        // Go's strings.Fields never yields an empty word; Dart's split can, so
        // skip before spending budget or the boundary shifts on padded input.
        if (word.isEmpty) continue;
        if (budget == 0) break;
        budget--;

        final parts = word
            .split(_nonAlphanumeric)
            .where((part) => part.isNotEmpty)
            .toList();

        final joined = parts.join();
        if (joined.isNotEmpty) _addPrefixes(tokens, joined);
        for (final part in parts) {
          _addPrefixes(tokens, part);
        }
      }
    }

    return _sortedCapped(tokens);
  }

  /// Mirrors `PhoneTokens` (`phone.go:45-62`): the canonical form, its
  /// prefixes, and the last four digits as a discrete token. Never route a
  /// phone number through [tokenize] — it does none of the canonicalization,
  /// so "0917…" and "+63917…" would index as two different clients.
  static List<String> phoneTokens(String raw) {
    final canonical = canonicalPhone(raw);
    // phone.go:47-49 returns nil. Without this guard every mobile-less user
    // gets a spurious '' token through userTokens.
    if (canonical.isEmpty) return const <String>[];

    final tokens = <String>{canonical};
    _addPrefixes(tokens, canonical);
    if (canonical.length >= lastDigits) {
      // Safe to index by code unit: [_nonDigit] leaves only ASCII digits.
      tokens.add(canonical.substring(canonical.length - lastDigits));
    }
    return _sortedCapped(tokens);
  }

  /// Mirrors `UserTokens` (`entities.go:11-17`). The four name/email fields go
  /// through ONE [tokenize] call — and therefore share one [maxWords] budget;
  /// the mobile goes through [phoneTokens]. Swapping that routing is the exact
  /// drift the `user_tokens` golden cases exist to catch.
  static List<String> userTokens(
    String firstName,
    String middleName,
    String lastName,
    String mobile,
    String email,
  ) {
    // entities.go:29-38 re-applies the count cap after the union: the sum of
    // two capped groups is not itself capped.
    return _sortedCapped(<String>{
      ...tokenize([firstName, middleName, lastName, email]),
      ...phoneTokens(mobile),
    });
  }

  /// Mirrors `ProductViewTokens` (`entities.go:22-24`) — one [tokenize] call,
  /// so all three values share one [maxWords] budget. `product_views` has no
  /// product-name field; `loan_type` carries that meaning.
  static List<String> productViewTokens(
    String companyName,
    String loanType,
    String tagLine,
  ) =>
      tokenize([companyName, loanType, tagLine]);

  /// Reduces a phone number to its national significant digits, so that
  /// `09175550142`, `+639175550142`, `639175550142` and `00639175550142` all
  /// collapse to one token.
  ///
  /// Deliberately not E.164 parsing: search needs consistency, not validity,
  /// and the E.164 path requires a country the query side does not have.
  static String canonicalPhone(String raw) {
    var digits = raw.replaceAll(_nonDigit, '');
    // A loop, not two ifs: phone.go:31-40 repeats until neither prefix
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
  /// — `tokenizer.go:178-179`: "Runes, not bytes, so the cap means the same
  /// thing in Dart."
  static String capFullValue(String normalized) {
    final runes = normalized.runes.toList();
    if (runes.length <= maxFullValue) return normalized;
    return String.fromCharCodes(runes.take(maxFullValue));
  }

  /// Flattens a token set into the sorted, count-capped array Go writes.
  ///
  /// Go sorts UTF-8 bytes and Dart sorts UTF-16 code units. Those orders agree
  /// for everything up to U+FFFF and diverge only for non-BMP tokens, which no
  /// golden vector contains; if one is ever added, sort both sides by code
  /// point rather than weakening the comparison.
  static List<String> _sortedCapped(Set<String> tokens) {
    final sorted = tokens.toList()..sort();
    return sorted.length <= maxTokens ? sorted : sorted.sublist(0, maxTokens);
  }

  static void _addPrefixes(Set<String> tokens, String token) {
    // Runes, matching tokenizer.go:189-203. Slicing code units would emit an
    // unpaired surrogate for a non-BMP character, a token Go can never
    // produce.
    final runes = token.runes.toList();
    if (runes.isEmpty) return;
    // tokenizer.go:193-196 — a token shorter than minPrefix (a middle initial,
    // a two-letter surname) is indexed verbatim, not dropped.
    if (runes.length < minPrefix) {
      tokens.add(token);
      return;
    }
    final limit = runes.length < maxPrefix ? runes.length : maxPrefix;
    for (var i = minPrefix; i <= limit; i++) {
      tokens.add(String.fromCharCodes(runes.take(i)));
    }
  }
}
