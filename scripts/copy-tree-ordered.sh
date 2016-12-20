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

SRC_DIR_ORIG=""
SRC_DIR_ABS=""

DST_DIR_ORIG=""
DST_DIR_ABS=""
DST_DIR_PARENT=""
DST_DIR_BNAME=""
TIMEREF=""

OPT_NDEREF=""

show_usage()
{
	set +x
	local arg="${1:-}"

	cat <<__EOF__

Usage: $0 -v [-T SECONDS] -C SOURCE DESTINATION
Copy directory tree, in ordered fashion

Arguments:
  -v                         verbose mode
  -T SECONDS                 set timestamps to to the given number of
                             seconds since January 1, 1970.
  -C                         only replace timestamps if they are later
                             than the time specified in -T SECONDS.
  -h                         this help message
  -V                         version
__EOF__

	if [ "${arg}" != 0 ] ; then
		exit ${arg}
	fi

	true
}

exit_handler()
{
	set +x
	if [ -n "${TIMEREF}" ] ; then
		rm -f "${TIMEREF}"
	fi

	if [ "${1:-}" != 0 ] ; then
		echo "ERROR: ${PROGNAME}: exiting with error"    >&2
	fi
	return 0
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

parse_options()
{
	if [ $# -lt 1 ] ; then
		WANT_USAGE="y"
		return 0
	fi

	local ret_val=0

	while getopts ":vT:ChV" OPTION ; do
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

	if [ ${ret_val} != 0 ] ; then
		return ${ret_val}
	fi

	return 0
}

parse_params()
{
	if [ $# != 2 ] ; then
		echo "ERROR: ${PROGNAME}: wrong number of arguments"    >&2
		return 1
	fi

	SRC_DIR_ORIG="${1}"
	DST_DIR_ORIG="${2}"

	if [ "${SRC_DIR_ORIG}" = . ] || [ "${SRC_DIR_ORIG}" = .. ] ; then
		echo "ERROR: ${PROGNAME}: do not use ${SRC_DIR_ORIG} for source directory"    >&2
		return 1
	fi

	if [ "${DST_DIR_ORIG}" = . ] || [ "${DST_DIR_ORIG}" = .. ] ; then
		echo "ERROR: ${PROGNAME}: do not use ${DST_DIR_ORIG} for destination directory"    >&2
		return 1
	fi

	SRC_DIR_ABS="$( cd "${SRC_DIR_ORIG}" && pwd )"

	DST_DIR_PARENT="$( cd "$( dirname "${DST_DIR_ORIG}" )" && pwd )"
	DST_DIR_BNAME="$( basename "${DST_DIR_ORIG}" )"
	DST_DIR_ABS="${DST_DIR_PARENT}/${DST_DIR_BNAME}"

	if [ -z "${SRC_DIR_ABS}" ] ; then
		echo "ERROR: ${PROGNAME}: could not resolve source directory name"    >&2
		return 1
	fi

	if ! [ -d "${SRC_DIR_ABS}" ] ; then
		echo "ERROR: ${PROGNAME}: source directory does not exist (${SRC_DIR_ABS})"    >&2
		return 1
	fi

	if [ -z "${DST_DIR_PARENT}" ] || [ -z "${DST_DIR_BNAME}" ] ; then
		echo "ERROR: ${PROGNAME}: could not resolve destination directory name"    >&2
		return 1
	fi

	return 0
}

copy_tree_ordered_sub()
{
	if touch --help | grep no-dereference >/dev/null 2>&1 ; then
		OPT_NDEREF=" -h"
	fi

	cd ${SRC_DIR_ABS}

	TIMEREF="$( mktemp /tmp/tmp.copy-tree-ordered.timeref.XXXXXXXXXX )" || exit 1

	touch -c ${OPT_NDEREF} -d "@${TIMESTAMP_EPOCH}" "${TIMEREF}"

	find . -mindepth 1 | LC_ALL=C sort | sed 's|^\./||;' | while read -r fname ; do
		local fparent="$( dirname "${fname}" )"
		local fmode=0644
		local ftype=

		if [ -L "${SRC_DIR_ABS}/${fname}" ] ; then
			ftype=symlink
		else
			if [ -d "${SRC_DIR_ABS}/${fname}" ] ; then
				ftype=dir
			else
				ftype=file
			fi
		fi

		if ! [ -d "${DST_DIR_ABS}/${fparent}" ] ; then
			fmode=0755

			${verbose_s_echo} "    MKDIR[P]    ${fmode}    ${fparent}"    >&2

			mkdir -p "${DST_DIR_ABS}/${fparent}"
			chmod ${fmode} "${DST_DIR_ABS}/${fparent}"
		fi

		if [ $ftype = file ] ; then
			if [ -x "${SRC_DIR_ABS}/${fname}" ] ; then
				fmode=0755
			fi

			${verbose_s_echo} "    COPY        ${fmode}    ${fname}"    >&2

			cp -T -d "${SRC_DIR_ABS}/${fname}" "${DST_DIR_ABS}/${fname}"
			chmod ${fmode} "${DST_DIR_ABS}/${fname}"
			touch -c ${OPT_NDEREF} -d "@${TIMESTAMP_EPOCH}"    \
					"${DST_DIR_ABS}/${fname}"
			if [ "${DO_CLAMP_TS}" ] ; then
				if [ "${TIMEREF}" -nt "${SRC_DIR_ABS}/${fname}" ] ; then
					touch -c ${OPT_NDEREF} -r "${SRC_DIR_ABS}/${fname}"    \
							"${DST_DIR_ABS}/${fname}"
				fi
			fi
		fi

		if [ $ftype = symlink ] ; then
			fmode=0777
			${verbose_s_echo} "    SYMLINK     ${fmode}    ${fname}"    >&2

			cp -T -d "${SRC_DIR_ABS}/${fname}" "${DST_DIR_ABS}/${fname}"
			touch -c ${OPT_NDEREF} -d "@${TIMESTAMP_EPOCH}"    \
					"${DST_DIR_ABS}/${fname}"
		fi

		if [ $ftype = dir ] ; then
			fmode=0755

			${verbose_s_echo} "    MKDIR       ${fmode}    ${fname}"    >&2

			mkdir -p "${DST_DIR_ABS}/${fname}"
			chmod ${fmode} "${DST_DIR_ABS}/${fname}"
		fi
	done

	find ${DST_DIR_ABS} -type d -print0    \
		| xargs -0 --no-run-if-empty touch -c ${OPT_NDEREF} -d "@${TIMESTAMP_EPOCH}"

	return 0
}

copy_tree_ordered_main()
{
	if ! parse_options "$@" ; then
		exit 1
	fi

	if [ -n "${WANT_USAGE}" ] ; then
		show_usage 0
		exit 0
	fi

	if [ -n "${WANT_VERSION}" ] ; then
		echo "${PROGNAME} version ${VERSION}"
		exit 0
	fi

	shift $(( ${OPTIND} - 1 ))

	if ! parse_params "$@" ; then
		show_usage 1    >&2
		exit 1
	fi

	umask 0022
	export LANG=C
	export LC_COLLATE=C
	export LC_NUMERIC=C
	export LC_ALL=C

	copy_tree_ordered_sub
	return $?
}

export TZ=UTC
umask 0022
trap 'exit_handler $?' EXIT
copy_tree_ordered_main "$@"
exit $?

