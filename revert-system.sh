#!/bin/bash
# revert-system.sh [BACKUP_DIR] — restore the originals saved by install-system.sh
set -u -o pipefail
CX_ROOT=${CX_ROOT:-/opt/cxoffice}

if [ "$(id -u)" != 0 ]; then
  exec sudo -- "$0" "$@"
fi
set -e

if [ -n "${1:-}" ]; then
  BACKUP=$1
else
  BACKUP=$(ls -1d /var/backups/cx-trial-patch-* 2>/dev/null | sort | tail -1)
fi
[ -d "$BACKUP" ] || { echo "找不到备份目录，请显式指定"; exit 1; }
echo "从 $BACKUP 恢复"

for f in "$BACKUP"/winewrapper-*.exe; do
  [ -f "$f" ] || continue
  arch=$(basename "$f" .exe); arch=${arch#winewrapper-}
  install -m 755 -o root -g root "$f" "$CX_ROOT/lib/wine/$arch-windows/winewrapper.exe"
  echo "恢复 $arch winewrapper.exe"
done
[ -f "$BACKUP/demoutils.py" ] && install -m 644 -o root -g root "$BACKUP/demoutils.py" "$CX_ROOT/lib/python/demoutils.py" && echo "恢复 demoutils.py"
echo "完成"
