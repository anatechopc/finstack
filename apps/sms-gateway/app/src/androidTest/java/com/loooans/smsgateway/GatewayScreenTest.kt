package com.loooans.smsgateway

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class GatewayScreenTest {

    @get:Rule
    val composeTestRule = createComposeRule()

    @Test
    fun gatewayScreen_displaysTitle() {
        composeTestRule.setContent {
            MaterialTheme {
                GatewayScreen(
                    status = "Stopped",
                    lastSmsSentTo = "None",
                    smsCount = 0,
                    isServiceRunning = false,
                    onToggleService = {},
                )
            }
        }

        composeTestRule.onNodeWithTag("title")
            .assertIsDisplayed()
            .assertTextEquals("Loooans SMS Gateway")
    }

    @Test
    fun gatewayScreen_displaysInitialStatus() {
        composeTestRule.setContent {
            MaterialTheme {
                GatewayScreen(
                    status = "Stopped",
                    lastSmsSentTo = "None",
                    smsCount = 0,
                    isServiceRunning = false,
                    onToggleService = {},
                )
            }
        }

        composeTestRule.onNodeWithTag("status")
            .assertTextEquals("Status: Stopped")
        composeTestRule.onNodeWithTag("lastSms")
            .assertTextEquals("Last SMS sent to: None")
        composeTestRule.onNodeWithTag("smsCount")
            .assertTextEquals("Total SMS sent: 0")
    }

    @Test
    fun gatewayScreen_showsStartButtonWhenStopped() {
        composeTestRule.setContent {
            MaterialTheme {
                GatewayScreen(
                    status = "Stopped",
                    lastSmsSentTo = "None",
                    smsCount = 0,
                    isServiceRunning = false,
                    onToggleService = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Start Gateway")
            .assertIsDisplayed()
    }

    @Test
    fun gatewayScreen_showsStopButtonWhenRunning() {
        composeTestRule.setContent {
            MaterialTheme {
                GatewayScreen(
                    status = "Online - Listening for OTPs",
                    lastSmsSentTo = "None",
                    smsCount = 0,
                    isServiceRunning = true,
                    onToggleService = {},
                )
            }
        }

        composeTestRule.onNodeWithText("Stop Gateway")
            .assertIsDisplayed()
    }

    @Test
    fun gatewayScreen_toggleButtonCallsCallback() {
        var toggled = false

        composeTestRule.setContent {
            MaterialTheme {
                GatewayScreen(
                    status = "Stopped",
                    lastSmsSentTo = "None",
                    smsCount = 0,
                    isServiceRunning = false,
                    onToggleService = { toggled = true },
                )
            }
        }

        composeTestRule.onNodeWithTag("toggleButton").performClick()

        assertTrue(toggled)
    }

    @Test
    fun gatewayScreen_displaysOnlineStatus() {
        composeTestRule.setContent {
            MaterialTheme {
                GatewayScreen(
                    status = "online",
                    lastSmsSentTo = "+639171234567",
                    smsCount = 5,
                    isServiceRunning = true,
                    onToggleService = {},
                )
            }
        }

        composeTestRule.onNodeWithTag("status")
            .assertTextEquals("Status: online")
        composeTestRule.onNodeWithTag("lastSms")
            .assertTextEquals("Last SMS sent to: +639171234567")
        composeTestRule.onNodeWithTag("smsCount")
            .assertTextEquals("Total SMS sent: 5")
    }

    @Test
    fun gatewayScreen_updatesWhenStateChanges() {
        var status by mutableStateOf("Stopped")
        var lastSms by mutableStateOf("None")
        var count by mutableIntStateOf(0)
        var running by mutableStateOf(false)

        composeTestRule.setContent {
            MaterialTheme {
                Surface {
                    GatewayScreen(
                        status = status,
                        lastSmsSentTo = lastSms,
                        smsCount = count,
                        isServiceRunning = running,
                        onToggleService = {},
                    )
                }
            }
        }

        // Verify initial state
        composeTestRule.onNodeWithTag("status")
            .assertTextEquals("Status: Stopped")
        composeTestRule.onNodeWithText("Start Gateway")
            .assertIsDisplayed()

        // Simulate state change
        status = "online"
        lastSms = "+639999999999"
        count = 3
        running = true

        composeTestRule.waitForIdle()

        composeTestRule.onNodeWithTag("status")
            .assertTextEquals("Status: online")
        composeTestRule.onNodeWithTag("lastSms")
            .assertTextEquals("Last SMS sent to: +639999999999")
        composeTestRule.onNodeWithTag("smsCount")
            .assertTextEquals("Total SMS sent: 3")
        composeTestRule.onNodeWithText("Stop Gateway")
            .assertIsDisplayed()
    }

    @Test
    fun gatewayScreen_displaysPermissionRequiredStatus() {
        composeTestRule.setContent {
            MaterialTheme {
                GatewayScreen(
                    status = "SMS permission required",
                    lastSmsSentTo = "None",
                    smsCount = 0,
                    isServiceRunning = false,
                    onToggleService = {},
                )
            }
        }

        composeTestRule.onNodeWithTag("status")
            .assertTextEquals("Status: SMS permission required")
    }
}
