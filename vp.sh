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
DELAY_DETIK=10 # jeda antar Roblox saat dibuka (bisa diatur buyer di menu)
PAKET=()       # daftar aplikasi Roblox yang terdeteksi
declare -A TIMER_MENIT   # timer per aplikasi (menit). 0 = tanpa timer
declare -A MULAI         # kapan aplikasi terakhir diluncurkan
declare -A SELESAI       # 1 = timernya sudah habis, jangan di-rejoin
declare -A TIMER_JADWAL  # jadwal off (waktu pasti, epoch). 0 = tidak ada
declare -A TMULAI        # kapan timer durasi mulai dihitung (tidak ikut ter-reset saat rejoin)

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

jeda() {
  echo "   jeda ${DELAY_DETIK} detik..."
  sleep "$DELAY_DETIK"
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
    TMULAI[$p]=$(date +%s)
    if [ "${TIMER_JADWAL[$p]:-0}" -gt 0 ] && [ "${TIMER_JADWAL[$p]}" -le "$(date +%s)" ]; then
      echo "   jadwal off sudah lewat, dilewati"
      TIMER_JADWAL[$p]=0
    fi
    buka "$p"
    if [ $i -lt ${#PAKET[@]} ]; then jeda; fi
  done
  echo
  echo "Semua Roblox sudah dibuka."
  return 0
}

punya_timer() {
  [ "${TIMER_MENIT[$1]:-0}" -gt 0 ] || [ "${TIMER_JADWAL[$1]:-0}" -gt 0 ]
}

ada_timer() {
  for p in "${PAKET[@]}"; do
    if punya_timer "$p"; then return 0; fi
  done
  return 1
}

# apakah timer paket $1 sudah habis pada waktu $2 (epoch)?
timer_habis() {
  local p="$1" now="$2"
  local j="${TIMER_JADWAL[$p]:-0}" t="${TIMER_MENIT[$p]:-0}"
  if [ "$j" -gt 0 ] && [ "$now" -ge "$j" ]; then return 0; fi
  if [ "$t" -gt 0 ] && [ $((now - ${TMULAI[$p]:-$now})) -ge $((t * 60)) ]; then return 0; fi
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
      if timer_habis "$p" "$now"; then
        tulis "[$(date +%T)] Timer habis: $p -> ditutup"
        rt "am force-stop $p" >/dev/null 2>&1
        SELESAI[$p]=1
        TIMER_JADWAL[$p]=0
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
          jeda
        fi
      fi
    done

    # mode timer saja: berhenti kalau semua timer sudah selesai
    if [ "$rejoin" = "0" ]; then
      local sisa=0
      for p in "${PAKET[@]}"; do
        if punya_timer "$p" && [ "${SELESAI[$p]:-0}" != "1" ]; then
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

# ---------- Timer ----------
format_durasi() {
  local m="$1" h j s out=""
  h=$((m / 1440)); j=$(((m % 1440) / 60)); s=$((m % 60))
  if [ "$h" -gt 0 ]; then out="$h hari "; fi
  if [ "$j" -gt 0 ]; then out="$out$j jam "; fi
  if [ "$s" -gt 0 ]; then out="$out$s menit"; fi
  echo "${out% }"
}

ket_timer() {
  local p="$1"
  if [ "${TIMER_JADWAL[$p]:-0}" -gt 0 ]; then
    echo "off $(date -d "@${TIMER_JADWAL[$p]}" '+%d/%m %H:%M')"
  elif [ "${TIMER_MENIT[$p]:-0}" -gt 0 ]; then
    echo "durasi $(format_durasi "${TIMER_MENIT[$p]}")"
  else
    echo "tanpa timer"
  fi
}

# cari waktu terdekat (di masa depan) untuk tanggal & jam yang dipilih
hitung_jadwal() {
  local tgl=$((10#$1)) jam=$((10#$2)) mnt=$((10#$3)) i ym e now
  now=$(date +%s)
  for i in 0 1 2 3 4 5 6 7 8 9 10 11 12; do
    ym=$(date -d "$(date +%Y-%m-01) +$i month" +%Y-%m 2>/dev/null) || continue
    e=$(date -d "$ym-$(printf '%02d' "$tgl") $(printf '%02d' "$jam"):$(printf '%02d' "$mnt"):00" +%s 2>/dev/null) || continue
    if [ "$e" -gt "$now" ]; then
      echo "$e"
      return 0
    fi
  done
  return 1
}

baca_angka() {   # hasil di $ANGKA, kosong dianggap 0
  local x
  while true; do
    read -r -p "$1" x
    [ -z "$x" ] && x=0
    if [[ "$x" =~ ^[0-9]+$ ]]; then
      ANGKA=$((10#$x))
      return
    fi
    echo "  harus angka"
  done
}

timer_durasi() {
  local p="$1" h j m total
  echo
  tulis "Isi angka, kosong = 0. Timer mulai dihitung saat Roblox diluncurkan."
  baca_angka "Hari  : "; h=$ANGKA
  baca_angka "Jam   : "; j=$ANGKA
  baca_angka "Menit : "; m=$ANGKA
  total=$((h * 1440 + j * 60 + m))
  if [ "$total" -le 0 ]; then
    TIMER_MENIT[$p]=0
    echo "Durasi 0, timer dihapus."
  else
    TIMER_MENIT[$p]=$total
    TIMER_JADWAL[$p]=0
    echo "Timer: $(format_durasi "$total")"
  fi
  sleep 2
}

timer_jadwal() {
  local p="$1" tgl jm jam mnt e
  echo
  tulis "Roblox ditutup pada tanggal & jam yang dipilih (format 24 jam, ikut jam Redfinger)."
  read -r -p "Tanggal (1-31): " tgl
  if ! [[ "$tgl" =~ ^[0-9]+$ ]] || [ "$((10#$tgl))" -lt 1 ] || [ "$((10#$tgl))" -gt 31 ]; then
    echo "Tanggal tidak valid."
    sleep 2
    return
  fi
  read -r -p "Jam:menit (contoh 00:10): " jm
  if ! [[ "$jm" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]]; then
    echo "Format jam salah."
    sleep 2
    return
  fi
  jam="${BASH_REMATCH[1]}"
  mnt="${BASH_REMATCH[2]}"
  e=$(hitung_jadwal "$tgl" "$jam" "$mnt")
  if [ -z "$e" ]; then
    echo "Tanggal tidak ditemukan."
    sleep 2
    return
  fi
  TIMER_JADWAL[$p]=$e
  TIMER_MENIT[$p]=0
  echo "Roblox akan ditutup:"
  echo "$(date -d "@$e" '+%d/%m/%Y %H:%M')"
  sleep 2
}

atur_timer_satu() {
  local p="$1" pil
  header
  echo "$p"
  echo "Timer: $(ket_timer "$p")"
  echo
  echo "1. Durasi (hari/jam/menit)"
  echo "2. Jadwal (tanggal & jam)"
  echo "3. Hapus timer"
  echo "0. Kembali"
  echo
  read -r -p "Pilih: " pil
  case "$pil" in
    1) timer_durasi "$p" ;;
    2) timer_jadwal "$p" ;;
    3)
      TIMER_MENIT[$p]=0
      TIMER_JADWAL[$p]=0
      echo "Timer dihapus."
      sleep 1
      ;;
  esac
}

menu_timer() {
  header
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
    tunggu_enter
    return
  fi

  local pil i p nowt
  while true; do
    header
    echo "TIMER (1 timer untuk 1 Roblox)"
    echo "Jam Redfinger: $(date '+%d/%m %H:%M')"
    echo
    i=0
    for p in "${PAKET[@]}"; do
      i=$((i + 1))
      echo "$i. $p"
      echo "   $(ket_timer "$p")"
    done
    echo
    echo "H. Hapus semua timer"
    echo "M. Mulai pantau timer"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil

    case "$pil" in
      0) return ;;
      [Hh])
        for p in "${PAKET[@]}"; do
          TIMER_MENIT[$p]=0
          TIMER_JADWAL[$p]=0
        done
        echo "Semua timer dihapus."
        sleep 1
        ;;
      [Mm])
        if ! ada_timer; then
          echo "Belum ada timer."
          sleep 2
        else
          nowt=$(date +%s)
          for p in "${PAKET[@]}"; do
            SELESAI[$p]=0
            TMULAI[$p]=$nowt
            if [ "${TIMER_JADWAL[$p]:-0}" -gt 0 ] && [ "${TIMER_JADWAL[$p]}" -le "$nowt" ]; then
              TIMER_JADWAL[$p]=0
            fi
          done
          tulis "Memantau timer tanpa membuka ulang Roblox."
          pantau 0
          tunggu_enter
        fi
        ;;
      *)
        if [[ "$pil" =~ ^[0-9]+$ ]] && [ "$pil" -ge 1 ] && [ "$pil" -le ${#PAKET[@]} ]; then
          atur_timer_satu "${PAKET[$((pil - 1))]}"
        else
          echo "Pilihan tidak ada."
          sleep 1
        fi
        ;;
    esac
  done
}

menu_delay() {
  header
  tulis "ATUR DELAY antar Roblox saat dibuka"
  tulis "(rekomendasi 5-10 detik)"
  echo
  echo "Delay sekarang: ${DELAY_DETIK} detik"
  read -r -p "Delay baru (detik): " d
  if [ -z "$d" ]; then
    echo "Tidak diubah."
  elif [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 1 ] && [ "$d" -le 120 ]; then
    DELAY_DETIK=$d
    echo "Delay diatur ke ${DELAY_DETIK} detik."
    if [ "$d" -lt 5 ]; then
      tulis "Peringatan: di bawah 5 detik berisiko membuat cloud crash."
    fi
  else
    tulis "Harus angka 1 sampai 120."
  fi
  tunggu_enter
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
    kirim_webhook "Semua Roblox ditutup."
    echo
    echo "Semua Roblox sudah ditutup."
  else
    echo "Dibatalkan."
  fi
  tunggu_enter
}

# ---------- Program utama ----------
cek_key
atur_webhook

while true; do
  header
  if [ -n "$WEBHOOK" ]; then echo "Webhook: aktif"; else echo "Webhook: tidak dipakai"; fi
  echo "Delay  : ${DELAY_DETIK} detik"
  echo
  echo "1. AUTO LAUNCH"
  echo "2. AUTO LAUNCH + RE JOIN"
  echo "3. TIMER"
  echo "4. ATUR DELAY"
  echo "5. TUTUP SEMUA ROBLOX"
  echo "6. KELUAR"
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
    4) menu_delay ;;
    5) tutup_semua ;;
    6)
      echo "Sampai jumpa!"
      exit 0
      ;;
    *)
      echo "Pilihan tidak ada."
      sleep 1
      ;;
  esac
done
