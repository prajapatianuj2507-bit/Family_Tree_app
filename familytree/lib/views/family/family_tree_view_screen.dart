import 'package:familytree/views/family/tree_layout.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/constants/app_colors.dart';
import '../../models/member_model.dart';
import '../../providers/family_provider.dart';
import 'member_profile_screen.dart';

class FamilyTreeViewScreen extends StatelessWidget {
  const FamilyTreeViewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final members = context.watch<FamilyProvider>().members;

    return Scaffold(
      backgroundColor: const Color(0xFFEDF2F7),
      appBar: AppBar(
        title: const Text('Family Tree'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Row(children: [
              _dot(AppColors.primary, 'Male'),
              const SizedBox(width: 12),
              _dot(Colors.pink.shade400, 'Female'),
            ]),
          ),
        ],
      ),
      body: members.isEmpty
          ? const Center(
        child: Text(
          'No members yet.\nAdd members and link relationships.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
        ),
      )
          : _TreeView(members: members),
    );
  }

  Widget _dot(Color c, String l) => Row(children: [
    CircleAvatar(radius: 6, backgroundColor: c),
    const SizedBox(width: 4),
    Text(l, style: const TextStyle(color: Colors.black87, fontSize: 12)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// _TreeView
// ─────────────────────────────────────────────────────────────────────────────
class _TreeView extends StatefulWidget {
  final List<MemberModel> members;
  const _TreeView({required this.members});

  @override
  State<_TreeView> createState() => _TreeViewState();
}

class _TreeViewState extends State<_TreeView> {
  final Set<String> _expandedIDs = {};

  Map<String, Offset> _positions      = {};
  List<MemberModel>   _visibleMembers = [];
  double _canvasWidth  = 2000;
  double _canvasHeight = 2000;

  @override
  void initState() {
    super.initState();
    _calculateDynamicLayout();
  }

  @override
  void didUpdateWidget(covariant _TreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.members != oldWidget.members) {
      final currentIds = {for (final m in widget.members) m.id};
      _expandedIDs.removeWhere((id) => !currentIds.contains(id));
      _calculateDynamicLayout();
    }
  }

  // ── Determine which member is the "primary" of a couple ─────────────────
  // Primary = the one the tree is anchored to (receives expand button, owns children).
  // Rules (in priority order):
  //   1. The one with a parent link in the full member list wins.
  //   2. If both or neither have parents → male wins.
  //   3. If same gender → lower id string wins (stable tiebreak).
  bool _isPrimary(MemberModel m) {
    if (m.spouseId == null) return true; // single — always primary

    final byId = {for (final x in widget.members) x.id: x};
    final spouse = byId[m.spouseId!];
    if (spouse == null) return true; // spouse not in list — treat as primary

    final mHasParents = (m.fatherId != null && byId.containsKey(m.fatherId)) ||
        (m.motherId != null && byId.containsKey(m.motherId));
    final sHasParents =
        (spouse.fatherId != null && byId.containsKey(spouse.fatherId)) ||
            (spouse.motherId != null && byId.containsKey(spouse.motherId));

    if (mHasParents && !sHasParents) return true;
    if (!mHasParents && sHasParents) return false;

    // Both or neither have parents — use gender then id as tiebreak
    if (m.gender == Gender.male && spouse.gender != Gender.male) return true;
    if (m.gender != Gender.male && spouse.gender == Gender.male) return false;
    return m.id.compareTo(spouse.id) < 0;
  }

  // ── Filter: which members are currently visible on the canvas ───────────
  // Rules:
  //   • Only "primary" members of a couple can be roots.
  //   • A member appears as a root only if they have no parent in the list.
  //   • Spouse of a root/expanded node becomes visible only when that node
  //     is expanded (even if the spouse has no parents — they are NOT a root).
  //   • Children appear only when their parent node is expanded.
  List<MemberModel> _filterVisibleMembers() {
    final byId = {for (final m in widget.members) m.id: m};
    final Set<String> visibleIds = {};

    // Roots = no parents in list AND is primary of their couple
    final roots = widget.members.where((m) {
      final hasFather = m.fatherId != null && byId.containsKey(m.fatherId);
      final hasMother = m.motherId != null && byId.containsKey(m.motherId);
      return !hasFather && !hasMother && _isPrimary(m);
    }).toList();

    void traverse(MemberModel node) {
      final expanded = _expandedIDs.contains(node.id) ||
          (node.spouseId != null && _expandedIDs.contains(node.spouseId));

      if (expanded) {
        // Show children of this node OR its spouse
        final children = widget.members.where((m) =>
        m.fatherId == node.id ||
            m.motherId == node.id ||
            (node.spouseId != null &&
                (m.fatherId == node.spouseId ||
                    m.motherId == node.spouseId)));

        for (final child in children) {
          // Only add the primary of each child couple — the secondary
          // will be revealed when that child is in turn expanded
          if (_isPrimary(child)) {
            visibleIds.add(child.id);
            if (child.spouseId != null && byId.containsKey(child.spouseId!)) {
              visibleIds.add(child.spouseId!);
            }
            traverse(child);
          } else {
            // child is a secondary (spouse-linked child) — add their primary instead
            final primaryId = child.spouseId;
            if (primaryId != null && byId.containsKey(primaryId)) {
              visibleIds.add(primaryId);
              final primaryNode = byId[primaryId]!;
              if (primaryNode.spouseId != null && byId.containsKey(primaryNode.spouseId!)) {
                visibleIds.add(primaryNode.spouseId!);
              }
              traverse(primaryNode);
            }
          }
        }
      }
    }

    for (final root in roots) {
      visibleIds.add(root.id);
      if (root.spouseId != null && byId.containsKey(root.spouseId!)) {
        visibleIds.add(root.spouseId!);
      }
      traverse(root);
    }

    return widget.members.where((m) => visibleIds.contains(m.id)).toList();
  }

  void _calculateDynamicLayout() {
    _visibleMembers = _filterVisibleMembers();
    _positions      = TreeLayout.compute(_visibleMembers);

    double maxX = 0, maxY = 0;
    for (final pos in _positions.values) {
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }

    setState(() {
      _canvasWidth  = maxX + kCardW + (kPadX * 2);
      _canvasHeight = maxY + kCardH + (kPadY * 2);
    });
  }

  Set<String> _getDescendantIds(String memberId, String? spouseId) {
    final descendants = <String>{};
    final queue       = <String>[memberId];
    if (spouseId != null) queue.add(spouseId);

    while (queue.isNotEmpty) {
      final parentId = queue.removeAt(0);
      for (final m in widget.members) {
        if (m.fatherId == parentId || m.motherId == parentId) {
          if (descendants.add(m.id)) {
            queue.add(m.id);
            if (m.spouseId != null) {
              descendants.add(m.spouseId!);
              queue.add(m.spouseId!);
            }
          }
        }
      }
    }
    return descendants;
  }

  void _toggleNodeExpansion(String memberId, String? spouseId) {
    setState(() {
      final isExpanded = _expandedIDs.contains(memberId) ||
          (spouseId != null && _expandedIDs.contains(spouseId));

      if (isExpanded) {
        _expandedIDs.remove(memberId);
        if (spouseId != null) _expandedIDs.remove(spouseId);
        _expandedIDs.removeAll(_getDescendantIds(memberId, spouseId));
      } else {
        _expandedIDs.add(memberId);
      }
    });
    _calculateDynamicLayout();
  }

  bool _hasChildren(String memberId) {
    return widget.members
        .any((m) => m.fatherId == memberId || m.motherId == memberId);
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      boundaryMargin: const EdgeInsets.all(100),
      minScale: 0.1,
      maxScale: 2.0,
      constrained: false,
      child: Container(
        width:  _canvasWidth,
        height: _canvasHeight,
        color:  const Color(0xFFEDF2F7),
        child: Stack(
          children: [
            CustomPaint(
              size: Size(_canvasWidth, _canvasHeight),
              painter: _TreeLinePainter(
                members:   _visibleMembers,
                positions: _positions,
              ),
            ),

            ..._visibleMembers.map((member) {
              final offset = _positions[member.id];
              if (offset == null) return const SizedBox.shrink();

              // Has children = this member or their spouse has children
              final hasKids = _hasChildren(member.id) ||
                  (member.spouseId != null &&
                      _hasChildren(member.spouseId!));

              final isCurrentlyExpanded =
                  _expandedIDs.contains(member.id) ||
                      (member.spouseId != null &&
                          _expandedIDs.contains(member.spouseId!));

              // Expand button only on the primary node of a couple
              final showExpandButton = hasKids && _isPrimary(member);

              return Positioned(
                left: offset.dx,
                top:  offset.dy,
                child: _MemberCard(
                  member:          member,
                  canExpand:       hasKids && _isPrimary(member),
                  showExpandIcon:  showExpandButton,
                  isExpanded:      isCurrentlyExpanded,
                  onToggleExpand:  () => _toggleNodeExpansion(
                      member.id, member.spouseId),
                  onLongPressProfile: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MemberProfileScreen(
                          member: member, isMaster: false),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Line painter
// ─────────────────────────────────────────────────────────────────────────────
class _TreeLinePainter extends CustomPainter {
  final List<MemberModel>   members;
  final Map<String, Offset> positions;

  _TreeLinePainter({required this.members, required this.positions});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color      = Colors.grey.shade400
      ..strokeWidth = 2.0
      ..style      = PaintingStyle.stroke;

    final heartPaint = Paint()
      ..color = Colors.pink.shade300
      ..style = PaintingStyle.fill;

    final byId = <String, MemberModel>{for (final m in members) m.id: m};

    for (final m in members) {
      final selfOffset = positions[m.id];
      if (selfOffset == null) continue;

      // ── Spouse connector (draw only from the primary side) ────
      if (m.spouseId != null) {
        final spouse = byId[m.spouseId!];
        if (spouse != null && positions.containsKey(spouse.id)) {
          // Draw from whichever is on the left
          final myX     = selfOffset.dx;
          final spouseX = positions[spouse.id]!.dx;
          if (myX < spouseX) {
            final p1 = Offset(myX + kCardW, selfOffset.dy + kCardH / 2);
            final p2 = Offset(spouseX,      positions[spouse.id]!.dy + kCardH / 2);
            canvas.drawLine(p1, p2, linePaint);
            final mid = Offset((p1.dx + p2.dx) / 2, p1.dy);
            canvas.drawCircle(mid, 5, heartPaint);
          }
        }
      }

      // ── Parent → child connector ──────────────────────────────
      final parentId = (m.fatherId != null && byId.containsKey(m.fatherId))
          ? m.fatherId
          : (m.motherId != null && byId.containsKey(m.motherId)
          ? m.motherId
          : null);

      if (parentId != null) {
        final parentOffset = positions[parentId];
        final parent       = byId[parentId];
        if (parentOffset == null || parent == null) continue;

        // Anchor the line to the midpoint between parent and spouse (if visible)
        Offset parentAnchor;
        if (parent.spouseId != null &&
            positions.containsKey(parent.spouseId)) {
          final spouseOffset = positions[parent.spouseId!]!;
          final leftX = parentOffset.dx < spouseOffset.dx
              ? parentOffset.dx
              : spouseOffset.dx;
          parentAnchor = Offset(
              leftX + kCardW + kSpouseGap / 2,
              parentOffset.dy + kCardH / 2);
        } else {
          parentAnchor =
              Offset(parentOffset.dx + kCardW / 2, parentOffset.dy + kCardH);
        }

        final childTop = Offset(selfOffset.dx + kCardW / 2, selfOffset.dy);
        final midY     = (parentAnchor.dy + childTop.dy) / 2;

        canvas.drawLine(parentAnchor, Offset(parentAnchor.dx, midY), linePaint);
        canvas.drawLine(
            Offset(parentAnchor.dx, midY), Offset(childTop.dx, midY), linePaint);
        canvas.drawLine(Offset(childTop.dx, midY), childTop, linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TreeLinePainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Member card widget
// ─────────────────────────────────────────────────────────────────────────────
class _MemberCard extends StatelessWidget {
  final MemberModel  member;
  final bool         canExpand;
  final bool         showExpandIcon;
  final bool         isExpanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onLongPressProfile;

  const _MemberCard({
    required this.member,
    required this.canExpand,
    required this.showExpandIcon,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onLongPressProfile,
  });

  String get _initials {
    final f = member.firstName.isNotEmpty ? member.firstName[0].toUpperCase() : '';
    final l = member.lastName.isNotEmpty  ? member.lastName[0].toUpperCase()  : '';
    return '$f$l';
  }

  Color get _color =>
      member.gender == Gender.male ? AppColors.primary : Colors.pink.shade400;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap:      canExpand ? onToggleExpand : onLongPressProfile,
          onLongPress: onLongPressProfile,
          child: Container(
            width:  kCardW,
            height: kCardH,
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isExpanded ? _color : _color.withOpacity(0.3),
                width: isExpanded ? 2.2 : 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color:      _color.withOpacity(0.15),
                  blurRadius: 8,
                  offset:     const Offset(0, 3),
                )
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius:          26,
                  backgroundColor: _color.withOpacity(0.12),
                  backgroundImage: member.profileImageUrl != null
                      ? CachedNetworkImageProvider(member.profileImageUrl!)
                      : null,
                  child: member.profileImageUrl == null
                      ? Text(_initials,
                      style: TextStyle(
                          color:      _color,
                          fontWeight: FontWeight.bold,
                          fontSize:   15))
                      : null,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    member.fullName,
                    textAlign:  TextAlign.center,
                    maxLines:   2,
                    overflow:   TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize:   11,
                      fontWeight: FontWeight.w600,
                      color:      AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color:        _color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    member.designationLabel,
                    style: TextStyle(
                        fontSize:   9,
                        color:      _color,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expand/collapse button — only on primary node
        if (showExpandIcon)
          Positioned(
            bottom: -11,
            left:   0,
            right:  0,
            child: Center(
              child: GestureDetector(
                onTap: onToggleExpand,
                child: Container(
                  width:  22,
                  height: 22,
                  decoration: BoxDecoration(
                    color:  _color,
                    shape:  BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.2),
                        blurRadius: 3,
                        offset:     const Offset(0, 1),
                      )
                    ],
                  ),
                  child: Icon(
                    isExpanded ? Icons.remove : Icons.add,
                    color: Colors.white,
                    size:  14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}