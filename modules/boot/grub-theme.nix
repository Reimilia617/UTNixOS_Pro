{ pkgs, ... }:

{
  boot.loader.grub.theme = 
    pkgs.stdenv.mkDerivation {
      pname = "th-rm-grub-theme";
      version = "1.0";

      src = ../../themes/grub/th-rm;

      installPhase = ''
        mkdir -p $out
        cp -r ./* $out/
        '';
    };
}