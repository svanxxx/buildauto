$TestDirectory = "H:\My Drive\Installations\ReleaseSocket\"
$WorkDirectory = "G:\ReleaseSocket\Stack\"
function Test-File-Valid {
    param (
        [string]$Path
    )
    $null = @(
        $result = $true
        $md5 = $Path + ".md5"
        if (!(Test-Path -Path $Path)) {
            $result = $false
        }
        if ($result -and !(Test-Path -Path $md5)) {
            $result = $false
        }
        if ($result) {
            $ExpectedHash = Get-Content -Path $md5
            $hash = Get-FileHash $Path -Algorithm MD5
            $result = ($ExpectedHash -eq $hash.Hash)
        }
    )
    return $result
}
while ($true) {
    Get-ChildItem -Path $($TestDirectory) -Recurse -Directory -Force -ErrorAction SilentlyContinue | Select-Object FullName |
    Foreach-Object {
        $directory = $_.FullName
        $status = "$($directory)\status.txt"
        $request = "$($directory)\request.txt"
        $CheckFile = "$($directory)\processed.txt"
        if (!(Test-Path -Path $CheckFile) -and (Test-File-Valid -Path $status) -and (Test-File-Valid -Path $request)) {
            Write-Host "Detected goal directory: $($directory)"
            $Files = Get-Content -Path $status
            if ($Files -is [array]) {
                $StartTest = $true
                for ($f = 0; $f -lt $Files.Length; $f++) {
                    $FileNameToTest = Split-Path $Files[$f] -leaf
                    $file = "$($directory)\$($FileNameToTest)"
                    if (!(Test-File-Valid -Path $file)) {
                        $StartTest = $false
                    }
                }
                if ($StartTest) {
                    Write-Host "All files are ready, processing..."
                    "Processed time: $(Get-Date)" | Out-File -FilePath $CheckFile -Encoding ascii
                    $testGuid = Split-Path $directory -leaf
                    New-Item -Path "$($WorkDirectory)$($testGuid)" -ItemType Directory
                    for ($f = 0; $f -lt $Files.Length; $f++) {
                        $FileNameToTest = Split-Path $Files[$f] -leaf
                        $file = "$($directory)\$($FileNameToTest)"
                        $Destination = "$($WorkDirectory)$($testGuid)\$($FileNameToTest)"
                        Copy-Item -Path $file -Destination $Destination
                    }
                    $params = Get-Content -Path $($request)
                    $url = "http://localhost/api/request/add?" + $params.ToString()
                    Invoke-RestMethod -Uri $($url)
                }
            }
        }
    }
    Write-Host $(Get-Date)
    Start-Sleep -Seconds 10
}
