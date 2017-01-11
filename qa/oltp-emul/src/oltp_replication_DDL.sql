set echo off;
set count off;
set list on;
select 'oltp_replication_DDL.sql start at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

--set echo on;
set bail on;
create or alter procedure tmp_sp_generate_update_pk_ddl(a_create_pk smallint) as begin end
;
recreate view tmp_v_tabs_without_pk_constr as
select 
    'invnt_turnover_log' as s from rdb$database union all select
    'money_turnover_log' from rdb$database union all select
    'pdistr' from rdb$database union all select
    'pstorned' from rdb$database union all select
    'perf_log' from rdb$database 
;

recreate view tmp_v_tabs_wo_pkid_and_constr as
select 
    'trace_stat' as s from rdb$database union all select
    'perf_estimated' as s from rdb$database union all select
    'zdoc_data' from rdb$database union all select
    'zdoc_list' from rdb$database union all select
    'zinvnt_turnover_log' from rdb$database union all select
    'zpdistr' from rdb$database union all select
    'zpstorned' from rdb$database union all select
    'zqdistr' from rdb$database union all select
    'zqstorned' from rdb$database union all select
    'ztmp_shopping_cart' from rdb$database
;

set term ^;
create or alter procedure tmp_sp_check_for_table_has_pk(a_rel_name varchar(64) character set utf8)
returns(has_pk smallint) as
begin
     select iif(rc.rdb$constraint_type is null, 0, 1)
     from rdb$database r
     left join rdb$relation_constraints rc
         on rc.rdb$constraint_type in( upper('primary key'), upper('unique') )
            and rc.rdb$relation_name = upper( :a_rel_name )
     into has_pk;
     suspend;
end
^
create or alter procedure tmp_sp_generate_update_pk_ddl(a_create_pk smallint)
returns(add_info varchar(255))
as
    declare v_table_to_be_changed varchar(31);
    declare v_pkey_expr varchar(255);
    declare v_trig_expr varchar(255);
    declare v_drop_pkid varchar(255);
    declare v_lf char(1);
    declare v_split_heavy_tabs smallint;
    declare c_split_1 cursor for (
        select iif(c.i=1, 'xqd_', 'xqs_') || q.snd_optype_id || '_' || q.rcv_optype_id as s
        from rules_for_qdistr q
        cross join (select 1 as i from rdb$database union all select 2 from rdb$database) c
        where q.snd_optype_id is not null --------------------------- '1000_1200'; '1200_2000' etc
        UNION ALL
        select s from tmp_v_tabs_without_pk_constr
    );
    declare c_split_0 cursor for (
        select 'qdistr' as s from rdb$database union all select 'qstorned' from rdb$database
        UNION ALL
        select s from tmp_v_tabs_without_pk_constr
    );
begin
    select t.svalue
    from settings t
    where t.working_mode='COMMON' and t.mcode='BUILD_WITH_SPLIT_HEAVY_TABS'
    into v_split_heavy_tabs;
    if ( v_split_heavy_tabs is null ) then
        exception ex_record_not_found;
    
    if ( v_split_heavy_tabs =  1 ) then
        open c_split_1;
    else
        open c_split_0;

    while (1=1) do
    begin
        --fetch c_shop_cart into ware_id, qty, purchase, retail;
        --if ( row_count = 0 ) then leave;

        if ( v_split_heavy_tabs =  1 ) then 
            fetch c_split_1 into v_table_to_be_changed;
        else 
            fetch c_split_0 into v_table_to_be_changed;

        if (row_count = 0) then leave;

        v_table_to_be_changed = trim(v_table_to_be_changed);
        if (a_create_pk = 1) then
            if ( (select has_pk from tmp_sp_check_for_table_has_pk(:v_table_to_be_changed)) = 0 ) then
                v_pkey_expr = 
                   'alter table ' 
                   || v_table_to_be_changed
                   || ' add constraint ' || v_table_to_be_changed || '_pk primary key(id)'
                   || ' using index ' || v_table_to_be_changed || '_pk'
                   ;
            else
                v_pkey_expr = '-- table '''||v_table_to_be_changed||' already has PK, skip add constraint.';
        else -- a_create_pk = 0 --> DROP PK (if exists)
            if ( (select has_pk from tmp_sp_check_for_table_has_pk(:v_table_to_be_changed)) = 1 ) then
                v_pkey_expr = 
                   'alter table ' 
                   || v_table_to_be_changed
                   || ' drop constraint ' || v_table_to_be_changed || '_pk';
            else
                v_pkey_expr = '-- table '''||v_table_to_be_changed||''' has no PK, skip drop constraint.';

        add_info = v_pkey_expr;
        suspend;
  
        if ( v_pkey_expr not starting with '--' ) then
            in autonomous transaction do
                execute statement v_pkey_expr;

    end
    if ( v_split_heavy_tabs =  1 ) then
        close c_split_1;
    else
        close c_split_0;

    if ( v_pkey_expr is null ) then
       -- This script should be called ***AFTER*** oltp_main_filling.sql which does fill table 'optypes'.
       -- Probably this table currently is empty!
       exception ex_record_not_found;
       --'required record not found, datasource: @1, key: @2';


    v_lf = ascii_char(10);
    for 
        select s from tmp_v_tabs_wo_pkid_and_constr
        into v_table_to_be_changed
    do begin
        v_table_to_be_changed = trim(v_table_to_be_changed);
        v_drop_pkid = null;
        if (a_create_pk = 1) then
            begin
                if ( (select has_pk from tmp_sp_check_for_table_has_pk(:v_table_to_be_changed)) = 0 ) then
                    begin
                        in autonomous transaction do
                            execute statement 'delete from '||v_table_to_be_changed;

                        v_pkey_expr = 
                            'alter table '
                            || v_table_to_be_changed
                            || ' add pkid dm_idb not null'
                            || ',add constraint ' || v_table_to_be_changed || '_pk primary key(pkid)'
                            || ' using index ' || v_table_to_be_changed || '_pk';
                    end
                else
                    v_pkey_expr = '-- table '''||v_table_to_be_changed||''' already has PK, skip add constraint.';

                v_trig_expr =
                    'create or alter trigger ' || v_table_to_be_changed || '_0i '
                    || v_lf || 'for ' ||v_table_to_be_changed || ' active before insert position 0 as '
                    || v_lf || 'begin'
                    || v_lf || '    -- do NOT edit, generated auto!'
                    || v_lf || '    new.pkid =  coalesce( new.pkid, gen_id(g_common, 1) );'
                    || v_lf || 'end';
            end
        else
            begin
                if ( exists(select * from rdb$triggers where rdb$trigger_name = upper(:v_table_to_be_changed||'_0i') ) ) then
                    v_trig_expr = 'drop trigger ' || v_table_to_be_changed || '_0i';
                else
                    v_trig_expr = '-- table '''||v_table_to_be_changed||''' has no PK-trigger, skip drop trigger.';

                if ( (select has_pk from tmp_sp_check_for_table_has_pk(:v_table_to_be_changed)) = 1 ) then
                    begin
                        v_pkey_expr = 
                           'alter table ' 
                           || v_table_to_be_changed
                           || ' drop constraint ' || v_table_to_be_changed || '_pk'
                           -- commented until CORE-5446 not fixed: || ',drop pkid'
                           ;
                        v_drop_pkid = 
                           'alter table ' 
                           || v_table_to_be_changed
                           || ' drop pkid'
                           ;
                    end
                else
                    v_pkey_expr = '-- table '''||v_table_to_be_changed||''' has no PK, skip drop constraint.';

            end


        if (a_create_pk = 1) then
            begin
                add_info = v_pkey_expr;
                suspend;
                if ( v_pkey_expr not starting with '--' ) then
                    in autonomous transaction do
                        execute statement v_pkey_expr;

                add_info = v_trig_expr;
                suspend;
                if ( v_trig_expr not starting with '--' ) then
                    in autonomous transaction do
                        execute statement v_trig_expr;
            end
        else
            begin
                add_info = v_trig_expr;
                suspend;
                if ( v_trig_expr not starting with '--' ) then
                    in autonomous transaction do
                        execute statement v_trig_expr;

                add_info = v_pkey_expr;
                suspend;
                if ( v_pkey_expr not starting with '--' ) then
                    in autonomous transaction do
                        execute statement v_pkey_expr;

                if ( v_drop_pkid is not null) then
                begin
                    add_info = v_drop_pkid;
                    suspend;
                    in autonomous transaction do
                        execute statement v_drop_pkid;
                end


            end

    end

end -- tmp_init_autogen_qdistr_tables

^ 
set term ;^
commit;

set transaction read committed record_version no wait;

-- Value of settings.svalue is replaced with config parameter 'used_in_replication'
--  by 1run_oltp_emul.bat (.sh) every time test is launched:
set count on;
set list on;
select * from tmp_sp_generate_update_pk_ddl( (select svalue from settings s where s.mcode ='USED_IN_REPLICATION') );
set list off;
set count off;
commit;

drop procedure tmp_sp_generate_update_pk_ddl;
drop procedure tmp_sp_check_for_table_has_pk;
drop view tmp_v_tabs_without_pk_constr;
drop view tmp_v_tabs_wo_pkid_and_constr;
commit;

set list on;
set echo off;
select 'oltp_replication_DDL.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;
-- #######################################################
-- End of script oltp_replication_DDL.sql; next to be run: 
-- oltp_data_filling.sql
-- #######################################################
