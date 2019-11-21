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
        Write-Host "! Invalid PowerShell version: ${$PSVersionTable.PSVersion.Major}" -ForegroundColor DarkYellow

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
        Write-Error "Not all requirements are met. Cannot install toolchain."

        return
    }

    # in case any requirements where installed and a restart is needed, do it here
    if ($restartRequired) {
        Write-Host "! A restart is required before proceeding." -ForegroundColor DarkYellow

        Restart-Computer -Confirm

        return
    }

    Write-Host "> Setting up remote machine" -ForegroundColor DarkCyan

    if ("" -eq $Hostname) {
        $hostname = "raspberry.local"
        $prompt = Read-Host "< Remote hostname [$hostname]"
        if ($prompt -ne "") {
            $hostname = $prompt
        }
    }
    else {
        Write-Host "- Using $Hostname as hostname."

        $hostname = $Hostname
    }

    if ("" -eq $Username) {
        $username = "pi"
        $prompt = Read-Host "< Remote username [$username]"
        if ($prompt -ne "") {
            $username = $prompt
        }
    }
    else {
        Write-Host "- Using $Username as username."

        $username = $Username
    }

    # generate ssh keypair
    Write-Host "- Generating keypair..."
    mkdir @(Split-Path -Path $PrivateKey) -Force > $null
    ssh-keygen -q -t ed25519 -f $PrivateKey -N '""'
    "`r`n"

    # push public key to authorized_keys
    Write-Host "- Adding public key to authorized_keys on remote host."
    Write-Host "! You will be prompted by ssh to enter your password for the remote machine." -ForegroundColor DarkYellow
    Get-Content "$PrivateKey.pub" `
        | ssh -o StrictHostKeyChecking=no $username@$hostname "cat >> ~/.ssh/authorized_keys"
    "`r`n"

    # upload setup script
    Write-Host "- Uploading and executing setup script on remote."
    scp -o StrictHostKeyChecking=no -i $PrivateKey .\setup.sh $username@$hostname`:~
    "`r`n"
    ssh -o StrictHostKeyChecking=no -i $PrivateKey $username@$hostname "bash ~/setup.sh"
    "`r`n"

    # # install dotnet
    # Write-Host "> Installing .NET core runtime on remote machine" -ForegroundColor DarkCyan
    # ssh -o StrictHostKeyChecking=no -i "keys/remote_ed25519" $username@$hostname "curl -sSL https://dotnetwebsite.azurewebsites.net/download/dotnet-core/scripts/v1/dotnet-install.sh | bash /dev/stdin --channel Current --runtime dotnet"

    # # install vsdbg
    # Write-Host "> Installing vsdbg on remote machine" -ForegroundColor DarkCyan
    # ssh -o StrictHostKeyChecking=no -i "keys/remote_ed25519" $username@$hostname "curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -u -r linux-arm -v latest -l ~/vsdbg"

    # create template project
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