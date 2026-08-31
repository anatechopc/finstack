import 'package:loooans/app/routing/paths.dart';
import 'package:loooans/features/search/search_scope.dart';
import 'package:user_repository/user_repository.dart';

/// Resolves a raw query into a scope, in strict order: role decides which
/// scopes exist at all, an explicit prefix overrides among those, a pinned
/// scope (a tab tap or a `/search?scope=` deep link) comes next, and the
/// route supplies the default.
///
/// Pure by design — it reads no `AuthenticationService`. `company` throws for
/// `customer` and `appAdmin` (`authentication_service.dart:42-53`), so an
/// authorization decision must never depend on it.
abstract final class SearchScopeResolver {
  /// Scopes available to [role]. A customer has no clients scope - this is the
  /// authorization boundary, not a UI preference.
  ///
  /// A new [UserRole] must be added to this switch explicitly; the switch is
  /// exhaustive so the compiler forces the choice. Default to the customer
  /// branch — clients scope is client-PII access and is granted deliberately,
  /// with a test naming the role. Before granting it, confirm the role already
  /// reaches `LoanClientsScreen` (`main_screen.dart:336-338` gates on
  /// `!isCustomer()`); search must be neither broader nor narrower than the
  /// screen it searches.
  static Set<SearchScope> scopesFor(UserRole role) {
    switch (role) {
      case UserRole.customer:
        return {SearchScope.offers};
      case UserRole.teller:
      case UserRole.loanOfficer:
      case UserRole.admin:
      case UserRole.appAdmin:
      case UserRole.reviewModerator:
        // reviewModerator matches `main_screen.dart:336-338`, which renders
        // LoanClientsScreen to every non-customer. Search must not be
        // stricter than the screen it searches.
        return {SearchScope.clients, SearchScope.offers};
    }
  }

  static ParsedQuery resolve({
    required UserRole role,
    required String location,
    required String rawQuery,
    SearchScope? pinnedScope,
  }) {
    final permitted = scopesFor(role);
    final trimmed = rawQuery.trim();

    for (final scope in SearchScope.values) {
      final marker = '${scope.prefix}:';
      if (!trimmed.toLowerCase().startsWith(marker)) continue;
      // A prefix naming a scope this role lacks must not escalate; fall
      // through and treat the whole string as search text.
      if (!permitted.contains(scope)) break;
      return ParsedQuery(
        scope: scope,
        term: trimmed.substring(marker.length).trim(),
      );
    }

    // A pin is minted outside this resolver (a scope tab, or `?scope=` on
    // /search, which has no role gate in `router.dart`). Intersect it with
    // the permitted set exactly as a typed prefix is: an impermissible pin
    // is dropped, not honoured.
    if (pinnedScope != null && permitted.contains(pinnedScope)) {
      return ParsedQuery(scope: pinnedScope, term: trimmed);
    }

    return ParsedQuery(
      scope: _defaultScope(location, permitted),
      term: trimmed,
    );
  }

  static SearchScope _defaultScope(
    String location,
    Set<SearchScope> permitted,
  ) {
    if (location.startsWith('/offers') || location == Paths.index) {
      if (permitted.contains(SearchScope.offers)) return SearchScope.offers;
    }
    if (permitted.contains(SearchScope.clients)) return SearchScope.clients;

    return SearchScope.offers;
  }
}
