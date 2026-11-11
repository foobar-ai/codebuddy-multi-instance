# AGENT.md —— AI 操作员执行手册：在 macOS 上部署 CodeBuddy CN 双开

> **给 AI 的话**：你是一位操作 macOS 的 AI 助手。用户要求在他的 Mac 上部署第二个 CodeBuddy CN 实例（双账号、数据隔离）。请严格按本手册执行：**先读「铁律」，再按阶段推进，每个阶段先检查、后动手、再验收**。本手册全程不修改主 app 的任何文件，所有动作可回滚。

用户可以这样把任务交给 AI：

> 请阅读并严格按照本项目的 AGENT.md 执行 CodeBuddy CN 双开部署。遇到与本手册冲突的情况，以本手册为准，并暂停向我确认。

---

## 铁律（违反任何一条立即停止）

1. **绝不修改主 app** `/Applications/CodeBuddy CN.app` 内的任何文件 —— 它只允许被读取（唯一操作是 `cp -R` 克隆）。
2. **绝不改副本的 `CFBundleName`**（必须保持 `CodeBuddy CN`）。改了会导致 `FATAL: Unable to find helper app`，Dock 有图标但永远无窗口，且无报错弹窗。只允许改 `CFBundleIdentifier` 和 `CFBundleDisplayName`。
3. **绝不拷贝身份类文件**到新数据目录 `~/.codebuddy-2`：`sessions/`、`memery/`、`traces/`、`app/`、`local_storage/`、`projects/`、`history.jsonl`、`user-state.json` 等。拷了 = 复制主实例身份 → 互踢或串号。只允许继承 `skills/`、`mcp.json`。
4. **绝不用 `pkill -f "CodeBuddy CN 2.app"`** —— 该模式会匹配到执行命令的 shell 自身并自杀。杀副本进程用精确路径匹配。
5. **绝不使用 `kill -9`** 杀副本，除非常规 `kill` 确认无效。
6. 所有破坏性动作（`rm -rf "$DST"`、覆盖文件）之前，先确认目标路径正确，并向用户口头说明。
7. 若用户的 CodeBuddy CN 版本明显不在 4.x 附近（`CFBundleShortVersionString`），先警告用户「未经此版本验证」，征得同意后再继续。

---

## 阶段 0 · 环境检查（只读）

```bash
# 0.1 操作系统
uname                            # 期望: Darwin
sw_vers -productVersion          # macOS 11+ 为佳（LSMinimumSystemVersion 11.0）

# 0.2 主 app 存在与版本
defaults read "/Applications/CodeBuddy CN.app/Contents/Info.plist" CFBundleShortVersionString
# 期望: 4.x（已验证 4.12.4）。若报错 = 未安装，终止并告知用户。

# 0.3 磁盘空间
df -h / | tail -1 | awk '{print $4}'
# 期望: 剩余 ≥ 5 GB（app 克隆 ~1GB + 运行时 + 余量）
```

**若 `/Applications/CodeBuddy CN 2.app` 已存在** → 这是修复/升级场景，直接跳到阶段 1 运行 setup 脚本即可（脚本自身处理旧副本）。

---

## 阶段 1 · 部署（一条命令完成）

```bash
bash scripts/setup-codebuddy-cn-2.sh --no-launch
```

脚本自动完成：关旧副本 → 克隆 → 改 Info.plist（Bundle ID / 显示名 / `CODEBUDDY_CONFIG_DIR`）→ 改 product.json 四字段 → 重签名 + 清隔离属性 → 准备数据目录 → 注册 LaunchServices → 内置自检。任一步自检不通过会立即报错停止。

---

## 阶段 2 · 验证

```bash
# 2.1 启动副本
open -a "/Applications/CodeBuddy CN 2.app"
sleep 15

# 2.2 双实例在场
lsappinfo list 2>/dev/null | grep -c 'com.tencent.codebuddycn.alt2'

# 2.3 副本从自己的 app 加载（关键验收）
PID=$(lsappinfo list 2>/dev/null | grep -B1 -A4 'com.tencent.codebuddycn.alt2' | grep -oE 'pid = [0-9]+' | head -1 | awk '{print $3}')
lsof -p "$PID" 2>/dev/null | grep -c "CodeBuddy CN 2.app"

# 2.4 全量自检
bash scripts/verify-isolation.sh
```

**无害告警**：端口 `EADDRINUSE`（端口自动顺延）、`[Splash] Skipped due to previous crash`。

---

## 阶段 3 · 用户操作（AI 只提示，不代劳）

1. 请用户在副本窗口**扫码登录第二个账号**。
2. 登录后验收 Electron 会话目录分离：
   ```bash
   ls -d "$HOME/Library/Application Support/CodeBuddy CN"*
   # 期望同时包含: CodeBuddy CN 与 CodeBuddy CN 2
   ```
3. 请用户做**终极测试**：在副本里登出 → 观察主实例是否仍在登录状态。主实例安坐不动 = 部署成功。

---

## 失败处理速查

| 现象 | 处置 |
| --- | --- |
| `open` 后 Dock 有图标、无窗口、日志不动 | 检查 `CFBundleName` 是否被误改 → 恢复为 `CodeBuddy CN`；无法恢复则重跑 setup 重建 |
| 副本直接是主账号登录态 | `nameShort` 未生效 → 重跑 setup，确认 `product.json.nameShort = CodeBuddy CN 2` |
| 报「已损坏」 | `xattr -cr "/Applications/CodeBuddy CN 2.app"` 再跑一次 |
| 副本秒退、`open` 无反应 | 曾被强杀：重跑 setup 脚本重建副本 |

## 回滚（用户要求撤销时）

```bash
PID=$(lsappinfo list 2>/dev/null | grep -B1 -A4 'com.tencent.codebuddycn.alt2' | grep -oE 'pid = [0-9]+' | head -1 | awk '{print $3}')
[ -n "$PID" ] && kill "$PID" && sleep 4
rm -rf "/Applications/CodeBuddy CN 2.app"   # 只删程序副本
# 数据目录 ~/.codebuddy-2 / ~/.codebuddycn2 含副本登录态 —— 先询问用户，确认后删除
```

主 app 与 `~/.codebuddy`、`~/.codebuddycn` 全程未被修改。

---

## 完工汇报模板

> ✅ CodeBuddy CN 双开部署完成：副本 v<版本> / Bundle ID `com.tencent.codebuddycn.alt2` / 数据目录 `~/.codebuddy-2`。
> 验证：双进程并存 ✓ / 副本从自身 app 加载 ✓ / 四层目录隔离 ✓。
> 请扫码登录第二个账号，并做一次「副本登出 → 主实例不动」的终极测试。
