#!/bin/bash

function pause(){
   read -p "$*"
}

msg_noarg() {
  clear
  echo Current script:
  echo $shname | sed -e 's/^/    /'
  echo
  echo - must be called from:
  echo $shdir/1run_oltp_emul.sh | sed -e 's/^/    /'
  echo
  echo Do not run it yourself.
  echo
  pause "Press any key to exit. . ."
}

sho() {
  local msg=$1
  local log=$2
  local use_ms=${3:-0}
  local dts
  if [[ $use_ms -eq 0 ]]; then
     dts=$(date +'%d.%m.%y %H:%M:%S')
  else
     dts=$(date +'%d.%m.%y %H:%M:%S.%3N')
  fi
  echo $dts. $msg
  echo $dts. $msg>>$log
}


log_elapsed_time() {
    local s1=$1
    local plog=$2
    local s2=$(date +%s)
    local sd=$(date -u -d "0 $s2 sec - $s1 sec" +"%H:%M:%S")
    local msg="Done for $sd, from $(date -d @$s1 +'%d-%m-%Y %H:%M:%S') to $(date -d @$s2 +'%d-%m-%Y %H:%M:%S')."
    sho "$msg" $plog
}

get_diff_fblog() {
    local mode=$1
    local fb_major=$2
    local sid=$3
    local fblog_beg=$4
    local log4sid=$5

    sho "Routine $FUNCNAME: start." $log4sid

    local get_log_switch
    local fb_home_dir
    local abend_flag=0
    local tmpdiff=$tmpdir/tmp_fb_diff.$sid.tmp
    local tmp_sql=$tmpdir/tmp_g_stop.$sid.tmp
    local fb_log_end=$tmpdir/tmp_fb_end.$sid.tmp

    [[ $fb_major -eq 25 ]] && get_log_switch=action_get_ib_log || get_log_switch=action_get_fb_log
    local run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"

    # fbc, host,port, dbconn, dbauth -- must be known here
    rm -f $tmpdir/tmp_fb_diff.$sid.tmp
    
    sho "SID=$sid. Gathering firebird.log, mode=$mode" $log4sid

    # fblog_beg = $tmpdir/fb_log_when_test_started.$fb.log
    if [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]; then
        fb_home_dir="$(dirname "$fbc")"
        sho "SID=$sid. ISQL session is running on server-side, we can open $fb_home_dir/firebird.log directly call fbsvcmgr to get its content." $log4sid
        echo -e 'Command: diff --unchanged-line-format="" --new-line-format=":%dn: %L" $fblog_beg $fb_home_dir/firebird.log' >> $log4sid
	echo --- start of diff output --- >>$tmpdiff
	diff --unchanged-line-format="" --new-line-format=":%dn: %L" $fblog_beg $fb_home_dir/firebird.log 1>>$tmpdiff 2>&1
	echo --- start of diff output --- >>$tmpdiff
    else
        sho "SID=$sid. Use command $run_fbs to get content of firebird.log" $log4sid
        $run_fbs 1>$fblog_end 2>>$log4sid
        sho "SID=$sid. Done, size of $fblog_end: $(stat -c%s $fblog_end). Starting comparison of old and new firebird log" $log4sid
	cat <<-EOF >$tmpdiff
		--- start of diff output ---
		diff --unchanged-line-format="" --new-line-format=":%dn: %L"  $fblog_beg $fblog_end
		--- end of diff output ---
	EOF
    fi
    cat $tmpdiff
    cat $tmpdiff >> $log4sid

    if  [ "$mode" == "check_for_crash" ] ; then
        if grep -q -i -E "(/firebird|/fb_smp_server).*terminated.*abnormally" $tmpdiff; then
            sho "SID=$sid. At least one message about FB crash detected in the diff file of firebird.log" $log4sid
            sho "SID=$sid. Test must be prematurely terminated. Trying to change sequence g_stop_test to negative value." $log4sid
            ###########################################################################################################
            ###   F O R C E D L Y     T E R M I N A T E     B E C A U S E     O F     F I R E B I R D    C R A S H  ###
            ###########################################################################################################
		cat <<-EOF >$tmp_sql
		set list on;
		set echo on;
		set bail on;
		-- ::: NOTE::: Command 'show sequence <g>' actually does:
		-- select gen_id(<G>,0) from rdb$database, i.e. it queries database table.
		-- It can take valuable time in case of extremely high workload (1500+ attachments).
		-- We can avoid such query this by using execute block
		set term ^;
		execute block returns( dts timestamp, g_stop_current bigint ) as
		begin
		    dts = 'now';
		    g_stop_current = gen_id( g_stop_test, 0 );
		    suspend;
		    if ( g_stop_current < 0 ) then
		       exception ex_test_cancellation;
		end^
		set term ;^
		set stat on;
		alter sequence g_stop_test restart with -999999999;
		commit;
		set stat off;
		set term ^;
		execute block returns( dts timestamp, g_stop_changed bigint ) as
		begin
		    dts = 'now';
		    g_stop_changed = gen_id( g_stop_test, 0 );
		    suspend;
		end^
		set term ;^
		exit;
		EOF
	    $fbc/isql $dbconn $dbauth -q -n -nod -i $tmp_sql 1>>$log4sid 2>&1
            #echo -e "show sequ g_stop_test; alter sequence g_stop_test restart with -999999999; commit; show sequ g_stop_test;" | $fbc/isql $dbconn $dbauth -q -n -nod 1>>$log4sid 2>&1
            sho "SID=$sid. Done. All workers soon will stop their job." $log4sid
            rm -f $tmp_sql

            abend_flag=1

        fi
    fi
    rm -f $tmpdiff
    rm -f $fb_log_end

    sho "Routine $FUNCNAME: finish." $log4sid
    if [ $abend_flag -eq 1 ]; then
        rm -f $sid_starter_sql
        exit 1
    fi
}
# get_diff_fblog

#.......................................... m a i n     p a r t ................................

export shname=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/`basename "${BASH_SOURCE[0]}"`
export shdir=$(cd "$(dirname "$0")" && pwd)

[ -z $1 ] && msg_noarg && exit 1

# limits for log of work and errors
# (zap if size exceed and fill again from zero):
maxlog=25000000
maxerr=25000000

cfg=$1
sql=$2
prf=$3 # prefix for temp files name which will be created by every ISQL session; based on $HOSTNAME value, sample: '/var/tmp/logs.oltp30/oltp30_some_box.our_firm.ru'
sid=$4 # ISQL window (session) sequential number
rpt=$5 # final report where sid N1 has to ADD info about performance ($tmpdir/oltp30.report.txt)
fname=$6 # file_name_with_test_params
build=$7
conn_pool_support=$8
ainfo=$9 # file_name_this_host_info: 'cpu_2x4_ram_16' etc

#echo build=$build

# 26.10.2018: number of ISQL sessions can be greater than 999.
prf=$prf-$(echo `printf "%04d" $sid`)

# log where current acitvity of this ISQL will be:
log=$prf.log

# log where ERRORS will be for this ISQL:
err=$prf.err

# cumulative log with brief info about running process state:
sts=$prf.state.txt

rm -f $log $err $sts
>$log
>$err

#echo -e Config file \>$cfg\< parsing result:
echo 
echo log=$log
sho "SID=$sid. Read config file $cfg. Log: $log" $log

shopt -s extglob

######################
# AGAIN RE-READ CONFIG
######################

# not work: grep -e "^[  ]*[a-z]" ./oltp_config.30 | \
while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
      # | sed -e 's/^[ \t]*//'
      #echo Init in line: lsh=$lhs, rhs=$rhs

      lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
      rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
      #echo Try to declare lhs=rhs: lsh=$lhs, rhs=$rhs
      declare $lhs=$rhs
      if [ $? -gt 0 ]; then
          sho "param=$lhs, val=$rhs" $log
          sho "-------------------- SOMETHING WRONG IN YOUR CONFIG FILE ------------------" $log
          exit
      fi
    fi
done < <( sed -e 's/^[ \t]*//' $cfg | grep "^[^#;]" )

sho "SID=$sid. Config file $cfg parsed OK." $log


##############################################################################################################
# 12.08.2018
# Define name of .sql script that will be launched by THIS - and only this - command window.
# This is name like "/var/tmp/logs.oltp30/sql/tmp_sid_197.starter.sql" etc, and it will create CONTEXT VAR
# with session-level scope. Main script will be invoked from THIS starter, thus it will know
# sequential ID of THIS command window: 1, 2, 3, ..., $winq


#sid_starter_sql=$(dirname $sql)/tmp_sid_$sid.starter.sql
sid_starter_sql=$(dirname $sql)/tmp_starter.$(echo `printf "%04d" $sid`).sql

sho "SID=$sid. Creating starter script sid_starter_sql='$sid_starter_sql'" $log

cat <<- EOF > $sid_starter_sql
        -- Generated auto by $shname
        -- Do _NOT_ edit. This script will be removed after test.
        set term ^;
        execute block as
        begin
            -- Define 'sequential number' of current ISQL session and make it be known 
            -- for main script and every business operations that are called from there:
            -- NB: name 'WORKER_SEQUENTIAL_NUMBER' is used in procedures for storing
            -- value in doc_list.worker_id for possible separation of scope that is avaliable
            -- for each ISQL session. Purpose - reduce frequency of lock conflicts.
            rdb\$set_context( 'USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER', '$sid' );
            rdb\$set_context( 'USER_SESSION', 'WORKER_SEQ_NUMB_4RESTORE', '$sid' );
        end^
        set term ;^
        -- Call main script that was created on prepare phase of oltp-emul scenario:
        in $sql;
EOF
##############################################################################################################

if [ $is_embed = 1 ]; then
  dbauth=
  dbconn=$dbnm
else
  dbauth="-user $usr -password $pwd"
  dbconn=$host/$port:$dbnm
fi


s1=$(date +%s)
#run_isql="$fbc/isql $dbconn -now -q -n -pag 9999 -i $sql $dbauth"
# since 12.08.2018
run_isql="$fbc/isql $dbconn -now -q -n -pag 9999 -i $sid_starter_sql $dbauth"
log_elapsed_time $s1 $log

cat << EOF >>$sts
$(date +'%Y.%m.%d %H:%M:%S'). Batch running now: $0 - check start command:
--- begin ---
$run_isql 1>>$log 2>>$err
--- end ---
EOF

[[ $sid = 1 ]] &&  echo This session *WILL* do performance report after test make selfstop.>>$sts

tmpauxsql=$tmpdir/tmp_$sid.aux.sql
tmpauxlog=$tmpdir/tmp_$sid.aux.log
tmpauxerr=$tmpdir/tmp_$sid.aux.err
tmpauxtmp=$tmpdir/tmp_$sid.aux.tmp

#tmpsidsql=$tmpdir/tmp_$sid.sql
#tmpsidlog=$tmpdir/tmp_$sid.log
#tmpsiderr=$tmpdir/tmp_$sid.err

tmpsidsql=$(dirname $sql)/tmp_$sid.sql
tmpsidlog=$(dirname $sql)/tmp_$sid.log
tmpsiderr=$(dirname $sql)/tmp_$sid.err

fblog_beg=$tmpdir/fb_log_when_test_started.$fb.log
fblog_end=$tmpdir/fb_log_when_test_finished.$fb.log

if [ $sid -eq 1 ]; then
  [[ $fb -eq 25 ]] && get_log_switch=action_get_ib_log || get_log_switch=action_get_fb_log

  run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"
  msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Gathering firebird.log before opening 1st window for obtaining new text which will appear in it during test."
  echo
  echo $msg
  echo $msg >>$rpt
  echo Command: $run_fbs >>$rpt
  $run_fbs 1>$fblog_beg 2>>$rpt
  echo Got:>>$rpt
  ls -l $fblog_beg 1>>$rpt 2>&1
  sho "SID=$sid. Extracted firebird.log BEFORE test: $(ls -l $fblog_beg)" $log
fi

if [ -z "$sleep_min" ]; then
    echo Parameter \'sleep_min\' was not defined in config and is assigned to 1.
    sleep_min=1
fi

random_delay=1
min_delay=$(( 1 + sid/25 ))
max_delay=$(( 2 + sid/max_cps ))

use_cps=0
if [[ $max_cps -ge 10 && $max_cps -le 100 ]]; then
    # Max rate of new attachments appearance set to some reasonable value.
    use_cps=1
fi

if [ $use_cps -eq 1 ]; then
    if [ $winq -gt $max_cps ]; then
        min_delay=$(( 1 + sid/max_cps ))
        max_delay=$(( 1 + sid/max_cps ))
        sho "SID=$sid. Use parameter 'max_cps'=$max_cps connections per second for evaluating delay." $sts
    else
        min_delay=1
        max_delay=4
        sho "SID=$sid. Number of sessions is too small, delay will be from $min_delay fo $max_delay seconds." $sts
    fi
else
    if [ $max_cps -eq 0 ]; then
        min_delay=0
        max_delay=0
        sho "SID=$sid. Config parameter 'max_cps' is 0. Heavy workload will be for big number of sessions." $sts
    else
        sho "SID=$sid. Config parameter 'max_cps' is $max_cps - out of reasonable scope. Delay will be from $min_delay fo $max_delay seconds." $sts
    fi
fi

sho "ISQL session SID=$sid. Start loop until limit of $(( warm_time + test_time )) minutes will expire." $log

packet=1
while :
do

  if [ $sid -gt 1 ]; then
      if [ $packet -eq 1 ]; then
          sho "SID=$sid. Point before execution packet $packet. Evaluate required delay before attempt to make attachment." $sts 
          if [ $min_delay -eq $max_delay ]; then
              random_delay=$min_delay
              msg_suff="Fixed delay for $min_delay seconds"
          else
              random_delay=$(( $min_delay+ ( RANDOM % (1+$max_delay-$min_delay) ) ))
              msg_suff="Random delay for $random_delay seconds from scope $min_delay ... $max_delay"
          fi
          sho "SID=$sid. $msg_suff" $sts

          sleep $random_delay
          sho "SID=$sid. Pause finished. Start ISQL to make attachment and work..." $sts
      else
          sho "SID=$sid. Packet=$k. Pause is skipped for all packets starting from 2nd." $sts
      fi
  else
      # 26.10.2018. If SID=1 will get client error and this message in STDERR:
      #     Statement failed, SQLSTATE = 08004
      #     connection rejected by remote interface
      # -- then no report will exist after test finish!
      sho "SID=1. SKIP pause before attempt to attach. This session will make reports thus we allow it to make attach w/o any delay." $sts
  fi

  if [ -s $log ]; then
    if [ $(stat -c%s $log) -gt $maxlog ]; then

      sho "SID=$sid. Size of $log = $(stat -c%s $log) - exceeds limit $maxlog, remove it" $sts
      rm -f $log $tmpsidlog $tmpsiderr
    fi
  fi
  if [ -s $err ]; then
    if [ $(stat -c%s $err) -gt $maxerr ]; then
      sho "SID=$sid. Size of $err = $(stat -c%s $err) - exceeds limit $maxerr, remove it" $sts
      rm -f $err
    fi
  fi

  sho "SID=$sid. Starting packet $packet." $sts
	cat <<- EOF >>$tmpsidlog
		RUNCMD: $run_isql
		STDLOG: $log
		STDERR: $err
	EOF

  cat $tmpsidlog
  cat $tmpsidlog>>$sts
  rm -f $tmpsidlog

  ##############################################################
  ####################   r u n    i s q l   ####################
  ##############################################################

  $run_isql 1>>$log 2>>$err

  sho "SID=$sid. Finish isql, packet No. $packet" $sts

  echo ------ last lines in isql STDOUT log: ------------>>$sts
  tail -15 $log | grep . | sed -e 's/^/    /' >>$sts
  echo ------ last lines in isql STDERR log: ------------>>$sts
  tail -15 $err | grep . | sed -e 's/^/    /' >>$sts
  echo -------------------------------------------------->>$sts

  if grep -E "database.*shutdown" $err > /dev/null ; then
      sho "SID=$sid. DATABASE SHUTDOWN DETECTED, session has finished its job." $sts
      ###################################################
      # ....................  e x i t ...................
      ###################################################
      break
  fi

  # 27.05.2016 Check whether server crashed during this round:
  # count number of lines 'error reading / writing from/to connection'
  # in the %err% file. If this number exceeds config parameter then
  # we TERMINATE further execution of test.

  crash_pattern="SQLSTATE = 08003\|SQLSTATE = 08006"
  crashes_cnt=$(grep -i -c -e "$crash_pattern" $err)
  if [ $crashes_cnt -gt 5 ] ; then
      sho "SID=$sid. Connection problem detected at least $crashes_cnt times, pattern = $crash_pattern. Session has finished its job." $sts
      ###################################################
      # ....................  e x i t ...................
      ###################################################
      break
  elif [ $crashes_cnt -gt 1 ]; then
      # When at least one of messages with SQLSTATE=08003 or 08006 appear we have to chek
      # that there wa not crash of firebird process since this test started. We can do it
      # by checking DIFFERENCE of $fblog_beg and $fblog_end for presense of string which
      # proves crash: firebird\fb_smp_server terminated abnormally. If such row exists then
      # test must be terminated ASAP.
      get_diff_fblog check_for_crash $fb $sid $fblog_beg $sts
      #                    1          2    3      4        5
  else
      sho "SID=$sid. No FB craches detected during last package was run." $sts
  fi

  # 42000 ==> -902 	335544569 	dsql_error 	Dynamic SQL Error
  # 42S22 ==> -206 	335544578 	dsql_field_err 	Column unknown
  # 42S02 ==> -204 	335544580 	table unknown: TMP // when forgen to add backstash befor tmp$foo
  # 22001 ==> arith overflow / string truncation
  # 39000 ==> function unknown: RDB // when forget to add backslash before rdb$get/rdb$set_context

  syntax_pattern="SQLSTATE = 42000\|SQLSTATE = 42S22\|SQLSTATE = 42S02\|SQLSTATE = 22001\|SQLSTATE = 39000"
  syntax_err_cnt=$(grep -i -c -e "$syntax_pattern" $err)
  if [ $syntax_err_cnt -gt 0 ] ; then
      sho "SID=$sid. Syntax / copliler errors found occured at least $syntax_err_cnt times, pattern = $syntax_pattern. Session has finished its job." $sts
      ###################################################
      # ....................  e x i t ...................
      ###################################################
      break
  fi
  
  run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth info_server_version info_implementation"

  cancel_test=0

  # 26.10.2018: unable to establish connect under extremely heavy workload, ~2000-3000 attachments.
  GET_FB_REPLY_MAX_TRIES=20
  for k in `seq $GET_FB_REPLY_MAX_TRIES`
  do
      if grep -i "test_was_cancelled" $log > /dev/null ; then
          msg="SID=$sid. Found sign of TEST CANCELLATION in STDOUT log, file $log."
          cancel_test=1
      elif grep -i "ex_test_cancel" $err > /dev/null ; then
          msg="SID=$sid. Found sign of TEST CANCELLATION in STDERR log, file $err."
          cancel_test=1
      fi
      if [ $cancel_test -eq 1 ]; then
          # ::: NB ::: do NOT forget double quotes here!
          sho "$msg" $sts
          break
      fi

      echo
      sho "SID=$sid. Check that FB is still alive: attempt to get server version using fbsvcmgr call. WAIT..." $sts
      #echo     Command: $run_fbs >>$sts
      #echo      STDLOG: $tmpsidlog >>$sts
      #echo      STDERR: $tmpsiderr >>$sts
      $run_fbs 1>$tmpsidlog 2>$tmpsiderr
      if [[ $k -gt 1 && $(stat -c%s $tmpsiderr) -eq 0 ]]; then
          sho "SID=$sid. Return to script. Problem RESOLVED after $k iterations." $sts
          echo Content of STDOUT received from fbsvcmgr:>>$sts
          echo ----------------------------------------->>$sts
          cat $tmpsidlog | sed -e 's/^/       /' >> $sts
          echo ----------------------------------------->>$sts
      else
          if [ $(stat -c%s $tmpsiderr) -gt 0 ]; then
              sho "SID=$sid. Problem EXISTS. Size of logs: STDOUT=$(stat -c%s $tmpsidlog), STDERR=$(stat -c%s $tmpsiderr)" $sts
          else
              sho "SID=$sid. Successful get FB version on first call." $sts
          fi
      fi

      #sho "SID=$sid. Size of logs: STDOUT=$(stat -c%s $tmpsidlog), STDERR=$(stat -c%s $tmpsiderr)" $sts
      # ::: NB ::: 26.10.2018
      # Under heavy workload (2500...3000 attachments) client can issue:
      # 'connection rejected by remote interface'
      # It is recommended to increase FB config parameter
      # connection_timeout in this case.
      # --------------------------------------------------------
      # When FB is really unavaliable then error message will be:
      # Unable to complete network request to host "localhost".
      # -Failed to establish a connection.  

      if [ -s $tmpsiderr ]; then
          sho "SID=$sid. Firebird is UNAVAILABLE. We have to check whether this problem relates to CLIENT or SERVER side." $sts
          cat $tmpsiderr
          echo Content of STDERR received from fbsvcmgr:>>$sts
          echo ----------------------------------------->>$sts
          cat $tmpsiderr | sed -e 's/^/       /' >> $sts
          echo ----------------------------------------->>$sts

          # Only 'connection rejected by remote interface' can be interpreted as TEMPORARY unavaliable!
          if grep -i "connection rejected" $tmpsiderr > /dev/null ; then
              sho "Failure seems to be on CLIENT-SIDE." $sts
              rm -f $tmpsiderr
              if [ $k -eq $GET_FB_REPLY_MAX_TRIES ] ; then
                  ###################################################
                  # ....................  e x i t ...................
                  ###################################################
                  sho "SID=$sid exceeds limit $GET_FB_REPLY_MAX_TRIES for attempts to get reply from FB server. Job is terminated." $sts
                  rm -f $sid_starter_sql
                  exit
              else
                  sho "Try to solve failure: iteration $k of total $GET_FB_REPLY_MAX_TRIES. Loop to next attempt after small pause." $sts
                  sleep 5
                  sho "Pause finished, LOOP to next iteration." $sts
              fi
          else
              ###################################################
              # ....................  e x i t ...................
              ###################################################
              sho "Failure seems to be on SERVER-SIDE. Job is terminated" $sts
              rm -f $tmpsiderr
              rm -f $sid_starter_sql
              exit
          fi
      else
          sho "SID=$sid. Firebird is alive, test can be continued." $sts
          cat $tmpsidlog>>$sts
          rm -f $tmpsidlog $tmpsiderr
          break
      fi
  done

  if [ $cancel_test -eq 1 ]; then

    sho "SID=$sid. Test has been CANCELLED." $sts

    # -------------------------------------------------------------------------
    # E X I T    i f   c u r r e n t    S I D     g r e a t e r   t h a n    1.
    # ~~~~~~~------------------------------------------------------------------
    if [ $sid -gt 1 ]; then
        sho "SID=$sid. Leave from loop because SID greater than 1." $sts
        break
    fi

    sho "SID=$sid. Forcedly drop all other attachments: change DB state to full shutdown." $rpt
    # rpt =$5 -- final report where sid N1 has to ADD info about performanc, its name: $tmpdir/oltpNN.report.txt

    run_fbs_dbshut="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_properties prp_shutdown_mode prp_sm_full prp_shutdown_db 0 dbname $dbnm"

    sho "Command: $run_fbs_dbshut" $rpt 1
    # ---------------------------------------------------
    # t e m p - l y    s h u t d o w n    d a t a b a s e
    # ---------------------------------------------------
    $run_fbs_dbshut 2>>$rpt
    sho "Return to shell. Database now must be in full shutdown state." $rpt 1

    run_fbs_dbattr="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth -action_db_stats -sts_hdr_pages -dbname $dbnm"
    $run_fbs_dbattr | grep -i attributes 1>>$rpt 2>&1

    # If we are here then one may sure that ALL attachments now are dropped and there is NO any activity of internal FB processes against DB.
    # Now we can turn DB online and continue work with it using only SINGLE attachment which SID=1

    if [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]; then
	#cat <<-EOF >$tmpauxtmp
	#	thread apply all bt
	#	shell $fbc/fb_lock_print -a -d $dbnm 1>$tmpdir/gdb-firebird-lock-print.txt 2>&1
	#	quit
	#	yes
	#EOF
	#gdb -q -x $tmpauxtmp $fbs/firebird $(pgrep firebird) 1>$tmpdir/gdb-firebird-stack-trace.txt 2>&1

        sho "SID=$sid. Check output of fb_lock_print: get header of LM for $dbnm:" $rpt
        while read line; do
            #sho "$line" $rpt
            echo -e "\t$line"
            echo $line >>$rpt
        done < <($fbc/fb_lock_print -c -d $dbnm)
        #$fbc/fb_lock_print -c -d $dbnm 1>$rpt 2>&1
    else
        sho "SID=$sid. Test uses REMOTE Firebird instance, utility fb_lock_print can not be used." $rpt
    fi
    #^-- [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]

    run_fbs_online="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_properties prp_db_online dbname $dbnm"
    sho "SID=$sid. Return DB to online state." $rpt 1
    sho "Command: $run_fbs_online" $rpt 1
    # -----------------------------------
    # r e t u r n     D B     o n l i n e 
    # -----------------------------------
    $run_fbs_online 2>>$rpt
    sho "Return to shell. Database now must be online." $rpt 1
    $run_fbs_dbattr | grep -i attributes 1>>$rpt 2>&1


    #sho "SID=$sid. Start final performance analisys." $sts

    psql=$prf.performance_report.tmp

    # $tmpdir/oltp30.report.txt -- it DOES contain now some info, we should NOT zap it!
    plog=$rpt

    rm -f $psql
    # ---- do NOT ---- rm $plog

    ################################################################################################
    ###  h o w     t e s t    w a s      f i n i s h e d ?   (normally / premature termination)  ###
    ################################################################################################
	cat <<- "EOF" >>$psql
		set heading off;
		select 'Test finish info:' as " " from rdb$database;
		set heading on;
		set list on;
		select
		   p.exc_info, p.dts_end, p.fb_gdscode, e.fb_mnemona,
		      coalesce(p.stack,'') as stack,
		         p.ip,p.trn_id, p.att_id,p.exc_unit
		from rdb$database r
		left join perf_log p on p.unit = 'sp_halt_on_error' -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
		left join fb_errors e on p.fb_gdscode = e.fb_gdscode
		order by p.dts_beg desc
		rows 1;
		set list off;

		set heading off;
		select 'Attachments that still alive:' as " " from rdb$database;
		set heading on;
		set list on;
		set blob all;
		set count on;
		select
		    a.mon$attachment_id as attachment_id
		    ,a.mon$server_pid as server_pid
		    ,a.mon$state as attachment_state
		    ,a.mon$remote_protocol as remote_protocol
		    ,a.mon$remote_address as remote_address
		    ,a.mon$remote_pid as remote_pid
		    ,a.mon$timestamp as attachment_timestamp
		    ,s.mon$state as statement_state
		    ,s.mon$timestamp as statement_timestamp
		    ,s.mon$sql_text as statement_sql
		from mon$attachments a
		left join mon$statements s on a.mon$attachment_id = s.mon$attachment_id
		where a.mon$attachment_id != current_connection and a.mon$remote_address is not null
		;
		set count off;
		set list off;
		commit;
		set transaction no wait;
		set list on;
		select
		    'Final data aggregation from PERF_FPLIT_nn tables to PERF_AGG' as msg
		    ,p.msg as result
		from srv_aggregate_perf_data( 1 ) as p; -- 1 = ignore stop-flag, do aggregation anyway.
		commit;
		set list off;
	EOF

    # psql = /var/tmp/logs.oltp30/oltp30_localhost.localdomain-001.performance_report.tmp

    echo $(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. START additional script after all sessions completed.

    $fbc/isql $dbconn -now -q -pag 9999 -i $psql $dbauth 1>>$plog 2>&1

    echo>>$plog
    echo $(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. FINISH additional script.



    rm -f $psql $tmpauxtmp $tmpauxsql $tmpauxerr

	cat <<- EOF >>$plog
	###############################################
	###  p e r f o r m a n c e    r e p o r t s ###
	###############################################
	EOF
	
	cat <<- EOF >>$plog
		
		Performance in TOTAL:
		=====================
		Get overall performance report for last test_time=$test_time minutes of activity.
		Value in column "avg_times_per_minute" in 1st row is OVERALL PERFORMANCE INDEX.
	EOF
	
	cat <<- "EOF" >>$psql
		set width action 35;
		select
		   business_action as action
		   ,avg_times_per_minute
		   ,avg_elapsed_ms
		   ,successful_times_done
		from rdb$database
		left join report_perf_total on 1=1;
		commit;
	EOF
	
	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1 $plog
	rm -f $psql


    #------------------------------------------------------------------------------------

	cat <<- EOF >>$plog
		
		Performance in DYNAMIC:
		=======================
	EOF
	
	cat <<- "EOF" >$psql
	    -- Get performance score for N equal time intervals, where N is defined by value 'test_intervals' config parameter
		set width itrv_no  7;
		set width itrv_beg 8;
		set width itrv_end 8;
		select cast(interval_no as smallint) as itrv_no
		      ,cnt_ok_per_minute
		      ,cnt_all
		      ,cnt_ok
		      ,cnt_err
		      ,cast(err_prc as numeric(8,2)) as err_prc
		      ,substring(cast(interval_beg as varchar(24)) from 12 for 8) itrv_beg
		      ,substring(cast(interval_end as varchar(24)) from 12 for 8) itrv_end
		from rdb$database
		left join report_perf_dynamic p on 1=1
		;
		commit;
	EOF
	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1 $plog
	rm -f $psql


    #------------------------------------------------------------------------------------

	cat <<- EOF >>$plog
		
		Performance for every MINUTE:
		=============================
		Extract values of ESTIMATED performance that was evaluated after EACH business
		operation finished.
		These data can help to find proper value of config parameter 'warm_time'.
		Current value of config parameter 'warm_time' = $warm_time.
	EOF

	cat <<- EOF >>$psql
        set width test_phase 20;
        select
            test_phase_name
            ,minutes_passed
            ,perf_score
            ,distinct_workers
        from report_perf_per_minute; -- since 27.03.2019
        commit;
	EOF

	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1 $plog
	rm -f $psql

    #------------------------------------------------------------------------------------

	cat <<- EOF >>$plog

		Preformance in DETAILS:
		=======================
		Get performance report with detaliation per units, for last test_time=$test_time minutes of workload.
		Fields:
		  CNT_ALL = total number of any level actions (business and internal) that were launched,
		  CNT_OK  = total number of any level actions that finished SUCCESSFULLY,
		  OK_MIN_MS, OK_MAX_MS, OK_AVG_MS = min, max and avg time of actions from CNT_OK.
	EOF

	cat <<- "EOF" >$psql
		set width unit 40;
		select
		    unit
		    ,cnt_all
		    ,cnt_ok
		    ,cnt_err
		    ,err_prc
		    ,ok_min_ms
		    ,ok_max_ms
		    ,ok_avg_ms
		    ,cnt_lk_confl
		    ,cnt_user_exc
		from rdb$database
		left join report_perf_detailed on 1=1;
		commit;
	EOF
	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1 $plog
	rm -f $psql
    #------------------------------------------------------------------------------------

    if [ $mon_unit_perf -eq 1 ]; then
		cat <<- EOF >>$plog
			
			Monitoring data, per application UNITS:
			=======================================
			Get report about gathered MONITOR tables data, detalization per UNITS.
			NOTE: source view for this report will be created only when config
			parameter 'mon_unit_perf' has value 1.
		EOF
		cat <<- "EOF" >$psql
			set width unit 31;
			select z.*
			from rdb$database
			left join report_stat_per_units z on 1=1;
			commit;
		EOF
		cat $psql >> $plog

		s1=$(date +%s)
		$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
		# Add timestamps of start and finish and how long last ISQL was:
		log_elapsed_time $s1 $plog
		rm -f $psql

		if [ $fb -gt 25 ]; then

			cat <<- EOF >>$plog
				
				Monitoring data, per TABLES and UNITS (avail. only in FB 3.0):
				==============================================================
				Get report about gathered MONITOR tables data, detalization  per TABLES and UNITS.
				NOTE: source view for this report will be created only when config
				parameter 'mon_unit_perf' has value 1. Avaliable only for FB 3.0.
			EOF

			cat <<- "EOF" >$psql
				set width unit 31;
				set width table_name 31;
				select z.*
				from rdb$database
				left join report_stat_per_tables z on 1=1;
				commit;
			EOF

			cat $psql >> $plog
			s1=$(date +%s)
			$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
			# Add timestamps of start and finish and how long last ISQL was:
			log_elapsed_time $s1 $plog
			rm -f $psql

		fi # fb is 30 or higher 
    elif [ $mon_unit_perf -eq 2 ]; then

		cat <<- "EOF" >>$plog
			
			Monitoring data: metadata cache size
			====================================
			Get report about metadata cache, attachments and statements memory usage.
			NOTE. Config parameter 'mon_unit_perf' must have value 2 for this report.
			Fields:
			  page cache memo used            = page cache total size, bytes:
			  metadata cache memo used        = metadata cache, bytes;
			  metadata cache percent of total = ratio between metadata cache and sum of metadata cache and page cache;
			  total attachments cnt           = total number of attachments, regardless of state;
			  active attachments cnt          = number of attachments with mon$state = 1;
			  running statements cnt          = number of statements that are operating with data from page cache, i.e. mon$state = 1;
			  stalled statements cnt          = number of statements that are waiting for client request for fetching, i.e. mon$state = 2;
			  memo used by attachments        = total of mon$memory_usage.mon$memory_used for attachment level, i.e. mon$stat_group = 1;
			  memo used by transactions       = total of mon$memory_usage.mon$memory_used for transaction level, i.e. mon$stat_group = 2;
			  memo used by statements         = total of mon$memory_usage.mon$memory_used for statement level, i.e. mon$stat_group = 3;
		EOF

		cat <<- "EOF" >$psql
			set heading off;
			set term ^;
			execute block returns(" " dm_info) as
			begin
			    " " = ascii_char(10) || ( select p.page_cache_info from srv_get_page_cache_info p ) ;
			    suspend;
			end
			^
			set term ;^
			set heading on;
			select
			    measurement_timestamp as "measurement_dts" -- 21.04.2019 do NOT use alias with SPACES for the 1st field of resultset!
			    ,measurement_elapsed_ms as "measurement duration ms"
			    ,page_cache_memo_used as "page cache memo used"
			    ,metadata_cache_memo_used as "metadata cache memo used"
			    ,metadata_cache_percent_of_total as "metadata cache percent of total"
			    ,total_attachments_cnt as "total attachments cnt"
			    ,active_attachments_cnt as "active attachments cnt"
			    ,running_statements_cnt as "running statements cnt"
			    ,stalled_statements_cnt as "stalled statements cnt"
			    ,memo_used_by_attachments as "memo used by attachments"
			    ,memo_used_by_transactions as "memo used by transactions"
			    ,memo_used_by_statements as "memo used by statements"
			from report_cache_dynamic d;
			-- select d.* from report_cache_dynamic d;
			commit;
		EOF
		cat $psql >> $plog
		
		s1=$(date +%s)
		$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
		# Add timestamps of start and finish and how long last ISQL was:
		log_elapsed_time $s1 $plog
		rm -f $psql
    else
		cat <<- EOF >>$plog
		
			Config parameter mon_unit_perf=0, data from MON$ tables were NOT gathered.
			==========================================================================
		EOF
    fi # mon_unit_perf = 1 | 0
	rm -f $psql

	cat <<- EOF >>$plog
		
		Exceptions occured during test was in run:
		==========================================
	EOF

	cat <<- "EOF" >>$psql
		set width fb_mnemona 31;
		set width unit 40;
		select fb_mnemona, cnt, unit, fb_gdscode
		from rdb$database
		left join report_exceptions on 1=1;
	EOF

	cat $psql >> $plog
	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1 $plog
	rm -f $psql



	cat <<- EOF >>$plog
		
		Database and FB version info:
		=============================
	EOF
	cat <<- "EOF" >>$psql
		set list on;
		select * from mon$database;
		set list off;
		show version;
	EOF
    $fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    rm -f $psql


    if [ $run_db_statistics -eq 1 ]; then
		run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth -action_db_stats -sts_data_pages -sts_idx_pages -sts_record_versions -dbname $dbnm"
		cat <<- EOF >>$plog
			
			Obtain database statistics after test.
			======================================
			Command: $run_fbs
		EOF
		msg="SID=$sid. Gather database statistics"
		echo $(date +'%Y.%m.%d %H:%M:%S'). $msg - START.

		s1=$(date +%s)
		$run_fbs 1>>$plog 2>&1
		# Add timestamps of start and finish and how long last action was:
		log_elapsed_time $s1 $plog
		
		echo $(date +'%Y.%m.%d %H:%M:%S'). $msg - FINISH.
    else
		cat <<- EOF >>$plog
			
			Database statistics was not gathered, see config parameter 'run_db_statistics'.
			===============================================================================
		EOF
    fi

    if [ $run_db_validation -eq 1 ]; then
		skip_val_list="(AGENTS|BUSINESS_OPS|DOC_STATES|FB_ERRORS|EXT_STOPTEST|SETTINGS|OPTYPES|RULES_FOR_%|PHRASES|TMP\$%|MON%|WARE%|Z_%)"
		run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth -action_validate -dbname $dbnm -val_lock_timeout 1 -val_tab_excl $skip_val_list"
		cat <<- EOF >>$plog
			
			Online validation of database.
			==============================
			Command: $run_fbs
		EOF
		msg="SID=$sid. Database online validation"
		echo $(date +'%Y.%m.%d %H:%M:%S'). $msg - START.

		s1=$(date +%s)
		$run_fbs 1>>$plog 2>&1
		# Add timestamps of start and finish and how long last action was:
		log_elapsed_time $s1 $plog

		echo $(date +'%Y.%m.%d %H:%M:%S'). $msg - FINISH.
    else
		cat <<- EOF >>$plog
			
			Database validation was not performed, see config parameter 'run_db_validation'.
			================================================================================
		EOF
    fi

    run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"
    msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Gathering firebird.log after test finished."
    echo $msg

	cat <<- EOF >>$plog
		
		$msg
		Command: $run_fbs
	EOF

    $run_fbs 1>$fblog_end 2>>$plog

	cat <<- EOF >>$plog
		Check new firebird.log:
	EOF
	
    ls -l $fblog_end 1>>$plog 2>&1

    msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Comparison of old and new firebird.log (get messages that appeared during test)."
    echo $msg

	cat <<- EOF >>$plog
		
		$msg
	EOF

    echo --- start of diff output --- >> $plog
    diff --unchanged-line-format="" --new-line-format=":%dn: %L"  $fblog_beg $fblog_end 1>>$plog 2>&1
    echo --- end of diff output --- >> $plog
    rm -f $fblog_beg $fblog_end
  
    #msg="$(date +'%Y.%m.%d %H:%M:%S'). Done."
    #echo $msg>>$sts

    sho "SID=$sid. Removing all ISQL logs according to value of config 'remove_isql_logs' setting" $plog

    # 335544558    check_constraint    Operation violates CHECK constraint @1 on view or table @2.
    # 335544347    not_valid    Validation error for column @1, value "@2".
    # 335544665 unique_key_violation (violation of PRIMARY or UNIQUE KEY constraint "..." on table ...") // if table has unique constraint
    # 335544349 no_dup (attempt to store duplicate value (visible to active transactions) in unique index "***") // if table has only unique index

    log_ptn=$tmpdir/oltp$(($fb))_**.**
    log_cnt=$(ls $log_ptn | wc -l)

    case $remove_isql_logs in
        never)
            msg="$log_cnt logs of every ISQL session are preserved, see config setting 'remove_isql_logs'"
        ;;
        always)
            msg="$log_cnt logs of every ISQL session are removed, see config setting 'remove_isql_logs'"
            rm -f $log_ptn
        ;;
        if_no_severe_errors)
            msg="Remove $log_cnt logs of every ISQL session if there were no serious errors, see config setting 'remove_isql_logs'"
        ;;
    esac

    echo $msg
    echo $msg >> $plog

    rm -f $psql
	cat <<- "EOF" >>$psql
          -- Checking query:
          set list on;
          select iif( exists( select *
                    from v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
                    where -- ::: NB ::: added "0" to the list of severe gdscodes! SuperClassic 3.0 trouble.
                        p.fb_gdscode in ( 0, 335544558, 335544347, 335544665, 335544349 )
                        and p.dts_beg > (
                            select x.dts_beg
                            from perf_log x -- 12.10.2018: do NOT replace here "perf_log" with "v_perf_log"
                            where x.unit='perf_watch_interval'
                            order by x.dts_beg desc
                            rows 1
                        )
                 ),
            'SEVERE_ERRORS_EXIST!',
            'NO_SEVERE_ERRORS_FOUND' ) as errors_checking_result
          from rdb$database;
	EOF

    if [ "$remove_isql_logs" == "if_no_severe_errors" ]; then
        $fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
        if grep -i "NO_SEVERE_ERRORS_FOUND" $plog > /dev/null ; then
            rm -f $log_ptn
        fi
    fi

    rm -f $psql


	if [ -n "$fname" ] ; then
		cat <<- EOF > $psql
		  set heading off;
		  select report_file from srv_get_report_name('$fname', '$build', $winq);
		EOF
                if [ $conn_pool_support -eq 1 ]; then
		    # ::: NB ::: 17.11.2018
		    # SP srv_get_report_name calls sys_get_fb_arch which uses ES/EDS in order to define FB arch.
		    # WHen using this in Firebird 2.5 with support of CONNECTIONS POOL then we have to clear
		    # manuall its connection pool, otherwise one EDS connection will remain infinitely.
                    echo -e "ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;">>$psql
                fi
                
		echo Evaluate new name of final report.
		run_isql="$fbc/isql $dbconn -i $psql -q -nod -n -c 256 $dbauth"
		$run_isql 1>$tmpsidlog 2>$tmpsiderr
		
		# Wrong: one trailing space will be included into varable content:
		# ----- do not --- log_with_params_in_name=`grep -v "^$" $tmpsidlog`
		
		if [ -s $tmpsiderr ]; then
			echo ERROR occured while defining name of final report:
			cat $tmpsiderr
		else
			log_with_params_in_name=`grep -v "^$" $tmpsidlog | sed 's/[ \t]*$//'`
			if [ -n "$ainfo" ]; then
			  # Suffix for adding at the end of report name: host location, hardware specific
			  # FB instance info etc (useful when analyze lot of logs).
			  # Make config parameter 'file_name_with_test_params\ commented if this is not needed.
			  log_with_params_in_name=${log_with_params_in_name}_$ainfo
			fi
			log_with_params_in_name=$tmpdir/$log_with_params_in_name.txt

                        #sho "Final report see in file: $log_with_params_in_name" $plog
			echo Report will be written into file: 
			echo $log_with_params_in_name
			rm -f $log_with_params_in_name $psql $tmpsidlog $tmpsiderr
			mv $plog $log_with_params_in_name
			plog=$log_with_params_in_name
		fi
	else
		cat <<- EOF > $tmpauxtmp
			New report has been saved with the same name as old one thus overwriting it.
			You have to change config parameter 'file_name_with_test_params' to 'regular' or 'benchmark'
			if every new report should be saved to new name. In that case final report file will contain
			info about current FB, DB and test settings.
		EOF
		cat $tmpauxtmp
		cat $tmpauxtmp>>$plog
	fi
	rm -f $tmpdir/1stoptest.tmp.sh
	break
  fi
  # end of: $cancel_test= 1

  sho "SID=$sid. Finished packet $packet" $sts

  packet=$((packet+1))
done

sho "SID=$sid. Bye-by from $shname" $sts
rm -f $sid_starter_sql
if [ $sid -eq 1 ]; then
    if [ -s $plog ]; then
	#ls -l $plog >> $sts
	cat <<- EOF

		Final report see in: 
		####################
		$plog
		####################

	EOF
	sleep 1
	touch $plog
    fi
fi
exit
