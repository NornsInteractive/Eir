import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a recently visited cinema room.
class RecentRoom {
  final String roomCode;
  final String roomId;
  final String roomName;
  final String role; // 'owner' or 'guest'
  final int lastVisitedMs;

  const RecentRoom({
    required this.roomCode,
    required this.roomId,
    required this.roomName,
    required this.role,
    required this.lastVisitedMs,
  });

  String get title => roomName;

  Map<String, dynamic> toJson() => {
    'roomCode': roomCode,
    'roomId': roomId,
    'roomName': roomName,
    'role': role,
    'lastVisitedMs': lastVisitedMs,
  };

  factory RecentRoom.fromJson(Map<String, dynamic> json) {
    final roomId = json['roomId'] as String? ?? '';
    final roomCode = json['roomCode'] as String? ?? roomId;
    return RecentRoom(
      roomCode: roomCode,
      roomId: roomId.isNotEmpty ? roomId : roomCode,
      roomName: json['roomName'] as String? ?? json['title'] as String? ?? '',
      role: json['role'] as String? ?? 'guest',
      lastVisitedMs: json['lastVisitedMs'] as int? ?? 0,
    );
  }

  String get displayTitle => roomName.isNotEmpty
      ? roomName
      : '放映室 #${roomCode.length > 8 ? roomCode.substring(0, 8) : roomCode}';

  bool get isOwner => role == 'owner';
}

/// Service managing persistent recent cinema rooms across app sessions.
class RoomHistoryService {
  static const String _kRecentRoomsKey = 'eir_recent_cinema_rooms';
  static const int kMaxRecentRooms = 5;

  static ValueNotifier<List<RecentRoom>> recentRoomsNotifier =
      ValueNotifier<List<RecentRoom>>([]);

  /// Loads recent rooms from SharedPreferences and updates the notifier.
  static Future<List<RecentRoom>> getRecentRooms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_kRecentRoomsKey);
      if (rawList == null || rawList.isEmpty) {
        recentRoomsNotifier.value = [];
        return [];
      }
      final list = <RecentRoom>[];
      for (final item in rawList) {
        try {
          final map = jsonDecode(item);
          if (map is Map<String, dynamic>) {
            list.add(RecentRoom.fromJson(map));
          }
        } catch (_) {}
      }
      recentRoomsNotifier.value = list;
      return list;
    } catch (e) {
      debugPrint('[RoomHistoryService] Error loading recent rooms: $e');
      return [];
    }
  }

  /// Records or updates a visited room, placing it at the head of the list.
  static Future<void> recordRoom({
    String? roomId,
    String? roomCode,
    String? roomName,
    String? title,
    String? role,
    bool? isOwner,
  }) async {
    final cleanCode = (roomCode ?? roomId ?? '').trim();
    final cleanId = (roomId ?? roomCode ?? '').trim();
    if (cleanCode.isEmpty && cleanId.isEmpty) return;

    final effectiveCode = cleanCode.isNotEmpty ? cleanCode : cleanId;
    final effectiveId = cleanId.isNotEmpty ? cleanId : effectiveCode;
    final effectiveRole = isOwner != null
        ? (isOwner ? 'owner' : 'guest')
        : (role ?? 'guest');

    try {
      final prefs = await SharedPreferences.getInstance();
      final current = await getRecentRooms();

      // Remove existing room with the same code or id to deduplicate
      final updated = current
          .where((r) => r.roomCode != effectiveCode && r.roomId != effectiveId)
          .toList();

      // Add to front
      final effectiveTitle = (roomName ?? title)?.trim().isNotEmpty == true
          ? (roomName ?? title)!.trim()
          : '放映室 #${effectiveCode.length > 8 ? effectiveCode.substring(0, 8) : effectiveCode}';

      updated.insert(
        0,
        RecentRoom(
          roomCode: effectiveCode,
          roomId: effectiveId,
          roomName: effectiveTitle,
          role: effectiveRole,
          lastVisitedMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      // Bound to max entries
      final bounded = updated.take(kMaxRecentRooms).toList();

      final encoded = bounded.map((r) => jsonEncode(r.toJson())).toList();
      await prefs.setStringList(_kRecentRoomsKey, encoded);
      recentRoomsNotifier.value = bounded;
    } catch (e) {
      debugPrint('[RoomHistoryService] Error recording recent room: $e');
    }
  }

  /// Removes a single room from history.
  static Future<void> removeRoom(String roomId) async {
    try {
      final target = roomId.trim();
      final prefs = await SharedPreferences.getInstance();
      final current = await getRecentRooms();
      final updated = current
          .where((r) => r.roomId != target && r.roomCode != target)
          .toList();
      final encoded = updated.map((r) => jsonEncode(r.toJson())).toList();
      await prefs.setStringList(_kRecentRoomsKey, encoded);
      recentRoomsNotifier.value = updated;
    } catch (e) {
      debugPrint('[RoomHistoryService] Error removing recent room: $e');
    }
  }

  /// Clears all recent rooms history.
  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kRecentRoomsKey);
      recentRoomsNotifier.value = [];
    } catch (e) {
      debugPrint('[RoomHistoryService] Error clearing recent rooms: $e');
    }
  }
}
