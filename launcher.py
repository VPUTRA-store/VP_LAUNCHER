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

GITHUB_USER = "VPUTRA-store"
REPO_NAME = "VP_LAUNCHER"
LICENSE_URL = f"https://raw.githubusercontent.com/{GITHUB_USER}/{REPO_NAME}/main/licenses.json"
KEY_FILE = os.path.expanduser("~/.vp_license_key")

def clear_screen():
    os.system('clear' if os.name == 'posix' else 'cls')

def verify_license():
    saved_key = ""
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE, "r") as f:
            saved_key = f.read().strip()

    if not saved_key:
        print("\n[!] Lisensi belum terdaftar di perangkat ini.")
        saved_key = input("    Masukkan License Key > ").strip()

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
            time.sleep(1.5)
            return True
        else:
            if os.path.exists(KEY_FILE):
                os.remove(KEY_FILE)
            print("[X] License Key tidak valid atau sudah nonaktif!")
            return False
    except Exception as e:
        print(f"[X] Kesalahan jaringan: {e}")
        return False

def scan_roblox_packages():
    packages = []
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

def launch_all_packages(delay_time=12):
    clear_screen()
    print("=" * 45)
    print("         MEMINDAI & MELUNCURKAN GAME         ")
    print("=" * 45)
    packages = scan_roblox_packages()

    if not packages:
        print("\n[!] Tidak ada package com.roblox terdeteksi!")
        print("[!] Pastikan Roblox sudah terinstal & root aktif.")
        input("\nTekan Enter untuk kembali...")
        return

    print(f"[+] Ditemukan {len(packages)} client Roblox.")
    print(f"[i] Jeda antar client: {delay_time} detik.")
    print("=" * 45)
    
    for idx, pkg in enumerate(packages, start=1):
        print(f"[{idx}/{len(packages)}] Membuka: {pkg}")
        cmd = f"su -c 'monkey -p {pkg} -c android.intent.category.LAUNCHER 1'"
        os.system(cmd)

        if idx < len(packages):
            print(f"    └─ Menunggu {delay_time} detik...")
            time.sleep(delay_time)

    print("-" * 45)
    print("[OK] Selesai! Semua client berhasil diluncurkan.")
    print("=" * 45)
    input("\nTekan Enter untuk kembali ke menu...")

def reset_license():
    if os.path.exists(KEY_FILE):
        os.remove(KEY_FILE)
        print("\n[✔] Lisensi berhasil di-reset dari perangkat ini.")
    else:
        print("\n[!] Belum ada lisensi tersimpan.")
    input("\nTekan Enter untuk kembali...")

def main():
    clear_screen()
    if not verify_license():
        sys.exit(1)

    delay_sec = 12  # Default jeda timer aman

    while True:
        clear_screen()
        print("=" * 45)
        print("            VP LAUNCHER - PANEL              ")
        print("=" * 45)
        print(" [1] LAUNCH ALL ROBLOX (AUTO)")
        print(f" [2] ATUR TIMER JEDA ({delay_sec} Detik)")
        print(" [3] GANTI / RESET LICENSE KEY")
        print(" [4] KELUAR")
        print("=" * 45)
        
        choice = input("Pilih menu [1-4] > ").strip()
        
        if choice == '1':
            launch_all_packages(delay_sec)
        elif choice == '2':
            clear_screen()
            print("=" * 45)
            print("            PENGATURAN TIMER                 ")
            print("=" * 45)
            try:
                val = input("Masukkan waktu jeda dalam detik (Misal: 10 atau 15) > ").strip()
                if val.isdigit() and int(val) > 0:
                    delay_sec = int(val)
                    print(f"\n[✔] Timer jeda berhasil diubah jadi {delay_sec} detik!")
                else:
                    print("\n[!] Masukkan angka yang valid.")
            except Exception:
                print("\n[!] Terjadi kesalahan input.")
            input("\nTekan Enter untuk kembali...")
        elif choice == '3':
            reset_license()
        elif choice == '4':
            clear_screen()
            print("Keluar dari VP Launcher. Sampai jumpa!")
            break
        else:
            print("\n[!] Pilihan tidak valid.")
            input("Tekan Enter...")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[!] Dihentikan.")
        sys.exit(0)
        
