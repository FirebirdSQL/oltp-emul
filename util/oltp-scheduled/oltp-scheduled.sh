#!/bin/bash

function pause(){
   read -p "$*"
}
#.............................................

sho() {
  local msg=$1
  local joblog=$2
  local dts=$(date +'%d.%m.%y %H:%M:%S')
  echo $dts. "${msg}"
  echo $dts. "${msg}" >> $joblog
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

catch_err() {
  local joblog=$1
  local tmperr=$2
  local addnfo=${3:-""}
  local quit_if_error=${4:-1}

  # Example:
  # catch_err $joblog $tmperr "${msg_abend}" 0

  if [[ -s $tmperr ]]; then
    sho "FAIL DETECTED. Error log $tmperr is NOT EMPTY." $joblog
    echo ...............................
    cat $tmperr | sed -e 's/^/    /'
    cat $tmperr | sed -e 's/^/    /' >>$joblog
    echo ...............................
    if [[ ! -z "$addnfo" ]]; then
        echo
        echo Additional info / advice:
        echo ${addnfo}
        echo ${addnfo} >>$joblog
        echo
    fi

    if [[ $quit_if_error -eq 1 ]]; then
        sho "Script is terminated." $joblog

        exit 1

    fi
  else
    sho "Result: no errors." $joblog
  fi

}
# end of func 'catch_err'

#.............................................

show_syntax() {
  clear
  local this_abend_name=$1
  rm -f this_abend_name
cat <<-EOF >$this_abend_name
Syntax:

$0  <mnemona>  <sessions_count>  <server_mode>  [ <update_FB_instance> ]

where:
    <mnemona> = fb<nn>|hq<nn> - mnemonic for brand and major version, case insensitive:
        fb - for vanilla Firebird;
        hq - for HQbird fork;
        <nn> = 30 | 40 | 50 | 60
        examples: fb40; fb50; fb60; hq30; hq40; hq50.
    <workers_count> = number of ISQL sessions to launch
    <server_mode> = CS | SC | SS  -  required mode, case-insensitive
    <update_FB_instance> = should we upgrade FB instance before test ? Default: 1.
        If 1 then every run of this script will check new FB snapshot on official site
             and replace existing instance if need (with apropriate .debug package).
        If 0 then existing FB instance will not be replaced.
        NOTE: value of ServerMode in firebird.conf is always changed with required value.

Example:

    $0  fb60  100  ss
    $0  hq50  100  ss

        * run test on FB 6.x,
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
  local joblog=$1
  local tmperr=$2
  local addnfo=${3:-""}
  local quit_if_error=${4:-1}

  # Example:
  # catch_err $joblog $tmperr "${msg_abend}" 0

  if [[ -s $tmperr ]]; then
    sho "FAIL DETECTED. Error log $tmperr is NOT EMPTY." $joblog
    echo ...............................
    cat $tmperr | sed -e 's/^/    /'
    cat $tmperr | sed -e 's/^/    /' >>$joblog
    echo ...............................
    if [[ ! -z "$addnfo" ]]; then
        echo
        echo Additional info / advice:
        echo ${addnfo}
        echo ${addnfo} >>$joblog
        echo
    fi

    if [[ $quit_if_error -eq 1 ]]; then
        sho "Script is terminated." $joblog

        exit 1

    fi
  else
    sho "Result: no errors." $joblog
  fi

}
# end of func 'catch_err'

#.............................................

msg_novar() {
  local cfgfile=$1
  local undefvar=$2
cat <<-EOF

	##########################################################
	At least one variable: ${undefvar} - is NOT defined.
	Check config file $cfgfile
	##########################################################
	Script terminated.

EOF
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
    local tmpsql=$2
    local tmplog=$3
    local tmperr=$4
    local joblog=$5

    local fb_snapshot_version # LI-V3.0.6.33289 etc
    local fb_installed_stamp

    fb_snapshot_version=$(echo "quit;" | $fbc/isql -q -z | awk '{print $3}')
    fb_installed_stamp=$(date +'%d.%m.%Y %H:%M:%S')

    sho "Attempt to add/update SYSDBA user." $joblog

    rm -f $tmpsql
cat <<- EOF >$tmpsql
	    set list on;
	    set count on;
	    set bail on;
	    set echo on;
	    create or alter user sysdba password '${new_password}' firstname '$fb_snapshot_version' lastname '$fb_installed_stamp' using plugin Srp;
	    commit;
	    select sec\$user_name,sec\$first_name,sec\$last_name,sec\$admin,sec\$plugin
	    from sec\$users
	    where upper(trim(sec\$user_name)) = upper('sysdba')
	    ;
EOF

    set -x
    $fbc/isql security.db -user sysdba -i $tmpsql 1>$tmplog 2>$tmperr
    set +x
    rm -f $tmpsql

    cat $tmplog
    cat $tmplog>>$joblog
    if [[ -s $tmperr ]]; then
        cat $tmperr
        cat $tmperr >>$joblog
        sho "ACHTUNG. Attempt to add/update SYSDBA user failed. Job terminated." $joblog
        exit
    else
        sho "Success." $joblog
    fi
    rm -f $tmplog $tmperr

}
#.............................................

check_for_sleep_UDF() {
    local dir_to_install_fb=$1
    local fb_cfg_for_work=$2
    local tmplog=$3
    local joblog=$4

    local run_cmd

    # Check whether oltp-emul config parameter 'sleep_ddl' points to 'default' UDF that is provided with test.
    # If yes then we have to make dir 'UDF' in FB_HOME and unpack there ./util/udf64/SleepUDF.so.tar.gz
    if grep -i -q "UdfAccess" $fb_cfg_for_work ; then

        # $sleep_ddl - parameter from oltpNN_config.
        # It must be name of SQL script which declares UDF to make delays.
        # This .sql file must be specified relatively to ${OLTP_ROOT}/src/ folder
        # This UDF is always needed when oltp-emul config parameter 'mon_unit_perf' is 2.
        # Also it is needed when parameters 'sleep_max' greater than 0 and 'sleep_ddl'
        # is uncommented and points to the script which declares this UDF.

        if [[ "${sleep_ddl}" == "./oltp_sleepUDF_nix.sql" ]]; then
            sho "Test requires UDF for make delays." $joblog
            # NB: firebird.conf already *contains* line UdfAccess = Restrict UDF - see creating of $fb_cfg_for_work at the start of main part.
            cd ${this_script_directory}

            # this can RELATIVE path, e.g.: ../..
            #cd ${OLTP_ROOT_DIR}
            cd ${OLTP_SRC_DIR}
            
            sho "Current directory: $PWD" $joblog
            if grep -i -E -q "entry_point[[:space:]]+'SleepUDF'[[:space:]]+module_name[[:space:]]+'SleepUDF'" ${sleep_ddl} ; then
                [[ -d "$dir_to_install_fb/UDF" ]] || mkdir $dir_to_install_fb/UDF

                COMPRESSED_OLTP_UDF=../util/udf64/SleepUDF.so.tar.gz
                sho "Extracting UDF binary provided with test package. Current dir: ${PWD}" $joblog
                if [[ -s $COMPRESSED_OLTP_UDF ]]; then
                    run_cmd="tar xvf ${COMPRESSED_OLTP_UDF} -C $dir_to_install_fb/UDF"
                else
                    sho "Compressed UDF $COMPRESSED_OLTP_UDF does not exist. Using alternate name for this file:" $joblog
                    COMPRESSED_OLTP_UDF=../util/udf64/SleepUDF.so.bz2
                    sho "$COMPRESSED_OLTP_UDF." $joblog
                    run_cmd="bzip2 --decompress --keep --force --stdout ${COMPRESSED_OLTP_UDF} 1>$dir_to_install_fb/UDF/SleepUDF.so"
                fi
                sho "Compressed file: ${COMPRESSED_OLTP_UDF}" $joblog
                sho "Command: $run_cmd" $joblog
                eval $run_cmd 1>$tmplog 2>&1
                if [[ $? -eq 0 ]]; then
                    sho "Success. Size of extracted binary $dir_to_install_fb/UDF/SleepUDF.so: $(stat -c%s $dir_to_install_fb/UDF/SleepUDF.so)" $joblog
                    #############################################
                    # Check actual type of UDF library:
                    # ELF 64-bit LSB shared object, x86-64, ... dynamically linked, BuildID[sha1]=..., not stripped
                    file $dir_to_install_fb/UDF/SleepUDF.so >$tmplog
                    #############################################
                    cat $tmplog
                    cat $tmplog >>$joblog
                    rm -f $tmplog
                else
                    sho "ACHTUNG. UDF binary could not be extracted. Job terminated." $joblog
                    cat $tmplog
                    cat $tmplog >>$joblog
                    rm -f $tmplog
                    exit
                fi
            else
                sho "Config of OLTP-EMUL test contains script thats point to 3rd-party UDF" $joblog
            fi
            cd ${this_script_directory}
            # dis 04.09.2025 chown firebird:root -R $dir_to_install_fb/UDF
            sho "Completed preparing steps for UDF usage. Check UDF folder:" $joblog
            ls -l $dir_to_install_fb/UDF
            ls -l $dir_to_install_fb/UDF >>$joblog
        else
            if [[ -z "${sleep_ddl}" ]]; then
                sho "Test does not require UDF usage, skip from extracting UDF binary." $joblog
            else
                sho "Test requires UDF usage but config '$oltp_emul_conf_name' points to 3-rd party DDL." $joblog
                sho "It is impossible to execute test in such case on scheduled basis. Job terminated." $joblog
                exit
            fi
        fi
    fi

}
# end of check_for_sleep_UDF
#.............................................

check_port() {
    local port=$1
    local fbc=$2
    local tmplog=$3
    local joblog=$4
    sho "Check whether port $port is listening by FB process." $joblog

    # NB: this delay needed because FB service can launch not instantly on slow hosts!
    sleep 2

    netstat --tcp --udp --listening --program --numeric | grep $port | grep -i "firebird\|fb_smp_server\|fb_inet_server" 1>$tmplog 2>&1
    retcode=$?
    cat $tmplog
    cat $tmplog>>$joblog
    if [[ $retcode -ne 0 ]]; then
            sho "Port $port is NOT linstening by any FB process. Job terminated." $joblog
            exit
    else
        fb_pid=$(awk '{print $NF}' $tmplog | cut -d"/" -f1)
        fb_exe=$(readlink -f /proc/${fb_pid}/exe)
        sho "Port $port is listening by process $fb_pid, executable name: $fb_exe" $joblog
        fb_dir=$(dirname $fb_exe)
        if [[ "$fb_dir" == "$fbc" ]]; then
            sho "Executable was launched from directory '$fbc'. Job can continue." $joblog
        else
            sho "Executable was launched NOT from '$fbc'. Job terminated." $joblog
            exit
        fi
    fi

}
# end of check_port

cleanup_dir() {
    local dir_to_clean=$1
    local files_pattern=$2 # "oltp-scheduled.*.log"
    local max_files_to_keep=$3 # $MAX_LOG_FILES
    local joblog=$4
    local tmplst=$5
    local tmperr=$6
    local run_cmd
    local del_cnt=0

    run_cmd="find ${dir_to_clean}/${files_pattern} -maxdepth 1 -type f -printf \"%f\n\" | sort -r | tail --lines=+$(( MAX_LOG_FILES+1 ))"

    sho "Cleanup folder $dir_to_clean: remove all files with pattern $files_pattern until their number become $max_files_to_keep" $joblog
    echo Command: "${run_cmd}"
    echo Command: "${run_cmd}" >>$joblog
    eval "${run_cmd}" 1>$tmplst 2>$tmperr
    if [[ -s "$tmperr" ]]; then
        sho "FAILED: could not find any file with pattern ${dir_to_clean}/${files_pattern} for removing." $joblog
        cat $tmperr
        cat $tmperr>>$joblog
        rm -f $tmperr
    else
        while read line; do
            sho "Removing file ${dir_to_clean}/$line" $joblog
            rm -f ${dir_to_clean}/$line
            del_cnt=$((del_cnt+1))
        done < <(grep . $tmplst)
        sho "Completed. Total removed files: $del_cnt" $joblog
    fi
    rm -f $tmplst $tmperr

}
# end of cleanup_dir

#.............................................

launch_fb_daemon() {
    local update_fb_instance=$1
    local svc_updated_txt=$2
    local svc_load_script=$3
    local joblog=$4
    local tmplog=$5
    local tmperr=$6

    local run_cmd

    run_cmd="cp --force --preserve $svc_updated_txt $svc_load_script"
    sho "Replace script that starts FB service. Command: $run_cmd" $joblog
    eval $run_cmd 1>$tmplog 2>$tmperr
    bulksho $tmplog $joblog
    catch_err $joblog $tmperr
    rm -f $svc_updated_txt
    echo ++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    run_cmd="systemctl enable $service_name"
    sho "Make service $service_name enable. Command: $run_cmd" $joblog
    # ::: NB :::
    # systemctl enable writes to STDERR! Example:
    # Created symlink from /etc/systemd/system/multi-user.target.wants/... to /usr/lib/systemd/system/...
    # We have to check STDERR only when elev not equals 0.
    eval $run_cmd 1>$tmplog 2>&1
    elev=$?
    bulksho $tmplog $joblog
    if [[ $elev -ne 0 ]]; then
        catch_err $joblog $tmperr
    fi
    echo ++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    run_cmd="systemctl daemon-reload"
    sho "Reload system info about services. Command: $run_cmd" $joblog
    eval $run_cmd 1>$tmplog 2>$tmperr
    bulksho $tmplog $joblog
    catch_err $joblog $tmperr
    echo ++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    run_cmd="systemctl start $service_name"
    sho "Start service. Command: $run_cmd" $joblog
    eval $run_cmd 1>$tmplog 2>$tmperr
    bulksho $tmplog $joblog
    catch_err $joblog $tmperr
    echo ++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    run_cmd="systemctl status $service_name"
    sho "Obtain service status. Command: $run_cmd" $joblog
    eval $run_cmd 1>$tmplog 2>$tmperr
    bulksho $tmplog $joblog
    catch_err $joblog $tmperr

}
# end of launch_fb_daemon

#.............................................

get_etalon_state() {
    # get_etalon_state "${fbc}" "${$etalon_dbnm}" etalon_readonly etalon_shutdown
    local fbc=$1
    local etalon_dbnm=$2
    local tmplog=$3
    local __etalon_readonly=$4 # output arg.
    local __etalon_shutdown=$5 # output arg.

    if [[ -f "$fbc/gstat" ]]; then
        $fbc/gstat -h $etalon_dbnm 1>$tmplog 2>&1
        if [[ $? -ne 0 ]]; then
              sho "Can not get DB header for 'etalon_dbnm' = $etalon_dbnm" $joblog
              cat $tmplog
              cat $tmplog>>$joblog
              exit 1
        fi
        if grep -q -i "attributes[[:space:]].*read[[:space:]]only" $tmplog; then
              etalon_readonly=1
              sho "Etalone database: $etalon_dbnm - has read_only mode." $joblog
        fi

        if grep -q -i "attributes[[:space:]].*shutdown" $tmplog; then
              etalon_shutdown=1
              sho "Etalone database: $etalon_dbnm - has shutdown state." $joblog
        fi
        if [[ $etalon_shutdown -eq 0 && $etalon_readonly -eq 0 ]]; then
              sho "Etalone database: $etalon_dbnm - has normal state and read_write mode." $joblog
        fi
    else
        sho "Could not find $fbc/gstat utility. Check parameter 'fbc' in OLTP-EMUL config!" $joblog
        exit 1
    fi

    # Returning value:
    ##################
    eval $__etalon_readonly="'$etalon_readonly'"
    eval $__etalon_shutdown="'$etalon_shutdown'"
}
# get_etalon_state

#.............................................

get_debug_pkg_name() {
    local fb_mnemona=$1
    local file_with_snapshot_basename=$2
    local __snapshot_dbg_pk=$3

    local mnemona_suffix x_snapshot_dbg_pk parse_cmd elev

    mnemona_suffix=${fb_mnemona: -2}

    if [[ "$mnemona_suffix" == "40" ]]; then
        parse_cmd="grep -m1 -i \"\\-debug\" $file_with_snapshot_basename | grep -m1 -i -E \"(x64|amd64)\" | awk -F'\"' '{print \$2}'"
    else
        parse_cmd="grep -i \"\\-debug\" $file_with_snapshot_basename | grep -i \"linux\" | grep -m1 -i -E \"(x64|amd64)\" | awk -F'\"' '{print \$2}'"
    fi

    sho "3. Get name of DEBUG PACKAGE for snapshot '$x_snap_no'. Command:" $joblog
    sho "$parse_cmd" $joblog
    eval "$parse_cmd" 1>$tmplst 2>$tmperr
    elev=$?
    sho "Result: elev=$elev" $joblog
    bulksho $tmplst $joblog 1
    #                      ^^^-- do NOT drop file $tmplst

    x_snapshot_dbg_pk=$(grep . $tmplst)
    x_snapshot_dbg_pk="https://github.com${x_snapshot_dbg_pk}"
    sho "Result: x_snapshot_dbg_pk=$x_snapshot_dbg_pk" $joblog

    # Expected results:
    # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-v4.0/Firebird-debuginfo-4.0.7.3231-9129571.amd64.tar.gz
    # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-v5.0-release/Firebird-5.0.4.1703-bd5ab06-linux-x64-debugSymbols.tar.gz
    # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.1246-5cad620-linux-x64-debugSymbols.tar.gz
    eval $__snapshot_dbg_pk="'$x_snapshot_dbg_pk'"

}

#.............................................

download_distr_list() {

    # download_distr_list ${fb_mnemona} ${download_method} ${download_from} ${tmplst} build_no
    #                           1                 2                3             4        5

    local fb_mnemona=$1
    local download_method=$2
    local download_from=$3
    local save_list_to_file=$4

    # Output args:
    ###########################
    local __parsed_build_no=$5  # output arg
    local __lupd_since_epoch=$6 # output arg: number of seconds since Linux epoch that matches to Last-Modified time of snapshot
    local __lupd_build_hash=$7  # output arg: SHA of github commit that was last before this snapshot building process started; this is part of file name
    local __snapshot_itself=$8
    local __snapshot_dbg_pk=$9
    ###########################

    local chk_code msg_subj run_cmd elev suffix_name suffix_value
    local mnemona_prefix mnemona_suffix
    local x_snapshot_itself x_snapshot_dbg_pk
    local tmpdts tmppy tmptmp tmplog tmperr tmplst parse_cmd x_snap_no x_snap_fn x_snap_fb x_snap_hash

    sho "Routine $FUNCNAME: start. Download method: $download_method, download_from=$download_from" $joblog

    x_snap_no=UNDEFINED
    x_snap_lupd=99991231235959
    x_snap_hash=UNDEFINED

    mnemona_prefix=${fb_mnemona::2}
    mnemona_suffix=${fb_mnemona: -2}

    # since 07-sep-2022: use DIFFERENT parameters from config for obtaining suffix of snapshot file names:
    # Firebird-3.0.11.33621-0.amd64.tar.gz
    # Firebird-4.0.3.2832-0.amd64.tar.gz
    # Firebird-5.0.0.714-Initial-linux-x64.tar.gz <<< !!! <<<
    suffix_name=${fb_mnemona^^}_SNAPSHOT_SUFFIX # name of config parameter with filter: 'FB30_SNAPSHOT_SUFFIX' or 'HQ30_SNAPSHOT_SUFFIX' etc
    suffix_value=${!suffix_name} # value of config parameter with filter: FB --> '.amd64.tar.gz'; HQ --> 'HQbird.amd64.tar.gz'

    if [[ "${mnemona_prefix^^}" == "FB" && "$mnemona_suffix" != "30" ]]; then
        # FB 4.x+ snapshots are created only in github
        #+++++++++++++++++++++
        download_method="http"
        #+++++++++++++++++++++
        download_prefix="https://github.com/FirebirdSQL/snapshots/releases/expanded_assets"
        if [[ "$fb_mnemona" == "FB40" ]]; then
            #download_from="${download_prefix}/snapshot-v4.0"
            # from oltp-scheduled_config.nix:
            download_from=$FB4X_SNAPSHOT_URL
        elif [[ "$fb_mnemona" == "FB50" ]]; then
            #download_from="${download_prefix}/snapshot-v5.0-release"
            # from oltp-scheduled_config.nix:
            download_from=$FB5X_SNAPSHOT_URL
        elif [[ "$fb_mnemona" == "FB60" ]]; then
            #download_from="${download_prefix}/snapshot-master"
            # from oltp-scheduled_config.nix:
            download_from=$FB6X_SNAPSHOT_URL
        fi
    fi
    sho "CHECK: mnemona_prefix=$mnemona_prefix, mnemona_suffix=$mnemona_suffix, download_from=$download_from" $joblog
    tmpdts=$(date +'%y%m%d_%H%M%S')
    tmplog=$tmpdir/${FUNCNAME}.${tmpdts}.tmp
    tmptmp=$tmpdir/${FUNCNAME}.${tmpdts}.tm2
    tmperr=$tmpdir/${FUNCNAME}.${tmpdts}.err
    tmplst=$tmpdir/${FUNCNAME}.${tmpdts}.lst
    tmppy=$tmpdir/${FUNCNAME}.${tmpdts}.py
    rm -f $save_list_to_file
    if [[ $download_method == "ftp" ]]; then
        run_cmd="${CURL_BIN} ${PROXY_DATA} --location --verbose $download_from/ --list-only --output $save_list_to_file --write-out %{http_code}"
        # http_code=226 --> download from FTP finished OK
        chk_code=226
    else
        run_cmd="${CURL_BIN} ${PROXY_DATA} --insecure --location --verbose $download_from --output $save_list_to_file --write-out %{http_code}"
        # http_code=200 --> download from HTTP finished OK
        chk_code=200
    fi

    if [[ $SEND_MAIL -eq 1 ]]; then
        msg_subj="$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). INFO. Point before get list of FB snapshots files from ${download_method} resource."
        # echo "Command: $run_cmd">$tmplog
        send_to_email "$msg_subj" $tmplog  n/a  n/a  elev
    fi

    sho "Attempt to download list of FB snapshots." $joblog
    if [[ $SHOW_PRIVATE_INFO -eq 1 ]]; then
        sho "$run_cmd" $joblog
    else
        sho "Command: [hidden]. Private data logging disabled. Change parameter 'SHOW_PRIVATE_INFO' to 1." $joblog
    fi

    ##################################################################
    ###    D O W N L O A D I N G     L I S T     O F    F I L E S  ###
    ##################################################################
    eval "$run_cmd" 1>$tmplog 2>$tmperr
    elev=$?

    # Example for LINUX:
    # FB40
    # grep -E "\<a href.*Firebird(-debug.*)?-4.*.amd64.tar.gz" github-fb40-list.html.txt
    # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-v4.0/Firebird-4.0.3.2885-0.amd64.tar.gz" rel="nofollow" d......
    # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-v4.0/Firebird-debuginfo-4.0.3.2885-0.amd64.tar.gz" rel="n.....
    # FB50
    # grep -E "\<a href.*Firebird-5.*linux-x64(-debug)?.*.tar.gz" github-fb50-list.html.txt
    # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-5.0.0.884-Beta1-linux-x64-debugSymbols.tar.gz" rel="nofollow" da......
    # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-5.0.0.884-Beta1-linux-x64.tar.gz" rel="nofollow" data-turbo="fal.......

    if [[ $elev -eq 0 && $chk_code -eq $(head -1 $tmplog) ]]; then
        sho "Success. Size of downloaded list $save_list_to_file: $(stat -c%s $save_list_to_file)." $joblog
        parse_cmd="grep . $save_list_to_file | grep ${suffix_value}"
        sho "Parse ${save_list_to_file}. Command: $parse_cmd" $joblog
        eval "$parse_cmd" 1>$tmplog 2>&1
        elev=$?
        sho "Result: elev=$elev. Check result of parsing:" $joblog
        bulksho $tmplog $joblog
        x_snapshot_itself=UNKNOWN
        x_snapshot_dbg_pk=UNKNOWN

        if [[ $download_method == "http" ]]; then
            # FB_SNAPSHOT_SUFFIX=.amd64.tar.gz
            if [[ "${fb_mnemona^^}" == "FB40" ]]; then
                # <td nowrap class=content><a href='./Firebird-4.0.0.2349-ReleaseCandidate1.amd64.tar.gz'>Firebird-4.0.0.2349-ReleaseCandidate1.amd64.tar.gz</a></td>
                # <td nowrap class=content><a href='./Firebird-debuginfo-4.0.0.2349-ReleaseCandidate1.amd64.tar.gz'>Firebird-debuginfo-4.0.0.2349-ReleaseCandidate1.amd64.tar.gz</a></td>    	    
                parse_cmd="grep -E \"\\<a href.*Firebird(-debug.*)?-4.*${FB40_SNAPSHOT_SUFFIX}\" $save_list_to_file "
            elif [[ "${fb_mnemona^^}" == "FB50" ]]; then
                # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-5.0.0.884-Beta1-linux-x64-debugSymbols.tar.gz" rel="nofollow" 
                # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-5.0.0.884-Beta1-linux-x64.tar.gz" rel="nofollow" data-turbo="f
                #grep -E "\<a href.*Firebird-5.*linux-x64(-debug)?.*.tar.gz" $save_list_to_file

                # https://github.com/FirebirdSQL/snapshots/releases/expanded_assets/snapshot-v5.0-release
                # Firebird-5.0.4.1703-bd5ab06-linux-x64.tar.gz
                # Firebird-5.0.4.1703-bd5ab06-linux-x64-debugSymbols.tar.gz
                parse_cmd="grep -E \"\\<a href.*Firebird-5.*linux-x64(-debug)?.*${FB50_SNAPSHOT_SUFFIX}\" $save_list_to_file "
            elif [[ "${fb_mnemona^^}" == "FB60" ]]; then
                # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.48-Initial-linux-x64-debugSymbols.tar.gz" rel="nofollow" 
                # <a href="/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.48-Initial-linux-x64.tar.gz" rel="nofollow" data-turbo="f
                parse_cmd="grep -E \"\\<a href.*Firebird-6.*linux-x64(-debug)?.*${FB60_SNAPSHOT_SUFFIX}\" $save_list_to_file "
            else
                #parse_cmd="grep -i -e \"href=.*${FB_SNAPSHOT_SUFFIX}\" $save_list_to_file " # | awk -F "'" '{print \$2}'"
                sho "${CRITICAL_LABEL} Command for parsing URL of snapshot remains UNDEFINED. Job terminated." $joblog
                exit 1
            fi

            sho "1. Get name of build. Command: $parse_cmd" $joblog
            eval "$parse_cmd" 1>$tmplog 2>$tmperr
            elev=$?
            sho "Result: elev=$elev, tmplog=$tmplog" $joblog
            bulksho $tmplog $joblog 1
            if [[ $elev -eq 0 ]]; then

                sho "Found lines with build number:" $joblog
                parse_cmd="grep -m1 -i -v \"\\-debug\" $tmplog | awk -F'\"' '{print \$2}'"
                # /FirebirdSQL/snapshots/releases/download/snapshot-v4.0/Firebird-4.0.3.2885-0.amd64.tar.gz
                # /FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-5.0.0.884-Beta1-linux-x64.tar.gz
                sho "2. Extract snapshot number. Command: $parse_cmd" $joblog

                eval "$parse_cmd" 1>$tmplst 2>$tmperr
                x_snap_fn=$(<$tmplst)
                x_snapshot_itself="https://github.com${x_snap_fn}"

                x_snap_fb=$(basename $x_snap_fn)
                x_snap_no=$(echo $x_snap_fb | cut -d"-" -f2)
                echo ${x_snap_no} | grep -E "[0-9]\.[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,}" 1>$tmplst 2>$tmperr
                elev=$?
                if [[ $elev -eq 0 && -s $tmplst ]]; then
                    sho "Build number parsed successfully: $x_snap_no" $joblog
                else
                   sho "${CRITICAL_LABEL} Build number can not be extracted from FB snapshot string '${x_snap_no}'" $joblog
                   exit 1
                fi
                x_snap_hash=$(echo $x_snap_fb | grep --extended-regexp "([a-f]|[0-9]){7,}" --only-matching)
                sho "x_snap_hash=$x_snap_hash" $joblog

                # grep -i -v "debug" /opt/distr/venv/qa-rundaily/logs/download_distr_list.230922_193356.tmp | grep -i "linux" | grep -i -E "(x64|amd64)"  | awk -F'"' '{print $2}'
                # /FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.48-Initial-linux-x64.tar.gz
                # Get name of DEBUG PACKAGE for snapshot
                if [[ "$mnemona_suffix" == "40" ]]; then
                    parse_cmd="grep -m1 -i \"\\-debug\" $tmplog | grep -m1 -i -E \"(x64|amd64)\" | awk -F'\"' '{print \$2}'"
                else
                    parse_cmd="grep -i \"\\-debug\" $tmplog | grep -i \"linux\" | grep -m1 -i -E \"(x64|amd64)\" | awk -F'\"' '{print \$2}'"
                fi

                sho "3. Get name of DEBUG PACKAGE for snapshot '$x_snap_no'. Command:" $joblog
                sho "$parse_cmd" $joblog
                eval "$parse_cmd" 1>$tmplst 2>$tmperr
                elev=$?
                sho "Result: elev=$elev" $joblog
                bulksho $tmplst $joblog 1
                #                      ^^^-- do NOT drop file $tmplog

                x_snapshot_dbg_pk=$(grep . $tmplst)
                x_snapshot_dbg_pk="https://github.com${x_snapshot_dbg_pk}"
                sho "Result: x_snapshot_dbg_pk=$x_snapshot_dbg_pk" $joblog

                # Expected results:
                # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-v4.0/Firebird-debuginfo-4.0.7.3231-9129571.amd64.tar.gz
                # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-v5.0-release/Firebird-5.0.4.1703-bd5ab06-linux-x64-debugSymbols.tar.gz
                # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.1246-5cad620-linux-x64-debugSymbols.tar.gz

            else
                sho "$CRITICAL_LABEL Could not find any string with FB build." $joblog
                exit
            fi
        else
            sho "Download using FTP" $joblog
            # Currently this is actual only for HQbird and official FB 3.x

            parse_cmd="grep \"${suffix_value}\" $save_list_to_file | grep -v \"debug\" | sed -e \"s/[[:punct:]]\+/ /g\" | sort -r -n -k5 | head -1"

            sho "1. Sort list of files in order to get MOST RECENT snapshot. Command:" $joblog
            sho "$parse_cmd" $joblog
            eval "$parse_cmd" 1>$tmplog 2>$tmperr
            elev=$?
            sho "Result: elev=$elev" $joblog

            bulksho $tmplog $joblog 1
            #                      ^^^-- do NOT drop file $tmplog

            # Result: tmplog has at the 1st line most recent snapshot which name was splitted on tokens:
            # Firebird 3 0 13 33818 HQbird a1be672 amd64 tar gz
            # Firebird 4 0  6  3223 HQbird 970bec8 amd64 tar gz
            # Firebird 5 0  3  1683 HQbird 7c14008 linux x64 tar gz
            #     ^    ^ ^  ^    ^
            # ----|----|-|--|----|---------------------------------
            #     1    2 3  4    5
            if [[ $elev -eq 0 ]]; then
                sho "List of files has been ordered by 3rd token of BUILD NUMBER, descending. Now we extract build number from the 1st line." $joblog
                IFS=' ' read -r -a array <<< "$(head -1 $tmplog)"
                echo a0 ${array[0]}
                echo a1 ${array[1]}
                echo a2 ${array[2]}
                echo a3 ${array[3]}
                echo a4 ${array[4]}
                x_snap_no=${array[1]}.${array[2]}.${array[3]}.${array[4]}
            fi
            sho "Result: most recent snapshot x_snap_no=$x_snap_no" $joblog
            parse_cmd="grep \"${x_snap_no}\" $save_list_to_file | grep -i -v \"debug\" | head -1"
            sho "2. Get filename of most recent snapshot, excluding names containing 'debug' word. Command:" $joblog
            sho "$parse_cmd" $joblog
            eval "$parse_cmd" 1>$tmplog 2>$tmperr
            elev=$?
            sho "Result: elev=$elev" $joblog
            x_snapshot_itself=$(grep . $tmplog)
            x_snap_hash=$(echo $x_snapshot_itself | grep --extended-regexp "([a-f]|[0-9]){7,}" --only-matching)

            sho "x_snapshot_itself=${x_snapshot_itself}, build_hash=${x_snap_hash}" $joblog
            parse_cmd="grep \"${x_snap_no}\" $save_list_to_file | grep -i \"debug\" | head -1"
            sho "3. Get name of DEBUG PACKAGE for snapshot '${x_snap_no}'. Command:" $joblog
            sho "$parse_cmd" $joblog
            eval "$parse_cmd" 1>$tmplog 2>$tmperr
            elev=$?
            sho "Result: elev=$elev" $joblog
            bulksho $tmplog $joblog 1
            #                      ^^^-- do NOT drop file $tmplog

            x_snapshot_dbg_pk=$(grep . $tmplog)
        fi
        # download_method = 'http' | 'ftp'

        # MANDATORY lines in the $save_list_to_file:
        #   line N1 = snapshot itself,
        #   line N2 = debug package (regardless on sort order of  their names)

        # Examples when download using ftp:
        # Firebird-3.0.13.33818-HQbird-a1be672.amd64.tar.gz
        # Firebird-debuginfo-3.0.13.33818-HQbird-a1be672.amd64.tar.gz
        # Firebird-5.0.3.1683-HQbird-2e691cf-linux-x64.tar.gz
        # Firebird-5.0.3.1683-HQbird-2e691cf-linux-x64-debugSymbols.tar.gz
        # Examples when download using http:
        # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-v4.0/Firebird-4.0.7.3231-9129571.amd64.tar.gz
        # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-v4.0/Firebird-debuginfo-4.0.7.3231-9129571.amd64.tar.gz
        # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.1246-5cad620-linux-x64.tar.gz
        # https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-6.0.0.1246-5cad620-linux-x64-debugSymbols.tar.gz

cat <<-EOF >$save_list_to_file
	$x_snapshot_itself
	$x_snapshot_dbg_pk
EOF

cat <<-EOF >$tmplog
	List of snapshot files to be downloaded:
	----------------------------------------
	$(cat $save_list_to_file)
	----------------------------------------
EOF
        bulksho $tmplog $joblog

        if [[ $SEND_MAIL -eq 1 ]]; then
            msg_subj="$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). INFO. Point after get list of FB snapshots files from ${download_method} resource."
            send_to_email "$msg_subj" $save_list_to_file n/a n/a  elev
        fi

        if [[ $download_method == "ftp" ]]; then
            file_for_check_lupd=${download_from}/${x_snapshot_itself}
            # http_code=226 --> download from FTP finished OK
            chk_code=226
        else
            file_for_check_lupd=${x_snapshot_itself}
            # http_code=200 --> download from HTTP finished OK
            chk_code=200
        fi

        # curl --silent --location --head https://github.com/FirebirdSQL/snapshots/releases/download/snapshot-master/Firebird-5.0.0.978-Beta1-linux-x64.tar.gz
        run_cmd="${CURL_BIN} ${PROXY_DATA} --location --silent --head ${file_for_check_lupd} --output $tmptmp --write-out %{http_code}"
        sho "Get last-modified date for snapshot that is to be downloaded. Command:" $joblog
        sho "$run_cmd" $joblog
        eval "$run_cmd" 1>$tmplog 2>&1
        elev=$?
        bulksho $tmptmp $joblog 1
        #                      ^^^-- do NOT drop file $tmplog
        sho "Result: elev=$elev, http_code: $(head -1 $tmplog), LUPD: $(grep "last-modified" $tmptmp)" $joblog
        # FB4x, FB5x: last-modified: Fri, 17 Mar 2023 21:00:42 GMT^M // NB: first letter is lowercase 'L', EOL = chr_13+chr_10 - even on Linux
        # FB3x:       Last-Modified: Mon, 27 Mar 2023 21:20:51 GMT
        # HQ3x, HQ4x: Last-Modified: Thu, 23 Mar 2023 23:23:45 GMT


        if [[ $elev -eq 0 ]]; then
            sed 's/\r//' $tmptmp  | grep -m1 -i -E "last(-|\s)?modified: " | awk '{i = 5; for (--i; i >= 0; i--){ printf "%s\t",$(NF-i)} print ""}' >$tmplog
            snapshot_lupd=$(cat $tmplog | sed -e 's/[[:space:]]*$//')
            sho "Success, last updated time: ${snapshot_lupd}" $joblog
            # 11       Aug     2025    20:26:15        GMT
            # 28       Jul     2025    00:20:30        GMT
cat <<-EOF >$tmppy
		#import time
		#import datetime as dt
		#lupd_epoch=int( time.mktime(time.strptime('${snapshot_lupd}', '%d %b %Y %H:%M:%S %Z'))  )
		#print(dt.datetime.utcfromtimestamp(lupd_epoch).strftime('%Y%m%d%H%M%S'))

		# since 27.08.2025
		from datetime import datetime
		dto = datetime.strptime( '${snapshot_lupd}', '%d %b %Y %H:%M:%S %Z')
		dts=dto.strftime('%Y%m%d%H%M%S')
		print(dts)
EOF

            $PYTHON_BIN $tmppy 1>$tmplog 2>$tmperr
            elev=$?
            if [[ $elev -eq 0 ]]; then
                # OUTPUT arg.:
                x_snap_lupd=$(head -1 $tmplog)
                sho "Snapshot Last-Modified timestamp, in ANSI format: $x_snap_lupd" $joblog
            else
                sho "$CRITICAL_LABEL Could not evaluate number of seconds since Linux EPOCH start to snapshot last-modified timestamp." $joblog
                sed 's/\r//' $tmperr > $tmplog
                bulksho $tmplog $joblog
                    rm -f $tmperr
            fi
            rm $tmppy
        else
            sho "$CRITICAL_LABEL Could not obtain metadata (including last-modified date) of file ${file_for_check_lupd}. Retcode: $(head -1 $tmplog)." $joblog
            sed 's/\r//' $tmperr > $tmplog
            rm -f $tmperr
            exit 1
        fi

    else
        sho "$CRITICAL_LABEL Could not download list of FB snapshot. Retcode: $(head -1 $tmplog)." $joblog
        sed 's/\r//' $tmperr | grep -v -i " (transfer " > $tmplog
        rm -f $tmperr
        sho "Log of downloading process $tmplog, size $(stat -c%s $tmplog), content:" $joblog
        bulksho $tmplog $joblog
        exit 1
    fi

    if [[ -z $save_list_to_file ]]; then
        sho "$CRITICAL_LABEL Could not find any compressed build in the donwloaded list. Job terminated." $joblog
        exit 1
    fi

    rm -f $tmplog $tmptmp $tmperr $tmplst $tmppy

    # Success, last updated time: 21 Sep 2023 20:29:35 GMT
    # Snapshot Last-Modified timestamp, in ANSI format: 20230921192935
    # Routine download_distr_list: finish. Parsed build_no: 5.0.0.1225, LUPD: 20230921192935    

    # Returning values:
    ##################
    eval $__parsed_build_no="'$x_snap_no'"
    eval $__lupd_since_epoch="'$x_snap_lupd'"
    eval $__lupd_build_hash="'$x_snap_hash'"

    eval $__snapshot_itself="'$x_snapshot_itself'"
    eval $__snapshot_dbg_pk="'$x_snapshot_dbg_pk'"

    sho "Routine $FUNCNAME: finish. Parsed build_no: ${x_snap_no}, LUPD: ${x_snap_lupd}, build_hash: ${x_snap_hash}" $joblog

}
# end of func 'download_distr_list'

#.............................................

extract_snapshot() {

    local target_folder=$1
    local snapshot_tar_gz=$2
    local debug_package_tar_gz=$3

    local run_cmd elev tmplog tmperr curdir

    curdir=${PWD}
    sho "Routine $FUNCNAME: start." $joblog

    tmplog=$tmpdir/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').tmp
    tmperr=$tmpdir/${FUNCNAME}.$(date +'%y%m%d_%H%M%S').err

    if [[ "${snapshot_tar_gz##*.}" == "7z"  ]]; then
        run_cmd="$P7Z_BIN x -y $snapshot_tar_gz -o${target_folder}"
        sho "Current dir: ${PWD}. Extract files from $snapshot_tar_gz to ${target_folder} using $P7Z_BIN" $joblog
        sho "Command: $run_cmd" $joblog
        eval $run_cmd 1>$tmplog 2>$tmperr
        elev=$?
        catch_err $joblog $tmperr "Problem with extraction from $snapshot_tar_gz to ${target_folder}, retcode: $elev"
        sho "Result: elev=$elev" $joblog
        ls -la ${target_folder}
        echo "quit;" | ${target_folder}/bin/isql -q -z 1>$tmplog 2>$tmperr
        catch_err $joblog $tmperr "Test ISQL version FAILED."
        bulksho $tmplog $joblog
        sho "Creator of $snapshot_tar_gz had to put .debug package in it. SKIP extraction." $joblog
    else
        run_cmd="tar xvf ${snapshot_tar_gz} -C ${target_folder} --strip-components=1 --overwrite --warning=no-timestamp"
        sho "Current dir: ${PWD}. Extract buildroot.tar.gz from compressed snapshot to ${target_folder}." $joblog
        sho "Command: ${run_cmd}" $joblog
        eval $run_cmd 1>$tmplog 2>$tmperr
        elev=$?
        catch_err $joblog $tmperr "Problem with extraction from $snapshot_tar_gz to ${target_folder}, retcode: $elev"
        sho "Result: elev=$elev" $joblog
        if [[ $elev -eq 0 ]]; then
            rm -f ${target_folder}/install.sh
            rm -f ${target_folder}/manifest.txt
            run_cmd="tar xvf ${target_folder}/buildroot.tar.gz -C ${target_folder} --strip-components=3 --overwrite --wildcards ./opt/firebird/*"
            sho "Current dir: ${PWD}. Extract files from buildroot.tar.gz to ${target_folder}" $joblog
            #sho "Command: tar xvf ${target_folder}/buildroot.tar.gz -C ${target_folder} --strip-components=3 --wildcards ./opt/firebird/*" $joblog
            sho "Command: \"${run_cmd}\"" $joblog
            #tar xvf ${target_folder}/buildroot.tar.gz -C ${target_folder} --strip-components=3 --wildcards ./opt/firebird/* 1>>$tmplog 2>$tmperr
            eval $run_cmd 1>$tmplog 2>$tmperr
            elev=$?
            catch_err $joblog $tmperr "Problem with extraction from ${target_folder}/buildroot.tar.gz to ${target_folder}, retcode: $elev"
            sho "Result: elev=$elev" $joblog
            rm -f ${target_folder}/buildroot.tar.gz
            echo "quit;" | ${target_folder}/bin/isql -q -z 1>$tmplog 2>$tmperr
            catch_err $joblog $tmperr "Test ISQL version FAILED."
            bulksho $tmplog $joblog
        fi

        if [[ ! -z "${debug_package_tar_gz}" && -f ${debug_package_tar_gz} ]]; then
            sho "Input arg 'debug_package_tar_gz' not empty and points to existing file: ${debug_package_tar_gz}" $joblog
            run_cmd="tar xvf $debug_package_tar_gz -C ${target_folder} --strip-components=3"
            sho "We have to extract its files to ${target_folder}. Command:" $joblog
            sho "$run_cmd" $joblog
            eval "$run_cmd" 1>$tmplog 2>&1
            elev=$?
            # If target file already exists and has newer or the same timestamp then result (in STDERR) will be
            # tar: Current ‘plugins/.debug/libLegacy_UserManager.so.debug’ is newer or same age
            # - but errorlevel remains 0.
            sho "Result of extraction: $elev. Check content of 'tar xvf' log:" $joblog
            bulksho $tmplog $joblog 1
            if [[ $elev -ne 0 ]]; then
                sho "$CRITICAL_LABEL Problem with unpacking '${debug_package_tar_gz}'" $joblog
                exit
            fi
        else
            elev=2
            sho "Input arg for debug package: '${debug_package_tar_gz}' - not defined or does not exist. Extraction NOT performed." $joblog
        fi
        if [[ $elev -ne 0 ]]; then
            sho "### WARNING ### Stack trace will not be readable in case of crash." $joblog
        fi
    fi
    # extension of compressed snapshot: 7z / gz

    # result: ${target_folder} must have following structure:
    # /bin/*
    # /lib/*
    # /plugins/*
    # securityN.fdb
    # firebird.conf
    # ... etc ...
    # -- i.e like we already inside common $FB_HOME folder.
    # Folder 'usr' was not extracted from buildroot.tar.gz (not needed).

    # Problem with FB 4.x snapshots: employee.fdb has permissions mask 'r--r--r--'
    # which prevents from making connection to this DB.
    sho "Changing permissions mask for employee.fdb: add 'w' access to owner and group." $joblog
    chmod 664 ${target_folder}/examples/empbuild/employee.fdb 1>$tmplog 2>&1
    elev=$?
    catch_err $joblog $tmperr "Problem with changing permission for employee.fdb, retcode: $elev"
    stat ${target_folder}/examples/empbuild/employee.fdb 1>$tmplog 2>&1
    bulksho $tmplog $joblog
    rm -f $tmplog $tmperr

    sho "Routine $FUNCNAME: finish." $joblog

}
# end of func 'extract_snapshot'

#.............................................

fb_launch() {
    local fb_lock_dir=$1
    local fbc=$2
    local fbport=$3
    local waiting_max_time=4
    local __fbguard_pid=$5  # output arg.
    local __firebird_pid=$6 # output arg.

    local run_cmd check_listening_port_cmd msg_subj elev sec must_abend
    local tmpdts tmplst tmplog tmperr tmppy

    sho "Routine $FUNCNAME: start." $joblog
    tmpdts=$(date +'%y%m%d_%H%M%S')
    tmplst=$tmpdir/${FUNCNAME}.${tmpdts}.lst
    tmplog=$tmpdir/${FUNCNAME}.${tmpdts}.tmp
    tmperr=$tmpdir/${FUNCNAME}.${tmpdts}.err
    tmppy=$tmpdir/${FUNCNAME}.${tmpdts}.py

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
    eval "$run_cmd" 1>$tmplst 2>&1
    elev=$?
    catch_err $joblog $tmperr
    echo "Retcode: $elev" >> $tmplst
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

        eval $check_listening_port_cmd 1>$tmplog 2>&1
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
    eval $check_listening_port_cmd 1>$tmplst 2>&1
    # send_to_email "$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). INFO. Firebird launch result: OK. Port: ${fbport}" $tmplst n/a n/a  elev
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
    local oltp_dbnm=$2
    local tmpdir=$3

    local tmpdbdir tmpdts tmplog tmperr tmpsql tmpfdb

    sho "Routine $FUNCNAME: start." $joblog
    tmpdts=$(date +'%y%m%d_%H%M%S')
    tmplog=$tmpdir/${FUNCNAME}.${tmpdts}.tmp
    tmperr=$tmpdir/${FUNCNAME}.${tmpdts}.err
    tmpsql=$tmpdir/${FUNCNAME}.${tmpdts}.sql
    tmpfdb=$(dirname ${oltp_dbnm})/${FUNCNAME}.${tmpdts}.fdb

    sho "Verifying that FB instance is working. Test DB: ${tmpfdb}" $joblog
    rm -f ${tmpfdb}
    rm -f $tmpsql
cat <<- EOF >$tmpsql
    set list on;
    set echo on;
    set bail on;
    create database 'localhost:${tmpfdb}' user '${usr}' password '${pwd}';
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
          a_connect_with_usr varchar(31) default '${usr}'
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
             else if ( upper(current_user) = upper('${usr}')
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
    select * from sys_get_fb_arch('${usr}', '${pwd}');
    commit;
    delete from mon\$attachments where mon\$attachment_id != current_connection ;
    commit;
    drop database;

EOF
    $fbc/isql -q -z -i $tmpsql 1>$tmplog 2>$tmperr
    bulksho $tmplog $joblog
    catch_err $joblog $tmperr
    rm -f $tmplog $tmperr $tmpsql
    sho "Routine $FUNCNAME: finish." $joblog
}
# end of func 'fb_basic_check'

#.............................................

###############################
###   M A I N     P A R T   ###
###############################

this_script_directory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Grand-parent directory related to current:
#OLTP_HOME_DIR=${this_script_directory%/*/*}

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

#if [ $EUID -ne 0 ];  then
#    echo You have to run this script as ROOT user.>$abendlog
#    cat $abendlog
#    exit 1
#fi

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

fb_mnemona=$1
winq=$2

fb_mnemona=$(echo "$fb_mnemona" | tr '[:upper:]' '[:lower:]')
fb_mnemona=${fb_mnemona//./}
mnemona_prefix=${fb_mnemona::2}
mnemona_suffix=${fb_mnemona: -2}

# name 'fb' is used in many places; todo: replace it.
fb=$mnemona_suffix

if [[ "$fb" = "25" ]]; then
    preferred_fb_mode="cs"
else
    preferred_fb_mode=${3:-"ss"}
fi
preferred_fb_mode=$(echo "$preferred_fb_mode" | tr '[:upper:]' '[:lower:]')

########################################
### DO WE UPDATE FIREBIRD INSTANCE ? ###
########################################
update_fb_instance=${4:-1}

unset check_existing_snapshot
if [[ "$update_fb_instance" == "0" || "$update_fb_instance" == "1" ]]; then
    :
elif [[ -s ${4} ]]; then
    # /mnt/hdd/oltp-emul/fb6x-snapshots/Firebird-6.0.0.1194-c157a2c-linux-x64.tar.gz
    sho "Arg N4 points to existing FILE. This file is assumed to be snapshot to be checked." $abendlog
    update_fb_instance=1
    sho "Check content of archive. Command: tar -tzf ${4}" $abendlog
    tar -tzf ${4} 1>>$abendlog 2>&1
    if [[ $? -eq 0 ]];then
        check_existing_snapshot="${4}"
        sho "Passed." $abendlog
    else
        sho "Failed to obtain list of files in compressed snapshot ${4}. Job terminated." $abendlog
        exit 1
    fi
else

cat <<-EOF >$abendlog
	Value of arg_4 [update_fb_instance] is invalid: $update_fb_instance.
	Must be 1 (default) or 0 or filename of existing FB snapshot (Firebird.A.B.C-<sha>.tar.gz)
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

#########################
# READ THIS SCRIPT CONFIG
#########################
readcfg $this_script_conf_name $abendlog

if [[ -s ${check_existing_snapshot} ]]; then
    DEBUG_SNAPSHOT_TO_CHECK=${check_existing_snapshot}
    sho "Redefinition of parameter 'DEBUG_SNAPSHOT_TO_CHECK': assign it to ${DEBUG_SNAPSHOT_TO_CHECK}" $abendlog
fi

if [[ "${DEBUG_SNAPSHOT_TO_CHECK}" == "" ]]; then
    sho "Config parameter 'DEBUG_SNAPSHOT_TO_CHECK' not specified" $abendlog
else
    msg="Config parameter DEBUG_SNAPSHOT_TO_CHECK='${DEBUG_SNAPSHOT_TO_CHECK}'"
    if [[ -s ${DEBUG_SNAPSHOT_TO_CHECK} ]]; then
        msg="${msg} points to existing file. Test will use this file instead of downloading."
        update_fb_instance=1
    else
        msg="${msg} points to NON existing or empty file. Job terminated."
    fi
    sho "${msg}" $abendlog
    if [[ ! -s ${DEBUG_SNAPSHOT_TO_CHECK} ]]; then
        exit 1
    fi
fi

# OLTP_ROOT_DIR - from this script config:
OLTP_SRC_DIR=${OLTP_ROOT_DIR}/src

# oltp-fb60.conf.nix
# oltp-hq30.conf.nix
export oltp_emul_conf_name=${OLTP_SRC_DIR}/oltp-${fb_mnemona}.conf.nix

if [[ -s $oltp_emul_conf_name ]]; then
    :
else
    echo "Config file '$oltp_emul_conf_name' does not exists or empty.">>$abendlog
    cat $abendlog
    exit
fi

sho "Parsing config file ${oltp_emul_conf_name}" $abendlog

#######################
# READ OLTP-EMUL CONFIG
#######################
readcfg $oltp_emul_conf_name $abendlog

if [[ -z "${tmpdir}" ]]; then
    echo Could not properly parse OLTP-EMUL config $oltp_emul_conf_name. Problem with parameter tmpdir.>>$abendlog
    exit 1
fi

mkdir -p $tmpdir && touch $tmpdir/tmp.tmp && rm $tmpdir/tmp.tmp
if [[ $? -eq 0 ]]; then
    echo "Successfully created / accessed tmpdir=$tmpdir"
else
    msg="Could NOT create / access tmpdir=$tmpdir"
    echo $msg
    echo $msg > $abendlog
    exit 1
fi

dbdir=$(dirname "${dbnm}")
if [[ -d ${dbdir} ]]; then
    touch $dbdir/tmp.tmp && rm $dbdir/tmp.tmp
    if [[ $? -eq 0 ]]; then
        echo "Successfully accessed dbdir=${dbdir}"
    else
        msg="Config parameter dbnm=${dbnm} points to non-accessible directory. You have to adjust access rights."
        echo $msg
        echo $msg > $abendlog
        exit 1
    fi
else
    msg="Config parameter dbnm=${dbnm} points to non-existing directory. You have to create it first."
    echo $msg
    echo $msg > $abendlog
    exit 1
fi

fb_lock_dir=${fb_mnemona^^}_LOCK_DIR # name of OPTIONAL config parameter for replacing default FIREBIRD_LOCK variable: FB60_LOCK_DIR etc
fb_lock_dir=${!fb_lock_dir} # value of 'XXXX_LOCK_DIR', e.g. /tmp/fb60_lock etc
if [[ -z "${fb_lock_dir}" ]]; then
    sho "Parameter '${fb_mnemona^^}_LOCK_DIR' not specified. Default value will be used for FIREBIRD_LOCK variable." $abendlog
    fb_lock_dir="default" # need to be non-empty because will be used as 1st arg for fb_launch() routine
else
    sho "Parameter '${fb_mnemona^^}_LOCK_DIR' not empty. Value for FIREBIRD_LOCK: '${fb_lock_dir}'" $abendlog
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
############    j o b l o g   ###################
joblog=$tmpdir/${this_script_name_only}.${dts}.log
##################################################

tmplog=$tmpdir/$this_script_name_only.${dts}.tmp
tmperr=$tmpdir/$this_script_name_only.${dts}.err
tmplst=$tmpdir/$this_script_name_only.${dts}.lst
tmpsql=$tmpdir/$this_script_name_only.${dts}.sql

###############################################
###    i n i t i a l i z e    j o b l o g   ###
###############################################

cat $abendlog
cat $abendlog>$joblog
rm -f $abendlog

sho "Config files parsing completed." $joblog

if [ "$clu" != "" ]; then
    # Name of ISQL on Ubuntu/Debian when FB is installed from OS repository
    # 'isql-fb' etc:
    echo Config contains custom name of command-line utility for interact with Firebird.>>$joblog
    echo Parameter: \'clu\', value: \|$clu\|>>$joblog
else
    echo Using standard name of command-line utility for interact with Firebird: 'isql'>>$joblog
    clu=isql
fi
isql_name=$fbc/$clu

#####################################
fb_config_prototype=$this_script_directory/${this_script_name_only}-${fb_mnemona}.conf.${preferred_fb_mode^^}
sho "Prototype for firebird.conf: ${fb_config_prototype}, LUPD: $(stat -c %y $fb_config_prototype)" $joblog

if [[ "${preferred_fb_mode^^}" == "SS" || "${preferred_fb_mode^^}" == "SC" || "${preferred_fb_mode^^}" == "CS" ]] ; then
    if [[ "$fb" == "30" ]]; then
        (grep "^[^#]" $fb_config_prototype | grep -m1 -i "FileSystemCacheThreshold") 1>$tmplog 2>$tmperr
        if  [[ -s $tmplog ]]; then
cat <<-EOF >>$joblog
		Prototype for firebird.conf: $fb_config_prototype - contains parameter 'FileSystemCacheThreshold':
		$(cat $tmplog)
EOF
        else
cat <<-EOF >>$joblog
		Prototype for firebird.conf: $fb_config_prototype - either does not exist or has no parameter 'FileSystemCacheThreshold'
		Check $tmplog and $tmperr:
		$(cat $tmplog)
		$(cat $tmperr)
		Job terminated.
EOF
		cat $joblog
	        exit 1

        fi
    else
        (grep "^[^#]" $fb_config_prototype | grep -i "UseFileSystemCache\s*=\s*false") 1>$tmplog 2>$tmperr
        if  [[ -s "$log" ]]; then
cat <<-EOF >>$joblog
		Prototype for firebird.conf: $fb_config_prototype - disables usage of File System cache:
		$(cat $tmplog)
		
		You have to change config and ENABLE usage of File System cache.
		Job terminated.
EOF
		cat $joblog
	        exit 1
        elif [[ -s "$tmperr" ]]; then
cat <<-EOF >>$joblog
		Prototype for firebird.conf: $fb_config_prototype - either absent or could not be parsed.
		$(cat $tmperr)
		
		Job terminated.
EOF
		cat $joblog
	        exit 1
        else
cat <<-EOF >>$joblog
		Prototype for firebird.conf: $fb_config_prototype - has no restriction of File System cache usage.
		$(cat $tmplog)
EOF
        fi
    fi
else
cat <<-EOF >>$joblog
		Value of arg_3 [server mode] is invalid: ${preferred_fb_mode^^}
		Must be SS, SC or CS (case-insensitive). Job terminated.
EOF
    cat $joblog
    exit 1
fi

curl_retry_avaliable=0
if [[ $update_fb_instance -eq 1 ]]; then
    command -v ${CURL_BIN} 1>>$joblog 2>&1
    if [[ $? -ne 0 ]]; then
        msg="Package 'curl' not found on this host. You have to install it first."
        echo $msg
        echo $msg>>$joblog
        exit 1
    fi

cat <<-EOF >$tmplst
	--connect-timeout
	--retry
	--retry-delay
	--retry-max-time
EOF
    $CURL_BIN --help all 1>$tmplog 2>&1

    # 19.05.2025 We have to check that every command switch from $tmplst presents in the log of
    # 'curl --help all' (command switch '--retry' added in curl 7.12.3)
    curl_retry_avaliable=1
    while read line; do
        required_command_switch=" $line "
        if grep -q -e "${required_command_switch}" $tmplog; then
            sho "Command switch '${required_command_switch}' FOUND in the help log of curl." $joblog
        else
            sho "Command switch '${required_command_switch}' NOT FOUND in the help log of curl." $joblog
            curl_retry_avaliable=0
        fi
    done < <(cat $tmplst)

    # | grep -e "--connect-timeout\|--retry\|--retry-delay\|--retry-max-time" 1>$tmlog 2>&1
    #curl --help all | grep -e "--connect-timeout\|--retry\|--retry-delay\|--retry-max-time"
    #     --connect-timeout <seconds>                   Maximum time allowed to connect
    #     --retry <num>                                 Retry request if transient problems occur
    #     --retry-all-errors                            Retry all errors (with --retry)
    #     --retry-connrefused                           Retry on connection refused (with --retry)
    #     --retry-delay <seconds>                       Wait time between retries
    #     --retry-max-time <seconds>                    Retry only within this period
    sho "curl_retry_avaliable=$curl_retry_avaliable" $joblog
fi # '$update_fb_instance -eq 1'

command -v netstat 1>>$joblog 2>&1
if [[ $? -ne 0 ]]; then
    msg="Package 'netstat' not found on this host. You have to install it first."
    echo $msg
    echo $msg>>$joblog
    exit 1
fi

sho "Console ISQL utility binary: ${isql_name}, LUPD: $(stat -c %y ${isql_name})" $joblog

pdir="$(dirname "$fbc")"
if [[ ! -d "${pdir}" ]]; then

    # CHANGE value of parameter update_fb_instance!
    update_fb_instance=1

    sho "Directory ${pdir} not yet exists. Make attempt to create it." $joblog
    mkdir "${pdir}" 1>$tmperr 2>&1
    elev=$?
    catch_err $joblog $tmperr "Adjust parameter 'fbc' in appropriate OLTP-EMUL config file."
    # 755: drwxr-xr-x
    sho "Result: $elev, check access rights: $(stat --format "%a" "${pdir}")" $joblog
fi

##########################################
###  c l e a n u p    t e m p   d i r  ###
##########################################
sho "Cleanup temp dir '$tmpdir'" $joblog
cleanup_dir $tmpdir "${this_script_name_only}.*.log" $MAX_LOG_FILES $joblog $tmplst $tmperr
if [[ $MAX_RPT_FILES -gt 0 ]]; then
    cleanup_dir $tmpdir "*_score_*.txt" $MAX_RPT_FILES $joblog $tmplst $tmperr
    cleanup_dir $tmpdir "*_score_*.htm*" $MAX_RPT_FILES $joblog $tmplst $tmperr
fi
cleanup_dir $tmpdir "*.tar.gz" $MAX_ZIP_FILES $joblog $tmplst $tmperr

#------------------------------------------------------------

if [[ $update_fb_instance -eq 1 ]]; then

    # <update_fb_instance> is command-line parameter N4, default: 1
    ######################################

    # Firebird instance must be [re-]installed in the PARENT directory for variable 'fbc' that was created
    # when we read oltp-emul config (folder where isql lives): '/opt/firebird/bin' --> '/opt/firebird'.
    # Normally GRAND-parent folder ('/opt') has all necessary access rights: 'drwxrwxr-x'
    # But if we want to put FB instance in some other dir then its PARENT must have the same access mask,
    # otherwise service will not start, even if acess rights to FB dir meet this requirement.
    # Output will be: "Failed at step EXEC spawning /home/ibase/fb3x/bin/fbguard: Permission denied"
    #
    sho "Check access rights to '$fbc' and all parent directories" $joblog
    pdir=$fbc
    access_rights_problem=0
    while :
    do
	pdir="$(dirname "$pdir")"
	[[ "${pdir}" == "/" ]] && break
	if [[ -d "${pdir}" ]]; then
    	    dir_access_rights=$(stat --format "%a" "${pdir}")
    	    if [[ $dir_access_rights -eq 775 || $dir_access_rights -eq 755 ]]; then
                # rwxrwxr-x or rwxr-xr-x
    		sho "Check access rights to '${pdir}' PASSED." $joblog
    	    else
cat <<-EOF >$tmplog
		### ACHTUNG ###
		Access rights to the directory ${pdir} is INEFFCICIENT to run installed FB as service:
		$(stat --format "%A" "${pdir}")
		Needed permissions for this directory: 'drwxr-xr-x'
		You have to run: chmod 755 ${pdir}
		-----------------------
EOF
		bulksho $tmplog $joblog
		access_rights_problem=$((access_rights_problem+1))
	    fi
	else
	    sho "Directory '$pdir' not yet exists. Access rights not checked." $joblog
	fi
    done

    if [[ $access_rights_problem -gt 0 ]]; then
        sho "Found $access_rights_problem folders which access rights must be adjusted. JOB TERMINATED." $joblog
        exit 1
    fi

  
    ###############################################################################################
    ### c h e c k    f o r     l i b t o m a t h    &   l i b n c u r s e s     p a c k a g e s ###
    ###############################################################################################
    cat /etc/*release* | grep -m1 -i "^id=" > $tmplog

    # NB: Ubuntu names have suffix '-dev', e.g.: libtommath-dev, libtomcrypt-dev
    required_packages_list="libtommath" #  libtomcrypt"
    if grep -q -i "debian\|ubuntu" $tmplog ; then
        # needed by gsec, gstat etc:
        # libncurses5 ==> libncurses6
        required_packages_list="${required_packages_list} libncurses"
    fi
    required_packages_array=(${required_packages_list})

    for checked_package in "${required_packages_array[@]}"; do

      retcode=0
      sho "Check whether package '$checked_package' is installed. THIS MAY TAKE A LONG TIME, WAIT!" $joblog
      if grep -q -i "centos" $tmplog ; then
          yum list installed | grep -i $checked_package 1>$tmplst
          retcode=$?
      elif grep -q -i "ubuntu" $tmplog ; then
          apt list --installed 2>&1 | grep -i $checked_package 1>$tmplst
          retcode=$?
      elif grep -q -i "debian" $tmplog ; then
          apt list --installed 2>&1 | grep -i $checked_package 1>$tmplst
          retcode=$?
      else
          sho "ERROR: CAN NOT DETECT OS." $joblog
          exit
      fi
      bulksho $tmplst $joblog 1

      if [[ $retcode -ne 0 ]]; then
          sho "ABEND. Package '$checked_package' not found on your system. Install it first." $joblog
          if grep -q -i "cenos" $tmplog ; then
              sho "Try command: yum -y install $checked_package" $joblog
          elif grep -q -i "ubuntu" $tmplog ; then
              sho "Try command: apt-get --assume-yes install ${checked_package}-dev" $joblog
          fi
          exit
      else
          sho "Completed, result: package found." $joblog
      fi
    done
    rm -f $tmplog $tmplst
else
    sho "Input argument 'update_fb_instance' is 0. Skip check for presence of packages required to install FB." $joblog
fi
# update_fb_instance -eq 1

#----------------------------------------------------------------

if [[ $CREATE_EMPTY_DB -eq 1 ]]; then
    sho "Etalone DB not needed: config parameter CREATE_EMPTY_DB=$CREATE_EMPTY_DB, empty ${dbnm} will be created." $joblog
else
    # Check that value of $etalon_dbnm is defined.
    # Get attributes of its header: whether it is in shutdown or readonly mode.
    etalon_shutdown=0
    etalon_readonly=0
    if [ -s ${etalon_dbnm} ]; then
        sho "Parameter 'etalon_dbnm' in $oltp_emul_conf_name points to existing .fdb file" $joblog

        if [[ $update_fb_instance -eq 1 ]]; then

cat <<- EOF >$tmplog
		FB instance will be re-installed in the directory '$dir_to_install_fb'.
		Parameter 'etalon_dbnm' in OLTP-EMUL config points to file:
		${etalon_dbnm}
		This database exists but its state will be checked after FB instalation.
EOF
           bulksho $tmplog $joblog
       else
          # Check that etalon_dbnm is really FB database. If yes - get its read_only and shutdown state:
          get_etalon_state "${fbc}" "${etalon_dbnm}" $tmplog etalon_readonly etalon_shutdown
        fi
    else
        sho "This scenario requires parameter 'etalon_dbnm' to be DEFINED in $oltp_emul_conf_name and point to existing .fdb file" $joblog
        exit 1
    fi
fi

#unset ISC_USER
#unset ISC_PASSWORD
# Take from oltp-emul config data for ISC* variables:
#####################
export ISC_USER=$usr
export ISC_PASSWORD=$pwd

#------------------------------------------------------------------------------
# get parent dir for  '/opt/fb30/bin' or '/opt/fb40/bin' --> '/opt/fb30'; '/opt/fb40'
dir_to_install_fb="$(dirname "$fbc")"
#------------------------------------------------------------------------------

sho "Start parsing prototype of firebird.conf and change its RemoteServicePort and BugCheckAbort parameters." $joblog

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

cat <<- EOF >$tmplog
Completed.
FB config '$fb_cfg_for_work' now has RemoteServicePort = $port
(as it specified in '$oltp_emul_conf_name').
BugCheckAbort=1 was added without conditions in order to allow dumps to be created.
EOF
bulksho $tmplog $joblog

#------------------------------------------------------------

command -v gdb 1>$tmplog 2>&1
if [[ $? -eq 0 ]]; then
  if [[ -f "$dbnm" ]]; then
    sho "Check whether $dbnm is opened now by any of FB-related processes. Make stack trace in this case." $joblog
    rm -f $tmplst
    # Example: find /proc/25686/fd/5
    # Can raise here: find: ‘/proc/25686/fd/5’: No such file or directory
    find /proc -regex '\/proc\/[0-9]+\/fd\/.*' -type l -lname "$dbnm" 1>$tmplog 2>$tmperr
    if [[ -s "$tmplog" ]]; then
        grep . $tmplog | awk -F'/' '{print $3}' > $tmplst
    fi
    # Result: $tmplst contains list of PIDs of processes which keep DB file open.
    # (find /proc -regex '\/proc\/[0-9]+\/fd\/.*' -type l -lname "$dbnm" 2>&1) | grep -v "find" | awk -F'/' '{print $3}' 1>$tmplst 2>&1
    rm -f $tmplog $tmperr

    if [[ -s "$tmplst" ]]; then
        sho "File $dbnm is opened by at least one process:" $joblog
        echo "(find /proc -regex '\/proc\/[0-9]+\/fd\/.*' -type l -lname \"$dbnm\" 2>&1) | grep -v \"find\" | awk -F'/' '{print \$3}'"
        cat $tmplst
        cat $tmplst>>$joblog

        # Count NOT EMPTY lines with PIDs.
        # This can be greater then 1 if DB is opened by FB Classic processes:
        processes_to_handle=$(cat $tmplst | sed '/^\s*$/d' | wc -l)
        got_lock_print=0
        gdb_commands=$tmpdir/gdb_commands.$this_script_name_only.txt

        while read pid_line; do
            binary_file_name=$(cat /proc/$pid_line/comm)
            echo "$FB_BIN_PATTERN" | grep -q -E "\|$binary_file_name\|" > /dev/null
            if [[ $? -eq 0 ]]; then
                sho "Process with PID=$pid_line has name '$binary_file_name' and present in FB-related list. We have to make stack-trace for it." $joblog
                binary_full_name=$(readlink /proc/$pid_line/exe)
                # Most of all $dbnm is opened by firebird | fb_inet_server | fb_smp_server or other FB-related process.
                # Before we try to make stack-trace for it, one need to ensure that there are .debug-files in following
                # sub-directories of folder that is parent for FB-process: ./bin; ./lib and ./plugins
                # /opt/fb30/bin/firebird --> /opt/firebird
                binary_parent_dir="$(dirname $(dirname "$binary_full_name"))"
                sho "Check for equality: binary_parent_dir=$binary_parent_dir; dir_to_install_fb=$dir_to_install_fb" $joblog
                if [[ "$binary_parent_dir" == "$dir_to_install_fb" ]]; then
                    ls -A $dir_to_install_fb/*/.debug/* 1>$tmplog 2>/dev/null
                    if [[ -s "$tmplog" ]]; then
                        sho "Found debug package under $dir_to_install_fb. Can try to make stack-trace" $joblog
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
			sho "Generating stack trace for $binary_full_name, command:" $joblog
			echo $run_cmd
			echo $run_cmd>>$joblog

			sho "Content of gdb command scenario '$gdb_commands':" $joblog
			cat $gdb_commands
			cat $gdb_commands>>$joblog

			eval $run_cmd 1>$stack_trace_txt 2>&1
			sho "Completed. Size of stack-trace: $(stat -c%s $stack_trace_txt). Process $pid_line now can be killed." $joblog
			rm -f $gdb_commands

			if grep -q -i -m1 "CRC[[:space:]]mism" $stack_trace_txt; then
			    sho "ACHTUNG. Stack-trace is INVALID: found message about CRC mismatch." $joblog
			    grep -i -m1 "crc[[:space:]]mism" $stack_trace_txt >$tmplog
			    cat $tmplog
			    cat $tmplog >>$joblog
			elif  grep -i -m1 "Missing separate debuginfo for[[:space:]]$dir_to_install_fb" $stack_trace_txt; then
			    sho "ACHTUNG. Stack-trace can be not readable. At least one file from FB debug package missed." $joblog
			    grep -i -m1 "Missing separate debuginfo for[[:space:]]$dir_to_install_fb" $stack_trace_txt >$tmplog
			    cat $tmplog
			    cat $tmplog >>$joblog
			else
			    if grep -q -m1 " at .*.h:[[:digit:]]\| at .*.cpp:[[:digit:]]" $stack_trace_txt; then
			        sho "Stack-trace looks VALID." $joblog
			    else
			        sho "Stack-trace looks valid but there is no lines related to source code references: .cpp or .h" $joblog
			    fi
			fi
			run_cmd="tar -czvf ${stack_trace_txt%.*}.tar.gz --directory $(dirname $stack_trace_txt) ${stack_trace_txt##*/}"
			sho "Compress stack-trace. Command: $run_cmd" $joblog
			eval $run_cmd 1>$tmplog 2>&1
			if [[ $? -eq 0 ]]; then
			    rm -f $stack_trace_txt
			    sho "Success. Size of compressed file: $(stat -c%s ${stack_trace_txt%.*}.tar.gz)" $joblog
			else
			    sho "ACHTUNG. Failed to compress stack-trace." $joblog
			    cat $tmplog
			    cat $tmplog>>$joblog
			    rm -f ${stack_trace_txt%.*}.tar.gz
			fi
			
			if [[ got_lock_print -eq 1 && -f $lock_p_txt ]]; then
			    run_cmd="tar -czvf ${lock_p_txt%.*}.tar.gz --directory $(dirname $lock_p_txt) ${lock_p_txt##*/}"
			    sho "Compress output of $fbc/fb_lock_print -a -d $dbnm. Command: $run_cmd" $joblog
			    eval $run_cmd 1>$tmplog 2>&1
			    sho "Completed. Size of compressed file: $(stat -c%s ${lock_p_txt%.*}.tar.gz)" $joblog
			    rm -f $lock_p_txt
			fi
			rm -f $tmplog
                    fi
                    # ls -A $dir_to_install_fb/*/.debug/* --> .debug package *exists*
                fi
                # if [[ "$binary_parent_dir" == "$dir_to_install_fb" ]]
            else
	        sho "SKIP gdb launch. DB file is opened by process '${binary_file_name}'" $joblog
	        sho "This name does not belong to this list: ${FB_BIN_PATTERN}" $joblog
            fi
            # DB file is opened by FB-related process (rather than some other utilities).
        done < <(cat $tmplst)
        rm -f $tmplst
    else
        sho "Database file $dbnm is NOT opened now and can be replaced." $joblog
    fi
    # end of processing non-empty list of PIDs which keep $dbnm file opened
  fi
  # end of -f "$dbnm"
fi
# gdb package presents here

#-------------------------------------------------------------------

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


previous_fb_snapshot=0
actual_fb_snapshot=0
debug_package_tar_gz=UNDEFINED
if [[ $update_fb_instance -eq 1 ]]; then

    if [[ -f "$fbc/isql" ]]; then
        # ISQL Version: LI-T4.0.0.1946 Firebird 4.0 Beta 2 --> LI-T4.0.0.1946 --> 1946
        previous_fb_snapshot=$( echo "quit;" | $fbc/isql -q -z | awk '{print $3}' | awk -F '.' '{print $NF}' )
    fi

    # fb_snapshots_root=$FB_SNAPSHOTS_URL # http://web.firebirdsql.org/download/snapshot_builds/linux
    if [[ "$fb_mnemona" == "fb30" ]]; then
        download_from=$FB3X_SNAPSHOT_URL
    elif [[ "$fb_mnemona" == "fb40" ]]; then
        download_from=$FB4X_SNAPSHOT_URL
    elif [[ "$fb_mnemona" == "fb50" ]]; then
        download_from=$FB5X_SNAPSHOT_URL
    elif [[ "$fb_mnemona" == "fb60" ]]; then
        download_from=$FB6X_SNAPSHOT_URL
    elif [[ "$fb_mnemona" == "hq30" ]]; then
        download_from=$HQ3X_SNAPSHOT_URL
    elif [[ "$fb_mnemona" == "hq40" ]]; then
        download_from=$HQ4X_SNAPSHOT_URL
    elif [[ "$fb_mnemona" == "hq50" ]]; then
        download_from=$HQ5X_SNAPSHOT_URL
    else
        sho "Variable for storing URL of FB snapshots was not defined, fb=${fb}." $joblog
        ######
        exit 1
        ######
    fi
    download_method=$(echo $download_from | awk -F ":" '{print $1}' | tr '[:upper:]' '[:lower:]')

    #---+++---+++---+++---+++---+++---+++---+++---+++---+++---+++---+++---+++---+++---+++---+++
    build_no=UNDEFINED
    build_hash=UNDEFINED

    if [[ -z "${DEBUG_SNAPSHOT_TO_CHECK}" ]]; then
        curl_addi_keys="${PROXY_DATA} --location --verbose --write-out %{http_code} --output $tmplst"

        if [[ "$download_method" == "ftp" ]]; then
            chk_code=226
        else
            chk_code=200
            curl_addi_keys="--insecure ${curl_addi_keys}"
        fi
        sho "download_from=${download_from}, chk_code=$chk_code" $joblog

        #curl -v –trace --proxy <[protocol://][user:password@]proxyhost[:port]>  $download_from 1>$tmplog
        #run_cmd="curl -L -v –trace $PROXY_DATA $download_from"
        #run_cmd="curl ${PROXY_DATA} --location --verbose $download_from/ --output $tmplst --write-out %{http_code}"
        run_cmd="$CURL_BIN ${curl_addi_keys} $download_from/"
        sho "Preparing to download FB snapshots list. Command: $run_cmd" $joblog
        #############################################################
        ###    D O W N L O A D      L I S T     O F    F I L E S  ###
        #############################################################
        download_distr_list ${fb_mnemona} ${download_method} ${download_from} $tmplst build_no build_lupd build_hash snapshot_itself_name snapshot_debug_package
        #                        1                 2                3            4       5         6         7           8                     9

        # already defined, not needed: build_no=$(grep . $tmplst | grep -m1 -v -i "debug" | cut -d"-" -f2) # Firebird-3.0.8.33415-HQbird.amd64.tar.gz --> 3.0.8.33415
cat <<-EOF >$tmplog
	Result of download_distr_list():
	  build_no=${build_no}
	  Last-Modified attribute: $build_lupd
	  build_hash=$build_hash
	  download URLs:
	      snapshot_itself_name=$snapshot_itself_name
	      snapshot_debug_package=$snapshot_debug_package
EOF
        bulksho $tmplog $joblog
    else

        build_no=$(basename ${DEBUG_SNAPSHOT_TO_CHECK})
        build_hash="$(echo $build_no | grep --extended-regexp "([a-f]|[0-9]){7,}" --only-matching)"

        # Get substring that starts after first occurence of 'Firebird' word:
        build_no=$(echo ${build_no#*Firebird} | cut -d"-" -f2)
cat <<-EOF >$tmplog
	Config parameter 'DEBUG_SNAPSHOT_TO_CHECK' not empty:
	$DEBUG_SNAPSHOT_TO_CHECK
	Result of parsing:
	    build_no=${build_no}
	    build_hash=${build_hash}
EOF
        bulksho $tmplog $joblog
        snapshot_itself_name=${DEBUG_SNAPSHOT_TO_CHECK}

        snapshot_extension=${snapshot_itself_name##*.}
        snapshot_pattern="$(dirname ${DEBUG_SNAPSHOT_TO_CHECK})/Firebird-${build_no}-${build_hash}*debug*.${snapshot_extension}"
        sho "Pattern to search file with debug package: ${snapshot_pattern}" $joblog
        ls -1 ${snapshot_pattern} 1>$tmplst 2>&1
        if [[ $? -eq 0 ]]; then
            snapshot_debug_package=$(head -n 1 $tmplst)
            sho "Found debug package: ${snapshot_debug_package}" $joblog
        else
            sho "WARNING. Debug package NOT found for snapshot ${DEBUG_SNAPSHOT_TO_CHECK}" $joblog
        fi
    fi # ${DEBUG_SNAPSHOT_TO_CHECK} --> empty / non-empty

    # ---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...---...

    if [[ "${build_no^^}" == "UNDEFINED" || "${build_hash^^}" == "UNDEFINED" ]]; then
cat <<-EOF >$tmplog
	######################################################################
	###   P A R S I N G    S N A P S H O T    N A M E    F A I L E D   ###
	######################################################################
	Could not properly parse build number for '$fb_mnemona'.
	build_no=${build_no}, build_hash=${build_hash}
EOF
	bulksho $tmplog $joblog
	#msg_subj="$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). ${CRITICAL_LABEL} Could not parse snapshot number for fb_mnemona='${fb_mnemona}'"
        #send_to_email "$msg_subj" $joblog n/a text/html elev

        exit 1
    fi

    if [[ -z "${DEBUG_SNAPSHOT_TO_CHECK}" ]]; then
        downloaded_counter=0
cat<<-EOF >$tmplog
	#############################################
	###      D O W N L O A D    S T A R T     ###
	#############################################
	Check file names:
	---  start  ---
	$(cat $tmplst)
	---- finish ---
EOF
        bulksho $tmplog $joblog
        while read href; do
            sho "Loop for $tmplst, found element for download: $href" $joblog

            # Values of href:
            #     Firebird: './Firebird-3.0.8.33413-0.amd64.tar.gz'
            #       HQbird: 'Firebird-3.0.8.33403-HQbird.amd64.tar.gz'
            fb_tar_gz="$(basename -- $href)"
            fb_clean_name="${fb_tar_gz/-debuginfo/}" # Firebird-debuginfo-4.0.0.1946-Beta2.amd64.tar.gz --> Firebird-4.0.0.1946-Beta2.amd64.tar.gz

            # since 07.09.2022, for FB 5.x only:
            fb_clean_name="${fb_clean_name/-debugSymbols/}" # Firebird-5.0.0.714-Initial-linux-x64-debugSymbols.tar.gz -> Firebird-5.0.0.714-Initial-linux-x64.tar.gz

            # Get build number of snapshot that is to be downloaded below:
            # 'Firebird-4.0.0.1946-Beta2.amd64.tar.gz' --> '1946';
            # 'Firebird-debuginfo-3.0.8.33403-HQbird.amd64.tar.gz' --> 33403 
            actual_fb_snapshot=$( echo $fb_clean_name | awk -F'-' '{print $2}' | awk -F '.' '{print $NF}' )

            # Check that result of removing dots from ${build_no} contains only digits:
            # chk4_digits_only $actual_fb_snapshot

            sho "fb_tar_gz=$fb_tar_gz; fb_clean_name=$fb_clean_name; actual_fb_snapshot=$actual_fb_snapshot" $joblog

            if [[ $fb_tar_gz == *"debug"* && ${GET_DEBUG_PACKAGE} -eq 0 ]]; then
                msg_verb="SKIP downloading package $fb_tar_gz, check config parameter GET_DEBUG_PACKAGE"
                sho "$msg_verb" $joblog
                if [[ $SEND_MAIL -eq 1 ]]; then
                    msg_subj="$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). INFO. $msg_verb."
                    send_to_email "$msg_subj" $tmplst n/a n/a  elev
                fi

                continue
            fi

cat <<-EOF >$tmplog
	######################################################
	###   g e t    f i l e    u s i n g     c u r l    ###
	######################################################
EOF
            bulksho $tmplog $joblog
            # --connect-timeout -- Maximum time in seconds that you allow curl connection to take
            if [[ $curl_retry_avaliable -eq 1 ]]; then
                curl_retry_keys="--connect-timeout 61 --retry 30 --retry-delay 20 --retry-max-time 600"
            else
                unset curl_retry_keys
                sho "WARNING. Version of '${CURL_BIN}' is too old. No retries will be performed in case of transfer errors." $joblog
            fi
            unset curl_insecure
            if [[ "${mnemona_prefix^^}" == "FB" && "$mnemona_suffix" != "30" ]]; then
                download_url=$href
                curl_insecure="--insecure"
            else
                download_url=$download_from/$fb_tar_gz
            fi

            # run_cmd="curl ${PROXY_DATA} --location --time-cond --verbose ${href}  --output $tmpdir/$fb_tar_gz --write-out %{http_code}"
            download_to_file=$tmpdir/$fb_tar_gz
            run_cmd="${CURL_BIN} ${curl_insecure} ${PROXY_DATA} ${curl_retry_keys} --location --verbose --remote-time ${curl_addi_key} --output $download_to_file --write-out %{http_code} $download_url"
            sho "Downloading file ${fb_tar_gz}, size: $size_on_remote_node" $joblog
            if [[ $SHOW_PRIVATE_INFO -eq 1 ]]; then
                sho "Command: $run_cmd." $joblog
            else
                sho "Command: [hidden]. Private data logging disabled. Change parameter 'SHOW_PRIVATE_INFO' to 1." $joblog
            fi

            eval "$run_cmd" 1>$tmplog 2>$tmperr
            elev=$?
            http_code=$(head -1 $tmplog)
            sed 's/\r//' $tmperr | grep -v -i " (transfer " > $tmplog
            mv $tmplog $tmperr

cat <<-EOF >$tmplog
	curl_retry_keys=$curl_retry_keys
	href=$href
	fb_tar_gz=$fb_tar_gz
	fb_clean_name=$fb_clean_name
	actual_fb_snapshot=$actual_fb_snapshot
	+++ RESULT +++
	http_code=$http_code
	stat ${download_to_file}:
	$( stat ${download_to_file} )
	++++++++++++++
EOF
            bulksho $tmplog $joblog 1
            #                   ^^^- do not remove file
            #  send_to_email "$mail_hdr_subj $(date +'%d.%m.%y %H:%M'). INFO. $fb_mnemona, download snapshot: ${actual_fb_snapshot}, expected size: $size_on_remote_node. Result: elev: $elev, http_code=$http_code" $tmplog $tmperr n/a mail_result

            downloaded_counter=$((downloaded_counter+1))
        done < <( grep . $tmplst )
        # ^ read href
        rm -f $tmplst
        #############################################
        ### end of block for downloading snapshot ###
        #############################################
    fi #  -z "${DEBUG_SNAPSHOT_TO_CHECK}"


    # :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    cd $dir_to_install_fb
    ##########################################################################################
    # Cleanup: remove all files and sub-dirs from directory which must store unpacked snapshot
    ##########################################################################################
    rm -rfv $dir_to_install_fb/*
    if [[ $? -eq 0 ]]; then
        sho "All fine: folder $dir_to_install_fb is empty now." $joblog
    else
        sho "Problem with removing all files and sub-directories in $dir_to_install_fb" $joblog
        exit 1
    fi
    cd ${this_script_directory}
    ###########################################
    ###   e x t r a c t    s n a p s h o t  ###
    ###########################################
    if [[ -z "${DEBUG_SNAPSHOT_TO_CHECK}" ]]; then
        snapshot_itself_to_unpack=${tmpdir}/$(basename -- $snapshot_itself_name)
        snapshot_debug_to_unpack=${tmpdir}/$(basename -- $snapshot_debug_package)
    else
        snapshot_itself_to_unpack=${snapshot_itself_name}
        snapshot_debug_to_unpack=${snapshot_debug_package}
    fi
    extract_snapshot ${dir_to_install_fb} ${snapshot_itself_to_unpack} ${snapshot_debug_to_unpack}

    #########################################################################
    # Create (if needed) $dir_to_install_fb/UDF and extract 'sleep-UDF' there
    #########################################################################
    check_for_sleep_UDF $dir_to_install_fb $fb_cfg_for_work $tmplog $joblog

    #######################################
    # Replace firebird.conf with custom one
    #######################################
    cp --force --preserve $fb_cfg_for_work $dir_to_install_fb/firebird.conf

    # ?! 04.09.2025 chown firebird -R $dir_to_install_fb

    ##############################################################
    ### Add/update SYSDBA user with giving him password=${pwd} ###
    ##############################################################

    # ::: NB :::
    # current user must belong to a group that has 'rwx' access rights to the '/tmp/firebird' directory, e.g.:
    # drwxrwx--- 2 firebird fbqa 4096 Sep  4 14:46 /tmp/firebird
    # 'x' (for a directory) allows a user to enter a directory and access its subdirectories and files
    # This can be done by: 'chmod 770 /tmp/firebird'
    upd_sysdba_pswd ${pwd} $tmpsql $tmplog $tmperr $joblog

    if [[ -z "${DEBUG_SNAPSHOT_TO_CHECK}" ]]; then
        sho "Cleanup ${tmpdir}: we do not need downloaded snapshot anymore." $joblog
        rm -f ${snapshot_itself_to_unpack} ${snapshot_debug_to_unpack}
    else
        sho "Snapshot [and its debug package if exists] is preserved. You have to remove it manually when need. " $joblog
    fi
    cd $this_script_directory

    ##############################################################
    ###  T R Y I N G    T O    S T A R T     F I R E B I R D   ###
    ##############################################################
    fb_launch "${fb_lock_dir}" ${fbc} $port $SECONDS_WAIT_FOR_PORT  fbguard_pid firebird_pid
    sho "Return from fb_launch: fbguard_pid=$fbguard_pid; firebird_pid=$firebird_pid" $joblog
    # ps aux| grep "/mnt/hdd/.*/bin/" | grep -v grep


    ##############################################################
    ###  B A S I C    C H E C K   O F    R U N N I N G    F B  ###
    ##############################################################
    fb_basic_check ${fbc} ${dbnm} ${tmpdir}

else # update_fb_instance = 0 - do NOT update FB, just run test; e.g. change FB arch from SS to CS, etc.

    sho "Input parameter 'update_fb_instance' is 0." $joblog
    if [[ -s ${DEBUG_SNAPSHOT_TO_CHECK} ]]; then
        sho "Attempt to extract snapshot from '${DEBUG_SNAPSHOT_TO_CHECK}'." $joblog
    else
        sho "Parameter 'DEBUG_SNAPSHOT_TO_CHECK' undefined. SKIP updating FB instance and just run test." $joblog
    fi

    #########################################################################
    # Create (if needed) $dir_to_install_fb/UDF and extract 'sleep-UDF' there
    #########################################################################
    check_for_sleep_UDF $dir_to_install_fb $fb_cfg_for_work $tmplog $joblog

    sho "Current dir: $PWD" $joblog

    #######################################
    # Replace firebird.conf with custom one
    #######################################
    cp --force --preserve $fb_cfg_for_work $dir_to_install_fb/firebird.conf
    # dis 04.09.2025 chown -R firebird $dir_to_install_fb

    ##############################################################
    ###  T R Y I N G    T O    S T A R T     F I R E B I R D   ###
    ##############################################################
    fb_launch "${fb_lock_dir}" ${fbc} $port $SECONDS_WAIT_FOR_PORT  fbguard_pid firebird_pid
    sho "Return from fb_launch: fbguard_pid=$fbguard_pid; firebird_pid=$firebird_pid" $joblog
    # ps aux| grep "/mnt/hdd/.*/bin/" | grep -v grep

    ##############################################################
    ###  B A S I C    C H E C K   O F    R U N N I N G    F B  ###
    ##############################################################
    fb_basic_check ${fbc} ${dbnm} ${tmpdir}


fi # update_fb_instance = 1 or 0

rm -f $fb_cfg_for_work $tmplog $tmpsql

sho "Check list of environment variables and their values for firebird_pid=${firebird_pid}:" $joblog
cat /proc/${firebird_pid}/environ  | tr '\0' '\n' | sort 1>$tmplog 2>&1
bulksho $tmplog $joblog

sho "Firebird is running. We are ready to launch OLTP-EMUL test." $joblog
if [[ "${fb_lock_dir}" != "default" ]]; then
    sho "Check files in ${fb_lock_dir}:" $joblog
    ls -l "${fb_lock_dir}" 1>$tmplog 2>&1
    bulksho $tmplog $joblog
fi


if [[ $CREATE_EMPTY_DB -eq 1 ]]; then
    ########################################################
    ###  S E T   E T A L O N _ D B  =  E M P T Y   D B  ####
    ########################################################
    etalon_dbnm=$(dirname "${dbnm}")/empty_etalon.tmp.fdb
    rm -f $etalon_dbnm
    sho "etalon_dbnm=$etalon_dbnm" $joblog
    echo "create database 'localhost:/${etalon_dbnm}' user '$usr' password '$pwd';set list on;select * from mon\$database;" | $fbc/isql -q -z 1>$tmplog 2>$tmperr
    catch_err $joblog $tmperr
    bulksho $tmplog $joblog
fi
sho "etalon_dbnm=$etalon_dbnm" $joblog

if [[ $update_fb_instance -eq 1 ]]; then
    # Check that etalon_dbnm is really FB database. If yes - get its read_only and shutdown state:
    get_etalon_state "${fbc}" "${etalon_dbnm}" $tmplog etalon_readonly etalon_shutdown
fi

sho "Perform copying $etalon_dbnm to $dbnm. Please WAIT." $joblog
cp --force --preserve $etalon_dbnm $dbnm
if [[ $? -ne 0 ]]; then
    sho "Could not make copy of etalon database. You have to check access rights or disk space! Job terminated." $joblog
    exit
fi

if [[ $CREATE_EMPTY_DB -eq 1 ]]; then
    rm -f $etalon_dbnm
fi

#sho "Change owner of $dbnm to 'firebird'." $joblog
#chown firebird $dbnm
#if [[ $? -ne 0 ]]; then
#    sho "Could not change owner! Job terminated." $joblog
#    exit
#fi

stat $dbnm >$tmplog
sho "Completed. Check attributes of ${dbnm}:" $joblog
bulksho $tmplog $joblog

if [[ $etalon_shutdown -eq 1 ]]; then
    sho "Change state of target database from shutdown to normal." $joblog
    $fbc/gfix -online $dbnm 1>$tmplog 2>&1
    retcode=$?
    bulksho $tmplog $joblog
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change DB state to normal. Job terminated." $joblog
        exit
    else
        sho "Check attributes after change DB state:" $joblog
        $fbc/gstat -h $dbnm | grep -i attributes 1>$tmplog 2>&1
        bulksho $tmplog $joblog 1
        if grep -q -i "attributes[[:space:]].*shutdown" $tmplog; then
            sho "DB is still in shutdown state! Job terminated." $joblog
            exit
        fi
        rm -f $tmplog
    fi
fi

if [[ $etalon_readonly -eq 1 ]]; then
    sho "Change mode of target database from read_only to read_write." $joblog
    $fbc/gfix -mode read_write localhost/$port:$dbnm 1>$tmplog 2>&1
    retcode=$?
    bulksho $tmplog $joblog
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change DB mode to read_write. Job terminated." $joblog
        exit
    else
        sho "Check attributes after change DB mode:" $joblog
        $fbc/gstat -h $dbnm | grep -i attributes 1>$tmplog 2>&1
	bulksho $tmplog $joblog 1
        if grep -q -i "attributes[[:space:]].*read only" $tmplog; then
            sho "DB is still in read only mode! Job terminated." $joblog
            exit
        fi
        rm -f $tmplog
    fi
fi

# NB-1: it is better to change attributes FW and sweep BEFORE changing backup-lock,
# otherwise gstat -h will report old values for FW/sweep. See CORE-6399.
# NB-2: we have to use remote protocol here, i.e. specify 'localhost/$port' before $dbnm.
# Otherwise one may to get unexpected error like this:
# I/O error during "lock" operation for file "/home/bases/oltp40-etalone.encrypted.fdb"
# -Database already opened with engine instance, incompatible with current

if [[ -n "${create_with_fw}" ]]; then
    sho "Change FORCED WRITES for target DB, using parameter 'create_with_fw' = $create_with_fw." $joblog
    $fbc/gfix -w $create_with_fw localhost/$port:$dbnm 1>$tmplog 2>&1
    retcode=$?
    bulksho $tmplog $joblog
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change FW attribute. Job terminated." $joblog
        exit
    fi
fi
if [[ -n "${create_with_sweep}" ]]; then
    sho "Change SWEEP INTERVAL for target DB, using parameter 'create_with_sweep' = $create_with_sweep." $joblog
    $fbc/gfix -h $create_with_sweep localhost/$port:$dbnm 1>$tmplog 2>&1
    retcode=$?
    bulksho $tmplog $joblog
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change sweep interval. Job terminated." $joblog
        exit
    fi
fi
rm -f $tmplog

if [[ $BACKUP_LOCK -eq 1 ]]; then
    sho "Config parameter 'BACKUP_LOCK' is 1." $joblog
    sho "Apply 'nbackup -L' command to target database." $joblog
    rm -f $dbnm.delta
    if [[ -f "$dbnm.delta" ]]; then
        sho "Could not drop file $dbnm.delta. Job terminated." $joblog
        exit
    fi

    $fbc/nbackup -L $dbnm 1>>$tmplog 2>&1
    retcode=$?
    bulksho $tmplog $joblog
    if [[ $retcode -ne 0 ]]; then
        sho "Could not change DB mode to backup-lock. Job terminated." $joblog
        exit
    else
        sho "Check attributes after change DB mode to backup-lock:" $joblog
        $fbc/gstat -h $dbnm | grep -i attributes 1>$tmplog 2>&1
        retcode=$?
        bulksho $tmplog $joblog 1
        if grep -q -v -i "attributes[[:space:]].*backup lock" $tmplog; then
            sho "DB state could not be changed to backup-lock. Job terminated." $joblog
            exit
        fi
        rm -f $tmplog
    fi
else
    rm -f $dbnm.delta
fi

sho "#############################################################" $joblog
sho "Prepare completed. Check attributes of target DB before work:" $joblog
$fbc/gstat -h $dbnm | grep -i "page size\|page buffers\|attributes\|sweep" >$tmplog
cat $tmplog
cat $tmplog >>$joblog
sho "#############################################################" $joblog
rm -f $tmplog

unset ISC_USER
unset ISC_PASSWORD

if [[ $CREATE_EMPTY_DB -eq 0 ]]; then
    sho "Clean file system cache..." $joblog
    free -m >>$tmplog
    sync
    echo 3 > /proc/sys/vm/drop_caches
    free -m >>$tmplog
    cat $tmplog >>$joblog
    rm -f $tmplog
fi

sho "Completed. Now run OLTP-EMUL test with launching $winq ISQL sessions agains FB $fb." $joblog


cat <<-EOF >$tmplog
#################################################
### ::: L a u n c h ::: O L T P - E M U L ::: ###
#################################################
EOF
bulksho $tmplog $joblog

cd $OLTP_SRC_DIR 1>$tmperr 2>&1
catch_err $joblog $tmperr
rm -f $tmperr
sho "Current dir: ${PWD}, launch: ./1run_oltp_emul.sh ./$(basename -- $oltp_emul_conf_name) $winq" $joblog

bash ./1run_oltp_emul.sh ./$(basename -- $oltp_emul_conf_name) $winq
