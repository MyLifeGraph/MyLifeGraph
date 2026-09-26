package com.mylifegraph.app

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import java.security.MessageDigest

/** Installed package identity only; no download/install or storage permissions. */
object AppUpdateBridge {
    @Suppress("DEPRECATION")
    fun installedVersion(context: Context): Map<String, Any> {
        val flags = if (Build.VERSION.SDK_INT >= 28) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }
        val info = context.packageManager.getPackageInfo(context.packageName, flags)
        val signatures = if (Build.VERSION.SDK_INT >= 28) {
            info.signingInfo?.apkContentsSigners
        } else {
            info.signatures
        }
        val signature = signatures?.singleOrNull()
            ?: throw IllegalStateException("Package signer unavailable")
        val digest = MessageDigest.getInstance("SHA-256").digest(signature.toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return mapOf(
            "applicationId" to context.packageName,
            "versionName" to (info.versionName ?: ""),
            "versionCode" to code,
            "certificateSha256" to digest,
        )
    }
}
