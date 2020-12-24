-- ###################################
-- Begin of script oltp_adjust_eds_perf.sql
-- ###################################

-- ::: NB ::: This script is 4.0+ only and is called when use_es = 2.
-- NB. Script must be called with "-nod" switch
set bail on;
set list off;

set heading off;
select 'set list on; select ''oltp_adjust_eds_perf.sql start at '' || current_timestamp as msg from rdb$database;' as " "
from rdb$database
union all
select 'set echo off; commit; set transaction no wait;' as " "
from rdb$database
;
commit;
set heading on;
set list on;

set transaction no wait;

-- Dummy view for ability to DROP tables perf_eds_split_NN and create them again
-- (much faster than delete all rows from it before every new test launch)
-- 03.12.2020. NB: this DDL must always be the same as in oltp30_DDL.sql
create or alter view v_perf_eds as
select 
     1 as id
    ,current_timestamp as dts
    ,1 as att
    ,1 as trn
    ,'' as app
    ,'' as evt
from rdb$database;
commit;

create or alter view v_perf_eds_life_agg as
select
     1 as att
    ,current_timestamp as dts_born
    ,current_timestamp as dts_last
    ,current_timestamp as dts_gone
    ,0 as max_idle_ms
    ,0 as avg_idle_ms
    ,'' as evt_last
    ,0 as evt_cnt
from rdb$database;
commit;

drop table perf_eds_life_agg;
commit;

recreate table perf_eds_life_agg (
     att bigint not null
    ,dts_born timestamp -- new EDS connection established, i.e. first record with evt for this EDS att in v_perf_eds (ordered by timestamp)
    ,dts_last timestamp -- last activity of this EDS before it gone (last record with evt='A' before record with evt = 'D', ord. by timestamp)
    ,dts_gone timestamp -- dts when connection is gone, i.e. last record with evt for this EDS att in v_perf_eds (ordered by timestamp)
    ,max_idle_ms int -- max duration of IDLE state for att
    ,avg_idle_ms double precision -- avg duration of IDLE state for key att
    ,evt_last char(1) -- last event type; if 'A' and new is 'B' then datediff between them is duration of IDLE state
    ,evt_cnt bigint -- needed for counting avg_idle_ms 'on-the-fly'
    ,id dm_idb -- needed only when config parameter 'used_in_replication' = 1
    ,constraint perf_eds_life_agg_pk primary key(att)
    --,constraint perf_eds_life_agg_unq unique (att)
);
commit;

create or alter view v_perf_eds_life_agg as
select * from perf_eds_life_agg
;
commit;

delete from perf_eds_agg;
commit;


---- %%%%%%%%%%%%%%%%%%%%%  D R O P  + C R E A T E     T A B L E    P E R F _ E D S  %%%%%%%%%%%%%%%%%%%%%

set term ^;
create or alter procedure srv_gen_4drop_perf_eds_split
returns( 
    sql_sttm varchar(32765) 
) as
    declare v_lf char(1) = x'0A';
    declare v_old_perf_eds_split_name varchar(31);
begin

    -- 04.12.2020. Called from 'oltp_isql_run_worker' batch scenario, when only session with SID=1 remains active.
    -- Generates SQL code for DROP procedure, trigger, view and perf_eds_split_NN tables.

    -- SP for totalling results that are in PERF_EDS_SPLIT_nn tables to PERF_EDS, using separate attachment.
    -- Purpose: reduce time of reports creation.
    sql_sttm = v_lf || 'set term ^;'
            || v_lf || 'create or alter procedure tmp_aggregate_perf_eds_autogen( a_ignore_stop_flag dm_sign = 0 ) '
            || v_lf || 'returns(msg dm_info) as '
            || v_lf || 'begin '
            || v_lf || '    suspend; '
            || v_lf || 'end^' 
            || v_lf || 'set term ;^' 
            || v_lf || 'commit;'
    ;
    suspend;
    
    -- 1. REcreate trigger for view v_perf_eds with *EMPTY* body:
    --    we need to drop its dependencies on tables PERF_EDS_SPLIT_nn if they were created before this point.
    sql_sttm = v_lf || 'create or alter trigger trg_v_perf_eds active before insert on v_perf_eds as '
            || v_lf || 'begin '
            || v_lf || 'end;'
            || v_lf || 'commit;'
    ;
    suspend;

    -- 2. DROP all tables with names PERF_EDS_SPLIT_nn
    for 
        select r.rdb$relation_name
        from rdb$relations r
        where r.rdb$relation_name starting with upper('perf_eds_split_')
            and r.rdb$relation_type in( 0, 4, 5) -- permanent, session-GTT, tx-GTT
        into v_old_perf_eds_split_name
    do begin
       sql_sttm = 'drop table ' || trim(v_old_perf_eds_split_name) || ';' ;
       suspend;
    end
    sql_sttm = v_lf || 'commit;' ;
    suspend;
    
    -- 4. DROP trigger that does not depend on tables:
    sql_sttm = v_lf || 'drop trigger trg_v_perf_eds;'
            || v_lf || 'commit;'
    ;
    suspend;

end

^ -- end of srv_gen_4drop_perf_eds_split


create or alter procedure tmp$sp$gen_trg_4_v_perf_eds( a_perf_eds_split_cnt smallint )
returns( 
    sql_sttm varchar(32765) 
) as
    declare v_lf char(1) = x'0A';
    declare v_old_perf_eds_split_name varchar(31);
    declare i smallint;
    declare v_autogen varchar(128);
begin

    v_autogen = '-- ### ACHTUNG ### DO NOT EDIT, GENERATED AUTO, see oltp_adjust_eds_perf.sql';
    
    -- Called only from HERE, see execute_block below.
    -- Generates SQL statements for TRIGGER trg_v_perf_eds which serves as 'case-switcher'
    -- on every insert into UPDATABLE VIEW v_perf_eds.
    -- Trigger must be created even for number of perf_split_nn tables = 1.
    sql_sttm = v_lf || 'set term ^;'
       || v_lf || 'create or alter trigger trg_v_perf_eds active before insert on v_perf_eds as'
       || v_lf || '    declare v_dts_beg timestamp;'
       || v_lf || '    declare v_dts_end timestamp;'
    ;
    if ( a_perf_eds_split_cnt >= 2 ) then
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

    sql_sttm = v_lf 
            || v_lf || '    select p.test_time_dts_beg, p.test_time_dts_end '
            || v_lf || '    from sp_get_test_time_dts p '
            || v_lf || '    into v_dts_beg, v_dts_end;'
            || v_lf || '    if ( cast(''now'' as timestamp) NOT between v_dts_beg and v_dts_end ) then '
            || v_lf || '        -- Skip logging out of test phase scope (i.e. on warm phase or when final reports are created).'
            || v_lf || '        exit;'
    ;    
    suspend;

    sql_sttm =
           v_lf || '    new.id = coalesce( new.id, gen_id(g_perf_log, 1) );'
    ;
    suspend;

    i = 0;
    while ( i < a_perf_eds_split_cnt ) do
    begin
        if ( i = 0 and a_perf_eds_split_cnt >= 2 or i >= 1 ) then 
        begin
           if ( i = 0 ) then
           begin
               sql_sttm = v_lf || '    c = mod(current_connection, '|| a_perf_eds_split_cnt ||');'
               ;
               suspend;
           end
           sql_sttm =
                 v_lf || '    if ( c = ' || i || ') then'
              || v_lf || '    begin'
              || v_lf
           ;
           suspend;
        end
        
        sql_sttm =
               v_lf || '        insert into perf_eds_split_'|| i
            || v_lf || '              (id,     app,     evt     )'
            || v_lf || '        values(new.id, new.app, new.evt );'
            || v_lf || '        exit;'
        ;
        suspend;
        if ( i = 0 and a_perf_eds_split_cnt >= 2 or i >= 1 ) then 
        begin
            sql_sttm  =  v_lf || '    end';
            suspend;
        end
        i = i + 1;
    end

    sql_sttm = v_lf
        ||'end^ -- trg_v_perf_eds' || v_lf
        ||'set term ;^' || v_lf
        ||'commit;' || v_lf ;
    suspend;

end -- tmp$sp$gen_trg_4_v_perf_eds
^
set term ;^
commit;

--------------------------------------------------------------------------------------------------------------------


set term ^;
execute block returns(" " varchar(32765)) as
    declare v_lf char(1) = x'0A';

    declare v_use_es smallint = null;
    declare v_split_heavy_tabs smallint;
    declare v_separate_workers smallint = null;
    declare v_sessions_count smallint = null;
    declare v_used_in_repl smallint = null;
  
    declare C_MIN_SESSIONS_4PERF_EDS_SPLIT smallint = 20;
    declare C_PERF_EDS_MAX_COUNT_FOR_SPLIT smallint = 10;

    declare v_perf_eds_fld_ddl varchar(1000);
    declare i smallint;
    declare v_perf_eds_split_cnt smallint;
    declare v_autogen varchar(128);
    declare DBG_PRESERVE_PERF_EDS_ROWS smallint = 0; -- must be 0; change to 1 only 4debug
begin

    v_autogen = '-- ### ACHTUNG ### DO NOT EDIT, GENERATED AUTO, see oltp_adjust_eds_perf.sql';

    " " = 'set bail on; '
    ;
    suspend;

    select
         max( iif( s.mcode = upper('USE_ES'), s.svalue, null ) )
        ,max( iif( s.mcode = upper('WORKERS_COUNT'), s.svalue, null ) )
        ,max( iif( s.mcode = upper('USED_IN_REPLICATION'), s.svalue, null ) )
        ,max( iif( s.mcode = upper('BUILD_WITH_SPLIT_HEAVY_TABS'), s.svalue, null ) )
    from settings s
    where s.mcode in ( upper('USE_ES'), upper('WORKERS_COUNT'), upper('USED_IN_REPLICATION'), upper('BUILD_WITH_SPLIT_HEAVY_TABS') )
    into v_use_es, v_sessions_count, v_used_in_repl, v_split_heavy_tabs;

    if ( v_use_es is null or v_sessions_count is null or v_used_in_repl is null or v_split_heavy_tabs is null ) then
        exception ex_record_not_found using('SETTINGS', 'USE_ES / WORKERS_COUNT / USED_IN_REPLICATION / BUILD_WITH_SPLIT_HEAVY_TABS');

    -- +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    -- g e n e r a t e     S Q L     f o r    D R O P     t e m p o r a r y   P E R F _ E D S _ S P L I T _ nn
    -- +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    for select sql_sttm from srv_gen_4drop_perf_eds_split into " "
    do 
        suspend;

    if ( v_use_es < 2 ) then
        -- ###################
        -- ###   e x i t   ###
        -- ###################
        exit;

    if ( v_split_heavy_tabs = 1 ) then
        v_perf_eds_split_cnt = maxvalue( 1, minvalue( C_PERF_EDS_MAX_COUNT_FOR_SPLIT, cast(ceiling( 1.00 * v_sessions_count / 10 ) as smallint) ) );
    else
        v_perf_eds_split_cnt = 1; -- regardless of launched ISQL sessions count!

    v_perf_eds_fld_ddl = v_lf ||
                 ' id int not null'
      || v_lf || ',dts timestamp default ''now'''
      || v_lf || ',att int default current_connection'
      || v_lf || ',trn int default current_transaction'
      || v_lf || ',app varchar(80)'
      || v_lf || ',evt varchar(1)'
    ;


    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --      g e n e r a t e        p e r f _ e d s _ s p l i t _ NN       t a b l e s
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#

    i = 0;
    while ( i < v_perf_eds_split_cnt ) do
    begin
        " " = v_lf || 'recreate table perf_eds_split_' || i || '(' || v_perf_eds_fld_ddl || ');'
        ;
        suspend;

        if ( DBG_PRESERVE_PERF_EDS_ROWS = 0 ) then
            begin
                -- ::: NB ::: Index on column ID must be created in ANY CASE, regardless of involving to replication.
                -- See below 'for select perf_eds_split_<i> ... order by ID' - this order is MANDATORY for correct results of aggregation!
                " " =  v_lf || 'alter table perf_eds_split_' || i || ' add constraint perf_eds_split_' || i || '_pk primary key(id);'
                ;
                suspend;
            end
        else
            begin
                -- 4debug only, when perf_eds_split_NN rows are preserved rather than deleted
                -- See below WHERE-expression of query: ' and p.att >=0 and p.id >= 0'
                " " =  v_lf || 'alter table perf_eds_split_' || i || ' add constraint perf_eds_split_' || i || '_pk primary key(att, id);'
                ;
                suspend;
            end
        
        
        i = i + 1;
    end
    " " = 'commit;' ;
    suspend;

    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --      a l t e r     v i e w     V _ P E R F _ E D S:    m a k e    i t    a s    " U N I O N E D "
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    " " = v_lf || 'Alter view v_perf_eds as ' ;
    suspend;
    i = 0;
    while ( i < v_perf_eds_split_cnt ) do
    begin
        if ( i = 0 ) then
        begin
            " " = v_lf || v_autogen ;
            suspend;
        end
        " " = v_lf || 'select * from perf_eds_split_' || i || ' as p'||i -- add alias in order to reduce plan text length (4debug only)
        ;
        suspend;   
        
        " " = v_lf || trim( iif( i <= v_perf_eds_split_cnt-2, 'union all', ';') )
        ;
        suspend;
        
        i = i + 1;
    end
    " " = 'commit;' ;
    suspend;


    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --     g e n e r a t e        T R I G G E R       t r g _ v _ p e r f _ e d s      c o d e
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    for
        select sql_sttm
        from tmp$sp$gen_trg_4_v_perf_eds( :v_perf_eds_split_cnt )
        into " "
    do
        suspend;


    -- Generate SP for totalling results that are in PERF_EDS_SPLIT_nn tables
    -- to V_PERF_EDS_AGG (which is 1-to-1 projecttion of table PERF_EDS_AGG).
    -- Purpose: reduce time of reports creation.
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
    --     g e n e r a t e        p r o c     f o r     a g g.    p e r f _ e d s     d a t a
    -- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#


    " " = v_lf || 'set term ^;'
       || v_lf || 'create or alter procedure tmp_aggregate_perf_eds_autogen('
       || v_lf || '    a_ignore_stop_flag dm_sign = 0'
       || v_lf || ') returns(msg dm_info) as'
       || v_lf || '    declare v_ins_rows int = 0;'
       || v_lf || '    declare v_upd_rows int = 0;'
       || v_lf || '    declare v_rownum int = 0;'
       || v_lf || '    declare v_test_time_dts_beg timestamp;'
       || v_lf || '    declare v_minute_since_test_start int;'
       || v_lf || '    declare v_stopcheck int = 5000; -- how often check for stop work inside loop of PERF_SPLIT_nn cursors'
       || v_lf || 'begin'
       || v_lf ||  v_autogen
    ;
    suspend;


    " " = v_lf
       || v_lf || '    if ( a_ignore_stop_flag = 0 ) then'
       || v_lf || '    begin'
       || v_lf || '        -- Check that table `ext_stoptest` (external text file) is EMPTY,'
       || v_lf || '        -- otherwise raises e`xception to stop test:'
       || v_lf || '        execute procedure sp_check_to_stop_work;'
       || v_lf || '    end'
    ;
    suspend;


    " " = v_lf
       || v_lf || '    select p.test_time_dts_beg'
       || v_lf || '    from sp_get_test_time_dts p'
       || v_lf || '    into v_test_time_dts_beg;'
       || v_lf || '    if ( cast(''now'' as timestamp) < v_test_time_dts_beg ) then'
       || v_lf || '    begin'
       || v_lf || '        msg = ''SKIP until WARM_TIME expire at '' || left(cast(v_test_time_dts_beg as varchar(50)), 19);'
       || v_lf || '        suspend;'
       || v_lf || '        exit;'
       || v_lf || '    end'
    ;
    suspend;

    i = 0;
    while ( i < v_perf_eds_split_cnt ) do
    begin

        if (v_perf_eds_split_cnt > 1) then
        begin
            " " =  v_lf || '-- ' || lpad( '', 80, '#' )
                || v_lf || '-- iter '|| (i+1) ||' of ' || v_perf_eds_split_cnt
            ;
            suspend;
        end


        if (i > 0) then
        begin
            -- All sessions except SID=1 must check stop-flag here:
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
            || v_lf || '             att'
            || v_lf || '            ,dts'
            || v_lf || '            ,evt'
            || v_lf || '        from perf_eds_split_' || i || ' as p'
            || v_lf || '        where p.dts >= :v_test_time_dts_beg and p.evt in(''N'', ''B'', ''I'', ''A'', ''D'')'
        ;

        if (DBG_PRESERVE_PERF_EDS_ROWS = 1) then
            -- We have to handle rows from perf_eds_split<I> in the order of their appearance! INDEX IS MANDATORY HERE!
            " " = " " || ' and p.att >=0 and p.id >= 0 order by p.att, p.id'
            ;

        else
            -- We have to handle rows from perf_eds_split<I> in the order of their appearance! INDEX IS MANDATORY HERE!
            " " = " " || ' order by p.id'
            ;

        " " = " " 
            || v_lf || '    as cursor c'
            || v_lf || '    do begin'
        ;
        suspend;

        -- All sessions except SID=1 must check stop-flag here:
        " " =  v_lf || '        v_rownum = v_rownum + 1;'
            || v_lf || '        if ( a_ignore_stop_flag = 0 and mod(v_rownum, v_stopcheck) = 0 ) then'
            || v_lf || '        begin'
            || v_lf || '            -- NB: only sessions with SID > 1 must check need to stop work'
            || v_lf || '            -- Session with SID = 1 must gather performance data regardless stop-flag.'
            || v_lf || '            execute procedure sp_check_to_stop_work;'
            || v_lf || '        end'
        ;
        suspend;


        -- NB: changing state of external connection from active to idle is done via ALTER SESSION RESET.
        -- It does following (see CORE-5832, starting comment by hvlad):
        -- - throw error (isc_ses_reset_err) if any open transaction exist in current conneciton, except of current transaction
        --   and prepared 2PC transactions which is allowed and ignored by this check
        -- - system variable RESETTING is set to true
        -- - ON DISCONNECT database triggers is fired, if present and allowed for current connection
        -- - ROLLBACK current user transaction (if present) and issue warning if that transaction changes any table before reset
        -- - reset DECFLOAT parameters (BIND, TRAP and ROUND) to its default values
        -- - reset session and statement timeouts to zero
        -- - remove all context variables in 'USER_SESSION' namespace
        -- - restore ROLE which was passed with DPB and clear all cached security classes (if role was changed)
        -- - clear contents of all used GLOBAL TEMPORARY TABLE ... ON COMMIT PRESERVE ROWS
        -- - ON CONNECT database triggers is fired, if present and allowed for current connection
        -- - START new transaction with the same properties as transaction that was rolled back (if transaction was present
        --   before reset)
        -- - system variable RESETTING is set to false
        -- Note, CURRENT_USER and CURRENT_CONNECTION will not be changed. 

        -- KEY NOTE: *BOTH* db-level triggers fire in that case, i.e.:
        -- 1. on DISCONNECT, which leads event type = 'I' to be written into v_perf_eds log;
        -- 2. on CONNECT, which leads event type = 'A' to be written into v_perf_eds log.
        -- When further this connection is required for new job (and must be changed to Active) then event type = 'B' is written
        -- into v_perf_eds, just before 'main' DML which is to be done within EDS (see multiple calls of SP 'sp_perf_eds_logging').
        -- This means that datediff between events of type 'A' and 'B' is exact duration of IDLE state that this connection was in.
        -- We have to take in account only records where event types are 'A' (this is when ALTER SESSION RESET was completed)
        -- and 'B' (this is where connection become active again).
        -- ### ACHTUNG ###
        -- NO trigger fires when connection state is changed from IDLE to ACTIVE!
        -- Both of them are done only when ACTIVE is changed to IDLE.


        -- Accumulate data about life activity: get avg_idle_ms, max_idle_ms (will be used in SP report_extpool_lifetime):
        " " =  v_lf || '        update v_perf_eds_life_agg a set '
            || v_lf || '            dts_born = minvalue(dts_born, c.dts)' -- timestamp of EDS creation
            || v_lf || '           ,dts_last = iif(c.evt<>''D'', maxvalue(dts_last, c.dts), dts_last)' -- last EDS-activity before this connection gone
            || v_lf || '           ,dts_gone = maxvalue(dts_gone, c.dts)'  -- timestamp of detach
            || v_lf || '           ,max_idle_ms = iif( c.evt = ''B'' and a.evt_last = ''A'', maxvalue(datediff(millisecond from a.dts_last to c.dts), a.max_idle_ms), a.max_idle_ms)'
            || v_lf || '           ,avg_idle_ms = iif( c.evt = ''B'' and a.evt_last = ''A'' and datediff(millisecond from a.dts_last to c.dts) > 0'
            || v_lf || '                               ,1.000 * (a.avg_idle_ms * a.evt_cnt + datediff(millisecond from a.dts_last to c.dts)) / (a.evt_cnt+1)'
            || v_lf || '                               ,a.avg_idle_ms '
            || v_lf || '                             )'
            || v_lf || '           ,evt_last = c.evt'
            || v_lf || '           ,evt_cnt = evt_cnt + iif( c.evt = ''B'' and a.evt_last = ''A'' and datediff(millisecond from a.dts_last to c.dts) > 0, 1, 0)'
            || v_lf || '        where a.att = c.att;' --  and a.att = c.att;' -- PK
        ;
        suspend;

        " " =  v_lf || '        if ( row_count  = 0 ) then '
            || v_lf || '            insert into v_perf_eds_life_agg('
            || v_lf || '                 att'           --  1
            || v_lf || '                ,dts_born'      --  2
            || v_lf || '                ,dts_last'      --  3
            || v_lf || '                ,dts_gone'      --  4
            || v_lf || '                ,max_idle_ms'   --  5
            || v_lf || '                ,avg_idle_ms'   --  6
            || v_lf || '                ,evt_last'      --  7
            || v_lf || '                ,evt_cnt'       --  8
            || v_lf || '            ) values('
            || v_lf || '                c.att'          --  1
            || v_lf || '                ,c.dts'         --  2: dts_born
            || v_lf || '                ,c.dts'         --  3: dts_last
            || v_lf || '                ,c.dts'         --  4: dts_gone
            || v_lf || '                ,0'             --  5: max_idle_ms
            || v_lf || '                ,0'             --  6: avg_idle_ms
            || v_lf || '                ,c.evt'         --  7: evt_last
            || v_lf || '                ,0'             --  8: evt_cnt
            || v_lf || '            );'
        ;
        suspend;

        /*
            Query for check results:
            ------------------------
            select
                 att
                ,cast(avg(idle_ms) as numeric(12,6)) as avg_idle_ms
                ,cast(max(idle_ms) as int) as max_idle_ms
            from (
              select
                    att
                    ,prev_evt
                    ,evt
                    ,prev_dts
                    ,dts
                    ,idle_ms
                    ,id
              from (
                  select
                      p.att
                      ,lag(p.evt)over(partition by p.att order by abs(p.id)) prev_evt
                      ,p.evt
                      ,lag(p.dts)over(partition by p.att order by abs(p.id)) prev_dts
                      ,p.dts
                      ,cast (
                       iif(  lag(p.evt)over(partition by p.att order by abs(p.id) ) = 'A'  and evt = 'B'
                             ,datediff(millisecond from lag(p.dts)over(partition by p.att order by abs(p.id)) to dts)
                             ,null
                           )
                        as double precision ) idle_ms
                      ,p.id
                    from v_perf_eds p
                    order by p.att, abs(p.id)
              ) p
              where p.idle_ms > 0
              order by p.att, abs(p.id)
            )
            group by att

        */
        
        --  evt_overall_cnt = computed_by: sum of all evt_* counters
        " " =  v_lf || '        v_minute_since_test_start = cast( datediff(second from v_test_time_dts_beg to c.dts) / 60 as int );'
            || v_lf || '        update v_perf_eds_agg a set'
            || v_lf || '             evt_N_total_cnt = evt_N_total_cnt + iif(c.evt = ''N'', 1, 0)'
            || v_lf || '            ,evt_A_total_cnt = evt_A_total_cnt + iif(c.evt = ''A'', 1, 0)'
            || v_lf || '            ,evt_I_total_cnt = evt_I_total_cnt + iif(c.evt = ''I'', 1, 0)'
            || v_lf || '            ,evt_D_total_cnt = evt_D_total_cnt + iif(c.evt = ''D'', 1, 0)'
            || v_lf || '        where'
            || v_lf || '            a.minute_since_test_start = :v_minute_since_test_start'
            || v_lf || '        ;'
        ;
        suspend;

        " " =  v_lf || '        if ( row_count  = 0 ) then'
            || v_lf || '            begin'
            || v_lf || '                insert into v_perf_eds_agg('
            || v_lf || '                    minute_since_test_start'
            || v_lf || '                    ,evt_N_total_cnt'
            || v_lf || '                    ,evt_A_total_cnt'
            || v_lf || '                    ,evt_I_total_cnt'
            || v_lf || '                    ,evt_D_total_cnt'
            || v_lf || '                ) values ('
            || v_lf || '                     :v_minute_since_test_start'
            || v_lf || '                    ,iif(c.evt = ''N'', 1, 0 )'
            || v_lf || '                    ,iif(c.evt = ''A'', 1, 0 )'
            || v_lf || '                    ,iif(c.evt = ''I'', 1, 0 )'
            || v_lf || '                    ,iif(c.evt = ''D'', 1, 0 )'
            || v_lf || '                );'
        ;
        suspend;

        " " =  v_lf || '                v_ins_rows = v_ins_rows + 1;'
            || v_lf || '            end'
            || v_lf || '        else'
            || v_lf || '            v_upd_rows = v_upd_rows + 1;'
        ;
        suspend;


        if ( DBG_PRESERVE_PERF_EDS_ROWS = 0 ) then
            begin
                " " =  v_lf || '       delete from perf_eds_split_' || i
                    || v_lf || '       where current of c;'
                ;
                suspend;
            end
        else
            begin
                -- 4debug only: preserve rows rather than delete:
                " " =  v_lf || '       update perf_eds_split_' || i || ' set att = -abs(att), id = -abs(id)'
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
set term ;^
commit;

drop procedure tmp$sp$gen_trg_4_v_perf_eds;
commit;

-- #####################################################################################################################

set heading off;
set list on;

select 'set echo off;' as " "
from rdb$database
union all
select 'set list on; select ''oltp_adjust_eds_perf.sql finish at '' || current_timestamp as msg from rdb$database;' as " "
from rdb$database
;
commit;

-- ######################################
-- End of script oltp_adjust_eds_perf.sql
-- ######################################

