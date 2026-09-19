import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'pulse_icon.dart';
import 'pulse_surface.dart';

/// Hero card in cima al dettaglio/form busta paga: mese, badge di stato e
/// netto in massima evidenza. In modalità modifica il mese/tipo sono
/// tap-to-edit (aprono i picker del chiamante); il badge di stato resta
/// sempre di sola lettura, non è modificabile direttamente. Il netto è
/// sempre un valore di sola lettura (derivato da lordo meno trattenute, mai
/// un campo editabile diretto).
///
/// Layout: la prima riga mostra il periodo (`periodoLabel`, es. "Luglio
/// 2026" o "14esima 2026" — il tipo, quando non è "Mensile", è già incluso
/// nel testo del periodo lato chiamante) con il badge di stato a destra. Il
/// testo del tipo non è mai mostrato separatamente accanto al periodo (per
/// ogni tipo, non solo "Mensile": mostrarlo di nuovo sarebbe sempre
/// ridondante col titolo). In modalità modifica (`onTapTipo != null`)
/// l'affordance di tap per cambiare tipo resta comunque raggiungibile per
/// qualunque tipo: al posto del testo compare solo la chevron tappabile,
/// mai testo. Sotto, una riga a due
/// colonne
/// centrate separate da un divisore verticale sottile (stesso stile di
/// `BustaPagaStatRow`) mostra il Lordo (sinistra, sempre di sola lettura — è
/// un valore derivato da `competenze`, mai un campo editabile diretto, vedi
/// CLAUDE.md) e il Netto (destra, il valore "hero" vero e proprio, anch'esso
/// sempre derivato/di sola lettura). Entrambe le colonne hanno la stessa
/// struttura (etichetta sopra, valore sotto); Lordo e Netto sono
/// visivamente identici in tutto (stesso stile `AppTextStyles.pulseDisplay`,
/// colore `pulseTextPrimary`) — nessuna differenziazione tra i due, si
/// distinguono solo tramite l'etichetta sopra.
///
/// Non richiede un `BustaPaga` intero: solo `isConfermato` per il badge
/// (il form di import, che non ha ancora una busta paga salvata, può così
/// passare `isConfermato: false` senza fabbricare un modello fittizio),
/// `lordoDisplay` e `nettoDisplay` per i due valori — già formattati
/// COMPLETI di simbolo "€" e segno (`formatEuroConSegno` lato chiamante,
/// vedi `lib/utils/busta_paga_formatting.dart`): questo widget si limita a
/// mostrarli così come arrivano, senza anteporre un proprio "€ " fisso. Un
/// prefisso "€ " fisso qui produrrebbe un doppio segno per i valori
/// negativi (es. "€ -1.411,00" invece di "− € 1.411,00") — sia
/// `computeNetto` che `computeLordo` possono risultare negativi per
/// costruzione (trattenute superiori al lordo, storni/conguagli), non è
/// un caso ipotetico — bug reale corretto qui, non un'ipotesi.
class BustaPagaHeroCard extends StatelessWidget {
  final bool isConfermato;
  final String periodoLabel;
  final String lordoDisplay;
  final String nettoDisplay;
  final VoidCallback? onTapPeriodo;
  final VoidCallback? onTapTipo;

  const BustaPagaHeroCard({
    super.key,
    required this.isConfermato,
    required this.periodoLabel,
    required this.lordoDisplay,
    required this.nettoDisplay,
    this.onTapPeriodo,
    this.onTapTipo,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    final separator = textSecondary.withValues(alpha: 0.3);
    final amountValueStyle =
        AppTextStyles.pulseDisplay.copyWith(color: textPrimary);

    final labelStyle = AppTextStyles.pulseLabel.copyWith(color: textSecondary);

    return PulseSurface(
      borderRadius: AppRadius.pulse,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: onTapPeriodo == null
                          ? Text(
                              periodoLabel,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: AppTextStyles.pulseDisplay.copyWith(
                                color: textPrimary,
                              ),
                            )
                          : Semantics(
                              label: 'Cambia periodo',
                              button: true,
                              child: GestureDetector(
                                onTap: onTapPeriodo,
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        periodoLabel,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                        style: AppTextStyles.pulseDisplay
                                            .copyWith(color: textPrimary),
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    PulseIcon(
                                        glyph: PulseIconGlyph.chevronDown,
                                        size: 16,
                                        color: textSecondary),
                                  ],
                                ),
                              ),
                            ),
                    ),
                    if (onTapTipo != null)
                      Semantics(
                        label: 'Cambia tipo busta paga',
                        button: true,
                        child: GestureDetector(
                          onTap: onTapTipo,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs),
                            child: PulseIcon(
                                glyph: PulseIconGlyph.chevronDown,
                                size: 14,
                                color: textSecondary),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _StatoBadge(isConfermato: isConfermato),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _AmountsRow(
            lordoDisplay: lordoDisplay,
            nettoDisplay: nettoDisplay,
            labelStyle: labelStyle,
            valueStyle: amountValueStyle,
            separatorColor: separator,
          ),
        ],
      ),
    );
  }
}

/// Riga Lordo/Netto della hero card: calcola UN SOLO fattore di scala
/// condiviso tra i due valori (invece di due `FittedBox` indipendenti, uno
/// per Lordo e uno per Netto), così i due restano sempre alla stessa
/// dimensione di font — requisito non negoziabile del widget (vedi doc sopra
/// su `BustaPagaHeroCard`). Con due `FittedBox` separati, stringhe di
/// lunghezza diversa (es. un Netto negativo col prefisso "− €" più lungo del
/// Lordo) venivano scalate ciascuna col proprio fattore, risultando in due
/// dimensioni di font diverse tra Lordo e Netto — bug reale corretto qui, non
/// un'ipotesi.
///
/// Il fattore è calcolato misurando la larghezza naturale di entrambe le
/// stringhe con `TextPainter` (stesso `valueStyle`, stesso `textScaler` di
/// sistema per rispettare l'accessibilità) e confrontandola con la larghezza
/// disponibile per singola colonna (metà della larghezza totale, al netto del
/// divisore centrale): si usa la stringa PIÙ LARGA delle due per calcolare lo
/// scala, applicato poi a ENTRAMBE — mai un fattore per stringa. Nel caso
/// comune (entrambi i valori di lunghezza normale, scala 1.0) il layout
/// risultante è identico a prima del fix: il fix è correttivo solo nel caso
/// limite in cui uno dei due valori non entrerebbe nella propria metà a
/// dimensione naturale.
class _AmountsRow extends StatelessWidget {
  final String lordoDisplay;
  final String nettoDisplay;
  final TextStyle labelStyle;
  final TextStyle valueStyle;
  final Color separatorColor;

  const _AmountsRow({
    required this.lordoDisplay,
    required this.nettoDisplay,
    required this.labelStyle,
    required this.valueStyle,
    required this.separatorColor,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const separatorSpace = 0.5 + AppSpacing.sm * 2;
        final columnWidth = ((constraints.maxWidth - separatorSpace) / 2).clamp(
          0.0,
          double.infinity,
        );
        final scale = _sharedScale(context, columnWidth);
        final scaledValueStyle = valueStyle.copyWith(
          fontSize: (valueStyle.fontSize ?? 20) * scale,
        );
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _AmountColumn(
                  label: 'Lordo',
                  value: lordoDisplay,
                  labelStyle: labelStyle,
                  valueStyle: scaledValueStyle,
                ),
              ),
              Container(
                width: 0.5,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                color: separatorColor,
              ),
              Expanded(
                child: _AmountColumn(
                  label: 'Netto',
                  value: nettoDisplay,
                  labelStyle: labelStyle,
                  valueStyle: scaledValueStyle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _sharedScale(BuildContext context, double columnWidth) {
    final textScaler = MediaQuery.textScalerOf(context);
    double naturalWidth(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: valueStyle),
        textDirection: Directionality.of(context),
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    final widest = [
      naturalWidth(lordoDisplay),
      naturalWidth(nettoDisplay),
    ].reduce((a, b) => a > b ? a : b);
    if (widest <= 0 || columnWidth <= 0) return 1.0;
    return (columnWidth / widest).clamp(0.0, 1.0);
  }
}

/// Singola colonna etichetta+valore (Lordo o Netto), stile condiviso tramite
/// [valueStyle] già scalato da [_AmountsRow].
class _AmountColumn extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle labelStyle;
  final TextStyle valueStyle;

  const _AmountColumn({
    required this.label,
    required this.value,
    required this.labelStyle,
    required this.valueStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, textAlign: TextAlign.center, style: labelStyle),
        const SizedBox(height: 2),
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: valueStyle,
        ),
      ],
    );
  }
}

/// Badge di stato (Confermato/Da confermare): sola visualizzazione, aspetto
/// sempre guidato dal chiamante (`isConfermato`, a sua volta derivato dallo
/// stato letto dal provider, mai da variabili locali di editing). Colori:
/// riempimento pieno `pulsePositive`/`pulseNegative`, testo
/// `pulseOnPositive`/`pulseOnNegative` — stesso pattern del badge di stato
/// nell'Archivio (`BustaPagaSummaryHero`/`BustaPagaListItem`). Aggiunge solo
/// un piccolo "pop" a molla sulla scala quando [isConfermato] cambia rispetto
/// al build precedente — mai al primo mount.
class _StatoBadge extends StatefulWidget {
  final bool isConfermato;

  const _StatoBadge({required this.isConfermato});

  @override
  State<_StatoBadge> createState() => _StatoBadgeState();
}

class _StatoBadgeState extends State<_StatoBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.15)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(_StatoBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isConfermato != widget.isConfermato) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeFill = CupertinoDynamicColor.resolve(
      widget.isConfermato ? AppColors.pulsePositive : AppColors.pulseNegative,
      context,
    );
    final badgeText = CupertinoDynamicColor.resolve(
      widget.isConfermato
          ? AppColors.pulseOnPositive
          : AppColors.pulseOnNegative,
      context,
    );
    return ScaleTransition(
      scale: _scale,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: badgeFill,
          borderRadius: BorderRadius.circular(AppRadius.pulseSmall),
        ),
        child: Text(
          widget.isConfermato ? 'Confermato' : 'Da confermare',
          style: AppTextStyles.pulseLabel.copyWith(color: badgeText),
        ),
      ),
    );
  }
}
