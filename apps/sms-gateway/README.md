# Loooans SMS Gateway

Android app that acts as an SMS gateway for Loooans OTP delivery.

## Setup

1. Place `google-services.json` in `app/` (from Firebase console for `loooans-dev-stg` or `loooans-prod`)
2. Update `FirebaseConfig.kt` with the gateway user password
3. Build: `./gradlew assembleDebug`
4. Install on the designated Android device

## How It Works

- Runs as a foreground service on a dedicated Android device
- Listens to Firebase RTDB `/otp/` for entries where `objective == "mobile_number"` and `sms_status == "pending"`
- Sends SMS via the device's SmsManager
- Updates `sms_status` to `"sent"` or `"failed"` in RTDB
- Sends heartbeat to `/gateway_status/{deviceId}` every 30 seconds

## Permissions

- `SEND_SMS` - Required to send SMS messages
- `FOREGROUND_SERVICE` - Required for persistent background service
- `POST_NOTIFICATIONS` - Required for foreground service notification
