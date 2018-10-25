$workdir = "Y:\";
$builddir = "$($workdir)Projects.32\";
$testdir = "$($workdir).Ext\";
$bstfile = "$($workdir)Common\BSTUserName.h"
$temp = [System.IO.Path]::GetTempPath();
$outfile = "$($temp)buildoutput.log";
$fipoutfile = "$($temp)fipbuildoutput.log";
$cxoutfile = "$($temp)cxbuildoutput.log";
$svc = New-WebServiceProxy –Uri ‘http://192.168.0.1/taskmanagerbeta/trservice.asmx?WSDL’
#$svc = New-WebServiceProxy –Uri ‘http://localhost:8311/TRService.asmx?WSDL’
$request = $null;
$vspath = """C:\Program Files (x86)\Microsoft Visual Studio 12.0\Common7\IDE\devenv.com"""

function Progress-Out([string]$txt)
{
    $txt | Out-File $($outfile) -Append;
    $svc.CommentBuild($request.ID, $txt);
    echo $txt;
}

function Build-Version()
{
    #=========================================================
    # clean up
    #=========================================================
    Progress-Out "Temp folders cleanup..."
    $loc = Get-Location
    Set-Location $temp
    Remove-Item * -recurse -force
    Set-Location $loc
    Progress-Out "V disk obj files folders cleanup..."
    Remove-Item –path V:\* -Force -Recurse -Confirm:$false
    Progress-Out "Preparing Inc-Build..."
    cmd /c "\\192.168.0.1\Installs\Work\incprep.bat"
    #=========================================================
    # init
    #=========================================================
    $branch = "TT$($request.TTID)";
    $user = "$($request.USER)";
    $version = "V8E";
    $ttid = """" + $branch + " " + $request.SUMMARY.Replace("""", "'") + """";
    $comment = """" + $request.COMM.Replace("""", "'") + """";
    $pathtolog = $svc.geBuildLogDir()

    "buildheler:" | Out-File $($outfile);
    Progress-Out "Starting build..."
    Progress-Out "$($ttid)"

    #=========================================================
    # GIT - getting code
    #=========================================================
    Progress-Out $branch
    Progress-Out "getting code from git..."
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
    cmd /c "git fetch --all" | Out-File $($outfile) -Append;
    cmd /c "git checkout $($branch)" | Out-File $($outfile) -Append;
    cmd /c "git pull origin" | Out-File $($outfile) -Append;

    #=========================================================
    # FIP - building
    #=========================================================

    "#define _BSTUserName _T("".$($user)"")" | Out-File $($bstfile) -Encoding ascii

    $buildcommand = "BuildConsole.exe ""$($workdir)Projects.32\All.sln"" /rebuild /cfg=""Release|Mixed Platforms"" /NOLOGO /OUT=""$($fipoutfile)"""
    Progress-Out $buildcommand
    Progress-Out "building fieldpro..."

    cmd /c "$($buildcommand)"

    $errors = 0
    if (Get-Content $($fipoutfile) | Select-String -Pattern "Build FAILED.")
    {
        $errors = 1
    }
    if ($errors -gt 0)
    {
        Copy-Item $fipoutfile -Destination "$($pathtolog)$($request.ID).log"
        $svc.FailBuild($request.ID);
        stop-computer;
        exit;
    }

    #=========================================================
    # CX - building
    #=========================================================
    Progress-Out "building CX..."
    Set-Location $($builddir);
    cmd /c "$($vspath) /clean Release Modules.sln"

    $srclib = "$($workdir)Modules.32\Release.lib\Src.lib"
    $srclib0 = "$($workdir)Modules.32\Release.lib\SRC\Src.lib"

    if(![System.IO.File]::Exists($srclib)){
        Copy-Item -Path $srclib0 -Destination $srclib -Force
    }

    cmd /c "$($vspath) /build Release Modules.sln"
    cmd /c "$($vspath) /build Release Modules.sln"
    cmd /c "$($vspath) /build Release Modules.sln" | Out-File $($cxoutfile) -Append;

    $buildresult = Get-Content $($cxoutfile) | Select-String -Pattern '========== Build:'
    $buildresults = $buildresult -split ","
    $errors = $buildresults[1].Trim() -replace "[^0-9]"
    if ($errors -gt 0)
    {
        Copy-Item $cxoutfile -Destination "$($pathtolog)$($request.ID).log"
        $svc.FailBuild($request.ID);
        stop-computer;
        exit;
    }

    #=========================================================
    # test request sending
    #=========================================================
    Progress-Out "Sending test request..."
    Set-Location $($testdir);
    $testcmd = "RELEASE_TEST.BAT $($user) $($version) $($ttid) $($comment) $($vspath)";
    Progress-Out "$($testcmd)"
    cmd /c "$($testcmd)" | Out-File $($outfile) -Append;

    $fileerror = Select-String -Path $outfile -Pattern "Error:"
    if ($fileerror -ne $null)
    {
        Copy-Item $outfile -Destination "$($pathtolog)$($request.ID).log"
        $svc.FailBuild($request.ID);
        stop-computer;
        exit;
    }

    Progress-Out "release test returned code: $($?)"

    $svc.FinishBuild($request.ID);
    Copy-Item $outfile -Destination "$($pathtolog)$($request.ID).log"
    stop-computer;
}

while ($true)
{
    $request = $svc.getBuildRequest($env:computername.ToUpper())
    if (!($request.TTID -eq ""))
    {
        Build-Version
    }
    echo "$(Get-Date)"
    Start-Sleep -s 20
}