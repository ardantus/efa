# Panduan instalasi NixOS minimal di VMware (siap SSH)

Panduan ini menyiapkan NixOS minimal di VMware sampai bisa SSH, dengan akun:
- `nixos` / `nixos`
- `root` / `nixos`

Catatan: password ini sengaja lemah untuk VM lokal agar minim kendala.

## 1) Siapkan VM dan boot ISO
1. Unduh ISO NixOS Minimal (64-bit).
2. Buat VM baru di VMware:
   - Guest OS: Linux -> Other 64-bit (atau "NixOS" jika ada).
   - CPU: 2, RAM: 4 GB (boleh lebih/kurang).
   - Disk: 20 GB (atau sesuai kebutuhan).
   - Firmware: UEFI (disarankan).
3. Boot VM dari ISO NixOS.

## 2) Partisi dan mount disk (NVMe)
Masuk ke root shell:
```sh
sudo -i
```

Lihat disk (contoh NVMe: `/dev/nvme0n1`):
```sh
lsblk
```

Contoh partisi sederhana (EFI + root) di `/dev/nvme0n1`:
```sh
cfdisk /dev/nvme0n1
```
Pada saat cfdisk terbuka:
- Pilih label `gpt` jika diminta.
- Buat:
  - `nvme0n1p1` 512M type EFI System
  - `nvme0n1p2` sisa disk type Linux filesystem
- Pilih menu `Write`, ketik `yes`, lalu `Quit`.

Jika muncul pesan `did not write partition table to disk`:
- Pastikan sudah `Write` dan mengetik `yes`.
- Pastikan disk tidak dalam keadaan read-only atau ter-mount:
  ```sh
  lsblk -f
  mount | grep nvme0n1
  ```
  Jika ada yang ter-mount, unmount dulu:
  ```sh
  umount /dev/nvme0n1p1 /dev/nvme0n1p2
  ```
  Jika disk masih menolak ditulis, bersihkan signature lama (hati-hati, ini menghapus label/FS lama):
  ```sh
  wipefs -a /dev/nvme0n1
  ```

Format dan mount:
```sh
mkfs.fat -F 32 /dev/nvme0n1p1
mkfs.ext4 /dev/nvme0n1p2

mount /dev/nvme0n1p2 /mnt
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
```

## 3) Generate konfigurasi NixOS
```sh
nixos-generate-config --root /mnt
```

Edit `/mnt/etc/nixos/configuration.nix` dan tambahkan/ubah bagian berikut:
```nix
{ config, pkgs, ... }:
{
  networking.hostName = "nixos-vm";
  networking.useDHCP = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot";

  console.keyMap = "us";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "nixos";
  };

  users.users.root.initialPassword = "nixos";
}
```

Jika keyboard layout tidak cocok saat instalasi (misal tombol tidak sesuai):
```sh
loadkeys us
```
Ganti `us` dengan layout lain bila perlu (misal `id`).

## 4) Install NixOS
```sh
nixos-install
reboot
```
Keluarkan ISO dari VM saat reboot agar boot dari disk.

## 4a) Jika OOM saat `nixos-install`
Jika muncul `Out of memory` (OOM), biasanya RAM VM terlalu kecil.
Solusi cepat:
1. **Naikkan RAM VM** ke minimal 2–4 GB.
2. **Tambahkan swap sementara** sebelum `nixos-install`:
   ```sh
   fallocate -l 2G /mnt/swapfile
   chmod 600 /mnt/swapfile
   mkswap /mnt/swapfile
   swapon /mnt/swapfile
   free -h
   ```
3. **Kurangi paralel build**:
   ```sh
   nixos-install --cores 1 --max-jobs 1
   ```

## 4b) Jika EFI VMware "unsuccessful"
Jika VM gagal boot EFI:
1. Pastikan firmware VM diset ke UEFI dan bukan BIOS.
2. Pastikan ISO sudah dilepas setelah instalasi.
3. Pastikan partisi EFI ter-mount ke `/boot` saat install.
4. Rebuild konfigurasi dan reinstall bootloader:
   ```sh
   nixos-install
   ```
5. Jika masih gagal, cek di console VMware:
   - Gunakan menu VMware `Send Ctrl+Alt+Del` untuk reboot.
   - Periksa `lsblk -f` apakah `nvme0n1p1` bertipe `vfat`.

## 4c) Jika error "configuration.nix:143:1"
Format error `configuration.nix:143:1` artinya:
- File: `/mnt/etc/nixos/configuration.nix`
- Baris: **143**
- Kolom: **1** (awal baris)

Cara cek baris itu:
```sh
nl -ba /mnt/etc/nixos/configuration.nix | sed -n '143p'
```
Atau buka editor dan lompat ke baris 143 (misal di `nano`):
```sh
nano +143 /mnt/etc/nixos/configuration.nix
```

## 4d) Jika error "syntax error, unexpected end of file, expecting ';' at configuration.nix:141:1"
Ini hampir selalu berarti ada baris yang kurang `;` atau blok `{ ... }`/`(` `)`/`[ ]` tidak tertutup.
Lakukan cek cepat:
```sh
nl -ba /mnt/etc/nixos/configuration.nix | sed -n '130,150p'
```

Checklist perbaikan:
- Pastikan setiap assignment berakhir dengan `;`:
  - Contoh benar: `services.openssh.enable = true;`
- Pastikan setiap `{` punya pasangan `}`.
- Pastikan setiap `[` punya pasangan `]`.
- Pastikan tidak ada baris `}` atau `]` yang hilang setelah menambahkan blok.

Contoh yang sering salah:
```nix
users.users.root.initialPassword = "nixos"  # salah: kurang ;
```
Perbaiki menjadi:
```nix
users.users.root.initialPassword = "nixos";
```

## 5) Cek IP dan SSH
Login di console VM sebagai `nixos` (password `nixos`), lalu cek IP:
```sh
ip a
```

Dari host, lakukan SSH:
```sh
ssh nixos@<IP_VM>
ssh root@<IP_VM>
```

## 6) Salin dan jalankan script
Salin script dari host ke VM (contoh menggunakan `scp`):
```sh
scp /path/ke/script.sh nixos@<IP_VM>:/home/nixos/
```

Masuk ke VM dan jalankan:
```sh
ssh nixos@<IP_VM>
chmod +x /home/nixos/script.sh
/home/nixos/script.sh
```

Ganti `/path/ke/script.sh` dan `script.sh` sesuai nama script yang dimaksud.

## 7) Kirim satu folder `efa` ke VM
Jika ingin mengirim folder `efa` ke `/home/nixos/` di VM (contoh IP `172.16.247.134`):
```sh
scp -r /path/ke/efa root@172.16.247.134:/home/nixos/
```

Alternatif lebih cepat dan bisa resume (rsync):
```sh
rsync -av --progress /path/ke/efa/ root@172.16.247.134:/home/nixos/efa/
```

```sh
rsync -av --progress efa/ root@172.16.247.134:/home/nixos/efa/
```

## 8) Build VM (x86_64 vs ARM/aarch64)
Setelah folder `efa` sudah ada di VM/host, jalankan build sesuai arsitektur:

**x86_64 (Intel/AMD):**
```sh
nix --extra-experimental-features "nix-command flakes" \
  build .#nixosConfigurations.efaVm.config.system.build.vm
```

**ARM/aarch64 (Apple Silicon/ARM64):**
```sh
nix --extra-experimental-features "nix-command flakes" \
  build .#nixosConfigurations.efaVmAarch64.config.system.build.vm
```

## 9) Menjalankan VM hasil build + troubleshooting
Jalankan VM:
```sh
./result/bin/run-efa-vm
```

Jika muncul error:
- **`failed to initialize kvm`**: VM host tidak punya KVM (nested virt). QEMU akan fallback ke TCG (lebih lambat) tapi tetap bisa jalan.
- **`cannot set up guest memory`**: RAM host kurang. Kurangi RAM VM di flake:
  - `efaVmAarch64` sudah diset 1024 MB.
  - Jika masih gagal, turunkan lagi (misal 768).
- **`gtk initialization failed`**: VM berjalan tanpa GUI. Untuk ARM, diset headless otomatis. Rebuild lalu run ulang.

Jika VM tidak boot, semua port (25/80/443/587) tidak akan listen. Pastikan VM benar-benar jalan dulu baru cek port.

## 10) Jika terlanjur menjalankan `run-efa-vm` (cara menghentikan)
`run-efa-vm` membuat VM baru di dalam VM (nested). Jika tidak sengaja jalan, hentikan:
1. Kembali ke terminal yang menjalankan `run-efa-vm` lalu tekan `Ctrl+C`.
2. Jika masih jalan, matikan proses QEMU:
   ```sh
   pkill -f qemu-system-aarch64
   pkill -f qemu-system-x86_64
   ```
3. Pastikan sudah berhenti:
   ```sh
   pgrep -a qemu-system-aarch64
   pgrep -a qemu-system-x86_64
   ```
4. Jika kamu masih berada di konsol QEMU:
   - Tekan `Ctrl+A` lalu `X` untuk keluar dari QEMU.

## 11) Menjalankan eFa di VM yang sedang dipakai (bukan VM baru)
Kalau tujuanmu install & menjalankan eFa langsung di VM sekarang, pakai:
```sh
nix --extra-experimental-features "nix-command flakes" \
  nixos-rebuild switch --flake .#efa
```

Untuk ARM/aarch64:
```sh
nix --extra-experimental-features "nix-command flakes" \
  nixos-rebuild switch --flake .#efaAarch64
```

Setelah itu, cek layanan & port:
```sh
systemctl status postfix rspamd nginx mariadb
ss -lntp
```

Jika muncul error **`nixos-rebuild is not a recognised command`**:
- Kamu **bukan sedang di NixOS** (misal Arch/Ubuntu). `nixos-rebuild` hanya ada di NixOS.
- Solusinya: jalankan di VM NixOS (setelah instal NixOS), atau gunakan `run-efa-vm` untuk testing.

Catatan penting: `nixos-rebuild` **bukan** subcommand `nix`. Jalankan langsung seperti ini:
```sh
sudo nixos-rebuild switch --flake .#efa
```
Untuk ARM:
```sh
sudo nixos-rebuild switch --flake .#efaAarch64
```

Jika muncul error **`fileSystems`/`boot.loader.grub.devices`/`ACME`**:
1. **Import hardware configuration** ke flake (wajib untuk `fileSystems` dan boot):
   ```sh
   mkdir -p /home/nixos/efa/hosts
   sudo cp /etc/nixos/hardware-configuration.nix /home/nixos/efa/hosts/nixos-vm.nix
   ```
   `flake.nix` sudah otomatis meng‑include `./hosts/nixos-vm.nix` jika file ada.
2. **ACME**: Jika belum punya email/SSL, matikan dulu:
   ```nix
   efa.web.enableACME = false;
   efa.web.forceSSL = false;
   ```
   Atau set email & terms:
   ```nix
   security.acme.defaults.email = "you@example.com";
   security.acme.acceptTerms = true;
   ```
3. Jika masih muncul error `boot.loader.grub.devices`:
   - Pastikan `boot.loader.systemd-boot.enable = true;`
   - Pastikan `boot.loader.efi.canTouchEfiVariables = true;`
   - Pastikan `boot.loader.efi.efiSysMountPoint = "/boot";`

Untuk instal lokal cepat, `efa.database.bootstrapSecrets = true;` akan membuat
password default (`nixos`) di `/run/secrets/*-db-pass` jika belum ada.

## 12) Login console `run-efa-vm` dan akses UI
Jika kamu menjalankan `run-efa-vm` (VM QEMU), login konsolnya:
- `root` / `nixos`
- atau `nixos` / `nixos`

Jika login masih `incorrect`, pastikan kamu:
1. Sync repo terbaru ke VM.
2. Rebuild `efaVmAarch64` / `efaVm`.
3. Jalankan ulang `run-efa-vm`.

Akses UI eFa:
- Jika pakai `run-efa-vm` (port forward di host):
  - `http://localhost:8080/`
  - `https://localhost:8443/`
- Jika pakai VM biasa (bukan VM nested), buka:
  - `http://<IP_VM>/`
  - `https://<IP_VM>/`

## 13) Jika phpfpm-mailwatch gagal saat `run-efa-vm`
Jika muncul `Failed to start PHP FastCGI Process Manager service for pool mailwatch`:
- Ini bukan masalah login; itu service PHP‑FPM MailWatch yang belum start.
- Untuk detail di VM QEMU: `systemctl status phpfpm-mailwatch.service` dan `journalctl -u phpfpm-mailwatch`.
- Jika tujuanmu adalah menjalankan eFa di VM utama, hentikan `run-efa-vm` dan pakai langkah di bagian 11.

## 14) Jika `efa-init-sync` gagal (composer HOME)
Jika ada error `The HOME or COMPOSER_HOME environment variable must be set`:
- Pastikan repo terbaru tersync (module sudah set `HOME` dan `COMPOSER_HOME`).
- Rebuild:
  ```sh
  sudo nixos-rebuild switch --flake .#efaAarch64
  ```
Jika masih gagal karena `symfony-cmd`/auto-scripts:
- Composer sekarang dijalankan dengan `--no-scripts`.
- Alternatif: matikan composer penuh dengan set:
  ```nix
  efa.web.efaInitRunComposer = false;
  ```

## 15) Jika `mysql.service` gagal saat switch
Sering terjadi karena resource kecil di VM. Untuk ARM kami override buffer InnoDB ke 256M.
Jika masih gagal:
1. Lihat log:
   ```sh
   systemctl status mysql
   journalctl -u mysql -b
   ```
2. Reset data dir (menghapus data lama, hanya lakukan jika masih baru):
   ```sh
   sudo systemctl stop mysql
   sudo rm -rf /var/lib/mysql
   sudo systemctl start mysql
   ```
Jika log menunjukkan error `Cannot change ownership of .../lib/mysql/plugin/...`:
- Modul MariaDB sekarang menyalin plugin ke `/var/lib/mysql/plugin` (writeable).
- Sync repo terbaru lalu `sudo nixos-rebuild switch --flake .#efaAarch64`.
Jika log menunjukkan `skip-host-cache` dengan argumen:
- Hapus konfigurasi legacy `/etc/my.cnf` atau `/etc/my.cnf.d/mariadb-server.cnf`.
- Ini sekarang dilakukan otomatis saat `nixos-rebuild`.

## 16) Jika `rspamd.service` gagal saat switch
1. Lihat log detail:
   ```sh
   systemctl status rspamd
   journalctl -u rspamd -b
   ```
2. Validasi konfigurasi:
   ```sh
   rspamd -t -c /etc/rspamd/rspamd.conf
   ```
3. Jika perlu sementara (agar sistem stabil), matikan Rspamd:
   ```nix
   efa.rspamd.enable = false;
   ```
   lalu `sudo nixos-rebuild switch --flake .#efaAarch64`.