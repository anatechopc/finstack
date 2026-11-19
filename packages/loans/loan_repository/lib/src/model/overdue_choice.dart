import 'package:json_annotation/json_annotation.dart';

/// What the lender chose when adding a top-up to an open-term loan with
/// overdue bills (owner, 2026-11-19).
enum OverdueChoice {
  /// Approval pays the overdue bills from the top-up's proceeds and
  /// releases the rest.
  @JsonValue('deduct')
  deduct,

  /// The full top-up is released; the overdue bills stay owed and are
  /// billed with the next bill.
  @JsonValue('next_bill')
  nextBill,
}
