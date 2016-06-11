-- #####################################
-- Begin of script oltp_main_filling.sql
-- #####################################
-- ::: NB ::: This script is COMMON for both FB 2.5 and 3.0 and should be called after oltpNN_sp.sql

set bail on;
set list on;
select 'oltp_main_filling.sql start at ' || current_timestamp as msg from rdb$database;
set list off;
commit;
set term ^;
execute block as
    declare trg_name varchar(255);
    declare tab_name varchar(255);
    declare stt varchar(255);
    declare n int;
begin
    for
        select trim(rt.rdb$trigger_name)
        from rdb$triggers rt
        join rdb$relations rr on rt.rdb$relation_name = rr.rdb$relation_name
        where
            coalesce(rt.rdb$system_flag,0)=0
            and rt.rdb$relation_name is not null
            and rt.rdb$trigger_inactive=0
            and rr.rdb$relation_type in (0, 4, 5) -- only fixed tables and GTTs, NOT VIEWS!
    into trg_name
    do begin
        rdb$set_context('USER_TRANSACTION','ACTIVE_TRIGGER_'||trg_name,trg_name);
        stt = 'alter trigger '||trg_name||' inactive';
        execute statement(stt) with autonomous transaction;
    end

    --------------------------------------------------------

    for
        select trim(t) from
        (
            select 'perf_log' t from rdb$database union all
            select 'mon_log' t from rdb$database union all
            select 'qdistr' t from rdb$database union all
            select 'qstorned' t from rdb$database union all
            select 'pdistr' t from rdb$database union all
            select 'pstorned' t from rdb$database union all
            select 'doc_data' t from rdb$database union all
            select 'doc_list' t from rdb$database union all
            select 'invnt_turnover_log' t from rdb$database union all
            select 'money_turnover_log' t from rdb$database union all
            select 'money_saldo' t from rdb$database union all
            select 'invnt_saldo' t from rdb$database union all
            select 'wares' t from rdb$database union all
            select 'phrases' t from rdb$database union all
            select 'agents' t from rdb$database union all
            select 'rules_for_qdistr' t from rdb$database union all
            select 'rules_for_pdistr' t from rdb$database union all
            select 'mon_log' t from rdb$database union all
            select 'mon_log_table_stats' t from rdb$database
            union all -- debug tables below:
            select 'zdoc_data' t from rdb$database union all
            select 'zdoc_list' t from rdb$database union all
            select 'zinvnt_turnover_log' t from rdb$database union all
            select 'zqdistr' t from rdb$database union all
            select 'zqstorned' t from rdb$database union all
            select 'zpdistr' t from rdb$database union all
            select 'zpstorned' t from rdb$database union all
            select 'ztmp_shopping_cart' t from rdb$database
        ) d
    into tab_name
    do begin
        -- ::: nb ::: check that table really exists! otherwise some triggers can
        -- stay inactive (being active before) and will NOT return to their prev. state!
        if ( exists(
                select * from rdb$relations r
                    where r.rdb$relation_name = upper( :tab_name )
                        and r.rdb$relation_type in (0, 4, 5) -- only fixed tables and GTTs, NOT VIEWS!
                        and coalesce(r.rdb$system_flag, 0) = 0
                   )
            ) then
        begin
            stt = 'delete from '||tab_name;
            execute statement(stt);
            stt = 'select count(*) from '||tab_name; -- GC
            execute statement(stt) into n;
        end
    end

    --------------------------------------------------------
    for
        select trim(m.mon$variable_value)
        from mon$context_variables m
        where
            m.mon$transaction_id=current_transaction
            and m.mon$variable_name starting with 'ACTIVE_TRIGGER_'
    into trg_name do
    begin
        stt = 'alter trigger '||trg_name||' active';
        execute statement(stt) with autonomous transaction;
        rdb$set_context('USER_TRANSACTION','ACTIVE_TRIGGER_'||trg_name,null);
    end
end
^
set term ;^
commit;
-------------------------------------------------------------------------------
insert into perf_log( unit,info,stack,dts_beg)
values('dump_dirty_data_semaphore', '', 'by oltp_main_filling.sql', null);
commit;
-------------------------------------------------------------------------------
delete from semaphores;
insert into semaphores(id, task) values(1, 'srv_make_money_saldo');
insert into semaphores(id, task) values(2, 'srv_recalc_idx_stat');
insert into semaphores(id, task) values(3, 'srv_make_invnt_saldo');
commit;

-- ##########   S E T T I N G S     f o r    D I F F.      M O D E S   #########

delete from settings;

-- Definitions for workload modes; list of avaliable working_modes see below:
set term ^;
execute block as
    declare v_insert_settings_statement varchar(512);
begin
    for
        with recursive
        n as(select 1 i from rdb$database union all select n.i+1 from n where n.i < 6)
        ,c(
            working_mode,
            wares_max_id,
            customer_doc_max_rows,
            supplier_doc_max_rows,
            customer_doc_max_qty,
            supplier_doc_max_qty,
            number_of_agents
        ) as (
        select
            -- #################################################################
            -- PUT YOUR OWN SETTINGS FOR DIFFERENT WORKLOAD MODES HERE:
            -- JUST CHANGE NUMERICAL VALUES IN COLUMNS OF THIS TABLE.
            -- ALSO YOU CAN ADD NEW WORKING_MODE AND FILL ALL IT'S PARAMS.
            -- AFTER YOU WILL CHANGE SETTINGS, UPDATE VALUE OF VAR. 'WORKING_MODE'
            -- (it's value must be from the field 'working_mode' in this table).
            -- To see current settings type: SELECT * FROM Z_SETTINGS_PIVOT
            -- #################################################################
            -- working | num of | max       | max       | max      | max      | num of
            -- mode    |  wares | cust_rows | supp_rows | cust_Qty | supp_Qty | agents
            'DEBUG_01',       1,       1,          1,          2,         5,        3  from rdb$database union all select
            'DEBUG_02',       2,       2,          3,          5,         5,        3  from rdb$database union all select
            'DEBUG_03',       3,       3,          5,          4,         8,       10  from rdb$database union all select
            'DEBUG_04',      10,       5,         30,          5,        30,       15  from rdb$database union all select
            'DEBUG_1A',       1,      10,         50,         10,        50,        3  from rdb$database union all select
            'SMALL_01',     100,       5,         20,          5,        20,       30  from rdb$database union all select
            'SMALL_02',     300,      10,         30,         10,        30,       40  from rdb$database union all select
            'SMALL_03',     400,      10,         50,         15,        50,       50  from rdb$database union all select
            'MEDIUM_01',    700,      20,         60,         30,       100,      100  from rdb$database union all select
            'MEDIUM_02',   1500,      30,         80,         50,       150,      150  from rdb$database union all select
            'MEDIUM_03',   3000,      50,        100,         70,       200,      200  from rdb$database union all select
            'LARGE_01',    5000,      70,        200,        100,       300,      500  from rdb$database union all select
            'LARGE_02',    7000,     100,        300,        150,       450,      700  from rdb$database union all select
            'LARGE_03',    9000,     150,        400,        200,       600,     1000  from rdb$database union all select
            'HEAVY_01',   50000,     250,        500,        300,       900,     2000  from rdb$database
        )
        ,d as(
            select
                 'insert into settings(working_mode, mcode, svalue, init_on) values('''
                 ||trim(c.working_mode)
                 ||''', ' expr_pref
                ,iif(n.i=1, c.wares_max_id, null ) v4wares_max_id
                ,iif(n.i=2, c.customer_doc_max_rows, null ) v4customer_doc_max_rows
                ,iif(n.i=3, c.supplier_doc_max_rows, null ) v4supplier_doc_max_rows
                ,iif(n.i=4, c.customer_doc_max_qty, null ) v4customer_doc_max_qty
                ,iif(n.i=5, c.supplier_doc_max_qty, null ) v4supplier_doc_max_qty
                ,iif(n.i=6, c.number_of_agents, null ) v4number_of_agents
                ,')' expr_suff
            from c
            cross join n
        )
        select
            d.expr_pref
            || iif( v4wares_max_id is not null, ''''||upper('c_wares_max_id')||''', '||v4wares_max_id||', ''db_prepare'''
                ,iif( v4customer_doc_max_rows is not null, ''''||upper('c_customer_doc_max_rows')||''', '||v4customer_doc_max_rows||', ''connect'''
                     ,iif( v4supplier_doc_max_rows is not null, ''''||upper('c_supplier_doc_max_rows')||''', '||v4supplier_doc_max_rows||', ''connect'''
                           ,iif( v4customer_doc_max_qty is not null, ''''||upper('c_customer_doc_max_qty')||''', '||v4customer_doc_max_qty||', ''connect'''
                                 ,iif( v4supplier_doc_max_qty is not null, ''''||upper('c_supplier_doc_max_qty')||''', '||v4supplier_doc_max_qty||', ''connect'''
                                       ,iif( v4number_of_agents is not null, ''''||upper('c_number_of_agents')||''', '||v4number_of_agents||', ''db_prepare''', null )
                                     )
                               )
                         )
                    )
               )
            || d.expr_suff
            as ins_sttm
        from d
        into v_insert_settings_statement
    do
    begin
        execute statement(v_insert_settings_statement);
    end
end
^
set term ;^
commit;

-- ::: NB ::: This record is created here only as 'stub'.
-- Value of this variable will be replaced with config parameter 'working_mode'
--  by 1run_oltp_emul.bat (.sh) every time test is launched.
insert into settings(working_mode, mcode,           svalue)
              values('INIT',       'WORKING_MODE',
                     -- DEBUG_01'
                     'SMALL_03'
              ); -- DEFAULT: 'SMALL_03'
-- DEBUG_01 DEBUG_1A DEBUG_02 DEBUG_03 DEBUG_04 SMALL_01  SMALL_02 SMALL_03
-- MEDIUM_01 MEDIUM_02 MEDIUM_03 LARGE_01 LARGE_02 LARGE_03
-- HEAVY_01


-- List of units for which we want to gather info from mon$table_stats.
-- Leave this INSERT statement with svalue = ',,'. 
-- If you want to analyze performance of some units (procedures or triggers),
-- use UPDATE statement after this:
insert into settings(working_mode, mcode,                  svalue
                    ,description)
              values('COMMON',       'TRACED_UNITS', ',,'
                    ,'Units that are subject to gathering MON$ statistics'
              );

-- This is the sample how to change list of units for which test should gather 
-- statistics from MON$ tables for further analyzing:
-- update settings set svalue = ',sp_make_qty_storno,sp_kill_qty_storno,sp_multiply_rows_for_qdistr,sp_multiply_rows_for_pdistr,'
-- where working_mode = 'COMMON' and mcode = 'TRACED_UNITS';

-- update settings set svalue = ',sp_make_qty_storno,sp_kill_qty_storno,sp_multiply_rows_for_qdistr,sp_multiply_rows_for_pdistr,'
-- where working_mode = 'COMMON' and mcode = 'TRACED_UNITS';


-- do we ALLOW to query mon$-tables in ALL cases (not only when some blocking bug encountered) ?
-- update settings set svalue='0' where mcode='ENABLE_MON_QUERY';
-- update settings set svalue='1' where mcode='ENABLE_MON_QUERY';
insert into settings(working_mode, mcode, svalue, description)
              values(  'COMMON'
                      ,'ENABLE_MON_QUERY'
                      ,iif(  left(rdb$get_context('SYSTEM','ENGINE_VERSION'),3) starting with '2.'
                            ,'0'
                            ,'0'  -- for 3.0 and above can be = '1' since ~10.08.2014
                          )
                      ,'0 =  do not gather mon$ tables at all; 1 = gather mon$ tables before and after each Tx, in every ISQL session'
                    );

-- Mnemonics of exceptions which forces test to be stopped (see calls of fn_halt_sign(gdscode)):
-- 'CK' -- halt if CHECK violation or 'not_valid' occurs
-- 'PK' -- halt if PK or UK violation occurs
-- 'FK' -- halt if FK violation occurs // now n/a
-- 'ST' -- halt if exc #335544842 appeared at the top of stack and logged into perf_log (strange problem only in 3.0 SC)
-- These mnemonics can be combined in list, i.e.: 'CK,PK,FK' - halt if CHECK or PK or FK violation occurs
-- Default: ',CK,' ==> force test to be stopped on attempt to write NEGATIVE values for stock remainders.
-- 12.02.2015: PK and FK violations *can* be detected only in sp_make_qty_storno & sp_kill_qty_storno,
-- but it is due to UNDEFINED order of UNDO when some Tx must perform bulk of such work.
-- Detailed investigation:
-- sql.ru/forum/1142271/posledstviya-nepredskazuemo-neposledovatelnyh-otkatov-izmeneniy-pri-exception
-- (EXPLANATION by dimitr see in e-mail, letters date = 12.02.2015)
insert into settings(working_mode, mcode, svalue, description)
              values(  'COMMON'
                      ,'HALT_TEST_ON_ERRORS'
                      ,iif(  left(rdb$get_context('SYSTEM','ENGINE_VERSION'),3) starting with '2.'
                            ,',CK,' -- 12.02.2015: can be ',CK,' on all architectures FB 3.0
                            ,',CK,'  -- 12.02.2015: can be ',CK,' on all architectures FB 3.0
                          )
                      ,'Mnemonics of exceptions which forces test to be stopped (see calls of fn_halt_sign(gdscode))'
                    );

-- LOG_PK_VIOLATION:
-- = '0' ==> REMOVE primary keys from tables doc_data, qdistr, qstorned, pdistr & pstorned
-- in order to get max possible performance (but only if HALT_TEST_ON_ERRORS does NOT
-- containing ',PK,');
-- = '1' ==> do NOT remove PK from these tables despite of these constraints actually
-- are NOT needed (they were added in early stage of test implementation).
-- Logging of PK violations see in sp SRV_LOG_DUPS_QD_QS
-- update settings set svalue='0' where mcode='LOG_PK_VIOLATION';
-- update settings set svalue='1' where mcode='LOG_PK_VIOLATION';
-- Removing PK from these tables see at the end of **THIS** script.
insert into settings(working_mode, mcode,                      svalue,  init_on)
              values('COMMON',     'LOG_PK_VIOLATION',   '0',     'db_prepare');

-- How stock remainders should be verified BEFORE totalling will occur in sp_make_invnt_saldo
-- (declarative CHECK constraint on qty_xxx >= 0  should NOT ever be fired in this test!):
-- bit#0 := 1 ==> perform calls of SRV_FIND_QD_QS_MISM in doc_list_aiud in order
--                to register mismatches between doc_data.qty and total number
--                of rows in qdistr + qstorned for doc_data.id
-- bit#1 := 1 ==> perform calls of SRV_CHECK_NEG_REMAINDERS from doc_list_aiud
--                (instead of totalling turnovers to `invnt_saldo` table)
-- bit#2 := 1 ==> allow dump dirty data into z-tables for analysis, see sp zdump4dbg, in case
--                when some 'bad exception' occurs (see ctx var `HALT_TEST_ON_ERRORS`)
-- ##################################################################################
-- ::: NB ::: Correct value of config parameter 'create_with_debug_objects' (set it = 1)
-- if you need to create debug "Z-" tables and procedure for DUMP all data on errors.
-- ##################################################################################
-- update settings set svalue='3' where mcode='QMISM_VERIFY_BITSET';
-- update settings set svalue='7' where mcode='QMISM_VERIFY_BITSET';
insert into settings(working_mode, mcode,         svalue)
              values('COMMON',     'QMISM_VERIFY_BITSET',  '1'); -- default: '1'; changed to '0' for branch 'create_with_split_heavy_tabs'


-- 27.11.2015. Minimal interval in minutes between two subsequent calls of service
-- procedure srv_recalc_idx_stat which updates index statistics and can last
-- too long (more than 3-4 minutes per table on database with size ~100Gb).
-- See SP srv_random_unit_choice for choising algorithm:
insert into settings(working_mode, mcode,                      svalue)
              values('COMMON',     'RECALC_IDX_MIN_INTERVAL', '15');

-- Do we allow to make 'batch reserve creations' in sp_add_invoice ?
-- When '1' then search of client orders with incompleted reserve amounts and
-- creation of customer reserves for them will be in the SAME transaction with
-- invoice accepting ==> this can lead this SP to long time of execution and
-- lot of lock_conflicts
insert into settings(working_mode, mcode,                                 svalue)
              values('COMMON',       'ENABLE_RESERVES_WHEN_ADD_INVOICE',  '1'); -- set to '0' only for debug purposes!

-- How frequently we order for OURSELVES rather than for common customers:
insert into settings(working_mode, mcode,          svalue)
              values('COMMON',     'ORDER_FOR_OUR_FIRM_PERCENT', '25');

-- For oltp_data_filling: do we fill phrases table with patterns based on
-- wares.name (it can take long time, several minutes):
insert into settings(working_mode, mcode,                   svalue)
              values('COMMON',       'ENABLE_FILL_PHRASES', '0');

-- For fn_get_random_id: max diff between id_min and id_max to use ROWS clause
-- like this: select id from v_xxx ROWS :random to :random
-- (good for small resultsets with skewed IDs)
-- update settings s set svalue='1000000' where s.working_mode='COMMON' and s.mcode='RANDOM_SEEK_VIA_ROWS_LIMIT';
insert into settings(working_mode, mcode,                      svalue)
              values('COMMON',       'RANDOM_SEEK_VIA_ROWS_LIMIT', '0');

-- Used only in script oltp_data_filling.sql that fills wares table:
-- min/max cost of purchasing for qty, max profit percent - common for all working_modes:
insert into settings(working_mode, mcode,                      svalue,  init_on)
              values('COMMON',     'C_INVOICE_MIN_PURCHASE',   '1000',  'db_prepare');
insert into settings(working_mode, mcode,                      svalue,  init_on)
              values('COMMON',     'C_INVOICE_MAX_PURCHASE',   '2000',  'db_prepare');
insert into settings(working_mode, mcode,                      svalue,  init_on)
              values('COMMON',     'C_INVOICE_MIN_PROFIT_PRC', '35',  'db_prepare');
insert into settings(working_mode, mcode,                      svalue,  init_on)
              values('COMMON',     'C_INVOICE_MAX_PROFIT_PRC', '80',  'db_prepare');

-- minimum threshold for COST of payment to be splitted into PDistr rows:
-- (to reduce lock conflicts when doing storno)
insert into settings(working_mode, mcode,  svalue)
              values('COMMON',     'C_MIN_COST_TO_BE_SPLITTED', '1000');

-- number of rows which should be added into rdistr for every new cost
-- (this setting will be stored into rules_for_pdistr table, see below):
-- ::: NB ::: this setting must remains in THIS script, see below filling
-- of table rules_for_pdistr
insert into settings(working_mode, mcode,              svalue)
              values('COMMON',     'C_ROWS_TO_MULTIPLY', '10');

-- min and max total of payment from client when no custom reserve docs
insert into settings(working_mode, mcode,                             svalue)
              values('COMMON',     'C_PAYMENT_FROM_CLIENT_MIN_TOTAL', '1000');  -- 1'000
insert into settings(working_mode, mcode,                             svalue)
              values('COMMON',     'C_PAYMENT_FROM_CLIENT_MAX_TOTAL', '5000'); -- 10'000 100'000

-- min and max total of payment to supplier when no invoices found
insert into settings(working_mode, mcode,                             svalue)
              values('COMMON',     'C_PAYMENT_TO_SUPPLIER_MIN_TOTAL', '2000'); -- 10'000
insert into settings(working_mode, mcode,              svalue)
              values('COMMON',     'C_PAYMENT_TO_SUPPLIER_MAX_TOTAL', '15000'); -- 50'000 500'000

commit;

-- 4debug on trivial working_mode:
set term ^;
execute block as
begin
  if ( (select s.svalue from settings s where s.working_mode = 'INIT' and s.mcode='WORKING_MODE') in ('DEBUG_01', 'DEBUG_02') ) then
  begin
    update settings s
    set s.svalue='0'
    where s.mcode in( 'ENABLE_RESERVES_WHEN_ADD_INVOICE', 'ORDER_FOR_OUR_FIRM_PERCENT' );
  end
end
^
set term ;^
commit;

--------------------------------------------------------------------------------
-- #########  Filling OPTYPES, RULES_FOR_QDISTR and RULES_FOR_PDISTR ###########
--------------------------------------------------------------------------------

set term ^;
execute block as
    declare fn_oper_order_by_customer dm_idb;
    declare fn_oper_order_for_supplier dm_idb;
    declare fn_oper_invoice_get dm_idb;
    declare fn_oper_invoice_add dm_idb;
    declare fn_oper_retail_reserve dm_idb;

    declare fn_oper_pay_from_customer dm_idb;
    declare fn_oper_retail_realization dm_idb;
    declare fn_oper_pay_to_supplier dm_idb;
begin
    delete from optypes;
    
    fn_oper_order_by_customer = 1000;
    insert into optypes(id,   mcode,     acn_type,  name,                  m_qty_clo)
                values( :fn_oper_order_by_customer, 'CLO',     '1',       'add to client order', 1);

    -- ::: nb ::: id of this oper must be GREATER than id for 'CLO' (see trigger doc_data_aiud):
    insert into optypes(id,   mcode,     acn_type,  name,                  m_qty_clr)
                values( 1100, 'CLR',     '1',       'client refused from order', 1);

    fn_oper_order_for_supplier = 1200;
    insert into optypes(id,   mcode,     acn_type,  name,                                   m_qty_clo, m_qty_ord)
                values( :fn_oper_order_for_supplier, 'ORD',     '2',       'add to stock order, send to supplier', -1,        1);

    fn_oper_invoice_get = 2000;
    insert into optypes(id,   mcode,     acn_type,  name,                             m_qty_ord, m_qty_sup)
                values( :fn_oper_invoice_get, 'SUP',     'i',       'get invoice from supplier',      -1,           1);

    -- ::: nb ::: id of this oper must be GREATER than id for 'SUP' (see trigger doc_data_aiud):
    fn_oper_invoice_add = 2100;
    insert into optypes(id,   mcode,     acn_type,  name,                                  m_qty_sup, m_qty_avl, m_supp_debt)
                values( :fn_oper_invoice_add, 'INC',     'i',       'add invoice to avaliable remainders', -1,           1,            1   );

    fn_oper_retail_reserve = 3300;
    insert into optypes(id,   mcode,     acn_type,  name,                                   m_qty_avl, m_qty_res)
                values( :fn_oper_retail_reserve, 'RES',     'o',       'retail sale - reserve for customer',   -1,           1);

    -- ::: nb ::: id of this oper must be GREATER than id for 'RES' (see trigger doc_data_aiud):
    fn_oper_retail_realization = 3400;
    insert into optypes(id,   mcode,     acn_type,  name,                                           m_qty_res, m_cust_debt)
                values( :fn_oper_retail_realization, 'SAL',     'o',       'retail sale - write-off (realization)',        -1,           1      );

    fn_oper_pay_to_supplier = 4000;
    insert into optypes(id,   mcode,     acn_type,  name,                                m_supp_debt)
                values( :fn_oper_pay_to_supplier, 'PSU',     's',       'payment to supplier for wares',     -1        ); -- "-1" ==> our debt decreases
    
    fn_oper_pay_from_customer = 5000;
    insert into optypes(id,   mcode,     acn_type,  name,                                                 m_cust_debt)
                values( :fn_oper_pay_from_customer, 'PCU',     'c',       'payment from customer (advance or target transfer)', -1        ); -- "-1" ==> hist debt decreases

    update optypes o
    set multiply_rows_for_fifo = 1
    where o.id in ( :fn_oper_order_by_customer, :fn_oper_order_for_supplier, :fn_oper_invoice_get ) ;

    ----------------------------------------------------------------------------

    -- 28.07.2014: add field storno_sub to rules_for_qdistr, see sp_make_qty_storno!
    delete from rules_for_qdistr;  -- 'distr_only' (snd='clo', rcv='res'), 'distr+new_doc' (all others)
    insert into rules_for_qdistr( mode,           snd_optype_id, rcv_optype_id)
                          values( 'new_doc_only', null,          :fn_oper_order_by_customer );

    insert into rules_for_qdistr( mode,            snd_optype_id,              rcv_optype_id,               storno_sub)
                          values( 'distr+new_doc', :fn_oper_order_by_customer, :fn_oper_order_for_supplier, 1 );
    insert into rules_for_qdistr(mode,             snd_optype_id,               rcv_optype_id,              storno_sub)
                          values( 'distr+new_doc', :fn_oper_order_for_supplier, :fn_oper_invoice_get,       1 );

    insert into rules_for_qdistr( mode,             snd_optype_id,              rcv_optype_id,              storno_sub)
                          values( 'mult_rows_only', :fn_oper_order_by_customer, :fn_oper_retail_reserve,    2 );

    -- need for adding new rows in qdistr when call sp_supplier_invoice
    -- (snd_op=2000(sup), rcv_op=3300(res), number_of_added_rows = tmp$cart.qty):
    insert into rules_for_qdistr( mode,             snd_optype_id,        rcv_optype_id)
                          values( 'mult_rows_only', :fn_oper_invoice_get, :fn_oper_retail_reserve );

    -- need for distribution when call sp_add_invoice_to_stock:
    -- (21.05.2014: storno of 'CLO' will be auto in sp_create_doc_using_fifo if a_client_order not null)
    insert into rules_for_qdistr( mode,            snd_optype_id,         rcv_optype_id,          storno_sub)
                          values( 'distr+new_doc', :fn_oper_invoice_add, :fn_oper_retail_reserve, 1 );

    insert into rules_for_qdistr( mode,           snd_optype_id,           rcv_optype_id)
                          values( 'new_doc_only', :fn_oper_retail_reserve, :fn_oper_retail_realization  ); -- 12.09.2015
                          --values( 'new_doc_only', :fn_oper_retail_reserve, null  );

    ----------------------------------------------------------------------------
    delete from rules_for_pdistr;
    -- ::: nb ::: Field `rows_to_multiply` is filled in oltp_load_ssettings.sql
    insert into rules_for_pdistr(mode, snd_optype_id,              rcv_optype_id               )
                          values( '', :fn_oper_pay_from_customer, :fn_oper_retail_realization );
    insert into rules_for_pdistr(mode, snd_optype_id,                rcv_optype_id            )
                          values( '',  :fn_oper_retail_realization, :fn_oper_pay_from_customer );
    
    insert into rules_for_pdistr(mode, snd_optype_id,             rcv_optype_id)
                          values( '',  :fn_oper_pay_to_supplier, :fn_oper_invoice_add);
    insert into rules_for_pdistr(mode, snd_optype_id,         rcv_optype_id)
                          values( '',  :fn_oper_invoice_add, :fn_oper_pay_to_supplier );

    update rules_for_pdistr p
    set p.rows_to_multiply =
        ( select cast(s.svalue as int)
          from settings s
          where s.working_mode='COMMON' and s.mcode = 'C_ROWS_TO_MULTIPLY'
        );

end

^set term ;^
commit;

--------------------------------------------------------------------------------
delete from doc_states;
insert into doc_states(id, mcode, name) values(2000, 'DOC_OPEN_STATE', 'content not checked, changes enable');
insert into doc_states(id, mcode, name) values(2010, 'DOC_FIX_STATE',  'content checked, accept only payments');
insert into doc_states(id, mcode, name) values(2020, 'DOC_CLOS_STATE', 'closed from any changes'); -- but WITH possibility to revert to doc_fix or doc_open state
insert into doc_states(id, mcode, name) values(2030, 'DOC_CANC_STATE', 'cancelled without revert'); -- for customer order cancellation when at least one stock order exists for it
commit;

--------------------------------------------------------------------------------
-- ##################   B U S I N E S    O P E R A T I O N S   #################
--------------------------------------------------------------------------------
delete from business_ops;

-- ::: nb ::: names in column 'unit' mustr match to those which are specified
-- in variable 'v_this' in all SPs!
-- select first 1 unit from business_ops where weight >= :r order by rand()
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_client_order',           'stock', 'creation',  95, 100,    'customer order: creation');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_client_order',    'stock', 'removal',   30, 120,    'customer order: refuse');

insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_supplier_order',         'stock', 'creation',  65, 200,    'order to supplier: creation');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_supplier_order',  'stock', 'removal',   10, 220,    'order to supplier: removal');

insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_supplier_invoice',       'stock', 'creation',  65, 300,    'invoice (draft): creation');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_supplier_invoice','stock', 'removal',   10, 320,    'invoice (draft): removal');

insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_add_invoice_to_stock',   'stock', 'state_next', 62, 400,    'invoice accept: apply');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_adding_invoice',  'stock', 'state_back', 10, 420,    'invoice accept: cancel');

-- nb: we can set LOW prior to sp_customer_reserve because most of these docs
-- will be created from sp_add_invoice_to_stock and only several percents
-- from avaliable remainders:
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_customer_reserve',       'stock', 'creation',   20, 500,    'customer reserve: creation');
--
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_customer_reserve','stock', 'removal',    15, 520,    'customer reserve: removal');
--
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_reserve_write_off',      'stock', 'state_next', 80, 600,    'realization accept: apply');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_write_off',       'stock', 'state_back', 20, 620,    'realization accept: cancel');

insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_pay_from_customer',       'payments', 'creation', 72, 700,   'payment from customer: creation');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_pay_from_customer','payments', 'removal',  15, 720,   'payment from customer: removal');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_pay_to_supplier',         'payments', 'creation', 67, 800,   'payment to supplier: creation');
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('sp_cancel_pay_to_supplier',  'payments', 'removal',  10, 820,   'payment to supplier: removal');

---
insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('srv_make_invnt_saldo',  'service', 'service',        35, 990,   'service: total inventory turnovers');

insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('srv_make_money_saldo',  'service', 'service',        25, 995,   'service: total monetary turnovers');

insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
values('srv_recalc_idx_stat',  'service', 'service',         20, 997,   'service: refresh index statistics');

-- need only to check FB stability against extremely high frequency of MON$-querying:
-- --update business_ops b set b.random_selection_weight=40 where b.unit='srv_fill_mon'; commit;
-- delete from business_ops b where b.unit='srv_fill_mon'; commit;
--insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, info )
--values('srv_fill_mon',         'service', 'service',         40, 999,   '(temply) stability test when querying mon$-tables');

--------------------------------------------------------------------------------
-- ##################   FIREBIRD STANDARD ERROR CODES   ########################
--------------------------------------------------------------------------------
delete from fb_errors;
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(101, 335544366, 'segment', 'Segment buffer length shorter than expected.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(100, 335544338, 'from_no_match', 'No match for first value expression.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(100, 335544354, 'no_record', 'Invalid database key.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(100, 335544367, 'segstr_eof', 'Attempted retrieval of more segments than exist.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(100, 335544374, 'stream_eof', 'Attempt to fetch past the last record in a record stream.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(0, 335741039, 'gfix_opt_SQL_dialect', 'use -sql_dialect to set database dialect n.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(0, 335544875, 'bad_debug_format', 'Bad debug info format.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-84, 335544554, 'nonsql_security_rel', 'Table/procedure has non-SQL security class defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-84, 335544555, 'nonsql_security_fld', 'Column has non-SQL security class defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-84, 335544668, 'dsql_procedure_use_err', 'Procedure @1 does not return any values.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544747, 'usrname_too_long', 'The username entered is too long. Maximum length is 31 bytes.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544748, 'password_too_long', 'The password specified is too long. Maximum length is 8 bytes.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544749, 'usrname_required', 'A username is required for this operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544750, 'password_required', 'A password is required for this operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544751, 'bad_protocol', 'The network protocol specified is invalid.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544752, 'dup_usrname_found', 'A duplicate user name was found in the security database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544753, 'usrname_not_found', 'The user name specified was not found in the security database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544754, 'error_adding_sec_record', 'An error occurred while attempting to add the user.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544755, 'error_modifying_sec_record', 'An error occurred while attempting to modify the user record.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544756, 'error_deleting_sec_record', 'An error occurred while attempting to delete the user record.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-85, 335544757, 'error_updating_sec_db', 'An error occurred while updating the security database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-103, 335544571, 'dsql_constant_err', 'Data type for constant unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336003075, 'dsql_transitional_numeric', 'Precision 10 to 18 changed from DOUBLE PRECISION in SQL dialect 1 to 64-bit scaled integer in SQL di');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336003077, 'sql_db_dialect_dtype_unsupport', 'Database SQL dialect @1 does not support reference to @2 datatype.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336003087, 'dsql_invalid_label', 'Label @1 @2 in the current scope.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336003088, 'dsql_datatypes_not_comparable', 'Datatypes @1 are not comparable in expression @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544343, 'invalid_blr', 'Invalid request BLR at offset @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544390, 'syntaxerr', 'BLR syntax error: expected @1 at offset @2, encountered @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544425, 'ctxinuse', 'Context already in use (BLR error).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544426, 'ctxnotdef', 'Context not defined (BLR error).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544429, 'badparnum', 'Bad parameter number.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544440, 'bad_msg_vec', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544456, 'invalid_sdl', 'Invalid slice description language at offset @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544570, 'dsql_command_err', 'Invalid command.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544579, 'dsql_internal_err', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544590, 'dsql_dup_option', 'Option specified more than once.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544591, 'dsql_tran_err', 'Unknown transaction option.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544592, 'dsql_invalid_array', 'Invalid array reference.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544608, 'command_end_err', 'Unexpected end of command.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544612, 'token_err', 'Token unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544634, 'dsql_token_unk_err', 'Token unknown- line @1, column @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544709, 'dsql_agg_ref_err', 'Invalid aggregate reference.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544714, 'invalid_array_id', 'Invalid blob id.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544730, 'cse_not_supported', 'Client/Server Express not supported in this release.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544743, 'token_too_long', 'Token size exceeds limit.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544763, 'invalid_string_constant', 'A string constant is delimited by double quotes.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544764, 'transitional_date', 'DATE must be changed to TIMESTAMP.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544796, 'sql_dialect_datatype_unsupport', 'Client SQL dialect @1 does not support reference to @2 data type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544798, 'depend_on_uncommitted_rel', 'You created an indirect dependency on uncommitted metadata. You must roll back the current transacti');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544821, 'dsql_column_pos_err', 'Invalid column position used in the @1 clause.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544822, 'dsql_agg_where_err', 'Cannot use an aggregate function in a WHERE clause, use HAVING instead.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544823, 'dsql_agg_group_err', 'Cannot use an aggregate function in a GROUP BY clause.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544824, 'dsql_agg_column_err', 'Invalid expression in the @1 (not contained in either an aggregate function or the GROUP BY clause).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544825, 'dsql_agg_having_err', 'Invalid expression in the @1 (neither an aggregate function nor a part of the GROUP BY clause).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544826, 'dsql_agg_nested_err', 'Nested aggregate functions are not allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544849, 'malformed_string', 'Malformed string.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 335544851, 'command_end_err2', 'Unexpected end of command - line @1, column @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397215, 'dsql_max_sort_items', 'Cannot sort on more than 255 items.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397216, 'dsql_max_group_items', 'Cannot group on more than 255 items.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397217, 'dsql_conflicting_sort_field', 'Cannot include the same field (@1.@2) twice in the ORDER BY clause with conflicting sorting options.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397218, 'dsql_derived_table_more_columns', 'Column list from derived table @1 has more columns than the number of items in its SELECT statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397219, 'dsql_derived_table_less_columns', 'Column list from derived table @1 has less columns than the number of items in its SELECT statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397220, 'dsql_derived_field_unnamed', 'No column name specified for column number @1 in derived table @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397221, 'dsql_derived_field_dup_name', 'Column @1 was specified multiple times for derived table @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397222, 'dsql_derived_alias_select', 'Internal dsql error: alias type expected by pass1_expand_select_node.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397223, 'dsql_derived_alias_field', 'Internal dsql error: alias type expected by pass1_field.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397224, 'dsql_auto_field_bad_pos', 'Internal dsql error: column position out of range in pass1_union_auto_cast.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397225, 'dsql_cte_wrong_reference', 'Recursive CTE member (@1) can refer itself only in FROM clause.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397226, 'dsql_cte_cycle', 'CTE ''@1'' has cyclic dependencies.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397227, 'dsql_cte_outer_join', 'Recursive member of CTE can''t be member of an outer join.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397228, 'dsql_cte_mult_references', 'Recursive member of CTE can''t reference itself more than once.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397229, 'dsql_cte_not_a_union', 'Recursive CTE (@1) must be a UNION.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397230, 'dsql_cte_nonrecurs_after_recurs', 'CTE ''@1'' defined non-recursive member after recursive.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397231, 'dsql_cte_wrong_clause', 'Recursive member of CTE ''@1'' has @2 clause.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397232, 'dsql_cte_union_all', 'Recursive members of CTE (@1) must be linked with another members via UNION ALL.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397233, 'dsql_cte_miss_nonrecursive', 'Non-recursive member is missing in CTE ''@1''.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397234, 'dsql_cte_nested_with', 'WITH clause can''t be nested.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397235, 'dsql_col_more_than_once_using', 'Column @1 appears more than once in USING clause.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-104, 336397237, 'dsql_cte_not_used', 'CTE "@1" is not used in query.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-105, 335544702, 'like_escape_invalid', 'Invalid ESCAPE sequence.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-105, 335544789, 'extract_input_mismatch', 'Specified EXTRACT part does not exist in input data type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-150, 335544360, 'read_only_rel', 'Attempted update of read-only table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-150, 335544362, 'read_only_view', 'Cannot update read-only view @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-150, 335544446, 'non_updatable', 'Not updatable.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-150, 335544546, 'constraint_on_view', 'Cannot define constraints on views.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-151, 335544359, 'read_only_field', 'Attempted update of read-only column.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-155, 335544658, 'dsql_base_table', '@1 is not a valid base table of the specified view.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-157, 335544598, 'specify_field_err', 'Must specify column name for view select expression.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-158, 335544599, 'num_field_err', 'Number of columns does not match select list.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-162, 335544685, 'no_dbkey', 'Dbkey not available for multi-table views.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-170, 335544512, 'prcmismat', 'Input parameter mismatch for procedure @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-170, 335544619, 'extern_func_err', 'External functions cannot have more than 10 parameters.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-170, 335544850, 'prc_out_param_mismatch', 'Output parameter mismatch for procedure @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-171, 335544439, 'funmismat', 'Function @1 could not be matched.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-171, 335544458, 'invalid_dimension', 'Column not array or invalid dimensions (expected @1, encountered @2).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-171, 335544618, 'return_mode_err', 'Return mode by value not allowed for this data type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-171, 335544873, 'array_max_dimensions', 'Array data type can use up to @1 dimensions.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-172, 335544438, 'funnotdef', 'Function @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-203, 335544708, 'dyn_fld_ambiguous', 'Ambiguous column reference.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 336003085, 'dsql_ambiguous_field_name', 'Ambiguous field name between @1 and @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544463, 'gennotdef', 'Generator @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544502, 'stream_not_defined', 'Reference to invalid stream number.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544509, 'charset_not_found', 'CHARACTER SET @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544511, 'prcnotdef', 'Procedure @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544515, 'codnotdef', 'Status code @1 unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544516, 'xcpnotdefException', '@1 not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544532, 'ref_cnstrnt_notfound', 'Name of Referential Constraint not defined in constraints table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544551, 'grant_obj_notfound', 'Could not find table/procedure for GRANT.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544568, 'text_subtype', 'Implementation of text subtype @1 not located.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544573, 'dsql_datatype_err', 'Data type unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544580, 'dsql_relation_err', 'Table unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544581, 'dsql_procedure_err', 'Procedure unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544588, 'collation_not_found', 'COLLATION @1 for CHARACTER SET @2 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544589, 'collation_not_for_charset', 'COLLATION @1 is not valid for specified CHARACTER SET.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544595, 'dsql_trigger_err', 'Trigger unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544620, 'alias_conflict_err', 'Alias @1 conflicts with an alias in the same statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544621, 'procedure_conflict_error', 'Alias @1 conflicts with a procedure in the same statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544622, 'relation_conflict_err', 'Alias @1 conflicts with a table in the same statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544635, 'dsql_no_relation_alias', 'There is no alias or table named @1 at this scope level.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544636, 'indexname', 'There is no index @1 for table @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544640, 'collation_requires_text', 'Invalid use of CHARACTER SET or COLLATE.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544662, 'dsql_blob_type_unknown', 'BLOB SUB_TYPE @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544759, 'bad_default_value', 'Can not define a not null column with NULL as default value.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544760, 'invalid_clause', 'Invalid clause: ''@1''.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544800, 'too_many_contexts', 'Too many Contexts of Relation/Procedure/Views. Maximum allowed is 255.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544817, 'bad_limit_param', 'Invalid parameter to FIRST. Only integers >= 0 are allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544818, 'bad_skip_param', 'Invalid parameter to SKIP. Only integers >= 0 are allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544837, 'bad_substring_offset', 'Invalid offset parameter @1 to SUBSTRING. Only positive integers are allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544853, 'bad_substring_length', 'Invalid length parameter @1 to SUBSTRING. Negative integers are not allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544854, 'charset_not_installed', 'CHARACTER SET @1 is not installed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544855, 'collation_not_installed', 'COLLATION @1 for CHARACTER SET @2 is not installed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-204, 335544867, 'subtype_for_internal_use', 'Blob sub_types bigger than 1 (text) are for internal use only.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-205, 335544396, 'fldnotdef', 'Column @1 is not defined in table @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-205, 335544552, 'grant_fld_notfound', 'Could not find column for GRANT.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-205, 335544883, 'fldnotdef2', 'Column @1 is not defined in procedure @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-206, 335544578, 'dsql_field_err', 'Column unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-206, 335544587, 'dsql_blob_err', 'Column is not a BLOB.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-206, 335544596, 'dsql_subselect_err', 'Subselect illegal in this context.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-206, 336397208, 'dsql_line_col_error', 'At line @1, column @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-206, 336397209, 'dsql_unknown_pos', 'At unknown line and column.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-206, 336397210, 'dsql_no_dup_name', 'Column@1 cannot be repeated in @2 statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-208, 335544617, 'order_by_err', 'Invalid ORDER BY clause.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-219, 335544395, 'relnotdef', 'Table @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-219, 335544872, 'domnotdef', 'Domain @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-230, 335544487, 'walw_err', 'WAL Writer error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-231, 335544488, 'logh_small', 'Log file header of @1 too small.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-232, 335544489, 'logh_inv_version', 'Invalid version of log file @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-233, 335544490, 'logh_open_flag', 'Log file @1 not latest in the chain but open flag still set.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-234, 335544491, 'logh_open_flag2', 'Log file @1 not closed properly; database recovery may be required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-235, 335544492, 'logh_diff_dbname', 'Database name in the log file @1 is different.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-236, 335544493, 'logf_unexpected_eof', 'Unexpected end of log file @1 at offset @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-237, 335544494, 'logr_incomplete', 'Incomplete log record at offset @1 in log file @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-238, 335544495, 'logr_header_small', 'Log record header too small at offset @1 in log file @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-239, 335544496, 'logb_small', 'Log block too small at offset @1 in log file @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-239, 335544691, 'cache_too_small', 'Insufficient memory to allocate page buffer cache.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-239, 335544693, 'log_too_small', 'Log size too small.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-239, 335544694, 'partition_too_small', 'Log partition size too small.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-243, 335544500, 'no_wal', 'Database does not use Write-ahead Log.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-257, 335544566, 'start_cm_for_wal', 'WAL defined; Cache Manager must be started first.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-260, 335544690, 'cache_redef', 'Cache redefined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-260, 335544692, 'log_redef', 'Log redefined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-261, 335544695, 'partition_not_supp', 'Partitions not supported in series of log file specification.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-261, 335544696, 'log_length_spec', 'Total length of a partitioned log must be specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-281, 335544637, 'no_stream_plan', 'Table @1 is not referenced in plan.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-282, 335544638, 'stream_twice', 'Table @1 is referenced more than once in plan; use aliases to distinguish.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-282, 335544643, 'dsql_self_join', 'The table @1 is referenced twice; use aliases to differentiate.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-282, 335544659, 'duplicate_base_table', 'Table @1 is referenced twice in view; use an alias to distinguish.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-282, 335544660, 'view_alias', 'View @1 has more than one base table; use aliases to distinguish.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-282, 335544710, 'complex_view', 'Navigational stream @1 references a view with more than one base table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-283, 335544639, 'stream_not_found', 'Table @1 is referenced in the plan but not the from list.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-284, 335544642, 'index_unused', 'Index @1 cannot be used in the specified plan.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-291, 335544531, 'primary_key_notnull', 'Column used in a PRIMARY constraint must be NOT NULL.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-292, 335544534, 'ref_cnstrnt_update', 'Cannot update constraints (RDB$REF_CONSTRAINTS).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-293, 335544535, 'check_cnstrnt_update', 'Cannot update constraints (RDB$CHECK_CONSTRAINTS).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-294, 335544536, 'check_cnstrnt_del', 'Cannot delete CHECK constraint entry (RDB$CHECK_CONSTRAINTS).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-295, 335544545, 'rel_cnstrnt_update', 'Cannot update constraints (RDB$RELATION_CONSTRAINTS).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-296, 335544547, 'invld_cnstrnt_type', 'Internal gds software consistency check (invalid RDB$CONSTRAINT_TYPE).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-297, 335544558, 'check_constraint', 'Operation violates CHECK constraint @1 on view or table @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-313, 336003099, 'upd_ins_doesnt_match_pk', 'UPDATE OR INSERT field list does not match primary key of table @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-313, 336003100, 'upd_ins_doesnt_match_matching', 'UPDATE OR INSERT field list does not match MATCHING clause.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-313, 335544669, 'dsql_count_mismatch', 'Count of column list and variable list do not match.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-314, 335544565, 'transliteration_failed', 'Cannot transliterate character between character sets.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-315, 336068815, 'dyn_dtype_invalid', 'Cannot change data type for column @1. Changing datatype is not supported for BLOB or ARRAY columns.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-383, 336068814, 'dyn_dependency_exists', 'Column @1 from table @2 is referenced in @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-401, 335544647, 'invalid_operator', 'Invalid comparison operator for find operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-402, 335544368, 'segstr_no_op', 'Attempted invalid operation on a BLOB.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-402, 335544414, 'blobnotsup', 'BLOB and array data types are not supported for @1 operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-402, 335544427, 'datnotsup', 'operation not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-406, 335544457, 'out_of_bounds', 'Subscript out of bounds.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-407, 335544435, 'nullsegkey', 'Null segment of UNIQUE KEY.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-413, 335544334, 'convert_error', 'Conversion error from string "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-413, 335544454, 'nofilter', 'Filter not found to convert type @1 to type @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-413, 335544860, 'blob_convert_error', 'Unsupported conversion to target type BLOB (subtype @1).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-413, 335544861, 'array_convert_error', 'Unsupported conversion to target type ARRAY.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-501, 335544577, 'dsql_cursor_close_err', 'Attempt to reclose a closed cursor.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 336003090, 'dsql_cursor_redefined', 'Statement already has a cursor @1 assigned.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 336003091, 'dsql_cursor_not_found', 'Cursor @1 is not found in the current context.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 336003092, 'dsql_cursor_exists', 'Cursor @1 already exists in the current context.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 336003093, 'dsql_cursor_rel_ambiguous', 'Relation @1 is ambiguous in cursor @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 336003094, 'dsql_cursor_rel_not_found', 'Relation @1 is not found in cursor @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 336003095, 'dsql_cursor_not_open', 'Cursor is not open.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 335544574, 'dsql_decl_err', 'Invalid cursor declaration.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-502, 335544576, 'dsql_cursor_open_err', 'Attempt to reopen an open cursor.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-504, 336003089, 'dsql_cursor_invalid', 'Empty cursor name is not allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-504, 335544572, 'dsql_cursor_err', 'Invalid cursor reference.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-508, 335544348, 'no_cur_rec', 'No current record for fetch operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-510, 335544575, 'dsql_cursor_update_err', 'Cursor @1 is not updatable.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-518, 335544582, 'dsql_request_err', 'Request unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-519, 335544688, 'dsql_open_cursor_request', 'The prepare statement identifies a prepare statement with an open cursor.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-530, 335544466, 'foreign_key', 'Violation of FOREIGN KEY constraint "@1" on table "@2".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-530, 335544838, 'foreign_key_target_doesnt_exist', 'Foreign key reference target does not exist.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-530, 335544839, 'foreign_key_references_present', 'Foreign key references are present for the record.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-531, 335544597, 'dsql_crdb_prepare_err', 'Cannot prepare a CREATE DATABASE/SCHEMA statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-532, 335544469, 'trans_invalid', 'Transaction marked invalid by I/O error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-551, 335544352, 'no_priv', 'No permission for @1 access to @2 @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-551, 335544790, 'insufficient_svc_privileges', 'Service @1 requires SYSDBA permissions. Reattach to the Service Manager using the SYSDBA account.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-552, 335544550, 'not_rel_owner', 'Only the owner of a table may reassign ownership.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-552, 335544553, 'grant_nopriv', 'User does not have GRANT privileges for operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-552, 335544707, 'grant_nopriv_on_base', 'User does not have GRANT privileges on base table/view for operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-553, 335544529, 'existing_priv_mod', 'Cannot modify an existing user privilege.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-595, 335544645, 'stream_crack', 'The current position is on a crack.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-596, 335544644, 'stream_bof', 'Illegal operation when at beginning of stream.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-597, 335544632, 'dsql_file_length_err', 'Preceding file did not specify length, so @1 must include starting page number.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-598, 335544633, 'dsql_shadow_number_err', 'Shadow number must be a positive integer.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-599, 335544607, 'node_err', 'Gen.c: node not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-599, 335544625, 'node_name_err', 'A node name is not permitted in a secondary, | shadow, cache or log file name.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-600, 335544680, 'crrp_data_err', 'Sort error: corruption in data structure.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-601, 335544646, 'db_or_file_exists', 'Database or file exists.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-604, 335544593, 'dsql_max_arr_dim_exceeded', 'Array declared with too many dimensions.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-604, 335544594, 'dsql_arr_range_error', 'Illegal array dimension range.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-605, 335544682, 'dsql_field_ref', 'Inappropriate self-reference of column.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 336003074, 'dsql_dbkey_from_non_table', 'Cannot SELECT RDB$DB_KEY from a stored procedure.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 336003086, 'dsql_udf_return_pos_err', 'External function should have return position between 1 and @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 336003096, 'dsql_type_not_supp_ext_tab', 'Data type @1 is not supported for EXTERNAL TABLES. Relation ''@2'', field ''@3''.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 335544351, 'no_meta_update', 'Unsuccessful metadata update.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 335544549, 'systrig_update', 'Cannot modify or erase a system trigger.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 335544657, 'dsql_no_blob_array', 'Array/BLOB/DATE data types not allowed in arithmetic.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 335544746, 'reftable_requires_pk', 'REFERENCES table without "(column)" requires PRIMARY KEY on referenced table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 335544815, 'generator_name', 'GENERATOR @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 335544816, 'udf_name', 'UDF @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 335544858, 'must_have_phys_field', 'Can''t have relation with only computed fields or constraints.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 336397206, 'dsql_table_not_found', 'Table @1 does not exist.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 336397207, 'dsql_view_not_found', 'View @1 does not exist.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 336397212, 'dsql_no_array_computed', 'Array and BLOB data types not allowed in computed field.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-607, 336397214, 'dsql_only_can_subscript_array', 'Scalar operator used on field @1 which is not an array.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-612, 336068812, 'dyn_domain_name_exists', 'Cannot rename domain @1 to @2. A domain with that name already exists.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-612, 336068813, 'dyn_field_name_exists', 'Cannot rename column @1 to @2. A column with that name already exists in table @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-615, 335544475, 'relation_lock', 'Lock on table @1 conflicts with existing lock.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-615, 335544476, 'record_lock', 'Requested record lock conflicts with existing lock.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-615, 335544507, 'range_in_use', 'Refresh range number @1 already in use.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544530, 'primary_key_ref', 'Cannot delete PRIMARY KEY being used in FOREIGN KEY definition.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544539, 'integ_index_del', 'Cannot delete index used by an integrity constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544540, 'integ_index_mod', 'Cannot modify index used by an integrity constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544541, 'check_trig_del', 'Cannot delete trigger used by a CHECK constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544543, 'cnstrnt_fld_del', 'Cannot delete column being used in an integrity constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544630, 'dependency', 'There are @1 dependencies.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544674, 'del_last_field', 'Last column in a table cannot be deleted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544728, 'integ_index_deactivate', 'Cannot deactivate index used by an integrity constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-616, 335544729, 'integ_deactivate_primary', 'Cannot deactivate index used by a PRIMARY/UNIQUE constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-617, 335544542, 'check_trig_update', 'Cannot update trigger used by a CHECK constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-617, 335544544, 'cnstrnt_fld_rename', 'Cannot rename column being used in an integrity constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-618, 335544537, 'integ_index_seg_del', 'Cannot delete index segment used by an integrity constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-618, 335544538, 'integ_index_seg_mod', '@@Cannot update index segment used by an integrity constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-625, 335544347, 'not_valid', 'Validation error for column @1, value "@2".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-625, 335544879, 'not_valid_for_var', 'Validation error for variable @1, value "@2".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-625, 335544880, 'not_valid_for', 'Validation error for @1, value "@2".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-637, 335544664, 'dsql_duplicate_spec', 'Duplicate specification of @1- not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-637, 336397213, 'dsql_implicit_domain_name', 'Implicit domain name @1 not allowed in user created domain.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-660, 336003098, 'primary_key_required', 'Primary key required on table @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-660, 335544533, 'foreign_key_notfound', 'Non-existent PRIMARY or UNIQUE KEY specified for FOREIGN KEY.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-660, 335544628, 'idx_create_err', 'Cannot create index @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-663, 335544624, 'idx_seg_err', 'Segment count of 0 defined for index @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-663, 335544631, 'idx_key_err', 'Too many keys defined for index @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-663, 335544672, 'key_field_err', 'Too few key columns found for index @1 (incorrect column name?).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-664, 335544434, 'keytoobig', 'Key size exceeds implementation restriction for index "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-677, 335544445, 'ext_err', '@1 extension error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-685, 335544465, 'bad_segstr_type', 'Invalid BLOB type for operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-685, 335544670, 'blob_idx_err', 'Attempt to index BLOB column in index @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-685, 335544671, 'array_idx_err', 'Attempt to index array column in index @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-689, 335544403, 'badpagtyp', 'Page@1 is of wrong type (expected @2, found @3).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-689, 335544650, 'page_type_err', 'Wrong page type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-690, 335544679, 'no_segments_err', 'Segments not allowed in expression index @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-691, 335544681, 'rec_size_err', 'New record size of @1 bytes is too big.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-692, 335544477, 'max_idx', 'Maximum indexes per table (@1) exceeded.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-693, 335544663, 'req_max_clones_exceeded', 'Too many concurrent executions of the same request.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-694, 335544684, 'no_field_access', 'Cannot access column @1 in view @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-802, 335544321, 'arith_except', 'Arithmetic exception, numeric overflow, or string truncation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-802, 335544836, 'concat_overflow', 'Concatenation overflow. Resulting string cannot exceed 32K in length.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-803, 335544349, 'no_dup', 'Attempt to store duplicate value (visible to active transactions) in unique index "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-803, 335544665, 'unique_key_violation', 'Violation of PRIMARY or UNIQUE KEY constraint "@1" on table "@2".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-804, 336003097, 'dsql_feature_not_supported_ods', 'Feature not supported on ODS version older than @1.@2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-804, 335544380, 'wronumarg', 'Wrong number of arguments on call.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-804, 335544583, 'dsql_sqlda_err', 'SQLDA missing or incorrect version, or incorrect number/type of variables.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-804, 335544584, 'dsql_var_count_err', 'Count of read-write columns does not equal count of values.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-804, 335544586, 'dsql_function_err', 'Function unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-804, 335544713, 'dsql_sqlda_value_err', 'Incorrect values within SQLDA structure.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-804, 336397205, 'dsql_too_old_ods', 'ODS versions before ODS@1 are not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-806, 335544600, 'col_name_err', 'Only simple column names permitted for VIEW WITH CHECK OPTION.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-807, 335544601, 'where_err', 'No WHERE clause for VIEW WITH CHECK OPTION.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-808, 335544602, 'table_view_err', 'Only one table allowed for VIEW WITH CHECK OPTION.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-809, 335544603, 'distinct_err', 'DISTINCT, GROUP or HAVING not permitted for VIEW WITH CHECK OPTION.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-810, 335544605, 'subquery_err', 'No subqueries permitted for VIEW WITH CHECK OPTION.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-811, 335544652, 'sing_select_err', 'Multiple rows in singleton select.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-816, 335544651, 'ext_readonly_err', 'Cannot insert because the file is readonly or is on a read only medium.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-816, 335544715, 'extfile_uns_op', 'Operation not supported for EXTERNAL FILE table @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 336003079, 'isc_sql_dialect_conflict_num', 'DB dialect @1 and client dialect @2 conflict with respect to numeric precision @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 336003101, 'upd_ins_with_complex_view', 'UPDATE OR INSERT without MATCHING could not be used with views based on more than one table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 336003102, 'dsql_incompatible_trigger_type', 'Incompatible trigger type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 336003103, 'dsql_db_trigger_type_cant_chang', 'Database trigger type can''t be changed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 335544361, 'read_only_trans', 'Attempted update during read-only transaction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 335544371, 'segstr_no_write', 'Attempted write to read-only BLOB.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 335544444, 'read_only', 'Operation not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 335544765, 'read_only_database', 'Attempted update on read-only database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 335544766, 'must_be_dialect_2_and_up', 'SQL dialect @1 is not supported in this database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-817, 335544793, 'ddl_not_allowed_by_db_sql_dial', 'Metadata update statement is not allowed by the current database SQL dialect @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-820, 335544356, 'obsolete_metadata', 'Metadata is obsolete.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-820, 335544379, 'wrong_ods', 'Unsupported on-disk structure for file @1; found @2.@3, support @4.@5.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-820, 335544437, 'wrodynver', 'Wrong DYN version.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-820, 335544467, 'high_minor', 'Minor version too high found @1 expected @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-820, 335544881, 'need_difference', 'Difference file name should be set explicitly for database on raw device.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-823, 335544473, 'invalid_bookmark', 'Invalid bookmark handle.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-824, 335544474, 'bad_lock_level', 'Invalid lock level @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-825, 335544519, 'bad_lock_handle', 'Invalid lock handle.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-826, 335544585, 'dsql_stmt_handle', 'Invalid statement handle.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-827, 335544655, 'invalid_direction', 'Invalid direction for find operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-827, 335544718, 'invalid_key', 'Invalid key for find operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-828, 335544678, 'inval_key_posn', 'Invalid key position.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 336068816, 'dyn_char_fld_too_small', 'New size specified for column @1 must be at least @2 characters.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 336068817, 'dyn_invalid_dtype_conversion', 'Cannot change data type for @1. Conversion from base type @2 to @3 is not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 336068818, 'dyn_dtype_conv_invalid', 'Cannot change data type for column @1 from a character type to a non-character type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 336068829, 'max_coll_per_charset', 'Maximum number of collations per character set exceeded.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 336068830, 'invalid_coll_attr', 'Invalid collation attributes.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 336068852, 'dyn_scale_too_big', 'New scale specified for column @1 must be at most @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 336068853, 'dyn_precision_too_small', 'New precision specified for column @1 must be at least @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-829, 335544616, 'field_ref_err', 'Invalid column reference.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-830, 335544615, 'field_aggregate_err', 'Column used with aggregate.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-831, 335544548, 'primary_key_exists', 'Attempt to define a second PRIMARY KEY for the same table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-832, 335544604, 'key_field_count_err', 'FOREIGN KEY column count does not match PRIMARY KEY.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-833, 335544606, 'expression_eval_err', 'Expression evaluation not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-833, 335544810, 'date_range_exceeded', 'Value exceeds the range for valid dates.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-834, 335544508, 'range_not_found', 'Refresh range number @1 not found.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-835, 335544649, 'bad_checksum', 'Bad checksum.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-836, 335544517, 'user_exc', 'Exception @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-836, 335544848, 'except2', 'Exception @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-837, 335544518, 'cache_restart', 'Restart shared cache manager.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-838, 335544560, 'shutwarn', 'Database @1 shutdown in @2 seconds.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-841, 335544677, 'version_err', 'Too many versions.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-842, 335544697, 'precision_err', 'Precision must be from 1 to 18.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-842, 335544698, 'scale_nogt', 'Scale must be between zero and precision.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-842, 335544699, 'expec_short', 'Short integer expected.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-842, 335544700, 'expec_long', 'Long integer expected.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-842, 335544701, 'expec_ushort', 'Unsigned short integer expected.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-842, 335544712, 'expec_positive', 'Positive value expected.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740929, 'gfix_db_name', 'Data base file name (@1) already given.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330753, 'gbak_unknown_switch', 'Found unknown switch.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336920577, 'gstat_unknown_switch', 'Found unknown switch.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336986113, 'fbsvcmgr_bad_am', 'Wrong value for access mode.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740930, 'gfix_invalid_sw', 'Invalid switch @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544322, 'bad_dbkey', 'Invalid database key.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336986114, 'fbsvcmgr_bad_wm', 'Wrong value for write mode.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330754, 'gbak_page_size_missing', 'Page size parameter missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336920578, 'gstat_retry', 'Please retry, giving a database name.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336986115, 'fbsvcmgr_bad_rs', 'Wrong value for reserve space.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336920579, 'gstat_wrong_ods', 'Wrong ODS version, expected @1, encountered @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330755, 'gbak_page_size_toobig', 'Page size specified (@1) greater than limit (16384 bytes).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740932, 'gfix_incmp_sw', 'Incompatible switch combination.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336920580, 'gstat_unexpected_eof', 'Unexpected end of database file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330756, 'gbak_redir_ouput_missing', 'Redirect location for output is not specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336986116, 'fbsvcmgr_info_err', 'Unknown tag (@1) in info_svr_db_info block after isc_svc_query().');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740933, 'gfix_replay_req', 'Replay log pathname required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330757, 'gbak_switches_conflict', 'Conflicting switches for backup/restore.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336986117, 'fbsvcmgr_query_err', 'Unknown tag (@1) in isc_svc_query() results.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544326, 'bad_dpb_form', 'Unrecognized database parameter block.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740934, 'gfix_pgbuf_req', 'Number of page buffers for cache required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336986118, 'fbsvcmgr_switch_unknown', 'Unknown switch "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330758, 'gbak_unknown_device', 'Device type @1 not known.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544327, 'bad_req_handle', 'Invalid request handle.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740935, 'gfix_val_req', 'Numeric value required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330759, 'gbak_no_protection', 'Protection is not there yet.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544328, 'bad_segstr_handle', 'Invalid BLOB handle.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740936, 'gfix_pval_req', 'Positive Numeric value required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330760, 'gbak_page_size_not_allowed', 'Page size is allowed only on restore or create.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544329, 'bad_segstr_id', 'Invalid BLOB ID.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740937, 'gfix_trn_req', 'Number of transactions per sweep required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330761, 'gbak_multi_source_dest', 'Multiple sources or destinations specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544330, 'bad_tpb_content', 'Invalid parameter in transaction parameter block.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330762, 'gbak_filename_missing', 'Requires both input and output filenames.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544331, 'bad_tpb_form', 'Invalid format for transaction parameter block.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330763, 'gbak_dup_inout_names', 'Input and output have the same name. Disallowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740940, 'gfix_full_req', 'full or "reserve" required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544332, 'bad_trans_handle', 'Invalid transaction handle (expecting explicit transaction start).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330764, 'gbak_inv_page_size', 'Expected page size, encountered "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740941, 'gfix_usrname_req', 'User name required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330765, 'gbak_db_specified', 'REPLACE specified, but the first file @1 is a database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740942, 'gfix_pass_req', 'Password required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330766, 'gbak_db_exists', 'Database @1 already exists. To replace it, use the -REP switch.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740943, 'gfix_subs_name', 'Subsystem name.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723983, 'gsec_cant_open_db', 'Unable to open database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330767, 'gbak_unk_device', 'Device type not specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723984, 'gsec_switches_error', 'Error in switch specifications.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740945, 'gfix_sec_req', 'Number of seconds required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544337, 'excess_trans', 'Attempt to start more than @1 transactions.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723985, 'gsec_no_op_spec', 'No operation specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740946, 'gfix_nval_req', 'Numeric value between 0 and 32767 inclusive required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723986, 'gsec_no_usr_name', 'No user name specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740947, 'gfix_type_shut', 'Must specify type of shutdown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544339, 'infinap', 'Information type inappropriate for object specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723987, 'gsec_err_add', 'Add record error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544340, 'infona', 'No information of this type available for object specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723988, 'gsec_err_modify', 'Modify record error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330772, 'gbak_blob_info_failed', 'Gds_$blob_info failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740948, 'gfix_retry', 'Please retry, specifying an option.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544341, 'infunk', 'Unknown information item.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723989, 'gsec_err_find_mod', 'Find/modify record error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330773, 'gbak_unk_blob_item', 'Do not understand BLOB INFO item @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544342, 'integ_fail', 'Action cancelled by trigger (@1) to preserve data integrity.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330774, 'gbak_get_seg_failed', 'Gds_$get_segment failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723990, 'gsec_err_rec_not_found', 'Record not found for user: @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723991, 'gsec_err_delete', 'Delete record error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330775, 'gbak_close_blob_failed', 'Gds_$close_blob failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740951, 'gfix_retry_db', 'Please retry, giving a database name.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330776, 'gbak_open_blob_failed', 'Gds_$open_blob failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723992, 'gsec_err_find_del', 'Find/delete record error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544345, 'lock_conflict', 'Lock conflict on no wait transaction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330777, 'gbak_put_blr_gen_id_failed', 'Failed in put_blr_gen_id.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330778, 'gbak_unk_type', 'Data type @1 not understood.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330779, 'gbak_comp_req_failed', 'Gds_$compile_request failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330780, 'gbak_start_req_failed', 'Gds_$start_request failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723996, 'gsec_err_find_disp', 'Find/display record error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330781, 'gbak_rec_failed', 'gds_$receive failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336920605, 'gstat_open_err', 'Can''t open database file @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723997, 'gsec_inv_param', 'Invalid parameter, no switch defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544350, 'no_finish', 'Program attempted to exit without finishing database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336920606, 'gstat_read_err', 'Can''t read a database page.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330782, 'gbak_rel_req_failed', 'Gds_$release_request failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723998, 'gsec_op_specified', 'Operation already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336920607, 'gstat_sysmemex', 'System memory exhausted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330783, 'gbak_db_info_failed', 'gds_$database_info failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336723999, 'gsec_pw_specified', 'Password already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724000, 'gsec_uid_specified', 'Uid already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330784, 'gbak_no_db_desc', 'Expected database description record.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544353, 'no_recon', 'Transaction is not in limbo.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724001, 'gsec_gid_specified', 'Gid already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330785, 'gbak_db_create_failed', 'Failed to create database @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724002, 'gsec_proj_specified', 'Project already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330786, 'gbak_decomp_len_error', 'RESTORE: decompression length error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544355, 'no_segstr_close', 'BLOB was not closed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330787, 'gbak_tbl_missing', 'Cannot find table @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724003, 'gsec_org_specified', 'Organization already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330788, 'gbak_blob_col_missing', 'Cannot find column for BLOB.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724004, 'gsec_fname_specified', 'First name already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544357, 'open_trans', 'Cannot disconnect database with open transactions (@1 active).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330789, 'gbak_create_blob_failed', 'Gds_$create_blob failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724005, 'gsec_mname_specified', 'Middle name already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544358, 'port_len', 'Message length error (encountered @1, expected @2).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330790, 'gbak_put_seg_failed', 'Gds_$put_segment failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724006, 'gsec_lname_specified', 'Last name already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330791, 'gbak_rec_len_exp', 'Expected record length.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724008, 'gsec_inv_switch', 'Invalid switch specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330792, 'gbak_inv_rec_len', 'Wrong length record, expected @1 encountered @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330793, 'gbak_exp_data_type', 'Expected data attribute.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724009, 'gsec_amb_switch', 'Ambiguous switch specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330794, 'gbak_gen_id_failed', 'Failed in store_blr_gen_id.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724010, 'gsec_no_op_specified', 'No operation specified for parameters.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544363, 'req_no_trans', 'No transaction for request.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330795, 'gbak_unk_rec_type', 'Do not recognize record type @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724011, 'gsec_params_not_allowed', 'No parameters allowed for this operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544364, 'req_sync', 'Request synchronization error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724012, 'gsec_incompat_switch', 'Incompatible switches specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330796, 'gbak_inv_bkup_ver', 'Expected backup version 1..8. Found @.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544365, 'req_wrong_db', 'Request referenced an unavailable database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330797, 'gbak_missing_bkup_desc', 'Expected backup description record.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330798, 'gbak_string_trunc', 'String truncated.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330799, 'gbak_cant_rest_record', 'warning record could not be restored.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330800, 'gbak_send_failed', 'Gds_$send failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544369, 'segstr_no_read', 'Attempted read of a new, open BLOB.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330801, 'gbak_no_tbl_name', 'No table name for data.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544370, 'segstr_no_trans', 'Attempted action on BLOB outside transaction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330802, 'gbak_unexp_eof', 'Unexpected end of file on backup file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330803, 'gbak_db_format_too_old', 'Database format @1 is too old to restore to.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544372, 'segstr_wrong_db', 'Attempted reference to BLOB in unavailable database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330804, 'gbak_inv_array_dim', 'Array dimension for column @1 is invalid.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330807, 'gbak_xdr_len_expected', 'Expected XDR record length.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544376, 'unres_rel', 'Table @1 was omitted from the transaction reserving list.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544377, 'uns_ext', 'Request includes a DSRI extension not supported in this implementation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544378, 'wish_list', 'Feature is not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544382, 'erased_rec', 'cannot update erased record in RC REC_VER'); -- <<< correction
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544383, 'fatal_conflict', 'Unrecoverable conflict with limbo transaction @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740991, 'gfix_exceed_max', 'Internal block exceeds maximum size.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740992, 'gfix_corrupt_pool', 'Corrupt pool.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740993, 'gfix_mem_exhausted', 'Virtual memory exhausted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330817, 'gbak_open_bkup_error', 'Cannot open backup file @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740994, 'gfix_bad_pool', 'Bad pool id.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330818, 'gbak_open_error', 'Cannot open status and error output file @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335740995, 'gfix_trn_not_valid', 'Transaction state @1 not in valid range.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544392, 'bdbincon', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724044, 'gsec_inv_username', 'Invalid user name (maximum 31 bytes allowed).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724045, 'gsec_inv_pw_length', 'Warning- maximum 8 significant bytes of password used.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724046, 'gsec_db_specified', 'Database already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724047, 'gsec_db_admin_specified', 'Database administrator name already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724048, 'gsec_db_admin_pw_specified', 'Database administrator password already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336724049, 'gsec_sql_role_specified', 'SQL role name already specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335741012, 'gfix_unexp_eoi', 'Unexpected end of input.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544407, 'dbbnotzer', 'Database handle not zero.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544408, 'tranotzer', 'Transaction handle not zero.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335741018, 'gfix_recon_fail', 'Failed to reconnect to a transaction in database @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544418, 'trainlim', 'Transaction in limbo.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544419, 'notinlim', 'Transaction not in limbo.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544420, 'traoutsta', 'Transaction outstanding.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544428, 'badmsgnum', 'Undefined message number.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335741036, 'gfix_trn_unknown', 'Transaction description item unknown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335741038, 'gfix_mode_req', 'read_only or "read_write" required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544431, 'blocking_signal', 'Blocking signal has been received.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335741042, 'gfix_pzval_req', 'Positive or zero numeric value required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544442, 'noargacc_read', 'Database system cannot read argument @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544443, 'noargacc_write', 'Database system cannot write argument @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544450, 'misc_interpreted', '@1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544468, 'tra_state', 'Transaction @1 is @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544485, 'bad_stmt_handle', 'Invalid statement handle.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330934, 'gbak_missing_block_fac', 'Blocking factor parameter missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330935, 'gbak_inv_block_fac', 'Expected blocking factor, encountered "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330936, 'gbak_block_fac_specified', 'A blocking factor may not be used in conjunction with device CT.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068796, 'dyn_role_does_not_exist', 'SQL role @1 does not exist.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330940, 'gbak_missing_username', 'User name parameter missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330941, 'gbak_missing_password', 'Password parameter missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068797, 'dyn_no_grant_admin_opt', 'User @1 has no grant admin option on SQL role @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544510, 'lock_timeout', 'Lock time-out on wait transaction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068798, 'dyn_user_not_role_member', 'User @1 is not a member of SQL role @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068799, 'dyn_delete_role_failed', '@1 is not the owner of SQL role @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068800, 'dyn_grant_role_to_user', '@1 is a SQL role and not a user.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068801, 'dyn_inv_sql_role_name', 'User name @1 could not be used for SQL role.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068802, 'dyn_dup_sql_role', 'SQL role @1 already exists.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068803, 'dyn_kywd_spec_for_role', 'Keyword @1 can not be used as a SQL role name.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068804, 'dyn_roles_not_supported', 'SQL roles are not supported in on older versions of the database. A backup and restore of the databa');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330952, 'gbak_missing_skipped_bytes', 'Missing parameter for the number of bytes to be skipped.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330953, 'gbak_inv_skipped_bytes', 'Expected number of bytes to be skipped, encountered "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068820, 'dyn_zero_len_id', 'Zero length identifiers are not allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330965, 'gbak_err_restore_charset', 'Character set.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330967, 'gbak_err_restore_collation', 'Collation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330972, 'gbak_read_error', 'Unexpected I/O error while reading from backup file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330973, 'gbak_write_error', 'Unexpected I/O error while writing to backup file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068840, 'dyn_wrong_gtt_scope', '@1 cannot reference @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330985, 'gbak_db_in_use', 'Could not drop database @1 (database might be in use).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336330990, 'gbak_sysmemex', 'System memory exhausted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544559, 'bad_svc_handle', 'Invalid service handle.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544561, 'wrospbver', 'Wrong version of service parameter block.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544562, 'bad_spb_form', 'Unrecognized service parameter block.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544563, 'svcnotdef', 'Service @1 is not defined.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336068856, 'dyn_ods_not_supp_feature', 'Feature ''@1'' is not supported in ODS @2.@3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331002, 'gbak_restore_role_failed', 'SQL role.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331005, 'gbak_role_op_missing', 'SQL role parameter missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331010, 'gbak_page_buffers_missing', 'Page buffers parameter missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331011, 'gbak_page_buffers_wrong_param', 'Expected page buffers, encountered "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331012, 'gbak_page_buffers_restore', 'Page buffers is allowed only on restore or create.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331014, 'gbak_inv_size', 'Size specification either missing or incorrect for file @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331015, 'gbak_file_outof_sequence', 'File @1 out of sequence.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331016, 'gbak_join_file_missing', 'Can''t join: one of the files missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331017, 'gbak_stdin_not_supptd', 'Standard input is not supported when using join operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331018, 'gbak_stdout_not_supptd', 'Standard output is not supported when using split operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331019, 'gbak_bkup_corrupt', 'Backup file @1 might be corrupt.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331020, 'gbak_unk_db_file_spec', 'Database file specification missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331021, 'gbak_hdr_write_failed', 'Can''t write a header record to file @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331022, 'gbak_disk_space_ex', 'Free disk space exhausted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331023, 'gbak_size_lt_min', 'File size given (@1) is less than minimum allowed (@2).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331025, 'gbak_svc_name_missing', 'Service name parameter missing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331026, 'gbak_not_ownr', 'Cannot restore over current database, must be SYSDBA or owner of the existing database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331031, 'gbak_mode_req', 'read_only or "read_write" required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331033, 'gbak_just_data', 'Just data ignore all constraints etc.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336331034, 'gbak_data_only', 'Restoring data only ignoring foreign key, unique, not null & other constraints.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544609, 'index_name', 'INDEX @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544610, 'exception_name', 'EXCEPTION @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544611, 'field_name', 'COLUMN @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544613, 'union_err', 'Union not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544614, 'dsql_construct_err', 'Unsupported DSQL construct.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544623, 'dsql_domain_err', 'Illegal use of keyword VALUE.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544626, 'table_name', 'TABLE @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544627, 'proc_name', 'PROCEDURE @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544641, 'dsql_domain_not_found', 'Specified domain or source column @1 does not exist.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544656, 'dsql_var_conflict', 'Variable @1 conflicts with parameter in same procedure.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544666, 'srvr_version_too_old', 'Server version too old to support all CREATE DATABASE options.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544673, 'no_delete', 'Cannot delete.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544675, 'sort_err', 'Sort error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544703, 'svcnoexe', 'Service @1 does not have an associated executable.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544704, 'net_lookup_err', 'Failed to locate host machine.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544705, 'service_unknown', 'Undefined service @1/@2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544706, 'host_unknown', 'The specified name was not found in the hosts file or Domain Name Services.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544711, 'unprepared_stmt', 'Attempt to execute an unprepared dynamic SQL statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544716, 'svc_in_use', 'Service is currently busy: @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544731, 'tra_must_sweep', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544740, 'udf_exception', 'A fatal exception occurred during the execution of a user defined function.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544741, 'lost_db_connection', 'Connection lost to database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544742, 'no_write_user_priv', 'User cannot write to RDB$USER_PRIVILEGES.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544767, 'blob_filter_exception', 'A fatal exception occurred during the execution of a blob filter.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544768, 'exception_access_violation', 'Access violation. The code attempted to access a virtual address without privilege to do so.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544769, 'exception_datatype_missalignmen', 'Data type misalignment. The attempted to read or write a value that was not stored on a memory bound');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544770, 'exception_array_bounds_exceeded', 'Array bounds exceeded. The code attempted to access an array element that is out of bounds.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544771, 'exception_float_denormal_operan', 'Float denormal operand. One of the floating-point operands is too small to represent a standard floa');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544772, 'exception_float_divide_by_zero', 'Floating-point divide by zero. The code attempted to divide a floating-point value by zero.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544773, 'exception_float_inexact_result', 'Floating-point inexact result. The result of a floating-point operation cannot be represented as a d');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544774, 'exception_float_invalid_operand', 'Floating-point invalid operand. An indeterminant error occurred during a floating-point operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544775, 'exception_float_overflow', 'Floating-point overflow. The exponent of a floating-point operation is greater than the magnitude al');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544776, 'exception_float_stack_check', 'Floating-point stack check. The stack overflowed or underflowed as the result of a floating-point op');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544777, 'exception_float_underflow', 'Floating-point underflow. The exponent of a floating-point operation is less than the magnitude allo');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544778, 'exception_integer_divide_by_zer', 'Integer divide by zero. The code attempted to divide an integer value by an integer divisor of zero.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544779, 'exception_integer_overflow', 'Integer overflow. The result of an integer operation caused the most significant bit of the result t');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544780, 'exception_unknown', 'An exception occurred that does not have a description. Exception number @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544781, 'exception_stack_overflow', 'Stack overflow. The resource requirements of the runtime stack have exceeded the memory available to');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544782, 'exception_sigsegv', 'Segmentation fault. The code attempted to access memory without privileges.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544783, 'exception_sigill', 'Illegal instruction. The code attempted to perform an illegal operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544784, 'exception_sigbus', 'Bus error. The code caused a system bus error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544785, 'exception_sigfpe', 'Floating point error. The code caused an arithmetic exception or a floating point exception.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544786, 'ext_file_delete', 'Cannot delete rows from external files.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544787, 'ext_file_modify', 'Cannot update rows in external files.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544788, 'adm_task_denied', 'Unable to perform operation. You must be either SYSDBA or owner of the database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544794, 'cancelled', 'Operation was cancelled.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544797, 'svcnouser', 'User name and password are required while attaching to the services manager.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544801, 'datype_notsup', 'Data type not supported for arithmetic.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544803, 'dialect_not_changed', 'Database dialect not changed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544804, 'database_create_failed', 'Unable to create database @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544805, 'inv_dialect_specified', 'Database dialect @1 is not a valid dialect.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544806, 'valid_db_dialects', 'Valid database dialects are @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544811, 'inv_client_dialect_specified', 'Passed client dialect @1 is not a valid dialect.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544812, 'valid_client_dialects', 'Valid client dialects are @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544814, 'service_not_supported', 'Services functionality will be supported in a later version of the product.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544820, 'invalid_savepoint', 'Unable to find savepoint with name @1 in transaction context.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544835, 'bad_shutdown_mode', 'Target shutdown mode is invalid for database "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544840, 'no_update', 'Cannot update.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544842, 'stack_trace', '@1.'); -- !! real trouble if this exc appears at the top of stack !!
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544843, 'ctx_var_not_found', 'Context variable @1 is not found in namespace @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544844, 'ctx_namespace_invalid', 'Invalid namespace name @1 passed to @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544845, 'ctx_too_big', 'Too many context variables.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544846, 'ctx_bad_argument', 'Invalid argument passed to @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544847, 'identifier_too_long', 'BLR syntax error. Identifier @1... is too long.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544859, 'invalid_time_precision', 'Time precision exceeds allowed range (0-@1).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544866, 'met_wrong_gtt_scope', '@1 cannot depend on @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544868, 'illegal_prc_type', 'Procedure @1 is not selectable (it does not contain a SUSPEND statement).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544869, 'invalid_sort_datatype', 'Data type @1 is not supported for sorting operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544870, 'collation_name', 'COLLATION @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544871, 'domain_name', 'DOMAIN @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544874, 'max_db_per_trans_allowed', 'A multi database transaction cannot span more than @1 databases.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544876, 'bad_proc_BLR', 'Error while parsing procedure @1''s BLR.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 335544877, 'key_too_big', 'Index key too big.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336397211, 'dsql_too_many_values', 'Too many values (more than @1) in member list to match against.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-901, 336397236, 'dsql_unsupp_feature_dialect', 'Feature is not supported in dialect @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544333, 'bug_check', 'Internal gds software consistency check (@1).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544335, 'db_corrupt', 'Database file appears corrupt (@1).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544344, 'io_error', 'I/O error for file "@2".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544346, 'metadata_corrupt', 'Corrupt system table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544373, 'sys_request', 'Operating system directive @1 failed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544384, 'badblk', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544385, 'invpoolcl', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544387, 'relbadblk', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544388, 'blktoobig', 'Block size exceeds implementation restriction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544394, 'badodsver', 'Incompatible version of on-disk structure.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544397, 'dirtypage', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544398, 'waifortra', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544399, 'doubleloc', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544400, 'nodnotfnd', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544401, 'dupnodfnd', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544402, 'locnotmar', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544404, 'corrupt', 'Database corrupted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544405, 'badpage', 'Checksum error on database page @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544406, 'badindex', 'Index is broken.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544409, 'trareqmis', 'Transaction request mismatch (synchronization error).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544410, 'badhndcnt', 'Bad handle count.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544411, 'wrotpbver', 'Wrong version of transaction parameter block.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544412, 'wroblrver', 'Unsupported BLR version (expected @1, encountered @2).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544413, 'wrodpbver', 'Wrong version of database parameter block.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544415, 'badrelation', 'Database corrupted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544416, 'nodetach', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544417, 'notremote', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544422, 'dbfile', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544423, 'orphan', 'Internal error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544432, 'lockmanerr', 'Lock manager error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544436, 'sqlerr', 'SQL error code = @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544448, 'bad_sec_info', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544449, 'invalid_sec_info', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544470, 'buf_invalid', 'Cache buffer for page @1 invalid.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544471, 'indexnotdefined', 'There is no index in table @1 with id @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544472, 'login', 'Your user name and password are not defined. Ask your database administrator to set up a Firebird lo');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544506, 'shutinprog', 'Database @1 shutdown in progress.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544528, 'shutdown', 'Database @1 shutdown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544557, 'shutfail', 'Database shutdown unsuccessful.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544569, 'dsql_error', 'Dynamic SQL Error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544653, 'psw_attach', 'Cannot attach to password database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544654, 'psw_start_trans', 'Cannot start transaction for password database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544717, 'err_stack_limit', 'Stack size insufficent to execute current request.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544721, 'network_error', 'Unable to complete network request to host "@1".');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544722, 'net_connect_err', 'Failed to establish a connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544723, 'net_connect_listen_err', 'Error while listening for an incoming connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544724, 'net_event_connect_err', 'Failed to establish a secondary connection for event processing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544725, 'net_event_listen_err', 'Error while listening for an incoming event connection request.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544726, 'net_read_err', 'Error reading data from the connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544727, 'net_write_err', 'Error writing data to the connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544732, 'unsupported_network_drive', 'Access to databases on file servers is not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544733, 'io_create_err', 'Error while trying to create file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544734, 'io_open_err', 'Error while trying to open file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544735, 'io_close_err', 'Error while trying to close file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544736, 'io_read_err', 'Error while trying to read from file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544737, 'io_write_err', 'Error while trying to write to file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544738, 'io_delete_err', 'Error while trying to delete file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544739, 'io_access_err', 'Error while trying to access file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544745, 'login_same_as_role_name', 'Your login @1 is same as one of the SQL role name. Ask your database administrator to set up a valid');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544791, 'file_in_use', 'The file @1 is currently in use by another process. Try again later.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544795, 'unexp_spb_form', 'Unexpected item in service parameter block, expected @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544809, 'extern_func_dir_error', 'Function @1 is in @2, which is not in a permitted directory for external functions.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544819, 'io_32bit_exceeded_err', 'File exceeded maximum size of 2GB. Add another database file or use a 64 bit I/O version of Firebird');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544831, 'conf_access_denied', 'Access to @1 "@2" is denied by server administrator.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544834, 'cursor_not_open', 'Cursor is not open.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544841, 'cursor_already_open', 'Cursor is already open.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544856, 'att_shutdown', 'Connection shutdown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-902, 335544882, 'long_login', 'Login name too long (@1 characters, maximum allowed @2).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544324, 'bad_db_handle', 'Invalid database handle (no active connection).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544375, 'unavailable', 'Unavailable database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544381, 'imp_exc', 'Implementation limit exceeded.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544386, 'nopoolids', 'Too many requests.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544389, 'bufexh', 'Buffer exhausted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544391, 'bufinuse', 'Buffer in use.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544393, 'reqinuse', 'Request in use.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544424, 'no_lock_mgr', 'No lock manager available.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544430, 'virmemexh', 'Unable to allocate memory from operating system.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544451, 'update_conflict', 'Update conflicts with concurrent update.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544453, 'obj_in_use', 'Object @1 is in use.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544455, 'shadow_accessed', 'Cannot attach active shadow file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544460, 'shadow_missing', 'A file in manual shadow @1 is unavailable.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544661, 'index_root_page_full', 'Cannot add index, index root page is full.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544676, 'sort_mem_err', 'Sort error: not enough memory.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544683, 'req_depth_exceeded', 'Request depth exceeded. (Recursive definition?)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544758, 'sort_rec_size_err', 'Sort record size of @1 bytes is too big.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544761, 'too_many_handles', 'Too many open handles to database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544792, 'service_att_err', 'Cannot attach to services manager.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544799, 'svc_name_missing', 'The service name was not specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544813, 'optimizer_between_err', 'Unsupported field type specified in BETWEEN predicate.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544827, 'exec_sql_invalid_arg', 'Invalid argument in EXECUTE STATEMENT cannot convert to string.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544828, 'exec_sql_invalid_req', 'Wrong request type in EXECUTE STATEMENT ''@1''.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544829, 'exec_sql_invalid_var', 'Variable type (position @1) in EXECUTE STATEMENT ''@2'' INTO does not match returned column type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544830, 'exec_sql_max_call_exceeded', 'Too many recursion levels of EXECUTE STATEMENT.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544832, 'wrong_backup_state', 'Cannot change difference file name while database is in backup mode.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544852, 'partner_idx_incompat_type', 'Partner index segment no @1 has incompatible data type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544857, 'blobtoobig', 'Maximum BLOB size exceeded.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544862, 'record_lock_not_supp', 'Stream does not support record locking.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544863, 'partner_idx_not_found', 'Cannot create foreign key constraint @1. Partner index does not exist or is inactive.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544864, 'tra_num_exc', 'Transactions count exceeded. Perform backup and restore to make database operable again.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544865, 'field_disappeared', 'Column has been unexpectedly deleted.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-904, 335544878, 'concurrent_transaction', 'Concurrent transaction number is @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-906, 335544744, 'max_att_exceeded', 'Maximum user count exceeded. Contact your database administrator.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-909, 335544667, 'drdb_completed_with_errs', 'Drop database completed with errors.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-911, 335544459, 'rec_in_limbo', 'Record from transaction @1 is stuck in limbo.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-913, 335544336, 'deadlock', 'Deadlock.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-922, 335544323, 'bad_db_format', 'File @1 is not a valid database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-923, 335544421, 'connect_reject', 'Connection rejected by remote interface.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-923, 335544461, 'cant_validate', 'Secondary server attachments cannot validate databases.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-923, 335544464, 'cant_start_logging', 'Secondary server attachments cannot start logging.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-924, 335544325, 'bad_dpb_content', 'Bad parameters on attach or create database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-924, 335544441, 'bad_detach', 'Database detach completed with errors.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-924, 335544648, 'conn_lost', 'Connection lost to pipe server.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-926, 335544447, 'no_rollback', 'No rollback performed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values(-999, 335544689, 'ib_error', 'Firebird error.');
commit;

-- REMOVE unneeded indices on field 'ID' for some tables if setting 'C_MINIMAL_PK_CREATION' = '1'
-- Prevent PK for: qdistr,qstorned,pdistr,pstorned - only if setting
-- 'HALT_TEST_ON_ERRORS' containing 'PK'
set term ^;
execute block as
    declare v_tab_name dm_dbobj;
    declare v_idx_name dm_dbobj;
    declare v_ctr_type dm_dbobj;
    declare v_ctr_name dm_dbobj;
    declare v_run_ddl varchar(128);
    declare v_rel_list varchar(255);
    declare v_halt_on_err_list dm_setting_value = ',,';
    declare v_log_pk_violation dm_setting_value = '1';
begin
    select s.svalue from settings s where s.mcode='HALT_TEST_ON_ERRORS'
    into v_halt_on_err_list; -- ',CK,'; ',CK,PK,'

    select s.svalue from settings s where s.mcode='LOG_PK_VIOLATION'
    into v_log_pk_violation; -- '1' or '0'

    if ( v_log_pk_violation = '1' or v_halt_on_err_list containing ',PK,'
       ) then
      --#####
        exit; -- PRESERVE PKs!
      --#####

    -- PK violation can occur only in these tables.
    -- If we have decided do not watch for PK violations than corresp. constraints
    -- can be removed now because actually there are no PK index from these tables
    -- which participates in any search/join etc:
    v_rel_list = 'doc_data,qdistr,qstorned,pdistr,pstorned'; -- 07.02.2015: do NOT remove doc_data from here!
    ------------------------------------------------------------------------
    for
        -- get only PK or ASCENDING UNIQUE indices on field 'ID'
        -- for tables from :v_rel_list
        select
            --ri.*,'#'l,rs.*,'#'ll,rc.*
            ri.rdb$relation_name tab_name, ri.rdb$index_name idx_name,
            rc.rdb$constraint_type ctr_type, rc.rdb$constraint_name ctr_name
        from rdb$indices ri
        join rdb$index_segments rs on ri.rdb$index_name = rs.rdb$index_name
        left join rdb$relation_constraints rc on
            ri.rdb$relation_name=rc.rdb$relation_name
            and ri.rdb$index_name = rc.rdb$index_name
        and lower(rc.rdb$constraint_type) in ('primary key','unique')
                    where
                        ri.rdb$index_type is distinct from 1 -- only asc indices or PK
                        and position( ','||lower(trim(ri.rdb$relation_name))||',' in ','|| :v_rel_list ||',') > 0
                        and lower(rs.rdb$field_name)='id'
    into v_tab_name, v_idx_name, v_ctr_type, v_ctr_name
    do begin
        v_run_ddl =
            iif( v_ctr_name is not null,
                'alter table '||trim(v_tab_name)||' drop constraint '||trim(v_ctr_name),
                'drop index '||trim(v_idx_name)
            );
        execute statement(v_run_ddl) with autonomous transaction;
    end

end
^
set term ;^
commit;

-- moved into 1build_oltp_emul.bat: execute procedure init_autogen_qdistr_tables; -- 29.08.2015, branch: create_with_split_heavy_tabs

set list on;
set echo off;
select 'oltp_main_filling.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;
-- #############################################################################
-- End of script oltp_main_filling.sql; next to be run: 
-- (common for both FB 2.5 and 3.0)
-- 1) if config parameter 'create_with_split_heavy_tabs' = 1 then oltp_autogen_ddl.sql 
-- 2) else oltp_data_filling.sql
-- #############################################################################

