#!/bin/bash

# limits for log of work and errors
# (zap if size exceed and fill again from zero):
maxlog=25000000
maxerr=25000000

cfg=$1
sql=$2
prf=$3
sid=$4 # ISQL window (session) sequential number
rpt=$5 # final report where sid N1 has to ADD info about performance ($tmpdir/oltp30.report.txt)
fname=$6 # file_name_with_test_params
build=$7
ainfo=$8 #file_name_this_host_info

#echo build=$build

#echo -e Config file \>$cfg\< parsing result:
shopt -s extglob
# not work: grep -e "^[  ]*[a-z]" ./oltp_config.30 | \
while IFS='=' read lhs rhs
do
  if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
    # | sed -e 's/^[ \t]*//'
    lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
    rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
    declare $lhs=$rhs
    #echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
  fi
done<$cfg

prf=$prf-$(echo `printf "%03d" $sid`)
# log where current acitvity of this ISQL will be:
log=$prf.log

# log where ERRORS will be for this ISQL:
err=$prf.err

# cumulative log with brief info about running process state:
sts=$prf.running_state.txt

rm -f $log $err $sts
>$log
>$err
if [ $is_embed = 1 ]; then
  dbauth=
  dbconn=$dbnm
else
  dbauth="-user $usr -password $pwd"
  dbconn=$host/$port:$dbnm
fi
run_isql="$fbc/isql $dbconn -now -q -n -pag 9999 -i $sql $dbauth"

cat << EOF >>$sts

echo $(date +'%H:%M:%S'). Batch running now: $0 - check start command:
--- beg of command for launch isql ---
$run_isql 1>>$log 2>>$err
--- end of command for launch isql ---

EOF

[[ $sid = 1 ]] &&  echo This session *WILL* do performance report after test make selfstop.>>$sts

tmpsidsql=$tmpdir/tmp_$sid.sql
tmpsidlog=$tmpdir/tmp_$sid.log
tmpsiderr=$tmpdir/tmp_$sid.err

fblog_beg=$tmpdir/fb_log_when_test_started.$fb.log
fblog_end=$tmpdir/fb_log_when_test_finished.$fb.log

if [ $sid -eq 1 ]; then
  [[ $fb -eq 25 ]] && get_log_switch=action_get_ib_log || get_log_switch=action_get_fb_log

  run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"
  msg="$(date +'%H:%M:%S'). SID=$sid. Gathering firebird.log before opening 1st window for obtaining new text which will appear in it during test."
  echo
  echo $msg
  echo $msg >>$rpt
  echo Command: $run_fbs >>$rpt
  $run_fbs 1>$fblog_beg 2>>$rpt
  echo Got:>>$rpt
  ls -l $fblog_beg 1>>$rpt 2>&1
  ls -l $fblog_beg
fi

echo
echo $(date +'%H:%M:%S'). Intro separate ISQL session, sid=$sid.
if [ $winq -gt 1 ]; then
  echo Take initial random pause. . .
  #echo TEMPLY DISABLED, UNCOMMENT LATER.
  sleep $[ ( $RANDOM % 8 )  + 2 ]s
fi
echo $(date +'%H:%M:%S'). "SID=$sid. Start loop until limit of $(( warm_time + test_time )) minutes will expire."

packet=1
while :
do
  #echo stat=$(stat -c%s $log) 
  #echo maxlog=$maxlog
  if [ -s $log ]; then
    if [ $(stat -c%s $log) -gt $maxlog ]; then

      # Before removing log we have to save in database data about performance
      # that we have evaluated on-the-fly in this session after each call
      # of business operation:
      msg="$(date +'%H:%M:%S'). Preserving data about estimated performance for displaying later in final report."
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
      rm -f $log $tmpsidlog
    fi
  fi
  if [ -s $err ]; then
    if [ $(stat -c%s $err) -gt $maxerr ]; then
      echo size of $err = $(stat -c%s $err) - exceeds limit $maxerr, remove it >> $sts
      rm -f $err
    fi
  fi

  [[ $packet -gt 1 ]] && echo ------------------------------------------
  echo $(date +'%H:%M:%S'). SID=$sid. Start isql, packet No. $packet
  echo Command: $run_isql
  echo Redirection of STDOUT to: $log
  echo Redirection of STDERR to: $err

  ##############################################################
  ####################   r u n    i s q l   ####################
  ##############################################################
  $run_isql 1>>$log 2>>$err
  
  #echo Done.
  #echo Size of $log: $(stat -c%s $log)
  #echo Size of $err: $(stat -c%s $err)
  echo $(date +'%H:%M:%S'). SID=$sid. Finish isql, packet No. $packet

  if grep -E "database.*shutdown" $err > /dev/null ; then
    msg="$(date +'%H:%M:%S'). DATABASE SHUTDOWN DETECTED, test has been cancelled."
    echo $msg
    echo $msg>>$sts
    exit
  fi

  run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth info_server_version info_implementation"
  msg="$(date +'%H:%M:%S'). SID=$sid. Check that FB is still alive: ask server version."
  echo
  echo $msg
  echo $msg>>$sts

  $run_fbs 1>$tmpsidlog 2>&1

  cat $tmpsidlog>>$sts
  if grep -i "connection rejected" $tmpsidlog > /dev/null ; then
    cat $tmpsidlog
    msg="$(date +'%H:%M:%S'). Server unavaliable, test has been cancelled."
    echo $msg
    echo $msg>>$sts
    exit
  else
    msg="$(date +'%H:%M:%S').OK, Firebird is active, test can be continued."
    echo $msg>>$sts
  fi

  if grep -i "ex_test_cancel" $err > /dev/null ; then
    msg="$(date +'%H:%M:%S'). SID=$sid. STOPFILE has non-zero size, test has been cancelled."
    echo $msg>>$sts
    echo $msg

    msg="Saving data about estimated performance for displaying later in final report."
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
    rm -f $tmpsidsql $tmpsidlog $tmpsiderr

    # -------------------------------------------------------------------------------------------------------
    # E X I T    i f   c u r r e n t    I S Q L    w i n d o w   h a s   I d   g r e a t e r   t h a n   "1".
    # -------------------------------------------------------------------------------------------------------
    if [ $sid -gt 1 ]; then
      echo Bye-bye from SID=$sid
      exit
    fi

    msg="$(date +'%H:%M:%S'). SID=$sid. Start final performance analysys."
    echo $msg >>$sts
    psql=$prf.performance_report.tmp

    # $tmpdir/oltp30.report.txt -- it DOES contain now some info, we should NOT zap it!
    plog=$rpt

    rm -f $psql
    # ---- do NOT ---- rm $plog

    ##########################################
    ###  t e s t    f i n i s h   i n f o  ###
    ##########################################
	cat <<- "EOF" >>$psql
		set heading off;
		select 'Test finish info:' as " " from rdb$database;
		set heading on;
		set list on;
		select
		   p.exc_info, p.dts_end, p.fb_gdscode, e.fb_mnemona,
		      coalesce(p.stack,'') as stack,
		         p.ip,p.trn_id, p.att_id,p.exc_unit
		from perf_log p
		left join fb_errors e on p.fb_gdscode = e.fb_gdscode
		where p.unit = 'sp_halt_on_error'
		order by p.dts_beg desc
		rows 1;
	EOF
    echo $(date +'%H:%M:%S'). SID=$sid. Output test finish state - START

    $fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    echo>>$plog

    rm -f $psql
    echo $(date +'%H:%M:%S'). SID=$sid. Output test finish state - FINISH


    ###############################################################################################
    ##########################   P e r f o r m a n c e    R e p o r t s    ########################
    ###############################################################################################

	cat <<- "EOF" >>$psql
	
		set heading off;
		select 'Performance TOTAL:' as " " from rdb$database;
		set heading on;
		--  Get overall performance report for last 3 hours of activity:
		--  Value in column "avg_times_per_minute" in 1st row is overall performance index.

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
	
		set heading off;
		select 'Performance in DYNAMIC:' as " " from rdb$database;
		set heading on;
		--  Get performance report with splitting data to 10 equal time intervals,
		--  for last 3 hours of activity:
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
		left join srv_mon_perf_dynamic p on
		-- where
		      p.business_action containing 'interval'
		      and p.business_action containing 'overall';
		commit;

		set heading off;
		select 'Performance for every MINUTE:' as " " from rdb$database;
		set heading on;
		-- Extract values of ESTIMATED performance that was evaluated after EACH business
		-- operation finished. View is base on table PERF_ESTIMATED which was filled up
		-- by every ISQL session after it finished and before it was terminated.
		-- These data can help to find proper value of config parameter 'warm_time'.
		-- Current value of config parameter 'warm_time' = %warm_time%.
		set width test_phase 10;
	EOF

	cat <<- EOF >>$psql
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

		--  Get performance report with detaliation per units, for last 3 hours of activity.
		--  "CNT_ALL" = total number of events when unit started,
		--  "CNT_OK"  = total number of events when unit finished successfully.
		--  "OK_MIN_MS", "OK_MAX_MS", "OK_AVG_MS" = min, max and average elapsed time of
		 --  successfully finished transactions which involved this unit in work.
		set heading off;
		select 'Performance in DETAILS:' as " " from rdb$database;
		set heading on;
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

    echo $(date +'%H:%M:%S'). SID=$sid. Analyzing performance log table - START.

    $fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    rm -f $psql
      
    echo>>$plog
    echo $(date +'%H:%M:%S'). SID=$sid. Analyzing performance log table - FINISH.


    if [ $mon_unit_perf -eq 1 ]; then
		cat <<- "EOF" >>$psql
			-- Get report about gathered MONITOR tables data, detalization per UNITS.
			-- NOTE: source view for this report will be created only when config
			-- parameter 'mon_unit_perf' has value 1.
			set heading off;
			select 'Monitoring data, per application UNITS:' as " " from rdb$database;
			set heading on;
			set width unit 31;
			select z.*
			from rdb$database
			left join srv_mon_stat_per_units z on 1=1;
			commit;
		EOF

      if [ $fb -eq 30 ]; then
		cat <<- "EOF" >>$psql
		  -- Get report about gathered MONITOR tables data, detalization  per TABLES and UNITS.
		  -- NOTE: source view for this report will be created only when config
		  -- parameter 'mon_unit_perf' has value 1. Avaliable only for FB 3.0.
		  set heading off;
		  select 'Monitoring data, per TABLES and UNITS (avail. only in FB 3.0):' as " " from rdb$database;
		  set heading on;
		  set width unit 31;
		  set width table_name 31;
		  select z.*
		  from rdb$database
		  left join srv_mon_stat_per_tables z on 1=1;
		  commit;
		EOF
      fi # fb = 30 

      msg="SID=$sid. Analyzing gathered MONITOR data"
      echo $(date +'%H:%M:%S'). $msg - START.

      $fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
      rm -f $psql

      echo>>$plog
      echo $(date +'%H:%M:%S'). $msg - FINISH.

    else
		cat <<- EOF >>$plog
		  Config parameter mon_unit_perf=0, data from MON$ tables were NOT gathered.
		EOF
    fi # mon_unit_perf = 1 | 0

	rm -f $psql
	cat <<- "EOF" >>$psql
		set heading off;
		select 'Exceptions occured during test was in run:' as " " from rdb$database;
		set heading on;
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

    msg="SID=$sid. Analyzing exceptions while test was running"
    echo $(date +'%H:%M:%S'). $msg - START.

    $fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth 1>>$plog 2>&1
    rm -f $psql

    echo>>$plog
    echo $(date +'%H:%M:%S'). $msg - FINISH.

    rm -f $psql
	cat <<- "EOF" >>$psql
		set heading off;
		select 'Get info about database and FB version:' as " " from rdb$database;
		set heading on;
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
			Command: $run_fbs
		EOF
		msg="SID=$sid. Gather database statistics"
		echo $(date +'%H:%M:%S'). $msg - START.
		$run_fbs 1>>$plog 2>&1
		echo $(date +'%H:%M:%S'). $msg - FINISH.
    else
		cat <<- EOF >>$plog
			Database statistics was not gathered, see config parameter 'run_db_statistics'.
		EOF
    fi

    if [ $run_db_validation -eq 1 ]; then
		skip_val_list="(AGENTS|BUSINESS_OPS|DOC_STATES|FB_ERRORS|EXT_STOPTEST|SETTINGS|OPTYPES|RULES_FOR_%|PHRASES|TMP\$%|MON%|WARE%|Z_%)"
		run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth -action_validate -dbname $dbnm -val_lock_timeout 1 -val_tab_excl $skip_val_list"
		cat <<- EOF >>$plog
			Online validation of database.
			Command: $run_fbs
		EOF
		msg="SID=$sid. Database online validation"
		echo $(date +'%H:%M:%S'). $msg - START.
		$run_fbs 1>>$plog 2>&1
		echo $(date +'%H:%M:%S'). $msg - FINISH.
    else
		cat <<- EOF >>$plog
			Database validation was not performed, see config parameter 'run_db_validation'.
		EOF
    fi

    run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth $get_log_switch"
    msg="$(date +'%H:%M:%S'). SID=$sid. Gathering firebird.log after test finished."
    echo $msg
    echo $msg >>$plog
    echo Command: $run_fbs>>$plog
    $run_fbs 1>$fblog_end 2>>$plog
    echo Got:>>$plog
    ls -l $fblog_end 1>>$plog 2>&1

    msg="$(date +'%H:%M:%S'). SID=$sid. Comparison of old and new firebird.log (get messages that appeared during test)."
    echo $msg
    echo $msg >>$plog
    echo --- start of diff output --- >> $plog
    diff --unchanged-line-format="" --new-line-format=":%dn: %L"  $fblog_beg $fblog_end 1>>$plog 2>&1
    echo --- end of diff output --- >> $plog
    rm -f $fblog_beg $fblog_end
  
    msg="$(date +'%H:%M:%S'). Done."
    echo $msg>>$sts
    echo $msg>>$plog

    echo $(date +'%H:%M:%S'). SID=$sid. Removing all ISQL logs according to value of config 'remove_isql_logs' setting...

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
                    from perf_log p
                    where -- ::: NB ::: added "0" to the list of severe gdscodes! SuperClassic 3.0 trouble.
                        p.fb_gdscode in ( 0, 335544558, 335544347, 335544665, 335544349 )
                        and p.dts_beg > (
                            select x.dts_beg
                            from perf_log x
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
		echo Evaluate new name of final report.

		run_isql="$fbc/isql $dbconn -i $psql -q -nod -n -c 256 $dbauth"
		$run_isql 1>$tmpsidlog 2>&1
		# Wrong: one trailing space will be included into varable content:
		# ----- do not --- og_with_params_in_name=`grep -v "^$" $tmpsidlog`

		log_with_params_in_name=`grep -v "^$" $tmpsidlog | sed 's/[ \t]*$//'`
        if [ -n "$ainfo" ]; then
          # Suffix for adding at the end of report name: host location, hardware specific
          # FB instance info etc (useful when analyze lot of logs).
          # Make config parameter 'file_name_with_test_params\ commented if this is not needed.
          log_with_params_in_name=${log_with_params_in_name}_$ainfo
        fi
		log_with_params_in_name=$tmpdir/$log_with_params_in_name.txt
		
        echo Report will be written into file: 
        echo $log_with_params_in_name

		rm -f $log_with_params_in_name $psql $tmpsidlog
		mv $plog $log_with_params_in_name
		plog=$log_with_params_in_name
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
		$(date +'%H:%M:%S'). Bye-bye from SID=1. Test has been FINISHED.
		------------------------------------------------------------
		
		Final report see in: 
		####################
		$plog
		####################
		Press any key to EXIT. . .
	EOF

    exit

  fi

  packet=$((packet+1))
done
