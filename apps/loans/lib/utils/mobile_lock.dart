class MobileLockState {
  const MobileLockState({required this.locked, required this.daysLeft});

  final bool locked;
  final int daysLeft;
}

/// Computes the 90-day mobile-number edit lock state.
///
/// After a successful mobile verification, the number cannot be changed
/// for 90 days. Returns `locked=false, daysLeft=0` when the user has
/// never verified (timestamp is null) or the window has elapsed.
MobileLockState computeMobileLock(DateTime? verifiedAt) {
  if (verifiedAt == null) {
    return const MobileLockState(locked: false, daysLeft: 0);
  }
  final daysSince = DateTime.now().difference(verifiedAt).inDays;
  if (daysSince >= 90) {
    return const MobileLockState(locked: false, daysLeft: 0);
  }
  return MobileLockState(locked: true, daysLeft: 90 - daysSince);
}
