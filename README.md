# msw-dotfiles

메이플스토리 월드 AI 코딩의 기본 규칙을 새 프로젝트에 한 번에 적용하는 부트스트랩 설치기입니다.

## 생성 파일

| 파일 | 내용 | 병합 동작 |
|---|---|---|
| `.mcp.json` | MSW-MCP 서버 (`${MSW_MCP_TOKEN}` 참조) | 기존 서버 보존, MSW-MCP만 추가 |
| `.claude/settings.json` | 마켓플레이스 참조 + 플러그인 활성화 + MSW-MCP 자동승인 (팀 공유) | 기존 키 보존 후 병합 |
| `.claude/settings.local.json` | `env.MSW_MCP_TOKEN` (개인, 커밋 금지) | 기존 토큰 값 보존 |
| `CLAUDE.md` | `MSW-BASE-RULES` 마커 블록 | 블록만 갱신, 나머지 본문 유지 |
| `.gitignore` | `settings.local.json` 보호 | 누락 시 추가 |

`.claude/settings.json` (팀 공유, 비밀 없음):

```jsonc
{
  "extraKnownMarketplaces": {
    "msw-ai-coding-plugins-official": {
      "source": { "source": "github", "repo": "MSW-Git/msw-ai-coding-plugins-official" }
    }
  },
  "enabledPlugins": {
    "msw-maker-base-skill@msw-ai-coding-plugins-official": true
  },
  "enabledMcpjsonServers": ["MSW-MCP"]
}
```

## 사용법

### Windows (PowerShell)

```powershell
# -Path 를 생략하면 대상 경로를 입력받습니다 (Enter 시 현재 폴더)
.\bootstrap.ps1
# 경로를 바로 지정할 수도 있습니다
.\bootstrap.ps1 -Path C:\path\to\my-new-world
```

### macOS / Linux / WSL (bash)

```bash
~/msw-dotfiles/bootstrap.sh -p ~/work/my-new-world
```

> 포크나 사설 마켓플레이스를 쓸 때만 슬러그를 바꾸세요: `-MarketplaceRepo OWNER/REPO` (PowerShell) / `-r OWNER/REPO` (bash).

### 토큰 설정

부트스트랩이 만든 `.claude/settings.local.json` 의 `env.MSW_MCP_TOKEN` 에 발급받은 토큰을 넣습니다. 이 값이 `.mcp.json` 의 `${MSW_MCP_TOKEN}` 로 치환됩니다.

```jsonc
{
  "env": { "MSW_MCP_TOKEN": "발급받은-토큰" }
}
```

> **왜 환경변수/`.env` 가 아니라 여기인가:** Claude Code 는 `.env` 파일을 자동으로 읽지 않고, OS 환경변수(`setx` 등)는 GUI/VSCode 확장처럼 이미 실행 중인 프로세스에 상속되지 않아 `${MSW_MCP_TOKEN}` 가 빈 값으로 치환되는 경우가 많습니다. `settings.local.json` 의 `env` 는 Claude Code 가 시작 시 로드해 치환에 확실히 반영되고, 머신 전역 노출 없이 Claude Code 로만 범위가 좁혀지며, gitignore 됩니다.

### 적용 확인

대상 폴더에서 Claude Code 를 (재)시작하면 워크스페이스 신뢰 → 마켓플레이스 설치 프롬프트가 뜹니다. 이미 세션이 열려 있으면 `/reload-plugins`. `/mcp` 로 `MSW-MCP` 연결 상태를 확인하세요.

## 보안 메모

- 토큰은 `.claude/settings.local.json`(개인·gitignore) 에만 들어가며 커밋되지 않습니다. `.mcp.json` 에는 `${MSW_MCP_TOKEN}` 참조만 들어갑니다.
- 부트스트랩이 `.gitignore` 에 `.claude/settings.local.json` 보호 라인을 추가합니다.
