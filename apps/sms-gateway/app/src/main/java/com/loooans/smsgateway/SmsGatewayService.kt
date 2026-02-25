package com.loooans.smsgateway

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.telephony.SmsManager
import android.util.Log
import com.google.firebase.database.ChildEventListener
import com.google.firebase.database.DataSnapshot
import com.google.firebase.database.DatabaseError
import com.google.firebase.database.ServerValue
import kotlinx.coroutines.*
import java.util.*

class SmsGatewayService : Service() {

    companion object {
        private const val TAG = "SmsGatewayService"
        private const val CHANNEL_ID = "sms_gateway_channel"
        private const val NOTIFICATION_ID = 1
        const val ACTION_STATUS_UPDATE = "com.loooans.smsgateway.STATUS_UPDATE"
        const val EXTRA_STATUS = "status"
        const val EXTRA_LAST_SMS = "last_sms"
        const val EXTRA_SMS_COUNT = "sms_count"
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var otpListener: ChildEventListener? = null
    private var heartbeatJob: Job? = null
    private var smsCount = 0
    private var lastSmsSentTo: String? = null
    private val deviceId: String by lazy {
        android.provider.Settings.Secure.getString(contentResolver, android.provider.Settings.Secure.ANDROID_ID)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Starting..."))
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
        serviceScope.launch {
            FirebaseConfig.database.reference
                .child("gateway_status")
                .child(deviceId)
                .child("status")
                .setValue("offline")
        }
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

        serviceScope.launch {
            sendSms(entry.hash, entry.phone, entry.message)
        }
    }

    private suspend fun sendSms(hash: String, phone: String, message: String) {
        try {
            val smsManager = getSystemService(SmsManager::class.java)
            val parts = smsManager.divideMessage(message)

            if (parts.size > 1) {
                smsManager.sendMultipartTextMessage(phone, null, parts, null, null)
            } else {
                smsManager.sendTextMessage(phone, null, message, null, null)
            }

            // Update RTDB: mark as sent
            val updates = mapOf<String, Any?>(
                "sms_status" to "sent",
                "sent_at" to ServerValue.TIMESTAMP,
                "error" to null,
            )
            FirebaseConfig.database.reference
                .child("otp")
                .child(hash)
                .updateChildren(updates)
                .addOnFailureListener { e ->
                    Log.e(TAG, "Failed to update sms_status", e)
                }

            smsCount++
            lastSmsSentTo = phone
            updateNotification("Online - Sent $smsCount SMS(s)")
            broadcastStatus("online")
            Log.i(TAG, "SMS sent to $phone for hash $hash")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send SMS to $phone", e)

            val updates = mapOf<String, Any?>(
                "sms_status" to "failed",
                "error" to e.message,
            )
            FirebaseConfig.database.reference
                .child("otp")
                .child(hash)
                .updateChildren(updates)
        }
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
