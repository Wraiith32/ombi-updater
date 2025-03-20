# Define variables
$OmbiServiceName = "Ombi"
$OmbiFolderPath = "E:\Data\Ombi"  # Path to your Ombi installation
$BackupFolderPath = "E:\Data\Ombi-Backup"  # Path to store database backups
$GitHubRepo = "Ombi-app/Ombi"
$ReleaseType = "latest" # latest or prerelease

# Create backup folder if it doesn't exist
if (-not (Test-Path -Path $BackupFolderPath)) {
    New-Item -ItemType Directory -Path $BackupFolderPath
}

# Stop the Ombi service
Write-Host "Stopping Ombi service..."
Stop-Service -Name $OmbiServiceName -Force

# Get the release data from GitHub
Write-Host "Fetching release data from GitHub..."
$ReleaseApiUrl = "https://api.github.com/repos/$GitHubRepo/releases"
$Releases = Invoke-RestMethod -Uri $ReleaseApiUrl

# Determine which release to use based on ReleaseType
if ($ReleaseType -eq "latest") {
    # Use the first non-prerelease (latest stable release)
    $SelectedRelease = $Releases | Where-Object { $_.prerelease -eq $false } | Select-Object -First 1
} elseif ($ReleaseType -eq "prerelease") {
    # Use the first prerelease (latest pre-release)
    $SelectedRelease = $Releases | Where-Object { $_.prerelease -eq $true } | Select-Object -First 1
} else {
    Write-Host "Invalid ReleaseType. Use 'latest' or 'prerelease'." -ForegroundColor Red
    exit 1
}

# Check if a suitable release was found
if (-not $SelectedRelease) {
    Write-Host "Could not find a suitable release for ReleaseType '$ReleaseType'." -ForegroundColor Red
    exit 1
}

# Extract version number from the release tag
$VersionNumber = $SelectedRelease.tag_name
Write-Host "Selected $ReleaseType release version: $VersionNumber"

# Prompt for confirmation
$Confirmation = Read-Host "Do you want to proceed with downloading version $VersionNumber? (y/n)"
if ($Confirmation -ne "y") {
    Write-Host "Download aborted by user." -ForegroundColor Yellow
    # Restart the service before exiting
    Write-Host "Restarting Ombi service..."
    Start-Service -Name $OmbiServiceName
    exit 0
}

# Find the asset (win-x64.zip)
$Asset = $SelectedRelease.assets | Where-Object { $_.name -like "*win-x64.zip" }

if (-not $Asset) {
    Write-Host "Could not find a suitable release asset." -ForegroundColor Red
    exit 1
}

$DownloadUrl = $Asset.browser_download_url
$ZipFilePath = Join-Path -Path $env:TEMP -ChildPath "OmbiUpdate.zip"

# Download the latest release
Write-Host "Downloading latest release..."
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipFilePath

# Backup database files
Write-Host "Backing up database files..."
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

# Remove all files except the database files
Write-Host "Removing old files..."
Get-ChildItem -Path $OmbiFolderPath -Recurse | Where-Object {
    $_.Name -notin $DbFiles
} | Remove-Item -Force -Recurse

# Extract new files
Write-Host "Extracting new files..."
Expand-Archive -Path $ZipFilePath -DestinationPath $OmbiFolderPath -Force

# Clean up downloaded zip file
Remove-Item -Path $ZipFilePath -Force

# Restart the Ombi service
Write-Host "Restarting Ombi service..."
Start-Service -Name $OmbiServiceName

Write-Host "Ombi update completed successfully!"