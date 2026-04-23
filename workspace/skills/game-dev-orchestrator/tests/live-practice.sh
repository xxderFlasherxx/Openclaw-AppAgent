#!/bin/bash
# ==============================================================================
# LIVE PRACTICE: Full-Pipeline Simulation inkl. Teil G
# ------------------------------------------------------------------------------
# Simuliert einen kompletten Projekt-Lauf von User-Wunsch bis DONE,
# mit allen drei Teil-G-Komponenten aktiv:
#   - Modell-Routing pro Phase (mit Kosten-Tracking)
#   - Pattern-Detection während der Ausführung
#   - Memory-Archivierung nach Build
#   - User-Feedback (simuliert: Rating=4, Kategorie "code")
# ==============================================================================
set -eu

SKILL=/home/vboxuser/.openclaw/workspace/skills/game-dev-orchestrator
WS=/home/vboxuser/.openclaw/workspace
CFG="$SKILL/gamedev-config.json"

# Temporary sandbox project + memory copies
TMPDIR=$(mktemp -d -t live-practice-XXXXXX)
PROJ="$TMPDIR/JumpingCubeLive"
MEM="$TMPDIR/memory"
mkdir -p "$PROJ/.plan" "$MEM"

cp "$SKILL/templates/gamedev-projects.json"  "$MEM/gamedev-projects.json"
cp "$SKILL/templates/gamedev-patterns.json"  "$MEM/gamedev-patterns.json"
cp "$SKILL/templates/model-usage.json"       "$PROJ/.plan/model-usage.json"
cp "$SKILL/templates/used-patterns.json"     "$PROJ/.plan/used-patterns.json"

echo "════════════════════════════════════════════════════"
echo " LIVE-PRACTICE: 10-Phasen-Projekt End-to-End"
echo "════════════════════════════════════════════════════"
echo "Sandbox:    $TMPDIR"
echo "Projekt:    $PROJ"
echo "Memory:     $MEM"
echo ""

# ── Routing-Funktion inline (entspricht test-model-routing.sh) ────────────────
select_model() {
  local phase_id="$1" category="$2" name="$3" prompt="$4" retry="$5"
  local override
  override=$(jq -r --arg k "$phase_id" '.modelRouting.overrides[$k] // empty' "$CFG")
  if [ -n "$override" ]; then echo "$override"; return; fi
  local esc
  esc=$(jq -r '.modelRouting.escalateAtRetry' "$CFG")
  [ "$retry" -ge "$esc" ] && { echo "opus"; return; }
  if [ -n "$category" ] && [ "$category" != "null" ]; then
    local m
    m=$(jq -r --arg c "$category" '.modelRouting.categoryMap[$c] // empty' "$CFG")
    [ -n "$m" ] && { echo "$m"; return; }
  fi
  local text_lc; text_lc=$(echo "$name $prompt" | tr '[:upper:]' '[:lower:]')
  local sh=0 ss=0 so=0 kw
  while read -r kw; do [[ -z "$kw" ]] && continue; [[ "$text_lc" == *"$kw"* ]] && sh=$((sh+1)); done < <(jq -r '.modelRouting.keywords.haiku[]' "$CFG")
  while read -r kw; do [[ -z "$kw" ]] && continue; [[ "$text_lc" == *"$kw"* ]] && ss=$((ss+1)); done < <(jq -r '.modelRouting.keywords.sonnet[]' "$CFG")
  while read -r kw; do [[ -z "$kw" ]] && continue; [[ "$text_lc" == *"$kw"* ]] && so=$((so+2)); done < <(jq -r '.modelRouting.keywords.opus[]' "$CFG")
  [ "$so" -ge 2 ] && { echo "opus"; return; }
  [ "$sh" -gt "$ss" ] && [ "$so" -eq 0 ] && { echo "haiku"; return; }
  jq -r '.modelRouting.defaultModel' "$CFG"
}

calc_cost() {
  local model="$1" in_tok="$2" out_tok="$3"
  local ip op
  ip=$(jq -r --arg m "$model" '.modelRouting.pricing[$m].inputPer1K'  "$CFG")
  op=$(jq -r --arg m "$model" '.modelRouting.pricing[$m].outputPer1K' "$CFG")
  awk "BEGIN{printf \"%.6f\", ($in_tok/1000)*$ip + ($out_tok/1000)*$op}"
}

# ── Master-Plan (10 Phasen mit Kategorien für Routing) ────────────────────────
cat > "$PROJ/.plan/master-plan.json" << 'JSON'
{
  "gameName": "JumpingCubeLive",
  "gameDescription": "Einfacher 3D-Platformer mit springendem Würfel",
  "totalPhases": 10,
  "genre": "platformer",
  "phases": [
    {"id":1, "name":"Projektstruktur",        "category":"structure",    "copilotPrompt":"Lege Ordnerstruktur Assets/Scripts/{Core,Player,UI}, .gitignore, editorconfig an.", "expectedFiles":["Assets/Scripts/Core/GameManager.cs"]},
    {"id":2, "name":"GameManager Singleton",  "category":"gamelogic",    "copilotPrompt":"Erstelle GameManager als Singleton mit Score-Property und UnityEvent OnScoreChanged.", "expectedFiles":["Assets/Scripts/Core/GameManager.cs"]},
    {"id":3, "name":"PlayerController",       "category":"gamelogic",    "copilotPrompt":"Schreibe PlayerController mit WASD-Movement und Space=Jump. Input via InputManager.", "expectedFiles":["Assets/Scripts/Player/PlayerController.cs"]},
    {"id":4, "name":"Physik & Collider",      "category":"physics",      "copilotPrompt":"Setze Rigidbody + BoxCollider auf Player. Nutze Physics.Raycast fuer Ground-Check.", "expectedFiles":["Assets/Scripts/Player/GroundCheck.cs"]},
    {"id":5, "name":"Kamera-Follow",          "category":"gamelogic",    "copilotPrompt":"Cinemachine Virtual Camera mit Follow-Target, DeadZone 0.1, Damping 1.5.", "expectedFiles":["Assets/Scripts/Camera/CameraFollow.cs"]},
    {"id":6, "name":"Prozedurale Platforms",  "category":"procedural",   "copilotPrompt":"Generiere Platformen prozedural mit Perlin Noise. Endless-Terrain-Pattern.", "expectedFiles":["Assets/Scripts/World/PlatformGenerator.cs"]},
    {"id":7, "name":"HUD & Menu",             "category":"ui",           "copilotPrompt":"HUD mit TextMeshPro Score-Anzeige, Pause-Menu, Settings-Options.", "expectedFiles":["Assets/Scripts/UI/HUDController.cs"]},
    {"id":8, "name":"Audio Manager",          "category":"gamelogic",    "copilotPrompt":"AudioManager mit PlaySFX und PlayMusic. Volumes Persistenz via PlayerPrefs.", "expectedFiles":["Assets/Scripts/Audio/AudioManager.cs"]},
    {"id":9, "name":"Enemy AI",               "category":"ai",           "copilotPrompt":"Enemy-Behavior-Tree mit Pathfinding via NavMeshAgent und Patrol/Chase-States.", "expectedFiles":["Assets/Scripts/Enemy/EnemyAI.cs"]},
    {"id":10,"name":"Final Build",            "category":"build",        "copilotPrompt":"Baue StandaloneLinux64 Build via AutoBuilder.Build(). Scene JumpingCubeLive.", "expectedFiles":["Builds/Linux/JumpingCubeLive.x86_64"]}
  ]
}
JSON

echo "▶ Phase 0: Genre erkannt = platformer (aus User-Prompt 'springender Wuerfel')"
echo ""

# ── Pattern-Detection Funktion ────────────────────────────────────────────────
# Nutzt `keywords[]` aus der Pattern-Library. Ein Pattern gilt als verwendet,
# wenn mindestens 1 Keyword als Substring im Prompt vorkommt (keywords sind
# kurze, hochspezifische Begriffe wie "cinemachine" oder "wheelcollider").
detect_patterns() {
  local prompt_lc; prompt_lc=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  local used=()
  while IFS=$'\t' read -r key keywords_csv; do
    local kw
    IFS=',' read -ra KWS <<< "$keywords_csv"
    for kw in "${KWS[@]}"; do
      [ -z "$kw" ] && continue
      if [[ "$prompt_lc" == *"$kw"* ]]; then
        used+=("$key"); break
      fi
    done
  done < <(jq -r '.patterns | to_entries[]
                 | select(.value.deprecated != true)
                 | "\(.key)\t\((.value.keywords // []) | map(ascii_downcase) | join(","))"' "$MEM/gamedev-patterns.json")
  printf '%s\n' "${used[@]}"
}

# ── Phasen-Schleife ───────────────────────────────────────────────────────────
TOTAL_COST=0
START_TS=$(date -u +%s)

for i in $(seq 0 9); do
  phase=$(jq ".phases[$i]" "$PROJ/.plan/master-plan.json")
  pid=$(echo "$phase" | jq -r '.id')
  pname=$(echo "$phase" | jq -r '.name')
  pcat=$(echo "$phase" | jq -r '.category')
  pprompt=$(echo "$phase" | jq -r '.copilotPrompt')

  # Retry-Simulation: Phase 4 (Physik) brauche 1 Retry, Phase 9 (AI) brauche 3 Retries (→ Opus-Eskalation)
  case "$pid" in
    4) retries=1 ;;
    9) retries=3 ;;
    *) retries=0 ;;
  esac

  model=$(select_model "$pid" "$pcat" "$pname" "$pprompt" "$retries")

  # Mock-Tokens (realistische Werte)
  in_tok=1200
  out_tok=800
  cost=$(calc_cost "$model" "$in_tok" "$out_tok")
  TOTAL_COST=$(awk "BEGIN{printf \"%.6f\", $TOTAL_COST + $cost}")

  # Pattern-Detection
  mapfile -t patterns < <(detect_patterns "$pprompt")

  # Log ins model-usage.json
  jq --arg m "$model" --argjson it "$in_tok" --argjson ot "$out_tok" --argjson c "$cost" \
     --arg pid "$pid" --arg reason "live-practice" \
     '.models[$m].calls += 1
      | .models[$m].promptTokens += $it
      | .models[$m].completionTokens += $ot
      | .models[$m].costUsd += $c
      | .totalCalls += 1
      | .totalTokens += ($it + $ot)
      | .totalCostUsd += $c
      | .decisions += [{phaseId:($pid|tonumber), model:$m, reason:$reason, timestamp:now|todate}]' \
     "$PROJ/.plan/model-usage.json" > "$PROJ/.plan/model-usage.new.json"
  mv "$PROJ/.plan/model-usage.new.json" "$PROJ/.plan/model-usage.json"

  # Log used-patterns
  if [ "${#patterns[@]}" -gt 0 ]; then
    patterns_json=$(printf '%s\n' "${patterns[@]}" | jq -R . | jq -s .)
    jq --arg pid "$pid" --argjson pats "$patterns_json" \
       '.phases[$pid] = $pats | .aggregate = (([.phases[]] | add) // [] | unique)' \
       "$PROJ/.plan/used-patterns.json" > "$PROJ/.plan/used-patterns.new.json"
    mv "$PROJ/.plan/used-patterns.new.json" "$PROJ/.plan/used-patterns.json"
  fi

  printf "  Phase %2d/10 %-28s | cat=%-10s | retry=%d → model=%-6s | \$%s | patterns=%s\n" \
    "$pid" "$pname" "$pcat" "$retries" "$model" "$cost" "$(IFS=,; echo "${patterns[*]:-—}")"
done

END_TS=$(date -u +%s)
DURATION=$((END_TS - START_TS))

echo ""
echo "▶ Alle 10 Phasen abgeschlossen in ${DURATION}s (simuliert)"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "▶ STATE: COMPLETE → ARCHIVING (Teil G, Schritt 23)"
echo "═══════════════════════════════════════════════════════"

# ── Projekt archivieren ──────────────────────────────────────────────────────
MODEL_USAGE=$(jq '.models' "$PROJ/.plan/model-usage.json")
USED_PATS=$(jq '.aggregate' "$PROJ/.plan/used-patterns.json")

ENTRY=$(jq -n \
  --arg name "JumpingCubeLive" \
  --arg path "$PROJ" \
  --arg genre "platformer" \
  --arg start "$(date -u -d @$START_TS +%Y-%m-%dT%H:%M:%SZ)" \
  --arg end   "$(date -u -d @$END_TS   +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson dur "$DURATION" \
  --argjson mu "$MODEL_USAGE" \
  --argjson cost "$TOTAL_COST" \
  --argjson patterns "$USED_PATS" \
  '{
    name:$name, projectPath:$path, genre:$genre,
    startDate:$start, endDate:$end, durationSeconds:$dur,
    phases:10, phasesCompleted:10, phasesEscalated:0,
    totalErrors:4, totalRetries:4,
    modelUsage:$mu, totalCostUsd:$cost,
    usedPatterns:$patterns,
    learnings:["Cinemachine fuer Kamera","Perlin Noise fuer Platforms","TMPro statt Legacy Text"],
    qualityRating:null, feedback:null,
    finalBuildPath:"\($path)/Builds/Linux",
    success:true
  }')

jq --argjson e "$ENTRY" \
   '.projects += [$e]
    | .aggregate.totalProjects = (.projects | length)
    | .aggregate.successfulProjects = ([.projects[] | select(.success==true)] | length)
    | .aggregate.totalCostUsd = ([.projects[].totalCostUsd] | add)
    | .aggregate.avgDurationSeconds = (([.projects[].durationSeconds] | add) / (.projects | length))
    | .lastUpdate = (now|todate)' \
   "$MEM/gamedev-projects.json" > "$MEM/gamedev-projects.new.json"
mv "$MEM/gamedev-projects.new.json" "$MEM/gamedev-projects.json"

# Pattern-Library updaten (success)
while read -r key; do
  [ -z "$key" ] && continue
  jq --arg k "$key" \
     '.patterns[$k].timesUsed += 1
      | .patterns[$k].successRate = ((.patterns[$k].successRate * (.patterns[$k].timesUsed - 1) + 1) / .patterns[$k].timesUsed)
      | .patterns[$k].lastUsed = (now|todate)
      | .lastUpdate = (now|todate)' \
     "$MEM/gamedev-patterns.json" > "$MEM/gamedev-patterns.new.json"
  mv "$MEM/gamedev-patterns.new.json" "$MEM/gamedev-patterns.json"
done < <(echo "$USED_PATS" | jq -r '.[]?')

echo "✔ Projekt archiviert (gamedev-projects.json)"
echo "✔ Pattern-Library aktualisiert für: $(echo "$USED_PATS" | jq -c .)"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "▶ STATE: ARCHIVING → AWAITING_FEEDBACK (Schritt 24)"
echo "═══════════════════════════════════════════════════════"

# Feedback simulieren: User antwortet "4" und "code"
RATING=4
CATS='["code"]'
FREETEXT="Guter Code, Kamera hervorragend. Enemy-AI könnte smarter sein."

jq --argjson r "$RATING" --argjson c "$CATS" --arg ft "$FREETEXT" \
   '.projects[-1].qualityRating = $r
    | .projects[-1].feedback = {
        rating: $r,
        categories: $c,
        freeText: $ft,
        submittedAt: (now|todate)
      }
    | .aggregate.ratedProjects = ([.projects[] | select(.qualityRating != null)] | length)
    | .aggregate.avgQualityRating = (([.projects[].qualityRating // empty] | add) / (.aggregate.ratedProjects))' \
   "$MEM/gamedev-projects.json" > "$MEM/gamedev-projects.fb.json"
mv "$MEM/gamedev-projects.fb.json" "$MEM/gamedev-projects.json"

echo "✔ User-Feedback gespeichert: Rating=$RATING, Kategorien=$CATS"
echo ""

echo "═══════════════════════════════════════════════════════"
echo "▶ STATE: AWAITING_FEEDBACK → DONE"
echo "═══════════════════════════════════════════════════════"
echo ""

# ── Finale Reports ────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " REPORT: Modell-Nutzung (routing-table)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
jq '.models | to_entries[] | "\(.key | ascii_upcase): \(.value.calls) calls | \(.value.promptTokens + .value.completionTokens) tokens | $\(.value.costUsd|tostring)"' \
   -r "$PROJ/.plan/model-usage.json"
echo "Gesamtkosten: \$$(jq -r '.totalCostUsd' "$PROJ/.plan/model-usage.json")"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " REPORT: Routing-Decisions"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
jq -r '.decisions | group_by(.model) | map({model: .[0].model, count: length, phases: [.[].phaseId]}) | .[] | "  \(.model): \(.count) phasen (IDs: \(.phases|join(", ")))"' \
   "$PROJ/.plan/model-usage.json"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " REPORT: Memory (Cross-Project)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
jq '.aggregate' "$MEM/gamedev-projects.json"
echo ""
echo " Pattern-Library (nach Update):"
jq '.patterns | to_entries | map({key, timesUsed:.value.timesUsed, successRate:.value.successRate})' \
   "$MEM/gamedev-patterns.json"
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " REPORT: User-Feedback"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
jq '.projects[-1] | {name, qualityRating, feedback}' "$MEM/gamedev-projects.json"
echo ""

# ── Validierungen ─────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " VALIDIERUNG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RC=0
check() {
  if eval "$1"; then
    echo "  ✔ $2"
  else
    echo "  ✘ $2"
    RC=1
  fi
}

# 1) Phase 1 & 10 (haiku via override), Phase 4 physics→opus, Phase 6 procedural→opus,
#    Phase 9 ai→opus (auch retry hätte eskaliert), Phase 7 ui→sonnet
HAIKU_PHASES=$(jq -r '[.decisions[] | select(.model=="haiku") | .phaseId] | sort | @csv' "$PROJ/.plan/model-usage.json")
OPUS_PHASES=$(jq -r '[.decisions[] | select(.model=="opus") | .phaseId] | sort | @csv' "$PROJ/.plan/model-usage.json")
SONNET_PHASES=$(jq -r '[.decisions[] | select(.model=="sonnet") | .phaseId] | sort | @csv' "$PROJ/.plan/model-usage.json")

check "[[ '$HAIKU_PHASES' == '1,10' ]]"                    "Haiku für Phase 1 + 10 (Override)"
check "[[ '$OPUS_PHASES' == *'4'* && '$OPUS_PHASES' == *'6'* && '$OPUS_PHASES' == *'9'* ]]" \
      "Opus für Phasen 4 (physics), 6 (procedural), 9 (ai)"
check "[[ '$SONNET_PHASES' == *'2'* && '$SONNET_PHASES' == *'7'* ]]" \
      "Sonnet für Phasen 2 + 7 (gamelogic/ui)"

check "[ \$(jq -r '.aggregate.totalProjects' '$MEM/gamedev-projects.json') = '1' ]" \
      "Memory: totalProjects=1"
check "[ \$(jq -r '.projects[-1].qualityRating' '$MEM/gamedev-projects.json') = '4' ]" \
      "Memory: Rating=4 gespeichert"
check "[ \$(jq -r '.projects[-1].success' '$MEM/gamedev-projects.json') = 'true' ]" \
      "Memory: success=true"
# Pattern-Library: camera-follow-cinemachine wurde verwendet (Phase 5 nennt Cinemachine)
check "[ \$(jq -r '.patterns[\"camera-follow-cinemachine\"].timesUsed' '$MEM/gamedev-patterns.json') -ge 1 ]" \
      "Pattern camera-follow-cinemachine.timesUsed >= 1"
# TMPro-Pattern via Phase 7
check "[ \$(jq -r '.patterns[\"text-mesh-pro-over-legacy\"].timesUsed' '$MEM/gamedev-patterns.json') -ge 1 ]" \
      "Pattern text-mesh-pro-over-legacy.timesUsed >= 1"

# Kosten plausibel (>0, <5)
TC=$(jq -r '.totalCostUsd' "$PROJ/.plan/model-usage.json")
check "awk 'BEGIN{exit !($TC > 0 && $TC < 5)}'" "Gesamtkosten plausibel (0 < \$$TC < \$5)"

# JSON-Integrität aller Output-Dateien
for f in "$PROJ/.plan/model-usage.json" "$PROJ/.plan/used-patterns.json" \
         "$MEM/gamedev-projects.json" "$MEM/gamedev-patterns.json"; do
  check "jq empty '$f' 2>/dev/null" "JSON valide: $(basename $f)"
done

echo ""
if [ "$RC" -eq 0 ]; then
  echo "═══════════════════════════════════════════════════════"
  echo "  ✔ LIVE-PRACTICE ERFOLGREICH"
  echo "═══════════════════════════════════════════════════════"
else
  echo "═══════════════════════════════════════════════════════"
  echo "  ✘ LIVE-PRACTICE: FEHLER"
  echo "═══════════════════════════════════════════════════════"
fi

# Aufräumen (aber erst nach Reports, damit Pfade klar sind)
rm -rf "$TMPDIR"
exit $RC
