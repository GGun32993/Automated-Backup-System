#!/usr/bin/env bash
# =============================================================================
# สคริปต์สำหรับเริ่มสร้าง Restic Repository บน Google Drive
# =============================================================================
# ใช้รันบนเครื่องเป้าหมายเพื่อสร้างพื้นที่เก็บข้อมูลในครั้งแรก
#
# การรันสคริปต์:
#   chmod +x scripts/init-restic-repo.sh
#   ./scripts/init-restic-repo.sh
# =============================================================================
set -euo pipefail

# สีสำหรับแสดงสถานะ
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ENV_FILE="/etc/restic/restic.env"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# -------------------------------------------------------------
# 1. ตรวจสอบหาไฟล์ Environment
# -------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
    log_error "ไม่พบไฟล์ตั้งค่าตัวแปร $ENV_FILE"
    log_error "กรุณารัน Ansible Playbook: setup.yml ก่อนเพื่อสร้างไฟล์นี้"
    exit 1
fi

# โหลดตัวแปร
# shellcheck disable=SC1090
source "$ENV_FILE"

log_info "ตรวจสอบการตั้งค่าเรียบร้อยแล้ว"
log_info "Repository: $RESTIC_REPOSITORY"

# -------------------------------------------------------------
# 2. ตรวจสอบการตั้งค่า Rclone
# -------------------------------------------------------------
if ! command -v rclone &> /dev/null; then
    log_error "ตรวจไม่พบโปรแกรม rclone กรุณาติดตั้ง rclone ก่อนรันสคริปต์"
    exit 1
fi

log_info "กำลังตรวจสอบการเชื่อมต่อไปยัง Google Drive..."
if rclone --config "$RCLONE_CONFIG" ls gdrive: &>/dev/null; then
    log_info "การเชื่อมต่อ Google Drive สมบูรณ์ (rclone OK)"
else
    log_error "ไม่สามารถเชื่อมต่อ Google Drive ผ่าน rclone ได้!"
    log_error "กรุณาตั้งค่า rclone.conf ให้ถูกต้องด้วย rclone config"
    exit 1
fi

# -------------------------------------------------------------
# 3. เริ่มสร้าง Repository
# -------------------------------------------------------------
log_info "กำลังตรวจสอบว่า Restic Repository เคยสร้างไว้แล้วหรือไม่..."

# คำสั่งตรวจสอบ
if restic --option rclone.program=rclone --option rclone.args="config disconnect" check &>/dev/null; then
    log_info "Restic Repository เคยสร้างไว้เรียบร้อยแล้ว ไม่จำเป็นต้องสร้างใหม่"
    exit 0
else
    log_info "ไม่พบ Restic Repository เริ่มทำการสร้าง (Initialize) ใหม่บน Google Drive..."
    
    if restic --option rclone.program=rclone --option rclone.args="config disconnect" init; then
        log_info "--------------------------------------------------------"
        log_info "${GREEN}สร้าง Restic Repository บน Google Drive สำเร็จ!${NC}"
        log_info "--------------------------------------------------------"
        log_info "คุณสามารถใช้คำสั่ง 'restic snapshots' เพื่อเช็คดูข้อมูลสำรองได้ในอนาคต"
    else
        log_error "การสร้าง Restic Repository ล้มเหลว!"
        exit 1
    fi
fi
