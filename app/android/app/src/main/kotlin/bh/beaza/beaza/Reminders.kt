package bh.beaza.beaza

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject

/**
 * One reminder at a set time (the end of a 24-hour hold, the daily close,
 * the weekly report). Inexact on purpose: no exact-alarm permission is
 * needed, and a few minutes late is fine. Texts come from Dart, already
 * localized, and never hold amounts.
 *
 * Android forgets alarms when the phone restarts, so each pending reminder
 * is also kept in the app's private preferences and set again by
 * [BootReceiver]. It is removed when it is shown or cancelled.
 */
object Reminders {
    private const val PREFS = "beaza.reminders"

    /** A reminder whose time passed while the phone was off by more than
     *  this is dropped instead of shown late. */
    const val STALE_MS = 12L * 60 * 60 * 1000

    private fun intent(context: Context, id: Int, title: String?, body: String?): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            id,
            Intent(context, ReminderReceiver::class.java)
                .putExtra("id", id)
                .putExtra("title", title)
                .putExtra("body", body),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun set(context: Context, id: Int, atMs: Long, title: String, body: String) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = intent(context, id, title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pending)
        } else {
            alarms.set(AlarmManager.RTC_WAKEUP, atMs, pending)
        }
    }

    fun schedule(context: Context, id: Int, atMs: Long, title: String, body: String) {
        set(context, id, atMs, title, body)
        val saved = JSONObject().put("at", atMs).put("title", title).put("body", body)
        prefs(context).edit().putString(id.toString(), saved.toString()).apply()
    }

    fun cancel(context: Context, id: Int) {
        context.getSystemService(AlarmManager::class.java)
            ?.cancel(intent(context, id, null, null))
        forget(context, id)
    }

    fun forget(context: Context, id: Int) {
        prefs(context).edit().remove(id.toString()).apply()
    }

    /** Sets every kept reminder again after a restart. One that is already
     *  due fires a minute from now; one more than [STALE_MS] late is dropped. */
    fun restore(context: Context, nowMs: Long = System.currentTimeMillis()) {
        val p = prefs(context)
        for ((key, value) in p.all) {
            val id = key.toIntOrNull()
            val saved = try {
                JSONObject(value as? String ?: "")
            } catch (e: Exception) {
                null
            }
            if (id == null || saved == null) {
                p.edit().remove(key).apply()
                continue
            }
            val at = saved.optLong("at")
            if (at < nowMs - STALE_MS) {
                forget(context, id)
                continue
            }
            set(context, id, maxOf(at, nowMs + 60_000), saved.optString("title"),
                saved.optString("body"))
        }
    }
}

/** Shows a reminder when its time comes. Only Beaza can send this. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 2)
        Reminders.forget(context, id)
        Alerts.show(
            context,
            id,
            intent.getStringExtra("title") ?: return,
            intent.getStringExtra("body") ?: return,
        )
    }
}

/** Sets the reminders again after the phone restarts or Beaza is updated.
 *  Both broadcasts can only come from the system. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                Reminders.restore(context)
        }
    }
}
