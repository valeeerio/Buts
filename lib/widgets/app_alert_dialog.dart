import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'flat_chip_button.dart';
import 'pulse_icon.dart';

/// Un bottone di `AppAlertDialog`: stesso identico componente
/// (`FlatChipButton`, icona + testo, riempimento pieno) dei segmenti della
/// sidecar e della barra Conferma/Modifica del dettaglio busta paga —
/// [icon] è opzionale solo per compatibilità, ogni punto di chiamata dovrebbe
/// valorizzarlo per restare coerente con quello stile. [onPressed] fa
/// interamente carico di sé del `Navigator.pop`/eventuale side effect, stesso
/// contratto di `CupertinoDialogAction.onPressed` che sostituisce.
class AppAlertAction {
  final String label;
  final Color color;
  final IconData? icon;

  /// Alternativa a [icon] per usare un glifo del set custom Pulse
  /// (`PulseIcon`/`PulseIconGlyph`) al posto di un `IconData`
  /// (`CupertinoIcons`) — stessa logica di priorità di
  /// `FlatChipButton.pulseGlyph`: se presente ha priorità su [icon].
  final PulseIconGlyph? pulseGlyph;
  final VoidCallback onPressed;

  const AppAlertAction({
    required this.label,
    required this.color,
    this.icon,
    this.pulseGlyph,
    required this.onPressed,
  });
}

/// Popup di conferma/errore dell'app — ridisegnato da zero (2026-08-01) per
/// essere un'estensione visiva della sidecar/barra Conferma-Modifica invece
/// di una card in stile Liquid Glass: **nessun vetro/`BackdropFilter`**, solo
/// una superficie piatta a colore pieno (`AppColors.pulseSurface`, coerente
/// con la direzione "Pulse") con un'ombra leggera per staccarla dal barrier
/// sottostante, e bottoni `FlatChipButton` con icona — stesso identico
/// linguaggio dei chip della sidecar (icona + testo, riempimento pieno
/// colorato). Titolo e messaggio centrati (stile alert nativo iOS).
class AppAlertDialog extends StatelessWidget {
  final String title;
  final String? message;
  final List<AppAlertAction> actions;

  /// Illustrazione opzionale (`CustomIllustration`) mostrata sopra il
  /// titolo, es. per l'onboarding dei promemoria. Additivo: se `null` (il
  /// caso di ogni chiamata esistente), l'aspetto del popup resta identico a
  /// prima.
  final Widget? illustration;

  const AppAlertDialog({
    super.key,
    required this.title,
    this.message,
    required this.actions,
    this.illustration,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    final surface =
        CupertinoDynamicColor.resolve(AppColors.pulseSurface, context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.pulse),
              boxShadow: [
                BoxShadow(
                  color: CupertinoColors.black.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (illustration != null) ...[
                    illustration!,
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.pulseBodyEmphasis.copyWith(
                      color: textPrimary,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message!,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.pulseBody.copyWith(
                        color: textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: FlatChipButton(
                            icon: actions[i].icon,
                            pulseGlyph: actions[i].pulseGlyph,
                            label: actions[i].label,
                            color: actions[i].color,
                            onPressed: actions[i].onPressed,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mostra un `AppAlertDialog`. Nessuna scala/molla: solo un fade secco,
/// stessa `Animation`/curva condivisa tra barrier e contenuto (sincronia
/// strutturale, non approssimata — il barrier è disegnato a mano qui invece
/// di affidarsi a quello di sistema, che usa `Curves.ease` fisso non
/// configurabile e non sincronizzabile con la curva del contenuto).
Future<T?> showAppAlertDialog<T>({
  required BuildContext context,
  required String title,
  String? message,
  required List<AppAlertAction> actions,
  Widget? illustration,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: false,
    barrierLabel: title,
    barrierColor: const Color(0x00000000),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (context, animation, secondaryAnimation) {
      return AppAlertDialog(
        title: title,
        message: message,
        actions: actions,
        illustration: illustration,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return _AlertTransition(animation: animation, child: child);
    },
  );
}

/// Isola la costruzione della `CurvedAnimation` di fade dal `transitionBuilder`
/// di `showGeneralDialog`, che viene richiamato ad ogni frame della
/// transizione (~200ms): come `StatefulWidget`, `_AlertTransitionState`
/// viene creato una sola volta (stesso `Element` riusato finché tipo/
/// posizione nell'albero restano gli stessi) e la `late final` qui sotto
/// costruisce la curva una sola volta invece che ad ogni frame.
class _AlertTransition extends StatefulWidget {
  final Animation<double> animation;
  final Widget child;

  const _AlertTransition({required this.animation, required this.child});

  @override
  State<_AlertTransition> createState() => _AlertTransitionState();
}

class _AlertTransitionState extends State<_AlertTransition> {
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedBarrierColor =
        CupertinoDynamicColor.resolve(AppColors.alertBarrier, context);
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _fade,
            child: ColoredBox(color: resolvedBarrierColor),
          ),
        ),
        FadeTransition(opacity: _fade, child: widget.child),
      ],
    );
  }
}
