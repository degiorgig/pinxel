# Prove a mano — Libreria

Avvia l'app normale (libreria in `~/Pictures/Pinxel/Library`).

| # | Prova | Atteso |
|---|-------|--------|
| L1 | Cattura un'area con "Solo appunti", poi Riapri l'ultima cattura | Si apre il file della libreria; la miniatura c'è |
| L2 | Annota, chiudi la finestra | Nessuna domanda di salvataggio; la miniatura mostra l'annotazione |
| L3 | Ritaglia una cattura, chiudi, riapri Pinxel | Dimensioni e miniatura aggiornate |
| L4 | Clic su un'altra miniatura | Sostituita nella stessa finestra, stessa posizione |
| L5 | Nuova dagli appunti (⇧⌘N), clic su una miniatura | Stessa finestra; il documento di prima ora è nel carosello |
| L6 | ⌘-clic su tre miniature, clic destro ▸ Sposta in ▸ Nuova cartella… "Lavoro" | Le tre stanno in Lavoro; il menu Cartella ▸ Lavoro mostra solo quelle |
| L7 | Etichette ▸ Nuova etichetta… "bug" su una, poi "BUG" su un'altra | Una sola etichetta "bug"; il filtro le mostra entrambe |
| L8 | Cerca "safari", poi la data di oggi (2026-10-19) | Filtri corretti; accenti e maiuscole ignorati |
| L9 | Elimina (⌫) una cattura aperta in un'altra finestra | La finestra si chiude; il file è nel Cestino |
| L10 | Trascina una miniatura oltre il bordo sinistro della tela | Diventa un oggetto immagine, annotazioni comprese; la tela si allarga da quella parte; ⌘Z annulla tutto in un passo |
| L11 | Trascina una miniatura nel Finder | Arriva un PNG con il nome della cattura |
| L12 | Trascina un PNG dal Finder sulla striscia | Entra nella libreria; l'originale resta |
| L13 | Nascondi il carosello (toolbar, menu Vista o ⌃⌘L), apri un'altra cattura | Nascosto anche lì; riavviando resta nascosto |
| L14 | Esci da Pinxel, rovina `library.json` (scrivi "x"), riapri | Avviso; catture presenti, cartelle ed etichette perse; `library.json.rovinato` esiste |
| L15 | Cancella un `.pinxel` dal Finder, torna su Pinxel | La miniatura sparisce |
| L16 | Con 200+ catture (copia file nella cartella), scorri il carosello | Scorrimento fluido, miniature che arrivano senza bloccare |
| L17 | Apri un editor con il carosello visibile, al primo avvio dopo l'aggiornamento | Le miniature si vedono intere, non tagliate in basso |
| L18 | Trascina in su il bordo superiore del carosello | Il cursore diventa quello di ridimensionamento; il carosello si alza e le miniature crescono, sempre nitide |
| L19 | Trascina il bordo fino in cima, con la finestra bassa | Si ferma prima: alla tela restano sempre almeno 240 punti; trascinando in giù si ferma all'altezza minima |
| L20 | Chiudi la finestra, aprine un'altra e poi riavvia Pinxel | Il carosello ha l'altezza scelta; doppio clic sul bordo superiore lo riporta all'altezza iniziale |
| L21 | Passa il mouse su una miniatura | In alto a destra compare una X; togliendo il mouse sparisce |
| L22 | Clic sulla X di una miniatura che non è aperta | La cattura sparisce dal carosello e finisce nel Cestino; la finestra resta com'è |
| L23 | Clic sulla X della miniatura aperta in questa finestra | Come con ⌫: la cattura va nel Cestino e la finestra si chiude |
