# Checklist manuale — cartelle nella build App Store

Prerequisiti: build App Store (sandbox), ad esempio il `Pinxel.pkg` del dry run installato con
`sudo installer -pkg Pinxel.pkg -target /`, in un account senza impostazioni di Pinxel. Verifica degli entitlement:
`codesign -d --entitlements - /Applications/Pinxel.app` non elenca nessun `com.apple.security.assets.*`.

| # | Prova | Risultato atteso |
|---|-------|------------------|
| F1 | Cattura un'area | La cattura compare nella libreria; i file sono in `~/Library/Containers/com.degiorgi.pinxel/Data/Library/Application Support/Pinxel/Library` |
| F2 | Impostazioni ▸ Salvataggio automatico, senza cartella scelta | Accanto a Cartella si legge "Nessuna cartella scelta" |
| F3 | Attiva "Salva automaticamente ogni cattura" | Si apre il pannello per scegliere la cartella |
| F4 | F3, Annulla | L'interruttore resta spento |
| F5 | F3, scegli una cartella | L'interruttore si accende, la cartella è mostrata; la cattura successiva viene salvata lì |
| F6 | Esci e riapri Pinxel, poi cattura | Il salvataggio automatico scrive ancora nella cartella scelta |
| F7 | Build GitHub (Developer ID) | La libreria resta in `~/Pictures/Pinxel/Library`; attivare il salvataggio non apre il pannello |
