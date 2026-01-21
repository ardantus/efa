{ config, lib, pkgs, ... }:
let
  cfg = config.efa.geoip;
in {
  options.efa.geoip = {
    enable = lib.mkEnableOption "GeoIP database for MailWatch";

    # MaxMind GeoLite2 requires license key (free registration)
    # Alternative: Use IP2Location or other free databases
    maxmindLicenseKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "MaxMind GeoLite2 license key (get free key from maxmind.com).";
    };

    # Alternative: Use free GeoIP database from IP2Location or other sources
    useFreeDatabase = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use free GeoIP database (IP2Location Lite or similar).";
    };
  };

  config = lib.mkIf cfg.enable {
    # GeoIP directories
    systemd.tmpfiles.rules = [
      "d /usr/share/GeoIP 0755 root root -"
      "d /var/www/html/mailscanner/temp 0775 nginx nginx -"
    ];

    # Service to download GeoIP database
    systemd.services.geoip-download = {
      description = "Download GeoIP database for MailWatch";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        
        GEOIP_DIR="/usr/share/GeoIP"
        TEMP_DIR="/var/www/html/mailscanner/temp"
        DB_FILE="$TEMP_DIR/GeoLite2-Country.mmdb"
        
        mkdir -p "$GEOIP_DIR"
        mkdir -p "$TEMP_DIR"
        chown nginx:nginx "$TEMP_DIR"
        
        # Check if database already exists and is recent (less than 30 days old)
        if [ -f "$DB_FILE" ]; then
          FILE_AGE=$(( ($(date +%s) - $(stat -c %Y "$DB_FILE")) / 86400 ))
          if [ $FILE_AGE -lt 30 ]; then
            echo "GeoIP database is recent ($FILE_AGE days old), skipping download."
            exit 0
          fi
        fi
        
        echo "Downloading GeoIP database..."
        
        # Option 1: Use MaxMind GeoLite2 (requires license key)
        if [ -n "${if cfg.maxmindLicenseKey != null then cfg.maxmindLicenseKey else ""}" ]; then
          LICENSE_KEY="${cfg.maxmindLicenseKey}"
          echo "Using MaxMind GeoLite2 with license key..."
          ${pkgs.curl}/bin/curl -sSL \
            "https://download.maxmind.com/app/geoip_download?edition_id=GeoLite2-Country&license_key=$LICENSE_KEY&suffix=tar.gz" \
            -o /tmp/GeoLite2-Country.tar.gz || {
            echo "Warning: MaxMind download failed, trying alternative..."
            LICENSE_KEY=""
          }
          
          if [ -f /tmp/GeoLite2-Country.tar.gz ] && [ -n "$LICENSE_KEY" ]; then
            ${pkgs.gnutar}/bin/tar -xzf /tmp/GeoLite2-Country.tar.gz -C /tmp
            find /tmp -name "GeoLite2-Country.mmdb" -exec mv {} "$DB_FILE" \;
            rm -rf /tmp/GeoLite2-Country* /tmp/GeoLite2-Country.tar.gz
          fi
        fi
        
        # Option 2: Use db-ip.com free MMDB database (recommended free alternative, no license required)
        if [ ! -f "$DB_FILE" ]; then
          echo "Downloading db-ip.com free GeoIP database..."
          CURRENT_DATE=$(${pkgs.coreutils}/bin/date +%Y-%m)
          ${pkgs.curl}/bin/curl -sSL \
            "https://download.db-ip.com/free/dbip-country-lite-$CURRENT_DATE.mmdb.gz" \
            -o /tmp/dbip-country.mmdb.gz || {
            # Try previous month if current month not available
            # Calculate previous month (handle year rollover)
            CURRENT_YEAR=$(${pkgs.coreutils}/bin/date +%Y)
            CURRENT_MONTH=$(${pkgs.coreutils}/bin/date +%m)
            if [ "$CURRENT_MONTH" = "01" ]; then
              PREV_YEAR=$((CURRENT_YEAR - 1))
              PREV_MONTH="12"
            else
              PREV_YEAR=$CURRENT_YEAR
              PREV_MONTH=$(printf "%02d" $((CURRENT_MONTH - 1)))
            fi
            PREV_DATE="$PREV_YEAR-$PREV_MONTH"
            ${pkgs.curl}/bin/curl -sSL \
              "https://download.db-ip.com/free/dbip-country-lite-$PREV_DATE.mmdb.gz" \
              -o /tmp/dbip-country.mmdb.gz || {
              echo "Warning: db-ip download failed, trying alternative source..."
              # Alternative: Use GeoLite2 from GitHub (community maintained)
              ${pkgs.curl}/bin/curl -sSL \
                "https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-Country.mmdb" \
                -o "$DB_FILE" || {
                echo "Warning: All GeoIP database download attempts failed."
                echo "GeoIP features will not be available until database is downloaded."
                exit 0  # Don't fail, just continue without GeoIP
              }
            }
          }
          
          if [ -f /tmp/dbip-country.mmdb.gz ]; then
            ${pkgs.gzip}/bin/gunzip -c /tmp/dbip-country.mmdb.gz > "$DB_FILE"
            rm -f /tmp/dbip-country.mmdb.gz
            chown nginx:nginx "$DB_FILE"
            chmod 644 "$DB_FILE"
            echo "GeoIP database downloaded successfully from db-ip.com."
          elif [ -f "$DB_FILE" ]; then
            chown nginx:nginx "$DB_FILE"
            chmod 644 "$DB_FILE"
            echo "GeoIP database downloaded successfully from alternative source."
          fi
        fi
        
        # Create symlink for SpamAssassin/MailWatch compatibility
        if [ -f "$DB_FILE" ]; then
          ln -sf "$DB_FILE" "$GEOIP_DIR/GeoLite2-Country.mmdb" || true
          echo "GeoIP database symlink created."
        fi
      '';
    };

    # Timer to update GeoIP database monthly
    systemd.timers.geoip-update = {
      description = "Update GeoIP database monthly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "monthly";
        Persistent = true;
      };
    };
    systemd.services.geoip-update = {
      description = "Update GeoIP database";
      serviceConfig = {
        Type = "oneshot";
      };
      script = ''
        # Force download by removing old database
        rm -f /var/www/html/mailscanner/temp/GeoLite2-Country.mmdb
        systemctl start geoip-download.service
      '';
    };
  };
}
