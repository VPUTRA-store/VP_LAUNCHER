#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import random
import string

def generate_key(prefix="VP"):
    part1 = ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))
    part2 = ''.join(random.choices(string.ascii_uppercase + string.digits, k=4))
    return f"{prefix}-{part1}-{part2}"

def main():
    print("=" * 50)
    print("        VP LAUNCHER - ADMIN KEY GENERATOR         ")
    print("=" * 50)
    
    owner = input("Nama Pembeli / Buyer : ").strip() or "Buyer"
    expires = input("Masa Aktif (YYYY-MM-DD) [Default 2099-12-31]: ").strip() or "2099-12-31"
    
    new_key = generate_key()
    
    entry = {
        new_key: {
            "status": "active",
            "owner": owner,
            "expires": expires
        }
    }
    
    print("\n" + "-" * 50)
    print(f"[✔] KEY BERHASIL DIBUAT: {new_key}")
    print("-" * 50)
    print("Salin blok JSON di bawah ini ke dalam file licenses.json di GitHub:\n")
    print(json.dumps(entry, indent=2))
    print("=" * 50)

if __name__ == "__main__":
    main()
  
