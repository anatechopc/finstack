# Penalties part 3: Application (finstack) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Charge penalties when an installment is confirmed late, measured from a collection date, through every confirmation path the app has; let the provider waive with a reason; show the running penalty on unpaid rows; print penalties on the statement of account.

**Architecture:** One pure decision (`resolveLateness`, in the schedule package) feeds one row-mutating helper (`PaymentConfirmationService.applyLateness`) that all four confirmation sites call: the client-detail `PaymentBloc`, the Payment Center's single and bulk-overdue handlers, and the borrower-submission `confirm()`. One shared form section (`PaymentPenaltySection`) registers `collected_at`, `waive_penalty`, `waive_reason` in whichever `FormBuilder` dialog hosts it. No Go change: the schedule trigger ignores the new fields (spec D10).

**Tech Stack:** Flutter 3.44.9 via fvm, flutter_bloc, flutter_form_builder, mocktail, `two_dimensional_scrollables` TableView, `pdf`.

**Spec:** `docs/superpowers/specs/2026-09-04-penalties-design.md` sections 5, 6, 7.4, 7.5, 7.7 (amended by Task 8 of this plan).

## Global Constraints

- Branch `feat/penalties-72-application`, stacked on `feat/penalties-72-definitions` (finstack PR #109). Worktree: `finstack/.claude/worktrees/penalties-72-app`. Never touch `master`, never commit on another branch: run `git rev-parse --abbrev-ref HEAD` before every commit and stop if it is not `feat/penalties-72-application`.
- Commit with an explicit identity: `git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit ...`. Conventional Commits, body states symptom → cause → fix, trailers `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ`.
- Running a package test suite rewrites its `analysis_options.yaml` (adds `- build/**`). Before every commit run `git checkout -- 'packages/core/*/analysis_options.yaml' 'packages/loans/*/analysis_options.yaml'` and never stage those files.
- Analyzer gate: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` from the worktree root. Baseline on this branch: 0 errors / 10 warnings / 137 infos. App-only baseline `cd apps/loans && fvm flutter analyze`: 147 issues. "Clean" means no new diagnostics.
- Always `fvm flutter` / `fvm dart`, never bare `flutter`. `*.g.dart` are gitignored; if a package model changes (none planned here) run `packages/build_models.sh`.
- Do not use `AuthenticationService.instance` inside BLoCs; use the injected `authService` field. Widgets may keep using `AuthenticationService.instance` where the surrounding file already does.
- Percentage base is the row's amount due: `amortization` for term rows, `outstandingBalance` for open-term rows (spec D7). Per-installment cadence uses `termDaysOf(loan.term)` (spec 4.1).
- `paid_late` is written only when the collection date is after the due date on a loan whose snapshot has `allowLatePayments == false` (spec section 6).
- A waive needs a non-empty reason; the helper throws otherwise (spec D6).
- Ticket references must carry the repo: `loooans#72`, `loooans#71`, `loooans#78` (finstack#72 is unrelated).
- Payment Center and client-detail dialogs use single-quoted Dart strings, `AppWidgets.*` helpers, and `AppColors.*` from `lib/utils/screen_helpers.dart`.

---

## File Structure

| File | Responsibility |
|------|----------------|
| `packages/loans/loan_schedule_repository/lib/src/penalty_calculator.dart` (modify) | Add `LatenessResult` and `resolveLateness`: the pure decision, no row mutation. |
| `packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart` (modify) | `resolveLateness` cases. |
| `apps/loans/lib/services/payment_confirmation_service.dart` (modify) | `applyLateness` writes the six row fields and returns the status; `confirm()` takes the collection date and waive. Replaces `scheduleStatusForConfirmation`. |
| `apps/loans/test/services/payment_confirmation_service_test.dart` (modify) | `applyLateness` unit cases. |
| `apps/loans/test/features/payment_center/payment_center_confirm_test.dart` (modify) | `confirm()` late path writes days late and penalty. |
| `apps/loans/lib/features/loans/bloc/payment_event.dart`, `payment_bloc.dart` (modify) | Client-detail teller path: event fields, `makePayment` params, handler calls `applyLateness`. |
| `apps/loans/lib/features/payment_center/bloc/payment_center_event.dart`, `payment_center_bloc.dart` (modify) | Payment Center single, bulk overdue, and submission-confirm paths. |
| `apps/loans/lib/features/users/widget/client_detail/client_detail_schedule_item.dart` (modify) | Red penalty line under the amount-due cell; new `Loan? loan` param. |
| `apps/loans/lib/features/users/widget/client_detail/client_detail_loan_body.dart` (modify) | Passes `loan: selectedLoan` to the row widget; review dialog gains the section (Task 6). |
| `apps/loans/lib/features/products/screen/loan_schedule_widget.dart` (modify) | Borrower table cell and list tile gain the red line; `Loan? loan`. |
| `apps/loans/lib/features/loans/screens/loan_details.dart` (modify) | Passes `loan` to both schedule renderers. |
| `apps/loans/lib/widgets/form_widgets.dart`, `app_widgets.dart` (modify) | `defaultFormBuilderDatePicker` gains `initialValue` and `onChanged`. |
| `apps/loans/lib/widgets/payment_penalty_section.dart` (create) | Shared section: collection date, breakdown across one or many schedules, waive + reason. |
| `apps/loans/test/widgets/payment_penalty_section_test.dart` (create) | Widget test for the section. |
| `apps/loans/lib/features/users/widget/client_detail/client_detail_dialogs.dart` (modify) | Client-detail make-payment dialog hosts the section; three `makePayment` calls forward the values. |
| `apps/loans/lib/features/payment_center/widget/payment_center_dialogs.dart` (modify) | Payment Center single and overdue dialogs host the section; six calls forward the values. |
| `apps/loans/lib/features/payment_center/model/pending_submission.dart` (modify) | Carries `loan` and `schedules` so the confirm dialog can preview. |
| `apps/loans/lib/features/payment_center/widget/pending_submission_section.dart` (modify) | Confirm opens a dialog with the section instead of confirming directly. |
| `apps/loans/lib/features/reports/models/soa_entry.dart` (modify) | `penalty` per entry. |
| `apps/loans/lib/features/reports/bloc/reports_bloc_extension_soa.dart` (modify) | Fills `penalty`; appends `Penalties` to `additionalCharges`. |
| `apps/loans/lib/utils/constants.dart` (modify) | `'Penalty'` header appended last. |
| `apps/loans/lib/features/loans/screens/statement_of_account_screen.dart` (modify) | Column 8 renders the penalty; last-column hooks use the header count. |
| `apps/loans/lib/utils/pdf_generator_build_soa.dart` (modify) | Penalty cell per row. |
| `docs/superpowers/specs/2026-09-04-penalties-design.md`, `apps/loans/MEMORY.md` (modify) | Spec amendment and session memory. |

Scope switch decided by the owner: **Tasks 5 and 6 are the "date and waive at every site" option.** If the owner picks the "client-detail dialog only" option, skip Tasks 5 and 6; the other sites still charge through `applyLateness` with `collectedAt = now` (teller paths) or `payment.createdAt` (borrower submissions) and no waive.

---

### Task 1: `resolveLateness`, `applyLateness`, and `confirm()` with a collection date

**Files:**
- Modify: `packages/loans/loan_schedule_repository/lib/src/penalty_calculator.dart` (append after `previewPenalty`, line 109)
- Test: `packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart` (append a group)
- Modify: `apps/loans/lib/services/payment_confirmation_service.dart`
- Test: `apps/loans/test/services/payment_confirmation_service_test.dart` (rewrite)
- Test: `apps/loans/test/features/payment_center/payment_center_confirm_test.dart` (fix the `sched()` helper, add two tests)

**Interfaces:**
- Consumes: `calculateDaysLate`, `computePenalties`, `PenaltyResult`, `termDaysOf`, `Loan.allowLatePayments`, `Loan.penalties`, `Loan.term`, `LoanSchedule.collectedAt/daysLate/penalty/penalties/penaltyWaivedBy/penaltyWaiveReason` (all on the definitions branch).
- Produces:
  ```dart
  final class LatenessResult { final int daysLate; final bool isLate; final PenaltyResult penalties; }
  LatenessResult resolveLateness({required LoanSchedule schedule, required Loan loan, required DateTime collectedAt});
  // apps/loans/lib/services/payment_confirmation_service.dart
  static LoanStatus PaymentConfirmationService.applyLateness({required LoanSchedule schedule, required Loan loan, required DateTime collectedAt, required String actorId, bool waivePenalty = false, String? waiveReason});
  Future<void> PaymentConfirmationService.confirm({required Payment payment, required String confirmedById, DateTime? collectedAt, bool waivePenalty = false, String? waiveReason});
  ```
  `scheduleStatusForConfirmation` is removed (its only callers were `confirm()` and its test).

- [ ] **Step 1: Write the failing package tests**

Append inside `main()` of `packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart`, after the last existing group. The file already declares `daily100` and `monthly2pct` at the top of `main()`. If the `previewPenalty` group declares `schedule(...)`/`loan(...)` helpers locally, hoist them to the top of `main()` so both groups share them; if they do not exist, add these at the top of `main()` after the penalty constants:

```dart
  LoanSchedule schedule({
    LoanStatus status = LoanStatus.not_paid,
    bool isOpenTerm = false,
  }) =>
      LoanSchedule()
        ..id = 's1'
        ..loanId = 'l1'
        ..status = status
        ..dueAt = DateTime(2026, 8, 15)
        ..amortization = 5000
        ..outstandingBalance = 20000
        ..isOpenTerm = isOpenTerm;

  Loan loan({
    List<Penalty> penalties = const [daily100],
    bool allowLatePayments = false,
    String term = '1m',
  }) =>
      Loan()
        ..id = 'l1'
        ..term = term
        ..penalties = List<Penalty>.of(penalties)
        ..allowLatePayments = allowLatePayments;
```

Then the group:

```dart
  group('resolveLateness', () {
    test('on time: not late, zero days, no penalties', () {
      final result = resolveLateness(
        schedule: schedule(),
        loan: loan(),
        collectedAt: DateTime(2026, 8, 15),
      );

      expect(result.isLate, false);
      expect(result.daysLate, 0);
      expect(result.penalties.total, 0);
    });

    test('late: days counted, penalties on amortization', () {
      final result = resolveLateness(
        schedule: schedule(),
        loan: loan(penalties: const [daily100, monthly2pct]),
        collectedAt: DateTime(2026, 9, 3),
      );

      expect(result.isLate, true);
      expect(result.daysLate, 19);
      expect(result.penalties.total, 2000);
    });

    test('open-term row uses the outstanding balance as the base', () {
      final result = resolveLateness(
        schedule: schedule(isOpenTerm: true),
        loan: loan(penalties: const [monthly2pct]),
        collectedAt: DateTime(2026, 8, 20),
      );

      expect(result.penalties.total, 400);
    });

    test('allow late payments: days recorded, not late, no penalty', () {
      final result = resolveLateness(
        schedule: schedule(),
        loan: loan(allowLatePayments: true),
        collectedAt: DateTime(2026, 9, 3),
      );

      expect(result.isLate, false);
      expect(result.daysLate, 19);
      expect(result.penalties.total, 0);
    });

    test('late with no penalties on the loan: late, nothing to charge', () {
      final result = resolveLateness(
        schedule: schedule(),
        loan: loan(penalties: const []),
        collectedAt: DateTime(2026, 9, 3),
      );

      expect(result.isLate, true);
      expect(result.penalties.total, 0);
    });

    test('ignores the row status, unlike previewPenalty', () {
      final result = resolveLateness(
        schedule: schedule(status: LoanStatus.paid_on_time),
        loan: loan(),
        collectedAt: DateTime(2026, 8, 16),
      );

      expect(result.isLate, true);
      expect(result.penalties.total, 100);
    });
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `cd packages/loans/loan_schedule_repository && fvm flutter test test/penalty_calculator_test.dart; cd -`

Expected: compile error, `resolveLateness` undefined.

- [ ] **Step 3: Add `resolveLateness`**

Append to `packages/loans/loan_schedule_repository/lib/src/penalty_calculator.dart`:

```dart
/// The confirmation-time decision for one installment.
final class LatenessResult {
  const LatenessResult({
    required this.daysLate,
    required this.isLate,
    required this.penalties,
  });

  /// Calendar days after the due date, recorded even when [isLate] is false.
  final int daysLate;

  /// True when collected after the due date on a loan that does not allow
  /// late payments. Drives the paid_late status.
  final bool isLate;

  /// Empty unless [isLate].
  final PenaltyResult penalties;
}

/// Decide lateness and penalties for a payment collected on [collectedAt].
/// Unlike [previewPenalty] this ignores the row's current status, because
/// the caller is about to set it.
LatenessResult resolveLateness({
  required LoanSchedule schedule,
  required Loan loan,
  required DateTime collectedAt,
}) {
  final daysLate = calculateDaysLate(
    dueAt: schedule.dueAt,
    collectedAt: collectedAt,
  );
  final isLate = daysLate > 0 && !loan.allowLatePayments;

  return LatenessResult(
    daysLate: daysLate,
    isLate: isLate,
    penalties: isLate
        ? computePenalties(
            amountDue: schedule.isOpenTerm
                ? schedule.outstandingBalance
                : schedule.amortization,
            penalties: loan.penalties,
            daysLate: daysLate,
            termDays: termDaysOf(loan.term),
          )
        : PenaltyResult.none,
  );
}
```

- [ ] **Step 4: Run the package tests**

Run: `cd packages/loans/loan_schedule_repository && fvm flutter test test/penalty_calculator_test.dart; cd -`

Expected: all PASS. Then `git checkout -- 'packages/loans/*/analysis_options.yaml'`.

- [ ] **Step 5: Write the failing service tests**

Replace the whole of `apps/loans/test/services/payment_confirmation_service_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/services/payment_confirmation_service.dart';
import 'package:loooans_helpers/data_helpers.dart';

void main() {
  const daily100 = Penalty(
    id: 'p1',
    name: 'Late fee',
    amount: 100,
    frequency: PenaltyFrequency.daily,
  );

  LoanSchedule row() => LoanSchedule()
    ..id = 's1'
    ..loanId = 'l1'
    ..status = LoanStatus.not_paid
    ..dueAt = DateTime(2026, 8, 15)
    ..amortization = 5000
    ..outstandingBalance = 5000
    ..isOpenTerm = false;

  Loan loan({
    bool allowLate = false,
    List<Penalty> penalties = const [daily100],
  }) =>
      Loan()
        ..id = 'l1'
        ..term = '1m'
        ..penalties = List<Penalty>.of(penalties)
        ..allowLatePayments = allowLate;

  group('PaymentConfirmationService.applyLateness', () {
    test('on time: paid_on_time, zero penalty, no snapshot', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 15),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_on_time);
      expect(s.collectedAt, DateTime(2026, 8, 15));
      expect(s.daysLate, 0);
      expect(s.penalty, 0);
      expect(s.penalties, isEmpty);
      expect(s.penaltyWaivedBy, isNull);
    });

    test('late: paid_late, penalty charged, definitions snapshotted', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 18),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_late);
      expect(s.daysLate, 3);
      expect(s.penalty, 300);
      expect(s.penalties.single.id, 'p1');
    });

    test('allow late payments: paid_on_time but days late recorded', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(allowLate: true),
        collectedAt: DateTime(2026, 8, 18),
        actorId: 'teller-1',
      );
      expect(status, LoanStatus.paid_on_time);
      expect(s.daysLate, 3);
      expect(s.penalty, 0);
    });

    test('waive zeroes the charge and records who and why', () {
      final s = row();
      PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 18),
        actorId: 'teller-1',
        waivePenalty: true,
        waiveReason: '  goodwill  ',
      );
      expect(s.penalty, 0);
      expect(s.penaltyWaivedBy, 'teller-1');
      expect(s.penaltyWaiveReason, 'goodwill');
      expect(s.penalties.single.id, 'p1');
    });

    test('waive without a reason throws before touching the row', () {
      final s = row();
      expect(
        () => PaymentConfirmationService.applyLateness(
          schedule: s,
          loan: loan(),
          collectedAt: DateTime(2026, 8, 18),
          actorId: 'teller-1',
          waivePenalty: true,
          waiveReason: ' ',
        ),
        throwsException,
      );
      expect(s.collectedAt, isNull);
    });

    test('waive on an on-time row is a no-op, no reason needed', () {
      final s = row();
      final status = PaymentConfirmationService.applyLateness(
        schedule: s,
        loan: loan(),
        collectedAt: DateTime(2026, 8, 15),
        actorId: 'teller-1',
        waivePenalty: true,
      );
      expect(status, LoanStatus.paid_on_time);
      expect(s.penaltyWaivedBy, isNull);
    });
  });

  group('PaymentConfirmationService.revertedStatus', () {
    test('overdue when dueAt is past, else not_paid', () {
      final past = DateTime.now().subtract(const Duration(days: 1));
      final future = DateTime.now().add(const Duration(days: 1));
      expect(
        PaymentConfirmationService.revertedStatus(dueAt: past),
        LoanStatus.not_paid_overdue,
      );
      expect(
        PaymentConfirmationService.revertedStatus(dueAt: future),
        LoanStatus.not_paid,
      );
    });
  });
}
```

In `apps/loans/test/features/payment_center/payment_center_confirm_test.dart`, `resolveLateness` reads `isOpenTerm`, `amortization`, and `outstandingBalance`, which are `late` fields the current helper never sets. Change the helper to:

```dart
  LoanSchedule sched() => LoanSchedule()
    ..id = 'sched-1'
    ..loanId = 'loan-1'
    ..status = LoanStatus.payment_submitted
    ..dueAt = DateTime.now().add(const Duration(days: 5))
    ..amortization = 5000
    ..outstandingBalance = 5000
    ..isOpenTerm = false;
```

Add `import 'package:loooans_helpers/data_helpers.dart';` and these two tests after `'confirm sets payment confirmed + schedule paid_on_time'`:

```dart
  test('confirm on a late submission writes days late and the penalty',
      () async {
    when(() => schedules.get(id: any(named: 'id'))).thenAnswer(
      (_) async =>
          sched()..dueAt = DateTime.now().subtract(const Duration(days: 3)),
    );
    when(() => loans.get(id: any(named: 'id'))).thenAnswer(
      (_) async => Loan()
        ..id = 'loan-1'
        ..period = 1
        ..term = '1m'
        ..penalties = [
          const Penalty(
            id: 'p1',
            name: 'Late fee',
            amount: 100,
            frequency: PenaltyFrequency.daily,
          ),
        ],
    );

    // Default collection date is when the borrower submitted (now).
    await svc.confirm(payment: pay(), confirmedById: 'lender-1');

    final s = verify(() => schedules.update(data: captureAny(named: 'data')))
        .captured
        .single as LoanSchedule;
    expect(s.status, LoanStatus.paid_late);
    expect(s.daysLate, 3);
    expect(s.penalty, 300);
    expect(s.collectedAt, isNotNull);
  });

  test('confirm with an explicit collection date on the due date is on time',
      () async {
    final due = DateTime.now().subtract(const Duration(days: 3));
    when(() => schedules.get(id: any(named: 'id')))
        .thenAnswer((_) async => sched()..dueAt = due);

    await svc.confirm(
      payment: pay(),
      confirmedById: 'lender-1',
      collectedAt: due,
    );

    final s = verify(() => schedules.update(data: captureAny(named: 'data')))
        .captured
        .single as LoanSchedule;
    expect(s.status, LoanStatus.paid_on_time);
    expect(s.penalty, 0);
  });
```

- [ ] **Step 6: Run to verify failure**

Run: `cd apps/loans && fvm flutter test test/services/payment_confirmation_service_test.dart test/features/payment_center/payment_center_confirm_test.dart; cd -`

Expected: compile error, `applyLateness` undefined / `collectedAt` not a parameter.

- [ ] **Step 7: Implement in the service**

In `apps/loans/lib/services/payment_confirmation_service.dart` (which already imports `loooans_helpers/data_helpers.dart`), replace `scheduleStatusForConfirmation` (lines 20–29) with:

```dart
  /// Applies the collection-date rule to [schedule] in place and returns the
  /// status to persist. Every confirmation path (client-detail teller flow,
  /// Payment Center single and bulk-overdue flows, borrower-submission
  /// confirm) routes through here so "late" means one thing app-wide
  /// (loooans#71, loooans#72, loooans#78).
  ///
  /// Throws before touching the row when [waivePenalty] is set without a
  /// reason and there is something to waive.
  static LoanStatus applyLateness({
    required LoanSchedule schedule,
    required Loan loan,
    required DateTime collectedAt,
    required String actorId,
    bool waivePenalty = false,
    String? waiveReason,
  }) {
    final lateness = resolveLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt,
    );
    final waived = waivePenalty && lateness.penalties.total > 0;
    final reason = waiveReason?.trim() ?? '';

    if (waived && reason.isEmpty) {
      throw Exception('A reason is required to waive penalties');
    }

    schedule
      ..collectedAt = collectedAt
      ..daysLate = lateness.daysLate
      ..penalties = lateness.isLate ? List<Penalty>.of(loan.penalties) : []
      ..penalty = waived ? 0 : lateness.penalties.total
      ..penaltyWaivedBy = waived ? actorId : null
      ..penaltyWaiveReason = waived ? reason : null;

    return lateness.isLate ? LoanStatus.paid_late : LoanStatus.paid_on_time;
  }
```

Replace `confirm` (lines 39–57) with:

```dart
  /// Confirm a borrower-submitted [payment]: persist the confirmed payment,
  /// mark its schedule paid, and advance the loan status to match.
  ///
  /// [collectedAt] defaults to when the borrower submitted the transfer, not
  /// when a teller got round to confirming it (loooans#71).
  Future<void> confirm({
    required Payment payment,
    required String confirmedById,
    DateTime? collectedAt,
    bool waivePenalty = false,
    String? waiveReason,
  }) async {
    final schedule =
        await loanScheduleRepository.get(id: payment.loanScheduleId);
    final loan = await loanRepository.get(id: schedule.loanId);

    // Decided first so a missing waive reason aborts the whole confirmation.
    final status = applyLateness(
      schedule: schedule,
      loan: loan,
      collectedAt: collectedAt ?? payment.createdAt,
      actorId: confirmedById,
      waivePenalty: waivePenalty,
      waiveReason: waiveReason,
    );

    payment.markConfirmed(confirmedById: confirmedById);
    await paymentRepository.update(data: payment);

    schedule
      ..paidAt = DateTime.timestamp()
      ..paymentId = payment.id
      ..status = status;
    await loanScheduleRepository.update(data: schedule);

    await _advanceLoanStatus(loan, schedule.status);
  }
```

In `reject`, change the last statement to:

```dart
    await _advanceLoanStatus(
      await loanRepository.get(id: schedule.loanId),
      schedule.status,
    );
```

Change `_advanceLoanStatus` to take the loan instead of loading it:

```dart
  Future<void> _advanceLoanStatus(Loan loan, LoanStatus status) async {
    var newStatus = status;

    // A fixed-term loan auto-completes once every scheduled payment is paid, so
    // the borrower can review and the pay buttons hide. (This advance runs
    // AFTER the just-paid schedule is persisted, so the count is correct.)
    if (loan.period != 0 &&
        _fixedTermFullyPaid(loan, await _loadLoanSchedules(loan.id))) {
      newStatus = LoanStatus.completed;
    }

    await loanRepository.update(
      data: loan..status = newStatus,
      updateView: true,
    );
  }
```

`grep -n "scheduleStatusForConfirmation" apps/loans/lib/services/payment_confirmation_service.dart` must print nothing afterwards (fix any doc comment that still names it).

- [ ] **Step 8: Run the tests**

Run: `cd apps/loans && fvm flutter test test/services/payment_confirmation_service_test.dart test/features/payment_center/payment_center_confirm_test.dart; cd -`

Expected: all PASS (existing `confirm`/`reject`/`completeLoanIfFullyPaid` tests included).

- [ ] **Step 9: Analyze and commit**

Run: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh`

Expected: 0 errors, no new warnings/infos versus the baseline. `grep -rn "scheduleStatusForConfirmation" apps/loans packages --include=*.dart` prints nothing.

```bash
git checkout -- 'packages/core/*/analysis_options.yaml' 'packages/loans/*/analysis_options.yaml'
git rev-parse --abbrev-ref HEAD   # must print feat/penalties-72-application
git add packages/loans/loan_schedule_repository/lib/src/penalty_calculator.dart packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart apps/loans/lib/services/payment_confirmation_service.dart apps/loans/test/services/payment_confirmation_service_test.dart apps/loans/test/features/payment_center/payment_center_confirm_test.dart
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "feat(payments): one lateness rule from the collection date, with waive (loooans#72 part 3)" -m "Symptom: four places decided 'late' by comparing the due date with the wall clock, so a payment recorded a day after it was received was tagged late (loooans#71), allow-late loans were still tagged late (loooans#78), and no penalty could be charged (loooans#72).

Cause: the rule was copied inline into each handler and PaymentConfirmationService.scheduleStatusForConfirmation only took the due date.

Fix: resolveLateness (pure, loan_schedule_repository) decides days late, lateness, and penalties from the collection date against the loan snapshot; PaymentConfirmationService.applyLateness writes collected_at, days_late, penalty, penalties, and the waive fields onto the row and returns the status. confirm() takes the collection date (default: when the borrower submitted) and waive. The bloc call sites follow in the next commit." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 2: Every bloc confirmation path calls `applyLateness`

**Files:**
- Modify: `apps/loans/lib/features/loans/bloc/payment_event.dart:7-42`
- Modify: `apps/loans/lib/features/loans/bloc/payment_bloc.dart:85-133`
- Modify: `apps/loans/lib/features/payment_center/bloc/payment_center_event.dart:47-82` (`MakePaymentEvent`), `:84-118` (`MakeOverduePaymentEvent`), `:143-149` (`ConfirmSubmissionEvent`)
- Modify: `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart:623-677` (`makePayment` + lateness block), `:788-877` (`makeOverduePayment` + loop lateness), `:1205-1241` (`confirmSubmission` + handler)

**Interfaces:**
- Consumes: `PaymentConfirmationService.applyLateness` (Task 1); the blocs' injected `authService.user.id`.
- Produces: every event and public method below accepts `DateTime? collectedAt`, `bool waivePenalty = false`, `String? waiveReason`:
  - `PaymentBloc.makePayment(...)`, `PayLoanScheduleEvent(...)`
  - `PaymentCenterBloc.makePayment(...)`, `MakePaymentEvent(...)`
  - `PaymentCenterBloc.makeOverduePayment(...)`, `MakeOverduePaymentEvent(...)` (one date for all rows)
  - `PaymentCenterBloc.confirmSubmission(List<Payment> payments, {DateTime? collectedAt, bool waivePenalty = false, String? waiveReason})`, `ConfirmSubmissionEvent(...)`

- [ ] **Step 1: Client-detail event and bloc**

In `payment_event.dart`, add to `PayLoanScheduleEvent`'s constructor `this.collectedAt, this.waivePenalty = false, this.waiveReason,` and the fields (after `otpVerified`):

```dart
  /// When the money was actually received. Null means now.
  final DateTime? collectedAt;

  /// Provider chose to waive the computed penalty. Needs [waiveReason].
  final bool waivePenalty;
  final String? waiveReason;
```

and append `collectedAt, waivePenalty, waiveReason,` to `props`.

In `payment_bloc.dart`, add `import 'package:loooans/services/payment_confirmation_service.dart';`. In `makePayment` (line 85) add the three named parameters `DateTime? collectedAt, bool waivePenalty = false, String? waiveReason,` after `bool otpVerified = false,` and forward them to the event (`collectedAt: collectedAt, waivePenalty: waivePenalty, waiveReason: waiveReason,`).

In `_handlePayLoanScheduleEvent`, replace lines 126–133:

```dart
        final now = DateTime.now();
        var status = LoanStatus.payment_submitted;

        if (schedule.dueAt.toLocal().isBefore(now)) {
          status = LoanStatus.paid_late;
        } else {
          status = LoanStatus.paid_on_time;
        }
```

with:

```dart
        final status = PaymentConfirmationService.applyLateness(
          schedule: schedule,
          loan: loan,
          collectedAt: event.collectedAt ?? DateTime.now(),
          actorId: authService.user.id,
          waivePenalty: event.waivePenalty,
          waiveReason: event.waiveReason,
        );
```

- [ ] **Step 2: Payment Center single payment**

In `payment_center_event.dart`, give `MakePaymentEvent` the same three constructor params, fields, and `props` entries as Step 1. In `payment_center_bloc.dart` `makePayment` (line 623) add the three parameters and forward them. Replace lines 670–677 (the `now`/`status` block) with:

```dart
      final status = PaymentConfirmationService.applyLateness(
        schedule: schedule,
        loan: loan,
        collectedAt: event.collectedAt ?? DateTime.now(),
        actorId: authService.user.id,
        waivePenalty: event.waivePenalty,
        waiveReason: event.waiveReason,
      );
```

- [ ] **Step 3: Payment Center bulk overdue**

Give `MakeOverduePaymentEvent` the same three params/fields/props. In `makeOverduePayment` (line 788) add and forward them. In `_handleMakeOverduePaymentEvent`, directly after the self-managed check (line 829) add a pre-check so a bad waive cannot fail halfway through the loop:

```dart
      if (event.waivePenalty && (event.waiveReason?.trim().isEmpty ?? true)) {
        throw Exception('A reason is required to waive penalties');
      }
      final collectedAt = event.collectedAt ?? DateTime.now();
```

Replace lines 874–877:

```dart
        final now = DateTime.now();
        final status = schedule.dueAt.toLocal().isBefore(now)
            ? LoanStatus.paid_late
            : LoanStatus.paid_on_time;
```

with:

```dart
        final status = PaymentConfirmationService.applyLateness(
          schedule: schedule,
          loan: loan,
          collectedAt: collectedAt,
          actorId: authService.user.id,
          waivePenalty: event.waivePenalty,
          waiveReason: event.waiveReason,
        );
```

- [ ] **Step 4: Payment Center submission confirm**

Replace `ConfirmSubmissionEvent`:

```dart
final class ConfirmSubmissionEvent extends PaymentCenterEvent {
  const ConfirmSubmissionEvent({
    required this.payments,
    this.collectedAt,
    this.waivePenalty = false,
    this.waiveReason,
  });
  final List<Payment> payments;
  final DateTime? collectedAt;
  final bool waivePenalty;
  final String? waiveReason;

  @override
  List<Object?> get props => [payments, collectedAt, waivePenalty, waiveReason];
}
```

Replace `confirmSubmission` (line 1206):

```dart
  /// Confirm a borrower payment submission (all schedules under it).
  void confirmSubmission(
    List<Payment> payments, {
    DateTime? collectedAt,
    bool waivePenalty = false,
    String? waiveReason,
  }) =>
      add(
        ConfirmSubmissionEvent(
          payments: payments,
          collectedAt: collectedAt,
          waivePenalty: waivePenalty,
          waiveReason: waiveReason,
        ),
      );
```

In `_handleConfirmSubmission`, add the same pre-check as Step 3 directly after the self-managed check, and change the loop body to:

```dart
        await service.confirm(
          payment: payment,
          confirmedById: authService.user.id,
          collectedAt: event.collectedAt,
          waivePenalty: event.waivePenalty,
          waiveReason: event.waiveReason,
        );
```

- [ ] **Step 5: Analyze, test, commit**

Run: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` then `cd apps/loans && fvm flutter test; cd -`.

Expected: analyzer clean versus baseline (`grep -rn "isBefore(now)" apps/loans/lib/features/loans/bloc apps/loans/lib/features/payment_center/bloc` prints nothing); all app tests pass (the OTP tests build both blocs through `withDependencies` and must still compile).

```bash
git checkout -- 'packages/core/*/analysis_options.yaml' 'packages/loans/*/analysis_options.yaml'
git rev-parse --abbrev-ref HEAD
git add apps/loans/lib/features/loans/bloc/payment_event.dart apps/loans/lib/features/loans/bloc/payment_bloc.dart apps/loans/lib/features/payment_center/bloc/payment_center_event.dart apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "feat(payments): route all four confirmation paths through applyLateness" -m "Symptom: the client-detail teller flow, the Payment Center single and bulk-overdue flows, and the submission confirm each compared due_at with the wall clock, so the same loan could be penalized on one screen and not another.

Cause: the lateness rule was duplicated inline in each handler.

Fix: the events carry collectedAt, waivePenalty, and waiveReason; each handler calls PaymentConfirmationService.applyLateness with the loan snapshot. The bulk and submission loops validate the waive reason before the first write so a bad waive cannot fail halfway." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 3: Red penalty line on schedule rows (lender and borrower)

**Files:**
- Modify: `apps/loans/lib/features/users/widget/client_detail/client_detail_schedule_item.dart:13-29` (ctor), `:229-237` (amount-due cell)
- Modify: `apps/loans/lib/features/users/widget/client_detail/client_detail_loan_body.dart:89-95`, `:99-106`
- Modify: `apps/loans/lib/features/products/screen/loan_schedule_widget.dart:13-32` (ctor/fields), `:83-96` (`_list`), `:110-143` (`scheduleItem`), `:162-168` (table column 1)
- Modify: `apps/loans/lib/features/loans/screens/loan_details.dart:271-275`, `:392-400`

**Interfaces:**
- Consumes: `previewPenalty(schedule:, loan:)`, `calculateDaysLate`, `PenaltyResult.none` (package); `LoanSchedule.penalty`, `penaltyWaivedBy`; `AppColors.red2`; `toCurrency()`.
- Produces: `ClientDetailScheduleItem({..., Loan? loan})`; `LoanScheduleWidget({..., Loan? loan})`; `LoanScheduleWidget.scheduleItem(context, {required schedule, int index = 0, Loan? loan})`. Null loan means no penalty lines (offer previews).

- [ ] **Step 1: Lender row**

In `client_detail_schedule_item.dart`, add `this.loan,` to the constructor and the field:

```dart
  /// The loan the row belongs to. Null hides the running-penalty line.
  final Loan? loan;
```

Replace the amount-due cell (lines 229–237):

```dart
          Expanded(
            child: Text(
              _displayAmount(
                schedule.isOpenTerm
                    ? schedule.outstandingBalance
                    : schedule.amortization,
              ),
            ),
          ),
```

with:

```dart
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayAmount(
                    schedule.isOpenTerm
                        ? schedule.outstandingBalance
                        : schedule.amortization,
                  ),
                ),
                ..._penaltyLines(),
              ],
            ),
          ),
```

and add this method after `_displayAmount`:

```dart
  /// Running penalty for an unpaid row, or what was charged/waived on a paid
  /// one. Lines are 11px so the row keeps its height on one-line rows.
  List<Widget> _penaltyLines() {
    const style = TextStyle(color: AppColors.red2, fontSize: 11);
    final currentLoan = loan;
    final preview = currentLoan == null
        ? PenaltyResult.none
        : previewPenalty(schedule: schedule, loan: currentLoan);
    final daysLateNow = calculateDaysLate(
      dueAt: schedule.dueAt,
      collectedAt: DateTime.now(),
    );

    return [
      if (preview.total > 0)
        Text(
          '+ ${preview.total.toCurrency()} penalty · $daysLateNow days late',
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (schedule.penalty > 0)
        Text(
          '+ ${schedule.penalty.toCurrency()} penalty charged',
          style: style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      if (schedule.penaltyWaivedBy != null)
        const Text('penalty waived', style: TextStyle(fontSize: 11)),
    ];
  }
```

In `client_detail_loan_body.dart`, add `loan: selectedLoan,` to both `ClientDetailScheduleItem(` constructions (header at line 89 and rows at line 99).

- [ ] **Step 2: Borrower table and list tile**

In `loan_schedule_widget.dart`, add `this.loan,` to the constructor and the field:

```dart
  /// The loan these rows belong to. Null for offer previews, where there is
  /// no loan yet and no penalty can be shown.
  final Loan? loan;
```

Add `import 'package:loooans/utils/screen_helpers.dart';`.

In `_list()` pass `loan: loan,` to `scheduleItem`. Change `scheduleItem`'s signature to `static Widget scheduleItem(BuildContext context, {required LoanSchedule schedule, int index = 0, Loan? loan})` and add, after the `'Principal: ...'` `Text` inside the subtitle `Column` (line 137):

```dart
          ..._penaltyLines(schedule, loan),
```

Replace the table's `vicinity.column == 1` branch (lines 162–168) with:

```dart
      } else if (vicinity.column == 1) {
        defaultCellDisplay = Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(schedule.amortization.toCurrency()),
              ..._penaltyLines(schedule, loan),
            ],
          ),
        );
      }
```

Add this static helper next to `_statusLabel`:

```dart
  /// Running penalty on an unpaid row, or the charged amount on a paid one.
  static List<Widget> _penaltyLines(LoanSchedule schedule, Loan? loan) {
    const style = TextStyle(color: AppColors.red2, fontSize: 11);
    final preview = loan == null
        ? PenaltyResult.none
        : previewPenalty(schedule: schedule, loan: loan);

    return [
      if (preview.total > 0)
        Text('+ ${preview.total.toCurrency()} penalty', style: style),
      if (schedule.penalty > 0)
        Text('+ ${schedule.penalty.toCurrency()} penalty charged', style: style),
    ];
  }
```

Table rows are `FixedTableSpanExtent(48)`; a 14px line plus an 11px line plus the 8px vertical padding fits. If a run shows a bottom overflow on that cell, reduce the cell's `EdgeInsets.symmetric(vertical: 8)` to `vertical: 4` for column 1 only.

- [ ] **Step 3: Pass the loan from loan details**

In `loan_details.dart`, both blocks already hold `final loan = context.read<LoansBloc>().selectedLoan;`. Add `loan: loan,` to the `LoanScheduleWidget.scheduleItem(` call (line 271) and to the `LoanScheduleWidget(` construction (line 392).

- [ ] **Step 4: Analyze, check, commit**

Run: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh`

Expected: clean versus baseline.

Dev-flavor check (`cd apps/loans && fvm flutter run -d web-server --web-port 8090 --web-hostname localhost --target lib/main_development.dart --dart-define=ENVIRONMENT=development`): as a self-managed teller, open a client loan created after part 2 with penalties; an unpaid row whose due date has passed shows the red `+ ₱… penalty · N days late` line under the amount; rows not yet due and loans with "Allow late payments" show nothing. As the borrower, loan details show `+ ₱… penalty` under the amortization in both the compact list and the wide table.

```bash
git rev-parse --abbrev-ref HEAD
git add apps/loans/lib/features/users/widget/client_detail/client_detail_schedule_item.dart apps/loans/lib/features/users/widget/client_detail/client_detail_loan_body.dart apps/loans/lib/features/products/screen/loan_schedule_widget.dart apps/loans/lib/features/loans/screens/loan_details.dart
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "feat(loans): show the running penalty on overdue schedule rows" -m "Symptom: neither the collector nor the borrower could see what an overdue installment would cost if paid today.

Cause: penalties were only defined (part 2), never displayed on rows.

Fix: the lender row and the borrower table/list tile take the loan and print previewPenalty in red under the amount due, plus 'penalty charged' / 'penalty waived' on confirmed rows." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 4: `PaymentPenaltySection` and the client-detail make-payment dialog

**Files:**
- Modify: `apps/loans/lib/widgets/form_widgets.dart:254-265` (`defaultFormBuilderDatePicker`) and `apps/loans/lib/widgets/app_widgets.dart:224` (its forwarder)
- Create: `apps/loans/lib/widgets/payment_penalty_section.dart`
- Test: `apps/loans/test/widgets/payment_penalty_section_test.dart`
- Modify: `apps/loans/lib/features/users/widget/client_detail/client_detail_dialogs.dart:138-255` (dialog content), `:409-422`, `:500-511`, `:549-559` (the three `makePayment` calls)

**Interfaces:**
- Consumes: `resolveLateness` (Task 1); `PaymentBloc.makePayment(collectedAt:, waivePenalty:, waiveReason:)` (Task 2); `PenaltyLabels.amountLabel` (`lib/utils/extensions.dart`); `AppWidgets.defaultFormBuilderTextField`, `AppWidgets.defaultFormBuilderDatePicker`.
- Produces:
  ```dart
  class PaymentPenaltySection extends StatefulWidget {
    const PaymentPenaltySection({required List<LoanSchedule> schedules, required Loan loan, DateTime? initialCollectedAt, Key? key});
  }
  ```
  Registers form fields `collected_at` (DateTime), `waive_penalty` (bool), `waive_reason` (String) in the enclosing `FormBuilder`. `AppWidgets.defaultFormBuilderDatePicker` gains `DateTime? initialValue` and `ValueChanged<DateTime?>? onChanged`.

- [ ] **Step 1: Extend the date-picker helper**

In `form_widgets.dart` `defaultFormBuilderDatePicker`, add parameters `DateTime? initialValue,` and `ValueChanged<DateTime?>? onChanged,` and pass `initialValue: initialValue, onChanged: onChanged,` into the returned `FormBuilderDateTimePicker`. `AppWidgets.defaultFormBuilderDatePicker` in `app_widgets.dart:224` forwards to it; add the same two parameters there and forward them.

- [ ] **Step 2: Write the failing widget test**

Create `apps/loans/test/widgets/payment_penalty_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/widgets/payment_penalty_section.dart';
import 'package:loooans_helpers/data_helpers.dart';

import '../helpers/helpers.dart';

void main() {
  const daily100 = Penalty(
    id: 'p1',
    name: 'Late fee',
    amount: 100,
    frequency: PenaltyFrequency.daily,
  );

  LoanSchedule row(DateTime dueAt) => LoanSchedule()
    ..id = 's1'
    ..loanId = 'l1'
    ..status = LoanStatus.not_paid
    ..dueAt = dueAt
    ..amortization = 5000
    ..outstandingBalance = 5000
    ..isOpenTerm = false;

  Loan loan({bool allowLate = false}) => Loan()
    ..id = 'l1'
    ..term = '1m'
    ..penalties = [daily100]
    ..allowLatePayments = allowLate;

  late GlobalKey<FormBuilderState> key;

  setUp(() => key = GlobalKey<FormBuilderState>());

  Widget host({required List<LoanSchedule> schedules, required Loan loan}) {
    return Scaffold(
      body: SingleChildScrollView(
        child: FormBuilder(
          key: key,
          child: PaymentPenaltySection(
            schedules: schedules,
            loan: loan,
            initialCollectedAt: DateTime(2026, 9, 3),
          ),
        ),
      ),
    );
  }

  testWidgets('late row shows the penalty line, total, and waive control',
      (tester) async {
    await tester.pumpApp(
      host(schedules: [row(DateTime(2026, 8, 31))], loan: loan()),
    );

    expect(find.textContaining('Late fee'), findsOneWidget);
    expect(find.textContaining('× 3'), findsOneWidget);
    expect(find.text('Waive penalties'), findsOneWidget);
    expect(find.text('Waive reason'), findsNothing);
  });

  testWidgets('on-time row shows no penalty and no waive control',
      (tester) async {
    await tester.pumpApp(
      host(schedules: [row(DateTime(2026, 9, 3))], loan: loan()),
    );

    expect(find.textContaining('Late fee'), findsNothing);
    expect(find.text('Waive penalties'), findsNothing);
  });

  testWidgets('allow-late loan explains why nothing is charged',
      (tester) async {
    await tester.pumpApp(
      host(
        schedules: [row(DateTime(2026, 8, 31))],
        loan: loan(allowLate: true),
      ),
    );

    expect(find.textContaining('late payments allowed'), findsOneWidget);
    expect(find.text('Waive penalties'), findsNothing);
  });

  testWidgets('ticking waive reveals the reason field and saves the values',
      (tester) async {
    await tester.pumpApp(
      host(schedules: [row(DateTime(2026, 8, 31))], loan: loan()),
    );

    await tester.tap(find.text('Waive penalties'));
    await tester.pumpAndSettle();
    expect(find.text('Waive reason'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('waive_reason_field')),
      'goodwill',
    );
    key.currentState!.save();
    expect(key.currentState!.value['waive_penalty'], true);
    expect(key.currentState!.value['waive_reason'], 'goodwill');
    expect(key.currentState!.value['collected_at'], DateTime(2026, 9, 3));
  });

  testWidgets('many rows sum their penalties', (tester) async {
    await tester.pumpApp(
      host(
        schedules: [row(DateTime(2026, 8, 31)), row(DateTime(2026, 9, 1))],
        loan: loan(),
      ),
    );

    // 3 days × ₱100 + 2 days × ₱100 on top of 2 × ₱5,000.
    expect(find.textContaining('10,500.00'), findsOneWidget);
  });
}
```

If `toCurrency()` formats without the thousands separator, match the format the existing tests assert (grep `toCurrency` in `apps/loans/test`).

- [ ] **Step 3: Run to verify failure**

Run: `cd apps/loans && fvm flutter test test/widgets/payment_penalty_section_test.dart; cd -`

Expected: compile error, `payment_penalty_section.dart` missing.

- [ ] **Step 4: Write the section**

Create `apps/loans/lib/widgets/payment_penalty_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:gap/gap.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:loooans/utils/extensions.dart';
import 'package:loooans/utils/screen_helpers.dart';
import 'package:loooans/widgets/app_widgets.dart';

/// Collection date, live penalty breakdown, and waive controls for any
/// confirm-payment dialog. Registers `collected_at`, `waive_penalty`, and
/// `waive_reason` in the enclosing [FormBuilder]. Handles one installment or
/// many (bulk overdue, multi-schedule submissions) under a single date.
class PaymentPenaltySection extends StatefulWidget {
  const PaymentPenaltySection({
    required this.schedules,
    required this.loan,
    this.initialCollectedAt,
    super.key,
  });

  final List<LoanSchedule> schedules;
  final Loan loan;

  /// Defaults to now. Borrower submissions pass the submission time.
  final DateTime? initialCollectedAt;

  @override
  State<PaymentPenaltySection> createState() => _PaymentPenaltySectionState();
}

class _PaymentPenaltySectionState extends State<PaymentPenaltySection> {
  late DateTime _collectedAt = widget.initialCollectedAt ?? DateTime.now();
  bool _waive = false;

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final results = [
      for (final schedule in widget.schedules)
        (
          schedule: schedule,
          lateness: resolveLateness(
            schedule: schedule,
            loan: loan,
            collectedAt: _collectedAt,
          ),
        ),
    ];
    final amountDue = results.fold<double>(
      0,
      (sum, r) =>
          sum +
          (r.schedule.isOpenTerm
              ? r.schedule.outstandingBalance
              : r.schedule.amortization),
    );
    final penaltyTotal = results.fold<double>(
      0,
      (sum, r) => sum + r.lateness.penalties.total,
    );
    final maxDaysLate = results.fold<int>(
      0,
      (m, r) => r.lateness.daysLate > m ? r.lateness.daysLate : m,
    );
    final total = _waive ? amountDue : amountDue + penaltyTotal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppWidgets.defaultFormBuilderDatePicker(
          name: 'collected_at',
          label: 'Collection date',
          helperText: 'When the money was received. Lateness and penalties '
              'use this date, not today.',
          initialValue: _collectedAt,
          lastDate: DateTime.now(),
          validator: FormBuilderValidators.required(),
          onChanged: (value) {
            if (value != null) {
              setState(() => _collectedAt = value);
            }
          },
        ),
        const Gap(12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _row(
                widget.schedules.length == 1
                    ? 'Installment'
                    : '${widget.schedules.length} installments',
                amountDue.toCurrency(),
              ),
              for (final r in results)
                for (final line in r.lateness.penalties.lines)
                  _row(
                    '${line.penalty.name} · ${line.penalty.amountLabel} '
                    '× ${line.periods}',
                    line.amount.toCurrency(),
                    sub: true,
                  ),
              if (maxDaysLate > 0 && penaltyTotal == 0)
                _row(
                  loan.allowLatePayments
                      ? '$maxDaysLate days late · late payments allowed'
                      : '$maxDaysLate days late · no penalties on this loan',
                  '',
                  sub: true,
                ),
              const Divider(),
              _row('Total to collect', total.toCurrency(), bold: true),
            ],
          ),
        ),
        if (penaltyTotal > 0) ...[
          FormBuilderCheckbox(
            name: 'waive_penalty',
            initialValue: false,
            title: const Text('Waive penalties'),
            subtitle: const Text(
              'Records who waived and why on the installment.',
              style: TextStyle(fontSize: 10),
            ),
            activeColor: AppColors.black,
            checkColor: AppColors.white,
            onChanged: (value) => setState(() => _waive = value ?? false),
          ),
          if (_waive)
            AppWidgets.defaultFormBuilderTextField(
              key: const Key('waive_reason_field'),
              name: 'waive_reason',
              label: 'Waive reason',
              validator: FormBuilderValidators.required(),
            ),
        ],
      ],
    );
  }

  Widget _row(
    String label,
    String value, {
    bool sub = false,
    bool bold = false,
  }) {
    final style = TextStyle(
      fontSize: sub ? 12 : 14,
      color: sub ? AppColors.lightBlack : AppColors.black,
      fontWeight: bold ? FontWeight.w700 : null,
    );

    return Padding(
      padding: EdgeInsets.only(top: 3, bottom: 3, left: sub ? 12 : 0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
```

If `AppWidgets.defaultFormBuilderTextField` has no `key` parameter, wrap it in `KeyedSubtree(key: const Key('waive_reason_field'), child: ...)` and in the test find the `TextField` descendant of that key. Match its other parameters to the call at `client_detail_dialogs.dart:202-232`.

- [ ] **Step 5: Run the widget test**

Run: `cd apps/loans && fvm flutter test test/widgets/payment_penalty_section_test.dart; cd -`

Expected: all 5 PASS.

- [ ] **Step 6: Host it in the client-detail dialog**

In `client_detail_dialogs.dart`, add imports `package:loooans/widgets/payment_penalty_section.dart` and (if missing) `package:loooans/features/loans/bloc/loans_bloc.dart`. Inside `showMakePaymentDialog`, wrap the content `Column` (line 145) in a `SingleChildScrollView` so the taller dialog fits short windows:

```dart
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
```

and after the `Row` holding the two amount fields (closing at line 251) add:

```dart
                const Gap(16),
                PaymentPenaltySection(
                  schedules: [schedule],
                  loan: context.read<LoansBloc>().selectedLoan,
                ),
```

Add to each of the three `context.read<PaymentBloc>().makePayment(` calls (signature path line 409, OTP path line 500, force path line 549), after the existing arguments:

```dart
                                  collectedAt: key.currentState!
                                      .value['collected_at'] as DateTime?,
                                  waivePenalty: key.currentState!
                                          .value['waive_penalty'] as bool? ??
                                      false,
                                  waiveReason: key.currentState!
                                      .value['waive_reason'] as String?,
```

All three sit after `key.currentState?.saveAndValidate()`, so the required validator on `waive_reason` blocks a waive without a reason at the form level; `applyLateness` throws as the second guard.

- [ ] **Step 7: Analyze, walk through, commit**

Run: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` and `cd apps/loans && fvm flutter test; cd -`.

Expected: clean; all tests pass.

Dev-flavor walkthrough as a self-managed teller on an overdue installment of a loan with penalties:
1. Make payment: dialog shows Collection date (today), one line per penalty with `× periods`, Total to collect, and Waive penalties.
2. Set the collection date to the due date: penalty lines vanish, total equals the installment.
3. Back to today, tick Waive: total drops, Waive reason appears; confirm with it empty is blocked; enter a reason, confirm (force option is fine).
4. Firestore row: `status: paid_late`, `penalty: 0`, `penalty_waived_by` = your user id, `penalty_waive_reason` = the text, `collected_at` today, `penalties` = the loan's definitions.
5. Another overdue row, no waive: `penalty` equals the breakdown total, waive fields null.
6. On an "Allow late payments" loan: `N days late · late payments allowed`, no waive box, row written `paid_on_time`.

```bash
git rev-parse --abbrev-ref HEAD
git add apps/loans/lib/widgets/form_widgets.dart apps/loans/lib/widgets/app_widgets.dart apps/loans/lib/widgets/payment_penalty_section.dart apps/loans/test/widgets/payment_penalty_section_test.dart apps/loans/lib/features/users/widget/client_detail/client_detail_dialogs.dart
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "feat(payments): collection date, penalty breakdown, and waive in the make-payment dialog" -m "Symptom: a teller had no way to say when the money was received or to see and waive the penalty being charged.

Cause: the dialog only collected the two amounts.

Fix: shared PaymentPenaltySection (date picker, live breakdown across one or many rows, waive with a required reason) hosted in the client-detail make-payment dialog; all three confirm paths forward the values." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 5: Payment Center teller dialogs (single and bulk overdue)

*Option "date and waive at every site" only.*

**Files:**
- Modify: `apps/loans/lib/features/payment_center/widget/payment_center_dialogs.dart:47-158` (single dialog content), `:263-372` (overdue dialog content), `:473-483`, `:499-507`, `:541-549` (three `makeOverduePayment` calls), `:665-675`, `:701-709`, `:749-757` (three `makePayment` calls)

**Interfaces:**
- Consumes: `PaymentPenaltySection` (Task 4); `PaymentCenterBloc.makePayment/makeOverduePayment(collectedAt:, waivePenalty:, waiveReason:)` (Task 2).
- Produces: nothing new.

- [ ] **Step 1: Single-payment dialog**

Add `import 'package:loooans/widgets/payment_penalty_section.dart';`. In `showPaymentCenterPaymentDialog`, wrap the content `Column` (line 52) in a `SingleChildScrollView` exactly as in Task 4 Step 6, and after the amounts `Row` (closing at line 155) add:

```dart
                        const Gap(16),
                        PaymentPenaltySection(
                          schedules: [schedule],
                          loan: loan,
                        ),
```

In `_handleSignaturePayment` (line 665), `_handleOtpPayment` (line 701), and `_handleForcePayment` (line 749), add to the `makePayment(` call:

```dart
        collectedAt: key.currentState!.value['collected_at'] as DateTime?,
        waivePenalty:
            key.currentState!.value['waive_penalty'] as bool? ?? false,
        waiveReason: key.currentState!.value['waive_reason'] as String?,
```

- [ ] **Step 2: Bulk overdue dialog**

In `showOverduePaymentDialog`, wrap the content `Column` (line 268) the same way and after the amounts `Row` (closing at line 369) add:

```dart
                        const Gap(16),
                        PaymentPenaltySection(
                          schedules: overdueSchedules,
                          loan: loan,
                        ),
```

Add the same three arguments to the three `makeOverduePayment(` calls in `_handleOverduePaymentOption` (lines 473, 499, 541).

- [ ] **Step 3: Analyze, walk through, commit**

Run: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh`

Expected: clean.

Dev-flavor walkthrough in the Payment Center as a teller: single payment on an overdue row shows the same section as the client-detail dialog and writes the same fields; "Pay overdue" on a loan with two overdue rows shows `2 installments`, one penalty line per row, one collection date; after confirming, each row carries its own `days_late` and `penalty`.

```bash
git rev-parse --abbrev-ref HEAD
git add apps/loans/lib/features/payment_center/widget/payment_center_dialogs.dart
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "feat(payment-center): collection date and waive in the single and overdue payment dialogs" -m "Symptom: the Payment Center charged penalties (via applyLateness) without showing them or letting the teller pick the collection date.

Cause: the section only existed in the client-detail dialog.

Fix: host PaymentPenaltySection in both Payment Center dialogs; the six confirm calls forward the values. Bulk overdue applies one date to every row." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 6: Borrower-submission confirm dialogs (Payment Center card and client-detail review)

*Option "date and waive at every site" only.*

**Files:**
- Modify: `apps/loans/lib/features/payment_center/model/pending_submission.dart`
- Modify: `apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart:245-310` (`_loadPendingSubmissions`)
- Modify: `apps/loans/lib/features/payment_center/widget/pending_submission_section.dart:155-166` (Confirm button), plus a new dialog function
- Modify: `apps/loans/lib/features/users/widget/client_detail/client_detail_loan_body.dart:189-305` (`_showReviewPaymentDialog`, `_onConfirmFromReview`)

**Interfaces:**
- Consumes: `PaymentPenaltySection` (Task 4); `PaymentCenterBloc.confirmSubmission(payments, collectedAt:, waivePenalty:, waiveReason:)` and `PaymentConfirmationService.confirm(collectedAt:, waivePenalty:, waiveReason:)` (Tasks 1–2).
- Produces: `PendingSubmission({required submissionId, required payments, required Loan loan, required List<LoanSchedule> schedules, double? totalAmount})`; `Future<void> showConfirmSubmissionDialog(BuildContext context, {required PendingSubmission submission})` in `pending_submission_section.dart`.

- [ ] **Step 1: Carry loan and schedules on the submission**

Replace `PendingSubmission`:

```dart
import 'package:equatable/equatable.dart';
import 'package:loan_repository/loan_repository.dart';
import 'package:loan_schedule_repository/loan_schedule_repository.dart';
import 'package:payment_repository/payment_repository.dart';

/// A borrower payment submission awaiting lender confirm/reject.
///
/// A single submission may cover multiple loan schedules (a "pay in full"
/// submission) — all payments sharing the same [submissionId] are grouped
/// here so the lender confirms/rejects them as ONE item.
class PendingSubmission extends Equatable {
  const PendingSubmission({
    required this.submissionId,
    required this.payments,
    required this.loan,
    required this.schedules,
    this.totalAmount,
  });

  final String submissionId;
  final List<Payment> payments;

  /// The loan and the submitted rows, in the same order as [payments], so the
  /// confirm dialog can preview lateness without another round trip.
  final Loan loan;
  final List<LoanSchedule> schedules;

  /// Sum of the linked schedules' amounts, if it could be resolved while
  /// loading. Null when amounts were unavailable.
  final double? totalAmount;

  @override
  List<Object?> get props =>
      [submissionId, payments, loan, schedules, totalAmount];
}
```

In `_loadPendingSubmissions`, add `final schedulesBySubmission = <String, List<LoanSchedule>>{};` next to `paymentsBySubmission` (line 268), add `schedulesBySubmission.putIfAbsent(key, () => []).add(schedule);` right after the `paymentsBySubmission...add(payment)` line (288), and build the item as:

```dart
            (entry) => PendingSubmission(
              submissionId: entry.key,
              payments: entry.value,
              loan: loan,
              schedules: schedulesBySubmission[entry.key] ?? const [],
              totalAmount: amountBySubmission[entry.key],
            ),
```

Run `grep -rn "PendingSubmission(" apps/loans --include=*.dart` and give every other construction (tests included) `loan:` and `schedules:`; in tests use `Loan()..id = 'l1'..term = '1m'` and `const []`.

- [ ] **Step 2: Payment Center confirm dialog**

In `pending_submission_section.dart`, add imports `package:flutter_form_builder/flutter_form_builder.dart` and `package:loooans/widgets/payment_penalty_section.dart`. Replace the Confirm button's `onPressed` (lines 160–164) with `onPressed: () => showConfirmSubmissionDialog(context, submission: submission),` and add at file bottom:

```dart
/// Confirms a borrower submission after the teller reviews the collection
/// date (defaults to when the borrower submitted) and any penalty.
Future<void> showConfirmSubmissionDialog(
  BuildContext context, {
  required PendingSubmission submission,
}) {
  final bloc = context.read<PaymentCenterBloc>();
  final key = GlobalKey<FormBuilderState>(debugLabel: 'confirm_submission');

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Confirm submission'),
        backgroundColor: AppColors.green1,
        content: SizedBox(
          width: 420,
          child: FormBuilder(
            key: key,
            child: SingleChildScrollView(
              child: PaymentPenaltySection(
                schedules: submission.schedules,
                loan: submission.loan,
                initialCollectedAt: submission.payments.first.createdAt,
              ),
            ),
          ),
        ),
        actions: [
          AppWidgets.defaultFilledButton(
            onPressed: () {
              if (!(key.currentState?.saveAndValidate() ?? false)) return;
              final values = key.currentState!.value;
              Navigator.of(dialogContext, rootNavigator: true).pop();
              bloc.confirmSubmission(
                submission.payments,
                collectedAt: values['collected_at'] as DateTime?,
                waivePenalty: values['waive_penalty'] as bool? ?? false,
                waiveReason: values['waive_reason'] as String?,
              );
            },
            child: const Text('Confirm'),
          ),
          AppWidgets.defaultOutlinedButton(
            onPressed: () =>
                Navigator.of(dialogContext, rootNavigator: true).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}
```

- [ ] **Step 3: Client-detail review dialog**

In `client_detail_loan_body.dart`, add imports `package:flutter_form_builder/flutter_form_builder.dart` and `package:loooans/widgets/payment_penalty_section.dart`. In `_showReviewPaymentDialog`, create `final key = GlobalKey<FormBuilderState>(debugLabel: 'review_payment');` before `showDialog`, wrap the content `Column` in `FormBuilder(key: key, child: SingleChildScrollView(child: Column(...)))`, widen the `SizedBox` to `width: 420`, and after the amount/due `Text` (line 247) add:

```dart
                const Gap(12),
                PaymentPenaltySection(
                  schedules: [schedule],
                  loan: context.read<LoansBloc>().selectedLoan,
                  initialCollectedAt: payment.createdAt,
                ),
```

Change the Confirm action to validate and pass the values:

```dart
            AppWidgets.defaultFilledButton(
              onPressed: () {
                if (!(key.currentState?.saveAndValidate() ?? false)) return;
                final values = key.currentState!.value;
                _onConfirmFromReview(
                  context,
                  dialogContext: dialogContext,
                  payment: payment,
                  collectedAt: values['collected_at'] as DateTime?,
                  waivePenalty: values['waive_penalty'] as bool? ?? false,
                  waiveReason: values['waive_reason'] as String?,
                );
              },
              child: const Text('Confirm'),
            ),
```

Give `_onConfirmFromReview` the three named parameters (`DateTime? collectedAt, bool waivePenalty = false, String? waiveReason`) and forward them to `service.confirm(...)`.

- [ ] **Step 4: Analyze, test, walk through, commit**

Run: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` and `cd apps/loans && fvm flutter test; cd -`.

Expected: clean; all tests pass (any test constructing `PendingSubmission` updated in Step 1).

Dev-flavor walkthrough: as a borrower, submit a bank-transfer payment on an overdue row; as the teller, the Payment Center card's Confirm opens the dialog with the collection date preset to the submission time and the penalty shown; confirm; the row is `paid_late` with the penalty recorded and red "penalty charged" on the row. Repeat from the client-detail row's "Confirm payment" button.

```bash
git rev-parse --abbrev-ref HEAD
git add apps/loans/lib/features/payment_center/model/pending_submission.dart apps/loans/lib/features/payment_center/bloc/payment_center_bloc.dart apps/loans/lib/features/payment_center/widget/pending_submission_section.dart apps/loans/lib/features/users/widget/client_detail/client_detail_loan_body.dart
git add -u apps/loans/test
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "feat(payments): review collection date and penalty when confirming borrower submissions" -m "Symptom: confirming a borrower's bank-transfer submission charged the snapshot penalty silently, dated at confirmation time.

Cause: both confirm buttons called the service directly with no dialog.

Fix: PendingSubmission carries the loan and rows; the Payment Center card and the client-detail review dialog show PaymentPenaltySection with the date preset to the submission time and forward date/waive to confirm()." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 7: Statement of account penalty column and total

**Files:**
- Modify: `apps/loans/lib/features/reports/models/soa_entry.dart`
- Modify: `apps/loans/lib/features/reports/bloc/reports_bloc_extension_soa.dart:168-180` (schedule entries), `:270-299` (totals entry and `additionalCharges`)
- Modify: `apps/loans/lib/utils/constants.dart:126-137`
- Modify: `apps/loans/lib/features/loans/screens/statement_of_account_screen.dart:449-454` (column 7 cell), `:548`, `:607` (last-column hooks)
- Modify: `apps/loans/lib/utils/pdf_generator_build_soa.dart:173-177`

**Interfaces:**
- Consumes: `LoanSchedule.penalty`; `ChargeSimple`; `toCurrency(allowEmpty: true)`; `Constants.statementOfAccountHeaders`.
- Produces: `SOAEntry.penalty: double` (default 0); a `ChargeSimple(description: 'Penalties')` in `SOAModel.additionalCharges` when any penalty was charged; header `'Penalty'` as the last column.

The totals rows on the screen are selected by index arithmetic keyed off `SOAModel.size`; appending penalties to `additionalCharges` reuses the existing `Add: <description>` rendering on both the screen and the PDF and lands in `totalAmountDue` with no index changes.

- [ ] **Step 1: Entry field**

In `soa_entry.dart` add `this.penalty = 0,` to the constructor (after `this.isAdditionalAmount = false,`) and the field:

```dart
  /// Penalty charged on this installment (0 when none, waived, or allowed).
  final double penalty;
```

- [ ] **Step 2: Builder**

In `_generateSOA`, add `penalty: sched.penalty,` to the `SOAEntry(` in the `for (final sched in schedules)` loop. Before the `// add the last entry` block (line 270) add:

```dart
      final totalPenalties =
          entries.fold<double>(0, (prev, entry) => prev + entry.penalty);
```

Add `penalty: totalPenalties,` to the `isTotal: true` entry. After the `additionalCharges` list is built (line 299) add:

```dart
      if (totalPenalties > 0) {
        additionalCharges.add(
          ChargeSimple(amount: totalPenalties, description: 'Penalties'),
        );
      }
```

(`additionalCharges` comes from `.toList()`, so it is growable.) `totalAmountDue` and `size` already fold over that list.

- [ ] **Step 3: Header and screen**

In `constants.dart`, append `'Penalty',` after `'Principal\nbalance',` so it is the last header.

In `statement_of_account_screen.dart`, after the `column == 7` (principal balance) branch at lines 449–454 add:

```dart
        } else if (column == 8) {
          final amount = entry.penalty;
          defaultCellDisplay = wrapPadding(
            Text(amount > 0 ? amount.toCurrency() : ''),
          );
```

The deduction and additional-charge rows advance their counters on the last column (`column == 7` at lines 548 and 607). Change both to `column == Constants.statementOfAccountHeaders.length - 1` so the counter still advances once per row now that there are nine columns. Run `grep -n "column == 7" apps/loans/lib/features/loans/screens/statement_of_account_screen.dart` afterwards; only the entry-cell branch at line 449 may remain.

- [ ] **Step 4: PDF**

In `pdf_generator_build_soa.dart`, after the `entry.principalBalance` cell (line 177) add:

```dart
                        _tableItemWidget(
                          entry.penalty.toCurrency(
                            allowEmpty: true,
                          ),
                        ),
```

The header row maps `statementOfAccountHeaders` and the `Add:` lines loop `additionalCharges`, so both pick up the change.

- [ ] **Step 5: Analyze, check, commit**

Run: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` and `cd apps/loans && fvm flutter test; cd -`.

Expected: clean; tests pass.

Dev-flavor check: generate the statement of account (screen and PDF) for the loan used in Task 4. Rows confirmed late show the penalty in the last column, others are blank; `ADD: PENALTIES` appears among the additional charges and the total amount due includes it; a loan with no penalties shows an empty column and no penalties line; the totals rows still line up (merged label at column 2, value at column 5).

```bash
git rev-parse --abbrev-ref HEAD
git add apps/loans/lib/features/reports/models/soa_entry.dart apps/loans/lib/features/reports/bloc/reports_bloc_extension_soa.dart apps/loans/lib/utils/constants.dart apps/loans/lib/features/loans/screens/statement_of_account_screen.dart apps/loans/lib/utils/pdf_generator_build_soa.dart
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "feat(reports): penalty column and 'Add: Penalties' on the statement of account" -m "Symptom: penalties charged at confirmation were invisible on the statement of account.

Cause: SOAEntry had no penalty field and the totals section is index arithmetic keyed off SOAModel.size.

Fix: per-row penalty column (last), and total penalties appended to additionalCharges so the screen and PDF render 'Add: Penalties' and include it in the total amount due without touching the row arithmetic." -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 8: Spec amendment and MEMORY.md

**Files:**
- Modify: `docs/superpowers/specs/2026-09-04-penalties-design.md` (sections 6, 7.4–7.5, 7.7, 8, 9, 10)
- Modify: `apps/loans/MEMORY.md` (append after the part-2 section)

- [ ] **Step 1: Amend the spec**

Replace section 6 with:

```markdown
## 6. Trigger: payment confirmation (PR 3)

finstack has four confirmation paths, all self-managed: the client-detail teller dialog (`PaymentBloc`), the Payment Center single payment and bulk overdue payment (`PaymentCenterBloc`), and the borrower bank-transfer submission confirm (`PaymentConfirmationService.confirm`, reached from the Payment Center card and the client-detail review dialog). All four call `PaymentConfirmationService.applyLateness`, which runs `resolveLateness` (pure, `loan_schedule_repository`) against the loan snapshot and writes `collected_at`, `days_late`, `penalty`, `penalties`, `penalty_waived_by`, and `penalty_waive_reason` onto the row before the payment record is created. `paid_late` is written only when the collection date is after the due date on a loan with `allow_late_payments == false`.

Collection date: chosen by the teller in the dialog; defaults to now for teller payments and to the borrower's submission time (`Payment.created_at`) for submissions. Bulk overdue applies one date to every row; each row gets its own days late and penalty. A waive needs a reason; bulk and submission loops validate it before the first write.

Borrower submissions: the transferred amount does not include the penalty. The penalty is still recorded on the row and appears on the row and the statement of account as owed; collecting it is manual in this pass.

Reporting: the Go trigger `loan_schedule_changes.go` reads only company_id, status, loan_id, interest_payment, principal_payment on document creation and ignores the new fields, so this is not Class B. Penalties are not added to `total_collections`; doing so would be a Class B change with its own Go PR. Side effect to note: allow-late loans stop producing `paid_late`, which changes which newly-created open-term rows pass the trigger's status gate.
```

Replace the line `- **7.4–7.5 Schedule rows and confirm dialog**: PR 3.` with:

```markdown
- **7.4 Schedule rows**: `ClientDetailScheduleItem` and `LoanScheduleWidget` (table and list tile) take the loan and print `previewPenalty` in red under the amount due (`+ ₱… penalty · N days late` on the lender side, `+ ₱… penalty` for the borrower), plus `penalty charged` / `penalty waived` on confirmed rows. Offer previews pass no loan and show nothing.
- **7.5 Confirm dialogs**: one shared `PaymentPenaltySection` (`lib/widgets/`) with the collection date picker, a live breakdown (one line per penalty per row, `name · amount label × periods`), `Total to collect`, and a `Waive penalties` checkbox that reveals a required reason. Hosted in the client-detail make-payment dialog, both Payment Center dialogs, the Payment Center submission confirm dialog, and the client-detail review dialog.
```

Replace `- **7.7 Statement of account**: PR 3.` with:

```markdown
- **7.7 Statement of account**: a `Penalty` column (last) per row, and total penalties appended to `additionalCharges` so the existing `Add: <description>` rendering and `totalAmountDue` include them on the screen and the PDF.
```

In section 8 add the bullet `- Penalties in report aggregates (`total_collections`); collecting the penalty on a borrower submission (recorded as owed only).` In section 9 add the new tests: `packages/loans/loan_schedule_repository/test/penalty_calculator_test.dart` (`resolveLateness`), `apps/loans/test/services/payment_confirmation_service_test.dart` (`applyLateness`), `apps/loans/test/features/payment_center/payment_center_confirm_test.dart` (late confirm), `apps/loans/test/widgets/payment_penalty_section_test.dart`. In section 10 item 2, note the branch stacks on 1 and merge waits for PR #109 and the loan-engine campaign's Gate 1 because penalty math is on the money path.

- [ ] **Step 2: MEMORY.md entry**

Append to `apps/loans/MEMORY.md` after the part-2 section:

```markdown
## Penalties application — loooans#72 part 3 (2026-09-04)

Branch `feat/penalties-72-application` stacked on `feat/penalties-72-definitions` (PR #109). Spec `docs/superpowers/specs/2026-09-04-penalties-design.md` sections 6, 7.4, 7.5, 7.7; plan `docs/superpowers/plans/2026-09-04-penalties-3-application-port.md`.

- One rule: `resolveLateness` (pure, `loan_schedule_repository/penalty_calculator.dart`) → `PaymentConfirmationService.applyLateness` writes `collected_at`, `days_late`, `penalty`, `penalties`, waive fields and returns the status. Called from `PaymentBloc._handlePayLoanScheduleEvent`, `PaymentCenterBloc._handleMakePaymentEvent`, `_handleMakeOverduePaymentEvent` (one date, per-row penalty), and `PaymentConfirmationService.confirm` (default date = `Payment.createdAt`). `scheduleStatusForConfirmation` removed. `paid_late` only when late on a loan with `allow_late_payments == false`.
- Events/methods gained `collectedAt`, `waivePenalty`, `waiveReason`: `PayLoanScheduleEvent`, `MakePaymentEvent`, `MakeOverduePaymentEvent`, `ConfirmSubmissionEvent` and their `makePayment`/`makeOverduePayment`/`confirmSubmission`.
- UI: `lib/widgets/payment_penalty_section.dart` (form keys `collected_at`, `waive_penalty`, `waive_reason`; takes `List<LoanSchedule>`), hosted in `client_detail_dialogs.showMakePaymentDialog`, `payment_center_dialogs.showPaymentCenterPaymentDialog`/`showOverduePaymentDialog`, `pending_submission_section.showConfirmSubmissionDialog`, `client_detail_loan_body._showReviewPaymentDialog`. `AppWidgets.defaultFormBuilderDatePicker` gained `initialValue`/`onChanged`. Red lines: `client_detail_schedule_item.dart` (`loan:` param) and `loan_schedule_widget.dart` (`loan:` on widget and `scheduleItem`). `PendingSubmission` carries `loan` and `schedules`.
- SOA: `SOAEntry.penalty`; `Penalty` header is the LAST column; total penalties appended to `additionalCharges` as `Penalties` (no index arithmetic touched); last-column counter hooks in `statement_of_account_screen.dart` use `statementOfAccountHeaders.length - 1`.
- Not Class B: `loan_schedule_changes.go` ignores the new fields. Penalties are NOT in `total_collections` (would be Class B). Allow-late loans no longer write `paid_late` (affects only newly created open-term rows at the trigger's status gate).
- Gate: merge waits for PR #109 and the loan-engine campaign's Gate 1 (penalty math is on the money path). Tests: `penalty_calculator_test.dart` (resolveLateness), `payment_confirmation_service_test.dart` (applyLateness), `payment_center_confirm_test.dart` (late confirm; `sched()` now sets `isOpenTerm`/`amortization`/`outstandingBalance` because `resolveLateness` reads them), `test/widgets/payment_penalty_section_test.dart`.
- Deferred: collecting the penalty on a borrower submission (recorded as owed only); a bloc-level test for `_handlePayLoanScheduleEvent` (blocked by the unmockable `CashPoolRepository` late field); `_nextPayment` "Pay in full" total excludes penalties.
```

- [ ] **Step 3: Commit**

```bash
git rev-parse --abbrev-ref HEAD
git add docs/superpowers/specs/2026-09-04-penalties-design.md apps/loans/MEMORY.md
git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit -m "docs(penalties): amend the design for four confirmation paths and record part 3" -m "Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ"
```

---

### Task 9: Verify, report aggregates, sign-off, push, stacked draft PR

**Files:** none new.

- [ ] **Step 1: Full gate**

```bash
.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh
(cd apps/loans && fvm flutter test)
(cd packages/loans/loan_schedule_repository && fvm flutter test)
git checkout -- 'packages/core/*/analysis_options.yaml' 'packages/loans/*/analysis_options.yaml'
git status --short   # must be empty
```

Expected: 0 errors and no new warnings/infos versus the baseline; all tests pass.

- [ ] **Step 2: Manual walkthrough on the development flavor**

Dev server: `cd apps/loans && fvm flutter run -d web-server --web-port 8090 --web-hostname localhost --target lib/main_development.dart --dart-define=ENVIRONMENT=development` (kill any previous `flutter_tools.snapshot run -d web-server --web-port 8090` dart child first).

1. Overdue row shows the red line in the lender's client detail and in the borrower's loan details.
2. Confirm on time → `paid_on_time`, no penalty, `days_late: 0`.
3. Confirm late, no waive → `paid_late`, penalty written, SOA shows it.
4. Confirm late, waive with reason → `paid_late`, penalty 0, waive fields set, row says `penalty waived`.
5. Confirm late on an allow-late loan → `paid_on_time`, penalty 0, `days_late` recorded.
6. Backdate the collection date to the due date on an overdue row → `paid_on_time`, no penalty (the loooans#71 case).
7. Payment Center single and bulk overdue behave the same; bulk writes per-row penalties.
8. Borrower submission confirmed from the Payment Center card and from the client-detail review dialog: date preset to the submission time.
9. A loan created before part 2 (empty penalties) confirms late as `paid_late` with penalty 0.

Record the results in the PR body. Get the owner's sign-off on the UI before pushing.

- [ ] **Step 3: Report aggregates check**

`loan_schedule_changes.go` fires on schedule document creation only and gates on `payment_submitted`/`paid_on_time`/`paid_late`. Confirm one late payment on an open-term loan (the `schedule.id == NO_ID` path that creates the document). In the RTDB `dev/` report node for the company, the collections/interest/principal figures move by that installment's amounts exactly once, and `firebase functions:log` shows no error for the trigger. Penalty amounts must NOT appear in the totals (out of scope). If anything double-counts or fails, stop and report before pushing.

- [ ] **Step 4: Push and open the stacked draft PR**

```bash
git rev-parse --abbrev-ref HEAD
git -c credential.helper="!gh auth git-credential" push -u https://github.com/anatechopc/finstack.git feat/penalties-72-application
gh pr create --repo anatechopc/finstack --base feat/penalties-72-definitions --draft \
  --title "feat(penalties): apply penalties at payment confirmation with collection date and waive (loooans#72 part 3)" \
  --body "$(cat <<'EOF'
## Summary
Part 3 of loooans#72 (penalties), also resolves loooans#71 and loooans#78. Stacked on #109 (retarget to `develop` once #109 merges). Design: `docs/superpowers/specs/2026-09-04-penalties-design.md` (section 6 amended here). Plan: `docs/superpowers/plans/2026-09-04-penalties-3-application-port.md`.

- One lateness rule: `resolveLateness` → `PaymentConfirmationService.applyLateness`, called from all four confirmation paths (client-detail teller, Payment Center single, Payment Center bulk overdue, borrower-submission confirm). Writes `collected_at`, `days_late`, `penalty`, `penalties`, `penalty_waived_by`, `penalty_waive_reason`. `paid_late` only when late on a loan that does not allow late payments.
- Shared `PaymentPenaltySection`: collection date, live breakdown, waive with required reason; hosted in every confirm dialog. Borrower submissions default the date to the submission time.
- Red running-penalty line on lender and borrower schedule rows.
- Statement of account: `Penalty` column and `Add: Penalties` in the total amount due.

## Change control
- Not Class B: `loan_schedule_changes.go` ignores the new fields (reads five named fields on document creation). Penalties are not added to `total_collections`; that would be a separate Go PR.
- Loan math on the money path: merge after #109 and the loan-engine campaign's Gate 1.
- Behavior note: allow-late loans no longer write `paid_late`, which changes which newly-created open-term rows pass the trigger's status gate.

## Test plan
- [ ] `analyze-source-only.sh` clean; `apps/loans` and `loan_schedule_repository` tests pass
- [ ] Manual walkthrough (plan Task 9 step 2) on the development flavor
- [ ] RTDB aggregates after a late open-term confirmation (plan Task 9 step 3)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ
EOF
)"
```

Expected: PR URL printed. Report it. Do not merge.

---

## Summary

| Task | Deliverable | Option-dependent |
|------|-------------|------------------|
| 1 | `resolveLateness`, `applyLateness`, `confirm()` with date/waive; tests | no |
| 2 | All four bloc/service paths call `applyLateness`; events carry date/waive | no |
| 3 | Red lines on lender and borrower rows | no |
| 4 | `PaymentPenaltySection` + client-detail make-payment dialog; widget test | no |
| 5 | Payment Center single and bulk overdue dialogs | yes |
| 6 | Borrower-submission confirm dialogs (Payment Center card, client-detail review) | yes |
| 7 | Statement of account column and total | no |
| 8 | Spec amendment, MEMORY.md | no |
| 9 | Gate, walkthrough, aggregates, push, stacked draft PR | no |

## Test plan

- Unit: `resolveLateness` (6 cases), `applyLateness` (6 cases), `confirm()` late and explicit-date cases.
- Widget: `PaymentPenaltySection` (5 cases).
- Manual: Task 9 step 2 list; RTDB aggregate check in step 3.
