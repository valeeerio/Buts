import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'pulse_icon.dart';
import 'spring_button.dart';

/// Chip piatto (icona + etichetta), senza superficie di vetro: componente
/// condiviso tra la barra "Conferma/Modifica"/"Salva/Annulla" del dettaglio
/// e del form busta paga, i popup di `AppAlertDialog` e (in passato) i
/// segmenti Archivio/Statistiche della sidecar.
///
/// [filled] controlla il riempimento a colore pieno (bassa opacità) più
/// bordo arrotondato: `true` per un'azione sempre "premuta" (es. i due
/// bottoni del dettaglio), `false` per uno stato non selezionato (es. il
/// tab non attivo nella sidecar), che resta solo icona+testo colorati senza
/// sfondo.
///
/// [primary] attiva il trattamento "azione primaria" (Modifica/Salva/
/// Conferma nella barra flottante): riempimento a **colore pieno** con
/// [color] (il colore passato dal chiamante, es. `AppColors.pulseAccent`
/// ciano per Modifica/Salva o `AppColors.pulsePositive` verde per Conferma),
/// testo/icona in [onColor] — di default `AppColors.pulseOnAccent`, che
/// regge bene solo il riempimento ciano; se [color] è
/// `AppColors.pulsePositive` (o un altro colore che non sia il ciano
/// standard) passare esplicitamente `onColor: AppColors.pulseOnPositive` (o
/// il token di contrasto corretto per quel colore) per evitare testo poco
/// leggibile. Ignora [filled] per il riempimento quando `true` (resta
/// inutilizzato per quella chiamata). Riservato alle CTA primarie della
/// barra flottante — NON i tab della sidecar né "Annulla", che restano sul
/// trattamento piatto esistente per gerarchia (primario ricco, secondario
/// sobrio).
///
/// Storia: il riempimento era in origine un gradiente viola→ciano
/// (`pulseSecondaryGlow`→`pulseAccent`, stesso trattamento del blocco Netto
/// in `BustaPagaSummaryHero`), ma produceva una rima scura visibile agli
/// angoli arrotondati nel rendering Impeller su device reale — persistita
/// dopo più tentativi di correzione (rimozione del `boxShadow`, `ClipRRect`
/// esplicito attorno al gradiente). Sostituito con colore pieno
/// `AppColors.pulseAccent`, stessa tecnica del bottone "+" circolare in
/// `_BustePagaNavBar` (`lib/screens/buste_paga/buste_paga_section_screen.
/// dart`, `_plusButton`): un solo `DecoratedBox`/`Container` con `color`
/// pieno, nessun clip esplicito, nessun `boxShadow` — quell'elemento non ha
/// mai mostrato l'artefatto, quindi qui si replica la stessa struttura
/// invece di continuare a correggere il gradiente.
///
/// Contrasto testo: `pulseOnAccent` (quasi-nero in entrambi i temi) regge
/// benissimo (~10:1) contro `pulseAccent` (ciano chiaro) risolto sia in dark
/// sia in light — stesso estremo già validato per il gradiente, quindi
/// contrasto già sicuro in entrambe le modalità senza bisogno di ulteriori
/// aggiustamenti.
/// `pulseOnPositive` (quasi-nero in entrambi i temi) regge 10.73:1 in dark e
/// 5.11:1 in light contro `pulsePositive` (verde), vedi
/// `lib/theme/app_colors.dart` — usato per il chip "Conferma".
class FlatChipButton extends StatelessWidget {
  final IconData? icon;

  /// Alternativa a [icon] per usare un glifo del set custom Pulse
  /// (`PulseIcon`/`PulseIconGlyph`) al posto di un `IconData`
  /// (`CupertinoIcons`/Material) — coerente con la regola di stile "niente
  /// `CupertinoIcons`, ogni icona è un `CustomPainter`" (vedi CLAUDE.md).
  /// Se presente ha priorità su [icon]. Il colore è sempre quello risolto
  /// del chip (stato pieno/non pieno, primario/secondario), non quello
  /// eventualmente passato al costruttore di [PulseIconGlyph].
  final PulseIconGlyph? pulseGlyph;
  final String label;
  final Color color;
  final Color? onColor;
  final bool filled;
  final bool primary;
  final VoidCallback onPressed;

  /// Raggio degli angoli del chip. Di default (`null`) arrotonda tutti e 4
  /// gli angoli con `AppRadius.glassSmall`. Quando il chip è affiancato a un
  /// altro dentro una barra flottante con gap centrale (es. Salva/Annulla,
  /// Conferma/Modifica), i due chip restano forme indipendenti con tutti gli
  /// angoli arrotondati — nessun raggio parziale da coordinare. Se il
  /// chiamante passa comunque un valore esplicito, deve combaciare con quello
  /// usato dal `ClipRRect` esterno che avvolge il chip, unica fonte di
  /// verità.
  final BorderRadius? borderRadius;

  const FlatChipButton({
    super.key,
    this.icon,
    this.pulseGlyph,
    required this.label,
    required this.color,
    required this.onPressed,
    this.onColor,
    this.filled = true,
    this.primary = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return SpringButton(
      onPressed: onPressed,
      child: primary ? _buildPrimary(context) : _buildFlat(context),
    );
  }

  Widget _buildFlat(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.mdMinus),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.16) : null,
        borderRadius:
            borderRadius ?? BorderRadius.circular(AppRadius.glassSmall),
        // Bordo sottile per i secondari (es. "Annulla"): senza fill a
        // gradiente il chip risultava "dimenticato" accanto al primario ora
        // molto più ricco — un contorno appena percettibile basta a dargli
        // rifinitura senza competere in vivacità, mantenendo la gerarchia
        // primario forte / secondario discreto.
        border: filled
            ? Border.all(color: color.withValues(alpha: 0.28), width: 1)
            : null,
      ),
      child: _content(color),
    );
  }

  Widget _buildPrimary(BuildContext context) {
    final fill = CupertinoDynamicColor.resolve(color, context);
    final onFill = CupertinoDynamicColor.resolve(
      onColor ?? AppColors.pulseOnAccent,
      context,
    );
    // Colore pieno, stessa tecnica del bottone "+" circolare in
    // `_BustePagaNavBar._plusButton` — vedi doc della classe: un solo
    // `DecoratedBox` con `color` pieno, nessun `ClipRRect`, nessun
    // `boxShadow`. Sostituisce il precedente riempimento a gradiente che
    // produceva una rima scura agli angoli.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius:
            borderRadius ?? BorderRadius.circular(AppRadius.glassSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.mdMinus),
        child: _content(onFill),
      ),
    );
  }

  Widget _content(Color contentColor) {
    // `SizedBox(width: infinity)` riempie la larghezza massima ricevuta (tutti
    // gli usi sono in `Expanded`/vincoli limitati); `FittedBox` riduce solo se
    // il contenuto non ci sta, altrimenti resta centrato a dimensione naturale.
    return SizedBox(
      width: double.infinity,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (pulseGlyph != null) ...[
              PulseIcon(glyph: pulseGlyph!, size: 22, color: contentColor),
              const SizedBox(width: AppSpacing.xs),
            ] else if (icon != null) ...[
              Icon(icon, size: 22, color: contentColor),
              const SizedBox(width: AppSpacing.xs),
            ],
            Text(
              label,
              style: AppTextStyles.cardAmount.copyWith(color: contentColor),
            ),
          ],
        ),
      ),
    );
  }
}
