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
  String get userNickname => isZh ? '我的设备' : 'My Device';
  String get close => isZh ? '关闭' : 'Close';
  String get done => isZh ? '完成' : 'Done';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get confirm => isZh ? '确认' : 'Confirm';

  // Hero & Lobby
  String get heroBadge =>
      isZh ? 'Eir P2P Sync Engine · 真实双人直连' : 'Eir P2P Sync Engine · Two-Peer Direct';
  String get heroTitle =>
      isZh ? '跨越距离，同频共赏' : 'Synchronized Cinema Across Distances';
  String get heroSubtitle => isZh
      ? '端对端 Ed25519 鉴权，P2P DataChannel 单调时钟调节同步。异地相隔，亦如促膝同席。'
      : 'Ed25519 peer auth, monotonic clock rate-trimming sync over WebRTC DataChannel.';
  String get createRoom => isZh ? '创建专属放映室' : 'Create Cinema Room';
  String get inputPlaceholder =>
      isZh ? '输入或粘贴邀请凭据 (signaling|room|token|genesis)...' : 'Paste invite payload (signaling|room|token|genesis)...';
  String get pasteJoin => isZh ? '粘贴加入' : 'Paste Join';
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
  String get initializingEngine => isZh ? '正在初始化安全身份与引擎...' : 'Initializing identity & engine...';
  String get initFailed => isZh ? '客户端初始化失败' : 'Client initialization failed';
  String get retryInit => isZh ? '重试初始化' : 'Retry Init';

  // Connection & Room Status
  String get stateDisconnected => isZh ? '未连接' : 'Disconnected';
  String get stateConnecting => isZh ? '正在连接信令与对端...' : 'Connecting...';
  String get stateConnected => isZh ? 'P2P 已直连' : 'P2P Connected';
  String get stateReconnecting => isZh ? '网络中断，正在重连 (1/2/4s)...' : 'Reconnecting...';
  String get retryConnection => isZh ? '重试连接' : 'Retry Connection';
  String get retryingConnection => isZh ? '正在重试连接...' : 'Retrying Connection...';
  String get disconnectedBannerText => isZh
      ? '放映室连接已断开，自动重连已停止，可点击重试恢复连接'
      : 'Room connection lost and auto-reconnect ended. Tap retry to reconnect.';

  // Roles & ACL
  String get roleOwner => isZh ? '房主' : 'HOST';
  String get roleAdmin => isZh ? '管理员' : 'ADMIN';
  String get roleMember => isZh ? '成员' : 'MEMBER';
  String get hostBadge => isZh ? 'HOST 房主' : 'HOST';
  String get grantAdmin => isZh ? '提升为管理员' : 'Grant Admin';
  String get revokeAdmin => isZh ? '撤销管理员' : 'Revoke Admin';
  String get peerYou => isZh ? '(你)' : '(You)';
  String get readOnlyControlTooltip =>
      isZh ? '只读模式：仅房主或管理员有权控制共享播放' : 'Read-only: Only Host or Admin can control shared playback';

  // Cinema View Header & HUD
  String peersConnected(int count) =>
      isZh ? '$count 人在线' : '$count Peers Online';
  String get copyInvite => isZh ? '复制邀请' : 'Copy Invite';
  String get inviteRoomTitle => isZh ? '放映室邀请凭据' : 'Room Invitation';
  String get inviteCopied => isZh ? '已复制邀请凭据到剪贴板' : 'Invite payload copied to clipboard';
  String get leaveRoom => isZh ? '离开房间' : 'Leave Room';
  String get disbandRoom => isZh ? '解散房间' : 'Disband Room';
  String get disbandPendingNotice => isZh
      ? '核心待接线：当前底层尚未提供 closeRoom 解散接口，已作为离开房间处理'
      : 'Core API pending: closeRoom interface not yet exposed by core, treated as leaveRoom.';
  String get playTooltip => isZh ? '播放 (共享)' : 'Play (Shared)';
  String get pauseTooltip => isZh ? '暂停 (共享)' : 'Pause (Shared)';
  String get muteTooltip => isZh ? '静音 (本机)' : 'Mute (Local)';
  String get unmuteTooltip => isZh ? '取消静音 (本机)' : 'Unmute (Local)';
  String get fullscreenTooltip => isZh ? '全屏 (本机)' : 'Fullscreen (Local)';
  String get exitFullscreenTooltip => isZh ? '退出全屏 (本机)' : 'Exit Fullscreen (Local)';
  String get volumeLabel => isZh ? '音量' : 'Volume';
  String get playbackRate => isZh ? '倍速' : 'Rate';
  String get timelineLabel => isZh ? '播放进度' : 'Playback Progress';
  String get timelineSeekHint => isZh ? '可拖拽或使用方向键调节播放进度' : 'Drag or use arrow keys to adjust position';
  String get timelineEmptyHint => isZh ? '未加载媒体' : 'No media loaded';
  String get rateChangeHint => isZh ? '切换播放倍速' : 'Cycle playback rate';
  String get selected => isZh ? '已选择' : 'Selected';

  // Dock Tabs
  String get tabPlaylist => isZh ? '播放列表' : 'Playlist';
  String get tabMembers => isZh ? '成员与权限' : 'Peers & ACL';
  String get tabSession => isZh ? '会话信息' : 'Session Info';

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
