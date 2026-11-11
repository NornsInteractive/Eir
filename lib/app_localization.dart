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
  String get heroBadge =>
      isZh ? '双人同步放映室 · 异地同屏观影' : 'Two-Peer Synchronized Cinema';
  String get heroTitle =>
      isZh ? '跨越距离，同频共赏' : 'Synchronized Cinema Across Distances';
  String get heroSubtitle => isZh
      ? '专属私密直连，毫秒级帧同步播放。相隔千里，亦如促膝同席。'
      : 'Private peer-to-peer connection with frame-accurate sync. Watch together, anywhere.';
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
  String get signalingUrlHint => isZh ? '默认 ws://127.0.0.1:8080/ws' : 'Default ws://127.0.0.1:8080/ws';
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
  String get tabPlaylist => isZh ? '播放列表' : 'Playlist';
  String get tabMembers => isZh ? '同看好友' : 'Friends';
  String get tabSession => isZh ? '放映详情' : 'Room Info';

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
      ? 'Eir · P2P 画面同步影厅 · 纯正 Apple Liquid Glass HIG 规范'
      : 'Eir · P2P Synchronized Cinema · Pure Apple Liquid Glass HIG';
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
