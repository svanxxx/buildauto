$TempCleanUp = $false
$BuildCleanUp = $false
$GitSync = $false
$Rebuild = $false

$DSN = "FIELDPRO_BLANK_DATABASE"
$workdir = "Y:\";
$builddir = "$($workdir)Projects.32\";
$FIPPortable = "$($builddir)Release.zip";
$MXPortable = "$($builddir)Modules.zip";
$buildLibdir = "$($workdir)Release.lib\";
$buildExedir = "$($workdir)Release.exe\";
$Migrator = "$($buildExedir)MigrateDB.exe";
$mxbuildLibdir = "$($workdir)Modules.32\Release.lib\";
$mxbuildExedir = "$($workdir)Modules.32\Release.exe\";
$ExtDir = "$($workdir).Ext\";
$DbReg = "$($ExtDir)db.reg";
$bstfile = "$($workdir)Common\BSTUserName.h"
$VersionFile = "$($workdir)Common\AppVersions.h"
$temp = [System.IO.Path]::GetTempPath();
$outfile = "$($temp)buildoutput.log";
$fipoutfile = "$($temp)fipbuildoutput.log";
$cxoutfile = "$($temp)cxbuildoutput.log";

$DBZip = "$($workdir)Installs\INPUT\Database\MSSQL_ETALON.zip";
$DBForMigration = "$($workdir)Installs\INPUT\Database\MSSQL_ETALON.BAK";
$RestoreCommand = "OSQL -S (local)\SQL2014 -E -Q ""RESTORE DATABASE $($DSN) FROM DISK = '$($DBForMigration)' WITH REPLACE"""
$DBForInstall = "$($workdir)Installs\INPUT\Database\FIELDPRO_BLANK_DATABASE.BAK";
$BackupCommand = "OSQL -S (local)\SQL2014 -E -Q ""BACKUP DATABASE $($DSN) TO DISK = '$($DBForInstall)'"""

$installs = "$($workdir)Installs\OUTPUT\";
$mxinstall = "$($installs)ONSITE_MODULES_WIX\BUILD_RELEASE.bat";
$mxinstallRes = "$($installs)ONSITE_MODULES_WIX\bin\FIELDPRO_MODELS_ONSITE_REAL_TIME.msi";
$onsiteinstallRes = "$($installs)ONSITE_MODULES_WIX\bin\FIELDPRO_ONSITE.msi";
$metadatainstall = "$($installs)METADATAGENERATOR_WIX\BUILD_RELEASE.bat";
$FIPinstall = "$($installs)FIELDPRO_WIX\BUILD_RELEASE.bat";
$FIPinstallRes = "$($installs)FIELDPRO_WIX\bin\FIELDPRO.msi";
$metadatainstallRes = "$($installs)METADATAGENERATOR_WIX\bin\METADATAGENERATOR.msi";
$machine = $env:computername.ToUpper()
$vspath = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\IDE\devenv.com"
$global:__UGuid = ""
function Get-UGuid() {
    if ($global:__UGuid -eq "") {
        $u = Get-BuildUser
        $v = Get-Version
        $v1 = $v[0]
        $v2 = $v[1]
        $v3 = $v[2]
        $v4 = $v[3]
        $d = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
        $global:__UGuid = "$($u)_V$($v1).$($v2).$($v3).$($v4)_$($d)"
    }
    return $global:__UGuid
}
function Remove-File([string]$FileName) {
    if (Test-Path -Path $FileName) {
        Remove-Item -Path $FileName
    }
}
function Test-File([string]$FileName, [string]$ActionName) {
    $null = @(
        $result = $true
        if (!(Test-Path -Path $FileName)) {
            Write-State "Failed to: $($ActionName)"
            Invoke-LogAndExit -Log $outfile -Fail $true
            $result = $false
        }
    )
    return $result
}
function Invoke-Command([string]$Command) {
    cmd /c "$($Command)" | Out-File $($outfile) -Append;
}
function GetURL {
    $file = $PSScriptRoot + "\builder.ini"
    $content = Get-Content $file
    return $content
}
$URL = GetURL
$NewRequestParams = @{
    Uri    = $URL + "/api/catch?machine=" + $machine
    Method = "GET"
}
$request = $null;
function Copy-File-ToCloud([string]$FileName, [string]$Message) {
    Write-State $Message
    $md5File = $FileName + ".md5"
    Remove-File $md5File
    $hash = Get-FileHash $FileName -Algorithm MD5
    $hash.Hash | Out-File $($md5File) -Encoding ascii

    $cfg = "$($PSScriptRoot)\bin\rclone.conf"
    "[syncconfig]`r`n$($request.config)" | Out-File $($cfg) -Encoding ascii
    $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""$($FileName)"" ""syncconfig:$(Get-UGuid)"""
    cmd /c $command
    $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""$($md5File)"" ""syncconfig:$(Get-UGuid)"""
    cmd /c $command
}
function Get-BuildUser() {
    return $request.userEmail.Split("@")[0].ToUpper()
}
function Get-Version() {
    $V = "", "", "", ""
    $VM = "#define __FILEVERSION_NUMBER_FIP_2__", "#define __FILEVERSION_NUMBER_FIP_3__", "#define __MINI_DB_UPDATE_VERSION__", "#define __FILEVERSION_NUMBER_FIP_4__"
    
    Get-Content $VersionFile | ForEach-Object {
        for ($i = 0; $i -lt $VM.Length; $i++) { 
            if ($_ -match "$($VM[$i])*") {
                $V[$i] = $_.Substring($VM[$i].Length).Trim().Split("//")[0].ToUpper()
            }    
        }
    }
    return $V
}
function Write-State([string]$txt) {
    if ($txt.Length -gt 512) {
        $txt = $txt.Substring(0, 512)
    }
    
    $stamp = Get-Date -Format "HH:mm:ss"
    $out = $stamp + ": " + $txt
    $out | Out-File $($outfile) -Append;
    $CommentRequestParams = @{
        Uri    = $URL + "/api/comment?id=" + $request.id + "&comment=" + [uri]::EscapeUriString($txt)
        Method = "POST"
    }
    $request = Invoke-RestMethod @CommentRequestParams
    Write-Host $out;
}
function Invoke-Cleanup([bool]$weboutput) {
    $Null = @(
        $result = $true

        Write-Host "Cleanup..."
        Write-Host "Removing old msi files..."
        Get-ChildItem "$($installs)" -Include *.msi -Recurse | Remove-Item

        Write-Host "$(Get-Date)"
        if ($weboutput) {
            Write-State "Temp Folders Cleanup..."
        }
        $loc = Get-Location
        Set-Location $temp
        if ($TempCleanUp) {
            Remove-Item * -Recurse -Force -ErrorAction SilentlyContinue
        }
        Set-Location $loc
        if ($weboutput) {
            Write-State "Lib files cleanup..."
        }
        Remove-Item -Path "$($buildLibdir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "$($buildExedir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "$($mxbuildLibdir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "$($mxbuildExedir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "y:\.git\index.lock" -Force -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "$(Get-Date)"
        if (IsBuildCancelled) {
            $result = $false
        }
    )
    return $result
}
function IsBuildCancelled {
    $Null = @(
        $CancelledRequestParams = @{
            Uri    = $URL + "/api/cancelled?id=" + $request.id
            Method = "GET"
        }
        $answer = Invoke-RestMethod @CancelledRequestParams
        if ($answer){
            Write-State "Build Cancelled..."
        }
    )
    return $answer
}
function FailBuild {
    $FaileRequestParams = @{
        Uri    = $URL + "/api/fail?id=" + $request.id
        Method = "POST"
    }
    Invoke-RestMethod @FaileRequestParams
}
function FinishBuild {
    $FinishRequestParams = @{
        Uri    = $URL + "/api/finish?id=" + $request.id
        Method = "POST"
    }
    Invoke-RestMethod @FinishRequestParams
}
function Invoke-Code-Synch([string]$branch) {
    $Null = @(
        $result = $true

        Write-State "Pull Code ($($branch)) From Git..."
        Set-Location $($workdir);
        Invoke-Command "git reset --hard"
        Invoke-Command "git checkout master"
        Invoke-Command "git reset --hard"
        $branches = git branch
        For ($i = 0; $i -lt $branches.Length; $i++) {
            if ($branches[$i].Trim() -ne "* master") {
                git branch -D "$($branches[$i].Trim())"
            }
        }
        Invoke-Command "git fetch --all --prune"
        Invoke-Command "git checkout ""$($branch)"""
        Invoke-Command "git status"
        Invoke-Command "git pull origin"
        $currbranch = cmd /c "git rev-parse --abbrev-ref HEAD"
        if ($currbranch -ne $branch) {
            Write-Output "Error: current brach is: $($currbranch)"
            Write-Output "Expected: $($branch)"
            Write-State "Build aborted, GIT exception..."
            $result = $false
        }    
        elseif (IsBuildCancelled) {
            $result = $false
        }
    )
    return $result
}
function Invoke-LogAndExit([string]$Log, [bool]$Fail) {
    $zip = "$($temp)log.zip"
    Remove-File $zip
    Compress-Archive -Path $($Log) -DestinationPath $($zip)
    Copy-File-ToCloud $zip "Uploading log file..."
    if ($Fail) {
        FailBuild
    }
    else {
        Write-State "Finished."
        FinishBuild
    }
}
function Invoke-CodeCompilation([string]$Solution, [string]$BuildLog) {
    
    $Null = @(
        $result = $true
        $BuildType = "build"
        if ($Rebuild) {
            $BuildType = "rebuild"
        }
        Remove-Item -Path "$($BuildLog)" -Force -Confirm:$false -ErrorAction SilentlyContinue
        $buildcommand = """$($vspath)"" ""$($Solution)"" /$($BuildType) ""Release|Mixed Platforms"" /Out ""$($BuildLog)"""
        Write-State "Building code $($Solution)..."
    
        cmd /c "$($buildcommand)"
    
        $errors = 0
        $filecontent = Get-Content $($BuildLog)
        $FinalString = $filecontent | Select-String -Pattern ", 0 failed,"
        if (!$FinalString) {
            if ($filecontent | Select-String -Pattern "TRACKER : error TRK0002") {
                Write-State "re - building code after TRK0002..."
                cmd /c "$($buildcommand)"
                $filecontent = Get-Content $($BuildLog)
            }
            $builderr = $filecontent | Select-String -SimpleMatch "): error"
            if ($builderr) {
                Write-State $builderr
                $errors = 1
            }
            if ($errors -lt 1) {
                $builderr = $filecontent | Select-String -SimpleMatch "): fatal error"
                if ($builderr) {
                    Write-State $builderr
                    $errors = 1
                }
            }
            if ($errors -lt 1) {
                $builderr = $filecontent | Select-String -SimpleMatch " -- FAILED."
                if ($builderr) {
                    Write-State $builderr
                    $errors = 1
                }
            }
            if ($errors -lt 1) {
                $builderr = $filecontent | Select-String -SimpleMatch "LINK : fatal error"
                if ($builderr) {
                    Write-State $builderr
                    $errors = 1
                }
            }
            if ($errors -lt 1) {
                Write-State "Build failed - unknown error, see logs for details"
                $errors = 1
            }
        }
        if ($errors -gt 0) {
            Invoke-LogAndExit -Log $BuildLog -Fail $true
            $result = $false
        }
        elseif (IsBuildCancelled) {
            $result = $false
        }        
    )
    return $result
}
function Update-UGuid() {
    $uguid_ = Get-UGuid
    $GuidRequestParams = @{
        Uri    = $URL + "/api/uguid?id=" + $request.id + "&guid=" + $uguid_
        Method = "POST"
    }
    Invoke-RestMethod @GuidRequestParams
}
function Invoke-CodeBuilder {
    #=========================================================
    # cleanup
    #=========================================================
    Remove-File $outfile
    if ($BuildCleanUp) {
        $res = Invoke-Cleanup($true)
        if (!$res) {
            return
        }
    }
    #=========================================================
    # init
    #=========================================================
    if ($GitSync) {
        $res = Invoke-Code-Synch($request.branch)
        if (!$res) {
            return
        }
    }

    Update-UGuid

    $user = Get-BuildUser
    "#define _BSTUserName _T("".$($user)"")" | Out-File $($bstfile) -Encoding ascii

    $res = Invoke-CodeCompilation -Solution "$($builddir)All.sln" -BuildLog $fipoutfile
    if (!$res) {
        return
    }

    $res = Invoke-CodeCompilation -Solution "$($builddir)Modules.sln" -BuildLog $cxoutfile
    if (!$res) {
        return
    }

    #=======================================================
    # Preparing database
    #=======================================================

    #Write-State "Creating DSN..."
    #$dbCommand = "regedit /s ""$($DbReg)"""
    #cmd /c $dbCommand | Out-File $($outfile) -Append;

    Write-State "Extracting database..."
    Expand-Archive -LiteralPath $DBZip -DestinationPath "C:\ProgramData\Fieldpro\" -Force
    if (IsBuildCancelled) { return }
    Write-State "Restoring database..."
    Invoke-Command $RestoreCommand
    if (IsBuildCancelled) { return }

    Write-State "Migrating database..."
    $MigrateCommand = "$($Migrator) $($DSN) SkipWait"
    $MigrateCommand | Out-File $($outfile) -Append;
    Invoke-Command $MigrateCommand
    if (IsBuildCancelled) { return }
    #=======================================================
    # making mx installation
    #=======================================================
    Write-State "MX installation..."
    Remove-File $mxinstallRes
    Remove-File $onsiteinstallRes
    Invoke-Command "$($mxinstall)"
    if (IsBuildCancelled) { return }
    if (!(Test-File $mxinstallRes "MX installation build")) {
        return
    }
    Copy-File-ToCloud $mxinstallRes "Uploading MX..."
    if (IsBuildCancelled) { return }
    if (!(Test-File $onsiteinstallRes "Onsite installation build")) {
        return
    }
    Copy-File-ToCloud $onsiteinstallRes "Uploading Onsite..."
    if (IsBuildCancelled) { return }

    #=======================================================
    # making METADATA installation
    #=======================================================
    Write-State "Building metadata..."
    Remove-File $metadatainstallRes
    Invoke-Command "$($metadatainstall)"
    if (IsBuildCancelled) { return }
    if (!(Test-File $metadatainstallRes "Metadata installation build")) {
        return
    }
    Copy-File-ToCloud $metadatainstallRes "Uploading metadata..."
    if (IsBuildCancelled) { return }
    #=======================================================
    # making FIP installation
    #=======================================================
    Write-State "Backup database..."
    Remove-File $DBForInstall
    Invoke-Command $BackupCommand
    if (IsBuildCancelled) { return }
    if (!(Test-File $DBForInstall "Database backup")) {
        return
    }

    Write-State "FIP installation..."
    Remove-File $FIPinstallRes
    Invoke-Command "$($FIPinstall)"
    if (IsBuildCancelled) { return }
    if (!(Test-File $FIPinstallRes "FIP installation build")) {
        return
    }
    Copy-File-ToCloud $FIPinstallRes "Uploading FIP installation..."
    if (IsBuildCancelled) { return }

    #=======================================================
    # making FIP portable
    #=======================================================
    Write-State "Archivating FIP..."
    Remove-File $FIPPortable
    Compress-Archive -Path $($buildExedir) -DestinationPath "$($FIPPortable)"
    if (IsBuildCancelled) { return }
    Copy-File-ToCloud $FIPPortable "Uploading FIP zip..."
    if (IsBuildCancelled) { return }
    #=======================================================
    # making MX portable
    #=======================================================
    Write-State "Archivating MX..."
    Remove-File $MXPortable
    Compress-Archive -Path $($mxbuildExedir) -DestinationPath "$($MXPortable)"
    if (IsBuildCancelled) { return }
    Copy-File-ToCloud $MXPortable "Uploading MX zip..."
    if (IsBuildCancelled) { return }

    Invoke-LogAndExit -Log $outfile -Fail $false
}
function Invoke-GitMaintain {
    $lastdate = ""
    $todaydate = Get-Date -Format "dd:MM:yyyy"
    if (Test-Path HKCU:\SOFTWARE\buldauto) {
        $lastdate = Get-ItemProperty -Path HKCU:\SOFTWARE\buldauto -Name "gctime"
    }
    else {
        New-Item HKCU:\SOFTWARE\buldauto
    }
    if ($todaydate -ne $lastdate.gctime) {
        Set-ItemProperty -Path HKCU:\SOFTWARE\buldauto -Name "gctime" -Value "$($todaydate)"
        Set-Location y:
        git.exe reset --hard
        git.exe checkout master
        git.exe pull
        git.exe gc
    }
}
function Wait-Lan() {
    while (-not (test-connection "google.com" -quiet)) { Write-Output "waiting for connecton..." }
}
if (!(Test-Path -Path $workdir)) {
    return
}
#//////////////////////////////////////////////////////////////////////////////////////////////////////
Wait-Lan
while ($true) {
    Wait-Lan
    $request = Invoke-RestMethod @NewRequestParams
    if ("" -ne $request) {
        Invoke-CodeBuilder
    }
    else {
        Invoke-GitMaintain
    }
    Write-Host "$(Get-Date)"
    Start-Sleep -Seconds 1
}
