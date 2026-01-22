{
  description = "eFa5 NixOS migration (Postfix, Rspamd, MariaDB, MailWatch)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      envSystem = builtins.getEnv "NIX_SYSTEM";
      system = if envSystem != "" then envSystem else "x86_64-linux";
      lib = nixpkgs.lib;
      hostModule = ./hosts/nixos-vm.nix;
      mkEfaVm = vmSystem: lib.nixosSystem {
        system = vmSystem;
        modules = [
          (import "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix")
          self.nixosModules.core
          self.nixosModules.derivations
          self.nixosModules.firewall
          self.nixosModules.efaScripts
          self.nixosModules.postfix
          self.nixosModules.filtering
          self.nixosModules.mailscanner
          self.nixosModules.greylist
          self.nixosModules.geoip
          self.nixosModules.mariadb
          self.nixosModules.web
          self.nixosModules.efaInit
          ({ ... }: {
            networking.hostName = "efa-vm";
            time.timeZone = "Etc/UTC";
            services.postfix.enable = lib.mkDefault true;
            efa.mailscanner.enable = lib.mkDefault true;
            efa.greylist.enable = lib.mkDefault true;
            efa.geoip.enable = lib.mkDefault true;
            system.stateVersion = "24.11";
            efa.web.enableACME = lib.mkForce false;
            efa.web.forceSSL = lib.mkForce false;
            users.users.root.initialPassword = "nixos";
            users.users.nixos = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              initialPassword = "nixos";
            };
            virtualisation = {
              memorySize = if vmSystem == "aarch64-linux" then 1024 else 4096;
              cores = 2;
              graphics = vmSystem != "aarch64-linux";
              forwardPorts = [
                { from = "host"; host.port = 2222; guest.port = 22; }
                { from = "host"; host.port = 8025; guest.port = 25; }
                { from = "host"; host.port = 8080; guest.port = 80; }
                { from = "host"; host.port = 8443; guest.port = 443; }
                { from = "host"; host.port = 8587; guest.port = 587; }
              ];
            };
          })
        ];
      };
    in {
      nixosModules = {
        core = import ./modules/efa/core.nix;
        derivations = import ./modules/efa/derivations.nix;
        firewall = import ./modules/efa/firewall.nix;
        efaScripts = import ./modules/efa/scripts.nix;
        postfix = import ./modules/mail/postfix.nix;
        filtering = import ./modules/mail/filtering.nix;
        mailscanner = import ./modules/mail/mailscanner.nix;
        greylist = import ./modules/mail/greylist.nix;
        geoip = import ./modules/mail/geoip.nix;
        mariadb = import ./modules/database/mariadb.nix;
        web = import ./modules/web/interface.nix;
        efaInit = import ./modules/web/efa-init.nix;
      };

      nixosConfigurations = {
        efa = lib.nixosSystem {
          inherit system;
          modules =
            [
            self.nixosModules.core
            self.nixosModules.derivations
            self.nixosModules.firewall
            self.nixosModules.efaScripts
            self.nixosModules.postfix
            self.nixosModules.filtering
            self.nixosModules.mailscanner
            self.nixosModules.greylist
            self.nixosModules.mariadb
            self.nixosModules.web
            self.nixosModules.efaInit
            ]
            ++ lib.optionals (builtins.pathExists hostModule) [ hostModule ]
            ++ [
            ({ ... }: {
              networking.hostName = "efa";
              time.timeZone = "Etc/UTC";
              services.postfix.enable = lib.mkDefault true;
              efa.mailscanner.enable = lib.mkDefault true;
              efa.mailscanner.startService = true;
              efa.greylist.dbType = "MySQL";
              efa.web.enableACME = lib.mkForce false;
              efa.web.forceSSL = lib.mkForce false;
              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = true;
                  PermitRootLogin = "yes";
                };
              };
              efa.database.bootstrapSecrets = lib.mkDefault true;
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;
              boot.loader.efi.efiSysMountPoint = "/boot";
              services.mysql.settings.mariadb = {
                innodb_buffer_pool_size = lib.mkForce "256M";
                innodb_log_buffer_size = lib.mkForce "8M";
                innodb_log_file_size = lib.mkForce "64M";
              };
              # FileSystems: Define your root filesystem here or in hosts/nixos-vm.nix
              # To find your disk UUIDs, run: lsblk -f or blkid
              # This is a placeholder - you MUST customize the device UUID for your system
              fileSystems."/" = lib.mkDefault {
                device = "/dev/disk/by-uuid/CHANGE-THIS-TO-YOUR-ROOT-UUID";
                fsType = "ext4";
              };
              fileSystems."/boot" = lib.mkDefault {
                device = "/dev/disk/by-uuid/CHANGE-THIS-TO-YOUR-EFI-UUID";
                fsType = "vfat";
              };
              system.stateVersion = "24.11";
            })
          ];
        };
        efaAarch64 = lib.nixosSystem {
          system = "aarch64-linux";
          modules =
            [
            self.nixosModules.core
            self.nixosModules.derivations
            self.nixosModules.firewall
            self.nixosModules.efaScripts
            self.nixosModules.postfix
            self.nixosModules.filtering
            self.nixosModules.mailscanner
            self.nixosModules.greylist
            self.nixosModules.mariadb
            self.nixosModules.web
            self.nixosModules.efaInit
            ]
            ++ lib.optionals (builtins.pathExists hostModule) [ hostModule ]
            ++ [
            ({ ... }: {
              networking.hostName = "efa";
              time.timeZone = "Etc/UTC";
              services.postfix.enable = lib.mkDefault true;
              efa.mailscanner.enable = lib.mkDefault true;
              efa.mailscanner.startService = true;
              efa.greylist.enable = lib.mkDefault true;
              efa.greylist.dbType = "MySQL";
              efa.web.enableACME = lib.mkForce false;
              efa.web.forceSSL = lib.mkForce false;
              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = true;
                  PermitRootLogin = "yes";
                };
              };
              # Dev/VM convenience: create default DB secrets if missing
              efa.database.bootstrapSecrets = lib.mkDefault true;
              boot.loader.systemd-boot.enable = true;
              boot.loader.efi.canTouchEfiVariables = true;
              boot.loader.efi.efiSysMountPoint = "/boot";
              system.stateVersion = "24.11";
            })
          ];
        };
        efaVm = mkEfaVm "x86_64-linux";
        efaVmAarch64 = mkEfaVm "aarch64-linux";
        efaContainer = lib.nixosSystem {
          inherit system;
          modules = [
            self.nixosModules.core
            self.nixosModules.derivations
            self.nixosModules.firewall
            self.nixosModules.efaScripts
            self.nixosModules.postfix
            self.nixosModules.filtering
            self.nixosModules.mailscanner
            self.nixosModules.greylist
            self.nixosModules.mariadb
            self.nixosModules.web
            self.nixosModules.efaInit
            ({ ... }: {
              networking.hostName = "efa-container";
              time.timeZone = "Asia/Jakarta";
              services.postfix.enable = lib.mkDefault true;
              efa.mailscanner.enable = lib.mkDefault true;
              system.stateVersion = "24.11";
              efa.web.enableACME = lib.mkForce false;
              efa.web.forceSSL = lib.mkForce false;
              boot.loader.grub.device = "nodev";
              fileSystems."/" = {
                device = "tmpfs";
                fsType = "tmpfs";
              };
            })
          ];
        };
      };
    };
}
