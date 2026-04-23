# Tests (Teil F – Qualitätssicherung)

Automatisiertes Testframework für das `game-dev-orchestrator`-Skill.

## Dateien

| Datei                         | Zweck                                                   |
|-------------------------------|---------------------------------------------------------|
| `run-tests.sh`                | **Haupt-Runner.** Führt alle automatischen Tests aus.   |
| `simulate-dry-run.sh`         | Dry-Run-Simulator für einzelne Szenarien.               |
| `test-genre-detection.sh`     | Unit-Test für die Keyword-basierte Genre-Erkennung.     |
| `lib/assertions.sh`           | Helper-Funktionen (assert_*, suite, print_summary).     |
| `test-scenarios.md`           | Beschreibung der 5 offiziellen Test-Szenarien.          |
| `e2e-jumping-cube.md`         | Runbook für den echten End-to-End-Lauf (Schritt 21).    |
| `KNOWN-ISSUES.md`             | Bekannte Abweichungen vom Plan & Design-Entscheidungen. |
| `fixtures/genre-rules.json`   | Genre-Keyword-Regeln (extrahiert aus planning-phase.md).|
| `fixtures/genre-detection-cases.json` | Ground-Truth für Genre-Tests.                   |
| `fixtures/unity-status.schema.json`   | JSON-Schema-Contract für Unity-Status-Datei.    |

## Schnellstart

```bash
# Alle automatischen Tests (offline)
bash tests/run-tests.sh

# Inklusive Online-Checks (Ollama-Cloud-Ping)
bash tests/run-tests.sh --online

# Einzelne Szenarien
bash tests/simulate-dry-run.sh happy_path       /tmp/dr
bash tests/simulate-dry-run.sh single_error     /tmp/dr
bash tests/simulate-dry-run.sh multiple_errors  /tmp/dr
bash tests/simulate-dry-run.sh max_retries      /tmp/dr

# 10-Phasen-Mock-Plan (Skalierungstest)
MOCK_PLAN=$(pwd)/test-data/mock-master-plan-10phases.json \
  bash tests/simulate-dry-run.sh happy_path /tmp/dr10

# Genre-Erkennung allein
bash tests/test-genre-detection.sh
```

Exit-Codes des Runners:
- `0` – alle Tests bestanden (Skipped zählen nicht als Fehler)
- `1` – mindestens ein Test fehlgeschlagen

## Testumfang (28 Suiten, 200+ Assertions)

1. Skill-Grundstruktur
2. Pipeline-Dokumente (Teil D)
3. Prompts & Genre-Kontexte
4. Templates (Teil E)
5. JSON-Validität (alle JSONs im Skill-Tree)
6. `gamedev-config.json`-Schema
7. Mock-Master-Plan-Konsistenz
8. Unity-Status-Sequenzen
9. Günther-Mock-Antworten (JSON-in-JSON)
10.–13. Dry-Run-Szenarien (Happy/Single/Multi/MaxRetries)
14. Bash-Syntax aller Shell-Scripts
15. Workspace-Integration (Teil B, Schritt 2)
16.–17. Teil C (Prompts + Referenzen)
18.–20. Teil E (Templates + Editor-Scripts + Build-Pipeline)
21. 10-Phasen-Mock-Plan (Skalierungs-Test)
22. Unity-Status-Schema-Contract + Atomic-Write-Check
23. Template-Content-Smoke-Tests
24. Deprecated-Kennzeichnung (`InventorySystem.cs.txt`)
25. dryRun-Sanity-Check
26. VS-Code-/Copilot-Umgebung (nicht-blockierend)
27. Genre-Detection (Unit-Test-Wrapper)
28. **[--online]** Ollama-Cloud-Erreichbarkeit

## Voraussetzungen

- `bash` ≥ 5
- `jq` ≥ 1.6
- `curl` (nur für `--online`)
- kein echtes Unity / Ollama nötig für die automatischen Tests.
