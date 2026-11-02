#!/bin/bash
# install-user.sh — extend / register the trial of the system-installed CrossOver
# without root, by shadowing the two places the trial lives:
#
#   1) GUI / CLI licensing  : <CX_ROOT>/lib/python/demoutils.py  (demo_status)
#      -> replaced by a PYTHONPATH-shadowed module (reports "registered").
#   2) Embedded trial length: winewrapper.exe resource RT_RCDATA #128 (15 days)
#      -> patched copy under $PREFIX/wine/<arch>-windows/, selected per bottle
#         through the bottle's [Wine] DllPath (read by /opt/cxoffice/bin/wine).
#
# Everything is written under $XDG_DATA_HOME/cx-trial-patch and ~/.local; /opt is
# never touched. Idempotent: re-run after adding bottles. Use --dry-run to preview.
set -u -o pipefail

CX_ROOT=${CX_ROOT:-/opt/cxoffice}
TRIAL_DAYS=${TRIAL_DAYS:-36500}
PREFIX=${XDG_DATA_HOME:-$HOME/.local/share}/cx-trial-patch
BINDIR=$HOME/.local/bin
APPDIR=$HOME/.local/share/applications
KIT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

say() { printf '%s\n' "$*"; }
run() { if [ $DRY = 1 ]; then say "  + $*"; else eval "$@"; fi; }

[ -d "$CX_ROOT/lib/wine" ] || { say "未找到 $CX_ROOT/lib/wine，请设置 CX_ROOT"; exit 1; }

say "== CrossOver 试用时长改造（用户级，无需 root）=="
say "CX_ROOT   = $CX_ROOT"
say "PREFIX    = $PREFIX"
say "TRIAL_DAYS= $TRIAL_DAYS"

# ---------------------------------------------------------------- 1. 目录结构
run "mkdir -p '$PREFIX/lib' '$PREFIX/python' '$PREFIX/wine/x86_64-windows' '$PREFIX/wine/i386-windows' '$PREFIX/bin' '$BINDIR' '$APPDIR'"

# ------------------------------------------------- 2. 打补丁的 winewrapper.exe
for arch in x86_64 i386; do
  src=$CX_ROOT/lib/wine/$arch-windows/winewrapper.exe
  [ -f "$src" ] || continue
  dst=$PREFIX/wine/$arch-windows/winewrapper.exe
  run "cp -f '$src' '$dst' && chmod 755 '$dst'"
  run "python3 '$KIT/lib/pe_demo_len.py' set '$dst' '$TRIAL_DAYS'"
done

# ------------------------------------------------------- 3. demo_status 影子模块
run "cp -f '$KIT/lib/demoutils_override.py' '$PREFIX/python/demoutils.py'"

# ------------------------------------------------------------- 4. GUI 启动器覆写
cat > "$PREFIX/bin/crossover" <<EOF
#!/bin/sh
# CrossOver launcher with the trial override active.
PREFIX=\${XDG_DATA_HOME:-\$HOME/.local/share}/cx-trial-patch
if [ -d "\$PREFIX/python" ]; then
    PYTHONPATH="\$PREFIX/python\${PYTHONPATH:+:\$PYTHONPATH}"
    export PYTHONPATH
fi
exec $CX_ROOT/bin/crossover "\$@"
EOF
if [ $DRY = 0 ]; then chmod 755 "$PREFIX/bin/crossover"; else say "  + chmod 755 $PREFIX/bin/crossover"; fi
run "ln -sfn '$PREFIX/bin/crossover' '$BINDIR/crossover'"

# 桌面项覆盖（同名 .desktop 在 ~/.local/share/applications 中优先于 /usr/share）
SRC_DESKTOP=/usr/share/applications/cxmenu-cxoffice-0-29ra4ke-CrossOver.desktop
if [ -f "$SRC_DESKTOP" ]; then
  if [ $DRY = 1 ]; then
    say "  + sed Exec -> $PREFIX/bin/crossover 写入 $APPDIR/$(basename "$SRC_DESKTOP")"
  else
    sed "s#^Exec=.*#Exec=$PREFIX/bin/crossover %u#" "$SRC_DESKTOP" \
      > "$APPDIR/$(basename "$SRC_DESKTOP")"
    chmod 644 "$APPDIR/$(basename "$SRC_DESKTOP")"
  fi
fi

# ------------------------- 5. 全局 DllPath（对所有 bottle，含将来新建的）
# /opt/cxoffice/bin/wine 会依次读取 /opt/cxoffice/etc/cxoffice.conf 与
# ~/.cxoffice/cxoffice.conf，bottle 自己的 cxbottle.conf 里没有 [Wine] 段时，
# 这里写入的 DllPath 就是最终值，因此一个文件即可覆盖全部 bottle。
CONF=$HOME/.cxoffice/cxoffice.conf
DLLPATH="$PREFIX/wine/x86_64-windows:$PREFIX/wine/i386-windows:$CX_ROOT/lib/wine/x86_64-windows:$CX_ROOT/lib/wine/i386-windows"
if [ $DRY = 1 ]; then
  say "  + 在 $CONF 写入 [Wine] DllPath=$DLLPATH"
else
  mkdir -p "$HOME/.cxoffice"
  [ -f "$CONF" ] && cp -f "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
  python3 - "$CONF" "$DLLPATH" <<'PYEOF'
import os, re, sys
conf, dllpath = sys.argv[1], sys.argv[2]
txt = open(conf, encoding='utf-8').read() if os.path.exists(conf) else ''
txt = re.sub(r';; cx-trial-patch[^\n]*\n(?:[^\n]*\n)*?(?=\n*\[|\Z)', '', txt)
txt = re.sub(r'^"DllPath"\s*=.*cx-trial-patch.*\n', '', txt, flags=re.M)
entry = '"DllPath" = "%s"' % dllpath
if re.search(r'^\[Wine\]', txt, flags=re.M):
    block = ';; cx-trial-patch: wine 优先加载打过补丁的 winewrapper.exe\n%s\n' % entry
    txt = re.sub(r'^(\[Wine\][^\n]*\n)', lambda m: m.group(1) + block, txt, count=1, flags=re.M)
else:
    if txt and not txt.endswith('\n'):
        txt += '\n'
    txt += ('\n;; cx-trial-patch: wine 优先加载打过补丁的 winewrapper.exe\n'
            '[Wine]\n%s\n' % entry)
open(conf, 'w', encoding='utf-8').write(txt)
print('  ~ 已写入', conf)
PYEOF
fi

say ""
say "== 完成 =="
say "验证： bash $KIT/verify.sh"
say "回滚： bash $KIT/revert-user.sh"
