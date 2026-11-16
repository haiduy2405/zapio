package com.duyluma.zapio

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.os.Handler
import android.os.Looper
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.InputStream
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.security.interfaces.RSAPublicKey
import java.util.concurrent.Executors
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509KeyManager
import javax.net.ssl.X509TrustManager
import javax.security.auth.x500.X500Principal

internal class AndroidTvChannel(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "zapio/android_tv")
    private val preferences = context.getSharedPreferences("zapio_tv_pairings", Context.MODE_PRIVATE)
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var id: Int? = null
    private var active: AndroidTvSession? = null

    init {
        channel.setMethodCallHandler { call, result ->
            val session = call.argument<Int>("session")
            if (session == null) {
                result.error("BAD_ARGS", "Missing TV session", null)
                return@setMethodCallHandler
            }
            if (call.method == "connect") {
                if (Build.VERSION.SDK_INT < 23) {
                    result.error("UNSUPPORTED", "Android TV control requires Android 6 or newer", null)
                    return@setMethodCallHandler
                }
                val ip = call.argument<String>("ip")
                if (ip.isNullOrBlank()) {
                    result.error("BAD_ARGS", "Missing TV address", null)
                    return@setMethodCallHandler
                }
                active?.close()
                val remote = AndroidTvSession(ip) {
                    main.post {
                        if (id == session) channel.invokeMethod("disconnected", session)
                    }
                }
                active = remote
                id = session
                val pinned = preferences.getString(ip, null)
                run(result) {
                    val connected = pinned != null && remote.tryConnect(pinned)
                    if (!connected) remote.beginPairing()
                    !connected
                }
                return@setMethodCallHandler
            }
            val remote = active.takeIf { id == session }
            when {
                call.method == "close" -> {
                    remote?.close()
                    if (remote != null) {
                        active = null
                        id = null
                    }
                    result.success(null)
                }
                remote == null -> result.error("CLOSED", "TV session is closed", null)
                call.method == "pair" -> run(result) {
                    val pin = call.argument<String>("code") ?: throw InvalidTvPin()
                    val fingerprint = remote.finishPairing(pin)
                    preferences.edit().putString(remote.ip, fingerprint).apply()
                    remote.connect(fingerprint)
                    null
                }
                call.method == "send" -> run(result) {
                    remote.sendKey(requireNotNull(call.argument<Int>("key")))
                    null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun run(result: MethodChannel.Result, block: () -> Any?) {
        io.execute {
            try {
                val value = block()
                main.post { result.success(value) }
            } catch (error: Exception) {
                val code = if (error is InvalidTvPin) "INVALID_PIN" else "TV_CONNECTION"
                main.post { result.error(code, error.message, null) }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        id = null
        active?.close()
        active = null
        io.shutdownNow()
    }
}

private class InvalidTvPin : IOException("The code does not match this TV pairing session")

private class AndroidTvSession(val ip: String, private val disconnected: () -> Unit) {
    private val lock = Any()
    @Volatile private var stopped = false
    @Volatile private var ready = false
    @Volatile private var socket: SSLSocket? = null

    fun tryConnect(fingerprint: String): Boolean = try {
        connect(fingerprint)
        true
    } catch (_: Exception) {
        closeSocket()
        false
    }

    fun beginPairing() {
        val connection = open(6467)
        val input = DataInputStream(connection.inputStream)
        val encoding = uint(1, 3) + uint(2, 6)
        try {
            pairMessage(connection, 10, string(1, "atvremote") + string(2, "Zapio"))
            expectPair(input, 11)
            pairMessage(connection, 20, bytes(1, encoding) + uint(3, 1))
            expectPair(input, 20)
            pairMessage(connection, 30, bytes(1, encoding) + uint(2, 1))
            expectPair(input, 31)
        } catch (error: Exception) {
            closeSocket()
            throw error
        }
    }

    fun finishPairing(pin: String): String {
        if (!pin.matches(Regex("[0-9a-fA-F]{6}"))) throw InvalidTvPin()
        val connection = checkNotNull(socket)
        val client = connection.session.localCertificates.first().publicKey as RSAPublicKey
        val serverCertificate = connection.session.peerCertificates.first()
        val server = serverCertificate.publicKey as RSAPublicKey
        val secret = MessageDigest.getInstance("SHA-256").digest(
            rsaBytes(client) + rsaBytes(server) +
                byteArrayOf(pin.substring(2, 4).toInt(16).toByte(), pin.substring(4).toInt(16).toByte())
        )
        if ((secret[0].toInt() and 255) != pin.substring(0, 2).toInt(16)) throw InvalidTvPin()
        try {
            pairMessage(connection, 40, bytes(1, secret))
            expectPair(DataInputStream(connection.inputStream), 41)
            return hexFingerprint(serverCertificate.encoded)
        } finally {
            closeSocket()
        }
    }

    fun connect(fingerprint: String) {
        val connection = open(6466)
        try {
            if (hexFingerprint(connection.session.peerCertificates.first().encoded) != fingerprint) {
                throw IOException("The TV certificate changed; pairing is required")
            }
            val input = DataInputStream(connection.inputStream)
            var features = 0
            while (true) {
                val message = fields(readFrame(input))
                val configure = message[1] as? ByteArray
                if (configure != null) {
                    val supported = fields(configure)[1] as? Int ?: 0
                    features = supported and 99 // Ping, keys, power and volume.
                    if (features and 2 == 0) throw IOException("TV does not support remote keys")
                    val device = uint(3, 1) + string(4, "1") +
                        string(5, "atvremote") + string(6, "1.0.0")
                    writeFrame(connection, bytes(1, uint(1, features) + bytes(2, device)))
                }
                if (message.containsKey(2)) writeFrame(connection, bytes(2, uint(1, features)))
                if (message.containsKey(3)) throw IOException("TV rejected remote configuration")
                replyToPing(connection, message)
                if (message.containsKey(40)) break
            }
            connection.soTimeout = 90000
            ready = true
            Thread {
                try {
                    while (!stopped) replyToPing(connection, fields(readFrame(input)))
                } catch (_: Exception) {
                    if (!stopped && socket === connection) {
                        closeSocket()
                        disconnected()
                    }
                }
            }.start()
        } catch (error: Exception) {
            closeSocket()
            throw error
        }
    }

    fun sendKey(key: Int) {
        val connection = socket
        if (!ready || connection == null) throw IOException("TV is disconnected")
        writeFrame(connection, bytes(10, uint(1, key) + uint(2, 3)))
    }

    fun close() {
        stopped = true
        closeSocket()
    }

    private fun closeSocket() = synchronized(lock) {
        ready = false
        val current = socket
        socket = null
        try { current?.close() } catch (_: IOException) { }
    }

    private fun open(port: Int): SSLSocket {
        val connection = TvIdentity.tls.socketFactory.createSocket() as SSLSocket
        synchronized(lock) {
            if (stopped) {
                connection.close()
                throw IOException("TV session is closed")
            }
            socket = connection
        }
        try {
            connection.soTimeout = 9000
            connection.connect(InetSocketAddress(ip, port), 3500)
            connection.startHandshake()
            return connection
        } catch (error: Exception) {
            closeSocket()
            throw error
        }
    }

    private fun pairMessage(connection: SSLSocket, field: Int, message: ByteArray) =
        writeFrame(connection, uint(1, 2) + uint(2, 200) + bytes(field, message))

    private fun expectPair(input: DataInputStream, field: Int) {
        val message = fields(readFrame(input))
        if (message[2] != 200 || !message.containsKey(field)) throw IOException("TV rejected pairing")
    }

    private fun replyToPing(connection: SSLSocket, message: Map<Int, Any>) {
        val ping = message[8] as? ByteArray ?: return
        val token = fields(ping)[1] as? Int ?: 0
        writeFrame(connection, bytes(9, uint(1, token)))
    }

    private fun writeFrame(connection: Socket, message: ByteArray) = synchronized(connection) {
        connection.getOutputStream().apply {
            write(varint(message.size) + message)
            flush()
        }
    }
}

private object TvIdentity {
    private const val alias = "zapio_android_tv"

    val tls: SSLContext by lazy {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!store.containsAlias(alias)) {
            val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_RSA, "AndroidKeyStore")
            generator.initialize(
                KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(2048)
                    .setDigests(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384, KeyProperties.DIGEST_SHA512)
                    .setSignaturePaddings(KeyProperties.SIGNATURE_PADDING_RSA_PKCS1, KeyProperties.SIGNATURE_PADDING_RSA_PSS)
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_RSA_PKCS1)
                    .setCertificateSubject(X500Principal("CN=Zapio"))
                    .build()
            )
            generator.generateKeyPair()
        }
        val clientKey = store.getKey(alias, null) as PrivateKey
        val certificate = store.getCertificate(alias) as X509Certificate
        val keys = object : X509KeyManager {
            override fun getClientAliases(type: String?, issuers: Array<out Principal>?) = arrayOf(alias)
            override fun chooseClientAlias(types: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = alias
            override fun getServerAliases(type: String?, issuers: Array<out Principal>?): Array<String>? = null
            override fun chooseServerAlias(type: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
            override fun getCertificateChain(requested: String?) = arrayOf(certificate)
            override fun getPrivateKey(requested: String?) = clientKey
        }
        // TVs use self-signed certificates. The displayed PIN binds both keys;
        // the control connection checks the saved fingerprint before sending commands.
        val trust = object : X509TrustManager {
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
        }
        SSLContext.getInstance("TLS").apply { init(arrayOf(keys), arrayOf(trust), null) }
    }
}

private fun rsaBytes(key: RSAPublicKey): ByteArray =
    listOf(key.modulus, key.publicExponent).fold(byteArrayOf()) { out, value ->
        val signed = value.toByteArray()
        out + if (signed.size > 1 && signed[0].toInt() == 0) signed.copyOfRange(1, signed.size) else signed
    }

private fun hexFingerprint(certificate: ByteArray) =
    MessageDigest.getInstance("SHA-256").digest(certificate).joinToString("") { "%02x".format(it.toInt() and 255) }

// Narrow protobuf encoder/decoder for the fields used by the Remote v2 service.
private fun varint(value: Int): ByteArray {
    val out = ByteArrayOutputStream()
    var rest = value
    while (rest and 127 != rest) {
        out.write((rest and 127) or 128)
        rest = rest ushr 7
    }
    out.write(rest)
    return out.toByteArray()
}

private fun uint(field: Int, value: Int) = varint(field shl 3) + varint(value)
private fun bytes(field: Int, value: ByteArray) = varint((field shl 3) or 2) + varint(value.size) + value
private fun string(field: Int, value: String) = bytes(field, value.toByteArray(Charsets.UTF_8))

private fun readVarint(input: InputStream): Long {
    var value = 0L
    for (shift in 0..63 step 7) {
        val byte = input.read()
        if (byte < 0) throw IOException("TV stream ended")
        value = value or ((byte and 127).toLong() shl shift)
        if (byte and 128 == 0) return value
    }
    throw IOException("Invalid TV message")
}

private fun readFrame(input: DataInputStream): ByteArray {
    val length = readVarint(input)
    if (length !in 1..65536) throw IOException("Invalid TV message length")
    return ByteArray(length.toInt()).also { input.readFully(it) }
}

private fun fields(message: ByteArray): Map<Int, Any> {
    val input = DataInputStream(ByteArrayInputStream(message))
    val result = mutableMapOf<Int, Any>()
    while (input.available() != 0) {
        val tag = readVarint(input).toInt()
        when (tag and 7) {
            0 -> result[tag ushr 3] = readVarint(input).toInt()
            1 -> input.readLong()
            2 -> {
                val length = readVarint(input)
                if (length < 0 || length > input.available()) throw IOException("Incomplete TV message")
                result[tag ushr 3] = ByteArray(length.toInt()).also { input.readFully(it) }
            }
            5 -> input.readInt()
            else -> throw IOException("Unsupported TV message type")
        }
    }
    return result
}
