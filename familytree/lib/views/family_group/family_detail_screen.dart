import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../models/family_model.dart';
import '../../models/member_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/family_provider.dart';
import '../family/add_member_screen.dart';
import '../family/family_tree_view_screen.dart';
import '../family/member_profile_screen.dart';
import 'family_events_screen.dart';

class FamilyDetailScreen extends StatefulWidget {
  final FamilyModel family;
  final bool        isMaster;
  final bool        isAdmin;

  const FamilyDetailScreen({
    super.key,
    required this.family,
    this.isMaster = false,
    this.isAdmin  = false,
  });

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  bool get _canAct => widget.isMaster || widget.isAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FamilyProvider>().startListening(widget.family.id);
    });
  }

  // TODO: Move this method into FamilyProvider to prevent frame stuttering on rebuilds!
  Map<int, List<MemberModel>> _buildGenerations(List<MemberModel> members) {
    final byId  = {for (final m in members) m.id: m};
    final genOf = <String, int>{};

    final roots = members.where((m) =>
    !(m.fatherId != null && byId.containsKey(m.fatherId)) &&
        !(m.motherId != null && byId.containsKey(m.motherId))).toList();

    final queue = <MapEntry<String, int>>[
      for (final r in roots) MapEntry(r.id, 0)
    ];
    while (queue.isNotEmpty) {
      final e  = queue.removeAt(0);
      final id = e.key;
      final g  = e.value;
      final currentGen = genOf[id] ?? -1;
      if (currentGen < g) {
        genOf[id] = g;
        for (final m in members) {
          if (m.fatherId == id || m.motherId == id) {
            queue.add(MapEntry(m.id, g + 1));
          }
        }
      }
    }
    for (final m in members) {
      genOf.putIfAbsent(m.id, () => 0);
    }

    // Sync spouses to same generation
    final Set<String> paired = {};
    for (final m in members) {
      if (paired.contains(m.id)) continue;
      final sid = m.spouseId;
      if (sid == null || !byId.containsKey(sid)) continue;
      if (paired.contains(sid)) continue;
      final coupleGen = (genOf[m.id]! > genOf[sid]!) ? genOf[m.id]! : genOf[sid]!;
      genOf[m.id] = coupleGen;
      genOf[sid]  = coupleGen;
      paired.addAll([m.id, sid]);
    }

    final grouped = <int, List<MemberModel>>{};
    for (final m in members) {
      grouped.putIfAbsent(genOf[m.id]!, () => []).add(m);
    }
    return grouped;
  }

  String _genLabel(int gen) {
    switch (gen) {
      case 0:  return 'Generation 1';
      case 1:  return 'Generation 2';
      case 2:  return 'Generation 3';
      case 3:  return 'Generation 4';
      default: return 'Generation ${gen + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final family     = context.watch<FamilyProvider>();
    final members    = family.members;
    final genMap     = _buildGenerations(members);
    final sortedGens = genMap.keys.toList()..sort();
    final me         = context.read<AuthProvider>().currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.family.familyName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(color: AppColors.primary),
        ),
        actions: [
          IconButton(
            tooltip: 'View Tree',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const FamilyTreeViewScreen())),
          ),
        ],
      ),
      // ── FAB: Add Member — only for Master / Admin ──────────
      floatingActionButton: _canAct
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text('Add Member',
                  style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => AddMemberScreen(
                          familyId:   widget.family.id,
                          familyName: widget.family.familyName,
                        )),
              ),
            )
          : null,
      body: Column(
        children: [
          // ── Full-width photo banner ──────────────────────
          _FamilyPhotoBanner(family: widget.family, isMaster: widget.isMaster),

          // ── Generation tab view ──────────────────────────
          Expanded(
            child: family.isLoading
                ? const Center(child: CircularProgressIndicator())
                : members.isEmpty
                ? _EmptyState(
              canAct: _canAct,
              onAdd: _canAct
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => AddMemberScreen(
                                familyId:   widget.family.id,
                                familyName: widget.family.familyName,
                              )))
                  : null,
            )
                : _GenerationTabView(
              genMap:     genMap,
              sortedGens: sortedGens,
              genLabel:   _genLabel,
              showActions: _canAct,
              canPromote:  widget.isMaster,
              currentUserId: me?.id,
              onTap: (m) => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => MemberProfileScreen(
                        member: m,
                        isMaster: widget.isMaster,
                        isSelf: m.id == me?.id)),
              ),
              onEdit: (m) => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => AddMemberScreen(
                          familyId:       widget.family.id,
                          familyName:     widget.family.familyName,
                          existingMember: m,
                          canEditRole:    widget.isMaster,
                        )),
              ),
              onDelete: (m) => _confirmDelete(context, family, m),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, FamilyProvider provider,
      MemberModel member) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove ${member.fullName} from this family?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              await provider.deleteMember(member.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${member.fullName} removed'),
                  backgroundColor: AppColors.error,
                ));
              }
            },
            child: const Text('Remove',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Full-width horizontal photo banner with family info overlay
// ─────────────────────────────────────────────────────────────
class _FamilyPhotoBanner extends StatelessWidget {
  final FamilyModel family;
  final bool isMaster;
  const _FamilyPhotoBanner({required this.family, required this.isMaster});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = family.photoUrl != null &&
        family.photoUrl!.trim().isNotEmpty;

    return SizedBox(
      height: 180,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasPhoto
              ? CachedNetworkImage(
            imageUrl: family.photoUrl!,
            fit: BoxFit.cover,
            placeholder: (_, __) => _placeholder(),
            errorWidget: (_, __, ___) => _placeholder(),
          )
              : _placeholder(),

          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.65),
                ],
              ),
            ),
          ),

          Positioned(
            left: 16, right: 16, bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  family.familyName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black54)
                      ]),
                ),
                if (family.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    family.description,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13),
                  ),
                ],
              ],
            ),
          ),

          Positioned(
            right: 16,
            top: 16,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FamilyEventsScreen(
                        familyId: family.id,
                        familyName: family.familyName,
                        isMaster: isMaster,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Events',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.primary.withOpacity(0.12),
    child: Center(
      child: Icon(Icons.family_restroom,
          size: 64, color: AppColors.primary.withOpacity(0.35)),
    ),
  );
}

// ─────────────────────────────────────────────────────────────
// Generation tab view — role-aware action buttons
// ─────────────────────────────────────────────────────────────
class _GenerationTabView extends StatelessWidget {
  final Map<int, List<MemberModel>> genMap;
  final List<int>                   sortedGens;
  final String Function(int)        genLabel;
  final bool                        showActions;
  final bool                        canPromote;
  final String?                     currentUserId;
  final void Function(MemberModel)  onTap;
  final void Function(MemberModel)  onEdit;
  final void Function(MemberModel)  onDelete;

  const _GenerationTabView({
    required this.genMap,
    required this.sortedGens,
    required this.genLabel,
    required this.showActions,
    required this.canPromote,
    required this.currentUserId,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      key: ValueKey(sortedGens.length),
      length: sortedGens.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              tabs: sortedGens
                  .map((g) => Tab(text: genLabel(g)))
                  .toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: sortedGens.map((g) {
                final genMembers = genMap[g] ?? [];
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: genMembers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _MemberCard(
                    member:       genMembers[i],
                    showActions:  showActions,
                    canPromote:   canPromote,
                    isCurrentUser: genMembers[i].id == currentUserId,
                    onTap:        () => onTap(genMembers[i]),
                    onEdit:       () => onEdit(genMembers[i]),
                    onDelete:     () => onDelete(genMembers[i]),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Member card — shows edit/delete only when showActions is true
// ─────────────────────────────────────────────────────────────
class _MemberCard extends StatelessWidget {
  final MemberModel  member;
  final bool         showActions;
  final bool         canPromote;
  final bool         isCurrentUser;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MemberCard({
    required this.member,
    required this.showActions,
    required this.canPromote,
    required this.isCurrentUser,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  String get _initials {
    final f = member.firstName.isNotEmpty ? member.firstName[0].toUpperCase() : '';
    final l = member.lastName.isNotEmpty ? member.lastName[0].toUpperCase() : '';
    return '$f$l';
  }

  Color get _color => member.gender == Gender.male
      ? AppColors.primary : Colors.pink.shade400;

  String get _roleLabel {
    switch (member.role) {
      case 'master': return 'Master';
      case 'admin':  return 'Admin';
      default:       return 'Member';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCurrentUser
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.divider,
          width: isCurrentUser ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: _color.withOpacity(0.12),
              backgroundImage: member.profileImageUrl != null
                  ? CachedNetworkImageProvider(member.profileImageUrl!) : null,
              child: member.profileImageUrl == null
                  ? Text(_initials,
                  style: TextStyle(
                      color: _color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                      Flexible(
                        child: Text(
                          member.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('You',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(member.mobileNumber,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text(member.designationLabel,
                        style: TextStyle(
                            fontSize: 11,
                            color: _color,
                            fontWeight: FontWeight.w500)),
                    if (member.role == 'admin') ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_roleLabel,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),

            // ── Action buttons: visible only to Admin/Master ───
            if (showActions)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Master gets a popup menu with Edit + Change Role
                  if (canPromote)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 20, color: AppColors.textSecondary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      onSelected: (val) {
                        if (val == 'edit')   onEdit();
                        if (val == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit_outlined,
                                size: 18, color: AppColors.primary),
                            SizedBox(width: 8),
                            Text('Edit / Change Role'),
                          ]),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline,
                                size: 18, color: AppColors.error),
                            SizedBox(width: 8),
                            Text('Remove',
                                style: TextStyle(color: AppColors.error)),
                          ]),
                        ),
                      ],
                    )
                  else ...[
                    // Admin: plain icon buttons
                    InkWell(
                      onTap: onEdit,
                      child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.edit_outlined,
                              size: 20, color: AppColors.primary)),
                    ),
                    InkWell(
                      onTap: onDelete,
                      child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(Icons.delete_outline,
                              size: 20, color: AppColors.error)),
                    ),
                  ],
                ],
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ]),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool         canAct;
  final VoidCallback? onAdd;
  const _EmptyState({required this.canAct, this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.people_outline,
            size: 72, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text('No members yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Text(
          canAct
              ? 'Tap + Add Member to get started'
              : 'No members have been added yet',
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 13),
        ),
        if (canAct && onAdd != null) ...[
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.person_add),
            label: const Text('Add Member'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ],
    ),
  );
}