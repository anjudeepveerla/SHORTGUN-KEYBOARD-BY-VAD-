$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
python generate_sound.py
dotnet publish windows/ShotgunKeyboard.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o windows/bin/publish
New-Item -ItemType Directory -Force dist | Out-Null
Copy-Item windows/bin/publish/ShotgunKeyboard.exe dist/ShotgunKeyboard-Windows-x64.exe -Force
Write-Host "Built dist/ShotgunKeyboard-Windows-x64.exe"
