# Pinxel — Cattura immagini ed editor (v1) — Design

- **Data:** 2026-10-14
- **Stato:** proposta, in revisione
- **Ambito:** sottoprogetti 1 (fondamenta + cattura immagini) e 2 (editor immagini)

## 1. Obiettivo e contesto

Pinxel è un'app macOS nativa per catturare lo schermo e annotare le catture, con
un editor di annotazione completo. Scopo primario: uso personale
quotidiano. Vincolo: le fondamenta non devono impedire una futura
distribuzione (bundle ID proprio, permessi gestiti correttamente, nessun codice
o asset di terzi).

### Roadmap complessiva

| # | Sottoprogetto | Stato |
|---|---------------|-------|
| 1 | Fondamenta + cattura immagini (area, finestra, schermo) | **questa spec** |
| 2 | Editor immagini | **questa spec** |
| 3 | Cattura a scorrimento (auto, poi manuale) | spec futura |
| 4 | Registrazione video + audio, trim, export MP4/GIF | spec futura |

La v1 è implementata in tre piani successivi:
(1) `PinxelKit` core — `DocumentModel`, `Rendering`, `Persistence`, headless e
testabile con `swift test`; (2) app + `CaptureKit` — barra dei menu,
scorciatoie, overlay, permessi, flusso post-cattura; (3) `EditorUI` — canvas,
strumenti, pannelli, export dall'interfaccia.

Fuori dalla v1: cronologia/libreria, cattura a scorrimento, video, OCR,
estensione Quick Look, sincronizzazione iCloud, firma e notarizzazione.

### Criteri di successo

1. Dalla scorciatoia globale all'editor aperto con la cattura in meno di 1 s su
   un Mac Apple Silicon con display Retina.
2. Tutti gli strumenti della sezione 6.2 utilizzabili, con annulla/ripeti
   completo.
3. Un documento `.pinxel` salvato e riaperto è identico (round-trip senza
   perdite) e l'export PNG corrisponde pixel per pixel a quanto mostrato nel
   canvas a zoom 100%.
4. Nessuna cattura nera o vuota: ogni errore di permesso o cattura produce un
   messaggio comprensibile.

## 2. Decisioni chiave

| Decisione | Scelta |
|-----------|--------|
| Nome / bundle ID | Pinxel / `com.degiorgi.pinxel` (provvisorio, modificabile prima della distribuzione) |
| Piattaforma | macOS 15+, Apple Silicon e Intel, Swift 6 (strict concurrency) |
| UI | SwiftUI per finestre, barre e pannelli; canvas `NSView` custom (AppKit) |
| Rendering | Core Graphics per le annotazioni, Core Image per sfocatura/pixel |
| Cattura | ScreenCaptureKit (`SCShareableContent`, `SCScreenshotManager`) |
| Documento | `NSDocument`, formato `.pinxel` (ZIP + JSON + asset separati) |
| Dopo la cattura | Configurabile: editor (default) / anteprima veloce / solo appunti |

Alternative scartate: editor interamente SwiftUI `Canvas` (hit-testing, testo
sul canvas e maniglie troppo limitati); editor web in `WKWebView` (ponte JS,
due linguaggi, resa meno nativa).

## 3. Scelte di formato

- L'immagine catturata resta separata e immutabile: ogni modifica è un oggetto
  o un'operazione sopra di essa, quindi tutto resta modificabile e reversibile.
- Le coordinate sono in pixel nello spazio dell'immagine, con la scala (pixel
  per punto) esplicita nel documento: indipendenti da zoom e schermo.
- Ogni annotazione ha un ID stabile (UUID), base per selezione, annulla/ripeti
  e copia/incolla.
- I metadati della cattura (data, app, finestra) viaggiano con il documento.
- Annotazioni tipizzate (enum con payload per tipo) invece di un unico record
  con tutte le proprietà: le combinazioni senza senso non sono rappresentabili.
- Colori numerici RGBA, non stringhe; immagini incollate come file separati
  nell'archivio, non base64 nel JSON.
- Niente file di backup manuale: basta il salvataggio atomico di `NSDocument`.

## 4. Architettura

Un'app (`Pinxel.app`) più un pacchetto Swift locale (`PinxelKit`) con moduli
separati e testabili in isolamento.

```
App ──► EditorUI ──► Rendering ──► DocumentModel
 │                      ▲               ▲
 ├──► Persistence ──────┘               │
 └──► CaptureKit ───────────────────────┘
```

| Modulo | Responsabilità | Dipende da |
|--------|----------------|------------|
| `DocumentModel` | Tipi del documento, annotazioni, operazioni immagine, comandi di modifica. Swift puro, nessun import di AppKit/SwiftUI. | — |
| `Rendering` | `render(document:into:options:)` su `CGContext`; unico percorso di disegno per canvas ed export. | `DocumentModel` |
| `CaptureKit` | Permessi, enumerazione schermi/finestre, overlay di selezione, scatto. Produce `CapturedImage`. | `DocumentModel` |
| `Persistence` | Lettura/scrittura `.pinxel`, migrazioni, export PNG/JPEG/HEIC/PDF. | `DocumentModel`, `Rendering` (per export e thumbnail) |
| `EditorUI` | Canvas `NSView`, macchina a stati degli strumenti, pannelli SwiftUI. | `Rendering`, `DocumentModel` |
| `App` | Barra dei menu, scorciatoie globali, preferenze, flusso post-cattura, `NSDocument`. | tutti |

`Persistence` dipende da `Rendering` (e quindi da `DocumentModel`) per
generare thumbnail ed export.

## 5. Modello del documento

### 5.1 Documento

```swift
struct PinxelDocument: Codable, Equatable {
    var background: ImageAssetRef      // immagine originale, mai modificata
    var canvasSize: PixelSize          // in pixel dell'immagine originale
    var scale: Double                  // pixel per punto (2.0 su Retina)
    var colorSpace: ColorSpaceID       // es. .sRGB, .displayP3
    var imageOperations: [ImageOperation]
    var canvasStyle: CanvasStyle       // bordo, ombra, padding, sfondo
    var annotations: [Annotation]      // ordine = z-order (indice 0 = in fondo)
    var metadata: CaptureMetadata      // data, app, titolo finestra, URL
}
```

Le coordinate delle annotazioni sono in pixel nello spazio dell'immagine *dopo*
le operazioni immagine. Zoom e scroll appartengono alla vista e non sono
persistiti.

### 5.2 Annotazioni

```swift
struct Annotation: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: Kind
    var rotation: Double               // radianti, attorno al centro dei bounds
    var style: Style
    var isLocked: Bool
}

enum Kind {
    case arrow(LineGeometry, ArrowHeads)
    case line(LineGeometry)
    case shape(RectGeometry, ShapeType)          // rectangle, roundedRect(radius), ellipse
    case text(RectGeometry, RichText)
    case callout(RectGeometry, RichText, CalloutTail)
    case step(center: Point, diameter: Double, StepLabel)
    case magnifier(source: RectGeometry, target: RectGeometry, ShapeType, connector: Bool)
    case blur(RectGeometry, radius: Double)
    case pixelate(RectGeometry, blockSize: Double)
    case highlight(PathGeometry)                 // tratto semitrasparente, blend multiply
    case pen(PathGeometry, smoothing: Double)
    case image(RectGeometry, ImageAssetRef)
    case unknown(type: String, raw: JSONValue)   // conservato per compatibilità futura
}

struct Style: Codable, Equatable {
    var stroke: RGBA?
    var fill: RGBA?
    var lineWidth: Double
    var dash: DashPattern                        // solid, dashed, dotted
    var opacity: Double                          // 0...1
    var shadow: Shadow?                          // offset, blur, color
}
```

`RGBA` usa componenti `Double` 0...1 nello spazio colore del documento.
`RichText` è una struttura Codable propria: famiglia e dimensione del font,
colore, allineamento e una lista di `TextRun` (testo + grassetto, corsivo,
sottolineato, colore opzionale). Niente `AttributedString` nel modello (JSON
stabile e indipendente da AppKit); niente barrato nella v1 (CoreText non lo
disegna nativamente). La conversione verso `NSAttributedString` avviene in
`Rendering` ed `EditorUI`.

`StepLabel`: `sequence` (numeri, lettere maiuscole, lettere minuscole),
`override: String?`. Senza override il valore visualizzato è calcolato
dall'ordine degli step dello stesso tipo di sequenza in `annotations`;
cancellare uno step rinumera i successivi.

### 5.3 Operazioni immagine

```swift
enum ImageOperation: Codable, Equatable {
    case crop(PixelRect)
    case resize(PixelSize)
    case cutOut(axis: Axis, range: ClosedRange<Int>, edge: CutEdge)  // straight, zigzag
}
```

Lo sfondo originale non viene mai modificato: le operazioni si applicano in
sequenza durante il render. Quando si aggiunge o annulla un'operazione, le
annotazioni vengono trasformate con la stessa mappatura (traslazione per crop e
cut-out, scala per resize) all'interno dello stesso comando, così l'annullamento
è esatto.

### 5.4 Comandi e annulla/ripeti

```swift
protocol EditCommand {
    var name: String { get }                     // per "Annulla <nome>"
    func apply(to doc: inout PinxelDocument)
    func revert(on doc: inout PinxelDocument)
}
```

Comandi: `AddAnnotations`, `DeleteAnnotations`, `UpdateAnnotations(id, before,
after)`, `Reorder`, `ApplyImageOperation`, `UpdateCanvasStyle`,
`Group([EditCommand])`.

Regole:

- Un'interazione continua (trascinamento, ridimensionamento, rotazione) produce
  un solo comando, registrato al mouse-up; durante il gesto il canvas mostra uno
  stato di anteprima non registrato.
- Spostamenti da tastiera consecutivi sullo stesso insieme di oggetti entro
  1 s vengono uniti in un comando.
- Lo stack è integrato con l'`UndoManager` di `NSDocument` (menu, `⌘Z`,
  `⇧⌘Z`); è illimitato, in memoria, non persistito.
- Invariante testata: per ogni comando `c` e documento `d`,
  `revert(apply(d))` è uguale a `d`.

## 6. Editor

### 6.1 Finestra

Una finestra per documento (`NSDocument` + `NSWindowController` che ospita
SwiftUI).

- **Toolbar** (in alto): strumenti con scorciatoia a tasto singolo.
- **Pannello proprietà** (a destra, comprimibile): proprietà contestuali allo
  strumento attivo o alla selezione; riga "stili rapidi" con gli ultimi 8 stili
  usati per strumento (salvati nelle preferenze).
- **Canvas** (centro): zoom (`⌘+`, `⌘-`, `⌘0` adatta, `⌘1` 100%, pinch),
  pan con `Spazio`+trascina o scroll, sfondo a scacchiera per la trasparenza.

### 6.2 Strumenti

| Strumento | Tasto | Note |
|-----------|-------|------|
| Selezione | V | clic, `⇧`+clic, riquadro; sposta, ridimensiona, ruota |
| Freccia | A | punte inizio/fine configurabili; `⇧` vincola a 45° |
| Linea | L | `⇧` vincola a 45° |
| Forma | R | rettangolo, arrotondato, ellisse; `⇧` = quadrato/cerchio |
| Testo | T | modifica sul canvas, testo formattato |
| Callout | C | fumetto con coda trascinabile |
| Step | S | numeri/lettere auto-incrementali, stile cerchio |
| Evidenziatore | H | tratto semitrasparente in multiply |
| Penna | P | mano libera con smoothing |
| Sfocatura / Pixel | B | rettangolo; modalità e intensità nel pannello |
| Lente | M | sorgente + destinazione ingrandita, connettore opzionale |
| Ritaglio | K | maniglie sui bordi, `Invio` conferma, `Esc` annulla |
| Cut-out | X | fascia orizzontale/verticale, bordo dritto o zig-zag |

Ridimensiona immagine, bordo, ombra e padding del canvas sono comandi dal menu
"Immagine" (non strumenti del canvas).

### 6.3 Comportamenti del canvas

- Maniglie: 8 per i rettangoli, estremi per linee e frecce, maniglia di
  rotazione sopra il bounding box.
- Linee guida magnetiche verso bordi e centri di altri oggetti e del canvas
  (disattivabili tenendo `⌘` durante il trascinamento).
- Copia/incolla di annotazioni tra documenti (tipo pasteboard privato
  `com.degiorgi.pinxel.annotations`); incollare un'immagine crea
  un'annotazione `.image`.
- `⌥`+trascina duplica; menu Disponi: porta in primo piano/avanti/indietro/in
  fondo; Blocca/Sblocca.
- Testo: doppio clic apre un `NSTextView` temporaneo sopra l'oggetto; alla
  chiusura il contenuto viene convertito in `RichText` con un singolo comando.
- La macchina a stati degli strumenti (`ToolController`) riceve eventi
  astratti (down/drag/up/key con coordinate canvas) e restituisce anteprime e
  comandi; non dipende da `NSView` e si testa senza finestra.

### 6.4 Sfocatura, pixel e lente

L'effetto è ricalcolato dallo sfondo (dopo le operazioni immagine, sotto le
annotazioni) a ogni render, con cache per regione e parametri. Nel `.pinxel`
resta modificabile e non distruttivo; negli export raster l'effetto è
incorporato nei pixel (irreversibile), che è il comportamento atteso per la
privacy. La lente campiona lo stesso livello (sfondo senza annotazioni).

## 7. Cattura

### 7.1 Avvio

- Icona nella barra dei menu (`MenuBarExtra`) con: Cattura area, Cattura
  finestra, Cattura schermo, Ripeti ultima area, Apri…, Preferenze, Esci.
- Scorciatoie globali configurabili; default `⌃⇧1` area, `⌃⇧2` finestra,
  `⌃⇧3` schermo, `⌃⇧4` ripeti ultima area. Registrate con l'API Carbon
  `RegisterEventHotKey` (non richiede il permesso Accessibilità).
- L'app è un agente (`LSUIElement`) finché non ci sono finestre di documento;
  mostra l'icona nel Dock quando un editor è aperto.

### 7.2 Overlay di selezione

1. Alla pressione, Pinxel scatta subito un'immagine di ogni schermo
   (`SCScreenshotManager`) e l'elenco delle finestre visibili
   (`SCShareableContent`, escluse quelle di Pinxel).
2. Su ogni schermo apre una finestra borderless a livello `.screenSaver` che
   mostra l'immagine congelata. Ciò che si seleziona è esattamente ciò che era
   visibile, inclusi menu e tooltip.
3. **Modalità unificata**: al passaggio del mouse la finestra sotto il cursore
   viene evidenziata (clic = cattura finestra); trascinando si definisce
   un'area. Nella modalità "Cattura schermo" un clic sceglie lo schermo.
4. Aiuti: lente con mirino e valore colore, dimensioni in pixel, `⇧` blocca le
   proporzioni, frecce per regolare di 1 px (`⇧` = 10 px), `Spazio` per
   spostare la selezione, `Esc` annulla, `Invio` conferma.
5. Il risultato viene ritagliato dall'immagine congelata. Per una finestra,
   Pinxel esegue invece una cattura dedicata della finestra tramite
   `SCContentFilter(desktopIndependentWindow:)` (senza finestre sovrapposte;
   ombra opzionale da preferenze).

Multi-monitor: ogni schermo è catturato alla propria scala nativa. Un'area a
cavallo di più schermi viene composta alla scala massima tra quelli coinvolti.

### 7.3 Permessi

- Prima di ogni cattura: `CGPreflightScreenCaptureAccess()`.
- Se assente: finestra guidata che spiega perché serve, chiama
  `CGRequestScreenCaptureAccess()` e apre il pannello
  Privacy e sicurezza → Registrazione schermo.
- Dopo la concessione macOS richiede il riavvio: la finestra offre "Riavvia
  Pinxel".
- Mai produrre una cattura nera: se il permesso manca la cattura non parte.

### 7.4 Flusso dopo la cattura

Preferenza con tre valori:

1. **Apri editor** (default): nuovo documento senza titolo con la cattura.
2. **Anteprima veloce**: miniatura nell'angolo in basso a destra per 5 s;
   trascinabile come file PNG verso altre app; clic apre l'editor; allo scadere
   applica il salvataggio automatico (se attivo) e scompare.
3. **Solo appunti**: copia PNG + TIFF negli appunti e mostra una breve
   conferma.

Opzione indipendente **Salva automaticamente**: cartella (default
`~/Pictures/Pinxel`), formato (`.pinxel` o PNG), modello del nome (default
`Pinxel yyyy-MM-dd 'at' HH.mm.ss`).

`CaptureMetadata` registra data, nome e bundle ID dell'app, titolo della
finestra (quando disponibili).

## 8. Formato `.pinxel`

UTI esportato `com.degiorgi.pinxel.document` (conforme a `public.data`,
`public.composite-content`), estensione `.pinxel`.

ZIP (deflate per i JSON, store per le immagini):

```
manifest.json        {"format":"pinxel","version":1,"appVersion":"0.1.0"}
document.json        PinxelDocument (Codable)
background.png       sfondo originale (HEIC se il PNG supera 20 MB)
assets/<uuid>.png    immagini incollate
thumbnail.png        lato lungo 512 px, renderizzata con annotazioni
```

Regole:

- `version` obbligatorio. Versione maggiore di quella supportata → apertura in
  sola lettura con avviso. Versioni minori → migrazione al caricamento.
- Tipi di annotazione sconosciuti → `Kind.unknown`, risalvati identici.
- Salvataggio atomico gestito da `NSDocument` (scrittura su file temporaneo e
  sostituzione).
- Lettura difensiva: limiti su dimensione decompressa (2 GB), numero di voci,
  path traversal vietato nei nomi delle voci.

## 9. Export e condivisione

- `⌘C` senza selezione: copia l'immagine composita (PNG + TIFF). Con
  selezione: copia le annotazioni (tipo privato) più il loro render PNG.
- Trascinamento dalla proxy icon della finestra o da un'area "trascina" nella
  toolbar → file PNG temporaneo.
- **Esporta…**: PNG, JPEG (qualità 0–100), HEIC, PDF; scala 1x o 2x.
- Menu Condividi di sistema (`NSSharingServicePicker`).

Tutti gli export passano da `Rendering.render`, con le stesse opzioni del
canvas a zoom 100%.

## 10. Gestione errori

| Situazione | Comportamento |
|------------|---------------|
| Permesso registrazione schermo assente o revocato | Finestra guidata (7.3); nessuna cattura |
| Cattura fallita (finestra chiusa, schermo scollegato) | Notifica non bloccante; nessun documento creato |
| File `.pinxel` corrotto o non valido | Errore con motivo; se `background.png` è integro, offre di aprirlo come immagine |
| Versione file non supportata | Apertura in sola lettura con avviso |
| Cartella di salvataggio automatico non scrivibile / disco pieno | Errore con proposta di scegliere un'altra cartella; la cattura resta aperta nell'editor |
| Scorciatoia globale già in uso | Avviso nelle preferenze, campo evidenziato |

Logging con `os.Logger` (subsystem `com.degiorgi.pinxel`), nessuna telemetria.

## 11. Test

| Area | Tipo | Contenuto |
|------|------|-----------|
| `DocumentModel` | unit | invariante apply/revert per ogni comando; rinumerazione step; mappatura coordinate con crop/resize/cut-out; merge dei comandi da tastiera |
| `Persistence` | unit | round-trip con tutti i tipi di annotazione; migrazione di versione; conservazione `unknown`; file corrotti, path traversal, limiti di dimensione |
| `Rendering` | snapshot | ogni strumento su immagine fissa vs PNG di riferimento (tolleranza per-pixel); export 1x/2x; sfocatura/pixel |
| `CaptureKit` | unit + manuale | geometria overlay, unione multi-monitor, conversioni di scala; checklist manuale per la cattura reale (richiede permesso) |
| `EditorUI` | unit + UI | `ToolController` con eventi sintetici → comandi attesi; pochi XCUITest per cattura → modifica → export |

Framework: Swift Testing per i test unitari, XCTest per UI test e snapshot
(confronto PNG implementato in-house, senza dipendenze esterne).

## 12. Struttura del repository

```
reatool/
├── Pinxel.xcodeproj
├── Pinxel/                 # target app: App, Info.plist, entitlements, asset
├── PinxelKit/              # Swift package locale
│   ├── Package.swift
│   ├── Sources/{DocumentModel,Rendering,CaptureKit,Persistence,EditorUI}/
│   └── Tests/{…}Tests/
├── PinxelUITests/
└── docs/superpowers/specs/
```

Entitlements: hardened runtime; nessuna sandbox nella v1 (semplifica cattura
finestre e cartelle di salvataggio; da rivalutare per un'eventuale
distribuzione sul Mac App Store). Nessuna dipendenza esterna nella v1.
