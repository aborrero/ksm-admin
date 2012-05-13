#!/bin/bash

# Author: Arturo Borrero Gonzalez { aborrero@cica.es || arturo.borrero.glez@gmail.com }
# http://ral-arturo.blogspot.com/
#
# Licensed under GPL license, readable at: http://www.gnu.org/copyleft/gpl.html


### Use:
# ksm-admin {start|stop|status {[-f]|[-s]}|flush|millisecs m|scan p|help}
### Return codes:
# Failure: 1
# Success: 0
# Bad arguments: 3
# ksm-admin status -s (KSM not running): 2
# ksm-admin status -s (KSM running): 0


# KSM related doc:
# http://www.mjmwired.net/kernel/Documentation/vm/ksm.txt
# Also Proxmox and RedHat's virtualization documentation.

################################################################
# Declarations

THIS="/usr/sbin/ksm-admin"
VERSION="0.1-6"

# Change this for using in different OS.
UNAME="/bin/uname"
CAT="/bin/cat"
WATCH="/usr/bin/watch"
BASH="/bin/bash"
GREP="/bin/grep"
AWK="/usr/bin/awk"
FREE="/usr/bin/free"


# Change this if KSM implementation also changes
KSM_PATH="/sys/kernel/mm/ksm"
KSM_RUN="$KSM_PATH/run"
KSM_PAGES_SHARED="$KSM_PATH/pages_shared"
KSM_PAGES_SHARING="$KSM_PATH/pages_sharing"
KSM_PAGES_UNSHARED="$KSM_PATH/pages_unshared"
KSM_FULL_SCANS="$KSM_PATH/full_scans"
KSM_SLEEP="$KSM_PATH/sleep_millisecs"
KSM_MAX_KERNEL_PAGES="$KSM_PATH/max_kernel_pages"
KSM_PAGES_TO_SCAN="$KSM_PATH/pages_to_scan"
KSM_VOLATILE="$KSM_PATH/pages_volatile"

# Color codes
C_RED="\E[31m"
C_YELLOWBOLD="\E[1;33m"
C_NORMAL="\E[0m"
C_BOLD="\E[1m"


################################################################
# Functions
required_bins()
{
	local required_bins_retval=0

	# Test all binary needed by this script. This is because from one OS to other, some PATH may vary.
	[ ! -x $UNAME ] && { required_bins_retval=1 ; echo -e "${C_RED}ERROR${C_NORMAL}: The [${UNAME}] binary has not execution permission or was not found." ; }
	[ ! -x $CAT ] && { required_bins_retval=1 ; echo -e "${C_RED}ERROR${C_NORMAL}: The [${CAT}] binary has not execution permission or was not found." ; }
	[ ! -x $WATCH ] && { required_bins_retval=1 ; echo -e "${C_RED}ERROR${C_NORMAL}: The [${WATCH}] binary has not execution permission or was not found." ; }
	[ ! -x $BASH ] && { required_bins_retval=1 ; echo -e "${C_RED}ERROR${C_NORMAL}: The [${BASH}] binary has not execution permission or was not found." ; }
	[ ! -x $GREP ] && { required_bins_retval=1 ; echo -e "${C_RED}ERROR${C_NORMAL}: The [${GREP}] binary has not execution permission or was not found." ; }
	[ ! -x $AWK ] && { required_bins_retval=1 ; echo -e "${C_RED}ERROR${C_NORMAL}: The [${AWK}] binary has not execution permission or was not found." ; }
	[ ! -x $FREE ] && { required_bins_retval=1 ; echo -e "${C_RED}ERROR${C_NORMAL}: The [${FREE}] binary has not execution permission or was not found." ; }

	return $required_bins_retval
}

files_exist()
{
	local retval=0
	if [ -d $KSM_PATH ] && [ -r $KSM_RUN ] && [ -r $KSM_PAGES_SHARING ] && [ -r $KSM_PAGES_UNSHARED ] && [ -r $KSM_PAGES_UNSHARED ] && [ -r $KSM_FULL_SCANS ] && [ -r $KSM_SLEEP ] && [ -r $KSM_MAX_KERNEL_PAGES ] && [ -r $KSM_PAGES_TO_SCAN ] && [ -r $KSM_VOLATILE ]
	then
		retval=1
	fi
	return $retval
}

has_support()
{
	local retval=0
	$GREP "CONFIG_KSM=y" /boot/config-`$UNAME -r` 2> /dev/null > /dev/null
	if [ $? -eq 0 ]
	then
		retval=1
	fi

	return $retval
}
is_running()
{
	local retval=`$CAT $KSM_RUN`
	return $retval
}
is_ksm_efective()
{
	# As seen in some documentation  Q(-_-Q)
	local retval=0
	if [ "`$CAT $KSM_PAGES_SHARING`" -gt "`$CAT $KSM_PAGES_SHARED`" ] || [ "`$CAT $KSM_PAGES_SHARING`" -eq "`$CAT $KSM_PAGES_SHARED`" ] 2> /dev/null
	then
		# yes, is effective.
		retval=1
	fi
	if [ "`$CAT $KSM_PAGES_UNSHARED`" -gt "`$CAT $KSM_PAGES_SHARING`" ] || [ "`$CAT $KSM_PAGES_UNSHARED`" -eq "`$CAT $KSM_PAGES_SHARING`" ] 2> /dev/null
	then
		# those parameters indicates that is not effective, despite previous check.
		retval=0
	fi
	return $retval
}
ram_usage()
{
	local retval=0
	local total_ram=`$FREE -m | $GREP -i "Mem:" | $AWK -F' ' '{print $2}'`
	local used_ram=`$FREE -m | $GREP -i "Mem:" | $AWK -F' ' '{print $3}'`
	if [ $total_ram -ne 0 ]
	then
		retval=`echo -- | $AWK "{print $used_ram / $total_ram * 100}" | $AWK -F'.' '{print $1}'`
	fi
	return $retval
}
swap_usage()
{
	local retval=0
	local total_swap=`$FREE -m | $GREP -i "Swap:" | $AWK -F' ' '{print $2}'`
	local used_swap=`$FREE -m | $GREP -i "Swap:" | $AWK -F' ' '{print $3}'`
	if [ $total_swap -ne 0 ]
	then
		retval=`echo -- | $AWK "{print $used_swap / $total_swap * 100}" | $AWK -F'.' '{print $1}'`
	fi
	return $retval
}
status()
{
	echo -e "${C_BOLD}--------------------------------------------${C_NORMAL}"
	echo -e "KSM status ${C_BOLD}|${C_NORMAL} `date`"
	echo -e "${C_BOLD}--------------------------------------------${C_NORMAL}"
	echo -n "- Running: "
	is_running
	if [ $? -eq 1 ]
	then
		echo -e "${C_BOLD}yes${C_NORMAL}"
	else
		echo -e "${C_RED}no${C_NORMAL}"
	fi
	echo "- Pages shared: `$CAT $KSM_PAGES_SHARED 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo "- Pages sharing: `$CAT $KSM_PAGES_SHARING 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo "- Pages unshared: `$CAT $KSM_PAGES_UNSHARED 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo "- Full scans: `$CAT $KSM_FULL_SCANS 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo "- Sleep millisecs: `$CAT $KSM_SLEEP 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo "- Max kernel pages: `$CAT $KSM_MAX_KERNEL_PAGES 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo "- Pages to scan: `$CAT $KSM_PAGES_TO_SCAN 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo "- Pages volatile: `$CAT $KSM_VOLATILE 2> /dev/null || echo -e ${C_RED}No data found!${C_NORMAL}`"
	echo -e "${C_BOLD}--------------------------------------------${C_NORMAL}"
	echo "Resume:"
	echo -e "${C_BOLD}--------------------------------------------${C_NORMAL}"
	is_ksm_efective
	if [ $? -eq 1 ]
	then
		echo -n "- KSM seems effective."
		is_running
		if [ $? -eq 1 ]
		then
			echo ""
		else
			echo " But not running."
		fi
	else
		is_running
		if [ $? -eq 1 ]
		then
			echo "- By now it seems that KSM is wasting effort."
		else
			echo "- No data about KSM usefullness. Not running."
		fi
	fi
	ram_usage
	echo "- System RAM usage: ${?}%"
	swap_usage
	echo "- System SWAP usage: ${?}%"
}
stop()
{
	echo 0 > $KSM_RUN
	return 0
}
start()
{
	local retval=1
	echo 1 > $KSM_RUN

	is_running
	if [ $? -eq 1 ]
	then
		retval=0
	fi
	return $retval
}
flush()
{
	echo 2 > $KSM_RUN
	return 0
}
millisecs()
{
	local retval=0

	if [ $1 -ge 0 ] 2> /dev/null
	then
		echo $1 > $KSM_SLEEP
		retval=$?
	else
		echo -e "${C_RED}ERROR${C_NORMAL}: millisecs, invalid value. An integer >= 0 is needed."
		retval=1
	fi

	return $retval
}
scan()
{
	local retval=0

	if [ $1 -ge 0 ] 2> /dev/null
	then
		echo $1 > $KSM_PAGES_TO_SCAN
		retval=$?
	else
		echo -e "${C_RED}ERROR${C_NORMAL}: scan, invalid value. An integer >= 0 is needed."
		retval=1
	fi

	return $retval
}
use()
{
	echo "Usage: ksm-admin {start|stop|status {[-f]|[-s]}|flush|millisecs m|scan p|help}"

}
help()
{
	use
	echo "Version: $VERSION"
	echo "Options description:"
	echo "	start		start KSM by doing \"echo 1 > $KSM_RUN\""
	echo ""
	echo "	stop		stop KSM by doing \"echo 0 > $KSM_RUN\""
	echo "			stop command doesn't clean cached pages."
	echo ""
	echo "	status		show KSM data and info and exit."
	echo ""
	echo "	status -f 	The '-f' option	shows data in continous mode (similar to \`top')"
	echo ""
	echo "	status -s	The '-s' option returns 0 if KSM is running and 2 if not. 1 if error."
	echo "			This option doesn't produce any textual output (for in-script use)"
	echo ""
	echo "	flush		stop KSM by doing \"echo 2 > $KSM_RUN\""
	echo "			flush command remove all cached data!"
	echo ""
	echo "	millisecs m	set to 'm' millisecs the time between scans,"
	echo "			doing \"echo m > $KSM_SLEEP\""
	echo ""
	echo "	scan p		set how many 'p' pages to scan between each"
	echo "			sleep, by doing \"echo p > $KSM_PAGES_TO_SCAN\""
	echo ""
	echo "	help		show this help and exit."
	return 0
}

#############################################################
# Program

required_bins || exit $?

files_exist
if [ $? -eq 0 ]
then
	echo -e "${C_YELLOWBOLD}WARNING${C_NORMAL}: Some KSM file missing at ${C_BOLD}$KSM_PATH${C_NORMAL}."
fi

has_support
if [ $? -eq 0 ]
then
	echo -e "${C_RED}ERROR${C_NORMAL}: This machine has no KSM support."
	exit 1
fi

case "$1" in
	status )
		case "$2" in
			"" )
				status
				exit $?
				;;
			"-f" )
				$WATCH -ct $BASH $THIS status
				exit $?
				;;
			"-s" )
				is_running
				case $? in
					0 )
						exit 2
						;;
					2 )
						exit 2
						;;
					1 )
						exit 0
						;;
				esac
				;;
			* )
				exit 3
				;;
		esac
		;;
	start )
		start
		exit $?
		;;
	stop )
		stop
		exit $?
		;;
	flush )
		flush
		exit $?
		;;
	millisecs )
		millisecs $2
		exit $?
		;;
	scan )
		scan $2
		exit $?
		;;
	help )
		help
		exit $?
		;;
	* )
		use
		exit 3
		;;
esac
exit 3
