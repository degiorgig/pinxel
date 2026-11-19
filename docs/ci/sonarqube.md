# SonarQube Server

Il job `test` del workflow CI analizza ogni pull request e `main` con SonarQube Server, dopo i test del pacchetto.
Il quality gate fallito fa fallire il job, così la PR lo mostra.

## Requisiti del server

- Raggiungibile dai runner GitHub (internet), in HTTPS.
- **Developer Edition o superiore**: la Community Edition non analizza Swift né le pull request.
- Per i commenti sulla PR: in Administration ▸ DevOps Platform Integrations, l'integrazione GitHub (una GitHub App con
  accesso a `degiorgig/pinxel`), poi nel progetto Project Settings ▸ General Settings ▸ DevOps Platform Integration.

## Configurazione, una volta sola

1. Crea il progetto con chiave **`pinxel`** (è in `sonar-project.properties`), da Create Project ▸ GitHub se
   l'integrazione c'è, altrimenti manualmente con analisi da CI ▸ GitHub Actions.
2. Crea un token di analisi del progetto: My Account ▸ Security ▸ Generate Tokens, tipo *Project Analysis Token*.
3. Imposta i due secret del repository **dall'app Terminale** (non con `!`: senza terminale interattivo il valore
   resta vuoto), incollando il valore quando `gh` lo chiede:

   ```sh
   gh secret set SONAR_HOST_URL --repo degiorgig/pinxel
   gh secret set SONAR_TOKEN --repo degiorgig/pinxel
   ```

4. Rilancia la CI di una PR: compaiono i passi "SonarQube coverage report" e "SonarQube analysis".

## Cosa viene analizzato

- Codice: `App/Pinxel`, `PinxelKit/Sources`, `scripts`. Test: `App/PinxelUITests`, `PinxelKit/Tests`.
- Copertura: i test del pacchetto girano con `-enableCodeCoverage YES`; `scripts/sonar/xccov_to_generic.py` converte il
  risultato nel formato generico di Sonar (`build/sonar-coverage.xml`). L'app (cartella `App`) non ha test unitari,
  quindi lì la copertura è zero: se il quality gate la richiede sul codice nuovo, conviene escludere `App/**` dalla
  copertura con `sonar.coverage.exclusions`.

Per provare in locale: `sonar-scanner -Dsonar.host.url=… -Dsonar.token=…` dalla radice del repository, dopo aver
generato `build/sonar-coverage.xml` come fa la CI.
