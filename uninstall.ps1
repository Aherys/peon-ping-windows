#Requires -Version 5.1
<#
.SYNOPSIS
    peon-ping uninstaller for Windows.
.DESCRIPTION
    Removes the peon-ping Claude Code hook from Windows.
    Cleans up hooks from settings.json, removes profile alias, and deletes install directory.
.EXAMPLE
    .\uninstall.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  peon-ping Uninstaller" -ForegroundColor Yellow
Write-Host "  =====================" -ForegroundColor Yellow
Write-Host ""

# ─── Constants ──────────────────────────────────────────────────────────────────
$ClaudeDir    = Join-Path $env:USERPROFILE ".claude"
$InstallDir   = Join-Path (Join-Path $ClaudeDir "hooks") "peon-ping"
$SettingsFile = Join-Path $ClaudeDir "settings.json"

# ─── Check if installed ────────────────────────────────────────────────────────
if (-not (Test-Path $InstallDir)) {
    Write-Host "  peon-ping is not installed." -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

Write-Host "[1/4] Removing hooks from settings.json..." -ForegroundColor Cyan

# ─── Remove hook entries from settings.json ─────────────────────────────────────
if (Test-Path $SettingsFile) {
    try {
        $settingsRaw = Get-Content $SettingsFile -Raw
        $settings = $settingsRaw | ConvertFrom-Json

        if ($settings.PSObject.Properties.Name -contains "hooks") {
            $HookEvents = @("SessionStart", "UserPromptSubmit", "Stop", "Notification")
            $modified = $false

            foreach ($eventName in $HookEvents) {
                if ($settings.hooks.PSObject.Properties.Name -contains $eventName) {
                    $eventEntries = @($settings.hooks.$eventName)
                    $filtered = @()

                    foreach ($entry in $eventEntries) {
                        $keepEntry = $true
                        if ($entry.hooks) {
                            # Filter out hooks containing peon.ps1
                            $filteredHooks = @()
                            foreach ($h in $entry.hooks) {
                                if ($h.command -and $h.command -match "peon\.ps1") {
                                    # Skip this hook - it's ours
                                    $modified = $true
                                } else {
                                    $filteredHooks += $h
                                }
                            }

                            if ($filteredHooks.Count -eq 0) {
                                # No hooks left in this entry, drop the whole entry
                                $keepEntry = $false
                            } else {
                                $entry.hooks = $filteredHooks
                            }
                        }

                        if ($keepEntry) {
                            $filtered += $entry
                        }
                    }

                    if ($filtered.Count -eq 0) {
                        # Remove the event entirely if no entries remain
                        $settings.hooks.PSObject.Properties.Remove($eventName)
                        $modified = $true
                    } else {
                        $settings.hooks.$eventName = $filtered
                    }
                }
            }

            # Remove hooks object entirely if empty
            if (($settings.hooks.PSObject.Properties | Measure-Object).Count -eq 0) {
                $settings.PSObject.Properties.Remove("hooks")
                $modified = $true
            }

            if ($modified) {
                $settingsJson = $settings | ConvertTo-Json -Depth 10
                $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
                [System.IO.File]::WriteAllText($SettingsFile, $settingsJson, $utf8NoBom)
                Write-Host "  Hooks removed from settings.json" -ForegroundColor Green
            } else {
                Write-Host "  No peon hooks found in settings.json" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  No hooks section in settings.json" -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "  Could not parse settings.json: $($_.Exception.Message)"
        Write-Host "  You may need to manually remove peon entries from: $SettingsFile" -ForegroundColor Yellow
    }
} else {
    Write-Host "  settings.json not found, nothing to clean" -ForegroundColor DarkGray
}

# ─── Check for notify.sh backup ────────────────────────────────────────────────
Write-Host "[2/4] Checking for backups..." -ForegroundColor Cyan

$NotifyBackup = Join-Path $InstallDir "notify.sh.bak"
if (Test-Path $NotifyBackup) {
    Write-Host "  Found notify.sh backup: $NotifyBackup" -ForegroundColor Yellow
    $restore = Read-Host "  Restore notify.sh backup? (y/N)"
    if ($restore -eq "y" -or $restore -eq "Y") {
        $hooksDir = Join-Path $ClaudeDir "hooks"
        $notifyDest = Join-Path $hooksDir "notify.sh"
        Copy-Item -Path $NotifyBackup -Destination $notifyDest -Force
        Write-Host "  Restored notify.sh" -ForegroundColor Green
    } else {
        Write-Host "  Backup not restored" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  No backups found" -ForegroundColor DarkGray
}

# ─── Remove install directory ───────────────────────────────────────────────────
Write-Host "[3/4] Removing install directory..." -ForegroundColor Cyan

try {
    Remove-Item -Path $InstallDir -Recurse -Force
    Write-Host "  Removed: $InstallDir" -ForegroundColor Green
} catch {
    Write-Warning "  Could not fully remove $InstallDir : $($_.Exception.Message)"
    Write-Host "  You may need to manually delete this directory." -ForegroundColor Yellow
}

# ─── Remove profile alias ──────────────────────────────────────────────────────
Write-Host "[4/4] Cleaning PowerShell profile..." -ForegroundColor Cyan

$ProfilePath = $PROFILE.CurrentUserAllHosts
if (-not $ProfilePath) {
    $ProfilePath = $PROFILE
}

$ProfileMarkerStart = "# >>> peon-ping >>>"
$ProfileMarkerEnd   = "# <<< peon-ping <<<"

if (Test-Path $ProfilePath) {
    $profileContent = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
    if ($profileContent -and $profileContent.Contains($ProfileMarkerStart)) {
        $pattern = [regex]::Escape($ProfileMarkerStart) + "[\s\S]*?" + [regex]::Escape($ProfileMarkerEnd)
        $profileContent = [regex]::Replace($profileContent, $pattern, "")
        # Clean up extra blank lines left behind
        $profileContent = [regex]::Replace($profileContent, "`n{3,}", "`n`n")
        $profileContent = $profileContent.TrimEnd()
        if ($profileContent) {
            Set-Content -Path $ProfilePath -Value $profileContent -NoNewline
        } else {
            # Profile is now empty, remove it
            Remove-Item -Path $ProfilePath -Force
        }
        Write-Host "  Removed 'peon' function from profile" -ForegroundColor Green
    } else {
        Write-Host "  No peon function found in profile" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  Profile not found, nothing to clean" -ForegroundColor DarkGray
}

# ─── Done ───────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================" -ForegroundColor Yellow
Write-Host "  peon-ping uninstalled successfully." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Yellow
Write-Host ""
Write-Host '  "Me go now."' -ForegroundColor Yellow
Write-Host ""
