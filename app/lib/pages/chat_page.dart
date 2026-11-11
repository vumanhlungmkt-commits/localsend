import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/pages/tabs/send_tab.dart' show pickerOptions;
import 'package:localsend_app/provider/chat_store.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/widget/dialogs/add_file_dialog.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/model/file_type.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const _zaloBlue = Color(0xFF0068FF);
const _outBubble = Color(0xFFE5EFFF);

Color _avatarColor(String key) {
  const colors = [
    Color(0xFF0068FF),
    Color(0xFF00A86B),
    Color(0xFFFF7A00),
    Color(0xFF8E44AD),
    Color(0xFFE91E63),
    Color(0xFF009688),
    Color(0xFF795548),
  ];
  return colors[key.codeUnits.fold<int>(0, (a, b) => a + b) % colors.length];
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
  return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
}

String _two(int n) => n.toString().padLeft(2, '0');

String _time(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return '${_two(d.hour)}:${_two(d.minute)}';
  }
  return '${_two(d.day)}/${_two(d.month)}';
}

String _dayLabel(int ts) {
  final d = DateTime.fromMillisecondsSinceEpoch(ts);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hôm nay';
  if (diff == 1) return 'Hôm qua';
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

class ChatAvatar extends StatelessWidget {
  final String name;
  final String keyText;
  final double size;

  const ChatAvatar({required this.name, required this.keyText, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: _avatarColor(keyText),
      child: Text(
        _initials(name),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.36),
      ),
    );
  }
}

/// Zalo-like list of all conversations.
class ChatListPage extends StatefulWidget {
  const ChatListPage();

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ChatStore.instance.load().then((_) {
        if (mounted) setState(() {});
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _zaloBlue,
        foregroundColor: Colors.white,
        title: const Text('Tin nhắn'),
      ),
      body: ValueListenableBuilder<List<ChatMessage>>(
        valueListenable: ChatStore.instance.messages,
        builder: (context, messages, _) {
          return ValueListenableBuilder<Map<String, int>>(
            valueListenable: ChatStore.instance.unread,
            builder: (context, unread, _) {
              // newest message per peer
              final last = <String, ChatMessage>{};
              for (final m in messages) {
                last[m.peer] = m;
              }
              final convs = last.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
              if (convs.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Chưa có cuộc trò chuyện nào.\nỞ tab Gửi, bấm biểu tượng 💬 cạnh một thiết bị để bắt đầu chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              return ListView.separated(
                itemCount: convs.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 76),
                itemBuilder: (context, i) {
                  final m = convs[i];
                  final device = ChatStore.instance.devices[m.peer];
                  final name = device?.alias ?? m.peerName;
                  final count = unread[m.peer] ?? 0;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: ChatAvatar(name: name, keyText: m.peer, size: 48),
                    title: Text(
                      name,
                      style: TextStyle(fontWeight: count > 0 ? FontWeight.bold : FontWeight.w500),
                    ),
                    subtitle: Text(
                      '${m.outgoing ? 'Bạn: ' : ''}${m.isFile ? '📎 ' : ''}${m.text}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_time(m.ts), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        if (count > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                            child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                      ],
                    ),
                    onTap: device == null ? null : () async => await context.push(() => ChatPage(device: device)),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// Zalo-like conversation with one device.
class ChatPage extends StatefulWidget {
  final Device device;

  /// Fingerprint of the conversation currently on screen (null if none).
  static String? openPeer;

  const ChatPage({required this.device});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with Refena {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    ChatPage.openPeer = widget.device.fingerprint;
    unawaited(
      ChatStore.instance.load().then((_) {
        if (mounted) setState(() {});
        _scrollToEnd();
      }),
    );
    ChatStore.instance.markRead(widget.device.fingerprint);
    ChatStore.instance.messages.addListener(_onMessages);
  }

  @override
  void dispose() {
    ChatStore.instance.messages.removeListener(_onMessages);
    if (ChatPage.openPeer == widget.device.fingerprint) {
      ChatPage.openPeer = null;
    }
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onMessages() {
    ChatStore.instance.markRead(widget.device.fingerprint);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendText() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    _focus.requestFocus();
    final bytes = utf8.encode(text);
    final file = CrossFile(
      name: 'message_${DateTime.now().millisecondsSinceEpoch}.txt',
      fileType: FileType.text,
      size: bytes.length,
      thumbnail: null,
      asset: null,
      path: null,
      bytes: bytes,
      lastModified: null,
      lastAccessed: null,
    );
    await ChatStore.instance.add(
      device: widget.device,
      peerName: widget.device.alias,
      outgoing: true,
      text: text,
    );
    try {
      await ref.notifier(sendProvider).startSession(target: widget.device, files: [file], background: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gửi lỗi: $e')));
      }
    }
  }

  Future<void> _sendFiles() async {
    ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
    await AddFileDialog.open(context: context, options: pickerOptions);
    final files = ref.read(selectedSendingFilesProvider);
    if (files.isEmpty) return;
    final names = files.map((f) => f.name).toList();
    await ChatStore.instance.add(
      device: widget.device,
      peerName: widget.device.alias,
      outgoing: true,
      text: names.length == 1 ? names.first : '${names.length} file: ${names.take(3).join(', ')}${names.length > 3 ? '…' : ''}',
      isFile: true,
    );
    await ref.notifier(sendProvider).startSession(target: widget.device, files: files, background: false);
    ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.device;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE2E9F1),
      appBar: AppBar(
        backgroundColor: _zaloBlue,
        foregroundColor: Colors.white,
        titleSpacing: 0,
        title: Row(
          children: [
            ChatAvatar(name: device.alias, keyText: device.fingerprint, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.alias, style: const TextStyle(fontSize: 17), overflow: TextOverflow.ellipsis),
                  Text(
                    device.ip ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<List<ChatMessage>>(
              valueListenable: ChatStore.instance.messages,
              builder: (context, all, _) {
                final list = all.where((m) => m.peer == device.fingerprint).toList();
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Hãy gửi lời chào 👋', style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final m = list[i];
                    final showDay = i == 0 || _dayLabel(list[i - 1].ts) != _dayLabel(m.ts);
                    final sameSenderNext = i + 1 < list.length && list[i + 1].outgoing == m.outgoing;
                    return Column(
                      children: [
                        if (showDay)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(_dayLabel(m.ts), style: const TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        _Bubble(message: m, device: device, showAvatar: !m.outgoing && !sameSenderNext, isDark: isDark),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Gửi file / ảnh',
                    icon: const Icon(Icons.attach_file, color: _zaloBlue),
                    onPressed: _sendFiles,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(
                        hintText: 'Tin nhắn',
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Gửi',
                    icon: const Icon(Icons.send, color: _zaloBlue),
                    onPressed: _sendText,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final Device device;
  final bool showAvatar;
  final bool isDark;

  const _Bubble({required this.message, required this.device, required this.showAvatar, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final out = message.outgoing;
    final bg = out ? (isDark ? const Color(0xFF1F3A66) : _outBubble) : (isDark ? const Color(0xFF333333) : Colors.white);
    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isFile)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file, color: _zaloBlue),
                const SizedBox(width: 6),
                Flexible(child: Text(message.text, style: const TextStyle(fontSize: 15))),
              ],
            )
          else
            SelectableText(message.text, style: const TextStyle(fontSize: 15)),
          const SizedBox(height: 3),
          Text(_time(message.ts), style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
    return Row(
      mainAxisAlignment: out ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (!out)
          SizedBox(
            width: 36,
            child: showAvatar ? ChatAvatar(name: device.alias, keyText: device.fingerprint, size: 30) : null,
          ),
        bubble,
      ],
    );
  }
}
