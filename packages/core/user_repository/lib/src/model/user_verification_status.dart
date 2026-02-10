enum UserVerificationStatus {
  /// user con
  unverified(
    label: 'Unverified',
    value: 0,
  ),
  aiVerified(
    label: 'AI verified',
    value: 1,
  ),
  mobileNumberVerified(
    label: 'Mobile number verified',
    value: 2,
  ),
  facebookProfileVerified(
    label: 'Facebook profile verified',
    value: 4,
  );

  const UserVerificationStatus({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;
}
