# eFa5 - Project for NixOS

Proyek ini adalah fork dari [eFa5 Project](https://github.com/E-F-A/eFa5).

Tujuan utama fork ini adalah untuk menulis ulang (rewrite) konfigurasi dan instalasi eFa5 agar bersifat **deklaratif** dan kompatibel dengan **NixOS**. Proyek ini tidak lagi menggunakan metode instalasi imperatif berbasis skrip bash yang digunakan pada versi aslinya, melainkan memanfaatkan kekuatan Nix language dan NixOS modules.

Source code asli dapat ditemukan di: https://github.com/E-F-A/eFa5

## Lisensi

Proyek ini adalah karya turunan (derivative work) dari [eFa5 Project](https://github.com/E-F-A/eFa5).
Kode sumber dalam repositori ini dilisensikan di bawah **GNU General Public License version 3** atau yang lebih baru (GPLv3+).

Anda diizinkan untuk menyalin, mendistribusikan, dan memodifikasi perangkat lunak ini asalkan Anda menyertakan sumber kode aslinya, serta perubahan yang Anda buat tetap berada di bawah lisensi yang sama (copyleft).

Lihat file [LICENSE](LICENSE) untuk teks lengkap dari lisensi ini.

### Atribusi
Proyek ini mengakui kerja keras pengembang asli dari [eFa Project](https://efa-project.org/).
Penulisan ulang deklaratif untuk NixOS ini tidak akan mungkin terjadi tanpa fondasi kokoh yang dibangun oleh tim eFa. Seluruh logika aplikasi, konfigurasi default, dan struktur layanan yang diadaptasi bersumber dari repositori upstream mereka.

---

# Dokumentasi Teknis

Repo ini berisi penulisan ulang NixOS deklaratif dari appliance eFa5 legacy.
Sumber legacy `./eFa5` disimpan hanya untuk referensi dan patching.

## eFa5 Legacy (CentOS) di Docker (hanya referensi)

Ini bersifat **best‑effort** untuk verifikasi dan inspeksi skrip. eFa5 asli
mengharapkan sistem CentOS penuh dengan systemd dan tooling RPM, jadi container harus
berjalan privileged.

### Opsi A: docker run

Dari root repo:

```sh
docker run --name efa5 \
  --privileged --cgroupns=host \
  --tmpfs /run --tmpfs /tmp \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  -v "$(pwd)/eFa5:/eFa5" \
  -p 8080:80 -p 8443:443 \
  -d quay.io/centos/centos:stream9 /sbin/init

docker exec -it efa5 /bin/bash
```

Di dalam container (contoh):

```sh
dnf -y install rpm-build rpmdevtools systemd
cd /eFa5
rpmbuild -ba rpmbuild/SPECS/eFa5.spec
```

### Opsi B: docker compose

Buat `docker-compose-centos.yml` (contoh):

```yaml
services:
  efa5:
    image: quay.io/centos/centos:stream9
    privileged: true
    cgroup: host
    tmpfs:
      - /run
      - /tmp
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
      - ./eFa5:/eFa5
    ports:
      - "8080:80"
      - "8443:443"
    command: ["/sbin/init"]
```

Lalu:

```sh
docker compose -f docker-compose-centos.yml up -d
docker exec -it efa5 /bin/bash
```

## NixOS di Docker (validasi)

Ini adalah menjalankan container best‑effort untuk memvalidasi refaktor. Ia memakai image Nix
untuk membangun derivasi sistem NixOS dan menampilkan error evaluasi.
Validasi layanan systemd secara penuh sebaiknya dilakukan di VM.

### Menggunakan `docker-compose.yml`

Dari root repo:

```sh
docker compose up -d
docker exec -it nixos /bin/bash
```

Di dalam container:

```sh
cd /efa
export NIX_SYSTEM="$(uname -m)-linux"
nix --extra-experimental-features "nix-command flakes" \
  build .#nixosConfigurations.efaContainer.config.system.build.toplevel
```

Untuk validasi layanan penuh, jalankan konfigurasi NixOS di VM.

## NixOS di VM (validasi penuh)

Bagian ini menjalankan NixOS VM berbasis QEMU untuk memastikan layanan dan port
sesuai instalasi eFa di CentOS (25/80/443/587). Pada host, port diarahkan ke
port non-privileged agar tidak perlu akses root.

### 1) Build VM

```sh
nix --extra-experimental-features "nix-command flakes" \
  build .#nixosConfigurations.efaVm.config.system.build.vm
```

### 2) Jalankan VM

```sh
./result/bin/run-efa-vm
```

Port forward (host -> guest):

- `2222` -> `22`
- `8025` -> `25`
- `8080` -> `80`
- `8443` -> `443`
- `8587` -> `587`

### 3) Verifikasi layanan di VM

Di console VM:

```sh
systemctl status postfix rspamd nginx mysql phpfpm-mailwatch
ss -tulpn | egrep ':(25|80|443|587)\s'
```

Uji dari host:

```sh
curl -I http://localhost:8080/
curl -k -I https://localhost:8443/
```

## Deploy NixOS (dari instal OS sampai eFa)

### 1) Instal NixOS 24.11

Instal NixOS seperti biasa. Setelah boot pertama, aktifkan flakes:

```sh
echo "experimental-features = nix-command flakes" | sudo tee -a /etc/nix/nix.conf
sudo systemctl restart nix-daemon
```

### 2) Clone repo ini

```sh
git clone <this-repo-url> /opt/efa
cd /opt/efa
```

### 3) Sediakan secrets

Buat secrets (atau gunakan `sops-nix`/`agenix`):

```sh
sudo install -d -m 0700 /run/secrets
sudo sh -c 'printf "CHANGEME\n" > /run/secrets/mailwatch-db-pass'
sudo sh -c 'printf "CHANGEME\n" > /run/secrets/sqlgrey-db-pass'
sudo sh -c 'printf "CHANGEME\n" > /run/secrets/sa-db-pass'
sudo sh -c 'printf "CHANGEME\n" > /run/secrets/opendmarc-db-pass'
sudo sh -c 'printf "CHANGEME\n" > /run/secrets/efa-db-pass'
sudo chmod 0400 /run/secrets/*-db-pass
```

### 4) Modul host (disarankan)

Buat `hosts/efa.nix` dengan pengaturan situs Anda:

```nix
{ ... }: {
  networking.hostName = "efa";

  efa.mail = {
    hostname = "mail.example.com";
    mydomain = "example.com";
    trustedNetworks = [ "127.0.0.0/8" "[::1]/128" ];
    enableSqlgrey = false;
  };

  efa.web = {
    root = "/var/www/html";
    enableACME = true;
    forceSSL = true;
  };
}
```

Lalu tambahkan ke daftar modul `flake.nix` (di `nixosConfigurations.efa.modules`).

### 5) Deploy

```sh
sudo nixos-rebuild switch --flake .#efa
```

### 6) Verifikasi

- UI Web: `https://<host>/` (MailWatch)
- Postfix + Rspamd: cek `systemctl status postfix rspamd`
- MariaDB: cek `systemctl status mysql`

## Catatan

- Skrip legacy eFa diguard pada NixOS dan akan menampilkan panduan alih‑alih
  melakukan perubahan imperatif.
- Semua perubahan dari upstream didokumentasikan di `CHANGES.md`.
