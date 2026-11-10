package com.carriez.flutter_hbb

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/** Ends sharing and asks the Flutter UI to panic-lock the listed PCs. */
@RequiresApi(Build.VERSION_CODES.N)
class HobsonPanicTileService : TileService() {
    override fun onStartListening() {
        qsTile?.apply {
            label = "Panic lock"
            state = Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        if (MainService.isReady) {
            startService(Intent(this, MainService::class.java).apply {
                action = HobsonTileService.ACTION_STOP
            })
        }
        val launch = Intent(this, MainActivity::class.java).apply {
            action = ACTION
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val pending = PendingIntent.getActivity(
                this,
                1,
                launch,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launch)
        }
    }

    companion object {
        const val ACTION = "com.hobson.remote.PANIC"
    }
}
