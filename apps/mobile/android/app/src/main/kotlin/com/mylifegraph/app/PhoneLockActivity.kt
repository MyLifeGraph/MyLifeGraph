package com.mylifegraph.app

import android.app.AlertDialog
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import android.content.Context
import android.content.Intent
import android.nfc.NfcAdapter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.Toast
import java.security.MessageDigest

/** Local control UI can always reach the dialer, even during a pending NFC scan. */
class PhoneLockActivity : ComponentActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var screen: PhoneLockScreenView
    private lateinit var store: PhoneLockStore
    private var scanning = false
    private var generation = 0
    private var removingChip = false
    private val tick = object : Runnable {
        override fun run() {
            val state = store.status()
            if (state["active"] != true && !removingChip) { leave(); return }
            screen.update(state); handler.postDelayed(this, 1000)
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        store = PhoneLockStore(this)
        screen = PhoneLockScreenView(this, BlockingPlans(this).custom(), ::action)
        setContentView(screen)
        onBackPressedDispatcher.addCallback(this, object: OnBackPressedCallback(true) {
            override fun handleOnBackPressed() { leave() }
        })
    }
    override fun onResume() {
        super.onResume()
        currentActivity=java.lang.ref.WeakReference(this)
        FocusBlockAccessibilityService.onAppResumed(applicationContext)
        handler.removeCallbacks(tick); handler.post(tick)
        if(intent.getBooleanExtra("scan", false)) { intent.removeExtra("scan"); scan() }
    }
    override fun onPause() {
        stopScan(); handler.removeCallbacks(tick); super.onPause()
    }
    override fun onDestroy() { handler.removeCallbacksAndMessages(null); super.onDestroy() }
    override fun onWindowFocusChanged(hasFocus:Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if(hasFocus) FocusTimerNotifications.askPending(this)
    }
    override fun onRequestPermissionsResult(requestCode:Int,permissions:Array<String>,grantResults:IntArray) {
        super.onRequestPermissionsResult(requestCode,permissions,grantResults)
        if(requestCode==FocusTimerNotifications.PERMISSION_REQUEST) runCatching { FocusTimerNotifications.sync(this) }
    }
    private fun action(name: String) {
        when(name) {
            "phone" -> PhoneLockSafety.openPhone(this)
            "scan" -> if(scanning) stopScan() else scan()
            "apps" -> allowedApps()
            "recovery" -> recovery()
        }
    }
    private fun dialog() = AlertDialog.Builder(this,
        if(BlockingPlans(this).custom().optString("tone")=="light") android.R.style.Theme_DeviceDefault_Light_Dialog_Alert
        else android.R.style.Theme_DeviceDefault_Dialog_Alert)
    private fun present(builder: AlertDialog.Builder) {
        val dialog=builder.create()
        dialog.setOnShowListener {
            val pair=BlockingScreenIcon.colors(BlockingPlans(this).custom().optString("tone","glass"))
            dialog.window?.setBackgroundDrawable(android.graphics.drawable.GradientDrawable().apply {
                setColor(android.graphics.Color.parseColor(pair.first)); cornerRadius=24*resources.displayMetrics.density
                setStroke(resources.displayMetrics.density.toInt().coerceAtLeast(1),0x556F8194)
            })
        }
        dialog.show()
    }
    private fun allowedApps() {
        val state = store.status()
        val apps = (state["allowedApps"] as List<*>).filterIsInstance<String>()
        val labels = listOf("Phone and emergency calls", "Alarms and essential functions") + apps.map { pkg ->
            runCatching { packageManager.getApplicationLabel(packageManager.getApplicationInfo(pkg,0)).toString() }.getOrDefault(pkg)
        }
        present(dialog().setTitle("Allowed apps").setItems(labels.toTypedArray()) { _, index ->
            if(index==0) PhoneLockSafety.openPhone(this)
            if(index>=2) packageManager.getLaunchIntentForPackage(apps[index-2])?.let { startActivity(it) }
        }.setNegativeButton("Close",null))
    }
    private fun recovery() {
        val state = store.status(); val id=state["id"] as String
        if(state["mode"] != "nfc") {
            present(dialog().setTitle("Recovery options").setMessage("Phone lock unlocks automatically when the timer ends. Phone and emergency calls remain available.")
                .setPositiveButton("Close",null)); return
        }
        if(state["recoveryStarted"] == true) {
            Toast.makeText(this,"Recovery timer continues in the background.",Toast.LENGTH_LONG).show(); return
        }
        present(dialog().setTitle("Recovery options")
            .setMessage("Use a saved backup chip, or unlock after a 15-minute recovery wait. The timer continues in the background.")
            .setNegativeButton("Cancel",null).setPositiveButton("Start recovery") { _, _ ->
                runCatching { store.recover(id); PhoneLockExpiryReceiver.reconcile(this) }.onFailure { Toast.makeText(this,it.message,Toast.LENGTH_LONG).show() }
                screen.update(store.status())
            })
    }
    private fun scan() {
        if(scanning || removingChip) return
        val state=store.status(); if(state["active"]!=true || state["mode"]!="nfc") return
        val adapter=NfcAdapter.getDefaultAdapter(this)
        if(adapter?.isEnabled!=true) { Toast.makeText(this,"Enable NFC first.",Toast.LENGTH_LONG).show(); return }
        val id=state["id"] as String; val turn=++generation
        scanning=true; screen.scanMessage("Hold your saved NFC chip nearby.", true)
        runCatching {
            adapter.enableReaderMode(this,{ tag -> handler.post {
                if(turn!=generation || !scanning) return@post
                try {
                    check(tag.id.isNotEmpty()) { "Use a chip with a stable identifier." }
                    val hash=MessageDigest.getInstance("SHA-256").digest(tag.id).joinToString("") { "%02x".format(it) }
                    // Keep reader ownership until physical removal, suppressing duplicate NDEF dispatch.
                    check(adapter.ignore(tag,500,{ handler.post { if(turn==generation) { removingChip=false; leave() } } },handler)) { "Remove the chip and try again." }
                    store.unlockNfc(id,hash)
                    runCatching { PhoneLockExpiryReceiver.reconcile(this) }
                    removingChip=true; screen.scanMessage("Chip recognized. Remove the chip.",false)
                    FocusBlockAccessibilityService.refreshOverlayIfRunning(this)
                } catch(e: Exception) {
                    stopScan(); Toast.makeText(this,e.message,Toast.LENGTH_LONG).show()
                }
            } }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_NFC_B or NfcAdapter.FLAG_READER_NFC_F or
                NfcAdapter.FLAG_READER_NFC_V or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,null)
            handler.postDelayed({ if(turn==generation && !removingChip) { stopScan(); Toast.makeText(this,"No chip scanned. Try again.",Toast.LENGTH_LONG).show() } },30000)
        }.onFailure { stopScan(); Toast.makeText(this,"Could not start NFC. Try again.",Toast.LENGTH_LONG).show() }
    }
    private fun stopScan() {
        ++generation; scanning=false; removingChip=false
        runCatching { NfcAdapter.getDefaultAdapter(this)?.disableReaderMode(this) }
        screen.scanMessage(null,false)
    }
    private fun leave() {
        startActivity(Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }
    companion object {
        private var currentActivity:java.lang.ref.WeakReference<PhoneLockActivity>?=null
        fun askPendingTimerPermission() { currentActivity?.get()?.let { if(!it.isFinishing) FocusTimerNotifications.askPending(it) } }
        fun open(context: Context, scan: Boolean=false) {
            context.startActivity(Intent(context,PhoneLockActivity::class.java).putExtra("scan",scan)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP))
        }
    }
}
