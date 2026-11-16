#!/data/data/com.termux/files/usr/bin/bash
# =====================================================
#  VP LAUNCHER - sisi buyer (versi ringkas)
#  Jalan di Termux. Butuh: curl (pkg install curl -y)
# =====================================================

# ---------- PENGATURAN (diisi admin) ----------
KEY_URL="https://raw.githubusercontent.com/VPUTRA-store/VP_LAUNCHER/main/keys.txt"
# ----------------------------------------------

WEBHOOK=""       # webhook Discord buyer (opsional)
PLACE_URL=""     # link map tetap (opsional). Kosong = pakai map terakhir yang dimainkan
DELAY_DETIK=10   # jeda antar Roblox saat dibuka
GAP_DETIK="0.5"  # jeda keluar -> masuk lagi saat jadwal (0.3 - 1)
PAKET=()         # daftar aplikasi Roblox yang terdeteksi
declare -A MULAI         # kapan aplikasi terakhir diluncurkan
declare -A JADWAL_TIPE   # "" = tidak ada, interval, harian
declare -A JADWAL_NILAI  # interval: menit | harian: "06:00,12:00"
declare -A NEXT_RESTART  # waktu (epoch) keluar-masuk berikutnya
declare -A LAST_MAP      # map terakhir yang terdeteksi: roblox://placeId=...
STOP=0

# Perintah root. Redfinger harus sudah di-root.
if command -v su >/dev/null 2>&1; then
  SU="su -c"
else
  SU="sh -c"
fi

fix_tty() { stty sane 2>/dev/null; }
rt() {
  $SU "$1" </dev/null
  local r=$?
  fix_tty
  return $r
}

# CTRL+C hanya menghentikan pemantauan dan kembali ke menu.
trap 'STOP=1' INT

# ---------- Tampilan ----------
lebar() {
  local c
  c=$({ stty size </dev/tty; } 2>/dev/null | cut -d' ' -f2)
  if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 10 ]; then
    c="${COLUMNS:-40}"
  fi
  echo "$c"
}

garis() {
  local w
  w=$(lebar)
  [ "$w" -gt 31 ] && w=31
  printf '%*s\n' "$((w - 1))" '' | tr ' ' '-'
}

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

json_esc() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN { ORS = "\\n" } { print }'
}

kirim_webhook() {
  [ -z "$WEBHOOK" ] && return
  curl -s -m 15 -H "Content-Type: application/json; charset=utf-8" \
    -d "{\"content\":\"$(json_esc "$1")\"}" "$WEBHOOK" >/dev/null 2>&1
}

info_webhook() {
  kirim_webhook "🤖 [VP LAUNCHER] $1"
}

# pesan: Roblox force close lalu di-rejoin
pesan_fc() {
  local p="$1" map msg
  map="map terakhir"
  [ -z "$(map_untuk "$p")" ] && map="hanya membuka aplikasi (map belum terdeteksi)"
  IFS= read -r -d '' msg <<EOF
⚠️ ───────────────────────── ⚠️
       🚨 PERINGATAN 🚨
───────────────────────────────

Akun Roblox kamu mengalami FORCE CLOSE (FC) secara tiba-tiba!

📱 Roblox: \`$p\`
🕐 Waktu: $(date '+%d/%m/%Y %H:%M:%S')

🔄 Sistem membuka Roblox lagi ($map).

───────────────────────────────
🤖 Powered by VP LAUNCHER
EOF
  kirim_webhook "$msg"
}

# pesan: keluar-masuk sesuai jadwal
pesan_jadwal() {
  local p="$1" msg
  IFS= read -r -d '' msg <<EOF
🔁 ───────────────────────── 🔁
     ⏰ KELUAR-MASUK TERJADWAL ⏰
───────────────────────────────

📱 Roblox: \`$p\`
🕐 Waktu: $(date '+%d/%m/%Y %H:%M:%S')

Akun sudah keluar dari Roblox dan masuk lagi sesuai jadwal.

───────────────────────────────
🤖 Powered by VP LAUNCHER
EOF
  kirim_webhook "$msg"
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

# map yang dipakai untuk masuk lagi: link tetap kalau ada, kalau tidak map terakhir
map_untuk() {
  if [ -n "$PLACE_URL" ]; then
    echo "$PLACE_URL"
  else
    echo "${LAST_MAP[$1]:-}"
  fi
}

# susun perintah membuka Roblox (dengan / tanpa map)
perintah_buka() {
  local p="$1" url="$2"
  if [ -n "$url" ]; then
    echo "am start -a android.intent.action.VIEW -d '$url' -p $p"
  else
    echo "am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p $p"
  fi
}

buka() {
  local p="$1" url out
  url=$(map_untuk "$p")
  out=$(rt "$(perintah_buka "$p" "$url")" 2>&1)
  if [ -z "$url" ] && printf '%s' "$out" | grep -qi 'error'; then
    rt "monkey -p $p -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
  fi
  MULAI[$p]=$(date +%s)
}

jeda() {
  echo "   jeda ${DELAY_DETIK} detik..."
  sleep "$DELAY_DETIK"
}

# ---------- Deteksi map terakhir ----------
# Dibaca dari log Roblox yang sedang jalan (dan dari intent aktivitas).
# Hasil disimpan di LAST_MAP supaya bisa dipakai setelah Roblox mati.
deteksi_map() {
  local p="$1" pid dat place kode lg dplace
  pid=$(rt "pidof $p" 2>/dev/null | tr -d '\r' | awk '{print $1}')
  [ -z "$pid" ] && return 1

  lg=$(rt "logcat -d --pid=$pid" 2>/dev/null | tr -d '\r' \
    | grep -oiE 'place(id)?[ =:"]+[0-9]{6,}' | tail -n1)
  place=$(grep -oE '[0-9]{6,}' <<<"$lg" | head -n1)

  dat=$(rt "dumpsys activity activities" 2>/dev/null | tr -d '\r' | grep -F "$p/" \
    | grep -oiE 'placeId=[0-9]+(&linkCode=[0-9A-Za-z_-]+)?' | tail -n1)
  dplace=$(grep -oE 'placeId=[0-9]+' <<<"$dat" | grep -oE '[0-9]+')

  [ -z "$place" ] && place="$dplace"
  if [ -n "$place" ] && [ "$place" = "$dplace" ]; then
    kode=$(grep -oE 'linkCode=[0-9A-Za-z_-]+' <<<"$dat" | cut -d= -f2)
  fi

  if [ -n "$place" ] && [ "$place" != "0" ]; then
    LAST_MAP[$p]="roblox://placeId=$place"
    [ -n "$kode" ] && LAST_MAP[$p]="roblox://placeId=$place&linkCode=$kode"
    return 0
  fi
  return 1
}

# ---------- Keluar-masuk cepat ----------
# force-stop lalu langsung buka lagi, semuanya dalam SATU panggilan root
# supaya jedanya tepat (GAP_DETIK) dan tidak tertunda proses su.
restart_cepat() {
  local p="$1" url cmd out ms
  deteksi_map "$p"                 # catat map sebelum aplikasi ditutup
  url=$(map_untuk "$p")
  cmd="am force-stop $p; T1=\$(date +%s%N); sleep $GAP_DETIK; $(perintah_buka "$p" "$url") >/dev/null 2>&1; T2=\$(date +%s%N); echo GAP=\$(( (T2 - T1) / 1000000 ))"
  out=$(rt "$cmd" 2>/dev/null | tr -d '\r' | grep -oE 'GAP=[0-9]+' | tail -n1)
  MULAI[$p]=$(date +%s)
  ms="${out#GAP=}"
  if [[ "$ms" =~ ^[0-9]+$ ]]; then
    echo "   keluar -> masuk: ${ms} ms"
    if [ "$ms" -gt 1000 ]; then
      tulis "   Lebih dari 1 detik. Turunkan jeda di menu ATUR DELAY."
    fi
  fi
  if [ -z "$url" ]; then
    tulis "   Map belum terdeteksi, Roblox dibuka tanpa map."
  fi
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
    buka "$p"
    if [ $i -lt ${#PAKET[@]} ]; then jeda; fi
  done
  echo
  echo "Semua Roblox sudah dibuka."
  return 0
}

# ---------- Jadwal ----------
punya_jadwal() {
  [ -n "${JADWAL_TIPE[$1]:-}" ]
}

ada_jadwal() {
  local p
  for p in "${PAKET[@]}"; do
    if punya_jadwal "$p"; then return 0; fi
  done
  return 1
}

# waktu terdekat dari daftar jam "06:00,12:00"
next_harian() {
  local x e best=0 now
  now=$(date +%s)
  for x in ${1//,/ }; do
    e=$(date -d "today $x" +%s 2>/dev/null) || continue
    if [ "$e" -le "$now" ]; then
      e=$(date -d "tomorrow $x" +%s 2>/dev/null) || continue
    fi
    if [ "$best" -eq 0 ] || [ "$e" -lt "$best" ]; then best=$e; fi
  done
  echo "$best"
}

hitung_next() {
  local p="$1" now
  now=$(date +%s)
  case "${JADWAL_TIPE[$p]:-}" in
    interval) NEXT_RESTART[$p]=$((now + ${JADWAL_NILAI[$p]} * 60)) ;;
    harian) NEXT_RESTART[$p]=$(next_harian "${JADWAL_NILAI[$p]}") ;;
    *) NEXT_RESTART[$p]=0 ;;
  esac
}

format_durasi() {
  local m="$1" h j s out=""
  h=$((m / 1440)); j=$(((m % 1440) / 60)); s=$((m % 60))
  if [ "$h" -gt 0 ]; then out="$h hari "; fi
  if [ "$j" -gt 0 ]; then out="$out$j jam "; fi
  if [ "$s" -gt 0 ]; then out="$out$s menit"; fi
  echo "${out% }"
}

ket_jadwal() {
  local p="$1"
  case "${JADWAL_TIPE[$p]:-}" in
    interval) echo "tiap $(format_durasi "${JADWAL_NILAI[$p]}")" ;;
    harian) echo "harian ${JADWAL_NILAI[$p]}" ;;
    *) echo "tanpa jadwal" ;;
  esac
}

jadwal_interval() {
  local p="$1" m
  echo
  tulis "Roblox keluar lalu masuk lagi setiap berapa menit?"
  read -r -p "Menit (minimal 1): " m
  if ! [[ "$m" =~ ^[0-9]+$ ]] || [ "$((10#$m))" -lt 1 ]; then
    echo "Harus angka, minimal 1."
    sleep 2
    return 1
  fi
  JADWAL_TIPE[$p]="interval"
  JADWAL_NILAI[$p]=$((10#$m))
  echo "Jadwal: tiap $(format_durasi "${JADWAL_NILAI[$p]}")"
  sleep 1
}

jadwal_harian() {
  local p="$1" jm x ok=1
  echo
  tulis "Isi jam keluar-masuk (format 24 jam, ikut jam Redfinger)."
  tulis "Boleh lebih dari satu, pisah koma. Contoh: 06:00,12:00,18:30"
  read -r -p "Jam: " jm
  jm="${jm// /}"
  if [ -z "$jm" ]; then
    echo "Kosong, tidak diubah."
    sleep 1
    return 1
  fi
  for x in ${jm//,/ }; do
    [[ "$x" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || ok=0
  done
  if [ "$ok" -ne 1 ]; then
    echo "Format jam salah."
    sleep 2
    return 1
  fi
  JADWAL_TIPE[$p]="harian"
  JADWAL_NILAI[$p]="$jm"
  echo "Jadwal: harian $jm"
  sleep 1
}

hapus_jadwal() {
  JADWAL_TIPE[$1]=""
  JADWAL_NILAI[$1]=""
  NEXT_RESTART[$1]=0
}

atur_jadwal_satu() {
  local p="$1" pil jawab q
  header
  echo "$p"
  echo "Jadwal: $(ket_jadwal "$p")"
  echo
  echo "1. Setiap N menit (berulang)"
  echo "2. Jam harian (bisa banyak jam)"
  echo "3. Hapus jadwal"
  echo "0. Kembali"
  echo
  read -r -p "Pilih: " pil
  case "$pil" in
    1) jadwal_interval "$p" || return ;;
    2) jadwal_harian "$p" || return ;;
    3) hapus_jadwal "$p"; echo "Jadwal dihapus."; sleep 1; return ;;
    *) return ;;
  esac
  if [ ${#PAKET[@]} -gt 1 ]; then
    read -r -p "Samakan untuk semua Roblox? (y/n): " jawab
    if [[ "$jawab" =~ ^[yY]$ ]]; then
      for q in "${PAKET[@]}"; do
        JADWAL_TIPE[$q]="${JADWAL_TIPE[$p]}"
        JADWAL_NILAI[$q]="${JADWAL_NILAI[$p]}"
      done
      echo "Dipakai untuk semua Roblox."
      sleep 1
    fi
  fi
}

# ---------- Pemantauan ----------
# - jadwal tiba  -> keluar & masuk lagi (cepat)
# - Roblox mati  -> buka lagi, masuk ke map terakhir
pantau() {
  local now last=0 lastdet=0 p
  STOP=0
  now=$(date +%s)
  for p in "${PAKET[@]}"; do hitung_next "$p"; done

  echo
  tulis "Memantau... (CTRL+C untuk berhenti)"
  for p in "${PAKET[@]}"; do
    if punya_jadwal "$p"; then
      echo " $p: $(ket_jadwal "$p"), berikut $(date -d "@${NEXT_RESTART[$p]}" '+%d/%m %H:%M')"
    fi
  done

  while [ "$STOP" = "0" ]; do
    now=$(date +%s)
    fix_tty

    # --- jadwal keluar-masuk ---
    for p in "${PAKET[@]}"; do
      if punya_jadwal "$p" && [ "$now" -ge "${NEXT_RESTART[$p]:-0}" ]; then
        tulis "[$(date +%T)] Jadwal: $p keluar-masuk"
        restart_cepat "$p"
        hitung_next "$p"
        pesan_jadwal "$p"
        echo "   berikut: $(date -d "@${NEXT_RESTART[$p]}" '+%d/%m %H:%M')"
        if [ ${#PAKET[@]} -gt 1 ]; then jeda; fi
        now=$(date +%s)
      fi
    done

    # --- cek mati & catat map: tiap 10 detik ---
    if [ $((now - last)) -ge 10 ]; then
      last=$now
      for p in "${PAKET[@]}"; do
        if sedang_jalan "$p"; then
          if [ $((now - lastdet)) -ge 60 ]; then deteksi_map "$p"; fi
        elif [ $((now - ${MULAI[$p]:-0})) -ge 60 ]; then
          # beri waktu 60 detik setelah peluncuran sebelum dianggap mati
          tulis "[$(date +%T)] $p mati -> dibuka lagi"
          pesan_fc "$p"
          buka "$p"
          if [ ${#PAKET[@]} -gt 1 ]; then jeda; fi
        fi
      done
      if [ $((now - lastdet)) -ge 60 ]; then lastdet=$now; fi
    fi

    sleep 1
  done

  echo
  echo "Pemantauan dihentikan."
  fix_tty
}

# ---------- Map ----------
# Enter kosong = pakai map terakhir yang dimainkan (otomatis)
tanya_map() {
  tulis "Link map / Place ID (opsional)."
  tulis "Kosongkan (Enter) = Roblox masuk ke map terakhir yang dimainkan."
  tulis "Contoh: 920587237"
  echo
  read -r -p "Place ID / link: " INPUT
  PLACE_URL=""
  if [ -z "$INPUT" ]; then
    echo "Pakai map terakhir (dideteksi otomatis)."
    return 0
  fi
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

# ---------- Menu ----------
menu_jadwal() {
  header
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
    tunggu_enter
    return
  fi

  local pil i p
  while true; do
    header
    echo "JADWAL KELUAR-MASUK"
    echo "Jam Redfinger: $(date '+%d/%m %H:%M')"
    echo
    i=0
    for p in "${PAKET[@]}"; do
      i=$((i + 1))
      echo "$i. $p"
      echo "   $(ket_jadwal "$p")"
    done
    echo
    echo "H. Hapus semua jadwal"
    echo "M. Mulai pantau (tanpa membuka ulang)"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil

    case "$pil" in
      0) return ;;
      [Hh])
        for p in "${PAKET[@]}"; do hapus_jadwal "$p"; done
        echo "Semua jadwal dihapus."
        sleep 1
        ;;
      [Mm])
        tulis "Memantau Roblox yang sedang jalan."
        pantau
        tunggu_enter
        ;;
      *)
        if [[ "$pil" =~ ^[0-9]+$ ]] && [ "$pil" -ge 1 ] && [ "$pil" -le ${#PAKET[@]} ]; then
          atur_jadwal_satu "${PAKET[$((pil - 1))]}"
        else
          echo "Pilihan tidak ada."
          sleep 1
        fi
        ;;
    esac
  done
}

menu_delay() {
  local pil d
  while true; do
    header
    echo "ATUR DELAY"
    echo
    echo "1. Antar Roblox saat dibuka : ${DELAY_DETIK} detik"
    echo "2. Keluar -> masuk (jadwal) : ${GAP_DETIK} detik"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil
    case "$pil" in
      1)
        tulis "Rekomendasi 5-10 detik. Di bawah 5 detik berisiko cloud crash."
        read -r -p "Detik (1-120): " d
        if [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 1 ] && [ "$d" -le 120 ]; then
          DELAY_DETIK=$d
        elif [ -n "$d" ]; then
          echo "Harus angka 1 sampai 120."
          sleep 2
        fi
        ;;
      2)
        tulis "Pilih 0.3 sampai 1 detik (maksimal 1)."
        read -r -p "Detik (contoh 0.5): " d
        if [[ "$d" =~ ^(0\.[3-9]|1|1\.0)$ ]]; then
          GAP_DETIK=$d
        elif [ -n "$d" ]; then
          echo "Harus 0.3 sampai 1."
          sleep 2
        fi
        ;;
      0) return ;;
    esac
  done
}

tutup_semua() {
  header
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
    tunggu_enter
    return
  fi

  echo "Terdeteksi ${#PAKET[@]} Roblox:"
  for p in "${PAKET[@]}"; do echo " - $p"; done
  echo
  read -r -p "Tutup semua? (y/n): " jawab
  if [[ "$jawab" =~ ^[yY]$ ]]; then
    for p in "${PAKET[@]}"; do
      echo "Menutup $p"
      rt "am force-stop $p"
    done
    info_webhook "Semua Roblox ditutup."
    echo
    echo "Semua Roblox sudah ditutup."
  else
    echo "Dibatalkan."
  fi
  tunggu_enter
}

menu_info() {
  local p pid
  header
  echo "CEK PERANGKAT"
  echo
  echo "Android : $(rt "getprop ro.build.version.release" 2>/dev/null | tr -d '\r')"
  if rt "id" 2>/dev/null | grep -q 'uid=0'; then echo "Root    : ya"; else echo "Root    : tidak"; fi
  echo
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
  else
    for p in "${PAKET[@]}"; do
      echo "$p"
      if sedang_jalan "$p"; then
        pid=$(rt "pidof $p" 2>/dev/null | tr -d '\r' | awk '{print $1}')
        echo "  status: jalan (pid $pid)"
        if deteksi_map "$p"; then
          echo "  map   : ${LAST_MAP[$p]}"
        else
          echo "  map   : belum terdeteksi"
          echo "  --- log (untuk dicek) ---"
          rt "logcat -d --pid=$pid" 2>/dev/null | tr -d '\r' | grep -iE 'place|join' | tail -n 5 | cut -c1-120
        fi
      else
        echo "  status: tidak jalan"
        echo "  map   : ${LAST_MAP[$p]:-belum terdeteksi}"
      fi
    done
  fi
  tunggu_enter
}

# ---------- Program utama ----------
cek_key
atur_webhook

while true; do
  header
  if [ -n "$WEBHOOK" ]; then echo "Webhook : aktif"; else echo "Webhook : tidak dipakai"; fi
  echo "Delay   : ${DELAY_DETIK} dtk | keluar-masuk ${GAP_DETIK} dtk"
  echo
  echo "1. AUTO LAUNCH"
  echo "2. AUTO LAUNCH + RE JOIN"
  echo "3. JADWAL KELUAR-MASUK"
  echo "4. ATUR DELAY"
  echo "5. TUTUP SEMUA ROBLOX"
  echo "6. CEK PERANGKAT / MAP"
  echo "7. KELUAR"
  echo
  read -r -p "Pilih: " PILIH

  case "$PILIH" in
    1)
      header
      PLACE_URL=""
      launch_semua
      tunggu_enter
      ;;
    2)
      header
      if tanya_map; then
        echo
        if launch_semua; then
          info_webhook "Auto launch + re join dimulai (${#PAKET[@]} Roblox)."
          pantau
        fi
      fi
      tunggu_enter
      ;;
    3) menu_jadwal ;;
    4) menu_delay ;;
    5) tutup_semua ;;
    6) menu_info ;;
    7)
      echo "Sampai jumpa!"
      exit 0
      ;;
    *)
      echo "Pilihan tidak ada."
      sleep 1
      ;;
  esac
done
