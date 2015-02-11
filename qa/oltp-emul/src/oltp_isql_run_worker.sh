#!/bin/bash

# limits for log of work and errors
# (zap if size exceed and fill again from zero):
maxlog=15000000
maxerr=15000000

cfg=$1
sql=$2
prf=$3
sid=$4 # ISQL window (session) sequential number

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

echo>>$sts
echo $(date +'%H:%M:%S'). Batch running now: $0 - check start command:>>$sts
echo --- beg of command for launch isql --->>$sts
echo -e "$run_isql 1\>\>$log 2\>\>$err"  >>$sts
echo --- end of command for launch isql --->>$sts
echo>>$sts

[[ $sid = 1 ]] &&  echo This session *WILL* do performance report after test make selfstop.>>$sts

# todo: take initial random delay = 2 + (%random% %% 8^)
echo
echo $(date +'%H:%M:%S'). Intro separate ISQL session, sid=$sid. Take initial random pause. . .
sleep $[ ( $RANDOM % 8 )  + 2 ]s
echo $(date +'%H:%M:%S'). "SID=$sid. Start loop until limit of $(( warm_time + test_time )) minutes will expire."

packet=1
while :
do
  if [ $(stat -c%s $log) -gt $maxlog ]; then
    echo size of $log = $(stat -c%s $log) - exceeds limit $maxlog, remove it >> $sts
    rm -f $log
  fi 
  if [ $(stat -c%s $err) -gt $maxerr ]; then
    echo size of $err = $(stat -c%s $err) - exceeds limit $maxerr, remove it >> $sts
    rm -f $err
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

  if grep -i "shutdown" $err > /dev/null ; then
    msg="$(date +'%H:%M:%S'). DATABASE SHUTDOWN DETECTED, test has been cancelled."
    echo $msg>>$sts
    exit
  fi

  if grep -i "ex_test_cancel" $err > /dev/null ; then
    msg="$(date +'%H:%M:%S'). SID=$sid. STOPFILE has non-zero size, test has been cancelled."
    echo $msg>>$sts
    echo $msg
    if [ $sid = 1 ]; then
      msg="$(date +'%H:%M:%S'). SID=$sid. Start final performance analysys."
      echo $msg >>$sts
      psql=$prf.performance_report.tmp
      plog=$prf.performance_report.txt
      rm -f $psql $plog

      echo $(date +'%H:%M:%S'). Created by $0, working window $sid.>$plog

      #############################################################################################
      ### w a s    t e s t    f i n i s h e d    w i t h    "c r i t i c a l     e r r o r s" ? ###
      #############################################################################################
      echo -e "-- 1. Was test finished due to timeout (i.e. normal) ?">>$psql
      echo>>$psql
      echo -e "set list on;"                                                         >>$psql
      echo -e "select iif( (select count(*) from z_halt_log) = 0"                    >>$psql
      echo -e "            ,'ALL OK, job stop reason: NORMAL (due to timeout), view Z_HALT_LOG is empty'"  >>$psql
      echo -e "            ,'BAD NEWS! At least one critical error found, check data in view Z_HALT_LOG'"  >>$psql
      echo -e "          ) as \"Test finish result:\""                               >>$psql
      echo -e "from rdb\$database;"                                                  >>$psql
      echo -e "set list off;"                                                        >>$psql
      echo>>$psql

      ###############################################
      ### o u t p u t    a l l   s e t t i n g s  ###
      ###############################################
      echo -e "-- 2. All used settings for this test run:">>$psql
      echo>>$psql
      echo -e "set heading off;set list on; select '' as \"All test settings:\" from rdb\$database; set list off;set heading on;">>$psql
      echo -e "set width category 12;"        >>$psql
      echo -e "set width setting 32;"         >>$psql
      echo -e "set width val 20;"             >>$psql
      echo -e "select s.working_mode as category, s.mcode as setting, s.svalue as val" >>$psql
      echo -e "from settings s"                                            >>$psql
      echo -e "where s.working_mode='COMMON'"                              >>$psql
      echo -e "union all"                                                  >>$psql
      echo -e "select s.working_mode, s.mcode as setting, s.svalue"        >>$psql
      echo -e "from settings s"                                            >>$psql
      echo -e "join ("                                                     >>$psql
      echo -e "    select s.svalue as working_mode"                        >>$psql
      echo -e "    from settings s where s.working_mode = 'INIT'"          >>$psql
      echo -e ") w on s.working_mode = w.working_mode;"                    >>$psql
      echo>>$psql


      ###############################################
      ###  p e r f o r m a n c e    r e p o r t s ###
      ###############################################
      echo -e "-- 3. Get performance report with splitting data to 10 equal time intervals,">>$psql
      echo -e "--    for last three hours of activity:">>$psql
      echo>>$psql
      echo -e "set heading off;set list on; select '' as \"Performance in DYNAMIC:\" from rdb\$database; set list off;set heading on;">>$psql
      echo -e "set width business_action 24;">>$psql
      echo -e "set width itrv_beg 8;">>$psql
      echo -e "set width itrv_end 8;">>$psql
      echo -e "select business_action,interval_no,cnt_ok_per_minute,cnt_all,cnt_ok,cnt_err,err_prc">>$psql
      echo -e "       ,substring(cast(interval_beg as varchar(24)) from 12 for 8) itrv_beg">>$psql
      echo -e "       ,substring(cast(interval_end as varchar(24)) from 12 for 8) itrv_end">>$psql
      echo -e "from srv_mon_perf_dynamic p">>$psql
      echo -e "where p.business_action containing 'interval' and p.business_action containing 'overall';">>$psql
      echo -e "commit;">>$psql
      echo>>$psql

      echo -e "-- 4. Get overall performance report for last three hours of activity:">>$psql
      echo -e "--    Value in column "avg_times_per_minute" in 1st row is overall performance index.">>$psql
      echo>>$psql
      echo -e "set heading off;set list on; select '' as \"Performance TOTAL:\" from rdb\$database; set list off;set heading on;">>$psql
      echo -e "set width business_action 35;">>$psql
      echo -e "select business_action, avg_times_per_minute, avg_elapsed_ms, successful_times_done, job_beg, job_end">>$psql
      echo -e "from srv_mon_perf_total;">>$psql
      echo>>$psql

      echo -e "set heading off;set list on; select '' as \"mon\$database and version info:\" from rdb\$database; set list off;set heading on;">>$psql
      echo -e "-- 5. Get info about database and FB version:">>$psql
      echo -e "set list on; select * from mon\$database; set list off;">>$psql
      echo -e "show version;">>$psql

      echo $(date +'%H:%M:%S'). SID=$sid. Analyzing performance log table - START.

      $fbc/isql $dbconn -now -q -n -pag 9999 -i $psql $dbauth -m -o $plog
      echo>>$plog
      echo $(date +'%H:%M:%S'). SID=$sid. Analyzing performance log table - FINISH.

      echo This report is result of:>>$plog
      cat $psql>>$plog
      rm -f $psql

      echo>>$plog
      echo "######################################################################################">>$plog
      echo>>$plog
      echo Obtain database statistics after test:>>$plog
      echo>>$plog
      run_fbs="$fbc/fbsvcmgr $host/$port:service_mgr $dbauth -action_db_stats -sts_data_pages -sts_idx_pages -sts_record_versions -dbname $dbnm"
      echo -e $run_fbs>>$plog
      echo $(date +'%H:%M:%S'). Gather database statistics - START.

      $run_fbs 1>>$plog

      echo $(date +'%H:%M:%S'). Gather database statistics - START.
      echo>>$plog
      msg="$(date +'%H:%M:%S'). Done."
      echo $msg>>$sts
      echo $msg>>$plog
    fi # sid=1

    echo Bye from SID=$sid.
    if [ $sid = 1 ]; then
      echo
      echo ------------------------------------------------------------
      echo $(date +'%H:%M:%S'). Test has been FINISHED. Press any key to EXIT. . .
      echo ------------------------------------------------------------
    fi

    exit
  fi

  packet=$((packet+1))
done
