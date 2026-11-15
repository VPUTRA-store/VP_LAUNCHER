import os
import subprocess
import time
import random

def detect_roblox_packages():
    """Mendeteksi semua aplikasi Roblox secara bersih dan aman"""
    packages = []
    try:
        # Perbaikan syntax agar tidak bentrok kutip di shell root
        cmd = "su -c pm list packages"
        output = subprocess.check_output(cmd, shell=True, universal_newlines=True)
        
        for line in output.splitlines():
            if "roblox" in line.lower():
                pkg = line.replace("package:", "").strip()
                if pkg not in packages:
                    packages.append(pkg)
    except Exception:
        # Fallback jika su butuh izin / dijalankan tanpa root
        try:
            output = subprocess.check_output("pm list packages", shell=True, universal_newlines=True)
            for line in output.splitlines():
                if "roblox" in line.lower():
                    pkg = line.replace("package:", "").strip()
                    if pkg not in packages:
                        packages.append(pkg)
        except:
            pass
            
    return sorted(packages)

def launch_package(pkg_name):
    """Menjalankan aplikasi secara langsung tanpa mengganggu tampilan"""
    cmd = f"su -c 'monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1'"
    os.system(cmd)

if __name__ == "__main__":
    # Tampilan Bersih & Rapi ala Profesional
    os.system('clear' if os.name == 'nt' else 'clear')
    print("=" * 48)
    print("       VP LAUNCHER - AUTO EXECUTE SYSTEM        ")
    print("=" * 48)
    
    print("[*] Memindai aplikasi Roblox di perangkat...")
    packages = detect_roblox_packages()
    
    if packages:
        print(f"[+] Berhasil mendeteksi {len(packages)} client aktif.\n")
        print("-" * 48)
        
        for i, pkg in enumerate(packages, 1):
            print(f"[{i}] Membuka: {pkg}")
            launch_package(pkg)
            
            if i < len(packages):
                delay = random.randint(10, 15)
                print(f"    └─ Menunggu {delay} detik ke client berikutnya...")
                time.sleep(delay)
                
        print("-" * 48)
        print("[✔] Semua client berhasil dijalankan dengan sempurna!")
        print("=" * 48)
    else:
        print("\n[!] Perhatian: Tidak ada aplikasi Roblox yang terdeteksi.")
        print("[!] Pastikan game sudah terinstal dan akses root aktif.")
        print("=" * 48)
        
