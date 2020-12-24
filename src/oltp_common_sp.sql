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

-- 14.12.2020: this table is used for check whether gdscode of currently raising exception requires test to be terminated or no.
recreate table fb_severe_errors (
    fb_gdscode int
     -- value of test config 'halt_test_on_errors' parameter that must lead to termination;
     -- Defautl is 'ANY': terminate test job regardless of this parameter if currently
     -- raising exception has gdscode = <fb_gdscode>:
    ,stop_if_halt_list dm_setting_value default 'ANY'
    ,fb_descr dm_info
    ,constraint fb_severe_errors_pk primary key(fb_gdscode)
);


--##################### restored 25.03.2019 #################################

-- This view is used in generated SQL after execute block finished, for showing estimated performance.
create or alter view v_est_perf_for_last_minute as
select
    -- 12.08.2018. Variable 'WORKER_SEQUENTIAL_NUMBER' is defined in 'oltp_isql_run_worker' scenario.
    -- Its value is used in procedures for storing in doc_list.worker_id field.
    -- This is done for separation of scope that is avaliable for each ISQL session.
    -- Purpose - reduce frequency of lock conflicts.
    rdb$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER') as worker_sequential_number
    ,left( cast( p.test_time_dts_end as varchar(24) ), 19 ) as test_ends_at
    ,rdb$get_context('USER_SESSION','GDS_RESULT') as last_operation_gds_code
     --    Sample:
     --        ESTIMATED_PERF_SINCE_TEST_BEG       -2973      8      <timestampX> -- for warm_time phase
     --        ESTIMATED_PERF_SINCE_TEST_BEG        5321    158      <timestampY> -- for test_time phase
     --    ::: NOTE ::: Do not use float numbers with decimal spearator:
     --    -414.50: syntax error: invalid arithmetic operator (error token is ".50")
    ,lpad( iif( p.curr_phase_lasts_minutes >0, cast(p.success_bop_total_cnt / p.curr_phase_lasts_minutes as int), 0 ), 12, ' ' )
        ||
        lpad( p.curr_phase_lasts_minutes, 7, ' ' )
        || ' ' ||
        left(cast( success_bop_last_dts as varchar(50) ),19)
     as estimated_perf_since_test_beg
    ,rdb$get_context('USER_SESSION','WORKING_MODE') as workload_type
    ,rdb$get_context('USER_SESSION','HALT_TEST_ON_ERRORS') as halt_test_on_errors
     -- this variable will be defined in SP srv_fill_mon:
    ,rdb$get_context('USER_SESSION','MON_INFO')  as mon_logging_info
    ,cast( rdb$get_context('USER_SESSION','MON_GATHER_0_END') as bigint)
         - cast( rdb$get_context('USER_SESSION','MON_GATHER_0_BEG') as bigint) 
         + cast( rdb$get_context('USER_SESSION','MON_GATHER_1_END') as bigint)
         - cast( rdb$get_context('USER_SESSION','MON_GATHER_1_BEG') as bigint) 
     as mon_gathering_time_ms
    ,rdb$get_context('USER_SESSION','TRACED_UNITS') as traced_units
from (
    select
          -- How long lasts this phase, minutes:
          maxvalue(
               iif( success_bop_last_dts > p.test_time_dts_beg,
                    datediff(minute from p.test_time_dts_beg to success_bop_last_dts ), -- TEST_TIME phase
                    cast( rdb$get_context('USER_SESSION','WARM_TIME') as int) - datediff(minute from success_bop_last_dts to p.test_time_dts_beg) -- WARM_TIME phase, $warm_time minutes
                 ),
               0
           ) + 1 as curr_phase_lasts_minutes
          -- Total number of business operations which did finish SUCCESSFULLY, since current test phase start.
          -- ::: NOTE ::: We have count them SEPARATELY on warm_time and test_time phases:
         ,success_bop_total_cnt
          -- timestamp of last successfully finished business operation:
         ,success_bop_last_dts
         ,p.test_time_dts_beg -- when tests_time phase started
         ,p.test_time_dts_end -- when tests_time phase will finish
    from (
        select 
             p.test_time_dts_beg
            ,p.test_time_dts_end
             -- ctx var 'TOTAL_OPS_SUCCESS_INFO' is changed in sp_add_perf_log by string:
             -- cast(v_curr_success_bop_cnt as char(18)) || ' ' || cast( v_dts as varchar(24)) ; v_dts = 'now'
            ,cast(left(rdb$get_context('USER_SESSION', 'TOTAL_OPS_SUCCESS_INFO' ), 18 ) as bigint) as success_bop_total_cnt
            ,cast(substring(rdb$get_context('USER_SESSION', 'TOTAL_OPS_SUCCESS_INFO' ) from 20) as timestamp) as success_bop_last_dts
        from sp_get_test_time_dts p -- 10.02.2019: will query 'perf_log' table only one time per session, then returns context variables
        where -- 27.08.2016, otherwise output can contain "null" for 'est_overall_at_minute_since_beg' field
            rdb$get_context('USER_SESSION','SELECTED_UNIT') is distinct from 'TEST_WAS_CANCELLED'
    ) p
) p
;


create or alter view v_estimated_perf_per_minute as
-- Do NOT delete! 28.10.2015.
-- This view is used in oltp_isql_run_worker.bat (.sh) when it creates final report.
-- Table PERF_ESTIMATED is filled up by temply created .sql which scans log
-- of 1st ISQL session (which, in turn, makes final report). This log contains
-- rows like this:
-- EST_OVERALL_AT_MINUTE_SINCE_BEG         0.00      0
-- - where 1st number is estimated performance value and 2nd is datediff(minute)
-- from test start to the moment when each business transaction SUCCESSFULLY finished.
-- Data in this view is performance value in *dynamic* but with detalization per
-- ONE minute, from time when all ISQL sessions start (rather then all other reports
-- which make starting point after database was warmed up).
-- This report can help to find proper value of warm-time in oltpNN_config.
select
    e.minute_since_test_start
    ,avg(e.success_count) as avg_successful_business_ops -- old: avg_estimated
    ,min(e.success_count) / nullif(avg(e.success_count), 0) min_to_avg_ratio
    ,max(e.success_count) / nullif(avg(e.success_count), 0) max_to_avg_ratio
    ,count(e.success_count) rows_aggregated
     -- how many ISQL sessions were actually in work:
    ,avg(distinct e.worker_id) distinct_workers
from v_perf_estimated e
where e.minute_since_test_start>0
group by e.minute_since_test_start
;

----------------------------------------------------------

-- 06.10.2020
create or alter view z_severe_errors as
select fb_gdscode, fb_descr from fb_severe_errors -- this table is filled in 'oltp_main_filling.sql'
;

--------------------------------------------------------
create or alter view z_severe_gds_occured as
select
      -- do NOT use current_timestamp in FB 4.0: this is time with timezone:
      -- e.g.: 2020-05-09 09:21:27.1160 Europe/Moscow
      left(cast(cast('now' as timestamp) as varchar(255)),19) as finished_at
     ,x.severe_errors_occured
    ,iif( x.severe_errors_occured = 1, 'SEVERE PSQL-related errors occured!', 'No severe PSQL-related problems occured' ) as errors_checking_result
from (
  select
      iif(
        exists(
                select *
                from perf_log p
                join z_severe_errors e
                  on p.fb_gdscode = e.fb_gdscode
                     and p.dts_beg >
                     (
                        select x.dts_beg
                        from perf_log x -- 12.10.2018: do NOT replace here "perf_log" with "v_perf_log"
                        where x.unit=lower('perf_watch_interval')
                        order by x.dts_beg desc
                        rows 1
                    )
             )
          ,1 -- found at least one record with severe gdscode {335544321,335544347,335544558,335544665,335544349,335544466,335544838,335544839}
          ,0 -- no severe gdscode found
      ) as severe_errors_occured
  from rdb$database
) x;

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
                ,'RECALC_IDX_MIN_INTERVAL'
                ,'UNIT_SELECTION_METHOD'
                ,'BUILD_WITH_SPLIT_HEAVY_TABS'
                ,'BUILD_WITH_SEPAR_QDISTR_IDX'
                ,'BUILD_WITH_QD_COMPOUND_ORDR'
                ,'ENABLE_MON_QUERY'
                ,'MON_UNIT_PERF'
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

create or alter view z_halt_log as
-- :: NB :: this view is only for DEBUG! 
-- One need to create index on perf_log.trn_id before usage of this view!
select p.id, p.fb_gdscode, p.unit, p.trn_id, p.dump_trn, p.att_id, p.exc_unit, p.info, p.ip, p.dts_beg, e.fb_mnemona, p.exc_info,p.stack
from perf_log p
join (
    select g.trn_id, g.fb_gdscode
    from perf_log g
    join z_severe_errors e -- 16.10.2020: added instead of hard-coded gdscodes for errors considered as 'severe'
    on g.fb_gdscode = e.fb_gdscode
    group by 1,2
) g
on p.trn_id = g.trn_id
left join fb_errors e on p.fb_gdscode = e.fb_gdscode
order by p.id
;

------------------------------------------------------

create or alter view z_finish_state as
-- 16.10.2020. This view is used when final report is created, see oltp_isql_run_worker' scenario:
select
    p.exc_info as finish_state
    ,p.dts_end
    ,p.fb_gdscode
    ,e.fb_mnemona
    ,coalesce(p.stack,'') as stack
    ,p.ip
    ,p.trn_id
    ,p.att_id
    ,p.exc_unit
from rdb$database r
left join perf_log p on p.unit = 'sp_halt_on_error' -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)
left join fb_errors e on p.fb_gdscode = e.fb_gdscode
order by p.dts_beg desc
rows 1;

commit;

------------------------------------------------------
create or alter view v_current_privileges as
-- 22.11.2020. Auxiliary for debug: view privileges for current_role and current_user
-- See src\jrd\grant.epp:
--    switch (UPPER7(privileges[0]))
--    {
--    case 'S':
--        priv |= SCL_select;
--        break;
--    case 'I':
--        priv |= SCL_insert;
--        break;
--    case 'U':
--        priv |= SCL_update;
--        break;
--    case 'D':
--        priv |= SCL_delete;
--        break;
--    case 'R':
--        priv |= SCL_references;
--        break;
--    case 'X':
--        priv |= SCL_execute;
--        break;
--    case 'G':
--        priv |= SCL_usage;
--        break;
--    case 'C':
--        priv |= SCL_create;
--        break;
--    case 'L':
--        priv |= SCL_alter;
--        break;
--    case 'O':
--        priv |= SCL_drop;
--        break;
--    }

select
     g.rdb$user as who_is_granted
    ,g.rdb$relation_name as obj_name
    ,decode( g.rdb$object_type
             ,0,'table'
             ,1,'view'
             ,2,'trigger'
             ,5,'procedure'
             ,7,'exception'
             ,9,'domain'
             ,11,'charset'
             ,13,'role'
             ,14,'generator'
             ,15,'function'
             ,16,'blob filt'
             ,18,'package'
             ,22,'systable'
             ,cast(g.rdb$object_type as varchar(10))
           ) as obj_type
    ,rpad(lpad(max(iif(g.rdb$privilege='S','*',' ')),4,' '),7,' ') as "select"
    ,rpad(lpad(max(iif(g.rdb$privilege='I','*',' ')),4,' '),7,' ') as "insert"
    ,rpad(lpad(max(iif(g.rdb$privilege='U','*',' ')),4,' '),7,' ') as "update"
    ,rpad(lpad(max(iif(g.rdb$privilege='D','*',' ')),4,' '),7,' ') as "delete"
    ,rpad(lpad(max(iif(g.rdb$privilege='G','*',' ')),4,' '),7,' ') as "usage"
    ,rpad(lpad(max(iif(g.rdb$privilege='X','*',' ')),4,' '),7,' ') as "exec"
    ,rpad(lpad(max(iif(g.rdb$privilege='R','*',' ')),4,' '),7,' ') as "refer"
    ,rpad(lpad(max(iif(g.rdb$privilege='C','*',' ')),4,' '),7,' ') as "create"
    ,rpad(lpad(max(iif(g.rdb$privilege='L','*',' ')),4,' '),7,' ') as "alter"
    ,rpad(lpad(max(iif(g.rdb$privilege='O','*',' ')),4,' '),7,' ') as "drop"
    ,rpad(lpad(max(iif(g.rdb$privilege='M','*',' ')),4,' '),7,' ') as "member"
from rdb$user_privileges g
where g.rdb$user in( current_user, current_role )
group by 1,2,3
;
--------------------------------------------------

set term ^;

create or alter procedure fn_halt_sign(a_gdscode int) returns (result smallint)
as
    declare v_halt_on_severe_error dm_name;
begin
    result = 0;
    -- Searches in the table FB_SEVERE_ERRORS record which match to :a_gdscode and meets to current value of 
    -- config parameter 'HALT_TEST_ON_ERRORS' ( list of mnemonas for different severe errors: PK/FK/check violations).
    -- If current :a_gdscode found field FB_SEVERE_ERRORS.stop_if_halt_list either 'ANY' or can be found in the mnemonas
    -- list <HALT_TEST_ON_ERRORS> then returns 1, which means that test must be terminated.
    if (
        exists( select * 
                from fb_severe_errors e
                where
                    e.fb_gdscode = :a_gdscode and -- primary key
                    (
                        e.stop_if_halt_list  = 'ANY'
                        or
                        rdb$get_context('USER_SESSION', 'HALT_TEST_ON_ERRORS') containing e.stop_if_halt_list
                    )
              )
       )
    then
        result = 1;

    suspend; -- 1 ==> force test to be stopped itself

end

^ -- fn_halt_sign

create or alter procedure sp_flush_tmpperf_in_auton_tx(
    a_starter dm_unit,  -- name of module which STARTED job, = rdb$get_context(..., 'LOG_PERF_STARTED_BY')
    a_context_rows_cnt int, -- how many 'records' with context vars need to be processed
    a_gdscode int default null
)
as
    declare i smallint;
    declare v_id dm_idb;
    declare v_curr_tx int;
    declare v_exc_unit char(1); -- type of column perf_log.exc_unit;
    declare v_stack dm_stack;
    declare v_dbkey dm_dbkey;
    declare v_dts_beg timestamp; -- 08.10.2018
begin
    -- Flushes all data from context variables with names 'PERF_LOG_xxx'
    -- which have been set in sp_f`lush_perf_log_on_ABEND for saving uncommitted
    -- data in tmp$perf_log in case of error. Frees namespace USER_SESSION from
    -- all such vars (allowing them to store values from other records in tmp$perf_log)
    -- Called only from sp_abend_flush_perf_log
    v_curr_tx = current_transaction;

    -- 13.08.2014: we have to get full call_stack in AUTONOMOUS trn!
    -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16422273
    in autonomous transaction do -- *****  A U T O N O M O U S    T x, due to call fn_get_stack *****
    begin
        v_dts_beg = cast('now' as timestamp);
        i=0;
        while (i < a_context_rows_cnt) do
        begin
            v_exc_unit =  rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XUNI');
            if ( v_exc_unit = '#' ) then -- ==> call from unit <U> where exception occured (not from callers of <U>)
                
                select result from fn_get_stack( (select result from fn_halt_sign(:a_gdscode)) ) into v_stack;
            else
                v_stack = null;

	        -- NB-1. Do NOT use here v_perf_log. Though it will be aggregated 
	        -- in SP srv_aggregate_perf_data, table perf_agg does not contain
	        -- fields STACK, INFO etc!
	        -- NB-2. DO NOT USE HERE POSTPROCESSING RELATED TO USE_ES = 1 or 2!
            insert into perf_log( -- current unit: sp_flush_tmpperf_in_auton_tx
                id
                ,unit
                ,fb_gdscode
                ,info
                ,exc_unit
                ,exc_info
                ,dts_beg
                ,dts_end
                ,elapsed_ms
                ,aux1
                ,aux2
                ,trn_id
                ,ip
                ,stack
            )
            values(
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_ID')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_UNIT')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_GDS')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_INFO')
                ,:v_exc_unit
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XNFO')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_BEG')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_END')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_MS')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX1')
                ,rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX2')
                ,:v_curr_tx
                ,rdb$get_context('SYSTEM','CLIENT_ADDRESS')
                ,:v_stack
            );

            -- free space for new context vars which can be set on later iteration:
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_ID', null);    -- 1
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_UNIT', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_GDS', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_INFO', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XUNI', null);  -- 5
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XNFO', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_BEG', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_END', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_MS', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX1', null);  -- 10
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX2', null);

            i = i + 1;
        end -- while (i < a_context_rows_cnt)

        /*****************
        -- disabled 13.12.2020
        -- 11.01.2015: decided to profile this;
        -- NB-1. Do NOT use here v_perf_log. Though it will be aggregated 
        -- in SP srv_aggregate_perf_data, table perf_agg does not contain
        -- fields STACK, INFO etc!
        -- NB-2. DO NOT USE HERE POSTPROCESSING RELATED TO USE_ES = 1 or 2!
        insert into perf_log(
             unit
            ,info
            ,dts_beg
            ,dts_end
            ,trn_id
            ,ip
            ,aux1
            ,stack
        ) values(
             't$perf-abend:' || coalesce(:a_starter, 'unknown')    -- unit -- ?? 21.04.2019, not yet fixed ...
            ,'gds='|| coalesce(:a_gdscode, '[null]') ||', saved ' ||:i||' rows in auton. tx'  -- info
            ,:v_dts_beg                                            -- dts_beg
            ,'now'                                                 -- dts_end
            ,:v_curr_tx                                            -- trn_id
            ,:rdb$get_context('SYSTEM','CLIENT_ADDRESS')           -- IP
            ,:i                                                    -- aux1
            ,iif( :a_starter is null, ( select result from fn_get_stack( 1 ) ), null) -- ?? 21.04.2019, not yet fixed ...
         );
         *************/

    end -- in autonom. tx
end
^ -- sp_flush_tmpperf_in_auton_tx

create or alter procedure sp_check_ctx(
    ctx_nmspace_01 dm_ctxns,
    ctx_varname_01 dm_ctxnv,
    ctx_nmspace_02 dm_ctxns = '',
    ctx_varname_02 dm_ctxnv = '',
    ctx_nmspace_03 dm_ctxns = '',
    ctx_varname_03 dm_ctxnv = '',
    ctx_nmspace_04 dm_ctxns = '',
    ctx_varname_04 dm_ctxnv = '',
    ctx_nmspace_05 dm_ctxns = '',
    ctx_varname_05 dm_ctxnv = '',
    ctx_nmspace_06 dm_ctxns = '',
    ctx_varname_06 dm_ctxnv = '',
    ctx_nmspace_07 dm_ctxns = '',
    ctx_varname_07 dm_ctxnv = '',
    ctx_nmspace_08 dm_ctxns = '',
    ctx_varname_08 dm_ctxnv = '',
    ctx_nmspace_09 dm_ctxns = '',
    ctx_varname_09 dm_ctxnv = '',
    ctx_nmspace_10 dm_ctxns = '',
    ctx_varname_10 dm_ctxnv = ''
)
as
    declare msg dm_info = '';
    declare txt dm_info;
begin
    -- Check for each non-empty pair that corresponding context variable
    -- EXISTS in it's namespace. TERMINATES test if one of them does not exist.

    if (ctx_nmspace_01>'' and rdb$get_context( upper(ctx_nmspace_01), upper(ctx_varname_01) ) is null ) then
        msg = 'UNDEFINED: ' || upper(ctx_nmspace_01)||':'||coalesce(upper(ctx_varname_01),'[null]');
    
    if (ctx_nmspace_02>'' and rdb$get_context( upper(ctx_nmspace_02), upper(ctx_varname_02) ) is null ) then
        begin
            txt = upper(ctx_nmspace_02) || ':' || coalesce(upper(ctx_varname_02),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
    if (ctx_nmspace_03>'' and rdb$get_context( upper(ctx_nmspace_03), upper(ctx_varname_03) ) is null ) then
        begin
            txt = upper(ctx_nmspace_03) || ':' || coalesce(upper(ctx_varname_03),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
    
    if (ctx_nmspace_04>'' and rdb$get_context( upper(ctx_nmspace_04), upper(ctx_varname_04) ) is null ) then
        begin
            txt = upper(ctx_nmspace_04) || ':' || coalesce(upper(ctx_varname_04),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
    
    if (ctx_nmspace_05>'' and rdb$get_context( upper(ctx_nmspace_05), upper(ctx_varname_05) ) is null ) then
        begin
            txt = upper(ctx_nmspace_05) || ':' || coalesce(upper(ctx_varname_05),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
    
    if (ctx_nmspace_06>'' and rdb$get_context( upper(ctx_nmspace_06), upper(ctx_varname_06) ) is null ) then
        begin
            txt = upper(ctx_nmspace_06) || ':' || coalesce(upper(ctx_varname_06),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
   
    if (ctx_nmspace_07>'' and rdb$get_context( upper(ctx_nmspace_07), upper(ctx_varname_07) ) is null ) then
        begin
            txt = upper(ctx_nmspace_07) || ':' || coalesce(upper(ctx_varname_07),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
    
    if (ctx_nmspace_08>'' and rdb$get_context( upper(ctx_nmspace_08), upper(ctx_varname_08) ) is null ) then
        begin
            txt = upper(ctx_nmspace_08) || ':' || coalesce(upper(ctx_varname_08),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
    
    if (ctx_nmspace_09>'' and rdb$get_context( upper(ctx_nmspace_09), upper(ctx_varname_09) ) is null ) then
        begin
            txt = upper(ctx_nmspace_09) || ':' || coalesce(upper(ctx_varname_09),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end
    
    if (ctx_nmspace_10>'' and rdb$get_context( upper(ctx_nmspace_10), upper(ctx_varname_10) ) is null ) then
        begin
            txt = upper(ctx_nmspace_10) || ':' || coalesce(upper(ctx_varname_10),'[null]');
            if ( char_length(msg) + char_length(txt) < 252 ) then
            begin
                    msg = msg||iif(msg='', '', '; ') || txt;
            end
        end

    if (msg<>'') then
    begin
        -- 13.12.2020: we have to STOP any further work if context variable not defined (5th arg = 1).
        -- Possible reason of this: TRG_CONNECT remains INACTIVE, one need to check logic of '1run_oltp_emul.bat ' batch.
        execute procedure sp_add_to_abend_log( msg, null, '', 'sp_check_ctx', 1 );
        
        exception ex_context_var_not_found; -- using( msg );

    end
end -- sp_check_ctx
^

create or alter procedure sp_rules_for_qdistr
returns(
    mode dm_name,
    snd_optype_id  bigint,
    rcv_optype_id  bigint,
    storno_sub smallint
) as
begin
    -- 29.03.2019: instead of multiple queries to tiny table 'rules_for_qdistr'
    -- Purpose: remove DB access always where it can be done.
    mode = 'new_doc_only';   snd_optype_id = NULL; rcv_optype_id = 1000; storno_sub = NULL; suspend;
    mode = 'distr+new_doc';  snd_optype_id = 1000; rcv_optype_id = 1200; storno_sub = 1;    suspend;
    mode = 'distr+new_doc';  snd_optype_id = 1200; rcv_optype_id = 2000; storno_sub = 1;    suspend;
    mode = 'mult_rows_only'; snd_optype_id = 1000; rcv_optype_id = 3300; storno_sub = 2;    suspend;
    mode = 'mult_rows_only'; snd_optype_id = 2000; rcv_optype_id = 3300; storno_sub = NULL; suspend;
    mode = 'distr+new_doc';  snd_optype_id = 2100; rcv_optype_id = 3300; storno_sub = 1;    suspend;
    mode = 'new_doc_only';   snd_optype_id = 3300; rcv_optype_id = 3400; storno_sub = NULL; suspend;
end

^ -- sp_rules_for_qdistr

create or alter procedure sp_rules_for_pdistr
returns(
    mode dm_name,
    snd_optype_id  bigint,
    rcv_optype_id  bigint,
    rows_to_multiply int
)
as
begin
    -- 29.03.2019: instead of multiple queries to tiny table 'rules_for_pdistr'
    -- Purpose: remove DB access always where it can be done.
    mode = ''; snd_optype_id = 5000; rcv_optype_id = 3400; rows_to_multiply = 10; suspend;
    mode = ''; snd_optype_id = 3400; rcv_optype_id = 5000; rows_to_multiply = 10; suspend;
    mode = ''; snd_optype_id = 4000; rcv_optype_id = 2100; rows_to_multiply = 10; suspend;
    mode = ''; snd_optype_id = 2100; rcv_optype_id = 4000; rows_to_multiply = 10; suspend;
end

^ -- sp_rules_for_pdistr

-- moved here 21.04.2019. Code was adjusted to be COMMON for FB 2.5 and 3.0.
create or alter procedure sp_add_perf_log (
    a_is_unit_beginning dm_sign,
    a_unit dm_unit,
    a_gdscode integer default null,
    a_info dm_info default null,
    a_aux1 dm_aux default null,
    a_aux2 dm_aux default null
) as
    declare v_curr_tx bigint;
    declare v_dts timestamp;
    declare v_save_dts_beg timestamp;
    declare v_save_dts_end timestamp;
    declare v_save_gtt_cnt int;
    declare v_id dm_idb;
    declare v_unit dm_unit;
    declare v_info dm_info;
    declare c_gen_inc_step_pf int = 20; -- size of `batch` for get at once new IDs for perf_log (reduce lock-contention of gen page)
    declare v_gen_inc_iter_pf int; -- increments from 1  up to c_gen_inc_step_pf and then restarts again from 1
    declare v_gen_inc_last_pf dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_pf)
    declare v_pf_new_id dm_idb;
    declare v_curr_phase_lasts_minutes int;
    declare v_top_unit_finish smallint = 0;
    declare v_business_actions_success_cnt bigint;

    declare v_fb_gdscode int;
    declare v_trn_id dm_idb;
    declare v_att_id dm_idb;
    declare v_elapsed_ms int;
    declare v_exc_unit char(1);
    declare v_exc_info dm_info;
    declare v_stack dm_stack;
    declare v_ip dm_ip;
    declare v_dts_beg timestamp;
    declare v_dts_end timestamp;
    declare v_aux1 double precision;
    declare v_aux2 double precision;
    declare v_pool_active int = 0;
    declare v_pool_idle int = 0;
    declare v_worker_id int;
    declare v_lf char(1) = x'0A';
    declare v_sttm varchar(8192);
begin
    -- Registration of all STARTs and FINISHes (both normal and failed)
    -- for all application SPs and some service units:
    v_curr_tx = current_transaction;
    v_dts = cast('now' as timestamp);

    -- 08.10.2018: usage of updatable view v_perf_log instead of table perf_log.

    -- Gather all avaliable mon info about caller module if its name belongs
    -- to list specified in `MON_UNIT_LIST` context var: add pair of row sets
    -- (for beg and end) and then calculate DIFFERENCES of mon. counters with
    -- logging in tables `mon_log` and `mon_log_table_stats`.
    execute procedure srv_log_mon_for_traced_units( a_unit, a_gdscode, a_info );

    if ( not exists(select * from tmp$perf_log) ) then
    begin
       rdb$set_context('USER_TRANSACTION','LOG_PERF_STARTED_BY', a_unit);
       a_is_unit_beginning = 1;
    end

    if ( a_is_unit_beginning = 1 ) then -- this is call from ENTRY of :a_unit
        begin
            insert into tmp$perf_log(
                 unit,
                 info,
                 ip,
                 trn_id,
                 dts_beg
            )
            values(
                 :a_unit,
                 :a_info,
                 rdb$get_context('SYSTEM','CLIENT_ADDRESS'),
                 :v_curr_tx,
                 :v_dts
            );
            -- save info about last started unit (which can raise exc):
            rdb$set_context('USER_TRANSACTION','TPLOG_LAST_UNIT', a_unit);
            rdb$set_context('USER_TRANSACTION','TPLOG_LAST_BEG', v_dts);
            rdb$set_context('USER_TRANSACTION','TPLOG_LAST_INFO', v_info);
        end

    else -- a_is_unit_beginning = 0 ==> this is _NORMAL_ finish of :a_unit (i.e. w/o exception)

        -- ###############################################
        -- ###   s u c c e s s f u l     f i n i s h   ###
        -- ###############################################
        begin
            update tmp$perf_log t set
                info = left(coalesce( info, '' ) || coalesce( trim(iif( info>'', '; ', '') || :a_info), ''), 255),
                dts_end = :v_dts,
                elapsed_ms = datediff(millisecond from dts_beg to :v_dts),
                aux1 = :a_aux1,
                aux2 = :a_aux2
            where -- Bitmap Index "TMP$PERF_LOG_UNIT_TRN" Range Scan (full match)
                t.unit = :a_unit
                and t.trn_id = :v_curr_tx
                and dts_end is NULL -- we are looking for record that was added at the BEG of this unit call
            ;

            -- 08.02.2019. Increment number of total BUSINESS routine calls within this Tx,
            -- in order to display estimated overall performance in ISQL session
            -- logs (see generated $tmpdir/tmp_random_run.sql).
            -- Instead of querying perf_log join business_ops it was decided to
            -- use only context variables in user_tran namespace:
        
            if ( exists(
                    select * from business_ops b
                    where b.unit = lower(:a_unit) -- and mode != 'service'
                    )
                ) then
            begin
                v_top_unit_finish = 1;
                -- # ----------------------------------------------------------------------------------------------------
                -- # i n c r e m e n t    n u m b e r    o f     f i n i s h e d    b u s i n e s     o p e r a t i o n s
                -- # ----------------------------------------------------------------------------------------------------
                rdb$set_context( 'USER_TRANSACTION',
                                 'BUSINESS_OPS_CNT',
                                 coalesce( cast(rdb$get_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT') as int), 0) + 1
                               );
            end
            --execute procedure srv_increment_tx_bops_counter( a_unit );

            if ( a_unit = rdb$get_context('USER_TRANSACTION','LOG_PERF_STARTED_BY') ) then
            begin
                -- We are at final point of top-level unit (which started business op.)
                -- (e.g. s`p_add_invoice_to_stock -- main SP which could call many
                -- times auxiliary s`p_customer_reserve for creating reserves)

                -- Save *ALL* data that currently in GTT tmp$perf_log to permanent storage.
                -- Since 08.10.2018 this is updatable view v_perf_log instead of table.

                v_gen_inc_iter_pf = c_gen_inc_step_pf;

                v_save_dts_beg = 'now'; -- for logging time and number of moved records
                v_save_gtt_cnt = 0;

                for
                    select
                         unit
                        ,exc_unit
                        ,fb_gdscode
                        ,trn_id
                        ,att_id
                        ,elapsed_ms
                        ,info
                        ,exc_info
                        ,stack
                        ,ip
                        ,dts_beg
                        ,dts_end
                        ,aux1
                        ,aux2
                    from tmp$perf_log g
                    into
                         v_unit
                        ,v_exc_unit
                        ,v_fb_gdscode
                        ,v_trn_id
                        ,v_att_id
                        ,v_elapsed_ms
                        ,v_info
                        ,v_exc_info
                        ,v_stack
                        ,v_ip
                        ,v_dts_beg
                        ,v_dts_end
                        ,v_aux1
                        ,v_aux2
                    as cursor ct
                do begin
                    if ( v_gen_inc_iter_pf = c_gen_inc_step_pf ) then -- its time to get another batch of IDs
                    begin
                        v_gen_inc_iter_pf = 1;
                        -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                        v_gen_inc_last_pf = gen_id( g_perf_log, :c_gen_inc_step_pf );
                    end
                    v_pf_new_id = v_gen_inc_last_pf - ( c_gen_inc_step_pf - v_gen_inc_iter_pf );
                    v_gen_inc_iter_pf = v_gen_inc_iter_pf + 1;

                    --    id          dm_idb not null /* dm_idb = bigint */,
                    --    unit        dm_unit /* dm_unit = varchar(80) */,
                    --    exc_unit    char(1),
                    --    fb_gdscode  integer,
                    --    trn_id      bigint default current_transaction,
                    --    att_id      integer default current_connection,
                    --    elapsed_ms  bigint,
                    --    info        dm_info /* dm_info = varchar(255) */,
                    --    exc_info    dm_info /* dm_info = varchar(255) */,
                    --    stack       dm_stack /* dm_stack = varchar(512) */,
                    --    ip          dm_ip /* dm_ip = varchar(255) */,
                    --    dts_beg     timestamp default 'now',
                    --    dts_end     timestamp,
                    --    aux1        double precision,
                    --    aux2        double precision,
                    --    dump_trn    bigint default current_transaction

                    -- Add record into VIEW, which will put it in apropriate
                    -- PERF_SPLIT_nn table (see its t`rigger):

                    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
                    v_sttm=
                    q'{ execute block (
                             v_pf_new_id bigint = ?
                            ,v_unit dm_unit = ?
                            ,v_exc_unit char(1) = ?
                            ,v_fb_gdscode int = ?
                            ,v_trn_id bigint = ?
                            ,v_att_id bigint = ?
                            ,v_elapsed_ms bigint = ?
                            ,v_info dm_info = ?
                            ,v_exc_info dm_info = ?
                            ,v_stack dm_stack = ?
                            ,v_ip dm_ip = ?
                            ,v_dts_beg timestamp = ?
                            ,v_dts_end timestamp = ?
                            ,v_aux1 double precision = ?
                            ,v_aux2 double precision = ?
                        ) as
                        begin
                            -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                            -- NOTE: we have to log timestamp of point just BEFORE query that
                            -- will work: datediff between this point and next firing of
                            -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                            -- of IDLE state for this connect in the Ext. Conn. Pool.
                            execute procedure sp_perf_eds_logging('B');

                            insert into v_perf_log --#EDS#TAG#
                            (
                                id
                                ,unit
                                ,exc_unit
                                ,fb_gdscode
                                ,trn_id
                                ,att_id
                                ,elapsed_ms
                                ,info
                                ,exc_info
                                ,stack
                                ,ip
                                ,dts_beg
                                ,dts_end
                                ,aux1
                                ,aux2
                            ) values (
                                :v_pf_new_id
                                ,:v_unit
                                ,:v_exc_unit
                                ,:v_fb_gdscode
                                ,:v_trn_id
                                ,:v_att_id
                                ,:v_elapsed_ms
                                ,:v_info
                                ,:v_exc_info
                                ,:v_stack
                                ,:v_ip
                                ,:v_dts_beg
                                ,:v_dts_end
                                ,:v_aux1
                                ,:v_aux2
                            );

                            -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                            -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                            -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                            -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                            -- for connect, so there we have TWO events: 'I' and 'A').
                            --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#

                        end
                    }';
                    execute statement (v_sttm)
                    (
                        :v_pf_new_id
                        ,:v_unit
                        ,:v_exc_unit
                        ,:v_fb_gdscode
                        ,:v_trn_id
                        ,:v_att_id
                        ,:v_elapsed_ms
                        ,:v_info
                        ,:v_exc_info
                        ,:v_stack
                        ,:v_ip
                        ,:v_dts_beg
                        ,:v_dts_end
                        ,:v_aux1
                        ,:v_aux2
                    )
                    -- 20.11.2020
                    -- If config parameter USE_ES is 2 then following line will be
                    -- replaced with uncommented code for run as ES/EDS.
                    -- Host and port will be taken from apropriate config parameters.
                    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
                    -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
                    ;
                    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

                    -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
                    insert into v_perf_log( -- current unit: sp_add_perf_log
                        id
                        ,unit
                        ,exc_unit
                        ,fb_gdscode
                        ,trn_id
                        ,att_id
                        ,elapsed_ms
                        ,info
                        ,exc_info
                        ,stack
                        ,ip
                        ,dts_beg
                        ,dts_end
                        ,aux1
                        ,aux2
                    ) values (
                        :v_pf_new_id
                        ,:v_unit
                        ,:v_exc_unit
                        ,:v_fb_gdscode
                        ,:v_trn_id
                        ,:v_att_id
                        ,:v_elapsed_ms
                        ,:v_info
                        ,:v_exc_info
                        ,:v_stack
                        ,:v_ip
                        ,:v_dts_beg
                        ,:v_dts_end
                        ,:v_aux1
                        ,:v_aux2
                    );
                    -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

                    v_save_gtt_cnt = v_save_gtt_cnt + 1;

                    -- do NOT, 22.04.2019: this table can be used for output detailed info about actions within current Tx,
                    -- see .bat and .sh, routine 'gen_working_sql': XXXdelete from tmp$perf_log where current of ct;
                end -- end of loop moving rows from GTT tmp$perf_log to fixed perf_log


                v_save_dts_end = 'now';

                -- 4debug only: how long data from GTT tmp$perf_log was saved:
                /* #ACTIVATE#IF#DEBUG_EQU_1#BEG#
                insert into v_perf_log( -- current unit: sp_add_perf_log
                        id,
                        unit, info, dts_beg, dts_end, elapsed_ms, ip, aux1)
                values( iif( :v_gen_inc_iter_pf < :c_gen_inc_step_pf, :v_pf_new_id+1, gen_id( g_perf_log, 1 )  ),
                        't$perf-norm:'||:a_unit,
                        'ok saved '||:v_save_gtt_cnt||' rows',
                        :v_save_dts_beg,
                        :v_save_dts_end,
                        datediff( millisecond from :v_save_dts_beg to :v_save_dts_end ),
                        rdb$get_context('SYSTEM','CLIENT_ADDRESS'),
                        :v_save_gtt_cnt
                      );
                -- #ACTIVATE#IF#DEBUG_EQU_1#END# */


                -- #################### restored 25.03.2019 ##################################
                -- 08.02.2019. Code control can pass here only when:
                -- 1) :a_unit is 'top-level' business action (i.e. that was chosen in "Big SQL" execute block
                --    by calling srv_random_unit_choice and is "STARTER" of business action),
                -- and 
                -- 2) this :a_unit is to be successfully finished now, i.e. no exceptions ware raise during its execution.
                -- This means that we can here increase g_success_counter.
                if ( v_top_unit_finish = 1 ) then
                begin
                    v_business_actions_success_cnt = gen_id( g_success_counter, cast(rdb$get_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT') as int) );
    
                    -- 21.02.2019: moved here from .bat/.sh. No sense to defer this up to test finish
                    -- because database state will be changed to full-shutdown and almost all of
                    -- attachments could not write all necessary info - they will be forcedly dropped
                    -- by ISQL session #1.
                    v_dts = cast('now' as timestamp);
    
                    -- 10.02.2019: this variable will be used in batch for show estimated perf score:
                    -- ESTIMATED_PERF_SINCE_TEST_BEG           1521    354 2019-02-21 07:50:34
                    rdb$set_context( 'USER_SESSION', 
                                     'TOTAL_OPS_SUCCESS_INFO', 
                                     cast(v_business_actions_success_cnt as char(18)) || ' ' || cast( v_dts as varchar(24)) 
                                   );
    
                    select datediff(minute from p.test_time_dts_beg to :v_dts )
                    from sp_get_test_time_dts p -- 10.02.2019: will query 'perf_log' table only one time per session, then returns context variables
                    into v_curr_phase_lasts_minutes;

                    -- NB: stored procedure rather than PSQL function is used here
                    -- (in order to make this code common for 2.5 and 3.0)
                    select result
                    from fn_this_worker_seq_no
                    into v_worker_id;


                    -- Here we operate with VIEW rather than with table: we have to remove
                    -- any dependencies on table 'perf_estimated' from .sql because this
                    -- table will be dropped and recreated again before each test launch.

                    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#

                    -- NB: this code can be uncommented only when current FB intance supports External COnnection Pool feature
                    -- that was introduced in commercial FB branch HQbird 3.x and also presents in official FB 4.x.
                    -- See batch scenario '1run_oltp_emul': "if use_es=2 if conn_pool_support=0 then <error> + goto final"

                    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# v_pool_active = rdb$get_context('SYSTEM', 'EXT_CONN_POOL_ACTIVE_COUNT'); -- #SUBST#EXTPOOL#SUPPORT_1#END#
                    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# v_pool_idle = rdb$get_context('SYSTEM', 'EXT_CONN_POOL_IDLE_COUNT'); -- #SUBST#EXTPOOL#SUPPORT_1#END#
                    -- #SUBST#EXTPOOL#SUPPORT_0#BEG# v_pool_active = -1; -- #SUBST#EXTPOOL#SUPPORT_0#END#
                    -- #SUBST#EXTPOOL#SUPPORT_0#BEG# v_pool_idle = -1; -- #SUBST#EXTPOOL#SUPPORT_0#END#

                    v_sttm=
                    q'{ execute block(
                            a_minute_since_test_start int = ?
                            ,a_business_actions_success_cnt numeric(12,2) = ?
                            ,a_worker_id dm_ids = ?
                            ,a_pool_active int = ?
                            ,a_pool_idle int = ?
                            ,a_att_id bigint = ?
                            ,a_dts timestamp = ?
                        ) as
                        begin
                            -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                            -- NOTE: we have to log timestamp of point just BEFORE query that
                            -- will work: datediff between this point and next firing of
                            -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                            -- of IDLE state for this connect in the Ext. Conn. Pool.
                            execute procedure sp_perf_eds_logging('B');

                            insert into v_perf_estimated -- #EDS#TAG#
                            (
                                minute_since_test_start
                                ,success_count
                                ,worker_id
                                ,pool_active
                                ,pool_idle
                                ,att_id
                                ,dts
                            ) values (
                                :a_minute_since_test_start
                               ,:a_business_actions_success_cnt
                               ,:a_worker_id
                               ,:a_pool_active
                               ,:a_pool_idle
                               ,:a_att_id
                               ,:a_dts
                            );

                            -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                            -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                            -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                            -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                            -- for connect, so there we have TWO events: 'I' and 'A').
                            --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#

                        end
                    }';
                    execute statement (v_sttm)
                    (
                        v_curr_phase_lasts_minutes
                        ,v_business_actions_success_cnt
                        ,v_worker_id
                        ,v_pool_active
                        ,v_pool_idle
                        ,current_connection
                        ,v_dts
                    )
                    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
                    -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
                    ;
                    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

                    -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
                    -- usual way (use_es = 0): use static PSQL code.
                    insert into v_perf_estimated(
                        minute_since_test_start
                        ,success_count
                        ,worker_id
                        ,pool_active
                        ,pool_idle
                        ,dts
                    ) values (
                        :v_curr_phase_lasts_minutes -- DO NOT add "+1" here, 25.03.2019 1117
                       ,:v_business_actions_success_cnt
                       ,:v_worker_id
                       ,:v_pool_active
                       ,:v_pool_idle
                       ,:v_dts
                    );
                    -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

                end
                --#############################################################################

            end --  a_unit = rdb$get_context( ..., 'LOG_PERF_STARTED_BY')
        end -- a_is_unit_beginning = 0
end
^ -- sp_add_perf_log


create or alter procedure sp_upd_in_perf_log(
    a_unit dm_unit,
    a_gdscode int default null,
    a_info dm_info default null
) as
begin
    -- need in case when we want to update info in just added row
    -- (e.g. info about selected doc etc)
    update tmp$perf_log t set
        t.fb_gdscode = coalesce(t.fb_gdscode, :a_gdscode),
        t.info = coalesce( t.info, '' ) || coalesce( trim(iif( t.info>'', '; ', '') || :a_info), '')
    where
        t.unit = :a_unit
        and t.trn_id = current_transaction
        and t.dts_end is NULL
        and coalesce(t.info,'') NOT containing coalesce(trim(:a_info),'');
end

^  -- sp_upd_in_perf_log


-- 19.09.2020: moved here, code was changed to be compatible with 2.5:

create or alter procedure srv_aggregate_perf_data (
    a_ignore_stop_flag dm_sign = 0)
returns (
    msg dm_info)
as
    declare v_semaphore_id type of dm_ids;
    declare v_deferred_to_next_time smallint = 0;
    declare v_gdscode int = null;
    declare v_dts_beg timestamp;
    declare v_this dm_dbobj = 'srv_aggregate_perf_data';
    declare v_eds_info dm_info;
    declare v_sttm varchar(8192);
    declare v_lf char(1) = x'0A';
    declare c_semaphores cursor for (
        select id from semaphores s where s.task = :v_this rows 1
    );
begin
    -- 19.09.2020: make code common for 2.5 and 3.x+
    -- This SP must be stored in oltp_common_sp.sql

    if ( a_ignore_stop_flag = 0 ) then
    begin
        -- Check that table `ext_stoptest` (external text file) is EMPTY,
        -- otherwise raises e`xception to stop test:
        execute procedure sp_check_to_stop_work;
    end

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    if ( (select result from fn_is_snapshot) <> 1 )
    then
        exception ex_snapshot_isolation_required;

    -- Ensure that current attach is the ONLY one which tries to make totals.
    -- Use locking record from `semaphores` table to serialize access to this
    -- code:
    begin
        open c_semaphores;
        while (1=1) do
        begin
            fetch c_semaphores into v_semaphore_id;
            if ( row_count = 0 ) then
                exception ex_record_not_found; -- using('semaphores', v_this);
            update semaphores set id = id where current of c_semaphores;
            leave;
        end
        close c_semaphores;
    when any do
        -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
        -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
        -- catched it's kind of exception!
        -- 1) tracker.firebirdsql.org/browse/CORE-3275
        --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
        -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
        begin
            if ( (select result from fn_is_lock_trouble(gdscode)) = 1 ) then
                begin
                    -- concurrent_transaction ==> if select for update failed;
                    -- deadlock ==> if attempt of UPDATE set id=id failed.
                    v_gdscode = gdscode;
                    v_deferred_to_next_time = 1;
                end
            else
                exception;  -- ::: nb ::: anonimous but in when-block! (check will it be really raised! find topic in sql.ru)
        end
    end

    if ( coalesce(v_deferred_to_next_time,0) <> 0 ) then
    begin
        -- Info to be stored in context var. A`DD_INFO, see below call of sp_add_to_abend_log (in W`HEN ANY section):
        msg = 'can`t lock semaphores.id='|| coalesce(v_semaphore_id,'<?>') ||', deferred'; -- current unit: srv_aggregate_perf_data
        exception ex_cant_lock_semaphore_record ( select result from sys_stamp_exception('ex_cant_lock_semaphore_record', :msg) );

    end

    if ( a_ignore_stop_flag = 0 ) then
    begin
        -- add to performance log timestamp about start/finish this unit:
        execute procedure sp_add_perf_log(1, v_this);
    end

    v_dts_beg = 'now';
    --- ###########################################################################################################
    --- ### a g g r e g a t i o n:   g a t h e r   d a t a   f r o m   p e r f _ s p l i t _ NN    t a b l e s  ###
    --- ###########################################################################################################

    -- See oltpNN_config, parameter 'use_es'. Can be 0, 1 or 2:


    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    v_sttm =
    q'{ execute block( a_ignore_stop_flag smallint = ? ) returns( msg dm_info ) as
        begin
            -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
            -- NOTE: we have to log timestamp of point just BEFORE query that
            -- will work: datediff between this point and next firing of
            -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
            -- of IDLE state for this connect in the Ext. Conn. Pool.
            execute procedure sp_perf_eds_logging('B');

            select msg --#EDS#TAG#
            from tmp_aggregate_perf_log_autogen( :a_ignore_stop_flag )
            into msg;

            -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
            -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
            -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
            -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
            -- for connect, so there we have TWO events: 'I' and 'A').
            --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#

            suspend;
        end
    }';
    execute statement (v_sttm) ( a_ignore_stop_flag )
    -- 20.11.2020
    -- If config parameter USE_ES is 2 then following line will be
    -- replaced with uncommented code for run as ES/EDS.
    -- Host and port will be taken from apropriate config parameters.
    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
    -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
    into msg;

    execute statement (
        'select --#EDS#TAG#' || v_lf
        || ' msg '
        || ' from tmp_aggregate_perf_eds_autogen( ? )'
    ) ( a_ignore_stop_flag )
    -- ::: NB ::: do NOT add "on-external" substituion here!
    -- Otherwise new records will appear in the perf_eds_split_NN tables
    -- because of firing triggers on connect/disconnect.
    into v_eds_info;
    msg = msg || ', EDS agg.: ' || v_eds_info;
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

    /* #ACTIVATE#IF#USE_ES_EQU_1#BEG#
    -- use_es = 1 --> run this statement via ES in order to see
    -- its occurences and performance in the trace log:
    execute statement (
        'select --#EDS#TAG#' || v_lf
        || ' msg '
        || ' from tmp_aggregate_perf_log_autogen( ? )'
    ) ( a_ignore_stop_flag )
    into msg;
    -- #ACTIVATE#IF#USE_ES_EQU_1#END# */

    -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
    -- usual way (use_es = 0): use static PSQL code.
    select msg from tmp_aggregate_perf_log_autogen( :a_ignore_stop_flag ) into msg; -- 'i=1234, u=3210' etc
    -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

    msg =  msg ||', ms='||datediff(millisecond from v_dts_beg to cast('now' as timestamp) );

    rdb$set_context('USER_SESSION','ADD_INFO', msg);  -- to be displayed in result log of isql

    if ( a_ignore_stop_flag = 0 ) then
    begin
        -- add to performance log timestamp about start/finish this unit:
        execute procedure sp_add_perf_log(0, v_this, v_gdscode, msg );
    end

    suspend;

when any do
    begin
        -- NB: proc sp_add_to_abend_log will set rdb$set_context('USER_SESSION','A`DD_INFO', msg)
        -- in order to show this additional info in ISQL log after operation will finish:
        execute procedure sp_add_to_abend_log(
            msg,  -- ==> context var. ADD_INFO will be = "can`t lock semaphores.id=..., deferred" - to be shown in ISQL log
            gdscode,
            msg,
            v_this,
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^ -- srv_aggregate_perf_data

-- moved here 05.10.2020: code of this SP was made common for FB 2.5 and 3.x
create or alter procedure sp_halt_on_error(
    a_char char(1) default '1',
    a_gdscode bigint default null,
    a_trn_id bigint default null,
    a_need_to_stop smallint default null
) as
    declare v_curr_trn bigint;
    declare v_dummy bigint;
    declare v_need_to_stop smallint;
    declare v_exc_info dm_info;
    declare v_stack dm_stack;
begin
    -- Adding single character + LF into external table (text file) 'stoptest.txt'
    -- when test is needed to stop (either due to test_time expiration or because of
    -- encountering some critical errors like PK/FK violations or negative amount remainders).
    -- Input argument a_char:
    -- '1' ==> call from SP_ADD_TO_ABEND_LOG: unexpected test finish due to PK/FK violation,
    --         and also call from SRV_FIND_QD_QS_MISM when founding mismatches between total
    --         sum of doc_data amounts and count of rows in QDistr + QStorned.
    -- '2' ==> call from SP_CHECK_TO_STOP_WORK: expected test finish due to test_time expired.
    --         In this case argument a_gdscode = -1 and we do NOT need to evaluate call stack.
    -- '5' ==> call from SRV_CHECK_NEG_REMAINDERS: unexpected test finish due to encountering
    --         negative remainder of some ware_id. NB: context var 'QMISM_VERIFY_BITSET' should
    --         have value N for which result of bin_and( N, 2 ) will be 1 in order this checkto be done.

    -- 16.01.2019: this SP can be called from outer .sql where UDF sleep() is called
    -- in loop with SMALL pause = 1 second and checking whether test has to be
    -- terminated or no (between each iteration, i.e. while this loop not ends)
    -- Loop can work in READ_ONLY transaction, thus we have to check it and SKIP
    -- any actions that attempts to write data:
    if ( rdb$get_context('SYSTEM','READ_ONLY') = upper('true') ) then
        exit;
    --########

    -- DO NOT change 'a_need_to_stop' here otherwise record into perf_log will not be added
    -- in case of premature test stop which can be done by 1stoptest.tmp.sh launch:
    -- a_need_to_stop = iif( gen_id(g_stop_test, 0) > 0, 0, a_need_to_stop);

    if ( (a_need_to_stop < 0 or gen_id(g_stop_test, 0) <= 0) and (select result from fn_remote_process) NOT containing 'IBExpert' )
    then
    begin
        v_curr_trn = coalesce(a_trn_id, current_transaction);

        -- "-1" ==> decision to premature stop all ISQL sessions by issuing EXTERNAl command
        -- (either running $tmpdir/1stoptest.tmp.sh or adding line into external file 'stoptest.txt')
        v_need_to_stop = coalesce( :a_need_to_stop, (select p.need_to_stop from sp_stoptest p rows 1) );

        -- 05.10.2020:
        -- 1) changed order of statements. We have to add record into PERF_LOG *before* changing value of g_stop_test!
        -- 2) make code of this SP common for 2.5 and 3.0, in order to move it to oltp_common_sp.sql
        in autonomous transaction do
        begin
            begin
                -- Following record was inserted into PERF_LOG table before test start.
                -- UPDATE statement will serialize access to it and all but one transactions will fail
                -- here with update-conflist error and immediately quit from this block.
                -- If record is absent for some (unknown) reason then we have immediatly to raise error
                -- <ex_record_not_found> and quit at all.
                update perf_log p set p.info = 'closed', trn_id = :v_curr_trn, fb_gdscode = :a_gdscode
                where p.unit = 'perf_watch_interval' and p.info containing 'active'
                order by dts_beg desc
                rows 1;

                if ( row_count = 0 ) then
                     exception ex_record_not_found;

                -- This point can be achieved by only one transaction (because of serialized access
                -- to record which was  updated by previous statement).

                if ( a_char in ('1', '5') ) then
                    -- '1' ==> call from SP_ADD_TO_ABEND_LOG: unexpected test finish due to violation
                    --         of PK or CHECK constraints, or when found some inacceptible conditions.
                    --         Also call from SRV_FIND_QD_QS_MISM when founding mismatches between total
                    --         sum of doc_data amounts and count of rows in QDistr + QStorned.
                    -- '5' ==> call from SRV_CHECK_NEG_REMAINDERS: unexpected test finish due to encountering
                    --         negative remainder of some ware_id. NB: context var 'QMISM_VERIFY_BITSET' should
                    --         have value N for which result of bin_and( N, 2 ) will be 1 in order this checkto be done.
                    begin
                        v_exc_info = 'ABNORMAL FINISH' ||iif( a_gdscode is null, ': gds = null, some data does not match or is missing.', ', gds = ' || coalesce(:a_gdscode,'<?>') );
                    end
                else if (a_char = '2') then
                    -- '2' ==> call from SP_CHECK_TO_STOP_WORK: expected test finish due to test_time expired.
                    --         In this case argument a_gdscode = -1 and we do NOT need to evaluate call stack.
                    begin
                        v_exc_info = iif( :v_need_to_stop < 0
                                          ,'PREMATURE: EXTERNAL COMMAND.'
                                          ,'NORMAL: TEST_TIME EXPIRED AT ' || left(cast(cast('now' as timestamp) as varchar(255)),19)
                                        );
                    end

                select result from fn_get_stack( 1 ) into v_stack;


                -- Leave as ES for ability to see this statement in the trace:
                execute statement ('
                  insert into perf_log -- #HALT#TAG#
                  (
                      unit             -- 1
                     ,fb_gdscode       -- 2
                     ,ip               -- 3
                     ,trn_id           -- 4
                     ,dts_end          -- 5
                     ,elapsed_ms       -- 6
                     ,stack            -- 7
                     ,exc_unit         -- 8
                     ,info             -- 9
                     ,exc_info         -- 10
                  ) values(
                      ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
                  )'
                )
                (
                    'sp_halt_on_error'    --  1
                    ,:a_gdscode           --  2
                    ,rdb$get_context('SYSTEM', 'CLIENT_ADDRESS') -- 3
                    ,:v_curr_trn          --  4
                    ,'now'                --  5
                    ,-1                   --  6 // NB: set elapsed_ms = -1 to skip this record from srv_mon_perf_detailed output:
                    ,v_stack              --  7
                    ,:a_char              --  8
                    ,left(rdb$get_context('USER_SESSION','ADD_INFO'),255) -- 9
                    ,v_exc_info           -- 10
                )
                ;


            when any do
                if ( (select result from fn_is_lock_trouble(gdscode)) = 1 ) then
                    begin
                        -- nop --
                    end
                else
                    exception;  -- ::: nb ::: anonimous but in when-block!

            end

            -- Value of sequence g_stop_test must be changed only ***AFTER***
            -- insering record about finish into poerf_log table!
            -- We change it to positive number in order to get false for
            -- any subsequent evaluation of 'gen_id(g_stop_test, 0) <= 0' (see above):

            v_dummy = gen_id( g_stop_test, abs(gen_id(g_stop_test,0)) + 1 );

        end
    end
end

^ -- sp_halt_on_error


create or alter procedure sp_add_to_abend_log(
       a_exc_info dm_info,
       a_gdscode int default null,
       a_info dm_info default null,
       a_caller dm_unit default null,
       a_halt_due_to_error smallint default 0 --  1 ==> forcely extract FULL STACK ignoring settings, because of error + halt test
) as
    declare v_last_unit dm_unit;
    declare v_last_info dm_info;
    declare v_last_beg timestamp;
    declare v_last_end timestamp;
begin
    -- SP for register info about e`xception occured in application module.
    -- When each module starts, it call sp_add_to_perf_log and creates record in
    -- perf_log table for this event. If some e`xception occurs in that module
    -- than code jumps into when_any section with call of this SP.
    -- Now we have to call sp_add_to_perf_log with special argument ('!abend!')
    -- signalling that all data from GTT tmp$perf_log should be saved now via ATx.
    if ( a_gdscode is NOT null and nullif(a_exc_info, '') is null ) then -- this is standard error
    begin
        select f.fb_mnemona
        from fb_errors f
        where f.fb_gdscode = :a_gdscode
        into a_exc_info;
    end
    -- For displaying in ISQL session logs:
    rdb$set_context('USER_SESSION','ADD_INFO', left( coalesce(a_exc_info, 'no-mnemona'), 255));

    v_last_unit = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_UNIT');

    if ( a_caller = v_last_unit 
         -- or a_halt_due_to_error = 1 -- 13.12.2020 (?!)
    ) then
    begin
        -- CORE-4483. "Changed data not visible in WHEN-section if exception
        -- occured inside SP that has been called from this code" ==> last record
        -- in tmp$perf_log that has been added in SP_ADD_PERF_LOG which has been
        -- called at the START point of this SP CALLER, will be backed out (REMOVED!)
        -- when exception occurs later in the intermediate point of caller, so
        -- HERE we get tmp$perf_log WITHOUT last record!
        -- 10.01.2015: replaced 'update' with 'update or insert': record in
        -- tmp$perf_log can be 'lost' in case of exc in caller before we come
        -- in this SP (sp_cancel_client_order => sp_lock_selected_doc).
        v_last_beg = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_BEG');
        v_last_end = cast('now' as timestamp);
        v_last_info = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_INFO');

        update tmp$perf_log t
        set
            fb_gdscode = :a_gdscode,
            info = :a_info, --  coalesce( :v_last_info, '<null-1>'),
            exc_unit = '#', -- exc_unit: direct CALLER of this SP is the SOURCE of raised exception
            dts_end = :v_last_end,
            elapsed_ms = datediff(millisecond from :v_last_beg to :v_last_end)
        where
            t.unit = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_UNIT')
            and t.trn_id = current_transaction
            and dts_end is NULL; -- index key: UNIT,TRN_ID,DTS_END

        if ( row_count = 0 ) then
            insert into tmp$perf_log(
                 unit
                ,fb_gdscode
                ,info
                ,exc_unit
                ,dts_beg
                ,dts_end
                ,elapsed_ms
                ,trn_id
            ) values (
                 :a_caller
                ,:a_gdscode
                ,:a_info --- coalesce( :v_last_info, '<null-2>')
                ,'#' -- ==> module :a_caller IS the source of raised exception
                ,:v_last_beg
                ,:v_last_end
                ,datediff(millisecond from :v_last_beg to :v_last_end)
                ,current_transaction
            );

        -- before 10.01.2015:
        -- update tmp$perf_log set ... where t.unit = :a_caller and and t.trn_id = current_transaction and dts_end is NULL;
        rdb$set_context('USER_TRANSACTION','TPLOG_LAST_UNIT', null);

        -- Save uncommitted data from tmp$perf_log to perf_log (via autonom. tx):
        -- NB: All records in GTT tmp$perf_log are visible ONLY at the "deepest" point
        -- when exc` occured. If SP_03 add records to tmp$perf_log and then raises exc
        -- then all its callers (SP_00==>SP_01==>SP_02) will NOT see these record because
        -- these changes will be rolled back when exc. comes into these caller.
        -- So, we must flush records from GTT to fixed table only in the "deepest" point,
        -- i.e. just in that SP where exc raises.
        execute procedure sp_flush_perf_log_on_abend(
            rdb$get_context('USER_TRANSACTION','LOG_PERF_STARTED_BY'), -- unit which start this job
            a_caller,
            a_gdscode,
            a_info, -- info for analysis
            a_exc_info -- info about user-defined or standard e`xception which occured now
        );

    end --  a_caller = v_last_unit 

    -- ########################   H A L T   T E S T   ######################
    if ( a_halt_due_to_error = 1 ) then
    begin
        execute procedure sp_halt_on_error('1', a_gdscode); -- '1' ==> unexpected test finish due to PK/FK violation or call from SRV_FIND_QD_QS_MISM
        if ( ( select result from fn_halt_sign( :a_gdscode ) ) = 1 ) then -- 27.07.2014 1003
        begin
             execute procedure zdump4dbg;
        end
    end
    -- #####################################################################

end

^ -- sp_add_to_abend_log

-- moved here 19.09.2020: code was changed to be compatible with 2.5.
create or alter procedure srv_recalc_idx_stat returns(
    tab_name dm_dbobj,
    idx_name dm_dbobj,
    elapsed_ms int
)
as
    declare msg dm_info;
    declare v_semaphore_id type of dm_idb;
    declare v_deferred_to_next_time smallint = 0;
    declare v_dummy bigint;
    declare idx_stat_befo double precision;
    declare v_gdscode int = null;
    declare v_this dm_dbobj = 'srv_recalc_idx_stat';
    declare v_start timestamp;
    declare c_semaphores cursor for ( select id from semaphores s where s.task = :v_this rows 1);
begin

    -- Refresh index statistics for most changed tables.
    -- Needs to be run in regular basis otherwise ineffective plans
    -- can be generated when doing inner joins!

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    -- Use locking record from `semaphores` table to synchronize access to this
    -- code:
    begin
        v_semaphore_id = null;
        open c_semaphores;
        while (1=1) do
        begin
            fetch c_semaphores into v_semaphore_id;
            if ( row_count = 0 ) then
                exception ex_record_not_found;
            update semaphores set id = id, dts = 'now'
            where current of c_semaphores;
            leave;
        end
        close c_semaphores;
    when any do
        -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
        -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
        -- catched it's kind of exception!
        -- 1) tracker.firebirdsql.org/browse/CORE-3275
        --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
        -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
        begin
            if ( (select result from fn_is_lock_trouble(gdscode)) = 1 ) then
                begin
                    -- concurrent_transaction ==> if select for update failed;
                    -- deadlock ==> if attempt of UPDATE set id=id failed.
                    v_deferred_to_next_time = 1;
                    v_gdscode = gdscode;
                end
            else
                exception; -- ::: nb ::: anonimous but in when-block!
        end
    end

    if ( v_deferred_to_next_time = 1 ) then
    begin
       -- Info to be stored in context var. A`DD_INFO, see below call of sp_add_to_abend_log (in W`HEN ANY section):
        msg = 'can`t lock semaphores.id='|| coalesce(v_semaphore_id,'<?>') ||', deferred'; --  current unit: srv_recalc_idx_stat
        exception ex_cant_lock_semaphore_record ( select result from sys_stamp_exception('ex_cant_lock_semaphore_record', :msg) );
    end

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    for
        select ri.rdb$relation_name, ri.rdb$index_name, ri.rdb$statistics
        from rdb$indices ri
        where
            coalesce(ri.rdb$system_flag,0)=0
            -- make recalc only for most used tables:
            and ri.rdb$relation_name in
            (
                 'DOC_DATA'
                ,'DOC_LIST'
                ,'QDISTR'
                ,'QSTORNED'
                ,'PDISTR'
                ,'PSTORNED'
                ,'XQD_1000_1200'
                ,'XQD_1000_3300'
                ,'XQD_1200_2000'
                ,'XQD_2000_3300'
                ,'XQD_2100_3300'
                ,'XQD_3300_3400'
                ,'XQS_1000_1200'
                ,'XQS_1000_3300'
                ,'XQS_1200_2000'
                ,'XQS_2000_3300'
                ,'XQS_2100_3300'
                ,'XQS_3300_3400'
            )
        order by ri.rdb$relation_name, ri.rdb$index_name
    into
        tab_name, idx_name, idx_stat_befo
    do begin
        -- Check that table `ext_stoptest` (external text file) is EMPTY,
        -- otherwise raises ex`ception to stop test:
        execute procedure sp_check_to_stop_work;

        execute procedure sp_add_perf_log(1, v_this||'_'||idx_name);

        v_start='now';

        execute statement( 'set statistics index '||idx_name )
        with autonomous transaction  -- again since 27.11.2015 (commit for ALL indices at once is too long for huge databases!)
        ;

        elapsed_ms = datediff(millisecond from v_start to cast('now' as timestamp)); -- 15.09.2015

        execute procedure sp_add_perf_log(0, v_this||'_'||idx_name,null,tab_name, idx_stat_befo);
        suspend;
    end

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this, v_gdscode);

when any do
    begin
        -- NB: proc sp_add_to_abend_log will set rdb$set_context('USER_SESSION','A`DD_INFO', msg)
        -- in order to show this additional info in ISQL log after operation will finish:
        execute procedure sp_add_to_abend_log(
            msg, -- ==> context var. ADD_INFO will be = "can`t lock semaphores.id=..., deferred" - to be shown in ISQL log
            gdscode,
            null,
            v_this
        );

        --#######
        exception; -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end
^ -- srv_recalc_idx_stat


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
    if ( rdb$get_context('SYSTEM','ENGINE_VERSION') NOT similar to ('2.5.[0-9]|3.[0-9].[0-9]') 
         and exists( select * from rdb$relations r where r.rdb$relation_name = upper('rdb$config') )
       ) then
        begin
            -- 4.0 and above: one may use RDB$CONFIG table for get actual config
            -- parameters, including server mode.
            -- NOTE: though this was appeared in 4.0.0.2260 (~nov-2010), date of
            -- database creation does not matter: this table WILL be avaliable also.
            execute statement (
                'select g.rdb$config_value, rdb$get_context(''SYSTEM'',''NETWORK_PROTOCOL'') as net_protocol '
                || ' from rdb$config g '
                || ' where g.rdb$config_name = ? '
            ) ( 'ServerMode' )
            into fb_arch, att_protocol; -- 'Super' / 'SuperClassic' / 'Classic'; 'TCPv4' / 'TCPv6' / 'WNET' / 'XNET' / NULL
            if ( att_protocol is null ) then
                fb_arch = 'Embedded';
            else if ( fb_arch = 'Super' ) then
                fb_arch = 'SuperServer';
        end

    else -- OLD way for 2.5, 3.0 and 4.0 (before 20.11.2020)
        begin
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


create or alter procedure sp_get_test_time_dts
returns(
    test_time_dts_beg timestamp,
    test_time_dts_end timestamp,
    test_intervals int
) as
begin
    test_time_dts_beg = rdb$get_context('USER_SESSION','PERF_WATCH_BEG');
    test_time_dts_end = rdb$get_context('USER_SESSION','PERF_WATCH_END');

    if ( test_time_dts_beg is null ) then
    begin
        -- this record is added in 1run_oltp_emul.bat before FIRST attach
        -- will begin it's work:
        -- PLAN (P ORDER PERF_LOG_DTS_BEG_DESC INDEX (PERF_LOG_UNIT))
        select p.dts_beg, p.dts_end
        from perf_log p
        where 
            p.unit = 'perf_watch_interval'
            -- and p.info containing 'active'
        order by dts_beg + 0 desc -- !! 24.09.2014, speed !! (otherwise dozen fetches!)
        rows 1
        into test_time_dts_beg, test_time_dts_end;

        rdb$set_context('USER_SESSION','PERF_WATCH_BEG', test_time_dts_beg);
        rdb$set_context('USER_SESSION','PERF_WATCH_END', test_time_dts_end);
    end

    test_intervals = cast( rdb$get_context('USER_SESSION','TEST_INTERVALS') as int); -- taken from config
    if ( test_intervals is null ) then
    begin
        select s.svalue from settings s where s.mcode = upper('test_intervals') 
        into test_intervals;
        rdb$set_context('USER_SESSION','TEST_INTERVALS', test_intervals);
    end

    suspend;

end
^ -- sp_get_test_time_dts

create or alter procedure report_perf_total
returns (
    business_action dm_info,
    avg_times_per_minute numeric(12,2),
    avg_elapsed_ms integer,
    successful_times_done integer)
AS
declare v_sort_prior int;
    declare v_overall_performance double precision;
    declare v_all_minutes int;
    declare v_test_time_dts_beg timestamp;
    declare v_test_time_dts_end timestamp;
    declare v_this dm_dbobj = 'srv_mon_perf_total';
begin
    -- Report. Estimating OVERALL performance: obtain number of SUCCESSULLY
    -- finished business operations per minute for whole test_time phase.
    -- 18.03.2019: refactored, using v_perf_agg instead of huge perf_split_NN table(s).

    select p.test_time_dts_beg, p.test_time_dts_end
    from sp_get_test_time_dts p
    into v_test_time_dts_beg, v_test_time_dts_end;

    delete from tmp$perf_log p  where p.stack = :v_this;

    insert into tmp$perf_log(
        unit
        ,info  -- business_ops.info
        ,id    -- sort_prior
        ,aux1  -- successful_times_done
        ,aux2  -- successful_avg_ms
        ,stack -- v_this
    )
    with
    p as(
        select
            g.unit
            ,sum( g.total_cnt ) as successful_times_done
            ,1.00 * cast( sum( g.total_ms ) / nullif(sum( g.total_cnt ),0) as numeric(12,2) ) as successful_avg_ms
        from business_ops p
        join v_perf_agg g on p.unit = g.unit
        where
            g.dts_interval > 0 and
            -- we must take in account only units which finished with SUCCESS, i.e. fb_gdscode is NULL.
            g.fb_gdscode is null
        group by g.unit
    )
    select
        b.unit
        ,b.info
        ,b.sort_prior
        ,p.successful_times_done
        ,p.successful_avg_ms
        ,:v_this
    from business_ops b
    left join p on b.unit = p.unit;

    v_all_minutes = nullif(datediff( minute from v_test_time_dts_beg to v_test_time_dts_end ),0);

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
                ,avg(aux2) as avg_elapsed_ms        -- for ALL business units
                ,sum(aux1) as successful_times_done -- for ALL business units
            from tmp$perf_log p
            where p.stack = :v_this

            UNION ALL
            
            select
                 p.id as sort_prior
                ,p.info as business_action
                ,1.00 * aux1 / maxvalue( 1, :v_all_minutes ) as avg_times_per_minute
                ,aux2 as avg_elapsed_ms        -- line for some business op
                ,aux1 as successful_times_done -- line for some business op
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

end

^ -- report_perf_total


create or alter procedure report_perf_dynamic
returns (
     interval_no smallint
    ,cnt_ok_per_minute int
    ,cnt_all int
    ,cnt_ok int
    ,cnt_err int
    ,err_prc numeric(12,2)
    ,interval_beg timestamp
    ,interval_end timestamp
)
as
    declare v_test_time_dts_beg timestamp;
    declare v_test_time_dts_end timestamp;
    declare v_intervals_number smallint;
    declare v_sec_per_one_interval double precision;
    declare v_this dm_dbobj = 'srv_mon_perf_dynamic';
begin

    -- Get performance separately for each of 1...N time intervals
    -- in order to see how it changed in DYNAMIC.

    select p.test_time_dts_beg, p.test_time_dts_end, p.test_intervals
    from sp_get_test_time_dts p
    into v_test_time_dts_beg, v_test_time_dts_end, v_intervals_number;

    -- v_sec_per_one_interval = 1 + datediff(second from v_test_time_dts_beg to v_test_time_dts_end) / v_intervals_number;
    v_sec_per_one_interval = maxvalue(1, 1.00 * datediff(second from v_test_time_dts_beg to v_test_time_dts_end) / v_intervals_number );

    for
        select
             interval_no
            ,60 * cnt_ok / nullif(:v_sec_per_one_interval,0) as cnt_ok_per_minute
            ,cnt_ok + cnt_err as cnt_all
            ,cnt_ok     -- aux1
            ,cnt_err    -- aux2
            ,100.00 * cnt_err /  nullif(cnt_ok + cnt_err, 0) as err_prc
            ,dateadd( (interval_no-1) * :v_sec_per_one_interval + 1 second to :v_test_time_dts_beg ) as interval_beg
            ,dateadd( interval_no * :v_sec_per_one_interval second to :v_test_time_dts_beg ) as interval_end
        from (
            select
                 g.dts_interval as interval_no
                ,sum( iif( g.fb_gdscode is null, g.total_cnt, 0) ) cnt_ok
                ,sum( iif( g.fb_gdscode is NOT null, g.total_cnt, 0) ) cnt_err
                ,sum( iif( g.fb_gdscode is null, g.total_ms, null) ) successful_sum_ms
            from business_ops b
            join v_perf_agg g on b.unit = g.unit
            where g.dts_interval > 0
            group by g.dts_interval
        ) t
        into
                 interval_no
                ,cnt_ok_per_minute
                ,cnt_all
                ,cnt_ok
                ,cnt_err
                ,err_prc
                ,interval_beg
                ,interval_end
    do
        suspend;

end

^ -- report_perf_dynamic

create or alter procedure report_perf_detailed
returns (
    unit type of dm_unit
   ,cnt_all integer
   ,cnt_ok integer
   ,cnt_err integer
   ,err_prc numeric(6,2)
   ,ok_min_ms integer
   ,ok_max_ms integer
   ,ok_avg_ms integer
   ,cnt_lk_confl integer
   ,cnt_user_exc integer
   ,cnt_chk_viol integer
   ,cnt_unq_viol integer
   ,cnt_fk_viol integer
   ,cnt_stack_trc integer -- 335544842, 'stack_trace': appears at the TOP of stack in 3.0 SC (strange!)
   ,cnt_zero_gds integer  -- 03.10.2014: core-4565 (gdscode=0 in when-section! 3.0 SC only)
   ,cnt_other_exc integer
)
as
    declare v_test_time_dts_beg timestamp;
    declare v_test_time_dts_end timestamp;
    declare v_this dm_dbobj = 'srv_mon_perf_dynamic';
begin
    -- SP for detailed performance analysis: count of operations
    -- (NOT only business ops; including BOTH successful and failed ones),
    -- count of errors (including by their types)
    -- Mnemonic names for ISC-code see in: src\include\gen\iberror.h

    select p.test_time_dts_beg, p.test_time_dts_end
    from sp_get_test_time_dts p
    into v_test_time_dts_beg, v_test_time_dts_end;

    for
        with
        c as (
            select
                 pg.unit
                ,sum( pg.total_cnt ) as cnt_all
                ,sum( iif( pg.fb_gdscode > 0, 0, 1 ) * pg.total_cnt ) as cnt_ok
                ,sum( iif( pg.fb_gdscode > 0, 1, 0 ) * pg.total_cnt ) as cnt_err
                ,min( iif( pg.fb_gdscode > 0, null, 1) * pg.min_ms ) ok_min_ms
                ,max( iif( pg.fb_gdscode > 0, null, 1) * pg.max_ms ) ok_max_ms
                ,sum( iif( pg.fb_gdscode > 0, 0, 1 ) * pg.total_ms ) successful_sum_ms
                ,sum( iif(pg.fb_gdscode in( 335544347, 335544558 ), pg.total_cnt, 0 ) ) cnt_chk_viol    -- isc_not_valid, isc_check_constraint
                ,sum( iif(pg.fb_gdscode in( 335544665, 335544349 ), pg.total_cnt, 0 ) ) cnt_unq_viol    -- isc_unique_key_violation, isc_no_dup
                ,sum( iif(pg.fb_gdscode in( 335544466, 335544838, 335544839 ), pg.total_cnt, 0 ) ) cnt_fk_viol -- isc_foreign_key, isc_foreign_key_target_doesnt_exist, isc_foreign_key_references_present
                ,sum( iif(pg.fb_gdscode in( 335544345, 335544878, 335544336, 335544451 ), pg.total_cnt, 0 ) ) cnt_lk_confl -- isc_lock_conflict, isc_concurrent_transaction, isc_deadlock, isc_update_conflict
                ,sum( iif(pg.fb_gdscode = 335544517, pg.total_cnt, 0) ) cnt_user_exc                    -- isc_except
                ,sum( iif(pg.fb_gdscode = 335544842, pg.total_cnt, 0) ) cnt_stack_trc                   -- isc_stack_trace
                ,sum( iif(pg.fb_gdscode = 0, pg.total_cnt, 0) ) cnt_zero_gds
                ,sum( iif( pg.fb_gdscode
                             in (
                                    335544347, 335544558,
                                    335544665, 335544349,
                                    335544466, 335544838, 335544839,
                                    335544345, 335544878, 335544336, 335544451,
                                    335544517,
                                    335544842,
                                    0
                                )
                              ,0
                              ,coalesce( sign(pg.fb_gdscode), 0) * pg.total_cnt
                           )
                       ) cnt_other_exc
            from v_perf_agg pg
            where
                pg.total_ms >= 0 and  -- 24.09.2014: prevent from display in result 'sp_halt_on_error', 'perf_watch_interval' and so on
                pg.dts_interval > 0 and
                pg.unit not starting with 'srv_recalc_idx_stat_' -- not interesting about time that was spent for reindxing of some table
            group by
                pg.unit
        )
        select 
            unit
           ,cnt_all
           ,cnt_ok
           ,cnt_err
           ,100.00 * cnt_err / nullif(cnt_all,0) as err_prc
           ,ok_min_ms
           ,ok_max_ms
           ,1.00 * successful_sum_ms / nullif(cnt_ok, 0) as ok_avg_ms
           ,cnt_chk_viol
           ,cnt_unq_viol
           ,cnt_fk_viol
           ,cnt_lk_confl
           ,cnt_user_exc
           ,cnt_stack_trc
           ,cnt_zero_gds
           ,cnt_other_exc
        from c
        into
            unit
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
    do
        suspend;

end

^ -- report_perf_detailed

-- old name: s`rv_mon_business_perf_with_exc
create or alter procedure report_business_perf_with_exc as
begin
    -- not used ; todo: remove it.
end

^ -- report_business_perf_with_exc

create or alter procedure report_exceptions
returns (
    fb_gdscode int
    ,fb_mnemona type of column fb_errors.fb_mnemona
    ,unit type of dm_unit
    ,cnt int
)
as
begin

    for
        select
            p.fb_gdscode
            ,e.fb_mnemona
            ,p.unit
            ,sum( p.total_cnt ) cnt
        from v_perf_agg p
        LEFT -- ::: NB ::: some exceptions can missing in fb_errors when it becomes obsolete
            join fb_errors e on p.fb_gdscode = e.fb_gdscode
        where
            p.fb_gdscode is not null
            and p.exc_unit='#' -- 10.01.2015, see sp_add_to_abend_log: take in account only those units where exception occured, and skip callers of them
        group by
            p.fb_gdscode
            ,e.fb_mnemona
            ,p.unit
    into
       fb_gdscode, fb_mnemona, unit, cnt
    do
        suspend;
end

^ -- report_exceptions

-- 26.03.2019
create or alter procedure report_perf_per_minute
returns (
        test_phase_name varchar(20)
       ,minutes_passed int
       ,perf_score int
       ,distinct_workers smallint
       ,pool_active smallint
       ,pool_idle smallint
)
as
    declare v_test_time_dts_beg timestamp;
    declare v_test_time_dts_end timestamp;
    declare v_warm_time int;
    declare v_this dm_dbobj = 'report_perf_est_per_minute';
begin

    select p.test_time_dts_beg, p.test_time_dts_end
    from sp_get_test_time_dts p
    into v_test_time_dts_beg, v_test_time_dts_end;

    select s.svalue
    from settings s
    where s.working_mode='COMMON' and s.mcode = 'WARM_TIME'
    into v_warm_time;

    delete from tmp$perf_est_whole where 1=1;
    insert into tmp$perf_est_whole(test_phase_sign, earliest_cnt_for_phase)
    select
         sign( datediff(millisecond from p.test_time_dts_beg to e.dts) )
         -- here we have to find number of success_count for EARLIEST moment of each phase:
        ,cast( substring( min( lpad(e.id, 18,' ') || ' ' || e.success_count ) from 20 ) as int )
    from v_perf_estimated e
    cross join sp_get_test_time_dts p
    group by 1;

    --------------------------------------
    for
        select
             iif( u.test_phase_sign < 0, 'WARM_TIME', 'TEST_TIME' ) as test_phase_name
            ,u.minutes_passed
            ,( u.last_cnt_per_minute - x.earliest_cnt_for_phase ) / nullif( u.minutes_passed, 0 ) perf_score
            ,u.distinct_workers
            ,u.pool_active
            ,u.pool_idle
        from (
            select
                 sign( datediff(millisecond from :v_test_time_dts_beg to e.dts) ) as test_phase_sign
                ,iif(  :v_test_time_dts_beg > e.dts
                      ,:v_warm_time + e.minute_since_test_start
                      ,e.minute_since_test_start
                     ) as minutes_passed
                ,max(e.success_count) last_cnt_per_minute
                ,avg(distinct e.worker_id) distinct_workers -- 27.11.2020; todo: sync .sh with with this!
                ,avg(e.pool_active) as pool_active
                ,avg(e.pool_idle) as pool_idle
            from v_perf_estimated e
            group by 1,2
        ) u
        join tmp$perf_est_whole x on u.test_phase_sign = x.test_phase_sign
        where u.minutes_passed <> 0
        order by u.test_phase_sign, u.minutes_passed
    into
        test_phase_name
       ,minutes_passed
       ,perf_score
       ,distinct_workers
       ,pool_active
       ,pool_idle
    do
        suspend;

end

^ -- report_perf_per_minute


create or alter procedure report_perf_trace (
    a_intervals_number smallint default 20,
    a_last_hours smallint default 0,
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
    declare v_test_time_dts_beg timestamp;
    declare v_test_time_dts_end timestamp;
    declare v_sec_per_one_interval int;
begin

    -- Report based on result of parsing TRACE log which was started by
    -- ISQL session #1 when config parameter trc_unit_perf = 1.
    -- Data for each business operation are displayed separately because
    -- they depends on execution plans and can not be compared each other.
    -- We have to analyze only RATIOS between reads/fetches and writes/marks,
    -- and also values of speed (fetches and marks per second) instead of
    -- absolute their values.

    -- 17.02.2019: this SP was replaced with report_perf_trace_pivot
    -- but its code can be useful for some other purposes. Do not kill it.

    a_intervals_number = iif( a_intervals_number <= 0, 20, a_intervals_number);
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    select p.test_time_dts_beg, p.test_time_dts_end
    from sp_get_test_time_dts p
    into v_test_time_dts_beg, v_test_time_dts_end;
    if ( a_last_hours > 0 or a_last_mins > 0 ) then
        v_test_time_dts_beg =
            maxvalue(   v_test_time_dts_beg,
                        dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to v_test_time_dts_end )
                    );

    v_sec_per_one_interval = 1 + datediff(second from v_test_time_dts_beg to v_test_time_dts_end) / a_intervals_number;

    for
        with
        p as(
            select
                t.unit
                ,b.info
                ,1+cast(datediff(second from :v_test_time_dts_beg to t.dts_end) / :v_sec_per_one_interval as int) as interval_no
                ,count(*) cnt_success
                ,avg( 1000 * t.fetches / nullif(t.elapsed_ms,0) ) fetches_per_second
                ,avg( 1000 * t.marks / nullif(t.elapsed_ms,0) ) marks_per_second
                ,avg( 100.00 * t.reads/nullif(t.fetches,0) ) reads_to_fetches_prc
                ,avg( 100.00 * t.writes/nullif(t.marks,0) ) writes_to_marks_prc
                ,min( :v_test_time_dts_beg ) as first_job_start_dts
                ,min( :v_sec_per_one_interval ) as sec_for_one_interval
            from trace_stat t
            join business_ops b on t.unit = b.unit
            where
                t.success = 1
                and t.dts_end between :v_test_time_dts_beg and :v_test_time_dts_end
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

^ -- report_perf_trace

-- old name: s`rv_mon_perf_trace_pivot
create or alter procedure report_perf_trace_pivot (
    a_intervals_number smallint default 20,
    a_last_hours smallint default 0,
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
    declare v_test_time_dts_beg timestamp;
    declare v_test_time_dts_end timestamp;
    declare v_sec_per_one_interval int;
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

    select p.test_time_dts_beg, p.test_time_dts_end
    from sp_get_test_time_dts p
    into v_test_time_dts_beg, v_test_time_dts_end;
    if ( a_last_hours > 0 or a_last_mins > 0 ) then
        v_test_time_dts_beg =
            maxvalue(   v_test_time_dts_beg,
                        dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to v_test_time_dts_end )
                    );

    v_sec_per_one_interval = 1 + datediff(second from v_test_time_dts_beg to v_test_time_dts_end) / a_intervals_number;


    for
        with recursive
        n as (
            select 1 i from rdb$database
            union all
            select n.i+1 from n where n.i+1<=4
        )
        ,p as(
            select
                t.unit
                ,b.info
                ,1+cast(datediff(second from :v_test_time_dts_beg to t.dts_end) / :v_sec_per_one_interval as int) as interval_no
                ,count(*) cnt_success
                ,avg( 1000 * t.fetches / nullif(t.elapsed_ms,0) ) fetches_per_second
                ,avg( 1000 * t.marks / nullif(t.elapsed_ms,0) ) marks_per_second
                ,avg( 100.00 * t.reads/nullif(t.fetches,0) ) reads_to_fetches_prc
                ,avg( 100.00 * t.writes/nullif(t.marks,0) ) writes_to_marks_prc
                ,min( :v_test_time_dts_beg ) as first_job_start_dts
                ,min( :v_sec_per_one_interval ) as sec_for_one_interval
            from trace_stat t
            join business_ops b on t.unit = b.unit
            where
                t.success = 1
                and t.dts_end between :v_test_time_dts_beg and :v_test_time_dts_end
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

^ -- report_perf_trace_pivot


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

create or alter procedure srv_fill_mon_cache_worker
returns (
     inserted_dbkey dm_dbkey
    ,meta_cache_size type of column mon_cache_memory.meta_cache_size
    ,statements_running_cnt type of column mon_cache_memory.page_cache_operating_stm_cnt
    ,statements_stalled_cnt type of column mon_cache_memory.data_transfer_paused_stm_cnt
)
as
    declare v_dts timestamp;
begin
    -- called only from SP srv_fill_mon_cache_memory.
    -- Code was separated from there in order to have ability to invoke it
    -- either by static PSQL (common way) or using ES/EDS (when config 'use_es'>0)

    v_dts = cast('now' as timestamp);

    -- Result of subtraction: (m.memo_used_att - (memo_used_trn + memo_used_stm)) equals to:
    -- 1) when pg_cache_type='dedicated' (SC, CS) then SUM of page cache and metadata cache
    -- 2) when pg_cahce_type='shared' (SS) then only metadata cache
    insert into mon_cache_memory (
        pg_buffers
        ,pg_size
        ,pg_cache_type -- 'dedicated' (SC/CS) or 'shared' (SS); just for info
        ,page_cache_size
        ,meta_cache_size
        ,memo_used_all -- 27.05.2020
        ,memo_allo_all -- 27.05.2020
        ,memo_used_att
        ,memo_used_trn
        ,memo_used_stm
        ,total_attachments_cnt
        ,active_attachments_cnt
        ,page_cache_operating_stm_cnt
        ,data_transfer_paused_stm_cnt
        ,dts
        ,elap_ms -- see SP report_cache_dynamic, column: 'measurement_elapsed_ms'
    )
    select
        d.mon$page_buffers pg_buffers
        ,d.mon$page_size pg_size
        ,iif(m.memo_db_used = 0, 'dedicated', 'shared') pg_cache_type
        ,d.mon$page_buffers * d.mon$page_size * iif( m.memo_db_used = 0, total_attachments_cnt, 1 ) as page_cache_size
        ,m.memo_used_att - (memo_used_trn + memo_used_stm) - iif( m.memo_db_used = 0, d.mon$page_buffers * d.mon$page_size * total_attachments_cnt, 0)  as meta_cache_size
        ,m.memo_db_used
        ,m.memo_db_allo
        ,m.memo_used_att
        ,m.memo_used_trn
        ,m.memo_used_stm
        ,m.total_attachments_cnt
        ,m.active_attachments_cnt
        ,m.page_cache_operating_stm_cnt
        ,m.data_transfer_paused_stm_cnt
        ,:v_dts
        ,datediff(millisecond from :v_dts to cast('now' as timestamp)) -- moved here 10.12.2020 from SP srv_fill_mon_cache_memory
    from (
        select
            sum( iif( u.stat_gr = 0, m.mon$memory_used, 0) ) memo_db_used -- SC/CS: 0; SS: >0
           ,sum( iif( u.stat_gr = 0, m.mon$memory_allocated, 0) ) memo_db_allo -- SC/CS: 0; SS: >0
           ,sum( iif( u.stat_gr = 1, m.mon$memory_used, 0) ) memo_used_att
           ,sum( iif( u.stat_gr = 2, m.mon$memory_used, 0) ) memo_used_trn
           ,sum( iif( u.stat_gr = 3, m.mon$memory_used, 0) ) memo_used_stm
           ,sum( iif( u.stat_gr = 1, 1, 0 ) ) total_attachments_cnt
           ,sum( iif( u.stat_gr = 1 and u.state = 1, 1, 0 ) ) active_attachments_cnt
           ,sum( iif( u.stat_gr = 2 and u.state = 1, 1, 0 ) ) active_transactions_cnt
           ,sum( iif( u.stat_gr = 3 and u.state = 1, 1, 0 ) ) page_cache_operating_stm_cnt --  server_side_run_stm_cnt
           ,sum( iif( u.stat_gr = 3 and u.state = 2, 1, 0 ) ) data_transfer_paused_stm_cnt -- data_transf_run_stm_cnt
        from mon$memory_usage m
        join
        (
            select 0 as stat_gr, m.mon$stat_id as stat_id, null as att_id, null as state
            from mon$memory_usage m
            where m.mon$stat_group =0
            UNION ALL
            select 1 as stat_gr, a.mon$stat_id as stat_id, a.mon$attachment_id as att_id, a.mon$state as state
            from mon$attachments a
             -- added 07.05.2020, actual for SuperServer 3.x+:
             -- total_attachments_cnt must not include GC and CW
            where mon$remote_protocol is not null -- common for 2.5 and 3.x+
            -- FB 3.x+ only: a.mon$system_flag is distinct from 1
            UNION ALL
            select 2,            t.mon$stat_id, t.mon$attachment_id, t.mon$state
            from mon$transactions t
            UNION ALL
            select 3,            s.mon$stat_id, s.mon$attachment_id, s.mon$state
            from mon$statements s
            -- ?! --> where upper( s.mon$sql_text ) not similar to upper('EXECUTE[[:WHITESPACE:]]+BLOCK%')
        )  u
        on
            m.mon$stat_id = u.stat_id and
            m.mon$stat_group = u.stat_gr
    ) m
    cross join mon$database d
    returning
         rdb$db_key
        ,meta_cache_size
        ,page_cache_operating_stm_cnt
        ,data_transfer_paused_stm_cnt
    into
        inserted_dbkey
        ,meta_cache_size
        ,statements_running_cnt
        ,statements_stalled_cnt
    ;

    suspend;

end
^ -- srv_get_page_cache_info

create or alter procedure srv_fill_mon_cache_memory
returns (
    info dm_info)
as
    declare v_dts_beg timestamp;
    declare v_dbkey dm_dbkey;
    declare v_meta_cache_size bigint;
    declare v_statements_running_cnt smallint;
    declare v_statements_stalled_cnt smallint;
    declare v_ibe smallint;
    declare v_elapsed_ms int;
    declare v_lf char(1) = x'0A';
    declare v_sttm varchar(8192);
    declare v_this dm_dbobj = 'srv_fill_mon_cache_memory';
begin
    -- Top-level SP that is used when mon_unit_perf=2 and is called from "Big SQL"
    -- only by session with SID=1,
    -- There is delay = <mon_query_interval> seconds between each call of this SP
    -- (see config file, parameter 'mon_query_interval').
    -- Adds data to the table MON_CACHE_MEMORY about memory consumption.

    -- 28.05.2020: moved here as common for 2.5 and 3.x+

    v_ibe = iif( (select result from fn_remote_process) containing 'IBExpert', 1, 0);
    if ( v_ibe = 0 -- fn_remote_process() NOT containing 'IBExpert'
         and
         coalesce(rdb$get_context('USER_SESSION', 'ENABLE_MON_QUERY'), 0) = 0
       ) then
    begin
        rdb$set_context( 'USER_SESSION','MON_INFO', 'mon$_dis!'); -- to be displayed in log of 1run_oltp_emul.bat
        suspend;
        --###
        exit;
        --###
    end
    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    v_dts_beg  = 'now';

    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    v_sttm =
    q'{ execute block returns(
            v_dbkey dm_dbkey
            ,v_meta_cache_size bigint
            ,v_statements_running_cnt smallint
            ,v_statements_stalled_cnt smallint
        ) as
        begin
            -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
            -- NOTE: we have to log timestamp of point just BEFORE query that
            -- will work: datediff between this point and next firing of
            -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
            -- of IDLE state for this connect in the Ext. Conn. Pool.
            execute procedure sp_perf_eds_logging('B');

            select -- #EDS#TAG#
                inserted_dbkey
                ,meta_cache_size
                ,statements_running_cnt
                ,statements_stalled_cnt
            from srv_fill_mon_cache_worker
            into
                v_dbkey
                ,v_meta_cache_size
                ,v_statements_running_cnt
                ,v_statements_stalled_cnt
            ;

            -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
            -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
            -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
            -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
            -- for connect, so there we have TWO events: 'I' and 'A').
            --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#

            suspend;
        end
    }';
    execute statement (v_sttm)
    -- 20.11.2020
    -- If config parameter USE_ES is 2 then following line will be
    -- replaced with uncommented code for run as ES/EDS.
    -- Host and port will be taken from apropriate config parameters.
    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
    -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
    into
        v_dbkey
        ,v_meta_cache_size
        ,v_statements_running_cnt
        ,v_statements_stalled_cnt
    ;
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

    /* #ACTIVATE#IF#USE_ES_EQU_1#BEG#
    execute statement (
        'select -- #EDS#TAG#' || v_lf
        || '  inserted_dbkey '
        || '  ,meta_cache_size '
        || '  ,statements_running_cnt '
        || '  ,statements_stalled_cnt '
        || ' from srv_fill_mon_cache_worker '
    )
    into
        v_dbkey
        ,v_meta_cache_size
        ,v_statements_running_cnt
        ,v_statements_stalled_cnt
    ;
    -- #ACTIVATE#IF#USE_ES_EQU_1#END# */

    -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
    -- usual way (use_es = 0): use static PSQL code.
    select
        inserted_dbkey
        ,meta_cache_size
        ,statements_running_cnt
        ,statements_stalled_cnt
    from srv_fill_mon_cache_worker
    into
        v_dbkey
        ,v_meta_cache_size
        ,v_statements_running_cnt
        ,v_statements_stalled_cnt
    ;
    -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

    -- 10.12.2020: NOT needed here: this is done inside SP srv_fill_mon_cache_worker
    -- v_elapsed_ms = datediff(millisecond from v_dts_beg to cast('now' as timestamp));
    -- update mon_cache_memory set dts = :v_dts_beg, elap_ms = :v_elapsed_ms
    -- where rdb$db_key = :v_dbkey;

    -- meta_cache 123456789012, stm_running 12345, stm_stalled 12345
    -- NB: do not add 'elapsed_ms NNNN', it will be evaluated in execute block.
    info = 'meta_cache ' || lpad(v_meta_cache_size,12,' ')
        || ', stm_running ' || lpad(v_statements_running_cnt,5,' ')
        || ', stm_stalled ' || lpad(v_statements_stalled_cnt,4,' ')
    ;

    -- ::: NB ::: We have to limit length of this info by 80 characters, see execute block 
    -- in tmp_random_run.sql (it is recreated every test start in .bat/.sh).
    -- This message will be displayed in SID_1 log after this SP finish:
    -- *** RESULT: *** (after business operation finish)
    -- DTS          TRN            UNIT                            ELAPSED_MS MSG                  ADD_INFO
    -- ============ ============== =============================== ========== ==================== ============================================================
    -- 22:09:21.823 tra_663        srv_fill_mon_cache_memory             1234 OK, 1 rows           meta_cache 123456789012, stm_running 12345, stm_stalled 1234

    info = left(info, 80); -- this is limit for output length in execute block, see $tmpdir/tmp_random_run.sql

    rdb$set_context( 'USER_SESSION','ADD_INFO', info ); -- to be displayed in log of ISQL, SID=1

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this, null, info );

    suspend;

when any do
    begin
        rdb$set_context( 'USER_SESSION','MON_INFO', 'gds='||gdscode );
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            '',
            v_this,
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end
^ -- srv_fill_mon_cache_memory


create or alter procedure report_cache_dynamic
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
    ,memo_used_all bigint -- 27.05.2020 memory_used for DB level; actual only for SS; always zero in SC/CS
    ,memo_allo_all bigint -- 27.05.2020 memory_allocatedd for DB level; actual only for SS; always zero in SC/CS
) as
begin

    -- 02.01.2019. Called only when config parameter 'mon_unit_perf' is 2: report about memory consumption
    -- by metadata cache size, active attachments and statements in 'running' and 'stalled' state.
    -- NB: all records from table 'mon_cache_memory' are DELETED before every new test run, see 1run_oltp_emul.bat/.sh
    -- See also sp SRV_FILL_MON_CACHE_MEMORY - it is called on every iteration for SID=1 in the "Big SQL".
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
            ,m.memo_used_all
            ,m.memo_allo_all
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
        ,memo_used_all
        ,memo_allo_all
    do
        suspend;
end
^ -- report_cache_dynamic

create or alter procedure report_stat_per_units (
    a_last_hours smallint default 0,
    a_last_mins smallint default 0 )
returns (
    unit dm_unit
   ,iter_counts bigint
   ,avg_elap_ms bigint

   --- io ---
   ,avg_fetches numeric(12,2)
   ,avg_marks numeric(12,2)
   ,avg_reads numeric(12,2)
   ,avg_writes numeric(12,2)

   ----- 19.05.2020. Page cache misses (the higher the worse) -----
   ,avg_reads_to_fetches numeric(12,4)
   ,avg_writes_to_marks numeric(12,4)

   --- memory usage ---
   -- NB: these are values that was gathered at the FINAL point of
   -- business action (i.e. after it completed but before commit).
   ,avg_mem_used bigint
   ,avg_mem_alloc bigint

    -------- scans, absolute values -----------
   ,avg_seq numeric(12,2)
   ,avg_idx numeric(12,2)
   ,avg_rpt numeric(12,2)
   ,avg_bkv numeric(12,2)
   ,avg_frg numeric(12,2)
    -------------- scans, ratios --------------
   ,avg_bkv_per_rec numeric(12,4)
   ,avg_frg_per_rec numeric(12,4)
    ---------- modifications ----------
   ,avg_ins numeric(12,2)
   ,avg_upd numeric(12,2)
   ,avg_del numeric(12,2)
    ---- garbage-related processing ----
   ,avg_bko numeric(12,2)
   ,avg_pur numeric(12,2)
   ,avg_exp numeric(12,2)
   ----------------------------------------
   ,avg_locks numeric(12,2)
   ,avg_confl numeric(12,2)

/* commented 19.05.2020: can not see any reason for use of these:
   ,avg_rec_reads_sec numeric(12,2)
   ,avg_rec_dmls_sec numeric(12,2)
   ,avg_bkos_sec numeric(12,2)
   ,avg_purg_sec numeric(12,2)
   ,avg_xpng_sec numeric(12,2)
   ,avg_fetches_sec numeric(12,2)
   ,avg_marks_sec numeric(12,2)
   ,avg_reads_sec numeric(12,2)
   ,avg_writes_sec numeric(12,2)
   ,max_seq bigint
   ,max_idx bigint
   ,max_rpt bigint
   ,max_bkv bigint
   ,max_frg bigint
   ,max_bkv_per_rec numeric(12,2)
   ,max_frg_per_rec numeric(12,2)
   ,max_ins bigint
   ,max_upd bigint
   ,max_del bigint
   ,max_bko bigint
   ,max_pur bigint
   ,max_exp bigint
   ,max_fetches bigint
   ,max_marks bigint
   ,max_reads bigint
   ,max_writes bigint
   ,max_locks bigint
   ,max_confl bigint
   ,job_beg varchar(16)
   ,job_end varchar(16)
*******/

) as
    declare v_test_time_dts_beg timestamp;
    declare v_test_time_dts_end timestamp;
begin

    a_last_hours = abs( a_last_hours );
    a_last_mins = coalesce(a_last_mins, 0);
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    select p.test_time_dts_beg, p.test_time_dts_end
    from sp_get_test_time_dts p
    into v_test_time_dts_beg, v_test_time_dts_end;
    if ( a_last_hours > 0 or a_last_mins > 0 ) then
        v_test_time_dts_beg =
            maxvalue(   v_test_time_dts_beg,
                        dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to v_test_time_dts_end )
                    );

    for
        -- 29.08.2014: data from measuring statistics per each unit
        -- (need FB rev. >= 60013: new mon$ counters were introduced, 28.08.2014)
        -- 25.01.2015: added rec_locks, rec_confl.
        -- 06.02.2015: reorder columns, made all `max` values most-right
        -- 17.05.2020: changed return type for all AVG* counters from bigint to numeric(12,2)
        select
             m.unit
            -------------- count, speed -------------
            ,count(*) iter_counts
            ,avg(m.elapsed_ms) avg_elap_ms
            --------------- io -----------------
            ,avg(1.00 * m.pg_fetches) avg_fetches
            ,avg(1.00 * m.pg_marks) avg_marks
            ,avg(1.00 * m.pg_reads) avg_reads
            ,avg(1.00 * m.pg_writes) avg_writes
            -------------- page cache usage -----------
            ,avg( 1.0000 * m.pg_reads / nullif(m.pg_fetches,0) ) as avg_reads_to_fetches
            ,avg( 1.0000 * m.pg_writes / nullif(m.pg_marks,0) ) as avg_writes_to_marks
            ----- memory usage  -----
            -- ATTENTION: counters in the MON$MEMORY_USAGE are *not* cumulative,
            -- their values are like 'snapshots' and represent current memory consumption.
            -- Delta between start and end of some query has no sense, we have to get only
            -- value that was gathered at the FINAL of business action (i.e. after it ended but before commit).
            -- See SP SRV_FILL_MON: we take in account only values that was at the END of action and ignore
            -- starting values (with t.mult=-1): select ... max( nullif(t.mult,-1) * t.mem_...) ...
            ,avg(m.mem_used) as avg_mem_used -- avg value of mem_used that was gathered only at the FINAL point of each business action
            ,avg(m.mem_alloc) as avg_mem_alloc -- avg value of mem_alloc that was gathered only at the FINAL point of each business action
            -------- scans, absolute values -----------
            ,avg(1.00 * m.rec_seq_reads) avg_seq
            ,avg(1.00 * m.rec_idx_reads) avg_idx
            ,avg(1.00 * m.rec_rpt_reads) avg_rpt
            ,avg(1.00 * m.bkv_reads) avg_bkv
            ,avg(1.00 * m.frg_reads) avg_frg
            -------------- scans, ratios --------------
            ,avg(1.0000 * m.bkv_per_seq_idx_rpt) avg_bkv_per_rec
            ,avg(1.0000 * m.frg_per_seq_idx_rpt) avg_frg_per_rec
            ---------- modifications ----------
            ,avg(1.00 * m.rec_inserts) avg_ins
            ,avg(1.00 * m.rec_updates) avg_upd
            ,avg(1.00 * m.rec_deletes) avg_del
            ,avg(1.00 * m.rec_backouts) avg_bko
            ,avg(1.00 * m.rec_purges) avg_pur
            ,avg(1.00 * m.rec_expunges) avg_exp
            ----------- locks and conflicts ----------
            ,avg(1.00 * m.rec_locks) avg_locks
            ,avg(1.00 * m.rec_confl) avg_confl

/* commented 19.05.2020: can not see any reason for use of these:
            ,avg(1000.00 * ( (m.rec_seq_reads + m.rec_idx_reads + m.bkv_reads ) / nullif(m.elapsed_ms,0))  ) avg_rec_reads_sec
            ,avg(1000.00 * ( (m.rec_inserts + m.rec_updates + m.rec_deletes ) / nullif(m.elapsed_ms,0))  ) avg_rec_dmls_sec
            ,avg(1000.00 * ( m.rec_backouts / nullif(m.elapsed_ms,0))  ) avg_bkos_sec
            ,avg(1000.00 * ( m.rec_purges / nullif(m.elapsed_ms,0))  ) avg_purg_sec
            ,avg(1000.00 * ( m.rec_expunges / nullif(m.elapsed_ms,0))  ) avg_xpng_sec
            ,avg(1000.00 * ( m.pg_fetches / nullif(m.elapsed_ms,0)) ) avg_fetches_sec
            ,avg(1000.00 * ( m.pg_marks / nullif(m.elapsed_ms,0)) ) avg_marks_sec
            ,avg(1000.00 * ( m.pg_reads / nullif(m.elapsed_ms,0)) ) avg_reads_sec
            ,avg(1000.00 * ( m.pg_writes / nullif(m.elapsed_ms,0)) ) avg_writes_sec
            --- 06.02.2015 moved here all MAX values, separate them from AVG ones: ---
            ,max(m.rec_seq_reads) max_seq
            ,max(m.rec_idx_reads) max_idx
            ,max(m.rec_rpt_reads) max_rpt
            ,max(m.bkv_reads) max_bkv
            ,max(m.frg_reads) max_frg
            ,max(m.bkv_per_seq_idx_rpt) max_bkv_per_rec
            ,max(m.frg_per_seq_idx_rpt) max_frg_per_rec
            ,max(m.rec_inserts) max_ins
            ,max(m.rec_updates) max_upd
            ,max(m.rec_deletes) max_del
            ,max(m.rec_backouts) max_bko
            ,max(m.rec_purges) max_pur
            ,max(m.rec_expunges) max_exp
            ,max(m.pg_fetches) max_fetches
            ,max(m.pg_marks) max_marks
            ,max(m.pg_reads) max_reads
            ,max(m.pg_writes) max_writes
            ,max(m.rec_locks) max_locks
            ,max(m.rec_confl) max_confl
            ,left(cast(:v_test_time_dts_beg as varchar(24)),16)
            ,left(cast(:v_test_time_dts_end as varchar(24)),16)
-- *****************/
        from mon_log m
        where m.dts between :v_test_time_dts_beg and :v_test_time_dts_end
        group by unit
    into
        unit
       ,iter_counts
       ,avg_elap_ms
       --- io ---
       ,avg_fetches
       ,avg_marks
       ,avg_reads
       ,avg_writes
       ----- 19.05.2020. Page cache usage -----
       ,avg_reads_to_fetches
       ,avg_writes_to_marks
       --- memory usage ---
       ,avg_mem_used
       ,avg_mem_alloc
        -------- scans, absolute values -----------
       ,avg_seq
       ,avg_idx
       ,avg_rpt
       ,avg_bkv
       ,avg_frg
        -------------- scans, ratios --------------
       ,avg_bkv_per_rec
       ,avg_frg_per_rec
        ---------- modifications ----------
       ,avg_ins
       ,avg_upd
       ,avg_del
       ,avg_bko
       ,avg_pur
       ,avg_exp
       ----------------------------------------
       ,avg_locks
       ,avg_confl
 

/* commented 19.05.2020: can not see any reason for use of these:
       ,max_seq
       ,max_idx
       ,max_rpt
       ,max_bkv
       ,max_frg
       ,max_bkv_per_rec
       ,max_frg_per_rec
       ,max_ins
       ,max_upd
       ,max_del
       ,max_bko
       ,max_pur
       ,max_exp
       ,max_fetches
       ,max_marks
       ,max_reads
       ,max_writes
       ,max_locks
       ,max_confl
       ,job_beg
       ,job_end
-- *****************/
    do
        suspend;
end
^ -- report_stat_per_units


-- ################################################################
-- ###         a u x i l i a r y        p r o c e d u r e s     ###
-- ################################################################

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
    ,html_doc_title varchar(50) -- 10.05.2020: string for top.document.title = '...'
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
    declare v_cpu_cores smallint;
    declare v_mem_total smallint;
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
        ,max(iif( mcode='CPU_CORES',                   svalue, null                                              ))
        ,max(iif( mcode='MEM_TOTAL',                   svalue, null                                              ))
    from (
        select s.mcode, s.svalue
        from settings s
        where s.mcode in ( 'SEPARATE_WORKERS', 'UNIT_SELECTION_METHOD', 'USED_IN_REPLICATION', 'CPU_CORES', 'MEM_TOTAL')
    )
    into v_sep_workers, v_unit_select, v_repl_involv, v_cpu_cores, v_mem_total;

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
            select iif(p.exc_unit = '9', 'FB_CRASHED', 'ABEND_GDS_' || p.fb_gdscode)
            from perf_log p
            where
                p.unit = 'sp_halt_on_error'
                and ( p.fb_gdscode >= 0
                      or 
                      exc_unit = '9' -- see 'oltp_isql_run_worker':  exc_unit='9' is reserved for crashes
                    )
            order by p.dts_beg desc
            rows 1
            into v_test_finish_state;
            -- v_test_finish_state:
            --    will remain NULL if not found ==> test finished NORMAL.
            --    'ABEND_GDS_nnnnnn' ==> critical error occured (negative remainders or PK violation, etc)
            --    'CRASHED' ==> FB has crashed during test run or after this when SID=1 attempted to change DB state to shutdown
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
        begin
            -- Use *actual* number of ISQL sessions that were participate in this test run.
            -- This case is used when final report is created AFTER test finish, from oltp_isql_run_worker.bat (.sh):
            select s.svalue
            from settings s
            where upper(s.mcode) = upper('WORKERS_COUNT')
            into v_num_of_sessions;

            if ( v_num_of_sessions is null ) then
            begin
                exception ex_record_not_found;
            end
        end
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
            || coalesce('_cpu' || v_cpu_cores, '')
            || coalesce('_ram' || v_mem_total, '')
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
                || coalesce('_cpu' || v_cpu_cores, '')
                || coalesce('_ram' || v_mem_total, '')

            ;
        end

    if ( trim(a_prefix) > '' ) then report_file = trim(a_prefix) || '-' || report_file;

    if ( trim(a_suffix) > '' ) then report_file = report_file || '-' || trim(a_suffix);

    -- 10.05.2020: extract main parameters of just finished test: score, build/FB_server_mode, FW and (if turned on) replication
    -- Example: '08958 b.33290/ss fw on repl_1'
    html_doc_title = replace(overall_perf,'score_','') || ' b.' || a_build || '/' || fb_arch || ' ' || replace(fw_setting,'_',' ') || trim(iif( v_repl_involv containing '1', 'repl_1', '' ));

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
        exception ex_bad_argument
        -- uncomment temply for 3.0+ if need
        -- using( coalesce('"'||trim(a_proc)||'"', '<null>'), 'sys_get_proc_ddl' )
        ;
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
                 when pt=-1 then 'create or alter procedure ' || trim(p_nam) || trim(iif(pq_in>0,' (',''))
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
                                'create or alter view ' || trim(v_name) || trim( iif( mode=0, ' as select',' (' ) )
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


create or alter procedure sp_get_stat returns(
    x_rows int
   ,x_mean double precision
   ,biased_std_dev double precision
   ,unbiased_std_dev double precision
   ,covar double precision
   ,skewness double precision
   ,kurtosis double precision
   ,variance_outcome varchar(100)
   ,sigma3_rule_outcome varchar(100)
   ,symmetry_outcome varchar(100)
   ,uniformity_outcome varchar(100)
   ,norm_law_outcome varchar(100)
)
as
    declare c_data cursor for ( select 1000+rand()*100 n from rdb$fields a, rdb$types b);
    declare rows_cnt double precision;
    declare rnd_val double precision;
    declare m2 double precision;
    declare m3 double precision;
    declare m4 double precision;
    declare x_min double precision;
    declare x_max double precision;
    declare delta double precision;
    declare delta_n double precision;
    declare delta_n2 double precision;
    declare term1 double precision;
    declare m_skew double precision;
    declare m_kurt double precision;
    declare skew_ratio double precision;
    declare kurt_ratio double precision;
    declare sigma3_violation smallint;
begin
    -- Get main statistics charcerictics (mean, median, cover, skewness, kurtosis) in one pass.
    -- Currently not used; probably can be useful in the future.

    rows_cnt=0;
    x_mean=0;
    m2=0;
    m3=0;
    m4=0;
    x_min = 9223372036854775807;
    x_max = -9223372036854775808;
    open c_data;
    while (2=2) do
    begin
        fetch c_data into rnd_val;
        if (row_count = 0) then
            leave;
        rows_cnt = rows_cnt + 1;
        delta = rnd_val - x_mean;
        delta_n = delta / rows_cnt;
        delta_n2 = delta_n * delta_n;
        term1 = delta * delta_n * (rows_cnt-1);
        x_mean = x_mean + delta_n;
        -- Increment sum for eval. kurtosis:
        m4 = m4 + term1 * delta_n2 * (rows_cnt * rows_cnt - 3 * rows_cnt + 3) + 6 * delta_n2 * m2 - 4 * delta_n * m3;
        -- Increment sum for eval. skewness:
        m3 = m3 + term1 * delta_n * (rows_cnt - 2) - 3 * delta_n * m2;
        -- Increment sum for eval. variance (aka dispersion):
        m2 = m2 + term1;
    
        x_min = minvalue(rnd_val, x_min);
        x_max = maxvalue(rnd_val, x_max);
    end
    close c_data;
    
    x_rows = rows_cnt;
    --
    biased_std_dev = sqrt( m2 / rows_cnt );

    --  Bessel's correction. We evaluate this only for info,
    -- it is NOT used for skewness or kurtosis.
    unbiased_std_dev = sqrt( m2 / ( rows_cnt - 1.0) );

    -- https://www.researchgate.net/post/What_is_the_acceptable_range_of_skewness_and_kurtosis_for_normal_distribution_of_data
    -- 1) The values for asymmetry and kurtosis between -2 and +2 are considered acceptable
    --    in order to prove normal univariate distribution (George & Mallery, 2010)
    -- 2) Most software packages that compute the skewness and kurtosis, also compute their standard error.
    --    Both S = skewness/SE(skewness) and K = kurtosis/SE(kurtosis)
    --    Thus, when |S| > 1.96 the skewness is significantly (alpha=5%) different from zero; the same for |K| > 1.96 and the kurtosis.
    -- 3) A rule of thumb is -1 to 1 amplitude. Nevertheless, as said by Casper you should calculate CI 95% for adequate results reporting.
    -- 4) I have also come across another rule of thumb -0.8 to 0.8 for skewness and -3.0 to 3.0 for kurtosis.


    -- If skewness = 0, the data are perfectly symmetrical. But a skewness of exactly zero is quite unlikely for real-world data,
    -- so how can you interpret the skewness number? Bulmer, M. G., Principles of Statistics (Dover,1979) - a classic - suggests this rule of thumb:
    -- If skewness is less than -1 or greater than +1, the distribution is highly skewed.
    -- If skewness is between -1 and -0.5 or between 0.5 and +1, the distribution is moderately skewed.
    -- If skewness is between -0.5 and 0.5, the distribution is approximately symmetric.

    -- NOTE. Evaluation of skewness and kurtosis uses *BIASED* std_dev,
    -- i.e. "n" rather than "n-1" in denominator.
    skewness = sqrt( rows_cnt ) * m3 / ( power(m2, 1.5) );

    /*
    A distribution with kurtosis < 0 is called platykurtic. Compared to a normal distribution,
    its central peak is lower and broader, and its tails are shorter and thinner.
    A distribution with kurtosis >0 is called leptokurtic. Compared to a normal distribution,
    its central peak is higher and sharper, and its tails are longer and fatter
    The smallest possible kurtosis -2, largest is infinity.

    https://ncss-wpengine.netdna-ssl.com/wp-content/themes/ncss/pdf/Procedures/NCSS/Normality_Tests.pdf
    Always remember that a reasonably large sample size is required to detect departures from normality.
    Only extreme types of non-normality can be detected with samples less than 50 observations.
    Normality tests generally have small statistical power (probability of detecting non-normal data)
    unless the sample sizes are at least over 100. 
    */

    kurtosis = ( rows_cnt * m4) / (m2*m2) - 3;

    m_skew = sqrt( 6*(rows_cnt-1) / ((rows_cnt+1)*(rows_cnt+3)) ); -- SES: Standard Error of Skewness
    
    m_kurt = sqrt( 24. * rows_cnt * (rows_cnt-2) * (rows_cnt-3) / ( (rows_cnt-1)*(rows_cnt-1)*(rows_cnt+3)*(rows_cnt+5) ) );

    -- https://brownmath.com/stat/shape.htm
    -- https://math.hws.edu/javamath/ryan/ChiSquare.html
    -- https://digitalcommons.wayne.edu/cgi/viewcontent.cgi?article=2427&context=jmasm

    skew_ratio=0;
    kurt_ratio=0;
    if ( m_skew<>0 ) then
        -- "Zg1",  page 85 of Cramer, Duncan, Basic Statistics for Social Research (Routledge, 1997)
        -- The critical value of Zg1 is approximately 2.
        -- If Zg1 < -2, the population is very likely skewed negatively (though you do not know by how much).
        -- If Zg1 is between -2 and +2, you can not reach any conclusion about the skewness of the population:
        -- it might be symmetric, or it might be skewed in either direction.
        -- If Zg1 > 2, the population is very likely skewed positively (though you do not know by how much).
        skew_ratio = skewness / m_skew;
    if ( m_kurt<>0 ) then
        --  "Zg2", page 89 of Duncan Cramer's Basic Statistics for Social Research (Routledge, 1997).
        -- The critical value of Zg2 is approximately 2.
        -- If Zg2 < -2, the population very likely has negative excess kurtosis (platykurtic), though you do not know how much.
        -- If Zg2 is between -2 and +2, you can not reach any conclusion about the kurtosis: excess kurtosis might be positive, negative, or zero.
        -- If Zg2 > +2, the population very likely has positive excess kurtosis (leptokurtic), though you do not know how much.

        kurt_ratio=kurtosis / m_kurt;


    covar = 100.00 * biased_std_dev / x_mean;
    sigma3_violation = iif( abs( x_mean - x_min ) > 3 * unbiased_std_dev  or abs( x_max - x_mean ) > 3 * unbiased_std_dev, 1, 0);
    ----------------------------------------------------------------------------
    if (  covar < 10 ) then
        variance_outcome = 'Dispersion is low';
    else if ( covar < 20 ) then
        variance_outcome = 'Dispersion is middle';
    else if ( covar < 33 ) then
        variance_outcome = 'Dispersion is high';
    else
        variance_outcome = 'Sampling is heterogeneous, need to exclude peaks';
    ----------------------------------------------------------------------------
    if ( sigma3_violation = 1) then
        sigma3_rule_outcome = 'Sampling DO NOT meet the Three Sigma rule.';
    else
        sigma3_rule_outcome = 'Sampling do MEET the Three Sigma rule.';
    ----------------------------------------------------------------------------
    if ( skewness < 0  ) then
        symmetry_outcome = 'Most of values are GREATER than average.' || iif(sigma3_violation = 1, ' One need to remove LEAST element.', '');
    else if ( skewness > 0 ) then
        symmetry_outcome = 'Most of values are LESS than average.' || iif(sigma3_violation = 1, ' One need to remove GREATEST element.', '');
    else
        symmetry_outcome = 'Distribution according to ND law.';
    
    ----------------------------------------------------------------------------
    if ( kurtosis < 0 ) then
        uniformity_outcome = 'Low top distribution, values are scattered evenly.';
    else if ( kurtosis = 0 ) then
        uniformity_outcome = 'Distribution according to ND law';
    else
        uniformity_outcome = 'Peat distribution, values are concentrated near mean.';

    ----------------------------------------------------------------------------
    if ( skew_ratio < 3 and kurt_ratio < 3 ) then
        norm_law_outcome = 'Distribution meets ND law requirements.';
    else
        norm_law_outcome = 'Distribution DOES NOT meet ND law requirements.';

    suspend;

end

^ -- sys_get_stat_in_one_pass


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
