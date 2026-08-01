// lib/views/family/tree_painter.dart
// ─────────────────────────────────────────────────────────────
// Phase 3.4 – CustomPainter for family-tree connection lines (v2)
//
// Line types:
//   spouse        – short horizontal bar connecting a couple
//   dropBar       – vertical drop from couple midpoint to a
//                   horizontal collector bar
//   collector     – horizontal bar spanning all children
//   childRise     – short vertical rise from collector to each child
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

enum LineType {
  spouse,       // horizontal line between couple cards
  dropBar,      // vertical from couple bottom-centre to collector
  collector,    // horizontal spanning children
  childRise,    // vertical from collector to child top
}

class LineSegment {
  final Offset start;
  final Offset end;
  final LineType type;
  const LineSegment({required this.start, required this.end, required this.type});
}

class TreePainter extends CustomPainter {
  final List<LineSegment> lines;

  // Colours
  static const Color _spouseColor      = Color(0xFFE67E22);  // warm orange
  static const Color _connectionColor  = Color(0xFF5D6D7E);  // muted blue-grey

  const TreePainter({required this.lines});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint spousePaint = Paint()
      ..color = _spouseColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Paint connPaint = Paint()
      ..color = _connectionColor.withOpacity(0.55)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Draw connection lines first (under spouse lines)
    for (final seg in lines) {
      if (seg.type == LineType.spouse) continue;
      canvas.drawLine(seg.start, seg.end, connPaint);
    }

    // Draw spouse lines on top
    for (final seg in lines) {
      if (seg.type != LineType.spouse) continue;
      // Draw a small heart/diamond at midpoint for polish
      final mid = Offset(
        (seg.start.dx + seg.end.dx) / 2,
        seg.start.dy,
      );
      canvas.drawLine(seg.start, Offset(mid.dx - 6, mid.dy), spousePaint);
      canvas.drawLine(Offset(mid.dx + 6, mid.dy), seg.end, spousePaint);

      // Small diamond at midpoint
      final diamondPaint = Paint()
        ..color = _spouseColor
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(mid.dx, mid.dy - 5)
        ..lineTo(mid.dx + 5, mid.dy)
        ..lineTo(mid.dx, mid.dy + 5)
        ..lineTo(mid.dx - 5, mid.dy)
        ..close();
      canvas.drawPath(path, diamondPaint);
    }
  }

  @override
  bool shouldRepaint(covariant TreePainter old) => old.lines != lines;
}