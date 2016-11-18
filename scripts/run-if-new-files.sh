#!/sbin/busybox ash

FILES_TO_REMOVE=""

intr_handler()
{
	set -x

	exit 0
}

exit_handler()
{
	set -x

	if [ -n "${FILES_TO_REMOVE}" ] ; then
		rm -f ${FILES_TO_REMOVE}
	fi

	return 0
}

do_main()
{
	local prog="${1:-}"
	local run_count=1
	shift
	## tmp_file is a stamp
	local tmp_file="$( mktemp "/tmp/tmp.run-multuple-builds.sh.XXXXXXXXXX" )"
	if [ -z "${tmp_file}" ] ; then
		return 111
	fi
	FILES_TO_REMOVE="${FILES_TO_REMOVE} ${tmp_file}"
	touch ${tmp_file}
	while true ; do
		echo "${run_count}" >&2
		run_count=$(( run_count + 1))
		sleep 5
		local count_newer="$( find scripts -type f -newer ${tmp_file} | wc -l )"
		if [ ${count_newer} -gt 0 ] ; then
			echo Running ${prog} "$@" >&2
			${prog} "$@"
		fi
		touch ${tmp_file}
	done
	true
}

trap 'intr_handler $?' INT
trap 'exit_handler $?' EXIT
do_main "$@"
true
