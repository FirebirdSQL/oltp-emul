#!/bin/bash

function pause(){
   read -p "$*"
}

sho() {
  local msg=$1
  local dts=$(date +'%d.%m.%y %H:%M:%S')
  echo $dts. $msg
  echo $dts. $msg>>$log4all
}

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

msg_nocfg() {
  echo
  echo Config file \'$1\' either not found or is empty.
  echo
  echo Script is now terminated.
  exit 1
}

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
    rm -f $tmperr
  fi
}

msg_novar() {
  echo
  echo -e "##########################################################"
  echo -e At least one variable: \>\>\>$1\<\<\< - is NOT defined.
  echo Check config file $cfg.
  echo -e "##########################################################"
  echo
  echo Script is now terminated.
}

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

###########################  m a i n    p a r t   #############################

# this file must be allowed to create on any POSIX:
abendlog=/var/tmp/oltp_overall_report.abend.err
rm -f $abendlog

this_script_directory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

cd ${this_script_directory}
this_script_full_name=${BASH_SOURCE[0]}
this_script_name_only=$(basename $this_script_full_name)
this_script_name_only=${this_script_name_only%.*}

while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        # | sed -e 's/^[ \t]*//'
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
        if [[ "$rhs" = "${rhs%[[:space:]]*}" ]] ; then
            #echo Try: declare $lhs=$rhs
            declare $lhs=$rhs
        else
            #echo Try: declare $lhs="$rhs"
            # We have to enclose declaration into double quotes
            # if some parameter contains space, e.g.:
            # mail_to = somename1@company.com somename2@company.com
            declare $lhs="$rhs"
        fi
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
done<${this_script_full_name%*.*}_config.nix

#  time echo $txt | $mail_cmd $mail_attach_file_cmd_sw "$this_script_log" $mail_subject_cmd_sw "$msg" $mail_to_address_cmd_sw $mail_to 

dts=$(date +'%Y%m%d_%H%M%S')

# Remove trailing slash from variables which store PATHs:
fbc=${HEAD_FBC%/}
LOGDIR=${LOGDIR%/}
DETAILS_DIR=${DETAILS_DIR%/}

mkdir -p $LOGDIR && touch $LOGDIR/tmp.tmp && rm $LOGDIR/tmp.tmp
if [ $? -eq 0 ]; then
    echo "Successfully created / accessed LOGDIR=$LOGDIR"
else
    msg="Could NOT create / access LOGDIR=$LOGDIR"
    echo $msg
    echo $msg > $abendlog
    exit 1
fi

this_script_log=$LOGDIR/${this_script_name_only}.$dts.log
this_script_lst=$LOGDIR/${this_script_name_only}.lst
this_script_sql=$LOGDIR/${this_script_name_only}.sql
this_script_tmp=$LOGDIR/${this_script_name_only}.tmp
this_script_err=$LOGDIR/${this_script_name_only}.err

log4all=$this_script_log

sho "Intro $this_script_full_name. Current dir: $(pwd)"

####################################################
###    p a r s e     o l t p 4 0 _ c o n f i g   ###
####################################################
sho "Start parsing config $oltp40_config"
awk '$1=$1' $oltp40_config | grep "^[^#]" | grep -i -E "dbnm[[:space:]]?=|usr[[:space:]]?=|pwd[[:space:]]?=|fbc[[:space:]]?=|mon_unit_perf[[:space:]]?=|results_storage_fbk[[:space:]]?=" > $this_script_tmp

while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
        if [[ "${lhs^^}" == "USR" ]]; then
            lhs=DBA_USER
        elif [[ "${lhs^^}" == "PWD" ]]; then
            lhs=DBA_PSWD
        elif [[ "${lhs^^}" == "FBC" ]]; then
	    # folder with most recent version of FB (will be used for DB_OVERALL).
	    # All .fbk will be restored using this version.
            lhs=HEAD_FBC
        elif [[ "${lhs^^}" == "MON_UNIT_PERF" ]]; then
            lhs=o40_mon_perf
        elif [[ "${lhs^^}" == "RESULTS_STORAGE_FBK" ]]; then
            lhs=FB4X_FBK
        fi
        declare $lhs=$rhs
        if [ $? -gt 0 ]; then
          msg="+++ ACHTUNG +++ SOMETHING WRONG IN YOUR CONFIG FILE"
          echo $msg
          echo $dts. $msg >> $abendlog
          exit 1
        fi
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")>>$abendlog
    fi
### 07.11.2020 DOES NOT WORK WHEN RUN FROM CRON!!! >>> done < <( awk '$1=$1' $oltp40_config | grep "^[^#]" | grep -i -E "usr[[:space:]]?=|pwd[[:space:]]?=|fbc[[:space:]]?=|mon_unit_perf[[:space:]]?=|results_storage_fbk[[:space:]]?="  )
done<$this_script_tmp 

sho "Finished parsing config $oltp40_config"

############################################

if [[ -z "FB4X_FBK" ]]; then
    sho "Parameter 'results_storage_fbk' must be defined in OLTP-EMUL config file '${oltp40_config}'"
    exit 1
fi

# client library that must be used for connect:
FB_CLNT=$(dirname "$HEAD_FBC")/lib/libfbclient.so.2

if [[ -n "${HEAD_FBC}/isql" && -n ${FB_CLNT} ]]; then
    : # Parameter 'fbc' from '${oltp40_config}' points to existing binaries
else
    sho "Parameter 'fbc' from '${oltp40_config}' points to NON existing binaries."
    exit 1
fi

####################################################
###    p a r s e     o l t p 3 0 _ c o n f i g   ###
####################################################

sho "Start parsing config $oltp30_config"

awk '$1=$1' $oltp30_config | grep "^[^#]" | grep -i -E "dbnm[[:space:]]?=|mon_unit_perf[[:space:]]?=|results_storage_fbk[[:space:]]?=">$this_script_tmp
while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
        if [[ "${lhs^^}" == "MON_UNIT_PERF" ]]; then
            lhs=o30_mon_perf
        elif [[ "${lhs^^}" == "RESULTS_STORAGE_FBK" ]]; then
            lhs=FB3X_FBK
        fi
        declare $lhs=$rhs
        if [ $? -gt 0 ]; then
          msg="+++ ACHTUNG +++ SOMETHING WRONG IN YOUR CONFIG FILE"
          echo $msg
          echo $dts. $msg >> $abendlog
          exit 1
          exit
        fi
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
done<$this_script_tmp

sho "Finished parsing config $oltp30_config"

if [[ -z "FB3X_FBK" ]]; then
    sho "Parameter 'results_storage_fbk' must be defined in OLTP-EMUL config file '${oltp30_config}'"
    exit 1
fi

if [[ ${o30_mon_perf} -ne 2 ]]; then
    sho "WARNING. Config parameter 'mon_unit_perf' in $oltp30_config has value $o30_mon_perf. Report can miss data about memory consumption for runs on FB 3.x."
fi
if [[ ${o40_mon_perf} -ne 2 ]]; then
    sho "WARNING. Config parameter 'mon_unit_perf' in $oltp40_config has value $o40_mon_perf. Report can miss data about memory consumption for runs on FB 4.x."
fi

# Dir where .fbk and DB with overall results are stored:
DB_OVERALL_DIR=$(dirname "${FB4X_FBK}")

# Database that will be used to store overall report data:
DB_OVERALL_FILE=${DB_OVERALL_DIR}/${this_script_name_only}.tmp.fdb

can_upload=$SSH_UPLOAD_ENABLED # from .conf
if [[ $can_upload -eq 1 ]]; then

    tmpfile=$SSH_RESULTS_HOME_DIR/tmp_check_access.tmp
    run_cmd="ssh -i $SSH_PRIVATE_KEY_FILE $SSH_UPLOAD_HOST_DATA 'hostname; touch $tmpfile;  ls --full-time $tmpfile; rm -f $tmpfile; exit;'"
    display_intention "Check access to $SSH_RESULTS_HOME_DIR folder on $SSH_UPLOAD_HOST_DATA" "$run_cmd" "$this_script_log" "$this_script_err"
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
    retcode=$?
    if [[ -s "$this_script_err" ]]; then
        sho "ERROR detected while checking access to $SSH_RESULTS_HOME_DIR folder using $SSH_UPLOAD_HOST_DATA"
        cat $this_script_err
        cat $this_script_err>>$log4all
        sho "Report will not be uploaded."
        can_upload=0
    else
        sho "SUCCESS. Remote host allows to operate with folder $SSH_RESULTS_HOME_DIR using $SSH_UPLOAD_HOST_DATA"
        cat $this_script_tmp
    fi
fi
rm -f $this_script_tmp $this_script_err

dbauth="-user $DBA_USER -pas $DBA_PSWD"
dbconn="localhost:$DB_OVERALL_FILE"

mkdir -p $DETAILS_DIR && touch $DETAILS_DIR/tmp.tmp && rm $DETAILS_DIR/tmp.tmp
if [ $? -eq 0 ]; then
  sho "Successfully created / accessed DETAILS_DIR '$DETAILS_DIR'"
else
  echo Could NOT create / access DETAILS_DIR '$DETAILS_DIR'
  exit 1
fi

sho "Remove logs of this script with age more than $LOGS_MAX_AGE days."

find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.log" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.err" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.tmp" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.lst" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $LOGDIR -type f -name "${this_script_name_only%*.*}.*.sql" -mtime +${LOGS_MAX_AGE} -exec rm {} \;

find $DETAILS_DIR -type f -name "*.htm" -mtime +${LOGS_MAX_AGE} -exec rm {} \;
find $DETAILS_DIR -type f -name "*.html" -mtime +${LOGS_MAX_AGE} -exec rm {} \;

run_cmd="$HEAD_FBC/fbsvcmgr localhost:service_mgr user $DBA_USER password $DBA_PSWD info_server_version"
fb_app_pid=0
display_intention "Attempt to get SERVER version in $HEAD_FBC folder" "$run_cmd" "$this_script_log" "$this_script_err"
eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err

cat $this_script_tmp
cat $this_script_tmp>>$log4all

if grep -q -i "Failed to establish a connection" $this_script_err ; then
    cat $this_script_err
    cat $this_script_err>>$log4all
    sho "Server that is specified by 'HEAD_FBC' parameter not running."
    sho "We make attempt to launch it as application."
    $HEAD_FBC/firebird &
    fb_app_pid=$!

    # ::: NB ::: DO NOT REMOVE THIS DELAY :::
    # Otherwise firebird process can be completely loaded under high concurrent workload
    # and we get SECOND error when try to obtain server version!
    sleep 5

    set -x
    ps aux | grep $HEAD_FBC/firebird | grep -v grep >$this_script_tmp
    set +x
    cat $this_script_tmp
    cat $this_script_tmp >>$log4all
    if [[ $fb_app_pid -gt 0 ]]; then
        display_intention "Attempt to get SERVER version for PID=$fb_app_pid" "$run_cmd" "$this_script_log" "$this_script_err"
        eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
        catch_err $this_script_err "Server seems not running."
        cat $this_script_tmp
        cat $this_script_tmp >>$log4all
    else
        sho "Firebird could not be launched as application. Script terminated."
        exit 1
    fi
else
    catch_err $this_script_err "Server was not started for unknown reason."
fi

rm -f $DETAILS_DIR/*.html

if [[ $RECREATE_DB -eq 0 ]]; then
    if [[ -f "$DB_OVERALL_FILE" ]]; then
        ls -l $DB_OVERALL_FILE 1>$this_script_tmp
        cat $this_script_tmp
        cat $this_script_tmp >>$log4all
        run_cmd="$HEAD_FBC/gstat -h $DB_OVERALL_FILE -user $DBA_USER -pas $DBA_PSWD"
        display_intention "DB with overall data does exist. Attempt to check its header" "$run_cmd" "$this_script_log" "$this_script_err"
        eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
        if [[ $? -ne 0 ]]; then
            cat $this_script_err
            cat $this_script_err >>$log4all
            sho "Database $DB_OVERALL_FILE seems to be invalid or has old ODS. We have to RECREATE it."
            RECREATE_DB=1
        fi

        if [[ $RECREATE_DB -eq 0 ]]; then
            echo "set list on; set bail on; select info from ddl_outcome;" > $this_script_sql
            run_cmd="$HEAD_FBC/isql $dbconn $dbauth -q -i $this_script_sql"
            display_intention "Attempt to get info about DDL completition." "$run_cmd" "$this_script_log" "$this_script_err"
            # ::: NB :::
            # isql can return retcode=0 when DB is corrupted! We have to ensure that size of STDERR is zero.
            eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
            if [[ $? -ne 0 || -s "$this_script_err"  ]]; then
                cat $this_script_err
                cat $this_script_err >>$log4all
                sho "Database $DB_OVERALL_FILE does not contain info about DDL completition. We have to RECREATE it."
                RECREATE_DB=1
            else
                cat $this_script_tmp
                grep . $this_script_tmp | sed 's/ *$//g' >>$log4all
            fi
            rm -f $this_script_tmp $this_script_sql $this_script_err
        fi

    else
        sho "Database $DB_OVERALL_FILE does not exist. We have to RECREATE it."
        RECREATE_DB=1
    fi
fi

if [[ $RECREATE_DB -eq 0 ]]; then
    sho "Config parameter RECREATE_DB=0. Existing database will be used."
    chown firebird $DB_OVERALL_FILE
    ls -l $DB_OVERALL_FILE 1>>$this_script_tmp
    cat $this_script_tmp
    cat $this_script_tmp>>$log4all
else
    rm -f $DB_OVERALL_FILE
    if [[ -s "$DB_OVERALL_FILE" ]]; then
        sho "Can not remove temporary database $DB_OVERALL_FILE"
        exit 1
    fi
    
    # NB: do not use embedded access here otherwise DB file will be owned by root rather then firebird:
    echo "create database 'localhost:$DB_OVERALL_FILE' user '$DBA_USER' password '$DBA_PSWD'; alter database set linger to 0; commit; set list on; select * from mon\$database;" > $this_script_sql

    run_cmd="$HEAD_FBC/isql -q -i $this_script_sql"
    display_intention "Attempt to create database" "$run_cmd" "$this_script_log" "$this_script_err"
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
    catch_err $this_script_err "Check whether Firebird is running. Check firebird.log"
    ls -l $DB_OVERALL_FILE 1>>$this_script_tmp
    cat $this_script_tmp
    cat $this_script_tmp>>$log4all
    rm -f $this_script_sql $this_script_tmp

    $HEAD_FBC/gfix -w async $DB_OVERALL_FILE -user $DBA_USER

    db_ddl=${this_script_directory}/${this_script_name_only}_DDL.sql
    run_cmd="$HEAD_FBC/isql $dbconn $dbauth -i ${db_ddl}"
    display_intention "Create database objects" "$run_cmd" "$this_script_log" "$this_script_err"
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
    catch_err $this_script_err "Database objects not created. Check script '${db_ddl}' and error log '${this_script_err}'"
    cat $this_script_tmp
    cat $this_script_tmp>>$log4all
fi
# RECREATE_DB = 0 | 1

#------------------------------------------------------------------------

dbarr=($FB4X_FBK $FB3X_FBK)

for fbk_name in "${dbarr[@]}"
do
    dbname_only=$(basename $fbk_name)
    dbname_only=${dbname_only%.*}
    oltp_tmp_restored=$(dirname "${fbk_name}")/${dbname_only}.$RANDOM.tmp.fdb

    if [[ ! -f $fbk_name ]]; then
        sho "Backup file $fbk_name does not exist. Skip iteration."
        continue
    fi
    
    run_cmd="$HEAD_FBC/gbak -rep $fbk_name localhost:${oltp_tmp_restored} $dbauth"
    display_intention "Attempt to restore previously saved results" "$run_cmd" "$this_script_log" "$this_script_err"
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
    catch_err $this_script_err "Restore failed. Check error log."
    cat $this_script_tmp
    cat $this_script_tmp>>$log4all

    fb_vers_in_source_db=UNKNOWN_SOURCE
    if [ "$fbk_name" == "$FB4X_FBK" ]; then
        fb_vers_in_source_db=4.
    elif [ "$fbk_name" == "$FB3X_FBK" ]; then
        fb_vers_in_source_db=3.
    fi

	cat <<-EOF >$this_script_sql
	set echo on;
	set bail on;
	set heading off;
	-- If RECREATE_DB = 0 then we load ONLY NEW data from source databases:
	-- Otherwise we load ALL data from source databases:
	select msg from sp_gather_results( 'localhost:$oltp_tmp_restored', '$DBA_USER', '$DBA_PSWD', $RECREATE_DB, '$fb_vers_in_source_db' );
	commit;
	EOF

    run_cmd="$HEAD_FBC/isql -q $dbconn $dbauth -i $this_script_sql -ch utf8"
    display_intention "Gather results from $oltp_tmp_restored" "$run_cmd" "$this_script_log" "$this_script_err"


    ################################################################################################################
    ###   g a t h e r    r e s u l t s    f r o m    $ f b k _ n a m e    to   $ D B _ O V E R A L L _ F I L E   ###
    ################################################################################################################
    # call SP sp_gather_results, see it in oltp_overall_report_DDL.sql:
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
    catch_err $this_script_err "Probably source and target tables have mismatched DDL."
    rm -f $this_script_sql

    # trim all spaces:
    grep . $this_script_tmp | sed 's/ *$//g' >>$log4all
    grep . $this_script_tmp | sed 's/ *$//g'


    run_cmd="$HEAD_FBC/gfix -shut full -force 0 localhost:$oltp_tmp_restored $dbauth"
    display_intention "Change temporary DB state to full shutdown in order to remove it" "$run_cmd" "$this_script_log" "$this_script_err"
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
    catch_err $this_script_err "Could not change DB state to full shutdown. Check error log."

    rm -f $oltp_tmp_restored
    rm -f $this_script_tmp


done

export PYTHON_CALLER_JOBLOG=$log4all
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
###export MAIN_CSS_FILE=$MAIN_CSS_FILE

###############################
###  c a l l   P y t h o n  ###
###############################

run_cmd="${PYTHON_BINARY} $this_script_directory/${this_script_name_only}.py"
display_intention "Launch Python and generate HTML reports" "$run_cmd" "$this_script_log" "$this_script_err"
eval "$run_cmd" 2>$this_script_err
catch_err $this_script_err "Check errors log."

# If we have launched FB as application then we must KILL it now.
if [[ $fb_app_pid -gt 0 ]]; then
    sho "Application with PID=$fb_app_pid is to be killed: it is no more needed for report."
    kill -9 $fb_app_pid
fi

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
    display_intention "Decode data from base64 to results of compression. File: $b" "$run_cmd" "$this_script_log" "$this_script_err"

    ####################################################################################
    ###  d e c o d e     f r o m     b a s e 6 4    to    .z i p / .7 z  / .z s t d  ###
    ####################################################################################
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err

    catch_err $this_script_err "Check errors log." 0
    if [[ -s "$tmperr" ]]; then
        broken_b64_cnt=$((broken_b64_cnt+1))
        sho "SKIP extraction because of problems with decoding from base64 format"
        continue
    fi
    
    cat $this_script_tmp
    cat $this_script_tmp>>$log4all
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
    display_intention "Decompress html content" "$extract_cmd" "$this_script_log" "$this_script_err"
    ###################################################################################
    ###  d e c o m p r e s s    a n d    w r i t e    t o    . h t m l   f i l e    ###
    ###################################################################################
    eval "$extract_cmd" 1>$this_script_tmp 2>$this_script_err
    if [[ $? -ne 0 ]]; then
        broken_zip_cnt=$((broken_zip_cnt+1))
        sho "WARNING: could not extract data from $decoded_zip and/or save it to $html_detl_name"
        cat $this_script_err
        cat $this_script_err>>$log4all
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

    rm -f $this_script_tmp $this_script_err

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
    run_cmd="${P7ZCMD} a -mx9 -mfb273 -ssw -r ./${compressed_name_only} ./oltp-overall-main.html ./oltp-overall-main.css ./$(basename $DETAILS_DIR)"
    display_intention "Compress report before uploading" "$run_cmd" "$this_script_log" "$this_script_err"

    eval "$run_cmd" 1>/dev/null 2>$this_script_err
    retcode=$?
    cd ${this_script_directory}
    if [[ $retcode -ne 0 ]]; then
        sho "ERROR detected while compressing files to $compressed_report."
        cat $this_script_err
        cat $this_script_err>>$log4all
        exit 1
    fi

    run_cmd="${P7ZCMD} l $compressed_report"
    display_intention "Obtain list of files stored in the compressed report. Check that '$(basename $DETAILS_DIR)' folder exists" "$run_cmd" "$this_script_log" "$this_script_err"
    eval "$run_cmd" 1>$this_script_tmp 2>$this_script_err
    catch_err $this_script_err "Compressed file seems broken."
    cat $this_script_tmp
    cat $this_script_tmp>>$log4all
    rm -f $this_script_tmp $this_script_err

    # scp -o StrictHostKeyChecking=no -- to avoid question "Are you sure you want to continue connecting (yes/no)"
    run_cmd="scp -o StrictHostKeyChecking=no -v -i $SSH_PRIVATE_KEY_FILE $compressed_report $SSH_UPLOAD_HOST_DATA:$SSH_RESULTS_HOME_DIR"
    display_intention "Uploading compressed file" "$run_cmd" "$this_script_log" "$this_script_err"
    eval "$run_cmd" 2>$this_script_err
    if [[ $? -ne 0 ]]; then
        sho "ERROR: could not upload compressed file $compressed_report."
        cat $this_script_err
        cat $this_script_err>>$log4all
        rm -f $this_script_err
        exit 1
    else
        sho "Success. $(grep -i -m1 "exit status" $this_script_err)"
    fi
    rm -f $compressed_report $this_script_err

    #ssh -i $SSH_PRIVATE_KEY_FILE $SSH_UPLOAD_HOST_DATA '/opt/scripts/update-oltp-emul-report.sh $SSH_RESULTS_HOME_DIR/$compressed_name_only;exit;'"

    run_cmd="ssh -i $SSH_PRIVATE_KEY_FILE $SSH_UPLOAD_HOST_DATA '/opt/scripts/update-oltp-emul-report.sh $SSH_RESULTS_HOME_DIR/$compressed_name_only;exit;'"
    display_intention "Remote call to decompress report" "$run_cmd" "$this_script_log" "$this_script_err"
    
    eval "$run_cmd" 2>$this_script_err
    if [[ $? -ne 0 ]]; then
        sho "WARNING. Remote decompression FAILED."
        cat $this_script_err
        cat $this_script_err>>$log4all
    else
        sho "Success."
    fi
    rm -f $this_script_tmp $this_script_err
else
    sho "Upload DISABLED or impossible."
fi

sho "Completed script $this_script_full_name"
exit
