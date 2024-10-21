# Void Linux installer (Full Disk Encryption)

The script is entirely based on "Full Disk Encryption" from [Void docs](https://docs.voidlinux.org/installation/guides/fde.html).

## Installation

Just clone the repo:
```bash
xbps-install -Syu xbps git
git clone https://github.com/IvnLum/Void-Linux-Crypt-Install
cd Void-Linux-Crypt-Install

# You must edit target partitions (ENV variables) inside script

./cryptinst.sh
```
