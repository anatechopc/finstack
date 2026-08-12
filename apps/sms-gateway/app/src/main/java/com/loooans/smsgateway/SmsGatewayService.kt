package com.loooans.smsgateway

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.IBinder
import android.telephony.SmsManager
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.firebase.database.ChildEventListener
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.ServerValue
import kotlinx.coroutines.*
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

class SmsGatewayService : Service() {

    companion object {
        private const val TAG = "SmsGatewayService"
        private const val CHANNEL_ID = "sms_gateway_channel"
        private const val NOTIFICATION_ID = 1
        const val ACTION_STATUS_UPDATE = "com.loooans.smsgateway.STATUS_UPDATE"
        const val EXTRA_STATUS = "status"
        const val EXTRA_LAST_SMS = "last_sms"
        const val EXTRA_SMS_COUNT = "sms_count"
        private const val ACTION_SMS_SENT = "com.loooans.smsgateway.SMS_SENT"
        private const val EXTRA_HASH = "hash"
        private const val EXTRA_SEND_ID = "send_id"
        private const val SEND_RESULT_TIMEOUT_MS = 60_000L

        // Terminal `error` strings written to /otp/<hash> when no radio result
        // decided the outcome. Kept as constants so operators can grep them.
        const val ERROR_EXPIRED = "otp expired before the gateway could send it"
        const val ERROR_NO_PARTS = "message body produced no SMS parts"
        const val ERROR_GATEWAY_STOPPED = "gateway stopped before the send result arrived"
    }

    /**
     * One in-flight send. [id] identifies this specific attempt so a late
     * result from a previous attempt for the same hash cannot be recorded
     * against its successor.
     */
    private data class InFlightSend(
        val id: Int,
        val tracker: SendResultTracker,
        val phone: String,
    )

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var otpListener: ChildEventListener? = null
    private var heartbeatJob: Job? = null
    private var smsCount = 0
    private var lastSmsSentTo: String? = null
    private val deviceId: String by lazy {
        android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID)
    }
    private val trackers = ConcurrentHashMap<String, InFlightSend>()
    private val sendIdCounter = AtomicInteger(0)

    private val smsSentReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            // Runs on the main thread; RTDB writes below are async, so this
            // stays cheap. Guarded because an uncaught throw here would kill
            // the process.
            try {
                val hash = intent.getStringExtra(EXTRA_HASH) ?: return
                val sendId = intent.getIntExtra(EXTRA_SEND_ID, -1)
                val inFlight = trackers[hash]
                if (inFlight == null) {
                    Log.w(TAG, "Send result for $hash (send $sendId) arrived with no tracker; result discarded")
                    return
                }
                if (inFlight.id != sendId) {
                    Log.w(TAG, "Ignoring stale result for $hash from send $sendId (current is ${inFlight.id})")
                    return
                }
                val isOk = resultCode == Activity.RESULT_OK
                when (val outcome = inFlight.tracker.record(isOk, smsResultErrorName(resultCode))) {
                    is SendResultTracker.Outcome.Sent ->
                        if (trackers.remove(hash, inFlight)) markSent(hash, inFlight.phone)
                    is SendResultTracker.Outcome.Failed ->
                        if (trackers.remove(hash, inFlight)) markFailed(hash, outcome.error)
                    null -> Unit // waiting for remaining parts, or already completed
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to handle SMS send result", e)
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Starting..."))
        ContextCompat.registerReceiver(
            this,
            smsSentReceiver,
            IntentFilter(ACTION_SMS_SENT),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        serviceScope.launch {
            try {
                FirebaseConfig.signIn()
                startListeningForOtps()
                startHeartbeat()
                updateNotification("Online - Listening for OTPs")
                broadcastStatus("online")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start service", e)
                updateNotification("Error: ${e.message}")
                broadcastStatus("error")
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        otpListener?.let {
            FirebaseConfig.database.reference.child("otp").removeEventListener(it)
        }
        heartbeatJob?.cancel()
        try {
            unregisterReceiver(smsSentReceiver)
        } catch (e: IllegalArgumentException) {
            // onCreate failed before registration; nothing to unregister.
            Log.w(TAG, "SMS result receiver was not registered", e)
        }

        // Cancelling serviceScope below kills the watchdog coroutines, so any
        // send still awaiting a radio result would otherwise be left at
        // "pending" forever. Give each one a terminal status first.
        for (hash in trackers.keys.toList()) {
            trackers.remove(hash)?.let { markFailed(hash, ERROR_GATEWAY_STOPPED) }
        }

        // Called directly rather than inside serviceScope: the launch below
        // used to be cancelled by serviceScope.cancel() before it ever ran, so
        // the device never actually went offline. Firebase manages its own
        // threads, so this survives the cancellation.
        FirebaseConfig.database.reference
            .child("gateway_status")
            .child(deviceId)
            .child("status")
            .setValue("offline")

        serviceScope.cancel()
        super.onDestroy()
    }

    private fun startListeningForOtps() {
        val otpRef = FirebaseConfig.database.reference.child("otp")

        otpListener = object : ChildEventListener {
            override fun onChildAdded(snapshot: DataSnapshot, previousChildName: String?) {
                handleOtpEntry(snapshot)
            }

            override fun onChildChanged(snapshot: DataSnapshot, previousChildName: String?) {
                // Only handle if status changed back to pending (e.g., resend)
                val smsStatus = snapshot.child("sms_status").getValue(String::class.java)
                if (smsStatus == "pending") {
                    handleOtpEntry(snapshot)
                }
            }

            override fun onChildRemoved(snapshot: DataSnapshot) {}
            override fun onChildMoved(snapshot: DataSnapshot, previousChildName: String?) {}
            override fun onCancelled(error: DatabaseError) {
                Log.e(TAG, "OTP listener cancelled", error.toException())
            }
        }

        otpRef.addChildEventListener(otpListener!!)
    }

    private fun handleOtpEntry(snapshot: DataSnapshot) {
        val data = mutableMapOf<String, Any?>()
        for (child in snapshot.children) {
            data[child.key!!] = child.value
        }

        val entry = OtpEntry.fromMap(snapshot.key, data) ?: return
        if (!entry.shouldProcess()) return

        serviceScope.launch { sendSms(entry) }
    }

    private fun sendSms(entry: OtpEntry) {
        val hash = entry.hash
        if (entry.isExpired(System.currentTimeMillis())) {
            // Must still write a terminal status: verify_otp only deletes the
            // entry on success, so returning silently would leave it "pending"
            // forever and poison the stuck-at-pending health check.
            Log.i(TAG, "Skipping expired OTP entry $hash")
            markFailed(hash, ERROR_EXPIRED)
            return
        }

        var claimed: InFlightSend? = null
        try {
            val smsManager = getSystemService(SmsManager::class.java)
            val parts = smsManager.divideMessage(entry.message)
            if (parts.isNullOrEmpty()) {
                markFailed(hash, ERROR_NO_PARTS)
                return
            }

            val sendId = sendIdCounter.incrementAndGet()
            val candidate = InFlightSend(sendId, SendResultTracker(parts.size), entry.phone)
            // Atomic claim. A containsKey/put pair would let two concurrent
            // deliveries of the same hash both pass and send a duplicate SMS.
            if (trackers.putIfAbsent(hash, candidate) != null) {
                Log.i(TAG, "Send already in flight for $hash, skipping duplicate")
                return
            }
            claimed = candidate

            // One PendingIntent per part, made unique by requestCode. Do NOT
            // put a data Uri on these intents: a dynamically registered
            // IntentFilter with no data scheme matches only intents that carry
            // no data (IntentFilter.matchData), so a data Uri would stop the
            // receiver from ever firing and every send would time out.
            val sentIntents = ArrayList<PendingIntent>(parts.size)
            for (i in 0 until parts.size) {
                val intent = Intent(ACTION_SMS_SENT)
                    .setPackage(packageName)
                    .putExtra(EXTRA_HASH, hash)
                    .putExtra(EXTRA_SEND_ID, sendId)
                sentIntents.add(
                    PendingIntent.getBroadcast(
                        this,
                        sendRequestCode(sendId, i),
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }

            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(entry.phone, null, parts, sentIntents, null)
            } else {
                smsManager.sendTextMessage(entry.phone, null, entry.message, sentIntents[0], null)
            }
            Log.i(TAG, "SMS handed to radio for $hash (${parts.size} part(s), send $sendId), awaiting result")

            serviceScope.launch {
                delay(SEND_RESULT_TIMEOUT_MS)
                candidate.tracker.timeout()?.let { outcome ->
                    // Only the tracker that still owns the slot may write a
                    // terminal status; otherwise a resend's success could be
                    // clobbered by this attempt's watchdog.
                    if (trackers.remove(hash, candidate)) {
                        markFailed(hash, (outcome as SendResultTracker.Outcome.Failed).error)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send SMS for $hash", e)
            claimed?.let { trackers.remove(hash, it) }
            markFailed(hash, e.message ?: e.javaClass.simpleName)
        }
    }

    private fun markSent(hash: String, phone: String) {
        val updates = mapOf<String, Any?>(
            "sms_status" to "sent",
            "sent_at" to ServerValue.TIMESTAMP,
            "error" to null,
        )
        FirebaseConfig.database.reference
            .child("otp").child(hash)
            .updateChildren(updates)
            .addOnFailureListener { e -> Log.e(TAG, "Failed to update sms_status", e) }

        // Recorded on confirmation, not at radio hand-off, so the on-device
        // status screen cannot report a failed send as the last successful one.
        lastSmsSentTo = phone
        smsCount++
        updateNotification("Online - Sent $smsCount SMS(s)")
        broadcastStatus("online")
        Log.i(TAG, "SMS confirmed sent for hash $hash")
    }

    private fun markFailed(hash: String, error: String) {
        val updates = mapOf<String, Any?>(
            "sms_status" to "failed",
            "error" to error,
        )
        FirebaseConfig.database.reference
            .child("otp").child(hash)
            .updateChildren(updates)
            .addOnFailureListener { e -> Log.e(TAG, "Failed to update sms_status", e) }
        // Broadcast too, so the UI reflects failures instead of silently
        // holding the last success.
        broadcastStatus("online")
        Log.w(TAG, "SMS failed for hash $hash: $error")
    }

    private fun startHeartbeat() {
        heartbeatJob = serviceScope.launch {
            while (isActive) {
                try {
                    val statusRef = FirebaseConfig.database.reference
                        .child("gateway_status")
                        .child(deviceId)

                    val heartbeat = mapOf<String, Any>(
                        "last_heartbeat" to ServerValue.TIMESTAMP,
                        "device_name" to (android.os.Build.MODEL ?: "Unknown"),
                        "status" to "online",
                    )
                    statusRef.updateChildren(heartbeat)
                } catch (e: Exception) {
                    Log.e(TAG, "Heartbeat failed", e)
                }
                delay(30_000) // 30 seconds
            }
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "SMS Gateway Service",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps the SMS gateway service running"
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(text: String): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Loooans SMS Gateway")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun broadcastStatus(status: String) {
        val intent = Intent(ACTION_STATUS_UPDATE).apply {
            putExtra(EXTRA_STATUS, status)
            putExtra(EXTRA_LAST_SMS, lastSmsSentTo ?: "None")
            putExtra(EXTRA_SMS_COUNT, smsCount)
        }
        sendBroadcast(intent)
    }
}
