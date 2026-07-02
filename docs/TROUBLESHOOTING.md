# 🔍 คู่มือแก้ไขปัญหาเบื้องต้น (Troubleshooting Guide)

รวบรวมอาการผิดพลาด (Symptoms) สาเหตุ (Causes) และวิธีการแก้ไข (Solutions) ของระบบสำรองข้อมูลใน Home Lab

---

## 1. อาการ: Restic ฟ้องว่า "repository is locked"

### อาการ (Symptom):
คำสั่ง restic แจ้งเตือนข้อผิดพลาด:
```text
unable to create lock in backend: repository is already locked by PID xxxx
```

### สาเหตุ (Cause):
Restic มีกลไกป้องกันการเขียนทับพร้อมกันโดยการล็อค repository ไว้ หากกระบวนการก่อนหน้านี้หยุดทำงานกะทันหัน (เช่น เครื่องดับกลางคัน, เน็ตหลุดชั่วคราว หรือโดน kill process) Restic จะไม่ได้เคลียร์ล็อคออก

### วิธีแก้ไข (Solution):
รันคำสั่งเคลียร์ตัวล็อคด้วยตนเอง:
```bash
# โหลดตัวแปรสภาพแวดล้อมก่อน
source /etc/restic/restic.env

# สั่งปลดล็อค Repository
restic --option rclone.program=rclone --option rclone.args="config disconnect" unlock
```

---

## 2. อาการ: Rclone แจ้งความล้มเหลวในการส่งข้อมูลไป Google Drive

### อาการ (Symptom):
ใน log ไฟล์ขึ้นแจ้งเตือน:
```text
Failed to configure token: oauth2: cannot fetch token: 400 Bad Request
```
หรือการทำงานจำกัดอยู่ที่หน้าเว็บและหยุดนิ่ง

### สาเหตุ (Cause):
1. OAuth Refresh Token หมดอายุ (โดยปกติแอปในสถานะ "Testing" ที่ไม่ได้รับการยืนยันจาก Google จะมีอายุ Token เพียง 7 วัน)
2. วันและเวลาของเครื่องโฮสต์คลาดเคลื่อนมากเกินไป (Time desynchronization)

### วิธีแก้ไข (Solution):
1. **แก้ปัญหา Token หมดอายุ**:
   - ไปที่ Google Cloud Console แก้ไขสถานะ Publishing Status ของโปรเจกต์จาก **Testing** เป็น **In Production** (ถึงแม้จะไม่ส่งแอปให้กูเกิลรีวิว แต่จะทำให้อายุ token ไม่มีวันหมดอายุสำหรับเจ้าของโปรเจกต์)
   - เข้าไปรัน `rclone config reconnect gdrive:` บนเครื่องโฮสต์เพื่อรับ OAuth Token ใหม่
   - นำ token ตัวใหม่ไปอัปเดตลงใน Ansible Vault `secrets.yml`
2. **แก้ไขเรื่องเวลา**:
   ติดตั้งและอัปเดต ntp daemon เพื่อซิงค์เวลากับ pool server:
   ```bash
   sudo apt install -y chrony
   sudo systemctl restart chrony
   ```

---

## 3. อาการ: SSH connection refused หรือ SSH key ใช้ไม่ได้

### อาการ (Symptom):
Control Node แจ้งข้อผิดพลาด `UNREACHABLE!` หรือ `Permission denied (publickey)`

### สาเหตุ (Cause):
1. ตัวแปร port, IP หรือ username ใน `hosts.yml` ไม่ตรงกับความจริง
2. สิทธิ์ในการเข้าถึงโฟลเดอร์ SSH ของโฮสต์ปลายทางกว้างเกินไป (SSH Daemon จะปฏิเสธการใช้คีย์หากสิทธิ์โฟลเดอร์ไม่ปลอดภัย)

### วิธีแก้ไข (Solution):
1. ตรวจสอบรายละเอียดโฮสต์และพอร์ต SSH ใน [hosts.yml](file:///C:/Users/User/.gemini/antigravity/scratch/automated-backup-system/inventory/hosts.yml)
2. ล็อกอินเข้าไปที่เครื่องเป้าหมายและแก้ไข permission ของโฟลเดอร์และไฟล์ SSH ให้เข้มงวด:
   ```bash
   chmod 700 ~/.ssh
   chmod 600 ~/.ssh/authorized_keys
   ```

---

## 4. อาการ: Database Dump มีขนาดเป็น 0 Bytes หรือรันล้มเหลว

### อาการ (Symptom):
ตรวจสอบไฟล์ใน `/opt/backup/tmp/db-dumps/` แล้วพบไฟล์ขนาด 0 bytes หรือไม่มีไฟล์ใหม่เกิดขึ้น

### สาเหตุ (Cause):
1. รหัสผ่านฐานข้อมูลที่กรอกใน Ansible Vault ไม่ถูกต้อง ทำให้ `pg_dump` เชื่อมต่อไม่ได้
2. โปรแกรม `pg_dump` หรือ `sqlite3` ไม่ได้ติดตั้งอยู่บนเครื่องโฮสต์
3. สิทธิ์การเข้าถึงโฟลเดอร์เก็บข้อมูล SQLite ผิดพลาด

### วิธีแก้ไข (Solution):
1. ตรวจสอบรหัสผ่านฐานข้อมูลใน `vault/secrets.yml`
2. ตรวจสอบ log การดัมพ์ที่เครื่องโฮสต์เป้าหมาย:
   ```bash
   cat /var/log/backup/db-backup.log
   ```
3. มั่นใจว่าได้ลงทะเบียน cli ของฐานข้อมูลไว้ในเครื่องเป้าหมายแล้ว (role `common` จะช่วยตรวจสอบเบื้องต้นให้)

---

## 5. อาการ: Cron Job ไม่รันตามเวลากำหนด (02:00)

### อาการ (Symptom):
ข้อมูลไม่มีการอัปเดตบน Google Drive และไม่มีแจ้งเตือนใน Discord ตอนเช้า

### สาเหตุ (Cause):
1. Cron service บนเครื่องปลายทางไม่ได้เริ่มทำงาน
2. ตัวแปร PATH ใน cron ไม่ครอบคลุมคำสั่ง rclone/restic
3. สิทธิ์ของตัวไฟล์สคริปต์ `/usr/local/bin/backup-wrapper.sh` รันไม่ได้

### วิธีแก้ไข (Solution):
1. ตรวจสอบสิทธิ์ของไฟล์สคริปต์ว่ารันได้ (ต้องมีสิทธิ์ execute `+x`):
   ```bash
   ls -la /usr/local/bin/backup-wrapper.sh
   # ควรเป็นสิทธิ์ rwxr-xr-x หรือ rwxr-x---
   ```
2. ตรวจสอบว่า cron service ทำงานอยู่:
   ```bash
   sudo systemctl status cron
   ```
3. ตรวจสอบ log ของ cron ระบบว่ามีการรันจริงตามรอบเวลาหรือไม่:
   ```bash
   grep "restic-backup" /var/log/syslog
   ```
