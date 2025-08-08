set bail on;
set list on;
select
'
set list on;
select ''oltp_adjust_eds_calls.sql start at '' || current_timestamp as msg from rdb$database;
set autoddl off;
set bail on;
commit;
set transaction no wait;
' as "--TMP$SQL$CODE"
from rdb$database
;
commit;

set term ^;
execute block returns("-- blob_id" blob sub_type 1) as
  declare v_lf char(1) = x'0A';
  declare v_use_es smallint;
  declare v_conn_pool_support smallint;
  declare v_resetting_support smallint;

  declare v_host varchar(64);
  declare v_port int;
  declare v_usr varchar(64);
  declare v_pwd varchar(64);
  declare v_tmp_user_pswd varchar(64);

  declare v_body_query varchar(4096);

  declare v_unit_query varchar(8192);
  declare v_base_filter varchar(8192);
  declare v_proc_filter varchar(8192);
  declare v_func_filter varchar(8192);
  declare v_trig_filter varchar(8192);

  declare v_obj_type char(1);
  declare v_obj_name dm_dbobj;


  --declare v_orig_body varchar(32765);
  --declare v_repl_body varchar(32765);
  
  -- 22.11.2020, SP sp_make_qty_storno: too long code!
  declare v_orig_body blob sub_type 1 segment size 80;
  declare v_repl_body blob sub_type 1 segment size 80;

  declare v_unit_header varchar(32765);
  declare v_body_line varchar(8190) character set utf8;
  declare v_orig_subst_with_at varchar(255);
  declare v_orig_subst_for_eds varchar(255);
  declare n_pad int;
  declare n_indent int;
begin
    select
         max( iif( upper(s.mcode) = upper('use_es'), s.svalue , null ) ) -- see config: 0; 1 or 2
        ,max( iif( upper(s.mcode) = upper('conn_pool_support'), s.svalue , null ) ) --  0 or 1
        ,max( iif( upper(s.mcode) = upper('resetting_support'), s.svalue , null ) ) -- 0 or 1
        ,max( iif( upper(s.mcode) = upper('host'), s.svalue , null ) )
        ,max( iif( upper(s.mcode) = upper('port'), s.svalue , null ) )
        ,max( iif( upper(s.mcode) = upper('usr'), s.svalue , null ) )
        ,max( iif( upper(s.mcode) = upper('pwd'), s.svalue , null ) )
        ,max( iif( upper(s.mcode) = upper('tmp_worker_user_pswd'), s.svalue , null ) )
    from settings s 
    where
        s.working_mode in( upper('init'), upper('common') )
        and upper(s.mcode) in (  upper('use_es')
                                ,upper('conn_pool_support')
                                ,upper('resetting_support')
                                ,upper('host')
                                ,upper('port')
                                ,upper('usr')
                                ,upper('pwd')
                                ,upper('tmp_worker_user_pswd')
                              )
    into
        v_use_es
       ,v_conn_pool_support
       ,v_resetting_support
       ,v_host
       ,v_port
       ,v_usr
       ,v_pwd
       ,v_tmp_user_pswd
    ;

    if ( v_use_es || v_conn_pool_support || v_resetting_support || v_host || v_port || v_usr || v_pwd || v_tmp_user_pswd is null ) then
        exception ex_record_not_found -- 'required record not found, datasource: @1, key: @2'
            using('SETTINGS', 'use_es / conn_pool_support / resetting_support / host / port / usr / pwd / tmp_worker_user_pswd')
        ;
    
    -- v_orig_subst_with_at = '-- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#';
    v_orig_subst_for_eds = q'{-- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#}';

    -- ############################
    -- special chars in SIMILAR TO:
    -- [ ] ( ) | ^ - + * % _ ? { }
    -- ############################

    -- Process any lines similar to '%\-\-[[:SPACE:]]*#SUBST#EXTPOOL#SUPPORT\_(0|1)#END#%' according to current value of v_conn_pool_support
    -- Process any lines similar to '%\-\-[[:SPACE:]]*#SUBST#RESETTING\_(0|1)#END#%' according to current value of v_use_es

    if ( v_use_es = 0 ) then
        begin
            -- When use_es=0 then we must:
            -- COMMENT OUT lines containing '-- #SUBS#CONNSTR#END#' and NOT containing '-- #SUBS#CONNSTR#BEG#' (i.e. they starts with: on external 'localhost/3400:...')
            -- COMMENT OUT lines containing '-- #SUBST#EXTPOOL#SUPPORT_1#END#' and NOT containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#'
            -- UNCOMMENT lines containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#'
            -- UNCOMMENT multi-line blocks that start with:
            --   '/* #ACTIVATE#IF#USE_ES_EQU_0' or
            --   '/* #ACTIVATE#IF#USE_ES_NEQ_1' or
            --   '/* #ACTIVATE#IF#USE_ES_NEQ_2'
            -- COMMENT OUT multi-line blocks that starts with:
            --   '-- #ACTIVATE#IF#USE_ES_EQU_1#BEG#' or
            --   '-- #ACTIVATE#IF#USE_ES_EQU_2#BEG#'

            v_base_filter = q'{ #rdb_source_column# containing '-- #SUBS#CONNSTR#END#' and #rdb_source_column# NOT containing '-- #SUBS#CONNSTR#BEG#' }'
                         || q'{ or #rdb_source_column# containing '-- #SUBST#EXTPOOL#SUPPORT_1#END#' and #rdb_source_column# NOT containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#' }'
                         || q'{ or #rdb_source_column# containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#' }'
                         || q'{ or #rdb_source_column# similar to '%/\* #ACTIVATE#IF#USE\_ES\_(EQU\_0|NEQ\_1|NEQ\_2)#BEG#%' escape '\' }'
                         || q'{ or #rdb_source_column# similar to '%\-\- #ACTIVATE#IF#USE_ES_(EQU\_1|EQU\_2)#BEG#%' escape '\' }'
            ;
        end
    else if ( v_use_es = 1 ) then
        begin
            -- When use_es=1 then we must:
            -- COMMENT OUT lines wich contain '-- #SUBS#CONNSTR#END# and NOT contain '-- #SUBS#CONNSTR#BEG#' (i.e. they starts with: on external 'localhost/3400:...')
            -- COMMENT OUT lines containing '-- #SUBST#EXTPOOL#SUPPORT_1#END#' and NOT containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#'
            -- UNCOMMENT lines containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#'
            -- UNCOMMENT multi-line blocks that start with:
            --   '/* #ACTIVATE#IF#USE_ES_EQU_1' or
            --   '/* #ACTIVATE#IF#USE_ES_NEQ_0' or
            --   '/* #ACTIVATE#IF#USE_ES_NEQ_2'
            -- COMMENT OUT multi-line blocks that starts with:
            --   '-- #ACTIVATE#IF#USE_ES_EQU_0#BEG#' or
            --   '-- #ACTIVATE#IF#USE_ES_EQU_2#BEG#'
            v_base_filter = q'{ #rdb_source_column# containing '-- #SUBS#CONNSTR#END#' and #rdb_source_column# not containing '#SUBSTITUTION#BEG#' }'
                         || q'{ or #rdb_source_column# containing '-- #SUBST#EXTPOOL#SUPPORT_1#END#' and #rdb_source_column# NOT containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#' }'
                         || q'{ or #rdb_source_column# containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#' }'
                         || q'{ or #rdb_source_column# similar to '%/\* #ACTIVATE#IF#USE\_ES\_(EQU\_1|NEQ\_0|NEQ\_2)#BEG#%' escape '\'}'
                         || q'{ or #rdb_source_column# similar to '%\-\- #ACTIVATE#IF#USE_ES_(EQU\_0|EQU\_2)#BEG#%' escape '\' }'
            ;
        end
    else if ( v_use_es = 2 ) then
        begin
            -- When use_es=2 then we must:
            -- UNCOMMENT lines that start with '-- #SUBS#CONNSTR#BEG#'; after further substitution such rows will start with: on external 'localhost/3400....'
            -- COMMENT OUT lines containing '-- #SUBST#EXTPOOL#SUPPORT_0#END#' and NOT containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#'
            -- UNCOMMENT lines containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#' (if v_conn_pool_support = 1) or leave them unchanged
            -- Process any lines similar to '%\-\-[[:SPACE:]]*#SUBST#EXTPOOL#SUPPORT\_(0|1)#END#%' according to current value of v_conn_pool_support
            -- Process any lines similar to '%\-\-[[:SPACE:]]*#SUBST#RESETTING\_(0|1)#END#%' according to current value of v_use_es
            -- UNCOMMENT multi-line blocks that start with:
            -- '/* #ACTIVATE#IF#USE_ES_EQU_2#BEG'
            -- '/* #ACTIVATE#IF#USE_ES_NEQ_1#BEG'
            -- '/* #ACTIVATE#IF#USE_ES_NEQ_0#BEG'
            -- COMMENT OUT multi-line blocks that starts with:
            --   '-- #ACTIVATE#IF#USE_ES_EQU_0#BEG#' or
            --   '-- #ACTIVATE#IF#USE_ES_EQU_1#BEG#'
            v_base_filter = q'{ #rdb_source_column# containing '-- #SUBS#CONNSTR#BEG#' }'
                         || q'{ or #rdb_source_column# containing '-- #SUBST#EXTPOOL#SUPPORT_0#END#' and #rdb_source_column# NOT containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#' }'
                         || q'{ or #rdb_source_column# containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#' }'
                         || q'{ or #rdb_source_column# similar to '%/\* #ACTIVATE#IF#USE\_ES\_(EQU\_2|NEQ\_1|NEQ\_0)#BEG#%' escape '\'}'
                         || q'{ or #rdb_source_column# similar to '%\-\- #ACTIVATE#IF#USE_ES_(EQU\_0|EQU\_1)#BEG#%' escape '\' }'
            ;

        end


     v_base_filter = q'{ #rdb_source_column# containing '-- #SUBS#CONNSTR#END#' }' || v_lf
                  || q'{ or #rdb_source_column# similar to '%\-\-#SUBST#EXTPOOL#SUPPORT\_(0|1)#END#%' escape '\' }' || v_lf
                  || q'{ or #rdb_source_column# similar to '%\-\- #ACTIVATE#IF#USE\_ES\_(EQU\_0|EQU\_1|EQU\_2|NEQ\_0|NEQ\_1|NEQ\_2)#END#%' escape '\' }'
     ;


    v_proc_filter = replace(v_base_filter, '#rdb_source_column#', 'p.rdb$procedure_source');
    v_func_filter = replace(v_base_filter, '#rdb_source_column#', 'f.rdb$function_source');
    v_trig_filter = replace(v_base_filter, '#rdb_source_column#', 't.rdb$trigger_source');

    v_unit_query =
           'select ''p'' as obj_type, p.rdb$procedure_name obj_name ' || v_lf
        || 'from rdb$procedures p ' || v_lf
        || 'where ' || v_proc_filter || v_lf
        || 'UNION ALL ' || v_lf
        || 'select ''f'', f.rdb$function_name ' || v_lf
        || 'from rdb$functions f '
        || 'where ' || v_func_filter || v_lf
        || 'UNION ALL ' || v_lf
        || 'select ''t'',t.rdb$trigger_name ' || v_lf
        || 'from rdb$triggers t '
        || 'where ' || v_trig_filter
    ;

    -- 4debug:
    "-- blob_id" = '/*** check query: ' || v_lf || v_unit_query || v_lf || '***/';
    suspend;

    "-- blob_id" = 'set echo on;' || v_lf;
    suspend;
    

    for
        execute statement ( v_unit_query )
        into v_obj_type, v_obj_name
    do begin

        -- 4debug:
        "-- blob_id" = '-- unit to change: ' || v_obj_name;
        suspend;

        -- get body of unit before change:
        v_body_query = 
            'select ' || decode(  v_obj_type
                                 ,'p', 'p.rdb$procedure_source'
                                 ,'f', 'f.rdb$function_source'
                                 ,'t', 't.rdb$trigger_source'
                               )
            || v_lf || ' from ' || decode(  v_obj_type
                                           ,'p', 'rdb$procedures p'
                                           ,'f', 'rdb$functions f'
                                           ,'t', 'rdb$triggers t'
                                         )
            || v_lf || ' where ' || decode(  v_obj_type
                                            ,'p', 'p.rdb$procedure_name'
                                            ,'f', 'f.rdb$function_name'
                                            ,'t', 't.rdb$trigger_name'
                                          )
                                 || ' = :v_unit'
        ;
        execute statement( v_body_query ) ( v_unit := v_obj_name ) into v_orig_body;

        -- Remove all occurences of chr13:
        v_orig_body = replace(v_orig_body, ascii_char(13) || ascii_char(10), ascii_char(10));
        v_orig_body = replace(v_orig_body, ascii_char(13), '');

        -- 4debug:
        "-- blob_id" = '-- Initial body length: ' || char_length(v_orig_body) ;
        suspend;

        v_repl_body = '';
        for
            select p.item as body_line
            from sys_list_to_rows(:v_orig_body, :v_lf) p -- this SP split input arg#1 (that is expected as BLOB subtype 1) onto lines;
            as cursor cb
        do begin
           
            n_pad = char_length(cb.body_line);
            n_indent = n_pad - char_length(trim(leading from cb.body_line));
            v_body_line = '';

            if ( cb.body_line containing '-- #SUBS#CONNSTR#END#' ) then
                -- ALWAYS revert to commented line because host/port/usr/pwd/tmp_user_pswd can change at any time!
                v_body_line = lpad('', n_indent, ' ') || v_orig_subst_for_eds;

            if ( v_body_line containing '-- #SUBS#CONNSTR#BEG#' ) then -- We have to replace parameters in 'ON EXTERNAL' clause (or disable it and revert to initial)
                begin
                    if (v_use_es = 2) then
                        begin
                            -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password '#pwd' role current_role -- #SUBS#CONNSTR#END#
                            v_body_line = replace(v_body_line, '-- #SUBS#CONNSTR#BEG# ', '');
                            v_body_line = replace(replace(v_body_line, '#host', v_host), '#port', v_port);
                            v_body_line = replace(v_body_line, '#pwd', 'iif(current_user=''' || v_usr || ''', ''' || v_pwd || ''', ''' || v_tmp_user_pswd || ''' )');
                            v_repl_body = v_repl_body || v_body_line || v_lf;
                        end
                    else
                        v_repl_body = v_repl_body || lpad('', n_indent, ' ') || v_orig_subst_for_eds || v_lf;
                end

            else if ( cb.body_line similar to '%\-\-[[:SPACE:]]*#SUBST#EXTPOOL#SUPPORT\_(0|1)#END#%' escape '\' ) then
                begin
                    v_body_line = cb.body_line;
                    if ( v_use_es = 2) then
                        -- 1. if current FB instance DOES support Ext Conn Pool then:
                        --    1.1 if line contains '-- #SUBST#EXTPOOL#SUPPORT_1#END#' then uncomment it by removing leading '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#'
                        --    1.2 if line contains '-- #SUBST#EXTPOOL#SUPPORT_0#END#' then COMMENT OUT it (if needed) by adding '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#'
                        -- 2. if current FB instance does NOT support Ext Conn Pool then:
                        --    2.1 if line contains '-- #SUBST#EXTPOOL#SUPPORT_1#END#' then COMMENT OUT it (if needed) by adding ''-- #SUBST#EXTPOOL#SUPPORT_1#BEG#'
                        --    2.2 if line contains '-- #SUBST#EXTPOOL#SUPPORT_0#END#' then uncomment it by removing leading '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#'
                        begin
                            if ( v_conn_pool_support = 1 ) then
                                begin
                                    if ( cb.body_line containing '-- #SUBST#EXTPOOL#SUPPORT_1#END#' ) then
                                        -- ### 1.1 ###
                                        v_body_line = replace(cb.body_line, '-- #SUBST#EXTPOOL#SUPPORT_1#BEG# ', '');
                                    else if ( cb.body_line containing '-- #SUBST#EXTPOOL#SUPPORT_0#END#' and cb.body_line not containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#' ) then
                                        -- ### 1.2 ###
                                        v_body_line = lpad('', n_indent, ' ') || '-- #SUBST#EXTPOOL#SUPPORT_0#BEG ' || trim(cb.body_line);
                                end
                            else -- v_conn_pool_support = 0
                                begin
                                    if ( cb.body_line containing '-- #SUBST#EXTPOOL#SUPPORT_1#END#' and cb.body_line not containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#' ) then
                                        -- ### 2.1 ###
                                        v_body_line = lpad('', n_indent, ' ') || '-- #SUBST#EXTPOOL#SUPPORT_1#BEG# ' || trim(cb.body_line);
                                    else if ( cb.body_line containing '-- #SUBST#EXTPOOL#SUPPORT_0#END#' ) then
                                        -- ### 2.2 ###
                                        v_body_line = replace(cb.body_line, '-- #SUBST#EXTPOOL#SUPPORT_0#BEG# ', '');
                                end
                        end
                    else -- v_use_es <> 2
                        -- This code must not be executed, regardless of Ext Pool Support
                        begin
                            if ( cb.body_line containing '-- #SUBST#EXTPOOL#SUPPORT_0#END#' and cb.body_line not containing '-- #SUBST#EXTPOOL#SUPPORT_0#BEG#' ) then
                                v_body_line = lpad('', n_indent, ' ') || '-- #SUBST#EXTPOOL#SUPPORT_0#BEG# ' || trim(cb.body_line);
                            if ( cb.body_line containing '-- #SUBST#EXTPOOL#SUPPORT_1#END#' and cb.body_line not containing '-- #SUBST#EXTPOOL#SUPPORT_1#BEG#' ) then
                                v_body_line = lpad('', n_indent, ' ') || '-- #SUBST#EXTPOOL#SUPPORT_1#BEG# ' || trim(cb.body_line);
                        end

                    v_repl_body = v_repl_body || v_body_line || v_lf;

                end

            else if ( cb.body_line similar to '%\-\-[[:SPACE:]]*#SUBST#RESETTING\_(0|1)#END#%' escape '\' ) then
                -- 12.12.2020: this is line from DB-level trigger. We have to:
                -- 1) if use_es = 2:
                --     1.1) if current FB instance does NOT support 'RESETTING' then UNcomment line by removing '--#SUBST#RESETTING_0#BEG' and activate apropriate PSQL code
                --     1,2) otherwise we have to COMMENT OUT this line because another code will be executed (with reference to 'RESETTING' variable)
                --     1.3) if current FB instance DOES support 'RESETTING' system var. then UNcomment line by removing '--#SUBST#RESETTING_1#BEG' ;
                --     1.4) otherwise we have to COMMENT OUT this line because another code will be executed (without reference to 'RESETTING' variable)
                -- 2) if use_es <> 2: comment out this line if it does not starts with '--#SUBST#RESETTING_0#BEG' or '--#SUBST#RESETTING_1#BEG'
                begin
                    v_body_line = cb.body_line;
                    if ( v_use_es = 2) then
                        begin
                            if ( cb.body_line containing '--#SUBST#RESETTING_0#END#' ) then
                            begin
                                if ( v_resetting_support = 0 ) then
                                    -- ### 1.1 ###
                                    -- Current FB instance does NOT support RESETTING variable, we have to UNCOMMENT line.
                                    -- Example:
                                    -- --#SUBST#RESETTING_0#BEG# <PSQL> ; --#SUBST#RESETTING_0#END#
                                    -- will be without starting comment, i.e.:
                                    -- <PSQL> ; --#SUBST#RESETTING_0#END#
                                    -- (where "<PSQL>" is some code WITHOUT reference to 'RESETTING' variable)
                                    v_body_line = replace(cb.body_line, '--#SUBST#RESETTING_0#BEG# ', '');
                                else
                                    if (cb.body_line not containing '--#SUBST#RESETTING_0#BEG#') then
                                        -- ### 1.2 ###
                                        -- Current FB instance does support RESETTING variable, we must COMMENT OUT this line
                                        -- because another code will be executed (with reference to 'RESETTING' variable)
                                        v_body_line = lpad('', n_indent, ' ') || '--#SUBST#RESETTING_0#BEG# ' || trim(cb.body_line);
                                    else
                                        v_body_line = cb.body_line;
                            end

                            if ( cb.body_line containing '--#SUBST#RESETTING_1#END#' ) then
                            begin
                                if ( v_resetting_support = 1 ) then
                                    -- ### 1.3 ###
                                    -- Current FB instance does support RESETTING variable, we must UNCOMMENT this line:
                                    v_body_line = replace(cb.body_line, '--#SUBST#RESETTING_1#BEG# ', '');
                                else
                                    -- ### 1.4 ###
                                    -- Current FB instance does NOT support RESETTING variable, we have to COMMENT OUT line
                                    -- by adding single-line comment '--#SUBST#RESETTING_1#BEG#' (if needed)
                                    -- because another code will be executed (without reference to 'RESETTING' variable).
                                    if ( cb.body_line not containing '--#SUBST#RESETTING_1#BEG#' ) then
                                        v_body_line = lpad('', n_indent, ' ') || '--#SUBST#RESETTING_1#BEG# ' || trim(cb.body_line);
                                    else
                                        v_body_line = cb.body_line;

                                    -- Example:
                                    -- <PSQL> ; --#SUBST#RESETTING_1#END#
                                    -- will be commented by starting comment, i.e.:
                                    -- --#SUBST#RESETTING_1#BEG# <PSQL> ; --#SUBST#RESETTING_1#END#
                                    -- (where "<PSQL>" is some code which refers to 'RESETTING' variable)

                            end
                            --if (v_body_line > '') then
                            --    v_repl_body = v_repl_body || v_body_line || v_lf;

                        end
                    else -- use_es <> 2
                        begin
                            -- comment out any line containing '#SUBST#RESETTING_0#END' or '#SUBST#RESETTING_1#END'
                            -- if it does not start with '--#SUBST#RESETTING_0#BEG' or '--#SUBST#RESETTING_1#BEG'
                            if ( cb.body_line containing '--#SUBST#RESETTING_0#END#' and cb.body_line NOT containing '--#SUBST#RESETTING_0#BEG#' ) then
                                v_body_line = lpad('', n_indent, ' ') || '--#SUBST#RESETTING_0#BEG# ' || trim(cb.body_line);
                            else if ( cb.body_line containing '--#SUBST#RESETTING_1#END#' and cb.body_line NOT containing '--#SUBST#RESETTING_1#BEG#') then
                                v_body_line = lpad('', n_indent, ' ') || '--#SUBST#RESETTING_1#BEG# ' || trim(cb.body_line);

                            --if (v_body_line > '') then
                            --    v_repl_body = v_repl_body || v_body_line || v_lf;
                        
                        end
                
                    v_repl_body = v_repl_body || v_body_line || v_lf;

                end

            else if (cb.body_line NOT containing 'ACHTUNG_EDS_READ_ME') then

                begin
                    -- if ( cb.body_line containing '#EDS#TAG#' ) then
                    if ( cb.body_line like '%#EDS#TAG#%' or cb.body_line like '%#EDS#OFF#%' or cb.body_line like '%#EDS#ON#%') then
                        begin
                            if (v_use_es = 2) then
                                begin
                                    v_body_line = replace(cb.body_line, '#EDS#TAG#', '#EDS#ON#');
                                    v_body_line = replace(v_body_line,  '#EDS#OFF#', '#EDS#ON#');
                                end
                            else if (v_use_es = 1) then
                                begin
                                    v_body_line = replace(cb.body_line, '#EDS#TAG#', '#EDS#OFF#');
                                    v_body_line = replace(v_body_line,  '#EDS#ON#',  '#EDS#OFF#');
                                end
                            else -- v_use_es = 0 ==> old way, use static PSQL code
                                begin
                                    v_body_line = replace(cb.body_line, '#EDS#ON#',  '#EDS#TAG#');
                                    v_body_line = replace(v_body_line,  '#EDS#OFF#', '#EDS#TAG#');
                                end

                            v_repl_body = v_repl_body || v_body_line || v_lf;
                        end
                    else
                        begin
                            --      ==============================================================================|
                            --      When:                                |               Then if:                 |
                            --                                           |                                        |
                            --      trim(cb.body_line) starting with:    | use_es=0:     use_es=1:     use_es=2:  |
                            --      ==============================================================================|
                            --   1  '/* #ACTIVATE#IF#USE_ES_EQU_0#BEG#'  | uncomment     do nothing    do nothing |
                            --   2  '-- #ACTIVATE#IF#USE_ES_EQU_0#BEG#'  | do nothing    comment out   comment out|
                            --   3  '/* #ACTIVATE#IF#USE_ES_EQU_1#BEG#'  | do nothing    uncomment     do nothing |
                            --   4  '-- #ACTIVATE#IF#USE_ES_EQU_1#BEG#'  | comment out   do nothing    comment out|
                            --   5  '/* #ACTIVATE#IF#USE_ES_EQU_2#BEG#'  | do nothing    do nothing    uncomment  |
                            --   6  '-- #ACTIVATE#IF#USE_ES_EQU_2#BEG#'  | comment out   comment out   do nothing |
                            --   7  '/* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#'  | do nothing    uncomment     uncomment  |
                            --   8  '-- #ACTIVATE#IF#USE_ES_NEQ_0#BEG#'  | comment out   do nothing    do nothing |
                            --   9  '/* #ACTIVATE#IF#USE_ES_NEQ_1#BEG#'  | uncomment     do nothing    uncomment  |
                            --  10  '-- #ACTIVATE#IF#USE_ES_NEQ_1#BEG#'  | do nothing    comment out   do nothing |
                            --  11  '/* #ACTIVATE#IF#USE_ES_NEQ_2#BEG#'  | uncomment     uncomment     do nothing |
                            --  12  '-- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#'  | do nothing    do nothing    comment out|
                            --      ==============================================================================


                            if ( cb.body_line like '%#ACTIVATE#IF#USE_ES%#BEG#') then
                                begin
                                    v_body_line = cb.body_line;

                                    -- ####### 1 #######
                                    -- '/* #ACTIVATE#IF#USE_ES_EQU_0#BEG#'    uncomment     do nothing    do nothing
                                    if ( trim(leading from cb.body_line) starting with '/* #ACTIVATE#IF#USE_ES_EQU_0#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then -- we have to UNCOMMENT multi-line block that follows after this line
                                                v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_EQU_0#BEG#', n_pad, ' ');
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=2 ) then
                                                begin
                                                    -- do nothing
                                                end
                                        end
                                    
                                    -- ####### 2 #######
                                    -- '-- #ACTIVATE#IF#USE_ES_EQU_0#BEG#'    do nothing    comment out   comment out
                                    if ( trim(leading from cb.body_line) starting with '-- #ACTIVATE#IF#USE_ES_EQU_0#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=1 ) then
                                                -- comment out
                                                v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_EQU_0#BEG#', n_pad, ' ');
                                            else if( v_use_es=2 ) then
                                                -- comment out
                                                v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_EQU_0#BEG#', n_pad, ' ');
                                        end

                                    -- ####### 3 ####### 
                                    -- '/* #ACTIVATE#IF#USE_ES_EQU_1#BEG#'    do nothing    uncomment     do nothing
                                    if ( trim(leading from cb.body_line) starting with '/* #ACTIVATE#IF#USE_ES_EQU_1#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                begin
                                                end
                                            else if( v_use_es=1 ) then
                                                -- uncomment
                                                v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_EQU_1#BEG#', n_pad, ' ');
                                            else if( v_use_es=2 ) then
                                                begin
                                                end
                                        end

                                    -- ####### 4 #######
                                    -- '-- #ACTIVATE#IF#USE_ES_EQU_1#BEG#'    comment out   do nothing    comment out 
                                    if ( trim(leading from cb.body_line) starting with '-- #ACTIVATE#IF#USE_ES_EQU_1#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                -- comment out
                                                v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_EQU_1#BEG#', n_pad, ' ');
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=2 ) then
                                                -- comment out
                                                v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_EQU_1#BEG#', n_pad, ' ');
                                        end
                                    -- ####### 5 ####### 
                                    -- '/* #ACTIVATE#IF#USE_ES_EQU_2#BEG#'    do nothing    do nothing    uncomment
                                    if ( trim(leading from cb.body_line) starting with '/* #ACTIVATE#IF#USE_ES_EQU_2#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=2 ) then
                                                begin
                                                    -- uncomment
                                                    v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_EQU_2#BEG#', n_pad, ' ');
                                                end
                                        end

                                    -- ####### 6 ####### 
                                    -- '-- #ACTIVATE#IF#USE_ES_EQU_2#BEG#'    comment out   comment out   do nothing
                                    if ( trim(leading from cb.body_line) starting with '-- #ACTIVATE#IF#USE_ES_EQU_2#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                -- comment out
                                                v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_EQU_2#BEG#', n_pad, ' ');
                                            else if( v_use_es=1 ) then
                                                -- comment out
                                                v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_EQU_2#BEG#', n_pad, ' ');
                                            else if( v_use_es=2 ) then
                                                begin
                                                    -- do nothing
                                                end
                                        end


                                    -- ####### 7 ####### 
                                    -- '/* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#'    do nothing    uncomment     uncomment
                                    if ( trim(leading from cb.body_line) starting with '/* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=1 ) then
                                                -- uncomment
                                                v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_NEQ_0#BEG#', n_pad, ' ');
                                             else if( v_use_es=2 ) then
                                                -- uncomment
                                                v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_NEQ_0#BEG#', n_pad, ' ');
                                        end


                                    -- ####### 8 ####### 
                                    -- '-- #ACTIVATE#IF#USE_ES_NEQ_0#BEG#'    comment out   do nothing    do nothing
                                    if ( trim(leading from cb.body_line) starting with '-- #ACTIVATE#IF#USE_ES_NEQ_0#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                -- comment out
                                                v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#', n_pad, ' ');
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=2 ) then
                                                begin
                                                    -- do nothing
                                                end
                                        end


                                    -- ####### 9 ####### 
                                    -- '/* #ACTIVATE#IF#USE_ES_NEQ_1#BEG#'    uncomment     do nothing    uncomment
                                    if ( trim(leading from cb.body_line) starting with '/* #ACTIVATE#IF#USE_ES_NEQ_1#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                -- uncomment
                                                v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_NEQ_1#BEG#', n_pad, ' ');
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=2 ) then
                                                -- uncomment
                                                v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_NEQ_1#BEG#', n_pad, ' ');
                                        end


                                    -- ####### 10 ####### 
                                    -- '-- #ACTIVATE#IF#USE_ES_NEQ_1#BEG#'    do nothing    comment out   do nothing
                                    if ( trim(leading from cb.body_line) starting with '-- #ACTIVATE#IF#USE_ES_NEQ_1#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- comment out
                                                    v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_NEQ_1#BEG#', n_pad, ' ');
                                                end
                                            else if( v_use_es=2 ) then
                                                begin
                                                    -- do nothing
                                                end
                                        end


                                    -- ####### 11 ####### 
                                    -- '/* #ACTIVATE#IF#USE_ES_NEQ_2#BEG#'    uncomment     uncomment     do nothing
                                    if ( trim(leading from cb.body_line) starting with '/* #ACTIVATE#IF#USE_ES_NEQ_2#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                begin
                                                    -- uncomment
                                                    v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#', n_pad, ' ');
                                                end
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- uncomment
                                                    v_body_line = lpad( '-- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#', n_pad, ' ');
                                                end
                                            else if( v_use_es=2 ) then
                                                begin
                                                    -- do nothing
                                                end
                                        end


                                    -- ####### 12 ####### 
                                    -- '-- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#'    do nothing    do nothing    comment out
                                    if ( trim(leading from cb.body_line) starting with '-- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#' ) then
                                        begin
                                            if ( v_use_es = 0 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=1 ) then
                                                begin
                                                    -- do nothing
                                                end
                                            else if( v_use_es=2 ) then
                                                begin
                                                    -- comment out
                                                    v_body_line = lpad( '/* #ACTIVATE#IF#USE_ES_NEQ_2#BEG#', n_pad, ' ');
                                                end
                                        end

                                    -- ############ finish of combinations ##########
                                    v_repl_body = v_repl_body || v_body_line || v_lf;

                                end
                            else
                                begin
                                    if ( NOT (v_obj_type = 't' and upper(cb.body_line) = upper('as') and v_repl_body = '') ) then
                                        -- ::: NB ::: trigger body includes "AS" at first line! We have to SKIP it now
                                        -- because of adding special "achtung"-comments , see below.
                                        v_repl_body = v_repl_body || cb.body_line || v_lf;
                                end
                        end
                end -- cb.body_line NOT containing 'ACHTUNG_EDS_READ_ME'

        end

        -- 4debug:
        "-- blob_id" = '-- Changed body length: ' || char_length(v_repl_body) ;
        suspend;

        "-- blob_id" = 'set term ^;' || v_lf;
        for
            execute statement
            (
                'select src from ' 
                || decode(  v_obj_type
                           ,'p', 'SYS_GET_PROC_DDL( :a_obj_name, -1, 0 )'
                           ,'f', 'SYS_GET_FUNC_DDL( :a_obj_name, -1, 0 )'
                           ,'t', 'SYS_GET_TRIG_DDL( :a_obj_name, -1, 0 )'
                         )
                || ' where src is not null'
            ) ( a_obj_name := v_obj_name )

            -- sys_get_proc_ddl and sys_get_func_ddl:
            --     param #1: name of proc/func
            --     param #2:  -1 = only SP name and its parameters, 0 = name+parameters+empty body, 1 = full text
            --     param #3:   1 = include 'set term ^;' clause; 0 = do not include 'set term'
            -- sys_get_trig_ddl:
            --     param #1: name of trigger
            --     param #2:   0 = only trigger name and its type, 1 = full text
            --     param #3:   1 = include 'set term ^;' clause; 0 = do not include 'set term'
            -- ::: NB ::: 
            -- Body of procedures and functions does NOT include 'as' clause and starts with 1st declare variable sentense.
            -- Body of trigger DOES include 'as' followed by declaration of variables
            into v_unit_header
        do begin
            "-- blob_id" = "-- blob_id" || v_lf || v_unit_header || v_lf;
        end
    
    
        if ( 1=1 or v_obj_type in ('p','f') ) then
        begin
            "-- blob_id" = "-- blob_id" || 'declare "-- ACHTUNG_EDS_READ_ME__1" varchar(255) = ''### GENERATED AUTO, BASED ON ' || trim(v_obj_name) ||'. DO NOT EDIT ###'';' || v_lf;
            if (v_use_es = 0) then
                "-- blob_id" = "-- blob_id" || q'{declare "-- ACHTUNG_EDS_READ_ME__2" varchar(255) = '### STATIC code will be performed. For use ES[/EDS], change config parameter ''use_es'' to 1 for run ES w/o EDS, or 2 for run ES with EDS. ###';}' || v_lf
                ;
            if (v_use_es = 1) then
                "-- blob_id" = "-- blob_id" || q'{declare "-- ACHTUNG_EDS_READ_ME__2" varchar(255) = '### Part of code uses EXECUTE STATEMENT mechanism. Change config parameter ''use_es'' to 0 for disabling it, or 2 for run ES with EDS. ###';}' || v_lf
                ;
            if (v_use_es = 2) then
                "-- blob_id" = "-- blob_id" || q'{declare "-- ACHTUNG_EDS_READ_ME__2" varchar(255) = '### Part of code uses ES/EDS mechanism. Change config parameter ''use_es'' to 1 for run ES w/o EDS, or 0 for disabling ES at all. ###';}' || v_lf
                ;
        end


        "-- blob_id" = "-- blob_id" || v_repl_body;
        "-- blob_id" = "-- blob_id" || v_lf;
        "-- blob_id" = "-- blob_id" || v_lf || '^';
        "-- blob_id" = "-- blob_id" || v_lf || 'set term ;^';

        suspend;

    end

    -- ??? -->> ??? for what ?? >>> suspend;
end
^
set term ;^
commit;

select
q'{
set echo off;
set list on;
select 'oltp_adjust_eds_calls.sql finish at ' || current_timestamp as msg from rdb$database;
}' as "--TMP$SQL$CODE"
from rdb$database
;
