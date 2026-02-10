enum CashPoolStatus {
  add_to_pool(label: 'Add to pool'),
  acknowledged_payment(label: 'Acknowledged payment'),
  change(label: 'Withdraw as change'),
  savings(label: 'Savings');

  const CashPoolStatus({required this.label});

  final String label;
}
