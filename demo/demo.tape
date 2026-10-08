# VHS script for the README GIF: `make gif` (after `make demo-setup`), or the
# e2e job in .github/workflows/ci.yaml, which uploads it as an artifact.
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
# Wait for the bare prompt to come back (demo lines start "$ kubectl", so
# they don't match).
Wait@180s /^\$ ?$/
Sleep 4s
