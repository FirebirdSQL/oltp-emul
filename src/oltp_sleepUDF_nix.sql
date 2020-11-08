set bail on;
set list on;
set count on;
commit;

set transaction no wait;

set term ^;
execute block returns( DROP_existent_UDF_sttm varchar(80) ) as
    declare v_udf_func varchar(255);
begin
    for
        select trim(rdb$function_name)
        from rdb$functions 
        where 
            upper( trim(rdb$function_name) ) similar to '(DELAY|SLEEP|PAUSE)'
            -- do not: and rdb$legacy_flag=1  -- added in 3.0 only, ~summer 2018
            and rdb$system_flag is distinct from 1
            and rdb$module_name is not null 
            and rdb$entrypoint is not null
        into v_udf_func
    do begin
        DROP_existent_UDF_sttm = 'drop external function ' || v_udf_func;
        execute statement :DROP_existent_UDF_sttm;
        suspend;
    end
end
^
set term ;^
commit;

declare external function sleep
    integer
returns integer by value
entry_point 'SleepUDF' module_name 'SleepUDF'
;
commit;

-- added 17.05.2022\0: this UDF must be avail for non-privileged users (actually needed in FB 3.x only):
-- grant execute on function sleep to public;
-- commit;


set list on;
select 'Check results for UDF that will make pauses in execution:' as msg from rdb$database;
set term ^;
execute block returns(
    "timestamp_before_sleep_UDF" timestamp,
    "timestamp__after_sleep_UDF" timestamp,
    "check_elapsed_milliseconds" int,
    "multiplier_for_sleep_arg" smallint
) as
    declare c int;
    declare n int;
begin
    n=0;
    while (n < 6) do
    begin
        "timestamp_before_sleep_UDF" = cast('now' as timestamp);
        "multiplier_for_sleep_arg" = cast( power(10,n) as int );
        c = sleep( "multiplier_for_sleep_arg" );
        "timestamp__after_sleep_UDF" = cast('now' as timestamp);
        "check_elapsed_milliseconds" = datediff(millisecond from "timestamp_before_sleep_UDF" to "timestamp__after_sleep_UDF");
        if ( "check_elapsed_milliseconds" < 500 ) then
            n = n+1;
        else
            leave;
    end
    suspend;
end
^
set term ^;
commit;

select trim(rdb$function_name) as ext_function_name
from rdb$functions 
where 
    upper( trim(rdb$function_name) ) similar to '(DELAY|SLEEP|PAUSE)'
    -- do not: and rdb$legacy_flag=1  -- added in 3.0 only, ~summer 2018
    and rdb$system_flag is distinct from 1
    and rdb$module_name is not null 
    and rdb$entrypoint is not null ;
