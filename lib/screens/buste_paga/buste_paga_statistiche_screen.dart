import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/busta_paga.dart';
import '../../providers/buste_paga_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/busta_paga_formatting.dart';
import '../../widgets/busta_paga_drilldown_sheet.dart';
import '../../widgets/period_year_month_picker.dart';
import '../../widgets/pulse_icon.dart';
import '../../widgets/pulse_surface.dart';
import '../../widgets/value_tile.dart';

/// Contenuto della tab "Statistiche" della sezione Buste Paga.
///
/// Redesign 2026-08-30 (approvato dall'utente su mockup, vedi CLAUDE.md):
/// 3 card, ciascuna con una vista "protagonista" (numeri grandi + area
/// chart con glow / anelli di progresso grandi / barre a gradiente) — stessa
/// logica di calcolo/aggregazione/filtro periodo di prima, solo
/// riorganizzazione visiva (eccezione consapevole: il blocco
/// Ferie/Permessi/Ex festività passa da un trend nel tempo a uno snapshot
/// dell'ultima busta paga nel periodo filtrato). Solo la card Netto/Lordo
/// mantiene la vecchia tabella Media/Minimo/Massimo/Totale dietro un link
/// "Dettagli" collassabile; le card Ferie/permessi/ex festività e
/// Straordinario per mese mostrano solo header/anelli o titolo/grafico,
/// senza dettagli aggiuntivi (rimossi in una revisione successiva, ridondanti
/// con la vista protagonista).
///
/// Palette: `pulseAccent` (ciano) resta il colore funzionale primario e
/// unico colore-dato dei 3 grafici. `pulseSecondaryGlow` (viola) resta usato
/// qui SOLO come metà del bordo decorativo esterno di `_ChartCard` — mai per
/// icone/testo/bottoni interattivi, coerente con CLAUDE.md. La card Netto
/// (Task 2, 2026-09-08) mostra una linea singola: il Lordo non è più una
/// serie/colonna della vista principale. Le barre Straordinario (Task 4,
/// 2026-09-08) sono un riempimento pieno ciano (niente più gradiente
/// viola→ciano né glow dietro la barra massima). Il confronto anno su anno
/// (Task 5, 2026-09-08) è stato rimosso il 2026-09-09 su richiesta esplicita
/// dell'utente: ridondante col preset dedicato "Anno precedente" del filtro
/// periodo (`PeriodFilterButton`), che permette già di guardare l'anno
/// scorso filtrando direttamente.
///
/// Grafici Netto e Straordinario di sola visualizzazione, nessun tap/
/// drill-down (rimosso di nuovo il 2026-09-10 su richiesta esplicita
/// dell'utente — "il tap sui grafici non mi piace per niente... eliminalo
/// del tutto" — dopo un primo tentativo con tooltip custom "Vedi dettaglio"
/// introdotto lo stesso giorno: entrambi gli approcci al tap sono stati
/// scartati, `lineTouchData`/`barTouchData` sono ora `enabled: false`). Gli
/// anelli Ferie/Permessi/Ex festività (Task 3, 2026-09-08) restano invece
/// monocromatici (stesso `pulseAccent` per tutti e 3, solo opacità
/// decrescente) e tappabili: è l'UNICA interazione a tocco rimasta in questa
/// schermata, apre `showBustaPagaDrilldown` sull'ultima busta paga del
/// periodo filtrato (unico punto da cui resta consultabile anche il Lordo,
/// non più mostrato nella card Netto).
class BustePagaStatisticheScreen extends ConsumerWidget {
  final ({DateTime start, DateTime end})? periodoFiltro;

  const BustePagaStatisticheScreen({super.key, this.periodoFiltro});

  // Dissolvenza in fondo allo scroll, stesso pattern di
  // BustePagaArchivioView ma con fadeHeight tarato a parte: il viewport qui
  // ha densità diversa (3 card ampie invece di righe fitte), vedi CLAUDE.md
  // sulla nota "non assumere lo stesso valore assoluto tra schermate".
  static const _fadeHeight = 90.0;

  // Netto: unica linea/area del grafico, colore funzionale primario
  // dell'app (`pulseAccent`, ciano) — niente più una seconda serie Lordo
  // (Task 2 del redesign 2026-09-08, vedi CLAUDE.md).
  static const _nettoColor = AppColors.pulseAccent;
  // Barre Straordinario: riempimento pieno ciano (Task 4 del redesign
  // 2026-09-08, vedi CLAUDE.md) — niente più gradiente viola→ciano né glow
  // dietro la barra massima, solo opacità ridotta per le barre non massime.
  static const _straordinarioColor = AppColors.pulseAccent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tutte = ref.watch(busteRepositoryProvider);
    final buste = tutte.where(bustaInclusaInStatistiche).toList();
    final sorted = [...buste]..sort((a, b) => a.periodo.compareTo(b.periodo));
    final filtro = periodoFiltro;
    final filtrati = filtro == null
        ? sorted
        : sorted
            .where((b) =>
                !b.periodo.isBefore(filtro.start) &&
                !b.periodo.isAfter(filtro.end))
            .toList();

    // Buste mensili "Da confermare" nel periodo selezionato (stesso filtro
    // di `filtrati`, criterio permissivo di [_bustaInclusaInRangePeriodo]
    // meno restrittivo di [bustaInclusaInStatistiche]): lo slider di periodo
    // sopra i grafici le include già (estende gli estremi min/max), ma i
    // grafici no — appena importate più buste paga in un colpo solo e prima
    // di confermarle, l'utente vedrebbe altrimenti uno slider popolato sopra
    // a tre card "Non ci sono dati" senza spiegazione, apparentemente un bug
    // di rendering. Passato a ogni grafico per un messaggio esplicito nello
    // stato vuoto (vedi [_NoDataMessage]) invece di quello generico.
    final busteNonConfermate = tutte
        .where((b) =>
            b.tipo == TipoBustaPaga.mensile &&
            b.statoVerifica == StatoVerificaBustaPaga.daConfermare &&
            (filtro == null ||
                (!b.periodo.isBefore(filtro.start) &&
                    !b.periodo.isAfter(filtro.end))))
        .length;

    // Fine a cui estendere i grafici Netto/Lordo e Straordinario oltre
    // l'ultima busta paga confermata nel periodo filtrato: di norma il mese
    // corrente reale, ma senza mai superare un filtro periodo più
    // restrittivo scelto esplicitamente dall'utente (in quel caso la
    // griglia si ferma comunque a `filtro.end`, comportamento invariato).
    // Il confronto va fatto contro l'ultima busta paga REALMENTE
    // disponibile (`sorted`, non filtrata), non contro oggi: il picker di
    // norma restituisce come estremo massimo proprio l'ultima busta paga
    // disponibile, non il mese corrente — usare `oggiNormalizzato` come
    // riferimento romperebbe l'estensione in quel caso comune, che non è
    // una restrizione deliberata dell'utente.
    final ultimoConfermato = sorted.isNotEmpty
        ? DateTime(sorted.last.periodo.year, sorted.last.periodo.month)
        : null;
    final oggiNormalizzato = DateTime(DateTime.now().year, DateTime.now().month);
    final restrizioneEsplicita = filtro != null &&
        ultimoConfermato != null &&
        filtro.end.isBefore(ultimoConfermato);
    final estendiFinoA =
        restrizioneEsplicita ? filtro.end : oggiNormalizzato;

    // Etichetta leggibile del periodo effettivo applicato, mostrata come
    // sottotitolo su ogni card (Task 6 del redesign 2026-09-08, vedi
    // CLAUDE.md) così l'effetto del filtro resta leggibile senza dover
    // riaprire il filtro per ricordarselo.
    final periodoFiltroLabel = filtro == null
        ? 'Tutto lo storico'
        : PeriodYearMonthPicker.formatRangeLabel(filtro.start, filtro.end);

    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final stop = 1 -
            (BustePagaStatisticheScreen._fadeHeight / rect.height)
                .clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            CupertinoColors.white,
            CupertinoColors.white,
            CupertinoColors.transparent,
          ],
          stops: [0.0, stop, 1.0],
        ).createShader(rect);
      },
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.lg,
              AppSpacing.screenHorizontal,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: _NettoCardSection(
                buste: filtrati,
                estendiFinoA: estendiFinoA,
                periodoFiltroLabel: periodoFiltroLabel,
                busteNonConfermate: busteNonConfermate,
                stats: _nettoStats(filtrati),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.md,
            ),
            sliver: SliverToBoxAdapter(
              child: _ChartCard(
                title: 'Ferie, permessi ed ex festività',
                subtitle: filtrati.isEmpty
                    ? periodoFiltroLabel
                    : '$periodoFiltroLabel · '
                        'Ultima busta paga: ${periodoLabel(filtrati.last)}',
                chart: _FerieRolPermessiSnapshot(
                  buste: filtrati,
                  busteNonConfermate: busteNonConfermate,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              0,
              AppSpacing.screenHorizontal,
              AppSpacing.xl,
            ),
            sliver: SliverToBoxAdapter(
              child: _StraordinarioCardSection(
                buste: filtrati,
                estendiFinoA: estendiFinoA,
                periodoFiltroLabel: periodoFiltroLabel,
                busteNonConfermate: busteNonConfermate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Messaggio mostrato al posto del grafico quando non ci sono buste paga da
/// rappresentare — archivio vuoto (nessuna busta paga mensile confermata nel
/// periodo selezionato), oppure [busteNonConfermate] > 0: in quel caso i
/// dati esistono e sono già inclusi nello slider di periodo sopra i grafici
/// (vedi `_bustaInclusaInRangePeriodo`), ma sono esclusi da qui perché non
/// ancora confermati (`bustaInclusaInStatistiche`) — un messaggio esplicito
/// al posto del generico "Non ci sono dati" evita che l'utente scambi
/// questo per un bug di rendering subito dopo un import massivo.
class _NoDataMessage extends StatelessWidget {
  final int busteNonConfermate;

  const _NoDataMessage({this.busteNonConfermate = 0});

  @override
  Widget build(BuildContext context) {
    final secondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    final messaggio = busteNonConfermate <= 0
        ? 'Non ci sono dati'
        : busteNonConfermate == 1
            ? 'Hai 1 busta paga da confermare: confermala per vederla nei '
                'grafici.'
            : 'Hai $busteNonConfermate buste paga da confermare: '
                'confermale per vederle nei grafici.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            busteNonConfermate > 0
                ? PulseIcon(
                    glyph: PulseIconGlyph.checkmark,
                    size: 28,
                    color: secondary,
                  )
                : PulseIcon(
                    glyph: PulseIconGlyph.chart,
                    size: 28,
                    color: secondary,
                  ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              messaggio,
              textAlign: TextAlign.center,
              style: AppTextStyles.pulseBody.copyWith(color: secondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card che ospita un grafico/vista principale, più — se [stats] non è
/// `null` e ha righe — un link testuale "Dettagli" che espande/nasconde la
/// vecchia tabella Media/Minimo/Massimo/Totale (`AnimatedSize`, collassata
/// di default). Stessa superficie piatta con bordo a gradiente viola→ciano
/// di prima (`PulseSurface` + `Container` esterno).
class _ChartCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget chart;
  final _StatsTableData? stats;

  /// Etichetta "in vista" (opzione D del redesign "molto storico" del
  /// 2026-09-11): riassume il range di mesi effettivamente visibile nello
  /// scroll orizzontale del grafico in quel momento (es. "Ott '25 → Mar
  /// '26"), aggiornata dal wrapper locale che possiede il grafico
  /// scrollabile (`_NettoCardSection`/`_StraordinarioCardSection`) —
  /// `null` quando il grafico non ha ancora dati o non supporta questo
  /// meccanismo (card Ferie/Permessi/Ex festività).
  final String? viewRangeLabel;

  const _ChartCard({
    required this.title,
    this.subtitle,
    required this.chart,
    this.stats,
    this.viewRangeLabel,
  });

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    // Bordo sottile a gradiente viola→ciano (direzione "gradient mesh", vedi
    // CLAUDE.md): non tocca `PulseSurface` in sé (widget condiviso da tutta
    // l'app, fuori scope qui) — un `Container` esterno con un `BoxDecoration`
    // a gradiente e 1px di `padding` disegna il bordo "attorno" alla
    // superficie piatta, così i tre grafici non sembrano isolati dal resto
    // dell'app ora più riccamente colorata, senza introdurre una seconda
    // superficie/ombra sovrapposta.
    final violet =
        CupertinoDynamicColor.resolve(AppColors.pulseSecondaryGlow, context);
    final cyan = CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final secondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final hasStats = widget.stats != null && widget.stats!.righe.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pulse),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            violet.withValues(alpha: 0.35),
            cyan.withValues(alpha: 0.35),
          ],
        ),
      ),
      padding: const EdgeInsets.all(1),
      child: PulseSurface(
        borderRadius: AppRadius.pulse,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: AppTextStyles.pulseBodyEmphasis.copyWith(
                  color: CupertinoDynamicColor.resolve(
                      AppColors.pulseTextPrimary, context),
                ),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: AppTextStyles.pulseLabel.copyWith(color: secondary),
                ),
              ],
              if (widget.viewRangeLabel != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.viewRangeLabel!,
                  style: AppTextStyles.pulseLabel.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              widget.chart,
              if (hasStats) ...[
                const SizedBox(height: AppSpacing.sm),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _expanded ? 'Nascondi dettagli' : 'Dettagli',
                          style:
                              AppTextStyles.pulseLabel.copyWith(color: accent),
                        ),
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          duration: const Duration(milliseconds: 220),
                          turns: _expanded ? 0.5 : 0,
                          child: PulseIcon(
                            glyph: PulseIconGlyph.chevronDown,
                            size: 14,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: _StatsTable(data: widget.stats!),
                        )
                      : const SizedBox(width: double.infinity, height: 0),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dati di `_StatsTable`: [colonne] è il nome di ciascuna serie (es.
/// `['Netto', 'Lordo']`), [righe] una lista di (etichetta metrica, un
/// valore già formattato per colonna, stesso ordine di [colonne]).
typedef _StatsTableData = ({
  List<String> colonne,
  List<(String label, List<String> valori)> righe,
});

/// Tabella numerica (media/min/max/totale) sotto un grafico Statistiche —
/// stesso pattern di `_MaturazioniSection` nel dettaglio busta paga
/// (`Row`+`Expanded` a flex fissi, non `Table`): riga header con i nomi
/// delle serie, poi una riga per metrica con un valore per colonna. Dal
/// redesign 2026-08-30 vive dietro il link "Dettagli" di `_ChartCard`
/// invece di essere sempre visibile — nessun cambio al contenuto/struttura
/// della tabella in sé.
class _StatsTable extends StatelessWidget {
  final _StatsTableData data;

  const _StatsTable({required this.data});

  @override
  Widget build(BuildContext context) {
    final labelColor =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    final valueColor =
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
    final dividerColor = labelColor.withValues(alpha: 0.3);
    final headerStyle = AppTextStyles.pulseLabel.copyWith(color: labelColor);
    final labelStyle = AppTextStyles.pulseBody.copyWith(
      color: valueColor,
      fontWeight: FontWeight.w600,
    );
    final valueStyle = AppTextStyles.pulseBody.copyWith(color: valueColor);

    Widget divider() => Container(height: 0.5, color: dividerColor);
    Widget columnDivider() => Container(
          width: 0.5,
          margin: const EdgeInsets.symmetric(vertical: 2),
          color: dividerColor,
        );

    // Il testo non deve mai andare a capo (anche con celle lunghe tipo
    // "€ 1563.99 (mag '26)" in colonne strette): FittedBox lo restringe
    // fino a stare su una riga sola invece di lasciarlo wrappare — garanzia
    // strutturale indipendente dal numero di colonne del grafico. Il
    // `Padding` orizzontale attorno al `FittedBox` è necessario oltre al
    // `columnDivider` (0.5px, quasi invisibile): senza margine esplicito, il
    // testo di due celle scalate a piena larghezza (es. "9,00 (gen '26)" e
    // "17,80 (gen '26)" nella riga Minimo) arriva a ridosso del divisore su
    // entrambi i lati e appare come un'unica stringa attaccata — bug reale
    // corretto qui, non un'ipotesi.
    Widget cell(String text, TextStyle style,
        {TextAlign align = TextAlign.center}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: align == TextAlign.center
              ? Alignment.center
              : Alignment.centerLeft,
          child: Text(text, style: style, maxLines: 1, softWrap: false),
        ),
      );
    }

    // Un divisore verticale sottile tra ogni colonna (oltre a quelli
    // orizzontali tra le righe), per separare a colpo d'occhio le serie
    // quando sono 2-3 affiancate (Netto/Lordo, Ferie/Permessi).
    List<Widget> withColumnDividers(List<Widget> celle) {
      return [
        for (var i = 0; i < celle.length; i++) ...[
          if (i > 0) columnDivider(),
          celle[i],
        ],
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: withColumnDividers([
              const Expanded(flex: 2, child: SizedBox.shrink()),
              for (final colonna in data.colonne)
                Expanded(
                  flex: 2,
                  child: cell(colonna, headerStyle),
                ),
            ]),
          ),
        ),
        divider(),
        for (var i = 0; i < data.righe.length; i++) ...[
          if (i > 0) divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: withColumnDividers([
                Expanded(
                  flex: 2,
                  child:
                      cell(data.righe[i].$1, labelStyle, align: TextAlign.left),
                ),
                for (final valore in data.righe[i].$2)
                  Expanded(
                    flex: 2,
                    child: cell(valore, valueStyle),
                  ),
              ]),
            ),
          ),
        ],
      ],
    );
  }
}

/// Trova la busta paga con il valore minimo secondo [selettore]. Richiede
/// [buste] non vuota.
BustaPaga _bustaConMinimo(
    List<BustaPaga> buste, double Function(BustaPaga) selettore) {
  return buste.reduce((a, b) => selettore(a) <= selettore(b) ? a : b);
}

/// Trova la busta paga con il valore massimo secondo [selettore]. Richiede
/// [buste] non vuota.
BustaPaga _bustaConMassimo(
    List<BustaPaga> buste, double Function(BustaPaga) selettore) {
  return buste.reduce((a, b) => selettore(a) >= selettore(b) ? a : b);
}

double _media(List<BustaPaga> buste, double Function(BustaPaga) selettore) {
  return buste.map(selettore).reduce((a, b) => a + b) / buste.length;
}

double _totale(List<BustaPaga> buste, double Function(BustaPaga) selettore) {
  return buste.map(selettore).reduce((a, b) => a + b);
}

/// Tabella del riepilogo sotto il grafico Netto. Opera sulle stesse [buste]
/// già filtrate (confermate, mensili, nel periodo selezionato) che
/// alimentano il grafico — nessun ricalcolo parallelo del filtro. Il Lordo
/// non è più una colonna di questa tabella (Task 2 del redesign
/// 2026-09-08): resta consultabile busta paga per busta paga tramite il
/// drill-down al tap su un punto della linea.
_StatsTableData? _nettoStats(List<BustaPaga> buste) {
  if (buste.isEmpty) return null;
  final minNetto = _bustaConMinimo(buste, (b) => b.netto);
  final maxNetto = _bustaConMassimo(buste, (b) => b.netto);
  return (
    colonne: const ['Netto'],
    righe: [
      (
        'Media',
        [formatEuroConSegno(_media(buste, (b) => b.netto))],
      ),
      (
        'Minimo',
        [
          '${formatEuroConSegno(minNetto.netto)} (${periodoAxisLabel(minNetto.periodo)})',
        ],
      ),
      (
        'Massimo',
        [
          '${formatEuroConSegno(maxNetto.netto)} (${periodoAxisLabel(maxNetto.periodo)})',
        ],
      ),
      (
        'Totale',
        [formatEuroConSegno(_totale(buste, (b) => b.netto))],
      ),
    ],
  );
}

/// Oltre questo numero di *slot mensili* nella griglia continua
/// (`_grigliaMensile`, l'ampiezza temporale coperta dal filtro — non il
/// numero di buste paga confermate, che può restare basso pur coprendo un
/// arco di molti anni se mancano mesi), `_StraordinarioChart` passa da barre
/// mensili a barre trimestrali (somma ore per trimestre): con 2+ anni di
/// dati mensili le barre diventano troppo sottili per essere lette anche con
/// lo scroll orizzontale, e 30 barre singole sono meno leggibili di un
/// andamento aggregato per trimestre.
const _quarterlyAggregationThreshold = 24;

/// Etichetta trimestre (es. "T1 '24"), usata sull'asse X e nel tooltip di
/// `_StraordinarioChart` quando le barre sono aggregate per trimestre.
String _trimestreLabel(DateTime periodo) {
  final trimestre = (periodo.month - 1) ~/ 3 + 1;
  return "T$trimestre '${annoAxisLabel(periodo).substring(1)}";
}

/// Aggrega [buste] per trimestre solare, sommando le ore di straordinario di
/// ogni trimestre. Il [DateTime] di ogni bucket è il primo giorno del primo
/// mese del trimestre, usato come riferimento per etichette e tooltip.
/// Assume [buste] ordinata per periodo crescente.
List<({DateTime periodo, double totale})> _aggregaStraordinariPerTrimestre(
    List<BustaPaga> buste) {
  final totali = <int, double>{};
  final riferimenti = <int, DateTime>{};
  for (final busta in buste) {
    final trimestre = (busta.periodo.month - 1) ~/ 3;
    final chiave = busta.periodo.year * 10 + trimestre;
    totali[chiave] = (totali[chiave] ?? 0) + busta.straordinari;
    riferimenti[chiave] ??= DateTime(busta.periodo.year, trimestre * 3 + 1);
  }
  final chiaviOrdinate = totali.keys.toList()..sort();
  return [
    for (final chiave in chiaviOrdinate)
      (periodo: riferimenti[chiave]!, totale: totali[chiave]!),
  ];
}

/// Indici del primo periodo di ogni anno presente in [periodi] (assume
/// [periodi] ordinata crescente) — usati per le etichette asse X in
/// modalità annuale.
List<int> _yearBoundaryIndices(List<DateTime> periodi) {
  final indices = <int>[];
  for (var i = 0; i < periodi.length; i++) {
    if (i == 0 || periodi[i].year != periodi[i - 1].year) {
      indices.add(i);
    }
  }
  return indices;
}

/// Espande [buste] (assunta ordinata per periodo crescente, un solo
/// elemento per mese solare — garantito da [bustaInclusaInStatistiche], che
/// filtra solo mensili confermate: l'app impedisce comunque due mensili
/// nello stesso anno+mese, vedi controllo anti-duplicati in
/// `buste_paga_section_screen.dart`) in una sequenza continua di TUTTI i
/// mesi solari fra il primo e l'ultimo periodo presente, un elemento per
/// mese: quelli senza una busta paga (mese non ancora confermato o non
/// importato) hanno `busta: null`.
///
/// Usata per disegnare le serie dei grafici su un asse X che riflette il
/// calendario reale invece della sola posizione nell'array: prima di questo
/// fix `FlSpot(i.toDouble(), ...)` usava l'indice nella lista filtrata come
/// coordinata X, quindi un mese mancante (frequente in un reimport massivo,
/// dove le buste si confermano una alla volta) faceva letteralmente sparire
/// il buco — la riga/barra del mese precedente si univa a quella del mese
/// successivo come se fossero consecutivi, senza alcun segnale visivo.
/// Con la griglia, l'indice nell'array coincide sempre con un preciso mese
/// solare (compresi quelli senza dati): un mese mancante resta uno slot con
/// `busta: null`, che i chiamanti traducono in un vero e proprio buco visivo
/// — `FlSpot.nullSpot` per le linee (fl_chart spezza la linea in più
/// segmenti quando incontra uno "spot nullo", meccanismo nativo, non uno
/// stratagemma: vedi `LineChartBarData.spots`) e l'assenza di una barra per
/// `_StraordinarioChart` — invece di un'interpolazione silenziosa.
/// [estendiFinoA], se non nullo e successivo all'ultimo periodo presente in
/// [buste], estende la griglia con ulteriori slot vuoti (`busta: null`) fino
/// a quel mese incluso — usato per estendere i grafici fino al mese corrente
/// reale invece di fermarsi all'ultima busta paga confermata, rispettando
/// comunque un filtro periodo più restrittivo (in quel caso il chiamante
/// passa la fine del filtro, non oggi).
List<({DateTime periodo, BustaPaga? busta})> _grigliaMensile(
  List<BustaPaga> buste, {
  DateTime? estendiFinoA,
}) {
  if (buste.isEmpty) return const [];
  final risultato = <({DateTime periodo, BustaPaga? busta})>[];
  var cursore = DateTime(buste.first.periodo.year, buste.first.periodo.month);
  var fine = DateTime(buste.last.periodo.year, buste.last.periodo.month);
  if (estendiFinoA != null) {
    final estensione = DateTime(estendiFinoA.year, estendiFinoA.month);
    if (estensione.isAfter(fine)) fine = estensione;
  }
  var indice = 0;
  while (!cursore.isAfter(fine)) {
    final corrisponde = indice < buste.length &&
        buste[indice].periodo.year == cursore.year &&
        buste[indice].periodo.month == cursore.month;
    risultato.add(
      (periodo: cursore, busta: corrisponde ? buste[indice] : null),
    );
    if (corrisponde) indice++;
    // `DateTime(year, month + 1)` normalizza da solo il riporto a gennaio
    // dell'anno successivo quando `month` supera 12.
    cursore = DateTime(cursore.year, cursore.month + 1);
  }
  return risultato;
}

/// Analoga a [_grigliaMensile] ma a livello di trimestre, sui bucket già
/// prodotti da [_aggregaStraordinariPerTrimestre]: un trimestre interamente
/// privo di buste paga confermate (3 mesi consecutivi mancanti, possibile
/// solo quando l'aggregazione trimestrale è attiva, cioè con 2+ anni di
/// dati) resta comunque un buco visibile invece di sparire. Richiede
/// [buste] non vuota.
/// [estendiFinoA], se non nullo e successivo al trimestre dell'ultimo bucket
/// aggregato, estende la griglia con trimestri vuoti (`totale: null`) fino al
/// trimestre che lo contiene — stessa logica di estensione di
/// [_grigliaMensile], vedi doc lì.
List<({DateTime periodo, double? totale})> _grigliaTrimestrale(
  List<BustaPaga> buste, {
  DateTime? estendiFinoA,
}) {
  final aggregati = _aggregaStraordinariPerTrimestre(buste);
  int chiaveTrimestre(DateTime periodo) =>
      periodo.year * 4 + (periodo.month - 1) ~/ 3;
  final mappa = <int, double>{
    for (final punto in aggregati) chiaveTrimestre(punto.periodo): punto.totale,
  };
  final risultato = <({DateTime periodo, double? totale})>[];
  var chiaveFine = chiaveTrimestre(aggregati.last.periodo);
  if (estendiFinoA != null) {
    final chiaveEstensione = chiaveTrimestre(estendiFinoA);
    if (chiaveEstensione > chiaveFine) chiaveFine = chiaveEstensione;
  }
  for (var chiave = chiaveTrimestre(aggregati.first.periodo);
      chiave <= chiaveFine;
      chiave++) {
    final anno = chiave ~/ 4;
    final trimestre = chiave % 4;
    risultato.add(
      (periodo: DateTime(anno, trimestre * 3 + 1), totale: mappa[chiave]),
    );
  }
  return risultato;
}

/// Asse X condiviso dai tre grafici della schermata (etichette periodo
/// diradate in base allo spazio disponibile) — estratto per evitare che il
/// fix della sovrapposizione venga applicato a un solo grafico per errore.
/// Prende una lista di [periodi] invece delle buste paga intere, così può
/// essere riusata anche per punti aggregati (es. barre trimestrali di
/// `_StraordinarioChart`) che non corrispondono 1:1 a una `BustaPaga`.
/// [shortLabelBuilder] permette di personalizzare l'etichetta di dettaglio
/// (default "gen '24"), usato per il caso trimestrale ("T1 '24").
///
/// Nessun diradamento delle etichette (rimosso interamente il 2026-09-11,
/// vedi CLAUDE.md "molto storico"): sia `_NettoChart` sia `_StraordinarioChart`
/// disegnano ora ogni mese/trimestre su uno slot a larghezza fissa dentro
/// un'area scrollabile orizzontalmente (`SingleChildScrollView`) — c'è
/// sempre spazio sufficiente per l'etichetta di ogni singolo tick, quindi
/// non serve più calcolare un interval in base alla larghezza disponibile
/// né passare a un'etichetta annuale oltre una certa soglia di punti
/// (rimossi `_bottomTitleInterval`/`_yearlyLabelsThreshold`). Resta solo
/// l'evidenziazione del confine anno (vedi sotto), utile a colpo d'occhio
/// anche con spazio garantito per ogni tick.
AxisTitles _periodoBottomAxisTitles({
  required List<DateTime> periodi,
  required Color labelColor,
  String Function(DateTime periodo) shortLabelBuilder = meseAxisLabel,
}) {
  final textStyle =
      AppTextStyles.pulseLabel.copyWith(color: labelColor, fontSize: 10);

  // Quando [periodi] attraversa più anni (tipico di un archivio con 12+
  // mensilità su due anni solari, es. ago '25 → lug '26), lo stesso nome di
  // mese può comparire due volte identico ("ago ott dic feb apr giu" non
  // rivela a colpo d'occhio che si passa da un anno all'altro): si forza
  // sempre visibile il primo tick di ogni anno (`_yearBoundaryIndices`) e
  // SOLO su quei tick si mostra il periodo completo con l'anno
  // (`periodoAxisLabel`, "ago '25") invece del solo mese — un'etichetta più
  // lunga isolata nel punto in cui serve davvero.
  //
  // Si applica SOLO quando [shortLabelBuilder] è il default (etichetta solo
  // mese): il caso trimestrale di `_StraordinarioChart` aggregato
  // (`_trimestreLabel`, "T1 '24") include già sempre l'anno per costruzione,
  // quindi non necessita di (e andrebbe anzi in conflitto di formato con)
  // questo trattamento.
  final usaEtichettaMeseDefault = identical(shortLabelBuilder, meseAxisLabel);
  final multiAnno = usaEtichettaMeseDefault &&
      periodi.isNotEmpty &&
      periodi.first.year != periodi.last.year;
  final confiniAnno =
      multiAnno ? _yearBoundaryIndices(periodi).toSet() : const <int>{};

  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 22,
      interval: 1,
      getTitlesWidget: (value, meta) {
        final index = value.round();
        if (index < 0 || index >= periodi.length) {
          return const SizedBox.shrink();
        }
        final label = confiniAnno.contains(index)
            ? periodoAxisLabel(periodi[index])
            : shortLabelBuilder(periodi[index]);
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(label, style: textStyle),
        );
      },
    ),
  );
}

/// Asse Y condiviso (valori sempre visibili, per dare la scala generale del
/// grafico senza dover toccare ogni punto/barra). Un solo asse per grafico:
/// nei grafici multi-serie tutte le serie condividono la stessa scala,
/// approccio più semplice scelto come primo passo — da rivedere con doppio
/// asse solo se le grandezze combinate risultassero poco leggibili.
AxisTitles _valueLeftAxisTitles({
  required Color labelColor,
  required double interval,
  String Function(double value) formatValue = formatNumber,
  // 40 di default (etichette corte tipo "12,5"/"20,0h" di `formatNumber`,
  // usate da Straordinario). Il grafico Netto/Lordo passa esplicitamente
  // `_euroCompactAxisReservedSize` (52): margine extra per il caso peggiore
  // plausibile del suo formato compatto ("− € 12,3k", vedi
  // `formatEuroConSegnoCompatto`) alla dimensione naturale del font (fontSize
  // 10), senza affidarsi allo scale-down di `FittedBox` sotto la soglia di
  // leggibilità.
  double reservedSize = 40,
}) {
  return AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: reservedSize,
      // Interval SEMPRE esplicito (mai lasciato calcolare da fl_chart): senza
      // questo, con un range di dati stretto (es. un solo mese), fl_chart
      // sceglie da solo uno step piccolo (es. €20-30) che, una volta passato
      // a [formatValue] con la sua risoluzione di arrotondamento (es. "k" a
      // un decimale, cioè €100, di `formatEuroConSegnoCompatto`), produce
      // etichette duplicate su tick adiacenti — bug reale corretto qui, non
      // un'ipotesi. [interval] arriva già calcolato da [_niceStep] con una
      // soglia minima legata alla risoluzione del formato usato su
      // quell'asse, e dagli stessi bound "nice" allineati allo stesso step
      // (vedi `_niceAxisBounds`), così i tick coincidono sempre con min/max.
      interval: interval,
      getTitlesWidget: (value, meta) {
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: SizedBox(
            // -6 per il padding a destra sopra, così la larghezza reale
            // dell'etichetta resta sempre coerente con [reservedSize] invece
            // di un valore fisso indipendente che potrebbe disallinearsi.
            width: reservedSize - 6,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                formatValue(value),
                style: AppTextStyles.pulseLabel
                    .copyWith(color: labelColor, fontSize: 10),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Arrotonda un intervallo di dati a multipli "puliti" di [step], così il
/// bordo dell'asse (`minY`/`maxY`) coincide sempre con un tick reale.
/// Senza questo, lasciare che fl_chart calcoli da solo `minY`/`maxY` produce
/// spesso un bordo non allineato ai tick automatici (es. 105.60 quando i
/// tick sono 0/50/100): fl_chart aggiunge comunque un'etichetta forzata al
/// bordo, che finisce per sovrapporsi al tick "pulito" più vicino.
/// Calcola uno step "nice" (1, 2 o 5 × una potenza di 10) per i tick di un
/// asse valori, mirando a circa [targetTicks] tick sul [range] di dati, ma
/// mai sotto [minStep] — la risoluzione minima della formattazione usata su
/// quell'asse (es. €100 per `formatEuroConSegnoCompatto` in notazione "k",
/// dove un decimale corrisponde a un decimo di migliaio). Con un range
/// stretto (es. un solo mese di dati) lo step "naturale" (range/targetTicks)
/// scenderebbe spesso sotto quella risoluzione, producendo tick adiacenti che
/// si formattano nella stessa stringa (bug reale corretto qui, non
/// un'ipotesi — vedi `_valueLeftAxisTitles`). Con un range ampio lo step
/// "nice" naturale è già più grande di [minStep], quindi il clamp non ha
/// alcun effetto e il numero di tick resta vicino a [targetTicks] invece di
/// esplodere: la stessa funzione copre così sia il caso "pochi
/// dati/range stretto" sia "molti dati/range ampio" senza introdurre
/// l'estremo opposto (assi con 1-2 soli tick).
double _niceStep(
  double range, {
  double targetTicks = 5,
  required double minStep,
}) {
  if (range <= 0) return minStep;
  final rawStep = range / targetTicks;
  final magnitude =
      math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
  final residual = rawStep / magnitude;
  final double niceResidual;
  if (residual <= 1) {
    niceResidual = 1;
  } else if (residual <= 2) {
    niceResidual = 2;
  } else if (residual <= 5) {
    niceResidual = 5;
  } else {
    niceResidual = 10;
  }
  final step = niceResidual * magnitude;
  return step < minStep ? minStep : step;
}

({double min, double max}) _niceAxisBounds(
  double dataMin,
  double dataMax, {
  required double step,
}) {
  final min = (dataMin / step).floor() * step;
  var max = (dataMax / step).ceil() * step;
  if (max <= min) max += step;
  return (min: min, max: max);
}

/// `reservedSize` di [_valueLeftAxisTitles] per il grafico Netto/Lordo,
/// l'unico che usa il formato euro compatto (`formatEuroConSegnoCompatto`,
/// caso peggiore "− € 12,3k") — costante condivisa per evitare che il fix del
/// disallineamento 40 vs 52 (vedi `_StraordinarioChartState._leftAxisWidth`)
/// si ripresenti in futuro se il valore viene cambiato in un solo punto.
const _euroCompactAxisReservedSize = 52.0;

/// Badge freccia + percentuale di variazione (▲ verde/▼ rossa) sotto un
/// valore in evidenza — usato dai due numeri grandi del blocco Netto/Lordo.
/// `null` produce un widget vuoto (nessun mese precedente nel periodo
/// filtrato con cui confrontare, o precedente pari a zero — divisione non
/// definita).
class _VariationBadge extends StatelessWidget {
  final double? variazione;

  const _VariationBadge({required this.variazione});

  @override
  Widget build(BuildContext context) {
    final variazione = this.variazione;
    if (variazione == null) return const SizedBox.shrink();
    final positiva = variazione >= 0;
    final color = CupertinoDynamicColor.resolve(
      positiva ? AppColors.pulsePositive : AppColors.pulseNegative,
      context,
    );
    final percentuale = variazione.abs() * 100;
    // Una sola cifra decimale sotto il 10% (es. "3,2%"), intero oltre (es.
    // "18%") — coerente con la risoluzione già usata da `formatNumber` per
    // valori piccoli senza appesantire percentuali a due cifre.
    final testo = percentuale < 10
        ? '${percentuale.toStringAsFixed(1).replaceAll('.', ',')}%'
        : '${percentuale.round()}%';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          positiva
              ? CupertinoIcons.arrow_up_right
              : CupertinoIcons.arrow_down_right,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(testo, style: AppTextStyles.pulseLabel.copyWith(color: color)),
      ],
    );
  }
}

/// Numero grande del Netto in cima al blocco 1, con la variazione
/// percentuale rispetto al mese immediatamente precedente nell'elenco già
/// filtrato dal periodo — non necessariamente il mese solare precedente, se
/// il periodo filtrato ha dei buchi. Il Lordo non compare più qui (Task 2
/// del redesign 2026-09-08): resta consultabile busta paga per busta paga
/// tramite il drill-down al tap su un punto della linea. Richiede [buste]
/// non vuota, ordinata per periodo crescente.
class _NettoHeader extends StatelessWidget {
  final List<BustaPaga> buste;

  const _NettoHeader({required this.buste});

  double? _variazione(double Function(BustaPaga) selettore) {
    if (buste.length < 2) return null;
    final attuale = selettore(buste.last);
    final precedente = selettore(buste[buste.length - 2]);
    if (precedente == 0) return null;
    return (attuale - precedente) / precedente;
  }

  @override
  Widget build(BuildContext context) {
    final ultima = buste.last;
    final primary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
    final secondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Netto',
            style: AppTextStyles.pulseLabel.copyWith(color: secondary)),
        const SizedBox(height: 4),
        Text(
          formatEuroConSegno(ultima.netto),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.pulseDisplayLarge
              .copyWith(fontSize: 24, color: primary),
        ),
        const SizedBox(height: 4),
        _VariationBadge(variazione: _variazione((b) => b.netto)),
      ],
    );
  }
}

/// Grafico ad area del blocco Netto: un'unica linea/area piena col colore
/// funzionale primario dell'app (`pulseAccent`), niente più una seconda
/// serie Lordo né un glow dietro il tracciato (Task 2 del redesign
/// 2026-09-08, vedi CLAUDE.md — vincolo "nessun glow/bagliore diffuso nei
/// grafici"; l'area sotto la linea resta perché è un riempimento pieno a
/// bassa opacità, non un bagliore). Stessa griglia mensile continua/bound
/// "nice" di prima del redesign, nessun cambio alla logica di aggregazione
/// dei dati.
///
/// Sola visualizzazione, nessuna interazione al tocco (2026-09-10, richiesta
/// esplicita dell'utente: "il tap sui grafici non mi piace per niente...
/// eliminalo del tutto" — sostituisce sia il tap diretto sia il successivo
/// tentativo di tooltip custom con "Vedi dettaglio", entrambi rimossi):
/// `lineTouchData` è `LineTouchData(enabled: false)`, che disattiva sia il
/// tooltip nativo sia qualunque callback di tocco/hover/scrubbing — nessun
/// overlay, nessuno stato locale, nessun drill-down da questo grafico.
/// Mixin condiviso da `_NettoChartState`/`_StraordinarioChartState`: entrambi
/// i grafici disegnano ora ogni slot (mese o trimestre) a larghezza fissa in
/// un'area scrollabile orizzontalmente quando lo storico non entra nella
/// larghezza della card (opzione B del redesign "molto storico" del
/// 2026-09-11, vedi CLAUDE.md) — questo mixin centralizza lo scroll iniziale
/// posizionato sull'estremità più recente e il calcolo del range di slot
/// effettivamente visibile nel viewport, riportato al wrapper esterno
/// (`_NettoCardSection`/`_StraordinarioCardSection`) tramite
/// [onVisibleRangeChanged] per l'etichetta "in vista" fissa in alto nella
/// card (opzione D) — resta a carico di ciascuna sottoclasse il proprio
/// `ScrollController`/dissolvenza di bordo destro (già esistenti prima di
/// questo mixin per Straordinario).
mixin _VisibleRangeReporterMixin<T extends StatefulWidget> on State<T> {
  bool _initialScrollDone = false;

  /// Notificata quando il range di slot visibile cambia — `null` per
  /// disattivare del tutto la segnalazione (nessun caso d'uso attuale, ma
  /// evita di dover gestire un valore mancante nei chiamanti).
  void Function(String label)? get onVisibleRangeChanged;

  /// Programma lo scroll iniziale sull'estremità più recente (il mese/
  /// trimestre più recente visibile appena la card compare), una sola volta
  /// per istanza dello State — va richiamato a ogni `build()` che disegna un
  /// [controller] scrollabile, il guard interno impedisce jump ripetuti a
  /// ogni rebuild.
  void scheduleInitialScrollToEnd(
    ScrollController controller, {
    required List<DateTime> periodi,
    required double slotWidth,
  }) {
    if (_initialScrollDone) return;
    _initialScrollDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !controller.hasClients) return;
      controller.jumpTo(controller.position.maxScrollExtent);
      reportVisibleRange(
        controller: controller,
        periodi: periodi,
        slotWidth: slotWidth,
      );
    });
  }

  /// Calcola e riporta a [onVisibleRangeChanged] il range di [periodi]
  /// effettivamente visibile nel viewport di [controller] in base alla
  /// larghezza fissa [slotWidth] di ciascuno slot — se [controller] non è
  /// ancora agganciato a uno `Scrollable` (grafico non scrollabile perché lo
  /// storico entra per intero nella card) l'intero range è per definizione
  /// visibile.
  void reportVisibleRange({
    required ScrollController controller,
    required List<DateTime> periodi,
    required double slotWidth,
  }) {
    final callback = onVisibleRangeChanged;
    if (callback == null || periodi.isEmpty) return;
    if (!controller.hasClients) {
      callback(_viewRangeLabel(periodi.first, periodi.last));
      return;
    }
    final position = controller.position;
    final firstIndex =
        (position.pixels / slotWidth).floor().clamp(0, periodi.length - 1);
    final lastIndexRaw =
        ((position.pixels + position.viewportDimension) / slotWidth).ceil() -
            1;
    final lastIndex = lastIndexRaw.clamp(firstIndex, periodi.length - 1);
    callback(_viewRangeLabel(periodi[firstIndex], periodi[lastIndex]));
  }
}

/// Etichetta "in vista" (es. "Ott '25 → Mar '26", o solo "Ott '25" se un solo
/// mese è visibile) — stesso formato/separatore "→" di
/// `PeriodYearMonthPicker.formatRangeLabel`, ma su etichette brevi
/// (`periodoAxisLabel`) invece del nome completo del mese: qui lo spazio è
/// quello stretto in cima a una card, non quello di un chip riassuntivo a
/// piena larghezza.
String _viewRangeLabel(DateTime start, DateTime end) {
  String cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  final startLabel = cap(periodoAxisLabel(start));
  if (start.year == end.year && start.month == end.month) return startLabel;
  return '$startLabel → ${cap(periodoAxisLabel(end))}';
}

/// Chiave dati passata a `_NettoChart`/`_StraordinarioChart` per forzare
/// Flutter a creare un nuovo `State` (quindi anche un nuovo
/// `ScrollController` e un nuovo `_initialScrollDone` di
/// `_VisibleRangeReporterMixin`, entrambi partono da zero) ogni volta che
/// l'insieme di buste paga effettivamente disegnato cambia — tipicamente
/// dopo un cambio di filtro periodo (`PeriodYearMonthPicker`/preset).
///
/// Bug reale corretto qui, non un'ipotesi: senza una `Key` che dipenda dai
/// dati, questi due grafici restano nella stessa posizione dell'albero dei
/// widget a ogni rebuild di `_NettoCardSection`/`_StraordinarioCardSection`
/// (stesso `runtimeType`, nessuna `Key` prima di questo fix) — Flutter
/// quindi riusa lo `State` esistente invece di crearne uno nuovo.
/// `_initialScrollDone` diventava `true` in modo permanente dopo il primo
/// scroll-to-end e non veniva mai resettato: un cambio di filtro con la card
/// ancora scrollabile (`needsScroll == true` sia prima sia dopo il cambio)
/// non faceva mai ripartire né il jump-to-end iniziale né un nuovo
/// `reportVisibleRange`, lasciando sia la posizione di scroll sia
/// l'etichetta "in vista" bloccate ai valori del periodo precedente (il ramo
/// `!needsScroll` non ne soffriva perché richiama `reportVisibleRange`
/// incondizionatamente a ogni build).
///
/// Preferita a un `didUpdateWidget` che resetti manualmente
/// `_initialScrollDone`: una `Key` derivata dai dati fa ripartire per intero
/// `initState`/i campi del mixin senza dover mantenere a mano l'elenco di
/// cosa resettare quando cambiano i dati, ed è coerente con l'unico altro
/// caso dell'app in cui lo stato locale di un grafico dipende dai dati
/// visualizzati. Basata su lunghezza + id di prima/ultima busta paga più
/// [estendiFinoA], che può da solo allungare la griglia anche a parità di
/// [buste] (es. il passare del tempo estende fino al mese corrente, vedi doc
/// di `_grigliaMensile`).
///
/// Caso limite reale corretto qui, non un'ipotesi (segnalato in revisione):
/// lunghezza + id di prima/ultima busta paga da soli NON bastano quando la
/// busta paga modificata è interna al range filtrato (non la prima né
/// l'ultima per data) e la modifica è un cambio di **periodo** (mese/anno,
/// possibile dal dettaglio in "Modifica inline") che sposta i dati da uno
/// slot della griglia mensile a un altro senza spostare i bordi del range —
/// `buste.length`/primo/ultimo id restano identici, ma lo slot che prima
/// aveva dati ora è un buco e viceversa: la "forma" della griglia (quali
/// mesi hanno un buco) cambia comunque, e scroll/etichetta "in vista" di
/// `_NettoChart`/`_StraordinarioChart` restano calcolati sulla vecchia
/// forma. Per questo la chiave include anche un'impronta della griglia
/// mensile reale (`_grigliaMensile` con lo stesso [estendiFinoA] usato dai
/// grafici): una stringa di bit, uno slot per mese, `1` se quel mese ha una
/// busta paga e `0` se è un buco. Una sequenza di bit (non solo un conteggio
/// di buchi) è necessaria perché uno spostamento interno lascia invariato il
/// numero totale di buchi (uno slot ne perde uno, l'altro ne guadagna uno) —
/// serve la posizione, non solo la quantità. Condivisa da
/// `_StraordinarioChart` anche quando aggrega per trimestre: l'aggregazione
/// trimestrale è un ulteriore raggruppamento della stessa griglia mensile
/// reale, quindi la stessa impronta ne cattura correttamente anche i cambi
/// di composizione.
Key _chartDataKey(List<BustaPaga> buste, DateTime estendiFinoA) {
  final primo = buste.isEmpty ? '' : buste.first.id;
  final ultimo = buste.isEmpty ? '' : buste.last.id;
  final griglia = _grigliaMensile(buste, estendiFinoA: estendiFinoA);
  final formaGriglia =
      griglia.map((slot) => slot.busta == null ? '0' : '1').join();
  return ValueKey(
      '${buste.length}|$primo|$ultimo|${estendiFinoA.toIso8601String()}|$formaGriglia');
}

/// Wrapper locale con stato che possiede la card Netto: l'unico scopo di
/// questo `StatefulWidget` è tenere l'etichetta "in vista" (opzione D)
/// aggiornata dallo scroll di `_NettoChart` senza forzare un rebuild
/// dell'intera schermata (`BustePagaStatisticheScreen` resta un
/// `ConsumerWidget` senza stato proprio, vedi CLAUDE.md).
class _NettoCardSection extends StatefulWidget {
  final List<BustaPaga> buste;
  final DateTime estendiFinoA;
  final String periodoFiltroLabel;
  final int busteNonConfermate;
  final _StatsTableData? stats;

  const _NettoCardSection({
    required this.buste,
    required this.estendiFinoA,
    required this.periodoFiltroLabel,
    required this.busteNonConfermate,
    required this.stats,
  });

  @override
  State<_NettoCardSection> createState() => _NettoCardSectionState();
}

class _NettoCardSectionState extends State<_NettoCardSection> {
  String? _viewRangeLabel;

  @override
  Widget build(BuildContext context) {
    final buste = widget.buste;
    return _ChartCard(
      title: 'Netto',
      subtitle: widget.periodoFiltroLabel,
      viewRangeLabel: buste.isEmpty ? null : _viewRangeLabel,
      chart: buste.isEmpty
          ? SizedBox(
              height: 180,
              child:
                  _NoDataMessage(busteNonConfermate: widget.busteNonConfermate),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NettoHeader(buste: buste),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 180,
                  child: _NettoChart(
                    key: _chartDataKey(buste, widget.estendiFinoA),
                    buste: buste,
                    estendiFinoA: widget.estendiFinoA,
                    // Guardia sull'invarianza: senza questo controllo un
                    // grafico non scrollabile (l'intero storico entra nella
                    // card) rischeggerebbe di richiamare la callback a ogni
                    // singolo `build()` — `reportVisibleRange` viene
                    // riprogrammata via `addPostFrameCallback` a ogni frame
                    // finché lo scroll non è scrollabile, e senza questo
                    // guard il conseguente `setState` qui rischierebbe un
                    // loop di rebuild infinito che non fa mai convergere
                    // `pumpAndSettle` (bug reale riprodotto nei test, non
                    // un'ipotesi).
                    onVisibleRangeChanged: (label) {
                      if (label != _viewRangeLabel) {
                        setState(() => _viewRangeLabel = label);
                      }
                    },
                  ),
                ),
              ],
            ),
      stats: widget.stats,
    );
  }
}

/// Grafico ad area del blocco Netto: un'unica linea/area piena col colore
/// funzionale primario dell'app (`pulseAccent`), niente più una seconda
/// serie Lordo né un glow dietro il tracciato (Task 2 del redesign
/// 2026-09-08, vedi CLAUDE.md — vincolo "nessun glow/bagliore diffuso nei
/// grafici"; l'area sotto la linea resta perché è un riempimento pieno a
/// bassa opacità, non un bagliore). Stessa griglia mensile continua/bound
/// "nice" di prima del redesign, nessun cambio alla logica di aggregazione
/// dei dati.
///
/// Ogni mese occupa una larghezza fissa ([_slotWidth]) in un'area di disegno
/// scrollabile orizzontalmente quando lo storico non entra nella larghezza
/// della card (redesign "molto storico" del 2026-09-11, vedi CLAUDE.md) —
/// stesso pattern architetturale già in uso da `_StraordinarioChart`
/// (`buildPlot`/`buildAxisOnly`, asse Y fisso a sinistra fuori dallo scroll:
/// fl_chart non supporta nativamente un asse fisso con area di disegno
/// scrollabile in un solo `LineChart`), con una larghezza per slot più ampia
/// (56 invece di 36) perché le etichette Netto sono più larghe ("gen '24"
/// sui confini anno, "− € 12,3k" sull'asse valori).
///
/// Sola visualizzazione, nessuna interazione al tocco (2026-09-10, richiesta
/// esplicita dell'utente: "il tap sui grafici non mi piace per niente...
/// eliminalo del tutto" — sostituisce sia il tap diretto sia il successivo
/// tentativo di tooltip custom con "Vedi dettaglio", entrambi rimossi):
/// `lineTouchData` è `LineTouchData(enabled: false)`, che disattiva sia il
/// tooltip nativo sia qualunque callback di tocco/hover/scrubbing — nessun
/// overlay, nessuno stato locale, nessun drill-down da questo grafico.
class _NettoChart extends StatefulWidget {
  final List<BustaPaga> buste;
  final DateTime estendiFinoA;
  final void Function(String label)? onVisibleRangeChanged;

  const _NettoChart({
    super.key,
    required this.buste,
    required this.estendiFinoA,
    this.onVisibleRangeChanged,
  });

  @override
  State<_NettoChart> createState() => _NettoChartState();
}

class _NettoChartState extends State<_NettoChart>
    with _VisibleRangeReporterMixin<_NettoChart> {
  // Larghezza comoda per mese (etichette/valori Netto più larghi delle
  // barre strette di Straordinario, che usa 36): vedi doc di libreria.
  static const _slotWidth = 56.0;
  static const _rightFadeWidth = 28.0;

  final _scrollController = ScrollController();
  bool _showRightFade = true;

  @override
  void Function(String label)? get onVisibleRangeChanged =>
      widget.onVisibleRangeChanged;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  List<DateTime> _periodiCorrenti = const [];

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final showFade = position.pixels < position.maxScrollExtent - 1;
    if (showFade != _showRightFade) {
      setState(() => _showRightFade = showFade);
    }
    reportVisibleRange(
      controller: _scrollController,
      periodi: _periodiCorrenti,
      slotWidth: _slotWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final nettoColor = CupertinoDynamicColor.resolve(
        BustePagaStatisticheScreen._nettoColor, context);
    final gridColor =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context)
            .withValues(alpha: 0.18);
    final labelColor =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);

    // Griglia continua mese per mese (vedi doc di libreria su
    // `_grigliaMensile`): un mese senza busta paga confermata resta un buco
    // visibile nel grafico (`FlSpot.nullSpot`) invece di sparire
    // silenziosamente collegando i due mesi adiacenti come se fossero
    // consecutivi.
    final griglia = _grigliaMensile(widget.buste, estendiFinoA: widget.estendiFinoA);
    final periodi = [for (final g in griglia) g.periodo];
    _periodiCorrenti = periodi;

    // Range ristretto ai dati reali (non da 0), margine 8% sopra e sotto il
    // range osservato, poi arrotondato a centinaia "pulite".
    final valori = widget.buste.map((b) => b.netto).toList();
    final datiMin = valori.reduce((a, b) => a < b ? a : b);
    final datiMax = valori.reduce((a, b) => a > b ? a : b);
    final margine = (datiMax - datiMin) * 0.08;
    // Step minimo di €100: coincide con la risoluzione di arrotondamento di
    // `formatEuroConSegnoCompatto` in notazione "k" (un decimale = un decimo
    // di migliaio) — vedi doc di [_niceStep], evita etichette duplicate
    // sull'asse con un range di dati stretto.
    final step = _niceStep(
      (datiMax + margine) - (datiMin - margine),
      minStep: 100,
    );
    final bounds = _niceAxisBounds(
      datiMin - margine,
      datiMax + margine,
      step: step,
    );

    Widget buildPlot({required double width, required bool showLeftAxis}) {
      return SizedBox(
        width: width,
        child: LineChart(
          LineChartData(
            minY: bounds.min,
            maxY: bounds.max,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: null,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: gridColor, strokeWidth: 0.5),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              leftTitles: showLeftAxis
                  ? _valueLeftAxisTitles(
                      labelColor: labelColor,
                      interval: step,
                      // Formato compatto SOLO per l'etichetta dell'asse
                      // (spazio ristretto): `formatEuroConSegno` resta usato
                      // per la tabella riepilogativa, dove serve precisione
                      // a 2 decimali — vedi doc di
                      // `formatEuroConSegnoCompatto`.
                      formatValue: formatEuroConSegnoCompatto,
                      reservedSize: _euroCompactAxisReservedSize,
                    )
                  : const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
              bottomTitles: _periodoBottomAxisTitles(
                periodi: periodi,
                labelColor: labelColor,
              ),
            ),
            // Nessuna interazione al tocco (vedi doc di libreria su
            // `_NettoChart`): `enabled: false` disattiva sia il tooltip
            // nativo sia qualunque callback di tap/hover/scrubbing.
            lineTouchData: const LineTouchData(enabled: false),
            lineBarsData: [
              _nettoLine(griglia, nettoColor),
            ],
          ),
        ),
      );
    }

    Widget buildAxisOnly() {
      return SizedBox(
        width: _euroCompactAxisReservedSize,
        child: LineChart(
          LineChartData(
            minY: bounds.min,
            maxY: bounds.max,
            lineBarsData: const [],
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false, reservedSize: 22)),
              leftTitles: _valueLeftAxisTitles(
                labelColor: labelColor,
                interval: step,
                formatValue: formatEuroConSegnoCompatto,
                reservedSize: _euroCompactAxisReservedSize,
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;
        final contentWidth = periodi.length * _slotWidth;
        final needsScroll =
            contentWidth > viewportWidth - _euroCompactAxisReservedSize;

        if (!needsScroll) {
          // Nessuno scroll necessario: l'intero range è già visibile per
          // intero, l'etichetta "in vista" copre subito tutto lo storico
          // filtrato senza aspettare un evento di scroll.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            reportVisibleRange(
              controller: _scrollController,
              periodi: periodi,
              slotWidth: _slotWidth,
            );
          });
          return buildPlot(width: viewportWidth, showLeftAxis: true);
        }

        scheduleInitialScrollToEnd(
          _scrollController,
          periodi: periodi,
          slotWidth: _slotWidth,
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildAxisOnly(),
            Expanded(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) {
                  final fadeWidth = _showRightFade ? _rightFadeWidth : 0.0;
                  final stop = 1 - (fadeWidth / rect.width).clamp(0.0, 1.0);
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: const [
                      CupertinoColors.white,
                      CupertinoColors.white,
                      CupertinoColors.transparent,
                    ],
                    stops: [0.0, stop, 1.0],
                  ).createShader(rect);
                },
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  child: buildPlot(width: contentWidth, showLeftAxis: false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<FlSpot> _spots(
    List<({DateTime periodo, BustaPaga? busta})> griglia,
    double Function(BustaPaga) selettore,
  ) {
    return [
      for (var i = 0; i < griglia.length; i++)
        griglia[i].busta == null
            ? FlSpot.nullSpot
            : FlSpot(i.toDouble(), selettore(griglia[i].busta!)),
    ];
  }

  LineChartBarData _nettoLine(
    List<({DateTime periodo, BustaPaga? busta})> griglia,
    Color color,
  ) {
    return LineChartBarData(
      spots: _spots(griglia, (b) => b.netto),
      isCurved: true,
      curveSmoothness: 0.2,
      color: color,
      barWidth: 2.5,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.32),
            color.withValues(alpha: 0.0),
          ],
        ),
      ),
    );
  }
}

/// Snapshot Ferie/Permessi/Ex festività residui: 3 tessere piatte
/// `ValueTile` (solo valore + label, nessun anello di progresso — stesso
/// stile già usato dall'Archivio, vedi `_MaturazioniRingsRow` in
/// `buste_paga_archivio_view.dart`) sull'ULTIMA busta paga del periodo
/// filtrato (non più un trend nel tempo, unica eccezione consapevole di
/// questo redesign — vedi CLAUDE.md).
class _FerieRolPermessiSnapshot extends StatelessWidget {
  final List<BustaPaga> buste;
  final int busteNonConfermate;

  const _FerieRolPermessiSnapshot({
    required this.buste,
    this.busteNonConfermate = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (buste.isEmpty) {
      return SizedBox(
        height: 180,
        child: _NoDataMessage(busteNonConfermate: busteNonConfermate),
      );
    }

    final ultima = buste.last;

    void apriDrilldown() => showBustaPagaDrilldown(context, ultima);

    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: apriDrilldown,
            child: ValueTile(
              label: 'Ferie',
              value: formatNumber(ultima.ferieResidue),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: apriDrilldown,
            child: ValueTile(
              label: 'Permessi',
              value: formatNumber(ultima.rolResidui),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: apriDrilldown,
            child: ValueTile(
              label: 'Ex festività',
              value: formatNumber(ultima.exFestivitaResidue),
            ),
          ),
        ),
      ],
    );
  }
}

/// Wrapper locale con stato che possiede la card Straordinario — stesso
/// scopo/pattern di `_NettoCardSection`, vedi doc lì: tiene l'etichetta "in
/// vista" (opzione D) aggiornata dallo scroll di `_StraordinarioChart` senza
/// forzare un rebuild dell'intera schermata.
class _StraordinarioCardSection extends StatefulWidget {
  final List<BustaPaga> buste;
  final DateTime estendiFinoA;
  final String periodoFiltroLabel;
  final int busteNonConfermate;

  const _StraordinarioCardSection({
    required this.buste,
    required this.estendiFinoA,
    required this.periodoFiltroLabel,
    required this.busteNonConfermate,
  });

  @override
  State<_StraordinarioCardSection> createState() =>
      _StraordinarioCardSectionState();
}

class _StraordinarioCardSectionState extends State<_StraordinarioCardSection> {
  String? _viewRangeLabel;

  @override
  Widget build(BuildContext context) {
    return _ChartCard(
      title: 'Straordinario per mese',
      subtitle: widget.periodoFiltroLabel,
      viewRangeLabel: widget.buste.isEmpty ? null : _viewRangeLabel,
      chart: _StraordinarioChart(
        key: _chartDataKey(widget.buste, widget.estendiFinoA),
        buste: widget.buste,
        busteNonConfermate: widget.busteNonConfermate,
        estendiFinoA: widget.estendiFinoA,
        // Guardia sull'invarianza: vedi doc dello stesso pattern in
        // `_NettoCardSectionState` — evita un loop di rebuild infinito col
        // grafico non scrollabile.
        onVisibleRangeChanged: (label) {
          if (label != _viewRangeLabel) {
            setState(() => _viewRangeLabel = label);
          }
        },
      ),
    );
  }
}

/// Grafico Straordinario per mese. Su range ampi (> [_quarterlyAggregationThreshold]
/// buste) le barre passano da mensili a trimestrali (vedi
/// `_aggregaStraordinariPerTrimestre`); se anche con l'aggregazione le barre
/// risulterebbero più strette di [_minGroupSlotWidth], il grafico diventa
/// scrollabile in orizzontale (barre a larghezza fissa leggibile) con
/// l'asse valori a sinistra tenuto fisso in un `BarChart` "scheletro"
/// separato — fl_chart non supporta nativamente un asse fisso + plot
/// scrollabile in un singolo chart. Ogni barra è un riempimento pieno ciano
/// (`pulseAccent`, Task 4 del redesign 2026-09-08, vedi CLAUDE.md — niente
/// più gradiente viola→ciano né glow dietro la barra massima): la barra del
/// valore più alto nel periodo filtrato resta piena/opaca, le altre a
/// opacità ridotta.
///
/// Sola visualizzazione, nessuna interazione al tocco (2026-09-10, richiesta
/// esplicita dell'utente: "il tap sui grafici non mi piace per niente...
/// eliminalo del tutto" — rimuove il precedente tap secco che apriva il
/// drill-down `showBustaPagaDrilldown` sulla busta paga corrispondente):
/// `barTouchData` è `BarTouchData(enabled: false)`, nessun tooltip nativo né
/// callback.
class _StraordinarioChart extends StatefulWidget {
  final List<BustaPaga> buste;
  final int busteNonConfermate;
  final DateTime estendiFinoA;
  final void Function(String label)? onVisibleRangeChanged;

  const _StraordinarioChart({
    super.key,
    required this.buste,
    this.busteNonConfermate = 0,
    required this.estendiFinoA,
    this.onVisibleRangeChanged,
  });

  @override
  State<_StraordinarioChart> createState() => _StraordinarioChartState();
}

class _StraordinarioChartState extends State<_StraordinarioChart>
    with _VisibleRangeReporterMixin<_StraordinarioChart> {
  static const _barWidth = 16.0;
  static const _groupsSpace = 20.0;
  static const _minGroupSlotWidth = _barWidth + _groupsSpace;
  // Larghezza della colonna fissa dell'asse Y in `buildAxisOnly()` (modalità
  // scroll orizzontale): deve corrispondere esattamente al `reservedSize`
  // passato a `_valueLeftAxisTitles` in ENTRAMBI i percorsi di rendering
  // (`buildPlot`/`buildAxisOnly`) di questo grafico — bug reale corretto qui
  // (40 vs 52, vedi CLAUDE.md), non un'ipotesi: se in futuro serve un valore
  // diverso dal default di `_valueLeftAxisTitles`, va cambiato qui e passato
  // esplicitamente a entrambe le chiamate sotto, mai lasciato disallineato.
  static const _leftAxisWidth = 40.0;
  static const _rightFadeWidth = 28.0;

  final _scrollController = ScrollController();

  // true finché non si è scrollato fino in fondo — nasconde la dissolvenza
  // di bordo destro non appena non c'è più altro da scorrere, invece di
  // lasciarla sempre visibile come indicatore statico.
  bool _showRightFade = true;

  List<DateTime> _periodiCorrenti = const [];

  @override
  void Function(String label)? get onVisibleRangeChanged =>
      widget.onVisibleRangeChanged;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final showFade = position.pixels < position.maxScrollExtent - 1;
    if (showFade != _showRightFade) {
      setState(() => _showRightFade = showFade);
    }
    reportVisibleRange(
      controller: _scrollController,
      periodi: _periodiCorrenti,
      slotWidth: _minGroupSlotWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final buste = widget.buste;
    if (buste.isEmpty) {
      return SizedBox(
        height: 180,
        child: _NoDataMessage(busteNonConfermate: widget.busteNonConfermate),
      );
    }

    final barColor = CupertinoDynamicColor.resolve(
        BustePagaStatisticheScreen._straordinarioColor, context);
    final gridColor =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context)
            .withValues(alpha: 0.18);
    final labelColor =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);

    // Griglia continua (mensile o trimestrale a seconda dell'aggregazione),
    // stesso meccanismo di `_NettoChart`: un mese/trimestre senza dati
    // resta un buco visibile (nessuna barra disegnata per quello slot)
    // invece di sparire silenziosamente avvicinando le barre dei
    // mesi/trimestri adiacenti come se fossero consecutivi.
    // Decisione basata sull'ampiezza temporale REALE dei dati (senza
    // l'estensione a `estendiFinoA`), non su quella estesa: estendere la
    // griglia fino a oggi allunga di uno slot vuoto ogni mese che passa
    // senza nuove buste paga, e se la decisione di aggregare si basasse su
    // quella lunghezza estesa l'aggregazione trimestrale scatterebbe da
    // sola col solo passare del tempo, senza che l'utente importi nulla.
    final grigliaMensileReale = _grigliaMensile(buste);
    // Decisione basata sull'ampiezza temporale reale coperta dalla griglia
    // (numero di slot mensili, buchi inclusi), non sul numero di buste paga
    // confermate: un archivio con molti mesi mancanti/non confermati ma che
    // copre un arco di molti anni renderizzerebbe altrimenti una griglia
    // mensile non aggregata su molti slot, con uno scroll orizzontale molto
    // lungo — in contrasto con l'intento della soglia (vedi doc su
    // `_quarterlyAggregationThreshold`).
    final aggregato =
        grigliaMensileReale.length > _quarterlyAggregationThreshold;
    // Griglia effettivamente renderizzata (estesa fino a `estendiFinoA`):
    // se non serve aggregare per trimestre, riusa quella reale già
    // calcolata solo quando coincide (nessuna estensione applicabile),
    // altrimenti ricalcola con l'estensione — evita un ricalcolo superfluo
    // nel caso comune in cui `estendiFinoA` non estende oltre i dati reali.
    final grigliaMensile = aggregato
        ? const <({DateTime periodo, BustaPaga? busta})>[]
        : _grigliaMensile(buste, estendiFinoA: widget.estendiFinoA);
    // L'asse X va dal mese/trimestre più vecchio del periodo filtrato (prima
    // barra a sinistra) al più recente (verso destra) — cronologico
    // CRESCENTE, come gli altri grafici della schermata (Netto/Lordo).
    // `_grigliaMensile`/`_grigliaTrimestrale` producono entrambe una
    // griglia continua in questo stesso ordine (compresi i buchi), quindi
    // vengono usate direttamente senza ulteriore riordino.
    final punti = aggregato
        ? _grigliaTrimestrale(buste, estendiFinoA: widget.estendiFinoA)
        : [
            for (final g in grigliaMensile)
              (periodo: g.periodo, totale: g.busta?.straordinari),
          ];
    final shortLabelBuilder = aggregato ? _trimestreLabel : meseAxisLabel;
    _periodiCorrenti = [for (final p in punti) p.periodo];

    final maxValue = punti.fold<double>(
        0, (max, p) => (p.totale ?? 0) > max ? p.totale! : max);
    final maxIndex =
        punti.indexWhere((p) => p.totale != null && p.totale == maxValue);
    final straordinarioAxisMax = maxValue <= 0 ? 1.0 : maxValue * 1.2;
    final step = _niceStep(straordinarioAxisMax, minStep: 1);
    final bounds = _niceAxisBounds(0, straordinarioAxisMax, step: step);

    // Ultimo indice con un dato reale (`totale != null`): i buchi INTERNI
    // alla storia (mesi mai confermati fra due mesi con dati) restano
    // "compressi via" come prima, ma tutti gli slot DOPO questo indice (la
    // coda aggiunta da `estendiFinoA`, sempre priva di dati per definizione)
    // ricevono comunque uno slot/etichetta — altrimenti l'estensione fino al
    // mese corrente reale (vedi doc di `_grigliaMensile`) resterebbe invisibile
    // con `BarChartAlignment.spaceEvenly`. -1 se `punti` non ha alcun dato.
    final ultimoDatoIndex = punti.lastIndexWhere((p) => p.totale != null);
    bool includiSlot(int i) => punti[i].totale != null || i > ultimoDatoIndex;

    Widget buildPlot({required double width, required bool showLeftAxis}) {
      return SizedBox(
        width: width,
        child: Stack(
          children: [
            BarChart(
              BarChartData(
                minY: bounds.min,
                maxY: bounds.max,
                groupsSpace: _groupsSpace,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: gridColor, strokeWidth: 0.5),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: showLeftAxis
                      ? _valueLeftAxisTitles(
                          labelColor: labelColor,
                          interval: step,
                          reservedSize: _leftAxisWidth,
                        )
                      : const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: _periodoBottomAxisTitles(
                    periodi: [for (final p in punti) p.periodo],
                    labelColor: labelColor,
                    shortLabelBuilder: shortLabelBuilder,
                  ),
                ),
                // Nessuna interazione al tocco (vedi doc di libreria su
                // `_StraordinarioChart`): `enabled: false` disattiva sia il
                // tooltip nativo sia qualunque callback di tap/hover.
                barTouchData: BarTouchData(enabled: false),
                barGroups: [
                  for (var i = 0; i < punti.length; i++)
                    if (includiSlot(i))
                      BarChartGroupData(
                        x: i,
                        barsSpace: 2,
                        barRods: [
                          BarChartRodData(
                            toY: punti[i].totale ?? 0,
                            color: i == maxIndex
                                ? barColor
                                : barColor.withValues(alpha: 0.55),
                            width: _barWidth,
                            borderRadius:
                                BorderRadius.circular(AppRadius.small / 2),
                          ),
                        ],
                      ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    Widget buildAxisOnly() {
      return SizedBox(
        width: _leftAxisWidth,
        child: BarChart(
          BarChartData(
            minY: bounds.min,
            maxY: bounds.max,
            barGroups: const [],
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false, reservedSize: 22)),
              leftTitles: _valueLeftAxisTitles(
                labelColor: labelColor,
                interval: step,
                reservedSize: _leftAxisWidth,
              ),
            ),
          ),
        ),
      );
    }

    // `SizedBox(height: 180, ...)` esplicito attorno al `LayoutBuilder`:
    // il ramo "archivio vuoto" sopra usa la stessa altezza fissa, ma questo
    // ramo con dati reali ne era rimasto privo dopo il redesign "Pulse"
    // 2026-08-30 — prima di quel redesign `_ChartCard` avvolgeva SEMPRE
    // `chart` in un `SizedBox(height: 180, ...)` uniforme per tutti e tre i
    // grafici, ma la nuova `_ChartCard` (vedi sopra) passa `widget.chart`
    // così com'è, e solo il grafico Netto/Lordo si è portato dietro
    // un'altezza fissa propria. Senza un limite esplicito qui,
    // `LayoutBuilder`/`BarChart` ricevono un vincolo di altezza ILLIMITATO
    // dalla `Column` di `PulseSurface` dentro lo `SliverToBoxAdapter` (che
    // non vincola l'altezza dei figli) — bug reale riprodotto e corretto
    // qui, non un'ipotesi: fl_chart usa a sua volta un `LayoutBuilder` +
    // `Stack` interni (`AxisChartScaffoldWidget`) che assumono un'altezza
    // FINITA per posizionare gli assi; con altezza infinita il layout del
    // renderer del grafico fallisce a metà (un `RenderBox` resta senza
    // dimensione assegnata), il che in questa versione di Flutter/fl_chart
    // si manifesta come un "Null check operator used on a null value" che
    // si ripete a ogni frame (l'animazione implicita di `BarChart` continua
    // a ritentare il rebuild) invece di un errore di asserzione più
    // esplicito sui vincoli illimitati.
    return SizedBox(
      height: 180,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final contentWidth = punti.length * _minGroupSlotWidth;
          final needsScroll = contentWidth > viewportWidth - _leftAxisWidth;

          if (!needsScroll) {
            // Nessuno scroll necessario: l'intero range è già visibile per
            // intero, l'etichetta "in vista" copre subito tutto lo storico
            // filtrato senza aspettare un evento di scroll.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              reportVisibleRange(
                controller: _scrollController,
                periodi: _periodiCorrenti,
                slotWidth: _minGroupSlotWidth,
              );
            });
            return buildPlot(width: viewportWidth, showLeftAxis: true);
          }

          scheduleInitialScrollToEnd(
            _scrollController,
            periodi: _periodiCorrenti,
            slotWidth: _minGroupSlotWidth,
          );

          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildAxisOnly(),
              Expanded(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) {
                    final fadeWidth = _showRightFade ? _rightFadeWidth : 0.0;
                    final stop = 1 - (fadeWidth / rect.width).clamp(0.0, 1.0);
                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: const [
                        CupertinoColors.white,
                        CupertinoColors.white,
                        CupertinoColors.transparent,
                      ],
                      stops: [0.0, stop, 1.0],
                    ).createShader(rect);
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: buildPlot(width: contentWidth, showLeftAxis: false),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
