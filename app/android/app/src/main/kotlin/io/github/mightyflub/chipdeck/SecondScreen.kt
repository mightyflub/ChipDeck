// Dual-screen support: when the device has a second display (Ayn Thor's
// bottom screen, an external monitor, ...), show the player controls there
// in a Presentation. The controls are Flutter too (controlsMain() in
// lib/main.dart, lib/ui/controls_screen.dart) running in a second engine;
// they get the player state from the main engine and send actions back,
// both relayed here.
// Copyright (C) 2026 ChipDeck contributors. GPL-2.0-or-later.
package io.github.mightyflub.chipdeck

import android.app.Activity
import android.app.Presentation
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Display
import android.view.WindowManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineGroup
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class SecondScreen(
    private val activity: Activity,
    private val main: MethodChannel,
) : DisplayManager.DisplayListener {
    private val displays = activity.getSystemService(DisplayManager::class.java)
    private var group: FlutterEngineGroup? = null
    private var engine: FlutterEngine? = null
    private var channel: MethodChannel? = null
    private var presentation: ControlsPresentation? = null
    private var started = false
    private var shownAt = 0L

    /** The user's setting ("Controls on second screen"). */
    var enabled = true
        set(value) {
            field = value
            refresh()
        }

    fun start() {
        if (started) return
        started = true
        displays.registerDisplayListener(this, Handler(Looper.getMainLooper()))
        refresh()
    }

    fun stop() {
        if (!started) return
        started = false
        displays.unregisterDisplayListener(this)
        hide()
    }

    /** Frees the controls' engine (when the activity goes away). */
    fun release() {
        stop()
        engine?.destroy()
        engine = null
        channel = null
    }

    /** Whether the controls are showing on another display right now. */
    val showing: Boolean get() = presentation != null

    /**
     * Puts the controls back in front on the other display, after another
     * app opened there covered them.
     */
    fun raise() {
        if (!started || presentation == null) return
        // Not right after showing them (start also counts as coming back).
        if (SystemClock.uptimeMillis() - shownAt < 1000) return
        hide()
        refresh()
    }

    /** Player state from the main engine, for the controls. */
    fun sendState(state: Any?) {
        channel?.invokeMethod("state", state)
    }

    override fun onDisplayAdded(displayId: Int) = refresh()
    override fun onDisplayRemoved(displayId: Int) = refresh()
    override fun onDisplayChanged(displayId: Int) = refresh()

    private fun ownDisplayId(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display?.displayId ?: Display.DEFAULT_DISPLAY
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.displayId
        }

    /** The display that is not showing ChipDeck, preferring presentation displays. */
    private fun targetDisplay(): Display? {
        val own = ownDisplayId()
        fun usable(d: Display) = d.displayId != own && d.state != Display.STATE_OFF
        return displays.getDisplays(DisplayManager.DISPLAY_CATEGORY_PRESENTATION)
            .firstOrNull(::usable)
            ?: displays.displays.firstOrNull(::usable)
    }

    private fun refresh() {
        if (!started) return
        // Only when ChipDeck itself is on the main display: if Android opened
        // it on the second screen, putting the controls on the main one would
        // swap the screens round.
        val onMain = ownDisplayId() == Display.DEFAULT_DISPLAY
        val target = if (enabled && onMain) targetDisplay() else null
        if (target == null) {
            hide()
            return
        }
        if (presentation?.display?.displayId == target.displayId) return
        hide()
        show(target)
    }

    private fun show(display: Display) {
        val e = engine ?: createEngine()
        val p = ControlsPresentation(activity, display, e)
        try {
            p.show()
        } catch (ex: WindowManager.InvalidDisplayException) {
            Log.w(TAG, "Cannot show controls on display ${display.displayId}", ex)
            return
        } catch (ex: RuntimeException) {
            Log.w(TAG, "Cannot show controls on display ${display.displayId}", ex)
            return
        }
        presentation = p
        shownAt = SystemClock.uptimeMillis()
        e.lifecycleChannel.appIsResumed()
        main.invokeMethod("secondScreen", true)
    }

    private fun hide() {
        val p = presentation ?: return
        presentation = null
        p.dismiss()
        engine?.lifecycleChannel?.appIsPaused()
        main.invokeMethod("secondScreen", false)
    }

    private fun createEngine(): FlutterEngine {
        val g = group ?: FlutterEngineGroup(activity).also { group = it }
        val entry = DartExecutor.DartEntrypoint(
            FlutterInjector.instance().flutterLoader().findAppBundlePath(),
            "controlsMain",
        )
        val e = g.createAndRunEngine(activity, entry)
        channel = MethodChannel(e.dartExecutor.binaryMessenger, "chipdeck/controls").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "ready" -> main.invokeMethod("controlsReady", null)
                    "action" -> main.invokeMethod("controlsAction", call.arguments)
                }
                result.success(null)
            }
        }
        engine = e
        return e
    }

    /** A window on the other display holding the controls' FlutterView. */
    private class ControlsPresentation(
        activity: Activity,
        display: Display,
        private val engine: FlutterEngine,
    ) : Presentation(activity, display) {
        private var view: FlutterView? = null

        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            // Touch still works; keys (the handheld's buttons) and focus stay
            // with ChipDeck on the main screen.
            window?.addFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
            val v = FlutterView(context)
            setContentView(v)
            v.attachToFlutterEngine(engine)
            view = v
        }

        override fun onStop() {
            view?.detachFromFlutterEngine()
            view = null
            super.onStop()
        }
    }

    companion object {
        private const val TAG = "ChipDeck"
    }
}
