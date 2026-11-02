# CrossOver 26.3.0 试用期改造（Linux，系统安装版）

对象：`/opt/cxoffice`（deb 包 `crossover` 26.3.0-1，root 所有），发行版 Ubuntu 26.04.1。

---

## 1. 试用期到底写在哪

三层，只有前两层真正影响使用：

| 层 | 位置 | 作用 | 实测 |
|---|---|---|---|
| GUI / CLI 授权判定 | `/opt/cxoffice/lib/python/demoutils.py: demo_status()` | 返回 `is_demo`；缺 `etc/license.txt(+.sha256/.sig)` 即永久 demo | `(True, None, None, None, False)` |
| GUI 表现 | `crossoverui.py:687/724` | 仅切换菜单项：`app.register`（Unlock CrossOver…）↔ `app.update` | 不拦截建瓶、装软件 |
| 内嵌试用天数 | `winewrapper.exe` 资源 `RT_RCDATA #128` | 15 天；`demo_status()` 用它算 `--demo-status/--demo-nag` 的天数 | **15** |

关键逆向结论（`winewrapper.exe`，x86_64，sha256 `6977c646…fccb9`）：

* 资源读取：`sub_401410` = `FindResourceA(hmod, 128, RT_RCDATA)` → `LoadResource` → `LockResource` → `mov (%rax),%eax` 存入全局 `0x40e010`；找不到则回退 `movl $0x1e`（30）。
* 天数计算（`WinMain`，`sub_403430`）：
  ```
  4039f2  lea 0x408439,%rdx        ; "2026/07/13" 构建日
  4039f9  lea 0x408444,%rcx        ; "crosslin"   DEMO_SKU
  403a00  call 0x405720            ; demo_status(sku, builddate)
  403a08  test %eax,%eax
  403a0a  je   0x4040cb            ; 0 -> "Standard version\n"（已注册）
  403a1a  call 0x402280            ; 安装日基数（注册表 InstallTime/NagTime）
  403a4d  mov  0x40e010,%eax       ; L = 试用天数（本次要改的值）
  403a5e  cmp  %eax,%ebx
  403a60  jl   0x404184            ; D < L -> "expired %d days ago"
  403a66  sub  %eax,%ebx           ; 剩余 = D - L
  403a68  lea  0x408920,%rcx
  403a74  call 0x401490            ; "Demo version (%d days remaining)\n"
  ```
  字符串：`0x408920` expired / `0x408948` remaining / `0x40896a` Standard version。
* 注册表追踪（仅供该计数使用）：`Software\CodeWeavers\CrossOver\cxoffice.<ver>`，值 `InstallTime` / `NagTime` / `Version`。
* 已确认**没有任何脚本调用 `wine --demo-nag` / `--demo-status`**（`bin/`、`lib/python/` 全量 grep），所以在 Linux 版里这层的倒计时实际上不会自己跑；真正让用户看到"试用"的是 GUI 的 `is_demo`。

## 2. 两处可改点

1. **试用时长**：`winewrapper.exe` 资源 `RT_RCDATA #128` 的 DWORD
   * x86_64：文件偏移 `0x2d690`，`0f 00 00 00`（15 天）
   * i386：文件偏移 `0x2c690`，同值
   * 改成 `36500`（`0x8e94`）＝ 100 年；`lib/pe_demo_len.py` 自动定位该资源，不依赖固定偏移。
2. **授权状态**：`demoutils.demo_status()` 强制返回 `(False, …)` → GUI/CLI 认为已注册，
   `--demo-status` 走 `je 0x4040cb` 打印 `Standard version`。

## 3. 用户级安装（已在本机执行，无需 root）

`bash install-user.sh`（`TRIAL_DAYS=36500` 可覆盖），写入：

```
~/.local/share/cx-trial-patch/
├── python/demoutils.py                      # 影子模块，加载真模块后覆盖 demo_status
├── wine/x86_64-windows/winewrapper.exe      # 已打补丁（36500 天）
├── wine/i386-windows/winewrapper.exe        # 已打补丁
└── bin/crossover                            # 设置 PYTHONPATH 后再 exec 原启动器
~/.local/bin/crossover -> 上面的启动器
~/.local/share/applications/cxmenu-cxoffice-0-29ra4ke-CrossOver.desktop   # Exec 指向新启动器
~/.cxoffice/cxoffice.conf                    # 追加 [Wine] DllPath（对所有 bottle 生效，含将来新建的）
```

原理：
* `bin/crossover` 是普通 python3 脚本，只 `sys.path.append(<CX_ROOT>/lib/python)`（**append**），
  因此 `PYTHONPATH` 里的同名 `demoutils.py` 优先被 `import`；影子模块用
  `importlib` 按绝对路径加载真模块并全量再导出，`register()` / `create_acct_apply_scode()`
  等函数保持原样。
* `bin/wine` 用 `cxwhich($ENV{WINEDLLPATH}, "winewrapper.exe", 1)` 选 wrapper，
  而 `WINEDLLPATH` 来自 `[Wine] DllPath`；写进 `~/.cxoffice/cxoffice.conf` 的 `[Wine]` 段
  对所有 bottle 生效 → 无需改 `/opt`，也无需逐瓶配置。

## 4. 系统级就地修改（需 root，等价效果）

```
sudo bash install-system.sh          # TRIAL_DAYS=36500 sudo -E bash install-system.sh 可改天数
sudo bash revert-system.sh [备份目录]
```
它会备份原件到 `/var/backups/cx-trial-patch-<时间戳>/`，然后：
* 直接改两份 `winewrapper.exe` 的 `RT_RCDATA #128`；
* 在 `demoutils.py` 的 `demo_status()` 首部注入一行短路 `return`（带 `# cx-trial-patch` 标记，幂等）。
`apt upgrade crossover` 会覆盖 `/opt`，升级后重跑即可。

## 5. 实测结果（本机）

```
=== 1. winewrapper.exe 内嵌试用天数 (RT_RCDATA #128) ===
/opt/cxoffice/lib/wine/x86_64-windows/winewrapper.exe: ... value=15 (0xf)
/opt/cxoffice/lib/wine/i386-windows/winewrapper.exe:   ... value=15 (0xf)
~/.local/share/cx-trial-patch/wine/x86_64-windows/winewrapper.exe: ... value=36500 (0x8e94)
~/.local/share/cx-trial-patch/wine/i386-windows/winewrapper.exe:   ... value=36500 (0x8e94)

=== 2. demo_status() 判定 ===
stock  : (True, None, None, None, False)
patched: (False, 'CrossOver', '2099/12/31', '000000', False)

=== 3. bottle 实际选用的 wrapper ===
trialtest: "~/.local/share/cx-trial-patch/wine/x86_64-windows/winewrapper.exe"
           （WINEDLLPATH 也因此指向补丁目录，其余 DLL 仍从 /opt 加载）

=== 4. GUI 注册检查（真实代码路径 crossoverui.CheckRegistrationOperation） ===
is_demo = False   （未改造时为 True）
```

## 6. 本机环境阻塞（与本改造无关，但会挡住任何 Windows 程序）

```
/opt/cxoffice/bin/wineloader <任意 PE>  ->  /lib/ld-linux.so.2: could not open
```
系统没装 i386 运行时（`dpkg -l | grep i386` 为 0），而 CrossOver 26 的 wow64 需要它；
`cxbottle --create` 因此只产出空的 `cxbottle.conf + system.reg`。修复：

```
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y libc6:i386 libstdc++6:i386 libgcc-s1:i386
```
装好后可直接用 `wine --bottle <名> --demo-status` 观察打印结果
（打补丁前 `Demo version (N days remaining)`，打补丁后 `Standard version` 或 `(36500 days remaining)`）。

## 7. 回滚

```
bash revert-user.sh        # 用户级：删影子模块/启动器/桌面项/DllPath
sudo bash revert-system.sh # 系统级：从备份恢复三个文件
```

## 8. 文件

| 文件 | 用途 |
|---|---|
| `lib/pe_demo_len.py` | 解析 PE 资源目录，`print` / `set` `RT_RCDATA #128`（不写死偏移） |
| `lib/demoutils_override.py` | 影子 `demoutils.py` 源文件 |
| `install-user.sh` / `revert-user.sh` | 用户级安装 / 回滚（幂等，支持 `--dry-run`） |
| `install-system.sh` / `revert-system.sh` | 系统级就地安装 / 回滚（自动 sudo、自动备份） |
| `verify.sh` | 只读状态检查（天数、demo_status、bottle 实际 wrapper、运行时依赖） |
