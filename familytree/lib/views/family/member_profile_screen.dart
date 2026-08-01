import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../models/member_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/family_provider.dart';
import 'add_member_screen.dart';

class MemberProfileScreen extends StatelessWidget {
  final MemberModel member;
  final bool isMaster;
  /// True when the logged-in user is viewing their own profile.
  final bool isSelf;

  const MemberProfileScreen({
    super.key,
    required this.member,
    required this.isMaster,
    this.isSelf = false,
  });

  @override
  Widget build(BuildContext context) {
    final family   = context.watch<FamilyProvider>();
    final auth     = context.watch<AuthProvider>();
    final me       = auth.currentUser;

    final currentMember = family.findById(member.id) ?? member;
    final father   = family.findById(currentMember.fatherId);
    final mother   = family.findById(currentMember.motherId);
    final spouse   = family.findById(currentMember.spouseId);
    final children = family.childrenOf(currentMember.id);

    final isMasterUser = isMaster || (me?.role == 'master');
    final isSelfUser   = isSelf || (me?.id == currentMember.id);
    final isFamilyAdmin = me?.role == 'admin' && me?.familyId == currentMember.familyId;
    final canEdit       = isMasterUser || isSelfUser || isFamilyAdmin;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // ── Collapsible header ───────────────────────────────
          SliverAppBar(
            expandedHeight: 230,
            pinned: true,
            backgroundColor: AppColors.primary,
            actions: [
              // ── Edit button: visible to Master, the member themselves, or their Family Admin ──
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  tooltip: 'Edit Profile',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => AddMemberScreen(
                              existingMember: currentMember,
                              familyId: currentMember.familyId,
                              // Masters can edit role; family admins and members editing self cannot
                              canEditRole: isMasterUser,
                            )),
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                color: AppColors.primary,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 56),
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      backgroundImage: currentMember.profileImageUrl != null
                          ? CachedNetworkImageProvider(currentMember.profileImageUrl!) : null,
                      child: currentMember.profileImageUrl == null
                          ? Text(_initials(currentMember),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.bold))
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(currentMember.fullName,
                         style: const TextStyle(
                             color: Colors.white,
                             fontSize: 20,
                             fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(currentMember.designationLabel,
                         style: TextStyle(
                             color: Colors.white.withOpacity(0.8), fontSize: 13)),
                    if (currentMember.role == 'admin' || currentMember.role == 'master') ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: currentMember.role == 'master'
                              ? Colors.purple.shade400
                              : Colors.amber.shade600,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          currentMember.role == 'master' ? 'Master' : 'Family Admin',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  _Section(title: 'Personal Information', rows: [
                    _InfoRow(icon: Icons.wc_outlined,
                        label: 'Gender', value: currentMember.gender.name),
                    if (currentMember.education.isNotEmpty)
                      _InfoRow(icon: Icons.school_outlined,
                          label: 'Education', value: currentMember.education),
                  ]),

                  _Section(title: 'Contact & Location', rows: [
                    _InfoRow(icon: Icons.phone_outlined,
                        label: 'Mobile', value: currentMember.mobileNumber),
                    if (currentMember.nativePlace.isNotEmpty)
                      _InfoRow(icon: Icons.location_city_outlined,
                          label: 'Native Place', value: currentMember.nativePlace),
                    if (currentMember.currentAddress.isNotEmpty)
                      _InfoRow(icon: Icons.home_outlined,
                          label: 'Address', value: currentMember.currentAddress),
                  ]),

                  if (father != null || mother != null ||
                      spouse != null || children.isNotEmpty)
                    _RelationSection(
                      title: 'Family',
                      father: father,
                      mother: mother,
                      spouse: spouse,
                      children: children,
                    ),

                  if (isSelfUser) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.logout),
                        label: const Text('Logout', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => _confirmLogout(context),
                      ),
                    ),
                  ],

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              Navigator.pop(dialogCtx);
              Navigator.pop(context); // close profile screen
              authProvider.signOut();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _initials(MemberModel m) {
    final f = m.firstName.isNotEmpty ? m.firstName[0].toUpperCase() : '';
    final l = m.lastName.isNotEmpty  ? m.lastName[0].toUpperCase()  : '';
    return '$f$l';
  }
}

// ── Section wrapper ───────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final visible = rows.whereType<_InfoRow>().toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.primary, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: Column(children: rows),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            Text(value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    ]),
  );
}

// ── Relationships section ─────────────────────────────────────
class _RelationSection extends StatelessWidget {
  final String title;
  final MemberModel? father;
  final MemberModel? mother;
  final MemberModel? spouse;
  final List<MemberModel> children;

  const _RelationSection({
    required this.title,
    this.father, this.mother, this.spouse,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: AppColors.primary, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        const Divider(height: 1),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.divider),
          ),
          child: Column(children: [
            if (father != null)
              _RelationRow(icon: Icons.man_outlined,
                  label: 'Father', member: father!),
            if (mother != null)
              _RelationRow(icon: Icons.woman_outlined,
                  label: 'Mother', member: mother!),
            if (spouse != null)
              _RelationRow(icon: Icons.favorite_outline,
                  label: 'Spouse', member: spouse!),
            ...children.map((c) =>
                _RelationRow(icon: Icons.child_care,
                    label: 'Child', member: c)),
          ]),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _RelationRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final MemberModel member;

  const _RelationRow({
    required this.icon,
    required this.label,
    required this.member,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => MemberProfileScreen(member: member, isMaster: false)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSecondary)),
                Text(member.fullName,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right,
              size: 18, color: AppColors.textSecondary),
        ]),
      ),
    );
  }
}
