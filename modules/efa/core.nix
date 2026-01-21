{ config, lib, ... }:
let
  cfg = config.efa;
in {
  options.efa = {
    version = lib.mkOption {
      type = lib.types.str;
      default = "5.0.0-11";
      description = "eFa version string for /etc/eFa-Version.";
    };
    sources = {
      efaSrcRoot = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to eFa-5.0.0 source root (contains eFa/ and updates/).";
      };
      efaBaseSrcRoot = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to eFa-base-5.0.0 source root (contains eFa/ and eFaInit/).";
      };
    };
  };

  config = {
    environment.etc."eFa-Version".text = "eFa-${cfg.version}\n";
  };
}
