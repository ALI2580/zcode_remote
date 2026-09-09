package com.zcoderemote.zcode_remote

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

class AttachmentPicker(private val activity: Activity, messenger: BinaryMessenger) {
    companion object { const val REQUEST = 4101; const val MAX_BYTES = 20 * 1024 * 1024 }
    @Volatile private var pending: MethodChannel.Result? = null
    @Volatile private var disposed = false
    private val worker = Executors.newSingleThreadExecutor()
    private val directory = File(activity.filesDir, "draft-attachments")
    private val tokenPattern = Regex("^[a-f0-9-]{36}$")

    private fun cached(token: String?): File? {
        if (token == null || !tokenPattern.matches(token)) return null
        val root = directory.canonicalFile
        val file = File(root, "$token.bin").canonicalFile
        return file.takeIf { it.parentFile == root }
    }

    init {
        MethodChannel(messenger, "zcode_remote/attachments").setMethodCallHandler { call, result ->
            when (call.method) {
                "environment" -> result.success(mapOf("packageName" to activity.packageName,
                    "cacheDirectory" to directory.absolutePath))
                "pick" -> {
                    if (pending != null) result.error("picker_busy", "文件选择器已打开", null)
                    else {
                        pending = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                type = "*/*"
                                addCategory(Intent.CATEGORY_OPENABLE)
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, REQUEST)
                        } catch (_: Exception) {
                            pending = null
                            result.error("picker_unavailable", "暂时无法打开文件选择器", null)
                        }
                    }
                }
                "cancelPick" -> {
                    val old = pending
                    pending = null
                    old?.success(emptyList<Any>())
                    result.success(null)
                }
                "exists" -> result.success(cached(call.argument("token"))?.isFile == true)
                "read" -> worker.execute {
                    try {
                        val file = cached(call.argument("token")) ?: throw IllegalArgumentException()
                        if (!file.isFile || file.length() > MAX_BYTES) throw IllegalArgumentException()
                        val bytes = file.readBytes()
                        val expected = call.argument<String>("sha256")
                        val hash = MessageDigest.getInstance("SHA-256").digest(bytes)
                            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
                        if (expected == null || hash != expected) throw IllegalArgumentException()
                        activity.runOnUiThread { if (!disposed) result.success(bytes) }
                    } catch (_: Exception) {
                        activity.runOnUiThread {
                            if (!disposed) result.error("file_unavailable", "附件不可读取，请重新选择", null)
                        }
                    }
                }
                "prune" -> {
                    val retained = call.argument<List<String>>("retained")?.toSet() ?: emptySet()
                    worker.execute {
                        val root = directory.canonicalFile
                        val cutoff = System.currentTimeMillis() - 24L * 60 * 60 * 1000
                        root.listFiles()?.forEach { file ->
                            if (file.canonicalFile.parentFile == root && file.isFile &&
                                file.lastModified() < cutoff && file.nameWithoutExtension !in retained) file.delete()
                        }
                        activity.runOnUiThread { if (!disposed) result.success(null) }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun cache(uri: Uri, allowed: () -> Boolean): Map<String, Any> {
        var name = "attachment"
        var size = 0L
        var mime = "application/octet-stream"
        var partial: File? = null
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
                null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                    if (nameIndex >= 0) name = cursor.getString(nameIndex) ?: name
                    if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex)
                }
            }
            mime = activity.contentResolver.getType(uri) ?: mime
            if (size > MAX_BYTES) return mapOf("name" to name, "mime" to mime, "size" to size, "error" to "too_large")
            if (!directory.isDirectory && !directory.mkdirs()) throw IllegalStateException()
            val token = UUID.randomUUID().toString()
            val target = cached(token) ?: throw IllegalStateException()
            val temporary = File(directory, "$token.part")
            partial = temporary
            val digest = MessageDigest.getInstance("SHA-256")
            size = 0
            activity.contentResolver.openInputStream(uri)!!.use { input ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        if (!allowed()) throw IllegalStateException()
                        val count = input.read(buffer)
                        if (count < 0) break
                        size += count
                        if (size > MAX_BYTES) throw IllegalArgumentException()
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
            if (!allowed() || !temporary.renameTo(target)) throw IllegalStateException()
            val hash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
            return mapOf("token" to token, "sha256" to hash, "name" to name, "mime" to mime, "size" to size)
        } catch (_: Exception) {
            partial?.delete()
            return mapOf("name" to name, "mime" to mime, "size" to size,
                "error" to if (size > MAX_BYTES) "too_large" else "unavailable")
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST) return
        val result = pending ?: return
        if (resultCode != Activity.RESULT_OK) {
            pending = null
            result.success(emptyList<Any>())
            return
        }
        val uris = mutableListOf<Uri>()
        data?.clipData?.let { clips -> for (i in 0 until clips.itemCount) uris.add(clips.getItemAt(i).uri) }
        if (uris.isEmpty()) data?.data?.let { uris.add(it) }
        worker.execute {
            val files = uris.distinct().map { cache(it) { !disposed && pending === result } }
            activity.runOnUiThread {
                if (!disposed && pending === result) {
                    pending = null
                    result.success(files)
                }
            }
        }
    }
    fun dispose() {
        disposed = true
        pending?.success(emptyList<Any>())
        pending = null
        worker.shutdown()
    }
}
