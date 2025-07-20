# Requires -Module Pester

# Import the script functions
. "$PSScriptRoot/Update-Ombi.ps1"

Describe 'Update-Ombi.ps1' {
    Context 'Parameter Defaults' {
        It 'Should default BackupMethod to sqlite' {
            $PSDefaultParameterValues['BackupMethod'] = $null
            param(
                [ValidateSet('sqlite', 'mysql')]
                [string]$BackupMethod = 'sqlite'
            )
            $BackupMethod | Should -Be 'sqlite'
        }
    }

    Context 'Backup-Sqlite' {
        BeforeAll {
            Mock -CommandName Copy-Item { $true }
            Mock -CommandName Test-Path { $true }
        }
        It 'Backs up all expected files if they exist' {
            Backup-Sqlite
            Assert-MockCalled -CommandName Copy-Item -Times 3
        }
    }

    Context 'Backup-MySql' {
        BeforeAll {
            Mock -CommandName Read-Host { 'test' }
            Mock -CommandName cmd.exe { $true }
            Mock -CommandName Test-Path { $true }
        }
        It 'Prompts for MySQL details and attempts backup for all databases' {
            Backup-MySql
            Assert-MockCalled -CommandName cmd.exe -Times 3
        }
    }

    Context 'Update-Ombi' {
        BeforeAll {
            Mock -CommandName Invoke-WebRequest { @{ Content = 'fake' } }
            Mock -CommandName Expand-Archive { $true }
            Mock -CommandName Remove-Item { $true }
            Mock -CommandName Remove-OldFiles { $true }
        }
        It 'Downloads and extracts the update' {
            $fakeRelease = @{ tag_name = 'v1.0.0'; assets = @(@{ name = 'Ombi-win-x64.zip'; browser_download_url = 'http://example.com/fake.zip' }) }
            Update-Ombi -SelectedRelease $fakeRelease -CurrentVersion 'v0.9.0'
            Assert-MockCalled -CommandName Invoke-WebRequest -Times 1
            Assert-MockCalled -CommandName Expand-Archive -Times 1
        }
    }

    Context 'Main Workflow' {
        BeforeAll {
            Mock -CommandName Check-Admin { $true }
            Mock -CommandName Prompt-EnvVars { $true }
            Mock -CommandName Ensure-BackupFolder { $true }
            Mock -CommandName Stop-OmbiService { $true }
            Mock -CommandName Backup-Sqlite { $true }
            Mock -CommandName Backup-MySql { $true }
            Mock -CommandName Update-Ombi { $true }
            Mock -CommandName Start-OmbiService { $true }
            Mock -CommandName Get-CurrentOmbiVersion { 'v0.9.0' }
            Mock -CommandName Get-Release { @{ tag_name = 'v1.0.0'; assets = @(@{ name = 'Ombi-win-x64.zip'; browser_download_url = 'http://example.com/fake.zip' }) } }
            Mock -CommandName Read-Host { 'y' }
        }
        It 'Runs the main workflow for sqlite' {
            $script:BackupMethod = 'sqlite'
            Main
            Assert-MockCalled -CommandName Backup-Sqlite -Times 1
            Assert-MockCalled -CommandName Update-Ombi -Times 1
        }
        It 'Runs the main workflow for mysql' {
            $script:BackupMethod = 'mysql'
            Main
            Assert-MockCalled -CommandName Backup-MySql -Times 1
            Assert-MockCalled -CommandName Update-Ombi -Times 1
        }
    }
} 