# Pinxel — Localizzazione in quattro lingue — Design

- **Data:** 2026-10-20
- **Stato:** proposta, in revisione
- **Ramo:** `feat/pinxel-localization` (parte da `main`, dopo la release 0.1.0)

## 1. Obiettivo

Oggi ogni testo dell'interfaccia è scritto in italiano direttamente nel codice
(circa 200 nell'app, circa 30 nomi di comandi, più avvisi, accessibilità e il
menu col tasto destro nei moduli di PinxelKit). L'utente vuole l'app in
**italiano, inglese, tedesco e francese**.

### Criteri di successo

1. Con il Mac (o la lingua di Pinxel in Impostazioni di Sistema ▸ Generali ▸
   Lingua e Zona ▸ App) in una delle quattro lingue, ogni testo che l'app
   mostra è in quella lingua: menu, barra degli strumenti, impostazioni,
   pannelli, fogli, avvisi, notifiche, nomi in "Annulla …", menu col tasto
   destro, suggerimenti, valori di accessibilità, tipi di documento nel Finder.
2. Con il Mac in un'altra lingua l'app è in inglese.
3. Aggiungere una lingua in futuro significa solo tradurre i cataloghi.
4. La libreria esistente dell'utente si ritrova intatta dopo l'aggiornamento.
5. Nessun testo mostrato resta scritto come letterale fuori dai cataloghi
   (un test lo impedisce per le traduzioni mancanti).

## 2. Decisioni

| Decisione | Scelta |
|-----------|--------|
| Lingue | Inglese (base), italiano, tedesco, francese |
| Scelta della lingua | Segue il Mac; nessun selettore in Pinxel |
| Lingua di riserva | Inglese |
| Lingua dei testi nel codice | Inglese; le altre sono traduzioni |
| Strumento | String Catalog (`.xcstrings`) di Xcode, uno per l'app e uno per ogni modulo che mostra testi |
| Cartella della libreria | `~/Pictures/Pinxel/Library` in tutte le lingue, con migrazione da `Libreria` |
| Nome predefinito dei file | Tradotto (`at` / `alle` / `um` / `à`); un modello personalizzato non cambia |
| Formato `.pinxel` e indice della libreria | Invariati (versione 2): niente testi tradotti dentro i file |
| Documenti del progetto | Spec, piani e prove a mano restano in italiano; README in inglese (PR #12) |
| Traduzioni tedesche e francesi | Scritte dall'implementatore, da far rileggere a un madrelingua |

## 3. Dove vivono i testi

### 3.1 App

- `project.yml`: `options.developmentLanguage: en`; `knownRegions` (o
  equivalente generato) con `en`, `it`, `de`, `fr`.
- I testi SwiftUI (`Text`, `Button`, `Label`, `Toggle`, `Picker`, `Section`,
  `CommandMenu`, `.help`…) sono già `LocalizedStringKey`: si riscrivono in
  inglese e Xcode li raccoglie in `App/Pinxel/Localizable.xcstrings`
  (`SWIFT_EMIT_LOC_STRINGS = YES`).
- I testi passati come `String` (titoli calcolati, avvisi AppKit, notifiche)
  usano `String(localized:)`.
- `App/Pinxel/InfoPlist.xcstrings`: `CFBundleTypeName` ("Pinxel Document",
  "Image") e `UTTypeDescription` dei tipi esportati. Il nome dell'app resta
  "Pinxel" in tutte le lingue.

### 3.2 PinxelKit

- `Package.swift`: `defaultLocalization: "en"`.
- Ogni modulo che mostra testi (`DocumentModel`, `EditorUI`, `AppCore` e, per
  le poche scritte che hanno, `Library`, `Rendering`, `CaptureKit`) ha
  `Sources/<Modulo>/Localizable.xcstrings` dichiarato come risorsa
  (`resources: [.process("Localizable.xcstrings")]`).
- Nel codice: `String(localized: "Move", bundle: .module, comment: "…")`.
  Il commento descrive dove compare il testo (aiuta chi traduce).
- I nomi dei comandi (es. "Sposta", "Ritaglia", "Adatta tela") stanno in un
  solo punto per modulo, come costanti già tradotte (es. `CommandName.move`):
  i comandi e i test usano la stessa costante.
- I titoli calcolati (`EditorTool.title`, `PostCaptureAction.title`, nomi delle
  scorciatoie e dei tasti speciali in `KeyCombo`, `ImageOperation.name`) passano
  dal catalogo del loro modulo.

### 3.3 Testi composti

Le frasi con numeri o nomi (es. il valore di accessibilità della tela
"Annotazioni: %lld, selezionate: %lld, immagine: %lld×%lld") usano
l'interpolazione di `String(localized:)`, così ogni lingua può cambiare l'ordine
delle parole. I plurali, dove servono, usano le varianti del catalogo.

### 3.4 Rischio da verificare per primo

I cataloghi `.xcstrings` dentro un pacchetto Swift devono compilarsi sia da
Xcode sia da riga di comando (`swift build` / `swift test`). Il primo passo del
piano lo verifica su un modulo. Se da riga di comando non funzionano, i moduli
usano i file `.strings` per lingua (`en.lproj`, `it.lproj`…) generati dal
catalogo; l'impostazione resta la stessa.

## 4. Cartella della libreria

- Il nome diventa `Library` (`LibraryStore`), uguale in tutte le lingue.
- All'avvio, prima di leggere la libreria:
  - esiste `Libreria` e non `Library` → la si rinomina con uno spostamento
    (`FileManager.moveItem`), senza copiare: catture e `library.json` restano;
  - esistono tutte e due → si usa `Library`, `Libreria` resta com'è;
  - non esiste nessuna → si crea `Library` come oggi;
  - lo spostamento fallisce → in quella sessione si usa `Libreria` e lo si
    scrive nel log (livello `.notice`).
- La libreria degli UI test (`-PinxelUITestLibraryName`) non passa dalla
  migrazione.

## 5. Nome predefinito dei file

- `FileNamer.defaultTemplate` diventa una stringa del catalogo di `AppCore`:
  `'Pinxel' yyyy-MM-dd 'at' HH.mm.ss` (en), `… 'alle' …` (it), `… 'um' …` (de),
  `… 'à' …` (fr).
- Le impostazioni salvate oggi contengono il modello: un modello uguale al
  vecchio predefinito (`… 'at' …`) viene trattato come "non personalizzato" e
  segue la lingua; qualunque altro modello resta com'è.

## 6. Cosa non si traduce

- I testi scritti dall'utente nelle annotazioni.
- Nomi e chiavi interni: JSON dei documenti, `library.json`, nomi delle
  immagini negli archivi, identificatori di accessibilità (`pinxel.editor.canvas`
  ecc.), nomi dei log.
- Il nome dell'app e il formato `.pinxel`.

## 7. Errori e casi limite

| Situazione | Comportamento |
|------------|---------------|
| Lingua del Mac non supportata | Inglese |
| Testo senza traduzione in una lingua (non dovrebbe succedere: test §8) | Si vede l'inglese |
| Migrazione della libreria impossibile | Si usa `Libreria`, log `.notice` |
| Modello del nome file personalizzato | Invariato |
| File `.pinxel` creati in un'altra lingua | Si aprono uguali: dentro non ci sono testi tradotti |

## 8. Test

| Area | Cosa si verifica |
|------|------------------|
| Cataloghi | Per ogni `.xcstrings` (app e moduli): ogni chiave ha `it`, `de`, `fr`, nessuna traduzione vuota o "da rivedere", stessi segnaposto (`%lld`, `%@`) in tutte le lingue |
| Test esistenti | Dove confrontano testi mostrati (nomi in "Annulla", voci di menu, accessibilità) li confrontano con le costanti tradotte, non con parole italiane: passano su un Mac in qualunque lingua |
| Migrazione | Solo `Libreria`, tutte e due, nessuna, spostamento impossibile |
| Nome file | Predefinito nelle quattro lingue; modello personalizzato invariato; vecchio predefinito trattato come non personalizzato |
| UI test | Avviati con `-AppleLanguages (it)`: quelli esistenti restano validi; uno nuovo in inglese controlla menu e barra; uno rapido in tedesco e in francese |
| Prove a mano | `docs/manual-tests/localization.md`: le quattro lingue da Impostazioni di Sistema; libreria spostata con tutte le catture |
