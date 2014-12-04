#!/bin/bash

function pause(){
   read -p "$*"
}
msg_noarg() {
  clear
  echo Specify:
  echo
  echo arg#1 = 25 or 30 - version of Firebird;
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

msg_novar() {
  echo
  echo -e At least one variable: \>$1\< - is NOT defined. Check config file $cfg.
  echo
  echo Script is now terminated.
}

msg_nofile() {
  echo
  echo At least one of Firebird command line utilities NOT FOUND in the folder
  echo -e defined by variable \'fbc\' = \>\>\>$fbc\<\<\<
  echo
  echo This folder has to contain following executable files: isql, gfix, fbsvcmgr
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


# -------------------------------  d b _ c r e a t e -----------------------------------

db_create() {
  echo
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.
  local tmperr=$tmpdir/tmp_create_dbnm.err
  local tmpsql=$tmpdir/tmp_create_dbnm.sql
  local tmplog=$tmpdir/tmp_create_dbnm.log
  local run_isql
  rm -f $tmpsql $tmplog $tmperr
  if [ $is_embed == 1 ]; then
    echo -e create database \'$dbnm\' page_size 8192\; commit\; show database\; exit\;>$tmpsql
    run_isql="$fbc/isql -q -i $tmpsql"
  else
    #echo set echo on\;>>$tmpsql
    echo -e create database \'$host/$port:$dbnm\'>>$tmpsql
    echo -e page_size 8192' '>>$tmpsql
    echo -e user \'$usr\' password \'$pwd\'\;>>$tmpsql
    echo commit\; show database\; exit\;>>$tmpsql
    run_isql="$fbc/isql -q -i $tmpsql"
  fi
  echo Command to be run:
  echo $run_isql
  echo Content of script $tmpsql:
  echo ---------------------------------------
  cat $tmpsql
  echo ---------------------------------------

  $run_isql 1>$tmplog 2>$tmperr

  # both on win and nix: -Error while trying to create file
  if [ -s $tmperr ];then
    echo Error log $tmperr is NOT EMPTY!
    echo -------------------------------
    cat $tmperr
    echo -------------------------------
    echo Verify that setting \'$dbnm\' in config file \'$cfg\' is VALID!
    echo Script is now terminated.
    exit 1
  fi
  echo RESULT: script finished OK, database has been created:
  echo ------------------------------------------
  cat $tmplog
  echo ------------------------------------------
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: finish.
  echo
}

# -------------------------------  d b _ b u i l d  -----------------------------------

db_build() {
  echo
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.

  local prf=tmp_build_$fb
  local bld=$tmpdir/$prf.sql
  local log=$tmpdir/$prf.log
  local err=$tmpdir/$prf.err
  local tmp=$tmpdir/$prf.tmp
  local run_isql="$fbc/isql $dbconn -nod -i $bld $dbauth"

  rm -f $bld $log $err $tmp
  # these scripts DIFFERS for each version of Firebird:
  echo set bail on\;>>$bld
  echo -e in \"$shdir/oltp"$fb"_DDL.sql\"\;>>$bld
  echo -e in \"$shdir/oltp"$fb"_sp.sql\"\;>>$bld

  # these scripts suitable for BOTH version of Firebird:
  echo in \"$shdir/oltp_main_filling.sql\"\;>>$bld
  echo in \"$shdir/oltp_data_filling.sql\"\;>>$bld
  echo show collation\;>>$bld
  echo show domain\;>>$bld
  echo show exception\;>>$bld
  echo show generator\;>>$bld
  echo show table\;>>$bld
  echo show view\;>>$bld
  echo show trigger\;>>$bld
  echo show proc\;>>$bld

  echo Content of building SQL script:
  echo -------------------------------
  cat $bld
  echo -------------------------------
  echo Command to be run:
  echo $run_isql
  echo
  echo Build test database. Please wait. . .

  rm -f $log
  echo Database objects building log. Script: $bld>>$log
  echo Script:>>$log
  cat $bld>>$log
  echo>>$log

  ###############################################
  ### b u i l d i n g    D B    o b j e c t s ###
  ###############################################
  $run_isql 1>>$log 2>$err

  if [ -s $err ];then
    echo Error log $err is NOT EMPTY!
    echo -------------------------------
    cat $err
    echo -------------------------------
    echo Script is now terminated.
    exit 1
  fi
  
  echo Creation of database objects COMPLETED. See results in $log.
  echo Test will be run with following settings:
  echo set width db_name 30\;>>$tmp
  echo select                                                    >>$tmp
  echo     m.mon\$page_size as page_size                          >>$tmp
  echo    ,m.mon\$page_buffers as page_buffers                    >>$tmp
  echo    ,iif\(m.mon\$forced_writes=0,\'OFF\',\'ON\'\) as FW           >>$tmp
  echo    ,m.mon\$sweep_interval as sweep                         >>$tmp
  echo    ,right\(m.mon\$database_name,30\) as db_name              >>$tmp
  echo from mon\$database m\;                                      >>$tmp
  echo set width working_mode 20\;>>$tmp
  echo set width setting_name 40\;>>$tmp
  echo set width setting_value 15\;>>$tmp
  echo set list off\;                                             >>$tmp
  echo select s.mcode as setting_name, s.svalue as setting_value >>$tmp
  echo from settings s                                           >>$tmp
  echo where s.working_mode=\'INIT\' and s.mcode=\'WORKING_MODE\'    >>$tmp
  echo UNION ALL                                                 >>$tmp
  echo select t.mcode as setting_name, t.svalue as setting_value >>$tmp
  echo from settings s                                           >>$tmp
  echo join settings t on s.svalue=t.working_mode                >>$tmp
  echo where s.working_mode=\'INIT\' and s.mcode=\'WORKING_MODE\'    >>$tmp
  echo UNION ALL                                                 >>$tmp
  echo select s.mcode, s.svalue                                  >>$tmp
  echo from settings s                                           >>$tmp
  echo where s.working_mode=\'COMMON\'                             >>$tmp
  echo       and s.mcode                                         >>$tmp
  echo           in \(\'ENABLE_MON_QUERY\',                         >>$tmp
  echo               \'ENABLE_RESERVES_WHEN_ADD_INVOICE\',         >>$tmp
  echo               \'C_CATCH_MISM_BITSET\',                      >>$tmp
  echo               \'TRACED_UNITS\',                             >>$tmp
  echo               \'C_MAKE_QTY_STORNO_MODE\',                   >>$tmp
  echo               \'C_MIN_COST_TO_BE_SPLITTED\',                >>$tmp
  echo               \'C_ROWS_TO_MULTIPLY\',                       >>$tmp
  echo               \'RANDOM_SEEK_VIA_ROWS_LIMIT\',               >>$tmp
  echo               \'HALT_TEST_ON_ERRORS\'\)\;                     >>$tmp
  if [ $is_embed == 1 ]; then
    $fbc/isql $dbnm -nod -i $tmp
  else
    $fbc/isql $host/$port:$dbnm -nod -i $tmp -user $usr -pas $pwd
  fi
  echo -e '###########################################################'
  rm -f $bld $tmp
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: finish.
  echo Press ENTER to continue. . .
  pause
  echo
}


# -------------------------------  c h e c k _ s t o p t e s t -----------------------------------

check_stoptest() {
  echo
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.
  # check that file 'stoptest.txt' is EMPTY
  local pfx=tmp_check_stoptest
  local tmpchk=$tmpdir/$pfx.sql
  local tmpclg=$tmpdir/$pfx.log
  local tmperr=$tmpdir/$pfx.err
  local run_isql="$fbc/isql $dbconn -nod -n -i $tmpchk $dbauth"

  rm -f $tmpchk $tmpclg $tmperr
  echo set heading off\; set list on\;>>$tmpchk
  echo -- check that test now can be run: table \'ext_stoptest\' must be EMPTY>>$tmpchk
  echo -n select iif\( exists\( select \* from ext_stoptest \), >>$tmpchk
  echo -n \'1\', >>$tmpchk
  echo -n \'0\'>>$tmpchk
  echo \) as \"cancel_flag=\" >>$tmpchk
  echo from rdb\$database\;>>$tmpchk

  echo
  echo Check for non-empty external file stoptest.txt.
  echo Command to be run:
  echo $run_isql
  echo Content of script $tmpchk:
  echo --------------------------
  cat $tmpchk
  echo --------------------------

  $run_isql 1>$tmpclg 2>$tmperr

  if [ -s $tmperr ];then
    echo Script for checking file \'stoptest.txt\' finished with ERRORS.
    echo Name of script: $tmpchk
    echo Name of errlog: $tmperr
    echo -------------------------------
    cat $tmperr
    echo -------------------------------
    echo Check in firebird.conf value of parameter ExternalFileAccess 
    echo and permissions for this folder.
    echo Script is now terminated.
    exit 1
  else
    # open log and parse it as config with 'param = value' string:
    echo No errors detected when run $tmpchk
    echo Obtain results from its log $tmpclg

    while IFS='=' read lhs rhs
    do
      if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
          # | sed -e 's/^[ \t]*//'
          lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
          rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
          declare $lhs=$rhs
          echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
      fi
    done<$tmpclg
    echo
    echo Result: cancel_flag=\>\>\>$cancel_flag\<\<\<
    if [ $cancel_flag = 1 ]; then
      echo -e '##################################################################################'
      echo -e FILE \'stoptest.txt\' ON SERVER SIDE HAS NON-ZERO SIZE, MAKE IT EMPTY TO START TEST
      echo -e '##################################################################################'
      echo
      echo Script is now terminated.
      exit 1
    fi
  fi
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: finish.
  echo
}

# -------------------------------  u p d _ i n i t _ d o c s  ------------------------------------

upd_init_docs() {
  echo
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.
  echo Check is the database needs to be filled up with necessary number of documents

  local pfx=tmp_get_init_docs
  local tmpchk=$tmpdir/$pfx.sql
  local tmpclg=$tmpdir/$pfx.log
  local tmperr=$tmpdir/$pfx.err
  local run_isql="$fbc/isql $dbconn -i $tmpchk -nod -n $dbauth"
  rm -f $tmpchk $tmpclg $tmperr

  # check that total number of docs (count from doc_list table) is LESS than $init_docs
  # and correct $init_docs (reduce it) so that its new value + count will be equal to 
  # required total number of docs (which is specified in oltp_config.NN)
  echo set list on\; set heading off\;>>$tmpchk
  echo -e select count\(*\) as \"old_docs=\" from doc_list\;>>$tmpchk

  echo -e Count number of existing documents to compare it with \$init_docs setting.
  echo Command to be run:
  echo $run_isql
  echo Content of script $tmpchk:
  echo --------------------------
  cat $tmpchk
  echo --------------------------

  $run_isql 1>$tmpclg 2>$tmperr

  # result: file $tmpclg contains ONE non-empty row like this: existing_docs=1234
  # now we can APPLY this row as it was SET command in batch and
  # assign its value to env. variable with the SAME name -- `existing_docs`:
  if [ -s $tmperr ];then
    echo Script for counting number of currently existing documents finished with ERRORS.
    echo Name of script: $tmpchk
    echo Name of errlog: $tmperr
    echo -------------------------------
    cat $tmperr
    echo -------------------------------
    echo Perhaps not all database objects was created.
    echo Script is now terminated.
    exit 1
  else
    # open log and parse it as config with 'param = value' string:
    echo No errors detected when run $tmpchk
    echo Obtain results from its log $tmpclg

    while IFS='=' read lhs rhs
    do
      if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
          # | sed -e 's/^[ \t]*//'
          lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
          rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
          declare $lhs=$rhs
          echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
      fi
    done<$tmpclg

    existing_docs=$old_docs
    if [ $existing_docs -lt $init_docs ]; then
      init_docs=$(( init_docs - existing_docs ))
    else
      init_docs=0
    fi
  fi
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: finish.
  echo
}

# --------------------------  i n i t _ d o c s _ s e t _ f w _ o f f  -------------------------

init_docs_set_fw_off() {
  echo
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.

  local pfx=tmp_restart_init_pop_sequence
  local tmpsql=$tmpdir/$pfx.sql
  local tmplog=$tmpdir/$pfx.log
  local tmperr=$tmpdir/$pfx.err
  local run_isql="$fbc/isql $dbconn -i $tmpsql -nod -n $dbauth"
  rm -f $tmpsql $tmplog $tmperr

  # LI-T3.0.0.31394 Firebird 3.0 Beta 1
  [[ $fbb == *"Firebird 3"* ]] && echo alter database set linger to 15\; >>$tmpsql
  echo commit\;>>$tmpsql
  echo set transaction no wait\;>>$tmpsql
  echo alter sequence g_init_pop restart with 0\;>>$tmpsql
  echo commit\;>>$tmpsql

  #  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  #  G E T    I N I T I A L  S T A T E    O F    F O R C E D   W R I T E S 
  #  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  
  echo set list on\;>>$tmpsql 
  echo select >>$tmpsql 
  echo "   m.mon\$forced_writes as \"prev_fw=\"" >>$tmpsql 
  echo "  ,iif( exists( select * from perf_log g"  >>$tmpsql 
  echo "                where g.unit='fw_both_changes_done' and g.aux1=1 and g.aux2 is null"  >>$tmpsql 
  echo "              ), '0', '1'"  >>$tmpsql 
  echo "      ) as \"can_set_fw_off=\"" >>$tmpsql 
  echo from mon\$database m\;>>$tmpsql
  echo set list off\;>>$tmpsql

  echo Command that now to be run:
  echo $run_isql
  echo Content of script $tmpsql:
  echo --------------------------
  cat $tmpsql
  echo --------------------------

  $run_isql 1>$tmplog 2>$tmperr

  if [ -s $tmperr ];then
    echo Script which set FW for initial data population finished with ERROR!
    echo Name of script: $tmpsql
    echo Name of errlog: $tmperr
    echo -------------------------------
    cat $tmperr
    echo -------------------------------
    echo Perhaps version of Firebird not properly defined 
    echo or sequence \'g_init_pop\' does not exist.
    echo Script is now terminated.
    exit 1
  fi
  
  # obtain current setting of FW and change it - perhaps temply - to OFF:
  # open log and parse it as config with 'param = value' string:
  echo No errors detected when run $tmpsql
  echo Obtain results from its log $tmplog

  while IFS='=' read lhs rhs
  do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
      # | sed -e 's/^[ \t]*//'
      lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
      rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
      declare $lhs=$rhs
      echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
  done<$tmplog
  fw_current=$prev_fw 
  fw_can_upd=$can_set_fw_off
  echo fw_current=$fw_current, fw_can_upd=$fw_can_upd

  rm -f $tmpsql $tmplog $tmperr

  # Save old value of FW (for restoring it after finish init doc filling):
  if [ $fw_current = 1 ]; then
    fw_mode=sync
  else
    fw_mode=async
  fi

  #  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  #  T E M P L Y    S E T    F O R C E D   W R I T E S   =   O F F
  #  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

  if [ $fw_can_upd = 1 ]; then
    # 1. add to perf_log table our intention to FIRST change FW, always to OFF
    echo "update or insert into perf_log (unit, aux1, aux2, dts_beg, dts_end)">>$tmpsql
    echo "values('fw_both_changes_done', $fw_current, null, 'now', null)">>$tmpsql
    echo "matching (unit);">>$tmpsql
    echo commit\;>>$tmpsql

    run_isql="$fbc/isql $dbconn -i $tmpsql -nod -n $dbauth"

    echo Command that now to be run:
    echo $run_isql
    echo Content of script $tmpsql:
    echo --------------------------
    cat $tmpsql
    echo --------------------------

    $run_isql 1>$tmplog 2>$tmperr

    # 2. run - perhaps LOCAL - gfix with command line for REMOTE database to set fw = OFF:
    echo Temply change Forced Writes to OFF.
    if [ $is_embed = 1 ];then
      $fbc/gfix $dbnm -w async
    else 
      $fbc/gfix $host/$port:$dbnm -w async -user $usr -pas $pwd
    fi
    rm -f $tmpsql $tmplog $tmperr
  fi
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: finish.
  echo
} # end of: init_docs_set_fw_off()


# --------------------------  g e n _ w o r k i n g _ s q l  -------------------------

gen_working_sql() {
 echo
 echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.
 local mode=$1 # 'init_pop' xor 'run_test'
 local sql=$2
 local lim=$3 
 local nau
 [[ $4=1 ]] && nau="no auto undo"
 
 # should detailed info for each iteration be added in log ? 
 # (actual only for mode=run_test; if "1" then add select * from perf_log)
 local nfo=${5:-0}
 local verb
 [[ $mode = "init_pop" ]] && verb=10 || verb=50

 rm -f $sql
 echo Input args: 
 echo mode: $mode,
 echo sql: $sql, 
 echo number of repeating EB: $lim
 #echo set tran option: $nau
 echo "-- ### WARNING: DO NOT EDIT ###">>$sql
 echo "-- Generated auto by $shname, routine: $FUNCNAME">>$sql
 if echo $mode | grep -i "^init_pop$" > /dev/null ; then
   echo>>$sql
   echo "-- mode='$mode': get data from mon\$database for verifying settings of database">>$sql
   echo "-- NB-1: FW must be (temply) set to OFF">>$sql
   echo "-- NB-2: cache buffers temply set to pretty big value">>$sql
   echo "set list on; select * from mon\$database; set list off;">>$sql
 fi

 echo>>$sql

 for (( i=1; i<=$lim; i++ ))
 do
    [[ $((  $i % $verb )) = 0 ]] && echo Done generating iter $i of total $lim
    echo "----------------- mode = $mode, iter # $i -----------------------">>$sql
    echo>>$sql
    [[ $i = 1 ]] && echo commit\;>>$sql
    echo -- check oltp_config.NN for optional setting NO AUTO UNDO here: >>$sql
    echo set transaction no wait $nau\;                                  >>$sql

    if echo $mode | grep -i "^run_test$" > /dev/null ; then
      echo set width test_ends_at 19\;                                           >>$sql
      echo set width engine 6\;                                                  >>$sql
      echo set width iter_info 16\;                                              >>$sql
      echo set width mon_info 50\;                                               >>$sql
      if [ $i = 1 ]; then
        echo -n "select left( cast( p.dts_end as varchar(24) ), 19 ) "           >>$sql
        echo      as test_ends_at                                                >>$sql
        echo -n "        ,rdb\$get_context('SYSTEM','ENGINE_VERSION') "          >>$sql
        echo      as engine                                                      >>$sql
        echo -e "        ,$i||' of '||$lim as iter_info"                         >>$sql
        echo from perf_log p                                                     >>$sql
        echo "where p.unit = 'perf_watch_interval'"                              >>$sql
        echo order by dts_beg desc                                               >>$sql
        echo rows 1\;                                                            >>$sql
      else # i > 1
        echo select                                                              >>$sql
        echo -ne "  left( cast( rdb\$get_context('USER_SESSION','PERF_WATCH_END') ">>$sql
        echo -n                  "as varchar(24)"                                >>$sql
        echo -ne  "), "                                                          >>$sql
        echo -ne  "19)"                                                          >>$sql
        echo -e  " as test_ends_at"                                              >>$sql
        echo -e "  ,lpad( $i, 4,' ')||' of '||$lim as iter_info"                 >>$sql
        if [ $fb = 30 ]; then
          if [ $mon_unit_perf = 1 ]; then
              echo -e "   -- this info set only in SP srv_fill_mon:"                >>$sql
              echo -e "  ,rdb\$get_context('USER_SESSION','MON_INFO') as mon_info"  >>$sql
          fi
        fi
        echo "from rdb\$database;"                                              >>$sql
      fi # i =1 or -gt 1
    fi # mode='run_test'
    
    echo "set term ^;"                                                      >>$sql
    echo execute block as                                                   >>$sql
    echo -e "    declare v_unit dm_name;"                                   >>$sql
    echo begin                                                              >>$sql
      if echo $mode | grep -i "^init_pop$" > /dev/null ; then
        echo -e "     -- SKIP choise of application units which REMOVE documents:"    >>$sql
        echo -e "     select p.unit"                                                  >>$sql
        echo -e "     from srv_random_unit_choice("                                   >>$sql
        echo -e "               '',"                                                  >>$sql
        echo -e "               'creation,state_next,service,',"                      >>$sql
        echo -e "               '',"                                                  >>$sql
        echo -e "               'removal'"                                            >>$sql
        echo -e "     ) p"                                                            >>$sql
        echo -e "     into v_unit;"                                                   >>$sql
      fi # $mode='init_pop'
 
      if echo $mode | grep -i "^run_test$" > /dev/null ; then #
        echo -e "     if ( NOT exists( select * from ext_stoptest ) ) then"          >>$sql
        echo -e "     begin"                                                         >>$sql
        echo -e "       select p.unit"                                               >>$sql
        echo -e "       from srv_random_unit_choice("                                >>$sql
        echo -e "                 '',"                                               >>$sql
        echo -e "                 '',"                                               >>$sql
        echo -e "                 '',"                                               >>$sql
        echo -e "                 ''"                                                >>$sql
        echo -e "       ) p"                                                         >>$sql
        echo -e "       into v_unit;"                                                >>$sql
        echo -e "     end"                                                           >>$sql
        echo -e "     else"                                                          >>$sql
        echo -e "       v_unit = 'TEST_WAS_CANCELLED';"                              >>$sql
      fi # # $mode='run_test'
      echo -e "     -- This will be shown in .log of working SQL script:"      >>$sql
      echo -e "     rdb\$set_context('USER_SESSION','SELECTED_UNIT', v_unit);"  >>$sql
      echo -e "     rdb\$set_context('USER_SESSION','ADD_INFO', null);"         >>$sql
    echo end^                                                                  >>$sql
    echo "set term ;^"                                                         >>$sql


    if echo $mode | grep -i "^run_test$" > /dev/null ; then # run_test
      if [ $fb = 30 ]; then
          if [ $mon_unit_perf = 1 ]; then
            echo "------ ###############################################  -------">>$sql
            echo "-----  G A T H E R    M O N.    D A T A    B E F O R E  -------">>$sql
            echo "------ ###############################################  -------">>$sql
            echo "set term ^;"                                                   >>$sql
            echo execute block as                                                >>$sql
            echo -e "  declare v_dummy bigint;"                                         >>$sql
            echo begin                                                                  >>$sql
              echo -e "  -- define context var which will identify rowset field"        >>$sql
              echo -e "  -- in mon_log and mon_log_table_stats:"                        >>$sql
              echo -e "  -- (this value is ised after call app. unit):"                 >>$sql
              echo -e "  rdb\$set_context('USER_SESSION','MON_ROWSET', gen_id(g_common,1));" >>$sql
              echo                                                                      >>$sql
              echo -e "  -- gather mon\$ tables BEFORE run app unit, only in FB 3.0"    >>$sql
              echo -e "  -- add FIRST row to GTT tmp\$mon_log"                          >>$sql
              echo -e "  select count(*)"                                               >>$sql
              echo -e "  from srv_fill_tmp_mon("                                        >>$sql
              echo -e "          rdb\$get_context('USER_SESSION','MON_ROWSET')    -- :a_rowset" >>$sql
              echo -e "         ,1                                               -- :a_ignore_system_tables" >>$sql
              echo -e "         ,rdb\$get_context('USER_SESSION','SELECTED_UNIT') -- :a_unit"   >>$sql
              echo -e "                       )"                                        >>$sql
              echo -e "  into v_dummy;"                                                 >>$sql
              echo                                                                      >>$sql
              echo -e "  -- result: tables tmp\$mon_log and tmp\$mon_log_table_stats"     >>$sql
              echo -e "  -- are filled with counters BEFORE application unit call."     >>$sql
              echo -e "  -- Field 'mult' in these tables is now negative: -1"           >>$sql
            echo end                                                                    >>$sql
            echo "^set term ;^"                                                         >>$sql
            echo "commit; --  ##### C O M M I T  #####  after 1st gathering mon\$data"      >>$sql
            echo "set transaction no wait $nau;"                                        >>$sql
          fi # mon_unit_perf = 1
      fi # fb = 30
    fi # mode = 'run_test' - gather mon info BEFORE application unit call
    echo>>$sql
    echo set width dts 12\;                                                  >>$sql
    echo set width trn 14\;                                                  >>$sql
    echo set width unit 20\;                                                 >>$sql
    echo set width elapsed_ms 10\;                                           >>$sql
    echo set width msg 20\;                                                  >>$sql
    echo set width add_info 40\;                                             >>$sql
    echo set width mon_info 20\;                                             >>$sql

    echo -- ensure that just before call application unit                   >>$sql
    echo -- table tmp\$perf_log is really EMPTY:                             >>$sql
    echo delete from tmp\$perf_log\;                                          >>$sql
    echo>>$sql
    echo --------------- before run app unit: show its NAME -------------- >>$sql
    echo set list off\;                                                      >>$sql
    echo select                                                             >>$sql
    echo -e "    substring(cast(current_timestamp as varchar(24)) from 12 for 12) as dts," >>$sql
    echo -e "    'tra_'||current_transaction trn,"                             >>$sql
    echo -e "     rdb\$get_context('USER_SESSION','SELECTED_UNIT') as unit," >>$sql
    echo -e "    'start' as msg,"                                                >>$sql
    echo -e "    'att_'||current_connection as add_info"                       >>$sql
    echo from rdb\$database\;                                                 >>$sql

    echo>>$sql

    echo "------ #########################################  -------">>$sql
    echo "------ R U N    A P P L I C A T I O N    U N I T  -------">>$sql
    echo "------ #########################################  -------">>$sql
    echo "set term ^;"                                                           >>$sql
    echo execute block as                                                        >>$sql
    echo -e "    declare v_stt varchar(128);"                                    >>$sql
    echo -e "    declare result int;"                                            >>$sql
    echo -e "    declare v_old_docs_num int;"                                    >>$sql
    echo begin                                                                   >>$sql
      if echo $mode | grep -i "^init_pop$" > /dev/null ; then
        echo -e "  -- ::: nb ::: g_init_pop is always incremented by 1"            >>$sql
        echo -e "  -- in sp_add_doc_list, even if fault will occur later"          >>$sql
        echo -e "  -- set context var 'INIT_DATA_POP' to not-null for analyzing"   >>$sql
        echo -e "  -- in sp_customer_reserve and others SPs and raise exception"   >>$sql 
        echo -e "  rdb\$set_context('USER_TRANSACTION','INIT_DATA_POP',1);"        >>$sql
        echo -e "  v_old_docs_num = gen_id( g_init_pop, 0);"                       >>$sql
      fi # mode = 'init_pop'

    echo   -e "  begin"                                                              >>$sql
      echo -e "    -- save in ctx var timestamp of START app unit:"                  >>$sql
      echo -e "    rdb\$set_context('USER_SESSION','BAT_PHOTO_UNIT_DTS', cast('now' as timestamp));">>$sql
      echo -e "    rdb\$set_context('USER_SESSION', 'GDS_RESULT', null);"            >>$sql
      echo -e "    -- save value of current_transaction because we make COMMIT"      >>$sql
      echo -e "    -- after gathering mon\$ tables when oltp_config.NN parameter"     >>$sql
      echo -e "    -- mon_unit_perf=1"                                               >>$sql
      echo -e "    rdb\$set_context('USER_SESSION', 'APP_TRANSACTION', current_transaction);" >>$sql
      echo -e "    if ( rdb\$get_context('USER_SESSION','SELECTED_UNIT')"            >>$sql
      echo -e "         is distinct from"                                            >>$sql
      echo -e "         'TEST_WAS_CANCELLED'"                                        >>$sql
      echo -e "       ) then"                                                        >>$sql
      echo -e "      begin"                                                           >>$sql
        echo -e "        v_stt='select count(*) from '"                            >>$sql
        echo -e "               ||rdb\$get_context('USER_SESSION','SELECTED_UNIT');"      >>$sql
        echo -e "        --- ##################################" >>$sql
        echo -e "        --- e x e c u t e    s t a t e m e n t" >>$sql
        echo -e "        --- ##################################" >>$sql
        echo -e "        execute statement (v_stt) into result;"                   >>$sql
        echo                                                                           >>$sql
        echo -e "        rdb\$set_context('USER_SESSION', 'RUN_RESULT',"           >>$sql
        echo -e "                         'OK, '|| result ||' rows');"              >>$sql
      echo -e "      end"                                                             >>$sql
      echo -e "   else -- test has been CANCELLED "                                 >>$sql
      echo -e "      begin"                                                           >>$sql
        echo -e "             rdb\$set_context('USER_SESSION','RUN_RESULT',"               >>$sql
        echo -e "                        (select e.fb_mnemona"                            >>$sql
        echo -e "                         from perf_log g"                                >>$sql
        echo -e "                         join fb_errors e on g.fb_gdscode=e.fb_gdscode"  >>$sql
        echo -e "                         where g.unit='sp_halt_on_error'"                >>$sql
        echo -e "                         order by g.dts_end DESC rows 1"                 >>$sql
        echo -e "                        )"                                              >>$sql
        echo -e "                            );"                                         >>$sql
      echo -e "      end"                                                                 >>$sql
      echo -e "    -- add timestamp for FINISH app unit:"                                 >>$sql
      echo -e "    rdb\$set_context( 'USER_SESSION','BAT_PHOTO_UNIT_DTS',"                >>$sql
      echo -e "                     rdb\$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS')">>$sql
      echo -e "                     || ' '"                                               >>$sql
      echo -e "                     || cast('now' as timestamp)"                          >>$sql
      echo -e "                    );"                                                    >>$sql
      echo                                                                                >>$sql
    echo -e "  when any do"                                                               >>$sql
    echo -e "    begin"                                                                   >>$sql
      echo -e "           rdb\$set_context('USER_SESSION', 'GDS_RESULT', gdscode);"      >>$sql
      if echo $mode | grep -i "^init_pop$" > /dev/null ; then
        echo -e "           v_stt = 'alter sequence g_init_pop restart with '"            >>$sql
        echo -e "                   ||v_old_docs_num;"                                    >>$sql
        echo -e "           execute statement (v_stt);"                                   >>$sql
      fi
      echo -e "           rdb\$set_context('USER_SESSION', 'RUN_RESULT', 'error, gds='||gdscode);" >>$sql
        echo -e "        --- ##############################" >>$sql
        echo -e "        --- r a i s e    e x c e p t i o n" >>$sql
        echo -e "        --- ##############################" >>$sql
      echo -e "           exception;"                                                     >>$sql
    echo -e "    end"                                                                     >>$sql
    echo -e "  end"                                                                       >>$sql
    echo end                                                                              >>$sql
    echo "^set term ;^"                                                                   >>$sql
    echo>>$sql

    if echo $mode | grep -i "^run_test$" > /dev/null ; then # run_test
      if [ $fb = 30 ]; then
          if [ $mon_unit_perf = 1 ]; then
            echo "------ ############################################  -------">>$sql
            echo "-----  G A T H E R    M O N.    D A T A   A F T E R   -------">>$sql
            echo "------ ############################################  -------">>$sql
            echo "set term ^;"                                                   >>$sql
            echo execute block as                                                >>$sql
            echo -e "  declare v_dummy bigint;"                                         >>$sql
            echo begin                                                                  >>$sql
                echo -e "  -- gather mon\$ tables AFTER running app unit, only in FB 3.0">>$sql
                echo -e "  -- add SECOND row to GTT tmp\$mon_log:"                      >>$sql
                echo -e "  select count(*) from srv_fill_tmp_mon"                       >>$sql
                echo -e "  ("                                                           >>$sql
                echo -e "          rdb\$get_context('USER_SESSION','MON_ROWSET')     -- :a_rowset" >>$sql
                echo -e "         ,1                                                -- :a_ignore_system_tables" >>$sql
                echo -e "         ,rdb\$get_context('USER_SESSION','SELECTED_UNIT') -- :a_unit"   >>$sql
                echo -e "         ,coalesce(                                        -- :a_info"   >>$sql
                echo -e "               rdb\$get_context('USER_SESSION','ADD_INFO') -- aux info, set in APP units only" >>$sql
                echo -e "              ,rdb\$get_context('USER_SESSION','RUN_RESULT')"  >>$sql
                echo -e "             )"                                                >>$sql
                echo -e "         ,rdb\$get_context('USER_SESSION', 'GDS_RESULT')   -- :a_gdscode" >>$sql
                echo -e "  )"                                                           >>$sql
                echo -e "  into v_dummy;"                                               >>$sql
                echo                                                                    >>$sql
                echo -e "  -- add pair of rows with aggregated differences of mon\$"    >>$sql
                echo -e "  -- counters from GTT to fixed tables"                        >>$sql
                echo -e "  -- (this SP also removes data from GTTs):"                   >>$sql
                echo -e "  select count(*)"                                             >>$sql
                echo -e "  from srv_fill_mon("                                          >>$sql
                echo -e "    rdb\$get_context('USER_SESSION','MON_ROWSET') -- :a_rowset" >>$sql
                echo -e "                   )"                                          >>$sql
                echo -e "  into v_dummy;"                                               >>$sql
                echo -e "  rdb\$set_context('USER_SESSION','MON_ROWSET', null);"         >>$sql
            echo end                                                                    >>$sql
            echo "^set term ;^"                                                         >>$sql
            echo "commit; --  ##### C O M M I T  #####  after 2nd gathering mon\$data"  >>$sql
            echo "set transaction no wait $nau;"                                        >>$sql

          fi # mon_unit_perf = 1
      fi # fb = 30
    fi # mode = 'run_test'

    echo -e "-- Output results of application unit run:"                           >>$sql
    echo -e "select"                                                               >>$sql
    echo -e "     substring(cast(current_timestamp as varchar(24)) from 12 for 12) as dts" >>$sql
    echo -e "     ,'tra_'||rdb\$get_context('USER_SESSION','APP_TRANSACTION') trn" >>$sql
    echo -e "     ,rdb\$get_context('USER_SESSION','SELECTED_UNIT') as unit"        >>$sql
    echo -e "     ,lpad("                                                           >>$sql
    echo -e "            cast("                                                     >>$sql
    echo -e "                  datediff("                                           >>$sql
    echo -e "                    millisecond"                                       >>$sql
    echo -e "                    from cast(left(rdb\$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'),24) as timestamp)">>$sql
    echo -e "                    to   cast(right(rdb\$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'),24) as timestamp)">>$sql
    echo -e "                         )"                                           >>$sql
    echo -e "                 as varchar(10)"                                      >>$sql
    echo -e "                )"                                                    >>$sql
    echo -e "           ,10"                                                        >>$sql
    echo -e "           ,' '"                                                       >>$sql
    echo -e "         ) as elapsed_ms"                                             >>$sql
    echo -e "     ,rdb\$get_context('USER_SESSION', 'RUN_RESULT') as msg"           >>$sql
    echo -e "     ,rdb\$get_context('USER_SESSION','ADD_INFO') as add_info"         >>$sql
    echo -e "from rdb\$database;"                                                   >>$sql

    if echo $mode | grep -i "^init_pop$" > /dev/null ; then # init_pop
      echo>>$sql
      echo -- Show current size of database and some other info from mon\$:         >>$sql
      echo "set list on;"                                                           >>$sql
      echo -e "set width db_name 80;"                                               >>$sql
      echo -e "select"                                                              >>$sql
      echo -e "     m.mon\$database_name db_name,"                                  >>$sql
      echo -e "     rdb\$get_context('SYSTEM','ENGINE_VERSION') engine,"             >>$sql
      echo -e "     mon\$FORCED_WRITES db_forced_writes,"                           >>$sql
      echo -e "     mon\$PAGE_BUFFERS page_buffers,"                                >>$sql
      echo -e "     m.mon\$page_size * m.mon\$pages as db_current_size,"            >>$sql
      echo -e "     gen_id(g_init_pop,0) as new_docs_created"                       >>$sql
      echo -e "from mon\$database m;"                                               >>$sql
    fi # mode = 'init_pop'

    if echo $mode | grep -i "^run_test$" > /dev/null ; then # run_test
      echo>>$sql
      echo -- Check for STOP test:                                                  >>$sql
      echo -e "set bail on; -- for catch test cancellation and stop all .sql"       >>$sql
      echo -e "set term ^;"                                                         >>$sql
      echo -e "execute block as"                                                    >>$sql
      echo -e "begin"                                                               >>$sql
      echo -e "     if ( rdb\$get_context('USER_SESSION','SELECTED_UNIT')"          >>$sql
      echo -e "          is NOT distinct from"                                      >>$sql
      echo -e "          'TEST_WAS_CANCELLED'"                                      >>$sql
      echo -e "       ) then"                                                       >>$sql
      echo -e "     begin"                                                          >>$sql
      echo -e "        exception ex_test_cancellation;"                             >>$sql
      echo -e "     end"                                                            >>$sql
      echo -e "     -- REMOVE data from context vars, they will not be used more"   >>$sql
      echo -e "     -- in this iteration:"                                          >>$sql
      echo -e "     rdb\$set_context('USER_SESSION','SELECTED_UNIT', null);"        >>$sql
      echo -e "     rdb\$set_context('USER_SESSION','RUN_RESULT',    null);"        >>$sql
      echo -e "     rdb\$set_context('USER_SESSION','GDS_RESULT',    null);"        >>$sql
      echo -e "     rdb\$set_context('USER_SESSION','ADD_INFO', null);"             >>$sql
      echo -e "     rdb\$set_context('USER_SESSION','APP_TRANSACTION', null);"      >>$sql
      echo -e "end"                                                                 >>$sql
      echo -e "^set term ;^"                                                        >>$sql
      echo -e "set bail off;"                                                       >>$sql
      echo>>$sql
      if [ $nfo = 1 ]; then
        echo -e "-- Begin block to output DETAILED results of iteration."            >>$sql
        echo -e "-- To disable this output change 'detailed_info' setting to 0"      >>$sql
        echo -e "-- in test configuration file $cfg"                                 >>$sql
        echo -e "set heading off;"                                                   >>$sql
        echo -e "set list on;"                                                       >>$sql
        echo -e "select '+++++++++  perf_log data for this Tx: ++++++++' as msg"     >>$sql
        echo -e "from rdb\$database;"                                                 >>$sql
        echo -e "set heading on;"                                                    >>$sql
        echo -e "set list on;"                                                       >>$sql
        echo -e "set width unit 35;"                                                 >>$sql
        echo -e "set width info 80;"                                                 >>$sql
        echo -e "select g.id, g.unit, g.exc_unit, g.info, g.fb_gdscode,g.trn_id,"    >>$sql
        echo -e "       g.elapsed_ms, g.dts_beg, g.dts_end"                          >>$sql
        echo -e "from perf_log g"                                                    >>$sql
        echo -e "where g.trn_id = current_transaction;"                              >>$sql
        echo -e "set list off;"                                                      >>$sql
        echo -e "-- Finish block to output DETAILED results of iteration."           >>$sql
      else
        echo -e "-- Output of detailed results of iteration DISABLED."               >>$sql
        echo -e "-- To enable this output change 'detailed_info' setting to 1"       >>$sql
        echo -e "-- in test configuration file $cfg"                                 >>$sql
      fi # nfo = 1 or 0
      echo>>$sql
    fi # mode = 'run_test'

    echo "--  F I N I S H    I T E R A T I O N    ### $i ###"                      >>$sql
    echo commit\;                                                                    >>$sql
    echo set list off\;                                                              >>$sql

    if [ $i -eq $lim ]; then
      echo set width msg 60\;                                                        >>$sql
      echo select                                                                    >>$sql
      echo -e "  current_timestamp dts,"                                             >>$sql
      echo -e "  '### FINISH packet, disconnect, att=$current_connection ###' as msg">>$sql
      echo from rdb\$database\;                                                      >>$sql
    fi

 done # i=1..$lim
 echo $(date +'%H:%M:%S'). Routine $FUNCNAME: finish.
 echo
} # end of gen_working_sql()

# --------------------------  a d d_ i n i t _ d o c s  -------------------------

add_init_docs() {
  # $tmpsql $tmplog $srv_frq
  echo
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.
  local tmpsql=$1
  local tmplog=$2
  local srv_frq=$3
  local run_isql
  t0=$(date +'%y%m%d_%H%M%S')
  echo
  echo Begin of initial data population.
  echo Recalc index statistcs: at the start of every $srv_frq packet.
  echo Script: $tmpsql

  echo Action start at $t0
  rm -f $tmplog
  
  # stop here 07.11.2014 2343, todo: see win batch, line 657
  local k=1
  local prf=tmp_chk_docs_count
  local tmpchk=$tmpdir/$prf.sql
  local tmpclg=$tmpdir/$prf.log
  while :
  do

    if [ $(( k % $srv_frq )) -eq 0  ]; then
      rm -f $tmpchk $tmpclg
      echo -e "set list on; set heading on;"               >>$tmpchk
      echo -e "commit; set transaction no wait;"           >>$tmpchk
      echo -e "select count(*) as srv_make_invnt_saldo_result from srv_make_invnt_saldo;">>$tmpchk
      echo -e "commit; set transaction no wait;"           >>$tmpchk
      echo -e "select count(*) as srv_make_money_saldo_result from srv_make_money_saldo;">>$tmpchk
      echo -e "commit; set transaction no wait;"           >>$tmpchk
      echo -e "select count(*) as srv_recalc_idx_stat_result from srv_recalc_idx_stat;" >>$tmpchk
      echo -e "commit;" >>$tmpchk

      echo -ne "$(date +'%H:%M:%S'), start service SPs... "
      # --------------- perform service: srv_make*_total, recalc index statistics -------------
      cat $tmpchk>>$tmplog
      run_isql="$fbc/isql $dbconn -i $tmpchk -c $init_buff -n -m -o $tmplog $dbauth"

      $run_isql

      echo -e "$(date +'%H:%M:%S'), finish service SPs."
    fi

    echo -ne "$(date +'%H:%M:%S'), packet $k start... "

    # Common application unit: create several documents
    # using .sql which was made in func gen_working_sql
    ###################################################
    run_isql="$fbc/isql $dbconn -i $tmpsql -c $init_buff -m -o $tmplog $dbauth"
    #echo Command to be run:
    #echo $run_isql
    
    $run_isql

    # result: one or more (in case of complex operations like sp_add_invoice_to_stock)
    # documents has been created; if some error occured, sequence g_init_pop has been
    # 'returned' to its previous value.
    # now we must check total number of docs:
    rm -f $tmpchk $tmpclg
    echo -n "set list off; set heading off; "     >>$tmpchk
    echo -n "select "                             >>$tmpchk
    echo -n "'new_docs='||gen_id(g_init_pop,0) " >>$tmpchk
    echo "from rdb\$database;"                 >>$tmpchk

    run_isql="$fbc/isql $dbconn -pag 0 -i $tmpchk -n $dbauth"
    #echo Obtain current number of documents. Command to be run:
    #echo $run_isql
    #echo Script $tmpchk:
    #echo --------------------------------------------
    #cat $tmpchk
    #echo --------------------------------------------

    $run_isql 1>$tmpclg 2>&1

    # result: file $tmpclg contains ONE row like this: new_docs=12345
    # now we can APPLY this row as it was SET command in batch and
    # assign its value to env. variable with the SAME name -- 'new_docs':

    while IFS='=' read lhs rhs
    do
      if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        # | sed -e 's/^[ \t]*//'
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        declare $lhs=$rhs
        #echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
      fi
    done<$tmpclg
    echo -e "$(date +'%H:%M:%S'), packet $k finish: docs created: >>>$new_docs<<<, limit: $init_docs"
    [[ $new_docs -gt $init_docs ]] && break
    k=$(( k+1 ))
  done
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: finish.
  echo
} # end of add_init_docs()

# --------------  i n i t _ d o c s _ r e s t o r e _ f w  ------------

init_docs_restore_fw() {
  echo
  echo $(date +'%H:%M:%S'). Routine $FUNCNAME: start.
  local fw_need_to_be_restored=${1:-0}
  local fw_mode=$2
  local fw_current=$3
  local prf=tmp_fw_restore
  local tmpsql=$tmpdir/$prf.sql
  local tmplog=$tmpdir/$prf.log
  local run_isql="$fbc/isql $dbconn -i $tmpsql -nod $dbauth"
  
  rm -f $tmpsql $tmplog
  if [ $fw_need_to_be_restored = 1 ];then
    echo RESTORE old value of FW.
    echo
    echo 1. Run gfix with command line for REMOTE database to set fw = $fw_mode
    if [ $is_embed = 1  ]; then
      $fbc/gfix $dbnm -w $fw_mode 2>$tmplog 1>&2
      $fbc/gstat -h $dbnm >>$tmplog
    else
      $fbc/gfix $host/$port:$dbnm -w $fw_mode -user $usr -pas $pwd 2>$tmplog 1>&2
      $fbc/gstat -h $host/$port:$dbnm -user $usr -pas $pwd >>$tmplog
    fi

    echo 2. Update in perf_log table our intention to REVERT change FW to its initial state
    echo "set stat on; set echo on;">>$tmpsql
    echo "update perf_log g set aux2=$fw_current, dts_end='now' where g.unit='fw_both_changes_done';">>$tmpsql
    echo "commit;">>$tmpsql
    echo "set stat off;">>$tmpsql
    echo "select aux1, aux2, dts_beg, dts_end from perf_log g where g.unit='fw_both_changes_done';">>$tmpsql
    echo Command to be run:
    echo $run_isql
    echo Script $tmpsql:
    echo -------------------------------------
    cat $tmpsql
    echo -------------------------------------
    $run_isql 1>>$tmplog 2>&1
    echo Done, check log $tmplog
  fi
  echo Routine $FUNCNAME: finish.
  echo
} # end of init_docs_restore_fw()

# --------------  l a u n c h _ p r e p a r i n g  -----------

launch_preparing() {
  echo
  echo Routine $FUNCNAME: start.

  local tmpsql=$1
  
  # Make comparison of TIMESTAMPS: this batch vs $tmpsql.
  # If this batch is OLDER that $tmpsql than we can SKIP recreating $tmpsql
  local skipGenSQL=0

  echo Check: should main SQL script be recreated due to its outdated timestamp.

  if [ -f $tmpsql ];then
    if [ $shname -ot $tmpsql ];then
      echo $shname is OLDER than $tmpsql
      if [ $cfg -ot $tmpsql ]; then
        echo $cfg is OLDER than $tmpsql 
        skipGenSQL=1
      else
        echo Test config is NEWER than $tmpsql
      fi
    else
      echo $shname is NEWER than $tmpsql
    fi
    [[ $skipGenSQL = 0 ]] && echo We must RECREATE $tmpsql, its timestamp is outdated. \
                          || echo We can SKIP recreation and use EXISTING $tmpsql.
  else
    echo Main script $tmpsql does not exist, now we create it.
  fi

  if [ $skipGenSQL = 0 ]; then
    # Generating script to be used by working isqls.
    # ############################################################
    gen_working_sql run_test $tmpsql 300 $no_auto_undo $detailed_info
    # ############################################################
  fi

  local prf=tmp_add_aux_rows
  local tmpchk=$tmpdir/$prf.sql
  local tmpclg=$tmpdir/$prf.log
  local run_isql="$fbc/isql $dbconn -i $tmpchk -n -m -o $tmpclg $dbauth"
  
  rm -f $tmpchk $tmpclg
  echo Add record for checking work to be stopped on timeout.
  echo -e "commit; set transaction no wait;"                                        >>$tmpchk
  echo -e "delete from perf_log g"                                                  >>$tmpchk
  echo -e "where g.unit in ( 'perf_watch_interval',"                                >>$tmpchk
  echo -e "                  'dump_dirty_data_semaphore',"                          >>$tmpchk
  echo -e "                  'dump_dirty_data_progress'"                            >>$tmpchk
  echo -e "                );"                                                      >>$tmpchk
  echo -e "commit;"                                                                 >>$tmpchk
  echo -e "insert into perf_log( unit,                  info,     exc_info,"        >>$tmpchk
  echo -e "                      dts_beg, dts_end, elapsed_ms)"                     >>$tmpchk
  echo -e "              values( 'perf_watch_interval', 'active', 'by $0',"         >>$tmpchk
  echo -e "        dateadd( $warm_time minute to current_timestamp),"              >>$tmpchk
  echo -e "        dateadd( $warm_time + $test_time minute to current_timestamp)," >>$tmpchk
  echo -e "        -1 -- skip this record from being displayed in srv_mon_perf_detailed" >>$tmpchk
  echo -e "        );"                                                              >>$tmpchk
  echo -e "insert into perf_log( unit,                        info,  stack,"        >>$tmpchk
  echo -e "                      dts_beg, dts_end, elapsed_ms)"                     >>$tmpchk
  echo -e "              values( 'dump_dirty_data_semaphore', '',    'by $0',"    >>$tmpchk
  echo -e "                      null, null, -1);"                                  >>$tmpchk
  echo -e "commit;">>$tmpchk
  echo -e "set width unit 20;">>$tmpchk
  echo -e "set width add_info 30;">>$tmpchk
  echo -e "set width dts_measure_beg 24;">>$tmpchk
  echo -e "set width dts_measure_end 24;">>$tmpchk
  echo -e "set list on;">>$tmpchk
  echo>>$tmpchk
  echo -e "select p.unit, p.exc_info as add_info,"                   >>$tmpchk
  echo -e "       cast(p.dts_beg as varchar(24)) as dts_measure_beg,">>$tmpchk
  echo -e "       cast(p.dts_end as varchar(24)) as dts_measure_end" >>$tmpchk
  echo -e "from perf_log p order by dts_beg desc rows 1;">>$tmpchk
  echo>>$tmpchk
  echo -e "set list off;">>$tmpchk

  echo Command to be run:
  echo $run_isql

  $run_isql

  echo Record in PERF_LOG table that will be checked by attachments to stop their work:
  cat $tmpclg
  rm -f $tmpchk $tmpclg

  echo Routine $FUNCNAME: finish.
  echo

} # end of launch_preparing()


#######################################################################
# ----------------------------   M A I N   ----------------------------
#######################################################################

[ -z $1 ] && msg_noarg && exit 1
[ -z $2 ] && msg_noarg && exit 1

echo Intro $0: arg1=$1, arg2=$2

export fb=$1
export k=$2
export cfg=./oltp$fb"_config.nix"
[[ -s $cfg ]] && echo "Config file '$cfg' found and not empty." || msg_nocfg $cfg

export shname=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)/`basename "${BASH_SOURCE[0]}"`
export shdir=$(cd "$(dirname "$0")" && pwd)

# stackoverflow.com/questions/4434797/read-a-config-file-in-bash-without-using-source
echo -e "Config file '$cfg' parsing result:"
shopt -s extglob
# not work: grep -e "^[  ]*[a-z]" ./oltp_config.30 | \
while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        # | sed -e 's/^[ \t]*//'
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        declare $lhs=$rhs
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
done<$cfg

# Remove trailing slash from variables which store PATHs:
fbc=${fbc%/}
tmpdir=${tmpdir%/}

# stackoverflow.com/questions/1921279/how-to-get-a-variable-value-if-variable-name-is-stored-as-string
echo -ne "Check that all necessary environment variables have values. . . "
vars=(tmpdir fbc is_embed dbnm no_auto_undo use_mtee detailed_info init_docs init_buff wait_for_copy warm_time test_time)
for i in ${vars[@]}; do
  #echo -e $i=\|${!i}\|
  [[ -z ${!i} ]] && msg_novar $i $cfg && exit 1
done
echo Ok.

vars=(isql gfix fbsvcmgr)
echo -ne "Check that all necessary Firebird console utilities exist in directory '$fbc'. . . "
for i in ${vars[@]}; do
  if [ ! -f "$fbc/${i}" ]
  then
    echo "File $fbc/${i} does not exist"
    msg_nofile
    exit 1
  fi
  #[[ -f $fbc/${i} ]] || msg_nofile
done
echo Ok.
mkdir -p $tmpdir/sql 2>/dev/null

# Attempt to get server version together with OS: WIndows or LInux
echo -ne "Getting Firebird info. . . "
export tmplog=$tmpdir/tmp_get_fb_db_info.log
export tmperr=$tmpdir/tmp_get_fb_db_info.err
if [ $is_embed -eq 1 ];then
  $fbc/fbsvcmgr localhost:service_mgr info_server_version 
else 
  $fbc/fbsvcmgr $host/$port:service_mgr user $usr password $pwd info_server_version 1>$tmplog 2>$tmperr
fi
[[ -s $tmperr ]] && msg_noserv
#cat $tmplog
while read a b c
do
  fbb=$c
  fbo=$(echo -n $fbb | cut -c1-2)
done<$tmplog
# output server version:
echo -e Build No. $fbb
rm -f $tmplog $tmperr

tmpsql=$tmpdir/tmp_init_data_pop.sql
tmplog=$tmpdir/tmp_init_data_pop.log
tmpchk=$tmpdir/tmp_init_data_chk.sql
tmpclg=$tmpdir/tmp_init_data_chk.log
tmperr=$tmpdir/tmp_init_data_chk.err

export dbauth=
export dbconn=
if [ $is_embed = 1 ]; then
  dbauth=
  dbconn=$dbnm
else
  dbauth="-user $usr -pas $pwd"
  dbconn=$host/$port:$dbnm
fi

echo Check result of previous building database objects.
rm -f $tmpchk $tmpclg
echo -- check that all database objects already exist: >>$tmpchk
echo -e set heading off\; set list on\;>>$tmpchk
echo -n -e select iif\( exists\( select \* from semaphores where task=\'all_build_ok\' \), >>$tmpchk
echo -n '1', >>$tmpchk
echo -n '0'>>$tmpchk
echo -e          \) as \"db_build_finished_ok=\" >>$tmpchk
echo -e from rdb\$database\;>>$tmpchk

run_isql="$fbc/isql $dbconn -i $tmpchk -nod -n -c 256 $dbauth"
echo -e Command that is to be run:
echo -e $run_isql
echo
echo Content of script $tmpchk:
echo --------------------------
cat $tmpchk
echo --------------------------
$run_isql 1>$tmpclg 2>$tmperr

# We must stop this .sh only in case when database has unsupported ODS or offline etc.
# We must CONTINUE if $tmpchk finished with error like 'table semaphores not found'.
if [ $(grep -i "Error while trying to open" $tmperr | wc -l) -gt 0 ]; then
  echo
  echo -e '#########################################################'
  echo -e Database \>$dbnm\< does NOT exist on host \>$host\<. 
  echo
  echo Press ENTER for attempt to CREATE it, Ctrl-C to QUIT. . .
  echo -e '#########################################################'
  pause
  db_create
  db_build

else

  badmsg=$(grep -i "Is a directory\|unavailable database\|unsupported on-disk\|shutdown" $tmperr | wc -l)
  [[ $badmsg -gt 0 ]] && msg_no_build_result $tmpchk $tmperr || echo "Database exists and online"

  # database DOES exist and ONLINE, but we have to ensure that ALL objects was successfully created in it.
  if [ -s $tmperr ];then
    echo Script that verifies finish of DB building process is NOT EMPTY.
    echo Name of script: $tmpclg
    echo Name of errlog: $tmperr
    echo
    echo Seems that at least one database object not found.
    db_build_finished_ok=0
  else
    # open log and parse it as config with 'param = value' string:
    echo No errors detected when run $tmpchk
    echo Obtain results from its log $tmpclg
    while IFS='=' read lhs rhs
    do
      if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        declare $lhs=$rhs
      fi
    done<$tmpclg
  fi
  echo db_build_finished_ok=\|$db_build_finished_ok\|
  echo -e -n Result:' ' && [[ $db_build_finished_ok -eq 1 ]] && echo database is READY for work. || echo database needs to be REBUILT.

  if [ $db_build_finished_ok -eq 0 ]; then
    echo
    echo -e Database: \>$dbnm\< -- DOES exist but
    echo process of creation its objects was not completed.
    echo
    echo -e '################################################################################'
    echo Press ENTER to start again recreation of all DB objects or Ctrl-C to FINISH. . .
    echo -e '################################################################################'
    pause
    db_build
  fi

fi # grep "Error while trying to open" $tmperr ==> true or false

# check that file 'stoptest.txt' is EMPTY
check_stoptest

# get number of currently existed documents and update value of $init_docs if need:
export existing_docs=0
if [ $init_docs -gt 0 ]; then
  upd_init_docs
  echo \$existing_docs=$existing_docs\; updated value of \$init_docs = \>\>\>$init_docs\<\<\<
fi

export fw_mode=
export fw_current=
export fw_can_upd=
if [ $init_docs -gt 0 ]; then
  echo Initial data population untill total number
  echo of created docs will be not less than \> $(( existing_docs +  init_docs )) \<
  echo
  echo Please wait. . .
  echo

  # 1. set linger to 15 (only for 3.0; greatly reduce time of connect!),
  # 2. temply change FW to OFF with saving old value of it.
  ####################
  init_docs_set_fw_off
  ####################
  echo stored value of FW: \>$fw_mode\<
````````````````  
  # 3. generate temp .sql script for initial filling:
  export init_pkq=50 # number of transactions in .sql (reduce re-connects)

  ########################################################
  gen_working_sql init_pop $tmpsql $init_pkq $no_auto_undo
  ########################################################

  # 4. Run just generated SQL: add new documents until their count less than $init_docs parameter:
  export srv_frq=10 # frequency of service procedures call (srv_make_invnt_saldo, srv_make_money_saldo, srv_recalc_idx_stat)

  ######################################
  add_init_docs $tmpsql $tmplog $srv_frq
  ######################################

  # 5. Restore previous value of Forced Writes (it could be changed in func init_docs_set_fw_off)
  echo Restore FW: fw_can_upd=\>$fw_can_upd\<, fw_mode=$fw_mode, fw_current=$fw_current
  ####################
  init_docs_restore_fw $fw_can_upd $fw_mode $fw_current
  ####################

  echo $(date +'%y%m%d_%H%M%S') FINISH initial data population.
  echo
  if [ $wait_for_copy = 1 ]; then
    echo "### NOTE ###"
    echo
    echo It\'s a good time to make COPY of test database in order 
    echo to start all following runs from the same state.
    echo
    echo Press ENTER to begin WARM-UP and TEST mode. . .
    pause
  fi

fi # $init_docs -gt 0

##############################################################
#               w o r k i n g     p h a s e
##############################################################
export mode=oltp$1

# winq = number of opening isqls
export winq=$2

export sql=$tmpdir/sql/tmp_random_run.sql

# 1. Generating main SQL script to be used by working isqls.
# 2. Add into perf_log table record for checking work to be stopped on timeout.
#####################
launch_preparing $sql
#####################
echo
export prf="$tmpdir/$mode"_"$HOSTNAME"
echo prf=$prf
echo Performance report will be in file:
echo -e "$prf"_001_performance_report.txt
echo
echo Main SQL script: $sql
echo Number of launched ISQL sessions: $winq

#rm -f $tmpsql $tmplog

echo launch $winq isqls. . .
echo

#. ./oltp_isql_run_worker.sh $cfg $sql $prf 1

for i in `seq $winq`
do
    sh ./oltp_isql_run_worker.sh ${cfg} ${sql} ${prf} ${i}&
done
echo Done script $0
