$svc = New-WebServiceProxy -Uri "http://192.168.0.1/taskmanagerbeta/trservice.asmx?WSDL"
# extract current file path
$thispath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
# include WOL command
. ($thispath + '.\add\SendWOL.ps1')
. ($thispath + '.\add\GetMACAddress.ps1')

$statusfile = "$($thispath)/tmp/Status.xml"
$mymachines = New-Object System.Collections.ArrayList

Write-Output "Starting build machines control"
Do
{
    # here is the code to get the xml file
    Write-Output "Getting information from coordinator..."
    $Command = "xgcoordconsole.exe"
    $Parms = ("/exportstatus=$($statusfile)")
    $Prms = $Parms.Split(" ")
    & "$Command" $Prms | out-null


    [xml]$XmlDocument = Get-Content -Path $statusfile
    $Agents = $XmlDocument.SelectSingleNode("//Agents") 
    $Building = $false
    Write-Output "Parsing xml..."
    FOREACH ($Agent in $Agents.ChildNodes)
    {
        if ($Agent.Attributes.GetNamedItem("Building").Value -eq "True")
        {
           $Building = $true
           break
        }
    }

    if ($Building -eq $false)
    {
        $Building = $svc.hasBuildRequest()
    }

    Write-Output "Checking MAC addresses..."
    FOREACH ($Agent in $Agents.ChildNodes)
    {
        $AgentName = $Agent.Attributes.GetNamedItem("Host").Value
        if ($Agent.Attributes.GetNamedItem("Online").Value -eq "True")
        {
            $machinefilename = "$($thispath)\machines\$($AgentName)"

            #file exists and size is greater than 0 and was created NOT recently (5 days) - DO nothing
            $timespan = new-timespan -days 5
            $condition = ((Test-Path $machinefilename) -and ((Get-Item $machinefilename).Length -gt 0) -and (((get-date) - (Get-Item $machinefilename).LastWriteTime) -lt $timespan))
            if ($condition -eq $false)
            {
                Write-Output "Checking machine for online status: $($AgentName)..."
                #only for machines that are phisically online:
                $ison = Test-Connection $AgentName -Count 1 -Quiet -TimeToLive 5
                if ($ison)
                {
                    Write-Output "Getting MAC of: $($AgentName)...."
                    $results = Get-MACAddress $AgentName | Out-String
                    if ($results -ne "")
                    {
                        $results | Out-File $machinefilename
                    }
                }
            }
        }
    }

    if ($Building -eq $false)
    {
        $stopped = $false
        FOREACH ($Agent in $Agents.ChildNodes)
        {
            $AgentName = $Agent.Attributes.GetNamedItem("Host").Value
            if (($mymachines.Contains($AgentName)) -and ($Agent.Attributes.GetNamedItem("LoggedOnUsers").Value -eq "") -and ($Agent.Attributes.GetNamedItem("Online").Value -eq "True"))
            {
                $mymachines.Remove($AgentName)
                #only for machines that are phisically online:
                $ison = Test-Connection $AgentName -Count 1 -Quiet
                if ($ison)
                {
                    if ($stopped -eq $false)
                    {
                        Start-Sleep -seconds 10 #allow build machine to clean cache files before shutdown
                        Write-Output "stopping machines..."
                        $stopped = $true
                    }

                    Write-Output "Stopping: $($AgentName)...."
                    if ($svc.hasBuildRequest() -eq $false)
                    {
                        stop-computer -ComputerName $AgentName
                    }
                }
            }
        }
    }
    else
    {
       $started = $false
       FOREACH ($Agent in $Agents.ChildNodes)
       {
           $AgentName = $Agent.Attributes.GetNamedItem("Host").Value
           $AgentFile = "$($thispath)/machines/$($AgentName)"
           if ((Test-Path $AgentFile) -and ($Agent.Attributes.GetNamedItem("LoggedOnUsers").Value -eq "") -and ($Agent.Attributes.GetNamedItem("Online").Value -eq "False"))
           {
                if ($mymachines.Contains($AgentName) -eq $false)
                {
                    $mymachines.Add($AgentName)
                }
                foreach($line in Get-Content $AgentFile)
                {
                    if($line.Contains(":"))
                    {
                       if ($started -eq $false)
                       {
                            Write-Output "starting machines..."
                            $started = $true
                       }
                       $line = $line -replace ':',''
                       $Command = "$($thispath)/bin/WolCmd.exe"
                       $Parms = "$($line) 192.168.0.1 255.255.255.0 3"
                       $Prms = $Parms.Split(" ")
                       & "$Command" $Prms
                    }
                }
           }
       }
    }
    Get-Date -Format HH:mm:ss
    Start-Sleep -seconds 5
} While ($TRUE)
