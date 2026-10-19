# Pinxel

Cattura dello schermo e editor di annotazioni per macOS, nativo (SwiftUI + AppKit).

## Cosa fa

- **Catture:** area, finestra (con o senza ombra), schermo intero, ripeti l'ultima area e cattura a scorrimento (scorri tu, Pinxel ricuce).
- **Dopo la cattura:** apri l'editor, un'anteprima veloce o copia solo negli appunti. Ogni cattura finisce anche nella libreria.
- **Editor:**
  - **Strumenti:** frecce, linee, forme, testo, callout, step numerati, penna, evidenziatore, sfocatura e pixelatura, lente d'ingrandimento.
  - **Immagine:** ritaglio, taglia e ricuci, ridimensiona, bordo, ombra e margini.
  - **Oggetti:** la cattura e le immagini trascinate sono oggetti come gli altri. Si spostano, si ruotano e si mettono sopra o sotto; la tela si adatta sempre al contenuto.
  - **Comodità:** stili rapidi, guide magnetiche, oggetti bloccati, annulla e ripeti.
- **Libreria:** tutte le catture in `~/Pictures/Pinxel/Libreria`, con il carosello sotto l'editor (⌃⌘L), cartelle, etichette e ricerca.
- **Esportazione:** PNG, JPEG, HEIC e PDF. Puoi anche condividere o trascinare la cattura in un'altra app.
- **Formato:** i documenti `.pinxel` tengono annotazioni modificabili e immagini originali.

## Scorciatoie predefinite

| Scorciatoia | Azione |
|---|---|
| ⌃⇧1 | Cattura un'area |
| ⌃⇧2 | Cattura una finestra |
| ⌃⇧3 | Cattura lo schermo intero |
| ⌃⇧4 | Ripeti l'ultima area |
| ⌃⇧5 | Cattura a scorrimento |

Si cambiano in Impostazioni. Nell'editor ogni strumento ha la sua lettera (passaci sopra col puntatore per vederla).

## Requisiti

- macOS 15 o successivo (Apple Silicon e Intel).
- Permesso di **Registrazione schermo** (Impostazioni di Sistema ▸ Privacy e sicurezza), richiesto al primo avvio.

## Installazione

Scarica `Pinxel-<versione>.dmg` o `.zip` dalle [release](https://github.com/degiorgig/pinxel/releases) e trascina Pinxel in Applicazioni.

Le build pubblicate non sono notarizzate da Apple. Su un Mac diverso da quello che le ha firmate, macOS le blocca al primo avvio: apri l'app con clic destro ▸ Apri, oppure da Impostazioni di Sistema ▸ Privacy e sicurezza ▸ Apri comunque.

## Compilare dai sorgenti

Servono Xcode (provato con Xcode 27) e [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open Pinxel.xcodeproj
```

Senza altre impostazioni l'app è firmata ad hoc, e macOS chiede di nuovo il permesso di Registrazione schermo a ogni build. Per una firma stabile crea `App/Config/Signing.local.xcconfig` (escluso da git) con il tuo certificato:

```
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = Apple Development
DEVELOPMENT_TEAM = <il tuo team ID>
```

Test del pacchetto: `cd PinxelKit && swift test`.
