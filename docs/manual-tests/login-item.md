# Checklist manuale — apertura al login

Prerequisiti: Pinxel firmato (Signing.local.xcconfig o la build della release), copiato in /Applications, con una sola
copia installata: l'elemento di login punta alla copia che lo registra. Per rifare la domanda del primo avvio:
`defaults delete com.degiorgi.pinxel` (cancella anche le altre impostazioni).

| # | Prova | Risultato atteso |
|---|-------|------------------|
| L1 | Primo avvio, senza impostazioni | Pinxel chiede "Apri Pinxel al login?" in primo piano, una volta sola |
| L2 | L1, "Apri al login" | Impostazioni ▸ Generali: l'interruttore è attivo; Impostazioni di Sistema ▸ Generali ▸ Elementi login elenca Pinxel |
| L3 | Esci e rientra nella sessione (o riavvia) | Pinxel parte da solo: icona nella barra dei menu, nessuna finestra |
| L4 | L1, "Non ora", poi riavvia Pinxel | Nessuna domanda; l'interruttore è spento |
| L5 | Spegni l'interruttore in Pinxel | Pinxel sparisce da Elementi login; al login successivo non parte |
| L6 | Con Impostazioni di Pinxel aperte, togli Pinxel da Elementi login, poi torna a Pinxel | L'interruttore si spegne da solo |
| L7 | Elementi login chiede di consentire Pinxel | Sotto l'interruttore compare "Consenti Pinxel in Elementi login…" con il pulsante che apre Impostazioni di Sistema |
| L8 | Build App Store (sandbox) | Come L2–L5 |
