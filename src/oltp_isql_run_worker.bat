@echo off
setlocal enabledelayedexpansion enableextensions
path=..\util;%path%
@rem Must be called from oltp_run_scenarios.bat
@rem ==========================================

@rem limits for log of work and errors
@rem (zap if size exceed and fill again from zero):
@set maxlog=15000000
@set maxerr=15000000

@rem -----------------------------------------------
@rem ###############  mandatory args: ##############
@rem -----------------------------------------------
set fb=%1
set sql=%2
set lognm=%3
set sid=%4

rem %tmpdir%\%logbase%-001.performance_report.txt - name of file for overall performance report
rem (do NOT overwrite it here, it has already some info that was added there in 1run*.bat):
set log4all=%5

if .%fb%.==.. (
  echo %~f0: not defined arg: fbc
  goto fin
)

if .%sql%.==.. (
  echo %~f0: not defined arg: sql
  goto fin
)
if .%lognm%.==.. (
  echo %~f0: not defined arg: lognm
  goto fin
)

set cfg=oltp%fb%_config.win

@rem log where current acitvity of this ISQL will be:
set log=%lognm%.log

@rem log where ERRORS will be for this ISQL:
set err=%lognm%.err

@rem cumulative log with brief info about running process state:
set sts=%lognm%.running_state.txt

del %err% 2>nul
set err_setenv=0

@echo off
if .%sid%.==.1. (
  echo Intro %~f0
  echo Parsing config %cfg%...>>%log4all%
)
for /F "tokens=*" %%a in ('findstr /i /r /c:"^[ 	]*[a-z,0-9]" %cfg%') do (
  if "%%a" neq "" (
    @rem Detect whether new var contain quotes or no. 
    @rem If yes than delimiter must be only ONE '=',
    @rem otherwise it will be <tab><equal_sign><space> or <tab><space><equal_sign>
    echo %%a|find """">nul
    if errorlevel 1 ( 
      @rem if .%sid%.==.1. echo Line: ^|%%a^| - does NOT contain quotes>>%log4all%
      for /F "tokens=1-2 delims=	= " %%i in ("%%a") do (
        @rem echo Parsed-1: param="%%i" val="%%j"
        if "%%j"=="" (
          set err_setenv=1
          rem if .%sid%.==.1. echo ### NO VALUE found for parameter "%%i" ###>>%log4all%
        ) else (
          set %%i=%%j
          rem if .%sid%.==.1. echo param=^|%%i^| val=^|%%j^|>>%log4all%
        )
      )
    ) else (
      @rem if .%sid%.==.1. echo ^|%%a^| - DOES contain quotes>>%log4all%
      for /F "tokens=1-2 delims==" %%i in ("%%a") do (
        @rem echo Parsed-1: param="%%i" val="%%j"
        if "%%j"=="" (
          set err_setenv=1
          rem if .%sid%.==.1. echo ### NO VALUE found for parameter "%%i" ###>>%log4all%
        ) else (
          set %%i=%%j
          rem if .%sid%.==.1. echo param=^|%%i^| val=^|%%j^|>>%log4all%
        )
      )
    )
  )
)

if .%sid%.==.1. echo Was errors while parsing config  ? =^> %err_setenv% >>%log4all%

if .%err_setenv%.==.1. (
  @echo Check error log:
  type %err%
  goto err_setenv
)

if .%is_embed%.==.. (
  echo %~f0: not defined arg: is_embed
  goto fin
)

if "%fbc%"==.. (
  echo %~f0: not defined arg: fbc
  goto fin
)

if "%dbnm%"==.. (
  echo %~f0: not defined arg: dbnm
  goto fin
)

@rem ----------------------------------------------
@rem ###############  optional args: ##############
@rem ----------------------------------------------

if .%is_embed%.==.1. (
  set dbauth=
  set dbconn=%dbnm%
) else (
  set dbauth=-user %usr% -pas %pwd%
  set dbconn=%host%/%port%:%dbnm%
) 

set initdelay=

if .%use_mtee%.==.1. (
  set run_isql=%fbc%\isql %dbconn% -now -q -n -pag 9999 -i %sql% %dbauth% 2^>^&1 1^>^>%log% ^| mtee /t/+ %err% ^>nul
) else (
  set run_isql=%fbc%\isql %dbconn% -now -q -n -pag 9999 -i %sql% %dbauth% 1^>^>%log% 2^>^>%err%
)

echo.>>%sts%
echo %date% %time%, batch running now: %~f0 - check start command: >>%sts%
echo --- beg of command for launch isql --->>%sts%
echo cmd /c !run_isql!>>%sts%
echo --- end of command for launch isql --->>%sts%
echo.>>%sts%
@rem echo %fbc%\isql %dbconn% -now -q -n -pag 9999 -i %sql% %dbauth% 2^>^&1 1^>^>%log% ^|mtee /t/+ %err% ^> nul >>%sts%

if .%sid%.==.1. (
  echo This window *WILL* do performance report after test make selfstop.>>%sts%
)

@rem log_after=1 -- this window must call srv_mon_perf_total after job will ends
@rem set log_after=0
@rem @rem extract last six characters from log file name and set log_after=1 only for 1st log:
@rem if .%log:~-8%.==._001.log. set log_after=1
@rem if .%log_after%.==.1. (
@rem   echo This window *WILL* do performance report after test make selfstop.>>%sts%
@rem )

@set k=0
@echo off

if .%initdelay%.==.. (
   set /a initdelay = 2 + (%random% %% 8^)
)
set msg=Take initial sleep %initdelay% seconds to start ISQLs at different moments. . .
echo %msg%>>%sts%
echo %msg%
echo Delay at: %date% %time%>>%sts%
ping -n %initdelay% 127.0.0.1 >nul
::set dts_beg=%date% %time%
echo Start at: %date% %time%>>%sts%

:start

  for /f "usebackq" %%A in ('%log%') do set size=%%~zA
  if .%size%.==.. set size=0
  echo size of %log% = %size%
  if %size% gtr %maxlog% (
    echo %date% %time% size of %log% = %size% - exceeds limit %maxlog%, remove it >> %sts%
    del %log%
  )

  for /f "usebackq" %%A in ('%err%') do set size=%%~zA
  if .%size%.==.. set size=0
  echo size of %err% = %size%
  if %size% gtr %maxerr% (
    echo %date% %time% size of %err% = %size% - exceeds limit %maxerr%, remove it >> %sts%
    del %err%
  )

  @set /a k=k+1
  @echo ------------------------------------------
  @echo Start isql, packet # %k% at %date% %time%
  @echo Command: !run_isql!
  @echo ------------------------------------------
  @echo on

  @rem #############################    R U N     I S Q L    ##############################
  cmd /c !run_isql!
  @rem ####################################################################################

  @echo off
  @echo ---------------------------------------
  @echo finish packet # %k% at %date% %time%
  @echo ---------------------------------------

  @rem ------------------------------------------------------------------------------
  @rem c h e c k    i f    d a t a b a s e   h a s    b e e n    s h u t d o w n e d:
  @rem ------------------------------------------------------------------------------
  find /c /i "shutdown" %err% >nul
  if errorlevel 1 goto db_online
  goto db_offline

:db_online
  @echo database ONLINE, continue the job - check test cancellation string in %err%
  @rem ------------------------------------------------------------------
  @rem c h e c k    i f    t e s t   h a s   b e e n    C A N C E L L E D:
  @rem ------------------------------------------------------------------
  find /c /i "EX_TEST_CANCEL" %err% >nul
  if errorlevel 1 goto start
  goto test_canc

:db_offline
  set msg=DATABASE SHUTDOWN DETECTED, test has been cancelled
  @echo.
  @echo %date% %time% %msg%
  @echo.
  @echo %date% %time% %msg% >>%sts%
  goto end
:test_canc
  set msg=STOPFILE has non-zero size, test has been cancelled
  @echo.
  @echo %date% %time% %msg%
  @echo.
  @echo %date% %time% %msg% >>%sts%

  @rem ---------------------------------------

  if .%sid%.==.1. (
    
    @rem All other attachment have to be FINISH before we start to creaing report.
    @rem We check this by periodical query to mon$attachments:

    call :wait4all   

    set msg=Making final performance analysys. . .
    echo %date% %time% %msg% >>%sts%

    set psql=%lognm%.performance_report.tmp
    del !psql! 2>nul
    set plog=%log4all%

    echo set width category 12;        >>!psql!
    echo set width setting 32;         >>!psql!
    echo set width val 20;             >>!psql!

    echo select s.working_mode as category, s.mcode as setting, s.svalue as val >>!psql!
    echo from settings s                                            >>!psql!
    echo where s.working_mode='COMMON'                              >>!psql!
    echo union all                                                  >>!psql!
    echo select s.working_mode, s.mcode as setting, s.svalue        >>!psql!
    echo from settings s                                            >>!psql!
    echo join (                                                     >>!psql!
    echo     select s.svalue as working_mode                        >>!psql!
    echo     from settings s where s.working_mode = 'INIT'          >>!psql!
    echo ^) w on s.working_mode = w.working_mode;                   >>!psql!

    echo.>>!plog!
    echo I. All used settings for this test run:>>!plog!
    echo.>>!plog!
    set run_isql=%fbc%\isql %host%/%port%:%dbnm% -now -q -n -pag 9999 -i !psql! -user %usr% -pas %pwd% -m
    cmd /c !run_isql! 1>>!plog! 2>>&1
    del !psql! 2>nul

    @rem ------------------------------------------------------------------------------

    echo set width business_action 24; >>!psql!
    echo set width itrv_beg 8;         >>!psql!
    echo set width itrv_end 8;         >>!psql!

    echo -- Set TIL = RC for SP srv_mon_perf_dynamic could see data>>!psql!
    echo -- in perf_all table when perf_log is VIEW and is PARTITIONED.>>!psql!
    echo -- See source code of all report SRV_MON_*** procedures:>>!psql!
    echo commit; set transaction read committed;>>!psql!
    echo.>>!psql!
    echo -- 1. Get performance report with splitting data to 10 equal time intervals,>>!psql!
    echo --    for last 3 hours of activity:>>!psql!
    echo select business_action,interval_no,cnt_ok_per_minute,cnt_all,cnt_ok,cnt_err,err_prc >>!psql!
    echo       ,substring(cast(interval_beg as varchar(24^)^) from 12 for 8^) itrv_beg >>!psql!
    echo       ,substring(cast(interval_end as varchar(24^)^) from 12 for 8^) itrv_end >>!psql!
    echo from srv_mon_perf_dynamic p >>!psql!
    echo where p.business_action containing 'interval' and p.business_action containing 'overall';>>!psql!
    echo commit;>>!psql!
    echo.>>!psql!
    echo -- 2. Get overall performance report for last 3 hours of activity:>>!psql!
    echo --    Value in column "avg_times_per_minute" in 1st row is overall performance index.>>!psql!
    echo set width business_action 35;>>!psql!
    echo select business_action, avg_times_per_minute, avg_elapsed_ms, successful_times_done, job_beg, job_end>>!psql!
    echo from srv_mon_perf_total;>>!psql!
    echo -- 3. Get info about database and FB version:>>!psql!
    echo set list on; select * from mon$database; set list off;>>!psql!
    echo show version;>>!psql!

    echo.>>!plog!
    echo II. Analyze performance log:>>!plog!
    echo.>>!plog!
    set run_isql=%fbc%\isql %host%/%port%:%dbnm% -now -q -n -pag 9999 -i !psql! -user %usr% -pas %pwd% -m
    echo !run_isql! >>!plog!
    cmd /c !run_isql! 1>>!plog! 2>>&1

    @echo off
    echo.>>!plog!
    echo.>>!plog!
    echo This report is result of:>>!plog!
    type !psql!>>!plog!
    del !psql! 2>nul
    
    @rem ------------------------------------------------------------------------------

    echo.>>!plog!
    echo III. Obtain database statistics:>>!plog!
    echo.>>!plog!
    set run_fbs=%fbc%\fbsvcmgr %host%/%port%:service_mgr -action_db_stats -sts_data_pages -sts_idx_pages -sts_record_versions -dbname %dbnm%
    echo !run_fbs!>>!plog!
    cmd /c !run_fbs! 1>>!plog! 2>>&1
    echo.>>!plog!
    echo %date% %time% - end of file !plog!>>!plog!
    echo.>>!plog!
    echo %date% %time% Done. >>%sts%

  )

  goto end

:end
  @echo.>>%sts%
  @echo ++++++++++++++++++++  E N D    O F    O L T P _ R U N _ I S Q L . B A T  ++++++++++++++++++++++>>%sts%
  @echo.>>%sts%
  @rem pause
  goto fin

:wait4all

  set tmpchk=%lognm%.wait4all.tmp
  set tmpclg=%lognm%.wait4all.log
  set tmperr=%lognm%.wait4all.err

  del %tmpchk% 2>nul
  del %tmpclg% 2>nul
  del %tmperr% 2>nul

  echo set list on; commit; >>%tmpchk%
  echo select count(*^) as "active_att=" from mon$attachments a >>%tmpchk%
  echo where a.mon$attachment_id ^<^> current_connection >>%tmpchk%
  echo       and a.mon$remote_address is not null >>%tmpchk%
  echo       and a.mon$remote_process containing 'isql'; >>%tmpchk%
  @rem -- do NOT add "a.mon$system_flag is distinct from 1", avail only in 3.0

  set active_att=1
  set attempt_no=1
  set max_retries=30
  :m1
    if .%attempt_no%.==.%max_retries%. (
      @rem Something wrong with database or one of hanged attaches. Go on with report.
      set msg=Limit for waiting exceeded, begin report creation.
      echo !msg!
      echo !msg!>>%log4all%
      goto:eof
    )

    if .%is_embed%.==.1. (
       set run_isql=%fbc%\isql %dbnm% -i %tmpchk% -nod -n 
    ) else (
       set run_isql=%fbc%\isql %host%/%port%:%dbnm% -i %tmpchk% -user %usr% -pas %pwd% -n -nod
    )
    set msg=%time%: check for other active ISQL attachments, attempt %attempt_no% of %max_retries%
    echo %msg%
    echo %msg%>>%log4all%

    echo %run_isql%
    echo %run_isql%>>%log4all%

    cmd /c %run_isql% 1^>%tmpclg% 2^>%tmperr%


    for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
      set /a %%a
    )
    @rem result: env var `active_att` if DEFINED now and equal to number of ISQL sessions
    
    if .%active_att%.==.0. (
      set msg=All ISQL attachments were FINISHED, now we can build final report.
    ) else (
      set msg=There are still .%active_att%. active ISQL attachments, we must WAIT. . .
    )
    echo %msg%
    echo %msg%>>%log4all%

    if .%active_att%.==.0. (
      del %tmpchk% 2>nul
      del %tmpclg% 2>nul
      del %tmperr% 2>nul
    ) else (
      set /a attempt_no=%attempt_no%+1
      ping -n 11 127.0.0.1>nul
      @rem ....................  l o o p    c o u n t    a t t a c h e s  .............
      goto m1
    )

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
