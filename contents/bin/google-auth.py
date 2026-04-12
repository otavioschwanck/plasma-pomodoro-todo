#!/usr/bin/env python3
"""Google OAuth2 PKCE flow for pomodoro-todo.
Opens the browser, starts a local HTTP server to capture the callback,
exchanges the code for tokens, and prints JSON to stdout.
Usage: google-auth.py CLIENT_ID CLIENT_SECRET [PORT]
"""
import sys, os, secrets, hashlib, base64, json
import urllib.parse, urllib.request, http.server, threading, subprocess

client_id     = sys.argv[1] if len(sys.argv) > 1 else ""
client_secret = sys.argv[2] if len(sys.argv) > 2 else ""
port          = int(sys.argv[3]) if len(sys.argv) > 3 else 18642
redirect_uri  = f"http://localhost:{port}"

if not client_id or not client_secret:
    print(json.dumps({"error": "missing_credentials"}))
    sys.exit(1)

# PKCE
verifier  = secrets.token_urlsafe(64)
challenge = base64.urlsafe_b64encode(
    hashlib.sha256(verifier.encode()).digest()
).decode().rstrip("=")

auth_url = (
    "https://accounts.google.com/o/oauth2/v2/auth"
    f"?client_id={urllib.parse.quote(client_id)}"
    f"&redirect_uri={urllib.parse.quote(redirect_uri)}"
    "&response_type=code"
    "&scope=https%3A%2F%2Fwww.googleapis.com%2Fauth%2Ftasks"
    f"&code_challenge={urllib.parse.quote(challenge)}"
    "&code_challenge_method=S256"
    "&access_type=offline"
    "&prompt=consent"
)

code_holder = []

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        params = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        code   = params.get("code",  [""])[0]
        error  = params.get("error", [""])[0]
        if code:
            code_holder.append(code)
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        if code:
            self.wfile.write(b"<h2>Authorized! You can close this tab.</h2>")
        else:
            msg = error or "unknown error"
            self.wfile.write(f"<h2>Authorization failed: {msg}</h2>".encode())
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def log_message(self, *a):
        pass

server = http.server.HTTPServer(("localhost", port), Handler)

# Open browser
subprocess.Popen(
    ["xdg-open", auth_url],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL
)

server.serve_forever()

if not code_holder:
    print(json.dumps({"error": "no_code"}))
    sys.exit(1)

# Exchange code for tokens
data = urllib.parse.urlencode({
    "code":          code_holder[0],
    "client_id":     client_id,
    "client_secret": client_secret,
    "redirect_uri":  redirect_uri,
    "grant_type":    "authorization_code",
    "code_verifier": verifier,
}).encode()

try:
    req  = urllib.request.Request("https://oauth2.googleapis.com/token", data=data)
    with urllib.request.urlopen(req, timeout=15) as resp:
        print(resp.read().decode())
except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
