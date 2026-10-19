# NetworkManager, Tailscale, and Mullvad (parked).
{ pkgs, ... }:

{
  networking.networkmanager.enable = true;

  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641, for direct rather than relayed connections
    useRoutingFeatures = "client"; # exit nodes / subnet routes; also sets the loose reverse-path filter
  };

  # Lets tailnet peers reach services running on this machine.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # Mullvad is parked on purpose: it fights Tailscale for DNS and routing,
  # and *.yeove.com stops resolving while it's connected. To use it anyway,
  # uncomment all three (the package line is what gives you the GUI app).
  # services.mullvad-vpn.enable = true;
  # services.mullvad-vpn.package = pkgs.mullvad-vpn;
  # services.resolved.enable = true;
}
