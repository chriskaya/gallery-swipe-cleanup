package fr.kayanet.tamis

import android.app.ActivityManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Secure by default, before the first frame: private photos never
        // reach the recent-apps thumbnail or a screenshot. Dart lifts it only
        // if the user opted out (Settings > Privacy).
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        // With FLAG_SECURE the app switcher cannot show a screenshot: Android
        // draws a flat card in the task's background colour (AOSP
        // AbsAppSnapshotController.drawAppThemeSnapshot), with no room for a
        // logo. Make that card the brand colour rather than black. On API
        // 30-32 the colour comes from the theme's colorBackground.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val brand = getColor(R.color.tamis_brand)
            setTaskDescription(
                ActivityManager.TaskDescription.Builder()
                    .setBackgroundColor(brand)
                    .setPrimaryColor(brand)
                    .build(),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        // Fails closed: a missing argument keeps the window secure.
                        val secure = call.argument<Boolean>("secure") ?: true
                        if (secure) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private companion object {
        const val CHANNEL = "fr.kayanet.tamis/window"
    }
}
