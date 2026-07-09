# Flutter test idioms (apps/loans + packages)

Verified 2026-07-07. Dev deps: `bloc_test: ^9.1.6`, `mocktail: ^1.0.3`,
`very_good_analysis: ^6.0.0` (`apps/loans/pubspec.yaml`).

## Commands

```bash
cd /Users/deibeeed/Projects/AnaheimTechnologies/finstack/apps/loans
fvm flutter test --coverage --test-randomize-ordering-seed random  # canonical
fvm flutter test test/features/chat/chat_bloc_test.dart            # one file
genhtml coverage/lcov.info -o coverage/                            # HTML report

# A package's own tests (run from the package dir):
cd ../../packages/core/chat_repository && fvm flutter test
```

Always `fvm flutter`, never bare `flutter` (apps/loans/CLAUDE.md). Randomized
ordering is part of the canonical command — tests must not depend on order or
on state leaked by a previous test.

## The `.withDependencies(...)` constructor seam

Problem: most concrete repositories (`ReviewRepository`, `AddressRepository`,
`CompanyRepository`, `SettingsRepository`, `UserLoanViewRepository`, ...) are
`final class` → mocktail cannot subclass them
(`invalid_use_of_type_outside_library`).

Solution pattern (canonical: `lib/features/reviews/bloc/reviews_bloc.dart`):

```dart
/// Production path — used by DI. Delegates to the seam.
ReviewsBloc(BuildContext context)
    : this.withDependencies(
        reviewRepository: context.read<ReviewRepository>(),
        authService: AuthenticationService.instance,
      );

/// Test seam. Repository typed as the mockable BaseRepository interface.
ReviewsBloc.withDependencies({
  required this.reviewRepository,   // BaseRepository<Review>
  required this.authService,
}) : super(const ReviewsState()) { ... }
```

Two seam variants (documented `apps/loans/MEMORY.md:406`):
- Bloc only calls `BaseRepository<T>` methods on the dep → type the field as
  `BaseRepository<T>` (mockable).
- Bloc calls a concrete-only method (e.g. `AddressRepository.getByDataType`)
  or passes the repo to something needing the concrete type → keep the field
  concrete but make it an **optional nullable** seam param, guarded with `!`
  at call sites the tests never reach.

Rules:
- The default `BuildContext` constructor is the production path. Never call
  `withDependencies` from app code; never change production behavior to make a
  test pass.
- Seams exist in 8 blocs as of 2026-07-07: `authentication_bloc`,
  `bank_details_bloc`, `chat_bloc`, `conversations_bloc`,
  `payment_submission_bloc`, `registration_bloc`, `reviews_bloc`, `user_bloc`.
  `loans_bloc` and `payment_bloc` have NO seam yet (they still bind
  `AuthenticationService.instance` in ctors) — adding seams there is part of
  the phantom follow-up loooans#134 (to be refiled on finstack; see
  `finstack-roadmap-and-frontier`).

## blocTest + mocktail shape

From `test/features/reviews/bloc/reviews_bloc_test.dart` (copy this shape):

```dart
class _MockReviewRepository extends Mock implements BaseRepository<Review> {}
class _MockAuthenticationService extends Mock implements AuthenticationService {}

setUpAll(() => registerFallbackValue(_review()));   // for any() on custom types

setUp(() {
  repository = _MockReviewRepository();
  authService = _MockAuthenticationService();
  when(() => authService.company).thenReturn(company);  // stub getters
});

ReviewsBloc build() => ReviewsBloc.withDependencies(
      reviewRepository: repository, authService: authService);

blocTest<ReviewsBloc, ReviewsState>(
  'loads reviews scoped by the company provider_id',
  setUp: () => when(() => repository.load(
        statements: any(named: 'statements'),
        limit: any(named: 'limit'),
        page: any(named: 'page'),
        reset: any(named: 'reset'),
      )).thenAnswer((_) async => [_review()]),
  build: build,
  act: (bloc) => bloc.add(LoadCompanyReviewsEvent()),
  expect: () => [
    const ReviewsState(status: ReviewsStatus.loading),
    isA<ReviewsState>().having((s) => s.status, 'status', ReviewsStatus.loaded),
  ],
  verify: (_) {
    final captured = verify(() => repository.load(
          statements: captureAny(named: 'statements'),
          limit: any(named: 'limit'),
          page: any(named: 'page'),
          reset: any(named: 'reset'),
        )).captured.single as List<QueryStatement>;
    expect(captured.single.field, 'provider_id');
  },
);
```

Idioms to keep: private `_Mock*` classes per test file; small factory helpers
for models (`_review(...)`); `isA<State>().having(...)` for partial state
asserts; `captureAny(named:)` to assert the Firestore query the bloc built.

## Widget tests

Use the `pumpApp` extension (`test/helpers/pump_app.dart`) — wraps the widget
in `MaterialApp` with the app's `AppLocalizations` delegates:

```dart
await tester.pumpApp(ReviewResponseDialog(...));
```

Good examples: `test/features/reviews/widget/review_response_dialog_test.dart`,
`test/features/payments/widget/submit_payment_dialog_test.dart`,
`test/features/chat/chat_room_screen_test.dart`.
There are NO golden tests (`matchesGoldenFile` count is 0 repo-wide) — don't
introduce them casually; they need infra decisions (finstack#41).

## Where tests exist today (2026-07-07)

App (`apps/loans/test/`, 28 files, 76 tests, all green): chat (7 files),
reviews (3), registration (2), users (2), bank_details (2), payments (2),
payment_center (1), set_password (2), products widget (1), authentication (1),
services (2: `loan_calculation_service_test.dart`,
`payment_confirmation_service_test.dart`), plus VGV counter scaffold
(`test/counter/`, `test/app/view/app_test.dart` — leftover boilerplate, ignore).
Untested hot spots: `loans_bloc`, `product_bloc`, `payment_bloc`,
`payment_center_bloc` (only the confirm path has a test), most screens.

Packages (test files per package): `chat_repository` 12, `user_repository` 4,
`review_repository` 2, `payment_repository` 2, `loooans_helpers` 2
(one is the collection-prefix invariant test,
`test/base_firestore_service_test.dart`), all others 1 VGV scaffold test.

## Known pre-existing failures (do not chase)

`packages/core/address_repository/test/src/address_repository_test.dart` and
`packages/core/bank_details_repository/test/src/bank_details_repository_test.dart`
are VGV scaffolds that call `AddressRepository()` / `BankDetailsRepository()` —
Firestore-backed constructors — without `Firebase.initializeApp()`, so they
throw. Pre-existing on `develop` (`apps/loans/MEMORY.md:344`).

Invariants: exactly these two packages fail, with exactly that failure mode;
everything else is green. Any deviation in either direction is caused by your
change. Proper fix (open, unclaimed): delete the scaffolds or refactor the
repos for injectable Firestore — a small hardening task, coordinate via
`finstack-change-control`.

## Analyzer discipline

CI runs no analyze (verified). Locally, raw `fvm flutter analyze` includes
`build/ios/SourcePackages/checkouts/**` noise after an iOS build — thousands of
phantom errors from flutterfire example code. Source-only baseline 2026-07-07:
0 errors / 10 warnings / 136 infos. Use
`../scripts/analyze-source-only.sh`; gate on 0 source errors and no new issues
from your diff.
