import java.io.FileInputStream
import java.util.Properties
import java.util.Base64
import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}
val signingKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val signingEnvironmentNames = mapOf(
    "keyAlias" to "ANDROID_KEY_ALIAS",
    "keyPassword" to "ANDROID_KEY_PASSWORD",
    "storeFile" to "ANDROID_KEYSTORE_PATH",
    "storePassword" to "ANDROID_KEYSTORE_PASSWORD",
)
val environmentSigning = signingKeys.associateWith { key ->
    System.getenv(signingEnvironmentNames.getValue(key))?.takeIf { it.isNotBlank() }
}
val propertySigning = signingKeys.associateWith { key ->
    keystoreProperties.getProperty(key)?.takeIf { it.isNotBlank() }
}
val hasAnyEnvironmentSigning = environmentSigning.values.any { it != null }
val hasAllEnvironmentSigning = environmentSigning.values.all { it != null }
val hasAnyPropertySigning = propertySigning.values.any { it != null }
val hasAllPropertySigning = propertySigning.values.all { it != null }
if (hasAnyEnvironmentSigning && !hasAllEnvironmentSigning) {
    throw GradleException("Android release-signing environment is incomplete.")
}
if (hasAnyPropertySigning && !hasAllPropertySigning) {
    throw GradleException("android/key.properties is missing a required value.")
}
val signingValues = when {
    hasAllEnvironmentSigning -> environmentSigning.mapValues { it.value!! }
    hasAllPropertySigning -> propertySigning.mapValues { it.value!! }
    else -> emptyMap()
}
val hasReleaseSigning = signingValues.isNotEmpty()
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
// Public Firebase client configuration, provided by CI or a gitignored local file.
// Never place a service-account key here. No Google Services/Analytics plugin needed.
val firebaseBase64 = System.getenv("FIREBASE_ANDROID_CONFIG_BASE64")?.takeIf { it.isNotBlank() }
val firebaseFile = file("google-services.json")
val firebaseText = firebaseBase64?.let { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
    ?: firebaseFile.takeIf { it.exists() }?.readText()
val firebaseConfig = firebaseText?.let { JsonSlurper().parseText(it) as Map<*, *> }
val firebaseProject = firebaseConfig?.get("project_info") as? Map<*, *>
val firebaseClient = (firebaseConfig?.get("client") as? List<*>)?.map { it as Map<*, *> }?.singleOrNull {
    val info = it["client_info"] as? Map<*, *>
    val android = info?.get("android_client_info") as? Map<*, *>
    android?.get("package_name") == "com.mylifegraph.app"
}
if (firebaseConfig != null && (firebaseProject?.get("project_id") != "mylifegraph-5d234" ||
    firebaseProject["project_number"] != "76944636936" || firebaseClient == null ||
    (firebaseClient["client_info"] as? Map<*, *>)?.get("mobilesdk_app_id") != "1:76944636936:android:3899180d908adc49e225bd" ||
    firebaseConfig.containsKey("private_key"))) {
    throw GradleException("Firebase Android client configuration does not match MyLifeGraph.")
}
if (releaseBuildRequested && !hasReleaseSigning) {
    throw GradleException(
        "Release signing is not configured. Add ignored android/key.properties and a private keystore before building a distributable release.",
    )
}

android {
    namespace = "com.mylifegraph.app"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mylifegraph.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        if (firebaseClient != null) {
            val info = firebaseClient["client_info"] as Map<*, *>
            val apiKey = ((firebaseClient["api_key"] as List<*>).first() as Map<*, *>)["current_key"] as String
            resValue("string", "google_app_id", info["mobilesdk_app_id"] as String)
            resValue("string", "gcm_defaultSenderId", firebaseProject!!["project_number"] as String)
            resValue("string", "project_id", firebaseProject["project_id"] as String)
            resValue("string", "google_api_key", apiKey)
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = signingValues.getValue("keyAlias")
                keyPassword = signingValues.getValue("keyPassword")
                storeFile = file(signingValues.getValue("storeFile"))
                storePassword = signingValues.getValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.google.firebase:firebase-messaging:25.0.1")
    testImplementation("junit:junit:4.13.2")
}
