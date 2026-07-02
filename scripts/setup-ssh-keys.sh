#!/usr/bin/env bash
# =============================================================================
# สคริปต์แจกจ่าย SSH Keys ไปยังเครื่องเป้าหมาย (SSH Key Setup Script)
# =============================================================================
# ใช้รันบน Control Node เพื่อ:
#   1. สร้าง SSH Key Pair (Ed25519) หากยังไม่มี
#   2. ก๊อปปี้ Public Key ไปยัง Host ต่างๆ ใน Home Lab
#
# วิธีการรัน:
#   chmod +x scripts/setup-ssh-keys.sh
#   ./scripts/setup-ssh-keys.sh backup@192.168.1.10 backup@192.168.1.20
# =============================================================================
set -euo pipefail

# สีสำหรับจัดรูปแบบ Output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

KEY_PATH="$HOME/.ssh/id_ed25519"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# -------------------------------------------------------------
# 1. ตรวจสอบหรือสร้าง SSH Key
# -------------------------------------------------------------
if [ ! -f "$KEY_PATH" ]; then
    log_info "ไม่พบ SSH Key เดิม กำลังสร้าง SSH Key (Ed25519)..."
    # -t ed25519: กำหนดประเภทคีย์
    # -N "": ไม่ใส่ passphrase เพื่อให้ Ansible เชื่อมต่อโดยไม่ติดรหัสผ่าน
    ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -C "ansible-control-node"
    log_info "สร้าง SSH Key สำเร็จ ณ $KEY_PATH"
else
    log_info "พบ SSH Key เดิมอยู่แล้ว ณ $KEY_PATH (ไม่ต้องสร้างใหม่)"
fi

# -------------------------------------------------------------
# 2. คัดลอก Public Key ไปยังเครื่องปลายทาง (Target Hosts)
# -------------------------------------------------------------
if [ $# -eq 0 ]; then
    log_error "กรุณาระบุเครื่องปลายทางที่ต้องการติดตั้ง SSH Key!"
    echo "การใช้งาน: $0 [user@host1] [user@host2] ..."
    echo "ตัวอย่าง:  $0 backup@192.168.1.10 backup@192.168.1.20"
    exit 1
fi

log_info "กำลังเตรียมคัดลอก Public Key ไปยังเครื่องปลายทางจำนวน $# เครื่อง..."

for HOST in "$@"; do
    log_info "--------------------------------------------------------"
    log_info "กำลังส่ง Key ไปที่: $HOST"
    
    # ใช้ ssh-copy-id ในการก๊อปปี้คีย์อย่างปลอดภัย
    # มันจะตรวจสอบสิทธิ์และเพิ่มคีย์ใน ~/.ssh/authorized_keys ของเครื่องเป้าหมาย
    if ssh-copy-id -i "${KEY_PATH}.pub" "$HOST"; then
        log_info "ส่งคีย์สำเร็จสำหรับเครื่อง: $HOST"
        
        # ทดสอบการเชื่อมต่อแบบไร้รหัสผ่าน
        log_info "ทดสอบการเชื่อมต่อแบบไม่ระบุรหัสผ่าน..."
        if ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "echo 'SUCCESS'" &>/dev/null; then
            log_info "${GREEN}ทดสอบการเชื่อมต่อไร้รหัสผ่านสำเร็จ!${NC}"
        else
            log_error "เชื่อมต่อไม่ได้อย่างสมบูรณ์แบบ กรุณาตรวจสอบสิทธิ์"
        fi
    else
        log_error "การคัดลอกคีย์ไปยัง $HOST ล้มเหลว! (กรุณาเช็ค IP หรือ User/Password)"
    fi
done

log_info "========================================================"
log_info "กระบวนการติดตั้ง SSH Key เสร็จสิ้น"
