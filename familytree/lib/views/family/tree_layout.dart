import 'dart:ui';

import '../../models/member_model.dart';

// Card dimensions — must match family_tree_view_screen.dart
const double kCardW     = 110.0;
const double kCardH     = 130.0;
const double kHGap      = 36.0;
const double kSpouseGap = 12.0;
const double kVGap      = 110.0;
const double kPadX      = 48.0;
const double kPadY      = 48.0;

class TreeNode {
  final MemberModel member;
  int    generation;
  double x = 0;
  double y = 0;
  TreeNode?      spouse;
  bool           isLeftNode = true; // left card of a couple (primary)
  List<TreeNode> children   = [];

  TreeNode({required this.member, required this.generation});
}

class TreeLayout {
  static Map<String, Offset> compute(List<MemberModel> visibleMembers) {
    if (visibleMembers.isEmpty) return {};

    final byId  = <String, MemberModel>{for (final m in visibleMembers) m.id: m};
    final nodes = <String, TreeNode>{
      for (final m in visibleMembers) m.id: TreeNode(member: m, generation: -1)
    };

    // ── 1. Assign generations via BFS from roots ──────────────────────────
    // Root = no father AND no mother in the visible set
    final roots = visibleMembers.where((m) {
      final hasFather = m.fatherId != null && byId.containsKey(m.fatherId);
      final hasMother = m.motherId != null && byId.containsKey(m.motherId);
      return !hasFather && !hasMother;
    }).toList();

    final queue = <MapEntry<String, int>>[
      for (final r in roots) MapEntry(r.id, 0),
    ];

    while (queue.isNotEmpty) {
      final e  = queue.removeAt(0);
      final id = e.key;
      final g  = e.value;
      if (!nodes.containsKey(id)) continue;
      final node = nodes[id]!;
      if (node.generation < g) {
        node.generation = g;
        for (final m in visibleMembers) {
          if (m.fatherId == id || m.motherId == id) {
            queue.add(MapEntry(m.id, g + 1));
          }
        }
      }
    }

    // Fallback for nodes not reached
    for (final n in nodes.values) {
      if (n.generation == -1) n.generation = 0;
    }

    // ── 2. Sync spouse generations (take max of the two) ─────────────────
    bool changed = true;
    while (changed) {
      changed = false;
      for (final m in visibleMembers) {
        if (m.spouseId == null || !nodes.containsKey(m.spouseId)) continue;
        final gA = nodes[m.id]!.generation;
        final gB = nodes[m.spouseId!]!.generation;
        final mx = gA > gB ? gA : gB;
        if (nodes[m.id]!.generation != mx) {
          nodes[m.id]!.generation = mx;
          changed = true;
        }
        if (nodes[m.spouseId!]!.generation != mx) {
          nodes[m.spouseId!]!.generation = mx;
          changed = true;
        }
      }
    }

    // ── 3. Pair spouses — left/right assignment ───────────────────────────
    // "Left" node = primary (has parent link, or male, or lower id as tiebreak)
    final Set<String> paired = {};

    for (final node in nodes.values) {
      if (paired.contains(node.member.id)) continue;
      final sid = node.member.spouseId;
      if (sid == null || !nodes.containsKey(sid)) continue;
      if (paired.contains(sid)) continue;

      final spouseNode = nodes[sid]!;
      final m          = node.member;
      final s          = spouseNode.member;

      // Determine which is left (primary)
      final mHasParents =
          (m.fatherId != null && byId.containsKey(m.fatherId)) ||
              (m.motherId != null && byId.containsKey(m.motherId));
      final sHasParents =
          (s.fatherId != null && byId.containsKey(s.fatherId)) ||
              (s.motherId != null && byId.containsKey(s.motherId));

      TreeNode left;
      TreeNode right;

      if (mHasParents && !sHasParents) {
        left  = node;
        right = spouseNode;
      } else if (!mHasParents && sHasParents) {
        left  = spouseNode;
        right = node;
      } else if (m.gender == Gender.male && s.gender != Gender.male) {
        left  = node;
        right = spouseNode;
      } else if (m.gender != Gender.male && s.gender == Gender.male) {
        left  = spouseNode;
        right = node;
      } else {
        // Same gender or both have parents — stable tiebreak by id
        if (m.id.compareTo(s.id) < 0) {
          left  = node;
          right = spouseNode;
        } else {
          left  = spouseNode;
          right = node;
        }
      }

      left.spouse       = right;
      left.isLeftNode   = true;
      right.spouse      = left;
      right.isLeftNode  = false;

      paired.addAll([m.id, sid]);
    }

    // ── 4. Wire parent → children (attach to left/primary parent) ────────
    for (final node in nodes.values) {
      final m = node.member;

      TreeNode? parentNode;
      if (m.fatherId != null && nodes.containsKey(m.fatherId)) {
        parentNode = nodes[m.fatherId]!;
      } else if (m.motherId != null && nodes.containsKey(m.motherId)) {
        parentNode = nodes[m.motherId]!;
      }
      if (parentNode == null) continue;

      // Always attach to the left (primary) of the couple
      if (!parentNode.isLeftNode && parentNode.spouse != null) {
        parentNode = parentNode.spouse!;
      }

      if (!parentNode.children.any((c) => c.member.id == node.member.id)) {
        parentNode.children.add(node);
      }
    }

    // ── 5. Build generation buckets ───────────────────────────────────────
    final Map<int, List<TreeNode>> genMap = {};
    for (final n in nodes.values) {
      genMap.putIfAbsent(n.generation, () => []).add(n);
    }
    final sortedGens = genMap.keys.toList()..sort();

    // ── 6. Assign Y per generation ────────────────────────────────────────
    for (final gen in sortedGens) {
      final y = kPadY + gen * (kCardH + kVGap);
      for (final n in genMap[gen]!) {
        n.y = y;
      }
    }

    // ── 7. Compute X recursively ──────────────────────────────────────────
    final positions = <String, Offset>{};

    double subtreeWidth(TreeNode n) {
      final unitW = kCardW + (n.spouse != null ? kSpouseGap + kCardW : 0.0);
      if (n.children.isEmpty) return unitW;
      double childW = 0;
      for (int i = 0; i < n.children.length; i++) {
        childW += subtreeWidth(n.children[i]);
        if (i > 0) childW += kHGap;
      }
      return childW > unitW ? childW : unitW;
    }

    void layoutNode(TreeNode n, double leftX) {
      final unitW  = kCardW + (n.spouse != null ? kSpouseGap + kCardW : 0.0);
      double childW = 0;
      for (int i = 0; i < n.children.length; i++) {
        childW += subtreeWidth(n.children[i]);
        if (i > 0) childW += kHGap;
      }

      double nodeX;
      double childStartX;

      if (childW > unitW) {
        nodeX      = leftX + (childW - unitW) / 2;
        childStartX = leftX;
      } else {
        nodeX      = leftX;
        childStartX = leftX + (unitW - childW) / 2;
      }

      n.x = nodeX;
      positions[n.member.id] = Offset(nodeX, n.y);

      if (n.spouse != null) {
        final spouseX = nodeX + kCardW + kSpouseGap;
        n.spouse!.x = spouseX;
        positions[n.spouse!.member.id] = Offset(spouseX, n.spouse!.y);
      }

      double curX = childStartX;
      for (final child in n.children) {
        layoutNode(child, curX);
        curX += subtreeWidth(child) + kHGap;
      }
    }

    // Collect primary roots (gen 0, left node or single)
    final primaryRoots    = <TreeNode>[];
    final Set<String> seen = {};

    for (final node in nodes.values) {
      if (node.generation != 0) continue;
      if (seen.contains(node.member.id)) continue;
      if (!node.isLeftNode && node.spouse != null) continue; // right side — skip

      primaryRoots.add(node);
      seen.add(node.member.id);
      if (node.spouse != null) seen.add(node.spouse!.member.id);
    }

    double curX = kPadX;
    for (final root in primaryRoots) {
      layoutNode(root, curX);
      curX += subtreeWidth(root) + kHGap;
    }

    return positions;
  }
}