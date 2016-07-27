# This script will be executed from XymonPS client

# Last update: 27.07.2016
# Added by: jarekole@gmail.com
# initial version of script

 param (
    [string]$xymon_server = "xymon.statoilfuelretail.com"
 )

# Write-Output "Param $($xymon_server)"

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



$CtrsList = "\PhysicalDisk(*)\Avg. Disk sec/Read","\PhysicalDisk(*)\Avg. Disk sec/Write","\PhysicalDisk(*)\Disk Reads/sec","\PhysicalDisk(*)\Disk Writes/sec"
$Vals = Get-Counter -counter $CtrsList | Select-Object -ExpandProperty CounterSamples | Select-Object path,CookedValue 

$TextInfo = (Get-Culture).TextInfo


foreach ($val in $vals)
{
    #$Val.Path.Split("\")[3].Replace("physicaldisk","").Replace("(","").Replace(")","").Replace(" ","_")
    $va= $Val.Path.Split("\")[4].Replace(".","").Replace("/"," ")
    $counterinfo = $TextInfo.ToTitleCase($va).Replace(" ","") +"_"+ $Val.Path.Split("\")[3].Replace("physicaldisk","").Replace("(","").Replace(")","").Replace(" ","_").Replace(":","")
    $countervalue = $val.CookedValue

    $out = $out + "`n" + $counterinfo + ': {0}' -f $countervalue

}



  $outputtext = ((get-date -format G) + "`n" + "<h2>PhysicalDisk</h2> "  + "`n" + $out)
    $output = ('status {0}.disk2 {1} {2}' -f $XymonClientName, $alertColour, $outputtext)
    "Output string for Xymon: " + $output
    if ($XymonReady -eq 1) { XymonSend $output $xymon_server }



