import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../screens/chat_screen.dart';

// ─────────────────────────────────────────────
//  DATA MODEL
// ─────────────────────────────────────────────
class ChatItem {
  final String uid;
  final String name;
  final String avatarUrl;
  final String lastMessage;
  final Timestamp lastMessageTime;
  final int unread;
  final bool isOnline;

  const ChatItem({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.unread,
    required this.isOnline,
  });
}

// ─────────────────────────────────────────────
//  WIDGET
// ─────────────────────────────────────────────
class ChatsTab extends StatefulWidget {
  const ChatsTab({super.key});

  @override
  State<ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<ChatsTab> with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  late final User _currentUser;

  final _searchController = TextEditingController();
  String _searchQuery = '';

  // Cached chat items so we avoid full rebuilds on every keystroke
  List<ChatItem> _allItems = [];
  bool _loading = true;
  String? _error;

  StreamSubscription? _friendsSub;
  StreamSubscription? _chatsSub;

  // Debounce timer for search
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser!;
    _listenToData();

    _searchController.addListener(() {
      if (_debounce?.isActive ?? false) _debounce!.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
      });
    });
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _chatsSub?.cancel();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Real-time listener combining friends + chats ──────────────────────────
  void _listenToData() {
    final uid = _currentUser.uid;

    _friendsSub = _firestore
        .collection('users')
        .doc(uid)
        .collection('friends')
        .snapshots()
        .listen((friendSnap) async {
      if (!mounted) return;
      try {
        final items = await _buildChatItems(friendSnap.docs);
        if (mounted) setState(() { _allItems = items; _loading = false; });
      } catch (e) {
        if (mounted) setState(() { _error = e.toString(); _loading = false; });
      }
    }, onError: (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    });
  }

  Future<List<ChatItem>> _buildChatItems(
      List<QueryDocumentSnapshot> friendDocs) async {
    if (friendDocs.isEmpty) return [];

    final uid = _currentUser.uid;

    // Fetch all users and chat docs in parallel
    final futures = friendDocs.map((f) async {
      final friendUid = f.id;

      final chatId = uid.compareTo(friendUid) < 0
          ? '$uid-$friendUid'
          : '$friendUid-$uid';

      final results = await Future.wait([
        _firestore.collection('users').doc(friendUid).get(),
        _firestore.collection('chats').doc(chatId).get(),
      ]);

      final userDoc = results[0] as DocumentSnapshot;
      final chatDoc = results[1] as DocumentSnapshot;

      final userData = userDoc.data() as Map<String, dynamic>? ?? {};
      final chatData = chatDoc.exists
          ? chatDoc.data() as Map<String, dynamic>? ?? {}
          : null;

      return ChatItem(
        uid: friendUid,
        name: (userData['name'] as String?)?.trim().isNotEmpty == true
            ? userData['name'] as String
            : 'Unknown',
        avatarUrl: userData['photoUrl'] as String? ?? '',
        lastMessage: chatData?['lastMessage'] as String? ?? '',
        lastMessageTime:
            chatData?['lastMessageTime'] as Timestamp? ?? Timestamp(0, 0),
        unread: (chatData?['unread']?[uid] as num?)?.toInt() ?? 0,
        isOnline: userData['isOnline'] as bool? ?? false,
      );
    });

    final items = await Future.wait(futures);

    items.sort((a, b) => b.lastMessageTime.compareTo(a.lastMessageTime));
    return items;
  }

  // ── Ensure chat doc exists, then clear unread ────────────────────────────
  Future<String> _openChat(ChatItem item) async {
    final uid = _currentUser.uid;
    final chatId = uid.compareTo(item.uid) < 0
        ? '$uid-${item.uid}'
        : '${item.uid}-$uid';

    final ref = _firestore.collection('chats').doc(chatId);
    final snap = await ref.get();

    if (!snap.exists) {
      await ref.set({
        'participants': [uid, item.uid],
        'lastMessage': '',
        'lastMessageTime': Timestamp.now(),
        'unread': {uid: 0, item.uid: 0},
      });
    } else {
      await ref.update({'unread.$uid': 0});
    }

    return chatId;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _formatTimestamp(Timestamp ts) {
    final date = ts.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(date.year, date.month, date.day);

    if (msgDay == today) return DateFormat.Hm().format(date);
    if (msgDay == yesterday) return 'Yesterday';
    if (now.difference(date).inDays < 7) return DateFormat.EEEE().format(date); // e.g. Monday
    return DateFormat('dd/MM/yy').format(date);
  }

  List<ChatItem> get _filtered {
    if (_searchQuery.isEmpty) return _allItems;
    return _allItems
        .where((i) => i.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  Color _avatarColor(String uid) {
    const palette = [
      Color(0xFF6C63FF),
      Color(0xFF00BCD4),
      Color(0xFFFF7043),
      Color(0xFF43A047),
      Color(0xFFE91E63),
      Color(0xFF8D6E63),
      Color(0xFF7E57C2),
      Color(0xFF26A69A),
    ];
    return palette[uid.hashCode.abs() % palette.length];
  }

  // ─────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: _buildAppBar(theme),
      body: Column(
        children: [
          _buildSearchBar(theme),
          Expanded(child: _buildBody(theme)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onNewChat,
        tooltip: 'New chat',
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 4,
        child: const Icon(Icons.chat_rounded),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(ThemeData theme) {
    final unreadTotal = _allItems.fold<int>(0, (sum, i) => sum + i.unread);

    return AppBar(
      title: Row(
        children: [
          const Text(
            'Messages',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 22),
          ),
          if (unreadTotal > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$unreadTotal',
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      scrolledUnderElevation: 1,
      actions: [
        IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: _showOptions,
          tooltip: 'Options',
        ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: SearchBar(
        controller: _searchController,
        hintText: 'Search conversations…',
        leading: const Icon(Icons.search, size: 20),
        trailing: _searchQuery.isNotEmpty
            ? [
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              ]
            : null,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12),
        ),
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return ListView.builder(
        itemCount: 6,
        itemBuilder: (_, i) => _ShimmerTile(key: ValueKey('shimmer_$i')),
      );
    }

    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: () {
        setState(() { _loading = true; _error = null; });
        _listenToData();
      });
    }

    final filtered = _filtered;

    if (_allItems.isEmpty) {
      return const _EmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No conversations yet',
        subtitle: 'Add friends to start chatting',
      );
    }

    if (filtered.isEmpty) {
      return _EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results for "$_searchQuery"',
        subtitle: 'Try a different name',
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _loading = true);
        _listenToData();
        await Future.delayed(const Duration(seconds: 1));
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final item = filtered[index];
          return _ChatTile(
            key: ValueKey(item.uid),
            item: item,
            avatarColor: _avatarColor(item.uid),
            formattedTime: _formatTimestamp(item.lastMessageTime),
            onTap: () => _handleTap(item),
            onLongPress: () => _showTileOptions(item),
          );
        },
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  Future<void> _handleTap(ChatItem item) async {
    final chatId = await _openChat(item);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          friendUid: item.uid,
          friendName: item.name,
        ),
      ),
    );
  }

  void _onNewChat() {
    // TODO: Navigate to new-chat / contact picker screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('New chat coming soon!')),
    );
  }

  void _showOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OptionsSheet(
        items: const [
          (Icons.mark_chat_read_outlined, 'Mark all as read'),
          (Icons.archive_outlined, 'Archived chats'),
          (Icons.settings_outlined, 'Settings'),
        ],
        onTap: (_) => Navigator.pop(context),
      ),
    );
  }

  void _showTileOptions(ChatItem item) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _OptionsSheet(
        title: item.name,
        items: const [
          (Icons.mark_chat_read_outlined, 'Mark as read'),
          (Icons.volume_off_outlined, 'Mute notifications'),
          (Icons.delete_outline_rounded, 'Delete chat'),
          (Icons.block_outlined, 'Block user'),
        ],
        onTap: (_) => Navigator.pop(context),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  CHAT TILE  (extracted for clean rebuilds)
// ─────────────────────────────────────────────
class _ChatTile extends StatelessWidget {
  final ChatItem item;
  final Color avatarColor;
  final String formattedTime;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _ChatTile({
    super.key,
    required this.item,
    required this.avatarColor,
    required this.formattedTime,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasUnread = item.unread > 0;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      splashColor: cs.primary.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // ── Avatar ──────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: avatarColor,
                  backgroundImage: item.avatarUrl.isNotEmpty
                      ? NetworkImage(item.avatarUrl)
                      : null,
                  child: item.avatarUrl.isEmpty
                      ? Text(
                          item.name[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                if (item.isOnline)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 14),

            // ── Text ────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight:
                          hasUnread ? FontWeight.w700 : FontWeight.w500,
                      color: cs.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.lastMessage.isEmpty
                        ? 'Say hello 👋'
                        : item.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: hasUnread
                          ? cs.onSurface.withOpacity(0.85)
                          : cs.onSurface.withOpacity(0.5),
                      fontWeight:
                          hasUnread ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── Right column ─────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: hasUnread ? cs.primary : cs.onSurface.withOpacity(0.4),
                    fontWeight:
                        hasUnread ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 5),
                if (hasUnread)
                  Container(
                    constraints:
                        const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        item.unread > 99 ? '99+' : '${item.unread}',
                        style: TextStyle(
                          color: cs.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  SHIMMER LOADING TILE
// ─────────────────────────────────────────────
class _ShimmerTile extends StatefulWidget {
  const _ShimmerTile({super.key});

  @override
  State<_ShimmerTile> createState() => _ShimmerTileState();
}

class _ShimmerTileState extends State<_ShimmerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base =
        Theme.of(context).colorScheme.onSurface.withOpacity(0.08);
    final highlight =
        Theme.of(context).colorScheme.onSurface.withOpacity(0.15);

    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) {
        final color = Color.lerp(base, highlight, _anim.value)!;
        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(radius: 26, backgroundColor: color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 14,
                        width: 120,
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 8),
                    Container(
                        height: 12,
                        width: 180,
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
              Container(
                  height: 10,
                  width: 40,
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4))),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  EMPTY STATE
// ─────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: cs.onSurface.withOpacity(0.18)),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.6))),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurface.withOpacity(0.35))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  ERROR STATE
// ─────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 56, color: cs.error.withOpacity(0.6)),
            const SizedBox(height: 12),
            Text('Something went wrong',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withOpacity(0.7))),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.4))),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  OPTIONS BOTTOM SHEET
// ─────────────────────────────────────────────
class _OptionsSheet extends StatelessWidget {
  final String? title;
  final List<(IconData, String)> items;
  final void Function(String) onTap;

  const _OptionsSheet({
    this.title,
    required this.items,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                title!,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (final (icon, label) in items)
            ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => onTap(label),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
