import 'job_layout.dart';
import 'payslip_layout.dart';
import 'pdf_contenuto.dart';

class PayslipLayoutRegistry {
  final List<PayslipLayout> layouts;

  const PayslipLayoutRegistry(this.layouts);

  /// Layout supportati, in ordine di prova. I nuovi layout si aggiungono qui.
  static const standard = PayslipLayoutRegistry([JobLayout()]);

  /// Primo layout che riconosce il PDF, o `null` se nessuno lo riconosce.
  PayslipLayout? rileva(PdfContenuto contenuto) {
    for (final layout in layouts) {
      if (layout.riconosce(contenuto)) return layout;
    }
    return null;
  }
}
