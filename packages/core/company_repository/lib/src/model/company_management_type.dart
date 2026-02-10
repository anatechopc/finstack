enum CompanyManagementType {
  app('App'),
  selfManaged('Self-managed');

  const CompanyManagementType(this.label);

  final String label;
}