# extract current file path
$thispath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
# include WOL command
. ($thispath + '.\SendWOL.ps1')

echo "Starting build machines control"
Do
{
	echo "Sleep 2 seconds"
    start-sleep -seconds 2
    # here is the code to get the xml file
    # ...
    # end

    $file1 = "$($thispath)\tmp\BuildCoordinatorStatus.xml"
    $file2 = "$($thispath)\tmp\BuildCoordinatorStatusNormalized.xml"
    #originally source file is a huge single line file. first: converting it to multiline
    (gc $($file1)) -replace '><', ">`r`n<" | Out-File $($file2)

    $dowwakeup = Select-String -Path $file2 -Pattern "Building=""False"""
    if ($dowwakeup -ne $null)
    {
        echo Contains String
    }
    else
    {
        echo Not Contains String
    }    
	#Send-WOL -mac 001132212D11 
} While ($TRUE)
