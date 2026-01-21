{ config, lib, pkgs, ... }:
let
  efaVersion = config.efa.version;
  efaSrc = pkgs.stdenvNoCC.mkDerivation {
    name = "efa-src-${efaVersion}";
    src = ../../upstream/eFa-5.0.0;
    patches = [
      ./patches/eFa-configure-apache-nixos.patch
    ];
    postPatch = ''
      substituteInPlace eFa/eFa-Configure \
        --replace-fail '    yum -y update' \
        '    echo "[eFa] NixOS: updates are handled declaratively."\n    echo "[eFa] Run nixos-rebuild switch instead."'

      substituteInPlace eFa/eFa-Configure \
        --replace-fail 'shopt -s extglob' \
        'shopt -s extglob\n\nif [[ -f /etc/NIXOS ]]; then\n  echo "[eFa] NixOS: configuration is declarative; edit NixOS config."\n  exit 0\nfi'

      substituteInPlace updates/update.sh \
        --replace-fail $'if [[ $instancetype != "lxc" ]]; then\n    cmd=\'checkmodule -M -m -o /var/eFa/lib/selinux/eFa.mod /var/eFa/lib/selinux/eFa9.te\'\n    execcmd\n    cmd=\'semodule_package -o /var/eFa/lib/selinux/eFa.pp -m /var/eFa/lib/selinux/eFa.mod -f /var/eFa/lib/selinux/eFa.fc\'\n    execcmd\n    cmd=\'semodule -i /var/eFa/lib/selinux/eFa.pp\'\n    execcmd\nfi\n' \
        $'if [[ $instancetype != "lxc" ]]; then\n    # NixOS: SELinux not enabled; skip policy update\n    :\nfi\n'
    '';
    installPhase = ''
      mkdir -p $out
      cp -a . $out/
    '';
  };
  efaBaseSrc = pkgs.stdenvNoCC.mkDerivation {
    name = "efa-base-src-${efaVersion}";
    src = ../../upstream/eFa-base-5.0.0;
    patches = [
      ./patches/eFa-base-apache-config-nixos.patch
      ./patches/eFa-base-efainit-config-nixos.patch
    ];
    postPatch = ''
      substituteInPlace eFa/eFa-Init \
        --replace-fail '# Copyright (C) 2013~2024 https://efa-project.org' \
        $'# Copyright (C) 2013~2024 https://efa-project.org\n\nif [[ -f /etc/NIXOS ]]; then\n  echo "[eFa] NixOS: eFa-Init is handled declaratively; use NixOS config."\n  exit 0\nfi\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail '# Copyright (C) 2013~2024 https://efa-project.org' \
        $'# Copyright (C) 2013~2024 https://efa-project.org\n\nif [[ -f /etc/NIXOS ]]; then\n  echo "[eFa] NixOS: eFa-Commit is handled declaratively; use NixOS config."\n  exit 0\nfi\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail $'func_Install-OpenVMTools(){\n    yum -y install glib2-devel pam-devel libdnet-devel gcc-c++ libicu-devel open-vm-tools\n    [ $? -ne 0 ] && exit 1\n    systemctl enable vmtoolsd\n    [ $? -ne 0 ] && exit 1\n    checkmodule -M -m -o /var/eFa/lib/selinux/eFavmtools.mod /var/eFa/lib/selinux/eFavmtools.te\n    [ $? -ne 0 ] && exit 1\n    semodule_package -o /var/eFa/lib/selinux/eFavmtools.pp -m /var/eFa/lib/selinux/eFavmtools.mod\n    [ $? -ne 0 ] && exit 1\n    semodule -i /var/eFa/lib/selinux/eFavmtools.pp\n    [ $? -ne 0 ] && exit 1\n}\n' \
        $'func_Install-OpenVMTools(){\n    # NixOS: guest tools should be configured declaratively\n    :\n}\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail $'func_Install-HyperVTools(){\n    yum -y install hyperv-tools hyperv-daemons hypervkvpd hypervvssd\n    [ $? -ne 0 ] && exit 1\n    systemctl enable hypervkvpd\n    [ $? -ne 0 ] && exit 1\n    systemctl enable hypervvssd\n    [ $? -ne 0 ] && exit 1\n    checkmodule -M -m -o /var/eFa/lib/selinux/eFahyperv.mod /var/eFa/lib/selinux/eFahyperv.te\n    [ $? -ne 0 ] && exit 1\n    semodule_package -o /var/eFa/lib/selinux/eFahyperv.pp -m /var/eFa/lib/selinux/eFahyperv.mod\n    [ $? -ne 0 ] && exit 1\n    semodule -i /var/eFa/lib/selinux/eFahyperv.pp\n    [ $? -ne 0 ] && exit 1\n}\n' \
        $'func_Install-HyperVTools(){\n    # NixOS: guest tools should be configured declaratively\n    :\n}\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail $'func_Install-QEMUAgent(){\n    yum -y install qemu-guest-agent\n    [ $? -ne 0 ] && exit 1\n    systemctl enable qemu-guest-agent\n    [ $? -ne 0 ] && exit 1\n    checkmodule -M -m -o /var/eFa/lib/selinux/eFaqemu.mod /var/eFa/lib/selinux/eFaqemu.te\n    [ $? -ne 0 ] && exit 1\n    semodule_package -o /var/eFa/lib/selinux/eFaqemu.pp -m /var/eFa/lib/selinux/eFaqemu.mod\n    [ $? -ne 0 ] && exit 1\n    semodule -i /var/eFa/lib/selinux/eFaqemu.pp\n    [ $? -ne 0 ] && exit 1\n}\n' \
        $'func_Install-QEMUAgent(){\n    # NixOS: guest tools should be configured declaratively\n    :\n}\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail $'clean=\'\\e[00m\'\n' \
        $'clean=\'\\e[00m\'\n\nsystemctl() {\n  local cmd=\"$1\"\n  shift || true\n  local svc=\"$1\"\n  case \"$svc\" in\n    mariadb) svc=\"mysql\" ;;\n    httpd) svc=\"nginx\" ;;\n    crond) svc=\"cron\" ;;\n    php-fpm) svc=\"phpfpm-mailwatch\" ;;\n  esac\n  if [[ \"$cmd\" =~ ^(enable|disable|start|restart|reload|try-restart)$ ]] && [[ -n \"$svc\" ]]; then\n    if ! command systemctl list-unit-files --type=service | grep -q \"^$svc.service\"; then\n      return 0\n    fi\n    command systemctl \"$cmd\" \"$svc\" \"$@\"\n  else\n    command systemctl \"$cmd\" \"$@\"\n  fi\n}\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail '  sed -i "/^#ServerName\s/ c\ServerName $HOSTNAME.$DOMAINNAME:80" /etc/httpd/conf/httpd.conf' \
        '  # NixOS: nginx config is declarative; skip httpd edits'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail '  sed -i "/^#ServerName\s/ c\ServerName $HOSTNAME.$DOMAINNAME:443" /etc/httpd/conf.d/ssl.conf' \
        '  :'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail $'    touch /.autorelabel\n    [ $? -ne 0 ] && exit 1\n' \
        $'    # NixOS: no SELinux relabel/enforcing\n    :\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail '    sed -i "/^SELINUX=/ c\SELINUX=enforcing" /etc/selinux/config' \
        '    :'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail $'  systemctl enable httpd\n  [ $? -ne 0 ] && exit 1\n' \
        $'  # NixOS: use nginx instead of httpd\n  systemctl enable nginx >/dev/null 2>&1 || true\n  systemctl enable php-fpm >/dev/null 2>&1 || true\n'

      substituteInPlace eFa/eFa-Commit \
        --replace-fail $'  systemctl enable firewalld\n  [ $? -ne 0 ] && exit 1\n  systemctl start firewalld\n  [ $? -ne 0 ] && exit 1\n  firewall-cmd --permanent --add-service=smtp\n  [ $? -ne 0 ] && exit 1\n  firewall-cmd --permanent --add-service=ssh\n  [ $? -ne 0 ] && exit 1\n  firewall-cmd --permanent --add-port 80/tcp\n  [ $? -ne 0 ] && exit 1\n  firewall-cmd --permanent --add-port 443/tcp\n  [ $? -ne 0 ] && exit 1\n  firewall-cmd --permanent --add-port 587/tcp\n  [ $? -ne 0 ] && exit 1\n  firewall-cmd --reload\n  [ $? -ne 0 ] && exit 1\n' \
        $'  # NixOS: firewall is declarative; skip firewalld actions\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...INITIALIZING SYSTEM, PLEASE WAIT... \';" /var/www/html/mailscanner/functions.php\n' \
        $'sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...INITIALIZING SYSTEM, PLEASE WAIT... \';" /var/www/html/mailscanner/functions.php\n\nsystemctl() {\n  local cmd=\"$1\"\n  shift || true\n  local svc=\"$1\"\n  case \"$svc\" in\n    mariadb) svc=\"mysql\" ;;\n    httpd) svc=\"nginx\" ;;\n    crond) svc=\"cron\" ;;\n    php-fpm) svc=\"phpfpm-mailwatch\" ;;\n  esac\n  if [[ \"$cmd\" =~ ^(enable|disable|start|restart|reload|try-restart)$ ]] && [[ -n \"$svc\" ]]; then\n    if ! command systemctl list-unit-files --type=service | grep -q \"^$svc.service\"; then\n      return 0\n    fi\n    command systemctl \"$cmd\" \"$svc\" \"$@\"\n  else\n    command systemctl \"$cmd\" \"$@\"\n  fi\n}\n\nhas_cmd() {\n  command -v \"$1\" >/dev/null 2>&1\n}\n\nhas_file() {\n  [[ -f \"$1\" ]]\n}\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'/bin/sa-update &\n' \
        $'if has_cmd sa-update; then\n  sa-update &\nfi\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'# Initial clamav unofficial sigs download\nsed -i \'/^enable_random/ c\\enable_random="no"\' /etc/clamav-unofficial-sigs/master.conf\nsystemctl stop clamav-unofficial-sigs\nsystemctl stop clamav-unofficial-sigs.timer\n/usr/sbin/clamav-unofficial-sigs.sh --force\nif [[ $? -ne 0 ]]; then\n    logger -p user.warn "eFa Post Init: ClamAV Unofficial Sigs download failed!  Please fix me to finish initializing eFa.  Retrying in 1 minute..."\n    sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...ERROR INITIALIZATING, CHECK clamav unofficial sigs... \';" /var/www/html/mailscanner/functions.php\n    rm -f /var/run/eFa-Post-Init.lock\n    exit 1\nfi\nsed -i \'/^enable_random/ c\\enable_random="yes"\' /etc/clamav-unofficial-sigs/master.conf\nsystemctl start clamav-unofficial-sigs\nsystemctl start clamav-unofficial-sigs.timer\n' \
        $'# Initial clamav unofficial sigs download\nif has_file /etc/clamav-unofficial-sigs/master.conf && has_file /usr/sbin/clamav-unofficial-sigs.sh; then\n  sed -i \'/^enable_random/ c\\enable_random="no"\' /etc/clamav-unofficial-sigs/master.conf\n  systemctl stop clamav-unofficial-sigs\n  systemctl stop clamav-unofficial-sigs.timer\n  /usr/sbin/clamav-unofficial-sigs.sh --force\n  if [[ $? -ne 0 ]]; then\n      logger -p user.warn "eFa Post Init: ClamAV Unofficial Sigs download failed!  Please fix me to finish initializing eFa.  Retrying in 1 minute..."\n      sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...ERROR INITIALIZATING, CHECK clamav unofficial sigs... \';" /var/www/html/mailscanner/functions.php\n      rm -f /var/run/eFa-Post-Init.lock\n      exit 1\n  fi\n  sed -i \'/^enable_random/ c\\enable_random="yes"\' /etc/clamav-unofficial-sigs/master.conf\n  systemctl start clamav-unofficial-sigs\n  systemctl start clamav-unofficial-sigs.timer\nfi\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'if [[ ! -f /var/lib/clamav/main.cvd ]]; then\n  systemctl stop clamd@scan\n\n  freshclam\n\n  systemctl start clamd@scan\n  if [[ $? -ne 0 ]]; then\n    # Error!  Try again...\n    logger -p user.warn "eFa Post Init: Clamd restart failed!  Please fix me to finish initializing eFa.  Retrying in 1 minute..."\n    sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...ERROR INITIALIZATING, CHECK CLAMD... \';" /var/www/html/mailscanner/functions.php\n    rm -f /var/run/eFa-Post-Init.lock\n    exit 1\n  fi\nfi\n' \
        $'if [[ ! -f /var/lib/clamav/main.cvd ]] && has_cmd freshclam; then\n  systemctl stop clamd@scan\n\n  freshclam\n\n  systemctl start clamd@scan\n  if [[ $? -ne 0 ]]; then\n    # Error!  Try again...\n    logger -p user.warn "eFa Post Init: Clamd restart failed!  Please fix me to finish initializing eFa.  Retrying in 1 minute..."\n    sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...ERROR INITIALIZATING, CHECK CLAMD... \';" /var/www/html/mailscanner/functions.php\n    rm -f /var/run/eFa-Post-Init.lock\n    exit 1\n  fi\nfi\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'# Fetch the initial public suffix list\ncurl -s https://publicsuffix.org/list/public_suffix_list.dat > /etc/opendmarc/public_suffix_list.dat\nif [[ $? -ne 0 ]]; then\n    logger -p user.warn "eFa Post Init: Unable to download the public suffix list!  Please fix me to finish initializing eFa.  Retrying in 1 minute..."\n    sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...ERROR INITIALIZATING, CHECK public suffix list... \';" /var/www/html/mailscanner/functions.php\n    rm -f /var/run/eFa-Post-Init.lock\n    exit 1\nfi\n' \
        $'# Fetch the initial public suffix list\nif has_cmd curl && [[ -d /etc/opendmarc ]]; then\n  curl -s https://publicsuffix.org/list/public_suffix_list.dat > /etc/opendmarc/public_suffix_list.dat\n  if [[ $? -ne 0 ]]; then\n      logger -p user.warn "eFa Post Init: Unable to download the public suffix list!  Please fix me to finish initializing eFa.  Retrying in 1 minute..."\n      sed -i "/^    echo \' running on \' . efa_version/ c\\    echo \' running on \' . efa_version() . \' ...ERROR INITIALIZATING, CHECK public suffix list... \';" /var/www/html/mailscanner/functions.php\n      rm -f /var/run/eFa-Post-Init.lock\n      exit 1\n  fi\nfi\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'# Late Asynchronous tasks\nsamplepath=\'spamassassin\'\n/usr/bin/sa-learn -p /etc/MailScanner/spamassassin.conf --spam --file /usr/share/doc/$samplepath/sample-spam.txt &\n/usr/bin/sa-learn -p /etc/MailScanner/spamassassin.conf --ham --file /usr/share/doc/$samplepath/sample-nonspam.txt &\nsu -l -c "/bin/cat /usr/share/doc/$samplepath/sample-spam.txt | razor-report -d --verbose" -s /bin/bash postfix &\n/usr/bin/mailwatch/tools/Cron_jobs/mailwatch_update_sarules.php &\n' \
        $'# Late Asynchronous tasks\nsamplepath=\'spamassassin\'\nif has_cmd sa-learn; then\n  /usr/bin/sa-learn -p /etc/MailScanner/spamassassin.conf --spam --file /usr/share/doc/$samplepath/sample-spam.txt &\n  /usr/bin/sa-learn -p /etc/MailScanner/spamassassin.conf --ham --file /usr/share/doc/$samplepath/sample-nonspam.txt &\nfi\nif has_cmd razor-report && has_cmd su; then\n  su -l -c "/bin/cat /usr/share/doc/$samplepath/sample-spam.txt | razor-report -d --verbose" -s /bin/bash postfix &\nfi\nif has_file /usr/bin/mailwatch/tools/Cron_jobs/mailwatch_update_sarules.php; then\n  /usr/bin/mailwatch/tools/Cron_jobs/mailwatch_update_sarules.php &\nfi\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'if [[ ! -f /etc/postfix/ssl/dhparam.pem ]]; then\n  /usr/bin/openssl dhparam -out /etc/postfix/ssl/dhparam.pem 2048\n  /usr/sbin/postconf -e "smtpd_tls_dh1024_param_file = /etc/postfix/ssl/dhparam.pem"\n  cat /etc/postfix/ssl/dhparam.pem >> /etc/pki/tls/certs/localhost.crt\nfi\n' \
        $'if [[ ! -f /etc/postfix/ssl/dhparam.pem ]] && has_cmd openssl; then\n  /usr/bin/openssl dhparam -out /etc/postfix/ssl/dhparam.pem 2048\n  /usr/sbin/postconf -e "smtpd_tls_dh1024_param_file = /etc/postfix/ssl/dhparam.pem"\n  if has_file /etc/pki/tls/certs/localhost.crt; then\n    cat /etc/postfix/ssl/dhparam.pem >> /etc/pki/tls/certs/localhost.crt\n  fi\nfi\n'

      substituteInPlace eFa/eFa-Post-Init \
        --replace-fail $'systemctl reload httpd\nif [[ $? -ne 0 ]]; then\n  # Apache Error!\n  logger -p user.warn "eFa Post Init: Apache reload failed!  Please fix me to finish initializing eFa."\nfi\n' \
        $'systemctl reload nginx >/dev/null 2>&1 || true\n'

      substituteInPlace service-config-5.0.0.sh \
        --replace-fail $'echo "Configuring services..."\n' \
        $'echo "Configuring services..."\n\nsystemctl() {\n  local cmd=\"$1\"\n  shift || true\n  local svc=\"$1\"\n  case \"$svc\" in\n    mariadb) svc=\"mysql\" ;;\n    httpd) svc=\"nginx\" ;;\n    crond) svc=\"cron\" ;;\n    php-fpm) svc=\"phpfpm-mailwatch\" ;;\n  esac\n  if [[ \"$cmd\" =~ ^(enable|disable|start|restart|reload|try-restart)$ ]] && [[ -n \"$svc\" ]]; then\n    if ! command systemctl list-unit-files --type=service | grep -q \"^$svc.service\"; then\n      return 0\n    fi\n    command systemctl \"$cmd\" \"$svc\" \"$@\"\n  else\n    command systemctl \"$cmd\" \"$@\"\n  fi\n}\n'

      substituteInPlace service-config-5.0.0.sh \
        --replace-fail $'if [[ "$instancetype" != "lxc" ]]; then\n  sed -i "/^SELINUX=/ c\\SELINUX=permissive" /etc/selinux/config\nfi\n' \
        $'if [[ "$instancetype" != "lxc" ]]; then\n  # NixOS: no SELinux mode change needed\n  :\nfi\n'

      substituteInPlace eFa-config-5.0.0.sh \
        --replace-fail $'# Is this a full vm or physical and not a container?\nif [[ "$instancetype" != "lxc" ]]; then\n    # Needed for apache to access postfix\n    setsebool -P daemons_enable_cluster_mode 1\n\n    # Needed for apache to exec binaries on server side\n    setsebool -P httpd_ssi_exec 1\n\n    # Needed for clamd to access system\n    setsebool -P antivirus_can_scan_system 1\n    setsebool -P clamd_use_jit 1\n\n    # Needed for mailscanner to bind to tcp_socket\n    setsebool -P nis_enabled 1\n\n    # Needed for mailscanner to preserve tmpfs\n    setsebool -P rsync_full_access 1\n\n    # Needed for httpd to connect to razor\n    setsebool -P httpd_can_network_connect 1\n\n    # Allow httpd to write content\n    setsebool -P httpd_unified 1\n\n    # Allow httpd to read content\n    setsebool -P httpd_read_user_content 1\n\n    # eFa policy module\n    checkmodule -M -m -o /var/eFa/lib/selinux/eFa.mod /var/eFa/lib/selinux/eFa9.te\n    semodule_package -o /var/eFa/lib/selinux/eFa.pp -m /var/eFa/lib/selinux/eFa.mod -f /var/eFa/lib/selinux/eFa.fc\n    semodule -i /var/eFa/lib/selinux/eFa.pp\nfi\n' \
        $'# Is this a full vm or physical and not a container?\n# NixOS: SELinux not enabled; skip policy setup\n:\n'
    '';
    installPhase = ''
      mkdir -p $out
      cp -a . $out/
    '';
  };
in {
  options.efa.sources.efaSrc = lib.mkOption {
    type = lib.types.path;
    default = efaSrc;
    description = "Derivation output for eFa source tree.";
  };
  options.efa.sources.efaBaseSrc = lib.mkOption {
    type = lib.types.path;
    default = efaBaseSrc;
    description = "Derivation output for eFa-base source tree.";
  };

  config = {
    efa.sources.efaSrcRoot = lib.mkDefault config.efa.sources.efaSrc;
    efa.sources.efaBaseSrcRoot = lib.mkDefault config.efa.sources.efaBaseSrc;
  };
}
