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

__nl=$'\n'

WANT_USAGE=""

# for main process
VALID_FAMILIES_LIST=""
VALID_VARIANTS_LIST=""
VALID_COMPONENTS_LIST=""

# for main process
# TODO convert to multi_str using newlines
# TODO add support for all-variants and all-components (must replace existing ones properly)
# TODO must support proper list canonicalization at the end
VARIANTS_MULTI_STR=""
HAVE_ALL_VARIANTS=""
COMPONENTS_MULTI_STR=""
HAVE_ALL_COMPONENTS=""
# for both main process and subprocesses
FAMILY_STR="UNKNOWNFAMILY"
# for subprocesses
VARIANT_STR="UNKNOWNVARIANT"
COMPONENT_STR="UNKNOWNCOMPONENT"

VERBOSE_LEVEL=0
# run the component command verbose
set_x_verbose_1="set +x"
# run the whole script verbose
set_x_verbose_script="set +x"
verbose_s_echo=":"

# options to pass to subprocesses
SUB_OPT_VERBOSE=""
SUB_OPT_LOGGING=""
SUB_OPT_ZAP=""
SUB_OPT_FAMILY=""
SUB_OPT_VARIANT=""

# exit handler globals
FILES_TO_REMOVE=""

exit_handler()
{
	set +x
	local rv_ex="$1"

	if [ -n "${FILES_TO_REMOVE}" ] ; then
		rm -f ${FILES_TO_REMOVE}
	fi

	if ! [ ${rv_ex} = 0 ] ; then
		if [ -z "${WANT_USAGE}" ] ; then
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

sed_filter_one_item()
{
	sed -e 's/\n\+//g; s/\s\+//g;'
}

sed_comma_list_to_space_sep_list()
{
	sed -e 's/,/ /g; s/\n\+/ /g; s/\s\+/ /g; s/^\s\+//; s/\s\+$//;'
}

sed_item_string()
{
	sed -e 's/\s\+//g;'
}

sed_list_string()
{
	sed -e 's/\s\+/ /g; s/^\s\+//; s/\s\+$//;'
}

debug_show_main_parse_result()
{
	cat <<__EOF__
PARSE_RESULT
	FAMILY_STR='${FAMILY_STR}'
	HAVE_ALL_VARIANTS='${HAVE_ALL_VARIANTS}'
	VARIANTS_MULTI_STR='${VARIANTS_MULTI_STR}'
	HAVE_ALL_COMPONENTS='${HAVE_ALL_COMPONENTS}'
	COMPONENTS_MULTI_STR='${COMPONENTS_MULTI_STR}'
	VERBOSE_LEVEL='${VERBOSE_LEVEL}'
	SUB_OPT_VERBOSE='${SUB_OPT_VERBOSE}'
	SUB_OPT_LOGGING='${SUB_OPT_LOGGING}'
	SUB_OPT_ZAP='${SUB_OPT_ZAP}'
	SUB_OPT_FAMILY='${SUB_OPT_FAMILY}'

__EOF__
	true
}

parse_verbose_option()
{
	VERBOSE_LEVEL=$(( VERBOSE_LEVEL + 1 ))
	SUB_OPT_VERBOSE="${SUB_OPT_VERBOSE} -v"

	set_x_verbose_1="set -x"
	if [ ${VERBOSE_LEVEL} -ge 3 ] ; then
		set_x_verbose_script="set -x"
		verbose_s_echo="echo"
	fi

	${set_x_verbose_script}

	return 0
}

parse_logging_option()
{
	SUB_OPT_LOGGING="${SUB_OPT_LOGGING} -l"
	return 0
}

parse_zap_option()
{
	SUB_OPT_ZAP="${SUB_OPT_ZAP} -z"
	return 0
}

parse_one_family_option()
{
	local additem="$( echo -n "${1:-}" | sed_filter_one_item )"

	if [ -z "${additem}" ] ; then
		return 1
	fi

	FAMILY_STR="${additem}"
	SUB_OPT_FAMILY=" -a ${FAMILY_STR}"

	return 0
}

parse_multiple_variants_option()
{
	local addlist="$( echo -n "${1:-}" | sed_comma_list_to_space_sep_list )"

	for additem in ${addlist} ; do
		if [ -z "${additem}" ] ; then
			continue
		fi
		if [ "${additem}" = "all-variants" ] ; then
			HAVE_ALL_VARIANTS="y"
		else
			VARIANTS_MULTI_STR="${VARIANTS_MULTI_STR}${additem}${__nl}"
		fi
	done

	return 0
}

parse_components_params()
{
	local have_empty_item=""

	while [ $# -gt 0 ] ; do
		local additem="$( echo -n "${1:-}" | sed_filter_one_item )"
		shift 1
		if [ -z "${additem}" ] ; then
			echo "ERROR: ${PROGINFO}: invalid component '${additem}'"    >&2
			have_empty_item="y"
			continue
		fi
		if [ "${additem}" = "all-components" ] ; then
			HAVE_ALL_COMPONENTS="y"
		else
			COMPONENTS_MULTI_STR="${COMPONENTS_MULTI_STR}${additem}${__nl}"
		fi
	done

	if [ -n "${have_empty_item}" ] ; then
		return 1
	fi

	return 0
}

get_logfile_path()
{
	echo -n "${PROJECT_HOME}/tmp.logs/${FAMILY_STR}-${VARIANT_STR}-${COMPONENT_STR}.log"
	return 0
}

main_parse_args()
{
	## -v -v -v -l -z -a family -b variant1,variant2,... component1 component2 component3
	if [ $# -lt 1 ] ; then
		WANT_USAGE="y"
		return 0
	fi

	local ret_val=0

	while getopts ":vlza:b:h" OPTION ; do
		case "${OPTION}" in
		v)
			if ! parse_verbose_option ; then
				echo "ERROR: ${PROGINFO}: invalid option -v"    >&2
				ret_val=71
			fi
			;;
		l)
			if ! parse_logging_option ; then
				echo "ERROR: ${PROGINFO}: invalid option -l"    >&2
				ret_val=72
			fi
			;;
		z)
			if ! parse_zap_option ; then
				echo "ERROR: ${PROGINFO}: invalid option -z"    >&2
				ret_val=73
			fi
			;;
		a)
			if ! parse_one_family_option "${OPTARG}" ; then
				echo "ERROR: ${PROGINFO}: invalid family option -a '${OPTARG}'"    >&2
				ret_val=74
			fi
			;;
		b)
			if ! parse_multiple_variants_option "${OPTARG}" ; then
				echo "ERROR: ${PROGINFO}: invalid variant option -b '${OPTARG}'"    >&2
				ret_val=75
			fi
			;;
		h)
			WANT_USAGE="y"
			;;
		*)
			echo "ERROR: ${PROGINFO}: illegal option -${OPTARG}"    >&2
			ret_val=79
			;;
		esac
	done

	shift $(( ${OPTIND} - 1 ))

	if ! parse_components_params "$@" ; then
		ret_val=78
	fi

	if [ -n "${WANT_USAGE}" ] ; then
		return 0
	fi

	if ! [ $ret_val = 0 ] ; then
		return $ret_val
	fi

	return 0
}

main_parse_env()
{
	local additem=
	local ret_val=0

	if [ "${FAMILY_STR}" = "UNKNOWNFAMILY" ] ; then
		additem="$( echo -n "${FAMILY:-}" | sed_filter_one_item )"
		if [ -n "${additem}" ] ; then
			if ! parse_one_family_option "${additem}" ; then
				echo "ERROR: ${PROGINFO}: invalid FAMILY='${FAMILY:-}' value"    >&2
				ret_val=74
			fi
		fi
	fi

	if [ -z "${VARIANTS_MULTI_STR}" ] ; then
		additem="$( echo -n "${VARIANT:-}" | sed_filter_one_item )"
		if [ -n "${additem}" ] ; then
			VARIANTS_MULTI_STR="${VARIANTS_MULTI_STR}${additem}${__nl}"
		fi
	fi

	debug_show_main_parse_result    >&2

	if ! [ $ret_val = 0 ] ; then
		return $ret_val
	fi

	return 0
}

main_parse_args___000()
{
	## -v -v -v -l -z -a family -b variant1,variant2,... component1 component2 component3
	if [ $# -lt 1 ] ; then
		WANT_USAGE="y"
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
			WANT_USAGE="y"
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

	if [ -n "${WANT_USAGE}" ] ; then
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
	if [ -z "${FAMILY_STR}" ] && [ -n "${FAMILY:-}" ] ; then
		FAMILY_STR="${FAMILY}"
	fi

	if [ -z "${VARIANTS_LIST}" ] && [ -n "${VARIANT:-}" ] ; then
		VARIANT="$( echo -n "${VARIANT}" | sed -e 's/\s\+//g;' )"
		VARIANTS_LIST="${VARIANT}"
	fi

	# Remove leading and trailing spaces
	FAMILY_STR="$( echo -n "${FAMILY_STR}" | sed_item_string )"
	VARIANTS_LIST="$( echo -n "${VARIANTS_LIST}" | sed_list_string )"
	COMPONENTS_LIST="$( echo -n "${COMPONENTS_LIST}" | sed_list_string )"

	if [ -z "${VARIANTS_LIST}" ] ; then
		echo "ERROR: ${PROGINFO}: no variants to build requested"    >&2
		return 23
	fi

	if [ -z "${COMPONENTS_LIST}" ] ; then
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

main_args_are_valid_00000()
{
	local not_in_list=""

	if [ -z "${FAMILY_STR}" ] ; then
		echo "ERROR: ${PROGINFO}: family option not specified"    >&2
		return 1
	fi

	if ! item_is_in_list "${FAMILY_STR}" "${VALID_FAMILIES_LIST}" ; then
		echo "ERROR: ${PROGINFO}: family ${FAMILY_STR} is not in list (${VALID_FAMILIES_LIST})"    >&2
		return 1
	fi

	VALID_VARIANTS_LIST="$( get_valid_variants_list_for_family_${FAMILY_STR} | sed_list_string )"
	VALID_COMPONENTS_LIST="$( get_valid_components_list_for_family_${FAMILY_STR} | sed_list_string )"

	not_in_list=""
	for variant in ${VARIANTS_LIST} ; do
		if ! item_is_in_list "${variant}" "${VALID_VARIANTS_LIST}" ; then
			echo "ERROR: ${PROGINFO}: variant ${variant} is not in variants list"    >&2
			not_in_list="y"
		fi
	done

	for component in ${COMPONENTS_LIST} ; do
		if ! item_is_in_list "${component}" "${VALID_COMPONENTS_LIST}" ; then
			echo "ERROR: ${PROGINFO}: component ${component} is not in components list"    >&2
			not_in_list="y"
		fi
	done

	if [ -n "${not_in_list}" ] ; then
		echo "INFO: ${PROGINFO}: valid variant list is ${VALID_VARIANTS_LIST}"    >&2
		echo "INFO: ${PROGINFO}: valid component list is ${VALID_COMPONENTS_LIST}"    >&2
		return 1
	fi

	## component list must be ordered like ${VALID_COMPONENTS_LIST}
	local new_comp_list=""
	for component in ${VALID_COMPONENTS_LIST} ; do
		if item_is_in_list "${component}" "${COMPONENTS_LIST}" ; then
			new_comp_list="${new_comp_list} ${component}"
		fi
	done
	COMPONENTS_LIST="$( echo -n "${new_comp_list}" | sed_list_string )"
	echo "INFO: ${PROGINFO}: component list is ${COMPONENTS_LIST}"    >&2

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

	COMPONENT_STR="${1:-}"
	if [ -z "${FAMILY_STR}" ] ; then
		return 37
	fi

	if [ -z "${VARIANT_STR}" ] ; then
		return 38
	fi

	if [ -z "${COMPONENT_STR}" ] ; then
		return 39
	fi

	return 0
}

sub_10_process_call_sub_20()
{
	${set_x_verbose_1}

	${THIS_SCRIPT_FULLPATH} --run sub_20 ${SUB_OPT_VERBOSE} ${SUB_OPT_LOGGING} \
		${SUB_OPT_FAMILY} ${SUB_OPT_VARIANT} ${COMPONENT_STR}

	return $?
}

sub_10_process()
{
	if ! sub_10_20_parse_args "$@" ; then
		exit 1
	fi

	${set_x_verbose_script}

	unset FAMILY
	unset VARIANT

	## tmp_file contains return value of command
	local tmp_file="$( mktemp "/tmp/tmp.build.sh.XXXXXXXXXX" )"
	if [ -z "${tmp_file}" ] ; then
		return 111
	fi
	FILES_TO_REMOVE="${FILES_TO_REMOVE} ${tmp_file}"

	local log_file_path=""
	if [ -n "${SUB_OPT_LOGGING}" ] ; then
		local log_file_path="$( get_logfile_path )"
		local log_parent_dir="$( dirname "${log_file_path}" )"
		mkdir -p "${log_parent_dir}"
		touch "${log_file_path}"
	fi

	echo -n 112 >"${tmp_file}"
	set +e
	if [ -n "${SUB_OPT_LOGGING}" ] ; then
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

	${set_x_verbose_1}

	unset FAMILY
	unset VARIANT

	echo "${PROGINFO}: build_sh_family_${FAMILY_STR}_component_${COMPONENT_STR} VARIANT ${VARIANT_STR}"    >&2
	build_sh_family_${FAMILY_STR}_component_${COMPONENT_STR}

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
	if [ "${DEBUG_FORCE_FAIL:-}" = "AA_${VARIANT_STR}_component1" ] ; then
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
	if [ "${DEBUG_FORCE_FAIL:-}" = "AA_${VARIANT_STR}_component2" ] ; then
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
	if [ "${DEBUG_FORCE_FAIL:-}" = "BB_${VARIANT_STR}_component3" ] ; then
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
	if [ "${DEBUG_FORCE_FAIL:-}" = "BB_${VARIANT_STR}_component4" ] ; then
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
	VALID_FAMILIES_LIST="$( get_valid_families_list )"

	if ! main_parse_args "$@" ; then
		exit 1
	fi

	if ! main_parse_env "$@" ; then
		exit 1
	fi

# 	if ! main_args_are_valid ; then
# 		exit 1
# 	fi

	unset FAMILY
	unset VARIANT

	if [ -n "${WANT_USAGE}" ] ; then
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
