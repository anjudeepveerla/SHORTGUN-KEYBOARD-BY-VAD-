#!/bin/sh
set -eu

cd "$(dirname "$0")"
python3 generate_sound.py

if [ -n "${DOTNET:-}" ]; then
    dotnet="$DOTNET"
elif [ -x ".tools/dotnet/dotnet" ]; then
    dotnet=".tools/dotnet/dotnet"
else
    dotnet="dotnet"
fi

mkdir -p dist
DOTNET_CLI_TELEMETRY_OPTOUT=1 "$dotnet" publish windows/ShotgunKeyboard.csproj \
    -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true \
    -o windows/bin/publish
cp windows/bin/publish/ShotgunKeyboard.exe dist/ShotgunKeyboard-Windows-x64.exe
echo "Built $(pwd)/dist/ShotgunKeyboard-Windows-x64.exe"
