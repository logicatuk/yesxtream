package io.github.clubanderson.clubtivi

import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.util.Rational
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val INSTALLER_CHANNEL = "io.github.clubanderson.clubtivi/installer"
    private val PIP_CHANNEL = "io.github.clubanderson.clubtivi/pip"
    private val PLATFORM_CHANNEL = "io.github.clubanderson.clubtivi/platform"
    private var pipChannel: MethodChannel? = null
    private var lastDpadMs = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
        hideSystemUI()
    }

    override fun onResume() {
        super.onResume()
        ensureTvFlutterFocus()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemUI()
            ensureTvFlutterFocus()
        }
    }

    @Suppress("DEPRECATION")
    private fun isTvHardware(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        if (uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION) {
            return true
        }
        val pm = packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION) ||
            pm.hasSystemFeature("amazon.hardware.fire_tv")
        ) {
            return true
        }
        return !pm.hasSystemFeature(PackageManager.FEATURE_TOUCHSCREEN)
    }

    private fun findFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findFlutterView(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private fun ensureTvFlutterFocus() {
        if (!isTvHardware()) return
        val decor = window?.decorView ?: return
        decor.post {
            val flutterView = findFlutterView(decor) ?: return@post
            if (!flutterView.isFocusable) flutterView.isFocusable = true
            if (!flutterView.isFocusableInTouchMode) flutterView.isFocusableInTouchMode = true
            if (!flutterView.hasFocus()) {
                flutterView.requestFocus()
            }
        }
    }

    private fun isDpadKey(code: Int): Boolean {
        return code == KeyEvent.KEYCODE_DPAD_UP ||
            code == KeyEvent.KEYCODE_DPAD_DOWN ||
            code == KeyEvent.KEYCODE_DPAD_LEFT ||
            code == KeyEvent.KEYCODE_DPAD_RIGHT
    }

    private fun isOkKey(code: Int): Boolean {
        return code == KeyEvent.KEYCODE_DPAD_CENTER ||
            code == KeyEvent.KEYCODE_ENTER ||
            code == KeyEvent.KEYCODE_NUMPAD_ENTER ||
            code == KeyEvent.KEYCODE_BUTTON_A ||
            code == KeyEvent.KEYCODE_BUTTON_SELECT
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!isTvHardware()) return super.dispatchKeyEvent(event)

        // Fire Stick remotes report Select as DPAD center, BUTTON_A, or
        // BUTTON_SELECT depending on the Fire OS build. Flutter treats
        // DPAD center as LogicalKeyboardKey.select.
        val outgoing = if (
            event.keyCode == KeyEvent.KEYCODE_BUTTON_SELECT ||
            event.keyCode == KeyEvent.KEYCODE_BUTTON_A
        ) {
            KeyEvent(
                event.downTime,
                event.eventTime,
                event.action,
                KeyEvent.KEYCODE_DPAD_CENTER,
                event.repeatCount,
                event.metaState,
            )
        } else {
            event
        }

        if (outgoing.action == KeyEvent.ACTION_DOWN && outgoing.repeatCount > 0) {
            if (isOkKey(outgoing.keyCode)) return true
            if (isDpadKey(outgoing.keyCode)) {
                if (outgoing.eventTime - lastDpadMs < 115L) return true
                lastDpadMs = outgoing.eventTime
            }
        } else if (outgoing.action == KeyEvent.ACTION_DOWN && isDpadKey(outgoing.keyCode)) {
            lastDpadMs = outgoing.eventTime
        }

        return super.dispatchKeyEvent(outgoing)
    }

    private fun hideSystemUI() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        val controller = WindowInsetsControllerCompat(window, window.decorView)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        controller.systemBarsBehavior =
            WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE

        @Suppress("DEPRECATION")
        window.decorView.systemUiVisibility = (
            android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            or android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            or android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            or android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
            or android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            or android.view.View.SYSTEM_UI_FLAG_FULLSCREEN
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Installer Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("filePath")
                if (filePath != null) {
                    try {
                        installApk(filePath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("INSTALL_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARG", "filePath is required", null)
                }
            } else {
                result.notImplemented()
            }
        }

        // PiP Channel
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isPipSupported" -> {
                        val supported = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
                        } else {
                            false
                        }
                        result.success(supported)
                    }
                    "enterPip" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val numerator = call.argument<Int>("aspectNumerator") ?: 16
                            val denominator = call.argument<Int>("aspectDenominator") ?: 9
                            try {
                                val rational = Rational(numerator.coerceAtLeast(1), denominator.coerceAtLeast(1))
                                val builder = PictureInPictureParams.Builder()
                                    .setAspectRatio(rational)
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    builder.setAutoEnterEnabled(true)
                                }
                                val success = enterPictureInPictureMode(builder.build())
                                result.success(success)
                            } catch (e: Exception) {
                                result.error("PIP_ERROR", e.message, null)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "isInPip" -> {
                        val inPip = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            isInPictureInPictureMode
                        } else {
                            false
                        }
                        result.success(inPip)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Platform / TV hardware detection Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isTvDevice" -> result.success(isTvHardware())
                else -> result.notImplemented()
            }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        val uri = FileProvider.getUriForFile(this, "${applicationContext.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}

