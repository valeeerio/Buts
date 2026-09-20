import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/busta_paga_formatting.dart';
import 'swipe_delete_background.dart';

/// Campo di testo numerico compatto, senza bordo/riempimento proprio (si
/// appoggia sopra il vetro della card ospitante), stile allineato al valore
/// che sostituisce. Riusato da `BustaPagaStatRow`, `BustaPagaMaturazioniSection`
/// e da `TrattenutaEditRow` in dettaglio/form busta paga.
///
/// Con `prefix` (es. "€ " nella statistica Lordo e nelle trattenute) o
/// `suffix` (es. " h" nella statistica Straordinari, in ore e non in euro),
/// il blocco "prefisso/suffisso + campo" si dimensiona sul proprio contenuto
/// (`IntrinsicWidth`, non una larghezza fissa arbitraria): entrare in
/// modifica non deve introdurre alcun gap visibile tra simbolo e numero
/// rispetto alla vista di sola lettura (che è un unico `Text` con
/// spaziatura naturale). `IntrinsicWidth` qui è sicuro: entrambi gli usi
/// attuali vivono dentro un `Expanded`/`Center` a larghezza già vincolata,
/// non dentro un `LayoutBuilder` a constraints illimitate (il bug storico
/// documentato altrove nel progetto riguardava tutt'altro contesto).
/// `rowAlignment` permette di riprodurre esattamente lo stesso allineamento
/// della corrispondente vista di sola lettura — centrato in tutti gli usi
/// attuali — l'unica differenza visibile tra vista e modifica deve restare
/// "il testo è ora in un campo tappabile", non lo spostamento del blocco.
Widget inlineNumberField(
  TextEditingController controller, {
  TextStyle? style,
  String? prefix,
  String? suffix,
  MainAxisAlignment rowAlignment = MainAxisAlignment.center,
}) {
  return Builder(
    builder: (context) {
      final textPrimary =
          CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
      final resolvedStyle = (style ?? AppTextStyles.pulseDisplaySmall).copyWith(
        color: textPrimary,
        fontWeight: style == null ? FontWeight.w400 : style.fontWeight,
      );
      final field = CupertinoTextField(
        controller: controller,
        placeholder: '0',
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        // Livello 1 della validazione numerica (vedi
        // `isValidItalianNumberField`): filtra in scrittura solo cifre e
        // virgola, MAI il punto (la convenzione dell'app è sempre virgola
        // decimale — un punto digitato per errore, es. formato USA "12.5",
        // verrebbe altrimenti interpretato come separatore delle migliaia e
        // gonfierebbe il valore di 10 volte, vedi doc di
        // `isValidItalianNumberField`) né lettere (che azzererebbero
        // silenziosamente il valore al salvataggio). Blocca a monte quello
        // che la validazione al salvataggio (livello 2, rete di sicurezza per
        // un eventuale incolla che bypassa questo filtro su alcune
        // piattaforme) segnala esplicitamente — bug reale corretto qui, non
        // un'ipotesi.
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
        decoration: const BoxDecoration(),
        padding: EdgeInsets.zero,
        style: resolvedStyle,
      );
      if (prefix == null && suffix == null) return field;
      // `IntrinsicWidth` invece di una larghezza fissa: il campo si
      // dimensiona sul testo digitato, come farebbe il `Text` di sola
      // lettura che sostituisce. Con `mainAxisSize.min` il blocco
      // "prefisso/suffisso + campo" resta un'unica unità di larghezza nota,
      // sicura da centrare o allineare a destra nella riga ospitante.
      final row = Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: rowAlignment,
        children: [
          if (prefix != null) Text(prefix, style: resolvedStyle),
          IntrinsicWidth(child: field),
          if (suffix != null) Text(suffix, style: resolvedStyle),
        ],
      );
      // `FittedBox(fit: scaleDown)` SOLO in questo ramo (prefisso/suffisso +
      // `IntrinsicWidth`, l'unico che può eccedere la larghezza disponibile):
      // valori a 4 cifre col prefisso valuta (es. "€ 1.500,00", "− € 1.500,00"
      // — retribuzione ordinaria di un mese pieno, scenario mainstream, non
      // un caso limite) possono superare la colonna disponibile su schermi
      // stretti (iPhone SE-class, ~307px di larghezza di contenuto reale)
      // anche dopo aver ottimizzato il flex ratio delle colonne ospitanti
      // (vedi `voce_competenza_edit_row.dart`/`busta_paga_competenze_
      // section.dart`) — bug reale corretto qui, non un'ipotesi. `scaleDown`
      // riduce il font SOLO quando il contenuto è realmente più largo dello
      // spazio disponibile, mai lo ingrandisce: il caso comune (valori a 3
      // cifre) resta invariato, a piena leggibilità. Il campo dentro
      // `IntrinsicWidth` resta interattivo (tap/cursore/focus): `FittedBox`
      // trasforma anche l'hit-testing, non solo il painting.
      return FittedBox(fit: BoxFit.scaleDown, child: row);
    },
  );
}

/// Riga di trattenuta in editing: chiave + importo come controller separati.
/// `id` è una chiave stabile e univoca per riga (indipendente dall'indice,
/// che cambia quando si rimuove una riga precedente), usata da `Dismissible`
/// per lo swipe-to-delete.
class TrattenutaEditRow {
  static int _nextId = 0;

  final int id;
  final TextEditingController chiave;
  final TextEditingController importo;

  /// `true` se il valore ORIGINALE di questa trattenuta (al momento della
  /// costruzione della riga) era negativo — un conguaglio/storno A CREDITO
  /// del dipendente, vedi `trattenutaPrefix`. Caso raro e MAI digitato
  /// direttamente dall'utente: nasce dalla riga ARR. PRECED./ARR. ATTUALE
  /// del cedolino, calcolata dal parser (vedi `_trattenuteDaCoordinate`/
  /// `chiaveArrotondamento` in `busta_paga_regex_parser.dart`).
  ///
  /// Il controller [importo] mostra e fa digitare SEMPRE e SOLO il valore
  /// ASSOLUTO — esattamente come la vista di sola lettura (`formatTrattenuta`,
  /// che applica `value.abs()` dentro `formatEuro`) — mentre il segno resta
  /// tracciato QUI, separato dal testo, e va riapplicato leggendo
  /// [valoreConSegno]: prima di questo fix il controller veniva precompilato
  /// col valore CON segno (es. "-0,14") e il widget anteponeva comunque un
  /// prefisso "+"/"−" calcolato dallo stesso segno, producendo un doppio
  /// segno in editing ("+ € -0,14") che la sola lettura non mostra mai — bug
  /// reale corretto qui, non un'ipotesi. Catturato una sola volta alla
  /// costruzione della riga, mai ricalcolato dal testo digitato in [importo].
  bool negativo;

  /// [importo] è il valore CON SEGNO originale (es. -0.14 per un conguaglio a
  /// credito), `null` per una riga nuova/vuota (bottone "+ Aggiungi voce") —
  /// vedi la doc su [negativo] per come viene scomposto in segno/valore
  /// assoluto.
  TrattenutaEditRow({String chiave = '', double? importo})
      : id = _nextId++,
        chiave = TextEditingController(text: chiave),
        negativo = importo != null && importo < 0,
        importo = TextEditingController(
          text: importo == null ? '' : formatEuro(importo.abs()),
        );

  /// Valore "vero" della trattenuta, col segno di [negativo] riapplicato al
  /// valore assoluto attualmente digitato in [importo] — unico punto da cui
  /// leggere il valore per salvataggio/calcoli live (mai
  /// `parseItalianNumber(importo.text)` da solo, che perderebbe il segno).
  /// `.abs()` sul testo digitato è una rete di sicurezza: il campo non
  /// impedisce comunque di incollare/digitare un "-" (nessun
  /// `inputFormatters` dedicato), un eventuale segno digitato per errore non
  /// deve poter invertire due volte il segno finale.
  double get valoreConSegno {
    final assoluto = parseItalianNumber(importo.text).abs();
    return negativo ? -assoluto : assoluto;
  }

  void dispose() {
    chiave.dispose();
    importo.dispose();
  }
}

/// Riga editabile di trattenuta: chiave + importo come campi di testo,
/// stesso layout a due colonne label/valore della vista di sola lettura. La
/// rimozione avviene via swipe verso sinistra (stesso pattern usato per
/// eliminare una busta paga in `BusteePagaArchivioView`), senza alert di
/// conferma: qui si rimuove solo una riga dallo stato locale di
/// modifica/import, ancora reversibile con "Annulla".
Widget trattenutaEditRow(TrattenutaEditRow row,
    {required VoidCallback onDismissed}) {
  return Dismissible(
    key: ValueKey(row.id),
    direction: DismissDirection.endToStart,
    onDismissed: (_) => onDismissed(),
    background: const SwipeDeleteBackground(radius: AppRadius.pulseSmall),
    child: Builder(
      builder: (context) {
        final textPrimary =
            CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
          child: Row(
            children: [
              Expanded(
                // Flex 5:4 (non più 3:2): l'aumento di `pulseDisplaySmall` da
                // 15 a 16px (vedi CLAUDE.md/app_text_styles.dart) faceva
                // andare in overflow di alcuni px la colonna importo su
                // larghezze strette — stesso rapporto applicato anche in
                // `trattenutaReadOnlyRow` per non alterare l'allineamento tra
                // vista e modifica (requisito non negoziabile).
                flex: 5,
                // `maxLines: null` (nessun limite, cresce verticalmente) invece
                // del default di `CupertinoTextField` (1 riga, che TRONCA
                // orizzontalmente il testo che eccede la larghezza) — la vista
                // di sola lettura (`Text` senza `maxLines`, in
                // `busta_paga_detail_screen.dart`) va invece a capo su più
                // righe per le chiavi lunghe (es. "FONDO INTEGR. SALARIALE -
                // FIS", "Differenza di arrotondamento (mese
                // precedente/attuale)"): senza questo, entrare in modifica
                // tagliava silenziosamente il testo visibile e cambiava
                // l'altezza della riga — violava il requisito "modifica
                // inline" non negoziabile (vedi CLAUDE.md), bug reale corretto
                // qui, non un'ipotesi.
                child: CupertinoTextField(
                  controller: row.chiave,
                  placeholder: 'Voce',
                  maxLines: null,
                  decoration: const BoxDecoration(),
                  padding: EdgeInsets.zero,
                  style: AppTextStyles.pulseBodyEmphasis.copyWith(
                    color: textPrimary,
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                // A differenza delle altre statistiche, l'importo di una
                // trattenuta NON è sempre positivo: il parser regex può
                // riconoscere un valore negativo (conguaglio/storno a
                // credito del dipendente, vedi commento su
                // `_rigaTrattenutaVerificata`/`_trattenuteDaCoordinate` in
                // `busta_paga_regex_parser.dart`). Il segno non è mai
                // digitato dall'utente: è catturato una sola volta in
                // `row.negativo` alla costruzione della riga (vedi la sua
                // doc), non ricalcolato ad ogni keystroke sul testo digitato
                // in `row.importo` — che mostra sempre e solo il valore
                // ASSOLUTO, esattamente come la vista di sola lettura
                // (`formatTrattenuta`). Il prefisso "− €"/"+ €" riflette
                // quindi sempre lo stesso segno mostrato in lettura, per
                // costruzione (requisito "modifica inline" non negoziabile,
                // vedi CLAUDE.md) — non più un doppio segno "+ € -0,14"
                // quando il valore digitato coincide col testo con segno del
                // controller (bug reale corretto qui, non un'ipotesi).
                child: Center(
                  child: inlineNumberField(
                    row.importo,
                    prefix: trattenutaPrefix(row.valoreConSegno),
                    style: AppTextStyles.pulseDisplaySmall,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Riga di trattenuta in sola lettura: stesso layout a due colonne
/// label/valore della versione editabile (`trattenutaEditRow`), condivisa tra
/// dettaglio busta paga e form di import.
Widget trattenutaReadOnlyRow(String label, String value) {
  return Builder(
    builder: (context) {
      final textPrimary =
          CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.smPlus),
        child: Row(
          children: [
            Expanded(
              // Stesso flex 5:4 di `trattenutaEditRow` (vedi commento lì): la
              // vista di sola lettura deve restare allineata pixel-per-pixel
              // alla modifica.
              flex: 5,
              child: Text(
                label,
                style: AppTextStyles.pulseBodyEmphasis.copyWith(
                  color: textPrimary,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: AppTextStyles.pulseDisplaySmall.copyWith(
                  color: textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
