-- to be continued: aux script for removing unnecessary DB objects from SLAVE db.
set list on;
set bail on;

select 'set bail on;' as " " from rdb$database;
select 'set echo on;' as " " from rdb$database;
select 'set autoddl on;' as " " from rdb$database;
select 'set stat on;' as " " from rdb$database;

set term ^;
execute block returns(" " varchar(255)) as
    declare cname varchar(64);
    declare rname varchar(64);
begin
    for
        select
            rc.rdb$constraint_name
            ,rc.rdb$relation_name
        from rdb$relation_constraints rc join rdb$relations rr using(rdb$relation_name) 
        where 
            rr.rdb$system_flag=0
            and
            --upper( rc.rdb$constraint_type ) not in ( upper('primary key'), upper('not null') ) 
            (
                upper( rc.rdb$constraint_type ) in ( upper('foreign key'), upper('check') )
                or
                upper( rc.rdb$constraint_type ) = upper( 'unique' )
                and exists
                    (
                        select * from rdb$relation_constraints rp 
                        where 
                            rp.rdb$relation_name = rc.rdb$relation_name 
                            and rp.rdb$constraint_type = upper('primary key')  
                    )
            )
        into cname, rname
    do begin
        " " = 'alter table ' || trim(rname) || ' drop constraint  ' || trim(cname) || ';' ;
        suspend;
    end
end
^

execute block returns(" " varchar(255)) as
    declare tname varchar(64);
begin
    for
        select
            rt.rdb$trigger_name
        from rdb$triggers rt
        where rt.rdb$system_flag = 0 and  rt.rdb$trigger_inactive = 0
        into tname
    do begin
        " " = 'alter trigger ' || trim(tname) || ' inactive;' ;
        suspend;
    end
end
^

execute block returns(" " varchar(255)) as
    declare iname varchar(64);
begin
    for
        select
            ri.rdb$index_name
        from rdb$indices ri
        where 
            ri.rdb$system_flag = 0 
            and ri.rdb$unique_flag is distinct from 1
            and ri.rdb$index_inactive is distinct from 1
        into iname
    do begin
        " " = 'alter index ' || trim(iname) || ' inactive;' ;
        suspend;
    end
end
^

set term ;^
/*
RDB$INDEX_NAME
RDB$RELATION_NAME
RDB$INDEX_ID
RDB$UNIQUE_FLAG
RDB$DESCRIPTION
RDB$SEGMENT_COUNT
RDB$INDEX_INACTIVE
RDB$INDEX_TYPE
RDB$FOREIGN_KEY
RDB$SYSTEM_FLAG
RDB$EXPRESSION_BLR
RDB$EXPRESSION_SOURCE
RDB$STATISTICS
CONSTRAINT RDB$INDEX_5:
  Unique key (RDB$INDEX_NAME)
*/
