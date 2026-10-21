# Public key radon uses for unattended OpenSSH into the DGX Sparks.
# Appended by users/dgx-spark.nix. The private half stays on radon at
# ~/.ssh/id_ed25519_sparks and is not in this repo.
# Fingerprint SHA256:ZDiov1MbGbm6Y7QU0KQqhhSg6M0nMG4F+8wZ+3eXUOE.
{
  radon = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC0qmMOUQk0gASZ6q3Txr/4e/26oZeyWNmPFRwyVHBtl radon-sparks";
}
