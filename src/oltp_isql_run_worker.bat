@echo off
setlocal enabledelayedexpansion enableextensions

set THIS_DIR=%~dp0
set THIS_DIR=!THIS_DIR:~0,-1!
for /f %%a in ("%~dp0.") do (
    for %%i in ("%%~dpa")  do (
        set PARENTDIR=%%~dpi
        set PARENTDIR=!PARENTDIR:~0,-1!
    )
    for %%i in ("%%~dpa.") do (
        set GRANDPDIR=%%~dpi
        set GRANDPDIR=!GRANDPDIR:~0,-1!
    )
)

cd /d !THIS_DIR!

path=..\util;%path%
set isc_user=
set isc_password=

rem limits for log of work and errors
rem (zap if size exceed and fill again from zero):
set maxlog=25000000
set maxerr=25000000

rem -----------------------------------------------
rem ###############  mandatory args: ##############
rem -----------------------------------------------

set sid=%1
set winq=%2
set conn_pool_support=%3
set sql=!%4!

@rem ##################################
@rem ### name of final text report: ###
@rem ### !tmpdir!\oltp40.report.txt ###
@rem ##################################
set log4all=!%5!

for /f %%f in ("!log4all!") do (
    set tmpdir=%%~dpf
    set tmpdir=!tmpdir:~0,-1!
)


@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@rem lognm: !tmpdir!\oltp40_IMAGE-PC1-0001
@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
set lognm=!tmpdir!\%6


set build=%7

@rem fname = value of config parameter file_name_with_test_params: regular | benchmark
set fname=%8

@rem set build=WI-T4.0.0.1227
@rem set build=WI-V3.0.4.33054

echo %build% | findstr /r /i /c:"-[V,T]2.5.[0-9].[0-9]" >nul
if NOT errorlevel 1 (
    set fb=25
) else (
    echo %build% | findstr /r /i /c:"-[V,T]3.[0-9].[0-9]" >nul
    if NOT errorlevel 1 (
        set fb=30
    ) else (
        echo %build% | findstr /r /i /c:"-[V,T]4.[0-9].[0-9]" >nul
        if NOT errorlevel 1 (
            set fb=40
        ) else (
            echo.
            echo Could not define numbers in major FB version: 25, 30 or 40.
            echo.
            echo ########################################################
            echo Ensure that this batch is called from 1run_oltp_emul.bat 
            echo ########################################################
            echo.
            pause
            goto fin
        )
    )
)


rem %tmpdir%\oltpNN.report.txt - name of file for overall performance report
rem (do NOT overwrite it here, it has already some info that was added there in 1run*.bat):

@rem @start /min oltp_isql_run_worker.bat %%i %winq% conn_pool_support tmp_run_test_sql log4all   %logbase%-!k:~1,4!   %build%   %file_name_with_test_params%
@rem                                       1     2          3                 4            5              6               7                 8
if .1.==.0. (
    echo 1 sid    = %sid%
    echo 2 winq   = %winq%
    echo 3 conn_pool_support = %conn_pool_support%
    echo 4 sql    = %sql%
    echo 5 log4all= %log4all%
    echo 6 lognm  = %lognm%
    echo 7 build  = %build%
    echo 8 fname  = %file_name_with_test_params%
    dir /-c %sql% | findstr %sql%
    dir /-c %log4all% | findstr %log4all%
    echo fb     = %fb%
    echo tmpdir = !tmpdir!
)

@rem sid    = 1
@rem winq   = 10
@rem fb     = 25
@rem conn_pool_support = 1
@rem sql    = c:\temp\logs.oltp25\sql\tmp_random_run.sql
@rem log4all= c:\temp\logs.oltp25\oltp25.report.txt
@rem lognm  = c:\temp\logs.oltp25\oltp25_IMAGE-PC1-0001
@rem build  = WI-V2.5.9.27117
@rem fname  = regular


@rem log where current acitvity of this ISQL will be:
set log=%lognm%.log

@rem where ERRORS will be for this ISQL:
set err=%lognm%.err

@rem Aux file for some messages
set tmp=%lognm%.tmp

@rem Cumulative log with brief info about running process state:
set sts=%lognm%.sts

set rpt=%lognm%.perf_report.sql

call :repl_with_bound_quotes %log% log
call :repl_with_bound_quotes %err% err
call :repl_with_bound_quotes %tmp% tmp
call :repl_with_bound_quotes %sts% sts
call :repl_with_bound_quotes %rpt% rpt

echo tmp=%tmp%
echo log=%log%
echo err=%err%
echo rpt=%rpt%
echo sts=%sts%

@rem Launch of more than 150 sessions from one PC box: some of them
@rem could not start because of strange result of creating file %tmp%:
@rem Windows did create DIRECTORY with name = %tmp% instead of FILE!
@rem Because of this, we have to ensure that there is no dir or file
@rem with such name:

rd /q /s %sts% 1>nul 2>&1

for /d %%i in (%tmp% %log% %err% %rpt%)  do (
  @rem todo later: https://stackoverflow.com/questions/138981/how-to-test-if-a-file-is-a-directory-in-a-batch-script
  for %%f in (%%i) do (
      if exist %%~sf\nul (
          rd /q /s %%~sf
      ) else if exist %%~sf (
          del /q %%~sf
      )
  )
)


@rem Only for 3.0: we can get content of firebird.log before and after test
@rem and compare them:

set fblog_begnm=oltp%fb%_fb_log_when_test_started.log
set fblog_endnm=oltp%fb%_fb_log_when_test_finished.log
set fblog_start=!tmpdir!\%fblog_begnm%
set fblog_final=!tmpdir!\%fblog_endnm%

call :repl_with_bound_quotes %fblog_start% fblog_start
call :repl_with_bound_quotes %fblog_final% fblog_final

if .%is_embed%.==.1. (
    set dbauth=
    set dbconn=%dbnm%
) else (
    set dbauth=-user %usr% -password %pwd%
    set dbconn=%host%/%port%:%dbnm%
)

for %%i in ("%sql%") do (
    set trace_lst=%%~dpitmp_trace.lst
    set trace_sql=%%~dpitmp_trace.sql
    set trace_log=%%~dpitmp_trace.log
    set trace_cfg=%%~dpitmp_trace.conf
    set trace_run=%%~dpitmp_run1t.sql
    set trace_prs=%%~dpitmp_parse.log
    set trace_sav=%%~dpitmp_tsave.sql

    @rem Define name of .sql script that will be launched by THIS - and only this - command window.
    @rem This is name like "!tmppath!\sql\tmp_sid_10_starter.sql" etc, and it will create CONTEXT VAR
    @rem with session-level scope. Main script will be invoked from THIS starter, thus it will know
    @rem sequential ID of THIS command window: 1, 2, 3, ..., !winq!
    set sid_starter_sql=%%~dpitmp_sid_!sid!_starter.sql
)

set conn_as_locksmith=1

set check_for_locksmith=0
if not .%fb%.==.25. (
    if not .!mon_query_role!.==.. (
        if not .!mon_usr_prefix!.==.. (
            @rem We create non-privileged users in all cases except mon_unit_perf=0
            @rem Working as NON_dba is much closer to the real-world applications
            @rem then doing common business tasks as SYSDBA.
            set check_for_locksmith=1
        )
    )
)

if .!check_for_locksmith!.==.1. (

    if .%mon_unit_perf%.==.1. (
        @rem  mon_unit_perf=1 requires that *each* worker will gather monitoring data
        @rem  before and after each selected business action, i.e. very frequently.
        @rem  Despite that every worker is interesting only for data related to himself
        @rem  (i.e. makes filter 'where mon$attachment_id = curent_connection'), every
        @rem  mon$ gathering involves all other workers to make 'dumps' of their state
        @rem  to the monitoring data pool.
        @rem  This leads to EXTREMELY high penalty of performance for approx. 15 times.
        @rem  -----------------------
        @rem  Engine FB 3.x was optimized for this case: if monitoring data are queried
        @rem  by non-privileged user then all connections from other users will not take
        @rem  in account this event and their work will continue without any delay for
        @rem  dumping data for this user.
        @rem  See: http://sourceforge.net/p/firebird/code/62745
        @rem  "Tag the shmem session clumplets with username. This allows much faster lookups for non-locksmith users."
        @rem  -----------------------
        @rem  Benchmark shows that cost of monitoring in this case is almost zero:
        @rem  overall performance score is equal to the case when mon_unit_perf=0.
        @rem  For this reason ALL attachments must connect as NON-privileged users
        @rem  (with different names for each connection):

        set conn_as_locksmith=0

    ) else if .%mon_unit_perf%.==.2. (
        if .%sid%.==.1. (
            @rem First ISQL session will gather mon$ info for *ALL* attachments.
            @rem This means that for SID=1 we must play as SYSDBA:

            set conn_as_locksmith=1

        ) else (
            @rem  Other attachments do NOT query monitoring tables.
            @rem  They must connect as NON-privileged users
            @rem  /with different names for each connection/

            set conn_as_locksmith=0

        )
    ) else (
        @rem ####################################################################
        @rem ### ::: NB ::: mon_unit_perf = 0 --> all sessions work as SYSDBA ###
        @rem ####################################################################
        @rem See also: 1run_oltp_emul.bat, routine: adjust_grants

        set conn_as_locksmith=1

    )
)


(

    echo -- Generated !date! !time! by %~f0.
    echo -- Do NOT edit. This script will be removed after test.

    if !conn_as_locksmith! EQU 0 (
        echo -- See: http://sourceforge.net/p/firebird/code/62745
        echo -- "Tag the shmem session clumplets with username. This allows much faster lookups for non-locksmith users."
        echo -- See config for logins prefix and role which must be used for non-privileged users:
        echo -- mon_usr_prefix=%mon_usr_prefix%, mon_query_role=%mon_query_role%

        set /a k=10000+!sid!
        set v_username_for_sid=!k:~1,4!
        echo rollback;
        echo connect '%host%/%port%:%dbnm%' user !mon_usr_prefix!!v_username_for_sid! password '123' role '!mon_query_role!';

    ) else (

        if not .%fb%.==.25. (
            echo -- #############################################################################
            echo -- ###                   w o r k   a s   S Y S D B A                         ###
            echo -- #############################################################################
            if .%mon_unit_perf%.==.0. (
                echo -- NOTE. config parameter mon_unit_perf = 0. All sessions can work as '%usr%'
            ) else if .%mon_unit_perf%==.1. (
                echo -- NOTE: config parameter 'mon_unit_perf' = 1 but parameters 'mon_usr_prefix' and 'mon_query_role'
                echo -- are undefined /commented/. All ISQL sessions will work as '$usr'.
                echo -- Queries to monitoring tables by each session will FORCE ALL other connections to transfer their own
                echo -- monitoring data into the common monitor pool thus performance will be SIGNIFICANTLY REDUCED.
            ) else if .%mon_unit_perf%==.2. (
                if .%sid%.==.1. (
                    echo -- NOTE. Text configuration parameter mon_unit_perf = 2.
                    echo -- First launched ISQL session will query mon\$ data for
                    echo -- ALL existing attachments thus have to work as SYSDBA.
          	    )
            )
        )
        echo rollback;
        echo connect '%host%/%port%:%dbnm%' user '%usr%' password '%pwd%';
    )
    echo.
    echo set term ^^;
    echo execute block as
    echo begin
    echo     -- Define 'sequential number' of current ISQL session and make it be known 
    echo     -- for main script and every business operations that are called from there:
    echo     -- NB: name 'WORKER_SEQUENTIAL_NUMBER' is used in procedures for storing
    echo     -- value in doc_list.worker_id for possible separation of scope that is avaliable
    echo     -- for each ISQL session. Purpose - reduce frequency of lock conflicts.
    echo     rdb$set_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER', '%sid%'^);
    echo     rdb$set_context('USER_SESSION', 'WORKER_SEQ_NUMB_4RESTORE', '%sid%'^);
    echo.
    echo end^^
    echo set term ;^^
    echo -- Call main script that was created on prepare phase of oltp-emul scenario.
    echo -- Usually this is C:\temp\logs.oltpNN\sql\tmp_random_run.sql 
    echo in %sql%;

) > !sid_starter_sql!

@rem we do NOT need to specify neither DB_name nor '-user .. -pas ...' command switches
@rem because they already are in !sid_starter_sql!:

set run_isql=%fbc%\isql -now -q -n -pag 9999 -i !sid_starter_sql!



(
    echo.
    echo !date! !time!, batch running now: %~f0 - check command for launch ISQL:
    echo --- beg ---
    echo !run_isql!
    echo --- end ---
    echo.
) >!tmp!

type !tmp!
type !tmp! >>%sts%

@rem echo sid=%sid%

set fbsvcrun=%fbc%\fbsvcmgr

call :repl_with_bound_quotes %fbsvcrun% fbsvcrun

@rem Result when 'fbc' contain spaces: "C:\Program Files\Firebird Database Server 2.5.5\bin\fbsvcmgr" 
@rem (should be invoked by 'cmd /c' without any troubles).

if .%is_embed%.==.1. (
    set fbsvcrun=%fbsvcrun% service_mgr
) else (
    set fbsvcrun=%fbsvcrun% %host%/%port%:service_mgr user %usr% password %pwd%
)
:: fbsvcrun="C:\Program Files\Firebird Database Server 2.5.5\bin\fbsvcmgr" localhost/3255:service_mgr -user SYSDBA -password masterke

set run_get_fb_ver=%fbsvcrun% info_server_version info_implementation

if NOT .%fb%.==.25. (
    set run_get_fb_log=%fbsvcrun% action_get_fb_log
) else (
    set run_get_fb_log=%fbsvcrun% action_get_ib_log
    @rem                                     ^------ for 2.5.x: "i", not "f" !
)

set run_get_db_sts=%fbsvcrun% action_db_stats sts_data_pages sts_idx_pages sts_record_versions dbname %dbnm%
set run_get_db_hdr=%fbsvcrun% action_db_stats sts_hdr_pages dbname %dbnm%
set run_db_validat=%fbsvcrun% action_validate dbname %dbnm% val_lock_timeout 1 
set run_fc_compare=fc.exe /w /n %fblog_start% %fblog_final%

if .%sid%.==.1. (

    if .%trc_unit_perf%.==.1. (

        set msg=First launching ISQL starts and stops TRACE before and after each packet - see config 'trc_unit_perf' parameter.
        echo !msg!
        echo !msg!>>%log4tmp%

        echo Building list of traced units...>>%log4tmp%

        (
            echo set heading off;
            echo select cast( list(unit,'^^^|'^) as varchar(4000^)^) from business_ops;
            echo set heading on;
        ) >%trace_sql%

        set run_4trc=%fbc%\isql %dbconn% -n -pag 9999 -i %trace_sql% %dbauth% 
        cmd /c !run_4trc! 1>%trace_log% 2>&1

        for /f %%a in (%trace_log%) do (
          set traced_units=%%a
        )

        @rem Pattern for findstr when we'll parse trace log: we have to replace all occurences of PIPE character with space:
        set unit_pattern=!traced_units:^^^|= !

        set msg=Done. traced_units=!traced_units!
        echo !msg!>>%log4tmp%

        for %%i in ("%dbnm%") do (
          set dbfx=%%~nxi
          set dbfn=%%~ni

          @rem Add default escape character = '\' in order trace can start when database contains
          @rem symbols from following list: - _ + % ^ { } ( ) [ ]

          set dbfx=!dbfx:-=\-!
          set dbfx=!dbfx:_=\_!
          set dbfx=!dbfx:+=\+!
          set dbfx=!dbfx:%%=\%%!
          set dbfx=!dbfx:^^=\^^!
          set dbfx=!dbfx:{=\{!
          set dbfx=!dbfx:}=\}!
          set dbfx=!dbfx:^(=\^(!
          set dbfx=!dbfx:^)=\^)!
          set dbfx=!dbfx:[=\[!
          set dbfx=!dbfx:]=\]!

          set dbfn=!dbfn:-=\-!
          set dbfn=!dbfn:_=\_!
          set dbfn=!dbfn:+=\+!
          set dbfn=!dbfn:%%=\%%!
          set dbfn=!dbfn:^^=\^^!
          set dbfn=!dbfn:{=\{!
          set dbfn=!dbfn:}=\}!
          set dbfn=!dbfn:^(=\^(!
          set dbfn=!dbfn:^)=\^)!
          set dbfn=!dbfn:[=\[!
          set dbfn=!dbfn:]=\]!
       
        )

        set msg=Creating temporary config file for trace: %trace_cfg%...
        echo !msg!
        echo !msg!>>%log4tmp%

        (
            if .%fb%.==.25. (
                echo set heading off;
                echo shell del %trace_cfg% 2^>nul;
                echo out %trace_cfg%;
                echo select '^<database (%%[\\/](!dbfn!^).fdb^)^|(!dbfn!^)^>' from rdb$database union all
                echo select '    enabled true' from rdb$database union all
                echo select '    time_threshold 0' from rdb$database union all
                @rem echo select '    include_filter = ''%%!traced_units:^^=!%%''' from rdb$database union all
                echo select '    include_filter = ''%%(from sp_^|from srv_^)%%''' from rdb$database union all
                echo select '    exclude_filter = ''%%execute block%%''' from rdb$database union all
                echo select '    log_statement_finish true' from rdb$database union all
                echo select '    print_perf true' from rdb$database union all
                echo select '    max_sql_length = 16384' from rdb$database union all
                echo select '    connection_id '^|^|current_connection from rdb$database union all
                echo select '^</database^>' from rdb$database;
                echo out;
            ) else (
                echo set heading off;
                echo shell del %trace_cfg% 2^>nul;
                echo out %trace_cfg%;
                echo select 'database = (%%[\\/](security[[:DIGIT:]]+^).fdb^|(security.db^)^)' from rdb$database union all
                echo select '{' from rdb$database union all
                echo select '   enabled = false' from rdb$database union all
                echo select '}' from rdb$database;

                echo select 'database=(%%[\\/]!dbfx!^|!dbfn!^)^' from rdb$database union all
                echo select '{'  from rdb$database union all
                echo select '    enabled = true' from rdb$database union all
                echo select '    log_initfini = false' from rdb$database union all
                echo select '    time_threshold = 0' from rdb$database union all
                @rem echo select '    include_filter = ''%%!traced_units:^^=!%%''' from rdb$database union all
                echo select '    include_filter = %%(from[[:WHITESPACE:]]+sp_^|from[[:WHITESPACE:]]+srv_^)%%' from rdb$database union all
                echo select '    exclude_filter = %%(execute[[:WHITESPACE:]]+block^)%%' from rdb$database union all
                echo select '    log_statement_finish = true' from rdb$database union all
                echo select '    print_perf = true' from rdb$database union all
                echo select '    max_sql_length = 16384' from rdb$database union all
                echo select '    connection_id='^|^|current_connection from rdb$database union all
                echo select '}' from rdb$database;
                echo out;
            )
            echo shell start /min cmd /c "%fbsvcrun% action_trace_start trc_cfg %trace_cfg% 1>%trace_log% 2>&1";
        ) > %trace_sql%

        (
            echo in %trace_sql%;
            echo in !sid_starter_sql!;
            @rem echo in %sql%;
        ) > %trace_run%

        echo Script for creating trace config, %trace_sql%: >> %log4tmp%
        type %trace_sql% >> %log4tmp%
        echo. >> %log4tmp%
        echo Script for running by 1st ISQL window, %trace_run%: >> %log4tmp%
        type %trace_run% >> %log4tmp%

        set run_isql=%fbc%\isql %dbconn% -now -q -n -pag 9999 -i %trace_run% %dbauth% 

    )
    @rem end of block for preparing trace when test config parameter 'trc_unit_perf' = 1
    
    echo This ISQL session will make performance report after test make selfstop.>>%sts%

    call :sho "Gathering firebird.log before opening 1st window for obtaining new text which will appear in it during test." %log4all%
    %run_get_fb_log% 1>%fblog_start% 2>%err%
    (
        echo %time%. Got:
        for /f "delims=" %%a in ('find /v /c "" %fblog_start%') do echo STDOUT: %%a (number of rows in extracted log^)
        for /f "delims=" %%a in ('type %err%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1


    echo.>>%log4all%
    echo Result of DIR command for firebird.log BEFORE test start:>>%log4all%
    dir /-c %fblog_start% | findstr /i /c:"%fblog_begnm%" 1>>%log4all% 2>&1
    dir /-c %fblog_start% | findstr /i /c:"%fblog_begnm%" 1>>%log4tmp% 2>&1
    echo.>>%log4all%
  
    call :sho "Preparing for test finished. Now %winq% ISQL sessions are launching." %log4tmp%

)
@rem sid=1

@set sql_execution_idx=0
@echo off

call :sho "Start ISQL #%sid% of total %winq%." %sts%

if .%sid%.==.1. (
    call :sho "SID=1. This ISQL session will create reports after test finish." %sts%
)


@rem ########################|  S M O O T H    W O R K L O A D   G R O W T H  |##########################
@rem # Make smooth workload increasing. ISQl with sid=1...%winq% must perform attachments NOT INSTANTLY #
@rem # otherwise some of them will receive TCP-related failures which end with:                         #
@rem #     Statement failed, SQLSTATE = 08004                                                           #
@rem #     connection rejected by remote interface                                                      #
@rem ####################################################################################################

@rem Create temporary VBS with unique name FOR_EACH launching ISQL otherWise lot of strange errors will occured in MS script host:
@rem "CScript Error: Loading script ... failed (The process cannot access the file because it is being used by another process. )"
call :getRandom gen_vbs %sid%

set /a random_delay=1
set /a min_delay = 1 + %sid% / 25
set /a max_delay = 2 + %sid% / 25

set use_cps=0
if %max_cps% GEQ 10 (
    if %max_cps% LEQ 100 (
        @rem Max rate of new attachments appearance set to some reasonable value.
        set use_cps=1
    )
)

if .!use_cps!.==.1. (
    if %winq% GTR %max_cps% (
        set mcase=a
        set /a min_delay = 1 + %sid% / %max_cps%
        set /a max_delay = 1 + %sid% / %max_cps%
        call :sho "SID=%sid%. Number of sessions greater than max_cps=%max_cps%. Delay for this SID is !max_delay! seconds." %sts%
    ) else (
        set mcase=b
        set /a min_delay = 1
        set /a max_delay = 4
        call :sho "SID=%sid%. Number of sessions is too small, delay will be from !min_delay! fo !max_delay! seconds." %sts%
    )
) else (
    set mcase=c
    if %max_cps% EQU 0 (
        set mcase=d
        set /a min_delay=0
        set /a max_delay=0
        call :sho "SID=%sid%. Config parameter 'max_cps' is 0. Heavy workload will be for big number of sessions." %sts%
    ) else (
        sho "SID=%sid%. Config parameter 'max_cps' = %max_cps% is out of reasonable scope. Delay will be from !min_delay! fo !max_delay! seconds." %sts%
    )
)


if .1.==.0. (
    echo ##### debug code, do not delete #####
    echo mcase=!mcase!, sid=%sid%, max_cps=%max_cps%, min_delay=!min_delay!, max_delay=!max_delay!
    call :getRandom get_rnd %sid% !min_delay! !max_delay! random_delay
    echo Result: random_delay=!random_delay!
    echo #####################################
    pause
    exit
)

@rem ###############################
@rem ###   m a i n     l o o p   ###
@rem ###############################

:start

    set /a sql_execution_idx=!sql_execution_idx!+1

    if %sid% GTR 1 (
        if !sql_execution_idx! EQU 1 (
            if !sleep_min! GEQ !sleep_max! (
                set /a sleep_min=1
            )
            call :sho "SID=%sid%. Point before execution packet !sql_execution_idx!." %sts%
            call :getRandom get_rnd %sid% !min_delay! !max_delay! random_delay

            if !random_delay! GTR 0 (
                set msg_suff=Get random delay from scope !min_delay!..!max_delay!. Result: !random_delay! seconds
                if %max_cps% GTR 0 (
                    call :sho "Parameter 'max_cps'=%max_cps% connections per second. !msg_suff!" %sts%
                ) else (
                    call :sho "Parameter 'warm_time'=%warm_time% minutes. !msg_suff!" %sts%
                )

                @rem ################################################################
                @rem ###    p a u s e      u s i n g      C S C R I P T   //t:NNN  ##
                @rem ################################################################
                @rem //t:nn -- Maximum time a script is permitted to run
                @rem NB: we have to copy script to separate file for each SID otherwise strange error will raise in many of launching sessions:
                @rem "CScript Error: Loading script ... failed (The process cannot access ... used by another process.)"

                copy !tmpdir!\sql\tmp_longsleep.vbs.tmp !tmpdir!\sql\tmp_sid_%sid%_sleep.vbs.tmp 1>nul

                set run_cmd=%systemroot%\system32\cscript.exe //nologo //e:vbscript !tmpdir!\sql\tmp_sid_%sid%_sleep.vbs.tmp !random_delay! !random_delay!

                call :sho "SID=%sid%. Pause is starting. Command: !run_cmd!" %sts%
                cmd /c !run_cmd! 1>>%sts% 2>&1

                call :sho "SID=%sid%. Pause finished. Start ISQL to make attachment and work..." %sts%
                del !tmpdir!\sql\tmp_sid_%sid%_sleep.vbs.tmp
            ) else (
                call :sho "SID=%sid%. Start ISQL without pause: random_delay=!random_delay!." %sts%
            )
        ) else (
            call :sho "SID=%sid%. Packet=!sql_execution_idx!. Pause is skipped for all packets starting from 2nd." %sts%
        )
        @rem packet EQU 1

    ) else (
        @rem 26.10.2018. If SID=1 will get client error and this message in STDERR:
        @rem     Statement failed, SQLSTATE = 08004
        @rem     connection rejected by remote interface
        @rem -- then no report will exist after test finish!
        @rem See mailbox pz@..., subj: "OLTP-EMUL, heavy workload testing", sent to dimitr et al at 26.10.2018 17:13
        call :sho "SID=1. SKIP pause before attempt to attach. This session will make reports thus we allow it to make attach w/o any delay." %sts%
    )

    for /f "usebackq tokens=*" %%a in ('%log%') do set size=%%~za
    if .%size%.==.. set size=0
    if %size% gtr %maxlog% (
        call :sho "Size of log %log% = %size% - exceeds limit %maxlog%, make it EMPTY" %sts%
        del %log%
    )

    for /f "usebackq tokens=*" %%a in ('%err%') do set size=%%~za
    if .%size%.==.. set size=0
    if %size% gtr %maxerr% (
        call :sho "Size of log %err% = %size% - exceeds limit %maxlog%, make it EMPTY" %sts%
        del %err%
    )

    echo ------------------------------------------
    (
        echo.
        echo RUNCMD: %run_isql%
        echo STDLOG: %log% 
        echo STDERR: %err%
        echo.
    ) >%tmp%
    type %tmp%
    type %tmp% >> %log%
    type %tmp% >> %sts%
    del %tmp%

    call :sho "SID=%sid%. Launch ISQL for executing packet N !sql_execution_idx!..." %sts%

    @rem ##############################
    @rem ###   R U N     I S Q L    ###
    @rem ##############################
    if .%use_mtee%.==.1. (
        %run_isql% 2>&1 1>>%log% | mtee /t /+ %err% >nul
    ) else (
        %run_isql% 1>>%log% 2>>%err%
    )

    @echo off

    @rem -----------------------------------------------------------------
    @rem Stop trace session that was launched for ISQL #1
    @rem -----------------------------------------------------------------

    if .%sid%.==.1. if .%trc_unit_perf%.==.1. (
        @rem NB: fvsvcmgr keeps open not only its own trace log but also one that is used for ISQL, i.e. %log%.
        @rem This is because we launched fbsvcmgr via start /min cmd /c "%fbc%\fbsvcmgr ... > %tmpdir%\tmp_trace.log"
        @rem - this command will open log for writing trace events but (tmp_trace.log) fbsvcmgr does not know that we
        @rem redirect ISQL output to other log = %tmpdir%\oltpNN_%computername%_001.log - thus we have to STOP trace
        @rem before doing any redirection to %tmpdir%\oltpNN_%computername%_001.log after get control here from ISQL.

        call :sho "Stop trace session that was launched for ISQL #1" %sts%

        %fbsvcrun% action_trace_list >!trace_lst! 2>&1
        type !trace_lst!>>%sts%


        for /f "tokens=1-3" %%a in ('findstr /i /c:"Session ID:" !trace_lst!') do (
            set run_repo=%fbsvcrun% action_trace_stop trc_id %%c
            call :sho "Command: !run_repo!" %sts%
            cmd /c "!run_repo!" 1>>%sts% 2>&1
        )
        ping -n 11 127.0.0.1>nul
        
        call :sho "Check that currently NO active trace sessions is running:" %sts%
        (
            echo ---- list begin -----
            %fbsvcrun% action_trace_list
            echo ---- list finish ----
        ) >>%sts%
        del !trace_lst!
    )

    call :sho "SID=%sid%. Completed packet N !sql_execution_idx!" %sts%

    if .%sid%.==.1. if .%trc_unit_perf%.==.1. (

        @rem Now we have to parse trace log and extract from it name of business action, whether result was successful and statistics.

        call :sho "Parsing trace log: obtaining name of units, results of execution and statistics." %sts%

        findstr /i "EXECUTE_STATEMENT_FINISH ms fetched fetch(es) !unit_pattern!" !trace_log! > %trace_prs%
        del %trace_sav% 2>nul
        
        set /a row=0
        for /f "tokens=*" %%a in (%trace_prs%) do (
           set /a row=!row!+1
           set txt=%%a
           set /a elapsed_ms=0
           set /a reads=0
           set /a writes=0
           set /a fetches=0
           set /a marks=0
           set /a "rmod=!row! %% 4"

           if .!rmod!.==.1. (
             @rem 2015-12-24T03:28:35.037
             set dts_end=!txt:~0,23!
             set dts_end=cast('!dts_end:T= !' as timestamp^)
             (
                 echo -- Line: !txt! 
                 echo --   dts_end=!dts_end! 
             ) >> %trace_sav%
           )

           if .!rmod!.==.2. (
             for /f "tokens=1-4" %%d in ("!txt!") do (
               @rem select count(*) from sp_client_order
               set opname=%%g
               echo --   opname=!opname! >>%trace_sav%
             )
           ) 
           if .!rmod!.==.3. (
             for /f "tokens=1" %%d in ("!txt!") do (
               @rem 1 records fetched  __or__  0 records fetched
               set success=%%d
               echo --   success=!success! >>%trace_sav%
             )
           )
           if .!rmod!.==.0. (
             @rem Statistics. OMG...
             @rem 314 ms, 3 read(s), 6 write(s), 3957 fetch(es), 754 mark(s)
             for /f "tokens=1-10" %%d in ("!txt!") do (
               set num=%%d
               set chr=%%e
               if "!chr:~0,2!"=="ms" set elapsed_ms=!num!

               set num=%%f
               set chr=%%g
               if "!chr:~0,5!"=="read(" set reads=!num!
               if "!chr:~0,6!"=="write(" set writes=!num!
               if "!chr:~0,6!"=="fetch(" set fetches=!num!
               if "!chr:~0,5!"=="mark(" set marks=!num!

               set num=%%h
               set chr=%%i
               if "!chr:~0,6!"=="write(" set writes=!num!
               if "!chr:~0,6!"=="fetch(" set fetches=!num!
               if "!chr:~0,5!"=="mark(" set marks=!num!

               set num=%%j
               set chr=%%k
               if "!chr:~0,6!"=="fetch(" set fetches=!num!
               if "!chr:~0,5!"=="mark(" set marks=!num!

               set num=%%l
               set chr=%%m
               if "!chr:~0,5!"=="mark(" set marks=!num!

               echo --   statistics: !txt! >>%trace_sav%

             )
             @rem           echo RESULT: !opname! !success! ms=!elapsed_ms! rd=!reads! wr=!writes! fe=!fetches! mk=!marks!
             (
               echo insert into trace_stat(unit, dts_end, success, elapsed_ms, reads, writes, fetches, marks^)
               echo                 values('!opname!', !dts_end!, !success!, !elapsed_ms!, !reads!, !writes!, !fetches!, !marks!^);
               echo.
             ) >> %trace_sav%
          )

        )
        echo commit;>>%trace_sav%

        call :sho "SID=%sid%. Saving parsed info from trace to database." %sts%

        set run_repo=%fbc%\isql %dbconn% -nod -n -i %trace_sav% %dbauth% 
        cmd /c !run_repo! 1>>%sts% 2>&1

        call :sho "SID=%sid%. Completed." %sts%

        for /d %%x in (%trace_prs%,%trace_sav%,%trace_log%,%trace_cfg%) do (
            del %%x 2>nul
        )

    )
    @rem end of "if .%sid%.==.1. if .%trc_unit_perf%.==.1."


    @rem -------------------------------------------------------------------------
    @rem c h e c k    t h a t   n o    s y n t a x    e r r o r s    o c c u r e d
    @rem -------------------------------------------------------------------------

    @rem --- DO NOT --- 1. 42000 ==> -902 	335544569 	dsql_error 	Dynamic SQL Error
    @rem ~~~~~~~~~~~~~~
    @rem 1. 22003 ==> Numeric value out of range
    @rem 2. 42S22 ==> -206 	335544578 	dsql_field_err 	Column not found
    @rem 3. 42S02 ==> -204  335544580   Table unknown
    @rem 4. 22001 ==> arith overflow / string truncation
    @rem 5. 39000 ==> function unknown: absent UDF or POSIX only: when forget to add backslash before rdb$get/rdb$set_context
    @rem 6. 28000 ==> no permission for ... access to ... // 17.05.2020: OLTP_USER_nnnn via role WORKER instead of SYSDBA

    @rem -- do NOT -- set syntax_msg1="SQLSTATE = 42000" -- this can be when FB crashes and client did EXECUTE STATEMENT at this time!
    set syntax_msg1="SQLSTATE = 22003"
    set syntax_msg2="SQLSTATE = 42S22"
    set syntax_msg3="SQLSTATE = 42S02"
    set syntax_msg4="SQLSTATE = 22001"
    set syntax_msg5="SQLSTATE = 39000"
    set syntax_msg6="SQLSTATE = 28000"

    findstr /i /m /c:!syntax_msg1! /c:!syntax_msg2! /c:!syntax_msg3! /c:!syntax_msg4! /c:!syntax_msg5! /c:!syntax_msg6! %err% >%tmp%
    if NOT errorlevel 1 (
        (
            echo At least one compile / runtime error found during SQL script execution.
            echo #######################################################################
            for /f "delims=" %%x in ( 'findstr /n /i /c:!syntax_msg1! /c:!syntax_msg2! /c:!syntax_msg3! /c:!syntax_msg4! /c:!syntax_msg5! /c:!syntax_msg6! %err% ^| find /i /c "SQLSTATE"') do (
                echo Total number of errors: %%x
            )
            echo.
            echo Errors to be checked: !syntax_msg1!, !syntax_msg2!, !syntax_msg3!, !syntax_msg4!, !syntax_msg5!, !syntax_msg6!
            echo Details see in file: %err%. Job terminated.
            
            @rem prevent from removing logs if some syntax error occured:
            @rem ########################################################
            set remove_isql_logs=never

            echo.
        ) >%tmp%
        type %tmp%
        type %tmp%>>%sts%

        goto end

    )


    @rem -------------------------------------------------------------
    @rem c h e c k    i f    s e r v e r   i s   u n a v a i l a b l e
    @rem -------------------------------------------------------------

    @rem 26.10.2018: unable to establish connect under extremely heavy workload, ~2000-3000 attachments.

    set GET_FB_REPLY_MAX_TRIES=30
    set fb_unavail=0

    @rem 20.10.2020. Windows FB service can be restarted NOT instantly.
    @rem Check value of 'Restart service after <N> minutes' in this service properties, 'Recovery' tab.
    for /l %%k in (1 1 %GET_FB_REPLY_MAX_TRIES%) do (

        call :sho "SID=%sid%, !date! !time!. Check whether Firebird server is still in work. Attempt N %%k of total %GET_FB_REPLY_MAX_TRIES%" %sts%
    	    
        %run_get_fb_ver% 1>%tmp% 2>&1

        findstr /m /i /c:"server version" %tmp% >nul

        if not errorlevel 1 (
            call :sho "SID=%sid%, !date! !time!. OK, Firebird is active" %sts%
            type %tmp%>>%sts%
            del %tmp% 2>nul

            goto :continue_job

        ) else (

            call :sho "SID=%sid%, !date! !time!. Firebird is UNAVAILABLE." %sts%
            type %tmp%>>%sts%
            del %tmp% 2>nul
            if %%k EQU %GET_FB_REPLY_MAX_TRIES% (
                (
                    echo Last attempt to establish connect to Firebird has done. Server still unavaliable.
                    echo Check value of 'Restart service after [N] minutes' in this service properties, 'Recovery' tab.
                    echo Batch will be terminated now.
                ) >> %sts%

                goto :fb_unavail

            ) else (
                call :sho "FAILED establish connect to Firebird. Take small delay before next iteration..." %sts%
                ping -n 6 127.0.0.1>nul
            )
        )
    )

:continue_job

    @rem ------------------------------------------------
    @rem c h e c k    n u m b e r    o f    c r a s h e s
    @rem ------------------------------------------------


    @rem 27.05.2016 Check whether server crashed during this round:
    @rem count number of lines 'error reading / writing from/to connection'
    @rem in the %err% file. If this number exceeds config parameter then
    @rem we TERMINATE further execution of test.

    set crash_msg1="SQLSTATE = 08006"
    set crash_msg2="SQLSTATE = 08003"

    @rem this variable will be changed in routine get_diff_fblog() if phrase about crash ("terminated abnormally")
    @rem will be detected in the difference file for $fblog_beg and $fblog_end.
    set crash_during_run=0

    findstr /i /c:!crash_msg1! /c:!crash_msg2! %err% | find /i /c "SQLSTATE" >%tmp%

    for /f "delims=" %%x in (%tmp%) do (
        set /a crashes_cnt=%%x
    )

    if !crashes_cnt! gtr 5 (
        (
            echo SID=%sid%. Connection problem detected at least !crashes_cnt! times, patterns: !crash_msg1!, !crash_msg2!.
            echo Number of this messages exceeds configurable limit. Details see in file: %err%
            if not .%sid%.==.1. (
                echo SID=%sid%: session is to be finished.
            )
        ) >%tmp%
        type %tmp%>>%log%
        type %tmp%>>%sts%

        set crash_during_run=1

    ) else (

        if !crashes_cnt! equ 0 (
            set msg=SID=%sid%. No connection problems detected during last run. Test will be continued.
        ) else (
            set msg=SID=%sid%. Found !crashes_cnt! phrases about connection problems. Perform additional check by parsing diff between old and current firebird.log
        )
        echo !msg!>>%log%
        call :sho "!msg!" %sts%

        if !crashes_cnt! GTR 0 (
            call :sho "SID=%sid%. Gathering current content of firebird.log" %sts%

            set fblog_current=!tmpdir!\fblog_current.%sid%.log
            %run_get_fb_log% 1>!fblog_current! 2>%err%

            (
                echo %time%. Got:
                for /f "delims=" %%a in ('find /v /c "" !fblog_current!') do (
                    echo STDOUT: %%a (number of rows in extracted log^)
                )
                for /f "delims=" %%a in ('type %err%') do (
                    echo STDERR: %%a
                )
            ) 1>>%sts% 2>&1

            @rem Get DIFF between initial and current content of firebird.log, count number of crashes in it:

            fc.exe /w /n %fblog_start% !fblog_current! 1>!tmp! 2>&1
            
            findstr /m /i /c:"access violation" /c:"error reading data" /c:"error writing data" /c:"terminate abnormal" !tmp! >nul
            if NOT errorlevel 1 (
                set crash_during_run=1
            )

            del !fblog_current!

        )
    )


    if .!crash_during_run!.==.1. (
        (
            @echo !date! !time!
            @echo ##############################################################################
            @echo ###  C R A S H    D E T E C T E D,      S T O P    F U R T H E R    J O B  ###
            @echo ##############################################################################
        ) > %tmp%
        type %tmp%
        type %tmp% >>%sts%

        goto :test_canc

    )


    @rem --------------------------------------------------------
    @rem c h e c k    i f    d a t a b a s e     s h u t d o w n:
    @rem --------------------------------------------------------
    (
        echo !date! !time! Check whether database state is shutdown.
        echo Command: %run_get_db_hdr%
    )>>%sts%

    %run_get_db_hdr% | findstr /i /r /c:"attributes.*shutdown" 1>>%sts% 2>&1
    if NOT errorlevel 1 (
        @rem Output msg about shutdown state and script termination.
        goto db_offline
    )

    @rem ------------------------------------------------------------------
    @rem c h e c k    i f    t e s t   h a s   b e e n    C A N C E L L E D:
    @rem ------------------------------------------------------------------
    call :sho "SID=%sid%. Database ONLINE. Check whether test has been cancelled." %sts%

    @rem 30.05.2016, suggestion by Alexey Kovyazin: let's check first of all STDOUT log
    @rem for the signal about test cancellation. This allow to skip raising EXCEPTION inside
    @rem %tmpdir%\sql\tmp_random_run.sql script, see generation of EB code with raising
    @rem exception ex_test_cancellation.

    findstr /m /i "TEST_WAS_CANCELLED" %log% >nul
    if not errorlevel 1 (
        call :sho "SID=%sid%. Found sign of TEST CANCELLATION in STDOUT log, file %log%" %sts%

        goto test_canc

    )

    @rem Old way: check only ERROR log for message about test cancellation:
    findstr /m /i "EX_TEST_CANCEL" %err% >nul
    if not errorlevel 1  (
        call :sho "SID=%sid%. Found sign of TEST CANCELLATION in STDERR log, file %log%" %sts%

        goto test_canc
    )

    call :sho "SID=%sid%. Test can continue. Make loop to run ISQL with next packet" %sts%

    @rem ############################################
    @REM ########                            ########
    @rem ########   G O T O     S T A R T    ########
    @REM ########                            ########
    @rem ############################################
    goto start

:fb_unavail
    call :sho "Firebird Server is unavailable now. Test has been cancelled." %sts%

    goto end

:fb_lot_of_crashes
    call :sho "Too many messages about connection problem during this test. Test has been cancelled." %sts%

    goto end

:db_offline
    call :sho "DATABASE SHUTDOWN DETECTED, test has been cancelled" %sts%

    goto end

:test_canc

    @rem ::: ACHTUNG ::: 10.05.2019
    @rem NO actions with final report files (.txt and .html) should be done here by any SIDs.
    @rem Only SID=1 is allowed to write into final report but this can be started only after 
    @rem all other attachments will gone.

    set msg=SID=%sid%. Return to %~f0. Test has been CANCELLED
    call :sho "!msg!" %sts%
    echo !msg! >>!log!


    @rem Remove temporary SID-unique .vbs file in %tmpdir%\sql that was used for delays:
    call :getRandom del_vbs %sid%

    del !sid_starter_sql!
    if not .%sid%.==.1. (

        @rem ---------------------------------------------------------------------------------------------------------------
        @rem E X I T    i f   c u r r e n t    I S Q L    w i n d o w   h a s   n u m b e r   g r e a t e r   t h a n   "1".
        @rem ---------------------------------------------------------------------------------------------------------------
        set msg=SID=%sid%: session is leaving from batch %~f0
        echo !msg! >>%log%
        call :sho "!msg!" %sts%
        set /a k=10000+%sid%
        set k=!k:~1,4!

        goto end

    )

    @rem ###########################################################################
    @rem ### 10.05.2019. Following code is allowed to be executed only for SID=1 ###
    @rem ###########################################################################
    call :sho "SID=%sid%. Test is to be COMPLETED. All attachments will be forcedly detached and final reports will be made." %log4all%
    
    
    @echo ########################################################################################################################
    @echo ###   S I D = 1:    c h a n g e    D B    s t a t e    t o    F U L L   S H U T D O W N  /   R E T.   O N L I N E    ###
    @echo ########################################################################################################################

    set backup_lock=0
    %run_get_db_hdr% | findstr /i /r /c:"attributes" 1>!tmp! 2>&1
    findstr /i /r /c:"attributes.*backup lock" !tmp! 1>nul 2>&1
    if NOT errorlevel 1 (
        call :sho "SID=%sid%. Database is in BACKUP LOCK state. We can change DB state to multi-user maintenance rather than full shutdown." %log4all%
        set run_cmd=%fbsvcrun% action_properties prp_shutdown_mode prp_sm_multi prp_shutdown_db 0 dbname %dbnm%
        set backup_lock=1
        
        @rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        @rem Value of 'run_db_statistics' is changed here to -1 in order to skip
        @rem gathering DB statistics when DB is in 'backup lock' state.
        @rem When DB is backup-lock then statistics will include only data from 'main' DB file
        @rem and data from .delta will be IGNORED. See CORE-6399
        @rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
        set run_db_statistics=-1

    ) else (
        call :sho "SID=%sid%. Forcedly drop all other attachments: change DB state to full shutdown." %log4all%
        set run_cmd=%fbsvcrun% action_properties prp_shutdown_mode prp_sm_full prp_shutdown_db 0 dbname %dbnm%
    )
    call :sho "SID=%sid%. Command: !run_cmd!" %log4all%

    @rem ---------------------------------------------------
    @rem t e m p - l y    s h u t d o w n    d a t a b a s e
    @rem ---------------------------------------------------

    cmd /c !run_cmd! 1>!tmp! 2>&1
    type !tmp! >>%log4all%

    @rem 06.10.2020: FB can crash when try to change DB state to shutdown!
    @rem We have to check !err! for presence of text like: "Error reading/writing data from/to the connection"
    @rem If such text presents then we have to try to write info about ABNORMAL finish into database!
    set crash_on_db_shut=0

    findstr /i /r /c:"error reading data" /c:"error writing data" !tmp! 1>nul 2>&1
    if NOT errorlevel 1 (
        set crash_on_db_shut=1
    )


    @rem NOTE: if DB was in 'backup lock' state then new attributes will not be seen in its header until nbackup -N.
    @rem This means that following command will show the same as previous. See CORE-6399

    call :sho "SID=1. Done. Check that DB is really in shutdown mode:" %log4all%
    @rem ### NOTE ###
    @rem OLD list of attributes will be shown if DB was initially in backup-lock state. See CORE-6399.
    @rem This means that we will NOT see 'shutdown' in this case, only query to mon#database can issue this.
    %run_get_db_hdr% | findstr /i /r /c:"attributes" 1>!tmp! 2>&1
    type !tmp!
    type !tmp! >>%log4all%
    
    @rem -----------------------------------
    @rem r e t u r n     D B     o n l i n e
    @rem -----------------------------------

    set run_cmd=%fbsvcrun% action_properties prp_db_online dbname %dbnm%
    call :sho "SID=%sid%. Return DB to online state." %log4all%
    call :sho "SID=%sid%. Command: !run_cmd!" %log4all%
    cmd /c !run_cmd! 1>!tmp! 2>&1
    type !tmp!
    type !tmp!>>%log4all%

    call :sho "SID=%sid%. Done. Check that DB is online:" %log4all%
    %run_get_db_hdr% | findstr /i /r /c:"attributes" 1>!tmp! 2>&1
    type !tmp!
    type !tmp! >>%log4all%

    (
		
		echo "set bail on;"
		echo "set term #;"
		echo "execute block as"
		echo "    declare c int;"
		echo "begin"
		echo "    -- Count records in order to remove all garbage in this table:"
		echo "    select count(*) from semaphores into c;"
		echo "end"
		echo "#"
		echo "set term #;"
		echo "commit;"
		echo "set heading off;"
		echo "select 'Attachments that still alive:' as " " from rdb$database;"
		echo "set heading on;"
		echo "set list on;"
		echo "set blob all;"
		echo "set count on;"
		echo "set echo on;"
        echo "select"
        echo "    a.mon$attachment_id as attachment_id"
        echo "    ,a.mon$server_pid as server_pid"
        echo "    ,a.mon$state as attachment_state"
        echo "    ,a.mon$remote_protocol as remote_protocol"
        echo "    ,a.mon$remote_address as remote_address"
        echo "    ,a.mon$remote_pid as remote_pid"
        echo "    ,a.mon$timestamp as attachment_timestamp"
        echo "    ,s.mon$state as statement_state"
        echo "    ,s.mon$timestamp as statement_timestamp"
        echo "    ,s.mon$sql_text as statement_sql"
        echo "from mon$attachments a"
        echo "left join mon$statements s on a.mon$attachment_id = s.mon$attachment_id"
        echo "where "
        echo "    a.mon$attachment_id is distinct from current_connection"
        echo "    and a.mon$remote_address is not null"
        
        @rem ############################# [[[ NOTE ]]] #####################################
        @rem ###  FOUR PERCENT SIGNS MUST BE SPECIFIED FOR EACH SINGLE '%' TO BE PRODUCED ###
        @rem ################################################################################
        echo "    and upper(s.mon$sql_text) not similar to upper('%%%%execute[[:WHITESPACE:]]+block%%%%')"
		@rem                                                      ^^^^                             ^^^^

        echo ";"
		echo "set echo off;"
		echo "set count off;"
		echo "set list off;"
    ) > %rpt%


    if !crash_on_db_shut! EQU 1 (
	    @rem 06.10.2020: update record in perf_log about test finish outcome:
	    @rem write info about FB crash when changed DB state to shutdown.
  		echo "set heading off;"
  		echo "select 'Update test finish record: add info about crash when DB state was changed to shutdown.' as " " from rdb$database;"
  		echo "set heading on;"
		echo "set list on;"
	    echo "set echo on;"
		echo "update perf_log set"
		echo "         stack = 'script: %~f0, crash_on_db_shut=1'"
		echo "        ,exc_unit = '9' -- special for crashes, see sp SRV_GET_REPORT_NAME"
		echo "        ,exc_info = 'CRASH DURING DB SHUTDOWN' || iif(exc_info is not null, '; ', '') || "
		echo "                    trim(coalesce( iif( upper(exc_info) similar to"

        @rem ############################# [[[ NOTE ]]] #####################################
        @rem ###  FOUR PERCENT SIGNS MUST BE SPECIFIED FOR EACH SINGLE '%' TO BE PRODUCED ###
        @rem ################################################################################
		echo "                                        upper('normal:%%%%expired%%%%')"
		@rem                                                        ^^^^       ^^^^

		echo "                                       ,replace(exc_info,'NORMAL:', '')"
		echo "                                       ,exc_info"
		echo "                                      )"
		echo "                                  ,''"
		echo "                                )"
		echo "                       )"
		echo "where unit = 'sp_halt_on_error'"
		echo "order by dts_beg desc"
		echo "rows 1"
		echo "returning exc_info;"
	    echo "set echo off;"
		echo "commit;"
		echo "set list off;"

    ) >>%rpt%

	if !crash_during_run! EQU 1 (
		@rem Record in perf_log with unit = 'sp_halt_on_error' mostly NOT YET exist at this point
		@rem because SP sp_halt_on_error was not called for test self-stop.
		@rem We have to *add* new record into perf_log in order to show it in the final report:
  		echo "set heading off;"
  		echo "select 'Insert record about crash during test run.' as " " from rdb$database;"
  		echo "set heading on;"
		echo "set list on;"
	    echo "set echo on;"
		echo "insert into perf_log(unit, dts_beg, dts_end, stack, exc_unit, exc_info)"
		echo "values("
		echo "    'sp_halt_on_error'"
		echo "    ,'now'"
		echo "    ,'now'"
		echo "    ,'script: %~f0, crash_during_run=1'"
		echo "    ,'9' -- special for crashes, see sp SRV_GET_REPORT_NAME"
		echo "    ,'CRASH DURING TEST RUN, ' || left(cast(cast('now' as timestamp) as varchar(50)),16)"
		echo ")"
		echo "returning exc_info;"
	    echo "set echo off;"
		echo "commit;"
		echo "set list off;"
	) >>%rpt%


    if !conn_as_locksmith! EQU 0 (
        @rem ######################################################
        @rem # 17.05.2020. Cleanup: remove all non-privileged users with names starting with '$mon_usr_prefix':
        @rem ######################################################
        (
    		echo set heading off;
    		echo select 'Drop all non-prvileged users with names defined by mon_usr_prefix=''%%mon_usr_prefix%%''' as " " from rdb$database;
    		echo set heading on;
            echo commit;
            echo set transaction no wait;
    	    echo set echo on;
            echo execute procedure srv_drop_oltp_worker;
    	    echo set echo off;
            echo commit;
        ) >>%rpt%
    )
    call :remove_enclosing_quotes !rpt!


    call :sho "SID=%sid%. Perform additional checks and cleanup." %log4all%

    set run_repo=%fbc%\isql %dbconn% -nod -n -pag 9999 -i %rpt% %dbauth% 

    cmd /c %run_repo% 1>>%log4all% 2>!err!

    @rem runcmd=!%1!
    @rem err_file=%2
    @rem sql_file=%3
    @rem add_label=%4
    @rem do_abend=%5

    call :catch_err  run_repo  !err!  %rpt%  n/a   0
    @rem -------------------------------------------
    @rem                 1       2      3     4    5

    del %rpt% 2>nul
    del !err! 2>nul
    del !tmpdir!\sql\tmp_longsleep.vbs.tmp 2>nul
    

    @rem Name of final report in HTML format:
    @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    set htm_file=!tmpdir!\oltp%fb%.report.html
    del %htm_file% 2>nul

    set htm_sect=^<h3^>
    set htm_secc=^</h3^>

    set htm_repn=^<h4^>
    set htm_repc=^</h4^>

    set br=^<br^>
    @rem set br=^<br /^>

    set tmp_file=!tmpdir!\oltp%fb%.report.tmp
    set tmpcharts=!tmpdir!\tmp-chart-settings.tmp

    call :sho "SID=1. Starting final performance analysys." %log4all%

    set vbs_oem_converter=%tmpdir%\oemcp_converter.vbs.tmp
    call :create_oemcp_converter %tmpdir% %log4all% %vbs_oem_converter%

    del %rpt% 2>nul
    del %tmpcharts% 2>nul

    @rem QQQQQQQQQQQQQQQQQQQ
    if .%make_html%.==.1. (

        @rem #######################################################################
        @rem #####   S t a r t i n g      w r i t e      i n t o    . h t m l  #####
        @rem #######################################################################
        (
            echo ^<^^!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"^>
            echo ^<html^>

            @rem ----------------------------
            @rem INCLUDE STATIC CONTENT: HEAD
            @rem ----------------------------
            type !THIS_DIR!\oltp_report_html_head.inc

            echo ^<body^>
            echo Generated by %~f0, ISQL session #1 of total launched %winq%. !date! !time!.

            echo ^<table^>
            echo ^<th^>Common^</th^>
            echo ^<th^>Performance^</th^>
            echo ^<th^>Final Results^</th^>
            echo ^<tr^>
            echo ^<td^>
            echo ^<ol^>

            if .%gather_hardware_info%.==.0. (
                echo     ^<li^>Hardware info was not gathered. Change config parameter 'gather_hardware_info' to 1. ^</li^>
            ) else (
                echo     ^<li^>^<a href="#hardwareinfo"^>Hardware and OS info^</a^> ^</li^>
            )

            set get_fbconf_via_sql=0
            if !fb! GTR 40 (
                set get_fbconf_via_sql=1
            ) else if !fb! EQU 40 (
                for /f "delims=. tokens=4" %%b in ("!build!") do (
                    @rem WI-V2.5.9.27150
                    @rem   ^   ^ ^   ^
                    @rem |-1-| 2 3 |-4-|
                    @rem Number of build: 27150 etc
                    set /a fb_build_no=%%b
                )

                @rem commit was 12.11.2020 23:34
                @rem next day build number was 2260
                @rem https://github.com/FirebirdSQL/firebird/commit/7e61b9f6985934cd84108549be6e2746475bb8ca
                @rem Reworked Config: correct work with 64-bit integer in 32-bit code, refactor config values checks and defaults,
                @rem remove some type casts.
                @rem Introduce new virtual table RDB$CONFIG.
                @rem Implement CORE-6332 : Get rid of FileSystemCacheThreshold parameter
                @rem new boolean setting UseFileSystemCache overrides legacy FileSystemCacheThreshold,
                @rem FileSystemCacheThreshold will be removed in the next major Firebird release.

                @rem Minimal build of FB 4.x that allows to query for actual config parameters via SQL:
                if !fb_build_no! GEQ 2260 (
                    set get_fbconf_via_sql=1
                )
            )
            if .!get_fbconf_via_sql!.==.1. (
                echo     ^<li^>^<a href="#fbconf"^>Firebird configuration^</a^> ^</li^>
            )

            echo     ^<li^>^<a href="#testsettings"^>Test configuration^</a^> ^</li^>
            echo     ^<li^>^<a href="#testfinishinfo"^>Test Finish details^</a^> ^</li^>
            echo     ^<li^>^<a href="#testworkload"^>Test workload details^</a^> ^</li^>
            echo     ^<li^>^<a href="#qdindexesddl"^>Indices DDL for heavy-loaded tables^</a^> ^</li^>
            echo ^</ol^>
            echo ^</td^>
            echo ^<td^>
            echo ^<ol^>
            
            
	        echo    ^<li^>Performance, TOTAL score:
	        echo        ^&nbsp;^&nbsp;^&nbsp;^<span^>^<a href="#perftotal"^>as table^</a^>^<span^> ^&nbsp;^&nbsp;^&nbsp; ^<span^>^<a href="#perf_total_chart"^>as chart^</a^>^<span^>
	        echo    ^</li^>

	        echo    ^<li^>Performance per MINUTE, during test_time phase:
	        echo        ^&nbsp;^&nbsp;^&nbsp;^<span^>^<a href="#perfminute"^>as table^</a^>^<span^> ^&nbsp;^&nbsp;^&nbsp; ^<span^>^<a href="#perf_m1_chart"^>as chart^</a^>^<span^>
	        echo    ^</li^>


            if .!trc_unit_perf!.==.0. (
                echo     ^<li^>TRACE was not launched by ISQL #1. Change config parameter 'trc_unit_perf' to 1. ^</li^>
            ) else (
                echo     ^<li^>^<a href="#perftrace"^>Performance, TRACE data for ISQL #1^</a^> ^</li^>
            )

            echo     ^<li^>^<a href="#perfdetail"^>Performance, DETAILS per units^</a^> ^</li^>

            if .!mon_unit_perf!.==.0. (
                echo ^<li^>Monitoring statistics was not gathered. Change config parameter 'mon_unit_perf' to 1 or 2^</li^>
            ) else if .!mon_unit_perf!.==.1. (
                @rem query to: SP report_stat_per_units / table mon_log, group by unit.
                @rem table mon_log is fulfilled by SP srv_fill_mon
                echo ^<li^>Monitoring performance: per UNITS
                echo     ^&nbsp;^&nbsp;^&nbsp;^<span^>^<a href="#perfmon4unit_table"^>as table^</a^>^<span^> ^&nbsp;^&nbsp; ^<span^>^<a href="#perfmon4unit_chart"^>as chart^</a^>^<span^>
                echo ^</li^>
                if not .!fb!.==.25. (
                    echo ^<li^>^<a href="#perfmon4tabs"^>Monitoring performance: per UNITS and TABLES^</a^>^</li^>
                )
            ) else if .!mon_unit_perf!.==.2. (
                echo ^<li^>Memory consumption, metadata cache, attachments activity
                echo     ^&nbsp;^&nbsp;^&nbsp;^<span^>^<a href="#perfmon4meta"^>as table^</a^>^<span^> ^&nbsp;^&nbsp; ^<span^>^<a href="#perf_memo_consumption_chart"^>as chart^</a^>^<span^>
                echo ^</li^>
                echo ^<li^>Monitoring data: STATEMENTS activity, ^<span^>^<a href="#perf_attachments_activity_chart"^>as chart^</a^>^<span^>
                echo ^</li^>
            )


            echo     ^<li^>^<a href="#exceptions"^>Exceptions during test run^</a^> ^</li^>
            echo ^</ol^>
            echo ^</td^>
            echo ^<td^>
            echo ^<ol^>
            echo     ^<li^>^<a href="#fbdbinfo"^>Database and server info^</a^> ^</li^>
            if .!run_db_statistics!.==.0. (
                echo     ^<li^>Database statistics was not gathered. Change config parameter 'run_db_statistics' to 1. ^</li^>
            ) else (
                if .!run_db_statistics!.==.-1. (
                    echo ^<li^>^<a href="#dbstatistics"^>Database statistics was not gathered: DB is in 'backup lock' state.^</a^> ^</li^>
                ) else (
                    echo ^<li^>^<a href="#dbstatistics"^>Database statistics, full^</a^> ^</li^>
                    echo ^<li^>Record versions statistics
                    echo     ^&nbsp;^&nbsp;^&nbsp;^<span^>^<a href="#dbvers_table"^>as table^</a^>^<span^> ^&nbsp;^&nbsp; ^<span^>^<a href="#dbvers_chart"^>as chart^</a^>^<span^>
                    echo ^</li^>
                )
            )
            if .!run_db_validation!.==.0. (
                echo     ^<li^>Database validation was not performed. Change config parameter 'run_db_validation' to 1. ^</li^>
            ) else (
                echo     ^<li^>^<a href="#dbvalidation"^>Database Validation Results^</a^> ^</li^>
            )
            echo     ^<li^>^<a href="#fblogcompare"^>New in firebird.log while test was run^</a^> ^</li^>
            echo     ^<li^>^<a href="#finalpart"^>Final processing of ISQL logs^</a^> ^</li^>
            echo ^</ol^>
            echo ^</td^>
            echo ^</tr^>
            echo ^</table^>

        ) > %htm_file%

    )
    @rem QQQQQQQQQQQQQQQQQQQ
    @rem .%make_html%.==.1.

@rem echo REMOVE LATER :DEBUG_P1
@rem pause
@rem goto :DEBUG_P1

    if .%gather_hardware_info%.==.1. (
        call :sho "SID=%sid%. Gathering hardware and OS info" %log4all%
        (
            echo.
            echo #########################################################
            echo ###   H a r d w a r e     a n d     O S     i n f o   ###
            echo #########################################################
        ) >> %log4all%

        if .%make_html%.==.1. (
            echo !htm_sect! ^<a name="hardwareinfo"^> Hardware and OS info ^</a^> !htm_secc! >> %htm_file%
        )
        call :gather_hwinfo %tmpdir% %log4all% %vbs_oem_converter% %make_html% %htm_file%
        @rem                   1         2              3               4          5

    )

    @rem RRRRRRRRRRRRRRRRRRR

    if .%make_html%.==.1. if .!get_fbconf_via_sql!.==.1. (
        @rem 17.11.2020: obtain actual config parameters from RDB$CONFIG table.
        @rem Avaliable only in FB 4.0 since build 2260:

        set msg=Firebird configuration
        call :sho "SID=%sid%. !msg!" %log4all%
        echo !htm_sect! ^<a name="fbconf"^> !msg! ^</a^> !htm_secc! >> %htm_file%

        (
            echo "set width param_name 35;"
            echo "set width param_value 40;"
            echo "set width param_default 40;"
            echo "set width param_source 20; -- 'firebird.conf' or 'databases.conf'"
            echo "select"
            echo "     rdb$config_name param_name"
            echo "    ,iif(trim(rdb$config_value)='', '[empty]',rdb$config_value) param_value"
            echo "    ,iif(trim(rdb$config_default)='', '[empty]', rdb$config_default) param_default"
            echo "    ,cast(iif(rdb$config_is_set, '[ X ]', '     ') as varchar(5)) as "is set ?""
            echo "    ,rdb$config_source param_source"
            echo "from rdb$config"
            echo "order by param_name"
            echo ";"
        ) > %rpt% 
        call :remove_enclosing_quotes !rpt!

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

        @rem -- not needed for text file -- %run_repo% 1>>%log4all% 2>&1
        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

        @rem del %rpt% 2>nul

    )

    set msg=Output test configuration
    call :sho "SID=%sid%. !msg!" %log4all%
    echo.>>%log4all%


    if .%make_html%.==.1. (
        @rem echo !htm_sect! !msg! !htm_secc! >> %htm_file%
        echo !htm_sect! ^<a name="testsettings"^> !msg! ^</a^> !htm_secc! >> %htm_file%
    )

    (
        for /F "tokens=*" %%a in ('findstr /i /r /c:"^[ 	]*[a-z,0-9]" %cfg% ^| sort') do (
            if "%%a" neq "" (
                for /F "tokens=1-2 delims==" %%i in ("%%a") do (
                  set par=%%i
                  call :trim par !par!
      
                  if "%%j"=="" (
                      set val=### NO VALUE defined ###
                  ) else (
                      for /F "tokens=1" %%p in ("!par!") do (
                          set val=%%j
                          call :trim val !val!
                          set val=!val:'=''!
                      )
                  )
                  echo param=!par!, val=!val!
                )
            )
        )
    ) >>%tmp_file%

    type !tmp_file! >> !log4all!
    if .%make_html%.==.1. (
        call :add_html_text tmp_file htm_file 0 null pre
    )
    del !tmp_file! 2>nul

    @rem RRRRRRRRRRRRRRRRRRR


    @rem -----------------------------------------------------------------------

    call :sho "SID=%sid%. Obtain test finish state" %log4all%
    (
        echo.
        echo ##########################################
        echo ###  t e s t    f i n i s h   i n f o  ###
        echo ##########################################
    ) >> %log4all%

    (
        echo set list on;
        echo set echo on;
        echo select
        echo     x.finish_state
        echo    ,x.dts_end
        echo    ,x.fb_gdscode
        echo    ,x.fb_mnemona
        echo    ,x.stack
        echo    ,x.ip 
        echo    ,x.trn_id 
        echo    ,x.att_id 
        echo    ,x.exc_unit
        echo from z_finish_state x
        echo ;
    ) > %rpt%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    if .%make_html%.==.1. echo !htm_sect! ^<a name="testfinishinfo"^> Test finish info ^</a^> !htm_secc! >>%htm_file%

    %run_repo% 1>>%log4all% 2>&1
   
    if .%make_html%.==.1. (
        (
          @rem Here we split patterns '$css$xxxxxxx' in order to prevent from undesirable indent for 2 characters when display result.
          echo "set list on;"
          echo "select"
          echo "    iif( x.finish_state containing 'abnormal' or x.finish_state containing 'crash'"
          echo "         ,'$css$' || 'error$'"
          echo "         ,iif( x.finish_state containing 'premature'"
          echo "               ,'$css$' || 'warning$'"
          echo "               ,'$css$' || 'success$'"
          echo "             )"
          echo "       ) || x.finish_state as finish_state"
          echo "   ,x.dts_end"
          echo "   ,x.fb_gdscode"
          echo "   ,x.fb_mnemona"
          echo "   ,x.stack"
          echo "   ,x.ip"
          echo "   ,x.trn_id"
          echo "   ,x.att_id"
          echo "   ,x.exc_unit"
          echo "from z_finish_state x"
          echo ";"
          echo "commit;"
        ) > !rpt!

        call :remove_enclosing_quotes !rpt!

        %run_repo% 1>%tmp_file% 2>&1
        @rem .sh: add_html_text $tmpauxlog $phtm 0 "null" "pre"

        @rem tmp_file=!%1!
        @rem htm_file=!%2!
        @rem add_br=%3
        @rem line_prefix=%4
        @rem use_style=%5
        call :add_html_text tmp_file htm_file 0 null pre

        del %tmp_file% 2>nul


    )
    del %rpt% 2>nul

    @rem ###################################

    set msg=Output workload related settings
    echo.>>%log4all%
    call :sho "SID=%sid%. !msg!" %log4all%
    echo.>>%log4all%

    if .%make_html%.==.1. echo !htm_sect! ^<a name="testworkload"^> !msg! ^</a^> !htm_secc! >> %htm_file%

    (

      echo set width working_mode 12;
      echo set width setting 32;
      echo set width val 30;
      echo select 'WORKING_MODE' as setting_name, s.svalue as setting_value
      echo from settings s
      echo where s.working_mode = 'INIT' and s.mcode='WORKING_MODE'
      echo UNION ALL
      echo select s.mcode as setting, s.svalue as val
      echo from settings s
      echo join (
      echo     select s.svalue as working_mode
      echo     from settings s
      echo     where s.working_mode = 'INIT' and s.mcode='WORKING_MODE'
      echo      ^) w on s.working_mode = w.working_mode;
    ) > %rpt%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    type %rpt% >> %log4all%
    %run_repo% 1>>%log4all% 2>&1

    if .%make_html%.==.1. call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

    del %rpt% 2>nul

    (
        echo set width tab_name 13;
        echo set width idx_name 31;
        echo set width idx_key 45;
        echo select * from z_qd_indices_ddl;
    ) > %rpt% 

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    set msg=Indexes for heavy-loaded tables

    echo !msg!: >>%log4all%
    if .%make_html%.==.1. echo !htm_sect! ^<a name="qdindexesddl"^> !msg! ^</a^> !htm_secc! >> %htm_file%

    %run_repo% 1>>%log4all% 2>&1
    if .%make_html%.==.1. call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

    del %rpt% 2>nul

    @rem ###########################


    @rem ------------------------------------------------------------------------------


    set msg=Final aggregation of data from PERF_SPLIT_nn tables to perf_agg
    call :sho "SID=%sid%. !msg!" %log4all%

    @rem 18.03.2019
    (
        echo set list on;
        echo set echo on;
        echo -- Final aggregation of data from PERF_SPLIT_nn tables to perf_agg:
        echo commit;
        echo set transaction no wait;
        echo select * from srv_aggregate_perf_data( 1 ^); -- 1 = ignore stop-flag, do aggregation anyway.
        echo commit;
    ) > %rpt% 

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    set t1=!time!

    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%

    set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
    
    call :sho "SID=%sid%. !tdmsg!" %log4all%

    @rem --------------------------------------------------------------------------

    (
      echo.
      echo ###############################################
      echo ###  p e r f o r m a n c e    r e p o r t s ###
      echo ###############################################
    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_sect! Performance reports !htm_secc! >>%htm_file%
   
    @rem --------------------------------------------------------------------------

    set msg=Performance, TOTAL
    call :sho "SID=%sid%. Generating report '!msg!'" %log4all%
    (
        echo.
        echo %msg%:
        echo.
    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_repn! ^<a name="perftotal"^> %msg%: ^</a^> !htm_repc! >>%htm_file%

    (  
        echo --  Get overall performance report for last 3 hours of activity:
        echo --  Value in column "avg_times_per_minute" in 1st row is overall performance index.
        echo.
        echo set width action 35;
        echo select 
        echo     business_action as action
        echo    ,avg_times_per_minute
        echo    ,avg_elapsed_ms
        echo    ,successful_times_done
        echo from rdb$database
        echo left join report_perf_total on 1=1;
        echo commit;
        @rem -- Result: table 'perf_log' contains overall performance value
        @rem -- which can be found by query:
        @rem -- select p.aux1 from perf_log p where p.unit = 'perf_watch_interval'
        @rem -- order by dts_beg desc rows 1;
    ) > %rpt%

    type %rpt% >>%log4all%
    
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    set t1=!time!

    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
    call :sho "SID=%sid%. !tdmsg!" %log4all%

    if .%make_html%.==.1. (
        call :sho "SID=%sid%. Output to .html file" %log4all%
        (
            echo draw_func_name=perf_total_chart
            echo href_name=perf_total_chart
            echo href_title=Performance in TOTAL, chart
            echo x_axis_field=action
            echo y_fields_list=successful_times_done;
            echo y_format_list=pattern:'0';
            echo x_values_skip_pattern=OVERALL
            echo chart_type=PieChart
            echo chart_div_wid=1100
            echo chart_div_hei=700
		) > !tmpcharts!

        set t1=!time!
        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
        @rem                  1    2      3      4     5     6         7

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
        call :sho "SID=%sid%. !tdmsg!" %log4all%
        echo !br! !tdmsg! >> !htm_file!
    )
    del %rpt% 2>nul

    @rem --------------------------------------------------------------------------

    set msg=Performance for every MINUTE
    call :sho "SID=1. Generating report '!msg!'" %log4all%
    (
      echo.
      echo %msg%:
      echo.
      echo Extract values of ESTIMATED performance that was evaluated after EACH business
      echo operation finished.
      echo These data can help to find proper value of config parameter 'warm_time'.
      echo Current value of config parameter 'warm_time' = %warm_time%.

    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_repn! ^<a name="perfminute"^> %msg%: ^</a^> !htm_repc!>> %htm_file%

    (
        echo set width test_phase 20;
        echo select
        echo     test_phase_name
        echo     ,minutes_passed
        echo     ,perf_score
        echo from report_perf_per_minute
        echo where test_phase_name = 'TEST_TIME' -- remove 'WARM_TIME' phase in order to draw ONE line in chart
        @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
        @rem echo UNION ALL select 'test_time', row_number(^)over(^), cast(10000+rand(^)*500 as int^) from rdb$types rows 20
        @rem echo UNION ALL select 'test_time', 1, cast(10000+rand(^)*500 as int^) from rdb$database
        @rem echo UNION ALL select 'test_time', 2, cast(10000+rand(^)*500 as int^) from rdb$database
        @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
        echo ;
        echo commit;
    ) > %rpt%

    type %rpt% >>%log4all%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    set t1=!time!
    
    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

    if .%make_html%.==.1. (
        call :sho "SID=%sid%. Output to .html file" %log4all%
        (
            echo draw_func_name=perf_m1_chart
            echo href_name=perf_m1_chart
            echo href_title=Performance per minute, chart
            echo axis_color=DarkBlue
            echo x_axis_field=minutes_passed
            echo x_axis_title=minute
            echo y_fields_list=perf_score
            echo y_format_list=pattern:'0'
            echo y_colors_list=Blue
            echo y_legends_list=performance: number of successfully completed business actions per minute.
            echo chart_div_wid=1400
            echo point_size=3
            echo chart_area_options={ left:60, top:25 }
            @rem DO NOT: echo y_scale_type=log
		) > !tmpcharts!

        set t1=!time!

        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
        @rem                  1    2      3      4     5     6         7

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
        call :sho "SID=%sid%. !tdmsg!" %log4all%
        echo !br! !tdmsg! >> !htm_file!
    )

    del %rpt% 2>nul


    @rem --------------------------------------------------------------------------
    if .%trc_unit_perf%.==.1. (
        set msg=Performance from TRACE for ISQL instance #1
        call :sho "SID=1. Generating report '!msg!'" %log4all%

        if .%make_html%.==.1. echo !htm_repn! ^<a name="perftrace"^> !msg!: ^</a^> !htm_repc! >>%htm_file%

        (
          echo --  Get TRACE performance report for ISQL session #1, with splitting data to 10 equal 
          echo -- time intervals, for last 3 hours of activity:
          
          echo set width traced_data 20; 
          echo set width itrv_no  7;
          echo set width itrv_beg 8;         
          echo set width itrv_end 8;         
          echo select
          echo      traced_data -- 22.04.2019 do NOT use alias with spaces for this column, trouble in html will be otherwise!
          echo      ,cast(interval_no as smallint^) as "interval no"
          echo      ,sp_client_order                as "create client order"
          echo      ,sp_cancel_client_order         as "cancel client order"
          echo      ,sp_supplier_order              as "create supplier order"
          echo      ,sp_cancel_supplier_order       as "cancel supplier order"
          echo      ,sp_supplier_invoice            as "create supplier invoice"
          echo      ,sp_cancel_supplier_invoice     as "cancel supplier invoice"
          echo      ,sp_add_invoice_to_stock        as "add invoice to stock"
          echo      ,sp_cancel_adding_invoice       as "cancel added invoice"
          echo      ,sp_customer_reserve            as "create customer reserve"
          echo      ,sp_cancel_customer_reserve     as "cancel customer reserve"
          echo      ,sp_reserve_write_off           as "shipment to customer"
          echo      ,sp_cancel_write_off            as "cancel shipment"
          echo      ,sp_pay_from_customer           as "create payment from customer"
          echo      ,sp_cancel_pay_from_customer    as "cancel customer payment"
          echo      ,sp_pay_to_supplier             as "create payment to supplier"
          echo      ,sp_cancel_pay_to_supplier      as "cancel payment to supplier"
          echo      ,srv_make_invnt_saldo           as "srv total invnt turnovers"
          echo      ,srv_make_money_saldo           as "srv total money turnovers"
          echo      ,srv_recalc_idx_stat            as "srv recalc idx statistics"
          @rem                                          12345678901234567890123456789012
          echo      ,substring(cast(interval_beg    as varchar(24^)^) from 12 for 8^) as "interval start"
          echo      ,substring(cast(interval_end    as varchar(24^)^) from 12 for 8^) as "interval finish"
          echo from rdb$database left join report_perf_trace_pivot on 1=1;
          echo commit;

        ) > %rpt%
        
        type %rpt% >>%log4all%

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
        set t1=!time!

        %run_repo% 1>>%log4all% 2>&1

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
        call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

        if .%make_html%.==.1. (
    
            call :sho "SID=%sid%. Output to .html file" %log4all%

            set t1=!time!
            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

            set t2=!time!
            set tdiff=0
            call :timediff "!t1!" "!t2!" tdiff
            set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
            call :sho "SID=%sid%. !tdmsg!" %log4all%
            echo !br! !tdmsg! >> !htm_file!
        )
        del %rpt% 2>nul

    ) else (

      set msg=Config param. trc_unit_perf=%trc_unit_perf%, trace for ISQL session #1 was not launched.
      (
        echo.
        echo %msg%:
        echo.
      ) >> %log4all%
 
      if .%make_html%.==.1. echo !htm_repn! ^<a name="perftrace"^> !msg! ^</a^> !htm_repc! >>%htm_file%

    )

    @rem --------------------------------------------------------------------------


    set msg=Performance in DETAILS
    call :sho "SID=1. Generating report '!msg!'" %log4all%
    (
      echo.
      echo %msg%:
      echo.
      echo Get performance report with detaliation per units, for last 3 hours of activity.
      echo "CNT_ALL" = total number of records for units start;
      echo "CNT_OK"  = total number of records for successful units finish;
      echo "OK_MIN_MS", "OK_MAX_MS", "OK_AVG_MS" = min, max and average elapsed time of 
      echo successfully finished transactions which involved this unit in work.
    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_repn! ^<a name="perfdetail"^> %msg%: ^</a^> !htm_repc! >>%htm_file%

    (
        echo set width unit 40;
        echo.
        echo select
        echo     unit
        echo     ,cnt_all
        echo     ,cnt_ok
        echo     ,cnt_err
        echo     ,err_prc
        echo     ,ok_min_ms
        echo     ,ok_max_ms
        echo     ,ok_avg_ms
        echo     ,cnt_lk_confl
        echo     ,cnt_user_exc
        if .1.==.0. (
            @rem Do not delete this fields. UNcomment if any troubles will ocur during test:
            echo     ,cnt_chk_viol
            echo     ,cnt_unq_viol
            echo     ,cnt_fk_viol
            echo     ,cnt_stack_trc
            echo     ,cnt_zero_gds
        )
        echo     ,cnt_other_exc
        echo from rdb$database
        echo left join report_perf_detailed on 1=1;
        echo commit;
    ) > %rpt%

    type %rpt% >>%log4all%
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    set t1=!time!
    
    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

    if .%make_html%.==.1. (
        call :sho "SID=%sid%. Output to .html file" %log4all%

        set t1=!time!

        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
        call :sho "SID=%sid%. !tdmsg!" %log4all%
        echo !br! !tdmsg! >> !htm_file!
    )
    del %rpt% 2>nul

    @rem --------------------------------------------------------------------------

    if .%mon_unit_perf%.==.1. (

        set msg=Monitoring data, per application UNITS
        call :sho "SID=1. Generating report '!msg!'" %log4all%
        (
          echo.
          echo #####################################################################
          echo ###    m o n i t o r i n g     d a t a     p e r     u n i t s    ###
          echo #####################################################################
        ) >> %log4all%
        (
          echo.
          echo !msg!:
          echo.
          echo Get report about gathered MONITOR tables data, detalization per UNITS.
          echo NOTE: source view for this report will be created only when config
          echo parameter 'mon_unit_perf' has value 1.
        ) >> %log4all%

        if .%make_html%.==.1. (
            echo !htm_repn! ^<a name="perfmon4unit"^> !msg!: ^</a^> !htm_repc! >>%htm_file%
        )

        (
            echo set width unit 31;
            echo select z.*
            echo from rdb$database
            echo left join report_stat_per_units z on 1=1;
            echo commit;
        ) > %rpt%

        type %rpt% >>%log4all%
        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

        set t1=!time!

        %run_repo% 1>>%log4all% 2>&1

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
        call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

        if .%make_html%.==.1. (

            @rem ::::::::::::::::::::::::::::::: 1a:  reads vs fetches ::::::::::::::::::::::::::::::::

            call :sho "SID=%sid%. Report '!msg!': draw chart for reads and fetches" %log4all%

            (
                echo set width unit 31;
                echo select
			    echo     z.unit
			    echo     ,z.avg_reads
			    echo     ,z.avg_fetches
                echo from rdb$database
                echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast(10000+rand(^)*5000 as int^), cast(1000+rand(^)*3000 as int^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Performance: reads and fetches, average
			    echo chart_inline_block=1
			    echo draw_func_name=mon_reads_fetches_chart
			    echo href_name=mon_reads_fetches_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_reads;      avg_fetches
			    echo y_format_list=pattern:'0.00'; pattern:'0.00'
			    echo y_colors_list=Teal;           DeepSkyBlue
			    echo y_legends_list=Average reads; Average fetches
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
			) > !tmpcharts!
            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7

			@rem ::::::::::::::::::::::::::::: 1b: writes vs marks :::::::::::::::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw chart for writes and marks" %log4all%
            (
                echo set width unit 31;
                echo select
			    echo     z.unit
			    echo     ,z.avg_writes
			    echo     ,z.avg_marks
                echo from rdb$database
                echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast(200+rand(^)*200 as int^), cast(2000+rand(^)*2000 as int^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Performance: writes and marks, average
			    echo chart_inline_block=1
			    echo draw_func_name=mon_writes_marks_chart
			    echo href_name=mon_writes_marks_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_writes;      avg_marks
			    echo y_format_list=pattern:'0.00';  pattern:'0.00'
			    echo y_colors_list=DarkMagenta;     HotPink
			    echo y_legends_list=Average writes; Average marks
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
			) > !tmpcharts!
            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7


            @rem :::::::::::::::::::::::::: 2a: page cache usage  :::::::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw page cache usage" %log4all%
            (
                echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,1.0000*(z.avg_reads / z.avg_fetches^) as "reads / fetches"
			    echo     ,1.0000*(z.avg_writes / z.avg_marks^) as "writes / marks"
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( rand(^) as numeric(10,4^)^), cast( rand(^) as numeric(10,4^)^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
                echo commit;
            ) > %rpt%
    
            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Performance: avg. ratio of page cache misses (0: good, 1: poor^)
			    echo chart_inline_block=1
			    echo draw_func_name=mon_page_cache_usage_chart
			    echo href_name=mon_page_cache_usage_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=reads / fetches;           writes / marks
			    echo y_format_list=pattern:'0.0000';          pattern:'0.0000'
			    echo y_colors_list=DarkCyan;                  DarkOrchid
			    echo y_legends_list=Average reads/fetches;    Average writes/marks
			    @rem DO NOT: y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
            ) > !tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7


            @rem :::::::::::::::::::::::::: 2b: memory usage  :::::::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw memory usage" %log4all%
            (
			    echo -- ATTENTION: counters in the MON$MEMORY_USAGE are *not* cumulative,
			    echo -- their values are like 'snapshots' and represent current memory consumption.
			    echo -- Delta between start and end of some query has no sense, we have to get only
			    echo -- value that was gathered at the FINAL of business action /i.e. after it ended but before commit/.
			    echo -- See SP SRV_FILL_MON: we take in account only values that was at the END of action and ignore
			    echo -- starting values with t.mult=-1: select ... max( nullif(t.mult,-1^) * t.mem_...^) ...
		        echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,z.avg_mem_used
			    echo     ,z.avg_mem_alloc
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( 100000+rand(^)*50000 as int^), cast(200000+rand(^)*50000 as int^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
			    echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=OS memory consumption, average at the end of each business action
			    echo chart_inline_block=1
			    echo draw_func_name=mon_os_memory_usage_chart
			    echo href_name=mon_os_memory_usage_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_mem_used;              avg_mem_alloc
			    echo y_format_list=pattern:'0';               pattern:'0'
			    echo y_colors_list=RosyBrown;                 DarkOrange
			    echo y_legends_list=Avg memory_used;          Avg memory_allocated
			    @rem DO NOT y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:120, right:5, width:"100%" }
			    echo point_size=3
			) > !tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7

            @rem :::::::::::::::::::::::::: 3a: scans, absolute values: sequential and indexed  :::::::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw number of sequential and indexed scans" %log4all%
            (
                echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,z.avg_seq
			    echo     ,z.avg_idx
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( 10000 + 5000*rand(^) as numeric(10,4^)^), cast( 50000 + 25000*rand(^) as numeric(10,4^)^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Performance: sequential and indexed scans, average
			    echo chart_inline_block=1
			    echo draw_func_name=mon_seq_idx_chart
			    echo href_name=mon_seq_idx_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_seq;         avg_idx
			    echo y_format_list=pattern:'0.00';  pattern:'0.00'
			    echo y_colors_list=DarkRed;         DarkCyan
			    echo y_legends_list=Average sequential reads; Average indexed reads
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
			) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7


            @rem :::::::::::::::::::::::::: 3b: scans, absolute values: repeatable, backvers. and fragmented records  :::::::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw number of repeatable, backversion and fragmented records scan" %log4all%
            (
                echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,z.avg_rpt -- monrecord_stats.monrecord_rpt_reads
			    echo     ,z.avg_bkv -- monrecord_stats.monbackversion_reads -- since rev. 60012, 28.08.2014 19:16
			    echo     ,z.avg_frg -- monrecord_stats.monfragment_reads
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( 100000+rand(^)*50000 as int^), cast(200000+rand(^)*100000 as int^), cast(300000+rand(^)*150000 as int^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Avg number of: repeatable, back version and fragmented record scans
			    echo chart_inline_block=1
			    echo draw_func_name=mon_rbf_chart
			    echo href_name=mon_rbf_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_rpt;         avg_bkv;           avg_frg
			    echo y_format_list=pattern:'0.00';  pattern:'0.00';    pattern:'0.00'
			    echo y_colors_list=BlueViolet;      DarkGoldenRod;     Silver
			    echo y_legends_list=Avg. repeatable scans; Avg. back versions scans; Avg. fragmented scans
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
			) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7


            @rem :::::::::::::::::::::::::  4a:  scans, ratios  :::::::::::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw scan ratios" %log4all%
            (
                echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,avg_bkv_per_rec &:: numeric 12,4, see: mon_log.bkv_per_seq_idx_rpt, computed by: bkv_reads / [rec_seq_reads + rec_idx_reads + rec_rpt_reads]
			    echo     ,avg_frg_per_rec &:: numeric 12,4, see: mon_log.frg_per_seq_idx_rpt, computed by: frg_reads / [rec_seq_reads + rec_idx_reads + rec_rpt_reads]
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( rand(^) as numeric(12,4^)^), cast( rand(^) as numeric(12,4^)^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Avg. ratio of: 1. back_vers_scans / total_scans,  2. fragmented_record_scans / total_scans
			    echo chart_inline_block=1
			    echo draw_func_name=mon_bkv_frg_ratio_chart
			    echo href_name=mon_rbf_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_bkv_per_rec;  avg_frg_per_rec
			    echo y_format_list=pattern:'0.0000'; pattern:'0.0000'
			    echo y_colors_list=PaleGoldenRod;    Orchid
			    echo y_legends_list=Avg. back_vers_scans / total_scans; Avg. fragm_rec_scans / total_scans
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
            ) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7


			@rem :::::::::::::::::::::::   4b:  modifications   ::::::::::::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw modifications statistics" %log4all%
            (
                echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,avg_ins
			    echo     ,avg_upd
			    echo     ,avg_del
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( 100000+rand(^)*50000 as int^), cast(200000+rand(^)*100000 as int^), cast(300000+rand(^)*150000 as int^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Avg. number of inserts, updates and deletes
			    echo chart_inline_block=1
			    echo draw_func_name=mon_ins_upd_del_chart
			    echo href_name=mon_iud_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_ins;         avg_upd;         avg_del
			    echo y_format_list=pattern:'0.00';  pattern:'0.00';  pattern: '0.00'
			    @rem echo y_format_list=pattern:'0.00';  pattern:'0.00';  pattern:'0.00'
			    echo y_colors_list=Turquoise;       PeachPuff;       Maroon
			    echo y_legends_list=Avg. inserts; Avg. updates ; Avg. deletes
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
            ) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7

			@rem ....................
			echo ^<br^> >> !htm_file!
			@rem ....................


			@rem ::::::::::::::::::::::::::  5a: garbage-related processing ::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw garbage-related statistics" %log4all%
            (
                echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,avg_bko
			    echo     ,avg_pur
			    echo     ,avg_exp
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( 100000+rand(^)*50000 as int^), cast(200000+rand(^)*100000 as int^), cast(300000+rand(^)*150000 as int^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Avg. number of backouts, purges and expunges
			    echo chart_inline_block=1
			    echo draw_func_name=mon_bko_pur_exp_chart
			    echo href_name=mon_bpx_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_bko;         avg_pur;         avg_exp
			    echo y_format_list=pattern:'0.00';  pattern:'0.00';  pattern:'0.00'
			    echo y_colors_list=Violet;          Coral ;          Gray
			    echo y_legends_list=Avg. backouts;  Avg. purges ; Avg. expunges
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
            ) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7


			@rem ::::::::::::::::::::   5b: record-level lock and conflicts  ::::::::::::::::::
            call :sho "SID=%sid%. Report '!msg!': draw record-level lock and conflicts" %log4all%
            (
                echo set width unit 31;
			    echo select
			    echo     z.unit
			    echo     ,z.avg_locks
			    echo     ,z.avg_confl
			    echo from rdb$database
			    echo left join report_stat_per_units z on 1=1
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                @rem echo UNION ALL select unit, cast( 100000+rand(^)*50000 as int^), cast(200000+rand(^)*100000 as int^) from business_ops
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
			    echo ;
                echo commit;
            ) > %rpt%

            (
			    echo chart_only_show=1
			    echo chart_type=ColumnChart
			    echo chart_title=Performance: record-level locks and conflicts, average
			    echo chart_inline_block=1
			    echo draw_func_name=mon_lock_and_conflict_chart
			    echo href_name=mon_lock_and_conflict_chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=unit
			    echo x_axis_title=action
			    echo y_fields_list=avg_locks;       avg_confl
			    echo y_format_list=pattern:'0.00';  pattern:'0.00'
			    echo y_colors_list=DarkOrange;      Yellow
			    echo y_legends_list=Average record locks; Average lock-conflicts
			    echo y_scale_type=log
			    echo chart_div_wid=550
			    echo chart_area_options={ left:90, right:5, width:"100%" }
			    echo point_size=3
            ) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7

			@rem ....................
			echo ^<br^> >> !htm_file!
			@rem ....................
        
        )
        @rem make_html==1

        del %rpt% 2>nul
    
        if NOT .%fb%.==.25. (
            set msg=Monitoring data, per TABLES and application UNITS
            call :sho "SID=1. Generating report '!msg!'" %log4all%
            (
              echo.
              echo ######################################################################
              echo ###    m o n i t o r i n g     d a t a     p e r     t a b l e s   ###
              echo ######################################################################
            ) >> %log4all%
            (
              echo.
              echo %msg%:
              echo.
              echo Get report about gathered MONITOR tables data, detalization  per __TABLES__ and units.
              echo NOTE: source view for this report will be created only when config
              echo parameter 'mon_unit_perf' has value 1. Avaliable only for FB 3.0.
            ) >> %log4all%
           
            if .%make_html%.==.1. echo !htm_repn! ^<a name="perfmon4tabs"^> !msg!: ^</a^> !htm_repc! >>%htm_file%

            (
              echo set width unit 31;
              echo set width table_name 31;
              echo select z.* 
              echo from rdb$database
              echo left join report_stat_per_tables z on 1=1;
              echo commit;
            ) > %rpt%

            type %rpt% >>%log4all%
            set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
            set t1=!time!

            %run_repo% 1>>%log4all% 2>&1

            set t2=!time!
            set tdiff=0
            call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
            call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

            if .%make_html%.==.1. (
                
                call :sho "SID=%sid%. Output to .html file" %log4all%

                set t1=!time!
                call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

                set t2=!time!
                set tdiff=0
                call :timediff "!t1!" "!t2!" tdiff
                set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
                call :sho "SID=%sid%. !tdmsg!" %log4all%
                echo !br! !tdmsg! >> !htm_file!
            )
            del %rpt% 2>nul

        )
        @rem "if NOT .%fb%.==.25."

    ) else if .%mon_unit_perf%.==.2. (

        set msg=Monitoring metadata cache size
        call :sho "SID=1. Generating report '!msg!'" %log4all%

        if .%make_html%.==.1. (
            echo !htm_sect! ^<a name="perfmon4meta"^> !msg!: ^</a^> !htm_secñ! >>%htm_file%
        )

        (
          echo.
          echo ################################################################################
          echo ###    m o n i t o r i n g:    m e t a d a t a     c a c h e     s i z e     ###
          echo ################################################################################
        ) >> %log4all%

        (
            echo.
            echo set heading off;
            @rem "Page cache type: dedicated, buffers: 256 per each connection, with total size: 20971520"
            echo select p.page_cache_info from srv_get_page_cache_info p;
            echo set heading on;
        ) > %rpt%

        type %rpt% >>%log4all%

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
        %run_repo% 1>%tmp_file% 2>&1

        type %tmp_file% >>%log4all%
       
        if .%make_html%.==.1. (
            echo !htm_repn! >>%htm_file%
            call :add_html_text tmp_file htm_file
            echo !htm_repc! >>%htm_file%
        )

        (
          echo page cache memo used            = page cache total size, bytes:
          echo metadata cache memo used        = metadata cache, bytes;
          echo metadata cache percent of total = ratio between metadata cache and sum of metadata cache and page cache;
          echo total attachments cnt           = total number of attachments, regardless of state;
          echo active attachments cnt          = number of attachments with mon$state = 1;
          echo running statements cnt          = number of statements that are operating with data from page cache, i.e. mon$state = 1;
          echo stalled statements cnt          = number of statements that are waiting for client request for fetching, i.e. mon$state = 2;
          echo memo used by attachments        = total of mon$memory_usage.mon$memory_used for attachment level, i.e. mon$stat_group = 1;
          echo memo used by transactions       = total of mon$memory_usage.mon$memory_used for transaction level, i.e. mon$stat_group = 2;
          echo memo used by statements         = total of mon$memory_usage.mon$memory_used for statement level, i.e. mon$stat_group = 3;
          echo.
        ) > %tmp_file%
        type %tmp_file% >>%log4all%
       
        if .%make_html%.==.1. (
            call :add_html_text tmp_file htm_file
        )
    

        @rem if .%make_html%.==.1. echo !htm_repn! ^<a name="perfmon4meta"^> !msg!: ^</a^> !htm_repc! >>%htm_file%

        (
            echo.

            echo select
            echo     substring(measurement_timestamp from 12 for 8^) as "measure time" -- 21.04.2019 do NOT use alias with SPACES for the 1st field of resultset!
            echo     ,measurement_elapsed_ms as "measurement duration ms"
            echo     ,page_cache_memo_used as "page cache memo used"
            echo     ,memo_used_all as "memo used, total"
            echo     ,memo_allo_all as "memo allocated, total"
            echo     ,metadata_cache_memo_used as "metadata cache"
            echo     ,metadata_cache_percent_of_total as "metadata cache percent of total"
            echo     ,total_attachments_cnt as "total attachments cnt"
            echo     ,active_attachments_cnt as "active attachments cnt"
            echo     ,running_statements_cnt as "running statements cnt"
            echo     ,stalled_statements_cnt as "stalled statements cnt"
            echo     ,memo_used_by_attachments as "memo used by attachments"
            echo     ,memo_used_by_transactions as "memo used by transactions"
            echo     ,memo_used_by_statements as "memo used by statements"
            echo from report_cache_dynamic d
            if .1.==.0. (
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
                echo UNION ALL
                echo select
                echo     substring(dateadd(row_number(^)over(^) minute to cast('19.10.2020 00:00:00' as timestamp^)^) from 12 for 8^)
                echo     ,cast(10000 + rand(^)*2000 as int^)
                echo     ,cast(10000 + rand(^)*20000 as int^)
                echo     ,cast(10000 + rand(^)*20000 as int^)
                echo     ,cast(10000 + rand(^)*2000 as int^)
                echo     ,cast(10000 + rand(^)*20000 as int^)
                echo     ,cast(10000 + rand(^)*200000 as int^)
                echo     ,cast(10000 + rand(^)*2000 as int^)
                echo     ,cast(10000 + rand(^)*20000 as int^)
                echo     ,cast(10000 + rand(^)*200000 as int^)
                echo     ,cast(10000 + rand(^)*2000 as int^)
                echo     ,cast(10000 + rand(^)*20000 as int^)
                echo     ,cast(10000 + rand(^)*200000 as int^)
                echo     ,cast(10000 + rand(^)*2000 as int^)
                echo from rdb$types rows 50
                @rem #DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG#DEBUG
            )
            echo ;
            echo commit;
        ) > %rpt%


        type %rpt% >>%log4all%
        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

        set t1=!time!

        %run_repo% 1>>%log4all% 2>&1

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
        call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

        if .%make_html%.==.1. (
    
            call :sho "SID=%sid%. Output to .html file" %log4all%

            set t1=!time!
            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
            set t2=!time!
            set tdiff=0
            call :timediff "!t1!" "!t2!" tdiff

            set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
            call :sho "SID=%sid%. !tdmsg!" %log4all%
            echo !br! !tdmsg! >> !htm_file!


            @rem :::::::::::::::: mon_unit=2, chart 1: total memory consumption for DB level

            call :sho "SID=%sid%. Report '!msg!': draw total memory consumption for DB level" %log4all%

            (
			    echo draw_func_name=perf_memo_consumption_chart
			    echo chart_only_show=1
			    echo href_name=perf_memo_consumption_chart
			    echo href_title=Memory consumption, total, chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=measure time
			    echo x_axis_title=timestamp
			    echo y_fields_list=memo used, total;          memo allocated, total
			    echo y_colors_list=Aqua;                      Blue
			    echo y_legends_list=memory used for DB level; memo allocated for DB level
			    echo y_format_list=pattern:'0';               pattern:'0'
			    echo y_list_delimiter=;
			    @rem do NOT y_scale_type=log
			    echo chart_div_hei=500
			    echo chart_div_wid=1300
			    echo point_size=3
			    echo x_axis_slanted_labels=true
			    echo chart_area_options={ left:90, top:25 }
			) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7


            @rem :::::::::::::::: mon_unit=2, chart 2: metadata cache size and memory consumed by attachments, transactions and statements
            @rem NB: we use the same SQL here but show other columns than in previous chart.

            call :sho "SID=%sid%. Report '!msg!': draw metadata cache size and memory consumed by attachments, transactions and statements" %log4all%

            (
			    echo draw_func_name=perf_metadata_cache_chart
			    echo chart_only_show=1
			    echo href_name=perf_metadata_cache_chart
			    echo href_title=Metadata cache size, chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=measure time
			    echo x_axis_title=timestamp
			    echo y_fields_list=metadata cache;  memo used by attachments;  memo used by transactions;  memo used by statements
			    echo y_colors_list=DarkCyan;        Red;                       Green;                      BlueViolet
			    echo y_legends_listmetadata cache;  memory for attachments;    memory for transactions;    memory for statements
			    echo y_format_list=pattern:'0';     pattern:'0';               pattern:'0';                pattern:'0'
			    echo y_list_delimiter=;
			    echo y_scale_type=log
			    echo y_leg_maxlines=2
			    echo chart_div_hei=500
			    echo chart_div_wid=1300
			    echo point_size=3
			    echo x_axis_slanted_labels=true
			    echo chart_area_options={ left:90, top:25 }
			) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7



            @rem :::::::::::::::: mon_unit=2, chart 3: number of active attachments, running and stalled statements
            @rem NB: we use the same SQL here but show other columns than in previous chart.

            call :sho "SID=%sid%. Report '!msg!': draw number of active attachments, running and stalled statements" %log4all%
            
            (
			    echo draw_func_name=perf_attachments_activity_chart
			    echo chart_only_show=1
			    echo href_name=perf_attachments_activity_chart
			    echo href_title=Statements activity, chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=measure time
			    echo x_axis_title=timestamp
			    echo y_fields_list=total attachments cnt; running statements cnt; stalled statements cnt
			    echo y_colors_list=Red;                   Green;                  BlueViolet
			    echo y_legends_list=total attachments count;running statements count;stalled statements count
			    echo y_list_delimiter=;
			    echo chart_div_hei=500
			    echo chart_div_wid=1300
			    echo point_size=3
			    echo x_axis_slanted_labels=true
			    echo chart_area_options={ left:60, top:25 }
            ) >!tmpcharts!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
            @rem                  1    2      3      4     5     6         7

        )
        del %rpt% 2>nul
    
    )
    @rem .%mon_unit_perf%.==.1.  or ==.2. or ==.0.

    if .%mon_unit_perf%.==.0. (
        @rem NOP
    ) else (
        set prefix_msg=Monitoring statistics related to
        set suffix_msg=was not gathered, see config parameter 'mon_unit_perf'
        if not .%mon_unit_perf%.==.1. (
            set msg= !prefix_msg! performance for units !suffix_msg!.
            (
              echo.
              echo %msg%:
              echo.
            ) >> %log4all%
            if .%make_html%.==.1. echo !htm_repn! ^<a name="perfmon4unit"^> !msg! ^</a^> !htm_repc! >>%htm_file%
        )
        if not .%mon_unit_perf%.==.2. (
            set msg=!prefix_msg! memory consumption, attachments and statements activity !suffix_msg!.
            (
              echo.
              echo %msg%:
              echo.
            ) >> %log4all%
            if .%make_html%.==.1. echo !htm_repn! ^<a name="perfmon4meta"^> !msg! ^</a^> !htm_repc! >>%htm_file%
        )
    )

    del !tmpcharts! 2>nul

    @rem ------------------------------------------------------------------------------

    set msg=Exceptions occured during test work

    call :sho "SID=1. Generating report '!msg!'" %log4all%
    (
      echo.
      echo #########################################################
      echo ###  e x c e p t i o n s     d u r i n g     t e s t  ###
      echo #########################################################
    ) >> %log4all%

    
    (
      echo.
      echo set width unit 40;
      echo select fb_mnemona, cnt, unit, fb_gdscode                                  
      echo from rdb$database
      echo left join report_exceptions on 1=1;
      echo.
    ) > %rpt%

    type %rpt% >>%log4all%
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    set t1=!time!
    
    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

    if .%make_html%.==.1. (
        call :sho "SID=%sid%. Output to .html file" %log4all%

        echo !htm_repn! ^<a name="exceptions"^> %msg%: ^</a^> !htm_repc! >>%htm_file%
        set t1=!time!

        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff

        set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
        call :sho "SID=%sid%. !tdmsg!" %log4all%
        echo !br! !tdmsg! >> !htm_file!
    )

    del %rpt% 2>nul

    @rem ---------------------------------------------------------------------------

    set msg=MON$DATABASE data and server version
    (
        echo.
        echo %msg%:
        echo.
    ) >> %log4all%
 
    (
      echo set list on; 
      echo select * from mon$database; 
      echo set list off;
    ) > %rpt%

    type %rpt% >>%log4all%
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    %run_repo% 1>%tmp_file% 2>&1
    type %tmp_file% >>%log4all%

    if .%make_html%.==.1. (
        echo !htm_sect! ^<a name="fbdbinfo"^> %msg% !htm_secc! ^</a^> >>%htm_file%

        call :add_html_text tmp_file htm_file 0 null pre
    )

    echo show version; > %rpt%
    type %rpt% >>%log4all%
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    %run_repo% 1>%tmp_file% 2>&1
    type %tmp_file% >>%log4all%
    if .%make_html%.==.1. (
        call :add_html_text tmp_file htm_file 0 null pre
    )

    del %rpt% 2>nul

    echo.>>%log4all%
    echo.>>%log4all%

    @rem ---------------------------------------------------------------------------
    set skip_fbsvc=0
    @rem 09.10.2015: call fbsvcmgr in embedded mode now is possible, CORE-4938 is fixed

    @rem ------------------------------------------------------------------------------

:DEBUG_P1

    if .%run_db_statistics%.==.1. (

        set msg=Database statistics, full
        call :sho "SID=1. !msg!" %log4all%

        (
           echo.
           echo #################################################
           echo ###  d a t a b a s e    s t a t i s t i c s   ###
           echo #################################################
           echo.
           echo ++++++++++++++++++++++++++
           echo Command: %run_get_db_sts%
           echo ++++++++++++++++++++++++++
           echo.
           echo Result:
        ) >> %log4all%

        set t1=!time!

        %run_get_db_sts% 1>%tmp_file% 2>&1

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%tmp_file%
        type %tmp_file% >>%log4all%

        call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

        if .%make_html%.==.1. (
            call :sho "SID=%sid%. Output to .html file" %log4all%
            echo !htm_sect! ^<a name="dbstatistics"^> !msg! ^</a^> !htm_secc!>>%htm_file%
            set t1=!time!
            
            call :add_html_text tmp_file htm_file 1 null monosp

            set t2=!time!
            set tdiff=0
            call :timediff "!t1!" "!t2!" tdiff

            set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
            call :sho "SID=%sid%. !tdmsg!" %log4all%
            echo !br! !tdmsg! >> !htm_file!

        )

        set msg=Record versions statistics
        call :sho "SID=1. !msg!" %log4all%

        copy %tmp_file% %rpt% >nul

        set t1=!time!
        findstr /i /r /c:"[A-Z,0-1,_$]* (" /c:"total records:" /c:"total versions:" %rpt% | findstr /i /v " Index" >%tmp_file%

        del %rpt% 2>nul
        (
            for /f "tokens=*" %%a in (%tmp_file%) do (
                set vprc=0
                set line=%%a
                if not .!line!.==.. (
                
                    echo !line! | findstr /i /r /b /c:"[A-Z_$0-9]* (" >nul
                    if not errorlevel 1 (
                        @rem echo !line!
                        for /f "tokens=1" %%a in ("!line!") do set tabn=%%a
                    ) else (
                
                      echo !line! | findstr /c:"total records:" >nul
                      if not errorlevel 1 (
                        @rem echo !line!
                        @rem Average record length: 33.52, total records: 50
                        for /f "tokens=7" %%a in ("!line!") do (
                          set /a recs=%%a
                        )
                      )
                
                      echo !line! | findstr /c:"total versions:" >nul
                      if not errorlevel 1 (
                        @rem echo !line!

                        @rem 2.5: Average version length:  9.00, total versions:   33, max versions: 18
                        @rem 3.0: Average version length: 17.79, total versions: 9057, max versions: 31
                        @rem      ---------------------------------------------------------------------
                        @rem        1        2      3       4      5       6      7     8      9     10

                        for /f "tokens=7,10 delims=, " %%a in ("!line!") do (
                          set /a vers=%%a
                          set /a maxv=%%b
                        )
   
                        @rem 'rowset' is INDEXED field.
                        echo insert into mon_log_table_stats(id, rowset, table_name, rec_inserts, rec_updates, rec_deletes^) 
                        echo values( -gen_id(g_common,1^), -current_connection, '!tabn!', !recs!, !vers!, !maxv!^);
                      )
                   )
                )
            
            )
            echo set list on;
            echo select -current_connection as rowset from rdb$database; -- this will be saved into script env. variable 'xrowset', see below
            echo commit;
        ) >%rpt%

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
        
        %run_repo% 1>%tmp_file% 2>&1

        for /f "tokens=2" %%x in ('findstr /i /c:"rowset " %tmp_file%') do (
            set xrowset=%%x
        )

        (
            echo "commit;"
            echo "create or alter view tmp$for$report$only as"
            echo "select"
            echo "    t.table_name"
            echo "    ,t.rec_inserts as total_recs"
            echo "    ,t.rec_updates as total_vers"
            echo "    ,t.rec_deletes as max_versions"
            echo "    ,cast( 100.0000 * coalesce( t.rec_updates / nullif(t.rec_inserts,0), 0) as numeric(14,4)) as vers_to_recs_prc"
            echo "    ,cast( 100.0000 * coalesce( t.rec_deletes / nullif(t.rec_updates,0), 0) as numeric(14,4)) as maxv_to_vers_prc"
            echo "from mon_log_table_stats t"
            echo "where "
            echo "   t.rowset=!xrowset!"
            echo "   and (t.rec_inserts > 0 or t.rec_updates > 0)"
            echo "order by t.table_name;"
            echo "commit;"
            echo "set width table_name 31;"
            echo "select * from tmp$for$report$only;"
            echo "commit;"
            @rem echo "show view tmp$for$report$only;"
        ) > !rpt!
        call :remove_enclosing_quotes !rpt!

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

        %run_repo% 1>%tmp_file% 2>&1

        (
          echo.
          echo !msg!
        ) >>%log4all%

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
        call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %log4all%

        type %tmp_file% >>%log4all%

        if .%make_html%.==.1. (
           
           call :sho "SID=%sid%. Output to .html file" %log4all%

           echo !htm_sect! ^<a name="dbvers_table"^> !msg!, table ^</a^> !htm_secc! >>%htm_file%

           (
               @rem NB: Add style prefix only to TEXT column. DO NOT add it to numeric values otherwise right-alignment in table cells will be lost.
               echo "select"
               @rem echo "     iif(x.vers_to_recs_prc > 500, '$css$' || 'error$', iif(x.vers_to_recs_prc > 50, '$css$' || 'warning$', '')) || table_name as table_name"
               echo "     iif(x.vers_to_recs_prc > 500, '$css$error$', iif(x.vers_to_recs_prc > 50, '$css$warning$', '')) || table_name as table_name"
               echo "    ,total_recs"
               echo "    ,total_vers"
               echo "    ,max_versions"
               echo "    ,vers_to_recs_prc"
               echo "    ,maxv_to_vers_prc"
               echo "from tmp$for$report$only x"
               echo ";"
           ) > !rpt!

           call :remove_enclosing_quotes !rpt!

           set t1=!time!

           call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

           set t2=!time!
           set tdiff=0
           call :timediff "!t1!" "!t2!" tdiff

           set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
           call :sho "SID=%sid%. !tdmsg!" %log4all%
           echo !br! !tdmsg! >> !htm_file!

           call :sho "SID=%sid%. Report '!msg!': draw chart for total records and versions" %log4all%

           echo !htm_sect! ^<a name="dbvers_chart"^> !msg!, chart ^</a^> !htm_secc! >>%htm_file%

           (
			    echo draw_func_name=dbstat_recs_and_vers
			    echo chart_only_show=1
			    echo href_name=dbstat_recs_and_vers_chart
			    echo href_title=Total records and versions, chart
			    echo axis_color=DarkBlue
			    echo x_axis_field=table_name
			    echo x_axis_title=table_name
			    echo y_scale_type=log
			    echo y_fields_list=total_recs; total_vers
			    echo y_colors_list=Green;      BlueViolet
			    echo y_legends_list=total records; total versions
			    echo y_list_delimiter=;
			    echo chart_div_hei=500
			    echo chart_div_wid=1300
			    echo point_size=3
			    echo x_axis_slanted_labels=true
			    echo chart_area_options={ left:60, top:25 }
			    echo chart_type=ColumnChart
           ) >!tmpcharts!

           call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
           @rem                  1    2      3      4     5     6         7

           call :sho "SID=%sid%. Report '!msg!': draw chart for ratios between max_versions, total_versions and records" %log4all%
           @rem NB: we use the same SQL here but show other columns than in previous chart.

           (
			    echo draw_func_name=dbstat_maxvers_vs_total_vers
			    echo chart_only_show=1
			    echo href_name=dbstat_maxvers_vs_total_vers
			    echo href_title=Ratios versions / total_records and max_versions / total_versions
			    echo axis_color=DarkBlue
			    echo x_axis_field=table_name
			    echo x_axis_title=table_name
			    echo y_scale_type=log
			    echo y_fields_list=vers_to_recs_prc; maxv_to_vers_prc
			    echo y_colors_list=Blue;             Red
			    echo y_legends_list=Ratio versions / total_records, percent; Ratio max_versions / versions, percent
			    echo y_list_delimiter=;
			    echo chart_div_hei=500
			    echo chart_div_wid=1300
			    echo point_size=3
			    echo x_axis_slanted_labels=true
			    echo chart_area_options={ left:60, top:25 }
			    echo chart_type=ColumnChart
           ) >!tmpcharts!

           call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file tmpcharts
           @rem                  1    2      3      4     5     6         7

           (
               echo delete from mon_log_table_stats t
               echo where t.rowset=!xrowset!
               echo ;
           ) > !rpt!
           set run_repo=%fbc%\isql %dbconn% -nod -i %rpt% %dbauth% 
           cmd /c !run_repo!

        )

        for /d %%x in (%tmp_file%,%rpt%,!tmpcharts!) do (
            del %%x 2>nul
        )

    ) else (

       if .%run_db_statistics%.==.-1. (
           @rem 31.10.2020
           set msg=DB statistics must not be gathered in 'backup lock' state. Merge delta with DB first. See CORE-6399.
       ) else (
           set msg=Database statistics was not gathered, see config parameter 'run_db_statistics'.
       )

       (
           echo.
           echo !msg!
           echo.
       ) >>%log4all%

       if .%make_html%.==.1. (
           echo !htm_sect! ^<a name="dbstatistics"^> !msg! ^</a^> !htm_secc!>>%htm_file%
       )

       if .%run_db_statistics%.==.-1. (
           (
               echo ::: ATTENTION :::
               echo.
               echo When DB is in 'backup lock' state then statistics will contain only data from the 'main' DB file
               echo NO data from .delta wll be included, so gathering of this statistics is USELESS. See CORE-6399.
               echo If this test as launched from oltp-scheduled.bat then check oltp-scheduled_config.win and replace
               echo its parameter 'BACKUP_LOCK' to 0.
               echo.
           ) > %tmp_file%
           type %tmp_file% >> %log4all%
           if .%make_html%.==.1. (
                  call :add_html_text tmp_file htm_file 1 null monosp
           )
           del %tmp_file%
       )
  
    )

    @rem ------------------------------------------------------------------------------

    if .%run_db_validation%.==.1. (

        set msg=Database validation
        call :sho "SID=1. !msg!" %log4all%

        set skip_val_list=(AGENTS^^^|BUSINESS_OPS^^^|DOC_STATES^^^|FB_ERRORS^^^|EXT_STOPTEST^^^|SETTINGS^^^|OPTYPES^^^|RULES_FOR_%%%%^^^|PHRASES^^^|TMP$%%%%^^^|MON%%%%^^^|WARE%%%%^^^|Z_%%%%^)
        (
          echo.
          echo #################################################
          echo ###  d a t a b a s e    v a l i d a t i o n   ###
          echo #################################################
          echo.
        ) >> %log4all%

        (
          echo Command: !run_db_validat!
          echo Pattern for tables which are NOT validated:
          echo !skip_val_list:^^=!
          echo.
          echo Result:
        ) > %tmp_file%

        type %tmp_file% >>%log4all%

        @rem 16:06:17.25 Relation 261 (XQD_1000_3300) : 1 ERRORS found 

        if .%make_html%.==.1. (
            echo !htm_sect! ^<a name="dbvalidation"^> !msg! ^</a^> !htm_secc!>>%htm_file%
            @rem call :add_html_text tmp_file htm_file
        )
        
        echo !run_db_validat! val_tab_excl !skip_val_list! > %tmpdir%\tmp_validation.bat

        set t1=!time!

        call %tmpdir%\tmp_validation.bat | findstr /i /v /c:"process pointer page" 1>%tmp_file% 2>&1

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%tmp_file%
        call :sho "SID=%sid%. Done for !tdiff! ms, from !t1! to !t2!" %tmp_file%

        type %tmp_file% >>%log4all%

        if .%make_html%.==.1. (

            del %rpt% 2>nul
            for /f "tokens=*" %%a in (!tmp_file!) do (
                set line=%%a
                if not .!line!.==.. (
                    set line=!line:ERRORS found=!
                    if not !line!==%%a set line=$css$error$%%a
                    echo !line!>>%rpt%
                ) else (
                    echo.>>%rpt%
                )
            )
            set t1=!time!
            
            call :add_html_text tmp_file htm_file 1 null monosp

            set t2=!time!
            set tdiff=0
            call :timediff "!t1!" "!t2!" tdiff 2>>%tmp_file%
            set tdmsg=Done for !tdiff! ms, from !t1! to !t2!
            call :sho "SID=%sid%. !tdmsg!" %log4all%
            echo !br! !tdmsg! >> !htm_file!

            del %rpt% 2>nul

        )
        echo End of database validation report.>>%log4all%

        del %tmp_file%
        del %tmpdir%\tmp_validation.bat

    ) else (
       set msg=Database validation was not performed, see config parameter 'run_db_validation'.
       (
           echo.
           echo !msg!
           echo.
       ) >>%log4all%
 
       if .%make_html%.==.1. (
           echo !htm_sect! ^<a name="dbvalidation"^> !msg! ^</a^> !htm_secc!>>%htm_file%
       )
    )

    set msg=Differences between old and current firebird.log
    call :sho "SID=1. !msg!" %log4all%

    %run_get_fb_log% 1>%fblog_final% 2>&1


    set msg=Comparison of old and new firebird.log (get messages that appeared during test^):
    set run_cmd=fc.exe /n %fblog_start% %fblog_final%

    (
        echo.
        echo !msg!
        echo.
        echo ++++++++++++++++++++++++++
        echo Command: !run_cmd!
        echo ++++++++++++++++++++++++++
        echo.
    ) >>%log4all%

    del %tmp_file% 2>nul
    echo +++ Start of comparison +++ > %tmp_file%

    %run_fc_compare% 1>>%tmp% 2>&1
    set fc_result=%errorlevel%
    
    del %fblog_start% 
    del %fblog_final%

    if .!fc_result!.==.0. (
        echo result: files match. No new messages appeared in firebird.log during test ran. >>!tmp_file!
    ) else (

        @rem NOTE: output of fc.exe utility is localized, we have to convert it to utf8 if make_html=1
        if NOT exist %vbs_oem_converter% (

            set /a k=1
            for /f "tokens=*" %%a in ('type !tmp!') do (
              @rem First line in output of fc.exe utility is localized, skip it.
              if not .!k!.==.1. echo %%a >> !tmp_file!
              set /a k+=1
            )

        ) else (
            type !tmp! >> !tmp_file!
        )

    )

    del %tmp% 2>nul

    echo +++ End of comparison +++>>%tmp_file%

    type %tmp_file% >>%log4all%

    if .%make_html%.==.1. (
        echo !htm_sect! ^<a name="fblogcompare"^> !msg! ^</a^> !htm_secc!>>%htm_file%

        if exist %vbs_oem_converter% (

            @rem Convert from OEM to UTF-8 in order to add into HTML report
            @rem -------------------------
            set tmputf8=!tmpdir!\tmputf8.tmp
            %systemroot%\system32\cscript.exe //nologo //e:vbscript !vbs_oem_converter! !tmp_file! !tmputf8! UTF-8

            copy !tmputf8! !tmp_file! 1>nul
            del !tmputf8! 2>nul

        )

        call :add_html_text tmp_file htm_file 1 null monosp

    )
    del %vbs_oem_converter% 2>nul


    (
        echo !date! !time! SID=%sid%.
        echo.
        echo +++++++ Reports creation completed. ++++++++
        echo.
    ) >>%log4all%

    call :sho "SID=%sid%. Final processing ISQL logs in !tmpdir! according to config parameter 'remove_isql_logs'" %log4all%

    set log_cnt=0
    set log_ptn=%tmpdir%\oltp%fb%_*.*
    for %%x in (%log_ptn%) do set /a log_cnt+=1

  	if .!crash_during_run!.==.1. (
        set msg=NOTE: FB has crashed during test run. Value of 'remove_isql_logs' is changed to 'never'. 
        remove_isql_logs=never
  	) else if .!crash_on_db_shut!.==.1. (
        set msg=NOTE: FB has crashed during DB shutdown. Value of 'remove_isql_logs' is changed to 'never'.
        remove_isql_logs=never
  	) else (
        if /i .%remove_isql_logs%.==.never. (
            set msg=Config parameter 'remove_isql_logs' has value 'never'.
        ) else if /i .!remove_isql_logs!.==.always. (
            set msg=Config parameter 'remove_isql_logs' has value 'always'. All %log_cnt% logs will be removed.
        ) else if /i .!remove_isql_logs!.==.if_no_severe_errors. (
            set msg=Config parameter 'remove_isql_logs' has value 'if_no_severe_errors'. All %log_cnt% logs will be deleted if no severe errors occured.
        )
    )
    if /i .!remove_isql_logs!.==.never. (
        set msg=!msg! All %log_cnt% logs of every ISQL session are preserved.
    )
    
    echo. > %tmp_file%
    echo !msg! >> %tmp_file%
    type %tmp_file% >> %log4all%


    if .%make_html%.==.1. (
        echo !htm_sect! ^<a name="finalpart"^> Final processing ISQL logs in %tmpdir% ^</a^> !htm_secc!>>%htm_file%
        call :add_html_text tmp_file htm_file
    )

    if /i .!remove_isql_logs!.==.always. (
        @rem ###############################################
        @rem ###  d e l e t e    l o g s     a l w a y s ###
        @rem ###############################################
        del %log_ptn%
    ) else if /i .!remove_isql_logs!.==.if_no_severe_errors. (

         (
               echo -- Check query:
               echo set list on;
               echo select
               echo     x.finished_at,
               echo     x.errors_checking_result
               echo from z_severe_gds_occured x;
               echo commit;
         ) > %rpt%

        @rem set msg=Remove logs of every ISQL session if there were no serious errors, pattern: %log_ptn%
        type %rpt% >>%log4all%
        set run_repo=%fbc%\isql %dbconn% -nod -n -pag 9999 -i %rpt% %dbauth% 

        %run_repo% 1>%tmp_file% 2>&1

        type %tmp_file% >> %log4all%

        @rem ERRORS_CHECKING_RESULT ='No severe PSQL-related problems occured'  ==> we can DELETE temp logs.
        set no_severe_errors=0
        findstr /i /c:"No severe" %tmp_file% 1>nul
        if NOT errorlevel 1 (
            set no_severe_errors=1
        )
        if .%make_html%.==.1. (
              (
                echo "<p>"
                echo Following values of gdscode are considered as SEVERE:
                echo             0 Unidentified error in PSQL code: gdscode=0 within WHEN block when exception raised.
                echo     335544321 'string truncation'. Attempt to assign too long text into string variable.
                echo     335544347 'not_valid'. Validation error for column.
                echo     335544349 'no_dup'. Attempt to store duplicate value visible to active transactions.
                echo     335544558 'check_constraint'. Operation violates CHECK constraint on view or table.
                echo     335544665 'unique_key_violation'. Violation of PRIMARY or UNIQUE KEY constraint.
                echo     335544838 'foreign_key_target_doesnt_exist'. Foreign key reference target does not exist.
                echo     335544839 'foreign_key_references_present'. Foreign key references are present for the record.
                echo "<p>"
              ) >%tmp_file%

              call :remove_enclosing_quotes %tmp_file%
      
              call :add_html_text tmp_file htm_file 1 null monosp

              (
                echo select
                echo     x.finished_at,
                echo     trim(iif(x.severe_errors_occured = 1, '$css' ^|^| '$error$', ''^)^) ^|^| x.errors_checking_result as errors_result
                echo from z_severe_gds_occured x;
                echo commit;
              ) > !rpt!
              @rem echo !htm_repn! %msg%: !htm_repc! >>%htm_file%
              call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
        )

        del %rpt% 2>nul

        if .!no_severe_errors!.==.1. (
            @rem ################################################################################
            @rem ###  d e l e t e    l o g s     i f     n o     s e v e r e     e r r o r s  ###
            @rem ################################################################################

            set msg=SID=%sid%. Required string about absence of severe errors FOUND. Temporary files with pattern %log_ptn% are DELETED.
            call :sho "!msg!" %log4all%
            del %log_ptn%
        ) else (
            set msg=At least one severe PSQL error occured. Temporary files with pattern %log_ptn% are PRESERVED.
            call :sho "!msg!" %log4all%
        )
        if .%make_html%.==.1. (
           (
               echo !msg!
               echo ^<p^>
           ) > %tmp_file%

           call :add_html_text tmp_file htm_file
        )

    )
    @rem !remove_isql_logs!.==.if_no_severe_errors.

    @rem log4all = %tmpdir%\oltp40.report.txt


    del %tmpdir%\1run_oltp_emul.err 2>nul
    del %tmpdir%\tmp_longsleep.* 2>nul

    (
        set msg=!date! !time! - end of report, text file: %log4all%
        if .%make_html%.==.1. (
            set msg=!msg!, html: %htm_file%
        )
        echo.
        echo !msg!
        echo.
        echo.
    ) > %tmp_file%

    type %tmp_file% >>%log4all%
    @rem log4all = %tmpdir%\oltp40.report.txt

    if .%make_html%.==.1. (
        call :add_html_text tmp_file htm_file
    )

    @rem Define name of final report file, see 'set name_for_saving=...' below:
    @rem ######################################################################

    @rem %fname% = value of optional config parameter 'file_name_with_test_params' = regular | benchmark, by default it is undefined.
    @rem When this value is not empty then we have to rename final report (text and html) to the file which will have maximum info
    @rem about FB build, database FW, test settings and performance result in its name.
    @rem Sample of report name when this parameter is:
    @rem 1. 'regular':   
    @rem    20151102_1448_score_06543_build_31236_ss30__3h00m_100_att_fw__on_<host_info>.txt
    @rem 2. 'benchmark': 
    @rem    ss30_fw_off_split_most__sel_1st_one_index_score_06543_build_31236__3h00m_100_att_20151102_1448_<host_info>.txt
    @rem -- where <host_info> = content of config parameter %file_name_this_host_info% // 09-mar-2016

    (
        @rem echo set heading off; 
        @rem echo select report_file from srv_get_report_name('%fname%', '%build%', %winq%^);
        @rem echo set heading on;

        echo "set list on;"
        echo "select"
        echo "    report_file"
        echo "    ,overall_perf"
        echo "    ,fb_arch"
        echo "    ,html_doc_title -- 10.05.2020: string for top.document.title = '...'"
        echo "from srv_get_report_name('%fname%', '%build%', %winq%);"

        echo "select"
        echo "    coalesce(p.exc_info,'UNKNOWN') as test_finish_state"
        echo "    ,coalesce(p.fb_gdscode, 0) as test_abend_gdscode -- when finish_state is normal then this value will be -1"
        echo "from rdb$database r"
        echo "left join perf_log p on p.unit = 'sp_halt_on_error' -- 13.10.2018: do NOT replace here "perf_log" (table) with "v_perf_log" (view)"
        echo "order by p.dts_beg desc"
        echo "rows 1;"

    ) > %rpt%

    if !conn_pool_support! EQU 1 (
        @rem ::: NB ::: 14.11.2018
        @rem Procedure srv_get_report_name uses PSQL function sys_get_fb_arch, which in turn uses ES/EDS 
        @rem which keeps infinitely connection in implementation for FB 2.5
        @rem If current implementation actually supports connection pool then we have to clear it, otherwise idle
        @rem connection will use metadata and we will not be able to drop existing PK from some tables.
        (
            echo -- ::: NB ::: do NOT add here any statement that produces output --
            echo ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;
            echo commit;
        ) >>%rpt%
    )
    call :remove_enclosing_quotes %rpt%

    set run_repo=%fbc%\isql %dbconn% -i %rpt% %dbauth%
    
    cmd /c %run_repo% 1>%tmp_file% 2>!err!

    @rem Example of result:
    @rem REPORT_FILE                     20201020_1104_score_00000_bld_33372_ss30__0h01m___1_att_fw_off_repl_0
    @rem OVERALL_PERF                    score_09876
    @rem FB_ARCH                         ss30
    @rem HTML_DOC_TITLE                  09876 b.33372/ss30 fw off

    @rem TEST_FINISH_STATE               NORMAL: TEST_TIME EXPIRED AT 2020-10-20 11:05:00
    @rem TEST_ABEND_GDSCODE              -1


    @rem runcmd=!%1!
    @rem err_file=%2
    @rem sql_file=%3
    @rem add_label=%4
    @rem do_abend=%5

    call :catch_err  run_repo  !err!  %rpt%  n/a   0
    @rem -------------------------------------------
    @rem                 1       2      3     4    5
    del %rpt% 2>nul

    findstr /m /i /c:"SQLSTATE =" !err! >nul
    if NOT errorlevel 1 (
        @rem Name of file with final report REMAINS THE SAME because we could not define it via SP srv_get_report_name.
        @rem UNSET value of 'fname':
        @rem ~~~~~
        set fname=
    )

    for /f "tokens=2" %%a in ('findstr /i /c:"REPORT_FILE " !tmp_file!') do (
        set name_for_saving=!tmpdir!\%%a
         if not .%file_name_this_host_info%.==.. (
             @rem from config: mnemona for host/cpu/ram etc:
             set name_for_saving=!name_for_saving!_%file_name_this_host_info%
         )

    )

    if .%make_html%.==.1. (
        if not .!fname!.==.. (
            for /f "tokens=*" %%a in ('findstr /i /c:"HTML_DOC_TITLE " !tmp_file!') do (
                set line=%%a
                set html_doc_title=!line:HTML_DOC_TITLE=!
                call :trim html_doc_title !html_doc_title!
            )
            if not .!html_doc_title!.==.. (
                (
                    echo ^<script^>
                    echo     // extract main data from full report name for display in the browser tab:
                    echo     top.document.title = '!html_doc_title!';
                    echo ^</script^>
                ) >> !htm_file!
            )
        )

        (
            echo ^</body^>
            echo ^</html^>
        ) >> !htm_file!

    )
    del !err!
    del !tmp_file!

    if not .!fname!.==.. (
         set final_txt=!name_for_saving!.txt
         call :repl_with_bound_quotes !final_txt! final_txt

         @rem ###################################################################################
         @rem ###  C R E A T E    T E X T    R E P O R T     W I T H     F I N A L    N A M E ###
         @rem ###################################################################################
         @rem NB: here we rename log4all = %tmpdir%\oltp40.report.txt to the final report name
         move %log4all% !final_txt!

         if .%make_html%.==.1. (
             set final_htm=!name_for_saving!.html
             call :repl_with_bound_quotes !final_htm! final_htm

             @rem ###################################################################################
             @rem ###  C R E A T E    .H T M L - R E P O R T     W I T H     F I N A L    N A M E ###
             @rem ###################################################################################
             move !htm_file! !final_htm!
          )
          @rem .%make_html%.==.1.

          if exist !results_storage_fbk! (

              call :sho "SID=%sid%. Saving data of just completed test to database." !final_txt!

              @rem 27.04.2020: obtain values from SETTINGS and write into special DB for storing overall results:
              @rem oltp_results.fdb, table results_overall
              for /f %%a in ("!results_storage_fbk!") do (
                  set results_fdb=%%~dpna.fdb.tmp
              )
              del !results_fdb! 2>nul

              set run_cmd="%fbc%\gbak -c -v -user !usr! -pas !pwd! !results_storage_fbk! !host!/!port!:!results_fdb!"
              cmd /c !run_cmd! 1>!tmp_file! 2>!err!

              @rem runcmd=!%1!
              @rem err_file=%2
              @rem sql_file=%3
              @rem add_label=%4
              @rem do_abend=%5

              call :catch_err  run_cmd   !err!   n/a   n/a   0
              @rem -------------------------------------------
              @rem                 1       2      3     4    5

              findstr /m /i /c:"gbak: ERROR:"  !err! >nul
              if errorlevel 1 (
                  call :sho "SID=%sid%. Restore from !results_storage_fbk! to temporary FDB completed OK." !final_txt!
                  (
                      echo set bail on;
                      echo connect '!host!/!port!:!results_fdb!' user '!usr!' password '!pwd!';
                      echo -- defined in oltp_results_storage_DDL.sql:
                      echo execute procedure eds_obtain_last_test_results(
                      echo    '!host!/!port!:!dbnm!' -- oltp_data_db
                      echo    ,'!usr!' -- eds_usr
                      echo    ,'!pwd!' -- eds_pwd
                      echo    ,!mon_unit_perf! -- smallint
                      echo ^);
                      echo commit;
                      echo set list on;
                      echo set echo on;
                      echo select * from results_overall order by run_id desc rows 1;
                  ) > %rpt%
                  set run_repo=%fbc%\isql -q -nod -i %rpt%

                  call :sho "SID=%sid%. Saving test settings and last run results in !results_fdb!. Command:" !final_txt!
                  call :sho "!run_repo!" !final_txt!
                  cmd /c !run_repo! 1>%tmp_file% 2>!err!
                  
                  type !err! >> !final_txt!

                  @rem runcmd=!%1!
                  @rem err_file=%2
                  @rem sql_file=%3
                  @rem add_label=%4
                  @rem do_abend=%5

                  call :catch_err  run_repo  !err!  %rpt%  n/a
                  @rem ---------------------------------------
                  @rem                 1       2      3     4 

                  if .%make_html%.==.1. if exist !final_htm! (

                      @rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                      @rem @@@  c o m p r e s s    H T M L,   c o n v e r t    t o    b a s e - 6 4    a n d    s a v e    t o    r e s u l t s _ f b k  @@@
                      @rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

                      for /f "tokens=2" %%a in ('findstr /i /c:"run_id " !tmp_file!') do (
                          set v_run_id=%%a
                      )
                      if not .!v_run_id!.==.. (

                          if not "!report_compressor!"=="" (

                              if not exist !report_compressor! (
                                  call :sho "Parameter 'report_compressor' points to missed file: !report_compressor!" !final_txt!
                                  goto :fin
                              )

                              @rem ################################################################
                              @rem Replace relative path to decompress binaries with absolute one.
                              @rem ::: NB ::: Variabled PARENTDIR and GRANDPDIR must be defined
                              @rem at the START of this script, NOT inside if (...) block!
                              @rem Otherwise replacing string will fail because their values
                              @rem will not be seen here!
                              @rem ################################################################
                              set report_compressor=!report_compressor:..\..=%GRANDPDIR%!
                              set report_compressor=!report_compressor:..=%PARENTDIR%!

                              @rem Generate temporary .vbs script in !TMPDIR! for extracting binary 7z.exe
                              @rem from ..\compressors\7z.exe.zip
                              @rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
                              set tmpvbs=!tmpdir!\%~n0.extract-from-zip.tmp.vbs

                              (
                                  echo ' Original text:
                                  echo ' https://social.technet.microsoft.com/Forums/en-US/8df8cbfc-fe5d-4285-8a7a-c1fb201656c8/automatic-unzip-files-using-a-script?forum=ITCG
                                  echo ' Examples:
                                  echo '     %systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !report_compressor! !tmpdir!

                                  echo option explicit

                                  echo dim sourceZip, targetDir, oFSO, oShell, oSource, oTarget

                                  echo ' Required input arguments:
                                  echo ' N1 = *full* name of .zip to be extracted;
                                  echo ' N2 = target directory 

                                  echo sourceZip=WScript.Arguments.Item(0^)
                                  echo targetDir=WScript.Arguments.Item(1^)

                                  echo set oFSO = CreateObject("Scripting.FileSystemObject"^)
                                  echo if not oFSO.FolderExists(targetDir^) then
                                  echo     oFSO.CreateFolder(targetDir^)
                                  echo end if
                                  echo set oShell = CreateObject("Shell.Application"^)
                                  echo set oSource = oShell.NameSpace(sourceZip^).Items(^)
                                  echo set oTarget = oShell.NameSpace(targetDir^)

                                  echo ' Prevent from dialog box with question overwrite existing files:
                                  echo ' https://docs.microsoft.com/en-us/previous-versions/tn-archive/ee176633(v=technet.10^)?redirectedfrom=MSDN
                                  echo ' Table 11.9 Shell Folder CopyHere Constants
                                  echo ' ^&H10^& -- Automatically responds "Yes to All" to any dialog box that appears. 
                                  echo ' ^&H4^& Copies files without displaying a dialog box.
                                  echo ' bin_or(10,14^) is 14

                                  echo oTarget.CopyHere oSource, ^&H14^&
                              ) >!tmpvbs!

                              set run_cmd=%systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !report_compressor! !tmpdir!
                              call :sho "Extract compressor from report_compressor=!report_compressor! to !tmpdir!. Command:" !final_txt!
                              call :sho "!run_cmd!" !final_txt!
                              
                              @rem ####################################
                              @rem ::: NB ::: 12.11.2020
                              @rem cscript returns errorlevel = 0 even when some error occured.
                              @rem We have to check SIZE of STDERR log!
                              @rem ####################################
                              cmd /c !run_cmd! 1>!err! 2>&1
                              
                              for /f "usebackq tokens=*" %%a in ('!err!') do (
                                  set err_size=%%~za
                              )
                              if .!err_size!.==.. set err_size=0
                              if !err_size! GTR 0 (
                                  call :sho "Extraction FAILED. Check log:" !final_txt!
                                  type !err!
                                  type !err!>>!final_txt!
                                  goto :fin
                              )
                              call :sho "Completed." !final_txt!

                              @rem Adjust path and name of utility for make HTML report compression:
                              @rem =================================================================
                              for /f %%a in ("!report_compressor!") do (
                                  set report_compress_cmd=!tmpdir!\%%~na
                                  if /i "%%~na"=="7z.exe" (
                                      set compress_format=7z
                                  ) else if /i "%%~na"=="zstd.exe" (
                                      set compress_format=zstd
                                  )
                              )

                              @rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

                          ) else (
                              call :sho "Ñonfig parameter 'report_compressor' is undefined. ZIP format is used to compress HTML report." !final_txt!
                              set compress_format=zip
                          )
                          

                          if /i .!compress_format!.==.7z. (
                              set compressed_name=!final_htm!.tmp.7z
                              set zip_cmd="!report_compress_cmd! u -mx9 -mfb273 !compressed_name! !final_htm!"
                              cmd /c !zip_cmd! 2>>!final_txt!
                              dir /-c !compressed_name! | findstr /i /c:".7z" 1>>!final_txt! 2>&1

                          ) else if /i .!compress_format!.==.zstd. (
                              set compressed_name=!final_htm!.tmp.zst
                              set zip_cmd="!report_compress_cmd! -19 !final_htm! -o !compressed_name!"
                              cmd /c !zip_cmd! 2>>!final_txt!
                              dir /-c !compressed_name! | findstr /i /c:".zst" 1>>!final_txt! 2>&1

                          ) else if /i .!compress_format!.==.zip. (
                              @rem Generate .vbs for compressing text file
                              set tmpvbs=!tmpdir!\%~n0.compress_report_to_zip.tmp.vbs
                              set compressed_name=!final_htm!.tmp.zip
                              (
                                  echo "' Generated auto by %~f0, !date! !time!"
                                  echo "' Source idea: https://www.tek-tips.com/viewthread.cfm?qid=1231429"
                                  echo "' This script is used for compressing html report to ZIP format when"
                                  echo "' OLTP-EMUL config parameter 'report_compressor' is UNDEFINED."
                                  echo "' Required input arguments:"
                                  echo "' N1 = path+name of .zip to be created;"
                                  echo "' N2 = path+name of text file to be compressed."
                                  echo "' NOTE: file defined by arg N1 must have extension .zip"
                                  echo "option explicit"
                                  echo "dim zipfile, srcfile, fso,ts, x,blankZip,objShell,WshShell, zipObj"
                                  echo "zipfile=WScript.Arguments.Item(0)"
                                  echo "srcfile=WScript.Arguments.Item(1)"
                                  echo "set fso = CreateObject("Scripting.FileSystemObject")"
                                  echo "set ts = fso.OpenTextFile(zipfile, 8, vbtrue)"
                                  echo "blankZip = "PK" & Chr(5) & Chr(6)"
                                  echo "for x = 0 to 17"
                                  echo "    blankZip = blankZip & Chr(0)"
                                  echo "next"
                                  echo "ts.write blankZip"
                                  echo "set fso = nothing"
                                  echo "set ts = nothing"
                                  echo "' This creates an empty zip file in the directory c:\test1"
                                  echo "' After this you fill the zipfile. I'm still searching for the best wait command but"
                                  echo "' you might want to let the script sleep for half a second to allow it to create the zip"
                                  echo "' file before progressing."
                                  echo "set objShell = CreateObject("Shell.Application")"
                                  echo "set WshShell = WScript.CreateObject("WScript.Shell")"
                                  echo "set zipObj = objShell.NameSpace(zipfile)"
                                  echo "zipObj.copyHere(srcfile)"
                                  echo "WScript.Sleep( 500 )"
                              ) > !tmpvbs!

                              call :remove_enclosing_quotes !tmpvbs!
                              set zip_cmd="%systemroot%\system32\cscript.exe //nologo //e:vbscript !tmpvbs! !compressed_name! !final_htm!"

                              @rem ################################################
                              @rem ###  compress file to .ZIP format using .VBS ###
                              @rem ################################################

                              cmd /c !zip_cmd! 2>!err!

                              if .!err_size!.==.. set err_size=0
                              if !err_size! GTR 0 (
                                  call :sho "Compress FAILED. Check !tmperr!:" !final_txt!
                                  type !err!
                                  type !err!>>!final_txt!
                                  goto :fin
                              )
                              call :sho "Completed." !final_txt!

                              dir /-c !compressed_name! | findstr /i /c:".zip" 1>>!final_txt! 2>&1

                          )
                          @rem !compress_format! == 7z / zstd /  zip

                          if not "!report_compress_cmd!"=="" (
                              for /f %%a in ("!report_compress_cmd!") do (
                                  if "%%~dpa"=="!tmpdir!\" (
                                      if exist !report_compress_cmd! (
                                          call :sho "Deleting file !report_compress_cmd!" !final_txt!
                                          del !report_compress_cmd! 1>>!final_txt! 2>&1
                                      )
                                  )
                              )
                          )


                          set b64_cmd="certutil -encode !compressed_name! !final_htm!.b64.tmp"
                          cmd /c !b64_cmd! 2>>!final_txt!
                          dir /-c !final_htm!.b64.tmp | findstr /i /c:".b64.tmp" 1>>!final_txt! 2>&1

                          @rem cut-off first and last rows from base64 that was created by certutil:
                          findstr /i /v /r /c:"begin[ ]*cert" /c:"end[ ]*cert" !final_htm!.b64.tmp > !final_htm!.compressed.b64
                          
                          for /d %%x in (!compressed_name!,!tmpvbs!, !final_htm!.b64.tmp) do (
                              if exist %%x del %%x
                          )

                          @rem result: compressed file was converted to base64 format and is stored as !final_htm!.7z.b64

                          @rem Now we generate temporary .sql for storing content of b64-file into results database:
                          del %rpt% 2>nul
                          (
                              echo set bail on;
                              echo set echo on;
                              echo connect '!host!/!port!:!results_fdb!' user '!usr!' password '!pwd!';
                              for /f %%a in (!final_htm!.compressed.b64) do (
                                  echo insert into results_reports(run_id, zip2b64^) values(!v_run_id!, '%%a'^);
                              )
                              if /i .!compress_format!.==.zip. (
                                  echo update results_overall o set o.report_compress_cmd=right('cscript ^<VBS^> ^<zip^> ^<report^>',255^) where o.run_id=!v_run_id!;
                              ) else (
                                  echo update results_overall o set o.report_compress_cmd=right('!report_compress_cmd!',255^) where o.run_id=!v_run_id!;
                              )
                              echo commit;
                              echo set echo off;
                              echo set list on;
                              echo select 'HTML-report has been compressed, converted to base64 and successfully saved in !results_fdb!.' as result_msg from rdb$database;
					      ) > %rpt%
					      del !final_htm!.compressed.b64

                          set run_repo=%fbc%\isql -q -nod -i %rpt%
                          call :sho "SID=%sid%. Saving HTML report in !results_fdb!, run_id=!v_run_id!. Command:" !final_txt!
                          call :sho "!run_repo!" !final_txt!

                          cmd /c !run_repo! 1>%tmp_file% 2>!err!
                          type !err! >> !final_txt!

                          call :catch_err  run_repo  !err!   n/a   n/a
                          @rem ---------------------------------------
                          @rem                 1       2      3     4

                          
                          findstr /i /c:"result_msg " !tmp_file! >> !final_txt!

                      )
                      @rem if not .!v_run_id!.==..

                  )
                  @rem .%make_html%.==.1. if exist !final_htm!

                  set run_cmd="%fbc%\gbak -b -user !usr! -pas !pwd! !host!/!port!:!results_fdb! !results_storage_fbk!"
                  call :sho "SID=%sid%. Make backup of new results to !results_storage_fbk!" !final_txt!
                  cmd /c !run_cmd! 1>!tmp_file! 2>!err!
                  type !err! >> !final_txt!

                  call :catch_err  run_cmd   !err!   n/a   n/a   0
                  @rem -------------------------------------------
                  @rem                 1       2      3     4    5

                  call :sho "SID=%sid%. Backup results to !results_storage_fbk! completed Ok." !final_txt!
                  for /d %%x in (!tmp_file!,!err!,!rpt!,!results_fdb!) do (
                      if exist %%x del %%x
                  )


              ) else (
                  call :sho "SID=%sid%. Restore from !results_storage_fbk! FAILED. Report data will not be saved." !final_txt!
              )
              @rem errlevel=0 when restore

          )

    ) else (
        @rem  .%fname%.==..
        set name_for_saving=%log4all%
    )
    @rem if .%fname% is-defined xor not-defined

    set batch4stop=%tmpdir%\1stoptest.tmp.bat
    call :repl_with_bound_quotes !batch4stop! batch4stop
    del !batch4stop! 2>nul

  goto end

:end
  @rem ###########################################################################
  @rem ###                                                                     ###
  @rem ###                             E N D                                   ###
  @rem ###                                                                     ###
  @rem ###########################################################################
  goto fin

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:remove_CR_from_file
@rem https://www.computing.net/answers/windows-xp/removing-carriage-returns-from-a-textfile/197677.html
setLocal
set sourfile=%1
set targfile=%2
if exist !targfile! del !targfile!
for /f "tokens=*" %%a in ('find /n /v "" ^< !sourfile!') do (
    set line=%%a
    set line=!line:*]=!
    @rem "set /p" won't take "=" at the start of a line....
    if "!line:~0,1!"=="=" set line= !line!

    @rem ::::::::::::::::: NB :::::::::::::::::::::::
    @rem there must be a blank line after "set /p"
    @rem and "<nul" must be at the start of the line
    @rem ::::::::::::::::: NB :::::::::::::::::::::::
    set /p =!line!^

<nul
) >> !targfile!
endlocal 
goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:repl_with_bound_quotes

    @rem Used for returning proper command that is full path and name of executable so that 
    @rem it can be further invoked via cmd /c.
    @rem When path from config is like: "C:\Program Files\Firebird Database Server 2.5.5\bin"
    @rem - then we can NOT simply add some FB utility name ('isql', 'fbsvcmgr' etc) after the 
    @rem right quote character: such command can not be interpreted by cmd.exe and will not run.
    @rem So, we need:
    @rem 1. Remove all quotes from input arg. (say, this is '<unquoted_input_arg>')
    @rem 2. Create output arg as: <double_quote_char> + <unquoted_input_arg> + <double_quote_char>
    @rem ..................................................................................................
    @rem Sample (suppose that `fbc` var. is: "C:\Program Files\Firebird Database Server 2.5.5\bin")
    @rem
    @rem set fbsvcrun=%fbc%\fbsvcmgr
    @rem call :repl_with_bound_quotes %fbsvcrun% fbsvcrun
    @rem
    @rem Result variable `fbsvcrun` will be: "C:\Program Files\Firebird Database Server 2.5.5\bin\fbsvcmgr" 

    setlocal

    set must_quote=-1
    set result=%1

    call :has_spaces %1 must_quote

    if .%must_quote%.==.1. (
 
        set result=!result:"=!
        set result="!result!"
    )
    endlocal & set "%~2=%result%"
goto:eof

:has_spaces

    @rem www.dostips.com/DtTutoFunctions.php#FunctionTutorial.ReturningLocalVariables
    @rem Sample:
    @rem set must_be_quoted=-1
    @rem                              v--------------v--- do NOT put '%' or '!' around argument that is passed by-ref!
    @rem call :has_spaces %some_var%   must_be_quoted
    @rem echo must_be_quoted=%must_be_quoted%

    setlocal
    @rem echo has_spaces: arg_1=%1 arg_2=%2

    set tmp=!%1:"=!
    set result=0
    if not "!tmp!"=="!tmp: =!" set result=1
    @rem echo result=%result%

    endlocal & set "%~2=%result%"

goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:add_html_text 

    setlocal

    set tmp_file=!%1!
    set htm_file=!%2!
    set add_br=%3
    set line_prefix=%4
    set use_style=%5
    set dbg=0

    if not defined add_br set add_br=1
    if .%line_prefix%.==.null. set line_prefix=

    (
        if not .%use_style%.==.. (
          if .%use_style%.==.pre. (
              echo ^<pre^>
          ) else (
              echo ^<div class="%use_style%"^>
          )
        )

        for /f "tokens=*" %%a in ('type %tmp_file%') do (
            set line=%line_prefix%%%a
            if not .!line!.==.. (
              set ccss=!line:$css$error$=!
              if not !ccss!==!line! (
                set line=^<span class="error"^>!ccss!^</span^>
              ) else (
                set ccss=!line:$css$warning$=!
                if not !ccss!==!line! (
                  set line=^<span class="warning"^>!ccss!^</span^>
                ) else (
                  set ccss=!line:$css$success$=!
                  if not !ccss!==!line! (
                    set line=^<span class="success"^>!ccss!^</span^>
                  ) else (
                    set ccss=!line:$css$fault$=!
                    if not !ccss!==!line! set line=^<span class="fault"^>!ccss!^</span^>
                  )
                )
              )
            )
            @rem do NOT add leading BR tag: excessive empty line will appear.
            if .%add_br%.==.1. ( echo !line!^<br /^> ) else ( echo !line! )
        )

        if not .%use_style%.==.. (
          if .%use_style%.==.pre. (
              echo ^</pre^>
          ) else (
              echo ^</div^>
          )
        )

    ) >> %htm_file%

    endlocal
goto:eof
@rem ^
@rem end of 'add_html_text' subroutine

@rem +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-

:split_key_value_pair

    setlocal

    set key_values_list=%1
    set delimiter_char=%2
    if .!delimiter_char!.==.. (
        echo Subroutine 'split_key_value_pair':
        echo MISSED MANDATORY ARG #2: 'delimiter_char'
        exit
    )
    @rem NOTE: arguments NN 3 and 4 are used for OUTPUT.

    call :dequote_string !key_values_list! key_values_list
    call :dequote_string !delimiter_char! delimiter_char

    @rem 23.10.2020 ### MANDATORY ###
    @rem Such names can be used in caller code!
    @rem ######################################
    set chart_attr_key=
    set chart_attr_val=

    set /a k=1
:loop_split
    for /f "tokens=1* delims=%delimiter_char%" %%a in ("!key_values_list!") do (
       if !k! EQU 1 (
           set chart_attr_key=%%a
       ) else (
           @rem For 2nd and further tokens - make concatenation:
           @rem 23.10.2020: it is crusial that 'chart_attr_val' must be UNSET before this loop!
           set chart_attr_val=!chart_attr_val!%%a
       )
       set key_values_list=%%b
       set /a k=!k!+1
       goto :loop_split
    )

endlocal & set "%~3=%chart_attr_key%" & set "%~4=%chart_attr_val%"
goto:eof
@rem ^
@rem end of 'split_key_value_pair' subroitine

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:split_by_delimiter

    setlocal

    set src_list=%1 &:: Example: "Average reads; Average fetches"
    set src_delimiter_char=%2 &:: delimiter that must be used for split. Usually semicolon.

    set out_delimiter_char=%3 &:: Delimiter that must be used in output list. Usually comma.
    set out_enclosing_char=%4 &:: Character that must be used for enclosing each token in output list. Usually single quote - apostroph

    @rem Arguments NN 5 and 6 are used for OUTPUT result:

    @rem out, resulting list:
    set out_tokens_list=

    @rem out, number of tokens:
    set /a out_tokens_count=0

    call :dequote_string !src_list! src_list
    call :dequote_string !src_delimiter_char! src_delimiter_char
    call :dequote_string !out_delimiter_char! out_delimiter_char
    call :dequote_string !out_enclosing_char! out_enclosing_char

if .1.==.0. (
    echo after dequote:
    echo src_list=.!src_list!.
    echo exclam: src_delimiter_char=!src_delimiter_char!
    echo percen: src_delimiter_char=%src_delimiter_char%
    echo.
    echo exclam: out_delimiter_char=.!out_delimiter_char!.
    echo percen: out_delimiter_char=.%out_delimiter_char%.
    echo.
    echo exclam: out_enclosing_char=!out_enclosing_char!
    echo percen: out_enclosing_char=%out_enclosing_char%
    set>set2.txt
    pause
)

:loop_src_list
    @rem ::: NOTE :::
    @rem DO NOT USE EXCLAMATION SIGN FOR src_delimiter_char HERE:
    for /f "tokens=1* delims=%src_delimiter_char%" %%x in ("!src_list!") do (
        set /a out_tokens_count=!out_tokens_count!+1
        set val=%%x

        call :trim val !val!

        if .!out_tokens_list!.==.. (
            set out_tokens_list=!out_enclosing_char!!val!!out_enclosing_char!
        ) else (
            set out_tokens_list=!out_tokens_list!!out_delimiter_char!!out_enclosing_char!!val!!out_enclosing_char!
        )

        if .1.==.0. (
            echo.
            echo routine split_by_delimiter: val=.!val!.
            echo src_delimiter_char=.!src_delimiter_char!.
            echo out_tokens_list=.!out_tokens_list!.
            pause
        )
        
        set src_list=%%y

        if .1.==.0. (
            echo routine split_by_delimiter: new out_tokens_list=.!out_tokens_list!.
            echo new src_list=.!src_list!.
            pause
        )

        goto :loop_src_list
    )

if .1.==.0. (
    echo leaving split_by_delimiter:
    echo out_tokens_list=.!out_tokens_list!.
    echo out_tokens_count=!out_tokens_count!
    set >set2.txt
    exit
)


endlocal & set "%~5=%out_tokens_list%" & set "%6=%out_tokens_count%"
goto:eof
@rem ^
@rem end of 'split_by_delimiter' subroitine

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:get_sqlda_fld_name
    setlocal
    set fb=%1

    @rem must be passed here enclosed into double quotes:
    set sqlda_name=%2

    @rem NOTE: argument N3 will be used for OUTPUT value.

    set fld_name=!sqlda_name!

    if .%fb%.==.25. (
       call :split_key_value_pair !sqlda_name! ")" dummy_key fld_name
    ) else (
       call :dequote_string !fld_name! fld_name
    )

    @rem ?!?!?!? FOR WHAT >>>> ???? >>>> set fld_name=!fld_name: =!
   
    endlocal & set "%~3=%fld_name%"
goto:eof
@rem ^
@rem end of get_sqlda_fld_name

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:is_num_type

    setlocal

    set fld_num=%1
    set tmp_file=%2
    set out_params_1st_line=%3

    set /a k=1000+%fld_num%
    set k=!k:~2,2!
    set result=0
    set num_types=SHORT LONG INT64 DOUBLE LONG FLOAT DECFLOAT INT128

    @rem Sample for lines in tmp_file = %tmpdir%\make_html_table.tmp.sqd (result of output SQLDA): with OUPUT parameters:
    @rem 2.5: 04: sqltype: 497 LONG	  Nullable sqlscale: 0 sqlsubtype: 0 sqllen: 4 -- TAB between "LONG" and NUllable
    @rem 3.0: 04: sqltype: 496 LONG Nullable scale: 0 subtype: 0 len: 4

    for /f "tokens=1-7 delims=: " %%a in ('findstr /n /c:"!k!: sqltype:" %tmp_file%') do (
      
      if %%a gtr %out_params_1st_line% (
         
         set fld_type=%%e

         @rem ::: NB ::: Token for 2.5 can contain TAB as trailing character, so we have to TRIM it
         @rem otherwise search for numeric-type columns for this resultset will NOT found any field!

         if not !fld_type!==.. call :trim fld_type !fld_type!
         @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
         
         @rem echo rowN=%%a b=1st_token=%%b c=%%c d=%%d fld_type=^|!fld_type!^| f=%%f g=%%g &pause

         for /d %%s in ( %num_types% ) do (
            if .!fld_type!.==.%%s. (
               set result=1
               @rem echo found NUMERIC type, field: %fld_num% &pause
            )
         )
      )
    )

    endlocal & set "%~4=%result%"
goto:eof
@rem ^
@rem end of is_num_type

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
@rem ###                 a d d _ h t m l _ t a b l e                      ###
@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
:add_html_table

    setlocal

    set fbc=!%1!
    set tmpdir=!%2!
    set dbconn=!%3!
    set dbauth=!%4!
    set sql_in=!%5!
    set htm_file=!%6!

    @rem 16.10.2020
    set chart_settings=!%7!

    set dbg=0

    rem %fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    set sql_temp=%tmpdir%\make_html_table.tmp.sql
    set sql_log=%tmpdir%\make_html_table.tmp.log
    set sql_err=%tmpdir%\make_html_table.tmp.err
    set tmp_sqlda=%tmpdir%\make_html_table.tmp.sqd
    set tmp_nums=%tmpdir%\make_html_table.tmp.num
    set tmp_html=%tmpdir%\make_html_table.tmp.html

    call :repl_with_bound_quotes %sql_temp% sql_temp
    call :repl_with_bound_quotes %sql_log% sql_log
    call :repl_with_bound_quotes %sql_err% sql_err
    call :repl_with_bound_quotes %tmp_sqlda% tmp_sqlda
    call :repl_with_bound_quotes %tmp_nums% tmp_nums
    call :repl_with_bound_quotes %tmp_html% tmp_html


    set tmp_chart_data=%tmpdir%\make_html_chart_data.tmp
    set tmp_chart_html=%tmpdir%\make_html_chart_data.html
    call :repl_with_bound_quotes %tmp_chart_data% tmp_chart_data
    call :repl_with_bound_quotes %tmp_chart_html% tmp_chart_html

    for /d %%f in (!sql_temp!,!sql_log!,!sql_err!,!tmp_sqlda!,!tmp_nums!,!tmp_html!,!tmp_chart_html!,!tmp_chart_data!) do (
        if exist %%f del %%f
    )

    if exist !chart_settings! (

        for /f "tokens=*" %%a in (!chart_settings!) do (
            set tmp_list=%%a

            set chart_attr_key=
            set chart_attr_val=

            call :split_key_value_pair "!tmp_list!" "=" chart_attr_key chart_attr_val

            if /i .!chart_attr_key!.==.draw_func_name. (
                set draw_func_name=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.x_axis_field. (
                set x_axis_field=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.x_axis_title. (
                set x_axis_title=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.y_fields_list. (
                set y_fields_list=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.y_format_list. (
                @rem https://developers.google.com/chart/interactive/docs/reference#numberformatter
                @rem List of formats (optional but all columns must be involved if specified):
                @rem pattern: '0';   pattern: '0.00',negativeColor: 'red';   fractionDigits: 4;   etc
                set y_format_list=!chart_attr_val!
                
                @rem remove all inner spaces because below we will iterato though this valirabel using "FOR /D" loop:
                set y_format_list=!y_format_list: =!

            ) else if /i .!chart_attr_key!.==.y_scale_type. (
                @rem Optional: 'log' --> show chart with logarithmic scale in Y-axis:
                set y_scale_type=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.y_legends_list. (
                set y_legends_list=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.y_leg_maxlines. (
                set y_leg_maxlines=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.y_colors_list. (
                set y_colors_list=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.y_list_delimiter. (
                set y_list_delimiter=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_libs_reload. (
                @rem chart_libs_reload -- whether we have to load basic google charts libraries HERE rather than suppose
                @rem they are loaded in the whole web page <head> section (i.e. in ONE place, ONE time for the page) ?
                @rem https://developers.google.com/chart/interactive/docs/basic_load_libs
                @rem default 0; if 1 then initializing of google chart will be HERE
                @rem ::: NB ::: Passing 1 here NOT recommended! runtime error can occur after drawing 6-7 charts in one page:
                @rem too much recursion (Firefox) or "Maximum Call Stack Size Exceeded" (Chrome).
                @rem See discussion here: https://groups.google.com/forum/#!topic/Google-Visualization-Api/iigCT7a-MFk
                set chart_libs_reload=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_only_show. (
                set chart_only_show=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_title. (
                set chart_title=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_inline_block. (
                @rem add 'display: inline-block;' to DIV as part of its STYLE properties
                @rem in order to show it in ONE LINE after previous div (if it is possible).
                @rem Trivial example: http://interestingwebs.blogspot.com/2012/10/div-side-by-side-in-one-line.html
                @rem Example of result: <div id="mon_reads_fetches_chart_div" style="width: 550px; height: 350px;display: inline-block;"></div>
                set chart_inline_block=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_area_options. (
                @rem Example: { left:60, right:5, width:"100%", } -- values for 'chartArea:'; useful to reduce margins around chart
                set chart_area_options=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_type. (
                set chart_type=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_div_wid. (
                set chart_div_wid=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.chart_div_hei. (
                set chart_div_hei=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.href_name. (
                @rem Name of HTML-anchor to quick-jump by click on inner URL
                set href_name=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.href_title. (
                @rem Name of inner URL for user
                set href_title=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.axis_color. (
                set axis_color=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.x_axis_slanted_labels. (
                @rem must be STRING with value: 'true' or 'false'
                set x_axis_slanted_labels=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.x_values_skip_pattern. (
                @rem Additional filter for records to be shown in chart (actual for perf per minute: we have to skip from there WARM_TIME phase).
                set x_values_skip_pattern=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.curve_type. (
                set curve_type=!chart_attr_val!
            ) else if /i .!chart_attr_key!.==.point_size. (
                set point_size=!chart_attr_val!
            )

        )
        if .!chart_libs_reload!.==.. (
            @rem default: we suppose that basic libaries already loaded in the <HEAD> section of web page.
            set chart_libs_reload=0
        )

        if .!chart_only_show!.==.. (
            @rem do we show only chart, without table ? Usually this is NO.
            set chart_only_show=0
        )

        if .!chart_div_wid!.==.. (
            set chart_div_wid=1200
        )
        if .!chart_div_hei!.==.. (
            set chart_div_hei=350
        )

        if .!y_list_delimiter!.==.. (
            set y_list_delimiter=;
        )

        if .!y_leg_maxlines!.==.. (
            set y_leg_maxlines=3
        )

        if .!chart_inline_block!.==.1. (
            @rem do NOT enclose into double quotes! This is INNER element of STYLE properties list:
            set div_inline_expr=display: inline-block;
        )
        if .!axis_color!.==.. (
            set axis_color=DarkOliveGreen
        )
        if .!chart_type!.==.. (
            set chart_type=ScatterChart
        )
        if .!x_values_skip_pattern!.==.. (
            @rem forcedly assign non-empty value to this var in order to apply findstr, see below:
            set x_values_skip_pattern=NOTHING_TO_SKIP
        )


        @rem ...............................

        set cols_for_data=
        for /d  %%x in (!y_fields_list!) do (
            set cols_for_data=!cols_for_data!,'%%x'
        )

        call :split_by_delimiter "!y_fields_list!"  ";"  ","  "'"  cols_for_data  dummy_var
        @rem                             1           2    3    4        5             6
     
        @rem Example:
        @rem y_fields_list = .reads / fetches;           writes / marks.
        @rem cols_for_data = .'reads / fetches','writes / marks'.

        @rem ...............................
        set color_expr=colors: [
        for /d  %%x in (!y_colors_list!) do (
            set color_expr=!color_expr!'%%x',
        )
        set color_expr=!color_expr! ]
        @rem Example: color_expr=colors: ['DarkCyan','Red','Green','Brown',],
        @rem ...............................
        if .!y_legends_list!.==.. (
            set tmp_list=!y_fields_list!
        ) else (
            set tmp_list=!y_legends_list!
        )

        call :split_by_delimiter "!tmp_list!"  ";"  ","  "'"  legend_expr  y_charts_count
        @rem                          1         2    3    4        5             6

        @rem Example-1:
        @rem     tmp_list=.field_name_01; field_name_02; field_name_03.
        @rem Result:
        @rem     legend_expr=.'field_name_01','field_name_02','field_name_03'.
        @rem     y_charts_count=3

        @rem Example-2:
        @rem     tmp_list=.Average reads; Average fetches.
        @rem Result:
        @rem     legend_expr=.'Average reads','Average fetches'.
        @rem     y_charts_count=2

        set legend_expr=[ '', !legend_expr! ]

        @rem ...............................

        set legpos_expr=legend:{ position:'top', maxLines: !y_leg_maxlines! }

	    (
    	    echo "    var data = google.visualization.arrayToDataTable(["
    	    echo "        !legend_expr!"
	    ) >!tmp_chart_data!

if .1.==.0. (
set>set.txt
echo chart_settings=!chart_settings!
echo tmp_list=!tmp_list!
echo legend_expr=!legend_expr!
echo KKKKKKKKKKKKKKKKKK
pause
)


    )
    @rem if exist !chart_settings!


    (
        echo set sqlda_display on;
        echo set planonly;
        type %sql_in%
    ) > %sql_temp%

    %fbc%\isql %dbconn% %dbauth% -i %sql_temp% 1>%tmp_sqlda% 2>%sql_err%

    set sql_abend=0
    for %%a in (%sql_err%) do if not %%~za lss 1 (
        echo !htm_repn! PREPARE FAILED: !htm_repc! >>%tmp_html%
        call :add_html_text sql_temp tmp_html
        call :add_html_text sql_err tmp_html 1 $css$fault$
        set sql_abend=1
    )

    if .!sql_abend!.==.1. (
        @rem ###############
        @rem ###  ABEND  ###
        @rem ###############
        goto :add_html_final
    )


    @rem 2.5: OUTPUT SQLDA version: 1 sqln: 20 sqld: 1
    @rem 3.0: OUTPUT message field count
    for /f "tokens=1 delims=:" %%a in ('findstr /n /c:"OUTPUT message " /c:"OUTPUT SQLDA" %tmp_sqlda%') do set out_line=%%a

    findstr /i /c:"alias" %tmp_sqlda% 1>%sql_log%

    @rem 2.5:
    @rem  :  name: (12)WORKING_MODE  alias: (8)CATEGORY
    @rem  :  name: (5)MCODE  alias: (7)SETTING
    @rem  :  name: (6)SVALUE  alias: (3)VAL
    @rem ^    ^            ^---^        ^
    @rem a    b              c          d
    
    @rem 3.0:
    @rem  :  name: WORKING_MODE  alias: CATEGORY
    @rem  :  name: MCODE  alias: SETTING
    @rem  :  name: SVALUE  alias: VAL
    @rem ^    ^       ^---^        ^
    @rem a    b         c          d

    @rem echo tmp_sqlda=%tmp_sqlda% out_line=%out_line%=!out_line!

    @rem Construct list of columns where data should be right-aligned because of their NUMERIC types:
    set /a k=1
    set num_list=
    set fld_name=

    for /f "tokens=1-5 delims=:" %%a in ('type !sql_log!') do (
        
        @rem Example for 2.5:
        @rem    :  name: (8)CONSTANT  alias: (11)foo rio bar
        @rem |a|  |-b-| |------- c -------| |------ d------|
        @rem %%d is: |(11)foo rio bar| ==> we have to split this string using delimiter ")"

        @rem Example for 3.0:
        @rem    :  name: CONSTANT  alias: mio meo mau
        @rem |a| |--b-| |------ c -----| |---- d ---|
        @rem %%d is: |foo rio bar| ==> we have to take this string 'as is', w/o any action.

        set fld_name=%%d

        call :trim fld_name !fld_name!

        call :get_sqlda_fld_name %fb% "!fld_name!" fld_name

        set is_num=2
        call :is_num_type !k! %tmp_sqlda% %out_line% is_num

        if .!is_num!.==.1. set num_list=!num_list!,!k!
        set /a k=!k!+1
    )
    @rem echo after loop for /f "tokens=1-5 delims=:" %%a in 'type !sql_log!'

    set num_list=!num_list!,
    echo !num_list!>%tmp_nums%

    @rem echo num_list=!num_list! &pause

    @rem result: num_list = list of POSITION INDICES which relates to numeric fields.

    echo "<table class="t_table" border="1" cellpadding="3">">> %tmp_html%


    @rem -------- tags for open and close table header, row and cell -----------
    set tho="<th>"& set tho=!tho:"=!
    set thc="</th>"& set thc=!thc:"=!

    set tro="<tr>"& set tro=!tro:"=!
    set trc="</tr>"& set trc=!trc:"=!

    set tdo="<td>"& set tdo=!tdo:"=!
    set tdc="</td>"& set tdc=!tdc:"=!

    set tdno="<td align=Right>"& set tdno=!tdno:"=!
    set tdnc="</td>"& set tdnc=!tdnc:"=!
    @rem -----------------------------------------------------------------------


    @rem Output HEADER of table
    @rem ######################
    set i=1
    (
        for /f "tokens=1-5 delims=:" %%a in ('type %sql_log%') do (

            set fld_name=%%d

            call :trim fld_name !fld_name!

            if .!i!.==.1. (
                call :get_sqlda_fld_name %fb% "!fld_name!" fld_first
            )

            call :get_sqlda_fld_name %fb% "!fld_name!" fld_name

            if not .%%d.==.. (
                echo "<th>!fld_name!</th>"
            ) else (
                echo "<th>&nbsp;</th>"
            )
            set fld_last=!fld_name!

            set /a i=!i!+1
        )
    ) >> %tmp_html%

    @rem --- dis 19.10.2020 set fld_first=!fld_first: =!
    @rem --- dis 19.10.2020 set fld_last=!fld_last: =!

    if .1.==.0. (
        @rem 22.04.2019. USE THIS ONLY FOR DEBUG! REMOVE AFTER BUG WILL BE FIXED!
        @rem HTML COMMENT: "<!--"  - can not be read and write from tmp_html to the final html report,
        @rem it will be "<--", i.e. WITHOUT EXCLAMATION sign!
        @rem ----------------------------------------------------------------------------------------
        @rem We have to output HTML-comment OUTSIDE from grouped-echo commands block!
        echo ^<^^!-- >> %tmp_html%
        (
            @rem NOTE: exclamation sign can not be written into file from HERE.
            @rem does not work: echo ^<^^!--
            @rem does not work: echo ^<^!--
            echo     Completed parsing file '%sql_log%':
            echo     -------------
            set /a i=1
            for /f "tokens=*" %%a in ('type %sql_log%') do (
                echo.    line !i! ^|%%a^|
                set /a i=!i!+1
            )
            @rem type     %sql_log%
            echo     -------------
            echo     fld_first=!fld_first!
            echo     fld_last=!fld_last!
            echo --^>
        ) >> %tmp_html%
    )


    @rem echo fld_first=.!fld_first!. fld_last=.!fld_last!. - check header of table in %tmp_html%  &pause

    (
        echo set list on;
        @rem NOTE: adding 'eol=' is mandatory because by default ';' is considered as comment and skipped by for /f.
        for /f "tokens=* eol=" %%a in ('type %sql_in%') do (
            if /i "%%a"=="set list off;" (
                echo -- disabled by %~f0, routine 'add_html_table' -- %%a
            ) else (
                echo %%a
            )
        )
        @rem type %sql_in%
    ) > %sql_temp%

    @rem echo cc1: check input file %sql_temp% &pause

    @rem ######################################
    @rem ### call isql for show report data ###
    @rem ######################################
    %fbc%\isql %dbconn% %dbauth% -i %sql_temp% 1>%sql_log% 2>%sql_err%

    for %%a in (%sql_err%) do if not %%~za lss 1 (
        echo !htm_repn! DATA PROCESSING FAULT: !htm_repc! >>%tmp_html%
        call :add_html_text sql_temp tmp_html
        call :add_html_text sql_err tmp_html 1 $css$fault$
        set sql_abend=1
    )


    if .!sql_abend!.==.1. (
        @rem ###############
        @rem ###  ABEND  ###
        @rem ###############
        goto :add_html_final
    )

    @rem Output DATA of report:
    @rem ######################
    (
      set fld_num=1
      set chart_record_elem_count=0
      for /f "tokens=*" %%a in ('type %sql_log%') do (
          set line=%%a
          set fld_name=!line:~0,31!
          call :trim fld_name !fld_name!
          if .!fld_name!.==.!fld_first!. (
              echo "<tr>"
              set fld_num=1
          )

          @rem Get SUBSTRING, starting from 32nd character: this is VALUE of cell
          @rem See above: ISQL worked in 'SET LIST ON;' mode.

          set cell=!line:~32!

          @rem NOTE: we need to replace html-specific characters: GT, LT, AMP - immediatelly,
          @rem BEFORE call trim subroutine:

          if not .!cell!.==.. (

              @rem When cell contains special html-entities like "&", "<" or ">" then it will be changed:
              @rem for proper displaying in html page: <null> becomes &lt;null&gt; etc.
              @rem But this value must be preserved when we add it to chart data array, i.e.
              @rem when we write such cell into %mp_chart_data%:
              set cbak=!cell!

              if not "!cell!"=="" (
                  @rem set left_char=!cell:~0,1!
                  set righ_char=!cell:~-1!
                  
                  @rem SPACE here:
                  if "!righ_char!"==" " set cutspaces=1

                  @rem TAB here:
                  if "!righ_char!"=="	" set cutspaces=1

                  if .!cutspaces!.==.1. (
                      set cell=!cell:^|=$PIPE$OPERATOR$!
                      set cell=!cell:%%=$PERCENT$SIGN$!
                      set cell=!cell:^&=$AMPERSAND$!
                      set cell=!cell:^>=$GREATER$THEN$!
                      set cell=!cell:^<=$LESS$THEN$!

                      @rem set cell=!cell:^&=^&amp;!
                      @rem set cell=!cell:^<=^&lt;!
                      @rem set cell=!cell:^>=^&gt;!

                      call :trim cell !cell!

                      @rem added 17.11.2020: if cell is empty then replacing will change it content to '$PIPE$OPERATOR$=' !!
                      if not .!cell!.==.. (
                          set cell=!cell:$PIPE$OPERATOR$=^|!
                          set cell=!cell:$PERCENT$SIGN$=%%!
                          set cell=!cell:^&=$AMPERSAND$!
                          set cell=!cell:$GREATER$THEN$=^>!
                          set cell=!cell:$LESS$THEN$=^<!
                      )
                  )
              )
    
              if not .!cell!.==.. (
                  set ccss=!cell:$css$error$=!

                  if not !ccss!==!cell! (
                      @rem 21.10.2020 DO NOT enclose into double quotes, use ^< and ^> here!
                      @rem Otherwise handling of such rows in :remove_enclosing_quotes -> :trim
                      @rem will produce line without part of text.
                      @rem TODO: check and try to fix this later.
                      set cell=^<span class="error"^>!ccss!^</span^>
                  ) else (
                      set ccss=!cell:$css$warning$=!
                      if not !ccss!==!cell! (
                          @rem 21.10.2020 DO NOT enclose into double quotes, use ^< and ^> here!
                          set cell=^<span class="warning"^>!ccss!^</span^>
                      ) else (
                          set ccss=!cell:$css$success$=!
                          @rem 21.10.2020 DO NOT enclose into double quotes, use ^< and ^> here!
                          if not !ccss!==!cell! set cell=^<span class="success"^>!ccss!^</span^>
                      )
                  )
              )

          ) 

          set is_num=1
          call :chk4num fld_num num_list is_num

          @rem Seems that: `findstr ,!fld_num!, %tmp_nums% 1>nul & if not errorlevel 1 (...` - is SLOWER more than 2x!

          if .!is_num!.==.1. (
              echo "<td Align=right>!cell!</td>"
          ) else (
              echo "<td>!cell!</td>"
          )

          if .!fld_name!.==.!fld_last!. (
              @rem Completed output for all columns of row, put closing tag:
              echo "</tr>"
              echo.
          )


          if exist !chart_settings! (
              set cbak=!cbak:$css$error$=!
              set cbak=!cbak:$css$warning$=!
              set cbak=!cbak:$css$success$=!
              set cbak=!cbak:$css$fault$=!

@rem echo fld_name=.!fld_name!.
@rem echo x_axis_field=.!x_axis_field!.
@rem echo cols_for_data=.!cols_for_data!.
@rem pause

              if /i .!fld_name!.==.!x_axis_field!. (

                  if /i "!cbak!"=="<null>" (
                      set chart_point_x_value=null
                  ) else if .!is_num!.==.1. (
                      @rem this column belongs to NUMERIC DATATYPE family.
                      @rem We have to write ts value 'as is', without any additions:
                      set chart_point_x_value=!cbak!
                  ) else (
                      @rem This field datatype is NOT numeric (most of all this is timestamp).
                      @rem We have to enclose its value into single quotes:
                      set chart_point_x_value='!cbak!'
                  )
                  set /a chart_record_elem_count=!chart_record_elem_count!+1
                  set chart_record_data_array=,[ !chart_point_x_value!

                  @rem echo X-axis field fld_name=!fld_name!: chart_record_data_array=!chart_record_data_array!
                  @rem echo new chart_record_elem_count=!chart_record_elem_count!

              )
              @rem result: defined X-coord of point to be shown.

              @rem DO NOT: XXX set tmpstr=!cols_for_data:'%fld_name%'=! XXX -- we have to compare strings IGNORING CASE!

              @rem Make case-INSENSITIVE search for occurence of !fld_name! in !cols_for_data!:
              @rem ~~~~~~~~~~~~~~~~~~~~~

              echo !cols_for_data! | findstr /i /c:"'!fld_name!'" >nul
              if NOT errorlevel 1 (
                  @rem List !cols_for_data! *contains* element '!fldname!'
                  @rem Example of cols_for_data: .'metadata cache memo used','memo used by attachments','memo used by transactions','memo used by statements'.
                  set /a chart_record_elem_count=!chart_record_elem_count!+1

                  if /i "!cbak!"=="<null>" (
                      set chart_point_y_value=null
                      @rem old: set chart_point_y_value=0
                  ) else (
                      set chart_point_y_value=!cbak!
                      @rem do not !cell!: it may contain html-entities for proper display in html page, e.g.: &lt;null&gt;
                  )

                  set chart_record_data_array=!chart_record_data_array!,!chart_point_y_value!
                  
                  @rem echo cols_for_data=!cols_for_data!, fld_name=!fld_name!
                  @rem echo new chart_record_data_array: !chart_record_data_array!
                  @rem echo new chart_record_elem_count=!chart_record_elem_count!

              ) else (
                  @rem echo field !fld_name! NOT from list cols_for_data=!cols_for_data!
              )

              if !chart_record_elem_count! GTR !y_charts_count! (
                  @rem .sh: $chart_record_elem_count -eq $(( y_charts_count+1 ))

                  @rem Example:
                  @rem chart_point_x_value='invoice (draft): removal'
                  @rem x_values_skip_pattern=OVERALL

                  @rem DO NOT XXX set tmpstr=!chart_point_x_value:%x_values_skip_pattern%:=! XXX -- we have to compare case INSENSITIVE

                  @rem Make case-INSENSITIVE search for occurence of !x_values_skip_pattern! in !chart_point_x_value!:
                  @rem ~~~~~~~~~~~~~~~~~~~~~
                  @rem NOTE-1: x_values_skip_pattern is always NON-empty. Default: NOTHING_TO_SKIP
                  @rem NOTE-2: we have to enclose !chart_point_x_value! into double quotes because
                  @rem it can have value 'null' and in this case "system cannot find the file specified"
                  @rem will raise when try following command:

                  echo "!chart_point_x_value!" | findstr /i /c:"!x_values_skip_pattern!" > nul

                  if not errorlevel 1 (
                     @rem === DO NOTHING === This value leads the record to be skipped from output.
                  ) else (
                     echo "        !chart_record_data_array! ]" >>!tmp_chart_data!
                  )

                  set /a chart_record_elem_count=0
                  set chart_record_data_array=
              )

          )
          @rem if exist !chart_settings!

          set /a fld_num=!fld_num!+1
      )

      echo "</table>"

    ) >>%tmp_html%

    @rem copy %tmp_html% %tmp_html%.check

    call :remove_enclosing_quotes %tmp_html%


    if exist !chart_settings! (

        @rem End of data table:
        echo "    ]);" >> !tmp_chart_data!

if .1.==.0. (
echo ooooooooooooooooooooooooooooosssssssssssssssssssssssssssssss
echo check %tmp_html%
echo check !tmp_chart_data!
echo ooooooooooooooooooooooooooooosssssssssssssssssssssssssssssss
pause
)
        
        @rem #################################
        @rem Start writing to !tmp_chart_html!
        @rem #################################

        (
            if not .!href_title!.==.. (
                echo "<h3><a name=!href_name!> !href_title! </a></h3>"
            )
            echo "<div id="!draw_func_name!_div" style="width: !chart_div_wid!px; height: !chart_div_hei!px;!div_inline_expr!"></div>"
            if .!chart_libs_reload!.==.1. (
                echo "<script type="text/javascript" src="https://www.gstatic.com/charts/loader.js"></script>"
            )
            echo "<script type="text/javascript">"
            if .!chart_libs_reload!.==.1. (
                echo "  google.charts.load('current', {'packages':['corechart']});"
            )
            echo "    // see settings here: https://developers.google.com/chart/interactive/docs/"
            echo "    google.charts.setOnLoadCallback(!draw_func_name!);"
            echo "    function !draw_func_name!() {"
            echo "        // Add data to temp html for drawing chart:"
            echo "        // ----------------------------------------"
    
            type !tmp_chart_data!

        ) >> !tmp_chart_html!


        (
            if not .!y_format_list!.==.. (
                @rem add formatting to number values
                @rem pattern: '0';   pattern: '0.00',negativeColor: 'red';   fractionDigits: 4;   etc
                set /a col_indx=1
                for /d %%f in (!y_format_list!) do (
                    @rem example: new google.visualization.NumberFormat({ pattern: '0.000' }).format(data, 1); -- format SECOND column of data array

                    echo "    new google.visualization.NumberFormat({ %%f }).format(data, !col_indx!);"
                    
                    set /a col_indx=!col_indx!+1
                )
            )
        ) >> !tmp_chart_html!


        (
            if /i .!chart_type!.==.PieChart. (
    	        echo "    var options = {"
                echo "           title: '!chart_title!',"
                @rem -- ?! -- not sure about PieChart !! -- echo "           interpolateNulls: true"
                echo "        };"
            ) else (
    	        echo "    var options = {"
                echo "        title: '!chart_title!',"
                echo "        interpolateNulls: true,"

                if not .!curve_type!.==.. (
                    echo "        curveType: '!curve_type!',"
                )
                if not .!point_size!.==.. (
                    echo "        pointSize: !point_size!,"
                )
                if not .!legpos_expr!.==.. (
                    echo "        !legpos_expr!,"
                )
                if not .!color_expr!.==.. (
                    echo "        !color_expr!,"
                )
                if not .!chart_area_options!.==.. (
                    echo "        chartArea:!chart_area_options!,"
                )
                echo "        hAxis: {"
                echo "            title: '!x_axis_title!',"
                echo "            format: '0',"
                echo "            textStyle: {"
                echo "                color: '!axis_color!',"
                echo "                bold: false,"
                echo "                italic: false,"
                echo "                fontSize: 10"
                echo "            },"
                if not .!x_axis_slanted_labels!.==.. (
                    echo "            slantedText: !x_axis_slanted_labels!"
                )
                echo "        },"
                echo "        vAxis: {"
                echo "            title: '!y_axis_title!',"
                echo "            minValue: 0,"
                if not .!y_scale_type!.==.. (
                    echo "            scaleType: '!y_scale_type!',"
                )
                echo "            textStyle: {"
                echo "                color: '!axis_color!',"
                echo "                bold: false,"
                echo "               italic: false,"
                echo "               fontSize: 10"
                echo "            }"
                echo "        }"
    	        echo "    }"
            )
            @rem chart_type == PieChart --> true /  false

            echo "        var chart = new google.visualization.!chart_type!(document.getElementById('!draw_func_name!_div'));"
            echo "        chart.draw(data, options);"
            echo "    }"
            echo "</script>"
        ) >> !tmp_chart_html!


        call :remove_enclosing_quotes !tmp_chart_html!

        if .!chart_only_show!.==.1. (
            @rem SKIP from showing html table, only chart is interested here:
            move !tmp_chart_html! !tmp_html! 1>nul
        ) else (
            @rem Show both the table and chart
            type !tmp_chart_html! >> !tmp_html!
        )

    )
    @rem if exist !chart_settings!

:add_html_final
    @rem this label is used for interruption of any further parsing/output when SQL-prepare/runtime error occurs


    @rem ########################
    type %tmp_html% >> %htm_file%
    @rem ########################

    for /d %%f in (!sql_temp!,!sql_log!,!sql_err!,!tmp_sqlda!,!tmp_nums!,!tmp_html!,!tmp_chart_html!,!tmp_chart_data!) do (
        if exist %%f del %%f
    )

    endlocal

goto:eof
@rem ^

@rem end of ':add_html_table' subroutine

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:gather_hwinfo

@rem call :gather_hwinfo %tmpdir% %log4all% %vbs_oem_converter% %make_html% %htm_file%
@rem                        1         2              3               4          5

setlocal
set tmpdir=%1
set log4all=%2
set vbs_oem_converter=%3

@rem ### OPTIONAL ### HTML file for final report, encoded in UTF8.
@rem If missed then we CREATE here new file with name=!tmpdir!\hwinfo.utf8.html, with adding all needed tags (html, head, body etc).
@rem Otherwise we only add to existing html file content of hardware info as <table>.
set outer_htm=%4
set htm_file=%5

@rem set oem2utf=%tmpdir%\oem2utf8.vbs.tmp

set lst=%tmpdir%\hwinfo.lst
set rpt=%tmpdir%\hwinfo.oem.txt
set rpu=%tmpdir%\hwinfo.utf8.txt
set rph=%tmpdir%\hwinfo.utf8.html
set tmp1=%tmpdir%\hwinfo.1.tmp
set tmp2=%tmpdir%\hwinfo.2.tmp

@rem ...............................................

set wincp=
reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v ACP 1>!tmp1! 2>!tmp2!
set /a errsize=0
for /f %%a in ("!tmp2!") do (
    set /a errsize=%%~za
)
if !errsize! EQU 0 (
    for /f "tokens=3" %%a in ('findstr /c:"ACP" !tmp1!') do (
        @rem wincp=windows-1251 etc:
        set wincp=windows-%%a
    )
    del !tmp1!
) else (
    call :sho "FAIL. Could not find Windows code page in registry." %log4all%
    call :bulksho !tmp2! %log4all%
    endlocal & goto:eof
)
del !tmp2!

@rem ...............................................

@rem Output language. English: 409; russian: 419
set lang_id=409

(
    echo os get Version,Caption,ServicePackMajorVersion,CountryCode,FreePhysicalMemory,FreeVirtualMemory,MaxProcessMemorySize,TotalSwapSpaceSize,TotalVirtualMemorySize,TotalVisibleMemorySize,LastBootupTime
    echo computersystem get Name, Manufacturer, Model, NumberofProcessors,TotalPhysicalMemory,CurrentTimeZone,SystemType
    echo baseboard get Manufacturer, Model, Name, Product, Version
    echo cpu get Name, Caption, MaxClockSpeed, DeviceID, status, NumberOfCores, NumberOfLogicalProcessors
    echo memphysical get MaxCapacity, MemoryDevices, MemoryErrorCorrection, Use
    echo diskdrive get DeviceID, InterfaceType, Name, Size, Manufacturer, Model,  MediaLoaded, MediaType, Partitions
    echo logicaldisk get caption,description,drivetype,volumename
    echo partition get BootPartition,DeviceID,DiskIndex,Name,NumberOfBlocks,Size,Type,Description
    echo pagefile get AllocatedBaseSize,Name,CurrentUsage,PeakUsage
)>!lst!

del !rpt! 2>nul
set /a i=1


for /f "tokens=*" %%f in (!lst!) do (
    if !i! GTR 1 (
        echo.>>!rpt!
    )
    for /f "tokens=1" %%g in ('echo %%f') do (
       set info_type=%%g
    )
    set run_cmd=%SystemRoot%\System32\wbem\WMIC.exe /locale:ms_!lang_id! %%f /format:list ^| more
    cmd /c "!run_cmd!" > !tmp2!
    for /f "tokens=*" %%a in (!tmp2!) do (
        set line_bak=%%a
        set line_chk=!line_bak:~0,-1!
        if NOT .!line_chk!.==.. (
            @rem echo !info_type!: !line_bak:~0,-1!
            echo !info_type!: !line_bak:~0,-1! >> !rpt!
        )
    )
    del !tmp2!
    set /a i=!i!+1
)
del !lst!

reg query "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\PriorityControl" 1>!tmp2! 2>nul

@rem    Win32PrioritySeparation    REG_DWORD    0x18 --> for background services
@rem    Win32PrioritySeparation    REG_DWORD    0x26 --> for programs
if not errorlevel 1 (
    echo.>>!rpt!
    for /f "tokens=3" %%p in ('findstr /i /c:"Win32PrioritySeparation" !tmp2!') do (
         set performance_priority=%%p
         if .!performance_priority!.==.0x18. (
             set perf_adjusting=SERVICES
         ) else if .!performance_priority!.==.0x26. (
             set perf_adjusting=PROGRAMS
         ) else if .!performance_priority!.==.0x2. (
             @rem Win 2008, adj for SERVICES:
             set perf_adjusting=SERVICES
         ) else if .!performance_priority!.==.0x0. (
             @rem   Foreground and background applications equally responsive
             set perf_adjusting=NO_ADJUSTING
         ) else (
             set perf_adjusting=UNKNOWN_VALUE_IN_REGISTRY
         )
    )
    echo PriorityControl: PerformanceAdjustedFor=!perf_adjusting! >> !rpt!
)
del !tmp2!

@rem Output power schemes. NOTE: "High performance" is highly recommended

powercfg -list | findstr /c:"GUID" > !tmp2!

echo.>>!rpt!
for /f "tokens=1* delims=:" %%a in ( !tmp2! ) do (
    set wmic_class=%%a
    set wmic_value=%%b
    for /f "tokens=1* delims= " %%u in ("!wmic_value!") do (
        set param=%%u
        set value=%%v
        set value=!value:(=!
        set value=!value:^)=!
        @rem echo !wmic_class: =_!: !param!=!value! >> !rpt!
        echo PowerScheme: !param!=!value! >> !rpt!
    )
)

del !tmp2!

if exist %vbs_oem_converter% (

    @rem Convert from OEM to Windows code page in order to add into %log4all%:
    @rem -------------------------------------
    %systemroot%\system32\cscript.exe //nologo //e:vbscript !vbs_oem_converter! !rpt! !tmp1! !wincp!

) else (

    call :sho "ATTENTION. VBS-converter from OEM codepage does not exist." %log4all%
    call :sho "Hardware and OS info is added to the final report text in OEM encoding." %log4all%
    copy !rpt! !tmp1!

)

(
    for /f "tokens=*" %%u in (!tmp1!) do (
        echo.    %%u
    )
) >> %log4all%


echo.>> %log4all%

del !tmp1!

@rem result: file !rpt! has been encoded in OEM codepage. We have to convert it to UTF8 without BOM.
@rem 1) do NOT use powershell -c "Get-Content wmic-comp-utf16.txt | Set-Content -Encoding utf8 wmic-comp-utf8.txt"
@rem    because it creates file with BOM.
@rem 2) do NOT use powershell -file <....ps1> because it requires additional permission for executing scripts:
@rem File <...> cannot be loaded because running scripts is disabled on this system <...> see about_Execution_Policies 
@rem at http://go.microsoft.com/fwlink/?LinkID=135170.
@rem     + CategoryInfo          : SecurityError: (:) [], ParentContainsErrorRecordException
@rem     + FullyQualifiedErrorId : UnauthorizedAccess

if exist %vbs_oem_converter% (

    @rem Convert from OEM to UTF-8 in order to add into HTML report
    @rem -------------------------
    %systemroot%\system32\cscript.exe //nologo //e:vbscript !vbs_oem_converter! !rpt! !rpu! UTF-8

) else (
    call :sho "ATTENTION. VBS-converter from OEM codepage does not exist." %log4all%
    call :sho "Hardware and OS info is added to HTML report in OEM encoding." %log4all%
    copy !rpt! !rpu!
)

del !rph! 2>nul

set tro=^<tr^>
set trc=^</tr^>
set tdo=^<td^>
set tdc=^</td^>

if .%outer_htm%.==.0. (
    (
        echo ^<html^>
        echo ^<head^>
        echo ^<meta http-equiv="content-type" content="text/html; charset=utf-8" /^>
        echo ^<meta http-equiv="cache-control" content="no-cache"^>
        echo ^<meta http-equiv="pragma" content="no-cache"^>
        echo ^<style type="text/css"^>
        echo     table {
        echo         border-collapse: collapse;
        echo         background: #99CCFF;
        echo         border: 2px solid black;
        echo     }
        echo     th {
        echo         padding: 5px; 
        echo         background: #E6E6FA;
        echo         border: 1px solid black;
        echo     }
        echo     td {
        echo         padding: 4px;
        echo         background: #FDF5E6;
        echo         border: 1px solid black;
        echo         white-space:nowrap;
        echo     }
        echo ^</style^>
        echo ^</head^>
        echo ^<body^>
        echo ^<table^>
    ) >> !rph!
) else (
    echo ^<table class="t_table"^>  >> !rph!
)

set wmic_clbak=UNKNOWN
(
    set /a i=1
    for /f "tokens=1* delims=:" %%a in ('findstr /c:":" !rpu!') do (
        if !i! GEQ 1 (
            set wmic_class=%%a
            set wmic_value=%%b
            @rem echo wmic_class=!wmic_class!
            @rem echo wmic_value=!wmic_value!
            echo !tro!
            if NOT .!wmic_class!.==.!wmic_clbak!. (
                echo !tro! ^<th colspan="2"^> !wmic_class! !tdc! !trc!
                set wmic_clbak=!wmic_class!
            )
            echo !tro!
            for /f "tokens=1* delims==" %%u in ("!wmic_value!") do (
                set param=%%u
                set value=%%v
                echo !tdo! !param! !tdc! !tdo! !value! !tdc!
            )
            echo !trc!
        )
        set /a i=!i!+1
    )
) >> !rph!

if .%outer_htm%.==.0. (
    (
        echo ^</table^>
        echo ^</body^>
        echo ^</html^>
    ) >> !rph!
) else (
    echo ^</table^> >> !rph!
    
    type !rph! >> !htm_file!

)

set lst=%tmpdir%\hwinfo.lst
set rpt=%tmpdir%\hwinfo.oem.txt
set rpu=%tmpdir%\hwinfo.utf8.txt
set rph=%tmpdir%\hwinfo.utf8.html
set tmp1=%tmpdir%\hwinfo.1.tmp
set tmp2=%tmpdir%\hwinfo.2.tmp

for /d %%x in (!lst!,!rpt!,!rpu!,!rph!,!tmp1!,!tmp2!) do (
    if exist %%x del %%x
)

endlocal
goto:eof

@rem ^
@rem end of 'gather_hwinfo' subroutine


@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:create_oemcp_converter

@rem call :gather_hwinfo %tmpdir% %log4all% %htm_file%
setlocal

set tmpdir=%1
set log4all=%2
set oem_vbs_converter=%3

@rem set oem_vbs_converter=%tmpdir%\oem_converter.vbs.tmp

set tmp1=%tmpdir%\hwinfo.1.tmp
set tmp2=%tmpdir%\hwinfo.2.tmp
@rem Output language. English: 409; russian: 419
set lang_id=409

set oemcp=
reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v OEMCP 1>!tmp1! 2>!tmp2!
set /a errsize=0
for /f %%a in ("!tmp2!") do (
    set /a errsize=%%~za
)
if !errsize! EQU 0 (
    for /f "tokens=3" %%a in ('findstr /c:"OEMCP" !tmp1!') do (
        @rem oemcp=cp866 etc:
        set oemcp=cp%%a
    )
    del !tmp1!
) else (
    call :sho "FAIL. Could not find OEM code page in registry." %log4all%
    call :bulksho !tmp2! %log4all%
    endlocal & goto:eof
)


@rem https://en.wikipedia.org/wiki/Windows_code_page#DOS_code_pages
@rem 437 - IBM PC US, 8-bit SBCS extended ASCII. Known as OEM-US
@rem 708 - Arabic, extended ISO 8859-6 (ASMO 708)
@rem 720 - Arabic, retaining box drawing characters in their usual locations
@rem 737 - "MS-DOS Greek". Retains all box drawing characters. More popular than 869.
@rem 775 - "MS-DOS Baltic Rim"
@rem 850 - "MS-DOS Latin 1". Full (re-arranged) repertoire of ISO 8859-1; aka DOS Latin 1
@rem 852 - "MS-DOS Latin 2"
@rem 855 - "MS-DOS Cyrillic", for South Slavic languages. Not to be confused with cp866.
@rem 857 - "MS-DOS Turkish"
@rem 858 - Western European with euro sign
@rem 860 - "MS-DOS Portuguese"
@rem 861 - "MS-DOS Icelandic"
@rem 862 - "MS-DOS Hebrew"
@rem 863 - "MS-DOS French Canada"
@rem 864 - Arabic
@rem 865 - "MS-DOS Nordic"
@rem 866 - "Cyrillic (DOS)", cp866.
@rem 869 - "MS-DOS Greek 2", IBM869. Full (re-arranged) repertoire of ISO 8859-7.
@rem 874 - Thai, also used as the ANSI code page, extends ISO 8859-11

(

    echo ' http://forum.script-coding.com/viewtopic.php?id=997
    echo ' https://stackoverflow.com/questions/31435662/vba-save-a-file-with-utf-8-without-bom/31436631#31436631
    echo ' Usage: %systemroot%\system32\cscript.exe //nologo //e:vbscript !oem_vbs_converter! ^<input-file-in-OEM-codepage^> ^<output-file^> ^<codepage-for-output-file^>
    echo ' Examples:
    echo '     cscript //nologo //e:vbscript !oem_vbs_converter! hwinfo.oem.txt tmp.utf8.tmp utf-8
    echo '     cscript //nologo //e:vbscript !oem_vbs_converter! hwinfo.oem.txt tmp.1251.tmp windows-1251
    echo ' To obtain id of OEM and Windows codepage one can use:
    echo '     reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v OEMCP | findstr /c:"OEMCP"
    echo '     reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v ACP | findstr /c:"ACP"
    echo.
    echo set objArgs = WScript.Arguments
    echo sourFile = objArgs(0^)
    echo targFile = objArgs(1^)
    echo targCset = objArgs(2^) ' charset for encoding new file: UTF-8, Windows-1251 etc
    echo.
    echo Const adTypeBinary = 1
    echo Const adTypeText   = 2
    echo Const adSaveCreateOverWrite = 2
    echo.
    echo Dim objStreamSource : Set objStreamSource = CreateObject("ADODB.Stream"^)
    echo Dim objStreamTarget : Set objStreamTarget = CreateObject("ADODB.Stream"^)
    echo.
    echo with objStreamSource
    echo     .Type = adTypeText
    echo.
    echo     ' .Charset was substituted here at runtime after parsing result of command:
    echo     ' reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v OEMCP
    echo     .Charset = "!oemcp!"
    echo.
    echo     .Open(^)
    echo     .LoadFromFile( sourFile ^)
    echo     Text = .ReadText(^)
    echo     .Close(^)
    echo.
    echo     .Open(^)
    echo     .Charset = targCset ' e.g. "UTF-8", "windows-1251" etc
    echo     .WriteText(Text^) ' NOTE: when target encoding is UTF-8 then file will contain unicode BOM in first three bytes 
    echo    .Position = 0
    echo    if UCase( targCset ^) = UCase( "UTF-8" ^) then
    echo        .Position = 3 ' we have to SKIP writing BOM into target UTF-8 file
    echo    end if
    echo end with
    echo.
    echo With objStreamTarget
    echo   .Type    = adTypeBinary
    echo   .Open
    echo   objStreamSource.CopyTo objStreamTarget
    echo   .SaveToFile targFile, adSaveCreateOverWrite
    echo End With
    echo.
    echo objStreamSource.close
    echo objStreamTarget.Close

) > !oem_vbs_converter!

endlocal
goto:eof
@rem ^
@rem end of 'create_oemcp_converter' subroutine


@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:dequote_string

    setlocal

    set src_list=%1

    set left_char=!src_list:~0,1!
    set righ_char=!src_list:~-1!

    set result=src_list
    @rem Remove enclosing double quotes from !src_list!:
    set chksym=!left_char:"=!
    if .!chksym!.==.. (
       set chksym=!righ_char:"=!
       if .!chksym!.==.. (
          set result=!src_list:~1,-1!
       )
    )
    endlocal & set "%~2=%result%"

goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:trim
    setLocal

    @rem 22.10.2020: we have to enclose assignment of Params into double quotes.
    @rem Otherwise caret will be duplicated here, i.e.
    @rem when call this routine with string like: "set term ^;"
    @rem then output will be: "set term ^^;"
    set "Params=%*"

    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

@rem +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-

:remove_enclosing_quotes

    setlocal

    @rem 17.10.2020. "Dequotes" each line from input file:
    @rem 22.10.2020. We have to replace all occurences of "<" and "<" with some plain text like this is done in HTML-escaping.
    @rem Otherwise :trim subroutine will fail to handle such rows :(

    set input_file=%1
    for /f %%a in ("!input_file!") do (
        set tmp_output=%%~dpna.dequote_lines.tmp
        if exist !tmp_output! del !tmp_output!
    )
    for /f "tokens=*" %%a in (!input_file!) do (
        set val=%%a
@rem echo init val=.!val!.
        set left_char=!val:~0,1!
        set righ_char=!val:~-1!

@rem echo left_char=.!left_char!.  righ_char=.!righ_char!.

        if "!left_char!"==" " set cutspaces=1
        if "!left_char!"=="	" set cutspaces=1
        if "!righ_char!"==" " set cutspaces=1
        if "!righ_char!"=="	" set cutspaces=1

@rem echo cutspaces=!cutspaces!

        if .!cutspaces!.==.1. (
            set val=!val:^|=$PIPE$OPERATOR$!
            set val=!val:^&=$AMPERSAND$!
            set val=!val:%%=$PERCENT$SIGN$!
            set val=!val:^>=$GREATER$THEN$!
            set val=!val:^<=$LESS$THEN$!

@rem echo befo trim: val=.!val!.

            call :trim val !val!

@rem echo afte trim: val=.!val!.

            for /f "useback tokens=*" %%x in ('!val!') do (
                    set val=%%~x
            )
            set val=!val:$GREATER$THEN$=^>!
            set val=!val:$LESS$THEN$=^<!
            set val=!val:$PIPE$OPERATOR$=^|!
            set val=!val:$AMPERSAND$=^&!
            set val=!val:$PERCENT$SIGN$=%%!

@rem echo afte repl: val=.!val!.

        ) else (
            for /f "useback tokens=*" %%x in ('!val!') do (
                    set val=%%~x
            )

@rem echo w/o trim: val=.!val!.

        )
        echo !val!>>!tmp_output!
    )
    move !tmp_output! !input_file! 1>nul

goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:chk4num
    setlocal
    set num_chk=,!%1!,
    set num_lst=!%2!
    set result=1
    if "!num_lst:%num_chk%=!"=="%num_lst%" set result=0
    endlocal & set "%~3=%result%"
goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:timediff

  @rem Takes three arguments: time1, time2 and placeholder for storing difference from time1 to time2 in milliseconds.
  @rem Sample:
  @rem set t1=%time%
  @rem . . .
  @rem set t2=%time%
  @rem set tdiff=0
  @rem call :timediff "%t1%" "%t2%" tdiff

  setlocal

  @rem Add '0' to value of hours, otherwise can not calculate expressions with modulo:
  for /f "delims= " %%x in ("%~1") do set t1=0%%x
  for /f "delims= " %%x in ("%~2") do set t2=0%%x
  @rem Evaluate seconds from midnight. Need doing this using modulo, otherwise get arith.
  @rem runtime error when number of hours/minutes/seconds is 8 or 9, i.e.:  8:08:09.01 or 9:09:09.01 etc.

  for /f "tokens=1-8 delims=:.," %%a in ("!t1!:!t2!") do (
    set /a t1s=(100%%a %% 100^) * 3600000 + (100%%b %% 100^) * 60000 + (100%%c %% 100^) * 1000 + (100%%d %% 100^) * 10
    set /a t2s=(100%%e %% 100^) * 3600000 + (100%%f %% 100^) * 60000 + (100%%g %% 100^) * 1000 + (100%%h %% 100^) * 10
  )
  set /a tdiff=!t2s! - !t1s!
  if .!t2s!. LSS .!t1s!. (
      set /a tdiff=!tdiff!+86400000
  )

  endlocal&set "%~3=%tdiff%"
goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:sho
    setlocal
    set msg=%1
    set msg=!msg:`="!
    set log=%2
    if .!log!.==.. (
        echo Internal func sho: missed argument for log file.
        @rem ::: 25.06.2018 do NOT use here reference to  %1, use here
        @rem ::: only variable that stores its value: !msg!
        @rem ::: Execution control can jump here even for correct
        @rem ::: input msg if it contains closing parenthesis ")"
        echo Arg. #1 = ^|!msg!^|
        goto fin
    ) 

    set left_char=!msg:~0,1!
    set righ_char=!msg:~-1!

    @rem REMOVE LEADING AND TRAILING DOUBLE QUOTES:
    @rem ##########################################
    set result=!left_char:"=!
    if .!result!.==.. (
       set result=!righ_char:"=!
       if .!result!.==.. (
          set msg=!msg:~1,-1!
       )
    )

    set dts=!time!
    set dts=!dts: =!
    set dts=10!dts:,=.!
    set dts=!dts:~-11!
    set msg=!dts!. !msg!
    echo !msg!
    echo !msg!>>!log!

endlocal & goto:eof

@rem +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:bulksho
    setlocal
    set tmplog=%1
    set joblog=%2
    set keep_tmp=%3

    set dts=!time!
    set dts=!dts: =!
    set dts=10!dts:,=.!
    set dts=!dts:~-11!

    for /f "tokens=*" %%a in (!tmplog!) do (
       set msg=%%a

       @rem Remove enclosing double quotes (if needed):
       set left_char=!msg:~0,1!
       set righ_char=!msg:~-1!
       set chksym=!left_char:"=!
       if .!chksym!.==.. (
          set chksym=!righ_char:"=!
          if .!chksym!.==.. (
             set msg=!msg:~1,-1!
          )
       )

       set msg=!dts!. !msg!
       echo !msg!
       echo !msg!>>!joblog!
    )
    if not .!keep_tmp!.==.1. (
        del !tmplog!
    )
endlocal & goto:eof

@rem +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:getRandom
    setlocal

    @rem call :getRandom gen_vbs --> for generating .vbs in tmpdir
    @rem call :getRandom get_rnd %sid% 0 100 rand_delay --> for assign random integer, from 0 to 100, to variable rand_delay that was defined before

    set mode=%1
    set sid=%2
    set from_min=%3
    set upto_max=%4
    @rem set vb4sid_file=!tmpdir!\sql\getRandomInt.vbs.%sid%.tmp
    @rem set result_file=!tmpdir!\sql\getRandomInt.dat.%sid%.tmp
    set vb4sid_file=!tmpdir!\sql\tmp_sid_%sid%_rndInt.vbs.tmp
    set result_file=!tmpdir!\sql\tmp_sid_%sid%_rndInt.dat.tmp

    if /i .!mode!.==.gen_vbs. (
        if exist %vb4sid_file% del %vb4sid_file%
        (
            echo ' Generated auto by %~f0, do NOT edit.
            echo ' Used to get random value within scope of two integers.
            echo ' Usage: %systemroot%\system32\cscript.exe ^/^/nologo ^/^/e:vbscript %vb4sid_file% ^<from_minimal^> ^<upto_maximal^>
            echo ' Result: random value within scope, cast as integer.
            echo dim min,max
            echo min=WScript.Arguments.Item(0^)
            echo max=WScript.Arguments.Item(1^)
            echo Randomize
            echo WScript.Echo int( min + (max-min+1^) * Rnd ^)
        )>>%vb4sid_file%

        endlocal & goto:eof

    ) else if /i .!mode!.==.get_rnd. (
        
        if .1.==.1. (
            %systemroot%\system32\cscript.exe //nologo //e:vbscript %vb4sid_file% %from_min% %upto_max% >%result_file%
            endlocal & set /p %~5=<%result_file%
            del /q %result_file%
        )

        if .1.==.0. (
            @rem does NOT work:
            @rem ==============
            set run_cmd=%systemroot%\system32\cscript.exe //nologo %vb4sid_file% %from_min% %upto_max%
            for /f %%a in ('cmd /c !run_cmd!') do (
               set %~5=%%a
            )
        )

    ) else if /i .!mode!.==.del_vbs. (
        if exist %vb4sid_file% del %vb4sid_file%
    )
    endlocal

goto:eof
@rem ^
@rem end of 'getRandom' subroutine

@rem +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:catch_err
    
    setlocal

    @rem Sample:
    @rem set run_cmd=!fbsvcrun! info_server_version
    @rem !run_cmd! 1>%tmplog% 2>%tmperr%
    @rem call :catch_err run_cmd !tmperr! n/a nofbvers
    @rem call :catch_err run_isql !tmperr! !tmpchk! db_not_ready 0
    @rem call :catch_err run_isql !tmperr! !tmpsql! db_cant_write 1

    set runcmd=!%1!
    set err_file=%2
    set sql_file=%3
    set add_label=%4
    set do_abend=%5
    if .%5.==.. set do_abend=1

    @rem set cmdlog=%tmpdir%\%~n0_last_cmd.log
    @rem call :repl_with_bound_quotes %cmdlog% cmdlog

    for /f "delims=" %%a in (!cmdlog!) do set cmd_run=%%a

    for /f "usebackq tokens=*" %%a in ('%err_file%') do set size=%%~za
    if .!size!.==.. set size=0
    if !size! gtr 0 (
        echo.
        echo ### ATTENTION ###
        echo.
        if not .%add_label%.==.. (
          if /i not .%add_label%.==.n/a. (
              call :!add_label!
          )
        )
        echo.
        echo Command: !runcmd!
        echo.
        if /i not .!sql_file!.==.n/a. (
            echo SQL script: %sql_file%
        )
        echo Content of error log (%err_file%^):
        echo ^=^=^=^=^=^=^=
        type %err_file%
        echo ^=^=^=^=^=^=^=

        if .!do_abend!.==.1. (
            if .%can_stop%.==.1. (
                echo.
                echo Press any key to FINISH this batch. . .
                pause>nul
            )
            goto fin
        )
    )
    endlocal
goto:eof

@rem +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-

:fin
@rem do NOT remove this exit command otherwise all cmd worker windows stay opened:

EXIT
