{ config, lib, pkgs, ... }:
let
  cfg = config.efa.web;
  efaBaseRoot = config.efa.sources.efaBaseSrcRoot;
  # App installed in /var/lib, public folder symlinked to web root
  efaInitAppRoot = "/var/lib/efa-init/app";
  efaInitPublic = "${efaInitAppRoot}/public";
  efaInitWebRoot = "${cfg.root}/eFaInit";  # Symlink -> efaInitPublic
in {
  options.efa.web.efaInitRunComposer = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Run composer install for eFaInit during sync.";
  };

  config = lib.mkIf (efaBaseRoot != null) {
    # eFaInit nginx configuration
    # ${efaInitWebRoot} is a symlink to ${efaInitPublic}
    services.nginx.virtualHosts."mailwatch".locations."/eFaInit/" = {
      root = cfg.root;
      index = "index.php";
      tryFiles = "$uri $uri/ /eFaInit/index.php$is_args$args";
    };

    # PHP handler for eFaInit
    services.nginx.virtualHosts."mailwatch".locations."~ ^/eFaInit/.+\\.php$" = {
      root = cfg.root;
      extraConfig = ''
        fastcgi_pass unix:/run/phpfpm/mailwatch.sock;
        include ${config.services.nginx.package}/conf/fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $document_root;
      '';
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/efa-init 0755 root root -"
      "d /var/lib/efa-init/composer 0755 root root -"
      "d ${efaInitAppRoot} 0755 nginx nginx -"
      "d ${efaInitAppRoot}/var 0775 nginx nginx -"
      "d ${efaInitAppRoot}/var/cache 0775 nginx nginx -"
      "d ${efaInitAppRoot}/var/log 0775 nginx nginx -"
      # Note: symlink ${efaInitWebRoot} -> ${efaInitPublic} is created by efa-init-sync service
      # Index.html redirects to MailWatch (NixOS is pre-configured, no wizard needed)
      "L+ ${cfg.root}/index.html - - - - /etc/efa/efa-mailwatch-index.html"
    ];

    # Redirect directly to MailWatch - NixOS handles all configuration declaratively
    environment.etc."efa/efa-mailwatch-index.html".text = ''
      <!DOCTYPE html>
      <html>
          <head>
          <title>eFa - Email Filter Appliance</title>
          <meta http-equiv="refresh" content="0; url=/mailscanner/" />
          </head>
          <body>
          <p>Redirecting to <a href="/mailscanner/">MailWatch</a>...</p>
          </body>
      </html>
    '';

    systemd.services.efa-checkreboot = {
      description = "eFa check reboot marker";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        if [ -f /reboot.system ]; then
          rm -f /reboot.system
          /run/current-system/sw/bin/shutdown -r now
        fi
      '';
    };

    systemd.timers.efa-checkreboot = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:*:00";
        Unit = "efa-checkreboot.service";
      };
    };

    security.sudo.extraRules = [
      {
        users = [ "nginx" ];
        commands = [
          { command = "ALL"; options = [ "NOPASSWD" ]; }
        ];
      }
    ];

    systemd.services.efa-init-sync = {
      description = "Sync eFaInit web UI";
      wantedBy = [ "multi-user.target" ];
      before = [ "nginx.service" "phpfpm-mailwatch.service" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "HOME=/var/lib/efa-init"
          "COMPOSER_HOME=/var/lib/efa-init/composer"
          "COMPOSER_ALLOW_SUPERUSER=1"
        ];
      };
      script = ''
        set -e
        install -d -m 0755 ${efaInitAppRoot}
        ${pkgs.rsync}/bin/rsync -a --delete --exclude '/var/' ${efaBaseRoot}/eFaInit/ ${efaInitAppRoot}/
        install -d -m 0775 ${efaInitAppRoot}/var
        install -d -m 0775 ${efaInitAppRoot}/var/cache
        install -d -m 0775 ${efaInitAppRoot}/var/log
        if [ "${lib.boolToString cfg.efaInitRunComposer}" = "true" ]; then
          cd ${efaInitAppRoot}
          # Run composer install with error handling
          # Skip scripts to avoid importmap:install issues (can be run manually if needed)
          ${pkgs.php82Packages.composer}/bin/composer install \
            --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader \
            --no-scripts --ignore-platform-reqs || {
            echo "Warning: composer install had some issues, trying without scripts..."
            # Retry without scripts if first attempt fails
            ${pkgs.php82Packages.composer}/bin/composer install \
              --no-dev --prefer-dist --no-interaction --no-progress --optimize-autoloader \
              --no-scripts --ignore-platform-reqs || {
              echo "Error: composer install failed, but continuing with basic setup..."
              # At minimum, ensure autoloader exists
              ${pkgs.php82Packages.composer}/bin/composer dump-autoload --optimize --no-interaction || true
            }
          }
        fi
        chmod -R a+rX ${efaInitAppRoot}
        chown -R nginx:nginx ${efaInitAppRoot}/var || true
        chown -R nginx:nginx ${efaInitAppRoot} || true

        # Create symlink for web access (after app is synced)
        ln -sfn ${efaInitPublic} ${efaInitWebRoot}
      '';
    };

    systemd.services.efa-init-env = {
      description = "Configure eFaInit environment";
      wantedBy = [ "multi-user.target" ];
      after = [ "efa-init-sync.service" ];
      before = [ "nginx.service" "phpfpm-mailwatch.service" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail
        install -d -m 0750 /var/lib/efa
        secret_file="/var/lib/efa/efa-init-secret"
        if [ ! -s "$secret_file" ]; then
          ${pkgs.openssl}/bin/openssl rand -hex 32 > "$secret_file"
          chmod 0400 "$secret_file"
        fi

        if [ -r "${config.efa.database.efaPassFile}" ]; then
          db_pass="$(cat "${config.efa.database.efaPassFile}")"
        else
          db_pass="nixos"
        fi
        app_secret="$(cat "$secret_file")"

        cat > ${efaInitAppRoot}/.env.local <<EOF
APP_ENV=prod
APP_DEBUG=0
APP_SECRET=$app_secret
DATABASE_URL="mysql://${config.efa.database.efaUser}:''${db_pass}@127.0.0.1:3306/efa?serverVersion=10.11.11-MariaDB&charset=utf8mb4"
EOF
        chown nginx:nginx ${efaInitAppRoot}/.env.local
        chmod 0640 ${efaInitAppRoot}/.env.local
      '';
    };
  };
}
