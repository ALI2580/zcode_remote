package com.zcoderemote.zcode_remote

import android.app.Activity
import android.app.Dialog
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Temporary, explicitly triggered Aliyun CAPTCHA container.
 *
 * This helper exposes only verify/cancel. The WebView cannot access local
 * files, content providers, arbitrary windows, or native commands. Its
 * success result is accepted only from the SDK success callback in the local
 * challenge page.
 */
class CaptchaChallengeHelper(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "zcode_remote/model-captcha"
        private const val SDK_URL =
            "https://o.alicdn.com/captcha-frontend/aliyunCaptcha/AliyunCaptcha.js"
        private const val REQUEST_TIMEOUT_MS = 120_000L
        private val ALLOWED_HOSTS = setOf(
            "o.alicdn.com",
            "aliyun.com",
            "aliyuncs.com",
            "alicdn.com",
        )
        private val REQUIRED_KEYS =
            setOf("region", "prefix", "sceneId", "language", "requestId")
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())
    private var pendingRequestId: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var dialog: Dialog? = null
    private var webView: WebView? = null
    private var timeout: Runnable? = null
    private var disposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (disposed) {
            result.error("captcha_disposed", "CAPTCHA helper is disposed", null)
            return
        }
        when (call.method) {
            "verify" -> begin(call, result)
            "cancel" -> cancel(call, result)
            else -> result.notImplemented()
        }
    }

    private fun begin(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("captcha_busy", "Another CAPTCHA verification is active", null)
            return
        }
        val args = call.arguments as? Map<*, *>
        if (args == null || args.keys.any { it !in REQUIRED_KEYS }) {
            result.error("captcha_invalid_arguments", "Invalid CAPTCHA arguments", null)
            return
        }
        val region = stringArg(args, "region")
        val prefix = stringArg(args, "prefix")
        val sceneId = stringArg(args, "sceneId")
        val language = stringArg(args, "language")
        val requestId = stringArg(args, "requestId")
        if (region.isEmpty() || prefix.isEmpty() || sceneId.isEmpty() ||
            requestId.isEmpty() || (language != "cn" && language != "en")
        ) {
            result.error("captcha_invalid_arguments", "Invalid CAPTCHA arguments", null)
            return
        }
        pendingRequestId = requestId
        pendingResult = result
        showChallenge(region, prefix, sceneId, language, requestId)
    }

    private fun cancel(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val requestId = args?.get("requestId") as? String
        if (requestId != null && requestId == pendingRequestId) {
            finishError("captcha_cancelled", "CAPTCHA verification was cancelled")
        }
        result.success(null)
    }

    private fun showChallenge(
        region: String,
        prefix: String,
        sceneId: String,
        language: String,
        requestId: String,
    ) {
        val view = WebView(activity)
        webView = view
        view.setBackgroundColor(Color.TRANSPARENT)
        view.settings.javaScriptEnabled = true
        view.settings.domStorageEnabled = true
        view.settings.allowFileAccess = false
        view.settings.allowContentAccess = false
        view.settings.allowFileAccessFromFileURLs = false
        view.settings.allowUniversalAccessFromFileURLs = false
        view.settings.javaScriptCanOpenWindowsAutomatically = false
        view.settings.setSupportMultipleWindows(false)
        view.settings.cacheMode = android.webkit.WebSettings.LOAD_NO_CACHE
        view.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(
                view: WebView,
                request: WebResourceRequest,
            ): Boolean = !allowed(request.url)

            @Suppress("DEPRECATION")
            override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean =
                !allowed(Uri.parse(url))

            override fun shouldInterceptRequest(
                view: WebView,
                request: WebResourceRequest,
            ): WebResourceResponse? {
                val scheme = request.url.scheme?.lowercase()
                if (scheme == "data" || scheme == "blob") {
                    return super.shouldInterceptRequest(view, request)
                }
                if (!allowed(request.url)) {
                    return WebResourceResponse(
                        "text/plain",
                        "UTF-8",
                        java.io.ByteArrayInputStream(ByteArray(0)),
                    )
                }
                return super.shouldInterceptRequest(view, request)
            }

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError,
            ) {
                if (request.isForMainFrame && pendingRequestId == requestId) {
                    finishError(
                        "captcha_sdk_failed",
                        "CAPTCHA challenge page failed to load",
                        requestId,
                    )
                }
            }
        }
        view.addJavascriptInterface(JavascriptBridge(requestId), "ZcodeCaptchaBridge")

        val container = FrameLayout(activity)
        container.setPadding(24, 24, 24, 24)
        container.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        val challengeDialog = Dialog(activity)
        challengeDialog.setTitle(if (language == "cn") "人机验证" else "Human verification")
        challengeDialog.setContentView(container)
        challengeDialog.setCanceledOnTouchOutside(false)
        challengeDialog.setOnCancelListener {
            if (pendingRequestId == requestId) {
                finishError("captcha_cancelled", "CAPTCHA verification was cancelled")
            }
        }
        dialog = challengeDialog
        challengeDialog.show()
        challengeDialog.window?.setLayout(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        )
        challengeDialog.window?.setGravity(Gravity.CENTER)

        timeout = Runnable {
            if (pendingRequestId == requestId) {
                finishError("captcha_timeout", "CAPTCHA verification timed out")
            }
        }.also { handler.postDelayed(it, REQUEST_TIMEOUT_MS) }

        val page = try {
            activity.assets.open("captcha_challenge.html").bufferedReader().use { it.readText() }
        } catch (_: Exception) {
            finishError("captcha_sdk_failed", "CAPTCHA challenge page is unavailable", requestId)
            return
        }
        val config = JSONObject()
            .put("region", region)
            .put("prefix", prefix)
            .put("sceneId", sceneId)
            .put("language", language)
            .put("requestId", requestId)
        // JSONObject escapes JSON syntax, while these additional escapes keep
        // remote configuration text from terminating the inline script.
        val safeConfig = config.toString()
            .replace("&", "\\u0026")
            .replace("<", "\\u003c")
            .replace(">", "\\u003e")
            .replace("\u2028", "\\u2028")
            .replace("\u2029", "\\u2029")
        val html = page.replace("__ZCODE_CAPTCHA_CONFIG__", safeConfig)
        view.loadDataWithBaseURL(
            "https://o.alicdn.com/",
            html,
            "text/html",
            "UTF-8",
            null,
        )
    }

    private fun allowed(uri: Uri): Boolean {
        if (uri.scheme?.lowercase() != "https") return false
        val host = uri.host?.lowercase() ?: return false
        return ALLOWED_HOSTS.any { host == it || host.endsWith(".$it") }
    }

    private fun finishSuccess(value: String, expectedRequestId: String? = null) {
        if (expectedRequestId != null && pendingRequestId != expectedRequestId) return
        val trimmed = value.trim()
        if (trimmed.isEmpty()) {
            finishError(
                "captcha_sdk_invalid_result",
                "CAPTCHA SDK returned no verification parameter",
                expectedRequestId,
            )
            return
        }
        val callback = pendingResult ?: return
        clearChallenge()
        callback.success(trimmed)
    }

    private fun finishError(
        code: String,
        message: String,
        expectedRequestId: String? = null,
    ) {
        if (expectedRequestId != null && pendingRequestId != expectedRequestId) return
        val callback = pendingResult ?: return
        clearChallenge()
        callback.error(code, message, null)
    }

    private fun clearChallenge() {
        timeout?.let(handler::removeCallbacks)
        timeout = null
        dialog?.setOnCancelListener(null)
        dialog?.dismiss()
        dialog = null
        webView?.apply {
            stopLoading()
            loadUrl("about:blank")
            removeJavascriptInterface("ZcodeCaptchaBridge")
            destroy()
        }
        webView = null
        pendingRequestId = null
        pendingResult = null
    }

    fun dispose() {
        if (disposed) return
        disposed = true
        if (pendingResult != null) {
            finishError("captcha_disposed", "CAPTCHA helper is disposed")
        } else {
            clearChallenge()
        }
        channel.setMethodCallHandler(null)
    }

    private fun stringArg(args: Map<*, *>, key: String): String =
        (args[key] as? String)?.trim() ?: ""

    private inner class JavascriptBridge(private val requestId: String) {
        @JavascriptInterface
        fun onResult(payload: String?) {
            val raw = payload ?: return
            activity.runOnUiThread {
                if (pendingResult == null || pendingRequestId != requestId) {
                    return@runOnUiThread
                }
                try {
                    val value = JSONObject(raw)
                    when (value.optString("type")) {
                        "success" -> {
                            val param = value.opt("param")
                            if (param is String && param.trim().isNotEmpty()) {
                                finishSuccess(param, requestId)
                            } else {
                                finishError(
                                    "captcha_sdk_invalid_result",
                                    "CAPTCHA SDK returned no verification parameter",
                                    requestId,
                                )
                            }
                        }
                        "error" -> finishError(
                            "captcha_sdk_failed",
                            value.optString("message", "CAPTCHA verification failed"),
                            requestId,
                        )
                    }
                } catch (_: Exception) {
                    finishError(
                        "captcha_sdk_invalid_result",
                        "CAPTCHA SDK returned an invalid result",
                        requestId,
                    )
                }
            }
        }
    }

}
