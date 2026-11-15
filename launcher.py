import os
import subprocess
import time
import random

def detect_roblox_packages():
    """Mendeteksi semua aplikasi yang mengandung nama com.roblox / roblox via akses root"""
    try:
        output = subprocess.check_output("su -c 'pm list packages'", shell=True, universal_newlines=True)
        packages = []
        for line in output.splitlines():
            # Filter khusus mendeteksi package roblox
            if "roblox" in line.lower() or "com.roblox" in line.lower():
                pkg = line.replace("package:", "").strip()
                if pkg not in packages:
                    packages.append(pkg)
        return sorted(packages)
    except Exception as e:
        print(f"[ERROR] Gagal mendeteksi package: {e}")
        return []

def launch_package(pkg_name):
    """Menjalankan aplikasi menggunakan perintah monkey dengan akses root"""
    cmd = f"su -c 'monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1'"
    os.system(cmd)

if __name__ == "__main__":
    print("=" * 45)
    print("   VP LAUNCHER - UNLIMITED AUTO LAUNCH   ")
    print("=" * 45)
    
    # Deteksi semua package roblox tanpa batas (unlimited)
    packages = detect_roblox_packages()
    print(f"[INFO] Total client terdeteksi: {len(packages)}")
    
    if packages:
        for i, pkg in enumerate(packages, 1):
            print(f"\n[LAUNCH {i}/{len(packages)}] Membuka: {pkg}")
            launch_package(pkg)
            
            # Beri delay acak 10 - 15 detik antar client (kecuali client terakhir)
            if i < len(packages):
                delay = random.randint(10, 15)
                print(f"[WAIT] Menunggu {delay} detik sebelum client berikutnya...")
                time.sleep(delay)
                
        print("\n[SUCCESS] Semua client berhasil dijalankan secara otomatis!")
    else:
        print("\n[ERROR] Tidak ada package Roblox (com.roblox) yang terdeteksi di perangkat ini!")
        
