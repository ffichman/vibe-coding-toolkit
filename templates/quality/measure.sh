#!/usr/bin/env bash
set -u

QDIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$QDIR")"
REPORT_DIR=""
MAX_LINES="${MAX_LINES:-350}"

while test $# -gt 0; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    *) echo "measure.sh: argumento desconhecido: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
if test -z "$REPORT_DIR"; then
  REPORT_DIR="$QDIR/reports"
fi
mkdir -p "$REPORT_DIR"

echo "== Medição de qualidade (só leitura, nunca corrige) =="
echo "repo:      $ROOT"
echo "relatório: $REPORT_DIR"
echo "MAX_LINES: $MAX_LINES"

line_count_report() {
  local label="$1"
  shift
  local out="$REPORT_DIR/lines-$label.txt"
  find "$ROOT" \( -name node_modules -o -name .git -o -name dist -o -name build -o -name out -o -name .next -o -name coverage -o -name vendor -o -name Pods -o -name Carthage -o -name .build -o -name DerivedData -o -name .quality \) -prune -o -type f \( "$@" \) -exec wc -l {} + 2>/dev/null \
    | awk -v max="$MAX_LINES" -v root="$ROOT/" '{ n=$1; sub(/^ *[0-9]+ /, ""); if ($0 != "total" && n > max) { f=$0; if (index(f, root) == 1) f = substr(f, length(root) + 1); printf "%6d  %s\n", n, f } }' \
    | sort -rn > "$out"
  local total
  total="$(wc -l < "$out" | tr -d ' ')"
  echo "  arquivos $label acima de $MAX_LINES linhas: $total"
  head -n 10 "$out" | sed 's/^/    /'
}

if test -f "$QDIR/eslint.measure.config.mjs"; then
  echo
  echo "-- JS/TS --"
  ESLINT_BIN="$ROOT/node_modules/.bin/eslint"
  if test -x "$ESLINT_BIN"; then
    (cd "$ROOT" && "$ESLINT_BIN" -c "$QDIR/eslint.measure.config.mjs" --no-warn-ignored -f json . > "$REPORT_DIR/eslint.json" 2> "$REPORT_DIR/eslint.stderr")
    if command -v node > /dev/null 2>&1 && test -s "$REPORT_DIR/eslint.json"; then
      node -e '
        const r = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
        const byRule = {};
        let files = 0;
        for (const f of r) { if (f.messages.length) files++; for (const m of f.messages) { const k = m.ruleId || "parse-error"; byRule[k] = (byRule[k] || 0) + 1; } }
        console.log("  arquivos analisados: " + r.length + " | com avisos: " + files);
        for (const [k, v] of Object.entries(byRule).sort((a, b) => b[1] - a[1])) console.log("    " + String(v).padStart(5) + "  " + k);
      ' "$REPORT_DIR/eslint.json"
    else
      echo "  ESLint não gerou relatório; veja $REPORT_DIR/eslint.stderr"
    fi
  else
    echo "  ESLint local não encontrado em node_modules; usando contagem de linhas."
    echo "  Para medição completa com ESLint: instale eslint como devDependency (apply-repo.sh --install-deps em repos não excluídos)."
  fi
  line_count_report js -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.ts' -o -name '*.tsx' -o -name '*.mts' -o -name '*.cts'
fi

if test -f "$QDIR/swiftlint.measure.yml"; then
  echo
  echo "-- Swift --"
  if command -v swiftlint > /dev/null 2>&1; then
    GEN_CFG="$REPORT_DIR/swiftlint.generated.yml"
    awk -v root="$ROOT" -v max="$MAX_LINES" '
      /^excluded:/ { inexc=1; print; next }
      /^[a-z_]+:/ { inexc=0 }
      inexc && /^  - / { sub(/^  - /, ""); print "  - " root "/" $0; next }
      /^  warning: / { print "  warning: " max; next }
      { print }
    ' "$QDIR/swiftlint.measure.yml" > "$GEN_CFG"
    (cd "$ROOT" && swiftlint lint --config "$GEN_CFG" --quiet --reporter json > "$REPORT_DIR/swiftlint.json" 2> "$REPORT_DIR/swiftlint.stderr")
    echo "  avisos file_length (SwiftLint): $(grep -c '"rule_id"' "$REPORT_DIR/swiftlint.json" 2>/dev/null || echo 0)"
  else
    echo "  SwiftLint não instalado; usando contagem de linhas. Para instalar: brew install swiftlint"
  fi
  line_count_report swift -name '*.swift'
fi

echo
echo "Medição concluída. Nada foi alterado no código."
exit 0
