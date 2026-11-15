import time
import os
import requests
import subprocess

PACKAGE_NAME = "com.roblox"
DELAY_BETWEEN_LAUNCH = 5
AUTO_REJOIN_ENABLED = True
WEBHOOK_ENABLED = True
WEBHOOK_URL = "URL_DISCORD_WEBHOOK_KAMU"
TIMER_LEAVE_MENIT = 60

def send_discord_webhook(message):
    if not WEBHOOK_ENABLED or not WEBHOOK_URL or WEBHOOK_URL == "URL_DISCORD_WEBHOOK_KAMU":
        return
    try:
        payload = {"content": f"🤖 **[VP Launcher Bot]**\n{message}"}
        requests.post(WEBHOOK_URL, json=payload, timeout=5)
    except Exception as e:
        print(f"[!] Gagal mengirim webhook: {e}")

def is_roblox_running():
    try:
        result = subprocess.run(["pidof", PACKAGE_NAME], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return len(result.stdout.strip()) > 0
    except:
        return False

def launch_roblox():
    print(f"[*] Membuka aplikasi {PACKAGE_NAME}...")
    os.system(f"monkey -p {PACKAGE_NAME} -c android.intent.category.LAUNCHER 1")

def force_stop_roblox():
    print(f"[*] Menghentikan paksa {PACKAGE_NAME}...")
    os.system(f"am force-stop {PACKAGE_NAME}")

def main():
    print("=" * 50)
    print("       VP LAUNCHER - AUTOMATION ENGINE       ")
    print("=" * 50)
    
    send_discord_webhook("🚀 **Sistem AFK Dimulai!** Launcher aktif.")
    launch_roblox()
    time.sleep(DELAY_BETWEEN_LAUNCH)
    
    end_time = time.time() + (TIMER_LEAVE_MENIT * 60)
    
    try:
        while True:
            if time.time() >= end_time:
                print("\n[!] Timer Leave habis! Menutup game...")
                force_stop_roblox()
                send_discord_webhook("⏰ **Timer Leave Tercapai:** Game ditutup otomatis.")
                break
            
            if AUTO_REJOIN_ENABLED and not is_roblox_running():
                print("\n[!] Roblox Terdeteksi Crash / Force Close!")
                send_discord_webhook("⚠️ **Peringatan Crash:** Roblox tertutup, melakukan Auto-Rejoin...")
                time.sleep(3)
                launch_roblox()
                time.sleep(5)
            
            time.sleep(10)
    except KeyboardInterrupt:
        print("\n[!] Dihentikan manual.")

if __name__ == "__main__":
    main()
    
