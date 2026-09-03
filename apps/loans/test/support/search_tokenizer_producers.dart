import 'package:loooans/features/search/search_tokenizer.dart';

/// Test-only mirrors of the four token PRODUCERS in
/// `functions/loans/utils/search` — `Tokenize`, `PhoneTokens`, `UserTokens`
/// and `ProductViewTokens`.
///
/// They live under `test/` because the app never writes `search_tokens`: it
/// builds one query token, so these would be dead code in `lib/`. They are
/// not dead: they are the producers the golden file names in its `paths`
/// block, and they exist so `golden_tokens.json` can be asserted from Dart at
/// all. Deleting them unpins the Go↔Dart contract.
///
/// Every rule they share with the query path — normalization, the word split,
/// phone canonicalization, the full-value cap — is taken from
/// [SearchTokenizer], so a golden failure here means the query side has
/// drifted too.
abstract final class SearchTokenizerProducers {
  /// Mirrors `Tokenize`, applied to name and email fields.
  ///
  /// Only the first [SearchTokenizer.maxWords] words are prefix-expanded,
  /// counted across all values in order; every non-empty value still
  /// contributes its full-value token regardless of the budget.
  static List<String> tokenize(List<String> values) {
    final tokens = <String>{};
    // Declared outside the values loop: one budget per composition, not per
    // value.
    var budget = SearchTokenizer.maxWords;

    for (final value in values) {
      final normalized = SearchTokenizer.normalize(value);
      if (normalized.isEmpty) continue;

      // The whole value — exempt from maxPrefix, which is what makes a pasted
      // email or phone number match: the word split consumes "@" and "." long
      // before prefixes are taken. Exempt is not unbounded, and truncated is
      // not dropped: a truncated token still matches a query truncated the
      // same way, a dropped one turns a paste into a silent miss.
      tokens.add(SearchTokenizer.capFullValue(normalized));

      // normalize() collapsed every whitespace run to one space and trimmed
      // the ends, so this split never yields an empty word — matching Go's
      // strings.Fields, which never does either.
      for (final word in normalized.split(' ')) {
        if (budget == 0) break;
        budget--;

        for (final form in SearchTokenizer.wordForms(word)) {
          _addPrefixes(tokens, form);
        }
      }
    }

    return _sortedCapped(tokens);
  }

  /// Mirrors `PhoneTokens`: the canonical form, its prefixes, and the last
  /// four digits as a discrete token. Never route a phone number through
  /// [tokenize] — it does none of the canonicalization, so "0917…" and
  /// "+63917…" would index as two different clients.
  static List<String> phoneTokens(String raw) {
    final canonical = SearchTokenizer.canonicalPhone(raw);
    // `PhoneTokens` returns nil for an empty canonical. Without this guard
    // every mobile-less user gets a spurious '' token through userTokens.
    if (canonical.isEmpty) return const <String>[];

    final tokens = <String>{canonical};
    _addPrefixes(tokens, canonical);
    if (canonical.length >= SearchTokenizer.lastDigits) {
      // Safe to index by code unit: canonicalPhone leaves only ASCII digits.
      tokens.add(
        canonical.substring(canonical.length - SearchTokenizer.lastDigits),
      );
    }
    return _sortedCapped(tokens);
  }

  /// Mirrors `UserTokens`. The four name/email fields go through ONE
  /// [tokenize] call — and therefore share one maxWords budget; the mobile
  /// goes through [phoneTokens]. Swapping that routing is the exact drift the
  /// `user_tokens` golden cases exist to catch.
  static List<String> userTokens(
    String firstName,
    String middleName,
    String lastName,
    String mobile,
    String email,
  ) {
    // `merge` in entities.go re-applies the count cap after the union: the
    // sum of two capped groups is not itself capped.
    return _sortedCapped(<String>{
      ...tokenize([firstName, middleName, lastName, email]),
      ...phoneTokens(mobile),
    });
  }

  /// Mirrors `ProductViewTokens` — one [tokenize] call, so all three values
  /// share one maxWords budget. `product_views` has no product-name field;
  /// `loan_type` carries that meaning.
  static List<String> productViewTokens(
    String companyName,
    String loanType,
    String tagLine,
  ) =>
      tokenize([companyName, loanType, tagLine]);

  /// Flattens a token set into the sorted, count-capped array Go writes.
  ///
  /// Go sorts UTF-8 bytes and Dart sorts UTF-16 code units. Those orders agree
  /// for everything up to U+FFFF and diverge only for non-BMP tokens, which no
  /// golden vector contains; if one is ever added, sort both sides by code
  /// point rather than weakening the comparison.
  static List<String> _sortedCapped(Set<String> tokens) {
    final sorted = tokens.toList()..sort();
    return sorted.length <= SearchTokenizer.maxTokens
        ? sorted
        : sorted.sublist(0, SearchTokenizer.maxTokens);
  }

  static void _addPrefixes(Set<String> tokens, String token) {
    // Runes, matching `addPrefixes`. Slicing code units would emit an
    // unpaired surrogate for a non-BMP character, a token Go can never
    // produce.
    final runes = token.runes.toList();
    if (runes.isEmpty) return;
    // A token shorter than minPrefix (a middle initial, a two-letter surname)
    // is indexed verbatim, not dropped.
    if (runes.length < SearchTokenizer.minPrefix) {
      tokens.add(token);
      return;
    }
    final limit = runes.length < SearchTokenizer.maxPrefix
        ? runes.length
        : SearchTokenizer.maxPrefix;
    for (var i = SearchTokenizer.minPrefix; i <= limit; i++) {
      tokens.add(String.fromCharCodes(runes.take(i)));
    }
  }
}
