{ ... }:

# Enable all terminfo entries so SSH sessions from Ghostty, Kitty,
# WezTerm, Foot, etc. work correctly on headless servers without
# needing TERM=xterm-256color workarounds.
{
  environment.enableAllTerminfo = true;
}
