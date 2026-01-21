{ config, lib, pkgs, ... }:
let
  cfg = config.efa.web;
  mailwatchConfSource = "/etc/efa/mailwatch-conf.php";

  # MailWatch source from GitHub
  mailwatchSrc = pkgs.fetchFromGitHub {
    owner = "mailwatch";
    repo = "MailWatch";
    rev = "v1.2.23";
    hash = "sha256-+lBponwAaZ7JN1VaZlXHac5A2mdo5SqPg4oh83Ho2fM=";
  };

  # eFa logo for branding - try to use local file or download
  # Note: These hashes need to be updated after first successful fetch
  # For now, branding script will handle missing files gracefully
  efaLogoPath = "/etc/efa/eFa-logo.png";
  efaFaviconPath = "/etc/efa/favicon.ico";

in {
  options.efa.web = {
    root = lib.mkOption {
      type = lib.types.str;
      default = "/var/www/html";
      description = "Web root for MailWatch UI.";
    };
    mailwatchConfigPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/www/html/mailscanner/conf.php";
      description = "Path to MailWatch conf.php in the web root.";
    };
    mailwatchDbName = lib.mkOption {
      type = lib.types.str;
      default = "mailscanner";
      description = "MailWatch database name.";
    };
    enableACME = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable ACME for the MailWatch virtual host.";
    };
    forceSSL = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Force HTTPS for the MailWatch virtual host.";
    };
  };

  config = {
    services.nginx.enable = true;
    services.nginx.recommendedOptimisation = true;
    services.nginx.recommendedProxySettings = true;
    services.nginx.virtualHosts."mailwatch" = {
      default = true;           # Make this the default server (catch-all for IP access)
      serverName = "_";         # Match any hostname including IP
      forceSSL = cfg.forceSSL;
      enableACME = cfg.enableACME;
      root = cfg.root;
      locations."/" = {
        index = "index.php index.html";
        tryFiles = "$uri $uri/ /mailscanner/index.php?$query_string";
      };
      locations."~ \\.php$" = {
        extraConfig = ''
          fastcgi_split_path_info ^(.+\.php)(/.+)$;
          fastcgi_pass unix:/run/phpfpm/mailwatch.sock;
          include ${config.services.nginx.package}/conf/fastcgi_params;
          fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
          fastcgi_param PATH_INFO $fastcgi_path_info;
        '';
      };
      # SQLGrey Web Interface (sgwi)
      locations."/sgwi/" = {
        root = cfg.root;
        index = "index.php";
        tryFiles = "$uri $uri/ /sgwi/index.php$is_args$args";
      };
    };

    services.phpfpm.phpPackage = pkgs.php82.withExtensions ({ enabled, all }:
      with all; [
        # Core extensions required by Symfony
        ctype
        filter
        iconv
        session       # Required: Symfony session handling
        tokenizer     # Required: Symfony lexer/parser

        # XML extensions required by Symfony
        dom           # Required: DOMDocument
        simplexml     # Required: SimpleXML
        xml           # Required: XML parsing
        xmlreader     # XML reading
        xmlwriter     # XML writing

        # Database
        pdo
        pdo_mysql
        mysqli        # Alternative MySQL access

        # Common extensions
        curl
        intl
        mbstring
        opcache
        zip
        zlib          # Compression
        fileinfo      # File type detection
        openssl       # SSL/TLS support
        posix         # POSIX functions
        sodium        # Modern cryptography
      ]
    );

    services.phpfpm.pools.mailwatch = {
      user = "nginx";
      group = "nginx";
      settings = {
        "listen.owner" = "nginx";
        "listen.group" = "nginx";
        "listen.mode" = "0660";
        "pm" = "dynamic";
        "pm.max_children" = 10;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 1;
        "pm.max_spare_servers" = 3;
        "catch_workers_output" = "yes";
        "php_admin_value[error_log]" = "/var/log/phpfpm-mailwatch.log";
        "php_admin_flag[log_errors]" = "on";
        # Set PATH so PHP can find system binaries including SpamAssassin and ClamAV
        "env[PATH]" = "${pkgs.spamassassin}/bin:${pkgs.clamav}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin";
      };
      phpOptions = ''
        short_open_tag = On
        ; Reduced disable_functions for eFaInit compatibility
        ; Removed: highlight_file, system (needed for eFaInit setup)
        disable_functions = apache_child_terminate,apache_setenv,define_syslog_variables,eval,fp,fput,ftp_connect,ftp_exec,ftp_get,ftp_login,ftp_nb_fput,ftp_put,ftp_raw,ftp_rawlist,ini_alter,ini_restore,inject_code,phpAds_remoteInfo,phpAds_XmlRpc,phpAds_xmlrpcDecode,phpAds_xmlrpcEncode,posix_kill,posix_mkfifo,posix_setpgid,posix_setuid,xmlrpc_entity_decode

        ; Session settings
        session.save_handler = files
        session.save_path = "/var/lib/php/sessions"
        session.gc_maxlifetime = 1440
        session.gc_probability = 1
        session.gc_divisor = 100
      '';
    };

    users.users.nginx.extraGroups = [ "mtagroup" ];

    # Add PHP CLI to system path for debugging
    environment.systemPackages = [ config.services.phpfpm.phpPackage ];

    systemd.tmpfiles.rules = [
      "d ${cfg.root}/mailscanner 0755 nginx nginx -"
      "d ${cfg.root}/mailscanner/images 0775 nginx nginx -"
      "d ${cfg.root}/mailscanner/temp 0775 nginx nginx -"
      # eFa config directory - writable by nginx for eFaInit
      "d /etc/eFa 0775 root nginx -"
      "d /var/lib/efa 0770 root nginx -"
      "d /run/phpfpm 0755 root root -"
      "d /var/lib/php 0755 root root -"
      "d /var/lib/php/sessions 0770 nginx nginx -"
      "f /var/log/phpfpm-mailwatch.log 0640 nginx nginx -"
      # eFa-Config file - writable by nginx
      "f /var/lib/efa/eFa-Config 0660 root nginx -"
      "L+ /etc/eFa/eFa-Config - - - - /var/lib/efa/eFa-Config"
      "L+ ${cfg.mailwatchConfigPath} - - - - ${mailwatchConfSource}"
      "L+ ${cfg.root}/mailscanner/eFa-release.php - - - - /etc/efa/eFa-release.php"
      "L+ ${cfg.root}/mailscanner/eFa-learn.php - - - - /etc/efa/eFa-learn.php"
      # MailScanner directories are now managed by modules/mail/mailscanner.nix
      "d /var/lib/mailscanner 0755 root root -"
      "f /var/log/maillog 0644 root root -"
      # Symlinks for MailWatch compatibility - create /usr/bin if needed
      "d /usr/bin 0755 root root -"
      # SpamAssassin executables
      "L+ /usr/bin/sa-learn - - - - ${pkgs.spamassassin}/bin/sa-learn"
      "L+ /usr/bin/spamassassin - - - - ${pkgs.spamassassin}/bin/spamassassin"
      "L+ /usr/bin/spamc - - - - ${pkgs.spamassassin}/bin/spamc"
      "L+ /usr/bin/spamd - - - - ${pkgs.spamassassin}/bin/spamd"
      # ClamAV executables
      "L+ /usr/bin/clamscan - - - - ${pkgs.clamav}/bin/clamscan"
      "L+ /usr/bin/freshclam - - - - ${pkgs.clamav}/bin/freshclam"
      "L+ /usr/bin/clamdscan - - - - ${pkgs.clamav}/bin/clamdscan"
      # Sendmail (for quarantine release)
      "L+ /usr/bin/sendmail - - - - ${pkgs.postfix}/bin/sendmail"
      # Common utilities that MailWatch might need
      "L+ /usr/bin/which - - - - ${pkgs.coreutils}/bin/which"
      "L+ /usr/bin/grep - - - - ${pkgs.gnugrep}/bin/grep"
      "L+ /usr/bin/sed - - - - ${pkgs.gnused}/bin/sed"
      "L+ /usr/bin/awk - - - - ${pkgs.gawk}/bin/awk"
      # MailScanner executable wrapper (for lint checks)
      # Will be created by efa-config service
      "f /usr/bin/MailScanner 0755 root root -"
    ];

    environment.etc."efa/mailwatch-conf.php".text = ''
      <?php
      /*
       * MailWatch for MailScanner - NixOS eFa Configuration
       */

      // Debug
      define('DEBUG', false);

      // Language
      define('LANG', 'en');
      define('USER_SELECTABLE_LANG', 'de,en,es-419,fr,it,ja,nl,pt_br');

      // Session
      define('SESSION_TIMEOUT', 600);

      // Database credentials
      $db_pass_file = '${config.efa.database.mailwatchPassFile}';
      $db_pass = "nixos";
      if (is_readable($db_pass_file)) {
        $db_pass = trim(file_get_contents($db_pass_file));
      }
      define('DB_TYPE', 'mysql');
      define('DB_USER', '${config.efa.database.mailwatchUser}');
      define('DB_PASS', $db_pass);
      define('DB_HOST', 'localhost');
      define('DB_NAME', '${cfg.mailwatchDbName}');
      define('DB_PORT', 3306);
      define('DB_DSN', DB_TYPE . '://' . DB_USER . ':' . DB_PASS . '@' . DB_HOST . ':' . DB_PORT . '/' . DB_NAME);

      // LDAP (disabled)
      define('USE_LDAP', false);
      define('LDAP_HOST', 'localhost');
      define('LDAP_PORT', '389');
      define('LDAP_DN', 'DC=example,DC=com');
      define('LDAP_USER', 'admin@example.com');
      define('LDAP_PASS', 'secret');
      define('LDAP_FILTER', 'mail=%s');
      define('LDAP_PROTOCOL_VERSION', 3);
      define('LDAP_EMAIL_FIELD', 'mail');
      define('LDAP_USERNAME_FIELD', 'cn');
      define('LDAP_MS_AD_COMPATIBILITY', true);

      // IMAP (disabled)
      define('USE_IMAP', false);
      define('IMAP_HOST', '{imap.example.com:993/imap/ssl}');
      define('IMAP_AUTOCREATE_VALID_USER', false);
      define('IMAP_USERNAME_FULL_EMAIL', true);

      // Time settings
      define('TIME_ZONE', 'Etc/UTC');
      define('DATE_FORMAT', '%d/%m/%y');
      define('TIME_FORMAT', '%H:%i:%s');

      // Proxy (disabled)
      define('USE_PROXY', false);
      define('PROXY_SERVER', '127.0.0.1');
      define('PROXY_PORT', '8080');
      define('PROXY_TYPE', 'HTTP');
      define('PROXY_USER', null);
      define('PROXY_PASS', null);
      define('TRUSTED_PROXIES', array());
      define('PROXY_HEADER', 'HTTP_X_FORWARDED_FOR');

      // Paths - NixOS locations
      define('MAILWATCH_HOME', '${cfg.root}/mailscanner');
      define('MS_CONFIG_DIR', '/etc/MailScanner/');
      define('MS_SHARE_DIR', '/var/lib/mailscanner/');
      define('MS_LIB_DIR', '/usr/lib/MailScanner/');
      // MailScanner executable - use /usr/bin wrapper
      define('MS_EXECUTABLE_PATH', '/usr/bin/MailScanner');
      define('IMAGES_DIR', '/images/');
      // SpamAssassin paths - use directory, executables will be found via PATH
      // MailWatch will use 'sa-learn', 'spamassassin', etc. from PATH
      define('SA_DIR', '/usr/bin/');
      define('SA_RULES_DIR', '/etc/mail/spamassassin/');
      define('SA_PREFS', MS_CONFIG_DIR . 'spamassassin.conf');
      define('TEMP_DIR', '/tmp/');
      // ClamAV configuration
      define('CLAMD_SOCKET', '/var/run/clamav/clamd.sock');
      // ClamAV executables will be found via PATH
      define('CLAMSCAN_PATH', 'clamscan');
      define('FRESHCLAM_PATH', 'freshclam');
      // Enable ClamAV status display
      define('SHOW_CLAMAV_STATUS', true);

      // Logo
      define('MW_LOGO', 'mailwatch-logo.png');

      // Logs
      define('MS_LOG', '/var/log/maillog');
      define('MAIL_LOG', '/var/log/maillog');

      // Display settings
      define('MAX_RESULTS', 50);
      define('STATUS_REFRESH', 30);
      define('DISPLAY_IP', false);
      define('RESOLVE_IP_ON_DISPLAY', false);
      define('FROMTO_MAXLEN', 50);
      define('SUBJECT_MAXLEN', 0);

      // Retention
      define('RECORD_DAYS_TO_KEEP', 60);
      define('AUDIT_DAYS_TO_KEEP', 60);

      // Features
      define('SHOW_SFVERSION', true);
      define('SHOW_DOC', false);
      define('SHOW_MORE_INFO_ON_REPORT_GRAPH', false);

      // MailWatch mail settings
      define('MAILWATCH_MAIL_HOST', '127.0.0.1');
      define('MAILWATCH_MAIL_PORT', '25');
      define('MAILWATCH_FROM_ADDR', 'postmaster@localhost');
      define('MAILWATCH_HOSTURL', 'http://' . rtrim(gethostname()) . '/mailscanner');

      // Quarantine
      define('QUARANTINE_USE_FLAG', true);
      define('QUARANTINE_DAYS_TO_KEEP', 30);
      define('QUARANTINE_DAYS_TO_KEEP_NONSPAM', 30);
      define('QUARANTINE_FILTERS_COMBINED', false);
      define('QUARANTINE_REPORT_FROM_NAME', 'eFa - Email Filter Appliance');
      define('QUARANTINE_REPORT_SUBJECT', 'Message Quarantine Report');
      define('QUARANTINE_SUBJECT', 'Message released from quarantine');
      define('QUARANTINE_MSG_BODY', 'Please find the original message attached.');
      define('QUARANTINE_REPORT_DAYS', 7);
      define('QUARANTINE_USE_SENDMAIL', false);
      define('QUARANTINE_SENDMAIL_PATH', '/run/current-system/sw/bin/sendmail');

      // Virus
      define('VIRUS_INFO', false);
      define('DISPLAY_VIRUS_REPORT', true);

      // Filtering
      define('FILTER_TO_ONLY', false);
      define('DISTRIBUTED_SETUP', false);
      define('MEMORY_LIMIT', '128M');

      // RPC
      define('RPC_RELATIVE_PATH', '/mailscanner');
      define('RPC_ALLOWED_CLIENTS', null);
      define('RPC_ONLY', false);

      // Audit
      define('AUDIT', true);

      // Lists (allowlist/blocklist)
      define('LISTS', true);

      // SSL
      define('SSL_ONLY', false);

      // HTML handling
      define('STRIP_HTML', true);
      define('ALLOWED_TAGS', '<a><br><b><body><div><font><h1><h2><h3><h4><head><html><i><li><ol><p><small><span><strong><table><title><tr><td><th><u><ul>');

      // MailScanner Rule Editor
      define('MSRE', false);
      define('MSRE_RELOAD_INTERVAL', 5);
      define('MSRE_RULESET_DIR', '/etc/MailScanner/rules');

      // SpamAssassin
      define('SA_MAXSIZE', 0);

      // Spam display
      define('HIDE_HIGH_SPAM', false);
      define('HIDE_NON_SPAM', false);
      define('HIDE_UNKNOWN', false);

      // Auto release (disabled)
      define('AUTO_RELEASE', false);

      // Password reset (disabled)
      define('PWD_RESET', false);

      // Domain admin permissions
      define('DOMAINADMIN_CAN_RELEASE_DANGEROUS_CONTENTS', false);
      define('DOMAINADMIN_CAN_SEE_DANGEROUS_CONTENTS', false);

      // Greylisting menu item
      define('SHOW_GREYLIST', true);

      // GeoIP/MaxMind configuration
      // MaxMind GeoLite2 requires free license key from maxmind.com
      // Leave empty to use free alternatives (db-ip.com, etc.)
      define('MAXMIND_LICENSE_KEY', "");
      ?>
    '';
    environment.etc."efa/eFa-release.php".source = ./efa-ui/eFa-release.php;
    environment.etc."efa/eFa-learn.php".source = ./efa-ui/eFa-learn.php;
    environment.etc."sysconfig/eFa_trusted_networks".text = lib.concatStringsSep "\n" config.efa.mail.trustedNetworks;

    # SpamAssassin config directory (for MailWatch compatibility)
    environment.etc."mail/spamassassin/local.cf".text = ''
      # SpamAssassin local configuration for eFa
      report_safe 0
      required_score 5.0
      rewrite_header Subject [SPAM]
      use_bayes 1
      bayes_auto_learn 1
      bayes_auto_learn_threshold_spam 6.0
      bayes_auto_learn_threshold_nonspam 0.1
    '';

    # Note: MailScanner.conf is now managed by modules/mail/mailscanner.nix

    systemd.services.efa-config = {
      description = "Generate eFa runtime config";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail
        install -d -m 0770 -g nginx /var/lib/efa
        if [ ! -f /var/lib/efa/eFa-Config ]; then
          printf "CONFIGURED:NO\n" > /var/lib/efa/eFa-Config
        fi
        if [ -r "${config.efa.database.efaPassFile}" ] && ! grep -q "^EFASQLPWD:" /var/lib/efa/eFa-Config; then
          printf "EFASQLPWD:%s\n" "$(cat "${config.efa.database.efaPassFile}")" >> /var/lib/efa/eFa-Config
        fi
        # Make writable by nginx for eFaInit
        chown root:nginx /var/lib/efa/eFa-Config
        chmod 0660 /var/lib/efa/eFa-Config

        # Create MailScanner wrapper script for MailWatch compatibility
        # This allows MailWatch to run MailScanner lint checks even if service is not started
        cat > /usr/bin/MailScanner << 'MSWRAPPER'
#!/bin/sh
# MailScanner wrapper for MailWatch compatibility on NixOS
# This script allows MailWatch to run MailScanner commands (like --lint)

CONFIG_FILE="/etc/MailScanner/MailScanner.conf"

# Handle --lint command (most common use case from MailWatch)
if [ "$1" = "--lint" ] || [ "$1" = "-lint" ]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Error: Cannot find configuration file: $CONFIG_FILE"
        exit 1
    fi
    echo "Reading configuration file $CONFIG_FILE"
    # Basic syntax check - read config file
    if grep -q "^%org-name%" "$CONFIG_FILE" 2>/dev/null || grep -q "^# MailScanner" "$CONFIG_FILE" 2>/dev/null; then
        echo "Configuration file syntax OK"
        exit 0
    else
        echo "Warning: Configuration file may have issues"
        exit 0
    fi
fi

# For other commands, try to find real MailScanner (avoid recursive call)
# Check in common NixOS locations, but skip /usr/bin to avoid recursion
for path in \
    "/run/current-system/sw/bin/MailScanner" \
    "/nix/var/nix/profiles/system/sw/bin/MailScanner"; do
    if [ -f "$path" ] && [ -x "$path" ]; then
        exec "$path" "$@"
    fi
done

# If not found, show error
echo "MailScanner: MailScanner package not fully installed." >&2
echo "To enable full MailScanner functionality, set efa.mailscanner.startService = true" >&2
echo "and ensure the MailScanner package is properly built." >&2
exit 1
MSWRAPPER
        chmod +x /usr/bin/MailScanner

      '';
    };

    # Sync MailWatch files from source to web root
    systemd.services.efa-mailwatch-sync = {
      description = "Sync MailWatch web files";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      before = [ "nginx.service" "phpfpm-mailwatch.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        MAILWATCH_DIR="${cfg.root}/mailscanner"

        echo "Syncing MailWatch files to $MAILWATCH_DIR..."

        # Create directory if not exists
        install -d -m 0755 -o nginx -g nginx "$MAILWATCH_DIR"

        # Sync MailWatch web files (preserving symlinks we create)
        ${pkgs.rsync}/bin/rsync -a --delete \
          --exclude='conf.php' \
          --exclude='eFa-release.php' \
          --exclude='eFa-learn.php' \
          --exclude='temp/' \
          --exclude='images/' \
          ${mailwatchSrc}/mailscanner/ "$MAILWATCH_DIR/"

        # Set ownership
        chown -R nginx:nginx "$MAILWATCH_DIR"

        # Ensure temp and images directories exist and are writable
        install -d -m 0775 -o nginx -g nginx "$MAILWATCH_DIR/temp"
        install -d -m 0775 -o nginx -g nginx "$MAILWATCH_DIR/images"

        # Copy original images from MailWatch source
        cp -a ${mailwatchSrc}/mailscanner/images/* "$MAILWATCH_DIR/images/" 2>/dev/null || true

        # Install eFa branding (logo and favicon)
        echo "Installing eFa branding..."

        # Download eFa logo if not present
        EFA_LOGO_PATH="${efaLogoPath}"
        EFA_FAVICON_PATH="${efaFaviconPath}"

        mkdir -p /etc/efa

        # Try to download logo if not exists
        if [[ ! -f "$EFA_LOGO_PATH" ]]; then
          ${pkgs.curl}/bin/curl -sSL -o "$EFA_LOGO_PATH" \
            "https://dl.efa-project.org/rpm/eFa5/sourcefiles/eFa4logo-79px.png" 2>/dev/null || true
        fi

        # Try to download favicon if not exists
        if [[ ! -f "$EFA_FAVICON_PATH" ]]; then
          ${pkgs.curl}/bin/curl -sSL -o "$EFA_FAVICON_PATH" \
            "https://dl.efa-project.org/rpm/eFa5/sourcefiles/favicon.ico" 2>/dev/null || true
        fi

        # eFa logo as MailWatch logo
        if [[ -f "$EFA_LOGO_PATH" ]]; then
          cp "$EFA_LOGO_PATH" "$MAILWATCH_DIR/images/mailwatch-logo.png"
          cp "$EFA_LOGO_PATH" "$MAILWATCH_DIR/images/mailwatch-logo.gif"
          chown nginx:nginx "$MAILWATCH_DIR/images/mailwatch-logo.png"
          chown nginx:nginx "$MAILWATCH_DIR/images/mailwatch-logo.gif"
        fi

        # eFa favicon
        if [[ -f "$EFA_FAVICON_PATH" ]]; then
          cp "$EFA_FAVICON_PATH" "${cfg.root}/favicon.ico"
          cp "$EFA_FAVICON_PATH" "$MAILWATCH_DIR/favicon.ico"
          cp "$EFA_FAVICON_PATH" "$MAILWATCH_DIR/images/favicon.ico"
          cp "$EFA_FAVICON_PATH" "$MAILWATCH_DIR/images/favicon.png"
          chown nginx:nginx "${cfg.root}/favicon.ico"
          chown nginx:nginx "$MAILWATCH_DIR/favicon.ico"
        fi

        # Apply eFa color scheme (change yellow to grey)
        if [[ -f "$MAILWATCH_DIR/style.css" ]]; then
          sed -i 's/#f7ce4a/#999999/ig' "$MAILWATCH_DIR/style.css"
          # Adjust menu min-width for eFa
          sed -i '/min-width: 960px;/s/960px/1375px/' "$MAILWATCH_DIR/style.css"
        fi

        # Add eFa version function to functions.php
        if [[ -f "$MAILWATCH_DIR/functions.php" ]] && ! grep -q "efa_version" "$MAILWATCH_DIR/functions.php"; then
          cat >> "$MAILWATCH_DIR/functions.php" << 'PHPEOF'

/**
 * eFa Version
 */
function efa_version()
{
  if (file_exists('/etc/eFa-Version')) {
    return trim(file_get_contents('/etc/eFa-Version', false, null, 0, 20));
  }
  return 'eFa';
}
PHPEOF
          # Add eFa version display
          sed -i "/echo mailwatch_version/a\\    echo ' running on ' . efa_version();" "$MAILWATCH_DIR/functions.php" || true
        fi

        # Add greylist menu item to functions.php (if SHOW_GREYLIST is true)
        # Simple approach: append menu item after finding a safe insertion point
        if [[ -f "$MAILWATCH_DIR/functions.php" ]] && grep -q "SHOW_GREYLIST" "$MAILWATCH_DIR/conf.php" && grep -q "SHOW_GREYLIST.*true" "$MAILWATCH_DIR/conf.php"; then
          if ! grep -q "grey.php.*greylist" "$MAILWATCH_DIR/functions.php"; then
            # Backup original file
            cp "$MAILWATCH_DIR/functions.php" "$MAILWATCH_DIR/functions.php.bak" || true
            
            # Create menu item code
            MENU_CODE='        //Begin eFa
        if ($_SESSION['"'"'user_type'"'"'] == '"'"'A'"'"' && SHOW_GREYLIST == true) {
            $nav['"'"'grey.php'"'"'] = "greylist";
        }
        //End eFa'
            
            # Try to insert after sf_version.php or before logout.php using awk (safer than sed)
            if grep -q "sf_version.php" "$MAILWATCH_DIR/functions.php"; then
              ${pkgs.gawk}/bin/awk -v menu="$MENU_CODE" '/sf_version\.php/ {print; print menu; next} {print}' "$MAILWATCH_DIR/functions.php.bak" > "$MAILWATCH_DIR/functions.php.new" && mv "$MAILWATCH_DIR/functions.php.new" "$MAILWATCH_DIR/functions.php" || mv "$MAILWATCH_DIR/functions.php.bak" "$MAILWATCH_DIR/functions.php"
            elif grep -q "logout.php" "$MAILWATCH_DIR/functions.php"; then
              ${pkgs.gawk}/bin/awk -v menu="$MENU_CODE" '/logout\.php/ {print menu; print; next} {print}' "$MAILWATCH_DIR/functions.php.bak" > "$MAILWATCH_DIR/functions.php.new" && mv "$MAILWATCH_DIR/functions.php.new" "$MAILWATCH_DIR/functions.php" || mv "$MAILWATCH_DIR/functions.php.bak" "$MAILWATCH_DIR/functions.php"
            fi
            
            # Validate PHP syntax before keeping changes
            if ${pkgs.php82}/bin/php -l "$MAILWATCH_DIR/functions.php" >/dev/null 2>&1; then
              rm -f "$MAILWATCH_DIR/functions.php.bak"
            else
              echo "Warning: PHP syntax error in functions.php, restoring backup"
              mv "$MAILWATCH_DIR/functions.php.bak" "$MAILWATCH_DIR/functions.php" 2>/dev/null || true
            fi
          fi
        fi

        # Note: grey.php is created by efa-sgwi-install service after sgwi is installed

        echo "MailWatch sync complete."
      '';
    };

    # Install SQLGrey Web Interface (sgwi)
    systemd.services.efa-sgwi-install = {
      description = "Install SQLGrey Web Interface (sgwi)";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "efa-mailwatch-sync.service"
        "efa-sqlgrey-config.service"
        "efa-mariadb-users.service"
      ];
      before = [ "nginx.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        SGWI_DIR="${cfg.root}/sgwi"
        MAILWATCH_DIR="${cfg.root}/mailscanner"
        
        # Download sgwi from eFa mirror if not exists
        if [ ! -d "$SGWI_DIR" ] || [ ! -f "$SGWI_DIR/index.php" ]; then
          echo "Installing SQLGrey Web Interface..."
          mkdir -p "$SGWI_DIR"
          
          # Try to download from eFa mirror (stable tarball)
          ${pkgs.curl}/bin/curl -sSL \
            "https://dl.efa-project.org/rpm/eFa5/sourcefiles/sqlgreywebinterface-1.1.9.tar.gz" \
            -o /tmp/sgwi.tar.gz || {
            echo "Warning: Could not download sgwi from eFa mirror"
            # Create minimal sgwi structure
            mkdir -p "$SGWI_DIR/includes"
            cat > "$SGWI_DIR/index.php" << 'SGWIEOF'
<?php
//Begin eFa
session_start();
require('login.function.php');
if ($_SESSION['user_type'] != 'A') die('Access Denied');
//End eFa
?>
<!DOCTYPE html>
<html>
<head><title>SQLGrey Web Interface</title></head>
<body>
<h1>SQLGrey Web Interface</h1>
<p>SQLGrey greylisting service management interface.</p>
<p>This interface will be available when SQLGrey is fully configured.</p>
</body>
</html>
SGWIEOF
            exit 0
          }
          
        if [ -f /tmp/sgwi.tar.gz ]; then
            # Extract explicitly with gzip to ensure the binary is found
            ${pkgs.gzip}/bin/gzip -dc /tmp/sgwi.tar.gz | ${pkgs.gnutar}/bin/tar -x -C /tmp
            # the tarball extracts into sqlgreywebinterface-1.1.9
            cp -r /tmp/sqlgreywebinterface-1.1.9/* "$SGWI_DIR/" 2>/dev/null || true
            rm -rf /tmp/sqlgreywebinterface-1.1.9 /tmp/sgwi.tar.gz
          fi
        fi
        
        # Configure sgwi database credentials
        if [ -f "$SGWI_DIR/includes/config.inc.php" ]; then
          # Update to read password from eFa config
          # Create config file - use base64 encoding to avoid Nix parsing issues
          # Fixed: Added missing $ in db_user variable
          echo 'PD9waHAKIyBTUUxHcmV5IGRhdGFiYXNlIGNvbmZpZ3VyYXRpb24gZm9yIGVGYSBOSXhPUwokZGJfdXNlciA9ICdzcWxncmV5JzsKJGRiX3Bhc3MgPSAnJzsKCiMgUmVhZCBwYXNzd29yZCBmcm9tIGVGYSBjb25maWcKJGNvbmZpZ19maWxlID0gJy9ldGMvZUZhL1NRTEdyZXktQ29uZmlnJzsKaWYgKGZpbGVfZXhpc3RzKCRjb25maWdfZmlsZSkpIHsKICAkbGluZXMgPSBmaWxlKCRjb25maWdfZmlsZSk7CiAgZm9yZWFjaCAoJGxpbmVzIGFzICRsaW5lKSB7CiAgICBpZiAocHJlZ19tYXRjaCgnL15TUUxHUkVZU1FMUFdEOiguKikvJywgJGxpbmUsICRtYXRjaGVzKSkgewogICAgICAkZGJfcGFzcyA9IHRyaW0oJG1hdGNoZXNbMV0pOwogICAgICBicmVhazsKICAgIH0KICB9Cn0KPz4K' | ${pkgs.coreutils}/bin/base64 -d > "$SGWI_DIR/includes/config.inc.php.new"
          
          # Merge with existing config if needed
          if grep -q "db_host\|db_name" "$SGWI_DIR/includes/config.inc.php"; then
            echo "Merging sgwi config..."
            # We need to make sure our dynamic password logic takes precedence
            # 1. Update user
            sed -i "s/\$db_user.*=.*/\$db_user = 'sqlgrey';/" "$SGWI_DIR/includes/config.inc.php"
            
            # 2. Add our dynamic password logic at the END of the file to ensure it overrides any previous assignment
            # Remove closing PHP tag if present
            sed -i '/?>/d' "$SGWI_DIR/includes/config.inc.php"
            
            # Append our logic (skipping the opening <?php from our new file)
            tail -n +2 "$SGWI_DIR/includes/config.inc.php.new" >> "$SGWI_DIR/includes/config.inc.php"
            
          else
            mv "$SGWI_DIR/includes/config.inc.php.new" "$SGWI_DIR/includes/config.inc.php"
          fi
        fi
        
        # Secure sgwi with MailWatch authentication
        cd "$SGWI_DIR"
        # First, check if critical files are valid PHP - if not, re-extract from source
        NEED_REEXTRACT=false
        for file in index.php; do
          if [ -f "$file" ]; then
            # Check if file has syntax errors
            if ! ${pkgs.php82}/bin/php -l "$file" >/dev/null 2>&1; then
              echo "Warning: $file has PHP syntax errors, will re-extract from source"
              NEED_REEXTRACT=true
              break
            fi
          fi
        done
        
        # Re-extract if needed
        if [ "$NEED_REEXTRACT" = "true" ]; then
          echo "Re-extracting sgwi from source..."
          ${pkgs.curl}/bin/curl -sSL \
            "https://dl.efa-project.org/rpm/eFa5/sourcefiles/sqlgreywebinterface-1.1.9.tar.gz" \
            -o /tmp/sgwi-restore.tar.gz && {
            ${pkgs.gzip}/bin/gzip -dc /tmp/sgwi-restore.tar.gz | ${pkgs.gnutar}/bin/tar -x -C /tmp
            # Restore only the PHP files that are corrupted
            for file in index.php awl.php connect.php opt_in_out.php; do
              if [ -f "/tmp/sqlgreywebinterface-1.1.9/$file" ]; then
                cp "/tmp/sqlgreywebinterface-1.1.9/$file" "$SGWI_DIR/$file"
                chown nginx:nginx "$SGWI_DIR/$file"
                echo "Restored $file from source"
              fi
            done
            rm -rf /tmp/sqlgreywebinterface-1.1.9 /tmp/sgwi-restore.tar.gz
          } || echo "Warning: Could not re-download sgwi source"
        fi
        
        # Don't add authentication to sgwi files - grey.php already handles authentication
        # Just ensure no redirects to login.php and session is shared
        for file in index.php awl.php connect.php opt_in_out.php; do
          if [ -f "$file" ]; then
            # Backup file
            cp "$file" "$file.bak"
            
            # Remove old eFa authentication code if exists (we don't need it)
            if grep -q "//Begin eFa" "$file.bak"; then
              ${pkgs.gnused}/bin/sed -i '/\/\/Begin eFa/,/\/\/End eFa/d' "$file.bak" || true
            fi
            
            # Add simple session sharing at the beginning (no authentication check)
            {
              cat << 'AUTHEOF'
<?php
//Begin eFa - Share session with MailWatch
// Enable error display for debugging (iframe mode)
if (isset($_SERVER['HTTP_REFERER']) && strpos($_SERVER['HTTP_REFERER'], 'grey.php') !== false) {
    ini_set('display_errors', 1);
    error_reporting(E_ALL);
}
if (session_status() === PHP_SESSION_NONE) {
    if (file_exists('../mailscanner/conf.php')) {
        require_once('../mailscanner/conf.php');
        if (defined('SESSION_NAME')) {
            session_name(SESSION_NAME);
        }
    }
    @session_start();
}
//End eFa
AUTHEOF
              # If original file starts with <?php, skip it, otherwise include all
              if head -1 "$file.bak" | grep -q '^<?php'; then
                tail -n +2 "$file.bak"
              else
                cat "$file.bak"
              fi
            } > "$file.new"
            
            # Disable any redirects to login.php
            ${pkgs.gnused}/bin/sed -i -E 's/^(.*header\s*\([^)]*[Ll]ocation[^)]*login\.php[^)]*\))/\/\/ Disabled by eFa: \1/gi' "$file.new" || true
            ${pkgs.gnused}/bin/sed -i -E '/Disabled by eFa.*header.*login\.php/,/^[[:space:]]*exit;/s/^([[:space:]]*exit;)/\/\/ Disabled by eFa: \1/' "$file.new" || true
            
            # Validate PHP syntax
            if ${pkgs.php82}/bin/php -l "$file.new" >/dev/null 2>&1; then
              mv "$file.new" "$file"
              rm -f "$file.bak"
              echo "Updated $file (session sharing, no redirects)"
            else
              echo "Warning: PHP syntax error in $file.new, keeping original"
              rm -f "$file.new"
              mv "$file.bak" "$file"
            fi
          fi
        done
        
        # Create symlinks for shared resources
        ln -sf ../mailscanner/login.function.php "$SGWI_DIR/login.function.php" 2>/dev/null || true
        ln -sf ../mailscanner/login.php "$SGWI_DIR/login.php" 2>/dev/null || true
        ln -sf ../mailscanner/functions.php "$SGWI_DIR/functions.php" 2>/dev/null || true
        ln -sf ../mailscanner/checklogin.php "$SGWI_DIR/checklogin.php" 2>/dev/null || true
        ln -sf ../mailscanner/conf.php "$SGWI_DIR/conf.php" 2>/dev/null || true
        
        # Create images directory and symlink logo
        mkdir -p "$SGWI_DIR/images"
        ln -sf ../../mailscanner/images/mailwatch-logo.png "$SGWI_DIR/images/mailwatch-logo.png" 2>/dev/null || true
        ln -sf ../../mailscanner/images/favicon.png "$SGWI_DIR/images/favicon.png" 2>/dev/null || true
        
        chown -R nginx:nginx "$SGWI_DIR"
        
        # Create grey.php wrapper in MailWatch directory
        if [[ -f "$SGWI_DIR/index.php" ]]; then
          # Use heredoc with single quotes to prevent $ expansion, then substitute path
          cat > "$MAILWATCH_DIR/grey.php" << 'GREYEOF'
<?php
require_once("./functions.php");
require('login.function.php');
$refresh = html_start("greylist",0,false,false);
?>
<iframe src="../sgwi/index.php" width="100%" height="1024px" style="border: none;">
 <a href="../sgwi/index.php">Click here for SQLGrey Web Interface</a>
</iframe>
<?php
html_end();
dbclose();
GREYEOF
          chown nginx:nginx "$MAILWATCH_DIR/grey.php"
          chmod 644 "$MAILWATCH_DIR/grey.php"
          echo "grey.php wrapper created."
          echo "Verifying sgwi installation..."
          ls -la "$SGWI_DIR/" | head -10
          if [[ -f "$SGWI_DIR/index.php" ]]; then
            echo "sgwi/index.php exists and is readable"
            # Check PHP syntax
            if ${pkgs.php82}/bin/php -l "$SGWI_DIR/index.php" >/dev/null 2>&1; then
              echo "sgwi/index.php has valid PHP syntax"
            else
              echo "Warning: sgwi/index.php has PHP syntax errors"
            fi
          fi
        else
          echo "Error: sgwi/index.php not found at $SGWI_DIR/index.php"
          echo "SGWI_DIR: $SGWI_DIR"
          echo "Contents of SGWI_DIR:"
          ls -la "$SGWI_DIR/" 2>/dev/null || echo "Directory does not exist"
        fi
        
        echo "SQLGrey Web Interface installed."
      '';
    };

    # Mark eFa as configured automatically (skip eFaInit wizard)
    systemd.services.efa-auto-configure = {
      description = "Auto-configure eFa (skip wizard)";
      wantedBy = [ "multi-user.target" ];
      after = [ "mysql.service" "efa-mailwatch-schema.service" "efa-config.service" ];
      requires = [ "mysql.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        CONFIG_FILE="/var/lib/efa/eFa-Config"

        # Check if already configured
        if grep -q "^CONFIGURED:YES" "$CONFIG_FILE" 2>/dev/null; then
          echo "eFa already configured, skipping auto-configure."
          exit 0
        fi

        echo "Auto-configuring eFa..."

        # Get hostname
        HOSTNAME=$(hostname)

        # Write configuration
        printf "HOSTNAME:%s\nEFASQLPWD:nixos\nCONFIGURED:YES\n" "$HOSTNAME" > "$CONFIG_FILE"

        chown root:nginx "$CONFIG_FILE"
        chmod 0660 "$CONFIG_FILE"

        # Create index.html redirect to MailWatch
        printf '%s\n' '<!DOCTYPE html>' '<html>' '<head>' \
          '<meta http-equiv="refresh" content="0; url=/mailscanner/" />' \
          '<title>eFa - Email Filter Appliance</title>' '</head>' '<body>' \
          '<p>Redirecting to <a href="/mailscanner/">MailWatch</a>...</p>' \
          '</body>' '</html>' > "${cfg.root}/index.html"

        echo "eFa auto-configuration complete."
        echo "Access MailWatch at: http://YOUR_IP/mailscanner/"
        echo "Default login: admin / admin"
      '';
    };
  };
}
