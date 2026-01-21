{ config, lib, ... }:
let
  cfg = config.efa.firewall;
in {
  options.efa.firewall = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Configure NixOS firewall for eFa services.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [
      22
      25
      80
      443
      587
    ];
  };
}
