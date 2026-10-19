{
  description = "Yeove's NixOS workstations";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    

    home-manager = {
      url = "github:nix-community/home-manager"; # master tracks unstable
      inputs.nixpkgs.follows = "nixpkgs"; # HM must track the same release as nixpkgs
    };
        
    # Your Firefox CSS repo. Only the AutoConfig loader (yeovefirefox.cfg) is
    # read from here; the chrome folder is symlinked from a local clone.
    firefox-css = {
      url = "github:Yeove/Yeoves_Custom_Firefox_CSS";
      flake = false;
    };
    
  };

  outputs =
    { nixpkgs, home-manager, ... }@inputs:
    {
      # The name matches networking.hostName, so `nh os switch` and
      # `nixos-rebuild --flake .` pick it automatically.
      nixosConfigurations.PC2-nixos = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          home-manager.nixosModules.home-manager
          ./hosts/PC2-nixos
        ];
      };

      # A second seat later is one more entry pointing at hosts/<name>,
      # reusing the same modules/.
    };
}
