import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_sticky_header/flutter_sticky_header.dart';

import '../../models/busta_paga.dart';
import '../../providers/buste_paga_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/busta_paga_formatting.dart';
import '../../widgets/app_alert_dialog.dart';
import '../../widgets/busta_paga_list_item.dart';
import '../../widgets/busta_paga_summary_hero.dart';
import '../../widgets/custom_illustration.dart';
import '../../widgets/pulse_icon.dart';
import '../../widgets/pulse_surface.dart';
import '../../widgets/spring_button.dart';
import '../../widgets/staggered_fade_slide_in.dart';
import '../../widgets/swipe_delete_background.dart';
import '../../widgets/value_tile.dart';

/// Filtra le buste paga per periodo (nome mese, anno e/o etichetta di tipo,
/// case-insensitive). Query vuota (dopo trim) restituisce l'elenco
/// invariato. Confronta con [bustaPagaPeriodoDisplay] (non [periodoLabel]):
/// per le mensili le due funzioni producono la stessa stringa ("Agosto
/// 2026"), ma solo [bustaPagaPeriodoDisplay] include l'etichetta di tipo per
/// 13esima/14esima ("13esima 2026") — [periodoLabel] da sola non faceva mai
/// matchare una ricerca per "13esima"/"14esima", bug reale corretto qui, non
/// un'ipotesi.
List<BustaPaga> _filtered(List<BustaPaga> sorted, String query) {
  final normalized = query.toLowerCase().trim();
  if (normalized.isEmpty) return sorted;
  return sorted
      .where(
          (b) => bustaPagaPeriodoDisplay(b).toLowerCase().contains(normalized))
      .toList();
}

/// Raggruppa per anno preservando l'ordine decrescente dell'elenco in
/// ingresso (già ordinato per periodo decrescente).
Map<int, List<BustaPaga>> _groupByYear(List<BustaPaga> sorted) {
  final Map<int, List<BustaPaga>> byYear = {};
  for (final bustaPaga in sorted) {
    byYear.putIfAbsent(bustaPaga.periodo.year, () => []).add(bustaPaga);
  }
  return byYear;
}

/// Contenuto della tab "Archivio" della sezione Buste Paga: card in
/// evidenza sull'ultima busta paga + elenco raggruppato per anno (header
/// sticky, stile Contatti/Mail). Estratto da `BustePagaSectionScreen` per
/// fare spazio alla sotto-navigazione Archivio/Statistiche. La ricerca per
/// periodo è pilotata dall'esterno (campo minimale nel titolo di
/// `BustePagaSectionScreen`): quando `searchActive` è vero l'hero
/// dell'ultima busta paga si nasconde per fare spazio all'elenco filtrato.
class BustePagaArchivioView extends ConsumerStatefulWidget {
  final ValueChanged<BustaPaga> onOpenDetail;
  final VoidCallback onAdd;
  final bool searchActive;
  final String query;

  const BustePagaArchivioView({
    super.key,
    required this.onOpenDetail,
    required this.onAdd,
    required this.searchActive,
    required this.query,
  });

  @override
  ConsumerState<BustePagaArchivioView> createState() =>
      _BustePagaArchivioViewState();
}

class _BustePagaArchivioViewState extends ConsumerState<BustePagaArchivioView> {
  /// Anni con la sotto-sezione "Extra" (13esima/14esima) espansa — vuoto di
  /// default, quindi tutte chiuse all'apertura dell'Archivio.
  final Set<int> _extraEspansi = {};

  /// Traccia, per ogni anno, se l'ultima build aveva la sotto-sezione
  /// "Extra" forzata-espansa (nessuna mensile in questa vista, vedi
  /// [_espansaExtra]). Serve a rilevare la transizione "solo extra" → "extra
  /// + mensili": in quel momento l'anno va aggiunto a [_extraEspansi] così
  /// il nuovo wrapper animato monta già espanso invece di collassare di
  /// scatto (vedi [_espansaExtra]).
  final Map<int, bool> _extraForzataEspansa = {};

  /// Durata/curva condivise dall'apertura/chiusura della sotto-sezione
  /// "Extra" (vedi [_extraSliver]) e dalla rotazione della freccetta (vedi
  /// [_extraToggle]): stesso valore per entrambe così i due effetti si
  /// percepiscono come un unico gesto, non due animazioni scollegate.
  static const _extraAnimationDuration = Duration(milliseconds: 260);
  static const _extraAnimationCurve = Curves.easeOutCubic;

  final _scrollController = ScrollController();

  // true finché non si è scrollato fino in fondo alla lista — nasconde la
  // dissolvenza di fondo (ShaderMask) non appena non c'è più altro sotto:
  // altrimenti, essendo un gradiente statico legato al viewport e non alla
  // posizione di scroll, l'ultima busta paga (o l'intera lista se sta tutta
  // a schermo senza bisogno di scroll) restava sempre semi-trasparente,
  // anche quando non c'era nient'altro da rivelare scorrendo oltre.
  bool _showBottomFade = true;

  /// Indice globale/continuo (non locale ad ogni sotto-sezione) di ogni
  /// busta paga nell'ordine in cui compare dall'alto verso il basso in
  /// tutta la colonna scrollabile (Extra e mensili di tutti gli anni
  /// visibili) — usato da [StaggeredFadeSlideIn] per lo scaglionamento
  /// dell'animazione d'ingresso. Ricalcolata ad ogni `build` in
  /// [_computeGlobalRowIndex] **prima** di costruire gli sliver, così resta
  /// coerente anche se `SliverList.separated`/`itemBuilder` costruiscono le
  /// righe in modo lazy/non sequenziale (l'ordine viene deciso qui, non
  /// dedotto dall'ordine di chiamata dei builder).
  Map<String, int> _globalRowIndex = const {};

  /// Id delle buste paga la cui animazione di ingresso ([StaggeredFadeSlideIn]
  /// in [_bustaPagaRow]) è già stata giocata almeno una volta in questa
  /// istanza dello `State`. `SliverList.separated`/`itemBuilder` costruiscono
  /// le righe in modo lazy: quando una riga esce dal viewport durante lo
  /// scroll e vi rientra, Flutter distrugge e ricrea il suo `State` (anche
  /// con una `Key` stabile, che protegge solo dal riordino/dalla rimozione
  /// nello stesso frame, non dalla ricostruzione lazy legata al viewport) —
  /// senza questo tracking, [StaggeredFadeSlideIn] rigiocherebbe da capo
  /// fade+slide ad ogni rientro, dando l'impressione che i dati "arrivino"
  /// di nuovo durante lo scroll — anche se in realtà erano già arrivate
  /// nello stesso build (il caricamento iniziale dal DB, quello vero, è
  /// asincrono: vedi `BustePagaNotifier._initialize`/
  /// `busteCaricamentoCompletatoProvider` in `busteRepositoryProvider`, e il
  /// guard su quel flag in [_buildBody]/`_EmptyState` più sotto in questo
  /// file). Passato direttamente a
  /// [StaggeredFadeSlideIn] (`playId`/`playedIds`), che decide/marca in
  /// `initState` — non qui in `_bustaPagaRow`/`build`: `SliverList`/
  /// `SliverStickyHeader` possono invocare l'`itemBuilder` più di una volta
  /// per la stessa riga durante un singolo ciclo di layout/misurazione senza
  /// creare una nuova `Element`/`State`, quindi marcare "già animato" a
  /// livello di chiamata dell'`itemBuilder` lo farebbe apparire "già visto"
  /// prima ancora che la riga sia stata effettivamente disegnata la prima
  /// volta (bug reale osservato scrivendo il test di questo fix, non
  /// un'ipotesi) — `initState` gira invece esattamente una volta per ogni
  /// vera istanza dello `State`, la granularità corretta.
  final Set<String> _idGiaAnimati = {};

  /// `playId` sintetici (non id di buste paga reali) per far rientrare
  /// l'hero dell'ultima busta paga e la riga di tessere
  /// Ferie/Permessi/Ex festività nella stessa cascata/nello stesso
  /// [_idGiaAnimati] delle righe elenco (vedi [build]): stringhe che non
  /// collidono mai con un id reale (`uuid`), così l'intera sequenza
  /// header→elenco gioca una sola volta per sessione app, con la stessa
  /// logica "già animato" già corretta in `initState` di
  /// [StaggeredFadeSlideIn].
  static const _headerHeroPlayId = 'header-hero';
  static const _headerRingsPlayId = 'header-rings';

  /// Calcola [_globalRowIndex] per la build corrente: stesso ordine con cui
  /// [_yearSliver] disegna le righe (per ogni anno decrescente, prima
  /// "Extra" ordinata per tipo poi le mensili in ordine cronologico
  /// decrescente già garantito da `sorted`).
  ///
  /// `startIndex` fa proseguire la numerazione dopo gli elementi
  /// dell'header/hero (vedi [_headerHeroIndex]/[_headerRingsIndex] in
  /// [build]), così l'intera cascata — header poi elenco — è un'unica
  /// sequenza continua dall'alto verso il basso invece di due animazioni
  /// scollegate: `0` quando l'header non è mostrato (ricerca attiva), così
  /// l'elenco riparte da zero senza un ritardo iniziale ingiustificato.
  void _computeGlobalRowIndex(
      List<int> anni, Map<int, List<BustaPaga>> byYear, int startIndex) {
    final index = <String, int>{};
    var i = startIndex;
    for (final anno in anni) {
      final buste = byYear[anno]!;
      final extra = buste.where((b) => b.tipo != TipoBustaPaga.mensile).toList()
        ..sort((a, b) => a.tipo.index.compareTo(b.tipo.index));
      final normali =
          buste.where((b) => b.tipo == TipoBustaPaga.mensile).toList();
      for (final bustaPaga in [...extra, ...normali]) {
        index[bustaPaga.id] = i;
        i++;
      }
    }
    _globalRowIndex = index;
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateBottomFade);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateBottomFade);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateBottomFade() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final showFade = position.pixels < position.maxScrollExtent - 1;
    if (showFade != _showBottomFade) {
      setState(() => _showBottomFade = showFade);
    }
  }

  /// Alert di conferma prima di eliminare davvero, mostrato dallo
  /// swipe-to-delete sia sull'hero sia sulle righe dell'elenco.
  Future<bool> _confirmaEliminazione(
    BuildContext context,
    BustaPaga bustaPaga,
  ) async {
    final labelSecondary =
        CupertinoDynamicColor.resolve(AppColors.labelSecondary, context);
    final destructive =
        CupertinoDynamicColor.resolve(AppColors.systemRed, context);
    final risultato = await showAppAlertDialog<bool>(
      context: context,
      title: 'Elimina busta paga',
      message: 'Sei sicuro di voler eliminare la busta paga di '
          '${bustaPagaPeriodoDisplay(bustaPaga)}?',
      actions: [
        AppAlertAction(
          pulseGlyph: PulseIconGlyph.close,
          label: 'Annulla',
          color: labelSecondary,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        AppAlertAction(
          pulseGlyph: PulseIconGlyph.delete,
          label: 'Elimina',
          color: destructive,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
    return risultato ?? false;
  }

  /// Rimuove una busta paga gestendo l'eventuale fallimento della scrittura
  /// Drift: `remove` fa già il revert ottimistico dello stato in caso di
  /// errore (la busta paga ricompare nell'elenco). Ritorna `true`/`false` in
  /// base all'esito — richiamata da `confirmDismiss` (vedi
  /// [_confermaEElimina]), non più da `onDismissed`: un `Dismissible` che
  /// anima via la riga (`onDismissed`) e poi la fa ricomparire per un
  /// rollback ottimistico fallito genera l'errore Flutter "A dismissed
  /// Dismissible widget is still part of the tree" — bug reale corretto qui,
  /// non un'ipotesi. Ritornando `false` da `confirmDismiss` in caso di
  /// errore, `Dismissible` non rimuove mai il widget dall'albero (anima la
  /// riga di ritorno in posizione), restando sempre coerente con lo stato.
  Future<bool> _removeBustaPaga(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    try {
      await ref.read(busteRepositoryProvider.notifier).remove(id);
      return true;
    } catch (_) {
      if (!context.mounted) return false;
      final accent =
          CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
      showAppAlertDialog<void>(
        context: context,
        title: 'Eliminazione non riuscita',
        message: 'Impossibile eliminare la busta paga, riprova.',
        actions: [
          AppAlertAction(
            pulseGlyph: PulseIconGlyph.checkmark,
            label: 'OK',
            color: accent,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
      return false;
    }
  }

  /// `confirmDismiss` condiviso da hero e righe elenco: conferma esplicita
  /// (alert), poi l'eliminazione vera e propria — entrambe le fasi sono
  /// completate PRIMA che `Dismissible` rimuova il widget dall'albero (vedi
  /// doc di [_removeBustaPaga] sul perché non si usa più `onDismissed`).
  Future<bool> _confermaEElimina(
    BuildContext context,
    WidgetRef ref,
    BustaPaga bustaPaga,
  ) async {
    final confermato = await _confirmaEliminazione(context, bustaPaga);
    if (!confermato) return false;
    if (!context.mounted) return false;
    return _removeBustaPaga(context, ref, bustaPaga.id);
  }

  /// Singola riga busta paga (swipe-to-delete + tap per il dettaglio),
  /// fattorizzata perché sia [_bustePagaSliverList] (mensilità) sia
  /// [_extraSliver] (sotto-sezione "Extra") disegnano esattamente questa
  /// riga — stessa `ValueKey`, stesso `Dismissible`/conferma di eliminazione
  /// in entrambi i casi.
  Widget _bustaPagaRow(
      BuildContext context, WidgetRef ref, BustaPaga bustaPaga) {
    final riga = Dismissible(
      key: ValueKey('row-${bustaPaga.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confermaEElimina(context, ref, bustaPaga),
      background: const SwipeDeleteBackground(radius: AppRadius.pulseSmall),
      child: BustaPagaListItem(
        bustaPaga: bustaPaga,
        onTap: () => widget.onOpenDetail(bustaPaga),
      ),
    );

    // Vedi doc di [_idGiaAnimati]: solo la primissima volta che lo `State`
    // di questo `StaggeredFadeSlideIn` viene creato per questo id gioca
    // l'animazione di ingresso (deciso in `initState`, non qui) — le
    // ricostruzioni successive dello stesso `State` mostrano subito la riga
    // nella sua posizione/opacità finale.
    final globalIndex = _globalRowIndex[bustaPaga.id] ?? 0;
    return StaggeredFadeSlideIn(
      key: ValueKey('stagger-${bustaPaga.id}'),
      index: globalIndex,
      playId: bustaPaga.id,
      playedIds: _idGiaAnimati,
      child: riga,
    );
  }

  /// Elenco (sliver) di un gruppo di buste paga: usato per le mensilità
  /// normali di un anno, che non hanno bisogno di apertura/chiusura
  /// animata (a differenza della sotto-sezione "Extra", vedi
  /// [_extraSliver]).
  Widget _bustePagaSliverList(WidgetRef ref, List<BustaPaga> buste) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.xs,
        AppSpacing.screenHorizontal,
        0,
      ),
      sliver: SliverList.separated(
        itemCount: buste.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) =>
            _bustaPagaRow(context, ref, buste[index]),
      ),
    );
  }

  /// Sotto-sezione "Extra" come singolo sliver, con apertura/chiusura
  /// animata: crescita di altezza dall'alto (`AnimatedAlign` con
  /// `heightFactor`, clippata da `ClipRect` per nascondere l'overflow oltre
  /// l'altezza corrente) + fade-in/out (`AnimatedOpacity`) + un leggero
  /// slide verticale d'ingresso (`AnimatedSlide`) — stessa
  /// `_extraAnimationDuration`/`_extraAnimationCurve` della freccetta in
  /// [_extraToggle], per un unico gesto percepito. Le righe restano sempre
  /// montate nell'albero (nessuno swap di widget tra aperto/chiuso): è
  /// questo che permette al contenuto di dissolversi visibilmente invece di
  /// sparire di scatto mentre la sezione collassa.
  ///
  /// Se `animato` è `false` (nessuna mensile in questa vista, la sezione è
  /// **sempre** espansa, vedi [_yearSliver]) la lista è mostrata
  /// direttamente senza alcun wrapper animato: niente flash di apertura
  /// quando non c'è nulla da collassare, e lo spacer verso le mensilità
  /// (`AppSpacing.md`) viene omesso perché non ci sono mensilità da cui
  /// separarsi.
  Widget _extraSliver(
    BuildContext context,
    WidgetRef ref,
    List<BustaPaga> extra, {
    required bool espansa,
    required bool animato,
  }) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        AppSpacing.xs,
        AppSpacing.screenHorizontal,
        0,
      ),
      child: Column(
        children: [
          for (var i = 0; i < extra.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _bustaPagaRow(context, ref, extra[i]),
          ],
        ],
      ),
    );

    if (!animato) {
      return SliverToBoxAdapter(child: content);
    }

    // Lo spacer verso le mensilità resta sempre presente (fuori dal blocco
    // che collassa in altezza): a differenza delle righe sopra, non deve
    // sparire con l'animazione di chiusura, altrimenti il gap tra il toggle
    // "Extra" nell'header e la prima riga mensile si riduce quando la
    // sezione è collassata.
    return SliverToBoxAdapter(
      child: Column(
        children: [
          ClipRect(
            child: AnimatedAlign(
              alignment: Alignment.topCenter,
              heightFactor: espansa ? 1.0 : 0.0,
              duration: _extraAnimationDuration,
              curve: _extraAnimationCurve,
              child: AnimatedSlide(
                offset: espansa ? Offset.zero : const Offset(0, -0.06),
                duration: _extraAnimationDuration,
                curve: _extraAnimationCurve,
                child: AnimatedOpacity(
                  opacity: espansa ? 1.0 : 0.0,
                  duration: _extraAnimationDuration,
                  curve: _extraAnimationCurve,
                  child: content,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ),
    );
  }

  /// `true` se `buste` contiene almeno una mensile (a differenza di
  /// 13esima/14esima, che sono "Extra") — determina se la sotto-sezione
  /// "Extra" ha un toggle animato o è forzata sempre espansa, vedi
  /// [_espansaExtra].
  bool _animato(List<BustaPaga> buste) =>
      buste.any((b) => b.tipo == TipoBustaPaga.mensile);

  /// Calcola se la sotto-sezione "Extra" dell'anno `anno` deve risultare
  /// espansa in questa build, gestendo la transizione "solo extra" (nessuna
  /// mensile in questa vista, forzata sempre espansa senza toggle) → "extra
  /// + mensili" (toggle animato, stato tracciato da `_extraEspansi`).
  ///
  /// Se `animato` è `false` l'anno viene marcato in
  /// [_extraForzataEspansa]. Alla prima build successiva in cui `animato`
  /// torna `true` (una mensile è stata importata per lo stesso anno), la
  /// marcatura viene rimossa e l'anno viene aggiunto a `_extraEspansi`
  /// **prima** di calcolare `espansa` — così il nuovo wrapper animato monta
  /// già espanso invece di collassare di scatto (bug reale corretto qui,
  /// non un'ipotesi, vedi CLAUDE.md/istruzioni task).
  ///
  /// Va chiamato una sola volta per anno per build, centralizzato in
  /// [_yearSection] **prima** di costruire sia [_extraToggle] sia
  /// [_yearSliver]: se venisse chiamato dentro [_yearSliver] (che è passato
  /// come argomento nominato `sliver:`, valutato dopo `header:` nell'ordine
  /// testuale del sorgente), [_extraToggle] leggerebbe lo stato di
  /// `_extraEspansi` prima della mutazione, causando un disallineamento tra
  /// la freccetta e il contenuto nel frame della transizione.
  bool _espansaExtra(int anno, bool animato) {
    if (!animato) {
      _extraForzataEspansa[anno] = true;
    } else if (_extraForzataEspansa.remove(anno) == true) {
      _extraEspansi.add(anno);
    }
    return !animato || _extraEspansi.contains(anno);
  }

  /// Contenuto (`sliver:`) di un `SliverStickyHeader` anno: le mensilità
  /// normali, poi in fondo la sotto-sezione "Extra" (13esima/14esima) se
  /// presente — header tappabile con freccetta che espande/collassa
  /// `_extraSliver(extra)` con una transizione animata (vedi
  /// [_extraSliver]), chiusa di default (`anno` non in `_extraEspansi`).
  /// Niente sticky header annidato (non supportato da
  /// `flutter_sticky_header`), tutto sotto lo stesso header "$anno".
  ///
  /// `buste` è già la lista **per questo anno nella vista corrente** (dopo
  /// un eventuale filtro di ricerca, vedi [_filtered]/`build`), non il
  /// totale assoluto dell'anno. `espansa` è calcolato esternamente da
  /// [_yearSection] (via [_espansaExtra]) e passato qui come parametro:
  /// questo metodo non muta più alcuno stato, solo disegna.
  Widget _yearSliver(BuildContext context, WidgetRef ref, int anno,
      List<BustaPaga> buste, bool espansa) {
    // Ordine fisso per tipo (13esima sempre prima della 14esima), non
    // cronologico per mese come le mensilità: il mese registrato su
    // ciascuna può variare da un anno all'altro, l'ordine per tipo resta
    // prevedibile in ogni sezione "Extra".
    final extra = buste.where((b) => b.tipo != TipoBustaPaga.mensile).toList()
      ..sort((a, b) => a.tipo.index.compareTo(b.tipo.index));
    final normali =
        buste.where((b) => b.tipo == TipoBustaPaga.mensile).toList();
    final animato = _animato(buste);

    return SliverMainAxisGroup(
      slivers: [
        if (extra.isNotEmpty)
          _extraSliver(context, ref, extra, espansa: espansa, animato: animato),
        if (normali.isNotEmpty) _bustePagaSliverList(ref, normali),
      ],
    );
  }

  /// Unico punto di ingresso per la sezione di un anno: calcola `animato`
  /// ed `espansa` **prima** di costruire `SliverStickyHeader`, poi passa
  /// `espansa` esplicitamente sia a [_extraToggle] (nell'header) sia a
  /// [_yearSliver] (nel contenuto) — evita il disallineamento tra freccetta
  /// e contenuto descritto in [_espansaExtra].
  Widget _yearSection(
      BuildContext context, WidgetRef ref, int anno, List<BustaPaga> buste) {
    final animato = _animato(buste);
    final espansa = _espansaExtra(anno, animato);
    final haExtra = buste.any((b) => b.tipo != TipoBustaPaga.mensile);

    return SliverStickyHeader(
      header: _pinnedBackground(
        context,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenHorizontal,
            AppSpacing.xs,
            AppSpacing.screenHorizontal,
            AppSpacing.smPlus,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$anno',
                  style: AppTextStyles.pulseBodyEmphasis.copyWith(
                    color: CupertinoDynamicColor.resolve(
                        AppColors.pulseTextPrimary, context),
                  ),
                ),
              ),
              // Toggle mostrato solo se l'anno ha ENTRAMBI mensili ed Extra
              // nella vista corrente: altrimenti (solo Extra, vedi
              // `_espansaExtra`) la sotto-sezione resta sempre espansa e non
              // c'è nulla da collassare — un toggle interattivo lì potrebbe
              // far ricomparire la sezione vuota che questo fix corregge.
              if (haExtra && animato) _extraToggle(context, anno, espansa),
            ],
          ),
        ),
      ),
      sliver: _yearSliver(context, ref, anno, buste, espansa),
    );
  }

  /// Toggle "Extra ⌄" (testo + `AnimatedRotation` chevron), disegnato sulla
  /// stessa riga dell'header sticky dell'anno invece che come riga a parte
  /// sopra l'elenco. `espansa` è calcolato da [_yearSection] (via
  /// [_espansaExtra]) e passato esplicitamente, così è sempre coerente col
  /// contenuto disegnato da [_yearSliver] nello stesso frame — vedi
  /// [_espansaExtra] per il perché questo calcolo non può più avvenire
  /// localmente qui o dentro [_yearSliver]. La rotazione della freccetta
  /// usa la stessa durata/curva (`_extraAnimationDuration`/
  /// `_extraAnimationCurve`) della crescita/fade della lista in
  /// [_extraSliver], così i due effetti si percepiscono come un unico
  /// gesto.
  Widget _extraToggle(BuildContext context, int anno, bool espansa) {
    final textSecondary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextSecondary, context);
    return SpringButton(
      onPressed: () => setState(() {
        if (espansa) {
          _extraEspansi.remove(anno);
        } else {
          _extraEspansi.add(anno);
        }
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Extra',
            style: AppTextStyles.pulseLabel.copyWith(color: textSecondary),
          ),
          const SizedBox(width: AppSpacing.xs),
          AnimatedRotation(
            turns: espansa ? 0.5 : 0,
            duration: _extraAnimationDuration,
            curve: _extraAnimationCurve,
            child: PulseIcon(
              glyph: PulseIconGlyph.chevronDown,
              size: 14,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buste = ref.watch(busteRepositoryProvider);
    final caricamentoCompletato =
        ref.watch(busteCaricamentoCompletatoProvider);
    final ultima = ref.watch(ultimaBustaPagaProvider);
    final sorted = [...buste]..sort((a, b) => b.periodo.compareTo(a.periodo));
    final filtered =
        widget.searchActive ? _filtered(sorted, widget.query) : sorted;
    final byYear = _groupByYear(filtered);
    final anni = byYear.keys.toList()..sort((a, b) => b.compareTo(a));
    final nessunRisultato = widget.searchActive &&
        widget.query.trim().isNotEmpty &&
        filtered.isEmpty;
    final mostraHero = !widget.searchActive && ultima != null;
    // Le righe elenco proseguono la cascata subito dopo i due elementi
    // dell'header (hero=indice 0, tessere=indice 1) quando l'header è
    // mostrato — vedi doc di [_computeGlobalRowIndex].
    _computeGlobalRowIndex(anni, byYear, mostraHero ? 2 : 0);

    // Ricontrolla dopo ogni layout (non solo sullo scroll dell'utente): il
    // contenuto della lista cambia (import/eliminazione, ricerca) e con
    // esso può cambiare se c'è ancora altro da scorrere sotto.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateBottomFade());

    return Column(
      children: [
        if (mostraHero) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenHorizontal,
              AppSpacing.sm,
              AppSpacing.screenHorizontal,
              0,
            ),
            // Primo elemento della cascata (indice 0): compare prima delle
            // righe elenco, vedi doc di [_headerHeroPlayId]/
            // [_computeGlobalRowIndex].
            child: StaggeredFadeSlideIn(
              key: const ValueKey('stagger-$_headerHeroPlayId'),
              index: 0,
              playId: _headerHeroPlayId,
              playedIds: _idGiaAnimati,
              child: Dismissible(
                key: ValueKey('hero-${ultima.id}'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confermaEElimina(context, ref, ultima),
                background:
                    const SwipeDeleteBackground(radius: AppRadius.pulse),
                child: BustaPagaSummaryHero(
                  bustaPaga: ultima,
                  onTap: () => widget.onOpenDetail(ultima),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            // Secondo elemento della cascata (indice 1): subito dopo l'hero,
            // prima dell'elenco (che riparte dall'indice 2, vedi
            // [_computeGlobalRowIndex]).
            child: StaggeredFadeSlideIn(
              key: const ValueKey('stagger-$_headerRingsPlayId'),
              index: 1,
              playId: _headerRingsPlayId,
              playedIds: _idGiaAnimati,
              child: _MaturazioniRingsRow(bustaPaga: ultima),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        Expanded(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) {
              final fadeHeight = _showBottomFade ? 120.0 : 0.0;
              final stop = 1 - (fadeHeight / rect.height).clamp(0.0, 1.0);
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
              controller: _scrollController,
              slivers: [
                if (!mostraHero)
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpacing.sm),
                  ),
                if (sorted.isEmpty && !caricamentoCompletato)
                  // Caricamento iniziale dal DB ancora in corso (vedi
                  // `busteCaricamentoCompletatoProvider`): uno stato vuoto è
                  // ancora indistinguibile da "nessuna busta paga mai
                  // importata", ma qui sappiamo che non è (ancora) certo —
                  // non mostrare l'invito ad aggiungere, che sarebbe
                  // fuorviante se sparisse una frazione di secondo dopo.
                  const SliverToBoxAdapter(child: SizedBox.shrink())
                else if (sorted.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenHorizontal,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _EmptyState(onAdd: widget.onAdd),
                    ),
                  )
                else if (nessunRisultato)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenHorizontal,
                      AppSpacing.lg,
                      AppSpacing.screenHorizontal,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _NessunRisultato(query: widget.query.trim()),
                    ),
                  )
                else
                  for (final anno in anni) ...[
                    _yearSection(context, ref, anno, byYear[anno]!),
                    if (anno != anni.last)
                      const SliverToBoxAdapter(
                        child: SizedBox(height: AppSpacing.lg),
                      ),
                  ],
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppSpacing.xl),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Sfondo "chrome" condiviso dall'header pinned dell'anno: riempimento
/// piatto a tinta piena (nessun `BackdropFilter`), coerente col materiale
/// "Pulse" bold/dark-first — sostituisce il vecchio vetro sfocato.
Widget _pinnedBackground(BuildContext context, {required Widget child}) {
  final fill =
      CupertinoDynamicColor.resolve(AppColors.pulseBackground, context);
  return DecoratedBox(
    decoration: BoxDecoration(color: fill),
    child: child,
  );
}

class _NessunRisultato extends StatelessWidget {
  final String query;

  const _NessunRisultato({required this.query});

  @override
  Widget build(BuildContext context) {
    return PulseSurface(
      borderRadius: AppRadius.pulseSmall,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            const CustomIllustration(
              variant: CustomIllustrationVariant.nessunRisultato,
              size: 72,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nessun risultato per "$query"',
              textAlign: TextAlign.center,
              style: AppTextStyles.pulseBodyEmphasis.copyWith(
                color: CupertinoDynamicColor.resolve(
                    AppColors.pulseTextPrimary, context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final onAccent =
        CupertinoDynamicColor.resolve(AppColors.pulseOnAccent, context);
    return PulseSurface(
      borderRadius: AppRadius.pulse,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            const CustomIllustration(
              variant: CustomIllustrationVariant.archivioVuoto,
              size: 132,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Nessuna busta paga in archivio',
              style: AppTextStyles.pulseBodyEmphasis.copyWith(
                color: CupertinoDynamicColor.resolve(
                    AppColors.pulseTextPrimary, context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Aggiungi la tua prima busta paga per iniziare l\'archivio.',
              textAlign: TextAlign.center,
              style: AppTextStyles.pulseBody.copyWith(
                color: CupertinoDynamicColor.resolve(
                    AppColors.pulseTextSecondary, context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Importa il PDF della tua busta paga per iniziare — servono '
              'PDF con testo selezionabile, non foto o scansioni.',
              textAlign: TextAlign.center,
              style: AppTextStyles.pulseBody.copyWith(
                color: CupertinoDynamicColor.resolve(
                    AppColors.pulseTextSecondary, context),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PulseSurface(
              filled: true,
              borderRadius: AppRadius.pulseSmall,
              onTap: onAdd,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.smPlus,
              ),
              child: Text(
                'Aggiungi busta paga',
                style: AppTextStyles.pulseBodyEmphasis.copyWith(
                  color: onAccent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Riga di 3 tessere piatte con i valori residui di Ferie/Permessi/Ex
/// festività — vedi CLAUDE.md, "Voci di competenza": nel modello dati
/// "Permessi" corrisponde ai campi `rol*`, stessa etichetta già usata da
/// `BustaPagaMaturazioniSection` nel dettaglio, non una quarta categoria
/// distinta dai ROL — per l'ultima busta paga in archivio. Una riga di 3
/// tessere `ValueTile` (`lib/widgets/value_tile.dart`, solo valore + label,
/// nessun anello di progresso), non un `GridView` 2x2: il dominio dati
/// traccia solo 3 categorie di ratei (Ferie, Permessi/ROL, Ex festività), non
/// 4 — vedi CLAUDE.md "Ferie, ROL e permessi" nel dettaglio busta paga,
/// stessa fonte di verità. `ValueTile` è condiviso anche con la card "Ferie,
/// Permessi, Ex festività" in Statistiche.
class _MaturazioniRingsRow extends StatelessWidget {
  final BustaPaga bustaPaga;

  const _MaturazioniRingsRow({required this.bustaPaga});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ValueTile(
            label: 'Ferie',
            value: formatNumber(bustaPaga.ferieResidue),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ValueTile(
            label: 'Permessi',
            value: formatNumber(bustaPaga.rolResidui),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: ValueTile(
            label: 'Ex festività',
            value: formatNumber(bustaPaga.exFestivitaResidue),
          ),
        ),
      ],
    );
  }
}
