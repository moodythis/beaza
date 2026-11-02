package bh.beaza.beaza

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Wakes Beaza when an SMS arrives while the app is closed: starts a small
 * Dart run (backgroundMain in main.dart) that reads new bank messages from
 * the inbox, stores the transactions and shows a guardrail alert if one is
 * due, then shuts down. Nothing keeps running afterwards.
 *
 * The SMS itself is not read here; Dart lists the inbox and drops unknown
 * senders before any text is read, exactly as on the app screen.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != SMS_RECEIVED) return
        // The open app already listens for new SMS itself.
        if (MainActivity.uiAlive || running) return
        running = true

        val pending = goAsync()
        val app = context.applicationContext
        val handler = Handler(Looper.getMainLooper())
        var engine: FlutterEngine? = null
        var finished = false

        fun finish() {
            if (finished) return
            finished = true
            handler.removeCallbacksAndMessages(null)
            engine?.destroy()
            engine = null
            running = false
            pending.finish()
        }

        try {
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(app)
            loader.ensureInitializationComplete(app, null)

            val e = FlutterEngine(app)
            engine = e
            val messenger = e.dartExecutor.binaryMessenger
            Channels.attach(app, messenger, null)
            MethodChannel(messenger, "beaza/background").setMethodCallHandler { call, result ->
                if (call.method == "done") {
                    result.success(null)
                    handler.post { finish() }
                } else {
                    result.notImplemented()
                }
            }

            // Android allows a short time for a broadcast; never hold it longer.
            handler.postDelayed({ finish() }, TIME_LIMIT_MS)
            e.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "backgroundMain"),
            )
        } catch (e: Exception) {
            finish()
        }
    }

    companion object {
        const val SMS_RECEIVED = "android.provider.Telephony.SMS_RECEIVED"
        private const val TIME_LIMIT_MS = 9000L

        @Volatile
        private var running = false
    }
}
