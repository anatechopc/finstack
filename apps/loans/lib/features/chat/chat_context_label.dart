import 'package:loooans/utils/constants.dart';

/// Builders for a chat room's `context_label` — the human-readable name of the
/// product or loan a conversation is anchored to, denormalized onto the room at
/// creation so the inbox can name it without a second fetch.
///
/// The label leads with the KIND ("Offer"/"Loan") because the type alone is
/// ambiguous: a product enquiry and the loan that came from that product share
/// a `loanType`, and a borrower with several loans of one product would see
/// identical labels on every room. Loans add the amount, which separates them.
///
/// Kept short on purpose — the inbox line fits roughly 20 characters at 390dp
/// before ellipsis.

/// Label for a room anchored to a marketplace product.
///
/// Products have no name field: `loanType` (free text, e.g. "Business loan")
/// is the only human-readable identifier the model carries, and `tagLine` is
/// empty in practice.
String productContextLabel(String loanType) => 'Offer · ${loanType.trim()}';

/// Label for a room anchored to a specific loan.
///
/// The amount comes BEFORE the product type on purpose. The line has ~210px on
/// a 390dp phone and this label needs ~275px, so it ellipsizes — and the amount
/// is what separates a borrower's several loans of the same product. Ordered
/// the other way round, truncation ate exactly the distinguishing part.
String loanContextLabel({required String loanType, required double amount}) =>
    'Loan ${compactAmount(amount)} · ${loanType.trim()}';

/// Short money for a label: ₱950, ₱50k, ₱1.2m.
///
/// Deliberately not [Constants.defaultCurrencyFormatOptionalDecimal] — "₱ 50,000"
/// costs eight characters against four, and width is the binding constraint on
/// this line.
String compactAmount(double amount) {
  const s = Constants.currencySymbol;
  if (amount >= 1000000) {
    final m = amount / 1000000;
    return '$s${m.toStringAsFixed(m % 1 == 0 ? 0 : 1)}m';
  }
  if (amount >= 1000) {
    final k = amount / 1000;
    return '$s${k.toStringAsFixed(k % 1 == 0 ? 0 : 1)}k';
  }
  return '$s${amount.toStringAsFixed(0)}';
}

/// Text for the room's context line.
///
/// Prefers the stored label; falls back to the kind for rooms created before
/// `context_label` existed. Null when the room has no anchor — no line shown.
String? contextPillText({String? contextType, String? contextLabel}) {
  final label = contextLabel?.trim();
  if (label != null && label.isNotEmpty) return label;

  switch (contextType) {
    case 'loan':
      return 'Loan';
    case 'product':
      return 'Offer';
    default:
      return null;
  }
}
