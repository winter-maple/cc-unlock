# cc-unlock v2.4-alpha — native Claude Desktop + workspace CLAUDE.md.
# Requires PowerShell 5.1+. Personal memory, agents and global settings are not managed.
param(
    [string]$Path, [switch]$Uninstall, [switch]$Verify, [switch]$All,
    [switch]$List, [switch]$GUI, [switch]$Codex, [switch]$Pi, [switch]$Omp, [switch]$SkipSettings,
    [switch]$SkipSkill, [switch]$Force, [string]$Mode,
    [string]$RelayUrl, [string]$RelayKey, [string]$RelayModel
)
$ErrorActionPreference = 'Stop'
$UTF8NoBOM = New-Object System.Text.UTF8Encoding $false
$SCRIPT_DIR = $PSScriptRoot
$USER_HOME = if ($env:USERPROFILE) { $env:USERPROFILE } else { [Environment]::GetFolderPath('UserProfile') }
$CLAUDE_DIR = Join-Path $USER_HOME '.claude'
$CLAUDE_PROJECTS = Join-Path $CLAUDE_DIR 'projects'
$CODEX_DIR = Join-Path $USER_HOME '.codex'
$CLAUDE_BUNDLE = Join-Path $SCRIPT_DIR 'claude-config-bundle'
$SKILL_BUNDLE = Join-Path $SCRIPT_DIR 'skill-bundle'
$CODEX_BUNDLE = Join-Path $SCRIPT_DIR '..\codex-files\codex-config-bundle'
$PI_DIR = Join-Path $USER_HOME '.pi\agent'
$PI_BUNDLE = Join-Path $SCRIPT_DIR '..\pi-files\pi-config-bundle'
$OMP_DIR = Join-Path $USER_HOME '.omp\agent'
$OMP_BUNDLE = Join-Path $SCRIPT_DIR '..\omp-files\omp-config-bundle'
$SKILL_DIRS = @('sec-forge')
function Write-Utf8NoBom($FilePath, $Content) {
    [IO.File]::WriteAllText($FilePath, $Content, $UTF8NoBOM)
    return $true
}
function Copy-Safe($Src, $Dst) {
    try { Copy-Item -LiteralPath $Src -Destination $Dst -Force; return $true } catch { return $false }
}
function Test-SameFile($Src, $Dst) {
    if (!(Test-Path -LiteralPath $Src -PathType Leaf) -or !(Test-Path -LiteralPath $Dst -PathType Leaf)) { return $false }
    # .NET SHA256 instead of Get-FileHash: the cmdlet lives in Microsoft.PowerShell.Utility,
    # which is absent/stripped on some hosts. The .NET API is always available.
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $a = $sha.ComputeHash([System.IO.File]::ReadAllBytes($Src))
        $b = $sha.ComputeHash([System.IO.File]::ReadAllBytes($Dst))
    } finally { $sha.Dispose() }
    if ($a.Length -ne $b.Length) { return $false }
    for ($i = 0; $i -lt $a.Length; $i++) { if ($a[$i] -ne $b[$i]) { return $false } }
    return $true
}
function Assert-NoReparse($Target) {
    $current = [IO.Path]::GetFullPath($Target)
    while ($current) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing linked/junction target: $current"
        }
        $parent = [IO.Directory]::GetParent($current)
        if (!$parent) { break }
        $current = $parent.FullName
    }
}
function Copy-BundleTree($Source, $Destination) {
    if (!(Test-Path -LiteralPath $Source -PathType Container)) { throw "Missing skill bundle: $Source" }
    Assert-NoReparse $Destination
    $base = [IO.Path]::GetFullPath($Source).TrimEnd('\') + '\'
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -File -Recurse)) {
        $target = Join-Path $Destination $file.FullName.Substring($base.Length)
        Assert-NoReparse $target
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
    Write-Host "[OK] skills/sec-forge -> $Destination (unrelated files preserved)"
}
function Remove-MatchingTree($Source, $Destination) {
    if (!(Test-Path -LiteralPath $Source -PathType Container) -or !(Test-Path -LiteralPath $Destination -PathType Container)) { return }
    Assert-NoReparse $Destination
    $base = [IO.Path]::GetFullPath($Source).TrimEnd('\') + '\'
    foreach ($file in @(Get-ChildItem -LiteralPath $Source -File -Recurse)) {
        $target = Join-Path $Destination $file.FullName.Substring($base.Length)
        Assert-NoReparse $target
        if (Test-SameFile $file.FullName $target) { Remove-Item -LiteralPath $target -Force }
    }
    # Leave directory containers: no recursive deletion of a user-owned tree.
}
function Deploy-Claude($Workspace) {
    $src = Join-Path $CLAUDE_BUNDLE 'CLAUDE.md'
    $dst = Join-Path $Workspace 'CLAUDE.md'
    if (!(Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing CLAUDE.md bundle: $src" }
    Assert-NoReparse $dst
    if ((Test-Path -LiteralPath $dst) -and !(Test-SameFile $src $dst) -and !$Force) {
        throw 'Existing CLAUDE.md differs. Inspect it first; use -Force to replace explicitly.'
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if (!$SkipSkill) { Copy-BundleTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $Workspace '.claude\skills\sec-forge') }
    Write-Host "[OK] $dst; native Desktop system prompt unchanged"
}
function Remove-Claude($Workspace) {
    $src = Join-Path $CLAUDE_BUNDLE 'CLAUDE.md'
    $dst = Join-Path $Workspace 'CLAUDE.md'
    Assert-NoReparse $dst
    if (Test-SameFile $src $dst) { Remove-Item -LiteralPath $dst -Force; Write-Host '[OK] Removed matching CLAUDE.md' }
    else { Write-Host '[KEEP] CLAUDE.md absent or user-modified' }
    Remove-MatchingTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $Workspace '.claude\skills\sec-forge')
    Write-Host '[KEEP] Personal memory, agents, rules, agent-memory and global settings untouched'
}
function Verify-Claude($Workspace) {
    if (!(Test-SameFile (Join-Path $CLAUDE_BUNDLE 'CLAUDE.md') (Join-Path $Workspace 'CLAUDE.md'))) {
        throw 'CLAUDE.md is missing or differs from bundle'
    }
    if (!$SkipSkill) {
        $src = Join-Path $SKILL_BUNDLE 'sec-forge'
        $base = [IO.Path]::GetFullPath($src).TrimEnd('\') + '\'
        foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File)) {
            $dst = Join-Path (Join-Path $Workspace '.claude\skills\sec-forge') $f.FullName.Substring($base.Length)
            if (!(Test-SameFile $f.FullName $dst)) { throw "Skill mismatch: $dst" }
        }
    }
    Write-Host '[OK] CLAUDE.md + sec-forge; no memory/subagent deployment'
}

# --- Codex functions ---

# Latin-1 (ISO 8859-1) byte passthrough for config.toml manipulation.
# Latin-1 is a 1-to-1 mapping: every byte 0x00-0xFF maps to the same
# Unicode code point. This means:
#   - Non-ASCII bytes (CJK in GBK, UTF-8, or any encoding) pass through
#     as-is without interpretation — they are NEVER decoded as text.
#   - Our key (model_instructions_file) is pure ASCII, so regex matches
#     work correctly on it without touching non-ASCII content.
#   - Writing back via Latin-1 produces the exact same bytes — zero
#     encoding corruption regardless of the file's actual encoding.
# This replaces the old UTF-8-strict-then-GBK-fallback approach, which
# failed when corruption had already produced "valid UTF-8 garbage" that
# passed the strict check.
$LATIN1 = [System.Text.Encoding]::GetEncoding(28591)

function Set-InstructionsFile($ConfigPath) {
    $line = 'model_instructions_file = "system-prompt.md"'
    if (!(Test-Path $ConfigPath)) {
        return (Write-Utf8NoBom $ConfigPath ($line + "`n"))
    }
    $raw = [System.IO.File]::ReadAllBytes($ConfigPath)
    $text = $LATIN1.GetString($raw)
    if ($text -match '(?m)^model_instructions_file\s*=\s*"system-prompt\.md"') { return $true }
    $lines = $text -split "`r?`n"
    $kept = @($lines | Where-Object { $_ -notmatch '^\s*model_instructions_file\s*=' })
    $content = $line + "`n" + ($kept -join "`n")
    if (!$content.EndsWith("`n")) { $content += "`n" }
    [System.IO.File]::WriteAllBytes($ConfigPath, $LATIN1.GetBytes($content))
    return $true
}

function Remove-InstructionsFile($ConfigPath) {
    if (!(Test-Path $ConfigPath)) { return 'absent' }
    $raw = [System.IO.File]::ReadAllBytes($ConfigPath)
    $text = $LATIN1.GetString($raw)
    $lines = $text -split "`r?`n"
    $kept = @($lines | Where-Object { $_ -notmatch '^\s*model_instructions_file\s*=' })
    $hasContent = $false
    foreach ($l in $kept) { if ($l -match '\S') { $hasContent = $true; break } }
    if ($hasContent) {
        $content = ($kept -join "`n")
        if (!$content.EndsWith("`n")) { $content += "`n" }
        [System.IO.File]::WriteAllBytes($ConfigPath, $LATIN1.GetBytes($content))
        return 'kept'
    }
    Remove-Item $ConfigPath -Force -ErrorAction SilentlyContinue
    return 'removed'
}

function Deploy-RelayProvider($ConfigPath, $ApiUrl, $ApiKey, $Model) {
    if (!(Test-Path $ConfigPath)) { return }
    $raw = [System.IO.File]::ReadAllBytes($ConfigPath)
    $text = $LATIN1.GetString($raw)
    $lines = $text -split "`r?`n"
    $kept = [System.Collections.ArrayList]::new()
    $skip = $false
    foreach ($l in $lines) {
        if ($l -match '^\[model_providers\.cc_unlock_relay\]') { $skip = $true; continue }
        if ($skip -and $l -match '^\[') { $skip = $false }
        if (!$skip) { [void]$kept.Add($l) }
    }
    $block = @(
        ''
        '[model_providers.cc_unlock_relay]'
        "name = `"cc-unlock Relay`""
        "base_url = `"$ApiUrl`""
        'wire_api = "responses"'
        'requires_openai_auth = false'
    )
    if ($ApiKey) { $block += "api_key = `"$ApiKey`"" }
    if ($Model) { $block += "model = `"$Model`"" }
    $content = ($kept -join "`n") + ($block -join "`n") + "`n"
    [System.IO.File]::WriteAllBytes($ConfigPath, $LATIN1.GetBytes($content))
}

function Remove-RelayProvider($ConfigPath) {
    if (!(Test-Path $ConfigPath)) { return }
    $raw = [System.IO.File]::ReadAllBytes($ConfigPath)
    $text = $LATIN1.GetString($raw)
    if ($text -notmatch '\[model_providers\.cc_unlock_relay\]') { return }
    $lines = $text -split "`r?`n"
    $kept = [System.Collections.ArrayList]::new()
    $skip = $false
    foreach ($l in $lines) {
        if ($l -match '^\[model_providers\.cc_unlock_relay\]') { $skip = $true; continue }
        if ($skip -and $l -match '^\[') { $skip = $false }
        if (!$skip) { [void]$kept.Add($l) }
    }
    $content = ($kept -join "`n")
    if (!$content.EndsWith("`n")) { $content += "`n" }
    [System.IO.File]::WriteAllBytes($ConfigPath, $LATIN1.GetBytes($content))
}

function Deploy-Codex-Config {
    Write-Host ''
    Write-Host '--- Codex ---' -ForegroundColor Cyan
    if (!(Test-Path $CODEX_BUNDLE)) {
        Write-Host '  [skip] Codex bundle not found' -ForegroundColor DarkGray
        return
    }
    if (!(Test-Path $CODEX_DIR)) {
        New-Item -ItemType Directory -Path $CODEX_DIR -Force | Out-Null
    }
    # AGENTS.md — 主人格载体,叠加在 Codex 内置 base instructions 之上(不替换)。
    # 不用 model_instructions_file 替换 base:那会顶掉内置操作守则、卡死桌面版 startup。
    $agentsSrc = Join-Path $CODEX_BUNDLE 'AGENTS.md'
    if (Test-Path $agentsSrc) {
        $agentsDst = Join-Path $CODEX_DIR 'AGENTS.md'
        if (Copy-Safe $agentsSrc $agentsDst) {
            $sz = (Get-Item $agentsDst).Length
            Write-Host "  [ok] AGENTS.md ($sz bytes) - persona" -ForegroundColor Green
        } else {
            Write-Host '  [FAIL] AGENTS.md' -ForegroundColor Red
        }
    }
    # config.toml — 移除 model_instructions_file(旧版遗留会替换 base prompt,修复启动),保留其它键
    $configPath = Join-Path $CODEX_DIR 'config.toml'
    switch (Remove-InstructionsFile $configPath) {
        'removed' { Write-Host '  [ok] config.toml - removed model_instructions_file' -ForegroundColor Green }
        'kept'    { Write-Host '  [ok] config.toml - base prompt intact (removed model_instructions_file, kept rest)' -ForegroundColor Green }
        default   { Write-Host '  [ok] config.toml - base prompt intact' -ForegroundColor DarkGray }
    }
    # legacy system-prompt.md 现由 AGENTS.md 承载,不再引用 —— 清理
    $legacySp = Join-Path $CODEX_DIR 'system-prompt.md'
    if (Test-Path $legacySp) {
        Remove-Item $legacySp -Force -ErrorAction SilentlyContinue
        Write-Host '  [ok] cleaned legacy system-prompt.md' -ForegroundColor DarkGray
    }
    if ($RelayUrl) {
        Deploy-RelayProvider $configPath $RelayUrl $RelayKey $RelayModel
        Write-Host "  [ok] Relay provider: $RelayUrl" -ForegroundColor Green
    }
    Deploy-Codex-Skills

}

function Deploy-Codex-Skills {
    if (!$SkipSkill) { Copy-BundleTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $CODEX_DIR 'skills\sec-forge') }
}

function Uninstall-Codex-Config {
    if (!(Test-Path $CODEX_DIR)) { return }
    Write-Host ''
    Write-Host '--- Codex ---' -ForegroundColor Cyan
    foreach ($f in @('system-prompt.md', 'AGENTS.md')) {
        $p = Join-Path $CODEX_DIR $f
        if (Test-Path $p) {
            Remove-Item $p -Force -ErrorAction SilentlyContinue
            Write-Host "  [ok] Removed $f" -ForegroundColor Yellow
        }
    }
    $cfgPath = Join-Path $CODEX_DIR 'config.toml'
    Remove-RelayProvider $cfgPath
    switch (Remove-InstructionsFile $cfgPath) {
        'removed' { Write-Host '  [ok] Removed config.toml' -ForegroundColor Yellow }
        'kept'    { Write-Host '  [ok] config.toml (kept other settings)' -ForegroundColor DarkGray }
    }
    Uninstall-Codex-Skills

}

function Uninstall-Codex-Skills {
    Remove-MatchingTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $CODEX_DIR 'skills\sec-forge')
}

function Verify-Codex-Config {
    $src = Join-Path $CODEX_BUNDLE 'AGENTS.md'
    $dst = Join-Path $CODEX_DIR 'AGENTS.md'
    if (!(Test-SameFile $src $dst)) { throw 'Codex AGENTS.md is missing or differs from bundle' }
    $cfg = Join-Path $CODEX_DIR 'config.toml'
    if ((Test-Path -LiteralPath $cfg) -and ([IO.File]::ReadAllText($cfg) -match '(?m)^\s*model_instructions_file\s*=')) {
        throw 'Codex config still overrides its base instructions'
    }
    Write-Host '[OK] Codex AGENTS.md; no memory/rollout management'
}

# --- Pi functions ---
# pi = @earendil-works/pi-coding-agent; agent dir defaults to ~/.pi/agent.
# Persona rides on <agent-dir>/AGENTS.md — an overlay on Pi's built-in system prompt.
# SYSTEM.md is deliberately NOT written: it replaces Pi's default system prompt outright.
function Deploy-Pi-Skills {
    if (!$SkipSkill) { Copy-BundleTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $PI_DIR 'skills\sec-forge') }
}

function Uninstall-Pi-Skills {
    Remove-MatchingTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $PI_DIR 'skills\sec-forge')
}

function Deploy-Pi-Config {
    Write-Host ''
    Write-Host '--- Pi ---' -ForegroundColor Cyan
    if (!(Test-Path $PI_BUNDLE)) {
        Write-Host '  [skip] Pi bundle not found' -ForegroundColor DarkGray
        return
    }
    if (!(Test-Path $PI_DIR)) {
        New-Item -ItemType Directory -Path $PI_DIR -Force | Out-Null
    }
    $src = Join-Path $PI_BUNDLE 'AGENTS.md'
    $dst = Join-Path $PI_DIR 'AGENTS.md'
    if (!(Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing Pi AGENTS.md bundle: $src" }
    Assert-NoReparse $dst
    if ((Test-Path -LiteralPath $dst) -and !(Test-SameFile $src $dst) -and !$Force) {
        throw 'Existing ~/.pi/agent/AGENTS.md differs. Inspect it first; use -Force to replace explicitly.'
    }
    if (Copy-Safe $src $dst) {
        Write-Host "  [ok] AGENTS.md ($((Get-Item $dst).Length) bytes) - persona overlay" -ForegroundColor Green
    } else {
        Write-Host '  [FAIL] AGENTS.md' -ForegroundColor Red
    }
    # SYSTEM.md replaces Pi's default system prompt — never write it.
    Write-Host '  [ok] SYSTEM.md untouched (base prompt intact)' -ForegroundColor DarkGray
    Deploy-Pi-Skills
}

function Uninstall-Pi-Config {
    if (!(Test-Path $PI_DIR)) { return }
    Write-Host ''
    Write-Host '--- Pi ---' -ForegroundColor Cyan
    $src = Join-Path $PI_BUNDLE 'AGENTS.md'
    $dst = Join-Path $PI_DIR 'AGENTS.md'
    if (Test-SameFile $src $dst) {
        Remove-Item -LiteralPath $dst -Force
        Write-Host '  [ok] Removed AGENTS.md' -ForegroundColor Yellow
    } else {
        Write-Host '  [KEEP] AGENTS.md absent or user-modified' -ForegroundColor DarkGray
    }
    Uninstall-Pi-Skills
    Write-Host '  [ok] SYSTEM.md untouched'
}

function Verify-Pi-Config {
    if (!(Test-SameFile (Join-Path $PI_BUNDLE 'AGENTS.md') (Join-Path $PI_DIR 'AGENTS.md'))) {
        throw 'Pi AGENTS.md is missing or differs from bundle'
    }
    if (!$SkipSkill) {
        $src = Join-Path $SKILL_BUNDLE 'sec-forge'
        $base = [IO.Path]::GetFullPath($src).TrimEnd('\') + '\'
        foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File)) {
            $dst = Join-Path (Join-Path $PI_DIR 'skills\sec-forge') $f.FullName.Substring($base.Length)
            if (!(Test-SameFile $f.FullName $dst)) { throw "Skill mismatch: $dst" }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $PI_DIR 'SYSTEM.md')) {
        Write-Host '  [warn] SYSTEM.md present - it replaces Pi base prompt' -ForegroundColor Yellow
    }
    Write-Host '[OK] Pi AGENTS.md + sec-forge; base system prompt untouched'
}

# --- omp functions ---
# omp = oh-my-pi (fork of pi); agent dir defaults to ~/.omp/agent.
# Carriers: AGENTS.md (context overlay) + RULES.md (sticky always-apply rules)
#           + skills/. SYSTEM.md is deliberately NOT written — it replaces omp's
#           default system prompt outright.
function Deploy-Omp-Skills {
    if (!$SkipSkill) { Copy-BundleTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $OMP_DIR 'skills\sec-forge') }
}

function Uninstall-Omp-Skills {
    Remove-MatchingTree (Join-Path $SKILL_BUNDLE 'sec-forge') (Join-Path $OMP_DIR 'skills\sec-forge')
}

function Deploy-Omp-Config {
    Write-Host ''
    Write-Host '--- omp ---' -ForegroundColor Cyan
    if (!(Test-Path $OMP_BUNDLE)) {
        Write-Host '  [skip] omp bundle not found' -ForegroundColor DarkGray
        return
    }
    if (!(Test-Path $OMP_DIR)) {
        New-Item -ItemType Directory -Path $OMP_DIR -Force | Out-Null
    }
    foreach ($pair in @(@{ Name = 'AGENTS.md'; Label = 'persona overlay' }, @{ Name = 'RULES.md'; Label = 'sticky rules' })) {
        $src = Join-Path $OMP_BUNDLE $pair.Name
        $dst = Join-Path $OMP_DIR $pair.Name
        if (!(Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing omp bundle file: $src" }
        Assert-NoReparse $dst
        if ((Test-Path -LiteralPath $dst) -and !(Test-SameFile $src $dst) -and !$Force) {
            throw "Existing $dst differs. Inspect it first; use -Force to replace explicitly."
        }
        if (Copy-Safe $src $dst) {
            Write-Host "  [ok] $($pair.Name) ($((Get-Item $dst).Length) bytes) - $($pair.Label)" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] $($pair.Name)" -ForegroundColor Red
        }
    }
    Write-Host '  [ok] SYSTEM.md untouched (base prompt intact)' -ForegroundColor DarkGray
    Deploy-Omp-Skills
}

function Uninstall-Omp-Config {
    if (!(Test-Path $OMP_DIR)) { return }
    Write-Host ''
    Write-Host '--- omp ---' -ForegroundColor Cyan
    foreach ($name in @('AGENTS.md', 'RULES.md')) {
        $src = Join-Path $OMP_BUNDLE $name
        $dst = Join-Path $OMP_DIR $name
        if (Test-SameFile $src $dst) {
            Remove-Item -LiteralPath $dst -Force
            Write-Host "  [ok] Removed $name" -ForegroundColor Yellow
        } else {
            Write-Host "  [KEEP] $name absent or user-modified" -ForegroundColor DarkGray
        }
    }
    Uninstall-Omp-Skills
    Write-Host '  [ok] SYSTEM.md untouched'
}

function Verify-Omp-Config {
    foreach ($name in @('AGENTS.md', 'RULES.md')) {
        if (!(Test-SameFile (Join-Path $OMP_BUNDLE $name) (Join-Path $OMP_DIR $name))) {
            throw "omp $name is missing or differs from bundle"
        }
    }
    if (!$SkipSkill) {
        $src = Join-Path $SKILL_BUNDLE 'sec-forge'
        $base = [IO.Path]::GetFullPath($src).TrimEnd('\') + '\'
        foreach ($f in @(Get-ChildItem -LiteralPath $src -Recurse -File)) {
            $dst = Join-Path (Join-Path $OMP_DIR 'skills\sec-forge') $f.FullName.Substring($base.Length)
            if (!(Test-SameFile $f.FullName $dst)) { throw "Skill mismatch: $dst" }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $OMP_DIR 'SYSTEM.md')) {
        Write-Host '  [warn] SYSTEM.md present - it replaces omp base prompt' -ForegroundColor Yellow
    }
    Write-Host '[OK] omp AGENTS.md + RULES.md + sec-forge; base system prompt untouched'
}

try {
    if ($Mode) {
        switch ($Mode.ToLowerInvariant()) {
            'deploy' { } 'install' { } 'uninstall' { $Uninstall = $true }
            'remove' { $Uninstall = $true } 'verify' { $Verify = $true }
            'list' { $List = $true } 'all' { $All = $true }
            'gui' { $GUI = $true } 'codex' { $Codex = $true } 'pi' { $Pi = $true } 'omp' { $Omp = $true }
            default { throw "Unknown -Mode: $Mode" }
        }
    }
    Write-Host 'cc-unlock v2.4-alpha | CLAUDE.md + sec-forge | no Desktop patch'
    if ($All) { throw '-All is disabled: encoded Claude project names are not reliable workspace paths. Use -Path.' }
    if ($GUI) { throw '-GUI legacy launcher is disabled. Use the v2.4 Claude application or -Path.' }
    if ($SkipSettings) { Write-Host '[INFO] -SkipSettings is obsolete; global Claude settings are always preserved.' }
    if ($List) {
        Write-Host 'Historical project IDs (not deployment destinations):'
        if (Test-Path -LiteralPath $CLAUDE_PROJECTS) { Get-ChildItem -LiteralPath $CLAUDE_PROJECTS -Directory | ForEach-Object { Write-Host $_.Name } }
        exit 0
    }
    if ($Codex) {
        if ($Uninstall) { Uninstall-Codex-Config }
        elseif ($Verify) { Verify-Codex-Config }
        else { Deploy-Codex-Config }
        exit 0
    }
    if ($Pi) {
        if ($Uninstall) { Uninstall-Pi-Config }
        elseif ($Verify) { Verify-Pi-Config }
        else { Deploy-Pi-Config }
        exit 0
    }
    if ($Omp) {
        if ($Uninstall) { Uninstall-Omp-Config }
        elseif ($Verify) { Verify-Omp-Config }
        else { Deploy-Omp-Config }
        exit 0
    }
    if (!$Path) {
        Write-Host 'Usage: .\deploy.ps1 -Path WORKSPACE [-Force|-Verify|-Uninstall] [-SkipSkill]'
        Write-Host 'Codex is separate: .\deploy.ps1 -Codex [-Verify|-Uninstall]'
        Write-Host 'Pi is separate:    .\deploy.ps1 -Pi    [-Verify|-Uninstall]'
        Write-Host 'omp is separate:   .\deploy.ps1 -Omp   [-Verify|-Uninstall]'
        exit 0
    }
    if (!(Test-Path -LiteralPath $Path -PathType Container)) { throw "Workspace not found: $Path" }
    $workspace = (Resolve-Path -LiteralPath $Path).Path
    Assert-NoReparse $workspace
    if ($Uninstall) { Remove-Claude $workspace }
    elseif ($Verify) { Verify-Claude $workspace }
    else { Deploy-Claude $workspace }
    exit 0
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    exit 1
}
