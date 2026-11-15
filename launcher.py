#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import random
import subprocess

try:
    import requests
except ImportError:
    os.system("pip install requests -q")
    import requests

# Konfigurasi Repository GitHub
GITHUB_USER = "VPUTRA-store"
REPO_NAME = "VP_LAUNCHER"
LICENSE_URL = f"https://raw.githubusercontent.com/{GITHUB_USER}/{REPO_NAME}/main/licenses.json"
KEY_FILE = os.path.expanduser("~/.vp_license_key")

def clear_screen():
    os.system('clear' if os.name != 'nt' else 'cls')

def print_banner():
    clear_screen()
    print("=" * 45)
    print("          VP LAUNCHER - PRO EDITION          ")
    print("     AUTOMATED MULTI-INSTANCE ROBLOX         ")
    print("=" * 45)

def verify_license():
    saved_key = ""
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE, "r") as f:
            saved_key = f.read().strip()

    if not saved_key:
        print("\n[!] Lisensi belum terdaftar di perangkat ini.")
        print("[?] Masukkan License Key lalu tekan Enter:")
        sys.stdout.write("    Key > ")
        sys.stdout.flush()
        saved_key = sys.stdin.readline().strip()

    if not saved_key:
        print("\n[X] License Key tidak boleh kosong!")
        return False

    print("\n[*] Memverifikasi lisensi ke server...")
    try:
        resp = requests.get(f"{LICENSE_URL}?t={int(time.time())}", timeout=10)
        if resp.status_code != 200:
            print("[X] Gagal terhubung ke server lisensi.")
            return False

        licenses = resp.json()
        if saved_key in licenses and licenses[saved_key].get("status") == "active":
            with open(KEY_FILE, "w") as f:
                f.write(saved_key)
            owner = licenses[saved_key].get("owner", "Member")
            print(f"[OK] Lisensi Valid! Selamat datang, {owner}.")
            return True
        else:
            if os.path.exists(KEY_FILE):
                os.remove(KEY_FILE)
            print("[X] License Key tidak valid atau nonaktif!")
            return False
    except Exception as e:
        print(f"[X] Kesalahan jaringan saat verifikasi: {e}")
        return False

def scan_roblox_packages():
    packages = []
    # Metode 1: os.popen dengan su -c
    try:
        stream = os.popen("su -c 'pm list packages'")
        output = stream.read()
        stream.close()
        for line in output.splitlines():
            clean = line.strip().lower()
            if "com.roblox" in clean or "roblox" in clean:
                pkg = clean.replace("package:", "").strip()
                if pkg and pkg not in packages:
                    packages.append(pkg)
    except Exception:
        pass

    # Metode 2: Fallback tanpa tanda kutip tunggal
    if not packages:
        try:
            stream = os.popen("su pm list packages")
            output = stream.read()
            stream.close()
            for line in output.splitlines():
                clean = line.strip().lower()
                if "com.roblox" in clean or "roblox" in clean:
                    pkg = clean.replace("package:", "").strip()
                    if pkg and pkg not in packages:
                        packages.append(pkg)
        except Exception:
            pass

    return sorted(packages)

def launch_package(pkg_name):
    cmd = f"su -c 'monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1'"
    os.system(cmd)

def main():
    print_banner()
    if not verify_license():
        print("=" * 45)
        sys.exit(1)

    print("-" * 45)
    print("[*] Memindai seluruh client Roblox...")
    packages = scan_roblox_packages()

    if not packages:
        print("\n[!] Tidak ada package com.roblox terdeteksi!")
        print("[!] Pastikan game terinstal & akses root aktif.")
        print("=" * 45)
        return

    print(f"[+] Terdeteksi {len(packages)} client (Unlimited).")
    print("[i] Sistem berjalan otomatis dalam 3 detik...")
    time.sleep(3)
    print("-" * 45)

    for idx, pkg in enumerate(packages, start=1):
        print(f"[{idx}/{len(packages)}] Membuka: {pkg}")
        launch_package(pkg)

        if idx < len(packages):
            delay = random.randint(10, 15)
            print(f"    -> Jeda aman {delay} detik...")
            time.sleep(delay)

    print("-" * 45)
    print("[OK] Semua client berhasil diluncurkan!")
    print("=" * 45)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[!] Dihentikan oleh pengguna.")
        sys.exit(0)
    
