package bh.beaza.beaza

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.os.Bundle
import android.provider.MediaStore
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.content.FileProvider
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File
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
    private var pendingScan: MethodChannel.Result? = null
    private var cameraFile: File? = null
    private var pendingSpeech: MethodChannel.Result? = null
    private var recognizer: SpeechRecognizer? = null
    private var speechEvents: EventChannel.EventSink? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        Channels.attach(this, messenger, this)
        clearReceiptPhotos()
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

    /**
     * A receipt photo (camera) or picture (gallery) to text, on the phone
     * with ML Kit. A camera photo goes to a temporary file that is deleted as
     * soon as its text is read, also on failure; a gallery picture is read in
     * place and never copied. Answers the text, or null when cancelled.
     */
    override fun scanReceipt(source: String, result: MethodChannel.Result) {
        if (pendingScan != null) {
            result.error("busy", "A scan is already open", null)
            return
        }
        pendingScan = result
        try {
            if (source == "camera") {
                val dir = File(cacheDir, "receipts").apply { mkdirs() }
                val file = File.createTempFile("receipt", ".jpg", dir)
                cameraFile = file
                val uri = FileProvider.getUriForFile(this, "$packageName.receipts", file)
                val intent = Intent(MediaStore.ACTION_IMAGE_CAPTURE).apply {
                    putExtra(MediaStore.EXTRA_OUTPUT, uri)
                    addFlags(
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    )
                }
                startActivityForResult(intent, SCAN_REQUEST)
            } else {
                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    type = "image/*"
                    addCategory(Intent.CATEGORY_OPENABLE)
                }
                startActivityForResult(intent, SCAN_REQUEST)
            }
        } catch (e: Exception) {
            pendingScan = null
            clearReceiptPhotos()
            result.error(if (source == "camera") "no_camera" else "no_picker", e.message, null)
        }
    }

    private fun readReceipt(resultCode: Int, data: Intent?) {
        val result = pendingScan ?: return
        pendingScan = null
        val file = cameraFile
        cameraFile = null
        val uri = when {
            resultCode != RESULT_OK -> null
            file != null -> if (file.length() > 0) Uri.fromFile(file) else null
            else -> data?.data
        }
        if (uri == null) {
            file?.delete()
            result.success(null)
            return
        }
        Thread {
            try {
                val image = InputImage.fromBitmap(loadBitmap(uri), 0)
                val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                recognizer.process(image)
                    .addOnSuccessListener { text -> result.success(text.text) }
                    .addOnFailureListener { e ->
                        result.error("ocr", "recognize: ${describe(e)}", null)
                    }
                    .addOnCompleteListener {
                        recognizer.close()
                        file?.delete()
                    }
            } catch (e: Throwable) {
                file?.delete()
                runOnUiThread {
                    result.error("ocr", "load: ${describe(e)}", null)
                }
            }
        }.start()
    }

    /** The error and the first lines of where it happened, for the person to send. */
    private fun describe(e: Throwable): String =
        "${e.javaClass.simpleName}: ${e.message}\n" +
            e.stackTrace.take(6).joinToString("\n") { "${it.className.substringAfterLast('.')}.${it.methodName}:${it.lineNumber}" }

    /**
     * The picture as a bitmap of at most about 2400 px on its long side (a
     * 12 MP photo needs no more to read a receipt and may not fit in memory),
     * turned upright from its EXIF orientation. Nothing is written to disk.
     */
    private fun loadBitmap(uri: Uri): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        (contentResolver.openInputStream(uri) ?: throw IOException("Cannot open the picture")).use {
            BitmapFactory.decodeStream(it, null, bounds)
        }
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / sample > 2400) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        val bitmap = (contentResolver.openInputStream(uri) ?: throw IOException("Cannot open the picture")).use {
            BitmapFactory.decodeStream(it, null, opts)
        } ?: throw IOException("Not a picture this phone can open")
        val degrees = try {
            (contentResolver.openInputStream(uri) ?: throw IOException("x")).use {
                when (ExifInterface(it).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            }
        } catch (e: Exception) {
            0f
        }
        if (degrees == 0f) return bitmap
        val m = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
    }

    /** Anything left from a scan that was interrupted (the app was closed). */
    private fun clearReceiptPhotos() {
        File(cacheDir, "receipts").listFiles()?.forEach { it.delete() }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SCAN_REQUEST) {
            readReceipt(resultCode, data)
            return
        }
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
        private const val SCAN_REQUEST = 4106

        /** True while the app screen's engine is running. */
        @Volatile
        var uiAlive = false
    }
}
