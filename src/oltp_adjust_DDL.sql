-- ###################################
-- Begin of script oltp_adjust_DDL.sql
-- ###################################

-- ::: NB ::: This script is COMMON for both FB 2.5 and 3.0 and should be called
-- from batch scenario after oltp_split_heavy_tabs_0.sql or oltp_split_heavy_tabs_1.sql
-- NOTE: do not use ISQL with '-n' switch when run this script!
-- Otherwise dependencies will not be cleared properly.

set bail on;
set list on;

select 'set list on; select ''oltp_adjust_DDL.sql start at '' || current_timestamp as msg from rdb$database;' as " "
from rdb$database
union all
select 'set echo off; commit; set transaction no wait;' as " "
from rdb$database
;
commit;

set transaction no wait;

create or alter view v_perf_estimated as 
-- Created in oltp_adjust_DDL.sql, will be recreated just now again.
-- Dummy view for ability to DROP table perf_estimated and create it again
-- (much faster than delete all rows from it before every new test launch)
select
     1 as id
    ,1 as minute_since_test_start
    ,1 as success_count
    ,1 as worker_id
    ,1 as pool_active
    ,1 as pool_idle
    ,1 as att_id
    ,current_timestamp as dts
from rdb$database;
commit;

-- %%%%%%%%%%%%%%%%%%%%%  D R O P  + C R E A T E     T A B L E    P E R F _ E S T I M A T E D   %%%%%%%%%%%%%%%
-- 27.11.2020, need for FB 4.x+: added pool_active and pool_idle columns
-- (num of active and idle connections in external conn. pool if enabled)
recreate table perf_estimated(
    id dm_idb not null -- generated by default as identity constraint pk_perf_estimated primary key using index pk_perf_estimated
    ,minute_since_test_start int
    ,success_count numeric(12,2)
    ,worker_id dm_ids
    ,pool_active int
    ,pool_idle int
    ,att_id int default current_connection
    ,dts timestamp default 'now'
    ,constraint pk_perf_estimated primary key(id)
);
commit;

create or alter view v_perf_estimated as 
-- Recreated in oltp_adjust_DDL.sql before every new test launch.
-- It must be the only DB object that depends on table 'perf_estimated'.
-- Must be updated only via sp_add_perf_log:
select * from perf_estimated;
commit;

-- %%%%%%%%%%%%%%%%%%%%%  D R O P  + C R E A T E     T A B L E    P E R F _ E D S  %%%%%%%%%%%%%%%%%%%%%

-- 03.12.2020. NB: this DDL must always be the same as in oltp30_DDL.sql
create or alter view v_perf_eds as
select 
     1 as id
    ,current_timestamp as dts
    ,1 as att
    ,1 as trn
    ,1 as sid -- ex. 'who'
    ,'' as app
    ,'' as evt
    ,1 as pool_active
    ,1 as pool_idle
from rdb$database;
commit;


-- DO NOT delete this table (though actually it is not used).
-- Otherwise triggers on CONNECT/DICSONNECT will not be compiled when run oltp_adjust_eds_calls.sql 
-- (this script removes comments from code which does insert into v_perf_eds when use_es = 2).
-- Used only in FB 3.x+
recreate table perf_eds (
    id int
    ,dts timestamp default 'now'
    ,att int default current_connection
    ,trn int default current_transaction
    ,sid smallint -- always = cast( right( current_user, position('_', reverse(current_user)) - 1 ) as smallint ) // ex. 'who'
    ,app varchar(80) -- name of client application (only file, w/o full path)
    -- Event associated with connection:
    -- when record is added by CONNECT trigger:
    --     'N' = new (non-EDS) connection established  (system var. RESETTING =  false)
    --     'A' = session reset: connection was idle and become active now (system var. RESETTING =  true)
    -- when record is added by DISCONNECT trigger:
    --     'I' = session reset: connection was active and become idle now  (system var. RESETTING =  true)
    --     'D' = connection is gone (system var. RESETTING =  false)
    ,evt varchar(1)
    ,pool_active int -- value of rdb$get_context('SYSTEM','E`XT_CONN_POOL_ACTIVE_COUNT')
    ,pool_idle int -- value of rdb$get_context('SYSTEM','E`XT_CONN_POOL_IDLE_COUNT')
    ,constraint pk_perf_eds primary key(id)
);

create or alter view v_perf_eds as
select * from perf_eds
;
commit;



-- %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

set term ^;

create or alter trigger perf_estimated_bi for perf_estimated active before insert position 0 as
begin
    new.id = coalesce(new.id, gen_id(g_common, 1) );
end

^ -- perf_estimated_bi

create or alter procedure srv_gen_4drop_perf_log_split
returns( 
    sql_sttm varchar(32765) 
) as
    declare v_lf char(1);
    declare v_old_perf_split_name varchar(31);
begin
    v_lf = ascii_char(10);
    -- 08.10.2018. Called from 'oltp_isql_run_worker' batch scenario, when only session with SID=1 remains active.
    -- Generates SQL code for DROP procedure, trigger, view and perf_split_NN tables.

    sql_sttm = v_lf || 'create or alter view v_perf_log as select * from perf_log;'
            || v_lf || 'commit;'
    ;
    suspend;

    -- 18.03.2019: aux SP for totalling results that are in PERF_SPLIT_nn tables to PERF_LOG, using separate attachment.
    -- Purpose: reduce time of reports creation.
    sql_sttm = v_lf || 'set term ^;'
            || v_lf || 'create or alter procedure tmp_aggregate_perf_log_autogen( a_ignore_stop_flag dm_sign = 0 ) returns(msg dm_info) as begin end ^'
            || v_lf || 'set term ;^'
            || v_lf || 'commit;'
    ;
    suspend;
    
    -- 1. REcreate trigger for view v_perf_log with *EMPTY* body:
    --    we need to drop its dependencies on tables PERF_SPLIT_nn if they were created before this point.
    sql_sttm =    v_lf || 'create or alter trigger trg_v_perf_log active before insert on v_perf_log as'
          || v_lf || 'begin'
          || v_lf || 'end;'
          || v_lf || 'commit;'
    ;
    suspend;

    -- 2. DROP all tables with names PERF_SPLIT_nn
    for 
        select r.rdb$relation_name
        from rdb$relations r
        where r.rdb$relation_name starting with upper('perf_split_')
        into v_old_perf_split_name
    do begin
       sql_sttm = 'drop table ' || trim(v_old_perf_split_name) || ';' ;
       suspend;
    end
    sql_sttm = v_lf || 'commit;' ;
    suspend;
    
    -- 4. DROP trigger that does not depend on tables:
    sql_sttm = v_lf || 'drop trigger trg_v_perf_log;'
            || v_lf || 'commit;'
    ;
    suspend;

end

^ -- end of srv_gen_4drop_perf_log_split


create or alter procedure tmp$sp$gen_trigger_4_v_per_log(  a_perf_log_split_cnt smallint )
returns( 
    sql_sttm varchar(32765) 
) as
    declare v_lf char(1);
    declare v_old_perf_split_name varchar(31);
    declare i smallint;
    declare v_autogen varchar(128);
begin
    
    v_lf = ascii_char(10);

    v_autogen = '-- ### ACHTUNG ### DO NOT EDIT, GENERATED AUTO, see oltp_adjust_DDL.sql';
    
    -- 13.10.2018, called only from HERE, see EB below.
    -- Generates SQL statements for TRIGGER trg_v_perf_log which serves as 'case-switcher'
    -- on every insert into UPDATABLE VIEW v_perf_log.
    -- 15.10.2018, NB: trigger must be created even for number of perf_split_nn tables = 1:
    -- we have to ensure that field PERF_SPLIT_0.ID will be always NOT null!
    sql_sttm = v_lf || 'set term ^;'
       || v_lf || 'create or alter trigger trg_v_perf_log active before insert on v_perf_log as'
       || v_lf || '    declare v_dts_beg timestamp;'
       || v_lf || '    declare v_dts_end timestamp;'
    ;
    if ( a_perf_log_split_cnt >= 2 ) then
    begin
       sql_sttm = sql_sttm 
           || v_lf || '    declare c smallint;'
       ;
    end
    sql_sttm = sql_sttm 
        || v_lf || 'begin'
        || v_lf || '    ' || v_autogen
    ;
    suspend;

    -- 10.12.2018
    sql_sttm = v_lf 
            || v_lf || '    select p.test_time_dts_beg, p.test_time_dts_end from sp_get_test_time_dts p into v_dts_beg, v_dts_end;'
            || v_lf || '    if ( datediff( minute from v_dts_beg to v_dts_end ) < 2 ) then '
            || v_lf || '        -- We can omit logging performance data if test_phase is too small.'
            || v_lf || '        -- This means that we have only PREPARING phase for initial data filling.'
            || v_lf || '        exit;'
    ;    
    suspend;

    -- ########################################################################################
    -- new value for ID field must be always NOT null, regardless of a_perf_log_split_cnt value
    -- ########################################################################################
    -- gen_id() actually will NOT be called because new.id was already defined as
    -- v_pf_new_id = v_gen_inc_last_pf - ( c_gen_inc_step_pf - v_gen_inc_iter_pf );
    -- - see SP sp_add_perf_log

    sql_sttm = v_lf || 'new.id = coalesce(new.id, gen_id(g_perf_log, 1) );'
    ;
    suspend;
    i = 0;
    while ( i < a_perf_log_split_cnt ) do
    begin
        if ( i = 0 and a_perf_log_split_cnt >= 2 or i >= 1 ) then 
        begin
           if ( i = 0 ) then
           begin
               sql_sttm = v_lf || 'c = mod(current_connection, '|| a_perf_log_split_cnt ||');' 
               ;
               suspend;
           end
           sql_sttm =
                 v_lf || 'if ( c = ' || i || ') then'
              || v_lf || 'begin'
              || v_lf
           ;
           suspend;
        end
        
        sql_sttm =
                 v_lf || '    insert into perf_split_'|| i || '('
              || v_lf || '       id'
              || v_lf || '      ,unit'
              || v_lf || '      ,exc_unit'
              || v_lf || '      ,fb_gdscode'
              || v_lf || '      ,trn_id'
              || v_lf || '      ,att_id'
              || v_lf || '      ,elapsed_ms'
              || v_lf || '      ,info'
              || v_lf || '      ,exc_info'
              || v_lf || '      ,stack'
              || v_lf || '      ,ip'
              || v_lf || '      ,dts_beg'
              || v_lf || '      ,dts_end'
              || v_lf || '      ,aux1'
              || v_lf || '      ,aux2'
              || v_lf || '      ,dump_trn'
              || v_lf || '    ) values('
              || v_lf || '       new.id'
              || v_lf || '      ,new.unit'
              || v_lf || '      ,new.exc_unit'
              || v_lf || '      ,new.fb_gdscode'
              || v_lf || '      ,new.trn_id'
              || v_lf || '      ,new.att_id'
              || v_lf || '      ,new.elapsed_ms'
              || v_lf || '      ,new.info'
              || v_lf || '      ,new.exc_info'
              || v_lf || '      ,new.stack'
              || v_lf || '      ,new.ip'
              || v_lf || '      ,new.dts_beg'
              || v_lf || '      ,new.dts_end'
              || v_lf || '      ,new.aux1'
              || v_lf || '      ,new.aux2'
              || v_lf || '      ,new.dump_trn'
              || v_lf || '    );'
              || v_lf || '    exit;'
        ;
        suspend;
        if ( i = 0 and a_perf_log_split_cnt >= 2 or i >= 1 ) then 
        begin
            sql_sttm  =  v_lf || 'end';
            suspend;
        end
        i = i + 1;
    end

    sql_sttm = v_lf
        ||'end^ -- trg_v_perf_log' || v_lf
        ||'set term ^;' || v_lf
        ||'commit;' || v_lf ;
    suspend;

end -- tmp$sp$gen_trigger_4_v_per_log
^
set term ;^
commit;

--------------------------------------------------------------------------------------------------------------------


set term ^;
execute block returns(" " varchar(32765)) as
    declare v_lf char(1);
    declare v_separate_workers smallint = null;
    declare v_sessions_count smallint = null;
    declare v_used_in_repl smallint = null;
  
    declare C_MIN_SESSIONS_4PERF_LOG_SPLIT smallint = 20;
    declare C_PERF_LOG_MAX_COUNT_FOR_SPLIT smallint = 10;
    -- old, not needed: declare C_PERF_SPLIT_HANDLE_MOVED_ROWS varchar(10) = 'delete'; -- 'delete' or 'update' (--> update set id=-id)

    declare v_old_perf_split_name varchar(31);
    declare v_old_index_name varchar(31);

    declare v_perf_log_fld_ddl varchar(1000);
    declare i smallint;
    declare v_split_heavy_tabs smallint;
    declare v_perf_log_split_cnt smallint;
    declare v_autogen varchar(128);
    declare DBG_PRESERVE_PERF_LOG_ROWS smallint = 0; -- 26.03.2019
begin
    v_lf = ascii_char(10);
    v_autogen = '-- ### ACHTUNG ### DO NOT EDIT, GENERATED AUTO, see oltp_adjust_DDL.sql';

    " " = 'set bail on; ' || v_autogen
    ;
    suspend;

    -- +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    -- g e n e r a t e     S Q L     f o r    D R O P      o l d     t e m p o r a r y   P E R F_ S P L I T _ nn
    -- +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    for select sql_sttm from srv_gen_4drop_perf_log_split into " " 
    do 
        suspend;


    select s.svalue
    from settings s
    where upper(s.mcode) = upper('WORKERS_COUNT')
    into v_sessions_count;
    if ( v_sessions_count is null ) then
        exception ex_record_not_found;

    select s.svalue
    from settings s
    where upper(s.mcode) = upper('USED_IN_REPLICATION')
    into v_used_in_repl;
    if ( v_used_in_repl is null ) then
        exception ex_record_not_found;

    select s.svalue
    from settings s
    where s.mcode = upper('BUILD_WITH_SPLIT_HEAVY_TABS')
    into v_split_heavy_tabs;
    if ( v_sessions_count is null ) then
        exception ex_record_not_found;

    if ( v_split_heavy_tabs = 1 ) then
        v_perf_log_split_cnt = maxvalue( 1, minvalue( C_PERF_LOG_MAX_COUNT_FOR_SPLIT, cast(ceiling( 1.00 * v_sessions_count / 10 ) as smallint) ) );
    else
        v_perf_log_split_cnt = 1; -- regardless of launched ISQL sessions count!

    -- ##########################################################
    -- dis 15.10.2018 0945: decided to use PERF_SPLIT_01 in any case
    -- because one may to insert into table w/o any indices during test run.
    --if ( v_sessions_count < C_MIN_SESSIONS_4PERF_LOG_SPLIT ) then
    --    exit;
    -- ##########################################################

    v_perf_log_fld_ddl = 
                 '  id dm_idb not null'
      || v_lf || ' ,unit dm_unit'
      || v_lf || ' ,exc_unit char(1)'
      || v_lf || ' ,fb_gdscode int'
      || v_lf || ' ,trn_id bigint default current_transaction'
      || v_lf || ' ,att_id int default current_connection'
      || v_lf || ' ,elapsed_ms bigint'
      || v_lf || ' ,info dm_info'
      || v_lf || ' ,exc_info dm_info'
      || v_lf || ' ,stack dm_stack'
      || v_lf || ' ,ip dm_ip'
      || v_lf || ' ,dts_beg timestamp default ''now'''
      || v_lf || ' ,dts_end timestamp'
      || v_lf || ' ,aux1 double precision'
      || v_lf || ' ,aux2 double precision'
      || v_lf || ' ,dump_trn bigint default current_transaction'
    ; -- len = ~520

    " " = '-- char_length(v_perf_log_fld_ddl) = ' || char_length(v_perf_log_fld_ddl);
    suspend;

    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --      g e n e r a t e            p e r f _ s p l i t _ NN       t a b l e s
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#

    i = 0;
    while ( i < v_perf_log_split_cnt ) do
    begin
        " " = v_lf || 'recreate table perf_split_' || i || '(' || v_perf_log_fld_ddl || ');'
        ;
        suspend;

        if ( v_used_in_repl = 1 ) then
            begin
              " " =  v_lf || 'alter table perf_split_' || i || ' add constraint perf_split_' || i || '_pk primary key(id);'
              ;
              suspend;

            end
        else -- ==> UNIONED-view V_PERF_LOG will be used instead of TABLE PERF_LOG in all queries (NB: reports!)
            begin
              " " =  v_lf || '-- SKIP adding primary key to PERF_SPLIT_' || i 
              ;
              suspend;
            end

        i = i + 1;
    end
    " " = 'commit;' ;
    suspend;

    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --      a l t e r     v i e w     V _ P E R F _ L O G:    m a k e    i t    a s    " U N I O N E D "
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    " " = v_lf || 'Alter view v_perf_log as ' ;
    suspend;
    i = 0;
    while ( i < v_perf_log_split_cnt ) do
    begin
        if ( i = 0 ) then
        begin
            " " = v_lf || v_autogen ;
            suspend;
        end
        " " = v_lf || 'select * from perf_split_' || i || ' as p'||i -- add alias in order to reduce plan text length (4debug only)
        ;
        suspend;   
        
        " " = v_lf || trim( iif( i <= v_perf_log_split_cnt-2, 'union all', ';') )
        ;
        suspend;
        
        i = i + 1;
    end
    " " = 'commit;' ;
    suspend;


    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --     g e n e r a t e        T R I G G E R       t r g _ v _ p e r f _ l o g      c o d e
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    for
        select sql_sttm from tmp$sp$gen_trigger_4_v_per_log( :v_perf_log_split_cnt )
        into " "
    do
        suspend;


    -- 18.03.2019: aux SP for totalling results that are in PERF_SPLIT_nn tables to PERF_LOG, using separate attachment.
    -- Purpose: reduce time of reports creation.
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --     g e n e r a t e        p r o c     f o r     a g g.    p e r f.    r e s u l t s
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#

    " " = v_lf || 'set term ^;'
       || v_lf || 'create or alter procedure tmp_aggregate_perf_log_autogen('
       || v_lf || '    a_ignore_stop_flag dm_sign = 0' -- added 19.09.2020
       || v_lf || ') returns(msg dm_info) as'
       || v_lf || '    declare unit        dm_unit;'
       || v_lf || '    declare exc_unit    char(1);'
       || v_lf || '    declare fb_gdscode  int;'
       || v_lf || '    declare elapsed_ms  bigint;'
       || v_lf || '    declare v_intervals_number smallint;'
       || v_lf || '    declare v_test_time_dts_beg timestamp;'
       || v_lf || '    declare v_test_time_dts_end timestamp;'
       || v_lf || '    declare v_seconds_per_interval int;'
       || v_lf || '    declare v_minute_since_start int;'
       || v_lf || '    declare v_dts_end timestamp;'
       || v_lf || '    declare v_dts_interval int;'
       || v_lf || '    declare v_ins_rows int = 0;'
       || v_lf || '    declare v_upd_rows int = 0;'
       || v_lf || '    declare v_rownum int = 0;'
       || v_lf || '    declare v_stopcheck int = 5000; -- how often check for stop work inside loop of PERF_SPLIT_nn cursors'
       || v_lf || 'begin'
       || v_lf ||  v_autogen
    ;
    suspend;

    -- added 19.09.2020:
    " " = v_lf
       || v_lf || '    if ( a_ignore_stop_flag = 0 ) then'
       || v_lf || '    begin'
       || v_lf || '        -- Check that table `ext_stoptest` (external text file) is EMPTY,'
       || v_lf || '        -- otherwise raises e`xception to stop test:'
       || v_lf || '        execute procedure sp_check_to_stop_work;'
       || v_lf || '    end'
    ;
    suspend;

    --   || v_lf || '        -- We can SKIP from logging in perf_* tables if WARM_TIME not yet elapsed, i.e. when database is warmed-up.'
    " " = v_lf
       || v_lf || '    select p.test_time_dts_beg, p.test_time_dts_end, p.test_intervals'
       || v_lf || '    from sp_get_test_time_dts p'
       || v_lf || '    into v_test_time_dts_beg, v_test_time_dts_end, v_intervals_number;'
       || v_lf || '    if ( cast(''now'' as timestamp) < v_test_time_dts_beg ) then'
       || v_lf || '    begin'
       || v_lf || '        msg = ''SKIP until WARM_TIME expire at '' || left(cast(v_test_time_dts_beg as varchar(50)), 19);'
       || v_lf || '        suspend;'
       || v_lf || '        exit;'
       || v_lf || '    end'
       || v_lf || '    v_seconds_per_interval = 1 + datediff(second from v_test_time_dts_beg to v_test_time_dts_end) / v_intervals_number;'
    ;
    suspend;

    i = 0;
    while ( i < v_perf_log_split_cnt ) do
    begin

        if (v_perf_log_split_cnt > 1) then
        begin
            " " =  v_lf || '-- ' || lpad( '', 80, '#' )
                || v_lf || '-- iter '|| (i+1) ||' of ' || v_perf_log_split_cnt
            ;
            suspend;
        end


        if (i > 0) then
        begin
            -- added 19.09.2020: all essions except SID=1 must check stop-flag here:
            " " =  v_lf 
                || v_lf || '    if ( a_ignore_stop_flag = 0 ) then'
                || v_lf || '    begin'
                || v_lf || '        -- NB: only sessions with SID > 1 must check need to stop work'
                || v_lf || '        -- Session with SID = 1 must gather performance data regardless stop-flag.'
                || v_lf || '        execute procedure sp_check_to_stop_work;'
                || v_lf || '    end'
            ;
            suspend;
        end



        " " =  v_lf || '    for'
            || v_lf || '        select'
            || v_lf || '             unit'
            || v_lf || '            ,exc_unit'
            || v_lf || '            ,fb_gdscode'
            || v_lf || '            ,coalesce(elapsed_ms, 0) as elapsed_ms'
            || v_lf || '            ,dts_end'
            || v_lf || '        from perf_split_' || i || ' as p'
            || v_lf || '        where p.dts_end >= :v_test_time_dts_beg'
            || v_lf || '              and p.unit is not null' -- 21.04.2019: to be sure, otherwise no_dup exception can occur if unit is null.
        ;
        suspend;

        if ( DBG_PRESERVE_PERF_LOG_ROWS = 1  ) then
        begin
            -- temply, 4debug only: need for compare results with old report SPs
            " " =  v_lf || '              and id > 0'
            ;
            suspend;
        end

        " " =  v_lf || '        into'
            || v_lf || '             unit'
            || v_lf || '            ,exc_unit'
            || v_lf || '            ,fb_gdscode'
            || v_lf || '            ,elapsed_ms'
            || v_lf || '            ,v_dts_end'
            || v_lf || '    as cursor c'
            || v_lf || '    do begin'
        ;
        suspend;

        -- added 19.09.2020: all essions except SID=1 must check stop-flag here:
        " " =  v_lf || '        v_rownum = v_rownum + 1;'
            || v_lf || '        if ( a_ignore_stop_flag = 0 and mod(v_rownum, v_stopcheck) = 0 ) then'
            || v_lf || '        begin'
            || v_lf || '            -- NB: only sessions with SID > 1 must check need to stop work'
            || v_lf || '            -- Session with SID = 1 must gather performance data regardless stop-flag.'
            || v_lf || '            execute procedure sp_check_to_stop_work;'
            || v_lf || '        end'
        ;
        suspend;

        " " =  v_lf || '        v_dts_interval = 1 + cast( datediff(second from v_test_time_dts_beg to v_dts_end) / v_seconds_per_interval as int);'
            || v_lf || '        update v_perf_agg a set'
            || v_lf || '             total_cnt = total_cnt + 1'
            || v_lf || '            ,total_ms = total_ms + :elapsed_ms'
            || v_lf || '            ,min_ms = minvalue( min_ms, :elapsed_ms)'
            || v_lf || '            ,max_ms = maxvalue( max_ms, :elapsed_ms)'
            || v_lf || '        where'
            || v_lf || '            a.unit = :unit'
            || v_lf || '            and a.fb_gdscode is not distinct from :fb_gdscode'
            || v_lf || '            and a.exc_unit is not distinct from :exc_unit'
            || v_lf || '            and a.dts_interval is not distinct from :v_dts_interval'
            || v_lf || '        ;'
        ;
        suspend;

        " " =  v_lf || '        if ( row_count  = 0 ) then'
            || v_lf || '            begin'
            || v_lf || '                insert into v_perf_agg( unit,  exc_unit,  fb_gdscode,  dts_interval,    total_cnt, total_ms,    min_ms,      max_ms )'
            || v_lf || '                                values( :unit, :exc_unit, :fb_gdscode, :v_dts_interval,         1, :elapsed_ms, :elapsed_ms, :elapsed_ms );'
            || v_lf || '                v_ins_rows = v_ins_rows + 1;'
            || v_lf || '            end'
            || v_lf || '        else'
            || v_lf || '            v_upd_rows = v_upd_rows + 1;'
        ;
        suspend;


        if ( DBG_PRESERVE_PERF_LOG_ROWS = 1  ) then
            begin
                -- temply, 4debug only: need for compare results with old report SPs
                " " =  v_lf || '        update perf_split_' || i || ' set id = -id'
                    || v_lf || '        where current of c;'
                ;
                suspend;
            end
        else
            begin
                " " =  v_lf || '       delete from perf_split_' || i
                    || v_lf || '       where current of c;'
                ;
                suspend;
            end

        " " = v_lf || '    end' ;
        suspend;

        i = i + 1;

    end

    " " = v_lf || '    msg = ''i='' || v_ins_rows || '', u='' || v_upd_rows;'
       || v_lf || '    rdb$set_context(''USER_SESSION'', ''ADD_INFO'', msg); -- to be displayed in result log of isql'
       || v_lf || '    suspend;'
    ;
    suspend;

    " " =  v_lf 
        || v_lf || 'end ^'
        || v_lf || 'set term ;^'
        || v_lf || 'commit;'
    ;
    suspend;
end
^



-- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
--    g e n e r a t e        D D L      f o r     d r o p / c r e a t e    i n d i c e s
--    o n    t a b l e s     D O C _ L I S T,     P D I S T R,     P S T O R N E D
-- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
execute block returns(" " varchar(32765)) as
    declare v_lf char(1);
    declare v_separate_workers smallint = null;
    declare v_old_index_name varchar(31);
    declare v_has_some_docs smallint = 0;
begin
    v_lf = ascii_char(10);

    select count(*) from (select 1 x from doc_list rows 1) into v_has_some_docs;

    -- ===== step-1: DROP OLD indexes if they exist =====
    for 
        select ri.rdb$index_name
        from rdb$indices ri
        where ri.rdb$index_name in ( 
                   upper('doc_list_worker_optype') 
                  ,upper('pdistr_worker_snd_id') 
                  ,upper('pstorned_worker_id') 
                  ,upper('pdistr_snd_id') 
              )
        into v_old_index_name
    do begin
        " " = v_lf || 'drop index ' || trim(v_old_index_name) || ';' ;
        suspend;
    end

    -- ===== step-2: DROP OLD constraints if they exist =====

    if ( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.5' ) then
        begin
            -- drop check constraint 'worker_id_nn' that was added before:
            if ( exists( select 1 from 
                         rdb$relation_constraints rc 
                         where 
                             rc.rdb$relation_name = upper('doc_list') 
                             and rc.rdb$constraint_type = upper('check') 
                             and rc.rdb$constraint_name = upper('worker_id_nn')
                       )
               ) then
            begin
                " " = v_lf || 'alter table doc_list drop constraint worker_id_nn;'
                   || v_lf || 'commit;' 
                ;
                suspend;
            end
        end
    else
        begin
            -- drop NOT_NULL field constraint that was added before:
            if ( exists( select 1 from 
                         rdb$relation_fields rf
                         where 
                             rf.rdb$relation_name = upper('doc_list') 
                             and rf.rdb$field_name = upper('worker_id')
                             and rf.rdb$null_flag = 1
                       )
               ) then
            begin
                " " = v_lf || 'alter table doc_list alter column worker_id drop NOT null;'
                   || v_lf || 'commit;' 
                ;
                suspend;
            end
        end

    " " = v_lf || 'commit;';
    suspend;


    -- Value 'v_separate_workers' is defined by config parameter 'separate_workers': 1 or 0.
    select s.svalue
    from settings s
    where s.working_mode = upper('COMMON') and s.mcode = upper('SEPARATE_WORKERS')
    into v_separate_workers;
    if ( v_separate_workers is null ) then
        exception ex_record_not_found;
                            
    -- 05.10.2018: moved here from batch files:
    if ( v_separate_workers = 1 ) then
        begin

            -- ===== step-3: CREATE indexes that is need when workers MUST BE separated  =====

            -- we have to add index on field WORKER_ID, tables: DOC_LIST, PDISTR, PSTORNED.
            -- This field contains 'sequential number' of each ISQL and serves for separating
            -- scope of documents which can be handled by "this" ISQL session.

            " " = 'create index doc_list_worker_optype on doc_list(worker_id, optype_id);' || v_lf ||
                  'commit;' ;
            suspend;

            if ( v_has_some_docs = 0 ) then
            begin
                -- 09.06.2021
                -- We can add NOT-NULL constraint on doc_list.worker_id only when there are no documents.
                -- Otherwise we have to leave existing documents with worker_id = null:

                if ( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.5' ) then
                    " " = 'alter table doc_list add constraint worker_id_nn check( worker_id is not null );' ;
                else
                    " " = 'alter table doc_list alter column worker_id set NOT null;' ;

                " " = " " || v_lf || 'commit;' ;
                suspend;
            end

            ---------------------------------------------------------------------------------------------
            " " = 'create index pdistr_worker_snd_id on pdistr(worker_id, snd_id);' || v_lf ||
                  'commit;' ;
            suspend;
            ---------------------------------------------------------------------------------------------
            " " = 'create index pstorned_worker_id on pstorned(worker_id);' || v_lf ||
                  'commit;' ;
            suspend;
        end -- v_separate_workers = 1
    else -- :::::::::::::::::::::::::::::::::::: v_separate_workers = 0 :::::::::::::::::::::::::::::::::::
        begin
            -- ===== step-3: CREATE indexes that is need when workers are NO separated  =====

            -- NB: it seems that index on doc_list(optype_id) is HARMFUL because of too low selectivity!
            -- Benchmark is needed; index creation is deferred.
            " " =    v_lf || 'create index pdistr_snd_id on pdistr(snd_id);' 
                  || v_lf || 'commit;' ;
            suspend;
        end -- v_separate_workers = 0

end
^
set term ;^
commit;

drop procedure tmp$sp$gen_trigger_4_v_per_log;
commit;

-- #####################################################################################################################

set heading off;
set list on;

select 'set echo off;' as " "
from rdb$database
union all
select 'set list on; select ''oltp_adjust_DDL.sql finish at '' || current_timestamp as msg from rdb$database;' as " "
from rdb$database
;
commit;

-- ##########################################################
-- End of script oltp_adjust_DDL.sql; next to be run:
-- oltp_replication_DDL.sql (common for both FB 2.5 and 3.0)
-- ##########################################################
