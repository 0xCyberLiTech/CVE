#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# backfill-cve.sh — Récupération initiale des CVE historiques NVD
#
# À lancer UNE SEULE FOIS pour peupler les mois manquants.
# Les mois déjà présents sont ignorés (sauf FORCE=1).
#
# Lancement :
#   chmod +x backfill-cve.sh
#   ./backfill-cve.sh
#   ./backfill-cve.sh >> /var/log/cve-backfill.log 2>&1
#   FORCE=1 ./backfill-cve.sh               # réécrire les fichiers existants
#   SLEEP_BETWEEN_MONTHS=60 ./backfill-cve.sh   # extra prudent (rate-limit NVD)
#
# Consommation API NVD (avec clé) :
#   - ~1 à 2 requêtes par mois (2 000 CVE/page)
#   - 18 mois → ~20 à 36 requêtes
#   - Quota NVD avec clé : 50 req/30s — aucun risque de dépassement
#
# Durée estimée avec les délais par défaut :
#   ~35-45 min pour 18 mois (18 × 30s pause + ~10s/page × ~20 pages)
#
# Architecture clé API :
#   Stockée dans nginx (/etc/nginx/api-keys.conf), injectée côté serveur.
#   Ce script interroge uniquement le proxy local nginx. Aucune clé ici.
#
# Dépendances : curl, jq  (apt-get install curl jq)
#
# Author  : 0xCyberLiTech
# Version : 1.1.0 (genericisé)
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Configuration — à adapter ─────────────────────────────────────────────────
readonly DATA_DIR=/var/www/html/assets/data
readonly NVD_PROXY='http://127.0.0.1/api/nvd/'
readonly RESULTS_PER_PAGE=2000
readonly RATE_LIMIT_SLEEP=8        # Secondes entre pages du même mois

# Pause entre chaque mois (augmenter si erreurs 403/429 NVD)
SLEEP_BETWEEN_MONTHS=${SLEEP_BETWEEN_MONTHS:-30}

# Mois de départ du backfill
readonly START_YEAR=2024
readonly START_MONTH=1             # Janvier 2024

# 0 = sauter si le fichier existe ; 1 = réécrire
FORCE=${FORCE:-0}

# ── Helpers ────────────────────────────────────────────────────────────────────
log() { printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*"; }

# ── Prérequis ─────────────────────────────────────────────────────────────────
for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || {
        log "ERREUR: '$cmd' introuvable — apt-get install $cmd"
        exit 1
    }
done

mkdir -p "$DATA_DIR"

last_day_of_month() {
    date -u -d "$(printf '%04d-%02d-01' "$1" "$2") +1 month -1 day" +%d
}

# ── Récupérer un mois complet avec pagination ──────────────────────────────────
fetch_month() {
    local year=$1 month=$2
    local month_pad
    month_pad=$(printf '%02d' "$month")
    local outfile="${DATA_DIR}/cve-${year}-${month_pad}.json"
    local tmpfile="${outfile}.tmp"
    local ndjson="${outfile}.ndjson"

    if [ -f "$outfile" ] && [ "$FORCE" != "1" ]; then
        log "SKIP ${year}-${month_pad} (existe déjà — FORCE=1 pour réécrire)"
        return 0
    fi

    local last_day
    last_day=$(last_day_of_month "$year" "$month")
    local start_date="${year}-${month_pad}-01T00:00:00"
    local end_date="${year}-${month_pad}-${last_day}T23:59:59"

    log ">>> ${year}-${month_pad} : ${start_date} → ${end_date}"
    > "$ndjson"

    local start_index=0
    local total_results=1
    local page_num=0

    while [ "$start_index" -lt "$total_results" ]; do
        local page=$(( start_index / RESULTS_PER_PAGE + 1 ))
        local url="${NVD_PROXY}?pubStartDate=${start_date}&pubEndDate=${end_date}&resultsPerPage=${RESULTS_PER_PAGE}&startIndex=${start_index}"

        log "  Page ${page} — requête #$(( ++page_num ))..."

        local response
        if ! response=$(curl -sf --max-time 90 \
                             --retry 3 --retry-delay 5 \
                             -H 'User-Agent: CVE-Tracker-Backfill/1.0' \
                             "$url"); then
            log "  ERREUR curl page ${page} — abandon ${year}-${month_pad}"
            rm -f "$tmpfile" "$ndjson"
            return 1
        fi

        total_results=$(printf '%s' "$response" | jq -r '.totalResults // 0')
        local page_count
        page_count=$(printf '%s' "$response" | jq -r '.vulnerabilities | length')

        printf '%s' "$response" | jq -c '.vulnerabilities[]?' >> "$ndjson"

        local retrieved=$(( start_index + page_count ))
        log "  Récupérés : ${retrieved}/${total_results}"

        start_index=$(( start_index + RESULTS_PER_PAGE ))

        [ "$start_index" -lt "$total_results" ] && sleep "$RATE_LIMIT_SLEEP"
    done

    local saved
    saved=$(wc -l < "$ndjson")
    jq -s '.' "$ndjson" > "$tmpfile"
    rm -f "$ndjson"
    mv "$tmpfile" "$outfile"
    chown www-data:www-data "$outfile"
    chmod 644 "$outfile"
    log "  ✓ ${saved} CVE → ${outfile}"
}

# ── Boucle principale ──────────────────────────────────────────────────────────
current_year=$(date -u +%Y)
current_month=$((10#$(date -u +%m)))

total_months=$(( (current_year - START_YEAR) * 12 + current_month - START_MONTH + 1 ))

log "========================================================"
log "Backfill CVE : ${START_YEAR}-$(printf '%02d' $START_MONTH)"
log "           → ${current_year}-$(printf '%02d' $current_month)"
log "Mois à traiter : ~${total_months}"
log "Durée estimée  : ~$(( total_months * SLEEP_BETWEEN_MONTHS / 60 + 10 )) min"
[ "$FORCE" = "1" ] && log "Mode FORCE : réécriture des fichiers existants"
log "========================================================"

year=$START_YEAR
month=$START_MONTH
month_count=0

while [ "$year" -lt "$current_year" ] \
   || { [ "$year" -eq "$current_year" ] && [ "$month" -le "$current_month" ]; }; do

    fetch_month "$year" "$month" \
        || log "AVERTISSEMENT: ${year}-$(printf '%02d' $month) ignoré (erreur fetch)"

    month_count=$(( month_count + 1 ))
    month=$(( month + 1 ))
    [ "$month" -gt 12 ] && { month=1; year=$(( year + 1 )); }

    # Pause entre les mois (sauf après le dernier)
    if [ "$year" -lt "$current_year" ] \
       || { [ "$year" -eq "$current_year" ] && [ "$month" -le "$current_month" ]; }; then
        log "  Pause inter-mois ${SLEEP_BETWEEN_MONTHS}s..."
        sleep "$SLEEP_BETWEEN_MONTHS"
    fi
done

# ── Régénérer index.json ──────────────────────────────────────────────────────
log "Mise à jour index.json..."

months_json='[]'
while IFS= read -r fname; do
    [ -z "$fname" ] && continue
    key="${fname%.json}"; key="${key#cve-}"
    months_json=$(jq -n --argjson arr "$months_json" --arg k "$key" '$arr + [$k]')
done < <(
    find "${DATA_DIR}" -maxdepth 1 -name 'cve-[0-9][0-9][0-9][0-9]-[0-9][0-9].json' \
        -printf '%f\n' 2>/dev/null | sort -r
)

generated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"generated":"%s","months":%s}\n' "$generated" "$months_json" \
    | jq '.' > "${DATA_DIR}/index.json.tmp"
mv "${DATA_DIR}/index.json.tmp" "${DATA_DIR}/index.json"
chown www-data:www-data "${DATA_DIR}/index.json"
chmod 644 "${DATA_DIR}/index.json"

log "✓ Backfill terminé — ${month_count} mois traités"
log "✓ index.json mis à jour — $(echo "$months_json" | jq 'length') mois disponibles"
log "========================================================"
