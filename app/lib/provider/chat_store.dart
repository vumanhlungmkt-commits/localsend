import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:path_provider/path_provider.dart';

/// A single chat bubble.
class ChatMessage {
  final String peer; // fingerprint of the other device
  final String peerName;
  final bool outgoing;
  final String text;
  final bool isFile;
  final int ts; // milliseconds since epoch

  const ChatMessage({
    required this.peer,
    required this.peerName,
    required this.outgoing,
    required this.text,
    required this.isFile,
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
    'peer': peer,
    'peerName': peerName,
    'outgoing': outgoing,
    'text': text,
    'isFile': isFile,
    'ts': ts,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    peer: j['peer'] as String,
    peerName: (j['peerName'] as String?) ?? '',
    outgoing: (j['outgoing'] as bool?) ?? false,
    text: (j['text'] as String?) ?? '',
    isFile: (j['isFile'] as bool?) ?? false,
    ts: (j['ts'] as int?) ?? 0,
  );
}

/// Stores the chat history on disk (chat_history.json in the app support folder).
class ChatStore {
  ChatStore._();

  static final ChatStore instance = ChatStore._();

  final ValueNotifier<List<ChatMessage>> messages = ValueNotifier(const []);

  /// Last known device for each peer, so a conversation can be reopened later.
  final Map<String, Device> devices = {};

  /// Number of unread messages for each peer.
  final ValueNotifier<Map<String, int>> unread = ValueNotifier(const {});

  File? _file;
  Future<void>? _loading;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}${Platform.pathSeparator}chat_history.json');
      if (await _file!.exists()) {
        final data = jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        messages.value = List.unmodifiable(
          (data['messages'] as List).map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map))),
        );
        final devs = Map<String, dynamic>.from((data['devices'] as Map?) ?? {});
        for (final entry in devs.entries) {
          try {
            devices[entry.key] = DeviceMapper.fromJson(Map<String, dynamic>.from(entry.value as Map));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('ChatStore load failed: $e');
    }
  }

  Future<void> _save() async {
    try {
      final f = _file;
      if (f == null) return;
      final list = messages.value;
      final keep = list.length > 5000 ? list.sublist(list.length - 5000) : list;
      await f.writeAsString(
        jsonEncode({
          'messages': keep.map((m) => m.toJson()).toList(),
          'devices': {for (final e in devices.entries) e.key: e.value.toJson()},
        }),
      );
    } catch (e) {
      debugPrint('ChatStore save failed: $e');
    }
  }

  Future<void> add({
    required Device device,
    required String peerName,
    required bool outgoing,
    required String text,
    bool isFile = false,
    bool markUnread = false,
  }) async {
    await load();
    devices[device.fingerprint] = device;
    messages.value = List.unmodifiable([
      ...messages.value,
      ChatMessage(
        peer: device.fingerprint,
        peerName: peerName,
        outgoing: outgoing,
        text: text,
        isFile: isFile,
        ts: DateTime.now().millisecondsSinceEpoch,
      ),
    ]);
    if (markUnread) {
      unread.value = {...unread.value, device.fingerprint: (unread.value[device.fingerprint] ?? 0) + 1};
    }
    await _save();
  }

  void markRead(String peer) {
    if ((unread.value[peer] ?? 0) == 0) return;
    unread.value = {...unread.value}..remove(peer);
  }

  int get totalUnread => unread.value.values.fold(0, (a, b) => a + b);
}
