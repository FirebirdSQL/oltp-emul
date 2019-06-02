#!/bin/bash

function pause(){
   read -p "$*"
}

sho() {
  local msg=$1
  local log=$2
  local dts=$(date +'%d.%m.%y %H:%M:%S')
  echo $dts. $msg
  echo $dts. $msg>>$log
}

display_intention() {
  local msg=$1
  local run_cmd=$2
  local std_log=$3
  local std_err=${4:-"UNDEFINED"}
cat <<- EOF

$msg
RUNCMD: $run_cmd
STDOUT: $std_log
STDERR: $std_err
EOF
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

catch_err() {
  local tmperr=$1
  local addnfo=${2:-""}
  local quit_if_error=${3:-1}
  if [ -s $tmperr ];then
    echo
    #echo -e "$(date +'%Y.%m.%d %H:%M:%S'). Routine '$FUNCNAME': start."
    echo Error log $tmperr is NOT EMPTY!
    echo ...............................
    cat $tmperr | sed -e 's/^/    /'
    echo ...............................
    if [ ! -z "$addnfo" ]; then
        echo
        echo Additional info / advice:
        echo $addnfo
        echo
    fi
    #echo -e "$(date +'%Y.%m.%d %H:%M:%S'). Routine '$FUNCNAME': finish."
    if [ $quit_if_error -eq 1 ]; then
        echo Script is terminated.
        exit 1
    fi
  else
	echo Result: SUCCESS.
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

chk4crash() {
    # Check for indications of FB crash in ERROR log of just completed ISQL.
    # Sample of use:
    # $run_isql 1>... 2>$tmperr
    # chk4crash "$run_isql" "$tmperr" "$log4all"

    local run_isql=$1
    local tmperr=$2
    local log4all=$3

    #sho "Routine $FUNCNAME: start." $log4all

    local crash_pattern
    local crashes_cnt
    local syntax_pattern
    local syntax_err_cnt
    local msg

    crash_pattern="SQLSTATE = 08003\|SQLSTATE = 08006"
    crashes_cnt=$(grep -i -c -e "$crash_pattern" $tmperr)
    #echo tmperr=$tmperr
    #echo crashes_cnt=$crashes_cnt
    if [ $crashes_cnt -gt 0 ] ; then
        sho "Connection problem found $crashes_cnt times, pattern = $crash_pattern." $log4all
        sho "Command: $run_isql" $log4all
        grep -n -i -e "$crash_pattern" $tmperr >> $log4all
        sho "Check details in $tmperr" $log4all
        sho "Script has been terminated." $log4all
        ###################################################
        # ....................  e x i t ...................
        ###################################################
        exit 1
    fi
    
    # 20.02.2019
    # 42000 ==> -902    335544569 dsql_error     Dynamic SQL Error // token unkown et al
    # 42S22 ==> -206    335544578 dsql_field_err Column unknown
    # 42S02 ==> -204    335544580 Table unknown
    # 39000 ==> function unknown: RDB // when forget to add backslash before rdb$get/rdb$set_context
    syntax_pattern="SQLSTATE = 42000\|SQLSTATE = 42S22\|SQLSTATE = 42S02\|SQLSTATE = 39000"
    syntax_err_cnt=$(grep -i -c -e "$syntax_pattern" $tmperr)
    if [ $syntax_err_cnt -gt 0 ] ; then
        sho "Syntax / copliler errors found occured $syntax_err_cnt times, pattern = $syntax_pattern." $log4all
        sho "Check details in $tmperr" $log4all
        sho "Script has been terminated." $log4all
        ###################################################
        # ....................  e x i t ...................
        ###################################################
        exit 1
    fi
    #echo $(date +'%Y.%m.%d %H:%M:%S'). STDERR log $tmperr with size $(stat -c%s $tmperr) bytes has been checked, script is working normally.>>$log4all
    #sho "Routine $FUNCNAME: finish." $log4all
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
      set bail on;
      create database '$dbconn' page_size 8192 $dbauth;
      show version;
      set list on;
      select 
          m.mon\$database_name
         ,m.mon\$creation_date
         ,m.mon\$page_size
         ,a.mon\$attachment_id
         ,a.mon\$remote_protocol
         ,a.mon\$remote_address
      from mon\$attachments a cross join mon\$database m
      where a.mon\$attachment_id = current_connection;
      exit;
	EOF

  run_isql="$isql_name -q -i $tmpsql"
  display_intention "Attempt to CREATE database." "$run_isql" "$tmpclg" "$tmperr"
  $run_isql 1>$tmplog 2>$tmperr
  catch_err $tmperr "Ensure that FB is running. Verify that parameter 'dbnm' is VALID: $dbnm"

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
     catch_err $tmperr "Can not change DB forced writes attribute."
  fi
  if [ $create_with_sweep != -1 ]; then
     echo Changing attribute sweep interval to $create_with_sweep.
     run_fbs="$fbspref action_properties dbname $dbnm prp_sweep_interval $create_with_sweep"
     echo Command:
     echo $run_fbs
     $run_fbs 1>>$tmplog 2>>$tmperr
     catch_err $tmperr "Can not change DB sweep interval attribute."
  fi
  run_fbs="$fbspref action_db_stats dbname $dbnm sts_hdr_pages"
  $run_fbs | grep -i "$dbnm\|creation date\|attributes\|forced\|sweep" 1>>$tmplog 2>>$tmperr


  echo RESULT: database has been created SUCCESSFULLY.
  echo Content of $tmplog:
  echo ---------------------------
  cat $tmplog
  echo ---------------------------
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo

  rm -f $tmperr $tmpsql $tmplog

} # end of db_create

# ------------------- i n j e c t   a c t u a l   s e t t i n g s   f r o m    c o n f i g ---------------

inject_actual_setting()
{
  # 14.09.2018

  local fb=$1
  local a_working_mode=$2
  local a_mcode=$3
  local new_value=$4
  local allow_insert_if_eof=${5:-0}

  # inject_actual_setting $fb common enable_mon_query '$mon_unit_perf'
  #                        1     2          3                4
  
  # SQL> show table settings;
  # WORKING_MODE                    VARCHAR(20) CHARACTER SET UTF8 Nullable
  # MCODE                           (DM_NAME) VARCHAR(80) CHARACTER SET UTF8 Nullable
  #                                  COLLATE NAME_COLL
  # CONTEXT                         VARCHAR(16) Nullable default 'USER_SESSION'
  # SVALUE                          (DM_SETTING_VALUE) VARCHAR(160) CHARACTER SET UTF8 Nullable
  #                                  COLLATE NAME_COLL
  # INIT_ON                         VARCHAR(20) Nullable default 'connect'
  # DESCRIPTION                     (DM_INFO) VARCHAR(255) Nullable
  # CONSTRAINT SETTINGS_UNQ:
  #   Unique key (WORKING_MODE, MCODE) uses explicit ascending index SETTINGS_MODE_CODE
  
	cat <<- EOF
        -- Update table SETTINGS with actual value of config parameter '$a_mcode':
        -- ::: NB ::: When test is launched from several hosts this DML can fail
        -- with update conflict or "deadlock" exception, so we have to suppress it:
	EOF
	if [ $allow_insert_if_eof -eq 0 ]; then
		cat <<- EOF
		        begin
		            update settings set svalue = $new_value
		            where working_mode = upper( '$a_working_mode' ) and mcode = upper( '$a_mcode' );
		            if ( row_count = 0 ) then
		        	     exception ex_record_not_found
		EOF
                if [ $fb != 25 ]; then
		    echo -e "            using ( 'settings', 'working_mode = upper( ''$a_working_mode'' ) and mcode = upper( ''$a_mcode'' )'  );"
                else
		    echo -e "            ;"
		fi
	else
		cat <<- EOF
		        begin
		            update or insert into settings(working_mode, mcode, svalue)
		            values( upper( '$a_working_mode' ), upper( '$a_mcode' ),  $new_value)
		            matching (working_mode, mcode);
		EOF
	fi

	cat <<- EOF
        when any do
            begin
               if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ) ) then exception;
            end
        end
	EOF

} 
# end of inject_actual_setting

# ------------------------- s y n c   s e t t i n g s    w i t h     c o n f i g ------------------

sync_settings_with_conf()
{
  local fb=$1
  local tmpsql=$2
cat <<-EOF >>$tmpsql
    -- Generated auto by $shname, routine: $FUNCNAME
    set list on;
    select 'Adjust settings: start at ' || cast('now' as timestamp) as msg from rdb\$database;
    commit;
    set transaction no wait;
    set term ^;
    execute block as
    begin
EOF


inject_actual_setting $fb init working_mode upper\(\'$working_mode\'\)  >>$tmpsql
inject_actual_setting $fb common enable_mon_query \'$mon_unit_perf\'  >>$tmpsql
inject_actual_setting $fb common unit_selection_method \'$unit_selection_method\' >>$tmpsql
if echo "$working_mode" | grep -q -i "debug_01\|debug_02"; then
    # 20.08.2018: move here from oltp_main_filling.sql.
    # For DEBUG modes we turn off complex logic related to adding invoices:
    inject_actual_setting $fb common enable_reserves_when_add_invoice \'0\'  >>$tmpsql
    inject_actual_setting $fb common order_for_our_firm_percent \'0\' >>$tmpsql
fi

inject_actual_setting $fb common build_with_split_heavy_tabs \'$create_with_split_heavy_tabs\' >>$tmpsql
inject_actual_setting $fb common build_with_qd_compound_ordr \'$create_with_compound_columns_order\' >>$tmpsql
inject_actual_setting $fb common build_with_separ_qdistr_idx \'$create_with_separate_qdistr_idx\' >>$tmpsql

inject_actual_setting $fb common used_in_replication \'$used_in_replication\' >>$tmpsql
inject_actual_setting $fb common separate_workers \'$separate_workers\' >>$tmpsql
inject_actual_setting $fb common workers_count \'$winq\' >>$tmpsql
inject_actual_setting $fb common update_conflict_percent \'$update_conflict_percent\' >>$tmpsql

# We need ability to RECONNECT on build phase if this is FB 2.5 instance which does support CONNECTIONS POOL feature.
# Otherwise EDS connection (that is created fin SP sys_get_fb_arch for definition whether FB is in Classic mode or no)
# will remain alive infinitely and will keep DB file opened.
# ::: NB ::: This setting will be INSERTED if record doesnot exist - see 5th argument = 1:
#inject_actual_setting $fb common connect_str "'connect ''$host/$port:$dbnm'' user ''$usr'' password ''$pwd'';'" 1 >>$tmpsql
# 21.02.2019: changed common to init
inject_actual_setting $fb init connect_str "'connect ''$host/$port:$dbnm'' user ''$usr'' password ''$pwd'';'" 1 >>$tmpsql

# Added 23.11.2018
##################
# List of top-level units (see business_ops table) which performance statistics we want to be logged by querying  mon$ tables.
# This setting is ignored if config parameter 'enable_mon_query' is zero.
# old name: mon_traced_units
inject_actual_setting $fb common mon_unit_list \'$mon_unit_list\' >>$tmpsql
inject_actual_setting $fb common halt_test_on_errors \'$halt_test_on_errors\' >>$tmpsql
inject_actual_setting $fb common qmism_verify_bitset \'$qmism_verify_bitset\' >>$tmpsql

if [ $recalc_idx_min_interval -eq 0 ]; then
    # added 14.04.2019
    recalc_idx_min_interval=99999999
fi
inject_actual_setting $fb common recalc_idx_min_interval \'$recalc_idx_min_interval\' >>$tmpsql
##################
#  Added 21.02.2019:
inject_actual_setting $fb common warm_time \'$warm_time\' 1 >>$tmpsql

# Added 21.03.2019
inject_actual_setting $fb common test_intervals  \'$test_intervals\' 1 >>$tmpsql

cat <<- EOF >>$tmpsql
    end
    ^
    set term ;^
    commit;
    select 'Adjust settings: finish at ' || cast('now' as timestamp) as msg from rdb\$database;
EOF

} 
# end of sync_settings_with_conf()


# -------------------------------  d b _ b u i l d  -----------------------------------

db_build() {
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
  
  local prf=tmp_build_$fb
  local bld=$tmpdir/$prf.sql
  local log=$tmpdir/$prf.log
  local err=$tmpdir/$prf.err
  local tmp=$tmpdir/$prf.tmp

  local run_isql="$isql_name $dbconn $dbauth -nod -i $bld"

  if [[ $fb == 25 ]]; then
     vers_family=25
  else
     vers_family=30
  fi

  rm -f $bld $log $err $tmp


    cat <<- EOF >>$bld
	set bail on;
	-- base units:
	in "$shdir/oltp$(($vers_family))_DDL.sql";
	-- business-level units:
	in "$shdir/oltp$(($vers_family))_sp.sql";
	-- reports and other units which are the same for ant FB version:
	in "$shdir/oltp_common_sp.sql"; 
EOF

  if [ $create_with_debug_objects=1 ]; then
	# this script contains DDL for miscelan debug views and SPs,
	# it is common for both version of Firebird:
    cat <<- EOF >>$bld
	-- script for debug purposes only:
	in "$shdir/oltp_misc_debug.sql";
EOF
  fi

    cat <<- EOF >>$bld
	-- script with filling data into settings and main lookup tables:
	in "$shdir/oltp_main_filling.sql";
EOF

    #::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    #:::    B u i l d     D a t a b a s e.     I n i t i a l    p h a s e   :::
    #::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    rm -f $log
    display_intention "Build database: initial phase." "$run_isql" "$log" "$err"
    $run_isql 1>>$log 2>$err
    catch_err $err "Check SQL script at line that was specified in error message."
    rm -f $bld


    #::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    #:::   S y n c h r o n i z e    t a b l e    'S E T T I N G S'    w i t h    c o n f i g    :::
    #::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    echo
    echo "Adjusting SETTINGS table with config, step-1: generate temporary SQL script."
    sync_settings_with_conf $fb $bld

    # result: file $bld now contains SQL script with 'UPDATE SESSTINGS' statements. We have to apply it.

    run_isql="$isql_name $dbconn $dbauth -nod -i $bld"
    display_intention "Adjusting SETTINGS table with config, step-2: apply temporary script" "$run_isql" "$log" "$err"
    echo Command: $run_isql

    $run_isql 1>>$log 2>$err
    catch_err $err "Check SQL script at line that was specified in error message."

    local post_handling_out=$tmpdir/oltp_split_heavy_tabs_$(($create_with_split_heavy_tabs))_$vers_family.tmp
    # /var/tmp/oltp-emul/oltp_split_heavy_tabs_1_30.tmp
    rm -f $post_handling_out
    echo
    echo "Generate SQL script for change DDL according to current value of 'create_with_split_heavy_tabs' parameter."
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

		-- Finish building process: insert custom data to lookup tables:
		in "$shdir/oltp_data_filling.sql";
EOF
    if [ -n "$use_external_to_stop" ]; then
	cat <<- EOF >>$bld
		-- External table for quick force running attaches to stop themselves by OUTSIDE command.
		-- When all ISQL attachments need to be stopped before warm_time+test_time expired, this
		-- external table (TEXT file) should be opened in editor and single ascii-character
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

    ###############################################
    ### b u i l d i n g    D B    o b j e c t s ###
    ###############################################
    run_isql="$isql_name $dbconn $dbauth -nod -i $bld"
    display_intention "Build database: final phase." "$run_isql" "$log" "$err"
    $run_isql 1>>$log 2>$err
    catch_err $err "Could not finish build DB. Check script $bld"

    sho "Creation of database objects COMPLETED." $log4all

    rm -f $err $tmp $post_handling_out
    rm -f $bld 
    rm -f $log

    # -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

    echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
    echo
    # 02.11.18: moved pause code when wait_after_create=1 to common block in main part, see below

}
# end of db_build

#  -------------- s h o w    D B   a n d   t e s t   p a r a m s  -----------------


show_db_and_test_params() {

  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.

  conn_pool_support=$1
  log4all=$2

  local tmp_show_sql=$tmpdir/tmp_show.sql
  local tmp_show_log=$tmpdir/tmp_show.log
  local tmp_show_cfg=$tmpdir/tmp_show.cfg
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

         set heading off;
         select 'Workload level settings (see definitions in oltp_main_filling.sql):' as " " from rdb\$database;
         set heading on;
         select * from z_settings_pivot;

         set heading off;
         select 'Main test settings:' as " " from rdb\$database;
         set heading on;
         select z.setting_name, z.setting_value from z_current_test_settings z;

         set width tab_name 13;
         set width idx_name 31;
         set width idx_key 65;
         -- NORMALLY MUST BE DISABLED. ENABLE FOR DEBUG OR BENCHMARK PURPOSES.
         -- set heading off;
         -- select 'Index(es) for heavy-loaded table(s):' as " " from rdb\$database;
         -- set heading on;
         -- select * from z_qd_indices_ddl;
         
         set heading off;
         select 'Table(s) WITHOUT primary and unique constrains:' as " " from rdb\$database;
         set heading on;
         set count on;
         set width tab_name 32;
         select distinct r.rdb\$relation_name as tab_name
         from rdb\$relations r 
         left join rdb\$relation_constraints c 
         on 
             r.rdb\$relation_name =  c.rdb\$relation_name 
             and c.rdb\$constraint_type in( 'PRIMARY KEY', 'UNIQUE' )
         where 
             r.rdb\$system_flag is distinct from 1 
             and r.rdb\$relation_type = 0  
             and c.rdb\$relation_name is null
         ;
         set count off;
         set heading off;
         select lpad('',32,'=') as " " from rdb\$database;
         set heading on;

	EOF

  if [ $conn_pool_support -eq 1 ]; then
    # ::: NB ::: 05.11.2018
    # PSQL function sys_get_fb_arch uses ES/EDS which keeps infinitely connection in implementation for FB 2.5
    # If current implementation actually supports connection pool then we have to clear it, otherwise idle
    # connection will use metadata and we will not be able to drop existing PK from some tables.
    cat <<- "EOF" >>$tmp_show_sql
    set bail on;
    set count on;
    set echo on;
    create or alter view v_pool_info as
    select 
       cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_SIZE') as int) as pool_size,
       cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_IDLE_COUNT') as int) as pool_idle,
       cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_ACTIVE_COUNT') as int) as pool_active,
       cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_LIFETIME') as int) as pool_lifetime
    from rdb$database;
    commit;
    select 'Before clear connections pool' as msg, v.* from v_pool_info v;
    ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;
    select 'After clear connections pool' as msg, v.* from v_pool_info v;
    set echo off;
    set count off;
    set bail off;
EOF
  fi

  run_isql="$isql_name $dbconn $dbauth -i $tmp_show_sql -pag 99999999"
  display_intention "Check DB parameters, workload map and current test settings." "$run_isql" "$tmp_show_log" "$tmp_show_err"
  $run_isql 1>$tmp_show_log 2>$tmp_show_err

  cat $tmp_show_err>>$log4all
  catch_err $tmp_show_err "Errors detected while running script $tmp_show_sql. Check STDOUT and STDERR logs."

  # Display database and main test parameters + add them to main log:
  echo ...............................
  cat $tmp_show_log | sed -e 's/^/    /'
  echo ...............................
  cat $tmp_show_log | sed -e 's/^/    /'>>$log4all

  rm -f $tmp_show_sql $tmp_show_err $tmp_show_log

  # 18.09.2018
  #####################################################################################
  ###   s h o w     p a r a m s     f r o m      o l t p N N _ c o n f i g . w i n  ###
  #####################################################################################
  
  if [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]; then
    fb_home_dir="$(dirname "$fbc")"

    echo "Changed parameters of $fb_home_dir/firebird.conf:" >>$tmp_show_log
    sed -e 's/^[ \t]*//' $fb_home_dir/firebird.conf | grep "^[^#;]" | sort > $tmp_show_cfg
    cat $tmp_show_cfg | sed -e 's/^/    /' >> $tmp_show_log

    # /opt/firebird/bin/fbsvcmgr localhost/3333:service_mgr user sysdba password masterkey info_get_env
    # Server root: /opt/firebird/

    if grep -q -i "DefaultDbCachePages" $tmp_show_cfg; then
        if ! grep -q -i "FileSystemCacheThreshold" $tmp_show_cfg ; then
            cat <<- EOF >>$tmp_show_log

### A C H T U N G ### YOU MUST DEFINE PARAMETER 'FileSystemCacheThreshold'

It is strongly recommended to add parameter 'FileSystemCacheThreshold' into your Firebird config file.
Please add it and assign value NOT LESS than number of pages that is specified for 'DefaultDbCachePages'.
Script is now terminated.
EOF
            cat $tmp_show_log
            cat $tmp_show_log>>$log4all
            rm -f $tmp_show_log $tmp_show_cfg
            exit 1
        fi
    fi

    if [ -z "$FIREBIRD_TMP" ]; then
      echo Variable \'FIREBIRD_TMP\' undefined, GTT data will be stored in the \'/tmp\'. >>$tmp_show_log
    else
      echo Value of \'FIREBIRD_TMP\': $FIREBIRD_TMP, GTT data will be stored in this folder. >>$tmp_show_log
    fi
  else
      echo Test uses REMOTE Firebird instance, content of firebird.conf is unavaliable.>>$tmp_show_log
  fi
  #^-- [[ $dbconn =~ .*localhost[/:]{1}.* || $dbconn =~ .*127.0.0.1[/:]{1}.* ]]
  cat $tmp_show_log
  cat $tmp_show_log>>$log4all
  rm -f $tmp_show_log $tmp_show_cfg
  echo

  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.

}
# end of show_db_and_test_params

# -------------------------------  c h e c k _ s t o p t e s t -----------------------------------

check_stoptest() {
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
  # check that file 'stoptest.txt' is EMPTY
  local pfx=tmp_check_stoptest
  local tmpchk=$tmpdir/$pfx.sql
  local tmpclg=$tmpdir/$pfx.log
  local tmperr=$tmpdir/$pfx.err
  local run_isql="$isql_name $dbconn -nod -n -i $tmpchk $dbauth"

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

  rm -f $tmp_show_sql $tmp_show_log $tmp_show_cfg $tmp_show_err

  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo
}
# end of check_stoptest

# -------------------------------  u p d _ i n i t _ d o c s  ------------------------------------

upd_init_docs() {
  echo
  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
  echo Check is the database needs to be filled up with necessary number of documents

  local pfx=tmp_get_init_docs
  local tmpchk=$tmpdir/$pfx.sql
  local tmpclg=$tmpdir/$pfx.log
  local tmperr=$tmpdir/$pfx.err
  local run_isql="$isql_name $dbconn -i $tmpchk -nod -n $dbauth"
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
# end of upd_init_docs

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
  local run_isql="$isql_name $dbconn -i $tmpsql -q -nod -n $dbauth"
  
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

} 
# end of: prepare_before_adding_init_data

# --------------------------  g e n _ w o r k i n g _ s q l  -------------------------

gen_working_sql() {
 echo
 echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: start.
 local mode=$1 # 'init_pop' xor 'run_test'
 local sql=$2
 local lim=$3 
 local nau
 [[ $4=1 ]] && nau="no auto undo"

 # echo $(( sleep_min + RANDOM % (sleep_max - sleep_min) ))
 
 # should detailed info for each iteration be added in log ? 
 # (actual only for mode=run_test; if "1" then add select * from perf_log)
 local nfo=${5:-0}

 local sleep_min=${6:-0}
 local sleep_max=${7:-0} 
 local sleep_udf=$8
 local sleep_mul=$9

 local unit_selection_method=random

 local verb=50
 #[[ $mode = "init_pop" ]] && verb=10 || verb=50

 if [[ $mode = "init_pop" && sleep_max -gt 0 ]]; then
     sleep_min=0
     sleep_max=0
     echo -e "Mode='$mode': disable sleep* values while add required initial count of documents."
 fi

 rm -f $sql
cat <<- EOF
     Input arguments: 
     1) mode:			$mode
     2) sql:			$sql
     3) number-of-EB:		$lim
     4) Tx-undo-clause:         $nau
     5) show-detailed-info:	$nfo
EOF
 if  [ "$mode" = "run_test" ] ; then
cat <<- EOF
     6) sleep_min:              $sleep_min
     7) sleep_max:              $sleep_max
     8) sleep_udf:              $sleep_udf
     9) sleep_mul:              $sleep_mul
EOF
  fi

#echo set tran option: $nau
cat <<- EOF >>$sql
	-- ### WARNING: DO NOT EDIT ###
	-- Generated auto by $shname, routine: $FUNCNAME
	-- SQL script generation started at $(date +'%d.%m.%Y %H:%M:%S')
EOF
 if  [ "$mode" = "init_pop" ] ; then
	cat <<- EOF >>$sql
		-- mode='$mode': get data from mon\$database for verifying settings of database
		-- NB-1: FW must be (temply) set to OFF
		-- NB-2: cache buffers temply set to pretty big value
		set list on; 
		select * from mon\$database; 
		set list off;
	EOF
 fi

 #############################################################################################################
 ###   g e n e r a t e    . s q l    f o r    p e r f o r m i n g      $lim     t r a n s a c t i o n s    ###
 #############################################################################################################

 for (( i=1; i<=$lim; i++ ))
 do

    #[[ $((  $i % $verb )) = 0 ]] && echo Done generating iter $i of total $lim
    if [ $((  $i % $verb )) = 0 ] ; then
	sho "Generating SQL script. Iter $i of total $lim" $log4all
    fi

    if [ $i = 1 ]; then
	cat <<-EOF >>$sql
		commit;
	EOF
    else
      if [ $sleep_max -gt 0 ] ; then
	    cat <<-EOF >>$sql
		-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
		-- Config parameter 'sleep_max' = $sleep_max. We have to make PAUSES between transactions.
		-- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
		set list on;
		EOF

	     if [ ! -z "$sleep_udf" ] ; then
		cat <<- EOF >>$sql
		set transaction read only read committed;
		set term ^;
		execute block returns( " " varchar(128) ) as
		  declare v_lf char(1);
		  declare taken_pause_in_seconds int;
		  declare SECONDS_IN_MINUTE smallint = 60;
		begin
		    v_lf = ascii_char(10);
		    " " = v_lf || cast('now' as timestamp);
		    if ( rdb\$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER') = 1 and rdb\$get_context('USER_SESSION','ENABLE_MON_QUERY') = 2 ) then
		        begin
		            -- $mon_query_interval: see config parameter 'mon_query_interval'
		            -- ($warm_time + $test_time) * SECONDS_IN_MINUTE / 20: see config parameters 'warm_time' and 'test_time'
		            taken_pause_in_seconds = minvalue( $mon_query_interval, maxvalue(1, $warm_time + $test_time) * SECONDS_IN_MINUTE / 20 ); 
		            " " = " " || '. Dedicated session N1 for query to mon$ tables. Point BEFORE constant pause ' || taken_pause_in_seconds || ' s.';
		            -- 15.12.2018 18:23:23.333. Dedicated session N1 for query to mon$ tables. Point BEFORE constant pause NNN s.
		        end
		    else
		        begin
		            taken_pause_in_seconds = cast( $sleep_min + rand() * ($sleep_max - $sleep_min) as int);
		            " " = " " || '. Point BEFORE pause from $sleep_min to $sleep_max seconds. Choosen value: ' || taken_pause_in_seconds || '. Use UDF ''$sleep_udf''.';
		        end
		    rdb\$set_context('USER_TRANSACTION', 'TAKE_PAUSE', taken_pause_in_seconds );
		    suspend;
		end^
		set term ^;

		-- ############################################################
		-- ###    p a u s e      u s i n g      U D F     c a l l   ###
		-- ############################################################
		set term ^;
		execute block returns(actual_delay_in_seconds numeric(12,3) ) as
		    declare t timestamp;
		    declare d int;
		    declare c int;
		begin
		    t = 'now';
		    c = cast( rdb\$get_context('USER_TRANSACTION', 'TAKE_PAUSE') as int);
		    --- c = c  * $sleep_mul; -- 14.11.2018: UDF can accept arg as number of PART of seconds, e.g. MILLISECONDS.
		    --- c = $sleep_udf( c );
		    while (c > 0) do
		    begin
		        -- +=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=
		        -- +=- C A L L     U D F   F O R    S L E E P  +=-
		        -- +=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=-+=
		        d = $sleep_udf( $sleep_mul ); -- here we wait only 1 second: we have to BREAK from this loop ASAP when test is prematurely cancelled.
		
		        execute procedure sp_check_to_stop_work; -- check whether we should terminate this loop because of test cancellation
		
		        c = c - 1;
		        when any do
		        begin
		            rdb\$set_context('USER_SESSION','SELECTED_UNIT', 'TEST_WAS_CANCELLED');
		            exception;
		        end
		    end
		    --- actual_delay_in_seconds = c * 1.000 / $sleep_mul;
		    actual_delay_in_seconds = datediff(millisecond from t to cast('now' as timestamp)) * 1.000 / 1000;
		    suspend;
		    rdb\$set_context('USER_TRANSACTION', 'TAKE_PAUSE', null );
		end^
		set term ;^
		EOF

	     else # Config parameter 'sleep_udf' is UNDEFINED (commented)

	        [[ $sleep_max -gt $sleep_min ]] && random_delay=$(( sleep_min + RANDOM % (sleep_max-sleep_mmin) )) || random_delay=$sleep_min
		cat <<-EOF >>$sql
		    set transaction read write read committed lock timeout 1; -- need for sp_pause: it DOES write operation into fixed table 'tpause'.
		    set term ^;
		    execute block returns( " " varchar(128) ) as
			declare v_lf char(1);
		     begin
			v_lf = ascii_char(10);
			" " = v_lf || cast('now' as timestamp) || '. Point BEFORE pause from $sleep_min to $sleep_max seconds. Choosen value: $random_delay. Use OS shell call.';
			suspend;
		    end^
		    set term ;^
	            -- #####################################################################################
	            -- ###    p a u s e      u s i n g      s h e l l    's l e e p'    c o m m a n d    ###
	            -- #####################################################################################
                    shell sleep $random_delay;
		    --select * from sp_pause( $random_delay, '$usr', '$pwd' );
		EOF
	     fi # 'sleep_udf' defined ? --> yes / no

	    cat <<-EOF >>$sql
		set term ^;
		execute block returns( " " varchar(128) ) as
		    declare v_lf char(1);
		begin
		v_lf = ascii_char(10);
		    " " = v_lf || cast('now' as timestamp) || '. Point AFTER delay finish.';
		    suspend;
		end^
		set term ;^
		commit; ------------------------ [ 2a ]
		set list off;

		EOF
      else 
            # ......................... config parameter sleep_max = 0
		cat <<-EOF >>$sql
		-- Pause between transactions is DISABLED. HEAVY WORKLOAD CAN OCCUR BECAUSE OF THIS.
		-- For enabling them assign positive value to 'sleep_max' parameter in $cfg.
		-- Pauses will be done either via 'shell sleep NN' invocation or using UDF call.
		-- The latter requires existense of appropriate binary .so and SQL script with UDF
		-- declaration.
		-- Configuration parameter 'sleep_ddl' must be uncommented and have to point on this SQL script.

		EOF

            if [ $mon_unit_perf -eq 2 ]; then
		cat <<-EOF >>$sql
			-- 16.12.2018. Config parameter 'mon_unit_perf' = 2.
			-- Statistics from mon$ tables is gathered in the session N1.
			-- Delay must be done here if current session has number = 1.

		EOF
                # if [ $test_time -ge 10 ]; then
		# 22.04.2019:
                if [ $test_time -ge 0 ]; then
			cat <<-EOF >>$sql
			-- Because of depening on session number, it can be implemented only using UDF call:
			-- we can not make SHELL call from PSQL "if/else" code branches.
				EOF
                    if [ ! -z "$sleep_udf" ] ; then
			cat <<-EOF >>$sql
			-- .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:
			-- :.:    d e l a y    b e t w n.     m o n $    q u e r i e s,   O N L Y   i n    s e s s i o n   N 1  .:.
			-- .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:
			set transaction read only read committed;
			set heading off;
			set term ^;
			execute block returns( " " varchar(128) ) as
			begin
			    if ( rdb\$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER') = 1 and rdb\$get_context('USER_SESSION','ENABLE_MON_QUERY') = 2 ) then
			    begin
			        " " = cast('now' as timestamp) || ' SID=1. This sesion is dedicated for gathering data from mon\$ tables. Take pause: use UDF $sleep_udf()...';
			        suspend;
			    end
			end
			^

			execute block returns( " " varchar(128) ) as
			    declare c int;
			    declare d int;
			    declare t timestamp;
			    declare SECONDS_IN_MINUTE smallint = 60;
			    declare session1_delay_before_mon_query numeric(12,3);
			begin
			    if ( rdb\$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER') = 1 and rdb\$get_context('USER_SESSION','ENABLE_MON_QUERY') = 2 ) then
			    begin
			        -- CONSTANT DELAY:
			        -- $mon_query_interval: see config parameter 'mon_query_interval'
			        -- maxvalue(1, $warm_time + $test_time) * SECONDS_IN_MINUTE / 20: see config parameters 'warm_time' and 'test_time'
			        c = minvalue( $mon_query_interval, maxvalue(1, $warm_time + $test_time) * SECONDS_IN_MINUTE / 20 );
			        t = 'now';
			        while (c > 0) do
			        begin
			            -- #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
			            -- #-#   C A L L     U D F   F O R    S L E E P   #-#
			            -- #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
			            d = $sleep_udf( $sleep_mul ); -- here we wait only 1 second: we have to BREAK from this loop ASAP when test is prematurely cancelled.
			
			            execute procedure sp_check_to_stop_work; -- check whether we should terminate this loop because of test cancellation
			
			            c = c - 1;
			        when any do
			            begin
			                rdb\$set_context('USER_SESSION','SELECTED_UNIT', 'TEST_WAS_CANCELLED');
			                exception;
			            end
			        end
			        session1_delay_before_mon_query = datediff(millisecond from t to cast('now' as timestamp)) * 1.000 / 1000;
			        " " = cast('now' as timestamp) || ' SID=1. Completed pause between gathering data from mon$ tables, s: ' || session1_delay_before_mon_query;
			        suspend;
			    end
			end
			^
			set term ;^
			commit; ------------------------ [ 2b ]
			set list off;
			set heading on;
			EOF
                    else # sleep_udf is UNDEFINED
			cat <<-EOF >>$sql
			-- * WARNING * mon_unit_perf = 2: config parameter 'sleep_ddl' must be UNCOMMENTED 
			-- and has to point on existing SQL script that defined UDF declaration for delays.
			EOF
                    fi # $sleep_udf is defined ? --> yes / no
                else # test_time LESS than 10 minutes --> too short time for pauses
			cat <<-EOF >>$sql
			-- PAUSE IS SKIPPED: TEST LASTS TOO SHORTLY: $test_time minutes.
			-- Increase value of config parameter 'test_time' at least to 10.
			EOF
                fi # $test_time -ge 10 / -lt 10
            fi # $mon_unit_perf -eq 2

      fi # config parameter sleep_max -gt 0 --> yes / no
	cat <<- EOF >>$sql
		
			-- .........................................................
			--     s t a r t     i t e r    $i    o f    $lim
			-- .........................................................
			
	EOF

    fi # iter i = 1 or all subsequent --> yes / no
    
    [[ $unit_selection_method = "random" ]] && eb_title="RANDOM" || eb_title="PREDICTABLE"
    cat <<- EOF >>$sql
        -- ################################################################
        -- START TRANSACTION WHICH WILL BE USED FOR BUSINESS UNIT EXECUTION
        -- ################################################################
		
		set transaction no wait $nau; -- check oltp_config.NN for optional setting NO AUTO UNDO here:
		set heading off;
		-- 18.01.2019. Avoid from querying rdb\$database: this can affect on performance
		-- in case of extremely high workload when number of attachments is ~1000 or more.
		-- Sample of output:
		-- Current value of 'stop'-flag: g_stop_test = 0, test_time: 2019-03-21 09:05:31.0390 ... 2019-03-21 12:05:31.0390
		set term ^;
		execute block returns(" " varchar(255)) as
		    declare v_dts_beg timestamp;
		    declare v_dts_end timestamp;
		begin
		    select test_time_dts_beg, test_time_dts_end
		    from sp_get_test_time_dts -- this SP uses session-level context variables since its 2nd call and until reconnect
		    into v_dts_beg, v_dts_end;
		    " " = 'Current value of ''stop''-flag: g_stop_test = ' || gen_id(g_stop_test, 0)
		          || ', test_time: '
		          || coalesce( v_dts_beg, '<?>' )
		          || ' ... '
		          || coalesce( v_dts_end, '<?>' )
		    ;
		    suspend;
		end^
		set term ;^
		set heading on;
		
		-- #########################################################
		-- TOP-LEVEL UNIT (BUSINESS OPERATION) CHOISE,  $eb_title
		-- #########################################################
		
		set term ^;
		execute block as
		  declare v_unit dm_name;
		begin
		    -- 21.02.2019 00:05
		    -- execute procedure sp_check_to_stop_work; -- check whether we should terminate this loop because of test cancellation
	EOF
	
    if  [ "$mode" = "init_pop" ] ; then
        # When database is filled up by initial data one need only to:
        # 1. Add NEW documents or
        # 2. Change state of existing docs
        # -- but we do NOT have to run any cancel operations:
        cat <<- EOF >>$sql
			  -- 12.08.2018 .................... m o d e    =   I N I T _ P O P  .....................
			  -- Parameter 'expected_workers'=$expected_workers, from config: typical value for count of launching ISQLs;
			  -- do NOT use: mod current_transaction, $winq for storing in WORKER_SEQ_NUM
			  -- We evaluate here random value for WORKER_SEQ in the scope = 0...=$expected_workers in order to make
			  -- database be with the same distribution after finish initial adding of  all needed documents.
			  -- Initial value of WORKER_SEQUENTIAL_NUMBER will be restored after execution from value
			  -- of WORKER_SEQ_NUMB_4RESTORE context variable.
			  rdb\$set_context( 'USER_SESSION',
			                    'WORKER_SEQUENTIAL_NUMBER',
			                    cast( 0.5 + rand() * $expected_workers as int ) 
			                  );

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
 
      if  [ "$mode" = "run_test" ] ; then
        cat <<-EOF >>$sql
			  if ( NOT exists( select * from sp_stoptest ) ) then
			    begin
		EOF
			      if [ $separate_workers -eq 1 ] ; then
                                 [[ $fb = "25" ]] && sel_worker_expr="(select worker_id from fn_other_rand_worker)" || sel_worker_expr="fn_other_rand_worker()"
        cat <<-EOF >>$sql
			        if ( rand() * 100 <= $update_conflict_percent ) then
			        begin
			            -- 17.09.2018: temply change current ISQL window sequential number for increasing update-conflicts
			            rdb\$set_context( 'USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER', $sel_worker_expr );
			        end
		EOF
			      fi

	# 16.12.2018
	cat <<-EOF >>$sql
		        v_unit = null;
		        if ( rdb\$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER') = 1 ) then
		        begin
		              if ( rdb\$get_context('USER_SESSION','ENABLE_MON_QUERY') is null ) then
		              begin
		                     rdb\$set_context( 'USER_SESSION', 'ENABLE_MON_QUERY',
		                                      ( select s.svalue from settings s where working_mode = upper('common') and mcode = upper('enable_mon_query') )
		                                    );
		              end
		              if ( rdb\$get_context('USER_SESSION','ENABLE_MON_QUERY') = 2 ) then
		              begin
		                  -- When config parameter 'mon_unit_perf' = 2 then we gather mon$ data by SINGLE attachment rather than by every running session.
		                  -- It was decided to gather mon$ info by ISQL worker N1 and estimate affect on overall performance, see discuss with dimitr.
		                  -- For this purpose we call the same SP every time:
		                  v_unit = 'SRV_FILL_MON_CACHE_MEMORY' ;
		              end
		        end
		        if ( v_unit is null ) then
		        begin
                      -- +++++++++++++++++++++++++++++++++++++++++++++++++++
                      -- +++  c h o o s e    b u s i n e s s    u n i t  +++
                      -- +++++++++++++++++++++++++++++++++++++++++++++++++++
	EOF

	if  [ "$unit_selection_method" = "random" ] ; then
        cat <<-EOF >>$sql
			          select p.unit
			          from srv_random_unit_choice(
			              ''
			             ,''
			             ,''
			             ,''
			          ) p
			          into v_unit;
		EOF
	else
        cat <<-EOF >>$sql
			          select p.unit
			          from srv_predictable_unit_choice p
			          into v_unit;
		EOF
	fi
	
        cat <<-EOF >>$sql
			          end -- ( v_unit is null )
			      end -- NOT exists( select * from sp_stoptest )
			  else -- "select * from sp_stoptest" DOES return something --> we have to CANCEL test
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

    if  [ "$mode" = "run_test" ] ; then
      if [ $mon_unit_perf = 1 ]; then
        cat <<- "EOF" >>$sql
			-- ############################################################
			-- ###    G A T H E R    M O N.    D A T A    B E F O R E   ###
			-- ############################################################
			set term ^;
			execute block as
			    declare v_dummy bigint;
			begin
			    rdb$set_context('USER_SESSION','MON_GATHER_0_BEG', 
					      datediff(millisecond from timestamp '01.01.2015' to cast('now' as timestamp) )
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
					      datediff(millisecond from timestamp '01.01.2015' to cast('now' as timestamp) )
					    );
			end
			^
			set term ;^
			set list on;
			select 
			     rdb$get_context('USER_SESSION','MON_GATHER_0_BEG') as mon_gather_0_beg
			    ,rdb$get_context('USER_SESSION','MON_GATHER_0_END') as mon_gather_0_end
			from rdb$database;
			set list off;
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

		-- ##############################################################
		-- ###   S H O W    S E L E C T E D     U N I T     N A M E   ###
		-- ##############################################################

		-- ensure that just before call application unit
		-- GTT tmp\$perf_log is really EMPTY:
		delete from tmp\$perf_log;

		set heading off;
		-- 16.01.2019. Avoid from querying rdb\$database: this can affect on performance
		-- in case of extremely high workload (when number of attachments is ~1000 or more).
		set term ^;
		execute block returns(" " varchar(150)) as
		begin
		    " " = lpad('',50,'+') || ' Action # $i of $lim ' || rpad('',50,'+');
		    suspend;
		end
		^
		set term ;^
		set heading on;

		set width dts 24;
		set width trn 14;
		set width att 14;
		set width unit 31;
		set width elapsed_ms 10;
		set width msg 16;
		set width add_info 30;
		set width mon_logging_info 20;

		set list off;
		
		-- 16.01.2019. Avoid from querying rdb\$database: this can affect on performance
		-- in case of extremely high workload (when number of attachments is ~1000 or more).
		set term ^;
		execute block returns( dts varchar(24), trn varchar(20), att varchar(20), unit varchar(50), worker_seq int, msg varchar(16), add_info varchar(50) ) as
		begin
		    dts = left( cast(current_timestamp as varchar(255)), 24); -- NB, 14.04.2019: FB 4.0 adds time_zone info
		    trn = 'tra_'||current_transaction;
		    att = 'att_'||current_connection;
		    unit = rdb\$get_context('USER_SESSION','SELECTED_UNIT'); 
		    worker_seq = cast( rdb\$get_context('USER_SESSION','WORKER_SEQUENTIAL_NUMBER' ) as int ); 
		    msg = 'start';
		    select iif( current_timestamp < p.dts_beg, 'WARM_TIME', 'TEST_TIME' ) || ', minute N '
		           || cast( iif( current_timestamp < p.dts_beg,
		                         60*$warm_time - datediff( second from current_timestamp to p.dts_beg ),
		                         datediff( second from p.dts_beg to current_timestamp )
		                       ) / 60
		                       +1
		                    as varchar(10)
		                  )
		    from (
		        select p.test_time_dts_beg as dts_beg from sp_get_test_time_dts p
		    ) p
		    into add_info;
		    suspend;
		end
		^
		set term ^;

		-- *** RESULT: ***
		--     +++++++++++++++++++++++++++++++++++++++++++++++++++++++ Action # mmm of NNN +++++++++++++++++++++++++++++++++++++++++++++++++++++++
		--     DTS                     TRN            ATT            UNIT                              WORKER_SEQ MSG              ADD_INFO
		--     ======================= ============== ============== =============================== ============ ================ =========================
		--     2019-01-16 12:09:12.802 tra_663        att_61         sp_supplier_order                         30 start            TEST_TIME, minute N 12345

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
		    rdb\$set_context('USER_SESSION', 'GDS_RESULT', null);
		    rdb\$set_context('USER_SESSION', 'TOTAL_OPS_SUCCESS_INFO', null);
		    -- save value of current_transaction because we make COMMIT
		    -- after gathering mon$ tables when oltp_config.NN parameter
		    -- mon_unit_perf=1
		    rdb\$set_context('USER_SESSION', 'APP_TRANSACTION', current_transaction);

		    -- save in ctx var timestamp of START app unit:
		    rdb\$set_context('USER_SESSION','BAT_PHOTO_UNIT_DTS', cast('now' as timestamp)); -- timestamp of START business unit

		    if ( rdb\$get_context('USER_SESSION','SELECTED_UNIT')
		       is distinct from
		       'TEST_WAS_CANCELLED'
		    ) then
		      begin
			        v_stt='select count(*) from ' || rdb\$get_context('USER_SESSION','SELECTED_UNIT');
			        -- ++++++++++++++++++++++++++++++++++++++++++++++++++++
                    -- +++  l a u n c h     b u s i n e s s    u n i t  +++
                    -- ++++++++++++++++++++++++++++++++++++++++++++++++++++
			        execute statement (v_stt) into result;
			        rdb\$set_context('USER_SESSION', 'RUN_RESULT',  'OK, '|| result ||' rows');
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
			                || cast('now' as timestamp) -- concatenate start timestamp with timestamp of FINISH
			   );
		  when any do
		    begin
		      rdb\$set_context('USER_SESSION', 'GDS_RESULT', gdscode);

	EOF

    #if echo $mode | grep -i "^init_pop$" > /dev/null ; then
    if  [ "$mode" = "init_pop" ] ; then
      cat <<- EOF >>$sql
		      v_stt = 'alter sequence g_init_pop restart with ' || v_old_docs_num;
		      execute statement (v_stt);
		EOF
    fi

    cat <<- EOF >>$sql
		      rdb\$set_context('USER_SESSION', 'RUN_RESULT', 'error, gds=' || gdscode );
		      -- ##############################
		      -- r a i s e    e x c e p t i o n
		      -- ##############################
		      exception;
		    end
		  end
		end
		^
		set term ;^
		SET STAT OFF;
	EOF

    #if echo $mode | grep -i "^run_test$" > /dev/null ; then # run_test
    if  [ "$mode" = "run_test" ] ; then
      if [ $mon_unit_perf = 1 ]; then
		cat <<- EOF >>$sql
			-- ##########################################################
			-- ###    G A T H E R    M O N.    D A T A    A F T E R   ###
			-- ##########################################################
			set term ^;
			execute block as
			    declare v_dummy bigint;
			begin
			    rdb\$set_context('USER_SESSION','MON_GATHER_1_BEG', 
			            datediff(millisecond from timestamp '01.01.2015' to cast('now' as timestamp) )
			    );
			    -- Gather mon$ tables BEFORE run app unit.
			    -- Add second row to GTT tmp\$mon_log - statistics on 'per unit' basis.
			    -- Note: for FB 3.0 - also add first rowset into table tmp\$mon_log_table_stats.
			    select count(*)
			    from srv_fill_tmp_mon (
			            rdb\$get_context('USER_SESSION','MON_ROWSET')    -- :a_rowset
			           ,1                                                -- :a_ignore_system_tables
			           ,rdb\$get_context('USER_SESSION','SELECTED_UNIT') -- :a_unit
			           ,coalesce(                                        -- :a_info ==> will be writted into mon_log.add_info, see SP: SRV_FILL_MON
			                 rdb\$get_context('USER_SESSION','ADD_INFO') -- aux info, set in APP units only!
			                ,rdb\$get_context('USER_SESSION','RUN_RESULT')
			               )
			           ,rdb\$get_context('USER_SESSION', 'GDS_RESULT')   -- :a_gdscode
			    )
			    into v_dummy;
			    rdb\$set_context('USER_SESSION','MON_GATHER_1_END', 
			            datediff(millisecond from timestamp '01.01.2015' to cast('now' as timestamp) )
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
			set list on;
			select 
			     rdb\$get_context('USER_SESSION','MON_GATHER_1_BEG') as mon_gather_1_beg
			    ,rdb\$get_context('USER_SESSION','MON_GATHER_1_END') as mon_gather_1_end
			from rdb\$database;
			set list off;
			-- 22.04.2019:
			-- do NOT otherwise tmp\$perf_log become empty -- commit; --  ##### C O M M I T  #####  after gathering mon$data
			-- set transaction no wait $nau;
		EOF
      fi # mon_unit_perf = 1

		cat <<- EOF >>$sql
			-- ##############################################################
			-- ###   S H O W    R E S U L T S    O F   E X E C U T I O N  ###
			-- ##############################################################
		EOF

		cat <<- EOF >>$sql
			set list on;
            select
                v.worker_sequential_number
                ,v.test_ends_at
                ,v.last_operation_gds_code
                ,v.estimated_perf_since_test_beg
		EOF
		#	Sample:
		# ESTIMATED_PERF_SINCE_TEST_BEG          10808     31 2019-03-25 12:16:18
		#	::: NOTE ::: Do not use float numbers with decimal spearator:
		#	-414.50: syntax error: invalid arithmetic operator (error token is ".50")
		
		if [ $mon_unit_perf -eq 1 ]; then
			cat <<- EOF >>$sql
                 -- this variable will be defined in SP srv_fill_mon:
                ,v.mon_logging_info
                ,v.mon_gathering_time_ms
                ,v.traced_units
			EOF
		elif [ $mon_unit_perf -eq 2 ]; then
			cat <<- EOF >>$sql
				,'MON$ statistics is queried from session N1, see config parameter ''mon_unit_perf''' as mon_logging_info
			EOF
		else
			cat <<- EOF >>$sql
				,'MON$ querying DISABLED, see config ''mon_unit_perf''' as mon_logging_info
			EOF
		fi
		# $mon_unit_perf = 1 or 2

		cat <<- EOF >>$sql
               ,v.workload_type
               ,v.halt_test_on_errors
            from v_est_perf_for_last_minute v;
            set list off;
		EOF
    fi # mode = 'run_test'

	cat <<- "EOF" >>$sql

		-- Output results of application unit run:
		set width dts 24;
		set width trn 14;
		set width att 14;
		set width unit 31;
		set width elapsed_ms 10;
		set width msg 20;
		set width add_info 60; -- 16.01.2019: increase width for add_info
		-- 16.01.2019. Avoid from querying rdb\$database: this can affect on performance
		-- in case of extremely high workload (when number of attachments is ~1000 or more).
		set term ^;
		execute block returns ( dts varchar(24), unit varchar(50), elapsed_ms int, msg varchar(80), add_info varchar(80) ) as
		begin
 		    dts = left( cast(current_timestamp as varchar(255)), 24); -- NB, 14.04.2019: FB 4.0 adds time_zone info

		    -- trn = 'tra_' || rdb$get_context('USER_SESSION','APP_TRANSACTION');
		    unit = rdb$get_context('USER_SESSION','SELECTED_UNIT');
		    elapsed_ms = datediff( millisecond 
		                           from cast(left(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'),24) as timestamp)
		                           to cast(right(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'),24) as timestamp)
		                         );
		    msg = rdb$get_context('USER_SESSION', 'RUN_RESULT');
		    add_info = rdb$get_context('USER_SESSION','ADD_INFO');
		    suspend;
		end
		^
		set term ;^
		-- *** RESULT: *** (after business operation finish)
		-- DTS          TRN            UNIT                            ELAPSED_MS MSG                  ADD_INFO
		-- ============ ============== =============================== ========== ==================== ========================================
		-- 22:09:21.823 tra_663        sp_supplier_order                     9013 OK, 5 rows           doc=211938601: created Ok
		--                                                                        error, gds=335544517

	EOF

    #if echo $mode | grep -i "^init_pop$" > /dev/null ; then
    if  [ "$mode" = "init_pop" ] ; then
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
		set list on;
		set term ^;
		execute block returns( msg_final_gather_perf_log dm_info ) as
		begin
		    if ( rdb$get_context('USER_SESSION','SELECTED_UNIT')
		         is NOT distinct from
		         'TEST_WAS_CANCELLED'
		      ) then
		    begin
		       -- ############################################################################################
		       -- ###   c a n c e l     t h i s     S Q L    s c r i p t,    r e t u r n     t o     s h e l l
		       -- ############################################################################################
		       exception ex_test_cancellation ( select result from sys_stamp_exception('ex_test_cancellation') );
		    end
		    -- REMOVE data from context vars, they will not be used more
		    -- in this iteration:
		    rdb$set_context('USER_SESSION','SELECTED_UNIT', null);
		    rdb$set_context('USER_SESSION','RUN_RESULT',    null);
		    rdb$set_context('USER_SESSION','GDS_RESULT',    null);
		    rdb$set_context('USER_SESSION','ADD_INFO', null);
		    rdb$set_context('USER_SESSION','APP_TRANSACTION', null);
		    rdb$set_context('USER_SESSION','TOTAL_OPS_SUCCESS_INFO', null);
		    rdb$set_context('USER_SESSION','MON_GATHER_0_BEG', null);
		    rdb$set_context('USER_SESSION','MON_GATHER_0_END', null);
		    rdb$set_context('USER_SESSION','MON_GATHER_1_BEG', null);
		    rdb$set_context('USER_SESSION','MON_GATHER_1_END', null);
		    -- 17.09.2018. Restore initial value of current ISQL window sequential number
		    -- 'WORKER_SEQUENTIAL_NUMBER' by its copy that was stored in 'WORKER_SEQ_NUMB_4RESTORE':
		    rdb$set_context('USER_SESSION','WORKER_SEQUENTIAL_NUMBER', rdb$get_context( 'USER_SESSION', 'WORKER_SEQ_NUMB_4RESTORE' ) );
		end
		^
		set term ;^
		set list off;
		set bail off;
	EOF

    if  [ "$mode" = "run_test" ] ; then
      if [ $nfo = 1 ]; then
		cat <<- EOF >>$sql
			-- Begin block to output DETAILED results of iteration.
			-- To disable this output change "detailed_info" setting to 0
			-- in test configuration file "$cfg"
			set list off;
			set heading off;
			select 'Current Tx actions:' as msg from rdb\$database;
			set heading on;
			set list on;
			set count on;
			select 
				-- g.id, -- useless, always is NULL
				g.unit, g.exc_unit, g.info, g.fb_gdscode,g.trn_id,
			       g.elapsed_ms, g.dts_beg, g.dts_end
			from tmp\$perf_log g ------------------------ GTT on commit DELETE rows
			order by dts_beg;
			set count off;
			set list off;
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
		commit; ------------------ [ 1 ]
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
    else
		cat <<- EOF >>$sql
		
			-- .........................................................
			--     e n d     o f     i t e r    $i    o f    $lim
			-- .........................................................
			
		EOF
    fi


 done 

  echo -- SQL script generation finished at $(date +'%d.%m.%Y %H:%M:%S') >> $sql


 # i=1..$lim
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
  local log4all=$4

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
  local tmpchk=$tmpdir/sql/$prf.sql
  local tmpclg=$tmpdir/sql/$prf.log
  local tmperr=$tmpdir/sql/$prf.err
  while :
  do

    if [ $(( k % $srv_frq )) -eq 0  ]; then
      rm -f $tmpchk $tmpclg

		cat <<- EOF >>$tmpchk
			set list on; 
			set heading on;
			commit;
			set transaction no wait;
			select count(*) as srv_make_invnt_saldo_result from srv_make_invnt_saldo;
			select * from srv_make_invnt_saldo;
			commit;
			set transaction no wait;
			select count(*) as srv_make_money_saldo_result from srv_make_money_saldo;
			select * from srv_make_money_saldo;
			commit;
			set transaction no wait;
			select count(*) as srv_recalc_idx_stat_result from srv_recalc_idx_stat;
			select * from srv_recalc_idx_stat;
			commit;
		EOF

      echo -ne "$(date +'%Y.%m.%d %H:%M:%S'), start service SPs... "
      # --------------- perform service: srv_make*_total, recalc index statistics -------------
      cat $tmpchk>>$tmplog
      run_isql="$isql_name $dbconn -i $tmpchk -c $init_buff -n $dbauth"

      $run_isql 1>$tmplog 2>$tmperr
      chk4crash "$run_isql" "$tmperr" "$log4all"

      echo -e "$(date +'%Y.%m.%d %H:%M:%S'), finish service SPs."
    fi

    echo -ne "$(date +'%Y.%m.%d %H:%M:%S'), packet $k start... "

    # Common application unit: create several documents
    # using .sql which was made in func gen_working_sql
    ###################################################
    run_isql="$isql_name $dbconn -i $tmpsql -c $init_buff -n $dbauth"

    $run_isql 1>$tmplog 2>$tmperr
    chk4crash "$run_isql" "$tmperr" "$log4all"

    cancel_test=0

    # current unit: add_init_docs
    #############################
    if grep -i -q "ex_test_cancel" $tmplog $tmperr ; then
          cancel_test=1
          echo Found sign of TEST CANCELLATION. Job terminated.
          exit 1
    fi

                                                                                                    
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
    run_isql="$isql_name $dbconn -pag 0 -i $tmpchk -n $dbauth"

    $run_isql 1>$tmpclg 2>$tmperr
    chk4crash "$run_isql" "$tmperr" "$log4all"


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
  rm -f $tmpsql $tmplog $tmpchk $tmpclg $tmperr

  echo $(date +'%Y.%m.%d %H:%M:%S'). Routine $FUNCNAME: finish.
  echo
} # end of add_init_docs()

# --------------  l a u n c h _ p r e p a r i n g  -----------

launch_preparing() {
  echo
  echo Routine $FUNCNAME: start.

  local tmpsql=$1
  local sleep_min=${2:-0}
  local sleep_max=${3:-0}
  local sleep_udf=$4
  local sleep_mul=$5
  
  echo sleep_min=$sleep_min, sleep_max=$sleep_max, sleep_udf=$sleep_udf, sleep_mul=$sleep_mul
  
  # Make comparison of TIMESTAMPS: this batch vs $tmpsql.
  # If this batch is OLDER that $tmpsql than we can SKIP recreating $tmpsql
  local skipGenSQL=0

  echo -e "Check: should script '$tmpsql' be recreated due to its outdated timestamp or incompleteness."

  if [ -f $tmpsql ];then
    if [ $shname -ot $tmpsql ];then
      echo -e "Current scenario: '$shname' - is OLDER than '$tmpsql'"
      if [ $cfg -ot $tmpsql ]; then
        echo -e "Test config '$cfg' is OLDER than '$tmpsql'"
        skipGenSQL=1
      else
        echo -e "Test config '$cfg' is NEWER than '$tmpsql'"
      fi
    else
      echo -e "Current scenario: '$shname' is NEWER than '$tmpsql'"
    fi
    if [ $skipGenSQL -eq 1 ]; then
        if ! grep -q "FINISH packet" $tmpsql ; then
            echo Creation of SQL script was INTERRUPTED, we have to recreate it again.
            skipGenSQL=0    
        fi
    fi
    [[ $skipGenSQL = 0 ]] && echo -e "We must RECREATE '$tmpsql'." \
                          || echo -e "We can use EXISTING '$tmpsql'."
  else
    echo -e "Script '$tmpsql' does NOT exist, now we create it."
  fi

  if [ $skipGenSQL = 0 ]; then
    # Generating script to be used by working isqls.
    # ##########################################################################
    if [ 1 -eq 1 ]; then
        gen_working_sql run_test $tmpsql 300 $no_auto_undo $detailed_info $sleep_min $sleep_max $sleep_udf $sleep_mul
        #                  1        2      3         4            5            6           7        8          9
    else
        gen_working_sql run_test $tmpsql  19  $no_auto_undo $detailed_info $sleep_min $sleep_max $sleep_udf $sleep_mul
        #                  1        2      3         4            5            6           7        8          9
        echo
        echo DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG
        echo Routine: $FUNCNAME
        echo RETURN INITIAL NUMBER OF EXEC BLOCKS TO 300. IT WAS CHANGED FOR DEBUG PURPOSES. PRESS ANY KEY...
        echo
        pause Press any key...
        exit
    fi
    #                  1        2     3       4             5             6
    # ##########################################################################
  fi


  local prf=tmp_add_aux_rows
  local tmpchk=$tmpdir/$prf.sql
  local tmpclg=$tmpdir/$prf.log
  local tmperr=$tmpdir/$prf.err
  local run_isql="$isql_name $dbconn -i $tmpchk $dbauth"
  
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
			    -- this view is one-to-one projection to the table perf_agg which is used in report "Performance for every MINUTE":
				delete from v_perf_agg;
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

		set list on;
		select
		       g.dts_measure_beg
		      ,g.dts_measure_end
		      ,g.add_info
		from
		(
		  select 
		     p.unit, 
		     p.exc_info as add_info, -- name of this .sh that did insert this record
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
	    echo -e "show sequ g_stop_test; alter sequence g_stop_test restart with -999999999; commit; show sequ g_stop_test;" | $isql_name $dbconn $dbauth -q -n -nod
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
export winq=$2

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
echo -e "Config file '$cfg' parsing results:"
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

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# INITIATE REPORT FILE "oltpNN.report.txt"
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
log4all=$tmpdir/oltp$1.report.txt
rm -f $log4all
##########################################

# stackoverflow.com/questions/1921279/how-to-get-a-variable-value-if-variable-name-is-stored-as-string

# Use command:
# sed -e 's/^[ \t]*//' ./oltp25_config.nix  | grep "^[^#;]" | sort | awk '{print $1}'
# - in order to get all uncommented parameters from config
vars=(
    create_with_compound_columns_order
    create_with_debug_objects
    create_with_fw
    create_with_separate_qdistr_idx
    create_with_split_heavy_tabs
    create_with_sweep
    dbnm
    detailed_info
    expected_workers
    fbc
    file_name_this_host_info
    file_name_with_test_params
    gather_hardware_info
    halt_test_on_errors
    host
    init_buff
    init_docs
    is_embed
    make_html
    max_cps
    mon_unit_list
    mon_unit_perf
    no_auto_undo
    port
    pwd
    qmism_verify_bitset
    recalc_idx_min_interval
    remove_isql_logs
    run_db_statistics
    run_db_validation
    separate_workers
    sleep_max
    test_time
    test_intervals
    tmpdir
    unit_selection_method
    update_conflict_percent
    used_in_replication
    usr
    wait_after_create
    wait_for_copy
    wait_if_not_exists
    warm_time
    working_mode
)

for i in ${vars[@]}; do
  #echo -e param: $i, value: \|${!i}\|
  [[ -z ${!i} ]] && msg_novar $i $cfg && exit 1
done

if [ "$clu" != "" ]; then
    # Name of ISQL on Ubuntu/Debian when FB is installed from OS repository
    # 'isql-fb' etc:
    echo Config contains custom name of command-line utility for interact with Firebird.
    echo Parameter: \'clu\', value: \|$clu\|
else
    echo Using standard name of command-line utility for interact with Firebird: 'isql'
    clu=isql
fi
isql_name=$fbc/$clu

dbdir=$(dirname "${dbnm}")

mkdir -p $tmpdir/sql 2>/dev/null
mkdir -p $dbdir/sql 2>/dev/null

if [ ! -d "$dbdir" ]; then
    echo Directory "$dbdir" does not exist and could not be created.
    echo
    exit 1
fi

if [ ! -d "$tmpdir" ]; then
    echo Directory "$tmpdir" does not exist and could not be created..
    echo
    exit 1
fi

echo
if [ $sleep_max -gt 0 ]; then
    if [ -z "$sleep_min" ]; then
        echo Parameter \'sleep_min\' was not defined in config and is assigned to 1.
        sleep_min=1
    fi
    if [[ $sleep_min -gt $sleep_max  || $sleep_min -lt 0 ]]; then
        echo
        echo -e "Incorrect value of 'sleep_min' parameter: it must be in the scope 0...$sleep_max"
        echo
        exit 1
    fi
fi

if [ $mon_unit_perf -eq 2 ]; then
   if [ -z "$sleep_ddl" ]; then
         echo -e "CONFIGURATION ISSUE. Parameter 'mon_unit_perf' = 2 requires that parameter 'sleep_ddl' must be UNCOMMENTED."
         echo -e "It must point to existing SQL script that declares UDF for delays from .so file avaliable to engine."
         pause Press any key to FINISH this script. . .
         exit 1
   fi

   if [ -z "$mon_query_interval" ]; then
         echo -e "CONFIGURATION ISSUE. Parameter 'mon_unit_perf' = 2 requires that parameter 'mon_query_interval' must be UNCOMMENTED."
         echo -e "Its value must be greater than zero and means duration of delay between receiving monitoring snapshots, in seconds."
         pause Press any key to FINISH this script. . .
         exit 1
   fi
fi

if [[ $host = "localhost" || $host = "127.0.0.1" ]]; then
    echo Test will run on localhost
else
    if [ $gather_hardware_info -eq 1 ]; then
	###############################################################################################
	###  C H A N G E    C O N F I G   'G A T H E R _ H A R D W A R E _ I N F O'   T O   Z E R O ###
	###############################################################################################
	cat <<-EOF
		CONFIGURATION ISSUE.
		Parameter 'gather_hardware_info' = 1 requires parameter 'host' having value 'localhost' or '127.0.0.1'.
		Hardware and OS info will not be gathered because probably you are going to run test on REMOTE server.
		Current value of 'host' parameter is: $host
		
		Open config file "$cfg" in editor and change parameter 'gather_hardware_info' to 0.
		
	EOF
	gather_hardware_info=0
        pause Press any key to FINISH this script. . .
        # NOTE: config file is re-read in worker.sh, so better to exit here than duplicate chek again in another place.
        exit 1
    fi
fi

# NOTE, 16.12.2018: we have to use UDF even when sleep_max=0 but mon_unit_perf = 2:
if [ -s "$sleep_ddl" ]; then
        # arr=($(grep -i -e "declare[[:space:]]*external[[:space:]]*function" "$sleep_ddl")) -- wrong if file $sleep_ddl contasins 
        # trailing newlines (^M ) when was copied from Windows host as binary rather than plain text:
        arr=($( sed 's/\r//' "$sleep_ddl" | grep -i -e "declare[[:space:]]*external[[:space:]]*function" ))

        ###################################################################################
        ###   p a r s i n g     n a m e     o f     U D F      f o r      p a u s e s   ###
        ###################################################################################
        sleep_udf=${arr[3]}

        if [ -z "$sleep_udf" ]; then
            echo
            echo SQL script "$sleep_ddl" must contain line with UDF declaration that starts with:
            echo
            echo declare external function \<UDF_name\>
            echo
            echo NOTE: all these four words must be written in one line.
            exit
        else
            echo
            echo Parsed UDF for pauses, its name: \'$sleep_udf\'
            echo $sleep_udf.
        fi
else
        echo
        echo -e "SQL script with UDF declaration: '$sleep_ddl' - either empty or does not exist."
        echo
        #exit 1
fi

# fi << old pos for  $sleep_max -gt 0


vars=($clu fbsvcmgr)
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

# Server version: LI-V2.5.9.27119 Firebird 2.5 HQbird
#    a      b            c            d     e     f        
while read a b c d
do
  fbb=$c
  fbo=$(echo -n $fbb | cut -c1-2)
done<$tmplog
# output server version: fbb=|LI-V2.5.9.27119|

rm -f $tmplog $tmperr

tmpsql=$tmpdir/sql/tmp_init_data_pop.sql
tmplog=$tmpdir/sql/tmp_init_data_pop.log
tmpchk=$tmpdir/sql/tmp_init_data_chk.sql
tmpclg=$tmpdir/sql/tmp_init_data_chk.log
tmperr=$tmpdir/sql/tmp_init_data_chk.err
tmpadj=$tmpdir/sql/tmp_adjust_ddl_with_cfg.sql
tmpa4r=$tmpdir/sql/tmp_adjust_for_replication.sql

export dbauth=
export dbconn=
if [ $is_embed = 1 ]; then
  dbauth=
  dbconn=$dbnm
else
  dbauth="-user $usr -pas $pwd"
  dbconn=$host/$port:$dbnm
fi


#	cat <<-EOF >$tmpdir/gdb-foo.txt
#		thread apply all bt
#		shell $fbc/fb_lock_print -a -d $dbnm 1>$tmpdir/gdb-firebird-lock-print.txt 2>&1
#		quit
#		yes
#	EOF
#


rm -f $tmpchk $tmpclg $tmpadj

rndname=$RANDOM

cat <<-EOF >>$tmpchk
    set heading off;
    set list on;
    set bail on;
    -- This sequence serves as 'stop-flag' for every ISQL attachment:
    alter sequence g_stop_test restart with 0;
    commit;
    -- Now we have to:
    -- 0. Check that all database objects already exist:
    -- 1. Ensure that Firebird engine *can* add rows to GTT, i.e. it *has* access to $FIREBIRD_TMP directory on server;
    -- 2. Database is not in read-only mode (updating 'settings' table with actual values of some config params).
    -- 3. Update some parameters in the database to be match for their actual values from config file
    --   see invocations of 'inject_actual_setting' subroutine

    select iif( exists( select * from semaphores where task='all_build_ok' ),
		        'all_dbo_exists',
		        'some_dbo_absent'
	    ) as "build_result="
    from rdb\$database;

    -- Check that database is not in read_only mode.
    -- Also we check here that Firebird account has enough rights to WRITE into GTT files.
    -- These files are created in the folder that is defined by 1st existent variable:
    -- 1) FIREBIRD_TMP;
    -- 2.1) (Windows): TEMP, TMP, USERPROFILE, Windows directory - see Windows API function GetTempPath:
    --      https://docs.microsoft.com/en-us/windows/desktop/api/fileapi/nf-fileapi-gettemppatha
    -- 2.2) (POSIX) /tmp
    -- When Firebird process has no rights to that directory, test will fail with message:
    -- #####################################################
    -- Statement failed, SQLSTATE = 08001
    -- I/O error during "open O_CREAT" operation for file ""
    -- -Error while trying to create file
    -- -No such file or directory
    -- #####################################################
    -- See also:
    -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1176238&msg=18172438
    recreate GLOBAL TEMPORARY table tmp\$$rndname(id int, s varchar(36) unique using index tmp_s_unq_$rndname );
    commit;
    set count on;
    insert into tmp\$$rndname(id, s) select rand()*1000, uuid_to_char(gen_uuid()) from rdb\$types;
    set list on;
    select min(id) as id_min, max(id) as id_max, count(*) as cnt from tmp\$$rndname;
    commit;
    drop table tmp\$$rndname;
    -- At this point one may be sure that FB really has enough rights to create files for GTT data.
    commit;
    quit;

    -- # 22.12.2018 removed from here, will be done in separate .sql after DB repbuild!
    -- #set bail off;
    -- #set heading off;
    -- #set list off;
    -- #select current_timestamp || ' - point before clear connections pool' as msg from rdb\$database;
    -- #set echo on;
    -- #ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;
    -- #set echo off;
    -- #select current_timestamp || ' - point after clear connections pool' as msg from rdb\$database;
EOF

run_isql="$isql_name $dbconn -i $tmpchk -q -nod -c 256 $dbauth"
display_intention "Check whether DB is avaliable and has all needed objects." "$run_isql" "$tmpclg" "$tmperr"
$run_isql 1>$tmpclg 2>$tmperr

if grep -q -i "Permission denied" $tmperr; then
	cat <<- EOF
		#######################################################################
		DBMS account ('firebird') does no have sufficient rights to open file that
		is specified by config parameter 'dbnm' (read/write access is required):
		$dbnm
		#######################################################################
		
		Content of STDERR file '$tmperr':
	EOF
	echo
	cat $tmperr
	echo
	pause Press any key to FINISH this script. . .
	exit 1
fi

# We must stop this .sh only in case when database has unsupported ODS or offline etc.
# We must CONTINUE if $tmpchk finished with error like 'table semaphores not found'.

rebuild_was_invoked=0

#if  grep -q -i "SQLSTATE = 08001" $tmperr  grep -q -i "Error while trying to open" $tmperr; then

if grep -q -i "Error while trying to open" $tmperr; then
 
    if [[ $wait_if_not_exists = 1 && $can_stop = 1 ]]; then
	cat <<- EOF
		###########################################################
		Press ENTER for attempt to CREATE database, Ctrl-C to QUIT.
		###########################################################
	EOF
        pause
    fi


    #........................  c r e a t e    d a t a b a s e  ..............
    db_create

    # ....................... b u i l d    d b    o b j e c t s .............
    db_build

    rebuild_was_invoked=1
else

    badmsg=$(grep -i "Is a directory\|unavailable database\|not a valid\|unsupported on-disk\|read-only\|shutdown" $tmperr | wc -l)

    [[ $badmsg -gt 0 ]] && msg_no_build_result $tmpchk $tmperr || echo "Database exists and online"

    # database DOES exist and ONLINE, but we have to ensure that ALL objects was successfully created in it.
    ########################################################################################################
    db_build_finished_ok=0
    if [ -s $tmperr ];then
        echo Script that verifies finish of DB building process is NOT EMPTY.
        echo Name of script: $tmpclg
        echo Name of errlog: $tmperr
        cat $tmperr
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

        #else # $db_build_finished_ok = 1
        # moved below, common block
        rebuild_was_invoked=1

    fi # $db_build_finished_ok = 0 or 1

fi # grep "Error while trying to open" $tmperr ==> true or false

# ********************
# *** COMMON BLOCK ***
# ********************


# /////////////////////////// check whether connections pool is supported /////////////////
cat <<-EOF >$tmpchk
    set bail off;
    set heading off;
    set list off;
    select current_timestamp || ' - point before clear connections pool' as msg from rdb\$database;
    set echo on;
    ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;
    set echo off;
    select current_timestamp || ' - point after clear connections pool' as msg from rdb\$database;
EOF

# for STANDARD build of Firebird (which does NOT support connection pool)
# last statement will issue:
# ===
#   Statement failed, SQLSTATE = 42000
#   Dynamic SQL Error
#   -SQL error code = -104
#   -Token unknown - line ..., column ...
#   -CONNECTIONS
# ==

run_isql="$isql_name $dbconn -i $tmpchk -q -nod -c 256 $dbauth"
display_intention "Check whether this FB has support connections pool." "$run_isql" "$tmpclg" "$tmperr"
$run_isql 1>$tmpclg 2>$tmperr

conn_pool_support=0
if grep -q -i "SQLSTATE = 42000" $tmperr && grep -q -i "Token unknown" $tmperr ; then
    echo This build does not support CONNECTIONS POOL.
    tail -15 $tmperr
else
    conn_pool_support=1
    catch_err $tmperr "At least one error occured when querying connections pool data at '$host/$port:$dbnm'" 0
    tail -15 $tmpclg | grep -i "connections pool"
    echo This build DOES support connections pool.
fi
# //////////////////////////////////////////////////////////////////////////////////////////


# ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
# :::   S y n c h r o n i z e    t a b l e    'S E T T I N G S'    w i t h    c o n f i g    :::
# ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

rm -f $tmpchk
echo Synchronize SETTINGS table with current values from config
sync_settings_with_conf $fb $tmpchk

cat <<-"EOF" >>$tmpchk
    -- 02.01.2019: delete all records in mon_cache_memory table
    -- that could remain there after interrupted previous run:
    set list on;
    select 'ZAP table mon_cache_memory, start at ' || cast('now' as timestamp) as msg from rdb$database;
    commit;
    set transaction NO wait;
    set count on;
    delete from mon_cache_memory;
    set count off;
    commit;
    select 'ZAP table mon_cache_memory, finish at ' || cast('now' as timestamp) as msg from rdb$database;
    set list off;
EOF

run_isql="$isql_name $dbconn -q -nod -n -c 256 $dbauth -i $tmpchk"

$run_isql 1>$tmpclg 2>$tmperr
catch_err $tmperr "Table SETTINGS was not synchronized with current config values."
grep -i "msg " $tmpclg

# ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
# :::   A d j u s t     D D L    f o r     's e p a r a t e _ w o r k e r s'     s e t t i n g   + :::
# :::   R E C R E A T E     n e e d e d   n u m b e r     o f    'PERF_LOG_SPLIT_nn'   t a b l e s :::
# ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

# Use file: $shdir/oltp_adjust_DDL.sql
# 1. GENERATE temporary script "$tmpadj" which will contain dynamically generated DDL statements
#    for PERF_SPLIT_nn tables
run_isql="$isql_name $dbconn -q -nod -n -c 256 $dbauth -i $shdir/oltp_adjust_DDL.sql"
$run_isql 1>$tmpadj 2>$tmperr
catch_err $tmperr "Could not generate SQL script for change DDL of some DB objects."

# 2. APPLY temporary script "$tmpadj" which contains dynamic DDL.
run_isql="$isql_name $dbconn -q -nod -c 256 $dbauth -i $tmpadj"
display_intention "Update DDL to current value of 'separate_workers' config parameter." "$run_isql" "$tmpclg" "$tmperr"
$run_isql 1>$tmpclg 2>$tmperr
catch_err $tmperr "Could not apply generated SQL script. DDL of some DB objects remains unchanged. Check script $tmpadj"

# ------------------------------
# Adjust DDL of tables with current value of 'used_in_replication' parameter:
# add primary keys for QDistr, QStorned and other tables if used_in_replication= 1,
# otherwise DROP existing primary keys for these tables (if they exist).
# -------------------------------
#echo -e "Update DDL to current value of 'used_in_replication' config parameter."

# 1. GENERATE temporary script "$tmpa4r" which will contain dynamically generated DDL statements
#    for creating or dropping indices, according to current value of 'used_in_replication' config parameter
# ::: NB ::: 01.11.2018
# RECONNECT is needed on 3.0.4 SuperServer between alter table add <field> not null and alter table add <PK_CONSTRAINT>.
# Script oltp_replication_DDL.sql has query to table SETTINGS with WHERE-expr: mcode='CONNECT_STR' for obtaining
# proper connection string to currently used database (see letters to dimitr et al, 01.11.2018, box pz@ibase.ru).

run_isql="$isql_name $dbconn -q -nod -c 256 $dbauth -i $shdir/oltp_replication_DDL.sql"
display_intention "Update DDL to 'used_in_replication' parameter: step-1: generate temporary DDL." "$run_isql" "$tmpa4r" "$tmperr"
$run_isql 1>$tmpa4r 2>$tmperr
catch_err $tmperr "Could not generate SQL for change indices according to 'used_in_replication' config parameter."

# 4debug4debug4debug
# echo -e "SHOW DATABASE;">>$tmpa4r

run_isql="$isql_name $dbconn -q -nod -c 256 $dbauth -i $tmpa4r"
display_intention "Update DDL to 'used_in_replication' parameter, step-2: apply generated DDL." "$run_isql" "$tmpclg" "$tmperr"
$run_isql 1>$tmpclg 2>$tmperr
catch_err $tmperr "Could not update DDL according to current value of 'used_in_replication' parameter. Check STDERR log $tmperr"


# Multiplier for input argument to sleep UDF for getting delays in SECONDS.
# Value will be adjusted after test call of sleep UDF that must present in the script "$sleep_ddl" from config:
sleep_mul=1

# 12.01.2019
# NOTE: we have to declare UDF and evaluate sleep_mul even when sleep_max = 0 - it can be required
# to use UDF for delays between every calls of SP 'SRV_FILL_MON_CACHE_MEMORY' when  mon_unit_perf = 2
# (this will be done in dedicated isql session N1)
must_decl_udf=0

if [ -s "$sleep_ddl" ]; then

    if [ $mon_unit_perf -eq 2 ]; then
        must_decl_udf=1
    else
        if [ $sleep_max -gt 0 ]; then
            must_decl_udf=1
        fi
    fi

    if [ $must_decl_udf -eq 1 ]; then
        #:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
        #:::   d e c l a r e      e x t e r n a l     S l e e p  U D F   :::
        #:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
        run_isql="$isql_name $dbconn -q -nod -c 256 $dbauth -i $sleep_ddl"
        display_intention "Attempt to apply SQL script '$sleep_ddl' that defines UDF for pauses in execution." "$run_isql" "$tmpclg" "$tmperr"
        $run_isql 1>$tmpclg 2>$tmperr
        catch_err $tmperr "Could not create/update UDF for sleep. Check file $sleep_ddl"
        if grep -q "multiplier_for_sleep_arg" $tmpclg; then
            #:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
            #:::   a d j u s t     m u l t i p l i e r    t o    i n p u t     f o r   g e t    d e l a y   i n   s e c o n d s  :::
            #:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
            sleep_mul=$( grep -i "multiplier_for_sleep_arg" $tmpclg | awk '{print $2}' )
        fi
    else
        sho "NOTE: config parameter 'sleep_ddl' is forcedly assigned to EMPTY string because of other parameters" $log4all
        sho "that allow SKIP usage of UDF now: mon_unit_perf=$mon_unit_perf, sleep_max=$sleep_max" $log4all
        unset sleep_ddl
    fi
else
    sho "Script defined by parameter 'sleep_ddl' does not exist. Sessions will work without UDF usage." $log4all
fi

rm -f $tmpclg $tmperr $tmpchk

# ....................... check that file 'stoptest.txt' is EMPTY .....................
if [ -n "$use_external_to_stop" ]; then
  check_stoptest
else
  sho "Parameter 'use_external_to_stop' is undefined (default). External text file will not be checked for premature stop." $log4all
fi

if [ $rebuild_was_invoked -eq 1 ]; then
    # 02.11.18: moved here from db_build
    if [[ $wait_after_create = 1 && $can_stop = 1 ]]; then
      echo Database has been created SUCCESSFULLY and is ready for initial documents filling.
      echo -e "######################################"
      echo
      echo Change config setting \'wait_after_create\' to 0 in order to remove this pause.
      echo
      echo Press ENTER to go on. . .
      pause
    fi
fi


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
    sho "Start initial data population until total number of documents will be not less than $(( existing_docs +  init_docs ))." $log4all
    echo Please wait. . .
    echo

    # 1. set linger to 15 (only for 3.0; greatly reduce time of connect!),
    # 2. temply change FW to OFF with saving old value of it.
    # 3. alter sequence g_init_pop restart with 0;
    ####################
    prepare_before_adding_init_data
    ####################

    # 3. generate temp .sql script for initial filling:
    #init_sql_packets_count=3 # number of transactions in .sql (reduce re-connects)
    init_sql_packets_count=50

    ######################################################################
    gen_working_sql init_pop $tmpsql $init_sql_packets_count $no_auto_undo
    #                  1        2                  3               4
    ######################################################################

    # 4. Run just generated SQL: add new documents until their count less than $init_docs parameter:
    srv_frq=20 # frequency of service procedures call (srv_make_invnt_saldo, srv_make_money_saldo, srv_recalc_idx_stat)

    # 1. If config parameter $use_external_to_stop IS defined, output its value with note about ability to stop
    #    all working ISQL sessions by adding single character + LF into this file.
    # 2. If $use_external_to_stop is UNDEFINED, create temp shell script in $tmpdir with name '1stoptest.tmp.sh'
    #    and display message about ability to stop test by running this temp script.
    ####################
    gen_temp_sh_for_stop
    ####################

    ###############################################
    add_init_docs $tmpsql $tmplog $srv_frq $log4all
    ###############################################

    if [[ $is_embed == 0 ]]; then
        fbspref="$fbc/fbsvcmgr $host/$port:service_mgr user $usr password $pwd "
    else
        fbspref="$fbc/fbsvcmgr service_mgr "
    fi
    run_fbs="$fbspref action_properties dbname $dbnm prp_write_mode prp_wm_$create_with_fw"
    msg="Adjusting FW to config parameter 'create_with_fw' value: $create_with_fw"
    sho "$msg" $log4all
    display_intention "$msg" "$run_fbs" "$tmpclg" "$tmperr"
    $run_fbs 1>$tmpclg 2>$tmperr
    catch_err $tmperr "Check whether database exists, is online and has read_write access."

    sho "Check attributes line from DB header info:" $log4all
    run_fbs="$fbspref action_db_stats dbname $dbnm sts_hdr_pages"
    $run_fbs | grep -i attributes 1>>$tmpclg 2>&1
    cat $tmpclg
    cat $tmpclg>>$log4all
    rm -f $tmpclg

    sho "FINISH initial data population." $log4all
    if [[ $wait_for_copy = 1 && $can_stop = 1 ]]; then
        echo "### NOTE ###"
        echo
        echo It\'s a good time to make COPY of test database in order 
        echo to start all following runs from the same state.
        echo
        sho "Press ENTER to begin WARM-UP and TEST mode. . ." $log4all
        pause
    fi

fi # $init_docs -gt 0


# ...................... s h o w    D B   a n d    t e s t    p a r a m s  ............

# 08.11.2018: SP sys_get_db_arch that shows current FB instance architercute (CS/SC/SS) uses
# ES/EDS in order to detect whether FB runs as Classic server or no. This ES/EDS can remain
# after its finish 'infinite attachment',i.e. it will exist even after parent connection make
# detach from DB (quit) -- and this will be so if current build is experimental 2.5 with support
# of  CONNECTIONS POOL.
# We have to run "ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;" statement in tha case.

show_db_and_test_params $conn_pool_support $log4all

##############################################################
#               w o r k i n g     p h a s e
##############################################################

export mode=oltp$1

# winq = number of opening isqls
export winq=$2

if [ "$unit_selection_method" == "random" ];then
  export sql=$tmpdir/sql/tmp_random_run.sql
else
  export sql=$tmpdir/sql/tmp_predict_run.sql
fi


# 1. Generating main SQL script to be used by working isqls.
# 2. Add into perf_log table record for checking work to be stopped on timeout.
#####################


if [ $sleep_max -gt 0 ]; then
    launch_preparing $sql $sleep_min $sleep_max $sleep_udf $sleep_mul
else
    # before 16.12.18: launch_preparing $sql
    launch_preparing $sql $sleep_min $sleep_max $sleep_udf $sleep_mul
fi
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
  run_isql="$isql_name $dbconn -i $tmpchk -q -nod -n -c 256 $dbauth"
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
#export prf="$tmpdir/$mode"_"$HOSTNAME"
export prf="$tmpdir/$mode"_"${HOSTNAME// /}"
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

if [ 0 -eq 1 ]; then
    echo "./oltp_isql_run_worker.sh $cfg $sql $prf 1 $log4all $file_name_with_test_params $fbb ${conn_pool_support} $file_name_this_host_info AMP"
    pause ... :::DEBUG::: stop_before_launch_single_isql...

    bash ./oltp_isql_run_worker.sh $cfg $sql $prf 1 $log4all $file_name_with_test_params $fbb ${conn_pool_support} $file_name_this_host_info

    echo +++DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+++
    exit
fi

#echo ./oltp_isql_run_worker.sh ${cfg} ${sql} ${prf} ${i} ${log4all} ${file_name_with_test_params} ${fbb} ${file_name_this_host_info}
#echo 1: ${cfg} 
#echo 2: ${sql} 
#echo 3: ${prf} 
#echo 4: ${i} 
#echo 5: ${log4all} 
#echo 6: ${file_name_with_test_params} 
#echo 7: ${fbb} 
#echo 8: ${file_name_this_host_info}
#exit

for i in `seq $winq`
do
    # 10.02.2015: it's wrong to start separate session via `sh`:
    # --- do NOT --- sh ./oltp_isql_run_worker.sh . . .

    #echo ./oltp_isql_run_worker.sh ${cfg} ${sql} ${prf} ${i} ${log4all} ${file_name_with_test_params} ${fbb} ${conn_pool_support} ${file_name_this_host_info}

    bash ./oltp_isql_run_worker.sh ${cfg} ${sql} ${prf} ${i} ${log4all} ${file_name_with_test_params} ${fbb} ${conn_pool_support} ${file_name_this_host_info}&
    #                            1      2      3     4      5                   6                   7                8                  9
done

echo Done script $0

