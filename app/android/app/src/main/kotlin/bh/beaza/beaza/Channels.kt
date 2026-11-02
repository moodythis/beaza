package bh.beaza.beaza

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Asking for a permission needs a screen, so only the activity can do it. */
interface PermissionRequester {
    fun requestSms(result: MethodChannel.Result)
    fun requestNotifications(result: MethodChannel.Result)
}

/**
 * The method channels Dart uses, shared by the app screen and the background
 * run started by [SmsReceiver].
 *
 * Privacy: listing returns only id, sender and date. Dart decides which
 * senders are banks, and only then asks for those message bodies. Nothing is
 * stored on the Android side.
 */
object Channels {
    private val main = Handler(Looper.getMainLooper())

    fun hasSms(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.READ_SMS) == PackageManager.PERMISSION_GRANTED &&
            context.checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED

    fun attach(context: Context, messenger: BinaryMessenger, permissions: PermissionRequester?) {
        val resolver = context.contentResolver

        MethodChannel(messenger, "beaza/sms").setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasSms(context))
                "requestPermission" ->
                    permissions?.requestSms(result) ?: result.success(hasSms(context))
                "listInbox" -> {
                    val since = call.argument<Number>("sinceMs")?.toLong() ?: 0L
                    inBackground(result) { SmsInbox.list(resolver, since) }
                }
                "readBodies" -> {
                    val ids = call.argument<List<String>>("ids") ?: emptyList()
                    inBackground(result) { SmsInbox.bodies(resolver, ids) }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "beaza/notify").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" ->
                    permissions?.requestNotifications(result) ?: result.success(false)
                "show" -> {
                    Alerts.show(
                        context,
                        call.argument<Number>("id")?.toInt() ?: 1,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("body") ?: "",
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun inBackground(result: MethodChannel.Result, work: () -> Any) {
        Thread {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("sms", e.message, null) }
            }
        }.start()
    }
}
