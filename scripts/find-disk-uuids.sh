#!/usr/bin/env bash
# Helper script to find disk UUIDs for fileSystems configuration

echo "=== Finding disk UUIDs for NixOS fileSystems configuration ==="
echo ""
echo "Method 1: Using lsblk"
echo "-------------------"
lsblk -f
echo ""
echo "Method 2: Using blkid"
echo "-------------------"
blkid
echo ""
echo "Method 3: Using findmnt (currently mounted filesystems)"
echo "-------------------"
findmnt -D -n -o SOURCE,TARGET,FSTYPE,UUID
echo ""
echo "=== Instructions ==="
echo "1. Find the UUID for your root filesystem (usually mounted on /)"
echo "2. Find the UUID for your EFI/boot filesystem (usually mounted on /boot)"
echo "3. Edit flake.nix or create hosts/nixos-vm.nix with these UUIDs"
echo ""
echo "Example fileSystems configuration:"
echo '  fileSystems."/" = {'
echo '    device = "/dev/disk/by-uuid/YOUR-ROOT-UUID-HERE";'
echo '    fsType = "ext4";'
echo '  };'
echo '  fileSystems."/boot" = {'
echo '    device = "/dev/disk/by-uuid/YOUR-EFI-UUID-HERE";'
echo '    fsType = "vfat";'
echo '  };'
