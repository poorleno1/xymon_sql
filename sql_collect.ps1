
Function Get-PerformanceCounterLocalName
{
  param
  (
    [UInt32]
    $ID,
 
    $ComputerName = $env:COMPUTERNAME
  )
 
  $code = '[DllImport("pdh.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern UInt32 PdhLookupPerfNameByIndex(string szMachineName, uint dwNameIndex, System.Text.StringBuilder szNameBuffer, ref uint pcchNameBufferSize);'
 
  $Buffer = New-Object System.Text.StringBuilder(1024)
  [UInt32]$BufferSize = $Buffer.Capacity
 
  $t = Add-Type -MemberDefinition $code -PassThru -Name PerfCounter -Namespace Utility
  $rv = $t::PdhLookupPerfNameByIndex($ComputerName, $id, $Buffer, [Ref]$BufferSize)
 
  if ($rv -eq 0)
  {
    $Buffer.ToString().Substring(0, $BufferSize-1)
  }
  else
  {
    Throw 'Get-PerformanceCounterLocalName : Unable to retrieve localized name. Check computer name and performance counter ID.'
  }
}


function Get-PerformanceCounterID
{
    param
    (
        [Parameter(Mandatory=$true)]
        $Name
    )
 
    if ($script:perfHash -eq $null)
    {
        #Write-Progress -Activity 'Retrieving PerfIDs' -Status 'Working'
 
        $key = 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\CurrentLanguage'
        $counters = (Get-ItemProperty -Path $key -Name Counter).Counter
        $script:perfHash = @{}
        $all = $counters.Count
 
        for($i = 0; $i -lt $all; $i+=2)
        {
           Write-Progress -Activity 'Retrieving PerfIDs' -Status 'Working' -PercentComplete ($i*100/$all)
           $script:perfHash.$($counters[$i+1]) = $counters[$i]
        }
    }
 
    $script:perfHash.$Name
}


function GetDiscoverySummaryFile
{

# Location of summary.txt depends on SQL version
# SQL 2008 R2 - "C:\Program Files\Microsoft SQL Server\100\Setup Bootstrap\Log\Summary.txt"
# "C:\Program Files\Microsoft SQL Server\100\Setup Bootstrap\SQLServer2008R2\setup.exe" /Action=RunDiscovery /q

# SQL 2012 - "C:\Program Files\Microsoft SQL Server\110\Setup Bootstrap\Log\Summary.txt"
# "C:\Program Files\Microsoft SQL Server\110\Setup Bootstrap\SQLServer2012\setup.exe" /Action=RunDiscovery /q

# SQL 2014 - "C:\Program Files\Microsoft SQL Server\120\Setup Bootstrap\Log\Summary.txt"
# "C:\Program Files\Microsoft SQL Server\120\Setup Bootstrap\SQLServer2014\setup.exe" /Action=RunDiscovery /q

    $SQLSummaryFile = ""

    If ((Test-Path -Path "C:\Program Files\Microsoft SQL Server\100\Setup Bootstrap\SQLServer2008R2\setup.exe") -eq $true)
    {
        $SQLSummaryFile = Get-Content "C:\Program Files\Microsoft SQL Server\100\Setup Bootstrap\Log\Summary.txt"
    }
    elseif ((Test-Path -Path "C:\Program Files\Microsoft SQL Server\110\Setup Bootstrap\SQLServer2012\setup.exe") -eq $true)
    {
        $SQLSummaryFile = Get-Content "C:\Program Files\Microsoft SQL Server\110\Setup Bootstrap\Log\Summary.txt"
    }
    elseif ((Test-Path -Path "C:\Program Files\Microsoft SQL Server\120\Setup Bootstrap\SQLServer2014\setup.exe") -eq $true)
    {
        $SQLSummaryFile = Get-Content "C:\Program Files\Microsoft SQL Server\120\Setup Bootstrap\Log\Summary.txt"
    }

    return $SQLSummaryFile

}


# Communicate with Xymon server
function XymonSend($msg, $servers)
{
	$saveresponse = 1	# Only on the first server
	$outputbuffer = ""
	$ASCIIEncoder = New-Object System.Text.ASCIIEncoding

	foreach ($srv in $servers) {
		$srvparams = $srv.Split(":")
		# allow for server names that may resolve to multiple A records
		$srvIPs = & {
			$local:ErrorActionPreference = "SilentlyContinue"
			$srvparams[0] | %{[system.net.dns]::GetHostAddresses($_)} | %{ $_.IPAddressToString}
		}
		if ($srvIPs -eq $null) { # no IP addresses could be looked up
			Write-Error -Category InvalidData ("No IP addresses could be found for host: " + $srvparams[0])
		} else {
			if ($srvparams.Count -gt 1) {
				$srvport = $srvparams[1]
			} else {
				$srvport = 1984
			}
			foreach ($srvip in $srvIPs) {

				$saveerractpref = $ErrorActionPreference
				$ErrorActionPreference = "SilentlyContinue"
				$socket = new-object System.Net.Sockets.TcpClient
				$socket.Connect($srvip, $srvport)
				$ErrorActionPreference = $saveerractpref
				if(! $? -or ! $socket.Connected ) {
					$errmsg = $Error[0].Exception
					Write-Error -Category OpenError "Cannot connect to host $srv ($srvip) : $errmsg"
					continue;
				}
				$socket.sendTimeout = 500
				$socket.NoDelay = $true

				$stream = $socket.GetStream()
				
				$sent = 0
				foreach ($line in $msg) {
					# Convert data to ASCII instead of UTF, and to Unix line breaks
					$sent += $socket.Client.Send($ASCIIEncoder.GetBytes($line.Replace("`r","") + "`n"))
				}

				if ($saveresponse-- -gt 0) {
					$socket.Client.Shutdown(1)	# Signal to Xymon we're done writing.

					$s = new-object system.io.StreamReader($stream,"ASCII")

					start-sleep -m 200  # wait for data to buffer
					$outputBuffer = $s.ReadToEnd()
				}

				$socket.Close()
			}
		}
	}
	$outputbuffer
}



function GetSqlInfo ([string] $SqlInstance)
{

    # $server = New-Object -typeName Microsoft.SqlServer.Management.Smo.Server -argumentList "$SqlInstance"

	$SqlInfo = "" | Select Version,Edition,fullVer,majVer,minVer,Build,Arch,Level,Root,Instance
	[string]$SqlInfo.fullVer = $server.information.VersionString.toString()
	[string]$SqlInfo.Edition = $server.information.Edition.toString()
	[int]$SqlInfo.majVer = $server.version.Major
	[int]$SqlInfo.minVer = $server.version.Minor
	[int]$SqlInfo.build = $server.version.Build
	switch ($SqlInfo.majVer) {
		8 {[string]$SqlInfo.Version = "SQL Server 2000"}
		9 {[string]$SqlInfo.Version = "SQL Server 2005"}
		10 {if ($SqlInfo.minVer -eq 0 ) {
					[string]$SqlInfo.Version = "SQL Server 2008"
				} else {
					[string]$SqlInfo.Version = "SQL Server 2008 R2"
				}
			}
        11 {[string]$SqlInfo.Version = "SQL Server 2012"}
        12 {[string]$SqlInfo.Version = "SQL Server 2014"}
		default {[string]$SqlInfo.Version = "Unknown"}
	}
	[string]$SqlInfo.Arch = $server.information.Platform.toString()
	[string]$SqlInfo.Level = $server.information.ProductLevel.toString()
	[string]$SqlInfo.Root = $server.information.RootDirectory.toString()
	[string]$SqlInfo.Instance = $currInstance

return $SqlInfo

}


Function Get-SQLInstance {  
    <#
        .SYNOPSIS
            Retrieves SQL server information from a local or remote servers.
        .DESCRIPTION
            Retrieves SQL server information from a local or remote servers. Pulls all 
            instances from a SQL server and detects if in a cluster or not.
        .PARAMETER Computername
            Local or remote systems to query for SQL information.
        .NOTES
            Name: Get-SQLInstance
            Author: Boe Prox
            DateCreated: 07 SEPT 2013
        .EXAMPLE
            Get-SQLInstance -Computername DC1
            SQLInstance   : MSSQLSERVER
            Version       : 10.0.1600.22
            isCluster     : False
            Computername  : DC1
            FullName      : DC1
            isClusterNode : False
            Edition       : Enterprise Edition
            ClusterName   : 
            ClusterNodes  : {}
            Caption       : SQL Server 2008
            SQLInstance   : MINASTIRITH
            Version       : 10.0.1600.22
            isCluster     : False
            Computername  : DC1
            FullName      : DC1\MINASTIRITH
            isClusterNode : False
            Edition       : Enterprise Edition
            ClusterName   : 
            ClusterNodes  : {}
            Caption       : SQL Server 2008
            Description
            -----------
            Retrieves the SQL information from DC1
    #>
    [cmdletbinding()] 
    Param (
        [parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [Alias('__Server','DNSHostName','IPAddress')]
        [string[]]$ComputerName = $env:COMPUTERNAME
    ) 
    Process {
        ForEach ($Computer in $Computername) {
            $Computer = $computer -replace '(.*?)\..+','$1'
            Write-Verbose ("Checking {0}" -f $Computer)
            Try { 
                $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $Computer) 
                $baseKeys = "SOFTWARE\\Microsoft\\Microsoft SQL Server",
                "SOFTWARE\\Wow6432Node\\Microsoft\\Microsoft SQL Server"
                If ($reg.OpenSubKey($basekeys[0])) {
                    $regPath = $basekeys[0]
                } ElseIf ($reg.OpenSubKey($basekeys[1])) {
                    $regPath = $basekeys[1]
                } Else {
                    Continue
                }
                $regKey= $reg.OpenSubKey("$regPath")
                If ($regKey.GetSubKeyNames() -contains "Instance Names") {
                    $regKey= $reg.OpenSubKey("$regpath\\Instance Names\\SQL" ) 
                    $instances = @($regkey.GetValueNames())
                } ElseIf ($regKey.GetValueNames() -contains 'InstalledInstances') {
                    $isCluster = $False
                    $instances = $regKey.GetValue('InstalledInstances')
                } Else {
                    Continue
                }
                If ($instances.count -gt 0) { 
                    ForEach ($instance in $instances) {
                        $nodes = New-Object System.Collections.Arraylist
                        $clusterName = $Null
                        $isCluster = $False
                        $instanceValue = $regKey.GetValue($instance)
                        $instanceReg = $reg.OpenSubKey("$regpath\\$instanceValue")
                        If ($instanceReg.GetSubKeyNames() -contains "Cluster") {
                            $isCluster = $True
                            $instanceRegCluster = $instanceReg.OpenSubKey('Cluster')
                            $clusterName = $instanceRegCluster.GetValue('ClusterName')
                            $clusterReg = $reg.OpenSubKey("Cluster\\Nodes")                            
                            $clusterReg.GetSubKeyNames() | ForEach {
                                $null = $nodes.Add($clusterReg.OpenSubKey($_).GetValue('NodeName'))
                            }
                        }
                        $instanceRegSetup = $instanceReg.OpenSubKey("Setup")
                        Try {
                            $edition = $instanceRegSetup.GetValue('Edition')
                        } Catch {
                            $edition = $Null
                        }
                        Try {
                            $ErrorActionPreference = 'Stop'
                            #Get from filename to determine version
                            $servicesReg = $reg.OpenSubKey("SYSTEM\\CurrentControlSet\\Services")
                            $serviceKey = $servicesReg.GetSubKeyNames() | Where {
                                $_ -match "$instance"
                            } | Select -First 1
                            $service = $servicesReg.OpenSubKey($serviceKey).GetValue('ImagePath')
                            $file = $service -replace '^.*(\w:\\.*\\sqlservr.exe).*','$1'
                            $version = (Get-Item ("\\$Computer\$($file -replace ":","$")")).VersionInfo.ProductVersion
                        } Catch {
                            #Use potentially less accurate version from registry
                            $Version = $instanceRegSetup.GetValue('Version')
                        } Finally {
                            $ErrorActionPreference = 'Continue'
                        }
                        New-Object PSObject -Property @{
                            Computername = $Computer
                            SQLInstance = $instance
                            Edition = $edition
                            Version = $version
                            Caption = {Switch -Regex ($version) {
                                "^14" {'SQL Server 2014';Break}
                                "^11" {'SQL Server 2012';Break}
                                "^10\.5" {'SQL Server 2008 R2';Break}
                                "^10" {'SQL Server 2008';Break}
                                "^9"  {'SQL Server 2005';Break}
                                "^8"  {'SQL Server 2000';Break}
                                Default {'Unknown'}
                            }}.InvokeReturnAsIs()
                            isCluster = $isCluster
                            isClusterNode = ($nodes -contains $Computer)
                            ClusterName = $clusterName
                            ClusterNodes = ($nodes -ne $Computer)
                            FullName = {
                                If ($Instance -eq 'MSSQLSERVER') {
                                    $Computer
                                } Else {
                                    "$($Computer)\$($instance)"
                                }
                            }.InvokeReturnAsIs()
                        }
                    }
                }
            } Catch { 
                Write-Warning ("{0}: {1}" -f $Computer,$_.Exception.Message)
            }  
        }   
    }
}

# Example for Get-SQLInstance function call
<#
Get-SQLInstance -Verbose | ForEach { 
    If ($_.isClusterNode) { 
        If (($list -notcontains $_.Clustername)) { 
            Get-SQLInstance -ComputerName $_.ClusterName 
            $list += ,$_.ClusterName 
        } 
    } Else { 
        $_ 
    } 
}
# Result of Get-SQLInstance function
isCluster     : False
ClusterNodes  : {}
ClusterName   :
FullName      : SFRFIDCSQLA007P
isClusterNode : False
SQLInstance   : MSSQLSERVER
Version       : 10.50.2500.0
Edition       : Enterprise Edition
Caption       : SQL Server 2008 R2
Computername  : SFRFIDCSQLA007P
isCluster     : True
ClusterNodes  : {SFRFIDCPRDB004P}
ClusterName   : SFRFIDCPRNC115P
FullName      : SFRFIDCPRDB003P\PNPRODLV
isClusterNode : True
SQLInstance   : PNPRODLV
Version       : 11.2.5058.0
Edition       : Standard Edition
Caption       : SQL Server 2012
Computername  : SFRFIDCPRDB003P
#>

$SqlServer = $(hostname)
$xymon_server = "xymon.statoilfuelretail.com"
$alertColour = 'green'

# get instances based on services

$localInstances = @()

 Get-SQLInstance

$localInstances = Get-SQLInstance

# load the SQL SMO assembly
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null

foreach ($currInstance in $localInstances) {

    if ($currInstance.isClusterNode)
    {
        $serverName = $currInstance.ClusterName + "\" + $currInstance.SQLInstance
        $XymonClientName = $currInstance.ClusterName + "-" + $currInstance.SQLInstance
    }
    else
    {
        if ($currInstance.SQLInstance -eq "MSSQLSERVER")
        {
	        $serverName = $currInstance.FullName
            $XymonClientName = $currInstance.Computername + "-MSSQLSERVER"
        }
        else
        {
	        $serverName = $currInstance.FullName
            $XymonClientName = $currInstance.Computername + "-" + $currInstance.SQLInstance
        }
    }
    
    "Current instance name: " + $serverName
    "Xymon name: " + $XymonClientName
    $server = New-Object -typeName Microsoft.SqlServer.Management.Smo.Server -argumentList "$serverName"

    GetSqlInfo 
    }






GetSqlInfo 

