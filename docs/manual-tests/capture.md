# Test manuali — cattura (ScreenCaptureKit reale)

Build: `xcodegen generate && xcodebuild -project Pinxel.xcodeproj -scheme Pinxel build`, poi avvia Pinxel.app
(percorso: `xcodebuild -project Pinxel.xcodeproj -scheme Pinxel -showBuildSettings | grep " BUILT_PRODUCTS_DIR "`).
Segna ogni voce con ✅ / ❌ e note.

| # | Passi | Atteso | Esito |
|---|-------|--------|-------|
| M0 | Avvia Pinxel e apri il menu dalla barra dei menu | Icona fotocamera; voci Cattura area/finestra/schermo con ⌃⇧1–3, Ripeti ultima area ⌃⇧4, Apri…, Preferenze…, Esci | |
| M0b | Preferenze…: cambia azione, attiva salvataggio, registra una nuova scorciatoia | La finestra si apre; l'etichetta nel menu si aggiorna con la nuova scorciatoia | |
| M1 | Primo avvio senza permesso, premi ⌃⇧1 | Si apre la finestra "Permesso di registrazione schermo"; nessuna cattura nera | |
| M2 | Concedi il permesso, premi "Riavvia Pinxel", poi ⌃⇧1 | Overlay su tutti gli schermi con l'immagine congelata, cursore a mirino, lente con colore | |
| M3 | Trascina un'area e rilascia | Si apre una finestra con esattamente l'area selezionata, nitida (Retina) | |
| M4 | ⌃⇧1, passa sopra una finestra e clicca | Cattura della sola finestra, senza finestre sovrapposte; ombra secondo le Preferenze | |
| M5 | ⌃⇧2, scegli una finestra che si chiude da sola (es. un popup) prima del clic | Notifica "La finestra è stata chiusa prima della cattura", nessun documento | |
| M6 | Revoca il permesso in Impostazioni di Sistema, premi ⌃⇧1 | Di nuovo la finestra del permesso, nessuna cattura nera | |
| M7 | Con due monitor a scale diverse, seleziona un'area a cavallo | Immagine unica, alla scala maggiore, allineata | |
| M8 | ⌃⇧3 e clic su uno schermo | Cattura dello schermo intero | |
| M9 | ⌃⇧4 dopo una cattura d'area | Ricattura la stessa area senza overlay | |
| M10 | Durante il trascinamento: ⇧ (quadrato), frecce, Spazio (sposta), Esc | Comportamenti come da spec §7.2 | |
| M11 | Preferenze → Anteprima veloce; cattura | Miniatura in basso a destra per 5 s; trascinala su Finder (crea un PNG); clic apre il documento | |
| M12 | Preferenze → Solo appunti; cattura, incolla in Anteprima → Nuovo dagli appunti | Immagine incollata corretta, notifica di conferma | |
| M13 | Salvataggio automatico attivo in una cartella in sola lettura | Notifica di errore e la cattura resta aperta in una finestra | |
| M14 | Assegna una scorciatoia già usata da un'altra app | Avviso rosso nelle Preferenze | |
| M15 | Apri un documento: l'icona compare nel Dock; chiudilo | L'icona sparisce dal Dock | |
| M16 | Ricompila l'app e cattura | Con firma Apple Development il permesso resta concesso (con firma ad hoc viene richiesto di nuovo) | |
