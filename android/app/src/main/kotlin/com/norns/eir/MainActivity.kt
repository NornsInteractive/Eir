package com.norns.eir

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.PowerManager
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.security.MessageDigest
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.norns.eir/media_picker"
    private var pendingResult: MethodChannel.Result? = null
    private val REQUEST_CODE_PICK_VIDEO = 1001

    private var mediaChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    companion object {
        private var instance: MainActivity? = null
        fun onReplyFromNotification(replyText: String) {
            instance?.runOnUiThread {
                instance?.mediaChannel?.invokeMethod("onNotificationReply", mapOf("text" to replyText))
            }
        }
    }

    private fun acquireKeepAlive() {
        try {
            KeepAliveService.start(applicationContext)
        } catch (_: Exception) {}
    }

    private fun releaseKeepAlive() {
        try {
            KeepAliveService.stop(applicationContext)
        } catch (_: Exception) {}
    }

    private fun bytesToHex(bytes: ByteArray): String {
        val hexChars = "0123456789abcdef"
        val result = StringBuilder(bytes.size * 2)
        for (b in bytes) {
            val i = b.toInt() and 0xff
            result.append(hexChars[i shr 4])
            result.append(hexChars[i and 0x0f])
        }
        return result.toString()
    }

    private fun sha256Hex(input: String): String {
        val md = MessageDigest.getInstance("SHA-256")
        return bytesToHex(md.digest(input.toByteArray(Charsets.UTF_8)))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        mediaChannel = channel
        channel.setMethodCallHandler { call, result ->
            if (call.method == "pickLocalVideo") {
                if (pendingResult != null) {
                    result.error("BUSY", "Picker is already open", null)
                    return@setMethodCallHandler
                }
                pendingResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "*/*"
                    putExtra(
                        Intent.EXTRA_MIME_TYPES,
                        arrayOf(
                            "video/*",
                            "audio/*",
                            "application/ogg",
                            "application/x-matroska"
                        )
                    )
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                }
                try {
                    startActivityForResult(intent, REQUEST_CODE_PICK_VIDEO)
                } catch (e: Exception) {
                    pendingResult = null
                    result.error("INTENT_ERROR", e.message, null)
                }
            } else if (call.method == "buildMediaManifest") {
                val uriString = call.argument<String>("uri")
                val sourceDeviceId = call.argument<String>("sourceDeviceId")
                var mime = call.argument<String>("mime")
                val title = call.argument<String>("title")
                val chunkSize = (call.argument<Number>("chunkSize"))?.toInt() ?: 262144
                if (uriString.isNullOrEmpty() || sourceDeviceId.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "uri and sourceDeviceId required", null)
                    return@setMethodCallHandler
                }
                thread(name = "ManifestBuilder") {
                    try {
                        val uri = Uri.parse(uriString)
                        if (mime.isNullOrEmpty() || mime == "application/octet-stream") {
                            val crType = contentResolver.getType(uri)
                            if (!crType.isNullOrEmpty()) {
                                mime = crType
                            }
                        }
                        if (mime.isNullOrEmpty() || mime == "application/octet-stream") {
                            val lowerTitle = (title ?: "").lowercase()
                            mime = when {
                                lowerTitle.endsWith(".mp4") || lowerTitle.endsWith(".m4v") -> "video/mp4"
                                lowerTitle.endsWith(".mkv") -> "video/x-matroska"
                                lowerTitle.endsWith(".webm") -> "video/webm"
                                lowerTitle.endsWith(".mov") -> "video/quicktime"
                                lowerTitle.endsWith(".avi") -> "video/x-msvideo"
                                lowerTitle.endsWith(".flv") -> "video/x-flv"
                                lowerTitle.endsWith(".ts") -> "video/mp2t"
                                lowerTitle.endsWith(".mp3") -> "audio/mpeg"
                                lowerTitle.endsWith(".m4a") || lowerTitle.endsWith(".aac") -> "audio/mp4"
                                lowerTitle.endsWith(".ogg") || lowerTitle.endsWith(".opus") -> "audio/ogg"
                                lowerTitle.endsWith(".flac") -> "audio/flac"
                                lowerTitle.endsWith(".wav") -> "audio/wav"
                                else -> "video/mp4"
                            }
                        }
                        mime = mime!!.lowercase().split(";")[0].trim()
                        if (mime == "application/x-matroska") mime = "video/x-matroska"
                        if (mime == "audio/mp3") mime = "audio/mpeg"
                        if (mime == "audio/m4a") mime = "audio/mp4"

                        val chunkHashes = ArrayList<String>()
                        val fileDigest = MessageDigest.getInstance("SHA-256")
                        val chunkDigest = MessageDigest.getInstance("SHA-256")
                        val buffer = ByteArray(chunkSize)
                        var totalRead: Long = 0

                        contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                            afd.createInputStream().use { fis ->
                                while (true) {
                                    var chunkRead = 0
                                    while (chunkRead < chunkSize) {
                                        val r = fis.read(buffer, chunkRead, chunkSize - chunkRead)
                                        if (r < 0) break
                                        chunkRead += r
                                    }
                                    if (chunkRead <= 0) break
                                    totalRead += chunkRead

                                    fileDigest.update(buffer, 0, chunkRead)

                                    chunkDigest.reset()
                                    chunkDigest.update(buffer, 0, chunkRead)
                                    chunkHashes.add(bytesToHex(chunkDigest.digest()))
                                }
                            }
                        } ?: run {
                            runOnUiThread { result.error("OPEN_FAILED", "Failed to open $uriString", null) }
                            return@thread
                        }

                        val fileSha256 = bytesToHex(fileDigest.digest())
                        val v = 1
                        val binding = "eir-media-manifest/v1|$v|$mime|$totalRead|$chunkSize|$sourceDeviceId|$fileSha256|${chunkHashes.joinToString(",")}"
                        val mediaId = sha256Hex(binding)

                        val manifestMap = mapOf(
                            "v" to v,
                            "mediaId" to mediaId,
                            "sourceDeviceId" to sourceDeviceId,
                            "fileSha256" to fileSha256,
                            "mime" to mime,
                            "size" to totalRead,
                            "chunkSize" to chunkSize,
                            "chunkCount" to chunkHashes.size,
                            "chunkHashes" to chunkHashes,
                            "title" to title
                        )

                        runOnUiThread { result.success(manifestMap) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("MANIFEST_ERROR", e.message, null) }
                    }
                }
            } else if (call.method == "readContentChunk") {
                val uriString = call.argument<String>("uri")
                val offset = (call.argument<Number>("offset"))?.toLong() ?: 0L
                val length = (call.argument<Number>("length"))?.toInt() ?: 0
                if (uriString.isNullOrEmpty() || length <= 0) {
                    result.error("INVALID_ARGS", "uri and length > 0 required", null)
                    return@setMethodCallHandler
                }
                thread(name = "ChunkReader") {
                    try {
                        val uri = Uri.parse(uriString)
                        contentResolver.openAssetFileDescriptor(uri, "r")?.use { afd ->
                            afd.createInputStream().use { fis ->
                                val channel = fis.channel
                                channel.position(offset)
                                val byteBuffer = ByteBuffer.allocate(length)
                                var totalRead = 0
                                while (totalRead < length) {
                                    val r = channel.read(byteBuffer)
                                    if (r < 0) break
                                    totalRead += r
                                }
                                val outBytes = if (totalRead == length) {
                                    byteBuffer.array()
                                } else {
                                    byteBuffer.array().copyOf(totalRead)
                                }
                                runOnUiThread { result.success(outBytes) }
                            }
                        } ?: run {
                            runOnUiThread { result.error("OPEN_FAILED", "Failed to open content URI", null) }
                        }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("READ_ERROR", e.message, null) }
                    }
                }
            } else if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath") ?: call.argument<String>("path")
                if (filePath.isNullOrEmpty()) {
                    result.error("INVALID_PATH", "File path missing", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist at $filePath", null)
                        return@setMethodCallHandler
                    }
                    val uri = FileProvider.getUriForFile(
                        this,
                        "${applicationContext.packageName}.fileprovider",
                        file
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }

                    // Explicitly grant read URI permissions to target activities
                    val resInfoList = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
                    for (resolveInfo in resInfoList) {
                        val pkgName = resolveInfo.activityInfo.packageName
                        grantUriPermission(pkgName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }

                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_ERROR", e.message, null)
                }
            } else if (call.method == "acquireKeepAliveLock") {
                acquireKeepAlive()
                result.success(true)
            } else if (call.method == "releaseKeepAliveLock") {
                releaseKeepAlive()
                result.success(true)
            } else if (call.method == "startMediaProjectionService") {
                try {
                    MediaProjectionService.start(applicationContext)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_ERROR", e.message, null)
                }
            } else if (call.method == "stopMediaProjectionService") {
                try {
                    MediaProjectionService.stop(applicationContext)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SERVICE_ERROR", e.message, null)
                }
            } else if (call.method == "showScreenShareMessageNotification") {
                try {
                    val id = call.argument<String>("id") ?: System.currentTimeMillis().toString()
                    val sender = call.argument<String>("sender") ?: "观众"
                    val text = call.argument<String>("text") ?: ""
                    MediaProjectionService.showChatMessageNotification(applicationContext, id, sender, text)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("NOTIFICATION_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.norns.eir/app_icon").setMethodCallHandler { call, result ->
            if (call.method == "setAppIcon") {
                val iconName = call.argument<String>("icon") ?: "classic"
                val pm = applicationContext.packageManager
                val pkg = applicationContext.packageName

                val aliases = mapOf(
                    "classic" to "$pkg.MainActivityAliasClassic",
                    "neon" to "$pkg.MainActivityAliasNeon",
                    "stealth" to "$pkg.MainActivityAliasStealth",
                    "silver" to "$pkg.MainActivityAliasSilver"
                )

                try {
                    val targetComponent = aliases[iconName] ?: aliases["classic"]!!
                    for ((_, compName) in aliases) {
                        val state = if (compName == targetComponent) {
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                        } else {
                            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                        }
                        pm.setComponentEnabledSetting(
                            ComponentName(pkg, compName),
                            state,
                            PackageManager.DONT_KILL_APP
                        )
                    }
                    // Ensure root MainActivity itself is always enabled
                    pm.setComponentEnabledSetting(
                        ComponentName(pkg, "$pkg.MainActivity"),
                        PackageManager.COMPONENT_ENABLED_STATE_ENABLED,
                        PackageManager.DONT_KILL_APP
                    )
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ICON_ERROR", e.message, null)
                }
            } else if (call.method == "createPinShortcut") {
                val iconPath = call.argument<String>("iconPath")
                val label = call.argument<String>("label") ?: "Eir"
                if (iconPath.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "iconPath required", null)
                    return@setMethodCallHandler
                }
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        val shortcutManager = getSystemService(ShortcutManager::class.java)
                        if (shortcutManager != null && shortcutManager.isRequestPinShortcutSupported) {
                            val bitmap = BitmapFactory.decodeFile(iconPath)
                            if (bitmap != null) {
                                val icon = Icon.createWithBitmap(bitmap)
                                val pm = applicationContext.packageManager
                                val pkg = applicationContext.packageName
                                val launchIntent = pm.getLaunchIntentForPackage(pkg)
                                    ?: Intent(applicationContext, MainActivity::class.java).apply {
                                        action = Intent.ACTION_MAIN
                                        addCategory(Intent.CATEGORY_DEFAULT)
                                    }
                                launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED

                                val pinShortcutInfo = ShortcutInfo.Builder(applicationContext, "eir_shortcut_" + System.currentTimeMillis())
                                    .setIcon(icon)
                                    .setShortLabel(label)
                                    .setLongLabel(label)
                                    .setIntent(launchIntent)
                                    .build()
                                shortcutManager.requestPinShortcut(pinShortcutInfo, null)
                                result.success(true)
                            } else {
                                result.error("DECODE_ERROR", "Failed to decode image file", null)
                            }
                        } else {
                            result.error("UNSUPPORTED", "Pin shortcuts not supported on this device/launcher", null)
                        }
                    } else {
                        result.error("UNSUPPORTED", "Requires Android 8.0+", null)
                    }
                } catch (e: Exception) {
                    result.error("SHORTCUT_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        mediaChannel = null
        releaseKeepAlive()
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_VIDEO) {
            val r = pendingResult
            pendingResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri: Uri = data.data!!
                try {
                    val takeFlags = (data.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    contentResolver.takePersistableUriPermission(uri, takeFlags)
                } catch (_: Exception) {}

                var name = "video"
                var size = 0L
                try {
                    contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIdx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            if (nameIdx >= 0) {
                                name = cursor.getString(nameIdx) ?: "video"
                            }
                            val sizeIdx = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) {
                                size = cursor.getLong(sizeIdx)
                            }
                        }
                    }
                } catch (_: Exception) {}

                r?.success(
                    mapOf(
                        "path" to uri.toString(),
                        "name" to name,
                        "size" to size
                    )
                )
            } else {
                r?.success(null)
            }
        }
    }
}
