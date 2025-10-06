#!/bin/bash

function pause(){
   read -p "$*"
}

sho() {
  local msg=$1
  local tmplog=${2:-"${joblog}"}
  local dts=$(date +'%d.%m.%y %H:%M:%S')
  echo $dts. ${msg}
  echo $dts. $msg>>${tmplog}
}

#.............................................

bulksho() {
    local tmplog=$1
    local joblog=$2
    local keep_tmp=${3:-0}
    local dts=$(date +'%d.%m.%y %H:%M:%S')

    # we have to set IFS to empty string in order to preserve leading spaces that are stored in the source file indentation
    # https://stackoverflow.com/questions/7314044/use-bash-to-read-line-by-line-and-keep-space
    # 'while IFS=... read...' - makes IFS be changed locally, only for duration of this loop:
    while IFS='' read -r line
    do
        echo $dts. "${line}" # NB: must enclose in quotes for disabling 'evaluation' of '*' or other wildcard characters!
        echo $dts. "$line" >> $joblog
    done < <(cat $tmplog)
    [[ $keep_tmp -eq 0 ]] && rm -f $tmplog
}

#.............................................

show_syntax() {
  clear
  local this_abend_name=$1
  rm -f this_abend_name
cat <<-EOF >$this_abend_name
Syntax:

$0  <mnemona>

where:
    <mnemona> = (fb|hq) - mnemonic for brand, case insensitive:
        fb - for vanilla Firebird;
        hq - for HQbird fork;
Example:

    $0  fb -- gather results for vanilla FB
    $0  hq -- gather results for HQbird fork
EOF
cat $this_abend_name
}

#.............................................

display_intention() {
    local msg=$1
    local run_cmd=$2
    local std_log=$3
    local std_err=${4:-"UNDEFINED"}
    echo
    sho "$msg" $joblog
cat <<- EOF
	RUNCMD: $run_cmd
	STDOUT: $std_log
	STDERR: $std_err
EOF
cat <<- EOF ->>$joblog
	RUNCMD: $run_cmd
	STDOUT: $std_log
	STDERR: $std_err
EOF
}

#.............................................

log_elapsed_time() {
  # 4 debug only
  local s1=$s1
  local plog=$2
  sleep 4
  local s2=$(date +%s)
  local sd=$(date -u -d "0 $s2 sec - $s1 sec" +"%H:%M:%S")
  local msg="Done for $sd, from $(date -d @$s1 +'%d-%m-%Y %H:%M:%S') to $(date -d @$s2 +'%d-%m-%Y %H:%M:%S')."
  #echo $msg
  echo $msg >>$plog
}

#.............................................

msg_noarg() {
  clear
  echo Specify:
  echo
  echo arg#1 = 25 or 30 or 40 - version of Firebird without dot: 2.5, 3.0, 4.0;
  echo -e arg#2 = \<N\> - number of ISQL sessions to be opened.
  echo
  echo Sample: 
  echo $0 25 50 - test Firebird 2.5 opening 50 ISQL sessions.
  echo
  echo Script is now terminated.
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

readcfg() {
    local cfg=$1
    local abendlog=$2

    while IFS='=' read lhs rhs
    do
        if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
            # | sed -e 's/^[ \t]*//'
            lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
            rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
            [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")

        export "$lhs=$rhs"
        if [ $? -gt 0 ]; then
cat <<-EOF >abendlog
	+++ ACHTUNG +++ SOMETHING WRONG IN YOUR CONFIG FILE '$cfg':
	Failed to evaluate: declare $lhs=$rhs
	Check declaration of parameter '$lhs':
	>${rhs}<
EOF
            cat $abendlog
            exit 1
        fi
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
    done < <(awk '$1=$1' $cfg  | grep "^[^#]")

}
# end of func 'readcfg'

#.............................................

catch_err() {
  local tmperr=$1
  local addnfo=${2:-""}
  local quit_if_error=${3:-1}
  if [ -s $tmperr ];then
    echo
    sho "Error log $tmperr is NOT EMPTY." $joblog
    echo ...............................
    cat $tmperr | sed -e 's/^/    /'
    cat $tmperr | sed -e 's/^/    /' >>$joblog
    echo ...............................
    if [ ! -z "$addnfo" ]; then
        echo
        echo Additional info / advice:
        echo $addnfo
        echo $addnfo >>$joblog
        echo
    fi

    if [ $quit_if_error -eq 1 ]; then
        sho "Script is terminated." $joblog
        exit 1
    fi
  else
    sho "Result: SUCCESS." $joblog
    rm -f $tmperr
  fi
}

#.............................................

msg_novar() {
  echo
  echo -e "##########################################################"
  echo -e At least one variable: \>\>\>$1\<\<\< - is NOT defined.
  echo Check config file $cfg.
  echo -e "##########################################################"
  echo
  echo Script is now terminated.
}

#.............................................

msg_nofile() {
  echo
  echo At least one of Firebird command line utilities NOT FOUND in the folder
  echo -e defined by variable \'fbc\' = \>\>\>$fbc\<\<\<
  echo
  echo This folder must have following executable files: $clu, fbsvcmgr
  echo
  echo Verify value of parameter \'fbc\' in the file \'$cfg\'!
  echo Script is now terminated.
}

#.............................................

msg_noserv() {
  echo
  echo -e Could NOT define server version on host=\>$host\<,   port=\>$port\<
  echo Result of trying to do that via fbsvcmgr:
  echo -----------------------------------------
  cat $tmperr
  echo -----------------------------------------
  echo
  echo 1. Ensure that Firebird is running on specified host.
  echo 2. Check settings in $cfg: host, port, user and password.
  echo
  echo Script is now terminated.
  exit 1
}

#.............................................

venv_start() {
    if [[ ! -z "${PY_VENV_RUN}" ]]; then
        echo Intro ${FUNCNAME}: PY_VENV_RUN=$PY_VENV_RUN
        source ${PY_VENV_RUN}
    fi
}

venv_stop() {
    if [[ ! -z "${PY_VENV_RUN}" ]]; then
        echo Intro ${FUNCNAME}
        deactivate
    fi
}

#.............................................

fb_launch() {
    local fb_lock_dir=$1
    local fbc=$2
    local fbport=$3
    local waiting_max_time=4
    local __fbguard_pid=$5  # output arg.
    local __firebird_pid=$6 # output arg.

    local run_cmd check_listening_port_cmd msg_subj elev sec must_abend
    local tmplst tmplog tmperr tmppy

    sho "Routine $FUNCNAME: start." $joblog

    tmplst=$LOGDIR/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').lst
    tmplog=$LOGDIR/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').tmp
    tmperr=$LOGDIR/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').err
    tmppy=$LOGDIR/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').py

cat <<-EOF > $tmplog
    ##############################################################
    ###  T R Y I N G    T O    S T A R T     F I R E B I R D   ###
    ##############################################################
EOF
    bulksho $tmplog $joblog

    if [[ "${fb_lock_dir}" == "default" ]]; then
        run_cmd="${fbc}/fbguard -daemon"
    else
        run_cmd="export FIREBIRD_LOCK="${fb_lock_dir}"; ${fbc}/fbguard -daemon"
    fi
    msg_subj="Launch Firebird server via 'fbguard -daemon'. Command: $run_cmd"
    sho "$msg_subj" $joblog
    eval "$run_cmd" 1>$tmplst 2>$tmperr
    elev=$?
    sho "Retcode: $elev" $joblog
    catch_err $tmperr
    # send_to_email "$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). INFO. Attempt to launch Firebird server, command: $run_cmd" $tmplst n/a n/a  elev
    sec=0
    must_abend=0

    # 09-jan-2024 DEPRECATED IN DEBIAN! --> run_cmd="netstat --all --numeric --program --timers | grep \":${fbport} \""
    # DOES NOT WORK ON CentOS-7! --> check_listening_port_cmd="ss --listening --tcp --processes | grep -i \"listen\" | grep \":${fbport} \" | grep -i \"firebird\""
    #/home/ibase/venv/bin/python /home/ibase/rundaily-2024/qa_rundaily.misc-utils.py isPortListening 127.0.0.1 3300
cat <<-EOF > $tmppy
	import socket
	s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
	try:
	    s.connect( ( '127.0.0.1', ${fbport} ) )
	    # Note close() releases the resource associated with a connection but does not necessarily close the connection immediately.
	    # If you want to close the connection in a timely fashion, call shutdown() before close()
	    # Shut down one or both halves of the connection. If how is SHUT_RD, further receives are disallowed.
	    # If how is SHUT_WR, further sends are disallowed. If how is SHUT_RDWR, further sends and receives are disallowed.
	    s.shutdown(socket.SHUT_RDWR)
	    s.close()
	    print(1)
	except:
	    print(0)
EOF

    check_listening_port_cmd="$PYTHON_BIN -u ${tmppy}"

    while :
    do
        ##################################################################
        ###  W A I T    F O R    P O R T    I S     L I S T E N I N G  ###
        ##################################################################
cat <<-EOF >$tmplog
	Seconds passed since launch 'fbguard -daemon': ${sec}/${waiting_max_time}.
	Obtain information about port ${fbport}. Command:
	$check_listening_port_cmd
EOF
        bulksho $tmplog $joblog

        venv_start
        eval $check_listening_port_cmd 1>$tmplog 2>&1
        venv_stop
        if grep -q "1" $tmplog; then
            bulksho $tmplog $joblog
            sho "Result: found that port $fbport is LISTENING after $sec seconds. Break from loop." $joblog
            break
        else
            # 03.02.2021: this can occur if the same port was used on previous iteration. The reason is undefined :(((
            # Config parameter 'INCREMENT_PORT_ON_EACH_ITER' must be 1 in this case (to change port number on each iter)
            sho "Result: port $fbport is NOT YET listenable:" $joblog
            sho "Check presense of FB processes." $joblog

            ps aux | grep "$fbc/firebird\|$fbc/fbguard" | grep -v grep 1>$tmplst
            if [[ -s "$tmplst" ]]; then
                bulksho $tmplst $joblog
            else
                sho "ABEND. Could not find PID for fbguard and/or firebird processes. Break from loop." $joblog
                must_abend=1
                break
            fi

            sec=$((sec+1))
            if [[ $sec -gt $waiting_max_time ]]; then
                must_abend=1
                break
            fi
            sho "Wait for 1 second." $joblog
            sleep 1
            continue
        fi
    done

    rm -f $tmplog $tmplst

    if [[ $must_abend -eq 1 ]]; then
cat <<-EOF >$tmplog
        $CRITICAL_LABEL

        Timeout expired. Could not find process which is listening to port $fbport
        after $waiting_max_time seconds. Perhaps firebird.log contains 'Address already is in use'.
        Abend. Job terminated.
EOF
        exit 1
    fi

    # Get PIDs of fbguard and firebird processes:
    #############################################
    ps aux | grep "$fbc/firebird\|$fbc/fbguard" | grep -v grep 1>$tmplst 2>&1
    # root     15156  0.0  0.0  10524  2416 ?        S    09:02   0:00 /opt/scripts/qa-rundaily/unpacked-snapshot.tmp/bin/fbguard -daemon
    # root     15157  0.1  0.2 155236 17916 ?        Sl   09:02   0:00 /opt/scripts/qa-rundaily/unpacked-snapshot.tmp/bin/firebird            
    fbguard_pid=$(grep "$fbc/fbguard" $tmplst | head -1 | awk '{print $2}')
    firebird_pid=$(grep "$fbc/firebird" $tmplst | head -1 | awk '{print $2}')

    if [[ -z "$fbguard_pid" || -z "$firebird_pid" || $fbguard_pid -le 0 || $firebird_pid -le 0 ]]; then
        msg_abend="Could not find PID for processes 'fbguard' and 'firebird' which have been launched from '$fbc'"
        sho "$msg_abend" $joblog
        # 09-jan-2024 DEPRECATED IN DEBIAN! >> netstat --listening --numeric --program --timers >>$tmplst
        echo "Abend. Job terminated." >>$tmplst
        # send_to_email "$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). ALERT. $msg_abend" $tmplst n/a n/a  elev
        bulksho $tmplst $joblog
        exit 1
    fi

    rm -f $tmplst $tmplog $tmperr $tmppy

    # Returning values
    ##################
    eval $__fbguard_pid="'$fbguard_pid'"
    eval $__firebird_pid="'$firebird_pid'"

    sho "Routine $FUNCNAME: finish: fbguard_pid=$fbguard_pid, firebird_pid=$firebird_pid" $joblog

}
# end of func 'fb_launch'

#.............................................

fb_basic_check()
{
    local fbc=$1
    local results_fbk=$2
    local tmpdir=$3
    local dba_user=$4
    local dba_pswd=$5

    local tmpdbdir tmplog tmperr tmpsql tmpfdb

    sho "Routine $FUNCNAME: start." $joblog

    tmplog=$tmpdir/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').tmp
    tmperr=$tmpdir/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').err
    tmpsql=$tmpdir/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').sql
    tmpfdb=$(dirname ${results_fbk})/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').fdb

    sho "Verifying that FB instance is working. Test DB: ${tmpfdb}" $joblog
    rm -f ${tmpfdb}
    rm -f $tmpsql
cat <<- EOF >$tmpsql
    set list on;
    set echo on;
    set bail on;
    create database 'localhost:${tmpfdb}' user '${dba_user}' password '${dba_pswd}';
    select mon\$database_name, mon\$page_buffers,mon\$creation_date from mon\$database;
    select * from mon\$attachments;
    commit;
    -- Verify access to 'fb_table_*' and 'fb_blob_*' files: server must have access to the folder defined
    -- either by environment 'FIREBIRD_TMP', 'TEMP', 'TMP' or config parameter 'TempTableDirectory':
    create global temporary table gtt_test_firebird_tmp(s varchar(36) unique using index gtt_test_uniq_s);
    commit;
    set term ^;
    execute block as
        declare n int = 300;
    begin
        while (n > 0) do
        begin
            insert into gtt_test_firebird_tmp( s ) values( uuid_to_char(gen_uuid()) );
            n = n - 1;
        end
    end ^
    set term ;^
    -- Verify access to 'fb_sort_*' files: server must have access to the folder defined
    -- either by environment 'FIREBIRD_TMP', 'TEMP', 'TMP' or config parameter 'TempDirectories':
    -- set explain on;
    -- explained plan must contain smth like: "Sort (record length: 1046, key length: 1008)":
    select count(*) as sorted_rows_cnt from (select lpad('', 1000, uuid_to_char(gen_uuid())) as long_txt from gtt_test_firebird_tmp, gtt_test_firebird_tmp order by 1);
    -- set explain off;
    commit;
    set echo off;
    set term ^;
    create or alter procedure sys_get_fb_arch (
          a_connect_with_usr varchar(31) default '${dba_user}'
         ,a_connect_with_pwd varchar(31) default '${dba_pswd}'
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
             else if ( upper(current_user) = upper('${dba_user}')
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
    select * from sys_get_fb_arch('${dba_user}', '${dba_pswd}');
    commit;
    delete from mon\$attachments where mon\$attachment_id != current_connection ;
    commit;
    drop database;

EOF
    $fbc/isql -q -z -i $tmpsql 1>$tmplog 2>$tmperr
    bulksho $tmplog $joblog
    catch_err $tmperr
    rm -f $tmplog $tmperr $tmpsql
    sho "Routine $FUNCNAME: finish." $joblog
}

# end of func 'fb_basic_check'


################################
###     M A I N   P A R T    ###
################################
brand_mnemona=$1

abendlog=/var/tmp/oltp_overall_report.abend.err
rm -f $abendlog

[ -z $1 ] && show_syntax $abendlog && exit 1
brand_mnemona=$(echo "$brand_mnemona" | tr '[:upper:]' '[:lower:]')

this_script_directory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd ${this_script_directory}
this_script_full_name=${BASH_SOURCE[0]}
this_script_name_only=$(basename $this_script_full_name)
this_script_name_only=${this_script_name_only%.*}

# oltp_overall_report_config_hq.nix
# oltp_overall_report_config_fb.nix
this_script_conf_name=$this_script_directory/${this_script_name_only}_config_${brand_mnemona}.nix

sho "Parsing config file ${this_script_conf_name}" $abendlog
shopt -s extglob

##########################
# READ THIS SCRIPT CONFIG:
##########################
readcfg $this_script_conf_name $abendlog

mkdir -p $LOGDIR && touch $LOGDIR/tmp.tmp && rm $LOGDIR/tmp.tmp
if [ $? -eq 0 ]; then
    sho "Successfully created / accessed LOGDIR=$LOGDIR" $abendlog
else
    sho "Could NOT create / access LOGDIR=$LOGDIR" $abendlog
    exit 1
fi

if [[ "${brand_mnemona}" == "fb" ]]; then
    head_vers=$FB_HEAD_VERSION
elif [[ "${brand_mnemona}" == "hq" ]]; then
    head_vers=$HQ_HEAD_VERSION
else
    sho "Could not find head version for value of input argument 'brand_mnemona'=${brand_mnemona}." $abendlog
    exit 1
fi

fb_lock_dir=${brand_mnemona^^}_HEAD_LOCK_DIR # name of OPTIONAL config parameter for replacing default FIREBIRD_LOCK variable: FB_HEAD_LOCK_DIR, HQ_HEAD_LOCK_DIR
fb_lock_dir=${!fb_lock_dir} # value of 'XXXX_LOCK_DIR', e.g. /tmp/fb60_lock etc
if [[ -z "${fb_lock_dir}" ]]; then
    sho "Parameter '${brand_mnemona^^}_HEAD_LOCK_DIR' not specified. Default value will be used for FIREBIRD_LOCK variable." $abendlog
    fb_lock_dir="default" # need to be non-empty because will be used as 1st arg for fb_launch() routine
else
    sho "Parameter '${brand_mnemona^^}_HEAD_LOCK_DIR' not empty. Value for FIREBIRD_LOCK: '${fb_lock_dir}'" $abendlog
    mkdir -p ${fb_lock_dir} && touch ${fb_lock_dir}/tmp.tmp && rm ${fb_lock_dir}/tmp.tmp
    if [[ $? -eq 0 ]]; then
        echo "Successfully created / accessed fb_lock_dir=${fb_lock_dir}"
    else
        msg="Could NOT create / access fb_lock_dir=${fb_lock_dir}"
        echo $msg
        echo $msg > $abendlog
        exit 1
    fi
fi

dts=$(date +'%Y%m%d_%H%M%S')
this_script_log=$LOGDIR/${this_script_name_only}.$dts.log
tmplst=$LOGDIR/${this_script_name_only}.${dts}.lst
tmpmap=$LOGDIR/${this_script_name_only}.${dts}.map
tmpsql=$LOGDIR/${this_script_name_only}.${dts}.sql
tmplog=$LOGDIR/${this_script_name_only}.${dts}.tmp
tmperr=$LOGDIR/${this_script_name_only}.${dts}.err

joblog=$this_script_log
mv -f $abendlog $joblog

sho "Intro $this_script_full_name. Current dir: $(pwd)"

# List of OLTP-EMUL config files which must be parsed for current ${brand_mnemona}:
# for 'fb:
#   oltp60_config=../../src/oltp-fb60.conf.nix
#   oltp50_config=../../src/oltp-fb50.conf.nix
#   oltp40_config=../../src/oltp-fb40.conf.nix
# for 'hq':
#   oltp50_config=../../src/oltp-hq50.conf.nix
#   oltp40_config=../../src/oltp-hq40.conf.nix
#   oltp30_config=../../src/oltp-hq30.conf.nix
grep -E "^oltp[[:digit:]]+_config[[:space:]]*=" ${this_script_conf_name} > $tmplst

########################################################
###   r e a d    o l t p - e m u l   c o n f i g s   ###
########################################################
unset CHART_COLORS_PERF_SCORE CHART_COLORS_MEMO_ALL CHART_COLORS_MEMO_ATT CHART_COLORS_MEMO_TRN CHART_COLORS_MEMO_STM
while read oltp_cfg_full_path; do
    echo oltp_cfg_full_path=$oltp_cfg_full_path
    oltp_config_file=$(basename $oltp_cfg_full_path)
    echo oltp_config_file=$oltp_config_file
    #echo $oltp_config_file | grep $head_vers
    sho "Start parsing config $oltp_cfg_full_path"
    awk '$1=$1' $oltp_cfg_full_path | grep "^[^#]" | grep -i -E "usr[[:space:]]?=|pwd[[:space:]]?=|fbc[[:space:]]?=|port[[:space:]]?=|mon_unit_perf[[:space:]]?=|dbnm[[:space:]]?=|results_storage_fbk[[:space:]]?=|html_chart_color_[^[:space:]]+[[:space:]]?=" > $tmplog
    echo ..................
    cat $tmplog
    echo ..................

    while IFS='=' read lhs rhs
    do
        if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
            lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
            rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')

            [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")

            # ${some_var//[!0-9]/} --> remove all non-digit characters: oltp-fb60.coonf.nix --> 60
            var_name_prefix="${brand_mnemona}${oltp_config_file//[!0-9]/}" # 'fb60', 'hq50' etc
            if [[ "${lhs,,}" == "html_chart_color_perf_score" ]]; then
                CHART_COLORS_PERF_SCORE="${CHART_COLORS_PERF_SCORE},${rhs}"
            fi
            if [[ "${lhs,,}" == "html_chart_color_memo_all" ]]; then
                CHART_COLORS_MEMO_ALL="${CHART_COLORS_MEMO_ALL},${rhs}"
            fi
            if [[ "${lhs,,}" == "html_chart_color_memo_att" ]]; then
                CHART_COLORS_MEMO_ATT="${CHART_COLORS_MEMO_ATT},${rhs}"
            fi
            if [[ "${lhs,,}" == "html_chart_color_memo_trn" ]]; then
                CHART_COLORS_MEMO_TRN="${CHART_COLORS_MEMO_TRN},${rhs}"
            fi
            if [[ "${lhs,,}" == "html_chart_color_memo_stm" ]]; then
                CHART_COLORS_MEMO_STM="${CHART_COLORS_MEMO_STM},${rhs}"
            fi

            if [[ "$oltp_config_file" == *"$head_vers"* ]]; then
                unset head_lhs
                if [[ "${lhs^^}" == "USR" ]]; then
                    head_lhs=DBA_USER
                elif [[ "${lhs^^}" == "PWD" ]]; then
                    head_lhs=DBA_PSWD
                elif [[ "${lhs^^}" == "RESULTS_STORAGE_FBK" ]]; then
                    head_lhs=HEAD_STORAGE_FBK
                elif [[ "${lhs^^}" == "FBC" ]]; then
                    # folder with most recent version of FB (will be used for DB_OVERALL).
                    # All .fbk will be restored using this version.
                    ############
                    head_lhs=HEAD_FBC
                    ############
                elif [[ "${lhs^^}" == "PORT" ]]; then
                    # folder with most recent version of FB (will be used for DB_OVERALL).
                    # All .fbk will be restored using this version.
                    ############
                    head_lhs=HEAD_PORT
                    ############
                fi
                if [[ -n "$head_lhs" ]]; then
                    sho "Additional declaration for head_vers=${head_vers}:"
                    echo -e param=\|$head_lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
                    echo -e param=\|$head_lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")>>$joblog
                    export "$head_lhs=$rhs"
                    echo
                fi
            fi

            lhs=${var_name_prefix}_${lhs}
            echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
            echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")>>$joblog

            echo export "$lhs=$rhs"
            export "$lhs=$rhs"
            if [ $? -gt 0 ]; then
cat <<-EOF >abendlog
	+++ ACHTUNG +++ SOMETHING WRONG IN YOUR CONFIG FILE '$cfg':
	Failed to evaluate: declare $lhs=$rhs
	Check declaration of parameter '$lhs':
	>${rhs}<
EOF
                cat $abendlog
                exit 1
            fi
            if [[ "${lhs}" == *"mon_unit_perf"* && "${rhs}" != "2" ]]; then
                sho "WARNING. Config parameter 'mon_unit_perf' in $oltp_cfg_full_path is $rhs. Memory consumtion will no be included in the report for ${var_name_prefix}."
            fi

        fi
    ### 07.11.2020 DOES NOT WORK WHEN RUN FROM CRON!!! >>> done < <( awk '$1=$1' $oltp40_config | grep "^[^#]" | grep -i -E "usr[[:space:]]?=|pwd[[:space:]]?=|fbc[[:space:]]?=|mon_unit_perf[[:space:]]?=|results_storage_fbk[[:space:]]?="  )
    done<$tmplog
done < <(grep . $tmplst | awk -F "=" '{print $2}')

# Remove trailing slash from variables which store PATHs:
fbc=${HEAD_FBC%/}
LOGDIR=${LOGDIR%/}
DETAILS_DIR=${DETAILS_DIR%/}

# client library that must be used for connect:
# it must belong to MOST RECENT Firebird major version
FB_CLNT=$(dirname "$HEAD_FBC")/lib/libfbclient.so
if [[ ! -s "${FB_CLNT}" ]]; then
    sho "Client library '$FB_CLNT' NOT found."
    exit 1
fi

export CHART_COLORS_PERF_SCORE=${CHART_COLORS_PERF_SCORE:1} # 'red,blue,green' etc
export CHART_COLORS_MEMO_ALL=${CHART_COLORS_MEMO_ALL:1}
export CHART_COLORS_MEMO_ATT=${CHART_COLORS_MEMO_ATT:1}
export CHART_COLORS_MEMO_TRN=${CHART_COLORS_MEMO_TRN:1}
export CHART_COLORS_MEMO_STM=${CHART_COLORS_MEMO_STM:1}

# Dir where .fbk and DB with overall results are stored.
# Must be created by MOST RECENT major version of FB.
DB_OVERALL_DIR=$(dirname "${HEAD_STORAGE_FBK}")

# Database that will be used to store overall report data:
DB_OVERALL_FILE=${DB_OVERALL_DIR}/${this_script_name_only}_${brand_mnemona}.tmp.fdb

cat <<-EOF >$tmplog

	Check settings:
	  DBA_USER=$DBA_USER
	  DBA_PSWD=$DBA_PSWD
	  HEAD_FBC=$HEAD_FBC
	  FB_CLNT=$FB_CLNT
	  HEAD_STORAGE_FBK=$HEAD_STORAGE_FBK
	  LOGDIR=$LOGDIR
	  DETAILS_DIR=$DETAILS_DIR
	  DB_OVERALL_FILE=$DB_OVERALL_FILE
EOF
bulksho $tmplog $joblog

can_upload=$SSH_UPLOAD_ENABLED # from .conf
if [[ $can_upload -eq 1 ]]; then

    # Get permissions mask for $SSH_PRIVATE_KEY_FILE as numeric value.
    # Check that permissions are NOT too open: must be either 400 or 600.
    sho "Get access rights for SSH_PRIVATE_KEY_FILE=$SSH_PRIVATE_KEY_FILE as numeric value."
    stat -c '%a' $SSH_PRIVATE_KEY_FILE 1>$tmplog 2>$tmperr
    retcode=$?
    if [[ -s "$tmperr" ]]; then
        sho "ERROR detected while obtaining access rights checking to SSH_PRIVATE_KEY_FILE=$SSH_PRIVATE_KEY_FILE"
        cat $tmperr
        cat $tmperr>>$joblog
        sho "Report will not be uploaded."
        can_upload=0
    else
        ssh_key_chmod_value=$(cat $tmplog)
        if [[ $ssh_key_chmod_value -eq 400 || $ssh_key_chmod_value -eq 600 ]]; then
            sho "Access rights check PASSED: $ssh_key_chmod_value"
        else
            # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            # @         WARNING: UNPROTECTED PRIVATE KEY FILE!          @
            # @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
            # Permissions 0644 for '<name>.ppk' are too open.
            # It is required that your private key files are NOT accessible by others.
            # This private key will be ignored.
            # Load key "<name>.ppk": bad permissions
            sho "### ACHTUNG ### UNPROTECTED PRIVATE KEY FILE. YOU HAVE TO SET PERMISSIONS FOR THAT TO 400 OR 600."
            can_upload=0
        fi
    fi

    tmpfile=$SSH_RESULTS_HOME_DIR/tmp_check_access.tmp
    run_cmd="ssh -i $SSH_PRIVATE_KEY_FILE $SSH_UPLOAD_HOST_DATA 'hostname; touch $tmpfile;  ls --full-time $tmpfile; rm -f $tmpfile; exit;'"
    display_intention "Check access to $SSH_RESULTS_HOME_DIR folder on $SSH_UPLOAD_HOST_DATA" "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    retcode=$?
    if [[ -s "$tmperr" ]]; then
        sho "ERROR detected while checking access to $SSH_RESULTS_HOME_DIR folder using $SSH_UPLOAD_HOST_DATA"
        cat $tmperr
        cat $tmperr>>$joblog
        sho "Report will not be uploaded."
        can_upload=0
    else
        sho "SUCCESS. Remote host allows to operate with folder $SSH_RESULTS_HOME_DIR using $SSH_UPLOAD_HOST_DATA"
        cat $tmplog
    fi
fi
rm -f $tmplog $tmperr

dbauth="-user $DBA_USER -pas $DBA_PSWD"
dbconn="localhost:$DB_OVERALL_FILE"

mkdir -p $DETAILS_DIR && touch $DETAILS_DIR/tmp.tmp && rm $DETAILS_DIR/tmp.tmp
if [ $? -eq 0 ]; then
  sho "Successfully created / accessed DETAILS_DIR '$DETAILS_DIR'"
else
  echo Could NOT create / access DETAILS_DIR '$DETAILS_DIR'
  exit 1
fi

sho "Remove files in '$LOGDIR' with age more than $LOGS_MAX_AGE days."


find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.log" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.err" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.tmp" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.lst" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.sql" -mtime +${LOGS_MAX_AGE} -exec rm {} \;

find $DETAILS_DIR -type f -name "*.htm" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $DETAILS_DIR -type f -name "*.html" -mtime +${LOGS_MAX_AGE} -exec rm {} \;

#############################################################
ps aux | grep fbguard | grep -v grep > $tmplog
ps aux | grep "firebird\|fbsvcmgr\|fbtracemgr\|gbak\|gstat\|isql\|gsec" | grep -v "grep\|fbguard" >> $tmplog
# firebird 18127  0.0  0.0  29652  1052 ?        S    09:11   0:00 /opt/fb30/bin/fbguard -pidfile
# firebird 18147  0.0  0.0  29260  1080 ?        S    09:11   0:00 /opt/fb40/bin/fbguard -pidfile
# firebird 18128  0.0  0.0 319848  3780 ?        Sl   09:11   0:00 /opt/fb30/bin/firebird
# firebird 18148  0.0  0.0 327200  5352 ?        Sl   09:11   0:00 /opt/fb40/bin/firebird
# root     24475  0.0  0.0 134352  2884 pts/1    S+   09:25   0:00 /opt/firebird/bin/isql
#     1      2     3    4     5     6   7        8     9       10          11               12
bulksho $tmplog $joblog 1

while read line; do
    fb_pid=$(echo $line | awk '{print $2}')
    if [[ "$line" == *" ${fbc}"* ]]; then
        sho "Detect FB-related process launched in '${fbc}': PID=$fb_pid - kill it." $joblog
        #sho "kill -9 $fb_pid" $joblog
        kill -9 $fb_pid
        if [[ $? -ne 0 ]]; then
            sho "Could not kill process $fb_pid. Jon terminated." $joblog
            exit 1
        fi
    else
        sho "Process $fb_pid was launched from other folder (differs from '${fbc}'). SKIP kill action." $joblog
    fi
done < <(grep . $tmplog)
# < <(cat $tmplog | awk '{print $2}')

#############################################################

##############################################################
###  T R Y I N G    T O    S T A R T     F I R E B I R D   ###
##############################################################
fb_launch "${fb_lock_dir}" ${fbc} ${HEAD_PORT} $SECONDS_WAIT_FOR_PORT  fbguard_pid firebird_pid
sho "Return from fb_launch: fbguard_pid=$fbguard_pid; firebird_pid=$firebird_pid" $joblog
# ps aux| grep "/mnt/hdd/.*/bin/" | grep -v grep

#run_cmd="$HEAD_FBC/fbsvcmgr localhost:service_mgr user $DBA_USER password $DBA_PSWD info_server_version"
#fb_app_pid=0
#display_intention "Attempt to get SERVER version in $HEAD_FBC folder" "$run_cmd" "$this_script_log" "$tmperr"
## TODO: why permission error can occur here for /tmp/firebird/fb_init ?
#eval "$run_cmd" 1>$tmplog 2>$tmperr

##############################################################
###  B A S I C    C H E C K   O F    R U N N I N G    F B  ###
##############################################################
fb_basic_check ${fbc} ${HEAD_STORAGE_FBK} ${LOGDIR} ${DBA_USER} ${DBA_PSWD}

rm -f $DETAILS_DIR/*.html
sho "RECREATE_DB=$RECREATE_DB"

if [[ $RECREATE_DB -eq 0 ]]; then
    if [[ -f "$DB_OVERALL_FILE" ]]; then
        ls -l $DB_OVERALL_FILE 1>$tmplog
        cat $tmplog
        cat $tmplog >>$joblog
        run_cmd="$HEAD_FBC/gstat -h $DB_OVERALL_FILE -user $DBA_USER -pas $DBA_PSWD"
        display_intention "DB with overall data does exist. Attempt to check its header" "$run_cmd" "$this_script_log" "$tmperr"
        eval "$run_cmd" 1>$tmplog 2>$tmperr
        if [[ $? -ne 0 ]]; then
            cat $tmperr
            cat $tmperr >>$joblog
            sho "Database $DB_OVERALL_FILE seems to be invalid or has old ODS. We have to RECREATE it."
            RECREATE_DB=1
        fi

        if [[ $RECREATE_DB -eq 0 ]]; then
            echo "set list on; set bail on; select info from ddl_outcome;" > $tmpsql
            run_cmd="$HEAD_FBC/isql $dbconn $dbauth -q -i $tmpsql"
            display_intention "Attempt to get info about DDL completition." "$run_cmd" "$this_script_log" "$tmperr"
            # ::: NB :::
            # isql can return retcode=0 when DB is corrupted! We have to ensure that size of STDERR is zero.
            eval "$run_cmd" 1>$tmplog 2>$tmperr
            if [[ $? -ne 0 || -s "$tmperr"  ]]; then
                cat $tmperr
                cat $tmperr >>$joblog
                sho "Database $DB_OVERALL_FILE does not contain info about DDL completition. We have to RECREATE it."
                RECREATE_DB=1
            else
                cat $tmplog
                grep . $tmplog | sed 's/ *$//g' >>$joblog
            fi
            rm -f $tmplog $tmpsql $tmperr
        fi

    else
        sho "Database $DB_OVERALL_FILE does not exist. We have to RECREATE it."
        RECREATE_DB=1
    fi
fi

if [[ $RECREATE_DB -eq 0 ]]; then
    sho "Config parameter RECREATE_DB=0. Existing database will be used."
    chown firebird $DB_OVERALL_FILE
    ls -l $DB_OVERALL_FILE 1>>$tmplog
    cat $tmplog
    cat $tmplog>>$joblog
else
    rm -f $DB_OVERALL_FILE
    if [[ -s "$DB_OVERALL_FILE" ]]; then
        sho "Can not remove temporary database $DB_OVERALL_FILE"
        exit 1
    fi

    # NB: do not use embedded access here otherwise DB file will be owned by root rather then firebird:
    echo "create database 'localhost:$DB_OVERALL_FILE' user '$DBA_USER' password '$DBA_PSWD'; alter database set linger to 0; commit; set list on; select * from mon\$database;" > $tmpsql

    run_cmd="$HEAD_FBC/isql -q -i $tmpsql"
    display_intention "Attempt to create database $DB_OVERALL_FILE" "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    catch_err $tmperr "Check whether Firebird is running. Check firebird.log"
    ls -l $DB_OVERALL_FILE 1>>$tmplog
    cat $tmplog
    cat $tmplog>>$joblog
    rm -f $tmpsql $tmplog

    $HEAD_FBC/gfix -w async $DB_OVERALL_FILE -user $DBA_USER

    db_ddl=${this_script_directory}/${this_script_name_only}_DDL.sql
    run_cmd="$HEAD_FBC/isql $dbconn $dbauth -i ${db_ddl}"
    display_intention "Create database objects" "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    catch_err $tmperr "Database objects not created. Check script '${db_ddl}' and error log '${tmperr}'"
    cat $tmplog
    cat $tmplog>>$joblog
fi
# RECREATE_DB = 0 | 1

# fb40_results_storage_fbk=/mnt/hdd/oltp-emul/data/oltp-fb40-results.fbk
# fb50_results_storage_fbk=/mnt/hdd/oltp-emul/data/oltp-fb50-results.fbk
# fb60_results_storage_fbk=/mnt/hdd/oltp-emul/data/oltp-fb60-results.fbk
unset MAJOR_VERSIONS_LST
while read fbk_name; do
    sho "Process fbk_name=$fbk_name"
    if [[ ! -f $fbk_name ]]; then
        sho "Backup file $fbk_name does not exist. Skip iteration."
        continue
    fi
    dbname_only=$(basename $fbk_name)
    dbname_only=${dbname_only%.*} # remove extension ('.fbk')
    oltp_tmp_restored=$(dirname "${fbk_name}")/${dbname_only}.$RANDOM.tmp.fdb
    rm -f $oltp_tmp_restored
    run_cmd="$HEAD_FBC/gbak -c $fbk_name localhost:${oltp_tmp_restored} $dbauth"
    display_intention "Attempt to restore previously saved results" "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    catch_err $tmperr "Restore failed. Check error log."
    cat $tmplog
    cat $tmplog>>$joblog

    # remove all non-digits: 'oltp-fb50.conf.nix' --> '50'; 'oltp-hq40.conf.nix' --> '40' etc
    major_num=${dbname_only//[!0-9]/}

    # remove all non-digit characters from name in order to obtain major version of checked FB:
    # needed by sp_gather_results, see below:
    # es('select o.run_id from all_fb_overall o where o.fb_engine starting with ? ...')(fb_vers_in_source_db)
    fb_vers_in_source_db=${dbname_only//[!0-9]/} # 'oltp-fb40-results' --> '40'
    if [[ "${fb_vers_in_source_db: -1}" == "0" ]]; then
        fb_vers_in_source_db="${fb_vers_in_source_db::-1}" # remove trailing '0' and add '.' --> '4.' etc
    fi
    MAJOR_VERSIONS_LST="${MAJOR_VERSIONS_LST}${fb_vers_in_source_db}x,"
    fb_vers_in_source_db="${fb_vers_in_source_db}." # '4.', '5.' etc

    sho "fb_vers_in_source_db=$fb_vers_in_source_db"

cat <<-EOF >$tmpsql
	set echo on;
	set bail on;
	set heading off;
	-- If RECREATE_DB = 0 then we load ONLY NEW data from source databases:
	-- Otherwise we load ALL data from source databases:
	select msg from sp_gather_results( 'localhost:$oltp_tmp_restored', '$DBA_USER', '$DBA_PSWD', $RECREATE_DB, '$fb_vers_in_source_db' );
	commit;
EOF

    run_cmd="$HEAD_FBC/isql -q $dbconn $dbauth -i $tmpsql -ch utf8"
    display_intention "Gather results from $oltp_tmp_restored" "$run_cmd" "$this_script_log" "$tmperr"
    sho "Content of $tmpsql:"
    bulksho $tmpsql $joblog 1

    ##################################################################################################################
    ###   g a t h e r    d a t a:    $ o l t p _ t m p _ r e s t o r e d   -->   $ D B _ O V E R A L L _ F I L E   ###
    ##################################################################################################################
    # call SP sp_gather_results, see it in oltp_overall_report_DDL.sql:
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    catch_err $tmperr "Probably source and target tables have mismatched DDL."
    rm -f $tmpsql

    # trim all spaces:
    grep . $tmplog | sed 's/ *$//g' >>$joblog
    grep . $tmplog | sed 's/ *$//g'

    run_cmd="$HEAD_FBC/gfix -shut full -force 0 localhost:${oltp_tmp_restored} $dbauth"
    display_intention "Change state of '${oltp_tmp_restored}' to shutdown before removing it." "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    catch_err $tmperr "Could not change DB state to full shutdown."
    sho "Removing file ${oltp_tmp_restored} as no more needed."
    rm -f ${oltp_tmp_restored}

done < <(env | grep "results_storage_fbk" | awk -F "=" '{print $2}' | sort --reverse)

MAJOR_VERSIONS_LST="${MAJOR_VERSIONS_LST::-1}" # 6x,5x,4x

sho "MAJOR_VERSIONS_LST=$MAJOR_VERSIONS_LST"

export MAJOR_VERSIONS_LST=$MAJOR_VERSIONS_LST

export BRAND_MNEMONA=${brand_mnemona} # 'fb' or 'hq'

#------------------------------------------------------------------------

PY_VENV_RUN="source ${PY_VENV_RUN}"
export PY_VENV_RUN
export PYTHON_CALLER_JOBLOG=$joblog
export HEAD_FBC=$HEAD_FBC
export FB_CLNT=$FB_CLNT
export DB_OVERALL_FILE=$DB_OVERALL_FILE
export DBA_USER=$DBA_USER
export DBA_PSWD=$DBA_PSWD
export LOGDIR=$LOGDIR
export DETAILS_DIR=$DETAILS_DIR
export MAX_ROWS_IN_REPORT=$MAX_ROWS_IN_REPORT
export MAX_POINTS_IN_CHART=$MAX_POINTS_IN_CHART

# 19.08.2020:
export DEFAULT_CHART_DIV_WIDTH=$DEFAULT_CHART_DIV_WIDTH
export DEFAULT_CHART_DIV_HEIGHT=$DEFAULT_CHART_DIV_HEIGHT

# 05.10.2020
export DEFAULT_CHART_AREA_LEFT=$DEFAULT_CHART_AREA_LEFT
export DEFAULT_CHART_AREA_TOP=$DEFAULT_CHART_AREA_TOP

# 07.11.2020
export MAIN_RPT_FILE=$MAIN_RPT_FILE

export USE_PREDEFINED_TABLE_HDR=$USE_PREDEFINED_TABLE_HDR

echo PYTHON_HOME=$PYTHON_HOME
echo PY_VENV_RUN=$PY_VENV_RUN
echo PYTHON_BIN=$PYTHON_BIN
#env | sort

###############################
###  c a l l   P y t h o n  ###
###############################
# '-u' ==> unbuffered output of each line
venv_start
run_cmd="${PYTHON_BIN} -u $this_script_directory/${this_script_name_only}.py"
display_intention "Launch Python and generate HTML reports" "$run_cmd" "$this_script_log" "$tmperr"

eval "$run_cmd" 2>$tmperr
venv_stop
catch_err $tmperr "Check errors log."

# If we have launched FB as application then we must KILL it now.
if [[ $fb_app_pid -gt 0 ]]; then
    sho "Application with PID=$fb_app_pid is to be killed: it is no more needed for report."
    kill -9 $fb_app_pid
fi

rm -f $DB_OVERALL_FILE

##########################
### b64 -> zip -> html ###
##########################

broken_b64_cnt=0
broken_zip_cnt=0

b64list=$DETAILS_DIR/*.b64
for b in $b64list
do
    decoded_zip=$(basename $b)
    decoded_zip=$DETAILS_DIR/${decoded_zip%.*}
    run_cmd="base64 --decode $b >$decoded_zip"
    display_intention "Decode data from base64 to results of compression. File: $b" "$run_cmd" "$this_script_log" "$tmperr"

    ####################################################################################
    ###  d e c o d e     f r o m     b a s e 6 4    to    .z i p / .7 z  / .z s t d  ###
    ####################################################################################
    eval "$run_cmd" 1>$tmplog 2>$tmperr

    catch_err $tmperr "Check errors log." 0
    if [[ -s "$tmperr" ]]; then
        broken_b64_cnt=$((broken_b64_cnt+1))
        sho "SKIP extraction because of problems with decoding from base64 format"
        continue
    fi
    
    cat $tmplog
    cat $tmplog>>$joblog
    rm -f $b

    unpacked_html=$(basename $decoded_zip)
    unpacked_html=${unpacked_html%.*}
    compressed_ext="${decoded_zip##*.}"

    html_detl_name=$DETAILS_DIR/${unpacked_html}.html

    if [[ $html_detl_name == *"crash"* ]]; then
        # DO NOT delete this file, it is preliminary created HTML with heading info about crash
        # We have to APPEND stack trace text to this file rather than to overwrite it.
        echo "<pre>" >>$html_detl_name
    else
        rm -f $html_detl_name
    fi

    if [[ "$compressed_ext" == "zip" ]]; then
       # ### ACHTUNG ###
       # Value of $DECOMPRESS_ZIP must be always equal to $DECOMPRESS_7Z and is 7za utility.
       # DO NOT use '-tzip' as command switch for 7za when extract files that were compressed
       # by /usr/bin/gzip: this leads to "Open ERROR: Can not open the file as [zip] archive"
       # Fortunately, 7-Zip can properly detect type of archieve without any hints (when extracts)
       extract_cmd="$DECOMPRESS_ZIP e -so $decoded_zip >> $html_detl_name"
    elif [[ "$compressed_ext" == "7z" ]]; then
       extract_cmd="$DECOMPRESS_7Z e -so $decoded_zip >> $html_detl_name"
    elif [[ "$compressed_ext" == "zstd" || "$compressed_ext" == "zst"  ]]; then
       extract_cmd="$DECOMPRESS_ZST -d $decoded_zip -c >> $html_detl_name"
    fi
    display_intention "Decompress html content" "$extract_cmd" "$this_script_log" "$tmperr"
    ###################################################################################
    ###  d e c o m p r e s s    a n d    w r i t e    t o    . h t m l   f i l e    ###
    ###################################################################################
    eval "$extract_cmd" 1>$tmplog 2>$tmperr
    if [[ $? -ne 0 ]]; then
        broken_zip_cnt=$((broken_zip_cnt+1))
        sho "WARNING: could not extract data from $decoded_zip and/or save it to $html_detl_name"
        cat $tmperr
        cat $tmperr>>$joblog
    else
        sho "Completed OK."
        rm -f $decoded_zip
    fi

    if [[ $html_detl_name == *"crash"* ]]; then
	cat <<- EOF ->>$html_detl_name
		</pre>
		</body>
		</html>
	EOF
    fi

    rm -f $tmplog $tmperr

done

if [[ $broken_b64_cnt -eq 0 ]]; then
    sho "All files in base64 format have been decoded successfully."
else
    sho "### ACHTUNG ### Total files that could not be decoded from base-64: $broken_b64_cnt"
fi

if [[ $broken_zip_cnt -eq 0 ]]; then
    sho "All decoded files have been decompressed successfully."
else
    sho "### ACHTUNG ### Total files that could not be decompressed: $broken_zip_cnt"
fi

#####################################################################
###   c o m p r e s s     a n d    u p l o a d      r e p o r t   ###
#####################################################################

if [[ $can_upload -eq 1 ]]; then

    compressed_name_only=${this_script_name_only}.$(date +'%Y%m%d%H%M%S').7z
    compressed_report=${LOGDIR}/${compressed_name_only}
    cd ${LOGDIR}
    echo current folder: $(pwd)
    run_cmd="${P7ZCMD} a -mx9 -mfb273 -ssw -r ./${compressed_name_only} ./${this_script_name_only}.html ./${this_script_name_only}.css ./$(basename $DETAILS_DIR)"
    display_intention "Compress report before uploading" "$run_cmd" "$this_script_log" "$tmperr"

    eval "$run_cmd" 1>/dev/null 2>$tmperr
    retcode=$?
    cd ${this_script_directory}
    if [[ $retcode -ne 0 ]]; then
        sho "ERROR detected while compressing files to $compressed_report."
        cat $tmperr
        cat $tmperr>>$joblog
        exit 1
    fi

    run_cmd="${P7ZCMD} l -ba $compressed_report" # '-ba' -- non documente feature: show only file names, w/o any other info.
    display_intention "Obtain list of files stored in the compressed report. Check that '$(basename $DETAILS_DIR)' folder exists" "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    catch_err $tmperr "Compressed file seems broken."
    cat $tmplog
    cat $tmplog>>$joblog
    rm -f $tmplog $tmperr

    # scp -o StrictHostKeyChecking=no -- to avoid question "Are you sure you want to continue connecting (yes/no)"
    run_cmd="scp -o StrictHostKeyChecking=no -v -i $SSH_PRIVATE_KEY_FILE $compressed_report $SSH_UPLOAD_HOST_DATA:$SSH_RESULTS_HOME_DIR"
    display_intention "Uploading compressed file" "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 2>$tmperr
    if [[ $? -ne 0 ]]; then
        sho "ERROR: could not upload compressed file $compressed_report."
        cat $tmperr
        cat $tmperr>>$joblog
        rm -f $tmperr
        exit 1
    else
        sho "Success. $(grep -i -m1 "exit status" $tmperr)"
    fi
    rm -f $compressed_report $tmperr

    #ssh -i $SSH_PRIVATE_KEY_FILE $SSH_UPLOAD_HOST_DATA '/opt/scripts/update-oltp-emul-report.sh $SSH_RESULTS_HOME_DIR/$compressed_name_only;exit;'"

    run_cmd="ssh -i $SSH_PRIVATE_KEY_FILE $SSH_UPLOAD_HOST_DATA '/opt/scripts/update-oltp-emul-report.sh $SSH_RESULTS_HOME_DIR/$compressed_name_only ${brand_mnemona};exit;'"
    display_intention "Remote call to decompress report" "$run_cmd" "$this_script_log" "$tmperr"
    eval "$run_cmd" 2>$tmperr
    if [[ $? -ne 0 ]]; then
        sho "WARNING. Remote decompression FAILED."
        cat $tmperr
        cat $tmperr>>$joblog
    else
        sho "Success."
    fi
    rm -f $tmplog $tmperr
else
    sho "Upload DISABLED or impossible."
fi
rm -f $tmplst
sho "Completed script $this_script_full_name"
exit
