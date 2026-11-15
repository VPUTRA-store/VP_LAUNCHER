#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VP LAUNCHER - ULTIMATE AUTO EXECUTE SYSTEM FOR REDFINGER
Author: VPutra Store
Description: Fully automated, robust Roblox multi-instance launcher.
"""

import os
import sys
import time
import random
import subprocess

def print_banner():
    print("=" * 60)
    print("                 VP LAUNCHER v3.0                  ")
    print("         ULTIMATE REDFINGER AUTO-LAUNCHER          ")
    print("=" * 60)

def check_root_access():
    print("[*] Memeriksa status akses root (su)...")
    try:
        result = subprocess.run(["su", "-c", "id"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, timeout=5)
        if result.returncode == 0:
            print("[+] Akses root (su) aktif dan terverifikasi!")
            return True
        else:
            print("[!] Peringatan: Perintah 'su' mengembalikan exit code non-zero.")
            return False
    except Exception as e:
        print(f"[!] Peringatan pengecekan root: {e}")
        return False

def scan_roblox_packages():
    print("[*] Memindai seluruh package aplikasi terinstal di sistem...")
    found_packages = []
    
    # Metode 1: Menggunakan su -c pm list packages (tanpa kutip bersarang yang bikin error)
    try:
        process = subprocess.run(
            ["su", "-c", "pm list packages"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=10
        )
        if process.returncode == 0 and process.stdout:
            for line in process.stdout.splitlines():
                clean_line = line.strip().lower()
                if "roblox" in clean_line:
                    pkg_name = clean_line.replace("package:", "").strip()
                    if pkg_name and pkg_name not in found_packages:
                        found_packages.append(pkg_name)
    except Exception as err:
        print(f"    └─ [Debug] Metode 1 gagal: {err}")

    # Metode 2: Fallback tanpa su jika metode 1 kosong
    if not found_packages:
        print("[*] Mencoba metode alternatif pemindaian package...")
        try:
            process = subprocess.run(
                ["pm", "list packages"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                timeout=10
            )
            if process.returncode == 0 and process.stdout:
                for line in process.stdout.splitlines():
                    clean_line = line.strip().lower()
                    if "roblox" in clean_line:
                        pkg_name = clean_line.replace("package:", "").strip()
                        if pkg_name and pkg_name not in found_packages:
                            found_packages.append(pkg_name)
        except Exception as err:
            print(f"    └─ [Debug] Metode 2 gagal: {err}")

    # Metode 3: Fallback menggunakan os.popen jika subprocess standar gagal
    if not found_packages:
        print("[*] Mencoba metode fallback sistem os.popen...")
        try:
            stream = os.popen("su -c pm list packages")
            output = stream.read()
            stream.close()
            for line in output.splitlines():
                clean_line = line.strip().lower()
                if "roblox" in clean_line:
                    pkg_name = clean_line.replace("package:", "").strip()
                    if pkg_name and pkg_name not in found_packages:
                        found_packages.append(pkg_name)
        except Exception as err:
            print(f"    └─ [Debug] Metode 3 gagal: {err}")

    return sorted(found_packages)

def execute_launch(package_name):
    print(f"[>] Menjalankan target: {package_name}")
    success = False
    
    # Daftar perintah eksekusi alternatif untuk memastikan game terbuka di berbagai versi Android Redfinger
    commands = [
        ["su", "-c", f"monkey -p {package_name} -c android.intent.category.LAUNCHER 1"],
        ["su", "-c", f"am start -n {package_name}/.MainActivity"],
        ["su", "-c", f"am start -p {package_name}"]
    ]
    
    for cmd in commands:
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
            if res.returncode == 0:
                success = True
                break
        except Exception:
            pass
            
    # Fallback terakhir menggunakan os.system murni
    if not success:
        try:
            os.system(f"su -c 'monkey -p {package_name} -c android.intent.category.LAUNCHER 1'")
            success = True
        except Exception:
            pass
            
    if success:
        print(f"    [✔] Perintah buka dikirim ke {package_name}")
    else:
        print(f"    [✖] Gagal mengeksekusi {package_name}")
    return success

def main_program():
    print_banner()
    check_root_access()
    
    print("-" * 60)
    packages = scan_roblox_packages()
    
    if not packages:
        print("\n[!] PERHATIAN KRITIS: Tidak ada package Roblox yang terdeteksi!")
        print("[!] Penyebab Umum:")
        print("    1. Aplikasi game Roblox belum terinstal di Cloud Phone.")
        print("    2. Izin Root (su) Termux belum di-Grant (izinkan) di jendela popup Redfinger.")
        print("    3. Layar perangkat perlu di-refresh ulang.")
        print("=" * 60)
        return

    print(f"\n[+] Total client Roblox terdeteksi: {len(packages)} (Tanpa Batas / Unlimited)")
    print("=" * 60)
    
    for index, pkg in enumerate(packages, start=1):
        print(f"\n[{index} dari {len(packages)}] Memproses...")
        execute_launch(pkg)
        
        # Jeda pengaman 10-15 detik antar client (kecuali client terakhir)
        if index < len(packages):
            delay = random.randint(10, 15)
            print(f"[i] Menunggu jeda pengaman selama {delay} detik...")
            time.sleep(delay)
            
    print("\n" + "=" * 60)
    print("   [✔] SEMUA CLIENT BERHASIL DIPROSES SECARA OTOMATIS!   ")
    print("=" * 60)

if __name__ == "__main__":
    try:
        main_program()
    except KeyboardInterrupt:
        print("\n[!] Program dihentikan secara manual.")
        sys.exit(0)
        
