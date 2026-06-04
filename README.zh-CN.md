# SleepGuard

[English](README.md) | 简体中文

SleepGuard 是一个 macOS 菜单栏应用，用于排查 Mac 无法自动休眠、频繁被唤醒或被外设持续阻止睡眠的问题。应用会读取系统 `pmset` 输出，解析进程断言、USB/内核断言和睡眠日志，并给出风险分级与处理建议。

## 界面截图

|  |  |  |  |
| --- | --- | --- | --- |
| <img src="Screenshot/1.png" alt="SleepGuard screenshot 1" width="220"> | <img src="Screenshot/2.png" alt="SleepGuard screenshot 2" width="220"> | <img src="Screenshot/3.png" alt="SleepGuard screenshot 3" width="220"> | <img src="Screenshot/4.png" alt="SleepGuard screenshot 4" width="220"> |

## 功能特性

- 菜单栏常驻：通过菜单栏图标快速查看当前休眠风险状态。
- 当前状态诊断：解析 `pmset -g assertions`，识别阻止休眠的进程、断言类型、持续时间和原因。
- 风险分级：将常见阻止项分为正常、注意、严重和 USB 注意，优先标出需要处理的问题。
- USB 与内核断言排查：提示扩展坞、Hub、鼠标接收器、转接器等外设可能造成的睡眠影响。
- 睡眠日志摘要：读取最近睡眠、唤醒、DarkWake 和 Wake reason 记录，辅助判断是否存在异常唤醒。
- 历史记录与趋势：保存最近 200 次诊断记录，并展示阻止项连续出现的次数与持续时间。
- 忽略规则：可忽略已知正常的进程或外设断言，避免影响整体判断。
- 诊断报告：一键复制包含状态、原始断言、趋势和建议的文本报告。
- 自动刷新与登录启动：支持设置刷新间隔，并可开启登录时启动。

## 系统要求

- macOS 13.0 或更高版本
- Xcode 15 或更高版本
- Swift 5

## 使用方式

1. 使用 Xcode 打开 `SleepGuard.xcodeproj`。
2. 选择 `SleepGuard` scheme。
3. 构建并运行应用。
4. 在菜单栏点击 SleepGuard 图标查看诊断结果。

应用不会主动终止进程，也不会修改系统电源设置。所有诊断基于本机命令输出和本地历史记录。

## 命令行构建

```sh
xcodebuild -project SleepGuard.xcodeproj -scheme SleepGuard -configuration Debug build
```

## 运行测试

```sh
xcodebuild test -project SleepGuard.xcodeproj -scheme SleepGuard -destination 'platform=macOS'
```

测试覆盖了 `pmset` 断言解析、风险分类、报告生成、趋势分析、忽略规则和设置持久化等核心逻辑。

## 数据与隐私

SleepGuard 只在本机运行诊断，不上传数据。

- 休眠断言来自 `/usr/bin/pmset -g assertions`。
- 睡眠日志来自 `/usr/bin/pmset -g log` 的本地输出筛选。
- 历史记录保存在用户目录的 Application Support 下：`SleepGuard/history.json`。
- 刷新间隔和忽略规则保存在 `UserDefaults`。
- 复制报告时，报告内容会写入系统剪贴板。

## 风险判断说明

SleepGuard 会根据断言类型、持续时间、进程名称和原因文本进行启发式判断。例如：

- `PreventSystemSleep` 和 `InternalPreventSleep` 通常视为严重。
- 长时间存在的 `PreventUserIdleSystemSleep` 会被提升为严重。
- 音频、备份、接力、蓝牙等常见系统活动通常先标记为注意。
- `powerd` 在屏幕亮起时阻止空闲睡眠通常属于正常行为。
- USB 内核断言会提示逐个排查扩展坞、Hub、接收器或转接器。

这些判断用于辅助定位问题，不替代系统日志的完整人工分析。

## 项目结构

```text
SleepGuard/
  SleepGuardApp.swift              # 菜单栏应用入口
  Models/                          # 诊断、断言、历史和日志模型
  ViewModels/                       # 应用状态、刷新流程和用户操作
  Views/                            # SwiftUI 菜单栏窗口界面
  Services/                         # pmset 调用、解析、分析、报告和持久化
SleepGuardTests/
  SleepGuardTests.swift             # 核心单元测试
SleepGuard.xcodeproj/               # Xcode 项目
```

## 常见排查流程

1. 点击刷新，查看整体状态是否为“严重”或“注意”。
2. 优先处理红色严重项目，手动退出对应应用或关闭相关后台登录项。
3. 如果出现 USB / 内核断言，先拔掉扩展坞、Hub、鼠标接收器或转接器，再逐个接回确认来源。
4. 查看“睡眠日志”，确认昨晚是否有睡眠记录，以及是否存在蓝牙、USB、网络相关唤醒迹象。
5. 对确认无害的项目使用忽略功能，后续诊断将不再把它计入整体状态。

## License

本项目使用 [LICENSE](LICENSE) 中声明的许可证。
