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

    # Your VSCodium momentum scrolling script. scroll-anywhere-vscode.js is baked
    # into VSCodium's workbench.html by the vscodium-momentum override in yeove.nix.
    # Pull script changes with: nix flake update momentum-nav
    momentum-nav = {
      url = "github:Yeove/VSCode_Addon_MomentumNavigation";
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
          { home-manager.extraSpecialArgs = { inherit inputs; }; } # lets HM files like yeove.nix use inputs
          ./hosts/PC2-nixos
        ];
      };

      # A second seat later is one more entry pointing at hosts/<name>,
      # reusing the same modules/.
    };
}
