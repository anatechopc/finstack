/// Text for a room's context pill.
///
/// Rooms are anchored to the product or loan they are about (`context_type` +
/// `context_id`), and since 2026-08 also carry a denormalized `context_label`
/// — the anchor's `loanType` — so the inbox can name it without a second fetch.
///
/// Prefers the label; falls back to a human name for the type, which is what
/// rooms created before the label existed will show. Returns null when the room
/// has no anchor at all, in which case no pill is rendered.
String? contextPillText({String? contextType, String? contextLabel}) {
  final label = contextLabel?.trim();
  if (label != null && label.isNotEmpty) return label;

  switch (contextType) {
    case 'loan':
      return 'Loan';
    case 'product':
      return 'Product';
    default:
      return null;
  }
}
