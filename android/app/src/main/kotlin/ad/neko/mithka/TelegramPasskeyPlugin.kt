package ad.neko.mithka

import android.os.Build
import android.os.CancellationSignal
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialCancellationException
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.CreateCredentialInterruptedException
import androidx.credentials.exceptions.CreateCredentialNoCreateOptionException
import androidx.credentials.exceptions.CreateCredentialProviderConfigurationException
import androidx.credentials.exceptions.CreateCredentialUnsupportedException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.GetCredentialInterruptedException
import androidx.credentials.exceptions.GetCredentialProviderConfigurationException
import androidx.credentials.exceptions.GetCredentialUnsupportedException
import androidx.credentials.exceptions.NoCredentialException
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import org.json.JSONObject

/**
 * Credential Manager bridge for Telegram passkeys.
 *
 * Telegram's TDLib supplies WebAuthn options for the telegram.org relying
 * party. Credential Manager must sign the exact clientDataJSON hash while the
 * request is attributed to https://telegram.org; otherwise Telegram will
 * reject the assertion or attestation.
 */
class TelegramPasskeyPlugin(
    private val activity: FragmentActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val credentialManager = CredentialManager.create(activity)
    private var cancellationSignal: CancellationSignal? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            "get" -> getCredential(call, result)
            "create" -> createCredential(call, result)
            "openSettings" -> openSettings(result)
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        cancellationSignal?.cancel()
        cancellationSignal = null
        channel.setMethodCallHandler(null)
    }

    private fun getCredential(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureSupported(result)) return
        val flutterResult = result
        val publicKeyJson = call.argument<String>("publicKeyJson")
        if (publicKeyJson.isNullOrBlank()) {
            flutterResult.error("passkey_invalid", "Missing public-key request", null)
            return
        }

        try {
            val publicKey = JSONObject(publicKeyJson)
            requireTelegramRp(publicKey.optString("rpId"))
            val clientDataJson = clientDataJson(
                type = "webauthn.get",
                challenge = publicKey.getString("challenge"),
            )
            val option = GetPublicKeyCredentialOption(
                requestJson = publicKeyJson,
                clientDataHash = sha256(clientDataJson),
            )
            val request = GetCredentialRequest.Builder()
                .addCredentialOption(option)
                .setOrigin(TELEGRAM_ORIGIN)
                .build()
            val signal = replaceCancellationSignal()
            credentialManager.getCredentialAsync(
                activity,
                request,
                signal,
                activity.mainExecutor,
                object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                    override fun onResult(result: GetCredentialResponse) {
                        if (cancellationSignal === signal) cancellationSignal = null
                        val credential = result.credential
                        if (credential !is PublicKeyCredential) {
                            flutterResult.error(
                                "passkey_invalid",
                                "Credential provider returned an unexpected credential type",
                                null,
                            )
                            return
                        }
                        flutterResult.success(
                            mapOf(
                                "responseJson" to credential.authenticationResponseJson,
                                "clientDataJson" to clientDataJson,
                            ),
                        )
                    }

                    override fun onError(e: GetCredentialException) {
                        if (cancellationSignal === signal) cancellationSignal = null
                        returnCredentialError(e, flutterResult)
                    }
                },
            )
        } catch (error: SecurityException) {
            flutterResult.error("passkey_not_allowed", error.localizedMessage, null)
        } catch (error: Exception) {
            flutterResult.error("passkey_invalid", error.localizedMessage, null)
        }
    }

    private fun createCredential(call: MethodCall, result: MethodChannel.Result) {
        if (!ensureSupported(result)) return
        val flutterResult = result
        val publicKeyJson = call.argument<String>("publicKeyJson")
        if (publicKeyJson.isNullOrBlank()) {
            flutterResult.error("passkey_invalid", "Missing public-key request", null)
            return
        }

        try {
            val publicKey = JSONObject(publicKeyJson)
            requireTelegramRp(publicKey.getJSONObject("rp").optString("id"))
            val clientDataJson = clientDataJson(
                type = "webauthn.create",
                challenge = publicKey.getString("challenge"),
            )
            val request = CreatePublicKeyCredentialRequest(
                requestJson = publicKeyJson,
                clientDataHash = sha256(clientDataJson),
                preferImmediatelyAvailableCredentials = false,
                origin = TELEGRAM_ORIGIN,
            )
            val signal = replaceCancellationSignal()
            credentialManager.createCredentialAsync(
                activity,
                request,
                signal,
                activity.mainExecutor,
                object : CredentialManagerCallback<
                    CreateCredentialResponse,
                    CreateCredentialException,
                > {
                    override fun onResult(result: CreateCredentialResponse) {
                        if (cancellationSignal === signal) cancellationSignal = null
                        if (result !is CreatePublicKeyCredentialResponse) {
                            flutterResult.error(
                                "passkey_invalid",
                                "Credential provider returned an unexpected response type",
                                null,
                            )
                            return
                        }
                        flutterResult.success(
                            mapOf(
                                "responseJson" to result.registrationResponseJson,
                                "clientDataJson" to clientDataJson,
                            ),
                        )
                    }

                    override fun onError(e: CreateCredentialException) {
                        if (cancellationSignal === signal) cancellationSignal = null
                        returnCredentialError(e, flutterResult)
                    }
                },
            )
        } catch (error: SecurityException) {
            flutterResult.error("passkey_not_allowed", error.localizedMessage, null)
        } catch (error: Exception) {
            flutterResult.error("passkey_invalid", error.localizedMessage, null)
        }
    }

    private fun openSettings(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            result.error("passkey_unavailable", "Credential settings require Android 14", null)
            return
        }
        try {
            credentialManager.createSettingsPendingIntent().send()
            result.success(null)
        } catch (error: Exception) {
            result.error("passkey_failed", error.localizedMessage, null)
        }
    }

    private fun ensureSupported(result: MethodChannel.Result): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) return true
        result.error("passkey_unavailable", "Passkeys require Android 9 or newer", null)
        return false
    }

    private fun replaceCancellationSignal(): CancellationSignal {
        cancellationSignal?.cancel()
        return CancellationSignal().also { cancellationSignal = it }
    }

    private fun requireTelegramRp(rpId: String) {
        require(rpId == TELEGRAM_RP_ID) { "Unexpected relying party" }
    }

    private fun clientDataJson(type: String, challenge: String): String =
        JSONObject()
            .put("type", type)
            .put("challenge", challenge)
            .put("origin", TELEGRAM_ORIGIN)
            .toString()

    private fun sha256(value: String): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))

    private fun returnCredentialError(
        error: Exception,
        result: MethodChannel.Result,
    ) {
        val code = when (error) {
            is GetCredentialCancellationException,
            is GetCredentialInterruptedException,
            is CreateCredentialCancellationException,
            is CreateCredentialInterruptedException -> "passkey_cancelled"
            is NoCredentialException -> "passkey_empty"
            is CreateCredentialNoCreateOptionException,
            is GetCredentialProviderConfigurationException,
            is GetCredentialUnsupportedException,
            is CreateCredentialProviderConfigurationException,
            is CreateCredentialUnsupportedException -> "passkey_unavailable"
            else -> "passkey_failed"
        }
        result.error(code, error.localizedMessage, null)
    }

    private companion object {
        const val CHANNEL = "mithka/passkeys"
        const val TELEGRAM_RP_ID = "telegram.org"
        const val TELEGRAM_ORIGIN = "https://telegram.org"
    }
}
