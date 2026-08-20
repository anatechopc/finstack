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
/// empty in practice. It is `late String`, not an enum, so the "others" path
/// can save it blank — hence the empty check: 'Offer · ' with a dangling
/// separator would be written once and never repairable, since the backfill
/// only fills an EMPTY label and the field is now write-protected.
String productContextLabel(String loanType) {
  final type = loanType.trim();
  return type.isEmpty ? 'Offer' : 'Offer · $type';
}

/// Label for a room anchored to a specific loan.
///
/// The amount comes BEFORE the product type on purpose. The line has ~210px on
/// a 390dp phone and this label needs ~275px, so it ellipsizes — and the amount
/// is what separates a borrower's several loans of the same product. Ordered
/// the other way round, truncation ate exactly the distinguishing part.
String loanContextLabel({required String loanType, required double amount}) {
  final type = loanType.trim();
  final money = compactAmount(amount);
  return type.isEmpty ? 'Loan $money' : 'Loan $money · $type';
}

/// Short money for a label: ₱950, ₱50k, ₱1.2m.
///
/// Deliberately not [Constants.defaultCurrencyFormatOptionalDecimal] — "₱ 50,000"
/// costs eight characters against four, and width is the binding constraint on
/// this line.
String compactAmount(double amount) {
  const s = Constants.currencySymbol;

  // Round BEFORE choosing the magnitude. Picking the unit first and rounding
  // after gave ₱999,999 -> '₱1000.0k' — eight characters from a function whose
  // whole purpose is four, on the one line where width is the constraint.
  String scaled(double value, String suffix) {
    final rounded = double.parse(value.toStringAsFixed(1));
    final text = rounded % 1 == 0
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '$s$text$suffix';
  }

  if (amount >= 999950) return scaled(amount / 1000000, 'm');
  if (amount >= 999.5) return scaled(amount / 1000, 'k');
  return '$s${amount.toStringAsFixed(0)}';
}

/// The room anchor kinds. Spelled once here — these strings are both written
/// (the three creation sites) and read (below), and a typo at a creation site
/// would dedup against a different key and silently fall through to no label.
const contextTypeLoan = 'loan';
const contextTypeProduct = 'product';

/// Text for the room's context line.
///
/// Prefers the stored label; falls back to the kind for rooms created before
/// `context_label` existed. Null when the room has no anchor — no line shown.
String? contextPillText({String? contextType, String? contextLabel}) {
  final label = contextLabel?.trim();
  if (label != null && label.isNotEmpty) return label;

  switch (contextType) {
    case contextTypeLoan:
      return 'Loan';
    case contextTypeProduct:
      return 'Offer';
    default:
      return null;
  }
}
