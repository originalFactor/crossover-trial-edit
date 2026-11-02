#!/bin/bash
# verify.sh — show the trial state before/after, without changing anything.
set -u
CX_ROOT=${CX_ROOT:-/opt/cxoffice}
PREFIX=${XDG_DATA_HOME:-$HOME/.local/share}/cx-trial-patch
KIT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

echo "=== 1. winewrapper.exe 内嵌试用天数 (RT_RCDATA #128) ==="
for f in "$CX_ROOT"/lib/wine/x86_64-windows/winewrapper.exe \
         "$CX_ROOT"/lib/wine/i386-windows/winewrapper.exe \
         "$PREFIX"/wine/x86_64-windows/winewrapper.exe \
         "$PREFIX"/wine/i386-windows/winewrapper.exe ; do
  [ -f "$f" ] && python3 "$KIT/lib/pe_demo_len.py" print "$f"
done

echo
echo "=== 2. demo_status() 判定 ==="
printf 'stock  : '
env -u PYTHONPATH python3 -c "
import sys; sys.path.append('$CX_ROOT/lib/python')
import demoutils; print(demoutils.demo_status('$CX_ROOT/etc/license.txt','$CX_ROOT/etc/license.sha256'))" 2>/dev/null
printf 'patched: '
PYTHONPATH=$PREFIX/python python3 -c "
import demoutils; print(demoutils.demo_status('$CX_ROOT/etc/license.txt','$CX_ROOT/etc/license.sha256'), demoutils.__file__)" 2>/dev/null

echo
echo "=== 3. bottle 实际选用的 wrapper ==="
shopt -s nullglob
found=0
for conf in "$HOME"/.cxoffice/*/cxbottle.conf; do
  b=$(basename "$(dirname "$conf")")
  found=1
  printf '%s: ' "$b"
  WINEWRAPPER=$(timeout 120 "$CX_ROOT/bin/wine" --bottle "$b" --demo-status --verbose 2>&1 |
                grep -m1 '^  WINEWRAPPER' | sed 's/.*= //')
  echo "${WINEWRAPPER:-<未取到>}"
done
[ $found = 0 ] && echo "（当前没有 bottle）"

echo
echo "=== 4. Wine 运行时依赖 ==="
if [ -e /lib/ld-linux.so.2 ]; then
  echo "32-bit loader 存在；可直接运行 winewrapper 验证 --demo-status 输出"
else
  echo "缺少 /lib/ld-linux.so.2 —— CrossOver 的 wow64 需要 i386 运行时，"
  echo "修复: sudo dpkg --add-architecture i386 && sudo apt-get update && \\"
  echo "      sudo apt-get install -y libc6:i386 libstdc++6:i386 libgcc-s1:i386"
fi
