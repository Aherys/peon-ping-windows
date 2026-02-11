#Requires -Version 5.1
# peon-ping: Warcraft III Peon voice lines for Claude Code hooks (Windows)
# Pure PowerShell - no Python dependency

# --- Resolve paths ---
$PEON_DIR = if ($env:CLAUDE_PEON_DIR) { $env:CLAUDE_PEON_DIR } else { Join-Path $env:USERPROFILE ".claude\hooks\peon-ping" }
$CONFIG = Join-Path $PEON_DIR "config.json"
$STATE = Join-Path $PEON_DIR ".state.json"
$PAUSED_FILE = Join-Path $PEON_DIR ".paused"

# --- UTF-8 no-BOM helper (avoids PS 5.1 BOM with Set-Content -Encoding UTF8) ---
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
}

# --- CLI subcommands (check BEFORE reading stdin) ---
if ($args.Count -gt 0) {
    switch ($args[0]) {
        '--pause' {
            New-Item -Path $PAUSED_FILE -ItemType File -Force | Out-Null
            Write-Output "peon-ping: sounds paused"
            exit 0
        }
        '--resume' {
            Remove-Item -Path $PAUSED_FILE -Force -ErrorAction SilentlyContinue
            Write-Output "peon-ping: sounds resumed"
            exit 0
        }
        '--toggle' {
            if (Test-Path $PAUSED_FILE) {
                Remove-Item -Path $PAUSED_FILE -Force
                Write-Output "peon-ping: sounds resumed"
            } else {
                New-Item -Path $PAUSED_FILE -ItemType File -Force | Out-Null
                Write-Output "peon-ping: sounds paused"
            }
            exit 0
        }
        '--status' {
            if (Test-Path $PAUSED_FILE) {
                Write-Output "peon-ping: paused"
            } else {
                Write-Output "peon-ping: active"
            }
            exit 0
        }
        { $_ -in '--help', '-h' } {
            Write-Output "Usage: peon --pause | --resume | --toggle | --status"
            exit 0
        }
        { $_ -like '--*' } {
            Write-Error "Unknown option: $($args[0])"
            Write-Error "Usage: peon --pause | --resume | --toggle | --status"
            exit 1
        }
    }
}

# --- Read stdin (hook event JSON) ---
# [Console]::In.ReadToEnd() is reliable across PS 5.1 and 7+ for piped stdin
try {
    $INPUT_DATA = [Console]::In.ReadToEnd()
} catch {
    $INPUT_DATA = ''
}
if ([string]::IsNullOrWhiteSpace($INPUT_DATA)) {
    exit 0
}

# --- Load config ---
$cfg = @{
    enabled                = $true
    volume                 = 0.5
    active_pack            = 'peon'
    annoyed_threshold      = 3
    annoyed_window_seconds = 10
    categories             = @{
        greeting       = $true
        acknowledge    = $true
        complete       = $true
        error          = $true
        permission     = $true
        resource_limit = $true
        annoyed        = $true
    }
}

if (Test-Path $CONFIG) {
    try {
        $jsonCfg = Get-Content $CONFIG -Raw | ConvertFrom-Json
        if ($null -ne $jsonCfg.enabled)                { $cfg.enabled = [bool]$jsonCfg.enabled }
        if ($null -ne $jsonCfg.volume)                 { $cfg.volume = [Math]::Max(0.0, [Math]::Min(1.0, [double]$jsonCfg.volume)) }
        if ($null -ne $jsonCfg.active_pack)            { $cfg.active_pack = $jsonCfg.active_pack }
        if ($null -ne $jsonCfg.annoyed_threshold)      { $cfg.annoyed_threshold = [int]$jsonCfg.annoyed_threshold }
        if ($null -ne $jsonCfg.annoyed_window_seconds) { $cfg.annoyed_window_seconds = [int]$jsonCfg.annoyed_window_seconds }
        if ($null -ne $jsonCfg.categories) {
            $catObj = $jsonCfg.categories
            foreach ($cat in @('greeting','acknowledge','complete','error','permission','resource_limit','annoyed')) {
                if ($null -ne $catObj.$cat) {
                    $cfg.categories[$cat] = [bool]$catObj.$cat
                }
            }
        }
    } catch {
        # Use defaults on parse error
    }
}

if (-not $cfg.enabled) { exit 0 }

# Sanitize active_pack: strip path separators and parent-dir traversal
$cfg.active_pack = $cfg.active_pack -replace '[\\\/]', '' -replace '\.\.', ''
if (-not $cfg.active_pack) { $cfg.active_pack = 'peon' }

$PAUSED = Test-Path $PAUSED_FILE

# --- Parse event fields ---
try {
    $eventData = $INPUT_DATA | ConvertFrom-Json
} catch {
    exit 0
}

$EVENT      = if ($eventData.hook_event_name)  { $eventData.hook_event_name }  else { '' }
$NTYPE      = if ($eventData.notification_type) { $eventData.notification_type } else { '' }
$CWD        = if ($eventData.cwd)              { $eventData.cwd }              else { '' }
$SESSION_ID = if ($eventData.session_id)       { $eventData.session_id }       else { '' }
$PERM_MODE  = if ($eventData.permission_mode)  { $eventData.permission_mode }  else { '' }

# --- State file mutex for concurrent access ---
$stateMutex = $null
try {
    $stateMutex = [System.Threading.Mutex]::new($false, "Global\PeonPingState")
    $stateMutex.WaitOne(2000) | Out-Null
} catch {
    # If mutex fails, proceed without locking (better than crashing)
    $stateMutex = $null
}

try {

# --- Load state (normalize all types for PS 5.1/7+ compat) ---
$stateObj = @{ agent_sessions = @(); prompt_timestamps = @(); last_played = @{} }
if (Test-Path $STATE) {
    try {
        $raw = Get-Content $STATE -Raw
        if ($raw) {
            $parsed = $raw | ConvertFrom-Json
            # Normalize PSCustomObject -> hashtable for last_played
            $lp = @{}
            if ($parsed.last_played -is [PSCustomObject]) {
                $parsed.last_played.PSObject.Properties | ForEach-Object { $lp[$_.Name] = $_.Value }
            } elseif ($parsed.last_played -is [hashtable]) {
                $lp = $parsed.last_played
            }
            # Normalize arrays
            $as = @()
            if ($parsed.agent_sessions) { $as = @($parsed.agent_sessions) }
            $pt = @()
            if ($parsed.prompt_timestamps) { $pt = @($parsed.prompt_timestamps) }

            $stateObj = @{
                agent_sessions    = $as
                prompt_timestamps = $pt
                last_played       = $lp
            }
        }
    } catch {
        $stateObj = @{ agent_sessions = @(); prompt_timestamps = @(); last_played = @{} }
    }
}

# --- Detect agent sessions ---
$AGENT_MODES = @('delegate')
$IS_AGENT = $false

$agentSessions = [System.Collections.Generic.List[string]]::new()
foreach ($s in @($stateObj.agent_sessions)) {
    if ($s) { $agentSessions.Add([string]$s) }
}

if ($PERM_MODE -and ($AGENT_MODES -contains $PERM_MODE)) {
    if (-not $agentSessions.Contains($SESSION_ID)) {
        $agentSessions.Add($SESSION_ID)
    }
    $IS_AGENT = $true
} elseif ($agentSessions.Contains($SESSION_ID)) {
    $IS_AGENT = $true
}

$stateObj.agent_sessions = @($agentSessions)

if ($IS_AGENT) {
    Write-Utf8File -Path $STATE -Content ($stateObj | ConvertTo-Json -Depth 10)
    exit 0
}

# --- Project name from CWD ---
$PROJECT = if ($CWD) { Split-Path $CWD -Leaf } else { 'claude' }
if (-not $PROJECT) { $PROJECT = 'claude' }
$PROJECT = $PROJECT -replace '[^\w .\-]', ''

# --- Update check (SessionStart, once/day, non-blocking) ---
if ($EVENT -eq 'SessionStart') {
    Start-Job -ScriptBlock {
        param($PeonDir)
        $ErrorActionPreference = 'SilentlyContinue'
        $CHECK_FILE = Join-Path $PeonDir ".last_update_check"
        $now = [int][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $lastCheck = 0
        if (Test-Path $CHECK_FILE) {
            $content = Get-Content $CHECK_FILE -Raw
            if ($content) { [int]::TryParse($content.Trim(), [ref]$lastCheck) | Out-Null }
        }
        if (($now - $lastCheck) -gt 86400) {
            $utf8 = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($CHECK_FILE, $now.ToString(), $utf8)
            $localVersion = ''
            $versionFile = Join-Path $PeonDir "VERSION"
            if (Test-Path $versionFile) {
                $localVersion = (Get-Content $versionFile -Raw).Trim()
            }
            try {
                $response = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/tonyyont/peon-ping/main/VERSION" -TimeoutSec 5 -UseBasicParsing
                $remoteVersion = $response.Content.Trim()
            } catch {
                $remoteVersion = ''
            }
            $updateFile = Join-Path $PeonDir ".update_available"
            if ($remoteVersion -and $localVersion -and ($remoteVersion -ne $localVersion)) {
                [System.IO.File]::WriteAllText($updateFile, $remoteVersion, $utf8)
            } else {
                Remove-Item $updateFile -Force -ErrorAction SilentlyContinue
            }
        }
    } -ArgumentList $PEON_DIR | Out-Null
}

# Show update notice
if ($EVENT -eq 'SessionStart') {
    $updateFile = Join-Path $PEON_DIR ".update_available"
    if (Test-Path $updateFile) {
        $newVer = (Get-Content $updateFile -Raw).Trim()
        $curVer = ''
        $versionFile = Join-Path $PEON_DIR "VERSION"
        if (Test-Path $versionFile) { $curVer = (Get-Content $versionFile -Raw).Trim() }
        if ($newVer) {
            Write-Host "peon-ping update available: $( if ($curVer) { $curVer } else { '?' } ) -> $newVer" -ForegroundColor Yellow
        }
    }
}

# Show pause status on SessionStart
if ($EVENT -eq 'SessionStart' -and $PAUSED) {
    Write-Host "peon-ping: sounds paused" -ForegroundColor DarkYellow
}

# --- Annoyed state detection ---
function Test-Annoyed {
    $now = [double][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() / 1000.0
    $window = [double]$cfg.annoyed_window_seconds
    $threshold = [int]$cfg.annoyed_threshold

    $timestamps = [System.Collections.Generic.List[double]]::new()
    foreach ($t in @($stateObj.prompt_timestamps)) {
        if (($now - [double]$t) -lt $window) {
            $timestamps.Add([double]$t)
        }
    }
    $timestamps.Add($now)
    $stateObj.prompt_timestamps = @($timestamps)

    if ($timestamps.Count -ge $threshold) {
        return 'annoyed'
    }
    return 'normal'
}

# --- Pick random sound ---
function Get-RandomSound {
    param([string]$Category)

    $packDir = Join-Path $PEON_DIR "packs\$($cfg.active_pack)"

    # Path traversal guard: ensure resolved path stays inside packs/
    $resolvedPack = [System.IO.Path]::GetFullPath($packDir)
    $resolvedPacks = [System.IO.Path]::GetFullPath((Join-Path $PEON_DIR "packs"))
    if (-not $resolvedPack.StartsWith($resolvedPacks, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $manifestPath = Join-Path $packDir "manifest.json"
    if (-not (Test-Path $manifestPath)) { return $null }

    try {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    } catch {
        return $null
    }

    $sounds = $manifest.categories.$Category.sounds
    if (-not $sounds -or $sounds.Count -eq 0) { return $null }

    # Avoid repeating the last played sound
    $lastFile = $stateObj.last_played[$Category]

    $candidates = @($sounds)
    if ($candidates.Count -gt 1 -and $lastFile) {
        $candidates = @($sounds | Where-Object { $_.file -ne $lastFile })
    }

    $pick = $candidates | Get-Random
    $stateObj.last_played[$Category] = $pick.file

    $soundPath = Join-Path $packDir "sounds\$($pick.file)"
    return $soundPath
}

# --- Event -> Category mapping ---
$CATEGORY = ''
$STATUS = ''
$MARKER = ''
$NOTIFY = $false
$MSG = ''
$BULLET = [char]0x25CF

switch ($EVENT) {
    'SessionStart' {
        $CATEGORY = 'greeting'
        $STATUS = 'ready'
    }
    'UserPromptSubmit' {
        # Only check annoyed state when NOT paused (avoid state mutation while paused)
        if (-not $PAUSED -and $cfg.categories['annoyed']) {
            $mood = Test-Annoyed
            if ($mood -eq 'annoyed') {
                $CATEGORY = 'annoyed'
            }
        }
        # Play acknowledge sound for normal (non-annoyed) prompts
        if (-not $CATEGORY -and $cfg.categories['acknowledge']) {
            $CATEGORY = 'acknowledge'
        }
        $STATUS = 'working'
    }
    'Stop' {
        $CATEGORY = 'complete'
        $STATUS = 'done'
        $MARKER = "$BULLET "
    }
    'Notification' {
        if ($NTYPE -eq 'permission_prompt') {
            $CATEGORY = 'permission'
            $STATUS = 'needs approval'
            $MARKER = "$BULLET "
            $NOTIFY = $true
            $MSG = "$PROJECT -- A tool is waiting for your permission"
        } elseif ($NTYPE -eq 'idle_prompt') {
            $STATUS = 'done'
            $MARKER = "$BULLET "
            $NOTIFY = $true
            $MSG = "$PROJECT -- Ready for your next instruction"
        } else {
            exit 0
        }
    }
    default { exit 0 }
}

# --- Check category enabled ---
if ($CATEGORY -and -not $cfg.categories[$CATEGORY]) {
    $CATEGORY = ''
}

# --- Tab title (PS 5.1 compatible ANSI escape) ---
$TITLE = "${MARKER}${PROJECT}: ${STATUS}"
if ($TITLE) {
    $ESC = [char]0x1B
    $BEL = [char]0x07
    [Console]::Write("${ESC}]0;${TITLE}${BEL}")
}

# --- Resolve sound file (before notifications, so state.last_played is updated) ---
$SOUND_FILE = $null
if ($CATEGORY -and -not $PAUSED) {
    $SOUND_FILE = Get-RandomSound -Category $CATEGORY
    if ($SOUND_FILE -and -not (Test-Path $SOUND_FILE)) { $SOUND_FILE = $null }
}

# --- Toast notification (always shown, even when terminal is focused) ---
if ($NOTIFY -and -not $PAUSED) {
    try {
        $AUMID = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        $template = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent(
            [Windows.UI.Notifications.ToastTemplateType]::ToastText02
        )
        $textNodes = $template.GetElementsByTagName("text")
        $textNodes.Item(0).AppendChild($template.CreateTextNode($TITLE)) | Out-Null
        $textNodes.Item(1).AppendChild($template.CreateTextNode($MSG)) | Out-Null
        $toast = [Windows.UI.Notifications.ToastNotification]::new($template)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AUMID).Show($toast)
    } catch {
        # Toast not available (older Windows, etc.) - silently ignore
    }
}

# --- Persist state (before blocking audio, so mutex is held minimally) ---
Write-Utf8File -Path $STATE -Content ($stateObj | ConvertTo-Json -Depth 10)

# --- Play sound (LAST - may block for duration of sound, <2s, within 10s hook timeout) ---
if ($SOUND_FILE) {
    $ext = [System.IO.Path]::GetExtension($SOUND_FILE).ToLowerInvariant()
    if ($ext -eq '.wav') {
        # SoundPlayer.PlaySync(): blocks until done, ensures full playback before exit.
        # Mirrors macOS `wait` at end of peon.sh. Peon lines are <2s.
        try {
            $player = New-Object System.Media.SoundPlayer($SOUND_FILE)
            $player.PlaySync()
        } catch {
            # Silently ignore audio errors
        }
    } else {
        # MP3/other: STA runspace with WPF MediaPlayer (supports volume control).
        # Invoke() blocks until script finishes (includes sleep for playback).
        try {
            $vol = [double]$cfg.volume
            $rs = [RunspaceFactory]::CreateRunspace()
            $rs.ApartmentState = [System.Threading.ApartmentState]::STA
            $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
            $rs.Open()
            $ps = [PowerShell]::Create()
            $ps.Runspace = $rs
            $ps.AddScript({
                param($path, $vol)
                Add-Type -AssemblyName PresentationCore
                $player = New-Object System.Windows.Media.MediaPlayer
                $player.Volume = $vol
                $player.Open([Uri]::new($path))
                $player.Play()
                Start-Sleep -Seconds 3
                $player.Close()
            }).AddArgument($SOUND_FILE).AddArgument($vol) | Out-Null
            $ps.Invoke() | Out-Null
            $ps.Dispose()
            $rs.Dispose()
        } catch {
            # Silently ignore audio errors
        }
    }
}

} finally {
    # Release state mutex
    if ($stateMutex) {
        try { $stateMutex.ReleaseMutex() } catch {}
        $stateMutex.Dispose()
    }
}

exit 0
