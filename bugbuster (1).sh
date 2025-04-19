#!/bin/bash

# Author: Varun's Bug Bounty Toolkit
# Description: Comprehensive Bash Script for Automated Web Vulnerability Scanning

TARGET=$1
WORDLIST="/usr/share/seclists/Discovery/Web-Content/common.txt"
OUTPUT_DIR="bugbuster_output"
mkdir -p "$OUTPUT_DIR"

echo "[+] Starting Bug Bounty Recon on $TARGET"
echo "[+] Output saved to $OUTPUT_DIR"

### 1. Subdomain Enumeration ###
echo "[*] Running Subfinder..."
subfinder -d "$TARGET" -o "$OUTPUT_DIR/subdomains.txt"

### 2. Probing for Live Hosts ###
echo "[*] Probing for live hosts..."
cat "$OUTPUT_DIR/subdomains.txt" | httpx -silent -o "$OUTPUT_DIR/live.txt"

### 3. Wayback + GAU URLs Collection ###
echo "[*] Collecting Wayback + GAU URLs..."
waybackurls "$TARGET" > "$OUTPUT_DIR/wayback.txt"
gau "$TARGET" >> "$OUTPUT_DIR/gau.txt"
cat "$OUTPUT_DIR/"*.txt | sort -u > "$OUTPUT_DIR/allurls.txt"

### 4. XSS Detection ###
echo "[*] Scanning for XSS..."
cat "$OUTPUT_DIR/allurls.txt" | gf xss | dalfox pipe -o "$OUTPUT_DIR/xss.txt"

### 5. SQL Injection ###
echo "[*] Scanning for SQLi..."
cat "$OUTPUT_DIR/allurls.txt" | gf sqli | tee "$OUTPUT_DIR/sqli_urls.txt" | while read url; do
    sqlmap -u "$url" --batch --random-agent --level 2 --risk 1 >> "$OUTPUT_DIR/sqlmap.txt"
done

### 6. SSRF Detection ###
echo "[*] Scanning for SSRF..."
cat "$OUTPUT_DIR/allurls.txt" | gf ssrf | tee "$OUTPUT_DIR/ssrf.txt"

### 7. IDOR Testing ###
echo "[*] Searching for IDOR patterns..."
cat "$OUTPUT_DIR/allurls.txt" | gf idor | tee "$OUTPUT_DIR/idor.txt"

### 8. CSRF & Clickjacking ###
echo "[*] Checking for CSRF and Clickjacking..."
python3 -c "
import requests
r = requests.get('http://$TARGET')
if 'X-Frame-Options' not in r.headers:
    print('[!] Might be vulnerable to Clickjacking')
if 'csrf' not in r.text.lower():
    print('[!] No CSRF tokens found in HTML form')
" | tee "$OUTPUT_DIR/csrf_clickjack.txt"

### 9. CORS Misconfiguration ###
echo "[*] Scanning for CORS issues..."
corsy -u "http://$TARGET" -o "$OUTPUT_DIR/cors.txt"

### 10. XXE Detection ###
echo "[*] Searching for XML/XXE injection points..."
cat "$OUTPUT_DIR/allurls.txt" | gf xxe | tee "$OUTPUT_DIR/xxe.txt"

### 11. SSTI Detection ###
echo "[*] Scanning for SSTI..."
cat "$OUTPUT_DIR/allurls.txt" | gf ssti | tee "$OUTPUT_DIR/ssti.txt"

### 12. Web Cache Deception ###
echo "[*] Testing Web Cache Deception..."
for url in $(cat "$OUTPUT_DIR/live.txt"); do
    curl -s -I "$url"/random.css >> "$OUTPUT_DIR/cache_deception.txt"
done

### 13. Host Header Injection ###
echo "[*] Testing for Host Header attacks..."
for url in $(cat "$OUTPUT_DIR/live.txt"); do
    curl -s -H "Host: attacker.com" "$url" >> "$OUTPUT_DIR/host_header.txt"
done

### 14. GraphQL Enumeration ###
echo "[*] Checking for GraphQL endpoints..."
cat "$OUTPUT_DIR/allurls.txt" | grep -i "graphql" | tee "$OUTPUT_DIR/graphql_endpoints.txt"

echo "[*] Testing GraphQL with GraphQLmap..."
for gql_url in $(cat "$OUTPUT_DIR/graphql_endpoints.txt"); do
    python3 graphqlmap.py -u "$gql_url" --method POST --headers '{"Content-Type": "application/json"}' >> "$OUTPUT_DIR/graphql_scan.txt"
done

### 15. JWT Token Discovery and Analysis ###
echo "[*] Checking for JWT tokens in responses..."
cat "$OUTPUT_DIR/allurls.txt" | xargs -I % curl -s % | grep -oEi 'eyJ[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+\.[A-Za-z0-9-_]+' | tee "$OUTPUT_DIR/jwt_tokens.txt"

if [ -s "$OUTPUT_DIR/jwt_tokens.txt" ]; then
    echo "[*] Running JWT Tool on found tokens..."
    for token in $(cat "$OUTPUT_DIR/jwt_tokens.txt"); do
        jwt_tool "$token" -C -d >> "$OUTPUT_DIR/jwt_analysis.txt"
    done
fi

### 16. API Fuzzing with ffuf ###
echo "[*] Checking for API endpoints..."
cat "$OUTPUT_DIR/allurls.txt" | grep -Ei "/api/" | tee "$OUTPUT_DIR/api_endpoints.txt"

echo "[*] Fuzzing API with ffuf..."
for api in $(cat "$OUTPUT_DIR/api_endpoints.txt"); do
    ffuf -u "$api?FUZZ=test" -w "$WORDLIST" -mc all -of csv -o "$OUTPUT_DIR/api_ffuf.csv"
done

echo "[+] Scan complete! Check '$OUTPUT_DIR' for all results."
