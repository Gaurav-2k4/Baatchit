import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// ============================================================================
// THEME CONSTANTS
// ============================================================================

class AppColors {
  static const Color primary = Color(0xFF6C63FF);
  static const Color secondary = Color(0xFF00BCD4);
  static const Color error = Color(0xFFE57373);
  static const Color success = Color(0xFF81C784);
  static const Color warning = Color(0xFFFFB74D);
  
  // Light theme colors
  static const Color bg = Color(0xFFF8F9FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceHigh = Color(0xFFF1F3F5);
  static const Color surfaceHigher = Color(0xFFE9ECEF);
  static const Color onBg = Color(0xFF212529);
  static const Color onBgMuted = Color(0xFF868E96);
  static const Color onBgFaint = Color(0xFFADB5BD);
  
  // Message bubbles
  static const Color bubbleMe = Color(0xFF6C63FF);
  static const Color bubbleThem = Color(0xFFE9ECEF);
  
  // Dark theme colors (uncomment if needed)
  // static const Color bg = Color(0xFF121212);
  // static const Color surface = Color(0xFF1E1E1E);
  // static const Color surfaceHigh = Color(0xFF2D2D2D);
  // static const Color surfaceHigher = Color(0xFF3D3D3D);
  // static const Color onBg = Color(0xFFE9ECEF);
  // static const Color onBgMuted = Color(0xFF9E9E9E);
  // static const Color onBgFaint = Color(0xFF757575);
  // static const Color bubbleMe = Color(0xFF6C63FF);
  // static const Color bubbleThem = Color(0xFF2D2D2D);
}

class AppTextStyles {
  static const String fontFamily = 'Outfit';
  
  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );
  
  static const TextStyle titleMed = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );
  
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
  
  static const TextStyle bodyMed = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
  
  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
  );
  
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.3,
  );
}

// ============================================================================
// CHAT SCREEN
// ============================================================================

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String friendUid;
  final String friendName;
  final String friendAvatarUrl;
  final bool friendIsOnline;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.friendUid,
    required this.friendName,
    this.friendAvatarUrl = '',
    this.friendIsOnline = false,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  late final User _currentUser;
  bool _isSending = false;
  bool _hasText = false;

  // Typing indicator
  Timer? _typingTimer;
  bool _friendTyping = false;
  StreamSubscription? _typingSubscription;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser!;
    WidgetsBinding.instance.addObserver(this);

    _markAsRead();
    _setOnlineStatus(true);
    _listenToTyping();

    _msgCtrl.addListener(() {
      final hasText = _msgCtrl.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
      _notifyTyping();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _setOnlineStatus(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _setOnlineStatus(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setOnlineStatus(false);
    _clearTyping();
    _typingTimer?.cancel();
    _typingSubscription?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Online status ────────────────────────────────────────────────────────
  Future<void> _setOnlineStatus(bool online) async {
    try {
      await _firestore.collection('users').doc(_currentUser.uid).update({
        'isOnline': online,
        'lastSeen': Timestamp.now(),
      });
    } catch (e) {
      debugPrint('Error setting online status: $e');
    }
  }

  // ── Mark messages read ───────────────────────────────────────────────────
  Future<void> _markAsRead() async {
    try {
      await _firestore.collection('chats').doc(widget.chatId).update({
        'unread.${_currentUser.uid}': 0,
      });
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  // ── Typing indicator ─────────────────────────────────────────────────────
  void _notifyTyping() {
    try {
      _firestore.collection('chats').doc(widget.chatId).update({
        'typing.${_currentUser.uid}': true,
      });
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), _clearTyping);
    } catch (e) {
      debugPrint('Error notifying typing: $e');
    }
  }

  Future<void> _clearTyping() async {
    try {
      await _firestore.collection('chats').doc(widget.chatId).update({
        'typing.${_currentUser.uid}': false,
      });
    } catch (e) {
      debugPrint('Error clearing typing: $e');
    }
  }

  void _listenToTyping() {
    _typingSubscription = _firestore
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || !mounted) return;
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final typing = data['typing'] as Map<String, dynamic>? ?? {};
      final ft = typing[widget.friendUid] as bool? ?? false;
      if (ft != _friendTyping) setState(() => _friendTyping = ft);
    });
  }

  // ── Send message ─────────────────────────────────────────────────────────
  Future<void> _sendMessage() async {
    final msg = _msgCtrl.text.trim();
    if (msg.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _msgCtrl.clear();
    await _clearTyping();

    final now = Timestamp.now();

    try {
      // Batch write for atomicity
      final batch = _firestore.batch();

      final msgRef = _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc();

      batch.set(msgRef, {
        'sender': _currentUser.uid,
        'receiver': widget.friendUid,
        'message': msg,
        'timestamp': now,
        'read': false,
      });

      batch.update(
        _firestore.collection('chats').doc(widget.chatId),
        {
          'lastMessage': msg,
          'lastMessageTime': now,
          'unread.${widget.friendUid}': FieldValue.increment(1),
        },
      );

      await batch.commit();
      _scrollToBottom();
    } catch (e) {
      // Restore message text on failure
      _msgCtrl.text = msg;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to send. Tap to retry.'),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _sendMessage(),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _formatTime(Timestamp ts) => DateFormat.Hm().format(ts.toDate());

  bool _isSameDay(Timestamp a, Timestamp b) {
    final da = a.toDate();
    final db = b.toDate();
    return da.year == db.year &&
        da.month == db.month &&
        da.day == db.day;
  }

  String _dateDivider(Timestamp ts) {
    final date = ts.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgD = DateTime(date.year, date.month, date.day);

    if (msgD == today) return 'Today';
    if (msgD == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMMM d, yyyy').format(date);
  }

  Color _avatarColor(String uid) {
    const palette = [
      Color(0xFF6C63FF),
      Color(0xFF00BCD4),
      Color(0xFFFF7043),
      Color(0xFF43A047),
      Color(0xFFE91E63),
      Color(0xFF8D6E63),
    ];
    return palette[uid.hashCode.abs() % palette.length];
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputBar(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _avatarColor(widget.friendUid),
                backgroundImage: widget.friendAvatarUrl.isNotEmpty
                    ? NetworkImage(widget.friendAvatarUrl)
                    : null,
                child: widget.friendAvatarUrl.isEmpty
                    ? Text(
                        widget.friendName[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      )
                    : null,
              ),
              if (widget.friendIsOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.surface,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.friendName,
                  style: AppTextStyles.titleMed,
                  overflow: TextOverflow.ellipsis,
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _friendTyping
                      ? Text(
                          'typing…',
                          key: const ValueKey('typing'),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.primary,
                          ),
                        )
                      : Text(
                          widget.friendIsOnline ? 'Online' : 'Offline',
                          key: const ValueKey('status'),
                          style: AppTextStyles.bodySmall.copyWith(
                            color: widget.friendIsOnline
                                ? AppColors.primary
                                : AppColors.onBgFaint,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.videocam_outlined),
          onPressed: () {
            // TODO: video call
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video call coming soon!')),
            );
          },
          tooltip: 'Video call',
        ),
        IconButton(
          icon: const Icon(Icons.call_outlined),
          onPressed: () {
            // TODO: voice call
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Voice call coming soon!')),
            );
          },
          tooltip: 'Voice call',
        ),
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showChatOptions,
          tooltip: 'Options',
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.error,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  'Failed to load messages',
                  style: AppTextStyles.bodyMed.copyWith(
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('👋', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'Say hello to ${widget.friendName}!',
                  style: AppTextStyles.bodyMed.copyWith(
                    color: AppColors.onBgMuted,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          controller: _scrollCtrl,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>? ?? {};
            final isMe = data['sender'] == _currentUser.uid;
            final ts = data['timestamp'] as Timestamp? ?? Timestamp.now();

            // Date divider between different days
            final showDivider = index == docs.length - 1 ||
                !_isSameDay(
                  ts,
                  (docs[index + 1].data() as Map<String, dynamic>?)?['timestamp']
                      as Timestamp? ??
                      ts,
                );

            return Column(
              children: [
                if (showDivider) _DateDivider(label: _dateDivider(ts)),
                _MessageBubble(
                  message: data['message'] as String? ?? '',
                  isMe: isMe,
                  time: _formatTime(ts),
                  read: data['read'] as bool? ?? false,
                  onLongPress: () => _onMessageLongPress(
                    data['message'] as String? ?? '',
                    docs[index].id,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInputBar() {
    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Text field ───────────────────────────────
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: AppColors.surfaceHigher,
                  width: 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      focusNode: _focusNode,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTextStyles.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.onBgFaint,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        fillColor: Colors.transparent,
                        filled: false,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                    child: IconButton(
                      icon: const Icon(
                        Icons.emoji_emotions_outlined,
                        color: AppColors.onBgMuted,
                        size: 22,
                      ),
                      onPressed: () {
                        // TODO: emoji picker
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Emoji picker coming soon!')),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ── Send button ──────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _hasText ? AppColors.primary : AppColors.surfaceHigh,
              boxShadow: _hasText
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _hasText ? _sendMessage : null,
                child: Center(
                  child: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.bg,
                          ),
                        )
                      : Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: _hasText ? AppColors.bg : AppColors.onBgFaint,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Long press on message ────────────────────────────────────────────────
  void _onMessageLongPress(String text, String messageId) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.onBgFaint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.copy_rounded,
              color: AppColors.onBg,
            ),
            title: Text(
              'Copy',
              style: AppTextStyles.bodyLarge,
            ),
            onTap: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
            title: Text(
              'Delete',
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.error,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              _deleteMessage(messageId);
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete message')),
        );
      }
    }
  }

  void _showChatOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.onBgFaint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: const Icon(
              Icons.search_rounded,
              color: AppColors.onBg,
            ),
            title: Text(
              'Search messages',
              style: AppTextStyles.bodyLarge,
            ),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement search
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search coming soon!')),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.volume_off_outlined,
              color: AppColors.onBg,
            ),
            title: Text(
              'Mute notifications',
              style: AppTextStyles.bodyLarge,
            ),
            onTap: () {
              Navigator.pop(context);
              // TODO: Implement mute
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Mute coming soon!')),
              );
            },
          ),
          ListTile(
            leading: const Icon(
              Icons.delete_sweep_outlined,
              color: AppColors.error,
            ),
            title: Text(
              'Clear chat',
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.error,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              _confirmClearChat();
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _confirmClearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear chat'),
        content: Text(
          'Are you sure you want to clear all messages with ${widget.friendName}?',
          style: AppTextStyles.bodyMed,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: AppTextStyles.bodyMed.copyWith(
                color: AppColors.onBgMuted,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Clear',
              style: AppTextStyles.bodyMed.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _clearAllMessages();
    }
  }

  Future<void> _clearAllMessages() async {
    try {
      final messages = await _firestore
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .get();
      
      final batch = _firestore.batch();
      for (var doc in messages.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      // Update chat last message
      await _firestore.collection('chats').doc(widget.chatId).update({
        'lastMessage': null,
        'lastMessageTime': null,
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat cleared successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to clear chat')),
        );
      }
    }
  }
}

// ============================================================================
// MESSAGE BUBBLE
// ============================================================================

class _MessageBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final String time;
  final bool read;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.time,
    required this.read,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    const radius = Radius.circular(18);
    const tinyRadius = Radius.circular(4);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? AppColors.bubbleMe : AppColors.bubbleThem,
              borderRadius: BorderRadius.only(
                topLeft: radius,
                topRight: radius,
                bottomLeft: isMe ? radius : tinyRadius,
                bottomRight: isMe ? tinyRadius : radius,
              ),
              boxShadow: isMe
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : [],
            ),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: isMe ? AppColors.bg : AppColors.onBg,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isMe
                            ? AppColors.bg.withOpacity(0.65)
                            : AppColors.onBgFaint,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        read ? Icons.done_all_rounded : Icons.done_rounded,
                        size: 14,
                        color: read
                            ? AppColors.bg.withOpacity(0.9)
                            : AppColors.bg.withOpacity(0.5),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DATE DIVIDER
// ============================================================================

class _DateDivider extends StatelessWidget {
  final String label;
  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: AppColors.surfaceHigher,
              thickness: 1,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surfaceHigh,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.onBgMuted,
                ),
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: AppColors.surfaceHigher,
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }
}
