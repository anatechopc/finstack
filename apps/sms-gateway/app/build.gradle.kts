import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.loooans.smsgateway"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.loooans.smsgateway"
        minSdk = 31
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "SMS Gateway (Dev)")
            buildConfigField("String", "GATEWAY_PASSWORD", "\"${localProperties.getProperty("gateway.password", "")}\"")
            buildConfigField("String", "GATEWAY_EMAIL", "\"${localProperties.getProperty("gateway.email", "")}\"")
        }
        release {
            isMinifyEnabled = false
            resValue("string", "app_name", "Loooans SMS Gateway")
            buildConfigField("String", "GATEWAY_PASSWORD", "\"${localProperties.getProperty("gateway.password", "")}\"")
            buildConfigField("String", "GATEWAY_EMAIL", "\"${localProperties.getProperty("gateway.email", "")}\"")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        viewBinding = true
        buildConfig = true
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.9.0"))
    implementation("com.google.firebase:firebase-database")
    implementation("com.google.firebase:firebase-auth")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")

    testImplementation("junit:junit:4.13.2")
    testImplementation("io.mockk:mockk:1.13.13")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
}
