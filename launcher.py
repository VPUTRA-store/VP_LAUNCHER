import os
import subprocess
import time
import random
import sys

def detect_roblox_packages():
    """Mendeteksi semua aplikasi Roblox (com.roblox) via akses root"""
    try:
        output = subprocess.check_output("su -c 'pm list packages'", shell=True, universal_newlines=True)
        packages = []
        for line in output.splitlines():
            # Filter mendeteksi package yang mengandung kata roblox atau com.roblox
            if "roblox" in line.lower() or "com.roblox" in line.lower():
                pkg = line.replace("package:", "").strip()
                if pkg not in packages:
                    packages.append(pkg)
        return sorted(packages)
    except Exception as e:
        print(f"[ERROR] Gagal mendeteksi package: {e}")
        return []

def launch_package(pkg_name):
    """
    Menjalankan aplikasi menggunakan perintah monkey.
    Aman untuk semua DPI karena memanggil sistem Android secara langsung 
    tanpa mengandalkan koordinat layar atau klik sentuh (touch).
    """
    cmd = f"su -c 'monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1'"
    os.system(cmd)

def main():
    print("=" * 45)
    print("   VP LAUNCHER - UNIVERSAL & AUTO-EXECUTE   ")
    print("=" * 45)
    
    packages = detect_roblox_packages()
    print(f"[INFO] Total client terdeteksi: {len(packages)}")
    
    if not packages:
        print("\n[ERROR] Tidak ada package Roblox (com.roblox) yang terdeteksi!")
        return

    print("\nPilih Mode Eksekusi:")
    print(" [1] Auto Launch Semua (Tanpa jeda ketik)")
    print(" [2] Auto Launch dengan Jeda Aman (10-15 detik)")
    print(" [0] Keluar")
    
    print("\n[INFO] Menunggu input (Jika keyboard macet, script otomatis jalan dalam 5 detik)...")
    
    # Mekanisme aman untuk semua keyboard & terminal: 
    # Jika dalam 5 detik tidak ada tombol yang ditekan, otomatis memilih mode 2 (Auto Launch aman)
    import select
    pilihan = "2" # Default aman jika keyboard error/macet total
    
    if os.name != 'nt': # Khusus lingkungan Linux/Termux Android
        i, o, e = select.select([sys.stdin], [], [], 5)
        if i:
            pilihan = sys.stdin.readline().strip()
    else:
        # Cadangan untuk Windows/Lokal
        try:
            pilihan = input("Masukkan pilihan [Default 2]: ").strip() or "2"
        except:
            pilihan = "2"

    if pilihan == "0":
        print("Keluar...")
        return

    print(f"\n[START] Menjalankan {len(packages)} client Roblox...")
    
    for i, pkg in enumerate(packages, 1):
        print(f"\n[LAUNCH {i}/{len(packages)}] Membuka: {pkg}")
        launch_package(pkg)
        
        # Jeda antar client (menggunakan jeda aman 10-15 detik sesuai permintaan)
        if i < len(packages):
            delay = random.randint(10, 15)
            print(f"[WAIT] Menunggu {delay} detik...")
            time.sleep(delay)
            
    print("\n[SUCCESS] Semua client berhasil dijalankan otomatis!")

if __name__ == "__main__":
    main()
    
