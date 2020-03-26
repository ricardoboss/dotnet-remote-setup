#!/bin/bash

# Install script to be run on remote device
echo "> [Remote] Setup script starting."

# get dotnet install script and run it
echo "> [Remote] Installing dotnet core runtime"
curl -sSL https://dotnetwebsite.azurewebsites.net/download/dotnet-core/scripts/v1/dotnet-install.sh | bash /dev/stdin --channel Current --runtime dotnet

# get vsdbg and store it in the current user's home directory
echo "> [Remote] Installing vsdbg (.NET Core Debugger for Linux)"
curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -u -r linux-arm -v latest -l ~/vsdbg

echo "> [Remote] Setup script finished."