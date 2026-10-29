# Server συγχρονισμού

Κρατά **ένα κρυπτογραφημένο blob ανά λογαριασμό**. Η κρυπτογράφηση γίνεται στις συσκευές (AES-256-GCM, με κλειδί από τον κωδικό μέσω PBKDF2), οπότε ο server δεν μπορεί να διαβάσει τα δεδομένα και δεν γνωρίζει τον κωδικό. Για τη σύνδεση αποθηκεύει μόνο το SHA-256 ενός δεύτερου κλειδιού που παράγεται επίσης στη συσκευή.

Τρέχει στο VPS `smarthome` στη διεύθυνση **https://sync.62-238-96-63.sslip.io**, με Docker.

## Ενημέρωση στο VPS
```sh
rsync -az --delete --exclude node_modules --exclude .wrangler --exclude .data --exclude 'deploy/.env' ./ smarthome:/opt/spending-sync/
ssh smarthome 'cd /opt/spending-sync/deploy && docker compose up -d --build'
```
Τα δεδομένα μένουν στο volume `spending-sync_sync-data`. Το Caddy ανοίγει μόνο τη θύρα 443 και βγάζει πιστοποιητικό μέσω TLS-ALPN, γιατί τη θύρα 80 τη χρησιμοποιεί άλλη υπηρεσία.

## Εκτίμηση θερμίδων από φωτογραφία (προαιρετικά)
Η εφαρμογή στέλνει τη φωτογραφία (μικρή, ~1024 px) στον server, και ο server σε AI με το δικό σου API key. Η φωτογραφία δεν αποθηκεύεται στον server. Ο server κρατά μόνο πόσες εκτιμήσεις έκανε κάθε λογαριασμός το τελευταίο 24ωρο. Δύο επιλογές:

| `ESTIMATE_PROVIDER` | Key | Μοντέλο (προεπιλογή) | Κόστος για ~4 φωτογραφίες/ημέρα | Ιδιωτικότητα |
|---|---|---|---|---|
| `claude` | `ANTHROPIC_API_KEY` (console.anthropic.com) | `claude-haiku-5-5` | ~0,10 €/μήνα | Δεν χρησιμοποιούνται για εκπαίδευση |
| `gemini` | `GEMINI_API_KEY` (aistudio.google.com) | `gemini-3.8-flash` | 0 € (δωρεάν έκδοση, με όρια) | Στη δωρεάν έκδοση η Google μπορεί να τις χρησιμοποιεί για βελτίωση των προϊόντων της |

Άλλο μοντέλο: `ESTIMATE_MODEL` (π.χ. `claude-opus-5-5`, πιο ακριβές, ~3–4 €/μήνα). Όριο: `ESTIMATES_PER_DAY` (40).

Ο server κανονικά δεν έχει πρόσβαση στο internet. Για τις εκτιμήσεις του δίνει πρόσβαση το `deploy/docker-compose.estimate.yml`:
```sh
ssh smarthome
cd /opt/spending-sync/deploy
echo 'ESTIMATE_PROVIDER=gemini' >> .env && echo 'GEMINI_API_KEY=...' >> .env && chmod 600 .env
docker compose -f docker-compose.yml -f docker-compose.estimate.yml up -d --build
```
Για αλλαγή πάροχου: άλλαξε το `ESTIMATE_PROVIDER` στο `.env` και ξανατρέξε την τελευταία εντολή.

## Ανάπτυξη
```sh
npm run dev   # Node.js + SQLite στο :8787
npm test      # tests απέναντι σε τρέχοντα server (SYNC_URL=… για άλλον)
node --test test/estimate.test.js   # η εκτίμηση από φωτογραφία, χωρίς server και δίκτυο
```
Εναλλακτικοί τρόποι εγκατάστασης: `deploy/install.sh` (systemd + Caddy, χωρίς Docker) ή Cloudflare Workers (`src/index.js`, `wrangler.toml`).

## API
| | |
|---|---|
| `POST /v1/register {username, auth}` | 201, 409 αν το όνομα υπάρχει, 429 μετά από 10 εγγραφές/IP/ημέρα |
| `GET /v1/data` | `{version, blob}` |
| `PUT /v1/data {version, blob}` | `{version}`, ή 409 με το τρέχον blob (optimistic concurrency) |
| `DELETE /v1/account` | 204 |
| `POST /v1/estimate {image, note?}` | Εκτίμηση θερμίδων από φωτογραφία (JPEG base64) μέσω Claude ή Gemini: `{items, kcal, confidence, note}`. 503 αν δεν έχει ρυθμιστεί, 429 μετά από 40/ημέρα |

Σύνδεση: header `Authorization: Sync <user>:<base64 auth key>`. Μετά από 10 λάθος προσπάθειες ο λογαριασμός κλειδώνει για 15 λεπτά.
