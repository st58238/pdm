function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "================ Powershell Disk Manager ================"
    $admin = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
    if ( -Not $admin) {
        Write-Host
        Write-Host "This script should be ran as Administrator."
        Write-Host "Disk and partition manipulation will not work!"
        Write-Host
    }
}

function Read-Input {
    param([string]$Prompt = '(  menu  )')
    $cmd = Read-Host "$Prompt"
    return $cmd
}

function List-StorageDevices {
    $disksObject = @()
    Get-WmiObject Win32_Volume -Filter "DriveType='3'" | ForEach-Object {
    $VolObj = $_
    $ParObj = Get-Partition | Where-Object { $_.AccessPaths -contains $VolObj.DeviceID }
    if ( $ParObj ) {
        $disksobject += [pscustomobject][ordered]@{
            DiskID = $ParObj.DiskNumber
            PartitionNumber = $ParObj.PartitionNumber
            Letter = $VolObj.DriveLetter
            Label = $VolObj.Label
            FileSystem = $VolObj.FileSystem
            'Capacity(GB)' = ([Math]::Round(($VolObj.Capacity / 1GB),2))
            'FreeSpace(GB)' = ([Math]::Round(($VolObj.FreeSpace / 1GB),2))
            'Free(%)' = ([Math]::Round(((($VolObj.FreeSpace / 1GB)/($VolObj.Capacity / 1GB)) * 100),0))
            }
        }
    }
    $disksObject | Sort-Object DiskID | Format-Table -AutoSize | Out-Host
}

function Select-StorageDevice {
    List-StorageDevices
    $selectedDevice = Read-Host "Enter the Drive ID of the device you want to select (e.g., D:)"
    return $selectedDevice
}

function Erase-StorageDevice {
    param (
        [string]$DriveID
    )

    $confirm = Read-Host "Are you sure you want to wipe drive $($DriveID.Trim(':, ')):? (Y/N)"
    if ($confirm.ToLower() -eq "y") {
        Remove-Partition -DriveLetter $DriveID.Trim(':')
        Write-Host "Drive $DriveID has been wiped successfully."
    } else {
        Write-Host "Erase aborted."
    }
}

function Select-FreePartition {
    List-StorageDevices

    $selectedPartition = Read-Host "Enter the Drive Number of the partition you want to format (e.g., D:)"
    return $selectedPartition
}

function Select-FileSystem {
    $fileSystems = @("NTFS", "FAT32", "exFAT", "ReFS")
    Write-Host "Available File Systems:"
    Write-Host "------------------------"
    for ($i = 0; $i -lt $fileSystems.Length; $i++) {
        Write-Host "$($i + 1). $($fileSystems[$i])"
    }
    $choice = Read-Host "Enter the number corresponding to the desired file system"
    return $fileSystems[$choice - 1]
}

function Format-Partition {
    $selectedPartition = Select-FreePartition
    $fileSystem = Select-FileSystem
    $confirm = Read-Host "Are you sure you want to format partition $($selectedPartition) with $($fileSystem)? (Y/N)"
    if ($confirm.ToLower() -eq "y") {
        Format-Volume -DriveLetter $($selectedPartition.Trim(':, ')) -FileSystem $fileSystem
        Write-Host "Partition $selectedPartition has been formatted with $fileSystem."
    } else {
        Write-Host "Format aborted."
    }
}

function Select-PartitionToBackup {
    $freePartitions = Get-Partition | Where-Object { $_.SizeRemaining -gt 0 -or $_.SizeRemaining -eq $null }

    $disk = Get-CimInstance Win32_DiskDrive -Filter 'Index = 1'

    $partitions = $disk |Get-CimAssociatedInstance -ResultClassName Win32_DiskPartition

    $selectedPartition = Read-Host "Enter the Drive Number of the partition you want to format (e.g., D:)"
    return $selectedPartition
}

function Select-Destination {
    $dest = Read-Host "Select the folder/path to backup to"
    if ($dest.toLower() -eq "q") { return 0 }
    if ( -Not $(Test-Path -Path $dest)) {
        Write-Host "Path $($dest) is not valid"
        $dest = Select-Destination
    }
    $destInfo = Get-ChildItem $dest | Measure-Object

    if ($destInfo.count -ne 0) {
        Write-Host "Path $($dest) is not empty"
        $dest = Select-Destination
    }
    return $dest
}

function Backup-Partition {
    $partition = Select-PartitionToBackup
    $dest = Select-Destination
    if ($dest -eq 0) { Write-Host "Backup aborted"; return }
    $src = "$($partition.Trim(':, ')):/"
    if ($(Read-Host "Backup partition $($src) to $($dest)? (y/n)") -ne "y") { Write-Host "Backup aborted"; return }
    robocopy $src $dest /e /b /copy:DATSOU /dcopy:DATE /sj /xd "System Volume Information"
}

function List-PartitionUnallocated {
    $disksObject = [ordered]@{"DiskID  " = "AllocatableSpace"} # I hate myself now
    Get-WmiObject Win32_Volume -Filter "DriveType='3'" | ForEach-Object {
    $VolObj = $_
    $ParObj = Get-Partition | Where-Object { $_.AccessPaths -contains $VolObj.DeviceID }
    if ( $ParObj ) {
        $disksobject["$($ParObj.DiskNumber)"] = "$((Get-Disk -Number $ParObj.DiskNumber).LargestFreeExtent) B"
        }
    }
    return $disksObject
}

function Create-PartitionUnallocated {
    $disks = List-PartitionUnallocated
    $disks | Sort-Object DiskID | Format-Table -AutoSize -HideTableHeaders
    $disk = Read-Host "Select disk to create partition on"
    if ($(Get-Disk -Number $disk -ErrorAction "silentlycontinue").GetType() -eq [CimInstance]) {} else {
        Write-Host "Disk number $($disk) is not valid"
        Create-PartitionUnallocated
    }

    $fs = Select-FileSystem
    $size = Read-Host "Partition size to be created (in bytes (maximum $($disks[$disk])) or 'max')"
    if ($size.ToLower() -eq "max") {
        New-Partition -DiskNumber $disk -UseMaximumSize -AssignDriveLetter | Format-Volume -FileSystem $fs
    } elseif ($size -gt 0 -And $size -le $disks[$disk]) {
        New-Partition -DiskNumber $disk -Size $size -AssignDriveLetter | Format-Volume -FileSystem $fs
    } else { Write-Host "Creation aborted"; return }
}

function Help {
    $text=[ordered]@{
        "list" = "Lists all info about currently selected device and it's child objects";
        "backup" = "Backs up entirity of a partition to another folder"
        "create" = "Creates a new partition from free space on a specific drive"
        "erase" = "Erases entire partition";
        "format" = "Selects a partition and formats it";
        "help" = "Prints this menu";
        "exit" = "Exits this program, discarding all pending operations";
    }
    $text | Format-Table -HideTableHeaders
}

function Match {
    param([string]$Command)
    $c = $Command.ToLower()
    Switch($c) {
        "backup" { Backup-Partition }
        "format" { Format-Partition }
        "list" { List-StorageDevices }
        "create" { Create-PartitionUnallocated }
        "erase" { Erase-StorageDevice -DriveID (Select-StorageDevice) }
        "help" { Help }
        "exit" { Exit }
        default { Help }
    }
}

function Main {
    Show-Header
    while ($true) {
        $cmd = Read-Input
        Match -Command $cmd
    }
}

Main