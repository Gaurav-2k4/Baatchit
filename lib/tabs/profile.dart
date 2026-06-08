import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileTab extends StatefulWidget {
  const ProfileTab({super.key});

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab>
    with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String userName = "";
  String userEmail = "";
  String username = "";
  String uniqueId = "";
  String phone = "";
  String gender = "";
  String bio = "";

  bool isLoading = true;
  bool _isSaving = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Theme colors — change these to match your brand
  static const Color _primaryColor = Color(0xFF3B5BDB);
  static const Color _accentColor = Color(0xFF74C0FC);
  static const Color _bgColor = Color(0xFFF8F9FC);
  static const Color _cardColor = Colors.white;
  static const Color _textDark = Color(0xFF1A1D23);
  static const Color _textMuted = Color(0xFF868E96);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    fetchUserData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> fetchUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final snapshot =
            await _firestore.collection('users').doc(user.uid).get();
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          if (mounted) {
            setState(() {
              userName = data['name'] ?? '';
              userEmail = data['email'] ?? '';
              username = data['username'] ?? '';
              uniqueId = data['uniqueId'] ?? '';
              phone = data['mobile'] ?? '';
              gender = data['gender'] ?? 'Not set';
              bio = data['bio'] ?? 'No bio yet';
              isLoading = false;
            });
            _animController.forward();
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ── Initials avatar fallback ──────────────────────────────────────────────
  String get _initials {
    final parts = userName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return userName.isNotEmpty ? userName[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(
          child: CircularProgressIndicator(color: _primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            _buildSliverAppBar(context),
            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Unique ID chip
                    _buildUniqueIdCard(),
                    const SizedBox(height: 20),

                    // Bio section
                    if (bio.isNotEmpty && bio != 'No bio yet') ...[
                      _sectionLabel("About"),
                      const SizedBox(height: 8),
                      _buildBioCard(),
                      const SizedBox(height: 20),
                    ],

                    // Info section
                    _sectionLabel("Details"),
                    const SizedBox(height: 8),
                    _buildInfoCard(),
                    const SizedBox(height: 20),

                    // Actions
                    _sectionLabel("Account"),
                    const SizedBox(height: 8),
                    _buildActionsCard(context),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Sliver App Bar with avatar ────────────────────────────────────────────
  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 260,
      pinned: true,
      stretch: true,
      backgroundColor: _primaryColor,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes: const [StretchMode.zoomBackground],
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF3B5BDB), Color(0xFF228BE6)],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 10),
                // Avatar
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 46,
                    backgroundColor: const Color(0xFF74C0FC),
                    child: Text(
                      _initials,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Name
                Text(
                  userName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                // Email
                Text(
                  userEmail,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 6),
                // Username badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.35), width: 1),
                  ),
                  child: Text(
                    "@$username",
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Section labels ────────────────────────────────────────────────────────
  Widget _sectionLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: _textMuted,
        letterSpacing: 1.2,
      ),
    );
  }

  // ── Unique ID card ────────────────────────────────────────────────────────
  Widget _buildUniqueIdCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEEF3FF), Color(0xFFE7F5FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBD0FF), width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.fingerprint_rounded,
                color: _primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Unique ID",
                    style: TextStyle(
                        fontSize: 11,
                        color: _textMuted,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                SelectableText(
                  uniqueId,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textDark,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Copy button
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: uniqueId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text("Unique ID copied!"),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: _primaryColor,
                  duration: const Duration(seconds: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.copy_rounded,
                  size: 16, color: _primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bio card ──────────────────────────────────────────────────────────────
  Widget _buildBioCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Text(
        bio,
        style: const TextStyle(
          fontSize: 14,
          color: _textDark,
          height: 1.6,
        ),
      ),
    );
  }

  // ── Info card ─────────────────────────────────────────────────────────────
  Widget _buildInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        children: [
          _infoTile(
            icon: Icons.phone_rounded,
            label: "Phone",
            value: phone.isEmpty ? "Not set" : phone,
            isFirst: true,
          ),
          _divider(),
          _infoTile(
            icon: Icons.wc_rounded,
            label: "Gender",
            value: gender,
          ),
        ],
      ),
    );
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _primaryColor, size: 18),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: _textMuted,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4)),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontSize: 14,
                      color: _textDark,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() => const Divider(
        height: 1,
        indent: 58,
        color: Color(0xFFF1F3F5),
      );

  // ── Actions card ──────────────────────────────────────────────────────────
  Widget _buildActionsCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        children: [
          _actionTile(
            icon: Icons.edit_rounded,
            label: "Edit Profile",
            color: _primaryColor,
            onTap: () => _openEditDialog(context),
          ),
          const Divider(height: 1, indent: 58, color: Color(0xFFF1F3F5)),
          _actionTile(
            icon: Icons.logout_rounded,
            label: "Log Out",
            color: Colors.redAccent,
            onTap: () => _showLogoutDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: color == Colors.redAccent ? Colors.redAccent : _textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
                color: Colors.grey.shade400, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Logout dialog ─────────────────────────────────────────────────────────
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text("Log Out",
            style: TextStyle(fontWeight: FontWeight.w700)),
        content:
            const Text("Are you sure you want to log out of your account?"),
        actionsPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              await _auth.signOut();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (_) => false);
              }
            },
            child: const Text("Log Out"),
          ),
        ],
      ),
    );
  }

  // ── Edit profile bottom sheet ─────────────────────────────────────────────
  void _openEditDialog(BuildContext context) {
    final nameController = TextEditingController(text: userName);
    final phoneController = TextEditingController(text: phone);
    final bioController = TextEditingController(text: bio);

    // Dropdown for gender
    String selectedGender =
        ['Male', 'Female', 'Non-binary', 'Prefer not to say'].contains(gender)
            ? gender
            : 'Prefer not to say';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20, top: 12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const Text(
                      "Edit Profile",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _sheetField(nameController, "Full Name",
                        Icons.person_outline_rounded),
                    const SizedBox(height: 14),
                    _sheetField(
                        phoneController, "Phone Number", Icons.phone_outlined,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 14),

                    // Gender dropdown
                    DropdownButtonFormField<String>(
                      value: selectedGender,
                      decoration: InputDecoration(
                        labelText: "Gender",
                        prefixIcon: const Icon(Icons.wc_rounded,
                            color: _primaryColor, size: 20),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: Colors.grey.shade300)),
                        focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: _primaryColor)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      items: [
                        'Male',
                        'Female',
                        'Non-binary',
                        'Prefer not to say'
                      ]
                          .map(
                              (g) => DropdownMenuItem(value: g, child: Text(g)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null)
                          setSheetState(() => selectedGender = val);
                      },
                    ),
                    const SizedBox(height: 14),
                    _sheetField(
                        bioController, "Bio", Icons.info_outline_rounded,
                        maxLines: 3),
                    const SizedBox(height: 24),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isSaving
                            ? null
                            : () async {
                                setSheetState(() => _isSaving = true);
                                try {
                                  final user = _auth.currentUser;
                                  if (user != null) {
                                    await _firestore
                                        .collection('users')
                                        .doc(user.uid)
                                        .update({
                                      'name': nameController.text.trim(),
                                      'mobile': phoneController.text.trim(),
                                      'gender': selectedGender,
                                      'bio': bioController.text.trim(),
                                    });
                                    if (mounted) {
                                      setState(() {
                                        userName = nameController.text.trim();
                                        phone = phoneController.text.trim();
                                        gender = selectedGender;
                                        bio = bioController.text.trim();
                                      });
                                    }
                                  }
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text("Profile updated!"),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: Colors.green.shade600,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  debugPrint("Save error: $e");
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: const Text(
                                            "Failed to save. Try again."),
                                        behavior: SnackBarBehavior.floating,
                                        backgroundColor: Colors.redAccent,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                      ),
                                    );
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _isSaving = false);
                                  }
                                }
                              },
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text("Save Changes",
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetField(
    TextEditingController controller,
    String label,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _primaryColor, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryColor),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
