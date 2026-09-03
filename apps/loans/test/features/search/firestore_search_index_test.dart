import 'dart:convert';
import 'dart:io';

import 'package:company_repository/company_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/search/firestore_search_index.dart';
import 'package:loooans/features/search/search_index.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_tokenizer.dart';
import 'package:loooans/services/authentication_service.dart';
import 'package:loooans_helpers/data_helpers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:product_view_repository/product_view_repository.dart';
import 'package:user_repository/user_repository.dart';

class MockAuthenticationService extends Mock
    implements AuthenticationService {}

class MockCompany extends Mock implements Company {}

/// A `User` fixture built field-by-field: `User.create` demands an
/// `ImageUrl`, a `Sex` and an `EmploymentDetails` that no search assertion
/// reads, and every field below is one the refinement actually touches.
User _user({
  String id = 'user-1',
  String firstName = 'Juan',
  String? middleName,
  String lastName = 'Dela Cruz',
  String mobileNumber = '9175550142',
  String emailAddress = 'juan.cruz@gmail.com',
  UserRole userRole = UserRole.customer,
}) =>
    User()
      ..id = id
      ..firstName = firstName
      ..middleName = middleName
      ..lastName = lastName
      ..mobileNumber = mobileNumber
      ..emailAddress = emailAddress
      ..userRole = userRole;

ProductView _offer({
  String productId = 'product-1',
  String companyId = 'lender-1',
  String companyName = 'Acme Lending',
  String loanType = 'Salary Loan',
  String? tagLine,
  String term = '30d',
}) =>
    ProductView.create(
      companyId: companyId,
      companyName: companyName,
      productId: productId,
      loanType: loanType,
      term: term,
      interestRate: 3.5,
      maxLoanableAmount: 50000,
      maxPeriod: 6,
      reviewRatingAvg: 0,
      reviewCount: 0,
      allowAddOns: true,
      tagLine: tagLine,
    );

QueryStatement? _stmt(List<QueryStatement> statements, String field) {
  for (final statement in statements) {
    if (statement.field == field) return statement;
  }

  return null;
}

Set<String> _fields(List<QueryStatement> statements) =>
    statements.map((statement) => statement.field).toSet();

/// The field sets of every shipped `search_tokens` composite index, read from
/// the deployed dev file. Firestore will not use a composite index unless
/// every field is constrained, so a query whose field set matches none of
/// these fails at runtime in production.
Map<String, List<Set<String>>> _shippedIndexes() {
  final json = jsonDecode(File('firestore.indexes.dev.json').readAsStringSync())
      as Map<String, dynamic>;
  final result = <String, List<Set<String>>>{};

  for (final entry in json['indexes']! as List<dynamic>) {
    final index = entry as Map<String, dynamic>;
    final fields = (index['fields']! as List<dynamic>)
        .map((field) => (field as Map<String, dynamic>)['fieldPath']! as String)
        .toSet();
    if (!fields.contains('search_tokens')) continue;
    final collection = (index['collectionGroup']! as String)
        .replaceFirst(RegExp('^(dev|stg)_'), '');
    result.putIfAbsent(collection, () => <Set<String>>[]).add(fields);
  }

  return result;
}

void main() {
  late MockAuthenticationService auth;
  late List<QueryStatement> clientStatements;
  late List<QueryStatement> offerStatements;
  late List<User> clientResponse;
  late List<ProductView> offerResponse;

  FirestoreSearchIndex buildIndex() => FirestoreSearchIndex(
        auth: auth,
        loadClients: (statements, limit) async {
          clientStatements = statements;

          return clientResponse;
        },
        loadOffers: (statements, limit) async {
          offerStatements = statements;

          return offerResponse;
        },
      );

  void signInAs(UserRole role, {String? companyId}) {
    when(() => auth.user).thenReturn(_user(userRole: role));
    if (companyId == null) {
      // Mirrors the shipped getter, which throws for `customer` and
      // `appAdmin` (`AuthenticationService.company`). Reading it for those
      // roles must fail the test, not silently return null.
      when(() => auth.company).thenThrow(
        Exception('Cannot get company for role ${role.label}'),
      );
    } else {
      final company = MockCompany();
      when(() => company.id).thenReturn(companyId);
      when(() => auth.company).thenReturn(company);
    }
  }

  setUp(() {
    auth = MockAuthenticationService();
    clientStatements = [];
    offerStatements = [];
    clientResponse = [];
    offerResponse = [];
  });

  group('SearchRequest', () {
    test('queryToken truncates to maxPrefix', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: 'bartholomewson',
      );
      expect(request.queryTokens, ['bartholomews']);
    });

    test('queryToken canonicalizes a pasted phone number', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: '0917 555 0142',
      );
      expect(request.queryTokens, ['9175550142']);
    });

    test('queryToken keeps a pasted email whole', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: 'juan.cruz@gmail.com',
      );
      expect(request.queryTokens.first, 'juan.cruz@gmail.com');
    });

    // The index prefix-expands the JOINED form of a word (`Tokenize`:
    // "o'brien" -> "obrien", "dela-cruz" -> "delacruz"), so punctuation typed
    // into a query must be stripped the same way or the token hits nothing.
    test('queryTokens send the joined form of a punctuated word', () {
      const cases = <String, String>{
        "o'br": 'obr',
        'dela-c': 'delac',
        'maria.santos': 'mariasantos',
        'mary-jane smith': 'maryjane',
      };
      for (final entry in cases.entries) {
        expect(
          SearchRequest(scope: SearchScope.clients, term: entry.key)
              .queryTokens,
          [entry.value],
          reason: entry.key,
        );
      }
    });

    // A partial paste ("juan.cruz@gm") has no full-value token to hit; the
    // joined prefix of the local part is what finds the document.
    test('an email term also sends the joined prefix of its local part', () {
      expect(
        const SearchRequest(
          scope: SearchScope.clients,
          term: 'juan.cruz@gmail.com',
        ).queryTokens,
        ['juan.cruz@gmail.com', 'juancruz'],
      );
      expect(
        const SearchRequest(
          scope: SearchScope.clients,
          term: 'juan_cruz-x+tag@gm',
        ).queryTokens,
        ['juan_cruz-x+tag@gm', 'juancruzxtag'],
      );
    });

    // `addPrefixes` counts runes. A code-unit cut at maxPrefix splits a
    // surrogate pair and sends a token Go can never have written.
    test('queryTokens and isSearchable count runes, not code units', () {
      // U+1D400 is non-BMP: two UTF-16 code units per rune.
      final long = '\u{1D400}' * (SearchTokenizer.maxPrefix + 1);
      final tokens =
          SearchRequest(scope: SearchScope.clients, term: long).queryTokens;
      expect(tokens.single.runes.length, SearchTokenizer.maxPrefix);
      expect(
        tokens.single,
        String.fromCharCodes(long.runes.take(SearchTokenizer.maxPrefix)),
      );

      // One rune, two code units: below minPrefix, so never sent.
      expect(
        const SearchRequest(scope: SearchScope.clients, term: '\u{1D400}')
            .isSearchable,
        isFalse,
      );
    });

    test('a term shorter than minPrefix is not searchable', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: 'd',
      );
      expect(request.isSearchable, isFalse);
    });

    test('a 4-digit tail emits both the raw tail and the canonical form', () {
      const request = SearchRequest(
        scope: SearchScope.clients,
        term: '0142',
      );
      expect(request.queryTokens, containsAll(<String>['0142', '142']));
    });

    test('a 4-digit run that needs no canonicalization emits one token', () {
      const request = SearchRequest(scope: SearchScope.clients, term: '1420');
      expect(request.queryTokens, ['1420']);
    });

    test('a prefix-shaped digit run is not regressed by the tail path', () {
      const request = SearchRequest(scope: SearchScope.clients, term: '0917');
      expect(request.queryTokens, containsAll(<String>['917', '0917']));
    });

    test('a term whose token canonicalizes away is not searchable', () {
      for (final term in ['63', '+63', '09', '()']) {
        expect(
          SearchRequest(scope: SearchScope.clients, term: term).isSearchable,
          isFalse,
          reason: '"$term" sends an empty token, which can never match',
        );
      }
      expect(
        const SearchRequest(scope: SearchScope.clients, term: '091')
            .isSearchable,
        isTrue,
      );
    });
  });

  group('clients query authorization', () {
    test('staff carry company_id equal to the authenticated company', () {
      for (final role in UserRole.companyManagedRoles) {
        signInAs(role, companyId: 'company-1');
        final statements = buildIndex().statementsFor(
          const SearchRequest(scope: SearchScope.clients, term: 'dela'),
        );

        expect(
          _stmt(statements, 'company_id')?.isEqualTo,
          'company-1',
          reason: '${role.name} must be scoped to its own company',
        );
        expect(_stmt(statements, 'user_role')?.isEqualTo, 'customer');
        expect(
          _stmt(statements, 'search_tokens')?.arrayContainsAny,
          ['dela'],
        );
      }
    });

    test('appAdmin carries no company_id and never reads company', () {
      signInAs(UserRole.appAdmin);
      final statements = buildIndex().statementsFor(
        const SearchRequest(scope: SearchScope.clients, term: 'dela'),
      );

      expect(_stmt(statements, 'company_id'), isNull);
      expect(_stmt(statements, 'user_role')?.isEqualTo, 'customer');
      verifyNever(() => auth.company);
    });

    test('no OfferFilters field ever reaches a clients query', () {
      signInAs(UserRole.admin, companyId: 'company-1');
      final statements = buildIndex().statementsFor(
        const SearchRequest(
          scope: SearchScope.clients,
          term: 'dela',
          filters: OfferFilters(companyId: 'lender-9', term: '30d'),
        ),
      );

      expect(_stmt(statements, 'term'), isNull);
      expect(
        _stmt(statements, 'company_id')?.isEqualTo,
        'company-1',
        reason: 'the viewer company, never the filter facet',
      );
    });

    test('no deleted_at statement — load() already adds one', () {
      signInAs(UserRole.admin, companyId: 'company-1');
      final statements = buildIndex().statementsFor(
        const SearchRequest(scope: SearchScope.clients, term: 'dela'),
      );

      expect(_stmt(statements, 'deleted_at'), isNull);
    });

    test('a customer never produces a clients query, under any input', () async {
      signInAs(UserRole.customer);
      final index = buildIndex();

      for (final term in ['dela', 'clients: dela', '0917 555 0142', 'a@b.co']) {
        for (final filters in const [
          OfferFilters(),
          OfferFilters(companyId: 'lender-9', term: '30d'),
        ]) {
          final request = SearchRequest(
            scope: SearchScope.clients,
            term: term,
            filters: filters,
          );
          final results = await index.query(request);

          expect(results.items, isEmpty);
          expect(index.statementsFor(request), isEmpty);
          expect(
            clientStatements,
            isEmpty,
            reason: 'no clients query may reach the repository for "$term"',
          );
        }
      }
      verifyNever(() => auth.company);
    });
  });

  group('offers query authorization', () {
    test('staff offers are scoped to the viewer company (design spec)', () {
      signInAs(UserRole.loanOfficer, companyId: 'company-1');
      final statements = buildIndex().statementsFor(
        const SearchRequest(
          scope: SearchScope.offers,
          term: 'salary',
          filters: OfferFilters(companyId: 'lender-9'),
        ),
      );

      expect(
        _stmt(statements, 'company_id')?.isEqualTo,
        'company-1',
        reason: 'the injected viewer company wins over the facet',
      );
    });

    test('a customer offers query is unscoped and honours the facet', () {
      signInAs(UserRole.customer);
      final statements = buildIndex().statementsFor(
        const SearchRequest(
          scope: SearchScope.offers,
          term: 'salary',
          filters: OfferFilters(companyId: 'lender-9', term: '30d'),
        ),
      );

      expect(_stmt(statements, 'company_id')?.isEqualTo, 'lender-9');
      expect(_stmt(statements, 'term')?.isEqualTo, '30d');
      verifyNever(() => auth.company);
    });

    test('an appAdmin offers query never reads company', () {
      signInAs(UserRole.appAdmin);
      final statements = buildIndex().statementsFor(
        const SearchRequest(scope: SearchScope.offers, term: 'salary'),
      );

      expect(_stmt(statements, 'company_id'), isNull);
      verifyNever(() => auth.company);
    });
  });

  group('every emitted query shape matches a shipped index', () {
    final shipped = _shippedIndexes();

    void expectServed(
      String collection,
      List<QueryStatement> statements,
      Set<String> implicit,
    ) {
      final shape = _fields(statements).union(implicit);
      // anyElement(unorderedEquals(...)), not contains(): Set does not
      // override ==, so contains() compares by identity and always fails.
      expect(
        shipped[collection],
        anyElement(unorderedEquals(shape)),
        reason: '$collection shape $shape is served by no shipped index',
      );
    }

    test('clients, for every role that can reach the scope', () {
      for (final role in [...UserRole.companyManagedRoles, UserRole.appAdmin]) {
        signInAs(
          role,
          companyId: role == UserRole.appAdmin ? null : 'company-1',
        );
        expectServed(
          'users',
          buildIndex().statementsFor(
            const SearchRequest(scope: SearchScope.clients, term: 'dela'),
          ),
          // load() adds `deleted_at isNull` and orders by `last_name`.
          {'deleted_at', 'last_name'},
        );
      }
    });

    test('offers, across every role and filter combination', () {
      const filterCombinations = [
        OfferFilters(),
        OfferFilters(term: '30d'),
        OfferFilters(companyId: 'lender-9'),
        OfferFilters(companyId: 'lender-9', term: '30d'),
      ];

      for (final role in UserRole.values) {
        signInAs(
          role,
          companyId: UserRole.companyManagedRoles.contains(role)
              ? 'company-1'
              : null,
        );
        for (final filters in filterCombinations) {
          expectServed(
            'product_views',
            buildIndex().statementsFor(
              SearchRequest(
                scope: SearchScope.offers,
                term: 'salary',
                filters: filters,
              ),
            ),
            // load() adds `deleted_at isNull` and orders by `updated_at`.
            {'deleted_at', 'updated_at'},
          );
        }
      }
    });
  });

  group('query', () {
    test('a customer search runs and does not throw', () async {
      signInAs(UserRole.customer);
      offerResponse = [_offer()];

      final results = await buildIndex().query(
        const SearchRequest(scope: SearchScope.offers, term: 'salary'),
      );

      expect(_stmt(offerStatements, 'search_tokens')?.arrayContainsAny, [
        'salary',
      ]);
      expect(results.items, hasLength(1));
      expect(
        (results.items.single as OfferResultItem).productView.productId,
        'product-1',
      );
      expect(results.items.single.matchedField, 'loan_type');
      verifyNever(() => auth.company);
    });

    test('an appAdmin search runs and does not throw', () async {
      signInAs(UserRole.appAdmin);
      clientResponse = [_user()];

      final results = await buildIndex().query(
        const SearchRequest(scope: SearchScope.clients, term: 'dela'),
      );

      expect(results.items, hasLength(1));
      verifyNever(() => auth.company);
    });

    test('an unsearchable term issues no query at all', () async {
      signInAs(UserRole.admin, companyId: 'company-1');

      final results = await buildIndex().query(
        const SearchRequest(scope: SearchScope.clients, term: '63'),
      );

      expect(results.items, isEmpty);
      expect(clientStatements, isEmpty);
    });

    test('refines names against the full term, not the sent token', () async {
      signInAs(UserRole.admin, companyId: 'company-1');
      clientResponse = [
        _user(id: 'keep', lastName: 'Bartholomewson'),
        _user(id: 'drop', lastName: 'Bartholomewsmith'),
      ];

      final results = await buildIndex().query(
        const SearchRequest(scope: SearchScope.clients, term: 'bartholomewson'),
      );

      expect(
        results.items
            .map((item) => (item as ClientResultItem).user.id)
            .toList(),
        ['keep'],
      );
    });

    // Firestore returns "Dela-Cruz" for the token 'cruz' because the indexer
    // split the word on the hyphen; refinement must split the same way or it
    // drops a row the index correctly returned.
    test('refinement splits words the way the indexer does', () async {
      signInAs(UserRole.admin, companyId: 'company-1');
      final fixtures = [
        _user(id: 'hyphen', lastName: 'Dela-Cruz'),
        _user(id: 'apostrophe', lastName: "O'Brien", emailAddress: 'pat@x.com'),
        _user(
          id: 'email',
          lastName: 'Reyes',
          emailAddress: 'juan.delacruz@x.com',
        ),
      ];
      const expected = <String, Map<String, String>>{
        'cruz': {'hyphen': 'name'},
        'brien': {'apostrophe': 'name'},
        "o'br": {'apostrophe': 'name'},
        'dela-c': {'hyphen': 'name', 'email': 'email'},
        'delacruz': {'hyphen': 'name', 'email': 'email'},
        'juan.delacruz@x.com': {'email': 'email'},
        'juan.dela': {'email': 'email'},
      };

      for (final entry in expected.entries) {
        clientResponse = fixtures;
        final results = await buildIndex().query(
          SearchRequest(scope: SearchScope.clients, term: entry.key),
        );

        expect(
          {
            for (final item in results.items)
              (item as ClientResultItem).user.id: item.matchedField,
          },
          entry.value,
          reason: '"${entry.key}"',
        );
      }
    });

    // `PhoneTokens` indexes prefixes of the canonical number AND its last four
    // digits, and the query sends both forms of a 4-digit term. Refinement
    // has to accept either, or '0917' and '9175' find nothing.
    test('a 4-digit term matches a prefix or the tail of the mobile', () async {
      signInAs(UserRole.admin, companyId: 'company-1');

      for (final term in ['0917', '9175', '0142', '917 5']) {
        clientResponse = [_user()];
        final results = await buildIndex().query(
          SearchRequest(scope: SearchScope.clients, term: term),
        );

        expect(results.items, hasLength(1), reason: '"$term" must match');
        expect(results.items.single.matchedField, 'mobile');
      }

      clientResponse = [_user()];
      final miss = await buildIndex().query(
        const SearchRequest(scope: SearchScope.clients, term: '5550'),
      );
      expect(miss.items, isEmpty, reason: 'neither a prefix nor the tail');
    });

    // `Tokenize` emits digit-only parts of an email ('jc.1998@x.com' ->
    // '1998'), so a digit run the mobile does not match may still be a
    // correct email match.
    test('a phone-shaped term falls back to the email parts', () async {
      signInAs(UserRole.admin, companyId: 'company-1');
      clientResponse = [_user(emailAddress: 'jc.1998@x.com')];

      final results = await buildIndex().query(
        const SearchRequest(scope: SearchScope.clients, term: '1998'),
      );

      expect(results.items, hasLength(1));
      expect(results.items.single.matchedField, 'email');
    });

    test('every phone spelling survives refinement', () async {
      signInAs(UserRole.admin, companyId: 'company-1');

      for (final term in [
        '+63 917 555 0142',
        '0917 555 0142',
        '09175550142',
        '0142',
      ]) {
        // The fixture stores the bare 10-digit form the app writes.
        clientResponse = [_user()];
        final results = await buildIndex().query(
          SearchRequest(scope: SearchScope.clients, term: term),
        );

        expect(results.items, hasLength(1), reason: '"$term" must match');
        expect(results.items.single.matchedField, 'mobile');
      }
    });

    test('hasMore comes from the raw page, not the refined one', () async {
      signInAs(UserRole.admin, companyId: 'company-1');
      // candidateLimit + 1 documents come back; all but one are refined away.
      clientResponse = [
        for (var i = 0; i <= 3; i++)
          _user(id: 'u$i', lastName: i == 0 ? 'Delacruz' : 'Delgado'),
      ];

      final results = await buildIndex().query(
        const SearchRequest(
          scope: SearchScope.clients,
          term: 'dela',
          candidateLimit: 3,
        ),
      );

      expect(results.items, hasLength(1));
      expect(results.hasMore, isTrue);
    });
  });
}
