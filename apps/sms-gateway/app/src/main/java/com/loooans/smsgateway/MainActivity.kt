package com.loooans.smsgateway

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {

    companion object {
        private const val PERMISSION_REQUEST_CODE = 100
    }

    private lateinit var statusText: TextView
    private lateinit var lastSmsText: TextView
    private lateinit var smsCountText: TextView
    private lateinit var toggleButton: Button

    private var isServiceRunning = false

    private val statusReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val status = intent?.getStringExtra(SmsGatewayService.EXTRA_STATUS) ?: "unknown"
            val lastSms = intent?.getStringExtra(SmsGatewayService.EXTRA_LAST_SMS) ?: "None"
            val count = intent?.getIntExtra(SmsGatewayService.EXTRA_SMS_COUNT, 0) ?: 0

            statusText.text = "Status: $status"
            lastSmsText.text = "Last SMS sent to: $lastSms"
            smsCountText.text = "Total SMS sent: $count"
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val layout = android.widget.LinearLayout(this).apply {
            orientation = android.widget.LinearLayout.VERTICAL
            setPadding(48, 48, 48, 48)
        }

        val titleText = TextView(this).apply {
            text = "Loooans SMS Gateway"
            textSize = 24f
            setPadding(0, 0, 0, 32)
        }
        layout.addView(titleText)

        statusText = TextView(this).apply {
            text = "Status: Stopped"
            textSize = 16f
            setPadding(0, 0, 0, 16)
        }
        layout.addView(statusText)

        lastSmsText = TextView(this).apply {
            text = "Last SMS sent to: None"
            textSize = 14f
            setPadding(0, 0, 0, 8)
        }
        layout.addView(lastSmsText)

        smsCountText = TextView(this).apply {
            text = "Total SMS sent: 0"
            textSize = 14f
            setPadding(0, 0, 0, 32)
        }
        layout.addView(smsCountText)

        toggleButton = Button(this).apply {
            text = "Start Gateway"
            setOnClickListener { toggleService() }
        }
        layout.addView(toggleButton)

        setContentView(layout)

        requestPermissions()
    }

    override fun onResume() {
        super.onResume()
        registerReceiver(
            statusReceiver,
            IntentFilter(SmsGatewayService.ACTION_STATUS_UPDATE),
            RECEIVER_NOT_EXPORTED,
        )
    }

    override fun onPause() {
        super.onPause()
        unregisterReceiver(statusReceiver)
    }

    private fun requestPermissions() {
        val permissions = mutableListOf<String>()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.SEND_SMS)
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (permissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(
                this,
                permissions.toTypedArray(),
                PERMISSION_REQUEST_CODE,
            )
        }
    }

    private fun toggleService() {
        if (isServiceRunning) {
            stopService(Intent(this, SmsGatewayService::class.java))
            isServiceRunning = false
            toggleButton.text = "Start Gateway"
            statusText.text = "Status: Stopped"
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                statusText.text = "Status: SMS permission required"
                requestPermissions()
                return
            }

            startForegroundService(Intent(this, SmsGatewayService::class.java))
            isServiceRunning = true
            toggleButton.text = "Stop Gateway"
            statusText.text = "Status: Starting..."
        }
    }
}
