package bh.beaza.beaza

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * One reminder at a set time (the end of a 24-hour hold). Inexact on
 * purpose: no exact-alarm permission is needed, and a few minutes late is
 * fine. Texts come from Dart, already localized. Alarms do not survive a
 * restart of the phone; the hold itself stays in the app.
 */
object Reminders {
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

    fun schedule(context: Context, id: Int, atMs: Long, title: String, body: String) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val pending = intent(context, id, title, body)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMs, pending)
        } else {
            alarms.set(AlarmManager.RTC_WAKEUP, atMs, pending)
        }
    }

    fun cancel(context: Context, id: Int) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        alarms.cancel(intent(context, id, null, null))
    }
}

/** Shows a reminder when its time comes. Only Beaza can send this. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Alerts.show(
            context,
            intent.getIntExtra("id", 2),
            intent.getStringExtra("title") ?: return,
            intent.getStringExtra("body") ?: return,
        )
    }
}
