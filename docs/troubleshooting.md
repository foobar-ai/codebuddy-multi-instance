# 踩坑全记录

> 适用对象：CodeBuddy CN 4.12.4（VS Code fork 架构）真机适配双开
> 思路源自 [workbuddy-multi-instance/docs/troubleshooting.md](https://github.com/ccccplus/workbuddy-multi-instance/blob/main/docs/troubleshooting.md)，本文记录 CodeBuddy CN 4.x 与 WorkBuddy 5.x 的差异与适配后的新坑。

---

## 第一幕：架构差异 —— 三件套为什么不能用

WorkBuddy 5.x 的双开核心是改 `product.json` 三件套：

```
productName             → 钥匙串身份
darwinBundleIdentifier  → 更新缓存目录
authentication.id       → 共享 auth 会话文件名（同登同退真凶）
```

**CodeBuddy CN 4.x 的 `product.json` 里这三个字段根本不存在**：`productName` 缺失、`authentication` 为 `null`。原因是 4.x 是标准 VS Code fork，登录态不走 WorkBuddy 5.x 那套「全局共享 auth 文件」，而是分散在 VS Code 自己的 userData / sessionData 里。

实测证据链：

- 共享 auth 目录 `~/Library/Application Support/CodeBuddyExtension/Data/Public/auth` 里只有 WorkBuddy 的 `workbuddy-desktop*.info`，**没有任何 codebuddycn 的会话文件**
- `com.tencent.codebuddycn`、`CodeBuddy CN` 等目录下也无 `.info` 会话文件
- CodeBuddy CN 的 `~/.codebuddy` 数据目录里，`user-state.json` 只有 UI 状态、`settings.json` 只有用户设置，无 token

**结论**：CodeBuddy CN 的多实例隔离改用 VS Code 系自身的四层隔离（见 README 隔离地图）。

---

## 第二幕：四个关键字段是怎么定位出来的

### 坑 2.1 · 环境变量开关是 `CODEBUDDY_CONFIG_DIR` 不是 `WORKBUDDY_CONFIG_DIR`

在 `Resources/app/extensions/genie/out/extension/index.js` 里搜到实锤：

```js
ar.CODEBUDDY_CONFIG_DIR_ENV = "CODEBUDDY_CONFIG_DIR";
// codeBuddyHomeDir() { const ir = process.env[ar.CODEBUDDY_CONFIG_DIR_ENV]; ... }
```

它控制默认 `~/.codebuddy` 目录。照搬 WorkBuddy 的 `WORKBUDDY_CONFIG_DIR` 会完全无效，副本仍读写主实例的 `~/.codebuddy`。

### 坑 2.2 · `nameShort` 决定 Electron 会话目录（登录态所在地）

在 `Resources/app/out/main.js` 里搜到：

```js
userDataDir: tC(t, e.nameShort)   // Electron userData/sessionData 目录名来自 nameShort
```

macOS 上 `tC(...)` 落到 `~/Library/Application Support/<nameShort>`。所以 `nameShort` 从 `CodeBuddy CN` 改成 `CodeBuddy CN 2`，登录态（Session Storage）目录就变成 `Application Support/CodeBuddy CN 2`，实现真正的登录隔离。

⚠️ 只改 `dataFolderName`（`~/.codebuddycn`）不改 `nameShort`，扩展/argv 隔离了，但登录 cookie 仍共享，会出现「副本一打开就是主账号」。

### 坑 2.3 · `dataFolderName` 决定 VS Code 用户数据目录

```js
// argv.json 路径：Ae(this.userHome, this.productService.dataFolderName, "argv.json")
// extensions 路径：Ae(this.userHome, this.productService.dataFolderName, "extensions")
```

`dataFolderName` 从 `.codebuddycn` 改成 `.codebuddycn2`，extensions、argv.json、secret storage 整体搬家到 `~/.codebuddycn2`。

---

## 第三幕：头号坑 —— CFBundleName 是隐形杀手

### 坑 3.1 · CFBundleName 改了会 FATAL 但无弹窗

CodeBuddy CN 的 Helper 进程名是 `CodeBuddy CN Helper.app`（还有 GPU/Plugin/Renderer 三个）。Electron 按 `CFBundleName + " Helper"` 去 `Contents/Frameworks/` 找它们。

如果把 `CFBundleName` 改成 `CodeBuddy CN 2`，四个 Helper 全部失联，报 `FATAL:electron/shell/app/electron_main_delegate_mac.mm:65] Unable to find helper app`，表现为 Dock 有图标但永远无窗口、无报错弹窗。

**解法**：只改 `CFBundleIdentifier` 和 `CFBundleDisplayName`，`CFBundleName` 永远保持 `CodeBuddy CN`。Dock 显示名由 `CFBundleDisplayName` 决定。

> 这条对任何 Electron app 做副本都适用。

### 坑 3.2 · URL 协议竞争：网页唤起被导向副本

副本 Info.plist 克隆自主 app，两者都注册了同一个 `codebuddycn://` 协议（`CFBundleURLTypes`）。部署脚本 `lsregister -f -R` 把副本注册为最新注册者后，LaunchServices 会把该协议默认处理器切到副本——现象：在 CodeBuddy Web 点「CodeBuddy IDE」，浏览器弹「你要允许此网站打开 "CodeBuddy CN 2" 吗？」。

**解法**：从副本 Info.plist 删除协议注册，协议永远归主实例，副本只通过 Dock/手动打开使用：

```bash
plutil -remove CFBundleURLTypes "/Applications/CodeBuddy CN 2.app/Contents/Info.plist"
# 改了 Info.plist 必须重签名
codesign --force --deep --sign - "/Applications/CodeBuddy CN 2.app"
xattr -cr "/Applications/CodeBuddy CN 2.app"
# 让主实例重新接管协议
lsregister -f -R "/Applications/CodeBuddy CN.app"
```

setup 脚本已内置此步（克隆后立即 `plutil -remove CFBundleURLTypes`）。

### 坑 3.3 · LSEnvironment 合并而非覆盖

CodeBuddy CN 的 `Info.plist` 里 `LSEnvironment` 已有系统默认项 `MallocNanoZone=0`。用 `plutil -replace LSEnvironment -string ...` 整体覆盖会把它冲掉。

**解法**：用 `plutil -replace LSEnvironment.CODEBUDDY_CONFIG_DIR -string <path>` 只加一个键，系统默认项保留。

---

## 第四幕：codesign 与隔离属性

### 坑 4.1 · 改了 app 内任何文件都要重签名

`Info.plist`、`product.json` 只要动一个字节，签名就失效，macOS 报「已损坏，建议移到废纸篓」。

**解法**：ad-hoc 签名 + 清 quarantine/provenance 二连：

```bash
codesign --force --deep --sign - "/Applications/CodeBuddy CN 2.app"
xattr -cr "/Applications/CodeBuddy CN 2.app"
```

macOS 新版还会重新贴 `com.apple.provenance`，启动失败时先查属性再怀疑人生。

### 坑 4.2 · codesign 幽灵 `.cstemp`（继承自 WorkBuddy 的坑）

`codesign --deep` 可能给插件造出 `.cstemp` 临时文件写进封印后又删掉，导致严格校验报 `sealed resource missing`。**此瑕疵不影响启动**，能跑就别为签名洁癖折腾；强迫症则先删内层 `_CodeSignature` 再签。

---

## 第五幕：数据目录身份雷区

### 坑 5.1 · 只拷「无身份」内容

准备 `~/.codebuddy-2` 时，只继承：

```
~/.codebuddy/skills     # 技能（无账号身份）
~/.codebuddy/mcp.json   # MCP 配置（无账号身份）
```

以下一律**不拷**，否则等于复制主实例身份，会互踢/串号：

```
sessions/          # 会话
memery/            # 记忆
traces/            # 运行轨迹（含 uid）
app/               # 应用状态
local_storage/     # 本地存储
projects/          # 项目状态
history.jsonl      # 历史（含账号信息）
user-state.json    # 用户状态
settings.json      # 若含账号/设备相关项
```

### 坑 5.2 · 沙箱里的 TCC 假象

受限环境里 `ls` 共享目录可能返回空（TCC 拦截），实际文件都在。诊断时用 Python `os.listdir` 直读更可靠，别被假象带偏。

---

## 第六幕：验证登录态是否真分离

### 坑 6.0 · 钥匙串弹窗「CodeBuddy CN Safe Storage」是预期行为

副本首次启动会弹窗：「"CodeBuddy CN 2" 想要使用你存储在钥匙串的 "CodeBuddy CN Safe Storage" 中的机密信息」。

**原因**：登录凭据走 Chromium/Electron `safeStorage`——加密密钥存钥匙串，条目名由 `CFBundleName` 派生（`CodeBuddy CN Safe Storage`），而 `CFBundleName` 是铁律不能改的，所以副本与主实例共用同一个密钥条目。加密后的登录数据本体则存在各自独立的 userData 目录，互不串扰。

**处置**：点「**始终允许**」（把副本加入条目授权列表，避免每次启动重复弹窗）。点「允许」会因 ad-hoc 签名身份不稳定而反复弹窗；点「拒绝」会导致副本读不到密钥、登录态无法加密存储。

**注意**：重跑 setup 重建副本后二进制变化，钥匙串授权可能失效，需要再点一次「始终允许」。

**安全边界澄清**：钥匙串授权是**条目级**的，本次只授权 `CodeBuddy CN Safe Storage` 这一条，**不会**连带授权其他软件的条目（如 VS Code 的 `Code Safe Storage`、Cursor 的 `Cursor Safe Storage`——名字不同、ACL 独立）。副本能读到的只有这一段加密密钥（非明文凭据）。唯一固有限制是主/副本因 `CFBundleName` 相同而共用这一把加密钥匙：理论上副本进程具备解密主实例本地加密数据的「钥匙」，但副本只写自己的 userData、不主动解主实例数据，实际影响有限。

### 验证顺序

1. **看目录**：副本首次启动/登录后，是否生成
   - `~/Library/Application Support/CodeBuddy CN 2/Session Storage`
   - `~/.codebuddycn2`
2. **看进程**：`lsof -p <副本pid> | grep "CodeBuddy CN 2.app"` —— 应指向副本自身，而非主实例缓存
3. **终极测试**：副本登出 → 主实例是否仍登录。主实例纹丝不动 = 成功。

若副本仍显示主账号，按此顺序排查：

| 症状 | 原因 | 处置 |
| --- | --- | --- |
| 副本一打开就是主账号 | `nameShort` 未生效（Session Storage 仍共享） | 重跑 setup 脚本，确认 `product.json.nameShort = CodeBuddy CN 2` |
| 副本扩展/设置和主实例一样 | `dataFolderName` 或 `CODEBUDDY_CONFIG_DIR` 未生效 | 检查 `product.json.dataFolderName` 与 `LSEnvironment.CODEBUDDY_CONFIG_DIR` |
| 一边登出另一边掉线 | 登录态仍共享（大概率是 nameShort 没改对） | 同第 1 行 |
| 副本起不来 / Dock 有图标无窗口 | `CFBundleName` 被误改 | 恢复 `CFBundleName = CodeBuddy CN`，或重跑 setup 重建 |
| 报「已损坏」 | 隔离属性未清 | `xattr -cr "/Applications/CodeBuddy CN 2.app"` |

---

## 验证状态速记

| 项目 | 状态 |
| --- | --- |
| 双进程同时运行 | ✅ 实测（lsappinfo 确认 `com.tencent.codebuddycn` 与 `.alt2` 并存） |
| 独立 Dock 图标 | ✅ 实测（独立 bundleID + CFBundleDisplayName） |
| 四层数据目录隔离 | ✅ 实测（`~/.codebuddy-2` / `~/.codebuddycn2` / `Application Support/CodeBuddy CN 2` 均独立生成） |
| 双账号登录互不影响 | ⚠️ 结构已验证（登录态目录独立），待登录第二账号做终极测试 |
| 服务端风控 | 无法从客户端判断，风险自担 |

> **2026-11-10 实测（CodeBuddy CN 4.12.4）**：副本部署成功、自检 15 项全过、双进程并存、副本从 `CodeBuddy CN 2.app` 自身加载（lsof 实锤，23 个文件句柄指向副本）、四层目录全部独立生成。唯一待完成项：登录第二个账号后做「副本登出 → 主实例不动」终极测试，并确认副本 `Session Storage` 生成。
