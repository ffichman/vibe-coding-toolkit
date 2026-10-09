#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "uso: remote.sh <the-dock|the-nextt|usuario@host> [--dry-run | --apply] [outros args do install-global.sh]"
  echo "Envia bootstrap/install-global.sh por stdin e executa com bash no host remoto."
  echo "Funciona com qualquer shell de login (zsh no THE-NEXTT incluso): o script nunca é interpretado pelo zsh."
  echo "Chave: VCT_SSH_KEY=<arquivo> ou, para the-nextt, ~/.ssh/id_ed25519_thenextt se existir."
}

if test $# -lt 1; then
  usage
  exit 64
fi

KEY="${VCT_SSH_KEY:-}"
case "$1" in
  the-dock|THE-DOCK) TARGET="rodrigofichman@10.100.0.4" ;;
  the-nextt|THE-NEXTT)
    TARGET="thenextt@10.100.0.2"
    if test -z "$KEY" && test -f "$HOME/.ssh/id_ed25519_thenextt"; then
      KEY="$HOME/.ssh/id_ed25519_thenextt"
    fi
    ;;
  -h|--help) usage; exit 0 ;;
  *) TARGET="$1" ;;
esac
shift

echo "== remote.sh -> $TARGET ${KEY:+(chave: $KEY)} =="
if test -n "$KEY"; then
  ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" bash -s -- "$@" < "$SCRIPT_DIR/install-global.sh"
else
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$TARGET" bash -s -- "$@" < "$SCRIPT_DIR/install-global.sh"
fi
