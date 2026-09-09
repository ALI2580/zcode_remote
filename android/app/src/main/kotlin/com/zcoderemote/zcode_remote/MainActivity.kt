package com.zcoderemote.zcode_remote

import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private var notifications: MethodChannel? = null
    private var dartReady = false
    private var foreground = false
    private var pendingPayload: String? = null
    private var permissionResult: MethodChannel.Result? = null
    private val permissionCode = 4096
    private var attachmentPicker: AttachmentPicker? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "zcode_remote/platform").setMethodCallHandler { call, result ->
            when (call.method) {
                "timeZone" -> result.success(java.util.TimeZone.getDefault().id)
                "quotaReadOnlyAudit" -> result.success(
                    (packageName.endsWith(".dev") || packageName.endsWith(".qa")) &&
                        intent?.getBooleanExtra("quotaReadOnlyAudit", false) == true
                )
                else -> result.notImplemented()
            }
        }
        attachmentPicker = AttachmentPicker(this, messenger)
        notifications = MethodChannel(messenger, "zcode_remote/notifications").also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "initialize" -> {
                            dartReady = true
                            val payload = pendingPayload ?: intent?.getStringExtra("notificationTask")
                            pendingPayload = null
                            intent?.removeExtra("notificationTask")
                            result.success(payload)
                        }
                        "capabilities" -> result.success(mapOf(
                            "allowed" to hasNotificationPermission(),
                            "promotedSupported" to (Build.VERSION.SDK_INT >= 36),
                            "promotedAllowed" to promotedAllowed(),
                            "dismissed" to TaskNotificationEvents.dismissed(this),
                            "sdkInt" to Build.VERSION.SDK_INT,
                            "foreground" to foreground,
                            "progressServiceRunning" to (TaskProgressService.instance != null),
                            "progressVisible" to getSystemService(NotificationManager::class.java)
                                .activeNotifications.any { it.id == TaskProgressService.ID }
                        ))
                        "requestPermission" -> requestNotificationPermission(result)
                        "showProgress" -> {
                            val allowed = hasNotificationPermission()
                            result.success(allowed && TaskProgressService.show(
                                this,
                                call.argument<String>("title") ?: "任务运行中",
                                call.argument<String>("text") ?: "",
                                call.argument<String>("shortText") ?: "工作中",
                                call.argument<String>("payload") ?: "{}",
                                foreground && call.argument<Boolean>("allowStart") == true
                            ))
                        }
                        "stopProgress" -> {
                            stopService(Intent(this, TaskProgressService::class.java))
                            result.success(null)
                        }
                        "showFinished" -> {
                            if (hasNotificationPermission()) TaskProgressService.finished(
                                this, call.argument<String>("title") ?: "任务结果",
                                call.argument<String>("text") ?: "",
                                call.argument<String>("key") ?: "task",
                                call.argument<String>("payload") ?: "{}"
                            )
                            result.success(null)
                        }
                        "openSettings" -> {
                            val settingsIntent = if (Build.VERSION.SDK_INT >= 26) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            }
                            startActivity(settingsIntent)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("notifications_unavailable", "系统暂时无法显示任务通知", null)
                }
            }
        }
        TaskNotificationEvents.listener = { method, payload -> notifications?.invokeMethod(method, payload) }
        MethodChannel(messenger, "zcode_remote/crypto").setMethodCallHandler { call, result ->
            try {
                val value = call.argument<String>("value") ?: ""
                when (call.method) {
                    "encrypt" -> {
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.ENCRYPT_MODE, credentialKey())
                        result.success(Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP))
                    }
                    "decrypt" -> {
                        val bytes = Base64.decode(value, Base64.NO_WRAP)
                        require(bytes.size >= 28)
                        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(Cipher.DECRYPT_MODE, credentialKey(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
                        result.success(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
                    }
                    else -> result.notImplemented()
                }
            } catch (_: Exception) {
                result.error("credentials_unavailable", "设备凭据暂时不可用，请重新添加连接链接", null)
            }
        }
    }

    private fun credentialKey(): SecretKey {
        val alias = "zcode_remote_device_credentials"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256).build())
            generateKey()
        }
    }

    private fun hasNotificationPermission(): Boolean =
        NotificationManagerCompat.from(this).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED)

    private fun promotedAllowed(): Boolean? {
        if (Build.VERSION.SDK_INT < 36) return null
        return try {
            // Some OEM SDK builds omit this framework symbol; query it without
            // taking a compile-time dependency on a flagged framework API.
            NotificationManager::class.java.getMethod("canPostPromotedNotifications")
                .invoke(getSystemService(NotificationManager::class.java)) as? Boolean
        } catch (_: Exception) { null }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (hasNotificationPermission()) {
            TaskNotificationEvents.setDismissed(this, false)
            result.success(true)
        } else if (Build.VERSION.SDK_INT >= 33 && permissionResult == null) {
            permissionResult = result
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionCode)
        } else {
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionCode) {
            val allowed = hasNotificationPermission()
            if (allowed) TaskNotificationEvents.setDismissed(this, false)
            permissionResult?.success(allowed)
            permissionResult = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingPayload = intent?.getStringExtra("notificationTask")
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingPayload = intent.getStringExtra("notificationTask")
        if (dartReady && pendingPayload != null) {
            notifications?.invokeMethod("onTap", pendingPayload)
            pendingPayload = null
            intent.removeExtra("notificationTask")
        }
    }
    override fun onResume() { super.onResume(); foreground = true }
    override fun onPause() { foreground = false; super.onPause() }
    override fun popSystemNavigator(): Boolean {
        // Keep the relay's Flutter engine alive when root back backgrounds an
        // actively monitored task, instead of leaving a stale native notice.
        if (isTaskRoot && TaskProgressService.runningOrStarting) {
            moveTaskToBack(false)
            return true
        }
        return super.popSystemNavigator()
    }
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        attachmentPicker?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        attachmentPicker?.dispose()
        if (isFinishing) stopService(Intent(this, TaskProgressService::class.java))
        TaskNotificationEvents.listener = null
        permissionResult?.success(false)
        permissionResult = null
        notifications = null
        super.onDestroy()
    }
}
