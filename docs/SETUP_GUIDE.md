# 📖 คู่มือการติดตั้งระบบสำรองข้อมูล (Setup Guide)

คู่มือฉบับละเอียดแบบเป็นขั้นตอน (Step-by-Step) สำหรับติดตั้งและตั้งค่าระบบสำรองข้อมูลอัตโนมัติ (Automated Backup System) ใน Home Lab ของคุณ

---

## ขั้นตอนที่ 1: การตั้งค่า SSH Key แบบไร้รหัสผ่าน (Passwordless SSH)

เพื่อให้ Ansible Control Node สามารถเข้าไปสั่งงานเครื่องเป้าหมายอื่นๆ ได้โดยไม่ต้องถามรหัสผ่านทุกครั้ง เราจำเป็นต้องใช้ SSH key pair

1. ตรวจสอบให้มั่นใจว่ารันสคริปต์จากโฟลเดอร์โครงการของ Control Node
2. สั่งรันสคริปต์พร้อมระบุ user และ IP ของเครื่องเป้าหมาย:
   ```bash
   chmod +x scripts/setup-ssh-keys.sh
   ./scripts/setup-ssh-keys.sh backup@192.168.1.10 backup@192.168.1.20
   ```
   *หมายเหตุ: ใน Home Lab แนะนำให้ใช้ username เดียวกันบนทุกโฮสต์ เช่น `backup` และให้สิทธิ์ sudo แบบไม่ต้องระบุรหัสผ่าน (`NOPASSWD` ใน visudo)*

---

## ขั้นตอนที่ 2: การสร้าง Google Drive API Credentials (OAuth)

การเข้าถึง Google Drive ผ่าน Rclone ในฐานะบุคคลภายนอก หากใช้ client ID ค่าเริ่มต้นของ rclone เอง ข้อมูลมักจะโอนย้ายได้ช้า และมักเจอปัญหา token หลุดการเชื่อมต่อ แนะนำให้สร้าง Client ID ของตัวเองใน Google Cloud Console ดังนี้:

1. เปิดเบราว์เซอร์ไปที่ [Google Cloud Console](https://console.cloud.google.com/)
2. สร้าง Project ใหม่ (เช่น "Home Lab Backup")
3. ไปที่เมนู **APIs & Services > Library** ค้นหา "Google Drive API" และคลิก **Enable**
4. ไปที่ **APIs & Services > OAuth consent screen**:
   - เลือก User Type เป็น **External**
   - กรอก App name และ User support email (ใส่อะไรก็ได้)
   - ข้ามหน้า Scopes ไปยัง Test users ให้กด **Add Users** แล้วกรอกอีเมล Gmail ของคุณ (เพื่อให้อีเมลนี้ใช้สิทธิ์ทดสอบได้)
5. ไปที่ **APIs & Services > Credentials**:
   - คลิก **Create Credentials** เลือก **OAuth client ID**
   - เลือก Application type เป็น **Desktop app**
   - ตั้งชื่อโปรเจกต์แล้วกด **Create**
   - คุณจะได้รับ **Client ID** และ **Client Secret** ให้ก๊อปปี้เก็บไว้

---

## ขั้นตอนที่ 3: การตั้งค่า Ansible Vault เก็บค่าความลับ

เราจะเก็บข้อมูลลับ (Client ID, Client Secret, Restic Password และ Discord Webhook) ไว้ในไฟล์ `vault/secrets.yml` แบบเข้ารหัส

1. เปิดไฟล์ `vault/secrets.yml`
2. กรอกข้อมูลจริงของคุณ เช่น:
   ```yaml
   vault_restic_password: "รหัสผ่านยากๆ-ที่คุณจำได้"
   vault_discord_webhook_url: "https://discord.com/api/webhooks/xxxxxx"
   vault_postgres_password: "รหัสผ่านแอดมินของฐานข้อมูล"
   vault_rclone_client_id: "client-id-ที่ได้จากขั้นตอนที่สอง.apps.googleusercontent.com"
   vault_rclone_client_secret: "client-secret-ที่ได้จากขั้นตอนที่สอง"
   ```
3. ทำการเข้ารหัสไฟล์ด้วยคำสั่ง:
   ```bash
   ansible-vault encrypt vault/secrets.yml
   ```
   *ระบบจะให้ป้อนรหัสผ่านสำหรับเปิดอ่านไฟล์นี้ แนะนำให้เขียนใส่ไว้ที่ไฟล์ `~/.vault_pass` เพื่อให้ Ansible สามารถเปิดใช้รหัสผ่านนี้รันอัตโนมัติได้ หากใช้ไฟล์ให้ปรับค่า `vault_password_file` ใน `ansible.cfg` ชี้ไปยังพาธของไฟล์รหัสผ่านนั้น*

---

## ขั้นตอนที่ 4: การรัน Ansible Playbook: Setup

สั่งให้ Ansible ทำการเตรียมระบบ ติดตั้ง restic, rclone และนำ configs ต่างๆ ไปวางบนเครื่องปลายทาง:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/setup.yml --ask-vault-pass
```

เมื่อ Playbook ทำงานเสร็จสมบูรณ์ ทุกเครื่องเป้าหมายจะถูกติดตั้งโปรแกรมและเตรียมโครงสร้างไฟล์ เช่น `/opt/backup` และไฟล์ Environment ใน `/etc/restic/restic.env` เรียบร้อย

---

## ขั้นตอนที่ 5: การขอสิทธิ์และสร้าง Rclone Token (OAuth Flow)

เนื่องจากระบบความปลอดภัยของ Google กำหนดให้ต้องมีการกดยืนยันตัวตนในบราวเซอร์ครั้งแรกเพื่อสร้าง OAuth Token (refresh token) สำหรับไปใช้ในเครื่องโฮสต์:

1. ล็อกอินเข้าไปยังเครื่องปลายทาง (เช่น Docker Host) ด้วย user `backup` (หรือเครื่องที่คุณจะรันก๊อปปี้ rclone)
2. สั่งรันคำสั่งรวบรวม Token:
   ```bash
   rclone config
   ```
3. เลือก **New remote** (ตั้งชื่อว่า `gdrive`)
4. เลือกประเภทพื้นที่จัดเก็บเป็น **Google Drive**
5. ป้อน `client_id` และ `client_secret` ที่คุณสร้างขึ้นเองในขั้นตอนที่ 2
6. เลือก Scope เป็น `1` (Full access to all files)
7. เมื่อถึงหน้าจอที่ระบบถามว่าต้องการ auto config หรือไม่ ให้เลือก **N** (No - เพราะคุณอาจรีโมทผ่าน SSH ไม่มีบราวเซอร์บนโฮสต์)
8. Rclone จะแสดงคำสั่งสำหรับก๊อปปี้ไปรันบนคอมพิวเตอร์ของคุณที่มีบราวเซอร์ (เช่น `rclone authorize "drive" ...`)
9. รันคำสั่งนั้นบนคอมพิวเตอร์ของคุณ ล็อกอินยืนยันสิทธิ์กับกูเกิล แล้วนำเอาโค้ด JSON ที่ได้จากคอมพิวเตอร์ของคุณกลับมาวางบนเครื่องเป้าหมาย
10. ตรวจสอบการใช้งาน Google Drive:
    ```bash
    rclone --config /opt/backup/.config/rclone/rclone.conf ls gdrive:
    ```
    *(ถ้าแสดงไฟล์และโฟลเดอร์ขึ้นมาแปลว่าผ่านการเชื่อมต่อสำเร็จ)*

11. **(สำคัญมาก)**: นำเอา JSON string ที่อยู่ในฟิลด์ `token` ในไฟล์ `rclone.conf` (ซึ่งถูกสร้างไว้ใน `/opt/backup/.config/rclone/rclone.conf` บนเครื่องเป้าหมาย) กลับมากรอกลงในตัวแปร `vault_rclone_refresh_token` ในไฟล์ `vault/secrets.yml` ใน Control Node เพื่อให้ Ansible สามารถอัปเดต config และเชื่อมต่อได้อย่างอัตโนมัติบนเครื่องอื่นๆ ในอนาคต

---

## ขั้นตอนที่ 6: การ Initialize Restic Repository บน Google Drive

ในเครื่องเป้าหมาย สั่งเตรียมไดเรกทอรีเก็บข้อมูลสำรองบนไดรฟ์โดยใช้สคริปต์ตัวช่วย:

```bash
# รันบนเครื่องโฮสต์ปลายทาง
sudo /opt/backup/scripts/init-restic-repo.sh
```
หรือรันสคริปต์ผ่านเครื่อง Control Node ไปยังเครื่องโฮสต์ (หาก copy สคริปต์ไปแล้ว)

---

## ขั้นตอนที่ 7: ทดสอบรันการสำรองข้อมูล (First Backup Job)

ทดลองส่งคำสั่งสั่งงานรัน Backup ทันทีจาก Control Node:

```bash
ansible-playbook -i inventory/hosts.yml playbooks/backup.yml --ask-vault-pass
```

เมื่อทำงานเสร็จสิ้น:
1. ตรวจสอบข้อความแจ้งเตือนสีเขียวสดบนแชนเนล Discord ของคุณ
2. ไฟล์ log วันที่ล่าสุดจะถูกสร้างที่ `/var/log/backup/backup-YYYY-MM-DD.log` บนเครื่องเป้าหมาย
3. ตรวจสอบการสำรองข้อมูลบน Google Drive:
   ```bash
   sudo restic -r rclone:gdrive:backup/restic-repo snapshots
   ```
