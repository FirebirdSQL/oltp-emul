-- ###################################
-- Begin of script oltp_common_DDL.sql
-- ###################################

-- ::: NB ::: This script is COMMON for both FB 2.5 and 3.0 and should be called
-- from batch scenario after oltp_split_heavy_tabs_0.sql or oltp_split_heavy_tabs_1.sql

set bail on;
set list on;

select 'set list on; select ''oltp_common_DDL.sql start at '' || current_timestamp as msg from rdb$database;' as " "
from rdb$database
union all
select 'set echo off;' as " "
from rdb$database
;
commit;

set term ^;
create or alter procedure srv_gen_sql_4drop_perf_split
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
    
    -- 4. DROP trigger, view and proc that not depend on tables:
    sql_sttm = v_lf || 'drop trigger trg_v_perf_log;'
            || v_lf || 'commit;'
    ;
    suspend;
end
^ -- end of srv_gen_sql_4drop_perf_split


create or alter procedure srv_gen_sql_4tmp_idx_perf_split( a_perf_log_split_cnt smallint = null )
returns( 
    sql_sttm varchar(32765) 
) as
    declare v_lf char(1);
    declare v_perf_split_name varchar(31);
    declare i smallint = 0;
begin
    v_lf = ascii_char(10);

    -- Create auxiliary indices for all tables with names PERF_SPLIT_nn
    -- (need them for REPORTS only)
  if ( a_perf_log_split_cnt  is null ) then
  begin
    for 
        select trim(r.rdb$relation_name)
        from rdb$relations r
        where trim(r.rdb$relation_name) similar to upper('perf_split_[[:DIGIT:]]{1,3}')
        order by 1
        into v_perf_split_name
    do begin
       sql_sttm = v_lf || '-- We need these indices TEMPORARY, for report procedures.'
               || v_lf || 'create descending index '|| v_perf_split_name ||'_unit on '|| v_perf_split_name ||'(unit, elapsed_ms);'
               || v_lf || 'create index '|| v_perf_split_name ||'_gdscode on '|| v_perf_split_name ||'( fb_gdscode );'
       ;
       suspend;
    end
    sql_sttm = v_lf || 'commit;' ;
    suspend;
  end
  else -- for debug only, remove it later
  begin
    i = 0;
    while (i <  a_perf_log_split_cnt ) do
    begin
       sql_sttm = 'create descending index perf_split_'|| i ||'_unit on perf_split_'|| i ||'(unit, elapsed_ms);'
       ;
       suspend;
       sql_sttm = 'create index perf_split_'|| i ||'_gdscode on perf_split_'|| i ||'( fb_gdscode );'
       ;
       suspend;
        i = i + 1;
    end
  end
end
^ -- srv_gen_sql_4tmp_idx_perf_split

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

    v_autogen = '-- ### ACHTUNG ### DO NOT EDIT, GENERATED AUTO!.';
    
    -- 13.10.2018, called only from HERE, see EB below.
    -- Generates SQL statements for TRIGGER trg_v_perf_log which serves as 'case-switcher'
    -- on every insert into UPDATABLE VIEW v_perf_log.
    -- 15.10.2018, NB: trigger must be created EVEN if number of perf_split_nn tables is 1:
    -- we have to ensure that field PERF_SPLIT_0.ID will be always NOT null!
    sql_sttm = v_lf || 'set term ^;'
       || v_lf || 'create or alter trigger trg_v_perf_log active before insert on v_perf_log as'
       || v_lf || '    declare v_dts_beg timestamp;'
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
    sql_sttm = 
           v_lf || '    if ( rdb$get_context(''USER_SESSION'',''PERF_WATCH_BEG'') is null ) then'
        || v_lf || '    begin'
        || v_lf || '        select p.dts_beg from perf_log p where p.unit = ''perf_watch_interval'' order by dts_beg+0 desc rows 1 into v_dts_beg;'
        || v_lf || '        rdb$set_context( ''USER_SESSION'',''PERF_WATCH_BEG'', v_dts_beg );'
        || v_lf || '    end'
        || v_lf || '    if ( cast(''now'' as timestamp) < cast( rdb$get_context(''USER_SESSION'',''PERF_WATCH_BEG'') as timestamp) ) then '
        || v_lf || '        -- We can SKIP from logging in perf_log table if current timestamp belongs to PREPARING phase or warm-up database.'
        || v_lf || '        exit;'
    ;    
    suspend;
    
    -- ########################################################################################
    -- new value for ID field must be always NOT null, regardless of a_perf_log_split_cnt value
    -- ########################################################################################
    sql_sttm = v_lf || 'new.id = coalesce(new.id, gen_id(g_perf_log, 1) );'
    ;
    suspend;
    i = 0;
    while ( i < a_perf_log_split_cnt ) do -- and a_perf_log_split_cnt >= 2 ) do
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
begin
    v_lf = ascii_char(10);
    v_autogen = '-- ### ACHTUNG ### DO NOT EDIT, GENERATED AUTO!.';
    
    " " = 'set bail on; ' || v_autogen
    ;
    suspend;

    -- +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    -- g e n e r a t e     S Q L     f o r    D R O P      o l d     t e m p o r a r y   P E R F_ S P L I T _ nn
    -- +=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+
    for select sql_sttm from srv_gen_sql_4drop_perf_split into " " 
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
              " " =  v_lf || 'alter table perf_split_' || i || ' add constraint perf_split_' || i || '_pk primary key(id) using index perf_split_' || i || '_id;'
              ;
              suspend;

            end
        else -- ==> UNIONED-view V_PERF_LOG will be used instead of TABLE PERF_LOG in all queries (NB: reports!)
            begin
              " " =  v_lf || '-- SKIP adding primary key to PERF_SPLIT_' || i || ':'
                  || v_lf || '-- its record in BUSINESS_OPS either does not exist or has random_selection_weight<=0.' 
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
begin
    v_lf = ascii_char(10);
   
    if ( NOT exists(select * from doc_list) ) then
        begin

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
                    if ( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.5' ) then
                        " " = 'alter table doc_list add constraint worker_id_nn check( worker_id is not null );' ;
                    else
                        " " = 'alter table doc_list alter column worker_id set NOT null;' ;

                    " " = " " || v_lf || 'commit;' ;
                    suspend;
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

        end -- NOT exists(select * from doc_list) ==> we CAN change indices DDL for doc_list, pdistr, pstorned

    else

        begin
            " " = '-- SKIP changing DDL of indices for tables DOC_LIST et al.: at least one document already does exist!';
            suspend;
        end -- EXISTS at least one record in doc_list --> we can NOT change indices for doc_list, pdistr, pstorned


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
select 'set list on; select ''oltp_common_DDL.sql finish at '' || current_timestamp as msg from rdb$database;' as " "
from rdb$database
;
commit;

-- ##########################################################
-- End of script oltp_common_DDL.sql; next to be run:
-- oltp_replication_DDL.sql (common for both FB 2.5 and 3.0)
-- ##########################################################
