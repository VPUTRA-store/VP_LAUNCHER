#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import random
import string

LOCAL_DB = "licenses.json"

def load_db():
    if not os.path.exists(LOCAL_DB):
        return {}
    try:
        with open(LOCAL_DB, "r") as f:
            return json.load(f)
    except Exception:
        return {}

def save_db(data):
    with open(LOCAL_DB, "w") as f:
        json.dump(data, f, indent=2)

def generate_key(prefix="VP"):
    part1 = ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))
    part2 = ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))
    return f"{prefix}-{part1}-{part2}"

def create_key():
    print("\n" + "=" * 45)
    print("          BUAT LICENSE KEY BARU          ")
    print("=" * 45)
    owner = input("Nama Pembeli / Buyer : ").strip() or "Buyer"
    expires = input("Masa Aktif (YYYY-MM-DD) [Default 2099-12-31]: ").strip() or "2099-12-31"
    
    db = load_db()
    new_key = generate_key()
    
    db[new_key] = {
        "status": "active",
        "owner": owner,
        "expires": expires
    }
    
    save_db(db)
    print("\n" + "-" * 45)
    print(f"[✔] BERHASIL DI-BUAT!")
    print(f"    Key   : {new_key}")
    print(f"    Owner : {owner}")
    print(f"    Exp   : {expires}")
    print("-" * 45)
    print("[!] Jangan lupa sinkronkan file licenses.json ke GitHub!")
    input("\nTekan Enter untuk kembali ke menu...")

def delete_key():
    db = load_db()
    if not db:
        print("\n[!] Belum ada key terdaftar di database.")
        input("\nTekan Enter untuk kembali ke menu...")
        return

    print("\n" + "=" * 45)
    print("           HAPUS LICENSE KEY             ")
    print("=" * 45)
    keys = list(db.keys())
    for idx, k in enumerate(keys, start=1):
        owner = db[k].get("owner", "-")
        print(f"[{idx}] {k} (Owner: {owner})")
    
    choice = input("\nPilih nomor key yang ingin dihapus (0 untuk batal): ").strip()
    if choice.isdigit():
        idx = int(choice)
        if 1 <= idx <= len(keys):
            target_key = keys[idx - 1]
            del db[target_key]
            save_db(db)
            print(f"\n[✔] Key {target_key} berhasil dihapus!")
        else:
            print("\n[!] Pilihan tidak valid.")
    else:
        print("\n[!] Batal menghapus.")
    input("\nTekan Enter untuk kembali ke menu...")

def check_keys():
    db = load_db()
    print("\n" + "=" * 45)
    print("          DAFTAR KEY AKTIF (LOCAL)       ")
    print("=" * 45)
    if not db:
        print("[!] Belum ada key yang tersimpan.")
    else:
        for k, info in db.items():
            print(f"• Key   : {k}")
            print(f"  Owner : {info.get('owner')}")
            print(f"  Exp   : {info.get('expires')}")
            print(f"  Status: {info.get('status')}")
            print("-" * 45)
    input("\nTekan Enter untuk kembali ke menu...")

def main():
    # Sinkronisasi awal database lokal dengan file yang ada atau buat kosong
    if not os.path.exists(LOCAL_DB):
        save_db({})

    while True:
        os.system('clear' if os.name != 'nt' else 'cls')
        print("=" * 45)
        print("             VP ADMIN PANEL              ")
        print("=" * 45)
        print(" [1] CREATE NEW KEY")
        print(" [2] DELETE KEY")
        print(" [3] CHECK KEY AKTIF")
        print(" [4] KELUAR")
        print("=" * 45)
        
        choice = input("Pilih menu [1-4] > ").strip()
        
        if choice == '1':
            create_key()
        elif choice == '2':
            delete_key()
        elif choice == '3':
            check_keys()
        elif choice == '4':
            print("\nKeluar dari Admin Panel. Sampai jumpa, MBG!")
            break
        else:
            print("\n[!] Pilihan tidak valid, silakan pilih 1-4.")
            input("Tekan Enter untuk mencoba lagi...")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[!] Panel ditutup.")
        sys.exit(0)
            
