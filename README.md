# Ombi Updater

This PowerShell script automates the process of updating [Ombi](https://github.com/Ombi-app/Ombi) and backing up its database(s). It supports both SQLite and MySQL backup methods, and is designed to be safe, interactive, and easy to use.

## Features
- Stops the Ombi Windows service
- Backs up Ombi databases (SQLite or MySQL)
- Downloads and installs the latest (or prerelease) Ombi release from GitHub
- Restarts the Ombi service
- Prompts for confirmation before making any changes

## Prerequisites
- Windows PowerShell (run as Administrator)
- [mysqldump](https://dev.mysql.com/doc/refman/8.0/en/mysqldump.html) in your PATH (for MySQL backups)
- Internet access (to fetch releases from GitHub)

## Usage

Open PowerShell **as Administrator** and run:

```powershell
# For default (SQLite) backup
powershell -File Update-Ombi.ps1

# For MySQL backup
powershell -File Update-Ombi.ps1 -BackupMethod mysql
```

### Parameters
| Name              | Description                                                      | Default                |
|-------------------|------------------------------------------------------------------|------------------------|
| BackupMethod      | Backup method: `sqlite` or `mysql`                               | sqlite                 |
| OmbiServiceName   | Name of the Ombi Windows service                                 | Ombi                   |
| OmbiFolderPath    | Path to your Ombi installation                                   | E:\Data\Ombi          |
| BackupFolderPath  | Path to store database backups                                   | E:\Data\Ombi-Backup   |
| GitHubRepo        | GitHub repo for Ombi releases                                    | Ombi-app/Ombi          |
| ReleaseType       | Release type: `latest` or `prerelease`                           | latest                 |

### MySQL Backup
If you select `mysql` as the backup method, you will be prompted for:
- MySQL Host
- MySQL Username
- MySQL Password

The script will back up the following databases (if they exist):
- `ombi`
- `ombisettings`
- `ombiexternal`

Each will be dumped to a separate file in the backup folder.

### Environment Variables
The script will prompt for Ombi API URL and API Key if not already set as environment variables (`OMBI_API_URL`, `OMBI_API_KEY`).

## Example
```powershell
# Update Ombi using MySQL backup, custom service and folder
powershell -File Update-Ombi.ps1 -BackupMethod mysql -OmbiServiceName "OmbiProd" -OmbiFolderPath "D:\Ombi" -BackupFolderPath "D:\Ombi-Backup"
```

## Testing
This repo includes a Pester test script (if present):
```powershell
Invoke-Pester .\Update-Ombi.Tests.ps1
```

## Notes
- Always run the script as Administrator.
- The script will prompt for confirmation before making any changes.
- For MySQL backup, ensure `mysqldump` is available in your system PATH.

## License
MIT
