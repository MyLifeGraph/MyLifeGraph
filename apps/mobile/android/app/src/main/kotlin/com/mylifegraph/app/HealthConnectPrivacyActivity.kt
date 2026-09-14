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
            .setMessage("MyLifeGraph reads steps and sleep only after you agree. Enable sharing in Garmin Connect first.\n\nDaily totals are uploaded to your MyLifeGraph account and kept separate from manual check-ins. Your selected Coach can read them; relevant results may be sent to its AI provider. No routes, heart rate or raw sleep notes are read.\n\nSettings → Health Connect lets you stop uploads or delete imported data. You can revoke Android access in Health Connect. Account export and deletion include these observations.")
            .setPositiveButton("Close") { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }
}
