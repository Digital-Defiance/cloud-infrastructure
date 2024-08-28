git clone https://github.com/RuiFilipeCampos/nvim.git "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
echo "source /workspaces/cloud-infrastructure/.1password" >> $HOME/.bashrc
echo "eval \$(op signin)" >> $HOME/.bashrc
echo "op run -- gh auth setup-git" >> $HOME/.bashrc

echo "echo 'Running git setup'" >> $HOME/.bashrc

echo "git config --global user.email \$(op read op://digital-defiance-secrets/github/GH_EMAIL)" >> $HOME/.bashrc
echo "git config --global user.name \$(op read op://digital-defiance-secrets/github/GH_NAME)" >> $HOME/.bashrc

nvim --headless "+Lazy! sync" +qa 

