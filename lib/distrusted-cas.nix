# NSS labels of CA roots the whole fleet distrusts, on top of the pinned
# nixpkgs cacert. Consumed by security.pki.caCertificateBlacklist (NixOS and
# nix-darwin, via lib/mksystem.nix) and by SSL_CERT_FILE in
# users/shared-home-manager.nix.
#
# TEMPORARY (2026-10-23): eMudhra intermediate CA key compromise,
# https://emudhra.we-have-a-problem.com/ (Mozilla bug 2083449). The eight
# leaked intermediates chain to these two Mozilla-bundle roots ("Comodo AAA
# Services root" is the NSS label of "AAA Certificate Services"). Fixed
# upstream by cacert 3.131.1; backout steps are in AGENTS.md under
# "Temporary reminder: eMudhra roots distrust".
[
  "Comodo AAA Services root"
  "emSign ECC Root CA - G3"
]
