#Requires -Version 5.1
<#
.SYNOPSIS
    peon-ping installer for Windows.
.DESCRIPTION
    Installs the peon-ping Claude Code hook on Windows.
    Supports both local (from git clone) and remote (irm | iex) installation.
.EXAMPLE
    # Local install (from cloned repo)
    .\install.ps1

    # Remote one-liner
    irm https://raw.githubusercontent.com/tonyyont/peon-ping/main/install.ps1 | iex
#>

$ErrorActionPreference = "Stop"

# ─── Branding ───────────────────────────────────────────────────────────────────
$Banner = @"

  ____                          ____  _
 |  _ \ ___  ___  _ __        |  _ \(_)_ __   __ _
 | |_) / _ \/ _ \| '_ \ ___  | |_) | | '_ \ / _`` |
 |  __/  __/ (_) | | | |___| |  __/| | | | | (_| |
 |_|   \___|\___/|_| |_|     |_|   |_|_| |_|\__, |
                                              |___/
  "Ready to work!" - Windows Installer

"@
Write-Host $Banner -ForegroundColor Yellow

# ─── Prerequisites ──────────────────────────────────────────────────────────────
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Cyan

if ($env:OS -ne "Windows_NT") {
    Write-Error "This installer is for Windows only."
    exit 1
}

if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell 5.1 or later is required. Current: $($PSVersionTable.PSVersion)"
    exit 1
}

$ClaudeDir = Join-Path $env:USERPROFILE ".claude"
if (-not (Test-Path $ClaudeDir)) {
    Write-Error "Claude Code not found. Expected directory: $ClaudeDir"
    Write-Host "Install Claude Code first: https://claude.ai/code" -ForegroundColor Yellow
    exit 1
}

Write-Host "  Windows OK, PowerShell $($PSVersionTable.PSVersion), Claude Code found." -ForegroundColor Green

# ─── Constants ──────────────────────────────────────────────────────────────────
$InstallDir   = Join-Path (Join-Path (Join-Path $env:USERPROFILE ".claude") "hooks") "peon-ping"
$PacksDir     = Join-Path $InstallDir "packs"
$SettingsFile = Join-Path $ClaudeDir "settings.json"
$ConfigFile   = Join-Path $InstallDir "config.json"
$StateFile    = Join-Path $InstallDir ".state.json"

$GithubRepo   = "tonyyont/peon-ping"
$GithubBranch = "main"
$GithubRawBase = "https://raw.githubusercontent.com/$GithubRepo/$GithubBranch"

$SoundPacks = @("peon", "peon_fr", "peasant", "peasant_fr", "ra2_soviet_engineer", "sc_battlecruiser", "sc_kerrigan")

$FilesToInstall = @("peon.ps1", "config.json", "VERSION")

# ─── Detect install mode ────────────────────────────────────────────────────────
$IsLocal = $false
$ScriptDir = $null

# When run via irm | iex, $PSScriptRoot is empty
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "peon.ps1"))) {
    $IsLocal = $true
    $ScriptDir = $PSScriptRoot
    Write-Host "  Install mode: LOCAL (from cloned repo)" -ForegroundColor DarkGray
} else {
    Write-Host "  Install mode: REMOTE (downloading from GitHub)" -ForegroundColor DarkGray
}

# ─── Detect update vs fresh install ────────────────────────────────────────────
$IsUpdate = $false
if ((Test-Path $InstallDir) -and (Test-Path $ConfigFile)) {
    $IsUpdate = $true
    Write-Host ""
    Write-Host "[*] Existing installation detected - UPDATE mode (config preserved)" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "[*] Fresh installation" -ForegroundColor Green
}

# ─── Create directories ────────────────────────────────────────────────────────
Write-Host "[2/6] Setting up directories..." -ForegroundColor Cyan

if (-not (Test-Path $InstallDir)) {
    New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
}
if (-not (Test-Path $PacksDir)) {
    New-Item -Path $PacksDir -ItemType Directory -Force | Out-Null
}
Write-Host "  Install dir: $InstallDir" -ForegroundColor DarkGray

# ─── Helper: Download file from GitHub ──────────────────────────────────────────
function Get-GithubFile {
    param(
        [string]$RelativePath,
        [string]$Destination
    )
    $url = "$GithubRawBase/$RelativePath"
    try {
        $parentDir = Split-Path $Destination -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        Write-Warning "  Failed to download: $RelativePath ($($_.Exception.Message))"
        return $false
    }
}

# ─── Install core files ────────────────────────────────────────────────────────
Write-Host "[3/6] Installing core files..." -ForegroundColor Cyan

# Backup config and state if updating
$BackupConfig = $null
$BackupState  = $null
if ($IsUpdate) {
    if (Test-Path $ConfigFile) {
        $BackupConfig = Get-Content $ConfigFile -Raw
        Write-Host "  Backed up config.json" -ForegroundColor DarkGray
    }
    if (Test-Path $StateFile) {
        $BackupState = Get-Content $StateFile -Raw
        Write-Host "  Backed up .state.json" -ForegroundColor DarkGray
    }
}

foreach ($file in $FilesToInstall) {
    # Skip config.json on update - we'll restore the backup
    if ($IsUpdate -and $file -eq "config.json") {
        Write-Host "  Skipping config.json (preserved from existing install)" -ForegroundColor DarkGray
        continue
    }

    $destPath = Join-Path $InstallDir $file

    if ($IsLocal) {
        $srcPath = Join-Path $ScriptDir $file
        if (Test-Path $srcPath) {
            Copy-Item -Path $srcPath -Destination $destPath -Force
            Write-Host "  Copied $file" -ForegroundColor Green
        } else {
            Write-Warning "  Source file not found: $srcPath"
        }
    } else {
        $ok = Get-GithubFile -RelativePath $file -Destination $destPath
        if ($ok) {
            Write-Host "  Downloaded $file" -ForegroundColor Green
        }
    }
}

# Restore config and state after update
if ($IsUpdate -and $BackupConfig) {
    Set-Content -Path $ConfigFile -Value $BackupConfig -NoNewline
    Write-Host "  Restored config.json" -ForegroundColor Green
}
if ($IsUpdate -and $BackupState) {
    Set-Content -Path $StateFile -Value $BackupState -NoNewline
    Write-Host "  Restored .state.json" -ForegroundColor Green
}

# ─── Install sound packs ───────────────────────────────────────────────────────
Write-Host "[4/6] Installing sound packs..." -ForegroundColor Cyan

foreach ($pack in $SoundPacks) {
    $packDir = Join-Path $PacksDir $pack
    $soundsDir = Join-Path $packDir "sounds"
    $manifestFile = Join-Path $packDir "manifest.json"

    if (-not (Test-Path $packDir)) {
        New-Item -Path $packDir -ItemType Directory -Force | Out-Null
    }
    if (-not (Test-Path $soundsDir)) {
        New-Item -Path $soundsDir -ItemType Directory -Force | Out-Null
    }

    if ($IsLocal) {
        $srcPackDir = Join-Path (Join-Path $ScriptDir "packs") $pack
        if (Test-Path $srcPackDir) {
            # Copy manifest
            $srcManifest = Join-Path $srcPackDir "manifest.json"
            if (Test-Path $srcManifest) {
                Copy-Item -Path $srcManifest -Destination $manifestFile -Force
            }
            # Copy sounds
            $srcSoundsDir = Join-Path $srcPackDir "sounds"
            if (Test-Path $srcSoundsDir) {
                Get-ChildItem -Path $srcSoundsDir -File | ForEach-Object {
                    Copy-Item -Path $_.FullName -Destination (Join-Path $soundsDir $_.Name) -Force
                }
            }
            $soundCount = (Get-ChildItem -Path $soundsDir -File -ErrorAction SilentlyContinue | Measure-Object).Count
            Write-Host "  Pack '$pack': $soundCount sounds" -ForegroundColor Green
        } else {
            Write-Host "  Pack '$pack': not found locally, skipping" -ForegroundColor DarkGray
        }
    } else {
        # Remote: download manifest first, then parse it for sound files
        $manifestRelPath = "packs/$pack/manifest.json"
        $ok = Get-GithubFile -RelativePath $manifestRelPath -Destination $manifestFile
        if (-not $ok) {
            Write-Host "  Pack '$pack': manifest download failed, skipping" -ForegroundColor DarkGray
            continue
        }

        try {
            $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json
            $soundFiles = @()

            # Extract all sound filenames from all categories
            $categories = $manifest.categories
            if ($categories) {
                foreach ($prop in $categories.PSObject.Properties) {
                    $catSounds = $prop.Value.sounds
                    if ($catSounds) {
                        foreach ($s in $catSounds) {
                            if ($s.file -and ($soundFiles -notcontains $s.file)) {
                                $soundFiles += $s.file
                            }
                        }
                    }
                }
            }

            $downloaded = 0
            foreach ($sf in $soundFiles) {
                $sfRelPath = "packs/$pack/sounds/$sf"
                $sfDest = Join-Path $soundsDir $sf
                $dlOk = Get-GithubFile -RelativePath $sfRelPath -Destination $sfDest
                if ($dlOk) { $downloaded++ }
            }
            Write-Host "  Pack '$pack': $downloaded sounds downloaded" -ForegroundColor Green
        } catch {
            Write-Warning "  Pack '$pack': failed to parse manifest ($($_.Exception.Message))"
        }
    }
}

# ─── Register hooks in settings.json ───────────────────────────────────────────
Write-Host "[5/6] Registering Claude Code hooks..." -ForegroundColor Cyan

$PeonScript = Join-Path $InstallDir "peon.ps1"
# Escape backslashes for JSON
$PeonScriptEscaped = $PeonScript -replace '\\', '\\\\'
$HookCommand = "powershell -ExecutionPolicy Bypass -NoProfile -File `"$PeonScriptEscaped`""

$HookEvents = @("SessionStart", "UserPromptSubmit", "Stop", "Notification")

# Load existing settings or create new
$settings = $null
if (Test-Path $SettingsFile) {
    try {
        $settingsRaw = Get-Content $SettingsFile -Raw
        $settings = $settingsRaw | ConvertFrom-Json
    } catch {
        Write-Warning "  Could not parse existing settings.json, creating backup..."
        $backupPath = "$SettingsFile.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item $SettingsFile $backupPath
        Write-Host "  Backup saved to: $backupPath" -ForegroundColor DarkGray
        $settings = New-Object PSObject
    }
} else {
    $settings = New-Object PSObject
}

# Ensure hooks object exists
if (-not ($settings.PSObject.Properties.Name -contains "hooks")) {
    $settings | Add-Member -NotePropertyName "hooks" -NotePropertyValue (New-Object PSObject)
}

$peonHookEntry = @{
    type    = "command"
    command = $HookCommand
    timeout = 10
}

$peonEventEntry = @{
    matcher = ""
    hooks   = @($peonHookEntry)
}

foreach ($eventName in $HookEvents) {
    $existingEvents = $null
    if ($settings.hooks.PSObject.Properties.Name -contains $eventName) {
        $existingEvents = @($settings.hooks.$eventName)
    }

    if ($existingEvents) {
        # Check if peon hook already registered
        $hasPeon = $false
        foreach ($entry in $existingEvents) {
            if ($entry.hooks) {
                foreach ($h in $entry.hooks) {
                    if ($h.command -and $h.command -match "peon\.ps1") {
                        $hasPeon = $true
                        # Update the command in case path changed
                        $h.command = $HookCommand
                    }
                }
            }
        }
        if (-not $hasPeon) {
            $existingEvents += $peonEventEntry
            $settings.hooks.$eventName = $existingEvents
        }
    } else {
        $settings.hooks | Add-Member -NotePropertyName $eventName -NotePropertyValue @($peonEventEntry) -Force
    }
}

# Write settings back (UTF-8 without BOM for Claude Code compatibility)
$settingsJson = $settings | ConvertTo-Json -Depth 10
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($SettingsFile, $settingsJson, $utf8NoBom)
Write-Host "  Hooks registered for: $($HookEvents -join ', ')" -ForegroundColor Green

# ─── PowerShell profile alias ──────────────────────────────────────────────────
Write-Host "[6/6] Setting up 'peon' command..." -ForegroundColor Cyan

$ProfilePath = $PROFILE.CurrentUserAllHosts
if (-not $ProfilePath) {
    $ProfilePath = $PROFILE
}

$PeonFunction = @"
function peon { & "`$env:USERPROFILE\.claude\hooks\peon-ping\peon.ps1" @args }
"@

$ProfileMarkerStart = "# >>> peon-ping >>>"
$ProfileMarkerEnd   = "# <<< peon-ping <<<"
$ProfileBlock = @"
$ProfileMarkerStart
$PeonFunction
$ProfileMarkerEnd
"@

$profileUpdated = $false
if (Test-Path $ProfilePath) {
    $profileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
    if ($profileContent -and $profileContent.Contains($ProfileMarkerStart)) {
        # Replace existing block
        $pattern = [regex]::Escape($ProfileMarkerStart) + "[\s\S]*?" + [regex]::Escape($ProfileMarkerEnd)
        $profileContent = [regex]::Replace($profileContent, $pattern, $ProfileBlock)
        Set-Content -Path $ProfilePath -Value $profileContent -NoNewline
        $profileUpdated = $true
        Write-Host "  Updated existing 'peon' function in profile" -ForegroundColor Green
    } else {
        # Append
        Add-Content -Path $ProfilePath -Value "`n$ProfileBlock"
        $profileUpdated = $true
        Write-Host "  Added 'peon' function to profile" -ForegroundColor Green
    }
} else {
    # Create profile
    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }
    Set-Content -Path $ProfilePath -Value $ProfileBlock
    $profileUpdated = $true
    Write-Host "  Created profile with 'peon' function" -ForegroundColor Green
}

Write-Host "  Profile: $ProfilePath" -ForegroundColor DarkGray

# ─── Audio test ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Testing audio..." -ForegroundColor Cyan

$TestSoundPlayed = $false
$DefaultPack = "peon"
$DefaultManifest = Join-Path (Join-Path $PacksDir $DefaultPack) "manifest.json"

if (Test-Path $DefaultManifest) {
    try {
        $manifest = Get-Content $DefaultManifest -Raw | ConvertFrom-Json
        $greetingSounds = $manifest.categories.greeting.sounds
        if ($greetingSounds -and $greetingSounds.Count -gt 0) {
            $testFile = $greetingSounds[0].file
            $testPath = Join-Path (Join-Path (Join-Path $PacksDir $DefaultPack) "sounds") $testFile
            if (Test-Path $testPath) {
                # Play a short test sound using SoundPlayer (.wav only, no volume control)
                $player = $null
                try {
                    $player = New-Object System.Media.SoundPlayer($testPath)
                    $player.Play()  # async playback
                    $TestSoundPlayed = $true
                    Start-Sleep -Milliseconds 1500
                } catch {
                    Write-Host "  Audio test skipped (SoundPlayer failed)" -ForegroundColor DarkGray
                } finally {
                    if ($player) { $player.Dispose() }
                }
            }
        }
    } catch {
        # Manifest parse failed - not critical
    }
}

if ($TestSoundPlayed) {
    Write-Host "  Audio OK!" -ForegroundColor Green
} else {
    Write-Host "  Audio test skipped (sound files not available yet)" -ForegroundColor DarkGray
}

# ─── Summary ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  peon-ping installed successfully!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Install dir : $InstallDir" -ForegroundColor White
Write-Host "  Config      : $ConfigFile" -ForegroundColor White
Write-Host "  Hooks       : $SettingsFile" -ForegroundColor White
Write-Host ""
Write-Host "  Commands:" -ForegroundColor White
Write-Host "    peon --status   Check if sounds are active" -ForegroundColor DarkGray
Write-Host "    peon --pause    Mute sounds" -ForegroundColor DarkGray
Write-Host "    peon --resume   Unmute sounds" -ForegroundColor DarkGray
Write-Host "    peon --toggle   Toggle mute" -ForegroundColor DarkGray
Write-Host ""

if ($IsUpdate) {
    Write-Host '  "Ready to work!" (updated)' -ForegroundColor Yellow
} else {
    Write-Host '  "Ready to work!"' -ForegroundColor Yellow
}
Write-Host ""
