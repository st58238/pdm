# https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy?redirectedfrom=MSDN
# robocopy <source> <dest> /e /b /copy:DATSOU /dcopy:DATE /sj /sparse

# FAT16,FAT32: 512B-256KB
# NTFS: 512B-2MB

$savePending = $false

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "================ Powershell Disk Manager ================"
}

function Read-Input {
    param([string]$Prompt = '(  menu  )')
    $cmd = Read-Host "$Prompt"
    return $cmd
}

function Exit-Check {
    if ($savePending -eq $true) {
        $confirm = Read-Input -Prompt "(  exit  ): There are pending changes to write to disk, confirm exit (y/n)"
        $confirm = $confirm.ToLower()
        if ($confirm -eq "y" -or $confirm -eq "yes") { Exit }
        elseif ($confirm -eq "n" -or $confirm -eq "no") { return }
        else { Exit-Check }

    } else { Exit }
}

function List-StorageDevices {
    $devices = Get-CimInstance win32_diskdrive | Get-CimAssociatedInstance -Association win32_diskdriveToDiskPartition 
    #$devices = Get-Volume
    Write-Host "Available Storage Devices:"
    Write-Host "--------------------------"
    write-host $devices
    foreach ($device in $devices) {
        $diskNumber = $($device.Name -Split ",")[0].Substring(6)
        $partitionNumber = $($device.Name -Split ",")[1].Substring(12)
        if ($partitionNumber -Eq 0) { continue; }
        Write-Host "$($device.DeviceID) - $($(Get-Partition -DiskNumber $diskNumber -PartitionNumber $partitionNumber -ErrorAction "silentlycontinue").DriveLetter) - $($device.Size / 1GB) GB"
    }
}

function Select-StorageDevice {
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
    $freePartitions = Get-Partition | Where-Object { $_.SizeRemaining -gt 0 -or $_.SizeRemaining -eq $null }
    Write-Host "Available Free Partitions:"
    Write-Host "--------------------------"

    $disk = Get-CimInstance Win32_DiskDrive -Filter 'Index = 1'

    $partitions = $disk |Get-CimAssociatedInstance -ResultClassName Win32_DiskPartition

    $allocated = $partitions |Measure-Object -Sum Size |Select-Object -Expand Sum

    $unallocated = $disk.Size - $allocated

    Write-Host ("There is {0}GB of disk space unallocated" -f $($unallocated/1GB))

    #New-Partition -DiskNumber 1 -Size 4096MB
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
    $confirm = Read-Host "Are you sure you want to format partition $selectedPartition with $fileSystem? (Y/N)"
    if ($confirm.ToLower() -eq "y") {
        Format-Volume -DriveLetter $selectedPartition -FileSystem $fileSystem
        Write-Host "Partition $selectedPartition has been formatted with $fileSystem."
    } else {
        Write-Host "Format aborted."
    }
}

function Help {
    $text=@{
        "format" = "Selects a free partition and formats it";
        "erase" = "Erases entire partition";
        "list" = "Lists all info about currently selected device and it's child objects";
        "help" = "Prints this menu";
        "exit" = "Exits this program, discarding all pending operations";
    }
    $text | Format-Table -HideTableHeaders
}

function Match {
    param([string]$Command)
    $c = $Command.ToLower()
    Switch($c) {
        "format" { Format-Partition }
        "list" { List-StorageDevices }
        "erase" { Erase-StorageDevice -DriveID (Select-StorageDevice) }
        "help" { Help }
        "exit" { Exit-Check }
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