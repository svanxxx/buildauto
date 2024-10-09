$TempCleanUp = $true
$BuildCleanUp = $true
$GitSync = $true
$Rebuild = $true

$DSN = "FIELDPRO_BLANK_DATABASE"
$workdir = "Y:\";
$builddir = "$($workdir)Projects.32\";
$buildLibdir = "$($workdir)Release.lib\";
$buildExedir = "$($workdir)Release.exe\";
$buildExeFile = "$($workdir)Release.exe\Fieldpro.exe";
$bstinfo = "$($buildExedir)BSTRequestInfo.txt";
$Migrator = "$($buildExedir)MigrateDB.exe";
$SiteManager = "$($buildExedir)FieldproSiteManager.exe";
$mxbuildLibdir = "$($workdir)Modules.32\Release.lib\";
$mxbuildExedir = "$($workdir)Modules.32\Release.exe\";
$bstfile = "$($workdir)Common\BSTUserName.h"
$statusFile = "$($builddir)status.txt"
$RequestFile = "$($builddir)request.txt"
$VersionFile = "$($workdir)Common\AppVersions.h"
$temp = [System.IO.Path]::GetTempPath();
$ProgramData = "C:\ProgramData\Fieldpro";
$outfile = "$($temp)buildoutput.log";
$fipoutfile = "$($temp)fipbuildoutput.log";
$cxoutfile = "$($temp)cxbuildoutput.log";

$usbip = "$($PSScriptRoot)\bin\usbip\usbip.exe"
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.19041.0\x64\signtool.exe"
$Cer = "$($workdir)Installs\INPUT\Signing\cer.cer";

$DBZip = "$($workdir)Installs\INPUT\Database\MSSQL_ETALON.zip";
$DBForMigration = "$($workdir)Installs\INPUT\Database\MSSQL_ETALON.BAK";
$RestoreCommand = "OSQL -S (local)\SQL2014 -E -Q ""RESTORE DATABASE $($DSN) FROM DISK = '$($DBForMigration)' WITH REPLACE"""
$DBForInstall = "$($workdir)Installs\INPUT\Database\FIELDPRO_BLANK_DATABASE.BAK";
$BackupCommand = "OSQL -S (local)\SQL2014 -E -Q ""BACKUP DATABASE $($DSN) TO DISK = '$($DBForInstall)'"""

$installs = "$($workdir)Installs\OUTPUT\";
$mxinstall = "$($installs)ONSITE_MODULES_WIX\BUILD_RELEASE.bat";
#=======================================
#Output files
#=======================================
$mxinstallRes = "$($installs)ONSITE_MODULES_WIX\bin\FIELDPRO_MODELS_ONSITE_REAL_TIME.msi";
$onsiteinstallRes = "$($installs)ONSITE_MODULES_WIX\bin\FIELDPRO_ONSITE.msi";
$historianinstallRes = "$($installs)ONSITE_MODULES_WIX\bin\FIELDPRO_HISTORIAN.msi";
$FIPinstallResOrig = "$($installs)FIELDPRO_WIX\bin\FIELDPRO.msi";
$FIPinstallRes = "$($installs)FIELDPRO_WIX\bin\FIELDPRO_SERVER.msi";
$FIPinstallResBat = "$($installs)FIELDPRO_WIX\bin\FIELDPRO_SERVER.msi.bat";
$FIPPortable = "$($builddir)Release.zip";
$MXPortable = "$($builddir)Modules.zip";
$TestRequested = $mxinstallRes, $onsiteinstallRes, $historianinstallRes, $FIPinstallRes, $FIPPortable, $MXPortable, $bstinfo
#=======================================
$FIPinstall = "$($installs)FIELDPRO_WIX\BUILD_RELEASE.bat";
$machine = $env:computername.ToUpper()
$vspath = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\IDE\devenv.com"
function IsRelease() {
    return ($request.BuildType -eq 2)
}
$global:__UGuid = ""
function Get-UGuid() {
    if ($global:__UGuid -eq "") {
        $u = Get-CodeOwner
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
$global:_CVersion = ""
function Get-CodeVersion() {
    $IsRelease = IsRelease
    if ($global:_CVersion -eq "") {
        if ($IsRelease) {
            $u = ""
        }
        else {
            $u = ".$(Get-CodeOwner)"
        }
        $v = Get-Version
        $v1 = $v[0]
        $v2 = $v[1]
        $v3 = $v[2]
        $v4 = $v[3]
        $d = (Get-Date).ToString("yyyy")
        $global:_CVersion = "$($d).$($v1).$($v2).$($v3).$($v4)$($u)"
    }
    return $global:_CVersion
}
function Compress-Directory {
    param (
        [string]$Path,
        [string]$DestinationPath
    )
    $Zipper = "$($PSScriptRoot)\bin\7za.exe a -tzip -r -mx=1 -mm=Deflate ""$($DestinationPath)"" ""$($Path)\*"""
    cmd /c "$($Zipper)"
}
function GetIniParam([int]$Index) {
    $file = $PSScriptRoot + "\builder.ini"
    $content = Get-Content $file
    return $content[$Index]
}
$URL = GetIniParam(0)
$ApiKey = GetIniParam(1)
function Get-Headers {
    return @{"X-API-KEY" = "$($ApiKey)" }
}
function Invoke-Command([string]$Command) {
    cmd /c "$($Command)" | Out-File $($outfile) -Append;
}
function FailBuild {
    $FaileRequestParams = @{
        Uri     = $URL + "/api/fail?id=" + $request.id
        Method  = "POST"
        Headers = Get-Headers
    }
    Invoke-RestMethod @FaileRequestParams
}
function Write-State([string]$txt) {
    if ($txt.Length -gt 512) {
        $txt = $txt.Substring(0, 512)
    }
    
    $stamp = Get-Date -Format "HH:mm:ss"
    $out = $stamp + ": " + $txt
    $out | Out-File $($outfile) -Append;
    $CommentRequestParams = @{
        Uri     = $URL + "/api/comment?id=" + $request.id + "&comment=" + [uri]::EscapeDataString($txt)
        Method  = "POST"
        Headers = Get-Headers
    }
    $request = Invoke-RestMethod @CommentRequestParams
    Write-Host $out;
}
function Lock-Usb {
    $Null = @(
        $LockRequestParams = @{
            Uri     = $URL + "/api/lockusb"
            Method  = "GET"
            Headers = Get-Headers
        }
        $answer = Invoke-RestMethod @LockRequestParams
        if ([string]::IsNullOrEmpty($answer)) {
            Write-State "Awating for signing usb lock..."
        }
        else {
            Write-State "Locking usb key: $($answer)"
        }
    )
    return $answer
}

function Wait-Usb {
    $Command = "pnputil.exe /enum-devices | findstr ""Device Description"" | findstr ""eToken"""
    $attempt = 1
    do {
        Write-State "Waiting for usb token to appear in the system. Attempt ($($attempt))..."
        Start-Sleep -Seconds 2
        $output = &"cmd.exe" /c "$($Command)"
        $attempt = $attempt + 1
        if ($attempt -gt 200) {
            Invoke-LogAndExit -Log $outfile -Fail $true
            return $false
        }
    } while ($Null -eq $output)
    return $true
}

function Unlock-Usb([string]$id) {
    $Null = @(
        $UnLockRequestParams = @{
            Uri     = $URL + "/api/unlockusb?id=$($id)"
            Method  = "GET"
            Headers = Get-Headers
        }
        $answer = Invoke-RestMethod @UnLockRequestParams
        Write-State "Unlocking usb key: $($answer)"
    )
}

function Install-Sign([string]$Path) {
    $IsRelease = IsRelease
    if (-not $IsRelease) {
        return $true
    }

    $timer = 0
    $lock = $null
    while ($timer -le 300) {
        $lock = Lock-Usb
        if (-not [string]::IsNullOrEmpty($lock)) {
            break
        }
        $timer = $timer + 1
        Start-Sleep -Seconds 1
    }
    if ($null -eq $lock) {
        Write-State "Failed to lock signing usb key during 5 minutes"
        return $false
    }
    
    $connector = """$($usbip)"" attach -r $($request.signAddress) -b 3-2"
    Invoke-Command $connector

    if (-not (Wait-Usb)) {
        return $false
    }

    Write-State "Signing..."
    $Signer = """$($signtool)"" sign /f ""$($Cer)"" /csp ""eToken Base Cryptographic Provider"" /k ""[{{$($request.SignPass)}}]=$($request.SignContainer)"" /fd SHA256 /t http://timestamp.digicert.com /d ""FIELDPRO® Application"" ""$($Path)"""
    Invoke-Command $Signer

    $disconnector = """$($usbip)"" -d detach -p 0"
    Invoke-Command $disconnector

    Unlock-Usb $lock

    return $true
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
$NewRequestParams = @{
    Uri     = $URL + "/api/catch?machine=" + $machine
    Method  = "GET"
    Headers = Get-Headers
}
$request = $null;
function Copy-Files-To-CloudChannel {
    $IsRelease = IsRelease
    if ($IsRelease) {
        $v = Get-Version
        $rootFolder = "FIELDPRO_V$($v[0])"
        $releaseFolder = "FIELDPRO V$($v[0]) $($v[1]).$($v[2]).$($v[3])"
    
        $cfg = "$($PSScriptRoot)\bin\rclone.conf"
        "[syncconfig]`r`n$($request.config)" | Out-File $($cfg) -Encoding ascii
        $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" delete ""syncconfig:/MASTER/"""
        Invoke-Command $command
        $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""syncconfig:/$($rootFolder)/$($releaseFolder)"" ""syncconfig:/MASTER/"""
        Invoke-Command $command

        $loc = Get-Location
        Set-Location $workdir
        $CodeFileName = "Sources.zip"
        $UpdateFileName = "CHANGELOG_V$($v[0]) $($v[1]).$($v[2]).$($v[3]).zip"

        $zipexe = "$($PSScriptRoot)\bin\7za.exe"
        &$zipexe a $CodeFileName common Modules.32 Resshare.32 Utils.32 Webpro.32 Wellpro.32 Release.exe Release.lib
        &$zipexe a $UpdateFileName Projects.32\ChangeLog.txt
        &$zipexe rn $UpdateFileName Projects.32\ChangeLog.txt ChangeLog.txt
        $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""$($workdir)$($UpdateFileName)"" ""syncconfig:/$($rootFolder)/$($releaseFolder)"""
        $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""$($workdir)$($CodeFileName)"" ""syncconfig:/$($rootFolder)/$($releaseFolder)"""
        Invoke-Command $command
        Remove-File $CodeFileName
        Set-Location $loc
    }
}
function Copy-File-ToCloud {
    param (
        [string]$FileName, 
        [string]$Message,
        [bool]$DeleteFile = $true
    )

    if ($Message.Length -gt 0) {
        Write-State $Message
    }
    $v = Get-Version
    $rootFolder = "FIELDPRO_V$($v[0])"
    $releaseFolder = "FIELDPRO V$($v[0]) $($v[1]).$($v[2]).$($v[3])"
    $prefix = "_$($v[0])_$($v[1])_$($v[2])_$($v[3])"

    $FileNameNoPath = [System.IO.Path]::GetFileName($FileName)
    $NameParts = $FileNameNoPath.Split(".")
    $FileNameNoPathNoExt = $NameParts[0]
    $AllExts = $NameParts[1..($NameParts.Length - 1)] -join "."

    $IsMSI = $NameParts.Contains("msi") -or $NameParts.Contains("bat")

    $md5File = $FileName + ".md5"
    Remove-File $md5File
    $hash = Get-FileHash $FileName -Algorithm MD5
    $hash.Hash | Out-File $($md5File) -Encoding ascii

    $cfg = "$($PSScriptRoot)\bin\rclone.conf"
    "[syncconfig]`r`n$($request.config)" | Out-File $($cfg) -Encoding ascii
    $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""$($FileName)"" ""syncconfig:/ReleaseSocket/$(Get-UGuid)"""
    Invoke-Command $command
    $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""$($md5File)"" ""syncconfig:/ReleaseSocket/$(Get-UGuid)"""
    Invoke-Command $command
    $IsRelease = IsRelease
    if ($IsRelease -and $IsMSI) {
        $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copyto ""syncconfig:/ReleaseSocket/$(Get-UGuid)/$($FileNameNoPath)"" ""syncconfig:/$($rootFolder)/$($releaseFolder)/$($FileNameNoPathNoExt)$($prefix).$($AllExts)"""
        Invoke-Command $command
        $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copyto ""syncconfig:/ReleaseSocket/$(Get-UGuid)/$($FileNameNoPath).md5"" ""syncconfig:/$($rootFolder)/$($releaseFolder)/$($FileNameNoPathNoExt)$($prefix).$($AllExts).md5"""
        Invoke-Command $command
    }

    if ($DeleteFile) {
        Remove-File $FileName    
    }
    Remove-File $md5File
}
function Get-BuildUser() {
    return $request.userEmail.Split("@")[0].ToUpper()
}
function Get-CodeOwner() {
    return $request.ownerEmail.Split("@")[0].ToUpper()
}

function Get-Version() {
    $V = "", "", "", ""
    $VM = "#define __FILEVERSION_NUMBER_FIP_2__", "#define __FILEVERSION_NUMBER_FIP_3__", "#define __MINI_DB_UPDATE_VERSION__", "#define __FILEVERSION_NUMBER_FIP_4__"
    
    Get-Content $VersionFile | ForEach-Object {
        for ($i = 0; $i -lt $VM.Length; $i++) { 
            if ($_ -match "$($VM[$i])*") {
                $V[$i] = $_.Substring($VM[$i].Length).Trim().Split("//")[0].ToUpper().Trim()
            }    
        }
    }
    return $V
}
function Invoke-Cleanup([bool]$weboutput) {
    $Null = @(
        $result = $true

        Write-Host "Cleanup..."

        Write-Host "Cleaning up program data folder..."
        $loc = Get-Location
        Set-Location $ProgramData
        Remove-Item * -Recurse -Force -ErrorAction SilentlyContinue
        Set-Location $loc

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
        Remove-Item -Path "$($workdir).obj\*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item -Path "$($workdir)eFieldpro\bin\*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue -Exclude .gitignore
        Remove-Item -Path "$($workdir)eFieldpro\API\bin\*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue -Exclude .gitignore
        Remove-Item -Path "$($workdir).git\index.lock" -Force -Confirm:$false -ErrorAction SilentlyContinue
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
            Uri     = $URL + "/api/cancelled?id=" + $request.id
            Method  = "GET"
            Headers = Get-Headers
        }
        $answer = Invoke-RestMethod @CancelledRequestParams
        if ($answer) {
            Write-State "Build Cancelled..."
        }
    )
    return $answer
}
function FinishBuild {
    $FinishRequestParams = @{
        Uri     = $URL + "/api/finish?id=" + $request.id
        Method  = "POST"
        Headers = Get-Headers
    }
    Invoke-RestMethod @FinishRequestParams
}
function Get-Git-Hash {
    $null = @(
        $loc = Get-Location
        Set-Location $workdir
        $hash = cmd /c "git rev-parse --abbrev-ref HEAD"
        Set-Location $loc
    )
    return $hash
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
        if ($branches -is [array]) {
            For ($i = 0; $i -lt $branches.Length; $i++) {
                if ($branches[$i].Trim() -ne "* master") {
                    git branch -D "$($branches[$i].Trim())"
                }
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
    Copy-File-ToCloud $zip ""
    if ($Fail) {
        FailBuild
    }
    else {
        Write-State "Finished."
        FinishBuild
        Copy-Files-To-CloudChannel
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
        Uri     = $URL + "/api/uguid?id=" + $request.id + "&guid=" + $uguid_
        Method  = "POST"
        Headers = Get-Headers
    }
    Invoke-RestMethod @GuidRequestParams
}
function Invoke-CodeBuilder {

    taskkill.exe /f /im "cl.exe"
    taskkill.exe /f /im "mspdbsrv.exe"

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

    $user = Get-CodeOwner
    if ($request.BuildType -ne 2) {
        "#define _BSTUserName _T("".$($user)"")" | Out-File $($bstfile) -Encoding ascii
    }
    else {
        "#define _BSTUserName _T("""")" | Out-File $($bstfile) -Encoding ascii
    }

    #=======================================================
    # building phx
    #=======================================================

    $res = Invoke-CodeCompilation -Solution "$($builddir)All.sln" -BuildLog $fipoutfile
    if (!$res) {
        return
    }

    #=======================================================
    # adding test info
    #=======================================================

    $TestData = 1..4
    $TestData[0] = $(Get-UGuid)
    $TestData[1] = "VER:" + $(Get-CodeVersion)
    $fi = (Get-ChildItem $($buildExeFile))
    $date = $fi.CreationTime
    $TestData[2] = $date.ToString("yyyy-MM-dd HH:mm:ss")
    $date = $fi.LastWriteTime
    $TestData[3] = $date.ToString("yyyy-MM-dd HH:mm:ss")
    $TestData | Out-File $($bstinfo) -Encoding ascii
        
    #=======================================================
    # building mx
    #=======================================================

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
    Expand-Archive -LiteralPath $DBZip -DestinationPath "$($workdir)Installs\INPUT\Database\" -Force
    if (!(Test-File $DBForMigration "Extract empty sql database")) {
        return
    }
    if (IsBuildCancelled) { return }
    Write-State "Restoring database..."
    Invoke-Command $RestoreCommand
    if (IsBuildCancelled) { return }
    Remove-Item -Path $DBForMigration

    Write-State "Migrating database..."
    $MigrateCommand = "$($Migrator) $($DSN) SkipWait"
    $MigrateCommand | Out-File $($outfile) -Append;
    Invoke-Command $MigrateCommand
    if (IsBuildCancelled) { return }

    Write-State "Generating template OIF..."
    $OIFCommand = "$($Migrator) $($DSN) gen_templ_oif"
    Invoke-Command $OIFCommand
    Copy-Item "$($buildExedir)Template.oif" -Destination "$($mxbuildExedir)"
    if (IsBuildCancelled) { return }

    Write-State "Backup database..."
    Remove-File $DBForInstall
    Invoke-Command $BackupCommand
    if (IsBuildCancelled) { return }
    if (!(Test-File $DBForInstall "Database backup")) {
        return
    }
    #=======================================================
    # making mx installation
    #=======================================================
    Write-State "MX installation..."
    Remove-File $mxinstallRes
    Remove-File $onsiteinstallRes
    Remove-File $historianinstallRes
    Invoke-Command "$($mxinstall)"
    if (IsBuildCancelled) { return }
    if (!(Test-File $mxinstallRes "MX installation build")) {
        return
    }
    if (!(Install-Sign $mxinstallRes)) {
        return
    }
    Copy-File-ToCloud $mxinstallRes "Uploading MX..."
    if (IsBuildCancelled) { return }
    if (!(Test-File $onsiteinstallRes "Onsite installation build")) {
        return
    }
    if (!(Install-Sign $onsiteinstallRes)) {
        return
    }
    Copy-File-ToCloud $onsiteinstallRes "Uploading Onsite..."
    if (IsBuildCancelled) { return }
    if (!(Test-File $historianinstallRes "Historian installation build")) {
        return
    }
    if (!(Install-Sign $historianinstallRes)) {
        return
    }
    
    Copy-File-ToCloud $historianinstallRes "Uploading Historian..."
    if (IsBuildCancelled) { return }
    #=======================================================
    # making FIP portable
    #=======================================================
    Write-State "Archivating FIP..."
    Remove-File $FIPPortable
    Compress-Directory -Path $($buildExedir) -DestinationPath "$($FIPPortable)"
    if (IsBuildCancelled) { return }
    Copy-File-ToCloud $FIPPortable "Uploading FIP zip..."
    if (IsBuildCancelled) { return }
    #=======================================================
    # send request information
    #=======================================================
    $RequestInformaion = "id=$([uri]::EscapeDataString($request.parentID))"
    $RequestInformaion += "&name=$([uri]::EscapeDataString($request.summary))"
    $RequestInformaion += "&commands=$([uri]::EscapeDataString($request.testCommands))"
    $RequestInformaion += "&batches=$([uri]::EscapeDataString($request.testBatches))"
    $RequestInformaion += "&guid=$([uri]::EscapeDataString($(Get-UGuid)))"
    $RequestInformaion += "&owner=$([uri]::EscapeDataString($(Get-CodeOwner)))"
    $RequestInformaion += "&version=$([uri]::EscapeDataString($(Get-CodeVersion)))"
    $RequestInformaion += "&comment=$([uri]::EscapeDataString($request.notes))"
    $RequestInformaion += "&git=$([uri]::EscapeDataString($(Get-Git-Hash)))"
    $RequestInformaion += "&priority=$([uri]::EscapeDataString($request.testPriority))"
    $RequestInformaion | Out-File $($RequestFile) -Encoding ascii
    Copy-File-ToCloud $RequestFile "Uploading request information..."
    if (IsBuildCancelled) { return }
    #=======================================================
    # send ready signal
    #=======================================================
    Copy-File-ToCloud $bstinfo "Uploading QA info file..."
    if (IsBuildCancelled) { return }
    $TestRequested | Out-File $($statusFile) -Encoding ascii
    Copy-File-ToCloud $statusFile "Sending test signal..."
    if (IsBuildCancelled) { return }
    #=======================================================
    # making FIP installation
    #=======================================================
    Write-State "FIP installation..."
    
    Remove-File $FIPinstallRes
    Remove-File $FIPinstallResOrig

    if (!(Install-Sign $SiteManager)) {
        return
    }

    Invoke-Command "$($FIPinstall)"

    Rename-Item -Path $FIPinstallResOrig -NewName $FIPinstallRes

    if (IsBuildCancelled) { return }
    if (!(Test-File $FIPinstallRes "FIP installation build")) {
        return
    }
    if (!(Install-Sign $FIPinstallRes)) {
        return
    }
    Copy-File-ToCloud $FIPinstallRes "Uploading FIP installation..."
    if (IsBuildCancelled) { return }

    "msiexec /i ""%~dpn0""" | Out-File $($FIPinstallResBat) -Encoding ascii
    Copy-File-ToCloud $FIPinstallResBat "Uploading FIP installation bat..."
    if (IsBuildCancelled) { return }

    #=======================================================
    # making MX portable
    #=======================================================
    Write-State "Archivating MX..."
    Remove-File $MXPortable
    Compress-Directory -Path $($mxbuildExedir) -DestinationPath "$($MXPortable)"
    if (IsBuildCancelled) { return }
    Copy-File-ToCloud $MXPortable "Uploading MX zip..."
    if (IsBuildCancelled) { return }

    Invoke-LogAndExit -Log $outfile -Fail $false
}
function Invoke-Self-Updater {
    $result = $false
    $null = @(
        Set-Location $PSScriptRoot
        $Changes = git.exe diff-index HEAD
        if ($null -ne $Changes) {
            Write-Host "Git files are modified! The version will not auto update!"
        }
        else {
            $HashLocal = git.exe rev-parse HEAD
            $HashRemote = git.exe ls-remote origin HEAD
            $HashRemote = $HashRemote.Split()[0]
            if ($HashLocal -ne $HashRemote) {
                git.exe pull origin
                Write-Host "New update arrived. Restarting..."
                $result = $true
            }
        }
    )
    return $result
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
        Set-Location $workdir
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
if (Invoke-Self-Updater) {
    Start-Sleep -Seconds 20
    Restart-Computer
    return
}
while ($true) {
    try {
        $request = Invoke-RestMethod @NewRequestParams
    }
    catch {
        Write-Host "falied to connect to server"
        Start-Sleep -Seconds 60
        continue
    } 
    
    $global:__UGuid = ""
    $global:_CVersion = ""
    if ("" -ne $request) {
        Invoke-CodeBuilder
        Start-Sleep -Seconds 60
        Restart-Computer
        return
    }
    else {
        Invoke-GitMaintain
    }
    Write-Host "$(Get-Date)"
    Wait-Lan
    if (Invoke-Self-Updater) {
        Start-Sleep -Seconds 20
        Restart-Computer
        return
    }
}
