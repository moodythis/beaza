package bh.beaza.beaza

import android.Manifest
import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Things that need a screen (permission dialogs, the file picker,
 * opening settings), so only the activity can do them. */
interface PermissionRequester {
    fun requestSms(result: MethodChannel.Result)
    fun requestNotifications(result: MethodChannel.Result)
    fun saveText(name: String, text: String, result: MethodChannel.Result)
    fun openAppSettings(result: MethodChannel.Result)
    fun listen(language: String, result: MethodChannel.Result)
    fun stopListening()
    fun scanReceipt(source: String, withImage: Boolean, result: MethodChannel.Result)
    fun recordStart(result: MethodChannel.Result)
    fun recordStop(result: MethodChannel.Result)
    fun recordCancel()
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

    /**
     * True when Android may stop Beaza in the background: battery
     * optimization is on (not "Unrestricted"), or background use is
     * restricted for the app.
     */
    fun batteryRestricted(context: Context): Boolean {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val optimized = Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !power.isIgnoringBatteryOptimizations(context.packageName)
        val activity = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val restricted = Build.VERSION.SDK_INT >= Build.VERSION_CODES.P &&
            activity.isBackgroundRestricted
        return optimized || restricted
    }

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

        MethodChannel(messenger, "beaza/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "batteryRestricted" -> result.success(batteryRestricted(context))
                "openAppSettings" ->
                    permissions?.openAppSettings(result) ?: result.success(null)
                "listen" -> {
                    val language = call.argument<String>("language") ?: "ar-BH"
                    permissions?.listen(language, result)
                        ?: result.error("no_screen", "Voice input needs the app screen", null)
                }
                "scanReceipt" -> {
                    val source = call.argument<String>("source") ?: "gallery"
                    val withImage = call.argument<Boolean>("withImage") ?: false
                    permissions?.scanReceipt(source, withImage, result)
                        ?: result.error("no_screen", "Scanning needs the app screen", null)
                }
                "recordStart" ->
                    permissions?.recordStart(result)
                        ?: result.error("no_screen", "Recording needs the app screen", null)
                "recordStop" ->
                    permissions?.recordStop(result)
                        ?: result.error("no_screen", "Recording needs the app screen", null)
                "recordCancel" -> {
                    permissions?.recordCancel()
                    result.success(null)
                }
                "stopListening" -> {
                    permissions?.stopListening()
                    result.success(null)
                }
                "saveText" -> {
                    val name = call.argument<String>("name") ?: "beaza-export.json"
                    val text = call.argument<String>("text") ?: ""
                    permissions?.saveText(name, text, result)
                        ?: result.error("no_screen", "Saving a file needs the app screen", null)
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
