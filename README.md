# dotfiles

zsh + starship 셸 환경과 Claude Code statusline 을 새 머신에 한 번에 맞추는 부트스트랩 저장소. macOS(Homebrew)와 Linux(dnf/apt) 를 같은 `install.sh` 로 설치하고, `uninstall.sh` 로 설치 전 상태까지 되돌린다.

어느 머신에나 그대로 적용할 수 있는 설정만 추적한다. 호스트 alias·내부 URL·API 키·개인 에이전트 지침처럼 머신이나 사람에 묶인 것은 저장소 밖(`~/.zshrc.local`, `~/.secrets.zsh`)에 둔다 — 자세한 경계는 [추적 범위](#추적-범위) 참고. 에이전트·기여자용 상세 규칙은 [AGENTS.md](AGENTS.md).

## 구성

```
dotfiles/
├── install.sh                 # 부트스트랩 스크립트 (멱등)
├── uninstall.sh               # install.sh 적용 전 상태로 복원 (--purge 로 패키지까지)
├── AGENTS.md                  # 프로젝트 개요·불변 규칙·검증 방법 (AI 에이전트/기여자용)
├── starship/
│   └── starship.toml          # Catppuccin Mocha 팔레트 2줄 프롬프트, Nerd Font 글리프 (OS 공통)
├── zsh/
│   ├── zshrc.macos            # macOS 용 — brew 기반(Apple Silicon/Intel 자동), eza/bat/zoxide/fzf/pyenv/pnpm/플러그인
│   ├── zshrc.linux            # Linux 서버용 — 같은 구조의 미니멀판, 도구는 있을 때만 활성
│   └── zshrc.local.example    # 머신별 alias/함수 템플릿(placeholder) → ~/.zshrc.local (미추적) 로 복사해 사용
└── claude/
    └── statusline-command.sh  # Claude Code 하단 statusline (경로·git·모델·컨텍스트 바·rate limit)
```

## 설치

```bash
git clone https://github.com/LeeYudok/dotfiles.git
cd dotfiles && ./install.sh
```

`install.sh` 동작 (스크립트 내 섹션 번호와 동일):

| # | 단계 | 내용 |
|---|---|---|
| 0 | 의존성 검사 | `curl`·`unzip`·`python3`, macOS 는 `brew`, Linux 는 `dnf`/`apt-get` 이 없으면 **홈 파일을 하나도 만들지 않고** 종료. `~/.claude/settings.json` 이 깨진 JSON 이어도 여기서 중단. |
| 1 | 패키지 설치 | macOS: brew 로 `starship eza bat zoxide fzf fd jq zsh-autosuggestions zsh-syntax-highlighting` (없을 때만). Linux: `zsh`(dnf/apt), `starship`(공식 스크립트, sudo 없으면 `~/.local/bin`), 자동완성 플러그인 2종(dnf 는 EPEL 활성화 후), `jq`(sudo 가능할 때만, 아니면 경고). |
| 2 | starship.toml | `starship/starship.toml` → `~/.config/starship.toml` |
| 2.5 | Nerd Fonts | GitHub 최신 릴리스에서 `JetBrainsMono`, `D2Coding` zip 을 받아 폰트 디렉터리(macOS `~/Library/Fonts`, Linux `~/.local/share/fonts` + `fc-cache`)에 설치. 폰트별 `.nerd-font-<name>-installed` 마커 파일로 재설치 방지. |
| 3 | zshrc | OS 에 맞는 `zsh/zshrc.*` → `~/.zshrc`. 머신별 alias/함수는 `~/.zshrc.local`(미추적) 에 두며 스크립트가 만들지 않는다 — 없으면 안내만. |
| 4 | Claude statusline | `claude/statusline-command.sh` → `~/.claude/statusline-command.sh` (+x). 스크립트 런타임에 `jq` 필요 — 없으면 경고만. 이어서 **python3** 로 `~/.claude/settings.json` 의 `statusLine` 키만 merge (다른 키 불변, 파일 없으면 생성). 같은 디렉터리의 임시 파일에 쓰고 `os.replace` 로 교체하므로 중단돼도 원본이 깨지지 않고, 기존 파일 mode 를 보존한다. |
| 5 | 기본 셸 | `$SHELL` 이 zsh 가 아니면 `chsh -s <zsh 경로>` 안내만 (자동 변경 안 함). |

런타임 의존성: `curl`, `unzip`, `python3`(0 단계에서 검사). macOS 는 Homebrew 필수. `jq` 는 statusline 스크립트 런타임 전용이라 1 단계에서 자동 설치한다(Linux 는 sudo 가능할 때만).

멱등(idempotent): 재실행해도 안전하다. 배치 대상 파일(`starship.toml`·`.zshrc`·`statusline-command.sh`)은 기존 파일과 내용이 다를 때만 `.bak` 백업 후 덮어쓴다 — `.bak` 은 1세대만 유지되므로 두 번 연속 다른 내용을 배치하면 첫 백업은 사라진다.

최초 실행 시 덮어쓸 파일의 원본과 설치 기록을 `~/.dotfiles-backup/` 에 남긴다(`<name>.orig` / `<name>.absent`, `brew-installed.txt`·`pkg-installed.txt`·`bin-installed.txt`, `settings.json.orig`). 재실행해도 이 기록은 갱신하지 않으므로 몇 번을 돌려도 "설치 전 원본"이 보존된다. Nerd Font 는 설치한 파일명을 `.nerd-font-<name>-files.txt` manifest 로 남긴다.

`~/.claude/settings.json` 전체는 이 저장소에 두지 않는다 — permissions/hooks/model 등 머신별·보안 민감 설정 포함. statusline 스크립트와 해당 키 merge 만 관리.

## 되돌리기 (uninstall.sh)

```bash
./uninstall.sh            # 배치 파일 복원/제거 + settings.json statusLine 키 복원 + Nerd Font 제거
./uninstall.sh --purge    # 위에 더해 install.sh 가 새로 설치한 brew/dnf/apt 패키지·starship 바이너리 제거
./uninstall.sh --keep-backup   # ~/.dotfiles-backup 을 남김 (기본은 복원 후 삭제)
```

- 복원 우선순위: `~/.dotfiles-backup/<name>.orig` 가 있으면 그 내용으로, `.absent` 면 삭제, 둘 다 없으면(이 기록 방식 이전에 설치한 머신) `.bak` 이 있을 때 `.bak` 으로, 없으면 삭제.
- `settings.json` 은 `statusLine` 키만 설치 전 값으로 되돌리고 다른 키(permissions/hooks/model 등)는 그대로 둔다. 설치 전에 파일이 없었고 남는 키도 없으면 파일 자체를 지운다. 쓰기는 install 과 같은 원자적 교체이며, 깨진 JSON 이면 손대지 않고 중단한다.
- `~/.zshrc.local`, `~/.secrets.zsh`, `~/.claude/CLAUDE.md` 는 사용자 파일이므로 건드리지 않는다.
- 폰트는 manifest 에 적힌 파일만 지운다. manifest 없이 설치된 옛 머신은 마커만 지우고 경고를 낸다.
- `--purge` 는 `install.sh` 가 **새로 설치했다고 기록한 것만** 제거한다. 이미 깔려 있던 starship/eza 등은 건드리지 않는다.
- 끝나면 `~/.zshrc` 가 원본(또는 없음)으로 돌아가 zsh 기본 프롬프트로 동작한다. 기본 셸 자체는 `chsh` 로 직접 되돌린다.
- 실제 홈에 영향 없이 시험하려면 `HOME=$(mktemp -d) ./install.sh && HOME=<같은 경로> ./uninstall.sh`.

## 프롬프트 (starship.toml)

starship 1.26 기준. `[palettes.catppuccin_mocha]` 로 색을 이름으로 참조하고, 심볼은 전부 Nerd Font 글리프(이모지 없음).

- 2줄: `╭─ OS아이콘 user @host dir git브랜치 [git상태] +추가 -삭제 via 언어버전 took 실행시간` / `╰─ 종료코드 ❯`
- 오른쪽 프롬프트(`right_format`)에 현재 시각 `HH:MM:SS`
- hostname 은 SSH 접속일 때만 (`ssh_only`), username 은 root 등 비기본 사용자일 때만
- git: branch(원격 추적 브랜치 포함)·status·state(rebase/merge 진행률)·`git_metrics`(라인 증감)
- 언어/런타임은 해당 프로젝트 파일이 있을 때만: rust/python(pyenv·venv)/node/bun/java/go, docker context 는 compose 파일 있을 때만. kubernetes 모듈은 기본 비활성.
- `directory.substitutions` 로 `~/workspace` → `ws` 축약
- 터미널 폰트를 JetBrainsMono Nerd Font(또는 D2Coding Nerd Font)로 지정해야 글리프가 깨지지 않는다 (2.5 단계에서 설치). Linux 서버의 starship 1.22 에서도 동작(palettes 는 1.9+, os 모듈 1.16+).

## zsh (zshrc.macos / zshrc.linux)

두 파일은 같은 섹션 순서를 따른다: 환경·PATH → 히스토리·옵션 → 자동완성 → 툴 초기화 → alias/함수 → 시크릿 → 플러그인(맨 끝).

- PATH 는 `typeset -U path` 로 중복 자동 제거. macOS 판은 `HOMEBREW_PREFIX` 를 자동 감지(Apple Silicon `/opt/homebrew`, Intel `/usr/local`, `brew shellenv` 가 이미 설정했으면 그 값)하고, rustup·JAVA_HOME(openjdk@21)·pnpm·Antigravity 등은 **디렉터리가 있을 때만** PATH 에 넣는다. starship/zoxide/fzf/eza/bat/플러그인도 없으면 조용히 건너뛴다.
- 머신별 항목(SSH 호스트 alias, 컨테이너 접속 alias, 프로젝트 전용 함수·경로 등)은 `~/.zshrc.local`(미추적) 에 두고 두 zshrc 가 플러그인 직전에 `source` 한다. 새 머신은 `cp zsh/zshrc.local.example ~/.zshrc.local` 후 필요한 예시만 주석을 풀어 그 머신 값으로 채운다.
- 히스토리: 세션 간 공유, 중복 제거, 앞에 공백 붙인 명령은 기록 안 함(시크릿 입력용). ↑/↓ 는 입력한 접두어로 필터.
- compinit 은 하루 한 번만 전체 스캔(`.zcompdump` 캐시)해 기동 시간을 줄인다.
- fzf: `Ctrl-R` 히스토리, `Ctrl-T` 파일, `Alt-C` 디렉터리. `fd` 있으면 파일 탐색 소스로 사용.
- zoxide 가 `cd` 를 대체(`cd <키워드>` 로 점프).
- 시크릿(API 키 등)은 `~/.secrets.zsh`(mode 600, 미추적)에만 두고 zshrc 는 `source` 만 한다. zshrc 에 값을 직접 쓰지 않는다.
- Linux 판은 starship/eza/zoxide/fzf 가 없으면 각각 기본 프롬프트·`ls --color`·일반 `cd` 로 폴백.

## Claude Code statusline

`claude/statusline-command.sh` 는 stdin 으로 받은 Claude Code statusLine JSON 을 파싱해 한 줄로 출력한다: 경로 · git 브랜치/dirty · 모델명 · 컨텍스트 사용률 바 · rate limit. 런타임에 `jq` 가 필요하다.

`install.sh` 는 스크립트를 배치하고 `~/.claude/settings.json` 의 `statusLine` 키 하나만 merge 한다. `settings.json` 전체와 `~/.claude/CLAUDE.md` 같은 개인 지침은 이 저장소가 관리하지 않는다.

## 추적 범위

| 추적한다 | 추적하지 않는다 |
|---|---|
| OS 공통 프롬프트(`starship.toml`) | 실제 호스트명·IP·SSH 포트·내부 URL |
| OS 별 zshrc (도구가 있을 때만 켜지는 구조) | 머신별 alias/함수 → `~/.zshrc.local` |
| placeholder 로만 채운 `zshrc.local.example` | API 키·토큰 → `~/.secrets.zsh` (mode 600) |
| statusline 스크립트 | `~/.claude/settings.json` 전체, 개인 `CLAUDE.md` |
| 설치/제거 스크립트와 문서 | 머신별 적용 현황, 백업 파일(`*.bak`) |

`.gitignore` 가 오른쪽 열의 파일명을 막아 두지만, 템플릿이나 문서에 실제 값을 적는 실수는 막지 못한다. 커밋 전에 `git diff --cached` 로 호스트명·IP·URL 이 들어가지 않았는지 확인한다.

## 홈 파일과의 드리프트

`install.sh` 는 홈 파일을 저장소 사본으로 덮어쓴다(`.bak` 1세대 백업). 홈에서 먼저 고친 설정이 있으면 저장소 사본이 더 오래된 상태일 수 있으므로, 재실행 전에 `diff zsh/zshrc.macos ~/.zshrc`, `diff starship/starship.toml ~/.config/starship.toml` 로 확인한다. 홈에서 가져올 때는 시크릿 값이나 머신 고유 경로가 섞여 있지 않은지 본다.

## 갱신 규칙

- 로컬에서 `~/.zshrc` / `~/.config/starship.toml` / `~/.claude/statusline-command.sh` 를 바꾸면 이 저장소에도 반영해 커밋한다.
- 머신별 일회성 설정(특정 호스트 alias 등)은 `~/.zshrc.local` 에 두고 저장소 zshrc 에는 넣지 않는다. 공통화 가능한 것만 양쪽 zshrc 에 반영.
- `install.sh` 에 단계를 추가하면 헤더 주석과 이 README 의 단계 표를 같이 고친다. 홈에 뭔가를 새로 만들면 `uninstall.sh` 에 그 역연산도 같이 넣는다.
- 작업은 이슈 먼저(`#N`) → `docs/`·`feat/`·`fix/`·`chore/` 브랜치 → PR.
