#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import time
import random

def get_roblox_packages():
    packages = []
    try:
        # Menggunakan os.popen untuk membaca langsung output su pm list packages
        stream = os.popen("su -c 'pm list packages'")
        output = stream.read()
        stream.close()
        
        for line in output.splitlines():
            clean_line = line.strip().lower()
            if "roblox" in clean_line:
                pkg = clean_line.replace("package:", "").strip()
                if pkg and pkg not in packages:
                    packages.append(pkg)
    except Exception:
        pass
        
    # Fallback jika su -c pakai tanda kutip tunggal gagal
    if not packages:
        try:
            stream = os.popen("su pm list packages")
            output = stream.read()
            stream.close()
            
            for line in output.splitlines():
                clean_line = line.strip().lower()
                if "roblox" in clean_line:
                    pkg = clean_line.replace("package:", "").strip()
                    if pkg and pkg not in packages:
                        packages.append(pkg)
        except Exception:
            pass

    return sorted(packages)

def launch_game(pkg_name):
    # Eksekusi buka aplikasi pakai monkey command via root
    cmd = f"su -c 'monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1'"
    os.system(cmd)

def main():
    # Tampilan bersih ala profesional
    print("=" * 50)
    print("           VP LAUNCHER - AUTO RUNNER            ")
    print("=" * 50)
    
    print("[*] Memindai client Roblox...")
    packages = get_roblox_packages()
    
    if not packages:
        print("\n[!] Gagal mendeteksi package Roblox.")
        print("[!] Pastikan game sudah terinstal & izin root aktif.")
        print("=" * 50)
        return

    print(f"[+] Ditemukan {len(packages)} client aktif.\n")
    print("-" * 50)
    
    for idx, pkg in enumerate(packages, start=1):
        print(f"[{idx}] Membuka: {pkg}")
        launch_game(pkg)
        
        # Jeda aman 10 - 15 detik antar client
        if idx < len(packages):
            delay = random.randint(10, 15)
            print(f"    └─ Menunggu {delay} detik ke client berikutnya...")
            time.sleep(delay)
            
    print("-" * 50)
    print("[✔] Semua client berhasil dijalankan otomatis!")
    print("=" * 50)

if __name__ == "__main__":
    main()
    
