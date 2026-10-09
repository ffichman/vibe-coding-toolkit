#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_DIR="$(dirname "$SCRIPT_DIR")"
TPL="$KIT_DIR/templates"
EXCLUSIONS="$SCRIPT_DIR/exclusions.txt"
ESLINT_VERSION="9.39.5"
TSESLINT_VERSION="8.71.1"
MAX_LINES=350

MODE="dry-run"
INSTALL_DEPS=0
MEASURE=0
TARGET=""

usage() {
  echo "uso: apply-repo.sh <caminho-do-repo> [--dry-run | --apply] [--install-deps] [--measure]"
  echo "padrão: --dry-run. Nunca refatora, nunca roda --fix, nunca sobrescreve arquivo existente."
}

while test $# -gt 0; do
  case "$1" in
    --apply) MODE="apply"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --install-deps) INSTALL_DEPS=1; shift ;;
    --measure) MEASURE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "argumento desconhecido: $1" >&2; usage; exit 64 ;;
    *) TARGET="$1"; shift ;;
  esac
done

if test -z "$TARGET"; then
  usage
  exit 64
fi
if ! test -d "$TARGET"; then
  echo "ERRO: $TARGET não é um diretório" >&2
  exit 66
fi
TARGET="$(cd "$TARGET" && pwd)"
if test "$TARGET" = "$KIT_DIR"; then
  echo "ERRO: o alvo é o próprio toolkit" >&2
  exit 64
fi

say() { printf '%s\n' "$*"; }
ACTIONS=0

REPO_NAME="$(basename "$TARGET")"
REMOTE="$(git -C "$TARGET" remote get-url origin 2>/dev/null || true)"

EXCLUDED=0
EXCL_MATCH=""
if test -f "$EXCLUSIONS"; then
  while IFS= read -r pat || test -n "$pat"; do
    pat="$(printf '%s' "$pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    case "$pat" in
      "") continue ;;
      "#"*) continue ;;
    esac
    if printf '%s\n%s\n' "$REPO_NAME" "$REMOTE" | grep -Fqi -- "$pat"; then
      EXCLUDED=1
      EXCL_MATCH="$pat"
      break
    fi
  done < "$EXCLUSIONS"
fi

HAS_JS=0
HAS_TS=0
HAS_SWIFT=0
if test -n "$(find "$TARGET" -maxdepth 2 \( -name node_modules -o -name .git \) -prune -o -name package.json -print 2>/dev/null | head -n 1)"; then
  HAS_JS=1
fi
if test -n "$(find "$TARGET" -maxdepth 2 \( -name node_modules -o -name .git \) -prune -o \( -name 'tsconfig*.json' \) -print 2>/dev/null | head -n 1)"; then
  HAS_JS=1
  HAS_TS=1
fi
if test -f "$TARGET/package.json" && grep -q '"typescript"' "$TARGET/package.json"; then
  HAS_TS=1
fi
if test -n "$(find "$TARGET" -maxdepth 2 \( -name Package.swift -o -name '*.xcodeproj' -o -name '*.xcworkspace' \) -print 2>/dev/null | head -n 1)"; then
  HAS_SWIFT=1
elif test -n "$(find "$TARGET" -maxdepth 4 \( -name node_modules -o -name .git -o -name Pods -o -name .build \) -prune -o -name '*.swift' -print 2>/dev/null | head -n 1)"; then
  HAS_SWIFT=1
fi

STACK=""
test "$HAS_JS" = 1 && STACK="${STACK}js "
test "$HAS_TS" = 1 && STACK="${STACK}ts "
test "$HAS_SWIFT" = 1 && STACK="${STACK}swift "
test -z "$STACK" && STACK="outros"

say "== vibe-coding-toolkit apply-repo (modo: $MODE) =="
say "repo:    $TARGET"
say "origin:  ${REMOTE:-sem remote}"
say "stack:   $STACK"
if test "$EXCLUDED" = 1; then
  say "lista de exclusão: SIM (padrão \"$EXCL_MATCH\") -> só CLAUDE.md + medição efêmera"
else
  say "lista de exclusão: não"
fi
if git -C "$TARGET" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  dirty="$(git -C "$TARGET" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  say "git:     branch $(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null), $dirty arquivo(s) modificado(s)"
else
  say "git:     não é um repositório git"
fi
say

place() {
  local src="$1"
  local dest="$2"
  local rel="${dest#$TARGET/}"
  if test -e "$dest"; then
    if cmp -s "$src" "$dest"; then
      say "  = $rel (já existe, idêntico)"
    else
      say "  ! $rel (já existe e é diferente; mantido sem alteração)"
    fi
    return 0
  fi
  ACTIONS=$((ACTIONS+1))
  if test "$MODE" = "apply"; then
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    say "  + $rel (criado)"
  else
    say "  (dry-run) criaria $rel ($(wc -l < "$src" | tr -d ' ') linhas)"
  fi
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/vct-apply.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

safe_name="$(printf '%s' "$REPO_NAME" | sed 's/[\/&]/\\&/g')"

build_claude_md() {
  sed "s/\[PROJECT NAME\]/$safe_name/" "$TPL/CLAUDE.md.template" > "$WORK/CLAUDE.md"
  if test "$EXCLUDED" = 1; then
    {
      echo
      echo "## Guardrails (vibe-coding-toolkit)"
      echo
      echo "- Este repo está na lista de exclusão do toolkit: sem quality gates instalados e sem MEMORY.md."
      echo "- Nunca refatore, reformate ou rode --fix por causa de métricas. Medição só sob pedido explícito."
    } >> "$WORK/CLAUDE.md"
    return
  fi
  if test "$WANT_MEMORY" = 0; then
    return
  fi
  {
    echo
    echo "## Memory"
    echo
    echo "@.claude/memory/MEMORY.md"
  } >> "$WORK/CLAUDE.md"
  if test "$HAS_JS" = 1 || test "$HAS_SWIFT" = 1; then
    {
      echo
      echo "## Quality gates (modo só-medição)"
      echo
      echo "- Medir: \`bash .quality/measure.sh\` (MAX_LINES=$MAX_LINES). Tudo é aviso; nada bloqueia build ou CI."
      echo "- Nunca refatore, reformate ou rode --fix por causa desses avisos sem pedido explícito."
    } >> "$WORK/CLAUDE.md"
  fi
}

WANT_MEMORY=0
if test "$EXCLUDED" = 0 && { test "$HAS_JS" = 1 || test "$HAS_SWIFT" = 1; }; then
  WANT_MEMORY=1
fi

say "-- CLAUDE.md --"
build_claude_md
place "$WORK/CLAUDE.md" "$TARGET/CLAUDE.md"
if test -e "$TARGET/CLAUDE.md" && ! grep -q 'MEMORY.md' "$TARGET/CLAUDE.md" && test "$WANT_MEMORY" = 1; then
  say "  dica: CLAUDE.md existente não importa a memória; adicione manualmente a linha @.claude/memory/MEMORY.md"
fi

if test "$WANT_MEMORY" = 1; then
  say "-- MEMORY.md --"
  sed "s/\[PROJECT NAME\]/$safe_name/" "$TPL/MEMORY.md.template" > "$WORK/MEMORY.md"
  place "$WORK/MEMORY.md" "$TARGET/.claude/memory/MEMORY.md"
fi

stage_quality() {
  local dest="$1"
  mkdir -p "$dest"
  cp "$TPL/quality/measure.sh" "$dest/measure.sh"
  cp "$TPL/quality/gitignore" "$dest/.gitignore"
  if test "$HAS_JS" = 1; then
    mkdir -p "$dest/eslint-rules"
    cp "$TPL/eslint/eslint-rules/utils.cjs" "$TPL/eslint/eslint-rules/core-rules.cjs" "$TPL/eslint/eslint-rules/index.cjs" "$dest/eslint-rules/"
    sed "s/^const MAX_LINES = [0-9]*;/const MAX_LINES = $MAX_LINES;/" "$TPL/quality/eslint.measure.config.mjs" > "$dest/eslint.measure.config.mjs"
  fi
  if test "$HAS_SWIFT" = 1; then
    sed "s/^  warning: [0-9]*$/  warning: $MAX_LINES/" "$TPL/quality/swiftlint.measure.yml" > "$dest/swiftlint.measure.yml"
  fi
}

measure_ephemeral() {
  local q="$WORK/quality"
  stage_quality "$q"
  say "  medição efêmera (configs em diretório temporário; nada é gravado no repo):"
  MAX_LINES="$MAX_LINES" bash "$q/measure.sh" --root "$TARGET" --report-dir "$WORK/reports" | sed 's/^/  | /'
}

if test "$HAS_JS" = 0 && test "$HAS_SWIFT" = 0; then
  say "-- Quality gates --"
  say "  stack sem gate definido: só CLAUDE.md."
elif test "$EXCLUDED" = 1; then
  say "-- Quality gates --"
  say "  repo excluído: nenhum arquivo de gate será criado."
  if test "$MODE" = "apply" || test "$MEASURE" = 1; then
    measure_ephemeral
  else
    say "  (dry-run) rodaria medição efêmera (use --measure para medir já no dry-run)"
  fi
else
  say "-- Quality gates (só medição, MAX_LINES=$MAX_LINES) --"
  stage_quality "$WORK/quality"
  for f in $(cd "$WORK/quality" && find . -type f | sed 's|^\./||' | sort); do
    place "$WORK/quality/$f" "$TARGET/.quality/$f"
  done
  if test "$MODE" = "apply" && test -f "$TARGET/.quality/measure.sh"; then
    chmod +x "$TARGET/.quality/measure.sh"
  fi
  if test "$HAS_JS" = 1; then
    if test -x "$TARGET/node_modules/.bin/eslint"; then
      say "  ESLint local: $("$TARGET/node_modules/.bin/eslint" --version 2>/dev/null) (não altero dependências)"
    elif test "$INSTALL_DEPS" = 1; then
      pkgs="eslint@$ESLINT_VERSION"
      test "$HAS_TS" = 1 && pkgs="$pkgs typescript-eslint@$TSESLINT_VERSION"
      if test -f "$TARGET/pnpm-lock.yaml"; then
        cmd="pnpm add -D --save-exact $pkgs"
      elif test -f "$TARGET/yarn.lock"; then
        cmd="yarn add -D --exact $pkgs"
      elif test -f "$TARGET/bun.lockb" || test -f "$TARGET/bun.lock"; then
        cmd="bun add -d --exact $pkgs"
      else
        cmd="npm install -D --save-exact $pkgs"
      fi
      ACTIONS=$((ACTIONS+1))
      if test "$MODE" = "apply"; then
        say "  + (cd repo && $cmd)"
        (cd "$TARGET" && sh -c "$cmd")
      else
        say "  (dry-run) instalaria devDependencies: $cmd"
      fi
    else
      say "  ESLint local ausente: a medição usa contagem de linhas até rodar com --install-deps"
    fi
  fi
  if test "$HAS_SWIFT" = 1 && ! command -v swiftlint > /dev/null 2>&1; then
    say "  SwiftLint ausente nesta máquina (brew install swiftlint); a medição usa contagem de linhas"
  fi
  if test "$MEASURE" = 1; then
    if test "$MODE" = "apply"; then
      MAX_LINES="$MAX_LINES" bash "$TARGET/.quality/measure.sh" | sed 's/^/  | /'
    else
      measure_ephemeral
    fi
  fi
fi

say
if test "$MODE" = "dry-run"; then
  say "Resumo: $ACTIONS ação(ões) seriam executadas. Nada foi alterado. Para aplicar: --apply"
else
  say "Resumo: $ACTIONS ação(ões) executadas. Nenhum commit feito no repo alvo; revise com git status."
fi
exit 0
