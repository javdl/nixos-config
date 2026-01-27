{ config, lib, pkgs, ... }:

# Security audit module with auditd
#
# Comprehensive system auditing for security monitoring:
# - Process execution tracking
# - Sensitive file watching
# - Network/time changes
# - Kernel module operations
# - Mount operations

let
  cfg = config.services.securityAudit;
  inherit (lib) mkEnableOption mkOption types mkIf;
in {
  options.services.securityAudit = {
    enable = mkEnableOption "security auditing with auditd";

    failureMode = mkOption {
      type = types.enum [ "silent" "printk" "panic" ];
      default = "printk";
      description = "How to handle audit failures (silent, printk, or panic)";
    };

    logFile = mkOption {
      type = types.str;
      default = "/var/log/audit/audit.log";
      description = "Path to the audit log file";
    };

    maxLogFile = mkOption {
      type = types.int;
      default = 50;
      description = "Maximum log file size in MB before rotation";
    };

    numLogs = mkOption {
      type = types.int;
      default = 10;
      description = "Number of log files to keep";
    };
  };

  config = mkIf cfg.enable {
    # Enable the audit daemon
    security.auditd.enable = true;

    # Enable audit at boot (kernel parameter)
    security.audit = {
      enable = true;
      failureMode = cfg.failureMode;

      rules = [
        # Delete all existing rules
        "-D"

        # Set buffer size for busy systems
        "-b 8192"

        # Failure mode (0=silent, 1=printk, 2=panic)
        "-f ${if cfg.failureMode == "silent" then "0" else if cfg.failureMode == "printk" then "1" else "2"}"

        # Monitor process execution
        "-a always,exit -F arch=b64 -S execve -k process_execution"
        "-a always,exit -F arch=b32 -S execve -k process_execution"

        # Monitor sensitive files
        "-w /etc/passwd -p wa -k identity"
        "-w /etc/group -p wa -k identity"
        "-w /etc/shadow -p wa -k identity"
        "-w /etc/gshadow -p wa -k identity"
        "-w /etc/sudoers -p wa -k sudoers"
        "-w /etc/sudoers.d/ -p wa -k sudoers"

        # Monitor SSH configuration and keys
        "-w /etc/ssh/ -p wa -k sshd_config"
        "-w /root/.ssh/ -p wa -k ssh_keys"

        # Monitor user SSH directories (common locations)
        "-w /home/ -p wa -k user_home"

        # Monitor network configuration
        "-w /etc/hosts -p wa -k network_config"
        "-w /etc/hostname -p wa -k network_config"
        "-w /etc/resolv.conf -p wa -k network_config"

        # Monitor time changes
        "-a always,exit -F arch=b64 -S adjtimex -S settimeofday -k time_change"
        "-a always,exit -F arch=b32 -S adjtimex -S settimeofday -S stime -k time_change"
        "-a always,exit -F arch=b64 -S clock_settime -k time_change"
        "-a always,exit -F arch=b32 -S clock_settime -k time_change"
        "-w /etc/localtime -p wa -k time_change"

        # Monitor kernel module loading/unloading
        "-w /sbin/insmod -p x -k modules"
        "-w /sbin/rmmod -p x -k modules"
        "-w /sbin/modprobe -p x -k modules"
        "-a always,exit -F arch=b64 -S init_module -S delete_module -k modules"
        "-a always,exit -F arch=b32 -S init_module -S delete_module -k modules"

        # Monitor mount operations
        "-a always,exit -F arch=b64 -S mount -S umount2 -k mounts"
        "-a always,exit -F arch=b32 -S mount -S umount -S umount2 -k mounts"

        # Monitor privileged commands
        "-a always,exit -F path=/usr/bin/sudo -F perm=x -k privileged_sudo"
        "-a always,exit -F path=/usr/bin/su -F perm=x -k privileged_su"

        # Monitor login/logout events
        "-w /var/log/lastlog -p wa -k logins"
        "-w /var/log/wtmp -p wa -k logins"
        "-w /var/log/btmp -p wa -k logins"

        # Monitor cron jobs
        "-w /etc/cron.d/ -p wa -k cron"
        "-w /etc/crontab -p wa -k cron"

        # Monitor PAM configuration
        "-w /etc/pam.d/ -p wa -k pam"
        "-w /etc/security/ -p wa -k pam"

        # Monitor systemd service changes
        "-w /etc/systemd/ -p wa -k systemd"
        "-w /usr/lib/systemd/ -p wa -k systemd"
      ];
    };

    # Add ausearch and aureport tools
    environment.systemPackages = with pkgs; [
      audit  # Provides ausearch, aureport, auditctl
    ];
  };
}
