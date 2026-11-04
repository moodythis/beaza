package bh.beaza.beaza

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.IOException
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** The app screen: channels, permission dialogs, and new-SMS pings. */
class MainActivity : FlutterActivity(), PermissionRequester {
    private var pendingSms: MethodChannel.Result? = null
    private var pendingNotify: MethodChannel.Result? = null
    private var pendingSave: Pair<String, MethodChannel.Result>? = null
    private var pendingMic: Pair<String, MethodChannel.Result>? = null
    private var pendingSpeech: MethodChannel.Result? = null
    private var recognizer: SpeechRecognizer? = null
    private var speechEvents: EventChannel.EventSink? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        Channels.attach(this, messenger, this)
        uiAlive = true

        EventChannel(messenger, "beaza/speech_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    speechEvents = events
                }

                override fun onCancel(arguments: Any?) {
                    speechEvents = null
                }
            },
        )

        EventChannel(messenger, "beaza/sms_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    startListening(events)
                }

                override fun onCancel(arguments: Any?) {
                    stopSmsListening()
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
            MIC_PERMISSION_REQUEST -> {
                val (language, result) = pendingMic ?: return
                pendingMic = null
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
                ) {
                    startRecognizer(language, result)
                } else {
                    result.error("no_permission", "Microphone not allowed", null)
                }
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

    /** Lets the person choose where to save the file (no storage permission
     * needed), then writes [text] there. Answers true, or false if cancelled. */
    override fun saveText(name: String, text: String, result: MethodChannel.Result) {
        if (pendingSave != null) {
            result.error("busy", "A save is already open", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/json"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        pendingSave = text to result
        try {
            startActivityForResult(intent, SAVE_FILE_REQUEST)
        } catch (e: ActivityNotFoundException) {
            pendingSave = null
            result.error("no_picker", e.message, null)
        }
    }

    /** Beaza's App info page, where Battery can be set to Unrestricted. */
    override fun openAppSettings(result: MethodChannel.Result) {
        try {
            startActivity(
                Intent(
                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null),
                ),
            )
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("no_settings", e.message, null)
        }
    }

    /**
     * Listens inside Beaza (no Google screen on top). Audio goes from the
     * microphone to the phone's speech service, which may use the internet;
     * Beaza keeps only the text. Answers the text, or null when nothing was
     * heard. Live text goes to the `beaza/speech_events` stream.
     */
    override fun listen(language: String, result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            if (pendingMic != null) {
                result.error("busy", "A permission request is already open", null)
                return
            }
            pendingMic = language to result
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MIC_PERMISSION_REQUEST)
            return
        }
        startRecognizer(language, result)
    }

    override fun stopListening() {
        recognizer?.stopListening()
    }

    private fun startRecognizer(language: String, result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            result.error("no_speech", "No speech service on this phone", null)
            return
        }
        finishSpeech(null, null) // a new request replaces an open one
        val r = SpeechRecognizer.createSpeechRecognizer(this)
        r.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {
                speechEvents?.success(mapOf("state" to "listening"))
            }
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {
                speechEvents?.success(mapOf("state" to "processing"))
            }
            override fun onError(error: Int) = finishSpeech(null, error)
            override fun onResults(results: Bundle?) = finishSpeech(
                results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull(),
                null,
            )
            override fun onPartialResults(partialResults: Bundle?) {
                val text = partialResults
                    ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    ?.firstOrNull()
                if (!text.isNullOrBlank()) speechEvents?.success(mapOf("partial" to text))
            }
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, language)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
        }
        pendingSpeech = result
        recognizer = r
        r.startListening(intent)
    }

    private fun finishSpeech(text: String?, error: Int?) {
        val result = pendingSpeech
        pendingSpeech = null
        recognizer?.destroy()
        recognizer = null
        if (result == null) return
        when (error) {
            null, SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT ->
                result.success(text)
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS ->
                result.error("no_permission", "Microphone not allowed", null)
            SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
                result.error("network", "Speech needs the internet", null)
            else -> result.error("speech_error", "Speech error $error", null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SAVE_FILE_REQUEST) return
        val (text, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        Thread {
            try {
                val stream = contentResolver.openOutputStream(uri, "wt")
                    ?: throw IOException("Cannot open the file")
                stream.use { it.write(text.toByteArray(Charsets.UTF_8)) }
                runOnUiThread { result.success(true) }
            } catch (e: Exception) {
                runOnUiThread { result.error("write", e.message, null) }
            }
        }.start()
    }

    /** While the screen exists it handles new SMS itself (no background run). */
    private fun startListening(events: EventChannel.EventSink) {
        stopSmsListening()
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

    private fun stopSmsListening() {
        smsReceiver?.let { unregisterReceiver(it) }
        smsReceiver = null
    }

    override fun onDestroy() {
        finishSpeech(null, null)
        stopSmsListening()
        uiAlive = false
        super.onDestroy()
    }

    companion object {
        private const val SMS_PERMISSION_REQUEST = 4101
        private const val NOTIFY_PERMISSION_REQUEST = 4102
        private const val SAVE_FILE_REQUEST = 4103
        private const val MIC_PERMISSION_REQUEST = 4105

        /** True while the app screen's engine is running. */
        @Volatile
        var uiAlive = false
    }
}
