{ config, lib, pkgs, ... }:
let
  cfg = config.efa.rspamd;
in {
  options.efa.rspamd = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Rspamd for spam filtering.";
    };
    redisHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Redis host for Rspamd state.";
    };
    redisPort = lib.mkOption {
      type = lib.types.port;
      default = 6379;
      description = "Redis port for Rspamd state.";
    };
    geoipDbPath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "GeoIP2 Country DB path for relay country lookups (null disables).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.redis.servers."".enable = lib.mkDefault true;

    services.rspamd = {
      enable = true;
      workers.rspamd_proxy = {
        bindSockets = [ "127.0.0.1:11332" ];
      };
      locals =
      {
        "actions.conf".text = ''
          add_header = 4.0;
          greylist = 6.0;
          reject = 7.0;
        '';
        "milter.conf".text = ''
          milter {
            add_headers = "both";
            reject_message = "Rejected by eFa Rspamd policy";
          }
        '';
        "redis.conf".text = ''
          servers = "${cfg.redisHost}:${toString cfg.redisPort}";
        '';
        "classifier-bayes.conf".text = ''
          backend = "redis";
          autolearn = [ -0.1, 6.0 ];
          min_tokens = 11;
          min_learns = 200;
        '';
        "reputation.conf".text = ''
          backend = "redis";
          symbols = {
            REPUTATION_BAD = {
              score = 2.0;
            }
            REPUTATION_GOOD = {
              score = -1.0;
            }
          }
        '';
        "history_redis.conf".text = ''
          backend = "redis";
        '';
        "dcc.conf".text = ''
          enabled = false;
        '';
        "pyzor.conf".text = ''
          enabled = false;
        '';
        "razor.conf".text = ''
          enabled = false;
        '';
      }
      // lib.optionalAttrs (cfg.geoipDbPath != null) {
        "geoip.conf".text = ''
          enabled = true;
          path = "${cfg.geoipDbPath}";
        '';
      };
    };
  };
}
