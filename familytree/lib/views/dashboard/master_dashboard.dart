import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/firebase_service.dart';
import '../../models/family_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/family_group_provider.dart';
import '../family_group/create_family_screen.dart';
import 'master_notifications_screen.dart';
import '../family_group/family_detail_screen.dart';

class MasterDashboard extends StatefulWidget {
  const MasterDashboard({super.key});

  @override
  State<MasterDashboard> createState() => _MasterDashboardState();
}

class _MasterDashboardState extends State<MasterDashboard> {
  Stream<List<Map<String, dynamic>>>? _resetStream;
  List<String> _streamFamilyIds = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final masterId = context.read<AuthProvider>().currentUser?.id ?? '';
      context.read<FamilyGroupProvider>().startListening(masterId);
    });
  }

  Stream<List<Map<String, dynamic>>> _getResetStream(List<String> ids) {
    if (ids.isEmpty) return const Stream.empty();
    final changed = ids.length != _streamFamilyIds.length ||
        ids.any((id) => !_streamFamilyIds.contains(id));
    if (changed || _resetStream == null) {
      _streamFamilyIds = List.unmodifiable(ids);
      _resetStream =
          FirebaseService.instance.resetRequestsStream(_streamFamilyIds);
    }
    return _resetStream!;
  }

  @override
  Widget build(BuildContext context) {
    final auth     = context.watch<AuthProvider>();
    final provider = context.watch<FamilyGroupProvider>();
    final families = provider.families;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Welcome, ${auth.currentUser?.firstName ?? ''}'),
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _getResetStream(families.map((f) => f.id).toList()),
            builder: (context, resetSnap) {
              return StreamBuilder<List<Map<String, dynamic>>>(
                stream: FirebaseService.instance.masterNotificationsStream(),
                builder: (context, notifSnap) {
                  final uid = auth.currentUser?.id ?? '';
                  final resetsCount = resetSnap.data?.length ?? 0;
                  final notifsCount = notifSnap.data?.where((n) {
                    final readBy = n['readBy'] as List<dynamic>? ?? [];
                    return !readBy.contains(uid);
                  }).length ?? 0;
                  final count = resetsCount + notifsCount;
                  return Stack(children: [
                    IconButton(
                      tooltip: 'Notifications',
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MasterNotificationsScreen()),
                      ),
                    ),
                    if (count > 0)
                      Positioned(
                        right: 8, top: 8,
                        child: Container(
                          width: 16, height: 16,
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: Center(
                            child: Text('$count',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                  ]);
                }
              );
            },
          ),
          IconButton(
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context, auth),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Family', style: TextStyle(color: Colors.white)),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateFamilyScreen()),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity, color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${families.length} ${families.length == 1 ? 'Family' : 'Families'}',
                  style: const TextStyle(fontSize: 22,
                      fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const Text('Tap a family to manage members',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 1),
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : families.isEmpty
                ? _EmptyState(
              onAdd: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const CreateFamilyScreen()),
              ),
            )
                : ListView.separated(
              padding:
              const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: families.length,
              separatorBuilder: (_, __) =>
              const SizedBox(height: 12),
              itemBuilder: (_, i) => _FamilyCard(
                family:   families[i],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        FamilyDetailScreen(
                          family:   families[i],
                          isMaster: true,
                          isAdmin:  true,
                        ),
                  ),
                ),
                onEdit: () => _editFamily(context, families[i]),
                onDelete: () =>
                    _confirmDelete(context, provider, families[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editFamily(BuildContext context, FamilyModel family) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => CreateFamilyScreen(existingFamily: family),
    ));
  }

  void _confirmLogout(BuildContext context, AuthProvider auth) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
            ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(context);
              context.read<FamilyGroupProvider>().stopListening();
              auth.signOut();
            },
            child: const Text('Logout',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, FamilyGroupProvider provider,
      FamilyModel family) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Family'),
        content: Text(
            'Delete "${family.familyName}" and all its members?\n'
                'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            style:
            ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              Navigator.pop(context);
              final ok = await provider.deleteFamily(family.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(ok
                      ? '"${family.familyName}" deleted'
                      : provider.errorMessage ?? 'Delete failed'),
                  backgroundColor:
                  ok ? AppColors.success : AppColors.error,
                ));
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Family card — shows photo banner + info row
// ─────────────────────────────────────────────────────────────
class _FamilyCard extends StatelessWidget {
  final FamilyModel  family;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _FamilyCard({
    required this.family,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasPhoto = family.photoUrl != null &&
        family.photoUrl!.trim().isNotEmpty;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Photo banner (full width, rounded top) ────────
            ClipRRect(
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(14)),
              child: hasPhoto
                  ? CachedNetworkImage(
                imageUrl: family.photoUrl!,
                height: 130,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 130,
                  color: AppColors.primary.withOpacity(0.06),
                  child: const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) =>
                    _photoPlaceholder(rounded: false),
              )
                  : _photoPlaceholder(rounded: false),
            ),

            // ── Info row ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(family.familyName,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      if (family.description.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(family.description,
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 6),
                      StreamBuilder<int>(
                        stream: FirebaseService.instance
                            .memberCountStream(family.id),
                        builder: (context, snap) {
                          final count =
                              snap.data ?? family.memberCount;
                          return Row(children: [
                            const Icon(Icons.person,
                                size: 13,
                                color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              '$count ${count == 1 ? 'member' : 'members'}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ]);
                        },
                      ),
                    ],
                  ),
                ),

                // Edit / delete
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
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder({required bool rounded}) {
    return Container(
      height: 90,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.07),
        borderRadius: rounded
            ? const BorderRadius.vertical(top: Radius.circular(14))
            : BorderRadius.zero,
      ),
      child: Center(
        child: Icon(Icons.family_restroom,
            size: 40, color: AppColors.primary.withOpacity(0.3)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.family_restroom,
            size: 80, color: Colors.grey.shade300),
        const SizedBox(height: 16),
        const Text('No families yet',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        const Text('Create your first family to get started',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Create Family'),
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
    ),
  );
}