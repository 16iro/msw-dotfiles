#Requires -Version 5.1
<#
.SYNOPSIS
    MSW 기본 규칙(닷파일)을 대상 프로젝트에 적용합니다.

.DESCRIPTION
    대상 프로젝트 폴더에 다음을 생성/병합합니다.
      - .mcp.json                    : MSW-MCP 서버 등록 (토큰은 ${MSW_MCP_TOKEN} 참조)
      - .claude/settings.json        : 마켓플레이스 참조 + 플러그인 활성화 + MSW-MCP 자동승인 (팀 공유)
      - .claude/settings.local.json  : env.MSW_MCP_TOKEN (개인, 커밋 금지)
      - CLAUDE.md                    : MSW 기본 운영 규칙 블록
      - .gitignore                   : settings.local.json 보호

    플러그인 본체는 복사하지 않습니다. settings.json 의 마켓플레이스 참조를 통해
    github:MSW-Git/msw-ai-coding-plugins-official 에서 원격으로 로드됩니다.

.PARAMETER Path
    적용할 대상 프로젝트 폴더. 생략하면 실행 시 입력받으며, 빈 값(Enter)이면 현재 폴더.

.PARAMETER MarketplaceRepo
    마켓플레이스 git 슬러그. 기본값: MSW-Git/msw-ai-coding-plugins-official (포크/사설일 때만 변경).

.PARAMETER Force
    이미 존재하는 .mcp.json 의 MSW-MCP 키를 덮어씁니다.

.EXAMPLE
    .\bootstrap.ps1 -Path C:\work\my-msw-world
#>
[CmdletBinding()]
param(
    [string]$Path,
    [string]$MarketplaceRepo = "MSW-Git/msw-ai-coding-plugins-official",
    [string]$MarketplaceName = "msw-ai-coding-plugins-official",
    [string]$PluginName = "msw-maker-base-skill",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateDir = Join-Path $ScriptDir "templates"

function Write-Step($m){ Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)  { Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Warn2($m){ Write-Host "    [!]  $m" -ForegroundColor Yellow }

# -Path 미지정 시 입력받음 (Enter = 현재 폴더)
if (-not $PSBoundParameters.ContainsKey('Path')) {
    $cur = (Get-Location).Path
    $answer = Read-Host "대상 프로젝트 경로를 입력하세요 (Enter = 현재 폴더: $cur)"
    $Path = if ([string]::IsNullOrWhiteSpace($answer)) { $cur } else { $answer.Trim('"') }
}

if (-not (Test-Path $Path)) { throw "대상 경로가 없습니다: $Path" }
$Path = (Resolve-Path $Path).Path

Write-Step "대상 프로젝트: $Path"
Write-Step "마켓플레이스 : $MarketplaceName  ->  github:$MarketplaceRepo"

function Read-JsonOrEmpty($file){
    if (Test-Path $file) {
        $raw = Get-Content $file -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) { return [PSCustomObject]@{} }
        return $raw | ConvertFrom-Json
    }
    return [PSCustomObject]@{}
}
function Ensure-Object($obj,$name){
    if (-not ($obj.PSObject.Properties.Name -contains $name)) {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    return $obj.$name
}
function Save-Json($obj,$file){
    $dir = Split-Path -Parent $file
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    ($obj | ConvertTo-Json -Depth 20) | Out-File -FilePath $file -Encoding utf8
}

# 1) .mcp.json
Write-Step ".mcp.json 구성"
$mcpFile = Join-Path $Path ".mcp.json"
$mcp = Read-JsonOrEmpty $mcpFile
$servers = Ensure-Object $mcp 'mcpServers'
if (($servers.PSObject.Properties.Name -contains 'MSW-MCP') -and -not $Force) {
    Write-Warn2 "MSW-MCP 서버가 이미 있어 건너뜁니다 (-Force 로 덮어쓰기)"
} else {
    $mswServer = [PSCustomObject]@{
        type    = "http"
        url     = "https://msw-mcp.nexon.com/mcp"
        headers = [PSCustomObject]@{ Authorization = "Bearer `${MSW_MCP_TOKEN}" }
    }
    $servers | Add-Member -NotePropertyName 'MSW-MCP' -NotePropertyValue $mswServer -Force
    Save-Json $mcp $mcpFile
    Write-Ok ".mcp.json 작성 (토큰은 `${MSW_MCP_TOKEN} 환경변수 참조)"
}

# 2) .claude/settings.json (팀 공유 — 비밀 없음)
Write-Step ".claude/settings.json 구성 (마켓플레이스 참조 + 플러그인/서버 활성화)"
$settingsFile = Join-Path $Path ".claude\settings.json"
$settings = Read-JsonOrEmpty $settingsFile
$mk = Ensure-Object $settings 'extraKnownMarketplaces'
$mk | Add-Member -NotePropertyName $MarketplaceName -NotePropertyValue ([PSCustomObject]@{
        source = [PSCustomObject]@{ source = "github"; repo = $MarketplaceRepo }
    }) -Force
$ep = Ensure-Object $settings 'enabledPlugins'
$ep | Add-Member -NotePropertyName "$PluginName@$MarketplaceName" -NotePropertyValue $true -Force
# .mcp.json 의 MSW-MCP 서버 자동 승인 (프롬프트 스킵)
$mcpEnabled = @()
if ($settings.PSObject.Properties.Name -contains 'enabledMcpjsonServers') { $mcpEnabled = @($settings.enabledMcpjsonServers) }
if ($mcpEnabled -notcontains 'MSW-MCP') { $mcpEnabled += 'MSW-MCP' }
$settings | Add-Member -NotePropertyName 'enabledMcpjsonServers' -NotePropertyValue ([object[]]$mcpEnabled) -Force
Save-Json $settings $settingsFile
Write-Ok "settings.json 작성 ($PluginName@$MarketplaceName = true, enabledMcpjsonServers: MSW-MCP)"

# 3) CLAUDE.md
Write-Step "CLAUDE.md 기본 규칙 블록 적용"
$claudeFile = Join-Path $Path "CLAUDE.md"
$baseBlock  = Get-Content (Join-Path $TemplateDir "CLAUDE.base.md") -Raw -Encoding UTF8
if (Test-Path $claudeFile) {
    $cur = Get-Content $claudeFile -Raw -Encoding UTF8
    if ($cur -match '(?s)<!-- MSW-BASE-RULES:START.*?MSW-BASE-RULES:END -->') {
        $new = [regex]::Replace($cur,'(?s)<!-- MSW-BASE-RULES:START.*?MSW-BASE-RULES:END -->',$baseBlock.TrimEnd())
        $new | Out-File -FilePath $claudeFile -Encoding utf8
        Write-Ok "기존 MSW 규칙 블록 갱신"
    } else {
        ($cur.TrimEnd() + "`r`n`r`n" + $baseBlock) | Out-File -FilePath $claudeFile -Encoding utf8
        Write-Ok "기존 CLAUDE.md 끝에 규칙 블록 추가"
    }
} else {
    $baseBlock | Out-File -FilePath $claudeFile -Encoding utf8
    Write-Ok "CLAUDE.md 생성"
}

# 4) .claude/settings.local.json (개인 — 토큰, 커밋 금지)
Write-Step ".claude/settings.local.json 구성 (토큰 보관용)"
$localFile = Join-Path $Path ".claude\settings.local.json"
$local = Read-JsonOrEmpty $localFile
$envObj = Ensure-Object $local 'env'
$tokenSet = ($envObj.PSObject.Properties.Name -contains 'MSW_MCP_TOKEN') -and -not [string]::IsNullOrWhiteSpace($envObj.MSW_MCP_TOKEN)
if ($tokenSet) {
    Write-Ok "기존 MSW_MCP_TOKEN 값 보존"
} else {
    $envObj | Add-Member -NotePropertyName 'MSW_MCP_TOKEN' -NotePropertyValue "" -Force
    Write-Ok "settings.local.json 생성 (MSW_MCP_TOKEN 빈칸 -> 직접 채워야 함)"
}
Save-Json $local $localFile

# 5) .gitignore 보호 (토큰 커밋 방지)
Write-Step ".gitignore 에 settings.local.json 보호 추가"
$giFile = Join-Path $Path ".gitignore"
$ignoreLine = ".claude/settings.local.json"
$covered = $false
if (Test-Path $giFile) {
    $gi = Get-Content $giFile -Raw -Encoding UTF8
    if ($gi -match [regex]::Escape($ignoreLine) -or $gi -match '\*\.local\.json') { $covered = $true }
}
if ($covered) {
    Write-Ok "이미 .gitignore 로 보호됨"
} else {
    Add-Content -Path $giFile -Value "`r`n# Claude Code 개인 설정(토큰 등) - 커밋 금지`r`n$ignoreLine" -Encoding utf8
    Write-Ok ".gitignore 에 $ignoreLine 추가"
}

Write-Host ""
Write-Step "완료. 다음 단계:"
if (-not $tokenSet) {
    Write-Warn2 "토큰이 비어 있습니다. .claude/settings.local.json 의 env.MSW_MCP_TOKEN 에 발급받은 토큰을 넣으세요:"
    Write-Host  '       "env": { "MSW_MCP_TOKEN": "발급받은-토큰" }'
} else {
    Write-Ok "MSW_MCP_TOKEN 이 settings.local.json 에 설정되어 있습니다."
}
Write-Host  "    - 대상 폴더에서 Claude Code 를 열면 워크스페이스 신뢰 -> 마켓플레이스 설치 프롬프트가 뜹니다."
Write-Host  "    - 이미 세션이 열려 있으면 /reload-plugins 또는 재시작. /mcp 로 MSW-MCP 연결 확인."
