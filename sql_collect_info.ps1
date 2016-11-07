# This script will be executed from BBWin
# Edit C:\Program Files (x86)\BBWin\etc\BBWin.cfg and add new line in <externals> section
# <load value="powershell -ExecutionPolicy Unrestricted -file collect_SQL_info2.ps1" timer="30m"/>

# Last update: 26.11.2015
# Added by: Viktors
# Added DBMemory column. Memory used by database in MB.

# Last update: 20.11.2015
# Added by: Viktors
# Added DBSize column

# Last update: 19.11.2015
# Added by: Viktors
# Added function GetDiscoverySummaryFile to read SQL discovery information

# Last update: 06.06.2016
# Added by: jarekole
# Added function GetDiscoverySummaryFile to read SQL discovery information

# Last update: 25.07.2016
# Added by: jarekole
# Added an optional parameter - main server

#Last update: 28.10.2016
# Added function Get-SQLInstance - used to discover instances, especially on cluster.
# Added information about date when backup was taken

#Last update: 07.11.2016
# Modified function Get-SQLInstance - used to discover instances, especially on cluster.

 param (
    [string]$xymon_server = "xymon.statoilfuelretail.com"
 )


# For testing = 0.
$XymonReady = 1

function GetSqlInfo ([string] $SqlInstance)
{

    #$server = New-Object -typeName Microsoft.SqlServer.Management.Smo.Server -argumentList "$SqlInstance"

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
                } ElseIf ($regKey.GetSubKeyNames() -contains "SQLEXPRESS") {
                    $instances = @()
                    $instances1 = @($regKey.GetSubKeyNames())
                    $instances1 | ForEach-Object {
                    Write-host "Found values: $_"
                    if ($_ -like 'SQL*') { $instances += $_ }
                    #ForEach ($inst in $instances) {
                    #if ($inst -like 'SQL*') { $instances += $inst }
                    }
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

# Return specific counter from table sys.dm_os_performance counters
function GetCounterValue ([string] $SqlCounterName)
{
    $db = $server.Databases.Item("master");
    $sqlquery = "SELECT cntr_value FROM sys.dm_os_performance_counters WHERE [counter_name] = '" + $SqlCounterName + "'"

    $result = $db.ExecuteWithResults($sqlquery)

    $table = $result.Tables[0]

    foreach ($row in $table)
    {
        $SqlCounterValue = $row.Item("cntr_value")
    }

    return $SqlCounterValue
}


# Return specific counter from table sys.dm_os_performance counters at database level
function GetDBCounterValue ([string] $SqlCounterName, [string] $SqlDbName)
{
    $db = $server.Databases.Item("master");
    $sqlquery = "SELECT cntr_value FROM sys.dm_os_performance_counters WHERE [counter_name] = '" + $SqlCounterName + "' AND [instance_name] = '"+ $SqlDBName + "'"

    $result = $db.ExecuteWithResults($sqlquery)
    
    $table = $result.Tables[0]

    foreach ($row in $table)
    {
        $SqlCounterValue = $row.Item("cntr_value")
    }

    return $SqlCounterValue
}

function GetDBUsers ([string] $SqlDbName)
{
    $db = $server.Databases.Item("master");
    # $sqlquery = "SELECT cntr_value FROM sys.dm_os_performance_counters WHERE [counter_name] = '" + $SqlCounterName + "' AND [instance_name] = '"+ $SqlDBName + "'"
    $sqlquery = "select DB_NAME(dbid) as DBName, COUNT(dbid) as NumberOfConnections, loginame as LoginName FROM sys.sysprocesses WHERE DB_NAME(dbid)='" + $SqlDBName + "' GROUP BY     dbid, loginame"
    $result = $db.ExecuteWithResults($sqlquery)
    
    $table = $result.Tables[0]
    $SqlCounterText = "DBName`t`tUsers`tLogin`n"
    
    if($result.Tables[0].rows.count -gt 0){    
    
        foreach ($row in $table)
        {
            $SqlCounterText += $row.Item("DBName") + "`t" + $row.Item("NumberOfConnections") + "`t" + $row.Item("LoginName") + "`n"
        }
        
        foreach ($row in $table)
        {
            $SqlCounterValue += $row.Item("NumberOfConnections")
        }
    }
    else
    {
    $SqlCounterValue = 0
    }
    
    $returnArray =@()
    $returnArray += $SqlCounterValue 
    $returnArray += $SqlCounterText 
    
    return $returnArray

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

# Main code
$SqlServer = $(hostname)
$alertColour = 'green'

# get instances based on services

$localInstances = @()

<#
[array]$captions = gwmi win32_service -computerName $SqlServer | ?{$_.Name -match "mssql*" -and $_.PathName -match "sqlservr.exe"} | %{$_.Caption}
foreach ($caption in $captions) {
	if ($caption -eq "MSSQLSERVER") {
		$localInstances += "MSSQLSERVER"
	} else {
				$temp = $caption | %{$_.split(" ")[-1]} | %{$_.trimStart("(")} | %{$_.trimEnd(")")} | %{$_.Replace("#","-")}
		$localInstances += $temp
	}
}

#>
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

    # This is global variable used in all funtions
    $server = New-Object -typeName Microsoft.SqlServer.Management.Smo.Server -argumentList "$serverName"

    #Get SQL instance information
    $sqlinfo = GetSqlInfo | Out-String

    #Add information from SQL discovery file
    $sqldiscoveryinfo = GetDiscoverySummaryFile | Out-String

    $sqlinfo = $sqlinfo + $sqldiscoveryinfo

    $outputtext = ((get-date -format G) + '<br><h2>MS SQL instance information</h2><br/> {0}' -f $sqlinfo)

    $output = ('status {0}.SQLInfo {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    #Get SQL instance Buffer cache hit ratio
    $sqlinfo_a =  GetCounterValue "Buffer cache hit ratio"
    $sqlinfo_b = GetCounterValue "Buffer cache hit ratio base"
    
    $sqlinfo = 100*$sqlinfo_a / $sqlinfo_b


    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Buffer cache hit ratio</h2> "  + "`n" + 'BufferCacheHR: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.BuffCHR {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output

    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }




    #Get SQL instance Target Server Memory (KB)
    $sqlinfo_a = GetCounterValue "Target Server Memory (KB)"
    $sqlinfo_a = $sqlinfo_a / 1024 | Out-string
    $sqlinfo_b = GetCounterValue "Total Server Memory (KB)"
    $sqlinfo_b = $sqlinfo_b / 1024

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Server Memory (MB)</h2> "  + "`n" + 'TargetServerMemory: {0}' -f $sqlinfo_a + "`n" + 'TotalServerMemory: {0}' -f $sqlinfo_b)
    	 
    $output = ('status {0}.ServerMemory {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }


    #Get SQL instance Page life expectancy
    $sqlinfo = GetCounterValue "Page life expectancy" | Out-String
    

    $sqlinfoDBPG = GetCounterValue "Database Pages" 
    $sqlinfoDBPG = 300*($sqlinfoDBPG*8/(1024*1024))
    

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Page life expectancy</h2> "  + "`n" + 'PageLifeExpectancy: {0}' -f $sqlinfo + "`n" + 'PageLifeExpectancyVal {0}' -f $sqlinfoDBPG)


    	 
    $output = ('status {0}.PageLifeExpectancy {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }


    #Get SQL instance User Connections
    $sqlinfo = GetCounterValue "User Connections" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance User Connections</h2> "  + "`n" + 'UserConnections: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.UserConnections {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }


    #Get SQL instance Connection Memory (KB)
    $sqlinfo = GetCounterValue "Connection Memory (KB)" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Connection Memory (KB)</h2> "  + "`n" + 'ConnectionMemory: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.ConnectionMemory {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }




    #Get SQL instance Database Pages
    $sqlinfo = GetCounterValue "Database Pages" | Out-String

    #$outputtext = ((get-date -format G) + '<br><h2>MS SQL instance Database Pages</h2><br/> {0}' -f $sqlinfo)
    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Database Pages</h2> "  + "`n" + 'DatabasePages: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.DBPages {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    #Get SQL instance Target pages
    $sqlinfo = GetCounterValue "Target pages" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Target pages</h2> "  + "`n" + 'TargetPages: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.TargetPages {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    #Get SQL instance Free pages
    $sqlinfo = GetCounterValue "Free pages" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Free pages</h2> "  + "`n" + 'FreePages: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.FreePages {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    #Get SQL instance Stolen pages
    $sqlinfo = GetCounterValue "Stolen pages" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Stolen pages</h2> "  + "`n" + 'StolenPages: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.StolenPages {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    #Get Memory Grants Pending
    $sqlinfo = GetCounterValue "Memory Grants Pending" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Memory Grants Pending</h2> "  + "`n" + 'MemoryGrantsPend: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.MemGrPend {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    #Get Free list stalls/sec
    $sqlinfo = GetCounterValue "Free list stalls/sec" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Free list stalls/sec</h2> "  + "`n" + 'FreeList: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.FreeList {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    # Get Page reads/sec
    $sqlinfo = GetCounterValue "Page reads/sec" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Page reads/sec</h2> "  + "`n" + 'PageReads: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.PageRead {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    # Get Page writes/sec
    $sqlinfo = GetCounterValue "Page writes/sec" | Out-String

    $outputtext = ((get-date -format G) + "`n" + "<h2>MS SQL instance Page writes/sec</h2> "  + "`n" + 'PageWrites: {0}' -f $sqlinfo)
    	 
    $output = ('status {0}.PageWrite {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }


    <#

    $server = New-Object -typeName Microsoft.SqlServer.Management.Smo.Server -argumentList "$serverName"

    $dbs = $server.Databases

    # $dbs | SELECT Name, Collation, CompatibilityLevel, AutoShrink, RecoveryModel, Size, SpaceAvailable

    $db = $server.Databases.Item("master");

    # $sqlquery = "select @@version"
    $sqlquery = "SELECT cntr_value FROM sys.dm_os_performance_counters WHERE [counter_name] = 'Buffer cache hit ratio'"

    $result = $db.ExecuteWithResults($sqlquery)

    $table = $result.Tables[0];

    # $table_output = $result.tables.column1
    $table_output = $result.tables.cntr_value

    "Buffer cache hit ratio is: " + $table_output

    #>

    # Get SQL Server start time.
    # The sqlserver_start_time column does not exist in sys.dm_os_sys_info in SQL Server 2005, so we will calculate the uptime based on the tempdb creation date.

	# $dbs = $server.Databases | Where-object {$_.name -notin ("master", "msdb", "tempdb", "model")} 

    $dbs = $server.Databases | Where-Object { "master", "msdb", "tempdb", "model" -notcontains $_.name }
	
    $db = $server.Databases.Item("master")
	$sqlquery = "SELECT create_date FROM sys.databases WHERE database_id = 2"
    $result = $db.ExecuteWithResults($sqlquery)
    # $SqlStartTime = $result.tables.create_date

    $table = $result.Tables[0]

    foreach ($row in $table)
    {
        $SqlStartTime = $row.Item("create_date")
    }


    $date_now = Get-Date

    "SQL Server start time is: " + $SqlStartTime

    $timespan = new-timespan -start $SqlStartTime -end $date_now

    #Calculate SQL Server uptime in seconds and milliseconds.
    $UpTime = $timespan.TotalSeconds
    $UpTimeMs = $timespan.TotalMilliSeconds

    "Up time in seconds: " + $UpTime
    "Up time in milliseconds: " + $UpTimeMs

    # Get memory used for every DB. Result fields: DB_NAME, MB
    # http://dba.stackexchange.com/questions/17486/memory-utilization-per-database-sql-server
    # https://www.mssqltips.com/sqlservertip/2393/determine-sql-server-memory-use-by-database-and-object/

    $memory_sql = "SELECT db_name(database_id) as DB_NAME, (count(*) * 8 / 1024) as MB FROM sys.dm_os_buffer_descriptors WHERE database_id BETWEEN 5 AND 32766 GROUP BY db_name(database_id) ,database_id"
    $memory_result = $db.ExecuteWithResults($memory_sql)
    $memory_table = $memory_result.Tables[0]

if($memory_table) {

    #Write-host "Object exists."
    foreach ($memory_row in $memory_table)
    {
        "DB name  : " + $memory_row.db_name
        "DB memory: " + $memory_row.mb

        #Add DB name to server-instance name
        $XymonClientNameDB = $XymonClientName+"-"+$memory_row.db_name

        "Xymon DB name: " + $XymonClientNameDB

        $sqlinfo = $memory_row.mb | Out-String
      
        $outputtext = ((get-date -format G) + "`n" + "<h2>DB memory used in MB</h2> "  + "`n" + 'DBMemory: {0}' -f $sqlinfo)
    	 
        $output = ('status {0}.DBMemory {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
        
    }


   } else {
   Write-host " "
   }
    if($dbs) {
    Write-host "There are user databases. Looping throught them."
    # Loop through all databases
    foreach ($db in $dbs)
    {
        
        "DB name: " + $db.name

        "DB size: " + $db.size

        #Add DB name to server-instance name
        $XymonClientNameDB = $XymonClientName+"-"+$db.Name

        "Xymon DB name: " + $XymonClientNameDB

        # Get Log Flush Wait Time for given DB
        $sqlinfo = GetDBCounterValue "Log Flush Wait Time" $db.name | Out-String
      
        $outputtext = ((get-date -format G) + "`n" + "<h2>Log Flush Wait Time</h2> "  + "`n" + 'LogFlush: {0}' -f $sqlinfo)
    	 
        $output = ('status {0}.LogFlush {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

        # Get Log Growths for given DB
        $sqlinfo = GetDBCounterValue "Log Growths" $db.name | Out-String
      
        $outputtext = ((get-date -format G) + "`n" + "<h2>Log Growths</h2> "  + "`n" + 'LogGrowths: {0}' -f $sqlinfo)
    	 
        $output = ('status {0}.LogGrowths {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

        # Get Log Shrinks for given DB
        $sqlinfo = GetDBCounterValue "Log Shrinks" $db.name | Out-String
      
        $outputtext = ((get-date -format G) + "`n" + "<h2>Log Shrinks</h2> "  + "`n" + 'LogShrinks: {0}' -f $sqlinfo)
    	 
        $output = ('status {0}.LogShrinks {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

        # Get Percent Log Used for given DB
        $sqlinfo = GetDBCounterValue "Percent Log Used" $db.name | Out-String
      
        $outputtext = ((get-date -format G) + "`n" + "<h2>Percent Log Used</h2> "  + "`n" + 'PrcLogUsed: {0}' -f $sqlinfo)
    	 
        $output = ('status {0}.PrcLogUsed {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
        
        # Get Number of Users connected for gived DB
        
        #$sqlinfo = GetDBUsers $db.name | Out-String
        $sqlinfo = GetDBUsers $db.name
      
        $outputtext = ((get-date -format G) + "`n" + "<h2>Number of users</h2> "  + "`n" +$($sqlinfo[1]) + "`n" + 'NoUsers: {0}' -f $($sqlinfo[0]))
    	 
        $output = ('status {0}.NoUsers {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
        
        
        

        # Get Transactions/sec for given DB
        $sqlinfo = GetDBCounterValue "Transactions/sec" $db.name | Out-String

        # Divide result by SQL server uptime in seconds
        $sqlinfo = [math]::Round($sqlinfo / $UpTime,2)
      
        $outputtext = ((get-date -format G) + "`n" + "<h2>Transactions/sec</h2> "  + "`n" + 'TransSec: {0}' -f $sqlinfo)
    	 
        $output = ('status {0}.TransSec {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

        # Get database size in MB
        $sqlinfo = [math]::Round($db.size)

        $outputtext = ((get-date -format G) + "`n" + "<h2>DB size (MB)</h2> "  + "`n" + 'DBSize: {0}' -f $sqlinfo)

        $output = ('status {0}.DBSize {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

		<#
        $model = $db.recoverymodel
        if ($model -eq 1)
        {
            $modelname = "Full"
        }
        elseif ($model -eq 2)
        {
            $modelname = "Bulk Logged"
        }
        elseif ($model -eq 3)
        {
        $modelname = "Simple"
        }
		#>
		
		#Get database backup information
		
		$model = $db.recoverymodel
		$LastBackupDate = $db.LastBackupDate
		$LastDifferentialBackupDate = $db.LastDifferentialBackupDate
		$LastLogBackupDate = $db.LastLogBackupDate
		
		$outputtext = ((get-date -format G) + "`n" + "<h2>DB Backup information</h2> " + "`n" + 'RecoveryModel: {0}' -f $model + "`n" + 'LastBackupDate: {0}' -f $db.LastBackupDate + "`n" + 'LastDifferentialBackupDate: {0}' -f $db.LastDifferentialBackupDate+ "`n" + 'LastLogBackupDate: {0}' -f $db.LastLogBackupDate)

        $output = ('status {0}.Backup {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
		
		#Get DB status
		
		$status = $db.Status
		
		$outputtext = ((get-date -format G) + "`n" + "<h2>DB Backup information</h2> " + "`n" + 'Database Status: {0}' -f $status)
		
		if ($status -eq "Normal" -or $status -eq "Restoring")  {$alertColour = "green"} else {$alertColour = "yellow"}

#		+ "`n" + 'LastBackupDate: {0}' -f $db.LastBackupDate + "`n" + 'LastDifferentialBackupDate: {0}' -f $db.LastDifferentialBackupDate+ "`n" + 'LastLogBackupDate: {0}' -f $db.LastLogBackupDate)

        $output = ('status {0}.Status {1} {2}' -f $XymonClientNameDB, $alertColour, $outputtext)
        "Output string for Xymon: " + $output
        if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
		$alertColour = 'green'
		
		
    }



} else {Write-host "There are no user databases."}
} 
Write-Host "End."
<#

# Load Smo and referenced assemblies.
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.ConnectionInfo');
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.Management.Sdk.Sfc');
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO');
# Requiered for SQL Server 2008 (SMO 10.0).
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMOExtended');


$server =  New-Object Microsoft.SqlServer.Management.Smo.Server ".\SQLEXPRESS";
$db = $server.Databases.Item("master");

[String] $sql = "SELECT [name] ,[create_date] FROM [master].[sys].[databases] ORDER BY [name];";
$result = $db.ExecuteWithResults($sql);
$table = $result.Tables[0];

foreach ($row in $table)
{
    Write-Host $row.Item("name") $row.Item("create_date");
}

#>