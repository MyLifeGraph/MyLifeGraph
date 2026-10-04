package com.mylifegraph.app

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle

/** Always accessible from Android's Health Connect permission screen. */
class HealthConnectPrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlertDialog.Builder(this)
            .setTitle("Health Connect · optional")
            .setMessage("MyLifeGraph reads steps and sleep only after you agree. Enable sharing in your watch app first.\n\nDaily totals are uploaded to your MyLifeGraph account and kept separate from manual check-ins. Heart-rate and resting-heart-rate averages require additional consent and permissions. Your selected Coach can read imported data; relevant results may be sent to its AI provider. No routes, raw sleep notes or stress data are read. This is not medical advice.\n\nSettings → Health Connect lets you stop uploads, remove heart data or delete all imports. You can revoke Android access in Health Connect. Account export and deletion include these observations.")
            .setPositiveButton("Close") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }
}
