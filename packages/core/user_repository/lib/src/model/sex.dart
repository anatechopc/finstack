enum Sex {
  male('Male'),
  female('Female'),

  /// Fallback for user documents that have no (or an unrecognized) `sex` —
  /// keeps the field mandatory while letting old/incomplete accounts log in.
  other('Other');

  const Sex(this.label);

  final String label;
}
