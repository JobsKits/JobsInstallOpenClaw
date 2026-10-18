# <span id="前言">🦞[**OpenClaw**](https://github.com/openclaw/openclaw)安装脚本</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

[实际目录结构](#repository-layout) · [安装入口流程](#repository-script-flows)

## 🔥 <font id=Features>Features</font> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 交互式安装流程，支持彩色日志与步骤提示
- 强校验本地  [**OpenClaw**](https://github.com/openclaw/openclaw) 仓库目录及 **Git** 远端
- 自动检测并安装 [**Homebrew**](https://brew.sh/)
- 支持可选执行 `brew update / upgrade / cleanup`
- 使用 `brew install node` 与 `brew install pnpm`
- 已安装依赖自动跳过，避免重复升级
- 自动执行  [**OpenClaw**](https://github.com/openclaw/openclaw) 官方构建与 **daemon** 安装流程
- 全局安装 `openclaw` **CLI**
- 安装后自动检测命令可用性，必要时自动修复 **PATH**
- 自动启动 `openclaw dashboard`
- 关键步骤支持失败自动重试
- 全流程输出日志，便于排障

## 一、脚本作用 <a href="#Features" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a>

这是一个面向 **macOS** 的 [**OpenClaw**](https://github.com/openclaw/openclaw) 一键安装脚本，目标是把本地仓库校验、依赖准备、项目构建、**CLI** 安装、**PATH** 修复和 **Dashboard** 启动串成一条完整安装链路

## 二、流程图 <a href="#Features" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a>

```mermaid
graph TD
    A([开始]) --> B[打印Logo并检查基础工具]
    B --> C{用户按回车开始安装?}
    C --> |是| D[校验OpenClaw仓库]
    C --> |否| B
    D --> E{仓库路径有效且为官方仓库?}
    E --> |是| F[检查并安装Homebrew]
    E --> |否| D
    F --> G[安装Node.js和pnpm]
    G --> H[构建OpenClaw项目]
    H --> I{构建和Daemon安装成功?}
    I --> |是| J[安装OpenClaw CLI并修复PATH]
    I --> |否| K([结束])
    J --> L[启动Dashboard并显示总结]
    L --> M([结束])
```

## 三、核心流程 <a href="#Features" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a>

### 1. 启动引导 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 脚本启动后先显示安装说明
- 等待用户按回车后再开始
- 全程带彩色日志和步骤提示

### 2. 仓库路径校验 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 要求用户拖入本地 `openclaw` 仓库目录
- 自动判断该目录是否为 **Git** 仓库
- 自动检查 `origin` 是否指向官方仓库`https://github.com/openclaw/openclaw`
- 路径错误时会循环提示，直到输入正确

### 3、[**Homebrew**](https://brew.sh/) 自检与处理 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 已有 Homebrew 时保留原有维护交互，不因目录只读而自动另装。
- [**Homebrew**](https://brew.sh/) 安装路径由用户选择：已有可运行安装时复用；确实需要安装时先强提示，只有精确输入大写 `YES` 才选择系统标准目录，其它输入或直接回车选择当前用户的 `.local/homebrew`。`YES` 只表示选择路径，权限与密码由官方安装器实际处理；有管理员权限也可以选用户目录。选定路径失败立即停止，不自动切换；`Ctrl+C` / 输入结束取消整个任务。
- 用户目录安装需要可用 Git 与 curl；后续系统级软件仍可能要求管理员权限。

### 4. 依赖安装策略 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 使用 `brew install node` 安装 **Node.js**，而不是单独安装 [**npm**](https://www.npmjs.com/)
- 使用 `brew install pnpm` 安装 [**pnpm**](https://pnpm.io/)
- 若 `node` 或 `pnpm` 已存在，则直接跳过，不重复升级。这样避免和前面的 `brew upgrade` 逻辑重复

### 5、官方构建流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

> 进入本地 [**OpenClaw**](https://github.com/openclaw/openclaw) 仓库后，依次执行：

```shell
pnpm install
pnpm ui:build
pnpm build
pnpm openclaw onboard --install-daemon
```

其中 `pnpm openclaw onboard --install-daemon` 会单独提示，因为它是最容易受系统权限影响的一步。

### 6. CLI 安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 使用 `npm install -g openclaw` 全局安装 [**OpenClaw**](https://github.com/openclaw/openclaw)  **CLI**

### 7. PATH 自动修复 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 安装完成后先检测 `openclaw` 命令是否可用
- 如果已经可用，则不修改 **PATH**
- 如果不可用，则自动将 [**npm**](https://www.npmjs.com/) 全局 **bin** 目录写入 shell 配置文件
- 这是兜底方案，避免用户安装完成后仍然 `command not found`

### 8. 启动 Dashboard <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 最后自动执行：`openclaw dashboard`

- 若启动失败，会给出手动执行提示

## 四、<span id="repository-layout">实际目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
🦞JobsInstallOpenClaw/
├── README.md / LICENSE / icon.png
└── install@OpenClaw.command                # 在已有官方源码目录上安装构建
```

## 五、<span id="repository-script-flows">安装入口流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### [install@OpenClaw.command](./install@OpenClaw.command)

> **目的：** 在本地已下载的 OpenClaw 官方源码上准备依赖、构建并打开 Dashboard。

* 阅读自述，输入或拖入已下载的 OpenClaw 仓库目录，校验 `.git` 目录和官方 origin 地址。
* 检测 Homebrew、Node.js 和 pnpm，按提示安装或更新需要的依赖。
  * 已有依赖可复用；本脚本不负责自动克隆 OpenClaw 源码。
* 依次执行依赖安装、界面构建和主程序构建；关键步骤失败时按设定次数重试。
* 运行 onboarding 并安装 daemon，再通过 npm 安装全局 OpenClaw 命令。
* 检查命令路径并尝试打开 Dashboard，汇总结果。
  * 命令不在 PATH 时补 npm 全局路径；Dashboard 启动失败时给出手动执行提示。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

