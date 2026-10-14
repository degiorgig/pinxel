# Test manuali — editor

Build: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel build`, poi avvia Pinxel.app e fai una cattura con l'azione "Apri l'editor".
Segna ogni voce con ✅ / ❌ e note.

| # | Passi | Atteso | Esito |
|---|-------|--------|-------|
| E1 | Cattura un'area | Si apre l'editor: tela al centro adattata alla finestra, strumenti nella toolbar, proprietà a destra; la finestra è attiva (⌘E apre subito Esporta… senza cliccare prima) | |
| E2 | Premi V, A, L, R, P, H, S, B | Lo strumento attivo nella toolbar cambia; il puntatore è una freccia con V e un mirino con gli altri | |
| E3 | Disegna freccia, linea, rettangolo, penna, evidenziatore; con ⇧ freccia e rettangolo | Le forme seguono il mouse dal primo movimento; ⇧ vincola a 45° e al quadrato | |
| E4 | Tre clic con lo strumento Step | Cerchi numerati 1, 2, 3; cancellando il 2 il 3 diventa 2 | |
| E5 | Sfocatura su un testo, poi Pixel dal pannello | Il testo diventa illeggibile; cambiando effetto resta la stessa area | |
| E6 | Selezione: clic, ⇧+clic, riquadro; trascina; ⌥+trascina; frecce e ⇧+frecce | Sposta seguendo il punto preso; ⌥ duplica; frecce 1 px, ⇧ 10 px; un ⌘Z annulla tutta la raffica di frecce | |
| E7 | Ridimensiona da angoli e lati, ruota dalla maniglia (⇧ = passi di 15°), poi ridimensiona l'oggetto ruotato | L'angolo opposto resta fermo anche quando l'oggetto è ruotato | |
| E8 | Pannello: colore (trascina nella ruota colori), spessore (trascina il cursore), tratteggio, opacità, ombra | Anteprima durante il trascinamento; un solo ⌘Z annulla ogni regolazione | |
| E9 | Disponi: avanti/indietro, Duplica (⌘D), Blocca (⌘L) e prova a spostare l'oggetto bloccato; Sblocca | L'oggetto bloccato si seleziona (contorno tratteggiato) ma non si sposta né si cancella | |
| E10 | ⌘S, chiudi, riapri il file | Annotazioni identiche e ancora modificabili | |
| E11 | Zoom: pinch, ⌘+scroll, ⌘+ / ⌘- / ⌘0 / ⌘1; Spazio+trascina e scroll per spostarsi | Lo zoom resta centrato sul puntatore; ⌘1 mostra i pixel nitidi; ⌘0 riadatta | |
| E12 | ⌘C senza selezione e incolla in Anteprima → Nuovo dagli appunti | Immagine composita con le annotazioni | |
| E13 | Seleziona due oggetti, ⌘C, apri un'altra cattura, ⌘V | Le copie compaiono spostate di 10 px e selezionate | |
| E14 | File → Esporta… (⌘E): PNG 2x, JPEG qualità 50, PDF | File corretti; il PNG a 2x ha le dimensioni in pixel della cattura | |
| E15 | Toolbar → Condividi → AirDrop o Messaggi | Viene proposto un PNG con le annotazioni | |
| E16 | Aspetto chiaro e scuro; Accessibilità → Riduci movimento | Toolbar, pannello e maniglie leggibili in entrambi; nessuna animazione che blocca | |
| E17 | Con "Solo appunti": cattura, poi icona nella barra dei menu → Modifica ultima cattura | La cattura si apre nell'editor; prima di qualsiasi cattura la voce è disattivata | |
| E18 | Copia un'immagine (es. da Safari), poi icona → Nuova dagli appunti, oppure ⌘N con l'editor in primo piano | L'immagine si apre nell'editor; uno screenshot Retina mantiene la scala 2x. Senza immagine negli appunti compare un avviso | |
| E19 | T, clic sull'immagine, scrivi "Ciao" con una parola in ⌘B, Esc; doppio clic sul testo, cambia una parola, clic fuori | Il testo resta formattato; ogni modifica è un solo ⌘Z; un testo nuovo lasciato vuoto non lascia nulla | |
| E20 | Durante la scrittura: dimensione, colore e allineamento dal pannello; poi cambia strumento con un tasto | Il testo cambia subito; cambiare strumento conferma il testo | |
| E21 | C, trascina un fumetto, scrivi; trascina la maniglia della coda e un angolo del fumetto | La coda segue il puntatore; il fumetto si ridimensiona senza spostare la punta | |
| E22 | M, trascina su un dettaglio; sposta la sorgente, poi l'ingrandimento; cambia Ingrandimento e Forma | Le due parti si spostano da sole; l'ingrandimento mostra sempre la zona sotto la sorgente | |
| E23 | K, trascina un riquadro, sposta e ridimensiona con ⇧, Invio; poi ⌘Z | L'immagine e le annotazioni vengono ritagliate insieme; ⌘Z ripristina tutto; Esc annulla senza ritagliare | |
| E24 | X, trascina in verticale su una fascia; poi in orizzontale; prova Dritto e Zig-zag | Durante il trascinamento la fascia è rossa; al rilascio sparisce e le parti si ricuciono | |
| E25 | Immagine → Ridimensiona immagine… al 50%; Immagine → Bordo, ombra e margini…: ombra, margine 40, sfondo | Anteprima dal vivo sulla tela; Annulla non cambia niente; Applica è un solo ⌘Z; l'export include ombra e margini | |
| E26 | Sposta un oggetto vicino al bordo di un altro e al centro dell'immagine; ripeti tenendo ⌘ | Compaiono guide rosa e l'oggetto si aggancia; con ⌘ niente guide | |
| E27 | Crea tre frecce con stili diversi; seleziona una forma; clicca uno stile rapido | Gli ultimi stili compaiono nel pannello per strumento e restano dopo il riavvio | |
| E28 | Copia un'immagine in Safari e incollala (⌘V); salva, chiudi, riapri; trascina l'icona foto della toolbar sulla Scrivania | L'immagine incollata è centrata e resta dopo la riapertura; sulla Scrivania compare un PNG con le annotazioni | |
| E29 | Apri un file danneggiato (vedi Task 13 Step 6 del piano 4) | L'errore offre "Apri l'immagine", che apre la cattura in un documento nuovo | |
| E30 | Apri un file di versione futura (modifica `manifest.json` a `"version": 99`) | Banner "solo leggere" sopra la tela; strumenti e menu di modifica grigi; Esporta funziona | |
| E31 | Menu Modifica e Disponi senza selezione, con un oggetto bloccato, e nelle Preferenze | Voci grigie quando non possono agire; "Annulla <azione>"; nelle Preferenze ⌘C/⌘V funzionano nei campi | |
| E32 | Cattura area su un Retina, poi frecce durante la selezione | Le dimensioni cambiano di 1 pixel per freccia (10 con ⇧) | |
