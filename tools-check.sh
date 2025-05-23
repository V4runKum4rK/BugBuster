#!/bin/bash
echo "[*] Checking for required tools..."

tools=(nmap sqlmap gf nuclei subfinder httpx jq ffuf dalfox gau waybackurls git curl corsy assetfinder amass qsreplace)

for tool in "${tools[@]}"; do
    if command -v $tool &>/dev/null; then
        echo "[✔] $tool is installed."
    else
        echo "[✘] $tool is NOT installed."
    fi
done
