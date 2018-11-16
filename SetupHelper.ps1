
Set-ExecutionPolicy RemoteSigned
Set-ExecutionPolicy Unrestricted
Set-ExecutionPolicy bypass

New-ItemProperty -Path HKLM:Software\Microsoft\Windows\CurrentVersion\policies\system -Name EnableLUA -PropertyType DWord -Value 0 -Force

Disable-ComputerRestore c:\

$powerPlan = Get-WmiObject -Namespace root\cimv2\power -Class Win32_PowerPlan -Filter "ElementName = 'High Performance'"
$powerPlan.Activate()

powercfg -h off

$computersys = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges;
$computersys.AutomaticManagedPagefile = $False;
$computersys.Put();
$pagefile = Get-WmiObject -Query "Select * From Win32_PageFileSetting Where Name like '%pagefile.sys'";
$pagefile.InitialSize = 2048;
$pagefile.MaximumSize = 2048;
$pagefile.Put();

Set-Location c:\
git clone \\192.168.0.1\git\v8 V8

Set-Location D:\
New-Item  -Name v8.release.obj -ItemType directory
New-Item  -Name v8.debug.obj -ItemType directory
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\DOS Devices" -Name "U:" -Value "\\??\\D:\\v8.debug.obj" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\DOS Devices" -Name "V:" -Value "\\??\\D:\\v8.release.obj" -Force | Out-Null
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\DOS Devices" -Name "Y:" -Value "\\??\\C:\\v8" -Force | Out-Null

Set-Location 'C:\Program Files (x86)\'
New-Item  -Name Farpoints -ItemType directory
Copy-item -Force -Recurse -Verbose "\\SIRIUS\Installs\Work\FarPoint Controls\For Win7\Inppro20" -Destination 'C:\Program Files (x86)\Farpoints'
Copy-item -Force -Recurse -Verbose "\\SIRIUS\Installs\Work\FarPoint Controls\For Win7\Spread25" -Destination 'C:\Program Files (x86)\Farpoints'
[Environment]::SetEnvironmentVariable("FARPOINTS_INCLUDE", "C:\Program Files (x86)\Farpoints\Inppro20\INCLUDE;C:\Program Files (x86)\Farpoints\Spread25\INCLUDE", "Machine")
Set-Location 'C:\Program Files (x86)\'
New-Item  -Name "Microsoft Visual Studio" -ItemType directory
Copy-item -Force -Recurse -Verbose "\\SIRIUS\Installs\Work\VFortran6\Fortran_compiler\DF98" -Destination 'C:\Program Files (x86)\Microsoft Visual Studio\'
[Environment]::SetEnvironmentVariable("FORTRAN_INCLUDE", "C:\Program Files (x86)\Microsoft Visual Studio\DF98\INCLUDE;C:\Program Files (x86)\Microsoft Visual Studio\DF98\LIB", "Machine")
[Environment]::SetEnvironmentVariable("FORTRAN_PATH", "C:\Program Files (x86)\Microsoft Visual Studio\DF98", "Machine")
[Environment]::SetEnvironmentVariable("DIRECTX_SDK_PATH", "C:\Program Files (x86)\Microsoft DirectX SDK (August 2009)", "Machine")
[Environment]::SetEnvironmentVariable("PATH", "$($env:Path);C:\Program Files (x86)\Microsoft Visual Studio\DF98\BIN", "Machine")
