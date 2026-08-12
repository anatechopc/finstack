package com.loooans.smsgateway

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SendResultTrackerTest {

    @Test
    fun `single part ok completes as Sent`() {
        val tracker = SendResultTracker(totalParts = 1)
        assertEquals(SendResultTracker.Outcome.Sent, tracker.record(isOk = true, errorName = ""))
    }

    @Test
    fun `single part failure completes as Failed with error name`() {
        val tracker = SendResultTracker(totalParts = 1)
        val outcome = tracker.record(isOk = false, errorName = "RESULT_ERROR_LIMIT_EXCEEDED (5)")
        assertEquals(SendResultTracker.Outcome.Failed("RESULT_ERROR_LIMIT_EXCEEDED (5)"), outcome)
    }

    @Test
    fun `multipart completes only after all parts ok`() {
        val tracker = SendResultTracker(totalParts = 3)
        assertNull(tracker.record(isOk = true, errorName = ""))
        assertNull(tracker.record(isOk = true, errorName = ""))
        assertEquals(SendResultTracker.Outcome.Sent, tracker.record(isOk = true, errorName = ""))
    }

    @Test
    fun `multipart fails immediately on first failed part`() {
        val tracker = SendResultTracker(totalParts = 3)
        assertNull(tracker.record(isOk = true, errorName = ""))
        val outcome = tracker.record(isOk = false, errorName = "RESULT_ERROR_NO_SERVICE (4)")
        assertEquals(SendResultTracker.Outcome.Failed("RESULT_ERROR_NO_SERVICE (4)"), outcome)
    }

    @Test
    fun `record after completion returns null`() {
        val tracker = SendResultTracker(totalParts = 1)
        tracker.record(isOk = false, errorName = "RESULT_ERROR_GENERIC_FAILURE (1)")
        assertNull(tracker.record(isOk = true, errorName = ""))
    }

    @Test
    fun `timeout before completion fails with timeout error`() {
        val tracker = SendResultTracker(totalParts = 2)
        tracker.record(isOk = true, errorName = "")
        assertEquals(
            SendResultTracker.Outcome.Failed("timeout waiting for send result"),
            tracker.timeout(),
        )
    }

    @Test
    fun `timeout after completion returns null`() {
        val tracker = SendResultTracker(totalParts = 1)
        tracker.record(isOk = true, errorName = "")
        assertNull(tracker.timeout())
    }

    @Test
    fun `known result codes map to names`() {
        assertEquals("RESULT_ERROR_GENERIC_FAILURE (1)", smsResultErrorName(1))
        assertEquals("RESULT_ERROR_RADIO_OFF (2)", smsResultErrorName(2))
        assertEquals("RESULT_ERROR_NULL_PDU (3)", smsResultErrorName(3))
        assertEquals("RESULT_ERROR_NO_SERVICE (4)", smsResultErrorName(4))
        assertEquals("RESULT_ERROR_LIMIT_EXCEEDED (5)", smsResultErrorName(5))
        assertEquals("RESULT_ERROR (99)", smsResultErrorName(99))
    }

    @Test
    fun `request codes are unique across sends and parts`() {
        // Guards the replacement for the setData() scheme: PendingIntent
        // identity ignores extras, so if two in-flight sends could produce the
        // same requestCode, FLAG_UPDATE_CURRENT would alias them and a result
        // could be attributed to the wrong send.
        val seen = mutableSetOf<Int>()
        for (sendId in 1..500) {
            for (part in 0 until MAX_SMS_PARTS) {
                assertTrue(
                    "duplicate requestCode for send=$sendId part=$part",
                    seen.add(sendRequestCode(sendId, part)),
                )
            }
        }
        assertEquals(500 * MAX_SMS_PARTS, seen.size)
    }

    @Test
    fun `request codes differ between consecutive sends of the same part`() {
        assertNotEquals(sendRequestCode(1, 0), sendRequestCode(2, 0))
        assertNotEquals(sendRequestCode(41, 3), sendRequestCode(42, 3))
    }
}
