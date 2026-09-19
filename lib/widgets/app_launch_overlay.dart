import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../theme/app_colors.dart';

/// Animazione di avvio ("Apertura"): l'anello dell'icona, fermo come nel
/// launch screen nativo, si chiude e si espande dissolvendosi sull'archivio.
///
/// Timeline (1500 ms): 0-250 ms fermo; 250-850 ms sweep 285° -> 360° con
/// rotazione del punto di partenza di 360°; 850-1500 ms raggio x7, tratto
/// x1.5, dissolvenza di anello e sfondo. Con `MediaQuery.disableAnimations`
/// dura solo 200 ms, come semplice dissolvenza dello sfondo.
///
/// Da mettere in uno `Stack` sopra il contenuto; il widget è già dentro un
/// [IgnorePointer]. [onDone] viene chiamato a fine animazione: il chiamante
/// rimuove l'overlay dall'albero.
class AppLaunchOverlay extends StatefulWidget {
  const AppLaunchOverlay({super.key, this.onDone, this.progress});

  final VoidCallback? onDone;

  /// Espone il progresso (0..1) dell'animazione, per animare il contenuto
  /// sottostante in sincrono (vedi [AppLaunchReveal]).
  final ValueNotifier<double>? progress;

  static const Duration duration = Duration(milliseconds: 1500);
  static const Duration reducedDuration = Duration(milliseconds: 200);

  @override
  State<AppLaunchOverlay> createState() => _AppLaunchOverlayState();
}

class _AppLaunchOverlayState extends State<AppLaunchOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppLaunchOverlay.duration,
    )..addListener(() {
        // Scala 0..1 della timeline completa; ridotta: il contenuto appare
        // in dissolvenza nello stesso arco dei 200 ms.
        widget.progress?.value =
            _reduced ? 0.6 + 0.3 * _controller.value : _controller.value;
      });
    _controller.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone?.call();
    });
  }

  double get _totalMs => _reduced ? 200 : 1500;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_reduced) _controller.duration = AppLaunchOverlay.reducedDuration;
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: LaunchRingPainter(
            ms: _controller.value * _totalMs,
            reduced: _reduced,
          ),
        ),
      ),
    );
  }
}

/// Dipinge sfondo + anello per l'istante [ms] (0..1500, o 0..200 se
/// [reduced]). Pubblico per poter essere ispezionato nei test.
class LaunchRingPainter extends CustomPainter {
  const LaunchRingPainter({required this.ms, this.reduced = false});

  final double ms;
  final bool reduced;

  static const double baseRadius = 44;
  static const double baseStroke = 8;
  static const double openSweepDeg = 285;

  static double _clamp01(double v) => v.clamp(0.0, 1.0);
  static double _eio(double p) {
    p = _clamp01(p);
    return p < .5 ? 4 * p * p * p : 1 - math.pow(-2 * p + 2, 3) / 2;
  }

  /// Sweep (gradi) all'istante [ms] della timeline completa.
  static double sweepAt(double ms) =>
      openSweepDeg + 75 * _eio((ms / 1000 - .25) / .6);

  @override
  void paint(Canvas canvas, Size size) {
    if (reduced) {
      final bgOp = 1 - _clamp01(ms / 200);
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AppColors.pulseBackground.withValues(alpha: bgOp),
      );
      return;
    }
    final s = ms / 1000;
    final p = _eio((s - .25) / .6);
    final sweep = (openSweepDeg + 75 * p) * math.pi / 180;
    final start = (-90 + 360 * p) * math.pi / 180;
    final q = _eio((s - .85) / (1.5 - .85));
    final r = baseRadius * (1 + 6 * q);
    final sw = baseStroke * (1 + .5 * q);
    final ringOp = 1 - _clamp01(q * 1.15);
    final bgOp = 1 - _clamp01(q * 1.6);

    if (bgOp > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = AppColors.pulseBackground.withValues(alpha: bgOp),
      );
    }
    if (ringOp <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = AppColors.brandRing.withValues(alpha: ringOp);
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    if (sweep >= 2 * math.pi - 0.002) {
      canvas.drawCircle(rect.center, r, paint);
    } else {
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(LaunchRingPainter old) =>
      old.ms != ms || old.reduced != reduced;
}

/// Progresso costante a 1.0 (animazione conclusa/assente): permette a
/// [AppLaunchReveal] di mantenere sempre la stessa struttura di widget, così
/// il figlio non viene rimontato a fine animazione.
class _ProgressCompleto implements ValueListenable<double> {
  const _ProgressCompleto();

  @override
  double get value => 1.0;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Anima il contenuto sottostante (archivio) in ingresso, in sincrono con
/// [progress] (vedi [AppLaunchOverlay.progress]): opacità 0->1 e salita di
/// 14 px (solo dissolvenza con `disableAnimations`), start 0.9 s, durata
/// 0.45 s, easeOutCubic. Con [progress] a `null` mostra il contenuto subito.
/// Finché il contenuto non è visibile ignora i tocchi. La struttura
/// dell'albero è identica con e senza [progress].
class AppLaunchReveal extends StatelessWidget {
  const AppLaunchReveal({
    super.key,
    required this.progress,
    required this.child,
    this.startSeconds = .9,
  });

  final ValueListenable<double>? progress;
  final Widget child;
  final double startSeconds;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ValueListenableBuilder<double>(
      valueListenable: progress ?? const _ProgressCompleto(),
      child: child,
      builder: (context, value, child) {
        final elapsed = value * 1.5;
        final t = ((elapsed - startSeconds) / .45).clamp(0.0, 1.0);
        final a = 1 - math.pow(1 - t, 3).toDouble();
        return IgnorePointer(
          ignoring: elapsed < startSeconds,
          child: Opacity(
            opacity: a,
            child: Transform.translate(
                offset: Offset(0, reduced ? 0 : 14 * (1 - a)), child: child),
          ),
        );
      },
    );
  }
}
