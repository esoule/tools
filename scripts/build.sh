#!/sbin/busybox ash
#
# This script builds all or requested components of the project, for
# requested family and variant
#
# when modifying, please test with "/bin/sh" and "/sbin/busybox ash"
#
# set -x
set -u
set -e
: Running "$0" "$@"
# set -o pipefail 2>/dev/null || :
PROGNAME="$(basename "$0")"
PROGINFO="${PROGNAME}"
PROJECT_HOME="$(cd "$(dirname "$0")" && cd .. && pwd)"
THIS_SCRIPT_FULLPATH="${PROJECT_HOME}/scripts/${PROGNAME}"

want_usage=""

family_str=""
variant_str=""
component_str=""

verbose_level=0
# run the component command verbose
if_verbose_1=": skip"
# run the whole script verbose
if_verbose_script=": skip"

# options to pass to subprocesses
opt_verbose_sub=""
opt_logging_sub=""
opt_family_sub=""
opt_variant_sub=""

# exit handler globals
files_to_remove=""

exit_handler()
{
	set +x
	local rv_ex="$1"

	if [ -n "${files_to_remove}" ] ; then
		rm -f ${files_to_remove}
	fi

	echo ""    >&2
	if ! [ ${rv_ex} = 0 ] ; then
		echo "ERROR: ${PROGINFO}: exiting with error"    >&2
	else
		echo "${PROGINFO}: success"    >&2
	fi
	return 0
}

show_usage()
{
	cat <<__EOF__

Usage: $0 [-v] [-l] [-z] -a FAMILY -b VARIANT1,... COMPONENT1 ...
Build all or requested components of the project, for requested family
and variants

Arguments:
  -v                         verbose mode
  -l                         log to file, in addition to standard error
  -z                         delete all untracked files before building
                             each variant (DANGEROUS)
  -a FAMILY                  build for requested family
  -b VARIANT,...             build for requested variant(s)
  -h                         this help message
__EOF__

	true
}

parse_verbose_option()
{
	verbose_level=$(( verbose_level + 1 ))
	opt_verbose_sub="${opt_verbose_sub} -v"

	if_verbose_1=""
	if [ ${verbose_level} -ge 3 ] ; then
		if_verbose_script=""
	fi

	${if_verbose_script} set -x

	return 0
}

parse_logging_option()
{
	opt_logging_sub="${opt_logging_sub} -l"
	return 0
}

parse_one_family_option()
{
	family_str="${1:-}"
	opt_family_sub=""
	if [ -z "${family_str}" ] ; then
		return 1
	fi
	opt_family_sub=" -a ${family_str}"
	return 0
}

parse_one_variant_option()
{
	variant_str="${1:-}"
	opt_variant_sub=""
	if [ -z "${variant_str}" ] ; then
		return 1
	fi
	opt_variant_sub=" -b ${variant_str}"
	return 0
}

get_logfile_path()
{
	echo -n "${PROJECT_HOME}/tmp.logs/${family_str}-${variant_str}-${component_str}.log"
	return 0
}

sub_10_20_parse_args()
{
	## -v -v -l -a family -b variant component
	if [ $# -lt 1 ] ; then
		return 11
	fi
	local ret_val=0

	while getopts "vla:b:" OPTION ; do
		case "${OPTION}" in
		v)
			if ! parse_verbose_option ; then
				ret_val=12
			fi
			;;
		l)
			if ! parse_logging_option ; then
				ret_val=13
			fi
			;;
		a)
			if ! parse_one_family_option "${OPTARG}" ; then
				ret_val=14
			fi
			;;
		b)
			if ! parse_one_variant_option "${OPTARG}" ; then
				ret_val=15
			fi
			;;
		*)
			ret_val=16
			;;
		esac
	done

	if ! [ $ret_val = 0 ] ; then
		return $ret_val
	fi

	shift $(( ${OPTIND} - 1 ))

	component_str="${1:-}"
	if [ -z "${family_str}" ] ; then
		return 17
	fi

	if [ -z "${variant_str}" ] ; then
		return 18
	fi

	if [ -z "${component_str}" ] ; then
		return 19
	fi

	return 0
}

sub_10_process_call_sub_20()
{
	${if_verbose_1} set -x

	${THIS_SCRIPT_FULLPATH} --run sub_20 ${opt_verbose_sub} ${opt_logging_sub} ${opt_family_sub} ${opt_variant_sub} ${component_str}

	return $?
}

sub_10_process()
{
	if ! sub_10_20_parse_args "$@" ; then
		echo "ERROR: ${PROGINFO}: invalid arguments"    >&2
		exit 1
	fi

	${if_verbose_script} set -x

	## tmp_file contains return value of command
	local tmp_file="$( mktemp "/tmp/tmp.build.sh.XXXXXXXXXX" )"
	if [ -z "${tmp_file}" ] ; then
		return 111
	fi
	files_to_remove="${files_to_remove} ${tmp_file}"

	local log_file_path=""
	if [ -n "${opt_logging_sub}" ] ; then
		local log_file_path="$( get_logfile_path )"
		local log_parent_dir="$( dirname "${log_file_path}" )"
		mkdir -p "${log_parent_dir}"
		touch "${log_file_path}"
	fi

	echo -n 112 >"${tmp_file}"
	set +e
	if [ -n "${opt_logging_sub}" ] ; then
		(
			sub_10_process_call_sub_20
			echo -n $? >"${tmp_file}"
		) 2>&1 | tee "${log_file_path}"
	else
		(
			sub_10_process_call_sub_20
			echo -n $? >"${tmp_file}"
		)
	fi
	set -e

	local rv_command="$( cat ${tmp_file} )"

	return $rv_command
}

sub_20_process()
{
	if ! sub_10_20_parse_args "$@" ; then
		echo "ERROR: ${PROGINFO}: invalid arguments"    >&2
		exit 1
	fi

	${if_verbose_1} set -x

	build_sh_family_${family_str}_component_${component_str}

	return $?
}

build_sh_family_AA_component_component1()
{
	true 1
	true 2
	if [ "${DEBUG_FORCE_FAIL:-}" = "AA_${variant_str}_component1" ] ; then
		echo "ERROR: ${PROGINFO}: forcing a failure"    >&2
		local vvvv="FAILED ALREADY"
		false
	fi
	true 3 ${vvvv:-}
	true 4 ${vvvv:-}
	return 0
}

build_sh_family_AA_component_component2()
{
	true 1
	true 2
	if [ "${DEBUG_FORCE_FAIL:-}" = "AA_${variant_str}_component2" ] ; then
		echo "ERROR: ${PROGINFO}: forcing a failure"    >&2
		local vvvv="FAILED ALREADY"
		false
	fi
	true 3 ${vvvv:-}
	true 4 ${vvvv:-}
	return 0
}

build_sh_family_BB_component_component3()
{
	true 1
	true 2
	if [ "${DEBUG_FORCE_FAIL:-}" = "BB_${variant_str}_component3" ] ; then
		echo "ERROR: ${PROGINFO}: forcing a failure"    >&2
		local vvvv="FAILED ALREADY"
		false
	fi
	true 3 ${vvvv:-}
	true 4 ${vvvv:-}
	return 0
}

build_sh_family_BB_component_component4()
{
	true 1
	true 2
	if [ "${DEBUG_FORCE_FAIL:-}" = "BB_${variant_str}_component4" ] ; then
		echo "ERROR: ${PROGINFO}: forcing a failure"    >&2
		local vvvv="FAILED ALREADY"
		false
	fi
	true 3 ${vvvv:-}
	true 4 ${vvvv:-}
	return 0
}

main_process()
{
	true main_process
	return 0
}

# process dispatcher
trap 'exit_handler $?' EXIT

cd "${PROJECT_HOME}"

if [ "${1:-}" = "--run" ] ; then
	case "${2:-}" in
	sub_10)
		PROGINFO="${PROGNAME}:[B]"
		shift 2
		sub_10_process "$@"
		exit $?
		;;
	sub_20)
		PROGINFO="${PROGNAME}:[C]"
		shift 2
		sub_20_process "$@"
		exit $?
		;;
	*)
		exit 1
		;;
	esac
else
	PROGINFO="${PROGNAME}:[A]"
	main_process "$@"
	exit $?
fi
# not reached
exit 1
