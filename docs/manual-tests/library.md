# Prove a mano — Libreria

Avvia l'app normale (libreria in `~/Pictures/Pinxel/Libreria`).

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
| L10 | Trascina una miniatura vicino al bordo destro della tela | Diventa un oggetto immagine, annotazioni comprese; la tela si allarga per contenerlo; ⌘Z annulla tutto in un passo |
| L11 | Trascina una miniatura nel Finder | Arriva un PNG con il nome della cattura |
| L12 | Trascina un PNG dal Finder sulla striscia | Entra nella libreria; l'originale resta |
| L13 | Nascondi il carosello (toolbar, menu Vista o ⌃⌘L), apri un'altra cattura | Nascosto anche lì; riavviando resta nascosto |
| L14 | Esci da Pinxel, rovina `library.json` (scrivi "x"), riapri | Avviso; catture presenti, cartelle ed etichette perse; `library.json.rovinato` esiste |
| L15 | Cancella un `.pinxel` dal Finder, torna su Pinxel | La miniatura sparisce |
| L16 | Con 200+ catture (copia file nella cartella), scorri il carosello | Scorrimento fluido, miniature che arrivano senza bloccare |
