import 'package:flutter/widgets.dart';

class AppI18n {
  final Locale locale;
  AppI18n(this.locale);

  static AppI18n of(BuildContext context) {
    return Localizations.of<AppI18n>(context, AppI18n) ??
        AppI18n(const Locale('zh', 'CN'));
  }

  bool get isZh => locale.languageCode.startsWith('zh');

  // App & Navigation
  String get appTitle => isZh ? 'Eir · P2P 同步影厅' : 'Eir · Synchronized Cinema';
  String get sync => 'Sync';
  String get navLobby => isZh ? '大厅' : 'Lobby';
  String get navRoom => isZh ? '放映室' : 'Cinema';
  String get mobileNavLobby => isZh ? '大厅' : 'Lobby';
  String get mobileNavScreenShare => isZh ? '投屏' : 'Cast';
  String get mobileNavSettings => isZh ? '设置' : 'Settings';
  String get mobileNavProfile => isZh ? '我的' : 'Me';
  String get profileTitle => isZh ? '个人中心' : 'Profile';
  String get editAvatar => isZh ? '更换头像' : 'Change Avatar';
  String get selectAvatarPreset => isZh ? '选择预设头像' : 'Choose Avatar Preset';
  String get customAvatar => isZh ? '自定义图片' : 'Custom Image';
  String get editNickname => isZh ? '修改昵称' : 'Edit Nickname';
  String get nicknameHint => isZh ? '请输入昵称 (1-20 字符)' : 'Enter nickname (1-20 chars)';
  String get nicknameSaved => isZh ? '昵称已更新' : 'Nickname updated';
  String get avatarUpdated => isZh ? '头像已更新' : 'Avatar updated';
  String get preferencesAndSettings => isZh ? '偏好与设置' : 'Preferences & Settings';
  String get networkAndSignaling => isZh ? '信令与网络' : 'Network & Signaling';
  String get storageAndCache => isZh ? '存储与缓存' : 'Storage & Cache';
  String get clearCache => isZh ? '清理缓存' : 'Clear Cache';
  String get cacheCleared => isZh ? '媒体缓存已清理' : 'Media cache cleared';
  String get aboutEir => isZh ? '关于 Eir' : 'About Eir';
  String get securityFingerprint => isZh ? '安全身份指纹' : 'Security Identity Fingerprint';
  String get copiedToClipboard => isZh ? '已复制到剪贴板' : 'Copied to clipboard';
  String get filePickerFailed => isZh ? '选择文件失败，请检查文件权限' : 'Failed to pick file. Please check permissions';
  String get defaultUserNickname => isZh ? '影视爱好者' : 'Cinema Fan';
  String get userNickname => isZh ? '我的设备' : 'My Device';
  String get checkUpdate => isZh ? '检查更新' : 'Check for Updates';
  String get checkingUpdate => isZh ? '正在检查更新...' : 'Checking for updates...';
  String get currentVersion => isZh ? '当前版本' : 'Current Version';
  String get latestVersionAlready => isZh ? '当前已是最新版本' : 'You are on the latest version';
  String get updateAvailable => isZh ? '发现新版本' : 'New Version Available';
  String get updateChangelog => isZh ? '更新内容' : 'Release Notes';
  String get updateDownloadNow => isZh ? '立即下载' : 'Download Now';
  String get updateDownloading => isZh ? '正在下载更新...' : 'Downloading update...';
  String get updateDownloadComplete => isZh ? '下载完成，正在准备安装' : 'Download complete, preparing install';
  String get updateInstallNow => isZh ? '立即安装' : 'Install Now';
  String get updateDownloadFailed => isZh ? '下载失败，请稍后重试' : 'Download failed, please retry';
  String get updateOpenInBrowser => isZh ? '在浏览器中打开' : 'Open in Browser';
  String get updateRetry => isZh ? '重试下载' : 'Retry Download';
  String get updateLater => isZh ? '稍后再说' : 'Later';
  String get updateCheckFailed => isZh ? '检查更新失败，请稍后重试' : 'Failed to check updates';
  String get close => isZh ? '关闭' : 'Close';
  String get done => isZh ? '完成' : 'Done';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get confirm => isZh ? '确认' : 'Confirm';

  // Hero & Lobby
  String get heroBadge => isZh ? '同步放映室' : 'Synchronized Cinema';
  String get heroTitle => isZh ? '双人同步观影' : 'Synchronized Watch Party';
  String get heroSubtitle => isZh
      ? '支持本地视频与网络流媒体同步播放，私密直连。'
      : 'Synchronized playback of local videos and streaming media via private connection.';
  String get createRoom => isZh ? '创建专属放映室' : 'Create Cinema Room';
  String get inputPlaceholder =>
      isZh ? '输入 6 位房间码或粘贴邀请链接' : 'Enter 6-digit code or paste invite';
  String get roomCodeLabel => isZh ? '6 位房间码' : '6-Digit Room Code';
  String get roomCodeHint => isZh ? '请输入 6 位数字房间码' : 'Enter 6-digit room code';
  String get enterRoomCode => isZh ? '输入房间码' : 'Room Code';
  String get shareRoomCode => isZh ? '房间码已生成，点击复制' : 'Room code generated, tap to copy';
  String get shuffleNickname => isZh ? '随机换名' : 'Shuffle';
  String get pasteJoin => isZh ? '快捷加入' : 'Quick Join';
  String get joinRoom => isZh ? '加入放映室' : 'Join Cinema';
  String get signalingUrl => isZh ? '信令服务器地址' : 'Signaling Server URL';
  String get signalingUrlHint => isZh ? '默认 wss://eir.norns.cc.cd/ws' : 'Default wss://eir.norns.cc.cd/ws';
  String get configuringSignaling => isZh ? '信令配置' : 'Signaling Config';
  String get save => isZh ? '保存' : 'Save';
  String get saving => isZh ? '保存中...' : 'Saving...';
  String get signalingSaved => isZh ? '信令地址已保存' : 'Signaling URL saved';
  String get signalingSaveError => isZh
      ? '信令地址格式无效，必须以 ws:// 或 wss:// 开头并包含有效主机名'
      : 'Invalid signaling URL: must start with ws:// or wss:// and include a valid host';
  String get signalingPersistFailed => isZh
      ? '信令地址保存失败，请检查存储权限并重试'
      : 'Failed to save signaling URL. Check storage permissions and retry';
  String get signalingInRoomNotice => isZh
      ? '房内仅保存未来连接地址，不自动打断当前会话'
      : 'Changes take effect for future connections; active session is not interrupted';

  // Root & Initialization
  String get initializingEngine => isZh ? '正在准备放映环境...' : 'Preparing cinema...';
  String get initFailed => isZh ? '客户端初始化失败' : 'Client initialization failed';
  String get retryInit => isZh ? '重试初始化' : 'Retry Init';

  // Connection & Room Status
  String get stateDisconnected => isZh ? '未连接' : 'Disconnected';
  String get stateConnecting => isZh ? '正在进入房间...' : 'Joining room...';
  String get stateConnected => isZh ? '已就绪 · 观影中' : 'Connected · Ready';
  String get stateReconnecting => isZh ? '网络波动，正在重新连线...' : 'Reconnecting...';
  String get retryConnection => isZh ? '重试连接' : 'Retry Connection';
  String get retryingConnection => isZh ? '正在重试连接...' : 'Retrying Connection...';
  String get disconnectedBannerText => isZh
      ? '放映室连接已断开，可点击重试恢复连接'
      : 'Room connection lost. Tap retry to reconnect.';

  // Roles & ACL
  String get roleOwner => isZh ? '房主' : 'HOST';
  String get roleAdmin => isZh ? '管理员' : 'ADMIN';
  String get roleMember => isZh ? '成员' : 'MEMBER';
  String get hostBadge => isZh ? 'HOST 房主' : 'HOST';
  String get grantAdmin => isZh ? '设为管理员' : 'Grant Admin';
  String get revokeAdmin => isZh ? '取消管理员' : 'Revoke Admin';
  String get peerYou => isZh ? '(你)' : '(You)';
  String get readOnlyControlTooltip =>
      isZh ? '仅房主或管理员可以控制播放' : 'Only Host or Admin can control playback';

  // Cinema View Header & HUD
  String peersConnected(int count) =>
      isZh ? '$count 人同看' : '$count Watching';
  String get copyInvite => isZh ? '复制邀请' : 'Copy Invite';
  String get copyRoomCode => isZh ? '复制房间码' : 'Copy Room Code';
  String get roomCodeCopied => isZh ? '已复制房间码到剪贴板' : 'Room code copied to clipboard';
  String get inviteRoomTitle => isZh ? '放映室邀请' : 'Room Invitation';
  String get inviteCopied => isZh ? '已复制邀请凭据到剪贴板' : 'Invite payload copied to clipboard';
  String get leaveRoom => isZh ? '离开房间' : 'Leave Room';
  String get disbandRoom => isZh ? '解散房间' : 'Disband Room';
  String get disbandPendingNotice => isZh
      ? '正在解散放映室...'
      : 'Disbanding room...';
  String get playTooltip => isZh ? '播放 (全员同步)' : 'Play (Synced)';
  String get pauseTooltip => isZh ? '暂停 (全员同步)' : 'Pause (Synced)';
  String get muteTooltip => isZh ? '静音' : 'Mute';
  String get unmuteTooltip => isZh ? '取消静音' : 'Unmute';
  String get fullscreenTooltip => isZh ? '全屏' : 'Fullscreen';
  String get fullscreen => fullscreenTooltip;
  String get exitFullscreenTooltip => isZh ? '退出全屏' : 'Exit Fullscreen';
  String get volumeLabel => isZh ? '音量' : 'Volume';
  String get brightnessLabel => isZh ? '亮度' : 'Brightness';
  String get playbackRate => isZh ? '倍速' : 'Rate';
  String get timelineLabel => isZh ? '播放进度' : 'Playback Progress';
  String get timelineSeekHint => isZh ? '拖动滑块调节进度' : 'Drag to adjust position';
  String get timelineEmptyHint => isZh ? '未加载媒体' : 'No media loaded';
  String get rateChangeHint => isZh ? '切换播放倍速' : 'Cycle playback rate';
  String get selected => isZh ? '已选择' : 'Selected';
  String get lockScreen => isZh ? '锁定控制' : 'Lock Screen';
  String get unlockScreen => isZh ? '解锁控制' : 'Unlock Screen';
  String get screenLocked => isZh ? '屏幕已锁定' : 'Screen locked';
  String get screenUnlocked => isZh ? '屏幕已解锁' : 'Screen unlocked';
  String get aspectRatio => isZh ? '比例' : 'Aspect';
  String get fastForward10 => isZh ? '+10秒' : '+10s';
  String get rewind10 => isZh ? '-10秒' : '-10s';

  // Dock Tabs
  String get tabChat => isZh ? '聊天' : 'Chat';
  String get tabPlaylist => isZh ? '播放列表' : 'Playlist';
  String get tabMembers => isZh ? '同看好友' : 'Friends';
  String get tabSession => isZh ? '放映详情' : 'Room Info';

  // Chat & Calling
  String get chatEmptyNotice => isZh ? '暂无聊天记录，发条消息和好友互动吧' : 'No messages yet. Send a message to chat!';
  String get sendChatHint => isZh ? '发一条弹幕聊天...' : 'Send chat & danmaku...';
  String get send => isZh ? '发送' : 'Send';
  String get callVoice => isZh ? '语音通话' : 'Voice Call';
  String get callVideo => isZh ? '视频通话' : 'Video Call';
  String get callIncomingVoice => isZh ? '邀请你进行语音通话' : 'invited you to a voice call';
  String get callIncomingVideo => isZh ? '邀请你进行视频通话' : 'invited you to a video call';
  String get callAccept => isZh ? '接听' : 'Accept';
  String get callDecline => isZh ? '拒绝' : 'Decline';
  String get callEnd => isZh ? '挂断' : 'End';
  String get callEnded => isZh ? '通话已结束' : 'Call ended';
  String get callConnecting => isZh ? '正在呼叫...' : 'Calling...';
  String get callConnected => isZh ? '通话中' : 'In Call';
  String get callBusy => isZh ? '对方忙或已拒绝' : 'Peer is busy or declined';
  String get cameraFlip => isZh ? '翻转' : 'Flip';
  String get cameraToggle => isZh ? '摄像头' : 'Camera';
  String get micToggle => isZh ? '麦克风' : 'Mic';
  String get speakerToggle => isZh ? '扬声器' : 'Speaker';
  String get voiceCallStarted => isZh ? '发起了语音通话' : 'started a voice call';
  String get videoCallStarted => isZh ? '发起了视频通话' : 'started a video call';

  // Playlist & Media
  String get addMedia => isZh ? '添加媒体' : 'Add Media';
  String get addVideoUrl => isZh ? '网络视频 URL' : 'Network Video URL';
  String get addLocalFile => isZh ? '选择本地视频' : 'Pick Local Video';
  String get urlDialogTitle => isZh ? '添加网络点播源' : 'Add Video URL';
  String get urlInputPlaceholder => isZh ? '输入 HTTPS 视频直链...' : 'Enter HTTPS direct video URL...';
  String get mediaTitlePlaceholder => isZh ? '视频标题 (可选)...' : 'Media title (optional)...';
  String get nowPlayingBadge => isZh ? '正在播放' : 'NOW PLAYING';
  String get playlistEmpty => isZh ? '播放列表暂无内容，点击上方按钮添加' : 'Playlist is empty. Add a video to start.';
  String get removeMedia => isZh ? '移除条目' : 'Remove';
  String get switchMedia => isZh ? '切换到此条目' : 'Switch to this item';
  String get replaceMedia => isZh ? '替换此条目' : 'Replace item';
  String get replaceDialogTitle => isZh ? '替换播单条目' : 'Replace Media Item';
  String get moveUp => isZh ? '上移' : 'Move up';
  String get moveDown => isZh ? '下移' : 'Move down';
  String get localFileNotice => isZh
      ? '注：支持常见主流音视频格式点播'
      : 'Note: Supports common standard media streaming';

  // Telemetry & Session Info
  String get sessionIdLabel => isZh ? '会话 ID' : 'Session ID';
  String get roomIdLabel => isZh ? '房间 ID' : 'Room ID';
  String get deviceIdLabel => isZh ? '本机设备指纹' : 'Device ID';
  String get ed25519KeyLabel => isZh ? 'Ed25519 公钥' : 'Ed25519 Public Key';
  String get currentSeqLabel => isZh ? '权威操作序列号 (Seq)' : 'Authoritative Sequence (Seq)';
  String get localPlaybackPos => isZh ? '当前渲染位置' : 'Render Position';
  String get syncTargetLabel => isZh ? '同步目标' : 'Sync Target';
  String get bufferingLabel => isZh ? '缓冲中...' : 'Buffering...';
  String get telemetryLabel => isZh ? '成员同步状态' : 'Member Playback State';
  String get telemetryPosition => isZh ? '进度' : 'Position';
  String get telemetryBuffering => isZh ? '缓冲中' : 'Buffering';
  String get telemetrySynced => isZh ? '已同步' : 'Synced';
  String get telemetryUnknown => isZh ? '未知' : 'Unknown';
  String get telemetryNoData => isZh ? '暂无遥测' : 'No telemetry';

  // Overlays & Error Handling
  String get sourceOfflineTitle => isZh ? '供片端暂时离线' : 'Media Source Offline';
  String get sourceOfflineDesc => isZh
      ? '该条目的提供者连接中断，正在等待重新连线以恢复播放...'
      : 'The peer supplying this media is disconnected. Waiting for recovery...';
  String get dismissError => isZh ? '知道了' : 'Dismiss';

  // Stable error code localization
  String mapErrorCode(String? code) {
    if (code == null || code.isEmpty) return '';
    switch (code) {
      case 'invalid_invite':
        return isZh ? '邀请凭据无效或已损坏，请检查格式' : 'Invalid invitation payload or corrupted token';
      case 'invite_expired':
        return isZh ? '邀请凭据已过期，请重新向房主索取' : 'Invitation token has expired, request a new one';
      case 'invite_consumed':
        return isZh ? '此邀请已被其他设备使用' : 'Invitation token has already been consumed by another device';
      case 'permission_denied':
        return isZh ? '权限不足，仅房主或管理员可执行此操作' : 'Permission denied: Host or Admin only';
      case 'unsupported_media':
        return isZh ? '不支持的媒体格式，请检查文件或链接' : 'Unsupported media format, please check the file or link';
      case 'source_offline':
        return isZh ? '媒体源供片端离线，等待网络恢复' : 'Media source peer offline, waiting for reconnection';
      case 'chunk_hash_mismatch':
        return isZh ? '媒体分片哈希校验失败，已拒绝损坏数据' : 'Media chunk hash verification failed';
      case 'signaling_unavailable':
        return isZh ? '无法连接信令服务器，请检查网络或信令地址' : 'Signaling server unavailable, check URL or connection';
      case 'media_probe_failed':
        return isZh ? '媒体资源探测失败，请确认直链可直接访问' : 'Media probe failed, verify direct URL accessibility';
      case 'room_full':
        return isZh ? '房间已满，无法加入' : 'Room is full, cannot join';
      case 'room_closed':
        return isZh ? '房间已被房主关闭或解散' : 'Room was closed by host';
      case 'connection_failed':
        return isZh ? 'P2P WebRTC 连接建立失败' : 'P2P WebRTC connection failed';
      case 'handshake_failed':
        return isZh ? '安全身份握手失败或证书验证未通过' : 'Security handshake failed or certificate mismatch';
      case 'protocol_violation':
        return isZh ? '协议校验失败，拒绝非法消息' : 'Protocol violation, invalid message rejected';
      case 'commit_rejected':
        return isZh ? '操作提交被房间仲裁拒绝' : 'Action commit rejected by room arbitration';
      case 'media_unavailable':
        return isZh ? '底层播放引擎初始化失败或不可用' : 'Playback engine unavailable or initialization failed';
      case 'room_not_found':
        return isZh ? '未找到指定的放映室，可能已解散' : 'Room not found or has been disbanded';
      case 'rate_limited':
        return isZh ? '操作过于频繁，请稍后再试' : 'Rate limit exceeded, please slow down';
      case 'network_timeout':
        return isZh ? '网络请求超时，请检查网络连接' : 'Network request timed out, please retry';
      case 'connection_closed':
        return isZh ? '连接已断开' : 'Connection closed';
      case 'storage_full':
        return isZh
            ? '存储空间不足，无法缓存该视频，请清理空间后重试'
            : 'Not enough storage to cache this video. Free up space and try again';
      case 'identity_unavailable':
        return isZh ? '本地设备身份不可用，请重新初始化' : 'Device identity unavailable, please re-initialize';
      default:
        return isZh ? '发生错误 ($code)，请稍后重试' : 'Error ($code), please try again';
    }
  }

  // Settings
  String get settingsTitle => isZh ? '全局偏好设置' : 'Preferences';
  String get settingsLang => isZh ? '语言 / Language' : 'Language / 语言';
  String get settingsLangHint =>
      isZh ? '即时生效，不丢失房间与播放状态' : 'Takes effect instantly without session loss';
  String get langSystem => isZh ? '跟随系统' : 'System Default';
  String get settingsLangZh => isZh ? '简体中文' : 'Simplified Chinese';
  String get settingsLangEn => isZh ? 'English (US)' : 'English (US)';
  String get settingsThemeMode => isZh ? '主题模式' : 'Theme Mode';
  String get settingsThemeHint => isZh ? '浅色 / 深色 / 跟随系统' : 'Light / Dark / Follow System';
  String get themeSystem => isZh ? '跟随系统' : 'System';
  String get themeLight => isZh ? '浅色模式' : 'Light Mode';
  String get themeDark => isZh ? '深色模式' : 'Dark Mode';
  String get independentColors => isZh ? '独立主题色配置' : 'Independent Theme Colors';
  String get independentColorsDesc => isZh
      ? '浅色与深色主题色独立保存及恢复默认，禁止互串'
      : 'Light & dark colors are saved and reset independently';
  String get lightColor => isZh ? '浅色主题色' : 'Light Theme Accent';
  String get darkColor => isZh ? '深色主题色' : 'Dark Theme Accent';
  String get resetDefault => isZh ? '恢复默认' : 'Reset Default';
  String get backgroundKeepAliveTitle => isZh ? '后台保活' : 'Background Keep-Alive';
  String get backgroundKeepAliveDesc => isZh
      ? '在房主或添加本地视频时保持后台网络连接与分片数据传输'
      : 'Keep connection and streaming active when app is in background';
  String get sourceUserLeftRoom => isZh ? '对方已退出房间' : 'Provider left';
  String get autoSkipNextVideo => isZh ? '添加者已离开房间，自动播放下一条' : 'Provider left, playing next item';
  String get toggleOrientation => isZh ? '横竖屏切换' : 'Toggle Orientation';
  String get enterFullscreen => isZh ? '全屏播放' : 'Fullscreen';
  String get exitFullscreen => isZh ? '退出全屏' : 'Exit Fullscreen';
  String newHostPromoted(String name) => isZh ? '$name 已成为新房主' : '$name is now the host';

  // Preset Colors
  String get colorAppleBlue => isZh ? '经典蓝' : 'Classic Blue';
  String get colorApplePurple => isZh ? '极光紫' : 'Aurora Purple';
  String get colorAppleGreen => isZh ? '薄荷绿' : 'Mint Green';
  String get colorAppleOrange => isZh ? '日落橙' : 'Sunset Orange';
  String get colorApplePink => isZh ? '玫瑰粉' : 'Rose Pink';
  String get colorAppleTeal => isZh ? '青空蓝' : 'Cyan Teal';

  // Custom Color Picker & App Icons
  String get customColor => isZh ? '自定义颜色' : 'Custom Color';
  String get selectColor => isZh ? '选取颜色' : 'Pick Color';
  String get colorHue => isZh ? '色相' : 'Hue';
  String get colorSaturation => isZh ? '饱和度' : 'Saturation';
  String get colorBrightness => isZh ? '明度' : 'Brightness';
  String get colorHexCode => isZh ? '十六进制色值' : 'Hex Code';
  String get applyColor => isZh ? '应用' : 'Apply';
  String get appIconTitle => isZh ? '桌面图标' : 'Launcher Icon';
  String get appIconDesc => isZh
      ? '预设图标直接切换应用主图标；自选图片置于桌面启动快捷方式并在应用内全量生效'
      : 'Preset styles switch the native app icon; custom images pin desktop shortcuts and apply in-app';
  String get appIconUpdated => isZh ? '桌面图标已更新' : 'Launcher icon updated';
  String get pickFromGallery => isZh ? '自选本地图片' : 'Pick Local Image';
  String get shortcutCreated => isZh ? '已请求添加桌面快捷方式' : 'Home screen shortcut requested';

  // Remote Config & Web Transport Engine
  String get serverDomain => isZh ? '服务器域名' : 'Server Domain';
  String get syncRemoteConfig => isZh ? '从云端同步配置' : 'Sync from Cloud';
  String get syncingConfig => isZh ? '正在同步...' : 'Syncing...';
  String get syncSuccess => isZh ? '配置同步成功' : 'Config synced';
  String get syncFailed => isZh ? '同步失败，请检查域名' : 'Sync failed';
  String get lastSyncTime => isZh ? '上次同步' : 'Last sync';
  String get tailcatClientOnly => isZh ? '仅客户端支持' : 'Client only';
  String get tailcatWebUnsupportedNote => isZh
      ? '当前为 Web 浏览器环境，仅支持 WebRTC 传输引擎；Tailcat (WireGuard P2P 底层穿透) 专供桌面端与移动客户端使用。'
      : 'Web browser environment only supports WebRTC; Tailcat engine is reserved for desktop and mobile clients.';

  // Cache Management (V1-PRD §9)
  String get cacheTitle => isZh ? '本地媒体缓存' : 'Media Cache';
  String get cacheDesc => isZh
      ? 'P2P 点播分片流式缓存与上限管理'
      : 'P2P streaming chunk cache & capacity management';
  String get cacheUsage => isZh ? '当前占用' : 'Occupancy';
  String get cacheLimit => isZh ? '容量上限' : 'Capacity Limit';
  String get cacheServiceStatus => isZh ? '缓存子系统' : 'Cache Subsystem';
  String get cacheStatusUninitialized =>
      isZh ? '未启动 (空缓存)' : 'Inactive (Empty cache)';
  String get cacheStatusActive => isZh ? '活跃中' : 'Active';
  String get cacheChunks => isZh ? '缓存分片' : 'Cached Chunks';
  String get cacheHitStats => isZh ? '命中 / 未命中' : 'Hits / Misses';
  String get cacheEvicted => isZh ? '累计淘汰' : 'Evicted';
  String get clearCacheBtn => isZh ? '安全清理非在用缓存' : 'Clean Unprotected Cache';
  String get clearingCache => isZh ? '正在清理...' : 'Cleaning...';
  String get clearCacheNotice => isZh
      ? '说明：仅清理未受保护的非活跃缓存分片，当前正在播放或分发的在用媒体分片及本地原文件将妥善保留。'
      : 'Notice: Only evicts unprotected inactive chunks. In-use playback chunks and source files are safely preserved.';
  String clearCacheSuccess(String freed) => isZh
      ? '已安全释放 $freed 未保护缓存'
      : 'Safely freed $freed of unprotected cache';
  String get clearCacheNone => isZh
      ? '暂无未保护缓存可清理（在用缓存已妥善保留）'
      : 'No unprotected cache to clean (in-use cache preserved)';
  String get clearCacheFailed => isZh
      ? '缓存清理失败，底层媒体服务暂不可用'
      : 'Cache cleanup failed: media service unavailable';

  // Diagnostics (Real values only, no secrets or URLs)
  String get diagTitle => isZh ? '节点诊断与实时状态' : 'Node Diagnostics & Status';
  String get diagSignalingServer => isZh ? '当前信令节点' : 'Signaling Node';
  String get diagDeviceId => isZh ? '本机身份指纹' : 'Local Device ID';
  String get diagRoomId => isZh ? '当前房间 ID' : 'Current Room ID';
  String get diagNotInRoom => isZh ? '未在房间中' : 'Not In Room';
  String get diagConnectionState => isZh ? 'P2P 连接状态' : 'P2P Connection';
  String get diagCurrentRole => isZh ? '当前权限角色' : 'Role & Permissions';
  String get diagActiveMembers => isZh ? '在线成员数' : 'Active Members';
  String get diagPlaylistItemCount => isZh ? '播单条目数' : 'Playlist Items';
  String get diagMediaEngine => isZh ? '底层播放引擎' : 'Media Playback Engine';
  String get diagEngineReady => isZh ? 'media_kit 就绪' : 'media_kit Ready';
  String get diagEngineNotReady => isZh ? '未就绪' : 'Not Ready';
  String get diagProtocolVersion => isZh ? '协议版本' : 'Protocol Version';

  String get footerText => isZh
      ? 'Eir · 异地同屏观影与实时投屏'
      : 'Eir · Synchronized Cinema & Live Screen Share';

  String get organizationTitle => isZh ? '开发组织' : 'Organization';
  String get organizationName => 'Norns Interactive';
  String get organizationDesc => isZh
      ? '跨平台协同与流媒体互联'
      : 'Cross-platform collaboration & real-time streaming';
  String get officialWebsiteTitle => isZh ? '官方网站' : 'Official Website';
  String get officialWebsiteUrl => 'https://norns.cc.cd';
  String get officialWebsiteDesc => isZh
      ? '访问 Norns 官方网站，浏览更多生态产品与资讯'
      : 'Visit Norns official website for ecosystem products and updates';
  String get visitWebsite => isZh ? '访问官网' : 'Visit Website';
  String get productWebsiteTitle => isZh ? 'Eir 网页版' : 'Eir Web App';
  String get productWebsiteUrl => 'https://eir.norns.cc.cd';
  String get githubRepoTitle => isZh ? 'GitHub 开源主页' : 'GitHub Repository';
  String get githubRepoUrl => 'https://github.com/NornsInteractive/Eir';
  String get privacyPolicyTitle => isZh ? '隐私政策' : 'Privacy Policy';
  String get privacyPolicyUrl => 'https://eir.norns.cc.cd/privacy.html';
  String get copyrightText => '© 2026 Norns Interactive. All rights reserved.';
  String get poweredByNorns => 'Norns Interactive';
  String get advancedTurnSection => isZh ? '高级穿透配置 (STUN / TURN)' : 'Advanced NAT Traversal (STUN / TURN)';
  String get advancedTurnDesc => isZh
      ? '系统默认已接入全球边缘穿透集群，日常使用无需修改'
      : 'Connected to global relay cluster by default. Manual modification unnecessary.';
  String get advancedTurnToggleShow => isZh ? '展开高级穿透配置' : 'Show Advanced NAT Traversal';
  String get advancedTurnToggleHide => isZh ? '收起高级穿透配置' : 'Hide Advanced NAT Traversal';

  String get danmakuToggle => isZh ? '弹幕' : 'Danmaku';
  String get danmakuEnabled => isZh ? '弹幕已开启' : 'Danmaku enabled';
  String get danmakuDisabled => isZh ? '弹幕已关闭' : 'Danmaku disabled';
  String get sendDanmaku => isZh ? '发个弹幕吧...' : 'Send a danmaku...';
  String get loopModeAll => isZh ? '列表循环' : 'Loop All';
  String get loopModeOne => isZh ? '单曲循环' : 'Loop One';
  String get loopModeSeq => isZh ? '顺序播放' : 'Sequential';
  String get subtitleTrack => isZh ? '字幕设置' : 'Subtitles';
  String get audioTrack => isZh ? '音轨设置' : 'Audio Tracks';
  String get noSubtitle => isZh ? '关闭字幕' : 'No Subtitles';
  String get autoSubtitle => isZh ? '自动选择' : 'Auto Subtitle';
  String get loadExternalSubtitle => isZh ? '加载本地字幕文件...' : 'Load external subtitle...';
  String get fastForwarding2x => isZh ? '2.0x 快速播放中' : '2.0x Fast Forwarding';
  String get connectionP2p => 'P2P';
  String get connectionServer => isZh ? '服务器' : 'Server';
  String get connectionP2pTooltip => isZh ? '当前为端到端 P2P 直连通道' : 'Connected via P2P direct channel';
  String get connectionServerTooltip => isZh ? '当前通过边缘信令服务器连接' : 'Connected via edge signaling server';
  String get moreSettings => isZh ? '更多设置' : 'More Settings';
  String get p2pConnecting => isZh ? 'P2P连接中' : 'P2P Connecting';
  String get p2pConnectingTooltip => isZh ? '正在尝试建立 P2P 端到端直连 (UDP 打洞中)...' : 'Attempting to establish P2P direct channel (UDP punching)...';
  String get p2pFailedPill => isZh ? '服务器 (P2P未通)' : 'Server (P2P Failed)';
  String get p2pFailedTooltip => isZh ? 'P2P 直连打洞超时（UDP 受阻）。在线视频已走服务器中继同步；如播放本地视频需配置 TURN 或切换 Tailcat。' : 'P2P direct channel timed out (UDP blocked). Online videos sync via server; for local files configure TURN or switch to Tailcat.';
  String get p2pBlockedLocalNotice => isZh ? '当前网络 UDP 打洞受阻（对称型 NAT / 移动 4G/5G），无法直接读取本地文件。可在设置中配置 TURN 中继，或改用在线视频。' : 'UDP hole-punching blocked by network (Symmetric NAT / 4G/5G). Cannot stream local media. Configure TURN in Settings or use an online URL video.';
  String get retryP2p => isZh ? '重试 P2P 打洞' : 'Retry P2P Hole Punching';
  String get turnServer => isZh ? 'TURN 中继服务器' : 'TURN Relay Server';
  String get turnUsername => isZh ? 'TURN 用户名' : 'TURN Username';
  String get turnCredential => isZh ? 'TURN 密码凭据' : 'TURN Password / Credential';
  String get testTurnConnection => isZh ? '测试中继' : 'Test Relay';
  String get testingTurnConnection => isZh ? '探测中...' : 'Testing...';
  String get turnConnectionSuccess => isZh ? '中继就绪 (Relay 候选已分配)' : 'Relay ready (Candidate allocated)';
  String get turnConnectionFailed => isZh ? '中继探测失败 (未分配 Relay 候选)' : 'Probe failed (No Relay candidate)';
  String get transportEngine => isZh ? '传输引擎 / 穿透模式' : 'Transport Engine / NAT Mode';
  String get transportWebrtc => isZh ? 'WebRTC 原生模式 (默认)' : 'WebRTC Native (Default)';
  String get transportTailcat => isZh ? 'Tailcat 穿透引擎 (跨网推荐)' : 'Tailcat Magicsock (Recommended for WAN)';
  String get transportWebrtcDesc => isZh ? '超轻量无额外体积，原生支持 Web 浏览器，适合同 Wi-Fi 或具备公网条件的环境。' : 'Lightweight, native browser support, best for same LAN or reachable IP networks.';
  String get transportTailcatDesc => isZh ? '内置 Tailscale Magicsock + WireGuard，直连失败自动走全球 DERP 节点（走 443 端口），抗丢包穿透率 99.9%。' : 'WireGuard + Magicsock with automatic global DERP fallback (HTTPS 443), 99.9% NAT traversal.';

  // Tabs for Settings
  String get tabAll => isZh ? '全部' : 'All';
  String get tabPersonalization => isZh ? '个性化与外观' : 'Personalization';
  String get tabNetwork => isZh ? '网络与连接' : 'Network & Relay';
  String get tabSystem => isZh ? '系统与存储' : 'System & Storage';

  // Recent Rooms & Clipboard
  String get recentRooms => isZh ? '最近放映室' : 'Recent Cinemas';
  String get noRecentRooms => isZh ? '暂无历史房间，创建或加入放映室后将在此快捷显示' : 'No recent rooms yet. Created or joined cinemas will show here.';
  String get clearHistory => isZh ? '清空历史' : 'Clear History';
  String get rejoin => isZh ? '快速重连' : 'Rejoin';
  String get clipboardInviteDetected => isZh ? '检测到放映室口令' : 'Cinema invite detected';
  String get quickJoin => isZh ? '立即加入' : 'Quick Join';

  // Greetings & Subtitles
  String get welcomeGreetingMorning => isZh ? '早上好，来一部清晨好片？' : 'Good morning, ready for a movie?';
  String get welcomeGreetingAfternoon => isZh ? '下午好，准备好一起看电影了吗？' : 'Good afternoon, ready for a movie?';
  String get welcomeGreetingEvening => isZh ? '晚上好，今晚看点什么？' : 'Good evening, what to watch tonight?';
  String get createRoomSubtitle => isZh ? '成为房主，添加本地或在线片源并邀请朋友同看' : 'Host a room, stream local or online media with friends';
  String get joinRoomSubtitle => isZh ? '输入 6 位房间口令或邀请链接加入放映' : 'Enter 6-digit room code or invite link';

  // Empty Cinema Playlist & Invite
  String get emptyPlaylistTitle => isZh ? '放映室屏幕静默中' : 'Cinema screen is quiet';
  String get emptyPlaylistDesc => isZh ? '房主可添加本地视频或在线流媒体链接，所有成员同步播放' : 'Host can add local files or streaming links with synchronized playback';
  String get addLocalVideo => isZh ? '添加本地视频' : 'Add Local Video';
  String get addOnlineStream => isZh ? '添加在线链接' : 'Add Online URL';
  String get shareInviteTitle => isZh ? '邀请好友同看' : 'Invite Friends to Watch';
  String get shareInviteDesc => isZh ? '将房间口令或网页链接发送给好友，对方打开即可同步观看' : 'Send the room code or web link to friends to watch together';
  String get copyWebLink => isZh ? '复制网页链接' : 'Copy Web Link';
  String get webLinkCopied => isZh ? '网页邀请链接已复制' : 'Web invite link copied';

  // Screen & Window Sharing
  String get navScreenShare => isZh ? '实时投屏' : 'Screen Mirror';
  String get screenShareTabTitle => isZh ? '实时投屏 · 60 FPS' : 'Screen Mirror · 60 FPS';
  String get screenShareTabSubtitle => isZh
      ? '应用窗口与屏幕内容实时共享'
      : 'Real-time screen and window sharing';
  String get startScreenShare => isZh ? '发起投屏' : 'Start Cast';
  String get joinScreenShare => isZh ? '观看投屏' : 'Join Cast';
  String get enterCastCodeHint => isZh ? '输入 6 位投屏码' : 'Enter 6-digit cast code';
  String get enterCastCodePrompt => isZh
      ? '输入对方分享的 6 位投屏码即可同步观看画面与声音'
      : 'Enter the 6-digit cast code to watch stream with audio';
  String get shareAppWindow => isZh ? '应用窗口' : 'Application Window';
  String get shareEntireScreen => isZh ? '整个屏幕' : 'Entire Display';
  String get shareSystemAudio => isZh ? '同时共享系统声音' : 'Share System Audio';
  String get fpsHighProfile => isZh ? '60 FPS 高帧率模式' : '60 FPS Motion';
  String get stopScreenShare => isZh ? '停止投屏' : 'Stop Cast';
  String get switchScreenShareSource => isZh ? '切换源' : 'Switch Source';
  String get castingToPeers => isZh ? '正在投屏推流中' : 'Casting to peers';
  String get watchingCastStream => isZh ? '正在观看投屏' : 'Watching cast stream';
  String get castCodeCopied => isZh ? '已复制投屏码' : 'Cast code copied';
  String get recentCasts => isZh ? '最近投屏' : 'Recent Casts';
  String get noRecentCasts => isZh ? '暂无历史投屏记录' : 'No recent cast sessions';
  String get selectSourceTitle => isZh ? '选择投屏内容' : 'Select Cast Source';
  String get selectSourceDesc => isZh
      ? '可选择特定软件窗口（如抖音、浏览器）或完整桌面'
      : 'Select a specific application window or entire display';
  String get mobileCastTitle => isZh ? '发起手机投屏' : 'Start Mobile Screen Cast';
  String get mobileCastSubtitle => isZh ? '实时共享手机屏幕与设备声音' : 'Share mobile screen & internal audio live';
  String get mobileShareAudioTitle => isZh ? '共享设备伴音' : 'Share Internal Audio';
  String get mobileShareAudioDesc => isZh ? '支持短视频伴奏、游戏及应用音效无损传输' : 'Transmit video music and app audio losslessly';
  String get mobileShareFpsTitle => isZh ? '60 FPS 极速推流' : '60 FPS High Framerate';
  String get mobileShareFpsDesc => isZh ? '动态帧率锁定，刷短视频丝滑流畅不卡顿' : 'Lock high frame rate for smooth video playback';
  String get mobileCastHint => isZh
      ? '提示：开启投屏后切至后台打开抖音等 App，对方即可实时同看画面与声音。'
      : 'Tip: After starting cast, switch to Douyin/TikTok; your companion will see and hear your screen in real time.';
  String get refreshSources => isZh ? '刷新窗口列表' : 'Refresh Windows';
  String get noWindowsFound => isZh ? '未检测到可共享的应用窗口' : 'No sharable windows found';
  String get noScreensFound => isZh ? '未检测到显示器' : 'No displays found';
  String get mobileScreenNotice => isZh
      ? '手机端将捕获整机屏幕，开启后可切至后台打开抖音，对方将实时接收画面与内录伴音。'
      : 'Mobile captures entire screen. Start cast and switch to Douyin/TikTok; companion hears internal audio and sees your screen live.';
  String get joinCast => isZh ? '加入观看' : 'Join';
  String get screenShareConnecting => isZh ? '正在建立投屏推流...' : 'Connecting screen stream...';
  String get screenShareReady => isZh ? '投屏流已就绪' : 'Screen stream ready';
  String get screenShareFailed => isZh ? '投屏连接失败' : 'Screen share failed';
  String get screenShareEnded => isZh ? '投屏已结束' : 'Screen share ended';
  String get talkbackToggle => isZh ? '对讲通话' : 'Voice Talkback';

  // Enhanced Screen Share & Audio Controls
  String get audioMixer => isZh ? '独立混音' : 'Audio Mixer';
  String get companionVolume => isZh ? '投屏伴声音量' : 'Cast Audio';
  String get voiceVolume => isZh ? '对讲人声音量' : 'Voice Volume';
  String get audioDucking => isZh ? '智能人声闪避' : 'Audio Ducking';
  String get audioDuckingDesc => isZh
      ? '开麦说话时伴奏自动降音 40%，清晰畅聊'
      : 'Lowers media 40% while speaking';
  String get aspectRatioContain => isZh ? '等比居中' : 'Fit Screen';
  String get aspectRatioCover => isZh ? '铺满无黑边' : 'Fill Screen';
  String get reactions => isZh ? '互动表情' : 'Reactions';
  String get liveBroadcastActive => isZh ? '当前房间正在推流中' : 'Live Stream Active';
  String get viewLiveNow => isZh ? '进入全屏视窗' : 'View Live Stream';
  String get searchWindowsHint => isZh ? '搜索应用窗口名称...' : 'Search windows...';
  String get streamHealthTitle => isZh ? '实时网络与画质看板' : 'Stream Diagnostics';
  String get fpsMetric => isZh ? '实时帧率' : 'FPS';
  String get rttMetric => isZh ? '往返延迟' : 'RTT Latency';
  String get bitrateMetric => isZh ? '实时码率' : 'Bitrate';
  String get packetLossMetric => isZh ? '丢包率' : 'Packet Loss';
  String get echoFreeNotice => isZh
      ? '已启用 Android 媒体与通话音轨隔离及 WebRTC 硬件级回声消除，双方开麦畅聊绝无回声困扰。'
      : 'Hardware AEC & OS audio sandboxing enabled. Zero echo loops during voice chat.';
  String get presetMotion => isZh ? '动态短视频 (60 FPS 优先)' : 'Motion (60 FPS)';
  String get presetCrystal => isZh ? '超清原画 (1080p 高清)' : 'Crystal (1080p)';
  String get presetLowLatency => isZh ? '极低延迟 (协同演示)' : 'Low Latency';

  // Screen Share Live Chat & Video Talkback
  String get castChat => isZh ? '投屏聊天' : 'Cast Chat';
  String get sendChatMessageHint => isZh ? '发送即时消息...' : 'Type a message...';
  String get noMessagesYet => isZh ? '暂无消息，打个招呼吧~' : 'No messages yet. Say hello~';
  String get quickReply => isZh ? '快捷回复' : 'Quick Reply';
  String get viewerTalking => isZh ? '对方正在说话' : 'Companion is speaking';

  // Desktop Adaptive Navigation & Screen Share Dashboard
  String get desktopNavLobby => isZh ? '🎬 同步放映厅' : '🎬 Cinema';
  String get desktopNavScreenShare => isZh ? '📱 实时投屏' : '📱 Screen Cast';
  String get activeCastTitle => isZh ? '正在实时投屏推流' : 'Live Screen Casting';
  String get activeCastSubtitle => isZh
      ? '正在将屏幕画面与声音实时共享给对方'
      : 'Streaming screen and internal audio live to peer';
  String get dragChatCapsuleHint => isZh ? '可拖拽悬浮球 · 点击即刻聊天' : 'Draggable · Tap to Chat';
  String get joinCastTitle => isZh ? '观看他人投屏' : 'Join Screen Cast';
  String get castDashboard => isZh ? '投屏控制台' : 'Cast Dashboard';
  String get switchBackgroundTip => isZh
      ? '推流已就绪！切至后台打开抖音、游戏或相册，对方将实时同看画面与声音。'
      : 'Live! Switch to Douyin/games; companion hears audio and sees your screen live.';

  // Floating Chat Bubble & Permissions
  String get mobileFloatingChatTitle => isZh ? '跨应用悬浮聊天球' : 'Floating Chat Bubble';
  String get mobileFloatingChatDesc => isZh
      ? '切换至其他应用时保持悬浮气泡，随时与观众交流'
      : 'Keep floating bubble over other apps for real-time chat';
  String get overlayPermissionTitle => isZh ? '需要悬浮窗权限' : 'Overlay Permission Required';
  String get overlayPermissionDesc => isZh
      ? '使用投屏悬浮聊天球需要开启【在其他应用上层显示】权限。开启后，在切换到其他 App 投屏时，屏幕上仍将显示可拖动的聊天气泡。'
      : 'Drawing over other apps permission is required for the floating chat bubble. It allows you to chat while streaming other apps.';
  String get grantPermission => isZh ? '去开启' : 'Grant';

  // Mobile App Download Dialog
  String get downloadAppTitle => isZh ? '下载移动端客户端' : 'Download Mobile App';
  String get downloadApp => isZh ? '下载 App' : 'Download App';
  String get downloadAppSubtitle => isZh
      ? '手机扫码或点击链接直接安装，随时同屏观影与投屏'
      : 'Scan QR code or click link to install for on-the-go sync & casting';
  String get androidClient => isZh ? 'Android 客户端' : 'Android App';
  String get androidDesc => isZh ? '支持 Android 7.0 及以上版本' : 'Requires Android 7.0 or later';
  String get downloadApk => isZh ? '下载 APK 安装包' : 'Download APK';
  String get copyDownloadLink => isZh ? '复制下载直链' : 'Copy Direct Link';
  String get downloadLinkCopied => isZh ? '下载直链已复制到剪贴板' : 'Direct download link copied to clipboard';
  String get iosClient => isZh ? 'iPhone / iPad' : 'iPhone / iPad';
  String get iosComingSoon => isZh ? '即将推出' : 'Coming Soon';
  String get iosDesc => isZh
      ? 'iOS 客户端正在筹备中，TestFlight 即将开启公测，敬请期待。'
      : 'iOS app is in active preparation. TestFlight public beta coming soon.';
  String get scanQrToDownload => isZh ? '使用手机相机或浏览器扫码下载' : 'Scan with mobile camera or browser to download';
  String get viewOnGithub => isZh ? '前往 GitHub Releases' : 'View on GitHub Releases';
  String get downloadMobilePrompt => isZh ? '移动端发起投屏需使用客户端 App' : 'Starting mobile screen share requires mobile app';
  String get downloadAndroidApp => isZh ? '下载 Android 客户端' : 'Download Android App';

  // Broadcaster & Cast Console
  String get endScreenShare => isZh ? '结束投屏' : 'End Cast';
  String get confirmStopScreenShareMessage =>
      isZh ? '确定要停止当前投屏并断开所有连接吗？' : 'Stop current screen share and disconnect all sessions?';
  String get liveCastDashboard => isZh ? '实时投屏控制台' : 'Live Cast Dashboard';
  String streamingDuration(String duration) => isZh ? '已推流 $duration' : 'Streaming $duration';
  String get streamingStable => isZh ? '正在稳定推流中...' : 'Streaming stably...';
  String get viewerCastCodeLabel => isZh ? '观众连接投屏码' : 'Viewer Cast Code';
  String get broadcasterCastCodePrompt =>
      isZh ? '对方在手机或电脑打开 Eir 输入投屏码，即可同步观看你的屏幕' : 'Open Eir on mobile or PC and enter this code to watch your screen in sync';
  String get copiedBadge => isZh ? '已复制！' : 'Copied!';
  String get copyCastCode => isZh ? '复制投屏码' : 'Copy Cast Code';
  String get directLinkCopiedBadge => isZh ? '直链已复制！' : 'Direct Link Copied!';
  String get copyWebDirectLink => isZh ? '复制网页直链' : 'Copy Web Direct Link';
  String get hideWebQrCode => isZh ? '收起网页直连二维码' : 'Hide Web QR Code';
  String get scanQrToWatchDirect => isZh ? '扫码免装观看直连' : 'Scan QR for Direct Web View';
  String get scanQrInstantOpenHint => isZh ? '微信或手机浏览器扫码直接秒开' : 'Scan with mobile browser or WeChat to watch instantly';
  String get screenSharingActive => isZh ? '屏幕正在实时共享中' : 'Screen is actively shared';
  String get screenSharingActiveDesc =>
      isZh ? '你可以切换到任意应用（如抖音、相册、游戏或浏览器），好友即可同步看到你的操作与伴音；观众发来的消息将显示在悬浮气泡中。'
          : 'Switch to any app (TikTok, Photos, Games, Browser); friends see your screen and hear audio in sync. Viewer chats appear in the floating bubble.';
  String get streamingFramerate => isZh ? '推流帧率' : 'Stream Framerate';
  String get ultraClearLowLatency => isZh ? '超清低延迟' : 'Ultra HD & Low Latency';
  String get viewerStatus => isZh ? '观看状态' : 'Viewer Status';
  String viewersConnected(int count) => isZh ? '$count 位观众 (已连接)' : '$count viewers connected';
  String get waitingForViewers => isZh ? '等待观众加入' : 'Waiting for viewers to join';
  String get p2pEncryptedDirect => isZh ? 'P2P 加密直连' : 'P2P Encrypted Direct';
  String get castControlsTitle => isZh ? '投屏控制' : 'Cast Controls';
  String get micOn => isZh ? '麦克风开启' : 'Mic On';
  String get micMuted => isZh ? '麦克风静音' : 'Mic Muted';
  String get systemAudioOn => isZh ? '系统伴音开' : 'Audio On';
  String get systemAudioMuted => isZh ? '伴音静音' : 'Audio Muted';
  String get floatingAvatarOn => isZh ? '悬浮头像开' : 'Avatar Cam On';
  String get floatingAvatarOff => isZh ? '悬浮头像关' : 'Avatar Cam Off';
  String get chatDanmakuOn => isZh ? '消息弹幕开' : 'Danmaku On';
  String get chatDanmakuHidden => isZh ? '弹幕已隐藏' : 'Danmaku Hidden';
  String get castServiceRunningBackground =>
      isZh ? '投屏服务已在后台稳定运行' : 'Cast service is running smoothly in the background';
  String get castBackgroundGuide =>
      isZh ? '您可以返回手机桌面打开王者荣耀、B站、文档或游戏，画面和声音都将持续实时传输。轻触屏幕上的【可拖动聊天胶囊】可随时与观众互动。'
          : 'Return to home screen and open games, videos, or documents; video and audio stream continuously. Tap the draggable chat capsule to chat anytime.';

  // Cast Chat Capsule
  String get castLiveInteraction => isZh ? '投屏实时互动' : 'Live Cast Interaction';
  String get sendingToViewers => isZh ? '正在向观看方发送消息' : 'Sending message to viewers';
  String get sendingToHost => isZh ? '正在向投屏方发送消息' : 'Sending message to broadcaster';
  String get castNoMessagesPrompt => isZh ? '暂无消息，发送一条打个招呼吧' : 'No messages yet, send one to say hi';

  // Screen Source Picker
  String get overlayPermissionBadgePrompt => isZh ? '需开启上层显示权限 · 点击设置' : 'Requires overlay permission · Tap to open settings';
  String fallbackWindowName(String id) => isZh ? '窗口 $id' : 'Window $id';
  String get browserScreenShareSupport => isZh ? '浏览器投屏支持' : 'Browser Screen Share Support';
  String get browserScreenShareDesc =>
      isZh ? '点击开始投屏后，浏览器将弹出系统原生的标签页、应用窗口或整屏选择器。勾选“共享音频”可同步伴奏声音。'
          : 'After starting cast, the browser opens its native picker for tab, window, or entire screen. Check "Share Audio" to stream audio.';

  // Screen Share Lobby & Live
  String get signalingCreateCastFailed => isZh ? '信令服务无法创建投屏房间，请检查网络连接' : 'Signaling service failed to create cast room, please check your network connection';
  String get startCastFailed => isZh ? '投屏发起失败' : 'Failed to start screen cast';
  String get invalidCastCodePrompt => isZh ? '请输入 6 位有效投屏码' : 'Please enter a valid 6-digit cast code';
  String joinCastRoomFailed(String code) => isZh ? '加入投屏房间失败: $code' : 'Failed to join cast room: $code';
  String get cannotConnectCast => isZh ? '无法连接到该投屏' : 'Cannot connect to this cast session';
  String get screenShareFeatureSubtitle => isZh ? '端到端低延迟传输 · 智能声画分离与回声消除' : 'End-to-end low latency · Audio separation & echo cancellation';
  String get fpsUltraClearBadge => isZh ? '60 FPS · 超清低延迟' : '60 FPS · Ultra HD & Low Latency';
  String get screenShareHeroDesc => isZh ? '将应用窗口或屏幕内容实时共享给好友' : 'Share application windows or screen in real time with friends';
  String get clipboardCastCodeDetected => isZh ? '检测到剪贴板投屏码' : 'Cast code detected from clipboard';
  String get quickWatch => isZh ? '一键观看' : 'Watch Now';
  String get returnToWindow => isZh ? '返回视窗' : 'Return to Viewport';
  String get startCastTitle => isZh ? '我要投屏' : 'Start Screen Cast';
  String get shareScreenOrWindowSubtitle => isZh ? '实时将手机屏幕或应用窗口共享给好友' : 'Stream mobile screen or application windows to friends live';
  String get startCastingNow => isZh ? '立即开启投屏' : 'Start Casting Now';
  String get enterCastCodeDescription => isZh ? '输入对方分享的 6 位投屏码，秒级同步画面' : 'Enter the 6-digit cast code to sync video in seconds';
  String get paste => isZh ? '粘贴' : 'Paste';
  String get enterWatchStream => isZh ? '进入观看' : 'Join Stream';
  String get recentCastHistory => isZh ? '最近投屏历史' : 'Recent Cast History';
  String get clear => isZh ? '清空' : 'Clear';
  String castCodeWithVal(String code) => isZh ? '投屏码: $code' : 'Cast Code: $code';
  String get disableTalkbackTooltip => isZh ? '关闭对讲' : 'Mute Talkback';
  String get enableTalkbackTooltip => isZh ? '开启对讲' : 'Enable Talkback';
  String get disableCameraTooltip => isZh ? '关闭摄像头' : 'Turn off Camera';
  String get exitWatchingCast => isZh ? '退出观看' : 'Exit Stream';
  List<String> get quickReactionPhrases => isZh
      ? const ['收到！', '好的', '看这里', '太赞了', '👍', '❤️', '666']
      : const ['Got it!', 'OK', 'Look here', 'Awesome!', '👍', '❤️', 'GG'];
  String get audioDuckingShortDesc => isZh ? '连麦说话时自动压低画面伴音40%' : 'Lowers stream audio 40% during talkback';
  String get aspectRatioMode => isZh ? '画面比例模式' : 'Aspect Ratio Mode';
  String connectingToCastWithCode(String code) => isZh ? '正在连接投屏 [$code]' : 'Connecting to cast [$code]';
  String get syncingCastStream => isZh ? '正在同步投屏画面' : 'Syncing cast stream';
  String get directChannelStalledHint =>
      isZh ? '直连通道建立耗时较长，请检查投屏方状态' : 'Connection is taking longer than expected. Please check host status';
  String get establishingP2pDirect =>
      isZh ? '正在与投屏方建立 P2P 加密直连通道...' : 'Establishing encrypted P2P direct channel...';
  String get backToLobby => isZh ? '返回大厅' : 'Back to Lobby';
  String get retryDirectConnection => isZh ? '重新直连' : 'Retry Direct Connection';
  String get localDeviceTag => isZh ? '本机' : 'Local';
  String get remoteTalkbackTag => isZh ? '连麦' : 'Peer';

  // Cinema View
  String get disbandRoomConfirmMessage =>
      isZh ? '解散房间后，所有正在一起观影的好友都将断开连接。确定解散吗？' : 'Disbanding the room will disconnect all watching members. Are you sure?';
  String get leaveRoomConfirmMessage => isZh ? '确定要退出当前放映室吗？' : 'Are you sure you want to leave the cinema room?';
  String get actionDisband => isZh ? '解散' : 'Disband';
  String get actionLeave => isZh ? '退出' : 'Leave';
  String get aspectFitContain => isZh ? '适应' : 'Contain';
  String get aspectFitCover => isZh ? '铺满' : 'Cover';
  String get aspectFitFill => isZh ? '拉伸' : 'Stretch';
  String aspectRatioToast(String fit) => isZh ? '画面比例: $fit' : 'Aspect Ratio: $fit';
  String get selectAllText => isZh ? '全选文本' : 'Select All';
  String get waitForPeerBuffering => isZh ? '等候好友缓冲完成' : 'Wait for Peer Buffering';
  String get waitForPeerBufferingDesc => isZh ? '当对端卡顿加载时自动暂停，就绪后恢复' : 'Auto-pause when peer is buffering, resume when ready';
  String get peerBufferingPausedNotice => isZh ? '好友正在缓冲，已为您暂停等候...' : 'Peer is buffering, paused to wait...';

  // Relative Time & History
  String get timeJustNow => isZh ? '刚刚' : 'Just now';
  String timeMinutesAgo(int count) => isZh ? '$count 分钟前' : '${count}m ago';
  String timeHoursAgo(int count) => isZh ? '$count 小时前' : '${count}h ago';
  String timeDaysAgo(int count) => isZh ? '$count 天前' : '${count}d ago';
  String timeWeeksAgo(int count) => isZh ? '$count 周前' : '${count}w ago';
  String get roleHostShort => isZh ? '房主' : 'Host';
  String get roleGuestShort => isZh ? '访客' : 'Guest';
  String lastVisited(String time) => isZh ? '最后访问: $time' : 'Visited: $time';
  String fallbackRoomName(String code) => isZh ? '放映室 #$code' : 'Cinema #$code';
  String get clipboardReadFailed =>
      isZh ? '无法读取剪贴板，请直接在输入框中粘贴邀请内容' : 'Clipboard access unavailable, please paste directly into the input';

  // Diagnostic & Transport
  String get turnServerAddressEmpty => isZh ? 'TURN 服务器地址不能为空' : 'TURN server address cannot be empty';
  String get turnProbeTimeout => isZh ? '探测超时 (未能分配中继候选，可能端口被阻断或凭据错误)' : 'Probe timed out (Failed to allocate relay candidate; port blocked or credentials invalid)';
  String turnConnectionSuccessWithRtt(int rtt) => isZh ? '连接成功 (中继就绪，耗时 ${rtt}ms)' : 'Connected successfully (Relay ready, ${rtt}ms)';
  String turnProbeException(String error) => isZh ? '探测异常: $error' : 'Probe exception: $error';
  String get turnConfigSaved => isZh ? 'TURN 配置已保存' : 'TURN configuration saved';
  String get turnServerEmptyHint => isZh ? '请先输入 TURN 服务器地址' : 'Please enter TURN server';
  String get sourceEntireScreen => isZh ? '全屏幕' : 'Entire Screen';
  String get sourceAppWindow => isZh ? '应用窗口' : 'Application Window';
  String get screenSharePermissionDeniedOrCancelled =>
      isZh ? '用户取消或未授予屏幕录制权限' : 'Screen capture permission denied or cancelled by user';
  String get tailcatDerpRelay => isZh ? 'DERP 中继 (Tailcat)' : 'DERP Relay (Tailcat)';

  // Modals & Badges
  String get releaseReadyBadge => isZh ? '正式可用' : 'Available Now';
  String get iosTestFlightInPrep => isZh ? 'TestFlight 公测筹备中' : 'TestFlight Beta in preparation';
  String get actionApply => isZh ? '应用' : 'Apply';
  String get preferencesSubtitle => isZh ? '外观配色与信令' : 'Theme, Language & Signaling';
  String get cleaningCache => isZh ? '正在清理...' : 'Cleaning...';
}

class AppLocalizationsDelegate extends LocalizationsDelegate<AppI18n> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['zh', 'en'].contains(locale.languageCode);

  @override
  Future<AppI18n> load(Locale locale) async => AppI18n(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
