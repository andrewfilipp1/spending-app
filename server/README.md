# Server συγχρονισμού

Κρατά **ένα κρυπτογραφημένο blob ανά λογαριασμό**. Η κρυπτογράφηση γίνεται στις συσκευές (AES-256-GCM, με κλειδί από τον κωδικό μέσω PBKDF2), οπότε ο server δεν μπορεί να διαβάσει τα δεδομένα και δεν γνωρίζει τον κωδικό. Για τη σύνδεση αποθηκεύει μόνο το SHA-256 ενός δεύτερου κλειδιού που παράγεται επίσης στη συσκευή.

Τρέχει στο VPS `smarthome` στη διεύθυνση **https://sync.62-238-96-63.sslip.io**, με Docker.

## Ενημέρωση στο VPS
```sh
rsync -az --delete --exclude node_modules --exclude .wrangler --exclude .data --exclude 'deploy/.env' ./ smarthome:/opt/spending-sync/
ssh smarthome 'cd /opt/spending-sync/deploy && docker compose up -d --build'
```
Τα δεδομένα μένουν στο volume `spending-sync_sync-data`. Το Caddy ανοίγει μόνο τη θύρα 443 και βγάζει πιστοποιητικό μέσω TLS-ALPN, γιατί τη θύρα 80 τη χρησιμοποιεί άλλη υπηρεσία.

## Ανάπτυξη
```sh
npm run dev   # Node.js + SQLite στο :8787
npm test      # tests απέναντι σε τρέχοντα server (SYNC_URL=… για άλλον)
```
Εναλλακτικοί τρόποι εγκατάστασης: `deploy/install.sh` (systemd + Caddy, χωρίς Docker) ή Cloudflare Workers (`src/index.js`, `wrangler.toml`).

## API
| | |
|---|---|
| `POST /v1/register {username, auth}` | 201, 409 αν το όνομα υπάρχει, 429 μετά από 10 εγγραφές/IP/ημέρα |
| `GET /v1/data` | `{version, blob}` |
| `PUT /v1/data {version, blob}` | `{version}`, ή 409 με το τρέχον blob (optimistic concurrency) |
| `DELETE /v1/account` | 204 |

Σύνδεση: header `Authorization: Sync <user>:<base64 auth key>`. Μετά από 10 λάθος προσπάθειες ο λογαριασμός κλειδώνει για 15 λεπτά.
