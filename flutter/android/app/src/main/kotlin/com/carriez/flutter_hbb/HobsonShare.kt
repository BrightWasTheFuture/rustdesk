package com.carriez.flutter_hbb

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import java.io.File

/**
 * Files handed to the app by Android's share sheet, copied into the cache so
 * the file-transfer session can read a real path. [take] clears the queue.
 */
object HobsonShare {
    private val paths = mutableListOf<String>()
    private var sharedText: String = ""
    private var panic = false

    fun capture(context: Context, intent: Intent?) {
        if (intent == null) return
        if (intent.action == HobsonPanicTileService.ACTION) {
            panic = true
        }
        intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
            if (text.startsWith("http://") || text.startsWith("https://")) {
                sharedText = text.trim()
            }
        }
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            }
            else -> return
        }
        synchronized(paths) {
            for (uri in uris) {
                copyToCache(context, uri)?.let { paths.add(it) }
            }
        }
    }

    fun takeText(): String {
        val text = sharedText
        sharedText = ""
        return text
    }

    fun takePanic(): String {
        if (!panic) return ""
        panic = false
        return "panic"
    }

    fun take(): List<String> {
        synchronized(paths) {
            val copy = paths.toList()
            paths.clear()
            return copy
        }
    }

    private fun copyToCache(context: Context, uri: Uri): String? {
        val name = displayName(context, uri).ifBlank { "shared-${System.currentTimeMillis()}" }
        val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val dir = File(context.cacheDir, "hobson-share").apply { mkdirs() }
        val dest = File(dir, "${System.currentTimeMillis()}-$safe")
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            dest.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun displayName(context: Context, uri: Uri): String {
        if (uri.scheme == "content") {
            context.contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val index = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                        if (index >= 0) return cursor.getString(index) ?: ""
                    }
                }
        }
        return uri.lastPathSegment ?: ""
    }
}

object HobsonNotify {
    private const val CHANNEL = "hobson_alerts"

    fun show(context: Context, title: String, text: String) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL, "Hobson Remote", NotificationManager.IMPORTANCE_HIGH)
            manager.createNotificationChannel(channel)
        }
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_stat_logo)
            .setContentTitle(title)
            .setContentText(text)
            .setAutoCancel(true)
            .build()
        manager.notify(text.hashCode(), notification)
    }
}
