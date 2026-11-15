#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import random
import select
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
    print("=" * 55)
    print("             VP LAUNCHER - PRO EDITION v4.0            ")
    print("        AUTOMATED MULTI-INSTANCE ROBLOX SYSTEM         ")
    print("=" * 55)

def verify_license():
    saved_key = ""
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE, "r") as f:
            saved_key = f.read().strip()

    if not saved_key:
        print("\n[!] Lisensi belum terdaftar di perangkat ini.")
        print("[?] Silakan masukkan License Key Anda lalu tekan Enter:")
        sys.stdout.write("    Key > ")
        sys.stdout.flush()
        saved_key = sys.stdin.readline().strip()

    if not saved_key:
        print("\n[✖] License Key tidak boleh kosong!")
        return False

    print("\n[*] Memverifikasi lisensi ke server...")
    try:
        resp = requests.get(f"{LICENSE_URL}?t={int(time.time())}", timeout=10)
        if resp.status_code != 200:
            print("[✖] Gagal terhubung ke server lisensi. Periksa koneksi internet.")
            return False

        licenses = resp.json()
        if saved_key in licenses and licenses[saved_key].get("status") == "active":
            with open(KEY_FILE, "w") as f:
                f.write(saved_key)
            owner = licenses[saved_key].get("owner", "Member")
            print(f"[✔] Lisensi Valid! Selamat datang, {owner}.")
            return True
        else:
            if os.path.exists(KEY_FILE):
                os.remove(KEY_FILE)
            print("[✖] License Key tidak valid atau sudah dinonaktifkan!")
            return False
    except Exception as e:
        print(f"[✖] Terjadi kesalahan jaringan saat verifikasi: {e}")
        return False

def scan_roblox_packages():
    packages = []
    # Metode 1: os.popen dengan su -c (paling stabil di Redfinger)
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
    # Independen DPI & resolusi menggunakan intent launcher sistem Android
    cmd = f"su -c 'monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1'"
    os.system(cmd)

def main():
    print_banner()
    if not verify_license():
        print("=" * 55)
        sys.exit(1)

    print("-" * 55)
    print("[*] Memindai seluruh client Roblox di perangkat...")
    packages = scan_roblox_packages()

    if not packages:
        print("\n[!] Tidak ada package com.roblox yang terdeteksi!")
        print("[!] Pastikan aplikasi game terinstal & izin root (su) aktif.")
        print("=" * 55)
        return

    print(f"[+] Terdeteksi {len(packages)} client Roblox (Unlimited Mode).")
    print("[i] Sistem akan otomatis berjalan dalam 3 detik...")
    time.sleep(3)
    print("-" * 55)

    for idx, pkg in enumerate(packages, start=1):
        print(f"[{idx}/{len(packages)}] Membuka: {pkg}")
        launch_package(pkg)

        if idx < len(packages):
            delay = random.randint(10, 15)
            print(f"      └─ Jeda aman {delay} detik sebelum client berikutnya...")
            time.sleep(delay)

    print("-" * 55)
    print("[✔] Seluruh client berhasil diluncurkan secara otomatis!")
    print("=" * 55)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[!] Dihentikan oleh pengguna.")
        sys.exit(0)
      
