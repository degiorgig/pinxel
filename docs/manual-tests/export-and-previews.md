# Checklist manuale — export PDF, salvataggio automatico, anteprime, cattura a scorrimento interrotta

Prerequisiti: chiudi il Pinxel installato (le scorciatoie andrebbero in conflitto), poi compila e apri la build Debug:

```sh
xcodegen generate
xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/dev build
open build/dev/Build/Products/Debug/Pinxel.app
```

La build Debug può chiedere di nuovo il permesso di Registrazione schermo. Le catture finiscono nella libreria vera:
alla fine cancella quelle di prova.

## Export PDF

| # | Prova | Risultato atteso |
|---|-------|------------------|
| P1 | Cattura, aggiungi un testo e una freccia sopra, esporta in PDF e apri in Anteprima | ⌘F trova il testo e si può selezionare; ingrandendo, testo e freccia restano nitidi |
| P2 | Scrivi un testo e coprilo con un rettangolo pieno, esporta in PDF | ⌘F **non** trova il testo coperto |
| P3 | Aggiungi un testo in una zona senza immagini, esporta in PDF | Il testo resta selezionabile |
| P4 | Esporta la stessa cattura in PNG e in PDF, confrontale affiancate | Colori identici |
| P5 | Con l'ombra del canvas attiva, esporta in PDF | L'ombra c'è ed è come nell'editor |

## Salvataggio automatico

| # | Prova | Risultato atteso |
|---|-------|------------------|
| S1 | Attiva il salvataggio automatico con una cartella, cattura lo schermo intero | L'anteprima compare subito, si può avviare un'altra cattura senza attese; il file compare nella cartella |
| S2 | Rendi la cartella non scrivibile (`chmod a-w <cartella>`), cattura | Notifica d'errore e la cattura si apre nell'editor; nessun blocco. Poi `chmod u+w <cartella>` |

## Anteprime rapide

| # | Prova | Risultato atteso |
|---|-------|------------------|
| A1 | Molte catture di fila senza chiudere le anteprime | Si impilano verso l'alto; arrivate in cima parte una colonna a sinistra; arrivate al bordo sinistro la pila riparte dall'angolo. Nessuna anteprima fuori schermo |
| A2 | Due monitor: con anteprime aperte sul monitor A, cattura sul monitor B | La nuova anteprima resta sul monitor A, insieme alle altre |
| A3 | A2, poi chiudi tutte le anteprime e cattura sul monitor B | L'anteprima compare sul monitor B |

## Cattura a scorrimento

| # | Prova | Risultato atteso |
|---|-------|------------------|
| C1 | Avvia una cattura a scorrimento e fermala | Il risultato va in libreria come sempre, nessun avviso |
| C2 | Facoltativa (non c'è un modo affidabile per provocarla): chiudi la finestra catturata mentre scorre | Avviso "Cattura a scorrimento incompleta" (nella lingua del sistema); la parte catturata si apre nell'editor e **non** è in libreria. Il caso è coperto anche dai test automatici |
