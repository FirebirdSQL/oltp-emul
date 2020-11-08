--shell rm -f /opt/oltp-emul/oltp_results.fdb 2>/dev/null;
--create database '/opt/oltp-emul/oltp_results.fdb' user 'SYSDBA' password 'masterkey';
set bail on;
set echo on;
commit;
set transaction no wait;
create or alter procedure eds_obtain_last_test_results as begin end;

-- drop tables on which results_overall ('main parent') can be dependent:
recreate table results_total(id int);
recreate table results_per_minute(id int);
recreate table results_perf_detailed(id int);
recreate table results_exceptions(id int);
recreate table results_cache_dyn(id int);
recreate table results_perf_trace(id int);
recreate table results_perf_trace_pivot(id int);
recreate table results_perf_stat_per_units(id int);
recreate table results_perf_stat_per_tables(id int);
recreate table results_reports(id int);
commit;

recreate global temporary table tmp$field_names(
    fld_name varchar(31)
   ,constraint tmp$field_names_unq unique(fld_name)
) on commit delete rows;

recreate exception exc_fb_build_is_null 'Column results_overall.fb_build_no remained NULL.';

------------------------------------------------------------------------------------------------

-- Table SETTINGS is fulfilled with data in following .sh/.bat routines:
-- sync_settings_with_conf()
-- show_db_and_test_params()
-- Table RESULTS_OVERALL must have fields which names equal to values stored in the table SETTINGS.
recreate table results_overall(
    run_id bigint not null
    ,fb_engine varchar(8) -- show_db_and_test_params(): rdb$get_context('SYSTEM','ENGINE_VERSION'): '3.0.6'
    
     -- NOTE: fb_build_no is part of PRIMARY KEY in the table all_fb_overall, see oltp_overall_report_DDL.sql
     -- Although it must be declared as not null, here we intentionally SKIP this because this table will be
     -- fulfilled with data in several steps, and fb_build_no will at the start remains null.
     -- This column will have non-null value at the final step of SP eds_obtain_last_test_results, see this:
     -- execute statement ('update or insert into results_overall(run_id, ' || v_mcode || ') values(?, ?) matching(run_id)') (v_run_id, v_svalue)
    
    ,fb_build_no int -- show_db_and_test_params(): fbsvcmgr info_server_version; 'Server version: LI-V3.0.6.33289 Firebird 3.0' ==> 33289

    ,fb_arch varchar(30) -- show_db_and_test_params()=>SYS_GET_FB_ARCH; SETTINGS: 'INIT', 'SuperClassic 3.0.6'
    ,db_fw smallint -- show_db_and_test_params(), SETTINGS: 'INIT', 'DB_FW'; 0|1;
    ,workers_count int -- sync_settings_with_conf()=>inject_actual_setting()
    ,db_file_size bigint -- show_db_and_test_params(), SETTINGS: 'INIT'; size before test start, mon$page_size * mon$pages 
    ,used_in_replication smallint -- sync_settings_with_conf()=>inject_actual_setting(): 'COMMON','USED_IN_REPLICATION' <<<<
    ,cpu_cores smallint -- show_db_and_test_params(): [getconf _NPROCESSORS_ONLN], SETTINGS: 'INIT'
    ,mem_total bigint -- show_db_and_test_params(): [getconf _PHYS_PAGES]*[getconf PAGESIZE], Gb; SETTINGS: 'INIT'
    ,page_buffers int -- show_db_and_test_params(), SETTINGS: 'INIT' <<<<
    ,perf_score int -- fulfilled AFTER test finish, by SID=1, query to SP srv_get_report_name
    ,warm_time int  -- sync_settings_with_conf()=>inject_actual_setting()
    ,test_time int -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,test_finish_state varchar(255) -- fulfilled AFTER test finish
    ,test_abend_gdscode int  -- fulfilled AFTER test finish
    ,separate_workers smallint -- sync_settings_with_conf()=>inject_actual_setting()
    ,sleep_min int -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,sleep_max int -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,working_mode varchar(20) -- sync_settings_with_conf()=>inject_actual_setting(); SETTINGS: 'INIT','WORKING_MODE'
    ,expected_workers smallint -- show_db_and_test_params(), SETTINGS: 'INIT','EXPECTED_WORKERS'
    ,update_conflict_percent numeric(5,2) -- sync_settings_with_conf()=>inject_actual_setting()
    ,unit_selection_method varchar(20) -- sync_settings_with_conf()=>inject_actual_setting(); in SETTINGS: 'COMMON','UNIT_SELECTION_METHOD'
    ,no_auto_undo smallint -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,recalc_idx_min_interval int -- sync_settings_with_conf()=>inject_actual_setting()
    ,detailed_info smallint -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,enable_mon_query smallint -- now: 0;1;2 was: 'enable_mon_query' 0|1; sync_settings_with_conf()=>inject_actual_setting(), in SETTINGS: 'COMMON','ENABLE_MON_QUERY'
    ,mon_query_interval smallint -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,qmism_verify_bitset smallint -- sync_settings_with_conf()=>inject_actual_setting()
    ,trc_unit_perf smallint -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,build_with_split_heavy_tabs smallint -- sync_settings_with_conf()=>inject_actual_setting(); in SETTINGS: 'build_with_heavy_tabs' <<<<
    ,build_with_separ_qdistr_idx smallint -- sync_settings_with_conf()=>inject_actual_setting(); in SETTINGS: 'build_with_separ_qdistr_idx' <<<<
    ,build_with_qd_compound_ordr varchar(30) -- sync_settings_with_conf()=>inject_actual_setting(); in SETTINGS: build_with_qd_compound_ordr <<<<
    ,run_db_statistics smallint -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,run_db_validation smallint -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,warm_phase_beg timestamp -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,test_phase_beg timestamp -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,test_phase_end timestamp -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,page_size int -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,db_name varchar(255) -- show_db_and_test_params(), SETTINGS: 'INIT'
    ,db_created timestamp
    ,db_host_name varchar(255) -- show_db_and_test_params(), SETTINGS: 'INIT'; `hostname`/%computername%
    ,report_compress_cmd varchar(255) -- 28.06.2020: zip / 7z / zstd
    ,constraint res_overall_pk primary key(run_id) using descending index res_overall_run_id_desc
);

-----------------------------------------------
-- Table for storing results of SP REPORT_PERF_TOTAL:
recreate table results_total(
     id bigint not null
    ,run_id bigint not null
    ,business_action varchar(255)
    ,avg_times_per_minute numeric(12,2)
    ,avg_elapsed_ms int
    ,successful_times_done int
    ,constraint res_perf_total_pk primary key(id)
    ,constraint res_perf_total_fk foreign key(run_id) references results_overall on delete cascade
);

-----------------------------------------------
-- Table for storing results of SP REPORT_PERF_PER_MINUTE:
recreate table results_per_minute(
     id bigint not null
    ,run_id bigint not null
    ,test_phase_name varchar(20)
    ,minutes_passed int
    ,perf_score int
    -- not needed -- >>> ,distinct_workers smallint
    ,constraint res_perf_per_minute_pk primary key(id)
    ,constraint res_perf_per_minute_fk foreign key(run_id) references results_overall on delete cascade
);
-----------------------------------------------
-- Table for storing results of SP REPORT_PERF_DETAILED:
recreate table results_perf_detailed(
     id bigint not null
    ,run_id bigint not null
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
    ,constraint res_perf_detailed_pk primary key(id)
    ,constraint res_perf_detailed_fk foreign key(run_id) references results_overall on delete cascade
);
-----------------------------------------------
-- Table for storing results of SP REPORT_EXCEPTIONS:
recreate table results_exceptions(
     id bigint not null
    ,run_id bigint not null
    ,fb_gdscode int
    ,fb_mnemona varchar(31)
    ,unit varchar(80)
    ,cnt int
    ,constraint res_exceptions_pk primary key(id)
    ,constraint res_exceptions_fk foreign key(run_id) references results_overall on delete cascade
);
-----------------------------------------------
-- Table for storing results of SP REPORT_CACHE_DYNAMIC:
recreate table results_cache_dyn(
     id bigint not null
    ,run_id bigint not null
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
    ,constraint res_perf_cache_dyn_pk primary key(id)
    ,constraint res_perf_cache_dyn_fk foreign key(run_id) references results_overall on delete cascade
);
-----------------------------------------------
-- Table for storing results of SP REPORT_PERF_TRACE:
recreate table results_perf_trace(
     id bigint not null
    ,run_id bigint not null
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
    ,constraint res_perf_trace_pk primary key(id)
    ,constraint res_perf_trace_fk foreign key(run_id) references results_overall on delete cascade
);
-----------------------------------------------
-- Table for storing results of SP REPORT_PERF_TRACE_PIVOT:
recreate table results_perf_trace_pivot(
     id bigint not null
    ,run_id bigint not null
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
    ,constraint res_perf_trace_pivot_pk primary key(id)
    ,constraint res_perf_trace_pivot_fk foreign key(run_id) references results_overall on delete cascade
);

-----------------------------------------------
-- Table for storing results of SP REPORT_STAT_PER_UNITS
recreate table results_perf_stat_per_units(
     id bigint not null
    ,run_id bigint not null
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
    ,constraint res_perf_stat_per_units_pk primary key(id)
    ,constraint res_perf_stat_per_units_fk foreign key(run_id) references results_overall on delete cascade
);

-----------------------------------------------
-- Table for storing results of SP REPORT_STAT_PER_TABLES // 3.x+
recreate table results_perf_stat_per_tables(
     id bigint not null
    ,run_id bigint not null
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
    ,constraint res_perf_stat_per_table_pk primary key(id)
    ,constraint res_perf_stat_per_table_fk foreign key(run_id) references results_overall on delete cascade
);

-- 23.06.2020: all lines from HTML reports:
recreate table results_reports(
    id bigint not null
    ,run_id bigint not null
    ,txt varchar(2048) character set utf8 -- deprecated: use only when no compressor presents; 22.08.2020 FB 2.5, 3.x, 4.x: max size = 8190
    ,zip2b64 varchar(80) -- recommended: raw_text -> compress -> base64
    ,constraint res_reports_pk primary key(id)
    ,constraint res_reports_fk foreign key(run_id) references results_overall on delete cascade
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

set term ^;
create or alter trigger trg_results_overall_bi for results_overall active before insert as
begin
    new.run_id = coalesce(new.run_id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_total_bi for results_total active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_per_minute_bi for results_per_minute active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_perf_detailed_bi for results_perf_detailed active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_exceptions_bi for results_exceptions active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_cache_dyn_bi for results_cache_dyn active before insert as
begin
    -- new.run_id = coalesce(new.id, gen_id(g_results,1));
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_perf_trace_bi for results_perf_trace active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_perf_trace_pivot_bi for results_perf_trace_pivot active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_res_perf_stat_per_tables_bi for results_perf_stat_per_tables active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_res_perf_stat_per_units_bi for results_perf_stat_per_units active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

create or alter trigger trg_results_reports_bi for results_reports active before insert as
begin
    new.id = coalesce(new.id, gen_id(g_results,1));
end
^

set term ;^
commit;

--############################################################################

set term ^;
create or alter procedure eds_obtain_last_test_results( 
    oltp_data_db varchar(255)
    ,eds_usr varchar(31)
    ,eds_pwd varchar(31)
    ,mon_unit_perf smallint
) as
    --declare oltp_data_db varchar(255) = 'localhost/3333:/home/bases/oltp30-etalone.fdb';
    --declare eds_usr varchar(31) = 'SYSDBA'; -- from oltpNN config
    --declare eds_pwd varchar(31) = 'masterkey'; -- from oltpNN config
    declare oltp_overall_qry varchar(8192);
    declare oltp_report_qry varchar(8192);
    declare v_mcode varchar(80);
    declare v_svalue varchar(160);
    declare v_run_id bigint;

    -- for storing results of SP report_perf_total:
    declare v_business_action varchar(255);
    declare v_avg_times_per_minute numeric(12,2);
    declare v_avg_elapsed_ms int;
    declare v_successful_times_done int;

    -- for storing results of SP report_perf_per_minute:
    declare v_test_phase varchar(20);
    declare v_minutes_passed int;
    declare v_perf_score int;

    -- for storing results of SP perf_detailed
    --declare v_unit           varchar(80);
    declare v_cnt_all        int;
    declare v_cnt_ok         int;
    declare v_cnt_err        int;
    declare v_err_prc        numeric(6,2);
    declare v_ok_min_ms      int;
    declare v_ok_max_ms      int;
    declare v_ok_avg_ms      int;
    declare v_cnt_lk_confl   int;
    declare v_cnt_user_exc   int;
    declare v_cnt_chk_viol   int;
    declare v_cnt_unq_viol   int;
    declare v_cnt_fk_viol    int;
    declare v_cnt_stack_trc  int;
    declare v_cnt_zero_gds   int;
    declare v_cnt_other_exc  int;

    -- for storing results of SP report_exceptions
    declare v_fb_mnemona varchar(31);
    declare v_cnt int;
    declare v_unit varchar(80);
    declare v_fb_gdscode int;


    -- for storing results of SP report_cache_dynamic:
    declare v_measurement_timestamp timestamp;
    declare v_measurement_elapsed_ms integer;
    declare v_page_cache_memo_used bigint;
    declare v_metadata_cache_memo_used bigint;
    declare v_metadata_cache_prc_of_total numeric(5,3);
    declare v_total_attachments_cnt integer;
    declare v_active_attachments_cnt integer;
    declare v_running_statements_cnt integer;
    declare v_stalled_statements_cnt integer;
    declare v_memo_used_by_attachments bigint;
    declare v_memo_used_by_transactions bigint;
    declare v_memo_used_by_statements bigint;
    declare v_memo_used_all bigint;
    declare v_memo_allo_all bigint;

    -- for storing results of SP report_stat_per_units
    declare v_iter_counts bigint;
    declare v_avg_elap_ms bigint;
    declare v_avg_fetches numeric(12,2);
    declare v_avg_marks numeric(12,2);
    declare v_avg_reads numeric(12,2);
    declare v_avg_writes numeric(12,2);
    declare v_avg_reads_to_fetches numeric(12,4);
    declare v_avg_writes_to_marks numeric(12,4);
    declare v_avg_mem_used bigint;
    declare v_avg_mem_alloc bigint;
    declare v_avg_seq numeric(12,2);
    declare v_avg_idx numeric(12,2);
    declare v_avg_rpt numeric(12,2);
    declare v_avg_bkv numeric(12,2);
    declare v_avg_frg numeric(12,2);
    declare v_avg_bkv_per_rec numeric(12,4);
    declare v_avg_frg_per_rec numeric(12,4);
    declare v_avg_ins numeric(12,2);
    declare v_avg_upd numeric(12,2);
    declare v_avg_del numeric(12,2);
    declare v_avg_bko numeric(12,2);
    declare v_avg_pur numeric(12,2);
    declare v_avg_exp numeric(12,2);
    declare v_avg_locks numeric(12,2);
    declare v_avg_confl numeric(12,2);

    declare perf_score double precision;
    declare test_finish_state varchar(255);
    declare test_abend_gdscode int;

begin
    delete from tmp$field_names;
    -- Make cache of field names of table RESULTS_OVERALL.
    insert into tmp$field_names(fld_name)
    select rf.rdb$field_name as fld_name
    from rdb$relation_fields rf
    join rdb$fields f on f.rdb$field_name = rf.rdb$field_source
    where
        rf.rdb$relation_name = upper('results_overall')
        and f.rdb$computed_blr is null
    ;

    -- query for obtaining **LAST** overall results (perf. score, test finish state, gdscode (if abend occured)).
    -- To be written into table results_overall, columns: perf_score, test_finish_state, test_abend_gdscode
    oltp_overall_qry =
        'select max(perf_score) as perf_score, max(exc_info) as test_finish_state , max(fb_gdscode) as test_abend_gdscode '
        || ' from ( '
        || '     select x.* '
        || '     from ( '
        || '         select unit, null as fb_gdscode, null as exc_info,aux1 as perf_score '
        || '         from perf_log p where p.unit = ''perf_watch_interval'' '
        || '         order by p.dts_beg DESC rows 1 ' -- 24.10.2020: added DESC
        || '     ) x'
        || '     UNION ALL '
        || '     select y.* '
        || '     from ( '
        || '         select unit, fb_gdscode,exc_info, null as aux1 '
        || '         from perf_log p '
        || '         where p.unit = ''sp_halt_on_error'' '
        || '         order by p.dts_beg DESC rows 1 ' -- 24.10.2020: added DESC
        || '     ) y '
        || ' ) z '
    ;

    execute statement (oltp_overall_qry)
        on external (oltp_data_db) as user eds_usr password eds_pwd
    into perf_score, test_finish_state, test_abend_gdscode;

    -- Possible values of :test_finish_state:
    -- ABNORMAL: GDSCODE=nnnnnnnn.
    -- NORMAL: TEST_TIME EXPIRED.
    -- PREMATURE: EXTERNAL COMMAND.
    insert into results_overall( perf_score,   test_finish_state,  test_abend_gdscode )
                         values( :perf_score, :test_finish_state, :test_abend_gdscode )
    returning run_id into v_run_id; -- PK for results_overall;

    ----  s a v i n g    r e p o r t s    d a t a:    b e g i n ---
                -- Obtaining data from REPORT_PERF_TOTAL (use ES/EDS) and save it:
                oltp_report_qry = '
                   select
                      business_action
                      ,avg_times_per_minute
                      ,avg_elapsed_ms
                      ,successful_times_done
                   from report_perf_total
                '
                ;
                for execute statement ( oltp_report_qry )
                on external (oltp_data_db) as user eds_usr password eds_pwd
                into
                    v_business_action
                    ,v_avg_times_per_minute
                    ,v_avg_elapsed_ms
                    ,v_successful_times_done
                do
                begin
                  insert into results_total(
                    run_id
                    ,business_action
                    ,avg_times_per_minute
                    ,avg_elapsed_ms
                    ,successful_times_done
                  )
                  values(
                    :v_run_id
                    ,:v_business_action
                    ,:v_avg_times_per_minute
                    ,:v_avg_elapsed_ms
                    ,:v_successful_times_done
                  );
                end -- cursor on ES/EDS results with data of SP report_perf_total


                -- Obtaining data from REPORT_PERF_PER_MINUTE (use ES/EDS) and save it:
                oltp_report_qry = '
                   select
                       test_phase_name
                       ,minutes_passed
                       ,perf_score
                   from report_perf_per_minute
                '
                ;
                for execute statement ( oltp_report_qry )
                on external (oltp_data_db) as user eds_usr password eds_pwd
                into
                   v_test_phase
                  ,v_minutes_passed
                  ,v_perf_score
                do
                begin
                  insert into results_per_minute(
                    run_id
                    ,test_phase_name
                    ,minutes_passed
                    ,perf_score
                  )
                  values(
                    :v_run_id
                    ,:v_test_phase
                    ,:v_minutes_passed
                    ,:v_perf_score
                  );
                end -- cursor on ES/EDS results with data of SP report_perf_per_minute


                -- Obtaining data from REPORT_PERF_DETAILED (use ES/EDS) and save it:
                oltp_report_qry = '
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
                       ,cnt_user_exc
                   from report_perf_detailed
                '
                ;
                for execute statement ( oltp_report_qry )
                on external (oltp_data_db) as user eds_usr password eds_pwd
                into
                       v_unit
                       ,v_cnt_all
                       ,v_cnt_ok
                       ,v_cnt_err
                       ,v_err_prc
                       ,v_ok_min_ms
                       ,v_ok_max_ms
                       ,v_ok_avg_ms
                       ,v_cnt_lk_confl
                       ,v_cnt_user_exc
                do
                begin
                  insert into results_perf_detailed(
                       run_id
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
                  )
                  values(
                       :v_run_id
                       ,:v_unit
                       ,:v_cnt_all
                       ,:v_cnt_ok
                       ,:v_cnt_err
                       ,:v_err_prc
                       ,:v_ok_min_ms
                       ,:v_ok_max_ms
                       ,:v_ok_avg_ms
                       ,:v_cnt_lk_confl
                       ,:v_cnt_user_exc
                  );
                end -- cursor on ES/EDS results with data of SP report_perf_detailed


                -- Obtaining data from REPORT_EXCEPTIONS (use ES/EDS) and save it:
                oltp_report_qry = 'select fb_mnemona, cnt, unit, fb_gdscode from report_exceptions';
                for execute statement ( oltp_report_qry )
                on external (oltp_data_db) as user eds_usr password eds_pwd
                into v_fb_mnemona, v_cnt, v_unit, v_fb_gdscode
                do
                begin
                  insert into results_exceptions(run_id, fb_mnemona, cnt, unit, fb_gdscode)
                                          values(:v_run_id, :v_fb_mnemona, :v_cnt, :v_unit, :v_fb_gdscode);
                end -- cursor on ES/EDS results with data of SP report_perf_pe_minute
                
                if ( mon_unit_perf = 1 ) then -- mon_unit_perf = 1
                begin
                    -- Config parameter mon_unit_perf = 2.
                    -- Obtaining data from REPORT_STAT_PER_UNITS (use ES/EDS) and save it:
                    oltp_report_qry = '
                    select
                       unit
                       ,iter_counts
                       ,avg_elap_ms
                       ,avg_fetches
                       ,avg_marks
                       ,avg_reads
                       ,avg_writes
                       ,avg_reads_to_fetches
                       ,avg_writes_to_marks
                       ,avg_mem_used
                       ,avg_mem_alloc
                       ,avg_seq
                       ,avg_idx
                       ,avg_rpt
                       ,avg_bkv
                       ,avg_frg
                       ,avg_bkv_per_rec
                       ,avg_frg_per_rec
                       ,avg_ins
                       ,avg_upd
                       ,avg_del
                       ,avg_bko
                       ,avg_pur
                       ,avg_exp
                       ,avg_locks
                       ,avg_confl
                    from report_stat_per_units d
                    '
                    ;
                    for execute statement ( oltp_report_qry )
                    on external (oltp_data_db) as user eds_usr password eds_pwd
                    into
                       v_unit
                       ,v_iter_counts
                       ,v_avg_elap_ms
                       ,v_avg_fetches
                       ,v_avg_marks
                       ,v_avg_reads
                       ,v_avg_writes
                       ,v_avg_reads_to_fetches
                       ,v_avg_writes_to_marks
                       ,v_avg_mem_used
                       ,v_avg_mem_alloc
                       ,v_avg_seq
                       ,v_avg_idx
                       ,v_avg_rpt
                       ,v_avg_bkv
                       ,v_avg_frg
                       ,v_avg_bkv_per_rec
                       ,v_avg_frg_per_rec
                       ,v_avg_ins
                       ,v_avg_upd
                       ,v_avg_del
                       ,v_avg_bko
                       ,v_avg_pur
                       ,v_avg_exp
                       ,v_avg_locks
                       ,v_avg_confl
                    do
                    begin
                        insert into results_perf_stat_per_units(
                            run_id
                           ,unit
                           ,iter_counts
                           ,avg_elap_ms
                           ,avg_fetches
                           ,avg_marks
                           ,avg_reads
                           ,avg_writes
                           ,avg_reads_to_fetches
                           ,avg_writes_to_marks
                           ,avg_mem_used
                           ,avg_mem_alloc
                           ,avg_seq
                           ,avg_idx
                           ,avg_rpt
                           ,avg_bkv
                           ,avg_frg
                           ,avg_bkv_per_rec
                           ,avg_frg_per_rec
                           ,avg_ins
                           ,avg_upd
                           ,avg_del
                           ,avg_bko
                           ,avg_pur
                           ,avg_exp
                           ,avg_locks
                           ,avg_confl
                        )
                        values (
                            :v_run_id
                           ,:v_unit
                           ,:v_iter_counts
                           ,:v_avg_elap_ms
                           ,:v_avg_fetches
                           ,:v_avg_marks
                           ,:v_avg_reads
                           ,:v_avg_writes
                           ,:v_avg_reads_to_fetches
                           ,:v_avg_writes_to_marks
                           ,:v_avg_mem_used
                           ,:v_avg_mem_alloc
                           ,:v_avg_seq
                           ,:v_avg_idx
                           ,:v_avg_rpt
                           ,:v_avg_bkv
                           ,:v_avg_frg
                           ,:v_avg_bkv_per_rec
                           ,:v_avg_frg_per_rec
                           ,:v_avg_ins
                           ,:v_avg_upd
                           ,:v_avg_del
                           ,:v_avg_bko
                           ,:v_avg_pur
                           ,:v_avg_exp
                           ,:v_avg_locks
                           ,:v_avg_confl
                        );
                    end -- cursor on ES/EDS results with data of SP report_stat_per_units

                end -- mon_unit_perf = 1


                if ( mon_unit_perf = 2 ) then -- mon_unit_perf = 2
                begin
                    -- Config parameter mon_unit_perf = 2: we can obtain data from REPORT_CACHE_DYNAMIC (use ES/EDS) and save it:
                    oltp_report_qry = '
                    select
                       measurement_timestamp
                      ,measurement_elapsed_ms
                      ,page_cache_memo_used
                      ,memo_used_all
                      ,memo_allo_all
                      ,metadata_cache_memo_used
                      ,metadata_cache_percent_of_total
                      ,total_attachments_cnt
                      ,active_attachments_cnt
                      ,running_statements_cnt
                      ,stalled_statements_cnt
                      ,memo_used_by_attachments
                      ,memo_used_by_transactions
                      ,memo_used_by_statements
                    from report_cache_dynamic d
                    '
                    ;
                    ----------------------------------
                    for execute statement ( oltp_report_qry )
                    on external (oltp_data_db) as user eds_usr password eds_pwd
                    into 
                       v_measurement_timestamp
                      ,v_measurement_elapsed_ms
                      ,v_page_cache_memo_used
                      ,v_memo_used_all
                      ,v_memo_allo_all
                      ,v_metadata_cache_memo_used
                      ,v_metadata_cache_prc_of_total
                      ,v_total_attachments_cnt
                      ,v_active_attachments_cnt
                      ,v_running_statements_cnt
                      ,v_stalled_statements_cnt
                      ,v_memo_used_by_attachments
                      ,v_memo_used_by_transactions
                      ,v_memo_used_by_statements
                    do
                    begin
                      insert into results_cache_dyn(
                          run_id                       -- FK to results_overall
                          ,measurement_timestamp
                          ,measurement_elapsed_ms
                          ,page_cache_memo_used
                          ,memo_used_all -- 07.06.2020
                          ,memo_allo_all -- 07.06.2020
                          ,metadata_cache_memo_used
                          ,metadata_cache_percent_of_total
                          ,total_attachments_cnt
                          ,active_attachments_cnt
                          ,running_statements_cnt
                          ,stalled_statements_cnt
                          ,memo_used_by_attachments
                          ,memo_used_by_transactions
                          ,memo_used_by_statements
                      )
                      values (
                          :v_run_id
                          ,:v_measurement_timestamp
                          ,:v_measurement_elapsed_ms
                          ,:v_page_cache_memo_used
                          ,:v_memo_used_all -- 07.06.2020
                          ,:v_memo_allo_all -- 07.06.2020
                          ,:v_metadata_cache_memo_used
                          ,:v_metadata_cache_prc_of_total
                          ,:v_total_attachments_cnt
                          ,:v_active_attachments_cnt
                          ,:v_running_statements_cnt
                          ,:v_stalled_statements_cnt
                          ,:v_memo_used_by_attachments
                          ,:v_memo_used_by_transactions
                          ,:v_memo_used_by_statements
                      );
                    end -- cursor on ES/EDS results with data of SP report_cache_dynamic
                end -- mon_unit_perf = 2

    ----  s a v i n g    r e p o r t s    d a t a:    f i n i s h ---

    -- Query to database where test was just finished, SETTINGS table.
    -- Get values only for fields from results_overall table:
    oltp_overall_qry = 'select mcode, svalue from settings s where s.working_mode in ( upper(''init''), upper(''common'') ) ' ;
    for
        execute statement (oltp_overall_qry)
        on external (oltp_data_db) as user eds_usr password eds_pwd
        into v_mcode, v_svalue
    do begin
        if ( exists( select * from tmp$field_names f where f.fld_name = upper( :v_mcode ) ) ) then
        begin
            -- table RESULTS_OVERALL *has* the field with name = :v_mcode
            -- NB: along with other fields, column 'fb_build_no' will be filled here with NON-null value,
            -- that was defined in .sh/.bat routine show_db_and_test_params() via parsing:
            -- fbsvcmgr info_server_version; 'Server version: LI-V3.0.6.33289 Firebird 3.0' ==> 33289
            execute statement ('update or insert into results_overall(run_id, ' || v_mcode || ') values(?, ?) matching(run_id)') (v_run_id, v_svalue);
        end
    end
    -- Final check: column fb_build_no must have NON-null value
    if ( not exists(select * from results_overall r where r.run_id = :v_run_id and r.fb_build_no is not null) ) then
    begin
        exception exc_fb_build_is_null;
    end
end
^ -- end of eds_obtain_last_test_results
set term ;^
commit;
