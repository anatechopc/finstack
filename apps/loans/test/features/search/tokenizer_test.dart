import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/search_tokenizer.dart';

/// The producers a golden case may name. Mirrors the `paths` block of
/// golden_tokens.json and `runGoldenCase` in
/// `functions/loans/test/utils/search/tokenizer_test.go:279-300`.
const String pathTokenize = 'tokenize';
const String pathPhoneTokens = 'phone_tokens';
const String pathUserTokens = 'user_tokens';
const String pathProductViewTokens = 'product_view_tokens';

/// How many arguments each path takes. `tokenize` is variadic and deliberately
/// absent. Mirrors `tokenizer_test.go:192-196`: a case with the wrong count is
/// a failure, not a skip - dispatching it anyway would silently assert a
/// different function's contract.
const Map<String, int> inputArity = <String, int>{
  pathPhoneTokens: 1,
  pathUserTokens: 5,
  pathProductViewTokens: 3,
};

List<String> runGoldenCase(String? path, List<String> input) {
  final arity = inputArity[path];
  if (arity != null && input.length != arity) {
    fail(
      'path "$path" takes exactly $arity inputs, got ${input.length}: $input',
    );
  }
  switch (path) {
    case pathTokenize:
      return SearchTokenizer.tokenize(input);
    case pathPhoneTokens:
      return SearchTokenizer.phoneTokens(input[0]);
    case pathUserTokens:
      return SearchTokenizer.userTokens(
        input[0],
        input[1],
        input[2],
        input[3],
        input[4],
      );
    case pathProductViewTokens:
      return SearchTokenizer.productViewTokens(input[0], input[1], input[2]);
    default:
      // golden_tokens.json:5 - an unknown or missing path is a FAILURE, not a
      // skip. A case nothing dispatches asserts nothing while still counting
      // as coverage.
      fail(
        'unknown golden path "$path" - add it here AND to the "paths" block '
        'of golden_tokens.json in the same PR',
      );
  }
}

void main() {
  group('SearchTokenizer', () {
    test('two-letter surnames are indexed whole', () {
      expect(SearchTokenizer.tokenize(['Go']), ['go']);
    });

    test('names expand to prefixes from two characters', () {
      expect(SearchTokenizer.tokenize(['Cruz']), ['cr', 'cru', 'cruz']);
    });

    // phone.go:26-36 loops until neither prefix remains. The last two
    // spellings need two and three trims respectively; trimming each prefix
    // once leaves a token no document contains, so the client is unfindable
    // by their own number with no error anywhere.
    test('canonical phone collapses every spelling', () {
      expect(SearchTokenizer.canonicalPhone('09175550142'), '9175550142');
      expect(SearchTokenizer.canonicalPhone('+639175550142'), '9175550142');
      expect(SearchTokenizer.canonicalPhone('0917 555-0142'), '9175550142');
      expect(SearchTokenizer.canonicalPhone('0639175550142'), '9175550142');
      expect(SearchTokenizer.canonicalPhone('00639175550142'), '9175550142');
    });

    // Mirrors tokenizer_test.go:108-124. Collapsing internal runs, not merely
    // trimming the ends: a doubled space is an ordinary paste artefact.
    test('normalize collapses internal whitespace runs', () {
      expect(SearchTokenizer.normalize('Juan  Carlos'), 'juan carlos');
      expect(SearchTokenizer.normalize('  dela   Cruz\t'), 'dela cruz');
      expect(SearchTokenizer.normalize('Acme\n\nLending'), 'acme lending');
      expect(SearchTokenizer.normalize('already fine'), 'already fine');
      expect(
        SearchTokenizer.tokenize(['Juan  Carlos']),
        SearchTokenizer.tokenize(['Juan Carlos']),
      );
    });

    // Go folds with NFD -> remove every Unicode Mn -> NFC
    // (tokenizer.go:141-152), so it folds precomposed AND decomposed marks and
    // every Latin-Extended letter - but NOT ß or ø, which have no canonical
    // decomposition. The decomposed literal is written as an explicit escape
    // so this file's encoding cannot silently precompose it.
    test('diacritics fold exactly the way Go folds them', () {
      expect(SearchTokenizer.normalize('Pe\u00F1a'), 'pena'); // precomposed
      expect(SearchTokenizer.normalize('Pen\u0303a'), 'pena'); // decomposed
      expect(SearchTokenizer.normalize('Nguy\u1EC5n'), 'nguyen');
      expect(SearchTokenizer.normalize('M\u0101ori'), 'maori');
      expect(SearchTokenizer.normalize('Erd\u0151s'), 'erdos');
      expect(SearchTokenizer.normalize('\u0218tefan'), 'stefan');
      // Go does NOT fold these: no canonical decomposition, so no Mn to
      // remove. A general ASCII-folding package would map them to ss and o
      // and diverge in the opposite direction.
      expect(SearchTokenizer.normalize('Stra\u00DFe'), 'stra\u00DFe');
      expect(SearchTokenizer.normalize('S\u00F8ren'), 's\u00F8ren');
    });

    // tokenizer.go:114-116 splits on !IsLetter && !IsDigit, which is Unicode
    // aware. An ASCII-only `[^a-z0-9]+` emits no prefixes at all for a
    // non-Latin name and mangles ß/ł.
    test('the word split is Unicode-aware, not ASCII-only', () {
      // 'Ivanov' in Cyrillic. The ASCII split emits the full value only.
      expect(
        SearchTokenizer.tokenize(['\u0418\u0432\u0430\u043D\u043E\u0432']),
        <String>[
          '\u0438\u0432',
          '\u0438\u0432\u0430',
          '\u0438\u0432\u0430\u043D',
          '\u0438\u0432\u0430\u043D\u043E',
          '\u0438\u0432\u0430\u043D\u043E\u0432',
        ],
      );
      expect(
        SearchTokenizer.tokenize(['Stra\u00DFe']),
        ['st', 'str', 'stra', 'stra\u00DF', 'stra\u00DFe'],
      );
      // \p{Nd}, not \p{N}: Go's unicode.IsDigit is Nd only, so U+00BD is a
      // separator on both sides and the emitted token is '2'.
      expect(SearchTokenizer.tokenize(['2\u00BD rate']), contains('2'));
      expect(
        SearchTokenizer.tokenize(['2\u00BD rate']),
        isNot(contains('2\u00BD')),
      );
    });

    // Mirrors tokenizer_test.go:75-102. No golden case reaches this length -
    // the longest input in the file is 25 runes - so without this test the cap
    // is unpinned.
    test('the full-value token is truncated, never dropped', () {
      final long = 'añ' * SearchTokenizer.maxFullValue; // multi-byte, 2x runes

      for (final token in SearchTokenizer.tokenize([long])) {
        expect(
          token.runes.length,
          lessThanOrEqualTo(SearchTokenizer.maxFullValue),
          reason: 'token longer than maxFullValue runes: $token',
        );
      }

      final want = String.fromCharCodes(
        SearchTokenizer.normalize(long).runes.take(SearchTokenizer.maxFullValue),
      );
      expect(
        SearchTokenizer.tokenize([long]),
        contains(want),
        reason: 'the full-value token was dropped, not capped',
      );

      // A value at the cap is untouched, so nothing real is truncated.
      final atCap = 'a' * SearchTokenizer.maxFullValue;
      expect(SearchTokenizer.tokenize([atCap]).last, atCap);
    });

    // Mirrors tokenizer_test.go:132-155. Token LENGTH was bounded; token COUNT
    // was not, and an unbounded array makes the document permanently
    // unwritable rather than merely bloated.
    test('word expansion stops at maxWords, counted in order', () {
      final words = List.generate(
        800,
        (i) => 'w${(i + 1).toString().padLeft(4, '0')}',
      );
      final tokens = SearchTokenizer.tokenize([words.join(' ')]);

      expect(tokens.length, lessThanOrEqualTo(SearchTokenizer.maxTokens));
      expect(
        tokens,
        contains('w${SearchTokenizer.maxWords.toString().padLeft(4, '0')}'),
        reason: 'the last word inside the budget was not expanded',
      );
      expect(
        tokens,
        isNot(
          contains(
            'w${(SearchTokenizer.maxWords + 1).toString().padLeft(4, '0')}',
          ),
        ),
        reason: 'the first word past the budget was expanded',
      );
    });

    // Mirrors tokenizer_test.go:160-178. maxWords cannot bound a single
    // pathological *word*; maxTokens is the backstop that makes the array
    // bounded regardless.
    test('the token count is capped for one pathological word', () {
      final word = List.generate(
        2000,
        (i) => String.fromCharCodes([
          97 + i ~/ 676,
          97 + (i ~/ 26) % 26,
          97 + i % 26,
        ]),
      ).join('-');
      expect(
        word.contains(RegExp(r'\s')),
        isFalse,
        reason: 'the input must be a single word, or it tests maxWords',
      );

      expect(
        SearchTokenizer.tokenize([word]).length,
        SearchTokenizer.maxTokens,
        reason: 'fewer means the input stopped being pathological; '
            'more means the cap is gone',
      );
    });
  });

  group('SearchTokenizer golden vectors', () {
    // Relative to the package root; `flutter test` runs with cwd = apps/loans.
    final file = File(
      '../../functions/loans/utils/search/testdata/golden_tokens.json',
    );

    late Map<String, dynamic> golden;
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      expect(
        file.existsSync(),
        isTrue,
        reason: 'golden vectors missing - is the backend merged?',
      );
      golden = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      cases = (golden['cases'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(cases, isNotEmpty);
    });

    // Dart reads these numbers instead of the Go source, so an absent or
    // changed one is silent drift. Mirrors tokenizer_test.go:256-273.
    // Per-key, not whole-map equality: Go flags missing/mismatched keys but
    // tolerates extras, and a sixth limit added later should not redden Dart
    // CI before Dart needs it.
    test('limits block matches the Dart constants', () {
      final limits =
          (golden['limits'] as Map<String, dynamic>).cast<String, int>();
      expect(limits['min_prefix'], SearchTokenizer.minPrefix);
      expect(limits['max_prefix'], SearchTokenizer.maxPrefix);
      expect(limits['max_full_value'], SearchTokenizer.maxFullValue);
      expect(limits['max_words'], SearchTokenizer.maxWords);
      expect(limits['max_tokens'], SearchTokenizer.maxTokens);
    });

    // This is the contract with the Go indexer. If it fails, search breaks
    // invisibly - a client simply cannot be found - so fix the mismatch rather
    // than relaxing the assertion or editing the golden file.
    test('every case matches the producer its path names', () {
      for (final entry in cases) {
        final path = entry['path'] as String?;
        final input = (entry['input'] as List<dynamic>).cast<String>();
        final expected = (entry['tokens'] as List<dynamic>).cast<String>();
        // ORDERED list, per golden_tokens.json:7 - "deduplicated and sorted
        // ascending. Compare as an ordered list." Go uses reflect.DeepEqual on
        // the slice (tokenizer_test.go:241). Ordered equality is safe only
        // while the vectors stay ASCII after folding: Go sorts by UTF-8 bytes
        // and Dart by UTF-16 code units, which diverge for non-BMP tokens. If
        // one is ever added, normalise the sort order on both sides - never
        // fall back to comparing sets, which also hides duplicates and an
        // unsorted return that maxTokens truncation depends on.
        expect(
          runGoldenCase(path, input),
          expected,
          reason: '${entry['name']}\n$path($input) drifted from Go',
        );
      }
    });

    // Coverage, not correctness: the failure this file prevents is silent, so
    // a path losing its last case must break CI rather than quietly stop being
    // asserted. Mirrors tokenizer_test.go:250-254.
    test('all four producers are still exercised', () {
      final seen = cases.map((c) => c['path'] as String?).toSet();
      expect(
        seen,
        containsAll(<String>[
          pathTokenize,
          pathPhoneTokens,
          pathUserTokens,
          pathProductViewTokens,
        ]),
      );
    });
  });
}
