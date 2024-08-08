# { inputs, ... }:
# {
#   programs.firefox = {
#     enable = true;

#     profiles.joost = {
#         extensions = with inputs.firefox-addons.packages."x86_64-linux"; [
#             bitwarden
#             bypass-paywalls-clean
#             darkreader
#             facebook-container
#             i-dont-care-about-cookies
#             privacy-badger
#             to-google-translate
#             view-image
#             ublock-origin
#             youtube-shorts-block
#         ];
#     };
#   };

#   programs.home-manager.enable = true;
# }
