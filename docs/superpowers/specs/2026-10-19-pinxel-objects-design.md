# Pinxel — Immagini come oggetti e tela adattata al contenuto — Design

- **Data:** 2026-10-19
- **Stato:** proposta, in revisione
- **Ramo:** `feat/pinxel-objects` (parte da `feat/pinxel-library`, PR #8)

## 1. Obiettivo

Oggi la cattura è lo sfondo fisso del documento: non si seleziona, non si
sposta, non si ridimensiona, e la tela ha una dimensione fissa che cambia solo
con ritaglio, ridimensiona, taglia e ricuci o con un'immagine trascinata (che la
allarga solo a destra e in basso). L'utente vuole che:

1. l'immagine catturata sia **sempre** un oggetto modificabile, come le
   immagini trascinate o incollate, anche senza trascinare niente;
2. la tela segua **sempre** il contenuto: cresce in ogni direzione e si stringe.

### Criteri di successo

1. Aperta una cattura, la sua immagine si seleziona, si sposta, si
   ridimensiona, si ruota, si elimina e si riordina con gli strumenti esistenti.
2. Dopo ogni modifica la tela è il rettangolo che racchiude tutto il contenuto;
   sullo schermo nessun oggetto salta quando la tela cambia.
3. Sfocatura, pixel e lente funzionano sopra qualsiasi immagine, anche
   trascinata.
4. Ogni file `.pinxel` esistente si apre identico a prima (stesso render) e
   diventa modificabile nel nuovo modo.
5. Un'azione dell'utente = un solo passo di annulla, adattamento della tela
   compreso.

## 2. Decisioni

| Decisione | Scelta |
|-----------|--------|
| Quando l'immagine è un oggetto | Sempre, per ogni documento (scelta dell'utente) |
| Tela | Sempre il rettangolo che racchiude il contenuto, cresce e si stringe |
| Cosa conta per i bordi | Tutti gli oggetti, anche annotazioni e oggetti ruotati |
| Quando si adatta | Alla fine di ogni comando (al rilascio, non durante il trascinamento) |
| Coordinate | Sempre con origine in alto a sinistra della tela: il comando trasla gli oggetti |
| Effetti (sfocatura, pixel, lente) | Campionano tutto ciò che sta sotto di loro nella pila |
| Ritaglio | Taglia tutto il contenuto sul rettangolo; annotazioni del tutto fuori eliminate, quelle a cavallo restano intere |
| Ridimensiona (menu) | Scala tutto il contenuto |
| Taglia e ricuci | Toglie la fascia da tutte le immagini che attraversa e avvicina ciò che c'è oltre |
| ⌘V / ⌥⌘V | ⌘V sostituisce l'immagine in fondo tenendo le annotazioni; ⌥⌘V aggiunge un'immagine-oggetto |
| Estendi tela | Rimossa: non serve più |
| Formato | `.pinxel` versione 2; i file versione 1 si convertono all'apertura |
| Trascinamento dal carosello | Invariato: arriva un'immagine appiattita |

Alternative scartate: composizione solo dopo il primo trascinamento (l'utente
vuole l'immagine sempre modificabile); tela con origine mobile nel modello
(rendering, selezione, guide ed export dovrebbero tutti conoscerla); effetti che
leggono solo l'immagine in fondo (una sfocatura sopra un'immagine trascinata
sembrerebbe rotta).

## 3. Modello del documento

### 3.1 Versione 2

```swift
struct PinxelDocument {
    var canvasSize: PixelSize          // calcolata: rettangolo del contenuto
    var scale: Double
    var colorSpace: ColorSpaceID
    var canvasStyle: CanvasStyle       // padding, colore, bordo, ombra intorno al contenuto
    var annotations: [Annotation]      // l'immagine catturata è un .image in fondo
    var metadata: CaptureMetadata
}
```

- Spariscono `background` e `imageOperations`: l'immagine catturata è una
  normale `Annotation` di tipo `.image` (indice 0 alla creazione), con il suo
  asset in `assets/`.
- `imageSize` resta come nome per la dimensione del contenuto (uguale a
  `canvasSize`), così chi oggi lo legge (libreria, esportazione, miniature)
  continua a funzionare.
- `PlacedImageData` resta `rect` + `asset`: ridimensionare scala il rettangolo,
  i pixel dell'asset non cambiano (come oggi per le immagini trascinate).
  Ritaglio e taglia e ricuci producono un nuovo asset (§5).
- Documento senza oggetti: `canvasSize` zero, l'editor lo mostra come la tela
  vuota di ⌘N (scacchiera e suggerimento "incolla").

### 3.2 Adattamento della tela

Funzione pura in `DocumentModel`:

```swift
enum ContentFit {
    /// Rettangolo intero (pixel) che racchiude tutti gli oggetti, rotazione compresa.
    static func bounds(of annotations: [Annotation]) -> PixelRect?
    /// Trasla tutto perché il rettangolo parta da (0,0) e imposta canvasSize.
    static func fitted(_ document: PinxelDocument) -> (document: PinxelDocument, offset: CGVector)
}
```

- I bordi di ogni oggetto sono quelli che la selezione già usa (bounds ruotati,
  spessore del tratto e ombra compresi, così una freccia spessa non viene
  tagliata).
- Arrotondamento all'esterno ai pixel interi.
- Limite: lato massimo `PinxelDocument.maxImageSide`. Se il contenuto è più
  grande, la tela si ferma al limite partendo dall'angolo in alto a sinistra
  del contenuto; la parte oltre non si vede e non si esporta.
- `EditorSession.perform` avvolge ogni comando in un `CommandGroup` con un
  comando `FitCanvas` calcolato dopo il primo: un solo passo di annulla.
  `FitCanvas` registra la traslazione e la dimensione di prima, quindi
  `revert(apply(d)) == d` vale ancora.
- Nessun `FitCanvas` se il rettangolo non cambia (nessuno spreco nella pila di
  annulla, nessun ricalcolo).
- La vista riceve l'`offset` e sposta lo scroll della stessa quantità × zoom:
  gli oggetti restano fermi sullo schermo.
- Durante un gesto (trascinamento, ridimensionamento, rotazione) l'anteprima
  non adatta la tela; si adatta al rilascio.

### 3.3 Conversione dei file versione 1

All'apertura di un file con `version == 1`, in memoria:

1. si calcola lo sfondo elaborato con `BackgroundProcessor.process` (le
   operazioni di ritaglio, ridimensiona, taglia e ricuci ed estendi già fatte);
2. lo si salva come asset nuovo e si inserisce un'annotazione `.image` in
   indice 0 con rettangolo `(0, 0, larghezza, altezza)` elaborate;
3. le annotazioni restano con le loro coordinate (sono già nello spazio dopo
   le operazioni);
4. si applica `ContentFit.fitted`.

- Il render del documento convertito deve coincidere con quello della
  versione 1 quando nessuna annotazione esce dall'immagine. Se un'annotazione
  usciva, prima era tagliata e ora allarga la tela: è il nuovo comportamento
  voluto.
- Il file su disco non cambia finché il documento non viene salvato (anche dal
  salvataggio automatico). Una volta salvato è versione 2: la versione
  vecchia di Pinxel lo apre in sola lettura (regola esistente sulle versioni).
- `PinxelArchive.readDocument` (lettura leggera per la libreria) converte
  senza decodificare le immagini: la dimensione elaborata si ricava da
  `imageSize` della versione 1, senza toccare i pixel.

## 4. Effetti: sfocatura, pixel, lente

- Per un effetto in posizione `i` della pila, la sorgente è il render dei
  livelli `0..<i` (immagini e annotazioni), ritagliato alla regione
  dell'effetto con un piccolo margine per il raggio della sfocatura.
- Cache: chiave = hash dei livelli sotto l'effetto che intersecano la regione
  + parametri dell'effetto. Spostare un oggetto lontano dalla regione non
  invalida la cache.
- Due effetti uno sopra l'altro: quello sopra vede quello sotto già applicato.
- La lente ingrandisce ciò che sta sotto di lei allo stesso modo.
- Conseguenza: una sfocatura sopra una freccia o un numero ora li sfoca.
  Prima no, perché leggeva solo lo sfondo. Per tenerli nitidi basta portarli
  sopra la sfocatura.
- Nei file versione 1 convertiti le annotazioni sotto un effetto possono
  quindi apparire sfocate dove prima non lo erano: accettato.

## 5. Strumenti dell'immagine

### 5.1 Ritaglia

- Il riquadro di ritaglio parte dall'intera tela.
- Conferma: per ogni immagine che il riquadro taglia, nuovo asset con solo la
  parte dentro (rotazione compresa: si ritaglia nello spazio dell'immagine,
  l'area fuori diventa trasparente se l'immagine è ruotata); immagini del tutto
  fuori eliminate; annotazioni del tutto fuori eliminate; annotazioni a cavallo
  restano intere; poi `FitCanvas`.
- Un solo passo di annulla (gli asset vecchi restano nell'archivio finché la
  pila di annulla li usa, come oggi per le immagini eliminate).

### 5.2 Ridimensiona (menu Immagine)

- Il pannello mostra la dimensione della tela; il nuovo valore scala tutti gli
  oggetti rispetto all'angolo in alto a sinistra (rettangoli, punti, spessori
  e diametri con la stessa `lengthScale` di oggi).
- Le immagini cambiano solo il rettangolo, gli asset no.

### 5.3 Taglia e ricuci

- La fascia si disegna sulla tela come oggi.
- Ogni immagine che la fascia attraversa ottiene un nuovo asset senza la
  fascia (stesso bordo dritto o a zig-zag di oggi); gli oggetti oltre la
  fascia si avvicinano della sua larghezza (mappatura `collapse` di oggi).
- Immagini ruotate attraversate dalla fascia: si spostano come le annotazioni,
  senza tagliarne i pixel (non c'è un taglio dritto sensato).

### 5.4 Incolla

- **⌘V** con un'immagine: sostituisce l'asset dell'immagine in fondo alla pila
  (la prima `.image` dall'indice 0) con le dimensioni della nuova, tenendo le
  annotazioni; senza immagini nella pila aggiunge la nuova in fondo. È il
  comportamento di oggi ("lo sfondo viene sostituito e la tela prende la sua
  dimensione") nel nuovo modello.
- **⌥⌘V** e trascinamento sulla tela: aggiungono un'immagine-oggetto nel punto
  indicato, la tela si adatta. Il parametro `growsCanvas` e l'operazione
  `.extend` spariscono.

## 6. Editor

- Clic sull'immagine con lo strumento Selezione: la seleziona. Gli altri
  strumenti disegnano sopra come oggi (un clic con la Freccia su un'immagine
  disegna una freccia, non seleziona l'immagine).
- Trascinare partendo da un'immagine **non selezionata** disegna il riquadro
  di selezione, come oggi sullo sfondo: altrimenti, con la cattura grande
  quanto la tela, non si potrebbe più selezionare col riquadro. Per spostare
  un'immagine: clic per selezionarla, poi trascinarla. Le annotazioni si
  spostano trascinandole subito, come oggi.
- Le guide magnetiche considerano anche le immagini.
- Il bordo della tela e la scacchiera seguono il rettangolo adattato.
- ⌘A seleziona anche le immagini.
- Elimina con l'immagine selezionata: la toglie; se non resta niente la tela
  è vuota.
- Lucchetto (Disponi ▸ Blocca) funziona anche sulle immagini, per non
  spostarle per errore mentre si annota.

## 7. Cattura, libreria, esportazione

- `CaptureDocumentBuilder` crea documenti versione 2: un'immagine-oggetto in
  indice 0, tela uguale alla cattura.
- Libreria: dimensioni nell'indice e miniature dalla tela adattata; nessun
  altro cambiamento. Il trascinamento dal carosello resta un'immagine
  appiattita.
- Esportazione e copia: il render della tela adattata; le parti senza oggetti
  sono trasparenti o del colore di sfondo della tela.

## 8. Errori

| Situazione | Comportamento |
|------------|---------------|
| File versione 1 il cui sfondo non si elabora | Errore di apertura come oggi per un file rovinato |
| Contenuto oltre il lato massimo | Tela fermata al limite (§3.2) |
| Ritaglio che non contiene nessun oggetto | Pulsante di conferma disattivato |
| Versione file maggiore di 2 | Sola lettura con avviso (regola esistente) |

## 9. Test

| Area | Contenuto |
|------|-----------|
| `ContentFit` | rettangolo di immagini, frecce spesse, oggetti ruotati; oggetti a sinistra e in alto (traslazione); eliminazione che stringe; tela vuota; limite massimo |
| `FitCanvas` / sessione | un comando = un passo di annulla; `revert(apply(d)) == d`; nessun `FitCanvas` se non cambia niente |
| Conversione v1 | ogni operazione (ritaglio, ridimensiona, taglia e ricuci, estendi) con annotazioni; render uguale al v1; `readDocument` leggero |
| Effetti | sfocatura sopra un'immagine trascinata; sopra una freccia; due effetti sovrapposti; lente; cache non invalidata da un oggetto lontano |
| Ritaglio / Ridimensiona / Taglia e ricuci | più immagini, immagini ruotate, annotazioni dentro, fuori, a cavallo |
| Incolla | ⌘V sostituisce l'immagine in fondo tenendo le annotazioni; ⌥⌘V e trascinamento aggiungono |
| Persistenza | round-trip versione 2; file v1 aperto, salvato, riaperto |
| Vista | l'offset della tela sposta lo scroll: un oggetto fermo resta nello stesso punto dello schermo |
| UI test | apri una cattura, trascina l'immagine a destra, la tela si allarga |
| Prove a mano | nuove voci in `docs/manual-tests/objects.md` |
