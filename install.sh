#!/usr/bin/env bash
# dotfiles install — zsh + starship 표준 셸 환경 부트스트랩
#
# 사용법:
#   git clone https://github.com/LeeYudok/dotfiles.git && cd dotfiles && ./install.sh
#
# 동작 (섹션 번호 = 아래 주석 번호 = README 단계 표):
#   0.   의존성 사전 검사 — 누락 시 홈 파일을 하나도 바꾸지 않고 종료
#   1.   zsh / starship / 플러그인 / jq 설치 (없을 때만; macOS 는 eza·bat·zoxide 포함)
#   2.   starship.toml 배치 (~/.config/starship.toml)
#   2.5. Nerd Fonts 설치 (JetBrainsMono, D2Coding; 마커 파일로 재설치 방지)
#   3.   OS 에 맞는 zshrc 배치 (~/.zshrc). 머신별 alias/함수는 ~/.zshrc.local (미추적, 이 스크립트가 만들지 않음)
#   4.   Claude Code statusline 스크립트 배치 (~/.claude/statusline-command.sh)
#        + settings.json 의 statusLine 키만 merge (python3, 원자적 쓰기)
#   5.   기본 셸이 zsh 가 아니면 chsh 안내
#
# 런타임 의존성: curl, unzip, python3 (0 단계에서 검사). macOS 는 Homebrew 필수.
#   jq 는 statusline 스크립트 런타임 전용 — 1 단계에서 brew/dnf/apt 로 자동 설치 (sudo 불가 시 경고만).
# 멱등(idempotent): 재실행해도 안전하다. 배치 대상은 내용이 다를 때만 .bak 백업 후 덮어쓴다.
#
# 되돌리기: ./uninstall.sh — 최초 실행 시 ~/.dotfiles-backup/ 에 보관한 원본과 manifest 를 기준으로 복원한다.
#   - <name>.orig     : 덮어쓰기 전 원본 (최초 1회만 기록, 이후 실행은 갱신하지 않음)
#   - <name>.absent   : 원래 그 파일이 없었다는 표시
#   - brew-installed.txt / pkg-installed.txt / bin-installed.txt : 이 스크립트가 새로 설치한 것만 기록
#   - settings.json.orig : settings.json 설치 전 전체 내용 (없었으면 settings.json.absent)

set -euo pipefail
cd "$(dirname "$0")"

OS="$(uname -s)"
info() { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[install] 오류:\033[0m %s\n' "$*" >&2; exit 1; }

# ── 0. 의존성 사전 검사 (홈 파일 변경 전) ────────────────────
# 여기서 실패하면 ~/.dotfiles-backup 을 포함해 아무것도 만들거나 바꾸지 않는다.
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

BACKUP_DIR="$HOME/.dotfiles-backup"
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
mkdir -p "$FONT_DIR"
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
for font in JetBrainsMono D2Coding; do
  install_nerd_font "$font"
done
if [ "$OS" = "Darwin" ]; then
  info "Nerd Font 설치 완료 (Font Book 자동 등록)"
else
  command -v fc-cache >/dev/null && fc-cache -f "$FONT_DIR" >/dev/null
  info "Nerd Font 설치 완료 (fc-cache 반영)"
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
backup = os.path.join(home, ".dotfiles-backup")

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

# ── 5. 기본 셸 ─────────────────────────────────────────────
ZSH_PATH="$(command -v zsh)"
if [ "${SHELL:-}" != "$ZSH_PATH" ]; then
  info "기본 셸이 zsh 가 아님 → 변경하려면: chsh -s $ZSH_PATH"
fi

info "완료. 새 셸을 열거나 'exec zsh' 로 적용."
