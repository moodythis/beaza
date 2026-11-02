package bh.beaza.beaza

import android.content.ContentResolver
import android.net.Uri

/** Reads the SMS inbox in two steps so bodies of unknown senders are never read. */
object SmsInbox {
    private val INBOX: Uri = Uri.parse("content://sms/inbox")
    private const val CHUNK = 200

    /** Id, sender and date of messages newer than [sinceMs]. No text. */
    fun list(resolver: ContentResolver, sinceMs: Long): List<Map<String, Any>> {
        val out = ArrayList<Map<String, Any>>()
        resolver.query(
            INBOX,
            arrayOf("_id", "address", "date"),
            "date > ?",
            arrayOf(sinceMs.toString()),
            "date ASC",
        )?.use { c ->
            val id = c.getColumnIndexOrThrow("_id")
            val address = c.getColumnIndexOrThrow("address")
            val date = c.getColumnIndexOrThrow("date")
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "id" to c.getLong(id).toString(),
                        "sender" to (c.getString(address) ?: ""),
                        "dateMs" to c.getLong(date),
                    ),
                )
            }
        }
        return out
    }

    /** Bodies of exactly the requested ids (digits only). */
    fun bodies(resolver: ContentResolver, ids: List<String>): Map<String, String> {
        val clean = ids.filter { it.isNotEmpty() && it.all(Char::isDigit) }
        val out = HashMap<String, String>()
        for (chunk in clean.chunked(CHUNK)) {
            val marks = chunk.joinToString(",") { "?" }
            resolver.query(
                INBOX,
                arrayOf("_id", "body"),
                "_id IN ($marks)",
                chunk.toTypedArray(),
                null,
            )?.use { c ->
                val id = c.getColumnIndexOrThrow("_id")
                val body = c.getColumnIndexOrThrow("body")
                while (c.moveToNext()) {
                    out[c.getLong(id).toString()] = c.getString(body) ?: ""
                }
            }
        }
        return out
    }
}
