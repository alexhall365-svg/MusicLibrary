"""Prints the technical part of recent TestFlight crash reports.

Used by .github/workflows/testflight-crashes.yml. The repository is public, so
this prints only what's needed to diagnose a crash (build, device, OS, the
exception and the crashed thread's stack). It never prints tester names,
emails, comments or screenshots.
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

import jwt  # PyJWT

API = "https://api.appstoreconnect.apple.com"


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        os.environ["ASC_KEY_P8"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def get(path, params=None):
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"Authorization": "Bearer " + token()})
    try:
        with urllib.request.urlopen(request) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        print(f"API error {error.code} for {path}: {error.read().decode()[:300]}")
        raise


KEEP_HEADER = re.compile(
    r"^(Hardware Model|OS Version|Version|Code Type|Exception Type|Exception Codes|"
    r"Exception Subtype|Termination Reason|Termination Description|Triggered by Thread|"
    r"Crashed Thread|Application Specific Information|Last Exception Backtrace)\s*:?", re.I)


def summarise(text, max_frames=40):
    lines = text.splitlines()
    out = [line for line in lines if KEEP_HEADER.match(line.strip())]
    # Application Specific Information / assertion messages (next few lines).
    for i, line in enumerate(lines):
        if line.strip().startswith("Application Specific Information"):
            out += [l for l in lines[i + 1:i + 6] if l.strip()]
    # The crashed thread's stack.
    crashed = None
    for i, line in enumerate(lines):
        if re.match(r"^Thread \d+ Crashed", line):
            crashed = i
            break
    if crashed is not None:
        out.append("")
        for line in lines[crashed:crashed + max_frames + 1]:
            if not line.strip():
                break
            out.append(line)
    # Last Exception Backtrace (Swift/ObjC exceptions).
    for i, line in enumerate(lines):
        if line.startswith("Last Exception Backtrace"):
            out.append("")
            out += lines[i:i + max_frames]
            break
    return "\n".join(out) if out else "(couldn't find the crash details in this log)"


def main():
    bundle = os.environ["APP_BUNDLE_ID"]
    apps = get("/v1/apps", {"filter[bundleId]": bundle})["data"]
    if not apps:
        sys.exit(f"No app with bundle ID {bundle}")
    app_id = apps[0]["id"]
    count = int(os.environ.get("CRASH_COUNT", "5"))
    subs = get(f"/v1/apps/{app_id}/betaFeedbackCrashSubmissions",
               {"limit": count, "sort": "-createdDate"})["data"]
    if not subs:
        print("No TestFlight crash reports found. Crashes only appear here when a tester taps "
              "'Share' on TestFlight's crash prompt.")
        return
    for sub in subs:
        a = sub.get("attributes", {})
        print("=" * 70)
        print(f"Crash {sub['id'][:8]}  date={a.get('createdDate')}  "
              f"device={a.get('deviceModel')}  os={a.get('osVersion')}  "
              f"build={a.get('appBuildVersion') or a.get('buildBundleVersion') or ''}")
        try:
            log = get(f"/v1/betaFeedbackCrashSubmissions/{sub['id']}/crashLog")
            text = (log.get("data") or {}).get("attributes", {}).get("logText") or ""
        except Exception:
            text = ""
        print(summarise(text) if text else "(no crash log attached yet; Apple can take a while to process it)")
    print("=" * 70)


if __name__ == "__main__":
    main()
