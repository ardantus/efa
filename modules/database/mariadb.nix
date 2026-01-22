{ config, lib, pkgs, ... }:
let
  cfg = config.efa.database;
  mailscannerSchema = builtins.readFile ./sql/create.sql;
  bayesSchema = builtins.readFile ./sql/bayes_mysql.sql;
  opendmarcSchema = builtins.readFile ./sql/schema.mysql;
  efaTokensSchema = builtins.readFile ./sql/efatokens.sql;
  initSql = pkgs.writeText "efa-mariadb-init.sql" ''
    ${mailscannerSchema}

    CREATE DATABASE IF NOT EXISTS sa_bayes;
    USE sa_bayes;
    ${bayesSchema}

    ${opendmarcSchema}

    ${efaTokensSchema}
  '';
in {
  options.efa.database = {
    bootstrapSecrets = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Create default DB password files in /run/secrets if missing (dev/local only).";
    };
    mailwatchUser = lib.mkOption {
      type = lib.types.str;
      default = "mailwatch";
      description = "MailWatch database user.";
    };
    sqlgreyUser = lib.mkOption {
      type = lib.types.str;
      default = "sqlgrey";
      description = "SQLGrey database user.";
    };
    saUser = lib.mkOption {
      type = lib.types.str;
      default = "sa_user";
      description = "SpamAssassin/Rspamd Bayes database user.";
    };
    opendmarcUser = lib.mkOption {
      type = lib.types.str;
      default = "opendmarc";
      description = "OpenDMARC database user.";
    };
    efaUser = lib.mkOption {
      type = lib.types.str;
      default = "efa";
      description = "eFa token database user.";
    };
    mailwatchPassFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/mailwatch-db-pass";
      description = "Path to MailWatch database password file.";
    };
    sqlgreyPassFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/sqlgrey-db-pass";
      description = "Path to SQLGrey database password file.";
    };
    saPassFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/sa-db-pass";
      description = "Path to Bayes/TxRep database password file.";
    };
    opendmarcPassFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/opendmarc-db-pass";
      description = "Path to OpenDMARC database password file.";
    };
    efaPassFile = lib.mkOption {
      type = lib.types.str;
      default = "/run/secrets/efa-db-pass";
      description = "Path to eFa token database password file.";
    };
  };

  config = {
    # Note: /var/lib/mysql is created by NixOS mysql module, but ensure it exists for plugin directory
    systemd.tmpfiles.rules = [
      "d /var/lib/mysql 0755 root root -"
      "d /var/lib/mysql/plugin 0755 root root -"
      "d /run/mysqld 0755 mysql mysql -"
    ];

    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      ensureDatabases = [
        "mailscanner"
        "sa_bayes"
        "sqlgrey"
        "opendmarc"
        "efa"
      ];
      initialScript = initSql;
      settings = {
        mysqld = {
          "character-set-server" = "utf8mb4";
          "init-connect" = "SET NAMES utf8mb4";
          "collation-server" = "utf8mb4_unicode_ci";
          "plugin_dir" = "/var/lib/mysql/plugin";
          "socket" = "/run/mysqld/mysqld.sock";
        };
        mariadb = {
          "bind-address" = "127.0.0.1";
          innodb-defragment = 1;
          innodb_buffer_pool_instances = 1;
          innodb_buffer_pool_size = "1G";
          innodb_file_per_table = 1;
          innodb_log_buffer_size = "32M";
          innodb_log_file_size = "125M";
          join_buffer_size = "512K";
          key_cache_segments = 4;
          "max_allowed_packet" = "16M";
          "max_heap_table_size" = "32M";
          "query_cache_size" = "0M";
          "query_cache_type" = "OFF";
          "read_buffer_size" = "2M";
          "read_rnd_buffer_size" = "1M";
          "skip-external-locking" = true;
          sort_buffer_size = "4M";
          thread_cache_size = 16;
          "tmp_table_size" = "32M";
        };
      };
    };

    systemd.services.mysql.serviceConfig = {
      LimitNOFILE = "infinity";
      LimitMEMLOCK = "infinity";
      TimeoutSec = 900;
    };

    systemd.services.mysql.preStart = lib.mkForce ''
      set -euo pipefail
      install -d -m 0750 -o mysql -g mysql /var/lib/mysql
      if [ ! -d /var/lib/mysql/mysql ]; then
        ${pkgs.mariadb}/bin/mariadb-install-db \
          --datadir=/var/lib/mysql \
          --plugin-dir=/var/lib/mysql/plugin \
          --user=mysql
      fi
    '';

    systemd.services.efa-mariadb-users = {
      description = "Ensure eFa MariaDB users/grants";
      after = [ "mysql.service" ];
      requires = [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        set -euo pipefail
        escape_sql() {
          printf "%s" "$1" | sed "s/'/''''/g"
        }
        read_secret() {
          local path="$1"
          if [ ! -r "$path" ]; then
            echo "Missing secret: $path" >&2
            exit 1
          fi
          cat "$path"
        }

        mailwatch_pass="$(read_secret "${cfg.mailwatchPassFile}")"
        sa_pass="$(read_secret "${cfg.saPassFile}")"
        sqlgrey_pass="$(read_secret "${cfg.sqlgreyPassFile}")"
        opendmarc_pass="$(read_secret "${cfg.opendmarcPassFile}")"
        efa_pass="$(read_secret "${cfg.efaPassFile}")"

        mailwatch_pass_esc="$(escape_sql "$mailwatch_pass")"
        sa_pass_esc="$(escape_sql "$sa_pass")"
        sqlgrey_pass_esc="$(escape_sql "$sqlgrey_pass")"
        opendmarc_pass_esc="$(escape_sql "$opendmarc_pass")"
        efa_pass_esc="$(escape_sql "$efa_pass")"

        ${pkgs.mariadb}/bin/mysql --protocol=socket -u root <<SQL
        CREATE USER IF NOT EXISTS '${cfg.mailwatchUser}'@'localhost' IDENTIFIED BY '$mailwatch_pass_esc';
        ALTER USER '${cfg.mailwatchUser}'@'localhost' IDENTIFIED BY '$mailwatch_pass_esc';
        GRANT ALL PRIVILEGES ON mailscanner.* TO '${cfg.mailwatchUser}'@'localhost';

        CREATE USER IF NOT EXISTS '${cfg.saUser}'@'localhost' IDENTIFIED BY '$sa_pass_esc';
        ALTER USER '${cfg.saUser}'@'localhost' IDENTIFIED BY '$sa_pass_esc';
        GRANT ALL PRIVILEGES ON sa_bayes.* TO '${cfg.saUser}'@'localhost';

        CREATE USER IF NOT EXISTS '${cfg.sqlgreyUser}'@'localhost' IDENTIFIED BY '$sqlgrey_pass_esc';
        ALTER USER '${cfg.sqlgreyUser}'@'localhost' IDENTIFIED BY '$sqlgrey_pass_esc';
        GRANT ALL PRIVILEGES ON sqlgrey.* TO '${cfg.sqlgreyUser}'@'localhost';

        CREATE USER IF NOT EXISTS '${cfg.opendmarcUser}'@'localhost' IDENTIFIED BY '$opendmarc_pass_esc';
        ALTER USER '${cfg.opendmarcUser}'@'localhost' IDENTIFIED BY '$opendmarc_pass_esc';
        GRANT ALL PRIVILEGES ON opendmarc.* TO '${cfg.opendmarcUser}'@'localhost';

        CREATE USER IF NOT EXISTS '${cfg.efaUser}'@'localhost' IDENTIFIED BY '$efa_pass_esc';
        ALTER USER '${cfg.efaUser}'@'localhost' IDENTIFIED BY '$efa_pass_esc';
        GRANT ALL PRIVILEGES ON efa.* TO '${cfg.efaUser}'@'localhost';

        FLUSH PRIVILEGES;
        SQL
      '';
    };

    # Keep legacy eFa location in sync for sgwi/sqlgrey tooling:
    # sgwi expects /etc/eFa/SQLGrey-Config with "SQLGREYSQLPWD:<password>"
    systemd.services.efa-sqlgrey-config = {
      description = "Write /etc/eFa/SQLGrey-Config from secret";
      after = [ "mysql.service" ];
      requires = [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        install -d -m 0755 /etc/eFa

        if [ ! -r "${cfg.sqlgreyPassFile}" ]; then
          echo "Missing secret: ${cfg.sqlgreyPassFile}" >&2
          echo "Set efa.database.sqlgreyPassFile to a readable path, or enable efa.database.bootstrapSecrets for dev." >&2
          exit 1
        fi

        sqlgrey_pass="$(cat "${cfg.sqlgreyPassFile}")"
        umask 077
        printf "SQLGREYSQLPWD:%s\n" "$sqlgrey_pass" > /etc/eFa/SQLGrey-Config
        # sgwi runs under nginx, so allow group read
        chown root:root /etc/eFa/SQLGrey-Config
        chgrp nginx /etc/eFa/SQLGrey-Config 2>/dev/null || true
        chmod 0440 /etc/eFa/SQLGrey-Config
      '';
    };

    # Ensure MailWatch schema is applied (idempotent - CREATE TABLE IF NOT EXISTS)
    systemd.services.efa-mailwatch-schema = {
      description = "Ensure MailWatch database schema";
      after = [ "mysql.service" "efa-mariadb-users.service" ];
      requires = [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail

        echo "Ensuring MailWatch schema exists..."
        # Use root to apply full schema (includes multiple databases)
        ${pkgs.mariadb}/bin/mysql --protocol=socket -u root < ${initSql}

        # Create default admin user if not exists (password: admin)
        # MD5 hash of 'admin' for MailWatch compatibility
        ADMIN_HASH="21232f297a57a5a743894a0e4a801fc3"

        ${pkgs.mariadb}/bin/mysql --protocol=socket -u root mailscanner -e \
          "INSERT IGNORE INTO users (username, password, fullname, type, quarantine_report) VALUES ('admin', '$ADMIN_HASH', 'Administrator', 'A', 0);"

        echo "MailWatch schema and admin user ready."
      '';
    };

    system.activationScripts.efaDbSecrets = lib.mkIf cfg.bootstrapSecrets ''
      set -euo pipefail
      install -d -m 0700 /run/secrets
      for name in mailwatch sqlgrey sa opendmarc efa; do
        path="/run/secrets/''${name}-db-pass"
        if [ ! -s "$path" ]; then
          printf "nixos\n" > "$path"
          chmod 0400 "$path"
        fi
      done
    '';

    system.activationScripts.efaMariaDbPlugins = ''
      set -euo pipefail
      if [ -d ${pkgs.mariadb}/lib/mysql/plugin ]; then
        # Ensure parent directories exist before rsync
        # Create /var/lib/mysql first if it doesn't exist
        mkdir -p /var/lib/mysql
        chmod 0755 /var/lib/mysql
        chown root:root /var/lib/mysql
        # Then create plugin subdirectory
        mkdir -p /var/lib/mysql/plugin
        chmod 0755 /var/lib/mysql/plugin
        chown root:root /var/lib/mysql/plugin
        # Now rsync can safely create files in the directory
        ${pkgs.rsync}/bin/rsync -a --delete ${pkgs.mariadb}/lib/mysql/plugin/ /var/lib/mysql/plugin/
        chown -R root:root /var/lib/mysql/plugin
        chmod -R 0755 /var/lib/mysql/plugin
      fi
    '';

    system.activationScripts.efaMariaDbCleanup = ''
      set -euo pipefail
      if [ -f /etc/my.cnf.d/mariadb-server.cnf ]; then
        rm -f /etc/my.cnf.d/mariadb-server.cnf
      fi
      if [ -f /etc/my.cnf ]; then
        rm -f /etc/my.cnf
      fi
    '';
  };
}
