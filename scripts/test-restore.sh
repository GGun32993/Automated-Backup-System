#!/usr/bin/env bash
# =============================================================================
# สคริปต์สแตนด์อโลนสำหรับทดสอบ Restore (Standalone Restore Verification)
# =============================================================================
# ใช้รันบนเครื่องเป้าหมายเพื่อทดสอบความถูกต้องของข้อมูลสำรองโดยไม่ต้องผ่าน Ansible
#
# การรันสคริปต์:
#   sudo ./scripts/test-restore.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ENV_FILE="/etc/restic/restic.env"
RESTORE_TEMP_DIR="/opt/backup/restore-test-temp-standalone"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# ตรวจสอบการรันในฐานะ root (จำเป็นสำหรับอ่าน env file และจัดการ directory พิเศษ)
if [ "$EUID" -ne 0 ]; then
   log_error "กรุณารันสคริปต์นี้ด้วยสิทธิ์ root (sudo)"
   exit 1
fi

# -------------------------------------------------------------
# 1. โหลดการตั้งค่า Restic
# -------------------------------------------------------------
if [ ! -f "$ENV_FILE" ]; then
    log_error "ไม่พบไฟล์คอนฟิก $ENV_FILE"
    exit 1
fi

# shellcheck disable=SC1090
source "$ENV_FILE"

# -------------------------------------------------------------
# 2. เตรียมไดเรกทอรีทดสอบ
# -------------------------------------------------------------
log_info "กำลังสร้างโฟลเดอร์สำหรับกู้คืนข้อมูลทดสอบ: $RESTORE_TEMP_DIR"
rm -rf "$RESTORE_TEMP_DIR"
mkdir -p "$RESTORE_TEMP_DIR"

# ฟังก์ชันทำความสะอาดเมื่อรันเสร็จ หรือเกิดข้อผิดพลาด
cleanup() {
    log_info "กำลังล้างโฟลเดอร์ทดสอบ..."
    rm -rf "$RESTORE_TEMP_DIR"
    log_info "ล้างโฟลเดอร์สำเร็จ"
}
# เมื่อสคริปต์จบลง (EXIT) หรือเกิดการขัดจังหวะ (INT, TERM) จะรันฟังก์ชัน cleanup อัตโนมัติ
trap cleanup EXIT

# -------------------------------------------------------------
# 3. ดำเนินการกู้คืนข้อมูลล่าสุด (Latest Snapshot)
# -------------------------------------------------------------
log_info "กำลังเชื่อมต่อกับ Google Drive และสั่ง Restic ดำเนินการดึงไฟล์สำรองล่าสุด..."
if restic --option rclone.program=rclone --option rclone.args="config disconnect" restore latest --target "$RESTORE_TEMP_DIR"; then
    log_info "${GREEN}ดึงไฟล์สำรองลงเครื่องเสร็จสมบูรณ์${NC}"
else
    log_error "การดึงข้อมูลจาก Google Drive ล้มเหลว!"
    exit 1
fi

# -------------------------------------------------------------
# 4. ตรวจสอบความถูกต้องของข้อมูล (Verification)
# -------------------------------------------------------------
log_info "เริ่มต้นตรวจสอบความถูกต้องของโครงสร้างไฟล์..."
TEST_PASSED=true

# ค้นหาไฟล์ database dump
log_info "ตรวจสอบไฟล์ Database Dump..."
DB_FILES=$(find "$RESTORE_TEMP_DIR" -name "*.dump" -o -name "*.sqlite" | wc -l)
if [ "$DB_FILES" -gt 0 ]; then
    log_info "-> PASS: พบไฟล์ Database Dump จำนวน $DB_FILES ไฟล์"
else
    log_error "-> FAIL: ไม่พบไฟล์ Database Dump ใน Snapshot ล่าสุด!"
    TEST_PASSED=false
fi

# ค้นหาไฟล์ docker-compose.yml
log_info "ตรวจสอบไฟล์ docker-compose.yml..."
COMPOSE_FILES=$(find "$RESTORE_TEMP_DIR" -name "docker-compose.yml" | wc -l)
if [ "$COMPOSE_FILES" -gt 0 ]; then
    log_info "-> PASS: พบไฟล์ docker-compose.yml จำนวน $COMPOSE_FILES ไฟล์"
else
    log_error "-> FAIL: ไม่พบไฟล์ docker-compose.yml ใน Snapshot ล่าสุด!"
    TEST_PASSED=false
fi

# สรุปผล
echo "========================================================"
if [ "$TEST_PASSED" = true ]; then
    echo -e "${GREEN}>>> ผลการทดสอบ: ผ่านการตรวจสอบ (PASS) <<<${NC}"
    echo "ข้อมูลสำรองบน Google Drive อยู่ในสภาพดีและพร้อมใช้งาน"
    exit 0
else
    echo -e "${RED}>>> ผลการทดสอบ: ล้มเหลว (FAIL) <<<${NC}"
    echo "พบว่าข้อมูลสำรองขาดหาย โปรดทำการตรวจสอบสคริปต์ backup และ log การรัน"
    exit 1
fi
