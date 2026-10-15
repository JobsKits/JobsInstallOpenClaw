#!/bin/zsh
# 脚本自述：
# - 脚本名称：install@OpenClaw.command
# - 核心用途：执行“install@OpenClaw”对应的快捷打开任务。
# - 影响范围：主要影响应用启动与路径跳转，不主动改写业务文件。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
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
# 展示脚本内置自述，并等待用户确认后执行。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：install@OpenClaw.command' | jobs_intro_style title
  print -r -- '核心用途：执行“install@OpenClaw”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
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
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_install_or_exit
    return 0
  fi
  if ! jobs_brew_find >/dev/null; then
    jobs_brew_install_or_exit
  else
    jobs_brew_install_or_exit
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
  show_script_intro_and_wait
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
