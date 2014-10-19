#!/bin/sh
TOP_DIR="$( cd "$( dirname "${0}" )" && cd .. && pwd )"
function do_cleanup_newlib_headers()
{
    local f=$1
    cp "$f" "$f.new.1.tmp"
    unifdef -b -D__STDC__=1 -D__GNUC__=1 -D_HAVE_STDC -U_HAVE_STD_CXX \
         -D__rtems__=1 \
         -U__NeXT__ \
         -U__CYGWIN__ -U__CYGWIN32__ -U__SCLE -U_never \
         -U_REENT_ONLY -U__FreeBSD__ \
         -U__linux__ -U__LARGE64_FILES \
         -U__MSDOS__ -U_WIN32 -UWIN32 -UGO32 -U_WINSOCK_H -U__MS_types__ \
         -U__sysvnecv70_target \
         -m "$f.new.1.tmp"
    sed -i -e 's,\s*_PARAMS\s\+((,<!!!!!!!!!!>_PARAMS((,g'  "$f.new.1.tmp"
    m4 -P "--define=M4_FILE=$f.new.1.tmp" ${TOP_DIR}/c/cleanup_newlib_headers_sub.m4 >"$f.new.2.tmp"
    mv "$f.new.2.tmp" "$f"
    rm -f "$f.new.1.tmp" "$f.new.2.tmp"
}

while test $# -gt 0 ; do
    do_cleanup_newlib_headers "${1}"
    shift
done
