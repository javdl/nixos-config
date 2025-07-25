#-------------------------------------------------------------------------------
# SSH Agent
#-------------------------------------------------------------------------------
function __ssh_agent_is_started -d "check if ssh agent is already started"
	if begin; test -f $SSH_ENV; and test -z "$SSH_AGENT_PID"; end
		source $SSH_ENV > /dev/null
	end

	if test -z "$SSH_AGENT_PID"
		return 1
	end

	ssh-add -l > /dev/null 2>&1
	if test $status -eq 2
		return 1
	end
end

function __ssh_agent_start -d "start a new ssh agent"
  ssh-agent -c | sed 's/^echo/#echo/' > $SSH_ENV
  chmod 600 $SSH_ENV
  source $SSH_ENV > /dev/null
  ssh-add
end

if not test -d $HOME/.ssh
    mkdir -p $HOME/.ssh
    chmod 0700 $HOME/.ssh
end

if test -d $HOME/.gnupg
    chmod 0700 $HOME/.gnupg
end

if test -z "$SSH_ENV"
    set -xg SSH_ENV $HOME/.ssh/environment
end

if not __ssh_agent_is_started
    __ssh_agent_start
end

#-------------------------------------------------------------------------------
# Ghostty Shell Integration
#-------------------------------------------------------------------------------
# Ghostty supports auto-injection but Nix-darwin hard overwrites XDG_DATA_DIRS
# which make it so that we can't use the auto-injection. We have to source
# manually.
if set -q GHOSTTY_RESOURCES_DIR
    source "$GHOSTTY_RESOURCES_DIR/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish"
end

#-------------------------------------------------------------------------------
# Programs
#-------------------------------------------------------------------------------
# Vim: We should move this somewhere else but it works for now
mkdir -p $HOME/.vim/{backup,swap,undo}

# Homebrew
if test -d "/opt/homebrew"
    set -gx HOMEBREW_PREFIX "/opt/homebrew";
    set -gx HOMEBREW_CELLAR "/opt/homebrew/Cellar";
    set -gx HOMEBREW_REPOSITORY "/opt/homebrew";
    set -q PATH; or set PATH ''; set -gx PATH "/opt/homebrew/bin" "/opt/homebrew/sbin" $PATH;
    set -q MANPATH; or set MANPATH ''; set -gx MANPATH "/opt/homebrew/share/man" $MANPATH;
    set -q INFOPATH; or set INFOPATH ''; set -gx INFOPATH "/opt/homebrew/share/info" $INFOPATH;
end

# Hammerspoon
if test -d "/Applications/Hammerspoon.app"
    set -q PATH; or set PATH ''; set -gx PATH "/Applications/Hammerspoon.app/Contents/Frameworks/hs" $PATH;
end

# Add ~/.local/bin
set -q PATH; or set PATH ''; set -gx PATH  "$HOME/.local/bin" $PATH;

#-------------------------------------------------------------------------------
# Prompt
#-------------------------------------------------------------------------------
# Do not show any greeting
set --universal --erase fish_greeting
function fish_greeting; end
funcsave fish_greeting

# bobthefish theme - using custom rose pine colors
set -g theme_color_scheme user

# Rose Pine color scheme
set -U fish_color_normal e0def4
set -U fish_color_command 9ccfd8
set -U fish_color_quote f6c177
set -U fish_color_redirection ebbcba
set -U fish_color_end eb6f92
set -U fish_color_error eb6f92
set -U fish_color_param e0def4
set -U fish_color_comment 6e6a86
set -U fish_color_match --background=403d52
set -U fish_color_selection e0def4 --bold --background=403d52
set -U fish_color_search_match --background=403d52
set -U fish_color_history_current --bold
set -U fish_color_operator c4a7e7
set -U fish_color_escape ebbcba
set -U fish_color_cwd 9ccfd8
set -U fish_color_cwd_root eb6f92
set -U fish_color_valid_path --underline
set -U fish_color_autosuggestion 6e6a86
set -U fish_color_user 31748f
set -U fish_color_host e0def4
set -U fish_color_cancel eb6f92
set -U fish_pager_color_completion e0def4
set -U fish_pager_color_description 6e6a86
set -U fish_pager_color_prefix e0def4 --bold --underline
set -U fish_pager_color_progress e0def4 --background=c4a7e7

# Rose Pine colors for bobthefish theme
set -g theme_color_dark_black 26233a
set -g theme_color_black 1f1d2e
set -g theme_color_light_black 403d52
set -g theme_color_grey 6e6a86
set -g theme_color_dark_grey 524f67
set -g theme_color_light_grey 908caa
set -g theme_color_dark_white e0def4
set -g theme_color_white e0def4
set -g theme_color_light_white e0def4
set -g theme_color_green 31748f
set -g theme_color_light_green 31748f
set -g theme_color_dark_green 31748f
set -g theme_color_red eb6f92
set -g theme_color_light_red eb6f92
set -g theme_color_dark_red eb6f92
set -g theme_color_yellow f6c177
set -g theme_color_light_yellow f6c177
set -g theme_color_dark_yellow f6c177
set -g theme_color_blue 9ccfd8
set -g theme_color_light_blue 9ccfd8
set -g theme_color_dark_blue 9ccfd8
set -g theme_color_cyan ebbcba
set -g theme_color_light_cyan ebbcba
set -g theme_color_dark_cyan ebbcba
set -g theme_color_purple c4a7e7
set -g theme_color_light_purple c4a7e7
set -g theme_color_dark_purple c4a7e7
set -g theme_color_violet c4a7e7
set -g theme_color_light_violet c4a7e7
set -g theme_color_dark_violet c4a7e7
set -g theme_color_magenta c4a7e7
set -g theme_color_light_magenta c4a7e7
set -g theme_color_dark_magenta c4a7e7
set -g theme_color_orange f6c177
set -g theme_color_light_orange f6c177
set -g theme_color_dark_orange f6c177

# Override the nix prompt for the theme so that we show a more concise prompt
function __bobthefish_prompt_nix -S -d 'Display current nix environment'
    [ "$theme_display_nix" = 'no' -o -z "$IN_NIX_SHELL" ]
    and return

    __bobthefish_start_segment $color_nix
    echo -ns N ' '

    set_color normal
end

#-------------------------------------------------------------------------------
# Vars
#-------------------------------------------------------------------------------
# Modify our path to include our Go binaries
contains $HOME/code/go/bin $fish_user_paths; or set -Ua fish_user_paths $HOME/code/go/bin
contains $HOME/bin $fish_user_paths; or set -Ua fish_user_paths $HOME/bin

# Exported variables
if isatty
    set -x GPG_TTY (tty)
end

# Editor
set -gx EDITOR nvim

#-------------------------------------------------------------------------------
# Functions
#-------------------------------------------------------------------------------
# Shortcut to setup a nix-shell with fish. This lets you do something like
# `fnix -p go` to get an environment with Go but use the fish shell along
# with it.
alias fnix "nix-shell --run fish"
