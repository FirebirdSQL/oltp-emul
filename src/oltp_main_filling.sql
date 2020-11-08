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
insert into semaphores(id, task, dts) values(2, 'srv_recalc_idx_stat', 'YESTERDAY');
insert into semaphores(id, task) values(3, 'srv_make_invnt_saldo');

-- 18.03.2019: serialize access to SP srv_autogen_aggregate_perf_data
-- (this SP will be called with frequency ~= srv_make*_saldo, in order to reduce time
-- of calculating final reports: datasource changed from v_perf_log to perf_agg)
insert into semaphores(id, task) values(4, 'srv_aggregate_perf_data');
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
                      '*** TAKE AT RUNTIME FROM CONFIG ***' -- value from config
                    ); 

-- ::: NB ::: This record is created here only as 'stub'.
-- Value of this variable will be replaced with config parameter 'used_in_replication'
--  by 1run_oltp_emul.bat (.sh) every time test is launched.
insert into settings(working_mode, mcode,                 svalue)
              values('COMMON',       'USED_IN_REPLICATION', 
                      '*** TAKE AT RUNTIME FROM CONFIG ***' -- value from config
                    );


-- @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
-- Moved here from .bat and .sh 03.10.2018:
-- @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
insert into settings(working_mode, mcode, context,svalue,init_on)
            values(  'COMMON'                       -- working_mode
                    ,'BUILD_WITH_SPLIT_HEAVY_TABS'  -- mcode
                    ,'USER_SESSION'                 -- context
                    ,'*** TAKE AT BUILD PHASE FROM CONFIG ***' -- value from config
                    ,'db_prepare'                   -- init_on
                  );

-- Inject setting which will force to create either one compound index for table
-- QDistr (or its XQD* clones) or split columns on two separate indices.
-- When setting 'create_with_split_heavy_tabs' is 0 then one of these indices is
-- still compund but contain three fields instead of four.
-- When setting 'create_with_split_heavy_tabs' is 0 then each XQD* table will have
-- either compound index of two fields or two single-field indices.
insert into settings(working_mode, mcode, context,svalue,init_on)
            values(  'COMMON'                       -- working_mode
                    ,'BUILD_WITH_SEPAR_QDISTR_IDX'  -- mcode
                    ,'USER_SESSION'                 -- context
                    ,'*** TAKE AT BUILD PHASE FROM CONFIG ***' -- value from config
                    ,'db_prepare'                   -- init_on
                  );

-- Inject setting for making columns order in compound index
-- according to the config setting 'create_with_compound_columns_order'.
-- actual only when setting 'create_with_split_heavy_tabs' = 0.
insert into settings(working_mode, mcode, context,svalue,init_on)
        values(  'COMMON'                       -- working_mode
            ,'BUILD_WITH_QD_COMPOUND_ORDR'  -- mcode
            ,'USER_SESSION'                 -- context
            ,'*** TAKE AT BUILD PHASE FROM CONFIG ***' -- value from config
            ,'db_prepare'                   -- init_on
          );


insert into settings(working_mode, mcode,           svalue)
              values( 'COMMON',     
                      'SEPARATE_WORKERS', 
                      '*** TAKE AT RUNTIME FROM CONFIG ***' -- value from config
                    );
--                      '*** INJECT AT RUNTIME: TEST LAUNCH PARAM ***'

insert into settings(working_mode, mcode,           svalue)
              values( 'COMMON',     
                      'WORKERS_COUNT', 
                      '*** INJECT AT RUNTIME: TEST LAUNCH PARAM ***' -- value from command line: second argument for '1run_oltp_emul' scenario
                    );


insert into settings(working_mode, mcode,           svalue)
              values( 'COMMON',     
                      'UPDATE_CONFLICT_PERCENT', 
                      '*** TAKE AT RUNTIME FROM CONFIG ***' -- value from config
                    );


insert into settings(working_mode, mcode,           svalue)
              values(  'COMMON'
                      ,'UNIT_SELECTION_METHOD'
                      ,'*** TAKE AT RUNTIME FROM CONFIG ***' -- value from config
                    );

insert into settings(working_mode, mcode, svalue, description)
              values(  'COMMON'
                      ,'ENABLE_MON_QUERY'
                      ,'*** TAKE AT RUNTIME FROM CONFIG ***' -- value from config
                      ,'0 =  do not gather mon$ tables at all; 1 = gather mon$ tables before and after each Tx, in every ISQL session'
                    );


insert into settings(working_mode, mcode, svalue ,description)
              values( 'COMMON'
                     ,'MON_UNIT_LIST'
                     ,'*** TAKE AT RUNTIME FROM CONFIG ***'
                     ,'Units that are subject to gathering MON$ statistics'
                    );


insert into settings(working_mode, mcode, svalue, description)
              values( 'COMMON'
                     ,'HALT_TEST_ON_ERRORS'
                     ,'*** TAKE AT RUNTIME FROM CONFIG ***'
                     ,'Mnemonics of exceptions which forces test to be stopped (see calls of fn_halt_sign(gdscode))'
                    );

insert into settings(working_mode, mcode, svalue, description)
              values( 'COMMON'
                      ,'QMISM_VERIFY_BITSET'
                      ,'*** TAKE AT RUNTIME FROM CONFIG ***'
                      ,'How stock remainders should be verified BEFORE totalling'
                    ); -- default: '1'; changed to '0' for branch 'create_with_split_heavy_tabs'

insert into settings(working_mode, mcode, svalue, description)
              values( 'COMMON'
                     ,'RECALC_IDX_MIN_INTERVAL'
                     ,'*** TAKE AT RUNTIME FROM CONFIG ***' --- recommened value: no less than 30
                     ,'Minimal interval in minutes between two subsequent calls of SP srv_recalc_idx_stat'
                    );

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

-- number of rows which should be added into Pdistr for every new cost
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
^

/************************
create or alter procedure sp_rules_for_qdistr returns(
    mode           dm_name
    ,snd_optype_id  smallint
    ,rcv_optype_id  smallint
    ,storno_sub     smallint
) as
begin
    -- 29.03.2019
    mode = 'new_doc_only';   snd_optype_id = NULL; rcv_optype_id = 1000; storno_sub = NULL; suspend;
    mode = 'distr+new_doc';  snd_optype_id = 1000; rcv_optype_id = 1200; storno_sub = 1;    suspend;
    mode = 'distr+new_doc';  snd_optype_id = 1200; rcv_optype_id = 2000; storno_sub = 1;    suspend;
    mode = 'mult_rows_only'; snd_optype_id = 1000; rcv_optype_id = 3300; storno_sub = 2;    suspend;
    mode = 'mult_rows_only'; snd_optype_id = 2000; rcv_optype_id = 3300; storno_sub = NULL; suspend;
    mode = 'distr+new_doc';  snd_optype_id = 2100; rcv_optype_id = 3300; storno_sub = 1;    suspend;
    mode = 'new_doc_only';   snd_optype_id = 3300; rcv_optype_id = 3400; storno_sub = NULL; suspend;
end
^

create or alter procedure sp_rules_for_pdistr returns(
    mode           dm_name
    ,snd_optype_id  smallint
    ,rcv_optype_id  smallint
    ,rows_to_multiply int
) as
begin
    -- 29.03.2019
    mode = ''; snd_optype_id = 5000; rcv_optype_id = 3400; rows_to_multiply = 10; suspend;
    mode = ''; snd_optype_id = 3400; rcv_optype_id = 5000; rows_to_multiply = 10; suspend;
    mode = ''; snd_optype_id = 4000; rcv_optype_id = 2100; rows_to_multiply = 10; suspend;
    mode = ''; snd_optype_id = 2100; rcv_optype_id = 4000; rows_to_multiply = 10; suspend;
end
^

*************************/

set term ;^
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
insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values( 'sp_client_order',             'stock', 'creation',      95,                      100,        100,                            'customer order: creation');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_cancel_client_order',       'stock',  'removal',      30,                      120,        1600,                           'customer order: refuse');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values( 'sp_supplier_order',           'stock', 'creation',      65,                      200,        200,                            'order to supplier: creation');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_cancel_supplier_order',     'stock',  'removal',      10,                      220,        1500,                           'order to supplier: removal');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values( 'sp_supplier_invoice',         'stock', 'creation',      65,                      300,        300,                            'invoice (draft): creation');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values( 'sp_cancel_supplier_invoice',  'stock',  'removal',      10,                      320,        1400,                           'invoice (draft): removal');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values( 'sp_add_invoice_to_stock',     'stock',  'state_next',   62,                      400,        400,                            'invoice accept: apply');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_cancel_adding_invoice',     'stock',  'state_back',   10,                      420,        1300,                           'invoice accept: cancel');

-- nb: we can set LOW prior to sp_customer_reserve because most of these docs
-- will be created from sp_add_invoice_to_stock and only several percents
-- from avaliable remainders:
insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_customer_reserve',          'stock',  'creation',     20,                      500,        500,                            'customer reserve: creation');
--
insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_cancel_customer_reserve',   'stock',  'removal',      15,                      520,        1200,                           'customer reserve: removal');
--
insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_reserve_write_off',         'stock',  'state_next',   80,                      600,        600,                            'realization accept: apply');

insert into business_ops(
        unit,                          mode,     kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_cancel_write_off',          'stock',  'state_back',   20,                      620,        1100,                           'realization accept: cancel');

insert into business_ops(
        unit,                        mode,       kind,           random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_pay_from_customer',       'payments',  'creation',     72,                      700,        550,                           'payment from customer: creation');

insert into business_ops(
        unit,                         mode,       kind,          random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_cancel_pay_from_customer', 'payments', 'removal',     15,                      720,        1000,                           'payment from customer: removal');

insert into business_ops(
        unit,                         mode,         kind,        random_selection_weight, sort_prior, predictable_selection_priority, info )
values('sp_pay_to_supplier',          'payments',   'creation',  67,                      800,        450,                            'payment to supplier: creation');

insert into business_ops(
        unit,                         mode,       kind,          random_selection_weight, sort_prior, predictable_selection_priority, info )
values( 'sp_cancel_pay_to_supplier',  'payments', 'removal',     10,                      820,        1050,                           'payment to supplier: removal');

---
insert into business_ops(
        unit,                         mode,       kind,          random_selection_weight, sort_prior, predictable_selection_priority, info )
values('srv_make_invnt_saldo',        'service',  'service',     35,                      990,        9990,                           'service: total inventory turnovers');

-- 12.01.2019. Increased frequency for gathering money turnovers from 25 to 33.
insert into business_ops(
        unit,                         mode,       kind,          random_selection_weight, sort_prior, predictable_selection_priority, info )
values('srv_make_money_saldo',        'service',  'service',     33,                      993,        9991,                           'service: total monetary turnovers');


-- 18.03.2019: task for aggregating data from perf_log / perf_split_NN in order to reduce time of reports creation:
insert into business_ops(
        unit,                         mode,       kind,          random_selection_weight, sort_prior, predictable_selection_priority, info )
values('srv_aggregate_perf_data',     'service',  'service',      5,                      995,        9992,                           'service: aggregate perf. data');


-- 12.01.2019. Algorithm of selection SP srv_recalc_idx_stat in srv_random_unit_choice has been changed: this routine must be launched **ALWAYS**
-- when number of minutes since its previous run exceeds config parameter 'recalc_idx_min_interval' (e.g. 30 minutes). Otherwise it should be SKIPPED from selection.
-- In order to make this possible, new field was added to table 'semaphores' with storing TIMESTAMP of last run.
insert into business_ops(
        unit,                         mode,       kind,          random_selection_weight, sort_prior, predictable_selection_priority, info )
values('srv_recalc_idx_stat',         'service',  'service',     99,                      997,        9993,                           'service: refresh index statistics');


-- need only to check FB stability against extremely high frequency of MON$-querying:
-- --update business_ops b set b.random_selection_weight=40 where b.unit='srv_fill_mon'; commit;
-- delete from business_ops b where b.unit='srv_fill_mon'; commit;
--insert into business_ops( unit, mode, kind, random_selection_weight, sort_prior, predictable_selection_priority, info )
--values('srv_fill_mon',         'service', 'service',         40, 999, 9995,  '(temply) stability test when querying mon$-tables');

update business_ops set unit = lower(unit); -- see SP srv_increment_tx_bops_counter: we have to be sure that business unit always be found there, but we can escape CI-collate here.
commit;

--------------------------------------------------------------------------------
-- ##################   FIREBIRD STANDARD ERROR CODES   ########################
--------------------------------------------------------------------------------
delete from fb_errors;
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 335544321, 'arith_except', 'arithmetic exception, numeric overflow, or string truncation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544322, 'bad_dbkey', 'invalid database key');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -922, 335544323, 'bad_db_format', 'file @1 is not a valid database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544324, 'bad_db_handle', 'invalid database handle (no active connection)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335544325, 'bad_dpb_content', 'bad parameters on attach or create database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544326, 'bad_dpb_form', 'unrecognized database parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544327, 'bad_req_handle', 'invalid request handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544328, 'bad_segstr_handle', 'invalid BLOB handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544329, 'bad_segstr_id', 'invalid BLOB ID');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544330, 'bad_tpb_content', 'invalid parameter in transaction parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544331, 'bad_tpb_form', 'invalid format for transaction parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544332, 'bad_trans_handle', 'invalid transaction handle (expecting explicit transaction start)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544333, 'bug_check', 'internal Firebird consistency check (@1)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -413, 335544334, 'convert_error', 'conversion error from string \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544335, 'db_corrupt', 'database file appears corrupt (@1)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -913, 335544336, 'deadlock', 'deadlock');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544337, 'excess_trans', 'attempt to start more than @1 transactions');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 100, 335544338, 'from_no_match', 'no match for first value expression');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544339, 'infinap', 'information type inappropriate for object specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544340, 'infona', 'no information of this type available for object specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544341, 'infunk', 'unknown information item');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544342, 'integ_fail', 'action cancelled by trigger (@1) to preserve data integrity');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544343, 'invalid_blr', 'invalid request BLR at offset @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544344, 'io_error', 'I/O error during \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544345, 'lock_conflict', 'lock conflict on no wait transaction');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544346, 'metadata_corrupt', 'corrupt system table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -625, 335544347, 'not_valid', 'validation error for column @1, value \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -508, 335544348, 'no_cur_rec', 'no current record for fetch operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -803, 335544349, 'no_dup', 'attempt to store duplicate value (visible to active transactions) in unique index \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544350, 'no_finish', 'program attempted to exit without finishing database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 335544351, 'no_meta_update', 'unsuccessful metadata update');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -551, 335544352, 'no_priv', 'no permission for @1 access to @2 @3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544353, 'no_recon', 'transaction is not in limbo');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 100, 335544354, 'no_record', 'invalid database key');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544355, 'no_segstr_close', 'BLOB was not closed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -820, 335544356, 'obsolete_metadata', 'metadata is obsolete');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544357, 'open_trans', 'cannot disconnect database with open transactions (@1 active)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544358, 'port_len', 'message length error (encountered @1, expected @2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -151, 335544359, 'read_only_field', 'attempted update of read-only column @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -150, 335544360, 'read_only_rel', 'attempted update of read-only table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 335544361, 'read_only_trans', 'attempted update during read-only transaction');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -150, 335544362, 'read_only_view', 'cannot update read-only view @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544363, 'req_no_trans', 'no transaction for request');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544364, 'req_sync', 'request synchronization error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544365, 'req_wrong_db', 'request referenced an unavailable database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 101, 335544366, 'segment', 'segment buffer length shorter than expected');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 100, 335544367, 'segstr_eof', 'attempted retrieval of more segments than exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -402, 335544368, 'segstr_no_op', 'attempted invalid operation on a BLOB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544369, 'segstr_no_read', 'attempted read of a new, open BLOB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544370, 'segstr_no_trans', 'attempted action on BLOB outside transaction');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 335544371, 'segstr_no_write', 'attempted write to read-only BLOB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544372, 'segstr_wrong_db', 'attempted reference to BLOB in unavailable database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544373, 'sys_request', 'operating system directive @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -596, 335544374, 'stream_eof', 'attempt to fetch past the last record in a record stream');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544375, 'unavailable', 'unavailable database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544376, 'unres_rel', 'table @1 was omitted from the transaction reserving list');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544377, 'uns_ext', 'request includes a DSRI extension not supported in this implementation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544378, 'wish_list', 'feature is not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -820, 335544379, 'wrong_ods', 'unsupported on-disk structure for file @1; found @2.@3, support @4.@5');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335544380, 'wronumarg', 'wrong number of arguments on call');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544381, 'imp_exc', 'Implementation limit exceeded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544382, 'random', '@1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544383, 'fatal_conflict', 'unrecoverable conflict with limbo transaction @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544384, 'badblk', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544385, 'invpoolcl', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544386, 'nopoolids', 'too many requests');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544387, 'relbadblk', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544388, 'blktoobig', 'block size exceeds implementation restriction');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544389, 'bufexh', 'buffer exhausted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544390, 'syntaxerr', 'BLR syntax error: expected @1 at offset @2, encountered @3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544391, 'bufinuse', 'buffer in use');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544392, 'bdbincon', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544393, 'reqinuse', 'request in use');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544394, 'badodsver', 'incompatible version of on-disk structure');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -219, 335544395, 'relnotdef', 'table @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -205, 335544396, 'fldnotdef', 'column @1 is not defined in table @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544397, 'dirtypage', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544398, 'waifortra', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544399, 'doubleloc', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544400, 'nodnotfnd', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544401, 'dupnodfnd', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544402, 'locnotmar', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -689, 335544403, 'badpagtyp', 'page @1 is of wrong type (expected @2, found @3)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544404, 'corrupt', 'database corrupted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544405, 'badpage', 'checksum error on database page @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544406, 'badindex', 'index is broken');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544407, 'dbbnotzer', 'database handle not zero');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544408, 'tranotzer', 'transaction handle not zero');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544409, 'trareqmis', 'transaction--request mismatch (synchronization error)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544410, 'badhndcnt', 'bad handle count');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544411, 'wrotpbver', 'wrong version of transaction parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544412, 'wroblrver', 'unsupported BLR version (expected @1, encountered @2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544413, 'wrodpbver', 'wrong version of database parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -402, 335544414, 'blobnotsup', 'BLOB and array data types are not supported for @1 operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544415, 'badrelation', 'database corrupted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544416, 'nodetach', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544417, 'notremote', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544418, 'trainlim', 'transaction in limbo');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544419, 'notinlim', 'transaction not in limbo');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544420, 'traoutsta', 'transaction outstanding');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -923, 335544421, 'connect_reject', 'connection rejected by remote interface');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544422, 'dbfile', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544423, 'orphan', 'internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544424, 'no_lock_mgr', 'no lock manager available');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544425, 'ctxinuse', 'context already in use (BLR error)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544426, 'ctxnotdef', 'context not defined (BLR error)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -402, 335544427, 'datnotsup', 'data operation not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544428, 'badmsgnum', 'undefined message number');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544429, 'badparnum', 'undefined parameter number');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544430, 'virmemexh', 'unable to allocate memory from operating system');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544431, 'blocking_signal', 'blocking signal has been received');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544432, 'lockmanerr', 'lock manager error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335544433, 'journerr', 'communication error with journal \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -664, 335544434, 'keytoobig', 'key size exceeds implementation restriction for index \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -407, 335544435, 'nullsegkey', 'null segment of UNIQUE KEY');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544436, 'sqlerr', 'SQL error code = @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -820, 335544437, 'wrodynver', 'wrong DYN version');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -172, 335544438, 'funnotdef', 'function @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -171, 335544439, 'funmismat', 'function @1 could not be matched');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544440, 'bad_msg_vec', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335544441, 'bad_detach', 'database detach completed with errors');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544442, 'noargacc_read', 'database system cannot read argument @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544443, 'noargacc_write', 'database system cannot write argument @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 335544444, 'read_only', 'operation not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -677, 335544445, 'ext_err', '@1 extension error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -150, 335544446, 'non_updatable', 'not updatable');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -926, 335544447, 'no_rollback', 'no rollback performed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544448, 'bad_sec_info', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544449, 'invalid_sec_info', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544450, 'misc_interpreted', '@1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544451, 'update_conflict', 'update conflicts with concurrent update');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -906, 335544452, 'unlicensed', 'product @1 is not licensed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544453, 'obj_in_use', 'object @1 is in use');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -413, 335544454, 'nofilter', 'filter not found to convert type @1 to type @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544455, 'shadow_accessed', 'cannot attach active shadow file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544456, 'invalid_sdl', 'invalid slice description language at offset @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -406, 335544457, 'out_of_bounds', 'subscript out of bounds');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -171, 335544458, 'invalid_dimension', 'column not array or invalid dimensions (expected @1, encountered @2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -911, 335544459, 'rec_in_limbo', 'record from transaction @1 is stuck in limbo');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544460, 'shadow_missing', 'a file in manual shadow @1 is unavailable');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -923, 335544461, 'cant_validate', 'secondary server attachments cannot validate databases');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -923, 335544462, 'cant_start_journal', 'secondary server attachments cannot start journaling');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544463, 'gennotdef', 'generator @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -923, 335544464, 'cant_start_logging', 'secondary server attachments cannot start logging');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -685, 335544465, 'bad_segstr_type', 'invalid BLOB type for operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -530, 335544466, 'foreign_key', 'violation of FOREIGN KEY constraint \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -820, 335544467, 'high_minor', 'minor version too high found @1 expected @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544468, 'tra_state', 'transaction @1 is @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -532, 335544469, 'trans_invalid', 'transaction marked invalid and cannot be committed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544470, 'buf_invalid', 'cache buffer for page @1 invalid');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544471, 'indexnotdefined', 'there is no index in table @1 with id @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544472, 'login', 'Your user name and password are not defined. Ask your database administrator to set up a Firebird login.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -823, 335544473, 'invalid_bookmark', 'invalid bookmark handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -824, 335544474, 'bad_lock_level', 'invalid lock level @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -615, 335544475, 'relation_lock', 'lock on table @1 conflicts with existing lock');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -615, 335544476, 'record_lock', 'requested record lock conflicts with existing lock');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -692, 335544477, 'max_idx', 'maximum indexes per table (@1) exceeded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544478, 'jrn_enable', 'enable journal for database before starting online dump');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544479, 'old_failure', 'online dump failure. Retry dump');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544480, 'old_in_progress', 'an online dump is already in progress');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544481, 'old_no_space', 'no more disk/tape space.  Cannot continue online dump');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544482, 'no_wal_no_jrn', 'journaling allowed only if database has Write-ahead Log');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544483, 'num_old_files', 'maximum number of online dump files that can be specified is 16');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544484, 'wal_file_open', 'error in opening Write-ahead Log file during recovery');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544485, 'bad_stmt_handle', 'invalid statement handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544486, 'wal_failure', 'Write-ahead log subsystem failure');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -230, 335544487, 'walw_err', 'WAL Writer error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -231, 335544488, 'logh_small', 'Log file header of @1 too small');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -232, 335544489, 'logh_inv_version', 'Invalid version of log file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -233, 335544490, 'logh_open_flag', 'Log file @1 not latest in the chain but open flag still set');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -234, 335544491, 'logh_open_flag2', 'Log file @1 not closed properly; database recovery may be required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -235, 335544492, 'logh_diff_dbname', 'Database name in the log file @1 is different');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -236, 335544493, 'logf_unexpected_eof', 'Unexpected end of log file @1 at offset @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -237, 335544494, 'logr_incomplete', 'Incomplete log record at offset @1 in log file @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -238, 335544495, 'logr_header_small', 'Log record header too small at offset @1 in log file @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -239, 335544496, 'logb_small', 'Log block too small at offset @1 in log file @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -240, 335544497, 'wal_illegal_attach', 'Illegal attempt to attach to an uninitialized WAL segment for @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -241, 335544498, 'wal_invalid_wpb', 'Invalid WAL parameter block option @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -242, 335544499, 'wal_err_rollover', 'Cannot roll over to the next log file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -243, 335544500, 'no_wal', 'database does not use Write-ahead Log');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -615, 335544501, 'drop_wal', 'cannot drop log file when journaling is enabled');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544502, 'stream_not_defined', 'reference to invalid stream number');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -244, 335544503, 'wal_subsys_error', 'WAL subsystem encountered error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -245, 335544504, 'wal_subsys_corrupt', 'WAL subsystem corrupted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544505, 'no_archive', 'must specify archive file when enabling long term journal for databases with round-robin log files');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544506, 'shutinprog', 'database @1 shutdown in progress');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -615, 335544507, 'range_in_use', 'refresh range number @1 already in use');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -834, 335544508, 'range_not_found', 'refresh range number @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544509, 'charset_not_found', 'CHARACTER SET @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544510, 'lock_timeout', 'lock time-out on wait transaction');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544511, 'prcnotdef', 'procedure @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -170, 335544512, 'prcmismat', 'Input parameter mismatch for procedure @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -246, 335544513, 'wal_bugcheck', 'Database @1: WAL subsystem bug for pid @2\@3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -247, 335544514, 'wal_cant_expand', 'Could not expand the WAL segment for database @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544515, 'codnotdef', 'status code @1 unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544516, 'xcpnotdef', 'exception @1 not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -836, 335544517, 'except', 'exception @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -837, 335544518, 'cache_restart', 'restart shared cache manager');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -825, 335544519, 'bad_lock_handle', 'invalid lock handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544520, 'jrn_present', 'long-term journaling already enabled');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -248, 335544521, 'wal_err_rollover2', 'Unable to roll over please see Firebird log.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -249, 335544522, 'wal_err_logwrite', 'WAL I/O error.  Please see Firebird log.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -250, 335544523, 'wal_err_jrn_comm', 'WAL writer - Journal server communication error.  Please see Firebird log.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -251, 335544524, 'wal_err_expansion', 'WAL buffers cannot be increased.  Please see Firebird log.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -252, 335544525, 'wal_err_setup', 'WAL setup error.  Please see Firebird log.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -253, 335544526, 'wal_err_ww_sync', 'obsolete');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -254, 335544527, 'wal_err_ww_start', 'Cannot start WAL writer for the database @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544528, 'shutdown', 'database @1 shutdown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -553, 335544529, 'existing_priv_mod', 'cannot modify an existing user privilege');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544530, 'primary_key_ref', 'Cannot delete PRIMARY KEY being used in FOREIGN KEY definition.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -291, 335544531, 'primary_key_notnull', 'Column used in a PRIMARY constraint must be NOT NULL.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544532, 'ref_cnstrnt_notfound', 'Name of Referential Constraint not defined in constraints table.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -660, 335544533, 'foreign_key_notfound', 'Non-existent PRIMARY or UNIQUE KEY specified for FOREIGN KEY.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -292, 335544534, 'ref_cnstrnt_update', 'Cannot update constraints (RDB$REF_CONSTRAINTS).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -293, 335544535, 'check_cnstrnt_update', 'Cannot update constraints (RDB$CHECK_CONSTRAINTS).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -294, 335544536, 'check_cnstrnt_del', 'Cannot delete CHECK constraint entry (RDB$CHECK_CONSTRAINTS)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -618, 335544537, 'integ_index_seg_del', 'Cannot delete index segment used by an Integrity Constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -618, 335544538, 'integ_index_seg_mod', 'Cannot update index segment used by an Integrity Constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544539, 'integ_index_del', 'Cannot delete index used by an Integrity Constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544540, 'integ_index_mod', 'Cannot modify index used by an Integrity Constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544541, 'check_trig_del', 'Cannot delete trigger used by a CHECK Constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -617, 335544542, 'check_trig_update', 'Cannot update trigger used by a CHECK Constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544543, 'cnstrnt_fld_del', 'Cannot delete column being used in an Integrity Constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -617, 335544544, 'cnstrnt_fld_rename', 'Cannot rename column being used in an Integrity Constraint.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -295, 335544545, 'rel_cnstrnt_update', 'Cannot update constraints (RDB$RELATION_CONSTRAINTS).');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -150, 335544546, 'constaint_on_view', 'Cannot define constraints on views');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -296, 335544547, 'invld_cnstrnt_type', 'internal Firebird consistency check (invalid RDB$CONSTRAINT_TYPE)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -831, 335544548, 'primary_key_exists', 'Attempt to define a second PRIMARY KEY for the same table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 335544549, 'systrig_update', 'cannot modify or erase a system trigger');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -552, 335544550, 'not_rel_owner', 'only the owner of a table may reassign ownership');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544551, 'grant_obj_notfound', 'could not find object for GRANT');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -205, 335544552, 'grant_fld_notfound', 'could not find column for GRANT');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -552, 335544553, 'grant_nopriv', 'user does not have GRANT privileges for operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -84, 335544554, 'nonsql_security_rel', 'object has non-SQL security class defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -84, 335544555, 'nonsql_security_fld', 'column has non-SQL security class defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -255, 335544556, 'wal_cache_err', 'Write-ahead Log without shared cache configuration not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544557, 'shutfail', 'database shutdown unsuccessful');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -297, 335544558, 'check_constraint', 'Operation violates CHECK constraint @1 on view or table @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544559, 'bad_svc_handle', 'invalid service handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -838, 335544560, 'shutwarn', 'database @1 shutdown in @2 seconds');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544561, 'wrospbver', 'wrong version of service parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544562, 'bad_spb_form', 'unrecognized service parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544563, 'svcnotdef', 'service @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544564, 'no_jrn', 'long-term journaling not enabled');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -314, 335544565, 'transliteration_failed', 'Cannot transliterate character between character sets');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -257, 335544566, 'start_cm_for_wal', 'WAL defined; Cache Manager must be started first');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -258, 335544567, 'wal_ovflow_log_required', 'Overflow log specification required for round-robin log');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544568, 'text_subtype', 'Implementation of text subtype @1 not located.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544569, 'dsql_error', 'Dynamic SQL Error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544570, 'dsql_command_err', 'Invalid command');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -103, 335544571, 'dsql_constant_err', 'Data type for constant unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -504, 335544572, 'dsql_cursor_err', 'Invalid cursor reference');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544573, 'dsql_datatype_err', 'Data type unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 335544574, 'dsql_decl_err', 'Invalid cursor declaration');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -510, 335544575, 'dsql_cursor_update_err', 'Cursor @1 is not updatable');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 335544576, 'dsql_cursor_open_err', 'Attempt to reopen an open cursor');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -501, 335544577, 'dsql_cursor_close_err', 'Attempt to reclose a closed cursor');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -206, 335544578, 'dsql_field_err', 'Column unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544579, 'dsql_internal_err', 'Internal error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544580, 'dsql_relation_err', 'Table unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544581, 'dsql_procedure_err', 'Procedure unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -518, 335544582, 'dsql_request_err', 'Request unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335544583, 'dsql_sqlda_err', 'SQLDA error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335544584, 'dsql_var_count_err', 'Count of read-write columns does not equal count of values');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -826, 335544585, 'dsql_stmt_handle', 'Invalid statement handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335544586, 'dsql_function_err', 'Function unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -206, 335544587, 'dsql_blob_err', 'Column is not a BLOB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544588, 'collation_not_found', 'COLLATION @1 for CHARACTER SET @2 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544589, 'collation_not_for_charset', 'COLLATION @1 is not valid for specified CHARACTER SET');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544590, 'dsql_dup_option', 'Option specified more than once');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544591, 'dsql_tran_err', 'Unknown transaction option');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544592, 'dsql_invalid_array', 'Invalid array reference');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -604, 335544593, 'dsql_max_arr_dim_exceeded', 'Array declared with too many dimensions');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -604, 335544594, 'dsql_arr_range_error', 'Illegal array dimension range');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544595, 'dsql_trigger_err', 'Trigger unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -206, 335544596, 'dsql_subselect_err', 'Subselect illegal in this context');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -531, 335544597, 'dsql_crdb_prepare_err', 'Cannot prepare a CREATE DATABASE/SCHEMA statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -157, 335544598, 'specify_field_err', 'must specify column name for view select expression');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -158, 335544599, 'num_field_err', 'number of columns does not match select list');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -806, 335544600, 'col_name_err', 'Only simple column names permitted for VIEW WITH CHECK OPTION');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -807, 335544601, 'where_err', 'No WHERE clause for VIEW WITH CHECK OPTION');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -808, 335544602, 'table_view_err', 'Only one table allowed for VIEW WITH CHECK OPTION');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -809, 335544603, 'distinct_err', 'DISTINCT, GROUP or HAVING not permitted for VIEW WITH CHECK OPTION');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -832, 335544604, 'key_field_count_err', 'FOREIGN KEY column count does not match PRIMARY KEY');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -810, 335544605, 'subquery_err', 'No subqueries permitted for VIEW WITH CHECK OPTION');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544606, 'expression_eval_err', 'expression evaluation not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -599, 335544607, 'node_err', 'gen.c: node not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544608, 'command_end_err', 'Unexpected end of command');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544609, 'index_name', 'INDEX @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544610, 'exception_name', 'EXCEPTION @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544611, 'field_name', 'COLUMN @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544612, 'token_err', 'Token unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544613, 'union_err', 'union not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544614, 'dsql_construct_err', 'Unsupported DSQL construct');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -830, 335544615, 'field_aggregate_err', 'column used with aggregate');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 335544616, 'field_ref_err', 'invalid column reference');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -208, 335544617, 'order_by_err', 'invalid ORDER BY clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -171, 335544618, 'return_mode_err', 'Return mode by value not allowed for this data type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -170, 335544619, 'extern_func_err', 'External functions cannot have more than 10 parameters');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544620, 'alias_conflict_err', 'alias @1 conflicts with an alias in the same statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544621, 'procedure_conflict_error', 'alias @1 conflicts with a procedure in the same statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544622, 'relation_conflict_err', 'alias @1 conflicts with a table in the same statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544623, 'dsql_domain_err', 'Illegal use of keyword VALUE');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -663, 335544624, 'idx_seg_err', 'segment count of 0 defined for index @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -599, 335544625, 'node_name_err', 'A node name is not permitted in a secondary, shadow, cache or log file name');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544626, 'table_name', 'TABLE @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544627, 'proc_name', 'PROCEDURE @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -660, 335544628, 'idx_create_err', 'cannot create index @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -259, 335544629, 'wal_shadow_err', 'Write-ahead Log with shadowing configuration not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544630, 'dependency', 'there are @1 dependencies');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -663, 335544631, 'idx_key_err', 'too many keys defined for index @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -597, 335544632, 'dsql_file_length_err', 'Preceding file did not specify length, so @1 must include starting page number');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -598, 335544633, 'dsql_shadow_number_err', 'Shadow number must be a positive integer');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544634, 'dsql_token_unk_err', 'Token unknown - line @1, column @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544635, 'dsql_no_relation_alias', 'there is no alias or table named @1 at this scope level');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544636, 'indexname', 'there is no index @1 for table @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -281, 335544637, 'no_stream_plan', 'table @1 is not referenced in plan');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -282, 335544638, 'stream_twice', 'table @1 is referenced more than once in plan; use aliases to distinguish');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -283, 335544639, 'stream_not_found', 'table @1 is referenced in the plan but not the from list');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544640, 'collation_requires_text', 'Invalid use of CHARACTER SET or COLLATE');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544641, 'dsql_domain_not_found', 'Specified domain or source column @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -284, 335544642, 'index_unused', 'index @1 cannot be used in the specified plan');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -282, 335544643, 'dsql_self_join', 'the table @1 is referenced twice; use aliases to differentiate');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -596, 335544644, 'stream_bof', 'attempt to fetch before the first record in a record stream');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -595, 335544645, 'stream_crack', 'the current position is on a crack');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -601, 335544646, 'db_or_file_exists', 'database or file exists');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -401, 335544647, 'invalid_operator', 'invalid comparison operator for find operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335544648, 'conn_lost', 'Connection lost to pipe server');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -835, 335544649, 'bad_checksum', 'bad checksum');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -689, 335544650, 'page_type_err', 'wrong page type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -816, 335544651, 'ext_readonly_err', 'Cannot insert because the file is readonly or is on a read only medium.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -811, 335544652, 'sing_select_err', 'multiple rows in singleton select');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544653, 'psw_attach', 'cannot attach to password database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544654, 'psw_start_trans', 'cannot start transaction for password database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -827, 335544655, 'invalid_direction', 'invalid direction for find operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544656, 'dsql_var_conflict', 'variable @1 conflicts with parameter in same procedure');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 335544657, 'dsql_no_blob_array', 'Array/BLOB/DATE data types not allowed in arithmetic');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -155, 335544658, 'dsql_base_table', '@1 is not a valid base table of the specified view');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -282, 335544659, 'duplicate_base_table', 'table @1 is referenced twice in view; use an alias to distinguish');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -282, 335544660, 'view_alias', 'view @1 has more than one base table; use aliases to distinguish');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544661, 'index_root_page_full', 'cannot add index, index root page is full.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544662, 'dsql_blob_type_unknown', 'BLOB SUB_TYPE @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -693, 335544663, 'req_max_clones_exceeded', 'Too many concurrent executions of the same request');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -637, 335544664, 'dsql_duplicate_spec', 'duplicate specification of @1 - not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -803, 335544665, 'unique_key_violation', 'violation of PRIMARY or UNIQUE KEY constraint \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544666, 'srvr_version_too_old', 'server version too old to support all CREATE DATABASE options');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -909, 335544667, 'drdb_completed_with_errs', 'drop database completed with errors');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -84, 335544668, 'dsql_procedure_use_err', 'procedure @1 does not return any values');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -313, 335544669, 'dsql_count_mismatch', 'count of column list and variable list do not match');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -685, 335544670, 'blob_idx_err', 'attempt to index BLOB column in index @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -685, 335544671, 'array_idx_err', 'attempt to index array column in index @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -663, 335544672, 'key_field_err', 'too few key columns found for index @1 (incorrect column name?)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544673, 'no_delete', 'cannot delete');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544674, 'del_last_field', 'last column in a table cannot be deleted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544675, 'sort_err', 'sort error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544676, 'sort_mem_err', 'sort error: not enough memory');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -841, 335544677, 'version_err', 'too many versions');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -828, 335544678, 'inval_key_posn', 'invalid key position');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -690, 335544679, 'no_segments_err', 'segments not allowed in expression index @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -600, 335544680, 'crrp_data_err', 'sort error: corruption in data structure');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -691, 335544681, 'rec_size_err', 'new record size of @1 bytes is too big');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -605, 335544682, 'dsql_field_ref', 'Inappropriate self-reference of column');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544683, 'req_depth_exceeded', 'request depth exceeded. (Recursive definition?)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -694, 335544684, 'no_field_access', 'cannot access column @1 in view @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -162, 335544685, 'no_dbkey', 'dbkey not available for multi-table views');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -839, 335544686, 'jrn_format_err', 'journal file wrong format');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -840, 335544687, 'jrn_file_full', 'intermediate journal file full');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -519, 335544688, 'dsql_open_cursor_request', 'The prepare statement identifies a prepare statement with an open cursor');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -999, 335544689, 'ib_error', 'Firebird error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -260, 335544690, 'cache_redef', 'Cache redefined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -239, 335544691, 'cache_too_small', 'Insufficient memory to allocate page buffer cache');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -260, 335544692, 'log_redef', 'Log redefined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -239, 335544693, 'log_too_small', 'Log size too small');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -239, 335544694, 'partition_too_small', 'Log partition size too small');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -261, 335544695, 'partition_not_supp', 'Partitions not supported in series of log file specification');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -261, 335544696, 'log_length_spec', 'Total length of a partitioned log must be specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335544697, 'precision_err', 'Precision must be from 1 to 18');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335544698, 'scale_nogt', 'Scale must be between zero and precision');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335544699, 'expec_short', 'Short integer expected');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335544700, 'expec_long', 'Long integer expected');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335544701, 'expec_ushort', 'Unsigned short integer expected');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -105, 335544702, 'escape_invalid', 'Invalid ESCAPE sequence');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544703, 'svcnoexe', 'service @1 does not have an associated executable');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544704, 'net_lookup_err', 'Failed to locate host machine.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544705, 'service_unknown', 'Undefined service @1/@2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544706, 'host_unknown', 'The specified name was not found in the hosts file or Domain Name Services.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -552, 335544707, 'grant_nopriv_on_base', 'user does not have GRANT privileges on base table/view for operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -203, 335544708, 'dyn_fld_ambiguous', 'Ambiguous column reference.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544709, 'dsql_agg_ref_err', 'Invalid aggregate reference');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -282, 335544710, 'complex_view', 'navigational stream @1 references a view with more than one base table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544711, 'unprepared_stmt', 'Attempt to execute an unprepared dynamic SQL statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335544712, 'expec_positive', 'Positive value expected');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335544713, 'dsql_sqlda_value_err', 'Incorrect values within SQLDA structure');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544714, 'invalid_array_id', 'invalid blob id');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -816, 335544715, 'extfile_uns_op', 'Operation not supported for EXTERNAL FILE table @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544716, 'svc_in_use', 'Service is currently busy: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544717, 'err_stack_limit', 'stack size insufficent to execute current request');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -827, 335544718, 'invalid_key', 'Invalid key for find operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544719, 'net_init_error', 'Error initializing the network software.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544720, 'loadlib_failure', 'Unable to load required library @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544721, 'network_error', 'Unable to complete network request to host \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544722, 'net_connect_err', 'Failed to establish a connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544723, 'net_connect_listen_err', 'Error while listening for an incoming connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544724, 'net_event_connect_err', 'Failed to establish a secondary connection for event processing.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544725, 'net_event_listen_err', 'Error while listening for an incoming event connection request.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544726, 'net_read_err', 'Error reading data from the connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544727, 'net_write_err', 'Error writing data to the connection.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544728, 'integ_index_deactivate', 'Cannot deactivate index used by an integrity constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -616, 335544729, 'integ_deactivate_primary', 'Cannot deactivate index used by a PRIMARY/UNIQUE constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544730, 'cse_not_supported', 'Client/Server Express not supported in this release');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544731, 'tra_must_sweep', '');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544732, 'unsupported_network_drive', 'Access to databases on file servers is not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544733, 'io_create_err', 'Error while trying to create file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544734, 'io_open_err', 'Error while trying to open file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544735, 'io_close_err', 'Error while trying to close file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544736, 'io_read_err', 'Error while trying to read from file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544737, 'io_write_err', 'Error while trying to write to file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544738, 'io_delete_err', 'Error while trying to delete file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544739, 'io_access_err', 'Error while trying to access file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544740, 'udf_exception', 'A fatal exception occurred during the execution of a user defined function.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544741, 'lost_db_connection', 'connection lost to database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544742, 'no_write_user_priv', 'User cannot write to RDB$USER_PRIVILEGES');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544743, 'token_too_long', 'token size exceeds limit');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -906, 335544744, 'max_att_exceeded', 'Maximum user count exceeded.  Contact your database administrator.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544745, 'login_same_as_role_name', 'Your login @1 is same as one of the SQL role name. Ask your database administrator to set up a valid Firebird login.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 335544746, 'reftable_requires_pk', '\');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544747, 'usrname_too_long', 'The username entered is too long.  Maximum length is 31 bytes.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544748, 'password_too_long', 'The password specified is too long.  Maximum length is 8 bytes.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544749, 'usrname_required', 'A username is required for this operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544750, 'password_required', 'A password is required for this operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544751, 'bad_protocol', 'The network protocol specified is invalid');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544752, 'dup_usrname_found', 'A duplicate user name was found in the security database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544753, 'usrname_not_found', 'The user name specified was not found in the security database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544754, 'error_adding_sec_record', 'An error occurred while attempting to add the user.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544755, 'error_modifying_sec_record', 'An error occurred while attempting to modify the user record.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544756, 'error_deleting_sec_record', 'An error occurred while attempting to delete the user record.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -85, 335544757, 'error_updating_sec_db', 'An error occurred while updating the security database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544758, 'sort_rec_size_err', 'sort record size of @1 bytes is too big');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544759, 'bad_default_value', 'can not define a not null column with NULL as default value');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544760, 'invalid_clause', 'invalid clause --- ''@1''');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544761, 'too_many_handles', 'too many open handles to database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544762, 'optimizer_blk_exc', 'size of optimizer block exceeded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544763, 'invalid_string_constant', 'a string constant is delimited by double quotes');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544764, 'transitional_date', 'DATE must be changed to TIMESTAMP');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 335544765, 'read_only_database', 'attempted update on read-only database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 335544766, 'must_be_dialect_2_and_up', 'SQL dialect @1 is not supported in this database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544767, 'blob_filter_exception', 'A fatal exception occurred during the execution of a blob filter.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544768, 'exception_access_violation', 'Access violation.  The code attempted to access a virtual address without privilege to do so.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544769, 'exception_datatype_missalignment', 'Datatype misalignment.  The attempted to read or write a value that was not stored on a memory boundary.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544770, 'exception_array_bounds_exceeded', 'Array bounds exceeded.  The code attempted to access an array element that is out of bounds.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544771, 'exception_float_denormal_operand', 'Float denormal operand.  One of the floating-point operands is too small to represent a standard float value.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544772, 'exception_float_divide_by_zero', 'Floating-point divide by zero.  The code attempted to divide a floating-point value by zero.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544773, 'exception_float_inexact_result', 'Floating-point inexact result.  The result of a floating-point operation cannot be represented as a decimal fraction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544774, 'exception_float_invalid_operand', 'Floating-point invalid operand.  An indeterminant error occurred during a floating-point operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544775, 'exception_float_overflow', 'Floating-point overflow.  The exponent of a floating-point operation is greater than the magnitude allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544776, 'exception_float_stack_check', 'Floating-point stack check.  The stack overflowed or underflowed as the result of a floating-point operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544777, 'exception_float_underflow', 'Floating-point underflow.  The exponent of a floating-point operation is less than the magnitude allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544778, 'exception_integer_divide_by_zero', 'Integer divide by zero.  The code attempted to divide an integer value by an integer divisor of zero.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544779, 'exception_integer_overflow', 'Integer overflow.  The result of an integer operation caused the most significant bit of the result to carry.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544780, 'exception_unknown', 'An exception occurred that does not have a description.  Exception number @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544781, 'exception_stack_overflow', 'Stack overflow.  The resource requirements of the runtime stack have exceeded the memory available to it.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544782, 'exception_sigsegv', 'Segmentation Fault. The code attempted to access memory without privileges.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544783, 'exception_sigill', 'Illegal Instruction. The Code attempted to perform an illegal operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544784, 'exception_sigbus', 'Bus Error. The Code caused a system bus error.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544785, 'exception_sigfpe', 'Floating Point Error. The Code caused an Arithmetic Exception or a floating point exception.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544786, 'ext_file_delete', 'Cannot delete rows from external files.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544787, 'ext_file_modify', 'Cannot update rows in external files.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544788, 'adm_task_denied', 'Unable to perform operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -105, 335544789, 'extract_input_mismatch', 'Specified EXTRACT part does not exist in input datatype');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -551, 335544790, 'insufficient_svc_privileges', 'Service @1 requires SYSDBA permissions.  Reattach to the Service Manager using the SYSDBA account.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544791, 'file_in_use', 'The file @1 is currently in use by another process.  Try again later.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544792, 'service_att_err', 'Cannot attach to services manager');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 335544793, 'ddl_not_allowed_by_db_sql_dial', 'Metadata update statement is not allowed by the current database SQL dialect @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544794, 'cancelled', 'operation was cancelled');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544795, 'unexp_spb_form', 'unexpected item in service parameter block, expected @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544796, 'sql_dialect_datatype_unsupport', 'Client SQL dialect @1 does not support reference to @2 datatype');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544797, 'svcnouser', 'user name and password are required while attaching to the services manager');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544798, 'depend_on_uncommitted_rel', 'You created an indirect dependency on uncommitted metadata. You must roll back the current transaction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544799, 'svc_name_missing', 'The service name was not specified.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544800, 'too_many_contexts', 'Too many Contexts of Relation/Procedure/Views. Maximum allowed is 256');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544801, 'datype_notsup', 'data type not supported for arithmetic');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 501, 335544802, 'dialect_reset_warning', 'Database dialect being changed from 3 to 1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544803, 'dialect_not_changed', 'Database dialect not changed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544804, 'database_create_failed', 'Unable to create database @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544805, 'inv_dialect_specified', 'Database dialect @1 is not a valid dialect.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544806, 'valid_db_dialects', 'Valid database dialects are @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 300, 335544807, 'sqlwarn', 'SQL warning code = @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 301, 335544808, 'dtype_renamed', 'DATE data type is now called TIMESTAMP');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544809, 'extern_func_dir_error', 'Function @1 is in @2, which is not in a permitted directory for external functions.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544810, 'date_range_exceeded', 'value exceeds the range for valid dates');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544811, 'inv_client_dialect_specified', 'passed client dialect @1 is not a valid dialect.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544812, 'valid_client_dialects', 'Valid client dialects are @1.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544813, 'optimizer_between_err', 'Unsupported field type specified in BETWEEN predicate.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544814, 'service_not_supported', 'Services functionality will be supported in a later version  of the product');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 335544815, 'generator_name', 'GENERATOR @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 335544816, 'udf_name', 'Function @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544817, 'bad_limit_param', 'Invalid parameter to FETCH or FIRST. Only integers >= 0 are allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544818, 'bad_skip_param', 'Invalid parameter to OFFSET or SKIP. Only integers >= 0 are allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544819, 'io_32bit_exceeded_err', 'File exceeded maximum size of 2GB.  Add another database file or use a 64 bit I/O version of Firebird.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544820, 'invalid_savepoint', 'Unable to find savepoint with name @1 in transaction context');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544821, 'dsql_column_pos_err', 'Invalid column position used in the @1 clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544822, 'dsql_agg_where_err', 'Cannot use an aggregate or window function in a WHERE clause, use HAVING (for aggregate only) instead');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544823, 'dsql_agg_group_err', 'Cannot use an aggregate or window function in a GROUP BY clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544824, 'dsql_agg_column_err', 'Invalid expression in the @1 (not contained in either an aggregate function or the GROUP BY clause)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544825, 'dsql_agg_having_err', 'Invalid expression in the @1 (neither an aggregate function nor a part of the GROUP BY clause)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544826, 'dsql_agg_nested_err', 'Nested aggregate and window functions are not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544827, 'exec_sql_invalid_arg', 'Invalid argument in EXECUTE STATEMENT - cannot convert to string');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544828, 'exec_sql_invalid_req', 'Wrong request type in EXECUTE STATEMENT ''@1''');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544829, 'exec_sql_invalid_var', 'Variable type (position @1) in EXECUTE STATEMENT ''@2'' INTO does not match returned column type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544830, 'exec_sql_max_call_exceeded', 'Too many recursion levels of EXECUTE STATEMENT');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544831, 'conf_access_denied', 'Use of @1 at location @2 is not allowed by server configuration');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544832, 'wrong_backup_state', 'Cannot change difference file name while database is in backup mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544833, 'wal_backup_err', 'Physical backup is not allowed while Write-Ahead Log is in use');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544834, 'cursor_not_open', 'Cursor is not open');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544835, 'bad_shutdown_mode', 'Target shutdown mode is invalid for database \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 335544836, 'concat_overflow', 'Concatenation overflow. Resulting string cannot exceed 32765 bytes in length.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544837, 'bad_substring_offset', 'Invalid offset parameter @1 to SUBSTRING. Only positive integers are allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -530, 335544838, 'foreign_key_target_doesnt_exist', 'Foreign key reference target does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -530, 335544839, 'foreign_key_references_present', 'Foreign key references are present for the record');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544840, 'no_update', 'cannot update');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544841, 'cursor_already_open', 'Cursor is already open');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544842, 'stack_trace', '@1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544843, 'ctx_var_not_found', 'Context variable @1 is not found in namespace @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544844, 'ctx_namespace_invalid', 'Invalid namespace name @1 passed to @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544845, 'ctx_too_big', 'Too many context variables');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544846, 'ctx_bad_argument', 'Invalid argument passed to @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544847, 'identifier_too_long', 'BLR syntax error. Identifier @1... is too long');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -836, 335544848, 'except2', 'exception @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544849, 'malformed_string', 'Malformed string');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -170, 335544850, 'prc_out_param_mismatch', 'Output parameter mismatch for procedure @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544851, 'command_end_err2', 'Unexpected end of command - line @1, column @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544852, 'partner_idx_incompat_type', 'partner index segment no @1 has incompatible data type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544853, 'bad_substring_length', 'Invalid length parameter @1 to SUBSTRING. Negative integers are not allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544854, 'charset_not_installed', 'CHARACTER SET @1 is not installed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544855, 'collation_not_installed', 'COLLATION @1 for CHARACTER SET @2 is not installed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544856, 'att_shutdown', 'connection shutdown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544857, 'blobtoobig', 'Maximum BLOB size exceeded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 335544858, 'must_have_phys_field', 'Can''t have relation with only computed fields or constraints');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544859, 'invalid_time_precision', 'Time precision exceeds allowed range (0-@1)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -413, 335544860, 'blob_convert_error', 'Unsupported conversion to target type BLOB (subtype @1)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -413, 335544861, 'array_convert_error', 'Unsupported conversion to target type ARRAY');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544862, 'record_lock_not_supp', 'Stream does not support record locking');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544863, 'partner_idx_not_found', 'Cannot create foreign key constraint @1. Partner index does not exist or is inactive.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544864, 'tra_num_exc', 'Transactions count exceeded. Perform backup and restore to make database operable again');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544865, 'field_disappeared', 'Column has been unexpectedly deleted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544866, 'met_wrong_gtt_scope', '@1 cannot depend on @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335544867, 'subtype_for_internal_use', 'Blob sub_types bigger than 1 (text) are for internal use only');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544868, 'illegal_prc_type', 'Procedure @1 is not selectable (it does not contain a SUSPEND statement)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544869, 'invalid_sort_datatype', 'Datatype @1 is not supported for sorting operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544870, 'collation_name', 'COLLATION @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544871, 'domain_name', 'DOMAIN @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -219, 335544872, 'domnotdef', 'domain @1 is not defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -171, 335544873, 'array_max_dimensions', 'Array data type can use up to @1 dimensions');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544874, 'max_db_per_trans_allowed', 'A multi database transaction cannot span more than @1 databases');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 0, 335544875, 'bad_debug_format', 'Bad debug info format');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544876, 'bad_proc_BLR', 'Error while parsing procedure @1''s BLR');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544877, 'key_too_big', 'index key too big');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544878, 'concurrent_transaction', 'concurrent transaction number is @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -625, 335544879, 'not_valid_for_var', 'validation error for variable @1, value \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -625, 335544880, 'not_valid_for', 'validation error for @1, value \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -820, 335544881, 'need_difference', 'Difference file name should be set explicitly for database on raw device');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544882, 'long_login', 'Login name too long (@1 characters, maximum allowed @2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -205, 335544883, 'fldnotdef2', 'column @1 is not defined in procedure @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -105, 335544884, 'invalid_similar_pattern', 'Invalid SIMILAR TO pattern');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544885, 'bad_teb_form', 'Invalid TEB format');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544886, 'tpb_multiple_txn_isolation', 'Found more than one transaction isolation in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544887, 'tpb_reserv_before_table', 'Table reservation lock type @1 requires table name before in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544888, 'tpb_multiple_spec', 'Found more than one @1 specification in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544889, 'tpb_option_without_rc', 'Option @1 requires READ COMMITTED isolation in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544890, 'tpb_conflicting_options', 'Option @1 is not valid if @2 was used previously in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544891, 'tpb_reserv_missing_tlen', 'Table name length missing after table reservation @1 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544892, 'tpb_reserv_long_tlen', 'Table name length @1 is too long after table reservation @2 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544893, 'tpb_reserv_missing_tname', 'Table name length @1 without table name after table reservation @2 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544894, 'tpb_reserv_corrup_tlen', 'Table name length @1 goes beyond the remaining TPB size after table reservation @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544895, 'tpb_reserv_null_tlen', 'Table name length is zero after table reservation @1 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544896, 'tpb_reserv_relnotfound', 'Table or view @1 not defined in system tables after table reservation @2 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544897, 'tpb_reserv_baserelnotfound', 'Base table or view @1 for view @2 not defined in system tables after table reservation @3 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544898, 'tpb_missing_len', 'Option length missing after option @1 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544899, 'tpb_missing_value', 'Option length @1 without value after option @2 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544900, 'tpb_corrupt_len', 'Option length @1 goes beyond the remaining TPB size after option @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544901, 'tpb_null_len', 'Option length is zero after table reservation @1 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544902, 'tpb_overflow_len', 'Option length @1 exceeds the range for option @2 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544903, 'tpb_invalid_value', 'Option value @1 is invalid for the option @2 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544904, 'tpb_reserv_stronger_wng', 'Preserving previous table reservation @1 for table @2, stronger than new @3 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544905, 'tpb_reserv_stronger', 'Table reservation @1 for table @2 already specified and is stronger than new @3 in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544906, 'tpb_reserv_max_recursion', 'Table reservation reached maximum recursion of @1 when expanding views in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544907, 'tpb_reserv_virtualtbl', 'Table reservation in TPB cannot be applied to @1 because it''s a virtual table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544908, 'tpb_reserv_systbl', 'Table reservation in TPB cannot be applied to @1 because it''s a system table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544909, 'tpb_reserv_temptbl', 'Table reservation @1 or @2 in TPB cannot be applied to @3 because it''s a temporary table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544910, 'tpb_readtxn_after_writelock', 'Cannot set the transaction in read only mode after a table reservation isc_tpb_lock_write in TPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544911, 'tpb_writelock_after_readtxn', 'Cannot take a table reservation isc_tpb_lock_write in TPB because the transaction is in read only mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544912, 'time_range_exceeded', 'value exceeds the range for a valid time');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544913, 'datetime_range_exceeded', 'value exceeds the range for valid timestamps');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 335544914, 'string_truncation', 'string right truncation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 335544915, 'blob_truncation', 'blob truncation when converting to a string: length limit exceeded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 335544916, 'numeric_out_of_range', 'numeric value is out of range');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544917, 'shutdown_timeout', 'Firebird shutdown is still in progress after the specified timeout');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544918, 'att_handle_busy', 'Attachment handle is busy');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544919, 'bad_udf_freeit', 'Bad written UDF detected: pointer returned in FREE_IT function was not allocated by ib_util_malloc');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544920, 'eds_provider_not_found', 'External Data Source provider ''@1'' not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544921, 'eds_connection', 'Execute statement error at @1 :\@2Data source : @3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544922, 'eds_preprocess', 'Execute statement preprocess SQL error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544923, 'eds_stmt_expected', 'Statement expected');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544924, 'eds_prm_name_expected', 'Parameter name expected');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544925, 'eds_unclosed_comment', 'Unclosed comment found near ''@1''');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544926, 'eds_statement', 'Execute statement error at @1 :\@2Statement : @3\Data source : @4');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544927, 'eds_input_prm_mismatch', 'Input parameters mismatch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544928, 'eds_output_prm_mismatch', 'Output parameters mismatch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544929, 'eds_input_prm_not_set', 'Input parameter ''@1'' have no value set');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544930, 'too_big_blr', 'BLR stream length @1 exceeds implementation limit @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 0, 335544931, 'montabexh', 'Monitoring table space exhausted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -172, 335544932, 'modnotfound', 'module name or entrypoint could not be found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544933, 'nothing_to_cancel', 'nothing to cancel');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544934, 'ibutil_not_loaded', 'ib_util library has not been loaded to deallocate memory returned by FREE_IT function');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544935, 'circular_computed', 'Cannot have circular dependencies with computed fields');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544936, 'psw_db_error', 'Security database error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544937, 'invalid_type_datetime_op', 'Invalid data type in DATE/TIME/TIMESTAMP addition or subtraction in add_datettime()');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544938, 'onlycan_add_timetodate', 'Only a TIME value can be added to a DATE value');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544939, 'onlycan_add_datetotime', 'Only a DATE value can be added to a TIME value');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544940, 'onlycansub_tstampfromtstamp', 'TIMESTAMP values can be subtracted only from another TIMESTAMP value');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544941, 'onlyoneop_mustbe_tstamp', 'Only one operand can be of type TIMESTAMP');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544942, 'invalid_extractpart_time', 'Only HOUR, MINUTE, SECOND and MILLISECOND can be extracted from TIME values');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544943, 'invalid_extractpart_date', 'HOUR, MINUTE, SECOND and MILLISECOND cannot be extracted from DATE values');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544944, 'invalidarg_extract', 'Invalid argument for EXTRACT() not being of DATE/TIME/TIMESTAMP type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544945, 'sysf_argmustbe_exact', 'Arguments for @1 must be integral types or NUMERIC/DECIMAL without scale');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544946, 'sysf_argmustbe_exact_or_fp', 'First argument for @1 must be integral type or floating point type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544947, 'sysf_argviolates_uuidtype', 'Human readable UUID argument for @1 must be of string type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544948, 'sysf_argviolates_uuidlen', 'Human readable UUID argument for @2 must be of exact length @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544949, 'sysf_argviolates_uuidfmt', 'Human readable UUID argument for @3 must have \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544950, 'sysf_argviolates_guidigits', 'Human readable UUID argument for @3 must have hex digit at position @2 instead of \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544951, 'sysf_invalid_addpart_time', 'Only HOUR, MINUTE, SECOND and MILLISECOND can be added to TIME values in @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544952, 'sysf_invalid_add_datetime', 'Invalid data type in addition of part to DATE/TIME/TIMESTAMP in @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544953, 'sysf_invalid_addpart_dtime', 'Invalid part @1 to be added to a DATE/TIME/TIMESTAMP value in @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544954, 'sysf_invalid_add_dtime_rc', 'Expected DATE/TIME/TIMESTAMP type in evlDateAdd() result');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544955, 'sysf_invalid_diff_dtime', 'Expected DATE/TIME/TIMESTAMP type as first and second argument to @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544956, 'sysf_invalid_timediff', 'The result of TIME-<value> in @1 cannot be expressed in YEAR, MONTH, DAY or WEEK');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544957, 'sysf_invalid_tstamptimediff', 'The result of TIME-TIMESTAMP or TIMESTAMP-TIME in @1 cannot be expressed in HOUR, MINUTE, SECOND or MILLISECOND');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544958, 'sysf_invalid_datetimediff', 'The result of DATE-TIME or TIME-DATE in @1 cannot be expressed in HOUR, MINUTE, SECOND and MILLISECOND');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544959, 'sysf_invalid_diffpart', 'Invalid part @1 to express the difference between two DATE/TIME/TIMESTAMP values in @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544960, 'sysf_argmustbe_positive', 'Argument for @1 must be positive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544961, 'sysf_basemustbe_positive', 'Base for @1 must be positive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544962, 'sysf_argnmustbe_nonneg', 'Argument #@1 for @2 must be zero or positive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544963, 'sysf_argnmustbe_positive', 'Argument #@1 for @2 must be positive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544964, 'sysf_invalid_zeropowneg', 'Base for @1 cannot be zero if exponent is negative');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544965, 'sysf_invalid_negpowfp', 'Base for @1 cannot be negative if exponent is not an integral value');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544966, 'sysf_invalid_scale', 'The numeric scale must be between -128 and 127 in @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544967, 'sysf_argmustbe_nonneg', 'Argument for @1 must be zero or positive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544968, 'sysf_binuuid_mustbe_str', 'Binary UUID argument for @1 must be of string type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544969, 'sysf_binuuid_wrongsize', 'Binary UUID argument for @2 must use @1 bytes');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544970, 'missing_required_spb', 'Missing required item @1 in service parameter block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544971, 'net_server_shutdown', '@1 server is shutdown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335544972, 'bad_conn_str', 'Invalid connection string');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544973, 'bad_epb_form', 'Unrecognized events block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544974, 'no_threads', 'Could not start first worker thread - shutdown server');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544975, 'net_event_connect_timeout', 'Timeout occurred while waiting for a secondary connection for event processing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544976, 'sysf_argmustbe_nonzero', 'Argument for @1 must be different than zero');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544977, 'sysf_argmustbe_range_inc1_1', 'Argument for @1 must be in the range [-1, 1]');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544978, 'sysf_argmustbe_gteq_one', 'Argument for @1 must be greater or equal than one');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544979, 'sysf_argmustbe_range_exc1_1', 'Argument for @1 must be in the range ]-1, 1[');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335544980, 'internal_rejected_params', 'Incorrect parameters provided to internal function @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335544981, 'sysf_fp_overflow', 'Floating point overflow in built-in function @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544982, 'udf_fp_overflow', 'Floating point overflow in result from UDF @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544983, 'udf_fp_nan', 'Invalid floating point value returned by UDF @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544984, 'instance_conflict', 'Database is probably already opened by another engine instance in another Windows session');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544985, 'out_of_temp_space', 'No free space found in temporary directories');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544986, 'eds_expl_tran_ctrl', 'Explicit transaction control is not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335544987, 'no_trusted_spb', 'Use of TRUSTED switches in spb_command_line is prohibited');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544988, 'package_name', 'PACKAGE @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544989, 'cannot_make_not_null', 'Cannot make field @1 of table @2 NOT NULL because there are NULLs present');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544990, 'feature_removed', 'Feature @1 is not supported anymore');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544991, 'view_name', 'VIEW @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335544992, 'lock_dir_access', 'Can not access lock files directory @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544993, 'invalid_fetch_option', 'Fetch option @1 is invalid for a non-scrollable cursor');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544994, 'bad_fun_BLR', 'Error while parsing function @1''s BLR');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544995, 'func_pack_not_implemented', 'Cannot execute function @1 of the unimplemented package @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544996, 'proc_pack_not_implemented', 'Cannot execute procedure @1 of the unimplemented package @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544997, 'eem_func_not_returned', 'External function @1 not returned by the external engine plugin @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544998, 'eem_proc_not_returned', 'External procedure @1 not returned by the external engine plugin @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335544999, 'eem_trig_not_returned', 'External trigger @1 not returned by the external engine plugin @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545000, 'eem_bad_plugin_ver', 'Incompatible plugin version @1 for external engine @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545001, 'eem_engine_notfound', 'External engine @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -532, 335545002, 'attachment_in_use', 'Attachment is in use');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -532, 335545003, 'transaction_in_use', 'Transaction is in use');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545004, 'pman_cannot_load_plugin', 'Error loading plugin @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545005, 'pman_module_notfound', 'Loadable module @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545006, 'pman_entrypoint_notfound', 'Standard plugin entrypoint does not exist in module @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545007, 'pman_module_bad', 'Module @1 exists but can not be loaded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545008, 'pman_plugin_notfound', 'Module @1 does not contain plugin @2 type @3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545009, 'sysf_invalid_trig_namespace', 'Invalid usage of context namespace DDL_TRIGGER');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545010, 'unexpected_null', 'Value is NULL but isNull parameter was not informed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545011, 'type_notcompat_blob', 'Type @1 is incompatible with BLOB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545012, 'invalid_date_val', 'Invalid date');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545013, 'invalid_time_val', 'Invalid time');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545014, 'invalid_timestamp_val', 'Invalid timestamp');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545015, 'invalid_index_val', 'Invalid index @1 in function @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -836, 335545016, 'formatted_exception', '@1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -532, 335545017, 'async_active', 'Asynchronous call is already running for this attachment');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545018, 'private_function', 'Function @1 is private to package @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545019, 'private_procedure', 'Procedure @1 is private to package @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335545020, 'request_outdated', 'Request can''t access new records in relation @1 and should be recompiled');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545021, 'bad_events_handle', 'invalid events id (handle)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545022, 'cannot_copy_stmt', 'Cannot copy statement @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545023, 'invalid_boolean_usage', 'Invalid usage of boolean expression');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545024, 'sysf_argscant_both_be_zero', 'Arguments for @1 cannot both be zero');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545025, 'spb_no_id', 'missing service ID in spb');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545026, 'ee_blr_mismatch_null', 'External BLR message mismatch: invalid null descriptor at field @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545027, 'ee_blr_mismatch_length', 'External BLR message mismatch: length = @1, expected @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -406, 335545028, 'ss_out_of_bounds', 'Subscript @1 out of bounds [@2, @3]');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545029, 'missing_data_structures', 'Install incomplete, please read the Compatibility chapter in the release notes for this version');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545030, 'protect_sys_tab', '@1 operation is not allowed for system table @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545031, 'libtommath_generic', 'Libtommath error code @1 in function @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545032, 'wroblrver2', 'unsupported BLR version (expected between @1 and @2, encountered @3)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -551, 335545033, 'trunc_limits', 'expected length @1, actual @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -551, 335545034, 'info_access', 'Wrong info requested in isc_svc_query() for anonymous service');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545035, 'svc_no_stdin', 'No isc_info_svc_stdin in user request, but service thread requested stdin data');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -551, 335545036, 'svc_start_failed', 'Start request for anonymous service is impossible');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545037, 'svc_no_switches', 'All services except for getting server log require switches');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545038, 'svc_bad_size', 'Size of stdin data is more than was requested from client');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545039, 'no_crypt_plugin', 'Crypt plugin @1 failed to load');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545040, 'cp_name_too_long', 'Length of crypt plugin name should not exceed @1 bytes');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545041, 'cp_process_active', 'Crypt failed - already crypting database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545042, 'cp_already_crypted', 'Crypt failed - database is already in requested state');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545043, 'decrypt_error', 'Missing crypt plugin, but page appears encrypted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545044, 'no_providers', 'No providers loaded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545045, 'null_spb', 'NULL data with non-zero SPB length');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545046, 'max_args_exceeded', 'Maximum (@1) number of arguments exceeded for function @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545047, 'ee_blr_mismatch_names_count', 'External BLR message mismatch: names count = @1, blr count = @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545048, 'ee_blr_mismatch_name_not_found', 'External BLR message mismatch: name @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545049, 'bad_result_set', 'Invalid resultset interface');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335545050, 'wrong_message_length', 'Message length passed from user application does not match set of columns');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335545051, 'no_output_format', 'Resultset is missing output format information');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335545052, 'item_finish', 'Message metadata not ready - item @1 is not finished');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545053, 'miss_config', 'Missing configuration file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545054, 'conf_line', '@1: illegal line <@2>');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545055, 'conf_include', 'Invalid include operator in @1 for <@2>');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545056, 'include_depth', 'Include depth too big');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545057, 'include_miss', 'File to include not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -552, 335545058, 'protect_ownership', 'Only the owner can change the ownership');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545059, 'badvarnum', 'undefined variable number');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545060, 'sec_context', 'Missing security context for @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545061, 'multi_segment', 'Missing segment @1 in multisegment connect block parameter');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545062, 'login_changed', 'Different logins in connect and attach packets - client library error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545063, 'auth_handshake_limit', 'Exceeded exchange limit during authentication handshake');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545064, 'wirecrypt_incompatible', 'Incompatible wire encryption levels requested on client and server');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545065, 'miss_wirecrypt', 'Client attempted to attach unencrypted but wire encryption is required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545066, 'wirecrypt_key', 'Client attempted to start wire encryption using unknown key @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545067, 'wirecrypt_plugin', 'Client attempted to start wire encryption using unsupported plugin @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545068, 'secdb_name', 'Error getting security database name from configuration file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545069, 'auth_data', 'Client authentication plugin is missing required data from server');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545070, 'auth_datalength', 'Client authentication plugin expected @2 bytes of @3 from server, got @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545071, 'info_unprepared_stmt', 'Attempt to get information about an unprepared dynamic SQL statement.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545072, 'idx_key_value', 'Problematic key value is @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545073, 'forupdate_virtualtbl', 'Cannot select virtual table @1 for update WITH LOCK');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545074, 'forupdate_systbl', 'Cannot select system table @1 for update WITH LOCK');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545075, 'forupdate_temptbl', 'Cannot select temporary table @1 for update WITH LOCK');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545076, 'cant_modify_sysobj', 'System @1 @2 cannot be modified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545077, 'server_misconfigured', 'Server misconfigured - contact administrator please');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545078, 'alter_role', 'Deprecated backward compatibility ALTER ROLE ... SET/DROP AUTO ADMIN mapping may be used only for RDB$ADMIN role');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545079, 'map_already_exists', 'Mapping @1 already exists');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545080, 'map_not_exists', 'Mapping @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545081, 'map_load', '@1 failed when loading mapping cache');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545082, 'map_aster', 'Invalid name <*> in authentication block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545083, 'map_multi', 'Multiple maps found for @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545084, 'map_undefined', 'Undefined mapping result - more than one different results found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335545085, 'baddpb_damaged_mode', 'Incompatible mode of attachment to damaged database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335545086, 'baddpb_buffers_range', 'Attempt to set in database number of buffers which is out of acceptable range [@1:@2]');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -924, 335545087, 'baddpb_temp_buffers', 'Attempt to temporarily set number of buffers less than @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545088, 'map_nodb', 'Global mapping is not available when database @1 is not present');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545089, 'map_notable', 'Global mapping is not available when table RDB$MAP is not present in database @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545090, 'miss_trusted_role', 'Your attachment has no trusted role');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545091, 'set_invalid_role', 'Role @1 is invalid or unavailable');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -596, 335545092, 'cursor_not_positioned', 'Cursor @1 is not positioned in a valid record');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545093, 'dup_attribute', 'Duplicated user attribute @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545094, 'dyn_no_priv', 'There is no privilege for this operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545095, 'dsql_cant_grant_option', 'Using GRANT OPTION on @1 not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335545096, 'read_conflict', 'read conflicts with concurrent update');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545097, 'crdb_load', '@1 failed when working with CREATE DATABASE grants');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545098, 'crdb_nodb', 'CREATE DATABASE grants check is not possible when database @1 is not present');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545099, 'crdb_notable', 'CREATE DATABASE grants check is not possible when table RDB$DB_CREATORS is not present in database @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 335545100, 'interface_version_too_old', 'Interface @3 version too old: expected @1, found @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -170, 335545101, 'fun_param_mismatch', 'Input parameter mismatch for function @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545102, 'savepoint_backout_err', 'Error during savepoint backout - transaction invalidated');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -291, 335545103, 'domain_primary_key_notnull', 'Domain used in the PRIMARY KEY constraint of table @1 must be NOT NULL');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 335545104, 'invalid_attachment_charset', 'CHARACTER SET @1 cannot be used as a attachment character set');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545105, 'map_down', 'Some database(s) were shutdown when trying to read mapping data');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545106, 'login_error', 'Error occurred during login, please check server firebird.log for details');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545107, 'already_opened', 'Database already opened with engine instance, incompatible with current');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545108, 'bad_crypt_key', 'Invalid crypt key @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545109, 'encrypt_error', 'Page requires encryption but crypt plugin is missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -904, 335545110, 'max_idx_depth', 'Maximum index depth (@1 levels) is reached');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545111, 'wrong_prvlg', 'System privilege @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545112, 'miss_prvlg', 'System privilege @1 is missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545113, 'crypt_checksum', 'Invalid or missing checksum of encrypted database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545114, 'not_dba', 'You must have SYSDBA rights at this server');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545115, 'no_cursor', 'Cannot open cursor for non-SELECT statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545116, 'dsql_window_incompat_frames', 'If <window frame bound 1> specifies @1, then <window frame bound 2> shall not specify @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545117, 'dsql_window_range_multi_key', 'RANGE based window with <expr> {PRECEDING | FOLLOWING');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545118, 'dsql_window_range_inv_key_type', 'RANGE based window must have an ORDER BY key of numerical, date, time or timestamp types');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545119, 'dsql_window_frame_value_inv_type', 'Window RANGE/ROWS PRECEDING/FOLLOWING value must be of a numerical type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545120, 'window_frame_value_invalid', 'Invalid PRECEDING or FOLLOWING offset in window function: cannot be negative');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545121, 'dsql_window_not_found', 'Window @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545122, 'dsql_window_cant_overr_part', 'Cannot use PARTITION BY clause while overriding the window @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545123, 'dsql_window_cant_overr_order', 'Cannot use ORDER BY clause while overriding the window @1 which already has an ORDER BY clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545124, 'dsql_window_cant_overr_frame', 'Cannot override the window @1 because it has a frame clause. Tip: it can be used without parenthesis in OVER');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545125, 'dsql_window_duplicate', 'Duplicate window definition for @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545126, 'sql_too_long', 'SQL statement is too long. Maximum size is @1 bytes.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545127, 'cfg_stmt_timeout', 'Config level timeout expired.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545128, 'att_stmt_timeout', 'Attachment level timeout expired.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545129, 'req_stmt_timeout', 'Statement level timeout expired.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545130, 'att_shut_killed', 'Killed by database administrator.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545131, 'att_shut_idle', 'Idle timeout expired.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545132, 'att_shut_db_down', 'Database is shutdown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545133, 'att_shut_engine', 'Engine is shutdown.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545134, 'overriding_without_identity', 'OVERRIDING clause can be used only when an identity column is present in the INSERT''s field list for table/view @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545135, 'overriding_system_invalid', 'OVERRIDING SYSTEM VALUE can be used only for identity column defined as ''GENERATED ALWAYS'' in INSERT for table/view @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545136, 'overriding_user_invalid', 'OVERRIDING USER VALUE can be used only for identity column defined as ''GENERATED BY DEFAULT'' in INSERT for table/view @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545137, 'overriding_system_missing', 'OVERRIDING SYSTEM VALUE should be used to override the value of an identity column defined as ''GENERATED ALWAYS'' in table/view @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335545138, 'decprecision_err', 'DecFloat precision must be 16 or 34');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545139, 'decfloat_divide_by_zero', 'Decimal float divide by zero.  The code attempted to divide a DECFLOAT value by zero.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545140, 'decfloat_inexact_result', 'Decimal float inexact result.  The result of an operation cannot be represented as a decimal fraction.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545141, 'decfloat_invalid_operation', 'Decimal float invalid operation.  An indeterminant error occurred during an operation.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545142, 'decfloat_overflow', 'Decimal float overflow.  The exponent of a result is greater than the magnitude allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545143, 'decfloat_underflow', 'Decimal float underflow.  The exponent of a result is less than the magnitude allowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545144, 'subfunc_notdef', 'Sub-function @1 has not been defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545145, 'subproc_notdef', 'Sub-procedure @1 has not been defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545146, 'subfunc_signat', 'Sub-function @1 has a signature mismatch with its forward declaration');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545147, 'subproc_signat', 'Sub-procedure @1 has a signature mismatch with its forward declaration');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545148, 'subfunc_defvaldecl', 'Default values for parameters are not allowed in definition of the previously declared sub-function @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545149, 'subproc_defvaldecl', 'Default values for parameters are not allowed in definition of the previously declared sub-procedure @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545150, 'subfunc_not_impl', 'Sub-function @1 was declared but not implemented');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545151, 'subproc_not_impl', 'Sub-procedure @1 was declared but not implemented');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545152, 'sysf_invalid_hash_algorithm', 'Invalid HASH algorithm @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545153, 'expression_eval_index', 'Expression evaluation error for index \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545154, 'invalid_decfloat_trap', 'Invalid decfloat trap state @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545155, 'invalid_decfloat_round', 'Invalid decfloat rounding mode @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545156, 'sysf_invalid_first_last_part', 'Invalid part @1 to calculate the @1 of a DATE/TIMESTAMP');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 335545157, 'sysf_invalid_date_timestamp', 'Expected DATE/TIMESTAMP value in @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -842, 335545158, 'precision_err2', 'Precision must be from @1 to @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545159, 'bad_batch_handle', 'invalid batch handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545160, 'intl_char', 'Bad international character in tag @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545161, 'null_block', 'Null data in parameters block with non-zero length');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545162, 'mixed_info', 'Items working with running service and getting generic server information should not be mixed in single info block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545163, 'unknown_info', 'Unknown information item, code @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545164, 'bpb_version', 'Wrong version of blob parameters block @1, should be @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545165, 'user_manager', 'User management plugin is missing or failed to load');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545166, 'icu_entrypoint', 'Missing entrypoint @1 in ICU library');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545167, 'icu_library', 'Could not find acceptable ICU library');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545168, 'metadata_name', 'Name @1 not found in system MetadataBuilder');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545169, 'tokens_parse', 'Parse to tokens error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545170, 'iconv_open', 'Error opening international conversion descriptor from @1 to @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545171, 'batch_compl_range', 'Message @1 is out of range, only @2 messages in batch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545172, 'batch_compl_detail', 'Detailed error info for message @1 is missing in batch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545173, 'deflate_init', 'Compression stream init error @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545174, 'inflate_init', 'Decompression stream init error @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545175, 'big_segment', 'Segment size (@1) should not exceed 65535 (64K - 1) when using segmented blob');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545176, 'batch_policy', 'Invalid blob policy in the batch for @1() call');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545177, 'batch_defbpb', 'Can''t change default BPB after adding any data to batch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545178, 'batch_align', 'Unexpected info buffer structure querying for default blob alignment');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545179, 'multi_segment_dup', 'Duplicated segment @1 in multisegment connect block parameter');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545180, 'non_plugin_protocol', 'Plugin not supported by network protocol');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545181, 'message_format', 'Error parsing message format');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545182, 'batch_param_version', 'Wrong version of batch parameters block @1, should be @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545183, 'batch_msg_long', 'Message size (@1) in batch exceeds internal buffer size (@2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545184, 'batch_open', 'Batch already opened for this statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545185, 'batch_type', 'Invalid type of statement used in batch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545186, 'batch_param', 'Statement used in batch must have parameters');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545187, 'batch_blobs', 'There are no blobs in associated with batch statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545188, 'batch_blob_append', 'appendBlobData() is used to append data to last blob but no such blob was added to the batch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545189, 'batch_stream_align', 'Portions of data, passed as blob stream, should have size multiple to the alignment required for blobs');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545190, 'batch_rpt_blob', 'Repeated blob id @1 in registerBlob()');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545191, 'batch_blob_buf', 'Blob buffer format error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545192, 'batch_small_data', 'Unusable (too small) data remained in @1 buffer');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545193, 'batch_cont_bpb', 'Blob continuation should not contain BPB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545194, 'batch_big_bpb', 'Size of BPB (@1) greater than remaining data (@2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545195, 'batch_big_segment', 'Size of segment (@1) greater than current BLOB data (@2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545196, 'batch_big_seg2', 'Size of segment (@1) greater than available data (@2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545197, 'batch_blob_id', 'Unknown blob ID @1 in the batch message');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545198, 'batch_too_big', 'Internal buffer overflow - batch too big');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545199, 'num_literal', 'Numeric literal too long');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545200, 'map_event', 'Error using events in mapping shared memory: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545201, 'map_overflow', 'Global mapping memory overflow');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545202, 'hdr_overflow', 'Header page overflow - too many clumplets on it');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545203, 'vld_plugins', 'No matching client/server authentication plugins configured for execute statement in embedded datasource');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -902, 335545204, 'db_crypt_key', 'Missing database encryption key for your attachment');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 335545205, 'no_keyholder_plugin', 'Key holder plugin @1 failed to load');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545206, 'ses_reset_err', 'Cannot reset user session');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545207, 'ses_reset_open_trans', 'There are open transactions (@1 active)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545208, 'ses_reset_warn', 'Session was reset with warning(s)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545209, 'ses_reset_tran_rollback', 'Transaction is rolled back due to session reset, all changes are lost');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545210, 'plugin_name', 'Plugin @1:');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545211, 'parameter_name', 'PARAMETER @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545212, 'file_starting_page_err', 'Starting page number for file @1 must be @2 or greater');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545213, 'invalid_timezone_offset', 'Invalid time zone offset: @1 - must be between -14:00 and +14:00');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545214, 'invalid_timezone_region', 'Invalid time zone region: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545215, 'invalid_timezone_id', 'Invalid time zone ID: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545216, 'tom_decode64len', 'Wrong base64 text length @1, should be multiple of 4');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545217, 'tom_strblob', 'Invalid first parameter datatype - need string or blob');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545218, 'tom_reg', 'Error registering @1 - probably bad tomcrypt library');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545219, 'tom_algorithm', 'Unknown crypt algorithm @1 in USING clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545220, 'tom_mode_miss', 'Should specify mode parameter for symmetric cipher');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545221, 'tom_mode_bad', 'Unknown symmetric crypt mode specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545222, 'tom_no_mode', 'Mode parameter makes no sense for chosen cipher');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545223, 'tom_iv_miss', 'Should specify initialization vector (IV) for chosen cipher and/or mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545224, 'tom_no_iv', 'Initialization vector (IV) makes no sense for chosen cipher and/or mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545225, 'tom_ctrtype_bad', 'Invalid counter endianess @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545226, 'tom_no_ctrtype', 'Counter endianess parameter is not used in mode @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545227, 'tom_ctr_big', 'Too big counter value @1, maximum @2 can be used');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545228, 'tom_no_ctr', 'Counter length/value parameter is not used with @1 @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545229, 'tom_iv_length', 'Invalid initialization vector (IV) length @1, need @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545230, 'tom_error', 'TomCrypt library error: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545231, 'tom_yarrow_start', 'Starting PRNG yarrow');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545232, 'tom_yarrow_setup', 'Setting up PRNG yarrow');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545233, 'tom_init_mode', 'Initializing @1 mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545234, 'tom_crypt_mode', 'Encrypting in @1 mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545235, 'tom_decrypt_mode', 'Decrypting in @1 mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545236, 'tom_init_cip', 'Initializing cipher @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545237, 'tom_crypt_cip', 'Encrypting using cipher @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545238, 'tom_decrypt_cip', 'Decrypting using cipher @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545239, 'tom_setup_cip', 'Setting initialization vector (IV) for @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545240, 'tom_setup_chacha', 'Invalid initialization vector (IV) length @1, need  8 or 12');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545241, 'tom_encode', 'Encoding @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545242, 'tom_decode', 'Decoding @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545243, 'tom_rsa_import', 'Importing RSA key');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545244, 'tom_oaep', 'Invalid OAEP packet');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545245, 'tom_hash_bad', 'Unknown hash algorithm @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545246, 'tom_rsa_make', 'Making RSA key');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545247, 'tom_rsa_export', 'Exporting @1 RSA key');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545248, 'tom_rsa_sign', 'RSA-signing data');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545249, 'tom_rsa_verify', 'Verifying RSA-signed data');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545250, 'tom_chacha_key', 'Invalid key length @1, need 16 or 32');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545251, 'bad_repl_handle', 'invalid replicator handle');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545252, 'tra_snapshot_does_not_exist', 'Transaction''s base snapshot number does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545253, 'eds_input_prm_not_used', 'Input parameter ''@1'' is not used in SQL query text');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -551, 335545254, 'effective_user', 'Effective user is @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545255, 'invalid_time_zone_bind', 'Invalid time zone bind mode @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545256, 'invalid_decfloat_bind', 'Invalid decfloat bind mode @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545257, 'odd_hex_len', 'Invalid hex text length @1, should be multiple of 2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335545258, 'invalid_hex_digit', 'Invalid hex digit @1 at position @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740929, 'gfix_db_name', 'data base file name (@1) already given');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740930, 'gfix_invalid_sw', 'invalid switch @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740932, 'gfix_incmp_sw', 'incompatible switch combination');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740933, 'gfix_replay_req', 'replay log pathname required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740934, 'gfix_pgbuf_req', 'number of page buffers for cache required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740935, 'gfix_val_req', 'numeric value required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740936, 'gfix_pval_req', 'positive numeric value required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740937, 'gfix_trn_req', 'number of transactions per sweep required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740940, 'gfix_full_req', '\');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740941, 'gfix_usrname_req', 'user name required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740942, 'gfix_pass_req', 'password required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740943, 'gfix_subs_name', 'subsystem name');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740944, 'gfix_wal_req', '\');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740945, 'gfix_sec_req', 'number of seconds required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740946, 'gfix_nval_req', 'numeric value between 0 and 32767 inclusive required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740947, 'gfix_type_shut', 'must specify type of shutdown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740948, 'gfix_retry', 'please retry, specifying an option');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740951, 'gfix_retry_db', 'please retry, giving a database name');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740991, 'gfix_exceed_max', 'internal block exceeds maximum size');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740992, 'gfix_corrupt_pool', 'corrupt pool');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740993, 'gfix_mem_exhausted', 'virtual memory exhausted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740994, 'gfix_bad_pool', 'bad pool id');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335740995, 'gfix_trn_not_valid', 'Transaction state @1 not in valid range.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335741012, 'gfix_unexp_eoi', 'unexpected end of input');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335741018, 'gfix_recon_fail', 'failed to reconnect to a transaction in database @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335741036, 'gfix_trn_unknown', 'Transaction description item unknown');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335741038, 'gfix_mode_req', '\');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 335741042, 'gfix_pzval_req', 'positive or zero numeric value required');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336003074, 'dsql_dbkey_from_non_table', 'Cannot SELECT RDB$DB_KEY from a stored procedure.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336003075, 'dsql_transitional_numeric', 'Precision 10 to 18 changed from DOUBLE PRECISION in SQL dialect 1 to 64-bit scaled integer in SQL dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 301, 336003076, 'dsql_dialect_warning_expr', 'Use of @1 expression that returns different results in dialect 1 and dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336003077, 'sql_db_dialect_dtype_unsupport', 'Database SQL dialect @1 does not support reference to @2 datatype');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 336003079, 'sql_dialect_conflict_num', 'DB dialect @1 and client dialect @2 conflict with respect to numeric precision @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 301, 336003080, 'dsql_warning_number_ambiguous', 'WARNING: Numeric literal @1 is interpreted as a floating-point');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 301, 336003081, 'dsql_warning_number_ambiguous1', 'value in SQL dialect 1, but as an exact numeric value in SQL dialect 3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 301, 336003082, 'dsql_warn_precision_ambiguous', 'WARNING: NUMERIC and DECIMAL fields with precision 10 or greater are stored');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 301, 336003083, 'dsql_warn_precision_ambiguous1', 'as approximate floating-point values in SQL dialect 1, but as 64-bit');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 301, 336003084, 'dsql_warn_precision_ambiguous2', 'integers in SQL dialect 3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -204, 336003085, 'dsql_ambiguous_field_name', 'Ambiguous field name between @1 and @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336003086, 'dsql_udf_return_pos_err', 'External function should have return position between 1 and @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336003087, 'dsql_invalid_label', 'Label @1 @2 in the current scope');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336003088, 'dsql_datatypes_not_comparable', 'Datatypes @1are not comparable in expression @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -504, 336003089, 'dsql_cursor_invalid', 'Empty cursor name is not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 336003090, 'dsql_cursor_redefined', 'Statement already has a cursor @1 assigned');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 336003091, 'dsql_cursor_not_found', 'Cursor @1 is not found in the current context');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 336003092, 'dsql_cursor_exists', 'Cursor @1 already exists in the current context');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 336003093, 'dsql_cursor_rel_ambiguous', 'Relation @1 is ambiguous in cursor @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 336003094, 'dsql_cursor_rel_not_found', 'Relation @1 is not found in cursor @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -502, 336003095, 'dsql_cursor_not_open', 'Cursor is not open');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336003096, 'dsql_type_not_supp_ext_tab', 'Data type @1 is not supported for EXTERNAL TABLES. Relation ''@2'', field ''@3''');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 336003097, 'dsql_feature_not_supported_ods', 'Feature not supported on ODS version older than @1.@2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -660, 336003098, 'primary_key_required', 'Primary key required on table @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -313, 336003099, 'upd_ins_doesnt_match_pk', 'UPDATE OR INSERT field list does not match primary key of table @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -313, 336003100, 'upd_ins_doesnt_match_matching', 'UPDATE OR INSERT field list does not match MATCHING clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 336003101, 'upd_ins_with_complex_view', 'UPDATE OR INSERT without MATCHING could not be used with views based on more than one table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 336003102, 'dsql_incompatible_trigger_type', 'Incompatible trigger type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 336003103, 'dsql_db_trigger_type_cant_change', 'Database trigger type can''t be changed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336003104, 'dsql_record_version_table', 'To be used with RDB$RECORD_VERSION, @1 must be a table or a view of single table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 336003105, 'dsql_invalid_sqlda_version', 'SQLDA version expected between @1 and @2, found @3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 336003106, 'dsql_sqlvar_index', 'at SQLVAR index @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 336003107, 'dsql_no_sqlind', 'empty pointer to NULL indicator variable');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 336003108, 'dsql_no_sqldata', 'empty pointer to data');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 336003109, 'dsql_no_input_sqlda', 'No SQLDA for input values provided');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -802, 336003110, 'dsql_no_output_sqlda', 'No SQLDA for output values provided');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -313, 336003111, 'dsql_wrong_param_num', 'Wrong number of parameters (expected @1, got @2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -817, 336003112, 'dsql_invalid_drop_ss_clause', 'Invalid DROP SQL SECURITY clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -313, 336003113, 'upd_ins_cannot_default', 'UPDATE OR INSERT value for field @1, part of the implicit or explicit MATCHING clause, cannot be DEFAULT');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068645, 'dyn_filter_not_found', 'BLOB Filter @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068649, 'dyn_func_not_found', 'Function @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068656, 'dyn_index_not_found', 'Index not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068662, 'dyn_view_not_found', 'View @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068697, 'dyn_domain_not_found', 'Domain not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068717, 'dyn_cant_modify_auto_trig', 'Triggers created automatically cannot be modified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068740, 'dyn_dup_table', 'Table @1 already exists');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068748, 'dyn_proc_not_found', 'Procedure @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068752, 'dyn_exception_not_found', 'Exception not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068754, 'dyn_proc_param_not_found', 'Parameter @1 in procedure @2 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068755, 'dyn_trig_not_found', 'Trigger @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068759, 'dyn_charset_not_found', 'Character set @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068760, 'dyn_collation_not_found', 'Collation @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068763, 'dyn_role_not_found', 'Role @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068767, 'dyn_name_longer', 'Name longer than database column size');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068784, 'dyn_column_does_not_exist', 'column @1 does not exist in table/view @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068796, 'dyn_role_does_not_exist', 'SQL role @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068797, 'dyn_no_grant_admin_opt', 'user @1 has no grant admin option on SQL role @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068798, 'dyn_user_not_role_member', 'user @1 is not a member of SQL role @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068799, 'dyn_delete_role_failed', '@1 is not the owner of SQL role @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068800, 'dyn_grant_role_to_user', '@1 is a SQL role and not a user');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068801, 'dyn_inv_sql_role_name', 'user name @1 could not be used for SQL role');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068802, 'dyn_dup_sql_role', 'SQL role @1 already exists');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068803, 'dyn_kywd_spec_for_role', 'keyword @1 can not be used as a SQL role name');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068804, 'dyn_roles_not_supported', 'SQL roles are not supported in on older versions of the database.  A backup and restore of the database is required.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -612, 336068812, 'dyn_domain_name_exists', 'Cannot rename domain @1 to @2.  A domain with that name already exists.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -612, 336068813, 'dyn_field_name_exists', 'Cannot rename column @1 to @2.  A column with that name already exists in table @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -383, 336068814, 'dyn_dependency_exists', 'Column @1 from table @2 is referenced in @3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -315, 336068815, 'dyn_dtype_invalid', 'Cannot change datatype for column @1.  Changing datatype is not supported for BLOB or ARRAY columns.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068816, 'dyn_char_fld_too_small', 'New size specified for column @1 must be at least @2 characters.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068817, 'dyn_invalid_dtype_conversion', 'Cannot change datatype for @1.  Conversion from base type @2 to @3 is not supported.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068818, 'dyn_dtype_conv_invalid', 'Cannot change datatype for column @1 from a character type to a non-character type.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068820, 'dyn_zero_len_id', 'Zero length identifiers are not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068822, 'dyn_gen_not_found', 'Sequence @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068829, 'max_coll_per_charset', 'Maximum number of collations per character set exceeded');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068830, 'invalid_coll_attr', 'Invalid collation attributes');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068840, 'dyn_wrong_gtt_scope', '@1 cannot reference @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068843, 'dyn_coll_used_table', 'Collation @1 is used in table @2 (field name @3) and cannot be dropped');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068844, 'dyn_coll_used_domain', 'Collation @1 is used in domain @2 and cannot be dropped');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336068845, 'dyn_cannot_del_syscoll', 'Cannot delete system collation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068846, 'dyn_cannot_del_def_coll', 'Cannot delete default collation of CHARACTER SET @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068849, 'dyn_table_not_found', 'Table @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068851, 'dyn_coll_used_procedure', 'Collation @1 is used in procedure @2 (parameter name @3) and cannot be dropped');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068852, 'dyn_scale_too_big', 'New scale specified for column @1 must be at most @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068853, 'dyn_precision_too_small', 'New precision specified for column @1 must be at least @2.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( 106, 336068855, 'dyn_miss_priv_warning', 'Warning: @1 on @2 is not granted to @3.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068856, 'dyn_ods_not_supp_feature', 'Feature ''@1'' is not supported in ODS @2.@3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -829, 336068857, 'dyn_cannot_addrem_computed', 'Cannot add or remove COMPUTED from column @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068858, 'dyn_no_empty_pw', 'Password should not be empty string');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068859, 'dyn_dup_index', 'Index @1 already exists');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068864, 'dyn_package_not_found', 'Package @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068865, 'dyn_schema_not_found', 'Schema @1 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336068866, 'dyn_cannot_mod_sysproc', 'Cannot ALTER or DROP system procedure @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336068867, 'dyn_cannot_mod_systrig', 'Cannot ALTER or DROP system trigger @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336068868, 'dyn_cannot_mod_sysfunc', 'Cannot ALTER or DROP system function @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336068869, 'dyn_invalid_ddl_proc', 'Invalid DDL statement for procedure @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336068870, 'dyn_invalid_ddl_trig', 'Invalid DDL statement for trigger @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068871, 'dyn_funcnotdef_package', 'Function @1 has not been defined on the package body @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068872, 'dyn_procnotdef_package', 'Procedure @1 has not been defined on the package body @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068873, 'dyn_funcsignat_package', 'Function @1 has a signature mismatch on package body @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068874, 'dyn_procsignat_package', 'Procedure @1 has a signature mismatch on package body @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068875, 'dyn_defvaldecl_package_proc', 'Default values for parameters are not allowed in the definition of a previously declared packaged procedure @1.@2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068877, 'dyn_package_body_exists', 'Package body @1 already exists');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336068878, 'dyn_invalid_ddl_func', 'Invalid DDL statement for function @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068879, 'dyn_newfc_oldsyntax', 'Cannot alter new style function @1 with ALTER EXTERNAL FUNCTION. Use ALTER FUNCTION instead.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068886, 'dyn_func_param_not_found', 'Parameter @1 in function @2 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068887, 'dyn_routine_param_not_found', 'Parameter @1 of routine @2 not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068888, 'dyn_routine_param_ambiguous', 'Parameter @1 of routine @2 is ambiguous (found in both procedures and functions). Use a specifier keyword.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068889, 'dyn_coll_used_function', 'Collation @1 is used in function @2 (parameter name @3) and cannot be dropped');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068890, 'dyn_domain_used_function', 'Domain @1 is used in function @2 (parameter name @3) and cannot be dropped');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068891, 'dyn_alter_user_no_clause', 'ALTER USER requires at least one clause to be specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068894, 'dyn_duplicate_package_item', 'Duplicate @1 @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068895, 'dyn_cant_modify_sysobj', 'System @1 @2 cannot be modified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068896, 'dyn_cant_use_zero_increment', 'INCREMENT BY 0 is an illegal option for sequence @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068897, 'dyn_cant_use_in_foreignkey', 'Can''t use @1 in FOREIGN KEY constraint');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068898, 'dyn_defvaldecl_package_func', 'Default values for parameters are not allowed in the definition of a previously declared packaged function @1.@2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068900, 'dyn_cyclic_role', 'role @1 can not be granted to role @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068904, 'dyn_cant_use_zero_inc_ident', 'INCREMENT BY 0 is an illegal option for identity column @1 of table @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068907, 'dyn_no_ddl_grant_opt_priv', 'no @1 privilege with grant option on DDL @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068908, 'dyn_no_grant_opt_priv', 'no @1 privilege with grant option on object @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068909, 'dyn_func_not_exist', 'Function @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068910, 'dyn_proc_not_exist', 'Procedure @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068911, 'dyn_pack_not_exist', 'Package @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068912, 'dyn_trig_not_exist', 'Trigger @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068913, 'dyn_view_not_exist', 'View @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068914, 'dyn_rel_not_exist', 'Table @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068915, 'dyn_exc_not_exist', 'Exception @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068916, 'dyn_gen_not_exist', 'Generator/Sequence @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336068917, 'dyn_fld_not_exist', 'Field @1 of table @2 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330753, 'gbak_unknown_switch', 'found unknown switch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330754, 'gbak_page_size_missing', 'page size parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330755, 'gbak_page_size_toobig', 'Page size specified (@1) greater than limit (32768 bytes)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330756, 'gbak_redir_ouput_missing', 'redirect location for output is not specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330757, 'gbak_switches_conflict', 'conflicting switches for backup/restore');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330758, 'gbak_unknown_device', 'device type @1 not known');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330759, 'gbak_no_protection', 'protection is not there yet');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330760, 'gbak_page_size_not_allowed', 'page size is allowed only on restore or create');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330761, 'gbak_multi_source_dest', 'multiple sources or destinations specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330762, 'gbak_filename_missing', 'requires both input and output filenames');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330763, 'gbak_dup_inout_names', 'input and output have the same name.  Disallowed.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330764, 'gbak_inv_page_size', 'expected page size, encountered \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330765, 'gbak_db_specified', 'REPLACE specified, but the first file @1 is a database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330766, 'gbak_db_exists', 'database @1 already exists.  To replace it, use the -REP switch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330767, 'gbak_unk_device', 'device type not specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330772, 'gbak_blob_info_failed', 'gds_$blob_info failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330773, 'gbak_unk_blob_item', 'do not understand BLOB INFO item @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330774, 'gbak_get_seg_failed', 'gds_$get_segment failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330775, 'gbak_close_blob_failed', 'gds_$close_blob failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330776, 'gbak_open_blob_failed', 'gds_$open_blob failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330777, 'gbak_put_blr_gen_id_failed', 'Failed in put_blr_gen_id');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330778, 'gbak_unk_type', 'data type @1 not understood');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330779, 'gbak_comp_req_failed', 'gds_$compile_request failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330780, 'gbak_start_req_failed', 'gds_$start_request failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330781, 'gbak_rec_failed', 'gds_$receive failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330782, 'gbak_rel_req_failed', 'gds_$release_request failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330783, 'gbak_db_info_failed', 'gds_$database_info failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330784, 'gbak_no_db_desc', 'Expected database description record');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330785, 'gbak_db_create_failed', 'failed to create database @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330786, 'gbak_decomp_len_error', 'RESTORE: decompression length error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330787, 'gbak_tbl_missing', 'cannot find table @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330788, 'gbak_blob_col_missing', 'Cannot find column for BLOB');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330789, 'gbak_create_blob_failed', 'gds_$create_blob failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330790, 'gbak_put_seg_failed', 'gds_$put_segment failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330791, 'gbak_rec_len_exp', 'expected record length');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330792, 'gbak_inv_rec_len', 'wrong length record, expected @1 encountered @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330793, 'gbak_exp_data_type', 'expected data attribute');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330794, 'gbak_gen_id_failed', 'Failed in store_blr_gen_id');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330795, 'gbak_unk_rec_type', 'do not recognize record type @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330796, 'gbak_inv_bkup_ver', 'Expected backup version 1..10.  Found @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330797, 'gbak_missing_bkup_desc', 'expected backup description record');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330798, 'gbak_string_trunc', 'string truncated');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330799, 'gbak_cant_rest_record', 'warning -- record could not be restored');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330800, 'gbak_send_failed', 'gds_$send failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330801, 'gbak_no_tbl_name', 'no table name for data');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330802, 'gbak_unexp_eof', 'unexpected end of file on backup file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330803, 'gbak_db_format_too_old', 'database format @1 is too old to restore to');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330804, 'gbak_inv_array_dim', 'array dimension for column @1 is invalid');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330807, 'gbak_xdr_len_expected', 'Expected XDR record length');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330817, 'gbak_open_bkup_error', 'cannot open backup file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330818, 'gbak_open_error', 'cannot open status and error output file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330934, 'gbak_missing_block_fac', 'blocking factor parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330935, 'gbak_inv_block_fac', 'expected blocking factor, encountered \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330936, 'gbak_block_fac_specified', 'a blocking factor may not be used in conjunction with device CT');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330940, 'gbak_missing_username', 'user name parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330941, 'gbak_missing_password', 'password parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330952, 'gbak_missing_skipped_bytes', ' missing parameter for the number of bytes to be skipped');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330953, 'gbak_inv_skipped_bytes', 'expected number of bytes to be skipped, encountered \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330965, 'gbak_err_restore_charset', 'character set');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330967, 'gbak_err_restore_collation', 'collation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330972, 'gbak_read_error', 'Unexpected I/O error while reading from backup file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330973, 'gbak_write_error', 'Unexpected I/O error while writing to backup file');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330985, 'gbak_db_in_use', 'could not drop database @1 (no privilege or database might be in use)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336330990, 'gbak_sysmemex', 'System memory exhausted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331002, 'gbak_restore_role_failed', 'SQL role');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331005, 'gbak_role_op_missing', 'SQL role parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331010, 'gbak_page_buffers_missing', 'page buffers parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331011, 'gbak_page_buffers_wrong_param', 'expected page buffers, encountered \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331012, 'gbak_page_buffers_restore', 'page buffers is allowed only on restore or create');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331014, 'gbak_inv_size', 'size specification either missing or incorrect for file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331015, 'gbak_file_outof_sequence', 'file @1 out of sequence');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331016, 'gbak_join_file_missing', 'can''t join -- one of the files missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331017, 'gbak_stdin_not_supptd', ' standard input is not supported when using join operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331018, 'gbak_stdout_not_supptd', 'standard output is not supported when using split operation or in verbose mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331019, 'gbak_bkup_corrupt', 'backup file @1 might be corrupt');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331020, 'gbak_unk_db_file_spec', 'database file specification missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331021, 'gbak_hdr_write_failed', 'can''t write a header record to file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331022, 'gbak_disk_space_ex', 'free disk space exhausted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331023, 'gbak_size_lt_min', 'file size given (@1) is less than minimum allowed (@2)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331025, 'gbak_svc_name_missing', 'service name parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331026, 'gbak_not_ownr', 'Cannot restore over current database, must be SYSDBA or owner of the existing database.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331031, 'gbak_mode_req', '\');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331033, 'gbak_just_data', 'just data ignore all constraints etc.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331034, 'gbak_data_only', 'restoring data only ignoring foreign key, unique, not null & other constraints');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331078, 'gbak_missing_interval', 'verbose interval value parameter missing');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331079, 'gbak_wrong_interval', 'verbose interval value cannot be smaller than @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331081, 'gbak_verify_verbint', 'verify (verbose) and verbint options are mutually exclusive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331082, 'gbak_option_only_restore', 'option -@1 is allowed only on restore or create');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331083, 'gbak_option_only_backup', 'option -@1 is allowed only on backup');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331084, 'gbak_option_conflict', 'options -@1 and -@2 are mutually exclusive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331085, 'gbak_param_conflict', 'parameter for option -@1 was already specified with value \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331086, 'gbak_option_repeated', 'option -@1 was already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331091, 'gbak_max_dbkey_recursion', 'dependency depth greater than @1 for view @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331092, 'gbak_max_dbkey_length', 'value greater than @1 when calculating length of rdb$db_key for view @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331093, 'gbak_invalid_metadata', 'Invalid metadata detected. Use -FIX_FSS_METADATA option.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331094, 'gbak_invalid_data', 'Invalid data detected. Use -FIX_FSS_DATA option.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331096, 'gbak_inv_bkup_ver2', 'Expected backup version @2..@3.  Found @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336331100, 'gbak_db_format_too_old2', 'database format @1 is too old to backup');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -804, 336397205, 'dsql_too_old_ods', 'ODS versions before ODS@1 are not supported');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336397206, 'dsql_table_not_found', 'Table @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336397207, 'dsql_view_not_found', 'View @1 does not exist');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -206, 336397208, 'dsql_line_col_error', 'At line @1, column @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -206, 336397209, 'dsql_unknown_pos', 'At unknown line and column');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -206, 336397210, 'dsql_no_dup_name', 'Column @1 cannot be repeated in @2 statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397211, 'dsql_too_many_values', 'Too many values (more than @1) in member list to match against');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336397212, 'dsql_no_array_computed', 'Array and BLOB data types not allowed in computed field');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -637, 336397213, 'dsql_implicit_domain_name', 'Implicit domain name @1 not allowed in user created domain');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -607, 336397214, 'dsql_only_can_subscript_array', 'scalar operator used on field @1 which is not an array');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397215, 'dsql_max_sort_items', 'cannot sort on more than 255 items');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397216, 'dsql_max_group_items', 'cannot group on more than 255 items');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397217, 'dsql_conflicting_sort_field', 'Cannot include the same field (@1.@2) twice in the ORDER BY clause with conflicting sorting options');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397218, 'dsql_derived_table_more_columns', 'column list from derived table @1 has more columns than the number of items in its SELECT statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397219, 'dsql_derived_table_less_columns', 'column list from derived table @1 has less columns than the number of items in its SELECT statement');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397220, 'dsql_derived_field_unnamed', 'no column name specified for column number @1 in derived table @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397221, 'dsql_derived_field_dup_name', 'column @1 was specified multiple times for derived table @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397222, 'dsql_derived_alias_select', 'Internal dsql error: alias type expected by pass1_expand_select_node');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397223, 'dsql_derived_alias_field', 'Internal dsql error: alias type expected by pass1_field');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397224, 'dsql_auto_field_bad_pos', 'Internal dsql error: column position out of range in pass1_union_auto_cast');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397225, 'dsql_cte_wrong_reference', 'Recursive CTE member (@1) can refer itself only in FROM clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397226, 'dsql_cte_cycle', 'CTE ''@1'' has cyclic dependencies');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397227, 'dsql_cte_outer_join', 'Recursive member of CTE can''t be member of an outer join');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397228, 'dsql_cte_mult_references', 'Recursive member of CTE can''t reference itself more than once');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397229, 'dsql_cte_not_a_union', 'Recursive CTE (@1) must be an UNION');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397230, 'dsql_cte_nonrecurs_after_recurs', 'CTE ''@1'' defined non-recursive member after recursive');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397231, 'dsql_cte_wrong_clause', 'Recursive member of CTE ''@1'' has @2 clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397232, 'dsql_cte_union_all', 'Recursive members of CTE (@1) must be linked with another members via UNION ALL');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397233, 'dsql_cte_miss_nonrecursive', 'Non-recursive member is missing in CTE ''@1''');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397234, 'dsql_cte_nested_with', 'WITH clause can''t be nested');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397235, 'dsql_col_more_than_once_using', 'column @1 appears more than once in USING clause');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397236, 'dsql_unsupp_feature_dialect', 'feature is not supported in dialect @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397237, 'dsql_cte_not_used', 'CTE \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397238, 'dsql_col_more_than_once_view', 'column @1 appears more than once in ALTER VIEW');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397239, 'dsql_unsupported_in_auto_trans', '@1 is not supported inside IN AUTONOMOUS TRANSACTION block');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397240, 'dsql_eval_unknode', 'Unknown node type @1 in dsql/GEN_expr');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397241, 'dsql_agg_wrongarg', 'Argument for @1 in dialect 1 must be string or numeric');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397242, 'dsql_agg2_wrongarg', 'Argument for @1 in dialect 3 must be numeric');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397243, 'dsql_nodateortime_pm_string', 'Strings cannot be added to or subtracted from DATE or TIME types');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397244, 'dsql_invalid_datetime_subtract', 'Invalid data type for subtraction involving DATE, TIME or TIMESTAMP types');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397245, 'dsql_invalid_dateortime_add', 'Adding two DATE values or two TIME values is not allowed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397246, 'dsql_invalid_type_minus_date', 'DATE value cannot be subtracted from the provided data type');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397247, 'dsql_nostring_addsub_dial3', 'Strings cannot be added or subtracted in dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397248, 'dsql_invalid_type_addsub_dial3', 'Invalid data type for addition or subtraction in dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397249, 'dsql_invalid_type_multip_dial1', 'Invalid data type for multiplication in dialect 1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397250, 'dsql_nostring_multip_dial3', 'Strings cannot be multiplied in dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397251, 'dsql_invalid_type_multip_dial3', 'Invalid data type for multiplication in dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397252, 'dsql_mustuse_numeric_div_dial1', 'Division in dialect 1 must be between numeric data types');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397253, 'dsql_nostring_div_dial3', 'Strings cannot be divided in dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397254, 'dsql_invalid_type_div_dial3', 'Invalid data type for division in dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397255, 'dsql_nostring_neg_dial3', 'Strings cannot be negated (applied the minus operator) in dialect 3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -833, 336397256, 'dsql_invalid_type_neg', 'Invalid data type for negation (minus operator)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397257, 'dsql_max_distinct_items', 'Cannot have more than 255 items in DISTINCT list');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397258, 'dsql_alter_charset_failed', 'ALTER CHARACTER SET @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397259, 'dsql_comment_on_failed', 'COMMENT ON @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397260, 'dsql_create_func_failed', 'CREATE FUNCTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397261, 'dsql_alter_func_failed', 'ALTER FUNCTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397262, 'dsql_create_alter_func_failed', 'CREATE OR ALTER FUNCTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397263, 'dsql_drop_func_failed', 'DROP FUNCTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397264, 'dsql_recreate_func_failed', 'RECREATE FUNCTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397265, 'dsql_create_proc_failed', 'CREATE PROCEDURE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397266, 'dsql_alter_proc_failed', 'ALTER PROCEDURE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397267, 'dsql_create_alter_proc_failed', 'CREATE OR ALTER PROCEDURE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397268, 'dsql_drop_proc_failed', 'DROP PROCEDURE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397269, 'dsql_recreate_proc_failed', 'RECREATE PROCEDURE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397270, 'dsql_create_trigger_failed', 'CREATE TRIGGER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397271, 'dsql_alter_trigger_failed', 'ALTER TRIGGER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397272, 'dsql_create_alter_trigger_failed', 'CREATE OR ALTER TRIGGER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397273, 'dsql_drop_trigger_failed', 'DROP TRIGGER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397274, 'dsql_recreate_trigger_failed', 'RECREATE TRIGGER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397275, 'dsql_create_collation_failed', 'CREATE COLLATION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397276, 'dsql_drop_collation_failed', 'DROP COLLATION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397277, 'dsql_create_domain_failed', 'CREATE DOMAIN @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397278, 'dsql_alter_domain_failed', 'ALTER DOMAIN @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397279, 'dsql_drop_domain_failed', 'DROP DOMAIN @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397280, 'dsql_create_except_failed', 'CREATE EXCEPTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397281, 'dsql_alter_except_failed', 'ALTER EXCEPTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397282, 'dsql_create_alter_except_failed', 'CREATE OR ALTER EXCEPTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397283, 'dsql_recreate_except_failed', 'RECREATE EXCEPTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397284, 'dsql_drop_except_failed', 'DROP EXCEPTION @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397285, 'dsql_create_sequence_failed', 'CREATE SEQUENCE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397286, 'dsql_create_table_failed', 'CREATE TABLE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397287, 'dsql_alter_table_failed', 'ALTER TABLE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397288, 'dsql_drop_table_failed', 'DROP TABLE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397289, 'dsql_recreate_table_failed', 'RECREATE TABLE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397290, 'dsql_create_pack_failed', 'CREATE PACKAGE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397291, 'dsql_alter_pack_failed', 'ALTER PACKAGE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397292, 'dsql_create_alter_pack_failed', 'CREATE OR ALTER PACKAGE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397293, 'dsql_drop_pack_failed', 'DROP PACKAGE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397294, 'dsql_recreate_pack_failed', 'RECREATE PACKAGE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397295, 'dsql_create_pack_body_failed', 'CREATE PACKAGE BODY @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397296, 'dsql_drop_pack_body_failed', 'DROP PACKAGE BODY @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397297, 'dsql_recreate_pack_body_failed', 'RECREATE PACKAGE BODY @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397298, 'dsql_create_view_failed', 'CREATE VIEW @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397299, 'dsql_alter_view_failed', 'ALTER VIEW @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397300, 'dsql_create_alter_view_failed', 'CREATE OR ALTER VIEW @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397301, 'dsql_recreate_view_failed', 'RECREATE VIEW @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397302, 'dsql_drop_view_failed', 'DROP VIEW @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397303, 'dsql_drop_sequence_failed', 'DROP SEQUENCE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397304, 'dsql_recreate_sequence_failed', 'RECREATE SEQUENCE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397305, 'dsql_drop_index_failed', 'DROP INDEX @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397306, 'dsql_drop_filter_failed', 'DROP FILTER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397307, 'dsql_drop_shadow_failed', 'DROP SHADOW @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397308, 'dsql_drop_role_failed', 'DROP ROLE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397309, 'dsql_drop_user_failed', 'DROP USER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397310, 'dsql_create_role_failed', 'CREATE ROLE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397311, 'dsql_alter_role_failed', 'ALTER ROLE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397312, 'dsql_alter_index_failed', 'ALTER INDEX @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397313, 'dsql_alter_database_failed', 'ALTER DATABASE failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397314, 'dsql_create_shadow_failed', 'CREATE SHADOW @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397315, 'dsql_create_filter_failed', 'DECLARE FILTER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397316, 'dsql_create_index_failed', 'CREATE INDEX @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397317, 'dsql_create_user_failed', 'CREATE USER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397318, 'dsql_alter_user_failed', 'ALTER USER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397319, 'dsql_grant_failed', 'GRANT failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397320, 'dsql_revoke_failed', 'REVOKE failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397321, 'dsql_cte_recursive_aggregate', 'Recursive member of CTE cannot use aggregate or window function');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397322, 'dsql_mapping_failed', '@2 MAPPING @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397323, 'dsql_alter_sequence_failed', 'ALTER SEQUENCE @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397324, 'dsql_create_generator_failed', 'CREATE GENERATOR @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397325, 'dsql_set_generator_failed', 'SET GENERATOR @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397326, 'dsql_wlock_simple', 'WITH LOCK can be used only with a single physical table');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397327, 'dsql_firstskip_rows', 'FIRST/SKIP cannot be used with OFFSET/FETCH or ROWS');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397328, 'dsql_wlock_aggregates', 'WITH LOCK cannot be used with aggregates');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -104, 336397329, 'dsql_wlock_conflict', 'WITH LOCK cannot be used with @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397330, 'dsql_max_exception_arguments', 'Number of arguments (@1) exceeds the maximum (@2) number of EXCEPTION USING arguments');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397331, 'dsql_string_byte_length', 'String literal with @1 bytes exceeds the maximum length of @2 bytes');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397332, 'dsql_string_char_length', 'String literal with @1 characters exceeds the maximum length of @2 characters for the @3 character set');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397333, 'dsql_max_nesting', 'Too many BEGIN...END nesting. Maximum level is @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336397334, 'dsql_recreate_user_failed', 'RECREATE USER @1 failed');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723983, 'gsec_cant_open_db', 'unable to open database');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723984, 'gsec_switches_error', 'error in switch specifications');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723985, 'gsec_no_op_spec', 'no operation specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723986, 'gsec_no_usr_name', 'no user name specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723987, 'gsec_err_add', 'add record error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723988, 'gsec_err_modify', 'modify record error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723989, 'gsec_err_find_mod', 'find/modify record error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723990, 'gsec_err_rec_not_found', 'record not found for user: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723991, 'gsec_err_delete', 'delete record error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723992, 'gsec_err_find_del', 'find/delete record error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723996, 'gsec_err_find_disp', 'find/display record error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723997, 'gsec_inv_param', 'invalid parameter, no switch defined');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723998, 'gsec_op_specified', 'operation already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336723999, 'gsec_pw_specified', 'password already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724000, 'gsec_uid_specified', 'uid already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724001, 'gsec_gid_specified', 'gid already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724002, 'gsec_proj_specified', 'project already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724003, 'gsec_org_specified', 'organization already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724004, 'gsec_fname_specified', 'first name already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724005, 'gsec_mname_specified', 'middle name already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724006, 'gsec_lname_specified', 'last name already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724008, 'gsec_inv_switch', 'invalid switch specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724009, 'gsec_amb_switch', 'ambiguous switch specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724010, 'gsec_no_op_specified', 'no operation specified for parameters');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724011, 'gsec_params_not_allowed', 'no parameters allowed for this operation');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724012, 'gsec_incompat_switch', 'incompatible switches specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724044, 'gsec_inv_username', 'Invalid user name (maximum 31 bytes allowed)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724045, 'gsec_inv_pw_length', 'Warning - maximum 8 significant bytes of password used');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724046, 'gsec_db_specified', 'database already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724047, 'gsec_db_admin_specified', 'database administrator name already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724048, 'gsec_db_admin_pw_specified', 'database administrator password already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336724049, 'gsec_sql_role_specified', 'SQL role name already specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336920577, 'gstat_unknown_switch', 'found unknown switch');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336920578, 'gstat_retry', 'please retry, giving a database name');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336920579, 'gstat_wrong_ods', 'Wrong ODS version, expected @1, encountered @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336920580, 'gstat_unexpected_eof', 'Unexpected end of database file.');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336920605, 'gstat_open_err', 'Can''t open database file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336920606, 'gstat_read_err', 'Can''t read a database page');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336920607, 'gstat_sysmemex', 'System memory exhausted');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986113, 'fbsvcmgr_bad_am', 'Wrong value for access mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986114, 'fbsvcmgr_bad_wm', 'Wrong value for write mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986115, 'fbsvcmgr_bad_rs', 'Wrong value for reserve space');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986116, 'fbsvcmgr_info_err', 'Unknown tag (@1) in info_svr_db_info block after isc_svc_query()');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986117, 'fbsvcmgr_query_err', 'Unknown tag (@1) in isc_svc_query() results');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986118, 'fbsvcmgr_switch_unknown', 'Unknown switch \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986159, 'fbsvcmgr_bad_sm', 'Wrong value for shutdown mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986160, 'fbsvcmgr_fp_open', 'could not open file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986161, 'fbsvcmgr_fp_read', 'could not read file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986162, 'fbsvcmgr_fp_empty', 'empty file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 336986164, 'fbsvcmgr_bad_arg', 'Invalid or missing parameter for switch @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337051649, 'utl_trusted_switch', 'Switches trusted_user and trusted_role are not supported from command line');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117213, 'nbackup_missing_param', 'Missing parameter for switch @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117214, 'nbackup_allowed_switches', 'Only one of -LOCK, -UNLOCK, -FIXUP, -BACKUP or -RESTORE should be specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117215, 'nbackup_unknown_param', 'Unrecognized parameter @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117216, 'nbackup_unknown_switch', 'Unknown switch @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117217, 'nbackup_nofetchpw_svc', 'Fetch password can''t be used in service mode');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117218, 'nbackup_pwfile_error', 'Error working with password file \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117219, 'nbackup_size_with_lock', 'Switch -SIZE can be used only with -LOCK');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117220, 'nbackup_no_switch', 'None of -LOCK, -UNLOCK, -FIXUP, -BACKUP or -RESTORE specified');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117223, 'nbackup_err_read', 'IO error reading file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117224, 'nbackup_err_write', 'IO error writing file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117225, 'nbackup_err_seek', 'IO error seeking file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117226, 'nbackup_err_opendb', 'Error opening database file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117227, 'nbackup_err_fadvice', 'Error in posix_fadvise(@1) for database @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117228, 'nbackup_err_createdb', 'Error creating database file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117229, 'nbackup_err_openbk', 'Error opening backup file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117230, 'nbackup_err_createbk', 'Error creating backup file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117231, 'nbackup_err_eofdb', 'Unexpected end of database file @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117232, 'nbackup_fixup_wrongstate', 'Database @1 is not in state (@2) to be safely fixed up');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117233, 'nbackup_err_db', 'Database error');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117234, 'nbackup_userpw_toolong', 'Username or password is too long');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117235, 'nbackup_lostrec_db', 'Cannot find record for database \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117236, 'nbackup_lostguid_db', 'Internal error. History query returned null SCN or GUID');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117237, 'nbackup_err_eofhdrdb', 'Unexpected end of file when reading header of database file \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117238, 'nbackup_db_notlock', 'Internal error. Database file is not locked. Flags are @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117239, 'nbackup_lostguid_bk', 'Internal error. Cannot get backup guid clumplet');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117240, 'nbackup_page_changed', 'Internal error. Database page @1 had been changed during backup (page SCN=@2, backup SCN=@3)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117241, 'nbackup_dbsize_inconsistent', 'Database file size is not a multiple of page size');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117242, 'nbackup_failed_lzbk', 'Level 0 backup is not restored');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117243, 'nbackup_err_eofhdrbk', 'Unexpected end of file when reading header of backup file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117244, 'nbackup_invalid_incbk', 'Invalid incremental backup file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117245, 'nbackup_unsupvers_incbk', 'Unsupported version @1 of incremental backup file: @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117246, 'nbackup_invlevel_incbk', 'Invalid level @1 of incremental backup file: @2, expected @3');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117247, 'nbackup_wrong_orderbk', 'Wrong order of backup files or invalid incremental backup file detected, file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117248, 'nbackup_err_eofbk', 'Unexpected end of backup file: @1');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117249, 'nbackup_err_copy', 'Error creating database file: @1 via copying from: @2');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117250, 'nbackup_err_eofhdr_restdb', 'Unexpected end of file when reading header of restored database file (stage @1)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117251, 'nbackup_lostguid_l0bk', 'Cannot get backup guid clumplet from L0 backup');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117255, 'nbackup_switchd_parameter', 'Wrong parameter @1 for switch -D, need ON or OFF');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117257, 'nbackup_user_stop', 'Terminated due to user request');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117259, 'nbackup_deco_parse', 'Too complex decompress command (> @1 arguments)');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337117261, 'nbackup_lostrec_guid_db', 'Cannot find record for database \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182750, 'trace_conflict_acts', 'conflicting actions \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182751, 'trace_act_notfound', 'action switch not found');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182752, 'trace_switch_once', 'switch \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182753, 'trace_param_val_miss', 'value for switch \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182754, 'trace_param_invalid', 'invalid value (\');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182755, 'trace_switch_unknown', 'unknown switch \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182756, 'trace_switch_svc_only', 'switch \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182757, 'trace_switch_user_only', 'switch \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182758, 'trace_switch_param_miss', 'mandatory parameter \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182759, 'trace_param_act_notcompat', 'parameter \');
insert into fb_errors(fb_sqlcode, fb_gdscode, fb_mnemona, fb_errtext) values( -901, 337182760, 'trace_mandatory_switch_miss', 'mandatory switch \');
commit;

-- REMOVE unneeded indices on field 'ID' for some tables if setting 'C_MINIMAL_PK_CREATION' = '1'
-- Prevent PK for: qdistr,qstorned,pdistr,pstorned - only if setting
-- 'HALT_TEST_ON_ERRORS' containing 'PK'
set list on;
set term ^;
execute block returns(add_info varchar(255)) as
    declare v_tab_name dm_dbobj;
    declare v_idx_name dm_dbobj;
    declare v_ctr_type dm_dbobj;
    declare v_ctr_name dm_dbobj;
    declare v_run_ddl varchar(128);
    declare v_rel_list varchar(255);
    declare v_halt_on_err_list dm_setting_value = '//';
begin
    select upper(s.svalue) from settings s where s.mcode='HALT_TEST_ON_ERRORS'
    into v_halt_on_err_list; -- '/CK/'; '/CK/PK/'

    if ( v_halt_on_err_list containing upper('/PK/') ) then
    begin
        add_info = 'Setting ''HALT_TEST_ON_ERRORS'' contains ''PK'', we have to preserve PK/UK in tables even if they are unneeded.';
        --#####
        exit; -- PRESERVE PKs!
        --#####
    end

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
        add_info = 'DROP unneeded primary/unique constraint from table '||trim(v_tab_name);
        suspend;
    end

end
^
set term ;^
commit;
set list off;

-- moved into 1build_oltp_emul.bat: execute procedure init_autogen_qdistr_tables; -- 29.08.2015, branch: create_with_split_heavy_tabs

set list on;
set echo off;
select 'oltp_main_filling.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;
-- #############################################################################
-- End of script oltp_main_filling.sql; next to be run: 
-- oltp_split_heavy_tabs_<N>.sql, 
-- where <N> = value of config parameter 'create_with_split_heavy_tabs' (0 or 1)
-- #############################################################################

