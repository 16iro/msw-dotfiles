#!/usr/bin/env bash
# MSW 기본 규칙(닷파일)을 대상 프로젝트에 적용 (macOS / Linux / WSL)
# 의존성: jq
#
# 사용법:
#   ./bootstrap.sh [-p /path/to/project] [-r OWNER/REPO] [-f]
#     -p  대상 프로젝트 폴더 (생략 시 입력받음, 빈 값이면 현재 폴더)
#     -r  마켓플레이스 git 슬러그 (기본: MSW-Git/msw-ai-coding-plugins-official)
#     -f  기존 .mcp.json 의 MSW-MCP 키 덮어쓰기
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SCRIPT_DIR/templates"

TARGET=""
REPO="MSW-Git/msw-ai-coding-plugins-official"
MKT_NAME="msw-ai-coding-plugins-official"
PLUGIN="msw-maker-base-skill"
FORCE=0

while getopts "p:r:f" opt; do
  case "$opt" in
    p) TARGET="$OPTARG" ;;
    r) REPO="$OPTARG" ;;
    f) FORCE=1 ;;
    *) echo "사용법: $0 [-p path] [-r OWNER/REPO] [-f]"; exit 1 ;;
  esac
done

# -p 미지정 시 입력받음 (Enter = 현재 폴더)
if [ -z "$TARGET" ]; then
  read -r -p "대상 프로젝트 경로를 입력하세요 (Enter = 현재 폴더: $(pwd)): " TARGET
  [ -n "$TARGET" ] || TARGET="$(pwd)"
fi

command -v jq >/dev/null || { echo "jq 가 필요합니다 (brew install jq / apt install jq)"; exit 1; }
[ -d "$TARGET" ] || { echo "대상 경로가 없습니다: $TARGET"; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

step(){ printf '\033[36m==> %s\033[0m\n' "$1"; }
ok(){ printf '\033[32m    [OK] %s\033[0m\n' "$1"; }
warn(){ printf '\033[33m    [!]  %s\033[0m\n' "$1"; }

step "대상 프로젝트: $TARGET"
step "마켓플레이스 : $MKT_NAME -> github:$REPO"

# 1) .mcp.json
step ".mcp.json 구성"
MCP="$TARGET/.mcp.json"
[ -f "$MCP" ] || echo '{}' > "$MCP"
if jq -e '.mcpServers["MSW-MCP"]' "$MCP" >/dev/null 2>&1 && [ "$FORCE" -ne 1 ]; then
  warn "MSW-MCP 가 이미 있어 건너뜀 (-f 로 덮어쓰기)"
else
  jq '.mcpServers["MSW-MCP"] = {
        "type":"http",
        "url":"https://msw-mcp.nexon.com/mcp",
        "headers":{"Authorization":"Bearer ${MSW_MCP_TOKEN}"}
      }' "$MCP" > "$MCP.tmp" && mv "$MCP.tmp" "$MCP"
  ok ".mcp.json 작성 (토큰은 \${MSW_MCP_TOKEN} 환경변수 참조)"
fi

# 2) .claude/settings.json (팀 공유 — 비밀 없음)
step ".claude/settings.json 구성 (마켓플레이스 + 플러그인/서버 활성화)"
mkdir -p "$TARGET/.claude"
SET="$TARGET/.claude/settings.json"
[ -f "$SET" ] || echo '{}' > "$SET"
jq --arg name "$MKT_NAME" --arg repo "$REPO" --arg key "$PLUGIN@$MKT_NAME" '
  .extraKnownMarketplaces[$name] = {"source":{"source":"github","repo":$repo}}
  | .enabledPlugins[$key] = true
  | .enabledMcpjsonServers = ((.enabledMcpjsonServers // []) + ["MSW-MCP"] | unique)
' "$SET" > "$SET.tmp" && mv "$SET.tmp" "$SET"
ok "settings.json 작성 ($PLUGIN@$MKT_NAME = true, enabledMcpjsonServers: MSW-MCP)"

# 3) CLAUDE.md
step "CLAUDE.md 기본 규칙 블록 적용"
CL="$TARGET/CLAUDE.md"
BLOCK="$(cat "$TPL/CLAUDE.base.md")"
if [ -f "$CL" ] && grep -q "MSW-BASE-RULES:START" "$CL"; then
  awk -v b="$BLOCK" '
    /MSW-BASE-RULES:START/{print b; skip=1}
    /MSW-BASE-RULES:END/{skip=0; next}
    skip!=1{print}
  ' "$CL" > "$CL.tmp" && mv "$CL.tmp" "$CL"
  ok "기존 MSW 규칙 블록 갱신"
elif [ -f "$CL" ]; then
  printf '\n\n%s\n' "$BLOCK" >> "$CL"; ok "기존 CLAUDE.md 끝에 규칙 블록 추가"
else
  printf '%s\n' "$BLOCK" > "$CL"; ok "CLAUDE.md 생성"
fi

# 4) .claude/settings.local.json (개인 — 토큰, 커밋 금지)
step ".claude/settings.local.json 구성 (토큰 보관용)"
LOCAL="$TARGET/.claude/settings.local.json"
[ -f "$LOCAL" ] || echo '{}' > "$LOCAL"
TOKEN_SET=0
if [ -n "$(jq -r '.env.MSW_MCP_TOKEN // ""' "$LOCAL")" ]; then TOKEN_SET=1; fi
if [ "$TOKEN_SET" -eq 1 ]; then
  ok "기존 MSW_MCP_TOKEN 값 보존"
else
  jq '.env.MSW_MCP_TOKEN = (.env.MSW_MCP_TOKEN // "")' "$LOCAL" > "$LOCAL.tmp" && mv "$LOCAL.tmp" "$LOCAL"
  ok "settings.local.json 생성 (MSW_MCP_TOKEN 빈칸 -> 직접 채워야 함)"
fi

# 5) .gitignore 보호 (토큰 커밋 방지)
step ".gitignore 에 settings.local.json 보호 추가"
GI="$TARGET/.gitignore"
LINE=".claude/settings.local.json"
if [ -f "$GI" ] && { grep -qF "$LINE" "$GI" || grep -qE '\*\.local\.json' "$GI"; }; then
  ok "이미 .gitignore 로 보호됨"
else
  printf '\n# Claude Code 개인 설정(토큰 등) - 커밋 금지\n%s\n' "$LINE" >> "$GI"
  ok ".gitignore 에 $LINE 추가"
fi

echo
step "완료. 다음 단계:"
if [ "$TOKEN_SET" -ne 1 ]; then
  warn "토큰이 비어 있습니다. .claude/settings.local.json 의 env.MSW_MCP_TOKEN 에 발급받은 토큰을 넣으세요."
  echo  '       "env": { "MSW_MCP_TOKEN": "발급받은-토큰" }'
else
  ok "MSW_MCP_TOKEN 이 settings.local.json 에 설정되어 있습니다."
fi
echo "    - 대상 폴더에서 Claude Code 를 열면 워크스페이스 신뢰 -> 마켓플레이스 설치 프롬프트가 뜹니다."
echo "    - 이미 세션이 열려 있으면 /reload-plugins 또는 재시작. /mcp 로 MSW-MCP 연결 확인."
