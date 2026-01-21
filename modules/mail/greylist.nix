{ config, lib, pkgs, ... }:
let
  cfg = config.efa.greylist;
in {
  options.efa.greylist = {
    enable = lib.mkEnableOption "SQLGrey greylisting service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2501;
      description = "Port for SQLGrey policy service.";
    };

    dbType = lib.mkOption {
      type = lib.types.enum [ "SQLite" "MySQL" ];
      default = "SQLite";
      description = "Database type for SQLGrey (SQLite or MySQL).";
    };
  };

  config = lib.mkIf cfg.enable {
    # SQLGrey package (simple Perl script, can be installed from nixpkgs or custom)
    # For now, we'll create a minimal package
    environment.systemPackages = [ pkgs.perl ];

    # SQLGrey directories
    systemd.tmpfiles.rules = [
      "d /var/lib/sqlgrey 0750 sqlgrey sqlgrey -"
      "d /etc/sqlgrey 0755 root root -"
    ];

    # SQLGrey user and group
    users.users.sqlgrey = {
      isSystemUser = true;
      group = "sqlgrey";
      home = "/var/lib/sqlgrey";
      description = "SQLGrey greylisting service";
    };
    users.groups.sqlgrey = {};

    # SQLGrey configuration
    environment.etc."sqlgrey/sqlgrey.conf".text = ''
      # SQLGrey configuration for eFa NixOS
      db_type = ${cfg.dbType}
      db_name = sqlgrey
      db_host = localhost
      db_user = sqlgrey
      db_pass = 
      db_socket = /var/lib/sqlgrey/sqlgrey.db
      
      # Policy service settings
      listen = 127.0.0.1:${toString cfg.port}
      
      # Greylisting settings
      greylist = 300
      whitelist_host = 86400
      whitelist_host_automatic = 2592000
      
      # Logging
      log_level = info
      log_facility = mail
    '';

    # SQLGrey systemd service
    # Note: Service disabled until SQLGrey package is properly built
    # For now, greylist menu will be available but service won't start
    # To enable: build SQLGrey package and set startService = true
    systemd.services.sqlgrey = lib.mkIf false {  # Disabled until package available
      description = "SQLGrey Postfix greylisting policy service";
      after = [ "network.target" ];
      wants = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.perl}/bin/perl -T /usr/sbin/sqlgrey";
        Restart = "on-failure";
        User = "sqlgrey";
        Group = "sqlgrey";
        RuntimeDirectory = "sqlgrey";
      };

      preStart = ''
        # Ensure database directory exists
        mkdir -p /var/lib/sqlgrey
        chown sqlgrey:sqlgrey /var/lib/sqlgrey
        chmod 750 /var/lib/sqlgrey
        
        # Create SQLite database if using SQLite
        if [ "${cfg.dbType}" = "SQLite" ] && [ ! -f /var/lib/sqlgrey/sqlgrey.db ]; then
          touch /var/lib/sqlgrey/sqlgrey.db
          chown sqlgrey:sqlgrey /var/lib/sqlgrey/sqlgrey.db
          chmod 640 /var/lib/sqlgrey/sqlgrey.db
        fi
      '';
    };

    # Schema for MySQL
    environment.etc."sqlgrey/schema.sql".text = ''
      CREATE TABLE IF NOT EXISTS connect (
        sender_name varchar(64) NOT NULL,
        sender_domain varchar(255) NOT NULL,
        src varchar(39) NOT NULL,
        rcpt varchar(255) NOT NULL,
        first_seen timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (sender_name, sender_domain, src, rcpt)
      );
      CREATE TABLE IF NOT EXISTS domain_awl (
        sender_domain varchar(255) NOT NULL,
        src varchar(39) NOT NULL,
        first_seen timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (sender_domain, src)
      );
      CREATE TABLE IF NOT EXISTS from_awl (
        sender_name varchar(64) NOT NULL,
        sender_domain varchar(255) NOT NULL,
        src varchar(39) NOT NULL,
        first_seen timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        last_seen timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (sender_name, sender_domain, src)
      );
      CREATE TABLE IF NOT EXISTS optout_domain (
        domain varchar(255) NOT NULL,
        PRIMARY KEY (domain)
      );
      CREATE TABLE IF NOT EXISTS optout_email (
        email varchar(255) NOT NULL,
        PRIMARY KEY (email)
      );
    '';

    # Service to initialize MySQL database
    systemd.services.sqlgrey-init-db = lib.mkIf (cfg.dbType == "MySQL") {
      description = "Initialize SQLGrey Database Schema";
      wantedBy = [ "multi-user.target" ];
      after = [ "mysql.service" "efa-mariadb-users.service" ];
      wants = [ "mysql.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        
        # Check if connect table exists
        if echo "DESCRIBE connect;" | ${pkgs.mariadb}/bin/mysql -u sqlgrey -p"$(grep ^SQLGREYSQLPWD: /etc/eFa/SQLGrey-Config | cut -d: -f2)" sqlgrey >/dev/null 2>&1; then
          echo "SQLGrey tables already exist."
        else
          echo "Initializing SQLGrey tables..."
          # Wait for MariaDB to be fully ready (just in case)
          sleep 5
          ${pkgs.mariadb}/bin/mysql -u sqlgrey -p"$(grep ^SQLGREYSQLPWD: /etc/eFa/SQLGrey-Config | cut -d: -f2)" sqlgrey < /etc/sqlgrey/schema.sql
          echo "SQLGrey tables created."
        fi
      '';
    };
  };
}
