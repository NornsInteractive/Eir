package com.norns.eir

import android.app.Activity
import android.content.Intent
import android.net.Uri
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                if (uriString.isNullOrEmpty() || sourceDeviceId.isNullOrEmpty()) {
                    result.error("INVALID_ARGS", "uri and sourceDeviceId required", null)
                    return@setMethodCallHandler
                }
                thread(name = "ManifestBuilder") {
                    try {
                        val uri = Uri.parse(uriString)
                        if (mime.isNullOrEmpty()) {
                            mime = contentResolver.getType(uri) ?: "video/mp4"
                        }
                        if (mime == "application/x-matroska") mime = "video/x-matroska"
                        if (mime == "audio/mp3") mime = "audio/mpeg"

                        val chunkSize = 131072 // 128 KiB
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
                val filePath = call.argument<String>("filePath")
                if (filePath.isNullOrEmpty()) {
                    result.error("INVALID_PATH", "File path missing", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist", null)
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
                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("INSTALL_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
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
