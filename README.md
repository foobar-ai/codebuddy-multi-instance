# CodeBuddy CN Mac 多实例

在 macOS 上把 `/Applications/CodeBuddy CN.app` 克隆为一个完全隔离的第二实例「CodeBuddy CN 2.app」，实现**双账号、双数据目录、双登录态**并行使用。

- 零二进制修改，纯配置隔离，随时可回退
- 主 app `/Applications/CodeBuddy CN.app` 全程只读，绝不修改
- 思路参考 [ccccplus/workbuddy-multi-instance](https://github.com/ccccplus/workbuddy-multi-instance)，并针对 CodeBuddy CN 4.x（VS Code fork 架构）做适配

> ⚠️ 已在 **CodeBuddy CN 4.12.4** 上验证。其他 4.x 版本预期兼容，但未逐一验证。

---

## 原理

CodeBuddy CN 是标准 VS Code fork，数据分散在四层。多实例隔离 = 把这四层各自的「名字」改到副本专属，各写各的：

| 层 | 主实例 | 副本 | 隔离手段 |
| --- | --- | --- | --- |
| 扩展层数据 | `~/.codebuddy` | `~/.codebuddy-2` | 环境变量 `CODEBUDDY_CONFIG_DIR` |
| VS Code 用户数据 | `~/.codebuddycn` | `~/.codebuddycn2` | `product.json.dataFolderName` |
| Electron 会话层（登录态） | `~/Library/Application Support/CodeBuddy CN` | `~/Library/Application Support/CodeBuddy CN 2` | `product.json.nameShort` / `nameLong` |
| 偏好 / 更新缓存 | `com.tencent.codebuddycn` | `com.tencent.codebuddycn.alt2` | `product.json.darwinBundleIdentifier` + `CFBundleIdentifier` |

其中**登录态**（登录 cookie / 会话）落在 Electron 会话层的 `Session Storage` 里，目录名由 `product.json.nameShort` 决定——这是本方案与 WorkBuddy 方案最本质的区别（WorkBuddy 5.x 靠 `authentication.id` 共享 auth 文件区分，CodeBuddy CN 4.x 没有这个字段）。

---

## 快速开始

```bash
# 一键部署（克隆 + 改配置 + 重签名 + 数据目录 + 注册 + 启动）
bash scripts/setup-codebuddy-cn-2.sh

# 只部署不启动
bash scripts/setup-codebuddy-cn-2.sh --no-launch

# 隔离自检
bash scripts/verify-isolation.sh
```

首次启动副本后，请在「CodeBuddy CN 2」窗口里**登录第二个账号**。

---

## 验证方法

1. 两个 Dock 图标并存：`CodeBuddy CN` 与 `CodeBuddy CN 2`
2. 运行 `bash scripts/verify-isolation.sh`，看是否 `🎉 隔离配置完好`
3. 终极测试：在副本里登出 → 观察主实例是否仍在登录状态。主实例纹丝不动 = 成功。

诊断登录态是否真正分离：

```bash
# 副本进程实际从哪个 app 加载（应指向 CodeBuddy CN 2.app，而非主实例缓存）
lsof -p <副本pid> | grep "CodeBuddy CN 2.app"

# 两个独立的 Electron 会话目录
ls -d "$HOME/Library/Application Support/CodeBuddy CN"* 
```

---

## 升级与回滚

- **副本不参与官方自动更新**。主 app 升级后，重跑一次部署脚本即可同步新版本（约 1 分钟）：
  ```bash
  bash scripts/setup-codebuddy-cn-2.sh
  ```
- 数据目录 `~/.codebuddy-2`、`~/.codebuddycn2` 完全不受影响，登录态 / 技能 / 插件 / 记忆全部保留。

**回滚**（删掉副本即可，主实例零影响）：

```bash
# 关闭副本
ps aux | grep -E 'CodeBuddy CN 2\.app/Contents' | grep -v grep | awk '{print $2}' | while read p; do kill "$p"; done
# 删除程序副本
rm -rf "/Applications/CodeBuddy CN 2.app"
# 数据目录（含副本登录态，确认后再删）
# rm -rf ~/.codebuddy-2 ~/.codebuddycn2
```

---

## 风险与免责

1. 本质上是「两台不同的设备」，副本拥有独立设备标识与登录态
2. 属于软件未承诺的使用方式，账号风控、数据丢失等风险由使用者自行承担
3. 请遵守 CodeBuddy 软件许可协议与服务条款
4. 本项目仅供学习研究 macOS 应用机制

---

## 目录结构

```
codebuddy-multi-instance/
├── scripts/
│   ├── setup-codebuddy-cn-2.sh   # 一键部署/修复/升级
│   └── verify-isolation.sh       # 隔离自检（6 组）
├── docs/
│   └── troubleshooting.md        # 踩坑复盘
├── AGENT.md                      # AI 操作员执行手册
├── CHANGELOG.md
├── LICENSE                       # Apache-2.0
└── README.md
```

---

## License

[Apache-2.0](./LICENSE) © foobar-ai

