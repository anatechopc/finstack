# Penalties definitions — finstack port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish porting the reviewed penalties "definitions" work (loooans#72 part 2) onto finstack's refactored app: ProductBloc state, the wizard section, company defaults on the profile, the loan snapshot, and the quotation listing; then verify, record, and open the PR.

**Architecture:** The model, calculator, dialog, and labels are already on this branch (commits 952d3fc..fcbf505, ported verbatim). What remains is wiring against files that finstack refactored since the old repo. The exact reviewed code for each piece lives in the patch files under `/home/deibeeed/.claude/jobs/c66fd09f/tmp/patches/` (paths already rewritten to finstack); implementers transplant that logic to the anchors below rather than re-deriving it. Screens compose small section widgets under `apps/loans/lib/features/products/widget/add_product/`, so the Penalties UI becomes one such widget.

**Tech Stack:** Flutter 3.44.9 via fvm, flutter_bloc, flutter_form_builder, json_serializable (generated files gitignored), Firestore.

**Spec:** `docs/superpowers/specs/2026-09-04-penalties-design.md`

## Global Constraints

- Worktree `/home/deibeeed/Projects/AnaheimTechnologies/finstack/.claude/worktrees/penalties-72`, branch `feat/penalties-72-definitions`, base `develop`. All paths relative to it. `cd` there for every command; the shell cwd does not persist.
- Always `fvm flutter` / `fvm dart`. Never edit `*.g.dart`, `firebase_options*.dart`; regenerate with `fvm flutter pub run build_runner build --delete-conflicting-outputs` inside a package.
- Git identity for commits: `git -c user.name="I am" -c user.email="2108226+deibeeed@users.noreply.github.com" commit ...` (the repo has none configured). Conventional Commits `type(scope): summary`, body as symptom → cause → fix narrative, trailers `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Xjheh1tumXqBP9S1Ces6KZ`. Never squash; never push `master`.
- Ticket numbers always carry the repo: `loooans#72`, `finstack#107`. A bare `#72` means something else on finstack.
- Analyzer gate: `.claude/skills/finstack-testing-and-validation/scripts/analyze-source-only.sh` must report 0 errors outside `build/`; no new warnings/infos versus the saved baseline `/home/deibeeed/.claude/jobs/c66fd09f/tmp/finstack-analyze-baseline-src.txt` (147 issues). Compare with `cd apps/loans && fvm flutter analyze > /tmp/a.txt; diff <(grep '•' <baseline> | sed 's/:[0-9]*:[0-9]* •/ •/' | sort) <(grep '•' /tmp/a.txt | grep -v '/build/' | sed 's/:[0-9]*:[0-9]* •/ •/' | sort) | grep '^>'`.
- Running a package test suite rewrites that package's `analysis_options.yaml` (adds `- build/**`). Never stage those files: `git add` explicit paths only, and `git checkout -- '<pkg>/analysis_options.yaml'` before committing.
- Known-failing package suites (pre-existing, leave alone): `packages/core/address_repository`, `packages/core/bank_details_repository`.
- No Go changes in this branch (spec D9/D10). Do not touch `functions/`.
- Do not `dart format` existing files; keep edits formatter-clean by hand. Format new files only.
- Do not push; the controller pushes after the owner's walkthrough sign-off.

## File Structure

| File | Responsibility |
|------|----------------|
| `apps/loans/lib/features/products/bloc/product_bloc.dart`, `product_event.dart` | penalties working list, events, seeding, persistence (Task 1) |
| `apps/loans/lib/features/products/widget/add_product/penalties_section.dart` | new section widget: chips, add, reset, allow-late checkbox (Task 2) |
| `apps/loans/lib/features/products/screen/add_product_screen.dart` | composition: portrait case + wide column (Task 2) |
| `apps/loans/lib/features/companies/bloc/company_bloc.dart`, `company_event.dart` | `UpdateDefaultPenaltiesEvent` with rollback (Task 3) |
| `apps/loans/lib/features/users/widget/default_penalties_section.dart` | new StatefulWidget owning the list, snackbar on error (Task 3) |
| `apps/loans/lib/features/users/widget/profile_widget.dart` | one insertion at the company column (Task 3) |
| `apps/loans/lib/features/loans/bloc/loans_bloc.dart` | loan snapshot at `Loan.create` (Task 4) |
| `apps/loans/lib/features/products/widget/quotation_widget.dart`, `apps/loans/lib/utils/pdf_generator_ext_widgets.dart` | parked patch `/home/deibeeed/.claude/jobs/c66fd09f/tmp/quotation-hunks.patch` (Task 4) |
| `apps/loans/lib/features/loans/screens/loan_details.dart`, `apps/loans/lib/features/users/widget/client_detail/client_detail_loan_body.dart` | four `QuotationWidget` call sites pass the loan snapshot (Task 4) |
| `apps/loans/MEMORY.md` | session entry (Task 5) |

---

### Task 1: ProductBloc penalties state and persistence

**Files:** Modify `apps/loans/lib/features/products/bloc/product_event.dart` (after `RemoveDeductionEvent`, ~line 48) and `apps/loans/lib/features/products/bloc/product_bloc.dart` (registrations 30–41; list fields 51–57; public methods 171–185; `initializeAddProduct` 105–111; `disposeAddProduct` 113–120; handlers after `_handleRemoveDeductionEvent`; `_handleAddProductEvent` `Product.create(` at ~516 with post-success clears ~579–581; `_handleUpdateProductEvent` cascade ~618–627 and clears ~690–692; `_handleSelectProductEvent` list fill ~739–747).

**Interfaces:** Produces `List<Penalty> get penalties`, `addPenalty(Penalty)`, `removePenalty({required String id})`, `resetPenalties()`, events `AddPenaltyEvent(penalty:)`, `RemovePenaltyEvent(id:)`, `ResetPenaltiesEvent`; reads form key `allow_late_payments`.

- [ ] Read `/home/deibeeed/.claude/jobs/c66fd09f/tmp/patches/0005-*.patch`, `0006-*.patch`, and the `product_bloc.dart` hunk of `0013-*.patch` (try/catch around the three handlers). Transplant every insertion to the anchors above. Seed in `initializeAddProduct` only when `productId == null`, from `AuthenticationService.instance.company.defaultPenalties`; clear in `disposeAddProduct`, after successful add and after successful update; pass `penalties: List<Penalty>.of(_penalties)` and `allowLatePayments: fields['allow_late_payments'] as bool? ?? false` into `Product.create` and the update cascade; fill from `product.penalties` on select. Handlers use the file's `try { … } catch (err) { log.severe(err); emit(ProductState.error(err.toString())); }` shape.
- [ ] Analyzer diff clean; `cd apps/loans && fvm flutter test` green.
- [ ] Commit: `feat(products): track penalties in ProductBloc, seeded from company defaults (loooans#72)`.

### Task 2: Wizard Penalties section with the allow-late-payments checkbox

**Files:** Create `apps/loans/lib/features/products/widget/add_product/penalties_section.dart`; modify `apps/loans/lib/features/products/screen/add_product_screen.dart` (portrait switch cases ~197–239: insert case 5, shift later cases, `itemCount` 18→19 at ~245, separator guard index 8→9 at ~242; wide layout `_inputCol1` ~287–312: insert after the Deductions entry at ~299).

**Interfaces:** Consumes Task 1's bloc API, `showPenaltyDialog`, `chipLabel`, `Product.allowLatePayments`. Produces `PenaltiesSection({required Product? product})` registering form field `allow_late_payments`.

- [ ] Model the widget on `charges_section.dart` (`DeductionsSection` at ~97, `_CustomChargeChip` at ~173) and `add_ons_section.dart` (~39–53, the boolean-field template). Content per the reviewed `0007-*.patch` `_penalties`/`_penaltyChip`/`_allowLatePayments` code: title row with add button (capture the bloc before `await showPenaltyDialog(context)`), `BlocBuilder` with the charges sections' `buildWhen`, chips marked `Default · ` with a green border when the id is in `company.defaultPenalties`, remove via `removePenalty(id:)`, "Reset to company defaults" `TextButton` when defaults exist, then a `FormBuilderCheckbox(name: 'allow_late_payments', initialValue: product == null ? false : product.allowLatePayments, title: 'Allow late payments', subtitle: 'When on, late payments are not tagged and no penalties are charged on this product.')` in the same section (the AutoCollect toggles are placeholders here). Pass whatever the neighbouring sections receive (`product: _product`).
- [ ] Wire both layouts. Analyzer diff clean.
- [ ] Commit: `feat(products): penalties section and allow-late-payments option in the product wizard (loooans#72)`.

### Task 3: Company default penalties on the profile card

**Files:** Modify `apps/loans/lib/features/companies/bloc/company_event.dart`, `company_bloc.dart` (registration at ~24; new method after `updateCompany` ~36; handler after `_handleUpdateCompanyEvent`); create `apps/loans/lib/features/users/widget/default_penalties_section.dart`; modify `apps/loans/lib/features/users/widget/profile_widget.dart` (insert between `..._buildCompanyWidgets(),` ~177 and the `Gap(24)` ~178, guarded by `AuthenticationService.instance.isAdmin`).

**Interfaces:** Produces `CompanyBloc.updateDefaultPenalties(List<Penalty>)` → `UpdateDefaultPenaltiesEvent`; `DefaultPenaltiesSection()` StatefulWidget.

- [ ] Bloc: handler per `0010-*.patch` (capture `previous`, mutate `company.defaultPenalties = List<Penalty>.of(event.penalties)`, `companyRepository.update(data: company)`, assign the returned company to `AuthenticationService.instance.company`, emit `loading()` then `success(message: 'Default penalties updated')`; on error restore `previous`, log, emit `loading()` then `error(...)` with the state's actual constructor shape from `company_state.dart`).
- [ ] Widget: owns `List<Penalty> _penalties` initialised from `AuthenticationService.instance.company.defaultPenalties`; title, add `IconButton` (dialog → append → `updateDefaultPenalties`), helper text "Every new product starts with these. Editing here does not change products already created.", `Wrap` of `Chip`s with `onDeleted`; wrap in `BlocListener<CompanyBloc, CompanyState>` that on error shows a `SnackBar` and reloads `_penalties` from the auth company (rolled back), on success with a message shows it. `CompanyState` has only initial/loading/error/success, no refresh: do not add one.
- [ ] Analyzer diff clean. Commit: `feat(companies): default penalties on the company profile (loooans#72)`.

### Task 4: Loan snapshot and quotation listing

**Files:** Modify `apps/loans/lib/features/loans/bloc/loans_bloc.dart` (`Loan.create(` at ~518, `product` promoted non-null; add after the `coMakerUserIds` arg ~560); apply `/home/deibeeed/.claude/jobs/c66fd09f/tmp/quotation-hunks.patch` with `git apply --index`; modify `loan_details.dart` (~254, ~332, variable `loan`) and `client_detail/client_detail_loan_body.dart` (~449, ~495, variable `selectedLoan`).

- [ ] `penalties: List<Penalty>.of(product.penalties), allowLatePayments: product.allowLatePayments,` in `Loan.create`. Apply the parked patch. At each of the four call sites add `penalties: <loan>.penalties, allowLatePayments: <loan>.allowLatePayments,`. Leave `loan_application_quotation.dart`, `loan_offer_details_form.dart`, `preview_detail.dart` untouched (no loan there). `grep -rn "QuotationWidget(" apps/loans/lib` in the report with a per-site decision.
- [ ] Analyzer diff clean; `cd apps/loans && fvm flutter test` green. Commit: `feat(loans): snapshot product penalties onto new loans and list them in quotations (loooans#72)`.

### Task 5: Record, verify, walkthrough, PR (controller-run)

- [ ] `apps/loans/MEMORY.md`: a feature-titled section `## Penalties definitions — loooans#72 part 2 (2026-09-04)` with what was added, the decisions D9/D10, the wrong-repo incident, resume state for PR 3; commit `docs(memory): record penalties definitions session (loooans#72)`.
- [ ] Gate: `analyze-source-only.sh`; `cd apps/loans && fvm flutter test`; package suites for `loooans_helpers`, `loan_schedule_repository` green; revert `analysis_options.yaml` churn.
- [ ] Owner walkthrough on `fvm flutter run -d web-server --web-port 8090 --web-hostname localhost --target lib/main_development.dart --dart-define=ENVIRONMENT=development` from `apps/loans`; sign-off; push over HTTPS; `gh pr create --repo anatechopc/finstack --base develop --draft` with body naming loooans#72/#71/#78, finstack#107/#108, and the roadmap risk note (new money math above a core with one golden test; no payment behavior in this PR).
