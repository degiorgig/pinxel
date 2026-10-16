# Pinxel — Cattura a scorrimento — Design

- **Data:** 2026-10-17
- **Stato:** proposta, in revisione
- **Ambito:** sottoprogetto 3 della roadmap (vedi `2026-10-14-pinxel-capture-editor-design.md`)

## 1. Obiettivo

Catturare in un'unica immagine un contenuto più lungo dello schermo — pagine web,
chat, mail, documenti, liste — in **qualsiasi app**, browser compreso.

### Decisioni prese con l'utente

| Tema | Decisione |
|------|-----------|
| App supportate | Tutte allo stesso modo (nessuna integrazione specifica col browser) |
| Chi scorre | Pinxel scorre da solo; l'utente può intervenire scorrendo a mano in qualsiasi momento |
| Selezione | Rettangolo trascinato, come la cattura area |
| Direzione | Solo verticale, verso il basso |
| Destinazione | Come le altre catture: segue l'impostazione "Dopo la cattura" |
| Metodo di cucitura | Confronto tra fotogrammi (approccio A); lo scorrimento inviato è solo un indizio |

### Criteri di successo

1. Un'immagine lunga senza righe doppie né buchi, identica pixel per pixel al
   contenuto originale nei test con pagine sintetiche.
2. Intestazioni e barre fisse dentro l'area compaiono una volta sola.
3. Funziona in app che scorrono più o meno del richiesto (scorrimento fluido,
   accelerazione) e con lo scorrimento a mano.
4. Senza permesso Accessibilità la cattura resta possibile scorrendo a mano.
5. Nessuna finestra di Pinxel (cornice, pannello) finisce nell'immagine.

### Fuori ambito

Scorrimento orizzontale; selezione con clic su una finestra o rilevamento
automatico della vista che scorre; integrazioni specifiche per browser (DOM,
estensioni); impostazione "Dopo la cattura" separata per lo scorrimento.

## 2. Flusso per l'utente

1. **Avvio.** Voce **"Cattura a scorrimento"** nel menu dell'icona e scorciatoia
   globale configurabile nelle Preferenze, predefinita **⌃⇧5** (⌃⇧1–4 sono già
   delle altre catture). Si apre l'overlay della cattura area: schermo congelato,
   trascinamento del rettangolo, maniglie e frecce come oggi. Esc annulla.
2. **Conferma dell'area.** Al rilascio l'overlay sparisce (il contenuto deve
   muoversi davvero). Restano:
   - una **cornice** sottile attorno all'area, disegnata appena fuori dal rettangolo;
   - un **pannello flottante** non attivante, accanto all'area e fuori da essa
     (sotto, sopra o di lato, dove c'è spazio sullo stesso schermo), con
     **Fine**, **Annulla**, una **miniatura** dell'immagine che cresce e
     l'altezza in pixel. Materiale traslucido di sistema; la miniatura cresce con
     animazione continua (rispettando "Riduci movimento").
3. **Scorrimento.** Pinxel scorre a passi dentro l'area. L'utente può scorrere a
   mano in qualsiasi momento: Pinxel aggiunge ciò che vede e riprende da solo
   dopo 1 s senza scorrimenti manuali. Scorrendo verso l'alto non si aggiunge
   nulla.
4. **Fine.** In uno di questi casi:
   - in fondo alla pagina (due passi di fila senza spostamento);
   - **Fine** o **Invio**;
   - raggiunto il limite di 32.768 px di altezza (`PinxelDocument.maxImageSide`):
     il pannello lo dice e l'immagine si tiene.
   L'immagine passa per `CaptureDocumentBuilder` e "Dopo la cattura" come le altre.
   **Esc** o **Annulla** scartano tutto.
5. **Senza Accessibilità.** Al primo uso Pinxel spiega perché serve il permesso e
   apre le Impostazioni di Sistema; la cattura parte comunque in modalità
   "Scorri tu" (il pannello lo indica). Lo chiede una volta sola; dopo, solo un
   promemoria nel pannello.

Esc e Invio arrivano da un monitor di eventi globale (disponibile con
Accessibilità) e locale; senza Accessibilità restano i pulsanti del pannello.

## 3. Componenti

### PinxelKit / CaptureKit (logica pura, senza interfaccia)

- **`ScrollStitcher`** — riceve i fotogrammi in ordine, calcola lo spostamento
  rispetto al precedente, riconosce le fasce fisse e accumula l'immagine lunga.
  Non conosce schermi né eventi. Interfaccia:
  - `init(maxHeight: Int)`
  - `mutating func add(_ frame: CGImage, hint: Int?) -> StitchStep` — `hint` è lo
    spostamento atteso in pixel (passo automatico) o `nil` (scorrimento a mano);
  - `var height: Int`, `func image() -> CGImage?`.
  `StitchStep` = `.appended(rows)`, `.unchanged`, `.movedBack`, `.noMatch`,
  `.reachedLimit`.
- **`RegionFrameSource`** (protocollo, `@MainActor`) —
  `func frame(of rect: CGRect, on display: DisplayInfo) async throws -> CGImage`.
  Implementazione vera con ScreenCaptureKit (`SCScreenshotManager` con
  `sourceRect`, filtro che esclude le finestre di Pinxel). Implementazione finta:
  `FakeScrollingPage`, una pagina lunga virtuale con posizione di scorrimento.
- **`ScrollDriver`** (protocollo, `@MainActor`) —
  `func scroll(by points: Double, at point: CGPoint)`. Implementazione vera con
  `CGEvent` di scorrimento in pixel. La finta sposta `FakeScrollingPage` e può
  applicare un fattore (es. 0,7 o 1,3) per simulare app che scorrono diversamente.

### AppCore

- **`ScrollCaptureSession`** (`@MainActor`, `@Observable`) — il ciclo
  cattura → cuci → scorri → attendi stabilità → ripeti; decide la fine; pubblica
  stato, altezza e miniatura. Dipende solo dai due protocolli, quindi si testa
  senza schermo né permessi.
- **`AccessibilityPermission`** — controllo (`AXIsProcessTrusted`) e richiesta,
  sul modello di `ScreenRecordingPermission`.
- **`HotKeyAction.scrolling`** — nuova azione con titolo "Cattura a scorrimento" e
  combinazione predefinita ⌃⇧5. Le impostazioni salvate senza questa azione
  devono continuare a decodificarsi (la nuova azione prende il suo predefinito).

### App

- **`ScrollCaptureController`** — riusa l'overlay di selezione in modalità area;
  poi mostra cornice e pannello (SwiftUI in un `NSPanel` non attivante), collega
  pulsanti e tasti alla sessione e consegna l'immagine al percorso post-cattura.
- **Menu e Preferenze** — voce nel menu dell'icona e riga nella lista delle
  scorciatoie, come le altre azioni.
- **UI test** — argomento di lancio `-PinxelUITestFakeScrolling` che usa
  `FakeScrollingPage` al posto dello schermo vero.

## 4. Algoritmo di cucitura

1. **Firma delle righe.** Ogni riga del fotogramma, in scala di grigi, diventa un
   vettore di 32 medie di blocchi orizzontali. Il confronto usa la differenza
   media assoluta tra firme: veloce e tollerante a piccole differenze di resa.
2. **Fasce fisse.** Confrontando fotogrammi consecutivi alla stessa posizione, le
   righe iniziali e finali identiche (mentre il centro cambia) sono fasce fisse.
   Si escludono dal confronto. Nell'immagine finale la fascia superiore entra una
   volta, dal primo fotogramma; quella inferiore una volta, dall'ultimo; in mezzo
   il contenuto che scorre.
3. **Spostamento.** Per ogni spostamento `d` tra 0 e l'altezza utile si misura
   quanto combaciano le righe vecchie da `d` in giù con le nuove dall'inizio
   (sovrapposizione minima: 1/4 dell'altezza utile). Vince l'errore minimo; a
   parità entro una tolleranza vince il più vicino a `hint`.
   - **Ambiguo** (contenuto uniforme: più spostamenti sotto soglia) → si usa
     `hint` se c'è; senza `hint` il fotogramma si scarta e si aspetta il prossimo.
   - **Nessuna corrispondenza** sotto soglia → `.noMatch`: la sessione torna su di
     mezzo passo e riprova con passi dimezzati.
4. **Posizione.** Lo stitcher tiene la posizione totale; aggiunge righe solo oltre
   il punto più basso già catturato. Spostamenti negativi (verso l'alto) si
   riconoscono cercando anche `d < 0` e aggiornano solo la posizione.
5. **Passi e stabilità.** Il passo automatico è 2/3 dell'altezza utile
   dell'area. Dopo ogni passo si cattura finché due fotogrammi consecutivi sono
   identici, al massimo 500 ms. In modalità a mano si cattura a circa 10
   fotogrammi al secondo.
6. **Fine.** Due passi di fila con `.unchanged`, o comando dell'utente, o
   `.reachedLimit`.
7. **Qualità.** Fotogrammi alla risoluzione nativa dello schermo; le righe nuove
   si copiano pixel per pixel, senza ricampionare.

## 5. Errori e casi limite

- **Registrazione schermo negata**: finestra di permesso esistente, come le altre catture.
- **Accessibilità negata**: modalità "Scorri tu" (sezione 2).
- **Area troppo bassa** (meno di 100 pt): il pannello lo dice e propone di allargarla; non si parte.
- **Più schermi**: l'area è limitata allo schermo dove è iniziata.
- **Contenuto che cambia da solo** (video, animazioni): dopo 3 `.noMatch` di
  fila la cattura si ferma e tiene il cucito; il pannello avvisa.
- **Finestra spostata o chiusa**: stesso comportamento.
- **Memoria**: prima di iniziare si calcola la dimensione massima
  (larghezza in pixel × 32.768 × 4 byte); oltre 1 GB l'area si limita in
  larghezza, avvisando.
- **Pinxel nell'immagine**: cornice e pannello stanno fuori dall'area e sono
  esclusi dal filtro di ScreenCaptureKit.

## 6. Test

- **`ScrollStitcherTests`** su pagine sintetiche (righe numerate, testo, zone
  bianche): spostamenti esatti; app al 70% e al 130%; intestazione e barra fisse;
  contenuto uniforme con e senza `hint`; scorrimento all'indietro; salto troppo
  grande; fine pagina; limite di altezza. Il risultato deve coincidere pixel per
  pixel con la pagina originale.
- **`ScrollCaptureSessionTests`** con `FakeScrollingPage`: flusso completo;
  Fine e Annulla; scorrimento a mano senza Accessibilità; contenuto che cambia;
  fermata al limite; area troppo bassa.
- **Persistenza impostazioni**: impostazioni salvate senza `scrolling` si
  decodificano con il predefinito.
- **UI test**: con `-PinxelUITestFakeScrolling`, cattura a scorrimento dal menu e
  verifica dell'altezza dell'immagine risultante.
- **Checklist manuale** (`docs/manual-tests/scrolling.md`): Safari con
  intestazione fissa, una chat, Mail, Finder in vista elenco, un PDF in
  Anteprima, una pagina quasi tutta bianca, scorrimento a mano, senza permesso
  Accessibilità.
