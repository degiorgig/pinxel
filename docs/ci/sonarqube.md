# SonarQube Cloud

Il job `test` del workflow CI analizza ogni pull request e `main` con SonarQube Cloud, dopo i test del pacchetto.
Il quality gate fallito fa fallire il job, così la PR lo mostra. Per i repository pubblici SonarQube Cloud è gratuito e
analizza anche Swift.

## Configurazione, una volta sola

1. Entra su [sonarcloud.io](https://sonarcloud.io) con **l'account GitHub privato che possiede `degiorgig/pinxel`**
   (Log in ▸ GitHub).
2. Importa l'account come organizzazione: ＋ ▸ Create new organization ▸ scegli `degiorgig`, piano **Free**. Dai
   all'app SonarQube Cloud accesso almeno a `pinxel`.
3. Analizza il progetto: ＋ ▸ Analyze new project ▸ `pinxel`. La chiave attesa è **`degiorgig_pinxel`** e
   l'organizzazione **`degiorgig`** (sono in `sonar-project.properties`): se SonarQube Cloud ne propone altre,
   correggi quel file.
4. Project ▸ Administration ▸ Analysis Method: **disattiva Automatic Analysis** (con l'analisi da CI attiva le due si
   escludono) e scegli GitHub Actions.
5. Genera il token: My Account ▸ Security ▸ Generate Tokens.
6. Imposta il secret del repository **dall'app Terminale** (non con `!`: senza terminale interattivo il valore resta
   vuoto), incollando il token quando `gh` lo chiede. Sostituisce quello eventualmente già presente:

   ```sh
   gh secret set SONAR_TOKEN --repo degiorgig/pinxel
   ```

   Il secret `SONAR_HOST_URL` non serve: l'indirizzo è nel workflow.
7. Rilancia la CI di una PR: compaiono i passi "SonarQube coverage report" e "SonarQube analysis", e SonarQube Cloud
   commenta la PR.

## Cosa viene analizzato

- Codice: `App/Pinxel`, `PinxelKit/Sources`, `scripts`. Test: `App/PinxelUITests`, `PinxelKit/Tests`.
- Copertura: i test del pacchetto girano con `-enableCodeCoverage YES`; `scripts/sonar/xccov_to_generic.py` converte il
  risultato nel formato generico di Sonar (`build/sonar-coverage.xml`). L'app e gli script non hanno test unitari, quindi
  sono esclusi dal calcolo della copertura (`sonar.coverage.exclusions`): altrimenti il quality gate predefinito (80% sul
  codice nuovo) fallirebbe su ogni PR che tocca `App`.
- Le PR da fork non vedono i secret: l'analisi viene saltata.
