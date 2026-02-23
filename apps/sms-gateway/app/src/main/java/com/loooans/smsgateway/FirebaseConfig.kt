package com.loooans.smsgateway

import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.database.FirebaseDatabase
import kotlinx.coroutines.tasks.await

object FirebaseConfig {
    val database: FirebaseDatabase
        get() = FirebaseDatabase.getInstance()

    val auth: FirebaseAuth
        get() = FirebaseAuth.getInstance()

    suspend fun signIn() {
        if (auth.currentUser == null) {
            auth.signInWithEmailAndPassword(BuildConfig.GATEWAY_EMAIL, BuildConfig.GATEWAY_PASSWORD).await()
        }
    }

    fun signOut() {
        auth.signOut()
    }
}
