#### `install.sh`
```bash
#!/bin/bash
echo "[*] Installing required tools..."
sudo apt update

tools=(nmap sqlmap nuclei subfinder httpx jq ffuf dalfox gau waybackurls git curl)

for tool in "${tools[@]}"; do
    if ! command -v $tool &>/dev/null; then
        echo "[+] Installing $tool..."
        sudo apt install -y $tool || go install github.com/projectdiscovery/$tool@latest
    else
        echo "[-] $tool already installed."
    fi
done

echo "[*] Installation complete."
