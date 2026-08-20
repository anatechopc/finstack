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
    expect(contextPillText(contextType: 'product'), 'Product');
    expect(contextPillText(contextType: 'loan'), 'Loan');
  });

  test('treats an empty or blank label as absent', () {
    expect(contextPillText(contextType: 'product', contextLabel: ''), 'Product');
    expect(
      contextPillText(contextType: 'product', contextLabel: '   '),
      'Product',
    );
  });

  test('returns null for an unanchored or unrecognised room — no pill', () {
    expect(contextPillText(), isNull);
    expect(contextPillText(contextType: null), isNull);
    // 'company' appears in the spec's type list but no entry point creates one;
    // an unknown type must not render a raw enum string at the user.
    expect(contextPillText(contextType: 'company'), isNull);
  });
}
