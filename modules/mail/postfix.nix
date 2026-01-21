{ config, lib, pkgs, ... }:
let
  cfg = config.efa.mail;
  recipientRestrictions =
    [
      "permit_sasl_authenticated"
      "permit_mynetworks"
      "reject_unauth_destination"
      "reject_non_fqdn_recipient"
      "reject_unknown_recipient_domain"
      "check_recipient_access hash:/etc/postfix/recipient_access"
    ]
    ++ lib.optional cfg.enableSqlgrey "check_policy_service inet:127.0.0.1:2501"
    ++ [ "reject_unverified_recipient" ];
  trustedNetworks = lib.concatStringsSep " " cfg.trustedNetworks;
in {
  options.efa.mail = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "mail.example.com";
      description = "Primary Postfix hostname.";
    };
    mydomain = lib.mkOption {
      type = lib.types.str;
      default = "example.com";
      description = "Mail domain for Postfix.";
    };
    trustedNetworks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "127.0.0.0/8" "[::1]/128" ];
      description = "Networks treated as trusted by Postfix.";
    };
    enableSqlgrey = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable SQLGrey policy service in recipient restrictions.";
    };
    milterAddress = lib.mkOption {
      type = lib.types.str;
      default = "inet:127.0.0.1:11332";
      description = "Milter socket address (Rspamd by default).";
    };
    tlsPemFile = lib.mkOption {
      type = lib.types.str;
      default = "/etc/postfix/ssl/smtpd.pem";
      description = "Path to combined TLS cert/key PEM for Postfix.";
    };
  };

  config = {
    users.groups.mtagroup = {};
    users.users.postfix.extraGroups = [ "mtagroup" ];

    services.postfix = {
      enable = true;
      hostname = cfg.hostname;
      domain = cfg.mydomain;
      networks = cfg.trustedNetworks;
      config = {
        inet_protocols = "ipv4, ipv6";
        inet_interfaces = "all";
        mynetworks = lib.mkForce trustedNetworks;
        header_checks = "regexp:${pkgs.writeText "postfix-header_checks" "# Add header_checks rules here.\n"}";
        myorigin = "$mydomain";
        mydestination = "$myhostname, localhost.$mydomain, localhost";
        relay_domains = "hash:/etc/postfix/transport";
        transport_maps = "hash:/etc/postfix/transport";
        local_recipient_maps = "";
        smtpd_helo_required = "yes";
        smtpd_delay_reject = "yes";
        disable_vrfy_command = "yes";
        virtual_alias_maps = "hash:/etc/postfix/virtual";
        alias_maps = lib.mkForce "hash:/etc/aliases";
        alias_database = lib.mkForce "hash:/etc/aliases";
        default_destination_recipient_limit = "1";
        smtp_use_tls = "yes";
        smtpd_use_tls = "yes";
        smtp_tls_CAfile = lib.mkForce cfg.tlsPemFile;
        smtp_tls_session_cache_database = "btree:/var/lib/postfix/smtp_tls_session_cache";
        smtp_tls_note_starttls_offer = "yes";
        smtpd_tls_key_file = cfg.tlsPemFile;
        smtpd_tls_cert_file = cfg.tlsPemFile;
        smtpd_tls_CAfile = lib.mkForce cfg.tlsPemFile;
        smtpd_tls_loglevel = "1";
        smtpd_tls_received_header = "yes";
        smtpd_tls_session_cache_timeout = "3600s";
        tls_random_source = "dev:/dev/urandom";
        smtpd_tls_session_cache_database = "btree:/var/lib/postfix/smtpd_tls_session_cache";
        smtpd_tls_security_level = "may";
        smtp_tls_security_level = "may";
        smtpd_tls_mandatory_protocols = "!SSLv2,!SSLv3";
        smtp_tls_mandatory_protocols = "!SSLv2,!SSLv3";
        smtpd_tls_protocols = "!SSLv2,!SSLv3";
        smtp_tls_protocols = "!SSLv2,!SSLv3";
        tls_preempt_cipherlist = "yes";
        tls_medium_cipherlist = "ECDSA+AESGCM:ECDH+AESGCM:DH+AESGCM:ECDSA+AES:ECDH+AES:DH+AES:ECDH+3DES:DH+3DES:RSA+AESGCM:RSA+AES:RSA+3DES:!aNULL:!MD5:!DSS";
        smtpd_tls_ciphers = "medium";
        smtpd_helo_restrictions = "check_helo_access hash:/etc/postfix/helo_access, reject_invalid_hostname";
        smtpd_sender_restrictions = "permit_sasl_authenticated, check_sender_access hash:/etc/postfix/sender_access, reject_non_fqdn_sender, reject_unknown_sender_domain";
        smtpd_data_restrictions = "reject_unauth_pipelining";
        smtpd_forbid_unauth_pipelining = "yes";
        smtpd_discard_ehlo_keywords = "chunking, silent-discard";
        smtpd_forbid_bare_newline = "yes";
        smtpd_forbid_bare_newline_exclusions = "$mynetworks";
        smtpd_client_restrictions = "permit_sasl_authenticated, permit_mynetworks, reject_rbl_client zen.spamhaus.org";
        smtpd_relay_restrictions = "permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination";
        smtpd_recipient_restrictions = lib.concatStringsSep ", " recipientRestrictions;
        unverified_recipient_reject_reason = "No user at this address";
        unverified_recipient_reject_code = "550";
        smtpd_milters = cfg.milterAddress;
        non_smtpd_milters = "";
        message_size_limit = "133169152";
        mailbox_size_limit = "133169152";
        qmqpd_authorized_clients = "127.0.0.1 [::1]";
        enable_long_queue_ids = "yes";
        error_notice_recipient = "root";
        sender_canonical_maps = "hash:/etc/postfix/sender_canonical";
        recipient_canonical_maps = "hash:/etc/postfix/recipient_canonical";
      };
      masterConfig = {
        submission = {
          type = "inet";
          private = false;
          chroot = false;
          command = "smtpd";
          args = [
            "-o"
            "smtpd_tls_security_level=encrypt"
            "-o"
            "smtpd_sasl_auth_enable=yes"
            "-o"
            "smtpd_sasl_type=dovecot"
            "-o"
            "smtpd_sasl_path=private/auth"
            "-o"
            "smtpd_sasl_security_options=noanonymous"
            "-o"
            "smtpd_sasl_local_domain=$myhostname"
            "-o"
            "smtpd_client_restrictions=permit_sasl_authenticated,reject"
            "-o"
            "smtpd_sender_login_maps=hash:/etc/postfix/virtual"
            "-o"
            "smtpd_recipient_restrictions=reject_non_fqdn_recipient,reject_unknown_recipient_domain,permit_sasl_authenticated,reject"
          ];
        };
        qmqp = {
          type = "unix";
          private = false;
          chroot = false;
          command = "qmqpd";
        };
      };
    };

    services.postfix.mapFiles = {
      transport = pkgs.writeText "postfix-transport" "# Add transport map entries here\n";
      virtual = pkgs.writeText "postfix-virtual" "# Add virtual alias entries here\n";
      helo_access = pkgs.writeText "postfix-helo_access" "# Add HELO access entries here\n";
      sender_access = pkgs.writeText "postfix-sender_access" "# Add sender access entries here\n";
      recipient_access = pkgs.writeText "postfix-recipient_access" "# Add recipient access entries here\n";
      sasl_passwd = pkgs.writeText "postfix-sasl_passwd" "# Add SASL relay credentials here\n";
      sender_canonical = pkgs.writeText "postfix-sender_canonical" "# Add sender canonical map entries here\n";
      recipient_canonical = pkgs.writeText "postfix-recipient_canonical" "# Add recipient canonical map entries here\n";
    };

    systemd.tmpfiles.rules = [
      "d /etc/postfix/ssl 0750 root postfix -"
      "d /var/spool/postfix/hold 0750 postfix mtagroup -"
      "d /var/spool/postfix/incoming 0750 postfix mtagroup -"
    ];
  };
}
