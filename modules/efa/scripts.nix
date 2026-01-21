{ config, lib, pkgs, ... }:
let
  srcCfg = config.efa.sources;
  efaRoot = srcCfg.efaSrcRoot;
  efaBaseRoot = srcCfg.efaBaseSrcRoot;
  
  # NixOS-compatible eFa-Commit script
  efaCommitScript = pkgs.writeShellScriptBin "eFa-Commit" (builtins.readFile ./eFa-Commit-NixOS);
in {
  config = lib.mkMerge [
    (lib.mkIf (efaRoot != null) {
      systemd.tmpfiles.rules = [
        "d /var/eFa 0755 root root -"
        "d /var/eFa/lib 0755 root root -"
        "d /var/eFa/lib/eFa-Configure 0755 root root -"
        "d /var/eFa/lib/token 0755 root root -"
        "d /var/eFa/lib/selinux 0755 root root -"
        "d /usr/src/eFa 0755 root root -"
        "L+ /var/eFa/lib/selinux/eFavmtools.te - - - - ${efaRoot}/eFa/eFavmtools.te"
        "L+ /var/eFa/lib/selinux/eFahyperv.te - - - - ${efaRoot}/eFa/eFahyperv.te"
        "L+ /var/eFa/lib/selinux/eFaqemu.te - - - - ${efaRoot}/eFa/eFaqemu.te"
        "L+ /var/eFa/lib/selinux/eFa.fc - - - - ${efaRoot}/eFa/eFa.fc"
        "L+ /var/eFa/lib/selinux/eFa9.te - - - - ${efaRoot}/eFa/eFa9.te"
        "L+ /var/eFa/lib/token/CustomAction.pm - - - - ${efaRoot}/eFa/CustomAction.pm"
        "L+ /var/eFa/lib/eFa-Configure/func_apachesettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_apachesettings"
        "L+ /var/eFa/lib/eFa-Configure/func_askcleandeliver - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_askcleandeliver"
        "L+ /var/eFa/lib/eFa-Configure/func_askdccservers - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_askdccservers"
        "L+ /var/eFa/lib/eFa-Configure/func_askhighspammailwatch - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_askhighspammailwatch"
        "L+ /var/eFa/lib/eFa-Configure/func_askmalwarepatrol - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_askmalwarepatrol"
        "L+ /var/eFa/lib/eFa-Configure/func_askmaxsize - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_askmaxsize"
        "L+ /var/eFa/lib/eFa-Configure/func_askmaxsizemailwatch - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_askmaxsizemailwatch"
        "L+ /var/eFa/lib/eFa-Configure/func_asknonspam - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_asknonspam"
        "L+ /var/eFa/lib/eFa-Configure/func_askspam - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_askspam"
        "L+ /var/eFa/lib/eFa-Configure/func_asksigrules - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_asksigrules"
        "L+ /var/eFa/lib/eFa-Configure/func_backup - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_backup"
        "L+ /var/eFa/lib/eFa-Configure/func_dkim_dmarc - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_dkim_dmarc"
        "L+ /var/eFa/lib/eFa-Configure/func_fail2ban - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_fail2ban"
        "L+ /var/eFa/lib/eFa-Configure/func_getipsettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_getipsettings"
        "L+ /var/eFa/lib/eFa-Configure/func_greylisting - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_greylisting"
        "L+ /var/eFa/lib/eFa-Configure/func_ipsettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_ipsettings"
        "L+ /var/eFa/lib/eFa-Configure/func_letsencrypt - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_letsencrypt"
        "L+ /var/eFa/lib/eFa-Configure/func_mailsettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_mailsettings"
        "L+ /var/eFa/lib/eFa-Configure/func_mailwatchsettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_mailwatchsettings"
        "L+ /var/eFa/lib/eFa-Configure/func_maintenance - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_maintenance"
        "L+ /var/eFa/lib/eFa-Configure/func_maxmind - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_maxmind"
        "L+ /var/eFa/lib/eFa-Configure/func_peruser - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_peruser"
        "L+ /var/eFa/lib/eFa-Configure/func_recovermariadb - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_recovermariadb"
        "L+ /var/eFa/lib/eFa-Configure/func_resetadmin - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_resetadmin"
        "L+ /var/eFa/lib/eFa-Configure/func_retention - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_retention"
        "L+ /var/eFa/lib/eFa-Configure/func_setipsettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_setipsettings"
        "L+ /var/eFa/lib/eFa-Configure/func_spamsettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_spamsettings"
        "L+ /var/eFa/lib/eFa-Configure/func_systemrestore - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_systemrestore"
        "L+ /var/eFa/lib/eFa-Configure/func_trustednetworks - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_trustednetworks"
        "L+ /var/eFa/lib/eFa-Configure/func_tunables - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_tunables"
        "L+ /var/eFa/lib/eFa-Configure/func_tunables_children - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_tunables_children"
        "L+ /var/eFa/lib/eFa-Configure/func_tunables_procdb - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_tunables_procdb"
        "L+ /var/eFa/lib/eFa-Configure/func_virussettings - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_virussettings"
        "L+ /var/eFa/lib/eFa-Configure/func_webmin - - - - ${efaRoot}/eFa/lib-eFa-Configure/func_webmin"
        "L+ /usr/sbin/eFa-Configure - - - - ${efaRoot}/eFa/eFa-Configure"
        "L+ /usr/sbin/eFa-Monitor-cron - - - - ${efaRoot}/eFa/eFa-Monitor-cron"
        "L+ /usr/sbin/eFa-Backup - - - - ${efaRoot}/eFa/eFa-Backup"
        "L+ /usr/sbin/eFa-Weekly-DMARC - - - - ${efaRoot}/eFa/eFa-Weekly-DMARC"
        "L+ /usr/sbin/eFa-Daily-DMARC - - - - ${efaRoot}/eFa/eFa-Daily-DMARC"
        "L+ /etc/cron.daily/eFa-Backup.cron - - - - ${efaRoot}/eFa/eFa-Backup.cron"
        "L+ /etc/cron.daily/eFa-Tokens.cron - - - - ${efaRoot}/eFa/eFa-Tokens.cron"
        "L+ /etc/logrotate.d/eFa-logrotate - - - - ${efaRoot}/eFa/eFa-logrotate"
        "L+ /etc/sysconfig/eFa-Monitor - - - - ${efaRoot}/eFa/eFa-Monitor"
        "L+ /usr/src/eFa/updates - - - - ${efaRoot}/updates"
      ];
    })
    (lib.mkIf (efaBaseRoot != null) {
      systemd.tmpfiles.rules = [
        "d /usr/src/eFa 0755 root root -"
        "d /etc/eFa 0775 root nginx -"
        "L+ /usr/src/eFa/eFa-settings.inc - - - - ${efaBaseRoot}/eFa-settings.inc"
        "L+ /usr/src/eFa/mariadb - - - - ${efaBaseRoot}/mariadb"
        "L+ /usr/sbin/eFa-Init - - - - ${efaBaseRoot}/eFa/eFa-Init"
        "L+ /usr/sbin/eFa-Post-Init - - - - ${efaBaseRoot}/eFa/eFa-Post-Init"
        # Symlink eFa-Commit to the NixOS version in /run/current-system/sw/bin
        "L+ /usr/sbin/eFa-Commit - - - - /run/current-system/sw/bin/eFa-Commit"
      ];
      
      # Add NixOS-compatible eFa-Commit to system packages
      environment.systemPackages = [ efaCommitScript ];
    })
  ];
}
