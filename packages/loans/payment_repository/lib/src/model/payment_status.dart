enum PaymentStatus {
  /// Borrower submitted proof; awaiting a lender's confirm/reject.
  pending('Pending'),

  /// A lender confirmed the payment (also the default for teller-created and
  /// legacy payment documents that predate this field).
  confirmed('Confirmed'),

  /// A lender rejected the proof; the borrower may resubmit.
  rejected('Rejected');

  const PaymentStatus(this.label);

  final String label;
}
