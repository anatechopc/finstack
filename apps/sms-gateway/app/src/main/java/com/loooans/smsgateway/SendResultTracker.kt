package com.loooans.smsgateway

/**
 * Aggregates per-part SMS sentIntent results into one terminal outcome.
 * Completes exactly once: Sent when all parts report OK, Failed on the
 * first error or on timeout. Pure Kotlin so it stays JVM-unit-testable —
 * callers translate Android result codes via [smsResultErrorName].
 */
class SendResultTracker(private val totalParts: Int) {

    sealed interface Outcome {
        data object Sent : Outcome
        data class Failed(val error: String) : Outcome
    }

    private var okCount = 0
    private var completed = false

    /** Records one part's result; returns the terminal outcome exactly once. */
    @Synchronized
    fun record(isOk: Boolean, errorName: String): Outcome? {
        if (completed) return null
        if (!isOk) {
            completed = true
            return Outcome.Failed(errorName)
        }
        okCount++
        if (okCount == totalParts) {
            completed = true
            return Outcome.Sent
        }
        return null
    }

    /** Marks the send failed if no terminal outcome arrived in time. */
    @Synchronized
    fun timeout(): Outcome? {
        if (completed) return null
        completed = true
        return Outcome.Failed("timeout waiting for send result")
    }
}

/**
 * Maps SmsManager sentIntent result codes to readable names. Values mirror
 * android.telephony.SmsManager.RESULT_ERROR_* — duplicated as plain ints so
 * this file needs no Android framework import.
 */
fun smsResultErrorName(code: Int): String = when (code) {
    1 -> "RESULT_ERROR_GENERIC_FAILURE (1)"
    2 -> "RESULT_ERROR_RADIO_OFF (2)"
    3 -> "RESULT_ERROR_NULL_PDU (3)"
    4 -> "RESULT_ERROR_NO_SERVICE (4)"
    5 -> "RESULT_ERROR_LIMIT_EXCEEDED (5)"
    else -> "RESULT_ERROR ($code)"
}

/** Highest number of message parts a single send may distinguish. */
const val MAX_SMS_PARTS = 16

/**
 * Unique PendingIntent requestCode for one (send attempt, message part) pair.
 *
 * PendingIntent identity ignores extras, so two sends would otherwise collide
 * and FLAG_UPDATE_CURRENT would alias them. The obvious alternative — making
 * each Intent unique with setData() — is a trap: a dynamically registered
 * IntentFilter that declares no data scheme matches *only* intents carrying no
 * data (IntentFilter.matchData), so a data Uri stops the result receiver from
 * ever firing and every send silently times out.
 */
fun sendRequestCode(sendId: Int, partIndex: Int): Int =
    sendId * MAX_SMS_PARTS + (partIndex and (MAX_SMS_PARTS - 1))
