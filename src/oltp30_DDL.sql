-- ##############################
-- Begin of script oltp30_DDL.sql
-- ##############################
-- ::: nb-1 ::: Required FB version: 3.0 and above.
-- ::: nb-2 ::: Use '-nod' switch when run this script from isql
-- Pattern for search queries to [v_]qdistr using regexp (in IBE):
-- (from|((left(( ){1,}outer( ){1,})|full(( ){1,}outer( ){1,})|inner)( ){0,1}){0,1}join)( ){1,}(v_){0,1}qdistr

set bail on;
set autoddl off;
set list on;
select 'oltp30_DDL.sql start at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

set term ^;
execute block as
begin
  begin
    execute statement 'recreate exception ex_exclusive_required ''At least one concurrent connection detected.''';
    when any do begin end
  end
  begin
    execute statement 'recreate exception ex_not_suitable_fb_version ''This script requires at least Firebird 3.x version''';
    when any do begin end
  end
end
^
set term ;^
commit;

set list on;
set term ^;
execute block returns(engine_version varchar(30)) as
begin
    engine_version = rdb$get_context('SYSTEM','ENGINE_VERSION');
    if (  engine_version starting with '2.' ) then
    begin
        suspend;
        exception ex_not_suitable_fb_version;
    end

    -- NB. From doc/README.monitoring_tables:
    -- columns MON$REMOTE_PID and MON$REMOTE_PROCESS contains non-NULL values
    -- only if the client library has version 2.1 or higher
    -- column MON$REMOTE_PROCESS can contain a non-pathname value
    -- if an application has specified a custom process name via DPB
    if ( exists( select * from mon$attachments a 
                 where a.mon$attachment_id<>current_connection 
                 and a.mon$remote_protocol is not null
                ) 
       ) then
    begin
        exception ex_exclusive_required;
    end
end
^
set term ;^
commit;
set list off;

-- ############################################################################
-- #########################    C L E A N I N G   #############################
-- ############################################################################

-- 1. Separate EB for devastation views with preserving their column names
-- (otherwise can get ISC error 336397288. invalid request BLR at offset 2. context not defined (BLR error).)
-- see letter to dimitr, 29.03.2014 22:43
set term ^;
execute block as
  declare stt varchar(8190);
  declare ref_name varchar(31);
  declare tab_name varchar(31);
  declare view_ddl varchar(8190);
  declare c_view cursor for (
    with
    a as(
      select rf.rdb$relation_name view_name, rf.rdb$field_position fld_pos
            ,iif( trim(rf.rdb$field_name) = upper(trim(rf.rdb$field_name)), trim(rf.rdb$field_name), '"' || trim(rf.rdb$field_name) || '"') as fld_name
      from rdb$relation_fields rf
      join rdb$relations rr on rf.rdb$relation_name=rr.rdb$relation_name
      where
      coalesce(rf.rdb$system_flag,0)=0 and coalesce(rr.rdb$system_flag,0)=0 and rr.rdb$relation_type=1
    )
    select view_name,
           cast( 'create or alter view '||trim(view_name)||' as select '
                 ||list( fld_pos||' '|| fld_name )
                 ||' from rdb$database' as varchar(8190)
               ) view_ddl
    from a
    group by view_name
  );
begin
  open c_view;
  while (1=1) do
  begin
    fetch c_view into tab_name, stt;
    if (row_count = 0) then leave;
    execute statement (:stt);
  end
  close c_view;
end^
set term ;^
commit;

-------------------------------------------------------------------------------

-- 2. Removing all objects from database is they exists:
set term ^;
execute block as
  declare stt varchar(512);
  declare ref_name varchar(31);
  declare tab_name varchar(31);
  --declare view_ddl varchar(8190);

  declare c_trig cursor for
    (select rt.rdb$trigger_name
       from rdb$triggers rt
       where coalesce(rt.rdb$system_flag,0)=0
    );

  declare c_view cursor for
    (select rr.rdb$relation_name
       from rdb$relations rr
      where rr.rdb$relation_type=1 and coalesce(rr.rdb$system_flag,0)=0
    );
  declare c_func cursor for
    (select rf.rdb$function_name
       from rdb$functions rf
      where coalesce(rf.rdb$system_flag,0)=0
    );
  declare c_proc cursor for
    (select rp.rdb$procedure_name
       from rdb$procedures rp
       where coalesce(rp.rdb$system_flag,0)=0
    );
  
  declare c_excp cursor for
    (select re.rdb$exception_name
       from rdb$exceptions re
       where coalesce(re.rdb$system_flag,0)=0
    );
  
  declare c_fk cursor for
    (select rc.rdb$constraint_name, rc.rdb$relation_name
       from rdb$relation_constraints rc
      where rc.rdb$constraint_type ='FOREIGN KEY'
    );
  
  declare c_tabs cursor for -- fixed tables and GTTs
    (select rr.rdb$relation_name
       from rdb$relations rr
      where rr.rdb$relation_type in(0,4,5) and coalesce(rr.rdb$system_flag,0)=0
      -- todo: what about external tables ?
    );
  
  declare c_doms cursor for -- domains
    (select rf.rdb$field_name
      from rdb$fields rf
     where coalesce(rf.rdb$system_flag,0)=0
           and rf.rdb$field_name not starting with 'RDB$'
    );
  
  declare c_coll cursor for -- collations
    (select rc.rdb$collation_name
       from rdb$collations rc
      where coalesce(rc.rdb$system_flag,0)=0
    );
  declare c_gens cursor for -- generators
    (select rg.rdb$generator_name
      from rdb$generators rg
     where coalesce(rg.rdb$system_flag,0)=0
    );
  declare c_role cursor for -- roles
    (select rr.rdb$role_name
      from rdb$roles rr
     where coalesce(rr.rdb$system_flag,0)=0
    );

begin

  -- ################   D R O P   T R I G G E R S  ################
  open c_trig;
  while (1=1) do
  begin
    fetch c_trig into stt;
    if (row_count = 0) then leave;
    stt = 'drop trigger '||stt;
    execute statement (:stt);
  end
  close c_trig;

  -- #########    Z A P   F U N C S    &    P R O C S  ##########
  -- not needed views has been already "zapped", see above separate EB

  open c_func;
  while (1=1) do
  begin
    fetch c_func into stt;
    if (row_count = 0) then leave;
    stt = 'create or alter function '||stt||' returns int as begin return 1; end';
    execute statement (:stt);
  end
  close c_func;

  open c_proc;
  while (1=1) do
  begin
    fetch c_proc into stt;
    if (row_count = 0) then leave;
    stt = 'create or alter procedure '||stt||' as begin end';
    execute statement (:stt);
  end
  close c_proc;

  -- ######################   D R O P    O B J E C T S   ######################

  open c_view;----------------------  d r o p   v i e w s  ---------------------
  while (1=1) do
  begin
    fetch c_view into stt;
    if (row_count = 0) then leave;
    stt = 'drop view '||stt;
    execute statement (:stt);
  end
  close c_view;

  open c_func; --------------------  d r o p   f u c t i o n s  ----------------
  while (1=1) do
  begin
    fetch c_func into stt;
    if (row_count = 0) then leave;
    stt = 'drop function '||stt;
    execute statement (:stt);
  end
  close c_func;

  open c_proc; -----------------  d r o p   p r o c e d u r e s  ---------------
  while (1=1) do
  begin
    fetch c_proc into stt;
    if (row_count = 0) then leave;
    stt = 'drop procedure '||stt;
    execute statement (:stt);
  end
  close c_proc;

  open c_excp; -----------------  d r o p   e x c e p t i o n s  ---------------
  while (1=1) do
  begin
    fetch c_excp into stt;
    if (row_count = 0) then leave;
    stt = 'drop exception '||stt;
    execute statement (:stt);
  end
  close c_excp;

  open c_fk; -----------  d r o p    r e f.   c o n s t r a i n t s ------------
  while (1=1) do
  begin
    fetch c_fk into ref_name, tab_name;
    if (row_count = 0) then leave;
    stt = 'alter table '||tab_name||' drop constraint '||ref_name;
    execute statement (:stt);
  end
  close c_fk;

  open c_tabs; -----------  d r o p    t a b l e s  ------------
  while (1=1) do
  begin
    fetch c_tabs into stt;
    if (row_count = 0) then leave;
    stt = 'drop table '||stt;
    execute statement (:stt);
  end
  close c_tabs;

  open c_doms; -------------------  d r o p    d o m a i n s -------------------
  while (1=1) do
  begin
    fetch c_doms into stt;
    if (row_count = 0) then leave;
    stt = 'drop domain '||stt;
    execute statement (:stt);
  end
  close c_doms;

  open c_coll; ---------------  d r o p    c o l l a t i o n s -----------------
  while (1=1) do
  begin
    fetch c_coll into stt;
    if (row_count = 0) then leave;
    stt = 'drop collation '||stt;
    execute statement (:stt);
  end
  close c_coll;

  open c_gens; -----------------  d r o p    s e q u e n c e s -----------------
  while (1=1) do
  begin
    fetch c_gens into stt;
    if (row_count = 0) then leave;
    stt = 'drop sequence '||stt;
    execute statement (:stt);
  end
  close c_gens;

  open c_role; --------------------  d r o p    r o l e s ----------------------
  while (1=1) do
  begin
    fetch c_role into stt;
    if (row_count = 0) then leave;
    stt = 'drop role '||stt;
    execute statement (:stt);
  end
  close c_role;

end
^
set term ;^
commit;


-------------------------------------------------------------------------------
-- #########################    C R E A T I N G   #############################
-------------------------------------------------------------------------------

create sequence g_common;
create sequence g_doc_data;
create sequence g_perf_log;
create sequence g_init_pop;
create sequence g_qdistr;
create sequence g_success_counter; -- used in .bat / .sh for displaying estimated performance value
create sequence g_stop_test; -- serves as signal to self-stop every ISQL attachment its job
commit;

-- create collations:
create collation name_coll for utf8 from unicode case insensitive;
create collation nums_coll for utf8 from unicode case insensitive 'NUMERIC-SORT=1';
commit;

-- create exceptions
recreate exception ex_context_var_not_found 'required context variable(s): @1 - not found or has invalid value';
recreate exception ex_bad_working_mode_value 'db-level trigger TRG_CONNECT: no found rows for settings.working_mode=''@1'', correct it!';
recreate exception ex_bad_argument 'argument @1 passed to unit @2 is invalid';

recreate exception ex_test_cancellation 'test_has_been_cancelled (either by adding text into external text file ''stoptest'' or by changing value of sequence ''g_stop_test'' to non-zero)';

recreate exception ex_record_not_found 'required record not found, datasource: @1, key: @2';
recreate exception ex_cant_lock_semaphore_record 'can`t lock record in SEMAPHORES table for serialization';
recreate exception ex_cant_lock_row_for_qdistr 'can`t lock any row in `qdistr`: optype=@1, ware_id=@2, qty_required=@3';
recreate exception ex_cant_find_row_for_qdistr 'no rows found for FIFO-distribution: optype=@1, rows in tmp$shopping_cart=@2';

recreate exception ex_no_doc_found_for_handling 'no document found for handling in datasource = ''@1'' with id=@2';
recreate exception ex_no_rows_in_shopping_cart 'shopping_cart is empty, check source ''@1''';

recreate exception ex_not_all_storned_rows_removed 'at least one storned row found in ''qstorned'' table, doc=@1'; -- 4debug, 27.06.2014
recreate exception ex_neg_remainders_encountered 'at least one neg. remainder, ware_id: @1, info: @2'; -- 4debug, 27.06.2014
recreate exception ex_mism_doc_data_qd_qs 'at least one mismatch btw doc_data.id=@1 and qdistr+qstorned: qty=@2, qd_cnt=@3, qs_cnt=@4'; -- 4debug, 07.08.2014
recreate exception ex_orphans_qd_qs_found 'at least one row found for DELETED doc id=@1, snd_id=@2: @3.id=@4';

recreate exception ex_can_not_lock_any_record 'no records could be locked in datasource = ''@1'' with ID >= @2.';

-- @1 is math sign: '>=' or '<='
-- @2 = random_selected_value
-- @3 = data source
--  @4 = min; @5 = max:
-- recreate exception ex_can_not_select_random_id 'no id @1 @2 in @3 found within scope @4 ... @5';
recreate exception ex_can_not_select_random_id 'can`t choose random ID.';

-- 09.12.2020
-- @1 \ data source
recreate exception ex_eds_random_id_not_found 'no random record found in @1 when use ES/EDS';

recreate exception ex_snapshot_isolation_required 'operation must run only in TIL = SNAPSHOT.';
recreate exception ex_read_committed_isolation_req 'operation must run only in TIL = READ COMMITTED.';
recreate exception ex_nowait_or_timeout_required 'transaction must start in NO WAIT mode or with LOCK_TIMEOUT.';

recreate exception ex_update_operation_forbidden 'update operation not allowed on table @1';
recreate exception ex_delete_operation_forbidden 'delete operation not allowed on table @1 when user-data exists';
recreate exception ex_debug_forbidden_operation 'debug: operation not allowed';

-- 23.11.2020: will be raised when use_es=2 and failed check for equality of worker_id in th "parent" connection and EDS.
-- See temporary .sql that is generated in oltp_isql_run_worker scenario before each ISQL launch.
recreate exception ex_further_work_forbidden 'Incompatible config parameters or test settings. Further operations not allowed.';
commit;


-------------------------------------------------------------------------------

-- create domains
-- ::: NB::: 08.06.2014:
-- not null constraints were taken out due to http://tracker.firebirdsql.org/browse/CORE-4453
create domain dm_dbkey as char(8) character set octets; -- do NOT: not null; -- for variables stored rdb$db_key
create domain dm_ids as smallint; -- IDs for operations and document states (will be assigned explicitly in 'oltp_main_filling.sql' to small values)
create domain dm_idb as bigint; -- not null; -- all IDs

create domain dm_ctxns as varchar(16) character set utf8 check( value in ('','USER_SESSION','USER_TRANSACTION', 'SYSTEM'));
create domain dm_ctxnv as varchar(80) character set none; -- m`on$context_variables.m`on$variable_name
create domain dm_dbobj as varchar(31) character set unicode_fss;
create domain dm_setting_value as varchar(160) character set utf8 collate name_coll; -- special for settings.value field (long lists can be there)
create domain dm_mcode as varchar(3) character set utf8 collate name_coll; -- optypes.mcode: mnemonic for operation
create domain dm_name as varchar(80) character set utf8 collate name_coll; -- character set utf8 not null collate name_coll; -- name of wares, contragents et al
create domain dm_nums as varchar(20) character set utf8 collate nums_coll; -- character set utf8 not null collate nums_coll; -- original (manufacturer) numbers
create domain dm_qty as numeric(12,3) check(value>=0); -- not null check(value>=0);
create domain dm_qtz as numeric(12,3) default 0 check(value>=0); -- default 0 not null check(value>=0);
create domain dm_cost as numeric(12,2); -- temply dis 15.05.2014 for DEBUG! uncomment later:   not null check(value>=0);
create domain dm_vals as numeric(12,2); -- numeric(12,2) not null; -- money_turnover_log.costXXXX, can be < 0
create domain dm_aux as double precision;
create domain dm_sign as smallint default 0 check(value in(-1, 1, 0)) ; -- smallint default 0 not null  check(value in(-1, 1, 0)) ;
create domain dm_account_type as varchar(1) character set utf8 NOT null check( value in('1','2','i','o','c','s') ); -- incoming; outgoing; payment

create domain dm_unit varchar(80) character set utf8; -- 'utf8' added 08.01.2017 (see letter from hvlad 06-jan-2017 01:59)
create domain dm_info varchar(255);
create domain dm_stack varchar(512);
-- Remote address to be written into perf_log, mon_log. 
-- Size should be enough to fit IPv6 and port number or even port text mnemona! 
-- See: http://www.networksorcery.com/enp/protocol/ip/ports04000.htm
-- See also reply from dimitr, letter 11-jan-2016 16:04 (subj: "SOS. M`ON$REMOTE_ADDRESS, ...")
-- Fixed in http://sourceforge.net/p/firebird/code/62802 (only port numbers will serve as "suffixes")
create domain dm_ip varchar(255);

-- 16.05.2020: domain for counter fields in mon_log, mon_log_table_stats and mon_cache_memory:
-- rec_inserts, rec_updates, ..., mem_used, mem_alloc: most of them are result of AGGREGATION of two records, with mult=-1 and +1.
-- Result must be always greater than 0. NOTE: any measurement related to mon$ queries can fail - for example, because of insufficient
-- space for temp files ==> one need check in firebird.log: "No free space found in temporary directories /... / No space left on device".
create domain dm_counter as bigint check( value >= 0 );

commit;

-------------------------------------------------------------------------------
--  ****************   A P P L I C A T I O N    T A B L E S   *****************
-------------------------------------------------------------------------------

recreate global temporary table tmp$shopping_cart(
   id dm_idb, --  = ware_id
   snd_id bigint, -- nullable! ref to invoice in case when create reserve doc (one invoice for each reserve; 03.06.2014)
   qty numeric(12,3) not null,
   optype_id bigint,
   snd_optype_id bigint,
   rcv_optype_id bigint,
   storno_sub smallint default 1, -- see table rules_for_qdistr.storno_sub
   qty_bak numeric(12,3) default 0, -- debug
   dup_cnt int default 0,  -- debug
   cost_purchase dm_cost, -- for sp_sp_fill_shopping_cart when create client order
   cost_retail dm_cost,
   constraint tmp_shopcart_unq unique(id, snd_id) using index tmp_shopcart_unq
) on commit delete rows;
commit;
-- 08.01.2015, see sp make_qty_storno, performance benchmark for NL vs MERGE
--create index tmp_shopcart_rcv_op on tmp$shopping_cart(rcv_optype_id);
--commit;

recreate global temporary table tmp$dep_docs(
  base_doc_id dm_idb,
  dependend_doc_id dm_idb,
  dependend_doc_state dm_idb,
  dependend_doc_dbkey dm_dbkey,
  dependend_doc_agent_id dm_idb,
  -- 29.07.2014 (4 misc debug)
  ware_id dm_idb,
  base_doc_qty dm_qty,
  dependend_doc_qty dm_qty,
  constraint tmp_dep_docs_unq unique(base_doc_id, dependend_doc_id) using index tmp_dep_docs_unq
) on commit delete rows;
commit;

recreate global temporary table tmp$result_set(
    snd_id bigint,
    id bigint, 
    storno_sub smallint,
    qdistr_id bigint, 
    qdistr_dbkey dm_dbkey,
    doc_id bigint,
    worker_id smallint,
    optype_id bigint,
    oper varchar(80),
    base_doc_id bigint,
    doc_data_id bigint,
    ware_id bigint,
    qty numeric(12,3),
    cost_purchase numeric(12,2),
    cost_retail numeric(12,2),
    qty_clo numeric(12,3),
    qty_clr numeric(12,3),
    qty_ord numeric(12,3),
    qty_sup numeric(12,3),
    qty_inc numeric(12,3),
    qty_avl numeric(12,3),
    qty_res numeric(12,3),
    qty_out numeric(12,3),
    cost_inc numeric(12,2),
    cost_out numeric(12,2),
    qty_acn numeric(12,3),
    cost_acn numeric(12,2),
    state_id bigint,
    agent_id bigint,
    dts_edit timestamp,
    dts_open timestamp,
    dts_fix timestamp,
    dts_clos timestamp,
    state bigint
) on commit delete rows;
commit;
create index tmp_result_set_ware_doc on tmp$result_set(ware_id, doc_id);
create index tmp_result_set_doc on tmp$result_set(doc_id);
commit;

-- for materializing temp results in some report SPs:
recreate global temporary table tmp$perf_mon(
    unit dm_name,
    cnt_all int,
    cnt_ok int,
    cnt_err int,
    err_prc numeric(6,2),
    ok_min_ms int,
    ok_max_ms int,
    ok_avg_ms int,
    cnt_deadlock int,
    cnt_upd_conf int,
    cnt_lk_confl int,
    cnt_user_exc int,
    cnt_chk_viol int,
    cnt_no_valid int,
    cnt_unq_viol int,
    cnt_fk_viol int,
    cnt_stack_trc int, -- 335544842, 'stack_trace': appears at the TOP of stack in 3.0 SC (strange!)
    cnt_zero_gds int, -- core-4565 (gdscode=0 in when-section! 3.0 SC only)
    cnt_other_exc int,
    first_done timestamp,
    last_done timestamp,
    rollup_level smallint,
    dts_beg timestamp,
    dts_end timestamp
) on commit delete rows;
commit;

recreate global temporary table tmp$idx_recalc(
  tab_name dm_dbobj,
  idx_name dm_dbobj,
  idx_stat_befo double precision,
  idx_stat_afte double precision,
  idx_stat_diff computed by( idx_stat_afte - idx_stat_befo ),
  constraint tmp_idx_recalc_idx_name_unq unique(idx_name)
) on commit preserve rows;
commit;

recreate global temporary table tmp$mon_log( -- used in tmp_random_run.sql
    unit dm_unit
   ,fb_gdscode int
   ,att_id bigint default current_connection
   ,trn_id bigint
   -----------------------------------------
   ,pg_reads bigint
   ,pg_writes bigint
   ,pg_fetches bigint
   ,pg_marks bigint
   ,rec_inserts bigint
   ,rec_updates bigint
   ,rec_deletes bigint
   ,rec_backouts bigint
   ,rec_purges bigint
   ,rec_expunges bigint
   ,rec_seq_reads bigint
   ,rec_idx_reads bigint
   ---------- counters avaliable only in FB 3.0, since rev. 59953 --------------
   ,rec_rpt_reads bigint -- <<< since rev. 60005, 27.08.2014 18:52
   ,bkv_reads bigint -- mon$backversion_reads, since rev. 60012, 28.08.2014 19:16
   -- since rev. 59953, 05.08.2014 08:46:
   ,frg_reads bigint
   ,rec_locks bigint
   ,rec_waits bigint
   ,rec_confl bigint
   -----------------------------------------------------------------------------
   ,mem_used bigint
   ,mem_alloc bigint
   ,stat_id bigint
   ,server_pid bigint
   ,mult dm_sign
   ,add_info dm_info
   ,dts timestamp default 'now'
   ,rowset bigint -- for grouping records that related to the same measurement
   ,sec int -- added 27.11.2020
) on commit preserve rows;
commit;

-- 29.08.2014: for identifying troubles by analyzing results per each table:
recreate global temporary table tmp$mon_log_table_stats( -- used in tmp_random_run.sql
    unit dm_unit
   ,fb_gdscode int
   ,att_id bigint default current_connection
   ,trn_id bigint
   ,table_id smallint
   ,table_name dm_dbobj  -- filled in SP srv_fill_mon
   -------------------
   ,rec_inserts bigint
   ,rec_updates bigint
   ,rec_deletes bigint
   ,rec_backouts bigint
   ,rec_purges bigint
   ,rec_expunges bigint
   ,rec_seq_reads bigint
   ,rec_idx_reads bigint
   ,rec_rpt_reads bigint
   ,bkv_reads bigint
   ,frg_reads bigint
   ,rec_locks bigint
   ,rec_waits bigint
   ,rec_confl bigint
   ,stat_id bigint
   ,mult dm_sign
   ,rowset bigint -- for grouping records that related to the same measurement
) on commit preserve rows;
commit;


-- Some values which are constant during app work, definitions for worload modes:
-- Values from 'svalue' field will be stored in session-level CONTEXT variables
-- with names defined in field 'mcode' ('C_CUSTOMER_DOC_MAX_ROWS' etc):
recreate table settings(
    working_mode varchar(20) character set utf8
    ,mcode dm_name -- mnemonic code
    ,context varchar(16) default 'USER_SESSION'
    ,svalue dm_setting_value
    ,init_on varchar(20) default 'connect' -- read this value in context var in trg_connect; 'db_prepare' ==> not needed in runtime
    ,description dm_info
    ,constraint settings_unq unique(working_mode, mcode) using index settings_mode_code
    ,constraint settings_valid_ctype check(context in(null,'USER_SESSION','USER_TRANSACTION'))
);
commit;
-- added 17.09.2020: forgotten since 28.04.2020!
create unique index settings_mcode_wm_unq on settings computed by ( mcode || iif(working_mode in ('COMMON','INIT'), '', working_mode) );
commit;

-- lookup table: types of operations
recreate table optypes(
   id dm_ids constraint pk_optypes primary key using index pk_optypes
  ,mcode dm_mcode -- mnemonic code
  ,name dm_name
  ,m_qty_clo dm_sign -- how this op. affects on remainder "clients order"
  ,m_qty_clr dm_sign -- how this op. affects on remainder "REFUSED clients order"
  ,m_qty_ord dm_sign -- how this op. affects on remainder "stock order"
  ,m_qty_sup dm_sign -- how this op. affects on remainder "unclosed invoices from supplier"
  ,m_qty_avl dm_sign -- how this op. affects on remainder "avaliable to be reserved"
  ,m_qty_res dm_sign -- how this op. affects on remainder "in reserve for some customer"
  ,m_cost_inc computed by(iif(m_qty_avl=1,1,0)) -- see field invnt_saldo.cost_inc
  ,m_cost_out computed by(iif(m_qty_res=-1,1,0)) -- see field invnt_saldo.cost_out
  ,m_cust_debt dm_sign -- auxiliary field: affect on mutual settlements with customer
  ,m_supp_debt dm_sign -- auxiliary field: affect on mutual settlements with supplier
  -- kind of this operation: 'i' = incoming; 'o' = outgoing; 'p' = payment
  ,acn_type dm_account_type -- need for FIFO distribution
  ,multiply_rows_for_fifo dm_sign default 0
  ,end_state bigint -- (todo later) state of document after operation is completed (-1 = "not changed")
  -- operation can not change both cost_INC and cost_OUT:
  ,constraint optypes_mcode_unq unique(mcode) using index optypes_mcode_unq
  ,constraint optype_mutual_inc_out check( abs(m_cost_inc)+abs(m_cost_out) < 2 )
  ,constraint optype_mult_pay_only check(
     m_supp_debt=1 and m_cost_inc=1
     or
     m_cust_debt=1 and m_cost_out=1
     or
     m_supp_debt<=0 and m_cust_debt <=0 and (m_cost_inc=0 and m_cost_out=0)
   )
  );
commit;

-- Definitions for "value_to_rows" distributions for operations when it's needed:
recreate table rules_for_qdistr(
    mode dm_name -- 'new_doc_only' (rcv='clo'), 'distr_only' (snd='clo', rcv='res'), 'distr+new_doc' (all others)
    ,snd_optype_id dm_ids -- nullable: there is no 'sender' for client order operation (this is start of business chain)
    ,rcv_optype_id dm_ids -- nullable: there is no 'receiver' for reserve write-off (this is end of business chain)
    ,storno_sub smallint -- NB: for rcv_optype_id=3300 there will be TWO records: 1 (snd_op=2100) and 2 (snd_op=1000)
    ,constraint rules_for_qdistr_unq unique(snd_optype_id, rcv_optype_id) using index rules_for_qdistr_unq
);
-- 10.09.2014: investigate performance vs sp_rules_for_qdistr; result: join with TABLE wins.
create index rules_for_qdistr_rcvop on rules_for_qdistr(rcv_optype_id);
commit;

-- create tables without ref. constraints
-- doc headers:
recreate table doc_list(
   id dm_idb
  ,optype_id dm_ids
  ,agent_id dm_idb
  ,state_id dm_ids
  ,base_doc_id bigint -- id of document that is 'base' for current (stock order => incoming invoice etc)
  ,cost_purchase dm_cost default 0 -- total in PURCHASING cost; can be ZERO for payment from customers
  ,cost_retail dm_cost default 0 -- total in RETAIL cost; can be zero OUR PAYMENT to suppliers
  ,acn_type dm_account_type
  ,dts_open timestamp default 'now'
  ,dts_fix timestamp -- when changes of CONTENT of this document became disabled
  ,dts_clos timestamp -- when ALL changes of this doc. became disabled
  ,constraint pk_doc_list primary key(id) using index pk_doc_list
  ,constraint dts_clos_greater_than_open check(dts_clos is null or dts_clos > dts_open)
   -- 12.08.2018, only when config parameter 'separate_work' is 1: 
   -- sequential number of ISQL session that did create this document.
   -- This number is evaluated as mod(CURRENT_CONNECTION, %winq% ), where %winq% is total number
   -- of ISQL sessions that are launched now. Value of %winq% is stored /updated in the table 'SETTINGS'.
  ,worker_id dm_ids 
);
create descending index doc_list_id_desc on doc_list(id); -- need for quick select random doc

-- 27.08.2018 do NOT put here this, instead inject actual value of config parameter 'separate_workers' in main batch when build DB: 
-- index doc_list_worker_id on doc_list(worker_id^);
commit;

-- doc detailization (child for doc_list):
recreate table doc_data(
   id dm_idb not null
  ,doc_id dm_idb
  ,ware_id dm_idb
  ,qty dm_qty
  ,cost_purchase dm_cost
  ,cost_retail dm_cost default 0
  ,dts_edit timestamp -- last modification timestamp; do NOT use `default 'now'` here!
  -- PK will be removed from this table if setting 'HALT_TEST_ON_ERRORS' does NOT containing
  -- word '/PK/'. See statements in EB at the ending part of oltp_main_filling.sql:
  ,constraint pk_doc_data primary key(id) using index pk_doc_data
  ,constraint doc_data_doc_ware_unq unique(doc_id, ware_id) using index doc_data_doc_ware_unq
  ,constraint doc_data_qty_cost_both check ( qty>0 and cost_purchase>0 and cost_retail>0 or qty = 0 and cost_purchase = 0 and cost_retail=0 )
);
create descending index doc_data_id_desc on doc_data(id); -- get max in fn_g`et_random_id; 04.06.2014
commit;
-- Cost turnovers "log", by contragents + doc_id + operation types
-- (will be agregated in sp_make_cost_storno, with serialized access to this SP)
-- (NB: *not* all operations add rows in this table)
recreate table money_turnover_log(
    id dm_idb not null
   ,doc_id dm_idb not null
   ,agent_id dm_idb not null -- -- added 09.12.2020 "not null": this field is used for match with money_saldo.agent_id which is PK!
   ,optype_id dm_ids
   ,cost_purchase dm_vals -- can be < 0 when deleting records in doc_xxx
   ,cost_retail dm_vals -- can be < 0 when deleting records in doc_xxx
   ,dts timestamp default 'now'
);
-- 27.09.2015: refactored SP srv_make_money_saldo
create index money_turnover_log_agent_optype on money_turnover_log(agent_id, optype_id);

-- Result of data aggregation of table money_turnover_log in sp_make_cost_storno
-- This table is updated only in 'serialized' mode by SINGLE attach at a time.
recreate table money_saldo(
  agent_id dm_idb constraint pk_money_saldo primary key using index pk_money_saldo,
  cost_purchase dm_vals,
  cost_retail dm_vals
);

-- lookup table: reference of wares (full price list of manufacturer)
-- This table is filled only once, at the test PREPARING phase, see oltp_data_filling.sql
recreate table wares(
   id dm_idb generated by default as identity constraint pk_wares primary key using index pk_wares
   ,group_id dm_idb
   ,numb dm_nums -- original manufacturer number, provided by supplier (for testing SIMILAR TO perfomnace)
   ,name dm_name -- name of ware (for testing SIMILAR TO perfomnace)
   ,price_purchase dm_cost -- we buy from supplier (non fixed price, can vary - sp_client_order)
   ,price_retail dm_cost -- we sale to customers (non fixed price, can vary - see sp_client_order)
   -- business logic contraint: all wares must have unique numbers:
   ,constraint wares_numb_unq unique(numb)
               using index wares_numb_unq
   );
-- aux. index for randomly selecting during emulating create docs:
create descending index wares_id_desc on wares(id);

-- aux table to check performance of similar_to (when search for STRINGS instead of IDs):
recreate table phrases(
   id dm_idb generated by default as identity constraint pk_phrases primary key using index pk_phrases
   ,pattern dm_name
   ,name dm_name
   ,constraint phrases_unq unique(pattern) using index phrases_unq
   --,constraint fk_words_wares_id foreign key (wares_id) references wares(id)
);
create index phrases_name on phrases(name);
create descending index phrases_id_desc on phrases(id);

-- catalog of views which are used in sp_get_random_id (4debug)
recreate table z_used_views( name dm_dbobj, constraint z_used_views_unq unique(name) using index z_used_views_unq);

-- Inventory registry (~agg. matview: how many wares do we have currently)
-- related 1-to-1 to table `wares`; updated periodically and only in "SERIALIZED manner", see s`rv_make_invnt_saldo
recreate table invnt_saldo(
    id dm_idb generated by default as identity constraint pk_invnt_saldo primary key using index pk_invnt_saldo
   ,qty_clo dm_qty default 0 -- amount that clients ordered us
   ,qty_clr dm_qty default 0 -- amount that was REFUSED by clients (s`p_cancel_client_order)
   ,qty_ord dm_qty default 0 -- amount that we ordered (sent to supplier)
   ,qty_sup dm_qty default 0 -- amount that supplier sent to us (specified in incoming doc)
   ,qty_avl dm_qty default 0 -- amount that is avaliable to be taken (after finish checking of incoming doc)
   ,qty_res dm_qty default 0 -- amount that is reserved for customers (for further sale)
   ,qty_inc dm_qty default 0 -- total amount of incomings
   ,qty_out dm_qty default 0 -- total amount of outgoings
   ,cost_inc dm_cost default 0 -- total cost of incomings (total on closed incoming docs)
   ,cost_out dm_cost default 0 -- total cost of outgoings (total on closed outgoing docs)
   ,qty_acn computed by(qty_avl+qty_res) -- amount "on hand" as it seen by accounter
   ,cost_acn computed by ( cost_inc - cost_out ) -- total cost "on hand"
   ,dts_edit timestamp default 'now' -- last modification timestamp
   ,constraint invnt_saldo_acn_zero check (NOT (qty_acn = 0 and cost_acn<>0 or qty_acn<>0 and cost_acn=0 ))
);
commit;

--------------------------------------------------------------------------------
-- Result of "value_to_rows" transformation of AMOUNTS (integers) in doc_data:
-- when we write doc_data.qty=5 then 5 rows with snd_qty=1 will be added to QDistr
-- (these rows will be moved from this table to QStorned during every storning
-- operation, see s`p_make_qty_storno):
recreate table qdistr(
   id dm_idb not null
  ,doc_id dm_idb -- denorm for speed, also 4debug
  ,worker_id dm_ids -- denorm for speed; 12.08.2018
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
  ,dts timestamp default 'now'
);
commit;
-- 21.09.2015: DDL of indices for QDistr table depends on config parameter 'separ_qd_idx' (0 or 1),
-- definition of index key(s) see in 'oltp_create_with_split_heavy_tabs_0.sql' (for non-splitted QDistr) or in
-- 'oltp_create_with_split_heavy_tabs_1.sql' (when table QDistr is replaced with XQD* tables).
-- ................................................................................................
-- ::: nb ::: PK on this table will be REMOVED at the end of script 'oltp_main_filling.sql'
-- if setting 'HALT_TEST_ON_ERRORS' does not contain '/PK/'
alter table qdistr add  constraint pk_qdistr primary key(id) using index pk_qdistr;
-- see in 'oltp_split_heavy_tabs_0,1.sql': create index qdistr_worker_id on qdistr(worker_id);
commit;

-- 22.05.2014: storage for records which are removed from Qdistr when they are 'storned'
-- (will be returned back into qdistr when cancel operation or delete document, see s`p_kill_qty_storno):
recreate table qstorned(
   id dm_idb not null
  ,doc_id dm_idb -- denorm for speed
  ,worker_id dm_ids -- denorm for speed; 12.08.2018
  ,ware_id dm_idb
  ,snd_optype_id dm_ids -- denorm for speed
  ,snd_id dm_idb -- ==> doc_data.id of "sender"
  ,snd_qty dm_qty
  ,rcv_doc_id dm_idb -- 30.12.2014, for enable to remove PK on doc_data, see S`P_LOCK_DEPENDENT_DOCS
  ,rcv_optype_id dm_ids
  ,rcv_id dm_idb
  ,rcv_qty dm_qty
  ,snd_purchase dm_cost
  ,snd_retail dm_cost
  ,rcv_purchase dm_cost
  ,rcv_retail dm_cost
  ,trn_id bigint default current_transaction
  ,dts timestamp default 'now'
);
create index qstorned_doc_id on qstorned(doc_id); -- confirmed 16.09.2014, see s`p_lock_dependent_docs
create index qstorned_snd_id on qstorned(snd_id); -- confirmed 16.09.2014, see s`p_kill_qty_storno
create index qstorned_rcv_id on qstorned(rcv_id); -- confirmed 16.09.2014, see s`p_kill_qty_storno
-- see in 'oltp_split_heavy_tabs_0,1.sql': create index qstorned_worker_id on qstorned(worker_id); -- 12.08.2018
-- ::: nb ::: PK on this table will be REMOVED at the end of script 'oltp_main_filling.sql'
-- if setting 'HALT_TEST_ON_ERRORS' does not contain '/PK/'
alter table qstorned add  constraint pk_qdstorned primary key(id) using index pk_qdstorned;
commit;
-------------------------------------------------------------------------------
-- Result of "value_to_rows" transformation of COSTS in doc_list
-- for payment docs and when we change document state in:
-- s`p_add_invoice_to_stock, s`p_reserve_write_off, s`p_cancel_adding_invoice, s`p_cancel_write_off
recreate table pdistr(
    -- ::: nb ::: PK on this table will be REMOVED at the end of script 'oltp_main_filling.sql'
    -- if setting 'HALT_TEST_ON_ERRORS' does not contain '/PK/'
    id dm_idb generated by default as identity constraint pk_pdistr primary key using index pk_pdistr
    ,agent_id dm_idb
    ,snd_optype_id dm_ids -- denorm for speed
    ,snd_id dm_idb -- ==> doc_list.id of "sender"
    ,worker_id dm_ids -- 12.08.2018
    ,snd_cost dm_qty
    ,rcv_optype_id dm_ids
    ,trn_id bigint default current_transaction
    ,constraint pdistr_snd_op_diff_rcv_op check( snd_optype_id is distinct from rcv_optype_id )
);

-- Index on (worker_id,snd_id) or (snd_id) will be created using dynamic SQL, depending on value
-- on config parameter separate_workers, see 'oltp_adjust_DDL.sql' (05.10.2018)
-- 09.09.2014: attempt to speed-up random choise of non-paid realizations and invoices
-- plus reduce number of doc_list IRs (see v_r`andom_find_non_paid_*, v_min_non_paid_*, v_max_non_paid_*)
create index pdistr_sndop_rcvop_sndid_asc on pdistr (snd_optype_id, rcv_optype_id, snd_id); -- see plan in V_MIN_NON_PAID_xxx
create descending index pdistr_sndop_rcvop_sndid_desc on pdistr (snd_optype_id, rcv_optype_id, snd_id); -- see plan in V_MAX_NON_PAID_xxx
create index pdistr_agent_id on pdistr(agent_id); -- confirmed, 16.09.2014: see s`p_make_cost_storno
commit;

-- Storage for records which are removed from Pdistr when they are 'storned'
-- (will returns back into Pdistr when cancel operation - see sp_k`ill_cost_storno):
recreate table pstorned(
    -- ::: nb ::: PK on this table will be REMOVED at the end of script 'oltp_main_filling.sql'
    -- if setting 'HALT_TEST_ON_ERRORS' does not contain '/PK/'
    id dm_idb generated by default as identity constraint pk_pstorned primary key using index pk_pstorned
    ,agent_id dm_idb
    ,snd_optype_id dm_ids -- denorm for speed
    ,snd_id dm_idb -- ==> doc_list.id of "sender"
    ,worker_id dm_ids -- 12.08.2018
    ,snd_cost dm_cost
    ,rcv_optype_id dm_ids
    ,rcv_id dm_idb
    ,rcv_cost dm_cost
    ,trn_id bigint default current_transaction
    ,constraint pstorned_snd_op_diff_rcv_op check( snd_optype_id is distinct from rcv_optype_id )
);
create index pstorned_snd_id on pstorned(snd_id); -- confirmed, 16.09.2014: see s`p_kill_cost_storno
create index pstorned_rcv_id on pstorned(rcv_id); -- confirmed, 16.09.2014: see s`p_kill_cost_storno
-- Index on worker_id will be created using dynamic SQL when value on config
-- parameter separate_workers is 1, see 'oltp_adjust_DDL.sql' (05.10.2018)
commit;

-- Definitions for "value-to-rows" COST distribution:
recreate table rules_for_pdistr(
    mode dm_name -- 'new_doc_only' (rcv='clo'), 'distr_only' (snd='clo', rcv='res'), 'distr+new_doc' (all others)
   ,snd_optype_id dm_ids
   ,rcv_optype_id dm_ids
   ,rows_to_multiply int default 10 -- how many rows to create when new doc of 'snd_optype_id' is created
   ,constraint rules_for_pdistr_unq unique(snd_optype_id, rcv_optype_id) using index rules_for_pdistr_unq
);
commit;

-------------------------------------------------------------------------------

-- lookup table: doc_states of documents (filled manually, see oltp_main_filling.sql)
recreate table doc_states(
   id dm_ids constraint pk_doc_states primary key using index pk_doc_states
  ,mcode dm_name  -- mnemonic code
  ,name dm_name
  ,constraint doc_states_mcode_unq unique(mcode) using index doc_states_mcode_unq
  ,constraint doc_states_name_unq unique(name) using index doc_states_name_unq
);

-- lookup table: contragents:
recreate table agents(
   id dm_idb generated by default as identity constraint pk_agents primary key using index pk_agents
  ,name dm_name
  ,is_customer dm_sign default 1
  ,is_supplier dm_sign default 0
  ,is_our_firm dm_sign default 0 -- for OUR orders to supplier (do NOT make reserves after add invoice for such docs)
  ,constraint agents_mutual_excl check(  bin_xor( is_our_firm, bin_or(is_customer, is_supplier) )=1 )
  ,constraint agents_name_unq unique(name) using index agents_name_unq
);
-- aux. index for randomly selecting during emulating create docs:
create descending index agents_id_desc on agents(id);
create index agents_is_supplier on agents(is_supplier);
create index agents_is_our_firm on agents(is_our_firm);

-- groups of wares (filled only once before test, see oltp_data_filling.sql)
recreate table ware_groups(
   id dm_idb constraint pk_ware_groups primary key using index pk_ware_groups
  ,name dm_name
  ,descr blob
  ,constraint ware_groups_name_unq unique(name) using index ware_groups_name_unq
);

-- Tasks like 'make_total_saldo' which should be serialized, i.e. run only
-- in 'SINGLETONE mode' (no two attaches can run such tasks at the same time);
-- Filled in oltp_main_filling.sql
recreate table semaphores(
    id dm_idb constraint pk_semaphores primary key using index pk_semaphores
    ,task dm_name
    ,dts timestamp default 'now' -- 12.01.2019: where last time this action was done (mostly for srv_recalc_idx_stat)
    ,constraint semaphores_task_unq unique(task) using index semaphores_task_unq
);
commit;

-- Log for all changes in doc_data.qty (including DELETION of rows from doc_data).
-- Only INSERTION is allowed to this table for 'common' business operations.
-- Fields qty_diff & cost_diff can be NEGATIVE when document is removed ('cancelled')
-- Aggregating and deleting rows from this table - see s`rv_make_invnt_saldo
recreate table invnt_turnover_log(
    ware_id dm_idb not null -- added 09.12.2020 "not null": this field is used for match with invnt_saldo.ware_id which is PK!
   ,qty_diff numeric(12,3)  -- can be < 0 when cancelling document
   ,cost_diff numeric(12,2) -- can be < 0 when cancelling document
   ,doc_list_id bigint
   ,doc_pref dm_mcode
   ,doc_data_id bigint
   ,optype_id dm_ids
   ,id dm_idb not null -- FB 3.x: do NOT `generated by default as identity`, we use bulk-getting new IDs (or trigger with gen_id) instead
   ,dts_edit timestamp default 'now' -- last modification timestamp
   ,att_id int default current_connection
   ,trn_id int default current_transaction
   -- finally dis 09.01.2015, not needed for this table: ,constraint pk_invnt_turnover_log primary key(id) using index pk_invnt_turnover_log
);
create index invnt_turnover_log_ware_dd_id on invnt_turnover_log(ware_id, doc_data_id);

-- Aux. table for random choise of app. unit to be performed and overall perfomance report.
-- see script %tmpdir%\tmp_random_run.sql which is auto generated by 1run_oltp_emul.bat:
recreate table business_ops(
    unit dm_unit,
    sort_prior int unique,
    info dm_info,
    mode dm_name,
    kind dm_name,
    random_selection_weight smallint,
    predictable_selection_priority smallint,
    constraint bo_unit unique(unit) using index bo_unit_unq
);
create index business_ops_rnd_wgth on business_ops(random_selection_weight); -- 23.07.2014
create index business_ops_predict_prior on business_ops(predictable_selection_priority);
commit;

-- Standard Firebird error list with descriptions:
-- Declarations with descriptions can be found in:
-- 1) src\include\gen\iberror.h (ISC error codes) -- declarations like:
--     const ISC_STATUS isc_arith_except                     = 335544321L;
--     const ISC_STATUS isc_update_conflict                  = 335544451L;
-- 2) src\include\gen\msgs.h -- multi-dim array like:
--     {335544321, "arithmetic exception, numeric overflow, or string truncation"},        /* arith_except */
--     {335544451, "update conflicts with concurrent update"},        /* update_conflict */
-- 3) src\include\gen\sql_code.h -- multi-dim array like:
--     {335544321, -802}, /*   1 arith_except */
--     {335544451, -904}, /* 131 update_conflict */
-- 4) src\include\gen\sql_state.h -- multi-dim array like:
--     {335544321, "22000"}, //   1 arith_except
--     {335544451, "40001"}, // 131 update_conflict
-- See also src\msgs\messages2.sql for set of messages that are used when exceptions raise:
-- set bulk_insert INSERT INTO MESSAGES ...
-- ('arith_except', NULL, NULL, NULL, 0, 1, NULL, 'arithmetic exception, numeric overflow, or string truncation', NULL, NULL);
-- ('update_conflict', NULL, NULL, NULL, 0, 131, NULL, 'update conflicts with concurrent update', NULL, NULL);
-- stop
recreate table fb_errors(
   fb_sqlcode int,
   fb_gdscode int,
   fb_mnemona varchar(64),
   fb_errtext varchar(256),
   constraint fb_errors_gds_code_unq unique(fb_gdscode) using index fb_errors_gds_code
);
commit;

-- Log of parsing ISQL statistics
recreate table perf_isql_stat(
    trn_id bigint default current_transaction
    ,isql_current bigint
    ,isql_delta bigint
    ,isql_max bigint
    ,isql_elapsed numeric(12,3)
    ,isql_reads bigint
    ,isql_writes bigint
    ,isql_fetches bigint
    ,sql_state varchar(5)
);
create index perf_isql_stat_trn on perf_isql_stat(trn_id);
commit;

-- 23.12.2015 Log of parsed trace for ISQL session #1
recreate table trace_stat(
    unit dm_unit
    ,dts_end timestamp
    ,success smallint
    ,elapsed_ms int
    ,reads bigint
    ,writes bigint
    ,fetches bigint
    ,marks bigint
);
commit;

-- 18.03.2019
recreate table perf_agg(
   unit dm_unit -- name of executed SP
  ,exc_unit char(1) -- was THIS unit the place where exception raised ? yes ==> '#'
  ,fb_gdscode int -- how did finish this unit (0 = OK)
  ,dts_interval int -- for ability to split data on time intervals, see sp REPORT_PERF_DYNAMIC
  ,total_cnt bigint
  ,total_ms bigint
  ,min_ms bigint
  ,max_ms bigint
  ,id dm_idb generated by default as identity constraint pk_perf_agg primary key
);
create unique index perf_agg_unq on perf_agg(unit, fb_gdscode, exc_unit, dts_interval);
commit;

-- Log for performance and errors (filled via autonom. tx if exc`eptions occur).
-- In the past, this table was sibject of lot of pending requests which in turn
-- had bad affect on performance.
-- Currently is used only for storing several records when test starts/finishes.
-- Several tables (up to 10) with the same DDL and names 'PERF_SPLIT_nn' will be
-- created dynamically in oltp_adjust.sql. All of these tables serve as source
-- view v_perf_log which accepts data about performance. Trigger with case-expression
-- is defined dynamically (also in oltp_adjust.sql) for redirect data to the "final"
-- place of storing: some concrete table with name PERF_SPLIT_nn.
recreate table perf_log(
   id dm_idb not null -- value from sequence where record has been added into GTT tmp$perf_log; not null -- added 11.01.2017, for possible replication (PK constraint is required)
  --,id2 bigint -- value from sequence where record has been written from tmp$perf_log into fixed table perf_log (need for debug)
  ,unit dm_unit -- name of executed SP
  ,exc_unit char(1) -- was THIS unit the place where exception raised ? yes ==> '#'
  ,fb_gdscode int -- how did finish this unit (0 = OK)
  ,trn_id bigint default current_transaction
  ,att_id int default current_connection
  ,elapsed_ms bigint -- do not make it computed_by, updating occur in single point (s`p_add_to_perf_log)
  ,info dm_info -- info for debug
  ,exc_info dm_info -- info about exception (if occured)
  ,stack dm_stack
  ,ip dm_ip  -- rdb$get_context('SYSTEM','CLIENT_ADDRESS'); for IPv6: 'FF80:0000:0000:0000:0123:1234:ABCD:EF12' - enough 39 chars
  ,dts_beg timestamp default 'now' -- current_timestamp
  ,dts_end timestamp
  ,aux1 double precision -- for srv_recalc_idx_stat: new value of index statistics
  ,aux2 double precision -- for srv_recalc_idx_stat: difference after recalc idx stat
  ,dump_trn bigint default current_transaction
);
-- No indices needed now for this table.
commit;

-- Table to store single record for every *start* point of any app. unit.
-- When unit finishes NORMALLY (without exc.) this record is removed to fixed
-- storage (perf_log). Otherwise this table will serve as source to 'transfer'
-- uncommitted data to fixed perf_log via autonom. tx and session-level contexts
-- This results all such uncommitted data to be saved even in case of exc`eption.
recreate global temporary table tmp$perf_log(
   id dm_idb
  ,id2 bigint -- == gen_id(g_perf_log, 0) at the end of unit (when doing update)
  ,unit dm_unit
  ,exc_unit char(1)
  ,fb_gdscode int
  ,trn_id bigint default current_transaction
  ,att_id int default current_connection
  ,elapsed_ms bigint
  ,info dm_info
  ,exc_info dm_info
  ,stack dm_stack
  ,ip dm_ip
  ,dts_beg timestamp default 'now' -- current_timestamp
  ,dts_end timestamp
  ,aux1 double precision
  ,aux2 double precision
  ,dump_trn bigint default current_transaction
) on commit delete rows;
create index tmp$perf_log_unit_trn_dts_end on tmp$perf_log(unit, trn_id, dts_end);
commit;

-- Table for report that shows performance score per each MINUTE of both test phases:
-- ##############################################################
-- NB: This table is dropped and created again in oltp_adjust.dll
-- common script for 2.5 and 3.0, do NOT use definition of PK via 'generated' clause.
-- ##############################################################
-- This table is used ONLY by view v_perf_estimated, see sp_add_perf_log.
-- 27.11.2020, need for FB 4.x+: added pool_active and pool_idle columns
-- (num of active and idle connections in external conn. pool if enabled)
recreate table perf_estimated(
    id dm_idb not null
    ,minute_since_test_start int
    ,success_count numeric(12,2)
    ,worker_id dm_ids
    ,pool_active int
    ,pool_idle int
    ,att_id int default current_connection
    ,dts timestamp default 'now'
    ,constraint pk_perf_estimated primary key(id)
);
commit;

-- 27.03.2019, for report only (speed), see SP report_perf_per_minute
-- (materializing intermediate result of aggregation perf_estimated table)
recreate global temporary table tmp$perf_est_whole(
    test_phase_sign smallint not null,
    earliest_cnt_for_phase int
) on commit delete rows;
commit;

-- introduced 09.08.2014, for checking mon$-tables stability: gather stats
-- Also used when config parameter 'mon_unit_list' is not empty (see s`p_add_to_perf_log).
-- see mail: SF.net SVN: firebird:[59967] firebird/trunk/src/jrd
-- (dimitr: Better (methinks) synchronization for the monitoring stuff)
recreate table mon_log(
    unit dm_unit
   ,fb_gdscode int
   ,elapsed_ms int -- added 08.09.2014
   ,trn_id bigint
   ,add_info dm_info
   --------------------
   ,rec_inserts dm_counter
   ,rec_updates dm_counter
   ,rec_deletes dm_counter
   ,rec_backouts dm_counter
   ,rec_purges dm_counter
   ,rec_expunges dm_counter
   ,rec_seq_reads dm_counter
   ,rec_idx_reads dm_counter
   ---------- counters avaliable only in FB 3.0, since rev. 59953 --------------
   ,rec_rpt_reads dm_counter -- <<< since rev. 60005, 27.08.2014 18:52
   ,bkv_reads dm_counter -- mon$backversion_reads, since rev. 60012, 28.08.2014 19:16
   ,frg_reads dm_counter -- since rev. 59953, 05.08.2014 08:46
   -- optimal values for (letter by dimitr 27.08.2014 21:30):
   -- bkv_per_rec_reads = 1.0...1.2
   -- frg_per_rec_reads = 0.01...0.1 (better < 0.01), depending on record width; increase page size if high value
   ,bkv_per_seq_idx_rpt computed by ( 1.00 * bkv_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,frg_per_seq_idx_rpt computed by ( 1.00 * frg_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,rec_locks dm_counter
   ,rec_waits dm_counter
   ,rec_confl dm_counter
   -----------------------------------------------------------------------------
   ,pg_reads dm_counter
   ,pg_writes dm_counter
   ,pg_fetches dm_counter
   ,pg_marks dm_counter
   ,mem_used bigint -- must NOT be type of dm_counter because negative values can be here
   ,mem_alloc bigint -- must NOT be type of dm_counter because negative values can be here
   ,server_pid bigint
   ,remote_pid bigint
   ,stat_id dm_counter
   ,dump_trn bigint default current_transaction
   ,ip dm_ip
   ,usr dm_dbobj
   ,remote_process dm_info
   ,rowset bigint -- for grouping records that related to the same measurement
   ,att_id bigint
   ,id dm_idb generated by default as identity constraint pk_mon_log primary key using index pk_mon_log
   ,dts timestamp default 'now'
   ,sec int
);
create descending index mon_log_rowset_desc on mon_log(rowset);
create index mon_log_gdscode on mon_log(fb_gdscode);
create index mon_log_unit on mon_log(unit);
create index mon_log_dts on mon_log(dts); -- 26.09.2015, for SP srv_mon_stat_per_units
commit;

-- 29.08.2014
recreate table mon_log_table_stats(
    unit dm_unit
   ,fb_gdscode int
   ,trn_id bigint
   ,table_name dm_dbobj
   --------------------
   ,rec_inserts dm_counter
   ,rec_updates dm_counter
   ,rec_deletes dm_counter
   ,rec_backouts dm_counter
   ,rec_purges dm_counter
   ,rec_expunges dm_counter
   ,rec_seq_reads dm_counter
   ,rec_idx_reads dm_counter
   --------------------
   ,rec_rpt_reads dm_counter
   ,bkv_reads dm_counter
   ,frg_reads dm_counter
   ,bkv_per_seq_idx_rpt computed by ( 1.00 * bkv_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,frg_per_seq_idx_rpt computed by ( 1.00 * frg_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,rec_locks dm_counter
   ,rec_waits dm_counter
   ,rec_confl dm_counter
   ,stat_id dm_counter
   ,rowset bigint -- for grouping records that related to the same measurement
   ,table_id smallint
   ,is_system_table smallint
   ,rel_type smallint
   ,att_id bigint default current_connection
   ,id dm_idb generated by default as identity constraint pk_mon_log_table_stats primary key using index pk_mon_log_table_stats
   ,dts timestamp default 'now'
);
create descending index mon_log_table_stats_rowset on mon_log_table_stats(rowset);
create index mon_log_table_stats_gdscode on mon_log_table_stats(fb_gdscode);
create index mon_log_table_stats_tn_unit on mon_log_table_stats(table_name, unit);
create index mon_log_table_stats_dts on mon_log_table_stats(dts); -- 26.09.2015, for SP srv_mon_stat_per_tables
commit;

-- 31.12.2018: data related to memory consumption (including metadata cache size).
recreate table mon_cache_memory (
    pg_buffers int
    ,pg_size int
    ,pg_cache_type varchar(10)
    ,page_cache_size bigint
    ,meta_cache_size bigint
    ,memo_used_all bigint -- 27.05.2020
    ,memo_allo_all bigint -- 27.05.2020
    ,memo_used_att bigint
    ,memo_used_trn bigint
    ,memo_used_stm bigint
    ,total_attachments_cnt smallint
    ,active_attachments_cnt smallint
    ,page_cache_operating_stm_cnt smallint
    ,data_transfer_paused_stm_cnt smallint
    ,id dm_idb generated by default as identity
    ,dts timestamp default 'now'
    ,elap_ms int -- duration of gathering mon$ info, milliseconds
    ,constraint pk_mon_cache_memory primary key(id)
);
commit;

-- 03.12.2020: table for final report about ExtConn Pool usage, stores aggregated data
recreate table perf_eds_agg (
    -- Number of minutes passed since <test_time> start
    minute_since_test_start int not null
    -- Totals for event associated with connection:
    -- when record is added by CONNECT trigger:
    --     'N' = new EDS connection established  (system var. RESETTING =  false)
    --     'A' = session reset: connection was idle and become active now (system var. RESETTING =  true)
    -- when record is added by DISCONNECT trigger:
    --     'I' = session reset: connection was active and become idle now  (system var. RESETTING =  true)
    --     'D' = connection is gone (system var. RESETTING =  false), i.e. is removed from Pool
    ,evt_N_total_cnt int
    ,evt_A_total_cnt int
    ,evt_I_total_cnt int
    ,evt_D_total_cnt int
    ,evt_overall_cnt computed by (evt_N_total_cnt + evt_A_total_cnt + evt_I_total_cnt + evt_D_total_cnt)
    -- Average, min and max number of active and idle connections
    -- in External Connections Pool, during <dts_interval>. 
    -- Only values for app='firebird' must be taken in account for report:
    ,avg_pool_active double precision
    ,min_pool_active int
    ,max_pool_active int
    ,avg_pool_idle double precision
    ,min_pool_idle int
    ,max_pool_idle int
    ,constraint perf_eds_agg_pk primary key(minute_since_test_start)
);
commit;

---create unique index perf_eds_agg_mi on perf_eds_agg(minute_since_test_start);
---commit;


recreate table perf_eds_life_agg (
     -- sid smallint -- ex. 'who' dm_dbobj
     att bigint not null
    ,dts_born timestamp -- new EDS connection established, i.e. first record with evt for this EDS att in v_perf_eds (ordered by timestamp)
    ,dts_last timestamp -- last activity of this EDS before it gone (last record with evt='A' before record with evt = 'D', ord. by timestamp)
    ,dts_gone timestamp -- dts when connection is gone, i.e. last record with evt for this EDS att in v_perf_eds (ordered by timestamp)
    ,max_idle_ms int -- max duration of IDLE state for key (sid, att)
    ,avg_idle_ms double precision -- avg duration of IDLE state for key (sid, att)
    ,evt_last char(1) -- last event type; if 'A' and new is 'B' then datediff between them is duration of IDLE state
    ,evt_cnt bigint -- needed for counting avg_idle_ms 'on-the-fly'
    ,id dm_idb -- needed only when config parameter 'used_in_replication' = 1
    ,constraint perf_eds_life_agg_pk primary key(att)
    --,constraint perf_eds_life_agg_unq unique (att)
);
commit;

--------------------------------------------------------------------------------
-- # # # # #                 F O R E I G N    K E Y S                  # # # # #
--------------------------------------------------------------------------------
-- create ref constraints (NB: must be defined AFTER creation parent tables with PK/UK)
-- ::: NB ::: See about cascades caution:
-- sql.ru/forum/1081231/kaskadnoe-udalenie-pochemu-trigger-tablicy-detali-ne-vidit-master-zapisi?hl=
alter table doc_list
  add constraint fk_doc_list_agents foreign key (agent_id) references agents(id)
;

alter table doc_data
   add constraint fk_doc_data_doc_list foreign key (doc_id) references doc_list(id)
       on delete cascade
       using index fk_doc_data_doc_list
;

alter table wares
   add constraint fk_wares_ware_groups foreign key (group_id) references ware_groups(id)
;

-- do NOT: alter table money_turnover_log add constraint fk_money_turnover_log_doc_list foreign key (doc_id) references doc_list(id);
-- (documents can be deleted but it mean that NEW record in money_turnover_log appear with cost < 0!)
commit;

--------------------------------------------------------------------------------
-- # # # # #      V I E W S:   I N I T I A L    D E F I N I T I O N    # # # # #
--------------------------------------------------------------------------------

create or alter view v_perf_log as
-- 08.10.2018: view for inserting rows in SP_ADD_PERF_LOG,
-- its DDL can be replaced below with UNIONED query from several tables,
-- each of them will serve as storage for 'separate' set of rows.
-- Purpose: reduce low-level lock contention that occurs for perf_log table.
select * from perf_log
;
commit;

create or alter view v_perf_agg as
-- 18.03.2019: datasource for reports (instead old v_perf_log):
-- Table perf_agg is filled through DML statements on this view in
-- autogen-proc tmp_autogen_aggregate_perf_data (see oltp_adjust_DDL.sql)
select * from perf_agg
;
commit;

create or alter view v_perf_estimated as
-- View for ability to DROP table perf_estimated and create it again
-- (much faster than delete all rows from it before every new test launch)
-- Recreated in oltp_adjust_DDL.sql before every new test launch.
-- It must be the only DB object that depends on table 'perf_estimated'.
-- Must be updated only via sp_add_perf_log:
select * from perf_estimated
;
commit;

create or alter view v_pool_usage as
select v.minute_since_test_start
    ,avg(distinct v.worker_id) active_workers_cnt
    ,avg(v.pool_active) avg_pool_active
    ,avg(v.pool_idle) avg_pool_idle
from v_perf_estimated v
group by 1;
commit;


create or alter view v_perf_eds as
select 
     1 as id
    ,current_timestamp as dts
    ,1 as att
    ,1 as trn
    ,1 as sid -- ex 'who', current_user
    ,'' as app
    ,'' as evt
    ,1 as pool_active
    ,1 as pool_idle
from rdb$database;
commit;


-- 03.12.2020
create or alter view v_perf_eds_agg as
-- UPDATABLE view, used in SP tmp_aggregate_perf_eds_autogen.
-- which is recreated on every test launch, see oltp_adjust_eds_perf.sql
-- NOTE: do use apply CAST(...) or ORDER BY here, because this view 
-- will not allow to use insert/update/delete statements against it.
select
    minute_since_test_start
    ,evt_n_total_cnt
    ,evt_a_total_cnt
    ,evt_i_total_cnt
    ,evt_d_total_cnt
    ,evt_overall_cnt
    ,avg_pool_active
    ,min_pool_active
    ,max_pool_active
    ,avg_pool_idle
    ,min_pool_idle
    ,max_pool_idle
from perf_eds_agg
;
commit;



create or alter view v_perf_eds_life_agg as
select * from perf_eds_life_agg
;


--------------------------------------------------------------------------------
-------    "S y s t e m"    f u n c s   &  s t o r e d     p r o c s   --------
--------------------------------------------------------------------------------

------------  P S Q L     S t o r e d    F u n c t i o n s  -----------------
-- As of current FB-3.x state, deterministic function can use internal 'cache'
-- only while some query is running. Its result is RE-CALCULATED every time when
-- 1) running new query with this func; 2) encounter every new call inside PSQL
-- see sql.ru/forum/actualutils.aspx?action=gotomsg&tid=951736&msg=12787923

set term ^;

create or alter function fn_infinity returns bigint deterministic as
begin
  return 9223372036854775807;
end -- fn_infinity
^

create or alter function fn_is_lock_trouble(a_gdscode int) returns boolean
as
begin
    -- lock_conflict, concurrent_transaction, deadlock, update_conflict
    return a_gdscode in (335544345, 335544878, 335544336,335544451 );
end

^ -- fn_is_lock_trouble

create or alter function fn_is_validation_trouble(a_gdscode int) returns boolean
as
begin
    -- 335544558    check_constraint    Operation violates CHECK constraint @1 on view or table @2.
    -- 335544347    not_valid    Validation error for column @1, value "@2".
    return a_gdscode in ( 335544347,335544558 );
end

^ -- fn_is_validation_trouble

create or alter function fn_is_uniqueness_trouble(a_gdscode int) returns boolean
as
begin
    -- if table has unique constraint: 335544665 unique_key_violation (violation of PRIMARY or UNIQUE KEY constraint "T1_XY" on table "T1")
    -- if table has only unique index: 335544349 no_dup (attempt to store duplicate value (visible to active transactions) in unique index "T2_XY")
    return a_gdscode in ( 335544665,335544349 );
end

^ -- fn_is_uniqueness_trouble

create or alter procedure fn_halt_sign(a_gdscode int) returns(result dm_sign) as
begin
    -- STUB! Actual code see in oltp_common_sp.sql
    suspend;
end
^

create or alter function fn_halt_sign(a_gdscode int) returns dm_sign as
begin
    return ( select result from fn_halt_sign( :a_gdscode ) );
end

^ -- fn_halt_sign


create or alter function fn_remote_process returns varchar(255) deterministic as
begin
    return rdb$get_context('SYSTEM', 'CLIENT_PROCESS');
end
^

create or alter procedure fn_remote_process returns (result varchar(255) ) as
begin
    -- 28.05.2020. This SP is needed only for units which are common for 2.5 and 3.x+.
    -- We can move them in sp_comnon_sp.sql (there is no PSQL functions in FB 2.5)
    result = fn_remote_process();
    suspend;
end
^


create or alter function fn_remote_address returns dm_ip deterministic as
begin
    return rdb$get_context('SYSTEM','CLIENT_ADDRESS');
end
^

create or alter function fn_is_snapshot returns boolean deterministic as
begin
    return
        fn_remote_process() containing 'IBExpert' 
        or
        rdb$get_context('SYSTEM','ISOLATION_LEVEL') is not distinct from upper('SNAPSHOT')
        or
        rdb$get_context('SYSTEM','ENGINE_VERSION') >= '4.0' and rdb$get_context('SYSTEM', 'SNAPSHOT_NUMBER') is not null
        ;
end
^

-- 19.09.2020
create or alter procedure fn_is_snapshot
returns (
    result dm_sign)
AS
begin
    -- 19.09.2020. This SP is needed only for units which are common for 2.5 and 3.x+.
    -- We can move them in sp_comnon_sp.sql (there is no PSQL functions in FB 2.5)
    result = iif( fn_is_snapshot(), 1, 0);
    suspend;
end
^

-- 19.09.2020
create or alter procedure fn_is_lock_trouble (
    a_gdscode integer)
returns(
    result dm_sign
)
as
begin
    -- 19.09.2020. This SP is needed only for units which are common for 2.5 and 3.x+.
    -- We can move them in sp_comnon_sp.sql (there is no PSQL functions in FB 2.5)
    result = iif( fn_is_lock_trouble(a_gdscode), 1, 0 );
    suspend;
end
^

------ stored functions for caching data from DOC_STATES table: --------
-- ::: NB ::: as of current FB-3 state, deterministic function will re-calculate
-- it's result on EVERY NEW call of the SAME statement inside the same transaction.
-- www.sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1081535&msg=15694407
-- Also such repeating work will be done on every function call from trigger or SP.
-- So instead of access to table it's better to return value of context variable
-- which has been defined once (at 1st call of this determ. function).
-----------------------------------------------------------------------------

create or alter function fn_get_state_id(
    a_mcode varchar(80) -- dm_name ? null  can be passed here ?
    ,a_ctx_name varchar(80) -- dm_name
) returns dm_idb deterministic  as
    declare v_id type of dm_idb = null;
    declare v_stt varchar(2048);
    declare v_lf char(1) = x'0A';
begin
    -- a_mcode = 'DOC_OPEN_STATE' etc
    -- a_ctx_name = 'FN_DOC_OPEN_STATE' etc
    -- select FN_GET_STATE_ID('DOC_OPEN_STATE', 'FN_DOC_OPEN_STATE') from rdb$database;

    -- check if this ID already known:
    v_id = rdb$get_context('USER_SESSION', a_ctx_name);

    if (v_id is null) then
    begin
        -- See oltpNN_config, parameter 'use_es'. Can be 0, 1 or 2:
        /* #ACTIVATE#IF#USE_ES_EQU_1#BEG#
        v_stt='select -- #EDS#TAG#' || v_lf
             ||' s.id from doc_states s where s.mcode = ? ';
        -- #ACTIVATE#IF#USE_ES_EQU_1#END# */

        /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
        v_stt =
        q'{ execute block(a_mcode type of column doc_states.mcode = ?) returns(v_id type of dm_idb) as
            begin
                -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                execute procedure sp_perf_eds_logging('B');
    
                select -- #EDS#TAG#
                s.id from doc_states s where s.mcode = :a_mcode
                into v_id;
                suspend;

                -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                -- for connect, so there we have TWO events: 'I' and 'A').
                --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#

            end
        }';
        -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

        /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
        execute statement (v_stt) ( a_mcode )
        -- 20.11.2020
        -- If config parameter USE_ES is 2 then following line will be
        -- replaced with uncommented code for run as ES/EDS.
        -- Host and port will be taken from apropriate config parameters.
        -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
        -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
        into v_id;
        -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */

        -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
        -- usual way (use_es = 0): use static PSQL code.
        select s.id from doc_states s where s.mcode = :a_mcode into v_id;
        -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

        ------------------------------------------------------------------------
        if (v_id is null) then
        begin
            exception ex_record_not_found using( 'DOC_STATES', 'mcode=' || a_mcode );
        end
        rdb$set_context('USER_SESSION', a_ctx_name, v_id);
    end
    
    return v_id;
end
^

create or alter function fn_doc_open_state returns int deterministic  as
begin
    -- Get value of session-level context var 'FN_DOC_xxxx_STATE'.
    -- If it was not yet defined, then get ID from doc_state
    --for mcode = 'DOC_xxxx_STATE' +save it in var 'FN_DOC_xxxx_STATE':
    return fn_get_state_id('DOC_OPEN_STATE', 'FN_DOC_OPEN_STATE');
end

^ -- fn_doc_open_state

create or alter function fn_doc_fix_state returns int deterministic  as
begin
    -- Get value of session-level context var 'FN_DOC_xxxx_STATE'.
    -- If it was not yet defined, then get ID from doc_state
    --for mcode = 'DOC_xxxx_STATE' +save it in var 'FN_DOC_xxxx_STATE':
    return fn_get_state_id('DOC_FIX_STATE', 'FN_DOC_FIX_STATE');
end

^ -- fn_doc_fix_state

create or alter function fn_doc_clos_state returns int deterministic  as
begin
    -- Get value of session-level context var 'FN_DOC_xxxx_STATE'.
    -- If it was not yet defined, then get ID from doc_state
    --for mcode = 'DOC_xxxx_STATE' +save it in var 'FN_DOC_xxxx_STATE':
    return fn_get_state_id('DOC_CLOS_STATE', 'FN_DOC_CLOS_STATE');
end -- fn_doc_clos_state

^

create or alter function fn_doc_canc_state returns int deterministic  as
begin
    -- Get value of session-level context var 'FN_DOC_xxxx_STATE'.
    -- If it was not yet defined, then get ID from doc_state
    --for mcode = 'DOC_xxxx_STATE' +save it in var 'FN_DOC_xxxx_STATE':
    return fn_get_state_id('DOC_CANC_STATE', 'FN_DOC_CANC_STATE');
end

^ -- fn_doc_canc_state


------ stored functions for caching data from OPTYPES table: --------


create or alter function fn_get_oper_id(a_ctx_name dm_name, a_expr varchar(255)) returns dm_idb deterministic  as
    declare v_id type of dm_idb = null;
    declare v_stt varchar(2048);
    declare v_lf char(1) = x'0A';
begin
    -- common unit for definition operation IDs from optypes
    -- and saving them in apropriate context variables.
    -- a_expr must be like 'o.<fieldA> = <m_qty_A> [and o.<fieldB> = <m_qty_B>]' etc,
    -- i.e. it must contain alias for OPTYPES table as 'o.' and apropriate multipliers
    -- for fields (they can be 1, 0, -1)
    -- Example:
    -- select fn_get_oper_id('FN_OPER_ORDER_BY_CUSTOMER', 'o.m_qty_clo = 1 and o.m_qty_clr = 0') from rdb$database;

    -- check if this ID already known:
    v_id = rdb$get_context('USER_SESSION', a_ctx_name);

    if (v_id is null) then begin
        -- See oltpNN_config, parameter 'use_es'. Can be 0, 1 or 2:
        /* #ACTIVATE#IF#USE_ES_EQU_1#BEG#
        -- use_es = 1 --> run this statement via ES in order to see
        -- its occurences and performance in the trace log:
        v_stt='select -- #EDS#TAG#' || v_lf
             ||' o.id from optypes o where ' || a_expr;
        -- #ACTIVATE#IF#USE_ES_EQU_1#END# */

        /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
        -- use_es = 2 --> run this statement via ES/EDS in order to see
        -- how External Connections Pool affects on performance
        v_stt =
        q'{ execute block returns(v_id type of dm_idb) as
            begin
                -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                -- NOTE: we have to log timestamp of point just BEFORE query that
                -- will work: datediff between this point and next firing of
                -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                -- of IDLE state for this connect in the Ext. Conn. Pool.
                execute procedure sp_perf_eds_logging('B');
    
                select -- #EDS#TAG#
                o.id from optypes o where
         }' || v_lf
            || a_expr || v_lf
            || '    into v_id; ' || v_lf
         || q'{
                -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                -- for connect, so there we have TWO events: 'I' and 'A').
                --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
              }' || v_lf
         || '           suspend;' || v_lf
         ||'   end'
         ;
        -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

        /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
        execute statement (v_stt)
        -- 20.11.2020
        -- If config parameter USE_ES is 2 then following line will be
        -- replaced with uncommented code for run as ES/EDS.
        -- Host and port will be taken from apropriate config parameters.
        -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
        -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
        into v_id;
        -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */

        -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
        -- usual way (use_es = 0): use static PSQL code.
        if ( a_ctx_name = 'FN_OPER_ORDER_BY_CUSTOMER' ) then
            select o.id from optypes o where o.m_qty_clo = 1 and o.m_qty_clr = 0 into v_id;
        else if ( a_ctx_name = 'FN_OPER_CANCEL_CUSTOMER_ORDER' ) then
            select o.id from optypes o where o.m_qty_clr = 1 into v_id;
        else if ( a_ctx_name = 'FN_OPER_ORDER_FOR_SUPPLIER' ) then
            select o.id from optypes o where o.m_qty_ord = 1 into v_id;
        else if ( a_ctx_name = 'FN_OPER_INVOICE_GET' ) then
            select o.id from optypes o where o.m_qty_ord = -1 and o.m_qty_sup = 1 into v_id;
        else if ( a_ctx_name = 'FN_OPER_INVOICE_ADD' ) then
            select o.id from optypes o where o.m_qty_sup = -1 and o.m_qty_avl=1 into v_id;
        else if ( a_ctx_name = 'FN_OPER_RETAIL_RESERVE' ) then
            select o.id from optypes o where o.m_qty_avl=-1 and o.m_qty_res=1 into v_id;
        else if ( a_ctx_name = 'FN_OPER_RETAIL_REALIZATION' ) then
            select o.id from optypes o where o.m_qty_res=-1 and o.m_cost_out=1 into v_id;
        else if ( a_ctx_name = 'FN_OPER_PAY_TO_SUPPLIER' ) then
            select o.id from optypes o where o.m_supp_debt = -1 into v_id;
        else if ( a_ctx_name = 'FN_OPER_PAY_FROM_CUSTOMER' ) then
            select o.id from optypes o where o.m_cust_debt = -1 into v_id;
        -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

        ------------------------------------------------------------------------
        if (v_id is null) then
        begin
            exception ex_record_not_found using( 'OPTYPES', 'expr: ' || a_expr );
        end
        rdb$set_context('USER_SESSION', a_ctx_name, v_id);
    end
    
    return v_id;
end
^ -- fn_get_oper_id

create or alter function fn_oper_order_by_customer returns int deterministic  as
begin
    return fn_get_oper_id('FN_OPER_ORDER_BY_CUSTOMER', 'o.m_qty_clo = 1 and o.m_qty_clr = 0');
end

^ -- fn_oper_order_by_customer

create or alter function fn_oper_cancel_customer_order returns int deterministic  as
begin
    return fn_get_oper_id('FN_OPER_CANCEL_CUSTOMER_ORDER', 'o.m_qty_clr = 1');
end

^ -- fn_oper_cancel_customer_order

create or alter function fn_oper_order_for_supplier returns int deterministic  as
begin
    return fn_get_oper_id('FN_OPER_ORDER_FOR_SUPPLIER', 'o.m_qty_ord = 1');
end

^ -- fn_oper_order_for_supplier

create or alter function fn_oper_invoice_get returns int deterministic  as
begin
    return fn_get_oper_id('FN_OPER_INVOICE_GET', 'o.m_qty_ord = -1 and o.m_qty_sup = 1');
end

^  -- fn_oper_invoice_get

create or alter function fn_oper_invoice_add returns int deterministic  as
begin
    return fn_get_oper_id('FN_OPER_INVOICE_ADD', 'o.m_qty_sup = -1 and o.m_qty_avl=1');
end

^ -- fn_oper_invoice_add 


create or alter function fn_oper_retail_reserve returns int deterministic  as
    declare v_id type of dm_idb = null;
    declare v_key1 dm_sign;
    declare v_key2 dm_sign;
    declare v_stt varchar(255);
begin
    return fn_get_oper_id('FN_OPER_RETAIL_RESERVE', 'o.m_qty_avl=-1 and o.m_qty_res=1');
end

^ -- fn_oper_retail_reserve

create or alter function fn_oper_retail_realization returns int deterministic  as
begin
    return fn_get_oper_id('FN_OPER_RETAIL_REALIZATION', 'o.m_qty_res=-1 and o.m_cost_out=1');
end

^ -- fn_oper_retail_realization

create or alter function fn_oper_pay_to_supplier returns int deterministic  as
begin
    return fn_get_oper_id('FN_OPER_PAY_TO_SUPPLIER', 'o.m_supp_debt = -1');
end

^ -- fn_oper_pay_to_supplier

create or alter function fn_oper_pay_from_customer returns int deterministic  as
    declare v_id type of dm_idb = null;
    declare v_key dm_sign;
    declare v_stt varchar(255);
begin
    return fn_get_oper_id('FN_OPER_PAY_FROM_CUSTOMER', 'o.m_cust_debt = -1');
end

^ -- fn_oper_pay_from_customer

create or alter function fn_mcode_for_oper(a_oper_id dm_idb) returns dm_mcode deterministic
as
    declare v_mnemonic_code type of dm_mcode;
begin
    -- returns mnemonic code for operation ('ORD' for stock order, et al)
    v_mnemonic_code = rdb$get_context('USER_SESSION','OPER_MCODE_'||:a_oper_id);
    if (v_mnemonic_code is null) then begin
        select o.mcode from optypes o where o.id = :a_oper_id into v_mnemonic_code;
        rdb$set_context('USER_SESSION','OPER_MCODE_'||:a_oper_id, v_mnemonic_code);
    end
    return v_mnemonic_code;
end

^ -- fn_mcode_for_oper

create or alter function fn_make_predictable_workload returns smallint deterministic as
begin
    return iif( upper(rdb$get_context('USER_SESSION', 'UNIT_SELECTION_METHOD')) = upper('predictable'), 1, 0);
end
^

create or alter function fn_this_worker_seq_no returns smallint deterministic as
    declare v_mon_usr_prefix varchar(31);
    declare v_worker smallint;
begin
    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    if (
         rdb$get_context('USER_SESSION', 'USE_ES') is null
       ) then
    begin
        -- 25.11.2020. This code must be active when config parameter 'use_es' = 2.
        -- There is problem when ExternalConnectionsPool is enabled (FB 4.x+):
        -- triggers on CONNECT / DISCONNECT will *not* fire if interval between
        -- two EDS connections (made by the same user/password/role) less than
        -- ExtConnPoolLifeTime seconds.
        -- This means that we have to forcedly re-read table settings and asign
        -- values from it to session-level context variables, see TRG_CONNECT!
        execute procedure sp_init_ctx;
    end
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

    if ( rdb$get_context('USER_SESSION', 'SEPARATE_WORKERS') = 0 ) then
        return null;
    --------------------------------------------------------------------
    -- 20.11.2020: when config 'use_es' = 2 then some untis work using ES/EDS, i.e. they do *NEW* attachments to DB.
    -- This means that context variable 'WORKER_SEQUENTIAL_NUMBER' that was set in oltp_isql_run_worker batch will
    -- will not be avaliable in new EDS-connections.
    -- This value can be the same as in caller only when user has name that starting with special prefix defined
    -- by config parameter 'mon_usr_prefix': tmp$oemul$user_ etc.
    -- This prefix must ended with underscore character in order to have ability to find sequential number of this user.
    -- We use here this prefix in order to define 'stable' worker seq. number that independent on EDS.

    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    select s.svalue
    from settings s
    where s.working_mode = upper('INIT') and s.mcode  = upper('TMP_WORKER_USER_PREFIX')
    into v_mon_usr_prefix;

    if ( v_mon_usr_prefix > '' and current_user starting with upper(v_mon_usr_prefix) ) then
        -- 'tmp$oemul$user_0067' --> 67 etc:
        -- 'tmp_oemul_user_0095' --> 95 etc:
        return cast( right( current_user, position('_', reverse(current_user)) - 1 ) as smallint );
    else
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

        -- Either 'use_es' is 0 or 1 --> no EDS will be in this test run,
        -- or 'use_es' is 2 and all attachments work as SYSDBA
        -- (but this must not occur because of check at the start of batch!)
        -- NB: do NOT use rdb$get_context('SYSTEM','CLIENT_PID'): it will be the same (PID of *server*) for any EDS!
        return
            coalesce(
                rdb$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER') -- this is defined in oltp_isql_run_worker batch
               ,10000 + mod( current_connection, 100 ) -- this is for initial doc population (obsolete!), developer call from IBE etc
            );
end
^ -- fn_this_worker_seq_no


create or alter procedure fn_this_worker_seq_no returns(result int) as
begin
    -- 21.04.2019. This SP is needed only for units which are common for 2.5 and 3.x+.
    -- We can move them in sp_comnon_sp.sql (there is no PSQL functions in FB 2.5)
    result = fn_this_worker_seq_no();
    suspend;
end
^

create or alter function fn_other_rand_worker returns smallint as
    declare n_this smallint;
    declare n_rnd smallint;
    declare n_max smallint;
    declare n_probes_limit int = 100;
    declare v_rnd double precision;
    declare v_min double precision;
    declare v_max double precision;
begin
    -- 17.09.2018
    -- Used when config params separate_workers = 1 and update_conflict_percent > 0.
    -- Searches in doc_list any record with worker_id differ from fn_this_worker_seq_no().
    -- Limit for these probes is defined by variable n_probes_limit: we have to stop search
    -- when distinct number of doc_list.worker_id is too low and random probes fails every time.
    -- In that case worker_id for "current" ISQL session is returned.
    n_max = cast(rdb$get_context('USER_SESSION', 'WORKERS_COUNT') as smallint);
    if ( n_max = 0 ) then
        return null;
    else
        begin
            n_this = fn_this_worker_seq_no();
            v_min = iif( n_this=1, 2, 1 ) - 0.5;
            v_max = iif( n_this=n_max, n_max-1, n_max ) + 0.5;
            while ( n_probes_limit > 0 ) do
            begin
                n_probes_limit = n_probes_limit - 1;
                v_rnd = v_min + rand() * (v_max - v_min);
                v_rnd = maxvalue( minvalue( v_rnd, v_max ), v_min);
    
                n_rnd = cast( round(v_rnd, 0) as int );
                if ( n_this != n_rnd and exists(select 1 from doc_list d where d.worker_id = :n_rnd) ) then
                    leave;
            end
            -- do NOT use this! Value of "current" ISQL worker_id+1 will be selected more often then all others:
            --n_rnd = ( select d.worker_id from doc_list d where d.worker_id >= :v_rnd and d.worker_id != :n_this order by d.worker_id rows 1 );

            return coalesce( n_rnd, n_this );

        end
end
^ -- fn_other_rand_worker

create or alter function fn_get_stack(
    a_halt_due_to_error smallint default 0
)
    returns dm_stack
as
    declare v_call_stack dm_stack;
    declare function fn_internal_stack_disabled returns boolean deterministic as
    begin
        return ( coalesce(rdb$get_context('USER_SESSION','ENABLE_MON_QUERY'),0) = 0 );
    end
    declare v_line dm_stack;
    declare v_this dm_dbobj = 'fn_get_stack';
begin
    -- :: NB ::
    -- 1. currently building of stack stack IGNORES procedures which are
    -- placed b`etween top-level SP and 'this' unit. See:
    -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16422390
    -- (resolved, see: ChangeLog, issue "2014-08-12 10:21  hvlad")
    -- 2. mon$call_stack is UNAVALIABLE if some SP is called from trigger and
    -- this trigger, in turn, fires IMPLICITLY due to cascade FK.
    -- 13.08.2014: still UNRESOLVED. See:
    -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16438071
    -- 3. Deadlocks trouble when heavy usage of monitoring was resolved only
    --    in FB-3, approx. 09.08.2014, see letter to dimitr 11.08.2014 11:56
    v_call_stack='';
    if ( fn_remote_process() NOT containing 'IBExpert'
         and a_halt_due_to_error = 0
         and fn_internal_stack_disabled()
       ) then
       --####
       exit;
       --####

    for
        with recursive
        r as (
            select 1 call_level,
                 c.mon$statement_id as stt_id,
                 c.mon$call_id as call_id,
                 c.mon$object_name as obj_name,
                 c.mon$object_type as obj_type,
                 c.mon$source_line as src_row,
                 c.mon$source_column as src_col
             -- NB, 13.08.2014: unavaliable record if SP is called from:
             -- 1) trigger which is fired by CASCADE
             -- 2) dyn SQL (ES)
             -- see:
             -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16438071
             -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16442098
            from mon$call_stack c
            where c.mon$caller_id is null

            UNION ALL

            select r.call_level+1,
                   c.mon$statement_id,
                   c.mon$call_id,
                   c.mon$object_name,
                   c.mon$object_type,
                   c.mon$source_line,
                   c.mon$source_column
            from mon$call_stack c
              join r
                on c.mon$caller_id = r.call_id
        )
        ,b as(
            select h.call_level,
                   h.obj_name,
                   h.obj_type,
                   h.src_row,
                   h.src_col
                   --count(*)over() cnt
            from r h
            join mon$statements s
                 on s.mon$statement_id = h.stt_id
            where s.mon$attachment_id = current_connection
        )
        select obj_name, obj_type, src_row, src_col, call_level
        from b
        -- where k < cnt -- <<< do NOT include THIS sp name in call_stack
        order by call_level -- ::: NB :::
        as cursor c
    do
    begin
        v_line = trim(c.obj_name)||'('||c.src_row||':'||c.src_col||') ==> ';
        if ( char_length(v_call_stack) + char_length(v_line) >= 512 )
        then
            exit;

        if ( v_call_stack NOT containing v_line and v_line NOT containing v_this||'(' )
        then
            v_call_stack = v_call_stack || v_line;
    end
    if ( v_call_stack > '' ) then
       v_call_stack = substring( v_call_stack from 1 for char_length(v_call_stack)-5 );
    return v_call_stack;
end

^ -- fn_get_stack

create or alter procedure fn_get_stack(
    a_halt_due_to_error smallint default 0
) returns(result dm_stack) as
begin
    -- 05.10.2020. Added SP in order to make code of sp_halt_on_error common for 2.5 and 3.x+.
    -- and move it into sp_comnon_sp.sql (there is no PSQL functions in FB 2.5)
    result = fn_get_stack(a_halt_due_to_error);
    suspend;
end
^ -- proc fn_get_stack


-- STUB, will be redefined when config parameter 'use_external_to_stop'
-- has some non-empty value of [path+]file of external table that will serve
-- as mean to stop test from outside (i.e. this parameter is UNcommented)
create or alter view v_stoptest as
select 1 as need_to_stop
from rdb$database
where 1 = 0
^

create or alter procedure sp_stoptest
returns(need_to_stop smallint) as
begin
    need_to_stop = sign( gen_id(g_stop_test, 0) );
    if ( need_to_stop = 0 and exists( select * from v_stoptest  ) )
    then
        need_to_stop = -1;
    if ( need_to_stop <> 0 ) then
        -- "+1" => test_time expired, normal finish;
        -- "-1" ==> outside command to premature stop test by adding line into
        --          text file defined by 'ext_stoptest' table or running temp
        --          batch file %tmpdir%\1stoptest.tmp.bat (1stoptest.tmp.sh)
        -- NB: external table is created from .bat / .sh when config parameter
        -- use_external_to_stop = 1.
        suspend;
end
^

create or alter procedure sys_stamp_exception (
    a_exc_name rdb$exception_name, -- name of exception that was just raised
    a_custom_msg rdb$message default null -- message with concrete details (if any)
)
returns(
    result type of column rdb$exceptions.rdb$message
)
 as
    declare exc_prefix varchar(255);
    declare msg_max_octet_len int;
begin
    -- 20.12.2018: add useful info (current_timestamp, connection and transaction id) to exception message 
    -- before sending to client side. Must be called with passing name of currently raising exception.
    if ( rdb$get_context('USER_SESSION', 'MSG_MAX_OCTET_LEN') is null ) then
        begin
            -- Obtain max allowed octet_length for exception text: get field length of rdb$exceptions.rdb$message.
            -- For all versions of FB up to 4.0 it is 1023 octets, but it will be better avoid hard coding of it.
            select c.rdb$bytes_per_character * f.rdb$field_length as field_octet_len
            from rdb$relation_fields rf
            join rdb$fields f on rf.rdb$field_source = f.rdb$field_name
            join rdb$character_sets c on f.rdb$character_set_id = c.rdb$character_set_id
            where
                rf.rdb$relation_name = upper('rdb$exceptions')
                and rf.rdb$field_name = upper('rdb$message')
            into msg_max_octet_len; -- 1023 for FB 2.5, 3.0 and 4.0
            rdb$set_context('USER_SESSION', 'MSG_MAX_OCTET_LEN', msg_max_octet_len);
        end
    else
        msg_max_octet_len = cast(rdb$get_context('USER_SESSION', 'MSG_MAX_OCTET_LEN') as int);

    exc_prefix = replace(cast('now' as timestamp),' ','T')
        || ' ATT_' || coalesce( current_connection, '<?>')
        || ' TRA_' || coalesce( current_transaction, '<?>')
    ;

    result = a_custom_msg;
    if ( result is null ) then
        select trim(rdb$message)
        from rdb$exceptions 
        where upper(rdb$exception_name) = upper( :a_exc_name ) 
        into result;

    if ( octet_length(result) + octet_length(exc_prefix) + 1 >= msg_max_octet_len ) then
        result = left(result, msg_max_octet_len - (octet_length(exc_prefix) + 1) );

    result = exc_prefix || ' ' || result ; -- max allowed octet_length is 32765; otherwise: SQLSTATE = 54000
    suspend;
end
^ -- sys_stamp_exception

create or alter procedure sp_halt_on_error(
    a_char char(1) default '1',
    a_gdscode bigint default null,
    a_trn_id bigint default null,
    a_need_to_stop smallint default null
) as
begin
    -- STUB! Will be defined in oltp_common_sp.sql
end

^ -- sp_halt_on_error


create or alter procedure sp_rules_for_qdistr
returns(
    mode dm_name,
    snd_optype_id  bigint,
    rcv_optype_id  bigint,
    storno_sub smallint
) as
begin
    -- STUB! Will be defined in oltp_common_sp.sql
    suspend;
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
    -- STUB! Will be defined in oltp_common.sp
    suspend;
end
^ -- sp_rules_for_pdistr

set term ;^
commit;

create or alter view v_rules_for_qdistr as
-- 29.03.2019
select * 
from sp_rules_for_qdistr;

create or alter view v_rules_for_pdistr as
-- 29.03.2019
select * 
from sp_rules_for_pdistr;
commit;

set term ^;
create or alter procedure sp_flush_tmpperf_in_auton_tx(
    a_starter dm_unit,  -- name of module which STARTED job, = rdb$get_context(..., 'LOG_PERF_STARTED_BY')
    a_context_rows_cnt int, -- how many 'records' with context vars need to be processed
    a_gdscode int default null
) as
begin
  -- STUB! Actual code see in oltp_common_sp.sql
end
^ -- sp_flush_tmpperf_in_auton_tx

create or alter procedure sp_flush_perf_log_on_abend(
    a_starter dm_unit,  -- name of module which STARTED job, = rdb$get_context( ..., 'LOG_PERF_STARTED_BY')
    a_unit dm_unit, -- name of module where trouble occured
    a_gdscode int default null,
    a_info dm_info default null, -- additional info for debug
    a_exc_info dm_info default null, -- user-def or standard ex`ception description
    a_aux1 dm_aux default null,
    a_aux2 dm_aux default null
)
as
    declare v_cnt smallint;
    declare v_dts timestamp;
    declare v_info dm_info = '';
    declare v_ctx_lim smallint; -- max number of context vars which can be put in one 'batch'
    declare c_max_context_var_cnt int = 1000; -- limitation of Firebird: not more than 1000 context variables
    declare c_std_user_exc int = 335544517; -- std FB code for user defined exceptions
    declare c_gen_inc_step_pf int = 20; -- size of `batch` for get at once new IDs for perf_log (reduce lock-contention of gen page)
    declare v_gen_inc_iter_pf int; -- increments from 1  up to c_gen_inc_step_pf and then restarts again from 1
    declare v_gen_inc_last_pf dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_pf)
    declare v_pf_new_id dm_idb;
begin

    -- called only if ***ABEND*** occurs (from sp`_add_to_abend_log)
    if ( rdb$get_context('USER_TRANSACTION', 'DONE_FLUSH_PERF_LOG_ON_ABEND') is NOT null )
    then
        exit; -- we already done this (just after unit where exc`exption occured)

    v_ctx_lim = cast( rdb$get_context('USER_SESSION', 'CTX_LIMIT_FOR_FLUSH_PERF_LOG') as smallint );
    if ( v_ctx_lim is null ) then
    begin
        -- First, calculate (approx) avaliable limit for creating new ctx vars:
        -- limitation of Firebird: not more than 1000 context variables; take twise less than this limit
        select :c_max_context_var_cnt - sum(c)
        from (
            select count(*) c
            from settings s
            where s.working_mode in(
                'COMMON',
                rdb$get_context('USER_SESSION','WORKING_MODE')
            )
            union all
            select count(*) from optypes    -- look at fn_oper_xxx stored funcs
            union all
            select count(*) from doc_states -- look at fn_doc_xxx_state stored funcs
            union all
            select count(*) from v_rules_for_qdistr -- 29.03.2019: replaced with view in order to remove dependencies
            union all
            select count(*) from v_rules_for_pdistr -- 29.03.2019: replaced with view in order to remove dependencies
        )
        into v_ctx_lim;
        -- Get number of ROWS from tmp$perf_log to start flush data after reaching it:
        -- "0.8*" - to be sure that we won`t reach limit;
        -- "/12" - number of context vars for each record of tmp$perf_log (see below)
        v_ctx_lim = cast( (0.8 * v_ctx_lim) / 12.0 as smallint);
        rdb$set_context('USER_SESSION', 'CTX_LIMIT_FOR_FLUSH_PERF_LOG', v_ctx_lim);
    end

    c_gen_inc_step_pf = v_ctx_lim; -- value to increment IDs in PERF_LOG at one call of gen_id
    v_gen_inc_iter_pf = c_gen_inc_step_pf;

    -- Perform `transfer` from tmp$perf_log to 'fixed' perf_log table
    -- in auton. tx, saving fields data in context vars:
    v_cnt = 0;
    v_dts = 'now';
    for
        select
            unit
            ,coalesce( fb_gdscode, :a_gdscode, :c_std_user_exc ) as fb_gdscode
            ,info
            ,exc_unit -- '#' ==> exception occured in the module with name = tmp$perf_log.unit
            ,iif( exc_unit is not null, coalesce( exc_info, :a_exc_info), null ) as exc_info -- fill exc_info only for unit where exc`eption really occured (NOT for unit that calls this 'problem' unit)
            ,dts_beg
            ,coalesce(dts_end, :v_dts) as dts_end
            ,iif(unit = :a_unit, coalesce(aux1, :a_aux1), aux1) as aux1
            ,iif(unit = :a_unit, coalesce(aux2, :a_aux2), aux2) as aux2
        from tmp$perf_log g
        -- ::: NB ::: CORE-4483: "Changed data not visible in WHEN-section if exception occured inside SP that has been called from this code"
        -- We have to save data from tmp$perf_log for ALL units that are now in it!
        as cursor c
    do
    begin
        if ( v_cnt < v_ctx_lim ) then
            -- there is enough place in namespace to create new context vars
            -- instead of starting auton. tx (performance!)
            begin
                v_info = coalesce(c.info, '');
                -- Some unit (e.g. ) could run several times and exc`eption could occured
                --  in Nth  call of that unit (N >= 2). We must add :a_info to v_info
                -- *ONLY* if processed record in tmp$perf_log relates to that Nth call
                -- of unit (where exc`ption occured).
                -- Sample: sp_cancel_adding_invoice => create list of dependent
                -- docs, lock all of them, and then for each of these docs (reserves):
                -- sp_cancel_reserve => trigger doc_list_aiud => sp_kill_qstorno_ret_qs2qd
                if (c.unit = a_unit
                    and
                    c.exc_unit is NOT null
                ) then
                    v_info = left(v_info || trim(iif( v_info>'', '; ', '')) || coalesce(a_info,''), 255);

                if ( v_gen_inc_iter_pf = c_gen_inc_step_pf ) then -- its time to get another batch of IDs
                begin
                    v_gen_inc_iter_pf = 1;
                    -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                    v_gen_inc_last_pf = gen_id( g_perf_log, :c_gen_inc_step_pf );
                end
                v_pf_new_id = v_gen_inc_last_pf - ( c_gen_inc_step_pf - v_gen_inc_iter_pf );
                v_gen_inc_iter_pf = v_gen_inc_iter_pf + 1;

                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_ID', v_pf_new_id);    --  1
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_UNIT', c.unit);       --  2
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_GDS', c.fb_gdscode ); --  3
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_INFO', v_info);       --  4
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_XUNI', c.exc_unit);   --  5
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_XNFO', c.exc_info);   --  6
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_BEG', c.dts_beg);     --  7
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_END', c.dts_end);     --  8
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_MS', datediff(millisecond from c.dts_beg to c.dts_end));
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_AUX1', c.aux1);       -- 10
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_AUX2', c.aux2);       -- 11
                v_cnt = v_cnt + 1;
            end
        else -- it's time to "flush" data from context vars to fixed table pref_log using auton tx
            begin
                -- namespace usage should be reduced ==> flush data from context vars
                execute procedure sp_flush_tmpperf_in_auton_tx(a_starter, v_cnt, a_gdscode);
                v_cnt = 0;
            end
    end -- cursor for all rows of tmp$perf_log

    if (v_cnt > 0) then
    begin
        -- flush (again!) to perf_log data from rest of context vars (v_cnt now can be >0 and < c_limit):
        execute procedure sp_flush_tmpperf_in_auton_tx( a_starter, v_cnt, a_gdscode);
    end

    -- create new ctx in order to prevent repeat of transfer on next-level stack:
    rdb$set_context('USER_TRANSACTION', 'DONE_FLUSH_PERF_LOG_ON_ABEND','1');

end

^ -- sp_flush_perf_log_on_abend

-- STUBS for two SP, they will be defined later, need in s`p_add_to_perf_log (30.08.2014)
create or alter procedure srv_fill_mon(a_rowset bigint default null) returns(rows_added int) as
begin
  suspend;
end

^ -- srv_fill_mon (stub!)

create or alter procedure srv_fill_tmp_mon(
    a_rowset dm_idb,
    a_ignore_system_tables smallint default 1,
    a_unit dm_unit default null,
    a_info dm_info default null,
    a_gdscode int default null
)
returns(
    rows_added int
)
as begin
  suspend;
end

^ -- srv_fill_tmp_mon (stub!)

--------------------------------------------------------------------------------

create or alter procedure srv_log_mon_for_traced_units(
    a_unit dm_unit,
    a_gdscode integer default null,
    a_info dm_info default null
)
as
  declare v_rowset bigint;
  declare v_dummy bigint;
begin
    if (
         rdb$get_context('USER_SESSION', 'ENABLE_MON_QUERY') = 1
         and
         rdb$get_context('USER_SESSION','MON_UNIT_LIST') containing '/'||a_unit||'/' -- this is call from some module which we want to analyze
       ) then
    begin
        -- Gather all avaliable mon info about caller module: add pair of row sets
        -- (for beg and end) and then calculate DIFFERENCES of mon. counters with
        -- logging in tables `mon_log` and `mon_log_table_stats`.
        -- NOT work in 2.5 due to bulk of deadlocks when intensive monitoring using
        v_rowset = rdb$get_context('USER_SESSION','MON_ROWSET_'||a_unit);
        if ( v_rowset is null  ) then
            begin
                -- define context var which will identify rowset field       
                -- in mon_log and mon_log_table_stats:                       
                -- (this value is ised after call app. unit):               
                v_rowset = gen_id(g_common,1);
                rdb$set_context('USER_SESSION','MON_ROWSET_'||a_unit, v_rowset);
                -- gather mon$ tables: add FIRST row to GTT tmp$mon_log,
                -- all counters will be written as NEGATIVE values
                in autonomous transaction do
                select count(*)                                             
                from srv_fill_tmp_mon
                (                                       
                      :v_rowset -- :a_rowset
                     ,1         -- :a_ignore_system_tables
                     ,:a_unit   -- :a_unit
                )
                into v_dummy;                                                
            end
        else -- add second row to GTT, all counters will be written as POSITIVE values:
            begin
                rdb$set_context('USER_SESSION','MON_ROWSET_'||a_unit, null);
                in autonomous transaction do -- NB: add in AT both when v_abend = true / false, otherwise records in tmp$mon$log_* remains when rollback (01.09.2014)
                begin
                    select count(*)                                             
                    from srv_fill_tmp_mon
                    (:v_rowset -- :a_rowset
                     ,1        -- :a_ignore_system_tables
                     ,:a_unit
                     ,:a_info
                     ,:a_gdscode
                    ) into v_dummy;

                    -- TOTALLING mon counters for this unit:
                    -- insert into mon_log(...)
                    -- select sum(...) from tmp$mon_log t
                    -- where t.rowset = :a_rowset group by t.rowset
                    select count(*) from srv_fill_mon( :v_rowset )
                    into v_dummy;
                end

            end

    end -- engine = '3.x' and remote_process containing 'IBExpert' and ctx MON_UNIT_LIST containing '/<a_unit>/'

end

^ -- srv_log_mon_for_traced_units

create or alter procedure sp_get_test_time_dts
returns(
    test_time_dts_beg timestamp,
    test_time_dts_end timestamp,
    test_intervals int
) as
begin
   -- STUB! Will be redefined in oltp_common_sp.sql 
    suspend;
end

^ -- sp_get_test_time_dts


-------------------------------------------------------------------------------

create or alter procedure sp_add_perf_log (
    a_is_unit_beginning dm_sign,
    a_unit dm_unit,
    a_gdscode integer default null,
    a_info dm_info default null,
    a_aux1 dm_aux default null,
    a_aux2 dm_aux default null
) as
begin
    -- STUB! Actual code see in oltp_common_sp.sql
end
^ -- sp_add_perf_log  // STUB!


create or alter procedure sp_upd_in_perf_log(
    a_unit dm_unit,
    a_gdscode int default null,
    a_info dm_info default null
) as
begin
    -- STUB! Actual code see in oltp_common_sp.sql
end

^  -- sp_upd_in_perf_log // STUB!


-- stub, will be overwritten, see below:
create or alter procedure zdump4dbg(
    a_doc_list_id bigint default null,
    a_doc_data_id bigint default null,
    a_ware_id bigint default null
) as begin
  -- ::: NB ::: This SP is overwritten in script 'oltp_misc_debug.sql' which
  -- is called ONLY if config parameter 'create_with_debug_objects' is set to 1.
  -- Open oltpNN_config.*** file and change this parameter if you want this
  -- proc and some other aux tables (named with "Z_" prefix) to be created.
end

^ -- zdump4dbg // STUB!

create or alter procedure sp_add_to_abend_log(
       a_exc_info dm_info,
       a_gdscode int default null,
       a_info dm_info default null,
       a_caller dm_unit default null,
       a_halt_due_to_error smallint default 0 --  1 ==> forcely extract FULL STACK ignoring settings, because of error + halt test
) as
begin
    -- STUB! Actual code see in oltp_common_sp.sql
end

^ -- sp_add_to_abend_log

set term ;^
commit;

set term ^;

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
) as
begin
    -- STUB! Actual code see in oltp_common_sp.sql
end -- sp_check_ctx
^
set term ;^
commit;

set term ^;
create or alter procedure sp_check_nowait_or_timeout as
    declare msg varchar(255);
    declare function fn_internal() returns int deterministic as
    begin
        return rdb$get_context('SYSTEM', 'LOCK_TIMEOUT');
    end
begin
    if ( fn_remote_process() containing 'IBExpert' ) then exit; -- 4debug

    -- Must be called from all SPs which are at 'top' level of data handling.
    -- Checks that current Tx is running with NO WAIT or LOCK_TIMEOUT.
    -- Otherwise raises error
    if  ( fn_internal() < 0 ) then -- better than call every time rdb$get_context('SYSTEM', 'LOCK_TIMEOUT') up to 4 times!
    begin
        msg = 'NO WAIT or LOCK_TIMEOUT required!';
        execute procedure sp_add_to_abend_log( msg, null, null, 'sp_check_nowait_or_timeout' );
        exception ex_nowait_or_timeout_required;
    end
end
^
set term ;^
commit;

set term ^;

create or alter procedure sp_check_to_stop_work as
    declare v_dts_beg timestamp;
    declare v_dts_end timestamp;
    declare v_need_to_stop smallint;
begin
    -- Must be called from all SPs which are at 'top' level of data handling.
    -- Checks that special external *TEXT* file is EMPTY, otherwise raise exc.
    -- Script tmp_random_run.sql (generated by 1run_oltp_emul.bat) contains
    -- 'set bail on' before each call of application unit, so if here we raise
    -- ex`ception EX_TEST_CANCELLATION than script tmp_random_run.sql will be
    -- cancelledthis immediatelly. The word "EX_TEST_CANCELLATION" will appear
    -- in .err file - log of errors for each ISQL session.
    -- Batch `oltp_isql_run_worker.bat` checks .err file for this word and if it
    -- is found there - all the batch will be finished via "goto test_canc" + exit

    if ( fn_remote_process() containing 'IBExpert' ) then exit; -- 4debug; 23.07.2014

    -- 25.11.2020: do NOT use here dynamic SQL, this must be called too frequent!
    select test_time_dts_beg, test_time_dts_end
    from sp_get_test_time_dts
    into v_dts_beg, v_dts_end;

    ---------------------------------------------------------------------------

    v_need_to_stop = null;
    select p.need_to_stop from sp_stoptest p rows 1 into v_need_to_stop;

    if ( cast('now' as timestamp) > v_dts_end -- NORMAL finish because of test_time expiration
         or
         v_need_to_stop < 0 -- External force all ISQL sessions PREMATURE be stopped itself (either by running $tmpdir/1stoptest.tmp batch or by adding line to 'stoptest.txt')
       )
    then
        begin
           -- current SP = sp_check_to_stop_work
           execute procedure sp_halt_on_error('2', -1, current_transaction, :v_need_to_stop); -- '2' => NORMAL test finish due to time expiration
           -- a_char char(1) default '1',
           -- a_gdscode bigint default null,
           -- a_trn_id bigint default null,
           -- a_need_to_stop smallint default null

           -- E X C E P T I O N:  C A N C E L   T E S T
           exception ex_test_cancellation ( select result from sys_stamp_exception('ex_test_cancellation') );
        end
end

^ -- sp_check_to_stop_work 

create or alter procedure sp_init_ctx
as
    declare v_name type of dm_name;
    declare v_context type of column settings.context;
    declare v_value type of dm_setting_value;
    declare v_counter int = 0;
    declare msg varchar(255);
    declare v_working_mode varchar(80);
    declare v_use_es smallint;
begin
    -- Called from db-level trigger on CONNECT. Reads table 'settings' and
    -- assigns values to context variables (in order to avoid further DB scans).

    -- ::: NOTE ABOUT POSSIBLE PROBLEM WHEN CONNECT TO DATABASE :::
    -- On Classic installed on *nix one may get exception on connect to database
    -- with following text:
    --     Statement failed, SQLSTATE = 2F000
    --     Error while parsing procedure SP_INIT_CTX's BLR
    --     -Error while parsing procedure SP_ADD_TO_ABEND_LOG's BLR
    --     -Error while parsing procedure SP_FLUSH_PERF_LOG_ON_ABEND's BLR
    --     -I/O error during "open O_CREAT" operation for file ""
    --     -Error while trying to create file
    -- This exception is caused by TRG_CONNECT trigger on database connect event.
    -- When this trigger calls SP_INIT_CTX, which then can attempt to add data
    -- into GTT table TMP$PERF_LOG. File which must store data for this GTT
    -- is created in the folder defined by FIREBIRD_TMP env. variable.
    -- Exception will occur when this folder is undefined xinetd daemon has
    -- no rights to create files in it.
    -- SOLUTION: check script /etc/init.d/xinetd - it should contain text like:
    -- #########
    -- FIREBIRD_TMP = /tmp/firebird
    -- export FIREBIRD_TMP, ...

    if (rdb$get_context('USER_SESSION','WORKING_MODE') is null) then
    begin
        select
             max( iif(s.mcode = 'WORKING_MODE', s.svalue, null) )
            ,max( iif(s.mcode = 'USE_ES', cast(s.svalue as smallint), null) )
        from settings s
        where s.working_mode in ('INIT','COMMON') and s.mcode in ('WORKING_MODE', 'USE_ES')
        into v_working_mode, v_use_es
        ;

        if (v_working_mode is null) then
            exception ex_record_not_found -- 'required record not found, datasource: @1, key: @2'
                using('settings', 'mcode = ''WORKING_MODE''')
            ;

        if (v_use_es is null) then
            exception ex_record_not_found -- 'required record not found, datasource: @1, key: @2'
                using('settings', 'mcode = ''USE_ES''')
            ;

        rdb$set_context('USER_SESSION','WORKING_MODE', v_working_mode);

        -- 20.11.2020: the only place where 'use_es' context variable is set:
        -- #################################################
        rdb$set_context('USER_SESSION','USE_ES', v_use_es);
        -- #################################################
    end

    if ( rdb$get_context('USER_SESSION','WORKING_MODE') is not null
       and
       exists (select * from settings s
                where s.working_mode = rdb$get_context('USER_SESSION','WORKING_MODE')
              )
     ) then
    begin
        -- initializes all needed context variables (scan `setting` table)
        -- See oltpNN_config, parameter 'use_es'. Can be 0, 1 or 2:
        -- NB use static PSQL code here, do NOT change it to EDS // 20.11.2020
        for
            select upper(s.mcode), upper(s.context), s.svalue
            from settings s
            where s.context in('USER_SESSION','USER_TRANSACTION')
                  and
                  ( s.working_mode = rdb$get_context('USER_SESSION','WORKING_MODE')
                    and s.init_on = 'connect' -- 03.09.2014: exclude 'C_NUMBER_OF_AGENTS', 'C_WARES_MAX_ID' - need only in init db building
                    or
                    s.working_mode = 'COMMON'
                  )
            into
                v_name, v_context, v_value
        do begin
            rdb$set_context(v_context, v_name, v_value);
            v_counter = v_counter + 1;
        end
    end

    if (v_counter = 0 and exists (select * from settings s) ) then
    begin
        msg = 'Context variable ''WORKING_MODE'' is invalid.';
        execute procedure sp_add_to_abend_log( msg, null, null, 'sp_init_ctx' );
        exception ex_bad_working_mode_value
        using ( coalesce( '>'||rdb$get_context('USER_SESSION','WORKING_MODE')||'<', '<null>') );
        -- "-db-level trigger TRG_CONNECT: no found rows for settings.working_mode='>****<', correct it!"
    end
end

^ -- sp_init_ctx

-- STUB! Redefinition see in file oltp_misc_debug.sql
create or alter procedure z_remember_view_usage (
    a_view_for_search dm_dbobj,
    a_view_for_min_id dm_dbobj default null,
    a_view_for_max_id dm_dbobj default null
) as
    declare i smallint;
    declare v_ctxn dm_ctxnv;
    declare v_name dm_dbobj;
begin

end

^ -- z_remember_view_usage (STUB!)s

create or alter procedure sp_get_random_id (
    a_view_for_search dm_dbobj,
    a_view_for_min_id dm_dbobj default null,
    a_view_for_max_id dm_dbobj default null,
    a_raise_exc dm_sign default 1, -- raise exc`eption if no record will be found
    a_can_skip_order_clause dm_sign default 0, -- 17.07.2014 (for some views where document is taken into processing and will be REMOVED from scope of this view after Tx is committed)
    a_find_using_desc_index dm_sign default 0,  -- 11.09.2014: if 1, then query will be: "where id <= :a order by id desc"
    a_count_to_generate int default 1 -- 09.10.2015: how many values to generate and return as resultset (to reduce number of ES preparing)
)
returns (
    id_selected bigint
)
as
    declare i smallint;
    declare v_sttm_for_small_scope varchar(8192);
    declare v_sttm_for_large_scope varchar(8192);
    declare v_sttx varchar(8192);
    declare id_min double precision;
    declare id_max double precision;
    declare v_rows int;
    declare id_random bigint;
    declare v_detailed_exc_text dm_info;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'sp_get_random_id';
    declare v_ctxn dm_ctxnv;
    declare v_name dm_dbobj;
    declare fn_internal_max_rows_usage int;
    declare v_lf char(1) = x'0A';
begin
    -- Selects random record from view <a_view_for_search>
    -- using select first 1 id from ... where id >= :id_random order by id.
    -- Aux. parameters:
    -- # a_view_for_min_id and a_view_for_max_id -- separate views that
    --   might be more effective to find min & max LIMITS than scan using a_view_for_search.
    -- # a_raise_exc (default=1) - do we raise exc`eption if record not found.
    -- # a_can_skip_order_clause (default=0) - can we SKIP including of 'order by' clause
    --   in statement which will be passed to ES ? (for some cases we CAN do it for efficiency)
    -- # a_find_using_desc_index - do we construct ES for search using DESCENDING index
    --   (==> it will use "where id <= :r order by id DESC" rather than "where id >= :r order by id ASC")
    -- [only when TIL = RC] Repeats <fn_internal_retry_count()> times if result is null
    -- (possible if bounds of IDs has been changed since previous call)

    v_this = trim(a_view_for_search);

    -- max difference b`etween min_id and max_id to allow scan random id via
    -- select id from <a_view_for_search> rows :x to :y, where x = y = random_int
    -- see oltp_main_filling.sql:
    fn_internal_max_rows_usage = coalesce(cast( rdb$get_context('USER_SESSION','RANDOM_SEEK_VIA_ROWS_LIMIT') as int), 0);

    -- Use either stub or non-empty executing code (depends on was 'oltp_dump.sql' compiled or no):
    -- save fact of usage views in the table `z_used_views`:
    execute procedure z_remember_view_usage(a_view_for_search, a_view_for_min_id, a_view_for_max_id);

    a_view_for_min_id = coalesce( a_view_for_min_id, a_view_for_search );
    a_view_for_max_id = coalesce( a_view_for_max_id, a_view_for_min_id, a_view_for_search );

    if ( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN' ) is null
       or
       rdb$get_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX' ) is null
     ) then
        begin
            -- v`iew can be used to see average, min and max elapsed time
            -- of this sttm:
            execute procedure sp_add_perf_log(1, a_view_for_min_id );

            /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
            v_sttx =
            q'{ execute block returns(id_min double precision) as
                begin
                    -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                    -- NOTE: we have to log timestamp of point just BEFORE query that
                    -- will work: datediff between this point and next firing of
                    -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                    -- of IDLE state for this connect in the Ext. Conn. Pool.
                    execute procedure sp_perf_eds_logging('B');
                    select min(id)-0.5 -- #EDS#TAG#
            }'
            || '    from ' || a_view_for_min_id || v_lf
            || '    into id_min;' || v_lf
            || q'{
                -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                -- for connect, so there we have TWO events: 'I' and 'A').
                --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
                }' || v_lf
            || '    suspend;' ||v_lf
            || 'end'
            ;
            -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

            -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
            -- Usual way: use ES without EDS
            v_sttx='select min(id)-0.5 from '|| a_view_for_min_id;
            -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

            execute statement (:v_sttx)
            -- 20.11.2020
            -- If config parameter USE_ES is 2 then following line will be
            -- replaced with uncommented code for run as ES/EDS.
            -- Host and port will be taken from apropriate config parameters.
            -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
            -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
            into id_min;
    
            execute procedure sp_add_perf_log(0, a_view_for_min_id, null, 'id_min='||coalesce(id_min,'<?>') );
    
            if ( id_min is NOT null ) then -- ==> source <a_view_for_min_id> is NOT empty
            begin
                -- v`iew may be used to see average, min and max elapsed time
                -- of this sttm:
                execute procedure sp_add_perf_log(1, a_view_for_max_id );
    
                /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
                v_sttm_for_small_scope =
                q'{ execute block returns(id_max double precision) as
                    begin
                        -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                        -- NOTE: we have to log timestamp of point just BEFORE query that
                        -- will work: datediff between this point and next firing of
                        -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                        -- of IDLE state for this connect in the Ext. Conn. Pool.
                        execute procedure sp_perf_eds_logging('B');
                        select max(id)+0.5 -- #EDS#TAG#
                }'
                || '    from ' || a_view_for_max_id || v_lf
                || '    into id_max;' || v_lf
                || q'{
                    -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                    -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                    -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                    -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                    -- for connect, so there we have TWO events: 'I' and 'A').
                    --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
                    }' || v_lf
                || '    suspend;' ||v_lf
                || 'end'
                ;
                -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

                -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
                -- Usual way: use ES without EDS
                v_sttm_for_small_scope='select max(id)+0.5 from '|| a_view_for_max_id;
                -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

                execute statement (:v_sttm_for_small_scope)
                -- 20.11.2020
                -- If config parameter USE_ES is 2 then following line will be
                -- replaced with uncommented code for run as ES/EDS.
                -- Host and port will be taken from apropriate config parameters.
                -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
                -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
                into id_max;
    
                execute procedure sp_add_perf_log(0, a_view_for_max_id, null, 'id_max='||coalesce(id_max,'<?>') );
    
                if ( id_max is NOT null  ) then -- ==> source <a_view_for_max_id> is NOT empty
                begin
                    -- Save values for subsequent calls of this func in this tx (minimize DB access)
                    -- (limit will never change in SNAPSHOT and can change with low probability in RC):
                    rdb$set_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN', :id_min);
                    rdb$set_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX', :id_max);
            
                    if ( id_max - id_min < fn_internal_max_rows_usage ) then
                    begin
                        -- when difference betwn id_min and id_max is not too high, we can simple count rows:

                        /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
                        v_sttm_for_small_scope =
                        q'{ execute block returns(v_rows int) as
                            begin
                                -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                                -- NOTE: we have to log timestamp of point just BEFORE query that
                                -- will work: datediff between this point and next firing of
                                -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                                -- of IDLE state for this connect in the Ext. Conn. Pool.
                                execute procedure sp_perf_eds_logging('B');
                                select count(*) -- #EDS#TAG#
                        }'
                        || '    from ' || a_view_for_search || v_lf
                        || '    into v_rows;' || v_lf
                        || '    suspend;' ||v_lf
                        || q'{
                            -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                            -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                            -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                            -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                            -- for connect, so there we have TWO events: 'I' and 'A').
                            --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
                            }' || v_lf
                        || 'end'
                        ;
                        -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

                        -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
                        -- Usual way: use ES without EDS
                        v_sttm_for_small_scope = 'select count(*) from '||a_view_for_search;
                        -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

                        execute statement (:v_sttm_for_small_scope)
                        -- 20.11.2020
                        -- If config parameter USE_ES is 2 then following line will be
                        -- replaced with uncommented code for run as ES/EDS.
                        -- Host and port will be taken from apropriate config parameters.
                        -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
                        -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
                        into v_rows;
                        rdb$set_context('USER_TRANSACTION', upper(:a_view_for_search)||'_COUNT', v_rows );
                    end
                end -- id_max is NOT null 
            end -- id_min is NOT null
        end
    else
        begin
            -- minimize database access! Performance on 10'000 loops: 1485 ==> 590 ms
            id_min=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN' ) as double precision);
            id_max=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX' ) as double precision);
            v_rows=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_search)||'_COUNT') as int);
        end

    --#############################################################################################################
    --#############################################################################################################
    --#############################################################################################################

    if ( id_max - id_min < fn_internal_max_rows_usage ) then
        begin
           -- select * from ... offset N rows fetch first 1 row only;
            -- ::: nb ::: `ORDER` clause not needed here!
            /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
            v_sttm_for_small_scope =
            q'{ execute block ( random_skip_rows_count int = ?) returns ( id_selected bigint ) as
                begin
                    -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                    -- NOTE: we have to log timestamp of point just BEFORE query that
                    -- will work: datediff between this point and next firing of
                    -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                    -- of IDLE state for this connect in the Ext. Conn. Pool.
                    execute procedure sp_perf_eds_logging('B');
                    select id -- #EDS#TAG#
            }'
            || '    from ' || a_view_for_search || v_lf
            || '    offset :random_skip_rows_count rows fetch first 1 row only' || v_lf
            || '    into id_selected;' || v_lf
            || q'{
                    -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                    -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                    -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                    -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                    -- for connect, so there we have TWO events: 'I' and 'A').
                    --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
                }' || v_lf
            || '    suspend;' ||v_lf
            || 'end'
            ;
            -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

            -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
            -- Usual way: use ES without EDS
            v_sttm_for_small_scope='select id from '||a_view_for_search||' offset ? rows fetch first 1 row only';
            -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */
        end
    else
        begin
            -- 17.07.2014: for some cases it is ALLOWED to query random ID without "ORDER BY"
            -- clause because this ID will be handled in such manner that it will be REMOVED
            -- after this handling from the scope of view! Samples of such cases are:
            -- sp_cancel_supplier_order, sp_cancel_supplier_invoice, sp_cancel_customer_reserve

            /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
            v_sttx = 'select id -- #EDS#TAG#' || v_lf
                || ' from ' || a_view_for_search || v_lf
                ||iif( a_find_using_desc_index = 0
                       , ' where id >= :randomly_selected_id ' -- separate expr for ASCENDING index
                       , ' where id <= :randomly_selected_id ' -- separate expr for DESCENDING index
                     );
            -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

            -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
            v_sttx = 'select id' || v_lf
                || ' from ' || a_view_for_search || v_lf
                ||iif( a_find_using_desc_index = 0
                       , ' where id >= ? ' -- separate expr for ASCENDING index
                       , ' where id <= ? ' -- separate expr for DESCENDING index
                     );
            -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

            if ( a_can_skip_order_clause = 0 ) then
                v_sttx = v_sttx || v_lf
                    || trim(iif(a_find_using_desc_index = 0, 'order by id', 'order by id desc'));
            v_sttx = v_sttx || ' rows 1';

            /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
            v_sttm_for_large_scope =
            q'{ execute block ( randomly_selected_id bigint = ?) returns ( id_selected bigint ) as
                begin
                    -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
                    -- NOTE: we have to log timestamp of point just BEFORE query that
                    -- will work: datediff between this point and next firing of
                    -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
                    -- of IDLE state for this connect in the Ext. Conn. Pool.
                    execute procedure sp_perf_eds_logging('B');
            }' || v_lf
            || '    ' || v_sttx || v_lf
            || '    into id_selected;' || v_lf
            || q'{
                    -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
                    -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
                    -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
                    -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
                    -- for connect, so there we have TWO events: 'I' and 'A').
                    --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
                }' || v_lf
            || '    suspend;' ||v_lf
            || 'end'
            ;
            -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

            -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
            -- Usual way: use ES without EDS
            v_sttm_for_large_scope = v_sttx;
            -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

        end

    i = a_count_to_generate;
    while ( i > 0 ) do
    begin
        id_selected = null;
        if ( id_max - id_min < fn_internal_max_rows_usage ) then
            begin
                -- id_random = ceiling( rand() * v_rows );
                id_random = floor( rand() * v_rows );
                rdb$set_context('USER_SESSION','DBG_Q4SMALL', coalesce(v_sttm_for_small_scope,'[null]'));
                execute statement (:v_sttm_for_small_scope) ( id_random )
                -- 20.11.2020
                -- If config parameter USE_ES is 2 then following line will be
                -- replaced with uncommented code for run as ES/EDS.
                -- Host and port will be taken from apropriate config parameters.
                -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
                -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
                into id_selected;
            end
        else
            begin
                id_random = cast( id_min + rand() * (id_max - id_min) as bigint);
                rdb$set_context('USER_SESSION','DBG_Q4LARGE', coalesce(v_sttm_for_large_scope,'[null]'));
                execute statement (:v_sttm_for_large_scope) ( id_random )
                -- 20.11.2020
                -- If config parameter USE_ES is 2 then following line will be
                -- replaced with uncommented code for run as ES/EDS.
                -- Host and port will be taken from apropriate config parameters.
                -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
                -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
                into id_selected;
            end


        if ( id_selected is null and coalesce(a_raise_exc, 1) = 1 ) then
            begin
        
                v_info = 'view: '||:a_view_for_search;
                if ( id_min is NOT null ) then
                   v_info = v_info || ', id_min=' || id_min || ', id_max='||id_max;
                else
                   v_info = v_info || ' - EMPTY';
        
                v_info = v_info ||', id_rnd='||coalesce(id_random,'<null>');
        
                -- 19.07.2014: 'no id >= @1 in @2 found in @3 within scope @4 ... @5';
                v_detailed_exc_text = 'no id >= ' || coalesce(id_random,'<?>') || ' found in ''' || a_view_for_search || ''' within scope ' || coalesce(id_min,'<?>') || ' ... ' || coalesce(id_max,'<?>');
                exception ex_can_not_select_random_id ( select result from sys_stamp_exception('ex_can_not_select_random_id', :v_detailed_exc_text) );

            end
        else
            suspend;

        i = i - 1;
    end

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '', -- before 25.11.2020: v_stt,
            gdscode,
            v_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_get_random_id

create or alter procedure sp_lock_selected_doc(
    doc_list_id type of dm_idb,
    a_view_for_search dm_dbobj, --  'v_reserve_write_off',
    a_selected_doc_id type of dm_idb default null
) as
    declare v_dbkey dm_dbkey = null;
    declare v_id dm_idb;
    declare v_sttx varchar(255);
    declare v_sttm varchar(8192);
    declare v_exc_info dm_info;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'sp_lock_selected_doc';
    declare v_lf char(1) = x'0A';
begin
    -- Seeks record in doc_list with checking existence
    -- of this ID in a_view_for_search (if need).
    -- Raises exc if not found, otherwise tries to lock this record.

    v_info = 'doc_id='||coalesce(doc_list_id, '<?>')||', src='||a_view_for_search;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    v_sttx = 'select h.rdb$db_key from doc_list h where h.id = :a_doc_to_find';
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

    -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
    v_sttx = 'select h.rdb$db_key from doc_list h where h.id = ?';
    -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

    if ( a_selected_doc_id is NOT null ) then
        v_sttx = v_sttx ||' and exists(select 1 from '||a_view_for_search||' v where v.id = h.id) ';

    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    -- use_es = 2 --> run this statement via ES/EDS in order to see
    -- how External Connections Pool affects on performance
    v_sttm =
    q'{ execute block( a_doc_to_find bigint = ? ) returns( doc_dbkey dm_dbkey ) as
        begin
            -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
            -- NOTE: we have to log timestamp of point just BEFORE query that
            -- will work: datediff between this point and next firing of
            -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
            -- of IDLE state for this connect in the Ext. Conn. Pool.
            execute procedure sp_perf_eds_logging('B');
    }' || v_lf
            || v_sttx || v_lf
            || '    into doc_dbkey;' || v_lf
            || '    suspend;' || v_lf
    || q'{
            -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
            -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
            -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
            -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
            -- for connect, so there we have TWO events: 'I' and 'A').
            --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
         }' || v_lf
    ||  'end' ;
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

    -- #ACTIVATE#IF#USE_ES_NEQ_2#BEG#
    v_sttm = v_sttx;
    -- #ACTIVATE#IF#USE_ES_NEQ_2#END# */

    execute statement ( v_sttm ) ( doc_list_id )
    -- 20.11.2020
    -- If config parameter USE_ES is 2 then following line will be
    -- replaced with uncommented code for run as ES/EDS.
    -- Host and port will be taken from apropriate config parameters.
    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
    -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
    into v_dbkey;

    if ( v_dbkey is null ) then
    begin
        -- no document found for handling in datasource = ''@1'' with id=@2';
        exception ex_no_doc_found_for_handling using( a_view_for_search, :doc_list_id );
    end
    rdb$set_context('USER_SESSION','ADD_INFO','doc='||v_id||': try to lock'); -- to be displayed in log of 1run_oltp_emul.bat

    select id from doc_list h
    where h.rdb$db_key = :v_dbkey
    for update with lock
    into v_id; -- trace rows: deadlock; update conflicts with conc.; 335544878 conc tran number is ...; at proc <this>
    rdb$set_context('USER_SESSION','ADD_INFO','doc='||v_id||': captured Ok'); -- to be displayed in log of 1run_oltp_emul.bat

    execute procedure sp_add_perf_log(0, v_this);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log( '', gdscode, v_info, v_this );
        --########
        exception; -- all number of retries exceeded: raise concurrent_transaction OR deadlock
        --########
    end
end

^ -- sp_lock_selected_doc

set term ;^
commit;


-- STUB, need for sp_multiply_rows_for_qdistr; will be redefined after (see below):
create or alter view v_our_firm as select 1 id from rdb$database
;

-- Views for usage in procedure s~p_multiply_rows_for_qdistr.
-- Their definition will be REPLACED with 'select * from XQD_1000_1200' and
-- 'select * from XQD_1000_3300' if config 'create_with_split_heavy_tabs' = 1

create or alter view v_qdistr_multiply_1 as
select * from qdistr
;

create or alter view v_qdistr_multiply_2 as
select * from qdistr
;

-- Updatable views (one-to-one data projections) for handling rows in heavy loaded
-- tables QDistr/QStorned (or in XQD_*, XQS_* when config par. create_with_split_heavy_tabs = 1):
-- See usage in SP_KILL_QSTORNO_RET_QS2QD and also in redirection procedures that
-- can be replaced when 'create_with_split_heavy_tabs=1':
-- sp_ret_qs2qd_on_canc_wroff, sp_ret_qs2qd_on_canc_reserve,
-- sp_ret_qs2qd_on_canc_invoice, sp_ret_qs2qd_on_canc_supp_order

create or alter view v_qdistr_source_1 as
select *
from qdistr
;

create or alter view v_qdistr_source_2 as
select *
from qdistr
;

create or alter view v_qdistr_target_1 as
select *
from qdistr
;

create or alter view v_qdistr_target_2 as
select *
from qdistr
;

create or alter view v_qstorned_target_1 as
select *
from qstorned
;

create or alter view v_qstorned_target_2 as
select *
from qstorned
;

create or alter view v_qdistr_name_for_del as
select *
from qdistr
;

create or alter view v_qdistr_name_for_ins as
select *
from qdistr
;

create or alter view v_qstorno_name_for_del as
select *
from qstorned
;

create or alter view v_qstorno_name_for_ins as
select *
from qstorned
;

commit;

set term ^;
create or alter procedure sp_multiply_rows_for_qdistr(
    a_doc_list_id dm_idb,
    a_optype_id dm_idb,
    a_clo_for_our_firm dm_idb,
    a_qty_sum dm_qty
) as
    declare c_gen_inc_step_qd int = 100; -- size of `batch` for get at once new IDs for QDistr (reduce lock-contention of gen page)
    declare v_gen_inc_iter_qd int; -- increments from 1  up to c_gen_inc_step_qd and then restarts again from 1
    declare v_gen_inc_last_qd dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_qd)
    declare v_doc_data_id dm_idb;
    declare v_ware_id dm_idb;
    declare v_qty_for_distr dm_qty;
    declare v_purchase_for_distr type of dm_cost;
    declare v_retail_for_distr type of dm_cost;
    declare v_rcv_optype_id type of dm_idb;
    declare n_rows_to_add int;
    declare v_qty_for_one_row type of dm_qty;
    declare v_purchase_for_one_row type of dm_cost;
    declare v_retail_for_one_row type of dm_cost;
    declare v_qty_acc type of dm_qty;
    declare v_purchase_acc type of dm_cost;
    declare v_retail_acc type of dm_cost;
    declare v_dbkey dm_dbkey;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'sp_multiply_rows_for_qdistr';
    declare v_storno_sub smallint;
    declare v_worker_id int;
    declare v_lf char(1) = x'0A';
begin
    -- Performs "value-to-rows" filling of QDISTR table: add rows which
    -- later will be "storned" (removed from qdistr to qstorned)

    v_info = 'dh='||a_doc_list_id||', q_sum='||a_qty_sum;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    v_gen_inc_iter_qd = 1;
    c_gen_inc_step_qd = (1 + a_qty_sum) * iif(a_clo_for_our_firm=1, 1, 2) + 1;
    -- take bulk IDs at once (reduce lock-contention for GEN page):
    v_gen_inc_last_qd = gen_id( g_qdistr, :c_gen_inc_step_qd );
    v_worker_id = fn_this_worker_seq_no();
    -- Cursor: how many distributions must be done for this doc if it is "sender" ?
    -- =2 for customer order (if agent <> our firm!!):
    --    it will be storned by stock order
    --    and later by customer reserve
    -- =1 for all other operations:
    for
        select r.rcv_optype_id, c.snd_id, c.id as ware_id, c.qty, c.cost_purchase, c.cost_retail, r.storno_sub
        from v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
        cross join tmp$shopping_cart c
        where
            r.snd_optype_id = :a_optype_id
            and (
                :a_clo_for_our_firm = 0
                or
                -- do NOT multiply rows for rcv_op = 'RES' if current doc = client order for OUR firm!
                :a_clo_for_our_firm = 1 and r.rcv_optype_id <> 3300 -- 4speed; do not call fn_oper_retail_reserve every time
            )
        into v_rcv_optype_id, v_doc_data_id, v_ware_id, v_qty_for_distr, v_purchase_for_distr, v_retail_for_distr, v_storno_sub
    do
    begin
        v_qty_acc = 0;
        v_purchase_acc = 0;
        v_retail_acc = 0;
        n_rows_to_add = ceiling( v_qty_for_distr );
        while( n_rows_to_add > 0 ) do
        begin
            v_qty_for_one_row = iif( n_rows_to_add > v_qty_for_distr, n_rows_to_add - v_qty_for_distr, 1 );
            v_purchase_for_one_row = v_purchase_for_distr * v_qty_for_one_row / v_qty_for_distr;
            v_retail_for_one_row = v_retail_for_distr * v_qty_for_one_row / v_qty_for_distr;
            /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
            execute statement (
                'insert into ' || iif(v_storno_sub = 1, 'v_qdistr_multiply_1', 'v_qdistr_multiply_2')
                || '('
                || '  id'              --   1
                || '  ,doc_id'         --   2
                || '  ,worker_id'      --   3
                || '  ,ware_id'        --   4
                || '  ,snd_optype_id'  --   5
                || '  ,rcv_optype_id'  --   6
                || '  ,snd_id'         --   7
                || '  ,snd_qty'        --   8
                || '  ,snd_purchase'   --   9
                || '  ,snd_retail'     --  10
                || ') values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )'
                || ' returning rdb$db_key'
            )
            (
                :v_gen_inc_last_qd - ( :c_gen_inc_step_qd - :v_gen_inc_iter_qd ) -- 1
                ,:a_doc_list_id          --  2
                ,:v_worker_id            --  3
                ,:v_ware_id              --  4
                ,:a_optype_id            --  5
                ,:v_rcv_optype_id        --  6
                ,:v_doc_data_id          --  7
                ,:v_qty_for_one_row      --  8
                ,:v_purchase_for_one_row --  9
                ,:v_retail_for_one_row   -- 10
            )
            -- DO NOT use EDS here! All changes must be within the same tx !
            into v_dbkey
            ;
            v_qty_acc = v_qty_acc + v_qty_for_one_row;
            v_purchase_acc = v_purchase_acc + v_purchase_for_one_row;
            v_retail_acc = v_retail_acc + v_retail_for_one_row;
            -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */

            -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
            -- usual way (use_es = 0): use static PSQL code.
            if ( v_storno_sub = 1 ) then
                insert into v_qdistr_multiply_1 (
                    id
                    ,doc_id
                    ,worker_id
                    ,ware_id
                    ,snd_optype_id
                    ,rcv_optype_id
                    ,snd_id
                    ,snd_qty
                    ,snd_purchase
                    ,snd_retail
                ) values(
                    :v_gen_inc_last_qd - ( :c_gen_inc_step_qd - :v_gen_inc_iter_qd )
                    ,:a_doc_list_id
                    ,:v_worker_id
                    ,:v_ware_id
                    ,:a_optype_id
                    ,:v_rcv_optype_id
                    ,:v_doc_data_id
                    ,:v_qty_for_one_row
                    ,:v_purchase_for_one_row
                    ,:v_retail_for_one_row
                )
                returning
                    rdb$db_key,
                    :v_qty_acc + snd_qty,
                    :v_purchase_acc + snd_purchase,
                    :v_retail_acc + snd_retail
                into
                    v_dbkey,
                    :v_qty_acc,
                    :v_purchase_acc,
                    :v_retail_acc
                ;
            else
                insert into v_qdistr_multiply_2 (
                    id
                    ,doc_id
                    ,worker_id
                    ,ware_id
                    ,snd_optype_id
                    ,rcv_optype_id
                    ,snd_id
                    ,snd_qty
                    ,snd_purchase
                    ,snd_retail
                ) values(
                    :v_gen_inc_last_qd - ( :c_gen_inc_step_qd - :v_gen_inc_iter_qd )
                    ,:a_doc_list_id
                    ,:v_worker_id
                    ,:v_ware_id
                    ,:a_optype_id
                    ,:v_rcv_optype_id
                    ,:v_doc_data_id
                    ,:v_qty_for_one_row
                    ,:v_purchase_for_one_row
                    ,:v_retail_for_one_row
                )
                returning
                    rdb$db_key,
                    :v_qty_acc + snd_qty,
                    :v_purchase_acc + snd_purchase,
                    :v_retail_acc + snd_retail
                into
                    v_dbkey,
                    :v_qty_acc,
                    :v_purchase_acc,
                    :v_retail_acc
                ;
            -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

            n_rows_to_add = n_rows_to_add - 1;
            v_gen_inc_iter_qd = v_gen_inc_iter_qd + 1;

            if ( n_rows_to_add = 0 and
                 ( v_qty_acc <> v_qty_for_distr
                   or v_purchase_acc <> v_purchase_for_distr
                   or v_retail_acc <> v_retail_for_distr
                 )
               ) then
                /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
                execute statement (
                    'update ' || iif(v_storno_sub = 1, 'v_qdistr_multiply_1', 'v_qdistr_multiply_2') || ' q set '
                    || '   q.snd_qty = q.snd_qty + ? '            -- 1
                    || '   ,q.snd_purchase = q.snd_purchase + ? ' -- 2
                    || '   ,q.snd_retail = q.snd_retail + ? '     -- 3
                    || ' where q.rdb$db_key = ? '                 -- 4
                )
                (
                    v_qty_for_distr - v_qty_acc           -- 1
                   ,v_purchase_for_distr - v_purchase_acc -- 2
                   ,v_retail_for_distr - v_retail_acc     -- 3
                   ,v_dbkey                               -- 4
                )
                -- DO NOT use EDS here! All changes must be within the same tx !
                ;
                -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */

                -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
                -- usual way (use_es = 0): use static PSQL code.
                begin
                    if ( v_storno_sub = 1 ) then
                        update v_qdistr_multiply_1 q set
                            q.snd_qty = q.snd_qty + ( :v_qty_for_distr - :v_qty_acc ),
                            q.snd_purchase = q.snd_purchase + ( :v_purchase_for_distr - :v_purchase_acc ),
                            q.snd_retail = q.snd_retail + ( :v_retail_for_distr - :v_retail_acc )
                        where q.rdb$db_key = :v_dbkey;
                    else
                        update v_qdistr_multiply_2 q set
                            q.snd_qty = q.snd_qty + ( :v_qty_for_distr - :v_qty_acc ),
                            q.snd_purchase = q.snd_purchase + ( :v_purchase_for_distr - :v_purchase_acc ),
                            q.snd_retail = q.snd_retail + ( :v_retail_for_distr - :v_retail_acc )
                        where q.rdb$db_key = :v_dbkey;
                end
                -- #ACTIVATE#IF#USE_ES_EQU_0#END# */
            else
                if ( v_gen_inc_iter_qd = c_gen_inc_step_qd ) then -- its time to get another batch of IDs
                begin
                    v_gen_inc_iter_qd = 1;
                    -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                    v_gen_inc_last_qd = gen_id( g_qdistr, :c_gen_inc_step_qd );
                end
        end -- while( n_rows_to_add > 0 )
    end -- cursor on doc_data cross join v_rules_for_qdistr

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^   -- sp_multiply_rows_for_qdistr

create or alter procedure sp_multiply_rows_for_pdistr(
    a_doc_list_id dm_idb,
    a_agent_id dm_idb,
    a_optype_id dm_idb,
    a_cost_for_distr type of dm_cost
) as
    declare v_rcv_optype_id type of dm_idb;
    declare n_rows_to_add int;
    declare v_dbkey dm_dbkey;
    declare v_cost_acc type of dm_cost;
    declare v_cost_for_one_row type of dm_cost;
    declare v_cost_div int;
    declare v_id dm_idb;
    declare v_worker_id int;
    declare v_key type of dm_unit;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'sp_multiply_rows_for_pdistr';
    declare function fn_internal_min_cost_4_split returns int deterministic as
    begin
        return cast(rdb$get_context('USER_SESSION', 'C_MIN_COST_TO_BE_SPLITTED' ) as int);
    end
    declare v_lf char(1) = x'0A';
begin
    -- Performs "cost-to-rows" filling of PDISTR table: add rows which
    -- later will be "storned" (removed from pdistr to pstorned)
    v_info = 'dh='||a_doc_list_id||', op='||a_optype_id||', $='||a_cost_for_distr;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);
    v_worker_id = fn_this_worker_seq_no();

    for
        select r.rcv_optype_id, iif( :a_cost_for_distr < fn_internal_min_cost_4_split(), 1, r.rows_to_multiply )
        from v_rules_for_pdistr r -- 29.03.2019: replaced with view in order to remove dependencies
        where r.snd_optype_id = :a_optype_id
        into v_rcv_optype_id, n_rows_to_add
    do
    begin
        v_cost_acc = 0;
        v_cost_div = round( a_cost_for_distr / n_rows_to_add, -2 ); -- round to handreds
        while( v_cost_acc < a_cost_for_distr ) do
        begin
            v_cost_for_one_row = iif( a_cost_for_distr > v_cost_div, v_cost_div, a_cost_for_distr );
            /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
            execute statement (
                'insert into pdistr('
                || ' agent_id'       -- 1
                || ' ,snd_optype_id' -- 2
                || ' ,snd_id'        -- 3
                || ' ,worker_id'     -- 4
                || ' ,snd_cost'      -- 5
                || ' ,rcv_optype_id' -- 6
                || ') values( ?, ?, ?, ?, ?, ? )'
                || ' returning rdb$db_key'
            )
            (
                a_agent_id          -- 1
                ,a_optype_id        -- 2
                ,a_doc_list_id      -- 3
                ,v_worker_id        -- 4
                ,v_cost_for_one_row -- 5
                ,v_rcv_optype_id    -- 6
            )
            -- DO NOT use EDS here! All changes must be within the same tx !
            into v_dbkey;

            v_cost_acc = v_cost_acc + v_cost_for_one_row;

            if ( v_cost_acc > a_cost_for_distr ) then
                execute statement (
                 'update -- #EDS#TAG#' || v_lf
                 || ' pdistr p set p.snd_cost = p.snd_cost + ? ' -- 1
                 || ' where p.rdb$db_key = ?'                    -- 2
                )
                (  a_cost_for_distr - v_cost_acc -- 1
                  ,v_dbkey                       -- 2
                )
                -- DO NOT use EDS here! All changes must be within the same tx !
                ;
            -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */

            -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
            -- usual way (use_es = 0): use static PSQL code.
            insert into pdistr(
                agent_id,
                snd_optype_id,
                snd_id,
                worker_id,
                snd_cost,
                rcv_optype_id
            )
            values(
                :a_agent_id,
                :a_optype_id,
                :a_doc_list_id,
                :v_worker_id,
                :v_cost_for_one_row,
                :v_rcv_optype_id
            )
            returning
                rdb$db_key,
                :v_cost_acc + snd_cost
            into
                v_dbkey,
                :v_cost_acc
            ;
            if ( v_cost_acc > a_cost_for_distr ) then
               update pdistr p set
                   p.snd_cost = p.snd_cost + ( :a_cost_for_distr - :v_cost_acc )
               where p.rdb$db_key = :v_dbkey;
            -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

        end
    end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^   -- sp_multiply_rows_for_pdistr

create or alter procedure sp_make_cost_storno(
    a_doc_id dm_idb, -- sp_add_invoice_to_stock: invoice_id;  sp_reserve_write_off: reserve_id
    a_optype_id dm_idb,
    a_agent_id dm_idb,
    a_cost_diff dm_cost
)
as
    declare v_pass smallint;
    declare not_storned_cost type of dm_cost;
    declare v_storned_cost type of dm_cost;
    declare v_storned_acc type of dm_cost;
    declare v_storned_doc_optype_id type of dm_idb;
    declare v_this dm_dbobj = 'sp_make_cost_storno';
    declare v_rows int = 0;
    declare v_lock int = 0;
    declare v_skip int = 0;
    declare v_sign dm_sign;
    declare v_lf char(1) = x'0A';
begin
    -- Performs attempt to make storno of:
    -- 1) payment docs by cost of stock document which state is changed
    --    to "closed"(sp_add_invoice_to_stock or sp_reserve_write_off)
    -- 2) old stock documents when adding new payment (sp_pay_from_customer, sp_pay_to_supplier)
    -- ::: nb ::: If record in "source" table (pdistr) can`t be locked - SKIP it
    -- and try to lock next one (in order to reduce number of lock conflicts)

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    v_storned_acc = 0;
    v_pass = 1;
    v_sign = iif( bin_and(current_transaction, 1)=0, 1, -1);

    while ( v_pass <= 2 ) do
    begin
        select r.snd_optype_id -- iif( :v_pass=1, r.snd_optype_id, r.rcv_optype_id )
        from v_rules_for_pdistr r -- 29.03.2019: replaced with view in order to remove dependencies
        where iif( :v_pass = 1, r.rcv_optype_id, r.snd_optype_id ) = :a_optype_id
        into v_storned_doc_optype_id; -- sp_add_invoice_to_stock ==> v_storned_doc_optype_id = fn_oper_pay_to_supplier()
    
        not_storned_cost = iif( v_pass=1, :a_cost_diff, v_storned_acc);

        if ( not_storned_cost <= 0 ) then leave;

        for
            select
                p.rdb$db_key as dbkey,
                p.id,
                p.agent_id,
                p.snd_optype_id,
                p.snd_id,
                p.worker_id,
                p.snd_cost as cost_to_be_storned,
                p.rcv_optype_id,
                :a_doc_id as rcv_id
            from pdistr p
            where
                p.agent_id = :a_agent_id
                and p.snd_optype_id = :v_storned_doc_optype_id
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and p.worker_id is not distinct from fn_this_worker_seq_no()
            order by
                p.snd_id+0 -- 23.07.2014: PLAN SORT (P INDEX (PDISTR_AGENT_ID)
                ,:v_sign * p.id -- attempt to reduce lock conflicts: odd and even Tx handling the same doc must have a chance do not encounter locked rows at all
            --order by p.id (wrong if new pdistr.id is generated via sequence when records returns from pstorned)
            as cursor c
        do
        begin
            v_rows = v_rows + 1;

            -- 26.10.2015. Additional begin..end block needs for providing DML
            -- 'atomicity' of BOTH tables pdistr & pstorned! Otherwise changes
            -- can become inconsistent if online validation will catch table-2
            -- after this code finish changes on table-1 but BEFORE it will
            -- start to change table-2.
            -- See CORE-4973 (example of WRONG code which did not used this addi block!)
            begin

                -- Explicitly lock record; skip to next if it is already locked
                -- (see below `when` section: supress all lock_conflict kind exc)
                -- benchmark: sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1108762&msg=16393721
                update pdistr set id = id where current of c; -- faster than 'where rdb$db_key = ...'
    
                v_storned_cost = minvalue( :not_storned_cost, c.cost_to_be_storned );
        
                -- move into `storage` table *PART* of prepayment that is now storned
                -- by just created customer reserve:
                -- :: nb :: pstorned PK = (id, rcv_id) - compound!
                if ( v_pass = 1 ) then

                begin
                    /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
                    execute statement (
                        'insert into pstorned( '
                        || ' agent_id'        -- 1
                        || ' ,snd_optype_id'  -- 2
                        || ' ,snd_id'         -- 3
                        || ' ,worker_id'      -- 4
                        || ' ,snd_cost'       -- 5
                        || ' ,rcv_optype_id'  -- 6
                        || ' ,rcv_id'         -- 7
                        || ' ,rcv_cost'       -- 8
                        || ') values ( ?, ?, ?, ?, ?, ?, ?, ? )'
                    )
                    (
                        c.agent_id        -- 1
                        ,c.snd_optype_id  -- 2
                        ,c.snd_id         -- 3
                        ,c.worker_id      -- 4
                        ,:v_storned_cost  -- 5
                        ,c.rcv_optype_id  -- 6
                        ,c.rcv_id         -- 7
                        ,:v_storned_cost  -- 8
                    )
                    -- DO NOT use EDS here! All changes must be within the same tx !
                    ;
                    -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */
        
                    -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
                    -- usual way (use_es = 0): use static PSQL code.
                    insert into pstorned(
                        agent_id       -- 1
                        ,snd_optype_id -- 2
                        ,snd_id        -- 3
                        ,worker_id     -- 4
                        ,snd_cost      -- 5
                        ,rcv_optype_id -- 6
                        ,rcv_id        -- 7
                        ,rcv_cost      -- 8
                    )
                    values(
                        c.agent_id       -- 1
                        ,c.snd_optype_id -- 2
                        ,c.snd_id        -- 3
                        ,c.worker_id     -- 4
                        ,:v_storned_cost -- 5
                        ,c.rcv_optype_id -- 6
                        ,c.rcv_id        -- 7
                        ,:v_storned_cost -- 8
                    );
                    -- #ACTIVATE#IF#USE_ES_EQU_0#END# */
                end
    
                if ( c.cost_to_be_storned = v_storned_cost ) then
                    delete from pdistr p where current of c;
                else
                    -- leave this record for futher storning (it has rest of cost > 0!):
                    update pdistr p set p.snd_cost = p.snd_cost - :v_storned_cost where current of c;
        
                not_storned_cost = not_storned_cost - v_storned_cost;
                v_lock = v_lock + 1;
    
                if ( v_pass = 1 ) then
                    v_storned_acc = v_storned_acc + v_storned_cost; -- used in v_pass = 2
    
                if ( not_storned_cost <= 0 ) then leave;
            end -- atomicity of changes several tables (CORE-4973!)
        when any do
            -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
            -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
            -- catched it's kind of exception!
            -- 1) tracker.firebirdsql.org/browse/CORE-3275
            --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
            -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
            begin
                if ( fn_is_lock_trouble( gdscode ) ) then
                    -- suppress this exc! we'll skip to next row of pdistr
                    v_skip = v_skip + 1;
                else -- some other ex`ception
                    --#######
                    exception;  -- ::: nb ::: anonimous but in when-block!
                    --#######
            end

        end -- cursor on pdistr
    
        v_pass = v_pass + 1;
    end -- v_pass=1..2

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(
        0,
        v_this,
        null,
        'dh='||coalesce(:a_doc_id,'<?>')
        ||', pd ('||iif(:v_sign=1,'asc','dec')||'): capt='||:v_lock||', skip='||:v_skip||', scan='||:v_rows
    );

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||a_doc_id,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^ -- sp_make_cost_storno

create or alter procedure sp_kill_cost_storno( a_deleted_or_cancelled_doc_id dm_idb ) as
    declare agent_id dm_idb;
    declare snd_optype_id dm_idb;
    declare snd_id dm_idb;
    declare storned_cost dm_cost;
    declare rcv_optype_id dm_idb;
    declare v_msg dm_info;
    declare v_worker_id dm_ids;

    declare v_this dm_dbobj = 'sp_kill_cost_storno';

    declare cs cursor for (
        select
            s.agent_id,
            iif(:a_deleted_or_cancelled_doc_id = s.rcv_id, s.snd_optype_id, s.rcv_optype_id) as snd_optype_id,
            iif(:a_deleted_or_cancelled_doc_id = s.rcv_id, s.snd_id, s.rcv_id) as snd_id,
            iif(:a_deleted_or_cancelled_doc_id = s.rcv_id, s.rcv_cost, s.snd_cost) as storned_cost,
            iif(:a_deleted_or_cancelled_doc_id = s.rcv_id, s.rcv_optype_id, s.snd_optype_id) as rcv_optype_id
        from pstorned s
        where
            :a_deleted_or_cancelled_doc_id in (s.rcv_id, s.snd_id)
            and s.worker_id is not distinct from :v_worker_id
    );
begin
    -- Called from trg D`OC_LIST_AIUD for operations:
    -- 1) delete document which cost was storned before (e.g. payment to supplier / from customer)
    -- 2) s`p_cancel_adding_invoice, s`p_cancel_write_off (i.e. REVERT state of doc)
    -- :a_deleted_or_cancelled_doc_id = doc
    -- 1) which is removed now
    -- XOR
    -- 2) which operation is cancelled now

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- 12.08.2018: get subsequent number of "current" ISQL session.
    -- We need this when config parameter separate_workers = 1:
    v_worker_id = fn_this_worker_seq_no();

    open cs;
    while (1=1) do
    begin
        fetch cs into agent_id, snd_optype_id, snd_id, storned_cost, rcv_optype_id;
        if ( row_count = 0) then leave;
        -- ::: nb ::: Revert sequence of these two commands if use `as cursor C`.
        -- See CORE-4488 ("Cursor references are not variables, they're not cached
        -- when reading. Instead, they represent the current state of the record")

        -- 04.08.2014: though no updates in statistics for 'select ... for update with lock' engine DOES them!
        -- See benchmark and issue by dimitr:
        -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1108762&msg=16394591
        delete from pstorned where current of cs;
        -- insert using variables instead of cursor ref (CORE-4488):
        insert into pdistr
              ( agent_id,   snd_optype_id,   snd_id,  worker_id,    snd_cost,       rcv_optype_id )
        values( :agent_id, :snd_optype_id,  :snd_id,  :v_worker_id, :storned_cost,   :rcv_optype_id );
    end
    close cs;

    delete from pdistr p
    where
        p.snd_id = :a_deleted_or_cancelled_doc_id
        and p.worker_id is not distinct from :v_worker_id
    ;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||a_deleted_or_cancelled_doc_id);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_msg,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_kill_cost_storno

create or alter procedure srv_log_dups_qd_qs( -- needed only in 3.0, SuperCLASSIC, in sep...oct 2014
    a_unit dm_dbobj,
    a_gdscode int,
    a_inserting_table dm_dbobj,
    a_inserting_id type of dm_idb,
    a_inserting_info dm_info
)
as
    declare v_curr_tx bigint;
    declare v_get_stt varchar(512);
    declare v_put_stt varchar(512);
    declare v_doc_id dm_idb;
    declare v_ware_id dm_idb;
    declare v_snd_optype_id dm_idb;
    declare v_snd_id dm_idb;
    declare v_snd_qty dm_qty;
    declare v_rcv_optype_id dm_idb;
    declare v_rcv_id dm_idb;
    declare v_rcv_qty dm_qty;
    declare v_snd_purchase dm_cost;
    declare v_snd_retail dm_cost;
    declare v_rcv_purchase dm_cost;
    declare v_rcv_retail dm_cost;
    declare v_trn_id dm_idb;
    declare v_dts timestamp;
begin
    -- 09.10.2014, continuing trouble with PK violations in 3.0 SuperCLASSIC.
    -- Add log info using auton Tx when PK violation occurs in QDistr or QStorned.
    -- 08.01.2014: replace wrong algorithm that ignored invisible data for auton Tx
    v_curr_tx = current_transaction;
    v_get_stt = 'select doc_id, ware_id, snd_optype_id, snd_id, snd_qty,'
            ||'rcv_optype_id, rcv_id, rcv_qty, snd_purchase, snd_retail,'
            ||'rcv_purchase,rcv_retail,trn_id,dts'
            ||' from '|| a_inserting_table ||' q'
            ||' where q.id = :x';

    v_put_stt = 'insert into '
            || iif( upper(a_inserting_table)=upper('QDISTR'), 'ZQdistr', 'ZQStorned' )
            ||'( id, doc_id, ware_id, snd_optype_id, snd_id, snd_qty,'
            ||'  rcv_optype_id, rcv_id, rcv_qty, snd_purchase, snd_retail,'
            ||'  rcv_purchase, rcv_retail, trn_id, dts, dump_att, dump_trn'
            ||') values '
            ||'(:id,:doc_id,:ware_id,:snd_optype_id,:snd_id,:snd_qty,'
            ||' :rcv_optype_id,:rcv_id,:rcv_qty,:snd_purchase,:snd_retail,'
            ||' :rcv_purchase,:rcv_retail,:trn_id,:dts,:dump_att,:dump_trn'
            ||')';


    execute statement (v_get_stt) ( x := a_inserting_id )
    -- 23.11.2020: no sense to use EDS here because we must check data
    -- that was changed by CURRENT transaction.
    into
        v_doc_id,
        v_ware_id,
        v_snd_optype_id,
        v_snd_id,
        v_snd_qty,
        v_rcv_optype_id,
        v_rcv_id,
        v_rcv_qty,
        v_snd_purchase,
        v_snd_retail,
        v_rcv_purchase,
        v_rcv_retail,
        v_trn_id,
        v_dts;

    in autonomous transaction do
    begin

        insert into perf_log( unit, exc_unit, fb_gdscode, trn_id, info, stack ) -- current unit: srv_log_dups_qd_qs
        values ( :a_unit, 'U', :a_gdscode, :v_curr_tx, :a_inserting_info, fn_get_stack( 1 ) );

        execute statement ( v_put_stt )
        (
            id  := a_inserting_id,
            doc_id := v_doc_id,
            ware_id := v_ware_id,
            snd_optype_id := v_snd_optype_id,
            snd_id := v_snd_id,
            snd_qty := v_snd_qty,
            rcv_optype_id := v_rcv_optype_id,
            rcv_id := v_rcv_id,
            rcv_qty := v_rcv_qty,
            snd_purchase := v_snd_purchase,
            snd_retail := v_snd_retail,
            rcv_purchase := v_rcv_purchase,
            rcv_retail := v_rcv_retail,
            trn_id := v_trn_id,
            dts := v_dts,
            dump_att := current_connection,
            dump_trn := v_curr_tx
        )
        -- 23.11.2020: no sense to add subst for EDS here: this SP is called when fatal error detected and job will be terminated
        ;

    end -- in auton Tx
end

^ -- srv_log_dups_qd_qs

create or alter procedure sp_kill_qstorno_ret_qs2qd(
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_deleting_doc dm_sign,
    a_aux_handling dm_sign default 0
)
as
    declare c_gen_inc_step_nt int = 100; -- size of `batch` for get at once new IDs for QDistr (reduce lock-contention of gen page)
    declare v_gen_inc_iter_nt int; -- increments from 1  up to c_gen_inc_step_nt and then restarts again from 1
    declare v_gen_inc_last_nt dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_nt)
    declare v_this dm_dbobj = 'sp_kill_qstorno_ret_qs2qd';
    declare v_call dm_unit; -- do NOT use `dm_dbobj`! This caused string overflow in 4.0, since 16-jul-2016; see letter from hvlad 06-jan-2017 01:59
    declare v_halt_on_pk_viol smallint;
    declare v_info dm_info;
    declare v_suffix dm_info;
    declare i int  = 0;
    declare k int  = 0;
    declare v_dd_id dm_idb;
    declare v_id dm_idb;
    declare v_doc_id dm_idb;
    declare v_worker_id type of dm_ids; -- 12.08.2018
    declare v_doc_optype dm_idb;
    declare v_dd_ware_id dm_idb;
    declare v_dd_qty dm_qty;
    declare v_dd_cost dm_qty;
    declare v_doc_pref dm_mcode;
    declare v_snd_optype_id dm_idb;
    declare v_snd_id dm_idb;
    declare v_snd_qty dm_qty;
    declare v_rcv_optype_id dm_idb;
    declare v_rcv_id dm_idb;
    declare v_rcv_qty dm_qty;
    declare v_snd_purchase dm_cost;
    declare v_snd_retail dm_cost;
    declare v_rcv_purchase dm_cost;
    declare v_rcv_retail dm_cost;
    declare v_log_cursor dm_dbobj; -- 4debug only
    declare v_ret_cursor dm_dbobj; -- 4debug only
    declare v_oper_retail_realization dm_idb;
    declare v_old_rcv_optype type of dm_idb;

    declare c_dd_rows_for_doc cursor for (
        -- used to immediatelly delete record in doc_data when document
        -- is to be deleted (avoid scanning doc_data rows in FK-trigger again)
        select d.id, d.ware_id, d.qty, d.cost_purchase
        from doc_data d
        where d.doc_id = :a_doc_id
    );

    declare c_qd_rows_for_doc cursor for (
        select id
        from v_qdistr_name_for_del q -- this name will be replaced with 'autogen_qdNNNN' when config 'create_with_split_heavy_tabs=1'
        where
            q.ware_id = :v_dd_ware_id
            and q.snd_optype_id = :a_old_optype
            and q.rcv_optype_id = :v_old_rcv_optype
            and q.worker_id is not distinct from fn_this_worker_seq_no()
            and q.snd_id = :v_dd_id
    );

    declare c_ret_qs2qd_by_rcv cursor for (
        select
             qs.id
            ,qs.doc_id
            ,qs.worker_id
            ,qs.snd_optype_id
            ,qs.snd_id
            ,qs.snd_qty
            ,qs.rcv_optype_id
            ,null as rcv_id
            ,null as rcv_qty
            ,qs.snd_purchase
            ,qs.snd_retail
            ,null as rcv_purchase
            ,null as rcv_retail
        from v_qstorno_name_for_del qs -- this name will be replaced with 'autogen_qdNNNN' when config 'create_with_split_heavy_tabs=1'
        where
            qs.rcv_id = :v_dd_id -- for all cancel ops except sp_cancel_wroff
            and qs.worker_id is not distinct from fn_this_worker_seq_no()
    );

    declare c_ret_qs2qd_by_snd cursor for (
        select
             qs.id
            ,qs.doc_id
            ,qs.worker_id
            ,qs.snd_optype_id
            ,qs.snd_id
            ,qs.snd_qty
            ,qs.rcv_optype_id
            ,null as rcv_id
            ,null as rcv_qty
            ,qs.snd_purchase
            ,qs.snd_retail
            ,null as rcv_purchase
            ,null as rcv_retail
        from v_qstorno_name_for_del qs -- this name will be replaced with 'autogen_qdNNNN' when config 'create_with_split_heavy_tabs=1'
        where
            qs.snd_id = :v_dd_id -- for sp_cancel_wroff
            and qs.worker_id is not distinct from fn_this_worker_seq_no()
    );
begin
    -- Aux SP, called from sp_kill_qty_storno for
    -- 1) sp_cancel_wroff (a_deleting = 0!) or
    -- 2) all doc removals (sp_cancel_xxx, a_deleting = 1)

    v_call = v_this;
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_call,null);

    v_oper_retail_realization = fn_oper_retail_realization();
    v_doc_pref = fn_mcode_for_oper(a_old_optype);

    -- move evaluation outside from cursor loop:
    v_halt_on_pk_viol = iif( rdb$get_context('USER_SESSION','HALT_TEST_ON_ERRORS') containing '/PK/', 1, 0);

    select r.rcv_optype_id
    from v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
    where
        r.snd_optype_id = :a_old_optype
        and coalesce(r.storno_sub,1) = 1 -- nb: old_op=2000 ==> storno_sub=NULL!
    into v_old_rcv_optype;

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    -- only for logging in perf_log.info name of handling cursor:
    v_ret_cursor = iif(a_old_optype <> fn_oper_retail_realization(), 'c_ret_qs2qd_by_rcv', 'c_ret_qs2qd_by_snd');

    -- return from QStorned to QDistr records which were previously moved
    -- (when currently deleting doc was created).
    -- Use explicitly declared cursor for immediate removing row from doc_data
    -- when document is to be deleted:
    open c_dd_rows_for_doc;
    while (1=1) do
    begin
        fetch c_dd_rows_for_doc
        into v_dd_id, v_dd_ware_id, v_dd_qty, v_dd_cost;
        if ( row_count = 0 ) then leave;

        if ( a_deleting_doc = 1 and a_aux_handling = 0 ) then
        begin
            v_log_cursor = 'c_qd_rows_for_doc'; -- 4debug
            open c_qd_rows_for_doc;
            while (1=1) do
            begin
                fetch c_qd_rows_for_doc into v_id;
                if ( row_count = 0 ) then leave;
                i = i+1; -- total number of processed rows
                delete from v_qdistr_name_for_del where current of c_qd_rows_for_doc;
            end
            close c_qd_rows_for_doc;
        end
        ----------------------------------------------------------
        if ( a_old_optype <> v_oper_retail_realization ) then
            open c_ret_qs2qd_by_rcv; -- from qstorned qs where qs.RCV_id = :v_dd_id
        else
            open c_ret_qs2qd_by_snd; -- from qstorned where qs.SND_id = :v_dd_id

        v_log_cursor = v_ret_cursor;
        while (1=1) do
        begin
            if ( a_old_optype <> v_oper_retail_realization ) then
                fetch c_ret_qs2qd_by_rcv into
                     v_id
                    ,v_doc_id
                    ,v_worker_id
                    ,v_snd_optype_id
                    ,v_snd_id
                    ,v_snd_qty
                    ,v_rcv_optype_id
                    ,v_rcv_id
                    ,v_rcv_qty
                    ,v_snd_purchase
                    ,v_snd_retail
                    ,v_rcv_purchase
                    ,v_rcv_retail;
            else
                fetch c_ret_qs2qd_by_snd into
                     v_id
                    ,v_doc_id
                    ,v_worker_id
                    ,v_snd_optype_id
                    ,v_snd_id
                    ,v_snd_qty
                    ,v_rcv_optype_id
                    ,v_rcv_id
                    ,v_rcv_qty
                    ,v_snd_purchase
                    ,v_snd_retail
                    ,v_rcv_purchase
                    ,v_rcv_retail;

            if ( row_count = 0 ) then leave;
            i = i+1; -- total number of processed rows

            v_suffix = ', id=' || :v_id || ', doc_id=' || :v_doc_id;

            if ( v_halt_on_pk_viol = 1 ) then
            begin
                -- debug info for logging in srv_log_dups_qd_qs if PK
                -- violation will occur on INSERT INTO QDISTR statement
                -- (remained for possible analysis):
                v_call = v_this || ':try_del_qstorned';
                v_info = v_ret_cursor
                    || ': try DELETE in qStorned'
                    || ' where ' || iif(v_ret_cursor = 'c_ret_qs2qd_by_rcv', 'rcv_id =', 'snd_id =') || :v_dd_id
                    || v_suffix
                ;
                execute procedure sp_add_perf_log(1, v_call, null, v_info, v_id); -- 10.02.2015, debug
                rdb$set_context('USER_TRANSACTION','DBG_RETQS2QD_TRY_DEL_QSTORNO_ID', v_id);
            end

            -- We can try to delete record in QStorned *before* inserting
            -- data in QDistr: all fields from cursor now are in variables.
            -- ::: NB ::: (measurements 28.01-05.02.2015)
            -- replacing qStorned with "unioned-view" based on N tables
            -- and applying "where id = :a" leads to performance DEGRADATION
            -- due to need to have index on ID field in each underlying table.
            if ( a_old_optype <> v_oper_retail_realization ) then
                delete from v_qstorno_name_for_del where current of c_ret_qs2qd_by_rcv;
            else
                delete from v_qstorno_name_for_del where current of c_ret_qs2qd_by_snd;

            if ( v_halt_on_pk_viol = 1 ) then
            begin
                rdb$set_context('USER_TRANSACTION','DBG_RETQS2QD_OK_DEL_QSTORNO_ID', v_id);
                execute procedure sp_add_perf_log(0, v_call, null, 'deleted OK' );
    
                -- debug info for logging in srv_log_dups_qd_qs if PK
                -- violation will occur on INSERT INTO QDISTR statement
                -- (remained for possible analysis):
                v_info = v_ret_cursor || ': try INSERT in qDistr' || v_suffix;
                v_call = v_this || ':try_ins_qdistr';
    
                execute procedure sp_add_perf_log(1, v_call, null, v_info, v_id); -- 10.02.2015, debug
                rdb$set_context('USER_TRANSACTION','DBG_RETQS2QD_TRY_INS_QDISTR_ID', v_id);
            end

            insert into v_qdistr_name_for_ins(
                id,
                doc_id,
                worker_id, -- 12.08.2018
                ware_id,
                snd_optype_id,
                snd_id,
                snd_qty,
                rcv_optype_id,
                rcv_id,
                rcv_qty,
                snd_purchase,
                snd_retail,
                rcv_purchase,
                rcv_retail
            )
            values(
                 :v_id
                ,:v_doc_id
                ,:v_worker_id -- 12.08.2018
                ,:v_dd_ware_id
                ,:v_snd_optype_id
                ,:v_snd_id
                ,:v_snd_qty
                ,:v_rcv_optype_id
                ,:v_rcv_id
                ,:v_rcv_qty
                ,:v_snd_purchase
                ,:v_snd_retail
                ,:v_rcv_purchase
                ,:v_rcv_retail
            );


            if ( v_halt_on_pk_viol = 1 ) then
            begin
                rdb$set_context('USER_TRANSACTION','DBG_RETQS2QD_OK_INS_QDISTR_ID', v_id);
                execute procedure sp_add_perf_log(0, v_call, null, 'inserted OK');
            end

        when any do
            begin
                if ( fn_is_uniqueness_trouble(gdscode) ) then
                    -- ###############################################
                    -- PK violation on INSERT INTO QDISTR, log this:
                    -- ###############################################
                    -- 12.02.2015: the reason of PK violations is unpredictable order
                    -- of UNDO, ultimately explained by dimitr, see letters in e-mail.
                    -- Also: sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1142271&msg=17257984
                    execute procedure srv_log_dups_qd_qs( -- 09.10.2014: add log info using auton Tx
                        :v_call,
                        gdscode,
                        'qdistr',
                        :v_id,
                        :v_info
                    );

                exception; -- ::: nb ::: anonimous but in when-block!
            end

        end -- cursor c_ret_qs2qd_by  _rcv | _snd

        if ( a_old_optype <> v_oper_retail_realization ) then
            close c_ret_qs2qd_by_rcv;
        else
            close c_ret_qs2qd_by_snd;

        -- 20.09.2014: move here from trigger on doc_list
        -- (reduce scans of doc_data)
        if ( a_aux_handling = 0 ) then
        begin
            insert into invnt_turnover_log(
                 id -- explicitly assign this field in order NOT to call gen_id in trigger (use v_gen_... counter instead)
                ,ware_id
                ,qty_diff
                ,cost_diff
                ,doc_list_id
                ,doc_pref
                ,doc_data_id
                ,optype_id
            ) values (
                 :v_gen_inc_last_nt - ( :c_gen_inc_step_nt - :v_gen_inc_iter_nt )
                ,:v_dd_ware_id
                ,-(:v_dd_qty)
                ,-(:v_dd_cost)
                ,:a_doc_id
                ,:v_doc_pref
                ,:v_dd_id
                ,:a_old_optype
            );

            v_gen_inc_iter_nt = v_gen_inc_iter_nt + 1;
            if ( v_gen_inc_iter_nt = c_gen_inc_step_nt ) then -- its time to get another batch of IDs
            begin
                v_gen_inc_iter_nt = 1;
                -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );
            end
        end

        if ( a_deleting_doc = 1 and a_aux_handling = 0 ) then
            delete from doc_data where current of c_dd_rows_for_doc;

    end -- cursor on doc_data rows for a_doc_id
    close c_dd_rows_for_doc;

    -- add to performance log timestamp about start/finish this unit:
    v_info =
        'qs->qd: doc='||a_doc_id||', op='||a_old_optype
        ||', ret_rows='||i
        ||', cur='||v_ret_cursor
    ;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    v_call = v_this;
    execute procedure sp_add_perf_log(0, v_call,null,v_info);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info, -- 'qs->qd, doc='||a_doc_id||': try ins qd.id='||coalesce(v_id,'<?>')||', v_dd_id='||coalesce(v_dd_id,'<?>'),
            v_call, -- ::: NB ::: do NOT use 'v_this' !! name of last started unit must be actual, see sp_add_to_abend_log!
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_kill_qstorno_ret_qs2qd

create or alter procedure sp_ret_qs2qd_on_canc_wroff(
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_deleting_doc dm_sign,
    a_aux_handling dm_sign default 0
)
as
begin
    -- This proc serves just as trivial 'redirector' when config parameter 'create_with_split_heavy_tabs = 0'.
    -- Otherwise it will be OVERWRITTEN: its code will be replaced with one from sp_kill_qstorno_ret_qs2qd
    -- and replacing of 'QDistr' and 'QStorned' sources with appropriate to current cancel operation.

    execute procedure sp_kill_qstorno_ret_qs2qd( :a_doc_id, :a_old_optype, :a_deleting_doc );
end

^ -- sp_ret_qs2qd_on_canc_wroff

create or alter procedure sp_ret_qs2qd_on_canc_reserve(
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_deleting_doc dm_sign,
    a_aux_handling dm_sign default 0
)
as
begin
    -- This proc serves just as trivial 'redirector' when config parameter 'create_with_split_heavy_tabs = 0'.
    -- Otherwise it will be OVERWRITTEN: its code will be replaced with one from sp_kill_qstorno_ret_qs2qd
    -- and replacing of 'QDistr' and 'QStorned' sources with appropriate to current cancel operation.

    execute procedure sp_kill_qstorno_ret_qs2qd( :a_doc_id, :a_old_optype, :a_deleting_doc );
end

^ -- sp_ret_qs2qd_on_canc_reserve

create or alter procedure sp_ret_qs2qd_on_canc_res_aux(
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_deleting_doc dm_sign,
    a_aux_handling dm_sign default 1
)
as
begin
    -- This proc remains EMPTY when config parameter 'create_with_split_heavy_tabs = 0'.
    -- Otherwise it will be OVERWRITTEN: its code will be replaced with one from sp_kill_qstorno_ret_qs2qd
    -- and replacing of 'QDistr' and 'QStorned' sources with autogen_qd1000 and autogen_qs1000.
    exit;   
end

^ -- sp_ret_qs2qd_on_canc_res_aux

create or alter procedure sp_ret_qs2qd_on_canc_invoice(
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_deleting_doc dm_sign,
    a_aux_handling dm_sign default 0
)
as
begin
    -- This proc serves just as trivial 'redirector' when config parameter 'create_with_split_heavy_tabs = 0'.
    -- Otherwise it will be OVERWRITTEN: its code will be replaced with one from sp_kill_qstorno_ret_qs2qd
    -- and replacing of 'QDistr' and 'QStorned' sources with appropriate to current cancel operation.

    execute procedure sp_kill_qstorno_ret_qs2qd( :a_doc_id, :a_old_optype, :a_deleting_doc );
end

^ -- sp_ret_qs2qd_on_canc_invoice

create or alter procedure sp_ret_qs2qd_on_canc_supp_order(
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_deleting_doc dm_sign,
    a_aux_handling dm_sign default 0
)
as
begin
    -- This proc serves just as trivial 'redirector' when config parameter 'create_with_split_heavy_tabs = 0'.
    -- Otherwise it will be OVERWRITTEN: its code will be replaced with one from sp_kill_qstorno_ret_qs2qd
    -- and replacing of 'QDistr' and 'QStorned' sources with appropriate to current cancel operation.

    execute procedure sp_kill_qstorno_ret_qs2qd( :a_doc_id, :a_old_optype, :a_deleting_doc );
end

^ -- sp_ret_qs2qd_on_canc_supp_order

create or alter procedure sp_qd_handle_on_reserve_upd_sts ( -- old name: s~p_kill_qstorno_mov_qd2qs(
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_new_optype dm_idb
) as
    declare c_gen_inc_step_nt int = 100; -- size of `batch` for get at once new IDs for QDistr (reduce lock-contention of gen page)
    declare v_gen_inc_iter_nt int; -- increments from 1  up to c_gen_inc_step_nt and then restarts again from 1
    declare v_gen_inc_last_nt dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_nt)

    declare v_this dm_dbobj = 'sp_qd_handle_on_reserve_upd_sts';
    declare v_info dm_info;
    declare v_curr_tx bigint;
    declare i int  = 0;
    declare v_dd_id dm_idb;
    declare v_dd_ware_id dm_qty;
    declare v_dd_qty dm_qty;
    declare v_dd_cost dm_qty;
    declare v_doc_pref dm_mcode;

    declare v_old_rcv_optype type of dm_idb;
    declare v_storno_sub smallint;
    declare v_id dm_idb;
    declare v_doc_id dm_idb;
    declare v_worker_id type of dm_ids; -- 12.08.2018
    declare v_doc_optype dm_idb;
    declare v_ware_id dm_idb;
    declare v_snd_optype_id dm_idb;
    declare v_snd_id dm_idb;
    declare v_snd_qty dm_qty;
    declare v_rcv_optype_id dm_idb;
    declare v_rcv_id dm_idb;
    declare v_rcv_qty dm_qty;
    declare v_snd_purchase dm_cost;
    declare v_snd_retail dm_cost;
    declare v_rcv_purchase dm_cost;
    declare v_rcv_retail dm_cost;

    declare c_mov_from_qd2qs cursor for (
        -- rows which will be MOVED from qdistr to qstorned
        select
             qd.id
            ,qd.doc_id
            ,qd.worker_id -- 12.08.2018
            ,qd.ware_id
            ,qd.snd_optype_id
            ,qd.snd_id
            ,qd.snd_qty
            ,qd.rcv_optype_id
            ,qd.rcv_id
            ,qd.rcv_qty
            ,qd.snd_purchase
            ,qd.snd_retail
            ,qd.rcv_purchase
            ,qd.rcv_retail
        from v_qdistr_name_for_del qd -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where
            qd.ware_id = :v_dd_ware_id
            and qd.snd_optype_id = :a_old_optype
            and qd.rcv_optype_id = :v_old_rcv_optype
            and qd.worker_id is not distinct from fn_this_worker_seq_no()
            and qd.snd_id = :v_dd_id
    );

begin
    -- Aux SP, called from sp_kill_qty_storno ONLY for sp_reserve_write_off
    -- (change state of customer reserve to 'waybill' when wares are written-off)

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    v_doc_pref = fn_mcode_for_oper(a_new_optype);

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    -- return from QStorned to QDistr records which were previously moved
    -- (when currently deleting doc was created):
    for
        select d.id, r.rcv_optype_id, r.storno_sub, d.ware_id, d.qty,  d.cost_purchase
        from doc_data d
        cross join v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
        where d.doc_id = :a_doc_id and r.snd_optype_id = :a_old_optype
    into v_dd_id, v_old_rcv_optype, v_storno_sub, v_dd_ware_id, v_dd_qty, v_dd_cost
    do
    begin
        if ( coalesce(v_storno_sub,1) = 1 ) then
        begin
            insert into invnt_turnover_log(
                 id -- explicitly assign this field in order NOT to call gen_id in trigger (use v_gen_... counter instead)
                ,ware_id
                ,qty_diff
                ,cost_diff
                ,doc_list_id
                ,doc_pref
                ,doc_data_id
                ,optype_id
            ) values (
                 :v_gen_inc_last_nt - ( :c_gen_inc_step_nt - :v_gen_inc_iter_nt ) -- iter=1: 12345 - (100-1); iter=2: 12345 - (100-2); ...; iter=100: 12345 - (100-100)
                ,:v_dd_ware_id
                ,:v_dd_qty
                ,:v_dd_cost
                ,:a_doc_id
                ,:v_doc_pref
                ,:v_dd_id
                ,:a_new_optype
            );
            v_gen_inc_iter_nt = v_gen_inc_iter_nt + 1;
            if ( v_gen_inc_iter_nt = c_gen_inc_step_nt ) then -- its time to get another batch of IDs
            begin
                v_gen_inc_iter_nt = 1;
                -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );
            end
        end

        open c_mov_from_qd2qs; -- from qstorned qs where qs.rcv_id = :v_dd_id
        while (1=1) do
        begin
            fetch c_mov_from_qd2qs into
                 v_id
                ,v_doc_id
                ,v_worker_id -- 12.08.2018
                ,v_ware_id
                ,v_snd_optype_id
                ,v_snd_id
                ,v_snd_qty
                ,v_rcv_optype_id
                ,v_rcv_id
                ,v_rcv_qty
                ,v_snd_purchase
                ,v_snd_retail
                ,v_rcv_purchase
                ,v_rcv_retail;
            if ( row_count = 0 ) then leave;
            i = i + 1;
            -- moved here 16.09.2014: all cursor fields are stored now in variables
            delete from v_qdistr_name_for_del where current of c_mov_from_qd2qs;

            -- for logging in autonom. Tx if PK violation occurs in subsequent sttmt:
            v_info = 'qd->qs, c_mov_from_qd2qs: try ins qStorned.id='||:v_id;

            -- S P _ R E S E R V E _ W R I T E _ O F F
            -- (FINAL point of ware turnover ==> remove data from qdistr in qstorned)
            insert into v_qstorno_name_for_ins ( -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
                id,
                doc_id,
                worker_id,
                ware_id,
                snd_optype_id,
                snd_id,
                snd_qty,
                rcv_optype_id,
                rcv_id,
                rcv_qty,
                snd_purchase,
                snd_retail,
                rcv_purchase,
                rcv_retail
            )
            values(
                :v_id,
                :v_doc_id,
                :v_worker_id,
                :v_ware_id,
                :v_snd_optype_id,
                :v_snd_id,
                :v_snd_qty,
                :v_rcv_optype_id,
                :v_rcv_id,
                :v_rcv_qty,
                :v_snd_purchase,
                :v_snd_retail,
                :v_rcv_purchase,
                :v_rcv_retail
            );

        when any do
            begin
                if ( fn_is_uniqueness_trouble(gdscode) ) then
                    -- temply, 09.10.2014 2120: resume investigate trouble with PK violation
                    execute procedure srv_log_dups_qd_qs(
                        :v_this,
                        gdscode,
                        'qstorned',
                        :v_id,
                        :v_info
                    );
                exception; -- ::: nb ::: anonimous but in when-block!
            end

        end -- cursor c_mov_from_qd2qs

        close c_mov_from_qd2qs;
    end -- cursor on doc_data

    -- add to performance log timestamp about start/finish this unit:
    v_info = 'qd->qs, doc='||a_doc_id||', rows='||i;
    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this,null,v_info);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'qs->qd, doc='||a_doc_id||': try ins qs.id='||coalesce(v_id,'<?>')||', v_dd_id='||coalesce(v_dd_id,'<?>'||', old_op='||a_old_optype ),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_qd_handle_on_reserve_upd_sts

create or alter procedure sp_qd_handle_on_cancel_clo (
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_new_optype dm_idb)
as
    declare c_gen_inc_step_nt int = 100; -- size of `batch` for get at once new IDs for QDistr (reduce lock-contention of gen page)
    declare v_gen_inc_iter_nt int; -- increments from 1  up to c_gen_inc_step_nt and then restarts again from 1
    declare v_gen_inc_last_nt dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_nt)
    declare v_this dm_dbobj = 'sp_qd_handle_on_cancel_clo';
    declare v_info dm_info;
    declare v_id dm_idb;
    declare v_snd_id dm_idb;
    declare v_dd_rows int  = 0;
    declare v_dd_qsum int = 0;
    declare v_del_sign dm_sign;
    declare v_qd_rows int = 0;
    declare v_qs_rows int = 0;
    declare v_dd_id dm_idb;
    declare v_dd_ware_id dm_qty;
    declare v_dd_qty dm_qty;
    declare v_dd_cost dm_qty;
    declare v_doc_pref dm_mcode;
    declare v_log_mult dm_sign;
    declare v_log_oper dm_idb;
    declare v_rcv_optype_id type of dm_idb;
    declare v_storno_sub smallint;

    declare c_qd_rows_sub_1 cursor for (
        select q.id, q.snd_id
        from v_qdistr_target_1 q -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where
            q.ware_id = :v_dd_ware_id
            and q.snd_optype_id = :a_old_optype
            and q.rcv_optype_id = :v_rcv_optype_id
            and q.worker_id is not distinct from fn_this_worker_seq_no()
            and q.snd_id = :v_dd_id
    );
    declare c_qd_rows_sub_2 cursor for (
        select q.id, q.snd_id
        from v_qdistr_target_2 q -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where
            q.ware_id = :v_dd_ware_id
            and q.snd_optype_id = :a_old_optype
            and q.rcv_optype_id = :v_rcv_optype_id
            and q.worker_id is not distinct from fn_this_worker_seq_no()
            and q.snd_id = :v_dd_id
    );

    declare c_qs_rows_sub_1 cursor for (
        select qs.id, qs.snd_id
        from v_qstorned_target_1 qs  -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where
            qs.snd_id = :v_dd_id
            and qs.worker_id is not distinct from fn_this_worker_seq_no()
    );
    declare c_qs_rows_sub_2 cursor for (
        select qs.id, qs.snd_id
        from v_qstorned_target_2 qs  -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where
            qs.snd_id = :v_dd_id
            and qs.worker_id is not distinct from fn_this_worker_seq_no()
    );

begin

    -- Aux SP, called from sp_kill_qty_storno ONLY for:
    -- 1) sp_cancel_client_order; 2) sp_add_invoice_to_stock (apply and cancel)

    -- add to performance log timestamp about start/finish this unit:
    v_info = iif( a_new_optype = fn_oper_cancel_customer_order(), 'DEL', 'UPD' )
             || ' in qdistr, doc='||a_doc_id
             || ', old_op='||a_old_optype
             || iif( a_new_optype <> fn_oper_cancel_customer_order(), ', new_op='||a_new_optype, '');
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    v_log_oper = iif( a_new_optype = fn_oper_invoice_get(), fn_oper_invoice_add(), a_new_optype);
    v_log_mult = iif( a_new_optype = fn_oper_invoice_get(), -1, 1);
    v_doc_pref = fn_mcode_for_oper(v_log_oper);
    v_del_sign = 1; -- iif(a_new_optype = fn_oper_cancel_customer_order(), 1, 0);

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    for
        select r.rcv_optype_id, r.storno_sub
        from v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
        where r.snd_optype_id = :a_old_optype
        --and coalesce(r.storno_sub,1) = 1 -- do NOT! old_op=1000 ==> two rows (storno_sub=1 and 2) - needs to be processed for sp_cancel_client_order
        into v_rcv_optype_id, v_storno_sub
    do
    begin
        for
            select d.id, d.ware_id, d.qty, d.cost_purchase
            from doc_data d
            where d.doc_id = :a_doc_id
            into v_dd_id, v_dd_ware_id, v_dd_qty, v_dd_cost
        do
        begin
            v_dd_rows = v_dd_rows + 1;
            v_dd_qsum = v_dd_qsum + v_dd_qty;
            -- 20.09.2014: move here from trigger on doc_list
            -- (reduce scans of doc_data)
            if ( coalesce(v_storno_sub,1) = 1 ) then
            begin
                insert into invnt_turnover_log(
                     id -- explicitly specify this field in order NOT to call gen_id in trigger (use v_gen_... counter instead)
                    ,ware_id
                    ,qty_diff
                    ,cost_diff
                    ,doc_list_id
                    ,doc_pref
                    ,doc_data_id
                    ,optype_id
                ) values (
                     :v_gen_inc_last_nt - ( :c_gen_inc_step_nt - :v_gen_inc_iter_nt ) -- iter=1: 12345 - (100-1); iter=2: 12345 - (100-2); ...; iter=100: 12345 - (100-100)
                    ,:v_dd_ware_id
                    ,:v_log_mult * :v_dd_qty
                    ,:v_log_mult * :v_dd_cost
                    ,:a_doc_id
                    ,:v_doc_pref
                    ,:v_dd_id
                    ,:v_log_oper
                );

                v_gen_inc_iter_nt = v_gen_inc_iter_nt + 1;
                if ( v_gen_inc_iter_nt = c_gen_inc_step_nt ) then -- its time to get another batch of IDs
                begin
                    v_gen_inc_iter_nt = 1;
                    -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );
                end
            end

            open c_qd_rows_sub_1;
            while (1=1) do
            begin
                fetch c_qd_rows_sub_1 into v_id, v_snd_id;
                if ( row_count = 0 ) then leave;
                v_qd_rows = v_qd_rows + 1;
                delete from v_qdistr_target_1
                where current of c_qd_rows_sub_1;
            end
            close c_qd_rows_sub_1;

            open c_qd_rows_sub_2;
            while (1=1) do
            begin
                fetch c_qd_rows_sub_2 into v_id, v_snd_id;
                if ( row_count = 0 ) then leave;
                v_qd_rows = v_qd_rows + 1;
                delete from v_qdistr_target_2
                where current of c_qd_rows_sub_2;
            end
            close c_qd_rows_sub_2;

            open c_qs_rows_sub_1;
            while (1=1) do
            begin
                fetch c_qs_rows_sub_1 into v_id, v_snd_id;
                if ( row_count = 0 ) then leave;
                v_qs_rows = v_qs_rows+1;
                delete from v_qstorned_target_1
                where current of c_qs_rows_sub_1;
            end
            close c_qs_rows_sub_1;

            open c_qs_rows_sub_2;
            while (1=1) do
            begin
                fetch c_qs_rows_sub_2 into v_id, v_snd_id;
                if ( row_count = 0 ) then leave;
                v_qs_rows = v_qs_rows+1;
                delete from v_qstorned_target_2
                where current of c_qs_rows_sub_2;
            end
            close c_qs_rows_sub_2;

        end
    end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'dd_qsum='||v_dd_qsum||', rows: dd='||v_dd_rows||', qd='||v_qd_rows||', qs='||v_qs_rows );

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_qd_handle_on_cancel_clo

create or alter procedure sp_qd_handle_on_invoice_upd_sts (
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_new_optype dm_idb)
as
    declare c_gen_inc_step_nt int = 100; -- size of `batch` for get at once new IDs for QDistr (reduce lock-contention of gen page)
    declare v_gen_inc_iter_nt int; -- increments from 1  up to c_gen_inc_step_nt and then restarts again from 1
    declare v_gen_inc_last_nt dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_nt)
    declare v_this dm_dbobj = 'sp_qd_handle_on_invoice_upd_sts';
    declare v_info dm_info;

    declare v_qd_id dm_idb;
    declare v_qd_doc_id dm_idb;
    declare v_qd_ware_id dm_idb;

    declare v_qd_snd_id dm_idb;
    declare v_qd_snd_qty dm_qty;
    declare v_qd_rcv_doc_id bigint;
    declare v_qd_rcv_optype_id bigint;
    declare v_qd_rcv_id bigint;
    declare v_qd_rcv_qty numeric(12,3);
    declare v_qd_snd_purchase dm_cost;
    declare v_qd_snd_retail dm_cost;
    declare v_qd_rcv_purchase dm_cost;
    declare v_qd_rcv_retail dm_cost;

    declare v_dd_rows int  = 0;
    declare v_dd_qsum int = 0;

    declare v_qd_rows int = 0;
    declare v_dd_id dm_idb;
    declare v_worker_id dm_ids; -- 12.08.2018
    declare v_dd_ware_id dm_qty;
    declare v_dd_qty dm_qty;
    declare v_dd_cost dm_qty;
    declare v_doc_pref dm_mcode;
    declare v_log_mult dm_sign;
    declare v_log_oper dm_idb;
    declare v_rcv_optype_id type of dm_idb;
    declare v_storno_sub smallint;

    declare c_qd_rows_for_doc cursor for (
        select --q.id, q.snd_id
            id,
            doc_id,
            worker_id,
            ware_id,
            snd_id,
            snd_qty,
            rcv_doc_id,
            rcv_optype_id,
            rcv_id,
            rcv_qty,
            snd_purchase,
            snd_retail,
            rcv_purchase,
            rcv_retail
        from v_qdistr_name_for_del q -- name of this datasource will be replaced when config 'create_with_split_heavy_tabs=1'
        where
            q.ware_id = :v_dd_ware_id
            and q.snd_optype_id = :a_old_optype
            and q.rcv_optype_id = :v_rcv_optype_id
            and q.worker_id is not distinct from fn_this_worker_seq_no()
            and q.snd_id = :v_dd_id
    );

begin

    -- Aux SP, called from sp_kill_qty_storno ONLY for
    -- sp_add_invoice_to_stock (apply and cancel)
    -- #######################

    -- Old name: s~p_kill_qstorno_handle_qd4dd

    -- add to performance log timestamp about start/finish this unit:
    v_info = 'UPD in qdistr, doc='||a_doc_id
             || ', old_op='||a_old_optype
             || ', new_op='||a_new_optype;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);


    v_log_oper = iif( a_new_optype = fn_oper_invoice_get(), fn_oper_invoice_add(), a_new_optype);
    v_log_mult = iif( a_new_optype = fn_oper_invoice_get(), -1, 1);
    v_doc_pref = fn_mcode_for_oper(v_log_oper);

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt ); -- take bulk IDs at once (reduce lock-contention for GEN page)

    for
        select r.rcv_optype_id, r.storno_sub
        from v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
        where r.snd_optype_id = :a_old_optype
        into v_rcv_optype_id, v_storno_sub -- 'v_rcv_optype_id' see in WHERE condition in c_qd_rows_for_doc
    do
    begin
        for
            select d.id, d.ware_id, d.qty, d.cost_purchase
            from doc_data d
            where d.doc_id = :a_doc_id
            into v_dd_id, v_dd_ware_id, v_dd_qty, v_dd_cost
        do
        begin
            v_dd_rows = v_dd_rows + 1;
            v_dd_qsum = v_dd_qsum + v_dd_qty;
            -- 20.09.2014: move here from trigger on doc_list
            -- (reduce scans of doc_data)
            if ( coalesce(v_storno_sub,1) = 1 ) then
            begin
                insert into invnt_turnover_log(
                     id -- explicitly specify this field in order NOT to call gen_id in trigger (use v_gen_... counter instead)
                    ,ware_id
                    ,qty_diff
                    ,cost_diff
                    ,doc_list_id
                    ,doc_pref
                    ,doc_data_id
                    ,optype_id
                ) values (
                     :v_gen_inc_last_nt - ( :c_gen_inc_step_nt - :v_gen_inc_iter_nt ) -- iter=1: 12345 - (100-1); iter=2: 12345 - (100-2); ...; iter=100: 12345 - (100-100)
                    ,:v_dd_ware_id
                    ,:v_log_mult * :v_dd_qty
                    ,:v_log_mult * :v_dd_cost
                    ,:a_doc_id
                    ,:v_doc_pref
                    ,:v_dd_id
                    ,:v_log_oper
                );

                v_gen_inc_iter_nt = v_gen_inc_iter_nt + 1;
                if ( v_gen_inc_iter_nt = c_gen_inc_step_nt ) then -- its time to get another batch of IDs
                begin
                    v_gen_inc_iter_nt = 1;
                    -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );
                end
            end

            open c_qd_rows_for_doc;
            while (1=1) do
            begin
                fetch c_qd_rows_for_doc
                into -- v_qd_id, v_qd_snd_id;
                     v_qd_id
                    ,v_qd_doc_id
                    ,v_worker_id -- 12.08.2018
                    ,v_qd_ware_id
                    ,v_qd_snd_id
                    ,v_qd_snd_qty
                    ,v_qd_rcv_doc_id
                    ,v_qd_rcv_optype_id
                    ,v_qd_rcv_id
                    ,v_qd_rcv_qty
                    ,v_qd_snd_purchase
                    ,v_qd_snd_retail
                    ,v_qd_rcv_purchase
                    ,v_qd_rcv_retail;
                if ( row_count = 0 ) then leave;
                v_qd_rows = v_qd_rows+1;

                -- sp_add_invoice_to_stock: apply and cancel
                -- #########################################

                -- 31.08.2015: replaced 'update qdistr' to del_ins algorithm,
                -- so this can be applied later for replacing to 'autogen_qdNNNN'.

                delete from v_qdistr_name_for_del where current of c_qd_rows_for_doc; -- name will be replaced when config 'create_with_split_heavy_tabs=1'

                insert into v_qdistr_name_for_ins( -- name will be replaced when config 'create_with_split_heavy_tabs=1'
                    id,
                    doc_id,
                    worker_id, -- 12.08.2018
                    ware_id,
                    snd_optype_id,
                    snd_id,
                    snd_qty,
                    rcv_doc_id,
                    rcv_optype_id,
                    rcv_id,
                    rcv_qty,
                    snd_purchase,
                    snd_retail,
                    rcv_purchase,
                    rcv_retail
                ) values(
                     :v_qd_id
                    ,:v_qd_doc_id
                    ,:v_worker_id
                    ,:v_qd_ware_id
                    ,:a_new_optype ----------- !!
                    ,:v_qd_snd_id
                    ,:v_qd_snd_qty
                    ,:v_qd_rcv_doc_id
                    ,:v_qd_rcv_optype_id
                    ,:v_qd_rcv_id
                    ,:v_qd_rcv_qty
                    ,:v_qd_snd_purchase
                    ,:v_qd_snd_retail
                    ,:v_qd_rcv_purchase
                    ,:v_qd_rcv_retail
                );

            end
            close c_qd_rows_for_doc;
        end
    end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'dd_qsum='||v_dd_qsum||', rows: dd='||v_dd_rows||', qd='||v_qd_rows );

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^  -- sp_qd_handle_on_invoice_upd_sts

-- Aux SP that serves just as "redirector" to sp_qd_handle_on_invoice_upd_sts when config 'create_with_split_heavy_tabs=0'
-- Source of this SP will be replaced to reflect actual value of autogen_qdNNNN when config 'create_with_split_heavy_tabs=1'
create or alter procedure sp_qd_handle_on_invoice_adding (
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_new_optype dm_idb
) as
begin
    execute procedure sp_qd_handle_on_invoice_upd_sts( :a_doc_id, :a_old_optype, :a_new_optype );
end

^ -- sp_qd_handle_on_invoice_adding (REDIRECTOR)

-- Aux SP that serves just as "redirector" to sp_qd_handle_on_invoice_upd_sts when config 'create_with_split_heavy_tabs=0'
-- Source of this SP will be replaced to reflect actual value of autogen_qdNNNN when config 'create_with_split_heavy_tabs=1'
create or alter procedure sp_qd_handle_on_invoice_reopen (
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_new_optype dm_idb
) as
begin
    execute procedure sp_qd_handle_on_invoice_upd_sts( :a_doc_id, :a_old_optype, :a_new_optype );
end

^ -- sp_qd_handle_on_invoice_reopen (REDIRECTOR)

create or alter procedure sp_kill_qty_storno (
    a_doc_id dm_idb,
    a_old_optype dm_idb,
    a_new_optype dm_idb,
    a_updating dm_sign,
    a_deleting dm_sign)
as
    declare v_this dm_dbobj = 'sp_kill_qty_storno';
    declare v_info dm_info;
    declare v_dbkey dm_dbkey;
begin
    -- Called from doc_list_biud for deleting doc or updating with changing it state.
    -- 1. For sp_reserve_write_off (FINAL point of ware turnover):
    --    remove data from qdistr into qstorned)
    -- 2. For CANCEL operations (deleting doc or change its state to "previous"):
    --    return storned rows from qstorned to qdistr
    -- 3. For sp_add_invoice_to_stock: change IDs in qdistr.snd_op XOR rcv_op to
    --    new ID (2000-->2100)

    if ( NOT (a_deleting = 1 or a_updating = 1 and a_new_optype is distinct from a_old_optype) )
    then
      --#####
        exit;
      --#####

    v_info = 'dh='|| a_doc_id
             ||' '||iif(a_updating=1,'UPD','DEL')
             ||iif(a_updating=1, ' old_op='||a_old_optype||' new_op='||a_new_optype, ' op='||a_old_optype);

    execute procedure sp_add_perf_log(1, v_this,null, v_info);

    if ( a_updating = 1 and a_new_optype is distinct from a_old_optype ) then
    begin
        ----------------   c h a n g e    o p t y p e _ i d   ------------------
        -- see s`p_cancel_client_order; sp_add_invoice_to_stock;
        -- sp_reserve_write_off, s`p_cancel_write_off
        -- ==> they all change doc_data.optype_id
        if ( a_new_optype = fn_oper_cancel_customer_order() ) then
            begin
                -- S P _ C A N C E L _ C L I E N T _ O R D E R
                -- Kill all records for this doc both in QDistr & QStorned
                -- delete rows in qdistr for currently cancelled client order:
                execute procedure sp_qd_handle_on_cancel_clo( :a_doc_id, :a_old_optype, fn_oper_cancel_customer_order() );
            end

        else if ( a_old_optype = fn_oper_retail_realization() and a_new_optype = fn_oper_retail_reserve() ) then
            -- S P _ C A N C E L _ W R I T E _ O F F
            -- return from QStorned to QDistr records which were previously moved
            -- (when currently deleting doc was created):
            execute procedure sp_ret_qs2qd_on_canc_wroff( :a_doc_id, :a_old_optype, :a_deleting );
            -- prev: direct call execute procedure s~p_kill_qstorno_ret_qs2qd( :a_doc_id, :a_old_optype, :a_deleting );

        else if ( a_old_optype = fn_oper_retail_reserve() and a_new_optype = fn_oper_retail_realization() ) then
            -- S P _ R E S E R V E _ W R I T E _ O F F
            execute procedure sp_qd_handle_on_reserve_upd_sts( :a_doc_id, :a_old_optype, :a_new_optype );
            -- prev: direct call of s~p_kill_qstorno_mov_qd2qs( :a_doc_id, :a_old_optype, :a_new_optype);

        else -- all other updates of doc state, except s`p_cancel_write_off
            -- update rows in qdistr for currently selected doc (3dr arg <> fn_oper_cancel_cust_order):    
            if ( a_old_optype = fn_oper_invoice_get() ) then
                -- S P _ A D D _ I N V O I C E _ T O _ S T O C K
                execute procedure sp_qd_handle_on_invoice_adding( :a_doc_id, :a_old_optype, :a_new_optype );
            else if ( a_old_optype = fn_oper_invoice_add() ) then
                -- S P _ C A N C E L _ A D D I N G _ I N V O I C E
                execute procedure sp_qd_handle_on_invoice_reopen( :a_doc_id, :a_old_optype, :a_new_optype );
            else
                exception ex_bad_argument using(':a_old_optype='||:a_old_optype, v_this );
            -- before: execute procedure s~p_kill_qstorno_handle_qd4dd( :a_doc_id, :a_old_optype, :a_new_optype );

    end -- a_updating = 1 and a_new_optype is distinct from a_old_optype

    if ( a_deleting = 1 ) then -- all other operations that delete document
    begin
        -- return from QStorned to QDistr records which were previously moved
        -- (when currently deleting doc was created):
        if ( :a_old_optype = fn_oper_invoice_get() ) then
            execute procedure sp_ret_qs2qd_on_canc_invoice( :a_doc_id, :a_old_optype, :a_deleting );
        else if ( :a_old_optype = fn_oper_order_for_supplier() ) then
            execute procedure sp_ret_qs2qd_on_canc_supp_order( :a_doc_id, :a_old_optype, :a_deleting );
        else if ( :a_old_optype = fn_oper_retail_reserve() ) then
            begin
                execute procedure sp_ret_qs2qd_on_canc_res_aux( :a_doc_id, :a_old_optype, :a_deleting );
                execute procedure sp_ret_qs2qd_on_canc_reserve( :a_doc_id, :a_old_optype, :a_deleting );
            end
        else
            exception ex_bad_argument using(':a_old_optype='||:a_old_optype, v_this );
        -- prev: direct call of s~p_kill_qstorno_ret_qs2qd( :a_doc_id, :a_old_optype, :a_deleting );
    end -- a_deleting = 1

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_kill_qty_storno


set term ;^
-- View for using in SRV_FIND_QD_QS_MISM as alias of table 'QDistr'.
-- Will be altered in 'oltp_autogen_ddl.sql' when config 'create_with_split_heavy_tabs=1'.
create or alter view v_qdistr_source as
select *
from qdistr
;

-- View for using in SRV_FIND_QD_QS_MISM as alias of table 'QStorned'.
-- Will be altered in 'oltp_autogen_ddl.sql' when config 'create_with_split_heavy_tabs=1'.
create or alter view v_qstorned_source as
select *
from qstorned
;
commit;

set term ^;

create or alter procedure srv_find_qd_qs_mism(
    a_doc_list_id type of dm_idb,
    a_optype_id type of dm_idb,
    a_after_deleting_doc dm_sign -- 1==> doc has been deleted, must check orphans only in qdistr+qstorned
) as
    declare v_this dm_dbobj = 'srv_find_qd_qs_mism';
    declare v_gdscode int;
    declare v_dd_mismatch_id bigint;
    declare v_dd_mismatch_qty dm_qty;
    declare v_qd_qs_orphan_src dm_dbobj; -- name of table where orphan row(s) found
    declare v_qd_qs_orphan_doc dm_idb;
    declare v_qd_qs_orphan_id dm_idb;
    declare v_qd_qs_orphan_sid dm_idb;
    declare v_qd_sum dm_qty;
    declare v_qs_sum dm_qty;
    declare v_info dm_info = '';
    declare c_chk_violation_code int = 335544558; -- check_constraint
    declare v_dh_id dm_idb;
    declare v_dd_id dm_idb;
    declare v_ware_id dm_idb;
    declare v_dd_qty dm_qty;
    declare v_all_qty_sum dm_qty;
    declare v_all_qd_sum dm_qty;
    declare v_all_qs_sum dm_qty;
    declare v_snd_optype_id dm_idb;
    declare v_rcv_optype_id dm_idb;
    declare v_rows_handled int;
    declare v_rows int = 0; -- 18.12.2018
    declare v_worker_id int;
    declare c_qd_qs_orphans cursor for ( -- used after deletion of doc: search for orphans in qd & qs
        -- deciced neither add index on qdistr.doc_id nor modify qdistr PK and set its key = {id, doc_id} (performance)
        select r.doc_data_id, r.ware_id
        from tmp$result_set r -- ::: NB ::: this table must be always filled in SPs which REMOVES (cancel) doc with wares
        where r.doc_id = :a_doc_list_id
    );

    declare c_dd_qty_match_qd_qs_counts cursor for (
        select f.dd_id, f.ware_id, f.dd_qty, f.qd_cnt, f.qs_cnt
        from (
            select e.dd_id, e.ware_id, e.qty as dd_qty, e.qd_cnt, coalesce(sum(qs.snd_qty),0) as qs_cnt
            -- PLAN SORT (JOIN (JOIN (SORT (E D D INDEX (FK_DOC_DATA_DOC_LIST)), E QD INDEX (QDISTR_SNDOP_RCVOP_SNDID_DESC)), QS INDEX (QSTORNED_SND_ID)))
            from (
                select
                    d.id as dd_id
                    ,d.ware_id
                    ,d.qty
                    ,coalesce(sum(qd.snd_qty),0) qd_cnt
                    --,iif(:a_optype_id=3400, 3300, :a_optype_id) as snd_optype_id
                    --,:v_snd_optype_id as snd_optype_id -- core-4927, affected 2.5 only
                from doc_data d
                left join v_qdistr_source qd on
                    -- {ware,snd_optype_id,rcv_optype_id} ==> Index Range Scan (full match, since )
                    -- Full match since 01.09.2015 2355, see:
                    -- http://sourceforge.net/p/firebird/code/62176 (3.0)
                    -- http://sourceforge.net/p/firebird/code/62177 (2.5.5)
                    qd.ware_id = d.ware_id
                    -- 07.09.2015. In 2.5, before core-4927 (http://sourceforge.net/p/firebird/code/62200):
                    -- we had to avoid usage of "iif()" for evaluating column that will be involved in
                    -- JOIN with "unioned" view: it (IIF function) prevented the condition from being
                    -- pushed into the union for better optimization. This lead to unneccessary index
                    -- scans of tables from unioned-view that sor sure did not contain req. data.
                    -- Thus we use here parameter ":v_snd_optype_id" which will be evaluated BEFORE
                    -- in separate IIF statement:
                    and qd.snd_optype_id = :v_snd_optype_id
                    and qd.rcv_optype_id = :v_rcv_optype_id
                    and qd.snd_id = d.id
                    and qd.worker_id is not distinct from :v_worker_id
                where
                    d.doc_id  = :a_doc_list_id
                group by d.id, d.ware_id, d.qty
            ) e
            left join v_qstorned_source qs on
                -- NB: we can skip this join if previous one produces ERROR in results:
                -- sum of amounts in doc_data rows has to be NOT LESS than sum(snd_qty) on qdistr
                -- (except CANCELLED client order for which qdistr must NOT contain any row for this doc)
                (
                    :v_snd_optype_id <> 1100 and e.qty >= e.qd_cnt
                    or
                    :v_snd_optype_id = 1100 and e.qd_cnt = 0
                )
                and qs.snd_id = e.dd_id
                and qs.worker_id is not distinct from :v_worker_id
            group by e.dd_id, e.ware_id, e.qty, e.qd_cnt
        ) f
    );

begin

    -- Search for mismatches b`etween doc_data.qty and number of records in
    -- v_qdistr + v_qstorned, for all operation. Algorithm for deleted ("cancelled")
    -- document differs from document that was just created or updated its state:
    -- we need found orphan rows in v_qdistr + v_qstorned when document has been removed
    -- (vs. checking sums of doc_data.qty and sum(qty) when doc. is created/updated)
    -- Log mismatches if they found and raise exc`eption.
    -- ### NB ### GTT tmp$result_set need to be fulfilled with data of doc that
    -- is to be deleted, BEFORE this deletion issues. It's bad (strong link between
    -- modules) but this is the only way to avoid excessive indexing of v_qdistr & v_qstorned.

    v_info = 'dh='||a_doc_list_id||', op='||a_optype_id;
    execute procedure sp_add_perf_log(1, v_this); -- , null, v_info);

    v_worker_id = fn_this_worker_seq_no();

    v_dd_mismatch_id = null;
    -- This value is used in CURSOR c_dd_qty_match_qd_qs_counts as argument of join:
    v_snd_optype_id = iif(:a_optype_id=3400, 3300, :a_optype_id);

    select r.rcv_optype_id
    from v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
    where r.snd_optype_id = :a_optype_id and coalesce(r.storno_sub,1)=1
    into v_rcv_optype_id;

    if ( a_after_deleting_doc = 1 ) then -- call after doc has been deleted: NO rows in doc_data but we must check orphan rows in qd&qs for this doc!
        begin
            select h.id from doc_list h where h.id = :a_doc_list_id into v_dh_id;
            if ( v_dh_id is NOT null or not exists(select * from tmp$result_set)  ) then
                exception ex_bad_argument using('a_after_deleting_doc', v_this) ; -- 'argument @1 passed to unit @2 is invalid';

            v_rows_handled = 0;
            open c_qd_qs_orphans;
            while ( v_dh_id is null ) do
            begin
                fetch c_qd_qs_orphans into v_dd_id, v_ware_id; -- get data of doc which have been saved in tmp$result_set
                if ( row_count = 0 ) then leave;
                v_rows_handled = v_rows_handled + 1;

                -- Added 18.12.2018
                v_rows = v_rows + 1;
                if ( mod(v_rows, 100) = 0 ) then
                    -- Check whether test can continue: if request to stop exists
                    -- then raises ex`ception to stop this session ASAP.
                    execute procedure sp_check_to_stop_work;

                select first 1 'v_qdistr' as src, qd.doc_id, qd.snd_id, qd.id
                from v_qdistr_source qd
                where
                    -- {ware,snd_optype_id,rcv_optype_id} ==> Index Range Scan (full match, since )
                    -- Full match since 01.09.2015 2355, see:
                    -- http://sourceforge.net/p/firebird/code/62176 (3.0)
                    -- http://sourceforge.net/p/firebird/code/62177 (2.5.5)
                    qd.ware_id = :v_ware_id
                    and qd.snd_optype_id = :v_snd_optype_id
                    and qd.rcv_optype_id = :v_rcv_optype_id
                    -- This is mandatory otherwise get lot of different docs for the same {ware,snd_optype_id,rcv_optype_id}:
                    and qd.snd_id = :v_dd_id
                    and qd.worker_id is not distinct from :v_worker_id
                into v_qd_qs_orphan_src, v_qd_qs_orphan_doc, v_qd_qs_orphan_sid, v_qd_qs_orphan_id;

                if ( v_qd_qs_orphan_id is null ) then -- run 2nd check only if there are NO row in QDistr
                    select first 1 'v_qstorned' as src, qs.doc_id, qs.snd_id, qs.id
                    from v_qstorned_source qs
                    where qs.snd_id = :v_dd_id
                    into v_qd_qs_orphan_src, v_qd_qs_orphan_doc, v_qd_qs_orphan_sid, v_qd_qs_orphan_id;

                if ( v_qd_qs_orphan_id is NOT null ) then
                begin
                    v_info = trim(v_info)
                        || ': orphan '||v_qd_qs_orphan_src||'.id='||v_qd_qs_orphan_id
                        || ' for deleted doc='||v_qd_qs_orphan_doc
                        || ', snd_id='||v_qd_qs_orphan_sid
                        || ', ware='||v_ware_id;
                    leave;
                end
            end
            close c_qd_qs_orphans;
            if ( v_qd_qs_orphan_id is null ) then
                v_info = trim(v_info)||': no data in qd+qs for deleted '||v_rows_handled||' rows';

        end
    else ------------------  _N O T_   a f t e r    d e l e t i n g  -------
        begin
            v_all_qty_sum = 0;
            v_all_qd_sum = 0;
            v_all_qs_sum = 0;
        
            v_rows_handled = 0;
            open c_dd_qty_match_qd_qs_counts;
            while ( 1 = 1 ) do
            begin
                fetch c_dd_qty_match_qd_qs_counts
                into v_dd_id, v_ware_id, v_dd_qty, v_qd_sum, v_qs_sum;
                -- e.dd_id, e.qty, e.qd_cnt, coalesce(sum(qs.snd_qty),0) as qs_cnt
                if (row_count = 0) then leave;

                -- Added 18.12.2018
                v_rows = v_rows + 1;
                if ( mod(v_rows, 100) = 0 ) then
                    -- Check whether test can continue: if request to stop exists
                    -- then raises ex`ception to stop this session ASAP.
                    execute procedure sp_check_to_stop_work;

                v_rows_handled = v_rows_handled + v_qd_sum + v_qs_sum;
                v_all_qty_sum = v_all_qty_sum + v_dd_qty; -- total AMOUNT in ALL rows of document
                v_all_qd_sum = v_all_qd_sum + v_qd_sum; -- number of rows in QDistr for ALL wares of document
                v_all_qs_sum = v_all_qs_sum + v_qs_sum; -- number of rows in v_qstorned for ALL wares of document

                if ( a_optype_id <> 1100 and v_dd_qty <> v_qd_sum + v_qs_sum -- error, immediately stop check if so!
                     or
                     a_optype_id = 1100 and v_qd_sum + v_qs_sum > 0 -- it's WRONG when we cancel client order and some rows still exist in qdistr or v_qstorned for this doc!
                   ) then
                begin
                    v_dd_mismatch_id = v_dd_id;
                    v_dd_mismatch_qty = v_dd_qty;
                    leave;
                end
            end
            close c_dd_qty_match_qd_qs_counts;

            if ( v_dd_mismatch_id is NOT null ) then
                begin
                    v_info=trim(v_info)
                           || ': dd='||v_dd_mismatch_id
                           || ', ware='||v_ware_id
                           || ', sum_qty='||cast(v_all_qty_sum as int)
                           || ', problem_qty='||cast(v_dd_mismatch_qty as int);
                    if ( a_optype_id <> 1100 ) then
                        v_info = v_info
                           || ' - mism: qd_cnt='||cast(v_qd_sum as int)
                           || iif( v_qs_sum >=0, ', qs_cnt='||cast(v_qs_sum as int), ', qs_cnt=n/a');
                    else
                        v_info = v_info
                           || ' - no_removal: qd_cnt='||cast(v_qd_sum as int)
                           || iif( v_qs_sum >=0, ', qs_cnt='||cast(v_qs_sum as int), ', qs_cnt=n/a');
                end
            else -- ok
                v_info = trim(v_info)
                    ||', sum_qty='||cast(v_all_qty_sum as int)
                    ||', cnt_qds='||cast((v_all_qd_sum + v_all_qs_sum) as int)
                    ||', rows_handled='||v_rows_handled;
        
        end -- block for NOT after deleting doc

    if ( a_after_deleting_doc = 0 and v_dd_mismatch_id is NOT null
         or
         a_after_deleting_doc = 1 and v_qd_qs_orphan_id is NOT null
       ) then
    begin
        -- dump dirty data:
        execute procedure zdump4dbg(:a_doc_list_id); --,:a_doc_data_id);
        --#######
        if ( a_after_deleting_doc = 1) then
            exception ex_orphans_qd_qs_found using( a_doc_list_id, v_qd_qs_orphan_sid, v_qd_qs_orphan_src, v_qd_qs_orphan_id );
            -- 'at least one row found for DELETED doc id=@1, snd_id=@2: @3.id=@4';
        else
            exception ex_mism_doc_data_qd_qs using( v_dd_mismatch_id, v_dd_mismatch_qty, v_qd_sum, v_qs_sum );
            -- at least one mismatch btw doc_data.id=@1 and qdistr+v_qstorned: qty=@2, qd_cnt=@3, qs_cnt=@4
            --#######
    end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'ok, '||v_info);

when any do
    begin
        v_gdscode = iif( :v_dd_mismatch_id is null, gdscode, :c_chk_violation_code);
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            :v_gdscode,
            'MISMATCH, '||v_info,
            v_this,
            fn_halt_sign(:v_gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --########
        exception;  -- ::: nb ::: anonimous but in when-block!
        --########
    end
end
^ -- srv_find_qd_qs_mism


create or alter procedure sp_add_money_log(
    a_doc_id dm_idb,
    a_old_mult dm_sign,
    a_old_agent_id dm_idb,
    a_old_op dm_idb,
    a_old_purchase type of dm_cost, -- NB: must allow negative values!
    a_old_retail type of dm_cost,     -- NB: must allow negative values!
    a_new_mult dm_sign,
    a_new_agent_id dm_idb,
    a_new_op dm_idb,
    a_new_purchase type of dm_cost, -- NB: must allow negative values!
    a_new_retail type of dm_cost      -- NB: must allow negative values!
)
as
begin
    -- called from trg d`oc_list_aiud for every operation which affects to contragent saldo
    if ( a_old_mult <> 0 ) then
        insert into money_turnover_log ( -- "log" of all changes in doc_list.cost_xxx
            doc_id,
            agent_id,
            optype_id,
            cost_purchase, -- NB: this field must allow negative values!
            cost_retail   -- NB: this field must allow negative values!
        )
        values(
            :a_doc_id, -- ref to doc_list
            :a_old_agent_id,
            :a_old_op,
            -:a_old_purchase,
            -:a_old_retail
        );

    if ( a_new_mult <> 0  ) then
        insert into money_turnover_log ( -- "log" of all changes in doc_list.cost_xxx
            doc_id,
            agent_id,
            optype_id,
            cost_purchase, -- NB: this field must allow negative values!
            cost_retail   -- NB: this field must allow negative values!
        )
        values(
            :a_doc_id, -- ref to doc_list
            :a_new_agent_id,
            :a_new_op,
            :a_new_purchase,
            :a_new_retail
        );
end

^ -- sp_add_money_log

------------------------------------------------------------------------------

create or alter procedure sp_lock_dependent_docs(
    a_base_doc_id dm_idb,
    a_base_doc_oper_id dm_idb default null -- = (for invoices which are to be 'reopened' - old_oper_id)
)
as
    declare v_rcv_optype_id dm_idb;
    declare v_dependend_doc_id dm_idb;
    declare v_dependend_doc_state dm_idb;
    declare v_catch_bitset bigint;
    declare v_dbkey dm_dbkey;
    declare v_info dm_info;
    declare v_list dm_info;
    declare v_this dm_dbobj = 'sp_lock_dependent_docs';
begin

    v_info = 'base_doc='||a_base_doc_id;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    if ( a_base_doc_oper_id is null ) then
        select h.optype_id
        from doc_list h
        where h.id = :a_base_doc_id
        into a_base_doc_oper_id;

    v_rcv_optype_id = decode(a_base_doc_oper_id,
                             fn_oper_invoice_add(),  fn_oper_retail_reserve(),
                             fn_oper_order_for_supplier(), fn_oper_invoice_get(),
                             null
                            );
    delete from tmp$dep_docs d where d.base_doc_id = :a_base_doc_id;
    for
        select x.dependend_doc_id, h.state_id, h.rdb$db_key
        -- 30.12.2014: PLAN JOIN (SORT (X Q INDEX (QSTORNED_DOC_ID)), H INDEX (PK_DOC_LIST))
        -- (added field rcv_doc_id in table qstorned, now can remove join with doc_data!)
        from (
            -- Checked plan 13.07.2014:
            -- PLAN (Q ORDER QSTORNED_RCV_ID INDEX (QSTORNED_DOC_ID))
            select q.rcv_doc_id dependend_doc_id
            from v_qstorned_source q
            where
                q.doc_id = :a_base_doc_id -- choosen invoice which is to be re-opened
                and q.snd_optype_id = :a_base_doc_oper_id
                and q.rcv_optype_id = :v_rcv_optype_id
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            group by 1
        ) x
        join doc_list h on x.dependend_doc_id = h.id
        into v_dependend_doc_id, v_dependend_doc_state, v_dbkey
    do begin
        -- immediatelly try to lock record in order to avoid wast handling
        -- of 99 docs and get fault on 100th one!
        -- (see s`p_cancel_adding_invoice, s`p_cancel_supplier_order)
        v_info = 'try lock dependent doc_id='||v_dependend_doc_id;
        select h.rdb$db_key
        from doc_list h
        where h.rdb$db_key = :v_dbkey -- lock_conflict can occur here!
        for update with lock
        into v_dbkey;

        begin
            -- NB:  BASE_DOC_ID,DEPENDEND_DOC_ID  ==> UNIQ index in tmp$dep_docs
            insert into tmp$dep_docs( base_doc_id, dependend_doc_id, dependend_doc_state)
            values( :a_base_doc_id, :v_dependend_doc_id, :v_dependend_doc_state );
        when any do
            -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
            -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
            -- catched it's kind of exception!
            -- 1) tracker.firebirdsql.org/browse/CORE-3275
            --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
            -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
            begin
              -- supress dup ex`ception - it is normal in this case!
              if ( NOT fn_is_uniqueness_trouble(gdscode) ) then exception;
            end
        end
    end

    v_catch_bitset = cast(rdb$get_context('USER_SESSION','QMISM_VERIFY_BITSET') as bigint);
    -- See oltp_main_filling.sql for definition of bitset var `QMISM_VERIFY_BITSET`:
    -- bit#0 := 1 ==> perform calls of srv_catch_qd_qs_mism in d`oc_list_aiud => sp_add_invnt_log
    --                in order to register mismatches b`etween doc_data.qty and total number of rows
    --                in qdistr + qstorned for doc_data.id
    -- bit#1 := 1 ==> perform calls of SRV_CATCH_NEG_REMAINDERS from INVNT_TURNOVER_LOG_AI
    --                (instead of totalling turnovers to `invnt_saldo` table)
    -- bit#2 := 1 ==> allow dump dirty data into z-tables for analysis, see sp zdump4dbg, in case
    --                when some 'bad exception' occurs (see ctx var `HALT_TEST_ON_ERRORS`)
    if ( bin_and( v_catch_bitset, 7 ) > 0 ) then -- ==> any of bits #0..2 is ON
       begin
           v_list=left( ( select list(d.dependend_doc_id) from tmp$dep_docs d where d.base_doc_id=:a_base_doc_id ), 255-char_length(v_info)-15);
           v_info = 'depDocsLst='|| coalesce(nullif(v_list,''),'<empty>');
       end
    else
       begin
           v_info = 'depDocsCnt='||( select count(*) from tmp$dep_docs d where d.base_doc_id=:a_base_doc_id );
       end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, v_info );

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_lock_dependent_docs

-- 29.07.2014: STUB, need for debug view z_invoices_to_be_adopted, will be redefined in oltp30_sp.sql:
create or alter procedure sp_get_clo_for_invoice( a_selected_doc_id dm_idb )
returns (
    clo_doc_id type of dm_idb,
    clo_agent_id type of dm_idb
)
as begin
  suspend;
end
^
set term ;^
commit;

------------------------------------------------------------------------------

set term ^;

-- several debug proc for catch cases when negative remainders encountered
create or alter procedure srv_check_neg_remainders( -- 28.09.2014, instead s`rv_catch_neg
    a_doc_list_id dm_idb,
    a_optype_id dm_idb
) as
declare v_id bigint;
    declare v_catch_bitset bigint;
    declare v_curr_tx bigint;
    declare c_chk_violation_code int = 335544558; -- check_constraint
    declare v_msg dm_info = '';
    declare v_info dm_info = '';
    declare v_this dm_dbobj = 'srv_check_neg_remainders';
begin
    -- called from d`oc_list_aiud
    -- #########################
    -- See oltp_main_filling.sql for definition of bitset var `QMISM_VERIFY_BITSET`:
    -- bit#0 := 1 ==> perform calls of srv_catch_qd_qs_mism in d`oc_list_aiud => sp_add_invnt_log
    --                in order to register mismatches b`etween doc_data.qty and total number of rows
    --                in qdistr + qstorned for doc_data.id
    -- bit#1 := 1 ==> perform calls of SRV_CATCH_NEG_REMAINDERS from INVNT_TURNOVER_LOG_AI
    --                (instead of totalling turnovers to `invnt_saldo` table)
    -- bit#2 := 1 ==> allow dump dirty data into z-tables for analysis, see sp zdump4dbg, in case
    --                when some 'bad exception' occurs (see ctx var `HALT_TEST_ON_ERRORS`)
    v_catch_bitset = cast(rdb$get_context('USER_SESSION','QMISM_VERIFY_BITSET') as bigint);
    if ( bin_and( v_catch_bitset, 2 ) = 0 ) then -- job of this SP meaningless because of totalling
        --####
          exit;
        --####

    -- do NOT add calls of sp_check_to_stop_work or sp_check_nowait_or_timeout:
    -- this SP is called very often!

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    v_msg ='dh='||:a_doc_list_id || ', op='||fn_mcode_for_oper( :a_optype_id );

    v_id = null;
    select first 1
        n.ware_id
        ,:v_msg
        || ', w='||n.ware_id||', dd='||n.dd_id
        || ', neg:'
        || trim( trailing from iif( n.qty_ord<0,' q_ord='||n.qty_ord,'' ) )
        || trim( trailing from iif( n.qty_sup<0,' q_sup='||n.qty_sup,'' ) )
        || trim( trailing from iif( n.qty_avl<0,' q_avl='||n.qty_avl,'' ) )
        || trim( trailing from iif( n.qty_res<0,' q_res='||n.qty_res,'' ) )
        || trim( trailing from iif( n.qty_inc<0,' q_inc='||n.qty_inc,'' ) )
        || trim( trailing from iif( n.qty_out<0,' q_out='||n.qty_out,'' ) )
        || trim( trailing from iif( n.qty_clo<0,' q_clo='||n.qty_clo,'' ) )
        || trim( trailing from iif( n.qty_clr<0,' q_clr='||n.qty_clr,'' ) )
        || trim( trailing from iif( n.qty_acn<0,' q_acn='||n.qty_acn,'' ) )
        || trim( trailing from iif( n.cost_acn<0,' $_acn='||n.cost_acn,'' ) )
    from --v_saldo_invnt n
    (
        select
            ng.ware_id
            ,min(ng.doc_data_id) as dd_id -- no matter min or max
            ,sum(o.m_qty_clo * ng.qty_diff) qty_clo
            ,sum(o.m_qty_clr * ng.qty_diff) qty_clr
            ,sum(o.m_qty_ord * ng.qty_diff) qty_ord
            ,sum(o.m_qty_sup * ng.qty_diff) qty_sup
            ,sum(o.m_qty_avl * ng.qty_diff) qty_avl
            ,sum(o.m_qty_res * ng.qty_diff) qty_res
            ,sum(o.m_cost_inc * ng.qty_diff) qty_inc
            ,sum(o.m_cost_out * ng.qty_diff) qty_out
            ,sum(o.m_cost_inc * ng.cost_diff) cost_inc
            ,sum(o.m_cost_out * ng.cost_diff) cost_out
            -- amount "on hand" as it seen by accounter:
            ,sum(o.m_qty_avl * ng.qty_diff) + sum(o.m_qty_res * ng.qty_diff) qty_acn
            -- total cost "on hand" in purchasing prices:
            ,sum(o.m_cost_inc * ng.cost_diff) - sum(o.m_cost_out * ng.cost_diff) cost_acn
        from invnt_turnover_log ng
        join optypes o on ng.optype_id=o.id
        join doc_data d on ng.ware_id = d.ware_id -- ng.doc_data_id = d.id
        where d.doc_id = :a_doc_list_id
        --where ng.ware_id = :a_ware_id
        group by
            ng.ware_id
            --,ng.doc_data_id
    ) n
    where
           n.qty_ord<0 or n.qty_sup<0 or n.qty_avl<0 or n.qty_res<0
        or n.qty_inc<0 or n.qty_out<0 or n.qty_clo<0 or n.qty_clr<0
        or n.qty_acn<0 or n.cost_acn<0
    into v_id, v_info;
    
    if ( v_id is not null) then
    begin
        v_curr_tx = current_transaction;
        in autonomous transaction do
        begin -- 26.09.2014 2222, temply
            insert into perf_log( -- current unit: srv_check_neg_remainders
                unit,
                exc_unit,
                fb_gdscode,
                trn_id,
                info,
                exc_info,
                stack,
                dump_trn
            ) values (
                :v_this,
                '!',
               :c_chk_violation_code,
               :v_curr_tx,
               :v_info,
               :v_info, --'ex_neg_remainders_encountered',
               :v_this, -- fn_get_stack(),
               current_transaction
            );
            -- current sp = srv_check_neg_remainders
            execute procedure sp_halt_on_error('5', :c_chk_violation_code, :v_curr_tx); -- '5' ==> ABEND because of negative stock remainder
            -- a_char char(1) default '1',
            -- a_gdscode bigint default null,
            -- a_trn_id bigint default null,
            -- a_need_to_stop smallint default null
        end
        -- 335544558 check_constraint    Operation violates CHECK constraint @1 on view or table @2.
        execute procedure sp_add_to_abend_log(
          'ex_neg_remainders_encountered',
          :c_chk_violation_code,
          v_info,
          v_this,
          1 -- ::: nb ::: force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        -- 4 debug: dump dirty data:
        execute procedure zdump4dbg; -- (null, a_doc_data_id, v_id);

        --########
        exception ex_neg_remainders_encountered using( v_id, v_info ); -- 'at least one remainder < 0, ware_id=@1';
        --########
    end
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this,null, 'ok, '||v_msg);

when any do
    begin
        --########
        exception;  -- ::: nb ::: anonimous but in when-block!
        --########
    end
end

^ -- srv_check_neg_remainders

set term ;^
commit;

-------------------------------------------------------------------------------
-- ############################   V I E W S   #################################
-------------------------------------------------------------------------------

create or alter view v_cancel_client_order as
-- source for random choose client_order document to be cancelled
select h.id
from doc_list h
where
    h.optype_id = 1000 -- fn_oper_order_by_customer
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_cancel_supplier_order as
-- Source for random choose supplier order doc to be cancelled
select h.id
from doc_list h
where
    h.optype_id = 1200 -- fn_oper_order_for_supplier
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;


create or alter view v_cancel_supplier_invoice as
-- source for random choose supplier order doc to be cancelled
select h.id
from doc_list h
where
    h.optype_id = 2000 -- fn_oper_invoice_get
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_add_invoice_to_stock as
select h.id
from doc_list h
where
    h.optype_id = 2000 -- fn_oper_invoice_get
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_cancel_adding_invoice as
select h.id
from doc_list h
where
    h.optype_id = 2100 -- fn_oper_invoice_add
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_cancel_customer_reserve as
-- source for s`p_cancel_customer_reserve: random take customer reserve
-- and CANCEL it (i.e. DELETE from doc_list)
select h.id
from doc_list h
where
    h.optype_id = 3300 -- fn_oper_retail_reserve
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_reserve_write_off as
-- source for random take customer reserve and make WRITE-OFF (i.e. 'close' it):
select h.id, h.agent_id, h.state_id, h.dts_open, h.dts_clos, h.cost_retail
from doc_list h
where
    h.optype_id = 3300 -- fn_oper_retail_reserve
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_cancel_write_off as
-- source for random take CLOSED customer reserve and CANCEL writing-off
-- (i.e. 'reopen' this doc for changes or removing):
select h.id
from doc_list h
where
    h.optype_id = 3400 -- fn_oper_retail_realization
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_cancel_payment_to_supplier as
-- source for random taking INVOICE with some payment and CANCEL all payments:
select h.id, h.agent_id, h.cost_purchase
from doc_list h
where
    h.optype_id = 4000 -- fn_oper_pay_to_supplier
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;

create or alter view v_cancel_customer_prepayment as
select h.id, h.agent_id, h.cost_retail
from doc_list h
where
    h.optype_id = 5000 -- fn_oper_pay_from_customer
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
;


create or alter view v_all_customers as
-- source for random taking agent from ALL customers
-- (see sp_customer_prepayment in case when all customer reserve docs are full paid)
select a.id
from agents a
where a.is_customer=1
;

create or alter view v_all_suppliers as
select a.id
from agents a
where a.is_supplier=1
;

create or alter view v_our_firm as
select a.id
from agents a
where a.is_our_firm=1
;

create or alter view v_all_wares as
-- source for random choose ware_id in SP_CLIENT_ORDER => SP_FILL_SHOPPING_CART
-- Plan in 3.0 (checked 06.02.2015):
-- PLAN (C ORDER TMP_SHOPCART_UNQ) // prevent from bitmap building in tmp$shopping_cart for each row of wares!
-- PLAN (A NATURAL)
select a.id
from wares a
where not exists(select * from tmp$shopping_cart c where c.id = a.id order by c.id) -- 19.09.2014
;

------------------------------
-- 12.09.2014 1920: refactoring v_random_find_xxx views for avl_res, clo_ord and ord_sup
-- use `wares` as driver table instead of scanning qdistr for seach doc_data.id
-- Performance increased from ~1250 up to ~2000 bop / minute (!)
------------------------------

-- ############## A V L => R E S ###############
-- Views for operation 'Create customer reserve from AVALIABLE remainders'
-- #############################################

create or alter view v_random_find_avl_res
as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choose ware_id in sp_customer_reserve => sp_fill_shopping_cart:
-- take record from invoice which has been added to stock and add it to set for
-- new customer reserve - from avaliable remainders (not linked with client order)
-- Checked 12.09.2014:
--PLAN (V TMP$SHOPPING_CART INDEX (TMP_SHOPCART_UNQ))
--PLAN (V QDISTR ORDER QDISTR_WARE_SNDOP_RCVOP) -- ::: NB ::: no bitmap here (speed!)
--PLAN (V W ORDER WARES_ID_DESC)
select w.id
from wares w
where
    not exists(select * from tmp$shopping_cart c where c.id = w.id order by c.id)
    and exists(
        select * from qdistr q
        where
            q.ware_id = w.id
            and q.snd_optype_id = 2100
            and q.rcv_optype_id = 3300
            -- 12.08.2018: sequential number of ISQL session that queries this view.
            -- This filter is added with purpose to reduce number of lock-conflict errors:
            and q.worker_id is not distinct from fn_this_worker_seq_no()
        order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
    );

create or alter view v_min_id_avl_res as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choose ware_id in sp_customer_reserve => sp_fill_shopping_cart:
-- take record from invoice which has been added to stock and add it to set for
-- new customer reserve - from ***AVALIABLE*** remainders (not linked with client order)
    select w.id
    from wares w
    where
        exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 2100
                and q.rcv_optype_id = 3300
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            -- 3.0 only: supress building index bitmap on QDistr:
            order by ware_id, snd_optype_id, rcv_optype_id -- do NOT use this 'order by' in 2.5!
        )
    order by w.id asc -- ascend, we search for MINIMAL id
    rows 1
;

create or alter view v_max_id_avl_res as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
--PLAN (Q ORDER QDISTR_WARE_SNDOP_RCVOP)
--PLAN (W ORDER WARES_ID_DESC)
    select w.id
    from wares w
    where
        exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 2100
                and q.rcv_optype_id = 3300
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            -- 3.0 only: supress building index bitmap on QDistr:
            order by ware_id, snd_optype_id, rcv_optype_id -- do NOT use this 'order by' in 2.5!
        )
    order by w.id desc -- descend, we search for MAXIMAL id
    rows 1
;

-- ############## C L O => O R D ###############
-- Views for operation 'Create order to SUPPLIER on the basis of CUSTOMER orders'
-- #############################################

create or alter view v_random_find_clo_ord as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
-- Checked 12.09.2014
--PLAN (V TMP$SHOPPING_CART INDEX (TMP_SHOPCART_UNQ))
--PLAN (V QDISTR ORDER QDISTR_WARE_SNDOP_RCVOP) -- ::: NB ::: no bitmap here (speed!)
--PLAN (V W ORDER WARES_ID_DESC)
select w.id
from wares w
where
    not exists(select * from tmp$shopping_cart c where c.id = w.id order by c.id)
    and exists(
        select * from qdistr q
        where
            q.ware_id = w.id
            and q.snd_optype_id = 1000
            and q.rcv_optype_id = 1200
            -- 12.08.2018: sequential number of ISQL session that queries this view.
            -- This filter is added with purpose to reduce number of lock-conflict errors:
            and q.worker_id is not distinct from fn_this_worker_seq_no()
        -- 3.0 only: supress building index bitmap on QDistr
        order by ware_id, snd_optype_id, rcv_optype_id
    );

create or alter view v_min_id_clo_ord as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
    select w.id
    from wares w
    where
        exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1000
                and q.rcv_optype_id = 1200
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            -- 3.0 only: supress building index bitmap on QDistr:
            order by ware_id, snd_optype_id, rcv_optype_id -- do NOT use this 'order by' in 2.5!
        )
    order by w.id asc -- ascend, we search for MINIMAL id
    rows 1
;

create or alter view v_max_id_clo_ord as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
    select w.id
    from wares w
        where exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1000
                and q.rcv_optype_id = 1200
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            -- 3.0 only: supress building index bitmap on QDistr:
            order by ware_id, snd_optype_id, rcv_optype_id -- do NOT use this 'order by' in 2.5!
        )
    order by w.id desc -- descend, we search for MAXIMAL id
    rows 1
;

-- ############## O R D => S U P ###############
-- Views for operation 'Create invoice from supplier on the basis of OUR orders to him'
-- #############################################

create or alter view v_random_find_ord_sup as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from supplier order to be added into invoice by him
-- Checked 12.09.2014:
--PLAN (V TMP$SHOPPING_CART INDEX (TMP_SHOPCART_UNQ))
--PLAN (V QDISTR ORDER QDISTR_WARE_SNDOP_RCVOP) -- ::: NB ::: no bitmap here (speed!)
--PLAN (V W ORDER WARES_ID_DESC)
    select w.id
    from wares w
    where
        not exists(select * from tmp$shopping_cart c where c.id = w.id order by c.id)
        and exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1200 -- fn_oper_order_for_supplier()
                and q.rcv_optype_id = 2000
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
        )
;

create or alter view v_min_id_ord_sup as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
    select w.id
    from wares w
    where
        exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1200
                and q.rcv_optype_id = 2000
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            -- 3.0 only: supress building index bitmap on QDistr:
            order by ware_id, snd_optype_id, rcv_optype_id -- do NOT use this 'order by' in 2.5!
        )
    order by w.id asc -- ascend, we search for MINIMAL id
    rows 1
;

create or alter view v_max_id_ord_sup as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
    select w.id
    from wares w
        where exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1200
                and q.rcv_optype_id = 2000
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            -- 3.0 only: supress building index bitmap on QDistr:
            order by ware_id, snd_optype_id, rcv_optype_id -- do NOT use this 'order by' in 2.5!
        )
    order by w.id desc -- descend, we search for MAXIMAL id
    rows 1
;

-- ############## C L O => R E S ###############
-- Views for operation 'Create reserve based on client order'
-- #############################################

create or alter view v_random_find_clo_res as
-- 08.09.2015: remove join from here, reduce number of IRs at ~1.5x
-- ################################################################################
-- ### NB DDL of this view will be replaced with code WITHOUT doc_data querying ###
-- ### if config param 'split_heavy_tabs' = 1, see: oltp_split_heavy_tabs_1.sql ###
-- ################################################################################
    select h.id
    from doc_list h
    where h.optype_id = 1000
        -- 12.08.2018: sequential number of ISQL session that queries this view.
        -- This filter is added with purpose to reduce number of lock-conflict errors:
        and h.worker_id is not distinct from fn_this_worker_seq_no()
        and exists(
            select *
            from doc_data d where d.doc_id = h.id
            and exists(
                select *
                from qdistr q
                where
                    q.ware_id = d.ware_id
                    and q.snd_optype_id = 1000 -- fn_oper_order_by_customer()
                    and q.rcv_optype_id = 3300 -- fn_oper_retail_reserve()
                    and q.snd_id = d.id
                    -- 12.08.2018: sequential number of ISQL session that queries this view.
                    -- This filter is added with purpose to reduce number of lock-conflict errors:
                    and q.worker_id is not distinct from fn_this_worker_seq_no()
                -- prevent from building bitmap, 3.0 only:
                order by q.ware_id, q.snd_optype_id, q.rcv_optype_id
            )
            order by d.doc_id -- prevent from building bitmap, 3.0 only
        )
;

-------------------------------------------------------------------------------

create or alter view v_min_id_clo_res as
-- DDL since 11.01.2019
--PLAN (Q ORDER XQD_1000_3300_WA_SO_RO_WKR_SND)
--PLAN (D ORDER FK_DOC_DATA_DOC_LIST)
--PLAN (H ORDER PK_DOC_LIST INDEX (DOC_LIST_WORKER_OPTYPE))
-- ################################################################################
-- ### NB DDL of this view will be replaced with code WITHOUT doc_data querying ###
-- ### if config param 'split_heavy_tabs' = 1, see: oltp_split_heavy_tabs_1.sql ###
-- ################################################################################
select h.id
from doc_list h
-- >>> this inner join had extremely POOR performance! >>> join doc_data d on h.id = d.doc_id
where h.optype_id = 1000
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
    and exists(
        select *
        from doc_data d where d.doc_id = h.id
        and exists(
            select *
            from qdistr q
            where
                q.ware_id = d.ware_id
                and q.snd_optype_id = 1000 -- fn_oper_order_by_customer()
                and q.rcv_optype_id = 3300 -- fn_oper_retail_reserve()
                and q.snd_id = d.id
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            order by q.ware_id, q.snd_optype_id, q.rcv_optype_id
        )
        order by d.doc_id -- prevent from building bitmap, 3.0 only
    )
    order by h.id
    rows 1
;

-------------------------------------------------------------------------------


create or alter view v_max_id_clo_res as
-- DDL since 11.01.2019
--PLAN (Q ORDER XQD_1000_3300_WA_SO_RO_WKR_SND)
--PLAN (D ORDER FK_DOC_DATA_DOC_LIST)
--PLAN (H ORDER DOC_LIST_ID_DESC INDEX (DOC_LIST_WORKER_OPTYPE))
-- ################################################################################
-- ### NB DDL of this view will be replaced with code WITHOUT doc_data querying ###
-- ### if config param 'split_heavy_tabs' = 1, see: oltp_split_heavy_tabs_1.sql ###
-- ################################################################################
select h.id
from doc_list h
-- >>> this inner join had extremely POOR performance! >>> join doc_data d on h.id = d.doc_id
where h.optype_id = 1000
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from fn_this_worker_seq_no()
    and exists(
        select *
        from doc_data d where d.doc_id = h.id
        and exists(
            select *
            from qdistr q
            where
                q.ware_id = d.ware_id
                and q.snd_optype_id = 1000 -- fn_oper_order_by_customer()
                and q.rcv_optype_id = 3300 -- fn_oper_retail_reserve()
                and q.snd_id = d.id
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from fn_this_worker_seq_no()
            order by q.ware_id, q.snd_optype_id, q.rcv_optype_id
        )
        order by d.doc_id -- prevent from building bitmap, 3.0 only
    )
    order by h.id desc
    rows 1
;

-------------------------------------------------------------------------------

create or alter view v_random_find_non_paid_invoice as
-- 09.09.2014. Used in dynamic SQL in sp_get_random_id, see SP_PAYMENT_COMMON
-- Source for random choose document of accepted invoice (optype=2100)
-- which still has some cost to be paid (==> has records in PDistr)
-- Introduced instead of v_p`distr_non_paid_realization to avoid scans doc_list
select p.snd_id as id -- this value match doc_list.id
from pdistr p
where
    p.snd_optype_id = 2100 -- fn_oper_invoice_add()
    and p.rcv_optype_id = 4000 -- fn_oper_pay_to_supplier()
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and p.worker_id is not distinct from fn_this_worker_seq_no()
;

-------------------------------------------------------------------------------

create or alter view v_min_non_paid_invoice as
-- 09.09.2014: source for fast get min snd_id (==> doc_list.id) before making
-- random choise of accepted invoice (optype=2100) which still has some
-- cost to be paid (==> has records in PDistr)
-- PLAN (P ORDER PDISTR_SNDOP_RCVOP_SNDID_ASC)
select p.snd_id as id -- this value match doc_list.id
from pdistr p
where
    p.snd_optype_id = 2100 -- fn_oper_invoice_add()
    and p.rcv_optype_id = 4000 -- fn_oper_pay_to_supplier()
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and p.worker_id is not distinct from fn_this_worker_seq_no()
order by
    snd_id
rows 1
;

-------------------------------------------------------------------------------

create or alter view v_max_non_paid_invoice as
-- 09.09.2014: source for fast get MAX snd_id (==> doc_list.id) before making
-- random choise of accepted invoice (optype=2100) which still has some
-- cost to be paid (==> has records in PDistr)
-- PLAN (P ORDER PDISTR_SNDOP_RCVOP_SNDID_DESC)
select p.snd_id as id -- this value match doc_list.id
from pdistr p
where
    p.snd_optype_id = 2100 -- fn_oper_invoice_add()
    and p.rcv_optype_id = 4000 -- fn_oper_pay_to_supplier()
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and p.worker_id is not distinct from fn_this_worker_seq_no()
order by
    p.snd_optype_id desc, p.rcv_optype_id desc, p.snd_id desc
rows 1
;

-------------------------------------------------------------------------------

create or alter view v_random_find_non_paid_realizn as
-- 09.09.2014. Used in dynamic SQL in sp_get_random_id, see SP_PAYMENT_COMMON
-- Source for random choose document of written-off realization (optype=3400)
-- which still has some cost to be paid (==> has records in PDistr)
-- Introduced instead of v_p`distr_non_paid_realization to avoid scans doc_list
select p.snd_id as id -- this value match doc_list.id
from pdistr p
where
    p.snd_optype_id = 3400 -- fn_oper_retail_realization()
    and p.rcv_optype_id = 5000 -- fn_oper_pay_from_customer()
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and p.worker_id is not distinct from fn_this_worker_seq_no()
;

-------------------------------------------------------------------------------

create or alter view v_min_non_paid_realizn as
-- 09.09.2014: source for fast get min snd_id (==> doc_list.id) before making
-- random choise of written-off realization (optype=3400) which still has some
-- cost to be paid (==> has records in PDistr)
-- PLAN (P ORDER PDISTR_SNDOP_RCVOP_SNDID_ASC)
select p.snd_id as id -- this value match doc_list.id
from pdistr p
where
    p.snd_optype_id = 3400 -- fn_oper_retail_realization()
    and p.rcv_optype_id = 5000 -- fn_oper_pay_from_customer()
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and p.worker_id is not distinct from fn_this_worker_seq_no()
order by
    snd_id
rows 1
;

-------------------------------------------------------------------------------

create or alter view v_max_non_paid_realizn as
-- 09.09.2014: source for fast get MAX snd_id (==> doc_list.id) before making
-- random choise of written-off realization (optype=3400) which still has some
-- cost to be paid (==> has records in PDistr)
-- PLAN (P ORDER PDISTR_SNDOP_RCVOP_SNDID_DESC)
select p.snd_id as id -- this value match doc_list.id
from pdistr p
where
    p.snd_optype_id = 3400 -- fn_oper_retail_realization()
    and p.rcv_optype_id = 5000 -- fn_oper_pay_from_customer()
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and p.worker_id is not distinct from fn_this_worker_seq_no()
order by
    p.snd_optype_id desc, p.rcv_optype_id desc, p.snd_id desc
rows 1
;

-------------------------------------------------------------------------------

create or alter view v_saldo_invnt as
-- 21.04.2014
-- ::: NB ::: this view can return NEGATIVE remainders in qty_xxx
-- if parallel attaches call of sp_make_invnt_saldo
-- (because of deleting rows in invnt_turnover_log in this SP)
-- !!! look at table INVNT_SALDO for actual remainders !!!
select
    ng.ware_id
    ,sum(o.m_qty_clo * ng.qty_diff) qty_clo
    ,sum(o.m_qty_clr * ng.qty_diff) qty_clr
    ,sum(o.m_qty_ord * ng.qty_diff) qty_ord
    ,sum(o.m_qty_sup * ng.qty_diff) qty_sup
    ,sum(o.m_qty_avl * ng.qty_diff) qty_avl
    ,sum(o.m_qty_res * ng.qty_diff) qty_res
    ,sum(o.m_cost_inc * ng.qty_diff) qty_inc
    ,sum(o.m_cost_out * ng.qty_diff) qty_out
    ,sum(o.m_cost_inc * ng.cost_diff) cost_inc
    ,sum(o.m_cost_out * ng.cost_diff) cost_out
    -- amount "on hand" as it seen by accounter:
    ,sum(o.m_qty_avl * ng.qty_diff) + sum(o.m_qty_res * ng.qty_diff) qty_acn
    -- total cost "on hand" in purchasing prices:
    ,sum(o.m_cost_inc * ng.cost_diff) - sum(o.m_cost_out * ng.cost_diff) cost_acn
from invnt_turnover_log ng
join optypes o on ng.optype_id + 0 = o.id + 0 -- ==> for 3.0 only: hash join, reduce number of`optypes` scans!
group by 1
;

commit;

---------------------------

create or alter view v_doc_detailed as
-- Used in all app unit for returning final resultset to client.
-- Also very useful for debugging
select
    h.id doc_id,
    h.worker_id,
    h.optype_id,
    o.mcode as oper,
    h.base_doc_id,
    d.id doc_data_id,
    d.ware_id,
    d.qty,
    coalesce(d.cost_purchase, h.cost_purchase) cost_purchase, -- cost in purchase price
    coalesce(d.cost_retail, h.cost_retail) cost_retail, -- cost in retail price
    n.qty_clo, -- amount of ORDERED by customer (which we not yet sent to supplier)
    n.qty_clr, -- amount of REFUSED by customer
    n.qty_ord, -- amount that we have already sent to supplier
    n.qty_sup, -- amount in invoices of supplier, in <open> state
    n.qty_inc, -- amount of incomings (when invoices were added)
    n.qty_avl, -- amount avaliable to be sold (usially - due to refused client orders)
    n.qty_res, -- amount in reserve to be sold to customer
    n.qty_out, -- amount of written-off
    n.cost_inc, -- total cost of incomes, in purchase prices
    n.cost_out, -- total cost of outgoings, in purchase prices
    n.qty_acn,
    n.cost_acn,
    h.state_id,
    h.agent_id,
    d.dts_edit,
    h.dts_open,
    h.dts_fix,
    h.dts_clos,
    s.mcode state
from doc_list h
    join optypes o on h.optype_id = o.id
    join doc_states s on h.state_id=s.id
    left join doc_data d on h.id = d.doc_id
    -- ::: NB ::: do NOT remove "left" from here otherwise performance will degrade
    -- (FB will not push predicate inside view; 22.04.2014)
    LEFT join v_saldo_invnt n on d.ware_id=n.ware_id
--left join sp_saldo_invnt(d.ware_id) n on 1=1 -- speed
;

-------------------------------------------------------------------------------
-- ###   v i e w s    f o r    m o n i t o r   g a t h e r e d   d a t a   ####
-------------------------------------------------------------------------------

create or alter view v_srv_fill_mon as
select     
    -- 27.11.2020 Used in SP srv_fill_mon
    ----------------------- ALL attachments: set #1
    datediff(second from coalesce( cast(p.test_time_dts_beg as date), cast( 'YESTERDAY' as date) ) to cast('now' as timestamp)) sec
    -- mon$attachments(1):
    ,a.mon$user mon_user
    ,a.mon$attachment_id attach_id
    ----------------------- ALL attachments: set #2
    -- mon$io_stats:
    ,i.mon$page_reads reads
    ,i.mon$page_writes writes     
    ,i.mon$page_fetches fetches     
    ,i.mon$page_marks marks     
    ----------------------- ALL attachments: set #3
    -- mon$record_stats:     
    ,r.mon$record_inserts ins_cnt
    ,r.mon$record_updates upd_cnt     
    ,r.mon$record_deletes del_cnt     
    ,r.mon$record_backouts bk_outs     
    ,r.mon$record_purges purges     
    ,r.mon$record_expunges expunges     
    ,r.mon$record_seq_reads seq_reads     
    ,r.mon$record_idx_reads idx_reads     
    ----------------------- ALL attachments: set #4
    -- since rev. 60012, 28.08.2014 19:16
    ,r.mon$record_rpt_reads rec_rpt_reads
    ,r.mon$backversion_reads bkv_reads
    ,r.mon$fragment_reads frg_reads
    ----------------------- ALL attachments: set #5
    ,r.mon$record_locks rec_locks
    ,r.mon$record_waits rec_waits
    ,r.mon$record_conflicts rec_confl
    ----------------------- ALL attachments: set #6
    -- mon$memory_usage:
    ,u.mon$memory_used used_memory     
    ,u.mon$memory_allocated alloc_by_OS     
    ----------------------- ALL attachments: set #7
    -- mon$attachments(2):
    ,a.mon$stat_id       stat_id
    ,a.mon$server_pid    server_PID     
    ,a.mon$remote_pid    remote_PID     
    ----------------------- ALL attachments: set #8
    ,a.mon$remote_address remote_IP     
    -- aux info:     
    ,right(a.mon$remote_process,30) remote_process     
--                    ,:v_curr_trn
--                    ,:v_this
--                    ,'all_attaches'
from mon$attachments a     
left join sp_get_test_time_dts p on 1=1
left join mon$memory_usage u on a.mon$stat_id=u.mon$stat_id
left join mon$io_stats i on a.mon$stat_id=i.mon$stat_id     
left join mon$record_stats r on a.mon$stat_id=r.mon$stat_id  
;

------------------------------------------------------------------------------

-- Following views are used in 'oltp_isql_run_worker.bat' during its first
-- launched ISQL session makes final report. These views will contain data
-- only when config parameter mon_unit_perf=1.
create or alter view z_mon_stat_per_units as
-- 29.08.2014: data from measuring statistics per each unit
-- (need FB rev. >= 60013: new mon$ counters were introduced, 28.08.2014)
-- 25.01.2015: added rec_locks, rec_confl.
-- 06.02.2015: reorder columns, made all `max` values most-right
select
     m.unit
    ,count(*) iter_counts
    -------------- speed -------------
    ,avg(m.elapsed_ms) avg_elap_ms
    ,avg(1000.00 * ( (m.rec_seq_reads + m.rec_idx_reads + m.bkv_reads ) / nullif(m.elapsed_ms,0))  ) avg_rec_reads_sec
    ,avg(1000.00 * ( (m.rec_inserts + m.rec_updates + m.rec_deletes ) / nullif(m.elapsed_ms,0))  ) avg_rec_dmls_sec
    ,avg(1000.00 * ( m.rec_backouts / nullif(m.elapsed_ms,0))  ) avg_bkos_sec
    ,avg(1000.00 * ( m.rec_purges / nullif(m.elapsed_ms,0))  ) avg_purg_sec
    ,avg(1000.00 * ( m.rec_expunges / nullif(m.elapsed_ms,0))  ) avg_xpng_sec
    ,avg(1000.00 * ( m.pg_fetches / nullif(m.elapsed_ms,0)) ) avg_fetches_sec
    ,avg(1000.00 * ( m.pg_marks / nullif(m.elapsed_ms,0)) ) avg_marks_sec
    ,avg(1000.00 * ( m.pg_reads / nullif(m.elapsed_ms,0)) ) avg_reads_sec
    ,avg(1000.00 * ( m.pg_writes / nullif(m.elapsed_ms,0)) ) avg_writes_sec
    -------------- reads ---------------
    ,avg(m.rec_seq_reads) avg_seq
    ,avg(m.rec_idx_reads) avg_idx
    ,avg(m.rec_rpt_reads) avg_rpt
    ,avg(m.bkv_reads) avg_bkv
    ,avg(m.frg_reads) avg_frg
    ,avg(m.bkv_per_seq_idx_rpt) avg_bkv_per_rec
    ,avg(m.frg_per_seq_idx_rpt) avg_frg_per_rec
    ---------- modifications ----------
    ,avg(m.rec_inserts) avg_ins
    ,avg(m.rec_updates) avg_upd
    ,avg(m.rec_deletes) avg_del
    ,avg(m.rec_backouts) avg_bko
    ,avg(m.rec_purges) avg_pur
    ,avg(m.rec_expunges) avg_exp
    --------------- io -----------------
    ,avg(m.pg_fetches) avg_fetches
    ,avg(m.pg_marks) avg_marks
    ,avg(m.pg_reads) avg_reads
    ,avg(m.pg_writes) avg_writes
    ----------- locks and conflicts ----------
    ,avg(m.rec_locks) avg_locks
    ,avg(m.rec_confl) avg_confl
    ,datediff( minute from min(m.dts) to max(m.dts) ) workload_minutes
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
from mon_log m
group by unit
;

--------------------------------------------------------------------------------

create or alter view z_mon_stat_per_tables
as
-- 29.08.2014: data from measuring statistics per each unit+table
-- (new table MON$TABLE_STATS required, see srv_fill_mon, srv_fill_tmp_mon)
-- 25.01.2015: added rec_locks, rec_confl;
-- ::: do NOT add `bkv_per_seq_idx_rpt` and `frg_per_seq_idx_rpt` into WHERE
-- clause with check sum > 0, because they can be NULL, see DDL!
-- 06.02.2015: reorder columns, made all `max` values most-right
select
     t.table_name
    ,t.unit
    ,count(*) iter_counts
    --------------- reads ---------------
    ,avg(t.rec_seq_reads) avg_seq
    ,avg(t.rec_idx_reads) avg_idx
    ,avg(t.rec_rpt_reads) avg_rpt
    ,avg(t.bkv_reads) avg_bkv
    ,avg(t.frg_reads) avg_frg
    ,avg(t.bkv_per_seq_idx_rpt) avg_bkv_per_rec
    ,avg(t.frg_per_seq_idx_rpt) avg_frg_per_rec
    ---------- modifications ----------
    ,avg(t.rec_inserts) avg_ins
    ,avg(t.rec_updates) avg_upd
    ,avg(t.rec_deletes) avg_del
    ,avg(t.rec_backouts) avg_bko
    ,avg(t.rec_purges) avg_pur
    ,avg(t.rec_expunges) avg_exp
    ----------- locks and conflicts ----------
    ,avg(t.rec_locks) avg_locks
    ,avg(t.rec_confl) avg_confl
    ,datediff( minute from min(t.dts) to max(t.dts) ) elapsed_minutes
    --- 06.02.2015 moved here all MAX values, separate them from AVG ones: ---
    ,max(t.rec_seq_reads) max_seq
    ,max(t.rec_idx_reads) max_idx
    ,max(t.rec_rpt_reads) max_rpt
    ,max(t.bkv_reads) max_bkv
    ,max(t.frg_reads) max_frg
    ,max(t.bkv_per_seq_idx_rpt) max_bkv_per_rec
    ,max(t.frg_per_seq_idx_rpt) max_frg_per_rec
    ,max(t.rec_inserts) max_ins
    ,max(t.rec_updates) max_upd
    ,max(t.rec_deletes) max_del
    ,max(t.rec_backouts) max_bko
    ,max(t.rec_purges) max_pur
    ,max(t.rec_expunges) max_exp
    ,max(t.rec_locks) max_locks
    ,max(t.rec_confl) max_confl
from mon_log_table_stats t
where
      t.rec_seq_reads
    + t.rec_idx_reads
    + t.rec_rpt_reads
    + t.bkv_reads
    + t.frg_reads
    + t.rec_inserts
    + t.rec_updates
    + t.rec_deletes
    + t.rec_backouts
    + t.rec_purges
    + t.rec_expunges
    + t.rec_locks
    + t.rec_confl
    > 0
group by t.table_name,t.unit
;


-------------------------------------------------------------------------------
--######################   d e b u g    v i e w s   ############################
-------------------------------------------------------------------------------

-- Following view were moved in 'oltp_common_sp.sql', 23.11.2018:
-- create or alter view z_current_test_settings
-- create or alter view z_settings_pivot
-- create or alter view z_qd_indices_ddl
-- create or alter view z_halt_log

create or alter view z_agents_tunrover_saldo as
-- 4 misc reports and debug, do not delete: agent turnovers and sums; only in 3.0
select
    m.agent_id, m.doc_id, o.mcode, o.acn_type
    ,o.m_supp_debt * m.cost_purchase vol_supp
    ,o.m_cust_debt * m.cost_retail vol_cust
    ,sum(o.m_supp_debt * m.cost_purchase)over(partition by m.agent_id) sum_supp
    ,sum(o.m_cust_debt * m.cost_retail  )over(partition by m.agent_id) sum_cust
from money_turnover_log m
join optypes o on m.optype_id = o.id
;
commit;

--------------------------------------------------------------------------------
-- ########################   T R I G G E R S   ################################
--------------------------------------------------------------------------------

set term ^;
-- not needed in 3.0, see DDL of their `ID` field ('generated as identity'):
--create or alter trigger wares_bi for wares active
--before insert position 0
--as
--begin
--   new.id = coalesce(new.id, gen_id(g_common, 1) );
--end
--^
--
--create or alter trigger phrases_bi for phrases active
--before insert position 0
--as
--begin
--   new.id = coalesce(new.id, gen_id(g_common, 1) );
--end
--^
--
--create or alter trigger agents_bi for agents active
--before insert position 0
--as
--begin
--   new.id = coalesce(new.id, gen_id(g_common, 1) );
--end
--^
--
--create or alter trigger invnt_saldo_bi for invnt_saldo active
--before insert position 0
--as
--begin
--   new.id = coalesce(new.id, gen_id(g_common, 1) );
--end
--^

create or alter trigger money_turnover_log_bi for money_turnover_log active before insert position 0 as
begin
    new.id = coalesce(new.id, gen_id(g_common, 1) ); -- new.id is NOT null for all docs except payments
end

^ -- money_turnover_log_bi

create or alter trigger perf_log_bi for perf_log active before insert position 0 as
begin
    new.id = coalesce(new.id, gen_id(g_perf_log, 1) );
end

^ -- perf_log_bi
-- not needed in 3.0, see DDL of their `ID` field ('generated as identity'):
--create or alter trigger pdistr_bi for pdistr
--active before insert position 0 as
--begin
--    new.id = coalesce(new.id, gen_id(g_common,1));
--end
--
--^ -- pdistr_bi
--
--create or alter trigger pstorned_bi for pstorned
--active before insert position 0 as
--begin
--    new.id = coalesce(new.id, gen_id(g_common,1));
--end
--
--^ -- pstorned_bi

set term ;^
commit;
set term ^;

--------------------------------------------------------------------------------

create or alter trigger doc_list_biud for doc_list
active before insert or update or delete position 0
as
    declare v_msg dm_info = '';
    declare v_info dm_info = '';
    declare v_this dm_dbobj = 'doc_list_biud';
    declare v_affects_on_inventory_balance smallint;
    declare v_old_op type of dm_idb;
    declare v_new_op type of dm_idb;
    declare v_lf char(1) = x'0A';
    declare v_sttm varchar(8192);
begin

    if ( inserting ) then
        new.id = coalesce(new.id, gen_id(g_common,1));

    v_info = 'dh='|| iif(not inserting, old.id, new.id)
             || ', op='||iif(inserting,'INS',iif(updating,'UPD','DEL'))
             || iif(not inserting, ' old='||old.optype_id, '')
             || iif(not deleting,  ' new='||new.optype_id, '');

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log( 1, v_this, null, v_info );

    if (inserting) then
    begin
        new.state_id = coalesce(new.state_id, fn_doc_open_state());
        -- 'i'=incoming; 'o' = outgoing; 's' = payment to supplier; 'c' = payment from customer
        new.acn_type = (select o.acn_type from optypes o where o.id = new.optype_id);
        v_msg = v_msg || ' new.id='||new.id||', acn_type='||coalesce(new.acn_type,'<?>');
    end

    if ( not deleting ) then
        begin
            if ( new.state_id <> fn_doc_open_state() ) then
            begin
                new.dts_fix = coalesce(new.dts_fix, 'now');
                new.dts_clos = iif( new.state_id in( fn_doc_clos_state(), fn_doc_canc_state() ), 'now', null);
            end
            if ( new.state_id = fn_doc_open_state() ) then -- 31.03.2014
            begin
                new.dts_fix = null;
                new.dts_clos = null;
            end
        end
    else
        v_msg = v_msg || ' doc='||old.id||', op='||old.optype_id;

    -- add to invnt_turnover_log
    -- rows that are 'totalled' in doc_data when make doc content in sp_create_doc_using_fifo
    -- (there are multiple rows from qdistr and multiple calls to sp_add_doc_data for each one)
    v_old_op=iif(inserting, null, old.optype_id);
    v_new_op=iif(deleting,  null, new.optype_id);

    /* #ACTIVATE#IF#USE_ES_EQU_1#BEG#
    v_sttm =
        'select --#EDS#TAG#' || v_lf
        || ' max(maxvalue(abs(o.m_qty_clo), abs(o.m_qty_clr), abs(o.m_qty_ord), abs(o.m_qty_sup), abs(o.m_qty_avl), abs(o.m_qty_res))) ' || v_lf
        || ' from optypes o ' || v_lf
        || ' where o.id in( ?, ? )'
    ;
    execute statement ( v_sttm ) ( :v_old_op, :v_new_op )
    into v_affects_on_inventory_balance;
    -- #ACTIVATE#IF#USE_ES_EQU_1#END# */

    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    v_sttm =
    q'{ execute block( a_old_op bigint = ?, a_new_op bigint = ? ) returns( affect_on_inventory_balance smallint ) as
        begin
            -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
            -- NOTE: we have to log timestamp of point just BEFORE query that
            -- will work: datediff between this point and next firing of
            -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
            -- of IDLE state for this connect in the Ext. Conn. Pool.
            execute procedure sp_perf_eds_logging('B');
    }' || v_lf
    || '    select --#EDS#TAG#' || v_lf
    || '        max(maxvalue(abs(o.m_qty_clo), abs(o.m_qty_clr), abs(o.m_qty_ord), abs(o.m_qty_sup), abs(o.m_qty_avl), abs(o.m_qty_res))) ' || v_lf
    || '    from optypes o ' || v_lf
    || '    where o.id in( :a_old_op, :a_new_op )' || v_lf
    || '    into affect_on_inventory_balance;' || v_lf
    || q'{
            -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
            -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
            -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
            -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
            -- for connect, so there we have TWO events: 'I' and 'A').
            --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#
        }' || v_lf
    || '    suspend;' || v_lf
    || 'end'
    ;
    execute statement ( v_sttm ) ( :v_old_op, :v_new_op )
    -- If config parameter USE_ES is 2 then following line will be
    -- replaced with uncommented code for run as ES/EDS.
    -- Host and port will be taken from apropriate config parameters.
    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
    -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
    into v_affects_on_inventory_balance;
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

    -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
    -- usual way (use_es = 0): use static PSQL code.
    select max(maxvalue(abs(o.m_qty_clo), abs(o.m_qty_clr), abs(o.m_qty_ord), abs(o.m_qty_sup), abs(o.m_qty_avl), abs(o.m_qty_res)))
    from optypes o
    where o.id in( :v_old_op, :v_new_op )
    into v_affects_on_inventory_balance;
    -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

    -- 20.09.2014 1825: remove calls of s`p_add_invnt_log to SPs (reduce scans of doc_data)
    if ( v_affects_on_inventory_balance > 0 and (deleting or updating and new.optype_id is distinct from old.optype_id) )
    then
        execute procedure sp_kill_qty_storno(
            old.id,
            old.optype_id,
            iif( deleting, null, new.optype_id),
            iif( updating, 1, 0),
            iif( deleting, 1, 0)
        );

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this,null,v_msg);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            'error in '||v_this,
            gdscode,
            v_msg,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- doc_list_biud

-------------------------------------------------------------------------------

create or alter trigger doc_list_aiud for doc_list
active after insert or update or delete position 0
as
    declare v_affects_on_monetary_balance smallint;
    declare v_affects_on_inventory_balance smallint;
    declare v_doc_id dm_idb;
    declare v_old_op type of dm_idb;
    declare v_new_op type of dm_idb;
    declare v_old_mult type of dm_sign = null;
    declare v_new_mult type of dm_sign = null;
    declare v_affects_on_customer_saldo smallint;
    declare v_affects_on_supplier_saldo smallint;
    declare v_oper_changing_cust_saldo type of dm_idb;
    declare v_oper_changing_supp_saldo type of dm_idb;
    declare v_cost_diff type of dm_cost;
    declare v_msg type of dm_info = '';
    declare v_this dm_dbobj = 'doc_list_aiud';
    declare v_catch_bitset bigint;
    declare v_lf char(1) = x'0A';
    declare v_sttm varchar(8192);
begin

    -- AFTER trigger on master table (THIS) will fired BEFORE any triggers on detail (doc_data)!
    -- www.sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1081231&msg=15685218
    v_affects_on_monetary_balance = 1;
    v_affects_on_inventory_balance = 1;
    v_doc_id=iif(deleting, old.id, new.id);
    v_old_op=iif(inserting, null, old.optype_id);
    v_new_op=iif(deleting,  null, new.optype_id);

    v_msg = 'dh='|| iif(not inserting, old.id, new.id)
             || ', op='||iif(inserting,'INS',iif(updating,'UPD','DEL'))
             || iif(not inserting, ' old='||old.optype_id, '')
             || iif(not deleting,  ' new='||new.optype_id, '');

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log( 1, v_this , null, v_msg );

    -- See oltpNN_config, parameter 'use_es'. Can be 0, 1 or 2:

    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    v_sttm =
    q'{ execute block( v_old_op bigint = ?, v_new_op bigint = ?)
        returns(
            v_old_mult bigint,
            v_new_mult bigint,
            v_oper_changing_cust_saldo bigint,
            v_oper_changing_supp_saldo bigint,
            v_affects_on_customer_saldo smallint,
            v_affects_on_supplier_saldo smallint,
            v_affects_on_inventory_balance smallint
        ) as
    begin
        -- Log precise timestamp when EDS attachment becomes ACTIVE and starts perform its job:
        -- NOTE: we have to log timestamp of point just BEFORE query that
        -- will work: datediff between this point and next firing of
        -- db-level CONNECT trigger which gets RESETTING = tru is actual duration
        -- of IDLE state for this connect in the Ext. Conn. Pool.
        execute procedure sp_perf_eds_logging('B');

        select
            iif(m_cust_4old<>0, m_cust_4old, m_supp_4old),
            iif(m_cust_4new<>0, m_cust_4new, m_supp_4new),
            iif(m_cust_4old<>0, v_old_op, iif(m_cust_4new<>0, v_new_op, 0)),
            iif(m_supp_4old<>0, v_old_op, iif(m_supp_4new<>0, v_new_op, 0)),
            iif(m_cust_4old<>0 or m_cust_4new<>0, 1, 0),
            iif(m_supp_4old<>0 or m_supp_4new<>0, 1, 0),
            q_mult_abs_max
        from(
            select
                max(iif(o.id = :v_old_op, o.m_cust_debt, null)) m_cust_4old,
                max(iif(o.id = :v_old_op, o.m_supp_debt, null)) m_supp_4old,
                max(iif(o.id = :v_new_op, o.m_cust_debt, null)) m_cust_4new,
                max(iif(o.id = :v_new_op, o.m_supp_debt, null)) m_supp_4new,
                max(iif(o.id = :v_old_op, :v_old_op, null)) v_old_op,
                max(iif(o.id = :v_new_op, :v_new_op, null)) v_new_op,
                max(maxvalue(abs(o.m_qty_clo), abs(o.m_qty_clr), abs(o.m_qty_ord), abs(o.m_qty_sup), abs(o.m_qty_avl), abs(o.m_qty_res))) q_mult_abs_max
            from optypes o
            where o.id in( :v_old_op, :v_new_op )
        )
        into
            v_old_mult,
            v_new_mult,
            v_oper_changing_cust_saldo,
            v_oper_changing_supp_saldo,
            v_affects_on_customer_saldo,
            v_affects_on_supplier_saldo,
            v_affects_on_inventory_balance;

        -- Log precise timestamp when EDS attachment is to be finished and thus will be INACTIVE.
        -- Because This FB instance does not support ALTER SESSION RESET, we add record manually.
        -- Instead of logging both 'I' and 'A', it is enough to write only 'A' for 'connect' event
        -- (note: for FB 4.x session reset invokes BOTH triggers for disconnect and then immediately
        -- for connect, so there we have TWO events: 'I' and 'A').
        --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging('A'); --#SUBST#RESETTING_0#END#

        suspend;
    end
    }';
    execute statement (v_sttm) (v_old_op, v_new_op)
    -- 20.11.2020
    -- If config parameter USE_ES is 2 then following line will be
    -- replaced with uncommented code for run as ES/EDS.
    -- Host and port will be taken from apropriate config parameters.
    -- #SUBST#EXTPOOL#SUPPORT_1#BEG# WITH AUTONOMOUS TRANSACTION -- #SUBST#EXTPOOL#SUPPORT_1#END#
    -- #SUBS#CONNSTR#BEG# on external '#host/#port:' || rdb$get_context('SYSTEM', 'DB_NAME') as user current_user password #pwd role current_role -- #SUBS#CONNSTR#END#
    into
        v_old_mult,
        v_new_mult,
        v_oper_changing_cust_saldo,
        v_oper_changing_supp_saldo,
        v_affects_on_customer_saldo,
        v_affects_on_supplier_saldo,
        v_affects_on_inventory_balance;
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */

    /* #ACTIVATE#IF#USE_ES_EQU_1#BEG#
    -- 22.11.2020. NB: cast(null as int) - otherwise 'conversion error from string " "'
    execute statement (
        'select --#EDS#TAG#' || v_lf
        || '    iif(m_cust_4old<>0, m_cust_4old, m_supp_4old), ' -- they are mutually excluded: only ONE can be <> 0
        || '    iif(m_cust_4new<>0, m_cust_4new, m_supp_4new), ' -- they are mutually excluded: only ONE can be <> 0
        || '    iif(m_cust_4old<>0, v_old_op, iif(m_cust_4new<>0, v_new_op, 0)) v_oper_changing_cust_saldo, '
        || '    iif(m_supp_4old<>0, v_old_op, iif(m_supp_4new<>0, v_new_op, 0)) v_oper_changing_supp_saldo, '
        || '    iif(m_cust_4old<>0 or m_cust_4new<>0, 1, 0) v_affects_on_customer_saldo, '
        || '    iif(m_supp_4old<>0 or m_supp_4new<>0, 1, 0) v_affects_on_supplier_saldo, '
        || '    q_mult_abs_max '
        || ' from( '
        || '    select '
        || '        max(iif(o.id = ?, o.m_cust_debt, cast(null as int))) m_cust_4old, ' -- par #1: :v_old_op
        || '        max(iif(o.id = ?, o.m_supp_debt, cast(null as int))) m_supp_4old, ' -- par #2: :v_old_op
        || '        max(iif(o.id = ?, o.m_cust_debt, cast(null as int))) m_cust_4new, ' -- par #3: :v_new_op
        || '        max(iif(o.id = ?, o.m_supp_debt, cast(null as int))) m_supp_4new, ' -- par #4: :v_new_op
        || '        max(iif(o.id = ?, ?, cast(null as int))) v_old_op, '        -- par #5: v_old_op;   par#6: :v_old_op
        || '        max(iif(o.id = ?, ?, cast(null as int))) v_new_op, '        -- par #7: v_new_op;   par#8: :v_new_op
        || '        max( maxvalue(abs(o.m_qty_clo), abs(o.m_qty_clr), abs(o.m_qty_ord), abs(o.m_qty_sup), abs(o.m_qty_avl), abs(o.m_qty_res))) q_mult_abs_max '
        || '    from optypes o '
        || '    where o.id in( ?, ? ) ' -- par 9: v_old_op;  par10:  v_new_op
        || ')'
    ) --  (   v_old_op := :v_old_op, v_new_op := :v_new_op    )
    (
        v_old_op    --  1
        ,v_old_op   --  2
        ,v_new_op   --  3
        ,v_new_op   --  4
        ,v_old_op   --  5
        ,v_old_op   --  6
        ,v_new_op   --  7
        ,v_new_op   --  8
        ,v_old_op   --  9
        ,v_new_op   -- 10
    )
    into
        v_old_mult,
        v_new_mult,
        v_oper_changing_cust_saldo,
        v_oper_changing_supp_saldo,
        v_affects_on_customer_saldo,
        v_affects_on_supplier_saldo,
        v_affects_on_inventory_balance;
    -- #ACTIVATE#IF#USE_ES_EQU_1#END# */

    -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
    -- usual way (use_es = 0): use static PSQL code.
    select
        iif(m_cust_4old<>0, m_cust_4old, m_supp_4old), -- they are mutually excluded: only ONE can be <> 0
        iif(m_cust_4new<>0, m_cust_4new, m_supp_4new), -- they are mutually excluded: only ONE can be <> 0
        iif(m_cust_4old<>0, v_old_op, iif(m_cust_4new<>0, v_new_op, 0)) v_oper_changing_cust_saldo,
        iif(m_supp_4old<>0, v_old_op, iif(m_supp_4new<>0, v_new_op, 0)) v_oper_changing_supp_saldo,
        iif(m_cust_4old<>0 or m_cust_4new<>0, 1, 0) v_affects_on_customer_saldo,
        iif(m_supp_4old<>0 or m_supp_4new<>0, 1, 0) v_affects_on_supplier_saldo,
        q_mult_abs_max
    from(
        select
            max(iif(o.id=:v_old_op, o.m_cust_debt, null)) m_cust_4old,
            max(iif(o.id=:v_old_op, o.m_supp_debt, null)) m_supp_4old,
            max(iif(o.id=:v_new_op, o.m_cust_debt, null)) m_cust_4new,
            max(iif(o.id=:v_new_op, o.m_supp_debt, null)) m_supp_4new,
            max(iif(o.id=:v_old_op, :v_old_op, null)) v_old_op,
            max(iif(o.id=:v_new_op, :v_new_op, null)) v_new_op,
            max(maxvalue(abs(o.m_qty_clo), abs(o.m_qty_clr), abs(o.m_qty_ord), abs(o.m_qty_sup), abs(o.m_qty_avl), abs(o.m_qty_res))) q_mult_abs_max
        from optypes o
        where o.id in( :v_old_op, :v_new_op )
    )
    into
        v_old_mult,
        v_new_mult,
        v_oper_changing_cust_saldo,
        v_oper_changing_supp_saldo,
        v_affects_on_customer_saldo,
        v_affects_on_supplier_saldo,
        v_affects_on_inventory_balance;
    -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

    ----------------------------------------------------------------------------
    if ( v_affects_on_inventory_balance > 0
         and
         (
             inserting and new.cost_purchase > 0
             or
             updating
             and ( new.cost_purchase is distinct from old.cost_purchase
                   or
                   new.optype_id is distinct from old.optype_id
                )
             or deleting
         )
       ) then
    begin
        v_catch_bitset = cast(rdb$get_context('USER_SESSION','QMISM_VERIFY_BITSET') as bigint);
        if (v_catch_bitset is null) then
            exception ex_context_var_not_found
            --'required context variable(s): @1 - not found or has invalid value'
            using('QMISM_VERIFY_BITSET')
            ;

        if ( bin_and( v_catch_bitset, 1 ) <> 0 ) then
        begin
            -- check that number of rows in qdistr+qstorned exactly equals
            -- add to perf_log row with exc. info about mismatch, gds=335544558
            execute procedure srv_find_qd_qs_mism( iif(deleting, old.id, new.id), iif(deleting, :v_old_op, :v_new_op), iif(deleting, 1, 0) );
        end

        if ( bin_and( v_catch_bitset, 2 ) <> 0 ) then
        begin
            --execute procedure srv_catch_neg_remainders( new.ware_id, new.optype_id, new.doc_list_id, new.doc_data_id, new.qty_diff );
            execute procedure srv_check_neg_remainders(  iif(deleting, old.id, new.id), iif(deleting, :v_old_op, :v_new_op) );
        end
    end
    ---------------

    if ( coalesce(v_old_mult,0)=0 and coalesce(v_new_mult,0)=0
     ) then -- this op does NOT affect on MONETARY turnovers (of customer or supplier)
        --####
        v_affects_on_monetary_balance = 0;
        --####
    
    if ( v_affects_on_monetary_balance <> 0 ) then
    begin
        if (
           new.cost_purchase is distinct from old.cost_purchase
           or
           new.cost_retail is distinct from old.cost_retail
         )
        then -- creating new doc or deleting it
            begin
                ----------
                if ( v_oper_changing_cust_saldo <> 0 or v_oper_changing_supp_saldo <> 0 ) then
                begin
                    if (  inserting or updating ) then
                        begin
                
                            if ( v_oper_changing_cust_saldo <> 0 ) then
                                v_cost_diff = new.cost_retail - iif(inserting, 0, old.cost_retail);
                            else
                                v_cost_diff = new.cost_purchase - iif(inserting, 0, old.cost_purchase);
    
                            -- 1: add rows for v_cost_diff for being storned further
                            execute procedure sp_multiply_rows_for_pdistr(
                                new.id,
                                new.agent_id,
                                v_new_op,
                                v_cost_diff
                            );
    
                            -- 2: storn old docs by v_cost_diff ( fn_oper_pay_to_supplier, fn_oper_pay_from_customer )
                            execute procedure sp_make_cost_storno( new.id, :v_new_op, new.agent_id, :v_cost_diff );
    
                        end -- ins or upd
                    else --- deleting in doc_list
                        begin
                            -- return back records from pstorned to pdistr
                            -- ::: nb ::: use MERGE instead of insert because partial
                            -- cost storning (when move PART of cost from pdistr to pstorned)
                            execute procedure sp_kill_cost_storno( old.id );
                        end -- deleting
    
                end -- v_oper_changing_cust_saldo<>0 or v_oper_changing_supp_saldo<>0
    
                ------------------- add to money_turnover_log ----------------------
                execute procedure sp_add_money_log(
                    iif(not deleting, new.id, old.id),
                    0, -- v_old_mult,
                    0, -- old.agent_id,
                    0, -- v_old_op,
                    0, -- old.cost_purchase,
                    0, -- old.cost_retail,
                    1, -- v_new_mult,
                    iif(not deleting, new.agent_id, old.agent_id),
                    iif(not deleting, new.optype_id, old.optype_id), --v_new_op,
                    iif(not deleting, new.cost_purchase - coalesce(old.cost_purchase,0), -old.cost_purchase), --  new.cost_purchase,
                    iif(not deleting, new.cost_retail - coalesce(old.cost_retail,0), - old.cost_retail) -- new.cost_retail
                );
    
            end
             -- ########################################
        else -- cost_purchase and cost_retail - the same (sp_add_invoice_to_stock; sp_reserve_write_off; s`p_cancel_adding_invoice; s`p_cancel_write_off)
             -- ########################################
    
            if (updating) then
            begin
              if ( --new.agent_id is distinct from old.agent_id -- todo later, not implemented yet
                   --or
                   new.optype_id is distinct from old.optype_id
                 ) then
              begin
                -----------
                if ( v_oper_changing_cust_saldo <> 0 or v_oper_changing_supp_saldo <> 0  ) then
                begin
                    if ( v_new_op in (v_oper_changing_cust_saldo, v_oper_changing_supp_saldo) ) then
                    begin
                        -- F O R W A R D   operation: sp_add_invoice_to_stock; sp_reserve_write_off
                        v_cost_diff = iif( v_oper_changing_cust_saldo <> 0, new.cost_retail, new.cost_purchase );
    
                        -- 1: add rows for rest of cost for being storned by further docs
                        execute procedure sp_multiply_rows_for_pdistr(
                            new.id,
                            new.agent_id,
                            v_new_op,
                            v_cost_diff
                        );
                        -- 2: storn old docs by v_cost_diff  (sp_add_invoice_to_stock; sp_reserve_write_off)
                        execute procedure sp_make_cost_storno( new.id, :v_new_op, new.agent_id, :v_cost_diff );
    
                    end
                    else -- R E V E R T   operation: s`p_cancel_adding_invoice, s`p_cancel_write_off
                    begin
                       -- AFTER trigger on master table (THIS) will fire BEFORE any triggers on detail (doc_data)!
                       -- http://www.sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1081231&msg=15685218
                       -- return back records from pstorned to pdistr
                       -- ::: nb ::: use MERGE instead of insert because partial
                       -- cost storning (when move PART of cost from pdistr to pstorned)
                       execute procedure sp_kill_cost_storno( old.id );
                   end -- v_new_op in (v_oper_changing_cust_saldo, v_oper_changing_supp_saldo) ==> true / false
    
                end -- ( v_oper_changing_cust_saldo <> 0 or v_oper_changing_supp_saldo <> 0  )
    
                ------------------- add to money_turnover_log ----------------------
                execute procedure sp_add_money_log(
                    old.id,
                    v_old_mult,
                    old.agent_id,
                    v_old_op,
                    old.cost_purchase,
                    old.cost_retail,
                    v_new_mult,
                    new.agent_id,
                    v_new_op,
                    new.cost_purchase,
                    new.cost_retail
                );
            end -- changes occur in agent_id or optype_id
        end -- updating

    end -- v_affects_on_monetary_balance <> 0

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this);

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            'error in '||v_this,
            gdscode,
            v_msg,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- doc_list_aiud

set term ;^
commit;


-- ###################################################################
-- database triggers, currently they must be created in INACTIVE state
-- ###################################################################
set term ^;

create or alter procedure sp_perf_eds_logging(a_event_type char(1), a_caller dm_dbobj = '') as
    declare v_app varchar(255);
    declare p smallint;
begin
    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#
    -- ::: NOTE :::
    -- Avoid to get values of EXT_CONN_POOL_IDLE_COUNT and _ACTIVE_COUNT
    -- here because this code is invoked extremely frequent!
    -- It is enough to log their values in sp_add_perf_log and do this
    -- only for unit which did start business action.
    -- See also suggestion by Vlad, letter 08.12.2020 18:09.

    v_app = reverse( right(rdb$get_context('SYSTEM','CLIENT_PROCESS'), 80) );
    p = maxvalue(position('\' in v_app ), position('/' in v_app ));
    v_app = reverse(substring(v_app from 1 for p-1));

    --#SUBST#RESETTING_0#BEG# if ( a_caller = 'TRG_CONNECT' ) then --#SUBST#RESETTING_0#END#
    --#SUBST#RESETTING_0#BEG#     a_event_type = iif(v_app = 'firebird' or v_app = 'firebird.exe', 'A', 'N'); --#SUBST#RESETTING_0#END#
    --#SUBST#RESETTING_0#BEG# else if ( a_caller = 'TRG_DISCONNECT' ) then --#SUBST#RESETTING_0#END#
    --#SUBST#RESETTING_0#BEG#     a_event_type = iif(v_app = 'firebird' or v_app = 'firebird.exe', 'I', 'D'); --#SUBST#RESETTING_0#END#

    insert into v_perf_eds(app, evt) values( :v_app, :a_event_type);
    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */
end
^

-- #################################
-- ###   T R G _ C O N N E C T   ###
-- #################################

-- NOTE: currently this trigger is created with INactive state.
-- It will be Active at the end of all database building process, see 'oltp_data_filling.sql'
create or alter trigger trg_connect inactive on connect as
begin
    -- Intialize session-leve context variables from SETTINGS values.
    -- NOTE (25.11.2020): this SP can also be called from function
    -- FN_THIS_WORKER_SEQ_NO
    execute procedure sp_init_ctx;

    if ( left(rdb$get_context ('SYSTEM', 'NETWORK_PROTOCOL'),3) != 'TCP' ) then
    begin
       insert into perf_log(unit, info )
       values( 'trg_connect', 'attach using NON-TCP protocol' );
    end

    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#

    --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging( '?', 'TRG_CONNECT' ); --#SUBST#RESETTING_0#END#
    --#SUBST#RESETTING_1#BEG# execute procedure sp_perf_eds_logging( iif(resetting, 'A', 'N') ); --#SUBST#RESETTING_1#END#

    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */
end
^ -- trg_connect

-- #######################################
-- ###   T R G _ D I S C O N N E C T   ###
-- #######################################
create or alter trigger trg_disconnect inactive on disconnect as
begin
    /* #ACTIVATE#IF#USE_ES_EQU_2#BEG#

    --#SUBST#RESETTING_0#BEG# execute procedure sp_perf_eds_logging( '?', 'TRG_DISCONNECT' ); --#SUBST#RESETTING_0#END#

    --#SUBST#RESETTING_1#BEG# -- NB. If current FB instance supports 'resetting' then ALTER SESSION RESET will run every time connection finish EDS. --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG# -- This statement actually fires BOTH triggers: 1) on DISCONNECT, and (immediatelly!) after this - 2) on CONNECT. --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG# -- Connection that becomes idle will remain in this state until next involving (if it will not be dropped after lifetime expiration). --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG# -- NO any operation will be performed when connection must be changed from idle to active. --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG# -- This means that **TWO** events occurs when connection become idle and *ZERO* when it must become active. --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG# -- This, in turn, means that we can IGNORE event of DISCONNECT and do not log it: it has not useful info. --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG# -- So, we have to log only event of final detach from DB: --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG# if ( not resetting ) then --#SUBST#RESETTING_1#END#
    --#SUBST#RESETTING_1#BEG#     execute procedure sp_perf_eds_logging( 'D' ); --#SUBST#RESETTING_1#END#

    -- #ACTIVATE#IF#USE_ES_EQU_2#END# */
end
^

set term ;^
commit;

--------------------------------------------------------------------------------
-- ####################   C O R E    P R O C s    a n d   F U N C s   ##########
--------------------------------------------------------------------------------
set term ^;

create or alter procedure sp_add_doc_list(
    a_gen_id type of dm_idb, -- preliminary obtained from sequence (used in s`p_make_qty_storno)
    a_optype_id type of dm_idb,
    a_agent_id type of dm_idb,
    a_new_state type of dm_idb default null,
    a_base_doc_id type of dm_idb default null, -- need only for customer reserve which linked to client order
    a_new_cost_purchase type of dm_cost default 0,
    a_new_cost_retail type of dm_cost default 0
) returns(
    id dm_idb,
    dbkey dm_dbkey
)
as
begin
    -- add single record into doc_list (document header)

    -- See oltpNN_config, parameter 'use_es'. Can be 0, 1 or 2:
    /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
    execute statement (
        'insert into doc_list('
        || '    id,'               -- 1
        || '    worker_id,'        -- 2
        || '    optype_id,'        -- 3
        || '    agent_id,'         -- 4
        || '    state_id,'         -- 5
        || '    base_doc_id,'      -- 6
        || '    cost_purchase,'    -- 7
        || '    cost_retail'       -- 8
        || ') '
        || 'values( ?, ?, ?, ?, ?, ?, ?, ? ) '
        || 'returning id, rdb$db_key'
    )
    (
        coalesce(:a_gen_id, gen_id(g_common,1)),
        fn_this_worker_seq_no(),
        :a_optype_id,
        :a_agent_id,
        :a_new_state,
        :a_base_doc_id,
        :a_new_cost_purchase,
        :a_new_cost_retail
    )
    -- 23.11.2020: do NOT use EDS here! FK violation will be in that case!
    into id, dbkey;
    -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */

    -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
    -- usual way (use_es = 0): use static PSQL code.
    insert into doc_list(
        id,
        worker_id,
        optype_id,
        agent_id,
        state_id,
        base_doc_id,
        cost_purchase,
        cost_retail
    )
    values(
        coalesce(:a_gen_id, gen_id(g_common,1)),
        fn_this_worker_seq_no(),
        :a_optype_id,
        :a_agent_id,
        :a_new_state,
        :a_base_doc_id,
        :a_new_cost_purchase,
        :a_new_cost_retail
    )
    returning id, rdb$db_key
    into id, dbkey;
    -- #ACTIVATE#IF#USE_ES_EQU_0#END# */


    rdb$set_context('USER_SESSION','ADD_INFO','doc='||id||': created Ok'); -- to be displayed in log of 1run_oltp_emul.bat (debug)

    if ( rdb$get_context('USER_TRANSACTION','INIT_DATA_POP') = 1 )
    then -- now we only run INITIAL data filling, see 1run_oltp_emul.bat
        -- 18.07.2014: added gen_id to analyze in init data populate script,
        -- see 1run_oltp_emul.bat 
        id = id + 0 * gen_id(g_init_pop, 1);

    suspend;
end

^   --  sp_add_doc_list

------------------------------------------------

create or alter procedure sp_add_doc_data(
    a_doc_id dm_idb,
    a_optype_id dm_idb,
    a_gen_dd_id dm_idb, -- preliminary calculated ID for new record in doc_data (reduce lock-contention of GEN page)
    a_gen_nt_id dm_idb, -- preliminary calculated ID for new record in invnt_turnover_log (reduce lock-contention of GEN page)
    a_ware_id dm_idb,
    a_qty type of dm_qty,
    a_cost_purchase type of dm_cost,
    a_cost_retail type of dm_cost
) returns(
    id dm_idb,
    dbkey dm_dbkey
)
as
    declare v_this dm_dbobj = 'sp_add_doc_data';
begin
    -- add to performance log timestamp about start/finish this unit:
    -- uncomment if need analyze perormance in mon_log tables
    -- + update settings set svalue='/sp_make_qty_storno/sp_add_doc_data/' where mcode='MON_UNIT_LIST';
    -- execute procedure sp_add_perf_log(1, v_this, null, 'a_gen_dd_id='||trim(coalesce(a_gen_dd_id||'=>ins','null'))||', a_dbkey: '||trim(iif(a_dbkey is null,'isNull','hasVal=>upd')) );

    -- insert single record into doc_data
    -- :: NB :: update & "if row_count = 0 ? => insert" is much effective
    -- then insert & "when uniq_violation ? => update" (no backouts, less fetches)
    if ( a_gen_dd_id is NOT null ) then
        insert into doc_data(
            id,
            doc_id,
            ware_id,
            qty,
            cost_purchase,
            cost_retail,
            dts_edit)
        values(
            :a_gen_dd_id,
            :a_doc_id,
            :a_ware_id,
            :a_qty,
            :a_cost_purchase,
            :a_cost_retail,
            'now')
        returning id, rdb$db_key into id, dbkey;
    else
        begin
            update doc_data t set
                t.qty = t.qty + :a_qty,
                t.cost_purchase = t.cost_purchase + :a_cost_purchase,
                t.cost_retail = t.cost_retail + :a_cost_retail,
                t.dts_edit = 'now'
            where t.doc_id = :a_doc_id and t.ware_id = :a_ware_id
            returning t.id, t.rdb$db_key into id, dbkey;

            if ( row_count = 0 ) then
                insert into doc_data( doc_id, ware_id, qty, cost_purchase, cost_retail, dts_edit)
                values( :a_doc_id, :a_ware_id, :a_qty, :a_cost_purchase, :a_cost_retail, 'now')
                returning id, rdb$db_key into id, dbkey;
        end
    ----------------------------------------------------------------------------
    -- 20.09.2014: move here from trigger on doc_list
    -- (reduce scans of doc_data)
    if ( :a_qty <> 0 ) then
        insert into invnt_turnover_log(
             id
            ,ware_id
            ,qty_diff
            ,cost_diff
            ,doc_list_id
            ,doc_pref
            ,doc_data_id
            ,optype_id
        ) values (
            :a_gen_nt_id
            ,:a_ware_id
            ,:a_qty
            ,:a_cost_purchase
            ,:a_doc_id
            ,fn_mcode_for_oper(:a_optype_id)
            ,:id
            ,:a_optype_id
        );

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    -- uncomment if need analyze perormance in mon_log tables:
    --execute procedure sp_add_to_perf_log(v_this,null,'out: id='||id);

    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'out: id='||coalesce(id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_add_doc_data

create or alter function fn_get_random_quantity(
    a_ctx_max_name dm_ctxnv
)
returns dm_qty as
    declare v_min double precision;
    declare v_max double precision;
begin
  v_min = 0.5;
  v_max = cast( rdb$get_context('USER_SESSION',a_ctx_max_name) as int) + 0.5;
  return cast( v_min + rand()* (v_max - v_min)  as int);

end

^ -- fn_get_random_quantity

create or alter function fn_get_random_cost(
    a_ctx_min_name dm_ctxnv,
    a_ctx_max_name dm_ctxnv,
    a_make_check_before smallint default 1
)
returns dm_cost as
    declare v_min double precision;
    declare v_max double precision;
begin
  if (a_make_check_before = 1) then
        execute procedure sp_check_ctx(
            'USER_SESSION',a_ctx_min_name,
            'USER_SESSION',a_ctx_max_name
      );
  v_min = cast( rdb$get_context('USER_SESSION',a_ctx_min_name) as int) - 0.5;
  v_max = cast( rdb$get_context('USER_SESSION',a_ctx_max_name) as int) + 0.5;
  return cast( v_min + rand()* (v_max - v_min)  as dm_cost);

end

^ -- fn_get_random_cost

create or alter function fn_get_random_customer returns bigint as
begin
    return (select id_selected from sp_get_random_id('v_all_customers', null, null, 0) );
end
^

create or alter function fn_get_random_supplier returns bigint as
begin
    return (select id_selected from sp_get_random_id('v_all_suppliers', null, null, 0) );
end

^ -- fn_get_random_customer

------------------------------------------------------------------------------

create or alter procedure sp_make_qty_storno(
    a_optype_id dm_idb
    ,a_agent_id dm_idb
    ,a_state_id type of dm_idb default null
    ,a_client_order_id type of dm_idb default null
    ,a_rows_in_shopcart int default null
    ,a_qsum_in_shopcart dm_qty default null
)
returns (
    doc_list_id bigint
)
as
    declare c_gen_inc_step_qd int = 100; -- size of `batch` for get at once new IDs for QDistr (reduce lock-contention of gen page)
    declare v_gen_inc_iter_qd int; -- increments from 1  up to c_gen_inc_step_qd and then restarts again from 1
    declare v_gen_inc_last_qd dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_qd)
    declare c_gen_inc_step_dd int = 20; -- size of `batch` for get at once new IDs for doc_data (reduce lock-contention of gen page)
    declare v_gen_inc_iter_dd int; -- increments from 1  up to c_gen_inc_step_dd and then restarts again from 1
    declare v_gen_inc_last_dd dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_dd)
    declare c_gen_inc_step_nt int = 20; -- size of `batch` for get at once new IDs for invnt_turnover_log (reduce lock-contention of gen page)
    declare v_gen_inc_iter_nt int; -- increments from 1  up to c_gen_inc_step_dd and then restarts again from 1
    declare v_gen_inc_last_nt dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_dd)
    declare v_inserting_table dm_dbobj;
    declare v_id type of dm_idb;
    declare v_curr_tx bigint;
    declare v_ware_id dm_idb;
    declare v_dh_new_id bigint;
    declare v_dd_new_id bigint;
    declare v_nt_new_id dm_idb;
    declare v_dd_dbkey dm_dbkey;
    declare v_dd_clo_id dm_idb;
    declare v_doc_data_purchase_sum dm_cost;
    declare v_doc_data_retail_sum dm_cost;
    declare v_doc_list_purchase_sum dm_cost;
    declare v_doc_list_retail_sum dm_cost;
    declare v_doc_list_dbkey dm_dbkey;
    declare v_rows_added int;
    declare v_storno_sub smallint;
    declare v_qty_storned_acc type of dm_qty;
    declare v_qty_required type of dm_qty;
    declare v_qty_could_storn type of dm_qty;
    declare v_snd_optype_id type of dm_idb;
    declare v_rcv_optype_id type of dm_idb;
    declare v_next_rcv_op type of dm_idb;
    declare v_this dm_dbobj = 'sp_make_qty_storno';
    declare v_call dm_unit; -- do NOT use `dm_dbobj`! This caused string overflow in 4.0, since 16-jul-2016; see letter from hvlad 06-jan-2017 01:59
    declare v_halt_on_pk_viol smallint;
    declare v_info dm_info;
    declare v_rows int = 0;
    declare v_lock int = 0;
    declare v_skip int = 0;
    declare v_dummy bigint;
    declare v_sign dm_sign;
    declare v_cq_id dm_idb;
    declare v_cq_snd_list_id dm_idb;
    declare v_cq_snd_data_id dm_idb;
    declare v_cq_snd_qty dm_qty;
    declare v_cq_snd_purchase dm_cost;
    declare v_cq_snd_retail dm_cost;
    declare v_cq_snd_optype_id dm_idb;
    declare v_cq_rcv_optype_id type of dm_idb;
    declare v_cq_trn_id dm_idb;
    declare v_cq_dts timestamp;
    declare v_worker_id int;
    declare c_shop_cart cursor for (
        select
            id,
            dd_clo_id,
            snd_optype_id,
            rcv_optype_id,
            qty,
            storno_sub
        from (
                select
                    c.id,
                    cast(null as dm_idb) as dd_clo_id,  -- 22.09.2014
                    c.snd_optype_id,
                    c.rcv_optype_id,
                    c.qty,
                    c.storno_sub
                from tmp$shopping_cart c

                UNION ALL

                select
                    c.id,
                    c.snd_id, -- 22.09.2014, for clo_res
                    r.snd_optype_id,
                    c.rcv_optype_id,
                    c.qty,
                    r.storno_sub
                from tmp$shopping_cart c
                INNER join v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
                  on :a_client_order_id is NOT null
                     -- only in 3.0: hash join (todo: check perf when NL, create indices)
                     and c.rcv_optype_id + 0 = r.rcv_optype_id + 0 -- PLAN HASH (R NATURAL, C NATURAL)
                     and r.storno_sub = 2
        ) u
        order by id, storno_sub
    );
    ----------------------------------------------------------------------------
    -- 22.09.2014: two separate cursors for diff storno_sub
    declare c_make_amount_distr_1 cursor for (
        select
             q.id
            ,q.doc_id as snd_list_id
            ,q.snd_id as snd_data_id
            ,q.snd_qty
            ,q.snd_purchase
            ,q.snd_retail
            ,q.snd_optype_id
            ,q.rcv_optype_id
            ,q.trn_id
            ,q.dts
        -- 'v_qdistr_source_1' initially this is one-to-one projection of 'QDistr' table. 
        -- But it can be replaced with 'AUTOGEN_QDnnnn' when config create_with_split_heavy_tabs = 1.
        from v_qdistr_source_1 q 
        where
            q.ware_id = :v_ware_id -- find invoices to be storned storning by new customer reserve, and all other ops except storning client orders
            and q.snd_optype_id = :v_snd_optype_id
            and q.rcv_optype_id = :v_rcv_optype_id
            -- 12.08.2018: sequential number of ISQL session that queries this view.
            -- This filter is added with purpose to reduce number of lock-conflict errors:
            and q.worker_id is not distinct from :v_worker_id
        order by
            q.doc_id
              + 0 -- handle docs in FIFO order
            ,:v_sign * q.id -- attempt to reduce locks: odd and even Tx handles rows in opposite manner (for the same doc) thus have a chance do not encounter locked rows at all
    );

    declare c_make_amount_distr_2 cursor for (
        select
             q.id
            ,q.doc_id as snd_list_id
            ,q.snd_id as snd_data_id
            ,q.snd_qty
            ,q.snd_purchase
            ,q.snd_retail
            ,q.snd_optype_id
            ,q.rcv_optype_id
            ,q.trn_id
            ,q.dts
        -- 'v_qdistr_source_2' initially this is one-to-one projection of 'QDistr' table.
        -- But it can be replaced with 'AUTOGEN_QD1000' when config create_with_split_heavy_tabs = 1.
        from v_qdistr_source_2 q
        where
            q.ware_id = :v_ware_id -- find client orders to be storned by new customer reserve
            and q.snd_optype_id = :v_snd_optype_id
            and q.rcv_optype_id = :v_rcv_optype_id
            and q.snd_id = :v_dd_clo_id 
            -- 12.08.2018: sequential number of ISQL session that queries this view.
            -- This filter is added with purpose to reduce number of lock-conflict errors:
            and q.worker_id is not distinct from :v_worker_id
        order by
            q.doc_id
              + 0 -- handle docs in FIFO order
            ,:v_sign * q.id -- attempt to reduce locks: odd and even Tx handles rows in opposite manner (for the same doc) thus have a chance do not encounter locked rows at all
    );
begin

    -- Issue about QDistr & QStorned: for each SINGLE record from doc_data with
    -- qty=<N> table QDistr initially contains <N> DIFFERENT records (if no storning
    -- yet occur for that amount from doc_data).
    -- Each storning takes off some records from this set and "moves" them into
    -- table QStorned. This SP *does* such storning.
    ----------------------------------------------------------------------------
    -- Performs attempt to make distribution of AMOUNTS which were added to "sender" docs
    -- and then 'multiplied' (added in QDISTR table) using "value-to-rows"
    -- algorithm in sp_multiply_rows_for_qdistr. If some row is locked now,
    -- SUPRESS exc`eption and skip to next one. If required amount can NOT
    -- be satisfied, it will be reduced (in tmp$shopping_cart) or even REMOVED
    -- at all from tmp$shopping_cart (without raising exc: we must minimize them)
    -- ::: NB :::
    -- Method: "try_to_lock_src => upd_confl ? skip : {ins_target & del_in_src}"
    -- is more than 3 times FASTER than: "ins_tgt => uniq_viol ? skip : del_in_src"
    -- (see benchmark in letter to dimitr 26.08.2014 13:00)
    -- 01.09.2014: refactored, remove cursor on doc_data (huge values of IDX_READS!)
    -- 02.09.2014: move here code block from  sp_create_doc_using_fifo, further reduce scans of doc_data
    -- 06.09.2014: doc_data: 3 idx_reads per each unique ware_id (one here, two in SP s`rv_find_qd_qs_mism)

    select r.rcv_optype_id
    from v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
    where r.snd_optype_id = :a_optype_id
    into v_next_rcv_op;

    -- move evaluation outside from cursor loop:
    v_halt_on_pk_viol = iif( rdb$get_context('USER_SESSION','HALT_TEST_ON_ERRORS') containing '/PK/', 1, 0);

    v_call = v_this;
    -- doc_list.id must be defined PRELIMINARY, before cursor that handles with qdistr:
    v_dh_new_id = gen_id(g_common, 1);

    v_info =
        'op='||a_optype_id
        ||', next_op='||coalesce(v_next_rcv_op,'<?>')
        ||coalesce(', clo='||a_client_order_id, '');
    execute procedure sp_add_perf_log(1, v_call, null, v_info);

    v_worker_id = fn_this_worker_seq_no();

    v_qty_could_storn = 0;
    v_rows_added = 0;
    v_doc_list_purchase_sum = 0;
    v_doc_list_retail_sum = 0;

    v_gen_inc_iter_dd = 1;
    c_gen_inc_step_dd = coalesce( 1 + a_rows_in_shopcart, 20 ); -- adjust value to increment IDs in DOC_DATA at one call of gen_id
    v_gen_inc_last_dd = gen_id( g_doc_data, :c_gen_inc_step_dd );-- take bulk IDs at once (reduce lock-contention for GEN page)

    v_gen_inc_iter_qd = 1;
    c_gen_inc_step_qd = coalesce( 1 + a_qsum_in_shopcart, 100 ); -- adjust value to increment IDs in QDISTR at one call of gen_id
    v_gen_inc_last_qd = gen_id( g_qdistr, :c_gen_inc_step_qd );-- take bulk IDs at once (reduce lock-contention for GEN page)

    v_gen_inc_iter_nt = 1;
    c_gen_inc_step_nt = coalesce( 1 + a_rows_in_shopcart, 20 ); -- adjust value to increment IDs in INVNT_TURNOVER_LOG at one call of gen_id
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    v_sign = iif( bin_and(current_transaction, 1)=0, 1, -1);

    -- rules_for_qdistr.storno_sub = 2 - storno data of clo when creating customer RESERVE:
    -- MODE              SND_OPTYPE_ID    RCV_OPTYPE_ID    STORNO_SUB
    -- mult_rows_only    1000             3300             2
    -- Result of cursor c_shop_cart for ware_id=1 when call from sp_customer_reserve:
    -- ID    SND_OPTYPE_ID    RCV_OPTYPE_ID    QTY    STORNO_SUB
    -- 1          2100             3300         1         1
    -- 1          1000             3300         1         2
    open c_shop_cart;
    while (1=1) do
    begin
        fetch c_shop_cart
        into v_ware_id, v_dd_clo_id, v_snd_optype_id, v_rcv_optype_id, v_qty_required, v_storno_sub;
        if ( row_count = 0 ) then leave;

        v_qty_could_storn = iif(v_storno_sub=1,  0, v_qty_could_storn);
        v_qty_required = iif(v_storno_sub=1,  v_qty_required, v_qty_could_storn);

        v_dd_dbkey = iif(v_storno_sub=1,  null, v_dd_dbkey);
        v_dd_new_id = iif(v_storno_sub=1,  null, v_dd_new_id);

        v_qty_storned_acc = 0; -- how many units will provide required Qty from CURRENT LINE of shopping cart
        v_doc_data_purchase_sum = 0;
        v_doc_data_retail_sum = 0;

        if ( v_storno_sub = 1 ) then
            open c_make_amount_distr_1;
        else
            open c_make_amount_distr_2;
        ------------------------------------------------------------------------
        while ( :v_qty_storned_acc < :v_qty_required ) do
        begin
            if ( v_storno_sub = 1 ) then
                fetch c_make_amount_distr_1
                into
                    v_cq_id,v_cq_snd_list_id,v_cq_snd_data_id
                    ,v_cq_snd_qty,v_cq_snd_purchase,v_cq_snd_retail
                    ,v_cq_snd_optype_id,v_cq_rcv_optype_id
                    ,v_cq_trn_id,v_cq_dts;
            else
                fetch c_make_amount_distr_2
                into
                    v_cq_id,v_cq_snd_list_id,v_cq_snd_data_id
                    ,v_cq_snd_qty,v_cq_snd_purchase,v_cq_snd_retail
                    ,v_cq_snd_optype_id,v_cq_rcv_optype_id
                    ,v_cq_trn_id,v_cq_dts;

            if ( row_count = 0 ) then leave;
            v_info =  'fetch '
                ||iif( v_storno_sub = 1, 'c_make_amount_distr_1', 'c_make_amount_distr_2')
                ||', qd.id='||v_cq_id;
            v_rows = v_rows + 1; -- total ATTEMPTS to make delete/update in QDistr

            if ( mod(v_rows, 100) = 0 ) then
               -- Check whether test can continue: if request to stop exists
               -- then raises ex`ception to stop this session ASAP.
               -- Added 11.09.2016.
               execute procedure sp_check_to_stop_work;


            -- ### A.C.H.T.U.N.G ###
            -- Make increment of `v_gen_inc_iter_**` ALWAYS BEFORE any lock-conflict statements
            -- (otherwise duplicates will appear in ID because of suppressing lock-conflict ex`c.)
            -- #####################
            if ( v_storno_sub = 1 ) then
            begin -- calculate subsequent value for doc_data.id from previously obtained batch:
                if ( v_gen_inc_iter_qd >= c_gen_inc_step_qd ) then -- its time to get another batch of IDs
                begin
                    v_gen_inc_iter_qd = 1;
                    -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                    v_gen_inc_last_qd = gen_id( g_qdistr, :c_gen_inc_step_qd );
                end

                if ( v_qty_storned_acc = 0 ) then
                begin
                    -- NO rows could be locked in QDistr (by now) for providing
                    -- QTY from current line of shopping cart ==> we did not yet
                    -- inserted row into doc_data with :v_ware_id ==> get subseq.
                    -- value for :v_dd_new_id from `pool`:
                    if ( v_gen_inc_iter_dd >= c_gen_inc_step_dd ) then -- its time to get another batch of IDs
                    begin
                        v_gen_inc_iter_dd = 1;
                        -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                        v_gen_inc_last_dd = gen_id( g_doc_data, :c_gen_inc_step_dd );
                    end
                    v_dd_new_id = v_gen_inc_last_dd - ( c_gen_inc_step_dd - v_gen_inc_iter_dd );
                    v_gen_inc_iter_dd = v_gen_inc_iter_dd + 1;
                end
            end


            -- 26.10.2015. Additional begin..end block needs for providing DML
            -- 'atomicity' of BOTH tables pdistr & pstorned! Otherwise changes
            -- can become inconsistent if online validation will catch table-2
            -- after this code finish changes on table-1 but BEFORE it will
            -- start to change table-2.
            -- See CORE-4973 (example of WRONG code which did not used this addi block!)
            begin
                -- We can place delete sttmt BEFORE insert because of using explicit cursor and
                -- fetch old fields data (which is to be moved into QStorned) into declared vars:
                if ( v_storno_sub = 1 ) then
                    begin
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            v_call = v_this || ':try_del_qdsub1';
                            execute procedure sp_add_perf_log(1, v_call, null, v_info); -- 10.02.2015
                            --rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_TRY_DEL_QD_ID', v_cq_id);
                        end
    
                        delete from v_qdistr_source_1 q where current of c_make_amount_distr_1; --- lock_conflict can occur here
    
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            --rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_OK_DEL_QD_ID', v_cq_id);
                            execute procedure sp_add_perf_log(0, v_call, null, 'c_make_amount_distr_1: deleted OK');
                        end
                    end --  v_storno_sub = 1
                else
                    begin
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            v_call = v_this || ':try_del_qdsub2';
                            execute procedure sp_add_perf_log(1, v_call, null, v_info);
                            --rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB2_TRY_DEL_QD_ID', v_cq_id);
                        end
    
                        -- When config parameter 'create_with_split_heavy_tabs' is 1 then 'v_qdistr_source_2' should be changed to 'XQD_*'
                        delete from v_qdistr_source_2 q where current of c_make_amount_distr_2; --- lock_conflict can occur here
    
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            --rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB2_OK_DEL_QD_ID', v_cq_id);
                            execute procedure sp_add_perf_log(0, v_call, null, 'c_make_amount_distr_2: deleted OK');
                        end
                    end --  v_storno_sub = 2
    
                if ( v_storno_sub = 1 ) then -- ==>  distr_mode containing 'new_doc'
                begin
                    v_inserting_table = 'qdistr';
                    -- iter=1: v_id = 12345 - (100-1); iter=2: 12345 - (100-2); ...
                    v_id = v_gen_inc_last_qd - ( c_gen_inc_step_qd - v_gen_inc_iter_qd );
    
                    if ( v_halt_on_pk_viol = 1) then
                    begin
                        -- debug info for logging in srv_log_dups_qd_qs if PK
                        -- violation will occur on INSERT INTO QSTORNED statement
                        -- (remained for possible analysis):
                        v_call = v_this || ':try_ins_qdsub1';
                        v_info = v_info || ', try INSERT into QDistr id='||v_id;
        
                        execute procedure sp_add_perf_log(1, v_call, null, v_info); -- 10.02.2015, debug
                        --rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_TRY_INS_QD_ID', v_id);
                    end
    
                    insert into v_qdistr_target_1 (
                        id,
                        doc_id,
                        worker_id,
                        ware_id,
                        snd_optype_id,
                        rcv_optype_id,
                        snd_id,
                        snd_qty,
                        snd_purchase,
                        snd_retail)
                    values(
                        :v_id,
                        :v_dh_new_id,
                        :v_worker_id,
                        :v_ware_id,
                        :a_optype_id,
                        :v_next_rcv_op,
                        :v_dd_new_id,
                        :v_cq_snd_qty,
                        :v_cq_snd_purchase,
                        :v_cq_snd_retail
                    );
    
                    if ( v_halt_on_pk_viol = 1) then
                    begin
                        --rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_OK_INS_QD_ID', v_id);
                        execute procedure sp_add_perf_log(0, v_call, null, 'v_qdistr_target_1: inserted OK');
                    end
    
                    v_gen_inc_iter_qd = v_gen_inc_iter_qd + 1;
                end --  v_storno_sub = 1
    
                v_inserting_table = 'qstorned';
                v_id =  v_cq_id;
    
                if ( v_halt_on_pk_viol = 1) then
                begin
                    -- debug info for logging in srv_log_dups_qd_qs if PK
                    -- violation will occur on INSERT INTO QSTORNED statement
                    -- (remained for possible analysis):
                    v_info = v_info||', try INSERT into QStorned: id='||:v_id;
                    v_call = v_this || ':try_ins_qStorn';
        
                    execute procedure sp_add_perf_log(1, v_call, null, v_info); -- 10.02.2015, debug
                    --rdb$set_context('USER_TRANSACTION','DBG_MAKE_QSTORN_TRY_INS_QS_ID', v_id);
                end
    
                if ( v_storno_sub = 1 )  then
                    insert into v_qstorned_target_1 (
                         id,
                         doc_id,
                         worker_id,
                         ware_id, dts, -- do NOT specify field `trn_id` here! 09.10.2014 2120
                         snd_optype_id, snd_id, snd_qty,
                         rcv_optype_id,
                         rcv_doc_id,
                         rcv_id,
                         snd_purchase, snd_retail
                    ) values (
                        :v_id
                        ,:v_cq_snd_list_id
                        ,:v_worker_id
                        ,:v_ware_id, :v_cq_dts -- dis 09.10.2014 2120: :v_cq_trn_id,
                        ,:v_cq_snd_optype_id, :v_cq_snd_data_id,:v_cq_snd_qty
                        ,:v_cq_rcv_optype_id
                        ,:v_dh_new_id
                        ,:v_dd_new_id
                        ,:v_cq_snd_purchase,:v_cq_snd_retail
                    );
                else
                    insert into v_qstorned_target_2 (
                        id,
                        doc_id,
                        worker_id,
                        ware_id, dts, -- do NOT specify field `trn_id` here! 09.10.2014 2120
                        snd_optype_id, snd_id, snd_qty,
                        rcv_optype_id,
                        rcv_doc_id,
                        rcv_id,
                        snd_purchase, snd_retail
                    ) values (
                        :v_id
                        ,:v_cq_snd_list_id
                        ,:v_worker_id
                        ,:v_ware_id, :v_cq_dts -- dis 09.10.2014 2120: :v_cq_trn_id,
                        ,:v_cq_snd_optype_id, :v_cq_snd_data_id,:v_cq_snd_qty
                        ,:v_cq_rcv_optype_id
                        ,:v_dh_new_id
                        ,:v_dd_new_id
                        ,:v_cq_snd_purchase,:v_cq_snd_retail
                    );
    
                if ( v_halt_on_pk_viol = 1) then
                begin
                    --rdb$set_context('USER_TRANSACTION','DBG_MAKE_QSTORN_OK_INS_QS_ID', v_id);
                    execute procedure sp_add_perf_log(0, v_call, null, 'inserted OK');
                end

                v_qty_storned_acc = v_qty_storned_acc + v_cq_snd_qty; -- ==> will be written in doc_data.qty (actual amount that could be gathered)
                v_lock = v_lock + 1; -- total number of SUCCESSFULY locked records
    
                if ( v_storno_sub = 1 ) then
                begin
                    -- increment sums that will be written into doc_data line:
                    v_qty_could_storn = v_qty_could_storn + v_cq_snd_qty;
                    v_doc_data_purchase_sum = v_doc_data_purchase_sum + v_cq_snd_purchase;
                    v_doc_data_retail_sum = v_doc_data_retail_sum + v_cq_snd_retail;
                end
            end -- begin..end for atomicity of changes several tables (CORE-4973!)
        when any do
            -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
            -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
            -- catched it's kind of exception!
            -- 1) tracker.firebirdsql.org/browse/CORE-3275
            --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
            -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
            begin
                if ( fn_is_lock_trouble(gdscode) ) then
                    -- suppress this kind of exc`eption and
                    -- skip to next record!
                    v_skip = v_skip + 1;
                else
                    begin
                        -- ###############################################
                        -- PK violation on INSERT INTO QSTORNED, log this:
                        -- ###############################################
                        if ( fn_is_uniqueness_trouble(gdscode) ) then
                            -- 12.02.2015: the reason of PK violations is unpredictable order
                            -- of UNDO, ultimately explained by dimitr, see letters in e-mail.
                            -- Also: sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1142271&msg=17257984
                            execute procedure srv_log_dups_qd_qs( -- 09.10.2014: add log info using auton Tx
                                :v_call,
                                gdscode,
                                :v_inserting_table,
                                :v_id,
                                :v_info
                            );

                        exception; -- ::: nb ::: anonimous but in when-block!
                    end
            end
        end -- cursor on QDistr find rows for storning amount from tmp$shopping_cart for current v_ware_id, and MAKE such storning (move them in QStorned table)
        if ( v_storno_sub = 1 ) then
            close c_make_amount_distr_1;
        else
            close c_make_amount_distr_2;


        if ( v_dd_new_id is not null and v_storno_sub = 1 ) then
        begin
            if ( v_qty_storned_acc > 0 ) then
                begin
                    if (doc_list_id is null) then
                    begin
                        -- add new record in doc_list (header)
                        execute procedure sp_add_doc_list(
                            :v_dh_new_id
                            ,:a_optype_id
                            ,:a_agent_id
                            ,:a_state_id
                            ,:a_client_order_id
                        )
                        returning_values :doc_list_id, :v_doc_list_dbkey;
                    end

                    if ( v_gen_inc_iter_nt = c_gen_inc_step_nt ) then -- its time to get another batch of IDs
                    begin
                        v_gen_inc_iter_nt = 1;
                        -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                        v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );
                    end
                    v_nt_new_id = v_gen_inc_last_nt - ( c_gen_inc_step_nt - v_gen_inc_iter_nt );
                    v_gen_inc_iter_nt = v_gen_inc_iter_nt + 1;

                    -- single update of doc_data for each ware after scanning N records in qdistr:
                    -- (remove call of sp_multiply_rows_for_qdistr from d`oc_data_aiud):
                    execute procedure sp_add_doc_data(
                        :v_dh_new_id -- preliminary defined above
                        ,:a_optype_id
                        ,:v_dd_new_id -- preliminary calculated above (to reduce lock-contention of GEN page)
                        ,:v_nt_new_id -- preliminary calculated above (to reduce lock-contention of GEN page)
                        ,:v_ware_id
                        ,:v_qty_could_storn
                        ,:v_doc_data_purchase_sum
                        ,:v_doc_data_retail_sum
                    )
                    returning_values :v_dummy, :v_dd_dbkey;
        
                    v_rows_added = v_rows_added + 1;
                    -- increment sums that will be written into doc header:
                    v_doc_list_purchase_sum = v_doc_list_purchase_sum + v_doc_data_purchase_sum;
                    v_doc_list_retail_sum = v_doc_list_retail_sum + v_doc_data_retail_sum;
                end
        end

    end -- cursor on tmp$shopping_cart c [join v_rules_for_qdistr r]
    close c_shop_cart;


    if ( :doc_list_id is NOT null and v_rows_added > 0) then --  v_lock > 0 ) then
        begin
            -- single update of doc header (not for every row added in doc_data)
            -- Trigger d`oc_list_aiud will call sp_add_invnt_log to add rows to invnt_turnover_log

            -- See oltpNN_config, parameter 'use_es'. Can be 0, 1 or 2:
            /* #ACTIVATE#IF#USE_ES_NEQ_0#BEG#
            -- 22.11.2020
            execute statement (
                'update doc_list h set'
                || '    h.cost_purchase = ?,'
                || '    h.cost_retail = ?,'
                || '    h.dts_fix = iif( cast(? as int) = fn_doc_fix_state(), current_timestamp, h.dts_fix )'
                || ' where h.rdb$db_key = cast(? as char(8) character set octets)'
            )
            (  v_doc_list_purchase_sum
              ,v_doc_list_retail_sum
              ,a_state_id
              ,v_doc_list_dbkey
            )
            -- 23.11.2020: do NOT use EDS here! FK violation will be in that case!
            ;
            -- #ACTIVATE#IF#USE_ES_NEQ_0#END# */

            -- #ACTIVATE#IF#USE_ES_EQU_0#BEG#
            -- usual way (use_es = 0): use static PSQL code.
            update doc_list h set
                h.cost_purchase = :v_doc_list_purchase_sum,
                h.cost_retail = :v_doc_list_retail_sum,
                h.dts_fix = iif( :a_state_id = fn_doc_fix_state(), 'now', h.dts_fix)
            where h.rdb$db_key = :v_doc_list_dbkey;
            -- #ACTIVATE#IF#USE_ES_EQU_0#END# */

        end -- ( :doc_list_id is NOT null )
    else
        begin
            v_info =
                fn_mcode_for_oper(a_optype_id)
                ||iif(a_optype_id = fn_oper_retail_reserve(), ', clo='||coalesce( a_client_order_id, '<null>'), '')
                ||',  rows in tmp$cart: '||(select count(*) from tmp$shopping_cart);
    
            if ( a_client_order_id is null ) then -- ==> all except call of sp_customer_reserve for client order
                exception ex_cant_find_row_for_qdistr using( a_optype_id, (select count(*) from tmp$shopping_cart) );
            --'no rows found for FIFO-distribution: optype=@1, rows in tmp$shopping_cart=@2';
        end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    v_call = v_this;
    execute procedure sp_add_perf_log(0, v_call, null, 'dh='||coalesce(:doc_list_id,'<?>')||', qd ('||iif(:v_sign=1,'asc','dec')||'): capt='||v_lock||', skip='||v_skip||', scan='||v_rows||'; dd: add='||v_rows_added );

    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            v_info,
            v_call,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_make_qty_storno

--------------------------------------------------------------------------------

create or alter procedure srv_predictable_unit_choice returns(
    unit dm_name
) as
    declare v_this dm_dbobj = 'srv_predictable_unit_choice';
    declare v_prev varchar(100);
begin
    v_prev = coalesce( rdb$get_context('USER_SESSION','PREV_SELECTED_INFO'), rpad('',80,' ') || cast(0 as char(11)) );
    select cast( b.unit as char(80) ) || cast( b.predictable_selection_priority as char(11) )
    from business_ops b
    where b.predictable_selection_priority > cast( substring( :v_prev from 81 ) as int )
    order by b.predictable_selection_priority
    rows 1
    into v_prev;
    if (row_count = 0) then
    begin
        -- returns to first operation: sp_client_order
        select cast( b.unit as char(80) ) || cast( b.predictable_selection_priority as char(11) )
        from business_ops b
        order by b.predictable_selection_priority
        rows 1
        into v_prev;
        if (row_count = 0) then
            exception ex_record_not_found using ('BUSINESS_OPS', '"' || trim( substring( v_prev from 81 ) ) || '"' );
    end
    rdb$set_context('USER_SESSION','PREV_SELECTED_INFO', v_prev);
    unit = trim(substring( v_prev from 1 for 80 ));
    suspend;
end
^

create or alter procedure srv_random_unit_choice(
    a_included_modes dm_info default '',
    a_included_kinds dm_info default '',
    a_excluded_modes dm_info default '',
    a_excluded_kinds dm_info default ''
)
returns(
    unit dm_name,
    sort_prior int,
    rnd_weight int,
    r double precision,
    c int,
    n int
) as
    declare r_max int;
    declare v_dts_beg timestamp;
    declare v_last_recalc_idx_timestamp timestamp;
    declare v_last_recalc_idx_minutes_ago int;
    declare v_this dm_dbobj = 'srv_random_unit_choice';
    declare c_unit_for_gather_mon_data dm_dbobj = 'srv_fill_mon'; -- do NOT change the name of this SP!
    declare c_unit_for_recalc_idx_stat dm_dbobj = 'srv_recalc_idx_stat'; -- do NOT change the name of this SP!
    declare function fn_internal_enable_mon_query  returns smallint deterministic as
    begin
        return ( cast(rdb$get_context('USER_SESSION', 'ENABLE_MON_QUERY') as smallint) );
    end
    --declare function fn_internal_reind_min_interval returns int deterministic as
    --begin
    --    return ( cast(rdb$get_context('USER_SESSION', 'RECALC_IDX_MIN_INTERVAL') as int) );
    --end
    -- 14.04.2019:
    declare function fn_internal_reind_min_interval returns bigint deterministic as
        declare c bigint;
    begin
        c = cast(rdb$get_context('USER_SESSION', 'RECALC_IDX_MIN_INTERVAL') as int);
        c = iif( c<= 0, fn_infinity(), c);
        return c;
    end
begin
    -- main SP for selection business operation that must be performed on current iteration.
    -- Called from EXECUTE BLOCK in "Big SQL script" that is generated in .bat/.sh

    -- refactored 18.07.2014 (for usage in init data pop)
    -- sample: select * from srv_random_unit_choice( '','creation,state_next','','removal' )
    -- (will return first randomly choosen record related to creation of document
    -- or to changing its state in 'forward' way; excludes all cancellations and change
    -- doc states in 'backward')
    a_included_modes = coalesce( a_included_modes, ''); -- business_ops.mode = one of: {stock, payments, service}
    a_included_kinds = coalesce( a_included_kinds, ''); -- business_ops.mode = one of: {creation, removal, state_next, state_back, service}
    a_excluded_modes = coalesce( a_excluded_modes, '');
    a_excluded_kinds = coalesce( a_excluded_kinds, '');

    if ( rdb$get_context('USER_SESSION','PERF_WATCH_BEG') is null ) then
    begin
        select p.dts_beg from perf_log p where p.unit = 'perf_watch_interval' order by dts_beg+0 desc rows 1 into v_dts_beg;
        rdb$set_context( 'USER_SESSION','PERF_WATCH_BEG', v_dts_beg );
    end

    if ( cast('now' as timestamp) < cast( rdb$get_context('USER_SESSION','PERF_WATCH_BEG') as timestamp) ) then 
    begin
        -- 31.12.2018 We have to SKIP from removal or changing doc state 'backward'
        -- on PREPARING phase, i.e. since 0th to <warm_time> minute of total test time.
        -- REASON: lot of garbage will be accumulated otherwise, database "useful size" grows too slowly.
        a_included_kinds = 'creation,state_next,service'; -- 'service' --> we can NOT skip srv_make_invnt_saldo and srv_make_money_saldo !
        a_excluded_kinds = 'removal';
    end

    select coalesce(s.dts, cast('YESTERDAY' as timestamp))
    from rdb$database
    left join semaphores s on 1=1
    where s.task = 'srv_recalc_idx_stat'
    into v_last_recalc_idx_timestamp;

    -- Value of 'v_last_recalc_idx_minutes_ago'  will be compared with minimal
    -- threshold for recalc index statistics: fn_internal_reind_min_interval():
    v_last_recalc_idx_minutes_ago = datediff( minute from v_last_recalc_idx_timestamp to cast('now' as timestamp) );

    r_max = rdb$get_context('USER_SESSION', 'BOP_RND_MAX');
    if ( r_max is null ) then
    begin
        select max( o.random_selection_weight )
        from business_ops o
        -- unit that does recalculation of index statistics
        -- will be taken in account separately, by comparing
        -- v_last_recalc_idx_minutes_ago and fn_internal_reind_min_interval()
        -- ==> we have to EXCLUDE it from this recordset:
        where o.unit <> :c_unit_for_recalc_idx_stat
        into r_max;
        rdb$set_context('USER_SESSION', 'BOP_RND_MAX', r_max);
    end

    r = rand() * r_max;
    delete from tmp$perf_log p where p.stack = :v_this;

    -- 12.01.2019. We add into tmp$ table for choosing:
    -- 1) all except unit that recalculates index statistics';
    -- 2) unit that does idx recalc - BUT ONLY if enough number of minutes passed since it previous launch
    --    (i.e. value of business_ops.random_selection_weight N/A for this unit!)
    insert into tmp$perf_log(unit, aux1, aux2, stack)
    select o.unit, o.sort_prior, o.random_selection_weight, :v_this
    from business_ops o
    where o.random_selection_weight >= :r
        and o.unit <> :c_unit_for_recalc_idx_stat
        and ( fn_internal_enable_mon_query() = 1 or o.unit <> :c_unit_for_gather_mon_data ) -- do NOT choose srv_fill_mon if mon query disabled
        and ( :a_included_modes = '' or :a_included_modes||',' containing trim(o.mode)||',' )
        and ( :a_included_kinds = '' or :a_included_kinds||',' containing trim(o.kind)||',' )
        and ( :a_excluded_modes = '' or :a_excluded_modes||',' NOT containing trim(o.mode)||',' )
        and ( :a_excluded_kinds = '' or :a_excluded_kinds||',' NOT containing trim(o.kind)||',' )
    UNION ALL
    select o.unit, o.sort_prior, o.random_selection_weight, :v_this
    from business_ops o
    where :v_last_recalc_idx_minutes_ago >= fn_internal_reind_min_interval() and o.unit = :c_unit_for_recalc_idx_stat
    ;

    c = maxvalue(row_count, 1); -- 12.01.2019, mistic! can not understand but somehow row_count can be ZERO here!
    n = cast( 0.5+rand()*(c+0.5) as int );
    n = minvalue(maxvalue(1, n),c);

    select p.unit, p.aux1, p.aux2
    from tmp$perf_log p
    where p.aux2 >= :r
    order by rand()
    rows :n to :n -- get SINGLE row!
    into unit, sort_prior, rnd_weight;

    delete from tmp$perf_log p where p.stack = :v_this; -- 18.08.2014! cleanup this temply created data!

    suspend;

end

^ -- srv_random_unit_choice

---------------------------------------------------------------------------
-- needed for sys_get_proc_ddl, sys_get_func_ddl, sys_get_trig_ddl
create or alter procedure sys_list_to_rows (
    a_lst blob sub_type 1 segment size 80,
    a_del char(1) = ',')
returns (
    line integer,
    eof integer,
    item varchar(8192))
as begin
   -- ########################################
   -- STUB! Actual code see in oltp_common.sql
   -- ########################################
   suspend;
end

^ -- sys_list_to_rows // STUB

---------------------------------------------------------------------------

create or alter procedure sys_get_func_ddl (
    a_func varchar(31),
    a_mode smallint = 1,
    a_include_setterm smallint = 1)
returns (
    src varchar(32760))
as
begin
    -- NB! this SP is called from 'oltp_adjust_eds_calls.sql'
    if ( a_func is null or
         not singular(select * from rdb$functions p where upper(p.rdb$function_name) = upper(:a_func))
       ) then
    begin
        src = '-- invalid input argument a_func = ' || coalesce('"'||trim(a_func)||'"', '<null>');
        suspend;
        exception ex_bad_argument
        -- uncomment temply for 3.0+ if need
        -- using( coalesce('"'||trim(a_func)||'"', '<null>'), 'sys_get_func_ddl' )
        ;
    end

    for
        -- Extracts metadata of STANDALONE FUNCTION to be executed as statements in isql.
        -- Samples:
        -- select src from sys_get_func_ddl('fn_some_name', 0) -- output all procs with EMPTY body (preparing to update)
        -- select src from sys_get_func_ddl('fn_some_name', 1) -- output all procs with ODIGIN body (finalizing update)
        with
        inp as (
            select
               -- 1 as mode
               --,1 as add_set_term
               :a_mode mode -- -1=only func_name + parameters + 'AS', 0 = func_name + parameters + 'AS' + empty body, 1=full text
               ,:a_include_setterm add_set_term -- 1 => include `set term ^;` clause
               ,:a_func as a_func
            from rdb$database
        
        )
        ,s as (
            select
                m.mon$sql_dialect db_dialect
                ,d.mode
                ,d.add_set_term
                ,r.rdb$character_set_name db_default_cset
                ,p.rdb$deterministic_flag as determ
                ,p.rdb$function_name fn_name
                ,ascii_char(10) d
                ,replace(cast(p.rdb$function_source as blob sub_type 1), ascii_char(13), '') p_src
                ,(
                    select
                        coalesce(sum(iif(fa.rdb$argument_position > 0,1,0))*1000 + sum(iif(fa.rdb$argument_position = 0, 1, 0)),0)
                    from rdb$function_arguments fa
                    where fa.rdb$function_name = p.rdb$function_name
                ) pq -- cast(pq/1000 as int) = qty of IN-args, mod(pq,1000) = qty of OUT args
            from mon$database m -- put it FIRST in the list of sources!
            join rdb$database r on 1=1
            join inp d on 1=1
            join rdb$functions p on upper(p.rdb$function_name) = upper(d.a_func)
        )
        --select * from s
        
        ,r as(
            select
                db_dialect
                ,mode
                ,add_set_term
                ,db_default_cset
                ,determ
                ,fn_name
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
        
        ,p as (
                    select
                        r.db_dialect
                        ,r.mode
                        ,r.add_set_term
                        ,r.db_default_cset
                        ,r.determ
                        ,r.fn_name
                        ,r.i
                        ,r.word
                        ,r.pq_in
                        ,r.pq_ou
                        ,x.pt -- ip=0, op=1
                        ,fa.rdb$field_source ppar_fld_src
                        ,iif( fa.rdb$argument_position = 0, '<result>', fa.rdb$argument_name) par_name
                        ,fa.rdb$argument_position par_num -- output arg has NULL in rdb$func_args.rdb$arg_pos
                        ,1-sign(fa.rdb$argument_position) par_ty -- 0=in, 1=>out
                        ,fa.rdb$null_flag p_not_null -- 1==> not null
                        ,fa.rdb$argument_mechanism ppar_mechan -- 1=type of (table.column, domain, other...)
                        ,fa.rdb$relation_name ppar_rel_name
                        ,fa.rdb$field_name par_fld
                        --/*
                        ,case f.rdb$field_type
                            when 7 then 'smallint'
                            when 8 then
                                case f.rdb$field_scale
                                    when 0 then 'integer'
                                    else iif( f.rdb$field_sub_type = 1, 'numeric', 'decimal' ) || '(' || f.rdb$field_precision || ',' || cast(-f.rdb$field_scale as varchar(2)) || ')'
                                end
                            when 10 then 'float'
                            when 14 then 'char(' || cast(cast(f.rdb$field_length / ce.rdb$bytes_per_character as int) as varchar(5)) || ')'
                            when 16 then -- dialect 3 only
                                case f.rdb$field_sub_type
                                    when 0 then 'bigint'
                                    else iif( f.rdb$field_sub_type = 1, 'numeric', 'decimal' ) || '(' || f.rdb$field_precision || ',' || cast(-f.rdb$field_scale as varchar(2)) || ')'
                                    -- when 1 then 'numeric(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                                    --when 2 then 'decimal(15,' || cast(-f.rdb$field_scale as varchar(6)) || ')'
                                    --else 'unknown'
                                end
                            when 12 then 'date'
                            when 13 then 'time'
                            when 23 then 'boolean' -- FB 3.x+
                            when 24 then 'decfloat(16)' -- FB 4.x+
                            when 25 then 'decfloat(24)' -- FB 4.x+
                            when 26 then 'int128' -- FB 4.x+
                            when 27 then -- dialect 1 only
                                case f.rdb$field_scale
                                    when 0 then 'double precision'
                                    else 'numeric(15,' || cast( minvalue(15,abs(f.rdb$field_scale)) as varchar(6)) || ')'
                                end
                            when 28 then 'time with time zone' -- FB 4.x+
                            when 29 then 'timestamp with time zone' -- FB 4.x+
                            when 35 then iif(db_dialect=1, 'date', 'timestamp')
                            when 37 then 'varchar(' || cast(cast(f.rdb$field_length / ce.rdb$bytes_per_character as int) as varchar(5)) || ')'
                            when 261 then 'blob sub_type ' || f.rdb$field_sub_type || ' segment size ' || f.rdb$segment_length
                            else '<unknown datatype>'
                        end
                        as fddl
                        ,f.rdb$character_set_id fld_source_cset_id
                        ,f.rdb$collation_id fld_coll_id
                        ,ce.rdb$character_set_name fld_src_cset_name
                        ,co.rdb$collation_name fld_collation
                        ,cast(f.rdb$default_source as varchar(1024)) fld_default_src
                        ,cast(fa.rdb$default_source as varchar(1024)) ppar_default_src   -- ppar_default_src
                        --*/
                        ,r.k -- k=-1 ==> last line of sp
                    from r
                    join (
                        select -2 pt from rdb$database -- 'set term ^;'
                        union all select -1 from rdb$database -- header stmt: 'create or alter function ...('
                        union all select  0 from rdb$database -- input pars
                        union all select  5 from rdb$database -- 'returns ('
                        union all select 10 from rdb$database -- output pars
                        union all select 15 from rdb$database -- deterministic flag
                        union all select 20 from rdb$database -- 'as'
                        union all select 50 from rdb$database -- source code
                        union all select 100 from rdb$database -- '^set term ;^'
                    ) x on
                        -- `i`=line of body, 0='begin'
                        r.i = 0 and x.pt = -1 -- header
                        or r.i =0 and x.pt = 0 and pq_in > 0 -- input args, if exists
                        or r.i =0 and x.pt in(5,10) and pq_ou > 0 -- output args, if exists ('returns(' line)
                        or r.i =0 and x.pt = 15 and r.determ = 1 -- 'deterministic'
                        or r.i =0 and x.pt = 20 -- 'AS'
                        or x.pt = 50
                        or r.i = 0 and x.pt in(-2, 100) and r.add_set_term = 1 -- 'set term ^;', final '^set term ;^'
                    left join rdb$function_arguments fa on
                        r.fn_name = fa.rdb$function_name
                        and (x.pt = 0 and fa.rdb$argument_position > 0 or x.pt = 10 and fa.rdb$argument_position = 0)
                    --/*
                    left join rdb$fields f on
                        fa.rdb$field_source = f.rdb$field_name
                    left join rdb$collations co on
                        f.rdb$character_set_id = co.rdb$character_set_id
                        and f.rdb$collation_id = co.rdb$collation_id
                    left join rdb$character_sets ce on
                        co.rdb$character_set_id = ce.rdb$character_set_id
                    --*/
        )
        --select * from p

        ,fin as(
            select
                db_dialect
                ,mode
                ,add_set_term
                ,db_default_cset
                ,fn_name
                ,i
                ,par_num
                ,case
                 when pt=-2 then 'set term ^;'
                 when pt=100 then '^set term ;^'
                 when pt=-1 then 'create or alter function ' || trim(fn_name) || trim(iif(pq_in>0,' (',''))
                 when pt=5 then 'returns '
                 when pt=15 then 'deterministic'
                 when pt=20 then 'AS'
                 when pt in(0,10) then --in or out argument definition
                     '    '
                     || trim( iif( par_name='<result>', '', par_name ) )||' '
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
                     || iif(pt=10, '', iif( pt=0 and par_num=pq_in, ')', ',' ) )
                  -- dis 20.11.2020; dont remember why: when k=-1 coalesce(nullif(word,'')||';','') -- nb: some sp can finish with empty line!
                  else word
                end word
                ,pt
                ,ppar_fld_src
                ,par_name
                ,par_ty
                ,pq_in
                ,pq_ou
                --/*
                ,p.fddl
                ,p.fld_src_cset_name
                ,p.fld_collation
                --*/
                ,k
                --,'#'l,f.*
            from p
            left join rdb$fields f on p.ppar_fld_src = f.rdb$field_name
        )
        --select * from fin order by pt,par_num,i
        
        select --mode,p_nam,
            cast(
                case
                    when mode<=0 then
                        -- mode: -1=only func_name + parameters + 'AS';
                        --        0 = func_name + parameters + 'AS' + empty body
                        case when pt <50 /*is not null*/ then word
                            when pt in(-2, 100) and add_set_term = 1 then word
                            when mode = 0 and i = 0 and pt < 100 then 'begin'||iif(k = -1, ' end','')
                            when mode = 0 and k = -1 then 'end' -- last line of body
                        end
                    else
                         word
                end
                as varchar(8192)
            ) -- blob can incorrectly displays (?)
            as src
        --,f.* -- do not! implementation exceeded
        --,i,pt
        from fin f
        where
            mode=-1 and pt< 50
            or mode = 0 and (i=0 or k=-1)
            or mode = 1
        order by pt,par_num,i

        into src
    do
        suspend;

end 

^ -- sys_get_func_ddl

------------------------------------------------------------------------------
create or alter procedure sys_get_trig_ddl (
    a_trg_name varchar(31),
    a_mode smallint = 1,
    a_include_setterm smallint = 1)
returns ( src varchar(32760) )
as
begin
    for
        with
        inp as(
            select
            :a_trg_name trg_name
            from rdb$database
        )
        ,t as(
          select
                rt.rdb$trigger_name tg_nam
                ,iif(rt.rdb$relation_name is null, 1, null) db_level
                ,rt.rdb$relation_name rel_nm
                ,rt.rdb$trigger_type tg_ty -- (1,3,5)=(before ins,upd,del); (2,4,6)=(after ins,upd,del)
                ,rt.rdb$trigger_inactive tg_ina
                ,rt.rdb$trigger_sequence tg_pos
                ,ascii_char(10) d
                --,replace(rt.rdb$trigger_source, ascii_char(13), '') tg_src
                ,replace(cast(rt.rdb$trigger_source as blob sub_type 1), ascii_char(13), '') tg_src
          from rdb$triggers rt
          join inp i on 1=1
          where coalesce(rt.rdb$system_flag,0) = 0 and rt.rdb$trigger_name = upper(i.trg_name)
        )
        --select * from t

        ,s as(
            select 
                 tg_nam
                ,rel_nm
                ,tg_ty
                ,tg_ina
                ,tg_pos
                ,d
                ,trim(iif(tg_ina=1,'inactive','active'))
                    ||' '
                    ||trim(decode(tg_ty
                                    ,1, 'before insert'
                                    ,3, 'before update'
                                    ,5, 'before delete'
                                    ,2, 'after insert'
                                    ,4, 'after update'
                                    ,6, 'after delete'
                                    ,17,'before insert or update'
                                    ,25,'before insert or delete'
                                    ,27,'before update or delete'
                                    ,18,'after insert or update'
                                    ,26,'after insert or delete'
                                    ,28,'after update or delete'
                                    ,113,'before insert or update or delete'
                                    ,114,'after insert or update or delete'
                                    ,8195,'on transaction commit'
                                    ,8196,'on transaction rollback'
                                    ,8194,'on transaction start'
                                    ,8193,'on disconnect'
                                    ,8192,'on connect'
                                 )
                        )
                    ||' position '||tg_pos
                 as expr
                ,tg_src
            from t
        )
        -- select * from s

        ,r as(
            select
                 tg_nam
                ,rel_nm
                ,p.line i
                ,p.item as word
                ,expr
                ,p.eof
            from s
            left join sys_list_to_rows(tg_src, d) p on 1=1
        )
        --  select * from r; --

        ,tfin as(
            select 
                 r.tg_nam
                ,decode(
                    n.kx
                    ,-2,  'set term ^;'
                    ,-1,  'create or alter trigger '||trim(r.tg_nam)||coalesce(' for '||r.rel_nm, '')
                    ,0,   r.expr
                    ,1,   r.word
                    ,2,    'as'
                    ,3,   iif(r.eof=-1,'^ set term ;^','')
                ) txt
                ,kx
                ,r.i
            from r
            join (
                  select -2 kx from rdb$database where :a_include_setterm = 1  -- /* set term ^; */
                  union all select -1 from rdb$database   -- create or alter trigger
                  union all select 0 from rdb$database    -- (in)active before/after ... position ...
                  union all select 1 from rdb$database where :a_mode = 1   -- body
                  union all select 2 from rdb$database where :a_mode <> 1 -- 'as'
                  union all select 3 from rdb$database where :a_include_setterm = 1 -- ^  or set term ;^
                 ) n
            on
              (
                     r.i=0 and n.kx < 3
                  or r.i>0 and n.kx=1
                  or r.eof=-1 and n.kx=3
              )
            --- DO NOT: where word>''
            order by tg_nam,n.kx,r.i
        )
        select txt
        from tfin f
        into src
    do
        suspend;
end

^ -- sys_get_trig_ddl

--------------------------------------------------------------------------------

create or alter procedure srv_drop_oltp_worker as
begin

    -- 17.05.2020, needed only in FB 3.x+.
    -- Drop all temporary users which could be created before when mon_unit_perf = 1
    -- for reducing affect of gathering mon$ data before and after every business action.
    -- Then drop temporary role.
    -- ::: NB::: TAG '#OLTP_EMUL#'IS USED HERE FOR SEARCH AND DROP OLD TEMPORARY USERS/ROLE.
    -- See also sp srv_gen_sql_make_oltp_worker
    for
            select trim(s.sec$user_name) as usr_name
            from sec$users s
            where
                upper(trim(s.sec$user_name)) != upper('sysdba')
                and s.sec$description containing '#oltp_emul#'
            as cursor c
    do begin
            begin
                execute statement 'drop user ' || c.usr_name;
            when any do
                begin
                    -- nop --
                end
            end
    end

    -- ::: NB::: TAG '#OLTP_EMUL#'IS USED HERE FOR SEARCH AND DROP OLD TEMPORARY USERS/ROLE.
    -- See also sp srv_gen_sql_make_oltp_worker
    for
        select trim(r.rdb$role_name) as role_name
        from rdb$roles r
        where
            upper(r.rdb$role_name) != upper('rdb$admin')
            and r.rdb$description containing '#oltp_emul#'
        as cursor c
    do  begin
        begin
            execute statement 'drop role ' || c.role_name;
        when any do
            begin
                -- nop --
            end
        end
    end
end

^ -- srv_drop_oltp_worker

set term ;^
set list on;
set echo off;
select 'oltp30_DDL.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

-- ###########################################################
-- End of script oltp30_DDL.sql; next to be run: oltp30_SP.sql
-- ########################################################### 
