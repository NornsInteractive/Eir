package com.norns.eir

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.util.Collections
import java.util.UUID
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * System-level Floating Chat Capsule and Overlay Dialog for Android.
 * Appears across all third-party applications when screen sharing is active.
 */
object FloatingChatManager {
    private var windowManager: WindowManager? = null
    private var appContext: Context? = null

    // Views
    private var bubbleView: FrameLayout? = null
    private var badgeView: TextView? = null
    private var chatDialogView: FrameLayout? = null
    private var messagesContainer: LinearLayout? = null
    private var messagesScrollView: ScrollView? = null
    private var inputEditText: EditText? = null

    // Layout Params
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var dialogParams: WindowManager.LayoutParams? = null

    data class ChatMessageItem(
        val id: String,
        val sender: String,
        val text: String,
        val isMe: Boolean,
        val timestamp: Long
    )

    private var isDialogShowing = false
    private var unreadCount = 0
    private val mainHandler = Handler(Looper.getMainLooper())
    private val chatHistory = Collections.synchronizedList(mutableListOf<ChatMessageItem>())

    private fun dpToPx(context: Context, dp: Float): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp,
            context.resources.displayMetrics
        ).toInt()
    }

    /**
     * Show the floating chat bubble if overlay permission is granted.
     */
    fun show(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            return
        }

        mainHandler.post {
            try {
                if (bubbleView != null) return@post
                appContext = context.applicationContext
                windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

                createBubbleView(context)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /**
     * Hide and remove the floating bubble and dialog, and clear chat history.
     */
    fun dismiss() {
        mainHandler.post {
            try {
                closeChatDialog()
                if (bubbleView != null && windowManager != null) {
                    windowManager?.removeViewImmediate(bubbleView)
                    bubbleView = null
                }
                unreadCount = 0
                chatHistory.clear()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /**
     * Add and persist chat message into history, updating UI if open or incrementing unread badge.
     */
    fun addMessage(id: String, sender: String, text: String, isMe: Boolean) {
        synchronized(chatHistory) {
            if (chatHistory.any { it.id == id }) return
            chatHistory.add(ChatMessageItem(id, sender, text, isMe, System.currentTimeMillis()))
        }
        mainHandler.post {
            try {
                if (!isMe && !isDialogShowing) {
                    unreadCount++
                    updateBadge()
                }
                if (isDialogShowing && messagesContainer != null) {
                    appendMessageBubble(sender, text, isMe)
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    /**
     * Notify floating overlay of a new incoming message from viewer.
     */
    fun onNewMessage(sender: String, text: String, id: String = UUID.randomUUID().toString()) {
        addMessage(id, sender, text, isMe = false)
    }

    /**
     * Show floating animated reaction emoji next to floating bubble over all apps.
     */
    fun onReaction(emoji: String) {
        mainHandler.post {
            try {
                val wm = windowManager ?: return@post
                val context = appContext ?: return@post
                val bubbleP = bubbleParams

                val posX = bubbleP?.x ?: dpToPx(context, 20f)
                val posY = bubbleP?.y ?: dpToPx(context, 120f)

                val emojiView = TextView(context).apply {
                    this.text = emoji
                    setTextSize(TypedValue.COMPLEX_UNIT_SP, 32f)
                    gravity = Gravity.CENTER
                }

                val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val sizePx = dpToPx(context, 54f)
                val params = WindowManager.LayoutParams(
                    sizePx,
                    sizePx,
                    layoutType,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = posX + dpToPx(context, 4f)
                    y = max(0, posY - dpToPx(context, 16f))
                }

                wm.addView(emojiView, params)

                // Animate floating upwards, scale and fade out
                emojiView.animate()
                    .translationY(-dpToPx(context, 96f).toFloat())
                    .alpha(0f)
                    .scaleX(1.35f)
                    .scaleY(1.35f)
                    .setDuration(1600L)
                    .withEndAction {
                        try {
                            wm.removeViewImmediate(emojiView)
                        } catch (_: Exception) {}
                    }
                    .start()
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun updateBadge() {
        badgeView?.let { badge ->
            if (unreadCount > 0) {
                badge.visibility = View.VISIBLE
                badge.text = if (unreadCount > 99) "99+" else unreadCount.toString()
            } else {
                badge.visibility = View.GONE
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createBubbleView(context: Context) {
        val wm = windowManager ?: return
        val sizePx = dpToPx(context, 56f)

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 24
            y = dpToPx(context, 160f)
        }
        bubbleParams = params

        val root = FrameLayout(context).apply {
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#E612141A"))
                setStroke(dpToPx(context, 1.5f), Color.parseColor("#55FFFFFF"))
            }
            background = bg
            elevation = dpToPx(context, 8f).toFloat()
        }

        // Icon inside bubble
        val iconView = ImageView(context).apply {
            setImageResource(R.mipmap.ic_launcher)
            layoutParams = FrameLayout.LayoutParams(
                dpToPx(context, 32f),
                dpToPx(context, 32f),
                Gravity.CENTER
            )
        }
        root.addView(iconView)

        // Unread Badge View
        val badge = TextView(context).apply {
            val badgeBg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FF3B30"))
            }
            background = badgeBg
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            gravity = Gravity.CENTER
            visibility = View.GONE
            val bSize = dpToPx(context, 18f)
            layoutParams = FrameLayout.LayoutParams(bSize, bSize, Gravity.TOP or Gravity.END)
        }
        badgeView = badge
        root.addView(badge)

        // Touch Listener for Dragging & Tapping
        root.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isDragging = false

            override fun onTouch(v: View?, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = params.x
                        initialY = params.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isDragging = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = (event.rawX - initialTouchX).toInt()
                        val dy = (event.rawY - initialTouchY).toInt()
                        if (abs(dx) > 12 || abs(dy) > 12) {
                            isDragging = true
                        }
                        if (isDragging) {
                            params.x = initialX + dx
                            params.y = initialY + dy
                            wm.updateViewLayout(root, params)
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            // Tap event: toggle chat dialog
                            toggleChatDialog(context)
                        } else {
                            // Snap to edge on release
                            snapToEdge(context, params, root, wm)
                        }
                        return true
                    }
                }
                return false
            }
        })

        bubbleView = root
        wm.addView(root, params)
    }

    private fun snapToEdge(
        context: Context,
        params: WindowManager.LayoutParams,
        view: View,
        wm: WindowManager
    ) {
        val dm = context.resources.displayMetrics
        val screenWidth = dm.widthPixels
        val targetX = if (params.x + view.width / 2 < screenWidth / 2) {
            16
        } else {
            screenWidth - view.width - 16
        }
        params.x = targetX
        try {
            wm.updateViewLayout(view, params)
        } catch (_: Exception) {}
    }

    private fun toggleChatDialog(context: Context) {
        if (isDialogShowing) {
            closeChatDialog()
        } else {
            openChatDialog(context)
        }
    }

    private fun openChatDialog(context: Context) {
        val wm = windowManager ?: return
        if (chatDialogView != null) return

        unreadCount = 0
        updateBadge()

        val dm = context.resources.displayMetrics
        val dialogWidth = min(dpToPx(context, 340f), (dm.widthPixels * 0.90f).toInt())
        val dialogHeight = min(dpToPx(context, 400f), (dm.heightPixels * 0.60f).toInt())

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            dialogWidth,
            dialogHeight,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
        }
        dialogParams = params

        val root = FrameLayout(context).apply {
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(context, 20f).toFloat()
                setColor(Color.parseColor("#F2161822"))
                setStroke(dpToPx(context, 1.5f), Color.parseColor("#44FFFFFF"))
            }
            background = bg
            elevation = dpToPx(context, 16f).toFloat()
            clipToOutline = true
        }

        val mainLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
            setPadding(
                dpToPx(context, 16f),
                dpToPx(context, 14f),
                dpToPx(context, 16f),
                dpToPx(context, 12f)
            )
        }

        // Header Bar
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                bottomMargin = dpToPx(context, 8f)
            }
        }

        val titleContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f)
        }

        val titleText = TextView(context).apply {
            text = "Eir 投屏互动聊天"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTypeface(typeface, android.graphics.Typeface.BOLD)
        }
        val subText = TextView(context).apply {
            text = "与远端观众即时双向交流"
            setTextColor(Color.parseColor("#99FFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f)
        }
        titleContainer.addView(titleText)
        titleContainer.addView(subText)
        header.addView(titleContainer)

        // Back to Eir App button
        val returnBtn = TextView(context).apply {
            text = "返回App"
            setTextColor(Color.parseColor("#0A84FF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(dpToPx(context, 8f), dpToPx(context, 4f), dpToPx(context, 8f), dpToPx(context, 4f))
            setOnClickListener {
                closeChatDialog()
                bringAppToFront(context)
            }
        }
        header.addView(returnBtn)

        // Close button
        val closeBtn = TextView(context).apply {
            text = "✕"
            setTextColor(Color.parseColor("#AAFFFFFF"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setPadding(dpToPx(context, 8f), dpToPx(context, 4f), dpToPx(context, 4f), dpToPx(context, 4f))
            setOnClickListener {
                closeChatDialog()
            }
        }
        header.addView(closeBtn)
        mainLayout.addView(header)

        // Divider
        val divider = View(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                dpToPx(context, 1f)
            ).apply {
                bottomMargin = dpToPx(context, 8f)
            }
            setBackgroundColor(Color.parseColor("#22FFFFFF"))
        }
        mainLayout.addView(divider)

        // Messages List ScrollView
        val scrollView = ScrollView(context).apply {
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                0,
                1.0f
            )
            isVerticalScrollBarEnabled = true
        }
        val msgContainer = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            )
        }
        scrollView.addView(msgContainer)
        mainLayout.addView(scrollView)
        messagesContainer = msgContainer
        messagesScrollView = scrollView

        // Input row
        val inputRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dpToPx(context, 8f)
            }
        }

        val editText = EditText(context).apply {
            hint = "发消息给观众..."
            setHintTextColor(Color.parseColor("#66FFFFFF"))
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            imeOptions = EditorInfo.IME_ACTION_SEND
            isSingleLine = true
            val editBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(context, 12f).toFloat()
                setColor(Color.parseColor("#2A2C38"))
            }
            background = editBg
            setPadding(
                dpToPx(context, 12f),
                dpToPx(context, 8f),
                dpToPx(context, 12f),
                dpToPx(context, 8f)
            )
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f)
        }
        inputEditText = editText
        inputRow.addView(editText)

        val sendButton = Button(context).apply {
            text = "发送"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            val btnBg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(context, 12f).toFloat()
                setColor(Color.parseColor("#0A84FF"))
            }
            background = btnBg
            layoutParams = LinearLayout.LayoutParams(
                dpToPx(context, 64f),
                dpToPx(context, 36f)
            ).apply {
                marginStart = dpToPx(context, 8f)
            }
            setOnClickListener {
                sendUserMessage(context)
            }
        }
        inputRow.addView(sendButton)

        editText.setOnEditorActionListener { _, actionId, _ ->
            if (actionId == EditorInfo.IME_ACTION_SEND) {
                sendUserMessage(context)
                true
            } else false
        }

        mainLayout.addView(inputRow)
        root.addView(mainLayout)

        chatDialogView = root
        isDialogShowing = true
        unreadCount = 0
        updateBadge()

        // Replay and populate all preserved chat history
        messagesContainer?.removeAllViews()
        synchronized(chatHistory) {
            for (item in chatHistory) {
                appendMessageBubble(item.sender, item.text, item.isMe)
            }
        }
        messagesScrollView?.post {
            messagesScrollView?.fullScroll(View.FOCUS_DOWN)
        }

        wm.addView(root, params)
    }

    private fun sendUserMessage(context: Context) {
        val et = inputEditText ?: return
        val text = et.text.toString().trim()
        if (text.isEmpty()) return

        et.setText("")
        val msgId = UUID.randomUUID().toString()
        addMessage(msgId, "我", text, isMe = true)

        // Route message back to Flutter
        MainActivity.onReplyFromNotification(text)
    }

    private fun appendMessageBubble(sender: String, text: String, isMe: Boolean) {
        val container = messagesContainer ?: return
        val context = container.context ?: return

        val msgLayout = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            gravity = if (isMe) Gravity.END else Gravity.START
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT
            ).apply {
                topMargin = dpToPx(context, 4f)
                bottomMargin = dpToPx(context, 4f)
            }
        }

        val headerText = TextView(context).apply {
            this.text = sender
            setTextColor(if (isMe) Color.parseColor("#70B2FF") else Color.parseColor("#FFB340"))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
            setPadding(dpToPx(context, 4f), 0, dpToPx(context, 4f), dpToPx(context, 2f))
        }
        msgLayout.addView(headerText)

        val bubbleText = TextView(context).apply {
            this.text = text
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            val bg = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dpToPx(context, 10f).toFloat()
                setColor(if (isMe) Color.parseColor("#0A84FF") else Color.parseColor("#34384A"))
            }
            background = bg
            setPadding(
                dpToPx(context, 10f),
                dpToPx(context, 6f),
                dpToPx(context, 10f),
                dpToPx(context, 6f)
            )
        }
        msgLayout.addView(bubbleText)
        container.addView(msgLayout)

        // Auto scroll to bottom
        messagesScrollView?.post {
            messagesScrollView?.fullScroll(View.FOCUS_DOWN)
        }
    }

    private fun closeChatDialog() {
        val wm = windowManager ?: return
        val dialog = chatDialogView ?: return
        try {
            // Hide keyboard if visible
            inputEditText?.let { et ->
                val imm = dialog.context.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
                imm?.hideSoftInputFromWindow(et.windowToken, 0)
            }
            wm.removeViewImmediate(dialog)
        } catch (_: Exception) {}
        chatDialogView = null
        messagesContainer = null
        messagesScrollView = null
        inputEditText = null
        isDialogShowing = false
    }

    private fun bringAppToFront(context: Context) {
        val pm = context.packageManager
        val launchIntent = pm.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
        }
        if (launchIntent != null) {
            context.startActivity(launchIntent)
        }
    }
}
