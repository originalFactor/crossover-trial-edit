#!/bin/bash
# install-system.sh — in-place modification of the system-installed CrossOver.
#
#   * <CX_ROOT>/lib/wine/{x86_64,i386}-windows/winewrapper.exe : RT_RCDATA #128
#     (embedded trial length, stock = 15 days) -> TRIAL_DAYS
#   * <CX_ROOT>/lib/python/demoutils.py : demo_status() returns "registered"
#
# Originals are copied to /var/backups/cx-trial-patch-<timestamp>/ first.
# A `crossover` package upgrade restores /opt, so re-run after upgrading.
set -u -o pipefail

CX_ROOT=${CX_ROOT:-/opt/cxoffice}
TRIAL_DAYS=${TRIAL_DAYS:-36500}
KIT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STAMP=$(date +%Y%m%d%H%M%S)
BACKUP=/var/backups/cx-trial-patch-$STAMP

if [ "$(id -u)" != 0 ]; then
  exec sudo -p "CrossOver 试用改造需要写入 $CX_ROOT，请输入密码: " -- "$0" "$@"
fi

set -e
mkdir -p "$BACKUP"
echo "== CrossOver 试用改造（系统级，就地修改）=="
echo "CX_ROOT=$CX_ROOT  TRIAL_DAYS=$TRIAL_DAYS  备份=$BACKUP"

for arch in x86_64 i386; do
  f=$CX_ROOT/lib/wine/$arch-windows/winewrapper.exe
  [ -f "$f" ] || continue
  install -m 755 -o root -g root "$f" "$BACKUP/winewrapper-$arch.exe"
  python3 "$KIT/lib/pe_demo_len.py" set "$f" "$TRIAL_DAYS"
done

DEMO=$CX_ROOT/lib/python/demoutils.py
install -m 644 -o root -g root "$DEMO" "$BACKUP/demoutils.py"
python3 - "$DEMO" <<'PY'
import sys
p = sys.argv[1]
txt = open(p, encoding='utf-8').read()
if '# cx-trial-patch' in txt:
    print('demoutils.py 已打过补丁，跳过')
    sys.exit(0)
needle = "    if not (os.path.exists(licenseFile) and os.path.exists(sigFile)):"
if needle not in txt:
    sys.exit('demoutils.py 结构与预期不符，未修改')
inject = ("    # cx-trial-patch: 强制报告为已注册（试用期无限）\n"
          "    return (False, 'CrossOver', '2099/12/31', '000000', False)\n")
txt = txt.replace(needle, inject + needle, 1)
open(p, 'w', encoding='utf-8').write(txt)
print('demoutils.py 已注入注册状态短路返回')
PY

echo
echo "== 结果 =="
for arch in x86_64 i386; do
  f=$CX_ROOT/lib/wine/$arch-windows/winewrapper.exe
  [ -f "$f" ] && python3 "$KIT/lib/pe_demo_len.py" print "$f"
done
grep -n "cx-trial-patch" "$DEMO" | head -3
echo
echo "回滚： sudo $KIT/revert-system.sh $BACKUP"
