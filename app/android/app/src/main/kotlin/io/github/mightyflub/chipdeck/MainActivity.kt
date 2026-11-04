// ChipDeck Android glue: storage access, file/folder pickers and the
// background playback service, exposed to Dart on the "chipdeck/android"
// method channel (see app/lib/platform/). Playback itself runs in the shared
// native library (libchipdeck.so) through dart:ffi, exactly as on Windows.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
package io.github.mightyflub.chipdeck

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var pending: MethodChannel.Result? = null
    private var askedNotifications = false
    private var secondScreen: SecondScreen? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "chipdeck/android")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasStorageAccess" -> result.success(hasStorageAccess())
                "requestStorageAccess" -> requestStorageAccess(result)
                "pickFiles" -> pickFiles(call.argument<Boolean>("multiple") ?: true, result)
                "pickFolder" -> pickFolder(result)
                "updatePlaybackService" -> {
                    maybeAskForNotifications()
                    PlaybackService.update(
                        this,
                        call.argument<String>("title") ?: "",
                        call.argument<String>("text") ?: "",
                        call.argument<Boolean>("playing") ?: false,
                    )
                    result.success(null)
                }
                "stopPlaybackService" -> {
                    PlaybackService.stop(this)
                    result.success(null)
                }
                "controlsState" -> {
                    secondScreen?.sendState(call.arguments)
                    result.success(null)
                }
                "setSecondScreenEnabled" -> {
                    secondScreen?.enabled = call.arguments as? Boolean ?: true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        // Buttons in the notification, on the lock screen, on headphones and
        // "audio becoming noisy" (headphones unplugged) come back here.
        PlaybackService.onAction = { action ->
            runOnUiThread { channel.invokeMethod("mediaAction", action) }
        }
        secondScreen = SecondScreen(this, channel)
    }

    // The controls stay on the second screen while ChipDeck is in the
    // background (it is a music player); they go when the activity does.
    override fun onStart() {
        super.onStart()
        secondScreen?.start()
    }

    // Back on the first screen: go to the background like other music
    // players instead of finishing, so playback carries on.
    override fun popSystemNavigator(): Boolean {
        moveTaskToBack(true)
        return true
    }

    override fun onDestroy() {
        PlaybackService.onAction = null
        secondScreen?.stop()
        secondScreen = null
        val finishing = isFinishing
        super.onDestroy()
        if (finishing) {
            // The native audio device would outlive the Flutter engine.
            PlaybackService.stop(this)
            android.os.Process.killProcess(android.os.Process.myPid())
        }
    }

    // ------------------------------------------------------------ storage

    private fun hasStorageAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        }

    private fun requestStorageAccess(result: MethodChannel.Result) {
        if (hasStorageAccess()) return result.success(true)
        if (!begin(result)) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            try {
                startActivityForResult(intent, REQ_STORAGE)
            } catch (e: ActivityNotFoundException) {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION), REQ_STORAGE,
                )
            }
        } else {
            requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE), REQ_STORAGE)
        }
    }

    private fun maybeAskForNotifications() {
        if (askedNotifications || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        askedNotifications = true
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQ_NOTIFY)
        }
    }

    // ------------------------------------------------------------ pickers

    private fun pickFiles(multiple: Boolean, result: MethodChannel.Result) {
        if (!begin(result)) return
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*" // chiptune files have no registered MIME types
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple)
        }
        startActivityForResult(intent, REQ_FILES)
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (!begin(result)) return
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE), REQ_FOLDER)
    }

    /** Only one picker or permission screen at a time. */
    private fun begin(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("BUSY", "Another picker is already open.", null)
            return false
        }
        pending = result
        return true
    }

    private fun finish(value: Any?) {
        val r = pending
        pending = null
        r?.success(value)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQ_STORAGE -> finish(hasStorageAccess())
            REQ_FILES -> {
                if (resultCode != RESULT_OK || data == null) return finish(emptyList<String>())
                val uris = mutableListOf<Uri>()
                data.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
                }
                if (uris.isEmpty()) data.data?.let { uris.add(it) }
                // Copying files from cloud providers can be slow: do it off the UI thread.
                Thread {
                    val paths = uris.mapNotNull { fileUriToPath(it) }
                    runOnUiThread { finish(paths) }
                }.start()
            }
            REQ_FOLDER -> {
                val uri = data?.data
                if (resultCode != RESULT_OK || uri == null) return finish(null)
                val path = treeUriToPath(uri)
                if (path == null) {
                    val r = pending
                    pending = null
                    r?.error(
                        "UNSUPPORTED",
                        "ChipDeck can only use folders on the phone storage or SD card.",
                        null,
                    )
                } else {
                    finish(path)
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_STORAGE) finish(hasStorageAccess())
    }

    // ------------------------------------------- content:// URIs to file paths

    /** "primary:Music/HVSC" in the external storage provider -> /storage/emulated/0/Music/HVSC. */
    private fun externalDocIdToPath(docId: String): String? {
        val colon = docId.indexOf(':')
        if (colon < 0) return null
        val volume = docId.substring(0, colon)
        val rel = docId.substring(colon + 1)
        val base = when {
            volume.equals("primary", ignoreCase = true) ->
                Environment.getExternalStorageDirectory().path
            volume.equals("home", ignoreCase = true) ->
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS).path
            else -> "/storage/$volume" // SD card or USB stick, e.g. 1A2B-3C4D
        }
        return if (rel.isEmpty()) base else "$base/$rel"
    }

    private fun treeUriToPath(uri: Uri): String? {
        if (uri.authority != EXTERNAL_STORAGE) return null
        val path = externalDocIdToPath(DocumentsContract.getTreeDocumentId(uri)) ?: return null
        return if (File(path).isDirectory) path else null
    }

    private fun fileUriToPath(uri: Uri): String? {
        try {
            if (DocumentsContract.isDocumentUri(this, uri)) {
                val id = DocumentsContract.getDocumentId(uri)
                val path = when (uri.authority) {
                    EXTERNAL_STORAGE -> externalDocIdToPath(id)
                    DOWNLOADS -> if (id.startsWith("raw:")) id.removePrefix("raw:") else null
                    else -> null
                }
                if (path != null && File(path).canRead()) return path
            }
        } catch (_: Exception) {
        }
        return copyToAppStorage(uri)
    }

    /** Files from providers without a real path (Drive, Downloads, ...) are copied in. */
    private fun copyToAppStorage(uri: Uri): String? {
        return try {
            var name = "tune"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { c -> if (c.moveToFirst()) name = c.getString(0) ?: name }
            name = name.replace('/', '_')
            val dir = File(filesDir, "imported").apply { mkdirs() }
            val out = File(dir, name)
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            out.path
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        private const val REQ_STORAGE = 4101
        private const val REQ_FILES = 4102
        private const val REQ_FOLDER = 4103
        private const val REQ_NOTIFY = 4104
        private const val EXTERNAL_STORAGE = "com.android.externalstorage.documents"
        private const val DOWNLOADS = "com.android.providers.downloads.documents"
    }
}
