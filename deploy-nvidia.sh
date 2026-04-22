#!/bin/bash
# =============================================================================
# deploy-nvidia.sh — Deploy nvidia.raw sysext to TrueNAS SCALE
#
# Usage:  ./deploy-nvidia.sh <path-to-nvidia.raw>
#
# This script:
#   1. Unmerges any active sysext extensions
#   2. Unlocks the read-only /usr ZFS dataset
#   3. Backs up the existing nvidia.raw alongside this script
#   4. Copies the new nvidia.raw into place
#   5. Re-locks /usr and merges extensions
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()   { echo -e "${RED}[FATAL]${NC} $*" >&2; exit 1; }

SYSEXT_DIR="/usr/share/truenas/sysext-extensions"
NVIDIA_RAW="${SYSEXT_DIR}/nvidia.raw"

# Backup directory — same directory as this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backups"

# ── Validate input ──────────────────────────────────────────────────────────
[[ $# -ge 1 ]] || die "Usage: $0 <path-to-nvidia.raw>"
[[ $(id -u) -eq 0 ]] || die "This script must be run as root."

NEW_RAW="$1"
[[ -f "${NEW_RAW}" ]] || die "File not found: ${NEW_RAW}"

NEW_SIZE=$(stat -c%s "${NEW_RAW}" 2>/dev/null || echo "unknown")
info "New image: ${NEW_RAW} (${NEW_SIZE} bytes)"
info "Will install as: ${NVIDIA_RAW}"
info "Backup dir: ${BACKUP_DIR}"

# ── Step 1: Unmerge active sysext ───────────────────────────────────────────
info "Unmerging active sysext extensions …"
systemd-sysext unmerge
ok "Extensions unmerged"

# ── Step 2: Unlock /usr ZFS dataset ─────────────────────────────────────────
USR_DATASET="$(zfs list -H -o name /usr)"
info "Unlocking ZFS dataset: ${USR_DATASET}"
zfs set readonly=off "${USR_DATASET}"
ok "Dataset unlocked (readonly=off)"

# ── Step 3: Backup existing nvidia.raw ──────────────────────────────────────
if [[ -f "${NVIDIA_RAW}" ]]; then
    mkdir -p "${BACKUP_DIR}"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP="${BACKUP_DIR}/nvidia.raw.backup_${TIMESTAMP}"
    info "Backing up existing nvidia.raw → ${BACKUP}"
    cp "${NVIDIA_RAW}" "${BACKUP}"
    ok "Backup saved: ${BACKUP} ($(du -h "${BACKUP}" | cut -f1))"

    # Keep only the 5 most recent backups
    BACKUP_COUNT=$(ls -1 "${BACKUP_DIR}"/nvidia.raw.backup_* 2>/dev/null | wc -l)
    if [[ ${BACKUP_COUNT} -gt 5 ]]; then
        info "Cleaning old backups (keeping 5 most recent) …"
        ls -1t "${BACKUP_DIR}"/nvidia.raw.backup_* | tail -n +6 | while read -r old; do
            info "  Removing: $(basename "${old}")"
            rm -f "${old}"
        done
    fi
else
    warn "No existing nvidia.raw found — fresh install"
fi

# ── Step 4: Copy new nvidia.raw ────────────────────────────────────────────
info "Installing new nvidia.raw …"
cp "${NEW_RAW}" "${NVIDIA_RAW}"
chmod 644 "${NVIDIA_RAW}"
ok "Installed: ${NVIDIA_RAW} ($(stat -c%s "${NVIDIA_RAW}") bytes)"

# ── Step 5: Re-lock /usr and merge ──────────────────────────────────────────
info "Locking ZFS dataset: ${USR_DATASET}"
zfs set readonly=on "${USR_DATASET}"
ok "Dataset locked (readonly=on)"

info "Merging sysext extensions …"
systemd-sysext merge
ok "Extensions merged"

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}  ✓ nvidia.raw deployed successfully${NC}"
echo ""
echo -e "  Verify with:  ${CYAN}nvidia-smi${NC}"
echo ""

# List current backups
BACKUP_LIST=$(ls -1t "${BACKUP_DIR}"/nvidia.raw.backup_* 2>/dev/null || true)
if [[ -n "${BACKUP_LIST}" ]]; then
    echo -e "  ${BOLD}Available rollback backups:${NC}"
    echo "${BACKUP_LIST}" | while read -r b; do
        SIZE=$(du -h "${b}" | cut -f1)
        echo -e "    $(basename "${b}")  (${SIZE})"
    done
    echo ""
    echo -e "  To rollback:  ${CYAN}$0 ${BACKUP_DIR}/nvidia.raw.backup_YYYYMMDD_HHMMSS${NC}"
    echo ""
fi
