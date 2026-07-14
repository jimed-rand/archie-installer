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

# When this script is executed via a pipe (e.g. `wget -qO- <url> | bash` or
# `curl -sL <url> | bash`), stdin is consumed by the pipe carrying the script
# itself, so `read -p` prompts below would silently fail or read garbage
# instead of waiting for real user input. Re-point stdin at the controlling
# terminal so all interactive prompts work correctly regardless of how the
# script was launched.
if [ ! -t 0 ]; then
    if [ -e /dev/tty ]; then
        exec < /dev/tty
    else
        echo "ERROR: This installer requires an interactive terminal (no /dev/tty available)." >&2
        echo "Download the script and run it directly instead of piping it into bash." >&2
        exit 1
    fi
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to detect system information
detect_system() {
    clear
    print_header "DETECTING SYSTEM INFORMATION"
    
    # Get CPU info
    CPU_MODEL=$(grep 'model name' /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
    CPU_VENDOR=$(grep 'vendor_id' /proc/cpuinfo | head -n1 | cut -d':' -f2 | xargs)
    
    # Get storage info
    EMMC_DEVICE=""
    SSD_DEVICE=""
    NVME_DEVICE=""
    
    if lsblk | grep -q "mmcblk0"; then
        EMMC_DEVICE="/dev/mmcblk0"
    elif lsblk | grep -q "mmcblk1"; then
        EMMC_DEVICE="/dev/mmcblk1"
    fi
    
    if lsblk | grep -q "sda"; then
        SSD_DEVICE="/dev/sda"
    fi
    
    if lsblk | grep -q "nvme0n1"; then
        NVME_DEVICE="/dev/nvme0n1"
    elif lsblk | grep -q "nvme1n1"; then
        NVME_DEVICE="/dev/nvme1n1"
    fi
    
    # Get memory info
    TOTAL_MEM=$(free -h | grep Mem | awk '{print $2}')
    
    # Detect laptop model
    LAPTOP_MODEL="unknown"
    if dmidecode &>/dev/null; then
        LAPTOP_MODEL=$(dmidecode -s system-product-name 2>/dev/null || echo "unknown")
    fi
    
    echo "CPU Model: $CPU_MODEL"
    echo "CPU Vendor: $CPU_VENDOR"
    echo "Total Memory: $TOTAL_MEM"
    echo "eMMC Device: ${EMMC_DEVICE:-Not detected}"
    echo "SSD Device: ${SSD_DEVICE:-Not detected}"
    echo "NVMe Device: ${NVME_DEVICE:-Not detected}"
    echo "Laptop Model: $LAPTOP_MODEL"
}

# Function to check if system is supported
check_support() {
    clear
    print_header "CHECKING SYSTEM SUPPORT"
    
    # Check if CPU is Intel
    if [[ "$CPU_VENDOR" != "GenuineIntel" ]]; then
        print_error "This installer only supports Intel CPUs"
        return 1
    fi
    
    # Check if CPU is x86_64
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" ]]; then
        print_error "This installer only supports x86_64 architecture"
        return 1
    fi
    
    # Check if storage exists (eMMC, SSD, or NVMe)
    if [[ -z "$EMMC_DEVICE" ]] && [[ -z "$SSD_DEVICE" ]] && [[ -z "$NVME_DEVICE" ]]; then
        print_warning "No storage device detected (eMMC/SSD/NVMe)."
        print_warning "This installer is designed for low-end/mid-end devices with eMMC, SSD, or NVMe storage."
    fi
    
    # Check for discrete GPU (not supported)
    if lspci | grep -qi "nvidia\|amd.*radeon"; then
        print_error "Discrete GPU detected. This installer only supports Intel integrated graphics."
        return 1
    fi
    
    print_success "System is supported"
    return 0
}

# Function to select language
select_language() {
    clear
    print_header "LANGUAGE SELECTION / PILIH BAHASA"
    
    echo "1. Bahasa Indonesia"
    echo "2. English"
    echo ""
    read -r -p "Select language / Pilih bahasa [1-2]: " lang_choice
    
    case $lang_choice in
        1)
            INSTALLER_SCRIPT="install-id.sh"
            echo "Bahasa Indonesia dipilih"
            ;;
        2)
            INSTALLER_SCRIPT="install-en.sh"
            echo "English selected"
            ;;
        *)
            print_error "Invalid choice / Pilihan tidak valid"
            exit 1
            ;;
    esac
}

# Function to determine laptop model script
determine_model_script() {
    clear
    print_header "DETERMINING INSTALLER SCRIPT"
    
    # Check for specific models
    case "$LAPTOP_MODEL" in
        *ADVA*|*Advan*|*ADVN*)
            if [[ "$LAPTOP_MODEL" == *"1405"* ]] || [[ "$LAPTOP_MODEL" == *"Soulmate"* ]]; then
                MODEL="advan-1405"
                print_success "Detected: ADVAN 1405 Series"
            elif [[ "$LAPTOP_MODEL" == *"5G"* ]] || [[ "$LAPTOP_MODEL" == *"5G+"* ]]; then
                MODEL="advan-5g"
                print_success "Detected: ADVAN 5G Series"
            elif [[ "$LAPTOP_MODEL" == *"War"* ]] || [[ "$LAPTOP_MODEL" == *"WAR"* ]]; then
                MODEL="advan-war"
                print_success "Detected: ADVAN War Series"
            elif [[ "$LAPTOP_MODEL" == *"Max"* ]] || [[ "$LAPTOP_MODEL" == *"MAX"* ]]; then
                MODEL="advan-max"
                print_success "Detected: ADVAN Max Series"
            elif [[ "$LAPTOP_MODEL" == *"Pro"* ]] || [[ "$LAPTOP_MODEL" == *"PRO"* ]]; then
                MODEL="advan-pro"
                print_success "Detected: ADVAN Pro Series"
            elif [[ "$LAPTOP_MODEL" == *"Elite"* ]] || [[ "$LAPTOP_MODEL" == *"ELITE"* ]]; then
                MODEL="advan-elite"
                print_success "Detected: ADVAN Elite Series"
            elif [[ "$LAPTOP_MODEL" == *"Plus"* ]] || [[ "$LAPTOP_MODEL" == *"PLUS"* ]]; then
                MODEL="advan-plus"
                print_success "Detected: ADVAN Plus Series"
            else
                MODEL="advan-generic"
                print_success "Detected: ADVAN Generic"
            fi
            ;;
        *Chromebook*|*CHROMEBOOK*)
            MODEL="chromebook-jailbroken"
            print_success "Detected: Jailbroken Intel Chromebook"
            ;;
        *LattePanda*)
            if [[ "$LAPTOP_MODEL" == *"Alpha"* ]] || [[ "$LAPTOP_MODEL" == *"ALPHA"* ]]; then
                MODEL="lattepanda-alpha"
                print_success "Detected: LattePanda Alpha"
            elif [[ "$LAPTOP_MODEL" == *"Delta"* ]] || [[ "$LAPTOP_MODEL" == *"DELTA"* ]]; then
                MODEL="lattepanda-delta"
                print_success "Detected: LattePanda Delta"
            elif [[ "$LAPTOP_MODEL" == *"3"* ]] || [[ "$LAPTOP_MODEL" == *"Sigma"* ]]; then
                MODEL="lattepanda-3"
                print_success "Detected: LattePanda 3 / Sigma"
            else
                MODEL="lattepanda"
                print_success "Detected: LattePanda (Generic)"
            fi
            ;;
        *ASUS*|*Asus*|*asus*)
            if [[ "$LAPTOP_MODEL" == *"Eee"* ]] || [[ "$LAPTOP_MODEL" == *"EEE"* ]]; then
                MODEL="asus-eee"
                print_success "Detected: ASUS Eee PC Series"
            elif [[ "$LAPTOP_MODEL" == *"VivoBook"* ]] || [[ "$LAPTOP_MODEL" == *"vivobook"* ]]; then
                MODEL="asus-vivobook"
                print_success "Detected: ASUS VivoBook Series"
            elif [[ "$LAPTOP_MODEL" == *"X Series"* ]] || [[ "$LAPTOP_MODEL" == *"X-series"* ]]; then
                MODEL="asus-x-series"
                print_success "Detected: ASUS X Series"
            else
                MODEL="asus-generic"
                print_success "Detected: ASUS Generic"
            fi
            ;;
        *Acer*|*ACER*)
            if [[ "$LAPTOP_MODEL" == *"Aspire"* ]] || [[ "$LAPTOP_MODEL" == *"aspire"* ]]; then
                MODEL="acer-aspire"
                print_success "Detected: Acer Aspire Series"
            elif [[ "$LAPTOP_MODEL" == *"One"* ]] || [[ "$LAPTOP_MODEL" == *"one"* ]]; then
                MODEL="acer-one"
                print_success "Detected: Acer One Series"
            elif [[ "$LAPTOP_MODEL" == *"Swift"* ]] || [[ "$LAPTOP_MODEL" == *"swift"* ]]; then
                MODEL="acer-swift"
                print_success "Detected: Acer Swift Series"
            else
                MODEL="acer-generic"
                print_success "Detected: Acer Generic"
            fi
            ;;
        *Lenovo*|*LENOVO*)
            if [[ "$LAPTOP_MODEL" == *"IdeaPad"* ]] || [[ "$LAPTOP_MODEL" == *"ideapad"* ]]; then
                MODEL="lenovo-ideapad"
                print_success "Detected: Lenovo IdeaPad Series"
            elif [[ "$LAPTOP_MODEL" == *"ThinkPad"* ]] || [[ "$LAPTOP_MODEL" == *"thinkpad"* ]]; then
                MODEL="lenovo-thinkpad"
                print_success "Detected: Lenovo ThinkPad Series"
            elif [[ "$LAPTOP_MODEL" == *"100S"* ]] || [[ "$LAPTOP_MODEL" == *"100s"* ]]; then
                MODEL="lenovo-100s"
                print_success "Detected: Lenovo 100S Series"
            else
                MODEL="lenovo-generic"
                print_success "Detected: Lenovo Generic"
            fi
            ;;
        *HP*|*hp*)
            if [[ "$LAPTOP_MODEL" == *"Stream"* ]] || [[ "$LAPTOP_MODEL" == *"stream"* ]]; then
                MODEL="hp-stream"
                print_success "Detected: HP Stream Series"
            elif [[ "$LAPTOP_MODEL" == *"Pavilion"* ]] || [[ "$LAPTOP_MODEL" == *"pavilion"* ]]; then
                MODEL="hp-pavilion"
                print_success "Detected: HP Pavilion Series"
            elif [[ "$LAPTOP_MODEL" == *"250 G"* ]] || [[ "$LAPTOP_MODEL" == *"255 G"* ]]; then
                MODEL="hp-250"
                print_success "Detected: HP 250/255 Series"
            else
                MODEL="hp-generic"
                print_success "Detected: HP Generic"
            fi
            ;;
        *Dell*|*DELL*)
            if [[ "$LAPTOP_MODEL" == *"Inspiron"* ]] || [[ "$LAPTOP_MODEL" == *"inspiron"* ]]; then
                MODEL="dell-inspiron"
                print_success "Detected: Dell Inspiron Series"
            elif [[ "$LAPTOP_MODEL" == *"Latitude"* ]] || [[ "$LAPTOP_MODEL" == *"latitude"* ]]; then
                MODEL="dell-latitude"
                print_success "Detected: Dell Latitude Series"
            else
                MODEL="dell-generic"
                print_success "Detected: Dell Generic"
            fi
            ;;
        *Zotac*|*ZOTAC*)
            MODEL="zotac"
            print_success "Detected: ZOTAC"
            ;;
        *NUC*)
            MODEL="intel-nuc"
            print_success "Detected: Intel NUC"
            ;;
        *Minisforum*)
            MODEL="minisforum"
            print_success "Detected: Minisforum"
            ;;
        *Beelink*)
            MODEL="beelink"
            print_success "Detected: Beelink"
            ;;
        *Chuwi*)
            if [[ "$LAPTOP_MODEL" == *"HeroBook"* ]] || [[ "$LAPTOP_MODEL" == *"Herobook"* ]]; then
                MODEL="chuwi-herobook"
                print_success "Detected: CHUWI HeroBook"
            elif [[ "$LAPTOP_MODEL" == *"AeroBook"* ]] || [[ "$LAPTOP_MODEL" == *"Aerobook"* ]]; then
                MODEL="chuwi-aerobook"
                print_success "Detected: CHUWI AeroBook"
            else
                MODEL="chuwi-generic"
                print_success "Detected: CHUWI Generic"
            fi
            ;;
        *Teclast*)
            MODEL="teclast"
            print_success "Detected: Teclast"
            ;;
        *Cube*)
            MODEL="cube"
            print_success "Detected: Cube"
            ;;
        *PiPO*)
            MODEL="pipo"
            print_success "Detected: PiPO"
            ;;
        *VOYO*)
            MODEL="voyo"
            print_success "Detected: VOYO"
            ;;
        *Jumper*)
            MODEL="jumper"
            print_success "Detected: Jumper"
            ;;
        *Meebook*)
            MODEL="meebook"
            print_success "Detected: Meebook"
            ;;
        *Gateway*)
            MODEL="gateway"
            print_success "Detected: Gateway"
            ;;
        *Medion*)
            MODEL="medion"
            print_success "Detected: Medion"
            ;;
        *Packard*|*PACKARD*)
            MODEL="packard-bell"
            print_success "Detected: Packard Bell"
            ;;
        *Toshiba*|*TOSHIBA*)
            MODEL="toshiba"
            print_success "Detected: Toshiba"
            ;;
        *Fujitsu*|*FUJITSU*)
            MODEL="fujitsu"
            print_success "Detected: Fujitsu"
            ;;
        *MSI*)
            MODEL="msi"
            print_success "Detected: MSI"
            ;;
        *Razer*|*RAZER*)
            MODEL="razer"
            print_success "Detected: Razer"
            ;;
        *Microsoft*|*Surface*)
            MODEL="surface"
            print_success "Detected: Microsoft Surface"
            ;;
        *Xiaomi*|*XIAOMI*)
            MODEL="xiaomi"
            print_success "Detected: Xiaomi"
            ;;
        *Huawei*|*HUAWEI*)
            MODEL="huawei"
            print_success "Detected: Huawei"
            ;;
        *Haier*|*HAIER*)
            MODEL="haier"
            print_success "Detected: Haier"
            ;;
        *Hisense*|*HISENSE*)
            MODEL="hisense"
            print_success "Detected: Hisense"
            ;;
        *LG*|*lg*)
            MODEL="lg"
            print_success "Detected: LG"
            ;;
        *Samsung*|*SAMSUNG*)
            MODEL="samsung"
            print_success "Detected: Samsung"
            ;;
        *Panasonic*|*PANASONIC*)
            MODEL="panasonic"
            print_success "Detected: Panasonic"
            ;;
        *Sony*|*SONY*)
            MODEL="sony"
            print_success "Detected: Sony"
            ;;
        *Sharp*|*SHARP*)
            MODEL="sharp"
            print_success "Detected: Sharp"
            ;;
        *NEC*)
            MODEL="nec"
            print_success "Detected: NEC"
            ;;
        *BenQ*)
            MODEL="benq"
            print_success "Detected: BenQ"
            ;;
        *ViewSonic*)
            MODEL="viewsonic"
            print_success "Detected: ViewSonic"
            ;;
        *AOpen*)
            MODEL="aopen"
            print_success "Detected: AOpen"
            ;;
        *Foxconn*)
            MODEL="foxconn"
            print_success "Detected: Foxconn"
            ;;
        *Compal*)
            MODEL="compal"
            print_success "Detected: Compal"
            ;;
        *Quanta*)
            MODEL="quanta"
            print_success "Detected: Quanta"
            ;;
        *Wistron*)
            MODEL="wistron"
            print_success "Detected: Wistron"
            ;;
        *Inventec*)
            MODEL="inventec"
            print_success "Detected: Inventec"
            ;;
        *Clevo*)
            MODEL="clevo"
            print_success "Detected: Clevo"
            ;;
        *Tongfang*)
            MODEL="tongfang"
            print_success "Detected: Tongfang"
            ;;
        *CWWK*)
            MODEL="cwwk"
            print_success "Detected: CWWK"
            ;;
        *Topton*)
            MODEL="topton"
            print_success "Detected: Topton"
            ;;
        *Kingdel*)
            MODEL="kingdel"
            print_success "Detected: Kingdel"
            ;;
        *Hystou*)
            MODEL="hystou"
            print_success "Detected: Hystou"
            ;;
        *Morefine*)
            MODEL="morefine"
            print_success "Detected: Morefine"
            ;;
        *GMK*)
            MODEL="gmk"
            print_success "Detected: GMK"
            ;;
        *ACEPC*)
            MODEL="acepc"
            print_success "Detected: ACEPC"
            ;;
        *ONEX*)
            MODEL="onex"
            print_success "Detected: ONEX"
            ;;
        *MeLE*)
            MODEL="mele"
            print_success "Detected: MeLE"
            ;;
        *Azulle*)
            MODEL="azulle"
            print_success "Detected: Azulle"
            ;;
        *Intel*|*intel*)
            MODEL="intel-generic"
            print_success "Detected: Intel Generic"
            ;;
        *)
            MODEL="generic-universal"
            print_success "Using: Generic Universal Intel installer (pre-Nxxx series, low-end/mid-end devices)"
            ;;
    esac
    
    # Check if the specific installer exists
    if [[ -f "scripts/${MODEL}-${INSTALLER_SCRIPT}" ]]; then
        INSTALLER_PATH="scripts/${MODEL}-${INSTALLER_SCRIPT}"
    elif [[ -f "scripts/${INSTALLER_SCRIPT}" ]]; then
        INSTALLER_PATH="scripts/${INSTALLER_SCRIPT}"
    else
        print_error "Installer script not found: $INSTALLER_PATH"
        exit 1
    fi
    
    echo "Using installer: $INSTALLER_PATH"
}

# Main execution
main() {
    clear
    print_header "ARCHIE eMMC INSTALLER"
    echo "Arch Linux Installer for any Intel low-end/mid-end Laptops (with storage eMMC/SSD/HDD/any)"
    echo ""
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root."
        exit 1
    fi
    
    # Gather system information: CPU, memory, storage devices (eMMC/SSD/NVMe), and laptop model
    echo "Detecting system hardware information..."
    detect_system
    
    # Validate system compatibility: Intel CPU, x86_64 architecture, storage availability, no discrete GPU
    echo "Validating system compatibility..."
    if ! check_support; then
        print_error "System is not compatible with this installer."
        exit 1
    fi
    
    # Select language
    echo "Selecting installation language..."
    select_language
    
    # Determine model script
    echo "Determining appropriate installer script for your device..."
    determine_model_script
    
    # Confirm installation
    print_header "INSTALLATION SUMMARY"
    echo "CPU: $CPU_MODEL"
    echo "Memory: $TOTAL_MEM"
    echo "eMMC: ${EMMC_DEVICE:-None}"
    echo "SSD: ${SSD_DEVICE:-None}"
    echo "NVMe: ${NVME_DEVICE:-None}"
    echo "Model: $LAPTOP_MODEL"
    echo "Installer: $INSTALLER_PATH"
    echo ""
    read -r -p "Continue with installation? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        print_success "Starting installation..."
        chmod +x "$INSTALLER_PATH"
        exec "$INSTALLER_PATH"
    else
        print_warning "Installation cancelled"
        exit 0
    fi
}

# Run main function
main