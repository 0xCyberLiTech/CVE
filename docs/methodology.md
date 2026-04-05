# Méthodologie — Construire un CVE Tracker de A à Z

Ce document décrit la démarche complète pour construire un tableau de bord CVE
alimenté automatiquement, de la conception au déploiement en production.

---

## Étape 1 — Comprendre la source de données : l'API NVD

L'API NVD (National Vulnerability Database) du NIST est la référence officielle.

**URL** : `https://services.nvd.nist.gov/rest/json/cves/2.0/`

**Paramètres clés** :

| Paramètre | Description | Exemple |
|-----------|-------------|---------|
| `pubStartDate` | Date de début (publication) | `2025-01-01T00:00:00` |
| `pubEndDate` | Date de fin (publication) | `2025-01-31T23:59:59` |
| `lastModStartDate` | Modifiées depuis... | `2025-04-01T00:00:00` |
| `resultsPerPage` | Max 2000 | `2000` |
| `startIndex` | Pagination | `0`, `2000`, `4000`... |

**Quota** : 50 req/30s avec clé, 5 req/30s sans.

> **Obtenir une clé** : https://nvd.nist.gov/developers/request-an-api-key (gratuit)

---

## Étape 2 — Choisir l'architecture : API directe ou fichiers statiques ?

### Option A — Appels API depuis le navigateur ❌

```
Navigateur → API NVD directement
```

**Problèmes** :
- La clé API est visible dans le code source / DevTools
- Quota partagé entre tous les visiteurs
- Lenteur (NVD peut mettre plusieurs secondes à répondre)
- Aucun contrôle du cache

### Option B — Fichiers JSON statiques (architecture choisie) ✅

```
Serveur (cron 3×/jour) → API NVD → JSON statiques → Navigateur
```

**Avantages** :
- Clé API 100% côté serveur, jamais exposée
- Chargement instantané pour le visiteur (fichiers locaux)
- Fonctionnel même si NVD est hors ligne
- Quota maîtrisé (3 req/jour ≪ 50 req/30s)

---

## Étape 3 — Sécuriser la clé API : pattern proxy nginx

La clé ne doit jamais apparaître dans un script exécutable, une variable d'environnement exposée, ou un fichier versionné.

**Solution** : nginx lit la clé depuis un fichier protégé (`chmod 600`) et l'injecte dans les headers — invisible pour les scripts, les logs applicatifs et le navigateur.

```
Script cron → http://127.0.0.1/api/nvd/?... 
             ↓ nginx injecte apiKey depuis /etc/nginx/api-keys.conf
             → https://services.nvd.nist.gov/rest/json/cves/2.0/?...apiKey=***
```

**Avantages** :
- Le script n'a jamais connaissance de la clé
- La clé n'apparaît pas dans les logs nginx (proxy_hide_header)
- La clé n'est pas dans le dépôt Git

---

## Étape 4 — Concevoir le script de collecte

### Logique de base

```bash
# 1. Construire l'URL pour le mois courant
url="http://127.0.0.1/api/nvd/?pubStartDate=2025-01-01T00:00:00
    &pubEndDate=2025-01-31T23:59:59
    &resultsPerPage=2000
    &startIndex=0"

# 2. Récupérer avec curl
response=$(curl -sf --max-time 90 "$url")

# 3. Extraire les CVE en NDJSON (1 CVE = 1 ligne)
echo "$response" | jq -c '.vulnerabilities[]?' >> /tmp/cve.ndjson

# 4. Si totalResults > 2000 : paginer (startIndex += 2000 jusqu'à épuisement)

# 5. Convertir NDJSON → tableau JSON
jq -s '.' /tmp/cve.ndjson > cve-2025-01.json.tmp
mv cve-2025-01.json.tmp cve-2025-01.json
```

### Points importants

**Pagination** : NVD retourne 2000 entrées max par requête. Un mois chargé (ex. janvier 2025 : ~3000 CVE) nécessite 2 pages.

**Écriture atomique** : toujours écrire dans un fichier `.tmp` puis renommer avec `mv`. Évite qu'un navigateur lise un fichier partiellement écrit.

**Anti-régression** : si le nouveau fichier contient moins de 80% des CVE de l'existant → conserver l'ancien. Protège contre les pannes NVD temporaires.

**Rate limiting** : pause de 6s entre pages du même mois. NVD limite à 50 req/30s — avec 1 passage toutes les 8h on est très loin du quota.

---

## Étape 5 — Concevoir l'index

Le frontend ne sait pas combien de fichiers existent. L'index résout ça :

```json
{
  "generated": "2025-04-05T06:00:00Z",
  "months": ["2025-04", "2025-03", "2025-02", "2025-01", "2024-12"]
}
```

Le JS lit `index.json` → construit le sélecteur de mois → charge `cve-YYYY-MM.json`.

---

## Étape 6 — Backfill historique

Avant de mettre en place le cron, alimenter les données historiques en une seule passe :

```bash
# Lance le backfill depuis START_YEAR/START_MONTH jusqu'au mois courant
./backfill-cve.sh >> /var/log/cve-backfill.log 2>&1
```

Durée : ~30-60 min pour 18 mois (pauses entre mois pour respecter NVD).

---

## Étape 7 — Frontend : lire les JSON statiques

```javascript
// 1. Lire l'index
const index = await fetch('assets/data/index.json', {cache: 'no-cache'}).then(r => r.json());

// 2. Charger le mois sélectionné
const month = index.months[0]; // ex. "2025-04"
const cves  = await fetch(`assets/data/cve-${month}.json`, {cache: 'no-cache'}).then(r => r.json());

// 3. Afficher
cves.forEach(item => {
    const score    = item.cve.metrics?.cvssMetricV31?.[0]?.cvssData?.baseScore;
    const severity = item.cve.metrics?.cvssMetricV31?.[0]?.cvssData?.baseSeverity;
    // ... construire la carte HTML
});
```

**`cache: 'no-cache'`** : envoie `If-Modified-Since` au serveur. Si le fichier n'a pas changé → réponse 304 (pas de re-download). Si le cron a régénéré → nouvelles données reçues.

---

## Étape 8 — Cron automatique

```cron
# /etc/cron.d/cve-fetch
0  6 * * * root /opt/cve-tracker/cron-cve-fetch.sh >> /var/log/cve-fetch.log 2>&1
0 13 * * * root /opt/cve-tracker/cron-cve-fetch.sh >> /var/log/cve-fetch.log 2>&1
0 21 * * * root /opt/cve-tracker/cron-cve-fetch.sh >> /var/log/cve-fetch.log 2>&1
```

3 passages/jour couvrent les publications NVD (qui publie en continu).

---

## Résumé des décisions d'architecture

| Problème | Solution retenue | Pourquoi |
|----------|-----------------|----------|
| Exposer la clé API | Proxy nginx + fichier hors dépôt | Sécurité maximale |
| Lenteur API pour l'utilisateur | Fichiers JSON statiques | Chargement <100ms |
| Risque de quota NVD | Cron 3×/jour côté serveur | 3 req/jour ≪ 50 req/30s |
| Fichier corrompu si cron interrompu | Écriture atomique (tmp + mv) | Intégrité des données |
| Baisse NVD temporaire | Validation anti-régression 80% | Conservation de l'existant |
| Pagination NVD (2000/page) | Boucle startIndex | Mois complets garantis |
