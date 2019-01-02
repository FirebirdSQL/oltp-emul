-- #################################################
-- Begin of script oltp30_common.sql (application units)
-- #################################################
-- 14.10.2018. File contains procedures which signatures and bodies are identical both in 2.5 and 3.0.
-- Most of procedures for REPORT purpuses are here.

-- Pattern for search queries to [v_]qdistr using regexp (in IBE):
-- (from|((left(( ){1,}outer( ){1,})|full(( ){1,}outer( ){1,})|inner)( ){0,1}){0,1}join)( ){1,}(v_){0,1}qdistr

set bail on;
set autoddl off;
set list on;
select 'oltp30_common.sql start at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

-------------------------------------------------------

create or alter view z_current_test_settings as
-- This view is used in 1run_oltp_emul.bat (.sh) to display current settings before test run.
-- Do NOT delete it!
select s.mcode as setting_name, s.svalue as setting_value, 'init' as stype
from settings s
where s.working_mode='INIT' and s.mcode = 'WORKING_MODE'

UNION ALL

select '--- Detalization for WORKING_MODE: ---' as setting_name, '' as setting_value, 'inf1' as stype
from rdb$database
UNION ALL

select '    ' || t.mcode as setting_name, t.svalue as setting_value, 'mode' as stype
from settings s
join settings t on s.svalue=t.working_mode
where s.working_mode='INIT' and s.mcode='WORKING_MODE'

UNION ALL

select '--- Main test settings: ---' as setting_name, '' as setting_value, 'inf2' as stype
from rdb$database
UNION ALL

select setting_name, setting_value, 'main' as stype
from (
    select '    ' || s.mcode as setting_name, s.svalue as setting_value
    from settings s
    where
        s.working_mode='COMMON'
        and s.mcode
            in (
                 'USED_IN_REPLICATION'
                ,'SEPARATE_WORKERS'
                ,'UNIT_SELECTION_METHOD'
                ,'BUILD_WITH_SPLIT_HEAVY_TABS'
                ,'BUILD_WITH_SEPAR_QDISTR_IDX'
                ,'BUILD_WITH_QD_COMPOUND_ORDR'
                ,'ENABLE_MON_QUERY'
                ,'MON_UNIT_LIST'
                ,'HALT_TEST_ON_ERRORS'
                ,'QMISM_VERIFY_BITSET'
                ,'ENABLE_RESERVES_WHEN_ADD_INVOICE'
               )
    order by setting_name
) x
;

--------------------------------------------------------------------------------

create or alter view z_settings_pivot as
-- vivid show of all workload settings (pivot rows to separate columns
-- for each important kind of setting). Currently selected workload mode
-- is marked by '*' and displayed in UPPER case, all other - in lower.
-- The change these settings open oltp_main_filling.sql and find EB
-- with 'v_insert_settings_statement' variable
select
    iif(s.working_mode=c.svalue,'* '||upper(s.working_mode), lower(s.working_mode) ) as working_mode
    ,cast(max( iif(mcode = upper('c_wares_max_id'), s.svalue, null ) ) as int) as wares_cnt
    ,cast(max( iif(mcode = upper('c_customer_doc_max_rows'), s.svalue, null ) ) as int) as cust_max_rows
    ,cast(max( iif(mcode = upper('c_supplier_doc_max_rows'), s.svalue, null ) ) as int) as supp_max_rows
    ,cast(max( iif(mcode = upper('c_customer_doc_max_qty'), s.svalue, null ) ) as int) as cust_max_qty
    ,cast(max( iif(mcode = upper('c_supplier_doc_max_qty'), s.svalue, null ) ) as int) as supp_max_qty
    ,cast(max( iif(mcode = upper('c_number_of_agents'), s.svalue, null ) ) as int) as agents_cnt
from settings s
left join (select s.svalue from settings s where s.mcode='working_mode') c on s.working_mode=c.svalue
where s.mcode
in (
     'c_wares_max_id'
    ,'c_customer_doc_max_rows'
    ,'c_supplier_doc_max_rows'
    ,'c_customer_doc_max_qty'
    ,'c_supplier_doc_max_qty'
    ,'c_number_of_agents'
)
group by s.working_mode, c.svalue
order by
    iif(s.working_mode starting with 'DEBUG',  0,
    iif(s.working_mode starting with 'SMALL',  1,
    iif(s.working_mode starting with 'MEDIUM', 2,
    iif(s.working_mode starting with 'LARGE',  3,
    iif(s.working_mode starting with 'HEAVY',  5,
    null) ) ) ) )
    nulls last
   ,s.working_mode
;

--------------------------------------------------------------------------------

create or alter view z_qd_indices_ddl as

-- This view is used in 1run_oltp_emulbat (.sh) to display current DDL of QDistr xor XQD* indices.
-- Do NOT delete it!

with recursive
r as (
    select
        ri.rdb$relation_name tab_name
        ,ri.rdb$index_name idx_name
        ,rs.rdb$field_name fld_name
        ,rs.rdb$field_position fld_pos
        ,cast( trim(rs.rdb$field_name) as varchar(512)) as idx_key
    from rdb$indices ri
    join rdb$index_segments rs using ( rdb$index_name )
    left join (
        select cast(t.svalue as int) as svalue
        from settings t
        where t.working_mode='COMMON' and t.mcode='BUILD_WITH_SPLIT_HEAVY_TABS'
    ) t on 1=1
    where
        rs.rdb$field_position = 0
        and (
            t.svalue = 0 and trim( ri.rdb$relation_name ) is not distinct from 'QDISTR'
            or
            t.svalue = 1 and trim( ri.rdb$relation_name ) starts with 'XQD_'
        )

    UNION ALL

    select
        r.tab_name
        ,r.idx_name
        ,rs.rdb$field_name
        ,rs.rdb$field_position
        ,r.idx_key || ',' || trim(rs.rdb$field_name) 
    from r
    join rdb$indices ri
        on r.idx_name = ri.rdb$index_name
    join rdb$index_segments rs
        on
            ri.rdb$index_name = rs.rdb$index_name
            and r.fld_pos +1 = rs.rdb$field_position
)
select r.tab_name, r.idx_name, max(r.idx_key) as idx_key
from r
group by r.tab_name, r.idx_name
;

--------------------------------------------------------------------------------

create or alter view z_halt_log as -- upd 28.09.2014
-- :: NB :: this view is only for DEBUG! 
-- One need to create index on perf_log.trn_id before usage of this view!
select p.id, p.fb_gdscode, p.unit, p.trn_id, p.dump_trn, p.att_id, p.exc_unit, p.info, p.ip, p.dts_beg, e.fb_mnemona, p.exc_info,p.stack
from perf_log p
join (
    select g.trn_id, g.fb_gdscode
    from perf_log g
    -- 335544558    check_constraint    Operation violates CHECK constraint @1 on view or table @2.
    -- 335544347    not_valid    Validation error for column @1, value "@2".
    -- if table has unique constraint: 335544665 unique_key_violation (violation of PRIMARY or UNIQUE KEY constraint "T1_XY" on table "T1")
    -- if table has only unique index: 335544349 no_dup (attempt to store duplicate value (visible to active transactions) in unique index "T2_XY")
    where g.fb_gdscode in (      0 -- 3.0 SC trouble, core-4565 (gdscode can come in when-section with value = 0!)
                                ,335544347, 335544558 -- not_valid or viol. of check constr.
                                ,335544665, 335544349 -- viol. of UNQ constraint or just unq. index (without binding to unq constr)
                                ,335544466 -- viol. of FOREIGN KEY constraint @1 on table @2
                                ,335544838 -- Foreign key reference target does not exist (when attempt to ins/upd in DETAIL table FK-field with value which doesn`t exists in PARENT)
                                ,335544839 -- Foreign key references are present for the record  (when attempt to upd/del in PARENT table PK-field and rows in DETAIL (no-cascaded!) exists for old value)
                          )
    group by 1,2
) g
on p.trn_id = g.trn_id
left join fb_errors e on p.fb_gdscode = e.fb_gdscode
order by p.id
;

------------------------------------------------------

commit;
set term ^;

create or alter procedure sys_get_fb_arch (
     a_connect_with_usr varchar(31) default 'SYSDBA'
    ,a_connect_with_pwd varchar(31) default 'masterkey'
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
    
    -- Aux SP for detect FB architecture.

    -- ::: NOTE ::: 
    -- This SP establishes new attachment using ES/EDS mechanism in order to detect whether FB works is Classic mode.
    -- If current FB instance does support connections pool then this additional attachment will exist after this SP 
    -- finish, i.e. it will be kept opened by engine. Despite that connections pool appeared only in 4.0, one of special 
    -- build of Firebird 2.5 also has it. This engine (2.5, special build) will leave such attachment alive even when
    -- its parent connection will be closed, moreover - even when LAST attachment will be gone. In order to kill all
    -- such attachments one need to issue: ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL (see this command in .bat and .sh),


    fb_arch = rdb$get_context('USER_SESSION', 'SERVER_MODE');

    if ( fb_arch is null ) then
    begin
        select a.mon$server_pid, a.mon$remote_protocol
        from mon$attachments a
        where a.mon$attachment_id = current_connection
        into cur_server_pid, att_protocol;

        if ( att_protocol is null ) then
            fb_arch = 'Embedded';
        else if ( upper(current_user) = upper('SYSDBA')
                  and rdb$get_context('SYSTEM','ENGINE_VERSION') NOT starting with '2.5' 
                  and exists(select * from mon$attachments a 
                             where a.mon$remote_protocol is null
                                   and upper(a.mon$user) in ( upper('Cache Writer'), upper('Garbage Collector'))
                            ) 
                ) then
            fb_arch = 'SuperServer';
        else
            begin
                v_test_sttm =
                    'select a.mon$server_pid + 0*(select 1 from rdb$database)'
                    ||' from mon$attachments a '
                    ||' where a.mon$attachment_id = current_connection';

                select i.mon$page_fetches
                from mon$io_stats i
                where i.mon$stat_group = 0  -- db_level
                into v_fetches_beg;
            
                execute statement v_test_sttm
                on external
                     'localhost:' || rdb$get_context('SYSTEM', 'DB_NAME')
                as
                     user a_connect_with_usr
                     password a_connect_with_pwd
                     role left('R' || replace(uuid_to_char(gen_uuid()),'-',''),31)
                into ext_server_pid;
            
                in autonomous transaction do
                select i.mon$page_fetches
                from mon$io_stats i
                where i.mon$stat_group = 0  -- db_level
                into v_fetches_end;
            
                fb_arch = iif( cur_server_pid is distinct from ext_server_pid, 
                               'Classic', 
                               iif( v_fetches_beg is not distinct from v_fetches_end, 
                                    'SuperClassic', 
                                    'SuperServer'
                                  ) 
                             );
            end

        fb_arch = trim(fb_arch) || ' ' || rdb$get_context('SYSTEM','ENGINE_VERSION');
        rdb$set_context('USER_SESSION', 'SERVER_MODE', fb_arch);
    end

    suspend;

end 

^ -- sys_get_fb_arch


create or alter procedure sys_timestamp_to_ansi (a_dts timestamp default 'now')
returns ( ansi_dts varchar(15) ) as
begin
    ansi_dts =
        cast(extract( year from a_dts)*10000 + extract(month from a_dts) * 100 + extract(day from a_dts) as char(8))
         || '_'
         || substring(cast(cast(1000000 + extract(hour from a_dts) * 10000 + extract(minute from a_dts) * 100 + extract(second from a_dts) as int) as char(7)) from 2);
    suspend;
end
^ -- sys_timestamp_to_ansi


create or alter procedure srv_get_last_launch_beg_end(
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
     last_launch_beg timestamp
    ,last_launch_end timestamp
) as

begin
    -- NB: STUB of this procedure was created before; now it is filled with actual code.
    -- Auxiliary SP: finds moments of start and finish business operations in perf_log
    -- on timestamp interval that is [L, N] where:
    -- "L" = latest from {-abs( :a_last_hours * 60 + :a_last_mins ), 'perf_watch_interval'}
    -- "N" = latest record in perf_log table

    select maxvalue( x.last_job_start_dts, y.last_job_finish_dts ) as last_job_start_dts
    from (
        select p.dts_beg as last_job_start_dts
        from perf_log p -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
        where p.unit = 'perf_watch_interval'
        order by dts_beg desc rows 1
        -- 14.10.2018 do NOT ever use decs index on dts_beg !!
        -- MUST BE: PLAN SORT (P INDEX (PERF_LOG_UNIT));
    ) x
    cross join
    (
        select dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to p.dts_beg) as last_job_finish_dts
        from business_ops b
        -- NB: unioned-view must be in RIGHT (driven) part of outer join if we want to involve indices of its tables!
        LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
            on p.unit=b.unit
        order by p.dts_beg desc
        rows 1
    ) y
    into last_launch_beg;

    select p.dts_end as report_end
    from business_ops b
    -- NB: unioned-view must be in RIGHT (driven) part of outer join if we want to involve indices of its tables!
    LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
        on p.unit=b.unit
    where
        p.dts_beg >= :last_launch_beg
        and p.dts_end is not null
    order by p.dts_beg desc
    rows 1
    into last_launch_end;

    suspend;

end

^ -- srv_get_last_launch_beg_end


create or alter procedure srv_mon_perf_total(
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
    business_action dm_info,
    job_beg varchar(16),
    job_end varchar(16),
    avg_times_per_minute numeric(12,2),
    avg_elapsed_ms int,
    successful_times_done int
)
as
    declare v_sort_prior int;
    declare v_overall_performance double precision;
    declare v_all_minutes int;
    declare v_last_job_start_dts timestamp;
    declare v_this dm_dbobj = 'srv_mon_perf_total';
begin
    -- MAIN SP for estimating performance: provides number of business operations
    -- per minute which were SUCCESSFULLY finished. Suggested by Alexey Kovyazin.

    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    -- reduce needed number of minutes from most last event of some SP starts:
    -- 18.07.2014: handle only data which belongs to LAST job.
    -- Record with p.unit = 'perf_watch_interval' is added in
    -- oltp_isql_run_worker.bat before FIRST isql will be launched
    -- for each mode ('sales', 'logist' etc)

    --#######################################################################################################################
    -- 13.10.2018: split complex queryL materializing its intermediate reults (poor performance when deal with unioned-view!)
    --#######################################################################################################################
    select maxvalue( x.last_job_start_dts, y.last_job_finish_dts ) as last_job_start_dts
    from (
        select p.dts_beg as last_job_start_dts
        from perf_log p -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
        where p.unit = 'perf_watch_interval'
        order by dts_beg desc rows 1
    ) x
    cross join
    (
        select dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to p.dts_beg) as last_job_finish_dts
        from business_ops b
        -- NB: unioned-view must be in RIGHT (driven) part of outer join if we want to involve indices of its tables!
        LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
            on p.unit=b.unit
        order by p.dts_beg desc
        rows 1
    ) y
    into v_last_job_start_dts; -- materialize intermediate result: save it in variable!


    delete from tmp$perf_log p  where p.stack = :v_this;

    insert into tmp$perf_log(
        unit
        ,info
        ,id
        ,dts_beg
        ,dts_end
        ,aux1
        ,aux2
        ,stack
    )
    with
    p as(
        select
            g.unit
            ,min( g.dts_beg ) report_beg
            ,max( g.dts_end  ) report_end
            ,count(*) successful_times_done
            ,avg(g.elapsed_ms) successful_avg_ms
        from business_ops p
        -- NB: unioned-view must be in RIGHT (driven) part of outer join if we want to involve indices of its tables!
        LEFT join v_perf_log g -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
            on p.unit=g.unit
        where
            -- 1) take in account only rows which are from THIS job!
            g.dts_beg >= :v_last_job_start_dts and
            -- 2) we must take in account only SUCCESSFULLY finished units, i.e. fb_gdscode is NULL.
            g.fb_gdscode + 0 -- 25.11.2015: suppress making bitmap for this index! almost 90% of rows contain NULL in this field.
            is null
        group by g.unit
    )
    select
        b.unit
        ,b.info
        ,b.sort_prior
        ,p.report_beg
        ,p.report_end
        ,p.successful_times_done
        ,p.successful_avg_ms
        ,:v_this
    from business_ops b
    left join p on b.unit = p.unit;
    -- tmp$perf_log(unit, info, id, dts_beg, dts_end, aux1, aux2, stack)

    -- total elapsed minutes and number of successfully finished SPs for ALL units:
    select nullif(datediff( minute from min_beg to max_end ),0),
           left(cast(min_beg as varchar(24)),16),
           left(cast(max_end as varchar(24)),16)
    from (
        select min(p.dts_beg) min_beg, max(p.dts_end) max_end
        from tmp$perf_log p
        where p.stack = :v_this
    )
    into v_all_minutes, job_beg, job_end;

    for
        select
             business_action
            ,avg_times_per_minute
            ,avg_elapsed_ms
            ,successful_times_done
            ,sort_prior
        from (
            select
                0 as sort_prior
                ,'*** OVERALL *** for '|| :v_all_minutes ||' minutes: ' as business_action -- 'Average ops/minute = '||:v_all_minutes||' ;'||(sum( aux1 ) / :v_all_minutes)  as business_action
                ,1.00*sum( aux1 ) / :v_all_minutes as avg_times_per_minute
                ,avg(aux2) as avg_elapsed_ms
                ,sum(aux1) as successful_times_done
            from tmp$perf_log p
            where p.stack = :v_this

            UNION ALL
            
            select
                 p.id as sort_prior
                ,p.info as business_action
                ,1.00 * aux1 / maxvalue( 1, datediff( minute from p.dts_beg to p.dts_end ) ) as avg_times_per_minute
                ,aux2 as avg_elapsed_ms
                ,aux1 as successful_times_done
            from tmp$perf_log p
            where p.stack = :v_this
        ) x
        order by x.sort_prior
        into
             business_action
            ,avg_times_per_minute
            ,avg_elapsed_ms
            ,successful_times_done
            ,v_sort_prior
    do begin
        if ( v_sort_prior = 0 ) then -- save value to be written into perf_log
            v_overall_performance = avg_times_per_minute;
        suspend;
    end

    delete from tmp$perf_log p  where p.stack = :v_this;

    begin
        -- 02.11.2015: save overall performance value so it can be used later:
        update perf_log p set aux1 = :v_overall_performance
        where p.unit = 'perf_watch_interval'
        order by dts_beg desc rows 1;
    when any do
        begin
            -- lock/update conflict can be here with another ISQL session with SID #1
            -- (running on other machine) that makes this report at the same time.
            -- We suppress this exception because this record will anyway contain
            -- value that we want to save.
        end
    end
    -- Statistics for database with size = 100 Gb and cleaned OS cache (LI-V3.0.0.32179):
    -- sync
    -- echo 3 > /proc/sys/vm/drop_caches
    -- 20 records fetched
    -- 600187 ms, 233041 read(s), 4 write(s), 3206400 fetch(es), 70 mark(s)
    --
    -- Table                             Natural     Index    Update    Insert    Delete
    -- ***********************************************************************************
    -- RDB$INDICES                                       9
    -- BUSINESS_OPS                           19        38
    -- PERF_LOG                                     369967         1
    -- TMP$PERF_LOG                           76                            19        19

end

^ -- srv_mon_perf_total

create or alter procedure srv_mon_perf_dynamic(
    a_intervals_number smallint default 20,
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
     business_action dm_info
    ,interval_no smallint
    ,cnt_ok_per_minute int
    ,cnt_all int
    ,cnt_ok int
    ,cnt_err int
    ,err_prc numeric(12,2)
    ,ok_avg_ms int
    ,interval_beg timestamp
    ,interval_end timestamp
)
as
    declare v_first_job_start_dts timestamp;
    declare v_last_job_finish_dts timestamp;
    declare v_sec_for_one_interval int;
    declare v_this dm_dbobj = 'srv_mon_perf_dynamic';
begin

    -- 15.09.2014 Get performance results 'in dynamic': split all job time to N
    -- intervals, where N is specified by 1st input argument.
    -- 03.09.2015 Removed cross join perf_log and CTE 'inp_args as i' because
    -- of inefficient plan. Input parameters are injected inside DT.
    -- See: http://www.sql.ru/forum/1173774/select-a-b-from-a-cross-b-order-by-indexed-field-of-a-rows-n-ignorit-rows-n-why

    a_intervals_number = iif( a_intervals_number <= 0, 20, a_intervals_number);
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    --#######################################################################################################################
    -- 13.10.2018: split complex queryL materializing its intermediate reults (poor performance when deal with unioned-view!)
    --#######################################################################################################################
    select
        a.first_job_start_dts
        ,a.last_job_finish_dts
        ,1+datediff(second from a.first_job_start_dts to a.last_job_finish_dts) / :a_intervals_number as sec_for_one_interval
    from (
        select
            maxvalue( x.last_added_watch_row_dts, y.first_measured_start_dts ) as first_job_start_dts
            ,y.last_job_finish_dts
            --,y.intervals_number
        from (
            -- reduce needed number of minutes from most last event of some SP starts:
            -- 18.07.2014: handle only data which belongs to LAST job.
            -- Record with p.unit = 'perf_watch_interval' is added in
            -- oltp_isql_run_worker.bat before FIRST isql will be launched
            select p.dts_beg as last_added_watch_row_dts
            from perf_log p
            where p.unit = 'perf_watch_interval'
            order by dts_beg desc rows 1
        ) x
        cross join
        (
            select
                dateadd( p.scan_bak_minutes minute to p.dts_beg) as first_measured_start_dts
                ,p.dts_beg as last_job_finish_dts
                --,:a_intervals_number as intervals_number
            from (
                select
                     p.*
                    ,-abs( :a_last_hours * 60 + :a_last_mins ) as scan_bak_minutes
                from business_ops b
                -- NB: unioned-view must be in RIGHT part of outer join if we want to involve indices of its tables!
                LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
                    on p.unit=b.unit
                order by p.dts_beg desc
                rows 1
            ) p
        ) y
    ) a
    into
        v_first_job_start_dts
        ,v_last_job_finish_dts
        ,v_sec_for_one_interval
    ;

    delete from tmp$perf_log p where p.stack = :v_this;
    insert into tmp$perf_log(
        unit
        ,info
        ,id        -- interval_no
        ,dts_beg   -- interval_beg
        ,dts_end   -- interval_end
        ,aux1      -- cnt_ok
        ,aux2       -- cnt_err
        ,elapsed_ms -- ok_avg_ms
        ,stack
    )
    with
    p as(
        select
            g.unit
            ,b.info
            ,1+cast(datediff(second from :v_first_job_start_dts to g.dts_beg) / :v_sec_for_one_interval as int) as interval_no
            ,count(*) cnt_all
            ,count( iif( g.fb_gdscode is null, 1, null ) ) cnt_ok
            ,count( iif( g.fb_gdscode is NOT null, 1, null ) ) cnt_err
            ,100.00 * count( nullif(g.fb_gdscode,0) ) / count(*) err_prc
            ,avg(  iif( g.fb_gdscode is null, g.elapsed_ms, null ) ) ok_avg_ms
        from business_ops b
        -- NB: unioned-view must be in RIGHT part of outer join if we want to involve indices of its tables!
        LEFT join v_perf_log g -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
            on b.unit=g.unit
        where
            -- 1) take in account only rows which are from THIS measured test run!
            g.dts_beg >= :v_first_job_start_dts
            -- do NOT! >>> and g.fb_gdscode + 0 is null -- we have to show count of FAILED transactions in this report
        group by 1,2,3
    )
    ,q as(
        select
            unit
            ,info
            ,interval_no
            ,dateadd( (interval_no-1) * :v_sec_for_one_interval + 1 second to :v_first_job_start_dts ) as interval_beg
            ,dateadd( interval_no * :v_sec_for_one_interval second to :v_first_job_start_dts ) as interval_end
            ,cnt_all
            ,cnt_ok
            ,cnt_err
            ,err_prc
            ,ok_avg_ms
        from p
    )
    --select * from q;
    select
        unit
        ,info
        ,interval_no
        ,interval_beg
        ,interval_end
        ,cnt_ok          -- aux1
        ,cnt_err         -- aux2
        ,ok_avg_ms
        ,:v_this
    from q;
    -----------------------------

    for
        select
             business_action
            ,interval_no
            ,cnt_ok_per_minute
            ,cnt_all
            ,cnt_ok
            ,cnt_err
            ,err_prc
            ,ok_avg_ms
            ,interval_beg
            ,interval_end
        from (
            select
                0 as sort_prior
                ,'interval #'||lpad(id, 4, ' ')||', overall' as business_action
                ,id as interval_no
                ,min(dts_beg) as interval_beg
                ,min(dts_end) as interval_end
                ,round(sum(aux1) / nullif(datediff(minute from min(dts_beg) to min(dts_end)),0), 0) cnt_ok_per_minute
                ,sum(aux1 + aux2) as cnt_all
                ,sum(aux1) as cnt_ok
                ,sum(aux2) as cnt_err
                ,100 * sum(aux2) / sum(aux1 + aux2) as err_prc
                ,cast(null as int) as ok_avg_ms
                --,avg(elapsed_ms) as ok_avg_ms
            from tmp$perf_log p
            where p.stack = :v_this
            group by id

            UNION ALL

            select
                1 as sort_prior
                ,info as business_action
                ,id as interval_no
                ,dts_beg as interval_beg
                ,dts_end as interval_end
                ,aux1 / nullif(datediff(minute from dts_beg to dts_end),0) cnt_ok_per_minute
                ,aux1 + aux2 as cnt_all
                ,aux1 as cnt_ok
                ,aux2 as cnt_err
                ,100 * aux2 / (aux1 + aux2) as err_prc
                ,elapsed_ms as ok_avg_ms
            from tmp$perf_log p
            where p.stack = :v_this
        )
        order by sort_prior, business_action, interval_no
    into
             business_action
            ,interval_no
            ,cnt_ok_per_minute
            ,cnt_all
            ,cnt_ok
            ,cnt_err
            ,err_prc
            ,ok_avg_ms
            ,interval_beg
            ,interval_end
    do suspend;
end
^ -- srv_mon_perf_dynamic

create or alter procedure srv_mon_perf_detailed (
    a_last_hours smallint default 3,
    a_last_mins smallint default 0,
    a_show_detl smallint default 0)
returns (
    unit type of dm_unit,
    cnt_all integer,
    cnt_ok integer,
    cnt_err integer,
    err_prc numeric(6,2),
    ok_min_ms integer,
    ok_max_ms integer,
    ok_avg_ms integer,
    cnt_lk_confl integer,
    cnt_user_exc integer,
    cnt_chk_viol integer,
    cnt_unq_viol integer,
    cnt_fk_viol integer,
    cnt_stack_trc integer, -- 335544842, 'stack_trace': appears at the TOP of stack in 3.0 SC (strange!)
    cnt_zero_gds integer,  -- 03.10.2014: core-4565 (gdscode=0 in when-section! 3.0 SC only)
    cnt_other_exc integer,
    job_beg varchar(16),
    job_end varchar(16)
)
as
    declare v_report_beg timestamp;
    declare v_report_end timestamp;
begin
    -- SP for detailed performance analysis: count of operations
    -- (NOT only business ops; including BOTH successful and failed ones),
    -- count of errors (including by their types)
    a_last_hours = abs( coalesce(a_last_hours, 3) );
    a_last_mins = coalesce(a_last_mins, 0);
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    -- reduce needed number of minutes from most last event of some SP starts:
    -- 18.07.2014: handle only data which belongs to LAST job.
    -- Record with p.unit = 'perf_watch_interval' is added in
    -- oltp_isql_run_worker.bat before FIRST isql will be launched
    -- for each mode ('sales', 'logist' etc)

    -- 13.10.2018: split complex query for materializing its intermediate reults (poor performance when deal with unioned-view!)
    select
        a.first_job_start_dts
        ,a.last_job_finish_dts
    from (
        select
            maxvalue( x.last_added_watch_row_dts, y.first_measured_start_dts ) as first_job_start_dts
            ,y.last_job_finish_dts
            --,y.intervals_number
        from (
            -- reduce needed number of minutes from most last event of some SP starts:
            -- 18.07.2014: handle only data which belongs to LAST job.
            -- Record with p.unit = 'perf_watch_interval' is added in
            -- oltp_isql_run_worker.bat before FIRST isql will be launched
            select p.dts_beg as last_added_watch_row_dts
            from perf_log p
            where p.unit = 'perf_watch_interval'
            order by dts_beg desc rows 1
        ) x
        cross join
        (
            select
                dateadd( p.scan_bak_minutes minute to p.dts_beg) as first_measured_start_dts
                ,p.dts_beg as last_job_finish_dts
                --,:a_intervals_number as intervals_number
            from (
                select
                     p.*
                    ,-abs( :a_last_hours * 60 + :a_last_mins ) as scan_bak_minutes
                from business_ops b
                -- NB: unioned-view must be in RIGHT part of outer join if we want to involve indices of its tables!
                LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
                    on p.unit=b.unit
                order by p.dts_beg desc
                rows 1
            ) p
        ) y
    ) a
    into
        v_report_beg
        ,v_report_end
    ;


    delete from tmp$perf_mon where 1=1;

    insert into tmp$perf_mon(
         rollup_level
        ,dts_beg                    --  1
        ,dts_end
        ,unit
        ,cnt_all
        ,cnt_ok                     --  5
        ,cnt_err
        ,err_prc
        ,ok_min_ms
        ,ok_max_ms
        ,ok_avg_ms                  -- 10
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_fk_viol
        ,cnt_lk_confl
        ,cnt_user_exc               -- 15
        ,cnt_stack_trc
        ,cnt_zero_gds
        ,cnt_other_exc
    )
    with
    c as (
        select
             pg.unit
            ,count(*) cnt_all
            ,count( iif( nullif(pg.fb_gdscode,0) is null, 1, null) ) cnt_ok                -- 5
            ,count( nullif(pg.fb_gdscode,0) ) cnt_err
            ,100.00 * count( nullif(pg.fb_gdscode,0) ) / count(*) err_prc
            ,min( iif( nullif(pg.fb_gdscode,0) is null, pg.elapsed_ms, null) ) ok_min_ms
            ,max( iif( nullif(pg.fb_gdscode,0) is null, pg.elapsed_ms, null) ) ok_max_ms
            ,avg( iif( nullif(pg.fb_gdscode,0) is null, pg.elapsed_ms, null) ) ok_avg_ms
            ,count( iif(pg.fb_gdscode in( 335544347, 335544558 ), 1, null ) ) cnt_chk_viol    -- 10
            ,count( iif(pg.fb_gdscode in( 335544665, 335544349 ), 1, null ) ) cnt_unq_viol
            ,count( iif(pg.fb_gdscode in( 335544466, 335544838, 335544839 ), 1, null ) ) cnt_fk_viol
            ,count( iif(pg.fb_gdscode in( 335544345, 335544878, 335544336, 335544451 ), 1, null ) ) cnt_lk_confl
            ,count( iif(pg.fb_gdscode = 335544517, 1, null) ) cnt_user_exc
            ,count( iif(pg.fb_gdscode = 335544842, 1, null) ) cnt_stack_trc                 -- 15
            ,count( iif(pg.fb_gdscode = 0, 1, null) ) cnt_zero_gds
            ,count( iif( pg.fb_gdscode
                         in (
                                335544347, 335544558,
                                335544665, 335544349,
                                335544466, 335544838, 335544839,
                                335544345, 335544878, 335544336, 335544451,
                                335544517,
                                335544842,
                                0
                            )
                          ,null
                          ,pg.fb_gdscode
                       )
                   ) cnt_other_exc
        from v_perf_log pg
        where
            pg.dts_beg between :v_report_beg and :v_report_end and
            pg.elapsed_ms >= 0 and  -- 24.09.2014: prevent from display in result 'sp_halt_on_error', 'perf_watch_interval' and so on
            pg.unit not starting with 'srv_recalc_idx_stat_' -- not interesting about time that was spent for reindxing of some table
        group by
            pg.unit
    )
    select 
        null ----------------- rollup_level
       ,:v_report_beg
       ,:v_report_end
       ,c.*
    from c;

    insert into tmp$perf_mon(
         rollup_level
        ,unit
        ,cnt_all
        ,cnt_ok
        ,cnt_err
        ,err_prc
        ,ok_min_ms
        ,ok_max_ms
        ,ok_avg_ms
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_fk_viol
        ,cnt_lk_confl
        ,cnt_user_exc
        ,cnt_stack_trc
        ,cnt_zero_gds
        ,cnt_other_exc
        ,dts_beg
        ,dts_end
    )
    select
         1
        ,unit
        ,sum(cnt_all)
        ,sum(cnt_ok)
        ,sum(cnt_err)
        ,100.00 * sum(cnt_err) / sum(cnt_all)
        ,min(ok_min_ms)
        ,max(ok_max_ms)
        ,max(ok_avg_ms)
        ,sum( cnt_chk_viol ) cnt_chk_viol
        ,sum( cnt_unq_viol ) cnt_unq_viol
        ,sum( cnt_fk_viol ) cnt_fk_viol
        ,sum( cnt_lk_confl ) cnt_lk_confl
        ,sum( cnt_user_exc ) cnt_user_exc
        ,sum( cnt_stack_trc ) cnt_stack_trc
        ,sum( cnt_zero_gds ) cnt_zero_gds
        ,sum( cnt_other_exc ) cnt_other_exc
        ,max( dts_beg )
        ,max( dts_end )
    from tmp$perf_mon
    group by unit; -- overall totals

    if ( :a_show_detl = 0 ) then
        delete from tmp$perf_mon m where m.rollup_level is null;

    -- final resultset (with overall totals first):
    for
        select
            unit, cnt_all, cnt_ok, cnt_err, err_prc, ok_min_ms, ok_max_ms, ok_avg_ms
            ,cnt_chk_viol
            ,cnt_unq_viol
            ,cnt_fk_viol
            ,cnt_lk_confl
            ,cnt_user_exc
            ,cnt_stack_trc
            ,cnt_zero_gds
            ,cnt_other_exc
            ,left(cast(dts_beg as varchar(24)),16)
            ,left(cast(dts_end as varchar(24)),16)
        from tmp$perf_mon
        --order by dy desc nulls first,hr desc, unit
    into unit, cnt_all, cnt_ok, cnt_err, err_prc, ok_min_ms, ok_max_ms, ok_avg_ms
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_fk_viol
        ,cnt_lk_confl
        ,cnt_user_exc
        ,cnt_stack_trc
        ,cnt_zero_gds
        ,cnt_other_exc
        ,job_beg
        ,job_end
    do
        suspend;

end

^ -- srv_mon_perf_detailed

create or alter procedure srv_mon_business_perf_with_exc (
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
    info dm_info,
    unit dm_unit,
    cnt_all integer,
    cnt_ok integer,
    cnt_err integer,
    err_prc numeric(6,2),
    cnt_chk_viol integer,
    cnt_unq_viol integer,
    cnt_lk_confl integer,
    cnt_user_exc integer,
    cnt_other_exc integer,
    job_beg varchar(16),
    job_end varchar(16)
)
AS
declare v_dummy int;
begin

    a_last_hours = abs( coalesce(a_last_hours, 3) );
    a_last_mins = coalesce(a_last_mins, 0);
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    delete from tmp$perf_mon where 1=1; -- will be fulfilled in SP srv_mon_perf_detailed

    select count(*) from srv_mon_perf_detailed(:a_last_hours, :a_last_mins, 0) into v_dummy;
    
    -- result: tmp$perf_mon is fulfilled now with aggregated result of query:
    -- select sum(...), sum(...) from v_perf_log pg where <timestamp filter> group by pg.unit


    for
        select
             o.info,s.unit, s.cnt_all, s.cnt_ok,s.cnt_err,s.err_prc
            ,s.cnt_chk_viol
            ,s.cnt_unq_viol
            ,s.cnt_lk_confl
            ,s.cnt_user_exc
            ,s.cnt_other_exc
            ,left(cast(s.dts_beg as varchar(24)),16)
            ,left(cast(s.dts_end as varchar(24)),16)
        from business_ops o
        left join tmp$perf_mon s on o.unit=s.unit
        order by o.sort_prior
    into
        info
        ,unit
        ,cnt_all
        ,cnt_ok
        ,cnt_err
        ,err_prc
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_lk_confl
        ,cnt_user_exc
        ,cnt_other_exc
        ,job_beg
        ,job_end
    do
        suspend;

end

^ -- srv_mon_business_perf_with_exc

create or alter procedure srv_mon_exceptions(
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
    fb_gdscode int,
    fb_mnemona type of column fb_errors.fb_mnemona,
    unit type of dm_unit,
    cnt int,
    dts_min timestamp,
    dts_max timestamp
)
as
    declare v_last_job_start_dts timestamp;
begin
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    -- reduce needed number of minutes from most last event of some SP starts:
    -- 18.07.2014: handle only data which belongs to LAST job.
    -- Record with p.unit = 'perf_watch_interval' is added in
    -- oltp_isql_run_worker.bat before FIRST isql will be launched
    -- for each mode ('sales', 'logist' etc)

    --#######################################################################################################################
    -- 13.10.2018: split complex queryL materializing its intermediate reults (poor performance when deal with unioned-view!)
    --#######################################################################################################################
    select maxvalue( x.last_job_start_dts, y.last_job_finish_dts ) as last_job_start_dts
    from (
        select p.dts_beg as last_job_start_dts
        from perf_log p -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
        where p.unit = 'perf_watch_interval'
        order by dts_beg desc rows 1
    ) x
    cross join
    (
        select dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to p.dts_beg) as last_job_finish_dts
        from business_ops b
        -- NB: unioned-view must be in RIGHT (driven) part of outer join if we want to involve indices of its tables!
        LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
            on p.unit=b.unit
        order by p.dts_beg desc
        rows 1
    ) y
    into v_last_job_start_dts; -- materialize intermediate result: save it in variable!

    for
        select p.fb_gdscode, e.fb_mnemona, p.unit, count(*) cnt, min(p.dts_beg) dts_min, max(p.dts_beg) dts_max
        from v_perf_log p
        LEFT -- ::: NB ::: some exceptions can missing in fb_errors when it becomes obsolete
            join fb_errors e on p.fb_gdscode = e.fb_gdscode
        where
            p.dts_beg >= :v_last_job_start_dts
            and p.fb_gdscode > 0
            and p.exc_unit='#' -- 10.01.2015, see sp_add_to_abend_log: take in account only those units where exception occured, and skip callers of them
        group by 1,2,3
    into
       fb_gdscode, fb_mnemona, unit, cnt, dts_min, dts_max
    do
        suspend;
end

^ -- srv_mon_exceptions

create or alter procedure srv_mon_perf_trace (
    a_intervals_number smallint default 20,
    a_last_hours smallint default 3,
    a_last_mins smallint default 0
)
returns (
    unit dm_unit
    ,info dm_info
    ,interval_no smallint
    ,cnt_success int
    ,fetches_per_second int
    ,marks_per_second int
    ,reads_to_fetches_prc numeric(6,2)
    ,writes_to_marks_prc numeric(6,2)
    ,interval_beg timestamp
    ,interval_end timestamp
) as
begin

    -- Report based on result of parsing TRACE log which was started by
    -- ISQL session #1 when config parameter trc_unit_perf = 1.
    -- Data for each business operation are displayed separately because
    -- they depends on execution plans and can not be compared each other.
    -- We have to analyze only RATIOS between reads/fetches and writes/marks,
    -- and also values of speed (fetches and marks per second) instead of
    -- absolute their values.

    a_intervals_number = iif( a_intervals_number <= 0, 20, a_intervals_number);
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    for
        with
        a as(
            -- reduce needed number of minutes from most last event of some SP starts:
            -- 18.07.2014: handle only data which belongs to LAST job.
            -- Record with p.unit = 'perf_watch_interval' is added in
            -- oltp_isql_run_worker.bat before FIRST isql will be launched
            select
                maxvalue( x.last_added_watch_row_dts, y.first_measured_start_dts ) as first_job_start_dts
                ,y.last_job_finish_dts
                ,y.intervals_number
            from (
                select p.dts_beg as last_added_watch_row_dts
                from perf_log p
                where p.unit = 'perf_watch_interval'
                order by dts_beg desc rows 1
            ) x
            cross join 
            (
                select
                    dateadd( p.scan_bak_minutes minute to p.dts_beg) as first_measured_start_dts
                    ,p.dts_beg as last_job_finish_dts
                    ,p.intervals_number
                from
                ( -- since 03.09.2015:
                    select
                        p.*
                        , -abs( :a_last_hours * 60 + :a_last_mins ) as scan_bak_minutes
                        , :a_intervals_number as intervals_number
                    from business_ops b
                    LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
                        on p.unit=b.unit
                    order by p.dts_beg desc
                    rows 1
                ) p
            ) y
        )
        ,d as(
            select
                a.first_job_start_dts
                ,a.last_job_finish_dts
                ,1+datediff(second from a.first_job_start_dts to a.last_job_finish_dts) / a.intervals_number as sec_for_one_interval
            from a
        )
        --select * from d
        ,p as(
            select
                t.unit
                ,b.info
                ,1+cast(datediff(second from d.first_job_start_dts to t.dts_end) / d.sec_for_one_interval as int) as interval_no
                ,count(*) cnt_success
                ,avg( 1000 * t.fetches / nullif(t.elapsed_ms,0) ) fetches_per_second
                ,avg( 1000 * t.marks / nullif(t.elapsed_ms,0) ) marks_per_second
                ,avg( 100.00 * t.reads/nullif(t.fetches,0) ) reads_to_fetches_prc
                ,avg( 100.00 * t.writes/nullif(t.marks,0) ) writes_to_marks_prc
                --,count( nullif(t.success,0) ) cnt_ok
                --,count( nullif(t.success,1) ) cnt_err
                --,100.00 * count( nullif(t.success,1) ) / count(*) err_prc
                --,avg(  iif( g.fb_gdscode is null, g.elapsed_ms, null ) ) ok_avg_ms
                ,min(d.first_job_start_dts) as first_job_start_dts
                ,min(d.sec_for_one_interval) as sec_for_one_interval
            from trace_stat t
            join business_ops b on t.unit = b.unit
            join d on t.dts_end between d.first_job_start_dts and d.last_job_finish_dts -- only rows which are from THIS measured test run!
            where t.success = 1
            group by 1,2,3
        )
        --select * from p
        ,q as (
            select
                unit
                ,info
                ,interval_no
                ,cnt_success
                ,fetches_per_second
                ,marks_per_second
                ,reads_to_fetches_prc
                ,writes_to_marks_prc
                ,first_job_start_dts
                ,sec_for_one_interval
                ,dateadd( (interval_no-1) * sec_for_one_interval+1 second to first_job_start_dts ) as interval_beg
                ,dateadd( interval_no * sec_for_one_interval second to first_job_start_dts ) as interval_end
            from p
        )
         --select * from q
        select
            unit
            ,info
            ,interval_no
            ,cnt_success
            ,fetches_per_second
            ,marks_per_second
            ,reads_to_fetches_prc
            ,writes_to_marks_prc
            ,interval_beg
            ,interval_end
        from q
        into
            unit
            ,info
            ,interval_no
            ,cnt_success
            ,fetches_per_second
            ,marks_per_second
            ,reads_to_fetches_prc
            ,writes_to_marks_prc
            ,interval_beg
            ,interval_end
    do
        suspend;
end

^ -- srv_mon_perf_trace

create or alter procedure srv_mon_perf_trace_pivot (
    a_intervals_number smallint default 20,
    a_last_hours smallint default 3,
    a_last_mins smallint default 0
)
returns (
    traced_data varchar(30),
    interval_no smallint,
    sp_client_order bigint,
    sp_cancel_client_order bigint,
    sp_supplier_order bigint,
    sp_cancel_supplier_order bigint,
    sp_supplier_invoice bigint,
    sp_cancel_supplier_invoice bigint,
    sp_add_invoice_to_stock bigint,
    sp_cancel_adding_invoice bigint,
    sp_customer_reserve bigint,
    sp_cancel_customer_reserve bigint,
    sp_reserve_write_off bigint,
    sp_cancel_write_off bigint,
    sp_pay_from_customer bigint,
    sp_cancel_pay_from_customer bigint,
    sp_pay_to_supplier bigint,
    sp_cancel_pay_to_supplier bigint,
    srv_make_invnt_saldo bigint,
    srv_make_money_saldo bigint,
    srv_recalc_idx_stat bigint,
    interval_beg timestamp,
    interval_end  timestamp
) as
begin

    -- ::: NB ::: This SP is called from temply created .sql in oltp_isql_run_worker.bat 

    -- Report based on result of parsing TRACE log which was started by
    -- ISQL session #1 when config parameter trc_unit_perf = 1.
    -- Data for each business operation are displayed separately because
    -- they depends on execution plans and can not be compared each other.
    -- We have to analyze only RATIOS between reads/fetches and writes/marks,
    -- and also values of speed (fetches and marks per second) instead of
    -- absolute their values.

    a_intervals_number = iif( a_intervals_number <= 0, 20, a_intervals_number);
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    for
        with recursive
        a as(
            -- reduce needed number of minutes from most last event of some SP starts:
            -- 18.07.2014: handle only data which belongs to LAST job.
            -- Record with p.unit = 'perf_watch_interval' is added in
            -- oltp_isql_run_worker.bat before FIRST isql will be launched
            select
                maxvalue( x.last_added_watch_row_dts, y.first_trace_start_dts ) as first_job_start_dts
                ,y.last_job_finish_dts
                ,y.intervals_number
            from (
                select p.dts_beg as last_added_watch_row_dts
                from perf_log p
                where p.unit = 'perf_watch_interval'
                order by dts_beg desc rows 1
            ) x
            cross join
            (
                select
                    dateadd( p.scan_bak_minutes minute to p.dts_beg) as first_trace_start_dts
                    ,p.dts_beg as last_job_finish_dts
                    ,p.intervals_number
                from
                ( -- since 03.09.2015:
                    select
                        p.*
                        , -abs( :a_last_hours * 60 + :a_last_mins ) as scan_bak_minutes
                        , :a_intervals_number as intervals_number
                    from business_ops b
                    LEFT join v_perf_log p -- 13.10.2018: replaced "perf_log" (table) with "v_perf_log" (view)
                        on p.unit=b.unit
                    order by p.dts_beg desc
                    rows 1
                ) p
            ) y
        )
        ,d as(
            select
                a.first_job_start_dts
                ,a.last_job_finish_dts
                ,1+datediff(second from a.first_job_start_dts to a.last_job_finish_dts) / a.intervals_number as sec_for_one_interval
            from a
        )
        --select * from d
        ,p as(
            select
                t.unit
                ,b.info
                ,1+cast(datediff(second from d.first_job_start_dts to t.dts_end) / d.sec_for_one_interval as int) as interval_no
                ,count(*) cnt_success
                ,avg( 1000 * t.fetches / nullif(t.elapsed_ms,0) ) fetches_per_second
                ,avg( 1000 * t.marks / nullif(t.elapsed_ms,0) ) marks_per_second
                ,avg( 100.00 * t.reads/nullif(t.fetches,0) ) reads_to_fetches_prc
                ,avg( 100.00 * t.writes/nullif(t.marks,0) ) writes_to_marks_prc
                --,count( nullif(t.success,0) ) cnt_ok
                --,count( nullif(t.success,1) ) cnt_err
                --,100.00 * count( nullif(t.success,1) ) / count(*) err_prc
                --,avg(  iif( g.fb_gdscode is null, g.elapsed_ms, null ) ) ok_avg_ms
                ,min(d.first_job_start_dts) as first_job_start_dts
                ,min(d.sec_for_one_interval) as sec_for_one_interval
            from trace_stat t
            join business_ops b on t.unit = b.unit
            join d on t.dts_end between d.first_job_start_dts and d.last_job_finish_dts -- only rows which are from trace sessions that relate to THIS test run!
            where t.success = 1
            group by 1,2,3
        )
        --select * from p
        ,q as (
            select
                unit
                ,info
                ,interval_no
                ,cnt_success
                ,fetches_per_second
                ,marks_per_second
                ,reads_to_fetches_prc
                ,writes_to_marks_prc
                ,first_job_start_dts
                ,sec_for_one_interval
                ,dateadd( (interval_no-1) * sec_for_one_interval+1 second to first_job_start_dts ) as interval_beg
                ,dateadd( interval_no * sec_for_one_interval second to first_job_start_dts ) as interval_end
            from p
        )
         --select * from q
        , n as (
          select 1 i from rdb$database union all
          select n.i+1 from n where n.i+1<=4
        )

        select
            decode(n.i, 1, 'fetches per second', 2, 'marks per second', 3, 'reads/fetches*100', 'writes/marks*100') as trace_stat
            ,interval_no
            ,max( iif(unit='sp_client_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as                  sp_client_order
            ,max( iif(unit='sp_cancel_client_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as           sp_cancel_client_order
            ,max( iif(unit='sp_supplier_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as                sp_supplier_order
            ,max( iif(unit='sp_cancel_supplier_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as         sp_cancel_supplier_order
            ,max( iif(unit='sp_supplier_invoice', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              sp_supplier_invoice
            ,max( iif(unit='sp_cancel_supplier_invoice', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as       sp_cancel_supplier_invoice
            ,max( iif(unit='sp_add_invoice_to_stock', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as          sp_add_invoice_to_stock
            ,max( iif(unit='sp_cancel_adding_invoice', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as         sp_cancel_adding_invoice
            ,max( iif(unit='sp_customer_reserve', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              sp_customer_reserve
            ,max( iif(unit='sp_cancel_customer_reserve', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as       sp_cancel_customer_reserve
            ,max( iif(unit='sp_reserve_write_off', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             sp_reserve_write_off
            ,max( iif(unit='sp_cancel_write_off', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              sp_cancel_write_off
            ,max( iif(unit='sp_pay_from_customer', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             sp_pay_from_customer
            ,max( iif(unit='sp_cancel_pay_from_customer', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as      sp_cancel_pay_from_customer
            ,max( iif(unit='sp_pay_to_supplier', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as               sp_pay_to_supplier
            ,max( iif(unit='sp_cancel_pay_to_supplier', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as        sp_cancel_pay_to_supplier
            ,max( iif(unit='srv_make_invnt_saldo', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             srv_make_invnt_saldo
            ,max( iif(unit='srv_make_money_saldo', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             srv_make_money_saldo
            ,max( iif(unit='srv_recalc_idx_stat', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              srv_recalc_idx_stat
            ,interval_beg
            ,interval_end
        from q
        cross join n
        group by n.i, interval_no, interval_beg, interval_end
        into
            traced_data
            ,interval_no
            ,sp_client_order
            ,sp_cancel_client_order
            ,sp_supplier_order
            ,sp_cancel_supplier_order
            ,sp_supplier_invoice
            ,sp_cancel_supplier_invoice
            ,sp_add_invoice_to_stock
            ,sp_cancel_adding_invoice
            ,sp_customer_reserve
            ,sp_cancel_customer_reserve
            ,sp_reserve_write_off
            ,sp_cancel_write_off
            ,sp_pay_from_customer
            ,sp_cancel_pay_from_customer
            ,sp_pay_to_supplier
            ,sp_cancel_pay_to_supplier
            ,srv_make_invnt_saldo
            ,srv_make_money_saldo
            ,srv_recalc_idx_stat
            ,interval_beg
            ,interval_end
    do
        suspend;
end

^ -- srv_mon_perf_trace_pivot


create or alter procedure srv_mon_idx
returns (
    tab_name dm_dbobj,
    idx_name dm_dbobj,
    last_stat double precision,
    curr_stat double precision,
    diff_stat double precision,
    last_done timestamp
) as
    declare v_last_recalc_trn bigint;
begin
    -- 13.10.2018: it seems that this SP is not called from anywhere, including .bat/.sh scripts.
    select p.trn_id
    from perf_log p
    where p.unit starting with 'srv_recalc_idx_stat_'
    order by p.trn_id desc rows 1
    into v_last_recalc_trn;

    -- SP for analyzing results of index statistics recalculation:
    -- ###########################################################
    for
        select
            t.tab_name
            ,t.idx_name
            ,t.last_stat
            ,r.rdb$statistics
            ,t.last_stat - r.rdb$statistics
            ,t.last_done
        from (
            select
                g.info as tab_name
                ,substring(g.unit from char_length('srv_recalc_idx_stat_')+1 ) as idx_name
                ,g.aux1 as last_stat
                ,g.dts_end as last_done
            from perf_log g
            where g.trn_id = :v_last_recalc_trn
        ) t
        join rdb$indices r on t.idx_name = r.rdb$index_name
    into
        tab_name,
        idx_name,
        last_stat,
        curr_stat,
        diff_stat,
        last_done
    do suspend;
end

^ -- srv_mon_idx

create or alter procedure srv_get_page_cache_info
returns (
    page_cache_info dm_info
) as
begin
   
    -- ::: NB ::: This SP is called from .bat / .sh only
    -- 02.01.2019. Called only when config parameter 'mon_unit_perf' is 2: report about memory consumption
    -- by metadata cache size, active attachments and statements in 'running' and 'stalled' state.
    -- NB: all records from table 'mon_cache_memory' are DELETED before every new test run, see 1run_oltp_emul.bat/.sh

    for
        select
            'Page cache type: ' || trim(pg_cache_type)
            || ', buffers: ' || m.pg_buffers || ' ' || trim(iif( pg_cache_type containing 'shared', ' for all connections', ' per each connection'))
            || ', with total size: ' || m.page_cache_size
        from mon_cache_memory m
        order by m.dts desc
        rows 1
    into
        page_cache_info
    do
        suspend;
end
^ -- srv_get_page_cache_info

create or alter procedure srv_mon_cache_dynamic
returns (
     measurement_timestamp timestamp
    ,measurement_elapsed_ms int
    ,page_cache_memo_used bigint
    ,metadata_cache_memo_used bigint
    ,metadata_cache_percent_of_total numeric(5,3)
    ,total_attachments_cnt int
    ,active_attachments_cnt int
    ,running_statements_cnt int -- page_cache_operating_stm_cnt
    ,stalled_statements_cnt int -- data_transfer_paused_stm_cnt
    ,memo_used_by_attachments bigint
    ,memo_used_by_transactions bigint
    ,memo_used_by_statements bigint
) as
begin

    -- 02.01.2019. Called only when config parameter 'mon_unit_perf' is 2: report about memory consumption
    -- by metadata cache size, active attachments and statements in 'running' and 'stalled' state.
    -- NB: all records from table 'mon_cache_memory' are DELETED before every new test run, see 1run_oltp_emul.bat/.sh

    for
        select
            m.dts
            ,m.elap_ms
            ,m.page_cache_size
            ,m.meta_cache_size
            ,100.000 * m.meta_cache_size / (m.meta_cache_size + m.page_cache_size)
            ,m.total_attachments_cnt
            ,m.active_attachments_cnt
            ,m.page_cache_operating_stm_cnt
            ,m.data_transfer_paused_stm_cnt
            ,m.memo_used_att
            ,m.memo_used_trn
            ,m.memo_used_stm
        from mon_cache_memory m
        order by m.id
    into
         measurement_timestamp
        ,measurement_elapsed_ms
        ,page_cache_memo_used
        ,metadata_cache_memo_used
        ,metadata_cache_percent_of_total
        ,total_attachments_cnt
        ,active_attachments_cnt
        ,running_statements_cnt -- page_cache_operating_stm_cnt
        ,stalled_statements_cnt -- data_transfer_paused_stm_cnt
        ,memo_used_by_attachments
        ,memo_used_by_transactions
        ,memo_used_by_statements
    do
        suspend;
end
^ -- srv_mon_cache_dynamic

--############################################
create or alter procedure srv_get_report_name(
     a_format varchar(20) default 'regular' -- 'regular' | 'benchmark'
    ,a_build varchar(50) default '' -- WI-V3.0.0.32136 or just '32136'
    ,a_num_of_sessions int default -1
    ,a_test_time_minutes int default -1
    ,a_prefix varchar(255) default ''
    ,a_suffix varchar(255) default ''
) returns (
    report_file varchar(255) -- full name of final report
    ,start_at varchar(15) -- '20150223_1527': timestamp of test_time phase start
    ,fb_arch varchar(50) -- 'ss30' | 'sc30' | 'cs30'
    ,overall_perf varchar(50) -- 'score_07548'
    ,fw_setting varchar(20) -- 'fw__on' | 'fw_off'
    ,load_time varchar(50) -- '03h00m'
    ,load_att varchar(50) -- '150_att'
    ,heavy_load_ddl varchar(50) -- only when a_format='benchmark': solid' | 'split'
    ,compound_1st_col varchar(50) -- only when a_format='benchmark': 'most__selective_1st' | 'least_selective_1st'
    ,compound_idx_num varchar(50) -- only when a_format='benchmark': 'one_index' | 'two_indxs'
)
as
    declare v_test_finish_state varchar(50);
    declare v_tab_name dm_dbobj;
    declare v_min_idx_key varchar(255);
    declare v_max_idx_key varchar(255);
    declare v_test_time int;
    declare v_num_of_sessions int;
    declare v_dts_beg timestamp;
    declare k smallint;
    declare v_fb_major_vers varchar(10);
    declare v_sep_workers varchar(50) = 'sep_UNKNOWN';
    declare v_unit_select varchar(50) = 'uns_UNKNOWN';
    declare v_repl_involv varchar(50) = 'rpl_UNKNOWN';
begin

    -- Aux. SP for returning FILE NAME of final report which does contain all
    -- significant FB, database and test params
    -- Sample:
    -- select * from srv_get_report_name('regular', 31236)
    -- select * from srv_get_report_name('benchmark', 31236)

    select d1 || d2
    from (
        select d1, left(s, position('.' in s)-1) d2
        from (
            select left(r,  position('.' in r)-1) d1, substring(r from 1+position('.' in r)) s
            from (
              select rdb$get_context('SYSTEM','ENGINE_VERSION') r from rdb$database
            )
        )
    ) into v_fb_major_vers; -- '2.5.0' ==> '25'; '3.0.0' ==> '30'; '19.17.1' ==> '1917' :-)

    select p.fb_arch from sys_get_fb_arch p into fb_arch;
    fb_arch =
        iif( fb_arch containing 'superserver' or upper(fb_arch) starting with upper('ss'), 'ss'
            ,iif( fb_arch containing 'superclassic' or upper(fb_arch) starting with upper('sc'), 'sc'
                ,iif( fb_arch containing 'classic' or upper(fb_arch) starting with upper('cs'), 'cs'
                    ,'fb'
                    )
                )
           )
        || v_fb_major_vers -- prev: iif( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.5', '25', '30' )
    ;
    fw_setting='fw' || iif( (select mon$forced_writes from mon$database)= 1,'__on','_off');

    select
         max(iif( mcode='SEPARATE_WORKERS',            iif( svalue=1,             'sepw_1',     'sepw_0'), null ))
        ,max(iif( mcode='UNIT_SELECTION_METHOD',       iif( svalue = 'random',    'rndUnitSel', 'predictSel' ), null ))
        ,max(iif( mcode='USED_IN_REPLICATION',         iif( svalue=1,             'repl_1',     'repl_0' ), null ))
    from (
        select s.mcode, s.svalue
        from settings s
        where s.mcode in ( 'SEPARATE_WORKERS', 'UNIT_SELECTION_METHOD', 'USED_IN_REPLICATION')
    )
    into v_sep_workers, v_unit_select, v_repl_involv;

    select
        'score_'||lpad( cast( coalesce(aux1,0) as int ), iif( coalesce(aux1,0) < 99999, 5, 18 ) , '0' )
        ,datediff(minute from p.dts_beg to p.dts_end)
        ,p.dts_beg
    from perf_log p
    where p.unit = 'perf_watch_interval'
    order by p.dts_beg desc
    rows 1
    into overall_perf, v_test_time, v_dts_beg;

    v_test_finish_state = null;
    if ( a_test_time_minutes = -1 ) then -- call AFTER test finish, when making final report
        begin
            select 'ABEND_GDS_'||p.fb_gdscode
            from perf_log p
            where p.unit = 'sp_halt_on_error' and p.fb_gdscode >= 0
            order by p.dts_beg desc
            rows 1
            into v_test_finish_state; -- will remain NULL if not found ==> test finished NORMAL.
        end
    else -- a_test_time_minutes > = 0
        begin
           -- call from main batch (1run_oltp_emul) just BEFORE all ISQL
           -- sessions will be launched: display *estimated* name of report
            overall_perf = 'score_' || lpad('',5,'X');
            v_test_time = a_test_time_minutes;
        end

    select left(ansi_dts, 13) from sys_timestamp_to_ansi( coalesce(:v_dts_beg, current_timestamp))
    into start_at;

    v_test_time = coalesce(v_test_time,0);
    load_time = lpad(cast(v_test_time/60 as int),2,'_')||'h' || lpad(mod(v_test_time,60),2,'0')||'m';

    if ( a_num_of_sessions = -1 ) then
        -- Use *actual* number of ISQL sessions that were participate in this test run.
        -- This case is used when final report is created AFTER test finish, from oltp_isql_run_worker.bat (.sh):
        select count(distinct e.att_id)
        from perf_estimated e
        into v_num_of_sessions;
    else
        -- Use *declared* number of ISQL sessions that *will* be participate in this test run:
        -- (this case is used when we diplay name of report BEFORE launching ISQL sessions, in 1run_oltp_emul.bat (.sh) script):
        v_num_of_sessions= a_num_of_sessions;

    k=iif( coalesce(v_num_of_sessions, 0) <= 0, 1, iif(v_num_of_sessions<=999, 3, char_length(v_num_of_sessions) ) );
    load_att = lpad( coalesce(v_num_of_sessions, '0'), k, '_') || '_att';

    k = position('.' in reverse(a_build));
    a_build = iif( k > 0, reverse(left(reverse(a_build), k - 1)), a_build );

    if ( a_format = 'regular' ) then
        -- ###########################################
        -- ###   f o r m a t  =  'r e g u l a r'   ###
        -- ###########################################
        -- 20190117_2219_score_06578_bld_33333_ss30__0h30m__10_att_fw_off_repl_1.txt 
        -- 20190121_2219_score_06578_bld_34444_ss30__0h30m__10_att_fw__on_repl_0.txt 
        report_file =
            start_at
            || '_' || coalesce( v_test_finish_state, overall_perf )
            || iif( a_build > '', '_bld_' || a_build, '' )
            || '_' || fb_arch
            || '_' || load_time
            || '_' || load_att
            || '_' || fw_setting
            -- excluded 02.01.19, not needed: || '_' || v_sep_workers
            -- excluded 31.10.18, not needed: || '_' || v_unit_select
            || '_' || v_repl_involv
        ;
    else if (a_format = 'benchmark') then
        -- ###############################################
        -- ###   f o r m a t  =  'b e n c h m a r k'   ###
        -- ###############################################
        begin
            for
                select
                    tab_name,
                    min(idx_key) as min_idx_key,
                    max(idx_key) as max_idx_key
                from z_qd_indices_ddl z
                group by tab_name
                rows 1
            into
                v_tab_name, v_min_idx_key, v_max_idx_key
            do begin
        
                heavy_load_ddl = iif( upper(v_tab_name)=upper('qdistr'), 'solid', 'split' );
        
                if ( upper(v_min_idx_key) starting with upper('ware_id') or upper(v_max_idx_key) starting with upper('ware_id')  ) then
                    compound_1st_col = 'most__sel_1st';
                else if ( upper(v_min_idx_key) starting with upper('snd_optype_id') or upper(v_max_idx_key) starting with upper('snd_optype_id')  ) then
                    compound_1st_col = 'least_sel_1st';
        
                if ( v_min_idx_key = v_max_idx_key ) then
                    compound_idx_num = 'one_index';
                else
                    compound_idx_num = 'two_indxs';
            end
            -- ss30_fw__on_solid_most__sel_1st_two_indxs_loadtime_180m_by_100_att_20151102_0958_20151102_1258.txt
            report_file =
                fb_arch
                || '_' || fw_setting
                || '_' || heavy_load_ddl -- 'solid' | 'split'
                || '_' || compound_1st_col -- 'most__sel_1st' | 'least_sel_1st'
                || '_' || compound_idx_num -- 'one_index' | 'two_indxs'
                || '_' || v_sep_workers
                -- excluded 31.10.18, not needed: || '_' || v_unit_select
                || '_' || v_repl_involv
                || '_' || coalesce( v_test_finish_state, overall_perf )
                || iif( a_build > '', '_bld_' || a_build, '' )
                || '_' || load_time
                || '_' || load_att
                || '_' || start_at
            ;
        end

    if ( trim(a_prefix) > '' ) then report_file = trim(a_prefix) || '-' || report_file;

    if ( trim(a_suffix) > '' ) then report_file = report_file || '-' || trim(a_suffix);

    suspend;

end

^ -- srv_get_report_name

create or alter procedure srv_test_work
returns (
    ret_code integer)
as
    declare v_bak_ctx1 int;
    declare v_bak_ctx2 int;
    declare n bigint;
    declare v_clo_id bigint;
    declare v_ord_id bigint;
    declare v_inv_id bigint;
    declare v_res_id bigint;
begin
    -- "express test" for checking that main app units work OK.
    -- NB: all tables must be EMPTY before this SP run.
    v_bak_ctx1 = rdb$get_context('USER_SESSION', 'ORDER_FOR_OUR_FIRM_PERCENT');
    v_bak_ctx2 = rdb$get_context('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE');

    rdb$set_context('USER_SESSION', 'ORDER_FOR_OUR_FIRM_PERCENT',0);
    rdb$set_context('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE',1);

    select min(p.doc_list_id) from sp_client_order(0,1,1) p into v_clo_id;
    select count(*) from srv_make_invnt_saldo into n;
    select min(p.doc_list_id) from sp_supplier_order(0,1,1) p into v_ord_id;
    select count(*) from srv_make_invnt_saldo into n;
    select min(p.doc_list_id) from sp_supplier_invoice(0,1,1) p into v_inv_id;
    select count(*) from srv_make_invnt_saldo into n;
    select count(*) from sp_add_invoice_to_stock(:v_inv_id) into n;
    select count(*) from srv_make_invnt_saldo into n;

    select h.id
    from doc_list h
    join optypes o
    on h.optype_id = o.id and o.m_qty_avl = 1 and o.m_qty_res = -1 -- FN_OPER_RETAIL_RESERVE
    rows 1
    into :v_res_id;

    select count(*) from sp_reserve_write_off(:v_res_id) into n;
    select count(*) from srv_make_invnt_saldo into n;
    select count(*) from sp_cancel_client_order(:v_clo_id) into n;
    select count(*) from srv_make_invnt_saldo into n;
    select count(*) from sp_cancel_supplier_order(:v_ord_id) into n;
    select count(*) from srv_make_invnt_saldo into n;

    rdb$set_context('USER_SESSION', 'ORDER_FOR_OUR_FIRM_PERCENT', v_bak_ctx1);
    rdb$set_context('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE', v_bak_ctx2);

    ret_code = iif( exists(select * from v_qdistr_source ) or exists(select * from v_qstorned_source ), 1, 0);
    ret_code = iif( exists(select * from invnt_turnover_log), bin_or(ret_code, 2), ret_code );
    ret_code = iif( NOT exists(select * from invnt_saldo), bin_or(ret_code, 4), ret_code );
    
    n = null;
    select s.id
    from invnt_saldo s
    where NOT
    (
        s.qty_clo=1 and s.qty_clr = 1
        and s.qty_ord = 0 and s.qty_sup = 0
        and s.qty_avl = 0 and s.qty_res = 0
        and s.qty_inc = 0 and s.qty_out = 0
    )
    rows 1
    into n;
    
    ret_code = iif( n is NOT null, bin_or(ret_code, 8), ret_code );
    
    suspend;
end

^ -- srv_test_work

-- 30.10.2018, temply, just 4compare with UDF:
recreate table tpause(id bigint primary key)
^
create or alter procedure sp_pause(
    a_sleep_to smallint
    ,a_connect_with_usr varchar(31) default 'SYSDBA'
    ,a_connect_with_pwd varchar(31) default 'masterkey'
) returns(
    slept_ms int
) as
   declare n smallint;
   declare k bigint;
   declare dts_start timestamp;
   declare v_role varchar(31);
begin

    -- Check that current Tx run in NO wait or with lock_timeout.
    execute procedure sp_check_nowait_or_timeout;

   -- set transaction lock timeout 1;
   -- select * from sp_pause(7);
   dts_start = cast('now' as timestamp);

   k =  rand() * 9223372036854775807;

   insert into tpause(id) values(:k);
   v_role = left('R' || replace(uuid_to_char(gen_uuid()),'-',''),31);
   n = a_sleep_to;
   while (n > 0) do
   begin
       -- Check that table `ext_stoptest` (external text file) is EMPTY,
       -- otherwise raises ex`ception to stop test:
       execute procedure sp_check_to_stop_work;
               
       begin
           execute statement ('insert into tpause(id) values( ? )' ) ( k )
            on external
                 'localhost:' || rdb$get_context('SYSTEM', 'DB_NAME')
            as
                 user a_connect_with_usr
                 password a_connect_with_pwd
                 role v_role
           ;
       when any do
           begin
           end
       end
       n =  n-1;
   end
   delete from tpause where id = :k;

   slept_ms = datediff( millisecond from dts_start to cast('now' as timestamp) );
   suspend;
end
^ -- sp_pause

create or alter procedure sys_get_run_info(a_mode varchar(12)) returns(
    dts varchar(12)
    ,trn varchar(14)
    ,unit dm_unit
    ,msg varchar(20)
    ,add_info varchar(40)
    ,elapsed_ms varchar(10)
)
as
begin
    -- Aux SP for output info about unit that is to be performed now.
    -- used in batch 'oltpNN_worker.bat'
    dts = substring(cast(current_timestamp as varchar(24)) from 12 for 12);
    unit = rdb$get_context('USER_SESSION','SELECTED_UNIT');
    if ( a_mode='start' ) then
        begin
            trn = 'tra_'||coalesce(current_transaction,'<?>');
            msg = 'start';
            add_info = 'att_'||current_connection;
        end
    else
        begin
            trn = 'tra_'||rdb$get_context('USER_SESSION','APP_TRANSACTION');
            msg = rdb$get_context('USER_SESSION', 'RUN_RESULT');
            add_info = rdb$get_context('USER_SESSION','ADD_INFO');
            elapsed_ms =
                lpad(
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
                        );
        end
    suspend;
end

^ -- sys_get_run_info

create or alter procedure sp_split_into_words(
    a_text dm_name,
    a_dels varchar(50) default ',.<>/?;:''"[]{}`~!@#$%^&*()-_=+\|/',
    a_special char(1) default ' '
)
returns (
  word dm_name
) as
begin
-- Aux SP, used only in oltp_data_filling.sql to filling table PATTERNS
-- with miscelan combinations of words to be used in SIMILAR TO testing.
for
    with recursive
    j as( -- loop #1: transform list of delimeters to rows
        select s,1 i, substring(s from 1 for 1) del
        from(
          select replace(:a_dels,:a_special,'') s
          from rdb$database
        )
        
        UNION ALL
        
        select s, i+1, substring(s from i+1 for 1)
        from j
        where substring(s from i+1 for 1)<>''
    )

    ,d as(
        select :a_text s, :a_special sp from rdb$database
    )
    ,e as( -- loop #2: perform replacing each delimeter to `space`
        select d.s, replace(d.s, j.del, :a_special) s1, j.i, j.del
        from d join j on j.i=1

        UNION ALL

        select e.s, replace(e.s1, j.del, :a_special) s1, j.i, j.del
        from e
        -- nb: here 'column unknown: e.i' error will be on old builds of 2.5,
        -- e.g: WI-V2.5.2.26540 (letter from Alexey Kovyazin, 24.08.2014 14:34)
        join j on j.i = e.i + 1
    )
    ,f as(
        select s1 from e order by i desc rows 1
    )
    
    ,r as ( -- loop #3: perform split text into single words
        select iif(t.k>0, substring(t.s from t.k+1 ), t.s) s,
             iif(t.k>0,position( del, substring(t.s from t.k+1 )),-1) k,
             t.i,
             t.del,
             iif(t.k>0,left(t.s, t.k-1),t.s) word
        from(
          select f.s1 s, d.sp del, position(d.sp, s1) k, 0 i from f cross join d
        )t

        UNION ALL

        select iif(r.k>0, substring(r.s from r.k+1 ), r.s) s,
             iif(r.k>0,position(r.del, substring(r.s from r.k+1 )),-1) k,
             r.i+1,
             r.del,
             iif(r.k>0,left(r.s, r.k-1),r.s) word
        from r
        where r.k>=0
    )
    select word from r where word>''
    into
        word
do
    suspend;
end

^ -- sp_split_into_words

create or alter procedure sys_list_to_rows (
    A_LST blob sub_type 1 segment size 80,
    A_DEL char(1) = ',')
returns (
    LINE integer,
    EOF integer,
    ITEM varchar(8192))
AS
  declare pos_ int;
  declare noffset int = 1;
  declare beg int;
  declare buf varchar(30100);
begin
  -- Splits blob to lines by single char delimiter.
  -- adapted from here:
  -- http://www.sql.ru/forum/actualthread.aspx?bid=2&tid=607154&pg=2#6686267
  if (a_lst is null) then exit;
  line=0;

  while (0=0) do begin
    buf = substring(a_lst from noffset for 30100);
    pos_ = 1; beg = 1;
    while (pos_ <= char_length(buf) and pos_ <= 30000) do begin
      if (substring(buf from pos_ for 1) = :a_del) then begin
        if (pos_ > beg) then
          item = substring(buf from beg for pos_ - beg);
        else
          item = ''; --null;
        suspend;
        line=line+1;
        beg = pos_ + 1;
      end
      pos_ = pos_ + 1;
    end
    if (noffset + pos_ - 2 = char_length(a_lst)) then leave;
    noffset = noffset + beg - 1;
    if (noffset > char_length(a_lst)) then leave;
  end

  if (pos_ > beg) then begin
    item = substring(buf from beg for pos_ - beg);
    eof=-1;
  end
  else begin
    item = '';
    eof=-1;
  end
  suspend;

end

^ -- sys_list_to_rows

create or alter procedure sys_get_proc_ddl (
    a_proc varchar(31),
    a_mode smallint = 1,
    a_include_setterm smallint = 1)
returns (
    src varchar(32760))
as
begin
    if ( a_proc is null or
         not singular(select * from rdb$procedures p where p.rdb$procedure_name starting with upper(:a_proc))
       ) then
    begin
        src = '-- invalid input argument a_proc = ' || coalesce('"'||trim(a_proc)||'"', '<null>');
        suspend;
        exception ex_bad_argument; -- using( coalesce('"'||trim(a_proc)||'"', '<null>'), 'sys_get_proc_ddl' );
    end

    for
        -- Extracts metadata of STORED PROCSEDURES to be executed as statements in isql.
        -- Samples:
        -- select src from sys_get_proc_ddl('', 0) -- output all procs with EMPTY body (preparing to update)
        -- select src from sys_get_proc_ddl('', 1) -- output all procs with ODIGIN body (finalizing update)
        
        with
        s as(
            select
                m.mon$sql_dialect db_dialect
                ,:a_mode mode -- -1=only SP name and its parameters, 0 = name+parameters+empty body, 1=full text
                ,:a_include_setterm add_set_term -- 1 => include `set term ^;` clause
                ,r.rdb$character_set_name db_default_cset
                ,p.rdb$procedure_name p_nam
                ,ascii_char(10) d
                ,replace(cast(p.rdb$procedure_source as blob sub_type 1), ascii_char(13), '') p_src
                ,(
                    select
                        coalesce(sum(iif(px.rdb$parameter_type=0,1,0))*1000 + sum(iif(px.rdb$parameter_type=1,1,0)),0)
                    from rdb$procedure_parameters px
                    where px.rdb$procedure_name = p.rdb$procedure_name
                ) pq -- cast(pq/1000 as int) = qty of IN-args, mod(pq,1000) = qty of OUT args
            from mon$database m -- put it FIRST in the list of sources!
            join rdb$database r on 1=1
            join rdb$procedures p on 1=1
            where p.rdb$procedure_name starting with upper(:a_proc) -- substitute with some name if needed
        )
        --select * from s
        ,r as(
            select
                db_dialect
                ,mode
                ,add_set_term
                ,db_default_cset
                ,p_nam
                ,p.line as i
                ,p.item as word
                ,d
                ,pq
                ,p_src
                ,cast(pq/1000 as int) pq_in
                ,mod(pq,1000) pq_ou
                ,p.eof k
            from s
            left join sys_list_to_rows(p_src, d) p on 1=1
        )
        --select * from r
        
        ,p as(
            select
                db_dialect
                ,mode
                ,add_set_term
                ,db_default_cset
                ,p_nam,i
                ,word
                ,r.pq_in
                ,r.pq_ou
                ,pt -- ip=0, op=1
                ,pp.rdb$field_source ppar_fld_src
                ,pp.rdb$parameter_name par_name
                ,pp.rdb$parameter_number par_num
                ,pp.rdb$parameter_type par_ty
                ,pp.rdb$null_flag p_not_null -- 1==> not null
                ,pp.rdb$parameter_mechanism ppar_mechan -- 1=type of (table.column, domain, other...)
                ,pp.rdb$relation_name ppar_rel_name
                ,pp.rdb$field_name par_fld
                ,case f.rdb$field_type
                    when 7 then 'smallint'
                    when 8 then 'integer'
                    when 10 then 'float'
                    --when 14 then 'char(' || cast(cast(f.rdb$field_length / iif(ce.rdb$character_set_name=upper('utf8'),4,1) as int) as varchar(5)) || ')'
                    when 14 then 'char(' || cast(cast(f.rdb$field_length / ce.rdb$bytes_per_character as int) as varchar(5)) || ')'
                    when 16 then -- dialect 3 only
                        case f.rdb$field_sub_type
                            when 0 then 'bigint'
                            when 1 then 'numeric(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                            when 2 then 'decimal(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                            else 'unknown'
                        end
                    when 12 then 'date'
                    when 13 then 'time'
                    when 27 then -- dialect 1 only
                        case f.rdb$field_scale
                            when 0 then 'double precision'
                            else 'numeric(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                        end
                    when 35 then iif(db_dialect=1, 'date', 'timestamp')
                    when 37 then 'varchar(' || cast(cast(f.rdb$field_length / ce.rdb$bytes_per_character as int) as varchar(5)) || ')'
                    when 261 then 'blob sub_type ' || f.rdb$field_sub_type || ' segment size ' || f.rdb$segment_length
                    else 'unknown'
                end
                as fddl
                ,f.rdb$character_set_id fld_source_cset_id
                ,f.rdb$collation_id fld_coll_id
                ,ce.rdb$character_set_name fld_src_cset_name
                ,co.rdb$collation_name fld_collation
                ,cast(f.rdb$default_source as varchar(1024)) fld_default_src
                ,cast(pp.rdb$default_source as varchar(1024)) ppar_default_src   -- ppar_default_src
                ,k -- k=-1 ==> last line of sp
            from r
            join (
                select -2 pt from rdb$database -- 'set term ^;'
                union all select -1 from rdb$database -- header stmt: 'create or alter procedure ...('
                union all select  0 from rdb$database -- input pars
                union all select  5 from rdb$database -- 'returns ('
                union all select 10 from rdb$database -- output pars
                union all select 20 from rdb$database -- 'as'
                union all select 50 from rdb$database -- source code
                union all select 100 from rdb$database -- '^set term ;^'
            ) x on
                -- `i`=line of body, 0='begin'
                i = 0 and x.pt = -1 -- header
                or i =0 and x.pt = 0 and pq_in > 0 -- input args, if exists
                or i =0 and x.pt in(5,10) and pq_ou > 0 -- output args, if exists ('returns(' line)
                or i =0 and x.pt = 20 -- 'AS'
                or pt = 50
                or i = 0 and x.pt in(-2, 100) and add_set_term = 1 -- 'set term ^;', final '^set term ;^'
            left join rdb$procedure_parameters pp on
                r.p_nam = pp.rdb$procedure_name
                and (x.pt = 0 and pp.rdb$parameter_type = 0 or x.pt = 10 and pp.rdb$parameter_type = 1)
            --x.pt=pp.rdb$parameter_type-- =0 => in, 1=out
            left join rdb$fields f on
                pp.rdb$field_source = f.rdb$field_name
            left join rdb$collations co on
                f.rdb$character_set_id = co.rdb$character_set_id
                and f.rdb$collation_id = co.rdb$collation_id
            left join rdb$character_sets ce on
                co.rdb$character_set_id = ce.rdb$character_set_id
        )
        --select * from p
        
        ,fin as(
            select
                db_dialect
                ,mode
                ,add_set_term
                ,db_default_cset
                ,p_nam
                ,i
                ,par_num
                ,case
                 when pt=-2 then 'set term ^;'
                 when pt=100 then '^set term ;^'
                 when pt=-1 then 'create or alter procedure '||trim(p_nam)||iif(pq_in>0,' (','')
                 when pt=5 then 'returns ('
                 when pt=20 then 'AS'
                 when pt in(0,10) then --in or out argument definition
                     '    '
                     ||trim(par_name)||' '
                     ||lower(trim( iif(nullif(p.ppar_mechan,0) is null, -- ==> parameter is defined with direct reference to base type, NOT like 'type of ...'
                                       iif(ppar_fld_src starting with 'RDB$', p.fddl, ppar_fld_src),
                                       ' type of '||coalesce('column '||trim(ppar_rel_name)||'.'||trim(par_fld), ppar_fld_src)
                                      )
                                 )
                            ) -- parameter type
                     ||iif(nullif(p.ppar_mechan,0) is not null -- parameter is defined as: "type of column|domain"
                           or
                           ppar_fld_src NOT starting with 'RDB$' -- parameter is defined by DOMAIN: "a_id dm_idb"
                           or
                           nullif(p.fld_src_cset_name,upper('NONE')) is null -- field of non-text type or charset was not specified
                           --coalesce(p.fld_src_cset_name, p.db_default_cset) is not distinct from p.db_default_cset
                           ,trim(trailing from iif(p.p_not_null=1, ' not null', ''))
                           ,' character set '||trim(p.fld_src_cset_name)
                             ||trim(trailing from iif(p.p_not_null=1, ' not null', ''))
                             ||iif(p.fld_collation is distinct from p.fld_src_cset_name, ' collate '||trim(p.fld_collation), '')
                          )
                     ||coalesce(
                          ' '||trim(
                               iif( ppar_fld_src starting with upper('RDB$'), ----- adding "default ..." clause
                                    coalesce(ppar_default_src, fld_default_src), -- this is only for 2.5; on 3.0 default values always are stored in ppar_default_src
                                    ppar_default_src
                                  )
                              )
                        ,'')
                     ||iif(pt=0 and par_num=pq_in-1 or pt=10 and par_num=pq_ou-1,')',',')
                  when k=-1 then coalesce(nullif(word,'')||';','') -- nb: some sp can finish with empty line!
                  else word
                end word
                ,pt
                ,ppar_fld_src
                ,par_name
                ,par_ty
                ,pq_in
                ,pq_ou
                --,f.rdb$field_type ftyp ,f.rdb$field_length flen,f.rdb$field_scale fdec
                ,p.fddl
                ,p.fld_src_cset_name
                ,p.fld_collation
                ,k
                --,'#'l,f.*
            from p
            left join rdb$fields f on p.ppar_fld_src = f.rdb$field_name
        )
        --select * from fin order by p_nam,pt,par_num,i
        
        select --mode,p_nam,
            cast(
            case
             when mode<=0 then
               case when pt <50 /*is not null*/ then word
                    when pt in(-2, 100) and add_set_term = 1 then word
                    when mode = 0 and i = 0 and pt < 100 then ' begin'||iif(k = -1, ' end','')
                    when mode = 0 and i = 1 then iif(pq_ou>0, '  suspend;', '  exit;')
                    when mode = 0 and k = -1 then 'end;' -- last line of body
               end
             else word
             end
            as varchar(8192)) -- blob can incorrectly displays (?)
             as src
        --,f.* -- do not! implementation exceeded
        from fin f
        where mode<=0 and (i in(0,1) or k=-1 /*or pt in(-2, 100) and strm=1*/ ) or mode=1
        order by p_nam,pt,par_num,i
        into src
    do
        suspend;

end

^ -- sys_get_proc_ddl

create or alter procedure sys_get_view_ddl (
    A_VIEW varchar(31) = '',
    A_MODE smallint = 1)
returns (
    SRC varchar(8192))
AS
begin
    -- Extracts metadata of VIEWS to be executed as statements in isql.
    -- Samples:
    -- select src from sys_get_view_ddl('', 0) -- output all views with EMPTY body (preparing to update)
    -- select src from sys_get_view_ddl('', 1) -- output all views with ODIGIN body (finalizing update)
    
    for
        with
        inp as(select :a_view a_view, :a_mode mode from rdb$database)
        ,s as(
            select
                m.mon$sql_dialect di
                ,i.mode mode -- 1=> fill
                ,1 strm -- 1 => include `set term ^;` clause
                ,r.rdb$character_set_name cs
                ,p.rdb$relation_name v_name
                ,(select count(*) from rdb$relation_fields rf where p.rdb$relation_name=rf.rdb$relation_name) fq -- count of fields
                ,ascii_char(10) d
                ,replace(cast(p.rdb$view_source as blob sub_type 1), ascii_char(13), '') ||ascii_char(10)||';' p_src
            from mon$database m -- put it FIRST in the list of sources!
            join rdb$database r on 1=1
            join rdb$relations p on 1=1
            join inp i on 1=1
            where coalesce(p.rdb$system_flag,0) = 0
            and p.rdb$view_source is not null -- views; do NOT: p.rdb$relation_type=1 !!
            and  (i.a_view='' or p.rdb$relation_name = upper(i.a_view))
        )
        ,r as(
            select --* --s.*,'#'l,p.*,rf.*
                di
                ,mode
                ,strm
                ,cs
                ,v_name
                ,fq
                ,p.item word
                ,p.line i
                ,p.eof k
                ,rf.rdb$field_position fld_pos
                ,x.rt
                ,rf.rdb$field_name v_fld
                ,rf.rdb$field_source v_src
                ,case f.rdb$field_type
                    when 7 then 'smallint'
                    when 8 then 'integer'
                    when 10 then 'float'
                    when 14 then 'char(' || cast(cast(f.rdb$field_length / ce.rdb$bytes_per_character as int) as varchar(5)) || ')'
                    when 16 then -- dialect 3 only
                    case f.rdb$field_sub_type
                        when 0 then 'bigint'
                        when 1 then 'numeric(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                        when 2 then 'decimal(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                        else 'unknown'
                    end
                    when 12 then 'date'
                    when 13 then 'time'
                    when 27 then -- dialect 1 only
                    case f.rdb$field_scale
                        when 0 then 'double precision'
                        else 'numeric(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                    end
                    when 35 then iif(di=1, 'date', 'timestamp')
                    when 37 then 'varchar(' || cast(cast(f.rdb$field_length / ce.rdb$bytes_per_character as int) as varchar(5)) || ')'
                    when 261 then 'blob sub_type ' || f.rdb$field_sub_type || ' segment size ' || f.rdb$segment_length
                    else 'unknown'
                end fddl
                ,f.rdb$character_set_id fld_cset
                ,f.rdb$collation_id fld_coll_id
                ,ce.rdb$character_set_name cset_name
                ,co.rdb$collation_name fld_collation
            from s
            left join sys_list_to_rows(p_src, d) p
                on p.line=0 or mode=1
            left join
            (
                select -2 rt from rdb$database -- create or alter view
                union all select -1 from rdb$database -- for fields of view
                union all select 0 from rdb$database -- body
                union all select 99 from rdb$database -- final ';'
            ) x on
                p.line=0 and x.rt in(-2,-1,99) or x.rt=0 and mode=1
            left join rdb$relation_fields rf on -- fields of the view
                ( /*mode=0 or mode=1 and*/ p.line=0 and x.rt=-1)
                and s.v_name=rf.rdb$relation_name
            left join rdb$fields f on
                rf.rdb$field_source=f.rdb$field_name
            left join rdb$collations co on
                f.rdb$character_set_id=co.rdb$character_set_id
                and f.rdb$collation_id=co.rdb$collation_id
            left join rdb$character_sets ce on
                co.rdb$character_set_id=ce.rdb$character_set_id
        )
        --select * from r order by v_name,rt,i,fld_pos
        
        ,fin as(
            select
                di
                ,mode
                ,strm
                ,cs
                ,v_name
                ,fq
                ,case
                    when 1=1 or mode=0 then
                        case
                            when rt=-2 then
                                'create or alter view '||trim(v_name)||iif( mode=0, ' as select',' (' )
                            when mode=1 and rt=-1 then -- rt=-1: fields of view
                                trim(v_fld)||trim(iif(fld_pos+1=fq,') as',','))
                            when mode=0 and rt=-1 then
                                iif(fld_pos=0, '', ', ')||
                                case when
                                        lower(fddl) in ('smallint','integer','bigint','double precision','float')
                                        or lower(fddl) starting with 'numeric'
                                        or lower(fddl) starting with 'decimal'
                                    then '0 as '||v_fld
                                    when
                                        lower(fddl) starting with 'varchar'
                                        or lower(fddl) starting with 'char'
                                        or lower(fddl) starting with 'blob'
                                    then ''''' as '||v_fld
                                    when
                                        lower(fddl) in ('timestamp','date')
                                    then 'cast(''now'' as '||lower(fddl)||') as '||v_fld
                                end
                            when rt=0 then word
                            when rt=99 then iif(mode=0,'from rdb$database;',';') -- final row
                        end
                    when mode=1 then
                        case
                            when rt=-1 then 'create or alter view '||trim(v_name)||' as '
                            else word||iif(k=-1 and right(word,1)<>';', ';','')
                        end
                 end
                 as word
                ,i
                ,k
                ,rt
                ,v_fld
                ,v_src
                ,fld_pos
                ,fddl
                ,fld_cset
                ,fld_coll_id
                ,cset_name
                ,fld_collation
            from r
            where word not in(';')
        )
        select word
        from fin
        order by v_name, rt, i,fld_pos
        into src
    do
        suspend;

end

^  -- sys_get_view_ddl

create or alter procedure sys_get_indx_ddl(
    a_relname varchar(31) = '')
returns (
    src varchar(8192))
as
begin
  -- extract DDLs of all indices EXCEPT those which are participated
  -- in PRIMARY KEYS
  for
    with
    inp as(select :a_relname nm from rdb$database)
    ,pk_defs as( -- determine primary keys
      select
        rc.rdb$relation_name rel_name
        ,rc.rdb$constraint_name pk_name
        ,rc.rdb$index_name pk_idx
      from rdb$relation_constraints rc
      where rc.rdb$constraint_type containing 'PRIMARY'
    )
    --select * from pk_defs
    
    ,ix_defs as(
      select
       ri.rdb$relation_name rel_name
      ,rc.rdb$constraint_name con_name
      ,rc.rdb$constraint_type con_type
      ,ri.rdb$index_id idx_id
      ,ri.rdb$index_name idx_name
      ,ri.rdb$unique_flag unq
      ,ri.rdb$index_type des
      ,ri.rdb$foreign_key fk
      ,ri.rdb$system_flag sy
      ,rs.rdb$field_name fld
      ,rs.rdb$field_position pos
      ,ri.rdb$expression_source ix_expr
      ,p.pk_idx
      from rdb$indices  ri
      join inp i on (ri.rdb$relation_name = upper(i.nm) or i.nm='')
      left join rdb$relation_constraints rc on ri.rdb$index_name=rc.rdb$index_name
      left join pk_defs p on ri.rdb$relation_name=p.rel_name and ri.rdb$index_name=p.pk_idx
      left join rdb$index_segments rs on ri.rdb$index_name=rs.rdb$index_name
      where
      ri.rdb$system_flag=0
      and p.pk_idx is null -- => this index is not participated in PK
      order by rel_name,idx_id, pos
    )
    --select * from ix_defs
    ,ix_grp as(
      select rel_name,con_name,con_type,idx_id,idx_name,unq,des,fk,ix_key,ix_expr
      ,r.rdb$relation_name parent_rname
      ,r.rdb$constraint_name parent_cname
      ,r.rdb$constraint_type parent_ctype
      ,iif(r.rdb$constraint_type='PRIMARY KEY'
      ,(select cast(list(trim(pk_fld),',') as varchar(8192)) from
        (select rs.rdb$field_name pk_fld
           from rdb$index_segments rs
          where rs.rdb$index_name=t.fk
          order by rs.rdb$field_position
        )u
       )
       ,null) parent_pkey
      from(
        select rel_name,con_name,con_type,idx_id,idx_name,unq,des,fk
              ,cast(list(trim(fld),',') as varchar(8192)) ix_key
              ,cast(ix_expr as varchar(8192)) ix_expr
        from ix_defs
        group by rel_name,con_name,con_type,idx_id,idx_name,unq,des,fk,ix_expr
      )t
      left join rdb$relation_constraints r on t.fk=r.rdb$index_name
    )
    --select * from ix_grp

    ,fin as(
    select
      rel_name,con_name,con_type,idx_id,idx_name,unq,des,fk
      ,parent_rname,parent_cname,parent_ctype,parent_pkey
      ,case
        when con_type='UNIQUE' then
            'alter table '
            ||trim(rel_name)
            ||' add '||trim(con_type)
            ||'('||trim(ix_key)||')'
            ||iif(idx_name like 'RDB$%', '', ' using index '||trim(idx_name))
            ||';'
        when con_type='FOREIGN KEY' and con_name like 'INTEG%' then
            'alter table '
            ||trim(rel_name)
            ||' add '||trim(con_type)
            ||'('||trim(ix_key)||') references '
            ||trim(parent_rname)
            ||'('||trim(coalesce(parent_pkey,ix_key)) ||')'
            ||iif(idx_name like 'RDB$FOREIGN%', '', ' using index '||trim(idx_name))
            ||';'
        when con_type='FOREIGN KEY' then
            'alter table '
            ||trim(rel_name)
            ||' add constraint '||trim(con_name)||' '||trim(con_type)
            ||'('||trim(ix_key)||') references '
            ||trim(parent_rname)||'('||trim(parent_pkey)||')'
            ||' using index '||trim(idx_name)
            ||';'
       end ct_ddl
      ,'create '
      ||trim(iif(unq=1,' unique','')
      ||iif(des=1,' descending',''))
      ||' index '||trim(idx_name)
      ||' on '||trim(rel_name)
      ||' '||iif(ix_expr is null,'('||trim(ix_key)||')', 'computed by ('||trim(ix_expr)||')' )
      ||';' ix_ddl
    from ix_grp
    )
    select coalesce(ct_ddl, ix_ddl) idx_ddl --, f.*
    from fin f
  into
    src
  do
    suspend;
end 

^ -- sys_get_indx_ddl

set term ;^
commit;

set list on;
set echo off;
select 'oltp_common_sp.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

-- ###################################################################
-- End of script oltp_common_sp.sql;  next to be run: oltp_main_filling.sql
-- (common for both FB 2.5 and 3.0)
-- ###################################################################

