package app.debridhub.shared.data.remote

import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.http.ContentType
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

class RealDebridApiTest {
    @Test
    fun `transport failure retries alternate host and keeps successful host preferred`() = runBlocking {
        val requestedHosts = mutableListOf<String>()
        val client = HttpClient(MockEngine { request ->
            requestedHosts += request.url.host
            when (request.url.host) {
                "api.real-debrid.com" -> error("TLS handshake failed")
                else -> respond(
                    content = """
                        {"id":1,"username":"sample-user","type":"premium","premium":432000,"expiration":"2026-04-23T09:00:00Z"}
                    """.trimIndent(),
                    status = HttpStatusCode.OK,
                    headers = headersOf("Content-Type", ContentType.Application.Json.toString())
                )
            }
        }) {
            install(ContentNegotiation) {
                json(Json { ignoreUnknownKeys = true })
            }
        }
        val api = RealDebridApi(client)

        api.getUser("token")
        api.getUser("token")

        assertEquals(
            listOf(
                "api.real-debrid.com",
                "api-1.real-debrid.com",
                "api-1.real-debrid.com"
            ),
            requestedHosts
        )
    }

    @Test
    fun `non transport failure does not retry alternate host`() = runBlocking {
        val requestedHosts = mutableListOf<String>()
        val client = HttpClient(MockEngine { request ->
            requestedHosts += request.url.host
            error("authorization_pending")
        })
        val api = RealDebridApi(client)

        assertFailsWith<IllegalStateException> {
            api.getDeviceCode("client-id")
        }
        assertEquals(listOf("api.real-debrid.com"), requestedHosts)
    }
}
