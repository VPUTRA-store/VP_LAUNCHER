import os
import json
import requests
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.prompt import Prompt

console = Console()

# GANTI DENGAN LINK RAW licenses.json MILIKMU
URL_LICENSES = "https://raw.githubusercontent.com/VPUTRA-store/VP_LAUNCHER/main/licenses.json"

def clear():
    os.system("clear")

def load_licenses():
    try:
        res = requests.get(URL_LICENSES, timeout=10)
        if res.status_code == 200:
            return res.json()
    except Exception:
        pass
    return {}

def menu_admin():
    while True:
        clear()
        console.print(Panel.fit("[bold red]VPUTRA STORE - ADMIN PANEL[/bold red]", border_style="red"))
        
        db = load_licenses()
        
        table = Table(show_header=True, header_style="bold white")
        table.add_column("No", width=4)
        table.add_column("License Key", style="cyan")
        table.add_column("Status", style="green")
        table.add_column("Expired", style="yellow")
        table.add_column("Max Client", style="magenta")
        table.add_column("HWID Terikat", style="dim")

        keys = list(db.keys())
        for idx, k in enumerate(keys, 1):
            data = db[k]
            hwid_status = "Ada (Terkunci)" if data.get("hwid") else "Kosong (Belum dipakai)"
            table.add_row(str(idx), k, data.get("status"), str(data.get("expired")), str(data.get("max_instances")), hwid_status)

        console.print(table)
        console.print("\n[bold white]Menu Kontrol Admin:[/bold white]")
        console.print("[1] Tambah / Update Key Buyer")
        console.print("[2] Reset HWID Buyer (Ganti HP)")
        console.print("[3] Hapus Key Buyer")
        console.print("[0] Keluar")

        pilihan = Prompt.ask("\nPilih menu", choices=["0", "1", "2", "3"])

        if pilihan == "1":
            clear()
            console.print("[bold cyan]--- TAMBAH / UPDATE KEY ---[/bold cyan]")
            key_name = Prompt.ask("Masukkan License Key baru (contoh: buyer123)").strip()
            if not key_name:
                continue
            
            expired = Prompt.ask("Masa aktif (ketik 'permanent' atau format YYYY-MM-DD)", default="permanent")
            max_inst = int(Prompt.ask("Batas maksimal instance Roblox", default="4"))
            
            # Masukkan ke database lokal
            db[key_name] = {
                "status": "active",
                "expired": expired,
                "hwid": "",
                "max_instances": max_inst
            }
            
            console.print("\n[bold yellow]CATATAN PENTING:[/bold yellow]")
            console.print("Karena keamanan GitHub, file `licenses.json` harus diperbarui secara manual di browser GitHub atau via API Token.")
            console.print(f"Salin struktur JSON di bawah ini lalu tempel ke file `licenses.json` di GitHub:\n")
            console.print(json.dumps(db, indent=4))
            Prompt.ask("\nTekan Enter jika sudah menyalin & commit di GitHub...")

        elif pilihan == "2":
            clear()
            console.print("[bold yellow]--- RESET HWID BUYER ---[/bold yellow]")
            key_name = Prompt.ask("Masukkan Key buyer yang ingin di-reset HWID-nya").strip()
            if key_name in db:
                db[key_name]["hwid"] = ""
                console.print(f"\nHWID untuk key [cyan]{key_name}[/cyan] berhasil dikosongkan!")
                console.print(json.dumps(db, indent=4))
            else:
                console.print("[bold red]Key tidak ditemukan![/bold red]")
            Prompt.ask("\nTekan Enter untuk lanjut...")

        elif pilihan == "3":
            clear()
            console.print("[bold red]--- HAPUS KEY ---[/bold red]")
            key_name = Prompt.ask("Masukkan Key buyer yang ingin dihapus").strip()
            if key_name in db:
                del db[key_name]
                console.print(f"\nKey [cyan]{key_name}[/cyan] dihapus dari list!")
                console.print(json.dumps(db, indent=4))
            else:
                console.print("[bold red]Key tidak ditemukan![/bold red]")
            Prompt.ask("\nTekan Enter untuk lanjut...")

        elif pilihan == "0":
            break

if __name__ == "__main__":
    menu_admin()
          
