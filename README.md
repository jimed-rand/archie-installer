# archie-installer

Arch Linux installer for Intel low-end/mid-end laptops with eMMC storage.

## Description

This script is designed specifically for installing Arch Linux on Intel low-end/mid-end laptops with eMMC storage (such as ADVAN 1405 and similar models). This script provides automated installation with full Intel hardware support, including complete Intel drivers, and various desktop environment options.

## Features

- **Automatic Hardware Detection**: Automatically detects eMMC and SSD
- **Automatic Partitioning**: Creates ESP, swap, and root partitions with optimal configuration
- **Kernel Selection**: Supports various Linux kernels (linux, linux-lts, linux-zen, linux-hardened)
- **Full Desktop Support**: Various desktop environment options (GNOME, KDE Plasma, XFCE, etc.)
- **Complete Intel Drivers**: Automatic installation of Intel drivers including sof-firmware and hardware rendering
- **Third Party Repositories**: Optional activation of CachyOS, Jim AUR, or Chaotic AUR
- **Localization**: Support for various locales and timezones
- **Multi-language**: Available in Indonesian and English

## Supported Hardware

### Specific Models
- **ADVAN 1405 Series** (Intel N4020, eMMC 128GB)
- **ADVAN Soulmate 1405**
- **ADVAN TBook Transformers 1405**

### General Compatibility
- Intel low-end/mid-end CPUs (Celeron, Pentium, Core i3 series)
- x86_64 and x86_64-v2 architecture
- eMMC storage (mmcblk0/mmcblk1)
- Intel integrated graphics
- Laptops with eMMC storage (~128GB)

### Not Supported
- AMD CPUs and GPUs
- Intel discrete GPUs (non-Intel)
- High-end/latest Intel CPUs
- Enterprise servers

## Requirements

- Arch Linux ISO (latest)
- Active internet connection (required)
- eMMC or SSD storage
- Minimum 4GB RAM (8GB recommended)
- Root access (sudo)

## Usage

### Step 1: Boot Arch Linux ISO
Boot from Arch Linux ISO USB on the target laptop.

### Step 2: Download Script
```bash
# Clone repository
git clone <repository-url>
cd archie-installer

# Or download directly
wget <raw-url>/start-here.sh
chmod +x start-here.sh
```

### Step 3: Run Script
```bash
sudo ./start-here.sh
```

### Step 4: Follow Instructions
The script will:
1. Detect laptop hardware
2. Select language (Indonesian/English)
3. Determine laptop model and appropriate installer
4. Start the installation process

## Installation Options

### Partitioning
- **ESP**: 256MB (FAT32, boot & esp flags)
- **Swap**: 4-10GB (automatic configuration)
- **Root**: Remaining storage (XFS default, ext4 optional)
- **Home**: Optional (separate or on SSD if available)

### Linux Kernels
- `linux` - Standard kernel
- `linux-lts` - Long Term Support
- `linux-zen` - Optimized kernel
- `linux-hardened` - Hardened kernel

### Desktop Environments
1. **No Desktop (Home Server)** - With OpenSSH and Cockpit
2. **No Desktop (Minimal)** - Minimal TTY/CLI
3. **Budgie** - Desktop from Solus Project
4. **Cinnamon** - Desktop from Linux Mint
5. **COSMIC** - Desktop from System76 (Rust-based)
6. **Deepin DE** - Desktop from Deepin
7. **GNOME** - Desktop from GNOME Project
8. **GNOME Flashback** - GNOME with classic appearance
9. **KDE Plasma** - Desktop from KDE
10. **LXDE** - Lightweight desktop
11. **LXQt** - Lightweight Qt desktop
12. **MATE** - Successor to GNOME 2
13. **Pantheon** - Desktop from elementary OS
14. **XFCE** - Lightweight X11 desktop
15. **Custom** - Custom installation for advanced users

### Third Party Repositories
- **CachyOS** - Repository with optimized packages
- **Jim AUR** - AUR repository from jimedrand (OBS)
- **Chaotic AUR** - AUR repository from Garuda Linux team

## Project Structure

```
archie-installer/
├── start-here.sh              # Preliminary detection script
├── scripts/
│   ├── install-id.sh          # Indonesian installer
│   └── install-en.sh          # English installer
├── README.md                  # This documentation
└── LICENSE                    # LGPL-2.1 license
```

## Recent Changes

- **Project Renaming**: The project was renamed from `archie-emmc-installer` to `archie-installer` to reflect broader compatibility and cleanup references across scripts.
- **English Translation**: Added full translation support (`scripts/install-en.sh`) with translated interactive prompts, system logs, display headers, user choices, and inline comments.
- **Multi-language Support**: Integrated language selection (Indonesian / English) directly inside the initialization stage of `start-here.sh`.
- **Default Locale & Timezone**: Configured `en_US.UTF-8` locale and `Australia/Sydney` timezone as defaults for the English installation.

## License

This project is licensed under the GNU Lesser General Public License v2.1. See the [LICENSE](LICENSE) file for more details.

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a branch for the new feature
3. Commit the changes
4. Push to the branch
5. Create a Pull Request

## Support

For issues or questions:
- Open an issue in the repository
- Check official Arch Linux documentation
- Visit Arch Linux forums

## Disclaimer

This script is provided "as is" without warranty. Users are fully responsible for the use of this script. Always backup important data before installation.