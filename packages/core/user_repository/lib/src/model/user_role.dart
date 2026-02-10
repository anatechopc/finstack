/// user roles of the app.
enum UserRole {
  /// systems administrator
  appAdmin(label: 'System administrator'),

  /// users that are customers of
  /// our client
  customer(label: 'Customer'),

  /// loan provider administrator
  admin(label: 'Administrator'),

  /// loan provider loan officer
  /// manages loans, has the authority
  /// to accept or decline loans
  loanOfficer(label: 'Loan officer'),

  /// user from a loan provider that creates
  /// transaction for the provider. Transaction
  /// in the form of:
  ///   * Accepting payments
  ///   * Updates customer payment record.
  ///
  /// These users are usually created for
  /// Self-managed type companies.
  teller(label: 'Teller'),

  /// loan provider review moderator
  /// manages the reviews
  reviewModerator(label: 'Review moderator');

  const UserRole({ required this.label});

  final String label;

  static List<UserRole> get companyManagedRoles => [
        admin,
        loanOfficer,
        teller,
        reviewModerator,
      ];
}
