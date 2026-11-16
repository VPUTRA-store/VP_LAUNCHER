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

# --- Anti AFK (auto klik) ---
AFK_AKTIF=0    # 1 = aktif
AFK_DETIK=30   # interval klik (3-50 detik)
AFK_MODE=1     # 1 = ketuk tengah jendela, 2 = geser kecil
declare -A NEXT_KLIK     # kapan klik berikutnya untuk tiap Roblox

# --- Auto posisi jendela ---
POSISI_AKTIF=0 # 1 = jendela ditata otomatis saat auto launch
AREA_PERSEN=100 # tinggi area penataan (persen tinggi layar)
declare -A POS_JENDELA   # posisi tujuan tiap Roblox: "kiri atas kanan bawah"
declare -A BOUNDS_CACHE  # posisi jendela terbaca: "kiri atas kanan bawah"
BOUNDS_WAKTU=0

# --- Cara keluar map saat timer habis ---
MODE_KELUAR=1  # 1 = pintasan keyboard, 2 = pindah ke map lain, 3 = tutup aplikasi
MAP_TUJUAN=""  # dipakai kalau MODE_KELUAR=2
MAP_HASIL=""
STOP=0         # diisi 1 saat CTRL+C ditekan

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

# CTRL+C hanya menghentikan pemantauan dan kembali ke menu.
trap 'STOP=1' INT

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
  local p="$1" msg
  IFS= read -r -d '' msg <<EOF
⚠️ ───────────────────────── ⚠️
       🚨 PERINGATAN 🚨
───────────────────────────────

Akun Roblox kamu mengalami FORCE CLOSE (FC) secara tiba-tiba!

📱 Roblox: \`$p\`
🕐 Waktu: $(date '+%d/%m/%Y %H:%M:%S')

🔄 Sistem sedang memproses perbaikan otomatis & melakukan RE-JOIN ulang ke dalam map.

📌 Status: Harap cek perangkat segera!

───────────────────────────────
🤖 Powered by VP LAUNCHER 
EOF
  kirim_webhook "$msg"
}

# pesan: timer / sesi waktu habis
pesan_timer() {
  local p="$1" msg
  IFS= read -r -d '' msg <<EOF
⏳ ───────────────────────── ⏳
       ⏰ SESI WAKTU HABIS ⏰
───────────────────────────────

Batas waktu sesi AFK untuk akun Roblox kamu telah SELESAI!

📱 Roblox: \`$p\`
🕐 Waktu: $(date '+%d/%m/%Y %H:%M:%S')

🚪 Akun telah otomatis keluar dari map / sesi dihentikan sesuai timer.

📌 Status: Silakan cek & atur ulang jika diperlukan.

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

# ---------- Info layar & jendela ----------
# ukuran layar saat ini (sudah memperhitungkan rotasi): "lebar tinggi"
ukuran_layar() {
  local u
  u=$(rt "dumpsys window displays" 2>/dev/null | tr -d '\r' | grep -oE 'cur=[0-9]+x[0-9]+' | head -n1 | cut -d= -f2)
  if ! [[ "$u" =~ ^[0-9]+x[0-9]+$ ]]; then
    u=$(rt "wm size" 2>/dev/null | tr -d '\r' | grep -oE '[0-9]+x[0-9]+' | tail -n1)
  fi
  echo "${u/x/ }"
}

# baca posisi semua jendela Roblox sekaligus -> BOUNDS_CACHE
ambil_bounds() {
  local p l t r b
  while read -r p l t r b; do
    if [ -n "$p" ] && [ -n "$b" ]; then BOUNDS_CACHE[$p]="$l $t $r $b"; fi
  done < <(rt "dumpsys window windows" 2>/dev/null | tr -d '\r' | awk '
    /Window #[0-9]+ Window\{/ {
      cur = ""
      if (match($0, /u[0-9]+ com\.roblox[A-Za-z0-9_.]*\//)) {
        cur = substr($0, RSTART, RLENGTH - 1)
        sub(/^u[0-9]+ /, "", cur)
        if (cur in seen) cur = ""
      }
    }
    cur != "" && match($0, /(mFrame|frame)=\[-?[0-9]+,-?[0-9]+\]\[-?[0-9]+,-?[0-9]+\]/) {
      s = substr($0, RSTART, RLENGTH)
      sub(/^[A-Za-z]+=/, "", s)
      gsub(/\]\[/, ",", s)
      gsub(/[][]/, "", s)
      if (split(s, a, ",") == 4) {
        print cur, a[1], a[2], a[3], a[4]
        seen[cur] = 1
        cur = ""
      }
    }')
  BOUNDS_WAKTU=$(date +%s)
  fix_tty
}

# nomor task (jendela) milik sebuah paket
ambil_task() {
  local esc="${1//./\\.}"
  rt "dumpsys activity activities" 2>/dev/null | tr -d '\r' \
    | grep -E "Task(Record)?\{[0-9a-f]+ #[0-9]+ .*${esc}([^A-Za-z0-9_.]|$)" | head -n1 \
    | sed -E 's/.*Task(Record)?\{[0-9a-f]+ #([0-9]+) .*/\2/'
}

# bagi layar sesuai jumlah jendela -> satu baris "kiri atas kanan bawah" per jendela
hitung_grid() {
  local n="$1" W="$2" H="$3" cols rows cw ch i c r
  if [ "$n" -le 3 ]; then
    if [ "$H" -ge "$W" ]; then cols=1; rows=$n; else cols=$n; rows=1; fi
  else
    cols=2
    while [ $((cols * cols)) -lt "$n" ]; do cols=$((cols + 1)); done
    rows=$(((n + cols - 1) / cols))
  fi
  cw=$((W / cols))
  ch=$((H / rows))
  for ((i = 0; i < n; i++)); do
    c=$((i % cols))
    r=$((i / cols))
    echo "$((c * cw)) $((r * ch)) $(((c + 1) * cw)) $(((r + 1) * ch))"
  done
}

dekat() {   # selisih dua angka masih wajar? (toleransi 120 px)
  local d=$(($1 - $2))
  [ "${d#-}" -le 120 ]
}

cocok_posisi() {   # $1 = target "l t r b", $2 = terbaca "l t r b"
  local a b c d e f g h
  read -r a b c d <<<"$1"
  read -r e f g h <<<"$2"
  [ -n "$h" ] && dekat "$a" "$e" && dekat "$b" "$f" && dekat "$c" "$g" && dekat "$d" "$h"
}

terapkan_posisi() {
  local p="$1" pos tid l t r b
  pos="${POS_JENDELA[$p]:-}"
  if [ -z "$pos" ]; then return 1; fi
  read -r l t r b <<<"$pos"

  tid=$(ambil_task "$p")
  if [ -z "$tid" ]; then
    echo " $p: jendela tidak ditemukan"
    return 1
  fi

  rt "am task resize $tid $l $t $r $b" >/dev/null 2>&1
  sleep 1
  ambil_bounds
  if cocok_posisi "$pos" "${BOUNDS_CACHE[$p]:-}"; then
    echo " $p: posisi OK"
    return 0
  fi

  rt "am task resize $tid $l,$t,$r,$b" >/dev/null 2>&1
  sleep 1
  ambil_bounds
  if cocok_posisi "$pos" "${BOUNDS_CACHE[$p]:-}"; then
    echo " $p: posisi OK"
    return 0
  fi

  echo " $p: belum cocok (lihat menu CEK PERANGKAT)"
  return 1
}

# tata semua jendela Roblox yang terdeteksi (PAKET harus sudah terisi)
susun_jendela() {
  local n="${#PAKET[@]}" ukuran W H i pos p
  if [ "$n" -eq 0 ]; then return 1; fi

  ukuran=$(ukuran_layar)
  read -r W H <<<"$ukuran"
  if ! [[ "$W" =~ ^[0-9]+$ ]] || ! [[ "$H" =~ ^[0-9]+$ ]]; then
    echo "Ukuran layar tidak terbaca."
    return 1
  fi
  H=$((H * AREA_PERSEN / 100))

  i=0
  while IFS= read -r pos; do
    POS_JENDELA[${PAKET[$i]}]="$pos"
    i=$((i + 1))
  done < <(hitung_grid "$n" "$W" "$H")

  echo "Layar ${W}x${H}, menata $n jendela:"
  for p in "${PAKET[@]}"; do terapkan_posisi "$p"; done
  ambil_bounds
}

# klik / geser di tengah jendela sebuah Roblox
klik_roblox() {
  local p="$1" l t r b cx cy
  read -r l t r b <<<"${BOUNDS_CACHE[$p]:-}"
  if [ -z "$b" ]; then return 1; fi
  cx=$(((l + r) / 2))
  cy=$(((t + b) / 2))
  if [ "$AFK_MODE" = "2" ]; then
    rt "input swipe $cx $cy $((cx + 40)) $cy 200" >/dev/null 2>&1
  else
    rt "input tap $cx $cy" >/dev/null 2>&1
  fi
}

nama_mode_keluar() {
  case "$MODE_KELUAR" in
    2) echo "pindah ke map lain" ;;
    3) echo "tutup aplikasi Roblox" ;;
    *) echo "pintasan keyboard (Esc, L, Enter)" ;;
  esac
}

# keluar dari map sesuai cara yang dipilih buyer
keluar_map() {
  local p="$1" l t r b
  case "$MODE_KELUAR" in
    2)
      if [ -n "$MAP_TUJUAN" ]; then
        rt "am start -a android.intent.action.VIEW -d '$MAP_TUJUAN' -p $p" >/dev/null 2>&1
      fi
      ;;
    3)
      rt "am force-stop $p" >/dev/null 2>&1
      ;;
    *)
      ambil_bounds
      read -r l t r b <<<"${BOUNDS_CACHE[$p]:-}"
      if [ -n "$b" ]; then
        rt "input tap $(((l + r) / 2)) $(((t + b) / 2))" >/dev/null 2>&1   # fokus ke jendela ini
      else
        rt "monkey -p $p -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
      fi
      sleep 1
      rt "input keyevent 111" >/dev/null 2>&1   # Esc (buka menu)
      sleep 2
      rt "input keyevent 40" >/dev/null 2>&1    # L (Leave)
      sleep 2
      rt "input keyevent 66" >/dev/null 2>&1    # Enter (konfirmasi)
      ;;
  esac
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
  if [ "$POSISI_AKTIF" = "1" ]; then
    echo
    echo "Menata jendela (tunggu sebentar)..."
    sleep 6
    susun_jendela
  fi
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
# rejoin=0 : hanya mengurus timer / anti AFK
pantau() {
  local rejoin="$1" now last=0 p sisa
  STOP=0
  echo
  tulis "Memantau... (CTRL+C untuk berhenti)"

  if [ "$AFK_AKTIF" = "1" ]; then
    ambil_bounds
    now=$(date +%s)
    for p in "${PAKET[@]}"; do NEXT_KLIK[$p]=$((now + AFK_DETIK)); done
  fi

  while [ "$STOP" = "0" ]; do
    now=$(date +%s)
    fix_tty

    # --- anti AFK: klik tengah tiap Roblox ---
    if [ "$AFK_AKTIF" = "1" ]; then
      if [ $((now - BOUNDS_WAKTU)) -ge 30 ]; then ambil_bounds; fi
      for p in "${PAKET[@]}"; do
        [ "${SELESAI[$p]:-0}" = "1" ] && continue
        if [ "$now" -ge "${NEXT_KLIK[$p]:-0}" ]; then
          klik_roblox "$p"
          NEXT_KLIK[$p]=$((now + AFK_DETIK))
        fi
      done
    fi

    # --- timer & rejoin: dicek tiap 10 detik ---
    if [ $((now - last)) -ge 10 ]; then
      last=$now

      for p in "${PAKET[@]}"; do
        [ "${SELESAI[$p]:-0}" = "1" ] && continue

        # timer habis -> keluar map (rejoin tidak berjalan lagi untuk Roblox ini)
        if timer_habis "$p" "$now"; then
          tulis "[$(date +%T)] Timer habis: $p -> keluar map"
          keluar_map "$p"
          SELESAI[$p]=1
          TIMER_JADWAL[$p]=0
          pesan_timer "$p"
          continue
        fi

        # Roblox mati -> luncurkan lagi
        if [ "$rejoin" = "1" ] && ! sedang_jalan "$p"; then
          # kasih waktu 60 detik setelah peluncuran sebelum dianggap mati
          if [ $((now - ${MULAI[$p]:-0})) -ge 60 ]; then
            tulis "[$(date +%T)] $p mati -> diluncurkan ulang"
            pesan_fc "$p"
            buka "$p"
            jeda
            if [ "$POSISI_AKTIF" = "1" ]; then
              sleep 6
              terapkan_posisi "$p" >/dev/null
            fi
          fi
        fi
      done

      # mode tanpa rejoin: berhenti kalau tidak ada lagi yang perlu dipantau
      if [ "$rejoin" = "0" ]; then
        sisa=0
        for p in "${PAKET[@]}"; do
          [ "${SELESAI[$p]:-0}" = "1" ] && continue
          if [ "$AFK_AKTIF" = "1" ] || punya_timer "$p"; then sisa=1; fi
        done
        if [ $sisa -eq 0 ]; then
          echo "Semua timer selesai."
          break
        fi
      fi
    fi

    sleep 1
  done

  if [ "$STOP" = "1" ]; then
    echo
    echo "Pemantauan dihentikan."
  fi
  fix_tty
}

# ---------- Menu ----------
baca_map() {
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

  MAP_HASIL="roblox://placeId=$place"
  if [ -n "$kode" ]; then
    MAP_HASIL="roblox://placeId=$place&linkCode=$kode"
  fi
  return 0
}

tanya_map() {
  if baca_map; then
    PLACE_URL="$MAP_HASIL"
    return 0
  fi
  return 1
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
    echo "K. Cara keluar map"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil

    case "$pil" in
      0) return ;;
      [Kk]) menu_keluar_map ;;
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
    info_webhook "Semua Roblox ditutup."
    echo
    echo "Semua Roblox sudah ditutup."
  else
    echo "Dibatalkan."
  fi
  tunggu_enter
}

menu_afk() {
  local pil d
  while true; do
    header
    echo "ANTI AFK (AUTO KLIK)"
    tulis "Klik tengah jendela tiap Roblox supaya tidak dianggap diam. Berjalan saat menu 1 atau 2 dijalankan."
    echo
    if [ "$AFK_AKTIF" = "1" ]; then echo "Status  : AKTIF"; else echo "Status  : MATI"; fi
    echo "Interval: ${AFK_DETIK} detik (3-50)"
    if [ "$AFK_MODE" = "2" ]; then echo "Mode    : geser kecil"; else echo "Mode    : ketuk"; fi
    echo
    echo "1. Aktif / matikan"
    echo "2. Atur interval"
    echo "3. Ganti mode klik"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil
    case "$pil" in
      1)
        if [ "$AFK_AKTIF" = "1" ]; then AFK_AKTIF=0; else AFK_AKTIF=1; fi
        ;;
      2)
        read -r -p "Interval (3-50 detik): " d
        if [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 3 ] && [ "$d" -le 50 ]; then
          AFK_DETIK=$d
        else
          echo "Harus angka 3 sampai 50."
          sleep 2
        fi
        ;;
      3)
        if [ "$AFK_MODE" = "2" ]; then AFK_MODE=1; else AFK_MODE=2; fi
        ;;
      0) return ;;
    esac
  done
}

menu_posisi() {
  local pil d
  while true; do
    header
    echo "AUTO POSISI"
    tulis "Jendela Roblox ditata rapi di layar saat auto launch, supaya tidak saling menimpa."
    echo
    if [ "$POSISI_AKTIF" = "1" ]; then echo "Status      : AKTIF"; else echo "Status      : MATI"; fi
    echo "Tinggi area : ${AREA_PERSEN}% layar"
    echo
    echo "1. Aktif / matikan"
    echo "2. Atur tinggi area"
    echo "3. Susun sekarang (tes)"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil
    case "$pil" in
      1)
        if [ "$POSISI_AKTIF" = "1" ]; then POSISI_AKTIF=0; else POSISI_AKTIF=1; fi
        ;;
      2)
        read -r -p "Tinggi area (30-100): " d
        if [[ "$d" =~ ^[0-9]+$ ]] && [ "$d" -ge 30 ] && [ "$d" -le 100 ]; then
          AREA_PERSEN=$d
        else
          echo "Harus angka 30 sampai 100."
          sleep 2
        fi
        ;;
      3)
        header
        cari_roblox
        if [ ${#PAKET[@]} -eq 0 ]; then
          tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
        else
          susun_jendela
        fi
        tunggu_enter
        ;;
      0) return ;;
    esac
  done
}

tes_keluar_map() {
  local i p pil
  header
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
    tunggu_enter
    return
  fi
  echo "Pilih Roblox untuk dites:"
  i=0
  for p in "${PAKET[@]}"; do
    i=$((i + 1))
    echo "$i. $p"
  done
  echo
  read -r -p "Nomor: " pil
  if [[ "$pil" =~ ^[0-9]+$ ]] && [ "$pil" -ge 1 ] && [ "$pil" -le ${#PAKET[@]} ]; then
    p="${PAKET[$((pil - 1))]}"
    tulis "Cara: $(nama_mode_keluar). Perhatikan layar Roblox..."
    keluar_map "$p"
    echo "Selesai dijalankan."
  else
    echo "Pilihan tidak ada."
  fi
  tunggu_enter
}

menu_keluar_map() {
  local pil
  while true; do
    header
    tulis "CARA KELUAR MAP saat timer habis"
    echo
    tulis "Sekarang: $(nama_mode_keluar)"
    if [ "$MODE_KELUAR" = "2" ]; then tulis "Map tujuan: ${MAP_TUJUAN:-belum diatur}"; fi
    echo
    echo "1. Pintasan keyboard"
    echo "2. Pindah ke map lain"
    echo "3. Tutup aplikasi"
    echo "4. Tes sekarang"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil
    case "$pil" in
      1) MODE_KELUAR=1 ;;
      2)
        echo
        if baca_map; then
          MAP_TUJUAN="$MAP_HASIL"
          MODE_KELUAR=2
        else
          sleep 2
        fi
        ;;
      3) MODE_KELUAR=3 ;;
      4) tes_keluar_map ;;
      0) return ;;
    esac
  done
}

menu_info() {
  local p
  header
  echo "CEK PERANGKAT"
  echo
  echo "Android : $(rt "getprop ro.build.version.release" 2>/dev/null | tr -d '\r')"
  echo "Layar   : $(ukuran_layar | tr ' ' 'x')"
  echo "DPI     : $(rt "wm density" 2>/dev/null | grep -oE '[0-9]+' | tail -n1)"
  if rt "id" 2>/dev/null | grep -q 'uid=0'; then echo "Root    : ya"; else echo "Root    : tidak"; fi
  if rt "am help" 2>&1 | grep -qi 'task resize'; then echo "Atur jendela: ada"; else echo "Atur jendela: tidak terlihat"; fi
  echo
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
  else
    ambil_bounds
    for p in "${PAKET[@]}"; do
      echo "$p"
      echo "  task  : $(ambil_task "$p")"
      echo "  posisi: ${BOUNDS_CACHE[$p]:-tidak terbaca}"
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
  echo "Delay   : ${DELAY_DETIK} detik"
  if [ "$AFK_AKTIF" = "1" ]; then echo "Anti AFK: aktif (${AFK_DETIK} dtk)"; else echo "Anti AFK: mati"; fi
  if [ "$POSISI_AKTIF" = "1" ]; then echo "Posisi  : otomatis"; else echo "Posisi  : manual"; fi
  echo
  echo "1. AUTO LAUNCH"
  echo "2. AUTO LAUNCH + RE JOIN"
  echo "3. TIMER"
  echo "4. ATUR DELAY"
  echo "5. ANTI AFK (AUTO KLIK)"
  echo "6. AUTO POSISI"
  echo "7. TUTUP SEMUA ROBLOX"
  echo "8. CEK PERANGKAT"
  echo "9. KELUAR"
  echo
  read -r -p "Pilih: " PILIH

  case "$PILIH" in
    1)
      header
      PLACE_URL=""
      if launch_semua; then
        if ada_timer || [ "$AFK_AKTIF" = "1" ]; then pantau 0; fi
      fi
      tunggu_enter
      ;;
    2)
      header
      if tanya_map; then
        echo
        if launch_semua; then
          info_webhook "Auto launch + re join dimulai (${#PAKET[@]} Roblox)."
          pantau 1
        fi
      fi
      tunggu_enter
      ;;
    3) menu_timer ;;
    4) menu_delay ;;
    5) menu_afk ;;
    6) menu_posisi ;;
    7) tutup_semua ;;
    8) menu_info ;;
    9)
      echo "Sampai jumpa!"
      exit 0
      ;;
    *)
      echo "Pilihan tidak ada."
      sleep 1
      ;;
  esac
done
