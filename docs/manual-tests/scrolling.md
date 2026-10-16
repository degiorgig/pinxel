# Checklist manuale — cattura a scorrimento

Prerequisiti: Pinxel firmato (Signing.local.xcconfig), Registrazione schermo concessa. Per S1–S7 anche Accessibilità.

| # | Prova | Risultato atteso |
|---|-------|------------------|
| S1 | Safari, pagina lunga con intestazione fissa: ⌃⇧5, trascina un'area sul contenuto | Pinxel scorre da solo fino in fondo; l'immagine non ha righe doppie né buchi; l'intestazione compare una volta sola |
| S2 | Una chat lunga (Messaggi o WhatsApp) | Come S1; i fumetti non sono tagliati né ripetuti |
| S3 | Mail, un messaggio lungo | Come S1 |
| S4 | Finder in vista elenco con molti file | Righe tutte presenti, nessuna ripetuta (contenuto ripetitivo) |
| S5 | Un PDF in Anteprima | Come S1 |
| S6 | Una pagina quasi tutta bianca | Nessun errore; l'immagine ha la lunghezza giusta |
| S7 | Durante S1 scorri a mano con il trackpad, anche verso l'alto | Pinxel aggiunge ciò che vedi, non duplica nulla, riprende da solo dopo 1 s |
| S8 | Revoca Accessibilità, ripeti S1 | Il pannello dice "Scorri tu"; scorrendo a mano l'immagine cresce; Fine la consegna |
| S9 | Area che occupa tutto lo schermo | Il pannello sta in basso a destra; non compare nell'immagine |
| S10 | Esc durante la cattura | Nessuna immagine, nessuna notifica |
| S11 | Invio o Fine a metà | L'immagine contiene la parte cucita fin lì |
| S12 | Area più bassa di 100 punti | Avviso "Area troppo bassa…", nessuna cattura |
| S13 | Un video in riproduzione nell'area | La cattura si ferma con "Il contenuto cambia da solo"; resta la parte già cucita |
| S14 | "Dopo la cattura" su Solo appunti / Editor / Anteprima rapida | L'immagine lunga segue l'impostazione |
| S15 | Preferenze → Scorciatoie | C'è "Cattura a scorrimento" con ⌃⇧5, modificabile |
