import 'package:flutter/cupertino.dart';
import 'package:open_filex/open_filex.dart';

import '../models/busta_paga.dart';
import '../services/pdf_path_resolver.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import '../utils/busta_paga_formatting.dart';
import 'app_alert_dialog.dart';
import 'pulse_icon.dart';
import 'pulse_surface.dart';

/// Etichetta leggibile per il documento, derivata da periodo/tipo della
/// busta paga (mai il nome file grezzo, es. "1787773076927_01_2026.pdf" —
/// illeggibile per l'utente). Costruita SOPRA [periodoDisplayFor]
/// (`utils/busta_paga_formatting.dart`, stessa firma `periodo`/`tipo`) con
/// il prefisso "Cedolino " anteposto, non reimplementata da zero: così la
/// forma "13esima"/"14esima" per le mensilità aggiuntive resta
/// strutturalmente coerente con [tipoMensilitaLabel]/[periodoDisplayFor],
/// usati ovunque nel resto dell'app (`buste_paga_archivio_view.dart`, hero
/// del dettaglio) — non la forma estesa "Tredicesima"/"Quattordicesima",
/// mai usata altrove. Esempi: "Cedolino Agosto 2026" per le mensili,
/// "Cedolino 13esima 2026" per una tredicesima.
String bustaPagaDocumentoLabel({
  required DateTime periodo,
  required TipoBustaPaga tipo,
}) {
  return 'Cedolino ${periodoDisplayFor(periodo: periodo, tipo: tipo)}';
}

/// Riga compatta per il PDF di origine: icona documento ed etichetta
/// leggibile ricavata da periodo/tipo della busta paga (mai il nome file
/// grezzo, vedi [bustaPagaDocumentoLabel]). L'intera card è tappabile
/// (nessuna etichetta/icona "Apri" separata, il tap ovunque sulla riga apre
/// direttamente l'anteprima di sistema — Quick Look su iOS — tramite
/// `open_filex`. L'anteprima include già un bottone di condivisione
/// nativo, quindi non serve un'azione di condivisione separata in questo
/// widget. Sempre tappabile (dettaglio e form di import: il file è già
/// copiato su disco prima ancora che il form sia visibile, vedi
/// `PdfImportService`).
class BustaPagaDocumentoChip extends StatelessWidget {
  final String filePath;
  final DateTime periodo;
  final TipoBustaPaga tipo;

  const BustaPagaDocumentoChip({
    super.key,
    required this.filePath,
    required this.periodo,
    required this.tipo,
  });

  Future<void> _apri(BuildContext context) async {
    try {
      final absolutePath = await resolvePdfAbsolutePath(filePath);
      final result = await OpenFilex.open(absolutePath);
      if (result.type != ResultType.done && context.mounted) {
        _mostraErroreApertura(
          context,
          result.message.isNotEmpty
              ? result.message
              : 'Il PDF non è disponibile o non può essere aperto.',
        );
      }
    } catch (_) {
      if (context.mounted) {
        _mostraErroreApertura(
          context,
          'Il PDF non è disponibile o non può essere aperto.',
        );
      }
    }
  }

  void _mostraErroreApertura(BuildContext context, String messaggio) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    showAppAlertDialog<void>(
      context: context,
      title: 'Impossibile aprire il documento',
      message: messaggio,
      actions: [
        AppAlertAction(
          pulseGlyph: PulseIconGlyph.checkmark,
          label: 'OK',
          color: accent,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent =
        CupertinoDynamicColor.resolve(AppColors.pulseAccent, context);
    final textPrimary =
        CupertinoDynamicColor.resolve(AppColors.pulseTextPrimary, context);

    return Semantics(
      label: 'Apri documento PDF',
      button: true,
      child: PulseSurface(
        borderRadius: AppRadius.pulseSmall,
        onTap: () => _apri(context),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.mdMinus,
        ),
        child: Row(
          children: [
            PulseIcon(glyph: PulseIconGlyph.document, size: 20, color: accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                bustaPagaDocumentoLabel(periodo: periodo, tipo: tipo),
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.pulseBody.copyWith(color: textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
