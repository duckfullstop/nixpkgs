{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.docker-containers;

  dockerContainer =
    { name, config, ... }: {

      options = {

        image = mkOption {
          type = types.str;
          description = "Docker image to run.";
          example = "library/hello-world";
        };

        cmd = mkOption {
          type =  with types; listOf str;
          default = [];
          description = "Commandline arguments to pass to the image's entrypoint.";
          example = literalExample ''
            ["--port=9000"]
          '';
        };

        devices = mkOption {
          type = with types; listOf str;
          default = [];
          description = ''
            List of Linux devices to directly expose to this container.
            Use with caution; mappings can potentially give far more access than you perhaps intend!

            There are also some mount options available
            as a third field; please refer to the
            <link xlink:href="https://docs.docker.com/engine/reference/commandline/run/#add-host-device-to-container---device">
            docker engine documentation</link> for details.
          '';
          example = literalExample ''
            [
              "/dev/dvb"
              "/dev/dri:/dev/dri:r"
              "/dev/sdb:/dev/sdb:rw"
            ]
          '';
        };

        entrypoint = mkOption {
          type = with types; nullOr str;
          description = "Overwrite the default entrypoint of the image.";
          default = null;
          example = "/bin/my-app";
        };

        environment = mkOption {
          type = with types; attrsOf str;
          default = {};
          description = "Environment variables to set for this container.";
          example = literalExample ''
            {
              DATABASE_HOST = "db.example.com";
              DATABASE_PORT = "3306";
            }
        '';
        };

        hostname = mkOption {
          type = with types; nullOr str;
          description = ''
            Set the hostname inside the container.
            If this is not set, the container will assume a hostname corresponding
            to its engine ID, or the host's hostname if using host networking
            (see the "network" option)
          '';
          default = null;
          example = "MyFancyDockerContainer";
        };

        labels = mkOption {
          type = with types; attrsOf str;
          default = {};
          description = ''
            Labels that should be applied to this container.

            For more details on labels, refer to the
            <link xlink:href="https://docs.docker.com/config/labels-custom-metadata/">
            Docker documentation</link>
          '';
          example = literalExample ''
            {
              "traefik.port" = "80";
              "traefik.enable" = "true"
              "mylabel.container.is-cool" = "true";
            }
        '';
        };

        log-driver = mkOption {
          type = types.str;
          default = "none";
          description = ''
            Logging driver for the container.  The default of
            <literal>"none"</literal> means that the container's logs will be
            handled as part of the systemd unit.  Setting this to
            <literal>"journald"</literal> will result in duplicate logging, but
            the container's logs will be visible to the <command>docker
            logs</command> command.

            For more details and a full list of logging drivers, refer to the
            <link xlink:href="https://docs.docker.com/engine/reference/run/#logging-drivers---log-driver">
            Docker engine documentation</link>
          '';
        };

        network = mkOption {
          type = types.str;
          default = "bridge";
          description = ''
            Network setting for the container.  The default of
            <literal>"bridge"</literal> means that the container will be
            connected to the default Docker bridge network.

            For more details and a full list of options, refer to the
            <link xlink:href="https://docs.docker.com/engine/reference/run/#network-settings">
            Docker engine documentation</link>
          '';
          example = "host";
        };

        ports = mkOption {
          type = with types; listOf str;
          default = [];
          description = ''
            Network ports to publish from the container to the outer host.

            Valid formats:

            <itemizedlist>
              <listitem>
                <para>
                  <literal>&lt;ip&gt;:&lt;hostPort&gt;:&lt;containerPort&gt;</literal>
                </para>
              </listitem>
              <listitem>
                <para>
                  <literal>&lt;ip&gt;::&lt;containerPort&gt;</literal>
                </para>
              </listitem>
              <listitem>
                <para>
                  <literal>&lt;hostPort&gt;:&lt;containerPort&gt;</literal>
                </para>
              </listitem>
              <listitem>
                <para>
                  <literal>&lt;containerPort&gt;</literal>
                </para>
              </listitem>
            </itemizedlist>

            Both <literal>hostPort</literal> and
            <literal>containerPort</literal> can be specified as a range of
            ports.  When specifying ranges for both, the number of container
            ports in the range must match the number of host ports in the
            range.  Example: <literal>1234-1236:1234-1236/tcp</literal>

            When specifying a range for <literal>hostPort</literal> only, the
            <literal>containerPort</literal> must <emphasis>not</emphasis> be a
            range.  In this case, the container port is published somewhere
            within the specified <literal>hostPort</literal> range.  Example:
            <literal>1234-1236:1234/tcp</literal>

            Refer to the
            <link xlink:href="https://docs.docker.com/engine/reference/run/#expose-incoming-ports">
            Docker engine documentation</link> for full details.
          '';
          example = literalExample ''
            [
              "8080:9000"
            ]
          '';
        };

        user = mkOption {
          type = with types; nullOr str;
          default = null;
          description = ''
            Override the username or UID (and optionally groupname or GID) used
            in the container.
          '';
          example = "nobody:nogroup";
        };

        volumes = mkOption {
          type = with types; listOf str;
          default = [];
          description = ''
            List of volumes to attach to this container.

            Note that this is a list of <literal>"src:dst"</literal> strings to
            allow for <literal>src</literal> to refer to
            <literal>/nix/store</literal> paths, which would difficult with an
            attribute set.  There are also a variety of mount options available
            as a third field; please refer to the
            <link xlink:href="https://docs.docker.com/engine/reference/run/#volume-shared-filesystems">
            docker engine documentation</link> for details.
          '';
          example = literalExample ''
            [
              "volume_name:/path/inside/container"
              "/path/on/host:/path/inside/container"
            ]
          '';
        };

        workdir = mkOption {
          type = with types; nullOr str;
          default = null;
          description = "Override the default working directory for the container.";
          example = "/var/lib/hello_world";
        };

        extraDockerOptions = mkOption {
          type = with types; listOf str;
          default = [];
          description = "Extra options for <command>docker run</command>.";
          example = literalExample ''
            ["--cpus 1"]
          '';
        };
      };
    };

  mkService = name: container: {
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "docker.socket" ];
    requires = [ "docker.service" "docker.socket" ];
    serviceConfig = {
      ExecStartPre = [
        # The - at the beginning of this rm command denotes that it is optional
        # (ie if the RM fails because the container, say, doesn't exist, systemd will continue)
        "-${pkgs.docker}/bin/docker rm -f %n" 
        "${pkgs.docker}/bin/docker pull ${container.image}"
        (concatStringsSep " \\\n  " ([
          "${pkgs.docker}/bin/docker create"
          "--name=%n"
          "--log-driver=${container.log-driver}"
          "--network=${container.network}"
        ] ++ optional (container.entrypoint != null)
          "--entrypoint=${escapeShellArg container.entrypoint}"
          ++ map (d: "--device ${escapeShellArg d}") container.devices
          ++ (mapAttrsToList (k: v: "-e ${escapeShellArg k}=${escapeShellArg v}") container.environment)
          ++ optional (container.hostname != null)
          "-h ${escapeShellArg container.hostname}"
          ++ (mapAttrsToList (k: v: "-l ${escapeShellArg k}=${escapeShellArg v}") container.labels)
          ++ map (p: "-p ${escapeShellArg p}") container.ports
          ++ optional (container.user != null) "-u ${escapeShellArg container.user}"
          ++ map (v: "-v ${escapeShellArg v}") container.volumes
          ++ optional (container.workdir != null) "-w ${escapeShellArg container.workdir}"
          ++ map escapeShellArg container.extraDockerOptions
          ++ [container.image]
          ++ map escapeShellArg container.cmd
        ))
      ];
      ExecStart = "${pkgs.docker}/bin/docker start -a %n";
      ExecStop = "${pkgs.docker}/bin/docker stop %n";
      ExecStopPost = "-${pkgs.docker}/bin/docker rm -f %n"; # see - optional note as above

      ### There is no generalized way of supporting `reload` for docker
      ### containers. Some containers may respond well to SIGHUP sent to their
      ### init process, but it is not guaranteed; some apps have other reload
      ### mechanisms, some don't have a reload signal at all, and some docker
      ### images just have broken signal handling.  The best compromise in this
      ### case is probably to leave ExecReload undefined, so `systemctl reload`
      ### will at least result in an error instead of potentially undefined
      ### behaviour.
      ###
      ### Advanced users can still override this part of the unit to implement
      ### a custom reload handler, since the result of all this is a normal
      ### systemd service from the perspective of the NixOS module system.
      ###
      # ExecReload = ...;
      ###

      TimeoutStartSec = 0;
      TimeoutStopSec = 120;
      Restart = "always";
    };
  };

in {

  options.docker-containers = mkOption {
    default = {};
    type = types.attrsOf (types.submodule dockerContainer);
    description = "Docker containers to run as systemd services.";
  };

  config = mkIf (cfg != {}) {

    systemd.services = mapAttrs' (n: v: nameValuePair "docker-${n}" (mkService n v)) cfg;

    virtualisation.docker.enable = true;

  };

}
