# Downloads sound packs from the original peon-ping repo
$ErrorActionPreference = "Stop"
$base = "https://raw.githubusercontent.com/tonyyont/peon-ping/main/packs"

$packs = @{
    "peon" = @("PeonAngry1.wav","PeonAngry2.wav","PeonAngry3.wav","PeonAngry4.wav","PeonDeath.wav","PeonReady1.wav","PeonWarcry1.wav","PeonWhat1.wav","PeonWhat2.wav","PeonWhat3.wav","PeonWhat4.wav","PeonYes1.wav","PeonYes2.wav","PeonYes3.wav","PeonYes4.wav","PeonYesAttack1.wav","PeonYesAttack2.wav","PeonYesAttack3.wav")
    "peon_fr" = @("PeonPissed1.wav","PeonPissed2.wav","PeonPissed3.wav","PeonPissed4.wav","PeonReady1.wav","PeonWarcry1.wav","PeonWhat1.wav","PeonWhat2.wav","PeonWhat3.wav","PeonWhat4.wav","PeonYes1.wav","PeonYes2.wav","PeonYes3.wav","PeonYes4.wav","PeonYesAttack1.wav","PeonYesAttack2.wav","PeonYesAttack3.wav")
    "peasant" = @("PeasantAngry1.wav","PeasantAngry2.wav","PeasantAngry3.wav","PeasantAngry4.wav","PeasantAngry5.wav","PeasantDeath.wav","PeasantReady1.wav","PeasantWarcry1.wav","PeasantWhat1.wav","PeasantWhat2.wav","PeasantWhat3.wav","PeasantWhat4.wav","PeasantYes1.wav","PeasantYes2.wav","PeasantYes3.wav","PeasantYes4.wav","PeasantYesAttack1.wav","PeasantYesAttack2.wav","PeasantYesAttack3.wav","PeasantYesAttack4.wav")
    "peasant_fr" = @("PeasantPissed1.wav","PeasantPissed2.wav","PeasantPissed3.wav","PeasantPissed4.wav","PeasantPissed5.wav","PeasantReady1.wav","PeasantWarcry1.wav","PeasantWhat1.wav","PeasantWhat2.wav","PeasantWhat3.wav","PeasantWhat4.wav","PeasantYes1.wav","PeasantYes2.wav","PeasantYes3.wav","PeasantYes4.wav","PeasantYesAttack1.wav","PeasantYesAttack2.wav","PeasantYesAttack3.wav","PeasantYesAttack4.wav")
    "ra2_soviet_engineer" = @("CheckingDesigns.mp3","Engineering.mp3","ExaminingDiagrams.mp3","GetMeOuttaHere.mp3","Information.mp3","PowerUp.mp3","ToolsReady.mp3","YesCommander.mp3")
    "sc_battlecruiser" = @("AllCrewsReporting.mp3","BattlecruiserOperational.mp3","BuckleUp.mp3","Engage.mp3","GoodDayCommander.mp3","HailingFrequenciesOpen.mp3","IdentifyYourself.mp3","MakeItHappen.mp3","ReallyHaveToGo.mp3","ReceivingTransmission.mp3","SetACourse.mp3","ShieldsUp.mp3","TakeItSlow.mp3","WayBehindSchedule.mp3","WeaponsOnline.mp3")
    "sc_kerrigan" = @("AnnoyingPeople.mp3","BeAPleasure.mp3","Death1.mp3","Death2.mp3","EasilyAmused.mp3","GotAJobToDo.mp3","IGotcha.mp3","IReadYou.mp3","ImReady.mp3","KerriganReporting.mp3","Telepath.mp3","ThinkingSameThing.mp3","WaitingOnYou.mp3","WhatNow.mp3")
}

$total = 0
foreach ($pack in $packs.Keys) {
    $dir = Join-Path (Join-Path (Join-Path $PSScriptRoot "packs") $pack) "sounds"
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

    # Download manifest
    $manifestUrl = "$base/$pack/manifest.json"
    $manifestDest = Join-Path (Join-Path (Join-Path $PSScriptRoot "packs") $pack) "manifest.json"
    try {
        Invoke-WebRequest -Uri $manifestUrl -OutFile $manifestDest -UseBasicParsing
    } catch {
        Write-Host "  SKIP manifest: $pack" -ForegroundColor Yellow
    }

    # Download sounds
    foreach ($f in $packs[$pack]) {
        $url = "$base/$pack/sounds/$f"
        $dest = Join-Path $dir $f
        try {
            Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
            $total++
        } catch {
            Write-Host "  SKIP: $pack/$f" -ForegroundColor Yellow
        }
    }
    $count = (Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Measure-Object).Count
    Write-Host "Pack '$pack': $count sounds" -ForegroundColor Green
}
Write-Host "`nTotal: $total sound files downloaded" -ForegroundColor Cyan
