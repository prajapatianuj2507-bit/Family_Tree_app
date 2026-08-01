// lib/core/utils/tree_generation_helper.dart
//
// Shared BFS utility that assigns a generation number to every member.
// Used by MemberDashboard (for grouped list) and can be reused by TreeLayout.
// Generation 0 = founders (no known parents in the family).

import '../../models/member_model.dart';

class TreeGenerationHelper {
  TreeGenerationHelper._();

  /// Returns a map of memberId → generation (0-based).
  static Map<String, int> compute(List<MemberModel> members) {
    if (members.isEmpty) return {};

    final byId = <String, MemberModel>{for (final m in members) m.id: m};
    final gen  = <String, int>{};

    // Roots = members with no father AND no mother in this family
    final roots = members.where((m) {
      final hasFather = m.fatherId != null && byId.containsKey(m.fatherId);
      final hasMother = m.motherId != null && byId.containsKey(m.motherId);
      return !hasFather && !hasMother;
    }).toList();

    if (roots.isEmpty && members.isNotEmpty) {
      gen[members.first.id] = 0;
    }

    final queue = <MapEntry<String, int>>[
      for (final r in roots) MapEntry(r.id, 0),
    ];

    while (queue.isNotEmpty) {
      final e   = queue.removeAt(0);
      final id  = e.key;
      final g   = e.value;
      if (!byId.containsKey(id)) continue;
      // Always take the maximum depth (handles re-marriages / diamonds)
      if ((gen[id] ?? -1) < g) {
        gen[id] = g;
        for (final m in members) {
          if (m.fatherId == id || m.motherId == id) {
            queue.add(MapEntry(m.id, g + 1));
          }
        }
      }
    }

    // Sync spouses to same generation (take max)
    bool changed = true;
    while (changed) {
      changed = false;
      for (final m in members) {
        if (m.spouseId == null || !byId.containsKey(m.spouseId)) continue;
        final gA = gen[m.id]       ?? 0;
        final gB = gen[m.spouseId] ?? 0;
        final mx = gA > gB ? gA : gB;
        if (gen[m.id] != mx)       { gen[m.id]       = mx; changed = true; }
        if (gen[m.spouseId] != mx) { gen[m.spouseId!] = mx; changed = true; }
      }
    }

    // Fallback for any orphan not reached by BFS
    for (final m in members) {
      gen.putIfAbsent(m.id, () => 0);
    }

    return gen;
  }
}