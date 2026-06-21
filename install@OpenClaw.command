#!/bin/zsh
# 脚本自述：
# - 脚本名称：install@OpenClaw.command
# - 核心用途：执行“install@OpenClaw”对应的快捷打开任务。
# - 影响范围：主要影响应用启动与路径跳转，不主动改写业务文件。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

OPENCLAW_REPO_PATH=""
TOTAL_STEPS=8
# 统一输出终端信息并同步记录日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 输出 info echo 对应级别的日志信息。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 输出 success echo 对应级别的日志信息。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 输出 note echo 对应级别的日志信息。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 输出 error echo 对应级别的日志信息。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 输出 highlight echo 对应级别的日志信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 输出 gray echo 对应级别的日志信息。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 输出 bold echo 对应级别的日志信息。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 输出 print logo 对应的说明与结果。
print_logo() {
  info_echo "======================="
  info_echo "     Jobs Installer    "
  info_echo "======================="
}
# 封装 pause for enter 对应的独立处理逻辑。
pause_for_enter() {
  read -r "?按回车开始安装..." _
}
# 展示同目录 README，并等待用户确认后执行。
show_readme_and_wait() {
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：install@OpenClaw.command'
  print -r -- '核心用途：执行“install@OpenClaw”对应的自动化任务。'
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  local readme_path="${SCRIPT_DIR}/README.md"
  [[ -f "$readme_path" ]] || { error_echo "未找到配套 README.md：$readme_path"; return 1; }
  cat "$readme_path" | tee -a "$LOG_FILE"
  echo ""
  read -r "?👉 已阅读 README，按回车继续；按 Ctrl+C 取消：" _
}
# 输出 show step 对应的说明与结果。
show_step() {
  echo
  highlight_echo "[$1/$TOTAL_STEPS] $2"
}
# 封装 retry run 对应的独立处理逻辑。
retry_run() {
  local desc="$1"; local retries="$2"; shift 2
  local i=1
  while (( i <= retries )); do
    info_echo "$desc（第 $i/$retries 次）"
    "$@" && { success_echo "$desc 成功"; return 0; }
    warn_echo "$desc 失败"
    ((i++))
    sleep 1
  done
  return 1
}
# 检查 ensure basic tools 所需条件，不满足时阻止继续执行。
ensure_basic_tools() {
  for cmd in git curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error_echo "缺少基础命令：$cmd"
      gray_echo "请先安装：xcode-select --install"
      exit 1
    fi
  done
}
# 封装 normalize path 对应的独立处理逻辑。
normalize_path() {
  local p="$1"
  p="${p#\'}"; p="${p%\'}"
  p="${p#\"}"; p="${p%\"}"
  printf '%b' "$p"
}
# 收集并校验 ask repo 对应的用户确认。
ask_repo() {
  while true; do
    echo
    bold_echo "拖入 openclaw 仓库目录后回车："
    read -r input
    local p=$(normalize_path "$input")

    [[ -d "$p/.git" ]] || { warn_echo "不是 Git 仓库"; continue; }

    local remote=$(git -C "$p" remote get-url origin 2>/dev/null)
    if [[ "$remote" != *"openclaw/openclaw"* ]]; then
      warn_echo "不是 openclaw 官方仓库"
      gray_echo "检测到：$remote"
      continue
    fi

    OPENCLAW_REPO_PATH="$p"
    success_echo "仓库 OK"
    break
  done
}
# 准备并配置 install homebrew 对应的运行条件。
install_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    retry_run "安装 Homebrew" 2 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      error_echo "Homebrew 安装失败"
      exit 1
    }
  else
    echo "👉 回车跳过升级 Homebrew，输入任意字符则升级"
    read -r c
    if [[ -n "$c" ]]; then
      brew update && brew upgrade && brew cleanup
    else
      gray_echo "已跳过 Homebrew 升级"
    fi
  fi
}
# 封装 brew install if needed 对应的独立处理逻辑。
brew_install_if_needed() {
  brew list "$1" >/dev/null 2>&1 && { success_echo "$1 已安装"; return; }
  retry_run "安装 $1" 2 brew install "$1" || exit 1
}
# 执行 run build 对应的独立业务步骤。
run_build() {
  cd "$OPENCLAW_REPO_PATH" || exit 1

  retry_run "pnpm install" 2 pnpm install || exit 1
  retry_run "pnpm ui:build" 2 pnpm ui:build || exit 1
  retry_run "pnpm build" 2 pnpm build || exit 1

  note_echo "正在安装 daemon（可能需要系统权限）"
  retry_run "daemon 安装" 2 pnpm openclaw onboard --install-daemon || {
    error_echo "daemon 安装失败"
    gray_echo "可能原因："
    gray_echo "- 系统权限未授权"
    gray_echo "- 后台服务安装失败"
    gray_echo "- 构建未完全成功"
    exit 1
  }
}
# 准备并配置 install cli 对应的运行条件。
install_cli() {
  retry_run "安装 openclaw CLI" 2 npm install -g openclaw || exit 1
}
# 封装 fix path if needed 对应的独立处理逻辑。
fix_path_if_needed() {
  if command -v openclaw >/dev/null; then
    success_echo "openclaw 命令可用"
    return
  fi

  warn_echo "openclaw 未在 PATH 中，自动修复"

  local bin="$(npm config get prefix)/bin"
  echo "export PATH=\"$bin:\$PATH\"" >> ~/.zprofile
  export PATH="$bin:$PATH"

  success_echo "已写入 PATH"

  echo
  note_echo "建议重新打开终端以确保环境完全生效"
}
# 封装 launch dashboard 对应的独立处理逻辑。
launch_dashboard() {
  if ! openclaw dashboard; then
    warn_echo "dashboard 启动失败"
    gray_echo "你可以手动运行：openclaw dashboard"
  fi
}
# 封装 summary 对应的独立处理逻辑。
summary() {
  echo
  bold_echo "====== 安装完成 ======"
  success_echo "openclaw 已安装完成"
  gray_echo "日志：$LOG_FILE"
}
# 编排脚本的高层业务流程。
# 初始化本次安装使用的日志文件。
initialize_install_log() {
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -u
  set -o pipefail
  setopt NO_NOMATCH
}
# 编排脚本的高层业务流程。
main() {
  # 展示配套 README，确认安装影响范围后继续。
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 清空旧日志，确保本次安装记录独立可查。
  initialize_install_log
  # 输出安装器标识，明确当前执行入口。
  print_logo
  # 检查 Git、curl 等基础命令是否可用。
  ensure_basic_tools
  # 在进入安装步骤前再次等待用户确认。
  pause_for_enter

  # 第 1 步：校验并选择 OpenClaw 仓库路径。
  show_step 1 "校验仓库"
  # 收集需要构建的 OpenClaw 仓库路径。
  ask_repo

  # 第 2 步：检查并准备 Homebrew。
  show_step 2 "检查 Homebrew"
  # 安装缺失的 Homebrew，已有环境按脚本策略处理。
  install_homebrew

  # 第 3 步：准备 Node.js 运行环境。
  show_step 3 "安装 Node"
  # 仅在缺失时安装 Node.js。
  brew_install_if_needed node

  # 第 4 步：准备 pnpm 包管理器。
  show_step 4 "安装 pnpm"
  # 仅在缺失时安装 pnpm。
  brew_install_if_needed pnpm

  # 第 5 步：构建 OpenClaw 工程。
  show_step 5 "构建 openclaw"
  # 执行仓库定义的构建命令。
  run_build

  # 第 6 步：安装 OpenClaw CLI。
  show_step 6 "安装 CLI"
  # 将构建结果安装为可调用的命令行工具。
  install_cli

  # 第 7 步：检查并修复命令搜索路径。
  show_step 7 "修复 PATH"
  # 仅在需要时写入 OpenClaw CLI 路径。
  fix_path_if_needed

  # 第 8 步：启动 OpenClaw Dashboard。
  show_step 8 "启动 dashboard"
  # 打开安装后的 Dashboard 管理界面。
  launch_dashboard

  # 输出安装结果和日志位置摘要。
  summary
}

main "$@"
