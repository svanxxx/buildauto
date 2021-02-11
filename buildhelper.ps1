$workdir = "Y:\";
$builddir = "$($workdir)Projects.32\";
$buildLibdir = "$($workdir)Release.lib\";
$buildExedir = "$($workdir)Release.exe\";
$requestInfo = "$($buildExedir)BSTRequestInfo.txt";
$mxbuildLibdir = "$($workdir)Modules.32\Release.lib\";
$mxbuildExedir = "$($workdir)Modules.32\Release.exe\";
$testdir = "$($workdir).Ext\";
$bstinfo = "$($workdir)Release.exe\BSTRequestInfo.txt";
$bstfile = "$($workdir)Common\BSTUserName.h"
$temp = [System.IO.Path]::GetTempPath();
$outfile = "$($temp)buildoutput.log";
$fipoutfile = "$($temp)fipbuildoutput.log";
$cxoutfile = "$($temp)cxbuildoutput.log";
$mxinstall = "$($workdir)Installs\OUTPUT\ONSITE_MODULES_WIX\BUILD_RELEASE.bat";
$mxinstallRes = "$($workdir)Installs\OUTPUT\ONSITE_MODULES_WIX\bin\FIELDPRO_MODELS_ONSITE_REAL_TIME.msi";
$SocketDir = "\\192.168.0.7\ReleaseSocket\Stack\";
$svc = New-WebServiceProxy –Uri ‘http://192.168.0.1/taskmanager/trservice.asmx?WSDL’
#$svc = New-WebServiceProxy –Uri ‘http://localhost:8311/TRService.asmx?WSDL’
$request = $null;
$vspath = """C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\devenv.com"""

function Write-State([string]$txt)
{
    $stamp = Get-Date -Format "HH:mm:ss"
    $out = $stamp+": "+$txt
    $out | Out-File $($outfile) -Append;
    $svc.CommentBuild($request.ID, $txt);
    Write-Host $out;
}
function Invoke-Cleanup([bool]$weboutput)
{
    Write-Host "Cleanup..."
    Write-Host "$(Get-Date)"
    if ($weboutput) {
        Write-State "Temp Folders Cleanup..."
    }
    $loc = Get-Location
    Set-Location $temp
    Remove-Item * -recurse -force
    Set-Location $loc
    if ($weboutput) {
        Write-State "V disk obj files folders cleanup..."
    }
    Remove-Item –path V:\* -Force -Recurse -Confirm:$false
    if ($weboutput) {
        Write-State "Lib files cleanup..."
    }
    Remove-Item –path "$($buildLibdir)*" -Force -Recurse -Confirm:$false
    Remove-Item –path "$($buildExedir)*" -Force -Recurse -Confirm:$false
    Remove-Item –path "$($mxbuildLibdir)*" -Force -Recurse -Confirm:$false
    Remove-Item –path "$($mxbuildExedir)*" -Force -Recurse -Confirm:$false
    if ($weboutput) {
        Write-State "IncrediBuild cleanup..."
    }
    Remove-Item –path "C:\Program Files (x86)\Xoreax\IncrediBuild\temp\*" -Force -Recurse -Confirm:$false
    Remove-Item –path "y:\.git\index.lock" -Force -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "$(Get-Date)"
}
function Invoke-Code-Synch([string]$branch)
{
    Write-State "Pull Code ($($branch)) From Git..."
    Set-Location $($workdir);
    cmd /c "git reset --hard" | Out-File $($outfile) -Append;
    cmd /c "git checkout master" | Out-File $($outfile) -Append;
    cmd /c "git reset --hard" | Out-File $($outfile) -Append;
    $branches = git branch
    For ($i=0; $i -lt $branches.Length; $i++) 
    {
        if ($branches[$i].Trim() -ne "* master")
        {
            git branch -D "$($branches[$i].Trim())"
        }
    }
    cmd /c "git fetch --all --prune" | Out-File $($outfile) -Append;
    cmd /c "git checkout ""$($branch)""" | Out-File $($outfile) -Append;
    cmd /c "git status" | Out-File $($outfile) -Append;
    cmd /c "git pull origin" | Out-File $($outfile) -Append;
    $currbranch = cmd /c "git rev-parse --abbrev-ref HEAD"
    if ($currbranch -ne $branch)
    {
        Write-Output "Error: current brach is: $($currbranch)"
        Write-Output "Expected: $($branch)"
        Write-State "Build aborted, GIT exception..."
        stop-computer
        exit
    }    
    if ($svc.IsBuildCancelled($request.ID))
    {
        Write-State "Build Cancelled..."
        stop-computer
        exit
    }
}
function Invoke-CodeCompilation([string]$solution, [string]$solutionOutfile, [string]$pathtolog)
{
    $buildcommand = "BuildConsole.exe ""$($solution)"" /rebuild /cfg=""Release|Mixed Platforms"" /NOLOGO /OUT=""$($solutionOutfile)"""
    Write-State "Building code $($solution)..."

    cmd /c "$($buildcommand)"

    $errors = 0
    $filecontent = Get-Content $($solutionOutfile)
    if ($filecontent | Select-String -Pattern "Build FAILED.")
    {
        if ($filecontent | Select-String -Pattern "TRACKER : error TRK0002")
        {
            Write-State "re - building code after TRK0002..."
            cmd /c "$($buildcommand)"
            $filecontent = Get-Content $($solutionOutfile)
        }
        $builderr = $filecontent | Select-String -SimpleMatch "): error"
        if ($builderr)
        {
            Write-State $builderr
            $errors = 1
        }        
        elseif ($filecontent | Select-String -Pattern "Build FAILED.")
        {
            Write-State "Build FAILED. Click to see the log."
            $errors = 1
        }
    }
    if ($errors -gt 0)
    {
        Copy-Item $solutionOutfile -Destination "$($pathtolog)$($request.ID).log"
        $svc.FailBuild($request.ID)
        stop-computer
        exit
    }

    if ($svc.IsBuildCancelled($request.ID))
    {
        Write-State "Build Cancelled..."
        stop-computer
        exit
    }
}
function Invoke-CodeBuilder()
{
    Invoke-Cleanup $true
    if ($svc.IsBuildCancelled($request.ID))
    {
        Write-State "Build Cancelled..."
        stop-computer;
        exit;
    }
    #=========================================================
    # init
    #=========================================================
    $branch = "$($request.BRANCH)"
    $user = "$($request.USER)"
    $version = "V8E"
    $ttid = """" + "TT$($request.TTID)" + " " + $request.SUMMARY.Replace("""", "'") + """"
    $comment = """" + $request.COMM.Replace("""", "'") + """"
    $pathtolog = $svc.geBuildLogDir()

    "Build Heler:" | Out-File "$($outfile)"
    Write-State "Starting Build For $($ttid)..."

    if ($svc.IsBuildCancelled($request.ID))
    {
        Write-State "Build Cancelled..."
        stop-computer;
        exit;
    }

    Invoke-Code-Synch($branch)

    "#define _BSTUserName _T("".$($user)"")" | Out-File $($bstfile) -Encoding ascii

    Invoke-CodeCompilation "$($builddir)All.sln" $fipoutfile $pathtolog

    Invoke-CodeCompilation "$($builddir)Modules.sln" $cxoutfile $pathtolog

    #=======================================================
    # making mx installation
    #=======================================================
    Write-State "$($mxinstall)"
    cmd /c "$($mxinstall)" | Out-File $($outfile) -Append;
    $sockfolder = Get-Content "$($requestInfo)" -First 1
    Copy-Item "$($mxinstallRes)" "$($SocketDir)$($sockfolder)"

    #=========================================================
    # test request sending
    #=========================================================
    Start-Service "MSSQLSERVER"
    Write-State "Sending test request..."
    Set-Location $($testdir);
    $testcmd = "RELEASE_TEST.BAT $($user) $($version) $($ttid) $($comment) $($vspath)";
    Write-State "$($testcmd)"
    cmd /c "$($testcmd)" | Out-File $($outfile) -Append;
    if ($LASTEXITCODE -eq 1) {
        Write-State "Failed to run release test."
        Copy-Item $outfile -Destination "$($pathtolog)$($request.ID).log"
        $svc.FailBuild($request.ID)
        stop-computer
        exit
    }
    
    Stop-Service "MSSQLSERVER"

    $fileerror = Select-String -Path $outfile -Pattern "^Error:" #line starts with 'error:'
    if ($null -ne $fileerror)
    {
        Copy-Item $outfile -Destination "$($pathtolog)$($request.ID).log"
        $svc.FailBuild($request.ID);
        stop-computer;
        exit;
    }

    Write-State "Release test was successfully sent. Click to see details."

    $verguid = Get-Content -Path $bstinfo
    $verguid = $verguid[0]

    $svc.FinishBuild($request.ID, "$($verguid)");
    Copy-Item $outfile -Destination "$($pathtolog)$($request.ID).log"

    #to speedup next build.
    Invoke-Cleanup $false

    stop-computer;
}
function Invoke-GitMaintain {
    $lastdate = ""
    $todaydate = Get-Date -Format "dd:MM:yyyy"
    if (Test-Path HKLM:\SOFTWARE\buldauto){
        $lastdate = Get-ItemProperty -Path HKLM:\SOFTWARE\buldauto -Name "gctime"
    } else {
        New-Item HKLM:\SOFTWARE\buldauto
    }
    if ($todaydate -ne $lastdate.gctime){
        Set-ItemProperty -Path HKLM:\SOFTWARE\buldauto -Name "gctime" -Value "$($todaydate)"
        Set-Location y:
        git.exe reset --hard
        git.exe checkout master
        git.exe pull
        git.exe gc
    }
}
function Wait-Lan()
{
    while (-not (test-connection 192.168.0.1 -quiet)){Write-Output "waiting for connecton..."}
}
Wait-Lan
cmd /c "\\192.168.0.1\Installs\Work\incprep.bat"
while ($true)
{
    Wait-Lan
    $request = $svc.getBuildRequest($env:computername.ToUpper())
    if ($request.TTID -ne 0 -and -not [string]::IsNullOrEmpty($request.BRANCH))
    {
        Invoke-CodeBuilder
    } else {
        Invoke-GitMaintain
    }
    Write-Host "$(Get-Date)"
    Start-Sleep -Seconds 1
}