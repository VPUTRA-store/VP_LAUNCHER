#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import random
import subprocess

def print_banner():
    print("=" * 60)
    print("         VP LAUNCHER - DEBUG INVESTIGATION V4      ")
    print("=" * 60)

def scan_roblox_packages():
    print("[*] Memulai investigasi sistem package...")
    found_packages = []
    
    # 1. Cek langsung pakai pm list packages tanpa su (apakah terbaca sebagai user biasa)
    try:
        print("[*] Mencoba scan standar: pm list packages")
        res = subprocess.run(["pm", "list packages"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, timeout=5)
        print(f"    [DEBUG] Return code: {res.returncode}")
        print(f"    [DEBUG] Stdout len: {len(res.stdout)} chars")
        if res.stderr:
            print(f"    [DEBUG] Stderr: {res.stderr.strip()}")
            
        for line in res.stdout.splitlines():
            if "roblox" in line.lower():
                pkg = line.replace("package:", "").strip()
                if pkg not in found_packages:
                    found_packages.append(pkg)
    except Exception as e:
        print(f"    [ERROR] Scan standar gagal: {e}")

    # 2. Jika masih kosong, coba cari via path su alternatif di Redfinger (/system/xbin/su atau /su/bin/su)
    if not found_packages:
        su_paths = ["/system/bin/su", "/system/xbin/su", "/su/bin/su", "su"]
        for su_bin in su_paths:
            try:
                print(f"[*] Mencoba akses root via binary: {su_bin}")
                res = subprocess.run([su_bin, "-c", "pm list packages"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, timeout=5)
                print(f"    [DEBUG] {su_bin} Return code: {res.returncode}")
                if res.stderr:
                    print(f"    [DEBUG] {su_bin} Stderr: {res.stderr.strip()}")
                    
                if res.returncode == 0 and res.stdout:
                    for line in res.stdout.splitlines():
                        if "roblox" in line.lower():
                            pkg = line.replace("package:", "").strip()
                            if pkg not in packages if 'packages' in locals() else pkg not in found_packages:
                                found_packages.append(pkg)
                    if found_packages:
                        print(f"[+] Sukses mendeteksi via {su_bin}!")
                        break
            except Exception as e:
                print(f"    [ERROR] Gagal dengan {su_bin}: {e}")

    return sorted(found_packages)

def main():
    print_banner()
    packages = scan_roblox_packages()
    
    print("-" * 60)
    if not packages:
        print("[!] HASIL: Masih 0 package terdeteksi.")
        print("[!] Silakan screenshot bagian teks [DEBUG] di atas dan kirim ke saya,")
        print("[!] agar kita tahu persis apakah diblokir root Redfinger atau path-nya beda!")
    else:
        print(f"[+] BERHASIL! Ditemukan {len(packages)} client:")
        for p in packages:
            print(f"    - {p}")
    print("=" * 60)

if __name__ == "__main__":
    main()
    
