#!/bin/bash

# BANNER
echo "=============================="
echo "     🔍 BugBuster Scanner     "
echo "=============================="

# VARIABLES
read -p "Enter the target domain (e.g. example.com): " TARGET
OUTPUT_DIR="bugbuster_output"
mkdir -p "$OUTPUT_DIR"

# Color definitions
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

log() {
    echo -e "$1"
}

check_tool() {
    if ! command -v "$1" &> /dev/null; then
        log "${RED}[!] $1 is not installed. Skipping this step.${RESET}"
        return 1
    fi
    return 0
}

### 1. Subdomain Enumeration ###
log "${YELLOW}[*] Running Subfinder...${RESET}"
if check_tool subfinder; then
    subfinder -d "$TARGET" -silent -o "$OUTPUT_DIR/subdomains.txt"
fi

### 2. Live Host Checking ###
log "${YELLOW}[*] Checking for live hosts with httpx...${RESET}"
if check_tool httpx; then
    cat "$OUTPUT_DIR/subdomains.txt" | httpx -o "$OUTPUT_DIR/live.txt"
fi

# Exit if no live hosts
if [ ! -s "$OUTPUT_DIR/live.txt" ]; then
    log "${RED}[!] No live hosts found. Exiting.${RESET}"
    exit 1
fi

### 3. Nuclei Scan ###
log "${YELLOW}[*] Running nuclei scan...${RESET}"
if check_tool nuclei; then
    nuclei -l "$OUTPUT_DIR/live.txt" -silent -o "$OUTPUT_DIR/nuclei.txt"
fi

### 4. Wayback + Param Discovery ###
log "${YELLOW}[*] Fetching Wayback URLs...${RESET}"
if check_tool waybackurls; then
    waybackurls "$TARGET" | tee "$OUTPUT_DIR/wayback.txt"
fi

log "${YELLOW}[*] Gathering all params with gau...${RESET}"
if check_tool gau; then
    gau "$TARGET" | tee -a "$OUTPUT_DIR/wayback.txt" > "$OUTPUT_DIR/allurls.txt"
fi

### 5. XSS Detection ###
log "${YELLOW}[*] Detecting XSS...${RESET}"
if check_tool gf && check_tool dalfox; then
    cat "$OUTPUT_DIR/allurls.txt" | gf xss | dalfox pipe -o "$OUTPUT_DIR/xss.txt"
fi

### 6. SQLi Detection ###
log "${YELLOW}[*] Detecting SQLi...${RESET}"
if check_tool gf; then
    cat "$OUTPUT_DIR/allurls.txt" | gf sqli | tee "$OUTPUT_DIR/sqli.txt"
fi

### 7. Open Redirects ###
log "${YELLOW}[*] Checking for Open Redirects...${RESET}"
if check_tool gf; then
    cat "$OUTPUT_DIR/allurls.txt" | gf redirect | tee "$OUTPUT_DIR/open_redirects.txt"
fi

### 8. CSRF & Clickjacking ###
log "${YELLOW}[*] Checking for CSRF and Clickjacking...${RESET}"
python3 - <<EOF
import requests
try:
    r = requests.get('https://$TARGET', timeout=10, verify=False)
    if 'X-Frame-Options' not in r.headers:
        print('[!] Might be vulnerable to Clickjacking')
    if 'csrf' not in r.text.lower():
        print('[!] No CSRF tokens found in HTML forms')
except Exception as e:
    print(f'[!] Error: {e}')
EOF

### 9. CORS Misconfiguration ###
log "${YELLOW}[*] Scanning for CORS issues...${RESET}"
if [ -d "Corsy" ]; then
    python3 Corsy/corsy.py -i "$OUTPUT_DIR/live.txt" -o "$OUTPUT_DIR/cors.txt"
else
    log "${RED}[!] Corsy not found. Clone it from https://github.com/s0md3v/Corsy${RESET}"
fi

### 10. SSTI & LFI ###
log "${YELLOW}[*] Scanning for SSTI & LFI...${RESET}"
if check_tool gf; then
    cat "$OUTPUT_DIR/allurls.txt" | gf ssti > "$OUTPUT_DIR/ssti.txt"
    cat "$OUTPUT_DIR/allurls.txt" | gf lfi > "$OUTPUT_DIR/lfi.txt"
fi

### 11. SSRF Detection ###
log "${YELLOW}[*] Scanning for SSRF...${RESET}"
if check_tool gf; then
    cat "$OUTPUT_DIR/allurls.txt" | gf ssrf > "$OUTPUT_DIR/ssrf.txt"
fi

### 12. IDOR Detection ###
log "${YELLOW}[*] Scanning for IDOR...${RESET}"
if check_tool gf; then
    cat "$OUTPUT_DIR/allurls.txt" | gf idor > "$OUTPUT_DIR/idor.txt"
fi

### 13. GraphQL Testing ###
log "${YELLOW}[*] Checking for GraphQL endpoints...${RESET}"
cat "$OUTPUT_DIR/allurls.txt" | grep -i "graphql" > "$OUTPUT_DIR/graphql.txt"
if [ -s "$OUTPUT_DIR/graphql.txt" ]; then
    log "${GREEN}[+] GraphQL endpoints found! Manually test them with graphqlmap.py${RESET}"
fi

### 14. JWT Token Detection ###
log "${YELLOW}[*] Looking for JWT tokens...${RESET}"
cat "$OUTPUT_DIR/allurls.txt" | xargs -I % curl -s % 2>/dev/null | grep -oE 'eyJ[^\"]{10,}\.[^\"]{10,}\.[^\"]{10,}' | tee "$OUTPUT_DIR/jwt_tokens.txt"

### 15. Cache Deception ###
log "${YELLOW}[*] Testing for cache deception...${RESET}"
for url in $(cat "$OUTPUT_DIR/live.txt"); do
    curl -s -o /dev/null -w "%{http_code}" "$url/random.js"
done | tee "$OUTPUT_DIR/cache_deception.txt"

### 16. Host Header Injection ###
log "${YELLOW}[*] Testing for Host Header Injection...${RESET}"
for url in $(cat "$OUTPUT_DIR/live.txt"); do
    curl -s -H "Host: evil.com" "$url" | grep -i "evil.com" && echo "[+] Possible Host Header Injection on $url"
done | tee "$OUTPUT_DIR/host_header.txt"

### DONE ###
log "${GREEN}[✓] Scan complete. All results saved in '${OUTPUT_DIR}' folder.${RESET}"
