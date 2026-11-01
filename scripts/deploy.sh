#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
set -euo pipefail
REMOTE="${DEPLOY_REMOTE:-devops}"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${CA_CERT:-${HOME}/devops.crt}"
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
LOCAL_DIR="$ROOT/site/"
DRY_RUN=false
if [[ $# -gt 1 ]]; then echo 'Использование: deploy.sh [--dry-run]' >&2; exit 1; fi
if [[ $# -eq 1 ]]; then
    [[ "$1" == --dry-run ]] || { echo 'Неизвестный аргумент' >&2; exit 1; }
    DRY_RUN=true
fi
[[ -f "${LOCAL_DIR}index.html" ]] || { echo 'Отсутствует site/index.html' >&2; exit 1; }
[[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ]] || { echo 'Есть незафиксированные изменения' >&2; exit 1; }
args=(-avz --delete --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r -e 'ssh -o BatchMode=yes -o ConnectTimeout=5')
if $DRY_RUN; then args+=(--dry-run); fi
rsync "${args[@]}" "$LOCAL_DIR" "$REMOTE:$REMOTE_DIR/" || { echo 'Ошибка доставки' >&2; exit 1; }
if $DRY_RUN; then exit 0; fi
curl --fail --silent --show-error --connect-timeout 5 --max-time 15 --cacert "$CA_CERT" "$SITE_URL/" >/dev/null || { echo 'Проверка HTTPS не пройдена' >&2; exit 1; }
printf 'Доставлен коммит %s\n' "$(git -C "$ROOT" rev-parse --short HEAD)"
