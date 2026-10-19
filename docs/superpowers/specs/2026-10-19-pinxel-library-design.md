# Pinxel — Libreria delle catture — Design

- **Data:** 2026-10-19
- **Stato:** proposta, in revisione
- **Ambito:** libreria/cronologia, rinviata dalla v1 (vedi `2026-10-14-pinxel-capture-editor-design.md`)

## 1. Obiettivo

Un **archivio permanente** di tutte le catture, da organizzare con cartelle ed
etichette e da consultare e usare mentre si lavora, tramite un **carosello**
di miniature sotto l'immagine dell'editor.

### Decisioni prese con l'utente

| Tema | Decisione |
|------|-----------|
| Scopo | Archivio da organizzare, non solo cronologia recente |
| Cosa entra | Ogni cattura, in automatico, qualunque sia "Dopo la cattura"; i file esterni solo trascinandoli sul carosello |
| Organizzazione | Cartelle (una o nessuna per cattura) ed etichette (zero o più) |
| Interfaccia | Solo il carosello in fondo all'editor, con filtri e ricerca sopra; nessuna finestra Libreria separata |
| Azioni sulla miniatura | Clic apre nella finestra; trascinare sulla tela, trascinare fuori; menu contestuale |
| Conservazione | Approccio A: cartella gestita con un file `.pinxel` per cattura più un indice `library.json` |

### Criteri di successo

1. Ogni cattura, anche "Solo appunti", compare nel carosello e si riapre
   modificabile dopo un riavvio di Pinxel.
2. Le modifiche a una cattura dell'archivio si salvano da sole: chiudendo la
   finestra non viene chiesto di salvare e la miniatura si aggiorna.
3. Nessuna cattura si perde per un indice rovinato o mancante: si perdono al
   più cartelle ed etichette.
4. Il carosello resta fluido con 2000 catture nell'archivio.

### Fuori ambito

OCR e ricerca nel testo delle immagini; sincronizzazione iCloud; cartelle
annidate; finestra Libreria separata; scelta della posizione dell'archivio;
importazione automatica dei file aperti dal Finder o della cartella del
salvataggio automatico.

## 2. Flusso per l'utente

### Archiviazione

1. Si fa una cattura qualsiasi (area, finestra, schermo, ripeti area,
   scorrimento). Prima di ogni altro passo di "Dopo la cattura" Pinxel la
   scrive nell'archivio come `.pinxel`.
2. "Apri l'editor" e l'anteprima veloce (quando la si apre) aprono **il file
   dell'archivio**, non un documento senza titolo. "Solo appunti" copia come
   oggi.
3. Il salvataggio automatico, se attivo, continua a scrivere la sua copia
   (PNG o `.pinxel`) nella sua cartella, indipendente dall'archivio.
4. "Riapri l'ultima cattura" dal menu apre il file dell'archivio quando c'è.

### Carosello

- Striscia alta ~110 pt in fondo a ogni finestra dell'editor, sotto la tela;
  i controlli di zoom e la maniglia di trascinamento salgono sopra di essa.
- Si mostra e nasconde con un pulsante nella toolbar e con
  Vista ▸ Mostra/Nascondi carosello (⌥⌘L); la scelta vale per tutte le
  finestre ed è ricordata nelle preferenze. Visibile per impostazione
  predefinita.
- Miniature dalla più nuova (a sinistra) alla più vecchia, scorrimento
  orizzontale. Quella aperta nella finestra ha il bordo nel colore di accento.
  Se l'archivio (o il filtro) è vuoto, un testo spiega che le catture
  compariranno qui.
- Barra sopra la striscia:
  - **Cartella ▾**: Tutte, Senza cartella, le cartelle in ordine alfabetico;
    poi Nuova cartella…, Rinomina cartella…, Elimina cartella (le ultime due
    sulla cartella scelta). Eliminare una cartella lascia le catture, senza
    cartella.
  - **Etichetta ▾**: Tutte oppure una sola etichetta.
  - **Ricerca**: testo libero, senza distinzione di maiuscole e accenti, su
    app, titolo della finestra, etichette, nome della cartella e data
    (formattata come nel nome del file, per esempio "2026-10-19").
  - I tre filtri si combinano (E logico).

### Azioni sulle miniature

- **Clic**: apre la cattura.
  - Se la finestra mostra una cattura dell'archivio, quella viene sostituita
    nella stessa finestra (stessa posizione e dimensione).
  - Se mostra un documento esterno o senza titolo, la cattura si apre in una
    finestra nuova: nulla di non salvato va perso.
  - Se la cattura è già aperta in un'altra finestra, si porta avanti quella.
- **Selezione multipla**: ⌘-clic aggiunge o toglie, ⇧-clic estende; il clic
  semplice seleziona e apre.
- **Trascinare sulla tela**: diventa un oggetto immagine nella cattura
  attuale, come ⌥⌘V, con le annotazioni della cattura trascinata già
  incorporate.
- **Trascinare fuori**: file PNG renderizzato, con il nome del file della
  cattura.
- **Trascinare file dal Finder sulla striscia**: immagini e `.pinxel` entrano
  nell'archivio (copiati; l'originale non si tocca). Altri file sono ignorati.
- **Menu contestuale** (sulla selezione): Copia, Apri in una nuova finestra,
  Sposta in ▸ (Senza cartella, cartelle, Nuova cartella…), Etichette ▸
  (spunte sulle etichette esistenti, Nuova etichetta…), Mostra nel Finder,
  Elimina.
- **⌫** con il fuoco sulla striscia elimina la selezione. Eliminare sposta i
  file nel Cestino senza chiedere conferma; le finestre aperte su quelle
  catture si chiudono prima.

## 3. Conservazione

- Cartella: `~/Pictures/Pinxel/Libreria` (creata al primo uso).
- Un file `.pinxel` per cattura, nome da `FileNamer` con il modello
  predefinito e mai sovrascritto (`FileNamer.uniqueURL`), scritto come
  `AutoSaver`: file nascosto temporaneo, poi spostamento.
- `library.json` nella stessa cartella, scritto in modo atomico:

```json
{
  "version": 1,
  "folders": [{ "id": "UUID", "name": "Lavoro" }],
  "items": [{
    "file": "Pinxel 2026-10-19 at 10.15.03.pinxel",
    "added": "2026-10-19T08:15:03Z",
    "captureDate": "2026-10-19T08:15:03Z",
    "appName": "Safari", "windowTitle": "…",
    "pixelWidth": 2400, "pixelHeight": 1600,
    "folder": "UUID o assente",
    "tags": ["bug", "doc"]
  }]
}
```

- L'identità di una cattura è il nome del file. Le etichette non hanno una
  lista propria: sono l'unione delle etichette delle catture (si confrontano
  senza distinzione di maiuscole, si mostrano come scritte la prima volta).
- **I file comandano.** Al caricamento e quando Pinxel torna attivo si
  confrontano indice e cartella: un `.pinxel` senza voce entra (metadati letti
  dal file, senza cartella né etichette); una voce senza file esce. Un
  riferimento a una cartella inesistente diventa "senza cartella".
- **Indice rovinato o di versione futura**: si rinomina in
  `library.json.rovinato` (sostituendo un'eventuale copia precedente), si
  ricostruisce dai file e si avvisa. Un campo sconosciuto di una voce non
  impedisce di leggere le altre.
- Miniature: quelle dentro i `.pinxel` (`Thumbnailer`), lette solo quando la
  miniatura entra in vista e tenute in una cache in memoria; si rileggono
  quando il file cambia (data di modifica).

## 4. Componenti

### PinxelKit / Library (nuovo modulo, dipende da DocumentModel, Persistence e AppCore per `FileNamer`)

- `LibraryIndex`: valore `Codable` con `folders` e `items`, e operazioni pure:
  `add`, `remove`, `move(_:to:)`, `addTag`, `removeTag`, `createFolder`,
  `renameFolder`, `deleteFolder`, `reconciled(withFiles:)`, `allTags`.
- `LibraryFilter`: cartella (tutte / nessuna / id), etichetta (tutte / nome),
  testo; `apply(to:) -> [LibraryItem]` ordinate dalla più nuova.
- `LibraryStore`: tutto ciò che tocca il disco, con `FileManager` iniettabile:
  `load()`, `save(_:)`, `add(_ contents: PinxelFileContents) -> LibraryItem`,
  `importFile(at:)`, `thumbnail(for:)`, `trash(_:)`, `url(for:)`.

### App

- `LibraryModel` (`@Observable`, `@MainActor`, unico per l'app): indice
  condiviso; esegue le operazioni e salva l'indice dopo ogni modifica.
- `LibraryStripState` (uno per finestra): filtro e selezione.
- `LibraryStrip` (SwiftUI): barra dei filtri, striscia con `LazyHStack`,
  trascinamenti, menu, cache delle miniature.
- `EditorView`: la striscia sotto la tela; i controlli di zoom sopra.
- `PostCaptureActions`: `library.add` prima dei passi; `DocumentOpener` apre
  l'URL dell'archivio con `NSDocumentController`; se `add` fallisce, avviso e
  comportamento di oggi.
- Sostituzione nella stessa finestra: si salva e chiude il documento attuale,
  si apre l'altro e se ne imposta la cornice della finestra a quella vecchia.
- `PinxelFileDocument` salvato in un file dell'archivio: notifica
  `LibraryModel`, che aggiorna miniatura e dimensioni.

## 5. Errori e casi limite

| Caso | Comportamento |
|------|---------------|
| Archivio non scrivibile / disco pieno alla cattura | Avviso; la cattura segue "Dopo la cattura" come oggi (documento senza titolo se si apre l'editor) |
| `library.json` rovinato o di versione futura | Rinominato in `library.json.rovinato`, indice ricostruito dai file, avviso |
| File cancellato o aggiunto dal Finder | Allineato al controllo successivo (caricamento o ritorno su Pinxel) |
| `.pinxel` illeggibile nell'archivio | Miniatura con icona di errore; aprendolo, il messaggio di oggi con il recupero dell'immagine |
| Cestino non disponibile (volume senza Cestino) | Conferma, poi cancellazione definitiva |
| Eliminare una cattura aperta | La finestra si chiude prima di spostare il file |
| Rinominare una cartella con un nome già usato | Rifiutato con un messaggio; nomi vuoti rifiutati |
| Trascinare sulla tela la cattura aperta nella stessa finestra | Ammesso: diventa un oggetto immagine come le altre |
| Due finestre che filtrano | Filtro e selezione sono per finestra; indice condiviso |

## 6. Test

- **Library (unitari)**: operazioni dell'indice; filtro (cartella, etichetta,
  testo senza accenti e maiuscole, combinazioni); allineamento con i file;
  indice rovinato e di versione futura; aggiunta senza sovrascrivere; Cestino
  con `FileManager` finto; importazione di PNG e `.pinxel`.
- **AppCore/App**: con l'archivio attivo ogni azione di "Dopo la cattura"
  produce una voce; con archivio non scrivibile la cattura non si perde.
- **UI** (cattura finta, archivio in una cartella temporanea passata con un
  argomento di avvio): la cattura compare nel carosello; il clic sostituisce
  la cattura nella finestra; il menu Cartella filtra; nascondi/mostra.
- **Prove a mano**: `docs/manual-tests/library.md`.
