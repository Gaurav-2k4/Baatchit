import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Theme Constants ──────────────────────────────────────────────────────────
class _AppColors {
  static const primary = Color(0xFF3B5BDB);
  static const primaryLight = Color(0xFFEEF3FF);
  static const primaryMid = Color(0xFFBBD0FF);
  static const accent = Color(0xFF40C057);
  static const accentLight = Color(0xFFEBFBEE);
  static const danger = Color(0xFFFA5252);
  static const dangerLight = Color(0xFFFFF5F5);
  static const bg = Color(0xFFF8F9FC);
  static const card = Colors.white;
  static const textDark = Color(0xFF1A1D23);
  static const textMuted = Color(0xFF868E96);
  static const divider = Color(0xFFF1F3F5);
}

// ─── Helper: Initials avatar ──────────────────────────────────────────────────
class _InitialsAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const _InitialsAvatar({required this.name, this.radius = 22});

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  // Simple deterministic color from name
  Color get _color {
    final colors = [
      const Color(0xFF4DABF7),
      const Color(0xFF69DB7C),
      const Color(0xFFFF8787),
      const Color(0xFFCC5DE8),
      const Color(0xFFFFD43B),
      const Color(0xFF20C997),
    ];
    int hash = name.codeUnits.fold(0, (prev, e) => prev + e);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _color.withOpacity(0.25),
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w700,
          color: _color.withOpacity(0.9),
        ),
      ),
    );
  }
}

// ─── Main Widget ──────────────────────────────────────────────────────────────
class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab>
    with SingleTickerProviderStateMixin {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? _currentUser;
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _debounce;

  // Track which UIDs have ongoing operations to show per-button loaders
  final Set<String> _pendingUids = {};

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _tabController = TabController(length: 3, vsync: this);
    _initUser();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ─── User init ────────────────────────────────────────────────────────────
  Future<void> _initUser() async {
    if (_currentUser == null) return;
    final doc = await _db.collection('users').doc(_currentUser!.uid).get();
    if (!doc.exists) {
      await _db.collection('users').doc(_currentUser!.uid).set({
        'uid': _currentUser!.uid,
        'name': _currentUser!.displayName ?? 'User',
        'email': _currentUser!.email ?? '',
        'username': (_currentUser!.displayName ?? 'user')
            .toLowerCase()
            .replaceAll(' ', ''),
        'bio': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // ─── Friend Actions ───────────────────────────────────────────────────────
  Future<void> _withPending(String uid, Future<void> Function() action) async {
    if (_pendingUids.contains(uid)) return;
    setState(() => _pendingUids.add(uid));
    try {
      await action();
    } catch (e) {
      debugPrint('Friend action error: $e');
      _showSnack('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _pendingUids.remove(uid));
    }
  }

  Future<void> _sendRequest(String uid) => _withPending(uid, () async {
        if (uid == _currentUser!.uid) return;
        final myRef = _db.collection('users').doc(_currentUser!.uid);
        final theirRef = _db.collection('users').doc(uid);

        // Already friends?
        if ((await myRef.collection('friends').doc(uid).get()).exists) {
          _showSnack('You are already friends.');
          return;
        }
        // Already sent?
        if ((await theirRef
                .collection('friend_requests')
                .doc(_currentUser!.uid)
                .get())
            .exists) {
          _showSnack('Request already sent.');
          return;
        }
        // They sent us one — auto-accept
        if ((await myRef.collection('friend_requests').doc(uid).get()).exists) {
          await _acceptRequest(uid);
          _showSnack('Friend request accepted!', isSuccess: true);
          return;
        }

        final myData = (await myRef.get()).data() ?? {};
        await theirRef.collection('friend_requests').doc(_currentUser!.uid).set({
          'uid': _currentUser!.uid,
          'name': myData['name'] ?? 'User',
          'username': myData['username'] ?? '',
          'timestamp': FieldValue.serverTimestamp(),
        });
        _showSnack('Friend request sent!', isSuccess: true);
      });

  Future<void> _cancelRequest(String uid) => _withPending(uid, () async {
        await _db
            .collection('users')
            .doc(uid)
            .collection('friend_requests')
            .doc(_currentUser!.uid)
            .delete();
        _showSnack('Request cancelled.');
      });

  Future<void> _acceptRequest(String uid) => _withPending(uid, () async {
        final batch = _db.batch();
        final myFriends =
            _db.collection('users').doc(_currentUser!.uid).collection('friends').doc(uid);
        final theirFriends =
            _db.collection('users').doc(uid).collection('friends').doc(_currentUser!.uid);
        final request = _db
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('friend_requests')
            .doc(uid);

        batch.set(myFriends, {'uid': uid});
        batch.set(theirFriends, {'uid': _currentUser!.uid});
        batch.delete(request);
        await batch.commit();
        _showSnack('Now you are friends!', isSuccess: true);
      });

  Future<void> _declineRequest(String uid) => _withPending(uid, () async {
        await _db
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('friend_requests')
            .doc(uid)
            .delete();
      });

  Future<void> _removeFriend(String uid, String name) async {
    final confirmed = await _showConfirmSheet(
      title: 'Remove Friend',
      message: 'Remove $name from your friends? This cannot be undone.',
      confirmLabel: 'Remove',
      isDanger: true,
    );
    if (!confirmed) return;

    await _withPending(uid, () async {
      final batch = _db.batch();
      batch.delete(_db
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('friends')
          .doc(uid));
      batch.delete(_db
          .collection('users')
          .doc(uid)
          .collection('friends')
          .doc(_currentUser!.uid));
      await batch.commit();
      _showSnack('$name removed from friends.');
    });
  }

  // ─── Snackbar helper ──────────────────────────────────────────────────────
  void _showSnack(String msg, {bool isSuccess = false, bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isSuccess
            ? _AppColors.accent
            : isError
                ? _AppColors.danger
                : const Color(0xFF343A40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      ),
    );
  }

  // ─── Confirm bottom sheet ─────────────────────────────────────────────────
  Future<bool> _showConfirmSheet({
    required String title,
    required String message,
    required String confirmLabel,
    bool isDanger = false,
  }) async {
    return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (_) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(title,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _AppColors.textDark)),
                const SizedBox(height: 10),
                Text(message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, color: _AppColors.textMuted, height: 1.5)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: isDanger
                              ? _AppColors.danger
                              : _AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(confirmLabel),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ) ??
        false;
  }

  // ─── Friend profile sheet ─────────────────────────────────────────────────
  Future<void> _showFriendProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists || !mounted) return;
    final data = doc.data()!;
    final name = data['name'] ?? 'User';
    final username = data['username'] ?? '';
    final bio = data['bio'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            _InitialsAvatar(name: name, radius: 36),
            const SizedBox(height: 14),
            Text(name,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _AppColors.textDark)),
            const SizedBox(height: 4),
            Text('@$username',
                style: const TextStyle(
                    fontSize: 13, color: _AppColors.textMuted)),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(bio,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14,
                        color: _AppColors.textDark,
                        height: 1.5)),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _AppColors.danger,
                  side: const BorderSide(color: _AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.person_remove_outlined, size: 18),
                label: const Text('Remove Friend'),
                onPressed: () async {
                  Navigator.pop(context);
                  await _removeFriend(uid, name);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── BUILD ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in.')),
      );
    }

    return Scaffold(
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Friends',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: _AppColors.textDark,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: _AppColors.primary,
              unselectedLabelColor: _AppColors.textMuted,
              indicatorColor: _AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
              unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500, fontSize: 13),
              tabs: [
                _tabWithBadge('Requests'),
                const Tab(text: 'Friends'),
                const Tab(text: 'Find'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RequestsTab(
            db: _db,
            currentUid: _currentUser!.uid,
            onAccept: _acceptRequest,
            onDecline: _declineRequest,
            pendingUids: _pendingUids,
          ),
          _FriendsListTab(
            db: _db,
            currentUid: _currentUser!.uid,
            onTap: _showFriendProfile,
          ),
          _FindTab(
            db: _db,
            currentUid: _currentUser!.uid,
            searchController: _searchController,
            searchQuery: _searchQuery,
            onSearchChanged: (val) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), () {
                if (mounted) setState(() => _searchQuery = val.toLowerCase().trim());
              });
            },
            onSend: _sendRequest,
            onCancel: _cancelRequest,
            onAccept: _acceptRequest,
            pendingUids: _pendingUids,
          ),
        ],
      ),
    );
  }

  // Badge on requests tab showing count
  Widget _tabWithBadge(String label) {
    return StreamBuilder<QuerySnapshot>(
      stream: _db
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('friend_requests')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _AppColors.danger,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─── Requests Tab ─────────────────────────────────────────────────────────────
class _RequestsTab extends StatelessWidget {
  final FirebaseFirestore db;
  final String currentUid;
  final Future<void> Function(String) onAccept;
  final Future<void> Function(String) onDecline;
  final Set<String> pendingUids;

  const _RequestsTab({
    required this.db,
    required this.currentUid,
    required this.onAccept,
    required this.onDecline,
    required this.pendingUids,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('users')
          .doc(currentUid)
          .collection('friend_requests')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _AppColors.primary));
        }
        if (snap.data!.docs.isEmpty) {
          return _EmptyState(
            icon: Icons.person_add_disabled_outlined,
            title: 'No requests yet',
            subtitle: "When someone adds you, it'll appear here.",
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: snap.data!.docs.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: _AppColors.divider, indent: 72),
          itemBuilder: (context, i) {
            final data =
                snap.data!.docs[i].data() as Map<String, dynamic>;
            final uid = data['uid'] as String;
            final name = data['name'] ?? 'User';
            final username = data['username'] ?? '';
            final isPending = pendingUids.contains(uid);

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: _InitialsAvatar(name: name),
              title: Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: _AppColors.textDark)),
              subtitle: Text('@$username',
                  style: const TextStyle(
                      fontSize: 12, color: _AppColors.textMuted)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Accept
                  _ActionChip(
                    label: 'Accept',
                    color: _AppColors.accent,
                    bgColor: _AppColors.accentLight,
                    isLoading: isPending,
                    onTap: () => onAccept(uid),
                  ),
                  const SizedBox(width: 8),
                  // Decline
                  _ActionChip(
                    label: 'Decline',
                    color: _AppColors.danger,
                    bgColor: _AppColors.dangerLight,
                    isLoading: false,
                    onTap: () => onDecline(uid),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─── Friends List Tab ─────────────────────────────────────────────────────────
class _FriendsListTab extends StatelessWidget {
  final FirebaseFirestore db;
  final String currentUid;
  final void Function(String) onTap;

  const _FriendsListTab({
    required this.db,
    required this.currentUid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db
          .collection('users')
          .doc(currentUid)
          .collection('friends')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _AppColors.primary));
        }
        if (snap.data!.docs.isEmpty) {
          return _EmptyState(
            icon: Icons.group_outlined,
            title: 'No friends yet',
            subtitle: 'Find people using the Find tab.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: snap.data!.docs.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: _AppColors.divider, indent: 72),
          itemBuilder: (context, i) {
            final uid =
                (snap.data!.docs[i].data() as Map<String, dynamic>)['uid']
                    as String;

            return StreamBuilder<DocumentSnapshot>(
              stream: db.collection('users').doc(uid).snapshots(),
              builder: (context, userSnap) {
                if (!userSnap.hasData || !userSnap.data!.exists) {
                  return const SizedBox.shrink();
                }
                final user =
                    userSnap.data!.data() as Map<String, dynamic>;
                final name = user['name'] ?? 'User';

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: _InitialsAvatar(name: name),
                  title: Text(name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _AppColors.textDark)),
                  subtitle: Text('@${user['username'] ?? ''}',
                      style: const TextStyle(
                          fontSize: 12, color: _AppColors.textMuted)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: _AppColors.textMuted, size: 18),
                  onTap: () => onTap(uid),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── Find Tab ─────────────────────────────────────────────────────────────────
class _FindTab extends StatelessWidget {
  final FirebaseFirestore db;
  final String currentUid;
  final TextEditingController searchController;
  final String searchQuery;
  final void Function(String) onSearchChanged;
  final Future<void> Function(String) onSend;
  final Future<void> Function(String) onCancel;
  final Future<void> Function(String) onAccept;
  final Set<String> pendingUids;

  const _FindTab({
    required this.db,
    required this.currentUid,
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    required this.pendingUids,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search by name or username...',
              hintStyle: const TextStyle(
                  fontSize: 13, color: _AppColors.textMuted),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: _AppColors.textMuted, size: 20),
              suffixIcon: searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () {
                        searchController.clear();
                        onSearchChanged('');
                      },
                      child: const Icon(Icons.close_rounded,
                          size: 18, color: _AppColors.textMuted),
                    )
                  : null,
              filled: true,
              fillColor: _AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: _AppColors.divider),
        // User list
        Expanded(child: _UserSearchList(
          db: db,
          currentUid: currentUid,
          searchQuery: searchQuery,
          onSend: onSend,
          onCancel: onCancel,
          onAccept: onAccept,
          pendingUids: pendingUids,
        )),
      ],
    );
  }
}

class _UserSearchList extends StatelessWidget {
  final FirebaseFirestore db;
  final String currentUid;
  final String searchQuery;
  final Future<void> Function(String) onSend;
  final Future<void> Function(String) onCancel;
  final Future<void> Function(String) onAccept;
  final Set<String> pendingUids;

  const _UserSearchList({
    required this.db,
    required this.currentUid,
    required this.searchQuery,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    required this.pendingUids,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: db.collection('users').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: _AppColors.primary));
        }

        final users = snap.data!.docs
            .map((e) => e.data() as Map<String, dynamic>)
            .where((u) => u['uid'] != currentUid)
            .where((u) {
          if (searchQuery.isEmpty) return true;
          return (u['name'] ?? '').toString().toLowerCase().contains(searchQuery) ||
              (u['username'] ?? '').toString().toLowerCase().contains(searchQuery);
        }).toList();

        if (users.isEmpty) {
          return _EmptyState(
            icon: Icons.search_off_rounded,
            title: searchQuery.isEmpty ? 'Find People' : 'No results',
            subtitle: searchQuery.isEmpty
                ? 'Search by name or username.'
                : 'Try a different search.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: users.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: _AppColors.divider, indent: 72),
          itemBuilder: (context, i) {
            final user = users[i];
            final uid = user['uid'] as String;
            final name = user['name'] ?? 'User';
            final isPending = pendingUids.contains(uid);

            return StreamBuilder<DocumentSnapshot>(
              stream: db
                  .collection('users')
                  .doc(uid)
                  .collection('friend_requests')
                  .doc(currentUid)
                  .snapshots(),
              builder: (context, sentSnap) {
                final requestSent =
                    sentSnap.hasData && sentSnap.data!.exists;

                return StreamBuilder<DocumentSnapshot>(
                  stream: db
                      .collection('users')
                      .doc(currentUid)
                      .collection('friend_requests')
                      .doc(uid)
                      .snapshots(),
                  builder: (context, inSnap) {
                    final receivedRequest =
                        inSnap.hasData && inSnap.data!.exists;

                    return StreamBuilder<DocumentSnapshot>(
                      stream: db
                          .collection('users')
                          .doc(currentUid)
                          .collection('friends')
                          .doc(uid)
                          .snapshots(),
                      builder: (context, friendSnap) {
                        final isFriend =
                            friendSnap.hasData && friendSnap.data!.exists;

                        Widget trailing;

                        if (isFriend) {
                          trailing = Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: _AppColors.accentLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Friends',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: _AppColors.accent,
                                  fontWeight: FontWeight.w600),
                            ),
                          );
                        } else if (receivedRequest) {
                          trailing = _ActionChip(
                            label: 'Accept',
                            color: _AppColors.accent,
                            bgColor: _AppColors.accentLight,
                            isLoading: isPending,
                            onTap: () => onAccept(uid),
                          );
                        } else if (requestSent) {
                          trailing = _ActionChip(
                            label: 'Sent',
                            color: _AppColors.textMuted,
                            bgColor: const Color(0xFFF1F3F5),
                            isLoading: isPending,
                            onTap: () => onCancel(uid),
                          );
                        } else {
                          trailing = _ActionChip(
                            label: 'Add',
                            color: _AppColors.primary,
                            bgColor: _AppColors.primaryLight,
                            isLoading: isPending,
                            onTap: () => onSend(uid),
                          );
                        }

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          leading: _InitialsAvatar(name: name),
                          title: Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: _AppColors.textDark)),
                          subtitle: Text(
                              '@${user['username'] ?? ''}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: _AppColors.textMuted)),
                          trailing: trailing,
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _ActionChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bgColor;
  final bool isLoading;
  final VoidCallback onTap;

  const _ActionChip({
    required this.label,
    required this.color,
    required this.bgColor,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: isLoading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color),
              )
            : Text(
                label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color),
              ),
      ),
    );
  }
}

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: _AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _AppColors.textDark)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13,
                    color: _AppColors.textMuted,
                    height: 1.5)),
          ],
        ),
      ),
    );
  }
}
