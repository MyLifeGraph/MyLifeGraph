import java.io.FileInputStream
import java.util.Properties

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
    testImplementation("junit:junit:4.13.2")
}
