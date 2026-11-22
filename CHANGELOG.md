# Changelog

## 1.0.1 — 2026-11-22

- 新增菜单「检查更新…」：手动请求 GitHub Releases API，显示是否有新版本并打开发布页
- CI GitHub Actions 升级到 Node 24 版本（checkout@v5、upload-artifact@v5）
- 更新隐私说明：仅手动检查更新时访问 GitHub，不做后台轮询

## 1.0.0 — 2026-11-22

首个公开版本。

### 功能

- 插电时保持屏幕常亮、不自动锁屏
- 插电时合盖后继续运行（`pmset -a disablesleep 1`）
- 拔电后自动恢复系统睡眠与屏幕保护设置
- 菜单栏状态与开关
- 首次启动引导、管理员授权安装后台助手
- 登录时自动启动
- 诊断信息
- 一键卸载并恢复系统设置
- 从旧版原型（`local.powerlock` LaunchAgent）自动迁移并清理

### 工程

- 单 App 架构：菜单栏 App + 随 App 安装的 root 助手
- IOKit 电源通知，无轮询
- universal 构建脚本、GitHub Actions、Homebrew Cask 模板
- 助手状态机冒烟测试（mock pmset）

### 已知限制

- 未做代码签名/公证：首次打开需要在「隐私与安全性」中放行
- 界面目前为中文（英文 README 摘要），多语言在 v1.1
- 仅跟随当前控制台用户，多用户同时使用未支持
- 无自动更新
- 无系统通知（本地签名限制，v1 不依赖）
- 插电保持不锁屏意味着屏幕常亮
