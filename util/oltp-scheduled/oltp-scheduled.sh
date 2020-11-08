#!/bin/bash

function pause(){
   read -p "$*"
}
#.............................................

sho() {
  local msg=$1
  local log=$2
  local dts=$(date +'%d.%m.%y %H:%M:%S')
  echo $dts. $msg
  echo $dts. $msg>>$log
}
#.............................................

show_syntax() {
  clear
  local this_abend_name=$1
  rm -f this_abend_name
cat <<-EOF >$this_abend_name
Syntax:

$0  <FB_major_version>  <sessions_count>  <server_mode>  [ <update_FB_instance> ]

where:
    <FB_major_version> = 25 or 30 or 40 - version of Firebird without dot: 2.5, 3.0, 4.0;
    <sessions_count> = number of ISQL sessions to launch
    <server_mode> = CS | SC | SS  -  required mode, case-insensitive
    <update_FB_instance> = should we upgrade FB instance before test ? Default: 1.
        If 1 then every run of this script will check new FB snapshot on official site
        and replace existing instance if need (with apropriate .debug package).
        If 0 then existing FB instance will not be replaced.
        NOTE: value of ServerMode in firebird.conf is always changed with required value.

Example:

    $0  30  100  ss

        * run test on FB 3.0,
        * launch 100 ISQL sessions,
        * check Server mode 'Super',
        * upgrade existing FB instance (default for <update_FB_instance>)
EOF
cat $this_abend_name
}
#.............................................


msg_nocfg() {
  echo
  echo Config file \'$1\' either not found or is empty.
  echo
  echo Script is now terminated.
  exit 1
}
#.............................................

display_intention() {
    local msg=$1
    local run_cmd=$2
    local std_log=$3
    local std_err=${4:-"UNDEFINED"}
    echo
    sho "$msg" $log4all
cat <<- EOF
	RUNCMD: $run_cmd
	STDOUT: $std_log
	STDERR: $std_err
EOF
cat <<- EOF ->>$log4all
	RUNCMD: $run_cmd
	STDOUT: $std_log
	STDERR: $std_err
EOF
}

#.............................................

catch_err() {
  local tmperr=$1
  local addnfo=${2:-""}
  local quit_if_error=${3:-1}
  if [ -s $tmperr ];then
    echo
    sho "Error log $tmperr is NOT EMPTY." $log4all
    echo ...............................
    cat $tmperr | sed -e 's/^/    /'
    cat $tmperr | sed -e 's/^/    /' >>$log4all
    echo ...............................
    if [ ! -z "$addnfo" ]; then
        echo
        echo Additional info / advice:
        echo $addnfo
        echo $addnfo >>$log4all
        echo
    fi

    if [ $quit_if_error -eq 1 ]; then
        sho "Script is terminated." $log4all
        exit 1
    fi
  else
        sho "Result: SUCCESS." $log4all
  fi
}
#.............................................

msg_novar() {
  local cfgfile=$1
  local undefvar=$2
  echo
  echo -e "##########################################################"
  echo -e At least one variable: ${undefvar} - is NOT defined.
  echo Check config file $cfgfile
  echo -e "##########################################################"
  echo
  echo Script is now terminated.
}
#.............................................

msg_nofile() {
  local cfgfile=$1
  echo
  echo At least one of Firebird command line utilities NOT FOUND in the folder
  echo -e defined by variable \'fbc\' = \>\>\>$fbc\<\<\<
  echo
  echo This folder must have following executable files: $clu, fbsvcmgr
  echo
  echo Verify value of parameter \'fbc\' in the file \'$cfgfile\'!
  echo Script is now terminated.
}
#.............................................

msg_noserv() {
  local cfgfile=$1
  echo
  echo -e Could NOT define server version on host=\>$host\<,   port=\>$port\<
  echo Result of trying to do that via fbsvcmgr:
  echo -----------------------------------------
  cat $tmperr
  echo -----------------------------------------
  echo
  echo 1. Ensure that Firebird is running on specified host.
  echo 2. Check settings in $cfgfile: host, port, user and password.
  echo
  echo Script is now terminated.
  exit 1
}
#.............................................

msg_no_build_result() {
  echo
  echo Could NOT define result of previous building of test database.
  echo Script $1 finished with ERRORS:
  echo -----------------------------------------
  cat $2
  echo -----------------------------------------
  echo
  echo Script is now terminated.
  exit 1
}
#.............................................

#  grep process by name. This was taken from FB install.sh
grepProcess() {
    processList=$1
    eol=\$
    ps $psOptions | egrep "\<($processList)($eol|[[:space:]])" | grep -v grep | grep -v -w '\-path'
}
#.............................................

upd_sysdba_pswd() {
    local new_password=$1 # ${pwd}
    local sql=$2
    local tmp=$3
    local err=$4
    local log=$5

    local fb_snapshot_version # LI-V3.0.6.33289 etc
    local fb_installed_stamp

    fb_snapshot_version=$(echo "quit;" | $fbc/isql -q -z | awk '{print $3}')
    fb_installed_stamp=$(date +'%d.%m.%Y %H:%M:%S')

    sho "Attempt to add/update SYSDBA user." $log

    rm -f $sql
	cat <<- EOF >$sql
	    set list on;
	    set count on;
	    set bail on;
	    set echo on;
	    create or alter user sysdba password '${new_password}' firstname '$fb_snapshot_version' lastname '$fb_installed_stamp' using plugin Srp;
	    commit;
	    select sec\$user_name,sec\$first_name,sec\$last_name,sec\$admin,sec\$plugin from sec\$users;
	EOF

    set -x
    $fbc/isql security.db -user sysdba -i $sql 1>$tmp 2>$err
    set +x
    rm -f $sql

    cat $tmp
    cat $tmp>>$log
    if [[ -s $err ]]; then
        cat $err
        cat $err >>$log
        sho "ACHTUNG. Attempt to add/update SYSDBA user failed. Job terminated." $log
        exit
    else
        sho "Success." $log
    fi
    rm -f $tmp $err

}
#.............................................

check_for_sleep_UDF() {
    local dir_to_install_fb=$1
    local fb_cfg_for_work=$2
    local tmp=$3
    local log=$4

    local run_cmd

    # Check whether oltp-emul config parameter 'sleep_ddl' points to 'default' UDF that is provided with test.
    # If yes then we have to make dir 'UDF' in FB_HOME and unpack there ./util/udf64/SleepUDF.so.tar.gz
    if grep -i -q "UdfAccess" $fb_cfg_for_work ; then
        if [[ "${sleep_ddl}" == "./oltp_sleepUDF_nix.sql" ]]; then
            sho "Test requires UDF for make delays." $log
            # NB: firebird.conf already *contains* line UdfAccess = Restrict UDF - see creating of $fb_cfg_for_work at the start of main part.
            if grep -i -E -q "entry_point[[:space:]]+'SleepUDF'[[:space:]]+module_name[[:space:]]+'SleepUDF'" ${OLTP_HOME_DIR}/$sleep_ddl ; then
                sho "Extracting UDF binary provided with test package. Current dir: ${PWD}, file to extract: ${COMPRESSED_OLTP_UDF}" $log
                [[ -d "$dir_to_install_fb/UDF" ]] || mkdir $dir_to_install_fb/UDF
                run_cmd="tar xvf ${COMPRESSED_OLTP_UDF} -C $dir_to_install_fb/UDF"
                sho "Command: $run_cmd" $log
                eval $run_cmd 1>$tmp 2>&1
                if [[ $? -eq 0 ]]; then
                    sho "Success. Size of extracted binary $dir_to_install_fb/UDF/SleepUDF.so: $(stat -c%s $dir_to_install_fb/UDF/SleepUDF.so)" $log
                    rm -f $tmp
                else
                    sho "ACHTUNG. UDF binary could not be extracted. Job terminated." $log
                    cat $tmp
                    cat $tmp >>$log
                    rm -f $tmp
                    exit
                fi
            else
                sho "Config of OLTP-EMUL test contains script thats point to 3rd-party UDF" $log
            fi
            chown firebird:root -R $dir_to_install_fb/UDF
            sho "Completed preparing steps for UDF usage. Check UDF folder:" $log
            ls -l $dir_to_install_fb/UDF
            ls -l $dir_to_install_fb/UDF >>$log
        else
            if [[ -z "${sleep_ddl}" ]]; then
                sho "Test does not require UDF usage, skip from extracting UDF binary." $log
            else
                sho "Test requires UDF usage but config '$oltp_emul_conf_name' points to 3-rd party DDL." $log
                sho "It is impossible to execute test in such case on scheduled basis. Job terminated." $log
                exit
            fi
        fi
    fi
}
# end of check_for_sleep_UDF
#.............................................

cleanup_dir() {
    local dir_to_clean=$1
    local files_pattern=$2 # "oltp-scheduled.*.log"
    local max_files_to_keep=$3 # $MAX_LOG_FILES
    local log=$4
    local lst=$5
    local err=$6
    local run_cmd
    local del_cnt=0

    run_cmd="find ${dir_to_clean}/${files_pattern} -maxdepth 1 -type f -printf \"%f\n\" | sort -r | tail --lines=+$(( MAX_LOG_FILES+1 ))"

    sho "Cleanup folder $dir_to_clean: remove all files with pattern $files_pattern until their number become $max_files_to_keep" $log
    echo Command: "${run_cmd}"
    echo Command: "${run_cmd}" >>$log
    eval "${run_cmd}" 1>$lst 2>$err
    if [[ -s "$err" ]]; then
        sho "FAILED: could not find any file with pattern ${dir_to_clean}/${files_pattern} for removing." $log
        cat $err
        cat $err>>$log
        rm -f $err
    else
        while read line; do
            sho "Removing file ${dir_to_clean}/$line" $log
            rm -f ${dir_to_clean}/$line
            del_cnt=$((del_cnt+1))
        done < <(grep . $lst)
        sho "Completed. Total removed files: $del_cnt" $log
    fi
    rm -f $lst $err
}
# end of cleanup_dir
#.............................................

###############################
###   M A I N     P A R T   ###
###############################

this_script_directory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# this file must be allowed to create on any POSIX:
abendlog=/var/tmp/oltp-scheduled.abend.txt
rm -f $abendlog

cd ${this_script_directory}

this_script_full_name=${BASH_SOURCE[0]}
this_script_name_only=$(basename $this_script_full_name)
this_script_name_only=${this_script_name_only%.*}
this_script_conf_name=$this_script_directory/${this_script_name_only}_config.nix
#this_script_abend_txt=$this_script_directory/$this_script_name_only.abend.err

rm -f $abendlog
if [ $EUID -ne 0 ];  then
    echo You have to run this script as ROOT user.>$abendlog
    cat $abendlog
    exit 1
fi


# This script requires first 3 arguments be specified:
[ -z $3 ] && show_syntax $abendlog && exit 1

cat <<-EOF >$abendlog
	Intro $0:
	    arg1 [major FB version] = $1
	    arg2 [number of launched sessions] = $2
	    arg3 [server mode] = $3
	    arg4 [should FB be updated ? Default: 1] = $4
	Current dir: $(pwd)
EOF

fb=$1
winq=$2

if [[ "$fb" = "25" ]]; then
    preferred_fb_mode="cs"
else
    preferred_fb_mode=${3:-"ss"}
fi

fb_config_prototype=$this_script_directory/${this_script_name_only}-fb${fb}.conf.${preferred_fb_mode^^}

if [[ "${preferred_fb_mode^^}" == "SS" || "${preferred_fb_mode^^}" == "SC" || "${preferred_fb_mode^^}" == "CS" ]] ; then
    if grep -q -m1 -i "FileSystemCacheThreshold" $fb_config_prototype ; then
        # Prototype for firebird.conf FOUND and contains parameter 'FileSystemCacheThreshold'
        :
    else
	cat <<-EOF >>$abendlog
		Prototype for firebird.conf: $fb_config_prototype - either does not exist or has no parameter 'FileSystemCacheThreshold'
		Job terminated.
	EOF
	cat $abendlog
        exit 1
    fi
else
	cat <<-EOF >>$abendlog
		Value of arg_3 [server mode] is invalid: ${preferred_fb_mode^^}
		Must be SS, SC or CS (case-insensitive). Job terminated.
	EOF
    cat $abendlog
    exit 1
fi


########################################
### DO WE UPDATE FIREBIRD INSTANCE ? ###
########################################
update_fb_instance=${4:-1}

if [[ "$update_fb_instance" == "0" || "$update_fb_instance" == "1" ]]; then
    :
else
	cat <<-EOF >$abendlog
	Value of arg_4 [update_fb_instance] is invalid: $update_fb_instance.
	Must be 1 (default) or 0.
	Job terminated.
	EOF
    cat $abendlog
    exit 1
fi

#------------------------------------------------------------------------------

# from FB install.sh, need for grepProcess():
# -e : select all processes. Identical to -A
# -f : does full-format listing
# -a : select all processes except both session leaders (see getsid(2)) and processes not associated with a terminal. 
# -w : Wide output. Use this option twice for unlimited width. 
psOptions=-efaww
export psOptions

export shname=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/`basename "${BASH_SOURCE[0]}"`
export shdir=$(cd "$(dirname "$0")" && pwd)

echo Parsing config file ${this_script_conf_name}>>$abendlog
shopt -s extglob

############################
# READ OLTP-SCHEDULED CONFIG
############################
while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        # | sed -e 's/^[ \t]*//'
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")

	# NOTE we have to use eval <cmd> if parameter value contain spaces.
	# Otherwise right part of declaration will be enclosed into single quotes, like this:
	# declare 'PROXY_DATA="--proxy' 'http://172.16.210.203:8080"'
	# - and this will raise bash eror:
	# declare: `http://172.16.210.203:8080"': not a valid identifier
        decl_cmd="declare ${lhs}=$rhs"
        eval $decl_cmd
        if [ $? -gt 0 ]; then
            echo "lhs=.${lhs}. ; rhs=.${rhs}."
            echo +++ ACHTUNG +++ SOMETHING WRONG IN CONFIG FILE '$oltp_emul_conf_name'>>$abendlog
            cat $abendlog
            exit
        fi
        # echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")>>$abendlog
    fi
done < <(awk '$1=$1' $this_script_conf_name | grep "^[^#]")



#export oltp_emul_conf_name=$this_script_directory/oltp$fb"_config.nix"
export oltp_emul_conf_name=${OLTP_HOME_DIR}/oltp${fb}_config.nix

if [[ -s $oltp_emul_conf_name ]]; then
    :
else
    echo "Config file '$oltp_emul_conf_name' does not exists or empty.">>$abendlog
    cat $abendlog
    exit
fi
echo Parsing config file ${oltp_emul_conf_name}>>$abendlog

#######################
# READ OLTP-EMUL CONFIG
#######################
while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        # | sed -e 's/^[ \t]*//'
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
        # echo "lhs=.${lhs}. ; rhs=.${rhs}."
        declare $lhs=$rhs
        if [ $? -gt 0 ]; then
            echo +++ ACHTUNG +++ SOMETHING WRONG IN CONFIG FILE '$oltp_emul_conf_name'>>$abendlog
            cat $abendlog
            exit
        fi
        # echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")>>$abendlog
    fi
done < <(awk '$1=$1' $oltp_emul_conf_name  | grep "^[^#]")


if [[ -z "${tmpdir}" ]]; then
    echo Could not properly parse OLTP-EMUL config $oltp_emul_conf_name. Problem with parameter tmpdir.>>$abendlog
    exit 1
fi

mkdir -p $tmpdir && touch $tmpdir/tmp.tmp && rm $tmpdir/tmp.tmp
if [ $? -eq 0 ]; then
    echo "Successfully created / accessed tmpdir=$tmpdir"
else
    msg="Could NOT create / access tmpdir=$tmpdir"
    echo $msg
    echo $msg > $abendlog
    exit 1
fi

dts=$(date +'%Y%m%d_%H%M%S')
log=$tmpdir/${this_script_name_only}.${dts}.log
tmp=$tmpdir/$this_script_name_only.tmp
err=$tmpdir/$this_script_name_only.err
lst=$tmpdir/$this_script_name_only.lst
sql=$tmpdir/$this_script_name_only.sql

if [ "$clu" != "" ]; then
    # Name of ISQL on Ubuntu/Debian when FB is installed from OS repository
    # 'isql-fb' etc:
    echo Config contains custom name of command-line utility for interact with Firebird.>>$abendlog
    echo Parameter: \'clu\', value: \|$clu\|>>$abendlog
else
    echo Using standard name of command-line utility for interact with Firebird: 'isql'>>$abendlog
    clu=isql
fi
isql_name=$fbc/$clu
cat $abendlog
cat $abendlog>$log
rm -f $abendlog

if [[ $update_fb_instance -eq 1 ]]; then
    command -v curl 1>>$abendlog 2>&1
    if [[ $? -ne 0 ]]; then
        msg="Package 'curl' was not installed on this host. You have to install it first."
        echo $msg
        echo $msg>>$abendlog
        exit 1
    fi
fi
rm -f $abendlog

# || { echo "Command '$curl' not found. Install its package first."; exit 1; }

sho "Config files parsing completed." $log


##########################################
###  c l e a n u p    t e m p   d i r  ###
##########################################
cleanup_dir $tmpdir "${this_script_name_only}.*.log" $MAX_LOG_FILES $log $lst $err
if [[ $MAX_RPT_FILES -gt 0 ]]; then
    cleanup_dir $tmpdir "*_score_*.txt" $MAX_RPT_FILES $log $lst $err
    cleanup_dir $tmpdir "*_score_*.htm*" $MAX_RPT_FILES $log $lst $err
fi
cleanup_dir $tmpdir "*.tar.gz" $MAX_ZIP_FILES $log $lst $err

#------------------------------------------------------------
if [[ $update_fb_instance -eq 1 ]]; then

  # <update_fb_instance> is command-line parameter N4, default: 1
  ######################################
  
  if [[ "$fb" = "25" ]]; then
    sho "FB of this version does not requires any 3rd-party packages." $log
  else
    #################################################################################################
    ### c h e c k    f o r     l i b t o m a t h    &   l i b t o m c r y p t     p a c k a g e s ###
    #################################################################################################
    cat /etc/*release* | grep -m1 -i "^id=" > $tmp
    required_packages_list="libtommath libtomcrypt"
    if grep -q -i "debian" $tmp ; then
        # needed by gsec, gstat etc:
        required_packages_list="${required_packages_list} libncurses5"
    fi
    required_packages_array=(${required_packages_list})
    for checked_package in "${required_packages_array[@]}"; do

      retcode=0
      sho "Check whether package '$checked_package' is installed. THIS MAY TAKE A LONG TIME, WAIT!" $log
      if grep -q -i "centos" $tmp ; then
          yum list installed | grep -i $checked_package 1>$lst
          retcode=$?
      elif grep -q -i "ubuntu" $tmp ; then
          apt list --installed 2>&1 | grep -i $checked_package 1>$lst
          retcode=$?
      elif grep -q -i "debian" $tmp ; then
          apt list --installed 2>&1 | grep -i $checked_package 1>$lst
          retcode=$?
      else
          sho "ERROR: CAN NOT DETECT OS." $log
          exit
      fi

      if [[ $retcode -ne 0 ]]; then
          sho "ABEND. Package '$checked_package' not found on your system. Install it first." $log
          if grep -q -i "cenos" $tmp ; then
              sho "Try command: yum -y install $checked_package" $log
          elif grep -q -i "ubuntu" $tmp ; then
              sho "Try command: apt-get --assume-yes install ${checked_package}-dev" $log
          fi
          exit
      else
          sho "Completed, result: package found." $log
      fi
    done
    rm -f $tmp $lst
  fi
else
  sho "Input argument 'update_fb_instance' is 0. Skip check for presence of packages required to install FB." $log
fi
# update_fb_instance -eq 1
#----------------------------------------------------------------

svc_script_startup_dir=$SYSDIR_CENTOS
[ -d $svc_script_startup_dir ] || svc_script_startup_dir=$SYSDIR_UBUNTU

if [[ ! -d $svc_script_startup_dir ]]; then
	cat <<- EOF >$tmp
		Can not find directory for storing sripts for starting services.
		None of this exists: $SYSDIR_CENTOS, $SYSDIR_UBUNTU
		OS loader name: $(ps -q 1 -o comm=)
		Job terminated.
	EOF
	cat $tmp
	cat $tmp>>$log
	rm -f $tmp
	exit
fi
#grep -m1 "/opt/fb30test/bin/fbguard.*-daemon.*-forever" firebird*.service | grep -v "@"
#------------------------------------------------------------------------------

if [[ "${preferred_fb_mode^^}" == "SS" || "${preferred_fb_mode^^}" == "SC" || "${preferred_fb_mode^^}" == "CS" ]] ; then
    if grep -q -m1 -i "FileSystemCacheThreshold" $fb_config_prototype ; then
        sho "Prototype for firebird.conf FOUND and contains parameter 'FileSystemCacheThreshold'." $log
    else
        sho "Prototype for firebird.conf: $fb_config_prototype - either does not exist or has no parameter 'FileSystemCacheThreshold'" $log
        sho "Job terminated." $log
        exit
    fi
else
    sho "Invalid server mode specified: $preferred_fb_mode" $log
    sho "Job terminated." $log
    exit
fi

# Check that value of $etalon_dbnm is defined.
# Get attributes of its header: whether it is in shutdown or readonly mode.
etalon_shutdown=0
etalon_readonly=0
if [ -z ${etalon_dbnm+x} ]; then
  sho "This scenario requires parameter 'etalon_dbnm' to be DEFINED in $oltp_emul_conf_name and point to existing .fdb file" $log
  exit 1
fi

#unset ISC_USER
#unset ISC_PASSWORD
# Take from oltp-emul config data for ISC* variables:
#####################
export ISC_USER=$usr
export ISC_PASSWORD=$pwd


if [[ -f "$etalon_dbnm"  ]]; then
      if [[ -f "$fbc/gstat" ]]; then
          $fbc/gstat -h $etalon_dbnm 1>$tmp 2>&1
          if [[ $? -ne 0 ]]; then
              sho "Can not get DB header for 'etalon_dbnm' = $etalon_dbnm" $log
              cat $tmp
              cat $tmp>>$log
              exit 1
          fi
          if grep -q -i "attributes[[:space:]].*read[[:space:]]only" $tmp; then
              etalon_readonly=1
              sho "Etalone database: $etalon_dbnm - has read_only mode." $log
          fi

          if grep -q -i "attributes[[:space:]].*shutdown" $tmp; then
              etalon_shutdown=1
              sho "Etalone database: $etalon_dbnm - has shutdown state." $log
          fi
          if [[ $etalon_shutdown -eq 0 && $etalon_readonly -eq 0 ]]; then
              sho "Etalone database: $etalon_dbnm - has normal state and read_write mode." $log
          fi
      else
          sho "Could not find $fbc/gstat utility. Check parameter 'fbc' in OLTP-EMUL config!" $log
          exit 1
      fi
else
      sho "Parameter 'etalon_dbnm' points to non-existing file: '$etalon_dbnm'" $log
      exit 1
fi


#------------------------------------------------------------------------------
if [[ "$fb" = "25" ]]; then
    # NB: folder '/opt/fb25cs' is hardcoded in install.sh for FB 2.5
    # Firebird will be installed as Classic.
    # There is NO WAY to change its mode to SuperClassic non-interactively:
    # command switch '-silent' does not prevent from asking question about
    # preferred mode when launch script changeMultiConnectMode.sh
    dir_to_install_fb=/opt/fb25cs
    if [[ $update_fb_instance -eq 1 ]]; then
        if [[ "$(dirname "$fbc")" != "$dir_to_install_fb" ]]; then
            sho "Destination folder for installing Firebird 2.5 instance is hardcoded: '$dir_to_install_fb'" $log
            sho "You have to change 'fbc' parameter in $oltp_emul_conf_name to: $dir_to_install_fb" $log
            exit
        fi
    fi
else
    # get parent dir for  '/opt/fb30/bin' or '/opt/fb40/bin' --> '/opt/fb30'; '/opt/fb40'
    dir_to_install_fb="$(dirname "$fbc")"
fi

#------------------------------------------------------------------------------
fb_config_can_be_used=0
if [[ -f "$fb_config_prototype" ]]; then
    awk '$1=$1' $fb_config_prototype  | grep "^[^#]" | grep -i "FileSystemCacheThreshold" >$tmp
    if [[ $? -eq 0 ]]; then
        fb_config_can_be_used=1
    else
	cat <<-EOF >$tmp

		Config file '$fb_config_prototype' can NOT be used now for test.
		Value of parameter 'FileSystemCacheThreshold' must be uncommented
		Its value must be greater then page cache size used for test DB.
		Job terminated.

	EOF
	cat $tmp
	cat $tmp >>$log
    fi
else
	cat <<-EOF >$tmp

		File for replacement of firebird.conf: '$fb_config_prototype' - does not exist.
		Job terminated.

	EOF
	cat $tmp
	cat $tmp >>$log
fi
rm -f $tmp

if [[ $fb_config_can_be_used -ne 1 ]]; then
    exit
fi

sho "Start parsing prototype of firebird.conf and change its RemoteServicePort and BugCheckAbort parameters." $log

# Now we have to read $fb_config_prototype and change there 'port' to the value that is specified in oltp-emul cfg
fb_cfg_for_work=$tmpdir/fb_config.conf
rm -f $fb_cfg_for_work

cat <<- EOF >>$fb_cfg_for_work
	# Updated by $this_script_full_name $(date +'%d.%m.%Y %H:%M:%S')
	# Prototype for this config: $fb_config_prototype.
EOF

adjusted_port_value=0
found_udf_param=0
while read line; do
    if [[ "${line^^}" == UDFACCESS* ]]; then
        if [[ -z "${sleep_ddl}" ]]; then
            :
        else
            echo $line >>$fb_cfg_for_work
        fi
        found_udf_param=1
    elif [[ "$line" != RemoteServicePort* &&  "$line" != BugCheckAbort*  ]]; then
        echo $line >>$fb_cfg_for_work
    fi
done < <(awk '$1=$1' $fb_config_prototype | grep "^[^#]")

if [[ -s "${sleep_ddl}" && found_udf_param -eq 0 ]]; then
	cat <<-EOF >>$fb_cfg_for_work
		# Added because current settings of OLTP-EMUL require 'sleep-UDF' for delays.
		# Details see in $oltp_emul_conf_name, parameter: 'sleep_ddl'
		UdfAccess = Restrict UDF
	EOF
fi

# We have to explicitly assign this value in that case.
# /var/tmp/logs.oltp40/fb_config.conf
cat <<- EOF >>$fb_cfg_for_work

	# RemoteServicePort is adjusted to the value of parameter 'port'
	# from oltp-emul config file '$oltp_emul_conf_name':
	RemoteServicePort=$port

	# BugCheckAbort must be set always to 1 in order to stop test
	# when both crash and expected internal FB error occurs.
	BugCheckAbort=1
EOF

sho "Completed. FB config file has value RemoteServicePort from $oltp_emul_conf_name. BugCheckAbort=1 was added without conditions." $log

#------------------------------------------------------------

command -v gdb 1>$tmp 2>&1
if [[ $? -eq 0 ]]; then
  if [[ -f "$dbnm" ]]; then
    sho "Check whether $dbnm is opened now by any of FB-related processes. Make stack trace in this case." $log
    rm -f $lst
    # Example: find /proc/25686/fd/5
    # Can raise here: find: ‘/proc/25686/fd/5’: No such file or directory
    find /proc -regex '\/proc\/[0-9]+\/fd\/.*' -type l -lname "$dbnm" 1>$tmp 2>$err
    if [[ -s "$tmp" ]]; then
        grep . $tmp | awk -F'/' '{print $3}' > $lst
    fi
    # Result: $lst contains list of PIDs of processes which keep DB file open.
    # (find /proc -regex '\/proc\/[0-9]+\/fd\/.*' -type l -lname "$dbnm" 2>&1) | grep -v "find" | awk -F'/' '{print $3}' 1>$lst 2>&1
    rm -f $tmp $err

    if [[ -s "$lst" ]]; then
        sho "File $dbnm is opened by at least one process:" $log
        echo "(find /proc -regex '\/proc\/[0-9]+\/fd\/.*' -type l -lname \"$dbnm\" 2>&1) | grep -v \"find\" | awk -F'/' '{print \$3}'"
        cat $lst
        cat $lst>>$log

        # Count NOT EMPTY lines with PIDs.
        # This can be greater then 1 if DB is opened by FB Classic processes:
        processes_to_handle=$(cat $lst | sed '/^\s*$/d' | wc -l)
        got_lock_print=0
        gdb_commands=$tmpdir/gdb_commands.$this_script_name_only.txt

        while read pid_line; do
            binary_file_name=$(cat /proc/$pid_line/comm)
            echo "$FB_BIN_PATTERN" | grep -q -E "\|$binary_file_name\|" > /dev/null
            if [[ $? -eq 0 ]]; then
                sho "Process with PID=$pid_line has name '$binary_file_name' and present in FB-related list. We have to make stack-trace for it." $log
                binary_full_name=$(readlink /proc/$pid_line/exe)
                # Most of all $dbnm is opened by firebird | fb_inet_server | fb_smp_server or other FB-related process.
                # Before we try to make stack-trace for it, one need to ensure that there are .debug-files in following
                # sub-directories of folder that is parent for FB-process: ./bin; ./lib and ./plugins
                # /opt/fb30/bin/firebird --> /opt/firebird
                binary_parent_dir="$(dirname $(dirname "$binary_full_name"))"
                sho "Check for equality: binary_parent_dir=$binary_parent_dir; dir_to_install_fb=$dir_to_install_fb" $log
                if [[ "$binary_parent_dir" == "$dir_to_install_fb" ]]; then
                    ls -A $dir_to_install_fb/*/.debug/* 1>$tmp 2>/dev/null
                    if [[ -s "$tmp" ]]; then
                        sho "Found debug package under $dir_to_install_fb. Can try to make stack-trace" $log
                        rm -f $gdb_commands
                        if [[ $got_lock_print -eq 0 ]]; then
                            # Name of file to store result of fb_lock_print:
                            # lock_print.oltp40-etalone.fdb.20200429_205346.txt
                            lock_p_txt=$tmpdir/lock_print.${dbnm##*/}.$(date +'%Y%m%d_%H%M%S').txt
                            if [[ $processes_to_handle -gt 1 ]]; then
                                # Classic: we HAVE to use '-c' otherwise some cal to fb_lock_print can produce infinite loop
                                # which leads to output of infinite size!
                                echo "shell $fbc/fb_lock_print -a -c -d $dbnm 1>$lock_p_txt 2>&1;" >>$gdb_commands
                            else
                                # SS/SC: do NOT use '-c', it can lead to hang of fb_lock_print:
                                echo "shell $fbc/fb_lock_print -a -d $dbnm 1>$lock_p_txt 2>&1;" >>$gdb_commands
                            fi
                            got_lock_print=1
                        fi
			cat <<-EOF >>$gdb_commands
				thread apply all bt
				quit
				yes
			EOF
			stack_trace_txt=$tmpdir/gdb.${binary_file_name}.pid_${pid_line}.$(date +'%Y%m%d_%H%M%S').txt
			run_cmd="gdb -q -x $gdb_commands $binary_full_name $pid_line"
			sho "Generating stack trace for $binary_full_name, command:" $log
			echo $run_cmd
			echo $run_cmd>>$log

			sho "Content of gdb command scenario '$gdb_commands':" $log
			cat $gdb_commands
			cat $gdb_commands>>$log

			eval $run_cmd 1>$stack_trace_txt 2>&1
			sho "Completed. Size of stack-trace: $(stat -c%s $stack_trace_txt). Process $pid_line now can be killed." $log
			rm -f $gdb_commands

			if grep -q -i -m1 "CRC[[:space:]]mism" $stack_trace_txt; then
			    sho "ACHTUNG. Stack-trace is INVALID: found message about CRC mismatch." $log
			    grep -i -m1 "crc[[:space:]]mism" $stack_trace_txt >$tmp
			    cat $tmp
			    cat $tmp >>$log
			elif  grep -i -m1 "Missing separate debuginfo for[[:space:]]$dir_to_install_fb" $stack_trace_txt; then
			    sho "ACHTUNG. Stack-trace can be not readable. At least one file from FB debug package missed." $log
			    grep -i -m1 "Missing separate debuginfo for[[:space:]]$dir_to_install_fb" $stack_trace_txt >$tmp
			    cat $tmp
			    cat $tmp >>$log
			else
			    if grep -q -m1 " at .*.h:[[:digit:]]\| at .*.cpp:[[:digit:]]" $stack_trace_txt; then
			        sho "Stack-trace looks VALID." $log
			    else
			        sho "Stack-trace looks valid but there is no lines related to source code references: .cpp or .h" $log
			    fi
			fi
			run_cmd="tar -czvf ${stack_trace_txt%.*}.tar.gz --directory $(dirname $stack_trace_txt) ${stack_trace_txt##*/}"
			sho "Compress stack-trace. Command: $run_cmd" $log
			eval $run_cmd 1>$tmp 2>&1
			if [[ $? -eq 0 ]]; then
			    rm -f $stack_trace_txt
			    sho "Success. Size of compressed file: $(stat -c%s ${stack_trace_txt%.*}.tar.gz)" $log
			else
			    sho "ACHTUNG. Failed to compress stack-trace." $log
			    cat $tmp
			    cat $tmp>>$log
			    rm -f ${stack_trace_txt%.*}.tar.gz
			fi
			
			if [[ got_lock_print -eq 1 && -f $lock_p_txt ]]; then
			    run_cmd="tar -czvf ${lock_p_txt%.*}.tar.gz --directory $(dirname $lock_p_txt) ${lock_p_txt##*/}"
			    sho "Compress output of $fbc/fb_lock_print -a -d $dbnm. Command: $run_cmd" $log
			    eval $run_cmd 1>$tmp 2>&1
			    sho "Completed. Size of compressed file: $(stat -c%s ${lock_p_txt%.*}.tar.gz)" $log
			    rm -f $lock_p_txt
			fi
			rm -f $tmp
                    fi
                    # ls -A $dir_to_install_fb/*/.debug/* --> .debug package *exists*
                fi
                # if [[ "$binary_parent_dir" == "$dir_to_install_fb" ]]
            else
	        sho "SKIP gdb launch. DB file is opened by process '${binary_file_name}'" $log
	        sho "This name does not belong to this list: ${FB_BIN_PATTERN}" $log
            fi
            # DB file is opened by FB-related process (rather than some other utilities).
        done < <(cat $lst)
        rm -f $lst
    else
        sho "Database file $dbnm is NOT opened now and can be replaced." $log
    fi
    # end of processing non-empty list of PIDs which keep $dbnm file opened
  fi
  # end of -f "$dbnm"
fi
# gdb package presents here

#-------------------------------------------------------------------

#############################################################
ps aux | grep fbguard | grep -v grep > $tmp
ps aux | grep "firebird\|fb_smp_server\|fb_inet_server\|fbserver\|fbsvcmgr\|fbtracemgr\|gbak\|gstat\|isql\|gsec" | grep -v "grep\|fbguard" >> $tmp
# firebird 18127  0.0  0.0  29652  1052 ?        S    09:11   0:00 /opt/fb30/bin/fbguard -pidfile
# firebird 18147  0.0  0.0  29260  1080 ?        S    09:11   0:00 /opt/fb40/bin/fbguard -pidfile
# firebird 18128  0.0  0.0 319848  3780 ?        Sl   09:11   0:00 /opt/fb30/bin/firebird
# firebird 18148  0.0  0.0 327200  5352 ?        Sl   09:11   0:00 /opt/fb40/bin/firebird
# root     24475  0.0  0.0 134352  2884 pts/1    S+   09:25   0:00 /opt/firebird/bin/isql
cat $tmp
cat $tmp >> $log
while read line; do
    sho "Detect FB-related process $line, kill it." $log
    kill -9 $line
done < <(cat $tmp | awk '{print $2}')
#############################################################


previous_fb_snapshot=0
actual_fb_snapshot=0
debug_package_tar_gz=UNDEFINED
if [[ $update_fb_instance -eq 1 ]]; then

    if [[ -f "$fbc/isql" ]]; then
        # ISQL Version: LI-T4.0.0.1946 Firebird 4.0 Beta 2 --> LI-T4.0.0.1946 --> 1946
        previous_fb_snapshot=$( echo "quit;" | $fbc/isql -q -z | awk '{print $3}' | awk -F '.' '{print $NF}' )
    fi

    fb_snapshots_root=$FB_SNAPSHOTS_URL # http://web.firebirdsql.org/download/snapshot_builds/linux

    if [[ "$fb" = "25" ]]; then
        systemctl list-unit-files | grep enabled | grep xinetd > /dev/null
        if [[ $? -ne 0 ]]; then
            sho "Service xinetd was disabled or absent. Install if need and enable it first." $log
            exit
        fi
        #systemctl restart xinetd
        #sho "Service xinetd was RESTARTED and now is running with PID=$(pgrep xinetd)." $log
        fb_major_vers_url=$fb_snapshots_root/fb2.5
        service_name=xinetd.service
    elif [[ "$fb" = "30" ]]; then
        fb_major_vers_url=$fb_snapshots_root/fb3.0
        fb_service_script_suffix="-superserver"
        service_name=firebird.$(echo "${dir_to_install_fb:1}" | tr / _)${fb_service_script_suffix}.service
    elif [[ "$fb" = "40" ]]; then
        fb_major_vers_url=$fb_snapshots_root/fbtrunk
        service_name=firebird.$(echo "${dir_to_install_fb:1}" | tr / _).service
    else
        sho "Invalid/unsupported FB major version passed. Can not defined URL for downloading FB snapshot." $log
        exit
    fi

    svc_load_script=${svc_script_startup_dir}/${service_name}
    if [[ -f $svc_load_script ]]; then
        sho "Found script to start systemd service: $svc_load_script" $log
    else
        sho "Script to start service: $svc_load_script - does NOT exist. We have to download and install FB focedly." $log
        previous_fb_snapshot=-1
    fi

    #curl -v –trace --proxy <[protocol://][user:password@]proxyhost[:port]>  $fb_major_vers_url 1>$tmp
    run_cmd="curl -L -v –trace $PROXY_DATA $fb_major_vers_url"
    sho "Attempt to download list of FB snapshots from $fb_major_vers_url. Command:" $log
    sho "$run_cmd" $log
    eval "$run_cmd" 1>$lst 2>$err
    grep -q -i "HTTP.*[[:space:]]200[[:space:]]OK" $err
    if [[ $? -eq 0 && -s "$lst" ]] ; then
        sho "Success. Size of downloaded list $lst: $(stat -c%s $lst). Strings to be parsed:" $log
        grep "<a href='.*${FB_SNAPSHOT_SUFFIX}'>" $lst >$tmp
        cat $tmp
        cat $tmp>>$log
    else
        # NB: curl always set its retcode to 0. Check of $? value can not be used here!
        # Remove all CR characters that curl produces in its output:
        sed 's/\r//' $err>$tmp
        rm -f $err
        sho "Failed. Log of downloading process $tmp, size $(stat -c%s $tmp):" $log
        cat $tmp
        cat $tmp >>$log
        sho "Job terminated." $log
        exit
    fi
    rm -f $tmp $err


    while read href; do
        sho "Loop for $lst, found element for download: $href" $log
        fb_tar_gz="$(basename -- $href)"
        fb_clean_name="${fb_tar_gz/-debuginfo/}" # Firebird-debuginfo-4.0.0.1946-Beta2.amd64.tar.gz --> Firebird-4.0.0.1946-Beta2.amd64.tar.gz
        actual_fb_snapshot=$( echo $fb_clean_name | awk -F'-' '{print $2}' | awk -F '.' '{print $NF}' )

        run_download=0
        if [[ $previous_fb_snapshot -ge $actual_fb_snapshot ]]; then
                sho "SKIP from downloading $fb_tar_gz: installed snapshot No. $previous_fb_snapshot is equal or more recent to offered on site: $actual_fb_snapshot." $log
        else
            if [[ $fb_tar_gz == *"debuginfo"* && ${GET_DEBUG_PACKAGE} -eq 0 ]]; then
                sho "SKIP downloading package $fb_tar_gz, check config parameter GET_DEBUG_PACKAGE" $log
            elif [[ "$fb" != "25" ]]; then
                [[ $fb_tar_gz == Firebird-* ]] && run_download=1
            elif [[ $fb_tar_gz == FirebirdCS* ]]; then
                # 2.5.x only: one need to get FirebirdCS-* but NOT FirebirdSS-*
                run_download=1
            fi

            if [[ $run_download -eq 1 ]]; then
                sho "Downloading $fb_tar_gz: installed snapshot No. $previous_fb_snapshot is OLDER than offered on site: $actual_fb_snapshot." $log
                run_cmd="curl -L -v -trace $PROXY_DATA $fb_major_vers_url/$fb_tar_gz"
                sho "Command: $run_cmd" $log
                eval "$run_cmd" 1>$tmpdir/$fb_tar_gz 2>$err
                sed 's/\r//' $err>$tmp
                sho "Download of $fb_tar_gz completed." $log
                rm -f $err
                if grep -q -i "HTTP.*[[:space:]]200[[:space:]]OK" $tmp; then
                    sho "Success. Size of downloaded file $tmpdir/$fb_tar_gz: $(stat -c%s $tmpdir/$fb_tar_gz)" $log
                else
                    sho "Failed. Check log:" $log
                    cat $tmp
                    cat $tmp >>$log
                    sho "Job terminated." $log
                    exit
                fi
                rm -f $tmp

                send_to_email=0
                if [[ -n "${mail_hdr_from}" && -n "${mail_pwd_from}" && -n "${mail_hdr_to}" && -n "${mail_smtp_url}"  ]] ; then
                    sho "Snapshot will be sent to e-mail according to config settings." $log
                    send_to_email=1
                else
                    sho "SKIP sending snapshot to e-mail: at least one of required settings is missed/commented in ${this_script_conf_name}" $log
                fi

                if [[ $send_to_email -eq 1 ]]; then

                    # https://unix.stackexchange.com/questions/1588/break-a-large-file-into-smaller-pieces
                    split --bytes $max_size_wo_split --numeric-suffixes --suffix-length=3 $tmpdir/${fb_tar_gz} $tmpdir/${fb_tar_gz}.

                    sho "Point after split original file onto volumes:" $log
                    sho "-------------------" $log
                    ls -1 $tmpdir/${fb_tar_gz}.*
                    ls -1 $tmpdir/${fb_tar_gz}.* >>$log
                    sho "-------------------" $log
                    cnt=0
                    while read -r line
                    do
                        sho "Processing attachment $line" $log
                        volume_name=$(basename -- "$line")
                        part_count_text="part: $((cnt+1)) of $(ls -1 $tmpdir/${fb_tar_gz}.* | wc -l)"
                        bnd_label="_002_$(uuidgen)_"
                        tmpeml=$tmpdir/tmp4mail.$(date +'%Y%m%d_%H%M%S').${cnt}.txt
			# fb_clean_name="${fb_tar_gz/-debuginfo/}" # Firebird-debuginfo-4.0.0.1946-Beta2.amd64.tar.gz --> Firebird-4.0.0.1946-Beta2.amd64.tar.gz
			# actual_fb_snapshot=$( echo $fb_clean_name | awk -F'-' '{print $2}' | awk -F '.' '{print $NF}' )
			#Subject: $mail_hdr_subj $(date +'%H:%M'). $([[ $fb_tar_gz == *"debuginfo"* ]] && echo Debug package for build || echo Build): ${actual_fb_snapshot} (FB $fb), ${part_count_text}
			cat <<-EOF > $tmpeml
			From: $mail_hdr_from
			To: $mail_hdr_to
			Subject: $mail_hdr_subj $(date +'%H:%M'). $([[ $fb_tar_gz == *"debuginfo"* ]] && echo Debug package || echo Build): ${fb_tar_gz}, ${part_count_text}
			MIME-Version: 1.0
			Content-Type: multipart/mixed;
			    boundary="$bnd_label"
			
			
			--${bnd_label}
			Content-Type: text/html; charset="utf-8"
			Content-Transfer-Encoding: quoted-printable
			
			<html>
			<head>
			<style>
			     body {
			         font: normal 14px courier;
			         background-color: #FFF8DC;
			     }
			</style>
			</head>
			<body>
			<pre>
			Snapshot: ${fb_clean_name}, ${part_count_text}
			Downloaded by: ${this_script_full_name}, on host: $(hostname)

			For re-assembling original file download all its parts and after this run:

			cat $(ls -1 $tmpdir/${fb_tar_gz}.* | xargs -n 1 basename | xargs echo) > ${fb_tar_gz}

			</pre>
			</body>
			</html>

			--${bnd_label}
			Content-Disposition: attachment;
			    filename="${volume_name}"
			Content-Transfer-Encoding: base64
			Content-Type: application/gzip;
			    name="${volume_name}"
			
			EOF
			base64 ${line}>>$tmpeml
			#base64 /opt/oltp-emul/oltp-scheduled.conf>>$tmpeml
			echo --${bnd_label}-->>$tmpeml
		        sho "Completed processing attachment $line" $log
		        curl_cmd="curl ${curl_verb} --url "${mail_smtp_url}" --ssl-reqd --mail-from "${mail_hdr_from}" --mail-rcpt "${mail_hdr_to}" --user "${mail_hdr_from}:${mail_pwd_from}" ${curl_insec}  --upload-file ${tmpeml}"
		        sho "Trying to send file ${volume_name} to e-mail. Command" $log
		        sho "${curl_cmd}" $log
		        # curl_opt=--verbose --url smtps://smtp.yandex.ru:465 --ssl-reqd --mail-from foo@yandex.ru --mail-rcpt bar@yandex.ru --user foo@yandex.ru:tot@11y-wr0ng --insecure
		        #########################
		        ###   s e n d i n g   ###
		        #########################
		        eval $curl_cmd 1>$tmp 2>&1
		        if [[ $? -eq 0 ]]; then
		            # We have to find BOTH lines in the curl output to be sure that message was sent OK:
		            #< 250 2.1.0 Sender OK
		            #... some other lines...
		            #< 250 2.1.5 Recipient OK
		            if [[ $(grep -l "250 .* Sender OK" $tmp | xargs grep -l "250 .* Recipient OK" | wc -l) -gt 0 ]]; then
		                sho "Result of sending: SUCCESS." $log
		                if [[ $((cnt+1)) -lt $(ls -1 $tmpdir/${fb_tar_gz}.* | wc -l) ]]; then
		                    # Example of error when messages are sent too often:
		                    # 450 4.2.1 The recipient has exceeded message rate limit. Try again later.
		                    sho "Now take some delay because of possible recipient deny of spam." $log
		                    sleep 30
		                fi
		            else
		                sho "Result of sending: UNKNOWN: could not find 'Sender/Recipient OK' phrases." $log
		            fi
		        else
		            sho "Result of sending: FAILED" $log
		        fi
		        echo "Details of sendipg process:">>$log
		        cat $tmp >>$log
		        # 4debug only:
		        #cp --force $tmp ${tmp}.${cnt}.log
                        cnt=$((cnt+1))
                        rm -f ${tmpeml} $tmp
                    done < <(ls -1 $tmpdir/${fb_tar_gz}.*)

                    # NB: removing must be done separately, after loop with sending:
                    while read -r line
                    do
                        sho "Removing file ${line}" $log
                        rm -f $line
                    done < <(ls $tmpdir/${fb_tar_gz}.*)
                fi
                # [[ $send_to_email -eq 1 ]]

                if [[ $fb_tar_gz == *"debuginfo"* ]]; then
                    sho "Files from debug package will be extrated after FB installation completes." $log
                    debug_package_tar_gz=$tmpdir/$fb_tar_gz
                else
                    mkdir -p $tmpdir/fb_extracted.$fb.tmp
                    sho "Extract files from compressed snapshot to $tmpdir/fb_extracted.$fb.tmp/" $log
                    tar xvf $tmpdir/$fb_tar_gz -C $tmpdir/fb_extracted.$fb.tmp --strip-components=1 1>$tmp 2>&1
                    if [[ $? -eq 0 ]]; then
                        rm -f $tmpdir/$fb_tar_gz
                        sho "Success. Compressed snapshot has been removed from disk." $log
                    else
                        sho "ACHTUNG. Snapshot extraction finished abnormaly. Job terminated." $log
                        cat $tmp
                        cat $tmp >>$log
                        exit
                    fi
                    rm -f $tmp
                fi
            fi
            # [[ $run_download -eq 1 ]]
        fi
    done < <( grep "<a href='.*${FB_SNAPSHOT_SUFFIX}'>" $lst | awk -F "'" '{print $2}' )
    # Example: <td nowrap class=content><a href='./Firebird-4.0.0.1884-Beta1.amd64.tar.gz'>Firebird-4.0.0.1884-Beta1.amd64.tar.gz</a></td>
    rm -f $lst

    # :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::


    if [[ $previous_fb_snapshot -ge $actual_fb_snapshot ]]; then
        sho "SKIP from re-installation. Perform only copying of firebird.conf prototype and restart of $service_name" $log

        #########################################################################
        # Create (if needed) $dir_to_install_fb/UDF and extract 'sleep-UDF' there
        #########################################################################
        check_for_sleep_UDF $dir_to_install_fb $fb_cfg_for_work $tmp $log

        #######################################
        # Replace firebird.conf with custom one
        #######################################
        cp --force --preserve $fb_cfg_for_work $dir_to_install_fb/firebird.conf
        chown firebird -R $dir_to_install_fb


        if [[ "$fb" != "25" ]]; then
            systemctl daemon-reload
            systemctl stop $service_name
            ##############################################################
            ### Add/update SYSDBA user with giving him password=${pwd} ###
            ##############################################################
            upd_sysdba_pswd ${pwd} $sql $tmp $err $log
            systemctl start $service_name
            systemctl status $service_name 1>$tmp 2>&1
        else
            set -x
            $dir_to_install_fb/bin/gsec -user sysdba -password $installer_random_pswd -modify sysdba -pw ${pwd}
            set +x
            systemctl restart xinetd.service
            systemctl status xinetd.service 1>$tmp 2>&1
        fi

        cat $tmp
        cat $tmp>>$log
    else
        if [[ -f "$dir_to_install_fb/bin/FirebirdUninstall.sh" ]]; then
            cd $dir_to_install_fb/bin
            ################################################################
            ### u n i n s t a l l     p r e v.    F B    i n s t a n c e ###
            ################################################################
            $dir_to_install_fb/bin/FirebirdUninstall.sh -silent
            if [[ -d "$dir_to_install_fb" ]]; then
                # This can occur if previous FB instance had .debug subfolders in it.
                # We change dir to PARENT, usually this will be /opt, and remove FB home:
                cd $(dirname "$dir_to_install_fb")
                rm -rf $dir_to_install_fb
            fi
        else
            #----------------------------------------------------
            # /opt/fb30/security3.fdb
            # /opt/fb40/security4.fdb
            rm -f $dir_to_install_fb/security${fb:0:1}.fdb
        fi

        cd $tmpdir/fb_extracted.$fb.tmp

        if [[ "$fb" != "25" ]]; then
            # Name of service must be defined via FOLDER where FB is to be installed:
            # 1) for FB 3.x: firebird.opt_fb30-superserver.service
            # 2) for FB 4.x: firebird.opt_fb40.service // ::: NB ::: without "-superserver" suffix.
            # Replace slash with underscore character: /opt/fb30 --> _opt_fb30 ; /opt/fb40 --> _opt_fb40
            # Then extract substring from this starting from 2nd char: opt_fb30; opt_fb40
            service_name=firebird.$(echo "${dir_to_install_fb:1}" | tr / _)${fb_service_script_suffix}.service

            ##################################################
            set -x
            bash ./install.sh -silent -path $dir_to_install_fb
            retcode=$?
            set +x
            if [[ $retcode -ne 0 ]]; then
                exit
            fi
            ##################################################

            cd $this_script_directory

            #########################################################################
            # Create (if needed) $dir_to_install_fb/UDF and extract 'sleep-UDF' there
            #########################################################################
            check_for_sleep_UDF $dir_to_install_fb $fb_cfg_for_work $tmp $log

            #######################################
            # Replace firebird.conf with custom one
            #######################################
            cp --force --preserve $fb_cfg_for_work $dir_to_install_fb/firebird.conf

            chown firebird -R $dir_to_install_fb

            ##############################################################
            ### Add/update SYSDBA user with giving him password=${pwd} ###
            ##############################################################
            upd_sysdba_pswd ${pwd} $sql $tmp $err $log

            # already defined: svc_load_script=${svc_script_startup_dir}/${service_name}
            svc_updated_txt=$tmpdir/$service_name
            rm -f $svc_updated_txt
            while read line; do
                echo $line>>$svc_updated_txt
                if [[ "$line" = "[Service]" ]]; then
		cat <<- EOF >>$svc_updated_txt
			# Added by $this_script_full_name $(date +'%d.%m.%Y %H:%M:%S')
			# ----------------------------------------
			LimitNOFILE=10000
			LimitCORE=infinity
			# ----------------------------------------
			
		EOF
                fi
            done < <(cat $svc_load_script)
            cp --force --preserve $svc_updated_txt $svc_load_script
            rm -f $svc_updated_txt

            systemctl daemon-reload
            systemctl start $service_name
            systemctl status $service_name 1>$tmp 2>&1
            cat $tmp
            cat $tmp>>$log
        else
            # NB: installer of FB 2.5 does not know option '-path'. Only '-silent' can be use.
            set -x
            bash ./install.sh -silent
            # Result: file /opt/fb25cs/SYSDBA.password will be created with random password like: ISC_PASSWD=ka2dbN7o
            # We have to change it now to be equal to $oltp_emul_conf_name parameter ${pwd}
            installer_random_pswd=$(grep ISC_PASSWD $dir_to_install_fb/SYSDBA.password | awk -F'=' '{print $2}')

            set -x
            $dir_to_install_fb/bin/gsec -user sysdba -password $installer_random_pswd -modify sysdba -pw ${pwd}
            set +x

            #########################################################################
            # Create (if needed) $dir_to_install_fb/UDF and extract 'sleep-UDF' there
            #########################################################################
            check_for_sleep_UDF $dir_to_install_fb $fb_cfg_for_work $tmp $log

            #######################################
            # Replace firebird.conf with custom one
            #######################################
            cp --force --preserve $fb_cfg_for_work $dir_to_install_fb/firebird.conf
            chown -R firebird $dir_to_install_fb
            set +x
            systemctl restart xinetd.service
            systemctl status xinetd.service 1>$tmp 2>&1
            cat $tmp
            cat $tmp>>$log
        fi

        if [[ -f $debug_package_tar_gz ]]; then
            #######################################################
            ### Decompress .debug package to $dir_to_install_fb ###
            #######################################################
            sho "Decompress .debug package to $dir_to_install_fb and change ownership of this dir." $log
            tar xvf $debug_package_tar_gz  -C $dir_to_install_fb --strip-components=3 1>$tmp 2>&1
            if [[ $? -eq 0 ]]; then
                rm -f $debug_package_tar_gz
                sho "Success. Debug package has been removed from disk." $log
            else
                sho "ACHTUNG. Debug package extraction finished abnormaly." $log
                cat $tmp
                cat $tmp >>$log
            fi
            rm -f $tmp
            chown firebird -R $dir_to_install_fb
        fi

        # Cleanup: we do not need downloaded snapshot anymore:
        cd $this_script_directory
        rm -rf $tmpdir/fb_extracted.$fb.tmp

    fi
    # $previous_fb_snapshot -lt $actual_fb_snapshot

    sho "Verifying that FB instance is working." $log
    rm -f /var/tmp/tmp4test.fdb
    rm -f $sql
	cat <<- EOF >$sql
            set list on;
            set echo on;
            set bail on;
            create database 'localhost:/var/tmp/tmp4test.fdb' user 'SYSDBA' password '${pwd}';
            select mon\$database_name, mon\$page_buffers,mon\$creation_date from mon\$database;
            create global temporary table gtt_test_firebird_tmp(s varchar(36) unique using index gtt_test_uniq_s);
            commit;
            set count on;
            insert into gtt_test_firebird_tmp(s) select uuid_to_char(gen_uuid()) from rdb\$types;
            set count off;
            select count(*) as added_rows_cnt from gtt_test_firebird_tmp;
            commit;
            set echo off;

                 set term ^;
                 create or alter procedure sys_get_fb_arch (
                      a_connect_with_usr varchar(31) default 'SYSDBA'
                     ,a_connect_with_pwd varchar(31) default '${pwd}'
                 ) returns(
                     fb_arch varchar(50)
                 ) as
                     declare cur_server_pid int;
                     declare ext_server_pid int;
                     declare att_protocol varchar(255);
                     declare v_test_sttm varchar(255);
                     declare v_fetches_beg bigint;
                     declare v_fetches_end bigint;
                 begin
                     fb_arch = rdb\$get_context('USER_SESSION', 'SERVER_MODE');
                     if ( fb_arch is null ) then
                     begin
                         select a.mon\$server_pid, a.mon\$remote_protocol
                         from mon\$attachments a
                         where a.mon\$attachment_id = current_connection
                         into cur_server_pid, att_protocol;
                         if ( att_protocol is null ) then
                             fb_arch = 'Embedded';
                         else if ( upper(current_user) = upper('SYSDBA')
                                   and rdb\$get_context('SYSTEM','ENGINE_VERSION') NOT starting with '2.5' 
                                   and exists(select * from mon\$attachments a 
                                              where a.mon\$remote_protocol is null
                                                    and upper(a.mon\$user) in ( upper('Cache Writer'), upper('Garbage Collector'))
                                             ) 
                                 ) then
                             fb_arch = 'SS';
                         else
                             begin
                                 v_test_sttm =
                                     'select a.mon\$server_pid + 0*(select 1 from rdb\$database)'
                                     ||' from mon\$attachments a '
                                     ||' where a.mon\$attachment_id = current_connection';
                                 select i.mon\$page_fetches
                                 from mon\$io_stats i
                                 where i.mon\$stat_group = 0  -- db_level
                                 into v_fetches_beg;
                                 execute statement v_test_sttm
                                 on external
                                      'localhost:' || rdb\$get_context('SYSTEM', 'DB_NAME')
                                 as
                                      user a_connect_with_usr
                                      password a_connect_with_pwd
                                      role left('R' || replace(uuid_to_char(gen_uuid()),'-',''),31)
                                 into ext_server_pid;
                                 in autonomous transaction do
                                 select i.mon\$page_fetches
                                 from mon\$io_stats i
                                 where i.mon\$stat_group = 0  -- db_level
                                 into v_fetches_end;
                                 fb_arch = iif( cur_server_pid is distinct from ext_server_pid, 
                                                'CS', 
                                                iif( v_fetches_beg is not distinct from v_fetches_end, 
                                                     'SC', 
                                                     'SS'
                                                   ) 
                                              );
                             end
                         fb_arch = trim(fb_arch) || ' ' || rdb\$get_context('SYSTEM','ENGINE_VERSION');
                         rdb\$set_context('USER_SESSION', 'SERVER_MODE', fb_arch);
                     end
                     suspend;
                 end 
                 ^ -- sys_get_fb_arch
                 set term ;^
                 commit;
                 select * from sys_get_fb_arch('SYSDBA', '${pwd}');
                 commit;
                 delete from mon\$attachments where mon\$attachment_id != current_connection ;
                 commit;

	    drop database;
	EOF
    $fbc/isql -q -z -i $sql 1>$tmp 2>$err
    rm -f $sql
    cat $tmp
    cat $tmp>>$log
    if [[ -s $err ]]; then
        cat $err
        cat $err >>$log
        sho "ACHTUNG. Check failed. Job terminated." $log
        exit
    fi
    rm -f $tmp $err

else # update_fb_instance = 0 - do NOT update FB, just run test; e.g. change FB arch from SS to CS, etc.

    sho "Input parameter 'update_fb_instance' is 0, SKIP updating FB instance and just run test." $log

    #########################################################################
    # Create (if needed) $dir_to_install_fb/UDF and extract 'sleep-UDF' there
    #########################################################################
    check_for_sleep_UDF $dir_to_install_fb $fb_cfg_for_work $tmp $log


    #######################################
    # Replace firebird.conf with custom one
    #######################################
    cp --force --preserve $fb_cfg_for_work $dir_to_install_fb/firebird.conf
    chown -R firebird $dir_to_install_fb
    if [[ "$fb" != "25" ]]; then
        # get parent dir for  '/opt/fb30/bin' or '/opt/fb40/bin' --> '/opt/fb30'; '/opt/fb40'
        if [[ "$fb" = "30" ]]; then
            fb_service_script_suffix="-superserver"
        fi
        service_name=firebird.$(echo "${dir_to_install_fb:1}" | tr / _)${fb_service_script_suffix}.service
        if [ ! -f "${svc_script_startup_dir}/${service_name}" ]; then
            sho "Script for launching service: '${service_name}' - not found in the folder ${svc_script_startup_dir}." $log
            sho "Trying to find actual name by grep..." $log
            # svc_script_startup_dir
            grep -m1 "$fbc/fbguard.*-daemon.*-forever" ${svc_script_startup_dir}/firebird*.service | grep -v "@" 1>$tmp 2>&1
            if [[ $? -gt 0 ]]; then
                sho "Could not find any file containing pattern '$fbc/fbguard.*-daemon.*-forever' in the folder ${svc_script_startup_dir}." $log
                sho "SERVICE NAME IS INVALID OR SOMETHING WRONG OCCURED DURING INSTALLATION." $log
                exit
            fi
            cat $tmp
            cat $tmp>>$log
            service_name=$(basename $(cat $tmp | cut -d':' -f1))
            sho "Actual script name for starting selected FB instance: >>>${service_name}<<<" $log
        fi

        # 26.09.2020: adjust script that starts service *EVERY* time before launch test, even if FB is not updated.
        # This is needed because we can build FB from sources and in this case script for start daemon will be overwritten by make.
        svc_load_script=${svc_script_startup_dir}/${service_name}
        svc_updated_txt=$tmpdir/$service_name
        rm -f $svc_updated_txt
        while read line; do
            if [[ $line == *"$this_script_full_name"* ]]; then
               continue
            elif [[ $line == *"LimitNOFILE"* ]]; then
               if [[ $line =~ ^#.* ]]; then
                   continue
               else
                   echo "#commented by $this_script_full_name $(date +'%d.%m.%Y %H:%M:%S'): $line" >>$svc_updated_txt
               fi
            elif [[ $line == *"LimitCORE"* ]]; then
               if [[ $line =~ ^#.* ]]; then
                   continue
               else
                   echo "#commented by $this_script_full_name $(date +'%d.%m.%Y %H:%M:%S'): $line" >>$svc_updated_txt
               fi
            else
                echo $line>>$svc_updated_txt
            fi
            if [[ "$line" = "[Service]" ]]; then
		cat <<- EOF >>$svc_updated_txt
			# Added by $this_script_full_name $(date +'%d.%m.%Y %H:%M:%S')
			LimitNOFILE=10000
			LimitCORE=infinity
		EOF
            fi
        done < <(cat $svc_load_script)
        cp --force --preserve $svc_updated_txt $svc_load_script
        rm -f $svc_updated_txt
        set -x
        systemctl daemon-reload
        systemctl restart $service_name
        set +x
        systemctl status $service_name 1>$tmp 2>&1
        cat $tmp
        cat $tmp>>$log
    fi

    if [[ "$fb" = "25" && $preferred_fb_mode = "cs" ]]; then
        sho "Check whether process xinetd is running: obtaining its PID using pgrep xinetd" $log
        pgrep xinetd 1>$tmp 2>&1
        retcode=$?
        cat $tmp
        cat $tmp>>$log
        if [[ $retcode -ne 0 ]]; then
            sho "Process xinetd is NOT running. Job terminated." $log
            exit
        else
            systemctl restart xinetd.service
            systemctl status $service_name 1>$tmp 2>&1
            cat $tmp
            cat $tmp>>$log
        fi
    else
        sho "Check whether port $port is listened by FB process." $log
        netstat --tcp --udp --listening --program --numeric | grep $port | grep -i "firebird\|fb_smp_server\|fb_inet_server" 1>$tmp 2>&1
        retcode=$?
        cat $tmp
        cat $tmp>>$log
        if [[ $retcode -ne 0 ]]; then
            sho "Port $port is NOT linstened by any FB process. Job terminated." $log
            exit
        else
            sho "Attempt to get FB server version." $log
            $fbc/fbsvcmgr localhost/$port:service_mgr info_server_version 1>$tmp 2>&1
            retcode=$?
            cat $tmp
            cat $tmp>>$log
            if [[ $retcode -ne 0 ]]; then
                sho "Could not get FB server version. Job terminated." $log
                exit
            fi
            sho "Firebird is running. We are ready to launch OLTP-EMUL test." $log
        fi
    fi
fi # update_fb_instance = 1 or 0

rm -f $fb_cfg_for_work $tmp $sql

sho "Perform copying $etalon_dbnm to $dbnm. Please WAIT." $log


cp --force --preserve $etalon_dbnm $dbnm
if [[ $? -ne 0 ]]; then
    sho "Could not make copy of etalon database. You have to check access rights or disk space! Job terminated." $log
    exit
fi
sho "Completed." $log

if [[ $etalon_shutdown -eq 1 ]]; then
    sho "Change state of target database from shutdown to normal." $log
    $fbc/gfix -online $dbnm 1>$tmp 2>&1
    retcode=$?
    cat $tmp
    cat $tmp>>$log
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change DB state to normal. Job terminated." $log
        exit
    else
        sho "Check attributes after change DB state:" $log
        $fbc/gstat -h $dbnm | grep -i attributes 1>$tmp 2>&1
        cat $tmp
        cat $tmp>>$log
        if grep -q -i "attributes[[:space:]].*shutdown" $tmp; then
            sho "DB is still in shutdown state! Job terminated." $log
            exit
        fi
        rm -f $tmp
    fi
fi


if [[ $etalon_readonly -eq 1 ]]; then
    sho "Change mode of target database from read_only to read_write." $log
    $fbc/gfix -mode read_write localhost/$port:$dbnm 1>$tmp 2>&1
    retcode=$?
    cat $tmp
    cat $tmp>>$log
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change DB mode to read_write. Job terminated." $log
        exit
    else
        sho "Check attributes after change DB mode:" $log
        $fbc/gstat -h $dbnm | grep -i attributes 1>$tmp 2>&1
        cat $tmp
        cat $tmp>>$log
        if grep -q -i "attributes[[:space:]].*read only" $tmp; then
            sho "DB is still in read only mode! Job terminated." $log
            exit
        fi
        rm -f $tmp
    fi
fi

# NB-1: it is better to change attributes FW and sweep BEFORE changing backup-lock,
# otherwise gstat -h will report old values for FW/sweep. See CORE-6399.
# NB-2: we have to use remote protocol here, i.e. specify 'localhost/$port' before $dbnm.
# Otherwise one may to get unexpected error like this:
# I/O error during "lock" operation for file "/home/bases/oltp40-etalone.encrypted.fdb"
# -Database already opened with engine instance, incompatible with current

if [[ -n "${create_with_fw}" ]]; then
    sho "Change FORCED WRITES for target DB, using parameter 'create_with_fw' = $create_with_fw." $log
    $fbc/gfix -w $create_with_fw localhost/$port:$dbnm 1>$tmp 2>&1
    cat $tmp
    cat $tmp>>$log
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change FW attribute. Job terminated." $log
        exit
    fi
fi
if [[ -n "${create_with_sweep}" ]]; then
    sho "Change SWEEP INTERVAL for target DB, using parameter 'create_with_sweep' = $create_with_sweep." $log
    $fbc/gfix -h $create_with_sweep localhost/$port:$dbnm 1>$tmp 2>&1
    cat $tmp
    cat $tmp>>$log
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change sweep interval. Job terminated." $log
        exit
    fi
fi
rm -f $tmp


if [[ $BACKUP_LOCK -eq 1 ]]; then
    sho "Config parameter 'BACKUP_LOCK' is 1." $log
    sho "Apply 'nbackup -L' command to target database." $log
    rm -f $dbnm.delta
    if [[ -f "$dbnm.delta" ]]; then
        sho "Could not drop file $dbnm.delta. Job terminated." $log
        exit
    fi
    $fbc/nbackup -L $dbnm 1>>$tmp 2>&1
    retcode=$?
    cat $tmp
    cat $tmp>>$log
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change DB mode to backup-lock. Job terminated." $log
        exit
    else
        sho "Check attributes after change DB mode to backup-lock:" $log
        $fbc/gstat -h $dbnm | grep -i attributes 1>$tmp 2>&1
        cat $tmp
        cat $tmp>>$log
        if grep -q -v -i "attributes[[:space:]].*backup lock" $tmp; then
            sho "DB state could not be changed to backup-lock. Job terminated." $log
            exit
        fi
        rm -f $tmp
    fi
else
    rm -f $dbnm.delta
fi

sho "#############################################################" $log
sho "Prepare completed. Check attributes of target DB before work:" $log
$fbc/gstat -h $dbnm | grep -i "page size\|page buffers\|attributes\|sweep" >$tmp
cat $tmp
cat $tmp >>$log
sho "#############################################################" $log
rm -f $tmp

unset ISC_USER
unset ISC_PASSWORD

sho "Clean file system cache..." $log


free -m >>$tmp
sync
echo 3 > /proc/sys/vm/drop_caches
free -m >>$tmp
cat $tmp >>$log
rm -f $tmp

sho "Completed. Now run OLTP-EMUL test with launching $winq ISQL sessions agains FB $fb." $log

cd $this_script_directory

sho "#################################################" $log
sho "### ::: L a u n c h ::: O L T P - E M U L ::: ###" $log
sho "#################################################" $log

cd $OLTP_HOME_DIR
bash ./1run_oltp_emul.sh $fb $winq
