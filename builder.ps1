$TempCleanUp = $false
$BuildCleanUp = $false
$GitSync = $false
$Rebuild = $false

$DSN = "FIELDPRO_BLANK_DATABASE"
$workdir = "Y:\";
$builddir = "$($workdir)Projects.32\";
$buildLibdir = "$($workdir)Release.lib\";
$buildExedir = "$($workdir)Release.exe\";
$Migrator = "$($buildExedir)MigrateDB.exe";
$requestInfo = "$($buildExedir)BSTRequestInfo.txt";
$mxbuildLibdir = "$($workdir)Modules.32\Release.lib\";
$mxbuildExedir = "$($workdir)Modules.32\Release.exe\";
$ExtDir = "$($workdir).Ext\";
$DbReg = "$($ExtDir)db.reg";
$bstinfo = "$($workdir)Release.exe\BSTRequestInfo.txt";
$bstfile = "$($workdir)Common\BSTUserName.h"
$VersionFile = "$($workdir)Common\AppVersions.h"
$temp = [System.IO.Path]::GetTempPath();
$outfile = "$($temp)buildoutput.log";
$fipoutfile = "$($temp)fipbuildoutput.log";
$cxoutfile = "$($temp)cxbuildoutput.log";
$DBZip = "$($workdir)Installs\INPUT\Database\MSSQL_ETALON.zip";
$installs = "$($workdir)Installs\OUTPUT\";
$mxinstall = "$($installs)ONSITE_MODULES_WIX\BUILD_RELEASE.bat";
$mxinstallRes = "$($installs)ONSITE_MODULES_WIX\bin\FIELDPRO_MODELS_ONSITE_REAL_TIME.msi";
$onsiteinstallRes = "$($installs)ONSITE_MODULES_WIX\bin\FIELDPRO_ONSITE.msi";
$metadatainstall = "$($installs)METADATAGENERATOR_WIX\BUILD_RELEASE.bat";
$metadatainstallRes = "$($installs)METADATAGENERATOR_WIX\bin\METADATAGENERATOR.msi";
$SocketDir = "\\192.168.0.7\ReleaseSocket\Stack\";
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
function Copy-File-ToCloud([string]$file) {
    $cfg = "$($PSScriptRoot)\bin\rclone.conf"
    "[syncconfig]`r`n$($request.config)" | Out-File $($cfg) -Encoding ascii
    $command = "$($PSScriptRoot)\bin\rclone.exe --config ""$($cfg)"" copy ""$($file)"" ""syncconfig:$(Get-UGuid)"""
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
        Remove-Item –path "$($buildLibdir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item –path "$($buildExedir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item –path "$($mxbuildLibdir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item –path "$($mxbuildExedir)*" -Force -Recurse -Confirm:$false -ErrorAction SilentlyContinue
        Remove-Item –path "y:\.git\index.lock" -Force -Confirm:$false -ErrorAction SilentlyContinue
        Write-Host "$(Get-Date)"
        if (IsBuildCancelled) {
            Write-State "Build Cancelled..."
            $result = $false
        }
    )
    return $result
}
function IsBuildCancelled {
    $CancelledRequestParams = @{
        Uri    = $URL + "/api/cancelled?id=" + $request.id
        Method = "GET"
    }
    $answer = Invoke-RestMethod @CancelledRequestParams
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
        cmd /c "git reset --hard" | Out-File $($outfile) -Append;
        cmd /c "git checkout master" | Out-File $($outfile) -Append;
        cmd /c "git reset --hard" | Out-File $($outfile) -Append;
        $branches = git branch
        For ($i = 0; $i -lt $branches.Length; $i++) {
            if ($branches[$i].Trim() -ne "* master") {
                git branch -D "$($branches[$i].Trim())"
            }
        }
        cmd /c "git fetch --all --prune" | Out-File $($outfile) -Append;
        cmd /c "git checkout ""$($branch)""" | Out-File $($outfile) -Append;
        cmd /c "git status" | Out-File $($outfile) -Append;
        cmd /c "git pull origin" | Out-File $($outfile) -Append;
        $currbranch = cmd /c "git rev-parse --abbrev-ref HEAD"
        if ($currbranch -ne $branch) {
            Write-Output "Error: current brach is: $($currbranch)"
            Write-Output "Expected: $($branch)"
            Write-State "Build aborted, GIT exception..."
            $result = $false
        }    
        elseif (IsBuildCancelled) {
            Write-State "Build Cancelled..."
            $result = $false
        }
    )
    return $result
}
function Invoke-LogAndExit([string]$Log, [bool]$Fail) {
    $zip = "$($temp)log.zip"
    if (Test-Path -Path $zip) {
        Remove-Item $zip
    }
    Compress-Archive -Path $($Log) -DestinationPath $($zip)
    Copy-File-ToCloud($zip)
    if ($Fail){
        FailBuild
    } else {
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
            Write-State "Build Cancelled..."
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
    if (Test-Path -Path $outfile) {
        Remove-Item -Path $outfile
    }
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
    
    Write-State "Restoring database..."
    $RestoreCommand = "OSQL -S (local)\SQL2014 -U sa -P prosuite -Q ""RESTORE DATABASE $($DSN) FROM DISK = 'C:\ProgramData\Fieldpro\MSSQL_ETALON.bak' WITH REPLACE"""
    cmd /c $RestoreCommand | Out-File $($outfile) -Append;

    Write-State "Migrating database..."
    $MigrateCommand = "$($Migrator) $($DSN) SkipWait"
    $MigrateCommand | Out-File $($outfile) -Append;
    cmd /c $MigrateCommand | Out-File $($outfile) -Append;

    #=======================================================
    # making mx installation
    #=======================================================
    Write-State "MX installation..."
    if (Test-Path -Path $mxinstallRes) {
        Remove-Item -Path $mxinstallRes
    }
    if (Test-Path -Path $onsiteinstallRes) {
        Remove-Item -Path $onsiteinstallRes
    }
    cmd /c "$($mxinstall)" | Out-File $($outfile) -Append;
    if (Test-Path -Path $mxinstallRes) {
        Write-State "Uploading MX..."
        Copy-File-ToCloud($mxinstallRes)
    } else {
        Write-State "Failed to build MX installation"
        Invoke-LogAndExit -Log $outfile -Fail $true
    }
    if (Test-Path -Path $onsiteinstallRes) {
        Write-State "Uploading Onsite..."
        Copy-File-ToCloud($onsiteinstallRes)
    } else {
        Write-State "Failed to build Onsite installation"
        Invoke-LogAndExit -Log $outfile -Fail $true
    }

    #=======================================================
    # making METADATA installation
    #=======================================================
    Write-State "Building metadata..."
    if (Test-Path -Path $metadatainstallRes) {
        Remove-Item -Path $metadatainstallRes
    }
    cmd /c "$($metadatainstall)" | Out-File $($outfile) -Append;
    if (Test-Path -Path $metadatainstallRes) {
        Write-State "Uploading metadata..."
        Copy-File-ToCloud($metadatainstallRes)
    } else {
        Write-State "Failed to build metadata"
        Invoke-LogAndExit -Log $outfile -Fail $true
    }

    Write-State "Finished."
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
