import os
import sys
import time
import json
import subprocess
import requests
from datetime import datetime
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.prompt import Prompt

console = Console()

# GANTI BAGIAN INI DENGAN LINK RAW licenses.json MILIKMU
URL_LICENSES = "https://raw.githubusercontent.com/VPUTRA-store/VP_LAUNCHER/main/licenses.json"

def clear():
    os.system("clear")

def get_hwid():
    """Mengambil ID unik perangkat (Android ID) untuk kunci lisensi"""
    try:
        res = subprocess.check_output("settings get secure android_id", shell=True).decode().strip()
        return res if res else "UNKNOWN_DEVICE"
    except Exception:
        return "UNKNOWN_DEVICE"

def verify_license(user_key):
    """Mencocokkan key input buyer dengan database licenses.json"""
    try:
        response = requests.get(URL_LICENSES, timeout=10)
        if response.status_code != 200:
            return False, "Gagal terhubung ke server lisensi."
        
        db = response.json()
        if user_key not in db:
            return False, "Key tidak terdaftar!"

        data = db[user_key]
        if data.get("status") != "active":
            return False, "Lisensi nonaktif atau diblokir."

        # Cek masa berlaku
        exp = data.get("expired", "")
        if exp.lower() != "permanent":
            exp_date = datetime.strptime(exp, "%Y-%m-%d")
            if datetime.now() > exp_date:
                return False, f"Lisensi sudah kedaluwarsa pada {exp}."

        # Cek HWID perangkat
        current_hwid = get_hwid()
        saved_hwid = data.get("hwid", "")
        if saved_hwid and saved_hwid != current_hwid:
            return False, "Key ini sudah terikat di perangkat lain!"

        return True, data
    except Exception as e:
        return False, f"Terjadi kesalahan koneksi: {e}"

def detect_roblox_packages():
    """Mendeteksi otomatis paket roblox dan zetsu client"""
    try:
        output = subprocess.check_output("pm list packages", shell=True, universal_newlines=True)
        packages = []
        for line in output.splitlines():
            if "roblox" in line.lower() or "zetsu" in line.lower():
                pkg = line.replace("package:", "").strip()
                packages.append(pkg)
        return sorted(packages)
    except subprocess.CalledProcessError:
        return []

def launch_package(pkg_name):
    """Menjalankan aplikasi Roblox menggunakan perintah root/monkey"""
    cmd = f"su -c 'monkey -p {pkg_name} -c android.intent.category.LAUNCHER 1'"
    os.system(cmd + " > /dev/null 2>&1")

def is_package_running(pkg_name):
    """Mengecek apakah proses aplikasi masih berjalan"""
    try:
        output = subprocess.check_output(f"su -c 'pidof {pkg_name}'", shell=True).decode().strip()
        return len(output) > 0
    except subprocess.CalledProcessError:
        return False

def stop_all_packages(packages):
    """Menghentikan paksa semua instance Roblox"""
    for pkg in packages:
        os.system(f"su -c 'am force-stop {pkg}' > /dev/null 2>&1")
        console.print(f"[bold red][STOP][/bold red] Menghentikan {pkg}...")

def menu_utama(license_info):
    packages = detect_roblox_packages()
    max_inst = license_info.get("max_instances", 4)
    active_packages = packages[:max_inst]

    while True:
        clear()
        console.print(Panel.fit(
            "[bold cyan]VP LAUNCHER + TIMERS[/bold cyan]\n"
            f"[white]Paket Terdeteksi:[/white] [bold green]{len(packages)} Client[/bold green] "
            f"(Batas Lisensi: {max_inst} Client)",
            border_style="blue"
        ))

        if not active_packages:
            console.print("[bold red]Tidak ada aplikasi Roblox (com.roblox.clien*) yang terdeteksi![/bold red]")
            Prompt.ask("\nTekan Enter untuk muat ulang...")
            packages = detect_roblox_packages()
            active_packages = packages[:max_inst]
            continue

        table = Table(show_header=True, header_style="bold white")
        table.add_column("No", width=4)
        table.add_column("Package Name (Client)", style="cyan")
        table.add_column("Status", style="green")

        for idx, pkg in enumerate(active_packages, 1):
            status = "Aktif" if is_package_running(pkg) else "Standby"
            table.add_row(str(idx), pkg, status)

        console.print(table)
        console.print("\n[bold white]Pilih Mode Operasi:[/bold white]")
        console.print("[1] Auto Launch (Buka semua client berurutan)")
        console.print("[2] Auto Launch + Re-join (Pantau & buka ulang jika force close)")
        console.print("[3] Timers Stop (Jadwalkan mati otomatis semua client)")
        console.print("[4] Force Stop Semua Sekarang")
        console.print("[0] Keluar")

        pilihan = Prompt.ask("\nMasukkan pilihan", choices=["0", "1", "2", "3", "4"])

        if pilihan == "1":
            delay = int(Prompt.ask("Delay antar launch (detik)", default="3"))
            for pkg in active_packages:
                console.print(f"[bold green][LAUNCH][/bold green] Membuka {pkg}...")
                launch_package(pkg)
                time.sleep(delay)
            Prompt.ask("\nSemua client telah dijalankan. Tekan Enter untuk kembali...")

        elif pilihan == "2":
            delay = int(Prompt.ask("Delay antar launch (detik)", default="4"))
            interval = int(Prompt.ask("Interval pengecekan crash/re-join (detik)", default="15"))
            console.print("\n[bold yellow]Mode Auto Re-join aktif! Tekan CTRL+C untuk berhenti.[/bold yellow]\n")
            try:
                while True:
                    for pkg in active_packages:
                        if not is_package_running(pkg):
                            console.print(f"[bold yellow][RE-JOIN][/bold yellow] {pkg} tertutup, membuka ulang...")
                            launch_package(pkg)
                            time.sleep(delay)
                    time.sleep(interval)
            except KeyboardInterrupt:
                console.print("\n[bold red]Pemantauan Re-join dihentikan.[/bold red]")
                time.sleep(1)

        elif pilihan == "3":
            menit = int(Prompt.ask("Set timer berhenti otomatis dalam berapa menit?", default="60"))
            detik_total = menit * 60
            console.print(f"\n[bold cyan]Timer berjalan untuk {menit} menit. Tekan CTRL+C untuk membatalkan.[/bold cyan]")
            try:
                while detik_total > 0:
                    mins, secs = divmod(detik_total, 60)
                    sys.stdout.write(f"\rSisa waktu sebelum Stop Semua: {mins:02d}:{secs:02d} ")
                    sys.stdout.flush()
                    time.sleep(1)
                    detik_total -= 1
                print("\n")
                stop_all_packages(active_packages)
                Prompt.ask("\nTimer selesai. Tekan Enter untuk kembali...")
            except KeyboardInterrupt:
                console.print("\n[bold yellow]Timer dibatalkan.[/bold yellow]")
                time.sleep(1)

        elif pilihan == "4":
            stop_all_packages(active_packages)
            Prompt.ask("\nSemua client dihentikan. Tekan Enter untuk kembali...")

        elif pilihan == "0":
            sys.exit()

def main():
    clear()
    console.print(Panel.fit("[bold blue]VPUTRA STORE - AUTHENTICATION SYSTEM[/bold blue]", border_style="white"))
    console.print(f"[dim]Device HWID: {get_hwid()}[/dim]\n")

    user_key = Prompt.ask("[bold white]Masukkan License Key Anda[/bold white]").strip()
    console.print("[yellow]Memverifikasi lisensi...[/yellow]")

    valid, result = verify_license(user_key)
    if valid:
        console.print("[bold green]Verifikasi berhasil! Membuka menu utama...[/bold green]")
        time.sleep(1.5)
        menu_utama(result)
    else:
        console.print(f"[bold red]Akses Ditolak:[/bold red] {result}")
        sys.exit()

if __name__ == "__main__":
    main()
      
