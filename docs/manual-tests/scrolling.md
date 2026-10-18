# Checklist manuale — cattura a scorrimento

Prerequisiti: Pinxel firmato (Signing.local.xcconfig), Registrazione schermo concessa. Lo scorrimento lo fa sempre
l'utente; Accessibilità serve solo perché Esc e Invio non arrivino all'app sotto (S17).

| # | Prova | Risultato atteso |
|---|-------|------------------|
| S1 | Safari, pagina lunga con intestazione fissa: ⌃⇧5, trascina un'area sul contenuto, scorri fino in fondo con mouse o trackpad, Fine | L'immagine non ha righe doppie né buchi; l'intestazione compare una volta sola |
| S2 | Una chat lunga (Messaggi o WhatsApp) | Come S1; i fumetti non sono tagliati né ripetuti |
| S3 | Mail, un messaggio lungo | Come S1 |
| S4 | Finder in vista elenco con molti file | Righe tutte presenti, nessuna ripetuta (contenuto ripetitivo) |
| S5 | Un PDF in Anteprima | Come S1 |
| S6 | Una pagina quasi tutta bianca | Nessun errore; l'immagine ha la lunghezza giusta |
| S7 | Durante S1 scorri anche verso l'alto, poi di nuovo giù | Non si aggiunge nulla tornando su, nulla di duplicato scendendo |
| S8 | Senza toccare niente dopo la selezione | Pinxel non scorre da solo; il pannello dice "Scorri verso il basso, poi premi Fine o Invio" |
| S9 | Area che occupa tutto lo schermo | Il pannello sta in basso a destra; non compare nell'immagine |
| S10 | Esc durante la cattura | Nessuna immagine, nessuna notifica |
| S11 | Invio o Fine a metà | L'immagine contiene la parte cucita fin lì |
| S12 | Area più bassa di 100 punti | Avviso "Area troppo bassa…", nessuna cattura |
| S13 | Un video in riproduzione nell'area | Nessuna riga spuria aggiunta mentre non scorri; Fine consegna la parte cucita |
| S14 | "Dopo la cattura" su Solo appunti / Editor / Anteprima rapida | L'immagine lunga segue l'impostazione |
| S15 | Preferenze → Scorciatoie | C'è "Cattura a scorrimento" con ⌃⇧5, modificabile |
| S16 | Durante S1 sposta il puntatore sul pannello e premi Fine | La cattura finisce con quanto cucito; il pannello non compare nell'immagine |
| S17 | Finder in vista elenco con un file selezionato: Invio durante la cattura | La cattura finisce; il Finder non entra in modifica del nome. In una chat Invio non invia il messaggio |
| S18 | Area che comprende la barra di scorrimento (scroller sovrapposti) | Nessun pezzo della barra ripetuto lungo il bordo destro dell'immagine |
| S19 | Area con elenchi che si evidenziano al passaggio del puntatore o mostrano un suggerimento | Nessuna evidenziazione o suggerimento ripetuto nell'immagine |
| S20 | Un colpo veloce sul trackpad | Il pannello dice in arancione "Troppo veloce: torna un po' su per riprendere"; tornando su la cattura riprende senza righe doppie |
