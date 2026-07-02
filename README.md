# 🔄 Automated Backup System for Home Lab (Restic + Rclone + Google Drive)

ระบบสำรองข้อมูลอัตโนมัติสำหรับ Home Lab ที่มีความปลอดภัยสูง โดยใช้ **Ansible** เป็นตัวควบคุม (Control Node) สั่งงานเครื่องเป้าหมายเพื่อทำ Backup ข้อมูลสำคัญ เช่น Docker volumes, Config (.env, docker-compose.yml), WireGuard, AdGuard Home และฐานข้อมูลหลัก PostgreSQL/SQLite ไปเก็บไว้บน **Google Drive** ด้วยโปรแกรม **Restic** ซึ่งรองรับการเข้ารหัสข้อมูล (Encryption) และการทำ Deduplication ประหยัดเนื้อที่

## 🚀 สถาปัตยกรรมระบบ (Architecture Overview)

```text
  [ Ansible Control Node ] (Debian 12)
          │
          │ (SSH via key pair)
          ▼
┌───────────────────┐    ┌───────────────────┐
│    Proxmox VE     │    │    Docker Host    │
│  (Config Backups) │    │  (Volumes + DBs)  │
└─────────┬─────────┘    └─────────┬─────────┘
          │                        │
          └───────────┬────────────┘
                      │ (restic backup via rclone)
                      ▼
             ┌───────────────────┐
             │   Google Drive    │
             │   (Restic Repo)   │
             └───────────────────┘
```

---

## 🛠️ ความต้องการทางเทคนิค (Prerequisites)

1. **Control Node**:
   - ระบบปฏิบัติการ Debian 12 (หรือ Ubuntu)
   - ติดตั้ง Ansible แล้ว (สามารถติดตั้งผ่าน `sudo apt install ansible`)
   - มีสิทธิ์เข้าถึง SSH ของเครื่องเป้าหมายแบบไร้รหัสผ่าน (Passwordless SSH)
2. **Target Nodes (Proxmox, Docker Host)**:
   - ระบบปฏิบัติการ Debian/Ubuntu
   - มี SSH Server ทำงานและตั้งค่าให้ backup user เข้าถึงได้
   - ได้รับสิทธิ์ sudo หรือตั้งค่า system cap ของระบบ
3. **Google Drive Storage**:
   - บัญชี Google Drive
   - API client ID และ client secret สำหรับติดตั้ง rclone (แนะนำ)

---

## 📂 โครงสร้างโฟลเดอร์ของโปรเจกต์ (Project Structure)

```text
automated-backup-system/
├── README.md                          # ไฟล์เอกสารอธิบายการใช้งานระบบเบื้องต้น
├── ansible.cfg                        # การตั้งค่าค่าเริ่มต้นของ Ansible
├── inventory/
│   ├── hosts.yml                      # กำหนดเครื่องเป้าหมายในระบบ
│   └── group_vars/
│       ├── all.yml                    # ตัวแปรส่วนกลาง (เช่น retention, rclone paths)
│       ├── docker_hosts.yml           # ตัวแปรเฉพาะของเครื่อง Docker Host ( volumes, db configs )
│       └── proxmox.yml                # ตัวแปรเฉพาะของเครื่อง Proxmox ( config paths )
├── vault/
│   └── secrets.yml                    # ตัวแปรเก็บความลับสำคัญ (รหัสผ่าน restic, discord url, db pass)
├── playbooks/
│   ├── site.yml                       # Playbook หลักที่นำมารวมกันทั้งหมด (Setup + Backup)
│   ├── setup.yml                      # Playbook สำหรับเตรียมเครื่องเป้าหมายและติดตั้งโปรแกรม
│   ├── backup.yml                     # Playbook สำหรับรันคำสั่ง Backup เดี๋ยวนั้น
│   ├── restore.yml                    # Playbook สำหรับสั่งกู้คืนไฟล์แบบเจาะจง (Interactive)
│   └── test-restore.yml               # Playbook ทดสอบประสิทธิภาพการกู้คืนไฟล์อัตโนมัติ
├── roles/                             # แยกรวม logic ตามบทบาทหน้าที่การรัน
│   ├── common/                        # สร้าง user, group, ssh keys, dirs บนเป้าหมาย
│   ├── restic_setup/                  # ติดตั้ง restic, rclone และ config ต่างๆ
│   ├── backup_docker/                 # ก๊อปปี้ docker configs, พัก docker container
│   ├── backup_configs/                # ตรวจสอบและเลือก paths config บน Host OS
│   ├── backup_database/               # เขียน dump สคริปต์ฐานข้อมูล PostgreSQL / SQLite
│   ├── restic_backup/                 # สคริปต์หลักสำหรับทำงาน Restic Backup และ prune ไฟล์
│   ├── notification/                  # จัดเตรียมและส่ง HTTP POST ไปยัง Discord Webhook
│   └── scheduling/                    # สร้าง Cron Job และ Logrotate
└── scripts/                           # สคริปต์ช่วยเหลือนอกรอบ
    ├── setup-ssh-keys.sh              # แจกจ่าย SSH public key จาก Control Node
    ├── init-restic-repo.sh            # สั่งสร้าง repo บน Google Drive ในครั้งแรก
    └── test-restore.sh                # เทส restore สแตนด์อโลน (ไม่ต้องผ่าน Ansible)
```

---

## 🏃 สรุปขั้นตอนเริ่มต้นใช้งานด่วน (Quick Start in 5 Steps)

รายละเอียดการตั้งค่าแบบเจาะลึกสามารถอ่านได้ที่ [SETUP_GUIDE.md](file:///C:/Users/User/.gemini/antigravity/scratch/automated-backup-system/docs/SETUP_GUIDE.md)

1. **สร้างและแลกคีย์ SSH**:
   ```bash
   chmod +x scripts/*.sh
   ./scripts/setup-ssh-keys.sh backup@192.168.1.10 backup@192.168.1.20
   ```
2. **แก้ไขตัวแปรและเข้ารหัสไฟล์ความลับ**:
   - แก้ไขไอพีและโฮสต์ใน [hosts.yml](file:///C:/Users/User/.gemini/antigravity/scratch/automated-backup-system/inventory/hosts.yml)
   - กรอกรหัสผ่านใน [secrets.yml](file:///C:/Users/User/.gemini/antigravity/scratch/automated-backup-system/vault/secrets.yml) จากนั้นทำการเข้ารหัสด้วย Ansible Vault:
     ```bash
     ansible-vault encrypt vault/secrets.yml
     ```
3. **ติดตั้ง Restic & Rclone และสร้าง Repo**:
   - รัน Playbook สำหรับเตรียมสภาพแวดล้อม:
     ```bash
     ansible-playbook -i inventory/hosts.yml playbooks/setup.yml --ask-vault-pass
     ```
   - เข้าเครื่องเป้าหมายเพื่อสร้าง Token ใน rclone.conf (อ่านขั้นตอนใน Setup Guide) แล้วสั่ง Init Restic Repo:
     ```bash
     ./scripts/init-restic-repo.sh
     ```
4. **ทดสอบ Backup ครั้งแรก**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/backup.yml --ask-vault-pass
   ```
5. **ทดสอบกู้คืนข้อมูล**:
   ```bash
   ansible-playbook -i inventory/hosts.yml playbooks/test-restore.yml --ask-vault-pass
   ```

---

## 📄 แผนเอกสารแนะนำโครงการเพิ่มเติม

- [SETUP_GUIDE.md](file:///C:/Users/User/.gemini/antigravity/scratch/automated-backup-system/docs/SETUP_GUIDE.md) - คู่มืออธิบายวิธีกรอก token, oauth และตั้งค่า restic
- [TESTING_GUIDE.md](file:///C:/Users/User/.gemini/antigravity/scratch/automated-backup-system/docs/TESTING_GUIDE.md) - วิธีทดสอบระบบ, ตรวจสอบ log และจำลองความเสียหาย
- [TROUBLESHOOTING.md](file:///C:/Users/User/.gemini/antigravity/scratch/automated-backup-system/docs/TROUBLESHOOTING.md) - รวบรวมแนวทางแก้ไขข้อผิดพลาดที่พบบ่อย
