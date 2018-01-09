# extract current file path
$thispath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
# include WOL command
. ($thispath + '.\SendWOL.ps1')
. ($thispath + '.\GetMACAddress.ps1')

$statusfile = "$($thispath)/tmp/Status.xml"

echo "Starting build machines control"
Do
{
    # here is the code to get the xml file
    $Command = "xgcoordconsole.exe"
    $Parms = ("/exportstatus=$($statusfile)")
    $Prms = $Parms.Split(" ")
    & "$Command" $Prms | out-null


    [xml]$XmlDocument = Get-Content -Path $statusfile
    $Agents = $XmlDocument.SelectSingleNode("//Agents") 
    $Building = $false
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
        echo "stopping machines..."
        FOREACH ($Agent in $Agents.ChildNodes)
        {
            $AgentName = $Agent.Attributes.GetNamedItem("Host").Value
            if ($Agent.Attributes.GetNamedItem("Online").Value -eq "True")
            {
                $machinefilename = "$($thispath)\machines\$($AgentName)"

                #file exists and size is greater than 0 and was created NOT recently (5 days) - DO nothing
                $timespan = new-timespan -days 5
                $condition = ((Test-Path $machinefilename) -and ((Get-Item $machinefilename).Length -gt 0) -and (((get-date) - (Get-Item $machinefilename).LastWriteTime) -gt $timespan))
                if ($condition)
                {
                    #only for machines that are phisically online:
                    $ison = Test-Connection $AgentName -Count 1 -Quiet
                    if ($ison)
                    {
                        echo "Getting MAC of: $($AgentName)...."
                        $results = Get-MACAddress $AgentName | Out-String
                        if ($results -ne "")
                        {
                            $results | Out-File $machinefilename
                        }
                    }
                }
            }
            if (($Agent.Attributes.GetNamedItem("LoggedOnUsers").Value -eq "") -and ($Agent.Attributes.GetNamedItem("Online").Value -eq "True"))
            {
                #only for machines that are phisically online:
                $ison = Test-Connection $AgentName -Count 1 -Quiet
                if ($ison)
                {
                    echo "Stopping: $($AgentName)...."
                    stop-computer $AgentName
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
                foreach($line in Get-Content $AgentFile)
                {
                    if($line.Contains(":"))
                    {
                       if ($started -eq $false)
                       {
                            echo "starting machines..."
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
    Get-Date -Format HH:MM:ss
    start-sleep -seconds 5
} While ($TRUE)
