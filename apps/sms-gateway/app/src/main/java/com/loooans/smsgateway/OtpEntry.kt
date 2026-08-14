package com.loooans.smsgateway

/**
 * Represents an OTP entry from Firebase RTDB.
 * Encapsulates the filtering and validation logic for SMS delivery.
 */
data class OtpEntry(
    val hash: String,
    val phone: String,
    val message: String,
    val objective: String,
    val smsStatus: String?,
    val expireAt: Long?,
) {
    /**
     * Returns true if this entry should be processed by the SMS gateway.
     * Only entries with objective "mobile_number" and sms_status "pending" should be sent.
     */
    fun shouldProcess(): Boolean = objective == "mobile_number" && smsStatus == "pending"

    /**
     * True when the entry's expire_at (int64 millis, house convention) is in
     * the past. Entries with no expire_at never count as expired.
     */
    fun isExpired(nowMillis: Long): Boolean = expireAt != null && expireAt < nowMillis

    companion object {
        /**
         * Parses an OTP entry from a map of RTDB fields.
         * Returns null if required fields (hash, objective, phone, message) are missing.
         */
        fun fromMap(key: String?, data: Map<String, Any?>): OtpEntry? {
            val hash = key ?: return null
            val objective = data["objective"] as? String ?: return null
            val phone = data["phone"] as? String ?: return null
            val message = data["message"] as? String ?: return null
            val smsStatus = data["sms_status"] as? String
            val expireAt = (data["expire_at"] as? Number)?.toLong()

            return OtpEntry(
                hash = hash,
                phone = phone,
                message = message,
                objective = objective,
                smsStatus = smsStatus,
                expireAt = expireAt,
            )
        }
    }
}
