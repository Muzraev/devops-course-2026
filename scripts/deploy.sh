#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]

set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "${SCRIPT_DIR}/.." rev-parse --show-toplevel)"
LOCAL_DIR="${REPO_ROOT}/site/"

DRY_RUN=false

case "${1:-}" in
    "")
        ;;
    --dry-run)
        DRY_RUN=true
        ;;
    *)
        echo "Использование: $0 [--dry-run]" >&2
        exit 1
        ;;
esac

# Главная страница должна существовать.
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует." >&2
    exit 1
fi

# Деплой разрешён только из чистого состояния Git.
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения." >&2
    exit 1
fi

RSYNC_ARGS=(
    -avz
    --delete
    --chmod=D755,F644
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5"
)

if [[ "${DRY_RUN}" == true ]]; then
    RSYNC_ARGS+=(--dry-run)
fi

rsync "${RSYNC_ARGS[@]}" \
    "${LOCAL_DIR}" \
    "${REMOTE}:${REMOTE_DIR}/"

COMMIT_HASH="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"

if [[ "${DRY_RUN}" == true ]]; then
    echo "Dry-run завершён. Коммит: ${COMMIT_HASH}"
    exit 0
fi

if ! curl -fsS --cacert "${CA_CERT}" "${SITE_URL}" > /dev/null; then
    echo "Ошибка: ресурс недоступен после деплоя." >&2
    exit 1
fi

echo "Деплой выполнен успешно. Коммит: ${COMMIT_HASH}"
