function md5hash($filename)
{
    $md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $file = [System.IO.File]::Open($filename,[System.IO.Filemode]::Open, [System.IO.FileAccess]::Read)
    try {
        [System.BitConverter]::ToString($md5.ComputeHash($file))
    } finally {
        $file.Dispose()
    }
}
$hashdir = "C:\Users\62049\Downloads\"
$filename = $hashdir + "FIELDPRO_8e_350_51_505_ACT.msi"
$hashfilename = $filename + ".md5"
$hash = md5hash $filename 
$hash = $hash.Replace("-", "")
$correcthash = Get-Content -Path $hashfilename
$correcthash = $correcthash.Trim().ToUpper()
if ($hash -eq $correcthash){
    Write-Host "ok"
} else {
    Write-Host "not ok"
}