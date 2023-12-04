set bail on;
--set echo on;
commit;
set transaction no wait;

-- drop dependencies:
create or alter procedure sp_gather_results as begin end;
create or alter procedure sp_show_report_data as begin end;

recreate table all_fb_perf_total(id int);
recreate table all_fb_perf_total(id int);
recreate table all_fb_perf_per_minute(id int);
recreate table all_fb_perf_detailed(id int);
recreate table all_fb_exceptions(id int);
recreate table all_fb_perf_cache_dyn(id int);
recreate table all_fb_perf_trace(id int);
recreate table all_fb_perf_trace_pivot(id int);
recreate table all_fb_perf_stat_per_units(id int);
recreate table all_fb_perf_stat_per_tables(id int);
recreate table all_fb_results_reports(id int);
recreate table all_fb_crash_data(id int);
recreate table all_fb_crash_list(id int);
recreate table ddl_outcome(id int);
commit;

--recreate global temporary table tmp$results_sources(
recreate table tmp$results_sources(
    host varchar(255)
   ,dbnm varchar(255)
)
-- on commit preserve rows
;


------------------------------------------------------------------------------------------------

recreate table all_fb_overall(
    run_id bigint          -- come from oltpNN_results.fdb; do NOT PK containing only this field!
    ,fb_engine varchar(8)
    ,fb_build_no int       -- come from oltpNN_results.fdb; run_id + fb_build_no ==> PK
    ,fb_arch varchar(30)
    ,db_fw smallint
    ,workers_count int
    ,db_file_size bigint
    ,used_in_replication smallint
    ,cpu_cores smallint
    ,mem_total bigint
    ,page_buffers int
    ,perf_score int
    ,warm_time int
    ,test_time int
    ,test_finish_state varchar(255)
    ,test_abend_gdscode int
    ,separate_workers smallint
    ,sleep_min int
    ,sleep_max int
    ,working_mode varchar(20)
    ,expected_workers smallint
    ,update_conflict_percent numeric(5,2)
    ,unit_selection_method varchar(20)
    ,no_auto_undo smallint
    ,recalc_idx_min_interval int
    ,detailed_info smallint
    ,enable_mon_query smallint
    ,mon_query_interval smallint
    ,qmism_verify_bitset smallint
    ,trc_unit_perf smallint
    ,build_with_split_heavy_tabs smallint
    ,build_with_separ_qdistr_idx smallint
    ,build_with_qd_compound_ordr varchar(30)
    ,run_db_statistics smallint
    ,run_db_validation smallint
    ,warm_phase_beg timestamp
    ,test_phase_beg timestamp
    ,test_phase_end timestamp
    ,page_size int
    ,db_name varchar(255)
    ,db_created timestamp
    ,db_host_name varchar(255)
    ,report_compress_cmd varchar(255) -- 28.06.2020: zip / 7z / zstd
    ,constraint all_fb_overall_pk primary key(run_id, fb_build_no) using descending index all_fb_overall_pk_desc
);

-----------------------------------------------
-- Table for gathering results of SP REPORT_PERF_TOTAL:
recreate table all_fb_perf_total(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,business_action varchar(255)
    ,avg_times_per_minute numeric(12,2)
    ,avg_elapsed_ms int
    ,successful_times_done int
    ,constraint all_fb_perf_total_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_total_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

-----------------------------------------------
-- Table for gathering results of SP REPORT_PERF_PER_MINUTE:
recreate table all_fb_perf_per_minute(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,test_phase_name varchar(20)
    ,minutes_passed int
    ,perf_score int
    ,constraint all_fb_perf_per_minute_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_per_minute_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

-----------------------------------------------
-- Table for gathering results of SP REPORT_PERF_DETAILED:
recreate table all_fb_perf_detailed(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,unit varchar(80)
    ,cnt_all int
    ,cnt_ok int
    ,cnt_err int
    ,err_prc numeric(6,2)
    ,ok_min_ms int
    ,ok_max_ms int
    ,ok_avg_ms int
    ,cnt_lk_confl int
    ,cnt_user_exc int
    ,cnt_chk_viol int
    ,cnt_unq_viol int
    ,cnt_fk_viol int
    ,cnt_stack_trc int
    ,cnt_zero_gds int
    ,cnt_other_exc int
    ,constraint all_fb_perf_per_detailed_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_per_detailed_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

-----------------------------------------------
-- Table for gathering results of SP REPORT_EXCEPTIONS:
recreate table all_fb_exceptions(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,fb_gdscode int
    ,fb_mnemona varchar(31)
    ,unit varchar(80)
    ,cnt int
    ,constraint all_fb_exceptions_pk primary key(fb_build_no, id)
    ,constraint all_fb_exceptions_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);


-----------------------------------------------
-- Table for gathering results of SP REPORT_CACHE_DYNAMIC:
recreate table all_fb_perf_cache_dyn(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,measurement_timestamp timestamp
    ,measurement_elapsed_ms int
    ,page_cache_memo_used bigint
    ,metadata_cache_memo_used bigint
    ,metadata_cache_percent_of_total numeric(5,3)
    ,total_attachments_cnt int
    ,active_attachments_cnt int
    ,running_statements_cnt int
    ,stalled_statements_cnt int
    ,memo_used_by_attachments bigint
    ,memo_used_by_transactions bigint
    ,memo_used_by_statements bigint
    ,memo_used_all bigint -- 07.06.2020
    ,memo_allo_all bigint -- 07.06.2020
    ,constraint all_fb_perf_cache_dyn_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_cache_dyn_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);


-----------------------------------------------
-- Table for gathering results of SP REPORT_PERF_TRACE:
recreate table all_fb_perf_trace(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,unit varchar(80)
    ,info varchar(255)
    ,interval_no smallint
    ,cnt_success int
    ,fetches_per_second int
    ,marks_per_second int
    ,reads_to_fetches_prc numeric(6,2)
    ,writes_to_marks_prc numeric(6,2)
    ,interval_beg timestamp
    ,interval_end timestamp
    ,constraint all_fb_perf_trace_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_trace_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

-----------------------------------------------
-- Table for gathering results of SP REPORT_PERF_TRACE_PIVOT:
recreate table all_fb_perf_trace_pivot(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,traced_data varchar(30)
    ,interval_no smallint
    ,sp_client_order bigint
    ,sp_cancel_client_order bigint
    ,sp_supplier_order bigint
    ,sp_cancel_supplier_order bigint
    ,sp_supplier_invoice bigint
    ,sp_cancel_supplier_invoice bigint
    ,sp_add_invoice_to_stock bigint
    ,sp_cancel_adding_invoice bigint
    ,sp_customer_reserve bigint
    ,sp_cancel_customer_reserve bigint
    ,sp_reserve_write_off bigint
    ,sp_cancel_write_off bigint
    ,sp_pay_from_customer bigint
    ,sp_cancel_pay_from_customer bigint
    ,sp_pay_to_supplier bigint
    ,sp_cancel_pay_to_supplier bigint
    ,srv_make_invnt_saldo bigint
    ,srv_make_money_saldo bigint
    ,srv_recalc_idx_stat bigint
    ,interval_beg timestamp
    ,interval_end timestamp
    ,constraint all_fb_perf_trace_pivot_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_trace_pivot_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

-----------------------------------------------
-- Table for gathering results of SP REPORT_STAT_PER_UNITS
recreate table all_fb_perf_stat_per_units(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,unit varchar(31)
    ,iter_counts bigint
    ,avg_elap_ms bigint
    ,avg_fetches numeric(12,2)
    ,avg_marks numeric(12,2)
    ,avg_reads numeric(12,2)
    ,avg_writes numeric(12,2)
    ,avg_reads_to_fetches numeric(12,4)
    ,avg_writes_to_marks numeric(12,4)
    ,avg_mem_used bigint
    ,avg_mem_alloc bigint
    ,avg_seq numeric(12,2)
    ,avg_idx numeric(12,2)
    ,avg_rpt numeric(12,2)
    ,avg_bkv numeric(12,2)
    ,avg_frg numeric(12,2)
    ,avg_bkv_per_rec numeric(12,4)
    ,avg_frg_per_rec numeric(12,4)
    ,avg_ins numeric(12,2)
    ,avg_upd numeric(12,2)
    ,avg_del numeric(12,2)
    ,avg_bko numeric(12,2)
    ,avg_pur numeric(12,2)
    ,avg_exp numeric(12,2)
    ,avg_locks numeric(12,2)
    ,avg_confl numeric(12,2)
    ,constraint all_fb_perf_stat_per_units_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_stat_per_units_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

-----------------------------------------------
-- Table for gathering results of SP REPORT_STAT_PER_TABLES // 3.x+
recreate table all_fb_perf_stat_per_tables(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,table_name varchar(31)
    ,unit varchar(80)
    ,iter_counts bigint
    ,avg_seq bigint
    ,avg_idx bigint
    ,avg_rpt bigint
    ,avg_bkv bigint
    ,avg_frg bigint
    ,avg_bkv_per_rec numeric(12,2)
    ,avg_frg_per_rec numeric(12,2)
    ,avg_ins bigint
    ,avg_upd bigint
    ,avg_del bigint
    ,avg_bko bigint
    ,avg_pur bigint
    ,avg_exp bigint
    ,avg_locks bigint
    ,avg_confl bigint
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
    ,max_locks bigint
    ,max_confl bigint
    ,job_beg varchar(16)
    ,job_end varchar(16)
    ,constraint all_fb_perf_stat_per_tables_pk primary key(fb_build_no, id)
    ,constraint all_fb_perf_stat_per_tables_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);
----------------------------------------------
-- Table for storing HTML reports that are generated by oltp_emul_worker scenario (SID #1 after test finish):
recreate table all_fb_results_reports(
     id bigint              -- PK, column_2
    ,run_id bigint not null -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,txt varchar(80) -- result of converting HTML report to base64 without compression
    ,zip2b64 varchar(80) -- compresse HTML report, converted to base64 (filled by SQL INSERT statements for each line of base64 text)
    ,constraint all_fb_results_reports_pk primary key(fb_build_no, id)
    ,constraint all_fb_results_reports_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

recreate table all_fb_crash_list(
    id bigint not null -- PK, column_2
    ,run_id bigint not null  -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_2 ; PK, column_1
    ,dumpname varchar(255)
    ,dumpsize bigint
    ,dumptime timestamp
    ,crashed_binary varchar(255) -- name of binary that crashed: '/opt/fb40/bin/firebird' etc
    ,stack_trace_validation_result varchar(255) -- additional info about problems with gathering stack-trace (missed/invalid .debug package; truncated dump etc)
    ,stack_trace_size bigint
    ,constraint all_fb_crash_list_pk primary key(fb_build_no, id)
    ,constraint all_fb_crash_list_fk foreign key(run_id, fb_build_no) references all_fb_overall on delete cascade
);

recreate table all_fb_crash_data(
    id bigint not null -- PK, column_2
    ,run_id bigint not null  -- compound FK, column_1
    ,fb_build_no int        -- compound FK, column_1 ; PK, column_1
    ,crash_id bigint not null -- compound FK, column_2: references to all_fb_crash_list(.fb_build_no,.id)
    ,txt2b64 varchar(80) -- result of converting stack trace to base 64, without compression
    ,zip2b64 varchar(80) -- compressed stack trace, converted to base64 (filled by SQL INSERT statements for each line of base64 text)
    ,constraint all_fb_crash_data_pk primary key(fb_build_no, id)
    ,constraint all_fb_crash_data_fk foreign key(fb_build_no, crash_id) references all_fb_crash_list on delete cascade
);

commit;

set transaction no wait;
set term ^;
execute block as
begin
    execute statement 'drop sequence g_results';
    when any do begin end
end
^
set term ;^
commit;

create sequence g_results;
commit;

--##################################################

set term ^;
create or alter procedure sp_gather_results(
    eds_dsn varchar(255)
    ,eds_usr varchar(31)
    ,eds_pwd varchar(31)
    ,load_all_data smallint
    ,fb_vers_in_source_db varchar(10) 
) returns(
    msg varchar(255)
)
as
    declare v_last_loaded_run_id bigint; -- 26.06.2020: we can avoid re-load all data, rather load only new.
    declare id bigint;
    declare run_id bigint;
    declare fb_build_no int;
    --------
    declare fb_engine type of column all_fb_overall.fb_engine;
    declare fb_arch type of column all_fb_overall.fb_arch;
    declare db_fw type of column all_fb_overall.db_fw;
    declare workers_count type of column all_fb_overall.workers_count;
    declare db_file_size type of column all_fb_overall.db_file_size;
    declare used_in_replication type of column all_fb_overall.used_in_replication;
    declare cpu_cores type of column all_fb_overall.cpu_cores;
    declare mem_total type of column all_fb_overall.mem_total;
    declare page_buffers type of column all_fb_overall.page_buffers;
    declare perf_score type of column all_fb_overall.perf_score;
    declare warm_time type of column all_fb_overall.warm_time;
    declare test_time type of column all_fb_overall.test_time;
    declare test_finish_state type of column all_fb_overall.test_finish_state;
    declare test_abend_gdscode type of column all_fb_overall.test_abend_gdscode;
    declare separate_workers type of column all_fb_overall.separate_workers;
    declare sleep_min type of column all_fb_overall.sleep_min;
    declare sleep_max type of column all_fb_overall.sleep_max;
    declare working_mode type of column all_fb_overall.working_mode;
    declare expected_workers type of column all_fb_overall.expected_workers;
    declare update_conflict_percent type of column all_fb_overall.update_conflict_percent;
    declare unit_selection_method type of column all_fb_overall.unit_selection_method;
    declare no_auto_undo type of column all_fb_overall.no_auto_undo;
    declare recalc_idx_min_interval type of column all_fb_overall.recalc_idx_min_interval;
    declare detailed_info type of column all_fb_overall.detailed_info;
    declare enable_mon_query type of column all_fb_overall.enable_mon_query;
    declare mon_query_interval type of column all_fb_overall.mon_query_interval;
    declare qmism_verify_bitset type of column all_fb_overall.qmism_verify_bitset;
    declare trc_unit_perf type of column all_fb_overall.trc_unit_perf;
    declare build_with_split_heavy_tabs type of column all_fb_overall.build_with_split_heavy_tabs;
    declare build_with_separ_qdistr_idx type of column all_fb_overall.build_with_separ_qdistr_idx;
    declare build_with_qd_compound_ordr type of column all_fb_overall.build_with_qd_compound_ordr;
    declare run_db_statistics type of column all_fb_overall.run_db_statistics;
    declare run_db_validation type of column all_fb_overall.run_db_validation;
    declare warm_phase_beg type of column all_fb_overall.warm_phase_beg;
    declare test_phase_beg type of column all_fb_overall.test_phase_beg;
    declare test_phase_end type of column all_fb_overall.test_phase_end;
    declare page_size type of column all_fb_overall.page_size;
    declare db_name type of column all_fb_overall.db_name;
    declare db_created type of column all_fb_overall.db_created;
    declare db_host_name type of column all_fb_overall.db_host_name;
    declare report_compress_cmd type of column all_fb_overall.report_compress_cmd; -- 28.06.2020
    -----------------------------------------------------
    declare business_action type of column all_fb_perf_total.business_action;
    declare avg_times_per_minute type of column all_fb_perf_total.avg_times_per_minute;
    declare avg_elapsed_ms type of column all_fb_perf_total.avg_elapsed_ms;
    declare successful_times_done type of column all_fb_perf_total.successful_times_done;
    -----------------------------------------------------
    declare test_phase_name type of column all_fb_perf_per_minute.test_phase_name;
    declare minutes_passed type of column all_fb_perf_per_minute.minutes_passed;
    -- already defined, for all_fb_overall: declare perf_score type of column all_fb_perf_per_minute.perf_score;
    -----------------------------------------------------
    declare measurement_timestamp type of column all_fb_perf_cache_dyn.measurement_timestamp;
    declare measurement_elapsed_ms type of column all_fb_perf_cache_dyn.measurement_elapsed_ms;
    declare page_cache_memo_used type of column all_fb_perf_cache_dyn.page_cache_memo_used;
    declare metadata_cache_memo_used type of column all_fb_perf_cache_dyn.metadata_cache_memo_used;
    declare metadata_cache_percent_of_total type of column all_fb_perf_cache_dyn.metadata_cache_percent_of_total;
    declare total_attachments_cnt type of column all_fb_perf_cache_dyn.total_attachments_cnt;
    declare active_attachments_cnt type of column all_fb_perf_cache_dyn.active_attachments_cnt;
    declare running_statements_cnt type of column all_fb_perf_cache_dyn.running_statements_cnt;
    declare stalled_statements_cnt type of column all_fb_perf_cache_dyn.stalled_statements_cnt;
    declare memo_used_by_attachments type of column all_fb_perf_cache_dyn.memo_used_by_attachments;
    declare memo_used_by_transactions type of column all_fb_perf_cache_dyn.memo_used_by_transactions;
    declare memo_used_by_statements type of column all_fb_perf_cache_dyn.memo_used_by_statements;
    declare memo_used_all type of column all_fb_perf_cache_dyn.memo_used_all;
    declare memo_allo_all type of column all_fb_perf_cache_dyn.memo_allo_all;
    -----------------------------------------------------
    declare unit type of column all_fb_perf_detailed.unit;
    declare cnt_all type of column all_fb_perf_detailed.cnt_all;
    declare cnt_ok type of column all_fb_perf_detailed.cnt_ok;
    declare cnt_err type of column all_fb_perf_detailed.cnt_err;
    declare err_prc type of column all_fb_perf_detailed.err_prc;
    declare ok_min_ms type of column all_fb_perf_detailed.ok_min_ms;
    declare ok_max_ms type of column all_fb_perf_detailed.ok_max_ms;
    declare ok_avg_ms type of column all_fb_perf_detailed.ok_avg_ms;
    declare cnt_lk_confl type of column all_fb_perf_detailed.cnt_lk_confl;
    declare cnt_user_exc type of column all_fb_perf_detailed.cnt_user_exc;
    declare cnt_chk_viol type of column all_fb_perf_detailed.cnt_chk_viol;
    declare cnt_unq_viol type of column all_fb_perf_detailed.cnt_unq_viol;
    declare cnt_fk_viol type of column all_fb_perf_detailed.cnt_fk_viol;
    declare cnt_stack_trc type of column all_fb_perf_detailed.cnt_stack_trc;
    declare cnt_zero_gds type of column all_fb_perf_detailed.cnt_zero_gds;
    declare cnt_other_exc type of column all_fb_perf_detailed.cnt_other_exc;
    ------------------------------------------------------
    declare fb_gdscode type of column all_fb_exceptions.fb_gdscode;
    declare fb_mnemona type of column all_fb_exceptions.fb_mnemona;
    -- already defined, for all_fb_perf_detailed: declare :unit
    declare cnt type of column all_fb_exceptions.cnt;
    ------------------------------------------------------
    declare txt type of column all_fb_results_reports.txt;
    declare zip2b64 type of column all_fb_results_reports.zip2b64; -- 28.06.2020
    ------------------------------------------------------
    declare dumpname type of column all_fb_crash_list.dumpname;
    declare dumpsize type of column all_fb_crash_list.dumpsize;
    declare dumptime type of column all_fb_crash_list.dumptime;
    declare crashed_binary type of column all_fb_crash_list.crashed_binary;
    declare stack_trace_validation_result type of column all_fb_crash_list.stack_trace_validation_result;
    declare stack_trace_size type of column all_fb_crash_list.stack_trace_size;
    declare crash_id type of column all_fb_crash_data.crash_id;
    declare txt2b64 type of column all_fb_crash_data.txt2b64;
    ------------------------------------------------------
    declare v_last_gathered_run_id bigint;
    declare v_rows_changed int;
begin

    msg = cast('now' as timestamp) || '. Starting procedure sp_gather_results.'; suspend;

    execute statement ('select o.run_id from all_fb_overall o where o.fb_engine starting with ? order by o.run_id desc rows 1' ) (fb_vers_in_source_db) into v_last_loaded_run_id;

    v_last_gathered_run_id = iif( load_all_data = 1 or v_last_loaded_run_id is null, -9223372036854775808, v_last_loaded_run_id );

    msg = cast('now' as timestamp) || '. DSN with OLTP-EMUL results: ' || eds_dsn; suspend;
    msg = cast('now' as timestamp) || '. Input arg. load_all_data = ' || load_all_data || '. Gather results for run_id > ' || v_last_gathered_run_id; suspend;

    -- ################################# main: results_overall ==> main: all_fb_overall  ################
    for
    execute statement
    (
        'select
            run_id
            ,fb_engine
            ,fb_build_no
            ,fb_arch
            ,db_fw
            ,workers_count
            ,db_file_size
            ,used_in_replication
            ,cpu_cores
            ,mem_total
            ,page_buffers
            ,perf_score
            ,warm_time
            ,test_time
            ,test_finish_state
            ,test_abend_gdscode
            ,separate_workers
            ,sleep_min
            ,sleep_max
            ,working_mode
            ,expected_workers
            ,update_conflict_percent
            ,unit_selection_method
            ,no_auto_undo
            ,recalc_idx_min_interval
            ,detailed_info
            ,enable_mon_query
            ,mon_query_interval
            ,qmism_verify_bitset
            ,trc_unit_perf
            ,build_with_split_heavy_tabs
            ,build_with_separ_qdistr_idx
            ,build_with_qd_compound_ordr
            ,run_db_statistics
            ,run_db_validation
            ,warm_phase_beg
            ,test_phase_beg
            ,test_phase_end
            ,page_size
            ,db_name
            ,db_created
            ,db_host_name
            ,report_compress_cmd
        from results_overall o where o.run_id > ?'
        )
        ( iif( load_all_data = 1 or v_last_loaded_run_id is null, -9223372036854775808, v_last_loaded_run_id ) )
    on external ( eds_dsn ) as user eds_usr password eds_pwd
    into 
            run_id
            ,fb_engine
            ,fb_build_no
            ,fb_arch
            ,db_fw
            ,workers_count
            ,db_file_size
            ,used_in_replication
            ,cpu_cores
            ,mem_total
            ,page_buffers
            ,perf_score
            ,warm_time
            ,test_time
            ,test_finish_state
            ,test_abend_gdscode
            ,separate_workers
            ,sleep_min
            ,sleep_max
            ,working_mode
            ,expected_workers
            ,update_conflict_percent
            ,unit_selection_method
            ,no_auto_undo
            ,recalc_idx_min_interval
            ,detailed_info
            ,enable_mon_query
            ,mon_query_interval
            ,qmism_verify_bitset
            ,trc_unit_perf
            ,build_with_split_heavy_tabs
            ,build_with_separ_qdistr_idx
            ,build_with_qd_compound_ordr
            ,run_db_statistics
            ,run_db_validation
            ,warm_phase_beg
            ,test_phase_beg
            ,test_phase_end
            ,page_size
            ,db_name
            ,db_created
            ,db_host_name
            ,report_compress_cmd
    do begin
        update or insert into all_fb_overall(
            run_id                -------------- PK, part1
            ,fb_engine
            ,fb_build_no          -------------- PK, part2
            ,fb_arch
            ,db_fw
            ,workers_count
            ,db_file_size
            ,used_in_replication
            ,cpu_cores
            ,mem_total
            ,page_buffers
            ,perf_score
            ,warm_time
            ,test_time
            ,test_finish_state
            ,test_abend_gdscode
            ,separate_workers
            ,sleep_min
            ,sleep_max
            ,working_mode
            ,expected_workers
            ,update_conflict_percent
            ,unit_selection_method
            ,no_auto_undo
            ,recalc_idx_min_interval
            ,detailed_info
            ,enable_mon_query
            ,mon_query_interval
            ,qmism_verify_bitset
            ,trc_unit_perf
            ,build_with_split_heavy_tabs
            ,build_with_separ_qdistr_idx
            ,build_with_qd_compound_ordr
            ,run_db_statistics
            ,run_db_validation
            ,warm_phase_beg
            ,test_phase_beg
            ,test_phase_end
            ,page_size
            ,db_name
            ,db_created
            ,db_host_name
            ,report_compress_cmd
        ) values (
            :run_id
            ,:fb_engine
            ,:fb_build_no
            ,:fb_arch
            ,:db_fw
            ,:workers_count
            ,:db_file_size
            ,:used_in_replication
            ,:cpu_cores
            ,:mem_total
            ,:page_buffers
            ,:perf_score
            ,:warm_time
            ,:test_time
            ,:test_finish_state
            ,:test_abend_gdscode
            ,:separate_workers
            ,:sleep_min
            ,:sleep_max
            ,:working_mode
            ,:expected_workers
            ,:update_conflict_percent
            ,:unit_selection_method
            ,:no_auto_undo
            ,:recalc_idx_min_interval
            ,:detailed_info
            ,:enable_mon_query
            ,:mon_query_interval
            ,:qmism_verify_bitset
            ,:trc_unit_perf
            ,:build_with_split_heavy_tabs
            ,:build_with_separ_qdistr_idx
            ,:build_with_qd_compound_ordr
            ,:run_db_statistics
            ,:run_db_validation
            ,:warm_phase_beg
            ,:test_phase_beg
            ,:test_phase_end
            ,:page_size
            ,:db_name
            ,:db_created
            ,:db_host_name
            ,:report_compress_cmd
        ) matching (run_id, fb_build_no)
        ;
        msg = cast('now' as timestamp) || '. Completed merge data into parent table ALL_FB_OVERALL for run_id=' || run_id; suspend;

        -- ################################# child: results_total ==> child: all_fb_perf_total  ################
        -- Obtain records from table 'results_total' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
                   id
                   ,business_action
                   ,avg_times_per_minute
                   ,avg_elapsed_ms
                   ,successful_times_done
               from results_total t
               where t.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
             id
            ,business_action
            ,avg_times_per_minute
            ,avg_elapsed_ms
            ,successful_times_done
        do begin
            update or insert into all_fb_perf_total(
                 id
                ,run_id
                ,fb_build_no
                ,business_action
                ,avg_times_per_minute
                ,avg_elapsed_ms
                ,successful_times_done
            ) values (
                 :id           -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
                ,:business_action
                ,:avg_times_per_minute
                ,:avg_elapsed_ms
                ,:successful_times_done
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_total ==> child: all_fb_perf_total"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_PERF_TOTAL for run_id=' || run_id; suspend;

        -- ############################## child: results_per_minute ==> child: all_fb_perf_per_minute #################

        -- Obtain records from table 'results_per_minute' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
                    id
                   ,test_phase_name
                   ,minutes_passed
                   ,perf_score
               from results_per_minute m
               where m.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
             id
            ,test_phase_name
            ,minutes_passed
            ,perf_score
        do begin
            update or insert into all_fb_perf_per_minute(
                 id
                ,run_id
                ,fb_build_no
                ,test_phase_name
                ,minutes_passed
                ,perf_score
            ) values (
                :id            -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
                ,:test_phase_name
                ,:minutes_passed
                ,:perf_score
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_per_minute ==> child: all_fb_perf_per_minute"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_PERF_MINUTE for run_id=' || run_id; suspend;


        -- ############################## child: results_cache_dyn ==> child: all_fb_perf_cache_dyn #################
        -- Obtain records from table 'results_cache_dyn' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
                    id
                   ,measurement_timestamp
                   ,measurement_elapsed_ms
                   ,page_cache_memo_used
                   ,metadata_cache_memo_used
                   ,metadata_cache_percent_of_total
                   ,total_attachments_cnt
                   ,active_attachments_cnt
                   ,running_statements_cnt
                   ,stalled_statements_cnt
                   ,memo_used_by_attachments
                   ,memo_used_by_transactions
                   ,memo_used_by_statements
                   ,memo_used_all
                   ,memo_allo_all
                from results_cache_dyn d
                where d.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
             id
             ,measurement_timestamp
             ,measurement_elapsed_ms
             ,page_cache_memo_used
             ,metadata_cache_memo_used
             ,metadata_cache_percent_of_total
             ,total_attachments_cnt
             ,active_attachments_cnt
             ,running_statements_cnt
             ,stalled_statements_cnt
             ,memo_used_by_attachments
             ,memo_used_by_transactions
             ,memo_used_by_statements
             ,memo_used_all
             ,memo_allo_all
        do begin
            update or insert into all_fb_perf_cache_dyn(
                 id
                ,run_id     
                ,fb_build_no
                ,measurement_timestamp
                ,measurement_elapsed_ms
                ,page_cache_memo_used
                ,metadata_cache_memo_used
                ,metadata_cache_percent_of_total
                ,total_attachments_cnt
                ,active_attachments_cnt
                ,running_statements_cnt
                ,stalled_statements_cnt
                ,memo_used_by_attachments
                ,memo_used_by_transactions
                ,memo_used_by_statements
                ,memo_used_all
                ,memo_allo_all
            ) values (
                 :id           -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
                ,:measurement_timestamp
                ,:measurement_elapsed_ms
                ,:page_cache_memo_used
                ,:metadata_cache_memo_used
                ,:metadata_cache_percent_of_total
                ,:total_attachments_cnt
                ,:active_attachments_cnt
                ,:running_statements_cnt
                ,:stalled_statements_cnt
                ,:memo_used_by_attachments
                ,:memo_used_by_transactions
                ,:memo_used_by_statements
                ,:memo_used_all
                ,:memo_allo_all
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_cache_dyn ==> child: all_fb_perf_cache_dyn"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_PERF_CACHE_DYN for run_id=' || run_id;
        suspend;


        -- ############################## child: results_perf_detailed ==> child: all_fb_perf_detailed #################
        -- Obtain records from table 'results_perf_detailed' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
                    id
                   ,unit
                   ,cnt_all
                   ,cnt_ok
                   ,cnt_err
                   ,err_prc
                   ,ok_min_ms
                   ,ok_max_ms
                   ,ok_avg_ms
                   ,cnt_lk_confl
                   ,cnt_user_exc
                   ,cnt_chk_viol
                   ,cnt_unq_viol
                   ,cnt_fk_viol
                   ,cnt_stack_trc
                   ,cnt_zero_gds
                   ,cnt_other_exc
                from results_perf_detailed d
                where d.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
            id
            ,unit
            ,cnt_all
            ,cnt_ok
            ,cnt_err
            ,err_prc
            ,ok_min_ms
            ,ok_max_ms
            ,ok_avg_ms
            ,cnt_lk_confl
            ,cnt_user_exc
            ,cnt_chk_viol
            ,cnt_unq_viol
            ,cnt_fk_viol
            ,cnt_stack_trc
            ,cnt_zero_gds
            ,cnt_other_exc
        do begin
            update or insert into all_fb_perf_detailed(
                 id
                ,run_id     
                ,fb_build_no
                ,unit
                ,cnt_all
                ,cnt_ok
                ,cnt_err
                ,err_prc
                ,ok_min_ms
                ,ok_max_ms
                ,ok_avg_ms
                ,cnt_lk_confl
                ,cnt_user_exc
                ,cnt_chk_viol
                ,cnt_unq_viol
                ,cnt_fk_viol
                ,cnt_stack_trc
                ,cnt_zero_gds
                ,cnt_other_exc

            ) values (
                :id            -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
                ,:unit
                ,:cnt_all
                ,:cnt_ok
                ,:cnt_err
                ,:err_prc
                ,:ok_min_ms
                ,:ok_max_ms
                ,:ok_avg_ms
                ,:cnt_lk_confl
                ,:cnt_user_exc
                ,:cnt_chk_viol
                ,:cnt_unq_viol
                ,:cnt_fk_viol
                ,:cnt_stack_trc
                ,:cnt_zero_gds
                ,:cnt_other_exc
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_perf_detailed ==> child: all_fb_perf_detailed"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_PERF_DETAILED for run_id=' || run_id; suspend;


        -- ############################## child: results_exceptions ==> child: all_fb_exceptions #################
        -- Obtain records from table 'results_exceptions' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
                    id
                   ,fb_gdscode
                   ,fb_mnemona
                   ,unit
                   ,cnt
                from results_exceptions e
                where e.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
             id
            ,fb_gdscode
            ,fb_mnemona
            ,unit
            ,cnt
        do begin
            update or insert into all_fb_exceptions(
                 id
                ,run_id     
                ,fb_build_no
                ,fb_gdscode
                ,fb_mnemona
                ,unit
                ,cnt
            ) values (
                 :id           -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
                ,:fb_gdscode
                ,:fb_mnemona
                ,:unit
                ,:cnt
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_exceptions ==> child: all_fb_exceptions"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_EXCEPTIONS for run_id=' || run_id; suspend;


        -- ############################## child: results_reports ==> child: all_fb_results_reports #################
        -- Obtain records from table 'results_reports' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
                    id
                   ,txt
                   ,zip2b64
                from results_reports e
                where e.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
             id
            ,txt
            ,zip2b64
        do begin
            update or insert into all_fb_results_reports(
                 id
                ,run_id     
                ,fb_build_no
                ,txt
                ,zip2b64
            ) values (
                 :id           -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
                ,:txt
                ,:zip2b64
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_reports ==> child: all_fb_results_reports"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_RESULTS_REPORTS for run_id=' || run_id; suspend;

        -- ############################## child: results_crash_list ==> child: all_fb_crash_list #################
        -- Obtain records from table 'results_crash_list' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
            	    id
		    ,dumpname
		    ,dumpsize
		    ,dumptime
		    ,crashed_binary
		    ,stack_trace_validation_result
		    ,stack_trace_size
                from results_crash_list e
                where e.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
             id
	    ,dumpname
	    ,dumpsize
	    ,dumptime
	    ,crashed_binary
	    ,stack_trace_validation_result
	    ,stack_trace_size
        do begin
            update or insert into all_fb_crash_list(
                 id
                ,run_id     
                ,fb_build_no
		,dumpname
		,dumpsize
		,dumptime
		,crashed_binary
		,stack_trace_validation_result
		,stack_trace_size
            ) values (
                 :id           -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
		,:dumpname
		,:dumpsize
		,:dumptime
		,:crashed_binary
		,:stack_trace_validation_result
		,:stack_trace_size
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_crash_list ==> child: all_fb_crash_list"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_CRASH_LIST for run_id=' || run_id; suspend;


        -- ############################## child: results_crash_data ==> child: all_fb_crash_data #################
        -- Obtain records from table 'results_crash_data' with run_id = :run_id.
        -- NB: primary key of child table is COMPOUND: (build_no, id). It is necessary because ID column can have the same value
        -- in different databases.
        v_rows_changed = 0;
        for
        execute statement
            (
              'select
            	    id
            	    ,crash_id
            	    ,txt2b64
            	    ,zip2b64
                from results_crash_data e
                where e.run_id = ?
              '
            ) 
            ( :run_id ) 
        on external ( eds_dsn ) as user eds_usr password eds_pwd
        into 
             id
             ,crash_id
             ,txt2b64
             ,zip2b64
        do begin
            update or insert into all_fb_crash_data(
                 id
                ,run_id
                ,fb_build_no
                ,crash_id
                ,txt2b64
                ,zip2b64
            ) values (
                 :id           -------------- PK part2
                ,:run_id       -------------- FK part1, defined in query to results_overall
                ,:fb_build_no  -------------- FK part2, defined in query to results_overall ; PK part1
                ,:crash_id
		,:txt2b64
		,:zip2b64
            ) matching (fb_build_no, id)
            ;
            v_rows_changed = v_rows_changed + 1;
        end -- "child: results_crash_data ==> child: all_fb_crash_data"
        msg = cast('now' as timestamp) || '. Completed merge ' || v_rows_changed || ' rows into child table ALL_FB_CRASH_DATA for run_id=' || run_id; suspend;

    end -- loop "main: results_overall ==> main: all_fb_overall"

    execute statement ('select o.run_id  from all_fb_overall o where o.fb_engine starting with ? order by o.run_id desc rows 1' ) (fb_vers_in_source_db) into v_last_loaded_run_id;
    if (v_last_loaded_run_id > v_last_gathered_run_id) then
        begin
            msg = cast('now' as timestamp) || '. Result of gathering: last loaded run_id = ' || v_last_loaded_run_id; suspend;
        end
    else
        begin
            msg = cast('now' as timestamp) || '. NO DATA FOUND in ' || eds_dsn || ' with run_id > ' || coalesce(v_last_gathered_run_id, '[null]'); suspend;
        end

    msg = cast('now' as timestamp) || '. Finished procedure sp_gather_results.'; suspend;

end
^
-- end of sp_gather_results

-- #########################################

create or alter procedure sp_show_results( a_rows_limit int = 999999999 )
returns(
     "run_date" date
    ,"run_seqn" smallint
    ,"fb3x_vers" varchar(80)
    ,"fb4x_vers" varchar(80)
    ,"fb5x_vers" varchar(80)
    ,"fb3x_perf_score" bigint
    ,"fb4x_perf_score" bigint
    ,"fb5x_perf_score" bigint
    ,"fb3x_used_all" bigint
    ,"fb4x_used_all" bigint
    ,"fb5x_used_all" bigint
    ,"fb3x_used_by_att" bigint
    ,"fb4x_used_by_att" bigint
    ,"fb5x_used_by_att" bigint
    ,"fb3x_used_by_trn" bigint
    ,"fb4x_used_by_trn" bigint
    ,"fb5x_used_by_trn" bigint
    ,"fb3x_used_by_stm" bigint
    ,"fb4x_used_by_stm" bigint
    ,"fb5x_used_by_stm" bigint
    ,"fb3x_run_hhmm" varchar(25)
    ,"fb4x_run_hhmm" varchar(25)
    ,"fb5x_run_hhmm" varchar(25)
    ,"fb3x_outcome" varchar(80)
    ,"fb4x_outcome" varchar(80)
    ,"fb5x_outcome" varchar(80)
    ,"fb3x_run_id" bigint
    ,"fb4x_run_id" bigint
    ,"fb5x_run_id" bigint
    ,"fb3x_compress_cmd" varchar(255)
    ,"fb4x_compress_cmd" varchar(255)
    ,"fb5x_compress_cmd" varchar(255)
)
as
begin
    a_rows_limit = iif( coalesce(a_rows_limit,0) <= 0, 999999999, a_rows_limit );
    for
        with
        fb3 as (
            select
                 o.run_id fb3x_run_id
                ,cast(o.test_phase_beg as date) as fb3x_run_date
                ,substring(cast(o.test_phase_beg as varchar(50)) from 12 for 5) as fb3x_run_hhmm
                ,o.fb_engine
                 || '.' || cast(o.fb_build_no as varchar(10)) fb3x_vers
                ,o.perf_score fb3x_perf_score
                ,coalesce(  o.test_finish_state
                           ,nullif((select count(*) from all_fb_crash_list k where k.run_id = o.run_id and k.fb_build_no = o.fb_build_no),0 ) || ' crash(es) detected'
                         )
                 as fb3x_outcome
                ,o.report_compress_cmd fb3x_compress_cmd
                ,coalesce( max(c.memo_used_all), 0) fb3x_used_all
                ,coalesce( max(c.memo_used_by_attachments), 0) fb3x_used_by_att
                ,coalesce( max(c.memo_used_by_transactions), 0) fb3x_used_by_trn
                ,coalesce( max(c.memo_used_by_statements), 0) fb3x_used_by_stm
                ,dense_rank()over( partition by cast(o.test_phase_beg as date) order by o.run_id desc) as fb3x_run_seqn
            from all_fb_overall o
            LEFT -- NB: table 'all_fb_perf_cache_dyn' will be EMPTY when mon_unit_perf = 0
                join all_fb_perf_cache_dyn c on o.run_id = c.run_id and o.fb_build_no = c.fb_build_no
            where o.fb_engine starting with '3.'
            group by
                 o.run_id
                ,cast(o.test_phase_beg as date)
                ,substring(cast(o.test_phase_beg as varchar(50)) from 12 for 5)
                ,o.fb_engine
                ,o.fb_build_no
                ,o.perf_score
                ,o.test_finish_state
                ,o.report_compress_cmd
        )
        ,fb4 as (
            select
                 o.run_id fb4x_run_id
                ,cast(o.test_phase_beg as date) as fb4x_run_date
                ,substring(cast(o.test_phase_beg as varchar(50)) from 12 for 5) as fb4x_run_hhmm
                ,o.fb_engine
                 || '.' || cast(o.fb_build_no as varchar(10)) fb4x_vers
                ,o.perf_score fb4x_perf_score
                --,o.test_finish_state fb4x_outcome
                ,coalesce(  o.test_finish_state
                           ,nullif((select count(*) from all_fb_crash_list k where k.run_id = o.run_id and k.fb_build_no = o.fb_build_no),0 ) || ' crash(es) detected'
                         )
                 as fb4x_outcome
                ,o.report_compress_cmd fb4x_compress_cmd
                ,coalesce( max(c.memo_used_all), 0) fb4x_used_all
                ,coalesce( max(c.memo_used_by_attachments), 0) fb4x_used_by_att
                ,coalesce( max(c.memo_used_by_transactions), 0) fb4x_used_by_trn
                ,coalesce( max(c.memo_used_by_statements), 0) fb4x_used_by_stm
                ,dense_rank()over( partition by cast(o.test_phase_beg as date) order by o.run_id desc) as fb4x_run_seqn
            from all_fb_overall o
            LEFT -- NB: table 'all_fb_perf_cache_dyn' will be EMPTY when mon_unit_perf = 0 
                join all_fb_perf_cache_dyn c on o.run_id = c.run_id and o.fb_build_no = c.fb_build_no
            where o.fb_engine starting with '4.'
            group by
                 o.run_id
                ,cast(o.test_phase_beg as date)
                ,substring(cast(o.test_phase_beg as varchar(50)) from 12 for 5)
                ,o.fb_engine
                ,o.fb_build_no
                ,o.perf_score
                ,o.test_finish_state
                ,o.report_compress_cmd
        )
        ,fb5 as (
            select
                 o.run_id fb5x_run_id
                ,cast(o.test_phase_beg as date) as fb5x_run_date
                ,substring(cast(o.test_phase_beg as varchar(50)) from 12 for 5) as fb5x_run_hhmm
                ,o.fb_engine
                 || '.' || cast(o.fb_build_no as varchar(10)) fb5x_vers
                ,o.perf_score fb5x_perf_score
                --,o.test_finish_state fb5x_outcome
                ,coalesce(  o.test_finish_state
                           ,nullif((select count(*) from all_fb_crash_list k where k.run_id = o.run_id and k.fb_build_no = o.fb_build_no),0 ) || ' crash(es) detected'
                         )
                 as fb5x_outcome
                ,o.report_compress_cmd fb5x_compress_cmd
                ,coalesce( max(c.memo_used_all), 0) fb5x_used_all
                ,coalesce( max(c.memo_used_by_attachments), 0) fb5x_used_by_att
                ,coalesce( max(c.memo_used_by_transactions), 0) fb5x_used_by_trn
                ,coalesce( max(c.memo_used_by_statements), 0) fb5x_used_by_stm
                ,dense_rank()over( partition by cast(o.test_phase_beg as date) order by o.run_id desc) as fb5x_run_seqn
            from all_fb_overall o
            LEFT -- NB: table 'all_fb_perf_cache_dyn' will be EMPTY when mon_unit_perf = 0 
                join all_fb_perf_cache_dyn c on o.run_id = c.run_id and o.fb_build_no = c.fb_build_no
            where o.fb_engine starting with '5.'
            group by
                 o.run_id
                ,cast(o.test_phase_beg as date)
                ,substring(cast(o.test_phase_beg as varchar(50)) from 12 for 5)
                ,o.fb_engine
                ,o.fb_build_no
                ,o.perf_score
                ,o.test_finish_state
                ,o.report_compress_cmd
        )

        ,u as (
            select
                 a.fb3x_run_date as run_date
                ,a.fb3x_run_seqn as run_seqn
                ----------------------------
                ,a.fb3x_run_id -- needed for extracting html-report
                ,a.fb3x_run_hhmm
                ,a.fb3x_vers
                ,a.fb3x_perf_score
                ,a.fb3x_used_all
                ,a.fb3x_used_by_att
                ,a.fb3x_used_by_trn
                ,a.fb3x_used_by_stm
                ,a.fb3x_outcome
                ,a.fb3x_compress_cmd
                ----------------------------
                ,null as fb4x_run_id
                ,null as fb4x_run_hhmm
                ,null as fb4x_vers
                ,null as fb4x_perf_score
                ,null as fb4x_used_all
                ,null as fb4x_used_by_att
                ,null as fb4x_used_by_trn
                ,null as fb4x_used_by_stm
                ,null as fb4x_outcome
                ,null as fb4x_compress_cmd
                -------------------------
                ,null as fb5x_run_id
                ,null as fb5x_run_hhmm
                ,null as fb5x_vers
                ,null as fb5x_perf_score
                ,null as fb5x_used_all
                ,null as fb5x_used_by_att
                ,null as fb5x_used_by_trn
                ,null as fb5x_used_by_stm
                ,null as fb5x_outcome
                ,null as fb5x_compress_cmd
                -------------------------
            from fb3 a

            UNION ALL

            select
                 b.fb4x_run_date
                ,b.fb4x_run_seqn
                ----------------------------
                ,null as fb3x_run_id
                ,null as fb3x_run_hhmm
                ,null as fb3x_vers
                ,null as fb3x_perf_score
                ,null as fb3x_used_all
                ,null as fb3x_used_by_att
                ,null as fb3x_used_by_trn
                ,null as fb3x_used_by_stm
                ,null as fb3x_outcome
                ,null as fb3x_compress_cmd
                ----------------------------
                ,b.fb4x_run_id -- needed for extracting html-report
                ,b.fb4x_run_hhmm
                ,b.fb4x_vers
                ,b.fb4x_perf_score
                ,b.fb4x_used_all
                ,b.fb4x_used_by_att
                ,b.fb4x_used_by_trn
                ,b.fb4x_used_by_stm
                ,b.fb4x_outcome
                ,b.fb4x_compress_cmd
                -------------------------
                ,null as fb5x_run_id
                ,null as fb5x_run_hhmm
                ,null as fb5x_vers
                ,null as fb5x_perf_score
                ,null as fb5x_used_all
                ,null as fb5x_used_by_att
                ,null as fb5x_used_by_trn
                ,null as fb5x_used_by_stm
                ,null as fb5x_outcome
                ,null as fb5x_compress_cmd
                -------------------------
            from fb4 b
            
            UNION ALL
            
            select
                 c.fb5x_run_date
                ,c.fb5x_run_seqn
                ----------------------------
                ,null as fb3x_run_id
                ,null as fb3x_run_hhmm
                ,null as fb3x_vers
                ,null as fb3x_perf_score
                ,null as fb3x_used_all
                ,null as fb3x_used_by_att
                ,null as fb3x_used_by_trn
                ,null as fb3x_used_by_stm
                ,null as fb3x_outcome
                ,null as fb3x_compress_cmd
                -------------------------
                ,null as fb4x_run_id
                ,null as fb4x_run_hhmm
                ,null as fb4x_vers
                ,null as fb4x_perf_score
                ,null as fb4x_used_all
                ,null as fb4x_used_by_att
                ,null as fb4x_used_by_trn
                ,null as fb4x_used_by_stm
                ,null as fb4x_outcome
                ,null as fb4x_compress_cmd
                ----------------------------
                ,c.fb5x_run_id -- needed for extracting html-report
                ,c.fb5x_run_hhmm
                ,c.fb5x_vers
                ,c.fb5x_perf_score
                ,c.fb5x_used_all
                ,c.fb5x_used_by_att
                ,c.fb5x_used_by_trn
                ,c.fb5x_used_by_stm
                ,c.fb5x_outcome
                ,c.fb5x_compress_cmd
                -------------------------
            from fb5 c
            
        )
        --select * from u

        select
             run_date
            ,run_seqn
            --------------------------------
            ,max(fb3x_vers) as fb3x_vers
            ,max(fb4x_vers) as fb4x_vers
            ,max(fb5x_vers) as fb5x_vers
             ------------------------------------------
            ,max(fb3x_perf_score) as fb3x_perf_score
            ,max(fb4x_perf_score) as fb4x_perf_score
            ,max(fb5x_perf_score) as fb5x_perf_score
             ------------------------------------------
            ,max(fb3x_used_all) as fb3x_used_all
            ,max(fb4x_used_all) as fb4x_used_all
            ,max(fb5x_used_all) as fb5x_used_all
             ------------------------------------------
            ,max(fb3x_used_by_att) as fb3x_used_by_att
            ,max(fb4x_used_by_att) as fb4x_used_by_att
            ,max(fb5x_used_by_att) as fb5x_used_by_att
             ------------------------------------------
            ,max(fb3x_used_by_trn) as fb3x_used_by_trn
            ,max(fb4x_used_by_trn) as fb4x_used_by_trn
            ,max(fb5x_used_by_trn) as fb5x_used_by_trn
             ------------------------------------------
            ,max(fb3x_used_by_stm) as fb3x_used_by_stm
            ,max(fb4x_used_by_stm) as fb4x_used_by_stm
            ,max(fb5x_used_by_stm) as fb5x_used_by_stm
             ------------------------------------------
            ,max(fb3x_run_hhmm) as fb3x_run_hhmm
            ,max(fb4x_run_hhmm) as fb4x_run_hhmm
            ,max(fb5x_run_hhmm) as fb4x_run_hhmm
            --------------------------------------------
            ,max(fb3x_outcome) as fb3x_outcome
            ,max(fb4x_outcome) as fb4x_outcome
            ,max(fb5x_outcome) as fb5x_outcome
            --------------------------------------------
            -- needed for extracting detailed html-reports:
            ,max(fb3x_run_id) as fb3x_run_id 
            ,max(fb4x_run_id) as fb4x_run_id
            ,max(fb5x_run_id) as fb5x_run_id
            ,max(fb3x_compress_cmd) as fb3x_compress_cmd
            ,max(fb4x_compress_cmd) as fb4x_compress_cmd
            ,max(fb5x_compress_cmd) as fb5x_compress_cmd
        from u
        group by run_date,run_seqn
        order by run_date desc, run_seqn
        rows (:a_rows_limit)
    into
     "run_date"
    ,"run_seqn"
    ,"fb3x_vers"
    ,"fb4x_vers"
    ,"fb5x_vers"
    ,"fb3x_perf_score"
    ,"fb4x_perf_score"
    ,"fb5x_perf_score"
    ,"fb3x_used_all"
    ,"fb4x_used_all"
    ,"fb5x_used_all"
    ,"fb3x_used_by_att"
    ,"fb4x_used_by_att"
    ,"fb5x_used_by_att"
    ,"fb3x_used_by_trn"
    ,"fb4x_used_by_trn"
    ,"fb5x_used_by_trn"
    ,"fb3x_used_by_stm"
    ,"fb4x_used_by_stm"
    ,"fb5x_used_by_stm"
    ,"fb3x_run_hhmm"
    ,"fb4x_run_hhmm"
    ,"fb5x_run_hhmm"
    ,"fb3x_outcome"
    ,"fb4x_outcome"
    ,"fb5x_outcome"
    ,"fb3x_run_id"
    ,"fb4x_run_id"
    ,"fb5x_run_id"
    ,"fb3x_compress_cmd"
    ,"fb4x_compress_cmd"
    ,"fb5x_compress_cmd"
    do
        suspend;
end
^
-- end of sp_show_results

create or alter procedure sp_show_report_data(a_fb_build_no int, a_run_id bigint) returns(
     txt type of column all_fb_results_reports.txt
    ,zip2b64 type of column all_fb_results_reports.zip2b64)
as
begin
    for
        select txt, zip2b64
        from all_fb_results_reports r
        where r.fb_build_no = :a_fb_build_no and r.run_id = :a_run_id
        order by r.id
    into txt, zip2b64
    do suspend;
end
^
-- end of sp_show_report_data

set term ;^
commit;

recreate table ddl_outcome(
    info varchar(255)
);
commit;
insert into ddl_outcome(info) values('DDL completed ' || cast('now' as timestamp) || ', engine: ' || rdb$get_context('SYSTEM', 'ENGINE_VERSION') );
commit;
