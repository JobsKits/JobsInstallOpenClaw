#!/bin/bash

set -u
set -o pipefail

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

OPENCLAW_REPO_PATH=""
TOTAL_STEPS=8

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
gray_echo()      { log "\033[0;90m$1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }

print_logo() {
  info_echo "======================="
  info_echo "     Jobs Installer    "
  info_echo "======================="
}

pause_for_enter() {
  read -r -p "按回车开始安装..."
}

show_step() {
  echo
  highlight_echo "[$1/$TOTAL_STEPS] $2"
}

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

ensure_basic_tools() {
  for cmd in git curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error_echo "缺少基础命令：$cmd"
      gray_echo "请先安装：xcode-select --install"
      exit 1
    fi
  done
}

normalize_path() {
  local p="$1"
  p="${p#\'}"; p="${p%\'}"
  p="${p#\"}"; p="${p%\"}"
  printf '%b' "$p"
}

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

install_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    retry_run "安装 Homebrew" 2 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      error_echo "Homebrew 安装失败"
      exit 1
    }
  else
    echo "👉 回车升级 brew，输入任意字符跳过"
    read -r c
    if [[ -z "$c" ]]; then
      brew update && brew upgrade && brew cleanup
    fi
  fi
}

brew_install_if_needed() {
  brew list "$1" >/dev/null 2>&1 && { success_echo "$1 已安装"; return; }
  retry_run "安装 $1" 2 brew install "$1" || exit 1
}

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

install_cli() {
  retry_run "安装 openclaw CLI" 2 npm install -g openclaw || exit 1
}

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

launch_dashboard() {
  if ! openclaw dashboard; then
    warn_echo "dashboard 启动失败"
    gray_echo "你可以手动运行：openclaw dashboard"
  fi
}

summary() {
  echo
  bold_echo "====== 安装完成 ======"
  success_echo "openclaw 已安装完成"
  gray_echo "日志：$LOG_FILE"
}

main() {
  : > "$LOG_FILE"

  print_logo
  ensure_basic_tools
  pause_for_enter

  show_step 1 "校验仓库"
  ask_repo

  show_step 2 "检查 Homebrew"
  install_homebrew

  show_step 3 "安装 Node"
  brew_install_if_needed node

  show_step 4 "安装 pnpm"
  brew_install_if_needed pnpm

  show_step 5 "构建 openclaw"
  run_build

  show_step 6 "安装 CLI"
  install_cli

  show_step 7 "修复 PATH"
  fix_path_if_needed

  show_step 8 "启动 dashboard"
  launch_dashboard

  summary
}

main "$@"
