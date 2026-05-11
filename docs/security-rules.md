# Firestore Security Rules

This document describes the Firestore security rules deployed for the **finstack** backend. Rules are sourced from `apps/loans/firestore.rules` and referenced by `apps/loans/firebase.json`. Deploy with:

```bash
cd apps/loans
firebase deploy --only firestore:rules --project <env>
```

## `users/{uid}` rules

### 90-day mobile-number lock

A `users/{uid}` document update is rejected if it changes `mobile_number` AND the existing `mobile_verified_at` is non-null AND less than 90 days old. This prevents number-hopping abuse after a successful mobile verification.

Pseudocode:

```
allow update: if (
  request.resource.data.mobile_number == resource.data.mobile_number ||
  resource.data.mobile_verified_at == null ||
  request.time.toMillis() - resource.data.mobile_verified_at.toMillis()
    >= duration.value(90, 'd').toMillis()
);
```

### Backend-only verification fields

Client writes that mutate `verificationStatus` or `mobile_verified_at` are rejected. These fields are written exclusively by:

- The `verifyOtp` Cloud Function (sets the `mobileNumberVerified` bit and `mobile_verified_at` on a successful verification — see `functions/loans/api/users/verify_otp.go`).
- The `userChanges` Firestore trigger (clears the bit and nulls the timestamp when `mobile_number` changes — see `functions/loans/triggers/user_changes.go`).

Both run with the Firebase Admin SDK, which bypasses security rules.

## Client-side parallel UX

The 90-day lock is mirrored in the client UI. The update-profile mobile field is disabled and shows "Editable in N days" while the user is inside the lock window — see `apps/loans/lib/features/users/widget/update_profile/update_profile_primary_details.dart` and `update_profile_portrait_personal_fields.dart`. The Firestore rule is the authoritative backstop.

## Testing

Emulator-based tests of these rules are tracked in [issue #134](https://github.com/anatechopc/loooans/issues/134) (combined with the broader bloc/widget test infrastructure work).

## Related

- Spec: `docs/superpowers/specs/2026-04-19-mobile-verification-design.md`
- Plan: `docs/superpowers/plans/2026-04-19-mobile-verification.md`
- Issue: [#13 — Verify user mobile number](https://github.com/anatechopc/loooans/issues/13)
