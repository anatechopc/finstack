import 'package:flutter_test/flutter_test.dart';
import 'package:loooans/features/chat/chat_context_label.dart';

void main() {
  test('prefers the denormalized label over the type', () {
    expect(
      contextPillText(contextType: 'product', contextLabel: 'Business loan'),
      'Business loan',
    );
    expect(
      contextPillText(contextType: 'loan', contextLabel: 'Open Term Loan'),
      'Open Term Loan',
    );
  });

  test('falls back to the type for rooms created before the label existed', () {
    expect(contextPillText(contextType: 'product'), 'Offer');
    expect(contextPillText(contextType: 'loan'), 'Loan');
  });

  test('treats an empty or blank label as absent', () {
    expect(contextPillText(contextType: 'product', contextLabel: ''), 'Offer');
    expect(
      contextPillText(contextType: 'product', contextLabel: '   '),
      'Offer',
    );
  });

  test('returns null for an unanchored or unrecognised room — no pill', () {
    expect(contextPillText(), isNull);
    // 'company' appears in the spec's type list but no entry point creates one;
    // an unknown type must not render a raw enum string at the user.
    expect(contextPillText(contextType: 'company'), isNull);
  });

  test('a blank loanType does not leave a dangling separator', () {
    // Product.loanType is `late String` free text, not an enum, so the "others"
    // path can save it blank. 'Offer · ' would be written once and never
    // repairable: the backfill only fills an EMPTY label, and the field is
    // write-protected.
    expect(productContextLabel(''), 'Offer');
    expect(productContextLabel('   '), 'Offer');
    expect(loanContextLabel(loanType: '', amount: 50000), 'Loan ₱50k');
  });

  test('compactAmount rounds before choosing the magnitude', () {
    // Choosing the unit first and rounding after gave ₱999,999 -> '₱1000.0k'.
    expect(compactAmount(999999), '₱1m');
    expect(compactAmount(1999999), '₱2m');
    expect(compactAmount(999), '₱999');
  });

  test('labels lead with the kind so product and loan rooms differ', () {
    // A product enquiry and the loan that came from it share a loanType; the
    // kind prefix is what keeps their rooms tellable apart.
    expect(productContextLabel('Business loan'), 'Offer · Business loan');
    expect(
      loanContextLabel(loanType: 'Business loan', amount: 50000),
      'Loan ₱50k · Business loan',
    );
  });

  test('the amount separates several loans of the same product', () {
    expect(
      loanContextLabel(loanType: 'Business loan', amount: 50000),
      isNot(loanContextLabel(loanType: 'Business loan', amount: 120000)),
    );
  });

  test('compactAmount keeps the label short', () {
    expect(compactAmount(950), '₱950');
    expect(compactAmount(50000), '₱50k');
    expect(compactAmount(120000), '₱120k');
    expect(compactAmount(1500), '₱1.5k');
    expect(compactAmount(1200000), '₱1.2m');
    expect(compactAmount(2000000), '₱2m');
  });
}
