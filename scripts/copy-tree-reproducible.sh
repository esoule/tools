#!/bin/sh
# set -x
set -u
# set -e
PROGNAME="$(basename "$0")"
VERSION="1.0"
PROJECT_HOME="$(cd "$(dirname "$0")" && cd .. && pwd)"

WANT_USAGE=""
WANT_VERSION=""
verbose_s_echo=":"
## Default timestamp is 2001-09-17 00:00:00 UTC
TIMESTAMP_EPOCH="1000684800"
DO_CLAMP_TS=""
DO_REPACK=""

show_usage()
{
	cat <<__EOF__
Usage: $0 [-v] [-T SECONDS] [-C] -b SOURCEDIR TARGETDIR
Copy SOURCEDIR to TARGETDIR and reset timestamps

Arguments:
  -v                         verbose mode
  -T SECONDS                 set timestamps to to the given number of
                             seconds since January 1, 1970.
  -C                         only replace timestamps if they are later
                             than the time specified to -T SECONDS.
  -b                         do the copying (required)
  -h                         this help message
  -V                         version
__EOF__

	true
}

parse_timestamp_option()
{
	local ts="$( LC_ALL=C LANG=C TZ=UTC date -u -d "@${1:-}" "+%s" 2>/dev/null || true ; )"

	if [ -z "${ts}" ] ; then
		return 1
	fi

	TIMESTAMP_EPOCH="${ts}"

	return 0
}

parse_args()
{
	if [ $# -lt 1 ] ; then
		WANT_USAGE="y"
		return 0
	fi

	local ret_val=0

	while getopts ":vT:CbhV" OPTION ; do
		case "${OPTION}" in
		v)
			verbose_s_echo="echo"
			;;
		T)
			if ! parse_timestamp_option "${OPTARG}" ; then
				echo "ERROR: ${PROGNAME}: invalid option -T ${OPTARG}"    >&2
				ret_val=73
			fi
			;;
		C)
			DO_CLAMP_TS="y"
			;;
		b)
			DO_REPACK="y"
			;;
		h)
			WANT_USAGE="y"
			;;
		V)
			WANT_VERSION="y"
			;;
		*)
			echo "ERROR: ${PROGNAME}: illegal option -${OPTARG}"    >&2
			ret_val=79
			;;
		esac
	done

	if ! [ ${ret_val} = 0 ] ; then
		return ${ret_val}
	fi

	return 0
}

process_copy_dir()
{
	local __opt_nd=""

	if [ $# -lt 2 ] ; then
		return 0
	fi

	if touch --help | grep no-dereference >/dev/null 2>&1 ; then
		__opt_nd=" -h"
	fi

	local src_dir="$( readlink -m "${1}")"
	local dst_dir="$( readlink -m "${2}")"

	local CURDIR="$( pwd )"

	local TIMEREF="$( mktemp ${CURDIR}/tmp.timeref.XXXXXXXXXX )" || exit 1
	local TARFILE="$( mktemp ${CURDIR}/tmp.tarfile.XXXXXXXXXX )" || exit 1

	touch -c -h -d "@${TIMESTAMP_EPOCH}" "${TIMEREF}"

	${verbose_s_echo} "    COPY-TREE  ${1} -> ${2}"    >&2

	set +e

	mkdir -p "${dst_dir}"

	cd ${src_dir}
	find . -print0 | LC_ALL=C sort -z | \
		tar --null -T - --no-recursion --numeric-owner --owner=0 --group=0 -cf ${TARFILE}

	cd ${dst_dir}
	tar -xf ${TARFILE}

	cd ${src_dir}
	find ! -type d | LC_ALL=C sort | while read f; do
		${verbose_s_echo} "    TOUCH  ${f}"    >&2
		touch ${__opt_nd} -c -d "@${TIMESTAMP_EPOCH}" "${dst_dir}/${f}"
		if [ "${DO_CLAMP_TS}" ] ; then
			if [ "${TIMEREF}" -nt "${f}" ] ; then
				touch ${__opt_nd} -c -r "${f}" "${dst_dir}/${f}"
			fi
		fi
	done

	find -type d | LC_ALL=C sort | while read f; do
		${verbose_s_echo} "    TOUCH  ${f}"    >&2
		touch ${__opt_nd} -c -d "@${TIMESTAMP_EPOCH}" "${dst_dir}/${f}"
		if [ "${DO_CLAMP_TS}" ] ; then
			if [ "${TIMEREF}" -nt "${f}" ] ; then
				touch ${__opt_nd} -c -r "${f}" "${dst_dir}/${f}"
			fi
		fi
	done

	set -e

	cd "${CURDIR}"

	rm -f ${TIMEREF} ${TARFILE}

	return 0
}

java_repack_jars_main()
{
	export TZ=UTC

	if ! parse_args "$@" ; then
		exit 1
	fi

	if [ -n "${WANT_USAGE}" ] ; then
		show_usage    >&2
		exit 1
	fi

	if [ -n "${WANT_VERSION}" ] ; then
		echo "${PROGNAME} version ${VERSION}"
		exit 0
	fi

	if [ -z "${DO_REPACK}" ] ; then
		echo "ERROR: ${PROGNAME}: please provide -b option to copy tree"    >&2
		exit 1
	fi

	shift $(( ${OPTIND} - 1 ))

	if ! [ -d "${1:-}" ] || [ -z "${2:-}" ] ; then
		echo "ERROR: ${PROGNAME}: must specify copy source or target"    >&2
		exit 1
	fi

	umask 0022
	export LANG=C
	export LC_ALL=C

	process_copy_dir "${1}" "${2}"

	return 0
}

java_repack_jars_main "$@"
exit $?
