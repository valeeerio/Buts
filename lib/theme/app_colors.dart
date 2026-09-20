import 'package:flutter/cupertino.dart';

/// Colori semantici stile Apple (system colors). L'app è solo dark mode
/// (2026-09-10): ogni token è un [Color] fisso, valore dark storico —
/// non esiste più una variante light.
class AppColors {
  AppColors._();

  // --- System semantic colors ---
  static const systemGreen = Color(0xFF30D158);
  static const systemBlue = Color(0xFF0A84FF);
  static const systemPurple = Color(0xFFBF5AF2);
  static const systemOrange = Color(0xFFFF9F0A);
  static const systemRed = Color(0xFFFF453A);

  // --- Backgrounds & surfaces ---
  static const backgroundPrimary = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceSecondary = Color(0xFF2C2C2E);

  // --- Labels (testo) ---
  static const labelPrimary = Color(0xFFFFFFFF);
  static const labelSecondary = Color(0x99EBEBF5); // 60% opacity white
  static const labelTertiary = Color(0x4DEBEBF5); // 30% opacity white

  static const separator = Color(0x99545458);

  // --- Liquid Glass ---
  // Palette volutamente sobria/neutra: il materiale vetro è la fonte di
  // profondità, il colore resta riservato ad accenti puntuali (badge di
  // stato, CTA primaria) — coerente con le linee guida Apple sul Liquid
  // Glass ("usa il colore con parsimonia sopra il vetro"). Usati solo da
  // `LiquidGlassSurface`/`LiquidGlassButton`.

  /// Riempimento della superficie di vetro, sopra il blur. Scuro/trasparente
  /// senza mai diventare nero pieno (il vetro "regular" di Apple schiarisce
  /// leggermente anche sopra sfondi scuri).
  static const glassFill = Color(0x40FFFFFF);

  /// Riflesso speculare sul bordo (angolo in cui la luce "colpisce" il
  /// vetro): usato solo per lo stroke con gradiente del bordo, mai come
  /// riempimento pieno.
  static const glassHighlight = Color(0x66FFFFFF);

  /// Bordo in ombra, lato opposto al riflesso speculare.
  static const glassShadowEdge = Color(0x4D000000);

  /// Scrim dietro `AppAlertDialog`: nero semi-trasparente, opaco per
  /// staccare la card piatta dal contenuto sottostante.
  static const alertBarrier = Color(0x99000000);

  // --- Pulse ---
  // Direzione visiva (vedi CLAUDE.md, "Stile visivo"): superfici piatte a
  // colore pieno, dark-first, accento ciano/cobalto elettrico. Dal
  // 2026-09-08 i valori sono quelli esatti già validati nel widget home
  // screen iOS (`ios/BustaPagaWidgetExtension/BustaPagaWidgetView.swift`,
  // `BustaPagaWidgetColors`) su richiesta esplicita dell'utente. Dal
  // 2026-09-10 l'app è solo dark mode: rimossi i valori light, ogni token è
  // il valore dark storico.

  /// Sfondo pagina: quasi-nero freddo — valore esatto del widget home screen.
  static const pulseBackground = Color(0xFF0A0F17);

  /// Superficie "tessera" (card, tile, riga di elenco): un grado più chiara
  /// dello sfondo. Derivato mantenendo lo stesso scarto per canale
  /// (+7,+8,+9) già usato tra sfondo e superficie, applicato a
  /// `pulseBackground` (il widget non ha un concetto di superficie separata
  /// dallo sfondo).
  static const pulseSurface = Color(0xFF111720);

  /// Accento primario (dal 2026-09-09, "Grafite fredda" — palette C scelta
  /// dall'utente tra più opzioni mostrate in un artefatto di design,
  /// sostituisce il precedente "Blu elettrico"): grigio-blu freddo,
  /// minimale, mood "premium", chiaro per restare leggibile sullo sfondo
  /// scuro Pulse.
  static const pulseAccent = Color(0xFF9AA7B5);

  /// Ciano dell'anello dell'icona app (campionato dal pixel dell'anello in
  /// `Icon-App-1024x1024@1x.png`, #3DDBFF). Usato solo dall'animazione di
  /// avvio; `pulseAccent` è invece un grigio-azzurro, non il ciano del brand.
  static const brandRing = Color(0xFF3DDBFF);

  /// Testo/icone sopra un riempimento pieno di `pulseAccent`. Verificato con
  /// la formula di luminanza relativa WCAG: quasi-nero #0E1420 su #9AA7B5,
  /// 7.52:1 (contro 2.42:1 di un testo chiaro), ampiamente sopra soglia
  /// 4.5:1.
  static const pulseOnAccent = Color(0xFF0E1420);

  /// Testo primario sopra le superfici Pulse: bianco puro, valore esatto del
  /// widget (era un bianco leggermente sporcato, #F5F8FA).
  static const pulseTextPrimary = Color(0xFFFFFFFF);

  /// Testo secondario/label sopra le superfici Pulse: grigio neutro, valore
  /// esatto del widget (#B3B3B3, non più grigio-bluastro).
  static const pulseTextSecondary = Color(0xFFB3B3B3);

  /// Viola elettrico per accenti/gradienti decorativi (direzione
  /// "futuristica" derivata dal mockup B — vedi CLAUDE.md/piano sessione).
  /// Uso ESCLUSIVAMENTE decorativo: seconda serie/colore "Lordo" nei grafici
  /// Statistiche (`buste_paga_statistiche_screen.dart`), bordo a gradiente
  /// opzionale (`showGradientBorder`) di `ProgressRingTile`. MAI come colore
  /// funzionale di icone/testo/CTA — quel ruolo resta interamente a
  /// `pulseAccent` (ciano), che non cambia.
  static const pulseSecondaryGlow = Color(0xFF7C5CFF);

  /// Variazione favorevole/stato positivo (es. "Confermato") sopra
  /// superfici Pulse: verde ricalibrato per contrasto adeguato sulla
  /// superficie scura Pulse, non il systemGreen Apple.
  static const pulsePositive = Color(0xFF3DE08A);

  /// Variazione sfavorevole/stato di attenzione (es. "Da confermare",
  /// alert) sopra superfici Pulse: rosso ricalibrato per contrasto adeguato
  /// sulla superficie scura Pulse, non il systemRed Apple.
  static const pulseNegative = Color(0xFFFF6B61);

  /// Testo sopra un riempimento pieno di `pulsePositive` (es. badge
  /// "Confermato"). Un testo bianco fisso non raggiunge 4.5:1 (calcolato con
  /// la formula di luminanza relativa WCAG: 1.72:1 su `pulsePositive`) —
  /// `pulsePositive` è abbastanza chiaro da dare invece ottimo contrasto con
  /// testo quasi-nero (10.73:1).
  static const pulseOnPositive = Color(0xFF0E1420);

  /// Testo sopra un riempimento pieno di `pulseNegative` (es. badge "Da
  /// confermare"). Stesso ragionamento di `pulseOnPositive`: bianco fisso
  /// insufficiente (2.79:1), testo quasi-nero invece raggiunge 6.61:1.
  static const pulseOnNegative = Color(0xFF0E1420);
}
