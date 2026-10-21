# Mac App Store: configurazione una tantum

Cose da fare una volta sola sul portale Apple. Dopo, ogni tag `vX.Y.Z` carica anche la build App Store su
App Store Connect (job `app-store` di `.github/workflows/release.yml`).

## 1. Identificativo dell'app

[developer.apple.com](https://developer.apple.com/account/resources/identifiers/list) ▸ Certificates, IDs &
Profiles ▸ Identifiers ▸ **+** ▸ App IDs ▸ App:

- Platform: macOS
- Description: Pinxel
- Bundle ID: Explicit, `com.degiorgi.pinxel`
- Capabilities: nessuna (la sandbox non va attivata qui)

## 2. Certificati

Certificates ▸ **+**:

1. **Apple Distribution**: c'è già (scade il 2027-02-01), si può riusare.
2. **Mac Installer Distribution**: nuovo. Serve una richiesta di certificato: Accesso Portachiavi ▸ Assistente
   Certificato ▸ Richiedi un certificato da un'autorità di certificazione ▸ salvato su disco. Scarica il
   certificato e aprilo con doppio clic.

Esporta i due certificati **insieme** in un solo `.p12`: Accesso Portachiavi ▸ I miei certificati ▸ seleziona
"Apple Distribution: …" e "3rd Party Mac Developer Installer: …" (o "Mac Installer Distribution: …") ▸ clic
destro ▸ Esporta 2 elementi ▸ formato `.p12`, con una password.

## 3. Profilo di provisioning

Profiles ▸ **+** ▸ Distribution ▸ **Mac App Store Connect**:

- App ID: `com.degiorgi.pinxel`
- Certificato: Apple Distribution
- Nome del profilo: `Pinxel Mac App Store` (lo stesso di `App/Config/AppStore.xcconfig`)

Scarica il file `.provisionprofile`.

## 4. Scheda su App Store Connect

[appstoreconnect.apple.com](https://appstoreconnect.apple.com) ▸ App ▸ **+** ▸ Nuova app:

- Piattaforma: macOS; nome: Pinxel; lingua principale: Inglese (USA); bundle ID: `com.degiorgi.pinxel`; SKU: `pinxel`
- I testi in quattro lingue, la categoria, la privacy e le note per la revisione sono in
  [listing.md](listing.md).
- Prezzo: gratuito. Contratto di licenza: personalizzato, incolla il testo di `LICENSE`.
- Privacy dell'app: "Dati non raccolti".

## 5. Chiave API di App Store Connect

App Store Connect ▸ Utenti e accessi ▸ Integrazioni ▸ App Store Connect API ▸ **+**: nome "GitHub Pinxel",
accesso **App Manager**. Scarica il file `AuthKey_XXXX.p8` (si può scaricare una volta sola) e annota Key ID e
Issuer ID.

## 6. Secrets del repository

Dall'app **Terminale** (non da Claude Code: lì `gh secret set` senza `--body` salva un valore vuoto):

```sh
cd ~/work/reatool
base64 -i Certificati.p12 | gh secret set MAS_CERTIFICATES_P12
gh secret set MAS_CERTIFICATES_PASSWORD          # incolla la password del .p12
base64 -i Pinxel_Mac_App_Store.provisionprofile | gh secret set MAS_PROVISIONING_PROFILE
gh secret set ASC_KEY_P8 < AuthKey_XXXX.p8
gh secret set ASC_KEY_ID                         # incolla il Key ID
gh secret set ASC_ISSUER_ID                      # incolla l'Issuer ID
```

## 7. Prova

`gh workflow run Release` (prova senza pubblicare): il job `app-store` esporta `Pinxel.pkg` come artefatto.
Se va, al prossimo tag la build arriva su App Store Connect; da lì la scegli nella versione e premi
**Invia per la revisione**.

## Screenshot

Servono screenshot 16:10 a una di queste risoluzioni: 1280×800, 1440×900, 2560×1600 o 2880×1800. Ne bastano
da 1 a 10, per ogni lingua (o gli stessi per tutte). Conviene mostrare: l'editor con frecce e passaggi
numerati, la cattura a scorrimento, la libreria, la sfocatura.
