# ~/.config/fish/config.fish

# start starship prompt
starship init fish | source

# aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias ll='ls -la'

# PATH
fish_add_path ~/.opencode/bin ~/.local/bin

# fzf integration (installed via fisher: jethrokuan/fzf)
if test -f ~/.config/fish/functions/fzf.fish
    source ~/.config/fish/functions/fzf.fish
end
