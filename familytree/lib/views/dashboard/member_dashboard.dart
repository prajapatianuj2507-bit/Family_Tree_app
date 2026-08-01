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
import '../family_group/family_events_screen.dart';
import '../../core/services/firebase_service.dart';
import 'member_notifications_screen.dart';

class MemberDashboard extends StatelessWidget {
  const MemberDashboard({super.key});

  // ⚠️ FIXED: Synchronized with tree layout and family details spouse pairing logic
  Map<int, List<MemberModel>> _buildGenerations(List<MemberModel> members) {
    final byId  = {for (final m in members) m.id: m};
    final genOf = <String, int>{};

    // 1. Locate root nodes
    final roots = members.where((m) =>
    !(m.fatherId != null && byId.containsKey(m.fatherId)) &&
        !(m.motherId != null && byId.containsKey(m.motherId))).toList();

    // 2. Map generation heights via standard BFS
    final queue = <MapEntry<String, int>>[
      for (final r in roots) MapEntry(r.id, 0)
    ];
    while (queue.isNotEmpty) {
      final e = queue.removeAt(0);
      final id = e.key;
      final g = e.value;

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

    // Fallback isolated nodes to index 0
    for (final m in members) {
      genOf.putIfAbsent(m.id, () => 0);
    }

    // 3. Normalize spouse generations so couples show up under the exact same tab layer
    final Set<String> paired = {};
    for (final m in members) {
      if (paired.contains(m.id)) continue;
      final sid = m.spouseId;
      if (sid == null || !byId.containsKey(sid)) continue;
      if (paired.contains(sid)) continue;

      final selfGen = genOf[m.id]!;
      final spouseGen = genOf[sid]!;

      // Pull couples down to the deepest common generation mapping point
      final coupleGen = selfGen > spouseGen ? selfGen : spouseGen;
      genOf[m.id] = coupleGen;
      genOf[sid]  = coupleGen;

      paired.addAll([m.id, sid]);
    }

    // 4. Split entries out into clean generation buckets
    final grouped = <int, List<MemberModel>>{};
    for (final m in members) {
      grouped.putIfAbsent(genOf[m.id]!, () => []).add(m);
    }
    return grouped;
  }

  String _genLabel(int gen) {
    switch (gen) {
      case 0:  return 'Generation 1 — Founders';
      case 1:  return 'Generation 2';
      case 2:  return 'Generation 3';
      case 3:  return 'Generation 4';
      default: return 'Generation ${gen + 1}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth    = context.read<AuthProvider>();
    final family  = context.watch<FamilyProvider>();
    final members = family.members;
    final me      = auth.currentUser;
    final isAdmin = auth.isAdmin;
    final currentFamily = family.activeFamily;

    // ⚠️ FIXED: Pass the full 'members' array instead of filtering out the logged-in user
    final generationsMap = _buildGenerations(members);
    final sortedGens     = generationsMap.keys.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(currentFamily?.familyName ?? 'Family Tree'),
            if (isAdmin)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, size: 12, color: Colors.amber.shade300),
                  const SizedBox(width: 3),
                  Text(
                    'Family Admin',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amber.shade300,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
          ],
        ),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirebaseService.instance.memberNotificationsStream(currentFamily?.id ?? ''),
            builder: (context, snap) {
              final uid = me?.id ?? '';
              final unreadCount = snap.data?.where((n) {
                final readBy = n['readBy'] as List<dynamic>? ?? [];
                return !readBy.contains(uid);
              }).length ?? 0;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    tooltip: 'Notifications',
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      if (currentFamily == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MemberNotificationsScreen(
                            familyId: currentFamily.id,
                          ),
                        ),
                      );
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            tooltip: 'View Tree',
            icon: const Icon(Icons.account_tree_outlined),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FamilyTreeViewScreen())),
          ),
          if (me != null)
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MemberProfileScreen(
                    member: me,
                    isMaster: false,
                    isSelf: true,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white24,
                  backgroundImage: me.profileImageUrl != null
                      ? CachedNetworkImageProvider(me.profileImageUrl!)
                      : null,
                  child: me.profileImageUrl == null
                      ? const Icon(Icons.person, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ),
        ],
      ),

      // ── FAB: visible only to Family Admins ───────────────────
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text('Add Member',
                  style: TextStyle(color: Colors.white)),
              onPressed: () {
                if (me == null) return;
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AddMemberScreen(
                    familyId:   me.familyId,
                    familyName: currentFamily?.familyName,
                  ),
                ));
              },
            )
          : null,

      body: family.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _DashboardTabs(
              me:             me,
              members:        members,
              generationsMap: generationsMap,
              sortedGens:     sortedGens,
              genLabel:       _genLabel,
              currentFamily:  currentFamily,
              isAdmin:        isAdmin,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Main tabbed view: generation tabs
// ─────────────────────────────────────────────────────────────
class _DashboardTabs extends StatefulWidget {
  final MemberModel?               me;
  final List<MemberModel>          members;
  final Map<int, List<MemberModel>> generationsMap;
  final List<int>                  sortedGens;
  final String Function(int)       genLabel;
  final FamilyModel?               currentFamily;
  final bool                       isAdmin;

  const _DashboardTabs({
    required this.me,
    required this.members,
    required this.generationsMap,
    required this.sortedGens,
    required this.genLabel,
    required this.currentFamily,
    required this.isAdmin,
  });

  @override
  State<_DashboardTabs> createState() => _DashboardTabsState();
}

class _DashboardTabsState extends State<_DashboardTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // Tabs = generations only
  int get _totalTabs => widget.sortedGens.length;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _totalTabs, vsync: this);
  }

  @override
  void didUpdateWidget(_DashboardTabs old) {
    super.didUpdateWidget(old);
    if (old.sortedGens.length != widget.sortedGens.length) {
      final prev = _tab.index;
      _tab.dispose();
      _tab = TabController(length: _totalTabs, vsync: this);
      // Clamp previous index to valid range
      _tab.index = prev.clamp(0, _totalTabs - 1);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Widget _buildTopBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _FamilyPhotoBanner(family: widget.currentFamily),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sortedGens.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBanner(context),
          const Expanded(
            child: Center(
              child: Text(
                'No members in this family yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Family Photo Banner (always at top) ───────────────
        _buildTopBanner(context),

        // ── Tab bar ───────────────────────────────────────────
        Container(
          color: Colors.white,
          child: TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            tabs: widget.sortedGens.map(
              (g) => Tab(text: widget.genLabel(g)),
            ).toList(),
          ),
        ),

        // ── Tab content ───────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: widget.sortedGens.map((g) {
              final genMembers = widget.generationsMap[g]!;
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: genMembers.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _MemberCard(
                  member:    genMembers[i],
                  isAdmin:   widget.isAdmin,
                  isSelf:    genMembers[i].id == widget.me?.id,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => MemberProfileScreen(
                              member:   genMembers[i],
                              isMaster: false,
                              isSelf:   genMembers[i].id == widget.me?.id,
                            )),
                  ),
                  onEdit: widget.isAdmin
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => AddMemberScreen(
                                      familyId: genMembers[i].familyId,
                                      familyName: widget.currentFamily
                                          ?.familyName,
                                      existingMember: genMembers[i],
                                    )),
                          )
                      : null,
                  onDelete: widget.isAdmin
                      ? () => _confirmDelete(context, genMembers[i])
                      : null,
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, MemberModel member) {
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              await context.read<FamilyProvider>().deleteMember(member.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('${member.fullName} removed'),
                  backgroundColor: AppColors.error,
                ));
              }
            },
            child:
                const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Family Photo Banner at top of dashboard
// ─────────────────────────────────────────────────────────────
class _FamilyPhotoBanner extends StatelessWidget {
  final FamilyModel? family;
  const _FamilyPhotoBanner({this.family});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = family?.photoUrl?.trim().isNotEmpty == true;

    return SizedBox(
      height: 160,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          hasPhoto
              ? CachedNetworkImage(
                  imageUrl: family!.photoUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _placeholder(),
                  errorWidget: (_, __, ___) => _placeholder(),
                )
              : _placeholder(),

          // Gradient overlay for text legibility
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.60),
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
                  family?.familyName ?? 'Family Tree',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black54)]),
                ),
                if (family != null && family!.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                     family!.description,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.85), fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                  if (family == null) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FamilyEventsScreen(
                        familyId: family!.id,
                        familyName: family!.familyName,
                        isMaster: false,
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
        color: AppColors.primary.withOpacity(0.10),
        child: Center(
          child: Icon(Icons.family_restroom,
              size: 52, color: AppColors.primary.withOpacity(0.30)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Read-only member card — Admin/Master version shows Edit/Delete and has custom styling
// ─────────────────────────────────────────────────────────────
class _MemberCard extends StatelessWidget {
  final MemberModel   member;
  final bool          isAdmin;
  final bool          isSelf;
  final VoidCallback  onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _MemberCard({
    required this.member,
    required this.isAdmin,
    required this.isSelf,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  String _initials() {
    final f = member.firstName.isNotEmpty ? member.firstName[0].toUpperCase() : '';
    final l = member.lastName.isNotEmpty  ? member.lastName[0].toUpperCase()  : '';
    return '$f$l';
  }

  Color get _color =>
      member.gender == Gender.male ? AppColors.primary : Colors.pink.shade400;

  @override
  Widget build(BuildContext context) {
    final isAdminRole = member.role == 'admin';
    final isMasterRole = member.role == 'master';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelf
              ? AppColors.primary.withOpacity(0.4)
              : AppColors.divider,
          width: isSelf ? 1.5 : 1,
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
                  ? Text(_initials(),
                  style: TextStyle(
                      color: _color,
                      fontWeight: FontWeight.bold, fontSize: 16))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.fullName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelf) ...[
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
                      if (isAdminRole) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade300, width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shield, size: 9, color: Colors.amber.shade800),
                              const SizedBox(width: 2),
                              Text(
                                'Admin',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isMasterRole) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.shade200, width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.gavel, size: 9, color: Colors.purple.shade800),
                              const SizedBox(width: 2),
                              Text(
                                'Master',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.purple.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(member.designationLabel,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ],
              ),
            ),

            // ── Action column ──────────────────────────────────
            if (isAdmin && onEdit != null && onDelete != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: onEdit,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.edit_outlined,
                          size: 20, color: AppColors.primary),
                    ),
                  ),
                  InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.delete_outline,
                          size: 20, color: AppColors.error),
                    ),
                  ),
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