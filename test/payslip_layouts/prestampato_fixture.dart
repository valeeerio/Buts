import 'package:buts/services/payslip_layouts/pdf_contenuto.dart';

ParolaVoce w(String testo, double sinistra, double destra, double top) => (
      testo: testo,
      bordoSuperiore: top,
      bordoSinistro: sinistra,
      bordoDestro: destra,
    );

/// Parole comuni a entrambe le pagine (blocchi FISSI + testata tabella).
List<ParolaVoce> _fissi() => [
      // Periodo (etichetta a 127,6, valore a 136,9).
      w('Periodo', 453.0, 478.0, 127.6),
      w('di', 479.7, 486.0, 127.6),
      w('retribuzione', 487.7, 515.5, 127.6),
      w('LUG.2026', 486.7, 523.3, 136.9),
      // Riquadro netto in alto (206,5 / 215,7) + un CF-like da scartare.
      w('Netto', 425.4, 448.0, 206.5),
      w('da', 449.7, 457.0, 206.5),
      w('pagare', 458.7, 472.7, 206.5),
      w('AAAAAA00A00A000A', 284.0, 365.0, 215.7),
      w('787,99', 535.0, 561.5, 215.7),
      // Ore lavorate (296,9 / 306,1) e ore retribuite.
      w('Ore', 72.7, 85.0, 296.9),
      w('lavorate', 86.7, 107.1, 296.9),
      w('160,00', 103.3, 127.9, 306.1),
      w('184,00', 164.0, 189.0, 306.1),
      // Testata tabella (331,9).
      w('COD.', 76.2, 90.0, 331.9),
      w('DESCRIZIONE', 162.4, 200.0, 331.9),
    ];

/// Pagina 1 (dati): etichette che traslano di [dy] rispetto alla pagina 0.
/// Valori fittizi coerenti: competenze 1.000,00 + 88,00 + arrAtt 0,01 =
/// 1.088,01; ritenute 100,00 + 200,00 + arrPrec 0,02 = 300,02; netto 787,99.
List<ParolaVoce> paginaDati({double dy = 11.3}) => [
      ..._fissi(),
      // Voce competenza (pagina 1): codice 42, "ROL GODUTI", 8,00 h, 88,00.
      w('42', 84.5, 93.3, 351.3),
      w('ROL', 107.4, 122.0, 351.3),
      w('GODUTI', 123.7, 160.0, 351.3),
      w('8,00', 305.0, 324.4, 351.3),
      w('11,0000', 362.8, 391.7, 351.3),
      w('88,00', 540.0, 561.5, 351.3),
      // Trattenute (senza codice): CTR FPLD e IRPEF NETTA.
      w('CTR', 107.4, 125.0, 362.6),
      w('FPLD', 126.7, 148.0, 362.6),
      w('100,00', 448.7, 473.3, 362.6),
      w('IRPEF', 107.4, 130.0, 373.9),
      w('NETTA', 131.7, 158.0, 373.9),
      w('200,00', 448.7, 473.3, 373.9),
      // Riga informativa senza importo in colonna competenze/ritenute.
      w('IMPONIBILE', 107.4, 160.0, 385.2),
      w('IRPEF', 161.7, 185.0, 385.2),
      w('1.500,00', 360.0, 392.0, 385.2),
      // Riga detrazioni/arrotondamenti (590,3 + dy) con valori a +9,3.
      w('Arrot.', 436.0, 453.0, 590.3 + dy),
      w('precedente', 454.7, 490.0, 590.3 + dy),
      w('Arrot.', 500.0, 517.0, 590.3 + dy),
      w('attuale', 518.7, 540.0, 590.3 + dy),
      w('0,02', 457.2, 472.8, 599.6 + dy),
      w('0,01', 545.2, 560.7, 599.6 + dy),
      // Totali (612,8 + dy) con valori a +9,3.
      w('Totale', 397.9, 425.0, 612.8 + dy),
      w('ritenute', 426.7, 437.8, 612.8 + dy),
      w('Totale', 479.0, 505.0, 612.8 + dy),
      w('Competenze', 506.7, 533.7, 612.8 + dy),
      w('300,02', 448.7, 473.3, 622.1 + dy),
      w('1.088,01', 530.2, 561.4, 622.1 + dy),
      // Ratei: etichette (635,4 + dy) e valori a +12,8. Esempio FITTIZIO:
      // Ferie a.p. 10,00 + spett. 35,00 = residue 45,00 (godute vuote);
      // ROL a.p. 20,00 + spett. 56,00 - goduti 30,00 = residui 46,00.
      w('Ferie', 72.7, 87.0, 635.4 + dy),
      w('a.p.', 88.7, 99.1, 635.4 + dy),
      w('Ferie', 113.5, 127.0, 635.4 + dy),
      w('spett.', 128.7, 144.8, 635.4 + dy),
      w('Ferie', 153.8, 167.0, 635.4 + dy),
      w('godute', 168.7, 189.0, 635.4 + dy),
      w('Ferie', 194.8, 208.0, 635.4 + dy),
      w('residue', 209.7, 231.2, 635.4 + dy),
      w('ROL', 235.0, 247.0, 635.4 + dy),
      w('a.p.', 248.7, 259.9, 635.4 + dy),
      w('ROL', 275.8, 288.0, 635.4 + dy),
      w('spett.', 289.7, 305.7, 635.4 + dy),
      w('ROL', 316.1, 328.0, 635.4 + dy),
      w('goduti', 329.7, 347.7, 635.4 + dy),
      w('ROL', 357.0, 369.0, 635.4 + dy),
      w('residui', 370.7, 390.1, 635.4 + dy),
      w('rateo', 130.0, 142.0, 641.7 + dy),
      w('m.:5,00', 143.7, 160.0, 641.7 + dy),
      w('10,00', 89.8, 109.8, 648.2 + dy),
      w('35,00', 130.3, 150.3, 648.2 + dy),
      w('45,00', 211.4, 231.4, 648.2 + dy),
      w('20,00', 251.9, 271.9, 648.2 + dy),
      w('56,00', 292.6, 312.6, 648.2 + dy),
      w('30,00', 333.0, 353.0, 648.2 + dy),
      w('46,00', 373.8, 393.8, 648.2 + dy),
      // Ex festività: solo etichette (celle vuote).
      w('Ex', 72.7, 80.0, 658.1 + dy),
      w('fes.', 81.7, 92.0, 658.1 + dy),
      w('a.p.', 93.7, 104.0, 658.1 + dy),
      // Netto in basso (647,9 + dy), valore a +19,4.
      w('NETTO', 463.6, 490.0, 647.9 + dy),
      w('DA', 491.7, 499.0, 647.9 + dy),
      w('PAGARE', 500.7, 524.0, 647.9 + dy),
      w('787,99', 535.0, 561.4, 667.3 + dy),
    ];

/// Pagina 0: prime voci, marker "SEGUE ..", etichette totali SENZA valori.
List<ParolaVoce> paginaSegue() => [
      ..._fissi(),
      w('1', 84.5, 93.3, 351.3),
      w('ORE', 107.4, 125.0, 351.3),
      w('ORD.', 126.7, 148.0, 351.3),
      w('100,00', 299.6, 324.4, 351.3),
      w('10,0000', 362.8, 391.7, 351.3),
      w('1.000,00', 530.2, 561.5, 351.3),
      w('Arrot.', 436.0, 453.0, 590.3),
      w('precedente', 454.7, 490.0, 590.3),
      w('Totale', 397.9, 425.0, 612.8),
      w('ritenute', 426.7, 437.8, 612.8),
      w('Totale', 479.0, 505.0, 612.8),
      w('Competenze', 506.7, 533.7, 612.8),
      w('SEGUE', 466.0, 494.0, 667.3),
      w('..', 495.7, 500.0, 667.3),
    ];
