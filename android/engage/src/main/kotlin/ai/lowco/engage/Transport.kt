package ai.lowco.engage

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/** Status and body of a track request. */
class EngageResponse(val statusCode: Int, val body: String)

/** Sends one track request. Called on the SDK's background thread. */
fun interface EngageTransport {
    @Throws(IOException::class)
    fun post(url: String, headers: Map<String, String>, body: ByteArray): EngageResponse
}

/** Default transport on [HttpURLConnection]; no extra dependency. */
class HttpUrlConnectionTransport @JvmOverloads constructor(
    private val timeoutMs: Int = 30_000,
) : EngageTransport {
    override fun post(url: String, headers: Map<String, String>, body: ByteArray): EngageResponse {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.useCaches = false
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            for ((name, value) in headers) connection.setRequestProperty(name, value)
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            return EngageResponse(status, stream?.use(::readCapped) ?: "")
        } finally {
            connection.disconnect()
        }
    }

    private fun readCapped(input: InputStream): String {
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (out.size() < MAX_BODY) {
            val n = input.read(buffer)
            if (n < 0) break
            out.write(buffer, 0, n)
        }
        return out.toString("UTF-8")
    }

    private companion object {
        const val MAX_BODY = 64 * 1024
    }
}
