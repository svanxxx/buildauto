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
    & "$Command" $Prms


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
                $results = Get-MACAddress $AgentName | Out-String
                if ($results -ne "")
                {
                    $results | Out-File $machinefilename
                }
            }
            if (($Agent.Attributes.GetNamedItem("LoggedOnUsers").Value -eq "") -and ($Agent.Attributes.GetNamedItem("Online").Value -eq "True"))
            {
                echo $AgentName
                stop-computer $AgentName
            }
        }
    }
    else
    {
       echo "starting machines..."
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
    echo "Sleep 15 seconds"
    start-sleep -seconds 15
} While ($TRUE)
