notes=$2
bindkey '^J' self-insert-unmeta
vared -p $'What to Test · Ctrl+J newline, Enter submit and upload, Ctrl+C cancel\n' notes
print -r -- $notes > $1
