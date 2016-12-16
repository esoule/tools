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
CREATED_BY_VER=""

ZIP_PROGRAM=${ZIP_PROGRAM:-/usr/bin/zip}
UNZIP_PROGRAM=${UNZIP_PROGRAM:-/usr/bin/unzip}

show_usage()
{
	cat <<__EOF__
Usage: $0 [-v] [-T SECONDS] [-C] -b DIRECTORY...
Repack jar files found in project

Arguments:
  -v                         verbose mode
  -T SECONDS                 set timestamps to to the given number of
                             seconds since January 1, 1970.
  -C                         only replace timestamps if they are later
                             than the time specified to -T SECONDS.
  -b                         do the repacking (required)
  -c STRING                  replace Created-By: header in manifest
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

	while getopts ":vT:Cbc:hV" OPTION ; do
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
		c)
			CREATED_BY_VER="${OPTARG}"
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

resolve_which()
{
	local arg="${1:-}"
	local __prog_which=""

	if [ -z "${arg}" ] ; then
		return 0
	fi

	if [ -x "${arg}" ] ; then
		echo "${arg}"
		return 0
	fi

	__prog_which="$( which "${arg}" | head -n 1 )"
	if [ -x "${__prog_which}" ] ; then
		echo "${__prog_which}"
		return 0
	fi

	echo "${arg}"
	return 0
}

process_jars_in_dirs()
{
	local __opt_nd=""

	ZIP_PROGRAM="$( resolve_which "${ZIP_PROGRAM}" )"
	UNZIP_PROGRAM="$( resolve_which "${UNZIP_PROGRAM}" )"

	if ! [ -x "${ZIP_PROGRAM}" ] ; then
		echo "ERROR: ${PROGNAME}: zip is not installed, we can't repack the jars (path: ${ZIP_PROGRAM})"    >&2
		return 1
	fi
	if ! [ -x "${UNZIP_PROGRAM}" ] ; then
		echo "ERROR: ${PROGNAME}: unzip is not installed, we can't repack the jars (path: ${UNZIP_PROGRAM})"    >&2
		return 1
	fi

	if [ $# -lt 1 ] ; then
		return 0
	fi

	if touch --help | grep no-dereference >/dev/null 2>&1 ; then
		__opt_nd=" -h"
	fi

	local JARS="$( find "$@" -type f -name \*.jar -not -size 0 | LC_ALL=C sort ; )"
	local CURDIR="$( pwd )"

	if [ -z "${JARS}" ] ; then
		return 0
	fi

	local JTOPTMPDIR="$( mktemp -d "${CURDIR}/.tmp.java-repack-jars.XXXXXXXXXX" )" || exit 1

	set +e

	for j in ${JARS} ; do
		${verbose_s_echo} "    JAR-REPACK  ${j}"    >&2

		local JAROWN="$( ls -l ${j} | cut -d' ' -f3 )"
		local JARGRP="$( ls -l ${j} | cut -d' ' -f4 )"
		local JARNAME="$( basename ${j} )"
		local jabs="$( readlink -m "${j}" )"

		local JTMPDIR="$( mktemp -d ${JTOPTMPDIR}/${JARNAME}.tmpdir.XXXXXXXXXX )" || exit 1
		local JTMP2DIR="$( mktemp -d ${JTOPTMPDIR}/${JARNAME}.tmpdir2.XXXXXXXXXX )" || exit 1
		local JARDIR="$( mktemp -d ${JTOPTMPDIR}/${JARNAME}.jardir.XXXXXXXXXX )" || exit 1
		local TIMEREF="$( mktemp ${JTOPTMPDIR}/${JARNAME}.timeref.XXXXXXXXXX )" || exit 1

		touch -c ${__opt_nd} -d "@${TIMESTAMP_EPOCH}" "${TIMEREF}"

		if [ -z "${jabs}" ] ; then
			exit 1
		fi

		cd ${JTMPDIR}

		LC_ALL=C TZ=UTC ${UNZIP_PROGRAM} -qq -o ${jabs}

		find . -type d -exec chmod u=rwx,g=rx,o=rx {} \;
		find . -type f -exec chmod u=rw,g=r,o=r {} \;

		# Create the directories first.
		find -type d | LC_ALL=C sort | while read d; do
			mkdir -p "${JARDIR}/${d}"
		done

		# move the contents over to the a new directory in order and set
		# the times.
		find -type f | LC_ALL=C sort | while read f; do
			cp "${f}" "${JARDIR}/${f}"
			touch -c ${__opt_nd} -d "@${TIMESTAMP_EPOCH}" "${JARDIR}/${f}"
			if [ "${DO_CLAMP_TS}" ] ; then
				if [ "${TIMEREF}" -nt "${f}" ] ; then
					touch -c ${__opt_nd} -r "${f}" "${JARDIR}/${f}"
				fi
			fi
		done

		# Edit Created-By field if asked
		local manif_file="${JARDIR}/META-INF/MANIFEST.MF"
		local manif_orig="${JTMP2DIR}/MANIFEST.MF.orig"

		if [ -r "${manif_file}" ]    \
				&& [ -n "${CREATED_BY_VER}" ] ; then
			cp --archive "${manif_file}" "${manif_orig}"
			sed -e "s|^Created[-]By:.*$|Created-By: ${CREATED_BY_VER}|i;" "${manif_orig}" \
				>"${manif_file}"
			touch -c -r "${manif_orig}" "${manif_file}"
			rm -f "${manif_orig}"
		fi

		cd "${CURDIR}"

		# Set the times of the directories.
		find ${JARDIR} -type d -print0 | xargs -0 touch -c ${__opt_nd} -d "@${TIMESTAMP_EPOCH}"

		# make the jar
		cd ${JARDIR}

		if [ -n "$( find -not -name '.' )" ]; then
			find * -not -name '.' | LC_ALL=C sort | LC_ALL=C TZ=UTC ${ZIP_PROGRAM} -q -X -9 ${jabs}.tmp.new.zip "-@"
		else
			# Put the empty jar back
			touch ${jabs}.tmp.new.zip
		fi
		cd "${CURDIR}"

		chown ${JAROWN} ${jabs}.tmp.new.zip
		chgrp ${JARGRP} ${jabs}.tmp.new.zip

		rm -f ${jabs}
		mv ${jabs}.tmp.new.zip ${jabs}

		# Cleanup.
		rm -rf ${JTMPDIR}
		rm -rf ${JTMP2DIR}
		rm -rf ${JARDIR}
		rm -f ${TIMEREF}

	done

	set -e

	rm -rf "${JTOPTMPDIR}"

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
		echo "ERROR: ${PROGNAME}: please provide -b option to repack files"    >&2
		exit 1
	fi

	shift $(( ${OPTIND} - 1 ))

	umask 0022
	export LANG=C
	export LC_ALL=C

	process_jars_in_dirs "$@"

	return 0
}

java_repack_jars_main "$@"
exit $?
