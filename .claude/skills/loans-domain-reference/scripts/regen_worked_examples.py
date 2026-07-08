#!/usr/bin/env python3
"""Re-derive every worked-example number cited in loans-domain-reference.

Mirrors the Dart implementation exactly:
  - fixed-term annuity: apps/loans/lib/utils/extensions.dart:148-166
    P = (Pv*R) / (1 - (1+R)^-n); '15d' => R/2, n*2
  - fixed-term row loop: apps/loans/lib/services/loan_calculation_service.dart:97-135
    interest = OB*R; amort = min(P, OB+interest); principal = amort-interest
  - open-term proration: loan_calculation_service.dart:262-266
    interestDayMultiplier = |diffDays|/30 ("1 month = 30 days")

Run from anywhere; no arguments, no dependencies. If the printed numbers stop
matching SKILL.md / references/schedule-math.md, either this repo's math changed
(update the skill!) or the skill drifted.
"""


def annuity_payment(pv: float, monthly_rate: float, months: int, term: str) -> float:
    """extensions.dart calculateMonthlyPayment. monthly_rate is decimal (0.03)."""
    r, n = monthly_rate, months
    if term == "15d":
        r /= 2
        n *= 2
    return (pv * r) / (1 - (1 + r) ** -n)


def fixed_term_table(pv: float, monthly_rate: float, months: int, term: str):
    """loan_calculation_service.dart calculateFixedTerm row loop."""
    p = annuity_payment(pv, monthly_rate, months, term)
    r, n = monthly_rate, months
    if term == "15d":
        r /= 2
        n *= 2
    ob, rows, total = pv, [], 0.0
    for i in range(1, n + 1):
        beginning = ob
        interest = ob * r
        amort = min(p, beginning + interest)  # final-row clamp
        principal = amort - interest
        ob -= principal
        total += amort
        rows.append((i, beginning, interest, amort, principal, ob))
    return p, rows, total


def open_term_interest(ob: float, monthly_rate: float, diff_days: float) -> float:
    """loan_calculation_service.dart:262-266 proration."""
    multiplier = abs(diff_days) / 30.0
    return ob * monthly_rate * multiplier


def main() -> None:
    print("=== Example A: fixed-term  Pv=10,000  3%/mo  6 months  term '1m' ===")
    p, rows, total = fixed_term_table(10_000, 0.03, 6, "1m")
    print(f"P = {p:.2f}   (SKILL.md says 1845.98)")
    print("  # |  begin OB | interest |  amort  | principal | end OB")
    for i, beg, intr, amort, prin, ob in rows:
        print(f"  {i} | {beg:9.2f} | {intr:8.2f} | {amort:7.2f} | {prin:9.2f} | {ob:.2f}")
    print(f"total paid = {total:.2f}   (schedule-math.md says 11075.85)")

    print("\n=== Example B: same loan at term '15d' ===")
    p15, rows15, total15 = fixed_term_table(10_000, 0.03, 6, "15d")
    print(f"P = {p15:.2f} per half-month x {len(rows15)} payments; "
          f"total = {total15:.2f}   (skill says 916.80 / 11001.60)")

    print("\n=== Example C: open-term proration  OB=10,000  5%/mo ===")
    print(f"amortization (interest-only month) = {10_000 * 0.05:.2f}   (skill says 500.00)")
    for days, expect in ((15, "250.00"), (30, "500.00"), (45, "750.00")):
        got = open_term_interest(10_000, 0.05, days)
        print(f"  {days:2d} days elapsed -> multiplier {days/30:.4g} -> interest {got:.2f} "
              f"(skill says {expect})")

    print("\nAll formulas mirror the Dart source cited in the docstring. If numbers")
    print("disagree with the skill, re-read loan_calculation_service.dart before editing.")


if __name__ == "__main__":
    main()
