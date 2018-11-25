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
  local dts=$(date +'%d.%m.%y %H:%M:%S')
  echo $dts. $msg
  echo $dts. $msg>>$log
}


log_elapsed_time() {
    local s1=$s1
    local plog=$2
    local s2=$(date +%s)
    local sd=$(date -u -d "0 $s2 sec - $s1 sec" +"%H:%M:%S")
    local msg="Done for $sd, from $(date -d @$s1 +'%d-%m-%Y %H:%M:%S') to $(date -d @$s2 +'%d-%m-%Y %H:%M:%S')."
    echo $msg >>$plog
}

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

#run_isql="$fbc/isql $dbconn -now -q -n -pag 9999 -i $sql $dbauth"
# since 12.08.2018
run_isql="$fbc/isql $dbconn -now -q -n -pag 9999 -i $sid_starter_sql $dbauth"


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


sho "ISQL session SID=$sid. Start loop until limit of $(( warm_time + test_time )) minutes will expire." $log

packet=1
while :
do

  if [ $sleep_max -gt 0 ]; then
      if [ $sid -gt 1 ]; then

          sho "SID=$sid. Point before execution packet $packet. Evaluate required delay before attempt to make attachment." $sts 
          
          min_delay=1
          if [ $max_cps -gt 0 ] ; then
              if [ $winq -gt $max_cps ]; then
                  min_delay=$(( 1 + $sid / $max_cps ))
                  max_delay=$(( 1 + $sid / $max_cps ))
              else
                  max_delay=30
              fi
              sho "SID=$sid. Use parameter 'max_cps'=$max_cps connections per second for evaluating." $sts
          else
              if [ $warm_time -eq 0 ]; then
                  max_delay=30
              else
                  min_delay=30
                  max_delay=$(( 60*$warm_time+30 ))
              fi
              sho "SID=$sid. Use parameter 'warm_time'=$warm_time minutes for evaluating." $sts
          fi
          if [ $min_delay -eq $max_delay ]; then
              random_delay=$min_delay
              msg_suff="Fixed delay for $min_delay seconds"
          else
              random_delay=$(( $min_delay+ ( RANDOM % (1+$max_delay-$min_delay) ) ))
              msg_suff="Random delay for $random_delay seconds from scope $min_delay ... $max_delay"
          fi
          sho "SID=$sid. $msg_suff" $sts

#          if [ $warm_time -gt 0 ]; then
#              random_delay=$(( 60 + ( RANDOM % ((1+$warm_time)*60) ) ))
#              sho "SID=$sid. Formula: 60 + ( RANDOM mod ((1 + warm_time)*60) ). Result: random_delay=$random_delay seconds." $sts
#          else
#              random_delay=$(( 1 + (RANDOM % 10) ))
#              sho "SID=$sid. Formula: (( 1 + (RANDOM mod 10) )), config parameter warm_time is zero. Result: random_delay=$random_delay seconds." $sts
#          fi

          sleep $random_delay
          sho "SID=$sid. Pause finished. Start ISQL to make attachment and work..." $sts
      else
          # 26.10.2018. If SID=1 will get client error and this message in STDERR:
          #     Statement failed, SQLSTATE = 08004
          #     connection rejected by remote interface
          # -- then no report will exist after test finish!
          sho "SID=1: SKIP pause before attempt to attach. This session will make reports thus we allow it to make attach w/o any delay." $sts
      fi
  fi

  if [ -s $log ]; then
    if [ $(stat -c%s $log) -gt $maxlog ]; then

      # Before removing log we have to save in database data about performance
      # that we have evaluated on-the-fly in this session after each call
      # of business operation:
      msg="$(date +'%Y.%m.%d %H:%M:%S'). Preserving data about estimated performance for displaying later in final report."
      echo $msg>>$sts
      echo $msg

      grep EST_OVERALL_AT_MINUTE_SINCE_BEG $log >$tmpsidlog
      while read s
      do
        a=( $s )
        echo insert into perf_estimated\( minute_since_test_start, success_count \) values\( ${a[2]}, ${a[1]}\)\;
      done < $tmpsidlog >$tmpsidsql
      echo commit\;>>$tmpsidsql

      $fbc/isql $dbconn -nod -q -n -i $tmpsidsql $dbauth 2>>$tmpsiderr

      echo size of $log = $(stat -c%s $log) - exceeds limit $maxlog, remove it >> $sts
      rm -f $log $tmpsidlog $tmpsiderr
    fi
  fi
  if [ -s $err ]; then
    if [ $(stat -c%s $err) -gt $maxerr ]; then
      echo size of $err = $(stat -c%s $err) - exceeds limit $maxerr, remove it >> $sts
      rm -f $err
    fi
  fi

	cat <<- EOF >>$tmpsidlog
		$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Starting packet $packet.
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
  #crashes_cnt=$(grep -i -c "elapsed time" $log)
  if [ $crashes_cnt -gt 5 ] ; then
      sho "SID=$sid. Connection problem found $crashes_cnt times, pattern = $crash_pattern. Session has finished its job." $sts
      ###################################################
      # ....................  e x i t ...................
      ###################################################
      break
  else
      sho "SID=$sid. No FB craches detected during last package was run." $sts
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
              exit
          fi
      else
          sho "SID=$sid. Firebird is alive, test can be continued." $sts
          cat $tmpsidlog>>$sts
          rm -f $tmpsidlog
          break
      fi
  done

  if [ $cancel_test -eq 1 ]; then

    sho "SID=$sid. Saving data about estimated performance for displaying later in final report." $sts

    grep EST_OVERALL_AT_MINUTE_SINCE_BEG $log >$tmpsidlog
    while read s
    do
        a=( $s )
        echo insert into perf_estimated\( minute_since_test_start, success_count \) values\( ${a[2]}, ${a[1]}\)\;
    done < $tmpsidlog >$tmpsidsql
    echo commit\;>>$tmpsidsql

    $fbc/isql $dbconn -nod -q -n -i $tmpsidsql $dbauth 2>>$tmpsiderr
    rm -f $tmpsidsql $tmpsidlog $tmpsiderr

    # -------------------------------------------------------------------------------------------------------
    # E X I T    i f   c u r r e n t    I S Q L    w i n d o w   h a s   I d   g r e a t e r   t h a n   "1".
    # -------------------------------------------------------------------------------------------------------
    if [ $sid -gt 1 ]; then
        sho "SID=$sid. Leave from loop because SID greater than 1." $sts
        break
    fi

    #run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth -action_db_stats -sts_data_pages -sts_idx_pages -sts_record_versions -dbname $dbnm"
    msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Forcedly drop all other attachments: change DB state to full shutdown."
    echo
    echo $msg
    # rpt =$5 -- final report where sid N1 has to ADD info about performanc, its name: $tmpdir/oltpNN.report.txt
    echo $msg >>$rpt

    # ---------------------------------------------------
    # t e m p - l y    s h u t d o w n    d a t a b a s e
    # ---------------------------------------------------
    run_fbs_dbshut="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_properties prp_shutdown_mode prp_sm_full prp_shutdown_db 0 dbname $dbnm"
    echo Command: $run_fbs_dbshut >>$rpt
    $run_fbs_dbshut 2>>$rpt

    run_fbs_dbattr="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth -action_db_stats -sts_hdr_pages -dbname $dbnm"
    $run_fbs_dbattr | grep -i attributes 1>>$rpt 2>&1
    
    # If we are here then one may sure that ALL attachments now are dropped and there is NO any activity of internal FB processes against DB.
    # Now we can turn DB online and continue work with it using only SINGLE attachment which SID=1

    msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Return DB online."
    echo $msg
    echo $msg >>$rpt
    # -----------------------------------
    # r e t u r n     D B     o n l i n e 
    # -----------------------------------
    run_fbs_online="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth action_properties prp_db_online dbname $dbnm"
    echo Command: $run_fbs_online >>$rpt

    $run_fbs_online 2>>$rpt
    $run_fbs_dbattr | grep -i attributes 1>>$rpt 2>&1

    
    msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Start final performance analysys."
    echo $msg >>$sts
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
		from perf_log p -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
		left join fb_errors e on p.fb_gdscode = e.fb_gdscode
		where p.unit = 'sp_halt_on_error'
		order by p.dts_beg desc
		rows 1;
		set list off;

		set heading off;
		select 'Attachments that still alive:' as " " from rdb$database;
		set heading on;
		set list on;
		set count on;
                select mon$attachment_id, mon$server_pid, mon$state, mon$remote_protocol, mon$remote_address, mon$remote_pid, mon$timestamp
                from mon$attachments where mon$attachment_id != current_connection and mon$remote_address is not null;
		set count off;
                set list off;

	EOF

    cat <<- EOF >$tmpauxtmp
                set list on;
                set term ^;
                -- get SQL statements 'create index ... on perf_split_NN' for applying them below (need for reports)
                execute block returns(" " varchar(32765)) as
                begin
                    for 
                        select sql_sttm from srv_gen_sql_4tmp_idx_perf_split into " "
                    do
                        suspend;
                end
                ^
                set term ;^
                commit;
                set list off;
EOF

    # Generate SQL code for create indexes on perf_split_NN tables 
    # (we need these indices only for reports):
    $fbc/isql $dbconn -now -q -n -i $tmpauxtmp $dbauth 1>$tmpauxsql 2>$tmpauxerr

    cat $tmpauxsql >> $psql
    # psql = /var/tmp/logs.oltp30/oltp30_localhost.localdomain-001.performance_report.tmp

    echo $(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. START additional script after all sessions completed.

    $fbc/isql $dbconn -now -q -pag 9999 -i $psql $dbauth 1>>$plog 2>&1

    echo>>$plog
    echo $(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. FINISH additional script.


    rm -f $psql $tmpauxtmp $tmpauxsql $tmpauxerr

    ###############################################################################################
    ##########################   P e r f o r m a n c e    R e p o r t s    ########################
    ###############################################################################################

	cat <<- EOF >>$plog
		
		Performance in TOTAL:
		=====================
		Get overall performance report for last test_time=$test_time minutes of activity.
		Value in column "avg_times_per_minute" in 1st row is OVERALL PERFORMANCE INDEX.
	EOF
	
	cat <<- "EOF" >>$psql
		set width action 35;
		select
		   business_action as action,
		   avg_times_per_minute,
		   avg_elapsed_ms,
		   successful_times_done,
		   job_beg,
		   job_end
		from rdb$database
		left join srv_mon_perf_total on 1=1;
		commit;
	EOF
	
	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1, $plog
	rm -f $psql


    #------------------------------------------------------------------------------------

	cat <<- EOF >>$plog
		
		Performance in DYNAMIC:
		=======================
		Get performance report with split data to 10 equal time intervals for 
		last test_time=$test_time minutes of activity.
	EOF
	
	cat <<- "EOF" >$psql
		set width action 24;
		set width itrv_no  7;
		set width itrv_beg 8;
		set width itrv_end 8;
		select business_action as action
		      ,cast(interval_no as smallint) as itrv_no
		      ,cnt_ok_per_minute
		      ,cnt_all
		      ,cnt_ok
		      ,cnt_err
		      ,cast(err_prc as numeric(8,2)) as err_prc
		      ,substring(cast(interval_beg as varchar(24)) from 12 for 8) itrv_beg
		      ,substring(cast(interval_end as varchar(24)) from 12 for 8) itrv_end
		from rdb$database
		left join srv_mon_perf_dynamic(20) p on -- 20 = number of intervals; default: 10
		-- where
		      p.business_action containing 'interval'
		      and p.business_action containing 'overall';
		commit;
	EOF
	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1, $plog
	rm -f $psql


    #------------------------------------------------------------------------------------

	cat <<- EOF >>$plog
		
		Performance for every MINUTE:
		=============================
		Extract values of ESTIMATED performance that was evaluated after EACH business
		operation finished. View is base on table PERF_ESTIMATED which was filled up
		by every ISQL session after it finished and before it was terminated.
		These data can help to find proper value of config parameter 'warm_time'.
		Current value of config parameter 'warm_time' = $warm_time.
	EOF

	cat <<- EOF >>$psql
		set width test_phase 10;
		select iif( minute_since_test_start <= $warm_time, 'WARM_TIME', 'TEST_TIME') test_phase
	EOF

	cat <<- "EOF" >>$psql
		     ,minute_since_test_start
		     ,avg_estimated
		     ,min_to_avg_ratio
		     ,max_to_avg_ratio
		     ,rows_aggregated
		     ,distinct_attachments -- 22.12.2015
		from z_estimated_perf_per_minute;
		commit;
	EOF
	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1, $plog
	rm -f $psql

    #------------------------------------------------------------------------------------

	cat <<- EOF >>$plog

		Preformance in DETAILS:
		=======================
		Get performance report with detaliation per units, for last test_time=$test_time minutes of workload.
		"CNT_ALL" = total number of any level actions (business and internal) that were launched,
		"CNT_OK"  = total number of any level actions that finished SUCCESSFULLY,
		"OK_MIN_MS", "OK_MAX_MS", "OK_AVG_MS" = min, max and avg time of actions from CNT_OK.
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
		    ,job_beg
		    ,job_end
		from rdb$database
		left join srv_mon_perf_detailed on 1=1;
		commit;
	EOF
	cat $psql >> $plog

	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1, $plog
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
			left join srv_mon_stat_per_units z on 1=1;
			commit;
		EOF
		cat $psql >> $plog

		s1=$(date +%s)
		$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
		# Add timestamps of start and finish and how long last ISQL was:
		log_elapsed_time $s1, $plog
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
				left join srv_mon_stat_per_tables z on 1=1;
				commit;
			EOF

			cat $psql >> $plog
			s1=$(date +%s)
			$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
			# Add timestamps of start and finish and how long last ISQL was:
			log_elapsed_time $s1, $plog
			rm -f $psql

		fi # fb is 30 or higher 
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
		set width dts_beg 16;
		set width dts_end 16;
		select fb_mnemona, cnt, unit, fb_gdscode
		      ,substring(cast( dts_min as varchar(24)) from 1 for 16) dts_beg
		      ,substring(cast( dts_max as varchar(24)) from 1 for 16) dts_end
		from rdb$database
		left join srv_mon_exceptions on 1=1;
	EOF

	cat $psql >> $plog
	s1=$(date +%s)
	$fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
	# Add timestamps of start and finish and how long last ISQL was:
	log_elapsed_time $s1, $plog
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
		log_elapsed_time $s1, $plog
		
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
		log_elapsed_time $s1, $plog

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
  
    msg="$(date +'%Y.%m.%d %H:%M:%S'). Done."
    echo $msg>>$sts

	cat <<- EOF >>$plog
		
		$msg
		$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Removing all ISQL logs according to value of config 'remove_isql_logs' setting...
	EOF

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
		echo New report has been saved with the same name as old one thus overwriting it.
		echo Change config parameter 'file_name_with_test_params' to 'regular' or 'benchmark'
		echo if every new report should be saved to new name. In that case final report file
		echo will contain info about current FB, DB and test settings.
	fi
	echo

	rm -f $tmpdir/1stoptest.tmp.sh
	
    cat <<- EOF
		------------------------------------------------------------
		$(date +'%Y.%m.%d %H:%M:%S'). Bye-bye from SID=1. Test has been FINISHED.
		------------------------------------------------------------
		
		Final report see in: 
		####################
		$plog
		####################
		Press any key to EXIT. . .
	EOF
      pause
      break
  fi
  # end of: $cancel_test= 1

  msg="$(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Finished packet $packet "
  echo $msg
  echo $msg>>$sts

  packet=$((packet+1))
done

echo $(date +'%Y.%m.%d %H:%M:%S'). SID=$sid. Bye-by from $shname
rm -f $sid_starter_sql
exit
