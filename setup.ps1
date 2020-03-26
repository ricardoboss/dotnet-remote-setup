# Setup script for Raspberry Pi <-> .NET Core toolchain
# =====================================================

# Requirements:
# - Windows 10 (1809+)
# - OpenSSH Client
# - PowerShell 6+

param(
    [switch] $SkipCheck,

    [string] $Hostname = $null,
    [string] $Username = $null,

    [ValidateNotNullOrEmpty()]
    [string] $PrivateKey = ".\keys\remote_ed25519"
)

$openSshClientName = "OpenSSH.Client~~~~0.0.1.0"
$restartRequired = $false;

# Installs OpenSSH.Client and restarts the computer if neccessary
function Install-OpenSSHClient {
    Write-Host "- Installing $openSshClientName"

    $result = Add-WindowsCapability -Online -Name $openSshClientName

    Write-Host "- Successfully installed $openSshClientName" -ForegroundColor Green

    if ($result.RestartNeeded -eq $true) {
        $script:restartRequired = $true;
    }
}

# Check if OpenSSH.Client is installed and prompts the user to install it if not
function Get-OpenSshClientInstalled {
    $openSshCapability = Get-WindowsCapability -Online | Where-Object Name -eq $openSshClientName;
    if ($openSshCapability.State -eq "Installed") {
        return $true
    }

    $confirmation = $Host.UI.PromptForChoice(
        "? Install OpenSSH Client",
        "OpenSSH Client not installed. Do you want to install it now?",
        @('&Yes'; '&No'),
        1
    )

    if ($confirmation -eq 0) {
        Install-OpenSSHClient

        return $true
    }
    else {
        return $false
    }
}

function Get-WindowsReleaseId {
    return (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").ReleaseId
}

# Checks every requirement and return true if all are met, false if not
function Get-RequirementsMet {
    if ($SkipCheck) {
        Write-Host "! Skipping requirements check" -ForegroundColor DarkYellow

        return $true
    }

    Write-Host "> Checking if all requirements are met." -ForegroundColor DarkCyan

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        Write-Host "- PowerShell version ok (6+)"
    }
    else {
        Write-Host "! Invalid PowerShell version: $($PSVersionTable.PSVersion.Major). Required: 6+" -ForegroundColor DarkYellow

        return $false
    }

    if (Get-WindowsReleaseId -ge 1809) {
        Write-Host "- Windows version ok (1809+)"
    }
    else {
        Write-Host "! Invalid Windows version: $(Get-WindowsReleaseId)" -ForegroundColor DarkYellow

        return $false
    }

    if (Get-OpenSshClientInstalled) {
        Write-Host "- OpenSSH.Client installed"
    }
    else {
        Write-Host "! OpenSSH.Client not installed" -ForegroundColor DarkYellow

        return $false
    }

    return $true
}

function Setup {
    Write-Host "Remote <-> .NET Core Debugging toolchain"
    Write-Host "========================================"

    # first, check if all requirements are met
    if ((Get-RequirementsMet) -eq $false) {
        Write-Error "Not all requirements are met. Cannot install toolchain." -Category InvalidResult

        return
    }

    # in case any requirements where installed and a restart is needed, do it here
    if ($restartRequired) {
        Write-Host "! A restart is required before proceeding." -ForegroundColor DarkYellow

        Restart-Computer -Confirm

        return
    }

    Write-Host "> Setting up remote login" -ForegroundColor DarkCyan

    if ("" -eq $Hostname) {
        $ssh_hostname = "raspberry.local"
        $prompt = Read-Host "< Remote hostname [$ssh_hostname]"
        if ($prompt -ne "") {
            $ssh_hostname = $prompt
        }
    }
    else {
        Write-Host "- Using $Hostname as hostname."

        $ssh_hostname = $Hostname
    }

    if ("" -eq $Username) {
        $ssh_username = "pi"
        $prompt = Read-Host "< Remote username [$ssh_username]"
        if ($prompt -ne "") {
            $ssh_username = $prompt
        }
    }
    else {
        Write-Host "- Using $Username as username."

        $ssh_username = $Username
    }

    # generate ssh keypair
    Write-Host "- Generating keypair..."
    mkdir @(Split-Path -Path $PrivateKey) -Force > $null
    ssh-keygen -q -t ed25519 -f $PrivateKey -N '""'

    # push public key to authorized_keys
    Write-Host "- Adding public key to authorized_keys on remote host."
    Write-Host "! You may be prompted by ssh to enter your password for the remote machine." -ForegroundColor DarkYellow
    Get-Content "$PrivateKey.pub" `
        | ssh -o StrictHostKeyChecking=no $ssh_username@$ssh_hostname "cat >> ~/.ssh/authorized_keys"

    Write-Host "> Setting up remote machine" -ForegroundColor DarkCyan

    # upload setup script
    Write-Host "- Uploading setup script on remote."
    scp -o StrictHostKeyChecking=no -i $PrivateKey .\setup.sh $ssh_username@$ssh_hostname`:~
    Write-Host "- Executing setup on remote."
    ssh -o StrictHostKeyChecking=no -i $PrivateKey $ssh_username@$ssh_hostname "bash ~/setup.sh"

    # TODO: create template project
    # modify project file to upload compiled files to raspberry after build:
    <# 
        <Target Name="PostBuild" AfterTargets="PostBuildEvent">
            <Exec Command="'C:\Windows\System32\OpenSSH\scp.exe' '$(OutDir)' <username>@<hostname>:~/$(ProjectName)/" />
        </Target>
    #>
    # modify project file to start debugging on raspberry after upload

    Write-Host "> Setup complete." -ForegroundColor Green

    return
}

# Setup entry point
Setup
