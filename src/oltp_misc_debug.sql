-- ###################################
-- Begin of script oltp_misc_debug.sql  // ###   O P T I O N A L   ###
-- ###################################
-- ::: NB ::: This scipt is COMMON for both FB 2.5 and 3.0 and should be called after oltp_main_filling.sql (if needed)

-- It creates some OPTIONAL debug views and procedures.
-- Need only when some troubles in algorithms are detected.
-- Call of this script should be AFTER running oltpNN_DDL.sql and oltpNN_sp.sql
set bail on;

set list on;
select 'oltp_misc_debug.sql start at ' || current_timestamp as msg from rdb$database;
set list off;

commit;

-------------------------------------------------------
--  ************   D E B U G   T A B L E S   **********
-------------------------------------------------------
 -- tables for dump dirty data, 4 debug only
recreate table ztmp_shopping_cart(
   id bigint,
   snd_id bigint,
   qty numeric(12,3),
   optype_id bigint,
   snd_optype_id bigint,
   rcv_optype_id bigint,
   qty_bak numeric(12,3),
   dup_cnt int,
   dump_att bigint,
   dump_trn bigint
);
commit;

recreate table ztmp_dep_docs(
  base_doc_id bigint,
  dependend_doc_id bigint,
  dependend_doc_state bigint,
  dependend_doc_dbkey dm_dbkey,
  dependend_doc_agent_id bigint,
  ware_id bigint,
  base_doc_qty numeric(12,3),
  dependend_doc_qty numeric(12,3),
  dump_att bigint,
  dump_trn bigint
);
commit;

recreate table zdoc_list(
   id bigint
  ,worker_id smallint
  ,optype_id bigint
  ,agent_id bigint
  ,state_id bigint
  ,base_doc_id bigint -- id of document that is 'base' for current (stock order => incoming invoice etc)
  ,cost_purchase numeric(12,2) default 0 -- total in PURCHASING cost (can be ZERO for stock orders)
  ,cost_retail numeric(12,2) default 0 -- total in RETAIL cost, can be zero for incoming docs and stock orders
  ,acn_type dm_account_type
  ,dts_open timestamp
  ,dts_fix timestamp -- when changes of CONTENT of this document became disabled
  ,dts_clos timestamp -- when ALL changes of this doc. became disabled
  ,att int
  ,dump_att bigint
  ,dump_trn bigint
);
commit;

recreate table zdoc_data(
   id dm_idb
  ,doc_id dm_idb
  ,ware_id dm_idb
  ,qty dm_qty
  ,cost_purchase dm_cost
  ,cost_retail dm_cost
  ,dts_edit timestamp
  ,optype_id dm_idb
  ,dump_att bigint
  ,dump_trn bigint
);

-- 27.06.2014 (need to find cases when negative remainders appear)
recreate table zinvnt_turnover_log(
    ware_id bigint
   ,qty_diff numeric(12,3)
   ,cost_diff numeric(12,2)
   ,doc_list_id bigint
   ,doc_pref dm_mcode
   ,doc_data_id bigint
   ,optype_id bigint
   ,id bigint
   ,dts_edit timestamp
   ,att_id int
   ,trn_id int
   ,dump_att bigint
   ,dump_trn bigint
);

recreate table zqdistr(
   id dm_idb
  ,worker_id smallint
  ,doc_id dm_idb
  ,ware_id dm_idb
  ,snd_optype_id dm_idb
  ,snd_id dm_idb
  ,snd_qty dm_qty
  ,rcv_optype_id bigint
  ,rcv_id bigint -- nullable! ==> doc_data.id of "receiver"
  ,rcv_qty numeric(12,3)
  ,snd_purchase dm_cost
  ,snd_retail dm_cost
  ,rcv_purchase dm_cost
  ,rcv_retail dm_cost
  ,trn_id bigint
  ,dts timestamp
  ,dump_att bigint
  ,dump_trn bigint
);
create index zqdistr_id on zqdistr(id); -- NON unique!
create index zqdistr_ware_sndop_rcvop on zqdistr(ware_id, snd_optype_id, rcv_optype_id);


recreate table zqstorned(
   id dm_idb
  ,worker_id smallint
  ,doc_id dm_idb
  ,ware_id dm_idb
  ,snd_optype_id dm_idb
  ,snd_id dm_idb
  ,snd_qty dm_qty
  ,rcv_optype_id dm_idb
  ,rcv_id dm_idb
  ,rcv_qty dm_qty
  ,snd_purchase dm_cost
  ,snd_retail dm_cost
  ,rcv_purchase dm_cost
  ,rcv_retail dm_cost
  ,trn_id bigint
  ,dts timestamp
  ,dump_att bigint
  ,dump_trn bigint
);
create index zqstorned_id on zqstorned(id); -- NON unique!
create index zqstorned_doc_id on zqstorned(doc_id); -- confirmed 16.09.2014, see s`p_lock_dependent_docs
create index zqstorned_snd_id on zqstorned(snd_id); -- confirmed 16.09.2014, see s`p_kill_qty_storno
create index zqstorned_rcv_id on zqstorned(rcv_id); -- confirmed 16.09.2014, see s`p_kill_qty_storno

recreate table zpdistr(
   id dm_idb
  ,worker_id smallint
  ,agent_id dm_idb
  ,snd_optype_id dm_idb
  ,snd_id dm_idb
  ,snd_cost dm_qty
  ,rcv_optype_id dm_idb
  ,trn_id bigint
  ,dump_att bigint
  ,dump_trn bigint
);
create index zpdistr_id on zpdistr(id); -- NON unique!

recreate table zpstorned(
   id dm_idb
  ,worker_id smallint
  ,agent_id dm_idb
  ,snd_optype_id dm_idb
  ,snd_id dm_idb
  ,snd_cost dm_cost
  ,rcv_optype_id dm_idb
  ,rcv_id dm_idb
  ,rcv_cost dm_cost
  ,trn_id bigint
  ,dump_att bigint
  ,dump_trn bigint
);
create index zpstorned_id on zpstorned(id); -- NON unique!

commit;

set term ^;
create or alter procedure z_remember_view_usage (
    a_view_for_search dm_dbobj,
    a_view_for_min_id dm_dbobj default null,
    a_view_for_max_id dm_dbobj default null
) as
    declare i smallint;
    declare v_ctxn dm_ctxnv;
    declare v_name dm_dbobj;
begin

    i = 1;
    while (i <= 3) do -- a_view_for_search, a_view_for_min_id,  a_view_for_max_id
    begin
        v_name = decode(i, 1, a_view_for_search, 2, a_view_for_min_id ,  a_view_for_max_id  );
        if ( v_name is not null ) then
        begin
            v_ctxn = right(v_name||'_is_used', 80);
            if ( rdb$get_context('USER_SESSION', v_ctxn) is null ) then
            begin
                if (not exists( select * from z_used_views u where u.name = :v_name )) then
                begin
                    insert into z_used_views(name) values( :v_name );
                    rdb$set_context('USER_SESSION', v_ctxn, '1' );
                end
            when any do
                -- ::: nb ::: do NOT use "wh`en gdscode <mnemona>" followed by "wh`en any":
                -- the latter ("w`hen ANY") will handle ALWAYS, even if "w`hen <mnemona>"
                -- catched it's kind of exception!
                -- 1) tracker.firebirdsql.org/browse/CORE-3275
                --    "W`HEN ANY handles exceptions even if they are handled in another W`HEN section"
                -- 2) sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1088890&msg=15879669
                begin
                    if ( not gdscode in ( 335544665,335544349 ) ) then

                        -- #######
                        exception;
                        -- #######
                    -- else ==> yes, supress no_dup exception here --
                end
            end
        end
        i = i + 1;
    end

end
^


--------------------------------------------------------------------------------

create or alter procedure z_get_dependend_docs(
    a_doc_list_id dm_idb,
    a_doc_oper_id dm_idb default null -- = (for invoices which are to be 'reopened' - old_oper_id)
) returns (
  dependend_doc_id dm_idb, 
  dependend_doc_state dm_idb
)
as
    declare v_rcv_optype_id dm_idb;
begin
    -- former: s`p_get_dependend_docs; now need only for debug
    if ( a_doc_oper_id is null ) then
        select h.optype_id
        from doc_list h
        where h.id = :a_doc_list_id
        into a_doc_oper_id;

    v_rcv_optype_id = decode(
                              a_doc_oper_id
                             ,2100,          3300 -- ,fn_oper_invoice_add(),  fn_oper_retail_reserve()
                             ,1200,          2000 -- ,fn_oper_order_for_supplier(), fn_oper_invoice_get()
                             ,null
                            );

    for
        select x.dependend_doc_id, h.state_id
        -- 30.12.2014: PLAN JOIN (SORT (X Q INDEX (QSTORNED_DOC_ID)), H INDEX (PK_DOC_LIST))
        -- (added field rcv_doc_id in table qstorned, now can remove join with doc_data!)
        from (
            -- Checked plan 13.07.2014:
            -- PLAN (Q ORDER QSTORNED_RCV_ID INDEX (QSTORNED_DOC_ID))
            select q.rcv_doc_id dependend_doc_id -- q.rcv_id dependend_doc_data_id
            from v_qstorned_source q
            where
                q.doc_id =  :a_doc_list_id -- choosen invoice which is to be re-opened
                and q.snd_optype_id = :a_doc_oper_id -- fn_oper_invoice_add()
                and q.rcv_optype_id = :v_rcv_optype_id --fn_oper_retail_reserve() -- in ( fn_oper_retail_reserve(), fn_oper_retail_realization() )
            group by 1
        ) x
        join doc_list h on x.dependend_doc_id = h.id
        into dependend_doc_id, dependend_doc_state
    do
        suspend;

end

^ -- z_get_dependend_docs

set term ;^
commit;

--------------------------------------------------------------------------------

create or alter view z_perf_trn as
select * from perf_log p where p.trn_id = current_transaction
;

-------------------------------------------------------------------------------

create or alter view z_random_bop as
select b.sort_prior as id, b.unit, b.info
from business_ops b
;

--------------------------------------------------------------------------------

create or alter view v_diag_fk_uk as
-- service view for check data in FK/UNQ indices: search 'orphan' rows in FK
-- or duplicate rows in all PK/UNQ keys (suggestion by DS, 05.05.2014 18:23)
-- ::: NB ::: this view does NOT include in its reultset self-referenced tables!
with recursive
c as (
    select
         rc.rdb$relation_name child_tab
        ,rc.rdb$constraint_name child_fk
        ,rc.rdb$index_name child_idx
        ,ru.rdb$const_name_uq parent_uk
        ,rp.rdb$relation_name parent_tab
        ,rp.rdb$index_name parent_idx
    from rdb$relation_constraints rc
    join rdb$ref_constraints ru on
         rc.rdb$constraint_name = ru.rdb$constraint_name
         and rc.rdb$constraint_type = 'FOREIGN KEY'
    join rdb$relation_constraints rp
         on ru.rdb$const_name_uq = rp.rdb$constraint_name
    where rc.rdb$relation_name <> rp.rdb$relation_name -- prevent from select self-ref PK/FK tables!
)
,d as(
    select
        0 i
        ,child_tab
        ,child_fk
        ,child_idx
        ,parent_uk
        ,parent_tab
        ,parent_idx
    from c c0
    -- filter tables which are NOT parents for any other tables:
    where not exists( select * from c cx where cx.parent_tab= c0.child_tab ) 
    
    union all
    
    select
        d.i+1
        ,c.child_tab
        ,c.child_fk
        ,c.child_idx
        ,c.parent_uk
        ,c.parent_tab
        ,c.parent_idx
    from d
    join c on d.parent_tab = c.child_tab
)
--select * from d where d.child_tab='DOC_DATA'

,e as(
    select distinct
         child_tab
        ,child_fk
        ,child_idx
        ,parent_uk
        ,parent_tab
        ,parent_idx
        ,rsc.rdb$field_name fk_fld
        ,rsp.rdb$field_name uk_fld
    from d
    join rdb$index_segments rsc on d.child_idx = rsc.rdb$index_name
    join rdb$index_segments rsp on d.parent_idx = rsp.rdb$index_name and rsc.rdb$field_position=rsp.rdb$field_position
)
,f as(
    select
        e.child_tab,e.child_fk,e.parent_tab,e.parent_uk
        --,e.fk_fld,e.uk_fld
        ,list( 'd.'||trim(e.fk_fld)||' = m.'||trim(e.uk_fld), ' and ') jcond
        ,list( 'm.'||trim(e.uk_fld)||' is null', ' and ' ) ncond
    from e
    group by e.child_tab,e.child_fk,e.parent_tab,e.parent_uk
)
--select * from f

select
    f.child_fk checked_constraint
   ,'FK' type_of_constraint
   ,'select count(*) from '
        ||trim(f.child_tab)||' d left join '
        ||trim(f.parent_tab)||' m on '
        ||f.jcond
        ||' where '||f.ncond as checked_qry
from f

UNION ALL

select
    uk_idx as checked_constraint
   ,'UK' type_of_constraint
   ,'select count(*) from '||trim(tab_name)||' group by '||trim(uk_lst)||' having count(*)>1' as checked_qry
from(
    select tab_name,uk_idx, list( trim(uk_fld) ) uk_lst
    from(
        select rr.rdb$relation_name tab_name, rc.rdb$index_name uk_idx, rs.rdb$field_name uk_fld
        from rdb$relation_constraints rc
        join rdb$relations rr on rc.rdb$relation_name = rr.rdb$relation_name
        join rdb$index_segments rs on rc.rdb$index_name = rs.rdb$index_name
        where
            rc.rdb$constraint_type in ('PRIMARY KEY', 'UNIQUE')
            and coalesce(rr.rdb$system_flag,0)=0
    )
    group by tab_name,uk_idx
)
-- v_diag_fk_uk
;

-------------------------------------------

create or alter view v_diag_idx_entries as
-- source to check match of all possible counts ortder by table indices
-- and count via natural order (suggestion by DS, 05.05.2014 18:23)
select
  tab_name
  ,idx_name
  ,cast('select count(*) from (select * from '||trim(tab_name)||' order by '||trim(idx_expr||desc_expr)||')' as varchar(255))
   as checked_qry
from(
    select
        tab_name
        ,idx_name
        ,max(iif(idx_type=1,' desc','')) desc_expr
        ,list(trim(coalesce(idx_comp, idx_key))) idx_expr
    from
    (
        select
            ri.rdb$relation_name tab_name
            ,ri.rdb$index_name idx_name
            ,ri.rdb$expression_source idx_comp
            ,ri.rdb$index_type idx_type
            ,rs.rdb$field_name idx_key
        from rdb$indices ri
            join rdb$relations rr on ri.rdb$relation_name = rr.rdb$relation_name
            left join rdb$index_segments rs on ri.rdb$index_name=rs.rdb$index_name
        where coalesce(rr.rdb$system_flag,0)=0 and rr.rdb$relation_type not in(4,5)
        order by ri.rdb$relation_name, rs.rdb$index_name,rs.rdb$field_position
    )
    group by
        tab_name
        ,idx_name
)
-- v_diag_idx_entries
;

commit;

------------------------------------------------------------------------

create or alter view z_check_inv_vs_sup as
-- for checking: all qty in INVOICES which supplier has sent us must be
-- LESS or EQUEAL than qty which we've ORDERED to supplier before
-- This view should return records with ERRORS in data.
select
    doc_id,
    doc_data_id,
    ware_id,
    qty as doc_qty,
    qty_sup,
    qty_clo,
    qty_clr,
    qty_ord,
    qty_avl,
    qty_res
from v_add_invoice_to_stock v
join v_doc_detailed f on v.id=f.doc_id
where qty > qty_sup
;
commit;



--------------------------------------------------------------------------------

create or alter view z_clean_data as
with recursive
c as (
    select
         rc.rdb$relation_name child_tab
        ,rc.rdb$constraint_name child_fk
        ,ru.rdb$const_name_uq parent_uk
        ,rp.rdb$relation_name parent_tab
    from rdb$relation_constraints rc
    join rdb$ref_constraints ru on
         rc.rdb$constraint_name = ru.rdb$constraint_name
         and rc.rdb$constraint_type = 'FOREIGN KEY'
    join rdb$relation_constraints rp
         on ru.rdb$const_name_uq = rp.rdb$constraint_name
    where rc.rdb$relation_name <> rp.rdb$relation_name
)
--select * from c
,d as(
    select
        0 i
        ,child_tab
        ,child_fk
        ,parent_uk
        ,parent_tab
    from c c0
    where not exists( select * from c cx where cx.parent_tab= c0.child_tab )
    
    union all
    
    select
        d.i+1
        ,c.child_tab
        ,c.child_fk
        ,c.parent_uk
        ,c.parent_tab
    from d
    join c on d.parent_tab = c.child_tab
)
,e as(
    select
        i
        ,child_tab
        ,child_fk
        ,parent_uk
        ,parent_tab
        --,max(i)over() mi
        --,(select max(i) from d) as mi
    from d
)
-- select * from e
,f as(
    select distinct
        0 i
        ,child_tab
    from e where i=0

    UNION DISTINCT

    select
        1
        ,child_tab
    from (select child_tab from e where i > 0 order by i)

    UNION DISTINCT

    select k,parent_tab
    from (
        select
            2 as k
            ,parent_tab
        from e
        order by i desc rows 1
    )
    --- doesn`t work in 3.0 when "(select max(i) from d) as mi", see CTE `e`, 06.02.2015:
    -- select 2 as k,parent_tab from e where i=mi
)
,t as(
    select
        rt.rdb$trigger_name trg_name -- f.child_tab, rt.rdb$trigger_name, rt.rdb$trigger_type
    from f
    join rdb$triggers rt on f.child_tab = rt.rdb$relation_name
    where rt.rdb$system_flag=0 and rt.rdb$trigger_inactive=0
)
select 'alter trigger '||trim(trg_name)||' inactive' sql_expr
from t
union all
select 'delete from '||trim(child_tab)
from f
union all
select 'alter trigger '||trim(trg_name)||' active'
from t
;

----------------------

create or alter view z_idx_stat as
select ri.rdb$relation_name tab_name, ri.rdb$index_name idx_name, nullif(ri.rdb$statistics,0) idx_stat
from rdb$indices ri
where ri.rdb$relation_name not starting with 'RDB$' --and ri.rdb$statistics > 0
order by 3 desc nulls first,1,2
;


--------------------------------------------------------------------------------

create or alter view z_rules_for_qdistr as
-- 4debug
select r.mode, r.snd_optype_id, so.mcode snd_mcode, r.rcv_optype_id, ro.mcode rcv_mcode
from v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
left join optypes so on r.snd_optype_id = so.id
left join optypes ro on r.rcv_optype_id = ro.id
;


--------------------------------------------------------------------------------

create or alter view zv_doc_detailed as
-- Debug: analysis of dumped dirty data (filled by SP zdump4dbg in some critical errors)
select
    h.id doc_id,
    h.optype_id,
    o.mcode oper,
    h.base_doc_id,
    d.id doc_data_id,
    d.ware_id,
    d.qty,
    coalesce(d.cost_purchase, h.cost_purchase) cost_purchase, -- cost in purchase price
    coalesce(d.cost_retail, h.cost_retail) cost_retail, -- cost in retail price
    h.state_id,
    h.agent_id,
    d.dts_edit,
    h.dts_open,
    h.dts_fix,
    h.dts_clos,
    s.mcode state,
    h.att
from zdoc_list h
    join optypes o on h.optype_id = o.id
    join doc_states s on h.state_id=s.id
    left join zdoc_data d on h.id = d.doc_id
    -- ::: NB ::: do NOT remove "left" from here otherwise performance will degrade
    -- (FB will not push predicate inside view; 22.04.2014)
    --LEFT join v_saldo_invnt n on d.ware_id=n.ware_id
;
--------------------------------------------------------------------------------
create or alter view zv_saldo_invnt as
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
from zinvnt_turnover_log ng
join optypes o on ng.optype_id=o.id
group by 1
;

--------------------------------------------------------------------------------


create or alter view z_mism_dd_qd_qs_orphans as
-- 4 debug: search only those rows in doc_data for which absent any rows in
-- qdistr and qstorned ('lite' diagnostics):
select d.doc_id,h.optype_id,d.id,d.ware_id,d.qty
from doc_data d
join doc_list h on d.doc_id = h.id
left join v_qdistr_source q on d.id=q.snd_id
left join v_qstorned_source s on d.id in(s.snd_id, s.rcv_id)
where h.optype_id<>1100 and q.id is null and s.id is null
;

--------------------------------------------------------------------------------

create or alter view z_mism_dd_qd_qs_sums as
-- 4 debug: search for mismatches be`tween doc_data.qty and number of
-- records in qdistr or qstorned
select d.doc_id, d.id,d.optype_id,d.qty,d.qd_sum,coalesce(sum(qs.snd_qty),0) qs_sum
from(
    select d.doc_id, d.id, d.optype_id, d.qty,coalesce(sum(qd.snd_qty),0) qd_sum
    from (
        select d.doc_id, d.id, d.ware_id, iif(h.optype_id=3400, 3300, h.optype_id) as optype_id, d.qty
        from doc_data d
        join doc_list h on d.doc_id = h.id
    ) d
    inner join v_rules_for_qdistr p  -- 29.03.2019: replaced with view in order to remove dependencies
        on d.optype_id = p.snd_optype_id + 0 and coalesce(p.storno_sub,1)=1 -- hash join! 3.0 only
    left join v_qdistr_source qd on
        qd.ware_id = d.ware_id
        and qd.snd_optype_id = p.snd_optype_id
        and qd.rcv_optype_id is not distinct from p.rcv_optype_id
    where d.optype_id<>1100 -- client refused from order
    group by d.doc_id, d.id, d.optype_id, d.qty
) d
join v_rules_for_qdistr p  -- 29.03.2019: replaced with view in order to remove dependencies
    on d.optype_id = p.snd_optype_id + 0 and coalesce(p.storno_sub,1)=1 -- hash join! 3.0 only
left join v_qstorned_source qs on
    d.id=qs.snd_id
    and p.snd_optype_id=qs.snd_optype_id
    and p.rcv_optype_id is not distinct from  qs.rcv_optype_id
group by d.doc_id, d.id,d.optype_id,d.qty,d.qd_sum
having d.qty <> d.qd_sum + coalesce(sum(qs.snd_qty),0)
;

--------------------------------------------------------------------------------

create or alter view z_mism_zdd_zqdzqs as
-- 4 debug: search for mismatches between doc_data.qty and number of
-- records in qdistr or qstorned
select d.doc_id, d.id,d.optype_id,d.qty,d.qd_sum,coalesce(sum(qs.snd_qty),0) qs_sum
from(
    select d.doc_id, d.id, d.optype_id, d.qty,coalesce(sum(qd.snd_qty),0) qd_sum
    from (
        select d.doc_id, d.id, d.ware_id, iif(d.optype_id=3400, 3300, d.optype_id) as optype_id, d.qty
        from zdoc_data d
    ) d
    inner join v_rules_for_qdistr p -- 29.03.2019: replaced with view in order to remove dependencies
        on d.optype_id=p.snd_optype_id and coalesce(p.storno_sub,1)=1
    left join zqdistr qd on
        qd.ware_id = d.ware_id
        and qd.snd_optype_id = p.snd_optype_id
        and qd.rcv_optype_id is not distinct from p.rcv_optype_id
    where d.optype_id<>1100 -- client refused from order
    group by d.doc_id, d.id, d.optype_id, d.qty
) d
inner join v_rules_for_qdistr p -- 29.03.2019: replaced with view in order to remove dependencies
    on d.optype_id=p.snd_optype_id and coalesce(p.storno_sub,1)=1
left join zqstorned qs on
    d.id=qs.snd_id
    and p.snd_optype_id=qs.snd_optype_id
    and p.rcv_optype_id is not distinct from  qs.rcv_optype_id
group by d.doc_id, d.id,d.optype_id,d.qty,d.qd_sum
having d.qty <> d.qd_sum + coalesce(sum(qs.snd_qty),0)
;

--------------------------------------------------------------------------------
create or alter view z_qdqs as
-- Debug: analysis of dumped dirty data (filled by SP zdump4dbg in some critical errors)
select
    cast(q.src as varchar(8)) as src,
    q.id,
    q.ware_id,
    q.snd_optype_id,
    cast(so.mcode as varchar(3)) snd_op,
    q.doc_id as snd_doc_id,
    sh.agent_id as snd_agent,
    q.snd_id,
    q.snd_qty,
    q.snd_purchase,
    q.snd_retail,
    q.rcv_optype_id,
    cast(ro.mcode as varchar(3)) rcv_op,
    d.doc_id as rcv_doc_id,
    rh.agent_id as rcv_agent,
    q.rcv_id,
    q.rcv_qty,
    q.rcv_purchase,
    q.rcv_retail,
    q.trn_id,
    q.dts
from (
  select 'qdistr' src,q.*
  from qdistr q
  union all
  select 'qstorned', s.*
  from qstorned s
) q
left join doc_data d on q.rcv_id = d.id
left join optypes so on q.snd_optype_id = so.id
left join doc_list sh on q.doc_id=sh.id
left join optypes ro on q.rcv_optype_id = ro.id
left join doc_list rh on d.doc_id=rh.id
order by q.src, q.doc_id, q.id
;

-------------------------------

create or alter view z_zqdzqs as
-- Debug: analysis of dumped dirty data (filled by SP zdump4dbg in some critical errors)
select
    q.src,
    q.id,
    q.ware_id,
    q.snd_optype_id,
    left(so.mcode,3) snd_op,
    q.doc_id as snd_doc_id,
    q.snd_id,
    q.snd_qty,
    q.rcv_optype_id,
    left(ro.mcode,3) rcv_op,
    d.doc_id as rcv_doc_id,
    q.rcv_id,
    q.rcv_qty,
    q.trn_id,
    q.dts,
    q.dump_att,
    q.dump_trn
from (
  select 'zqdistr' src,q.*
  from zqdistr q
  union all
  select 'zqstorned', s.*
  from zqstorned s
) q
left join zdoc_data d on q.rcv_id = d.id
left join optypes so on q.snd_optype_id = so.id
left join optypes ro on q.rcv_optype_id = ro.id
order by q.src, q.doc_id, q.id
;
-------------------------------

create or alter view z_pdps as
-- Debug: analysis of dumped dirty data (filled by SP zdump4dbg in some critical errors)
select
    cast(p.src as varchar(8)) as src,
    p.id,
    p.agent_id,
    p.snd_optype_id,
    cast(so.mcode as varchar(3)) snd_op,
    p.snd_id,
    p.snd_cost,
    p.rcv_optype_id,
    cast(ro.mcode as varchar(3)) rcv_op,
    p.rcv_id,
    p.rcv_cost,
    p.trn_id
from (
    select 'pdistr' src,p.id,p.agent_id,p.snd_optype_id,p.snd_id,p.snd_cost,p.rcv_optype_id, cast(null as bigint) as rcv_id, cast(null as numeric(12,2)) as rcv_cost, p.trn_id
    from pdistr p
    union all
    select 'pstorned', s.id, s.agent_id, s.snd_optype_id, s.snd_id, s.snd_cost, s.rcv_optype_id, s.rcv_id, s.rcv_cost, s.trn_id
    from pstorned s
) p
left join optypes so on p.snd_optype_id = so.id
left join optypes ro on p.rcv_optype_id = ro.id
order by p.src, p.id -- p.agent_id, p.rcv_id, p.id
;
------------------------------

create or alter view z_zpdzps as
-- Debug: analysis of dumped dirty data (filled by SP zdump4dbg in some critical errors)
select
    p.src,
    p.id,
    p.agent_id,
    p.snd_optype_id,
    left(so.mcode,3) snd_op,
    p.snd_id,
    p.snd_cost,
    p.rcv_optype_id,
    left(ro.mcode,3) rcv_op,
    p.rcv_id,
    p.rcv_cost,
    p.trn_id,
    p.dump_att,
    p.dump_trn
from (
    select 'zpdistr' src,p.id,p.agent_id,p.snd_optype_id,p.snd_id,p.snd_cost,p.rcv_optype_id,
          cast(null as bigint) as rcv_id, cast(null as numeric(12,2)) as rcv_cost,
          p.trn_id, p.dump_att, p.dump_trn
    from zpdistr p
    union all
    select 'zpstorned', s.id, s.agent_id, s.snd_optype_id, s.snd_id, s.snd_cost, s.rcv_optype_id,
          s.rcv_id, s.rcv_cost,
          s.trn_id, s.dump_att, s.dump_trn
    from zpstorned s
) p
left join optypes so on p.snd_optype_id = so.id
left join optypes ro on p.rcv_optype_id = ro.id
order by p.src, p.agent_id, p.rcv_id, p.id
;

--------------------------------------------------------------------------------

create or alter view z_slow_get_random_id as
select
    substring(pg.info from 1 for coalesce(nullif(position(';',pg.info)-1,-1),31) ) mode,
    pg.elapsed_ms,
    min(pg.elapsed_ms) ms_min,
    max(pg.elapsed_ms) ms_max,
    count(*) cnt
from perf_log pg
where pg.unit='fn_get_random_id' and pg.elapsed_ms>=3000
group by 1,2
;


--------------------------------------------------------------------------------

create or alter view z_get_min_max_id as
-- 08.02.2015: debug view for efficiency estimation of 'boundary' views which
-- is used for obtaining MIN and MAX ids before subsequent random selection.
-- (v_min/max_id_clo_ord, v_min/max_id_ord_sup etc)
-- Registering in perf_log is in fn_get_random_id.
select
    g.unit
    ,count(iif( coalesce(g.fb_gdscode,0)=0, 1, null ) ) cnt_ok
    ,count(*) cnt_all
    ,avg(g.elapsed_ms) avg_time
    ,min(g.elapsed_ms) min_time
    ,max(g.elapsed_ms) max_time
from perf_log g
where
(
  g.unit starting with 'v_min_id'
  or
  g.unit starting with 'v_max_id'
)
group by 1
order by right(g.unit,6),left(g.unit,4) desc
;

--------------------------------------------------------------------------------

create or alter view z_doc_data_oper_cnt as
-- 19.07.2014, for analyze results of init data population alg
select h.optype_id,o.name op_name,count(*) doc_data_cnt
from doc_list h
join optypes o on h.optype_id=o.id
join doc_data d on h.id=d.doc_id
group by 1,2
;


--------------------------------------------------------------------------------

create or alter view z_doc_list_oper_cnt as
-- 19.07.2014, for analyze results of init data population alg
select h.optype_id,o.name op_name, count(*) doc_list_cnt
from doc_list h
join optypes o on h.optype_id=o.id
group by 1,2
;

--------------------------------------------------------------------------------

create or alter view z_invoices_to_be_adopted as
--  4 debug (performance of sp_add_invoice_to_stock)
select
     invoice_id, total_rows, total_qty
    ,min(p.clo_agent_id) agent_min_id
    ,max(p.clo_agent_id) agent_max_id
    ,count(distinct p.clo_agent_id) agent_diff_cnt
from (
    select h.id invoice_id, count(*) total_rows, sum(qty) total_qty
    from doc_list h
    join doc_data d on h.id=d.doc_id
    where h.optype_id = 2000 -- fn_oper_invoice_get
    group by 1
) x
left join sp_get_clo_for_invoice(x.invoice_id) p on 1=1
group by invoice_id, total_rows, total_qty
order by total_rows desc, total_qty desc
;

--------------------------------------------------------------------------------

create or alter view z_invoices_to_be_cancelled as
--  4 debug (performance of s`p_cancel_adding_invoice)
select h.id invoice_id, count(*) total_rows, sum(qty) total_qty
from doc_list h
join doc_data d on h.id=d.doc_id
where h.optype_id = 2100 -- fn_oper_invoice_add
group by 1
order by 2 desc
;

--------------------------------------------------------------------------------

create or alter view z_ord_inc_res_dependencies as
-- 17.07.2014: get all dependencies (links) b`etween
-- supplier orders (take first 5), invoices and customer reserves
with
s as(
    select v.ord_id, count(*) ord_rows, sum(d0.qty) ord_qty_sum
    from ( select first 5 v.id as ord_id from v_cancel_supplier_order v ) v
    join doc_data d0 on v.ord_id = d0.doc_id
    group by v.ord_id
)
,i as(
    select
         s.ord_id
        ,s.ord_rows
        ,s.ord_qty_sum
        ,p1.dependend_doc_id as inv_id
        ,count(*) inv_rows
        ,sum(di.qty) inv_qty_sum
    from s
    left join z_get_dependend_docs( s.ord_id, 1200 ) p1 on 1=1 -- 1200=fn_oper_order_for_supplier()
    left join doc_data di on p1.dependend_doc_id = di.doc_id
    group by
         s.ord_id
        ,s.ord_rows
        ,s.ord_qty_sum
        ,p1.dependend_doc_id
)
select
    i.ord_id
    ,i.ord_rows
    ,i.ord_qty_sum
    ,i.inv_id
    ,i.inv_rows
    ,i.inv_qty_sum
    ,p2.dependend_doc_id as res_id
    ,count(*) res_rows
    ,sum(dr.qty) res_qty_sum
from i
left join z_get_dependend_docs( i.inv_id, 2100 ) p2 on 1=1-- 2100=fn_oper_invoice_add()
left join doc_data dr on p2.dependend_doc_id = dr.doc_id
group by
    i.ord_id
    ,i.ord_rows
    ,i.ord_qty_sum
    ,i.inv_id
    ,i.inv_rows
    ,i.inv_qty_sum
    ,p2.dependend_doc_id
;

commit;

---------------------------------------

set term ^;

-- ::: NB :::
-- We have to avoid declaration of SP parameters in form 'type of column <some_view>.<col>'
-- otherwise extracted metadata will be invalid.
-- See: https://github.com/FirebirdSQL/firebird/issues/6862 (still not fixed, 29.08.2025).
create or alter procedure srv_diag_fk_uk
returns(
    checked_constraint type of column rdb$relation_constraints.rdb$constraint_name,
    type_of_constraint varchar(2), -- prev (bad): v_diag_fk_uk.type_of_constraint,
    failed_rows int
)
as
    declare v_checked_qry varchar(8190);
begin
    -- obtain text of queries for checking data in tables which have
    -- FK and PK/UNQ constraints; counts rows from these tables where
    -- violations of FK or PK/UNQ occur: 'orphan' FK, duplicates in PK/UNQ
    for
        select v.checked_constraint, v.type_of_constraint, cast(v.checked_qry as varchar(8190))
        from v_diag_fk_uk v
    into checked_constraint, type_of_constraint, v_checked_qry
    do begin
       execute statement(v_checked_qry) into failed_rows; -- this must be always 'select count(*) from ...'
       if (failed_rows > 0) then suspend;
    end
end

^ -- srv_diag_fk_uk

----------------------------------------------------------------------

create or alter procedure srv_diag_idx_entries
returns(
    tab_name type of column rdb$relations.rdb$relation_name,
    idx_name type of column rdb$indices.rdb$index_name,
    nat_count bigint,
    idx_count bigint,
    failed_rows bigint
)
as
    declare v_checked_qry varchar(8190);
    declare v_nat_stt varchar(255);
    declare rn bigint;
    declare v_prev_tab type of column rdb$relations.rdb$relation_name = '';
begin
    for
        select v.tab_name, v.idx_name, v.checked_qry
        from v_diag_idx_entries v
        where v.checked_qry not containing 'DOC_NUMB' -- temply, smth wrong with coll num-sort=1 and unique index: FB uses plan natural instead of that index, see: http://www.sql.ru/forum/1093394/select-from-t1-order-by-s-ne-uzaet-uniq-indeks-esli-s-utf8-coll-numeric-sort-1
    into tab_name, idx_name, v_checked_qry
    do begin
        if ( v_prev_tab is distinct from tab_name ) then begin
          v_nat_stt = 'select count(*) from '||tab_name;
          execute statement ( v_nat_stt ) into nat_count;
          v_prev_tab = tab_name;
        end
       execute statement(v_checked_qry) into idx_count; -- this must be always 'select count(*) from ...'
       if ( nat_count <> idx_count ) then begin
           failed_rows = nat_count - idx_count;
           suspend;
       end
    end
end

^  -- srv_diag_idx_entries

----------------------------------------------------------------------

create or alter procedure srv_diag_qty_distr
returns(
    doc_id dm_idb,
    optype_id dm_idb,
    rcv_optype_id dm_idb,
    doc_data_id dm_idb,
    qty dm_qty,
    qdqs_sum dm_qty,
    qdistr_q dm_qty,
    qstorned_q dm_qty
) as
begin
    -- Looks for mismatches between records count in v_qdistr + v_qstorned and doc_data
    -- Must be run ONLY in TIL = SNAPSHOT!
    -- ###################################
    -- Check that current Tx run in NO wait or with lock_timeout.
    -- Otherwise raise error: performance degrades almost to zero.
    execute procedure sp_check_nowait_or_timeout;

    for
        select
            b.doc_id,
            b.optype_id,
            b.rcv_optype_id,
            b.id,
            b.qty,
            b.qdistr_q + coalesce(sum(qs.snd_qty),0) qdqs_sum,
            b.qdistr_q,
            coalesce(sum(qs.snd_qty),0) qstorned_q
        from (
            select d.doc_id, h.optype_id, r.rcv_optype_id, d.id, d.qty --
            ,coalesce(sum(qd.snd_qty),0) qdistr_q
            from doc_data d
            join doc_list h on d.doc_id = h.id
            join v_rules_for_qdistr r -- 29.03.2019: replaced with view in order to remove dependencies
                on h.optype_id = r.snd_optype_id
            left join v_qdistr_source qd on
                d.ware_id = qd.ware_id
                and qd.snd_optype_id = r.snd_optype_id
                and qd.rcv_optype_id is not distinct from r.rcv_optype_id
            group by d.doc_id, h.optype_id, r.rcv_optype_id, d.id, d.qty
        ) b
        left join v_qstorned_source qs on b.id = qs.snd_id and b.optype_id=qs.snd_optype_id and b.rcv_optype_id=qs.rcv_optype_id
        group by
            b.doc_id,
            b.optype_id,
            b.rcv_optype_id,
            b.id,
            b.qty,
            b.qdistr_q
        having b.qty <> b.qdistr_q + coalesce(sum(qs.snd_qty),0)
        into
            doc_id,
            optype_id,
            rcv_optype_id,
            doc_data_id,
            qty,
            qdqs_sum,
            qdistr_q,
            qstorned_q
    do suspend;
end

^ -- srv_diag_qty_distr

commit ^

--------------------------------------------------------------------------------
-- #############    D E B U G:     D U M P    D I R T Y     D A T A  ###########
--------------------------------------------------------------------------------

create or alter procedure zdump4dbg(
       a_doc_list_id bigint default null,
       a_doc_data_id bigint default null,
       a_ware_id bigint default null
)
as
    declare v_catch_bitset bigint;
    declare id bigint;
    declare trn_id bigint;
    declare snd_optype_id bigint;
    declare rcv_optype_id bigint;
    declare qty numeric(12,3);
    declare dup_cnt int;
    declare qty_bak numeric(12,3);
    declare snd_qty numeric(12,3);
    declare rcv_qty numeric(12,3);

    declare snd_id bigint;
    declare rcv_id bigint;
    declare doc_id bigint;
    declare worker_id smallint; -- 12.08.2018
    declare ware_id bigint;
    declare optype_id bigint;
    declare agent_id bigint;
    declare state_id bigint;
    declare dts_open timestamp;
    declare dts_fix timestamp;
    declare dts_clos timestamp;
    declare dts_edit timestamp;
    declare base_doc_id bigint;
    declare acn_type type of dm_account_type;

    declare dependend_doc_id bigint;
    declare dependend_doc_state bigint;
    declare dependend_doc_dbkey dm_dbkey;
    declare dependend_doc_agent_id bigint;
    declare base_doc_qty numeric(12,3);
    declare dependend_doc_qty numeric(12,3);

    declare cost_purchase numeric(12,2);
    declare cost_retail numeric(12,2);
    declare snd_purchase numeric(12,2);
    declare snd_retail numeric(12,2);
    declare rcv_purchase numeric(12,2);
    declare rcv_retail numeric(12,2);
    declare snd_cost numeric(12,2);
    declare rcv_cost numeric(12,2);

    declare v_curr_att int;
    declare v_curr_trn int;
    declare i int;
    declare v_step int = 1000;
    declare v_max_id bigint;
    declare v_perf_semaphore_id bigint;
    declare v_perf_progress_id bigint;
    declare v_this dm_dbobj = 'zdump4dbg';
begin
    -- See oltp_main_filling.sql for definition of bitset var `QMISM_VERIFY_BITSET`:
    -- bit#0 := 1 ==> perform calls of srv_catch_qd_qs_mism in doc_list_aiud => sp_add_invnt_log
    --                in order to register mismatches b`etween doc_data.qty and total number of rows
    --                in v_qdistr_source + v_qstorned_source for doc_data.id
    -- bit#1 := 1 ==> perform calls of SRV_CATCH_NEG_REMAINDERS from INVNT_TURNOVER_LOG_AI
    --                (instead of totalling turnovers to `invnt_saldo` table)
    -- bit#2 := 1 ==> allow dump dirty data into z-tables for analysis, see sp zdump4dbg, in case
    --                when some 'bad exception' occurs (see ctx var `HALT_TEST_ON_ERRORS`)
    v_catch_bitset = cast(rdb$get_context('USER_SESSION','QMISM_VERIFY_BITSET') as bigint);
    if ( bin_and( v_catch_bitset, 4 ) = 0 ) -- dump dirty data DISABLED
    then
        --####
          exit;
        --####

    v_curr_att = current_connection;
    v_curr_trn = current_transaction;
    v_perf_semaphore_id = null;

    -- record with EMPTY is added by 1run_oltp_emul.bat on every new start of test,
    -- it always contains EMPTY string in field `info` at this moment:
    select id from perf_log g
    where g.unit = 'dump_dirty_data_semaphore'
    order by id
    rows 1
    into v_perf_semaphore_id;
    if ( v_perf_semaphore_id is null ) then
    begin
        exit;
    end

    in autonomous transaction do
        update perf_log g set
            g.info = 'start, tra_'||:v_curr_trn,
            dts_beg = 'now',
            dts_end = null
        where g.id = :v_perf_semaphore_id
              and g.dts_beg is null;

    -- jump to when-section if lock_conflict, see below --
    if ( row_count = 0 ) then -- ==> this job was already done by another attach
    begin
        exit;
    end

    -- record for show progress in case of watching from IBE etc:
    in autonomous transaction do
        insert into perf_log(unit, dts_beg) values( 'dump_dirty_data_progress', current_timestamp )
        returning id into v_perf_progress_id;

    -- dumps dirty data into tables for further analysis before halt (4debug only)
    ----------------------------------------------------------------------------
    for
        select c.id,c.snd_optype_id,c.rcv_optype_id,c.qty,c.dup_cnt,c.qty_bak
        from tmp$shopping_cart c
        --as cursor ct
        into id,snd_optype_id,rcv_optype_id,qty,dup_cnt,qty_bak
    do
        in autonomous transaction do
        insert into ztmp_shopping_cart(id, snd_optype_id, rcv_optype_id, qty, dup_cnt, qty_bak)
        values( :id,  :snd_optype_id,  :rcv_optype_id,  :qty,  :dup_cnt, :qty_bak)
    ;
    ----------------------------------------------------------------------------
    for
        select
            base_doc_id,dependend_doc_id,dependend_doc_state,dependend_doc_dbkey
            ,dependend_doc_agent_id,ware_id,base_doc_qty,dependend_doc_qty
        from tmp$dep_docs
        into
            base_doc_id,dependend_doc_id,dependend_doc_state,dependend_doc_dbkey
            ,dependend_doc_agent_id,ware_id,base_doc_qty,dependend_doc_qty
    do
        in autonomous transaction do
        insert into ztmp_dep_docs(
            base_doc_id,dependend_doc_id,dependend_doc_state,dependend_doc_dbkey
            ,dependend_doc_agent_id,ware_id,base_doc_qty,dependend_doc_qty
            ,dump_att
            ,dump_trn
        )
        values(
            :base_doc_id,:dependend_doc_id,:dependend_doc_state,:dependend_doc_dbkey
            ,:dependend_doc_agent_id,:ware_id,:base_doc_qty,:dependend_doc_qty
            ,:v_curr_att
            ,:v_curr_trn
        )
    ;

    ----------------------------------------------------------------------------
    --   dump dirty data from   ### d o c _ l i s t ###
    select 0, max(id) from doc_list into i,v_max_id; -- for verbosing in perf_log.stack
    for
        select
            id
            ,worker_id
            ,optype_id
            ,agent_id
            ,state_id
            ,dts_open
            ,dts_fix
            ,dts_clos
            ,base_doc_id
            ,acn_type
            ,cost_purchase
            ,cost_retail
        from doc_list h
        where h.id = :a_doc_list_id or :a_doc_list_id is null
        into
            :id
            ,:worker_id
            ,:optype_id
            ,:agent_id
            ,:state_id
            ,:dts_open
            ,:dts_fix
            ,:dts_clos
            ,:base_doc_id
            ,:acn_type
            ,:cost_purchase
            ,:cost_retail
    do
    begin
        in autonomous transaction do
        insert into zdoc_list(
            id
            ,worker_id
            ,optype_id
            ,agent_id
            ,state_id
            ,dts_open
            ,dts_fix
            ,dts_clos
            ,base_doc_id
            ,acn_type
            ,cost_purchase
            ,cost_retail
        )
        values(
            :id
            ,:worker_id
            ,:optype_id
            ,:agent_id
            ,:state_id
            ,:dts_open
            ,:dts_fix
            ,:dts_clos
            ,:base_doc_id
            ,:acn_type
            ,:cost_purchase
            ,:cost_retail
         );
        if ( mod(i, v_step) = 0 ) then
            in autonomous transaction do
            update perf_log g set g.stack = 'doc_list: id='||:id||', max='||:v_max_id
            where g.id = :v_perf_progress_id;
        i = i + 1;

     end

    ----------------------------------------------------------------------------
    --   dump dirty data from   ### d o c _ d a t a ###
    select 0, max(id) from doc_data into i,v_max_id; -- for verbosing in perf_log.stack
    for
        select
            id
            ,doc_id
            ,ware_id
            ,qty
            ,cost_purchase
            ,cost_retail
            ,dts_edit
        from doc_data d
        where d.id between coalesce(:a_doc_data_id, -9223372036854775807) and coalesce(:a_doc_data_id, 9223372036854775807)
              and
              d.ware_id between coalesce(:a_ware_id, -9223372036854775807) and coalesce(:a_ware_id, 9223372036854775807)
        --as cursor cd
        into
            id
            ,doc_id
            ,ware_id
            ,qty
            ,cost_purchase
            ,cost_retail
            ,dts_edit
    do
    begin
        in autonomous transaction do
        insert into zdoc_data(
            id
            ,doc_id
            ,ware_id
            ,qty
            ,cost_purchase
            ,cost_retail
            ,dts_edit
            ,dump_att
            ,dump_trn
        )
        values(
            :id
            ,:doc_id
            ,:ware_id
            ,:qty
            ,:cost_purchase
            ,:cost_retail
            ,:dts_edit
            ,:v_curr_att
            ,:v_curr_trn
        );
        if ( mod(i, v_step) = 0 ) then
            in autonomous transaction do
            update perf_log g set g.stack = 'doc_data: id='||:id||', max='||:v_max_id
            where g.id = :v_perf_progress_id;
        i = i + 1;
    end
    ----------------------------------------------------------------------------
    -- 27.06.2014 dump dirty data from  ### q d i s t r  ###
    select 0, max(id) from v_qdistr_source into i,v_max_id; -- for verbosing in perf_log.stack
    for
        select
            id
            ,doc_id
            ,worker_id
            ,ware_id
            ,snd_optype_id
            ,snd_id
            ,snd_qty
            ,rcv_optype_id
            ,rcv_id
            ,rcv_qty
            ,snd_purchase
            ,snd_retail
            ,rcv_purchase
            ,rcv_retail
            ,trn_id
            ,dts
        from v_qdistr_source d
        where d.ware_id between coalesce(:a_ware_id, -9223372036854775807) and coalesce(:a_ware_id, 9223372036854775807)
        --as cursor cq
        into
            id
            ,doc_id
            ,worker_id
            ,ware_id
            ,snd_optype_id
            ,snd_id
            ,snd_qty
            ,rcv_optype_id
            ,rcv_id
            ,rcv_qty
            ,snd_purchase
            ,snd_retail
            ,rcv_purchase
            ,rcv_retail
            ,trn_id
            ,dts_edit
    do
    begin
        in autonomous transaction do
        insert into zqdistr (
            id
            ,doc_id
            ,worker_id
            ,ware_id
            ,snd_optype_id
            ,snd_id
            ,snd_qty
            ,rcv_optype_id
            ,rcv_id
            ,rcv_qty
            ,snd_purchase
            ,snd_retail
            ,rcv_purchase
            ,rcv_retail
            ,trn_id
            ,dts
            ,dump_att
            ,dump_trn
        )
        values(
            :id
            ,:doc_id
            ,:worker_id
            ,:ware_id
            ,:snd_optype_id
            ,:snd_id
            ,:snd_qty
            ,:rcv_optype_id
            ,:rcv_id
            ,:rcv_qty
            ,:snd_purchase
            ,:snd_retail
            ,:rcv_purchase
            ,:rcv_retail
            ,:trn_id
            ,:dts_edit
            ,:v_curr_att
            ,:v_curr_trn
        );
        if ( mod(i, v_step) = 0 ) then
            in autonomous transaction do
            update perf_log g set g.stack = 'v_qdistr_source: id='||:id||', max='||:v_max_id
            where g.id = :v_perf_progress_id;
        i = i + 1;
    end
    ----------------------------------------------------------------------------
    -- 27.06.2014 dump dirty data from  ### q s t o r n e d  ###
    select 0, max(id) from v_qstorned_source into i,v_max_id; -- for verbosing in perf_log.stack
    for
        select
            id
            ,doc_id
            ,worker_id
            ,ware_id
            ,snd_optype_id
            ,snd_id
            ,snd_qty
            ,rcv_optype_id
            ,rcv_id
            ,rcv_qty
            ,snd_purchase
            ,snd_retail
            ,rcv_purchase
            ,rcv_retail
            ,trn_id
            ,dts
        from v_qstorned_source d
        where d.ware_id between coalesce(:a_ware_id, -9223372036854775807) and coalesce(:a_ware_id, 9223372036854775807)
        into
            id
            ,doc_id
            ,worker_id
            ,ware_id
            ,snd_optype_id
            ,snd_id
            ,snd_qty
            ,rcv_optype_id
            ,rcv_id
            ,rcv_qty
            ,snd_purchase
            ,snd_retail
            ,rcv_purchase
            ,rcv_retail
            ,trn_id
            ,dts_edit
    do
    begin
        in autonomous transaction do
        insert into zqstorned(
            id
            ,doc_id
            ,worker_id
            ,ware_id
            ,snd_optype_id
            ,snd_id
            ,snd_qty
            ,rcv_optype_id
            ,rcv_id
            ,rcv_qty
            ,snd_purchase
            ,snd_retail
            ,rcv_purchase
            ,rcv_retail
            ,trn_id
            ,dts
            ,dump_att
            ,dump_trn
        )
        values(
            :id
            ,:doc_id
            ,:worker_id
            ,:ware_id
            ,:snd_optype_id
            ,:snd_id
            ,:snd_qty
            ,:rcv_optype_id
            ,:rcv_id
            ,:rcv_qty
            ,:snd_purchase
            ,:snd_retail
            ,:rcv_purchase
            ,:rcv_retail
            ,:trn_id
            ,:dts_edit
            ,:v_curr_att
            ,:v_curr_trn
         );
        if ( mod(i, v_step) = 0 ) then
            in autonomous transaction do
            update perf_log g set g.stack = 'v_qstorned_source: id='||:id||', max='||:v_max_id
            where g.id = :v_perf_progress_id;
        i = i + 1;
    end
    ---------------------------------------------------------------------------
    -- 04.07.2014 dump dirty data from  ### p d i s t r,    p s t o r n e d  ###
    select 0, max(id) from pdistr into i,v_max_id; -- for verbosing in perf_log.stack
    for
        select
            id
            ,worker_id
            ,agent_id
            ,snd_optype_id
            ,snd_id
            ,snd_cost
            ,rcv_optype_id
            ,trn_id
        from pdistr
        into
            id
            ,worker_id
            ,agent_id
            ,snd_optype_id
            ,snd_id
            ,snd_cost
            ,rcv_optype_id
            ,trn_id
    do
    begin
        in autonomous transaction do
        insert into zpdistr(
            id
            ,worker_id
            ,agent_id
            ,snd_optype_id
            ,snd_id
            ,snd_cost
            ,rcv_optype_id
            ,trn_id
            ,dump_att
            ,dump_trn
        )
        values(
            :id
            ,:worker_id
            ,:agent_id
            ,:snd_optype_id
            ,:snd_id
            ,:snd_cost
            ,:rcv_optype_id
            ,:trn_id
            ,:v_curr_att
            ,:v_curr_trn
         );
        if ( mod(i, v_step) = 0 ) then
            in autonomous transaction do
            update perf_log g set g.stack = 'pdistr: id='||:id||', max='||:v_max_id
            where g.id = :v_perf_progress_id;
        i = i + 1;
    end

    ----------------------------------------------------------------------------
    select 0, max(id) from pstorned into i,v_max_id; -- for verbosing in perf_log.stack
    for
        select
            id
            ,worker_id
            ,agent_id
            ,snd_optype_id
            ,snd_id
            ,snd_cost
            ,rcv_optype_id
            ,rcv_id
            ,rcv_cost
            ,trn_id
        from pstorned
        into
            id
            ,worker_id
            ,agent_id
            ,snd_optype_id
            ,snd_id
            ,snd_cost
            ,rcv_optype_id
            ,rcv_id
            ,rcv_cost
            ,trn_id
    do
    begin
        in autonomous transaction do
        insert into zpstorned(
            id
            ,worker_id
            ,agent_id
            ,snd_optype_id
            ,snd_id
            ,snd_cost
            ,rcv_optype_id
            ,rcv_id
            ,rcv_cost
            ,trn_id
            ,dump_att
            ,dump_trn
        )
        values(
            :id
            ,:worker_id
            ,:agent_id
            ,:snd_optype_id
            ,:snd_id
            ,:snd_cost
            ,:rcv_optype_id
            ,:rcv_id
            ,:rcv_cost
            ,:trn_id
            ,:v_curr_att
            ,:v_curr_trn
         );
        if ( mod(i, v_step) = 0 ) then
            in autonomous transaction do
            update perf_log g set g.stack = 'pstorned: id='||:id||', max='||:v_max_id
            where g.id = :v_perf_progress_id;
        i = i + 1;
     end

    in autonomous transaction do
    begin
        update perf_log g
        set g.info = 'finish, tra_'||:v_curr_trn,
            g.dts_end = 'now'
            --stack = fn_get_stack(1)
        where g.id = :v_perf_semaphore_id;
        delete from perf_log g where g.id = :v_perf_progress_id;
    end

when any do
    begin
        -- nop: supress ANY exception! We now dump dirty data due to abnormal case! --
    end
end

^ -- zdump4dbg

set term ;^
commit; 

set list on;
set echo off;
select 'oltp_misc_debug.sql finish at ' || current_timestamp as msg from rdb$database;
set list off;
commit;

-- #################################
-- End of script oltp_misc_debug.sql  // ###   O P T I O N A L   ###
-- Next run: oltp_split_heavy_tabs_0 | 1.sql - depending on config parameter 'create_with_split_heavy_tabs'
-- #################################
