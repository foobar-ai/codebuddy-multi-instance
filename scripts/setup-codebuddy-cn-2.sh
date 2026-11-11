#!/usr/bin/env bash
# ============================================================================
# CodeBuddy CN 2 —— 一键双开安装 / 修复 / 升级脚本（macOS）
#
# 做什么：把 /Applications/CodeBuddy CN.app 克隆为完全独立的第二实例
#         "CodeBuddy CN 2.app"（独立 Dock 图标、独立数据目录、独立登录态）。
#         已安装过 = 修复；主 app 升级后运行 = 同步新版本。
#
# 隔离四层（对应 CodeBuddy CN 4.x VS Code fork 架构）：
#   1. 扩展层数据目录 ~/.codebuddy      → 环境变量 CODEBUDDY_CONFIG_DIR
#   2. VS Code 用户数据 ~/.codebuddycn  → product.json.dataFolderName
#   3. Electron 会话层（登录态）        → product.json.nameShort / nameLong
#   4. 偏好 plist / 更新缓存           → product.json.darwinBundleIdentifier
#
# 主 app /Applications/CodeBuddy CN.app 全程只读，绝不修改。
# 数据目录 ~/.codebuddy-2 与 ~/.codebuddycn2 永不被本脚本删除或覆盖。
#
# 用法：bash setup-codebuddy-cn-2.sh              # 安装/修复并启动
#       bash setup-codebuddy-cn-2.sh --no-launch  # 只部署，不启动
#       bash setup-codebuddy-cn-2.sh --force      # 强制重建
# ============================================================================
set -euo pipefail

SRC="/Applications/CodeBuddy CN.app"
DST="/Applications/CodeBuddy CN 2.app"
ALT_ID="com.tencent.codebuddycn.alt2"
CFG_DIR="$HOME/.codebuddy-2"        # CODEBUDDY_CONFIG_DIR 目标（扩展层）
DATA_FOLDER_NAME=".codebuddycn2"    # product.json.dataFolderName（VS Code 层）
DISPLAY_NAME="CodeBuddy CN 2"       # CFBundleDisplayName / nameShort / nameLong
ORIG_BUNDLE_NAME="CodeBuddy CN"     # CFBundleName 必须保持，绝不改
PRODUCT_JSON_REL="Contents/Resources/app/product.json"

# ---------------------------------------------------------------- 参数解析
FORCE=0
NO_LAUNCH=0
for arg in "$@"; do
  case "$arg" in
    --force)     FORCE=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
  esac
done

# ---------------------------------------------------------------- 前置检查
if [ "$(uname)" != "Darwin" ]; then
  echo "❌ 本脚本仅支持 macOS。"; exit 1
fi
if [ ! -d "$SRC" ]; then
  echo "❌ 找不到主 app：$SRC"
  echo "   请确认 CodeBuddy CN 已安装在 /Applications。"; exit 1
fi

MAIN_VER=$(defaults read "$SRC/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
echo "🔍 主 app 版本：${MAIN_VER}"
case "$MAIN_VER" in
  4.*) : ;;
  *) echo "⚠️  当前版本 ${MAIN_VER} 未经此脚本验证（已在 4.12.4 上验证），请知悉。" ;;
esac

CUR_VER=""
if [ -d "$DST" ]; then
  CUR_VER=$(defaults read "$DST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "")
  echo "📦 副本当前版本：${CUR_VER:-?}"
fi

# 已是最新版则跳过，避免白白关掉副本重建一遍（首次安装 DST 不存在不受影响）
if [ -n "$CUR_VER" ] && [ "$CUR_VER" = "$MAIN_VER" ] && [ "$FORCE" -eq 0 ]; then
  echo "✨ 副本已是最新版 ${CUR_VER}，无需更新（想强制重建加 --force）"
  exit 0
fi

# ---------------------------------------------------------------- 1. 关闭副本
# 精确路径匹配（绝不 pkill -f，会误杀执行脚本自身的 shell）
echo "⏹  关闭旧副本进程（如有）…"
# 管道末尾 || true：grep 无匹配时返回 1，pipefail + set -e 会误中断脚本（首次部署无旧进程）
ps aux | grep -E 'CodeBuddy CN 2\.app/Contents' | grep -v grep \
  | awk '{print $2}' | while read -r p; do kill "$p" 2>/dev/null || true; done || true
sleep 2

# ---------------------------------------------------------------- 2. 克隆副本
echo "♻️  克隆副本（APFS clone，约 2 秒）…"
rm -rf "$DST"
cp -R "$SRC" "$DST"

# ---------------------------------------------------------------- 3. 改 Info.plist
# ⚠️ 绝不改 CFBundleName！Electron 按 "CFBundleName Helper" 在 Contents/Frameworks/
#    里找辅助进程（CodeBuddy CN Helper.app 等四个）。改了 → FATAL: Unable to find helper app，
#    表现为 Dock 有图标但永远没有窗口。
echo "🪪  改写 Info.plist（Bundle ID / 显示名 / 环境变量）…"
INFO_PLIST="$DST/Contents/Info.plist"
plutil -replace CFBundleIdentifier  -string "$ALT_ID"       "$INFO_PLIST"
plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$INFO_PLIST"
# 环境变量：合并而非覆盖，保留系统默认 LSEnvironment.MallocNanoZone
plutil -replace LSEnvironment.CODEBUDDY_CONFIG_DIR -string "$CFG_DIR" "$INFO_PLIST"
# CFBundleName 保持原值 CodeBuddy CN，故意不动。
# 删除副本的 URL 协议注册（克隆自主 app，与主 app 同注册 codebuddycn:// 会产生协议竞争，
# lsregister 副本后网页唤起「CodeBuddy IDE」会被浏览器导向副本。删掉后协议永远归主实例）。
plutil -remove CFBundleURLTypes "$INFO_PLIST" 2>/dev/null || true

# ---------------------------------------------------------------- 4. 改 product.json 四字段
# 不改这里，两个实例会共用同一份 Electron 会话存储（登录态）与 VS Code 用户数据。
#   dataFolderName           → 隔离 ~/.codebuddycn（extensions / argv.json / secret storage）
#   nameShort / nameLong     → 隔离 Electron userData/sessionData（Session Storage 登录态所在地）
#   darwinBundleIdentifier   → 隔离偏好 plist / 更新缓存目录名
# 明确不改：applicationName、serverApplicationName、urlProtocol（改它们会破坏服务端/协议绑定）
PRODUCT_JSON="$DST/$PRODUCT_JSON_REL"
if [ -f "$PRODUCT_JSON" ]; then
  echo "🧬  改写 product.json（dataFolderName / nameShort / nameLong / darwinBundleIdentifier）…"
  /usr/bin/python3 - "$PRODUCT_JSON" "$DATA_FOLDER_NAME" "$DISPLAY_NAME" "$ALT_ID" <<'PYEOF'
import json, sys
path, data_folder, display, alt_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(path))
d['dataFolderName'] = data_folder
d['nameShort'] = display
d['nameLong'] = display
d['darwinBundleIdentifier'] = alt_id
json.dump(d, open(path, 'w'), ensure_ascii=False, indent=2)
print("   ✅ product.json 四字段已隔离")
PYEOF
else
  echo "⚠️  未找到 product.json：$PRODUCT_JSON —— 登录态可能无法隔离！"
fi

# ---------------------------------------------------------------- 5. 重签名 + 清隔离属性
# 改任何 app 内文件都会使签名失效，否则 macOS 报"已损坏"。ad-hoc 签名 + 清 quarantine/provenance。
echo "🔏  ad-hoc 重签名…"
if ! codesign --force --deep --sign - "$DST" >/dev/null 2>&1; then
  echo "   ⚠️  codesign 返回非零退出码（可能真失败）。若启动报「已损坏」，请重跑本脚本。"
fi
xattr -cr "$DST"
if codesign --verify --deep "$DST" >/dev/null 2>&1; then
  echo "   ✅ 签名校验通过"
else
  echo "   ⚠️  codesign --verify 未通过；若启动报「已损坏」，请重跑本脚本。"
fi

# ---------------------------------------------------------------- 6. 准备数据目录
# 只继承「无身份」内容（skills / mcp.json）。
# 身份/会话类（sessions、memery、traces、app、local_storage、projects、history.jsonl 等）
# 一律不拷 —— 拷了等于复制主实例身份，会互踢或串号。
echo "📁  准备数据目录 ${CFG_DIR} …"
mkdir -p "$CFG_DIR"
if [ -d "$HOME/.codebuddy/skills" ] && [ ! -d "$CFG_DIR/skills" ]; then
  cp -R "$HOME/.codebuddy/skills" "$CFG_DIR/skills" 2>/dev/null \
    && echo "   ✅ 已继承 skills/（如不需要可删除 ${CFG_DIR}/skills）"
fi
if [ -f "$HOME/.codebuddy/mcp.json" ] && [ ! -f "$CFG_DIR/mcp.json" ]; then
  cp "$HOME/.codebuddy/mcp.json" "$CFG_DIR/mcp.json" 2>/dev/null \
    && echo "   ✅ 已继承 mcp.json"
fi

# ---------------------------------------------------------------- 7. 注册 LaunchServices
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f -R "$DST" >/dev/null 2>&1 || true

NEW_VER=$(defaults read "$DST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")

# ---------------------------------------------------------------- 8. 自检（任一不对立刻停手报警）
echo "🔬  自检隔离配置…"
FAIL=0

BN=$(defaults read "$DST/Contents/Info.plist" CFBundleName 2>/dev/null || echo "?")
if [ "$BN" = "$ORIG_BUNDLE_NAME" ]; then
  echo "   ✅ CFBundleName 保持 ${ORIG_BUNDLE_NAME}（未误改）"
else
  echo "   ❌ CFBundleName = ${BN} —— 被改过！Helper 会找不到，必须恢复为 ${ORIG_BUNDLE_NAME}"; FAIL=1
fi

BID=$(defaults read "$DST/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "?")
if [ "$BID" = "$ALT_ID" ]; then
  echo "   ✅ CFBundleIdentifier = ${BID}"
else
  echo "   ❌ CFBundleIdentifier = ${BID}（应为 ${ALT_ID}）"; FAIL=1
fi

ENV_VAL=$(plutil -extract LSEnvironment.CODEBUDDY_CONFIG_DIR raw -o - "$INFO_PLIST" 2>/dev/null || echo "")
if [ "$ENV_VAL" = "$CFG_DIR" ]; then
  echo "   ✅ LSEnvironment.CODEBUDDY_CONFIG_DIR = ${ENV_VAL}"
else
  echo "   ❌ 环境变量注入异常（当前: ${ENV_VAL:-未设置}）"; FAIL=1
fi

if [ -f "$PRODUCT_JSON" ]; then
  if ! /usr/bin/python3 - "$PRODUCT_JSON" "$DATA_FOLDER_NAME" "$DISPLAY_NAME" "$ALT_ID" <<'PYEOF'
import json, sys
path, data_folder, display, alt_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(path))
checks = [
    ("dataFolderName",         d.get('dataFolderName'),         data_folder),
    ("nameShort",              d.get('nameShort'),              display),
    ("nameLong",               d.get('nameLong'),               display),
    ("darwinBundleIdentifier", d.get('darwinBundleIdentifier'), alt_id),
]
ok = True
for name, got, want in checks:
    if got == want:
        print(f"   ✅ {name} = {got}")
    else:
        print(f"   ❌ {name} = {got}（应为 {want}）"); ok = False
sys.exit(0 if ok else 1)
PYEOF
  then
    FAIL=1
  fi
else
  echo "   ❌ product.json 不存在：$PRODUCT_JSON"; FAIL=1
fi

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "❌ 隔离自检未通过！请勿使用副本，检查 product.json / Info.plist 字段是否被新版改动。"
  exit 1
fi

echo ""
echo "✅ 部署完成：CodeBuddy CN 2 v${NEW_VER}"
echo "   · 程序：$DST"
echo "   · 数据（扩展层）：$CFG_DIR（独立登录态，首次启动请重新登录第二个账号）"
echo "   · VS Code 层：$HOME/${DATA_FOLDER_NAME}"
echo ""

# ---------------------------------------------------------------- 9. 启动
if [ "$NO_LAUNCH" -eq 0 ]; then
  echo "🚀 启动 CodeBuddy CN 2 …"
  open -a "$DST"
  sleep 3
  echo "   如果 Dock 出现第二个图标但没窗口，等 10 秒再点一次图标即可。"
fi

echo ""
echo "🧪 建议运行隔离自检：bash scripts/verify-isolation.sh"
