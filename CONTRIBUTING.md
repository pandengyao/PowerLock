# Contributing

感谢参与 PowerLock。

## 开发环境

- macOS 13+
- Xcode Command Line Tools（`xcode-select --install`）
- 不需要完整 Xcode，也不需要 Python/Pillow

## 构建与检查

```bash
./scripts/build.sh             # 构建 build/PowerLock.app
./scripts/check.sh             # 脚本语法 + plist + 构建 + CLI
./Tests/helper-test.sh         # 助手状态机测试（mock pmset / ioreg）
UNIVERSAL=1 ./scripts/build.sh # universal
```

## 代码约定

- Swift 5 语法（`-swift-version 5`），最低部署目标 macOS 13
- UI 文本使用中文；新增文案尽量简短、面向普通用户
- 助手脚本使用 zsh，`set -u`，只执行固定命令，不拼接用户输入
- 改了助手逻辑要把 `HELPER_VERSION` 加 1，并在 `Tests/helper-test.sh` 加用例
- 不要在用户没开启时修改系统设置；恢复设置时只恢复 PowerLock 自己改过的
- 不引入第三方运行时依赖；构建只依赖系统工具
- 不添加网络请求、分析或遥测

## 提交 PR

1. Fork 并创建分支
2. 说明改动动机与测试方式
3. 确保 `./scripts/check.sh` 与 `./Tests/helper-test.sh` 通过
4. 涉及助手/权限的改动，请在 PR 中说明安全影响

## 发布

见 [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md)。版本号以 `Resources/Info.plist` 为准，tag 必须与之一致。

## 安全问题

请勿在公开 Issue 中披露安全细节，见 [SECURITY.md](SECURITY.md)。
