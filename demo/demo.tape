# VHS script for the README GIF: `make gif` (after `make demo-setup`).
# https://github.com/charmbracelet/vhs
Output docs/demo.gif

Set Shell "bash"
Set FontSize 15
Set Width 1280
Set Height 760
Set Padding 16
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms

Hide
Type "export DEMO_PAUSE=1.2 PS1='$ ' && clear"
Enter
Show

Type "./demo/demo.sh"
Sleep 500ms
Enter
Wait+Screen@180s /All checks passed|check\(s\) failed/
Sleep 4s
