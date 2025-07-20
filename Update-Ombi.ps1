<#
.SYNOPSIS
    Updates Ombi and backs up its database(s).
.DESCRIPTION
    This script stops the Ombi service, backs up the database(s) (SQLite or MySQL), updates Ombi, and restarts the service.
.PARAMETER BackupMethod
    The method to use for backup: 'sqlite' or 'mysql'. Default is 'sqlite'.
.PARAMETER OmbiServiceName
    The name of the Ombi Windows service.
.PARAMETER OmbiFolderPath
    The path to the Ombi installation.
.PARAMETER BackupFolderPath
    The path to store database backups.
.PARAMETER GitHubRepo
    The GitHub repo for Ombi releases.
.PARAMETER ReleaseType
    The release type: 'latest' or 'prerelease'.
.EXAMPLE
    .\Update-Ombi.ps1 -BackupMethod mysql
#>

param(
    [ValidateSet("sqlite", "mysql")]
    [string]$BackupMethod = "sqlite",
    [string]$OmbiServiceName = "Ombi",
    [string]$OmbiFolderPath = "E:\Data\Ombi",
    [string]$BackupFolderPath = "E:\Data\Ombi-Backup",
    [string]$GitHubRepo = "Ombi-app/Ombi",
    [ValidateSet("latest", "prerelease")]
    [string]$ReleaseType = "latest"
)

# --- Function Definitions ---

function Check-Admin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "This script must be run as Administrator. Exiting." -ForegroundColor Red
        exit 1
    }
}

function Prompt-EnvVars {
    $global:OmbiApiUrl = [System.Environment]::GetEnvironmentVariable("OMBI_API_URL", "User")
    if (-not $global:OmbiApiUrl) {
        $global:OmbiApiUrl = Read-Host "Enter Ombi API URL (e.g., https://localhost:5000)"
        $global:OmbiApiUrl = $global:OmbiApiUrl + "/api/v1/Status/info"
        [System.Environment]::SetEnvironmentVariable("OMBI_API_URL", $global:OmbiApiUrl, "User")
    }
    $global:OmbiApiKey = [System.Environment]::GetEnvironmentVariable("OMBI_API_KEY", "User")
    if (-not $global:OmbiApiKey) {
        $global:OmbiApiKey = Read-Host "Enter Ombi API Key (Settings > Configuration > General > Api Key)"
        [System.Environment]::SetEnvironmentVariable("OMBI_API_KEY", $global:OmbiApiKey, "User")
    }
}

function Ensure-BackupFolder {
    if (-not (Test-Path -Path $BackupFolderPath)) {
        New-Item -ItemType Directory -Path $BackupFolderPath | Out-Null
    }
}

function Get-CurrentOmbiVersion {
    Write-Host "Checking current Ombi version via API..."
    try {
        $ApiHeaders = @{ "ApiKey" = $global:OmbiApiKey }
        $StatusResponse = Invoke-RestMethod -Uri $global:OmbiApiUrl -Headers $ApiHeaders -Method Get
        Write-Host "Current installed version: $StatusResponse"
        return $StatusResponse
    } catch {
        Write-Host "Failed to retrieve current version via API. Proceeding without it." -ForegroundColor Yellow
        return "Unknown"
    }
}

function Get-Release {
    Write-Host "Fetching release data from GitHub..."
    $ReleaseApiUrl = "https://api.github.com/repos/$GitHubRepo/releases"
    $Releases = Invoke-RestMethod -Uri $ReleaseApiUrl
    if ($ReleaseType -eq "latest") {
        return $Releases | Where-Object { $_.prerelease -eq $false } | Select-Object -First 1
    } elseif ($ReleaseType -eq "prerelease") {
        return $Releases | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1
    } else {
        Write-Host "Invalid ReleaseType. Use 'latest' or 'prerelease'." -ForegroundColor Red
        exit 1
    }
}

function Stop-OmbiService {
    Write-Host "Stopping Ombi service..."
    try {
        Stop-Service -Name $OmbiServiceName -Force
    } catch {
        Write-Host "Failed to stop Ombi service: $_" -ForegroundColor Yellow
    }
}

function Start-OmbiService {
    Write-Host "Restarting Ombi service..."
    try {
        Start-Service -Name $OmbiServiceName
    } catch {
        Write-Host "Failed to start Ombi service: $_" -ForegroundColor Red
    }
}

function Backup-Sqlite {
    Write-Host "Backing up SQLite database files..."
    $DbFiles = @("OmbiSettings.db", "OmbiExternal.db", "Ombi.db")
    foreach ($DbFile in $DbFiles) {
        $SourcePath = Join-Path -Path $OmbiFolderPath -ChildPath $DbFile
        if (Test-Path -Path $SourcePath) {
            Copy-Item -Path $SourcePath -Destination $BackupFolderPath -Force
            Write-Host "Backed up $DbFile"
        } else {
            Write-Host "$DbFile not found, skipping backup." -ForegroundColor Yellow
        }
    }
}

function Backup-MySql {
    Write-Host "Backing up MySQL databases..."
    $MySqlHost = Read-Host "Enter MySQL Host (e.g., localhost)"
    $MySqlUser = Read-Host "Enter MySQL Username"
    $MySqlPassword = Read-Host -AsSecureString "Enter MySQL Password"
    $MySqlPasswordPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($MySqlPassword))
    $TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $MySqlDatabases = @("ombi", "ombisettings", "ombiexternal")
    foreach ($MySqlDb in $MySqlDatabases) {
        $BackupFile = Join-Path -Path $BackupFolderPath -ChildPath ("Ombi-MySQL-Backup-$MySqlDb-$TimeStamp.sql")
        $DumpCommand = "mysqldump -h $MySqlHost -u $MySqlUser --password=$MySqlPasswordPlain $MySqlDb > `"$BackupFile`""
        Write-Host "Running: $DumpCommand"
        try {
            $cmdOutput = cmd.exe /c $DumpCommand
            if (Test-Path -Path $BackupFile) {
                Write-Host "MySQL backup for $MySqlDb completed: $BackupFile"
            } else {
                Write-Host "MySQL backup for $MySqlDb failed!" -ForegroundColor Red
            }
        } catch {
            Write-Host "mysqldump failed for $MySqlDb: $($_)" -ForegroundColor Red
        }
    }
}

function Remove-OldFiles {
    Write-Host "Removing old files (except database files)..."
    $DbFiles = @("OmbiSettings.db", "OmbiExternal.db", "Ombi.db")
    Get-ChildItem -Path $OmbiFolderPath -Recurse | Where-Object { $_.Name -notin $DbFiles } | Remove-Item -Force -Recurse
}

function Update-Ombi {
    $SelectedRelease = Get-Release
    if (-not $SelectedRelease) {
        Write-Host "Could not find a suitable release for ReleaseType '$ReleaseType'." -ForegroundColor Red
        exit 1
    }
    $VersionNumber = $SelectedRelease.tag_name
    Write-Host "Selected $ReleaseType release version: $VersionNumber"
    $CurrentVersion = Get-CurrentOmbiVersion
    $Confirmation = Read-Host "Current Version: $CurrentVersion. Update to version $VersionNumber (y/n)"
    if ($Confirmation -ne "y") {
        Write-Host "Download aborted by user." -ForegroundColor Yellow
        exit 0
    }
    # Download and extract
    $Asset = $SelectedRelease.assets | Where-Object { $_.name -like "*win-x64.zip" }
    if (-not $Asset) {
        Write-Host "Could not find a suitable release asset." -ForegroundColor Red
        exit 1
    }
    $DownloadUrl = $Asset.browser_download_url
    $ZipFilePath = Join-Path -Path $env:TEMP -ChildPath "OmbiUpdate.zip"
    Write-Host "Downloading latest release..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFilePath
    Remove-OldFiles
    Write-Host "Extracting new files..."
    Expand-Archive -Path $ZipFilePath -DestinationPath $OmbiFolderPath -Force
    Remove-Item -Path $ZipFilePath -Force
}

function Main {
    Check-Admin
    Prompt-EnvVars
    Ensure-BackupFolder
    Stop-OmbiService
    if ($BackupMethod -eq "sqlite") {
        Backup-Sqlite
    } elseif ($BackupMethod -eq "mysql") {
        Backup-MySql
    } else {
        Write-Host "Unknown backup method: $BackupMethod" -ForegroundColor Red
        exit 1
    }
    Update-Ombi
    Start-OmbiService
    Write-Host "Ombi update completed successfully!" -ForegroundColor Green
}

# --- Script Entry Point ---
Main