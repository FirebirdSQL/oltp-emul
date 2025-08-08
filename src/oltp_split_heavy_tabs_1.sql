-- #####################################
-- Begin of script oltp_split_heavy_tabs_1.sql 
-- #####################################
-- ::: NB ::: This script is COMMON for both FB 2.5 and 3.0 and should be called 
-- after oltp_main_filling.sql and oltp_misc_debug.sql 

-- run: isql /3333:oltp30 -i oltp_split_heavy_tabs_1.sql  | sed "s/[ \t]*$//" 1>log.tmp

set echo off;

set term ^;

create or alter procedure tmp_init_autogen_qdistr_tables
as
    declare v_ddl_const varchar(1024);

    declare v_idx_expr1 varchar(1024);
    declare v_idx_expr2 varchar(1024);
    declare v_idx_suff1 varchar(31);
    declare v_idx_suff2 varchar(31);
    declare v_ddl_qdidx1 varchar(1024);
    declare v_ddl_qdidx2 varchar(1024);

    declare v_qd_table varchar(31);
    declare v_qd_suffix varchar(31);
    declare v_ddl_qdistr varchar(1024);
    declare v_id bigint;
    declare v_build_with_qd_compound_ordr varchar(31); -- 'most_selective_first' or 'least_selective_first'
    declare v_separate_workers smallint; -- 12.08.2018
    declare v_make_separate_qd_idx smallint;
begin

    -- Called from 1build_oltp_emul.bat  when config setting create_with_split_heavy_tabs = 1, see:
    -- echo execute procedure tmp_init_autogen_qdistr_tables; >> %...%

    v_ddl_const = '
       id dm_idb not null
      ,doc_id dm_idb -- denorm for speed, also 4debug
      ,worker_id dm_ids -- 12.08.2018
      ,ware_id dm_idb
      ,snd_optype_id dm_ids -- denorm for speed
      ,snd_id dm_idb -- ==> doc_data.id of "sender"
      ,snd_qty dm_qty
      ,rcv_doc_id bigint -- 30.12.2014, always null, for some debug views
      ,rcv_optype_id dm_ids
      ,rcv_id bigint -- nullable! ==> doc_data.id of "receiver"
      ,rcv_qty numeric(12,3)
      ,snd_purchase dm_cost
      ,snd_retail dm_cost
      ,rcv_purchase dm_cost
      ,rcv_retail dm_cost
      ,trn_id bigint default current_transaction
      ,dts timestamp default ''now''
    ';


    -- This row is created in 1run_oltp_emul.bat, in sub-routine "make_db_objects":
    -- Value is defined by config parameter create_with_split_heavy_tabs = 0 | 1.
    select s.svalue 
    from settings s 
    where s.working_mode='COMMON' and s.mcode='BUILD_WITH_SEPAR_QDISTR_IDX'
    into v_make_separate_qd_idx;
    
    -- This row is created in 1run_oltp_emul.bat, in sub-routine "make_db_objects":
    -- Value is defined by config parameter create_with_compound_columns_order = 'most_selective_first' or 'least_selective_first'
    select s.svalue 
    from settings s 
    where s.working_mode='COMMON' and s.mcode='BUILD_WITH_QD_COMPOUND_ORDR'
    into v_build_with_qd_compound_ordr;

    -- Value is defined by config parameter 'separate_workers' = 1 or 0.
    select s.svalue 
    from settings s 
    where s.working_mode = upper('COMMON') and s.mcode = upper('SEPARATE_WORKERS')
    into v_separate_workers;
    
    v_idx_expr1 = '';
    v_idx_expr2 = '';
    -- 24.10.2015: do NOT remove 'snd_optype_id' and 'rcv_optype_id' from index key
    -- otherwise excessive index scans will occur in each XQD* table even if it has no
    -- such key. See SP srv_find_qd_qs_mism which is called after each document creation
    -- (this SP, in turn, is called from doc_list_aiud trigger when QMISM_VERIFY_BITSET = 1,
    -- see oltp_main_filling.sql).
    -- See also sp_get_clo_for_invoice - there is query that search only for ware_id, w/o snd_id!
    if ( v_make_separate_qd_idx = 1 ) then
        -- ###########################################################
        -- ### create TWO INDICES for XQD***: compound and ordinar ###
        -- ###########################################################
        begin
            if ( upper(v_build_with_qd_compound_ordr) = upper('least_selective_first') ) then
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'sop_rop_ware';
                        end
                    else
                        begin
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id, worker_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'so_ro_wa_wkr';
                        end
                    v_idx_expr2 = '(snd_id)';
                    v_idx_suff2 = 'snd';
                end
            else -- 'most_selective_first'
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'ware_sop_rop';
                        end
                    else
                        begin
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id, worker_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'wa_so_ro_wkr';
                        end
                    v_idx_expr2 = '(snd_id)';
                    v_idx_suff2 = 'snd';
                end
        end
    else
        -- ###############################################
        -- ### create SINGLE compound index for XQD*** ###
        -- ###############################################
        begin
            if ( upper(v_build_with_qd_compound_ordr) = upper('least_selective_first') ) then
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id, snd_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'sop_rop_ware_snd';
                        end
                    else
                        begin
                            -- 21.08.2018 19:20 ==> performance score = 05553 (!) ### BEST ### ?!
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id, worker_id, snd_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'so_ro_wa_wkr_snd';
                            
                            -- 21.08.2018 18:10 ==> performance score = ~1070
                            -- v_idx_expr1 = '(snd_optype_id, rcv_optype_id, worker_id, ware_id, snd_id)'; -- do NOT remove snd_optype & rcv_optype!
                            -- v_idx_suff1 = 'so_ro_wkr_wa_snd';
                        end
                end
            else -- 'most_selective_first'
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id, snd_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'ware_sop_rop_snd';
                        end
                    else
                        begin
                           -- retest, 21.08.2018 16:47 ==> performance score = 05399
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id, worker_id, snd_id)'; -- do NOT remove snd_optype & rcv_optype!
                            v_idx_suff1 = 'wa_so_ro_wkr_snd';

                            -- 21.08.2018: probe, move 'worker_id' to beginning of key  ==> performance score = 04346
                            --v_idx_expr1 = '(ware_id, worker_id, snd_optype_id, rcv_optype_id, snd_id)'; -- do NOT remove snd_optype & rcv_optype!
                            --v_idx_suff1 = 'wa_wkr_so_ro_snd';
                        end
                end
        end

    for
        select '' || q.snd_optype_id || '_' || q.rcv_optype_id
        from rules_for_qdistr q
        where q.snd_optype_id is not null
        into v_qd_suffix --------------------------- '1000_1200'; '1200_2000' etc
    do begin
        v_qd_table = 'xqd_' || v_qd_suffix;
        v_ddl_qdistr = 'recreate table ' || v_qd_table || '(' || v_ddl_const || ')';
        
        v_ddl_qdidx1 = 'create index ' || v_qd_table || '_' || v_idx_suff1 || ' on ' || v_qd_table || v_idx_expr1;
        v_ddl_qdidx2 = 'create index ' || v_qd_table || '_' || v_idx_suff2 || ' on ' || v_qd_table || v_idx_expr2;

        in autonomous transaction do
        begin
            -- Here we create TABLE xqd_****:
            execute statement v_ddl_qdistr;

            -- 12.08.2018
            -- ?? --> dis 21.08.2018 --> execute statement 'create index ' || v_qd_table || '_worker_id on ' || v_qd_table || '(worker_id)';

            if ( not v_ddl_qdidx1 = '' ) then execute statement v_ddl_qdidx1;
            if ( not v_ddl_qdidx2 = '' ) then execute statement v_ddl_qdidx2;
            

            if ( v_qd_suffix = '1000_3300' ) then
            begin
                -- ###########################################################################################################
                -- ###  c r e a t e      a d d i t i o n a l     i n d i c e s     f o r    v_min_clo_res / v_max_clo_res  ###
                -- ###########################################################################################################
                -- initially was 13.11.2015 ("make v_min_id_clo_res much faster"); refactored 11.01.2019: 
                -- performance of views v_min_id_clo_res and v_max_id_clo_res can be significantly increased underlied query
                -- will select only from SINGLE table (xqd_1000_3300) and, moreover, will have appropriate index for each view:
                if ( v_separate_workers = 0 ) then
                    begin
                        -- field 'worker_id' yet present there, but always is NULL, so it is useless:
                        execute statement 'create index xqd_1000_3300_doc_asc on xqd_1000_3300(doc_id)';
                        execute statement 'create DESCENDING index xqd_1000_3300_doc_dec on xqd_1000_3300(doc_id)';
                    end
                else
                    begin
                        execute statement 'create index xqd_1000_3300_wkr_doc_asc on xqd_1000_3300(worker_id, doc_id)';
                        execute statement 'create DESCENDING index xqd_1000_3300_wkr_doc_dec on xqd_1000_3300(worker_id, doc_id)';
                    end
            end

        end
    end
    if ( v_ddl_qdistr is null ) then
       -- This script should be called ***AFTER*** oltp_main_filling.sql which does fill table 'optypes'.
       -- Probably this table currently is empty!
       exception ex_record_not_found;
       --'required record not found, datasource: @1, key: @2';


end -- tmp_init_autogen_qdistr_tables

^ 
set term ;^
commit;

set term ^;

create or alter procedure tmp_init_autogen_qstorn_tables
as
    declare v_ddl_const varchar(1024);
    declare v_idx_expr1 varchar(1024);
    declare v_idx_expr2 varchar(1024);
    declare v_idx_expr3 varchar(1024);
    declare v_qs_table varchar(31);
    declare v_qs_suffix varchar(31);
    declare v_ddl_qstorn varchar(1024);
    declare v_ddl_qsidx1 varchar(1024);
    declare v_ddl_qsidx2 varchar(1024);
    declare v_ddl_qsidx3 varchar(1024);
    declare v_id bigint;
    declare v_separate_workers smallint; -- 12.08.2018
begin
    -- Called from 1build_oltp_emul.bat  when config setting create_with_split_heavy_tabs = 1, see:
    -- echo execute procedure tmp_init_autogen_qstorn_tables; >> %...%

    select s.svalue 
    from settings s 
    where s.working_mode = upper('COMMON') and s.mcode = upper('SEPARATE_WORKERS')
    into v_separate_workers;

    v_ddl_const = '
       id dm_idb not null
      ,doc_id dm_idb -- denorm for speed
      ,worker_id dm_ids -- 12.08.2018
      ,ware_id dm_idb
      ,snd_optype_id dm_ids -- denorm for speed
      ,snd_id dm_idb -- ==> doc_data.id of "sender"
      ,snd_qty dm_qty
      ,rcv_doc_id dm_idb -- 30.12.2014, for enable to remove PK on doc_data, see S    P_LOCK_DEPENDENT_DOCS
      ,rcv_optype_id dm_ids
      ,rcv_id dm_idb
      ,rcv_qty dm_qty
      ,snd_purchase dm_cost
      ,snd_retail dm_cost
      ,rcv_purchase dm_cost
      ,rcv_retail dm_cost
      ,trn_id bigint default current_transaction
      ,dts timestamp default ''now''
    ';
    v_idx_expr1='(doc_id)';
    v_idx_expr2='(snd_id)';
    v_idx_expr3='(rcv_id)';
    for
        select '' || q.snd_optype_id || '_' || q.rcv_optype_id
        from rules_for_qdistr q
        where q.snd_optype_id is not null
        into v_qs_suffix
    do begin
        v_qs_table = 'xqs_' || v_qs_suffix;
        v_ddl_qstorn = 'recreate table ' || v_qs_table || '(' || v_ddl_const || ')';
        v_ddl_qsidx1 = 'create index '||v_qs_table||'_doc_id on ' || v_qs_table || v_idx_expr1;
        v_ddl_qsidx2 = 'create index '||v_qs_table||'_snd_id on ' || v_qs_table || v_idx_expr2;
        v_ddl_qsidx3 = 'create index '||v_qs_table||'_rcv_id on ' || v_qs_table || v_idx_expr3;
        in autonomous transaction do
        begin

            -- Here we create TABLE xqs_****:
            execute statement v_ddl_qstorn;

            -- 12.08.2018
            if ( v_separate_workers = 1 ) then
                execute statement 'create index ' || v_qs_table || '_worker_id on ' || v_qs_table || '(worker_id)';

            execute statement v_ddl_qsidx1;
            execute statement v_ddl_qsidx2;
            if ( upper(v_qs_table) <> upper('xqs_3300_3400') ) then
                -- 25.11.2015, look at index statistics of 'xqs_3300_3400': 
                -- there are 100% dups in the field 'rcv_id', it has NULL value in all rows.
                -- We have to avoid creation of this index, it's absolutely useless!
                execute statement v_ddl_qsidx3;
        end
    end

    if ( v_ddl_qstorn is null ) then 
       -- This script should be called ***AFTER*** oltp_main_filling.sql which does fill table 'optypes'.
       -- Probably this table currently is empty!
       exception ex_record_not_found;

end 

^ -- tmp_init_autogen_qstorn_tables


set term ;^
commit;

-- |||||||||||||||||||||||||||||||||||   M A I N     S T A R T   |||||||||||||||||||||||||||||||

set list on;

select 'set echo off;' as "--TMP$SQL$CODE"
from rdb$database
union all
select 'set list on;'
from rdb$database
union all
select 'select ''oltp_split_heavy_tabs_1.sql start at '' || current_timestamp as msg from rdb$database;'
from rdb$database
;

--select 'select ''oltp_split_heavy_tabs_1.sql start at '' || current_timestamp as msg from rdb$database;' as "--TMP$SQL$CODE"
--from rdb$database
--union all
--select 'set echo off;'
--from rdb$database
--;

commit;

--set transaction no wait;
set term ^;
execute block returns("--TMP$SQL$CODE" varchar(32765)) as
  declare v_lf char(10);

  declare v_old_name varchar(31);
  declare v_qd_auto_name varchar(31);
  declare v_qd_targ_name varchar(31);
  declare v_qs_auto_name varchar(31);
  declare v_qs_targ_name varchar(31);

  declare v_qd_name_4del varchar(31);
  declare v_qd_name_4ins varchar(31);
  declare v_qs_name_4del varchar(31);
  declare v_qs_name_4ins varchar(31);

  declare v_sp_auto_name varchar(31);
  declare sp_init_name varchar(31);
  declare sp_repl_name varchar(31);
  declare v_src varchar(32765);

  declare v_proc_body varchar(32765);
  declare v_body_repl varchar(32765);

  declare v_body_line varchar(8190) character set utf8;
  declare v_line_repl varchar(8190) character set utf8;

  declare vew_for_inject varchar(31);
  declare v_add_comment smallint;
  declare i int;
  declare k smallint;

  declare v_snd_optype_id dm_idb;
  declare v_rcv_optype_id dm_idb;
  declare v_storno_sub smallint;


  declare v_name_fin varchar(31);
  declare v_name_min varchar(31);
  declare v_name_max varchar(31);
  declare v_line_type varchar(12);

  declare v_sour_snd_op dm_idb;
  declare v_sour_rcv_op dm_idb;
  declare v_targ_snd_op dm_idb;
  declare v_targ_rcv_op dm_idb;
  declare v_qd_names varchar(32765);
  declare v_qs_names varchar(32765);

  declare v_separate_workers smallint;

begin
   
    -- Value is defined by config parameter 'separate_workers' = 1 or 0.
    select s.svalue 
    from settings s 
    where s.working_mode = upper('COMMON') and s.mcode = upper('SEPARATE_WORKERS')
    into v_separate_workers;
    
    v_lf = ascii_char(10);

    
    "--TMP$SQL$CODE" =    v_lf || 'set bail on;'
          || v_lf || '-- #########'
          || v_lf || 'execute procedure tmp_init_autogen_qdistr_tables;'
          || v_lf || 'execute procedure tmp_init_autogen_qstorn_tables;'
          || v_lf || 'commit;'
    ;

    suspend;


    -- Change target table that will be affected in SP_MULTIPLY_ROWS_FOR_QDISTR when
    -- client order is created ("Qdistr" ==> "XQD_1000_1200"):
    "--TMP$SQL$CODE" = 'alter view v_qdistr_multiply_1 as '; 
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '-- ### DDL has been auto replaced because of test config requirements. DO NOT EDIT! ###';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'select * from XQD_1000_1200';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || ';'
    ;

    suspend;


    "--TMP$SQL$CODE" = 'alter view v_qdistr_multiply_2 as '; 
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '-- ### DDL has been auto replaced because of test config requirements. DO NOT EDIT! ###';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'select * from XQD_1000_3300';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || ';'
    ;

    suspend;


    -- ||||||||||||||||||||||||||||||||||||||||||||||||||||||
    -- Replace source of with code of "redirectors":
    -- {sp_ret_qs2qd_on_canc_wroff, sp_ret_qs2qd_on_canc_reserve, sp_ret_qs2qd_on_canc_invoice, sp_ret_qs2qd_on_canc_supp_order}
    -- with code from sp_kill_qstorno_ret_qs2qd in which we use special views as aliases for qDistr & qStorned:
    -- v_qdistr_name_for_del, v_qdistr_name_for_ins, v_qstorno_name_for_del and v_qstorno_name_for_ins
    
    i = 1;
    while (i<=5) do
    begin
        sp_repl_name = 'SP_KILL_QSTORNO_RET_QS2QD';
        v_sp_auto_name = decode(i, 1, 'sp_ret_qs2qd_on_canc_wroff', 
                                   2, 'sp_ret_qs2qd_on_canc_reserve', 
                                   3, 'sp_ret_qs2qd_on_canc_res_aux',
                                   4, 'sp_ret_qs2qd_on_canc_invoice', 
                                      'sp_ret_qs2qd_on_canc_supp_order');

        v_qd_name_4del =
            decode(i,
                1, 'xqd_3300_3400', -- cancel write-off: name is STUB here, no rows in xqD_xxxx for this op. // old: autogen_qd3400
                2, 'xqd_3300_3400', -- cancel reserve: table where rows will be REMOVED // old: autogen_qd3300
                3, 'xqd_1000_3300', -- cancel reserve: name is STUB here, real action will be on v_qs_name_4del // old: autogen_qd1000
                4, 'xqd_2000_3300', -- cancel invoice (not closed): table where rows will be removed // old: autogen_qd2000
                   'xqd_1200_2000'  -- cancel supp. order: table where rows will be removed // old: autogen_qd1200
            );
        v_qd_name_4ins =
            decode(i,
                1, 'xqd_3300_3400', -- cancel write-off: target for add row (ret from qStorned) // old: autogen_qd3300
                2, 'xqd_2100_3300', -- cancel reserve: target for add 1st rows (ret from qStorned) // old: autogen_qd2100
                3, 'xqd_1000_3300', -- cancel reserve, aux: target for add 2nd row (ret from qStorned) // old: autogen_qd1000
                4, 'xqd_1200_2000', -- cancel invoice (not closed): // old: autogen_qd1200
                   'xqd_1000_1200'  -- cancel supp. order: target for add row (ret from qStorned) // old: autogen_qd1000
            );
        v_qs_name_4del =
            decode(i,
                1, 'xqs_3300_3400', -- cancel write-off: qSt0rno-table where rows will be removed // old: autogen_qs3300
                2, 'xqs_2100_3300', -- cancel reserve: qSt0rno-table where rows will be removed // old: autogen_qs2100
                3, 'xqs_1000_3300', -- cancel reserve, aux: qSt0rno where 2nd row will be removed // old: autogen_qs1000
                4, 'xqs_1200_2000', -- cancel invoice (not closed): qSt0rno where rows will be removed // old: autogen_qs1200
                   'xqs_1000_1200'  -- cancel supp. order: qSt0rno where rows will be removed // old: autogen_qs1000
            );

        -- Adding rows in qSt0rno actually occurs only in SP_reserve_write_off,
        -- see usage of view "v_qstorno_name_for_ins"
        -- Here all these are STUBS only, there is no such code that will be affected by replace():
        v_qs_name_4ins =
            decode(i,
                1, 'xqs_3300_3400', -- cancel write-off: target qSt0rno for ADD rows // old: autogen_qs3300
                2, 'xqs_2100_3300', -- cancel reserve: target qSt0rno for ADD rows // old: autogen_qs2100
                3, 'xqs_1000_3300', -- cancel reserve, aux:  target qSt0rno for ADD rows // old: autogen_qs1000
                4, 'xqs_1200_2000', -- cancel invoice (not closed): target qSt0rno for ADD rows // old: autogen_qs1200
                   'xqs_1000_1200'  -- cancel supp. order: target qSt0rno for ADD rows // old: autogen_qs1000
            );

        
        select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
        from rdb$procedures p
        where p.rdb$procedure_name = upper(:sp_repl_name)
        into v_proc_body;

        v_body_repl = '';

        for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
        do begin
          v_line_repl = replace( v_body_line collate unicode_ci , 'v_qdistr_name_for_del', v_qd_name_4del);
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_name_for_ins', v_qd_name_4ins);
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_del', v_qs_name_4del);
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_ins', v_qs_name_4ins);
          v_body_repl = v_body_repl || v_line_repl || v_lf;
        end

      
        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
        for
            select src from SYS_GET_PROC_DDL(:v_sp_auto_name,-1,0) where src is not null into v_src
        do begin
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || replace(v_src, ' '||sp_repl_name, ' '||v_sp_auto_name) || v_lf;
        end
    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || v_lf;
    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### GENERATED AUTO, BASED ON '||sp_repl_name||'. DO NOT EDIT ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### References to "v_qdistr_name_for_*" were replaced with "'||upper(v_qd_name_4del)||'" and "'||upper(v_qd_name_4ins)||'" ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_3" varchar(255) = ''### References to "v_qstorno_name_for_*" were replaced with "'||upper(v_qs_name_4del)||'" and "'||upper(v_qs_name_4ins)||'" ###'';' || v_lf;
    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || v_body_repl;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';
    
        suspend;

        i = i + 1;

    end -- i = 1..4

    -- ||||||||||||||||||||||||||||||||||||||||||||

    -- Replace source of SP_QD_HANDLE_ON_RESERVE_UPD_STS: 
    -- inject new names instead of 'v_qdistr_name_for_del' and 'v_qstorno_name_for_ins'
    sp_repl_name = 'SP_QD_HANDLE_ON_RESERVE_UPD_STS'; -- is called when SP_RESERVE_WRITE_OFF works

    v_qd_name_4del = 'xqd_3300_3400'; -- where record will be removed // old: autogen_qd3300
    v_qs_name_4ins = 'xqs_3300_3400'; -- where record will be inserted // old: autogen_qs3300

    v_proc_body='';

    select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
    from rdb$procedures p
    where p.rdb$procedure_name = upper(:sp_repl_name)
    into v_proc_body;

    v_body_repl = '';

    for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
    do begin
      v_line_repl = replace( v_body_line collate unicode_ci , 'v_qdistr_name_for_del', v_qd_name_4del);
      -- not needed here: v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_name_for_ins', v_qd_name_4ins);
      -- not needed here: v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_del', v_qs_name_4del);
      v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_ins', v_qs_name_4ins);

      v_body_repl = v_body_repl || v_line_repl || v_lf;
    end

    "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
    for
        select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) where src is not null into v_src
    do begin
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_src || v_lf; -- add empty line after last SP header line
    end

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### GENERATED AUTO, BASED ON '||sp_repl_name||'. DO NOT EDIT ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### Deletion from "v_qdistr_name_for_del" was replaced with "'||upper(v_qd_name_4del)||'" ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_3" varchar(255) = ''### Insertion into "v_qstorno_name_for_ins" was replaced with "'||upper(v_qs_name_4ins)||'" ###'';' || v_lf || v_lf;

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_body_repl;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';

    suspend;


    -- ||||||||||||||||||||||||||||||||||||||||||||||||||||||
    -- Replace source of SP_QD_HANDLE_ON_CANCEL_CLO: inject new names instead of
    -- 'v_qdistr_name_for_del' and 'v_qstorno_name_for_del'
    sp_repl_name = 'SP_QD_HANDLE_ON_CANCEL_CLO'; -- is called when SP_CANCEL_CLIENT_ORDER works


    --v_qd_name_4del = 'autogen_qd1000'; -- where record will be removed
    --v_qs_name_4del = 'autogen_qs1000'; -- where record will be removed

    v_proc_body='';

    select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
    from rdb$procedures p
    where p.rdb$procedure_name = upper(:sp_repl_name)
    into v_proc_body;

    v_body_repl = '';

    for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
    do begin
          v_line_repl = replace( v_body_line collate unicode_ci , 'v_qdistr_target_1', 'xqd_1000_3300');
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_target_2', 'xqd_1000_1200');
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorned_target_1', 'xqs_1000_3300');
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorned_target_2', 'xqs_1000_1200');

          -- not needed here: v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_name_for_ins', v_qd_name_4ins);
          -----v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_del', v_qs_name_4del);
          -- not needed here:  v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_ins', v_qs_name_4ins);

          v_body_repl = v_body_repl || v_line_repl || v_lf;
    end

    "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
    for
        select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) where src is not null into v_src
    do begin
        v_src = trim(trailing from v_src);
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_src || v_lf;  -- add empty line after last SP header line
    end

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### GENERATED AUTO, BASED ON '||sp_repl_name||'. DO NOT EDIT ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### References to "v_qdistr_target_*" were replaced with "xqd_1000_3300" and "xqd_1000_1200" ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_3" varchar(255) = ''### References to "v_qstorned_target_*" were replaced with "xsd_1000_3300" and "xsd_1000_1200" ###'';' || v_lf || v_lf;

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_body_repl;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';

    suspend;


    -- ||||||||||||||||||||||||||||||||||||||||||||
    -- Replace source of REDIRECTORS: sp_qd_handle_on_invoice_adding and sp_qd_handle_on_invoice_reopen: 
    -- now instead of redirection to sp_qd_handle_on_invoice_upd_sts these procedures have to do appropriate work themselves.
    -- ::: NB :::
    -- These procedures should be changed BEFORE procedure SP_QD_HANDLE_ON_INVOICE_UPD_STS which source is BASIS for them!
    i = 1;
    while (i <=2 ) do
    begin
        sp_repl_name = 'SP_QD_HANDLE_ON_INVOICE_UPD_STS'; -- its body will be added in currently empty two procedures

        sp_init_name = iif(i=1, 'SP_QD_HANDLE_ON_INVOICE_ADDING', 'SP_QD_HANDLE_ON_INVOICE_REOPEN');
        --v_qd_name_4del = iif(i=1, 'autogen_qd2000', 'autogen_qd2100');
        --v_qd_name_4ins = iif(i=1, 'autogen_qd2100', 'autogen_qd2000');

        v_qd_name_4del = iif(i=1, 'xqd_2000_3300', 'xqd_2100_3300');
        v_qd_name_4ins = iif(i=1, 'xqd_2100_3300', 'xqd_2000_3300');

        -- Extract DDL of proc "sp_qd_handle_on_invoice_upd_sts" and take it as basis for recreating procedures
        -- sp_qd_handle_on_invoice_adding and sp_qd_handle_on_invoice_reopen, with appropriate replacements:

        select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
        from rdb$procedures p
        where p.rdb$procedure_name = upper(:sp_repl_name)
        into v_proc_body;


        v_body_repl = '';
        for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
        do begin
          v_line_repl = replace( v_body_line collate unicode_ci , 'v_qdistr_name_for_del', v_qd_name_4del);
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_name_for_ins', v_qd_name_4ins);
          -- not needed here:  v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_del', v_qs_name_4del);
          -- not needed here:  v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_ins', v_qs_name_4ins);

          v_body_repl = v_body_repl || v_line_repl || v_lf;
        end

        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
        for
            select src from SYS_GET_PROC_DDL(:sp_init_name,-1,0) where src is not null into v_src
        do begin
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_src || v_lf;
        end

    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || v_lf;
    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### GENERATED AUTO, BASED ON '||sp_repl_name||'. DO NOT EDIT ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### References to "V_QD_ALIAS_FOR_DEL" were replaced with "'||upper(v_qd_name_4del)||'" ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_3" varchar(255) = ''### References to "V_QD_ALIAS_FOR_INS" were replaced with "'||upper(v_qd_name_4ins)||'" ###'';' || v_lf;

    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_body_repl;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';
    
        suspend;

        i = i + 1;

    end


    -- ||||||||||||||||||||||||||||||||||||||||||||

    -- Replace source of SP_QD_HANDLE_ON_INVOICE_UPD_STS: inject new names instead of 'from qdistr' and 'into qdistr'
    -- ### !!! NB !!! ###
    -- Replacing this SP source must be AFTER replacement of procedures that serve as redirectors when create_with_split_heavy_tabs = 0:
    -- sp_qd_handle_on_invoice_adding and sp_qd_handle_on_invoice_reopen, because they have to take INITIAL source
    -- code of SP_QD_HANDLE_ON_INVOICE_UPD_STS for their own changing!

    sp_repl_name = 'SP_QD_HANDLE_ON_INVOICE_UPD_STS';

    v_qd_name_4del = 'xqd_2000_3300'; -- where record will be removed
    v_qd_name_4ins = 'xqd_2100_3300'; -- where record will be inserted

    v_proc_body='';

    select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
    from rdb$procedures p
    where p.rdb$procedure_name = upper(:sp_repl_name)
    into v_proc_body;


    v_body_repl = '';

    for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
    do begin
          v_line_repl = replace( v_body_line collate unicode_ci , 'v_qdistr_name_for_del', v_qd_name_4del);
          v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_name_for_ins', v_qd_name_4ins);
          -- not needed here:  v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_del', v_qs_name_4del);
          -- not needed here:  v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorno_name_for_ins', v_qs_name_4ins);

          v_body_repl = v_body_repl || v_line_repl || v_lf;
    end

    "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
    for
        select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) where src is not null into v_src
    do begin
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_src || v_lf;  -- add empty line after last SP header line
    end

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### GENERATED AUTO, BASED ON '||sp_repl_name||'. DO NOT EDIT ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### Deletion from "v_qdistr_name_for_del" was replaced with "'||upper(v_qs_name_4del)||'" ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_3" varchar(255) = ''### Insertion into "v_qdistr_name_for_ins" was replaced with "'||upper(v_qd_name_4ins)||'" ###'';' || v_lf || v_lf;

    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_body_repl;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';

    suspend;


    -- ||||||||||||||||||||||||||||||||||||||||||||
    -- Replace source of SP_LOCK_DEPENDENT_DOCS: inject new names instead of 'from qstorned'
    -- Also replace source of sp_cancel_supplier_invoice and sp_cancel_supplier_order:
    -- inject there new name of SP_LOCK_DEPENDENT_DOCS

    -- First, create procedures with empty source:
    i = 1;
    while (i <=2 ) do
    begin
        sp_repl_name = 'SP_LOCK_DEPENDENT_DOCS'; -- used when we call sp_cancel_supplier_invoice and sp_cancel_supplier_order
        v_sp_auto_name = iif(i=1, 'X_LOCK_DEPDOCS_ON_CANC_SUP_ORD', 'X_LOCK_DEPDOCS_ON_CANC_INVOICE'); -- new names of 'SP_LOCK_DEPENDENT_DOCS'

        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
        for
            select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) where src is not null into v_src
        do begin
            v_src = trim(trailing from v_src);
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || replace(v_src, ' '||sp_repl_name, ' '||v_sp_auto_name) || v_lf;
        end
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'begin' || v_lf || 'end';
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';
        suspend;
        -- Result: STUB code has been generated for X_LOCK_DEPDOCS_ON_CANC_SUP_ORD and X_LOCK_DEPDOCS_ON_CANC_INVOICE.
        -- In the next loop we can refer to these procedures while doing injections into source code of 
        -- SP_CANCEL_SUPPLIER_ORDER and SP_ADD_INVOICE_TO_STOCK
        i = i+1;
    end

    -- Second, make replacements: any call of SP_LOCK_DEPENDENT_DOCS is replaced
    -- with 1) X_LOCK_DEPDOCS_ON_CANC_SUP_ORD or 2) X_LOCK_DEPDOCS_ON_CANC_INVOICE
    -- (depending on SP we correct on each iter: SP_CANCEL_SUPPLIER_ORDER or SP_ADD_INVOICE_TO_STOCK)
    i = 1;
    while (i <=2 ) do
    begin
        sp_repl_name = 'SP_LOCK_DEPENDENT_DOCS'; -- used when we call sp_cancel_supplier_invoice and sp_cancel_supplier_order
        v_sp_auto_name = iif(i=1, 'X_LOCK_DEPDOCS_ON_CANC_SUP_ORD', 'X_LOCK_DEPDOCS_ON_CANC_INVOICE'); -- new names of 'SP_LOCK_DEPENDENT_DOCS'

        sp_init_name = iif(i=1, 'SP_CANCEL_SUPPLIER_ORDER', 'SP_ADD_INVOICE_TO_STOCK'); -- where we replace call to old name ('SP_LOCK_DEPENDENT_DOCS') with new one
        -- // old: v_qs_auto_name = iif(i=1, 'autogen_qs1200', 'autogen_qs2100'); -- where we have to search dependent docs

        -- where we have to search dependent docs:
        v_qs_auto_name =
            iif(i=1,
                'xqs_1200_2000', -- we have to find INVOICES when cancelling order to SUPPLIER
                'xqs_2100_3300'  -- we have to find RESERVES when cancelling INVOICE from supplier
            );

        select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
        from rdb$procedures p
        where p.rdb$procedure_name = upper(:sp_repl_name)
        into v_proc_body;

        v_body_repl = '';

        for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
        do begin
            v_line_repl = replace( v_body_line collate unicode_ci , 'v_qstorned_source', v_qs_auto_name);

            if ( trim(v_line_repl) starting with 'declare' 
                 and v_line_repl containing 'v_this' 
                 and v_line_repl containing sp_repl_name ) then
                v_line_repl = replace( v_body_line collate unicode_ci , sp_repl_name, lower(v_sp_auto_name));

            v_body_repl = v_body_repl || v_line_repl || v_lf;
        end


        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
        for
            select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) where src is not null into v_line_repl
        do begin
            --v_line_repl = trim(trailing from v_src);
            v_line_repl = replace( v_line_repl collate unicode_ci , ' '||sp_repl_name, ' '||lower(v_sp_auto_name)) ||v_lf;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || v_line_repl; -- replace(v_src, ' '||sp_repl_name, ' '||v_sp_auto_name) || v_lf;
        end

        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || v_lf;
    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### GENERATED AUTO, BASED ON '||sp_repl_name||'. DO NOT EDIT ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### References to "v_qstorned_source" were replaced with "'||upper(v_qs_auto_name)||'" ###'';' || v_lf || v_lf;
    
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_body_repl;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';

        suspend;

        -- Result: get source code for X_LOCK_DEPDOCS_ON_CANC_SUP_ORD or X_LOCK_DEPDOCS_ON_CANC_INVOICE
        -- (these procedures now have to be called from SP_CANCEL_SUPPLIER_ORDER and SP_ADD_INVOICE_TO_STOCK
        -- instead of old call to common SP_LOCK_DEPENDENT_DOCS).

        -- Now we have to change source of SP_CANCEL_SUPPLIER_ORDER | SP_ADD_INVOICE_TO_STOCK:
        v_add_comment = 0;
        -- sp_init_name = iif(i=1, 'SP_CANCEL_SUPPLIER_ORDER', 'SP_ADD_INVOICE_TO_STOCK'); -- where we replace call to old name ('SP_LOCK_DEPENDENT_DOCS') with new one

        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;

        for
            select src from SYS_GET_PROC_DDL(:sp_init_name,1,0) where src is not null into v_line_repl
        do begin
            v_line_repl = trim(trailing from v_line_repl);
            if (v_add_comment = 0 and lower(trim(v_line_repl)) starting with 'declare' ) then
            begin
               v_add_comment = 1;
               v_line_repl = v_lf
                       || 'declare "-- ACHTUNG_READ_ME" VARCHAR(255) = ''### References of "'||sp_repl_name||'" were replaced with "'|| v_sp_auto_name ||'" DO NOT EDIT.### '';'
                       || v_lf || v_lf 
                       || v_line_repl;
            end

            if ( sp_init_name = 'SP_CANCEL_SUPPLIER_ORDER' ) then
            begin
                if ( v_line_repl containing sp_repl_name and v_line_repl containing 'oper_order_for_supplier' ) then
                    begin
                        v_line_repl = replace( v_line_repl collate unicode_ci, sp_repl_name, lower('X_LOCK_DEPDOCS_ON_CANC_SUP_ORD') );
                    end
                else if ( v_line_repl containing sp_repl_name and v_line_repl containing 'oper_invoice_add'  ) then
                    begin
                        v_line_repl = replace( v_line_repl collate unicode_ci, sp_repl_name, lower('X_LOCK_DEPDOCS_ON_CANC_INVOICE') );
                    end
            end
            else if ( v_line_repl containing sp_repl_name ) then
                v_line_repl = replace( v_line_repl collate unicode_ci, sp_repl_name, lower('X_LOCK_DEPDOCS_ON_CANC_INVOICE') );

            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || v_line_repl;

        end

        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^' || v_lf || 'set term ;^';
        suspend;

        i = i + 1;
    end

    -- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
    -- #########################################################################
    -- For each record from table 'rules_for_qdistr' generate procedure that will
    -- do quantity distribution that correspond to source = 'autogen_qd' || snd_optype_id
    -- and target = 'autogen_qd' || rcv_optype_id.

    sp_repl_name = 'SP_MAKE_QTY_STORNO';
--    for
--    select 
--        snd_optype_id,
--        rcv_optype_id,
--        storno_sub
--    from rules_for_qdistr
--    where snd_optype_id is not null and rcv_optype_id is not null and storno_sub = 1
--    into v_snd_optype_id, v_rcv_optype_id, v_storno_sub

    for
    select --s.*, t.*
            s.snd_optype_id sour_snd_op,
            s.rcv_optype_id sour_rcv_op,
            t.snd_optype_id targ_snd_op,
            t.rcv_optype_id targ_rcv_op
    from (
        select 
            s.snd_optype_id,
            s.rcv_optype_id,
            s.storno_sub
        from rules_for_qdistr s
        where s.snd_optype_id is not null and s.rcv_optype_id is not null and s.storno_sub = 1
    ) s
    left join rules_for_qdistr t on s.rcv_optype_id = t.snd_optype_id
    into v_sour_snd_op, v_sour_rcv_op, v_targ_snd_op, v_targ_rcv_op
    do begin

       /*
            MODE    SND_OPTYPE_ID    RCV_OPTYPE_ID    STORNO_SUB
            distr+new_doc    1000    1200    1
            distr+new_doc    1200    2000    1
            distr+new_doc    2100    3300    1

            SOUR_SND_OP    SOUR_RCV_OP    TARG_SND_OP    TARG_RCV_OP
            1000    1200    1200    2000
            1200    2000    2000    3300
            2100    3300    3300    3400
        */

        v_sp_auto_name = 'X_MAKE_QSTORNO_' || v_sour_snd_op || '_' || v_sour_rcv_op;

        -- sp_supplier_order   : need move rows from xqd_1000_1200 to xqd_1200_2000
        -- sp_supplier_invoice : need move rows from xqd_1200_2000 to xqd_2000_3300
        -- sp_customer_reserve : need move rows from xqd_2100_3300 to xqd_3300_3400

        v_qd_auto_name = 'xqd_' || v_sour_snd_op || '_' || v_sour_rcv_op; -- name of qDistr for delete rows // old: 'autogen_qd'||v_snd_optype_id;
        v_qd_targ_name = 'xqd_' || v_targ_snd_op || '_' || v_targ_rcv_op; -- name of qDistr for insert rows // old: 'autogen_qd'||v_rcv_optype_id;
        v_qs_auto_name = 'xqs_' || v_sour_snd_op || '_' || v_sour_rcv_op; -- name of qStorno for add rows which were deleted from qDistr 'autogen_qs'||v_snd_optype_id;

        v_qd_name_4del = 'xqd_' || v_sour_snd_op || '_' || v_sour_rcv_op; -- // old: 'autogen_qd'||v_snd_optype_id;
        v_qd_name_4ins = 'xqd_' || v_targ_snd_op || '_' || v_targ_rcv_op; -- // old: 'autogen_qd'||v_rcv_optype_id;
        v_qs_name_4ins = 'xqs_' || v_sour_snd_op || '_' || v_sour_rcv_op; -- // 'autogen_qs'||v_snd_optype_id;

        v_proc_body='';

        -- ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
        -- Generate procedures with name = 'X_MAKE_QSTORNO_NNNN_MMMM'
        -- They will be called from SP_SUPPLIER_ORDER, SP_SUPPLIER_INVOICE, SP_CUSTOMER_RESERVE

        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
        for
            select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) -- get header of 'SP_MAKE_QTY_STORNO'
            where src is not null
            into v_line_repl
        do begin
            --v_src = trim(trailing from v_src);
            v_line_repl = replace( v_line_repl collate unicode_ci , :sp_repl_name, v_sp_auto_name ); 
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_line_repl || v_lf;
        end
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### GENERATED AUTO, BASED ON '||sp_repl_name||'. DO NOT EDIT ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### References to "v_qdistr_source_1" were replaced with "'||v_qd_name_4del||'" ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_3" varchar(255) = ''### References to "v_qdistr_target_1" were replaced with "'||v_qd_name_4ins||'" ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_4" varchar(255) = ''### References to "v_qstorned_target_1" were replaced with "'||v_qs_name_4ins||'" ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        suspend;


        select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
        from rdb$procedures p
        where p.rdb$procedure_name = upper(:sp_repl_name) -- 'SP_MAKE_QTY_STORNO'
        into v_proc_body;
 
        v_body_repl = '';

        for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
        do begin
            v_line_repl = v_body_line;
            if ( trim(lower(v_line_repl)) starting with 'declare'
                 and v_line_repl containing 'v_this'
                 and v_line_repl containing sp_repl_name ) then
               v_line_repl = replace( v_line_repl collate unicode_ci , sp_repl_name, lower(v_sp_auto_name) );

            v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_source_1', v_qd_name_4del );
            v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_source_2', 'xqd_1000_3300'); -- 'autogen_qd1000' );
            v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qdistr_target_1', v_qd_name_4ins );

            v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorned_target_1', v_qs_name_4ins ); 
            v_line_repl = replace( v_line_repl collate unicode_ci , 'v_qstorned_target_2', 'xqs_1000_3300'); -- 'autogen_qs1000' );

            -- //// "--TMP$SQL$CODE" = v_line_repl;
            if ( char_length(v_body_repl) + char_length(v_line_repl) + 2 < 32000 ) then
                begin
                  v_body_repl = v_body_repl || v_line_repl || v_lf;
                end
            else
                begin
                    "--TMP$SQL$CODE" = v_body_repl;
                    suspend;
                    v_body_repl = v_line_repl || v_lf ;
                end

            -- ///suspend;
        end
        "--TMP$SQL$CODE" = v_body_repl; 
        suspend;


        "--TMP$SQL$CODE" = v_lf || '^' || v_lf || 'set term ;^';
        suspend;


        -- ||||||||||||||||||||||||||||||||||||||||||||

        -- Replace source of SP_SUPPLIER_ORDER, SP_SUPPLIER_INVOICE, SP_CUSTOMER_RESERVE:
        -- inject call to 'X_MAKE_QSTORNO_NNNN_MMMM' instead of 'sp_make_qty_storno'

        -- sp_supplier_order   : need move rows from xqd_1000_1200 to xqd_1200_2000
        -- sp_supplier_invoice : need move rows from xqd_1200_2000 to xqd_2000_3300
        -- sp_customer_reserve : need move rows from xqd_2100_3300 to xqd_3300_3400

        sp_init_name='';
        if ( v_sour_snd_op = 1000 and v_sour_rcv_op = 1200 ) then sp_init_name='SP_SUPPLIER_ORDER';
        else if ( v_sour_snd_op = 1200 and v_sour_rcv_op = 2000 ) then sp_init_name='SP_SUPPLIER_INVOICE';
        else if ( v_sour_snd_op = 2100 and v_sour_rcv_op = 3300  ) then sp_init_name='SP_CUSTOMER_RESERVE';
        else
            exception; -- !!!
       

        v_proc_body='';

        select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
        from rdb$procedures p
        where p.rdb$procedure_name = upper(:sp_init_name)
        into v_proc_body;

        v_proc_body = replace(replace(v_proc_body, lower(sp_repl_name), lower(v_sp_auto_name) ), upper(sp_repl_name), upper(v_sp_auto_name) );

        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;

        for
            select src from SYS_GET_PROC_DDL(:sp_init_name,-1,0) where src is not null into v_src
        do begin
            v_src = trim(trailing from v_src);
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_src || v_lf;
        end

        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME" varchar(255) = ''### AUTO REPLACED CALLS OF "'||sp_repl_name||'" WITH "'||v_sp_auto_name||'". DO NOT EDIT ###'';' || v_lf || v_lf;

        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_proc_body;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';

        suspend;


        -- ||||||||||||||||||||||||||||||||||||||||||||

        -- Replacing VIEWS that use QDistr when procedures SP_SUPPLIER_ORDER, SP_SUPPLIER_INVOICE, SP_CUSTOMER_RESERVE work:
        v_old_name = 'qdistr';

            i = 1;
            k = iif(v_sour_rcv_op <> 3300, 3, 6);
            while ( i <= k ) do
            begin
              if (v_sour_rcv_op = 1200) then -- for SP_SUPPLIER_ORDER
                  begin
                      vew_for_inject = decode(i, 1, 'v_min_id_clo_ord', 2, 'v_max_id_clo_ord', 'v_random_find_clo_ord');
                      v_qd_auto_name = 'xqd_1000_1200'; -- // old: 'autogen_qd1000';
                  end
              else if (v_sour_rcv_op = 2000) then -- for SP_SUPPLIER_INVOICE
                  begin
                      vew_for_inject = decode(i, 1, 'v_min_id_ord_sup', 2, 'v_max_id_ord_sup', 'v_random_find_ord_sup');
                      v_qd_auto_name = 'xqd_1200_2000'; -- // old:  'autogen_qd1200';
                  end
              else if (v_sour_rcv_op = 3300) then -- for SP_CUSTOMER_RESERVE
                  begin
                      if (i <= 3) then
                          begin
                              vew_for_inject = decode(i,   1, 'v_min_id_avl_res', 2, 'v_max_id_avl_res', 'v_random_find_avl_res');
                              v_qd_auto_name = 'xqd_2100_3300'; -- // old:  'autogen_qd2100'; -- '2100', not '2000'! see output of cursor on rules_for_qdistr
                          end
                      else
                          begin
                              --vew_for_inject = decode(i-3, 1, 'v_min_id_clo_res', 2, 'v_max_id_clo_res', 'v_random_find_clo_res');
                              vew_for_inject = decode(i,   4, 'v_min_id_clo_res', 5, 'v_max_id_clo_res', 'v_random_find_clo_res');
                              v_qd_auto_name = 'xqd_1000_3300'; -- // old: 'autogen_qd1000'; -- must be same view as used for clo_ord
                          end

                  end


              v_body_repl = '';

              v_add_comment=0;
              for
                  select src from sys_get_view_ddl(:vew_for_inject, 1) into v_src
              do begin
                  --v_src = trim(trailing from v_src);
                  v_line_repl = v_src;

                  if ( (trim(v_line_repl) starting with '--' or trim(v_src)=' ') and v_add_comment = 0) then
                      begin
                        v_line_repl = v_lf
                                || '-- !ACHTUNG_README! ### AUTO REPLACED OLD DATA SOURCE "'||upper(v_old_name)||'" WITH "'||upper(v_qd_auto_name)||'". DO NOT EDIT.'
                                || v_lf || v_lf
                                || v_line_repl;
                        v_add_comment = 1;
                      end
                  else
                     v_line_repl = replace( v_line_repl collate unicode_ci , v_old_name, v_qd_auto_name ); 

                  v_body_repl = v_body_repl || v_line_repl || v_lf;

                  --"--TMP$SQL$CODE" = v_line_repl; -- output arg.
                  -- suspend;
              end

              "--TMP$SQL$CODE" = v_body_repl;
              suspend;

              i = i + 1;
            end



    end -- cursor on rules_for_qdistr


    -- ||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||
    -- Replace source of SP_FILL_SHOPPING_CART_CLO_RES and SP_GET_CLO_FOR_INVOICE:
    -- inject 'xqd_1000_3300' instead of 'v_qdistr_source'
    -- (for resultset of items from CLO that still waiting for RESERVE):
    i = 1;
    while (i <= 2) do
    begin

        sp_repl_name = iif( i = 1, 'SP_FILL_SHOPPING_CART_CLO_RES', 'SP_GET_CLO_FOR_INVOICE');
        v_qd_auto_name = 'xqd_1000_3300'; -- // old: 'autogen_qd1000'; -- name which will replace 'v_qdistr_source'
        v_proc_body='';
    
        select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
        from rdb$procedures p
        where p.rdb$procedure_name = upper(:sp_repl_name)
        into v_proc_body;
    
        v_body_repl = '';
    
        for select p.item
                from sys_list_to_rows(:v_proc_body, :v_lf) p
                into v_body_line
        do begin
          v_line_repl = replace( v_body_line collate unicode_ci , 'v_qdistr_source', v_qd_auto_name );
          v_body_repl = v_body_repl || v_line_repl || v_lf;
        end
    
        "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
        for
            select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) where src is not null into v_src
        do begin
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_src || v_lf; -- add empty line after last SP header line
        end
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### DO NOT EDIT ###'';' || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### References to "v_qdistr_source" were replaced with "'||v_qd_auto_name||'" ###'';' || v_lf || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_body_repl;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';
    
        suspend;
        i = i + 1;
    end


    -- ||||||||||||||||||||||||||||||||||||||||||||

    -- Replace in source of SRV_RECALC_IDX_STAT 'QDISTR' and 'QSTORNO' with new names (autogen_qdNNNN and autogen_qsNNNN).

    sp_repl_name = 'SRV_RECALC_IDX_STAT';

    v_proc_body='';

    select replace(replace(p.rdb$procedure_source, ascii_char(13) || :v_lf, :v_lf), ascii_char(13), '')
    from rdb$procedures p
    where p.rdb$procedure_name = upper(:sp_repl_name)
    into v_proc_body;

    v_body_repl = '';

    v_qd_names = '';
    v_qs_names = '';
    for
        select '' || q.snd_optype_id || '_' || q.rcv_optype_id
        from rules_for_qdistr q
        where q.snd_optype_id is not null
        into v_qd_auto_name
    do begin
      v_qd_names = v_qd_names || ',''xqd_' || v_qd_auto_name || '''';
      v_qs_names = v_qs_names || ',''xqs_' || v_qd_auto_name || '''';
    end
    v_qd_names = upper( substring( v_qd_names from 2 ) );
    v_qs_names = upper( substring( v_qs_names from 2 ) );

    for select p.item
            from sys_list_to_rows(:v_proc_body, :v_lf) p
            into v_body_line
    do begin
      v_line_repl = v_body_line;
      v_line_repl = replace( v_line_repl collate unicode_ci , '''qdistr''', v_qd_names);
      v_line_repl = replace( v_line_repl collate unicode_ci , '''qstorned''', v_qs_names);
      --v_line_repl = replace( v_line_repl collate unicode_ci , '''qdistr''', upper('''autogen_qd1000'',''autogen_qd1100'',''autogen_qd1200'',''autogen_qd2000'',''autogen_qd2100'',''autogen_qd3300'',''autogen_qd3400''') );
      --v_line_repl = replace( v_line_repl collate unicode_ci , '''qstorned''', upper('''autogen_qs1000'',''autogen_qs1100'',''autogen_qs1200'',''autogen_qs2000'',''autogen_qs2100'',''autogen_qs3300'',''autogen_qs3400''') );
      v_body_repl = v_body_repl || v_line_repl || v_lf;
    end

    "--TMP$SQL$CODE" = 'set term ^;' || v_lf;
    for
        select src from SYS_GET_PROC_DDL(:sp_repl_name,-1,0) where src is not null into v_src
    do begin
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_src || v_lf; -- add empty line after last SP header line
    end
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_1" varchar(255) = ''### DO NOT EDIT ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'declare "-- ACHTUNG_READ_ME_2" varchar(255) = ''### References to "QDISTR" and "QSTORNED" were replaced with list of auto generated tables XQD_* and XQS_* ###'';' || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_body_repl;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf;
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || '^';
    "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'set term ;^';

    suspend;

    -- |||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||||

    -- Redefinition of views that was initially created with query only to QDistr table (when config 'create_with_split_heavy_tabs=0').
    -- This view is used in SP srv_find_qd_qs_mism as source to data that waiting for distribution (e.g. QDistr):

    k = 1;
    while (k <= 2) do
    begin
        "--TMP$SQL$CODE" = 'alter view '|| iif(k=1, 'v_qdistr_source', 'v_qstorned_source') ||' as '||v_lf
              || '-- DDL was replaced by oltp_split_heavy_tabs_1.sql due to config "create_with_split_heavy_tabs = 1":'
              || v_lf;
        i = 0;
        for
            select '' || q.snd_optype_id || '_' || q.rcv_optype_id
            from rules_for_qdistr q
            where q.snd_optype_id is not null
            into v_qd_auto_name
        do begin
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || iif(i = 0, '', v_lf||'UNION ALL'||v_lf);
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || 'select '''||iif(k=1,'xqd_', 'xqs_') || v_qd_auto_name ||''' as src, q.* from '
                      || iif(k=1, 'xqd_', 'xqs_') || v_qd_auto_name ||' q';
            i = i + 1;
        end
        "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || ';';
        suspend;
        k = k + 1;
    end

   
    "--TMP$SQL$CODE" = '
    create or alter view z_autogen_qd_qs as
    -- DDL was replaced by oltp_split_heavy_tabs_1.sql due to config "create_with_split_heavy_tabs = 1":
    -- 4debug: analysis of dumped dirty data (filled by SP zdump4dbg in some critical errors)
    select
        cast(q.src as varchar(14)) as src,
        q.id,
        q.ware_id,
        q.snd_optype_id,
        cast(so.mcode as varchar(3)) snd_op,
        q.doc_id as snd_doc_id,
        sh.agent_id as snd_agent,
        q.snd_id,
        q.snd_qty,
        q.snd_purchase,
        q.snd_retail,
        q.rcv_optype_id,
        cast(ro.mcode as varchar(3)) rcv_op,
        d.doc_id as rcv_doc_id,
        rh.agent_id as rcv_agent,
        q.rcv_id,
        q.rcv_qty,
        q.rcv_purchase,
        q.rcv_retail,
        q.trn_id,
        q.dts
    from (
      select * from v_qdistr_source
      union all
      select * from v_qstorned_source
    ) q
    left join doc_data d on q.rcv_id = d.id
    left join optypes so on q.snd_optype_id = so.id
    left join doc_list sh on q.doc_id=sh.id
    left join optypes ro on q.rcv_optype_id = ro.id
    left join doc_list rh on d.doc_id=rh.id
    order by q.src, q.doc_id, q.id;
    ';
    suspend;


    ----------------------------------------------------------------------------------

    -- DISABLED 11.01.2019! REPLACED WITH MORE APPROPRIATE CODE, SEE BELOW:
    ----- 13.11.2015: query to this view can be significantly faster if it is replaced 
    ----- with just single select to xqd_1000_3300 which has index on doc_id:
    --"--TMP$SQL$CODE" =  'alter view v_min_id_clo_res as' || v_lf
    --    || '-- ### DO NOT EDIT! ### DDL was replaced by oltp_split_heavy_tabs_1.sql due to config "create_with_split_heavy_tabs = 1"' || v_lf
    --    || 'select doc_id as id' || v_lf
    --    || 'from xqd_1000_3300' || v_lf
    --    || 'order by doc_id' || v_lf
    --    || 'rows 1;' || v_lf
    --;
    --
    --suspend;
    --
    --"--TMP$SQL$CODE" =  'alter view v_random_find_clo_res as' || v_lf
    --    || '-- ### DO NOT EDIT! ### DDL was replaced by oltp_split_heavy_tabs_1.sql due to config "create_with_split_heavy_tabs = 1"' || v_lf
    --    || 'select h.id' || v_lf
    --    || 'from doc_list h' || v_lf
    --    || 'where h.optype_id = 1000' || v_lf
    --    || 'and exists(' || v_lf
    --    || '    select * from xqd_1000_3300 q' || v_lf
    --    || '    where q.doc_id = h.id' || v_lf
    --    || ');' || v_lf
    --;
    --suspend;
    --
    --"--TMP$SQL$CODE" = 'commit;';
    --suspend;


    v_body_line = v_lf
                || '-- ### DO NOT EDIT! ### DDL was replaced by oltp_split_heavy_tabs_1.sql due to config parameter "create_with_split_heavy_tabs = 1"' || v_lf
                || '-- ### Config parameter ''separate_workers'' = 1 --> use search in xqd_1000_3000 using @1 index with key: (@2).' || v_lf
                || '-- ### Expected plan must contain: Q ORDER/INDEX <name_of_@1_index> // 11.01.2019' || v_lf
    ;
    if ( v_separate_workers = 1 ) then
        begin

            -------------------------------- v _ m i n _ i d  _ c l o _ r e s ------------------------------
            "--TMP$SQL$CODE" =  v_lf
                || 'alter view v_min_id_clo_res as' || v_lf
                || replace(replace( v_body_line, '@1', 'COMPOUND_ASCENDING' ), '@2', 'worker_id, doc_id')
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || 'select doc_id as id' || v_lf
                || 'from xqd_1000_3300 q' || v_lf
                || 'where -- column q.worker_id is compared with result of rdb$get_context():' || v_lf
                || '    q.worker_id is not distinct from '
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE"
                || iif( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.', 
                        '(select result from fn_this_worker_seq_no)', 
                        'fn_this_worker_seq_no()' 
                      ) || v_lf
                || '-- NB: column "worker_id" must present in "ORDER_BY" clause only for FB 2.5' || v_lf
                || '-- Otherwise plan will be: SORT ((Q INDEX (...)))' || v_lf
                || 'order by q.worker_id, q.doc_id' || v_lf
                || 'rows 1;' || v_lf
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'commit;'
            ;
            suspend;


            -------------------------------- v _ m a x _ i d  _ c l o _ r e s ------------------------------
            "--TMP$SQL$CODE" =  v_lf
                || 'alter view v_max_id_clo_res as' || v_lf
                || replace(replace( v_body_line, '@1', 'COMPOUND_DESCENDING' ), '@2', 'worker_id, doc_id')
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || 'select doc_id as id' || v_lf
                || 'from xqd_1000_3300 q' || v_lf
                || 'where -- column q.worker_id is compared with result of rdb$get_context():' || v_lf
                || '    q.worker_id is not distinct from '
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE"
                || iif( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.', 
                        '(select result from fn_this_worker_seq_no)', 
                        'fn_this_worker_seq_no()' 
                      )
            ;

            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || '-- NB: column "worker_id" must present in ''ORDER_BY'' clause only for FB 2.5' || v_lf
                || '-- Otherwise plan will be: SORT Q INDEX <ascending_index>' || v_lf
                || '-- i.e. desc index will be ignored.' || v_lf
                || '-- In FB 3.0 it is enough to specify only ''ORDER BY q.doc_id DESC'' here.'
            ;


            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || 'order by q.worker_id DESC, q.doc_id DESC' || v_lf
                || 'rows 1;' || v_lf
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'commit;'
            ;
            suspend;        


            -------------------------------- v _ r a n d o m  _ f i n d _ c l o _ r e s ------------------------------
            "--TMP$SQL$CODE" =  'alter view v_random_find_clo_res as' || v_lf
                || replace(replace( v_body_line, '@1', 'COMPOUND' ), '@2', 'doc_id')
            ;

            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || 'select h.id' || v_lf
                || 'from doc_list h' || v_lf
                || 'where ' || v_lf
                || '    h.optype_id = 1000' || v_lf
                || '    and h.worker_id is not distinct from '
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE"
                || iif( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.', 
                        '(select result from fn_this_worker_seq_no)', 
                        'fn_this_worker_seq_no()' 
                      )
            ;

            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || '    and exists(' || v_lf
                || '        select * from xqd_1000_3300 q' || v_lf
                || '        where -- column q.worker_id is compared with result of rdb$get_context():' || v_lf
                || '            q.worker_id is not distinct from '
            ;

            "--TMP$SQL$CODE" = "--TMP$SQL$CODE"
                || iif( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.', 
                        '(select result from fn_this_worker_seq_no)', 
                        'fn_this_worker_seq_no()' 
                      ) || v_lf
                || '            and q.doc_id = h.id' || v_lf
                || '    );' || v_lf
            ;
            suspend;

            "--TMP$SQL$CODE" = 'commit;';
            suspend;


        end
    else --    ______________________________  s e p a r a t e _ w o r k e r s = 0 _________________________
        begin
            -------------------------------- v _ m i n _ i d  _ c l o _ r e s ------------------------------
            "--TMP$SQL$CODE" =  v_lf
                || 'alter view v_min_id_clo_res as' || v_lf
                || replace(replace( v_body_line, '@1', 'SINGLE_COLUMN_ASCENDING' ), '@2', 'doc_id')
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || 'select doc_id as id' || v_lf
                || 'from xqd_1000_3300 q' || v_lf
                || 'order by doc_id' || v_lf
                || 'rows 1;' || v_lf
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'commit;'
            ;
            suspend;


            -------------------------------- v _ m a x _ i d  _ c l o _ r e s ------------------------------
            "--TMP$SQL$CODE" =  v_lf
                || 'alter view v_max_id_clo_res as' || v_lf
                || replace(replace( v_body_line, '@1', 'SINGLE_COLUMN_DESCENDING' ), '@2', 'doc_id')
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf
                || 'select doc_id as id' || v_lf
                || 'from xqd_1000_3300 q' || v_lf
                || 'order by doc_id DESC' || v_lf
                || 'rows 1;' || v_lf
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'commit;'
            ;
            suspend;


            -------------------------------- v _ r a n d o m  _ f i n d _ c l o _ r e s ------------------------------
            "--TMP$SQL$CODE" =  'alter view v_random_find_clo_res as' || v_lf
                || replace(replace( v_body_line, '@1', 'SINGLE_COLUMN' ), '@2', 'doc_id')
                || 'select h.id' || v_lf
                || 'from doc_list h' || v_lf
                || 'where ' || v_lf
                || '    h.optype_id = 1000' || v_lf
                || 'and exists(' || v_lf
                || '    select * from xqd_1000_3300 q' || v_lf
                || '    where q.doc_id = h.id' || v_lf
                || ');' || v_lf
            ;
            "--TMP$SQL$CODE" = "--TMP$SQL$CODE" || v_lf || 'commit;'
            ;
            suspend;


        end

--and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)

    ----------------------------------------------------------------------------------


  
    "--TMP$SQL$CODE" = 'set term ^;' || v_lf
          || 'alter procedure SP_KILL_QSTORNO_RET_QS2QD as' || v_lf
          || 'begin' || v_lf
          || '    -- Source code has been removed by script "oltp_split_heavy_tabs_1.sql".' || v_lf
          || '    -- See procedures:' || v_lf
          || '    -- sp_ret_qs2qd_on_canc_wroff,' || v_lf
          || '    -- sp_ret_qs2qd_on_canc_reserve,' || v_lf
          || '    -- sp_ret_qs2qd_on_canc_res_aux,'  || v_lf
          || '    -- sp_ret_qs2qd_on_canc_invoice,' || v_lf
          || '    -- sp_ret_qs2qd_on_canc_supp_order.' || v_lf
          || 'end ^' || v_lf
          || 'alter procedure SP_LOCK_DEPENDENT_DOCS as' || v_lf
          || 'begin' || v_lf
          || '    -- Source code has been removed by script "oltp_split_heavy_tabs_1.sql".' || v_lf
          || '    -- See procedures:' || v_lf
          || '    -- X_LOCK_DEPDOCS_ON_CANC_SUP_ORD,' || v_lf
          || '    -- X_LOCK_DEPDOCS_ON_CANC_INVOICE.' || v_lf
          || 'end ^' || v_lf
          || 'alter procedure SP_MAKE_QTY_STORNO as' || v_lf
          || 'begin' || v_lf
          || '    -- Source code has been removed by script "oltp_split_heavy_tabs_1.sql".' || v_lf
          || '    -- See procedures with name matching X_MAKE_QSTORNO_*.' || v_lf
          || 'end ^' || v_lf
          || 'set term ;^';
          --|| 'create or alter procedure ZDUMP4DBG as' || v_lf
          --|| 'begin' || v_lf
          --|| '    -- Source code has been removed by script "oltp_split_heavy_tabs_1.sql".' || v_lf
          --|| '    -- (not implemented for case when config par. "create_with_split_heavy_tabs = 1").' || v_lf
          --|| 'end ^' || v_lf
          --|| 'set term ;^';
    suspend;

    "--TMP$SQL$CODE" = 'commit;';
    suspend;

    -- |||||||||||||||||||||||
    -- Removing views that are NOT used anymore. Finally - removal of tables QDistr and QStorned.

    "--TMP$SQL$CODE" = 'create or alter view z_qdqs as select 1 id from rdb$database; drop view z_qdqs;';
    suspend;

    "--TMP$SQL$CODE" = 'create or alter view v_qdistr_source_1 as select 1 id from rdb$database; drop view v_qdistr_source_1;';
    suspend;
    "--TMP$SQL$CODE" = 'create or alter view v_qdistr_source_2 as select 1 id from rdb$database; drop view v_qdistr_source_2;';
    suspend;


    "--TMP$SQL$CODE" = 'create or alter view v_qdistr_target_1 as select 1 id from rdb$database; drop view v_qdistr_target_1;';
    suspend;
    "--TMP$SQL$CODE" = 'create or alter view v_qdistr_target_2 as select 1 id from rdb$database; drop view v_qdistr_target_2;';
    suspend;

    "--TMP$SQL$CODE" = 'create or alter view v_qdistr_name_for_del as select 1 id from rdb$database; drop view v_qdistr_name_for_del;';
    suspend;
    "--TMP$SQL$CODE" = 'create or alter view v_qdistr_name_for_ins as select 1 id from rdb$database; drop view v_qdistr_name_for_ins;';
    suspend;



    "--TMP$SQL$CODE" = 'create or alter view v_qstorned_target_1 as select 1 id from rdb$database; drop view v_qstorned_target_1;';
    suspend;
    "--TMP$SQL$CODE" = 'create or alter view v_qstorned_target_2 as select 1 id from rdb$database; drop view v_qstorned_target_2;';
    suspend;

    "--TMP$SQL$CODE" = 'create or alter view v_qstorno_name_for_del as select 1 id from rdb$database; drop view v_qstorno_name_for_del;';
    suspend;
    "--TMP$SQL$CODE" = 'create or alter view v_qstorno_name_for_ins as select 1 id from rdb$database; drop view v_qstorno_name_for_ins;';
    suspend;

    "--TMP$SQL$CODE" = 'drop table qdistr;';
    suspend;

    "--TMP$SQL$CODE" = 'drop table qstorned;';
    suspend;


    "--TMP$SQL$CODE" = 'commit;';
    suspend;

    "--TMP$SQL$CODE" = 'drop procedure tmp_init_autogen_qdistr_tables;' || v_lf ||
          'drop procedure tmp_init_autogen_qstorn_tables;' || v_lf ||
          'commit;' ;
    suspend;

end
^
set term ;^
commit;

-- #####################################################################################################################

set heading off;
set list on;

select 'set echo off;' as "--TMP$SQL$CODE"
from rdb$database
union all
select 'select ''oltp_split_heavy_tabs_1.sql finish at '' || current_timestamp as msg from rdb$database;' as "--TMP$SQL$CODE"
from rdb$database
;
commit;

-- ##########################################################
-- End of script oltp_split_heavy_tabs_1.sql; next to be run:
-- oltp_replication_DDL.sql (common for both FB 2.5 and 3.0)
-- ##########################################################

