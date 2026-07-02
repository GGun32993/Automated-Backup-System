# 🧪 คู่มือการทดสอบระบบก่อนใช้งานจริง (Testing Guide)

การสำรองข้อมูลที่ดีจะไม่มีประโยชน์เลยหากคุณไม่แน่ใจว่ามันสามารถ "กู้คืนได้จริง" คู่มือนี้อธิบายวิธีตรวจสอบความถูกต้อง ความทนทาน และระบบความปลอดภัยของระบบ backup ทั้งหมดใน Home Lab ของคุณ

---

## 1. การทำ Unit Test รายย่อย (Component Verification)

ก่อนประกอบร่างเป็นงานรันระบบจริง แนะนำให้ตรวจสอบฟังก์ชันแยกส่วนดังต่อไปนี้:

### ก. ทดสอบการเชื่อมต่อ SSH
จากเครื่อง Control Node ไปยังเป้าหมาย:
```bash
ansible all -m ping -i inventory/hosts.yml
```
*(ต้องแสดงผลเป็น "pong" สีเขียวหรือเหลืองทั้งหมด ห้ามมีสีแดง)*

### ข. ทดสอบการจำลอง Dump Database
ล็อกอินเข้าโฮสต์ที่มี database (เช่น Docker Host) แล้วสั่งรันสคริปต์จำลอง dump:
```bash
sudo /opt/backup/tmp/db-dumps/dump-app_db.sh
```
ตรวจสอบ:
- มีไฟล์ดัมพ์ถูกสร้างที่ `/opt/backup/tmp/db-dumps/`
- ตรวจสอบขนาดไฟล์ไม่ใช่ 0 byte
- ตรวจสอบประวัติบันทึกใน `/var/log/backup/db-backup.log`

### ค. ทดสอบการยิง Discord Webhook ทันที
ทดสอบยิง API เพื่อเช็คว่าบอทมีสิทธิ์และแสดงผลสวยงาม:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/backup.yml --tags notification --ask-vault-pass
```

---

## 2. การสั่ง Dry-Run ด้วย Ansible Check Mode

เราสามารถตรวจสอบหาความผิดพลาดทาง syntax หรือสิทธิ์การทำงานของ role ก่อนการแก้ไขค่าจริงในระบบโฮสต์ โดยใช้ `--check` ร่วมกับ `--diff`:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --check --diff --ask-vault-pass
```
*ตัวเลือกนี้จะแสดงการจำลองการเปลี่ยนแปลงทั้งหมดโดยไม่บันทึกหรือเขียนทับข้อมูลจริง*

---

## 3. การกู้คืนข้อมูลแบบสมบูรณ์และอัตโนมัติ (Disaster Recovery Test)

ระบบนี้มี playbook ที่ออกแบบมาเพื่อตรวจสอบสิทธิ์การกู้คืนโดยอัตโนมัติ คือ `playbooks/test-restore.yml`

### ขั้นตอนการรันจาก Control Node:
```bash
ansible-playbook -i inventory/hosts.yml playbooks/test-restore.yml --ask-vault-pass
```

### การทำสแตนด์อโลนเทสบนเครื่องโฮสต์ (ไม่ต้องรันผ่าน Ansible Control Node):
ใช้สคริปต์สแตนด์อโลนในการทดสอบกู้คืนแบบด่วน:
```bash
sudo /opt/backup/scripts/test-restore.sh
```

**สิ่งที่สคริปต์ทดสอบทำ:**
1. ตรวจสอบสภาพแวดล้อม และเชื่อมต่อไปดึง Snapshot ล่าสุดใน Google Drive
2. ดึงไฟล์ออกมาวางที่ `/opt/backup/restore-test-temp-standalone`
3. ทำการหาเช็คความสมบูรณ์ไฟล์ (Database dumps และ compose configurations)
4. ลบโฟลเดอร์ทดสอบหลังตรวจสอบเสร็จ และรายงานสรุปเป็นสถานะ PASS/FAIL กลับมา

---

## 4. การจำลองสถานการณ์พังของระบบ (Failure Scenarios Simulation)

เพื่อทดสอบประสิทธิภาพของระบบกู้ภัยและการแจ้งเตือนผ่าน Discord Webhook ให้ทำการทดสอบดังนี้:

### ก. จำลองกรณีตั้งรหัสผ่าน Restic ผิด
1. เข้าเครื่องเป้าหมายแล้วเปิดไฟล์ `/etc/restic/restic.env`
2. แก้ไขรหัสผ่าน `RESTIC_PASSWORD` ให้ผิดไป 1 ตัวอักษร
3. สั่งรันคำสั่ง Backup Wrapper:
   ```bash
   sudo /usr/local/bin/backup-wrapper.sh
   ```
4. **สิ่งที่ต้องสังเกต**:
   - คำสั่งต้องรายงานรหัสผิดพลาด (exit status != 0)
   - มี log แจ้ง error บันทึกใน `/var/log/backup/backup-YYYY-MM-DD.log`
   - แชนเนล Discord ต้องส่งการแจ้งเตือน embed **แถบสีแดงสด** พร้อมระบุว่าล้มเหลว (FAILED)

### ข. จำลองกรณี Disk พังหรือสิทธิ์เข้าถึงผิด
1. ลบ Token สิทธิ์เข้าถึง Google Drive ชั่วคราว หรือตั้งค่า IP บล็อกเน็ตเวิร์กชั่วคราว
2. สั่งรันสำรองข้อมูล
3. ตรวจสอบว่าระบบมีความสามารถในการเคลียร์ Temp file ออกหรือไม่ (ต้องไม่ทิ้งขยะทิ้งไว้ในเครื่องหลังงานรันจบ)
4. สังเกตการแจ้งเตือนความล้มเหลวทาง Discord

---

## 📅 ข้อแนะนำในการดูแลรักษา (Operational Checklist)

1. **ทุกวัน (Daily)**: ตรวจสอบห้องแชท Discord เพื่อดูข้อความ "✅ สำเร็จ (Success)"
2. **ทุกเดือน (Monthly)**: สั่งรัน `test-restore.sh` เพื่อมั่นใจว่าข้อมูลสำรองใช้กู้ภัยได้จริง
3. **ทุก 6 เดือน (Bi-yearly)**: ทดสอบนำไฟล์ SQL dump ล่าสุดที่ backup ไปสั่งรัน restore ลงในเครื่องทดสอบเพื่อเช็คสภาพ table ข้อมูลจริง
