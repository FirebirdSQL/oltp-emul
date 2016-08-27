@echo off
setlocal enabledelayedexpansion enableextensions
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
rem oltp_isql_run_worker.bat %%i %fb% tmpdir sql log4all %logbase%-!k:~1,3!  

set sid=%1
set winq=%2
set fb=%3
set tmpdir=!%4!
set sql=!%5!
set log4all=!%6!
set lognm=!tmpdir!\%7
set build=%8

@rem fname = value of config parameter file_name_with_test_params: regular | benchmark
set fname=%9

rem %tmpdir%\oltpNN.report.txt - name of file for overall performance report
rem (do NOT overwrite it here, it has already some info that was added there in 1run*.bat):

if not .%3.==.25. if not .%3.==.30. if not .%3.==.40. (
  echo.
  echo This batch must be called from 1run_oltp_emul.bat 
  echo #################################################
  echo.
  pause
  goto fin
)

@rem -- echo sid=%sid%
@rem -- echo winq=%winq%
@rem -- echo fb=%fb%
@rem -- echo tmpdir=%tmpdir%
@rem -- echo sql=%sql%
@rem -- echo log4all=%log4all%
@rem -- echo lognm=%lognm%
@rem -- echo on
@rem -- dir %sql%
@rem -- dir %log4all%

@rem log where current acitvity of this ISQL will be:
set log=%lognm%.log

@rem where ERRORS will be for this ISQL:
set err=%lognm%.err

@rem Aux file for some messages
set tmp=%lognm%.tmp

@rem Cumulative log with brief info about running process state:
set sts=%lognm%.running_state.txt

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
  set msg=Trying to remove FILE %%i
  echo !msg!
  echo !msg!>>%sts%
  del /q /s %%i 1>>%sts% 2>&1

  set msg=Trying to remove DIR %%i
  echo !msg!
  echo !msg!>>%sts%
  rd /q /s %%i 1>>%sts% 2>&1
)


@rem Only for 3.0: we can get content of firebird.log before and after test
@rem and compare them:

set fblog_begnm=oltp%fb%_fb_log_when_test_started.log
set fblog_endnm=oltp%fb%_fb_log_when_test_finished.log
set fblog_start=!tmpdir!\%fblog_begnm%
set fblog_final=!tmpdir!\%fblog_endnm%

call :repl_with_bound_quotes %fblog_start% fblog_start
call :repl_with_bound_quotes %fblog_final% fblog_final

for %%i in ("%sql%") do (
  set trace_lst=%%~dpitmp_trace.lst
  set trace_sql=%%~dpitmp_trace.sql
  set trace_log=%%~dpitmp_trace.log
  set trace_cfg=%%~dpitmp_trace.conf
  set trace_run=%%~dpitmp_run1t.sql
  set trace_prs=%%~dpitmp_parse.log
  set trace_sav=%%~dpitmp_tsave.sql
)

if .%is_embed%.==.1. (
    set dbauth=
    set dbconn=%dbnm%
) else (
    set dbauth=-user %usr% -password %pwd%
    set dbconn=%host%/%port%:%dbnm%
)

set run_isql=%fbc%\isql %dbconn% -now -q -n -pag 9999 -i %sql% %dbauth% 

echo.>>%sts%
echo %date% %time%, batch running now: %~f0 - check start command: >>%sts%
echo --- beg of command for launch isql --->>%sts%
echo !run_isql!>>%sts%
echo --- end of command for launch isql --->>%sts%
echo.>>%sts%
echo sid=%sid%

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
set run_fc_compare=fc.exe /n %fblog_start% %fblog_final%

if .%sid%.==.1. (

    if .%trc_unit_perf%.==.1. (

        set msg=1st launching ISQL starts and stops TRACE before and after each packet - see config 'trc_unit_perf' parameter.
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
                echo select 'database=(%%[\\/]!dbfx!^|!dbfn!^)^' from rdb$database union all
                echo select '{'  from rdb$database union all
                echo select '    enabled = true' from rdb$database union all
                echo select '    time_threshold = 0' from rdb$database union all
                @rem echo select '    include_filter = ''%%!traced_units:^^=!%%''' from rdb$database union all
                echo select '    include_filter = %%(from sp_^|from srv_^)%%' from rdb$database union all
                echo select '    exclude_filter = %%(execute block^)%%' from rdb$database union all
                echo select '    log_statement_finish = true' from rdb$database union all
                echo select '    print_perf = true' from rdb$database union all
                echo select '    max_sql_length = 16384' from rdb$database union all
                echo select '    connection_id='^|^|current_connection from rdb$database union all
                echo select '}' from rdb$database;
                echo out;
                
                @rem echo shell echo database=(%%[\\/]!dbfx!^^^^^|!dbfn!^^^^^)^>%trace_cfg%;
                @rem echo shell echo { ^>^>%trace_cfg%;
                @rem echo shell echo     enabled=true^>^>%trace_cfg%;
                @rem echo shell echo     time_threshold=0 ^>^>%trace_cfg%;
                @rem echo shell echo     include_filter = %%(!traced_units!^)%%^>^>%trace_cfg%;
                @rem echo shell echo     log_statement_finish = true^>^>%trace_cfg%;
                @rem echo shell echo     print_perf = true^>^>%trace_cfg%;
                @rem echo shell echo     max_sql_length = 16384^>^>%trace_cfg%;
                @rem echo out %trace_cfg%;
                @rem echo set heading off;
                @rem echo select '    connection_id='^|^|current_connection from rdb$database;
                @rem echo out;
                @rem echo shell echo }^>^>%trace_cfg%;
            )
            echo shell start /min cmd /c "%fbsvcrun% action_trace_start trc_cfg %trace_cfg% 1>%trace_log% 2>&1";
        ) > %trace_sql%

        (
            echo in %trace_sql%;
            echo in %sql%;
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

    set msg=Gathering firebird.log before opening 1st window for obtaining new text which will appear in it during test.
    echo !msg!
    echo !msg!>>%log4all%

    echo %time%. Run: %run_get_fb_log% 1^>%fblog_start% 2^>%err%  >>%log4tmp%

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
  
    echo %date% %time%. Preparing for test finished. Now launch ISQL sessions. >>%log4tmp%

)

@set k=0
@echo off

set initdelay=1
if not .%winq%.==.1. if .%initdelay%.==.. (
   set /a initdelay = 2 + (%random% %% 8^)
)

set msg=Take initial sleep %initdelay% seconds to start ISQLs at different moments. . .
echo %msg%>>%sts%
echo %msg%
echo Delay at: %date% %time%>>%sts%

@rem echo ################# REMOVE DEBUG COMMENT ########################
ping -n %initdelay% 127.0.0.1 >nul

set msg=Start ISQL #%sid% of total %winq% at: %date% %time%

echo %msg% >>%sts%

if .%sid%.==.1. (
  echo.>>%log4all%
  echo %date% %time%. Now wait for all ISQL sessions will finish their job. After this, ISQL session #1 will continue writing final report here.>>%log4all%
  echo.>>%log4all%
)

:start
    @rem for /f "usebackq" %%A in ('%log%') do set size=%%~zA
    for /f "usebackq tokens=*" %%a in ('%log%') do set size=%%~za
    if .%size%.==.. set size=0
    echo size of %log% = %size%
    if %size% gtr %maxlog% (

        @rem ---------------------------------------------------------------------------------
        @rem Saving estimated performance counters that have been evaluated on each iteration
        @rem of current ISQL session before every call of business action - see .sql script:
        @rem ---------------------------------------------------------------------------------
        
        call :save_perf_estimated log sts rpt fbc dbconn dbauth

        echo %date% %time% size of log %log% = %size% - exceeds limit %maxlog%, make it EMPTY.>> %sts%
        del %log%
    )

    @rem for /f "usebackq" %%A in ('%err%') do set size=%%~zA
    for /f "usebackq tokens=*" %%a in ('%err%') do set size=%%~za
    if .%size%.==.. set size=0
    echo size of %err% = %size%
    if %size% gtr %maxerr% (
        echo %date% %time% size of %err% = %size% - exceeds limit %maxerr%, remove it >> %sts%
        del %err%
    )

    @set /a k=k+1

    echo ------------------------------------------
    (
        echo.
        echo %date% %time%. Starting packet # %k%.
        echo RUNCMD: %run_isql%
        echo STDLOG: %log% 
        echo STDERR: %err%
        echo.
    ) >%tmp%
    type %tmp%
    type %tmp% >> %log%
    type %tmp% >> %sts%
    del %tmp%
    echo ------------------------------------------
    echo WAIT for ISQL will finish current packet...

    @rem #############################    R U N     I S Q L    ##############################
    if .%use_mtee%.==.1. (
        %run_isql% 2>&1 1>>%log% | mtee /t /+ %err% >nul
    ) else (
        %run_isql% 1>>%log% 2>>%err%
    )
    @rem ####################################################################################

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

        set msg=!time!. Stop trace session that was launched for ISQL #1 
        echo !msg!
        echo !msg!>>%sts%


        %fbsvcrun% action_trace_list >!trace_lst! 2>&1
        type !trace_lst!>>%sts%


        for /f "tokens=1-3" %%a in ('findstr /i /c:"Session ID:" !trace_lst!') do (
            set run_repo=%fbsvcrun% action_trace_stop trc_id %%c
            echo !run_repo!
            echo !run_repo! >>%sts%
            cmd /c "!run_repo!" 1>>%sts% 2>&1
        )
        ping -n 2 127.0.0.1>nul
        
        set msg=!time!. Check that currently NO active trace sessions is running:
        echo !msg!
        echo !msg!>>%sts%
        echo ---- list begin ----->>%sts%
        %fbsvcrun% action_trace_list >>%sts% 2>&1
        echo ---- list finish ---->>%sts%
        del !trace_lst!
    )

    set msg=%date% %time%. Finished packet # %k%.
    echo %msg%
    echo %msg% >> %log%
    echo %msg% >> %sts%

    if .%sid%.==.1. if .%trc_unit_perf%.==.1. (

      @rem Now we have to parse trace log and extract from it name of business action, whether result was successful and statistics.

      set msg=!time!. Parsing trace log: obtaining name of units, results of execution and statistics.
      echo !msg!
      echo !msg!>>%sts%
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

      set msg=!time!. Saving parsed info from trace to database.
      echo !msg!
      echo !msg!>>%sts%

      set run_repo=%fbc%\isql %dbconn% -nod -n -i %trace_sav% %dbauth% 
      cmd /c !run_repo! 1>>%sts% 2>&1
      set msg=!time!. Done.
      echo !msg!
      echo !msg!>>%sts%

      del %trace_prs% 2>nul
      del %trace_sav% 2>nul
      del %trace_log% 2>nul
      del %trace_cfg% 2>nul

    )
    @rem end of "if .%sid%.==.1. if .%trc_unit_perf%.==.1."

    @rem ------------------------------------------------
    @rem c h e c k    n u m b e r    o f    c r a s h e s
    @rem ------------------------------------------------

    @rem 27.05.2016 Check whether server crashed during this round:
    @rem count number of lines 'error reading / writing from/to connection'
    @rem in the %err% file. If this number exceeds config parameter then
    @rem we TERMINATE further execution of test.

    set crash_msg1="SQLSTATE = 08006"
    set crash_msg2="SQLSTATE = 08003"

    findstr /i /c:!crash_msg1! /c:!crash_msg2! %err% | find /i /c "SQLSTATE" >%tmp%

    @rem set crash_msg1="Elapsed time"
    @rem findstr /i /c:!crash_msg1! %log% | find /i /c !crash_msg1! >%tmp%

    for /f "delims=" %%x in (%tmp%) do set /a crashes_cnt=%%x
    if !crashes_cnt! gtr 5 (
        (
          echo !time!. FB crashed during last run !crashes_cnt! times.
          echo Error log contain  !crashes_cnt! message(s^) with phrase !crash_msg1! or !crash_msg2!
          echo Number of this messages exceeds configurable limit.
          echo Details see in file: %err%
          echo.
        ) >%tmp%
        type %tmp%
        type %tmp%>>%sts%
        goto fb_lot_of_crashes
    ) else (
        if !crashes_cnt! equ 0 (
            set msg=!time!. There were NO connection problems during last run. Test will be continued.
        ) else (
            set msg=!time!. Detected !crashes_cnt! problems with connection. It's less than configurable limit. Test will be continued.
        )
        echo !msg!
        echo !msg!>>%sts%
    )

    @rem -------------------------------------------------------------
    @rem c h e c k    i f    s e r v e r   i s   u n a v a i l a b l e
    @rem -------------------------------------------------------------
    echo !date! !time! Check whether Firebird server is still in work >>%log%
    
    %run_get_fb_ver% 1>%tmp% 2>&1

    findstr /m /i /c:"server version" %tmp% >nul

    if not errorlevel 1 (
        echo OK, Firebird is active:>>%log%
        type %tmp%>>%log%
        type %tmp%>>%sts%
        del %tmp% 2>nul
        goto chk4shutdown
    ) else (
        echo Firebird is UNAVAILABLE.>>%log%
        type %tmp%>>%log%
        type %tmp%>>%sts%
        del %tmp% 2>nul
        goto fb_unavail
    )

:chk4shutdown
    @rem ------------------------------------------------------------------------------
    @rem c h e c k    i f    d a t a b a s e   h a s    b e e n    s h u t d o w n e d:
    @rem ------------------------------------------------------------------------------
    (
      echo !date! !time! Check whether database state is shutdown.
      echo Command: %run_get_db_hdr%
    )>>%sts%

    %run_get_db_hdr% | findstr /i /c:"Attributes" 1>%tmp% 2>&1
    @rem Attributes              full shutdown

    findstr /i /c:"shutdown" %tmp% >nul
    if errorlevel 1 goto db_online
    goto db_offline


:db_online
    @echo database ONLINE, continue the job - check test cancellation string in %err%
    @rem ------------------------------------------------------------------
    @rem c h e c k    i f    t e s t   h a s   b e e n    C A N C E L L E D:
    @rem ------------------------------------------------------------------
    echo !date! !time! Check whether test has been stopped >>%sts%

    @rem 30.05.2016, suggestion by Alexey Kovyazin: let's check first of all STDOUT log
    @rem for the signal about test cancellation. This allow to skip raising EXCEPTION inside
    @rem %tmpdir%\sql\tmp_random_run.sql script, see generation of EB code with raising
    @rem exception ex_test_cancellation.

    findstr /m /i "TEST_WAS_CANCELLED" %log% >nul
    if not errorlevel 1 (
        echo !time! Found sign of TEST CANCELLATION in STDOUT log, file %log% >>%sts%
        goto test_canc
    )

    @rem Old way: check only ERROR log for message about test cancellation:
    findstr /m /i "EX_TEST_CANCEL" %err% >nul
    if not errorlevel 1  (
        echo !time! Found sign of TEST CANCELLATION in STDERR log, file %err% >>%sts%
        goto test_canc
    )

    echo Test can be continued. Now we make loop and run ISQL with next packet.>>%sts%

    @rem ############################################
    @REM ########                            ########
    @rem ########   G O T O     S T A R T    ########
    @REM ########                            ########
    @rem ############################################
    goto start

:fb_unavail
    set msg=Firebird Server is unavailable now. Test has been cancelled.
    @echo.
    @echo %date% %time% %msg%
    @echo.
    @echo %date% %time% %msg% >>%sts%
    goto end

:fb_lot_of_crashes
    set msg=Too many messages about connection problem during this test. Test has been cancelled.
    @echo.
    @echo %date% %time% %msg%
    @echo.
    @echo %date% %time% %msg% >>%sts%
    goto end

:db_offline
    set msg=DATABASE SHUTDOWN DETECTED, test has been cancelled.
    @echo.
    @echo %date% %time% %msg%
    @echo.
    @echo %date% %time% %msg% >>%sts%
    goto end
:test_canc

    set htm_file=!tmpdir!\oltp%fb%.report.html
    del %htm_file% 2>nul

    set htm_sect=^<h3^>
    set htm_secc=^</h3^>

    set htm_repn=^<h4^>
    set htm_repc=^</h4^>

    set tmp_file=!tmpdir!\oltp%fb%.report.tmp

    set msg=!date! !time!. Test has been CANCELLED.

    echo.
    echo !msg!
    echo !msg! >>%log%
    echo !msg! >>%sts%
    echo.

    @rem ---------------------------------------------------------------------------------
    @rem Saving estimated performance counters that have been evaluated on each iteration
    @rem of current ISQL session before every call of business action - see .sql script:
    @rem ---------------------------------------------------------------------------------

    call :save_perf_estimated log sts rpt fbc dbconn dbauth


    if not .%sid%.==.1. (
        @rem ---------------------------------------------------------------------------------------------------------------
        @rem E X I T    i f   c u r r e n t    I S Q L    w i n d o w   h a s   n u m b e r   g r e a t e r   t h a n   "1".
        @rem ---------------------------------------------------------------------------------------------------------------
        set msg=!date! !time!. Session %sid% is now finishing its work: exit from batch.
        echo !msg!
        echo !msg! >>%log%
        echo !msg! >>%sts%
        goto end
    )
    
    @rem All other attachment have to be FINISH before we start to creaing report.
    @rem We check this by periodical query to mon$attachments:

    call :wait4all

    set msg=Making final performance analysys. . .
    echo %date% %time% %msg% >>%sts%

    del %rpt% 2>nul

    if .%make_html%.==.1. (

      @rem #######################################################################
      @rem #####   S t a r t i n g      w r i t e      i n t o    . h t m l  #####
      @rem #######################################################################
      (
        @rem -- dis 14.12.2015 -- this will be added later, see below -- echo ^<^^!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"^> 
        echo ^<html^>
        echo ^<head^>
        echo ^<meta http-equiv="content-type" content="text/html; charset=utf-8" /^>
        echo ^<meta http-equiv="cache-control" content="no-cache"^>
        echo ^<meta http-equiv="pragma" content="no-cache"^>
        @rem -- dis 14.12.2015 -- echo ^<title^>FB-%fb% OLTP-EMUL^</title^> -- this tag will be added with concrete info about FB, database and test settings plus performance score, see below
        echo  ^<style type="text/css"^>
        echo     table {
        echo         border-collapse: collapse;
        @rem echo         background: #99CCFF;
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
        echo    .success {
        echo       color: black;
        echo       background-color: #00FF00;
        echo    }
        echo    .warning {
        echo       color: black;
        echo       background-color: #FFFF00;
        echo    }
        echo    .error {
        echo       color: black;
        echo       background-color: #FF0000;
        echo    }
        echo    .fault {
        echo       color: #990000;
        echo       background-color: #FFFFCC;
        echo       font-weight: bold;
        echo    }
        echo    .monosp {
        echo       font-family: monospace;
        echo    }
        echo ^</style^>
        echo ^</head^>
        echo ^<body^>
        echo Generated by %~f0, ISQL session #1 of total launched %winq%. !date! !time!.

        echo ^<table^>
        echo ^<th^>Common^</th^>
        echo ^<th^>Performance^</th^>
        echo ^<th^>Final Results^</th^>
        echo ^<tr^>
        echo ^<td^>
        echo ^<ol^>
        echo     ^<li^>^<a href="#testsettings"^>Test configuration^</a^> ^</li^>
        echo     ^<li^>^<a href="#testfinishinfo"^>Test Finish details^</a^> ^</li^>
        echo     ^<li^>^<a href="#testworkload"^>Test workload details^</a^> ^</li^>
        echo     ^<li^>^<a href="#qdindexesddl"^>Indices DDL for heavy-loaded table(s^)^</a^> ^</li^>
        echo ^</ol^>
        echo ^</td^>
        echo ^<td^>
        echo ^<ol^>
        echo     ^<li^>^<a href="#perftotal"^>Performance, TOTAL score^</a^> ^</li^>
        echo     ^<li^>^<a href="#perfdynam"^>Performance, DYNAMIC, 10 intervals^</a^> ^</li^>
        echo     ^<li^>^<a href="#perfminute"^>Performance, per MINUTE, since launch^</a^> ^</li^>
        echo     ^<li^>^<a href="#perftrace"^>Performance, TRACE data for ISQL #1^</a^> ^</li^>
        echo     ^<li^>^<a href="#perfdetail"^>Performance, DETAILS per units^</a^> ^</li^>
        echo     ^<li^>^<a href="#perfmon4unit"^>MON$-analysis, per business units^</a^> ^</li^>
        if .%mon_unit_perf%.==.1. if not .%fb%.==.25. (
            echo     ^<li^>^<a href="#perfmon4tabs"^>MON$-analysis, per business units and tables^</a^> ^</li^>
        )

        echo     ^<li^>^<a href="#exceptions"^>Exceptions during test run^</a^> ^</li^>
        echo ^</ol^>
        echo ^</td^>
        echo ^<td^>
        echo ^<ol^>
        echo     ^<li^>^<a href="#fbdbinfo"^>mon$database and 'show version' results^</a^> ^</li^>
        echo     ^<li^>^<a href="#dbstatistics"^>Database Statistics, full^</a^> ^</li^>
        echo     ^<li^>^<a href="#dbverstotal"^>Ratio "Versions / Records" for tables^</a^> ^</li^>
        echo     ^<li^>^<a href="#dbvalidation"^>Database Validation Results^</a^> ^</li^>
        echo     ^<li^>^<a href="#fblogcompare"^>New in firebird.log while test was run^</a^> ^</li^>
        echo     ^<li^>^<a href="#finalpart"^>Final processing of ISQL logs^</a^> ^</li^>
        echo ^</ol^>
        echo ^</td^>
        echo ^</tr^>
        echo ^</table^>

      ) > %htm_file%

      @rem  -- do NOT -- call :add_html_text tmp_file htm_file 0  // wrong output of "<!DOCTYPE", 1st line in html will start from wrong text: <//www.w3.org/TR/html4/strict.dtd">

      @rem -----------------------------------------------------------------------

      echo !htm_sect! ^<a name="testsettings"^> Server and database settings ^</a^> !htm_secc! >> %htm_file%

      %run_get_fb_ver% 1>%tmp_file% 2>&1

      call :add_html_text tmp_file htm_file

      del %tmp_file% 2>nul

      (
        echo set list on;
        echo select
        echo     p.fb_arch as fb_architecture
        echo     ,mon$database_name as db_name
        echo     ,iif(mon$forced_writes=0, '$css$warning$OFF', 'ON'^) as forced_writes
        echo     ,mon$sweep_interval as sweep_int
        echo     ,mon$page_buffers as page_buffers
        echo     ,mon$page_size as page_size
        echo from mon$database
        echo left join sys_get_fb_arch p on 1=1;
      ) > %rpt%

      call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
      del %rpt% 2>nul

      echo !htm_sect! Test configuration settings !htm_secc! >> %htm_file%
      echo File: %~dp0%cfg% >> %htm_file%
      @rem ::: NB ::: Space + TAB should be inside `^[ ]` pattern!
      @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
      (
          set /a k=1
          for /F "tokens=*" %%a in ('findstr /i /r /c:"^[ 	]*[a-z,0-9]" %cfg%') do (
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
                    if !k! gtr 1 echo union all
                    echo select '!par!' as param_name, '!val!' as param_value from rdb$database
                  )
              )
              @rem echo %%a
              set /a k=!k!+1
          )
          if !k! gtr 1 echo ;
      ) > %rpt%
      @rem > %tmp_file%
      call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

      del %rpt% 2>nul
      @rem call :add_html_text tmp_file htm_file
      @rem del %tmp_file% 2>nul

    )

    @rem -----------------------------------------------------------------------

    @echo %date% %time%. Output test finish state...
    (
        echo.
        echo ##########################################
        echo ###  t e s t    f i n i s h   i n f o  ###
        echo ##########################################
    ) >> %log4all%

    (
        echo commit;
        echo create or alter view tmp$for$report$only as
        echo     select 
        echo        p.exc_info as finish_state,
        echo        p.dts_end, p.fb_gdscode, e.fb_mnemona, 
        echo        coalesce(p.stack,''^) as stack,
        echo        p.ip,p.trn_id, p.att_id,p.exc_unit
        echo     from perf_log p
        echo     left join fb_errors e on p.fb_gdscode = e.fb_gdscode
        echo     where p.unit = 'sp_halt_on_error'
        echo     order by p.dts_beg desc
        echo     rows 1;
        echo commit;
        echo set list on;
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
        echo from tmp$for$report$only x
        echo ;
        echo commit;
    ) > %rpt%
    type %rpt% >>%log4all%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    if .%make_html%.==.1. echo !htm_sect! ^<a name="testfinishinfo"^> Test finish info ^</a^> !htm_secc! >>%htm_file%

    %run_repo% 1>>%log4all% 2>&1
   
    if .%make_html%.==.1. (
        (
          echo select
          echo     iif(x.finish_state containing 'abnormal', '$css$error$', iif(x.finish_state containing 'premature', '$css$warning$', '$css$success$' ^) ^) ^|^| x.finish_state as finish_state
          echo    ,x.dts_end
          echo    ,x.fb_gdscode
          echo    ,x.fb_mnemona
          echo    ,x.stack
          echo    ,x.ip 
          echo    ,x.trn_id 
          echo    ,x.att_id 
          echo    ,x.exc_unit
          echo from tmp$for$report$only x
          echo ;
          echo commit;
        ) > !rpt!
        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
    )
    del %rpt% 2>nul

    (
      echo.
      echo #####################################################
      echo ###  c u r r e n t    t e s t    s e t t i n g s  ###
      echo #####################################################
    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_sect! ^<a name="testworkload"^> Current test settings ^</a^> !htm_secc! >> %htm_file%

    (

      echo set width category 12;
      echo set width setting 32;
      echo set width val 20;

      echo select 
      echo    s.working_mode as category, 
      echo    s.mcode as setting, 
      echo    s.svalue as val
      echo from settings s
      echo where s.working_mode='COMMON'

      echo union all

      echo select s.working_mode, s.mcode as setting, s.svalue
      echo from settings s
      echo join (
      echo     select s.svalue as working_mode
      echo     from settings s where s.working_mode = 'INIT'
      echo ^) w on s.working_mode = w.working_mode;

    ) > %rpt%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    echo Command for obtaining current test settings:>>%sts%
    echo %run_repo%>>%sts%
 
    echo %date% %time%. Output current database and test settings...
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

    set msg=Index(es) for heavy-loaded table(s)

    echo %msg%: >>%log4all%
    if .%make_html%.==.1. echo !htm_sect! ^<a name="qdindexesddl"^> %msg% ^</a^> !htm_secc! >> %htm_file%

    %run_repo% 1>>%log4all% 2>&1

    if .%make_html%.==.1. call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

    del %rpt% 2>nul

    @rem ------------------------------------------------------------------------------

    (
      echo.
      echo ###############################################
      echo ###  p e r f o r m a n c e    r e p o r t s ###
      echo ###############################################
    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_sect! Performance reports !htm_secc! >>%htm_file%
   

    @rem --------------------------------------------------------------------------

    set msg=Performance in TOTAL
    echo %date% %time%. Generating report "%msg%"...
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
      echo    business_action as action, 
      echo    avg_times_per_minute, 
      echo    avg_elapsed_ms, 
      echo    successful_times_done, 
      echo    job_beg, 
      echo    job_end
      echo from rdb$database
      echo left join srv_mon_perf_total on 1=1;
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
    echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

    if .%make_html%.==.1. (
        set t1=!time!
        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
        call :add_html_text tmp_file htm_file
    )

    del %rpt% 2>nul

    @rem --------------------------------------------------------------------------

    set msg=Performance in DYNAMIC
    echo %date% %time%. Generating report "%msg%"...
    (
      echo.
      echo %msg%:
      echo.
    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_repn! ^<a name="perfdynam"^> %msg%: ^</a^> !htm_repc!>> %htm_file%

    (
      echo --  Get performance report with splitting data to 10 equal time intervals,
      echo --  for last 3 hours of activity:
      echo set width action 24; 
      echo set width itrv_no  7;
      echo set width itrv_beg 8;         
      echo set width itrv_end 8;         
      echo select business_action as action
      echo       ,cast(interval_no as smallint^) as itrv_no
      echo       ,cnt_ok_per_minute
      echo       ,cnt_all
      echo       ,cnt_ok
      echo       ,cnt_err
      echo       ,cast(err_prc as numeric(8,2^)^) as err_prc
      echo       ,substring(cast(interval_beg as varchar(24^)^) from 12 for 8^) itrv_beg 
      echo       ,substring(cast(interval_end as varchar(24^)^) from 12 for 8^) itrv_end 
      echo from rdb$database 
      echo left join srv_mon_perf_dynamic p on
      echo -- where 
      echo       p.business_action containing 'interval' 
      echo       and p.business_action containing 'overall';
      echo commit;
    ) > %rpt%
    
    type %rpt% >>%log4all%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    set t1=!time!

    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

    if .%make_html%.==.1. (
        set t1=!time!

        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
        call :add_html_text tmp_file htm_file
    )
    del %rpt% 2>nul



    @rem --------------------------------------------------------------------------

    set msg=Performance for every MINUTE
    echo %date% %time%. Generating report "%msg%"...
    (
      echo.
      echo %msg%:
      echo.
    ) >> %log4all%

    if .%make_html%.==.1. echo !htm_repn! ^<a name="perfminute"^> %msg%: ^</a^> !htm_repc!>> %htm_file%

    (
      echo -- Extract values of ESTIMATED performance that was evaluated after EACH business
      echo -- operation finished. View is base on table PERF_ESTIMATED which was filled up
      echo -- by every ISQL session after it finished and before it was terminated.
      echo -- These data can help to find proper value of config parameter 'warm_time'.
      echo -- Current value of config parameter 'warm_time' = %warm_time%.
      echo set width test_phase 10; 
      echo select iif( minute_since_test_start ^<= %warm_time%, 'WARM_TIME', 'TEST_TIME'^) test_phase
      echo       ,minute_since_test_start
      echo       ,avg_estimated
      echo       ,min_to_avg_ratio
      echo       ,max_to_avg_ratio
      echo       ,rows_aggregated
      echo       ,distinct_attachments -- since 22.12.2015: helps to ensure that all ISQL sessions were alive in every minute of test work time
      echo from z_estimated_perf_per_minute;
      echo commit;
    ) > %rpt%
    
    type %rpt% >>%log4all%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    set t1=!time!
    
    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

    if .%make_html%.==.1. (
        set t1=!time!
        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
        call :add_html_text tmp_file htm_file
    )

    del %rpt% 2>nul

    @rem --------------------------------------------------------------------------
    if .%trc_unit_perf%.==.1. (
        set msg=Performance from TRACE for ISQL instance #1
        echo !date! !time!. Generating report "!msg!"...

        if .%make_html%.==.1. echo !htm_repn! ^<a name="perftrace"^> !msg!: ^</a^> !htm_repc! >>%htm_file%

        (
          echo --  Get TRACE performance report for ISQL session #1, with splitting data to 10 equal 
          echo -- time intervals, for last 3 hours of activity:
          
          echo set width traced_data 20; 
          echo set width itrv_no  7;
          echo set width itrv_beg 8;         
          echo set width itrv_end 8;         
          echo select
          echo      traced_data
          echo      ,cast(interval_no as smallint^) as itrv_no
          echo      ,sp_client_order
          echo      ,sp_cancel_client_order
          echo      ,sp_supplier_order
          echo      ,sp_cancel_supplier_order
          echo      ,sp_supplier_invoice
          echo      ,sp_cancel_supplier_invoice
          echo      ,sp_add_invoice_to_stock
          echo      ,sp_cancel_adding_invoice
          echo      ,sp_customer_reserve
          echo      ,sp_cancel_customer_reserve
          echo      ,sp_reserve_write_off
          echo      ,sp_cancel_write_off
          echo      ,sp_pay_from_customer
          echo      ,sp_cancel_pay_from_customer
          echo      ,sp_pay_to_supplier
          echo      ,sp_cancel_pay_to_supplier
          echo      ,srv_make_invnt_saldo
          echo      ,srv_make_money_saldo
          echo      ,srv_recalc_idx_stat
          echo      ,substring(cast(interval_beg as varchar(24^)^) from 12 for 8^) itrv_beg 
          echo      ,substring(cast(interval_end as varchar(24^)^) from 12 for 8^) itrv_end 
          echo from rdb$database left join srv_mon_perf_trace_pivot on 1=1;
          echo commit;

          @rem echo select info as action
          @rem echo       ,cast(interval_no as smallint^) as itrv_no
          @rem echo       ,cnt_success
          @rem echo       ,fetches_per_second
          @rem echo       ,marks_per_second
          @rem echo       ,reads_to_fetches_prc
          @rem echo       ,writes_to_marks_prc
          @rem echo       ,substring(cast(interval_beg as varchar(24^)^) from 12 for 8^) itrv_beg 
          @rem echo       ,substring(cast(interval_end as varchar(24^)^) from 12 for 8^) itrv_end 
          @rem echo from rdb$database 
          @rem echo left join srv_mon_perf_trace p on 1=1;
          @rem echo commit;
        ) > %rpt%
        
        type %rpt% >>%log4all%

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
        set t1=!time!

        %run_repo% 1>>%log4all% 2>&1

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
        echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

        if .%make_html%.==.1. (
            set t1=!time!

            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

            set t2=!time!
            set tdiff=0
            call :timediff "!t1!" "!t2!" tdiff
            echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
            call :add_html_text tmp_file htm_file
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
    echo %date% %time%. Generating report "%msg%"...
    (
      echo.
      echo %msg%:
      echo.
      echo Get performance report with detaliation per units, for last 3 hours of activity.
      echo "CNT_ALL" = total number of events when unit started,
      echo "CNT_OK"  = total number of events when unit finished successfully.
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
      echo     ,job_beg
      echo     ,job_end
      echo from rdb$database
      echo left join srv_mon_perf_detailed on 1=1;
      echo commit;
    ) > %rpt%

    type %rpt% >>%log4all%
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    set t1=!time!
    
    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

    if .%make_html%.==.1. (
        set t1=!time!

        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
        call :add_html_text tmp_file htm_file
    )
    del %rpt% 2>nul

    @rem --------------------------------------------------------------------------

    if .%mon_unit_perf%.==.1. (
      set msg=Monitoring data, per application UNITS
      echo !date! !time!. Generating report "!msg!"...
      (
        echo.
        echo %msg%:
        echo.
        echo Get report about gathered MONITOR tables data, detalization per UNITS.
        echo NOTE: source view for this report will be created only when config
        echo parameter 'mon_unit_perf' has value 1.
      ) >> %log4all%

      if .%make_html%.==.1. echo !htm_repn! ^<a name="perfmon4unit"^> !msg!: ^</a^> !htm_repc! >>%htm_file%

      (
          echo set width unit 31;
          echo select z.*
          echo from rdb$database
          echo left join srv_mon_stat_per_units z on 1=1;
          echo commit;
      ) > %rpt%

      type %rpt% >>%log4all%
      set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

      set t1=!time!

      %run_repo% 1>>%log4all% 2>&1

      set t2=!time!
      set tdiff=0
      call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
      echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

      if .%make_html%.==.1. (
          set t1=!time!
          call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
          set t2=!time!
          set tdiff=0
          call :timediff "!t1!" "!t2!" tdiff
          echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
          call :add_html_text tmp_file htm_file
      )
      del %rpt% 2>nul
  
      if NOT .%fb%.==.25. (
          set msg=Monitoring data, per TABLES and application UNITS
          echo !date! !time!. Generating report "!msg!"...
   
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
            echo left join srv_mon_stat_per_tables z on 1=1;
            echo commit;
          ) > %rpt%

          type %rpt% >>%log4all%
          set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
          set t1=!time!

          %run_repo% 1>>%log4all% 2>&1

          set t2=!time!
          set tdiff=0
          call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
          echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

          if .%make_html%.==.1. (
              set t1=!time!
              call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
              set t2=!time!
              set tdiff=0
              call :timediff "!t1!" "!t2!" tdiff
              echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
              call :add_html_text tmp_file htm_file
          )
          del %rpt% 2>nul

      )

    ) else (

      set msg=Config param. mon_unit_perf=%mon_unit_perf%, data from MON$ tables were NOT gathered.
      (
        echo.
        echo %msg%:
        echo.
      ) >> %log4all%
 
      if .%make_html%.==.1. echo !htm_repn! ^<a name="perfmon4unit"^> !msg! ^</a^> !htm_repc! >>%htm_file%

    )


    @rem ------------------------------------------------------------------------------

    set msg=Exceptions occured during test work
    echo %date% %time%. Generating report "%msg%"...
    (
      echo.
      echo #########################################################
      echo ###  e x c e p t i o n s     d u r i n g     t e s t  ###
      echo #########################################################
    ) >> %log4all%

    
    (
      echo.
      echo set width fb_mnemona 31;                  
      echo set width unit 40;                        
      echo set width dts_beg 16;                     
      echo set width dts_end 16;                     
      echo select fb_mnemona, cnt, unit, fb_gdscode                                  
      echo       ,substring(cast( dts_min as varchar(24^)^) from 1 for 16^) dts_beg  
      echo       ,substring(cast( dts_max as varchar(24^)^) from 1 for 16^) dts_end  
      echo from rdb$database
      echo left join srv_mon_exceptions on 1=1;
      echo.
    ) > %rpt%

    type %rpt% >>%log4all%
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    set t1=!time!
    
    %run_repo% 1>>%log4all% 2>&1

    set t2=!time!
    set tdiff=0
    call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
    echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1


    if .%make_html%.==.1. (
        echo !htm_repn! ^<a name="exceptions"^> %msg%: ^</a^> !htm_repc! >>%htm_file%
        set t1=!time!

        call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff
        echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
        call :add_html_text tmp_file htm_file
    )
    del %rpt% 2>nul

    @rem ---------------------------------------------------------------------------

    set msg=MON$DATABASE and FB VERSION info
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

        call :add_html_text tmp_file htm_file
    )

    echo show version; > %rpt%
    type %rpt% >>%log4all%
    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    %run_repo% 1>%tmp_file% 2>&1
    type %tmp_file% >>%log4all%
    if .%make_html%.==.1. (
        call :add_html_text tmp_file htm_file
    )

    del %rpt% 2>nul

    echo.>>%log4all%
    echo.>>%log4all%

    @rem ---------------------------------------------------------------------------
    set skip_fbsvc=0
    @rem 09.10.2015: call fbsvcmgr in embedded mode now is possible, CORE-4938 is fixed

    @rem ------------------------------------------------------------------------------

    if .%run_db_statistics%.==.1. (

        set msg=Database statistics, full
        echo !date! !time!. Generating report "!msg!"...

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
        echo Done for !tdiff! ms, from !t1! to !t2!. >>%tmp_file% 2>&1

        type %tmp_file% >>%log4all%

        if .%make_html%.==.1. (
            echo !htm_sect! ^<a name="dbstatistics"^> !msg! ^</a^> !htm_secc!>>%htm_file%
            call :add_html_text tmp_file htm_file 1 null monosp
        )

        set msg=Analyzing DB stat log: obtaining values of total records and versions
        echo !date! !time!. !msg!...

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
                        @rem Average version length: 0.00, total versions: 0, max versions: 0
                        for /f "tokens=7 delims=, " %%a in ("!line!") do (
                          set /a vers=%%a
                        )
                        @rem echo recs=!recs! vers=!vers!
                        if not .!recs!.==.0. (
                          set /a vprc=!vers!*100/!recs!
                          @rem echo vprc=!vprc!
                          if !vprc! gtr 9 (
                            set line=!line!. Versions ratio: !vprc!%%
                            @rem echo !line!
                          )
                        )
                        @rem echo tabn=!tabn! recs=!recs! vers=!vers! vprc=!vprc!%%
                        @rem echo insert into perf_log(unit, table_name, rec_inserts, rec_updates^) values('!tabn!', !recs!, !vers!^);
    
                        echo insert into mon_log_table_stats(id, rowset, table_name, rec_inserts, rec_updates^) 
                        echo values( -gen_id(g_common,1^), -current_connection, '!tabn!', !recs!, !vers!^); -- NB: 'rowset' is INDEXED field.
                      )
                   )
                )
            
            )
            echo set heading off;
            echo select -current_connection from rdb$database; -- this will be saved into script env. variable 'xrowset', see below
            echo set heading on;
            echo commit;
        ) >%rpt%

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
        
        %run_repo% 1>%tmp_file% 2>&1
        
        for /f %%x in (%tmp_file%) do set xrowset=%%x

        (
          echo commit;
          echo create or alter view tmp$for$report$only as
          echo select
          echo     t.table_name
          echo     ,t.rec_inserts as total_recs
          echo     ,t.rec_updates as total_vers
          echo     ,cast( 100.0000 * t.rec_updates / t.rec_inserts  as numeric(14,4^)^) as vers_percent
          echo from mon_log_table_stats t
          echo where 
          echo    t.rowset=!xrowset!
          echo    and t.rec_inserts ^> 0
          echo order by t.table_name;
          echo commit;
          echo set width table_name 31;
          echo select * from tmp$for$report$only; 
          echo commit;
        ) > %rpt%

        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

        %run_repo% 1>%tmp_file% 2>&1
        
        (
          echo.
          echo !msg!
        ) >>%log4all%

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%log4all%
        echo Done for !tdiff! ms, from !t1! to !t2!. >>%log4all% 2>&1

        type %tmp_file% >>%log4all%

        if .%make_html%.==.1. (
           echo !htm_sect! ^<a name="dbverstotal"^> !msg! ^</a^> !htm_secc! >>%htm_file%

           (
             echo select
             echo     x.table_name
             echo    ,x.total_recs
             echo    ,x.total_vers
             echo    ,iif(x.vers_percent ^> 500, '$css$error$', iif(x.vers_percent ^> 50, '$css$warning$', ''^)^) ^|^| x.vers_percent as vers_percent
             echo from tmp$for$report$only x
             echo ;
             echo commit;
             echo delete from mon_log_table_stats t
             echo where t.rowset=!xrowset!
             echo ;
           ) > !rpt!
           
           set t1=!time!

           call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file

           set t2=!time!
           set tdiff=0
           call :timediff "!t1!" "!t2!" tdiff
           echo Done for !tdiff! ms, from !t1! to !t2!. 1>!tmp_file! 2>&1
           call :add_html_text tmp_file htm_file

        )

        del %tmp_file% 2>nul
        del %rpt% 2>nul

    ) else (

       set msg=Database statistics was not gathered, see config parameter 'run_db_statistics'.
       (
           echo.
           echo !msg!
           echo.
       ) >>%log4all%
       if .%make_html%.==.1. (
           echo !htm_sect! ^<a name="dbstatistics"^> !msg! ^</a^> !htm_secc!>>%htm_file%
       )
    )

    @rem ------------------------------------------------------------------------------

    if .%run_db_validation%.==.1. (

        set msg=Database validation
        echo !date! !time!. Generating report "!msg!"...

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

        call %tmpdir%\tmp_validation.bat 1>%tmp_file% 2>&1

        set t2=!time!
        set tdiff=0
        call :timediff "!t1!" "!t2!" tdiff 2>>%tmp_file%
        echo Done for !tdiff! ms, from !t1! to !t2!. >>%tmp_file% 2>&1

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
            
            call :add_html_text tmp_file htm_file 1 null monosp

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
    echo !date! !time!. Generating report "!msg!"...

    (
        echo.
        echo ###################################################################################
        echo ###  C o m p a r i s o n    o f    o l d   a n d   n e w    f i r e b i r d . l o g
        echo ###################################################################################
        echo.
        echo Gathering firebird.log AFTER test finish.
        echo ++++++++++++++++++++++++++
        echo Command: !run_get_fb_log!
        echo ++++++++++++++++++++++++++
        echo Result:
    ) > %tmp_file%

    type %tmp_file% >>%log4all%

    %run_get_fb_log% 1>%fblog_final% 2>&1

    (
        echo %time%. Got:
        for /f "delims=" %%a in ('find /v /c "" %fblog_final%') do echo STDOUT: %%a (number of rows in extracted log^)
    ) 1>%tmp_file% 2>&1


    (
        echo.
        echo Obtained firebird.log info:
        echo Result of DIR command for firebird.log AFTER test finish:
        dir /-c %fblog_final% | findstr /i /c:"%fblog_endnm%"
    )>>%tmp_file% 2>&1

    (
        echo. 
        echo End of gathering firebird.log AFTER test finish.
    ) >>%tmp_file%

    type %tmp_file% >>%log4all%
    if .%make_html%.==.1. (
        echo !htm_sect! !msg! !htm_secc!>>%htm_file%
        call :add_html_text tmp_file htm_file
    )

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

    echo +++ Start of comparison +++>%tmp_file%

    %run_fc_compare% 1>>%tmp% 2>&1

    set fc_result=%errorlevel%
    if .!fc_result!.==.0. (
        echo result: files match. No new messages appeared in firebird.log during test ran. >>!tmp_file!
    ) else (
        set /a k=1
        for /f "tokens=*" %%a in ('type !tmp!') do (
          @rem First line in output of fc.exe utility is localized, skip it.
          if not .!k!.==.1. echo %%a >> !tmp_file!
          set /a k+=1
        )
        @rem type !tmp!>>!tmp_file!
    )

    del %tmp% 2>nul

    echo +++ End of comparison +++>>%tmp_file%

    type %tmp_file% >>%log4all%

    if .%make_html%.==.1. (
        echo !htm_sect! ^<a name="fblogcompare"^> !msg! ^</a^> !htm_secc!>>%htm_file%
        call :add_html_text tmp_file htm_file
    )

    (
        echo !date! !time! Done.
        echo.
        echo +++++++ end of batch %~f0 ++++++++
        echo.
    ) >>%sts%


    echo !date! !time!. Removing all ISQL logs according to value of config 'remove_isql_logs' setting...

    @rem 335544558    check_constraint    Operation violates CHECK constraint @1 on view or table @2.
    @rem 335544347    not_valid    Validation error for column @1, value "@2".
    @rem 335544665 unique_key_violation (violation of PRIMARY or UNIQUE KEY constraint "..." on table ...") // if table has unique constraint
    @rem 335544349 no_dup (attempt to store duplicate value (visible to active transactions) in unique index "***") // if table has only unique index

    set log_cnt=0
    set log_ptn=%tmpdir%\oltp%fb%_*.*
    for %%x in (%log_ptn%) do set /a log_cnt+=1

    if /i .%remove_isql_logs%.==.never. (
        set msg=%log_cnt% logs of every ISQL session are preserved, see config setting 'remove_isql_logs'
    ) else if /i .%remove_isql_logs%.==.always. (
        set msg=%log_cnt% logs of every ISQL session are removed, see config setting 'remove_isql_logs'
    ) else if /i .%remove_isql_logs%.==.if_no_severe_errors. (
        set msg=Remove %log_cnt% logs of every ISQL session if there were no serious errors.
    )
    
    echo. > %tmp_file%
    echo !msg! >> %tmp_file%
    type %tmp_file% >> %log4all%

    if .%make_html%.==.1. (
        echo !htm_sect! ^<a name="finalpart"^> Final processing ISQL logs in %tmpdir% ^</a^> !htm_secc!>>%htm_file%
        call :add_html_text tmp_file htm_file
    )

    (
          echo.
          echo create or alter view tmp$for$report$only as
          echo select 
          echo     x.severe_errors_occured
          echo    ,iif( x.severe_errors_occured = 1, 'SEVERE_ERRORS_EXIST!', 'NO_SEVERE_ERRORS_FOUND' ^) as errors_checking_result
          echo from (
          echo select iif( exists( select *
          echo                     from perf_log p
          echo                     where -- ::: NB ::: added "0" to the list of severe gdscodes! SuperClassic 3.0 trouble.
          echo                         p.fb_gdscode in ( 0, 335544558, 335544347, 335544665, 335544349 ^)
          echo                         and p.dts_beg ^> (
          echo                             select x.dts_beg
          echo                             from perf_log x
          echo                             where x.unit='perf_watch_interval'
          echo                             order by x.dts_beg desc
          echo                             rows 1
          echo                         ^)
          echo                  ^)
          echo              ,1
          echo              ,0 
          echo         ^) as severe_errors_occured
          echo from rdb$database
          echo ^) x;
          echo commit;
          echo -- Checking query:
          echo set list on;
          echo select x.errors_checking_result from tmp$for$report$only x;
          echo commit;
    ) > %rpt%


    if /i .%remove_isql_logs%.==.never. (
        set msg=Logs of every ISQL session are preserved, pattern: %log_ptn% - see config setting 'remove_isql_logs'
    ) else if /i .%remove_isql_logs%.==.always. (
        set msg=Logs of every ISQL session are removed, pattern: %log_ptn% - see config setting 'remove_isql_logs'
        del %log_ptn%
    ) else if /i .%remove_isql_logs%.==.if_no_severe_errors. (
        set msg=Remove logs of every ISQL session if there were no serious errors, pattern: %log_ptn%
        type %rpt% >>%log4all%
        set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 
    )

    if .%remove_isql_logs%.==.if_no_severe_errors. (

      %run_repo% 1>%tmp_file% 2>&1
      
      type %tmp_file% >> %log4all%

      if .%make_html%.==.1. (
            (
              echo select iif(x.severe_errors_occured = 1, '$css$error$', '$css$success$'^) ^|^| x.errors_checking_result as errors_checking_result
              echo from tmp$for$report$only x;
              echo commit;
              echo drop view tmp$for$report$only;
              echo commit;
            ) > !rpt!
            echo !htm_repn! %msg%: !htm_repc! >>%htm_file%
            call :add_html_table fbc tmpdir dbconn dbauth rpt htm_file
      )

      del %rpt% 2>nul

      findstr "NO_SEVERE_ERRORS_FOUND" %tmp_file% >nul
      if not errorlevel 1 (
          echo ISQL logs are removed because no severe errors occured during test. > %tmp_file%
          type %tmp_file% >> %log4all%
          call :add_html_text tmp_file htm_file
          del %log_ptn%
      )
    )
    del %tmpdir%\1run_oltp_emul.err 2>nul
    del %tmpdir%\getFileTimeStamp.* 2>nul
    del %tmpdir%\tmp_longsleep.* 2>nul

    (
      echo.
      echo %date% %time% - end of report, text file: %log4all%, html: %htm_file%
      echo.
      echo.
    ) > %tmp_file%

    type %tmp_file% >>%log4all%

    if .%make_html%.==.1. (
      call :add_html_text tmp_file htm_file
 
      (
        echo ^</body^>
        echo ^</html^>
      ) > !tmp_file!

      call :add_html_text tmp_file htm_file 0
    
    )

    @rem Define name of final report file, see 'set name_for_saving=...' below:
    @rem ######################################################################
    (
        echo set heading off; 
        echo select report_file from srv_get_report_name('%fname%', '%fbb%', %winq%^);
        echo set heading on; 
    ) > %rpt%

    set run_repo=%fbc%\isql %dbconn% -i %rpt% %dbauth%
    %run_repo% 1>%tmp_file% 2>&1
    
    del %rpt% 2>nul

    @rem %fname% = value of optional config parameter 'file_name_with_test_params' = regular | benchmark, by default it is undefined.
    @rem When this value is not empty then we have to rename final report (text and html) to the file which will have maximum info
    @rem about FB build, database FW, test settings and performance result in its name.
    @rem Sample of report name when this parameter is:
    @rem 1. 'regular':   
    @rem    20151102_1448_score_06543_build_31236_ss30__3h00m_100_att_fw__on_<host_info>.txt
    @rem 2. 'benchmark': 
    @rem    ss30_fw_off_split_most__sel_1st_one_index_score_06543_build_31236__3h00m_100_att_20151102_1448_<host_info>.txt
    @rem -- where <host_info> = content of config parameter %file_name_this_host_info% // 09-mar-2016

    if not .%fname%.==.. (
        set upload_log=!tmpdir!\oltp_emul_upload_results.log
        for /f %%a in (!tmp_file!) do (
            set name_for_saving=!tmpdir!\%%a
            set final_txt=!name_for_saving!
            if not .%file_name_this_host_info%.==.. (
              set final_txt=!final_txt!_%file_name_this_host_info%
            )
            set final_txt=!final_txt!.txt
            call :repl_with_bound_quotes !final_txt! final_txt

            copy %log4all% !final_txt! >nul
            if exist !final_txt! del %log4all% 2>nul
    
            if .%make_html%.==.1. (
              set final_htm=!name_for_saving!
              if not .%file_name_this_host_info%.==.. (
                set final_htm=!final_htm!_%file_name_this_host_info%
              )
              set final_htm=!final_htm!.html
              call :repl_with_bound_quotes !final_htm! final_htm

              for %%i in ("!final_htm!") do set report_name=%%~ni
              del !final_htm! 2>nul

              @rem HTML report: add DOCTYPE as 1st line and <title>...</title? tag for conveniency:
              set /a k=1
              for /f "delims=" %%a in (!htm_file!) do (
                if .!k!.==.1. (
                  echo ^<^^!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"^> >>!final_htm!
                ) 
                set "line=%%a"
                echo !line!>>!final_htm!
                if .!line!.==.^<head^>. (
                    echo ^<title^>!report_name!^</title^> >>!final_htm!
                )
                set /a k=!k!+1
              )

              @rem old: copy %htm_file% !final_htm! >nul

              if exist !final_htm! (
                del %htm_file% 2>nul
                @rem 'upload_report' - optional config parameter, by default it is UNDEFINED.
                @rem When this parameter = 1 then we have to upload report and remove it from
                @rem local drive if upload finished OK.
                if .%upload_report%.==.1. (
                    echo !date! !time!. Upload results in HTML format...
                    for %%n in ("!final_htm!") do set report_name=%%~nxn

                    (
                        echo # This log was created by %~dp0%~nx0
                        echo # Command: call ..\util\upload.bat !report_name! !final_htm!
                        echo.
                    ) >!upload_log!

                    call ..\util\upload.bat !report_name! !final_htm! 1>>!upload_log! 2>&1

                    echo !date! !time!. Done, check !upload_log!:
                    type !upload_log! 
                    findstr /i /c:"success" !upload_log! >nul
                    if not errorlevel 1 (
                      echo Final HTML report has been uploaded by: ..\util\upload.bat !report_name! !final_htm! >>!upload_log!
                      del !final_htm!
                      del !final_txt!
                    ) 
                )
              )
            ) else (
                @rem 'upload_report' - optional config parameter, by default it is UNDEFINED.
                @rem When this parameter = 1 then we have to upload report and remove it from
                @rem local drive if upload finished OK.
                if .%upload_report%.==.1. (
                    echo !date! !time!. Upload results in TEXT format...
                    for %%n in ("!final_txt!") do set report_name=%%~nxn
                    call ..\util\upload.bat !report_name! !final_txt! 1>!upload_log! 2>&1
                    echo !date! !time!. Done, check !upload_log!:
                    type !upload_log! 
                    findstr /i /c:"success" !upload_log! >nul
                    if not errorlevel 1 (
                      echo Final TEXT report has been uploaded by: ..\util\upload.bat !report_name! !final_htm! >>!upload_log!
                      del !final_txt!
                    ) 
                )
            )
        )
    ) else (
        set name_for_saving=%log4all%
    )

    if not .!postie_send_args!.==.. (
          set mail_sending_log=!tmpdir!\oltp_emul_mail_send.log
          call :repl_with_bound_quotes !mail_sending_log! mail_sending_log
          del !mail_sending_log! 2>nul
          set msg=!date! !time!. Sending report to e-mail

          for /f %%i in ("!name_for_saving!") do (
              echo !msg!...
              set name4subj=%%~ni
              set run_cmd=postie.exe !postie_send_args! ^
                 -s:"OLTP-EMUL REPORT: !name4subj!" ^
                 -msg:"See attached file" ^
                 -a:!name_for_saving! 

              (
                  echo !msg!
                  echo Command: !run_cmd!
              ) >> !mail_sending_log!

              !run_cmd! 1>>!mail_sending_log! 2>&1
          )
    )

    @rem -- echo %date% %time% Done. >>%sts%
    del %tmp_file% 2>nul

    set batch4stop=%tmpdir%\1stoptest.tmp.bat
    call :repl_with_bound_quotes !batch4stop! batch4stop
    del !batch4stop! 2>nul

  goto end

:end

  goto fin

:wait4all
    setlocal
    
    
    set logname=%tmpdir%\tmp_wait_for_all_stop
    set tmpchk=!logname!.sql
    set tmpclg=!logname!.clg
    set tmperr=!logname!.err
    set tmplog=!logname!.tmp
    
    
    set tmpchk=!tmpchk:"=!
    set tmpchk="!tmpchk!"
    
    set tmpclg=!tmpclg:"=!
    set tmpclg="!tmpclg!"
    
    set tmperr=!tmperr:"=!
    set tmperr="!tmperr!"
    
    set tmplog=!tmplog:"=!
    set tmplog="!tmplog!"
    
    del %tmpchk% 2>nul
    del %tmpclg% 2>nul
    del %tmperr% 2>nul
    del %tmplog% 2>nul
    
    (
        echo set list on; 
        echo commit;
        echo select count(*^) as "active_att=" 
        echo from mon$attachments a 
        echo where a.mon$attachment_id ^<^> current_connection 
        echo       and a.mon$remote_address is not null 
        echo       and a.mon$remote_process containing 'isql'; 
        @rem -- do NOT add "a.mon$system_flag is distinct from 1", avail only in 3.0
    )>%tmpchk%
    
    set active_att=1
    set attempt_no=1
    set max_retries=30
 
    :m1

        if .%attempt_no%.==.%max_retries%. (
            @rem Something wrong with database or one of hanged attaches. Go on with report.
            set msg=Limit for waiting exceeded, begin report creation.
            echo !msg!
            echo !msg!>>%tmplog%
            goto:eof
        )
        
        set run_isql=%fbc%\isql %dbconn% -nod -n -i %tmpchk% %dbauth% 
        
        set msg=%time%: check for other active ISQL attachments, attempt %attempt_no% of %max_retries%
        echo %msg%
        echo %msg%>>%tmplog%
        
        echo %run_isql%
        echo %run_isql%>>%tmplog%
        
        %run_isql% 1>%tmpclg% 2>%tmperr%
        
        for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
            set /a %%a
        )
        @rem result: env var 'active_att' if DEFINED now and equal to number of ISQL sessions
        
        if .%active_att%.==.0. (
            set msg=All ISQL attachments were FINISHED, now we can build final report.
        ) else (
            set msg=There are still .%active_att%. active ISQL attachments, we must WAIT. . .
        )
        echo %msg%
        echo %msg%>>%tmplog%
        
        if .%active_att%.==.0. (
            del %tmpchk% 2>nul
            del %tmpclg% 2>nul
            del %tmperr% 2>nul
            del %tmplog% 2>nul
        ) else (
            set /a attempt_no=%attempt_no%+1
            ping -n 11 127.0.0.1>nul
            @rem ....................  l o o p    c o u n t    a t t a c h e s  .............

            goto m1
        )

    endlocal

goto:eof

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

:add_html_text 

    setlocal

    set tmp_file=!%1!
    set htm_file=!%2!
    set add_br=%3
    set line_prefix=%4
    set use_style=%5

    if not defined add_br set add_br=1
    if .%line_prefix%.==.null. set line_prefix=


    (
        if not .%use_style%.==.. (
          echo ^<div class="%use_style%"^>
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
          echo ^</div^>
        )

    ) >> %htm_file%

    endlocal
goto:eof

:add_html_table    

    setlocal

    set fbc=!%1!
    set tmpdir=!%2!
    set dbconn=!%3!
    set dbauth=!%4!
    set sql_in=!%5!
    set htm_file=!%6!

    set dbg=%7

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


    (
        echo set sqlda_display on;
        echo set planonly;
        type %sql_in%
    ) > %sql_temp%

    %fbc%\isql %dbconn% %dbauth% -i %sql_temp% 1>%tmp_sqlda% 2>%sql_err%

    for %%a in (%sql_err%) do if not %%~za lss 1 (
        echo !htm_repn! RUNTIME FAULT: !htm_repc! >>%tmp_html%
        call :add_html_text sql_temp tmp_html
        call :add_html_text sql_err tmp_html 1 $css$fault$
    )

    @rem 2.5: OUTPUT SQLDA version: 1 sqln: 20 sqld: 1
    @rem 3.0: OUTPUT message field count
    for /f "tokens=1 delims=:" %%a in ('findstr /n /c:"OUTPUT message " /c:"OUTPUT SQLDA" %tmp_sqlda%') do set out_line=%%a

    @rem -- %fbc%\isql %dbconn% %dbauth% -i %sql_temp% | findstr /i /c:"alias:" 1>%sql_log%

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
        
        @rem 2.5: " (7)SETTING"
        @rem 3.0: " SETTING"

        call :get_sqlda_fld_name %fb% %%d fld_name

        @rem echo a=%%a b=%%b c=%%c d=%%d e=%%e fld_name=%fld_name%=!fld_name!  &pause

        set is_num=2
        call :is_num_type !k! %tmp_sqlda% %out_line% is_num

        @rem echo fld_name=!fld_name! is_num=!is_num! &pause

        if .!is_num!.==.1. set num_list=!num_list!,!k!
        set /a k=!k!+1
    )
    set num_list=!num_list!,
    echo !num_list!>%tmp_nums%

    @rem echo num_list=!num_list! &pause

    @rem result: num_list = list of POSITION INDICES which relates to numeric fields.

    echo ^<table border="1" cellpadding="3"^> >>%tmp_html%

    set tho="<th>"
    set tho=!tho:"=!
    set thc="</th>"
    set thc=!thc:"=!

    set tro="<tr>"
    set tro=!tro:"=!
    set trc="</tr>"
    set trc=!trc:"=!

    set tdo="<td>"
    set tdo=!tdo:"=!
    set tdc="</td>"
    set tdc=!tdc:"=!

    set tdno="<td align=right>"
    set tdno=!tdno:"=!
    set tdnc="</td>"
    set tdnc=!tdnc:"=!


    @rem Output HEADER of table
    set i=1
    (
      for /f "tokens=1-5 delims=:" %%a in ('type %sql_log%') do (
          if .!i!.==.1. (
              call :get_sqlda_fld_name %fb% %%d fld_first
          )

          set fld_name=%%d
          call :get_sqlda_fld_name %fb% %%d fld_name

          if not .%%d.==.. (
              echo !tho! !fld_name! !thc!
              @rem echo !tho! !fld_name:_= ! !thc!
          ) else (
              echo !tho! " " !thc!
          )
          set fld_last=%%d
          call :get_sqlda_fld_name %fb% %%d fld_last

          set /a i=!i!+1
      )
    ) >> %tmp_html%

    set fld_first=!fld_first: =!
    set fld_last=!fld_last: =!

    @rem echo fld_first=.!fld_first!. fld_last=.!fld_last!. - check header of table in %tmp_html%  &pause

    (
        echo set list on;
        @rem NOTE: adding 'eol=' is mandatory because by default ';' is considered as comment and skipped by for /f.
        for /f "tokens=* eol=" %%a in ('type %sql_in%') do (
            if /i "%%a"=="set list off;" (
                echo --%%a
            ) else (
                echo %%a
            )
        )
        @rem type %sql_in%
    ) > %sql_temp%

    @rem echo cc1: check input file %sql_temp% &pause

    %fbc%\isql %dbconn% %dbauth% -i %sql_temp% 1>%sql_log% 2>%sql_err%

    for %%a in (%sql_err%) do if not %%~za lss 1 (
        echo !htm_repn! RUNTIME FAULT: !htm_repc! >>%tmp_html%
        call :add_html_text sql_temp tmp_html
        call :add_html_text sql_err tmp_html 1 $css$fault$
    )

    @rem Output DATA of report:
    (
      set fld_num=1
      for /f "tokens=*" %%a in ('type %sql_log%') do (
          set line=%%a
          set fld_name=!line:~0,31!
          call :trim fld_name !fld_name!
          if .!fld_name!.==.!fld_first!. (
              echo !tro!
              set fld_num=1
          )

          @rem echo ci1: fld_name=!fld_name! pause

          set cell=!line:~32!

          @rem NOTE: we need to replace html-specific characters (GT, LT, AMP) immediatelly,
          @rem BEFORE call trim subroutine:

          if not .!cell!.==.. (
              set cell=!cell:^&=^&amp;!
              set cell=!cell:^<=^&lt;!
              set cell=!cell:^>=^&gt;!
              @rem $css$success$','$css$error$

              call :trim cell !cell!

              set ccss=!cell:$css$error$=!
              if not !ccss!==!cell! (
                set cell=^<span class="error"^>!ccss!^</span^>
              ) else (
                set ccss=!cell:$css$warning$=!
                if not !ccss!==!cell! (
                  set cell=^<span class="warning"^>!ccss!^</span^>
                ) else (
                  set ccss=!cell:$css$success$=!
                  if not !ccss!==!cell! set cell=^<span class="success"^>!ccss!^</span^>
                )
              )
          ) 
          set is_num=1
          call :chk4num fld_num num_list is_num

          @rem Seem that: `findstr ,!fld_num!, %tmp_nums% 1>nul & if not errorlevel 1 (...` - is SLOWER more than 2x!
          if .!is_num!.==.1. (
              echo !tdno! !cell! !tdnc!
          ) else (
              echo !tdo! !cell! !tdc!
          )

          if .!fld_name!.==.!fld_last!. echo !trc!
          set /a fld_num=!fld_num!+1
      )
    ) >> %tmp_html%

    echo ^</table^> >>%tmp_html%

    type %tmp_html% >> %htm_file%

    del %sql_temp% 2>nul
    del %sql_log% 2>nul
    del %sql_err% 2>nul
    del %tmp_sqlda% 2>nul
    del %tmp_nums% 2>nul
    del %tmp_html% 2>nul

goto:eof


:trim
    setLocal
    set Params=%*
    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

:chk4num
    setlocal
    set num_chk=,!%1!,
    set num_lst=!%2!
    set result=1
    if "!num_lst:%num_chk%=!"=="%num_lst%" set result=0
    endlocal & set "%~3=%result%"
goto:eof

:get_sqlda_fld_name
    setlocal
    set fb=%1
    set sqlda_name=%2
    set fld_name=%2
    if .%fb%.==.25. (
       for /f "tokens=1-3 delims=()" %%u in ("%sqlda_name%") do (
           if not .%%v.==.. ( set fld_name=%%v ) else ( set fld_name=%%w )
       )
    )
    set fld_name=!fld_name: =!
    
    endlocal & set "%~3=%fld_name%"
goto:eof

:save_perf_estimated

    @rem call {this} log sts rpt fbc dbconn dbauth
    @rem              1   2   3   4     5     6
    setlocal
    set log=!%1!
    set sts=!%2!
    set rpt=!%3!
    set fbc=!%4!
    set dbconn=!%5!
    set dbauth=!%6!

    set msg=!date! !time!. Writing statistics data about estimated performance from %log%
    echo !msg!
    echo !msg! >>%log%
    echo !msg! >>%sts%
    (
      echo -- Debug. Uncomment this if some problem occur and see then %log%
      echo -- set echo on;
    ) > %rpt%

    set /a k=0
    (
      @rem do NOT: echo delete from perf_estimated; -- this is done in 1run_oltp_emul before every new test (re)start.
      for /f "tokens=1-3" %%a in ('findstr EST_OVERALL_AT_MINUTE_SINCE_BEG %log%') do (
        if not .%%c.==.. if not .%%b.==.. (
            echo insert into perf_estimated( minute_since_test_start, success_count ^) values( %%c, %%b ^);
            set /a k=!k!+1
        ) else (
            echo -- PARSING ERROR. Statement can not be executed: %%a %%b %%c
        )
      )
      echo commit;
    ) >> %rpt%

    set run_repo=%fbc%\isql %dbconn% -n -pag 9999 -i %rpt% %dbauth% 

    set msg=!date! !time!. Running !run_repo!
    echo !msg!

    echo !msg! >>%log%
    echo !msg! >>%sts%
    findstr /i /c:"parsing error" %rpt% >>%sts%

    %run_repo% 1>>%log% 2>&1

    set msg=!date! !time!. Done, !k! rows were saved in the database before this log will be made empty.
    echo !msg!
    echo !msg! >>%log%
    echo !msg! >>%sts%

    del %rpt% 2>nul
goto:eof

:is_num_type

    setlocal

    set fld_num=%1
    set tmp_file=%2
    set out_params_1st_line=%3

    set /a k=1000+%fld_num%
    set k=!k:~2,2!
    set result=0
    set num_types=SHORT LONG INT64 DOUBLE LONG FLOAT

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
  if .!t2s!. LSS .!t1s!. set /a tdiff=!tdiff!+86400000
  @echo off

  endlocal&set "%~3=%tdiff%"
goto:eof


:err_setenv
  @echo off
  echo.
  echo Batch running now: %~f0
  echo.
  echo Config file: %cfg% - could NOT set new environment variables.
  echo.
  echo Press any key to FINISH. . .
  echo.
  @pause>nul
  @goto fin

:fin
@rem do NOT remove this exit command otherwise all cmd worker windows stay opened:

EXIT
