-- ########################################
-- Begin of script oltp_replication_DDL.sql
-- ########################################

set bail on;
set list on;

set term ^;
execute block returns( " " varchar(255) ) as
begin
    " " = 'set list on; select ''oltp_replication_DDL.sql start at '' || current_timestamp as msg from rdb$database;';
    suspend;
    " " = 'set echo ON;'; suspend;
    " " = 'set bail ON;'; suspend;
end
^
set term ;^
commit;

--select 'set list on; select ''oltp_replication_DDL.sql start at '' || current_timestamp as msg from rdb$database;' as " "
--from rdb$database
--union all
--select 'set echo ON; set bail ON;' as " "
--from rdb$database
--union all
--select 'set autoddl ON; commit;' as " "
--from rdb$database
--;
--commit;


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
    'perf_isql_stat' as s from rdb$database union all select
    'zdoc_data' from rdb$database union all select
    'zdoc_list' from rdb$database union all select
    'zinvnt_turnover_log' from rdb$database union all select
    'zpdistr' from rdb$database union all select
    'zpstorned' from rdb$database union all select
    'zqdistr' from rdb$database union all select
    'zqstorned' from rdb$database union all select
    'ztmp_dep_docs' from rdb$database union all select
    'ztmp_shopping_cart' from rdb$database
;
commit;

set term ^;
create or alter procedure tmp_sp_check_for_table_has_pk(a_rel_name varchar(64) character set utf8)
returns(has_pk smallint) as
begin
     -- returns 1 if table has PK/UK, otherwise returns 0.
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
returns(sql_expr varchar(512))
as
    declare v_table_to_be_changed varchar(31);
    declare v_pkey_expr varchar(512);
    declare v_trig_expr varchar(512);
    declare v_drop_pkid varchar(512);
    declare v_lf char(1);
    declare v_connect_usr varchar(31);
    declare v_connect_pwd varchar(31);
    declare v_connect_str varchar(512);
    
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
        select 'qdistr' as s from rdb$database 
        union all 
        select 'qstorned' from rdb$database
        UNION ALL
        select s from tmp_v_tabs_without_pk_constr
    );
begin
    v_lf = ascii_char(10);

    select t.svalue
    from settings t
    where t.working_mode='COMMON' and t.mcode='BUILD_WITH_SPLIT_HEAVY_TABS'
    into v_split_heavy_tabs;
    if ( v_split_heavy_tabs is null ) then
        exception ex_record_not_found;

    -- extract value of connection string that was inserted into settings on initial phase of batch script
    -- as result of concatenations config parameters: host, port, usr and pwd.
    -- This record is added/chganged in SETTINGS table by statement:
    -- update or insert into settings(working_mode, mcode, svalue)
    -- values( upper( 'common' ), upper( 'connect_str' ),  'connect ''localhost/3050:/Data/oltp-emul/oltp30_test.fdb'' user ''SYSDBA'' password ''masterkey'';')
    -- matching (working_mode, mcode);

    select t.svalue
    from settings t
    where t.mcode='CONNECT_STR'
    into v_connect_str;
    if ( v_connect_str is null ) then
        exception ex_record_not_found;

    -- result: v_connect_str = 
    -- connect 192.168.20.31/3322:/var/db/oltp-emul/testdb_30.fdb user 'SYSDBA' password 'QweRty';

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
                v_pkey_expr = v_lf
                   || 'alter table ' 
                   || v_table_to_be_changed
                   || ' add constraint ' || v_table_to_be_changed || '_pk primary key(id)'
                   || ' using index ' || v_table_to_be_changed || '_pk;'
                   ;
            else
                v_pkey_expr = '-- table '''||v_table_to_be_changed||' already has PK, skip add constraint.';
        else -- a_create_pk = 0 --> DROP PK (if exists)
            if ( (select has_pk from tmp_sp_check_for_table_has_pk(:v_table_to_be_changed)) = 1 ) then
                v_pkey_expr = v_lf
                   || 'alter table ' 
                   || v_table_to_be_changed
                   || ' drop constraint ' || v_table_to_be_changed || '_pk;'
                   ;
            else
                v_pkey_expr = '-- table '''||v_table_to_be_changed||''' has no PK, skip drop constraint.';

        sql_expr = v_pkey_expr;
        suspend;
  
        -- dis 01.11.2018
        -- if ( v_pkey_expr not starting with '--' ) then
        --    in autonomous transaction do
        --        execute statement v_pkey_expr;

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


    for 
        select s from tmp_v_tabs_wo_pkid_and_constr
        where exists(
                select * from rdb$relations r
                    where r.rdb$relation_name = upper( s )
                        and coalesce(r.rdb$system_flag, 0) = 0
                    )

        into v_table_to_be_changed
    do begin
        v_table_to_be_changed = trim(v_table_to_be_changed);
        v_drop_pkid = null;
        if (a_create_pk = 1) then
            begin
                if ( (select has_pk from tmp_sp_check_for_table_has_pk(:v_table_to_be_changed)) = 0 ) then
                    begin
                        --in autonomous transaction do
                        --    execute statement 'delete from '||v_table_to_be_changed;
                        sql_expr = v_lf 
                            || 'delete from ' || v_table_to_be_changed || ';' 
                            || v_lf || 'commit;'
                        ;
                        suspend;

                        sql_expr = v_lf
                            ||'alter table '
                            || v_table_to_be_changed
                            || ' add pkid dm_idb not null;'
                            || v_lf || 'commit;'
                        ;
                        suspend;

                        -- ############################
                        -- ###   r e c o n n e c t  ###
                        -- ############################
                        -- See letter to dimitr, hvlad, alex; 01.11.2018 17:13.
                        sql_expr = v_connect_str;
                        suspend;

                        v_pkey_expr = v_lf
                            ||'alter table '
                            || v_table_to_be_changed
                            || ' add constraint ' || v_table_to_be_changed || '_pk primary key( pkid )'
                            || ' using index ' || v_table_to_be_changed || '_pk;'
                            || v_lf || 'commit;'
                            ;
                    end
                else
                    v_pkey_expr = v_lf || '-- table '''||v_table_to_be_changed||''' already has PK, skip add constraint.';

                v_trig_expr = v_lf 
                            || 'commit;' || v_lf
                            || 'set term ^;'
                    || v_lf || 'create or alter trigger ' || v_table_to_be_changed || '_0i '
                    || v_lf || 'for ' ||v_table_to_be_changed || ' active before insert position 0 as '
                    || v_lf || 'begin'
                    || v_lf || '    -- do NOT edit, generated auto by ''oltp_replication_DDL.sql''.'
                    || v_lf || '    new.pkid =  coalesce( new.pkid, gen_id(g_common, 1) );'
                    || v_lf || 'end ^'
                    || v_lf || 'set term ;^'
                    ;
            end
        else
            begin
                if ( exists(select * from rdb$triggers where rdb$trigger_name = upper(:v_table_to_be_changed||'_0i') ) ) then
                    v_trig_expr = 'drop trigger ' || v_table_to_be_changed || '_0i;' ;
                else
                    v_trig_expr = '-- table '''||v_table_to_be_changed||''' has no PK-trigger, skip drop trigger.';

                if ( (select has_pk from tmp_sp_check_for_table_has_pk(:v_table_to_be_changed)) = 1 ) then
                    begin
                        v_pkey_expr = v_lf
                           || 'alter table ' 
                           || v_table_to_be_changed
                           || ' drop constraint ' || v_table_to_be_changed || '_pk;'
                           || v_lf ||'commit;'
                           -- commented until CORE-5446 not fixed: || ',drop pkid'
                           ;
                        v_drop_pkid = v_lf
                           || 'alter table ' 
                           || v_table_to_be_changed
                           || ' drop pkid;' -- drop column 'pkid' that was created before
                           || v_lf ||'commit;'
                           ;
                    end
                else
                    v_pkey_expr = v_lf || '-- table '''||v_table_to_be_changed||''' has no PK, skip drop constraint.';

            end


        if (a_create_pk = 1) then
            begin
                sql_expr = v_pkey_expr;
                suspend;
                --if ( v_pkey_expr not starting with '--' ) then
                --    in autonomous transaction do
                --        execute statement v_pkey_expr;

                sql_expr = v_trig_expr;
                suspend;
                --if ( v_trig_expr not starting with '--' ) then
                --    in autonomous transaction do
                --        execute statement v_trig_expr;
            end
        else
            begin
                sql_expr = v_trig_expr;
                suspend;
                --if ( v_trig_expr not starting with '--' ) then
                --    in autonomous transaction do
                --        execute statement v_trig_expr;

                sql_expr = v_pkey_expr;
                suspend;
                --if ( v_pkey_expr not starting with '--' ) then
                --    in autonomous transaction do
                --        execute statement v_pkey_expr;

                if ( v_drop_pkid is not null) then
                begin
                    sql_expr = v_drop_pkid;
                    suspend;
                    --in autonomous transaction do
                    --    execute statement v_drop_pkid;
                end


            end

    end

end -- tmp_sp_generate_update_pk_ddl

^ 
set term ;^
commit;

--set transaction read committed record_version no wait;

-- Value of settings.svalue is replaced with config parameter 'used_in_replication'
--  by 1run_oltp_emul.bat (.sh) every time test is launched:
set list on;
set term ^;
execute block returns(" " varchar(512)) as
begin
    for 
        select sql_expr 
        from tmp_sp_generate_update_pk_ddl( (select svalue from settings s where s.mcode ='USED_IN_REPLICATION') )
    into " "
    do 
        suspend;
end
^
set term ;^
commit;

drop procedure tmp_sp_generate_update_pk_ddl;
drop procedure tmp_sp_check_for_table_has_pk;
drop view tmp_v_tabs_without_pk_constr;
drop view tmp_v_tabs_wo_pkid_and_constr;
commit;

set heading off;
set list on;

select 'set echo off;' as " "
from rdb$database
union all
select 'set list on; select ''oltp_replication_DDL.sql finish at '' || current_timestamp as msg from rdb$database;' as " "
from rdb$database
;

/*
-- select r.rdb$relation_type, r.rdb$relation_name, c.rdb$constraint_type from rdb$relations r left join rdb$relation_constraints c on r.rdb$relation_name =  c.rdb$relation_name and c.rdb$constraint_type in( 'PRIMARY KEY', 'UNIQUE' ) where r.rdb$system_flag is distinct from 1 and r.rdb$relation_type = 0  and c.rdb$relation_name is null rows 10;

select r.rdb$relation_name as "Table without PK/UK"
from rdb$relations r 
left join rdb$relation_constraints c 
on r.rdb$relation_name =  c.rdb$relation_name and c.rdb$constraint_type in( 'PRIMARY KEY', 'UNIQUE' ) 
where 
    r.rdb$system_flag is distinct from 1 
    and r.rdb$relation_type = 0 -- fixed tables (NOT views and NOT GTTs)
    and c.rdb$relation_name is null 
;
*/

commit;

-- #######################################################
-- End of script oltp_replication_DDL.sql; next to be run: 
-- oltp_data_filling.sql
-- #######################################################
