import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';

/// Glifi disponibili nel set di icone custom "Pulse" — sostituirà
/// `CupertinoIcons` nell'app (vedi CLAUDE.md, redesign Pulse). Altri glifi
/// verranno aggiunti nelle fasi successive quando serviranno a una
/// schermata specifica.
enum PulseIconGlyph {
  search,
  close,
  chevronBack,
  chevronForward,
  chevronDown,
  edit,
  delete,
  add,
  checkmark,
  document,
  calendar,
  settings,
  archive,
  chart,
  filter,
  cycle,
}

/// Icona vettoriale custom, disegnata con `CustomPainter` invece che con
/// glifi da font (`CupertinoIcons`): stroke spesso e geometria semplice,
/// coerente con il linguaggio visivo bold/geometrico di Pulse.
class PulseIcon extends StatelessWidget {
  final PulseIconGlyph glyph;
  final double size;
  final Color? color;

  const PulseIcon({
    super.key,
    required this.glyph,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ??
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PulseIconPainter(glyph: glyph, color: resolvedColor),
      ),
    );
  }
}

class _PulseIconPainter extends CustomPainter {
  final PulseIconGlyph glyph;
  final Color color;

  _PulseIconPainter({required this.glyph, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;

    switch (glyph) {
      case PulseIconGlyph.search:
        final radius = w * 0.28;
        final center = Offset(w * 0.42, h * 0.42);
        canvas.drawCircle(center, radius, stroke);
        canvas.drawLine(
          Offset(
            center.dx + radius * 0.72,
            center.dy + radius * 0.72,
          ),
          Offset(w * 0.82, h * 0.82),
          stroke,
        );
        break;

      case PulseIconGlyph.close:
        canvas.drawLine(
          Offset(w * 0.22, h * 0.22),
          Offset(w * 0.78, h * 0.78),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.78, h * 0.22),
          Offset(w * 0.22, h * 0.78),
          stroke,
        );
        break;

      case PulseIconGlyph.chevronBack:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.62, h * 0.22)
            ..lineTo(w * 0.34, h * 0.5)
            ..lineTo(w * 0.62, h * 0.78),
          stroke,
        );
        break;

      case PulseIconGlyph.chevronForward:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.38, h * 0.22)
            ..lineTo(w * 0.66, h * 0.5)
            ..lineTo(w * 0.38, h * 0.78),
          stroke,
        );
        break;

      case PulseIconGlyph.chevronDown:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.22, h * 0.38)
            ..lineTo(w * 0.5, h * 0.66)
            ..lineTo(w * 0.78, h * 0.38),
          stroke,
        );
        break;

      case PulseIconGlyph.edit:
        // Matita solo contorno (vuota), ingrandita nel box con tratto
        // dedicato più spesso per reggere il peso del testo nei chip.
        final body = Path()
          ..moveTo(w * 0.14, h * 0.86)
          ..lineTo(w * 0.20, h * 0.60)
          ..lineTo(w * 0.62, h * 0.18)
          ..lineTo(w * 0.82, h * 0.38)
          ..lineTo(w * 0.40, h * 0.80)
          ..close();
        canvas.drawPath(
          body,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = size.shortestSide * 0.11
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
        break;

      case PulseIconGlyph.delete:
        canvas.drawLine(
          Offset(w * 0.24, h * 0.3),
          Offset(w * 0.76, h * 0.3),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTRB(w * 0.32, h * 0.3, w * 0.68, h * 0.82),
            Radius.circular(w * 0.05),
          ),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.42, h * 0.2),
          Offset(w * 0.58, h * 0.2),
          stroke,
        );
        break;

      case PulseIconGlyph.add:
        canvas.drawLine(
          Offset(w * 0.5, h * 0.2),
          Offset(w * 0.5, h * 0.8),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.2, h * 0.5),
          Offset(w * 0.8, h * 0.5),
          stroke,
        );
        break;

      case PulseIconGlyph.checkmark:
        canvas.drawPath(
          Path()
            ..moveTo(w * 0.2, h * 0.52)
            ..lineTo(w * 0.42, h * 0.74)
            ..lineTo(w * 0.8, h * 0.28),
          stroke,
        );
        break;

      case PulseIconGlyph.document:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.26, h * 0.14, w * 0.48, h * 0.72),
            Radius.circular(w * 0.06),
          ),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.38, h * 0.42),
          Offset(w * 0.62, h * 0.42),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.38, h * 0.58),
          Offset(w * 0.62, h * 0.58),
          stroke,
        );
        break;

      case PulseIconGlyph.calendar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.18, h * 0.24, w * 0.64, h * 0.58),
            Radius.circular(w * 0.06),
          ),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.18, h * 0.4),
          Offset(w * 0.82, h * 0.4),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.34, h * 0.16),
          Offset(w * 0.34, h * 0.3),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.66, h * 0.16),
          Offset(w * 0.66, h * 0.3),
          stroke,
        );
        break;

      case PulseIconGlyph.settings:
        final center = Offset(w * 0.5, h * 0.5);
        canvas.drawCircle(center, w * 0.14, stroke);
        for (var i = 0; i < 6; i++) {
          final angle = (i / 6) * 2 * math.pi;
          final inner = Offset(
            center.dx + w * 0.2 * math.cos(angle),
            center.dy + w * 0.2 * math.sin(angle),
          );
          final outer = Offset(
            center.dx + w * 0.34 * math.cos(angle),
            center.dy + w * 0.34 * math.sin(angle),
          );
          canvas.drawLine(inner, outer, stroke);
        }
        break;

      case PulseIconGlyph.archive:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.16, h * 0.18, w * 0.68, h * 0.16),
            Radius.circular(w * 0.04),
          ),
          stroke,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(w * 0.2, h * 0.36, w * 0.6, h * 0.46),
            Radius.circular(w * 0.05),
          ),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.4, h * 0.58),
          Offset(w * 0.6, h * 0.58),
          stroke,
        );
        break;

      case PulseIconGlyph.filter:
        // Tre linee orizzontali di larghezza decrescente, centrate, stile
        // "sliders/filtro" — coordinate normalizzate su una griglia 16x16
        // (mockup: M2 3h12 / M4.5 8h7 / M7 13h2).
        canvas.drawLine(
          Offset(w * (2 / 16), h * (3 / 16)),
          Offset(w * (14 / 16), h * (3 / 16)),
          stroke,
        );
        canvas.drawLine(
          Offset(w * (4.5 / 16), h * (8 / 16)),
          Offset(w * (11.5 / 16), h * (8 / 16)),
          stroke,
        );
        canvas.drawLine(
          Offset(w * (7 / 16), h * (13 / 16)),
          Offset(w * (9 / 16), h * (13 / 16)),
          stroke,
        );
        break;

      case PulseIconGlyph.cycle:
        // Due archi opposti con freccia in punta — stile "cicla/confronta"
        // (sostituisce `CupertinoIcons.arrow_2_circlepath`), stessa tecnica
        // trigonometrica di `settings` sopra.
        final center = Offset(w * 0.5, h * 0.5);
        final radius = w * 0.26;
        final rect = Rect.fromCircle(center: center, radius: radius);
        const degToRad = math.pi / 180;
        final arcs = [
          (-160.0 * degToRad, 140.0 * degToRad),
          (20.0 * degToRad, 140.0 * degToRad),
        ];
        final arrowLen = w * 0.16;
        for (final arc in arcs) {
          final startAngle = arc.$1;
          final sweepAngle = arc.$2;
          canvas.drawArc(rect, startAngle, sweepAngle, false, stroke);

          final endAngle = startAngle + sweepAngle;
          final tip = Offset(
            center.dx + radius * math.cos(endAngle),
            center.dy + radius * math.sin(endAngle),
          );
          // Direzione di percorrenza dell'arco nel punto finale: puntando
          // avanti disegniamo una freccia che comunica il "ciclo" continuo.
          final tangentAngle = endAngle + math.pi / 2;
          final backAngle = tangentAngle + math.pi;
          canvas.drawLine(
            tip,
            Offset(
              tip.dx + arrowLen * math.cos(backAngle - 0.5),
              tip.dy + arrowLen * math.sin(backAngle - 0.5),
            ),
            stroke,
          );
          canvas.drawLine(
            tip,
            Offset(
              tip.dx + arrowLen * math.cos(backAngle + 0.5),
              tip.dy + arrowLen * math.sin(backAngle + 0.5),
            ),
            stroke,
          );
        }
        break;

      case PulseIconGlyph.chart:
        canvas.drawLine(
          Offset(w * 0.24, h * 0.8),
          Offset(w * 0.24, h * 0.5),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.5, h * 0.8),
          Offset(w * 0.5, h * 0.28),
          stroke,
        );
        canvas.drawLine(
          Offset(w * 0.76, h * 0.8),
          Offset(w * 0.76, h * 0.62),
          stroke,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PulseIconPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
