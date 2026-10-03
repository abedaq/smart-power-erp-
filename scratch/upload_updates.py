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

import base64
import requests

def encode_metadata(meta_dict):
    parts = []
    for k, v in meta_dict.items():
        encoded = base64.b64encode(v.encode('utf-8')).decode('utf-8')
        parts.append(f"{k} {encoded}")
    return ",".join(parts)

def upload_file_requests(filename, filepath, content_type="application/octet-stream"):
    file_size = os.path.getsize(filepath)
    print(f"[INFO] Initializing TUS resumable upload for {filename} ({file_size} bytes)...", flush=True)
    
    # 1. Delete existing object to avoid 409 Conflict in TUS
    del_url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}"
    del_headers = {
        "Authorization": f"Bearer {ANON_KEY}",
        "apikey": ANON_KEY,
        "Content-Type": "application/json", "Cache-Control": "max-age=0, no-cache, no-store, must-revalidate"
    }
    requests.delete(del_url, headers=del_headers, json={"prefixes": [filename]}, timeout=15)
    
    meta = {
        "bucketName": BUCKET,
        "objectName": filename,
        "contentType": content_type
    }
    
    init_headers = {
        "Authorization": f"Bearer {ANON_KEY}",
        "apikey": ANON_KEY,
        "Upload-Length": str(file_size),
        "Upload-Metadata": encode_metadata(meta),
        "Tus-Resumable": "1.0.0",
        "x-upsert": "true"
    }
    
    init_url = f"{SUPABASE_URL}/storage/v1/upload/resumable"
    resp = requests.post(init_url, headers=init_headers, timeout=30)
    
    if resp.status_code not in (200, 201):
        print(f"[ERROR] TUS init failed (HTTP {resp.status_code}): {resp.text}", flush=True)
        return False
        
    location = resp.headers.get("Location")
    if not location:
        print("[ERROR] No Location header in TUS init response", flush=True)
        return False
        
    if location.startswith("/"):
        upload_url = f"{SUPABASE_URL}{location}"
    else:
        upload_url = location
        
    print(f"[SUCCESS] TUS session created: {upload_url}", flush=True)
    
    chunk_size = 4 * 1024 * 1024  # 4 MB chunks
    offset = 0
    
    with open(filepath, "rb") as f:
        while offset < file_size:
            chunk = f.read(chunk_size)
            if not chunk:
                break
                
            patch_headers = {
                "Authorization": f"Bearer {ANON_KEY}",
                "apikey": ANON_KEY,
                "Upload-Offset": str(offset),
                "Content-Type": "application/offset+octet-stream",
                "Tus-Resumable": "1.0.0"
            }
            
            chunk_len = len(chunk)
            print(f"[INFO] Uploading chunk: {offset} to {offset + chunk_len} - {(offset/file_size)*100:.1f}%...")
            
            success = False
            for attempt in range(5):
                try:
                    patch_resp = requests.patch(upload_url, headers=patch_headers, data=chunk, timeout=120)
                    if patch_resp.status_code in (200, 204):
                        offset_header = patch_resp.headers.get("Upload-Offset")
                        if offset_header:
                            offset = int(offset_header)
                        else:
                            offset += chunk_len
                        success = True
                        break
                    else:
                        print(f"âš ï¸ Chunk warning (HTTP {patch_resp.status_code}): {patch_resp.text}")
                except Exception as ex:
                    print(f"âš ï¸ Chunk exception: {ex}, retrying ({attempt+1}/5)...")
            
            if not success:
                print(f"[ERROR] Failed to upload chunk at offset {offset}")
                return False
                
    print(f"ðŸŽ‰ [SUCCESS] File {filename} uploaded completely via TUS!")
    return True

def upload_json_requests(filename, data_dict):
    url = f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{filename}"
    headers = {
        "Authorization": f"Bearer {ANON_KEY}",
        "apikey": ANON_KEY,
        "x-upsert": "true",
        "Content-Type": "application/json", "Cache-Control": "max-age=0, no-cache, no-store, must-revalidate"
    }
    resp = requests.post(url, headers=headers, json=data_dict, timeout=30)
    if resp.status_code not in (200, 201):
        print(f"[ERROR] Upload JSON failed (HTTP {resp.status_code}): {resp.text}", flush=True)
        return False
    print(f"[SUCCESS] Uploaded {filename}: {resp.text}", flush=True)
    return True

def main():
    parser = argparse.ArgumentParser(description="Upload updates to Supabase Storage")
    parser.add_argument("--manifest-only", action="store_true", help="Upload only version.json manifest")
    parser.add_argument("--version", default="3.4.3.5", help="Target release version string")
    parser.add_argument("--changelog", default="âš¡ ØªØ­Ø¯ÙŠØ« Ø§Ù„ØªØ­ØµÙŠÙ† Ø§Ù„Ù…Ø¹Ù…Ø§Ø±ÙŠ v3.4.3.5: Ø¹Ø²Ù„ Ø³Ø¬Ù„Ø§Øª Ø§Ù„Ù…Ø­Ø±Ùƒ Ø¨Ø§Ù„ÙƒØ§Ù…Ù„ØŒ ØªØ³Ø±ÙŠØ¹ Ø§Ù„Ø¥Ù‚Ù„Ø§Ø¹ØŒ ÙˆØ­Ù…Ø§ÙŠØ© Ø§Ù„Ø§Ø³ØªØ¨Ø¯Ø§Ù„ Ø§Ù„Ø°Ø±ÙŠ ÙˆØªØ­Ø¯ÙŠØ«Ø§Øª Ø§Ù„ÙˆØ§Ø¬Ù‡Ø© Ø§Ù„ØªÙ„Ù‚Ø§Ø¦ÙŠØ©.", help="Changelog text")
    parser.add_argument("--target-license", default="", help="Comma-separated target license keys for canary/patch update")
    parser.add_argument("--target-hwid", default="", help="Comma-separated target HWIDs for canary/patch update")
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
        if not upload_file_requests("SmartPowerERP.exe", dist_exe, "application/octet-stream"):
            print("[ERROR] Failed to upload executable.")
            sys.exit(1)
        
    # 2. Prepare and Upload version.json
    target_licenses = [x.strip() for x in args.target_license.split(",") if x.strip()]
    target_hwids = [x.strip() for x in args.target_hwid.split(",") if x.strip()]

    manifest = {
        "version": args.version,
        "download_url": f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/SmartPowerERP.exe",
        "sha256": exe_sha256,
        "changelog": args.changelog,
        "mandatory": False,
        "release_date": "2026-09-11"
    }

    if target_licenses:
        manifest["target_licenses"] = target_licenses
        print(f"ðŸŽ¯ [CANARY] Targeted Release for Licenses: {target_licenses}")
    if target_hwids:
        manifest["target_hwids"] = target_hwids
        print(f"ðŸŽ¯ [CANARY] Targeted Release for HWIDs: {target_hwids}")
    
    print(f"[INFO] Uploading version.json (v{args.version})...")
    if not upload_json_requests("version.json", manifest):
        print("[ERROR] Failed to upload version.json.")
        sys.exit(1)
        
    print(f"\n[COMPLETE] Supabase Storage Release v{args.version} completed successfully!")

if __name__ == "__main__":
    main()

