$workdir = "d:\v8\";
$builddir = "$($workdir)Projects.32\";
$testdir = "$($workdir).Ext\";
$bstfile = "$($workdir)Common\BSTUserName.h"
$temp = [System.IO.Path]::GetTempPath();
$outfile = "$($temp)buildoutput.log";
$fipoutfile = "$($temp)fipbuildoutput.log";
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
    $branch = "TT$($request.TTID)";
    $user = "$($request.USER)";
    $version = "V8E";
    $ttid = """$($branch) $($request.SUMMARY)""";
    $comment = """$($request.COMM)""";

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
    cmd /c "git fetch --all" | Out-File $($outfile) -Append;
    cmd /c "git checkout $($branch)" | Out-File $($outfile) -Append;
    cmd /c "git pull origin" | Out-File $($outfile) -Append;

    #=========================================================
    # FIP - building
    #=========================================================
    "#define _BSTUserName _T("".$($user)"")" | Out-File $($bstfile)

    $buildcommand = "BuildConsole.exe ""$($workdir)Projects.32\All.sln"" /rebuild /cfg=""Release|Mixed Platforms"" /NOLOGO /OUT=""$($fipoutfile)"""
    Progress-Out $buildcommand
    Progress-Out "building fieldpro..."

    cmd /c "$($buildcommand)"

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
    cmd /c "$($vspath) /build Release Modules.sln" | Out-File $($outfile) -Append;

    #=========================================================
    # test request sending
    #=========================================================
    Progress-Out "Sending test request..."
    Set-Location $($testdir);
    $testcmd = "RELEASE_TEST.BAT $($user) $($version) $($ttid) $($comment) $($vspath)";
    Progress-Out "$($testcmd)"
    cmd /c "$($testcmd)" | Out-File $($outfile) -Append;
    $svc.FinishBuild($request.ID);
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