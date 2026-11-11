#!/usr/bin/env bash
# ============================================================================
# CodeBuddy CN 双开隔离自检 —— 逐项核对两个实例是否真正"分家"
# 用法：bash verify-isolation.sh
# 退出码：0 = 全部通过；1 = 存在未通过项
# ============================================================================
set -uo pipefail

SRC="/Applications/CodeBuddy CN.app"
DST="/Applications/CodeBuddy CN 2.app"
ALT_ID="com.tencent.codebuddycn.alt2"
CFG_DIR="$HOME/.codebuddy-2"
DATA_FOLDER_NAME=".codebuddycn2"
DISPLAY_NAME="CodeBuddy CN 2"
ORIG_BUNDLE_NAME="CodeBuddy CN"
PRODUCT_JSON="$DST/Contents/Resources/app/product.json"
INFO_PLIST="$DST/Contents/Info.plist"

PASS=0; FAIL=0
ok()  { echo " ✅ $1"; PASS=$((PASS+1)); }
bad() { echo " ❌ $1"; FAIL=$((FAIL+1)); }
note(){ echo " ⚠️ $1"; }

echo "════════════════════════════════════════════"
echo " CodeBuddy CN 双开隔离自检"
echo "════════════════════════════════════════════"
echo ""

# ---------------------------------------------------------------- 1/6 程序副本
echo "【1/6】程序副本"
if [ -d "$DST" ]; then
  ok "副本存在：$DST (v$(defaults read "$DST/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '?'))"
  BID=$(defaults read "$DST/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "?")
  if [ "$BID" = "$ALT_ID" ]; then ok "Bundle ID = $BID"; else bad "Bundle ID = $BID（应为 $ALT_ID）"; fi
  BN=$(defaults read "$DST/Contents/Info.plist" CFBundleName 2>/dev/null || echo "?")
  if [ "$BN" = "$ORIG_BUNDLE_NAME" ]; then
    ok "CFBundleName 保持 ${ORIG_BUNDLE_NAME}（未误改）"
  else
    bad "CFBundleName = $BN —— 被改过！Helper 会找不到，必须恢复为 ${ORIG_BUNDLE_NAME}"
  fi
  DISP=$(defaults read "$DST/Contents/Info.plist" CFBundleDisplayName 2>/dev/null || echo "?")
  if [ "$DISP" = "$DISPLAY_NAME" ]; then ok "CFBundleDisplayName = $DISP"; else bad "CFBundleDisplayName = $DISP（应为 $DISPLAY_NAME）"; fi
else
  bad "副本不存在，先运行 scripts/setup-codebuddy-cn-2.sh"
fi
echo ""

# ---------------------------------------------------------------- 2/6 环境变量注入
echo "【2/6】环境变量注入"
ENV_VAL=$(plutil -extract LSEnvironment.CODEBUDDY_CONFIG_DIR raw -o - "$INFO_PLIST" 2>/dev/null || echo "")
if [ "$ENV_VAL" = "$CFG_DIR" ]; then
  ok "LSEnvironment.CODEBUDDY_CONFIG_DIR = $ENV_VAL"
else
  bad "CODEBUDDY_CONFIG_DIR 注入异常（当前: '${ENV_VAL:-未设置}'）"
fi
# 系统默认项不应被覆盖
MALLOC=$(plutil -extract LSEnvironment.MallocNanoZone raw -o - "$INFO_PLIST" 2>/dev/null || echo "")
[ -n "$MALLOC" ] && ok "系统默认 LSEnvironment.MallocNanoZone 保留（=$MALLOC）" || note "LSEnvironment.MallocNanoZone 缺失（通常无碍，但建议保留）"
echo ""

# ---------------------------------------------------------------- 3/6 product.json 四字段
echo "【3/6】product.json 四字段"
if [ -f "$PRODUCT_JSON" ]; then
  /usr/bin/python3 - "$PRODUCT_JSON" "$DATA_FOLDER_NAME" "$DISPLAY_NAME" "$ALT_ID" <<'PYEOF'
import json, sys
path, data_folder, display, alt_id = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = json.load(open(path))
checks = [
    ("dataFolderName",         d.get('dataFolderName'),         data_folder),
    ("nameShort",              d.get('nameShort'),              display),
    ("nameLong",               d.get('nameLong'),               display),
    ("darwinBundleIdentifier", d.get('darwinBundleIdentifier'), alt_id),
    ("applicationName 未被改动", d.get('applicationName'),       'buddycn'),
]
ok = True
for name, got, want in checks:
    if got == want:
        print(f" ✅ {name} = {got}")
    else:
        print(f" ❌ {name} = {got}（应为 {want}）"); ok = False
sys.exit(0 if ok else 1)
PYEOF
  if [ $? -eq 0 ]; then PASS=$((PASS+5)); else FAIL=$((FAIL+1)); fi
else
  bad "product.json 不存在：$PRODUCT_JSON"
fi
echo ""

# ---------------------------------------------------------------- 4/6 数据目录
echo "【4/6】数据目录（扩展层）"
if [ -d "$CFG_DIR" ]; then
  ok "副本数据目录存在：$CFG_DIR"
else
  bad "副本数据目录不存在：$CFG_DIR（首次启动后应出现，或运行 setup 脚本）"
fi
if [ -d "$HOME/.codebuddy" ]; then
  ok "主实例数据目录未被挪动：$HOME/.codebuddy"
else
  note "主实例数据目录 $HOME/.codebuddy 不存在（从未启动过主实例？）"
fi
echo ""

# ---------------------------------------------------------------- 5/6 VS Code 层 + Electron 会话层
echo "【5/6】VS Code 层 与 Electron 会话层分离"
ALT_VDATA="$HOME/$DATA_FOLDER_NAME"
if [ -d "$ALT_VDATA" ]; then
  ok "副本 VS Code 用户数据目录已生成：$ALT_VDATA"
else
  note "副本 VS Code 用户数据目录尚未生成：$ALT_VDATA（首次启动后出现）"
fi
MAIN_SESSION="$HOME/Library/Application Support/CodeBuddy CN"
ALT_SESSION="$HOME/Library/Application Support/$DISPLAY_NAME"
if [ -d "$ALT_SESSION" ]; then
  ok "副本 Electron 会话目录已生成：$ALT_SESSION（登录态应在此独立）"
elif [ -d "$MAIN_SESSION" ]; then
  note "副本 Electron 会话目录尚未生成：$ALT_SESSION（首次启动后出现；若启动后仍不生成 → nameShort 未生效）"
else
  note "主实例 Electron 会话目录也不存在（从未启动？），此项暂无法判断"
fi
echo ""

# ---------------------------------------------------------------- 6/6 登录态隔离提示
echo "【6/6】登录态隔离"
# CodeBuddy CN 4.x 不使用 WorkBuddy 5.x 的全局共享 auth 文件；
# 登录态在 Electron Session Storage（Application Support/<nameShort>/Session Storage）。
# 此处仅做目录级诊断，不读取任何账号/令牌内容。
if [ -d "$ALT_SESSION/Session Storage" ]; then
  ok "副本独立 Session Storage 在场：$ALT_SESSION/Session Storage"
  if [ -d "$MAIN_SESSION/Session Storage" ]; then
    ok "主实例 Session Storage 原样存在（未串到副本）"
  fi
else
  note "副本 Session Storage 尚未生成 —— 属正常（登录/首次加载 webview 后出现）。若副本已登录却显示主账号，说明隔离未生效，重跑 setup 脚本。"
fi
echo ""

echo "════════════════════════════════════════════"
echo " 结果：$PASS 项通过，$FAIL 项未通过"
if [ "$FAIL" -eq 0 ]; then
  echo " 🎉 隔离配置完好（登录态最终请以实际登录第二个账号为准）"
else
  echo " 🔧 修复建议：重跑 bash scripts/setup-codebuddy-cn-2.sh --force"
fi
echo "════════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then exit 0; else exit 1; fi
