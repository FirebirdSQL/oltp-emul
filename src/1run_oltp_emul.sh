#!/bin/bash

function pause(){
   read -p "$*"
}

log_elapsed_time() {
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
  echo This folder must have following executable files: isql, fbsvcmgr
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
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
  local tmperr=$tmpdir/tmp_create_dbnm.err
  local tmpsql=$tmpdir/tmp_create_dbnm.sql
  local tmplog=$tmpdir/tmp_create_dbnm.log
  local run_isql
  local fbspref
  local run_fbs
  local dbconn
  local dbauth

  rm -f $tmpsql $tmplog $tmperr
  
  [[ $is_embed == 0 ]] && dbconn=$host/$port:$dbnm || dbconn=$dbnm
  [[ $is_embed == 0 ]] && dbauth="user '$usr' password '$pwd'"

	cat <<- EOF >>$tmpsql
      create database '$dbconn' page_size 8192 $dbauth;
      show version;
      set list on;
      select 
          m.mon\$database_name
         ,m.mon\$creation_date
         ,m.mon\$page_size
         ,a.mon\$server_pid
         ,a.mon\$attachment_id
         ,a.mon\$remote_protocol
         ,a.mon\$remote_address
      from mon\$attachments a cross join mon\$database m
      where a.mon\$attachment_id = current_connection;
      exit;
	EOF

  run_isql="$fbc/isql -q -i $tmpsql"
  echo Command to be run:
  echo $run_isql
  echo Content of script $tmpsql:
  echo ---------------------------------------
  cat $tmpsql
  echo ---------------------------------------

  $run_isql 1>$tmplog 2>$tmperr

  [[ $is_embed == 0 ]] && fbsrun=$host/$port:$dbnm || dbconn=$dbnm
  if [[ $is_embed == 0 ]]; then
     fbspref="$fbc/fbsvcmgr $host/$port:service_mgr user $usr password $pwd "
  else
     fbspref="$fbc/fbsvcmgr service_mgr "
  fi

  if [ $create_with_fw == async ]; then
     echo Changing attribute FW to OFF.
     run_fbs="$fbspref action_properties dbname $dbnm prp_write_mode prp_wm_async"
     echo Command:
     echo $run_fbs
     $run_fbs 1>>$tmplog 2>>$tmperr
  fi
  if [ $create_with_sweep != 0 ]; then
     echo Changing attribute sweep interval to $create_with_sweep.
     run_fbs="$fbspref action_properties dbname $dbnm prp_sweep_interval $create_with_sweep"
     echo Command:
     echo $run_fbs
     $run_fbs 1>>$tmplog 2>>$tmperr
  fi
  run_fbs="$fbspref action_db_stats dbname $dbnm sts_hdr_pages"
  $run_fbs | grep -i "$dbnm\|creation date\|attributes\|forced\|sweep" 1>>$tmplog 2>>$tmperr

  if [ -s $tmperr ];then
    echo Error log $tmperr is NOT EMPTY!
    echo -------------------------------
    cat $tmperr
    echo -------------------------------
    echo Verify that setting \'$dbnm\' in config file \'$cfg\' is VALID!
    echo Script is now terminated.
    exit 1
  fi
  echo RESULT: script finished OK, database has been created SUCCESSFULLY.
  echo Content of $tmplog:
  echo ---------------------------
  cat $tmplog
  echo ---------------------------
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo

  rm -f $tmperr $tmpsql $tmplog
}

# -------------------------------  d b _ b u i l d  -----------------------------------

db_build() {
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
  
  local prf=tmp_build_$fb
  local bld=$tmpdir/$prf.sql
  local log=$tmpdir/$prf.log
  local err=$tmpdir/$prf.err
  local tmp=$tmpdir/$prf.tmp
  local run_isql="$fbc/isql $dbconn -nod -i $bld $dbauth"

  if [[ $fb == 25 ]]; then
     vers_family=25
  else
     vers_family=30
  fi

  rm -f $bld $log $err $tmp

  cat <<- EOF >>$bld
		set bail on;
		in "$shdir/oltp$(($vers_family))_DDL.sql";
		in "$shdir/oltp$(($vers_family))_sp.sql";
	EOF

  if [ $create_with_debug_objects=1 ]; then
    # this script contains DDL for miscelan debug views and SPs,
    # it is common for both version of Firebird:
    cat <<- EOF >>$bld
    in "$shdir/oltp_misc_debug.sql";
	EOF
  fi
  
  #if [[ $create_with_split_heavy_tabs -eq 0 ]]; then
    inject_for_compound_columns_order=$(
	cat <<- SETVAR
	-- Inject setting for making columns order in compound index
	    -- according to the config setting 'create_with_compound_columns_order'
	    -- (actual only when setting 'create_with_split_heavy_tabs' = 0):
	    insert into settings(working_mode, mcode, context,svalue,init_on)
	             values( 'COMMON'                       -- working_mode
	                     ,'BUILD_WITH_QD_COMPOUND_ORDR'  -- mcode
	                     ,'USER_SESSION'                 -- context
	                     ,upper('$create_with_compound_columns_order') -- value from config
	                     ,'db_prepare'                   -- init_on
	                   );
	SETVAR
  )
  #fi

  cat <<- EOF >>$bld
    in "$shdir/oltp_main_filling.sql";
    
    -- Inject setting which will force to create either single table QDistr
    -- or several clones of it with names matching to patterh 'XQD_*'.
    -- Similar action will be done for table QStorned and 'XQS_*' clones.
    insert into settings(working_mode, mcode, context,svalue,init_on)
               values(  'COMMON'                       -- working_mode
                       ,'BUILD_WITH_SPLIT_HEAVY_TABS'  -- mcode
                       ,'USER_SESSION'                 -- context
                       ,$create_with_split_heavy_tabs             -- value from config
                       ,'db_prepare'                   -- init_on
                     );
    -- Inject setting which will force to create either one compound index for table
    -- QDistr (or its XQD* clones) or split columns on two separate indices.
    -- When setting 'create_with_split_heavy_tabs' is 0 then one of these indices is
    -- still compund but contain three fields instead of four.
    -- When setting 'create_with_split_heavy_tabs' is 0 then each XQD* table will have
    -- either compound index of two fields or two single-field indices.
    insert into settings(working_mode, mcode, context,svalue,init_on)
               values(  'COMMON'                       -- working_mode
                       ,'BUILD_WITH_SEPAR_QDISTR_IDX'  -- mcode
                       ,'USER_SESSION'                 -- context
                       ,$create_with_separate_qdistr_idx             -- value from config
                       ,'db_prepare'                   -- init_on
                     );

    $inject_for_compound_columns_order

    commit;

	EOF

	local post_handling_out=$tmpdir/oltp_split_heavy_tabs_$(($create_with_split_heavy_tabs))_$vers_family.tmp
	rm -f $post_handling_out

	cat <<- EOF >>$bld

		set echo off;
		-- Redirect output in order to auto-creation of SQL for change DDL after main build phase:
		out $post_handling_out;

		-- result in .sql:
		-- out "/var/tmp/.../oltp_split_heavy_tabs_n_25.tmp"; - where n=0|1.
		-- This will generate SQL statements for changing DDL according to 'create_with_split_heavy_tabs' setting.
		in "$shdir/oltp_split_heavy_tabs_$create_with_split_heavy_tabs.sql";

		-- Result: previous OUT-command provides redirection of
		-- |in "$shdir/oltp_split_heavy_tabs_$create_with_split_heavy_tabs.sql"|
		-- to the new temp file which will be applied on the next step.
		-- Close current output:
		out;

		-- Aplying temp file with SQL statements for change DDL according to 'create_with_split_heavy_tabs=$create_with_split_heavy_tabs':
		in $post_handling_out;

		set term ^;
		execute block as
		begin
			begin
				-- Inject value of config parameter 'mon_unit_perf' into table SETTINGS:
				update settings set svalue = $mon_unit_perf
				where working_mode=upper('common') and mcode=upper('enable_mon_query');
			when any do
				if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ) ) 
				then exception;
			end

			begin
				-- Inject value of config parameter 'working_mode' into table SETTINGS.
				-- This will be taken in account in the final script 'oltp_data_filling.sql'
				-- which created necessary amount of initial data in lookup tables:
				update settings set svalue=upper('$working_mode')
				where working_mode=upper('init') and mcode=upper('working_mode');
			when any do
				if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ) ) 
				then exception;
			end
	EOF

	if [ -n "$use_external_to_stop" ]; then
		cat <<- EOF >>$bld
			-- External table for quick force running attaches to stop themselves by OUTSIDE command.
			-- When all ISQL attachments need to be stopped before warm_time+test_time expired, this
			-- external table (TEXT file) shoudl be opened in editor and single ascii-character
			-- has to be typed followed by LF. Saving this file will cause test to be stopped.
			recreate table ext_stoptest external '$use_external_to_stop' ( s char(2) );
			commit;
			-- REDEFINITION of view that is used by every ISQL attachment as 'stop-flag' source:
			create or alter view v_stoptest as
			select 1 as need_to_stop
			from ext_stoptest;
			commit;
		EOF
	fi

	cat <<- EOF >>$bld
		end
		^
		set term ^;
		commit;
		-- Finish building process: insert custom data to lookup tables:
		in "$shdir/oltp_data_filling.sql";
	EOF

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
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo

  if [[ $wait_after_create = 1 && $can_stop = 1 ]]; then
    echo Database has been created SUCCESSFULLY and is ready for initial documents filling.
    echo -e "######################################"
    echo
    echo Change config setting \'wait_after_create\' to 0 in order to remove this pause.
    echo
    echo Press ENTER to go on. . .
    pause
  fi

  rm -f $err $tmp $post_handling_out
  rm -f $bld

}

# -------------- s h o w    D B   a n d   t e s t   p a r a m s  -----------------

show_db_and_test_params() {

  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.

  log4all=$1
  local tmp_show_sql=$tmpdir/tmp_show.sql
  local tmp_show_log=$tmpdir/tmp_show.log
  local tmp_show_err=$tmpdir/tmp_show.err

  echo $(date +'%Y.%m.%d %H:%M:%S'). Database parameters, workload level map and current test settings: > $tmp_show_log
  
  # [[ $create_with_split_heavy_tabs == 0 ]] && inject_compound_ordr=",rdb\$get_context('USER_SESSION', 'BUILD_WITH_QD_COMPOUND_ORDR') build_with_qd_compound_ordr"
  # NB: use quoted "EOF" in heredoc clause in order to avoid specifying backslash leftside of any special characters, like $:
  cat <<- EOF >$tmp_show_sql

         set list on;
         set term ^;
         execute block as
            declare c varchar(255);
         begin
              if ( exists(select * from rdb\$procedures where rdb\$procedure_name = upper('sys_get_fb_arch')) ) then
              begin
                  select fb_arch
                  from sys_get_fb_arch('$usr', '$pwd')
                  into c;
                  rdb\$set_context('USER_TRANSACTION', 'FB_ARCH', c);
             end
             else
             begin
                 rdb\$set_context('USER_TRANSACTION', 'FB_ARCH', 'UNKNOWN: missing procedure SYS_GET_FB_ARCH.' );
             end
         end
         ^
         set term ;^
         select
             coalesce( rdb\$get_context('USER_TRANSACTION', 'FB_ARCH'), 'UNKNOWN (EMBEDDED ?)') as fb_arch
            ,m.mon\$database_name as db_name
            ,iif(m.mon\$forced_writes=0,'OFF','ON') as forced_writes
            ,m.mon\$sweep_interval as sweep_int
            ,m.mon\$page_buffers as page_buffers
            ,m.mon\$page_size as page_size
            ,m.mon\$creation_date as creation_timestamp
            ,current_timestamp
         from mon\$database m;
         set list off;

         set list off;
         set width working_mode 12;
         set width setting_name 40;
         set width setting_value 20;
         select * from z_settings_pivot;
         select z.setting_name, z.setting_value from z_current_test_settings z;

         set width tab_name 13;
         set width idx_name 31;
         set width idx_key 45;
         set heading off;
         select 'Index(es) for heavy-loaded table(s):' as " " from rdb\$database;
         set heading on;
         select * from z_qd_indices_ddl;

	EOF

  $fbc/isql $dbconn $dbauth -i $tmp_show_sql 1>>$tmp_show_log 2>$tmp_show_err

  if [ -s $tmp_show_err ];then
    cat $tmp_show_err >> $log4all
    echo Could NOT run script with commands for show database and test parameters.
    echo SQL  file: $tmp_show_sql
    echo Error log: $tmp_show_err
    echo ------------------------------------------------------------------
    cat $tmp_show_err
    cat $tmp_show_err>>$log4all
    echo ------------------------------------------------------------------
    echo
    echo Script is now terminated.
    exit 1
  fi
  rm -f $tmp_show_sql $tmp_show_err

  # Display database and main test parameters + add them to main log:
  cat $tmp_show_log
  cat $tmp_show_log>>$log4all
  rm -f $tmp_show_log
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.

}

# -------------------------------  c h e c k _ s t o p t e s t -----------------------------------

check_stoptest() {
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
  # check that file 'stoptest.txt' is EMPTY
  local pfx=tmp_check_stoptest
  local tmpchk=$tmpdir/$pfx.sql
  local tmpclg=$tmpdir/$pfx.log
  local tmperr=$tmpdir/$pfx.err
  local run_isql="$fbc/isql $dbconn -nod -n -i $tmpchk $dbauth"

  rm -f $tmpchk $tmpclg $tmperr
  echo set heading off\; set list on\;>>$tmpchk
  echo -- check that test now can be run: procedure \'sp_stoptest\' should return EMPTY resultset>>$tmpchk
  echo -n select iif\( exists\( select \* from sp_stoptest \), >>$tmpchk
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
    rm -f $tmpchk $tmpclg $tmperr
  fi
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo
}

# -------------------------------  u p d _ i n i t _ d o c s  ------------------------------------

upd_init_docs() {
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
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
  cat <<- EOF >$tmpchk
      set list on;
      set heading off;
      select count(*) as "old_docs=" from (select id from doc_list rows (1+$init_docs));
	EOF

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
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  rm -f $tmpchk $tmpclg $tmperr
  echo
}

# --------------------------  p r e p a r e:   set linger, change FW to OFF ------------------
prepare_before_adding_init_data() {
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.

  local pfx=tmp_before_adding_init_data
  local tmpsql=$tmpdir/$pfx.sql
  local tmplog=$tmpdir/$pfx.log
  local tmperr=$tmpdir/$pfx.err
  local run_fbs
  local fbspref
  local run_isql="$fbc/isql $dbconn -i $tmpsql -q -nod -n $dbauth"
  
  if [[ $is_embed == 0 ]]; then
     fbspref="$fbc/fbsvcmgr $host/$port:service_mgr user $usr password $pwd "
  else
     fbspref="$fbc/fbsvcmgr service_mgr "
  fi
  rm -f $tmpsql $tmplog $tmperr

  echo Changing attribute FW to OFF.
  run_fbs="$fbspref action_properties dbname $dbnm prp_write_mode prp_wm_async"
  echo Command:
  echo $run_fbs
  $run_fbs 1>>$tmplog 2>>$tmperr
  
  # LI-T3.0.0.31394 Firebird 3.0 Beta 1
  #[[ $fbb == *"Firebird 3"* ]] && echo alter database set linger to 15\;commit\;select rdb\$linger from rdb$database\; >>$tmpsql
  if [ $fbb == *"Firebird 3"* ]; then
     cat <<-"EOF" >>$tmpsql
       alter database set linger to 15;
       commit;
       select rdb$linger from rdb$database;
	EOF
  fi
  
  cat <<- "EOF" >>$tmpsql
    commit;
    set transaction no wait;
    alter sequence g_init_pop restart with 0;
    commit;
    show sequence g_init_pop;
    set list on;
    select iif(m.mon$forced_writes=1, 'ON', 'OFF') as forced_writes from mon$database m;
    set list off;
	EOF

  echo Command that now to be run:
  echo $run_isql
  echo Content of script $tmpsql:
  echo --------------------------
  cat $tmpsql
  echo --------------------------

  $run_isql 1>>$tmplog 2>>$tmperr


  if [ -s $tmperr ];then
    echo Script which changes FW, restarts aux. sequence and, for FB-3, increases  value of linger - finished with ERROR!
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

  echo Result:
  grep -v "^$" $tmplog
  
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo
  rm -f $tmpsql $tmplog $tmperr

} # end of: prepare_before_adding_init_data

# --------------------------  g e n _ w o r k i n g _ s q l  -------------------------

gen_working_sql() {
 echo
 echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
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

 local idle=${6:-0}

 rm -f $sql
 cat <<- EOF
     Input arguments: 
     1) mode:			$mode
     2) sql:			$sql
     3) number-of-EB:		$lim
     4) Tx-undo-clause:	$nau
     5) show-detailed-info:	$nfo
     6) idle-time-seconds:	$idle
	EOF
 
 #echo set tran option: $nau
 echo "-- ### WARNING: DO NOT EDIT ###">>$sql
 echo "-- Generated auto by $shname, routine: $FUNCNAME">>$sql
 if echo $mode | grep -i "^init_pop$" > /dev/null ; then
   cat <<- EOF >>$sql
		-- mode='$mode': get data from mon\$database for verifying settings of database
		-- NB-1: FW must be (temply) set to OFF
		-- NB-2: cache buffers temply set to pretty big value
		set list on; 
		select * from mon\$database; 
		set list off;
	EOF
 fi

 for (( i=1; i<=$lim; i++ ))
 do
    
    [[ $((  $i % $verb )) = 0 ]] && echo Done generating iter $i of total $lim
    echo "----------------- mode = $mode, iter # $i -----------------------">>$sql
    echo>>$sql

    #[[ $i = 1 ]] && echo commit\;>>$sql

    if [ $i = 1 ]; then
      echo commit\;>>$sql
    else
      if [ $idle -gt 0 ]; then
	    cat <<-EOF >>$sql
             -- Take delay between transactions. Argument for 'sleep' command
             -- is in SECONDS and is equal to 'idle_time' parameter in config.
             set list on;
             commit;
             select current_timestamp as "Delay $idle seconds starting at: "
             from rdb\$database;
             commit;
             ----------------------------- p a u s e--------------------------------
             shell sleep $idle;
             -----------------------------------------------------------------------
             set transaction read only read committed;
             select current_timestamp as "Delay $idle seconds finished at: "
             from rdb\$database;
             commit;
             set list off;
		EOF
      else
	    cat <<-EOF >>$sql

             -- Delay between transactions is DISABLED.
             -- For enabling them set value of 'idle_time' parameter
             -- in test config file to some value > 0.

		EOF
      fi
    fi


    cat <<-EOF >>$sql
			-- check oltp_config.NN for optional setting NO AUTO UNDO here:
			set transaction no wait $nau;
	EOF

    cat <<- EOF >>$sql
		------ ##############################################
		-----  R A N D O M    S E L E C T    A P P.   U N I T
		------ ##############################################
		set term ^;
		execute block as
		  declare v_unit dm_name;
		begin
	EOF
	

      if echo $mode | grep -i "^init_pop$" > /dev/null ; then
        cat <<- EOF >>$sql
			  -- SKIP choise of application units which REMOVE documents:
			  select p.unit
			  from srv_random_unit_choice(
			     ''
			    ,'creation,state_next,service,'
			    ,''
			    ,'removal'
			  ) p
			  into v_unit; 
		EOF
      fi # $mode='init_pop'
 
      if echo $mode | grep -i "^run_test$" > /dev/null ; then #
        cat <<-EOF >>$sql
			  if ( NOT exists( select * from sp_stoptest ) ) then
			    begin
			      select p.unit
			      from srv_random_unit_choice(
			         ''
			         ,''
			         ,''
			         ,''
			      ) p
			      into v_unit;
			    end
			  else
			    v_unit = 'TEST_WAS_CANCELLED';
		EOF
      fi # # $mode='run_test'
      cat <<- EOF >>$sql
			  -- This will be shown in .log of working SQL script:
			  rdb\$set_context('USER_SESSION','SELECTED_UNIT', v_unit);
			  rdb\$set_context('USER_SESSION','ADD_INFO', null);
			end^
			set term ;^
		EOF

    if echo $mode | grep -i "^run_test$" > /dev/null ; then # run_test
      if [ $mon_unit_perf = 1 ]; then
        cat <<- "EOF" >>$sql
			------ ###############################################  -------
			-----  G A T H E R    M O N.    D A T A    B E F O R E  -------
			------ ###############################################  -------
			set term ^;
			execute block as
			    declare v_dummy bigint;
			begin
			    rdb$set_context('USER_SESSION','MON_GATHER_0_BEG', 
					      datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp) to cast('now' as timestamp) ) 
					    );
			    -- define context var which will identify rowset field
			    -- in mon_log and mon_log_table_stats:
			    -- (this value is ised after call app. unit):
			    rdb$set_context('USER_SESSION','MON_ROWSET', gen_id(g_common,1));
			
			    -- Gather mon$ tables BEFORE run app unit.
			    -- Add FIRST row to GTT tmp\$mon_log - statistics on 'per unit' basis.
			    -- Note: for FB 3.0 - also add first rowset into table tmp\$mon_log_table_stats.
			    select count(*)
			    from srv_fill_tmp_mon(
			            rdb$get_context('USER_SESSION','MON_ROWSET')    -- :a_rowset
			           ,1                                   -- :a_ignore_system_tables
			           ,rdb$get_context('USER_SESSION','SELECTED_UNIT') -- :a_unit
						        )
			    into v_dummy;
			
			    -- result: tables tmp\$mon_log and tmp\$mon_log_table_stats
			    -- are filled with counters BEFORE application unit call.
			    -- Field "mult" in these tables is now negative: -1
			    rdb$set_context('USER_SESSION','MON_GATHER_0_END',
					      datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp) to cast('now' as timestamp) ) 
					    );
			end
			^
			set term ;^
		EOF
		cat <<- EOF >>$sql
			commit; --  ##### C O M M I T  #####  after gathering mon$data
			set transaction no wait $nau;
		EOF
      else
        cat <<- EOF >>$sql
			-- Gathering statistics data from MON$ tables DISABLED.
			-- For enabling it set value of config parameter 'mon_unit_perf' to 1.
		EOF
      fi # mon_unit_perf = 1
    fi # mode = 'run_test' - gather mon info BEFORE application unit call


    cat <<- EOF >>$sql

		------ ###############################################  -------
		-----  S H O W   S E L E C T E D    U N I T    N A M E  -------
		------ ###############################################  -------
		set heading off;
		select lpad('',40,'+') || ' Action # $i of $lim ' || rpad('',40,'+') as " " from rdb\$database;
		set heading on;

		set width dts 12;
		set width trn 14;
		set width att 14;
		set width unit 31;
		set width elapsed_ms 10;
		set width msg 16;
		set width add_info 40;
		set width mon_logging_info 20;

		-- ensure that just before call application unit
		-- table tmp\$perf_log is really EMPTY:
		delete from tmp\$perf_log;

		set list off;
		select
		      substring(cast(current_timestamp as varchar(24)) from 12 for 12) as dts
		      ,'tra_'||current_transaction                                     as trn
		      ,'att_'||current_connection                                      as att
		      , rdb\$get_context('USER_SESSION','SELECTED_UNIT')               as unit
		      ,'start'                                                         as msg
		      ,'iter # $i  of $lim'                                            as add_info
		from rdb\$database;

		SET STAT ON;

		set term ^;
		execute block as
		      declare v_stt varchar(128);
		      declare result int;
		      declare v_old_docs_num int;
		      declare v_success_ops_increment int;
		begin
	EOF
    if echo $mode | grep -i "^init_pop$" > /dev/null ; then
      cat <<- "EOF" >>$sql
		  -- ::: nb ::: g_init_pop is always incremented by 1
		  -- in sp_add_doc_list, even if fault will occur later
		  -- set context var 'INIT_DATA_POP' to not-null for analyzing
		  -- in sp_customer_reserve and others SPs and raise ex~ception
		  rdb$set_context('USER_TRANSACTION','INIT_DATA_POP',1);
		  v_old_docs_num = gen_id( g_init_pop, 0);
		EOF
    fi
    
    cat <<- EOF >>$sql
		  begin
		    -- save in ctx var timestamp of START app unit:
		    rdb\$set_context('USER_SESSION','BAT_PHOTO_UNIT_DTS', cast('now' as timestamp));
		    rdb\$set_context('USER_SESSION', 'GDS_RESULT', null);
		    -- save value of current_transaction because we make COMMIT
		    -- after gathering mon$ tables when oltp_config.NN parameter
		    -- mon_unit_perf=1
		    rdb\$set_context('USER_SESSION', 'APP_TRANSACTION', current_transaction);

		    if ( rdb\$get_context('USER_SESSION','SELECTED_UNIT')
		       is distinct from
		       'TEST_WAS_CANCELLED'
		    ) then
		      begin
			        rdb\$set_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT', null);
			        v_stt='select count(*) from ' || rdb\$get_context('USER_SESSION','SELECTED_UNIT');
			        ------   ######################################### ------
			        ------   r u n    a p p l i c a t i o n    u n i t ------
			        ------   ######################################### ------
			        execute statement (v_stt) into result;
			        rdb\$set_context('USER_SESSION', 'RUN_RESULT',  'OK, '|| result ||' rows');
			        -- Get count of 'atomic' business operations that occured 'under-cover' of SELECTED_UNIT:
			        v_success_ops_increment = cast(rdb\$get_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT') as int);
			        ---------------------------------------------------------------
			        -- Increment counter of SUCCESSFULLY finished business asctions
			        -- for using later in ESTIMATED performance value:
			        ---------------------------------------------------------------
			        result = gen_id( g_success_counter, v_success_ops_increment );
		      end
		    else
		      begin
			        rdb\$set_context('USER_SESSION','RUN_RESULT',
			            ( select coalesce(e.fb_mnemona, 'gds_'||g.fb_gdscode)
			              from perf_log g
			              left join fb_errors e on g.fb_gdscode=e.fb_gdscode
			              where g.unit='sp_halt_on_error'
			              order by g.dts_end DESC rows 1
			            )
			        );
		    end
		    -- add timestamp for FINISH app unit:
		    rdb\$set_context( 'USER_SESSION','BAT_PHOTO_UNIT_DTS',
			                rdb\$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS')
			                || ' '
			                || cast('now' as timestamp)
			   );
		  when any do
		    begin
		      rdb\$set_context('USER_SESSION', 'GDS_RESULT', gdscode);

	EOF

    if echo $mode | grep -i "^init_pop$" > /dev/null ; then
      cat <<- EOF >>$sql
		      v_stt = 'alter sequence g_init_pop restart with ' || v_old_docs_num;
		      execute statement (v_stt);
		EOF
    fi

    cat <<- EOF >>$sql
		      rdb\$set_context('USER_SESSION', 'RUN_RESULT', 'error, gds=' || gdscode );
		      --- ##############################
		      --- r a i s e    e x c e p t i o n
		      --- ##############################
		      exception;
		    end
		  end
		end
		^
		set term ;^
		SET STAT OFF;
	EOF

    if echo $mode | grep -i "^run_test$" > /dev/null ; then # run_test
      if [ $mon_unit_perf = 1 ]; then
        cat <<- EOF >>$sql
			----- ###############################################  -------
			-----  G A T H E R    M O N.    D A T A    A F T E R    -------
			----- ###############################################  -------
			set term ^;
			execute block as
			    declare v_dummy bigint;
			begin
			    rdb\$set_context('USER_SESSION','MON_GATHER_1_BEG', 
			            datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp) to cast('now' as timestamp) ) 
			    );
			    -- Gather mon$ tables BEFORE run app unit.
			    -- Add second row to GTT tmp\$mon_log - statistics on 'per unit' basis.
			    -- Note: for FB 3.0 - also add first rowset into table tmp\$mon_log_table_stats.
			    select count(*) from srv_fill_tmp_mon
			    (
			            rdb\$get_context('USER_SESSION','MON_ROWSET')    -- :a_rowset
			           ,1                                                -- :a_ignore_system_tables
			           ,rdb\$get_context('USER_SESSION','SELECTED_UNIT') -- :a_unit
			           ,coalesce(                                        -- :a_info
			                 rdb\$get_context('USER_SESSION','ADD_INFO') -- aux info, set in APP units only!
			                ,rdb\$get_context('USER_SESSION','RUN_RESULT')
			               )
			           ,rdb\$get_context('USER_SESSION', 'GDS_RESULT')   -- :a_gdscode
			    )
			    into v_dummy;
			    rdb\$set_context('USER_SESSION','MON_GATHER_1_END', 
			            datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp) to cast('now' as timestamp) ) 
			    );
			    -- add pair of rows with aggregated differences of mon$
			    -- counters from GTT to fixed tables
			    -- (this SP also removes data from GTTs):
			    select count(*)
			    from srv_fill_mon(
			                       rdb\$get_context('USER_SESSION','MON_ROWSET') -- :a_rowset
			                     )
			    into v_dummy;
			    rdb\$set_context('USER_SESSION','MON_ROWSET', null);
			end
			^
			set term ;^
			commit; --  ##### C O M M I T  #####  after gathering mon$data
			set transaction no wait $nau;
		EOF
      fi # mon_unit_perf = 1

		cat <<- EOF >>$sql
			----- ####################################################  -------
			-----  S H O W    R E S U L T S    O F   E X E C U T I O N
			----- ####################################################  -------
		EOF

#		if [ $i = 1 ]; then
#		  end_time_dts="left( cast( p.dts_end as varchar(24) ), 19 )"
#		else
#		  end_time_dts="left( cast( rdb\$get_context('USER_SESSION','PERF_WATCH_END') as varchar(24)), 19)"
#		fi

		end_time_dts="left( cast( rdb\$get_context('USER_SESSION','PERF_WATCH_END') as varchar(24)), 19)"
		cat <<- EOF >>$sql
			set list on;
			select
			    $end_time_dts as test_ends_at
			    ,rdb\$get_context('USER_SESSION','GDS_RESULT') as last_operation_gds_code
			    ,lpad( iif( minutes_since_start > 0, 1.00 * success_ops_count / minutes_since_start, 0 ), 12, ' ' )
			     ||
			     lpad( minutes_since_start, 7, ' ')
			     as est_overall_at_minute_since_beg
		EOF
		if [ $mon_unit_perf = 1 ]; then
        	cat <<- EOF >>$sql
				    -- this variable will be defined in SP srv_fill_mon:
				    ,rdb\$get_context('USER_SESSION','MON_INFO') as mon_logging_info
				    ,cast( rdb\$get_context('USER_SESSION','MON_GATHER_0_END') as bigint)
				     - cast( rdb\$get_context('USER_SESSION','MON_GATHER_0_BEG') as bigint)
				     + cast( rdb\$get_context('USER_SESSION','MON_GATHER_1_END') as bigint)
				     - cast( rdb\$get_context('USER_SESSION','MON_GATHER_1_BEG') as bigint)
				     as mon_gathering_time_ms
				    ,rdb\$get_context('USER_SESSION','TRACED_UNITS') as traced_units
			EOF
		else
        	cat <<- EOF >>$sql
				    ,'MON$ querying DISABLED, see config ''mon_unit_perf''' as mon_logging_info
			EOF
		fi
		cat <<- EOF >>$sql
		    ,rdb\$get_context('USER_SESSION','WORKING_MODE') as workload_type
		    ,rdb\$get_context('USER_SESSION','HALT_TEST_ON_ERRORS') as halt_test_on_errors
		    ,rdb\$get_context('USER_SESSION','QMISM_VERIFY_BITSET') as qmism_verify_bitset
		EOF
		
		cat <<- EOF >>$sql
			from (
			  select
			    gen_id( g_success_counter, 0 ) as success_ops_count
			    ,datediff( minute
			               -- Variable 'PERF_WATCH_BEG' is assigned with value from table PERF_LOG, see SP sp_check_to_stop_work:
			               -- ... from perf_log where p.unit = 'perf_watch_interval' and p.info containing 'active'.
			               -- We need to substract %warm_time% from the moment PERF_WATCH_BEG because sequence
			               -- of successfully finished business ops is increased from ACTUAL start rather than 
			               -- timestamp PERF_WATCH_BEG which is used for reports:
			               from dateadd( -$warm_time minute to cast( rdb\$get_context('USER_SESSION','PERF_WATCH_BEG') as timestamp) )
			               to current_timestamp
			             ) -- datediff minus config "warm_time" value
			             as minutes_since_start
		EOF
		if [ $i = 1 ]; then
			cat <<- EOF >>$sql
				    ,p.dts_end
				  from perf_log p
				  where p.unit = 'perf_watch_interval'
				  order by dts_beg desc
				  rows 1
				) p;
				set list off;
			EOF
		else
			cat <<- EOF >>$sql
					from rdb\$database
				) p;
				set list off;
			EOF
		fi
    fi # mode = 'run_test'

	cat <<- "EOF" >>$sql
		-- Output results of application unit run:
		set width msg 20;
		select
		    substring(cast(current_timestamp as varchar(24)) from 12 for 12) as dts
		    ,'tra_' || rdb$get_context('USER_SESSION','APP_TRANSACTION') trn
		    ,rdb$get_context('USER_SESSION','SELECTED_UNIT') as unit
		    ,lpad(
		           cast(
		                 datediff(
		                   millisecond
		                   from cast(left(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'),24) as timestamp)
		                   to   cast(right(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'),24) as timestamp)
		                        )
		                as varchar(10)
		               )
		          ,10
		          ,' '
		        ) as elapsed_ms
		    ,rdb$get_context('USER_SESSION', 'RUN_RESULT') as msg
		    ,rdb$get_context('USER_SESSION','ADD_INFO') as add_info
		from rdb$database;
	EOF

    if echo $mode | grep -i "^init_pop$" > /dev/null ; then
		cat <<- "EOF" >>$sql
		set list on;
		set width db_name 80;
		select
		  m.mon$database_name db_name,
		  rdb$get_context('SYSTEM','ENGINE_VERSION') engine,
		  iif(mon$forced_writes=1,'ON','OFF') forced_writes,
		  mon$page_buffers page_buffers,
		  m.mon$page_size * m.mon$pages as db_current_size,
		  gen_id( g_init_pop, 0) as new_docs_created
		from mon$database m;
		EOF
    fi

	cat <<- "EOF" >>$sql
		set bail on; -- for catch test cancellation and stop all .sql
		set term ^;
		execute block as
		begin
		    if ( rdb$get_context('USER_SESSION','SELECTED_UNIT')
		         is NOT distinct from
		         'TEST_WAS_CANCELLED'
		      ) then
		    begin
		       exception ex_test_cancellation;
		    end
		    -- REMOVE data from context vars, they will not be used more
		    -- in this iteration:
		    rdb$set_context('USER_SESSION','SELECTED_UNIT', null);
		    rdb$set_context('USER_SESSION','RUN_RESULT',    null);
		    rdb$set_context('USER_SESSION','GDS_RESULT',    null);
		    rdb$set_context('USER_SESSION','ADD_INFO', null);
		    rdb$set_context('USER_SESSION','APP_TRANSACTION', null);
		    rdb$Set_context('USER_SESSION','MON_GATHER_0_BEG', null);
		    rdb$Set_context('USER_SESSION','MON_GATHER_0_END', null);
		    rdb$Set_context('USER_SESSION','MON_GATHER_1_BEG', null);
		    rdb$Set_context('USER_SESSION','MON_GATHER_1_END', null);
		end
		^
		set term ;^
		set bail off;
	EOF

    if echo $mode | grep -i "^run_test$" > /dev/null ; then # run_test
      if [ $nfo = 1 ]; then
		cat <<- EOF >>$sql
			-- Begin block to output DETAILED results of iteration.
			-- To disable this output change "detailed_info" setting to 0
			-- in test configuration file "$cfg"
			set heading off;
			set list on;
			select '+++++++++  perf_log data for this Tx: ++++++++' as msg
			from rdb\$database;
			set heading on;
			set list on;
			set width unit 35;
			set width info 80;
			select g.id, g.unit, g.exc_unit, g.info, g.fb_gdscode,g.trn_id,
			       g.elapsed_ms, g.dts_beg, g.dts_end
			from perf_log g
			where g.trn_id = current_transaction;
			-- do NOT add:  order by id;
			set list off;
			-- Finish block to output DETAILED results of iteration.
		EOF
      else
		cat <<- EOF >>$sql
			-- Output of detailed results of iteration DISABLED.
			-- To enable this output change "detailed_info" setting to 1
			-- in test configuration file "$cfg"
		EOF
      fi # $nfo=1 or 0
    fi # mode=run_test

	cat <<- EOF >>$sql
		commit;
		set list off;
	EOF

    ################################
    #DO NOT CHANGE FINAL MESSAGE: "FINISH packet" - it is used in decision about whether this .sql should be recreated or no.
    ###############################

    if [ $i -eq $lim ]; then
		cat <<- EOF >>$sql
			set width msg 60;
			select
			  current_timestamp dts,
			  '### FINISH packet, disconnect ###' as msg
			from rdb\$database;
		EOF
    fi


 done # i=1..$lim
 echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
 echo


} # end of gen_working_sql()

# --------------------------  a d d_ i n i t _ d o c s  -------------------------


add_init_docs() {
  # $tmpsql $tmplog $srv_frq
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
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
  
  local k=1
  local prf=tmp_chk_docs_count
  local tmpchk=$tmpdir/$prf.sql
  local tmpclg=$tmpdir/$prf.log
  while :
  do

    if [ $(( k % $srv_frq )) -eq 0  ]; then
      rm -f $tmpchk $tmpclg

		cat <<- EOF >>$tmpchk
			set list on; 
			set heading on;
			commit;
			set transaction no wait;
			echo select count(*) as srv_make_invnt_saldo_result from srv_make_invnt_saldo;
			select * from srv_make_invnt_saldo;
			commit;
			set transaction no wait;
			echo select count(*) as srv_make_money_saldo_result from srv_make_money_saldo;
			select * from srv_make_money_saldo;
			commit;
			set transaction no wait;
			echo select count(*) as srv_recalc_idx_stat_result from srv_recalc_idx_stat;
			select * from srv_recalc_idx_stat;
			commit;
		EOF

      echo -ne "$(date +'%Y.%m.%d %H:%M:%S'), start service SPs... "
      # --------------- perform service: srv_make*_total, recalc index statistics -------------
      cat $tmpchk>>$tmplog
      run_isql="$fbc/isql $dbconn -i $tmpchk -c $init_buff -n -m -o $tmplog $dbauth"

      $run_isql

      echo -e "$(date +'%Y.%m.%d %H:%M:%S'), finish service SPs."
    fi

    echo -ne "$(date +'%Y.%m.%d %H:%M:%S'), packet $k start... "

    # Common application unit: create several documents
    # using .sql which was made in func gen_working_sql
    ###################################################
    run_isql="$fbc/isql $dbconn -i $tmpsql -c $init_buff -m -m2 -o $tmplog $dbauth"

    $run_isql

    # result: one or more (in case of complex operations like sp_add_invoice_to_stock)
    # documents has been created; if some error occured, sequence g_init_pop has been
    # 'returned' to its previous value.
    # now we must check total number of docs:
    rm -f $tmpchk $tmpclg
	cat <<- "EOF" >$tmpchk
		set list on;
		select gen_id( g_init_pop, 0 ) as "new_docs=" from rdb$database;
		set list off;
	EOF

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

    echo -e "$(date +'%Y.%m.%d %H:%M:%S'), packet $k finish: docs created: >>>$new_docs<<<, limit: $init_docs"
    [[ $new_docs -gt $init_docs ]] && break
    k=$(( k+1 ))

  done
  rm -f $tmpsql $tmplog $tmpchk $tmpclg
  
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo
} # end of add_init_docs()

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
    # ##########################################################################
    gen_working_sql run_test $tmpsql 300 $no_auto_undo $detailed_info $idle_time
    #                  1        2     3       4             5             6
    # ##########################################################################
  fi

  local prf=tmp_add_aux_rows
  local tmpchk=$tmpdir/$prf.sql
  local tmpclg=$tmpdir/$prf.log
  local tmperr=$tmpdir/$prf.err
  local run_isql="$fbc/isql $dbconn -i $tmpchk $dbauth"
  
  rm -f $tmpchk $tmpclg
  echo Add record for checking work to be stopped on timeout.

	cat <<- EOF >>$tmpchk
		set bail on;
		commit;
		set transaction no wait;
		-- NB: we have to enclose potentially update-conflicting statements in begin..end blocks with EMPTY when-any section
		-- because of possible launch test from several hosts.
		set term ^;
		execute block as
		begin
			begin
				delete from perf_estimated; -- this table will be used in report "Performance for every MINUTE", see query to z_estimated_perf_per_minute
				when any do
				begin
					-- nop --
				end
			end
			begin
				delete from perf_log g
				where g.unit in ( 'perf_watch_interval',
		                          'sp_halt_on_error',
		                          'dump_dirty_data_semaphore',
		                          'dump_dirty_data_progress'
		                        );
				when any do
				begin
					-- nop --
				end
			end
		end
		^
		set term ^;
		commit;
		insert into perf_log( unit,                  info,     exc_info,
		                      dts_beg, dts_end, elapsed_ms)
		              values( 'perf_watch_interval', 'active', 'by $0',
		        dateadd( $warm_time minute to current_timestamp),
		        dateadd( $warm_time + $test_time minute to current_timestamp),
		        -1 -- skip this record from being displayed in srv_mon_perf_detailed
		        );
		insert into perf_log( unit,                        info,  stack,
		                      dts_beg, dts_end, elapsed_ms)
		              values( 'dump_dirty_data_semaphore', '',    'by $0',
		                      null, null, -1);
		alter sequence g_success_counter restart with 0;
		commit;
		set width unit 20;
		set width add_info 30;
		set width dts_measure_beg 19;
		set width dts_measure_end 19;
		set list on;
		select
		       g.dts_measure_beg
		      ,g.dts_measure_end
		from
		(
		  select p.unit, p.exc_info as add_info,
		     left(replace(cast(p.dts_beg as varchar(24)),' ','_'),19) as dts_measure_beg,
		     left(replace(cast(p.dts_end as varchar(24)),' ','_'),19) as dts_measure_end
		  from perf_log p
		       where p.unit = 'perf_watch_interval'
		       order by dts_beg desc rows 1
		) g;
		set list off;
	EOF

  echo Command to be run:
  echo $run_isql

  $run_isql 1>$tmpclg 2>$tmperr

  if [ -s $tmperr ];then
    echo Attempt to add singnal row for auto stop test finished with ERROR.
    echo SQL  file: $tmpchk
    echo Error log: $tmperr
    echo ------------------------------------------------------------------
    cat $tmperr
    echo ------------------------------------------------------------------
    echo
    echo Script is now terminated.
    exit 1
  fi

  echo Time limits for this test session:
  cat $tmpclg
  cat $tmpclg >> $log4all
  rm -f $tmpchk $tmpclg $tmperr

  echo Routine $FUNCNAME: finish.
  echo

} # end of launch_preparing()

gen_temp_sh_for_stop()
{
  #echo Routine $FUNCNAME: start.
  local tmpsh4stop
  if [ -z "$use_external_to_stop" ]; then
	tmpsh4stop=$tmpdir/1stoptest.tmp.sh
	cat <<- EOF >$tmpsh4stop
	    # --------------------------------------------------------------------------------
	    # Generated auto, do NOT edit.
	    # This scenario can be used in order to immediatelly STOP all working ISQL sessions.
	    # It is highly rtecommended to use this script for that goal rather than brute kill
	    # ISQL sessions or use Firebird monitoring tables.
	    # --------------------------------------------------------------------------------
	    echo \$(date +'%Y.%m.%d %H:%M:%S'). Running command to stop all working ISQL sessions:
	    echo -e "show sequ g_stop_test; alter sequence g_stop_test restart with -999999999; commit; show sequ g_stop_test;" | $fbc/isql $dbconn $dbauth -q -n -nod
	    echo \$(date +'%Y.%m.%d %H:%M:%S') Done.
	EOF
	chmod +x $tmpsh4stop
	echo In order to premature stop all working ISQL sessions run following script:
	echo $tmpsh4stop
  else 
	cat <<- EOF
		In order to premature stop all working ISQL sessions open server-side file '$use_external_to_stop' 
		in editor and type there any single ascii character plus LF. Then save this file.
	EOF
  fi
  #echo Routine $FUNCNAME: finish.
} # create_temp_sh_for_stop(


#######################################################################
# ----------------------------   M A I N   ----------------------------
#######################################################################


[ -z $1 ] && msg_noarg && exit 1
[ -z $2 ] && msg_noarg && exit 1

echo Intro $0: arg1=$1, arg2=$2, arg3=$3

export fb=$1
export k=$2

# 19.04.2016: disable any pause, even severe, when this script is launched from scheduler:
can_stop=1
if [ "$3" == "nostop" ];then
  can_stop=0
fi
export can_stop

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
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
        declare $lhs=$rhs
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
done<$cfg

# Remove trailing slash from variables which store PATHs:
fbc=${fbc%/}
tmpdir=${tmpdir%/}

# stackoverflow.com/questions/1921279/how-to-get-a-variable-value-if-variable-name-is-stored-as-string
echo -ne "Check that all necessary environment variables have values. . . "
vars=(tmpdir fbc is_embed dbnm create_with_fw create_with_sweep wait_if_not_exists wait_after_create no_auto_undo detailed_info create_with_debug_objects mon_unit_perf init_docs init_buff wait_for_copy warm_time test_time idle_time create_with_split_heavy_tabs create_with_separate_qdistr_idx)
for i in ${vars[@]}; do
  #echo -e $i=\|${!i}\|
  [[ -z ${!i} ]] && msg_novar $i $cfg && exit 1
done
echo Ok.

vars=(isql fbsvcmgr)
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
while read a b c d
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
rndname=$RANDOM

if [[ $fb != 25 ]]; then
   fb30exc_1 = "using ('settings', 'working_mode=''COMMON'' and mcode=''ENABLE_MON_QUERY''')"
   fb30exc_2 = "using ('settings', 'working_mode=''INIT'' and mcode=''WORKING_MODE''')"
fi

cat <<- EOF >>$tmpchk
		 set heading off;
		 set list on;
		 set bail on;
		 -- check that all database objects already exist:
		 select iif( exists( select * from semaphores where task='all_build_ok' ),
		                     'all_dbo_exists',
		                     'some_dbo_absent'
		           ) as "build_result="
		 from rdb\$database;
		 -- Check that database is not in read_only mode.
		 -- NOTE: we create GTT in order to check *not* only ability to write into database file,
		 -- but also to check that Firebird process has enough rights to WRITE into GTT files.
		 -- These files are created in the folder that is defined by 1st environment variable:
		 -- from following list: 1) FIREBIRD_TMP; 2) TMP; or in 3) /tmp (for POSIX).
		 -- When Firebird process has no rights to that directory, test will fail with message:
		 -- #####################################################
		 -- Statement failed, SQLSTATE = 08001
		 -- I/O error during "open O_CREAT" operation for file ""
		 -- -Error while trying to create file
		 -- -No such file or directory
		 -- #####################################################
		 -- See also: sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1176238&msg=18172438
		 recreate GLOBAL TEMPORARY table tmp\$$rndname(id int, s varchar(36) unique using index tmp_s_unq_$rndname );
		 commit;
		 set count on;
		 insert into tmp\$$rndname(id, s) select rand()*1000, uuid_to_char(gen_uuid()) from rdb\$types;
		 set list on;
		 select min(id) as id_min, max(id) as id_max, count(*) as cnt from tmp\$$rndname;
		 commit;
		 drop table tmp\$$rndname;
		 -- This sequence serves as 'stop-flag' for every ISQL attachment:
		 alter sequence g_stop_test restart with 0;
		 set term ^;
		 execute block as
		 begin
			 begin
			     -- Inject value of config parameter 'mon_unit_perf' into table SETTINGS.
			     -- ::: NB ::: When test is launched from several hosts this DML can fail
			     -- with update conflict or "deadlock" exception, so we have to suppress it:
			     update settings set svalue=$mon_unit_perf
			     where working_mode=upper('common') and mcode=upper('enable_mon_query');
			     if (row_count = 0) then
			         exception ex_record_not_found
		       	  $fb30exc_1
			     ;
			 when any do
			     begin
		       	 if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ) ) then exception;
			     end
			 end
	
			 begin
			     -- Inject value of config parameter 'working_mode' into table SETTINGS.
			     -- ::: NB ::: When test is launched from several hosts this DML can fail
			     -- with update conflict or "deadlock" exception, so we have to suppress it:
			     update settings set svalue = upper('$working_mode')
			     where working_mode=upper('init') and mcode=upper('working_mode');
			     if (row_count = 0) then
			         exception ex_record_not_found
			         $fb30exc_2
			     ;
			 when any do
			     begin
			        if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ) ) then exception;
			     end
			 end 
		 end
		 ^
		 set term ;^
		 commit;
EOF

run_isql="$fbc/isql $dbconn -i $tmpchk -q -nod -n -c 256 $dbauth"
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
  cat <<- EOF
		######################################################################
		Database >$dbnm< does NOT exist 
		on host >$host< 
		or has a problem with ACCESS to it.
		Content of error log:
		--------------------
	EOF

  cat $tmperr
  
  cat <<- EOF
		--------------------
		Press ENTER for attempt to CREATE it, Ctrl-C to QUIT.
		#####################################################
	EOF
  if [[ $wait_if_not_exists = 1 && $can_stop = 1 ]]; then
    pause
  fi

  #........................  c r e a t e    d a t a b a s e  ..............
  db_create

  # ....................... b u i l d    d b    o b j e c t s .............
  db_build

else

  badmsg=$(grep -i "Is a directory\|unavailable database\|unsupported on-disk\|shutdown" $tmperr | wc -l)
  [[ $badmsg -gt 0 ]] && msg_no_build_result $tmpchk $tmperr || echo "Database exists and online"

  # database DOES exist and ONLINE, but we have to ensure that ALL objects was successfully created in it.
  db_build_finished_ok=0
  if [ -s $tmperr ];then
    echo Script that verifies finish of DB building process is NOT EMPTY.
    echo Name of script: $tmpclg
    echo Name of errlog: $tmperr
    echo
    echo Seems that at least one database object not found.
  else
    # open log and parse it as config with 'param = value' string:
    echo No errors detected when run $tmpchk
    echo Obtain results from its log $tmpclg
    if grep -i "all_dbo_exists" $tmpclg > /dev/null ; then    
      db_build_finished_ok=1
    fi
  fi
  echo db_build_finished_ok=\|$db_build_finished_ok\|
  echo -e -n Result:' ' && [[ $db_build_finished_ok -eq 1 ]] && echo database is READY for work. || echo database needs to be REBUILT.

  if [ $db_build_finished_ok -eq 0 ]; then
    echo
    echo -e Database: \>$dbnm\< -- DOES exist but
    echo process of creation its objects was not completed.
    echo
    if [[ $wait_if_not_exists = 1 && $can_stop = 1 ]]; then
        echo -e '################################################################################'
        echo Press ENTER to start again recreation of all DB objects or Ctrl-C to FINISH. . .
        echo -e '################################################################################'
        pause
    fi

    # ....................... b u i l d    d b    o b j e c t s .............
    db_build

  fi

fi # grep "Error while trying to open" $tmperr ==> true or false

rm -f $tmpclg $tmperr $tmpchk


# ....................... check that file 'stoptest.txt' is EMPTY .....................
if [ -n "$use_external_to_stop" ]; then
  check_stoptest
else
  echo Config parameter 'use_external_to_stop' is UNDEFINED, this is DEFAULT.
  echo SKIP checking for non-empty external file.
fi


# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# INITIATE REPORT FILE "oltp30.report.txt"
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
log4all=$tmpdir/oltp$1.report.txt
rm -f $log4all
##########################################

this_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
cat <<- EOF > $log4all
	$(date +'%Y.%m.%d %H:%M:%S'). Created by: $this_sh, at host: $file_name_this_host_info
EOF

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
  msg="$(date +'%Y.%m.%d %H:%M:%S'). Start initial data population until total number of documents will be not less than $(( existing_docs +  init_docs ))."
  echo $msg
  echo $msg>>$log4all
  echo
  echo Please wait. . .
  echo

  # 1. set linger to 15 (only for 3.0; greatly reduce time of connect!),
  # 2. temply change FW to OFF with saving old value of it.
  # 3. alter sequence g_init_pop restart with 0;
  ####################
  prepare_before_adding_init_data
  ####################

  # 3. generate temp .sql script for initial filling:
  export init_pkq=50 # number of transactions in .sql (reduce re-connects)

  ########################################################
  gen_working_sql init_pop $tmpsql $init_pkq $no_auto_undo
  #                  1        2       3           4
  ########################################################

  # 4. Run just generated SQL: add new documents until their count less than $init_docs parameter:
  export srv_frq=10 # frequency of service procedures call (srv_make_invnt_saldo, srv_make_money_saldo, srv_recalc_idx_stat)

  ######################################
  add_init_docs $tmpsql $tmplog $srv_frq
  ######################################

  msg="$(date +'%Y.%m.%d %H:%M:%S'). Setting FW to the config parameter 'create_with_fw' value: $create_with_fw"
  echo $msg
  echo $msg>>$log4all
  if [[ $is_embed == 0 ]]; then
    fbspref="$fbc/fbsvcmgr $host/$port:service_mgr user $usr password $pwd "
  else
    fbspref="$fbc/fbsvcmgr service_mgr "
  fi
  run_fbs="$fbspref action_properties dbname $dbnm prp_write_mode prp_wm_$create_with_fw"
  echo Command:
  echo $run_fbs
  echo $run_fbs>>$log4all
  $run_fbs 1>$tmp$clg 2>&1

  msg="Check attributes line from DB header info:"
  echo $msg
  echo $msg>>$log4all
  run_fbs="$fbspref action_db_stats dbname $dbnm sts_hdr_pages"
  $run_fbs | grep -i attributes 1>>$tmpclg 2>&1
  cat $tmpclg
  cat $tmpclg>>$log4all
  rm -f $tmpclg

  msg="$(date +'%Y.%m.%d %H:%M:%S'). FINISH initial data population."
  echo $msg
  echo $msg>>$log4all
  echo
  if [[ $wait_for_copy = 1 && $can_stop = 1 ]]; then
    echo "### NOTE ###"
    echo
    echo It\'s a good time to make COPY of test database in order 
    echo to start all following runs from the same state.
    echo
    echo Press ENTER to begin WARM-UP and TEST mode. . .
    pause
  fi

fi # $init_docs -gt 0


# ...................... s h o w    D B   a n d    t e s t    p a r a m s  ............
show_db_and_test_params $log4all

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

# 1. If config parameter $use_external_to_stop IS defined, output its value with note about ability to stop
#    all working ISQL sessions by adding single character + LF into this file.
# 2. If $use_external_to_stop is UNDEFINED, create temp shell script in $tmpdir with name '1stoptest.tmp.sh'
#    and display message about ability to stop test by running this temp script.
####################
gen_temp_sh_for_stop
####################

# 30.10.2015
if [ -n "$file_name_with_test_params" ]; then
	cat <<- EOF > $tmpchk
		set heading off;
		-- NB: here we pass $test_time value as argument A_TEST_TIME_MINUTES for SP SRV_GET_REPORT_NAME: this value
		-- mean that we want to get ESTIMATED name of report with '0000' as performance score - rather that ACTUAL name
		-- which will be obtained AFTER test will finish, see call from 'oltp_isql_run_worker.sh':
		select report_file from srv_get_report_name('$file_name_with_test_params', '$fbb', $winq, $test_time);
		set heading on;
	EOF
  run_isql="$fbc/isql $dbconn -i $tmpchk -q -nod -n -c 256 $dbauth"
  $run_isql 1>$tmpclg 2>$tmperr

  log_with_params_in_name=`grep -v "^$" $tmpclg | sed 's/[ \t]*$//'`

  echo Final report will be saved in:
  echo +++++++++++++++++++++++++++++++++++++++++++++++++
  echo DIR.: $tmpdir
  echo FILE: $log_with_params_in_name.txt
  echo +++++++++++++++++++++++++++++++++++++++++++++++++
  rm -f $tmpchk $tmpclg $tmperr
else
  echo +++++++++++++++++++++++++++++++++++++++++++++++++++++
  echo Final report will be saved in: $log4all
  echo +++++++++++++++++++++++++++++++++++++++++++++++++++++
fi
echo
export prf="$tmpdir/$mode"_"$HOSTNAME"
echo Main SQL script: $sql
#rm -f $tmpsql $tmplog

echo -e '#######################'
echo Launch $winq isqls. . .
echo -e '#######################'
echo

msg="$(date +'%Y.%m.%d %H:%M:%S'). Now wait for all ISQL sessions will finish their job. After this, ISQL session #1 will continue writing final report here."
echo $msg
echo $msg>>$log4all
echo>>$log4all

for i in `seq $winq`
do
    # 10.02.2015: it's wrong to start separate session via `sh`:
    # --- do NOT --- sh ./oltp_isql_run_worker.sh . . .
    ./oltp_isql_run_worker.sh ${cfg} ${sql} ${prf} ${i} ${log4all} ${file_name_with_test_params} ${fbb} ${file_name_this_host_info}&
    #./oltp_isql_run_worker.sh ${cfg} ${sql} ${prf} ${i} ${log4all} ${file_name_with_test_params} ${fbb} ${file_name_this_host_info}
done
echo Done script $0
