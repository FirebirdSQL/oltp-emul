-- 17.05.2020
-- NOTE: THIS SQL WILL NOT BE COMPILED IN B 2.5, IT MUST BE RUN ONLY IN 3.X+.
-- All DB objects (tables, views, proceures, function) must already exists here.

set bail on;
set list on;

select 'set list on; select ''oltp_adjust_grants.sql start at '' || current_timestamp as msg from rdb$database;' as "--TMP$SQL$CODE"
from rdb$database
union all
select 'set echo off;'
from rdb$database
;
commit;
set term ^;

-- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
--  g e n e r a t e        S Q L    f o r    c r e a t i n g      t e m p.    u s e r s
--  w h i c h     w i l l    q u e r y     m o n $     t a b l e s    w h e n   c o n f.
--  p a r a m e t e r      m o n _ u n i t _ p e r f = 1
--  -------------------------------------------------------------------
--  :::: N B ::::  a c t u a l     o n l y     i n     F B   3.x +
-- +#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#+#
-- See: http://sourceforge.net/p/firebird/code/62745
-- Tag the shmem session clumplets with username. This allows much faster lookups for non-locksmith users.
-- 01.08.2025: returning argument must not be empty in 6.x; choosen name: "--TMP$SQL$CODE"

create or alter procedure srv_gen_sql_make_oltp_worker returns( "--TMP$SQL$CODE" varchar(8192) ) as
    declare v_lf char(1) = x'0A';
    declare v_sessions_count smallint = null;
    declare i smallint;
    declare v_tmp_user_prefix varchar(31);
    declare v_tmp_user_pswd varchar(31);
    declare v_tmp_worker_user varchar(31);
    declare v_tmp_worker_role varchar(31);
begin
    if ( rdb$get_context('SYSTEM', 'ENGINE_VERSION') NOT starting with '2.5' ) then
    begin
        "--TMP$SQL$CODE" = 'set bail on;' ;
        suspend;
        "--TMP$SQL$CODE" = 'set autoddl off;' ;
        suspend;
        "--TMP$SQL$CODE" = 'execute procedure srv_drop_oltp_worker;' ;
        suspend;
        "--TMP$SQL$CODE" = 'commit;' ;
        suspend;

        -- These values were added into SETTINGS in the routine 'sync_settings_with_conf'.
        select
             min(iif( s.mcode = upper('tmp_worker_user_prefix'), nullif(s.svalue, ''), null ))
            ,min(iif( s.mcode = upper('tmp_worker_user_pswd'), nullif(s.svalue, ''), null ))
            ,min(iif( s.mcode = upper('tmp_worker_role_name'), nullif(s.svalue, ''), null ))
            ,min( cast( iif(s.mcode = upper('WORKERS_COUNT'), s.svalue, null) as int ))
        from settings s
        where s.mcode in (  upper('tmp_worker_user_prefix')
                           ,upper('tmp_worker_user_pswd')
                           ,upper('tmp_worker_role_name')
                           ,upper('WORKERS_COUNT')
                         )
        into
             v_tmp_user_prefix
            ,v_tmp_user_pswd
            ,v_tmp_worker_role
            ,v_sessions_count;

        "--TMP$SQL$CODE" = '-- Found in SETTINGS table:'
              || ' tmp_worker_user_prefix=' || coalesce(v_tmp_user_prefix, '[null]')
              || ', tmp_worker_user_passwd=' || coalesce(v_tmp_user_pswd, '[null]')
              || ', tmp_worker_role_name=' || coalesce(v_tmp_worker_role, '[null]')
              || ', sessions_count=' || coalesce(v_sessions_count, '[null]')
        ;
        suspend;

        if ( v_tmp_user_prefix is null or v_tmp_user_pswd is null or v_tmp_worker_role is null ) then
            exception ex_record_not_found 'At least one of mandatory values not found: ''tmp_worker_user_prefix'' or ''tmp_worker_user_pswd'' or ''tmp_worker_role_name''.';

        -- Value in SETTINGS table is updated every time with required number of ISQL sessions.
        -- This is done always before test run, see .bat:
        -- call :inject_actual_setting %fb% common workers_count '%winq%'

        if ( v_tmp_user_prefix > '' ) then
            begin
                i = 1;
                -------------------   C R E A T E    T E M P .    U S E R S   ----------------
                while ( i <= v_sessions_count) do
                begin
                    v_tmp_worker_user = v_tmp_user_prefix || lpad(i, 4, '0');
                    "--TMP$SQL$CODE" = 'create or alter user ' || coalesce(v_tmp_worker_user,'[null]') || ' password ''' || coalesce(v_tmp_user_pswd,'[null]') || ''' revoke admin role;' ;
                    suspend;
                    -- ::: NB ::: 22.08.2020
                    -- DO NOT DELETE/CHANGE TAG '#OLTP_EMUL#'! IT IS USED IN SP SRV_DROP_OLTP_WORKER
                    -- FOR SEARCH AND DROP OLD TEMPORARY CREATED USERS/ROLE!
                    "--TMP$SQL$CODE" = 'comment on user '|| coalesce(v_tmp_worker_user, '[null]')
                          || ' is ''#OLTP_EMUL# temporary non-privileged user, created to gather monitoring'
                          || ' data using role "' || v_tmp_worker_role || '" and its grants.'
                          || ' See config parameters "tmp_worker_user_prefix" and "tmp_worker_role_name".'';'
                    ;
                    suspend;
                    i = i + 1;
                end
                "--TMP$SQL$CODE" = 'commit;';
                suspend;
              end
        else
            begin
                "--TMP$SQL$CODE" = q'{-- Temporary DB users for worker sessions are NOT created: config parameter 'mon_usr_prefix' is undefined.}';
                suspend;
            end


        -------------------  R E C R E A T E    R O L E  ----------------
        if ( v_tmp_worker_role > '' and upper(v_tmp_worker_role) != upper('rdb$admin') ) then
            begin

                "--TMP$SQL$CODE" = 'create role ' || v_tmp_worker_role ||';' ;
                suspend;
                -- ::: NB ::: 22.08.2020
                -- DO NOT DELETE/CHANGE TAG '#OLTP_EMUL#'! IT IS USED IN SP SRV_DROP_OLTP_WORKER
                -- FOR SEARCH AND DROP OLD TEMPORARY CREATED USERS/ROLE!
                "--TMP$SQL$CODE" = 'comment on role ' || v_tmp_worker_role
                      || ' is ''#OLTP_EMUL# temporary role for gathering monitoring data by non-privileged users'
                      || ' which names start with prefix "' || v_tmp_user_prefix || '".'
                      || ' See config parameters "tmp_worker_user_prefix" and "tmp_worker_role_name".'';'
                ;
                suspend;
                ------------------------------------------------------------------

                -- This is needed for srv_recalc_idx: no separate privilege for this, only alter WHOLE table!
                "--TMP$SQL$CODE" = 'grant alter any table to role ' || v_tmp_worker_role || '; commit;' ;
                suspend;

                -----------------------------------------------------------------
                for
                    select 'p' as unit_type, trim( p.rdb$procedure_name ) as unit_name
                    from rdb$procedures p
                    where p.rdb$system_flag is distinct from 1

                    UNION ALL
                    
                    select 'f', trim( f.rdb$function_name )
                    from rdb$functions f
                    where f.rdb$system_flag is distinct from 1
                    as cursor c
                do begin
                    "--TMP$SQL$CODE" = 'grant execute on '
                               || iif(c.unit_type='p', 'procedure ', 'function ')
                               || c.unit_name
                               || ' to role ' || v_tmp_worker_role || ';'
                    ;
                    suspend;
                end

                ------------------------
                -- tables (permanent and GTTs: rel_type=0,4,5) and VIEWs (rel_type=1):
                for
                    select trim(r.rdb$relation_name) as rel_name
                    from rdb$relations r
                    where r.rdb$relation_type in (0,4,5, 1) and r.rdb$system_flag is distinct from 1
                    as cursor c
                do begin
                    "--TMP$SQL$CODE" = 'grant select,insert,update,delete on ' || c.rel_name || ' to role ' || v_tmp_worker_role || ';'
                    ;
                    suspend;
                end

                ------------------------
                -- generators and exceptions:
                for
                    select 'g' as obj_type, trim(g.rdb$generator_name) as obj_name
                    from rdb$generators g
                    where g.rdb$system_flag is distinct from 1
                    and g.rdb$generator_name not starting with upper('rdb$')

                    UNION ALL

                    select 'x', trim(x.rdb$exception_name) as exc_name
                    from rdb$exceptions x
                    where x.rdb$system_flag is distinct from 1

                    as cursor c
                do begin
                    "--TMP$SQL$CODE" = 'grant usage on '
                          || iif(c.obj_type='g', 'sequence ', 'exception ')
                          || c.obj_name
                          || ' to role ' || v_tmp_worker_role || ';'
                    ;
                    suspend;
                end
                ------------------------

                -- grant role to all temp users:
                i = 1;
                while ( i <= v_sessions_count) do
                begin
                    v_tmp_worker_user = v_tmp_user_prefix || lpad(i, 4, '0');
                    "--TMP$SQL$CODE" = 'grant ' || v_tmp_worker_role || ' to user '|| v_tmp_worker_user ||';' ;
                    suspend;
                    i = i + 1;
                end
    
                "--TMP$SQL$CODE" = 'set autoddl on;'
                        || v_lf || 'commit;'
                        || v_lf || 'show users;'
                        || v_lf || 'show role;'
                        || v_lf || 'show grants;'
                        || v_lf || 'set bail off;'
                ;
                suspend;
    
            end -- v_tmp_worker_role is DEFINED and not 'rdb$admin'

        else
            begin
                "--TMP$SQL$CODE" = q'{-- Temporary role for worker sessions is NOT created: config parameter 'mon_query_role' is undefined or incorrect.}';
                suspend;
            end

    end
    -- engine NOT starting with '2.5'
end
^ -- srv_gen_sql_make_oltp_worker
set term ;^
commit;


-- #####################################################################################################################

set heading off;
set list on;


set transaction no wait;
-- We have ALWAYS to drop any old temp users and role before their recreation:
execute procedure srv_drop_oltp_worker;
commit;

-- This produces SQL code for create role and users:
-- @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
select * from srv_gen_sql_make_oltp_worker;
-- @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

select 'set echo off;' as "--TMP$SQL$CODE"
from rdb$database
union all
select 'set list on; select ''oltp_adjust_grants.sql finish at '' || current_timestamp as msg from rdb$database;'
from rdb$database
;
commit;

-- #####################################################################################
-- End of script oltp_adjust_grants.sql. It must be LAST script before run ISQL sessions
-- #####################################################################################
