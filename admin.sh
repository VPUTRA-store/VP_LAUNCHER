#!/data/data/com.termux/files/usr/bin/bash
# =====================================================
#  VP LAUNCHER - MENU ADMIN
#  Jalankan di HP utama kamu. JANGAN dibagikan ke buyer
#  dan JANGAN diupload ke GitHub.
#
#  Butuh: curl  (pkg install curl -y)
# =====================================================

DIR="$HOME/vp-admin"
DB="$DIR/keys.db"        # satu baris per key: key|hash|hari|dibuat|catatan|status
CFG="$DIR/config"        # pengaturan (berisi token, hanya ada di HP ini)

GH_USER="VPUTRA-store"
GH_REPO="VP_LAUNCHER"
GH_BRANCH="main"
GH_FILE="keys.txt"
GH_TOKEN=""
DB_URL=""                # alamat database Firebase pencatat pemakaian

mkdir -p "$DIR"
chmod 700 "$DIR" 2>/dev/null
touch "$DB"

# shellcheck disable=SC1090
[ -f "$CFG" ] && source "$CFG"

# ---------- Tampilan (menyesuaikan lebar layar) ----------
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
  printf '%s\n' "$1" | fold -s -w "$(($(lebar) - 1))"
}

header() {
  clear
  garis
  echo "VP LAUNCHER - ADMIN"
  garis
  echo
}

tunggu_enter() {
  echo
  read -r -p "Enter = kembali: " _
}

tgl() {   # epoch -> tanggal & jam
  date -d "@$1" '+%d/%m/%Y %H:%M' 2>/dev/null
}

# ---------- Pengaturan ----------
simpan_config() {
  {
    printf 'GH_USER=%q\n' "$GH_USER"
    printf 'GH_REPO=%q\n' "$GH_REPO"
    printf 'GH_BRANCH=%q\n' "$GH_BRANCH"
    printf 'GH_FILE=%q\n' "$GH_FILE"
    printf 'GH_TOKEN=%q\n' "$GH_TOKEN"
    printf 'DB_URL=%q\n' "$DB_URL"
  } > "$CFG"
  chmod 600 "$CFG" 2>/dev/null
}

valid_db_url() {
  [[ "$1" =~ ^https://[A-Za-z0-9.-]+\.(firebaseio\.com|firebasedatabase\.app)$ ]]
}

atur_github() {
  local x code lama="$DB_URL"
  header
  tulis "PENGATURAN (sekali saja)"
  tulis "Token GitHub dipakai supaya key baru langsung terkirim tanpa upload manual. Token hanya disimpan di HP ini."
  echo
  read -r -p "Username GitHub [$GH_USER]: " x
  [ -n "$x" ] && GH_USER="$x"
  read -r -p "Nama repo [$GH_REPO]: " x
  [ -n "$x" ] && GH_REPO="$x"
  echo
  tulis "Tempel token GitHub (tidak tampak saat diketik, Enter = tidak diubah):"
  read -r -s -p "Token: " x
  echo
  [ -n "$x" ] && GH_TOKEN="$x"

  echo
  tulis "Alamat database Firebase untuk mencatat pemakaian key (Enter = tidak diubah):"
  read -r -p "URL: " x
  x="${x%/}"
  if [ -n "$x" ]; then
    if valid_db_url "$x"; then
      DB_URL="$x"
    else
      tulis "Format tidak dikenali (contoh: https://nama-default-rtdb.firebaseio.com). URL tidak diubah."
    fi
  fi
  simpan_config

  echo
  if [ -n "$GH_TOKEN" ]; then
    echo "Mengetes GitHub..."
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 \
      -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/$GH_USER/$GH_REPO")
    if [ "$code" = "200" ]; then
      echo "GitHub: terhubung ke $GH_USER/$GH_REPO"
    elif [ "$code" = "401" ] || [ "$code" = "403" ]; then
      tulis "GitHub: token ditolak. Pastikan token benar dan punya izin Contents (baca & tulis) untuk repo ini."
    elif [ "$code" = "404" ]; then
      tulis "GitHub: repo tidak ditemukan atau token tidak punya akses. Cek username dan nama repo."
    else
      tulis "GitHub: gagal terhubung (kode: ${code:-kosong}). Cek internet kamu."
    fi
  else
    tulis "Token kosong. Key tetap bisa dibuat, tapi harus ditempel manual ke keys.txt di GitHub."
  fi

  if [ -n "$DB_URL" ]; then
    echo "Mengetes database..."
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$DB_URL/pakai.json?shallow=true" </dev/null)
    if [ "$code" = "200" ]; then
      echo "Database: terhubung"
    elif [ "$code" = "401" ]; then
      tulis "Database: ditolak. Periksa bagian Rules di Firebase sudah dipasang dan dipublikasikan."
    else
      tulis "Database: gagal terhubung (kode: ${code:-kosong}). Cek URL-nya."
    fi
  fi

  if [ -n "$GH_TOKEN" ] && [ "$DB_URL" != "$lama" ]; then
    echo
    sinkron
  fi
  tunggu_enter
}

# ---------- Kirim keys.txt ke GitHub ----------
isi_keys_txt() {
  local isi
  if [ -n "$DB_URL" ]; then echo "#db=$DB_URL"; fi
  isi=$(awk -F'|' 'NF >= 3 { s = ($6 == "B") ? "|B" : ""; print $2 "|" $3 s }' "$DB")
  if [ -z "$isi" ]; then isi="# belum ada key"; fi
  printf '%s\n' "$isi"
}

kirim_ke_github() {
  local api b64 sha body code
  if [ -z "$GH_TOKEN" ]; then return 1; fi

  b64=$(isi_keys_txt | base64 | tr -d '\n')
  api="https://api.github.com/repos/$GH_USER/$GH_REPO/contents/$GH_FILE"

  sha=$(curl -s --max-time 20 -H "Authorization: Bearer $GH_TOKEN" \
    -H "Accept: application/vnd.github+json" "$api?ref=$GH_BRANCH" \
    | grep -m1 '"sha"' | cut -d'"' -f4)

  body="{\"message\":\"update keys\",\"content\":\"$b64\",\"branch\":\"$GH_BRANCH\""
  if [ -n "$sha" ]; then body="$body,\"sha\":\"$sha\""; fi
  body="$body}"

  code=$(curl -s --max-time 30 -o "$DIR/resp.json" -w '%{http_code}' -X PUT \
    -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
    -d "$body" "$api")
  [ "$code" = "200" ] || [ "$code" = "201" ]
}

sinkron() {
  echo "Mengirim ke GitHub..."
  if kirim_ke_github; then
    echo "Berhasil terkirim. Berlaku untuk buyer dalam beberapa menit."
    return 0
  fi
  if [ -z "$GH_TOKEN" ]; then
    tulis "Token belum diatur, jadi belum terkirim. Tempel isi berikut ke keys.txt di GitHub (ganti seluruh isinya):"
  else
    tulis "Gagal terkirim ke GitHub. Perubahan tetap tersimpan di HP ini dan akan ikut terkirim saat kamu mengubah key berikutnya. Atau tempel manual isi berikut ke keys.txt:"
  fi
  echo
  isi_keys_txt
  return 1
}

# ---------- Key ----------
buat_key() {
  local a b c
  a=$(tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 4)
  b=$(tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 4)
  c=$(tr -dc 'A-HJ-NP-Z2-9' </dev/urandom | head -c 4)
  echo "VP-$a-$b-$c"
}

tambah_key() {
  local hari catatan key hash
  header
  echo "1. TAMBAH KEY"
  echo
  read -r -p "Masa aktif (hari): " hari
  if ! [[ "$hari" =~ ^[0-9]+$ ]] || [ "$hari" -lt 1 ] || [ "$hari" -gt 3650 ]; then
    echo "Harus angka 1 sampai 3650."
    tunggu_enter
    return
  fi
  read -r -p "Nama buyer (opsional): " catatan
  catatan="${catatan//|//}"

  key=$(buat_key)
  while grep -q "^$key|" "$DB"; do key=$(buat_key); done
  hash=$(printf '%s' "$key" | sha256sum | cut -d' ' -f1)
  echo "$key|$hash|$hari|$(date +%s)|$catatan|" >> "$DB"

  echo
  sinkron
  echo
  garis
  echo "KEY BUYER : $key"
  echo "Masa aktif: $hari hari"
  garis
  tulis "Hitungan $hari hari dimulai saat buyer PERTAMA KALI memakai key ini, bukan saat key dibuat."
  tunggu_enter
}

daftar_key() {   # tampilkan daftar bernomor
  local n=0 key hash hari dibuat catatan status tanda
  while IFS='|' read -r key hash hari dibuat catatan status; do
    [ -z "$key" ] && continue
    n=$((n + 1))
    tanda=""
    if [ "$status" = "B" ]; then tanda=" [BLACKLIST]"; fi
    echo "$n. $key$tanda"
    echo "   $hari hari | dibuat $(tgl "$dibuat")"
    if [ -n "$catatan" ]; then echo "   $catatan"; fi
  done < "$DB"
  return 0
}

jumlah_key() {
  grep -c '|' "$DB"
}

nama_key() {   # nomor -> key
  sed -n "${1}p" "$DB" | cut -d'|' -f1
}

hapus_key() {
  local total nomor jawab key
  header
  echo "2. HAPUS KEY"
  echo
  total=$(jumlah_key)
  if [ "$total" -eq 0 ]; then
    echo "Belum ada key."
    tunggu_enter
    return
  fi
  daftar_key
  echo
  read -r -p "Nomor yang dihapus (Enter = batal): " nomor
  if [ -z "$nomor" ]; then return; fi
  if ! [[ "$nomor" =~ ^[0-9]+$ ]] || [ "$nomor" -lt 1 ] || [ "$nomor" -gt "$total" ]; then
    echo "Nomor tidak ada."
    tunggu_enter
    return
  fi
  key=$(nama_key "$nomor")
  read -r -p "Hapus $key? (y/n): " jawab
  if [[ "$jawab" =~ ^[yY]$ ]]; then
    sed -i "${nomor}d" "$DB"
    echo
    sinkron
    echo
    tulis "Key dihapus. Buyer yang sedang memakainya akan keluar dari launcher dalam sekitar 5 menit."
  else
    echo "Dibatalkan."
  fi
  tunggu_enter
}

lihat_key() {
  local total
  header
  echo "3. KEY AKTIF"
  echo
  total=$(jumlah_key)
  if [ "$total" -eq 0 ]; then
    echo "Belum ada key."
  else
    daftar_key
    echo
    echo "Total: $total key"
    echo
    tulis "Catatan: hitungan hari berjalan sejak buyer pertama kali memakai key, jadi sisa waktu tiap key tidak bisa dilihat dari sini."
  fi
  tunggu_enter
}

# ---------- Pemakaian key ----------
# baca catatan pemakaian satu key -> PK_JUMLAH, PK_PERANGKAT, PK_TERAKHIR (epoch detik)
pakai_data() {
  local resp
  PK_JUMLAH=0; PK_PERANGKAT=0; PK_TERAKHIR=0
  resp=$(curl -s -m 15 "$DB_URL/pakai/$1.json" </dev/null) || return 1
  if [ -z "$resp" ] || [ "$resp" = "null" ]; then return 0; fi
  case "$resp" in "{"*) ;; *) return 1 ;; esac
  if printf '%s' "$resp" | grep -q '"error"'; then return 1; fi
  PK_JUMLAH=$(printf '%s' "$resp" | grep -o '"dev":"' | wc -l)
  PK_PERANGKAT=$(printf '%s' "$resp" | grep -oE '"dev":"[^"]*"' | sort -u | wc -l)
  PK_TERAKHIR=$(printf '%s' "$resp" | grep -oE '"t":[0-9]+' | cut -d: -f2 | sort -n | tail -n1)
  PK_TERAKHIR=$((${PK_TERAKHIR:-0} / 1000))
  return 0
}

tampil_pemakaian() {
  local n=0 key hash hari dibuat catatan status tanda peringatan
  while IFS='|' read -r key hash hari dibuat catatan status; do
    [ -z "$key" ] && continue
    n=$((n + 1))
    if [ "$status" = "B" ]; then tanda="BLACKLIST"; else tanda="aktif"; fi
    echo "$n. $key [$tanda]"
    if pakai_data "$hash"; then
      peringatan=""
      if [ "$PK_PERANGKAT" -gt 1 ]; then peringatan=" (!)"; fi
      echo "   dipakai ${PK_JUMLAH}x | ${PK_PERANGKAT} perangkat${peringatan}"
      if [ "$PK_TERAKHIR" -gt 0 ]; then echo "   terakhir $(tgl "$PK_TERAKHIR")"; fi
    else
      echo "   gagal membaca data pemakaian"
    fi
    if [ -n "$catatan" ]; then echo "   $catatan"; fi
  done < "$DB"
  return 0
}

ubah_status() {   # $1 = B (blacklist) atau A (hidupkan)
  local total nomor key
  total=$(jumlah_key)
  read -r -p "Nomor key (Enter = batal): " nomor
  if [ -z "$nomor" ]; then return; fi
  if ! [[ "$nomor" =~ ^[0-9]+$ ]] || [ "$nomor" -lt 1 ] || [ "$nomor" -gt "$total" ]; then
    echo "Nomor tidak ada."
    sleep 2
    return
  fi
  key=$(nama_key "$nomor")
  awk -F'|' -v OFS='|' -v n="$nomor" -v s="$1" \
    'NR == n { if (s == "B") $6 = "B"; else $6 = "" } { print }' "$DB" > "$DB.tmp" \
    && mv "$DB.tmp" "$DB"
  echo
  sinkron
  echo
  if [ "$1" = "B" ]; then
    tulis "$key di-blacklist. Buyer yang sedang memakainya keluar dari launcher dalam sekitar 5 menit dan tidak bisa masuk lagi."
  else
    tulis "$key dihidupkan lagi. Masa aktifnya tetap berjalan sesuai waktu, termasuk selama diblacklist."
  fi
  tunggu_enter
}

cek_pemakaian() {
  local pil total
  if [ -z "$DB_URL" ]; then
    header
    echo "4. CEK PEMAKAIAN KEY"
    echo
    tulis "Database belum diatur. Buka menu G lalu isi URL database Firebase."
    tunggu_enter
    return
  fi
  while true; do
    header
    echo "4. CEK PEMAKAIAN KEY"
    echo
    total=$(jumlah_key)
    if [ "$total" -eq 0 ]; then
      echo "Belum ada key."
      tunggu_enter
      return
    fi
    tampil_pemakaian
    echo
    tulis "(!) = dipakai di lebih dari 1 perangkat. \"dipakai\" = berapa kali buyer masuk ke launcher dengan key itu."
    echo
    echo "B. Blacklist key"
    echo "H. Hidupkan key"
    echo "0. Kembali"
    echo
    read -r -p "Pilih: " pil
    case "$pil" in
      [Bb]) ubah_status B ;;
      [Hh]) ubah_status A ;;
      0) return ;;
    esac
  done
}

# ---------- Program utama ----------
main() {
  local pil
  if [ -z "$GH_TOKEN" ]; then atur_github; fi

  while true; do
    header
    if [ -n "$GH_TOKEN" ]; then echo "GitHub  : $GH_USER/$GH_REPO"; else echo "GitHub  : belum diatur"; fi
    if [ -n "$DB_URL" ]; then echo "Database: terhubung"; else echo "Database: belum diatur"; fi
    echo "Key     : $(jumlah_key)"
    echo
    echo "1. TAMBAH KEY"
    echo "2. HAPUS KEY"
    echo "3. LIHAT KEY AKTIF"
    echo "4. CEK PEMAKAIAN KEY"
    echo "5. KELUAR"
    echo "G. Pengaturan"
    echo
    read -r -p "Pilih: " pil
    case "$pil" in
      1) tambah_key ;;
      2) hapus_key ;;
      3) lihat_key ;;
      4) cek_pemakaian ;;
      5)
        echo "Sampai jumpa!"
        exit 0
        ;;
      [Gg]) atur_github ;;
      *)
        echo "Pilihan tidak ada."
        sleep 1
        ;;
    esac
  done
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main
fi
