enum LoanStatus {
  pending('Pending'),
  declined('Declined'),
  approved('Approved'),
  payment_submitted('Payment submitted'),
  paid_on_time('Paid (on time)'),
  paid_late('Paid (late)'),
  not_paid('Not paid'),
  not_paid_overdue('Not paid (overdue)'),
  completed('Fully paid'),
  bad_debt('Bad debt'),
  ;

  const LoanStatus(this.label);

  final String label;
}
