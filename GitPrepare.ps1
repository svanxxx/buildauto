while (-not (test-connection 192.168.0.1 -quiet)){}

Set-Location c:\buildauto\
git.exe reset --hard
git.exe checkout master
git.exe pull
git.exe gc

Set-Location y:
git.exe reset --hard
git.exe checkout master
git.exe pull
git.exe gc

& "c:\buildauto\buildhelper.ps1"

