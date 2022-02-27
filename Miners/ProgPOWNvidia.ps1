﻿using module ..\Modules\Include.psm1

param(
    [PSCustomObject]$Pools,
    [Bool]$InfoOnly
)

if (-not $IsWindows -and -not $IsLinux) {return}

$Port = "331{0:d2}"
$ManualURI = "https://github.com/BitcoinInterestOfficial/BitcoinInterest/releases"
$DevFee = 0.0
$Version = "0.16"

if ($IsLinux) {
    $UriCuda = @(
        [PSCustomObject]@{
            Path = ".\Bin\NVIDIA-ProgPOW\progpowminer_cuda10"
            Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v0.16-progpowminer/progpow_linux_0.16_final.7z"
            Cuda = "10.0"
        },
        [PSCustomObject]@{
            Path = ".\Bin\NVIDIA-ProgPOW\progpowminer_cuda9.2"
            Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v0.16-progpowminer/progpow_linux_0.16_final.7z"
            Cuda = "9.2"
        },
        [PSCustomObject]@{
            Path = ".\Bin\NVIDIA-ProgPOW\progpowminer_cuda9.1"
            Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v0.16-progpowminer/progpow_linux_0.16_final.7z"
            Cuda = "9.1"
        }
    )
} else {
    $UriCuda = @(
        [PSCustomObject]@{
            Path = ".\Bin\NVIDIA-ProgPOW\progpowminer-cuda.exe"
            Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v0.16-progpowminer/progpowminer-cuda10.0-windows-0.16_final.7z"
            Cuda = "10.0"
        },
        [PSCustomObject]@{
            Path = ".\Bin\NVIDIA-ProgPOW\progpowminer-cuda.exe"
            Uri = "https://github.com/RainbowMiner/miner-binaries/releases/download/v0.16-progpowminer/progpowminer-cuda9.2-windows-0.16_final.7z"
            Cuda = "9.2"
        }
    )
}

if (-not $Global:DeviceCache.DevicesByTypes.NVIDIA -and -not $InfoOnly) {return} # No NVIDIA present in system

$Commands = [PSCustomObject[]]@(
    [PSCustomObject]@{MainAlgorithm = "progpow"; Params = ""; ExtendInterval = 2; MinMemGB = 3} #ProgPOW
)

$Name = Get-Item $MyInvocation.MyCommand.Path | Select-Object -ExpandProperty BaseName

if ($InfoOnly) {
    [PSCustomObject]@{
        Type      = @("NVIDIA")
        Name      = $Name
        Path      = $UriCuda.Path | Select-Object -First 1
        Port      = $Miner_Port
        Uri       = $UriCuda.Uri
        DevFee    = $DevFee
        ManualUri = $ManualUri
        Commands  = $Commands
    }
    return
}

$Cuda = $null
for($i=0;$i -lt $UriCuda.Count -and -not $Cuda;$i++) {
    if (Confirm-Cuda -ActualVersion $Session.Config.CUDAVersion -RequiredVersion $UriCuda[$i].Cuda -Warning $(if ($i -lt $UriCuda.Count-1) {""}else{$Name})) {
        $Path = $UriCuda[$i].Path
        $Uri  = $UriCuda[$i].Uri
        $Cuda = $UriCuda[$i].Cuda
    }
}

if (-not $Cuda) {return}

$Global:DeviceCache.DevicesByTypes.NVIDIA | Select-Object Vendor, Model -Unique | ForEach-Object {
    $First = $true
    $Miner_Model = $_.Model
    $Device = $Global:DeviceCache.DevicesByTypes."$($_.Vendor)".Where({$_.Model -eq $Miner_Model})

    $Commands.ForEach({

        $Algorithm_Norm_0 = Get-Algorithm $_.MainAlgorithm

        $CoinSymbol = if ($Pools.$Algorithm_Norm_0.CoinSymbol) {$Pools.$Algorithm_Norm_0.CoinSymbol} else {"BCI"}

        $MinMemGB = Get-EthDAGSize -CoinSymbol $CoinSymbol -Algorithm $Algorithm_Norm_0 -Minimum $_.MinMemGb

        $Miner_Device = $Device | Where-Object {Test-VRAM $_ $MinMemGB}

		foreach($Algorithm_Norm in @($Algorithm_Norm_0,"$($Algorithm_Norm_0)-$($Miner_Model)","$($Algorithm_Norm_0)-GPU")) {
			if ($Pools.$Algorithm_Norm.Host -and $Miner_Device) {
                if ($First) {
                    $Miner_Port = $Port -f ($Miner_Device | Select-Object -First 1 -ExpandProperty Index)
                    $Miner_Name = (@($Name) + @($Miner_Device.Name | Sort-Object) | Select-Object) -join '-'
                    $DeviceIDsAll = $Miner_Device.Type_Vendor_Index -join ' '
                    $First = $false
                }

                $Miner_Protocol = Switch ($Pools.$Algorithm_Norm.EthMode) {
                    "stratum"          {"stratum+$(if ($Pools.$Algorithm_Norm.SSL) {"ssl"} else {"tcp"})"}
                    "ethproxy"         {"stratum1+$(if ($Pools.$Algorithm_Norm.SSL) {"ssl"} else {"tcp"})"}
					"ethstratumnh"     {"stratum2+$(if ($Pools.$Algorithm_Norm.SSL) {"ssl"} else {"tcp"})"}
					default            {"stratum$(if ($Pools.$Algorithm_Norm.SSL) {"s"})"}
				}

				$Pool_Port = if ($Pools.$Algorithm_Norm.Ports -ne $null -and $Pools.$Algorithm_Norm.Ports.GPU) {$Pools.$Algorithm_Norm.Ports.GPU} else {$Pools.$Algorithm_Norm.Port}
				[PSCustomObject]@{
					Name           = $Miner_Name
					DeviceName     = $Miner_Device.Name
					DeviceModel    = $Miner_Model
					Path           = $Path
					Arguments      = "--api-port -`$mport -P $($Miner_Protocol)://$(Get-UrlEncode $Pools.$Algorithm_Norm.User)$(if ($Pools.$Algorithm_Norm.Pass) {":$(Get-UrlEncode $Pools.$Algorithm_Norm.Pass)"})@$($Pools.$Algorithm_Norm.Host):$($Pools.$Algorithm_Norm.Port) --cuda --cuda-devices $($DeviceIDsAll) $($_.Params)"
					HashRates      = [PSCustomObject]@{$Algorithm_Norm = $Global:StatsCache."$($Miner_Name)_$($Algorithm_Norm_0)_HashRate".Week }
					API            = "Claymore"
					Port           = $Miner_Port
					Uri            = $Uri
					FaultTolerance = $_.FaultTolerance
					ExtendInterval = $_.ExtendInterval
                    Penalty        = 0
					DevFee         = $DevFee
					ManualUri      = $ManualUri
                    Version        = $Version
                    PowerDraw      = 0
                    BaseName       = $Name
                    BaseAlgorithm  = $Algorithm_Norm_0
                    Benchmarked    = $Global:StatsCache."$($Miner_Name)_$($Algorithm_Norm_0)_HashRate".Benchmarked
                    LogFile        = $Global:StatsCache."$($Miner_Name)_$($Algorithm_Norm_0)_HashRate".LogFile
				}
			}
		}
    })
}