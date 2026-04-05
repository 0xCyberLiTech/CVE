# Changelog — CVE Tracker

Toutes les modifications notables sont documentées ici.

---

## [1.5.0] — 2026-03-16

### Ajouté
- Mode "Mises à jour récentes" : charge `cve-recent.json` (CVE modifiées sur 7j glissants)
- `cron-cve-fetch.sh` : 3 passages/jour (06h, 13h, 21h)
- Fenêtre glissante `lastModStartDate` → `cve-recent.json` trié par `lastModified` décroissant

## [1.4.0] — 2026-03-08

### Amélioré
- `cron-cve-fetch.sh` : validation anti-régression (80% seuil minimum)
- Double passage cron : 06h00 + 21h00

## [1.3.0] — 2026-03-03

### Ajouté
- Hero stats : ajout Moyennes + Faibles avec couleurs par sévérité
- Indice de risque composite

## [1.2.0] — 2026-02-27

### Modifié
- Architecture : abandon des appels API NVD directs depuis le navigateur
- Migration vers fichiers JSON statiques générés par cron côté serveur
- Proxy nginx pour injection de la clé API (pattern sécurisé)
- Écriture atomique : `.tmp` + `mv` (supprime les fichiers corrompus)
- `If-Modified-Since` côté navigateur (cache conditionnel)

## [1.1.0] — 2026-02-22

### Ajouté
- Section pédagogique "Comprendre les CVE" + lien explainer
- Export CSV des CVE filtrées
- Métriques analytiques : CVSS moyen, exploit refs, CISA KEV, CWE dominant
- Graphique d'évolution temporelle (publications quotidiennes)

## [1.0.0] — 2026-02-16

### Initial
- Dashboard CVE basique avec filtres sévérité
- Tri par date, CVSS, ID
- Recherche plein texte
- Sélecteur de période (mois/année)
