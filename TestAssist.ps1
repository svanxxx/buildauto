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
        $LogFile = "$($directory)\log.txt"
        if (!(Test-Path -Path $CheckFile) -and (Test-File-Valid -Path $status) -and (Test-File-Valid -Path $request)) {
            Add-Content -Path $LogFile -Value "$(Get-Date): new diretory found..."
            Write-Host "Detected goal directory: $($directory)"
            $Files = Get-Content -Path $status
            if ($Files -is [array]) {
                $StartTest = $true
                $hashes = [System.Collections.ArrayList]::new()
                for ($f = 0; $f -lt $Files.Length; $f++) {
                    $FileNameToTest = Split-Path $Files[$f] -leaf
                    $file = "$($directory)\$($FileNameToTest)"
                    if (!(Test-File-Valid -Path $file)) {
                        $StartTest = $false
                        Add-Content -Path $LogFile -Value "$(Get-Date): file is not ready: $($file)"
                        Write-Output "file hash is invalid: $($file)"
                        break
                    } else {
                        $md5 = $file + ".md5"
                        $ExpectedHash = Get-Content -Path $md5
                        $hashes.Add($ExpectedHash)
                    }
                }
                if ($StartTest) {
                    Write-Host "All files are ready, processing..."
                    Add-Content -Path $LogFile -Value "$(Get-Date): Starting...."
                    $testGuid = Split-Path $directory -leaf
                    New-Item -Path "$($WorkDirectory)$($testGuid)" -ItemType Directory -ErrorAction Ignore
                    Remove-Item "$($WorkDirectory)$($testGuid)\*" -Recurse -Force
                    $AllFilesAreOK = $true
                    for ($f = 0; $f -lt $Files.Length; $f++) {
                        $FileNameToTest = Split-Path $Files[$f] -leaf
                        $file = "$($directory)\$($FileNameToTest)"
                        $Destination = "$($WorkDirectory)$($testGuid)\$($FileNameToTest)"
                        Add-Content -Path $LogFile -Value "$(Get-Date): Copy $($FileNameToTest)"
                        Copy-Item -Path $file -Destination $Destination
                        Add-Content -Path $LogFile -Value "$(Get-Date): $($FileNameToTest) done"
                        $hash = Get-FileHash $Destination -Algorithm MD5
                        $hash = $hash.Hash
                        if ($hash -ne $hashes[$f]){
                            Write-Host "after file copy mD5 is wrong - repeating operation!"
                            Add-Content -Path $LogFile -Value "$(Get-Date): MD5 is wrong!"
                            $AllFilesAreOK = $false
                            break
                        } else {
                            Add-Content -Path $LogFile -Value "$(Get-Date): MD5 is OK"
                        }
                    }
                    if ($AllFilesAreOK){
                        "Processed time: $(Get-Date)" | Out-File -FilePath $CheckFile -Encoding ascii
                        $params = Get-Content -Path $($request)
                        $url = "http://localhost/api/request/add?" + $params.ToString()
                        Add-Content -Path $LogFile -Value "$(Get-Date): Adding web request..."
                        Invoke-RestMethod -Uri $($url)
                        Add-Content -Path $LogFile -Value "$(Get-Date): web request done"
                    }
                }
            }
        }
    }
    Write-Host $(Get-Date)
    Start-Sleep -Seconds 10

    #Cleanup:
    $MinimumAge = (Get-Date).AddDays(-5)
    $folders = Get-ChildItem -Path $TestDirectory -Directory | Where-Object {$_.LastWriteTime -lt $MinimumAge}
    foreach ($folder in $folders)
    {
        Remove-Item -LiteralPath $folder.FullName -Force -Recurse
    }

    $MinimumAge = (Get-Date).AddDays(-10)
    $folders = Get-ChildItem -Path $WorkDirectory -Directory | Where-Object {$_.LastWriteTime -lt $MinimumAge}
    foreach ($folder in $folders)
    {
        Remove-Item -LiteralPath $folder.FullName -Force -Recurse
    }
}
