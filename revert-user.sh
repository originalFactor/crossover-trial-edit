#!/bin/bash
# revert-user.sh — undo install-user.sh (removes the shadow module, the launcher
# override, the desktop override and every [Wine] DllPath block it added).
set -u -o pipefail

PREFIX=${XDG_DATA_HOME:-$HOME/.local/share}/cx-trial-patch
BINDIR=$HOME/.local/bin
APPDIR=$HOME/.local/share/applications
DESKTOP=cxmenu-cxoffice-0-29ra4ke-CrossOver.desktop

if [ -L "$BINDIR/crossover" ]; then
  rm -f "$BINDIR/crossover"; echo "已移除 $BINDIR/crossover"
elif [ -f "$BINDIR/crossover" ]; then
  echo "保留 $BINDIR/crossover（不是本脚本创建的符号链接）"
fi

[ -f "$APPDIR/$DESKTOP" ] && { rm -f "$APPDIR/$DESKTOP"; echo "已移除 $APPDIR/$DESKTOP"; }

# 清理 ~/.cxoffice/cxoffice.conf 中的 DllPath 覆盖
CONF=$HOME/.cxoffice/cxoffice.conf
if [ -f "$CONF" ] && grep -q 'cx-trial-patch' "$CONF"; then
  python3 - "$CONF" <<'PYEOF'
import re, sys
p = sys.argv[1]
txt = open(p, encoding='utf-8').read()
txt = re.sub(r'\n;; cx-trial-patch[^\n]*\n', '\n', txt)
txt = re.sub(r'^"DllPath"\s*=.*cx-trial-patch.*\n', '', txt, flags=re.M)
txt = re.sub(r'\n\[Wine\]\n(?=\n*\Z)', '\n', txt)
open(p, 'w', encoding='utf-8').write(txt.rstrip('\n') + '\n')
PYEOF
  echo "已清理 $CONF 中的 DllPath"
fi

# 兼容早期版本：清理 bottle 内的 DllPath 块
shopt -s nullglob
for conf in "$HOME"/.cxoffice/*/cxbottle.conf; do
  if grep -q 'cx-trial-patch' "$conf" 2>/dev/null; then
    python3 - "$conf" <<'PYEOF'
import re, sys
p = sys.argv[1]
txt = open(p, encoding='utf-8', errors='surrogateescape').read()
txt = re.sub(r'\n;; cx-trial-patch[^\n]*\n(?:[^\n]*\n)*?(?=\n*\[|\Z)', '\n', txt)
txt = re.sub(r'^"DllPath"\s*=.*cx-trial-patch.*\n', '', txt, flags=re.M)
open(p, 'w', encoding='utf-8', errors='surrogateescape').write(txt)
PYEOF
    echo "已清理 $(basename "$(dirname "$conf")")/cxbottle.conf"
  fi
done

rm -rf "$PREFIX" && echo "已删除 $PREFIX"
echo "如需恢复 bell 备份： ~/.cxoffice/<bottle>/cxbottle.conf.bak.<时间戳>"
