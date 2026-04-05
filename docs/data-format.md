# Format des fichiers JSON — CVE Tracker

## Fichiers générés

| Fichier | Contenu | Fréquence |
|---------|---------|-----------|
| `cve-YYYY-MM.json` | Toutes les CVE publiées dans le mois | 3×/jour |
| `cve-recent.json` | CVE modifiées sur 7 jours glissants | 3×/jour |
| `index.json` | Liste des mois disponibles | À chaque cron |

## Structure `index.json`

```json
{
  "generated": "2025-04-05T06:00:00Z",
  "months": ["2025-04", "2025-03", "2025-02", "2025-01"]
}
```

## Structure `cve-YYYY-MM.json`

Tableau d'objets CVE au format NVD API 2.0.

```json
[
  {
    "cve": {
      "id": "CVE-2025-XXXXX",
      "sourceIdentifier": "security@vendor.com",
      "published": "2025-01-15T10:00:00.000",
      "lastModified": "2025-01-16T08:00:00.000",
      "vulnStatus": "Analyzed",
      "descriptions": [
        { "lang": "en", "value": "A vulnerability in..." },
        { "lang": "es", "value": "Una vulnerabilidad en..." }
      ],
      "metrics": {
        "cvssMetricV31": [
          {
            "source": "nvd@nist.gov",
            "type": "Primary",
            "cvssData": {
              "version": "3.1",
              "vectorString": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H",
              "baseScore": 9.8,
              "baseSeverity": "CRITICAL"
            },
            "exploitabilityScore": 3.9,
            "impactScore": 5.9
          }
        ]
      },
      "weaknesses": [
        {
          "source": "nvd@nist.gov",
          "type": "Primary",
          "description": [
            { "lang": "en", "value": "CWE-89" }
          ]
        }
      ],
      "configurations": [...],
      "references": [
        {
          "url": "https://github.com/vendor/repo/security/advisories/...",
          "source": "security@vendor.com",
          "tags": ["Exploit", "Third Party Advisory"]
        }
      ]
    }
  }
]
```

## Champs clés exploités par le dashboard

| Champ | Usage |
|-------|-------|
| `cve.id` | Identifiant CVE |
| `cve.published` | Date de publication (axe graphique) |
| `cve.lastModified` | Date de modification (mode "récents") |
| `cve.descriptions[].value` | Description affichée |
| `cvssMetricV31.cvssData.baseScore` | Score CVSS affiché |
| `cvssMetricV31.cvssData.baseSeverity` | Couleur de sévérité |
| `weaknesses.description[].value` | CWE — catégorie de faiblesse |
| `references[].tags` | Détection exploit/KEV |

## Détection des références exploit

Le dashboard considère une CVE comme ayant une référence exploit si un tag contient :

```javascript
['Exploit', 'Vendor Advisory', 'Patch', 'Third Party Advisory']
```

La détection CISA KEV repose sur la présence du tag `"US Government Resource"` ou de l'URL `cisa.gov` dans les références.
