-- #################################################
-- Begin of script oltp30_SP.sql (application units)
-- #################################################
-- ::: nb ::: Required FB version: 3.0 and above
set bail on;
set autoddl off;
set list on;
select 'oltp30_sp.sql start at ' || current_timestamp as msg from rdb$database;
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

set term ^;
execute block as
begin
    if ( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.' ) then
    begin
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

set term ^;

create or alter procedure srv_increment_tx_bops_counter
as
begin
    rdb$set_context( 'USER_TRANSACTION', 'BUSINESS_OPS_CNT', coalesce( cast(rdb$get_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT') as int), 0) + 1);
end

^ -- srv_increment_tx_bops_counter

create or alter procedure sp_fill_shopping_cart(
    a_optype_id dm_idb,
    a_rows2add int default null, 
    a_maxq4row int default null)
returns(
    row_cnt int, -- number of rows added to tmp$shop_cart
    qty_sum dm_qty -- total on QTY field in tmp$shop_cart
)
as
    declare v_doc_rows int;
    declare v_id dm_idb;
    declare v_ware_id type of dm_idb;
    declare v_qty dm_qty;
    declare v_cost_purchase dm_cost;
    declare v_cost_retail dm_cost;
    declare v_snd_optype_id dm_idb;
    declare v_storno_sub smallint;
    declare v_ctx_max_rows type of dm_ctxnv;
    declare v_ctx_max_qty type of dm_ctxnv;
    declare v_stt varchar(255);
    declare v_pattern type of dm_name;
    declare v_source_for_random_id dm_dbobj;
    declare v_source_for_min_id dm_dbobj;
    declare v_source_for_max_id dm_dbobj;
    declare v_raise_exc_on_nofind dm_sign;
    declare v_can_skip_order_clause dm_sign;
    declare v_find_using_desc_index dm_sign;
    declare v_this dm_dbobj = 'sp_fill_shopping_cart';
    declare v_info dm_info = '';
begin
    -- Fills "shopping cart" table with wares ID for futher handling.
    -- If context var 'ENABLE_FILL_PHRASES' = 1 then does it via SIMILAR TO
    -- by searching phrases (patterns) in wares.name table.
    -- Used in apps that CREATE new documents (client order, customer reserve etc)

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    v_ctx_max_rows = iif( a_optype_id in ( fn_oper_order_for_supplier(), fn_oper_invoice_get() ),
                          'C_SUPPLIER_DOC_MAX_ROWS',
                          'C_CUSTOMER_DOC_MAX_ROWS'
                        );
    v_ctx_max_qty = iif( a_optype_id in ( fn_oper_order_for_supplier(), fn_oper_invoice_get() ),
                          'C_SUPPLIER_DOC_MAX_QTY',
                          'C_CUSTOMER_DOC_MAX_QTY'
                        );

    v_doc_rows =  coalesce( a_rows2add, fn_get_random_quantity( v_ctx_max_rows ) ) ;

    v_source_for_random_id =
        decode( a_optype_id,
                fn_oper_order_by_customer(),  'v_all_wares',
                fn_oper_order_for_supplier(), 'v_random_find_clo_ord',
                fn_oper_invoice_get(),        'v_random_find_ord_sup',
                fn_oper_retail_reserve(),     'v_random_find_avl_res',
                'unknown_source'
              );

    v_source_for_min_id =
        decode( a_optype_id,
                fn_oper_order_for_supplier(), 'v_min_id_clo_ord',
                fn_oper_invoice_get(),        'v_min_id_ord_sup',
                fn_oper_retail_reserve(),     'v_min_id_avl_res',
                null
              );

    v_source_for_max_id =
        decode( a_optype_id,
                fn_oper_order_for_supplier(), 'v_max_id_clo_ord',
                fn_oper_invoice_get(),        'v_max_id_ord_sup',
                fn_oper_retail_reserve(),     'v_max_id_avl_res',
                null
              );

    -- 17.07.2014: for some cases we allow to skip 'ORDER BY ID' clause
    -- in sp_get_random_id when it will generate SQL expr for ES,
    -- because all such randomly choosen IDs are handled in so way
    -- that thay will be unavaliable in the source view
    -- after this handling after it successfully ends.
    -- Since 11.09.2014, start usage id desc in sp_get_random_id,
    -- bitmaps building is very expensive ==> always set this var = 0.
    v_can_skip_order_clause = 0;

    -- 19.07.2014, see DDL of views v_random_find_xxx:
    -- they have `where not exists(select * from ... c id >= :id_rand_selected)`,
    -- so it can be that search will NOT found any ID due to unhappy result of random
    -- selection of 'anchor-ID' (no IDs will be found in 'where id >= :id_selected'
    -- due to all of them have been removed etc) ==> we suppress e`xc in such case!
    v_raise_exc_on_nofind =
        decode( a_optype_id,
                fn_oper_order_by_customer(),  0,
                fn_oper_order_for_supplier(), 0,
                fn_oper_invoice_get(),        0,
                fn_oper_retail_reserve(),     0,
                1
              );

    v_find_using_desc_index =
        decode( a_optype_id,
                fn_oper_order_for_supplier(), 1,
                fn_oper_invoice_get(),        1,
                fn_oper_retail_reserve(),     1,
                0
              );

    select
        r.snd_optype_id
        ,r.storno_sub
    from rules_for_qdistr r
    where
        r.rcv_optype_id = :a_optype_id
        and r.mode containing 'new_doc' 
    into v_snd_optype_id, v_storno_sub;

    v_info = 'view='||v_source_for_random_id||', rows='||v_doc_rows||', oper='||a_optype_id;

    delete from tmp$shopping_cart where 1=1;
    row_cnt = 0;
    qty_sum = 0;

    for
        select p.id_selected
        from
                sp_get_random_id(
                    :v_source_for_random_id,
                    :v_source_for_min_id,
                    :v_source_for_max_id,
                    :v_raise_exc_on_nofind, -- 19.07.2014: 0 ==> do NOT raise exception if not able to find any ID in view :v_source_for_random_id
                    :v_can_skip_order_clause, -- 17.07.2014: if = 1, then 'order by id' will be SKIPPED in statement inside fn
                    :v_find_using_desc_index, -- 11.09.2014, performance of select id from v_xxx order by id DESC rows 1
                    :v_doc_rows
                ) p
         into v_ware_id
    do
    begin
        v_qty = coalesce(a_maxq4row, fn_get_random_quantity( v_ctx_max_qty ));
        if ( a_optype_id = fn_oper_order_by_customer() ) then
        begin
            -- Define cost of ware being added in customer order,
            -- in purchasing and retailing prices (allow them to vary):
            select
                 round( w.price_purchase + rand() * 300, -2) * :v_qty
                ,round( w.price_retail + rand() * 300, -2) * :v_qty
            from wares w
            where w.id = :v_ware_id
            into v_cost_purchase, v_cost_retail;
        end

        if ( v_ware_id is not null ) then
        begin
            -- All the views v_r`andom_finx_xxx have checking clause like
            -- "where NOT exists(select * from tmp$shopping_cart c where ...)"
            -- so we can immediatelly do INSERT rather than update+check row_count=0
            insert into tmp$shopping_cart(
                id,
                snd_optype_id,
                rcv_optype_id,
                qty,
                storno_sub,
                cost_purchase,
                cost_retail
            )
            values (
                :v_ware_id,
                :v_snd_optype_id,
                :a_optype_id,
                :v_qty,
                :v_storno_sub,
                :v_cost_purchase,
                :v_cost_retail
            );
            row_cnt = row_cnt + 1; -- out arg, will be used in getting batch IDs for doc_data (reduce lock-contention of GEN page)
            qty_sum = qty_sum + ceiling( v_qty ); -- out arg, will be passed to s`p_multiply_rows_for_pdistr, s`p_make_qty_storno
        
        when any
            do begin
                if ( fn_is_uniqueness_trouble(gdscode) ) then
                    update tmp$shopping_cart t
                    set t.dup_cnt = t.dup_cnt+1 -- 4debug only
                    where t.id = :v_ware_id;
                else
                    exception; -- anonimous but in WHEN block
            end
        end -- v_ware_id not null
    end

--    while ( v_doc_rows > 0 ) do begin
--
--        v_qty = coalesce(a_maxq4row, fn_get_random_quantity( v_ctx_max_qty ));
--
--        if ( a_optype_id = fn_oper_order_by_customer() ) then
--            begin
--                if ( rdb$get_context('USER_SESSION','ENABLE_FILL_PHRASES')='1' -- enable check performance of similar_to
--                     and
--                     exists( select * from phrases )
--                   ) then
--                    begin
--                        -- For checking performance of SIMILAR TO:
--                        -- search using preliminary generated patterns
--                        -- (generation of them see in oltp_fill_data.sql):
--                        select p.pattern from phrases p
--                        where p.id = (select sp_get_random_id('phrases',null,null, :v_raise_exc_on_nofind) from rdb$database)
--                        into v_pattern;
--                        v_stt = 'select id from wares where '||v_pattern||' rows 1';
--                        execute statement(v_stt) into v_ware_id;
--                        if ( v_ware_id is null ) then
--                          exception ex_record_not_found using ('wares', v_pattern);
--                    end
--                else
--                    v_ware_id =
--                    sp_get_random_id(
--                        v_source_for_random_id,
--                        null,
--                        null,
--                        :v_raise_exc_on_nofind
--                    ); -- <<< take random ware from price list
--
--                -- Define cost of ware being added in customer order,
--                -- in purchasing and retailing prices (allow them to vary):
--                select
--                     round( w.price_purchase + rand() * 300, -2) * :v_qty
--                    ,round( w.price_retail + rand() * 300, -2) * :v_qty
--                from wares w
--                where w.id = :v_ware_id
--                into v_cost_purchase, v_cost_retail;
--            end
--        else -- a_optype_id <> fn_oper_order_by_customer()
--            begin
--                v_ware_id =
--                sp_get_random_id(
--                    v_source_for_random_id,
--                    v_source_for_min_id,
--                    v_source_for_max_id,
--                    v_raise_exc_on_nofind, -- 19.07.2014: 0 ==> do NOT raise exception if not able to find any ID in view :v_source_for_random_id
--                    v_can_skip_order_clause, -- 17.07.2014: if = 1, then 'order by id' will be SKIPPED in statement inside fn
--                    v_find_using_desc_index -- 11.09.2014, performance of select id from v_xxx order by id DESC rows 1
--                );
--            end
--
--        if ( v_ware_id is not null ) then
--        begin
--            -- All the views v_r`andom_finx_xxx have checking clause like
--            -- "where NOT exists(select * from tmp$shopping_cart c where ...)"
--            -- so we can immediatelly do INSERT rather than update+check row_count=0
--            insert into tmp$shopping_cart(
--                id,
--                snd_optype_id,
--                rcv_optype_id,
--                qty,
--                storno_sub,
--                cost_purchase,
--                cost_retail
--            )
--            values (
--                :v_ware_id,
--                :v_snd_optype_id,
--                :a_optype_id,
--                :v_qty,
--                :v_storno_sub,
--                :v_cost_purchase,
--                :v_cost_retail
--            );
--            row_cnt = row_cnt + 1; -- out arg, will be used in getting batch IDs for doc_data (reduce lock-contention of GEN page)
--            qty_sum = qty_sum + ceiling( v_qty ); -- out arg, will be passed to s`p_multiply_rows_for_pdistr, s`p_make_qty_storno
--
--        when any
--            do begin
--                if ( fn_is_uniqueness_trouble(gdscode) ) then
--                    update tmp$shopping_cart t
--                    set t.dup_cnt = t.dup_cnt+1 -- 4debug only
--                    where t.id = :v_ware_id;
--                else
--                    exception; -- anonimous but in WHEN block
--            end
--        end -- v_ware_id not null
--        v_doc_rows = v_doc_rows -1;
--
--    end -- while ( v_doc_rows > 0 ) 

    if ( not exists(select * from tmp$shopping_cart) ) then
        exception ex_no_rows_in_shopping_cart using( v_source_for_random_id ); -- 'shopping_cart is empty, check source ''@1'''

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this,null, v_info );

    suspend; -- row_cnt, qty_sum

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

^ -- sp_fill_shopping_cart

------------------------------------------------------------------------------

create or alter procedure sp_client_order(
    dbg int default 0,
    dbg_rows2add int default null,
    dbg_maxq4row int default null
)
returns (
    doc_list_id type of dm_idb,
    agent_id type of dm_idb,
    doc_data_id type of dm_idb,
    ware_id type of dm_idb,
    qty type of dm_qty,
    purchase type of dm_cost, -- purchasing cost for qty
    retail type of dm_cost, -- retail cost
    qty_clo type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_clr type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_ord type of dm_qty -- new value of corresponding row in invnt_saldo
)
as
    declare c_gen_inc_step_dd int = 20; -- size of `batch` for get at once new IDs for doc_data (reduce lock-contention of gen page)
    declare v_gen_inc_iter_dd int; -- increments from 1  up to c_gen_inc_step_dd and then restarts again from 1
    declare v_gen_inc_last_dd dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_dd)

    declare c_gen_inc_step_nt int = 20; -- size of `batch` for get at once new IDs for invnt_turnover_log (reduce lock-contention of gen page)
    declare v_gen_inc_iter_nt int; -- increments from 1  up to c_gen_inc_step_dd and then restarts again from 1
    declare v_gen_inc_last_nt dm_idb; -- last got value after call gen_id (..., c_gen_inc_step_dd)

    declare v_oper_order_by_customer dm_idb;
    declare v_nt_new_id dm_idb;
    declare v_clo_for_our_firm dm_sign = 0;
    declare v_rows_added int = 0;
    declare v_qty_sum dm_qty = 0;
    declare v_purchase_sum dm_cost;
    declare v_retail_sum dm_cost;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_dd_new_id bigint;
    declare v_dd_dbkey dm_dbkey;
    declare v_dbkey dm_dbkey;
    declare v_this dm_dbobj = 'sp_client_order';

    declare c_shop_cart cursor for (
        select
            c.id,
            c.qty,
            c.cost_purchase,
            c.cost_retail
        from tmp$shopping_cart c
    );
begin
    -- Selects randomly agent, wares and creates a new document with wares which
    -- we should provide to customer ("CLIENT ORDER"). Business starts from THIS
    -- kind of doc: customer comes in our office and wants to buy / order smthn.
    
    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    v_oper_order_by_customer = fn_oper_order_by_customer();

    -- Random select contragent for this client order
    -- About 20...30% of orders are for our firm (==> they will NOT move to
    -- 'reserves' after corresponding invoices will be added to stock balance):
    if ( rand()*100 <= cast(rdb$get_context('USER_SESSION', 'ORDER_FOR_OUR_FIRM_PERCENT') as int) ) then
        begin
            v_clo_for_our_firm = 1;
            --agent_id = sp_get_random_id('v_our_firm', null, null, 0);
            select id_selected from sp_get_random_id('v_our_firm', null, null, 0) into agent_id;
        end
    else
        agent_id = fn_get_random_customer();

    execute procedure sp_fill_shopping_cart( v_oper_order_by_customer, dbg_rows2add, dbg_maxq4row )
    returning_values v_rows_added, v_qty_sum;

    if (dbg=1) then exit;

    execute procedure sp_add_doc_list(
        null,
        v_oper_order_by_customer,
        agent_id,
        fn_doc_fix_state()
    )
    returning_values
        :doc_list_id, -- out arg
        :v_dbkey;

    v_gen_inc_iter_dd = 1;
    c_gen_inc_step_dd = 1 + v_rows_added; -- for adding rows in doc_data: size of batch = number of rows in tmp$shop_cart + 1
    v_gen_inc_last_dd = gen_id( g_doc_data, :c_gen_inc_step_dd );-- take bulk IDs at once (reduce lock-contention for GEN page)

    v_gen_inc_iter_nt = 1;
    c_gen_inc_step_nt = 1 + v_rows_added; -- for adding rows in invnt_turnover_log: size of batch = number of rows in tmp$shop_cart + 1
    v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );-- take bulk IDs at once (reduce lock-contention for GEN page)

    v_purchase_sum = 0;
    v_retail_sum = 0;

    -- Process each record in tmp$shopping_cart:
    -- 1) add row to detalization table (doc_data) with amount that client orders;
    -- 2) add for each row from shoping cart SEVERAL rows in QDistr - they form
    --    set of records for futher STORNING by new document(s) in next business
    -- operation (our order to supplier). Number of rows being added in QDistr
    -- equals to doc_data.qty (for simplicity of code these amounts are considered
    -- to be always INTEGER values).
    open c_shop_cart;
    while (1=1) do
    begin
        fetch c_shop_cart into ware_id, qty, purchase, retail;
        if ( row_count = 0 ) then leave;

        if ( v_gen_inc_iter_dd = c_gen_inc_step_dd ) then -- its time to get another batch of IDs
        begin
            v_gen_inc_iter_dd = 1;
            -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
            v_gen_inc_last_dd = gen_id( g_doc_data, :c_gen_inc_step_dd );
        end
        v_dd_new_id = v_gen_inc_last_dd - ( c_gen_inc_step_dd - v_gen_inc_iter_dd );

--        rdb$set_context('USER_TRANSACTION','DBG_DD_D',
--              'v_dd_new_id='||v_dd_new_id
--            ||', v_last_dd='||v_gen_inc_last_dd
--            ||', c_step_dd='||c_gen_inc_step_dd
--            ||', v_iter_dd='||v_gen_inc_iter_dd
--        );
        v_gen_inc_iter_dd = v_gen_inc_iter_dd + 1;

        if ( v_gen_inc_iter_nt = c_gen_inc_step_nt ) then -- its time to get another batch of IDs
        begin
            v_gen_inc_iter_nt = 1;
            -- take subsequent bulk IDs at once (reduce lock-contention for GEN page)
            v_gen_inc_last_nt = gen_id( g_common, :c_gen_inc_step_nt );
        end
        v_nt_new_id = v_gen_inc_last_nt - ( c_gen_inc_step_nt - v_gen_inc_iter_nt );
        v_gen_inc_iter_nt = v_gen_inc_iter_nt + 1;

        execute procedure sp_add_doc_data(
            doc_list_id,
            v_oper_order_by_customer,
            v_dd_new_id, -- preliminary calculated ID for new record in doc_data (reduce lock-contention of GEN page)
            v_nt_new_id, -- preliminary calculated ID for new record in invnt_turnover_log (reduce lock-contention of GEN page)
            ware_id,
            qty,
            purchase,
            retail
        ) returning_values v_dd_new_id, v_dd_dbkey;

        -- Write ref to doc_data.id - it will be used in sp_multiply_rows_for_qdistr:
        update tmp$shopping_cart c set c.snd_id = :v_dd_new_id where current of c_shop_cart;

        -- do NOT use trigger-way updates of doc header for each row being added
        -- in detalization table: it will be run only once after this loop (performance):
        v_purchase_sum = v_purchase_sum + purchase;
        v_retail_sum = v_retail_sum + retail;
    end -- cursor on tmp$shopping_car join wares
    close c_shop_cart;

    if (dbg=2) then exit;
    -- 02.09.2014 2205: remove call of sp_multiply_rows_for_qdistr from t`rigger d`oc_data_aiud
    -- (otherwise fractional values in cumulative qdistr.snd_purchase will be when costs for
    --  same ware in several storned docs differs):
    -- 30.09.2014: move out from for-loop, single call:
    execute procedure sp_multiply_rows_for_qdistr(
        doc_list_id,
        v_oper_order_by_customer,
        v_clo_for_our_firm,
        v_qty_sum -- this is number of _ROWS_ that will be added into QDistr (used to calc. size of 'bulks' of new IDs - minimize call of gen_id in sp_multiply_rows_for_qdistr)
    );
    if (dbg=3) then exit;

    -- Single update of doc header (not for every row added in doc_data table
    -- as it would be via it's trigger).
    -- Trigger d`oc_list_aiud will call sp_add_invnt_log to add rows to invnt_turnover_log
    update doc_list h set
        h.cost_purchase = :v_purchase_sum,
        h.cost_retail = :v_retail_sum
    where h.rdb$db_key  = :v_dbkey;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this,null, 'doc_id='||coalesce(doc_list_id,'<null>')||', rows='||v_rows_added );

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);
    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if ( v_ibe = 1 ) then
        v_stt = 'select v.agent_id, v.doc_data_id, v.ware_id, v.qty, v.cost_purchase, v.cost_retail'
                ||',v.qty_clo ,v.qty_clr ,v.qty_ord'
                ||' from v_doc_detailed v where v.doc_id = :x';
    else
        v_stt = 'select h.agent_id, d.id, d.ware_id, d.qty, d.cost_purchase, d.cost_retail'
                ||',null      ,null      ,null'
                ||' from doc_data d join doc_list h on d.doc_id = h.id where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement(v_stt) ( x := :doc_list_id )
    into
         agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_clo
        ,qty_clr
        ,qty_ord
    do
    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- end of sp_client_order
------------------------------------------------------------------------------

create or alter procedure sp_cancel_client_order(
    a_selected_doc_id type of dm_idb default null,
    dbg int default 0
)
returns (
    doc_list_id type of dm_idb,
    agent_id type of dm_idb,
    doc_data_id type of dm_idb,
    ware_id type of dm_idb,
    qty type of dm_qty,
    purchase type of dm_cost, -- purchasing cost for qty
    retail type of dm_cost, -- retail cost
    qty_clo type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_clr type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_ord type of dm_qty
)
as
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_dummy bigint;
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
    declare v_this dm_dbobj = 'sp_cancel_client_order';
begin

    -- Moves client order in 'cancelled' state. No rows from such client order
    -- will be ordered to supplier (except those which we already ordered before)

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            (select id_selected from
                            sp_get_random_id( 'v_cancel_client_order' -- a_view_for_search
                                              ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                              ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                              ,:c_raise_exc_when_no_found
                                              ,:c_can_skip_order_clause
                                            )
                            )
                          );

    -- Find doc ID (with checking in view v_*** is need) and try to LOCK it.
    -- Raise exc if can`t lock:
    execute procedure sp_lock_selected_doc( doc_list_id, 'v_cancel_client_order', a_selected_doc_id);

    -- 20.05.2014: BLOCK client_order in ALL cases instead of solving question about deletion
    -- Trigger doc_list_biud will (only for deleting doc or updating it's state):
    -- 1) call s`p_kill_qty_storno that returns rows from Q`Storned to Q`distr 
    -- Trigger doc_list_aiud will:
    -- 1) add rows in table i`nvnt_turnover_log (log to be processed by SP s`rv_make_invnt_saldo)
    -- 2) call s`p_multiply_rows_for_pdistr, s`p_make_cost_storno or s`p_kill_cost_storno, s`p_add_money_log
    update doc_list h set
        h.optype_id = fn_oper_cancel_customer_order(),
        h.state_id = fn_doc_canc_state() --"cancelled without revert"
    where h.id = :doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this,null, 'doc_id='||doc_list_id);

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);
    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if ( v_ibe = 1 ) then
        v_stt = 'select v.agent_id, v.doc_data_id, v.ware_id, v.qty, v.cost_purchase, v.cost_retail'
                ||',v.qty_clo ,v.qty_clr ,v.qty_ord'
                ||' from v_doc_detailed v where v.doc_id = :x';
    else
        v_stt = 'select h.agent_id, d.id, d.ware_id, d.qty, d.cost_purchase, d.cost_retail'
                ||',null      ,null      ,null'
                ||' from doc_data d join doc_list h on d.doc_id = h.id where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement(v_stt) ( x := :doc_list_id )
    into
         agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_clo
        ,qty_clr
        ,qty_ord
    do
    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- end of sp_cancel_client_order

------------------------------------------------------------------------------

create or alter procedure sp_supplier_order(
    dbg int default 0,
    dbg_rows2add int default null,
    dbg_maxq4row int default null
)
returns (
    doc_list_id type of dm_idb,
    agent_id type of dm_idb,
    doc_data_id type of dm_idb,
    ware_id type of dm_idb,
    qty type of dm_qty, -- amount that we ordered for client
    purchase type of dm_cost, -- purchasing cost for qty
    retail type of dm_cost, -- retail cost
    qty_clo type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_ord type of dm_qty -- new value of corresponding row in invnt_saldo
)
as
    declare v_id bigint;
    declare v_rows_added int;
    declare v_qty_sum dm_qty;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_dummy bigint;
    declare v_this dm_dbobj = 'sp_supplier_order';
begin

    -- Processes several client orders and creates OUR order of wares to randomly
    -- selected supplier (i.e. we expect these wares to be supplied by him).
    -- Makes storning of corresp. amounts, so preventing duplicate including in further
    -- supplier orders such wares (part of their total amounts) which was already ordered.
    -- This operation is NEXT after client order in 'business chain'.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    -- choose randomly contragent that will be supplier for this order:
    agent_id = fn_get_random_supplier();

    execute procedure sp_fill_shopping_cart( fn_oper_order_for_supplier(), dbg_rows2add, dbg_maxq4row )
    returning_values v_rows_added, v_qty_sum;

    if (dbg=1) then exit;

    -- 1. Find rows in QDISTR (and silently try to LOCK them) which can provide
    --    required amounts in tmp$shopping_cart, in FIFO manner.
    -- 2. Perform "STORNING" of them (moves these rows from QDISTR to QSTORNED)
    -- 3. Create new document: header (doc_list) and detalization (doc_data).
    execute procedure sp_make_qty_storno(
        fn_oper_order_for_supplier()
        ,agent_id
        ,fn_doc_open_state()
        ,null
        ,v_rows_added -- used there for 'smart' definition of value to increment gen
        ,v_qty_sum -- used there for 'smart' definition of value to increment gen
    ) returning_values doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||coalesce(doc_list_id,'<null>'));

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);

    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if ( v_ibe = 1 ) then
       v_stt = 'select v.agent_id, v.doc_data_id, v.ware_id, v.qty, v.cost_purchase, v.cost_retail'
               ||' ,v.qty_clo ,v.qty_ord'
               ||' from v_doc_detailed v where v.doc_id = :x';
    else
       v_stt = 'select h.agent_id, d.id, d.ware_id, d.qty, d.cost_purchase, d.cost_retail'
               ||' ,null     ,null'
               ||' from doc_data d join doc_list h on d.doc_id = h.id where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement(v_stt) ( x := :doc_list_id )
    into
         agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_clo
        ,qty_ord
    do
        suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- end of sp_supplier_order

-----------------------------------------

create or alter procedure sp_supplier_invoice (
    dbg int = 0,
    dbg_rows2add int default null,
    dbg_maxq4row int default null
)
returns (
    doc_list_id type of dm_idb,
    agent_id type of dm_idb,
    doc_data_id type of dm_idb,
    ware_id type of dm_idb,
    qty type of dm_qty,
    purchase type of dm_cost,
    retail type of dm_cost,
    qty_clo type of dm_qty,
    qty_ord type of dm_qty,
    qty_sup type of dm_qty
)
as
    declare v_rows_added int;
    declare v_qty_sum dm_qty;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_this dm_dbobj = 'sp_supplier_invoice';
begin

    -- Simulates activity of our SUPPLIER when he got from us several orders:
    -- process randomly chosen wares from our orders and add them into INVOICE -
    -- the document that we consider as preliminary income (i.e. NOT yet accepted).
    -- Makes storning of corresp. amounts, so preventing duplicate including in further
    -- supplier invoices such wares (part of their total amounts) which was already
    -- included in this invoice.
    -- This operation is NEXT after our order to supplier in 'business chain'.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises exc`eption to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    -- select supplier, random:
    agent_id = fn_get_random_supplier();

    execute procedure sp_fill_shopping_cart( fn_oper_invoice_get(), dbg_rows2add, dbg_maxq4row )
    returning_values v_rows_added, v_qty_sum;

    if (dbg=1) then exit;

    -- 1. Find rows in QDISTR (and silently try to LOCK them) which can provide required
    --    amounts in tmp$shopping_cart, in FIFO manner.
    -- 2. Perform "STORNING" of them (moves these rows from QDISTR to QSTORNED)
    -- 3. Create new document: header (doc_list) and detalization (doc_data).
    execute procedure sp_make_qty_storno(
        fn_oper_invoice_get()
        ,agent_id
        ,fn_doc_open_state()
        ,null
        ,v_rows_added -- used there for 'smart' definition of value to increment gen
        ,v_qty_sum -- used there for 'smart' definition of value to increment gen
    ) returning_values doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||coalesce(doc_list_id,'<null>'));

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);
    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if ( v_ibe = 1 ) then
       v_stt = 'select v.agent_id, v.doc_data_id, v.ware_id, v.qty, v.cost_purchase, v.cost_retail'
               ||' ,v.qty_clo ,v.qty_ord ,v.qty_sup'
               ||' from v_doc_detailed v where v.doc_id = :x';
    else
       v_stt = 'select h.agent_id, d.id, d.ware_id, d.qty, d.cost_purchase, d.cost_retail'
               ||' ,null     ,null       ,null'
               ||' from doc_data d join doc_list h on d.doc_id = h.id where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement(v_stt) ( x := :doc_list_id )
    into
         agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_clo
        ,qty_ord
        ,qty_sup
    do
        suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^ -- end of sp_supplier_invoice

-----------------------------------------

create or alter procedure sp_cancel_supplier_invoice(
    a_selected_doc_id type of dm_idb default null,
    a_skip_lock_attempt dm_sign default 0 -- 1==> do NOT call sp_lock_selected_doc because this doc is already locked (see call from sp_cancel_adding_invoice)
)
returns(
    doc_list_id type of dm_idb, -- id of created invoice
    agent_id type of dm_idb, -- id of supplier
    doc_data_id type of dm_idb, -- id of created records in doc_data
    ware_id type of dm_idb, -- id of wares that we will get from supplier
    qty type of dm_qty, -- amount that supplier will send to us
    purchase type of dm_cost, -- total purchasing cost for qty
    retail type of dm_cost, -- assigned retail cost
    qty_clo type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_ord type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_sup type of dm_qty  -- new value of corresponding row in invnt_saldo
)
as
    declare v_dummy bigint;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
    declare v_this dm_dbobj = 'sp_cancel_supplier_invoice';
begin

    -- Randomly chooses invoice from supplier (NOT yet accepted) and CANCEL it
    -- by REMOVING all its data + record in docs header table. It occurs when
    -- we mistakenly created such invoice and now have to cancel this operation.
    -- All wares which were in such invoice will be enabled again to be included
    -- in new (another) invoice which we create after this - due to removing info
    -- about amounts storning that was done before when invoice was created.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises exc`eption to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            ( select id_selected from
                              sp_get_random_id(  'v_cancel_supplier_invoice' -- a_view_for_search
                                                ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                                ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                                ,:c_raise_exc_when_no_found
                                                ,:c_can_skip_order_clause
                                              )
                            )
                          );
    -- upd. log with doc id whic is actually handling now:
    execute procedure sp_upd_in_perf_log( v_this, null, 'dh='||doc_list_id);

    -- Try to LOCK just selected doc, raise exc if can`t:
    if (  NOT (a_selected_doc_id is NOT null and a_skip_lock_attempt = 1) ) then
        execute procedure sp_lock_selected_doc( doc_list_id, 'v_cancel_supplier_invoice', a_selected_doc_id);

    -- 17.07.2014: add cond for indexed scan to minimize fetches when multiple
    -- calls of this SP from sp_cancel_adding_invoice:
    delete from tmp$result_set r where r.doc_id = :doc_list_id;

    -- save data which is to be deleted (NB! this action became MANDATORY for
    -- checking in srv_find_qd_qs_mism, do NOT delete it!):
    insert into tmp$result_set( doc_id, agent_id, doc_data_id, ware_id, qty, cost_purchase, cost_retail)
    select :doc_list_id, h.agent_id, d.id, d.ware_id, d.qty, d.cost_purchase, d.cost_retail
    from doc_data d
    join doc_list h on d.doc_id = h.id
    where d.doc_id = :doc_list_id; -- invoice which is to be removed now

    -- Trigger doc_list_biud will (only for deleting doc or updating it's state):
    -- 1) call s`p_kill_qty_storno that returns rows from Q`Storned to Q`distr 
    -- Trigger doc_list_aiud will:
    -- 1) add rows in table i`nvnt_turnover_log (log to be processed by SP s`rv_make_invnt_saldo)
    -- 2) call s`p_multiply_rows_for_pdistr, s`p_make_cost_storno or s`p_kill_cost_storno, s`p_add_money_log
    delete from doc_list h where h.id = :doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null);

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);
    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    v_stt = 'select r.doc_id,r.agent_id,r.doc_data_id,r.ware_id,r.qty,r.cost_purchase,r.cost_retail';

    if ( v_ibe = 1 ) then
       v_stt = v_stt || ' ,n.qty_clo ,n.qty_ord ,n.qty_sup';
    else
       v_stt = v_stt || ' ,null     ,null       ,null';

    v_stt = v_stt ||' from tmp$result_set r';
    if ( v_ibe = 1 ) then
       v_stt = v_stt || ' left join v_saldo_invnt n on r.ware_id = n.ware_id';

    -- 17.07.2014: add cond for indexed scan to minimize fetches when multiple
    -- calls of this SP from s`p_cancel_supplier_order:
    v_stt = v_stt || ' where r.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id )
    into
        doc_list_id
        ,agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_clo
        ,qty_ord
        ,qty_sup
    do
        suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_cancel_supplier_invoice

-----------------------------------------

create or alter procedure sp_fill_shopping_cart_clo_res(
    a_client_order_id dm_idb
)
returns (
    row_cnt int, -- number of rows added to tmp$shop_cart
    qty_sum dm_qty -- total on QTY field in tmp$shop_cart
)
as
    declare v_oper_invoice_add dm_idb;
    declare v_oper_retail_reserve dm_idb;
    declare v_oper_order_by_customer dm_idb;
    declare v_ware_id dm_idb;
    declare v_dd_id dm_idb;
    declare v_clo_qty_need_to_reserve dm_qty;
    declare v_this dm_dbobj = 'sp_fill_shopping_cart_clo_res';
begin
    -- Aux. SP: fills tmp$shopping_cart with data from client_order, but take in
    -- account only those amounts which still need to be reserved.

    execute procedure sp_add_perf_log(1, v_this, null, 'clo='||a_client_order_id);

    v_oper_invoice_add =  fn_oper_invoice_add();
    v_oper_order_by_customer = fn_oper_order_by_customer();
    v_oper_retail_reserve = fn_oper_retail_reserve();
    qty_sum = 0; -- out arg
    for
        select
            d.ware_id,
            d.id as dd_id, -- 22.09.2014: for processing in separate cursor in sp_make_qty_distr that used index on snd_op, rcv_op, snd_id
            sum(q.snd_qty) as clo_qty_need_to_reserve -- rest of init amount in client order that still needs to be reserved
        -- 16.09.2014 PLAN SORT (JOIN (D INDEX (FK_DOC_DATA_DOC_LIST), Q INDEX (QDISTR_SNDOP_RCVOP_SNDID_DESC)))
        -- (much faster than old: from qdistr where q.doc_id = :a_client_order_id and snd_op = ... and rcv_op = ...)
        from doc_data d
        LEFT -- !! force to fix plan with 'doc_data' as drive table, see CORE-4926
        join v_qdistr_source q on
             -- :: NB :: full match on index range scan must be here!
             q.ware_id = d.ware_id
             and q.snd_optype_id = :v_oper_order_by_customer
             and q.rcv_optype_id = :v_oper_retail_reserve
             and q.snd_id = d.id --- :: NB :: full match on index range scan must be here!
        where
            d.doc_id = :a_client_order_id
            and q.id is not null
        group by d.ware_id, d.id
    into v_ware_id, v_dd_id, v_clo_qty_need_to_reserve
    do begin
        insert into tmp$shopping_cart(
            id,
            snd_id, -- 22.09.2014: for handling qdistr in separate cursor wher storno_sub=2!
            snd_optype_id,
            rcv_optype_id,
            qty,
            storno_sub
        )
        values (
            :v_ware_id,
            :v_dd_id,
            :v_oper_invoice_add,
            :v_oper_retail_reserve,
            :v_clo_qty_need_to_reserve, -- :: NB :: this is the REST of initially ordered amount (i.e. LESS or equal to origin value in doc_data.qty for clo!)
            1
        );
        row_cnt = row_cnt + 1; -- out arg
        qty_sum = qty_sum + v_clo_qty_need_to_reserve; -- out arg
    end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'rc='||row_count );

    suspend; -- row_cnt, qty_sum

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'clo='||a_client_order_id,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_fill_shopping_cart_clo_res

-----------------------------------------

create or alter procedure sp_customer_reserve(
    a_client_order_id type of dm_idb default null,
    dbg integer default 0)
returns (
    doc_list_id type of dm_idb,
    client_order_id type of dm_idb,
    doc_data_id type of dm_idb,
    ware_id type of dm_idb,
    qty type of dm_qty,
    purchase type of dm_cost,
    retail type of dm_cost,
    qty_ord type of dm_qty,
    qty_avl type of dm_qty,
    qty_res type of dm_qty
)
as
    declare v_rows_added int;
    declare v_qty_sum dm_qty;
    declare v_dbkey dm_dbkey;
    declare v_agent_id type of dm_idb;
    declare v_raise_exc_on_nofind dm_sign;
    declare v_can_skip_order_clause dm_sign;
    declare v_find_using_desc_index dm_sign;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_this dm_dbobj = 'sp_customer_reserve';
begin

    -- Takes several wares, adds them into
    -- tmp$shopping_cart and and creates new document that reserves
    -- these wares for customer, in amount that is currently avaliable
    -- If parameter a_client_order_id is NOT_null then fill tmp$shopping_cart
    -- with wares from THAT client order rather than random choosen wares set
    -- Document 'customer_reserve' can appear in business chain in TWO places:
    -- 1) at the beginning (when customer comes to us and wants to buy some wares
    --    which we have just now);
    -- 2) after we accept invoice which has wares from client order - in that case
    --    we need to reserve wares for customer(s) as soon as possible and we do
    --    it in the same Tx with accepting invoice (==> this will be 'heavy' Tx).

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises exc`eption to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(
        1,
        v_this,
        null,
        iif( a_client_order_id is null, 'from avaliable remainders', 'for clo_id='||a_client_order_id )
    );

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    if ( a_client_order_id = -1 ) then -- create reserve from avaliable remainders
        a_client_order_id = null;
    else if ( a_client_order_id is null ) then
        begin
            v_raise_exc_on_nofind = 0;   -- do NOT raise exc if random seacrh will not find any record
            v_can_skip_order_clause = 0; -- do NOT skip `order by` clause in sp_get_random_id (if order by id DESC will be used!)
            v_find_using_desc_index = 0; -- 22.09.2014; befo: 1; -- use 'order by id DESC' (11.09.2014)
            -- First of all try to search among client_orders which have
            -- at least one row with NOT_fully reserved ware.
            -- Call sp_get_random_id with arg NOT to raise exc`eption if
            -- it will not found such documents:
            select id_selected
            from
                sp_get_random_id(
                    'v_random_find_clo_res',
                    'v_min_id_clo_res',
                    'v_max_id_clo_res',
                    :v_raise_exc_on_nofind,
                    :v_can_skip_order_clause,
                    :v_find_using_desc_index
                )
            into
                a_client_order_id;
        end

    v_qty_sum = 0;
    while (1=1) do begin -- ...............   m a i n   l o o p  .................
  
        delete from tmp$shopping_cart where 1=1;

        if (a_client_order_id is null) then -- 'common' reserve, NOT related to client order
        begin
            -- ######  R E S E R V E    A V A L I A B L E    W A R E S  #####
            execute procedure sp_fill_shopping_cart( fn_oper_retail_reserve() )
            returning_values v_rows_added, v_qty_sum;
            
            -- select customer, random:
            v_agent_id = fn_get_random_customer();
        end
        else begin -- reserve based on client order: scan its wares which still need to be reserved
        
            -- ##########   R E S E R V E    F O R    C L I E N T    O R D E R  ######
            
            select h.rdb$db_key, h.agent_id
            from doc_list h
            where h.id = :a_client_order_id
            into v_dbkey, v_agent_id;
            
            if (v_dbkey is null) then exception ex_no_doc_found_for_handling using('doc_list', :a_client_order_id);

            -- fill tmp$shopping_cart with client_order data
            -- (NB: sp_make_qty_storno will put in reserve only those amounts
            -- for which there are at least one row in qdistr, so we can put in
            -- tmp$shopp_cart ALL rows from client order and no filter them now):
            execute procedure sp_fill_shopping_cart_clo_res( :a_client_order_id )
            returning_values v_rows_added, v_qty_sum;

        end -- a_client_order_id order NOT null
  
        if (dbg=1) then leave;
    
        -- 1. Find rows in QDISTR (and silently try to LOCK them) which can provide required
        --    amounts in tmp$shopping_cart, in FIFO manner.
        -- 2. Perform "STORNING" of them (moves these rows from QDISTR to QSTORNED)
        -- 3. Create new document: header (doc_list) and detalization (doc_data).
        if ( v_qty_sum > 0 ) then
        begin
            execute procedure sp_make_qty_storno(
                fn_oper_retail_reserve()
                ,v_agent_id
                ,fn_doc_open_state()
                ,a_client_order_id
                ,v_rows_added
                ,v_qty_sum
            ) returning_values doc_list_id; -- out arg
        end
        leave;

    end -- while (1=1) -- ...............   m a i n   l o o p  .................

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, coalesce(doc_list_id,'<null>') );

    if ( dbg=4 ) then exit;

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);
    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if ( v_ibe = 1 ) then
        v_stt = 'select v.base_doc_id, v.doc_data_id, v.ware_id, v.qty,v.cost_purchase, v.cost_retail'
                ||',v.qty_ord ,v.qty_avl ,v.qty_res'
                ||' from v_doc_detailed v where v.doc_id = :x';
    else
        v_stt = 'select h.base_doc_id, d.id, d.ware_id, d.qty,d.cost_purchase, d.cost_retail'
                ||',null      ,null      ,null     '
                ||' from doc_data d join doc_list h on d.doc_id = h.id where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id )
    into
         client_order_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_ord
        ,qty_avl
        ,qty_res
    do
        suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^ -- sp_customer_reserve

--------------------------------------------------------------------------------

create or alter procedure sp_cancel_customer_reserve(
    a_selected_doc_id type of dm_idb default null,
    a_skip_lock_attempt dm_sign default 0 -- 1==> do NOT call sp_lock_selected_doc because this doc is already locked (see call from sp_cancel_adding_invoice)
)
returns (
    doc_list_id type of dm_idb, -- id of new created reserve doc
    client_order_id type of dm_idb, -- id of client order (if current reserve was created with link to it)
    doc_data_id type of dm_idb, -- id of created records in doc_data
    ware_id type of dm_idb, -- id of wares that we resevre for customer
    qty type of dm_qty, -- amount that we can reserve (not greater than invnt_saldo.qty_avl)
    purchase type of dm_cost, -- cost in purchasing prices
    retail type of dm_cost, -- cost in retailing prices
    qty_ord type of dm_qty, -- new value of corresp. row
    qty_avl type of dm_qty, -- new value of corresp. row
    qty_res type of dm_qty -- new value of corresp. row
) as
    declare v_linked_client_order type of dm_idb;
    declare v_stt varchar(255);
    declare v_ibe smallint;
    declare v_dummy bigint;
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
    declare v_this dm_dbobj = 'sp_cancel_customer_reserve';
begin

    -- Randomly chooses customer reserve (which is NOT yet sold) and CANCEL it
    -- by REMOVING all its data + record in docs header table. It occurs when
    -- we mistakenly created such reserve and now have to cancel this operation.
    -- All wares which were in such reserve will be enabled to be reserved for
    -- other customer - due to removing info about storning that was done before
    -- when this customer reserve was created.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            ( select id_selected from
                              sp_get_random_id(
                                'v_cancel_customer_reserve' -- a_view_for_search
                                ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                ,:c_raise_exc_when_no_found
                                ,:c_can_skip_order_clause
                                            )
                            )
                          );

    -- Try to LOCK just selected doc, raise exc if can`t:
    if (  NOT (a_selected_doc_id is NOT null and a_skip_lock_attempt = 1) ) then
        execute procedure sp_lock_selected_doc( doc_list_id, 'v_cancel_customer_reserve', a_selected_doc_id);

    select
        h.base_doc_id
    from doc_list h
    where
        h.id = :doc_list_id
    into
        v_linked_client_order; -- not null ==> this reserve was filled with wares from client order

    -- 17.07.2014: add cond for indexed scan to minimize fetches when multiple
    -- calls of this SP from sp_cancel_adding_invoice:
    delete from tmp$result_set r where r.doc_id = :doc_list_id;

    -- save data which is to be deleted (NB! this action became MANDATORY for
    -- checking in srv_find_qd_qs_mism, do NOT delete it!):
    insert into tmp$result_set(
        doc_id,
        base_doc_id,
        doc_data_id,
        ware_id,
        qty,
        cost_purchase,
        cost_retail
    )
    select
        :doc_list_id,
        :v_linked_client_order,
        d.id,
        d.ware_id,
        d.qty,
        d.cost_purchase,
        d.cost_retail
    from doc_data d
    where d.doc_id = :doc_list_id; -- customer reserve which is to be deleted now

    -- Remove selected customer reserve.
    -- Trigger d`oc_list_biud will (only for deleting doc or updating it's state):
    -- 1) call s`p_kill_qty_storno that returns rows from Q`Storned to Q`distr 
    -- Trigger d`oc_list_aiud will:
    -- 1) add rows in table i`nvnt_turnover_log (log to be processed by SP s`rv_make_invnt_saldo)
    -- 2) call s`p_multiply_rows_for_pdistr, s`p_make_cost_storno or s`p_kill_cost_storno, s`p_add_money_log
    delete from doc_list h where h.id = :doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||doc_list_id);

    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    v_stt = 'select r.doc_id,r.base_doc_id,r.doc_data_id,r.ware_id,r.qty,r.cost_purchase,r.cost_retail';
    if ( v_ibe = 1 ) then
       v_stt = v_stt || ' ,n.qty_ord,       n.qty_avl,       n.qty_res';
    else
       v_stt = v_stt || ' ,null as qty_ord, null as qty_avl, null as qty_res';

    v_stt = v_stt ||' from tmp$result_set r';
    if ( v_ibe = 1 ) then
       v_stt = v_stt || ' left join v_saldo_invnt n on r.ware_id = n.ware_id';

    -- 17.07.2014: add cond for indexed scan to minimize fetches when multiple
    -- calls of this SP from sp_cancel_adding_invoice:
    v_stt = v_stt || ' where r.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id)
    into
        doc_list_id
        ,client_order_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_ord
        ,qty_avl
        ,qty_res
    do
        suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^ -- sp_cancel_customer_reserve

-----------------------------------------

create or alter procedure sp_cancel_write_off(
    a_selected_doc_id type of dm_idb default null,
    a_skip_lock_attempt dm_sign default 0 -- 1==> do NOT call sp_lock_selected_doc because this doc is already locked (see call from sp_cancel_adding_invoice)
)
returns (
    doc_list_id type of dm_idb, -- id of invoice being added to stock
    client_order_id type of dm_idb, -- id of client order (if current reserve was created with link to it)
    doc_data_id type of dm_idb, -- id of created records in doc_data
    ware_id type of dm_idb, -- id of wares that we will get from supplier
    qty type of dm_qty,
    purchase type of dm_cost,
    retail type of dm_cost,
    qty_avl type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_res type of dm_qty,  -- new value of corresponding row in invnt_saldo
    qty_out type of dm_qty  -- new value of corresponding row in invnt_saldo
)
as
    declare v_dummy bigint;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_agent_id type of dm_idb;
    declare v_linked_client_order type of dm_idb;
    declare v_this dm_dbobj = 'sp_cancel_write_off';
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
begin

    -- Randomly chooses waybill (ex. customer reserve after it was sold) and
    -- MOVES ("returns") it back to state "customer reserve" thus cancelling
    -- write-off operation that was previously done with these wares.
    -- All wares which were in such waybill will be returned back on stock and
    -- will be reported as 'reserved'. So, we only change the STATE of document
    -- rather its content.
    -- Total cost of realization will be added (INSERTED) into money_turnover_log table
    -- with "-" sign to be gathered later in service sp_make_money_saldo
    -- that calculates balance of contragents.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);

    -- Choose random doc of corresponding kind ("closed" customer reserve)
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            ( select id_selected from
                              sp_get_random_id(
                                'v_cancel_write_off' -- a_view_for_search
                                ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                ,:c_raise_exc_when_no_found
                                ,:c_can_skip_order_clause
                                              )
                            )
                          );

    -- Try to LOCK just selected doc, raise exc if can`t:
    if (  NOT (a_selected_doc_id is NOT null and a_skip_lock_attempt = 1) ) then
        execute procedure sp_lock_selected_doc( doc_list_id, 'v_cancel_write_off', a_selected_doc_id);

    -- Change STATE of document back to "Reserve".
    -- Trigger doc_list_biud will (only for deleting doc or updating it's state):
    -- 1) call s`p_kill_qty_storno that returns rows from Q`Storned to Q`distr 
    -- Trigger doc_list_aiud will:
    -- 1) add rows in table i`nvnt_turnover_log (log to be processed by SP s`rv_make_invnt_saldo)
    -- 2) call s`p_multiply_rows_for_pdistr, s`p_make_cost_storno or s`p_kill_cost_storno, s`p_add_money_log
    update doc_list h
    set
        h.state_id = fn_doc_open_state(), -- return to prev. docstate
        h.optype_id = fn_oper_retail_reserve(), -- return to prev. optype
        dts_fix = null,
        dts_clos = null
    where
        h.id = :doc_list_id
    returning
        h.base_doc_id
    into
        client_order_id; -- out arg

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||doc_list_id);

    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    v_stt = 'select d.doc_id, d.ware_id, d.qty, d.cost_purchase, d.cost_retail';
    if ( v_ibe = 1 ) then
       v_stt = v_stt || ',d.doc_data_id ,d.qty_avl ,d.qty_res  ,d.qty_out from v_doc_detailed d';
    else
       v_stt = v_stt || ',d.id         ,null      ,null       ,null      from doc_data d';

    v_stt = v_stt || ' where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id )
    into
        doc_list_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,doc_data_id
        ,qty_avl
        ,qty_res
        ,qty_out
    do
        suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_cancel_write_off

-------------------------------------------------------------------------------

create or alter procedure sp_get_clo_for_invoice( a_invoice_doc_id dm_idb )
returns (
    clo_doc_id type of dm_idb,
    clo_agent_id type of dm_idb -- 23.07.2014
)
as
    declare v_dbkey dm_dbkey;
    declare v_qty_acc dm_qty;
    declare v_qty_sup type of dm_qty;
    declare v_snd_qty dm_qty;
    declare v_qty_clo_still_not_reserved dm_qty;
    declare v_clo_doc_id dm_idb;
    declare v_clo_agent_id dm_idb;
    declare v_ware_id dm_idb;
    declare v_cnt int = 0;
    declare v_this dm_dbobj = 'sp_get_clo_for_invoice';
    declare v_oper_order_by_customer dm_idb;
    declare v_oper_retail_reserve dm_idb;
begin

    -- Aux SP: find client orders which have at least one unit of amount of
    -- some ware that still not reserved for customer.
    -- This SP is called when we finish checking invoice data and move invoice
    -- to state "Accepted". We need then find for immediate RESERVING such
    -- wares which customers waiting for.

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    --?! 06.02.2015 2020, performance affect ?
    v_oper_order_by_customer =  fn_oper_order_by_customer();
    v_oper_retail_reserve = fn_oper_retail_reserve();

    delete from tmp$dep_docs d where d.base_doc_id = :a_invoice_doc_id;

    -- :: NB :: We need handle rows via CURSOR here because of immediate leave
    -- from cursor when limit (invoice doc_data.qty as v_qty_sup) will be exceeded
    -- FB 3.0 analitycal function sum()over(order by) which get running total
    -- is inefficient here (poor performance)
    for
        select d.ware_id, d.qty
        from doc_data d
        where d.doc_id = :a_invoice_doc_id -- invoice which we are closing now
        into v_ware_id, v_qty_sup
    do begin
        v_qty_acc = 0;

        -- Gather REMAINDER of initial amount in ALL client orders
        -- that still not yet reserved.
        -- 05.09.2015. Note: we have to stop scrolling on QDistr for each ware
        -- from invoice as soon as number of scrolled records will be >= v_qty_sup
        -- (because we can`t put in reserve more than we got from supplier;
        -- also because of performance: there are usially **LOT** of rows in QDistr
        -- for the same value of {ware, snd_op, rcv_op})
        for
        select
            q.doc_id as clo_doc_id, -- id of customer order
            q.snd_qty as clo_qty -- always = 1 (in current implementation)
        from v_qdistr_source q
        where
            -- :: NB :: PARTIAL match on index range scan will be here.
            -- For that reason we have to STOP scrolling as soon as possible!
            q.ware_id = :v_ware_id
            and q.snd_optype_id = :v_oper_order_by_customer
            and q.rcv_optype_id = :v_oper_retail_reserve
            and not exists(
                select * from tmp$dep_docs t
                where
                    t.base_doc_id = :a_invoice_doc_id
                    and t.dependend_doc_id = q.doc_id
                -- prevent from building index bitmap (has effect only in 3.0; do NOT repeat in 2.5!):
                order by t.base_doc_id, t.dependend_doc_id
            )
        order by q.ware_id, q.snd_optype_id, q.rcv_optype_id, q.snd_id -- ==> 3.0: plan_order, avoid bild bitmap
        into v_clo_doc_id, v_snd_qty
        do begin
            v_qty_acc = v_qty_acc + v_snd_qty;
            v_cnt = v_cnt + 1;

            update or insert into tmp$dep_docs(
                base_doc_id,
                dependend_doc_id)
            values (
                :a_invoice_doc_id,
                :v_clo_doc_id)
            matching(base_doc_id, dependend_doc_id);

            if ( v_qty_acc >= v_qty_sup ) then leave; -- we can`t put in reserve more than we got from supplier
        when any do -- added 10.09.2014: strange 'concurrent transaction' error occured on GTT!
            -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
            -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
            -- catched it's kind of exception!
            -- 1) tracker.firebirdsql.org/browse/CORE-3275
            --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
            -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
            begin
                if ( NOT fn_is_uniqueness_trouble(gdscode) ) then exception;
            end
        end

    end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||a_invoice_doc_id||', gather_qd_rows='||v_cnt);

    for
        select f.dependend_doc_id, h.agent_id
        from tmp$dep_docs f
        join doc_list h on
                f.dependend_doc_id = h.id
                and h.optype_id = :v_oper_order_by_customer -- 31.07.2014: exclude cancelled customer orders!
        where f.base_doc_id = :a_invoice_doc_id
        -- not needed! >>> group by f.dependend_doc_id, h.agent_id
        into clo_doc_id, clo_agent_id
    do
        suspend;

when any do  -- added 10.09.2014: strange 'concurrent transaction' error occured on INSERT!
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(a_invoice_doc_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end


^  -- sp_get_clo_for_invoice

-------------------------------------------------------------------------------

create or alter procedure sp_add_invoice_to_stock(
    a_selected_doc_id type of dm_idb default null,
    a_cancel_mode dm_sign default 0,
    a_skip_lock_attempt dm_sign default 0, -- 1==> do NOT call sp_lock_selected_doc because this doc is already locked (see call from s`p_cancel_supplier_order)
    dbg int default 0
)
returns (
    doc_list_id type of dm_idb, -- id of invoice being added to stock
    agent_id type of dm_idb, -- id of supplier
    doc_data_id type of dm_idb, -- id of created records in doc_data
    ware_id type of dm_idb, -- id of wares that we will get from supplier
    qty type of dm_qty, -- amount that supplier will send to us
    purchase type of dm_cost, -- how much we must pay to supplier for this ware
    qty_sup type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_avl type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_res type of dm_qty,  -- new value of corresponding row in invnt_saldo
    res_ok int, -- number of successfully created reserves for client orders
    res_err int, -- number of FAULTS when attempts to create reserves for client orders
    res_nul int -- 4debug: number of mismatches between estimated and actually created reserves
)
as
    declare v_dummy bigint;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_info dm_info;
    declare v_new_doc_state type of dm_idb;
    declare v_old_oper_id type of dm_idb;
    declare v_new_oper_id type of dm_idb;
    declare v_client_order type of dm_idb;
    declare v_linked_reserve_id type of dm_idb;
    declare v_linked_reserve_state type of dm_idb;
    declare v_view_for_search dm_dbobj;
    declare v_this dm_dbobj = 'sp_add_invoice_to_stock';
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;

    declare function fn_internal_enable_reserving() returns boolean deterministic as
    begin
      return rdb$get_context('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE')='1';
    end

begin

    -- This SP implements TWO tasks (see parameter `a_cancel_mode`):
    -- 1) MOVES invoice to the state "ACCEPTED" after we check its content;
    -- 2) CANCEL previously accepted invoice and MOVES it to the state "TO BE CHECKED".
    -- For "1)" it will also find all client orders which have at least one unit
    -- of amount that still not reserved and CREATE customer reserve(s).
    -- Total cost of invoice will be added (INSERTED) into money_turnover_log table
    -- with "+" sign to be gathered later in service sp_make_money_saldo that
    -- calculates balance of contragents.
    -- For "2)" it will find all customer reserves and waybills ('closed reserves')
    -- and firstly CANCEL all of them and, if no errors occur, will then cancel
    -- currently selected invoice.
    -- Total cost of cancelled invoice will be added (INSERTED) into money_turnover_log table
    -- with "-" sign to be gathered later in service sp_make_money_saldo that
    -- calculates balance of contragents.
    -- ::: NB-1 ::: This SP supresses lock-conflicts which can be occur when trying
    -- to CREATE customer reserves in module sp_make_qty_storno which storning amounts.
    -- In such case amount will be stored in 'avaliable' remainder.
    -- ::: NB-2 ::: This SP does NOT supress lock-conflicts when invoice is to be
    -- CANCELLED (i.e. moved back to state 'to be checked') - otherwise we get
    -- negative values in 'reserved' or 'sold' kinds of stock remainder.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- input arg a_cancel_mode = 0 ==> ADD invoice to stock and 'fix' it;
    --                   otherwise ==> CANCEL adding and return to 'open' state
    ----------------------------------------------------------------------------
    -- add to performance log timestamp about start/finish this unit:
    if ( a_cancel_mode = 1 ) then v_this = 'sp_cancel_adding_invoice';

    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    -- check that special context var EXISTS otherwise raise exc:
    execute procedure sp_check_ctx('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE');
    
    v_new_doc_state = iif( a_cancel_mode = 0, fn_doc_fix_state(),  fn_doc_open_state() );
    v_old_oper_id = iif( a_cancel_mode = 0, fn_oper_invoice_get(), fn_oper_invoice_add() );
    v_new_oper_id = iif( a_cancel_mode = 0, fn_oper_invoice_add(), fn_oper_invoice_get() );
    v_view_for_search = iif( a_cancel_mode = 0, 'v_add_invoice_to_stock', 'v_cancel_adding_invoice' );
    
    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            (select id_selected
                             from sp_get_random_id( :v_view_for_search -- a_view_for_search
                                                    ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                                    ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                                    ,:c_raise_exc_when_no_found
                                                    ,:c_can_skip_order_clause
                                                  )
                            )
                          );


    execute procedure sp_upd_in_perf_log(v_this, null, 'doc_id='||doc_list_id); -- 06.07.2014, 4debug

    -- Try to LOCK just selected doc, raise exc if can`t:
    if (  NOT (a_selected_doc_id is NOT null and a_skip_lock_attempt = 1) ) then
        execute procedure sp_lock_selected_doc( doc_list_id, v_view_for_search, a_selected_doc_id);

    res_ok = 0;
    res_err = 0;
    res_nul = 0;

    while (1=1) do begin -- ................  m a i n    l o o p   ...............

        if ( a_cancel_mode = 1 ) then
        begin
            -- search all RESERVES (including those that are written-off) which
            -- stornes some amounts from currently selected invoice and lock them
            -- (add to tmp$dep_docs.dependend_doc_id)
            execute procedure sp_lock_dependent_docs( :doc_list_id, :v_old_oper_id );
            -- result: tmp$dep_docs.dependend_doc_id filled by ID of all locked
            -- RESERVES which depends on currently selected invoice.
            -- Extract set of reserve docs that storned amounts from current
            -- invoice and cancel them:
            for
                select d.dependend_doc_id, d.dependend_doc_state
                from tmp$dep_docs d
                where d.base_doc_id = :doc_list_id
            into
                v_linked_reserve_id, v_linked_reserve_state
            do begin
                -- if we are here then ALL dependend docs have been SUCCESSFULLY locked.
                if ( v_linked_reserve_state <> fn_doc_open_state() ) then
                    select count(*) from sp_cancel_write_off( :v_linked_reserve_id, 1 ) into v_dummy;

                select count(*) from sp_cancel_customer_reserve(:v_linked_reserve_id, 1 ) into v_dummy;

                res_ok = res_ok + 1;

                -- do NOT supress any lock_conflict ex`ception here
                -- otherwise get negative remainders!

            end
        end -- block for CANCELLING mode

        -- Change info in doc header for INVOICE.
        -- 1. trigger d`oc_list_biud will call sp_kill_qty_storno which:
        --    update qdistr.snd_optype_id (or rcv_optype_id)
        --    where qd.snd_id = doc_data.id or qd.rcv_id = doc_data.id
        -- 2. trigger d`oc_list_aiud will:
        -- 2.1 add rows into invnt_turnover_log
        -- 2.2 add rows into money_turnover_log
        update doc_list h
        set h.optype_id = :v_new_oper_id,  -- iif( a_cancel_mode = 0, fn_oper_invoice_add(), fn_oper_invoice_get() );
            h.state_id = :v_new_doc_state, -- iif( :a_cancel_mode = 0 , :fn_doc_clos_state , :v_new_doc_state),
            dts_fix = iif( :a_cancel_mode = 0, 'now', null )
        where h.id = :doc_list_id;

        if (dbg=1) then leave;

        -- build unique list of client orders which still need to reserve some wares
        -- and create for each item of this list new reserve that is linked to client_order.
        v_client_order = null;
        if (a_cancel_mode = 0) then  -- create reserve docs (avaliable remainders exists after adding this invoice)
        begin
        
            if (dbg=3) then leave;

            if (fn_internal_enable_reserving() ) then
            begin
                for
                    select p.clo_doc_id
                    from sp_get_clo_for_invoice( :doc_list_id  ) p
                    where not exists(
                        select * from v_our_firm v
                        where v.id = p.clo_agent_id
                        -- 3.0: fixed 16.12.2014, revision 60368
                        -- "Postfix for CORE-1550 Unnecessary index scan happens
                        --- when the same index is mapped to both WHERE and ORDER BY clauses."
                        order by v.id -- <<< can do this since 16.12.2014
                    )
                    into v_client_order
                do begin
                    -- reserve immediatelly all avaliable wares for each found client order:
                    select min(doc_list_id) from sp_customer_reserve( :v_client_order, iif(:dbg=4, 2, null) )
                    into v_linked_reserve_id;

                    if (  v_linked_reserve_id is null ) then
                        res_nul = res_nul + 1;
                    else
                        res_ok = res_ok + 1;

                when any do
                    -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
                    -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
                    -- catched it's kind of exception!
                    -- 1) tracker.firebirdsql.org/browse/CORE-3275
                    --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
                    -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
                    begin
                        if ( fn_is_lock_trouble(gdscode) ) then
                            begin
                                execute procedure sp_add_to_abend_log(
                                    'can`t create res',
                                    gdscode,
                                    'clo_id='||coalesce(v_client_order, '<null>'),
                                    v_this
                                );
                                res_err = res_err + 1;
                            end
                        else
                            begin
                                execute procedure sp_add_to_abend_log('', gdscode, 'doc_id='||doc_list_id, v_this );
                                --########
                                exception;  -- ::: nb ::: anonimous but in when-block!
                            end
                    end
                end -- cursor select clo_doc_id from sp_get_clo_for_invoice( :doc_list_id  )
            end -- ENABLE_RESERVES_WHEN_ADD_INVOICE ==> '1'
        end -- a_cancel_mode = 0
        leave;
    end -- while (1=1)  -- ................  m a i n    l o o p   ...............

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'dh='||doc_list_id, res_ok, res_nul);

    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if (  v_ibe = 1 ) then
        v_stt = 'select v.agent_id, v.doc_data_id, v.ware_id, v.qty, v.cost_purchase, v.qty_sup, v.qty_avl, v.qty_res'
                ||' from v_doc_detailed v where v.doc_id = :x';
    else
        v_stt = 'select h.agent_id, d.id,          d.ware_id, d.qty, d.cost_purchase, null,     null,       null '
                ||' from doc_data d join doc_list h on d.doc_id = h.id where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id )
     into
         agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,qty_sup
        ,qty_avl
        ,qty_res
    do
    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^ -- end of sp_add_invoice_to_stock

create or alter procedure sp_cancel_adding_invoice(
    a_selected_doc_id type of dm_idb default null,
    a_skip_lock_attempt dm_sign default 0, -- 1==> do NOT call sp_lock_selected_doc because this doc is already locked (see call from s`p_cancel_supplier_order)
    dbg int default 0
)
returns (
    doc_list_id type of dm_idb, -- id of invoice being added to stock
    agent_id type of dm_idb, -- id of supplier
    doc_data_id type of dm_idb, -- id of created records in doc_data
    ware_id type of dm_idb, -- id of wares that we will get from supplier
    qty type of dm_qty, -- amount that supplier will send to us
    purchase type of dm_cost, -- how much we must pay to supplier for this ware
    qty_sup type of dm_qty, -- new value of corresponding row in invnt
    qty_avl type of dm_qty, -- new value of corresponding row in invnt
    qty_res type of dm_qty,  -- new value of corresponding row in invnt_saldo
    res_ok int, -- number of successfully CANCELLED reserves for client orders
    res_err int -- number of FAULTS when attempts to CANCEL reserves for client orders
)
as
    declare v_dummy bigint;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_this dm_dbobj = 'sp_cancel_adding_invoice';
begin

    -- MOVES invoice from state 'accepted' to state 'to be checked'.
    -- Delegates all this work to sp_add_invoice_to_stock.

    -- add to performance log timestamp about start/finish this unit:
    -- no need, see s`p_add_invoice:    execute procedure s`p_add_to_perf_log(v_this);

    select min(doc_list_id), min(res_ok), min(res_err)
    from sp_add_invoice_to_stock(
             :a_selected_doc_id,
             1, -- <<<<<<<<< sign to CANCEL document <<<<<
             :a_skip_lock_attempt,
             :dbg
         )
    into doc_list_id, res_ok, res_err;

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);

    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if ( v_ibe = 1 ) then
        v_stt = 'select v.agent_id, v.doc_data_id, v.ware_id, v.qty, v.cost_purchase, v.qty_sup, v.qty_avl, v.qty_res'
                ||' from v_doc_detailed v where v.doc_id = :x';
    else
        v_stt = 'select h.agent_id, d.id,          d.ware_id, d.qty, d.cost_purchase, null,      null,      null'
                ||' from doc_data d join doc_list h on d.doc_id = h.id where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id )
    into
         agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,qty_sup
        ,qty_avl
        ,qty_res
    do
        suspend;

    -- add to performance log timestamp about start/finish this unit:
    -- no need, see s`p_add_invoice:    execute procedure s`p_add_to_perf_log(v_this, null, 'doc_id='||doc_list_id);
when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end -- sp_cancel_adding_invoice

^
--------------------------------------------------------------------------------

create or alter procedure sp_cancel_supplier_order(
    a_selected_doc_id type of dm_idb default null)
returns (
    doc_list_id type of dm_idb,
    agent_id type of dm_idb,
    doc_data_id type of dm_idb,
    ware_id type of dm_idb,
    qty type of dm_qty, -- amount that we ordered for client
    purchase type of dm_cost, -- purchasing cost for qty
    retail type of dm_cost, -- retail cost
    qty_clo type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_ord type of dm_qty -- new value of corresponding row in invnt_saldo
)
as
    declare v_dummy bigint;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_info dm_info = '';
    declare v_linked_invoice_id bigint;
    declare v_linked_invoice_state bigint;
    declare v_linked_reserve_id bigint;
    declare v_linked_reserve_state bigint;
    declare v_this dm_dbobj = 'sp_cancel_supplier_order';
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
begin

    -- Randomly chooses our order to supplier and CANCEL it by REMOVING all its
    -- data + record in docs header table. It occurs when we mistakenly created
    -- such order and now have to cancel this operation.
    -- All wares which were in such supplier order will be enabled again
    -- to be included in new (another) order which we create after this.
    -- ::: NB :::
    -- Before cancelling supplier order we need to find all INVOICES which have
    -- at least one unit of amounts that was participated in storning process of
    -- currently selected order. All these invoices need to be:
    -- 1) moved from state 'accepted' to state 'to be checked' (if need);
    -- 2) cancelled at all (i.e. removed from database).
    -- Because each 'accepted' invoice can be cancelled only when all customer
    -- reserves and waybills are cancelled first, we need, in turn, to find all
    -- these documents and cancel+remove them.
    -- For that reason this SP is most 'heavy' vs any others: it can fail with
    -- 'lock-conflict' up to 75% of calls in concurrent environment.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            (select id_selected from
                              sp_get_random_id( 'v_cancel_supplier_order' -- a_view_for_search
                                                ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                                ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                                ,:c_raise_exc_when_no_found
                                                ,:c_can_skip_order_clause
                                              )
                            )
                          );
    v_info = 'dh='||doc_list_id;
    -- upd. log with doc id whic is actually handling now:
    --execute procedure sp_upd_in_perf_log( v_this, null, 'dh='||doc_list_id);

    -- Try to LOCK just selected doc, raise exc if can`t:
    execute procedure sp_lock_selected_doc( doc_list_id, 'v_cancel_supplier_order', a_selected_doc_id);

    -- Since 08.08.2014: first get and lock *ALL* dependent docs - both invoices and reserves
    -- Continue handling of them only after we get ALL locks!
    -- 1. lock all INVOICES that storned amounts from currently selected supp_order:
    execute procedure sp_lock_dependent_docs( :doc_list_id, fn_oper_order_for_supplier() );
    -- result: tmp$dep_docs.dependend_doc_id filled by ID of all locked dependent invoices

    -- 2. for each of invoices search all RESERVES (including those that are written-off)
    -- and also lock them (add to tmp$dep_docs.dependend_doc_id)
    for
        select
            d.dependend_doc_id as linked_invoice_id
        from tmp$dep_docs d
        where d.base_doc_id = :doc_list_id
        order by d.base_doc_id+0
        into v_linked_invoice_id
    do begin
        execute procedure sp_lock_dependent_docs(:v_linked_invoice_id, fn_oper_invoice_add());
    end
    -- result: tmp$dep_docs.dependend_doc_id filled by ID of all locked RESERVES
    -- which depends on invoices.

    -- 3. Scan tmp$dep_docs filtering only RESERVES and cancel them
    -- (do NOT delegate this job to sp_cancel_adding_invoice...)
    for
        select d.dependend_doc_id, d.dependend_doc_state
        from tmp$dep_docs d
        where d.base_doc_id <> :doc_list_id
        group by 1,2 -- ::: NB ::: one reserve can depends on SEVERAL invoices!
        into v_linked_reserve_id, v_linked_reserve_state
    do begin
        if ( v_linked_reserve_state <> fn_doc_open_state() ) then
            -- a_skip_lock_hdr = 1  ==> do NOT try to lock doc header, it was ALREADY locked in sp_lock_dependent_docs
            select count(*) from sp_cancel_write_off( :v_linked_reserve_id, 1 ) into v_dummy;

        -- a_skip_lock_hdr = 1  ==> do NOT try to lock doc header, it was ALREADY locked in sp_lock_dependent_docs
        select count(*) from sp_cancel_customer_reserve(:v_linked_reserve_id, 1 ) into v_dummy;

        -- do NOT supress any lock_conflict ex`ception here
        -- otherwise get negative remainders!
    end

    -- 4. Scan tmp$dep_docs filtering only INVOICES and cancel them:
    for
        select d.dependend_doc_id, d.dependend_doc_state
        from tmp$dep_docs d
        where d.base_doc_id = :doc_list_id
        into v_linked_invoice_id, v_linked_invoice_state
    do begin
        if ( v_linked_invoice_state <> fn_doc_open_state() ) then
            -- a_skip_lock_hdr = 1  ==> do NOT try to lock doc header, it was ALREADY locked in sp_lock_dependent_docs
            select count(*) from sp_cancel_adding_invoice( :v_linked_invoice_id, 1 ) into v_dummy;

        -- a_skip_lock_hdr = 1  ==> do NOT try to lock doc header, it was ALREADY locked in sp_lock_dependent_docs
        select count(*) from sp_cancel_supplier_invoice( :v_linked_invoice_id, 1 ) into v_dummy;

        -- do NOT supress any lock_conflict ex`ception here
        -- otherwise get negative remainders!

    end

    -- 17.07.2014: add cond for indexed scan to minimize fetches:
    delete from tmp$result_set r where r.doc_id = :doc_list_id;

    -- save data which is to be deleted (NB! this action became MANDATORY for
    -- checking in srv_find_qd_qs_mism, do NOT delete it!):
    insert into tmp$result_set( doc_id, agent_id, doc_data_id, ware_id, qty, cost_purchase, cost_retail)
    select
        :doc_list_id,
        h.agent_id,
        d.id,
        d.ware_id,
        d.qty,
        d.cost_purchase,
        d.cost_retail
    from doc_data d
    join doc_list h on d.doc_id = h.id
    where d.doc_id = :doc_list_id; -- supplier order which is to be removed now

    -- 1. Trigger doc_list_biud will (only for deleting doc or updating it's state)
    -- call s`p_kill_qty_storno that returns rows from Q`Storned to Q`distr.
    -- 2. FK cascade will remove records from table doc_data.
    -- 3. Trigger doc_list_aiud will:
    -- 3.1) add rows in table i`nvnt_turnover_log (log to be processed by SP s`rv_make_invnt_saldo)
    -- 3.2) call s`p_multiply_rows_for_pdistr, s`p_make_cost_storno or s`p_kill_cost_storno, s`p_add_money_log
    delete from doc_list h where h.id = :doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this,null, v_info);

    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    v_stt = 'select r.agent_id,r.doc_data_id,r.ware_id,r.qty,r.cost_purchase,r.cost_retail';
    if ( v_ibe = 1 ) then
        v_stt = v_stt ||' ,n.qty_clo,n.qty_ord'
                      ||' from tmp$result_set r left join v_saldo_invnt n on r.ware_id = n.ware_id';
    else
        v_stt = v_stt ||' ,null     ,null from tmp$result_set r';

    -- 17.07.2014: add cond for indexed scan to minimize fetches:
    v_stt = v_stt || ' where r.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id )
    into
         agent_id
        ,doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_clo
        ,qty_ord
    do
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
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );
        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_cancel_supplier_order

--------------------------------------------------------------------------------

create or alter procedure sp_reserve_write_off(a_selected_doc_id type of dm_idb default null)
returns (
    doc_list_id type of dm_idb, -- id of customer reserve doc
    client_order_id type of dm_idb, -- id of client order (if current reserve was created with link to it)
    doc_data_id type of dm_idb, -- id of processed records in doc_data
    ware_id type of dm_idb, -- id of ware
    qty type of dm_qty, -- amount that is written-offf
    purchase type of dm_cost, -- cost in purchasing prices
    retail  type of dm_cost, -- cost in retailing prices
    qty_avl type of dm_qty, -- new value of corresponding row in invnt_saldo
    qty_res type of dm_qty,  -- new value of corresponding row in invnt_saldo
    qty_out type of dm_qty  -- new value of corresponding row in invnt_saldo
)
as
    declare v_linked_client_order type of dm_idb;
    declare v_ibe smallint;
    declare v_stt varchar(255);
    declare v_dummy bigint;
    declare v_this dm_dbobj = 'sp_reserve_write_off';
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
begin

    -- Randomly choose customer reserve and MOVES it to the state 'sold',
    -- so this doc becomes 'waybill' (customer can take out his wares since
    -- that moment).
    -- Total cost of realization will be added (INSERTED) into money_turnover_log table
    -- with "+" sign to be gathered later in service sp_make_money_saldo
    -- that calculates balance of contragents.

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    v_ibe = iif( fn_remote_process() containing 'IBExpert', 1, 0);

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            (select id_selected from
                             sp_get_random_id( 'v_reserve_write_off' -- a_view_for_search
                                              ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                              ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                              ,:c_raise_exc_when_no_found
                                              ,:c_can_skip_order_clause
                                            )
                            )
                          );

    -- Try to LOCK just selected doc, raise exc if can`t:
    execute procedure sp_lock_selected_doc( doc_list_id, 'v_reserve_write_off', a_selected_doc_id);

    -- Change info in doc header for CUSTOMER RESERVE.
    -- 1. Trigger doc_list_biud will (only for deleting doc or updating it's state)
    -- call s`p_kill_qty_storno that returns rows from Q`Storned to Q`distr.
    -- 2. FK cascade will remove records from table doc_data.
    -- 3. Trigger doc_list_aiud will:
    -- 3.1) add rows in table i`nvnt_turnover_log (log to be processed by SP s`rv_make_invnt_saldo)
    -- 3.2) call s`p_multiply_rows_for_pdistr, s`p_make_cost_storno or s`p_kill_cost_storno, s`p_add_money_log
    update doc_list h
    set
        h.state_id = fn_doc_fix_state(), -- goto "next" docstate: 'waybill'
        h.optype_id = fn_oper_retail_realization() -- goto "next" optype ==> add row to money_turnover_log
    where h.id = :doc_list_id
    returning h.base_doc_id
    into client_order_id; -- out arg

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||doc_list_id);

    -- 16.07.2014: make ES more 'smart': we do NOT need any records from view
    -- v_doc_detailed (==> v_saldo_invnt!) if there is NO debug now (performance!)
    if ( v_ibe = 1 ) then
        v_stt = 'select v.doc_data_id,v.ware_id,v.qty,v.cost_purchase,v.cost_retail'
                ||',v.qty_avl,v.qty_res,v.qty_out'
                ||' from v_doc_detailed v where v.doc_id = :x';
    else
        v_stt = 'select d.id,d.ware_id,d.qty,d.cost_purchase,d.cost_retail'
                ||',null     ,null     ,null'
                ||' from doc_data d where d.doc_id = :x';

    -- final resultset (need only in IBE, for debug purposes):
    for
        execute statement (v_stt) ( x := :doc_list_id )
    into
         doc_data_id
        ,ware_id
        ,qty
        ,purchase
        ,retail
        ,qty_avl
        ,qty_res
        ,qty_out
    do
        suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end -- sp_reserve_write_off

^
-------------------------------------------------------------------------------
-- ###########################  P A Y M E N T S  ##############################
-------------------------------------------------------------------------------

create or alter procedure sp_payment_common(
    a_payment_oper dm_idb, -- fn_oper_pay_from_customer() or  fn_oper_pay_to_supplier()
    a_selected_doc_id type of dm_idb default null,
    a_total_pay type of dm_cost default null
)
returns (
    source_doc_id type of dm_idb, -- id of doc which is paid (reserve or invoice)
    agent_id type of dm_idb,
    current_pay_sum type of dm_cost
)
as
    declare v_stt varchar(255);
    declare v_source_for_random_id dm_dbobj;
    declare v_source_for_min_id dm_dbobj;
    declare v_source_for_max_id dm_dbobj;
    declare v_can_skip_order_clause smallint;
    declare v_find_using_desc_index dm_sign;
    declare view_to_search_agent dm_dbobj;
    declare v_non_paid_total type of dm_cost;
    declare v_round_to smallint;
    declare v_id bigint;
    declare v_dummy bigint;
    declare v_this dm_dbobj = 'sp_payment_common';
begin

    -- Aux SP - common for both payments from customers and our payments
    -- to suppliers.
    -- If parameter `a_selected_doc_id` is NOT null than we create payment
    -- that is LINKED to existent doc of realization (for customer) or incomings
    -- (for supplier). Otherwise this is ADVANCE payment.
    -- This SP tries firstly to find 'linked' document for payment an returns it
    -- in out argument 'source_doc_id' if it was found. Otherwise it only randomly
    -- choose agent + total cost of payment and return them.

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this,null);

    -- added 09.09.2014 due to new views for getting bounds & random find:
    v_source_for_random_id =
        decode( a_payment_oper,
                fn_oper_pay_from_customer(), 'v_random_find_non_paid_realizn',
                fn_oper_pay_to_supplier(),   'v_random_find_non_paid_invoice',
                'unknown_source'
              );

    v_source_for_min_id =
        decode( a_payment_oper,
                fn_oper_pay_from_customer(), 'v_min_non_paid_realizn',
                fn_oper_pay_to_supplier(),   'v_min_non_paid_invoice',
                null
              );

    v_source_for_max_id =
        decode( a_payment_oper,
                fn_oper_pay_from_customer(), 'v_max_non_paid_realizn',
                fn_oper_pay_to_supplier(),   'v_max_non_paid_invoice',
                null
              );

    v_can_skip_order_clause =
        decode( a_payment_oper,
                fn_oper_pay_from_customer(), 1,
                fn_oper_pay_to_supplier(),   1,
                0
              );
    v_find_using_desc_index =
        decode( a_payment_oper,
                fn_oper_pay_from_customer(), 1,
                fn_oper_pay_to_supplier(),   1,
                0
              );

    view_to_search_agent = iif( a_payment_oper = fn_oper_pay_from_customer(), 'v_all_customers', 'v_all_suppliers');
    v_round_to = iif( a_payment_oper = fn_oper_pay_from_customer(), -2, -3);

    if ( :a_selected_doc_id is null ) then
        begin
            select id_selected
            from sp_get_random_id(
                                   :v_source_for_random_id,
                                   :v_source_for_min_id,
                                   :v_source_for_max_id,
                                   0, -- 19.07.2014: 0 ==> do NOT raise exception if not able to find any ID in view :v_source_for_random_id
                                   :v_can_skip_order_clause, -- 17.07.2014: if = 1, then 'order by id' will be SKIPPED in statement inside fn
                                   :v_find_using_desc_index -- 11.09.2014
                                 )
            into source_doc_id;
            if ( source_doc_id is not null ) then
            begin
                select agent_id from doc_list h where h.id = :source_doc_id into agent_id;
            end
        end
    else
        select :a_selected_doc_id, h.agent_id
        from doc_list h
        where h.id = :a_selected_doc_id
        into source_doc_id, agent_id;

    if ( source_doc_id is not null ) then
        begin
            -- Find doc ID (with checking in view v_*** if need) and try to LOCK it.
            -- Raise exc if no found or can`t lock:
            -- ::: do NOT ::: execute procedure sp_lock_selected_doc( source_doc_id, 'doc_list', a_selected_doc_id);

            select h.agent_id from doc_list h where h.id = :a_selected_doc_id into agent_id;
            if ( agent_id is null ) then
                exception ex_no_doc_found_for_handling using('doc_list', a_selected_doc_id);
                -- no document found for handling in datasource = '@1' with id=@2

            if ( a_total_pay is null ) then
                begin
                    select sum( p.snd_cost ) from pdistr p where p.snd_id = :source_doc_id into v_non_paid_total;
                    current_pay_sum = round( v_non_paid_total, v_round_to );
                    if (current_pay_sum < v_non_paid_total) then
                    begin
                        current_pay_sum = current_pay_sum + power(10, abs(v_round_to));
                    end
                end
            else
                current_pay_sum = a_total_pay;

        end
    else -- source_doc_id is null
        begin
            select id_selected from sp_get_random_id( :view_to_search_agent, null, null, 0 ) into agent_id;
            if ( a_total_pay is null ) then
                begin
                    if (a_payment_oper = fn_oper_pay_from_customer() ) then
                        current_pay_sum = round(fn_get_random_cost('C_PAYMENT_FROM_CLIENT_MIN_TOTAL', 'C_PAYMENT_FROM_CLIENT_MAX_TOTAL'), v_round_to); -- round to hundreds
                    else
                        current_pay_sum = round(fn_get_random_cost('C_PAYMENT_TO_SUPPLIER_MIN_TOTAL', 'C_PAYMENT_TO_SUPPLIER_MAX_TOTAL'), v_round_to); -- round to thousands
                end
            else
                current_pay_sum = a_total_pay;
        end

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this,null,'doc_id='||coalesce(source_doc_id, '<null>') );

    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(source_doc_id, '<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_payment_common

--------------------------------------------------------------------------------

create or alter procedure sp_pay_from_customer(
    a_selected_doc_id type of dm_idb default null,
    a_total_pay type of dm_cost default null,
    dbg int default 0
)
returns (
    agent_id type of dm_idb,
    prepayment_id type of dm_idb, -- id of prepayment that was done here
    realization_id type of dm_idb, -- id of reserve realization doc that 'receives' this advance
    current_pay_sum type of dm_cost
)
as
    declare v_dbkey dm_dbkey;
    declare v_this dm_dbobj = 'sp_pay_from_customer';
begin

    -- Implementation for payment from customer to us.
    -- Randomly choose invoice that is not yet fully paid (by customer) and creates
    -- payment document (with sum that can be equal or LESS than rest of value
    -- that should be 100% paid).

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    execute procedure sp_payment_common(
        fn_oper_pay_from_customer(),
        a_selected_doc_id,
        a_total_pay
    ) returning_values realization_id, agent_id, current_pay_sum;

    -- add new record in doc_list (header)
    execute procedure sp_add_doc_list(
        null,
        fn_oper_pay_from_customer(),
        agent_id,
        null,
        null,
        0,
        current_pay_sum
    )
    returning_values :prepayment_id, :v_dbkey;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'payment_id='||prepayment_id);

    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(prepayment_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^  -- sp_pay_from_customer

create or alter procedure sp_cancel_pay_from_customer(
    a_selected_doc_id type of dm_idb default null
)
returns (
    doc_list_id type of dm_idb, -- id of selected doc (prepayment that is deleted)
    agent_id type of dm_idb, -- id of customer
    prepayment_sum type of dm_cost -- customer's payment (in retailing prices)
)
as
    declare v_dummy bigint;
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
    declare v_this dm_dbobj = 'sp_cancel_pay_from_customer';
begin

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
     -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            (select id_selected from
                             sp_get_random_id( 'v_cancel_customer_prepayment' -- a_view_for_search
                                              ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                              ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                              ,:c_raise_exc_when_no_found
                                              ,:c_can_skip_order_clause
                                             )
                            )
                          );

    -- Try to LOCK just selected doc, raise exc if can`t:
    execute procedure sp_lock_selected_doc( doc_list_id, 'v_cancel_customer_prepayment', a_selected_doc_id);

    select agent_id, cost_retail
    from doc_list h
    where h.id = :doc_list_id
    into agent_id, prepayment_sum;
    
    -- finally, remove prepayment doc (decision about corr. `money_turnover_log` - see trigger doc_list_aiud)
    delete from doc_list h where h.id = :doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||doc_list_id);

    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_cancel_pay_from_customer


create or alter procedure sp_pay_to_supplier(
    a_selected_doc_id type of dm_idb default null,
    a_total_pay type of dm_cost default null,
    dbg int default 0
)
returns (
    agent_id type of dm_idb,
    prepayment_id type of dm_idb, -- id of prepayment that was done here
    invoice_id type of dm_idb, -- id of open supplier invoice(s) that 'receives' this advance
    current_pay_sum type of dm_cost -- total sum of prepayment (advance)
)
as
    declare v_dbkey dm_dbkey;
    declare v_round_to smallint;
    declare v_id type of dm_idb;
    declare v_this dm_dbobj = 'sp_pay_to_supplier';
begin

    -- Implementation for our payment to supplier.
    -- Randomly choose invoice that is not yet fully paid (by us) and creates
    -- payment document (with sum that can be equal or LESS than rest of value
    -- that should be 100% paid).

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    execute procedure sp_payment_common(
        fn_oper_pay_to_supplier(),
        a_selected_doc_id,
        a_total_pay
    ) returning_values invoice_id, agent_id, current_pay_sum;

    -- add new record in doc_list (header)
    execute procedure sp_add_doc_list(
        null,
        fn_oper_pay_to_supplier(),
        agent_id,
        null,
        null,
        current_pay_sum,
        0
    )
    returning_values :prepayment_id, :v_dbkey;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this, null, 'payment_id='||prepayment_id);

    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(prepayment_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end
end

^  -- sp_pay_to_supplier

create or alter procedure sp_cancel_pay_to_supplier(
    a_selected_doc_id type of dm_idb default null
)
returns (
    doc_list_id type of dm_idb, -- id of selected doc
    agent_id type of dm_idb, -- id of customer
    prepayment_sum type of dm_cost
)
as
    declare v_dummy bigint;
    declare v_this dm_dbobj = 'sp_cancel_pay_to_supplier';
    declare c_raise_exc_when_no_found dm_sign = 1;
    declare c_can_skip_order_clause dm_sign = 0;
begin

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    -- Choose random doc of corresponding kind.
    -- 25.09.2014: do NOT set c_can_skip_order_clause = 1,
    -- performance degrades from ~4900 to ~1900.
    doc_list_id = coalesce( :a_selected_doc_id,
                            (select id_selected from
                             sp_get_random_id( 'v_cancel_payment_to_supplier' -- a_view_for_search
                                              ,null -- a_view_for_min_id ==> the same as a_view_for_search
                                              ,null -- a_view_for_max_id ==> the same as a_view_for_search
                                              ,:c_raise_exc_when_no_found
                                              ,:c_can_skip_order_clause
                                            )
                            )
                          );

    -- Try to LOCK just selected doc, raise exc if can`t:
    execute procedure sp_lock_selected_doc( doc_list_id, 'v_cancel_payment_to_supplier', a_selected_doc_id);

    select agent_id, cost_purchase
    from doc_list h
    where h.id = :doc_list_id
    into agent_id, prepayment_sum;

    -- finally, remove prepayment doc (decision about corr. `money_turnover_log` - see trigger doc_list_aiud)
    delete from doc_list h where h.id = :doc_list_id;

    -- add to performance log timestamp about start/finish this unit
    -- (records from GTT tmp$perf_log will be MOVED in fixed table perf_log):
    execute procedure sp_add_perf_log(0, v_this, null, 'doc_id='||doc_list_id);

    suspend;

when any do
    begin
        -- in a`utonomous tx:
        -- 1) add to tmp$perf_log error info + timestamp,
        -- 2) move records from tmp$perf_log to perf_log
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            'doc_id='||coalesce(doc_list_id,'<null>'),
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- sp_cancel_pay_to_supplier

--------------------------------------------------------------------------------
-- #######################   S E R V I C E   U N I T S   #######################
--------------------------------------------------------------------------------

create or alter procedure srv_make_invnt_saldo(
    a_selected_ware_id type of dm_idb default null
)
returns (
    msg dm_info,
    ins_rows int,
    upd_rows int,
    del_rows int
)
as
    declare v_semaphore_id type of dm_idb;
    declare v_deferred_to_next_time boolean = false;
    declare v_gdscode int = null;
    declare v_catch_bitset bigint;
    declare v_exc_on_chk_violation smallint;
    declare v_this dm_dbobj = 'srv_make_invnt_saldo';
    declare s_qty_clo type of dm_qty;
    declare s_qty_clr type of dm_qty;
    declare s_qty_ord type of dm_qty;
    declare s_qty_sup type of dm_qty;
    declare s_qty_avl type of dm_qty;
    declare s_qty_res type of dm_qty;
    declare s_qty_inc type of dm_qty;
    declare s_qty_out type of dm_qty;
    declare s_cost_inc type of dm_cost;
    declare s_cost_out type of dm_cost;
    declare v_rc int;
    declare v_err_msg dm_info;
    declare v_neg_info dm_info;
    declare c_chk_violation_code int = 335544558; -- check_constraint
    declare c_semaphores cursor for ( select id from semaphores s where s.task = :v_this rows 1);
begin
    -- Gathers all turnovers for wares in 'invnt_turnover_log' table and makes them total
    -- to merge in table 'invnt_saldo'
    -- Original idea: sql.ru/forum/964534/hranimye-agregaty-bez-konfliktov-i-blokirovok-recept?hl=
    -- 21.08.2014: refactored in order to maximal detailed info (via cursor)
    -- and SKIP problem wares (with logging first ware which has neg. remainder)
    -- and continue totalling for other ones.

    v_catch_bitset = cast(rdb$get_context('USER_SESSION','QMISM_VERIFY_BITSET') as bigint);
    -- bit#0 := 1 ==> perform calls of srv_catch_qd_qs_mism in doc_list_aiud => sp_add_invnt_log
    -- bit#1 := 1 ==> perform calls of srv_catch_neg_remainders from invnt_turnover_log_ai
    --                (instead of totalling turnovers to `invnt_saldo` table)
    -- bit#2 := 1 ==> allow dump dirty data into z-tables for analysis, see sp zdump4dbg, in case
    --                when some 'bad exception' occurs (see ctx var `HALT_TEST_ON_ERRORS`)
    if ( bin_and( v_catch_bitset, 2 ) = 2 ) then
        -- instead of totalling turnovers (invnt_turnover_log => group_by => invnt_saldo)
        -- we make verification of remainders after every time invnt_turnover_log is
        -- changed, see: INVNT_TURNOVER_LOG_AI => SRV_CATCH_NEG_REMAINDERS
        --####
          exit;
        --####

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    if ( not fn_is_snapshot() )
    then
        exception ex_snapshot_isolation_required;


    -- Ensure that current attach is the ONLY one which tries to make totals.
    -- Use locking record from `semaphores` table to serialize access to this
    -- code:
    begin
        v_semaphore_id = null;
        open c_semaphores;
        while (1=1) do
        begin
            fetch c_semaphores into v_semaphore_id;
            if ( row_count = 0 ) then
                exception ex_record_not_found using('semaphores', v_this);
            update semaphores set id = id where current of c_semaphores;
            leave;
        end
        close c_semaphores;

    when any do
        -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
        -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
        -- catched it's kind of exception!
        -- 1) tracker.firebirdsql.org/browse/CORE-3275
        --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
        -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
        begin
            if ( fn_is_lock_trouble(gdscode) ) then
                begin
                    -- concurrent_transaction ==> if select for update failed;
                    -- deadlock ==> if attempt of UPDATE set id=id failed.
                    v_gdscode = gdscode;
                    del_rows = -gdscode;
                    v_deferred_to_next_time = true;
                end
            else
                exception;  -- ::: nb ::: anonimous but in when-block! (check will it be really raised! find topic in sql.ru)
        end
    end

    if ( v_deferred_to_next_time ) then
    begin
        -- Info to be stored in context var. A`DD_INFO, see below call of sp_add_to_abend_log (in W`HEN ANY section):
        msg = 'can`t lock semaphores.id='|| coalesce(v_semaphore_id,'<?>') ||', deferred';
        exception ex_cant_lock_semaphore_record msg;
    end

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    ins_rows = 0;
    upd_rows = 0;
    del_rows = 0;
    v_neg_info = '';
    v_exc_on_chk_violation = iif( rdb$get_context('USER_SESSION', 'HALT_TEST_ON_ERRORS') containing ',CK,', 1, 0);

    for
        select
            ware_id,
            qty_clo, qty_clr, qty_ord, qty_sup,
            qty_avl, qty_res, qty_inc, qty_out,
            cost_inc, cost_out
        from v_saldo_invnt sn -- result MUST be totalled by WARE_ID (see DDL of this view)
        as cursor cn
    do
    begin
        s_qty_clo=0; s_qty_clr=0; s_qty_ord=0; s_qty_sup=0;
        s_qty_avl=0; s_qty_res=0; s_qty_inc=0; s_qty_out=0;
        s_cost_inc=0; s_cost_out=0;

        select
            qty_clo, qty_clr, qty_ord, qty_sup,
            qty_avl, qty_res, qty_inc, qty_out,
            cost_inc, cost_out
        from invnt_saldo t
        where t.id = cn.ware_id
        into
             s_qty_clo, s_qty_clr, s_qty_ord, s_qty_sup
            ,s_qty_avl, s_qty_res, s_qty_inc,s_qty_out
            ,s_cost_inc, s_cost_out;

        v_rc = row_count; -- 0=> will be INSERT, otherwise UPDATE
        -- these values WILL be written in invnt_saldo:
        s_qty_clo = s_qty_clo + cn.qty_clo;
        s_qty_clr = s_qty_clr + cn.qty_clr;
        s_qty_ord = s_qty_ord + cn.qty_ord;
        s_qty_sup = s_qty_sup + cn.qty_sup;
        s_qty_avl = s_qty_avl + cn.qty_avl;
        s_qty_res = s_qty_res + cn.qty_res;
        s_qty_inc = s_qty_inc + cn.qty_inc;
        s_qty_out = s_qty_out + cn.qty_out;
        s_cost_inc = s_cost_inc + cn.cost_inc;
        s_cost_out = s_cost_out + cn.cost_out;

        v_err_msg='';
        -- Check all new values before writing into invnt_saldo for matching
        -- rule of non-negative remainders, to be able DETAILED LOG of any
        -- violation (we can`t get any info about data that violates rule when
        -- exception raising):
        if ( s_qty_clo < 0 ) then v_err_msg = v_err_msg||' clo='||s_qty_clo;
        if ( s_qty_clr < 0 ) then v_err_msg = v_err_msg||' clr='||s_qty_clr;
        if ( s_qty_ord < 0 ) then v_err_msg = v_err_msg||' ord='||s_qty_ord;
        if ( s_qty_sup < 0 ) then v_err_msg = v_err_msg||' sup='||s_qty_sup;
        if ( s_qty_avl < 0 ) then v_err_msg = v_err_msg||' avl='||s_qty_avl;
        if ( s_qty_res < 0 ) then v_err_msg = v_err_msg||' res='||s_qty_res;
        if ( s_qty_inc < 0 ) then v_err_msg = v_err_msg||' inc='||s_qty_inc;
        if ( s_qty_out < 0 ) then v_err_msg = v_err_msg||' out='||s_qty_out;
        if ( s_cost_inc < 0 ) then v_err_msg = v_err_msg||' $inc='||s_cost_inc;
        if ( s_cost_out < 0 ) then v_err_msg = v_err_msg||' $out='||s_cost_out;

        if ( v_err_msg >  '' and v_neg_info = '' ) then
            -- register info only for FIRST ware when negative remainder found:
            v_neg_info = 'ware='||cn.ware_id||v_err_msg;

        if ( v_neg_info > '' ) then
        begin
            -- ::: NB ::: do NOT raise exc`eption! Let all wares which have NO troubles
            -- be totalled and removed from invnt_turnover_log (=> reduce size of this table)
            rdb$set_context( 'USER_SESSION','ADD_INFO', v_neg_info ); -- to be displayed in log of 1run_oltp_emul.bat
            msg = v_neg_info||'; '||msg;
            execute procedure sp_upd_in_perf_log(
                v_this,
                c_chk_violation_code,
                msg
            );
        end

        if ( v_err_msg = '' -- all remainders will be CORRECT => can write
             or
             v_exc_on_chk_violation = 1 -- allow attempt to write incorrect remainder in order to raise not_valid e`xception and auto-cancel test itself
           ) then
        begin
            update or insert into invnt_saldo(
                id
                ,qty_clo,qty_clr,qty_ord,qty_sup
                ,qty_avl,qty_res,qty_inc,qty_out
                ,cost_inc,cost_out
            ) values (
                cn.ware_id
                ,:s_qty_clo,:s_qty_clr,:s_qty_ord,:s_qty_sup
                ,:s_qty_avl,:s_qty_res,:s_qty_inc,:s_qty_out
                ,:s_cost_inc,:s_cost_out
            )
            matching(id);
    
            delete from invnt_turnover_log ng
            where ng.ware_id = cn.ware_id;
    
            del_rows = del_rows + row_count;
            ins_rows = ins_rows + iif( v_rc=0, 1, 0 );
            upd_rows = upd_rows + iif( v_rc=0, 0, 1 );

        end -- v_err_msg = ''
    end --  cursor on v_saldo_invnt

    msg = 'i='||ins_rows||', u='||upd_rows||', d='||del_rows;
    if ( v_neg_info = '' ) then
        rdb$set_context('USER_SESSION','ADD_INFO', msg); -- to be displayed in result log of isql

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this, v_gdscode, msg );

    suspend;

when any do
    begin
        -- NB: proc sp_add_to_abend_log will set rdb$set_context('USER_SESSION','A`DD_INFO', msg)
        -- in order to show this additional info in ISQL log after operation will finish:
        execute procedure sp_add_to_abend_log(
            msg, -- ==> context var. ADD_INFO will be = "can`t lock semaphores.id=..., deferred" - to be shown in ISQL log
            gdscode,
            v_neg_info,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- end of srv_make_invnt_saldo

--------------------------------------------------------------------------------

create or alter procedure srv_make_money_saldo(
    a_selected_agent_id type of dm_idb default null
)
returns (
    msg dm_info,
    ins_rows int,
    upd_rows int,
    del_rows int
)
as
    declare v_semaphore_id type of dm_ids;
    declare v_deferred_to_next_time boolean = false;
    declare v_gdscode int = null;
    declare v_dbkey dm_dbkey;
    declare agent_id type of dm_ids;
    declare m_cust_debt dm_sign;
    declare m_supp_debt dm_sign;
    declare cost_purchase type of dm_cost;
    declare cost_retail type of dm_cost;
    declare v_dts_beg timestamp;
    declare v_dummy bigint;
    declare v_this dm_dbobj = 'srv_make_money_saldo';
    declare c_semaphores cursor for ( select id from semaphores s where s.task = :v_this rows 1);
begin

    -- Gathers all turnovers for agents in 'money_turnover_log' table and makes them total
    -- to merge in table 'money_saldo'
    -- Original idea by Dimitry Sibiryakov:
    -- sql.ru/forum/964534/hranimye-agregaty-bez-konfliktov-i-blokirovok-recept?hl=

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;
    
    if ( not fn_is_snapshot() )
    then
        exception ex_snapshot_isolation_required;

    -- Ensure that current attach is the ONLY one which tries to make totals.
    -- Use locking record from `semaphores` table to serialize access to this
    -- code:
    begin
        open c_semaphores;
        while (1=1) do
        begin
            fetch c_semaphores into v_semaphore_id;
            if ( row_count = 0 ) then
                exception ex_record_not_found using('semaphores', v_this);
            update semaphores set id = id where current of c_semaphores;
            leave;
        end
        close c_semaphores;
    when any do
        -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
        -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
        -- catched it's kind of exception!
        -- 1) tracker.firebirdsql.org/browse/CORE-3275
        --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
        -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
        begin
            if ( fn_is_lock_trouble(gdscode) ) then
                begin
                    -- concurrent_transaction ==> if select for update failed;
                    -- deadlock ==> if attempt of UPDATE set id=id failed.
                    v_gdscode = gdscode;
                    v_deferred_to_next_time = true;
                end
            else
                exception;  -- ::: nb ::: anonimous but in when-block! (check will it be really raised! find topic in sql.ru)
        end
    end

    if ( v_deferred_to_next_time ) then
    begin
        -- Info to be stored in context var. A`DD_INFO, see below call of sp_add_to_abend_log (in W`HEN ANY section):
        msg = 'can`t lock semaphores.id='|| coalesce(v_semaphore_id,'<?>') ||', deferred';
        exception ex_cant_lock_semaphore_record msg;
    end

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    ins_rows = 0;
    upd_rows = 0;
    del_rows = 0;
    v_dts_beg = 'now';
    for
        select x.agent_id,
                sum( o.m_supp_debt * x.sum_purchase ) sum_purchase,
                sum( o.m_cust_debt * x.sum_retail ) sum_retail
        from (
            select
                m.agent_id,
                m.optype_id,
                sum( m.cost_purchase ) sum_purchase,
                sum( m.cost_retail ) sum_retail
            from money_turnover_log m
            -- 27.09.2015: added index on (agent_id, optype_id)
            group by m.agent_id, m.optype_id
        ) x
        join optypes o on x.optype_id = o.id
        group by x.agent_id
    into
        agent_id,
        cost_purchase,
        cost_retail
    do begin

        delete from money_turnover_log m
        where m.agent_id = :agent_id;
        del_rows = del_rows + row_count;

        update money_saldo
        set cost_purchase = cost_purchase + :cost_purchase,
            cost_retail = cost_retail +  :cost_retail
        where agent_id = :agent_id;

        if ( row_count = 0 ) then
            begin
                insert into money_saldo( agent_id, cost_purchase, cost_retail )
                values( :agent_id, :cost_purchase, :cost_retail);

                ins_rows = ins_rows + 1;
            end
        else
            upd_rows = upd_rows + row_count;

    end -- cursor for money_turnover_log m join optypes o on m.optype_id = o.id

    msg = 'i='||ins_rows||', u='||upd_rows||', d='||del_rows
          ||', ms='||datediff(millisecond from v_dts_beg to cast('now' as timestamp) );
    rdb$set_context('USER_SESSION','ADD_INFO', msg);  -- to be displayed in result log of isql

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this, v_gdscode, msg );

    suspend;

when any do
    begin
        -- NB: proc sp_add_to_abend_log will set rdb$set_context('USER_SESSION','A`DD_INFO', msg)
        -- in order to show this additional info in ISQL log after operation will finish:
        execute procedure sp_add_to_abend_log(
            msg,  -- ==> context var. ADD_INFO will be = "can`t lock semaphores.id=..., deferred" - to be shown in ISQL log
            gdscode,
            'agent_id='||agent_id,
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- srv_make_money_saldo

--------------------------------------------------------------------------------

create or alter procedure srv_recalc_idx_stat returns(
    tab_name dm_dbobj,
    idx_name dm_dbobj,
    elapsed_ms int
)
as
    declare msg dm_info;
    declare v_semaphore_id type of dm_idb;
    declare v_deferred_to_next_time boolean = false;
    declare v_dummy bigint;
    declare idx_stat_befo double precision;
    declare v_gdscode int = null;
    declare v_this dm_dbobj = 'srv_recalc_idx_stat';
    declare v_start timestamp;
    declare c_semaphores cursor for ( select id from semaphores s where s.task = :v_this rows 1);
begin

    -- Refresh index statistics for most changed tables.
    -- Needs to be run in regular basis otherwise ineffective plans
    -- can be generated when doing inner joins!

    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises ex`ception to stop test:
    execute procedure sp_check_to_stop_work;

    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    -- Use locking record from `semaphores` table to synchronize access to this
    -- code:
    begin
        v_semaphore_id = null;
        open c_semaphores;
        while (1=1) do
        begin
            fetch c_semaphores into v_semaphore_id;
            if ( row_count = 0 ) then
                exception ex_record_not_found using('semaphores', v_this);
            update semaphores set id = id where current of c_semaphores;
            leave;
        end
        close c_semaphores;
    when any do
        -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
        -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
        -- catched it's kind of exception!
        -- 1) tracker.firebirdsql.org/browse/CORE-3275
        --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
        -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
        begin
            if ( fn_is_lock_trouble(gdscode) ) then
                begin
                    -- concurrent_transaction ==> if select for update failed;
                    -- deadlock ==> if attempt of UPDATE set id=id failed.
                    v_deferred_to_next_time = true;
                    v_gdscode = gdscode;
                end
            else
                exception; -- ::: nb ::: anonimous but in when-block!
        end
    end

    if ( v_deferred_to_next_time ) then
    begin
       -- Info to be stored in context var. A`DD_INFO, see below call of sp_add_to_abend_log (in W`HEN ANY section):
        msg = 'can`t lock semaphores.id='|| coalesce(v_semaphore_id,'<?>') ||', deferred';
        exception ex_cant_lock_semaphore_record msg;
        exit;
    end

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    -- increment number of total business routine calls within this Tx,
    -- in order to display estimated overall performance in ISQL session
    -- logs (see generated $tmpdir/tmp_random_run.sql).
    -- Instead of querying perf_log join business_ops it was decided to
    -- use only context variables in user_tran namespace:
    execute procedure srv_increment_tx_bops_counter;

    for
        select ri.rdb$relation_name, ri.rdb$index_name, ri.rdb$statistics
        from rdb$indices ri
        where
            coalesce(ri.rdb$system_flag,0)=0
            -- make recalc only for most used tables:
            and ri.rdb$relation_name in ( 'DOC_DATA', 'DOC_LIST', 'QDISTR', 'QSTORNED', 'PDISTR', 'PSTORNED')
        order by ri.rdb$relation_name, ri.rdb$index_name
    into
        tab_name, idx_name, idx_stat_befo
    do begin
        -- Check that table `ext_stoptest` (external text file) is EMPTY,
        -- otherwise raises ex`ception to stop test:
        execute procedure sp_check_to_stop_work;

        execute procedure sp_add_perf_log(1, v_this||'_'||idx_name);

        v_start='now';

        execute statement( 'set statistics index '||idx_name )
        with autonomous transaction -- again since 27.11.2015 (commit for ALL indices at once is too long for huge databases!)
        ; 

        elapsed_ms = datediff(millisecond from v_start to cast('now' as timestamp)); -- 15.09.2015

        execute procedure sp_add_perf_log(0, v_this||'_'||idx_name,null,tab_name, idx_stat_befo);
        suspend;
    end

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this, v_gdscode);

when any do
    begin
        -- NB: proc sp_add_to_abend_log will set rdb$set_context('USER_SESSION','A`DD_INFO', msg)
        -- in order to show this additional info in ISQL log after operation will finish:
        execute procedure sp_add_to_abend_log(
            msg, -- ==> context var. ADD_INFO will be = "can`t lock semaphores.id=..., deferred" - to be shown in ISQL log
            gdscode,
            null,
            v_this
        );

        --#######
        exception; -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- srv_recalc_idx_stat

--------------------------------------------------------------------------
-- ###########################    R E P O R T S   ########################
--------------------------------------------------------------------------

create or alter procedure srv_get_last_launch_beg_end(
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
     last_launch_beg timestamp
    ,last_launch_end timestamp
) as
begin
    -- Auxiliary SP: finds moments of start and finish business operations in perf_log
    -- on timestamp interval that is [L, N] where:
    -- "L" = latest from {-abs( :a_last_hours * 60 + :a_last_mins ), 'perf_watch_interval'}
    -- "N" = latest record in perf_log table
    select maxvalue( x.last_job_start_dts, y.last_job_finish_dts ) as last_job_start_dts
    from (
        select p.dts_beg as last_job_start_dts
        from perf_log p
        where p.unit = 'perf_watch_interval'
        order by dts_beg desc rows 1
    ) x
    cross join
    (
        select dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to p.dts_beg) as last_job_finish_dts
        from perf_log p
        where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit) -- nb: do NOT use inner join here (bad plan with sort)
        order by p.dts_beg desc
        rows 1
    ) y
    into last_launch_beg;

    select p.dts_end as report_end
    from perf_log p
    where
        p.dts_beg >= :last_launch_beg
        and p.dts_end is not null
    order by p.dts_beg desc
    rows 1
    into last_launch_end;
    suspend;
end

^ -- srv_get_last_launch_beg_end

create or alter procedure srv_mon_perf_total(
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
    business_action dm_info,
    job_beg varchar(16),
    job_end varchar(16),
    avg_times_per_minute numeric(12,2),
    avg_elapsed_ms int,
    successful_times_done int
)
as
    declare v_sort_prior int;
    declare v_overall_performance double precision;
    declare v_all_minutes int;
    declare v_succ_all_times int;
    declare v_this dm_dbobj = 'srv_mon_perf_total';
begin
    -- MAIN SP for estimating performance: provides number of business operations
    -- per minute which were SUCCESSFULLY finished. Suggested by Alexey Kovyazin.

    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    delete from tmp$perf_log p  where p.stack = :v_this;

    insert into tmp$perf_log(unit, info, id, dts_beg, dts_end, aux1, aux2, stack)
    with
    a as(
        -- reduce needed number of minutes from most last event of some SP starts:
        -- 18.07.2014: handle only data which belongs to LAST job.
        -- Record with p.unit = 'perf_watch_interval' is added in
        -- oltp_isql_run_worker.bat before FIRST isql will be launched
        -- for each mode ('sales', 'logist' etc)
        select maxvalue( x.last_job_start_dts, y.last_job_finish_dts ) as last_job_start_dts
        from (
            select p.dts_beg as last_job_start_dts
            from perf_log p
            where p.unit = 'perf_watch_interval'
            order by dts_beg desc rows 1
        ) x
        join
        (
            select dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to p.dts_beg) as last_job_finish_dts
            from perf_log p
            -- nb: do NOT use inner join here (bad plan with sort)
            where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit) -- "order by" - only for 3.0
            order by p.dts_beg desc
            rows 1
        ) y
        on 1=1
    )
    ,p as(
        select
            g.unit
            ,min( g.dts_beg ) report_beg
            ,max( g.dts_end  ) report_end
            ,count(*) successful_times_done
            ,avg(g.elapsed_ms) successful_avg_ms
        from perf_log g
        join business_ops b on b.unit=g.unit
        join a on g.dts_beg >= a.last_job_start_dts -- only rows which are from THIS job!
        where  -- we must take in account only SUCCESSFULLY finished units, i.e. fb_gdscode is NULL.
            g.fb_gdscode + 0 -- 25.11.2015: suppress making bitmap for this index! almost 90% of rows contain NULL in this field.
            is null
        group by g.unit
    )
    select b.unit, b.info, b.sort_prior, p.report_beg, p.report_end,
           p.successful_times_done, p.successful_avg_ms, :v_this
    from business_ops b
    left join p on b.unit = p.unit;
    -- tmp$perf_log(unit, info, id, dts_beg, dts_end, aux1, aux2)

    -- total elapsed minutes and number of successfully finished SPs for ALL units:
    select nullif(datediff( minute from min_beg to max_end ),0),
           succ_all_times,
           left(cast(min_beg as varchar(24)),16),
           left(cast(max_end as varchar(24)),16)
    from (
        select min(p.dts_beg) min_beg, max(p.dts_end) max_end, sum(p.aux1) succ_all_times
        from tmp$perf_log p
        where p.stack = :v_this
    )
    into v_all_minutes, v_succ_all_times, job_beg, job_end;

    for
        select
             business_action
            ,avg_times_per_minute
            ,avg_elapsed_ms
            ,successful_times_done
            ,sort_prior
        from (
            select
                0 as sort_prior
                ,'*** OVERALL *** for '|| :v_all_minutes ||' minutes: ' as business_action -- 'Average ops/minute = '||:v_all_minutes||' ;'||(sum( aux1 ) / :v_all_minutes)  as business_action
                ,1.00*sum( aux1 ) / :v_all_minutes as avg_times_per_minute
                ,avg(aux2) as avg_elapsed_ms
                ,sum(aux1) as successful_times_done
            from tmp$perf_log p
            where p.stack = :v_this

            UNION ALL
            
            select
                 p.id as sort_prior
                ,p.info as business_action
                ,1.00 * aux1 / maxvalue( 1, datediff( minute from p.dts_beg to p.dts_end ) ) as avg_times_per_minute
                ,aux2 as avg_elapsed_ms
                ,aux1 as successful_times_done
            from tmp$perf_log p
            where p.stack = :v_this
        ) x
        order by x.sort_prior
        into
             business_action
            ,avg_times_per_minute
            ,avg_elapsed_ms
            ,successful_times_done
            ,v_sort_prior
    do begin
        if ( v_sort_prior = 0 ) then -- save value to be written into perf_log
            v_overall_performance = avg_times_per_minute;
        suspend;
    end

    delete from tmp$perf_log p  where p.stack = :v_this;

    begin
        -- 02.11.2015: save overall performance value so it can be used later:
        update perf_log p set aux1 = :v_overall_performance
        where p.unit = 'perf_watch_interval'
        order by dts_beg desc rows 1;
    when any do
        begin
            -- lock/update conflict can be here with another ISQL session with SID #1
            -- (running on other machine) that makes this report at the same time.
            -- We suppress this exception because this record will anyway contain
            -- value that we want to save.
        end
    end
    -- Statistics for database with size = 100 Gb and cleaned OS cache (LI-V3.0.0.32179):
    -- sync
    -- echo 3 > /proc/sys/vm/drop_caches
    -- 20 records fetched
    -- 600187 ms, 233041 read(s), 4 write(s), 3206400 fetch(es), 70 mark(s)
    --
    -- Table                             Natural     Index    Update    Insert    Delete
    -- ***********************************************************************************
    -- RDB$INDICES                                       9
    -- BUSINESS_OPS                           19        38
    -- PERF_LOG                                     369967         1
    -- TMP$PERF_LOG                           76                            19        19

end

^ -- srv_mon_perf_total

create or alter procedure srv_mon_perf_dynamic(
    a_intervals_number smallint default 10,
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
     business_action dm_info
    ,interval_no smallint
    ,cnt_ok_per_minute int
    ,cnt_all int
    ,cnt_ok int
    ,cnt_err int
    ,err_prc numeric(12,2)
    ,ok_avg_ms int
    ,interval_beg timestamp
    ,interval_end timestamp
)
as
    declare v_this dm_dbobj = 'srv_mon_perf_dynamic';
begin

    -- 15.09.2014 Get performance results 'in dynamic': split all job time to N
    -- intervals, where N is specified by 1st input argument.
    -- 03.09.2015 Removed cross join perf_log and CTE 'inp_args as i' because
    -- of inefficient plan. Input parameters are injected inside DT.
    -- See: http://www.sql.ru/forum/1173774/select-a-b-from-a-cross-b-order-by-indexed-field-of-a-rows-n-ignorit-rows-n-why

    a_intervals_number = iif( a_intervals_number <= 0, 10, a_intervals_number);
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    delete from tmp$perf_log p where p.stack = :v_this;
    insert into tmp$perf_log(
        unit
        ,info
        ,id        -- interval_no
        ,dts_beg   -- interval_beg
        ,dts_end   -- interval_end
        ,aux1      -- cnt_ok
        ,aux2       -- cnt_err
        ,elapsed_ms -- ok_avg_ms
        ,stack
    )
    with
    a as(
        -- reduce needed number of minutes from most last event of some SP starts:
        -- 18.07.2014: handle only data which belongs to LAST job.
        -- Record with p.unit = 'perf_watch_interval' is added in
        -- oltp_isql_run_worker.bat before FIRST isql will be launched
        select
            maxvalue( x.last_added_watch_row_dts, y.first_measured_start_dts ) as first_job_start_dts
            ,y.last_job_finish_dts
            ,y.intervals_number
        from (
            select p.dts_beg as last_added_watch_row_dts
            from perf_log p
            where p.unit = 'perf_watch_interval'
            order by dts_beg desc rows 1
        ) x
        join (
            select
                dateadd( p.scan_bak_minutes minute to p.dts_beg) as first_measured_start_dts
                ,p.dts_beg as last_job_finish_dts
                ,p.intervals_number
            from
            ( -- since 03.09.2015:
                select
                    p.*
                    , -abs( :a_last_hours * 60 + :a_last_mins ) as scan_bak_minutes
                    , :a_intervals_number as intervals_number
                from perf_log p
            ) p
            -- nb: do NOT use inner join here (bad plan with sort)
            where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit)
            order by p.dts_beg desc
            rows 1
-- Before 03.09.2015
-- (inefficient plan with nested loops of all pef_log rows + SORT, 'rows 1' was ignored!
-- See: http://www.sql.ru/forum/1173774/select-a-b-from-a-cross-b-order-by-indexed-field-of-a-rows-n-ignorit-rows-n-why
--            select
--                dateadd( i.scan_bak_minutes minute to p.dts_beg) as first_measured_start_dts
--                ,p.dts_beg as last_job_finish_dts
--                ,i.intervals_number
--            from perf_log p
--            join i on 1=1  -- CTE 'i' was: "with i as(select :a_intervals_number, :a_last_hours, :a_last_mins from rdb$database)
--            -- nb: do NOT use inner join here (bad plan with sort)
--            where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit)
--            order by p.dts_beg desc
--            rows 1
        ) y on 1=1
    )
    ,d as(
        select
            a.first_job_start_dts
            ,a.last_job_finish_dts
            ,1+datediff(second from a.first_job_start_dts to a.last_job_finish_dts) / a.intervals_number as sec_for_one_interval
        from a
    )
    --    select * from d

    ,p as(
        select
            g.unit
            ,b.info
            ,1+cast(datediff(second from d.first_job_start_dts to g.dts_beg) / d.sec_for_one_interval as int) as interval_no
            ,count(*) cnt_all
            ,count( iif( g.fb_gdscode is null, 1, null ) ) cnt_ok
            ,count( iif( g.fb_gdscode is NOT null, 1, null ) ) cnt_err
            ,100.00 * count( nullif(g.fb_gdscode,0) ) / count(*) err_prc
            ,avg(  iif( g.fb_gdscode is null, g.elapsed_ms, null ) ) ok_avg_ms
            ,min(d.first_job_start_dts) as first_job_start_dts
            ,min(d.sec_for_one_interval) as sec_for_one_interval
        from perf_log g
        join business_ops b on b.unit = g.unit
        join d on g.dts_beg >= d.first_job_start_dts -- only rows which are from THIS measured test run!
        group by 1,2,3
    )
    ,q as(
        select
            unit
            ,info
            ,interval_no
            ,dateadd( (interval_no-1) * sec_for_one_interval+1 second to first_job_start_dts ) as interval_beg
            ,dateadd( interval_no * sec_for_one_interval second to first_job_start_dts ) as interval_end
            ,cnt_all
            ,cnt_ok
            ,cnt_err
            ,err_prc
            ,ok_avg_ms
        from p
    )
    --select * from q;
    select
        unit
        ,info
        ,interval_no
        ,interval_beg
        ,interval_end
        ,cnt_ok          -- aux1
        ,cnt_err         -- aux2
        ,ok_avg_ms
        ,:v_this
    from q;
    -----------------------------

    for
        select
             business_action
            ,interval_no
            ,cnt_ok_per_minute
            ,cnt_all
            ,cnt_ok
            ,cnt_err
            ,err_prc
            ,ok_avg_ms
            ,interval_beg
            ,interval_end
        from (
            select
                0 as sort_prior
                ,'interval #'||lpad(id, 4, ' ')||', overall' as business_action
                ,id as interval_no
                ,min(dts_beg) as interval_beg
                ,min(dts_end) as interval_end
                ,round(sum(aux1) / nullif(datediff(minute from min(dts_beg) to min(dts_end)),0), 0) cnt_ok_per_minute
                ,sum(aux1 + aux2) as cnt_all
                ,sum(aux1) as cnt_ok
                ,sum(aux2) as cnt_err
                ,100 * sum(aux2) / sum(aux1 + aux2) as err_prc
                ,cast(null as int) as ok_avg_ms
                --,avg(elapsed_ms) as ok_avg_ms
            from tmp$perf_log p
            where p.stack = :v_this
            group by id
        
            UNION ALL
        
            select
                1 as sort_prior
                ,info as business_action
                ,id as interval_no
                ,dts_beg as interval_beg
                ,dts_end as interval_end
                ,aux1 / nullif(datediff(minute from dts_beg to dts_end),0) cnt_ok_per_minute
                ,aux1 + aux2 as cnt_all
                ,aux1 as cnt_ok
                ,aux2 as cnt_err
                ,100 * aux2 / (aux1 + aux2) as err_prc
                ,elapsed_ms as ok_avg_ms
            from tmp$perf_log p
            where p.stack = :v_this
        )
        order by sort_prior, business_action, interval_no
    into
             business_action
            ,interval_no
            ,cnt_ok_per_minute
            ,cnt_all
            ,cnt_ok
            ,cnt_err
            ,err_prc
            ,ok_avg_ms
            ,interval_beg
            ,interval_end
    do suspend;
end

^ -- srv_mon_perf_dynamic

create or alter procedure srv_mon_perf_detailed (
    a_last_hours smallint default 3,
    a_last_mins smallint default 0,
    a_show_detl smallint default 0)
returns (
    unit type of dm_unit,
    cnt_all integer,
    cnt_ok integer,
    cnt_err integer,
    err_prc numeric(6,2),
    ok_min_ms integer,
    ok_max_ms integer,
    ok_avg_ms integer,
    cnt_lk_confl integer,
    cnt_user_exc integer,
    cnt_chk_viol integer,
    cnt_unq_viol integer,
    cnt_fk_viol integer,
    cnt_stack_trc integer, -- 335544842, 'stack_trace': appears at the TOP of stack in 3.0 SC (strange!)
    cnt_zero_gds integer,  -- 03.10.2014: core-4565 (gdscode=0 in when-section! 3.0 SC only)
    cnt_other_exc integer,
    job_beg varchar(16),
    job_end varchar(16)
)
as
begin
    -- SP for detailed performance analysis: count of operations
    -- (NOT only business ops; including BOTH successful and failed ones),
    -- count of errors (including by their types)
    a_last_hours = abs( coalesce(a_last_hours, 3) );
    a_last_mins = coalesce(a_last_mins, 0);
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    delete from tmp$perf_mon where 1=1;

    insert into tmp$perf_mon(
         dts_beg                     -- 1
        ,dts_end
        ,unit
        ,cnt_all
        ,cnt_ok                       -- 5
        ,cnt_err
        ,err_prc
        ,ok_min_ms
        ,ok_max_ms
        ,ok_avg_ms                  -- 10
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_fk_viol
        ,cnt_lk_confl
        ,cnt_user_exc               -- 15
        ,cnt_stack_trc
        ,cnt_zero_gds
        ,cnt_other_exc
    )
    with
    a as(
        -- reduce needed number of minutes from most last event of some SP starts:
        -- 18.07.2014: handle only data which belongs to LAST job.
        -- Record with p.unit = 'perf_watch_interval' is added in
        -- oltp_isql_run_worker.bat before FIRST isql will be launched
        -- for each mode ('sales', 'logist' etc)
        select maxvalue( x.last_job_start_dts, y.last_job_finish_dts ) as last_job_start_dts
        from (
            select p.dts_beg as last_job_start_dts
            from perf_log p
            where p.unit = 'perf_watch_interval'
            order by dts_beg desc rows 1
        ) x
        join
        (
            select dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to p.dts_beg) as last_job_finish_dts
            from perf_log p
            where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit) -- nb: do NOT use inner join here (bad plan with sort)
            order by p.dts_beg desc
            rows 1
        ) y
        on 1=1
    )
--    a as( select p.dts_beg last_beg from perf_log p order by p.dts_beg desc rows 1 )
    ,r as(
          select min(p.dts_beg) report_beg, max(dts_end) report_end
          from perf_log p
          join a on p.dts_beg >= a.last_job_start_dts
    )
    ,c as (
        select
             r.report_beg
            ,r.report_end
            ,pg.unit
            ,count(*) cnt_all
            ,count( iif( nullif(pg.fb_gdscode,0) is null, 1, null) ) cnt_ok                -- 5
            ,count( nullif(pg.fb_gdscode,0) ) cnt_err
            ,100.00 * count( nullif(pg.fb_gdscode,0) ) / count(*) err_prc
            ,min( iif( nullif(pg.fb_gdscode,0) is null, pg.elapsed_ms, null) ) ok_min_ms
            ,max( iif( nullif(pg.fb_gdscode,0) is null, pg.elapsed_ms, null) ) ok_max_ms
            ,avg( iif( nullif(pg.fb_gdscode,0) is null, pg.elapsed_ms, null) ) ok_avg_ms
            ,count( iif(pg.fb_gdscode in( 335544347, 335544558 ), 1, null ) ) cnt_chk_viol    -- 10
            ,count( iif(pg.fb_gdscode in( 335544665, 335544349 ), 1, null ) ) cnt_unq_viol
            ,count( iif(pg.fb_gdscode in( 335544466, 335544838, 335544839 ), 1, null ) ) cnt_fk_viol
            ,count( iif(pg.fb_gdscode in( 335544345, 335544878, 335544336, 335544451 ), 1, null ) ) cnt_lk_confl
            ,count( iif(pg.fb_gdscode = 335544517, 1, null) ) cnt_user_exc
            ,count( iif(pg.fb_gdscode = 335544842, 1, null) ) cnt_stack_trc                 -- 15
            ,count( iif(pg.fb_gdscode = 0, 1, null) ) cnt_zero_gds
            ,count( iif( pg.fb_gdscode
                         in (
                                335544347, 335544558,
                                335544665, 335544349,
                                335544466, 335544838, 335544839,
                                335544345, 335544878, 335544336, 335544451,
                                335544517,
                                335544842,
                                0
                            )
                          ,null
                          ,pg.fb_gdscode
                       )
                   ) cnt_other_exc
        from perf_log pg
        join r on pg.dts_beg between r.report_beg and r.report_end
        where
            pg.elapsed_ms >= 0 and  -- 24.09.2014: prevent from display in result 'sp_halt_on_error', 'perf_watch_interval' and so on
            pg.unit not starting with 'srv_recalc_idx_stat_'
        group by
             r.report_beg
            ,r.report_end
            ,pg.unit
    )
    select *
    from c;

    insert into tmp$perf_mon(
         rollup_level
        ,unit
        ,cnt_all
        ,cnt_ok
        ,cnt_err
        ,err_prc
        ,ok_min_ms
        ,ok_max_ms
        ,ok_avg_ms
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_fk_viol
        ,cnt_lk_confl
        ,cnt_user_exc
        ,cnt_stack_trc
        ,cnt_zero_gds
        ,cnt_other_exc
        ,dts_beg
        ,dts_end
    )
    select
         1
        ,unit
        ,sum(cnt_all)
        ,sum(cnt_ok)
        ,sum(cnt_err)
        ,100.00 * sum(cnt_err) / sum(cnt_all)
        ,min(ok_min_ms)
        ,max(ok_max_ms)
        ,max(ok_avg_ms)
        ,sum( cnt_chk_viol ) cnt_chk_viol
        ,sum( cnt_unq_viol ) cnt_unq_viol
        ,sum( cnt_fk_viol ) cnt_fk_viol
        ,sum( cnt_lk_confl ) cnt_lk_confl
        ,sum( cnt_user_exc ) cnt_user_exc
        ,sum( cnt_stack_trc ) cnt_stack_trc
        ,sum( cnt_zero_gds ) cnt_zero_gds
        ,sum( cnt_other_exc ) cnt_other_exc
        ,max( dts_beg )
        ,max( dts_end )
    from tmp$perf_mon
    group by unit; -- overall totals

    if ( :a_show_detl = 0 ) then
        delete from tmp$perf_mon m where m.rollup_level is null;

    -- final resultset (with overall totals first):
    for
        select
            unit, cnt_all, cnt_ok, cnt_err, err_prc, ok_min_ms, ok_max_ms, ok_avg_ms
            ,cnt_chk_viol
            ,cnt_unq_viol
            ,cnt_fk_viol
            ,cnt_lk_confl
            ,cnt_user_exc
            ,cnt_stack_trc
            ,cnt_zero_gds
            ,cnt_other_exc
            ,left(cast(dts_beg as varchar(24)),16)
            ,left(cast(dts_end as varchar(24)),16)
        from tmp$perf_mon
        --order by dy desc nulls first,hr desc, unit
    into unit, cnt_all, cnt_ok, cnt_err, err_prc, ok_min_ms, ok_max_ms, ok_avg_ms
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_fk_viol
        ,cnt_lk_confl
        ,cnt_user_exc
        ,cnt_stack_trc
        ,cnt_zero_gds
        ,cnt_other_exc
        ,job_beg
        ,job_end
    do
        suspend;

end

^ -- srv_mon_perf_detailed

create or alter procedure srv_mon_business_perf_with_exc (
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
    info dm_info,
    unit dm_unit,
    cnt_all integer,
    cnt_ok integer,
    cnt_err integer,
    err_prc numeric(6,2),
    cnt_chk_viol integer,
    cnt_unq_viol integer,
    cnt_lk_confl integer,
    cnt_user_exc integer,
    cnt_other_exc integer,
    job_beg varchar(16),
    job_end varchar(16)
)
AS
declare v_dummy int;
begin

    a_last_hours = abs( coalesce(a_last_hours, 3) );
    a_last_mins = coalesce(a_last_mins, 0);
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    delete from tmp$perf_mon where 1=1;
    -- call to fill tmp$perf_mon with ONLY aggregated data:
    select count(*) from srv_mon_perf_detailed(:a_last_hours, :a_last_mins, 0) into v_dummy;

    for
        select
             o.info,s.unit, s.cnt_all, s.cnt_ok,s.cnt_err,s.err_prc
            ,s.cnt_chk_viol
            ,s.cnt_unq_viol
            ,s.cnt_lk_confl
            ,s.cnt_user_exc
            ,s.cnt_other_exc
            ,left(cast(s.dts_beg as varchar(24)),16)
            ,left(cast(s.dts_end as varchar(24)),16)
        from business_ops o
        left join tmp$perf_mon s on o.unit=s.unit
        order by o.sort_prior
    into
        info
        ,unit
        ,cnt_all
        ,cnt_ok
        ,cnt_err
        ,err_prc
        ,cnt_chk_viol
        ,cnt_unq_viol
        ,cnt_lk_confl
        ,cnt_user_exc
        ,cnt_other_exc
        ,job_beg
        ,job_end
    do
        suspend;

end

^ -- srv_mon_business_perf_with_exc

create or alter procedure srv_mon_exceptions(
    a_last_hours smallint default 3,
    a_last_mins smallint default 0)
returns (
    fb_gdscode int,
    fb_mnemona type of column fb_errors.fb_mnemona,
    unit type of dm_unit,
    cnt int,
    dts_min timestamp,
    dts_max timestamp
)
as
begin
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    for
        with
        a as(
            -- reduce needed number of minutes from most last event of some SP starts:
            -- 18.07.2014: handle only data which belongs to LAST job.
            -- Record with p.unit = 'perf_watch_interval' is added in
            -- oltp_isql_run_worker.bat before FIRST isql will be launched
            -- for each mode ('sales', 'logist' etc)
            select maxvalue( x.last_job_start_dts, y.last_job_finish_dts ) as last_job_start_dts
            from (
                select p.dts_beg as last_job_start_dts
                from perf_log p
                where p.unit = 'perf_watch_interval'
                order by dts_beg desc rows 1
            ) x
            join
            (
                select dateadd( -abs( :a_last_hours * 60 + :a_last_mins ) minute to p.dts_beg) as last_job_finish_dts
                from perf_log p
                -- nb: do NOT use inner join here (bad plan with sort)
                where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit)
                order by p.dts_beg desc
                rows 1
            ) y
            on 1=1
        )
        select p.fb_gdscode, e.fb_mnemona, p.unit, count(*) cnt, min(p.dts_beg) dts_min, max(p.dts_beg) dts_max
        from perf_log p
        join a on p.dts_beg >= a.last_job_start_dts
        LEFT -- !! some exceptions can missing in fb_errors !!
            join fb_errors e on p.fb_gdscode = e.fb_gdscode
        where
            p.fb_gdscode > 0
            and p.exc_unit='#' -- 10.01.2015, see sp_add_to_abend_log: take in account only those units where exception occured, and skip callers of them
        group by 1,2,3
    into
       fb_gdscode, fb_mnemona, unit, cnt, dts_min, dts_max
    do
        suspend;
end

^ -- srv_mon_exceptions

create or alter procedure srv_mon_perf_trace (
    a_intervals_number smallint default 10,
    a_last_hours smallint default 3,
    a_last_mins smallint default 0
)
returns (
    unit dm_unit
    ,info dm_info
    ,interval_no smallint
    ,cnt_success int
    ,fetches_per_second int
    ,marks_per_second int
    ,reads_to_fetches_prc numeric(6,2)
    ,writes_to_marks_prc numeric(6,2)
    ,interval_beg timestamp
    ,interval_end timestamp
) as
begin

    -- Report based on result of parsing TRACE log which was started by
    -- ISQL session #1 when config parameter trc_unit_perf = 1.
    -- Data for each business operation are displayed separately because
    -- they depends on execution plans and can not be compared each other.
    -- We have to analyze only RATIOS between reads/fetches and writes/marks,
    -- and also values of speed (fetches and marks per second) instead of
    -- absolute their values.

    a_intervals_number = iif( a_intervals_number <= 0, 10, a_intervals_number);
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    for
        with
        a as(
            -- reduce needed number of minutes from most last event of some SP starts:
            -- 18.07.2014: handle only data which belongs to LAST job.
            -- Record with p.unit = 'perf_watch_interval' is added in
            -- oltp_isql_run_worker.bat before FIRST isql will be launched
            select
                maxvalue( x.last_added_watch_row_dts, y.first_measured_start_dts ) as first_job_start_dts
                ,y.last_job_finish_dts
                ,y.intervals_number
            from (
                select p.dts_beg as last_added_watch_row_dts
                from perf_log p
                where p.unit = 'perf_watch_interval'
                order by dts_beg desc rows 1
            ) x
            join (
                select
                    dateadd( p.scan_bak_minutes minute to p.dts_beg) as first_measured_start_dts
                    ,p.dts_beg as last_job_finish_dts
                    ,p.intervals_number
                from
                ( -- since 03.09.2015:
                    select
                        p.*
                        , -abs( :a_last_hours * 60 + :a_last_mins ) as scan_bak_minutes
                        , :a_intervals_number as intervals_number
                    from perf_log p
                ) p
                -- nb: do NOT use inner join here (bad plan with sort)
                where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit)
                order by p.dts_beg desc
                rows 1
            ) y on 1=1
        )
        ,d as(
            select
                a.first_job_start_dts
                ,a.last_job_finish_dts
                ,1+datediff(second from a.first_job_start_dts to a.last_job_finish_dts) / a.intervals_number as sec_for_one_interval
            from a
        )
        --select * from d
        ,p as(
            select
                t.unit
                ,b.info
                ,1+cast(datediff(second from d.first_job_start_dts to t.dts_end) / d.sec_for_one_interval as int) as interval_no
                ,count(*) cnt_success
                ,avg( 1000 * t.fetches / nullif(t.elapsed_ms,0) ) fetches_per_second
                ,avg( 1000 * t.marks / nullif(t.elapsed_ms,0) ) marks_per_second
                ,avg( 100.00 * t.reads/nullif(t.fetches,0) ) reads_to_fetches_prc
                ,avg( 100.00 * t.writes/nullif(t.marks,0) ) writes_to_marks_prc
                --,count( nullif(t.success,0) ) cnt_ok
                --,count( nullif(t.success,1) ) cnt_err
                --,100.00 * count( nullif(t.success,1) ) / count(*) err_prc
                --,avg(  iif( g.fb_gdscode is null, g.elapsed_ms, null ) ) ok_avg_ms
                ,min(d.first_job_start_dts) as first_job_start_dts
                ,min(d.sec_for_one_interval) as sec_for_one_interval
            from trace_stat t
            join business_ops b on t.unit = b.unit
            join d on t.dts_end between d.first_job_start_dts and d.last_job_finish_dts -- only rows which are from THIS measured test run!
            where t.success = 1
            group by 1,2,3
        )
        --select * from p
        ,q as (
            select
                unit
                ,info
                ,interval_no
                ,cnt_success
                ,fetches_per_second
                ,marks_per_second
                ,reads_to_fetches_prc
                ,writes_to_marks_prc
                ,first_job_start_dts
                ,sec_for_one_interval
                ,dateadd( (interval_no-1) * sec_for_one_interval+1 second to first_job_start_dts ) as interval_beg
                ,dateadd( interval_no * sec_for_one_interval second to first_job_start_dts ) as interval_end
            from p
        )
         --select * from q
        select
            unit
            ,info
            ,interval_no
            ,cnt_success
            ,fetches_per_second
            ,marks_per_second
            ,reads_to_fetches_prc
            ,writes_to_marks_prc
            ,interval_beg
            ,interval_end
        from q
        into
            unit
            ,info
            ,interval_no
            ,cnt_success
            ,fetches_per_second
            ,marks_per_second
            ,reads_to_fetches_prc
            ,writes_to_marks_prc
            ,interval_beg
            ,interval_end
    do
        suspend;
end

^ -- srv_mon_perf_trace

create or alter procedure srv_mon_perf_trace_pivot (
    a_intervals_number smallint default 10,
    a_last_hours smallint default 3,
    a_last_mins smallint default 0
)
returns (
    traced_data varchar(30),
    interval_no smallint,
    sp_client_order bigint,
    sp_cancel_client_order bigint,
    sp_supplier_order bigint,
    sp_cancel_supplier_order bigint,
    sp_supplier_invoice bigint,
    sp_cancel_supplier_invoice bigint,
    sp_add_invoice_to_stock bigint,
    sp_cancel_adding_invoice bigint,
    sp_customer_reserve bigint,
    sp_cancel_customer_reserve bigint,
    sp_reserve_write_off bigint,
    sp_cancel_write_off bigint,
    sp_pay_from_customer bigint,
    sp_cancel_pay_from_customer bigint,
    sp_pay_to_supplier bigint,
    sp_cancel_pay_to_supplier bigint,
    srv_make_invnt_saldo bigint,
    srv_make_money_saldo bigint,
    srv_recalc_idx_stat bigint,
    interval_beg timestamp,
    interval_end  timestamp
) as
begin

    -- Report based on result of parsing TRACE log which was started by
    -- ISQL session #1 when config parameter trc_unit_perf = 1.
    -- Data for each business operation are displayed separately because
    -- they depends on execution plans and can not be compared each other.
    -- We have to analyze only RATIOS between reads/fetches and writes/marks,
    -- and also values of speed (fetches and marks per second) instead of
    -- absolute their values.

    a_intervals_number = iif( a_intervals_number <= 0, 10, a_intervals_number);
    a_last_hours = abs( a_last_hours );
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    for
        with recursive
        a as(
            -- reduce needed number of minutes from most last event of some SP starts:
            -- 18.07.2014: handle only data which belongs to LAST job.
            -- Record with p.unit = 'perf_watch_interval' is added in
            -- oltp_isql_run_worker.bat before FIRST isql will be launched
            select
                maxvalue( x.last_added_watch_row_dts, y.first_trace_statd_start_dts ) as first_job_start_dts
                ,y.last_job_finish_dts
                ,y.intervals_number
            from (
                select p.dts_beg as last_added_watch_row_dts
                from perf_log p
                where p.unit = 'perf_watch_interval'
                order by dts_beg desc rows 1
            ) x
            join (
                select
                    dateadd( p.scan_bak_minutes minute to p.dts_beg) as first_trace_statd_start_dts
                    ,p.dts_beg as last_job_finish_dts
                    ,p.intervals_number
                from
                ( -- since 03.09.2015:
                    select
                        p.*
                        , -abs( :a_last_hours * 60 + :a_last_mins ) as scan_bak_minutes
                        , :a_intervals_number as intervals_number
                    from perf_log p
                ) p
                -- nb: do NOT use inner join here (bad plan with sort)
                where exists(select 1 from business_ops b where b.unit=p.unit order by b.unit)
                order by p.dts_beg desc
                rows 1
            ) y on 1=1
        )
        ,d as(
            select
                a.first_job_start_dts
                ,a.last_job_finish_dts
                ,1+datediff(second from a.first_job_start_dts to a.last_job_finish_dts) / a.intervals_number as sec_for_one_interval
            from a
        )
        --select * from d
        ,p as(
            select
                t.unit
                ,b.info
                ,1+cast(datediff(second from d.first_job_start_dts to t.dts_end) / d.sec_for_one_interval as int) as interval_no
                ,count(*) cnt_success
                ,avg( 1000 * t.fetches / nullif(t.elapsed_ms,0) ) fetches_per_second
                ,avg( 1000 * t.marks / nullif(t.elapsed_ms,0) ) marks_per_second
                ,avg( 100.00 * t.reads/nullif(t.fetches,0) ) reads_to_fetches_prc
                ,avg( 100.00 * t.writes/nullif(t.marks,0) ) writes_to_marks_prc
                --,count( nullif(t.success,0) ) cnt_ok
                --,count( nullif(t.success,1) ) cnt_err
                --,100.00 * count( nullif(t.success,1) ) / count(*) err_prc
                --,avg(  iif( g.fb_gdscode is null, g.elapsed_ms, null ) ) ok_avg_ms
                ,min(d.first_job_start_dts) as first_job_start_dts
                ,min(d.sec_for_one_interval) as sec_for_one_interval
            from trace_stat t
            join business_ops b on t.unit = b.unit
            join d on t.dts_end between d.first_job_start_dts and d.last_job_finish_dts -- only rows which are from THIS trace_statd test run!
            where t.success = 1
            group by 1,2,3
        )
        --select * from p
        ,q as (
            select
                unit
                ,info
                ,interval_no
                ,cnt_success
                ,fetches_per_second
                ,marks_per_second
                ,reads_to_fetches_prc
                ,writes_to_marks_prc
                ,first_job_start_dts
                ,sec_for_one_interval
                ,dateadd( (interval_no-1) * sec_for_one_interval+1 second to first_job_start_dts ) as interval_beg
                ,dateadd( interval_no * sec_for_one_interval second to first_job_start_dts ) as interval_end
            from p
        )
         --select * from q
        , n as (
          select 1 i from rdb$database union all
          select n.i+1 from n where n.i+1<=4
        )

        select
            decode(n.i, 1, 'fetches per second', 2, 'marks per second', 3, 'reads/fetches*100', 'writes/marks*100') as trace_stat
            ,interval_no
            ,max( iif(unit='sp_client_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as                  sp_client_order
            ,max( iif(unit='sp_cancel_client_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as           sp_cancel_client_order
            ,max( iif(unit='sp_supplier_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as                sp_supplier_order
            ,max( iif(unit='sp_cancel_supplier_order', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as         sp_cancel_supplier_order
            ,max( iif(unit='sp_supplier_invoice', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              sp_supplier_invoice
            ,max( iif(unit='sp_cancel_supplier_invoice', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as       sp_cancel_supplier_invoice
            ,max( iif(unit='sp_add_invoice_to_stock', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as          sp_add_invoice_to_stock
            ,max( iif(unit='sp_cancel_adding_invoice', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as         sp_cancel_adding_invoice
            ,max( iif(unit='sp_customer_reserve', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              sp_customer_reserve
            ,max( iif(unit='sp_cancel_customer_reserve', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as       sp_cancel_customer_reserve
            ,max( iif(unit='sp_reserve_write_off', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             sp_reserve_write_off
            ,max( iif(unit='sp_cancel_write_off', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              sp_cancel_write_off
            ,max( iif(unit='sp_pay_from_customer', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             sp_pay_from_customer
            ,max( iif(unit='sp_cancel_pay_from_customer', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as      sp_cancel_pay_from_customer
            ,max( iif(unit='sp_pay_to_supplier', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as               sp_pay_to_supplier
            ,max( iif(unit='sp_cancel_pay_to_supplier', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as        sp_cancel_pay_to_supplier
            ,max( iif(unit='srv_make_invnt_saldo', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             srv_make_invnt_saldo
            ,max( iif(unit='srv_make_money_saldo', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as             srv_make_money_saldo
            ,max( iif(unit='srv_recalc_idx_stat', decode(n.i, 1, fetches_per_second, 2, marks_per_second, 3, reads_to_fetches_prc, writes_to_marks_prc), null) ) as              srv_recalc_idx_stat
            ,interval_beg
            ,interval_end
        from q
        cross join n
        group by n.i, interval_no, interval_beg, interval_end
        into
            traced_data
            ,interval_no
            ,sp_client_order
            ,sp_cancel_client_order
            ,sp_supplier_order
            ,sp_cancel_supplier_order
            ,sp_supplier_invoice
            ,sp_cancel_supplier_invoice
            ,sp_add_invoice_to_stock
            ,sp_cancel_adding_invoice
            ,sp_customer_reserve
            ,sp_cancel_customer_reserve
            ,sp_reserve_write_off
            ,sp_cancel_write_off
            ,sp_pay_from_customer
            ,sp_cancel_pay_from_customer
            ,sp_pay_to_supplier
            ,sp_cancel_pay_to_supplier
            ,srv_make_invnt_saldo
            ,srv_make_money_saldo
            ,srv_recalc_idx_stat
            ,interval_beg
            ,interval_end
    do
        suspend;
end

^ -- srv_mon_perf_trace_pivot


create or alter procedure srv_mon_idx
returns (
    tab_name dm_dbobj,
    idx_name dm_dbobj,
    last_stat double precision,
    curr_stat double precision,
    diff_stat double precision,
    last_done timestamp
) as
    declare v_last_recalc_trn bigint;
begin

    select p.trn_id
    from perf_log p
    where p.unit starting with 'srv_recalc_idx_stat_'
    order by p.trn_id desc rows 1
    into v_last_recalc_trn;

    -- SP for analyzing results of index statistics recalculation:
    -- ###########################################################
    for
        select
            t.tab_name
            ,t.idx_name
            ,t.last_stat
            ,r.rdb$statistics
            ,t.last_stat - r.rdb$statistics
            ,t.last_done
        from (
            select
                g.info as tab_name
                ,substring(g.unit from char_length('srv_recalc_idx_stat_')+1 ) as idx_name
                ,g.aux1 as last_stat
                ,g.dts_end as last_done
            from perf_log g
            where g.trn_id = :v_last_recalc_trn
        ) t
        join rdb$indices r on t.idx_name = r.rdb$index_name
    into
        tab_name,
        idx_name,
        last_stat,
        curr_stat,
        diff_stat,
        last_done
    do suspend;
end

^ -- srv_mon_idx
--------------------------------------------------------------------------------

create or alter procedure srv_fill_mon(
    a_rowset bigint default null -- not null ==> gather info from tmp$mo_log (2 rows); null ==> gather info from ALL attachments
)
returns(
    rows_added int
)
as
    declare v_curr_trn bigint;
    declare v_total_stat_added_rows int = 0;
    declare v_table_stat_added_rows int = 0;
    declare v_dummy bigint;
    declare v_info dm_info;
    declare v_this dm_dbobj = 'srv_fill_mon';
begin
    rows_added = -1;

    if ( fn_remote_process() NOT containing 'IBExpert'
         and
         coalesce(rdb$get_context('USER_SESSION', 'ENABLE_MON_QUERY'), 0) = 0
       ) then
    begin
        rdb$set_context( 'USER_SESSION','MON_INFO', 'mon$_dis!'); -- to be displayed in log of 1run_oltp_emul.bat
        suspend;
        --###
        exit;
        --###
    end
    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    v_curr_trn = current_transaction;
    if ( a_rowset is NULL  ) then -- gather data from ALL attachments (separate call of this SP)
        begin
            in autonomous transaction do
            begin
                insert into mon_log(
                    ----------------------- ALL attachments: set #1
                    --dts,
                    sec,
                    usr,
                    att_id,
                    ----------------------- ALL attachments: set #2
                    pg_reads,
                    pg_writes,
                    pg_fetches,
                    pg_marks,
                    ----------------------- ALL attachments: set #3
                    rec_inserts,
                    rec_updates,
                    rec_deletes,
                    rec_backouts,
                    rec_purges,
                    rec_expunges,
                    rec_seq_reads,
                    rec_idx_reads,
                    ----------------------- ALL attachments: set #4
                    rec_rpt_reads,
                    bkv_reads, -- mon$backversion_reads, since rev. 60012, 28.08.2014 19:16
                    frg_reads,
                    ----------------------- ALL attachments: set #5
                    rec_locks,
                    rec_waits,
                    rec_confl,
                    ----------------------- ALL attachments: set #6
                    mem_used,
                    mem_alloc,
                    ----------------------- ALL attachments: set #7
                    stat_id,
                    server_pid,
                    remote_pid,
                    ----------------------- ALL attachments: set #8
                    ip,
                    remote_process,
                    dump_trn,
                    unit,
                    add_info
                )
                -- 09.08.2014
                select     
                    ----------------------- ALL attachments: set #1
                    --current_time dts
                    datediff(second from current_date-1 to current_timestamp ) sec
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
                    ,r.mon$record_rpt_reads
                    ,r.mon$backversion_reads -- since rev. 60012, 28.08.2014 19:16
                    ,r.mon$fragment_reads
                    ----------------------- ALL attachments: set #5
                    ,r.mon$record_locks
                    ,r.mon$record_waits
                    ,r.mon$record_conflicts
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
                    ,:v_curr_trn
                    ,:v_this
                    ,'all_attaches'
                from mon$attachments a     
                --left join mon$statements s on a.mon$attachment_id = s.mon$attachment_id     
                left join mon$memory_usage u on a.mon$stat_id=u.mon$stat_id     
                left join mon$io_stats i on a.mon$stat_id=i.mon$stat_id     
                left join mon$record_stats r on a.mon$stat_id=r.mon$stat_id     
                where     
                  a.mon$attachment_id<>current_connection 
                  order by 
                  iif( a.mon$user in ('Garbage Collector', 'Cache Writer'  )
                      ,1 
                      , iif( a.mon$remote_process containing 'gfix'
                            ,2 
                            ,iif( a.mon$remote_process containing 'nbackup'
                                  or a.mon$remote_process containing 'gbak'
                                  or a.mon$remote_process containing 'gstat'
                                 ,3 
                                 ,1000+a.mon$attachment_id
                                 )
                            )
                      )
                ;
                v_total_stat_added_rows = row_count;
            end -- in AT
        end
    else -- input arg :a_rowset is NOT null ==> gather data from tmp$mon_log (were added there in calls before and after application unit from tmp_random_run.sql)
        begin
            insert into mon_log(
                ---------------- CURRENT attachment only: set #1
                rowset,
                --dts,
                sec,
                usr,
                att_id,
                trn_id,
                ---------------- CURRENT attachment only: set #2
                pg_reads,
                pg_writes,
                pg_fetches,
                pg_marks,
                ---------------- CURRENT attachment only: set #3
                rec_inserts,
                rec_updates,
                rec_deletes,
                rec_backouts,
                rec_purges,
                rec_expunges,
                --------------- CURRENT attachment only: set #4
                rec_seq_reads,
                rec_idx_reads,
                rec_rpt_reads,
                --------------- CURRENT attachment only: set #5
                bkv_reads, -- mon$backversion_reads, since rev. 60012, 28.08.2014 19:16
                frg_reads,
                --------------- CURRENT attachment only: set #6
                rec_locks,
                rec_waits,
                rec_confl,
                --------------- CURRENT attachment only: set #7
                mem_used,
                mem_alloc,
                --------------- CURRENT attachment only: set #8
                stat_id,
                server_pid,
                remote_pid,
                --------------- CURRENT attachment only: set #9
                ip,
                remote_process,
                dump_trn,
                --------------- CURRENT attachment only: set #10
                unit,
                add_info,
                fb_gdscode,
                elapsed_ms -- added 08.09.2014
            )
            select
                -------------------------------  set #1: dts, sec, usr, att_id
                 t.rowset
                --,current_time
                ,datediff(second from current_date-1 to current_timestamp )
                ,current_user
                ,current_connection
                ,max( t.trn_id )
                ------------ CURRENT attachment only: set #2: pg_reads,pg_writes,pg_fetches,pg_marks
                ,sum( t.mult * t.pg_reads)   -- t.mult = -1 for first meause, +1 for second -- see srv_fill_tmp_mon
                ,sum( t.mult * t.pg_writes)
                ,sum( t.mult * t.pg_fetches)
                ,sum( t.mult * t.pg_marks)
                ------------ CURRENT attachment only: set #3: inserts,updates,deletes,backouts,purges,expunges,
                ,sum( t.mult * t.rec_inserts)
                ,sum( t.mult * t.rec_updates)
                ,sum( t.mult * t.rec_deletes)
                ,sum( t.mult * t.rec_backouts)
                ,sum( t.mult * t.rec_purges)
                ,sum( t.mult * t.rec_expunges)
                ------------ CURRENT attachment only: set #4: seq_reads,idx_reads,rpt_reads
                ,sum( t.mult * t.rec_seq_reads)
                ,sum( t.mult * t.rec_idx_reads)
                ,sum( t.mult * t.rec_rpt_reads) -- <<< since rev. 60005 27.08.2014 18:52
                ------------ CURRENT attachment only: set #5: ver_reads, frg_reads (since rev. 59953 05.08.2014 08:46)
                ,sum( t.mult * t.bkv_reads) -- mon$backversion_reads, since rev. 60012, 28.08.2014 19:16
                ,sum( t.mult * t.frg_reads)
                ------------- CURRENT attachment only: set #6: rec_locks,rec_waits,rec_confl (since rev. 59953)
                ,sum( t.mult * t.rec_locks)
                ,sum( t.mult * t.rec_waits)
                ,sum( t.mult * t.rec_confl)
                -------------- CURRENT attachment only: set #7: mem_used,mem_alloc
                ,sum( t.mult * t.mem_used)
                ,sum( t.mult * t.mem_alloc)
                -------------- CURRENT attachment only: set #8 stat_id,server_pid,remote_pid
                ,max( t.stat_id )
                ,max( t.server_pid )
                ,rdb$get_context('SYSTEM', 'CLIENT_PID')
                --------------- CURRENT attachment only: set #9: ip,remote_process,dump_trn
                ,fn_remote_address() --  rdb$get_context('SYSTEM', 'CLIENT_ADDRESS')
                ,right( fn_remote_process(), 30) -- rdb$get_context('SYSTEM', 'CLIENT_PROCESS')
                ,:v_curr_trn
                --------------- CURRENT attachment only: set #10 unit,add_info
                ,max(unit)
                ,max(add_info)
                ,max(fb_gdscode)
                ,datediff(millisecond from min(t.dts) to max(t.dts) )
            from tmp$mon_log t
            where t.rowset = :a_rowset
            group by t.rowset;

            v_total_stat_added_rows = row_count;

            delete from tmp$mon_log t where t.rowset = :a_rowset;

            -----------------------------------------
            -- 29.08.2014: gather data from tmp$mon_log_table_stats to mon_log_table_stats
            insert into mon_log_table_stats(
                 rowset                     --  1
                ,table_name
                ,att_id
                ,table_id
                ,is_system_table            --  5
                ,rel_type
                ,unit
                ,fb_gdscode
                ,rec_inserts
                ,rec_updates                -- 10
                ,rec_deletes
                ,rec_backouts
                ,rec_purges
                ,rec_expunges
                ,rec_seq_reads              -- 15
                ,rec_idx_reads
                ,rec_rpt_reads
                ,bkv_reads
                ,frg_reads
                ,rec_locks                  -- 20
                ,rec_waits
                ,rec_confl
                ,trn_id
                ,stat_id                    -- 24
            )
            select
                 s.rowset                                      --  1
                ,s.table_name as tab_name -- :: NB :: mon$table_stats has field mon$table_NAME rather than mon$table_ID
                ,current_connection as att_id
                ,max( r.rdb$relation_id ) as tab_id
                ,max( r.rdb$system_flag ) as sys_flag          --  5
                ,max( r.rdb$relation_type ) as rel_type
                ,max( s.unit ) -- can be NULL before random choise of app unit!
                ,sum( s.mult * s.fb_gdscode )   -- t.mult = -1 for first measure, +1 for second -- see srv_fill_tmp_mon
                ,sum( s.mult * s.rec_inserts )
                ,sum( s.mult * s.rec_updates )                 -- 10
                ,sum( s.mult * s.rec_deletes )
                ,sum( s.mult * s.rec_backouts )
                ,sum( s.mult * s.rec_purges )
                ,sum( s.mult * s.rec_expunges )
                ,sum( s.mult * s.rec_seq_reads )               -- 15
                ,sum( s.mult * s.rec_idx_reads )
                ,sum( s.mult * s.rec_rpt_reads )
                ,sum( s.mult * s.bkv_reads )
                ,sum( s.mult * s.frg_reads )
                ,sum( s.mult * s.rec_locks )                   -- 20
                ,sum( s.mult * s.rec_waits )
                ,sum( s.mult * s.rec_confl )
                ,max( s.trn_id )
                ,max( s.stat_id )                              -- 24
            from tmp$mon_log_table_stats s
            join rdb$relations r on s.table_name = r.rdb$relation_name
            where s.rowset = :a_rowset
            group by s.rowset, s.table_name;

            v_table_stat_added_rows = row_count;

            delete from tmp$mon_log_table_stats s where s.rowset = :a_rowset;

        end

    rows_added = v_total_stat_added_rows + v_table_stat_added_rows;
    v_info='rows added: total_stat='||v_total_stat_added_rows||', table_stat='||v_table_stat_added_rows;
    -- ::: nb ::: do NOT use the name 'ADD_INFO', it is reserved to common app unit result!
    rdb$set_context( 'USER_SESSION','MON_INFO', v_info ); -- to be displayed in log of 1run_oltp_emul.bat
    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(0, v_this, null, v_info );

    suspend;

when any do
    begin
        rdb$set_context( 'USER_SESSION','MON_INFO', 'gds='||gdscode );
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            '',
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- srv_fill_mon

--------------------------------------------------------------------------------

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
as
    declare v_mult dm_sign;
    declare v_curr_trn bigint;
    declare v_this dm_dbobj = 'srv_fill_tmp_mon';
    declare v_total_stat_added_rows int;
    declare v_table_stat_added_rows int;
    declare v_info dm_info;
begin
    rows_added = -1;

    if ( fn_remote_process() NOT containing 'IBExpert'
         and
         coalesce(rdb$get_context('USER_SESSION', 'ENABLE_MON_QUERY'), 0) = 0
       ) then
    begin
        rdb$set_context( 'USER_SESSION','MON_INFO', 'mon$_dis!'); -- to be displayed in log of 1run_oltp_emul.bat
        suspend;
        --###
        exit;
        --###
    end
    -- Check that table `ext_stoptest` (external text file) is EMPTY,
    -- otherwise raises e`xception to stop test:
    execute procedure sp_check_to_stop_work;

    -- add to performance log timestamp about start/finish this unit:
    execute procedure sp_add_perf_log(1, v_this);

    v_mult = iif( exists(select * from tmp$mon_log g where g.rowset is not distinct from :a_rowset), 1, -1);
    v_curr_trn = iif( v_mult = 1, current_transaction, null);

    insert into tmp$mon_log( -- NB: on commit PRESERVE rows!
        -- mon$io_stats:
        pg_reads
       ,pg_writes
       ,pg_fetches
       ,pg_marks
        -- mon$record_stats:     
       ,rec_inserts
       ,rec_updates
       ,rec_deletes
       ,rec_backouts
       ,rec_purges
       ,rec_expunges
       ,rec_seq_reads
       ,rec_idx_reads

       ,rec_rpt_reads
       ,bkv_reads -- mon$backversion_reads, since rev. 60012, 28.08.2014 19:16
       ,frg_reads

       ,rec_locks
       ,rec_waits
       ,rec_confl
       ------------
       ,mem_used
       ,mem_alloc
       ,stat_id
       ,server_pid
       ------------
       ,rowset
       ,unit
       ,add_info
       ,fb_gdscode
       ,mult
       ,trn_id
    )
    select
        -- mon$io_stats:
         i.mon$page_reads
        ,i.mon$page_writes
        ,i.mon$page_fetches
        ,i.mon$page_marks
        -- mon$record_stats:     
        ,r.mon$record_inserts
        ,r.mon$record_updates
        ,r.mon$record_deletes
        ,r.mon$record_backouts
        ,r.mon$record_purges
        ,r.mon$record_expunges
        ,r.mon$record_seq_reads
        ,r.mon$record_idx_reads
    
        ,r.mon$record_rpt_reads
        ,r.mon$backversion_reads -- since rev. 60012, 28.08.2014 19:16
        ,r.mon$fragment_reads
    
        ,r.mon$record_locks
        ,r.mon$record_waits
        ,r.mon$record_conflicts
        ------------------------
        ,u.mon$memory_used
        ,u.mon$memory_allocated
        ,a.mon$stat_id
        ,a.mon$server_pid
        ------------------------
        ,:a_rowset
        ,:a_unit
        ,:a_info
        ,:a_gdscode
        ,:v_mult
        ,:v_curr_trn
    from mon$attachments a
    --left join mon$statements s on a.mon$attachment_id = s.mon$attachment_id     
    left join mon$memory_usage u on a.mon$stat_id=u.mon$stat_id     
    left join mon$io_stats i on a.mon$stat_id=i.mon$stat_id     
    left join mon$record_stats r on a.mon$stat_id=r.mon$stat_id     
    where     
      a.mon$attachment_id = current_connection;

    v_total_stat_added_rows = row_count;

    -- 29.08.2014: use also mon$table_stats to analyze per table:
    insert into tmp$mon_log_table_stats(
        table_name
        ,rec_inserts
        ,rec_updates
        ,rec_deletes
        ,rec_backouts
        ,rec_purges
        ,rec_expunges
        ---------
        ,rec_seq_reads
        ,rec_idx_reads
        ,rec_rpt_reads
        ,bkv_reads
        ,frg_reads
        ---------
        ,rec_locks
        ,rec_waits
        ,rec_confl
        ---------
        ,rowset
        ,unit
        ,fb_gdscode
        ,stat_id
        ,mult
        ,trn_id
    )
    select
        t.mon$table_name
        ,r.mon$record_inserts
        ,r.mon$record_updates
        ,r.mon$record_deletes
        ,r.mon$record_backouts
        ,r.mon$record_purges
        ,r.mon$record_expunges
        -----------
        ,r.mon$record_seq_reads
        ,r.mon$record_idx_reads
        ,r.mon$record_rpt_reads
        ,r.mon$backversion_reads
        ,r.mon$fragment_reads
        -----------
        ,r.mon$record_locks
        ,r.mon$record_waits
        ,r.mon$record_conflicts
        ------------
        ,:a_rowset
        ,:a_unit
        ,:a_gdscode
        ,a.mon$stat_id
        ,:v_mult
        ,:v_curr_trn
    from mon$record_stats r
    join mon$table_stats t on r.mon$stat_id = t.mon$record_stat_id
    join mon$attachments a on t.mon$stat_id = a.mon$stat_id
    where
        a.mon$attachment_id = current_connection
        and ( :a_ignore_system_tables = 0 or t.mon$table_name not starting with 'RDB$' );

    v_table_stat_added_rows = row_count;

    -- add to performance log timestamp about start/finish this unit:
    v_info = 'unit: '||coalesce(a_unit,'<?>')
            || ', rowset='||coalesce(a_rowset,'<?>')
            || ', rows added: total_stat='||v_total_stat_added_rows||', table_stat='||v_table_stat_added_rows;
    execute procedure sp_add_perf_log(0, v_this, null, v_info );

    rows_added = v_total_stat_added_rows + v_table_stat_added_rows; -- out arg

    suspend;

when any do
    begin
        -- ::: nb ::: do NOT use the name 'ADD_INFO', it;s reserved to common app unit result!
        rdb$set_context( 'USER_SESSION','MON_INFO', 'gds='||gdscode ); -- to be displayed in isql output, see 1run_oltp_emul.bat
        execute procedure sp_add_to_abend_log(
            '',
            gdscode,
            '',
            v_this,
            fn_halt_sign(gdscode) -- ::: nb ::: 1 ==> force get full stack, ignoring settings `DISABLE_CALL_STACK` value, and HALT test
        );

        --#######
        exception;  -- ::: nb ::: anonimous but in when-block!
        --#######
    end

end

^ -- srv_fill_tmp_mon

create or alter procedure srv_mon_stat_per_units (
    a_last_hours smallint default 3,
    a_last_mins smallint default 0 )
returns (
    unit dm_unit
   ,iter_counts bigint
   ,avg_elap_ms bigint
   ,avg_rec_reads_sec numeric(12,2)
   ,avg_rec_dmls_sec numeric(12,2)
   ,avg_bkos_sec numeric(12,2)
   ,avg_purg_sec numeric(12,2)
   ,avg_xpng_sec numeric(12,2)
   ,avg_fetches_sec numeric(12,2)
   ,avg_marks_sec numeric(12,2)
   ,avg_reads_sec numeric(12,2)
   ,avg_writes_sec numeric(12,2)
   ,avg_seq bigint
   ,avg_idx bigint
   ,avg_rpt bigint
   ,avg_bkv bigint
   ,avg_frg bigint
   ,avg_bkv_per_rec numeric(12,2)
   ,avg_frg_per_rec numeric(12,2)
   ,avg_ins bigint
   ,avg_upd bigint
   ,avg_del bigint
   ,avg_bko bigint
   ,avg_pur bigint
   ,avg_exp bigint
   ,avg_fetches bigint
   ,avg_marks bigint
   ,avg_reads bigint
   ,avg_writes bigint
   ,avg_locks bigint
   ,avg_confl bigint
   ,max_seq bigint
   ,max_idx bigint
   ,max_rpt bigint
   ,max_bkv bigint
   ,max_frg bigint
   ,max_bkv_per_rec numeric(12,2)
   ,max_frg_per_rec numeric(12,2)
   ,max_ins bigint
   ,max_upd bigint
   ,max_del bigint
   ,max_bko bigint
   ,max_pur bigint
   ,max_exp bigint
   ,max_fetches bigint
   ,max_marks bigint
   ,max_reads bigint
   ,max_writes bigint
   ,max_locks bigint
   ,max_confl bigint
   ,job_beg varchar(16)
   ,job_end varchar(16)
) as
    declare v_report_beg timestamp;
    declare v_report_end timestamp;
begin
    -- SP for detailed performance analysis: count of operations
    -- (NOT only business ops; including BOTH successful and failed ones),
    -- count of errors (including by their types)
    a_last_hours = abs( coalesce(a_last_hours, 3) );
    a_last_mins = coalesce(a_last_mins, 0);
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    select p.last_launch_beg, p.last_launch_end
    from srv_get_last_launch_beg_end( :a_last_hours, :a_last_mins ) p
    into v_report_beg, v_report_end;

    for
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
            ,left(cast(:v_report_beg as varchar(24)),16)
            ,left(cast(:v_report_end as varchar(24)),16)
        from mon_log m
        where m.dts between :v_report_beg and :v_report_end
        group by unit
    into
        unit
       ,iter_counts
       ,avg_elap_ms
       ,avg_rec_reads_sec
       ,avg_rec_dmls_sec
       ,avg_bkos_sec
       ,avg_purg_sec
       ,avg_xpng_sec
       ,avg_fetches_sec
       ,avg_marks_sec
       ,avg_reads_sec
       ,avg_writes_sec
       ,avg_seq
       ,avg_idx
       ,avg_rpt
       ,avg_bkv
       ,avg_frg
       ,avg_bkv_per_rec
       ,avg_frg_per_rec
       ,avg_ins
       ,avg_upd
       ,avg_del
       ,avg_bko
       ,avg_pur
       ,avg_exp
       ,avg_fetches
       ,avg_marks
       ,avg_reads
       ,avg_writes
       ,avg_locks
       ,avg_confl
       ,max_seq
       ,max_idx
       ,max_rpt
       ,max_bkv
       ,max_frg
       ,max_bkv_per_rec
       ,max_frg_per_rec
       ,max_ins
       ,max_upd
       ,max_del
       ,max_bko
       ,max_pur
       ,max_exp
       ,max_fetches
       ,max_marks
       ,max_reads
       ,max_writes
       ,max_locks
       ,max_confl
       ,job_beg
       ,job_end
    do
        suspend;
end

^ -- srv_mon_stat_per_units

create or alter procedure srv_mon_stat_per_tables (
    a_last_hours smallint default 3,
    a_last_mins smallint default 0 )
returns (
    table_name dm_dbobj
   ,unit dm_unit
   ,iter_counts bigint
   ,avg_seq bigint
   ,avg_idx bigint
   ,avg_rpt bigint
   ,avg_bkv bigint
   ,avg_frg bigint
   ,avg_bkv_per_rec numeric(12,2)
   ,avg_frg_per_rec numeric(12,2)
   ,avg_ins bigint
   ,avg_upd bigint
   ,avg_del bigint
   ,avg_bko bigint
   ,avg_pur bigint
   ,avg_exp bigint
   ,avg_locks bigint
   ,avg_confl bigint
   --,elapsed_minutes int
   ,max_seq bigint
   ,max_idx bigint
   ,max_rpt bigint
   ,max_bkv bigint
   ,max_frg bigint
   ,max_bkv_per_rec numeric(12,2)
   ,max_frg_per_rec numeric(12,2)
   ,max_ins bigint
   ,max_upd bigint
   ,max_del bigint
   ,max_bko bigint
   ,max_pur bigint
   ,max_exp bigint
   ,max_locks bigint
   ,max_confl bigint
   ,job_beg varchar(16)
   ,job_end varchar(16)
) as
    declare v_report_beg timestamp;
    declare v_report_end timestamp;
begin
    -- SP for detailed performance analysis: count of operations
    -- (NOT only business ops; including BOTH successful and failed ones),
    -- count of errors (including by their types)
    a_last_hours = abs( coalesce(a_last_hours, 3) );
    a_last_mins = coalesce(a_last_mins, 0);
    a_last_mins = iif( a_last_mins between 0 and 59, a_last_mins, 0 );

    select p.last_launch_beg, p.last_launch_end
    from srv_get_last_launch_beg_end( :a_last_hours, :a_last_mins ) p
    into v_report_beg, v_report_end;

    for
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
        --,datediff( minute from min(t.dts) to max(t.dts) ) elapsed_minutes
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
        ,left(cast(:v_report_beg as varchar(24)),16)
        ,left(cast(:v_report_end as varchar(24)),16)
    from mon_log_table_stats t
    where
        t.dts between :v_report_beg and :v_report_end
        and
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
    group by t.table_name, t.unit
    into
        table_name
       ,unit
       ,iter_counts
       ,avg_seq
       ,avg_idx
       ,avg_rpt
       ,avg_bkv
       ,avg_frg
       ,avg_bkv_per_rec
       ,avg_frg_per_rec
       ,avg_ins
       ,avg_upd
       ,avg_del
       ,avg_bko
       ,avg_pur
       ,avg_exp
       ,avg_locks
       ,avg_confl
       --,elapsed_minutes
       ,max_seq
       ,max_idx
       ,max_rpt
       ,max_bkv
       ,max_frg
       ,max_bkv_per_rec
       ,max_frg_per_rec
       ,max_ins
       ,max_upd
       ,max_del
       ,max_bko
       ,max_pur
       ,max_exp
       ,max_locks
       ,max_confl
       ,job_beg
       ,job_end
    do
        suspend;
end

^ -- srv_mon_stat_per_tables

create or alter procedure srv_get_report_name(
     a_format varchar(20) default 'regular' -- 'regular' | 'benchmark'
    ,a_build varchar(50) default '' -- WI-V3.0.0.32136 or just '32136'
    ,a_num_of_sessions int default -1
    ,a_test_time_minutes int default -1
    ,a_prefix varchar(255) default ''
    ,a_suffix varchar(255) default ''
) returns (
    report_file varchar(255) -- full name of final report
    ,start_at varchar(15) -- '20150223_1527': timestamp of test_time phase start
    ,fb_arch varchar(50) -- 'ss30' | 'sc30' | 'cs30'
    ,overall_perf varchar(50) -- 'score_07548'
    ,fw_setting varchar(20) -- 'fw__on' | 'fw_off'
    ,load_time varchar(50) -- '03h00m'
    ,load_att varchar(50) -- '150_att'
    ,heavy_load_ddl varchar(50) -- only when a_format='benchmark': solid' | 'split'
    ,compound_1st_col varchar(50) -- only when a_format='benchmark': 'most__selective_1st' | 'least_selective_1st'
    ,compound_idx_num varchar(50) -- only when a_format='benchmark': 'one_index' | 'two_indxs'
)
as
    declare v_test_finish_state varchar(50);
    declare v_tab_name dm_dbobj;
    declare v_idx_name dm_dbobj;
    declare v_min_idx_key varchar(255);
    declare v_max_idx_key varchar(255);
    declare v_test_time int;
    declare v_num_of_sessions int;
    declare v_dts_beg timestamp;
    declare v_dts_end timestamp;
    declare k smallint;
    declare v_fb_major_vers varchar(10);
begin

    -- Aux. SP for returning FILE NAME of final report which does contain all
    -- valuable FB, database and test params
    -- Sample:
    -- select * from srv_get_report_name('regular', 31236)
    -- select * from srv_get_report_name('benchmark', 31236)

    select d1 || d2
    from (
        select d1, left(s, position('.' in s)-1) d2
        from (
            select left(r,  position('.' in r)-1) d1, substring(r from 1+position('.' in r)) s
            from (
              select rdb$get_context('SYSTEM','ENGINE_VERSION') r from rdb$database
            )
        )
    ) into v_fb_major_vers; -- '2.5.0' ==> '25'; '3.0.0' ==> '30'; '19.17.1' ==> '1917' :-)

    select p.fb_arch from sys_get_fb_arch p into fb_arch;
    fb_arch =
        iif( fb_arch containing 'superserver' or upper(fb_arch) starting with upper('ss'), 'ss'
            ,iif( fb_arch containing 'superclassic' or upper(fb_arch) starting with upper('sc'), 'sc'
                ,iif( fb_arch containing 'classic' or upper(fb_arch) starting with upper('cs'), 'cs'
                    ,'fb'
                    )
                )
           )
        || v_fb_major_vers -- prev: iif( rdb$get_context('SYSTEM','ENGINE_VERSION') starting with '2.5', '25', '30' )
    ;
    fw_setting='fw' || iif( (select mon$forced_writes from mon$database)= 1,'__on','_off');

    select
        'score_'||lpad( cast( coalesce(aux1,0) as int ), iif( coalesce(aux1,0) < 99999, 5, 18 ) , '0' )
        ,datediff(minute from p.dts_beg to p.dts_end)
        ,p.dts_beg, p.dts_end
    from perf_log p
    where p.unit = 'perf_watch_interval'
    order by p.dts_beg desc
    rows 1
    into overall_perf, v_test_time, v_dts_beg, v_dts_end;

    v_test_finish_state = null;
    if ( a_test_time_minutes = -1 ) then -- call AFTER test finish, when making final report
        begin
            select 'ABEND_GDS_'||p.fb_gdscode
            from perf_log p
            where p.unit = 'sp_halt_on_error' and p.fb_gdscode >= 0
            order by p.dts_beg desc
            rows 1
            into v_test_finish_state; -- will remain NULL if not found ==> test finished NORMAL.
        end
    else -- a_test_time_minutes > = 0
        begin
           -- call from main batch (1run_oltp_emul) just BEFORE all ISQL
           -- sessions will be launched: display *estimated* name of report
            overall_perf = 'score_' || lpad('',5,'X');
            v_test_time = a_test_time_minutes;
        end

    select left(ansi_dts, 13) from sys_timestamp_to_ansi( coalesce(:v_dts_beg, current_timestamp))
    into start_at;

    v_test_time = coalesce(v_test_time,0);
    load_time = lpad(cast(v_test_time/60 as int),2,'_')||'h' || lpad(mod(v_test_time,60),2,'0')||'m';

    if ( a_num_of_sessions = -1 ) then
        -- Use *actual* number of ISQL sessions that were participate in this test run.
        -- This case is used when final report is created AFTER test finish, from oltp_isql_run_worker.bat (.sh):
        select count(distinct e.att_id)
        from perf_estimated e
        into v_num_of_sessions;
    else
        -- Use *declared* number of ISQL sessions that *will* be participate in this test run:
        -- (this case is used when we diplay name of report BEFORE launching ISQL sessions, in 1run_oltp_emul.bat (.sh) script):
        v_num_of_sessions= a_num_of_sessions;

    load_att = lpad( coalesce(v_num_of_sessions, '0'), 3, '_') || '_att';

    k = position('.' in reverse(a_build));
    a_build = iif( k > 0, reverse(left(reverse(a_build), k - 1)), a_build );

    if ( a_format = 'regular' ) then
        -- 20151102_2219_score_06578_build_32136_ss30__0h30m__10_att_fw_off.txt 
        report_file =
            start_at
            || '_' || coalesce( v_test_finish_state, overall_perf )
            || iif( a_build > '', '_build_' || a_build, '' )
            || '_' || fb_arch
            || '_' || load_time
            || '_' || load_att
            || '_' || fw_setting
        ;
    else if (a_format = 'benchmark') then
        begin
            for
                select
                    tab_name,
                    min(idx_key) as min_idx_key,
                    max(idx_key) as max_idx_key
                from z_qd_indices_ddl z
                group by tab_name
                rows 1
            into
                v_tab_name, v_min_idx_key, v_max_idx_key
            do begin
        
                heavy_load_ddl = iif( upper(v_tab_name)=upper('qdistr'), 'solid', 'split' );
        
                if ( upper(v_min_idx_key) starting with upper('ware_id') or upper(v_max_idx_key) starting with upper('ware_id')  ) then
                    compound_1st_col = 'most__sel_1st';
                else if ( upper(v_min_idx_key) starting with upper('snd_optype_id') or upper(v_max_idx_key) starting with upper('snd_optype_id')  ) then
                    compound_1st_col = 'least_sel_1st';
        
                if ( v_min_idx_key = v_max_idx_key ) then
                    compound_idx_num = 'one_index';
                else
                    compound_idx_num = 'two_indxs';
            end
            -- ss30_fw__on_solid_most__sel_1st_two_indxs_loadtime_180m_by_100_att_20151102_0958_20151102_1258.txt
            report_file =
                fb_arch
                || '_' || fw_setting
                || '_' || heavy_load_ddl -- 'solid' | 'split'
                || '_' || compound_1st_col -- 'most__sel_1st' | 'least_sel_1st'
                || '_' || compound_idx_num -- 'one_index' | 'two_indxs'
                || '_' || coalesce( v_test_finish_state, overall_perf )
                || iif( a_build > '', '_build_' || a_build, '' )
                || '_' || load_time
                || '_' || load_att
                || '_' || start_at
            ;
        end

    if ( trim(a_prefix) > '' ) then report_file = trim(a_prefix) || '-' || report_file;

    if ( trim(a_suffix) > '' ) then report_file = report_file || '-' || trim(a_suffix);

    suspend;

end

^ -- srv_get_report_name

create or alter procedure srv_test_work
returns (
    ret_code integer)
as
    declare v_bak_ctx1 int;
    declare v_bak_ctx2 int;
    declare n bigint;
    declare v_clo_id bigint;
    declare v_ord_id bigint;
    declare v_inv_id bigint;
    declare v_res_id bigint;
begin
    -- "express test" for checking that main app units work OK.
    -- NB: all tables must be EMPTY before this SP run.
    v_bak_ctx1 = rdb$get_context('USER_SESSION', 'ORDER_FOR_OUR_FIRM_PERCENT');
    v_bak_ctx2 = rdb$get_context('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE');

    rdb$set_context('USER_SESSION', 'ORDER_FOR_OUR_FIRM_PERCENT',0);
    rdb$set_context('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE',1);

    select min(p.doc_list_id) from sp_client_order(0,1,1) p into v_clo_id;
    select count(*) from srv_make_invnt_saldo into n;
    select min(p.doc_list_id) from sp_supplier_order(0,1,1) p into v_ord_id;
    select count(*) from srv_make_invnt_saldo into n;
    select min(p.doc_list_id) from sp_supplier_invoice(0,1,1) p into v_inv_id;
    select count(*) from srv_make_invnt_saldo into n;
    select count(*) from sp_add_invoice_to_stock(:v_inv_id) into n;
    select count(*) from srv_make_invnt_saldo into n;

    select h.id
    from doc_list h
    where h.optype_id = fn_oper_retail_reserve()
    rows 1
    into :v_res_id;

    select count(*) from sp_reserve_write_off(:v_res_id) into n;
    select count(*) from srv_make_invnt_saldo into n;
    select count(*) from sp_cancel_client_order(:v_clo_id) into n;
    select count(*) from srv_make_invnt_saldo into n;
    select count(*) from sp_cancel_supplier_order(:v_ord_id) into n;
    select count(*) from srv_make_invnt_saldo into n;

    rdb$set_context('USER_SESSION', 'ORDER_FOR_OUR_FIRM_PERCENT', v_bak_ctx1);
    rdb$set_context('USER_SESSION', 'ENABLE_RESERVES_WHEN_ADD_INVOICE', v_bak_ctx2);

    ret_code = iif( exists(select * from v_qdistr_source ) or exists(select * from v_qstorned_source ), 1, 0);
    ret_code = iif( exists(select * from invnt_turnover_log), bin_or(ret_code, 2), ret_code );
    ret_code = iif( NOT exists(select * from invnt_saldo), bin_or(ret_code, 4), ret_code );
    
    n = null;
    select s.id
    from invnt_saldo s
    where NOT
    (
        s.qty_clo=1 and s.qty_clr = 1
        and s.qty_ord = 0 and s.qty_sup = 0
        and s.qty_avl = 0 and s.qty_res = 0
        and s.qty_inc = 0 and s.qty_out = 0
    )
    rows 1
    into n;
    
    ret_code = iif( n is NOT null, bin_or(ret_code, 8), ret_code );
    
    suspend;
end

^ -- srv_test_work

set term ;^
commit;

drop exception ex_exclusive_required;
drop exception ex_not_suitable_fb_version;
set list on;
set echo off;
select 'oltp30_sp.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

-- ###################################################################
-- End of script oltp30_SP.sql;  next to be run: oltp_main_filling.sql
-- (common for both FB 2.5 and 3.0)
-- ###################################################################

