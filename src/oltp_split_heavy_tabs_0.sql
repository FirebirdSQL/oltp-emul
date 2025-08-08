-- ########################################
-- Begin of script oltp_split_heavy_tabs_0.sql 
-- ########################################

-- ::: NB ::: This script is COMMON for both FB 2.5 and 3.0 and should be called 
-- after oltp_main_filling.sql and oltp_misc_debug.sql 

-- Sample for run: isql /3333:oltp30 -i oltp_split_heavy_tabs_0.sql | sed "s/[ \t]*$//" 1>log.tmp

set echo off;


set heading off;
set list on;

select 'select ''oltp_split_heavy_tabs_0.sql start at '' || current_timestamp as msg from rdb$database;' as "--TMP$SQL$CODE"
from rdb$database
union all
select 'set echo off;'
from rdb$database
;
commit;


recreate global temporary table tmp$source(
    obj_depends_name varchar(31), 
    obj_depends_type smallint,
    constraint tmp$source_obj_name_unq unique(obj_depends_name)
) 
on commit delete rows;

recreate global temporary table tmp$vew_to_tabs(
    vew_for_removal varchar(31), 
    tab_for_restore varchar(31)
) 
on commit delete rows;

commit;

set transaction no wait;
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
    declare v_add_inlined_note smallint;
    declare v_add_node varchar(255);
    declare i int;
    declare k smallint;

    declare v_snd_optype_id dm_ids;
    declare v_rcv_optype_id dm_ids;
    declare v_storno_sub smallint;


    declare v_name_fin varchar(31);
    declare v_name_min varchar(31);
    declare v_name_max varchar(31);
    declare v_line_type varchar(12);
    --declare v_add_comment smallint = 0;

    declare v_who_depends_name varchar(31);
    declare v_who_depends_type smallint;
    declare v_views_to_be_replaced varchar(512);
    declare v_tabs_for_replace_with varchar(512);

    declare tab_for_inject varchar(31);

    declare c_proc_src cursor for (
      select src from sys_get_proc_ddl( :v_who_depends_name, 1, 1) 
    );

    declare c_view_src cursor for (
      select src from sys_get_view_ddl( :v_who_depends_name, 1) 
    );

    declare v_make_separate_qd_idx smallint; -- 1 or 0
    declare v_build_with_qd_compound_ordr varchar(31); -- 'most_selective_first' or 'least_selective_first'
    declare v_separate_workers smallint; -- 12.08.2018

    declare v_qdistr_idx_old_name varchar(31);

    declare v_idx_expr1 varchar(1024);
    declare v_idx_expr2 varchar(1024);
    declare v_idx_suff1 varchar(31);
    declare v_idx_suff2 varchar(31);
    declare v_ddl_qdidx1 varchar(1024);
    declare v_ddl_qdidx2 varchar(1024);

    declare v_qd_table varchar(31);
    declare v_qd_suffix varchar(31);

begin
    v_lf = ascii_char(10);


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

    -- This row is created in 1run_oltp_emul.bat, in sub-routine "make_db_objects":
    -- Value is defined by config parameter 'separate_workers' = 1 or 0.
    select s.svalue 
    from settings s 
    where s.working_mode='COMMON' and s.mcode='SEPARATE_WORKERS'
    into v_separate_workers;


    -- DROP all indices for table QDistr except those which are involved to constraints job:
    for 
        select ri.rdb$index_name
        from rdb$indices ri
        left join rdb$relation_constraints rc using(rdb$index_name, rdb$relation_name)
        where
            ri.rdb$relation_name=upper('QDISTR')
            and rc.rdb$constraint_name is null
        into v_qdistr_idx_old_name
    do
        execute statement 'drop index ' || v_qdistr_idx_old_name;


    v_idx_expr1 = '';
    v_idx_expr2 = '';

    -- NB: now we *DO* need to include 'snd_optype_id' and 'rcv_optype_id' fields in index
    -- Because this script is running when config parameter 'create_with_split_heavy_tabs' = '0',
    -- so we have SINGLE table QDistr instead of multiple XQD_* tables.

    if ( v_make_separate_qd_idx = 1 ) then
        -- ###########################################################
        -- ### create TWO INDICES for QDistr: compound and ordinar ###
        -- ###########################################################
        begin
            if ( upper(v_build_with_qd_compound_ordr) = upper('least_selective_first') ) then
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_suff1 = 'sndop_rcvop_ware';
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id)'; 
                        end
                    else
                        begin
                            v_idx_suff1 = 'sop_rop_ware_wkr';
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id, worker_id)'; 
                        end
                    v_idx_suff2 = 'snd';
                    v_idx_expr2 = '(snd_id)';
                end
            else -- 'most_selective_first' (was originally developed in 2014)
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_suff1 = 'ware_sndop_rcvop';
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id)'; 
                        end
                    else
                        begin
                            v_idx_suff1 = 'ware_sop_rop_wkr';
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id, worker_id)'; 
                        end
                    v_idx_suff2 = 'snd';
                    v_idx_expr2 = '(snd_id)';
                end
        end
    else 
        -- ###############################################
        -- ### create SINGLE compound index for QDistr ###
        -- ###############################################
        begin
            if ( upper(v_build_with_qd_compound_ordr) = upper('least_selective_first') ) then
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_suff1 = 'sndop_rcvop_ware_snd';
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id, snd_id)';
                        end
                    else 
                        begin
                            v_idx_suff1 = 'sop_rop_ware_wkr_snd';
                            v_idx_expr1 = '(snd_optype_id, rcv_optype_id, ware_id, worker_id, snd_id)';
                        end
                    v_idx_suff2 = '';
                    v_idx_expr2 = '';
                end
            else -- 'most_selective_first' (was originally developed in 2014)
                begin
                    if ( v_separate_workers = 0 ) then
                        begin
                            v_idx_suff1 = 'ware_sndop_rcvop_snd';
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id, snd_id)';
                        end
                    else 
                        begin
                            v_idx_suff1 = 'ware_sop_rop_wkr_snd';
                            v_idx_expr1 = '(ware_id, snd_optype_id, rcv_optype_id, worker_id, snd_id)';
                        end
                    v_idx_suff2 = '';
                    v_idx_expr2 = '';
                end

            -- Note. 02.10.2015. Order of fields with 'ware_id' at FIRST position:
            -- (ware_id, snd_optype_id, rcv_optype_id,snd_id)
            -- was used originally and appeared much more effective
            -- than this: (snd_optype_id, rcv_optype_id, ware_id, snd_id)
            -- Ratio is about 8000:5300 (performance total indicator, FW=OFF, SS).
        end

    v_qd_table = 'QDISTR';
    v_ddl_qdidx1 = 'create index ' || v_qd_table || '_' || v_idx_suff1 || ' on ' || v_qd_table || v_idx_expr1;
    v_ddl_qdidx2 = 'create index ' || v_qd_table || '_' || v_idx_suff2 || ' on ' || v_qd_table || v_idx_expr2;


    in autonomous transaction do
    begin
        if ( not v_idx_expr1 = '' ) then execute statement v_ddl_qdidx1;
        if ( not v_idx_expr2 = '' ) then execute statement v_ddl_qdidx2;

        --execute statement 'create index qdistr_worker_id on qdistr(worker_id)'; -- 12.08.2018
    end


    v_views_to_be_replaced =
           'V_QDISTR_MULTIPLY_1,'   --  1
        || 'V_QDISTR_MULTIPLY_2,'
        || 'V_QDISTR_NAME_FOR_DEL,'
        || 'V_QDISTR_NAME_FOR_INS,'
        || 'V_QDISTR_SOURCE_1,'     --  5
        || 'V_QDISTR_SOURCE_2,'
        || 'V_QDISTR_TARGET_1,'
        || 'V_QDISTR_TARGET_2,'
        || 'V_QDISTR_SOURCE,'
        || 'V_QSTORNED_SOURCE,'     -- 10
        || 'V_QSTORNED_TARGET_1,'
        || 'V_QSTORNED_TARGET_2,'
        || 'V_QSTORNO_NAME_FOR_DEL,'
        || 'V_QSTORNO_NAME_FOR_INS'
    ;
    v_tabs_for_replace_with =
           'QDISTR,'                --  1
        || 'QDISTR,'
        || 'QDISTR,'
        || 'QDISTR,'
        || 'QDISTR,'                -- 5
        || 'QDISTR,'
        || 'QDISTR,'
        || 'QDISTR,'
        || 'QDISTR,'
        || 'QSTORNED,'              -- 10
        || 'QSTORNED,'
        || 'QSTORNED,'
        || 'QSTORNED,'
        || 'QSTORNED'
    ;


    "--TMP$SQL$CODE" = '-- Need to replace references of:';
    suspend;
    v_views_to_be_replaced = upper( v_views_to_be_replaced );
    v_tabs_for_replace_with = upper( v_tabs_for_replace_with );
    i = 1;
    for 
        select 
            a.item as a_name, b.item as b_name
        from sys_list_to_rows( :v_views_to_be_replaced ) a
        join sys_list_to_rows( :v_tabs_for_replace_with ) b on a.line = b.line
        into vew_for_inject, tab_for_inject
    do begin
        "--TMP$SQL$CODE" = '-- '|| i ||'. View "' || vew_for_inject || '" with table "' || tab_for_inject || '"';
        insert into tmp$vew_to_tabs(vew_for_removal, tab_for_restore) values( :vew_for_inject, :tab_for_inject);
        suspend;
        i = i + 1;
    end

    "--TMP$SQL$CODE" = 'set bail on;' ;
    suspend;


    for 
        select 
            a.item as a_name, b.item as b_name
        from sys_list_to_rows( :v_views_to_be_replaced ) a
        join sys_list_to_rows( :v_tabs_for_replace_with ) b on a.line = b.line
        into vew_for_inject, tab_for_inject
    do begin
        -- this is written to oltp_split_heavy_tabs_0_NN.tmp:
        "--TMP$SQL$CODE" = '-- vew_for_inject:' || vew_for_inject || ', tab_for_inject='|| tab_for_inject ||';';
        suspend;
        for
            select distinct rd.rdb$dependent_name, rd.rdb$dependent_type  -- 1=view; 5=sp; 2=trigger
            from rdb$dependencies rd
            where rd.rdb$depended_on_name = upper(:vew_for_inject)
            into v_who_depends_name, v_who_depends_type
        do begin
            update or insert into tmp$source(obj_depends_name, obj_depends_type)
            values( :v_who_depends_name, :v_who_depends_type)
            matching(obj_depends_name);
            "--TMP$SQL$CODE" = '-- Point before replace code of: ' || v_who_depends_name || ', type: '|| v_who_depends_type  ||', depends on: ' || upper(:vew_for_inject) ||';';
            suspend;
        end
    end

/*
SP_MULTIPLY_ROWS_FOR_QDISTR    
SP_KILL_QSTORNO_RET_QS2QD
SP_QD_HANDLE_ON_CANCEL_CLO
SP_QD_HANDLE_ON_INVOICE_UPD_STS
SP_QD_HANDLE_ON_RESERVE_UPD_STS
SP_FILL_SHOPPING_CART_CLO_RES
SP_GET_CLO_FOR_INVOICE
SRV_DIAG_QTY_DISTR
SRV_FIND_QD_QS_MISM
SRV_TEST_WORK
ZDUMP4DBG
Z_MISM_DD_QD_QS_ORPHANS
Z_MISM_DD_QD_QS_SUMS
SP_MAKE_QTY_STORNO
SP_LOCK_DEPENDENT_DOCS
Z_GET_DEPENDEND_DOCS
*/

    for 
        select obj_depends_name, obj_depends_type
        from tmp$source
        into v_who_depends_name, v_who_depends_type
    do begin
        "--TMP$SQL$CODE" = '-- Restore references to the table "' || tab_for_inject || '" in "' || v_who_depends_name || '"';
        suspend;

        v_body_repl = '';
        v_add_comment = 0;

        if ( v_who_depends_type = 5 ) then 
            open c_proc_src;
            -- temply dis (in 3.0 only, see CORE-4929): else if ( v_who_depends_type = 1 ) then open c_view_src;
        else 
            open c_view_src;

        while ( 1 = 1 ) do
        begin
            if ( v_who_depends_type = 5 ) then -- 1=view; 5=sp; 2=trigger
                fetch c_proc_src into v_line_repl;
                -- temply dis (in 3.0 only, see CORE-4929):  else if ( v_who_depends_type = 1 ) then fetch c_view_src into v_line_repl;
            else 
                fetch c_view_src into v_line_repl;

            if ( row_count = 0 ) then leave;

            v_line_repl = v_line_repl || ' ';

            if (v_who_depends_type = 5 and v_add_comment = 0 and lower(trim(v_line_repl)) starting with 'declare' ) then
            begin
                       v_add_comment = 1;
                       v_line_repl = v_lf
                               || 'declare "-- ACHTUNG_READ_ME_1" VARCHAR(255) = ''### DO NOT EDIT: this source is result of auto post-handling. ### '';' || v_lf
                               || 'declare "-- ACHTUNG_READ_ME_2" VARCHAR(255) = ''### References to TABLES "QDistr", "QStorned" have been restored instead of views.'';' || v_lf || v_lf 
                               || v_line_repl;
            end

            if ( 1 = 0 and v_separate_workers = 0 
                 and 
                 v_line_repl collate unicode_ci 
                 similar to 
                 '%worker_id[[:WHITESPACE:]]+is[[:WHITESPACE:]]+not[[:WHITESPACE:]]+distinct[[:WHITESPACE:]]+from[[:WHITESPACE:]]+fn_this_worker_seq_no%' ) then
                begin
                    v_line_repl = '-- ' || v_line_repl || ' // DISABLED because separate_workers = 0' ;
                end
            else
                begin
                    for 
                        select vew_for_removal, tab_for_restore 
                        from tmp$vew_to_tabs 
                        into vew_for_inject, tab_for_inject
                    do begin
                        v_add_node = '';
                        if ( v_line_repl collate unicode_ci containing vew_for_inject ) then 
                        begin
                            v_add_node = ' -- ### auto post-handling: replace "'||trim(vew_for_inject)||'" with TABLE';
                        end
                        v_line_repl = replace( v_line_repl collate unicode_ci, vew_for_inject, tab_for_inject ) || v_add_node;

                    end
                end
            --if ( v_add_inlined_note = 1 ) then v_line_repl = v_line_repl || ' -- post-handling, auto: restored TABLE name.';


            if ( char_length(v_body_repl) + char_length(v_line_repl) + 2 < 32000 ) then -- 32765 ) then
                begin
                    v_body_repl = v_body_repl || trim(trailing from v_line_repl) || v_lf;
                end
            else
                begin
                    "--TMP$SQL$CODE" = v_body_repl;
                    suspend;
                    v_body_repl = v_line_repl || v_lf;
                end

        end
        "--TMP$SQL$CODE" = v_body_repl; 
        suspend;

        if ( v_who_depends_type = 5 ) then 
            close c_proc_src;
        -- temply dis (in 3.0 only, see CORE-4929): else if ( v_who_depends_type = 1 ) then close c_view_src;
        else close 
            c_view_src;
    end

    "--TMP$SQL$CODE" = 'commit;';
    suspend;

    for select 'drop view ' || trim(vew_for_removal) ||';' from tmp$vew_to_tabs into "--TMP$SQL$CODE" do suspend;

    "--TMP$SQL$CODE" = 'commit;';
    suspend;

end
^
set term ;^
commit;

drop table tmp$source;
drop table tmp$vew_to_tabs;
commit;

-- #####################################################################################################################

set heading off;
set list on;

select 'set echo off;' as "--TMP$SQL$CODE"
from rdb$database
union all
select 'select ''oltp_split_heavy_tabs_0.sql finish at '' || current_timestamp as msg from rdb$database;'
from rdb$database
;
commit;

-- ##########################################################
-- End of script oltp_split_heavy_tabs_0.sql; next to be run: 
-- oltp_common_DDL.sql (common for both FB 2.5 and 3.0)
-- ##########################################################
