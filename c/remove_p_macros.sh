#!/bin/sh
TOP_DIR="$( cd "$( dirname "${0}" )" && cd .. && pwd )"
function do_remove_p_macros()
{
    local f=$1
    m4 -P "--define=M4_FILE=$f" ${TOP_DIR}/c/remove_p_macros_sub.m4 >"$f.new.tmp" \
        && mv "$f.new.tmp" "$f"
    rm -f "$f.new.tmp"
}

while test $# -gt 0 ; do
    do_remove_p_macros "${1}"
    shift
done
