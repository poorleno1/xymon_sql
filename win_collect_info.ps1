# This script will be executed from XymonPS client

# Last update: 27.07.2016
# Added by: jarekole@gmail.com
# initial version of script

 param (
    [string]$xymon_server = "xymon.statoilfuelretail.com"
 )

#Write-Output "Param $($xymon_server)"

# For testing = 0.
$XymonReady = 1

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
$XymonClientName = $(hostname)
$alertColour = 'green'

#Get Memory - available mbytes
   


    #Get Memory - Pages Faults/sec, Pages Input/sec (Hard Page Faults) and Page Faults/sec - Pages Input/sec (Soft Page Faults)
    $CtrsList = "\Memory\Page Faults/sec","\Memory\Pages Input/sec",`
    "\Memory\Pages Output/sec","\Memory\Page Reads/sec",`
    "\Memory\Page Writes/sec","\Memory\Pool Nonpaged Bytes",`
    "\Memory\Pool paged bytes","\Memory\Committed Bytes",`
    "\Memory\% Committed Bytes in Use","\System\Processor Queue Length",`
    "\Paging file(*)\% Usage","\memory\available mbytes"
    $Vals = Get-Counter -counter $CtrsList | Select-Object -ExpandProperty CounterSamples | Select-Object path,CookedValue 
    
    $counterinfo = $vals[0].CookedValue - $vals[1].CookedValue
    $outputtext = ((get-date -format G) + "`n" + `
    "<h2>Memory - Page Faults/sec (sum of soft and hard page faults)</h2> "  + "`n" +`
    "<h2>Memory - (Hard Page Faults) Page Input/sec</h2> "  + "`n" + `
    "<h2>Memory - (Soft Page Faults) Page Faults/sec - Pages Input/sec </h2> "  + "`n" `
     + 'PageFaults: {0}' -f $vals[0].CookedValue + "`n" + 'HardPageFaults: {0}' -f $vals[1].CookedValue + "`n" + 'SoftPageFaults: {0}' -f $counterinfo)
    $output = ('status {0}.PFA {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
 

    $outputtext = ((get-date -format G) + "`n" +
    "<h2>Memory - Page Output/sec</h2> "  + "`n" +`
    "<h2>Memory - Page Reads/sec</h2> "  + "`n" +`
    "<h2>Memory - Page Writes/sec</h2> "  + "`n" +`
     'PageOutput: {0}' -f $vals[2].CookedValue + "`n" +`
     'PageReads: {0}' -f $vals[3].CookedValue +"`n" +`
     'PageWrites: {0}' -f $vals[4].CookedValue)
    $output = ('status {0}.PO {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }


    $counterinfo = $vals[5].CookedValue/(1024*1024)
    $poolPagedMbytes = $vals[6].CookedValue/(1024*1024)
    $outputtext = ((get-date -format G) + "`n" + `
    "<h2>Memory - Pool nonpaged Mbytes</h2> "  + "`n" + `
    "<h2>Memory - Pool paged Mbytes</h2> "  + "`n" +`
    'PoolNonpagedMbytes: {0}' -f $counterinfo + "`n" +`
    'PoolPagedMbytes: {0}' -f $poolPagedMbytes
    )
    $output = ('status {0}.PP {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }


    $counterinfo = $vals[7].CookedValue/(1024*1024)
    $percentInUse = $vals[8].CookedValue
    $MemInUse = $counterinfo * $percentInUse / 100
    $availMem = $vals[11].CookedValue
    $outputtext = ((get-date -format G) + "`n" + `
    "<h2>Memory - Committed Mbytes</h2> "  + "`n" + `
    "<h2>Memory - % Committed bytes in use</h2> "  + "`n" + `
    "<h2>Memory - Available Mbytes</h2> "  + "`n" +
    'CommittedMbytes: {0}' -f $counterinfo + "`n" + `
    'CommittedBytesInUse: {0}' -f $MemInUse + "`n" + `
    'AvailableMbytes: {0}' -f $availMem + "`n" + `
    'PercentCommittedBytesInUse - {0}' -f $percentInUse)
    $output = ('status {0}.CB {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
   
  

    
    $counterinfo = $vals[9].CookedValue
    $outputtext = ((get-date -format G) + "`n" + "<h2>System - Processor Queue Length</h2> "  + "`n" + 'ProcessorQueueLength: {0}' -f $counterinfo)
    $output = ('status {0}.PQL {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }

    $counterinfo = $vals[10].CookedValue
    $PageFileSize = (gwmi Win32_PageFileUsage).AllocatedBaseSize
    $PageFileSizeUsage = $PageFileSize * $counterinfo/100
    $outputtext = ((get-date -format G) + "`n" +`
    "<h2>Paging file\usage MB</h2> "  + "`n" + `
    "<h2>Paging file size MB</h2> "  + "`n" + `
    "<h2>Paging file\% usage</h2> "  + "`n" + `
    'PagingFileUsage: {0}' -f $PageFileSizeUsage  + "`n" + `
    'PagingFileSize: {0}' -f $PageFileSize + "`n" + `
    'PagingPercentageFileSize - {0}' -f $counterinfo )
    $output = ('status {0}.PF {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }
