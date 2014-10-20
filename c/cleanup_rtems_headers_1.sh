#!/bin/sh
TOP_DIR="$( cd "$( dirname "${0}" )" && cd .. && pwd )"
function do_cleanup_rtems_headers_1()
{
    local f=$1
    rm -f "$f.new.1.tmp" "$f.new.2.tmp"
    cp "$f" "$f.new.1.tmp"
    unifdef -b -Unotdef \
         -m "$f.new.1.tmp"
    sed -i -e 's,\s*_PARAMS\s\+((,<!!!!!!!!!!>_PARAMS((,g'  "$f.new.1.tmp"
    m4 -P "--define=M4_FILE=$f.new.1.tmp" ${TOP_DIR}/c/cleanup_rtems_headers_1_sub.m4 >"$f.new.2.tmp"
    mv "$f.new.2.tmp" "$f"
    rm -f "$f.new.1.tmp" "$f.new.2.tmp"
}

while test $# -gt 0 ; do
    do_cleanup_rtems_headers_1 "${1}"
    shift
done
