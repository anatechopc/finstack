import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:loooans/features/search/search_scope_resolver.dart';
import 'package:user_repository/user_repository.dart';

/// Realistic locations, taken from the routes `router.dart` actually
/// registers. `/offers/id` and the in-shell marketplace `/?sec=offers` are
/// the offer-shaped locations; a bare `/` is not — there the role decides, so
/// staff get clients and a customer gets offers.
const _locations = <String>[
  Paths.index,
  Paths.dashboard,
  Paths.users,
  Paths.paymentCenter,
  Paths.chat,
  '/offers/id',
  '/?sec=offers',
  '/?sec=offers&id=123abc',
  '/?sec=clients',
  '/loans/id',
  '/clients/id',
  '/search',
];

/// Every spelling of "the user is looking at offers". The marketplace is a
/// section of the shell, not a route: `MainScreen` renders it for
/// `?sec=offers`, so a path check alone left staff there searching clients.
const _offerLocations = <String>[
  '/offers/id',
  '/?sec=offers',
  '/?sec=offers&id=123abc',
  '/?id=123abc&sec=offers',
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

    // The home page used to force offers as "the marketplace", so a teller
    // typing a client's name there searched products. The role decides now.
    test('staff on the home page default to clients', () {
      for (final role in [
        UserRole.admin,
        UserRole.teller,
        UserRole.loanOfficer,
      ]) {
        final parsed = SearchScopeResolver.resolve(
          role: role,
          location: Paths.index,
          rawQuery: 'dela cruz',
        );
        expect(parsed.scope, SearchScope.clients, reason: role.name);
      }
    });

    // `products:` was the only offers keyword and the first admin to try it
    // typed `offer:`, which fell through as literal text. Every obvious
    // spelling of both scopes is accepted; a forbidden one is still text.
    test('every alias of a prefix forces its scope', () {
      for (final alias in ['offers', 'offer', 'products', 'product']) {
        final parsed = SearchScopeResolver.resolve(
          role: UserRole.admin,
          location: Paths.index,
          rawQuery: '$alias: salary',
        );
        expect(parsed.scope, SearchScope.offers, reason: alias);
        expect(parsed.term, 'salary', reason: alias);
      }
      for (final alias in ['clients', 'client', 'borrowers', 'borrower']) {
        for (final location in _offerLocations) {
          final parsed = SearchScopeResolver.resolve(
            role: UserRole.admin,
            location: location,
            rawQuery: '$alias: dela cruz',
          );
          expect(parsed.scope, SearchScope.clients, reason: '$alias $location');
          expect(parsed.term, 'dela cruz', reason: alias);
        }
      }
    });

    test('an alias of a forbidden scope is literal text for a customer', () {
      for (final alias in ['client', 'borrowers', 'borrower']) {
        final parsed = SearchScopeResolver.resolve(
          role: UserRole.customer,
          location: Paths.index,
          rawQuery: '$alias: dela cruz',
        );
        expect(parsed.scope, SearchScope.offers, reason: alias);
        expect(parsed.term, '$alias: dela cruz', reason: alias);
      }
    });

    test('borrowers default to offers', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.customer,
        location: Paths.index,
        rawQuery: 'salary',
      );
      expect(parsed.scope, SearchScope.offers);
    });

    // appAdmin has no company (`AuthenticationService.company` throws for
    // it), so this must resolve without ever reading AuthenticationService.
    test('appAdmin gets clients on a staff route without touching auth', () {
      final parsed = SearchScopeResolver.resolve(
        role: UserRole.appAdmin,
        location: Paths.users,
        rawQuery: 'dela cruz',
      );
      expect(parsed.scope, SearchScope.clients);
    });

    test('every offers location defaults to offers even for staff', () {
      for (final location in _offerLocations) {
        final parsed = SearchScopeResolver.resolve(
          role: UserRole.teller,
          location: location,
          rawQuery: 'salary',
        );
        expect(parsed.scope, SearchScope.offers, reason: location);
      }
    });

    // Only the offers section is offers; every other section of the shell,
    // and a `sec` that merely mentions offers elsewhere in the URL, is where
    // the role decides.
    test('other shell sections and look-alikes still default to clients', () {
      for (final location in <String>[
        '/?sec=clients',
        '/?sec=loans&id=offers',
        '/?section=offers',
        '/search?q=offers',
        '/loans/offers',
      ]) {
        final parsed = SearchScopeResolver.resolve(
          role: UserRole.teller,
          location: location,
          rawQuery: 'dela',
        );
        expect(parsed.scope, SearchScope.clients, reason: location);
      }
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

    test('a clients prefix overrides an offers location for staff', () {
      for (final location in _offerLocations) {
        final parsed = SearchScopeResolver.resolve(
          role: UserRole.loanOfficer,
          location: location,
          rawQuery: 'clients: dela cruz',
        );
        expect(parsed.scope, SearchScope.clients, reason: location);
        expect(parsed.term, 'dela cruz');
      }
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
