package com.loooans.smsgateway

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OtpEntryTest {

    private fun validOtpMap(): Map<String, Any?> = mapOf(
        "objective" to "mobile_number",
        "sms_status" to "pending",
        "phone" to "+639171234567",
        "message" to "Your Loooans OTP is 123456.",
    )

    // --- fromMap parsing tests ---

    @Test
    fun `fromMap returns OtpEntry for valid data`() {
        val entry = OtpEntry.fromMap("abc123", validOtpMap())

        assertNotNull(entry)
        assertEquals("abc123", entry!!.hash)
        assertEquals("+639171234567", entry.phone)
        assertEquals("Your Loooans OTP is 123456.", entry.message)
        assertEquals("mobile_number", entry.objective)
        assertEquals("pending", entry.smsStatus)
    }

    @Test
    fun `fromMap returns null when key is null`() {
        val entry = OtpEntry.fromMap(null, validOtpMap())
        assertNull(entry)
    }

    @Test
    fun `fromMap returns null when objective is missing`() {
        val data = validOtpMap().toMutableMap().apply { remove("objective") }
        val entry = OtpEntry.fromMap("abc123", data)
        assertNull(entry)
    }

    @Test
    fun `fromMap returns null when phone is missing`() {
        val data = validOtpMap().toMutableMap().apply { remove("phone") }
        val entry = OtpEntry.fromMap("abc123", data)
        assertNull(entry)
    }

    @Test
    fun `fromMap returns null when message is missing`() {
        val data = validOtpMap().toMutableMap().apply { remove("message") }
        val entry = OtpEntry.fromMap("abc123", data)
        assertNull(entry)
    }

    @Test
    fun `fromMap allows null sms_status`() {
        val data = validOtpMap().toMutableMap().apply { remove("sms_status") }
        val entry = OtpEntry.fromMap("abc123", data)

        assertNotNull(entry)
        assertNull(entry!!.smsStatus)
    }

    @Test
    fun `fromMap returns null when objective is wrong type`() {
        val data = validOtpMap().toMutableMap().apply { put("objective", 123) }
        val entry = OtpEntry.fromMap("abc123", data)
        assertNull(entry)
    }

    @Test
    fun `fromMap returns null when phone is wrong type`() {
        val data = validOtpMap().toMutableMap().apply { put("phone", 123) }
        val entry = OtpEntry.fromMap("abc123", data)
        assertNull(entry)
    }

    @Test
    fun `fromMap returns null when message is wrong type`() {
        val data = validOtpMap().toMutableMap().apply { put("message", true) }
        val entry = OtpEntry.fromMap("abc123", data)
        assertNull(entry)
    }

    @Test
    fun `fromMap ignores extra fields`() {
        val data = validOtpMap().toMutableMap().apply {
            put("extra_field", "ignored")
            put("otp", "123456")
            put("userId", "user1")
        }
        val entry = OtpEntry.fromMap("abc123", data)

        assertNotNull(entry)
        assertEquals("abc123", entry!!.hash)
    }

    // --- shouldProcess filtering tests ---

    @Test
    fun `shouldProcess returns true for mobile_number objective with pending status`() {
        val entry = OtpEntry(
            hash = "abc123",
            phone = "+639171234567",
            message = "OTP: 123456",
            objective = "mobile_number",
            smsStatus = "pending",
            expireAt = null,
        )
        assertTrue(entry.shouldProcess())
    }

    @Test
    fun `shouldProcess returns false for email objective`() {
        val entry = OtpEntry(
            hash = "abc123",
            phone = "+639171234567",
            message = "OTP: 123456",
            objective = "email",
            smsStatus = "pending",
            expireAt = null,
        )
        assertFalse(entry.shouldProcess())
    }

    @Test
    fun `shouldProcess returns false for sent status`() {
        val entry = OtpEntry(
            hash = "abc123",
            phone = "+639171234567",
            message = "OTP: 123456",
            objective = "mobile_number",
            smsStatus = "sent",
            expireAt = null,
        )
        assertFalse(entry.shouldProcess())
    }

    @Test
    fun `shouldProcess returns false for failed status`() {
        val entry = OtpEntry(
            hash = "abc123",
            phone = "+639171234567",
            message = "OTP: 123456",
            objective = "mobile_number",
            smsStatus = "failed",
            expireAt = null,
        )
        assertFalse(entry.shouldProcess())
    }

    @Test
    fun `shouldProcess returns false for null status`() {
        val entry = OtpEntry(
            hash = "abc123",
            phone = "+639171234567",
            message = "OTP: 123456",
            objective = "mobile_number",
            smsStatus = null,
            expireAt = null,
        )
        assertFalse(entry.shouldProcess())
    }

    @Test
    fun `shouldProcess returns false for unknown objective`() {
        val entry = OtpEntry(
            hash = "abc123",
            phone = "+639171234567",
            message = "OTP: 123456",
            objective = "push_notification",
            smsStatus = "pending",
            expireAt = null,
        )
        assertFalse(entry.shouldProcess())
    }

    @Test
    fun `shouldProcess returns false when both objective and status are wrong`() {
        val entry = OtpEntry(
            hash = "abc123",
            phone = "+639171234567",
            message = "OTP: 123456",
            objective = "email",
            smsStatus = "sent",
            expireAt = null,
        )
        assertFalse(entry.shouldProcess())
    }

    // --- Data class equality ---

    @Test
    fun `data class equality works correctly`() {
        val entry1 = OtpEntry("hash1", "+639171234567", "msg", "mobile_number", "pending", null)
        val entry2 = OtpEntry("hash1", "+639171234567", "msg", "mobile_number", "pending", null)
        val entry3 = OtpEntry("hash2", "+639171234567", "msg", "mobile_number", "pending", null)

        assertEquals(entry1, entry2)
        assertFalse(entry1 == entry3)
    }

    // --- expiry tests ---

    @Test
    fun `fromMap parses expire_at as Long`() {
        val data = validOtpMap().toMutableMap().apply { put("expire_at", 1784877157691L) }
        val entry = OtpEntry.fromMap("abc123", data)
        assertEquals(1784877157691L, entry!!.expireAt)
    }

    @Test
    fun `fromMap tolerates missing expire_at`() {
        val entry = OtpEntry.fromMap("abc123", validOtpMap())
        assertNull(entry!!.expireAt)
    }

    @Test
    fun `isExpired is true past expire_at`() {
        val data = validOtpMap().toMutableMap().apply { put("expire_at", 1_000L) }
        val entry = OtpEntry.fromMap("abc123", data)!!
        assertTrue(entry.isExpired(nowMillis = 1_001L))
    }

    @Test
    fun `isExpired is false before expire_at`() {
        val data = validOtpMap().toMutableMap().apply { put("expire_at", 1_000L) }
        val entry = OtpEntry.fromMap("abc123", data)!!
        assertFalse(entry.isExpired(nowMillis = 999L))
    }

    @Test
    fun `isExpired is false when expire_at missing`() {
        val entry = OtpEntry.fromMap("abc123", validOtpMap())!!
        assertFalse(entry.isExpired(nowMillis = Long.MAX_VALUE))
    }
}
