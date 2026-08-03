# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt HIST_IGNORE_DUPS
setopt SHARE_HISTORY
setopt AUTO_CD

# Completion
autoload -Uz compinit
compinit

# Aliases
alias ls="eza -la --icons --header --group-directories-first --sort=name"
alias ll="eza -la --icons --header --group-directories-first --sort=name"
alias la="eza -a --icons --header --group-directories-first --sort=name"
alias tree="eza --tree --icons"
alias cat="bat"

# Fastfetch on startup
# fastfetch

eval "$(zoxide init zsh)"

source /usr/share/fzf/key-bindings.zsh
source /usr/share/fzf/completion.zsh


# Starship prompt
eval "$(starship init zsh)"
