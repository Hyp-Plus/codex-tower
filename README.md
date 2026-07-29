# Codex Tower

**在 macOS 菜单栏中，一眼掌握所有 Codex 任务。**

Codex Tower 是一款本地优先的 Codex 插件与原生菜单栏应用。它将正在进行、等待你处理和已完成的任务集中到一个轻量面板里，让你无需在多个对话之间来回寻找。

![Codex Tower dashboard showing active tasks](assets/dashboard.png)

## 它能做什么

- **任务总览**：按最新活动时间展示本地 Codex 任务，默认优先显示进行中的工作。
- **需要处理的提醒**：等待审批或等待查看的任务会被显著标记，并在菜单栏显示数量。
- **一键回到对话**：点击任务卡片即可打开对应的 Codex 对话。
- **筛选清晰**：在 Active、Attention、History 与全部任务之间快速切换；历史记录不会遮挡当前工作。
- **本地提示音**：任务需要注意或被显式标记为完成时，可播放 macOS 系统提示音；支持一键静音。
- **历史同步**：可导入已有的本地 Codex 对话作为只读历史卡片，不会猜测它们是否已完成。

## 隐私优先

Codex Tower 只保存本机任务元数据，例如标题、状态、更新时间、计划进度和子代理数量。

它**不会读取、保存或上传**对话正文、工具输出或其他敏感内容。数据默认存放在：

```text
~/Library/Application Support/Codex Tower
```

## 安装

1. 前往 [Releases](https://github.com/Hyp-Plus/codex-tower/releases) 下载最新版 `Codex Tower-*-macos-arm64.zip`。
2. 解压后将 `Codex Tower.app` 拖入「应用程序」。
3. 首次打开后，在 Codex 中安装并信任 Codex Tower 插件的 hooks。
4. 开始新的 Codex 任务，菜单栏应用便会自动显示任务状态。

> 目前支持 Apple Silicon Mac，要求 macOS 13 或更新版本。应用为本地构建、未公证版本；首次打开如被系统拦截，请在「应用程序」中右键选择“打开”。

## 工作方式

```text
Codex 生命周期 hooks  →  本地 JSON 元数据  →  Codex Tower 菜单栏面板
```

插件在任务状态变化时更新本地元数据；菜单栏应用每秒读取一次这些文件并刷新界面。整个过程不经过云端服务。

## 开发

```zsh
cd menu-bar-app
zsh build-app.sh
open "dist/Codex Tower.app"
```

项目包含三部分：

- `hooks/`：记录 Codex 任务生命周期。
- `server/`：提供本地任务查询、历史同步及通知设置。
- `menu-bar-app/`：原生 SwiftUI 菜单栏应用。

## 许可证与贡献

欢迎提交 issue 和 pull request。请先阅读代码及隐私边界，确保任何贡献都不会引入对对话内容的收集或上传。
