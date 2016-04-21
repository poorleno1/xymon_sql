
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
    }

$server = New-Object -typeName Microsoft.SqlServer.Management.Smo.Server -argumentList "$serverName"

GetSqlInfo