#!/data/data/com.termux/files/usr/bin/bash
# =====================================================
#  VP LAUNCHER - sisi buyer
#  Jalan di Termux. Butuh: curl (pkg install curl -y)
# =====================================================

# ---------- PENGATURAN (diisi admin) ----------
# Ganti USERNAME_GITHUB dengan username GitHub kamu.
KEY_URL="https://raw.githubusercontent.com/VPUTRA-store/VP_LAUNCHER/main/keys.txt"
# ----------------------------------------------

WEBHOOK=""     # webhook Discord buyer (opsional)
PLACE_URL=""   # link map untuk fitur re join
PAKET=()       # daftar aplikasi Roblox yang terdeteksi
declare -A TIMER_MENIT   # timer per aplikasi (menit). 0 = tanpa timer
declare -A MULAI         # kapan aplikasi terakhir diluncurkan
declare -A SELESAI       # 1 = timernya sudah habis, jangan di-rejoin

# Perintah root. Redfinger harus sudah di-root untuk force-stop & cek proses.
if command -v su >/dev/null 2>&1; then
  SU="su -c"
else
  SU="sh -c"
fi

# su bisa mengacaukan pengaturan layar Termux (Enter tidak berfungsi,
# tulisan miring ke kanan). Dua fungsi ini mencegah dan memperbaikinya.
fix_tty() { stty sane 2>/dev/null; }
rt() {
  $SU "$1" </dev/null
  local r=$?
  fix_tty
  return $r
}

trap 'echo; echo "Dihentikan."; exit 0' INT

# ---------- Tampilan (menyesuaikan lebar layar / DPI) ----------
lebar() {
  local c
  c=$({ stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)
  if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 10 ]; then
    c="${COLUMNS:-40}"
  fi
  echo "$c"
}

# garis pemisah: panjangnya mengikuti lebar layar (maksimal 30)
garis() {
  local w
  w=$(lebar)
  [ "$w" -gt 31 ] && w=31
  printf '%*s\n' "$((w - 1))" '' | tr ' ' '-'
}

# tulisan panjang otomatis dipotong rapi sesuai lebar layar
tulis() {
  printf '%s\n' "$1" | fold -s -w "$(( $(lebar) - 1 ))"
}

header() {
  fix_tty
  clear
  garis
  echo "VP LAUNCHER"
  garis
  echo
}

tunggu_enter() {
  fix_tty
  echo
  read -r -p "Enter = kembali: " _
}

# ---------- Cek key ----------
cek_key() {
  header
  read -r -p "Masukkan key kamu: " KEY
  if [ -z "$KEY" ]; then
    echo "Key kosong."
    exit 1
  fi

  echo "Memeriksa key..."
  DAFTAR=$(curl -fsSL --max-time 20 "$KEY_URL?t=$(date +%s)") || {
    tulis "Gagal terhubung ke server key. Cek internet kamu."
    exit 1
  }

  HASH=$(printf '%s' "$KEY" | sha256sum | cut -d' ' -f1)
  BARIS=$(printf '%s\n' "$DAFTAR" | tr -d '\r' | grep -i "^$HASH|" | head -n1)

  if [ -z "$BARIS" ]; then
    echo "Key salah."
    exit 1
  fi

  EXP="${BARIS#*|}"
  HARI_INI=$(date +%F)
  if [[ "$HARI_INI" > "$EXP" ]]; then
    tulis "Key sudah kedaluwarsa (berlaku sampai $EXP)."
    exit 1
  fi

  echo "Key benar. Aktif sampai $EXP"
  sleep 2
}

# ---------- Webhook ----------
atur_webhook() {
  header
  tulis "Masukkan webhook Discord kamu *opsional"
  tulis "(kosongkan lalu Enter kalau tidak mau)"
  echo
  read -r -p "Webhook: " WEBHOOK
  if [ -n "$WEBHOOK" ] && [[ "$WEBHOOK" != https://discord.com/api/webhooks/* && "$WEBHOOK" != https://discordapp.com/api/webhooks/* ]]; then
    tulis "Format webhook tidak dikenali, webhook dimatikan."
    WEBHOOK=""
    sleep 2
  fi
}

kirim_webhook() {
  [ -z "$WEBHOOK" ] && return
  curl -s -m 15 -H "Content-Type: application/json" \
    -d "{\"content\":\"[VP LAUNCHER] $1\"}" "$WEBHOOK" >/dev/null 2>&1
}

# ---------- Roblox ----------
cari_roblox() {
  PAKET=()
  while IFS= read -r p; do
    [ -n "$p" ] && PAKET+=("$p")
  done < <(rt "pm list packages" 2>/dev/null | tr -d '\r' | grep -i '^package:com\.roblox' | cut -d: -f2 | sort)
  fix_tty
}

sedang_jalan() {
  local hasil
  hasil=$(rt "pidof $1" 2>/dev/null | tr -d '\r\n ')
  [ -n "$hasil" ]
}

buka() {
  local p="$1"
  if [ -n "$PLACE_URL" ]; then
    rt "am start -a android.intent.action.VIEW -d '$PLACE_URL' -p $p" >/dev/null 2>&1
  else
    rt "monkey -p $p -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
  fi
  MULAI[$p]=$(date +%s)
}

jeda_acak() {
  local d=$((RANDOM % 11 + 5))   # 5 sampai 15 detik
  echo "   jeda ${d} detik..."
  sleep "$d"
}

launch_semua() {
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
    return 1
  fi

  echo "Terdeteksi ${#PAKET[@]} Roblox:"
  for p in "${PAKET[@]}"; do echo " - $p"; done
  echo

  local i=0
  for p in "${PAKET[@]}"; do
    i=$((i + 1))
    echo "[$i/${#PAKET[@]}] Membuka $p"
    SELESAI[$p]=0
    buka "$p"
    if [ $i -lt ${#PAKET[@]} ]; then jeda_acak; fi
  done
  echo
  echo "Semua Roblox sudah dibuka."
  return 0
}

ada_timer() {
  for p in "${PAKET[@]}"; do
    if [ "${TIMER_MENIT[$p]:-0}" -gt 0 ]; then return 0; fi
  done
  return 1
}

# rejoin=1 : kalau Roblox mati, luncurkan lagi
# rejoin=0 : hanya mengurus timer
pantau() {
  local rejoin="$1"
  echo
  tulis "Memantau... (CTRL+C untuk berhenti)"
  while true; do
    local now
    now=$(date +%s)
    fix_tty

    for p in "${PAKET[@]}"; do
      [ "${SELESAI[$p]:-0}" = "1" ] && continue

      # --- cek timer ---
      local t="${TIMER_MENIT[$p]:-0}"
      if [ "$t" -gt 0 ] && [ $((now - ${MULAI[$p]:-$now})) -ge $((t * 60)) ]; then
        tulis "[$(date +%T)] Timer habis: $p -> ditutup"
        rt "am force-stop $p" >/dev/null 2>&1
        SELESAI[$p]=1
        kirim_webhook "Timer habis, $p ditutup."
        continue
      fi

      # --- cek rejoin ---
      if [ "$rejoin" = "1" ] && ! sedang_jalan "$p"; then
        # kasih waktu 60 detik setelah peluncuran sebelum dianggap mati
        if [ $((now - ${MULAI[$p]:-0})) -ge 60 ]; then
          tulis "[$(date +%T)] $p mati -> diluncurkan ulang"
          kirim_webhook "$p mati, diluncurkan ulang ke map terakhir."
          buka "$p"
          jeda_acak
        fi
      fi
    done

    # mode timer saja: berhenti kalau semua timer sudah selesai
    if [ "$rejoin" = "0" ]; then
      local sisa=0
      for p in "${PAKET[@]}"; do
        if [ "${TIMER_MENIT[$p]:-0}" -gt 0 ] && [ "${SELESAI[$p]:-0}" != "1" ]; then
          sisa=1
        fi
      done
      if [ $sisa -eq 0 ]; then
        echo "Semua timer selesai."
        break
      fi
    fi

    sleep 10
  done
}

# ---------- Menu ----------
tanya_map() {
  tulis "Masukkan Place ID atau link game/private server."
  tulis "Contoh: 920587237"
  tulis "atau link: https://www.roblox.com/games/920587237?privateServerLinkCode=12345"
  echo
  read -r -p "Place ID / link: " INPUT
  local place kode
  place=$(echo "$INPUT" | grep -oE '[0-9]{4,}' | head -n1)
  kode=$(echo "$INPUT" | grep -oE 'privateServerLinkCode=[0-9A-Za-z_-]+' | cut -d= -f2)

  if [ -z "$place" ]; then
    echo "Place ID tidak terbaca."
    return 1
  fi

  PLACE_URL="roblox://placeId=$place"
  if [ -n "$kode" ]; then
    PLACE_URL="roblox://placeId=$place&linkCode=$kode"
  fi
  return 0
}

menu_timer() {
  header
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
    tunggu_enter
    return
  fi

  tulis "TIMER (1 timer untuk 1 Roblox)"
  tulis "Isi menit. Isi 0 untuk tanpa timer. Enter = tidak diubah."
  echo
  for p in "${PAKET[@]}"; do
    echo "$p"
    read -r -p "  menit [${TIMER_MENIT[$p]:-0}]: " m
    [ -z "$m" ] && continue
    if [[ "$m" =~ ^[0-9]+$ ]]; then
      TIMER_MENIT[$p]=$m
    else
      echo "  bukan angka, dilewati"
    fi
  done
  echo
  tulis "Timer tersimpan. Timer mulai dihitung saat Roblox diluncurkan (menu 1 atau 2)."
  tunggu_enter
}

# ---------- Program utama ----------
cek_key
atur_webhook

while true; do
  header
  if [ -n "$WEBHOOK" ]; then echo "Webhook: aktif"; else echo "Webhook: tidak dipakai"; fi
  echo
  echo "1. AUTO LAUNCH"
  echo "2. AUTO LAUNCH + RE JOIN"
  echo "3. TIMER"
  echo "4. KELUAR"
  echo
  read -r -p "Pilih: " PILIH

  case "$PILIH" in
    1)
      header
      PLACE_URL=""
      if launch_semua; then
        if ada_timer; then pantau 0; fi
      fi
      tunggu_enter
      ;;
    2)
      header
      if tanya_map; then
        echo
        if launch_semua; then
          kirim_webhook "Auto launch + re join dimulai (${#PAKET[@]} Roblox)."
          pantau 1
        fi
      fi
      tunggu_enter
      ;;
    3) menu_timer ;;
    4)
      echo "Sampai jumpa!"
      exit 0
      ;;
    *)
      echo "Pilihan tidak ada."
      sleep 1
      ;;
  esac
done
