package com.carriez.flutter_hbb

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Quick Settings tile that starts or stops sharing this phone's screen.
 * Android still shows the screen-capture consent dialog the first time;
 * a tile cannot grant that permission by itself.
 */
@RequiresApi(Build.VERSION_CODES.N)
class HobsonTileService : TileService() {
    override fun onStartListening() {
        qsTile?.apply {
            label = "Share screen"
            state = if (MainService.isStart) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
            updateTile()
        }
    }

    override fun onClick() {
        if (MainService.isReady) {
            startService(Intent(this, MainService::class.java).apply { action = ACTION_STOP })
            qsTile?.apply {
                state = Tile.STATE_INACTIVE
                updateTile()
            }
            return
        }
        val launch = Intent(this, MainActivity::class.java).apply {
            action = ACTION_START
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        if (Build.VERSION.SDK_INT >= 34) {
            val pending = PendingIntent.getActivity(
                this,
                0,
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
        const val ACTION_START = "com.jcb.remote.TILE_START"
        const val ACTION_STOP = "com.jcb.remote.TILE_STOP"
    }
}
