// UI Models and Projections for Eir MVP
// Re-exports core RoomSession models and provides UI projection helpers.

import 'dart:math';

export 'core/room_session.dart'
    show
        RoomRole,
        RoomConnectionState,
        PlaybackMode,
        PlaybackLoopMode,
        DanmakuMessage,
        DeviceIdentityInfo,
        RoomMember,
        PlaylistItem,
        PlaybackState,
        MemberTelemetry,
        RoomSession;

export 'core/call_session.dart'
    show
        CallState,
        CallType,
        ChatMessageType,
        ChatMessage,
        CallSession;

export 'media/local_media_service.dart' show MediaCacheTelemetrySnapshot;

/// Helper to format a Duration as HH:MM:SS or MM:SS
String formatDuration(Duration? duration) {
  if (duration == null || duration.inMilliseconds <= 0) {
    return '00:00';
  }
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

/// Helper to format byte counts with bounded units (B, KB, MB, GB, TB)
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = (log(bytes) / log(1024)).floor();
  if (i < 0) i = 0;
  if (i >= suffixes.length) i = suffixes.length - 1;
  final numVal = bytes / pow(1024, i);
  return '${numVal.toStringAsFixed(numVal < 10 && i > 0 ? 1 : 0)} ${suffixes[i]}';
}

/// Helper to format device ID for display with bounded length checks
String formatDeviceId(String deviceId) {
  if (deviceId.isEmpty) return '-';
  if (deviceId.length <= 12) return deviceId;
  final prefixLen = min(6, deviceId.length);
  final suffixLen = min(4, max(0, deviceId.length - prefixLen));
  if (suffixLen == 0) return deviceId.substring(0, prefixLen);
  return '${deviceId.substring(0, prefixLen)}...${deviceId.substring(deviceId.length - suffixLen)}';
}
