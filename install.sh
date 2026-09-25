#!/usr/bin/env bash
# dotfiles install — zsh + starship 표준 셸 환경 부트스트랩
#
# 사용법:
#   git clone https://github.com/LeeYudok/dotfiles.git && cd dotfiles && ./install.sh
#
# 동작 (섹션 번호 = 아래 주석 번호 = README 단계 표):
#   0.   의존성 사전 검사 — 누락 시 홈 파일을 하나도 바꾸지 않고 종료. Git Bash/MSYS/Cygwin 은 지원하지 않음(WSL2 에서 실행)
#   1.   zsh / starship / 플러그인 / jq 설치 (없을 때만; macOS 는 eza·bat·zoxide 포함)
#   2.   starship.toml 배치 (~/.config/starship.toml)
#   2.5. Nerd Fonts 설치 (JetBrainsMono, D2Coding; 마커 파일로 재설치 방지)
#        WSL 에서는 건너뛰고 안내만 — 글리프는 Windows 쪽 터미널이 그리므로 폰트도 Windows 에 설치해야 한다
#   3.   OS 에 맞는 zshrc 배치 (~/.zshrc). 머신별 alias/함수는 ~/.zshrc.local (미추적, 이 스크립트가 만들지 않음)
#   4.   Claude Code statusline 스크립트 배치 (~/.claude/statusline-command.sh)
#        + settings.json 의 statusLine 키만 merge (python3, 원자적 쓰기)
#   5.   Codex CLI status line — ~/.codex/config.toml 의 [tui] status_line 키만 merge (codex/status-line.py)
#        + 비용 훅 배치 (~/.codex/cost-hook.py) 와 ~/.codex/hooks.json Stop 항목 하나만 merge (codex/hooks.py)
#        Codex 를 쓰는 머신(codex 명령 또는 ~/.codex 존재)에서만. 없으면 건너뜀
#   6.   Antigravity CLI(agy) statusline 스크립트 배치 (~/.gemini/antigravity-cli/statusline-command.sh)
#        + settings.json 의 statusLine 키만 merge (agy/settings.py). agy 명령 또는 ~/.gemini/antigravity-cli 가 있을 때만
#   7.   기본 셸이 zsh 가 아니면 chsh 안내
#
# 런타임 의존성: curl, unzip, python3 (0 단계에서 검사). macOS 는 Homebrew 필수. Windows 는 WSL2 안에서 실행.
#   jq 는 statusline 스크립트(Claude·Antigravity) 런타임 전용 — 1 단계에서 brew/dnf/apt 로 자동 설치 (sudo 불가 시 경고만).
# 멱등(idempotent): 재실행해도 안전하다. 배치 대상은 내용이 다를 때만 .bak 백업 후 덮어쓴다.
#
# 되돌리기: ./uninstall.sh — 최초 실행 시 ~/.config/dotfiles/backup/ 에 보관한 원본과 manifest 를 기준으로 복원한다.
#   - <name>.orig     : 덮어쓰기 전 원본 (최초 1회만 기록, 이후 실행은 갱신하지 않음)
#   - <name>.absent   : 원래 그 파일이 없었다는 표시
#   - brew-installed.txt / pkg-installed.txt / bin-installed.txt : 이 스크립트가 새로 설치한 것만 기록
#   - settings.json.orig : settings.json 설치 전 전체 내용 (없었으면 settings.json.absent)
#   - codex-config.toml.orig : ~/.codex/config.toml 설치 전 전체 내용 (없었으면 codex-config.toml.absent)
#   - codex-hooks.json.absent / .present : ~/.codex/hooks.json 설치 전 유무 (다른 도구와 공유하는 파일이라 내용은 기록하지 않음)
#   - agy-settings.json.orig : ~/.gemini/antigravity-cli/settings.json 설치 전 전체 내용 (없었으면 agy-settings.json.absent)

set -euo pipefail
cd "$(dirname "$0")"

OS="$(uname -s)"
info() { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[install] 오류:\033[0m %s\n' "$*" >&2; exit 1; }

# ── 0. 의존성 사전 검사 (홈 파일 변경 전) ────────────────────
# 여기서 실패하면 ~/.config/dotfiles/backup 을 포함해 아무것도 만들거나 바꾸지 않는다.
case "$OS" in
  MINGW*|MSYS*|CYGWIN*)
    die "Git Bash/MSYS/Cygwin 은 지원하지 않음 (zsh·패키지 매니저 없음) — WSL2 를 설치(wsl --install)하고 그 안에서 실행. WSL2 를 쓸 수 없는 폐쇄망은 windows\\install-git.cmd 로 Git Bash 환경만 구성 (홈 파일은 변경하지 않았음)" ;;
esac
missing=()
for cmd in curl unzip python3; do command -v "$cmd" >/dev/null || missing+=("$cmd"); done
if [ "$OS" = "Darwin" ]; then
  command -v brew >/dev/null || missing+=("brew (https://brew.sh)")
else
  command -v dnf >/dev/null || command -v apt-get >/dev/null || missing+=("dnf 또는 apt-get")
fi
if [ "${#missing[@]}" -gt 0 ]; then
  die "필수 명령 누락: ${missing[*]} — 설치 후 다시 실행 (홈 파일은 변경하지 않았음)"
fi
# settings.json 이 있는데 깨진 JSON 이면 4 단계에서 손댈 수 없으므로 시작 전에 막는다
if [ -f "$HOME/.claude/settings.json" ]; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$HOME/.claude/settings.json" 2>/dev/null \
    || die "$HOME/.claude/settings.json 이 올바른 JSON 이 아님 — 수동으로 고친 뒤 다시 실행 (홈 파일은 변경하지 않았음)"
fi
# ~/.codex/config.toml 이 깨진 TOML 이거나 [tui] 표기가 아니면 5 단계에서 손댈 수 없으므로 시작 전에 막는다
if [ -f "$HOME/.codex/config.toml" ]; then
  python3 codex/status-line.py check || die "$HOME/.codex/config.toml 을 편집할 수 없음 — 수동으로 고친 뒤 다시 실행 (홈 파일은 변경하지 않았음)"
fi
if [ -f "$HOME/.codex/hooks.json" ]; then
  python3 codex/hooks.py check || die "$HOME/.codex/hooks.json 을 편집할 수 없음 — 수동으로 고친 뒤 다시 실행 (홈 파일은 변경하지 않았음)"
fi
if [ -f "$HOME/.gemini/antigravity-cli/settings.json" ]; then
  python3 agy/settings.py check || die "$HOME/.gemini/antigravity-cli/settings.json 을 편집할 수 없음 — 수동으로 고친 뒤 다시 실행 (홈 파일은 변경하지 않았음)"
fi

# WSL 여부 — 커널 버전 문자열에 microsoft 가 들어 있다. DOTFILES_PROC_VERSION 은 시험용(다른 파일을 읽게 한다)
is_wsl() {
  local f="${DOTFILES_PROC_VERSION:-/proc/version}"
  [ "$OS" != "Darwin" ] && [ -r "$f" ] && grep -qi microsoft "$f"
}

BACKUP_DIR="$HOME/.config/dotfiles/backup"
# 이전 버전이 쓰던 ~/.dotfiles-backup 이 남아 있으면 새 위치로 옮긴다 (설치 전 원본 기록을 잃지 않도록)
if [ -d "$HOME/.dotfiles-backup" ] && [ ! -e "$BACKUP_DIR" ]; then
  mkdir -p "$(dirname "$BACKUP_DIR")" && mv "$HOME/.dotfiles-backup" "$BACKUP_DIR"
  info "~/.dotfiles-backup → $BACKUP_DIR 이동"
fi
mkdir -p "$BACKUP_DIR"

# 최초 실행 시에만 원본 상태를 기록 (있으면 .orig 로 복사, 없으면 .absent 마커)
preserve_original() {   # preserve_original <대상 경로> <기록 이름>
  local target="$1" name="$2"
  [ -e "$BACKUP_DIR/$name.orig" ] || [ -e "$BACKUP_DIR/$name.absent" ] && return 0
  if [ -f "$target" ]; then cp "$target" "$BACKUP_DIR/$name.orig"; else touch "$BACKUP_DIR/$name.absent"; fi
}

# 파일 배치: 원본 기록 → 내용 다르면 .bak 1세대 백업 → 복사
deploy_file() {         # deploy_file <원본(레포)> <대상(홈)> <기록 이름>
  local src="$1" dst="$2" name="$3"
  mkdir -p "$(dirname "$dst")"
  preserve_original "$dst" "$name"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    cp "$dst" "$dst.bak"
    info "기존 $(basename "$dst") → .bak 백업"
  fi
  cp "$src" "$dst"
}

# manifest 에 한 줄 추가 (중복 없이)
record() {              # record <manifest 파일명> <값>
  grep -qxF -- "$2" "$BACKUP_DIR/$1" 2>/dev/null || printf '%s\n' "$2" >> "$BACKUP_DIR/$1"
}

# ── 1. 패키지 설치 ──────────────────────────────────────────
if [ "$OS" = "Darwin" ]; then
  for pkg in starship eza bat zoxide fzf fd jq zsh-autosuggestions zsh-syntax-highlighting; do
    brew list "$pkg" >/dev/null 2>&1 || { info "brew install $pkg"; brew install "$pkg"; record brew-installed.txt "$pkg"; }
  done
else
  # Linux (RHEL/Rocky/Debian 계열 공통)
  command -v zsh >/dev/null || {
    info "zsh 설치"
    if command -v dnf >/dev/null; then sudo dnf install -y zsh
    elif command -v apt-get >/dev/null; then sudo apt-get install -y zsh
    else echo "지원하지 않는 패키지 매니저 — zsh 수동 설치 필요"; exit 1; fi
    record pkg-installed.txt zsh
  }
  command -v starship >/dev/null || {
    info "starship 설치 (공식 스크립트 → /usr/local/bin, sudo 불가 시 ~/.local/bin)"
    if sudo -n true 2>/dev/null; then
      curl -sS https://starship.rs/install.sh | sh -s -- -y
      record bin-installed.txt /usr/local/bin/starship
    else
      mkdir -p "$HOME/.local/bin"
      curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
      record bin-installed.txt "$HOME/.local/bin/starship"
    fi
  }
  if [ ! -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ] || [ ! -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    info "zsh-autosuggestions / zsh-syntax-highlighting 설치"
    if command -v dnf >/dev/null; then
      rpm -q epel-release >/dev/null 2>&1 || sudo dnf install -y epel-release || true
      { sudo dnf install -y zsh-autosuggestions zsh-syntax-highlighting && record pkg-installed.txt zsh-autosuggestions && record pkg-installed.txt zsh-syntax-highlighting; } \
        || info "경고: 자동완성 플러그인 설치 실패 (sudo/repo 확인 필요)"
    elif command -v apt-get >/dev/null; then
      { sudo apt-get install -y zsh-autosuggestions zsh-syntax-highlighting && record pkg-installed.txt zsh-autosuggestions && record pkg-installed.txt zsh-syntax-highlighting; } \
        || info "경고: 자동완성 플러그인 설치 실패 (sudo/repo 확인 필요)"
    fi
  fi
  # jq — statusline 런타임 전용. sudo 가 없으면 설치를 건너뛰고 경고만 (셸 환경 자체는 jq 없이도 동작)
  command -v jq >/dev/null || {
    if sudo -n true 2>/dev/null; then
      info "jq 설치"
      if command -v dnf >/dev/null; then sudo dnf install -y jq && record pkg-installed.txt jq
      else sudo apt-get install -y jq && record pkg-installed.txt jq; fi
    else
      info "경고: jq 없음 + sudo 불가 — Claude statusline 은 jq 설치 전까지 동작하지 않음 (dnf/apt install jq)"
    fi
  }
fi

# ── 2. starship.toml ───────────────────────────────────────
deploy_file starship/starship.toml "$HOME/.config/starship.toml" starship.toml
info "starship.toml 배치 완료"

# ── 2.5. Nerd Fonts (JetBrainsMono, D2Coding) ──────────────
if [ "$OS" = "Darwin" ]; then FONT_DIR="$HOME/Library/Fonts"; else FONT_DIR="$HOME/.local/share/fonts"; fi
install_nerd_font() {
  local name="$1"
  local marker="$FONT_DIR/.nerd-font-${name}-installed"
  if [ -f "$marker" ]; then
    return
  fi
  info "Nerd Font 설치: $name"
  local tmp; tmp="$(mktemp -d)"
  # 폰트는 부가 요소 — 다운로드/압축해제 실패 시 경고만 남기고 다음 단계로 진행 (마커 미생성 → 재실행 시 재시도).
  # trap RETURN 은 함수 밖으로 새어 이후 모든 함수 리턴에 발화하므로 쓰지 않고, 정리는 단일 지점에서 한 번만.
  # 설치한 파일명을 manifest(.nerd-font-<name>-files.txt) 에 남겨 uninstall.sh 가 정확히 그 파일만 지운다.
  local ok=1
  { curl -fsSL -o "$tmp/$name.zip" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$name.zip" \
      && unzip -oq "$tmp/$name.zip" -d "$tmp/$name" \
      && find "$tmp/$name" \( -iname "*.ttf" -o -iname "*.otf" \) -exec basename {} \; > "$FONT_DIR/.nerd-font-${name}-files.txt" \
      && find "$tmp/$name" \( -iname "*.ttf" -o -iname "*.otf" \) -exec cp {} "$FONT_DIR/" \; \
      && touch "$marker"; } || ok=0
  rm -rf "$tmp"
  [ "$ok" = 1 ] || info "경고: Nerd Font $name 다운로드/압축해제 실패 — 건너뜀 (네트워크·GitHub 릴리스 확인 후 재실행)"
}
if is_wsl; then
  # 글리프를 그리는 것은 Windows 쪽 터미널이다. WSL 안에 설치해도 효과가 없고, Windows 사용자 프로필은 $HOME 밖이라 자동 설치하지 않는다.
  info "WSL 감지 — Nerd Font 설치 건너뜀. Windows 에 JetBrainsMono Nerd Font(또는 D2Coding Nerd Font)를 설치하고 터미널 프로필의 글꼴로 지정 (README 'Windows (WSL2)' 절)"
else
  mkdir -p "$FONT_DIR"
  for font in JetBrainsMono D2Coding; do
    install_nerd_font "$font"
  done
  if [ "$OS" = "Darwin" ]; then
    info "Nerd Font 설치 완료 (Font Book 자동 등록)"
  else
    command -v fc-cache >/dev/null && fc-cache -f "$FONT_DIR" >/dev/null
    info "Nerd Font 설치 완료 (fc-cache 반영)"
  fi
fi

# ── 3. zshrc ───────────────────────────────────────────────
if [ "$OS" = "Darwin" ]; then SRC=zsh/zshrc.macos; else SRC=zsh/zshrc.linux; fi
deploy_file "$SRC" "$HOME/.zshrc" zshrc
info ".zshrc 배치 완료 ($SRC)"
[ -f "$HOME/.zshrc.local" ] || info "참고: 머신별 alias/함수는 ~/.zshrc.local 에 (템플릿: zsh/zshrc.local.example). 없으면 건너뜀"

# ── 4. Claude Code statusline ──────────────────────────────
# 스크립트 복사 + settings.json 에 statusLine 키만 merge (다른 키는 건드리지 않음)
deploy_file claude/statusline-command.sh "$HOME/.claude/statusline-command.sh" statusline-command.sh
chmod +x "$HOME/.claude/statusline-command.sh"
command -v jq >/dev/null || info "경고: statusline 스크립트는 jq 필요 — 설치 권장 (brew/dnf/apt install jq)"
python3 - <<'PYEOF'
import json, os, sys, tempfile
home = os.path.expanduser("~")
p = os.path.join(home, ".claude", "settings.json")
backup = os.path.join(home, ".config", "dotfiles", "backup")

def atomic_write_json(path, obj):
    """같은 디렉터리의 임시 파일에 쓰고 os.replace 로 교체 — 중단돼도 원본은 온전. 기존 mode 보존."""
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    mode = os.stat(path).st_mode & 0o777 if os.path.exists(path) else 0o600
    fd, tmp = tempfile.mkstemp(prefix=".settings.", suffix=".tmp", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2); f.write("\n")
            f.flush(); os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        try: os.unlink(tmp)
        except OSError: pass
        raise

d = {}
existed = os.path.exists(p)
if existed:
    try:
        with open(p) as f:
            d = json.load(f)
    except ValueError as e:
        print(f"[install] 오류: {p} 이 올바른 JSON 이 아님 ({e}) — 원본을 건드리지 않고 중단", file=sys.stderr)
        sys.exit(1)
    if not isinstance(d, dict):
        print(f"[install] 오류: {p} 최상위가 객체가 아님 — 원본을 건드리지 않고 중단", file=sys.stderr)
        sys.exit(1)
# 최초 1회: settings.json 자체 유무와 이전 내용을 기록 (uninstall 복원용)
if not os.path.exists(os.path.join(backup, "settings.json.orig")) and not os.path.exists(os.path.join(backup, "settings.json.absent")):
    if existed:
        atomic_write_json(os.path.join(backup, "settings.json.orig"), d)
    else:
        open(os.path.join(backup, "settings.json.absent"), "w").close()
want = {"type": "command", "command": f"bash {home}/.claude/statusline-command.sh"}
if d.get("statusLine") != want:
    d["statusLine"] = want
    atomic_write_json(p, d)
    print("[install] settings.json statusLine 키 갱신")
else:
    print("[install] settings.json statusLine 이미 최신")
PYEOF
info "Claude statusline 배치 완료"

# ── 5. Codex CLI status line ───────────────────────────────
# Codex 는 외부 명령 status line 이 없어 스크립트 대신 config.toml 의 [tui] status_line 키만 merge (다른 키는 건드리지 않음)
# 내장 비용 항목(estimated-thread-cost)은 Enterprise 전용이라, API 환산 비용은 Stop 훅이 턴마다 한 줄로 보여준다
if command -v codex >/dev/null || [ -d "$HOME/.codex" ]; then
  python3 codex/status-line.py apply
  deploy_file codex/cost-hook.py "$HOME/.codex/cost-hook.py" codex-cost-hook.py
  python3 codex/hooks.py apply
  info "Codex status line 배치 완료"
fi

# ── 6. Antigravity CLI statusline ──────────────────────────
# Claude 와 같은 방식(외부 명령이 stdin JSON 을 받아 출력) — 스크립트 복사 + settings.json 의 statusLine 키만 merge
# Antigravity CLI 를 쓰는 머신에서만. 없으면 ~/.gemini 를 만들지 않고 건너뜀
if command -v agy >/dev/null || [ -d "$HOME/.gemini/antigravity-cli" ]; then
  deploy_file agy/statusline-command.sh "$HOME/.gemini/antigravity-cli/statusline-command.sh" agy-statusline-command.sh
  chmod +x "$HOME/.gemini/antigravity-cli/statusline-command.sh"
  python3 agy/settings.py apply
  command -v jq >/dev/null || info "경고: Antigravity statusline 스크립트는 jq 필요 — 설치 권장 (brew/dnf/apt install jq)"
  info "Antigravity CLI statusline 배치 완료"
fi

# ── 7. 기본 셸 ─────────────────────────────────────────────
ZSH_PATH="$(command -v zsh)"
if [ "${SHELL:-}" != "$ZSH_PATH" ]; then
  info "기본 셸이 zsh 가 아님 → 변경하려면: chsh -s $ZSH_PATH"
fi

info "완료. 새 셸을 열거나 'exec zsh' 로 적용."
