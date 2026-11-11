# Changelog

本项目迭代记录。所有改动均遵循「主 app 全程只读，只改克隆副本」铁律。

## v1.0.0 (2026-11-10)

首个版本，参考 [ccccplus/workbuddy-multi-instance](https://github.com/ccccplus/workbuddy-multi-instance) 思路，适配 CodeBuddy CN 4.x（VS Code fork 架构）。

### 新增

- `scripts/setup-codebuddy-cn-2.sh`：一键部署/修复/升级脚本（克隆 → 改 Info.plist → 改 product.json → 重签名 → 数据目录 → 注册 → 自检 → 启动），支持 `--no-launch` / `--force`
- `scripts/verify-isolation.sh`：隔离自检脚本（6 组检查）
- `README.md`：原理、隔离地图、快速开始、验证、升级回滚、风险免责
- `docs/troubleshooting.md`：踩坑复盘（架构差异、CFBundleName、登录态定位等）
- `AGENT.md`：AI 操作员执行手册

### 验证版本

- CodeBuddy CN **4.12.4**（四层隔离字段均已从源码与文件系统实锤定位）

### 与 WorkBuddy 方案的差异

| 项 | WorkBuddy 5.x | CodeBuddy CN 4.x |
| --- | --- | --- |
| 扩展层数据隔离 | `WORKBUDDY_CONFIG_DIR` | `CODEBUDDY_CONFIG_DIR` |
| 登录态隔离 | `authentication.id`（共享 auth 文件） | `nameShort` / `nameLong`（Electron Session Storage 目录名） |
| VS Code 用户数据 | 无 | `dataFolderName` |
| 偏好/缓存 | `darwinBundleIdentifier` + `productName` | `darwinBundleIdentifier`（无 `productName` 字段） |
