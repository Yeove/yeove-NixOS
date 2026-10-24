# Custom Nautilus folder icons for /mnt/Production.
# Every <name>.svg in the icon folder is applied to /mnt/Production/<name>,
# if that folder exists. Folders without a matching SVG are left alone.
{ pkgs, ... }:

let
  root    = "/mnt/Production";
  iconDir = "${root}/24_UI/Icons/svg";

  setFolderIcons = pkgs.writeShellScript "set-folder-icons" ''
    shopt -s nullglob
    for icon in "${iconDir}"/*.svg; do
      name="$(${pkgs.coreutils}/bin/basename "$icon" .svg)"
      dir="${root}/$name"
      if [ -d "$dir" ]; then
        ${pkgs.glib}/bin/gio set "$dir" metadata::custom-icon "file://$icon"
      fi
    done
  '';
in
{
  systemd.user.services.folder-icons = {
    description = "Apply custom folder icons under ${root}";
    after    = [ "graphical-session.target" ];
    partOf   = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${setFolderIcons}";
    };
  };
}
