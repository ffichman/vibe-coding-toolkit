#!/usr/bin/env bash
set -u

VCT_REF="baseline-revisado"
AGENT_BROWSER_VERSION="0.38.2"
CONTEXT7_URL="https://mcp.context7.com/mcp"
PLUGIN_MARKETPLACE_SRC="anthropics/claude-plugins-official"
PLUGIN_MARKETPLACE_NAME="claude-plugins-official"
PLUGIN_ID="superpowers@claude-plugins-official"

MODE="dry-run"
SKIP_BROWSER_DOWNLOAD=0
ONLY=""

usage() {
  echo "uso: install-global.sh [--dry-run | --apply] [--skip-browser-download] [--only superpowers,context7,agent-browser,hooks]"
  echo "padrão: --dry-run (nada é alterado)"
}

while test $# -gt 0; do
  case "$1" in
    --apply) MODE="apply"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --skip-browser-download) SKIP_BROWSER_DOWNLOAD=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; usage; exit 64 ;;
  esac
done

for d in "$HOME/.local/bin" "$HOME/.claude/local" "$HOME/.npm-global/bin" "$HOME/.bun/bin" "$HOME/.homebrew/bin" /usr/local/bin /opt/homebrew/bin; do
  if test -d "$d"; then
    case ":$PATH:" in
      *":$d:"*) ;;
      *) PATH="$d:$PATH" ;;
    esac
  fi
done
export PATH

if test -s "$HOME/.nvm/nvm.sh" && ! command -v node > /dev/null 2>&1; then
  . "$HOME/.nvm/nvm.sh" > /dev/null 2>&1
fi

CLAUDE_DIR="$HOME/.claude"
HOOK_DIR="$CLAUDE_DIR/hooks/vct"
SETTINGS="$CLAUDE_DIR/settings.json"
RESULTS=""
FAILS=0

say() { printf '%s\n' "$*"; }
note() { RESULTS="$RESULTS$1|$2
"; }

run() {
  if test "$MODE" = "apply"; then
    say "  + $*"
    "$@"
  else
    say "  (dry-run) $*"
    return 0
  fi
}

want() {
  if test -z "$ONLY"; then
    return 0
  fi
  case ",$ONLY," in
    *",$1,"*) return 0 ;;
    *) return 1 ;;
  esac
}

have() { command -v "$1" > /dev/null 2>&1; }

say "== vibe-coding-toolkit install-global ($VCT_REF) =="
say "host: $(hostname -s 2>/dev/null || hostname)  usuário: $(id -un)  shell de login: ${SHELL:-desconhecido}  modo: $MODE"
say "claude: $(claude --version 2>/dev/null || echo 'NÃO ENCONTRADO')"
say "node:   $(node --version 2>/dev/null || echo 'NÃO ENCONTRADO')   npm: $(npm --version 2>/dev/null || echo 'NÃO ENCONTRADO')"
say "~/.claude: $(test -d "$CLAUDE_DIR" && echo existe || echo 'não existe')"
say

if ! have claude; then
  say "ERRO: CLI claude não encontrada no PATH. Instale o Claude Code antes (instalador nativo)."
  exit 2
fi

step_superpowers() {
  say "-- [1/4] Superpowers (plugin oficial) --"
  local mk="$CLAUDE_DIR/plugins/known_marketplaces.json"
  local ip="$CLAUDE_DIR/plugins/installed_plugins.json"
  if test -f "$mk" && grep -q "\"$PLUGIN_MARKETPLACE_NAME\"" "$mk"; then
    say "  marketplace $PLUGIN_MARKETPLACE_NAME: já registrado"
  else
    run claude plugin marketplace add "$PLUGIN_MARKETPLACE_SRC" || { note superpowers FALHOU; FAILS=$((FAILS+1)); return; }
  fi
  if test -f "$ip" && grep -q "\"$PLUGIN_ID\"" "$ip"; then
    say "  $PLUGIN_ID: já instalado"
    note superpowers "já instalado"
  else
    if run claude plugin install "$PLUGIN_ID"; then
      note superpowers "$( test "$MODE" = apply && echo instalado || echo 'seria instalado' )"
    else
      note superpowers FALHOU; FAILS=$((FAILS+1))
    fi
  fi
}

step_context7() {
  say "-- [2/4] Context7 MCP (HTTP remoto, escopo user, sem npx) --"
  if claude mcp get context7 > /dev/null 2>&1; then
    say "  context7: já configurado"
    note context7 "já configurado"
    return
  fi
  local ok=0
  if test -n "${CONTEXT7_API_KEY:-}"; then
    if test "$MODE" = "apply"; then
      say "  + claude mcp add --scope user --transport http context7 $CONTEXT7_URL --header CONTEXT7_API_KEY:***"
      claude mcp add --scope user --transport http context7 "$CONTEXT7_URL" --header "CONTEXT7_API_KEY: $CONTEXT7_API_KEY" && ok=1
    else
      say "  (dry-run) claude mcp add --scope user --transport http context7 $CONTEXT7_URL --header CONTEXT7_API_KEY:***"
      ok=1
    fi
  else
    run claude mcp add --scope user --transport http context7 "$CONTEXT7_URL" && ok=1
    say "  dica: sem CONTEXT7_API_KEY o limite de requisições é menor (opcional)."
  fi
  if test "$ok" = 1; then
    note context7 "$( test "$MODE" = apply && echo configurado || echo 'seria configurado' )"
  else
    note context7 FALHOU; FAILS=$((FAILS+1))
  fi
}

step_agent_browser() {
  say "-- [3/4] agent-browser@$AGENT_BROWSER_VERSION (versão fixa) --"
  if ! have npm; then
    say "  npm não encontrado; pulando."
    note agent-browser "PULADO (sem npm)"
    return
  fi
  local cur
  cur="$(agent-browser --version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
  if test "$cur" = "$AGENT_BROWSER_VERSION"; then
    say "  agent-browser $cur: já na versão fixada"
    note agent-browser "já instalado ($cur)"
    return
  fi
  say "  versão atual: ${cur:-nenhuma}"
  local prefix
  prefix="$(npm prefix -g 2>/dev/null)"
  if test -n "$prefix" && ! test -w "$prefix/lib" && ! test -w "$prefix"; then
    say "  prefixo global do npm ($prefix) não é gravável sem sudo; não uso sudo. Ajuste o prefixo do npm e rode de novo."
    note agent-browser "PULADO (npm -g exige sudo)"
    return
  fi
  if run npm install -g "agent-browser@$AGENT_BROWSER_VERSION"; then
    if test "$SKIP_BROWSER_DOWNLOAD" = 1; then
      say "  download do Chromium pulado (--skip-browser-download)"
    else
      run agent-browser install
    fi
    note agent-browser "$( test "$MODE" = apply && echo "instalado $AGENT_BROWSER_VERSION" || echo "seria instalado $AGENT_BROWSER_VERSION" )"
  else
    note agent-browser FALHOU; FAILS=$((FAILS+1))
  fi
}

write_hook_files() {
  local target="$1"
  mkdir -p "$target"
  cat > "$target/session-context.mjs" <<'HOOK_EOF'
import { existsSync } from "node:fs";
import path from "node:path";

const root = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const lines = [];
try {
  if (existsSync(path.join(root, ".quality", "measure.sh"))) {
    lines.push(
      "vibe-coding-toolkit: este repo tem quality gates em MODO SO-MEDICAO (MAX_LINES=350).",
      "Avisos de lint/tamanho sao informativos: nao refatore, nao rode --fix e nao altere limites sem pedido explicito.",
      "Para medir: bash .quality/measure.sh"
    );
  }
  if (existsSync(path.join(root, ".claude", "memory", "MEMORY.md"))) {
    lines.push("Memoria do projeto: .claude/memory/MEMORY.md (indice, uma linha por entrada).");
  }
} catch {
  lines.length = 0;
}
if (lines.length) {
  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: lines.join("\n") },
    })
  );
}
process.exitCode = 0;
HOOK_EOF
  cat > "$target/merge-settings.mjs" <<'MERGE_EOF'
import { readFileSync, writeFileSync, existsSync } from "node:fs";

const [settingsPath, hookCmd, outPath] = process.argv.slice(2);
let current = {};
if (existsSync(settingsPath)) {
  const raw = readFileSync(settingsPath, "utf8");
  try {
    current = raw.trim() ? JSON.parse(raw) : {};
  } catch (e) {
    console.error("settings.json invalido; nao vou sobrescrever: " + e.message);
    process.exit(3);
  }
}
const next = structuredClone(current);
next.hooks = next.hooks && typeof next.hooks === "object" ? next.hooks : {};
const isOurs = (h) => typeof h?.command === "string" && h.command.includes("/hooks/vct/");
for (const ev of Object.keys(next.hooks)) {
  if (!Array.isArray(next.hooks[ev])) continue;
  next.hooks[ev] = next.hooks[ev]
    .map((g) => ({ ...g, hooks: (g.hooks || []).filter((h) => !isOurs(h)) }))
    .filter((g) => g.hooks.length > 0);
  if (next.hooks[ev].length === 0) delete next.hooks[ev];
}
next.hooks.SessionStart = next.hooks.SessionStart || [];
next.hooks.SessionStart.push({
  hooks: [{ type: "command", command: hookCmd, timeout: 5 }],
});
const before = JSON.stringify(current, null, 2);
const after = JSON.stringify(next, null, 2);
if (before === after) {
  console.log("UNCHANGED");
} else {
  writeFileSync(outPath, after + "\n");
  console.log("CHANGED");
}
MERGE_EOF
}

step_hooks() {
  say "-- [4/4] settings.json de hooks (merge, com backup) --"
  if ! have node; then
    say "  node não encontrado; pulando hooks."
    note hooks "PULADO (sem node)"
    return
  fi
  local tmp
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/vct.XXXXXX")"
  write_hook_files "$tmp"
  local hook_cmd="node \"$HOOK_DIR/session-context.mjs\""
  local merge_status
  merge_status="$(node "$tmp/merge-settings.mjs" "$SETTINGS" "$hook_cmd" "$tmp/settings.new.json")"
  local rc=$?
  if test $rc -ne 0; then
    note hooks "FALHOU (settings.json inválido)"; FAILS=$((FAILS+1))
    rm -rf "$tmp"
    return
  fi
  local hooks_same=0
  if test -f "$HOOK_DIR/session-context.mjs" && cmp -s "$tmp/session-context.mjs" "$HOOK_DIR/session-context.mjs"; then
    hooks_same=1
  fi
  if test "$merge_status" = "UNCHANGED" && test "$hooks_same" = 1; then
    say "  hooks já instalados e settings.json já contém a entrada"
    note hooks "já configurado"
    rm -rf "$tmp"
    return
  fi
  say "  hook: $HOOK_DIR/session-context.mjs (SessionStart, timeout 5s, só injeta contexto, nunca bloqueia)"
  if test "$merge_status" = "CHANGED"; then
    say "  settings.json resultante (bloco hooks):"
    node -e 'const s=require(process.argv[1]); console.log(JSON.stringify({hooks:s.hooks},null,2))' "$tmp/settings.new.json" | sed 's/^/    /'
  fi
  if test "$MODE" = "apply"; then
    mkdir -p "$HOOK_DIR"
    cp "$tmp/session-context.mjs" "$HOOK_DIR/session-context.mjs"
    if test "$merge_status" = "CHANGED"; then
      if test -f "$SETTINGS"; then
        local bak="$SETTINGS.bak-vct-$(date +%Y%m%d%H%M%S)"
        cp "$SETTINGS" "$bak"
        say "  backup: $bak"
      fi
      cp "$tmp/settings.new.json" "$SETTINGS"
    fi
    note hooks configurado
  else
    say "  (dry-run) gravaria $HOOK_DIR/session-context.mjs"
    if test "$merge_status" = "CHANGED"; then
      say "  (dry-run) faria backup e atualizaria $SETTINGS"
    fi
    note hooks "seria configurado"
  fi
  rm -rf "$tmp"
}

want superpowers && step_superpowers
say
want context7 && step_context7
say
want agent-browser && step_agent_browser
say
want hooks && step_hooks
say

say "== Resumo ($MODE) =="
printf '%s' "$RESULTS" | while IFS='|' read -r k v; do
  test -n "$k" && printf '  %-14s %s\n' "$k" "$v"
done
if test "$MODE" = "dry-run"; then
  say "Nada foi alterado. Para aplicar: --apply"
fi
if test "$FAILS" -gt 0; then
  exit 1
fi
exit 0
