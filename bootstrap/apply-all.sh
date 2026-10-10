#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="--dry-run"
DEPTH=4
ROOTS=""
LOG_DIR=""
FROM=""
KIT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
  echo "uso: apply-all.sh [--dry-run | --apply] [--depth N] [--log-dir DIR] [--from LISTA] [raiz...]"
  echo "--from LISTA: arquivo com um caminho de repo por linha (linhas com # são ignoradas); não faz varredura."
  echo "Acha repositórios git sob cada raiz e roda apply-repo.sh em cada um."
  echo "Pula node_modules, worktrees, mirrors, backups, obsoleto, Library e .Trash."
  echo "padrão: --dry-run (nada é alterado)"
}

while test $# -gt 0; do
  case "$1" in
    --apply) MODE="--apply"; shift ;;
    --dry-run) MODE="--dry-run"; shift ;;
    --depth) DEPTH="$2"; shift 2 ;;
    --log-dir) LOG_DIR="$2"; shift 2 ;;
    --from) FROM="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "argumento desconhecido: $1" >&2; usage; exit 64 ;;
    *) ROOTS="$ROOTS
$1"; shift ;;
  esac
done

if test -z "$ROOTS" && test -z "$FROM"; then
  usage
  exit 64
fi
if test -z "$LOG_DIR"; then
  LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vct-all.XXXXXX")"
fi
mkdir -p "$LOG_DIR"

LIST="$LOG_DIR/repos.txt"
: > "$LIST"
if test -n "$FROM"; then
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e "s|^~|$HOME|" "$FROM" | grep -v '^$' >> "$LIST"
fi
printf '%s\n' "$ROOTS" | while IFS= read -r root; do
  test -z "$root" && continue
  test -d "$root" || { echo "aviso: $root não existe" >&2; continue; }
  find "$root" -maxdepth "$DEPTH" \( -name node_modules -o -name worktrees -o -name mirrors -o -name 'backups*' -o -name 'obsoleto*' -o -name Library -o -name .Trash -o -name .build -o -name Pods \) -prune -o -name .git -print 2>/dev/null \
    | sed 's|/\.git$||' >> "$LIST"
done
grep -vxF "$KIT_DIR" "$LIST" > "$LIST.tmp"; mv "$LIST.tmp" "$LIST"
sort -u "$LIST" -o "$LIST"

TOTAL="$(wc -l < "$LIST" | tr -d ' ')"
echo "== vibe-coding-toolkit apply-all ($MODE) =="
echo "repositórios encontrados: $TOTAL"
echo "logs por repo: $LOG_DIR"
echo
printf '%-58s %-14s %-9s %s\n' "REPO" "STACK" "EXCLUÍDO" "AÇÕES"

n=0
while IFS= read -r repo; do
  test -z "$repo" && continue
  n=$((n+1))
  log="$LOG_DIR/$(printf '%03d' "$n")-$(basename "$repo").log"
  bash "$SCRIPT_DIR/apply-repo.sh" "$repo" "$MODE" > "$log" 2>&1
  stack="$(grep -m1 '^stack:' "$log" | sed 's/^stack: *//' | tr -s ' ' | sed 's/ $//' | tr ' ' '+')"
  if grep -q 'lista de exclusão: SIM' "$log"; then excl="sim"; else excl="não"; fi
  acts="$(grep -m1 '^Resumo:' "$log" | grep -Eo '[0-9]+ ação' | grep -Eo '[0-9]+')"
  short="$repo"
  case "$short" in "$HOME"/*) short="~${short#$HOME}" ;; esac
  printf '%-58s %-14s %-9s %s\n' "$short" "${stack:-?}" "$excl" "${acts:-erro}"
done < "$LIST"

echo
if test "$MODE" = "--dry-run"; then
  echo "Nada foi alterado. Revise os logs e rode com --apply, de preferência repo a repo com apply-repo.sh."
else
  echo "Aplicado. Nenhum commit foi feito nos repos; revise com git status em cada um."
fi
