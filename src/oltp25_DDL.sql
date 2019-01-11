-- 1) run oltp25_DDL.sql
-- 2) run oltp25_sp.sql
-- 3) run oltp_main_filling.sql 
-- 4) run oltp_data_filling.sql
-- ##############################
-- Begin of script oltp25_DDL.sql
-- ##############################
-- ::: nb-1 ::: Required FB version: 2.5 only.
-- ::: nb-2 ::: Use '-nod' switch when run this script from isql
-- Pattern for search queries to [v_]qdistr using regexp (in IBE):
-- (from|((left(( ){1,}outer( ){1,})|full(( ){1,}outer( ){1,})|inner)( ){0,1}){0,1}join)( ){1,}(v_){0,1}qdistr

set bail on;
set autoddl off;
set list on;
select 'oltp25_DDL.sql start at ' || current_timestamp as msg from rdb$database;
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
    execute statement 'recreate exception ex_not_suitable_fb_version ''This script can be run only in Firebird 2.5''';
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
    if (  engine_version NOT starting with '2.5' ) then
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
      select rf.rdb$relation_name view_name, rf.rdb$field_position fld_pos, rf.rdb$field_name fld_name
      from rdb$relation_fields rf
      join rdb$relations rr
      on rf.rdb$relation_name=rr.rdb$relation_name
      where
      coalesce(rf.rdb$system_flag,0)=0 and coalesce(rr.rdb$system_flag,0)=0 and rr.rdb$relation_type=1
    )
    select view_name,
           cast( 'create or alter view '||trim(view_name)||' as select '
                 ||list( fld_pos||' '||trim(lower(fld_name)) )
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

  -- #########    Z A P     P R O C S  ##########

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
--exit;

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
-- NB, 09-mar-2016: at least on 2.5.3 attempt to create two collations w/o commit lead to:
-- -DEFINE COLLATION failed
-- -attempt to store duplicate value (visible to active transactions) in unique index "RDB$INDEX_26"
-- -Problematic key value is ("RDB$COLLATION_ID" = NULL, "RDB$CHARACTER_SET_ID" = 4)
-- Found on WI-V2.5.3.26780, official release.
create collation name_coll for utf8 from unicode case insensitive;
commit; -- mandatory for versions <=2.5.3!
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
recreate exception ex_can_not_select_random_id 'no id>=@1 in @2 found within scope @3 ... @4';

recreate exception ex_snapshot_isolation_required 'operation must run only in TIL = SNAPSHOT.';
recreate exception ex_read_committed_isolation_req 'operation must run only in TIL = READ COMMITTED.';
recreate exception ex_nowait_or_timeout_required 'transaction must start in NO WAIT mode or with LOCK_TIMEOUT.';

recreate exception ex_update_operation_forbidden 'update operation not allowed on table @1';
recreate exception ex_delete_operation_forbidden 'delete operation not allowed on table @1 when user-data exists';
recreate exception ex_debug_forbidden_operation 'debug: operation not allowed';
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
commit;

-------------------------------------------------------------------------------
--  **************   G L O B A L    T E M P.    T A B L E S   *****************
-------------------------------------------------------------------------------
recreate global temporary table tmp$shopping_cart(
   id dm_idb, --  = ware_id
   snd_id bigint, -- nullable! ref to invoice in case when create reserve doc (one invoice for each reserve; 03.06.2014)
   qty numeric(12,3) not null,
   optype_id bigint,
   snd_optype_id bigint,
   rcv_optype_id bigint,
   storno_sub smallint default 1, -- see table rules_for_qistr.storno_sub
   qty_bak numeric(12,3) default 0, -- debug
   dup_cnt int default 0,  -- debug
   cost_purchase dm_cost, -- for sp_sp_fill_shopping_cart when create client order
   cost_retail dm_cost,
   constraint tmp_shopcart_unq unique(id, snd_id) using index tmp_shopcart_unq
) on commit delete rows;
commit;
-- 08.01.2015, see sp make_qty_storno, investigatin perf. for NL vs MERGE
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
-- This table actually is NOT used in FB 2.5 (new counters avaliable only in 3.0):
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
) on commit preserve rows;
commit;

-- 29.08.2014: for identifying troubles by analyzing results per each table:
recreate global temporary table tmp$mon_log_table_stats( -- used in tmp_random_run.sql
    unit dm_unit
   ,fb_gdscode int
   ,att_id bigint default current_connection
   ,trn_id bigint
   ,table_id smallint
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

-- Used only when config parameter create_with_split_heavy_tabs = 1:
-- stores INITIAL source code of sp_get_random_id as basis for generation
-- of new DB object with this name which almost fully excludes running of
-- dynamic SQL statements for getting random selection of IDs:
recreate global temporary table tmp$autogen$source(
    line_no int,
    text varchar(8190),
    line_type varchar(10)
) on commit delete rows;

-- Used only when config parameter create_with_split_heavy_tabs = 1: library of known
-- views which names should be written explicitly in new sp_get_random_id code:
recreate global temporary table tmp$autogen$rand$calls(
    view_name_for_find varchar(31)
    ,view_name_for_min_id varchar(31)
    ,view_name_for_max_id varchar(31)
) on commit delete rows;
commit;


------------------------------------------------------------------------------
--  ************   D E B U G   T A B L E S (can be taken out after)  *********
------------------------------------------------------------------------------
-- moved out, see oltp_misc_debug.sql
-- (this script will be involved only when config parameter create_with_debug_objects = 1)

-------------------------------------------------------------------------------
--  ****************   A P P L I C A T I O N    T A B L E S   *****************
-------------------------------------------------------------------------------
-- Some values which are constant during app work, definitions for worload modes:
-- Values from 'svalue' field will be stored in session-level CONTEXT variables
-- with names defined in field 'mcode' ('C_CUSTOMER_DOC_MAX_ROWS' etc):
recreate table settings(
  working_mode varchar(20) character set utf8,
  mcode dm_name, -- mnemonic code
  context varchar(16) default 'USER_SESSION',
  svalue dm_setting_value,
  init_on varchar(20) default 'connect', -- read this value in context var in trg_connect; 'db_prepare' ==> not needed in runtime
  description dm_info,
  constraint settings_unq unique(working_mode, mcode) using index settings_mode_code,
  constraint settings_valid_ctype check(context in(null,'USER_SESSION','USER_TRANSACTION'))
);
commit;

-- lookup table: types of operations (create before doc_list!):
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
   -- sequential number of ISQL session that created with this document.
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
   ,doc_id dm_idb
   ,agent_id dm_idb
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
   id dm_idb constraint pk_wares primary key using index pk_wares
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
   id dm_idb constraint pk_phrases primary key using index pk_phrases
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
    id dm_idb constraint pk_invnt_saldo primary key using index pk_invnt_saldo
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
    id dm_idb constraint pk_pdistr primary key using index pk_pdistr
    ,agent_id dm_idb
    ,snd_optype_id dm_ids -- denorm for speed
    ,snd_id dm_idb -- ==> doc_list.id of "sender"
    ,worker_id dm_ids -- 12.08.2018
    ,snd_cost dm_qty
    ,rcv_optype_id dm_ids
    ,trn_id bigint default current_transaction
    ,constraint pdistr_snd_op_diff_rcv_op check( snd_optype_id is distinct from rcv_optype_id )
);

-- disabled here 05.10.2018, see 'oltp_adjust_DDL.sql':
-- key must be either (worker_id,snd_id) or (snd_id): create index pdistr_snd_id on pdistr(snd_id); -- for fast seek when emul cascade deleting in s`p_kill_cost_storno
-- 09.09.2014: attempt to speed-up random choise of non-paid realizations and invoices
-- plus reduce number of doc_list IRs (see v_r`andom_find_non_paid_*, v_min_non_paid_*, v_max_non_paid_*)
create index pdistr_sndop_rcvop_sndid_asc on pdistr (snd_optype_id, rcv_optype_id, snd_id); -- see plan in V_MIN_NON_PAID_xxx
create descending index pdistr_sndop_rcvop_sndid_desc on pdistr (snd_optype_id, rcv_optype_id, snd_id); -- see plan in V_MAX_NON_PAID_xxx
create index pdistr_agent_id on pdistr(agent_id); -- confirmed, 16.09.2014: see s`p_make_cost_storno

-- 27.08.2018 do NOT put here this, instead inject actual value of config parameter 'separate_workers' in main batch when build DB: 
-- index pdistr_worker_id on pdistr(worker_id); -- 12.08.2018
commit;

-- Storage for records which are removed from Pdistr when they are 'storned'
-- (will returns back into Pdistr when cancel operation - see sp_k`ill_cost_storno):
recreate table pstorned(
    -- ::: nb ::: PK on this table will be REMOVED at the end of script 'oltp_main_filling.sql'
    -- if setting 'HALT_TEST_ON_ERRORS' does not contain '/PK/'
    id dm_idb constraint pk_pstorned primary key using index pk_pstorned
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

-- disabled here 05.10.2018, see 'oltp_adjust_DDL.sql': index pstorned_worker_id on pstorned(worker_id); -- 12.08.2018
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
   id dm_idb constraint pk_agents primary key using index pk_agents
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
    ,constraint semaphores_task_unq unique(task) using index semaphores_task_unq
);
commit;

-- Log for all changes in doc_data.qty (including DELETION of rows from doc_data).
-- Only INSERTION is allowed to this table for 'common' business operations.
-- Fields qty_diff & cost_diff can be NEGATIVE when document is removed ('cancelled')
-- Aggregating and deleting rows from this table - see s`rv_make_invnt_saldo
recreate table invnt_turnover_log(
    ware_id dm_idb
   ,qty_diff numeric(12,3)  -- can be < 0 when cancelling document
   ,cost_diff numeric(12,2) -- can be < 0 when cancelling document
   ,doc_list_id bigint
   ,doc_pref dm_mcode
   ,doc_data_id bigint
   ,optype_id dm_ids
   ,id dm_idb not null
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

-- standard Firebird error list with descriptions:
recreate table fb_errors(
   fb_sqlcode int,
   fb_gdscode int,
   fb_mnemona varchar(31),
   fb_errtext varchar(100),
   constraint fb_errors_gds_code_unq unique(fb_gdscode) using index fb_errors_gds_code
);

-- 28.10.2015: source for view z_estimated_perf_per_minute, see oltp_isql_run_worker.bat (.sh):
-- data of estimated overall performance value with detalization to one minute, useful for
-- finding proper value of config parameter 'warm_time'. Values in the field SUCCESS_COUNT are
-- result of total count of business ops that SUCCESSFUL finished, see auto-generated script
-- $tmpdir/tmp_random_run.sql:
-- v_success_ops_increment = cast(rdb$get_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT') as int);
-- result = gen_id( g_success_counter, v_success_ops_increment );
-- Context variable 'BUSINESS_OPS_CNT' is incremented by 1 on every invokation of each unit
-- that implements BUSINESS action: client order, order to supplier, etc, -- see table business_ops
recreate table perf_estimated(
    minute_since_test_start int,
    success_count numeric(12,2),
    att_id int default current_connection,
    dts timestamp default 'now'
);
create index perf_est_minute_since_start on perf_estimated (minute_since_test_start);
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

-- Log for performance and errors (filled via autonom. tx if exc`eptions occur)
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
-- finally dis 09.01.2015, not needed for this table: create index perf_log_id on perf_log(id);
-- finally dis 13.10.2018, huge fetches when do query for 'perfwatch_interval' and get last record among extracted rows: create descending index perf_log_dts_beg_desc on perf_log(dts_beg);
create descending index perf_log_unit on perf_log(unit, elapsed_ms);
-- 4 some analysis, added 25.06.2014:
-- dis 20.08.2014: create index perf_log_att on perf_log(att_id);
-- dis 13.10.2018 (seems that SP srv_mon_idx is not called from anywhere): create descending index perf_log_trn_desc on perf_log(trn_id); --  descending - for fast access to last actions, e.g. of srv_mon_idx
-- 20.08.2014:
create index perf_log_gdscode on perf_log(fb_gdscode);

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

-- introduced 09.08.2014, for checking mon$-tables stability: gather stats
-- Also used when context 'MON_UNIT_LIST' is not empty (see s`p_add_to_perf_log).
-- see mail: SF.net SVN: firebird:[59967] firebird/trunk/src/jrd
-- (dimitr: Better (methinks) synchronization for the monitoring stuff)
recreate table mon_log(
    unit dm_unit
   ,fb_gdscode int
   ,elapsed_ms int -- added 08.09.2014
   ,trn_id bigint
   ,add_info dm_info
   --------------------
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
   -- optimal values for (letter by dimitr 27.08.2014 21:30):
   -- bkv_per_rec_reads = 1.0...1.2
   -- frg_per_rec_reads = 0.01...0.1 (better < 0.01), depending on record width; increase page size if high value
   ,bkv_per_seq_idx_rpt computed by ( 1.00 * bkv_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,frg_per_seq_idx_rpt computed by ( 1.00 * frg_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,rec_locks bigint
   ,rec_waits bigint
   ,rec_confl bigint
   -----------------------------------------------------------------------------
   ,pg_reads bigint
   ,pg_writes bigint
   ,pg_fetches bigint
   ,pg_marks bigint
   ,mem_used bigint
   ,mem_alloc bigint
   ,server_pid bigint
   ,remote_pid bigint
   ,stat_id bigint
   ,dump_trn bigint default current_transaction
   ,ip dm_ip
   ,usr dm_dbobj
   ,remote_process dm_info
   ,rowset bigint -- for grouping records that related to the same measurement
   ,att_id bigint
   ,id dm_idb constraint pk_mon_log primary key using index pk_mon_log
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
   ,rec_inserts bigint
   ,rec_updates bigint
   ,rec_deletes bigint
   ,rec_backouts bigint
   ,rec_purges bigint
   ,rec_expunges bigint
   ,rec_seq_reads bigint
   ,rec_idx_reads bigint
   --------------------
   ,rec_rpt_reads bigint
   ,bkv_reads bigint
   ,frg_reads bigint
   ,bkv_per_seq_idx_rpt computed by ( 1.00 * bkv_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,frg_per_seq_idx_rpt computed by ( 1.00 * frg_reads / nullif((rec_seq_reads + rec_idx_reads + rec_rpt_reads),0) )
   ,rec_locks bigint
   ,rec_waits bigint
   ,rec_confl bigint
   ,stat_id bigint
   ,rowset bigint -- for grouping records that related to the same measurement
   ,table_id smallint
   ,is_system_table smallint
   ,rel_type smallint
   ,att_id bigint default current_connection
   ,id dm_idb constraint pk_mon_log_table_stats primary key using index pk_mon_log_table_stats
   ,dts timestamp default 'now'
);
create descending index mon_log_table_stats_rowset on mon_log_table_stats(rowset);
create index mon_log_table_stats_gdscode on mon_log_table_stats(fb_gdscode);
create index mon_log_table_stats_tn_unit on mon_log_table_stats(table_name, unit);
create index mon_log_table_stats_dts on mon_log_table_stats(dts); -- 26.09.2015, for SP srv_mon_stat_per_tables
commit;

-- 16.12.2018
recreate table mon_memory_consumption(
    stat_type varchar(20)
    ,sys_memo_used bigint
    ,usr_memo_used bigint
    ,active_attachments_cnt smallint
    ,active_transactions_cnt smallint
    ,running_statements_cnt int
    ,stalled_statements_cnt int
    ,rowset bigint -- for grouping records that related to the same measurement
    ,id dm_idb
    ,dts timestamp default 'now'
    --,sec int --  datediff(second from current_date-1 to current_timestamp ) sec
    --,add_info dm_info
    ,constraint pk_mon_memory_consumption primary key(id)
);

create descending index mon_memo_rowset_desc on mon_memory_consumption(rowset);
create index mon_memo_dts on mon_memory_consumption(dts);
commit;

--31.12.2018
recreate table mon_cache_memory (
    pg_buffers int
    ,pg_size int
    ,pg_cache_type varchar(10)
    ,page_cache_size bigint
    ,meta_cache_size bigint
    ,memo_used_att bigint
    ,memo_used_trn bigint
    ,memo_used_stm bigint
    ,total_attachments_cnt smallint
    ,active_attachments_cnt smallint
    ,page_cache_operating_stm_cnt smallint
    ,data_transfer_paused_stm_cnt smallint
    ,id dm_idb
    ,dts timestamp default 'now'
    ,elap_ms int -- duration of gathering mon$ info, milliseconds
    ,constraint pk_mon_cache_memory primary key(id)
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

-- dis 28.01.2015 0135, no need:
--alter table money_turnover_log
--   add constraint fk_money_turnover_log_agents foreign key (agent_id) references agents(id)
--;

commit;

-- 08.10.2018: view for inserting rows in SP_ADD_PERF_LOG,
-- its DDL can be replaced below with UNIONED query from several tables,
-- each of them will serve as storage for 'separate' set of rows.
-- Purpose: reduce low-level lock contention that occurs for perf_log table.
create or alter view v_perf_log as select * from perf_log
;
commit;

set term ^;

--------------------------------------------------------------------------------
-------    "S y s t e m"    f u n c s   &  s t o r e d     p r o c s   --------
--------------------------------------------------------------------------------

-- procedures instead of stored funcs (as in FB 3.x):

create or alter procedure fn_infinity returns (result bigint) as
begin
  result = 9223372036854775807;
  suspend;
end -- fn_infinity

^

create or alter procedure fn_is_lock_trouble(a_gdscode int) returns(result smallint)
as
begin
    -- lock_conflict, concurrent_transaction, deadlock, update_conflict
    result = iif( a_gdscode in (335544345, 335544878, 335544336,335544451 ), 1, 0);
    suspend;
end

^ -- fn_is_lock_trouble

create or alter procedure fn_is_validation_trouble(a_gdscode int) returns(result smallint)
as
begin
    -- 335544558    check_constraint    Operation violates CHECK constraint @1 on view or table @2.
    -- 335544347    not_valid    Validation error for column @1, value "@2".
    result = iif( a_gdscode in ( 335544347,335544558 ), 1, 0);
    suspend;
end

^ -- fn_is_validation_trouble

create or alter procedure fn_is_uniqueness_trouble(a_gdscode int) returns(result smallint)
as
begin
    --  if table has unique constraint: 335544665 unique_key_violation (violation of PRIMARY or UNIQUE KEY constraint "T1_XY" on table "T1")
    --  if table has only unique index: 335544349 no_dup (attempt to store duplicate value (visible to active transactions) in unique index "T2_XY")
    result = iif( a_gdscode in ( 335544665,335544349 ), 1, 0);
    suspend;
end

^ -- fn_is_validation_trouble

create or alter procedure fn_halt_sign(a_gdscode int) returns (result smallint)
as
    declare v_halt_on_severe_error dm_name;
begin
    result = 0;
    -- refactored 13.08.2014 - see setting 'HALT_TEST_ON_ERRORS' (oltp_main_filling.sql)
    v_halt_on_severe_error = rdb$get_context('USER_SESSION', 'HALT_TEST_ON_ERRORS');

    if ( a_gdscode  = 0 ) then result =1; -- 3.x SC & CS trouble, core-4565!

    -- 'arith_except' (Arithmetic exception, numeric overflow, or string truncation):
    -- all these errors must be fixed by increasing of field size or check source code.
    -- Particularly, string truncation of 'v_call' variable (when it was modified by
    -- debug code in sp_make_qty_storno and sp_kill_qstorno_ret_qs2qd) was actual reason
    -- of "performance regression" in 4.0 since 16-jul-2016: variable of unicode_fss type
    -- does not allow to fit more chars than declared len, even if all chars are ascii (1 byte).
    -- See also letter from hvlad 06-jan-2017 01:59
    if ( a_gdscode = 335544321 ) then result = 1;

    if ( result = 0 and v_halt_on_severe_error containing 'CK'  ) then
        result = iif( a_gdscode
                      in ( 335544347 -- not_valid    Validation error for column @1, value "@2".
                          ,335544558 -- check_constraint    Operation violates CHECK constraint @1 on view or table @2.
                         )
                     ,1
                     ,0
                    );
     if (result = 0 and v_halt_on_severe_error containing 'PK' ) then
         result = iif( a_gdscode
                       in ( 335544665 -- unique_key_violation (violation of PRIMARY or UNIQUE KEY constraint "T1_XY" on table "T1")
                           ,335544349 -- no_dup (attempt to store duplicate value (visible to active transactions) in unique index "T2_XY") - without UNQ constraint
                          )
                      ,1
                      ,0
                     );
     if (result = 0 and v_halt_on_severe_error containing 'FK' ) then
         result = iif( a_gdscode
                       in ( 335544466 -- violation of FOREIGN KEY constraint @1 on table @2
                           ,335544838 -- Foreign key reference target does not exist (when attempt to ins/upd in DETAIL table FK-field with value for which parent ID has been changed or deleted - even in uncommitted concurrent Tx)
                           ,335544839 -- Foreign key references are present for the record  (when attempt to upd/del in PARENT table PK-field and rows in DETAIL (no-cascaded!) exists for old value)
                          )
                      ,1
                      ,0
                     );

    if ( result = 0 and v_halt_on_severe_error containing 'ST'  ) then
        result = iif( a_gdscode = 335544842, 1, 0); -- trouble in 3.0 SC only: this error appears at the TOP of stack and this prevent following job f Tx

    suspend; -- 1 ==> force test to be stopped itself

end

^ -- fn_halt_sign

create or alter procedure fn_remote_process returns (result varchar(255)) as
begin
    result = rdb$get_context('SYSTEM', 'CLIENT_PROCESS');
    suspend;
end

^ -- fn_remote_process 

create or alter procedure fn_remote_address returns (result dm_ip) as
begin
    result = rdb$get_context('SYSTEM','CLIENT_ADDRESS');
    suspend;
end

^
-- NB: commit MUST be here for FB 2.5!
-- All even runs (2,4,6,...) of script containing procedures which references
-- to some SPs declared above them will faults if running is in the same connection
-- as previous one! See http://tracker.firebirdsql.org/browse/CORE-4490
set term ;^
commit;
set term ^;

create or alter --function fn_is_snapshot returns boolean deterministic as
procedure fn_is_snapshot returns (result smallint) as
begin
    result =
        iif(
            (select result from fn_remote_process) containing 'IBExpert'
            or
            rdb$get_context('SYSTEM','ISOLATION_LEVEL') is not distinct from upper('SNAPSHOT')
            , 1
            , 0
            );
    suspend;
end

^ -- fn_is_snapshot

create or alter procedure fn_doc_open_state returns (result int)
as
    declare v_key type of column doc_states.mcode = 'DOC_OPEN_STATE';
    declare v_stt varchar(255);
begin
    -- find id for documents state where any changes enabled:
    result=rdb$get_context('USER_SESSION', 'FN_DOC_OPEN_STATE');
    if (result is null) then begin
        v_stt='select s.id from doc_states s where s.mcode=:x';
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'DOC_STATES', v_key );
        end
        rdb$set_context('USER_SESSION', 'FN_DOC_OPEN_STATE', result);
    end
    
    suspend;
end

^  -- fn_doc_open_state

create or alter procedure fn_doc_fix_state  returns (result int)
as
    declare v_key type of column doc_states.mcode = 'DOC_FIX_STATE';
    declare v_stt varchar(255);
begin
    -- find id for documents state where no change except payment enabled:
    result=rdb$get_context('USER_SESSION', 'FN_DOC_FIX_STATE');
    if (result is null) then begin
        v_stt='select s.id from doc_states s where s.mcode=:x';
        --select s.id from doc_states s where s.mcode=:v_key into result;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'DOC_STATES', v_key );
        end
        rdb$set_context('USER_SESSION', 'FN_DOC_FIX_STATE', result);
    end

    suspend;

end

^ -- fn_doc_fix_state

create or alter procedure fn_doc_clos_state returns (result int)
as
    declare v_key type of column doc_states.mcode = 'DOC_CLOS_STATE';
    declare v_stt varchar(255);
begin
    -- find id for documents state where ALL changes  disabled:
    result=rdb$get_context('USER_SESSION', 'FN_DOC_CLOS_STATE');
    if (result is null) then begin
        v_stt='select s.id from doc_states s where s.mcode=:x';
        --select s.id from doc_states s where s.mcode=:v_key into result;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'DOC_STATES', v_key );
        end

        rdb$set_context('USER_SESSION', 'FN_DOC_CLOS_STATE', result);
    end
    
    suspend;
end

^  -- fn_doc_clos_state

create or alter procedure fn_doc_canc_state returns (result int)
as
    declare v_key type of column doc_states.mcode = 'DOC_CANC_STATE';
    declare v_stt varchar(255);
begin
    -- find id for documents state where ALL changes  disabled:
    result=rdb$get_context('USER_SESSION', 'FN_DOC_CANC_STATE');
    if (result is null) then begin
        v_stt='select s.id from doc_states s where s.mcode=:x';
        --select s.id from doc_states s where s.mcode=:v_key into result;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'DOC_STATES', v_key );
        end

        rdb$set_context('USER_SESSION', 'FN_DOC_CANC_STATE', result);
    end
    
    suspend;
end -- fn_doc_canc_state

^
------ stored functions for caching data from OPTYPES table: --------

create or alter procedure fn_oper_order_by_customer returns (result int) as
    declare v_key dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "client's order".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_ORDER_BY_CUSTOMER');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_qty_clo = :x and o.m_qty_clr = 0';
        v_key = 1;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', v_key );
        end
        rdb$set_context('USER_SESSION', 'FN_OPER_ORDER_BY_CUSTOMER', result);
    end

    suspend;

end -- fn_oper_order_by_customer

^

create or alter procedure fn_oper_cancel_customer_order returns (result int) as
    declare v_key dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "client's order".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_CANCEL_CUSTOMER_ORDER');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_qty_clr = :x';
        v_key = 1;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', v_key );
        end

        rdb$set_context('USER_SESSION', 'FN_OPER_CANCEL_CUSTOMER_ORDER', result);
    end

    suspend;

end -- fn_oper_cancel_customer_order

^

create or alter procedure fn_oper_order_for_supplier returns (result int) as
    declare v_key dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "add to stock order, sent to supplier".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_ORDER_FOR_SUPPLIER');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_qty_ord = :x';
        v_key = 1;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', v_key );
        end

        rdb$set_context('USER_SESSION', 'FN_OPER_ORDER_FOR_SUPPLIER', result);
    end

    suspend;

end -- fn_oper_order_for_supplier

^

create or alter procedure fn_oper_invoice_get  returns (result int) as
    declare v_key1 dm_sign;
    declare v_key2 dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "get invoice from supplier".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_INVOICE_GET');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_qty_ord=:x and o.m_qty_sup=:y';
        v_key1 = -1;
        v_key2 = 1;
        execute statement (v_stt) ( x := :v_key1, y := :v_key2 ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', 'm_qty_ord=-1 and m_qty_sup=1' );
        end

        rdb$set_context('USER_SESSION', 'FN_OPER_INVOICE_GET', result);
    end
    
    suspend;

end -- fn_oper_invoice_get

^

create or alter procedure fn_oper_invoice_add returns (result int) as
    declare v_key dm_sign;
    declare v_key1 dm_sign;
    declare v_key2 dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "invoice checked, add to avaliable remainders".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_INVOICE_ADD');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_qty_avl=:x'; -- 'o.m_qty_sup=:x and o.m_qty_avl=:y';
        --v_key1 = -1;
        --v_key2 = 1;
        v_key = 1;
        execute statement (v_stt)  ( x := :v_key ) into result; -- ( x := :v_key1, y := :v_key2 ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', 'm_qty_sup=-1 and m_qty_avl=1' );
        end

        rdb$set_context('USER_SESSION', 'FN_OPER_INVOICE_ADD', result);
    end
    
    suspend;

end -- fn_oper_invoice_add 

^

create or alter procedure fn_oper_retail_reserve returns (result int) as
    declare v_key1 dm_sign;
    declare v_key2 dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "retail selling - reserve for customer".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_RETAIL_RESERVE');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_qty_avl=:x and o.m_qty_res=:y';
        v_key1 = -1;
        v_key2 = 1;
        execute statement (v_stt) ( x := :v_key1, y := :v_key2 ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', 'm_qty_avl=-1 and m_qty_res=1' );
        end
        rdb$set_context('USER_SESSION', 'FN_OPER_RETAIL_RESERVE', result);
    end
    
    suspend;

end -- fn_oper_retail_reserve

^

create or alter procedure fn_oper_retail_realization returns (result int) as
    declare v_key1 dm_sign;
    declare v_key2 dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "retail selling - write-off (realization)".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_RETAIL_REALIZATION');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_qty_res=:x and o.m_cost_out=:y';
        v_key1 = -1;
        v_key2 = 1;
        execute statement (v_stt) ( x := :v_key1, y := :v_key2 ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', 'm_qty_res=-1 and m_cost_out=1' );
        end

        rdb$set_context('USER_SESSION', 'FN_OPER_RETAIL_REALIZATION', result);
    end

    suspend;

end -- fn_oper_retail_realization

^

create or alter procedure fn_oper_pay_to_supplier returns (result int) as
    declare v_key dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "incoming - we pay to supplier for wares".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_PAY_TO_SUPPLIER');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_supp_debt=:x';
        v_key = -1;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', 'm_qty_res=-1 and m_cost_out=1' );
        end

        rdb$set_context('USER_SESSION', 'FN_OPER_PAY_TO_SUPPLIER', result);
    end
    
    suspend;

end -- fn_oper_pay_to_supplier

^

create or alter procedure fn_oper_pay_from_customer returns (result int) as
    declare v_key dm_sign;
    declare v_stt varchar(255);
begin
    -- find id for operation "accept payment for sold wares (target transfer)".
    -- Raises exception if it can`t be found.
    result=rdb$get_context('USER_SESSION', 'FN_OPER_PAY_FROM_CUSTOMER');
    if (result is null) then begin
        v_stt = 'select o.id from optypes o where o.m_cust_debt=:x';
        v_key = -1;
        execute statement (v_stt) ( x := :v_key ) into result;
        if (result is null) then
        begin
            exception ex_record_not_found; -- using( 'OPTYPES', 'm_qty_res=-1 and m_cost_out=1' );
        end

        rdb$set_context('USER_SESSION', 'FN_OPER_PAY_FROM_CUSTOMER', result);
    end
    
    suspend;

end -- fn_oper_pay_from_customer

^

create or alter procedure fn_mcode_for_oper(a_oper_id dm_idb) returns (result dm_mcode)
as
begin
    -- returns mnemonic code for operation ('ORD' for stock order, et al)
    result = rdb$get_context('USER_SESSION','OPER_MCODE_'||:a_oper_id);
    if (result is null) then begin
        select o.mcode from optypes o where o.id = :a_oper_id into result;
        rdb$set_context('USER_SESSION','OPER_MCODE_'||:a_oper_id, result);
    end
    suspend;
end

^ -- fn_mcode_for_oper

create or alter procedure fn_make_predictable_workload returns(result smallint) as
begin
    result = iif( upper(rdb$get_context('USER_SESSION', 'UNIT_SELECTION_METHOD')) = upper('predictable'), 1, 0);
    suspend;
end
^

create or alter procedure fn_this_worker_seq_no returns (result smallint) as
begin
    if ( rdb$get_context('USER_SESSION', 'SEPARATE_WORKERS') = 0 ) then
        result = null;
    else
        result =
            coalesce(
               rdb$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER'), -- this is defined in oltp_isql_run_worker
               10000 + mod( current_connection, 100 ) -- this is for initial doc population, developer call from IBE etc
            );
    suspend;
end
^ -- fn_this_worker_seq_no

-- ::: NB ::: do __NOT__ change name of output arg!
-- It must be 'worker_id', see auto generated script 'tmp_random_run.sql':
-- ... rdb$set_context( 'USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER', (select worker_id from fn_other_rand_worker) )
create or alter procedure fn_other_rand_worker returns (
    worker_id smallint 
) as
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
        worker_id = null;
    else
        begin
            n_this = (select result from fn_this_worker_seq_no);
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

            worker_id = coalesce( n_rnd, n_this );

        end

   suspend; -- output: 'worker_id'; do NOT change its name!

end
^ -- fn_other_rand_worker

create or alter procedure fn_get_stack(
    a_halt_due_to_error smallint default 0
)
returns (result dm_stack)
as
    declare obj_name dm_dbobj; -- varchar(31); -- type of column m`on$call_stack.m`on$object_name;
    declare obj_type smallint; -- type of column m`on$call_stack.m`on$object_type;
    declare src_row int; -- type of column m`on$call_stack.m`on$source_line;
    declare src_col int; -- type of column m`on$call_stack.m`on$source_column;
    declare v_call_level int;
    declare v_line dm_stack;
    declare v_this dm_dbobj = 'fn_get_stack';
begin
    result='';
    -- 1. currently building of stack stack IGNORES procedures which are
    -- placed between top-level SP and 'this' unit. See:
    -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16422390
    -- (resolved, see: ChangeLog, issue "2014-08-12 10:21  hvlad")
    -- 2. mon$call_stack is UNAVALIABLE if some SP is called from trigger and
    -- this trigger, in turn, fires IMPLICITLY due to cascade FK.
    -- 13.08.2014: still UNRESOLVED. See:
    -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16438071
    -- 3. Deadlocks trouble when heavy usage of monitoring was resolved only
    --    in FB-3, approx. 09.08.2014, see letter to dimitr 11.08.2014 11:56
    if ( (select result from fn_remote_process) NOT containing 'IBExpert'
         and a_halt_due_to_error = 0
         and coalesce(rdb$get_context('USER_SESSION','ENABLE_MON_QUERY'),0) = 0
       ) then
       --####
       exit;
       --####

    for
        with recursive
        r as (
            select 1 call_level,
                 c.mon$statement_id,
                 c.mon$call_id,
                 c.mon$object_name,
                 c.mon$object_type,
                 c.mon$source_line,
                 c.mon$source_column
             -- NB, 13.08.2014: unavaliable record if SP is called from:
             -- 1) trigger which is fired by CASCADE
             -- 2) dyn SQL (ES)
             -- see:
             -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16438071
             -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16442098
            from mon$call_stack c
            where c.mon$caller_id is null
            union all
            select h.call_level+1,
                   c.mon$statement_id,
                   c.mon$call_id,
                   c.mon$object_name,
                   c.mon$object_type,
                   c.mon$source_line,
                   c.mon$source_column
            from mon$call_stack c
              join r h
                on c.mon$caller_id = h.mon$call_id
        )
        ,b as(
            select h.call_level,
                   h.mon$object_name obj_name,
                   h.mon$object_type obj_type,
                   h.mon$source_line src_row,
                   h.mon$source_column src_col
                   --count(*)over() cnt
            from r h
            join mon$statements s
                 on s.mon$statement_id = h.mon$statement_id
            where s.mon$attachment_id = current_connection
        )
        select obj_name, obj_type, src_row, src_col, call_level
        from b
        -- where call_level < cnt -- <<< do NOT include THIS sp name in call_stack
        order by call_level -- ::: NB :::
        into obj_name, obj_type, src_row, src_col, v_call_level
    do
    begin
        v_line = trim(obj_name)||'('||src_row||':'||src_col||') ==> ';
        if ( char_length(result) + char_length(v_line) >= 512 )
        then
            exit;

        if ( result NOT containing v_line and v_line NOT containing v_this||'(' )
        then
            result = result || v_line;

    end
    if ( result > '' ) then
       result = substring( result from 1 for char_length(result)-5 );

    suspend;
end

^ -- fn_get_stack

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
    declare v_curr_trn bigint;
    declare v_dummy bigint;
    declare v_need_to_stop smallint;
begin
    -- Adding single character + LF into external table (text file) 'stoptest.txt'
    -- when test is needed to stop (either due to test_time expiration or because of
    -- encountering some critical errors like PK/FK violations or negative amount remainders).
    -- Input argument a_char:
    -- '1' ==> call from SP_ADD_TO_ABEND_LOG: unexpected test finish due to PK/FK violation,
    --         and also call from SRV_FIND_QD_QS_MISM when founding mismatches between total
    --         sum of doc_data amounts and count of rows in QDistr + QStorned.
    -- '2' ==> call from SP_CHECK_TO_STOP_WORK: expected test finish due to test_time expired.
    --         In this case argument a_gdscode = -1 and we do NOT need to evaluate call stack.
    -- '5' ==> call from SRV_CHECK_NEG_REMAINDERS: unexpected test finish due to encountering
    --         negative remainder of some ware_id. NB: context var 'QMISM_VERIFY_BITSET' should
    --         have value N for which result of bin_and( N, 2 ) will be 1 in order this checkto be done.
    
    if ( (a_need_to_stop < 0 or gen_id(g_stop_test, 0) <= 0) and (select result from fn_remote_process) NOT containing 'IBExpert' )
    then
        begin
            v_curr_trn = coalesce(a_trn_id, current_transaction);
            
            -- "-1" ==> decision to premature stop all ISQL sessions by issuing EXTERNAl command
            -- (either running $tmpdir/1stoptest.tmp.sh or adding line into external file 'stoptest.txt')
            v_need_to_stop = coalesce( :a_need_to_stop, (select p.need_to_stop from sp_stoptest p rows 1) );

            v_dummy = gen_id( g_stop_test, 2147483647);
            
            in autonomous transaction do
            begin
                -- set elapsed_ms = -1 to skip this record from srv_mon_perf_detailed output:
                insert into perf_log(
                    unit
                    ,fb_gdscode
                    ,ip
                    ,trn_id
                    ,dts_end
                    ,elapsed_ms
                    ,stack
                    ,exc_unit
                    ,exc_info
                ) values(
                    'sp_halt_on_error'
                    ,:a_gdscode
                    ,rdb$get_context('SYSTEM', 'CLIENT_ADDRESS')
                    ,:v_curr_trn
                    ,'now'
                    ,-1
                    ,(select result from fn_get_stack( iif(:a_gdscode>=0, 1, 0) )) -- pass '1' to force write call_stack into perf_log if this is NOT expected test finish
                    ,:a_char
                    ,iif( -- write info for reporting state of how test finished:
                        :a_gdscode >= 0, 'ABNORMAL: GDSCODE='||coalesce(:a_gdscode,'<?>')
                        ,iif( :v_need_to_stop < 0
                             ,'PREMATURE: EXTERNAL COMMAND.'
                             ,'NORMAL: TEST_TIME EXPIRED.'
                            )
                    )
                );
                begin
                    -- moved here from sp_check_to_stop_work: avoid excessive start auton. Tx!
                    update perf_log p set p.info = 'closed'
                    where p.unit = 'perf_watch_interval' and p.info containing 'active'
                    order by dts_beg desc -- "+0" ?
                    rows 1;
                when any do
                    begin
                        -- NOP --
                    end
                end

            end
        end
end

^ -- sp_halt_on_error

-- NB: commit MUST be here for FB 2.5!
-- All even runs (2,4,6,...) of script containing procedures which references
-- to some SPs declared above them will faults if running is in the same connection
-- as previous one! See http://tracker.firebirdsql.org/browse/CORE-4490
set term ;^
commit;
set term ^;

create or alter procedure sp_flush_tmpperf_in_auton_tx(
    a_starter dm_unit,  -- name of module which STARTED job, = rdb$get_context('USER_SESSION','LOG_PERF_STARTED_BY')
    a_context_rows_cnt int, -- how many 'records' with context vars need to be processed
    a_gdscode int default null
)
as
    declare i smallint;
    declare v_id dm_idb;
    declare v_curr_tx int;
    declare v_exc_unit char(1); -- type of column perf_log.exc_unit;
    declare v_stack dm_stack;
    declare v_dbkey dm_dbkey;
    declare v_remote_addr dm_ip;
    declare v_dts_beg timestamp; -- 08.10.2018
begin
    -- Flushes all data from context variables with names 'PERF_LOG_xxx'
    -- which have been set in sp_f`lush_perf_log_on_abend for saving uncommitted
    -- data in tmp$perf_log in case of error. Frees namespace USER_SESSION from
    -- all such vars (allowing them to store values from other records in tmp$perf_log)
    -- Called only from sp_abend_flush_perf_log
    v_curr_tx = current_transaction;
    select result from fn_remote_address into v_remote_addr; -- out from loop (seems that recalc on every iteration + cost of savepoint when call this fn)

    -- 13.08.2014: we have to get full call_stack in AUTONOMOUS trn!
    -- sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1109867&msg=16422273
    in autonomous transaction do -- *****  A U T O N O M O U S    T x, due to call fn_get_stack *****
    begin
        v_dts_beg = cast('now' as timestamp);
        i=0;
        while (i < a_context_rows_cnt) do
        begin
            v_exc_unit =  rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XUNI');
            if ( v_exc_unit = '#' ) then -- ==> call from unit <U> where exception occured (not from callers of <U>)
                select result from fn_get_stack( (select result from fn_halt_sign(:a_gdscode)) ) into v_stack;
            else
                v_stack = null;

            insert into v_perf_log(
                id,
                unit,
                fb_gdscode,
                info,
                exc_unit,
                exc_info,
                dts_beg,
                dts_end,
                elapsed_ms,
                aux1,
                aux2,
                trn_id,
                ip,
                stack
            )
            values(
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_ID'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_UNIT'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_GDS'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_INFO'),
                :v_exc_unit,
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XNFO'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_BEG'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_END'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_MS'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX1'),
                rdb$get_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX2'),
                :v_curr_tx,
                :v_remote_addr,
                :v_stack
            );

            -- free space for new context vars which can be set on later iteration:
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_ID', null);    -- 1
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_UNIT', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_GDS', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_INFO', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XUNI', null);  -- 5
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_XNFO', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_BEG', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_END', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_MS', null);
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX1', null);  -- 10
            rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :i ||'_AUX2', null);
    
            i = i + 1;
        end -- while (i < a_context_rows_cnt)

        -- 11.01.2015: decided to profile this;
        -- upd 08.10.2018: replace with V_perf_log (reduce lock contention)
        insert into v_perf_log(
             unit
            ,info
            ,dts_beg
            ,dts_end
            ,trn_id
            ,ip
            ,aux1
        ) values(
             't$perf-abend:' || :a_starter                         -- unit
            ,'gds='|| :a_gdscode||', saved ' ||:i||' rows in ATx'  -- info
            ,:v_dts_beg                                            -- dts_beg
            ,'now'                                                 -- dts_end
            ,:v_curr_tx                                            -- trn_id
            ,:v_remote_addr                                        -- IP
            ,:i                                                    -- aux1
         );

    end -- in autonom. tx
end

^ -- sp_flush_tmpperf_in_auton_tx

-- NB: commit MUST be here for FB 2.5!
-- All even runs (2,4,6,...) of script containing procedures which references
-- to some SPs declared above them will faults if running is in the same connection
-- as previous one! See http://tracker.firebirdsql.org/browse/CORE-4490
set term ;^
commit;
set term ^;

create or alter procedure sp_flush_perf_log_on_abend(
    a_starter dm_unit,  -- name of module which STARTED job, = rdb$get_context('USER_SESSION','LOG_PERF_STARTED_BY')
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
    declare v_id bigint;
    declare v_unit dm_unit;
    declare v_fb_gdscode bigint;
    declare v_exc_unit char(1); -- type of column perf_log.exc_unit;
    declare v_exc_info dm_info;
    declare v_dts_beg timestamp;
    declare v_dts_end timestamp;
    declare v_aux1 dm_aux;
    declare v_aux2 dm_aux;
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
            select count(*) from rules_for_qdistr -- look at sp_cache_rules_for_distr('QDISTR')
            union all
            select count(*) from rules_for_pdistr -- look at sp_cache_rules_for_distr('PDISTR')
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
        into v_unit, v_fb_gdscode, v_info, v_exc_unit, v_exc_info, v_dts_beg, v_dts_end, v_aux1, v_aux2
    do
    begin
        if ( v_cnt < v_ctx_lim ) then
            -- there is enough place in namespace to create new context vars
            -- instead of starting auton. tx (performance!)
            begin
                v_info = coalesce(v_info, '');
                -- Some unit (e.g. ) could run several times and exc`eption could occured
                --  in Nth  call of that unit (N >= 2). We must add :a_info to v_info
                -- *ONLY* if processed record in tmp$perf_log relates to that Nth call
                -- of unit (where exc`ption occured).
                -- Sample: sp_cancel_adding_invoice => create list of dependent
                -- docs, lock all of them, and then for each of these docs (reserves):
                -- sp_cancel_reserve => trigger doc_list_aiud => sp_kill_qstorno_ret_qs2qd
                if (v_unit = a_unit
                    and
                    v_exc_unit is NOT null
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

                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_ID', :v_pf_new_id);    --  1
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_UNIT', :v_unit);       --  2
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_GDS', :v_fb_gdscode ); --  3
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_INFO', :v_info);       --  4
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_XUNI', :v_exc_unit);   --  5
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_XNFO', :v_exc_info);   --  6
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_BEG', :v_dts_beg);     --  7
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_END', :v_dts_end);     --  8
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_MS', datediff(millisecond from :v_dts_beg to :v_dts_end));
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_AUX1', :v_aux1);       -- 10
                rdb$set_context('USER_SESSION', 'PERF_LOG_'|| :v_cnt ||'_AUX2', :v_aux2);       -- 11
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

-- STUBS for two SP, they will be defined later, need in sp_add_to_perf_log (30.08.2014)
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
          --rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '3.' -- new mon counters were introduced only in 3.0!
         --and fn_remote_process() containing 'IBExpert'
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
--------------------------------------------------------------------------------
-- NB: commit MUST be here for FB 2.5!
-- All even runs (2,4,6,...) of script containing procedures which references
-- to some SPs declared above them will faults if running is in the same connection
-- as previous one! See http://tracker.firebirdsql.org/browse/CORE-4490
set term ;^
commit;
set term ^;

-------------------------------------------------------------------------------

create or alter procedure sp_add_perf_log (
    a_is_unit_beginning dm_sign,
    a_unit dm_unit,
    a_gdscode integer default null,
    a_info dm_info default null,
    a_aux1 dm_aux default null,
    a_aux2 dm_aux default null
) as
    declare v_curr_tx bigint;
    declare v_dts timestamp;
    declare v_save_dts_beg timestamp;
    declare v_save_dts_end timestamp;
    declare v_save_gtt_cnt int;
    declare v_id dm_idb;
    declare v_unit dm_unit;
    declare v_info dm_info;
    declare c_gen_inc_step_pf int = 20; -- size of `batch` for get at once new IDs for perf_log (reduce lock-contention of gen page)
    declare v_gen_inc_iter_pf int; -- increments from 1  up to c_gen_inc_step_pf and then restarts again from 1
    declare v_gen_inc_last_pf dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_pf)
    declare v_pf_new_id dm_idb;
    declare v_exc_unit char(1);
    declare c_tmp_perf_log cursor for (
        select
             unit, exc_unit
            ,fb_gdscode, trn_id, att_id, elapsed_ms
            ,info, exc_info, stack
            ,ip, dts_beg, dts_end
            ,aux1, aux2
        from tmp$perf_log g
    );
    declare v_fb_gdscode int;
    declare v_trn_id dm_idb;
    declare v_att_id dm_idb;
    declare v_elapsed_ms int;

    declare v_exc_info dm_info;
    declare v_stack dm_stack;
    declare v_ip dm_ip;
    declare v_dts_beg timestamp;
    declare v_dts_end timestamp;
    declare v_aux1 double precision;
    declare v_aux2 double precision;
begin
    -- Registration of all STARTs and FINISHes (both normal and failed)
    -- for all application SPs and some service units:
    v_curr_tx = current_transaction;
    v_dts = cast('now' as timestamp);

    -- 08.10.2018: usage of updatable view v_perf_log instead of table perf_log.

    -- Gather all avaliable mon info about caller module if its name belongs
    -- to list specified in `MON_UNIT_LIST` context var: add pair of row sets
    -- (for beg and end) and then calculate DIFFERENCES of mon. counters with
    -- logging in tables `mon_log` and `mon_log_table_stats`.
    execute procedure srv_log_mon_for_traced_units( a_unit, a_gdscode, a_info );

    if ( not exists(select * from tmp$perf_log) ) then
    begin
       rdb$set_context('USER_SESSION','LOG_PERF_STARTED_BY', a_unit);
       a_is_unit_beginning = 1;
    end

    if ( a_is_unit_beginning = 1 ) then -- this is call from ENTRY of :a_unit
        begin
            insert into tmp$perf_log(
                 unit,
                 info,
                 ip,
                 trn_id,
                 dts_beg
            )
            values(
                 :a_unit,
                 :a_info,
                 rdb$get_context('SYSTEM','CLIENT_ADDRESS'),
                 :v_curr_tx,
                 :v_dts
            );
            -- save info about last started unit (which can raise exc):
            rdb$set_context('USER_TRANSACTION','TPLOG_LAST_UNIT', a_unit);
            rdb$set_context('USER_TRANSACTION','TPLOG_LAST_BEG', v_dts);
            rdb$set_context('USER_TRANSACTION','TPLOG_LAST_INFO', v_info);
        end
    else -- a_is_unit_beginning = 0 ==> this is _NORMAL_ finish of :a_unit (i.e. w/o exception)
        begin
            update tmp$perf_log t set
                info = left(coalesce( info, '' ) || coalesce( trim(iif( info>'', '; ', '') || :a_info), ''), 255),
                dts_end = :v_dts,
                -- dis 12.01.2015, not need more: id2 = gen_id(g_perf_log, 1), -- 4 debug! 28.09.2014
                elapsed_ms = datediff(millisecond from dts_beg to :v_dts),
                aux1 = :a_aux1,
                aux2 = :a_aux2
            where -- Bitmap Index "TMP$PERF_LOG_UNIT_TRN" Range Scan (full match)
                t.unit = :a_unit
                and t.trn_id = :v_curr_tx
                and dts_end is NULL -- we are looking for record that was added at the BEG of this unit call
            ;

            if ( a_unit = rdb$get_context('USER_SESSION','LOG_PERF_STARTED_BY') ) then
            begin
                v_gen_inc_iter_pf = c_gen_inc_step_pf;

                -- Finish of top-level unit (which start business op.):
                -- MOVE *ALL* data currently stored in GTT tmp$perf_log to fixed table perf_log

                v_save_dts_beg = 'now'; -- for logging time and number of moved records
                v_save_gtt_cnt = 0;

                open c_tmp_perf_log;
                while (1=1) do
                begin
                    fetch c_tmp_perf_log into
                         v_unit
                        ,v_exc_unit
                        ,v_fb_gdscode
                        ,v_trn_id
                        ,v_att_id
                        ,v_elapsed_ms
                        ,v_info
                        ,v_exc_info
                        ,v_stack
                        ,v_ip
                        ,v_dts_beg
                        ,v_dts_end
                        ,v_aux1
                        ,v_aux2;
                    if (row_count = 0) then leave;

                    if ( v_gen_inc_iter_pf = c_gen_inc_step_pf ) then -- its time to get another batch of IDs
                    begin
                        v_gen_inc_iter_pf = 1;
                        -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                        v_gen_inc_last_pf = gen_id( g_perf_log, :c_gen_inc_step_pf );
                    end
                    v_pf_new_id = v_gen_inc_last_pf - ( c_gen_inc_step_pf - v_gen_inc_iter_pf );
                    v_gen_inc_iter_pf = v_gen_inc_iter_pf + 1;

                    insert into v_perf_log( -- current unit: sp_add_perf_log
                        id
                        ,unit, exc_unit
                        ,fb_gdscode, trn_id, att_id, elapsed_ms
                        ,info, exc_info, stack
                        ,ip, dts_beg, dts_end
                        ,aux1, aux2
                    ) values (
                        :v_pf_new_id
                        ,:v_unit, :v_exc_unit
                        ,:v_fb_gdscode, :v_trn_id, :v_att_id, :v_elapsed_ms
                        ,:v_info, :v_exc_info, :v_stack
                        ,:v_ip, :v_dts_beg, :v_dts_end
                        ,:v_aux1, :v_aux2
                    );
                    v_save_gtt_cnt = v_save_gtt_cnt + 1;

                    delete from tmp$perf_log where current of c_tmp_perf_log;
                end -- end of loop moving rows from GTT tmp$perf_log to fixed perf_log
                close c_tmp_perf_log;

                v_save_dts_end = 'now';

                -- Add info about timing and num. of record (tmp$ --> fixed):
                insert into v_perf_log( -- current unit: sp_add_perf_log
                        id,
                        unit, info, dts_beg, dts_end, elapsed_ms, ip, aux1)
                values( iif( :v_gen_inc_iter_pf < :c_gen_inc_step_pf, :v_pf_new_id+1, gen_id( g_perf_log, 1 )  ),
                        't$perf-norm:'||:a_unit,
                        'ok saved '||:v_save_gtt_cnt||' rows',
                        :v_save_dts_beg,
                        :v_save_dts_end,
                        datediff( millisecond from :v_save_dts_beg to :v_save_dts_end ),
                        rdb$get_context('SYSTEM','CLIENT_ADDRESS'),
                        :v_save_gtt_cnt
                      );
            end --  a_unit = rdb$get_context('USER_SESSION','LOG_PERF_STARTED_BY')
        end -- a_is_unit_beginning = 0
end

^ -- sp_add_perf_log

create or alter procedure sp_upd_in_perf_log(
    a_unit dm_unit,
    a_gdscode int default null,
    a_info dm_info default null
) as
begin
    -- need in case when we want to update info in just added row
    -- (e.g. info about selected doc etc)
    update tmp$perf_log t set
        t.fb_gdscode = coalesce(t.fb_gdscode, :a_gdscode),
        t.info = coalesce( t.info, '' ) || coalesce( trim(iif( t.info>'', '; ', '') || :a_info), '')
    where
        t.unit = :a_unit
        and t.trn_id = current_transaction
        and t.dts_end is NULL
        and coalesce(t.info,'') NOT containing coalesce(trim(:a_info),'');
end

^  -- sp_upd_in_perf_log

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

^ -- zdump4dbg (STUB!)

create or alter procedure sp_add_to_abend_log(
       a_exc_info dm_info,
       a_gdscode int default null,
       a_info dm_info default null,
       a_caller dm_unit default null,
       a_halt_due_to_error smallint default 0 --  1 ==> forcely extract FULL STACK ignoring settings, because of error + halt test
) as
    declare v_last_unit dm_unit;
    declare v_last_info dm_info;
    declare v_last_beg timestamp;
    declare v_last_end timestamp;
begin
    -- SP for register info about e`xception occured in application module.
    -- When each module starts, it call sp_add_to_perf_log and creates record in
    -- perf_log table for this event. If some e`xception occurs in that module
    -- than code jumps into when_any section with call of this SP.
    -- Now we have to call sp_add_to_perf_log with special argument ('!abend!')
    -- signalling that all data from GTT tmp$perf_log should be saved now via ATx.
    if ( a_gdscode is NOT null and nullif(a_exc_info, '') is null ) then -- this is standard error
    begin
        select f.fb_mnemona
        from fb_errors f
        where f.fb_gdscode = :a_gdscode
        into a_exc_info;
    end
    -- For displaying in ISQL session logs:
    rdb$set_context('USER_SESSION','ADD_INFO', left( coalesce(a_exc_info, 'no-mnemona'), 255));

    v_last_unit = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_UNIT');

    if ( a_caller = v_last_unit ) then
    begin
        -- CORE-4483. "Changed data not visible in WHEN-section if exception
        -- occured inside SP that has been called from this code" ==> last record
        -- in tmp$perf_log that has been added in SP_ADD_PERF_LOG which has been
        -- called at the START point of this SP CALLER, will be backed out (REMOVED!)
        -- when exception occurs later in the intermediate point of caller, so
        -- HERE we get tmp$perf_log WITHOUT last record!
        -- 10.01.2015: replaced 'update' with 'update or insert': record in
        -- tmp$perf_log can be 'lost' in case of exc in caller before we come
        -- in this SP (sp_cancel_client_order => sp_lock_selected_doc).
        v_last_beg = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_BEG');
        v_last_end = cast('now' as timestamp);
        v_last_info = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_INFO');

        update tmp$perf_log t
        set
            fb_gdscode = :a_gdscode,
            info = :a_info, --  coalesce( :v_last_info, '<null-1>'),
            exc_unit = '#', -- exc_unit: direct CALLER of this SP is the SOURCE of raised exception
            dts_end = :v_last_end,
            elapsed_ms = datediff(millisecond from :v_last_beg to :v_last_end)
        where
            t.unit = rdb$get_context('USER_TRANSACTION','TPLOG_LAST_UNIT')
            and t.trn_id = current_transaction
            and dts_end is NULL; -- index key: UNIT,TRN_ID,DTS_END

        if ( row_count = 0 ) then
            insert into tmp$perf_log(
                 unit
                ,fb_gdscode
                ,info
                ,exc_unit
                ,dts_beg
                ,dts_end
                ,elapsed_ms
                ,trn_id
            ) values (
                 :a_caller
                ,:a_gdscode
                ,:a_info --- coalesce( :v_last_info, '<null-2>')
                ,'#' -- ==> module :a_caller IS the source of raised exception
                ,:v_last_beg
                ,:v_last_end
                ,datediff(millisecond from :v_last_beg to :v_last_end)
                ,current_transaction
            );

        -- before 10.01.2015:
        -- update tmp$perf_log set ... where t.unit = :a_caller and and t.trn_id = current_transaction and dts_end is NULL;
        rdb$set_context('USER_TRANSACTION','TPLOG_LAST_UNIT', null);

        -- Save uncommitted data from tmp$perf_log to perf_log (via autonom. tx):
        -- NB: All records in GTT tmp$perf_log are visible ONLY at the "deepest" point
        -- when exc` occured. If SP_03 add records to tmp$perf_log and then raises exc
        -- then all its callers (SP_00==>SP_01==>SP_02) will NOT see these record because
        -- these changes will be rolled back when exc. comes into these caller.
        -- So, we must flush records from GTT to fixed table only in the "deepest" point,
        -- i.e. just in that SP where exc raises.
        execute procedure sp_flush_perf_log_on_abend(
            rdb$get_context('USER_SESSION','LOG_PERF_STARTED_BY'), -- unit which start this job
            a_caller,
            a_gdscode,
            a_info, -- info for analysis
            a_exc_info -- info about user-defined or standard e`xception which occured now
        );

    end --  a_caller = v_last_unit 

    -- ########################   H A L T   T E S T   ######################
    if ( a_halt_due_to_error = 1 ) then
    begin
        execute procedure sp_halt_on_error('1', a_gdscode);
        if ( ( select result from fn_halt_sign( :a_gdscode ) ) = 1 ) then -- 27.07.2014 1003
        begin
             execute procedure zdump4dbg;
        end
    end
    -- #####################################################################

end

^ -- sp_add_to_abend_log

-- NB: commit MUST be here for FB 2.5!
-- All even runs (2,4,6,...) of script containing procedures which references
-- to some SPs declared above them will faults if running is in the same connection
-- as previous one! See http://tracker.firebirdsql.org/browse/CORE-4490
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
)
as
  declare msg varchar(512) = '';
begin
    -- Check for each non-empty pair that corresponding context variable
    -- EXISTS in it's namespace. Raises exception and pass to it list of pairs
    -- which does not exists.

    if (ctx_nmspace_01>'' and rdb$get_context( upper(ctx_nmspace_01), upper(ctx_varname_01) ) is null  ) then
        msg = msg||upper(ctx_nmspace_01)||':'||coalesce(upper(ctx_varname_01),'''null''');
    
    if (ctx_nmspace_02>'' and rdb$get_context( upper(ctx_nmspace_02), upper(ctx_varname_02) ) is null  ) then
        msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_02)||':'||coalesce(upper(ctx_varname_02),'''null''');
    
    if (ctx_nmspace_03>'' and rdb$get_context( upper(ctx_nmspace_03), upper(ctx_varname_03) ) is null  ) then
       msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_03)||':'||coalesce(upper(ctx_varname_03),'''null''');
    
    if (ctx_nmspace_04>'' and rdb$get_context( upper(ctx_nmspace_04), upper(ctx_varname_04) ) is null  ) then
       msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_04)||':'||coalesce(upper(ctx_varname_04),'''null''');
    
    if (ctx_nmspace_05>'' and rdb$get_context( upper(ctx_nmspace_05), upper(ctx_varname_05) ) is null  ) then
        msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_05)||':'||coalesce(upper(ctx_varname_05),'''null''');
    
    if (ctx_nmspace_06>'' and rdb$get_context( upper(ctx_nmspace_06), upper(ctx_varname_06) ) is null  ) then
        msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_06)||':'||coalesce(upper(ctx_varname_06),'''null''');
    
    if (ctx_nmspace_07>'' and rdb$get_context( upper(ctx_nmspace_07), upper(ctx_varname_07) ) is null  ) then
        msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_07)||':'||coalesce(upper(ctx_varname_07),'''null''');
    
    if (ctx_nmspace_08>'' and rdb$get_context( upper(ctx_nmspace_08), upper(ctx_varname_08) ) is null  ) then
        msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_08)||':'||coalesce(upper(ctx_varname_08),'''null''');
    
    if (ctx_nmspace_09>'' and rdb$get_context( upper(ctx_nmspace_09), upper(ctx_varname_09) ) is null  ) then
        msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_09)||':'||coalesce(upper(ctx_varname_09),'''null''');
    
    if (ctx_nmspace_10>'' and rdb$get_context( upper(ctx_nmspace_10), upper(ctx_varname_10) ) is null  ) then
        msg = msg||iif(msg='', '', '; ')||upper(ctx_nmspace_10)||':'||coalesce(upper(ctx_varname_10),'''null''');

    if (msg<>'') then
    begin
        execute procedure sp_add_to_abend_log( left( msg, 255 ) );
        exception ex_context_var_not_found; -- using( msg );
    end
end -- sp_check_ctx

^
set term ;^
commit;

set term ^;

create or alter procedure sp_check_nowait_or_timeout as
    declare msg varchar(255);
begin
    if ( (select result from fn_remote_process) containing 'IBExpert' ) then exit; -- 4debug

    -- Must be called from all SPs which are at 'top' level of data handling.
    -- Checks that current Tx is running with NO WAIT or LOCK_TIMEOUT.
    -- Otherwise raises error
    if  ( cast( rdb$get_context('SYSTEM', 'LOCK_TIMEOUT') as int) < 0 ) then
    begin
        msg = 'NO WAIT or LOCK_TIMEOUT required!';
        execute procedure sp_add_to_abend_log( msg, null, null, 'sp_check_nowait_or_timeout' );
        exception ex_nowait_or_timeout_required;
    end
end
^

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

    if ( (select result from fn_remote_process) containing 'IBExpert' ) then exit; -- 4debug; 23.07.2014

    if ( rdb$get_context('USER_SESSION','PERF_WATCH_END') is null ) then
        begin
            -- this record is added in 1run_oltp_emul.bat before FIRST attach
            -- will begin it's work:
            -- PLAN (P ORDER PERF_LOG_DTS_BEG_DESC INDEX (PERF_LOG_UNIT))
            select p.dts_beg, p.dts_end
            from perf_log p
            where p.unit = 'perf_watch_interval' and p.info containing 'active'
            order by dts_beg + 0 desc -- !! 24.09.2014, speed !! (otherwise dozen fetches!)
            rows 1
            into v_dts_beg, v_dts_end;
            rdb$set_context('USER_SESSION','PERF_WATCH_BEG', v_dts_beg);
            rdb$set_context('USER_SESSION','PERF_WATCH_END', coalesce(v_dts_end, dateadd(3 hour to current_timestamp) ) );
        end
    else
        begin
            v_dts_end = rdb$get_context('USER_SESSION','PERF_WATCH_END');
        end

    v_need_to_stop = null;
    select p.need_to_stop from sp_stoptest p rows 1 into v_need_to_stop;

    if ( cast('now' as timestamp) > v_dts_end -- NORMAL finish because of test_time expiration
         or
         v_need_to_stop < 0 -- External force all ISQL sessions PREMATURE be stopped itself (either by running $tmpdir/1stoptest.tmp batch or by adding line to 'stoptest.txt')
       )
    then
        begin
           execute procedure sp_halt_on_error('2', -1, current_transaction, :v_need_to_stop);
           -- exception ex_test_cancellation; -- E X C E P T I O N:  C A N C E L   T E S T
           exception ex_test_cancellation ( select result from sys_stamp_exception('ex_test_cancellation') );
        end
end

^ -- sp_check_to_stop_work

set term ;^
commit;
set term ^;

create or alter procedure sp_init_ctx
as
    declare v_name type of dm_name;
    declare v_context type of column settings.context;
    declare v_value type of dm_setting_value;
    declare v_counter int = 0;
    declare msg varchar(255);
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
        rdb$set_context(
            'USER_SESSION',
            'WORKING_MODE',
            (select s.svalue
            from settings s
            where s.working_mode = 'INIT' and s.mcode = 'WORKING_MODE')
                       );
    end

    if ( rdb$get_context('USER_SESSION','WORKING_MODE') is not null
       and
       exists (select * from settings s
                where s.working_mode = rdb$get_context('USER_SESSION','WORKING_MODE')
              )
     ) then
    begin
        -- initializes all needed context variables (scan `setting` table)
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
        exception ex_bad_working_mode_value;
        -- "-db-level trigger TRG_CONNECT: no found rows for settings.working_mode='>****<', correct it!"
    end
end

^ -- sp_init_ctx



-- STUB! Redefinition see in file oltp_dump.sql
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

^

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
    result bigint
)
as
    declare i smallint;
    declare v_stt varchar(255);
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
    fn_internal_max_rows_usage = cast( rdb$get_context('USER_SESSION','RANDOM_SEEK_VIA_ROWS_LIMIT') as int);

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
        execute procedure sp_add_perf_log(1, a_view_for_min_id );
        -- v`iew z_get_min_max_id may be used to see average, min and max elapsed time
        -- of this sttm:
        v_stt='select min(id)-0.5 from '|| a_view_for_min_id;
        execute statement (:v_stt) into id_min; -- do via ES in order to see statistics in the TRACE!
        execute procedure sp_add_perf_log(0, a_view_for_min_id, null, 'id_min='||coalesce(id_min,'<?>') );

        if ( id_min is NOT null ) then -- ==> source <a_view_for_min_id> is NOT empty
        begin

            execute procedure sp_add_perf_log(1, a_view_for_max_id );
            -- v`iew z_get_min_max_id may be used to see average, min and max elapsed time
            -- of this sttm:
            v_stt='select max(id)+0.5 from '|| a_view_for_max_id;
            execute statement (:v_stt) into id_max; -- do via ES in order to see statistics in the TRACE!
            execute procedure sp_add_perf_log(0, a_view_for_max_id, null, 'id_max='||coalesce(id_max,'<?>') );

            if ( id_max is NOT null  ) then -- ==> source <a_view_for_max_id> is NOT empty
            begin
                -- Save values for subsequent calls of this func in this tx (minimize DB access)
                -- (limit will never change in SNAPSHOT and can change with low probability in RC):
                rdb$set_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN', :id_min);
                rdb$set_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX', :id_max);
        
                if ( id_max - id_min < fn_internal_max_rows_usage ) then
                begin
                    -- when difference b`etween id_min and id_max is not too high, we can simple count rows:
                    execute statement 'select count(*) from '||a_view_for_search into v_rows;
                    rdb$set_context('USER_TRANSACTION', upper(:a_view_for_search)||'_COUNT', v_rows );
                end
            end -- id_max is NOT null 
        end -- id_min is NOT null
    end
    else begin
        -- minimize database access! Performance on 10'000 loops: 1485 ==> 590 ms
        id_min=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN' ) as double precision);
        id_max=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX' ) as double precision);
        v_rows=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_search)||'_COUNT') as int);
    end

    if ( id_max - id_min < fn_internal_max_rows_usage ) then
        begin
            v_stt='select id from '||a_view_for_search||' rows :x to :y'; -- ::: nb ::: `ORDER` clause not needed here!
        end
    else
        begin
            -- 17.07.2014: for some cases it is ALLOWED to query random ID without "ORDER BY"
            -- clause because this ID will be handled in such manner that it will be REMOVED
            -- after this handling from the scope of view! Samples of such cases are:
            -- sp_cancel_supplier_order, sp_cancel_supplier_invoice, sp_cancel_customer_reserve
            v_stt='select id from '
                ||a_view_for_search
                ||iif(a_find_using_desc_index = 0, ' where id >= :x', ' where id <= :x');
            if ( a_can_skip_order_clause = 0 ) then
                v_stt = v_stt || iif(a_find_using_desc_index = 0, ' order by id     ', ' order by id desc');
            v_stt = v_stt || ' rows 1';
        end

    i = a_count_to_generate;
    while ( i > 0 ) do
    begin
        result = null;
        if ( id_max - id_min < fn_internal_max_rows_usage ) then
            begin
                id_random = ceiling( rand() * v_rows );
                execute statement (:v_stt) (x := id_random, y := id_random) into result;
            end
        else
            begin
                id_random = cast( id_min + rand() * (id_max - id_min) as bigint);
                execute statement (:v_stt) (x := id_random) into result;
            end

        if ( result is null and coalesce(a_raise_exc, 1) = 1 ) then
            begin

                v_info = 'view: '||:a_view_for_search;
                if ( id_min is NOT null ) then
                   v_info = v_info || ', id_min=' || id_min || ', id_max='||id_max;
                else
                   v_info = v_info || ' - EMPTY';

                v_info = v_info ||', id_rnd='||coalesce(id_random,'<null>');

                -- 19.07.2014: 'no id>=@1 in @2 found within scope @3 ... @4'
                v_detailed_exc_text = 'no id >= ' || coalesce(id_random,'<?>') || ' in ' || a_view_for_search || ' found within scope ' || coalesce(id_min,'<?>') || ' ... ' || coalesce(id_max,'<?>');
                exception ex_can_not_select_random_id ( select result from sys_stamp_exception('ex_can_not_select_random_id', :v_detailed_exc_text) );

            end
        else
            suspend; -- output arg: result

        i = i - 1;
    end

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            v_stt,
            gdscode,
            v_info,
            v_this,
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_stt varchar(255);
    declare v_exc_info dm_info;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'sp_lock_selected_doc';
begin
    -- Seeks selected id in doc_list with checking existence
    -- of this ID in a_view_for_search (if need).
    -- Raises exc if not found, otherwise tries to lock ID in doc_list

    v_info = 'doc_id='||coalesce(doc_list_id, '<?>')||', src='||a_view_for_search;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    v_stt =
          'select rdb$db_key from doc_list'
        ||' where '
        ||' id = :x'
        ||' and ( :y is null' -- ==> doc_list_id was defined via sp_get_random_id
        ||' or'
        ||' exists( select id from '||a_view_for_search||' v where v.id = :x )'
        ||')';

    execute statement (v_stt) ( x := :doc_list_id, y := :a_selected_doc_id ) into v_dbkey;

    if ( v_dbkey is null ) then
    begin
        -- no document found for handling in datasource = ''@1'' with id=@2';
        exception ex_no_doc_found_for_handling;
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

create or alter procedure sp_cache_rules_for_distr( a_table dm_dbobj )
returns(
    mode dm_name,
    snd_optype_id  bigint,
    rcv_optype_id  bigint,
    rows_to_multiply int
)
as
    declare v_ctx_prefix type of dm_ctxnv;
    declare v_stt varchar(255);
    declare i int;
    declare v_mode dm_name;
    declare v_snd_optype_id type of dm_idb;
    declare v_rcv_optype_id type of dm_idb;
    declare v_rows_to_multiply int;
begin
    if ( upper(coalesce(a_table,'')) not in ( upper('QDISTR'), upper('PDISTR') ) )
    then
      exception ex_bad_argument; --  'argument @1 passed to unit @2 is invalid';

    -- cache records from rules_for_Qdistr and rules_for_Pdistr in context variables
    -- for fast output of them (without database access)

    v_ctx_prefix = 'MEM_TABLE_'||upper(a_table)||'_'; -- 'MEM_TABLE_QDISTR' or 'MEM_TABLE_PDISTR'
    v_stt='select mode, snd_optype_id, rcv_optype_id' || iif( upper(a_table)=upper('QDISTR'),', storno_sub',', rows_to_multiply ' )
          ||' from rules_for_'||a_table;
    if ( rdb$get_context('USER_SESSION', v_ctx_prefix||'CNT') is null ) then
    begin
        i = 1;
        for
            execute statement( v_stt )
            into v_mode, v_snd_optype_id, v_rcv_optype_id, v_rows_to_multiply
        do begin
            rdb$set_context(
            'USER_SESSION'
            ,v_ctx_prefix||i
            ,rpad( v_mode ,80,' ')
             || coalesce( cast(v_snd_optype_id as char(18)), rpad('', 18,' ') )
             || coalesce( cast(v_rcv_optype_id as char(18)), rpad('', 18,' ') )
             || coalesce( cast(v_rows_to_multiply as char(10)), rpad('', 10,' ') )
            );
            rdb$set_context('USER_SESSION', v_ctx_prefix||'CNT', i);
            i = i+1;
        end
    end
    i = 1;
    while ( i <= cast(rdb$get_context('USER_SESSION', v_ctx_prefix||'CNT') as int) )
    do begin
        mode = trim( substring( rdb$get_context('USER_SESSION', v_ctx_prefix||i) from 1 for 80 ) );
        snd_optype_id = cast( nullif(trim(substring( rdb$get_context('USER_SESSION', v_ctx_prefix||i) from 81 for 18 )), '') as dm_idb);
        rcv_optype_id = cast( nullif(trim(substring( rdb$get_context('USER_SESSION', v_ctx_prefix||i) from 99 for 18 )), '') as dm_idb);
        rows_to_multiply = cast( nullif(trim(substring( rdb$get_context('USER_SESSION', v_ctx_prefix||i) from 117 for 10 )), '') as int);
        suspend;
        i = i+1;
    end
end

^ -- sp_cache_rules_for_distr

create or alter procedure sp_rules_for_qdistr
returns(
    mode dm_name,
    snd_optype_id  bigint,
    rcv_optype_id  bigint,
    storno_sub smallint -- 28.07.2014
) as
begin
  for
      select p.mode,p.snd_optype_id, p.rcv_optype_id,
             p.rows_to_multiply -- 28.07.2014
      from sp_cache_rules_for_distr('QDISTR') p
      into mode, snd_optype_id, rcv_optype_id,
           storno_sub -- 28.07.2014
  do
      suspend;
end

^ -- sp_rules_for_qdistr

create or alter procedure sp_rules_for_pdistr
returns(
    snd_optype_id  bigint,
    rcv_optype_id  bigint,
    rows_to_multiply int
)
as
begin
  for
      select p.snd_optype_id, p.rcv_optype_id, p.rows_to_multiply
      from sp_cache_rules_for_distr('PDISTR') p
      into snd_optype_id, rcv_optype_id, rows_to_multiply
  do
      suspend;
end

^ -- sp_rules_for_pdistr

set term ;^
commit; -- mandatory for FB 2.5!

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

-- 07.09.2015: probe to replace ES in all cases of fn_get_rand_id:
create or alter view name$to$substutite$min$id$ as select 1 id from rdb$database;
create or alter view name$to$substutite$max$id$ as select 1 id from rdb$database;
create or alter view name$to$substutite$search$ as select 1 id from rdb$database;

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
    declare v_qty_acc type of dm_qty;
    declare v_purchase_acc type of dm_cost;
    declare v_retail_acc type of dm_cost;
    declare v_dbkey dm_dbkey;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'sp_multiply_rows_for_qdistr';
    declare v_storno_sub smallint;
    declare v_worker_id type of dm_ids;
begin
    -- Performs "value-to-rows" filling of QDISTR table: add rows which
    -- later will be "storned" (removed from qdistr to qstorned)

    v_info = 'dh='||a_doc_list_id||', q_sum='||a_qty_sum;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    v_gen_inc_iter_qd = 1;
    c_gen_inc_step_qd = (1 + a_qty_sum) * iif(a_clo_for_our_firm=1, 1, 2) + 1;
    -- take bulk IDs at once (reduce lock-contention for GEN page):
    v_gen_inc_last_qd = gen_id( g_qdistr, :c_gen_inc_step_qd );
    
    -- 12.08.2018: get subsequent number of "current" ISQL session.
    -- We need this when config parameter separate_workers = 1:
    select result from fn_this_worker_seq_no into v_worker_id;

    -- Cursor: how many distributions must be done for this doc if it is "sender" ?
    -- =2 for customer order (if agent <> our firm!!):
    --    it will be storned by stock order
    --    and later by customer reserve
    -- =1 for all other operations:
    for
        select r.rcv_optype_id, c.snd_id, c.id as ware_id, c.qty, c.cost_purchase, c.cost_retail, r.storno_sub
        from rules_for_qdistr r
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
            if ( v_storno_sub = 1 ) then
                insert into v_qdistr_multiply_1 (
                    id,
                    doc_id,
                    worker_id, -- 12.08.2018
                    ware_id,
                    snd_optype_id,
                    rcv_optype_id,
                    snd_id,
                    snd_qty,
                    snd_purchase,
                    snd_retail)
                values(
                    :v_gen_inc_last_qd - ( :c_gen_inc_step_qd - :v_gen_inc_iter_qd ), -- iter=1: 12345 - (100-1); iter=2: 12345 - (100-2); ...; iter=100: 12345 - (100-100)
                    :a_doc_list_id,
                    :v_worker_id,
                    :v_ware_id,
                    :a_optype_id,
                    :v_rcv_optype_id,
                    :v_doc_data_id,
                    :v_qty_for_one_row,
                    :v_purchase_for_distr * :v_qty_for_one_row / :v_qty_for_distr,
                    :v_retail_for_distr * :v_qty_for_one_row / :v_qty_for_distr
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
                    id,
                    doc_id,
                    worker_id, -- 12.08.2018
                    ware_id,
                    snd_optype_id,
                    rcv_optype_id,
                    snd_id,
                    snd_qty,
                    snd_purchase,
                    snd_retail)
                values(
                    :v_gen_inc_last_qd - ( :c_gen_inc_step_qd - :v_gen_inc_iter_qd ), -- iter=1: 12345 - (100-1); iter=2: 12345 - (100-2); ...; iter=100: 12345 - (100-100)
                    :a_doc_list_id,
                    :v_worker_id,
                    :v_ware_id,
                    :a_optype_id,
                    :v_rcv_optype_id,
                    :v_doc_data_id,
                    :v_qty_for_one_row,
                    :v_purchase_for_distr * :v_qty_for_one_row / :v_qty_for_distr,
                    :v_retail_for_distr * :v_qty_for_one_row / :v_qty_for_distr
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

            n_rows_to_add = n_rows_to_add - 1;
            v_gen_inc_iter_qd = v_gen_inc_iter_qd + 1;

            if ( n_rows_to_add = 0 and
                 ( v_qty_acc <> v_qty_for_distr
                   or v_purchase_acc <> v_purchase_for_distr
                   or v_retail_acc <> v_retail_for_distr
                 )
               ) then
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
            else
                if ( v_gen_inc_iter_qd = c_gen_inc_step_qd ) then -- its time to get another batch of IDs
                begin
                    v_gen_inc_iter_qd = 1;
                    -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
                    v_gen_inc_last_qd = gen_id( g_qdistr, :c_gen_inc_step_qd );
                end
        end -- while( n_rows_to_add > 0 )
    end -- cursor on doc_data cross join rules_for_qdistr

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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_internal_min_cost_4_split int;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'sp_multiply_rows_for_pdistr';
    declare v_worker_id type of dm_ids;
begin
    -- Performs "cost-to-rows" filling of PDISTR table: add rows which
    -- later will be "storned" (removed from pdistr to pstorned)
    v_info = 'dh='||a_doc_list_id||', op='||a_optype_id||', $='||a_cost_for_distr;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    -- 12.08.2018: get subsequent number of "current" ISQL session.
    -- We need this when config parameter separate_workers = 1:
    select result from fn_this_worker_seq_no into v_worker_id;

    v_internal_min_cost_4_split = cast(rdb$get_context('USER_SESSION', 'C_MIN_COST_TO_BE_SPLITTED' ) as int);
    for
        select r.rcv_optype_id, iif( :a_cost_for_distr < :v_internal_min_cost_4_split, 1, r.rows_to_multiply )
        from sp_rules_for_pdistr r
        where r.snd_optype_id = :a_optype_id
        into v_rcv_optype_id, n_rows_to_add
    do
    begin
        v_cost_acc = 0;
        v_cost_div = round( a_cost_for_distr / n_rows_to_add, -2 ); -- round to handreds
        while( v_cost_acc < a_cost_for_distr ) do
        begin
            v_cost_for_one_row = iif( a_cost_for_distr > v_cost_div, v_cost_div, a_cost_for_distr );

            insert into pdistr(
                agent_id,
                snd_optype_id,
                snd_id,
                worker_id,               -- 12.08.2018
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
            (select result from fn_halt_sign(gdscode) ) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_id dm_idb;
    declare v_dbkey dm_dbkey;
    declare agent_id dm_idb;
    declare snd_optype_id dm_idb;
    declare snd_id dm_idb;
    declare cost_to_be_storned type of dm_cost;
    declare rcv_optype_id dm_idb;
    declare rcv_id bigint;
    declare v_remote_process varchar(255);
    declare v_worker_id type of dm_ids;

    declare cp cursor for (
        select
            p.rdb$db_key,
            p.id,
            p.agent_id,
            p.snd_optype_id,
            p.snd_id,
            p.snd_cost as cost_to_be_storned,
            p.rcv_optype_id,
            :a_doc_id as rcv_id
        from pdistr p
        where 
            p.agent_id = :a_agent_id 
            and p.snd_optype_id = :v_storned_doc_optype_id
            -- 12.08.2018: sequential number of ISQL session that queries this view.
            -- This filter is added with purpose to reduce number of lock-conflict errors:
            and p.worker_id is not distinct from :v_worker_id
        order by
            p.snd_id+0 -- 23.07.2014: PLAN SORT (P INDEX (PDISTR_AGENT_ID)
            ,:v_sign * p.id -- attempt to reduce locks: odd and even Tx handling the same doc must have a chance do not encounter locked rows at all
        --order by p.id (wrong if new pdistr.id is generated via sequence when records returns from pstorned)
    );

begin
    -- Performs attempt to make storno of:
    -- 1) payment docs by cost of stock document which state is changed
    --    to "closed"(sp_add_invoice_to_stock or sp_reserve_write_off)
    -- 2) old stock documents when adding new payment (sp_pay_from_customer, sp_pay_to_supplier)
    -- ::: nb ::: If record in "source" table (pdistr) can`t be locked - SKIP it
    -- and try to lock next one (in order to reduce number of lock conflicts)

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    select result from fn_remote_process into v_remote_process;

    -- 12.08.2018: get subsequent number of "current" ISQL session.
    -- We need this when config parameter separate_workers = 1:
    select result from fn_this_worker_seq_no into v_worker_id;

    v_storned_acc = 0;
    v_pass = 1;
    v_sign = iif( bin_and(current_transaction, 1)=0, 1, -1);

    while ( v_pass <= 2 ) do
    begin
        select r.snd_optype_id -- iif( :v_pass=1, r.snd_optype_id, r.rcv_optype_id )
        from sp_rules_for_pdistr r
        where iif( :v_pass = 1, r.rcv_optype_id, r.snd_optype_id ) = :a_optype_id
        into v_storned_doc_optype_id; -- sp_add_invoice_to_stock ==> v_storned_doc_optype_id = fn_oper_pay_to_supplier()
    
        not_storned_cost = iif( v_pass=1, :a_cost_diff, v_storned_acc);

        if ( not_storned_cost <= 0 ) then leave;

        open cp;
        while (1=1) do
        begin
            fetch cp into v_dbkey, v_id, agent_id, snd_optype_id, snd_id, cost_to_be_storned, rcv_optype_id, rcv_id;
            if ( row_count = 0 ) then leave;

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
                update pdistr set id = id where current of cp;  -- faster than 'where rdb$db_key = ...'
    
                v_storned_cost = minvalue( :not_storned_cost, :cost_to_be_storned );
        
                -- move into `storage` table *PART* of prepayment that is now storned
                -- by just created customer reserve:
                -- :: nb :: pstorned PK = (id, rcv_id) - compound!
                if ( v_pass = 1 ) then
                begin
                    insert into pstorned(
                        agent_id,
                        snd_optype_id,
                        snd_id,
                        worker_id, -- 12.08.2018
                        snd_cost,
                        rcv_optype_id,
                        rcv_id,
                        rcv_cost
                    )
                    values(
                        :agent_id,
                        :snd_optype_id,
                        :snd_id,
                        :v_worker_id,
                        :v_storned_cost,
                        :rcv_optype_id,
                        :rcv_id,
                        :v_storned_cost
                    );
                end
    
                if ( cost_to_be_storned = v_storned_cost ) then
                    delete from pdistr p where current of cp;
                else
                    -- leave this record for futher storning (it has rest of cost > 0!):
                    update pdistr p set p.snd_cost = p.snd_cost - :v_storned_cost where current of cp;
        
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
                if ( (select result from fn_is_lock_trouble( gdscode )) = 1 ) then
                    -- suppress this exc! we'll skip to next row of pdistr
                    v_skip = v_skip + 1;
                else -- some other ex`ception
                    --#######
                    exception;  -- ::: nb ::: anonimous but in when-block!
                    --#######
            end    

        end -- cursor on pdistr
        close cp;
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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_worker_id type of dm_ids;

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
    select result from fn_this_worker_seq_no into v_worker_id;

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
              ( agent_id,   snd_optype_id,   snd_id,  worker_id,      snd_cost,       rcv_optype_id )
        values( :agent_id, :snd_optype_id,  :snd_id,  :v_worker_id,   :storned_cost,   :rcv_optype_id );
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
            null,
            v_this,
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^ -- sp_kill_cost_storno


create or alter procedure srv_log_dups_qd_qs( -- need only in 3.0, SuperCLASSIC.
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
        values ( :a_unit, 'U', :a_gdscode, :v_curr_tx, :a_inserting_info, (select result from fn_get_stack( 1 )) );

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
        );

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
            and q.worker_id is not distinct from :v_worker_id
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
            and qs.worker_id is not distinct from :v_worker_id

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
            and qs.worker_id is not distinct from :v_worker_id
    );
begin
    -- Aux SP, called from sp_kill_qty_storno for
    -- 1) sp_cancel_wroff (a_deleting = 0!) or
    -- 2) all doc removals (sp_cancel_xxx, a_deleting = 1)

    v_call = v_this;
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this,null);

    select result from fn_mcode_for_oper(:a_old_optype) into v_doc_pref;
    select result from fn_oper_retail_realization into v_oper_retail_realization;
    select result from fn_this_worker_seq_no into v_worker_id;

    -- move evaluation outside from cursor loop:
    v_halt_on_pk_viol = iif( rdb$get_context('USER_SESSION','HALT_TEST_ON_ERRORS') containing '/PK/', 1, 0);


    select r.rcv_optype_id
    from rules_for_qdistr r
    where
        r.snd_optype_id = :a_old_optype
        and coalesce(r.storno_sub,1) = 1 -- nb: old_op=2000 ==> storno_sub=NULL!
    into v_old_rcv_optype;

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    -- only for logging in perf_log.info name of handling cursor:
    v_ret_cursor = iif(a_old_optype <> v_oper_retail_realization, 'c_ret_qs2qd_by_rcv', 'c_ret_qs2qd_by_snd');

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
                execute procedure sp_add_perf_log(0, v_call, null, 'deleted OK');
    
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
                if ( (select result from fn_is_uniqueness_trouble(gdscode)) = 1 ) then
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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
            and qd.worker_id is not distinct from :v_worker_id
            and qd.snd_id = :v_dd_id
    );

begin
    -- Aux SP, called from sp_kill_qty_storno ONLY for sp_reserve_write_off
    -- (change state of customer reserve to 'waybill' when wares are written-off)

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    select result from fn_mcode_for_oper(:a_new_optype) into v_doc_pref;

    select result from fn_this_worker_seq_no into v_worker_id;

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    -- return from QStorned to QDistr records which were previously moved
    -- (when currently deleting doc was created):
    for
        select d.id, r.rcv_optype_id, r.storno_sub, d.ware_id, d.qty,  d.cost_purchase
        from doc_data d
        cross join rules_for_qdistr r
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
                if ( (select result from fn_is_uniqueness_trouble(gdscode)) = 1 ) then
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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_oper_cancel_customer_order dm_idb;
    declare v_oper_invoice_get dm_idb;
    declare v_oper_invoice_add dm_idb;
    declare v_worker_id type of dm_ids;

    declare c_qd_rows_sub_1 cursor for (
        select q.id, q.snd_id
        from v_qdistr_target_1 q -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where
            q.ware_id = :v_dd_ware_id
            and q.snd_optype_id = :a_old_optype
            and q.rcv_optype_id = :v_rcv_optype_id
            and q.worker_id is not distinct from :v_worker_id
            and q.snd_id = :v_dd_id
    );
    declare c_qd_rows_sub_2 cursor for (
        select q.id, q.snd_id
        from v_qdistr_target_2 q -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where
            q.ware_id = :v_dd_ware_id
            and q.snd_optype_id = :a_old_optype
            and q.rcv_optype_id = :v_rcv_optype_id
            and q.worker_id is not distinct from :v_worker_id
            and q.snd_id = :v_dd_id
    );

    declare c_qs_rows_sub_1 cursor for (
        select qs.id, qs.snd_id
        from v_qstorned_target_1 qs  -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where 
            qs.snd_id = :v_dd_id
            and qs.worker_id is not distinct from :v_worker_id
    );
    declare c_qs_rows_sub_2 cursor for (
        select qs.id, qs.snd_id
        from v_qstorned_target_2 qs  -- this name will be replaced when config parameter create_with_split_heavy_tabs = 1
        where 
            qs.snd_id = :v_dd_id
            and qs.worker_id is not distinct from :v_worker_id
    );

begin

    -- Aux SP, called from sp_kill_qty_storno ONLY for:
    -- 1) sp_cancel_client_order; 2) sp_add_invoice_to_stock (apply and cancel)

    select result from fn_oper_cancel_customer_order into v_oper_cancel_customer_order;
    select result from fn_oper_invoice_get into v_oper_invoice_get;
    select result from fn_oper_invoice_add into v_oper_invoice_add;
    select result from fn_this_worker_seq_no into v_worker_id;

    -- add to performance log timestamp about start/finish this unit:
    v_info = iif( a_new_optype = v_oper_cancel_customer_order, 'DEL', 'UPD' )
             || ' in qdistr, doc='||a_doc_id
             || ', old_op='||a_old_optype
             || iif( a_new_optype <> v_oper_cancel_customer_order, ', new_op='||a_new_optype, '');
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    v_log_oper = iif( a_new_optype = v_oper_invoice_get, v_oper_invoice_add, a_new_optype);
    v_log_mult = iif( a_new_optype = v_oper_invoice_get, -1, 1);
    select result from fn_mcode_for_oper(:v_log_oper) into v_doc_pref;
    v_del_sign = 1; -- iif(a_new_optype = fn_oper_cancel_customer_order(), 1, 0);

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    for
        select r.rcv_optype_id, r.storno_sub
        from rules_for_qdistr r
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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_worker_id type of dm_ids; -- 12.08.2018
    declare v_dd_ware_id dm_qty;
    declare v_dd_qty dm_qty;
    declare v_dd_cost dm_qty;
    declare v_doc_pref dm_mcode;
    declare v_log_mult dm_sign;
    declare v_log_oper dm_idb;
    declare v_rcv_optype_id type of dm_idb;
    declare v_storno_sub smallint;
    declare v_oper_invoice_get dm_idb;
    declare v_oper_invoice_add dm_idb;

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
            and q.worker_id is not distinct from :v_worker_id
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


    select result from fn_oper_invoice_get into v_oper_invoice_get;
    select result from fn_oper_invoice_add into v_oper_invoice_add;
    v_log_oper = iif( a_new_optype = v_oper_invoice_get, v_oper_invoice_add, a_new_optype);
    v_log_mult = iif( a_new_optype = v_oper_invoice_get, -1, 1);
    select result from fn_mcode_for_oper(:v_log_oper) into v_doc_pref;
    select result from fn_this_worker_seq_no into v_worker_id;

    v_gen_inc_iter_nt = 1;
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt ); -- take bulk IDs at once (reduce lock-contention for GEN page)

    for
        select r.rcv_optype_id, r.storno_sub
        from rules_for_qdistr r
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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_trouble_qid bigint;
    declare v_oper_retail_realization dm_idb;
    declare v_oper_retail_reserve dm_idb;
    declare v_oper_cancel_customer_order dm_idb;
    declare v_oper_invoice_get dm_idb;
    declare v_oper_invoice_add dm_idb;
    declare v_oper_order_for_supplier dm_idb;

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

    select result from fn_oper_retail_realization into v_oper_retail_realization;
    select result from fn_oper_retail_reserve into v_oper_retail_reserve;
    select result from fn_oper_cancel_customer_order into v_oper_cancel_customer_order;
    select result from fn_oper_invoice_get into v_oper_invoice_get;
    select result from fn_oper_invoice_add into v_oper_invoice_add;
    select result from fn_oper_order_for_supplier into v_oper_order_for_supplier;
    select result from fn_oper_retail_reserve into v_oper_retail_reserve;

    if ( a_updating = 1 and a_new_optype is distinct from a_old_optype ) then
    begin
        ----------------   c h a n g e    o p t y p e _ i d   ------------------
        -- see s`p_cancel_client_order; sp_add_invoice_to_stock;
        -- sp_reserve_write_off, s`p_cancel_write_off
        -- ==> they all change doc_data.optype_id
        if ( a_new_optype = v_oper_cancel_customer_order) then
            begin
                -- S P _ C A N C E L _ C L I E N T _ O R D E R
                -- Kill all records for this doc both in QDistr & QStorned
                -- delete rows in qdistr for currently cancelled client order:
                execute procedure sp_qd_handle_on_cancel_clo( :a_doc_id, :a_old_optype, :v_oper_cancel_customer_order );
            end

        else if ( a_old_optype = v_oper_retail_realization and a_new_optype = v_oper_retail_reserve ) then
            -- S P _ C A N C E L _ W R I T E _ O F F
            -- return from QStorned to QDistr records which were previously moved
            -- (when currently deleting doc was created):
            execute procedure sp_ret_qs2qd_on_canc_wroff( :a_doc_id, :a_old_optype, :a_deleting );
            -- prev: direct call execute procedure s~p_kill_qstorno_ret_qs2qd( :a_doc_id, :a_old_optype, :a_deleting );

        else if ( a_old_optype = v_oper_retail_reserve and a_new_optype = v_oper_retail_realization ) then
            -- S P _ R E S E R V E _ W R I T E _ O F F
            execute procedure sp_qd_handle_on_reserve_upd_sts( :a_doc_id, :a_old_optype, :a_new_optype );
            -- prev: direct call of s~p_kill_qstorno_mov_qd2qs( :a_doc_id, :a_old_optype, :a_new_optype);

        else -- all other updates of doc state, except s`p_cancel_write_off
            -- update rows in qdistr for currently selected doc (3dr arg <> fn_oper_cancel_cust_order):    
            if ( a_old_optype = v_oper_invoice_get ) then
                -- S P _ A D D _ I N V O I C E _ T O _ S T O C K
                execute procedure sp_qd_handle_on_invoice_adding( :a_doc_id, :a_old_optype, :a_new_optype );
            else if ( a_old_optype = v_oper_invoice_add ) then
                -- S P _ C A N C E L _ A D D I N G _ I N V O I C E
                execute procedure sp_qd_handle_on_invoice_reopen( :a_doc_id, :a_old_optype, :a_new_optype );
            else
                exception ex_bad_argument; -- using(':a_old_optype='||:a_old_optype, v_this );
            -- before: execute procedure s~p_kill_qstorno_handle_qd4dd( :a_doc_id, :a_old_optype, :a_new_optype );

    end -- a_updating = 1 and a_new_optype is distinct from a_old_optype

    if ( a_deleting = 1 ) then -- all cancel ops
    begin
        -- return from QStorned to QDistr records which were previously moved
        -- (when currently deleting doc was created):
        if ( a_old_optype = v_oper_invoice_get ) then
            execute procedure sp_ret_qs2qd_on_canc_invoice( :a_doc_id, :a_old_optype, :a_deleting );
        else if ( a_old_optype = v_oper_order_for_supplier ) then
            execute procedure sp_ret_qs2qd_on_canc_supp_order( :a_doc_id, :a_old_optype, :a_deleting );
        else if ( a_old_optype = v_oper_retail_reserve ) then
            begin
                execute procedure sp_ret_qs2qd_on_canc_res_aux( :a_doc_id, :a_old_optype, :a_deleting );
                execute procedure sp_ret_qs2qd_on_canc_reserve( :a_doc_id, :a_old_optype, :a_deleting );
            end
        else
            exception ex_bad_argument; -- using(':a_old_optype='||:a_old_optype, v_this );
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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_worker_id type of dm_ids;
    declare v_rows int = 0; -- 18.12.2018

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

    v_dd_mismatch_id = null;
    -- This value is used in CURSOR c_dd_qty_match_qd_qs_counts as argument of join:
    v_snd_optype_id = iif(:a_optype_id=3400, 3300, :a_optype_id);

    select result from fn_this_worker_seq_no into v_worker_id;

    select r.rcv_optype_id
    from rules_for_qdistr r
    where r.snd_optype_id = :a_optype_id and coalesce(r.storno_sub,1)=1
    into v_rcv_optype_id;

    if ( a_after_deleting_doc = 1 ) then -- call after doc has been deleted: NO rows in doc_data but we must check orphan rows in qd&qs for this doc!
        begin
            select h.id from doc_list h where h.id = :a_doc_list_id into v_dh_id;
            if ( v_dh_id is NOT null or not exists(select * from tmp$result_set)  ) then
                exception ex_bad_argument; -- using('a_after_deleting_doc', v_this) ; -- 'argument @1 passed to unit @2 is invalid';

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
                    -- Added only 18.12.2018 :(
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
            exception ex_orphans_qd_qs_found;
            -- 'at least one row found for DELETED doc id=@1, snd_id=@2: @3.id=@4';
        else
            exception ex_mism_doc_data_qd_qs;
            -- at least one mismatch btw doc_data.id=@1 and qdistr+qstorned: qty=@2, qd_cnt=@3, qs_cnt=@4
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
            (select result from fn_halt_sign(:v_gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --########
        exception;  -- ::: nb ::: anonimous but in when-block!
        --########
    end
end

^ -- srv_find_qd_qs_mism

set term ;^
commit;
set term ^;

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
    declare v_oper_invoice_add dm_idb;
    declare v_oper_invoice_get dm_idb;
    declare v_oper_retail_reserve dm_idb;
    declare v_oper_order_for_supplier dm_idb;
    declare v_worker_id type of dm_ids;
begin

    v_info = 'base_doc='||a_base_doc_id;
    execute procedure sp_add_perf_log(1, v_this, null, v_info);

    select result from fn_oper_invoice_add into v_oper_invoice_add;
    select result from fn_oper_retail_reserve into v_oper_retail_reserve;
    select result from fn_oper_order_for_supplier into v_oper_order_for_supplier;
    select result from fn_oper_invoice_get into v_oper_invoice_get;
    select result from fn_this_worker_seq_no into v_worker_id;

    if ( a_base_doc_oper_id is null ) then
        select h.optype_id
        from doc_list h
        where h.id = :a_base_doc_id
        into a_base_doc_oper_id;

    v_rcv_optype_id = decode(a_base_doc_oper_id,
                             v_oper_invoice_add,  v_oper_retail_reserve,
                             v_oper_order_for_supplier, v_oper_invoice_get,
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
                and q.worker_id is not distinct from :v_worker_id
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
              if ( (select result from fn_is_uniqueness_trouble(gdscode) ) = 0 ) then exception;
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
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_lock_dependent_docs

-- 29.07.2014: STUB, need for debug view z_invoices_to_be_adopted, will be redefined in oltp25_sp.sql:
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

    v_msg ='dh='||:a_doc_list_id || ', op='||(select result from fn_mcode_for_oper( :a_optype_id ) );

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
            execute procedure sp_halt_on_error('5', :c_chk_violation_code, :v_curr_tx); -- temply
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
        exception ex_neg_remainders_encountered; -- using( v_id, v_info ); -- 'at least one remainder < 0, ware_id=@1';
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

-- 07.09.2015: probe to replace ES in all cases of fn_get_rand_id:
create or alter view name$to$substutite$min$id$ as select 1 id from rdb$database;
create or alter view name$to$substutite$max$id$ as select 1 id from rdb$database;
create or alter view name$to$substutite$search$ as select 1 id from rdb$database;

create or alter view v_cancel_client_order as
-- source for random choose client_order document to be cancelled
select h.id
from doc_list h
where
    h.optype_id = 1000 -- fn_oper_order_by_customer
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
;

create or alter view v_cancel_supplier_order as
-- Source for random choose supplier order doc to be cancelled
select h.id
from doc_list h
where
    h.optype_id = 1200 -- fn_oper_order_for_supplier
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
;


create or alter view v_cancel_supplier_invoice as
-- source for random choose invoice from supplier that will be cancelled
select h.id
from doc_list h
where
    h.optype_id = 2000 -- fn_oper_invoice_get
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
;

create or alter view v_add_invoice_to_stock as
select h.id
from doc_list h
where
    h.optype_id = 2000 -- fn_oper_invoice_get
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
;

create or alter view v_cancel_adding_invoice as
select h.id
from doc_list h
where
    h.optype_id = 2100 -- fn_oper_invoice_add
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
;

create or alter view v_reserve_write_off as
-- source for random take customer reserve and make WRITE-OFF (i.e. 'close' it):
select h.id, h.agent_id, h.state_id, h.dts_open, h.dts_clos, h.cost_retail
from doc_list h
where
    h.optype_id = 3300 -- fn_oper_retail_reserve
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
;

create or alter view v_cancel_payment_to_supplier as
-- source for random taking INVOICE with some payment and CANCEL all payments:
select h.id, h.agent_id, h.cost_purchase
from doc_list h
where
    h.optype_id = 4000 -- fn_oper_pay_to_supplier
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
;

create or alter view v_cancel_customer_prepayment as
select h.id, h.agent_id, h.cost_retail
from doc_list h
where
    h.optype_id = 5000 -- fn_oper_pay_from_customer
    -- 12.08.2018: sequential number of ISQL session that queries this view.
    -- This filter is added with purpose to reduce number of lock-conflict errors:
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
-- plan in 2.5 (checked 02.12.2014):
-- (C INDEX (TMP_SHOPCART_UNQ))
-- (A NATURAL)
-- ::: NB ::: do NOT use `order by c.id` in exists(), this lead to *BAD* plan:
-- C ORDER TMP_SHOPCART_UNQ INDEX (TMP_SHOPCART_UNQ)) // not fixed in 2.5, only in 3.0
select a.id
from wares a
where not exists(select * from tmp$shopping_cart c where c.id = a.id)
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
-- plan in 2.5 (checked 02.12.2014):
-- (C INDEX (TMP_SHOPCART_UNQ))
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W NATURAL)
select w.id
from wares w
where
    not exists(select * from tmp$shopping_cart c where c.id = w.id) -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by c.id)
    and exists(
        select * from qdistr q
        where
            q.ware_id = w.id
            and q.snd_optype_id = 2100
            and q.rcv_optype_id = 3300
            -- 12.08.2018: sequential number of ISQL session that queries this view.
            -- This filter is added with purpose to reduce number of lock-conflict errors:
            and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
    );

create or alter view v_min_id_avl_res
as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choose ware_id in sp_customer_reserve => sp_fill_shopping_cart:
-- take record from invoice which has been added to stock and add it to set for
-- new customer reserve - from ***AVALIABLE*** remainders (not linked with client order)
-- plan in 2.5 (checked 02.12.2014):
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W ORDER PK_WARES)
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
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
        )
    order by w.id -- ascend, we search for MINIMAL id
    rows 1
;


create or alter view v_max_id_avl_res
as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choose ware_id in sp_customer_reserve => sp_fill_shopping_cart:
-- take record from invoice which has been added to stock and add it to set for
-- new customer reserve - from avaliable remainders
-- plan in 2.5 (checked 02.12.2014):
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W ORDER WARES_ID_DESC)
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
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
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
-- plan in 2.5 (checked 02.12.2014):
-- (C INDEX (TMP_SHOPCART_UNQ))
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W NATURAL)
select w.id
from wares w
where
    not exists(select * from tmp$shopping_cart c where c.id = w.id) -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by c.id)
    and exists(
        select * from qdistr q
        where
            q.ware_id = w.id
            and q.snd_optype_id = 1000
            and q.rcv_optype_id = 1200
            -- 12.08.2018: sequential number of ISQL session that queries this view.
            -- This filter is added with purpose to reduce number of lock-conflict errors:
            and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
        -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
    );

create or alter view v_min_id_clo_ord as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
-- plan in 2.5 (checked 02.12.2014):
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W ORDER PK_WARES)
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
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
        )
    order by w.id  -- ascend, we search for MINIMAL id
    rows 1
;

create or alter view v_max_id_clo_ord as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from client order to be added into supplier order
-- plan in 2.5 (checked 02.12.2014):
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
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
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
-- plan in 2.5 (checked 02.12.2014):
-- (C INDEX (TMP_SHOPCART_UNQ))
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W NATURAL)
    select w.id
    from wares w
    where
        not exists(select * from tmp$shopping_cart c where c.id = w.id) -- 02.12.2014 wrong in 2.5 (use only in 3.0):  order by c.id)
        and exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1200 -- fn_oper_order_for_supplier()
                and q.rcv_optype_id = 2000
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
        )
;

create or alter view v_min_id_ord_sup as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from supplier order to be added into invoice by him
-- plan in 2.5 (checked 02.12.2014):
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W ORDER PK_WARES)
    select w.id
    from wares w
    where
        exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1200 -- fn_oper_order_for_supplier()
                and q.rcv_optype_id = 2000
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
        )
    order by id  -- ascend, we search for MINIMAL id
    rows 1
;

create or alter view v_max_id_ord_sup as
-- 08.07.2014. used in dynamic sql in sp_get_random_id, see it's call in sp_fill_shopping_cart
-- source for random choise record from supplier order to be added into invoice by him
-- plan in 2.5 (checked 02.12.2014):
-- (Q INDEX (QDISTR_WARE_SNDOP_RCVOP))
-- (W ORDER WARES_ID_DESC)
    select w.id
    from wares w
    where
        exists(
            select * from qdistr q
            where
                q.ware_id = w.id
                and q.snd_optype_id = 1200 -- fn_oper_order_for_supplier()
                and q.rcv_optype_id = 2000
                -- 12.08.2018: sequential number of ISQL session that queries this view.
                -- This filter is added with purpose to reduce number of lock-conflict errors:
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- 02.12.2014 wrong in 2.5 (use only in 3.0): order by ware_id, snd_optype_id, rcv_optype_id -- supress building index bitmap on QDistr!
        )
    order by id desc -- descend, we search for MAXIMAL id
    rows 1
;

-- ############## C L O => R E S ###############
-- Views for operation 'Create reserve based on client order'
-- #############################################

create or alter view v_random_find_clo_res as
-- plan in 2.5 (checked 11.01.2019):
-- PLAN (FN_THIS_WORKER_SEQ_NO NATURAL)
-- PLAN (FN_THIS_WORKER_SEQ_NO NATURAL)
-- PLAN (Q INDEX (QDISTR_WARE_SOP_ROP_WKR_SND))
-- PLAN (D INDEX (FK_DOC_DATA_DOC_LIST))
-- 7PLAN (H INDEX (DOC_LIST_WORKER_OPTYPE))
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
        and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
                    and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
                -- prevent from building bitmap, 3.0 only:
                --order by q.ware_id, q.snd_optype_id, q.rcv_optype_id
            )
            --order by d.doc_id -- prevent from building bitmap, 3.0 only
        )
;

-------------------------------------------------------------------------------

create or alter view v_min_id_clo_res as
-- plan in 2.5 (checked 11.01.2019):
-- PLAN (FN_THIS_WORKER_SEQ_NO NATURAL)
-- PLAN (FN_THIS_WORKER_SEQ_NO NATURAL)
-- PLAN (Q INDEX (QDISTR_WARE_SOP_ROP_WKR_SND))
-- PLAN (D INDEX (FK_DOC_DATA_DOC_LIST))
-- PLAN (H ORDER PK_DOC_LIST INDEX (DOC_LIST_WORKER_OPTYPE))
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
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
                -- prevent from building bitmap, 3.0 only:
                -- do NOT use in 2.5: order by q.ware_id, q.snd_optype_id, q.rcv_optype_id
        )
        -- prevent from building bitmap, 3.0 only
        -- do NOT use in 2.5: order by d.doc_id
    )
    order by h.id
    rows 1
;

-------------------------------------------------------------------------------

create or alter view v_max_id_clo_res as
-- plan in 2.5 (checked 11.09.2015):
-- PLAN (FN_THIS_WORKER_SEQ_NO NATURAL)
-- PLAN (FN_THIS_WORKER_SEQ_NO NATURAL)
-- PLAN (Q INDEX (QDISTR_WARE_SOP_ROP_WKR_SND))
-- PLAN (D INDEX (FK_DOC_DATA_DOC_LIST))
-- PLAN (H ORDER DOC_LIST_ID_DESC INDEX (DOC_LIST_WORKER_OPTYPE))
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
    and h.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
                and q.worker_id is not distinct from (select result from fn_this_worker_seq_no)
            -- prevent from building bitmap, 3.0 only:
            -- do NOT use in 2.5: order by q.ware_id, q.snd_optype_id, q.rcv_optype_id
        )
        -- prevent from building bitmap, 3.0 only:
        -- do NOT use in 2.5: order by d.doc_id
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
    and p.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
    and p.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
    and p.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
    and p.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
    and p.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
    and p.worker_id is not distinct from (select result from fn_this_worker_seq_no)
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
join optypes o on ng.optype_id = o.id
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
commit;

-------------------------------------------------------------------------------

create or alter view z_estimated_perf_per_minute as
-- Do NOT delete! 28.10.2015.
-- This view is used in oltp_isql_run_worker.bat (.sh) when it creates final report.
-- Table PERF_ESTIMATED is filled up by temply created .sql which scans log
-- of 1st ISQL session (which, in turn, makes final report). This log contains
-- rows like this:
-- EST_OVERALL_AT_MINUTE_SINCE_BEG         0.00      0
-- - where 1st number is estimated performance value and 2nd is datediff(minute)
-- from test start to the moment when each business transaction SUCCESSFULLY finished.
-- Data in this view is performance value in *dynamic* but with detalization per
-- ONE minute, from time when all ISQL sessions start (rather then all other reports
-- which make starting point after database was warmed up).
-- This report can help to find proper value of warm-time in oltpNN_config.
select
    e.minute_since_test_start
    ,avg(e.success_count) avg_estimated
    ,min(e.success_count) / nullif(avg(e.success_count), 0) min_to_avg_ratio
    ,max(e.success_count) / nullif(avg(e.success_count), 0) max_to_avg_ratio
    ,count(e.success_count) rows_aggregated
    ,count(distinct e.att_id) distinct_attachments -- 22.12.2015: helps to ensure that all ISQL sessions were alive in every minute of test work time
from perf_estimated e
where e.minute_since_test_start>0
group by e.minute_since_test_start
;

commit;

-------------------------------------------------------------------------------
--######################   d e b u g    v i e w s   ############################
-------------------------------------------------------------------------------

-- Following view were moved in 'oltp_common_sp.sql', 23.11.2018:
-- create or alter view z_current_test_settings
-- create or alter view z_settings_pivot
-- create or alter view z_qd_indices_ddl
-- create or alter view z_halt_log

--------------------------------------------------------------------------------
-- create or alter view z_agents_tunrover_saldo as
-- n/a here (uses windowed functions), see in FB 3.0
--------------------------------------------------------------------------------

commit;


--------------------------------------------------------------------------------
-- ########################   T R I G G E R S   ################################
--------------------------------------------------------------------------------

set term ^;
create or alter trigger wares_bi for wares active
before insert position 0
as
begin
   new.id = coalesce(new.id, gen_id(g_common, 1) );
end
^

create or alter trigger phrases_bi for phrases active
before insert position 0
as
begin
   new.id = coalesce(new.id, gen_id(g_common, 1) );
end
^

create or alter trigger agents_bi for agents active
before insert position 0
as
begin
   new.id = coalesce(new.id, gen_id(g_common, 1) );
end
^

create or alter trigger invnt_saldo_bi for invnt_saldo active
before insert position 0
as
begin
   new.id = coalesce(new.id, gen_id(g_common, 1) );
end
^

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

create or alter trigger pdistr_bi for pdistr
active before insert position 0 as
begin
    new.id = coalesce(new.id, gen_id(g_common,1));
end

^ -- pdistr_bi

create or alter trigger mon_memory_consumption_bi for mon_memory_consumption
active before insert position 0 as
begin
    new.id = coalesce(new.id, gen_id(g_common,1));
end

^ -- mon_memory_consumption_bi

create or alter trigger mon_cache_memory_bi for mon_cache_memory
active before insert position 0 as
begin
    new.id = coalesce(new.id, gen_id(g_common,1));
end

^ -- mon_memory_consumption_bi


create or alter trigger pstorned_bi for pstorned
active before insert position 0 as
begin
    new.id = coalesce(new.id, gen_id(g_common,1));
end

^ -- pstorned_bi

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
        new.state_id = coalesce(new.state_id, (select result from fn_doc_open_state) );
        -- 'i'=incoming; 'o' = outgoing; 's' = payment to supplier; 'c' = payment from customer
        new.acn_type = (select o.acn_type from optypes o where o.id = new.optype_id);
        v_msg = v_msg || ' new.id='||new.id||', acn_type='||coalesce(new.acn_type,'<?>');
    end

    if ( not deleting ) then
        begin
            if ( new.state_id <> (select result from fn_doc_open_state) ) then
            begin
                new.dts_fix = coalesce(new.dts_fix, 'now');
                new.dts_clos = iif( new.state_id in( (select result from fn_doc_clos_state), (select result from fn_doc_canc_state) ), 'now', null);
            end
            if ( new.state_id = (select result from fn_doc_open_state) ) then -- 31.03.2014
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

    select max(maxvalue(abs(o.m_qty_clo), abs(o.m_qty_clr), abs(o.m_qty_ord), abs(o.m_qty_sup), abs(o.m_qty_avl), abs(o.m_qty_res))) q_mult_abs_max
    from optypes o
    where o.id in( :v_old_op, :v_new_op )
    into v_affects_on_inventory_balance;

    -- 20.09.2014 1825: remove calls of s`p_add_invnt_log to SPs (reduce scans of doc_data)
    -- 16.09.2014: moved here from d`oc_data_biud:
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
            (select result from fn_halt_sign(gdscode) ) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
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
    declare v_oper_retail_realization dm_idb;
    declare v_cost_diff type of dm_cost;
    declare v_msg type of dm_info = '';
    declare v_this dm_dbobj = 'doc_list_aiud';
    declare v_catch_bitset bigint;
begin

    -- AFTER trigger on master table (THIS) will fired BEFORE any triggers on detail (doc_data)!
    -- www.sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1081231&msg=15685218
    v_affects_on_monetary_balance = 1;
    v_affects_on_inventory_balance = 1;
    v_doc_id=iif(deleting, old.id, new.id);
    v_old_op=iif(inserting, null, old.optype_id);
    v_new_op=iif(deleting,  null, new.optype_id);
    select result from fn_oper_retail_realization into v_oper_retail_realization;
    v_msg = 'dh='|| iif(not inserting, old.id, new.id)
             || ', op='||iif(inserting,'INS',iif(updating,'UPD','DEL'))
             || iif(not inserting, ' old='||old.optype_id, '')
             || iif(not deleting,  ' new='||new.optype_id, '');

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log( 1, v_this , null, v_msg );

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

    ---------------
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
                       -- AFTER trigger on master table (THIS) will fired BEFORE any triggers on detail (doc_data)!
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
            (select result from fn_halt_sign( gdscode )) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- doc_list_aiud

-------------------------------------------------------------------------------

-- NOTE: currently tis trigger is created with INactive state.
-- It will be Active at the end of all database building process, see 'oltp_data_filling.sql'
create or alter trigger trg_connect inactive on connect as
begin
    execute procedure sp_init_ctx;
    if ( rdb$get_context ('SYSTEM', 'NETWORK_PROTOCOL') is null ) then
    begin
       insert into perf_log(unit, info )
       values( 'trg_connect', 'attach using NON-TCP protocol' );
    end
end

^ -- trg_connect

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
    insert into doc_list(
        id, -- 06.09.2014 2200
        worker_id, -- 12.08.2018
        optype_id,
        agent_id,
        state_id,
        base_doc_id,
        cost_purchase,
        cost_retail
    )
    values(
        coalesce(:a_gen_id, gen_id(g_common,1)),
        (select result from fn_this_worker_seq_no),
        :a_optype_id,
        :a_agent_id,
        :a_new_state,
        :a_base_doc_id,
        :a_new_cost_purchase,
        :a_new_cost_retail
    )
    returning id, rdb$db_key
    into id, dbkey;

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
            ,(select result from fn_mcode_for_oper(:a_optype_id))
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
            (select result from  fn_halt_sign(gdscode) ) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_add_doc_data

create or alter procedure fn_get_random_quantity(
    a_ctx_max_name dm_ctxnv
)
returns (result dm_qty)
as
    declare v_min double precision;
    declare v_max double precision;
begin
  v_min = 0.5;
  v_max = cast( rdb$get_context('USER_SESSION',a_ctx_max_name) as int) + 0.5;
  result = cast( v_min + rand()* (v_max - v_min)  as int);
  suspend;
end

^ -- fn_get_random_quantity

create or alter procedure fn_get_random_cost(
    a_ctx_min_name dm_ctxnv,
    a_ctx_max_name dm_ctxnv,
    a_make_check_before smallint default 1
)
returns (result dm_cost)
as
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
  result = cast( v_min + rand()* (v_max - v_min)  as dm_cost);
  suspend;

end

^ -- fn_get_random_cost

create or alter procedure fn_get_random_customer returns (result bigint) as
begin
    select result from sp_get_random_id('v_all_customers', null, null, 0) into result;
    suspend;
end

^

create or alter procedure fn_get_random_supplier returns (result bigint) as
begin
     select result from sp_get_random_id('v_all_suppliers', null, null, 0) into result;
     suspend;
end

^ -- fn_get_random_customer

------------------------------------------------------------------------------
set term ;^
commit;
set term ^;

create or alter procedure sp_make_qty_storno (
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
    declare v_worker_id type of dm_ids;

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
                INNER join rules_for_qdistr r
                  on :a_client_order_id is NOT null
                     -- ...= r.rcv_optype_id + 0 ==> PLAN MERGE (SORT (R NATURAL), SORT (C NATURAL))
                     -- ...= r.rcv_optype_id  ==> PLAN JOIN (C NATURAL, R INDEX (RULES_FOR_QDISTR_RCVOP))
                     and c.rcv_optype_id = r.rcv_optype_id
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
    from rules_for_qdistr r
    where r.snd_optype_id = :a_optype_id
    into v_next_rcv_op;

    select result from fn_this_worker_seq_no into v_worker_id;

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
                -- We can move delete sttmt BEFORE insert because of using explicit cursor and
                -- fetch old fields data (which is to be moved into QStorned) into declared vars:
                if ( v_storno_sub = 1 ) then
                    begin
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            v_call = v_this || ':try_del_qdsub1';
                            execute procedure sp_add_perf_log(1, v_call, null, v_info); -- 10.02.2015
                            rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_TRY_DEL_QD_ID', v_cq_id);
                        end
    
                        delete from v_qdistr_source_1 q where current of c_make_amount_distr_1; --- lock_conflict can occur here
    
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_OK_DEL_QD_ID', v_cq_id);
                            execute procedure sp_add_perf_log(0, v_call, null, 'c_make_amount_distr_1: deleted OK');
                        end
                    end --  v_storno_sub = 1
                else
                    begin
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            v_call = v_this || ':try_del_qdsub2';
                            execute procedure sp_add_perf_log(1, v_call, null, v_info);
                            rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB2_TRY_DEL_QD_ID', v_cq_id);
                        end
    
                        -- When config parameter 'create_with_split_heavy_tabs' is 1 then 'v_qdistr_source_2' should be changed to 'XQD_*'
                        delete from v_qdistr_source_2 q where current of c_make_amount_distr_2; --- lock_conflict can occur here
    
                        if ( v_halt_on_pk_viol = 1) then
                        begin
                            rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB2_OK_DEL_QD_ID', v_cq_id);
                            execute procedure sp_add_perf_log(0, v_call, null, 'c_make_amount_distr_2: deleted ok');
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
                        rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_TRY_INS_QD_ID', v_id);
                    end
    
                    insert into v_qdistr_target_1 (
                        id,
                        doc_id,
                        worker_id, -- 12.08.2018
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
                        rdb$set_context('USER_TRANSACTION','DBG_MAKE_STSUB1_OK_INS_QD_ID', v_id);
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
                    rdb$set_context('USER_TRANSACTION','DBG_MAKE_QSTORN_TRY_INS_QS_ID', v_id);
                end
    
                if ( v_storno_sub = 1 )  then
                    insert into v_qstorned_target_1 (
                         id,
                         doc_id, 
                         worker_id,
                         ware_id, dts, -- do NOT specify field `trn_id` here! 09.10.2014 2120
                         snd_optype_id, snd_id, snd_qty,
                         rcv_optype_id,
                         rcv_doc_id, -- 30.12.2014
                         rcv_id,
                         snd_purchase, snd_retail
                    ) values (
                        :v_id
                        ,:v_cq_snd_list_id,
                        :v_worker_id,
                        :v_ware_id, :v_cq_dts -- dis 09.10.2014 2120: :v_cq_trn_id,
                        ,:v_cq_snd_optype_id, :v_cq_snd_data_id,:v_cq_snd_qty
                        ,:v_cq_rcv_optype_id
                        ,:v_dh_new_id -- 30.12.2014
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
                        rcv_doc_id, -- 30.12.2014
                        rcv_id,
                        snd_purchase, snd_retail
                    ) values (
                        :v_id
                        ,:v_cq_snd_list_id,
                        :v_worker_id,
                        :v_ware_id, :v_cq_dts -- dis 09.10.2014 2120: :v_cq_trn_id,
                        ,:v_cq_snd_optype_id, :v_cq_snd_data_id,:v_cq_snd_qty
                        ,:v_cq_rcv_optype_id
                        ,:v_dh_new_id -- 30.12.2014
                        ,:v_dd_new_id
                        ,:v_cq_snd_purchase,:v_cq_snd_retail
                    );
    
    
                if ( v_halt_on_pk_viol = 1) then
                begin
                    rdb$set_context('USER_TRANSACTION','DBG_MAKE_QSTORN_OK_INS_QS_ID', v_id);
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
                if ( (select result from fn_is_lock_trouble(gdscode)) = 1 ) then
                    -- suppress this kind of exc`eption and
                    -- skip to next record!
                    v_skip = v_skip + 1;
                else
                    begin
                        -- ###############################################
                        -- PK violation on INSERT INTO QSTORNED, log this:
                        -- ###############################################
                        if ( (select result from fn_is_uniqueness_trouble(gdscode)) = 1 ) then
                            -- 12.02.2015: the reason of PK violations is unpredictable order
                            -- of UNDO, ultimately explained by dimitr, see letters in e-mail.
                            -- Also: sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1142271&msg=17257984
                            execute procedure srv_log_dups_qd_qs( -- add log info in auton Tx
                                :v_this,
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

    end -- cursor on tmp$shopping_cart c [join rules_for_qdistr r]
    close c_shop_cart;


    if ( :doc_list_id is NOT null and v_rows_added > 0) then --  v_lock > 0 ) then
        begin
            -- single update of doc header (not for every row added in doc_data)
            -- Trigger d`oc_list_aiud will call sp_add_invnt_log to add rows to invnt_turnover_log
            update doc_list h set
                h.cost_purchase = :v_doc_list_purchase_sum,
                h.cost_retail = :v_doc_list_retail_sum,
                h.dts_fix = iif( :a_state_id = (select result from fn_doc_fix_state), 'now', h.dts_fix)
            where h.rdb$db_key = :v_doc_list_dbkey;

        end -- ( :doc_list_id is NOT null )
    else
        begin
            v_info =
                (select result from fn_mcode_for_oper(:a_optype_id))
                ||iif(a_optype_id = (select result from fn_oper_retail_reserve), ', clo='||coalesce( a_client_order_id, '<null>'), '')
                ||',  rows in tmp$cart: '||(select count(*) from tmp$shopping_cart);
    
            if ( a_client_order_id is null ) then -- ==> all except call of sp_customer_reserve for client order
                exception ex_cant_find_row_for_qdistr; -- using( a_optype_id, (select count(*) from tmp$shopping_cart) );
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
            (select result from fn_halt_sign(gdscode) ) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_make_qty_storno

set term ;^
commit;
set term ^;
------------------------------------------------------------------------------

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
            exception ex_record_not_found ; -- using ('BUSINESS_OPS', '"' || trim( substring( v_prev from 81 ) ) || '"' );
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
    declare v_last_recalc_idx_dts timestamp;
    declare v_dts_beg timestamp;
    declare v_last_recalc_idx_minutes_ago int;
    declare v_this dm_dbobj = 'srv_random_unit_choice';
    declare c_unit_for_mon_query dm_dbobj = 'srv_fill_mon'; -- do NOT change the name of thios SP!
    declare fn_internal_enable_mon_query smallint;
begin
    fn_internal_enable_mon_query = 0; -- always in 2.5;  in 3.0: cast(rdb$get_context('USER_SESSION', 'ENABLE_MON_QUERY') as smallint)
    -- refactored 18.07.2014 (for usage in init data pop)
    -- sample: select * from srv_random_unit_choice( '','creation,state_next','','removal' )
    -- (will return first randomly choosen record related to creation of document
    -- or to changing its state in 'forward' way; excludes all cancellations and change
    -- doc states in 'backward')
    a_included_modes = coalesce( a_included_modes, '');
    a_included_kinds = coalesce( a_included_kinds, '');
    a_excluded_modes = coalesce( a_excluded_modes, '');
    a_excluded_kinds = coalesce( a_excluded_kinds, '');

-- disabled 14.10.2018: perf_log now is replaced with V_pref_log ("unioned" view),
-- and its underlied tables (perf_split_NN) have no index on field 'unit' (due to possible performance issues!)
--    select g.dts_beg
--    from perf_log g where g.unit = 'srv_recalc_idx_stat'
--    order by g.dts_beg desc rows 1
--    into v_last_recalc_idx_dts;

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
        a_included_kinds = 'creation,state_next';
        a_excluded_kinds = 'removal';
    end

--    if ( rdb$get_context('USER_SESSION','PERF_WATCH_BEG')is not null ) then -- see SP_CHECK_TO_STOP_WORK
--        v_last_recalc_idx_dts = maxvalue(v_last_recalc_idx_dts, cast(rdb$get_context('USER_SESSION','PERF_WATCH_BEG') as timestamp) );
--
--    v_last_recalc_idx_minutes_ago = coalesce( datediff(minute from v_last_recalc_idx_dts to cast('now' as timestamp)), cast( rdb$get_context('USER_SESSION', 'RECALC_IDX_MIN_INTERVAL') as int ) );

    r_max = rdb$get_context('USER_SESSION', 'BOP_RND_MAX');
    if ( r_max is null ) then
    begin
        select max( b.random_selection_weight ) from business_ops b into r_max;
        rdb$set_context('USER_SESSION', 'BOP_RND_MAX', r_max);
    end

    r=rand()*r_max;
    delete from tmp$perf_log p where p.stack = :v_this;

    insert into tmp$perf_log(unit, aux1, aux2, stack)
    select o.unit, o.sort_prior, o.random_selection_weight, :v_this
    from business_ops o
    where o.random_selection_weight >= :r
        and (:fn_internal_enable_mon_query = 1 or o.unit <> :c_unit_for_mon_query) -- do NOT choose srv_fill_mon if mon query disabled
-- disabled 14.10.2018: perf_log now is replaced with V_pref_log ("unioned" view),
-- and its underlied tables (perf_split_NN) have no index on field 'unit' (due to possible performance issues!)
-- Decided to reduce frequency by assigned low value for probability of srv_recalc_idx_stat calls.
--        and ( -- 27.11.2015: skip call of index statistics recalc if it was done not so far:
--                o.unit <> 'srv_recalc_idx_stat'
--                or
--                o.unit = 'srv_recalc_idx_stat'
--                and
--                    :v_last_recalc_idx_minutes_ago
--                    >=
--                    cast( rdb$get_context('USER_SESSION', 'RECALC_IDX_MIN_INTERVAL') as int )
--            )
        and (:a_included_modes = '' or :a_included_modes||',' containing trim(o.mode)||',' )
        and (:a_included_kinds = '' or :a_included_kinds||',' containing trim(o.kind)||',' )
        and (:a_excluded_modes = '' or :a_excluded_modes||',' NOT containing trim(o.mode)||',' )
        and (:a_excluded_kinds = '' or :a_excluded_kinds||',' NOT containing trim(o.kind)||',' )
    ;
    c = row_count;
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

create or alter procedure sys_get_proc_ddl (
    a_func varchar(31),
    a_mode smallint = 1,
    a_include_setterm smallint = 1)
returns (
    src varchar(32760))
as
begin
    -- STUB! Actual code see in 'oltp_common.sql'
    suspend;
end
^ -- sys_get_proc_ddl // STUB

create or alter procedure sys_get_func_ddl (
    a_func varchar(31),
    a_mode smallint = 1,
    a_include_setterm smallint = 1)
returns (
    src varchar(32760))
as
begin
    -- redirector in 2.5; NB! this SP is called from 'oltp_split_heavy_tabs_1.sql'
    for
        select src from sys_get_proc_ddl( :a_func, :a_mode, :a_include_setterm )
        into src
    do
        suspend;
end

^ -- sys_get_func_ddl

create or alter procedure fn$get$random$id$subst$names (
    a_view_for_search dm_dbobj,
    a_view_for_min_id dm_dbobj default null,
    a_view_for_max_id dm_dbobj default null,
    a_raise_exc dm_sign default 1, -- raise exc`eption if no record will be found
    a_can_skip_order_clause dm_sign default 0, -- 17.07.2014 (for some views where document is taken into processing and will be REMOVED from scope of this view after Tx is committed)
    a_find_using_desc_index dm_sign default 0  -- 11.09.2014: if 1, then query will be: "where id <= :a order by id desc"
)
returns (result bigint)
as

    declare i smallint;
    declare v_stt varchar(255);
    declare id_min double precision;
    declare id_max double precision;
    declare v_rows int;
    declare id_random bigint;
    declare id_selected bigint = null;
    declare msg dm_info;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'fn_get_random_id';
    declare v_ctxn dm_ctxnv;
    declare v_name dm_dbobj;
    declare fn_internal_max_rows_usage int;
    declare v_is_known smallint = 0;
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
    fn_internal_max_rows_usage = cast( rdb$get_context('USER_SESSION','RANDOM_SEEK_VIA_ROWS_LIMIT') as int);

    -- Use either stub or non-empty executing code (depends on was 'oltp_dump.sql' compiled or no):
    -- save fact of usage views in the table `z_used_views`:
    execute procedure z_remember_view_usage(a_view_for_search, a_view_for_min_id, a_view_for_max_id);

    a_view_for_min_id = coalesce( a_view_for_min_id, a_view_for_search );
    a_view_for_max_id = coalesce( a_view_for_max_id, a_view_for_min_id, a_view_for_search );

    -- Label: $name_to_substutite_start_of_loop. Do not delete this line!

    if ( upper(a_view_for_search) = upper(trim('name$to$substutite$search$'))  ) then
    begin
        v_is_known = 1;
        if ( rdb$get_context('USER_TRANSACTION', upper(trim('name$to$substutite$min$id$'))||'_ID_MIN' ) is null
               or
               rdb$get_context('USER_TRANSACTION', upper(trim('name$to$substutite$max$id$'))||'_ID_MAX' ) is null
             ) then
            begin
                execute procedure sp_add_perf_log(1, a_view_for_min_id );
    
                if ( a_view_for_min_id is not null ) then
                    select min(id)-0.5 from name$to$substutite$min$id$ into id_min;
                else
                    select min(id)-0.5 from name$to$substutite$search$ into id_min;
    
                execute procedure sp_add_perf_log(0, a_view_for_min_id, null, 'static SQL, id_min='||coalesce(id_min,'<?>') );
        
                if ( id_min is NOT null ) then -- ==> source <a_view_for_min_id> is NOT empty
                begin
        
                    execute procedure sp_add_perf_log(1, a_view_for_max_id );
    
                    if ( a_view_for_max_id is not null ) then
                        select max(id)+0.5 from name$to$substutite$max$id$ into id_max;
                    else
                        select max(id)+0.5 from name$to$substutite$search$ into id_max;
    
                    execute procedure sp_add_perf_log(0, a_view_for_max_id, null, 'static SQL, id_max='||coalesce(id_max,'<?>') );
        
                    if ( id_max is NOT null  ) then -- ==> source <a_view_for_max_id> is NOT empty
                    begin
                        -- Save values for subsequent calls of this func in this tx (minimize DB access)
                        -- (limit will never change in SNAPSHOT and can change with low probability in RC):
                        rdb$set_context('USER_TRANSACTION', upper(trim('name$to$substutite$min$id$')) || '_ID_MIN', :id_min);
                        rdb$set_context('USER_TRANSACTION', upper(trim('name$to$substutite$max$id$')) || '_ID_MAX', :id_max);
                
                        if ( id_max - id_min < fn_internal_max_rows_usage ) then
                        begin
                            -- when difference b`etween id_min and id_max is not too high, we can simple count rows:
                            select count(*) from name$to$substutite$search$ into v_rows;
                            rdb$set_context('USER_TRANSACTION', upper(trim('name$to$substutite$search$')) || '_COUNT', v_rows );
                        end
                    end -- id_max is NOT null 
                end -- id_min is NOT null
            end
            else
                begin
                    -- minimize database access! Performance on 10'000 loops: 1485 ==> 590 ms
                    id_min=cast( rdb$get_context('USER_TRANSACTION', upper(trim('name$to$substutite$min$id$')) || '_ID_MIN' ) as double precision);
                    id_max=cast( rdb$get_context('USER_TRANSACTION', upper(trim('name$to$substutite$max$id$')) || '_ID_MAX' ) as double precision);
                    v_rows=cast( rdb$get_context('USER_TRANSACTION', upper(trim('name$to$substutite$search$')) || '_COUNT') as int);
                end
        
            if ( id_max - id_min < fn_internal_max_rows_usage ) then
                begin
                    --id_random = cast( 1 + rand() * (v_rows - 1) as int); -- WRONG when data skewed to low values; 30.07.2014
                    id_random = ceiling( rand() * (v_rows) );
                    select id
                    from name$to$substutite$search$
                    -- ::: nb ::: `ORDER` clause not needed here
                    rows :id_random to :id_random
                    into id_selected;
                end
            else
                begin
                    -- 17.07.2014: for some cases it is ALLOWED to query random ID without "ORDER BY"
                    -- clause because this ID will be handled in such manner that it will be REMOVED
                    -- after this handling from the scope of view! Samples of such cases are:
                    -- sp_cancel_supplier_order, sp_cancel_supplier_invoice, sp_cancel_customer_reserve
                    id_random = cast( id_min + rand() * (id_max - id_min) as bigint);

                    if ( a_can_skip_order_clause = 0 and a_find_using_desc_index = 0 ) then
                        select id
                        from name$to$substutite$search$
                        where id >= :id_random
                        order by id ASC
                        rows 1
                        into id_selected;
                    else if ( a_can_skip_order_clause = 0 and a_find_using_desc_index = 1 ) then
                        select id
                        from name$to$substutite$search$
                        where id <= :id_random
                        order by id DESC
                        rows 1
                        into id_selected;
                    else if ( a_can_skip_order_clause = 1 and a_find_using_desc_index = 0 ) then
                        select id
                        from name$to$substutite$search$
                        where id >= :id_random
                        rows 1
                        into id_selected;
                    else if ( a_can_skip_order_clause = 1 and a_find_using_desc_index = 1 ) then
                        select id
                        from name$to$substutite$search$
                        where id <= :id_random
                        rows 1
                        into id_selected;
                    else
                        exception ex_bad_argument; -- using('a_can_skip_order_clause and/or a_find_using_desc_index', v_this);
        
                end

    end -- upper(a_view_for_search) = upper(trim('name$to$substutite$min$id$'))

    -- Label: $name_to_substutite_end_of_loop. Do not delete this line!

    if ( v_is_known = 0 ) then  -- passed view not from list of known names
    begin -- use ES (old code)

        if ( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN' ) is null
           or
           rdb$get_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX' ) is null
         ) then
        begin
            execute procedure sp_add_perf_log(1, a_view_for_min_id );
            -- v`iew z_get_min_max_id may be used to see average, min and max elapsed time
            -- of this sttm:
            v_stt='select min(id)-0.5 from '|| a_view_for_min_id;
            execute statement (:v_stt) into id_min; -- do via ES in order to see statistics in the TRACE!
            execute procedure sp_add_perf_log(0, a_view_for_min_id, null, 'dyn SQL, id_min='||coalesce(id_min,'<?>') );
    
            if ( id_min is NOT null ) then -- ==> source <a_view_for_min_id> is NOT empty
            begin
    
                execute procedure sp_add_perf_log(1, a_view_for_max_id );
                -- v`iew z_get_min_max_id may be used to see average, min and max elapsed time
                -- of this sttm:
                v_stt='select max(id)+0.5 from '|| a_view_for_max_id;
                execute statement (:v_stt) into id_max; -- do via ES in order to see statistics in the TRACE!
                execute procedure sp_add_perf_log(0, a_view_for_max_id, null, 'dyn SQL, id_max='||coalesce(id_max,'<?>') );
    
                if ( id_max is NOT null  ) then -- ==> source <a_view_for_max_id> is NOT empty
                begin
                    -- Save values for subsequent calls of this func in this tx (minimize DB access)
                    -- (limit will never change in SNAPSHOT and can change with low probability in RC):
                    rdb$set_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN', :id_min);
                    rdb$set_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX', :id_max);
            
                    if ( id_max - id_min < fn_internal_max_rows_usage ) then
                    begin
                        -- when difference b`etween id_min and id_max is not too high, we can simple count rows:
                        execute statement 'select count(*) from '||a_view_for_search into v_rows;
                        rdb$set_context('USER_TRANSACTION', upper(:a_view_for_search)||'_COUNT', v_rows );
                    end
                end -- id_max is NOT null 
            end -- id_min is NOT null
        end
        else begin
            -- minimize database access! Performance on 10'000 loops: 1485 ==> 590 ms
            id_min=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_min_id)||'_ID_MIN' ) as double precision);
            id_max=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_max_id)||'_ID_MAX' ) as double precision);
            v_rows=cast( rdb$get_context('USER_TRANSACTION', upper(:a_view_for_search)||'_COUNT') as int);
        end
    
        if ( id_max - id_min < fn_internal_max_rows_usage ) then
            begin
                v_stt='select id from '||a_view_for_search||' rows :x to :y'; -- ::: nb ::: `ORDER` clause not needed here!
                --id_random = cast( 1 + rand() * (v_rows - 1) as int); -- WRONG when data skewed to low values; 30.07.2014
                id_random = ceiling( rand() * (v_rows) );
                execute statement (:v_stt) (x := id_random, y := id_random) into id_selected;
            end
        else
            begin
                -- 17.07.2014: for some cases it is ALLOWED to query random ID without "ORDER BY"
                -- clause because this ID will be handled in such manner that it will be REMOVED
                -- after this handling from the scope of view! Samples of such cases are:
                -- sp_cancel_supplier_order, sp_cancel_supplier_invoice, sp_cancel_customer_reserve
                v_stt='select id from '
                    ||a_view_for_search
                    ||iif(a_find_using_desc_index = 0, ' where id >= :x', ' where id <= :x');
                if ( a_can_skip_order_clause = 0 ) then
                    v_stt = v_stt || iif(a_find_using_desc_index = 0, ' order by id     ', ' order by id desc');
                v_stt = v_stt || ' rows 1';
                id_random = cast( id_min + rand() * (id_max - id_min) as bigint);
    
                -- execute procedure sp_add_perf_log(1, a_view_for_search );
                -- do via ES in order to see statistics in the TRACE:
                execute statement (:v_stt) (x := id_random) into id_selected;
                -- execute procedure sp_add_perf_log(0, a_view_for_search, null, 'id_sel='||coalesce(id_selected,'<?>') );
            end

    end -- v_is_known = 0 ==> use ES (old code, when passed name of view NOT from known list)


    if ( id_selected is null and coalesce(a_raise_exc, 1) = 1 ) then
    begin

        v_info = 'view: name$to$substutite$search$';
        if ( id_min is NOT null ) then
           v_info = v_info || ', id_min=' || id_min || ', id_max='||id_max;
        else
           v_info = v_info || ' - EMPTY';

        v_info = v_info ||', id_rnd='||coalesce(id_random,'<null>');

        -- 19.07.2014: 'no id>=@1 in @2 found within scope @3 ... @4'
        exception ex_can_not_select_random_id;
    end

    result = id_selected;
    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            v_stt,
            gdscode,
            v_info,
            v_this,
            (select result from fn_halt_sign(gdscode)) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end -- fn$get$random$id$subst$names 

^

set term ;^
set list on;
select 'oltp25_DDL.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

-- ###########################################################
-- End of script oltp25_DDL.sql; next to be run: oltp25_SP.sql
-- ###########################################################
