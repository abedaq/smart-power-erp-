import argparse
import hashlib
import json
import os
import subprocess
import sys

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

SUPABASE_URL = "https://pkuoytiickgbtfeffmxq.supabase.co"
ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrdW95dGlpY2tnYnRmZWZmbXhxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0NDk0MjAsImV4cCI6MjEwNDAyNTQyMH0.9aGjAHdibP2uKiiTQ8XuGsYmwsZeWsA3hVQ9gD4xq7Q"
BUCKET = "updates"

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest().upper()

def upload_file_curl(filename, filepath, content_type="application/octet-stream"):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{filename}"
    cmd = [
        "curl.exe", "-X", "POST", url,
        "-H", f"Authorization: Bearer {ANON_KEY}",
        "-H", f"apikey: {ANON_KEY}",
        "-H", "x-upsert: true",
        "-H", f"Content-Type: {content_type}",
        "--data-binary", f"@{filepath}"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[ERROR] curl failed for {filename}: {res.stderr}")
        return False
    print(f"[SUCCESS] Uploaded {filename}: {res.stdout.strip()}")
    return True

def upload_json_curl(filename, data_dict):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{filename}"
    json_str = json.dumps(data_dict, ensure_ascii=False, indent=2)
    temp_json = os.path.join(os.path.dirname(__file__), "temp_version.json")
    with open(temp_json, "w", encoding="utf-8") as f:
        f.write(json_str)
        
    cmd = [
        "curl.exe", "-X", "POST", url,
        "-H", f"Authorization: Bearer {ANON_KEY}",
        "-H", f"apikey: {ANON_KEY}",
        "-H", "x-upsert: true",
        "-H", "Content-Type: application/json",
        "--data-binary", f"@{temp_json}"
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    try:
        os.remove(temp_json)
    except Exception:
        pass
        
    if res.returncode != 0:
        print(f"[ERROR] curl failed for {filename}: {res.stderr}")
        return False
    print(f"[SUCCESS] Uploaded {filename}: {res.stdout.strip()}")
    return True

def main():
    parser = argparse.ArgumentParser(description="Upload updates to Supabase Storage")
    parser.add_argument("--manifest-only", action="store_true", help="Upload only version.json manifest")
    args = parser.parse_args()

    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    dist_exe = os.path.join(root_dir, "dist_portable", "SmartPowerERP.exe")
    
    if not os.path.exists(dist_exe):
        print(f"[ERROR] Executable not found at {dist_exe}")
        sys.exit(1)
        
    exe_sha256 = compute_sha256(dist_exe)
    print(f"[INFO] Computed SHA256 for {dist_exe}: {exe_sha256}")
    
    # 1. Upload SmartPowerERP.exe if not manifest-only
    if not args.manifest_only:
        print(f"[INFO] Uploading SmartPowerERP.exe ({os.path.getsize(dist_exe)} bytes) to Supabase Storage bucket '{BUCKET}'...")
        if not upload_file_curl("SmartPowerERP.exe", dist_exe, "application/octet-stream"):
            print("[ERROR] Failed to upload executable.")
            sys.exit(1)
        
    # 2. Prepare and Upload version.json
    manifest = {
        "version": "1.0.7",
        "download_url": f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/SmartPowerERP.exe",
        "sha256": exe_sha256,
        "changelog": "🚀 إصدار السحاب v1.0.7: صندوق حوار التحديث الرشيق المطور وتثبيت تلقائي بضغطة زر واحدة.",
        "mandatory": False,
        "release_date": "2026-09-10"
    }
    
    print(f"[INFO] Uploading version.json (v1.0.7)...")
    if not upload_json_curl("version.json", manifest):
        print("[ERROR] Failed to upload version.json.")
        sys.exit(1)
        
    print("\n[COMPLETE] Supabase Storage Release v1.0.7 completed successfully!")

if __name__ == "__main__":
    main()
