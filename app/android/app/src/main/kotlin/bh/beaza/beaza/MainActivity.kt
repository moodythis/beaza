package bh.beaza.beaza

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridge between Android's SMS inbox and Dart.
 *
 * Privacy: listing returns only id, sender and date. Dart decides which
 * senders are banks, and only then asks for those message bodies. Nothing is
 * stored on the Android side, and the new-SMS event carries no content.
 */
class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingPermission: MethodChannel.Result? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "beaza/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSmsPermission())
                "requestPermission" -> requestSmsPermission(result)
                "listInbox" -> {
                    val since = call.argument<Number>("sinceMs")?.toLong() ?: 0L
                    inBackground(result) { SmsInbox.list(contentResolver, since) }
                }
                "readBodies" -> {
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    inBackground(result) { SmsInbox.bodies(contentResolver, ids) }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "beaza/sms_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startListening(events)
                }

                override fun onCancel(arguments: Any?) {
                    stopListening()
                }
            },
        )
    }

    private fun hasSmsPermission(): Boolean =
        checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.error("busy", "A permission request is already open", null)
            return
        }
        pendingPermission = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
            SMS_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SMS_PERMISSION_REQUEST) {
            pendingPermission?.success(hasSmsPermission())
            pendingPermission = null
        }
    }

    /** Only tells Dart that something arrived; Dart then scans the inbox. */
    private fun startListening(events: EventChannel.EventSink) {
        stopListening()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                events.success(System.currentTimeMillis())
            }
        }
        val filter = IntentFilter(SMS_RECEIVED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        smsReceiver = receiver
    }

    private fun stopListening() {
        smsReceiver?.let { unregisterReceiver(it) }
        smsReceiver = null
    }

    override fun onDestroy() {
        stopListening()
        super.onDestroy()
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any) {
        Thread {
            try {
                val value = work()
                mainHandler.post { result.success(value) }
            } catch (e: Exception) {
                mainHandler.post { result.error("sms", e.message, null) }
            }
        }.start()
    }

    companion object {
        private const val SMS_PERMISSION_REQUEST = 4101
        private const val SMS_RECEIVED = "android.provider.Telephony.SMS_RECEIVED"
    }
}
