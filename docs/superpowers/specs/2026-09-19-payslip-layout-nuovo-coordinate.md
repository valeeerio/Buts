# Nuovo layout cedolino: ancore e coordinate (Task 4, scoperta)

Findings ricavati leggendo un cedolino di esempio (luglio 2026, 2 pagine) con
Syncfusion tramite `PdfImportService.leggiContenuto`, lo stesso motore
dell'app. Nessun dato personale: solo etichette generiche, intervalli X/Y e
strutture. Coordinate in punti PDF (origine in alto a sinistra, pagina
~595x842); `Y` e' `bordoSuperiore` della parola, `X` sono
`bordoSinistro`/`bordoDestro`.

Base dati: **un solo PDF** (vedi "Punti aperti").

## 0. Comportamento generale di Syncfusion su questo PDF

- `testo` linearizzato: prima TUTTE le etichette (modulo prestampato), poi TUTTI
  i valori, senza ordine di riga. Inutilizzabile per associare etichetta e
  valore: serve l'estrazione a coordinate. Contiene le due pagine
  concatenate.
- Le parole hanno una riga = un valore di `bordoSuperiore` comune. Valori
  della stessa riga hanno Y identico a meno di ~0,6 pt (descrizione e importo
  della stessa riga: es. 498,1 e 498,1; ma sottoannotazioni come "Anno ..."
  stanno a Y-0,6). Tolleranza consigliata sulle righe: +-1,0 pt.
- Compaiono parole composte solo da spazio (`" "`, larghezza ~1,7 pt) fra
  ogni coppia di parole di una stessa frase: vanno scartate (`trim().isEmpty`).
  Il testo linearizzato contiene anche una riga vuota finale.
- Le etichette del modulo sono divise in una parola per token
  ("Totale", "Competenze"; "Ferie", "spett."): per ancorarsi a un'etichetta
  di piu' parole cercare la prima parola e verificare la successiva sulla
  stessa riga (Y uguale, sinistra = destra precedente + ~1,7).
- Le celle vuote non producono NESSUNA parola (ne' stringa vuota): si
  riconoscono solo per assenza di parole nella colonna/riga attesa.

## 1. Firma di riconoscimento

Stringhe presenti nel testo linearizzato di Syncfusion del nuovo layout (tutte
verificate `true`):

- `ELEMENTI DELLA RETRIBUZIONE`
- `Periodo di retribuzione`
- `Netto da pagare` (e in maiuscolo `NETTO DA PAGARE`)
- `Totale Competenze`, `Totale ritenute` (maiuscole/minuscole esatte)

Verifica di non-ambiguita' con JOB: `JobLayout().riconosce(...)` (firma
`JOB - Copyright`) e' **false** sull'esempio; nessuna delle stringhe sopra
compare nel testo di nessuno dei 15 PDF JOB reali controllati (2025 e 2026),
cioe' nessun falso positivo in quella direzione. La firma proposta per il nuovo
layout: presenza contemporanea di `ELEMENTI DELLA RETRIBUZIONE` e
`Periodo di retribuzione`, piu' l'assenza della firma JOB (o registro con
JOB per primo, come oggi).

Nota: tutte queste stringhe sono etichette del modulo prestampato, ripetute
identiche su ogni pagina: sono robuste, ma non dicono nulla sulla pagina
che contiene i valori (vedi 2).

## 2. Selezione pagina

Il PDF di esempio ha 2 pagine, **entrambe con lo stesso modulo prestampato**
(stesse etichette, "Totale Competenze" compreso). Non ci si puo' quindi
basare sulla sola presenza delle etichette.

- **Pagina 0**: intestazione (periodo, netto nel riquadro in alto),
  prime voci di competenza, marker `SEGUE ..` (parola "SEGUE" X ~466-494,
  Y ~667, seguita da ".."). **Nessun valore** sotto "Totale Competenze",
  "Totale ritenute", nessun rateo, nessuna trattenuta.
- **Pagina 1**: intestazione (periodo e netto ripetuti), altre voci di
  competenza, trattenute, totali, ratei.

Le voci di competenza sono **distribuite su entrambe le pagine** (verificato
aritmeticamente: somma delle voci pagina 0 + pagina 1 + arrotondamento
= Totale Competenze). Le ore lavorate del riquadro in alto sono ripetute
su tutte le pagine.

Regola proposta per scegliere la pagina dei totali: la **pagina che ha una
parola numerica (formato `1.234,56`) nella riga sotto l'etichetta "Totale
Competenze"** (Y etichetta + 5..+14, X che si sovrappone a 479..562). In
pratica: l'ultima pagina, che non ha "SEGUE ..". In alternativa: la pagina
senza il marker `SEGUE`. La regola sulla presenza del valore e' piu'
robusta di un indice fisso e regge anche un documento a pagina singola. Le
voci di competenza vanno invece lette da TUTTE le pagine (unendo, ordinate
per pagina e Y).

Attenzione: il Y di ogni sezione **cambia da pagina a pagina** (es. riga
etichette "Totale ritenute / Totale Competenze" a Y 612,8 in pagina 0 e a
624,1 in pagina 1; riquadro presenze, righe ratei, "NETTO DA PAGARE" sono
tutti traslati di ~11 pt fra le due pagine). Le ancore vanno perche' sempre
**relative all'etichetta** della stessa pagina, mai a Y assoluti.

## 3. Ancore per campo

Tutte le X sono valide per la pagina 1 dell'esempio; il modulo e' prestampato,
quindi sono tenute per stabili (da confermare, vedi punto 5).
"Riga valori" = Y etichetta + ~9,2-9,3 pt, salvo dove indicato.

### Periodo
- Etichetta: `Periodo` `di` `retribuzione` X 453,0-515,5, Y ~127,6.
- Valore: **una sola parola** `LUG.2026` (formato `MMM.AAAA`, mese di 3
  lettere maiuscole abbreviato, punto, anno a 4 cifre) X 486,7-523,3, Y
  ~136,9 (etichetta + 9,3). Non sotto l'etichetta: allineato piu' a
  destra, ma su un solo candidato nella zona (prima parola con regex
  `[A-Z]{3}\.\d{4}` nell'area X 450-560, Y 130-145).
- Mesi abbreviati da mappare (finora visto solo LUG): GEN, FEB, MAR, APR,
  MAG, GIU, LUG, AGO, SET, OTT, NOV, DIC (da confermare su altri PDF).

### Netto da pagare (due posizioni, stesso valore)
- Riquadro in alto (presente su TUTTE le pagine): etichetta `Netto da pagare`
  X 425,4-472,7 Y ~206,5; valore in formato `1.234,56` X ~530-561,5 (bordo
  destro ~561,5), Y ~215,7 (+9,2). Piu' a destra dell'etichetta, non
  sotto. Nella stessa riga Y ~215,7 c'e' anche un codice fiscale (X
  ~284-365): scartare con filtro X >= 520.
- In basso (solo pagina dei totali): etichetta `NETTO DA PAGARE` X
  463,6-524,0 Y ~659,2 (pagina 1); valore X 530,2-561,4, Y ~678,6
  (etichetta + 19,4).
- Le due posizioni coincidono; verificato: Totale Competenze - Totale
  ritenute = netto. Preferire quello in basso della pagina dei totali;
  usare il riquadro in alto come ripiego/controllo.

### Totale ritenute / Totale competenze
Riga etichette pagina 1 a Y ~624,1 (pagina 0: 612,8):
- `Totale` `ritenute`: X 397,9-437,8. Valore: X 448,7-473,3, Y +9,3
  (633,4), bordo destro ~473,3.
- `Totale` `Competenze`: X 479,0-533,7. Valore: X 530,2-561,4, stessa Y
  (bordo destro ~561,4).
- Nota: il valore NON e' centrato sotto l'etichetta (x diversi), va
  agganciato per **colonna** (bordo destro ~473 per ritenute, ~561 per
  competenze), non per sovrapposizione con l'etichetta.

### Ore lavorate
- Etichetta `Ore` `lavorate` X 72,7-107,1, Y ~296,9 (uguale su tutte le pagine).
- Valore (formato `146,00`): X 103,3-127,9, Y ~306,1 (+9,2). E' la prima
  parola numerica (piu' a sinistra) della riga valori a Y ~306,1: le altre
  sono Ore retribuite (X 164-189), giorni (`26`, `19`...) nelle colonne
  seguenti. Non sovrapposto alla sola etichetta (comincia a destra):
  scegliere la parola numerica con bordo sinistro piu' basso della riga.

### Ratei Ferie / ROL / Ex festivita' (solo pagina dei totali)
Struttura a righe di 3 sottolivelli. Etichette (Y ~646,7 in pagina 1):

| Riga | Etichetta | X etichetta |
|---|---|---|
| Ferie | `Ferie a.p.` | 72,7-99,1 |
| Ferie | `Ferie spett.` | 113,5-144,8 |
| Ferie | `Ferie godute` | 153,8-189,0 |
| Ferie | `Ferie residue` | 194,8-231,2 |
| ROL | `ROL a.p.` | 235,0-259,9 |
| ROL | `ROL spett.` | 275,8-305,7 |
| ROL | `ROL goduti` | 316,1-347,7 |
| ROL | `ROL residui` | 357,0-390,1 |
| Ex fes. | `Ex fes. a.p.` | 72,7-104,0, Y ~669,4 |
| Ex fes. | `Ex fes. spett.` | 113,5-149,7, Y ~669,4 |
| Ex fes. | `Ex fes. god.` | 153,8-186,9, Y ~669,4 |
| Ex fes. | `Ex fes. resid.` | 194,8-230,9, Y ~669,4 |

Riga valori: Y ~659,5 (etichetta + 12,8) per Ferie e ROL; i valori
sono formato `47,93`, larghezza ~20-25 pt, **piu' a destra dell'inizio
dell'etichetta** (cella allineata a destra dentro una colonna):

- `a.p.` (anno precedente): Ferie X 89,8-109,8; ROL X 251,9-271,9.
- `spett.` (maturato del mese): Ferie X 130,3-150,3; ROL X 292,6-312,6.
  Sopra ciascun valore `spett.` c'e' anche una piccola parola
  `rateo m.:NN,NN` (due parole: `rateo` + `m.:13,33`, Y ~652,7, tra riga
  etichette e riga valori): e' il rateo mensile, **non** un saldo; il `:`
  dentro una singola parola (`m.:13,33`) la rende non parsabile come numero
  isolato: va ignorata (o letta come numero dopo `m.:`).
- `godute`/`goduti`: Ferie: **cella vuota** nel PDF di esempio (nessuna
  parola in X 154-189, Y 659,5); ROL X 328,4-353,0.
- `residue`/`residui`: Ferie X 206,9-231,4; ROL X 373,8-393,8.
- Riga Ex fes. (Y etichetta 669,4): **tutte le celle vuote** nel PDF di
  esempio (nessuna parola nella riga valori attesa, ~Y 682): non
  verificabile dove stiano i valori (ipotesi: stessa struttura, Y = etichetta
  + 12,8).

Assegnazione valore-cella: dato che il valore e' piu' a destra
dell'etichetta, agganciare per bordo destro del valore ai centri di colonna
(Ferie: a.p. ~110, spett. ~150, godute ~189, residue ~231; ROL: a.p. ~272,
spett. ~313, goduti ~353, residui ~394) con tolleranza +-6 pt. Dettaglio
implementativo del Task 5.

Verifica aritmetica della spec sulle colonne trovate: Ferie 47,93 + 93,31 =
141,24 (a.p.+spett.=residue, godute vuote); ROL 62,07 + 60,69 - 106,00 =
16,76 (a.p.+spett.-goduti=residuo). Coerenti: la mappatura e' confermata.

### Voci di competenza
Righe della tabella centrale (Y da ~351 in avanti, passo ~11,3 pt), colonne:

| Colonna | Testo | X (sinistra-destra) |
|---|---|---|
| Codice | numerico (`1`, `16`, `25`, `42`) | 84,5-93,3 |
| Descrizione | testo multi-parola | da X ~107,4 |
| Ore-giorni | quantita', `40,00` | 299,6-324,4 (bordo destro ~324) |
| Dato base | tariffa, `11,1029` | 362,8-391,7 |
| Importo | `444,12` | 530,2-561,5 (bordo destro ~561,4) |

Note:
- Etichette della testata (`COD.` X 76,2, `DESCRIZIONE` 162,4,
  `ORE - GIORNI` 278-319, `DATO BASE` 343,7-379,5, `RITENUTE` 419,8-451,1,
  `COMPETENZE` 498-541,5) a Y ~331,9. Le righe voce stanno tra la testata e
  la riga delle detrazioni (Y 590,3 pag. 0 / 601,6 pag. 1).
- Una voce ha sempre il codice numerico nella colonna Codice: le righe della
  sezione ritenute (vedi sotto) non lo hanno.
- Nomi di voce visti (etichette generiche): "ORE ORD.", "CARENZA MALATTIA",
  "ROL GODUTI", "TRASFERTA (tipo 3)" (descrizione con parentesi).
- "ROL GODUTI" compare come voce con importo positivo (ore + tariffa +
  importo): e' una voce di competenza retribuita, **non** i ROL goduti della
  tabella ratei.
- Il totale competenze verifica: somma degli importi (voci di entrambe le
  pagine) + arrotondamento attuale (in colonna Importo, riga
  detrazioni) = Totale Competenze. Esattamente coincide.
- Le voci con quantita' vuota (es. importo semplice) non hanno parola nella
  colonna Ore-giorni.
- Una stessa descrizione ("ORE ORD.", "ROL GODUTI") si ripete su piu' pagine:
  non fare deduplicazione per descrizione.

### Trattenute (IRPEF, addizionali, contributi)
Stessa tabella, righe **senza codice** (colonna Codice vuota), descrizione da
X ~107,4, valore nella colonna **Ritenute** (bordo destro ~473,3-473,4,
sinistra 448,7-457). Quindi discriminante voce/trattenuta: bordo destro
dell'importo ~473 (ritenuta) vs ~561 (competenza). Righe viste:

- Contributi: `CTR FPLD` (due righe, base imponibile in colonna Dato base X
  ~360-392: `1.332,00` e `711,00`; contributo in colonna Ritenute:
  `81,78` e `43,66`).
- IRPEF: `IRPEF NETTA` (Ritenute X 448,7-473,3); accanto restano righe
  informative NON trattenute: `IMPONIBILE IRPEF` (X 360-392, colonna Dato
  base), `IRPEF LORDA` (X 367-392), `DETRAZIONI` (X 367-392), e
  un'annotazione `(reddito presuntivo: NN.NNN,NN)` a X 194-268 stessa riga di
  DETRAZIONI: numero fra parentesi da NON leggere come importo.
- Aumenti CCNL: `IMPONIBILE AUMENTI CCNL` (informativa, colonna Dato base) e
  `IMPOSTA AUMENTI CCNL 5%` (Ritenute X 457,2-472,8): il `5%` e' parte della
  descrizione.
- Addizionali: `TRATT.ADDIZ.REGIONALE`, `TRATT.ADDIZ.COMUNALE`,
  `ACCONTO ADDIZ.COMUNALE` (Ritenute X 453-473). Ogni riga e' preceduta/
  accompagnata da una sottostringa `Anno AAAA Cod.ENTE XXXX` (X 243-316,
  Y ~0,6 pt sopra la riga): parte del contesto, non e' una voce a se'.
- Informative senza colonna Ritenute/Competenze: `RETR. UTILE TFR`
  (X 238,9-270,2), `QUOTA TFR VER. FONDO` (X 245,5-270,1): valore e' in
  colonna intermedia (bordo destro ~270), non e' una trattenuta.
- Riga detrazioni (Y 601,6 etichette pag. 1, valori a +9,3): `Detraz.lav.dip.
  / Ulteriori` (2 valori, X 238,8-263,4 e 284,0-304,0), `Arrot. precedente`
  (colonna Ritenute, X 457,2-472,8: e' un importo di arrotondamento, entra
  nel totale ritenute), `Arrot. attuale` (colonna Competenze, X 545,2-560,7,
  entra nel totale competenze).
- Verifica: somma trattenute (contributi + IRPEF netta + imposta aumenti +
  addizionali) + arrotondamento precedente = Totale ritenute.
  Coincide esattamente.

Regola proposta di classificazione riga: raggruppare per Y (+-1,0);
`competenza` se c'e' una parola nella colonna Codice (X 84-94) **e** un importo
con bordo destro ~561; `trattenuta` se manca il codice e c'e' un importo con
bordo destro ~473 (esclusa la riga `Arrot.`, che va trattata a parte come
nel layout JOB); tutto il resto e' informativo.

## 4. Riepilogo verifiche aritmetiche fatte

- Totale competenze - totale ritenute = netto da pagare.
- Somma trattenute + Arrot. precedente = Totale ritenute.
- Somma voci di competenza (entrambe le pagine) + Arrot. attuale = Totale
  competenze.
- Ferie: a.p. + spett. = residue; ROL: a.p. + spett. - goduti = residui.
- Ore lavorate (riquadro) = somma delle quantita' delle voci "ORE ORD." delle
  due pagine, nell'esempio; non generalizzabile (ci sono anche voci malattia
  e ROL), non usarla come controllo.

## 5. Punti aperti / ambigui

1. **Un solo PDF**: ancore X/Y e mesi abbreviati tarati su un unico esempio.
   Serve almeno un secondo cedolino del nuovo layout (un mese diverso, meglio
   uno con Ex festivita', Ferie godute e 13a/14a valorizzati) per confermare
   che le colonne siano davvero prestampate, non dipendenti dall'impaginazione
   dei dati.
2. **Ex festivita'**: nell'esempio tutte le celle sono vuote: non e' noto
   dove cadano i valori (ipotesi: stessa struttura di Ferie/ROL a +12,8 pt
   dall'etichetta). Non tarabile senza un secondo PDF.
3. **Ferie godute** vuote nell'esempio: colonna attesa X ~154-189 ma non
   osservata con un valore.
4. **ROL goduti nella tabella ratei (106,00)** vs voce "ROL GODUTI" nelle
   competenze (somma delle ore nelle due pagine: non coincide): il valore nei
   ratei coincide con il totale di un'altra voce, quindi il significato
   esatto (cumulativo annuo? ore del mese?) va chiarito dall'utente. La
   mappatura scelta nella spec (a.p. + spett. - goduti = residuo) regge
   comunque aritmeticamente.
5. **Permessi**: il layout JOB ha "Permessi riduz. orario goduti" mensile; nel
   nuovo layout non c'e' nessuna etichetta analoga distinta dai ROL: i ROL sono
   gli unici permessi visti.
6. **13a/14a e buste con tipo diverso**: non presenti nell'esempio, il
   layout potrebbe cambiare (etichette, testata); non valutabile.
7. **Pagina singola**: l'esempio ha 2 pagine con "SEGUE ..". Non e' verificato
   cosa cambia per un cedolino di una sola pagina (la regola di selezione per
   presenza del valore sotto "Totale Competenze" dovrebbe reggere).
8. **Nome del layout / software paghe**: non deducibile dal PDF (nessuna
   marca); decisione da prendere con l'utente.
