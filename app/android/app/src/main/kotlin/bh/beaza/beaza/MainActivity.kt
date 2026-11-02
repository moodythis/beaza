package bh.beaza.beaza

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** The app screen: channels, permission dialogs, and new-SMS pings. */
class MainActivity : FlutterActivity(), PermissionRequester {
    private var pendingSms: MethodChannel.Result? = null
    private var pendingNotify: MethodChannel.Result? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        Channels.attach(this, messenger, this)
        uiAlive = true

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

    override fun requestSms(result: MethodChannel.Result) {
        if (Channels.hasSms(this)) {
            result.success(true)
            return
        }
        if (pendingSms != null) {
            result.error("busy", "A permission request is already open", null)
            return
        }
        pendingSms = result
        requestPermissions(
            arrayOf(Manifest.permission.READ_SMS, Manifest.permission.RECEIVE_SMS),
            SMS_PERMISSION_REQUEST,
        )
    }

    override fun requestNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingNotify != null) {
            result.error("busy", "A permission request is already open", null)
            return
        }
        pendingNotify = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFY_PERMISSION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            SMS_PERMISSION_REQUEST -> {
                pendingSms?.success(Channels.hasSms(this))
                pendingSms = null
            }
            NOTIFY_PERMISSION_REQUEST -> {
                pendingNotify?.success(
                    grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED,
                )
                pendingNotify = null
            }
        }
    }

    /** While the screen exists it handles new SMS itself (no background run). */
    private fun startListening(events: EventChannel.EventSink) {
        stopListening()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                events.success(System.currentTimeMillis())
            }
        }
        val filter = IntentFilter(SmsReceiver.SMS_RECEIVED)
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
        uiAlive = false
        super.onDestroy()
    }

    companion object {
        private const val SMS_PERMISSION_REQUEST = 4101
        private const val NOTIFY_PERMISSION_REQUEST = 4102

        /** True while the app screen's engine is running. */
        @Volatile
        var uiAlive = false
    }
}
