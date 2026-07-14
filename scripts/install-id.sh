#!/bin/bash

# archie-installer
#
# Copyright (C) 2026 James "Jim" Ed Randson
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

set -e

# Ketika skrip ini dijalankan lewat pipe (mis. `wget -qO- <url> | bash` atau
# `curl -sL <url> | bash`), stdin dipakai untuk mengalirkan isi skrip itu
# sendiri, sehingga prompt `read -p` di bawah bisa gagal diam-diam atau
# membaca data yang salah, bukan menunggu input pengguna. Arahkan ulang stdin
# ke terminal pengendali agar semua prompt interaktif tetap bekerja terlepas
# dari cara skrip ini dijalankan.
if [ ! -t 0 ]; then
    if [ -e /dev/tty ]; then
        exec < /dev/tty
    else
        echo "ERROR: Installer ini membutuhkan terminal interaktif (tidak ada /dev/tty)." >&2
        echo "Unduh skrip ini lalu jalankan langsung, jangan di-pipe ke bash." >&2
        exit 1
    fi
fi

# Warna untuk output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variabel global
EMMC_DEVICE=""
SSD_DEVICE=""
NVME_DEVICE=""
ESP_SIZE_MIB=256
SWAP_SIZE=""
ROOT_FS="xfs"
HOME_FS="xfs"
SEPARATE_HOME=false
HAVE_SSD=false
HAVE_NVME=false
MAIN_STORAGE=""
HOME_STORAGE=""
KERNEL=""
KERNEL_HEADERS=""
DESKTOP=""
DISPLAY_MANAGER=""
THIRD_PARTY_REPOS=()
TIMEZONE="Asia/Jakarta"
LOCALE="en_US.UTF-8"
HOSTNAME=""
USERNAME=""
ROOT_PASSWORD=""
USER_PASSWORD=""
DEEPIN_EXTRA=false
GNOME_EXTRA_OPTION=""
KDE_DM_OPTION=""
KDE_MOBILE=false

# Fungsi untuk output berwarna
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Fungsi untuk refresh repository
refresh_repos() {
    clear
    print_header "MEMPERBARUI REPOSITORI"
    
    if ! pacman -Sy; then
        print_error "Gagal memperbarui repositori. Instalasi tidak dapat dilanjutkan"
        exit 1
    fi
    
    # Aktifkan multilib jika belum aktif
    if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
        print_info "Mengaktifkan repository multilib..."
        echo "" >> /etc/pacman.conf
        echo "[multilib]" >> /etc/pacman.conf
        echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
        pacman -Sy
    fi
    
    print_success "Repository diperbarui. Dilanjutkan ke langkah berikutnya."
}

# Fungsi untuk mendeteksi storage
detect_storage() {
    clear
    print_header "MENDETEKSI STORAGE"
    
    if lsblk | grep -q "mmcblk0"; then
        EMMC_DEVICE="/dev/mmcblk0"
    elif lsblk | grep -q "mmcblk1"; then
        EMMC_DEVICE="/dev/mmcblk1"
    fi
    
    if lsblk | grep -q "sda"; then
        SSD_DEVICE="/dev/sda"
        HAVE_SSD=true
    fi
    
    if lsblk | grep -q "nvme0n1"; then
        NVME_DEVICE="/dev/nvme0n1"
        HAVE_NVME=true
    elif lsblk | grep -q "nvme1n1"; then
        NVME_DEVICE="/dev/nvme1n1"
        HAVE_NVME=true
    fi
    
    echo "eMMC Device: ${EMMC_DEVICE:-Tidak terdeteksi}"
    echo "SSD Device: ${SSD_DEVICE:-Tidak terdeteksi}"
    echo "NVMe Device: ${NVME_DEVICE:-Tidak terdeteksi}"
}

# Fungsi untuk memilih storage utama
select_main_storage() {
    clear
    print_header "MEMILIH STORAGE UTAMA"
    
    AVAILABLE_STORAGES=()
    
    if [[ -n "$EMMC_DEVICE" ]]; then
        AVAILABLE_STORAGES+=("eMMC:$EMMC_DEVICE")
    fi
    if [[ -n "$SSD_DEVICE" ]]; then
        AVAILABLE_STORAGES+=("SSD:$SSD_DEVICE")
    fi
    if [[ -n "$NVME_DEVICE" ]]; then
        AVAILABLE_STORAGES+=("NVMe:$NVME_DEVICE")
    fi
    
    if [[ ${#AVAILABLE_STORAGES[@]} -eq 0 ]]; then
        print_error "Tidak ada storage yang terdeteksi. Instalasi tidak dapat dilanjutkan"
        exit 1
    fi
    
    echo "Storage yang tersedia:"
    local index=1
    for storage in "${AVAILABLE_STORAGES[@]}"; do
        local type device
        type=$(echo "$storage" | cut -d: -f1)
        device=$(echo "$storage" | cut -d: -f2)
        echo "$index. $type ($device)"
        ((index++))
    done
    
    read -r -p "Pilih storage utama untuk sistem (root/): [1-${#AVAILABLE_STORAGES[@]}]: " main_choice
    MAIN_STORAGE=$(echo "${AVAILABLE_STORAGES[$((main_choice-1))]}" | cut -d: -f2)
    MAIN_STORAGE_TYPE=$(echo "${AVAILABLE_STORAGES[$((main_choice-1))]}" | cut -d: -f1)
    
    print_success "Storage utama: $MAIN_STORAGE_TYPE ($MAIN_STORAGE). Lanjut ke langkah berikutnya."
}

# Fungsi untuk memilih storage untuk /home
select_home_storage() {
    clear
    print_header "MEMILIH STORAGE UNTUK /HOME"
    
    AVAILABLE_STORAGES=()
    
    if [[ -n "$EMMC_DEVICE" && "$EMMC_DEVICE" != "$MAIN_STORAGE" ]]; then
        AVAILABLE_STORAGES+=("eMMC:$EMMC_DEVICE")
    fi
    if [[ -n "$SSD_DEVICE" && "$SSD_DEVICE" != "$MAIN_STORAGE" ]]; then
        AVAILABLE_STORAGES+=("SSD:$SSD_DEVICE")
    fi
    if [[ -n "$NVME_DEVICE" && "$NVME_DEVICE" != "$MAIN_STORAGE" ]]; then
        AVAILABLE_STORAGES+=("NVMe:$NVME_DEVICE")
    fi
    
    # Tambahkan opsi untuk partisi terpisah di storage yang sama
    AVAILABLE_STORAGES+=("Terpisah di storage utama:$MAIN_STORAGE")
    
    echo "Pilih lokasi untuk /home:"
    local index=1
    for storage in "${AVAILABLE_STORAGES[@]}"; do
        local type device
        type=$(echo "$storage" | cut -d: -f1)
        device=$(echo "$storage" | cut -d: -f2)
        echo "$index. $type ($device)"
        ((index++))
    done
    
    read -r -p "Pilih lokasi /home: [1-${#AVAILABLE_STORAGES[@]}]: " home_choice
    HOME_STORAGE=$(echo "${AVAILABLE_STORAGES[$((home_choice-1))]}" | cut -d: -f2)
    HOME_STORAGE_TYPE=$(echo "${AVAILABLE_STORAGES[$((home_choice-1))]}" | cut -d: -f1)
    
    if [[ "$HOME_STORAGE_TYPE" == "Terpisah di storage utama" ]]; then
        SEPARATE_HOME=true
        HOME_STORAGE="$MAIN_STORAGE"
    else
        SEPARATE_HOME=false
    fi
    
    print_success "Storage /home: $HOME_STORAGE_TYPE ($HOME_STORAGE). Lanjut ke langkah berikutnya."
}

# Fungsi untuk mempartisi storage utama
partition_main_storage() {
    clear
    print_header "MEMPARTISI STORAGE UTAMA"
    
    local device="$MAIN_STORAGE"
    
    # Tentukan prefix partisi berdasarkan tipe device
    if [[ "$device" == *"nvme"* ]]; then
        PART_PREFIX="p"
    else
        PART_PREFIX=""
    fi
    
    # Cek apakah sudah dipartisi
    if lsblk "$device" | grep -q "part"; then
        print_warning "$device sudah memiliki partisi"
        read -r -p "Apakah Anda ingin mempartisi ulang? Ini akan menghapus semua data! [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Menggunakan partisi yang sudah ada"
            return 0
        fi
    fi
    
    # Hapus partisi yang ada
    wipefs -a "$device"
    sgdisk --zap-all "$device"
    
    # Buat partisi baru dengan parted
    parted "$device" mklabel gpt
    parted "$device" mkpart ESP fat32 1MiB $((ESP_SIZE_MIB + 1))MiB
    parted "$device" set 1 boot on
    parted "$device" set 1 esp on
    
    # Tanya ukuran swap
    echo "Ukuran swap (minimal 4 GiB, maksimal 10 GiB):"
    read -r -p "Masukkan ukuran swap dalam GiB [4]: " swap_input
    SWAP_SIZE="${swap_input:-4}"
    
    if [[ "$SWAP_SIZE" -lt 4 ]]; then
        SWAP_SIZE=4
    elif [[ "$SWAP_SIZE" -gt 10 ]]; then
        SWAP_SIZE=10
    fi
    
    # Hitung ukuran partisi
    ESP_END=$((ESP_SIZE_MIB + 1))
    SWAP_START=$ESP_END
    SWAP_END=$((SWAP_START + (SWAP_SIZE * 1024)))
    
    parted "$device" mkpart swap linux-swap ${SWAP_START}MiB ${SWAP_END}MiB
    
    # Jika home terpisah di storage yang sama
    if [[ "$SEPARATE_HOME" == true ]]; then
        read -r -p "Masukkan ukuran /home dalam GiB: " home_size
        HOME_START=$SWAP_END
        HOME_END=$((HOME_START + (home_size * 1024)))
        parted "$device" mkpart home ${HOME_FS} ${HOME_START}MiB ${HOME_END}MiB
        parted "$device" mkpart root ${ROOT_FS} ${HOME_END}MiB 100%
    else
        parted "$device" mkpart root ${ROOT_FS} ${SWAP_END}MiB 100%
    fi
    
    # Format partisi
    print_info "Memformat partisi..."
    mkfs.fat -F32 "${device}${PART_PREFIX}1"
    mkswap "${device}${PART_PREFIX}2"
    
    if [[ "$SEPARATE_HOME" == true ]]; then
        mkfs.${HOME_FS} "${device}${PART_PREFIX}3"
        mkfs.${ROOT_FS} "${device}${PART_PREFIX}4"
    else
        mkfs.${ROOT_FS} "${device}${PART_PREFIX}3"
    fi
    
    print_success "Partisi selesai. Lanjut ke langkah berikutnya."
}

# Fungsi untuk mempartisi storage /home (jika storage berbeda)
partition_home_storage() {
    clear
    print_header "MEMPARTISI STORAGE /HOME"
    
    local device="$HOME_STORAGE"
    
    # Jika home di storage yang sama, skip
    if [[ "$device" == "$MAIN_STORAGE" ]]; then
        return 0
    fi
    
    # Tentukan prefix partisi berdasarkan tipe device
    if [[ "$device" == *"nvme"* ]]; then
        PART_PREFIX="p"
    else
        PART_PREFIX=""
    fi
    
    # Cek apakah sudah dipartisi
    if lsblk "$device" | grep -q "part"; then
        print_warning "$device sudah memiliki partisi"
        read -r -p "Apakah Anda ingin mempartisi ulang? Ini akan menghapus semua data! [y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            print_info "Menggunakan partisi yang sudah ada"
            return 0
        fi
    fi
    
    # Hapus partisi yang ada
    wipefs -a "$device"
    sgdisk --zap-all "$device"
    
    # Buat partisi baru
    parted "$device" mklabel gpt
    parted "$device" mkpart home ${HOME_FS} 1MiB 100%
    
    # Format
    mkfs.${HOME_FS} "${device}${PART_PREFIX}1"
    
    print_success "Storage /home dipartisi"
}

# Fungsi untuk mounting partisi
mount_partitions() {
    clear
    print_header "MOUNTING PARTISI"
    
    # Tentukan prefix partisi untuk storage utama
    if [[ "$MAIN_STORAGE" == *"nvme"* ]]; then
        MAIN_PART_PREFIX="p"
    else
        MAIN_PART_PREFIX=""
    fi
    
    # Tentukan prefix partisi untuk storage home
    if [[ "$HOME_STORAGE" == *"nvme"* ]]; then
        HOME_PART_PREFIX="p"
    else
        HOME_PART_PREFIX=""
    fi
    
    # Mount root
    if [[ "$SEPARATE_HOME" == true ]]; then
        mount "${MAIN_STORAGE}${MAIN_PART_PREFIX}4" /mnt
    else
        mount "${MAIN_STORAGE}${MAIN_PART_PREFIX}3" /mnt
    fi
    
    # Buat direktori dan mount ESP
    mkdir -p /mnt/boot/efi
    mount "${MAIN_STORAGE}${MAIN_PART_PREFIX}1" /mnt/boot/efi
    
    # Mount swap
    swapon "${MAIN_STORAGE}${MAIN_PART_PREFIX}2"
    
    # Mount home jika terpisah di storage yang sama
    if [[ "$SEPARATE_HOME" == true ]]; then
        mkdir -p /mnt/home
        mount "${MAIN_STORAGE}${MAIN_PART_PREFIX}3" /mnt/home
    fi
    
    # Mount home jika di storage berbeda
    if [[ "$HOME_STORAGE" != "$MAIN_STORAGE" ]]; then
        mkdir -p /mnt/home
        mount "${HOME_STORAGE}${HOME_PART_PREFIX}1" /mnt/home
    fi
    
    print_success "Partisi dimount. Lanjut ke langkah berikutnya."
}

# Fungsi untuk memilih kernel
select_kernel() {
    clear
    print_header "MEMILIH KERNEL LINUX"
    
    echo "Kernel yang tersedia:"
    echo "1. linux (kernel standar)"
    echo "2. linux-lts (kernel Long Term Support)"
    echo "3. linux-zen (kernel yang dioptimalkan)"
    echo "4. linux-hardened (kernel yang diperketat)"
    echo ""
    read -r -p "Pilih kernel [1-4]: " kernel_choice
    
    case $kernel_choice in
        1)
            KERNEL="linux"
            KERNEL_HEADERS="linux-headers"
            ;;
        2)
            KERNEL="linux-lts"
            KERNEL_HEADERS="linux-lts-headers"
            ;;
        3)
            KERNEL="linux-zen"
            KERNEL_HEADERS="linux-zen-headers"
            ;;
        4)
            KERNEL="linux-hardened"
            KERNEL_HEADERS="linux-hardened-headers"
            ;;
        *)
            print_error "Pilihan tidak valid"
            exit 1
            ;;
    esac
    
    print_success "Kernel dipilih: $KERNEL"
}

# Fungsi untuk memilih desktop environment
select_desktop() {
    clear
    print_header "MEMILIH DESKTOP ENVIRONMENT"
    
    echo "Pilih desktop environment:"
    echo "1. No desktop (Home Server) - dengan OpenSSH dan Cockpit"
    echo "2. No desktop (Minimal) - TTY/CLI minimal"
    echo "3. Budgie"
    echo "4. Cinnamon"
    echo "5. COSMIC"
    echo "6. Deepin DE"
    echo "7. GNOME"
    echo "8. GNOME Flashback"
    echo "9. KDE Plasma"
    echo "10. LXDE"
    echo "11. LXQt"
    echo "12. MATE"
    echo "13. Pantheon"
    echo "14. XFCE"
    echo "15. Instal kustom (Custom installation)"
    echo ""
    read -r -p "Pilih desktop environment [1-15]: " desktop_choice
    
    case $desktop_choice in
        1)
            DESKTOP="no-desktop-server"
            ;;
        2)
            DESKTOP="no-desktop-minimal"
            ;;
        3)
            DESKTOP="budgie"
            DISPLAY_MANAGER="lightdm"
            ;;
        4)
            DESKTOP="cinnamon"
            DISPLAY_MANAGER="lightdm"
            ;;
        5)
            DESKTOP="cosmic"
            DISPLAY_MANAGER="cosmic-greeter"
            ;;
        6)
            DESKTOP="deepin"
            DISPLAY_MANAGER="lightdm"
            read -r -p "Pasang deepin-extra? [y/N]: " deepin_confirm
            if [[ "$deepin_confirm" =~ ^[Yy]$ ]]; then
                DEEPIN_EXTRA=true
            fi
            ;;
        7)
            DESKTOP="gnome"
            DISPLAY_MANAGER="gdm"
            echo "Pilih paket tambahan GNOME:"
            echo "1. gnome-circle"
            echo "2. gnome-extra"
            echo "3. Tidak ada"
            read -r -p "Pilih [1-3]: " gnome_extra_choice
            case $gnome_extra_choice in
                1) GNOME_EXTRA_OPTION="gnome-circle" ;;
                2) GNOME_EXTRA_OPTION="gnome-extra" ;;
                3) GNOME_EXTRA_OPTION="" ;;
            esac
            ;;
        8)
            DESKTOP="gnome-flashback"
            DISPLAY_MANAGER="lightdm"
            ;;
        9)
            DESKTOP="kde-plasma"
            echo "Pilih display manager:"
            echo "1. SDDM"
            echo "2. Plasma Login Manager"
            read -r -p "Pilih [1-2]: " kde_dm_choice
            case $kde_dm_choice in
                1) 
                    DISPLAY_MANAGER="sddm"
                    KDE_DM_OPTION="sddm"
                    ;;
                2) 
                    DISPLAY_MANAGER="plasmalogin"
                    KDE_DM_OPTION="plasma-login-manager"
                    ;;
            esac
            read -r -p "Pasang KDE Plasma Mobile? [y/N]: " kde_mobile_confirm
            if [[ "$kde_mobile_confirm" =~ ^[Yy]$ ]]; then
                KDE_MOBILE=true
            fi
            ;;
        10)
            DESKTOP="lxde"
            DISPLAY_MANAGER="lightdm"
            ;;
        11)
            DESKTOP="lxqt"
            DISPLAY_MANAGER="lightdm"
            ;;
        12)
            DESKTOP="mate"
            DISPLAY_MANAGER="lightdm"
            ;;
        13)
            DESKTOP="pantheon"
            DISPLAY_MANAGER="lightdm"
            ;;
        14)
            DESKTOP="xfce"
            DISPLAY_MANAGER="lightdm"
            ;;
        15)
            DESKTOP="custom"
            ;;
        *)
            print_error "Pilihan tidak valid. Instalasi tidak dapat dilanjutkan."
            exit 1
            ;;
    esac
    
    print_success "Desktop dipilih: $DESKTOP. Lanjut ke langkah berikutnya."
}

# Fungsi untuk memilih repository pihak ketiga
select_third_party_repos() {
    clear
    print_header "REPOSITORY PIHAK KETIGA"
    
    echo "Pilih repository pihak ketiga (opsional):"
    echo "1. CachyOS repo"
    echo "2. Jim AUR (jimedrand's AUR repo)"
    echo "3. Chaotic AUR repo"
    echo "4. Tidak ada"
    echo ""
    read -r -p "Pilih repository [1-4]: " repo_choice
    
    case $repo_choice in
        1)
            THIRD_PARTY_REPOS+=("cachyos")
            ;;
        2)
            THIRD_PARTY_REPOS+=("jim-aur")
            ;;
        3)
            THIRD_PARTY_REPOS+=("chaotic-aur")
            ;;
        4)
            ;;
        *)
            print_error "Pilihan tidak valid. Instalasi tidak dapat dilanjutkan."
            exit 1
            ;;
    esac
}

# Fungsi untuk konfigurasi lokalisasi
configure_locale() {
    clear
    print_header "KONFIGURASI LOKALISASI"
    
    echo "Timezone (default: Asia/Jakarta):"
    read -r -p "Masukkan timezone: " timezone_input
    TIMEZONE="${timezone_input:-Asia/Jakarta}"
    
    echo "Locale (default: en_US.UTF-8):"
    read -r -p "Masukkan locale: " locale_input
    LOCALE="${locale_input:-en_US.UTF-8}"
    
    print_success "Lokalisasi dikonfigurasi. Lanjut ke langkah berikutnya."
}

# Fungsi untuk konfigurasi hostname
configure_hostname() {
    clear
    print_header "KONFIGURASI HOSTNAME"
    
    read -r -p "Masukkan hostname: " hostname_input
    HOSTNAME="${hostname_input:-archlinux}"
    
    print_success "Hostname: $HOSTNAME. Lanjut ke langkah berikutnya."
}

# Fungsi untuk konfigurasi user
configure_users() {
    clear
    print_header "KONFIGURASI USER"
    
    # Root password
    while true; do
        read -r -s -p "Masukkan password root: " root_pass1
        echo ""
        read -r -s -p "Ulangi password root: " root_pass2
        echo ""
        if [[ "$root_pass1" == "$root_pass2" ]]; then
            ROOT_PASSWORD="$root_pass1"
            break
        else
            print_error "Password tidak cocok"
        fi
    done
    
    # Username
    read -r -p "Masukkan username: " username_input
    USERNAME="${username_input:-user}"
    
    # User password
    while true; do
        read -r -s -p "Masukkan password user: " user_pass1
        echo ""
        read -r -s -p "Ulangi password user: " user_pass2
        echo ""
        if [[ "$user_pass1" == "$user_pass2" ]]; then
            USER_PASSWORD="$user_pass1"
            break
        else
            print_error "Password tidak cocok"
        fi
    done
    
    print_success "User dikonfigurasi. Lanjut ke langkah berikutnya."
}

# Fungsi untuk konfirmasi instalasi
confirm_installation() {
    clear
    print_header "KONFIRMASI INSTALASI"
    
    echo "Ringkasan instalasi:"
    echo "eMMC: $EMMC_DEVICE"
    echo "SSD: ${SSD_DEVICE:-Tidak ada}"
    echo "Kernel: $KERNEL"
    echo "Desktop: $DESKTOP"
    echo "Display Manager: ${DISPLAY_MANAGER:-Tidak ada}"
    echo "Timezone: $TIMEZONE"
    echo "Locale: $LOCALE"
    echo "Hostname: $HOSTNAME"
    echo "Username: $USERNAME"
    echo ""
    echo "Pilihan:"
    echo "1. Lanjutkan instalasi"
    echo "2. Ulangi penetapan opsi"
    echo "3. Batalkan instalasi"
    echo ""
    read -r -p "Pilih [1-3]: " confirm_choice
    
    case $confirm_choice in
        1)
            print_success "Melanjutkan instalasi..."
            ;;
        2)
            print_info "Mengulang penetapan opsi..."
            exec "$0"
            ;;
        3)
            print_warning "Instalasi dibatalkan."
            exit 0
            ;;
        *)
            print_error "Pilihan tidak valid. Instalasi tidak dapat dilanjutkan."
            exit 1
            ;;
    esac
}

# Fungsi untuk install base system
install_base_system() {
    clear
    print_header "INSTALL BASE SYSTEM"
    
    # Siapkan paket Intel driver
    INTEL_DRIVERS="intel-ucode sof-firmware"
    
    # Siapkan filesystem utils
    FS_UTILS="xfsprogs e2fsprogs btrfs-progs f2fs-tools jfsutils reiserfsprogs"
    
    # Siapkan bluetooth
    BLUETOOTH="bluez bluez-utils"
    
    # Pacstrap
    pacstrap -K /mnt base base-devel "$KERNEL" "$KERNEL_HEADERS" linux-firmware \
        "$INTEL_DRIVERS" nano plymouth wget git curl networkmanager grub efibootmgr \
        os-prober sudo "$FS_UTILS" fastfetch gvfs mtpfs htop "$BLUETOOTH"
    
    print_success "Base system terinstall. Lanjut ke langkah berikutnya."
}

# Fungsi untuk generate fstab
generate_fstab() {
    clear
    print_header "GENERATE FSTAB"
    
    genfstab -U /mnt >> /mnt/etc/fstab
    
    print_success "fstab dibuat. Lanjut ke langkah berikutnya."
}

# Fungsi untuk chroot configuration
chroot_configuration() {
    clear
    print_header "CHROOT CONFIGURATION"
    
    # Masukkan konfigurasi ke file sementara
    cat > /mnt/chroot-config.sh <<EOF
#!/bin/bash
set -e

# Timezone
timedatectl set-timezone $TIMEZONE

# Locale
LOCALES=(
"aa_DJ.UTF-8 UTF-8"
"af_ZA.UTF-8 UTF-8"
"am_ET.UTF-8 UTF-8"
"ar_EG.UTF-8 UTF-8"
"ast_ES.UTF-8 UTF-8"
"be_BY.UTF-8 UTF-8"
"bg_BG.UTF-8 UTF-8"
"bn_BD.UTF-8 UTF-8"
"br_FR.UTF-8 UTF-8"
"bs_BA.UTF-8 UTF-8"
"ca_ES.UTF-8 UTF-8"
"cs_CZ.UTF-8 UTF-8"
"cy_GB.UTF-8 UTF-8"
"da_DK.UTF-8 UTF-8"
"de_AT.UTF-8 UTF-8"
"de_CH.UTF-8 UTF-8"
"de_DE.UTF-8 UTF-8"
"el_GR.UTF-8 UTF-8"
"en_AU.UTF-8 UTF-8"
"en_CA.UTF-8 UTF-8"
"en_GB.UTF-8 UTF-8"
"en_IE.UTF-8 UTF-8"
"en_NZ.UTF-8 UTF-8"
"en_US.UTF-8 UTF-8"
"en_ZA.UTF-8 UTF-8"
"eo.UTF-8 UTF-8"
"es_AR.UTF-8 UTF-8"
"es_CL.UTF-8 UTF-8"
"es_ES.UTF-8 UTF-8"
"es_MX.UTF-8 UTF-8"
"et_EE.UTF-8 UTF-8"
"eu_ES.UTF-8 UTF-8"
"fa_IR.UTF-8 UTF-8"
"fi_FI.UTF-8 UTF-8"
"fr_FR.UTF-8 UTF-8"
"fy_NL.UTF-8 UTF-8"
"ga_IE.UTF-8 UTF-8"
"gd_GB.UTF-8 UTF-8"
"gl_ES.UTF-8 UTF-8"
"gu_IN.UTF-8 UTF-8"
"he_IL.UTF-8 UTF-8"
"hi_IN.UTF-8 UTF-8"
"hr_HR.UTF-8 UTF-8"
"hu_HU.UTF-8 UTF-8"
"hy_AM.UTF-8 UTF-8"
"id_ID.UTF-8 UTF-8"
"is_IS.UTF-8 UTF-8"
"it_IT.UTF-8 UTF-8"
"ja_JP.UTF-8 UTF-8"
"ka_GE.UTF-8 UTF-8"
"kk_KZ.UTF-8 UTF-8"
"km_KH.UTF-8 UTF-8"
"kn_IN.UTF-8 UTF-8"
"ko_KR.UTF-8 UTF-8"
"lg_UG.UTF-8 UTF-8"
"lt_LT.UTF-8 UTF-8"
"lv_LV.UTF-8 UTF-8"
"mk_MK.UTF-8 UTF-8"
"ml_IN.UTF-8 UTF-8"
"mr_IN.UTF-8 UTF-8"
"ms_MY.UTF-8 UTF-8"
"mt_MT.UTF-8 UTF-8"
"nb_NO.UTF-8 UTF-8"
"nl_BE.UTF-8 UTF-8"
"nl_NL.UTF-8 UTF-8"
"nn_NO.UTF-8 UTF-8"
"oc_FR.UTF-8 UTF-8"
"pa_PK.UTF-8 UTF-8"
"pl_PL.UTF-8 UTF-8"
"pt_BR.UTF-8 UTF-8"
"pt_PT.UTF-8 UTF-8"
"ro_RO.UTF-8 UTF-8"
"ru_RU.UTF-8 UTF-8"
"ru_UA.UTF-8 UTF-8"
"si_LK.UTF-8 UTF-8"
"sk_SK.UTF-8 UTF-8"
"sl_SI.UTF-8 UTF-8"
"sq_AL.UTF-8 UTF-8"
"sr_RS.UTF-8 UTF-8"
"sv_SE.UTF-8 UTF-8"
"sw_KE.UTF-8 UTF-8"
"ta_IN.UTF-8 UTF-8"
"te_IN.UTF-8 UTF-8"
"tg_TJ.UTF-8 UTF-8"
"th_TH.UTF-8 UTF-8"
"tl_PH.UTF-8 UTF-8"
"tr_TR.UTF-8 UTF-8"
"uk_UA.UTF-8 UTF-8"
"vi_VN.UTF-8 UTF-8"
"wa_BE.UTF-8 UTF-8"
"xh_ZA.UTF-8 UTF-8"
"zh_CN.UTF-8 UTF-8"
"zh_HK.UTF-8 UTF-8"
"zh_SG.UTF-8 UTF-8"
"zh_TW.UTF-8 UTF-8"
"zu_ZA.UTF-8 UTF-8"
)

# Hapus komentar untuk semua locale
for locale in "\${LOCALES[@]}"; do
    sed -i "s/#\$locale/\$locale/" /etc/locale.gen
done

locale-gen
echo LANG=$LOCALE > /etc/locale.conf

# Hostname
echo $HOSTNAME > /etc/hostname

# Hosts file
cat > /etc/hosts <<EOL
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME
EOL

# Root password
echo "root:$ROOT_PASSWORD" | chpasswd

# User creation
useradd -m -G wheel,audio,video,storage $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Sudoers
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Multilib di chroot
if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    echo "" >> /etc/pacman.conf
    echo "[multilib]" >> /etc/pacman.conf
    echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
fi

pacman -Sy

# Third party repos
EOF

    # Tambahkan konfigurasi repository pihak ketiga
    for repo in "${THIRD_PARTY_REPOS[@]}"; do
        case $repo in
            cachyos)
                cat >> /mnt/chroot-config.sh <<EOF
# CachyOS repo
pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com
pacman-key --lsign-key F3B607488DB35A47
pacman -U --no-confirm 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-keyring-20240331-1-any.pkg.tar.zst' 'https://mirror.cachyos.org/repo/x86_64/cachyos/cachyos-mirrorlist-27-1-any.pkg.tar.zst'
EOF
                ;;
            jim-aur)
                cat >> /mnt/chroot-config.sh <<EOF
# Jim AUR repo
wget -qO- https://raw.githubusercontent.com/GNUWeeb/jim-aur/refs/heads/master/jim-aur.sh | bash
EOF
                ;;
            chaotic-aur)
                cat >> /mnt/chroot-config.sh <<EOF
# Chaotic AUR repo
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --no-confirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
EOF
                ;;
        esac
    done

    # Tambahkan konfigurasi desktop
    cat >> /mnt/chroot-config.sh <<EOF
# Display server dan desktop
EOF

    case $DESKTOP in
        no-desktop-server)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm openssh cockpit
systemctl enable sshd
systemctl enable cockpit
EOF
            ;;
        no-desktop-minimal)
            # Tidak ada desktop
            ;;
        budgie)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland budgie lightdm lightdm-slick-greeter
systemctl enable lightdm
EOF
            ;;
        cinnamon)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland cinnamon lightdm lightdm-slick-greeter
systemctl enable lightdm
EOF
            ;;
        cosmic)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland cosmic
systemctl enable cosmic-greeter
EOF
            ;;
        deepin)
            if [[ "$DEEPIN_EXTRA" == true ]]; then
                cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland deepin deepin-kwin lightdm lightdm-deepin-greeter deepin-extra
systemctl enable lightdm
EOF
            else
                cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland deepin deepin-kwin lightdm lightdm-deepin-greeter
systemctl enable lightdm
EOF
            fi
            ;;
        gnome)
            if [[ -n "$GNOME_EXTRA_OPTION" ]]; then
                cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland gnome $GNOME_EXTRA_OPTION
systemctl enable gdm
EOF
            else
                cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland gnome
systemctl enable gdm
EOF
            fi
            ;;
        gnome-flashback)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland gnome-flashback lightdm lightdm-slick-greeter
systemctl enable lightdm
EOF
            ;;
        kde-plasma)
            if [[ "$KDE_MOBILE" == true ]]; then
                cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland plasma-meta konsole kate $KDE_DM_OPTION plasma-mobile plasma-settings
systemctl enable $DISPLAY_MANAGER
EOF
            else
                cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland plasma-meta konsole kate $KDE_DM_OPTION
systemctl enable $DISPLAY_MANAGER
EOF
            fi
            ;;
        lxde)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland lxde lightdm lightdm-slick-greeter
systemctl enable lightdm
EOF
            ;;
        lxqt)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland lxqt lightdm lightdm-slick-greeter
systemctl enable lightdm
EOF
            ;;
        mate)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland mate mate-extra lightdm lightdm-slick-greeter
systemctl enable lightdm
EOF
            ;;
        pantheon)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland pantheon lightdm lightdm-pantheon-greeter
systemctl enable lightdm
EOF
            ;;
        xfce)
            cat >> /mnt/chroot-config.sh <<EOF
pacman -S --no-confirm xorg wayland xfce4 xfce4-goodies labwc lightdm lightdm-slick-greeter
systemctl enable lightdm
EOF
            ;;
        custom)
            cat >> /mnt/chroot-config.sh <<EOF
# Custom installation - silakan install desktop environment sendiri
pacman -S --no-confirm xorg wayland
EOF
            ;;
    esac

    # NetworkManager
    cat >> /mnt/chroot-config.sh <<EOF
# NetworkManager
systemctl enable NetworkManager
EOF

    # Enable periodic TRIM when installing on SSD/NVMe storage
    if [[ "$HAVE_SSD" == true ]] || [[ "$HAVE_NVME" == true ]]; then
        cat >> /mnt/chroot-config.sh <<EOF
# SSD/NVMe detected: enable periodic TRIM
systemctl enable fstrim.timer
EOF
    fi

    # GRUB bootloader installation
    cat >> /mnt/chroot-config.sh <<EOF
# GRUB bootloader installation
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Archie
grub-mkconfig -o /boot/grub/grub.cfg
EOF

    # Hapus file konfigurasi
    cat >> /mnt/chroot-config.sh <<EOF
# Cleanup
rm /chroot-config.sh
EOF

    # Jalankan script di chroot
    chmod +x /mnt/chroot-config.sh
    arch-chroot /mnt /chroot-config.sh
    
    print_success "Konfigurasi chroot selesai. Instalasi sudah berakhir."
}

# Fungsi untuk unmount dan reboot
finish_installation() {
    clear
    print_header "INSTALASI SELESAI"
    
    # Unmount
    umount -R /mnt
    
    print_success "Arch Linux berhasil diinstall!"
    echo ""
    read -r -p "Apakah Anda ingin reboot sekarang? [y/N]: " reboot_confirm
    
    if [[ "$reboot_confirm" =~ ^[Yy]$ ]]; then
        reboot
    else
        print_info "Silakan reboot secara manual"
    fi
}

# Fungsi utama
main() {
    clear
    print_header "ARCHIE INSTALLER - BAHASA INDONESIA"
    echo "Installer Arch Linux untuk laptop Intel (eMMC/SSD/NVMe)"
    echo ""
    
    # Cek root
    if [[ $EUID -ne 0 ]]; then
        print_error "Script ini harus dijalankan sebagai root"
        exit 1
    fi
    
    # Refresh repository
    refresh_repos
    
    # Detect storage
    detect_storage
    
    # Select storage
    select_main_storage
    select_home_storage
    
    # Partition
    partition_main_storage
    partition_home_storage
    
    # Mount
    mount_partitions
    
    # Select kernel
    select_kernel
    
    # Select desktop
    select_desktop
    
    # Third party repos
    select_third_party_repos
    
    # Locale
    configure_locale
    
    # Hostname
    configure_hostname
    
    # Users
    configure_users
    
    # Confirm
    confirm_installation
    
    # Install base system
    install_base_system
    
    # Generate fstab
    generate_fstab
    
    # Chroot configuration
    chroot_configuration
    
    # Finish
    finish_installation
}

# Jalankan fungsi utama
main