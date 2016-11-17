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

newline=$'\n'

want_usage=""

# for main process
valid_families_list=""
valid_variants_list=""
valid_components_list=""

# for main process
# TODO convert to multi_str using newlines
# TODO add support for all-variants and all-components (must replace existing ones properly)
# TODO must support proper list canonicalization at the end
variants_list=""
components_list=""
# for both main process and subprocesses
family_str=""
# for subprocesses
variant_str=""
component_str=""

verbose_level=0
# run the component command verbose
if_verbose_1=": skip"
# run the whole script verbose
if_verbose_script=": skip"
verbose_s_echo=":"

# options to pass to subprocesses
opt_verbose_sub=""
opt_logging_sub=""
opt_zap_sub=""
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

	if ! [ ${rv_ex} = 0 ] ; then
		if [ -z "${want_usage}" ] ; then
			echo ""    >&2
			echo "ERROR: ${PROGINFO}: exiting with error"    >&2
		fi
	else
		${verbose_s_echo} ""    >&2
		${verbose_s_echo} "${PROGINFO}: success"    >&2
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

sed_item_string()
{
	sed -e 's/\s\+//g;'
}

sed_list_string()
{
	sed -e 's/\s\+/ /g; s/^\s\+//; s/\s\+$//;'
}

parse_verbose_option()
{
	verbose_level=$(( verbose_level + 1 ))
	opt_verbose_sub="${opt_verbose_sub} -v"

	if_verbose_1=""
	if [ ${verbose_level} -ge 3 ] ; then
		if_verbose_script=""
		verbose_s_echo="echo"
	fi

	${if_verbose_script} set -x

	return 0
}

parse_logging_option()
{
	opt_logging_sub="${opt_logging_sub} -l"
	return 0
}

parse_zap_option()
{
	opt_zap_sub="${opt_zap_sub} -z"
	return 0
}

parse_one_family_option()
{
	family_str="$( echo -n "${1:-}" | sed_item_string )"
	opt_family_sub=""
	if [ -z "${family_str}" ] ; then
		return 1
	fi
	opt_family_sub=" -a ${family_str}"
	return 0
}

parse_multiple_variants_option()
{
	local addlist="$( echo -n "${1:-}" | sed -e 's/,/ /g;' | sed_list_string )"

	if [ -z "${addlist}" ] ; then
		return 1
	fi

	variants_list="${variants_list} ${addlist}"

	return 0
}

parse_one_variant_option()
{
	variant_str="$( echo -n "${1:-}" | sed_item_string )"

	opt_variant_sub=""

	if [ -z "${variant_str}" ] ; then
		return 1
	fi

	opt_variant_sub=" -b ${variant_str}"

	return 0
}

parse_one_of_many_components()
{
	local additem="$( echo -n "${1:-}" | sed_item_string )"

	if [ -z "${additem}" ] ; then
		return 1
	fi

	components_list="${components_list} ${additem}"

	return 0
}

get_logfile_path()
{
	echo -n "${PROJECT_HOME}/tmp.logs/${family_str}-${variant_str}-${component_str}.log"
	return 0
}

main_parse_args()
{
	## -v -v -v -l -z -a family -b variant1,variant2,... component1 component2 component3
	if [ $# -lt 1 ] ; then
		want_usage="Y"
		return 0
	fi
	local ret_val=0

	while getopts ":vlza:b:h" OPTION ; do
		case "${OPTION}" in
		v)
			if ! parse_verbose_option ; then
				echo "ERROR: ${PROGINFO}: invalid option -v"    >&2
				ret_val=12
			fi
			;;
		l)
			if ! parse_logging_option ; then
				echo "ERROR: ${PROGINFO}: invalid option -l"    >&2
				ret_val=13
			fi
			;;
		z)
			if ! parse_zap_option ; then
				echo "ERROR: ${PROGINFO}: invalid option -z"    >&2
				ret_val=14
			fi
			;;
		a)
			if ! parse_one_family_option "${OPTARG}" ; then
				echo "ERROR: ${PROGINFO}: invalid family option -a ${OPTARG}"    >&2
				ret_val=15
			fi
			;;
		b)
			if ! parse_multiple_variants_option "${OPTARG}" ; then
				echo "ERROR: ${PROGINFO}: invalid variant option -b ${OPTARG}"    >&2
				ret_val=16
			fi
			;;
		h)
			want_usage="Y"
			;;
		*)
			echo "ERROR: ${PROGINFO}: illegal option -${OPTARG}"    >&2
			ret_val=17
			;;
		esac
	done

	if ! [ $ret_val = 0 ] ; then
		return $ret_val
	fi

	if [ -n "${want_usage}" ] ; then
		return 0
	fi

	shift $(( ${OPTIND} - 1 ))

	if [ $# -lt 1 ] ; then
		echo "ERROR: ${PROGINFO}: no components to build requested"    >&2
		return 21
	fi

	while [ $# -gt 0 ] ; do
		if ! parse_one_of_many_components "${1:-}" ; then
			echo "ERROR: ${PROGINFO}: illegal component ${1:-}"    >&2
			ret_val=22
		fi
		shift 1
	done

	if ! [ $ret_val = 0 ] ; then
		return $ret_val
	fi

	## read the environment, if necessary
	if [ -z "${family_str}" ] && [ -n "${FAMILY:-}" ] ; then
		family_str="${FAMILY}"
	fi

	if [ -z "${variants_list}" ] && [ -n "${VARIANT:-}" ] ; then
		variants_list="${VARIANT}"
	fi

	# Remove leading and trailing spaces
	family_str="$( echo -n "${family_str}" | sed_item_string )"
	variants_list="$( echo -n "${variants_list}" | sed_list_string )"
	components_list="$( echo -n "${components_list}" | sed_list_string )"

	if [ -z "${variants_list}" ] ; then
		echo "ERROR: ${PROGINFO}: no variants to build requested"    >&2
		return 23
	fi

	if [ -z "${components_list}" ] ; then
		echo "ERROR: ${PROGINFO}: no components to build requested"    >&2
		return 24
	fi

	return 0
}

item_is_in_list()
{
	local item="${1:-}"
	local list="${2:-}"

	if [ -z "${item}" ] || [ -z "${list}" ] ; then
		return 1
	fi

	if ! { echo -n " ${list} " | grep -F -o " ${item} " >/dev/null ; } ; then
		return 1
	fi

	return 0
}

main_args_are_valid()
{
	local not_in_list=""

	if [ -z "${family_str}" ] ; then
		echo "ERROR: ${PROGINFO}: family option not specified"    >&2
		return 1
	fi

	if ! item_is_in_list "${family_str}" "${valid_families_list}" ; then
		echo "ERROR: ${PROGINFO}: family ${family_str} is not in list (${valid_families_list})"    >&2
		return 1
	fi

	valid_variants_list="$( get_valid_variants_list_for_family_${family_str} | sed_list_string )"
	valid_components_list="$( get_valid_components_list_for_family_${family_str} | sed_list_string )"

	not_in_list=""
	for variant in ${variants_list} ; do
		if ! item_is_in_list "${variant}" "${valid_variants_list}" ; then
			echo "ERROR: ${PROGINFO}: variant ${variant} is not in variants list"    >&2
			not_in_list="Y"
		fi
	done

	for component in ${components_list} ; do
		if ! item_is_in_list "${component}" "${valid_components_list}" ; then
			echo "ERROR: ${PROGINFO}: component ${component} is not in components list"    >&2
			not_in_list="Y"
		fi
	done

	if [ -n "${not_in_list}" ] ; then
		echo "INFO: ${PROGINFO}: valid variant list is ${valid_variants_list}"    >&2
		echo "INFO: ${PROGINFO}: valid component list is ${valid_components_list}"    >&2
		return 1
	fi

	## component list must be ordered like ${valid_components_list}
	local new_comp_list=""
	for component in ${valid_components_list} ; do
		if item_is_in_list "${component}" "${components_list}" ; then
			new_comp_list="${new_comp_list} ${component}"
		fi
	done
	components_list="$( echo -n "${new_comp_list}" | sed_list_string )"
	echo "INFO: ${PROGINFO}: component list is ${components_list}"    >&2

	return 0
}

sub_10_20_parse_args()
{
	## -v -v -v -l -a family -b variant component
	if [ $# -lt 1 ] ; then
		return 31
	fi
	local ret_val=0

	while getopts "vla:b:" OPTION ; do
		case "${OPTION}" in
		v)
			if ! parse_verbose_option ; then
				ret_val=32
			fi
			;;
		l)
			if ! parse_logging_option ; then
				ret_val=33
			fi
			;;
		a)
			if ! parse_one_family_option "${OPTARG}" ; then
				ret_val=34
			fi
			;;
		b)
			if ! parse_one_variant_option "${OPTARG}" ; then
				ret_val=35
			fi
			;;
		*)
			ret_val=36
			;;
		esac
	done

	if ! [ $ret_val = 0 ] ; then
		return $ret_val
	fi

	shift $(( ${OPTIND} - 1 ))

	component_str="${1:-}"
	if [ -z "${family_str}" ] ; then
		return 37
	fi

	if [ -z "${variant_str}" ] ; then
		return 38
	fi

	if [ -z "${component_str}" ] ; then
		return 39
	fi

	return 0
}

sub_10_process_call_sub_20()
{
	${if_verbose_1} set -x

	${THIS_SCRIPT_FULLPATH} --run sub_20 ${opt_verbose_sub} ${opt_logging_sub} \
		${opt_family_sub} ${opt_variant_sub} ${component_str}

	return $?
}

sub_10_process()
{
	if ! sub_10_20_parse_args "$@" ; then
		exit 1
	fi

	${if_verbose_script} set -x

	unset FAMILY
	unset VARIANT

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

	unset FAMILY
	unset VARIANT

	echo "${PROGINFO}: build_sh_family_${family_str}_component_${component_str} VARIANT ${variant_str}"    >&2
	build_sh_family_${family_str}_component_${component_str}

	return $?
}

get_valid_families_list()
{
	echo -n "FAA FBB FCC"
	return 0
}

get_valid_variants_list_for_family_FAA()
{
	echo -n "VMM VNN VOO"
	return 0
}

get_valid_variants_list_for_family_FBB()
{
	echo -n "VPP VQQ VRR"
	return 0
}

get_valid_variants_list_for_family_FCC()
{
	echo -n "VSS VTT VUU"
	return 0
}

get_valid_components_list_for_family_FAA()
{
	echo -n "component11 component12 component13 component14 component15"
	return 0
}

get_valid_components_list_for_family_FBB()
{
	echo -n "component21 component22 component23 component24 component25"
	return 0
}

get_valid_components_list_for_family_FCC()
{
	echo -n "component31 component32 component33 component34 component35"
	return 0
}

build_sh_family_FAA_component_component11()
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

build_sh_family_FAA_component_component12()
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

build_sh_family_FBB_component_component21()
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

build_sh_family_FBB_component_component22()
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
	valid_families_list="$( get_valid_families_list )"

	if ! main_parse_args "$@" ; then
		exit 1
	fi

	if ! main_args_are_valid ; then
		exit 1
	fi

	unset FAMILY
	unset VARIANT

	if [ -n "${want_usage}" ] ; then
		show_usage    >&2
		exit 1
	fi

	echo "ERROR: ${PROGINFO}: SCRIPT INCOMPLETE. FORCING FAILURE."    >&2

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
