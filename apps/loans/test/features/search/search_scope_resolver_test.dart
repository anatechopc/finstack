import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:user_repository/user_repository.dart';

/// Realistic locations, taken from the routes `router.dart` actually
/// registers. `/offers/id` and `/` are the two offer-shaped ones.
const _locations = <String>[
  Paths.index,
  Paths.dashboard,
  Paths.users,
  Paths.paymentCenter,
  Paths.chat,
  '/offers/id',
  '/loans/id',
  '/clients/id',
  '/search',
];

void main() {
  group('SearchScopeResolver.scopesFor', () {
    // The security-relevant case: a borrower has no clients scope at all.
    // Not hidden in the UI - absent from the resolver, so no caller can
    // construct a clients query even by trying.
    test('a customer can never resolve a clients scope', () {
      expect(
        SearchScopeResolver.scopesFor(UserRole.customer),
        {SearchScope.offers},
      );
    });

    // Written over UserRole.values rather than a hand-written list so a
    // seventh role cannot be added to the enum without this test naming it.
    test('every non-customer role gets both scopes', () {
      for (final role in UserRole.values.where((r) => r != UserRole.customer)) {
        expect(
          SearchScopeResolver.scopesFor(role),
          {SearchScope.clients, SearchScope.offers},
          reason: '$role should have both scopes',
        );
      }
    });

    test('every role resolves to a non-empty scope set', () {
      for (final role in UserRole.values) {
        expect(
          SearchScopeResolver.scopesFor(role),
          isNotEmpty,
          reason: '$role has no searchable scope at all',
        );
      }
    });
  });

  group('SearchScopeResolver.resolve', () {
    test('staff default to clients', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.admin,
        location: Paths.paymentCenter,
        rawQuery: 'dela cruz',
      );
      expect(parsed.scope, SearchScope.clients);
      expect(parsed.term, 'dela cruz');
    });

    test('borrowers default to offers', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.customer,
        location: Paths.index,
        rawQuery: 'salary',
      );
      expect(parsed.scope, SearchScope.offers);
    });

    // appAdmin has no company (authentication_service.dart:42-53 throws for
    // it), so this must resolve without ever reading AuthenticationService.
    test('appAdmin gets clients on a staff route without touching auth', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.appAdmin,
        location: Paths.users,
        rawQuery: 'dela cruz',
      );
      expect(parsed.scope, SearchScope.clients);
    });

    test('the offers route defaults to offers even for staff', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.teller,
        location: '/offers/id',
        rawQuery: 'salary',
      );
      expect(parsed.scope, SearchScope.offers);
    });

    test('an explicit prefix overrides the route default', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.admin,
        location: Paths.paymentCenter,
        rawQuery: 'products: salary',
      );
      expect(parsed.scope, SearchScope.offers);
      expect(parsed.term, 'salary');
    });

    test('a clients prefix overrides an offers route for staff', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.loanOfficer,
        location: '/offers/id',
        rawQuery: 'clients: dela cruz',
      );
      expect(parsed.scope, SearchScope.clients);
      expect(parsed.term, 'dela cruz');
    });

    // A prefix naming a scope the role lacks must not escalate. It is text.
    test('a prefix for a forbidden scope is treated as literal text', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.customer,
        location: Paths.index,
        rawQuery: 'clients: dela cruz',
      );
      expect(parsed.scope, SearchScope.offers);
      expect(parsed.term, 'clients: dela cruz');
    });

    test('casing and spacing cannot smuggle a forbidden prefix past', () {
      for (final raw in <String>[
        'clients: dela cruz',
        'CLIENTS: dela cruz',
        'Clients:dela cruz',
        '   clients:dela cruz   ',
        'clients:',
      ]) {
        final parsed = SearchScopeResolver.resolve(
          role: UserRole.customer,
          location: Paths.paymentCenter,
          rawQuery: raw,
        );
        expect(
          parsed.scope,
          SearchScope.offers,
          reason: '"$raw" escalated a customer to clients',
        );
        expect(
          parsed.term,
          raw.trim(),
          reason: '"$raw" was stripped as if the prefix were honoured',
        );
      }
    });

    // The deep-link path from amendment B11: /search?scope=clients hands the
    // resolver a pinned scope minted outside it. The pin is intersected with
    // the role's permitted set, so a borrower's pin is dropped, not honoured.
    test('a pinned scope the role lacks is dropped, not honoured', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.customer,
        location: '/search',
        rawQuery: 'dela cruz',
        pinnedScope: SearchScope.clients,
      );
      expect(parsed.scope, SearchScope.offers);
      expect(parsed.term, 'dela cruz');
    });

    test('a pinned scope the role has overrides the route default', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.admin,
        location: Paths.paymentCenter,
        rawQuery: 'salary',
        pinnedScope: SearchScope.offers,
      );
      expect(parsed.scope, SearchScope.offers);
    });

    test('an explicit prefix beats a pinned scope', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.admin,
        location: Paths.index,
        rawQuery: 'clients: dela cruz',
        pinnedScope: SearchScope.offers,
      );
      expect(parsed.scope, SearchScope.clients);
      expect(parsed.term, 'dela cruz');
    });

    // The whole boundary, swept: no location, no prefix, and no pin lets a
    // customer out of the offers scope.
    test('no location, prefix or pin ever gives a customer clients', () {
      for (final location in _locations) {
        for (final raw in <String>[
          'dela cruz',
          'clients: dela cruz',
          'products: salary',
          'clients:clients:clients: x',
          '',
        ]) {
          for (final pin in <SearchScope?>[null, ...SearchScope.values]) {
            final parsed = SearchScopeResolver.resolve(
              role: UserRole.customer,
              location: location,
              rawQuery: raw,
              pinnedScope: pin,
            );
            expect(
              parsed.scope,
              SearchScope.offers,
              reason: 'customer escaped to clients via '
                  'location=$location raw="$raw" pin=$pin',
            );
          }
        }
      }
    });
  });
}
