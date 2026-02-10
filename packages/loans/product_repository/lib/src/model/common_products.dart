enum CommonProducts {
  personalLoan(label: 'Personal loan'),
  businessLoan(label: 'Business loan'),
  emergencyLoan(label: 'Emergency loan');

  const CommonProducts({ required this.label});

  final String label;

  // label should be in exact case.
  static bool isOthers(String label) {
    return CommonProducts.values.map((val) => val.label).contains(label);
  }
}