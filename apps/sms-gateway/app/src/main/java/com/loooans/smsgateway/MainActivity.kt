package com.loooans.smsgateway

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {

    var status by mutableStateOf("Stopped")
    var lastSmsSentTo by mutableStateOf("None")
    var smsCount by mutableIntStateOf(0)
    var isServiceRunning by mutableStateOf(false)

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { _ -> }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        requestPermissions()

        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    GatewayScreen(
                        status = status,
                        lastSmsSentTo = lastSmsSentTo,
                        smsCount = smsCount,
                        isServiceRunning = isServiceRunning,
                        onToggleService = { toggleService() },
                    )
                }
            }

            StatusBroadcastReceiver { receivedStatus, receivedLastSms, receivedCount ->
                status = receivedStatus
                lastSmsSentTo = receivedLastSms
                smsCount = receivedCount
            }
        }
    }

    private fun requestPermissions() {
        val needed = mutableListOf<String>()

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(Manifest.permission.SEND_SMS)
        }

        if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED
        ) {
            needed.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        if (needed.isNotEmpty()) {
            permissionLauncher.launch(needed.toTypedArray())
        }
    }

    private fun toggleService() {
        if (isServiceRunning) {
            stopService(Intent(this, SmsGatewayService::class.java))
            isServiceRunning = false
            status = "Stopped"
        } else {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.SEND_SMS)
                != PackageManager.PERMISSION_GRANTED
            ) {
                status = "SMS permission required"
                requestPermissions()
                return
            }

            startForegroundService(Intent(this, SmsGatewayService::class.java))
            isServiceRunning = true
            status = "Starting..."
        }
    }
}

@Composable
fun GatewayScreen(
    status: String,
    lastSmsSentTo: String,
    smsCount: Int,
    isServiceRunning: Boolean,
    onToggleService: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        verticalArrangement = Arrangement.Top,
    ) {
        Text(
            text = "Loooans SMS Gateway",
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.testTag("title"),
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = "Status: $status",
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.testTag("status"),
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Last SMS sent to: $lastSmsSentTo",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.testTag("lastSms"),
        )

        Spacer(modifier = Modifier.height(4.dp))

        Text(
            text = "Total SMS sent: $smsCount",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.testTag("smsCount"),
        )

        Spacer(modifier = Modifier.height(24.dp))

        Button(
            onClick = onToggleService,
            modifier = Modifier
                .fillMaxWidth()
                .testTag("toggleButton"),
            colors = if (isServiceRunning) {
                ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.error)
            } else {
                ButtonDefaults.buttonColors()
            },
        ) {
            Text(text = if (isServiceRunning) "Stop Gateway" else "Start Gateway")
        }
    }
}

@Composable
fun StatusBroadcastReceiver(
    onStatusUpdate: (status: String, lastSms: String, count: Int) -> Unit,
) {
    val context = LocalContext.current

    DisposableEffect(Unit) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                val status = intent?.getStringExtra(SmsGatewayService.EXTRA_STATUS) ?: "unknown"
                val lastSms = intent?.getStringExtra(SmsGatewayService.EXTRA_LAST_SMS) ?: "None"
                val count = intent?.getIntExtra(SmsGatewayService.EXTRA_SMS_COUNT, 0) ?: 0
                onStatusUpdate(status, lastSms, count)
            }
        }

        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(SmsGatewayService.ACTION_STATUS_UPDATE),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )

        onDispose {
            context.unregisterReceiver(receiver)
        }
    }
}
