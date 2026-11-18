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
declare -A TIMER_JADWAL  # jadwal off (waktu pasti, epoch). 0 = tidak ada
declare -A TMULAI        # kapan timer durasi mulai dihitung (tidak ikut ter-reset saat rejoin)

MAP_HASIL=""
declare -A LAST_MAP      # map terakhir tiap Roblox (Place ID), dibaca otomatis dari catatan Roblox
declare -A LAUNCH_COMP   # nama aktivitas peluncur tiap Roblox (supaya buka aplikasi cepat)
JEDA_MS=0                # jeda keluar-masuk terakhir (milidetik)

# --- status di dalam map atau tidak ---
CPU_AMBANG=3             # CPU (persen) di atas ini dianggap sedang di dalam map
declare -A UID_PKG       # uid tiap aplikasi Roblox
declare -A PREV_TICK     # hitungan CPU sebelumnya
declare -A PREV_WAKTU    # waktu hitungan CPU sebelumnya
declare -A PERNAH_MAP    # 1 = sudah terlihat masuk map sejak dibuka
declare -A KELUAR_CNT    # berapa kali berturut-turut terlihat tidak di map
ST_PID=""; ST_CPU=""; ST_UDP=0; ST_DALAM=""
STOP=0                   # diisi 1 saat CTRL+C ditekan

# --- masa aktif key ---
AKTIF_FILE="$HOME/.vp_aktivasi"     # catatan waktu pemakaian pertama (di Termux)
SD_FILE="/sdcard/.vp_aktivasi"      # salinan di penyimpanan, selamat kalau Termux dihapus
KEY_HASH=""
EXP_EPOCH=0
LAST_VALIDASI=0
DAFTAR=""
WAKTU_SERVER=0
DB_URL=""   # alamat database pencatat pemakaian (dibaca dari keys.txt, baris #db=)

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
# waktu pemakaian pertama sebuah key (paling awal dari dua catatan), kosong kalau belum pernah
baca_aktivasi() {
  local h="$1" a b
  a=$(grep -s "^$h|" "$AKTIF_FILE" | tail -n1 | cut -d'|' -f2)
  b=$(rt "cat $SD_FILE 2>/dev/null" 2>/dev/null | tr -d '\r' | grep "^$h|" | tail -n1 | cut -d'|' -f2)
  [[ "$a" =~ ^[0-9]+$ ]] || a=""
  [[ "$b" =~ ^[0-9]+$ ]] || b=""
  # lengkapi catatan yang hilang (misal Termux baru dipasang ulang)
  if [ -z "$a" ] && [ -n "$b" ]; then echo "$h|$b" >> "$AKTIF_FILE"; fi
  if [ -n "$a" ] && [ -z "$b" ]; then rt "echo '$h|$a' >> $SD_FILE" >/dev/null 2>&1; fi
  if [ -n "$a" ] && [ -n "$b" ]; then
    if [ "$a" -le "$b" ]; then echo "$a"; else echo "$b"; fi
  else
    echo "${a:-$b}"
  fi
}

tulis_aktivasi() {
  echo "$1|$2" >> "$AKTIF_FILE"
  rt "echo '$1|$2' >> $SD_FILE" >/dev/null 2>&1
}

# ambil daftar key dari GitHub + waktu server (dari header Date, sulit dipalsukan)
ambil_daftar() {
  local tmp="${TMPDIR:-/tmp}" h k d
  h="$tmp/vp_h.$$"
  k="$tmp/vp_k.$$"
  if ! curl -fsSL --max-time 20 -D "$h" -o "$k" "$KEY_URL?t=$(date +%s)" 2>/dev/null; then
    rm -f "$h" "$k"
    return 1
  fi
  DAFTAR=$(tr -d '\r' < "$k")
  DB_URL=$(printf '%s\n' "$DAFTAR" | grep -m1 '^#db=' | cut -d= -f2- | tr -d ' ')
  [[ "$DB_URL" =~ ^https://[A-Za-z0-9.-]+\.(firebaseio\.com|firebasedatabase\.app)$ ]] || DB_URL=""
  d=$(tr -d '\r' < "$h" | grep -i '^date:' | tail -n1 | cut -d' ' -f2-)
  WAKTU_SERVER=$(date -d "$d" +%s 2>/dev/null)
  [[ "$WAKTU_SERVER" =~ ^[0-9]+$ ]] || WAKTU_SERVER=$(date +%s)
  rm -f "$h" "$k"
  return 0
}

# hitung kapan key habis. Isi baris: "hash|jumlah hari" (hitung sejak pemakaian pertama)
# atau "hash|YYYY-MM-DD" (format lama, tanggal pasti)
hitung_exp() {
  local nilai now="$2" akt
  nilai=$(printf '%s' "$1" | cut -d'|' -f2 | tr -d ' ')
  if [[ "$nilai" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    EXP_EPOCH=$(date -d "$nilai 23:59:59" +%s 2>/dev/null)
  elif [[ "$nilai" =~ ^[0-9]+$ ]]; then
    akt=$(baca_aktivasi "$KEY_HASH")
    if [ -z "$akt" ]; then
      akt="$now"
      tulis_aktivasi "$KEY_HASH" "$akt"
    fi
    EXP_EPOCH=$((akt + nilai * 86400))
  else
    return 1
  fi
  [[ "$EXP_EPOCH" =~ ^[0-9]+$ ]]
}

# key diblokir admin? (kolom ke-3 bernilai B)
key_diblokir() {
  [ "$(printf '%s' "$1" | cut -d'|' -f3 | tr -d ' ')" = "B" ]
}

# pengenal perangkat: android_id Redfinger, atau angka acak yang disimpan kalau tidak terbaca
id_perangkat() {
  local id
  id=$(rt "settings get secure android_id" 2>/dev/null | tr -d '\r\n ')
  if ! [[ "$id" =~ ^[0-9a-fA-F]{8,}$ ]]; then
    id=$(cat "$HOME/.vp_dev" 2>/dev/null)
    if [ -z "$id" ]; then
      id=$(tr -dc 'a-f0-9' </dev/urandom | head -c 16)
      echo "$id" > "$HOME/.vp_dev"
    fi
  fi
  echo "${id:0:12}"
}

# catat satu pemakaian ke database (hanya menambah catatan baru, tidak bisa mengubah yang lama)
lapor_pemakaian() {
  local dev
  if [ -z "$DB_URL" ]; then return 0; fi
  dev=$(id_perangkat)
  curl -s -m 8 -X POST \
    -d "{\"dev\":\"$dev\",\"t\":{\".sv\":\"timestamp\"}}" \
    "$DB_URL/pakai/$KEY_HASH.json" >/dev/null 2>&1
  return 0
}

cek_key() {
  header
  read -r -p "Masukkan key kamu: " KEY
  if [ -z "$KEY" ]; then
    echo "Key kosong."
    exit 1
  fi

  echo "Memeriksa key..."
  if ! ambil_daftar; then
    tulis "Gagal terhubung ke server key. Cek internet kamu."
    exit 1
  fi

  KEY_HASH=$(printf '%s' "$KEY" | sha256sum | cut -d' ' -f1)
  BARIS=$(printf '%s\n' "$DAFTAR" | grep -i "^$KEY_HASH|" | head -n1)
  if [ -z "$BARIS" ]; then
    echo "Key salah."
    exit 1
  fi

  if key_diblokir "$BARIS"; then
    tulis "Key ini diblokir oleh admin."
    exit 1
  fi

  if ! hitung_exp "$BARIS" "$WAKTU_SERVER"; then
    tulis "Data key rusak. Hubungi admin."
    exit 1
  fi
  if [ "$WAKTU_SERVER" -ge "$EXP_EPOCH" ]; then
    tulis "Key sudah kedaluwarsa ($(date -d "@$EXP_EPOCH" '+%d/%m/%Y %H:%M'))."
    exit 1
  fi

  LAST_VALIDASI=$(date +%s)
  lapor_pemakaian
  echo "Key benar."
  tulis "Aktif sampai $(date -d "@$EXP_EPOCH" '+%d/%m/%Y %H:%M')"
  sleep 2
}

# keluar dari launcher (Roblox yang sedang berjalan tidak ikut ditutup)
keluar_habis() {
  fix_tty
  echo
  tulis "$1"
  tulis "Launcher ditutup. Roblox yang sedang berjalan tidak ikut ditutup."
  exit 0
}

# cek ulang ke GitHub: key dihapus admin / masa aktif habis menurut waktu server
validasi_ulang() {
  local baris
  LAST_VALIDASI=$(date +%s)
  if ! ambil_daftar; then return 0; fi    # tidak ada internet: jangan ditendang
  baris=$(printf '%s\n' "$DAFTAR" | grep -i "^$KEY_HASH|" | head -n1)
  if [ -z "$baris" ]; then keluar_habis "Key kamu sudah tidak berlaku (dihapus admin)."; fi
  if key_diblokir "$baris"; then keluar_habis "Key kamu diblokir oleh admin."; fi
  if [ "$WAKTU_SERVER" -ge "$EXP_EPOCH" ]; then keluar_habis "Masa aktif key kamu sudah habis."; fi
}

# ringan, dipanggil sering: cek jam lokal, dan cek ulang ke GitHub tiap 5 menit
cek_masa_aktif() {
  local now
  now=$(date +%s)
  if [ "$now" -ge "$EXP_EPOCH" ]; then keluar_habis "Masa aktif key kamu sudah habis."; fi
  if [ $((now - LAST_VALIDASI)) -ge 300 ]; then validasi_ulang; fi
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
  local p="$1" sebab="${2:-aplikasi tertutup (FC)}" msg
  IFS= read -r -d '' msg <<EOF
⚠️ ───────────────────────── ⚠️
       🚨 PERINGATAN 🚨
───────────────────────────────

Akun Roblox kamu mengalami FORCE CLOSE (FC) secara tiba-tiba!

📱 Roblox: \`$p\`
🕐 Waktu: $(date '+%d/%m/%Y %H:%M:%S')
🔎 Penyebab: $sebab

🔄 Sistem sedang memproses perbaikan otomatis & melakukan RE-JOIN ulang ke dalam map.

📌 Status: Harap cek perangkat segera!

───────────────────────────────
🤖 Powered by VP LAUNCHER 
EOF
  kirim_webhook "$msg"
}

# pesan: timer / sesi waktu habis
pesan_timer() {
  local p="$1" ms="$2" msg
  IFS= read -r -d '' msg <<EOF
⏳ ───────────────────────── ⏳
       ⏰ SESI WAKTU HABIS ⏰
───────────────────────────────

Batas waktu sesi AFK untuk akun Roblox kamu telah SELESAI!

📱 Roblox: \`$p\`
🕐 Waktu: $(date '+%d/%m/%Y %H:%M:%S')
⚡ Jeda keluar-masuk: ${ms} ms

🚪 Akun telah otomatis keluar dari Roblox sesuai timer dan sedang masuk kembali.

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

# alamat map yang dipakai saat membuka/rejoin: link buatan buyer,
# kalau kosong pakai map terakhir yang terbaca otomatis
url_map() {
  local p="$1"
  if [ -n "$PLACE_URL" ]; then
    echo "$PLACE_URL"
  elif [ -n "${LAST_MAP[$p]:-}" ]; then
    echo "roblox://placeId=${LAST_MAP[$p]}"
  fi
}

# baca map terakhir dari catatan (logcat) Roblox yang sedang berjalan
deteksi_map() {
  local p="$1" pid id
  pid=$(rt "pidof $p" 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
  if [ -z "$pid" ]; then return 1; fi
  id=$(rt "logcat -d -v brief --pid=$pid" 2>/dev/null | tr -d '\r' \
    | grep -iE "joining game|place ?id|place_id" \
    | grep -ioE "(place|placeid|place_id)[=: \"']+[0-9]{5,}" | tail -n1 | grep -oE '[0-9]{5,}$')
  if [ -n "$id" ]; then
    LAST_MAP[$p]="$id"
    return 0
  fi
  return 1
}

# nama aktivitas peluncur sebuah aplikasi (dicatat sekali)
komponen_launcher() {
  local p="$1" c
  if [ -z "${LAUNCH_COMP[$p]:-}" ]; then
    c=$(rt "cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -p $p" 2>/dev/null \
      | tr -d '\r' | grep -E "^${p//./\\.}/" | tail -n1)
    LAUNCH_COMP[$p]="${c:-none}"
  fi
  if [ "${LAUNCH_COMP[$p]}" = "none" ]; then return 1; fi
  echo "${LAUNCH_COMP[$p]}"
}

# perintah untuk membuka Roblox (ke map kalau alamatnya diketahui)
# mode "awal"  : hanya buka Roblox (masuk map hanya kalau buyer mengisi Place ID/link sendiri)
# mode "rejoin": masuk ke map (link buyer, atau map terakhir yang terbaca otomatis)
perintah_buka() {
  local p="$1" mode="${2:-awal}" url comp
  if [ "$mode" = "rejoin" ]; then
    url=$(url_map "$p")
  else
    url="$PLACE_URL"
  fi
  if [ -n "$url" ]; then
    echo "am start -a android.intent.action.VIEW -d '$url' -p $p"
  else
    comp=$(komponen_launcher "$p")
    if [ -n "$comp" ]; then
      echo "am start -n $comp"
    else
      echo "monkey -p $p -c android.intent.category.LAUNCHER 1"
    fi
  fi
}

buka() {
  local p="$1" mode="${2:-awal}"
  rt "$(perintah_buka "$p" "$mode")" >/dev/null 2>&1
  MULAI[$p]=$(date +%s)
}

# keluar lalu masuk lagi dalam SATU perintah supaya jedanya sependek mungkin
restart_cepat() {
  local p="$1" cmd t0 t1
  cmd=$(perintah_buka "$p" awal)   # disiapkan dulu, di luar hitungan jeda
  t0=$(date +%s%N)
  rt "am force-stop $p; $cmd" >/dev/null 2>&1
  t1=$(date +%s%N)
  JEDA_MS=$(((t1 - t0) / 1000000))
  MULAI[$p]=$(date +%s)
}

jeda() {
  echo "   jeda ${DELAY_DETIK} detik..."
  sleep "$DELAY_DETIK"
}

# ---------- Status: sedang di dalam map atau tidak ----------
uid_paket() {
  local p="$1" u
  if [ -z "${UID_PKG[$p]:-}" ]; then
    u=$(rt "stat -c %u /data/data/$p" 2>/dev/null | tr -d '\r\n ')
    if ! [[ "$u" =~ ^[0-9]+$ ]]; then
      u=$(rt "ls -ldn /data/data/$p" 2>/dev/null | tr -d '\r' | awk '{print $3}')
    fi
    if [[ "$u" =~ ^[0-9]+$ ]]; then UID_PKG[$p]="$u"; fi
  fi
  echo "${UID_PKG[$p]:-}"
}

# jumlah soket UDP milik aplikasi (tanpa DNS dan QUIC/443). Di dalam map ada koneksi UDP ke server game.
jumlah_udp() {
  local uid="$1"
  if [ -z "$uid" ]; then echo 0; return; fi
  rt "cat /proc/net/udp /proc/net/udp6" 2>/dev/null | tr -d '\r' | awk -v uid="$uid" '
    $1 ~ /^[0-9]+:$/ && $8 == uid {
      n = split($3, r, ":"); rp = toupper(r[n])
      if (rp != "01BB" && rp != "0035") c++
    }
    END { print c + 0 }'
}

ticks_cpu() {   # $1 = pid -> pemakaian CPU kumulatif (tick)
  rt "cat /proc/$1/stat" 2>/dev/null | tr -d '\r' | sed 's/^.*) //' | awk '{ print $12 + $13 }'
}

# periksa satu aplikasi. Hasil: ST_PID, ST_CPU, ST_UDP, ST_DALAM (1 = di map, 0 = tidak, kosong = belum bisa dinilai)
# return 1 kalau aplikasinya mati
periksa_map() {
  local p="$1" pid uid tk now dt dtk
  ST_PID=""; ST_CPU=""; ST_UDP=0; ST_DALAM=""
  pid=$(rt "pidof $p" 2>/dev/null | tr -d '\r' | cut -d' ' -f1)
  if [ -z "$pid" ]; then
    unset "PREV_TICK[$p]"
    return 1
  fi
  ST_PID="$pid"
  uid=$(uid_paket "$p")
  ST_UDP=$(jumlah_udp "$uid")
  tk=$(ticks_cpu "$pid")
  now=$(date +%s)
  if [[ "$tk" =~ ^[0-9]+$ ]]; then
    if [ -n "${PREV_TICK[$p]:-}" ]; then
      dt=$((now - ${PREV_WAKTU[$p]}))
      if [ "$dt" -lt 1 ]; then dt=1; fi
      dtk=$((tk - ${PREV_TICK[$p]}))
      if [ "$dtk" -lt 0 ]; then dtk=0; fi
      ST_CPU=$((dtk / dt))
    fi
    PREV_TICK[$p]=$tk
    PREV_WAKTU[$p]=$now
  fi
  if [ "$ST_UDP" -ge 1 ]; then
    ST_DALAM=1
  elif [ -n "$ST_CPU" ]; then
    if [ "$ST_CPU" -ge "$CPU_AMBANG" ]; then ST_DALAM=1; else ST_DALAM=0; fi
  fi
  return 0
}

# masuk lagi ke map untuk Roblox yang sudah keluar dari map (aplikasinya masih hidup)
rejoin_map() {
  local p="$1" n="${1#com.roblox.}"
  if [ -z "$(url_map "$p")" ]; then
    tulis "[$(date +%T)] $n keluar map, tapi map belum diketahui. Isi Place ID di menu 2."
    PERNAH_MAP[$p]=0
    KELUAR_CNT[$p]=0
    return 1
  fi
  tulis "[$(date +%T)] $n keluar map -> rejoin"
  pesan_fc "$p" "keluar dari map"
  buka "$p" rejoin
  PERNAH_MAP[$p]=1
  KELUAR_CNT[$p]=-9     # beri waktu ~90 detik untuk memuat map; kalau gagal dicoba lagi
  jeda
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

# rejoin=1 : kalau Roblox mati, luncurkan lagi ke map terakhir
# rejoin=0 : hanya mengurus timer
pantau() {
  local rejoin="$1" now last=0 lastmap=0 p sisa n
  STOP=0
  echo
  tulis "Memantau... (CTRL+C untuk berhenti)"

  # mulai dari nol: Roblox harus terlihat masuk map dulu, baru bisa dianggap keluar map
  for p in "${PAKET[@]}"; do
    PERNAH_MAP[$p]=0
    KELUAR_CNT[$p]=0
  done

  while [ "$STOP" = "0" ]; do
    cek_masa_aktif
    now=$(date +%s)
    fix_tty

    # --- timer: dicek tiap detik (tanpa perintah root) ---
    for p in "${PAKET[@]}"; do
      if punya_timer "$p" && timer_habis "$p" "$now"; then
        restart_cepat "$p"
        tulis "[$(date +%T)] Timer: $p keluar-masuk (${JEDA_MS} ms)"
        TIMER_JADWAL[$p]=0
        TIMER_MENIT[$p]=0
        pesan_timer "$p" "$JEDA_MS"
        PERNAH_MAP[$p]=0
        KELUAR_CNT[$p]=0
      fi
    done

    # --- rejoin & catat map terakhir: dicek tiap 10 detik ---
    if [ $((now - last)) -ge 10 ]; then
      last=$now

      if [ "$rejoin" = "1" ]; then
        for p in "${PAKET[@]}"; do
          n="${p#com.roblox.}"
          if periksa_map "$p"; then
            if [ "$ST_DALAM" = "1" ]; then
              if [ "${PERNAH_MAP[$p]:-0}" != "1" ] || [ "${KELUAR_CNT[$p]:-0}" -ne 0 ]; then
                tulis "[$(date +%T)] $n: di dalam map"
              fi
              PERNAH_MAP[$p]=1
              KELUAR_CNT[$p]=0
              if [ -z "$PLACE_URL" ] && [ $((now - lastmap)) -ge 30 ]; then deteksi_map "$p"; fi
            elif [ "$ST_DALAM" = "0" ] && [ "${PERNAH_MAP[$p]:-0}" = "1" ]; then
              KELUAR_CNT[$p]=$(( ${KELUAR_CNT[$p]:-0} + 1 ))
              if [ "${KELUAR_CNT[$p]}" -gt 0 ]; then
                tulis "[$(date +%T)] $n: tidak di map (${KELUAR_CNT[$p]}/3)"
              fi
              if [ "${KELUAR_CNT[$p]}" -ge 3 ]; then rejoin_map "$p"; fi
            fi
          else
            # aplikasi mati (FC): kasih waktu 60 detik setelah peluncuran sebelum dianggap mati
            if [ $((now - ${MULAI[$p]:-0})) -ge 60 ]; then
              tulis "[$(date +%T)] $n mati -> diluncurkan ulang"
              pesan_fc "$p" "aplikasi tertutup (FC)"
              buka "$p" rejoin
              PERNAH_MAP[$p]=1
              KELUAR_CNT[$p]=-9
              jeda
            fi
          fi
        done
      fi
      if [ $((now - lastmap)) -ge 30 ]; then lastmap=$now; fi

      # mode tanpa rejoin: berhenti kalau semua timer sudah habis
      if [ "$rejoin" = "0" ]; then
        sisa=0
        for p in "${PAKET[@]}"; do
          if punya_timer "$p"; then sisa=1; fi
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
  tulis "Masukkan Place ID atau link private server."
  tulis "Kosongkan lalu Enter = Roblox hanya dibuka (tidak langsung masuk map). Kalau nanti keluar map atau FC, otomatis masuk lagi ke map terakhir."
  tulis "Contoh: 920587237"
  echo
  read -r -p "Place ID / link: " INPUT
  MAP_HASIL=""
  if [ -z "$INPUT" ]; then return 0; fi

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
    tulis "Saat waktunya tiba, Roblox keluar lalu masuk lagi (jeda sekitar 1 detik)."
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

menu_info() {
  local p
  header
  echo "CEK PERANGKAT"
  echo
  echo "Android : $(rt "getprop ro.build.version.release" 2>/dev/null | tr -d '\r')"
  echo "DPI     : $(rt "wm density" 2>/dev/null | grep -oE '[0-9]+' | tail -n1)"
  if rt "id" 2>/dev/null | grep -q 'uid=0'; then echo "Root    : ya"; else echo "Root    : tidak"; fi
  echo
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
  else
    for p in "${PAKET[@]}"; do
      echo "$p"
      if sedang_jalan "$p"; then echo "  status: berjalan"; else echo "  status: tidak berjalan"; fi
      deteksi_map "$p"
      echo "  map terakhir: ${LAST_MAP[$p]:-tidak terbaca}"
    done
    echo
    tulis "Map terakhir dibaca saat akun sedang berada di dalam map."
  fi
  tunggu_enter
}

# lihat status tiap Roblox secara langsung (untuk memastikan deteksi map bekerja)
tes_status() {
  local p n st
  header
  cari_roblox
  if [ ${#PAKET[@]} -eq 0 ]; then
    tulis "Tidak ada Roblox (com.roblox) yang terdeteksi."
    tunggu_enter
    return
  fi
  STOP=0
  tulis "TES STATUS MAP (CTRL+C untuk berhenti)"
  tulis "Masuk map, lalu keluar map di salah satu Roblox. Perhatikan status berubah."
  echo
  while [ "$STOP" = "0" ]; do
    echo "$(date +%T)"
    for p in "${PAKET[@]}"; do
      n="${p#com.roblox.}"
      if periksa_map "$p"; then
        if [ "$ST_DALAM" = "1" ]; then st="DI MAP"; elif [ "$ST_DALAM" = "0" ]; then st="BERANDA"; else st="?"; fi
        echo " $n cpu ${ST_CPU:--}% udp ${ST_UDP} = $st"
      else
        echo " $n mati"
      fi
    done
    echo
    sleep 3
  done
  fix_tty
  echo "Dihentikan."
  tunggu_enter
}

# ---------- Program utama ----------
cek_key
atur_webhook

while true; do
  cek_masa_aktif
  header
  if [ -n "$WEBHOOK" ]; then echo "Webhook : aktif"; else echo "Webhook : tidak dipakai"; fi
  echo "Delay   : ${DELAY_DETIK} detik"
  echo
  echo "1. AUTO LAUNCH"
  echo "2. AUTO LAUNCH + RE JOIN"
  echo "3. TIMER"
  echo "4. ATUR DELAY"
  echo "5. TUTUP SEMUA ROBLOX"
  echo "6. CEK PERANGKAT"
  echo "7. TES STATUS MAP"
  echo "8. KELUAR"
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
        PLACE_URL="$MAP_HASIL"
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
    5) tutup_semua ;;
    6) menu_info ;;
    7) tes_status ;;
    8)
      echo "Sampai jumpa!"
      exit 0
      ;;
    *)
      echo "Pilihan tidak ada."
      sleep 1
      ;;
  esac
done
