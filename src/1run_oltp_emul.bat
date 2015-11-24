@echo off
@rem ----------------------------------------------
@rem arg #1 = 25 or 30 - version of FB
@rem arg #2 = number of ISQL sessions top be opened
@rem ----------------------------------------------
@cls
setlocal enabledelayedexpansion enableextensions

if .%1.==.. goto no_arg1

set fb=%1
if .%fb%.==.25. goto chk2
if .%fb%.==.30. goto chk2
goto no_arg1

:chk2
if .%2.==.. goto noarg1
set /a k = %2
if not .%k%. gtr .0. goto no_arg1

:ok
echo %date% %time% - starting %~f0
echo Input arg1 = ^|%1^|, arg2  = ^|%2^|

set cfg=oltp%fb%_config.win

set isc_user=
set isc_password=

echo Parsing config file ^>%cfg%^<. Please wait. . .
set err_setenv=0

::::::::::::::::::::::::::::::::
:::: R E A D    C O N G I G ::::
::::::::::::::::::::::::::::::::

call :readcfg %cfg% !err_setenv!

@rem Removing trailing backslash from %fbc% and %tmpdir% if any.
@rem NB: `command error` will be here in case when value ends with double quote
@rem      so we have to remove it before comparision with trailing backslash.
@rem See: stackoverflow.com/questions/535975/dealing-with-quotes-in-windows-batch-scripts

set q_tmp=2
if defined tmpdir (
    call :has_spaces %tmpdir% q_tmp
    if .%q_tmp%.==.2. (
        call :has_spaces "%tmpdir%" q_tmp
    )
    set tmp_deq=!tmpdir:"=!
    if .!tmp_deq:~-1!.==.\. (
        set tmp_deq=!tmp_deq:~0,-1!
    )
    if .!q_tmp!.==.1. (
        set tmpdir="!tmp_deq!"
    ) else (
        set tmpdir=!tmp_deq!
    )
) else (
  echo.
  echo Missing variable with name 'tmpdir'.
  echo.
  goto :no_env
)

set q_fbc=2
if defined fbc (
    
    if /i .%fbc%.==.*. (
       echo Found asterisk instead of path to FB client binaries. 
       echo Attempt to define path via detecting most appropriate FB service.
       call :getfblst %fb% fbc
    )

    call :has_spaces %fbc% q_fbc
    if .%q_fbc%.==.2. (
        call :has_spaces "%fbc%" q_fbc
    )
    set fbc_deq=!fbc:"=!
    if .!fbc_deq:~-1!.==.\. (
        set fbc_deq=!fbc_deq:~0,-1!
    )
    if .!q_fbc!.==.1. (
        set fbc="!fbc_deq!"
    ) else (
        set fbc=!fbc_deq!
    )
)

set q_fdb=2
if defined dbnm (
    call :has_spaces %dbnm% q_fdb
    if .%q_fdb%.==.2. (
        call :has_spaces "%dbnm%" q_fdb
    )

    set tmp_deq=!dbnm:"=!
    if .!tmp_deq:~-1!.==.\. (
        set tmp_deq=!tmp_deq:~0,-1!
    )
    if .!q_fdb!.==.1. (
        set dbnm="!tmp_deq!"
    ) else (
        set dbnm=!tmp_deq!
    )
)

@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@rem INITIATE REPORT FILE "oltp30.report.txt"
@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
if defined tmpdir (
    if not exist %tmpdir% md %tmpdir%
    if not exist %tmpdir%\sql md %tmpdir%\sql
    set log4all=%tmpdir%\oltp%fb%.report.txt
    set log4tmp=%tmpdir%\oltp%fb%.prepare.log
) else (
    set log4all=%~dp0oltp%fb%.report.txt
    set log4tmp=%~dp0oltp%fb%.prepare.log
)

del %log4all% 2>nul
::if errorlevel 1 goto :cannot_del
del %log4tmp% 2>nul
::if errorlevel 1 goto :cannot_del

echo Created by: %~f0>>%log4all%.
(
  echo %date% %time%. Preparing for test started.
  echo Currently running batch: %~f0
  echo Checking parameters. Config file: %cfg%.
) >>%log4tmp%

echo. && echo Config parsing finished. Result:

set varlist=fbc,dbnm,tmpdir,is_embed,create_with_fw,create_with_sweep,no_auto_undo
set varlist=%varlist%,use_mtee,detailed_info,init_docs,init_buff,wait_after_create
set varlist=%varlist%,wait_for_copy,warm_time,test_time,idle_time,remove_isql_logs
set varlist=%varlist%,create_with_split_heavy_tabs,create_with_separate_qdistr_idx
set varlist=%varlist%,create_with_compound_columns_order,create_with_debug_objects
set varlist=%varlist%,working_mode,wait_if_not_exists

if .%is_embed%.==.0. (
    set varlist=%varlist%,usr,pwd,host,port
)
if .%1.==.30. (
    set varlist=!varlist!,mon_unit_perf
)

for %%v in (%varlist%) do (
    if "!%%v!"=="" (
        set msg=### MISSED: %%v ###
        echo. && echo !msg! && echo.
        set err_setenv=1
    ) else (
        set msg=Param: ^|%%v^|, value: ^|!%%v!^|
        echo !msg!
    )
    echo !msg! >> %log4tmp%
)

if .%err_setenv%.==.1. goto no_env

@rem Change PATH variable: insert %fbc% to the HEAD of path list:
set pbak=%path%
set path=%fbc%;%pbak%

echo Changing path: put %fbc% into HEAD of list.

@rem check that result of PREVIOUS launch of this batch was OK:
@rem #############################
set build_was_cancelled=0

call :check_for_prev_build_err %tmpdir% %fb% build_was_cancelled

@rem Result: build_was_cancelled = 1 ==> previous building process was cancelled (found "SQLSTATE = HY008" in .err).

@rem echo build_was_cancelled=%build_was_cancelled% &pause

if not exist %fbc%\isql.exe goto bad_fbc_path
if not exist %fbc%\gfix.exe goto bad_fbc_path
if not exist %fbc%\fbsvcmgr.exe goto bad_fbc_path

set msg=All necessary FB utilities found in %fbc% 
echo %msg% & echo %msg% >> %log4tmp%

set tmplog=%tmpdir%\tmp_get_fb_db_info.log
set tmperr=%tmpdir%\tmp_get_fb_db_info.err

@rem 18.09.2015 0217
call :repl_with_bound_quotes %tmplog% tmplog
call :repl_with_bound_quotes %tmperr% tmperr

if .%is_embed%.==.1. (
    set dbauth=
    set dbconn=%dbnm%
) else (
    set dbauth=-user %usr% -password %pwd%
    set dbconn=%host%/%port%:%dbnm%
)

set fbsvcrun=%fbc%\fbsvcmgr

call :repl_with_bound_quotes %fbsvcrun% fbsvcrun

@rem Result when 'fbc' contain spaces: "C:\Program Files\Firebird Database Server 2.5.5\bin\fbsvcmgr" 
@rem (should be invoked by 'cmd /c' without any troubles).

if .%is_embed%.==.1. (
    set fbsvcrun=%fbsvcrun% service_mgr
) else (
    set fbsvcrun=%fbsvcrun% %host%/%port%:service_mgr %dbauth%
)

echo dbauth=%dbauth% >>%log4tmp%
echo dbconn=%dbconn% >>%log4tmp%
echo fbsvcrun=%fbsvcrun% >>%log4tmp%


@rem Sample for path 'fbc' with spaces (works Ok):
@rem "C:\Program Files\Firebird Database Server 2.5.5\bin\fbsvcmgr" localhost/3255:service_mgr -user SYSDBA -password masterke info_server_version

@rem ::: NB ::: do NOT include redirection to tmplog and tmperr in run_cmd 
@rem - it does not work via 'cmd /c !cmd_run!' when path contains spaces and is quoted!

@rem #######################################
@rem Attempt to get server version together with OS prefix: 'WI'=WIndows or 'LI'=LInux)

echo|set /p=Obtain Firebird info...

set run_cmd=!fbsvcrun! info_server_version

echo %time%. Run: !run_cmd! 1^>%tmplog% 2^>%tmperr%  >>%log4tmp%

%run_cmd% 1>%tmplog% 2>%tmperr%

(
    echo %time%. Got:
    for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
    for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
) 1>>%log4tmp% 2>&1

call :catch_err run_cmd !tmperr! n/a nofbvers

@rem result: log content = "Server version: LI-V2.5.3.26790 Firebird 2.5" etc


for /f "tokens=1-3 delims= " %%a in ('findstr /i /c:version %tmplog%') do (
  set fbb=%%c
  set fbo=!fbb:~0,2!
)

if not defined fbb (
    echo.
    echo Could not detect Firebird build number from 'FBSVCMGR info_server_version' log.
    echo Probably FBSVCMGR output was changed or error in this batch algorithm.
    echo.
    echo See details in %log4tmp%
    if .%wait_if_not_exists%.==.1. (
        echo Press any key to FINISH this batch. . .
        pause>nul
    )
    goto final
)
set msg= Build: ^|%fbb%^|, prefix of server OS: ^|%fbo%^|
echo !msg! & echo !msg! >>%log4tmp%

del %tmperr% 2>nul
del %tmplog% 2>nul

@rem #######################################

set tmpname=%~n0

set tmplog=%tmpdir%\%tmpname%.log
set tmperr=%tmpdir%\%tmpname%.err
set tmpsql=%tmpdir%\%tmpname%.sql
set tmpchk=%tmpdir%\%tmpname%.chk
set tmpclg=%tmpdir%\%tmpname%.clg

call :repl_with_bound_quotes %tmplog% tmplog
call :repl_with_bound_quotes %tmperr% tmperr
call :repl_with_bound_quotes %tmpsql% tmpsql
call :repl_with_bound_quotes %tmpchk% tmpchk
call :repl_with_bound_quotes %tmpclg% tmpclg

set msg=Check that database is avaliable.
echo !msg! & echo !msg! >>%log4tmp%
echo.

@rem ##############################################################
@rem TODO LATER: change this alg! use hash of all db object names ?

(
     echo set heading off; 
     echo set list on;
     echo set bail on;
     echo -- check that all database objects already exist:
     echo select iif( exists( select * from semaphores where task='all_build_ok' ^),
     echo                     'all_dbo_exists',
     echo                     'some_dbo_absent'
     echo           ^) as "build_result="
     echo from rdb$database;
     set rndname=!random!
     echo -- Check that database is not in read_only mode.
     echo -- NOTE: we create GTT in order to check *not* only ability to write into database file,
     echo -- but also to check that Firebird process has enough rights to WRITE into GTT files.
     echo -- These files are created in the folder that is defined by 1st environment variable:
     echo -- from following list: 1^) FIREBIRD_TMP; 2^) TMP; or in 3^) /tmp (for POSIX^).
     echo -- When Firebird process has no rights to that directory, test will fail with message:
     echo -- #####################################################
     echo -- Statement failed, SQLSTATE = 08001
     echo -- I/O error during "open O_CREAT" operation for file ""
     echo -- -Error while trying to create file
     echo -- -No such file or directory
     echo -- #####################################################
     echo -- See also: sql.ru/forum/actualutils.aspx?action=gotomsg^&tid=1176238^&msg=18172438
     echo.
     echo recreate GLOBAL TEMPORARY table tmp!rndname!(id int, s varchar(36^) unique using index tmp!rndname!_s_unq ^);
     echo commit;
     echo set count on;
     echo insert into tmp!rndname!(id, s^) select rand(^)*1000, uuid_to_char(gen_uuid(^)^) from rdb$types;
     echo set list on;
     echo select min(id^) as id_min, max(id^) as id_max, count(*^) as cnt from tmp!rndname!; 
     echo commit;
     echo drop table tmp!rndname!;
     echo.
     echo alter sequence g_stop_test restart with 0;
     echo.
     echo set term ^^;
     echo execute block as
     echo begin
     echo     begin
     echo         -- Inject value of config parameter `mon_unit_perf` into table SETTINGS.
     echo         -- ::: NB ::: When test is launched from several hosts this DML can fail
     echo         -- with update conflict or "deadlock" exception, so we have to suppress it:
     echo         update settings set svalue=%mon_unit_perf%
     echo         where working_mode=upper('common'^) and mcode=upper('enable_mon_query'^);
     echo         if (row_count = 0^) then 
     echo             exception ex_record_not_found
     if .%fb%.==.30. (
     echo             using ('settings', 'working_mode=''COMMON'' and mcode=''ENABLE_MON_QUERY'''^)
     )
     echo         ;
     echo     when any do 
     echo         begin
     echo            if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ^) ^) then exception;
     echo         end
     echo     end

     echo     begin
     echo         -- Inject value of config parameter `working_mode` into table SETTINGS.
     echo         -- ::: NB ::: When test is launched from several hosts this DML can fail
     echo         -- with update conflict or "deadlock" exception, so we have to suppress it:
     echo         update settings set svalue = upper('%working_mode%'^)
     echo         where working_mode=upper('init'^) and mcode=upper('working_mode'^);
     echo         if (row_count = 0^) then
     echo             exception ex_record_not_found
     if .%fb%.==.30. (
     echo             using ('settings', 'working_mode=''INIT'' and mcode=''WORKING_MODE'''^)
     )
     echo         ;
     echo     when any do 
     echo         begin
     echo            if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ^) ^) then exception;
     echo         end
     echo     end
     echo end ^^
     echo set term ;^^
     echo commit;
)>%tmpsql%

set run_isql=%fbc%\isql
call :repl_with_bound_quotes %run_isql% run_isql

set run_isql=!run_isql! %dbconn% %dbauth% -i %tmpsql% -q -n -nod
echo %time%. Run: !run_isql! 1^>%tmpclg% 2^>%tmperr%  >>%log4tmp%

%run_isql% 1>%tmpclg% 2>%tmperr%

(
    for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
    echo %time%. Got:
    for /f "delims=" %%a in ('type %tmpclg%') do echo STDOUT: %%a
    for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
) >>%log4tmp% 2>&1

call :catch_err run_isql !tmperr! !tmpsql! db_notready 0

del %tmpsql% 2>nul
@rem -- later! -- del %tmpclg% 2>nul
@rem -- later! -- del %tmperr% 2>nul

set db_build_finished_ok=2

@rem NB: first line in error text DEPENDS on server OS!
@rem win: I/O error during "CreateFile (open)" operation for file "c:\temp\test\badname.fdb"
@rem      -Error while trying to open file
@rem nix: I/O error during "open" operation for file "/var/db/fb25/badname.fdb"
@rem      -Error while trying to open file
@rem PS. Explanation: sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1120390&msg=16689978

@rem Seems that this can be on linux only:

find /c /i "Is a directory" %tmperr% >nul
if errorlevel 1 goto chk4unav
goto bad_dbnm

:chk4unav
find /c /i "unavailable database" %tmperr% >nul
if errorlevel 1 goto chk4ods
goto unavail_db

:chk4ods
find /c /i "unsupported on-disk" %tmperr% >nul
if errorlevel 1 goto chk4online
goto bad_ods

:chk4online
find /c /i "shutdown" %tmperr% >nul
if errorlevel 1 goto chk4read_only
goto db_offline

:chk4read_only
find /c /i "read-only" %tmperr% >nul
if errorlevel 1 goto chk4open
goto db_read_only


:chk4open
find /c /i "Error while trying to open file" %tmperr% >nul

if errorlevel 1 (

    @rem database DOES exist and ONLINE, but we have to ensure that ALL objects was successfully created in it.
    @rem -------------------------------------------------------------------------------------------------------

    if .%build_was_cancelled%.==.0. (
        for /f "usebackq tokens=*" %%a in ('%tmperr%') do set size=%%~za
        if .!size!.==.. set size=0
        if !size!% gtr 0 (
            set db_build_finished_ok=0
        ) else (
            set db_build_finished_ok=1
            find /c /i "all_dbo_exists" !tmpclg! >nul
            if errorlevel 1 set db_build_finished_ok=0
        )
    ) else (
        set db_build_finished_ok=0
    )
    echo.
    echo db_build_finished_ok=^>^>^>!db_build_finished_ok!^<^<^<
    echo ############################
    echo.
    del %tmperr% 2>nul
    del %tmpclg% 2>nul

    if .!db_build_finished_ok!.==.0. (
        echo.
        echo Database: ^>%dbnm%^< -- DOES exist but
        echo its creation process was not completed.
        echo.
        if .%wait_if_not_exists%.==.1. (
            echo ################################################################################
            echo Press ENTER to start again recreation of all DB objects or Ctrl-C to FINISH. . .
            echo ################################################################################
            echo.
            pause>nul
        )

        set need_rebuild_db=1

    ) else (

        echo Database ^>%dbnm%^< avaliable and has all needed objects.
        set need_rebuild_db=0

    )

) else (

    @rem Text "Error while trying to open file" was found in error log.

    echo.
    echo Database file DOES NOT exist or has a problem with ACCESS to it.
    echo.
    if .%wait_if_not_exists%.==.1. (
        echo Press ENTER to attempt database recreation or Ctrl-C for FINISH. . .
        echo.
        pause>nul
    )

    set need_rebuild_db=1

)

del %tmpclg% 2>nul
del %tmperr% 2>nul

if .%need_rebuild_db%.==.1. (
    @rem #########################   C R E A T E   D A T A B A S E   #######################
    call :prepare
)

@rem ################### check for non-empty stoptest.txt ################################

if  defined use_external_to_stop (
  call :chk_stop_test init_chk !tmpdir! !fbc! !dbconn! "!dbauth!"
) else (
  echo Config parameter 'use_external_to_stop' is UNDEFINED (this is DEFAULT^).
  echo SKIP checking for non-empty external file.
)     

call :show_db_and_test_params !tmpdir! !fbc! !dbconn! "!dbauth!" %is_embed% %log4all%

set existing_docs=-1
set engine=unknown_engine
set log_tab=unknown_table

call :count_existing_docs !tmpdir! !fbc! !dbconn! "!dbauth!" %init_docs% existing_docs engine log_tab
@rem                         1       2       3        4         5             6          7       8

@rem echo existing_docs=%existing_docs%, log_tab=%log_tab%
@rem if /i .%init_docs%.==.0. goto more

set initd_bak=%init_docs%
set /a required_docs = init_docs - %existing_docs%

if %required_docs% geq 0 (
    if .%existing_docs%.==.0. (
      echo Database has NO documents.
    ) else (
      echo There are only %existing_docs% documents in database. Required minimum is: %initd_bak%. 
    )
    echo We have to create yet ^>^>^>%required_docs%^<^<^< ones before launch working ISQL sessions.
) else (
    echo Database has all necessary number of documents that should be initially populated.
    echo Existing ^>= %existing_docs%, required minimum = %initd_bak%. We can launch working ISQL sessions.
)
echo.

if %init_docs% gtr 0 (
  
  @rem ############## I N I T    D A T A    P O P.   ####################

  call :run_init_pop !tmpdir! !fbc! !dbconn! "!dbauth!" %existing_docs% %required_docs% %engine% %log_tab%
)

@rem -----------------------   w o r k i n g    p h a s e   -----------------------------

:more

set mode=oltp_%1

@rem winq = number of opening isqls
set winq=%2
if .%is_embed%.==.1. set winq=1

set sql=%tmpdir%\sql\tmp_random_run.sql
set logbase=oltp%1_%computername%

@rem Make comparison of TIMESTAMPS: this batch vs %sql%.
@rem If this batch is OLDER that %sql% than we can SKIP recreating %sql%
set skipGenSQL=0

set sqldts=19000101000000
set cfgdts=19000101000000
set thisdts=19000101000000

if exist %sql% (

    @rem Check that SQL script contains test "FINISH packet" - this is LAST message
    @rem when its creation finishes w/o interruption.

    echo Check that previous creation of script %sql% was not interrupted...
    findstr /i /c:"FINISH packet" %sql% 1>nul
    if not errorlevel 1 (
        echo Creation of script %sql% finished w/o interruptions.
        call :getFileDTS gen_vbs
        @rem echo before call: sqldts=!sqldts!, thisdts=!thisdts!
        call :getFileDTS get_dts !sql! sqldts
        call :getFileDTS get_dts %~f0 thisdts
        @rem echo after call: sqldts=!sqldts!, thisdts=!thisdts!
        if .!thisdts!. lss .!sqldts!. (
            echo this batch is OLDER than sql

            call :getFileDTS get_dts !cfg! cfgdts
            if .!cfgdts!. lss .!sqldts!. (
                echo Test config file is OLDER than %sql%
                set skipGenSQL=1
            ) else (
                echo Test config file %cfg% is NEWER than %sql%
            )
        ) else (
            echo This batch is NEWER than %sql%
        )
    ) else (
        echo Creation of script %sql% was INTERRUPTED.
    )
    echo.
    if .!skipgenSQL!.==.0. (
        echo must RECREATE %sql%
    ) else (
        echo can SKIP recreating %sql%
    )
)

if .%skipGenSQL%.==.0. (
    @rem Generating script to be used by working isqls.
    @rem ##################################################
    call :gen_working_sql  run_test  %sql%  300   %no_auto_undo%  %detailed_info% %idle_time%
    @rem                      1        2     3         4              5              6
    @rem ##################################################
)


if not exist %sql% goto no_script

del %tmpdir%\%logbase%*.log 2>nul
del %tmpdir%\%logbase%*.err 2>nul

@rem Add 'signal' record into perf_log with current time (this row will be serve as 'anchor' in reports).
@rem Display start and planning finish of working time:

call :show_time_limits !tmpdir! !fbc! !dbconn! "!dbauth!" log4all

echo Launching %winq% ISQL sessions:
echo off

call :repl_with_bound_quotes %log4all% log4all

set run_vers=!fbsvcrun! info_server_version info_implementation
set run_stat=!fbsvcrun! action_db_stats sts_hdr_pages dbname %dbnm%

(
    echo set heading off; 
    echo -- NB: here we pass %test_time% value as argument A_TEST_TIME_MINUTES for SP SRV_GET_REPORT_NAME: this value
    echo -- mean that we want to get ESTIMATED name of report with '0000' as performance score - rather that ACTUAL name
    echo -- which will be obtained AFTER test will finish, see call from 'oltp_isql_run_worker.bat':
    echo select report_file 
    echo from srv_get_report_name( 
    echo    '%file_name_with_test_params%', -- = value of config parameter 'file_name_with_test_params'
    echo    '%fbb%', -- = FB build number, full or only last 5 digits
    echo     %winq%, -- = number of launched ISQL sessions, command-line argument of this batch
    echo     %test_time% --  = value of config parameter 'test_time', must be ZERO or POSITIVE
    echo ^);
    echo set heading on;
) > %tmpsql%

(
  echo !time!. Obtaining name of final report when config parameter 'file_name_with_test_params' = %file_name_with_test_params%.
  echo Run: !run_isql! 1^>%tmpclg% 2^>%tmperr%  
) >>%log4tmp%

%run_isql% 1>%tmpclg% 2>%tmperr%
    
if not .%file_name_with_test_params%.==.. (
    for /f %%a in (!tmpclg!) do (
        set log_with_params_in_name=!tmpdir!\%%a
        call :repl_with_bound_quotes !log_with_params_in_name! log_with_params_in_name
    )
    echo Final report will be saved with name = !log_with_params_in_name!.txt >> %log4tmp%
) else (
    set log_with_params_in_name=%log4all%
    echo Final report will be saved with name = %log4all% >> %log4tmp%
)

del %tmpsql% 2>nul
del %tmpclg% 2>nul
del %tmperr% 2>nul

for /l %%i in (1, 1, %winq%) do (

    echo|set /p=.

    set /a k=1000+%%i
    if .%%i.==.1. (
        (
            echo.
            echo Obtain server version and implementation info:
            echo.
        )>>%log4all%


        %run_vers% 1>>%log4all% 2>%tmperr%

        call :catch_err run_vers !tmperr! n/a nofbvers
        del %tmperr% 2>nul

        (
            echo.
            echo Obtain database header statistics BEFORE test:
            echo.
        )>>%log4all%

        %run_stat% 1>>%log4all% 2>%tmperr%

        call :catch_err run_stat !tmperr! n/a failed_fbsvc

        (
            echo.
            echo %date% %time% Done. Now launch %winq% ISQL sessions.
        )>>%log4all%
    )

    @rem Sample of %tmpdir%\%logbase%-!k:~1,3!: "C:\TEMP\logs.oltp25\oltp25_CSPROG-001"
    @rem =========

    @rem #######################################################
    @rem +++    l a u n c h   w o r k i n g     I S Q L s    +++
    @rem #######################################################

    @rem oltp_isql_run_worker.bat 1 10 30 tmpdir sql log4all oltp30_CSPROG-001 WI-V3.0.0.32136
    @rem call oltp_isql_run_worker.bat %%i %winq% %fbb% tmpdir sql log4all %logbase%-!k:~1,3! %fbb% %file_name_with_test_params%

    @start /min oltp_isql_run_worker.bat %%i %winq% %fb% tmpdir sql log4all %logbase%-!k:~1,3! %fbb% %file_name_with_test_params%
    @rem                                  ^     ^     ^     ^    ^     ^           ^             ^                 ^
    @rem                                  1     2     3     4    5     6           7             8                 9

)
echo. && echo %date% %time% Done.

if .%use_external_to_stop%.==.. (
  set b4stopbase=1stoptest.tmp
  set b4stop_bat=!tmpdir!\!b4stopbase!.bat
  set b4stop_sql=!tmpdir!\!b4stopbase!.sql
  set b4stop_err=!tmpdir!\!b4stopbase!.err

  call :repl_with_bound_quotes !b4stop_bat! b4stop_bat
  call :repl_with_bound_quotes !b4stop_sql! b4stop_sql
  call :repl_with_bound_quotes !b4stop_err! b4stop_err

  (
    echo @echo off
    echo rem --------------------------------------------------------------------------------
    echo rem Generated auto, do NOT edit.
    echo rem This batch can be used in order to immediatelly STOP all working ISQL sessions.
    echo rem It is highly rtecommended to use this batch for that goal rather than brute kill
    echo rem ISQL sessions or use Firebird monitoring tables.
    echo rem --------------------------------------------------------------------------------
    echo setlocal enabledelayedexpansion enableextensions
    echo echo ^^!time^^!. Start batch for asynchronous stop all working ISQL sessions:
    echo (
    echo     echo set list on; 
    echo     echo -- set echo on;
    echo     echo set term #;
    echo     echo execute block returns("Cancelling test, start at:" timestamp, "'g_stop_test' value:" bigint^^^) as
    echo     echo begin
    echo     echo     "Cancelling test, start at:" = current_timestamp;
    echo     echo     "'g_stop_test' value:" = gen_id(g_stop_test, 0^^^);
    echo     echo     suspend;
    echo     echo end
    echo     echo #
    echo     echo alter sequence g_stop_test restart with -999999999
    echo     echo #
    echo     echo commit
    echo     echo #
    echo     echo execute block returns("Cancelling test, finish at:" timestamp, "'g_stop_test' value:" bigint^^^) as
    echo     echo begin
    echo     echo     "Cancelling test, finish at:" = current_timestamp;
    echo     echo     "'g_stop_test' value:" = gen_id(g_stop_test, 0^^^);
    echo     echo     suspend;
    echo     echo end
    echo     echo #
    echo ^) ^> !b4stop_sql!
    echo.
    echo !fbc!\isql !dbconn! !dbauth! -q -n -nod -i !b4stop_sql! 2^>!b4stop_err!
    echo.
    echo for %%%%a in (!b4stop_err!^) do (
    echo     if not %%%%~za lss 1 (
    echo         echo ^^!time^^! ### ACHTUNG ###
    echo         echo.
    echo         echo ISQL that tried to send stop-signal finished with ERROR.
    echo         echo.
    echo         echo Check file !b4stop_err!:
    echo         echo ++++++++++++++++++++++++++++++
    echo         type !b4stop_err!
    echo         echo ++++++++++++++++++++++++++++++
    echo     ^) else (
    echo         del !b4stop_sql!
    echo         del !b4stop_err!
    echo         echo ^^!time^^! Batch finished OK. ISQL sessions can be alive a few minutes - it depends on current workload.
    echo         echo Note: one of ISQL sessions will close much later: it will create report of test results.
    echo     ^)
    echo ^)
  ) >!b4stop_bat!
  echo.
  echo In order to premature stop all working ISQL sessions run following batch:
  echo.
  echo !b4stop_bat!
  echo.
) else (
  echo.
  echo In order to premature stop all working ISQL sessions open server-side file 'stoptest.txt' in editor and
  echo type there any single ascii character plus LF. Save this file (on Windows use 'Save as...' + overwrite^).
  echo This file should be in the directory which depends on value of FB config 'ExternalFileAccess' parameter.
  echo.
)

echo Config params, running commands and results see in file(s): 

echo 1. TEXT: !log_with_params_in_name!.txt
if .%make_html%.==.1. (
  echo 2. HTML: !log_with_params_in_name!.html
  @rem %tmpdir%\oltp%fb%.report.html
) else (
  echo 2. HTML report will NOT be created. Change config parameter 'make_html' to 1 if you want to see it.
)

@rem -- dis, too many messages on the screen --echo.
@rem -- dis, too many messages on the screen --if .%file_name_with_test_params%.==.1. (
@rem -- dis, too many messages on the screen --  echo PS. You may to change config parameter 'file_name_with_test_params' to 0 in order
@rem -- dis, too many messages on the screen --  echo to have final report file with SHORT name = "%log4all%"
@rem -- dis, too many messages on the screen --) else (
@rem -- dis, too many messages on the screen --  echo PS. You may to change config parameter 'file_name_with_test_params' to 1 in order 
@rem -- dis, too many messages on the screen --  echo to have final report file with LONG name which includes all valuable FB, DB and test settings.
@rem -- dis, too many messages on the screen --)

goto :end_of_test

@rem ##########################    E N D     O F     M A I N    B L O C K   ######################

:no_arg1
    @echo off
    cls
    echo.
    echo.
    echo Please specify:
    echo arg #1 =  25 ^| 30 -- version of Firebird for which to make database objects.
    echo arg #2 =  ^<N^> -- number of ISQL sessions to be opened.
    echo.
    echo Valid variants:
    echo.
    echo    %~f0 25 ^<N^> - for Firebird 2.5
    echo.
    echo    %~f0 30 ^<N^> - for Firebird 3.0
    echo.
    echo Where ^<N^> must be greater than 0.
    echo.
    echo Press any key to FINISH this batch file. . .
    @pause>nul
    @goto final

:no_env
    @echo off
    echo.
    echo #######################################################
    echo Missed at least one of necessary environment variables.
    echo #######################################################
    echo,
    echo Check %cfg% file!
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:bad_fbc_path
    @echo off
    echo.
    echo There is NO Firebird command line utilities in the folder defined by
    echo variable 'fbc' = ^>^>^>%fbc%^<^<^<
    echo.
    echo This folder has to contain following executeble files: isql, gfix, fbsvcmgr
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:bad_dbnm
    @echo off
    echo.
    echo Invalid name for database in %cfg% file: ^>%dbnm%^<
    echo.
    echo If you want that database being auto-created:
    echo 1) ensure that it specified as full path and file name rather than alias;
    echo 2) ensure that all folders in its path already exists on the host;
    echo 3) ensure that its name meet requirements of OS where Firebird runs;
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:unavail_db
    @echo off
    echo.
    echo Can not access to database file.
    echo.
    echo Ensure that Firebird is running on specified host.
    if .%is_embed%.==.1. (
        echo.
        echo NOTE: check Windows registry, HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\FirebirdServer^<Instance Name^>!
        echo Message "unavailable database" can appear when ImagePath contains command key "-i" which allows only connections
        echo by remote protocol and disables XNet.
    )
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:bad_ods
    @echo off
    echo.
    echo Database ^>%dbnm%^< DOES exist but it has been created in later FB version.
    echo.
    echo 1. Ensure that you have specified proper value of 1st argument to this batch.
    echo 2. Check value of 'dbnm' parameter in file %cfg%
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:db_offline
    @echo off
    echo.
    echo Database ^>%dbnm%^< DOES exist but is OFFLINE now. Test can not start.
    echo Run first:
    echo            gfix -online %dbconn% %dbauth%
    echo.
    echo Press any key to FINISH. . .
    @pause>nul
    goto final

:db_read_only
    @echo off
    echo.
    echo Database ^>%dbnm%^< DOES exist but in READ ONLY mode now. Test can not start.
    echo Run first:
    echo            gfix -mode read_write %dbconn% %dbauth%
    echo.
    echo Press any key to FINISH. . .
    @pause>nul
    goto final

:build_not_finished
    @echo off
    echo.
    echo Host: ^>%host%^<
    echo Port: ^>%port%^<
    echo Database: ^>%dbnm%^<
    echo.
    echo Building of database objects was INTERRUPTED or NOT STARTED.
    echo Erase this database and try to run again this batch.
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:no_script
    @echo off
    echo.
    echo THERE IS NO .SQL SCRIPT FOR SPECIFIED SCENARIO ^>^>^>%1^<^<^<
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:err_setenv
    @echo off
    echo.
    echo Config file: %cfg% - can NOT set some of environment variables.
    echo Perhaps, there is no equal sign ("=") between name and value in some line.
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:test_canc
    @echo off
    echo.
    echo ##################################################################################
    echo FILE 'stoptest.txt' ON SERVER SIDE HAS NON-ZERO SIZE, MAKE IT EMPTY TO START TEST!
    echo ##################################################################################
    echo.
    if .%wait_if_not_exists%.==.1. (
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    EXIT

:err_del

    @echo off
    cls
    echo.
    echo Batch running now: %~f0
    echo.
    echo Can`t delete file (.sql or .log) - probably it is opened in another window!
    echo.
    echo Press any key to FINISH. . .
    echo.
    @pause>nul
    @goto final

:gen_working_sql
      setlocal
      @echo off

      set mode=%1

      @rem Usually smth like: C:\TEMP\logs.oltpNN\sql\tmp_random_run.sql

      set sql=%2

      @rem Number of repeated pairs {execute_block, commit} in the file %sql%
      set lim=%3

      @rem should NO AUTO UNDO clause be added in SET TRAN command ? 1=yes, 0=no

      if .%4.==.1. set nau=NO AUTO UNDO

      @rem should detailed info for each iteration be added in log ?
      @rem (actual only for mode=run_test; if "1" then add select * from %log_tab%)

      set nfo=%5

      @rem How many seconds each ISQL worker should be idle between transactions (only when mode='run_test')
      set idle=%6

      del %sql% 2>nul
      echo.
      echo SQL generating routine `gen_working_sql`, input arguments:
      echo         1) Mode:                          ^|%mode%^|
      echo         2) Creating SQL script:           ^|%sql%^|
      echo         3) Number of execute blocks:      ^|%lim%^|
      echo         4) Tx auto_undo clause:           ^|%nau%^|
      echo         5) Output records from perf_log:  ^|%nfo%^|
      echo         6) Make idle between Tx, seconds: ^|%idle%^|

      @echo -- ### WARNING: DO NOT EDIT ###>>%sql%
      @echo -- GENERATED AUTO BY %~f0>>%sql%

      if /i .%mode%.==.init_pop. (
          (
            echo -- For check settings of database.
            echo -- NB-1: FW must be (temply^) set to OFF
            echo -- NB-2: cache buffers temply set to pretty big value
            echo set list on;
            echo select * from mon$database;
            echo set list off;
          )>>%sql%
      ) else (
          del !tmpdir!\tmp_longsleep.tmp 2>nul
          (
            echo ' Generated AUTO by %~f0, do NOT edit.
            echo ' This file is used by Windows CSCRIPT.EXE as dummy scenario.
            echo ' Cscript is called via SHELL from %sql%
            echo ' after every COMMIT statement.
            echo WScript.Sleep(900000^)
          )>>!tmpdir!\tmp_longsleep.tmp
      )

      echo.>>%sql%
      echo.
      for /l %%i in (1, 1, %lim%) do (

        set /a k = %%i %% 50
        if !k! equ 0 echo Generating SQL script for work, iter # %%i of total %lim%

        (
            echo.
            echo ------ Routine: gen_working_sql, mode = %mode%, start iter # %%i of %lim% ------
            echo.
        ) >> %sql%

        if %%i equ 1 (
            echo commit; >> %sql%
        ) else (
          if /i .%mode%.==.run_test. (
            if .%idle%. gtr .0. (

              (
                echo -- Take relax between transactions, value after '//t:' is number of
                echo -- SECONDS and is equal to 'idle_time' parameter in !cfg! file.
                echo set list on;
                echo set transaction read only read committed;
                echo select current_timestamp as "Pause %idle% seconds starting at: "
                echo from rdb$database;
                echo ----------------------------- p a u s e--------------------------------
                echo shell cscript //e:vbscript //t:%idle% !tmpdir!\tmp_longsleep.tmp ^>nul;
                echo -----------------------------------------------------------------------
                echo select current_timestamp as "Pause %idle% seconds finished at: "
                echo from rdb$database;
                echo commit;
                echo set list off;
                echo.
              )>>%sql%

            ) else (

              (
                echo.
                echo -- Pause between transactions is DISABLED.
                echo -- For enabling them set value of 'idle_time' parameter
                echo -- in !cfg! file to some value ^> 0.
                echo.
              )>>%sql%

            )
          )
        )


        (
            echo,
            echo -- ##################################
            echo -- S T A R T    T R A N S A C T I O N
            echo -- ##################################
            echo.
            echo set transaction no wait %nau%; -- check oltp%fb%_config.win for optional setting NO AUTO UNDO
            echo.
            echo ------ ##############################################  -------
            echo -----  R A N D O M    S E L E C T    A P P.   U N I T  -------
            echo ------ ##############################################  -------
            echo set term ^^;
            echo execute block as
            echo     declare v_unit dm_name;
            echo begin
            echo   if ( NOT exists( select * from sp_stoptest ^) ^) then
            echo       begin
        )>>%sql%

        if /i .%mode%.==.init_pop. (
          @rem When database is filled up by initial data one need only to:
          @rem 1. Add NEW documents or 
          @rem 2. Change state of existing docs
          @rem -- but we do NOT have to run any cancel operations:
          (
            echo           select p.unit
            echo           from srv_random_unit_choice(
            echo                   '',
            echo                   'creation,state_next,service,',
            echo                   '',
            echo                   'removal'
            echo           ^) p
            echo           into v_unit;
          )>>%sql%
        )

        if /i .%mode%.==.run_test. (
          (
            echo           select p.unit
            echo           from srv_random_unit_choice(
            echo                   '',
            echo                   '',
            echo                   '',
            echo                   ''
            echo           ^) p
            echo           into v_unit;
          )>>%sql%
        )

        (
          echo         end
          echo   else
          echo         v_unit = 'TEST_WAS_CANCELLED';
          echo   rdb$set_context('USER_SESSION','SELECTED_UNIT', v_unit^);
          echo   rdb$set_context('USER_SESSION','ADD_INFO', null^);
          echo end
          echo ^^
          echo set term ;^^
        )>>%sql%


        if /i .%mode%.==.run_test. (
          if /i .%mon_unit_perf%.==.1. (
            (
                echo ------ ###############################################  -------
                echo -----  G A T H E R    M O N.    D A T A    B E F O R E  -------
                echo ------ ###############################################  -------
                echo set term ^^;
                echo execute block as
                echo   declare v_dummy bigint;
                echo begin
                echo   rdb$set_context('USER_SESSION','MON_GATHER_0_BEG', datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp^) to cast('now' as timestamp^) ^) ^);
                echo   -- define context var which will identify rowset field
                echo   -- in mon_log and mon_log_table_stats:
                echo   -- (this value is ised after call app. unit^):
                echo   rdb$set_context('USER_SESSION','MON_ROWSET', gen_id(g_common,1^)^);
                echo.
                echo   -- Gather mon$ tables BEFORE run app unit.
                echo   -- Add FIRST row to GTT tmp$mon_log - statistics on 'per unit' basis.
                echo   -- Note: for FB 3.0 - also add first rowset into table tmp$mon_log_table_stats.
                echo   select count(*^)
                echo   from srv_fill_tmp_mon(
                echo           rdb$get_context('USER_SESSION','MON_ROWSET'^)    -- :a_rowset
                echo          ,1                                                -- :a_ignore_system_tables
                echo          ,rdb$get_context('USER_SESSION','SELECTED_UNIT'^) -- :a_unit
                echo                       ^)
                echo   into v_dummy;
                echo.
                echo   -- result: tables tmp$mon_log and tmp$mon_log_table_stats
                echo   -- are filled with counters BEFORE application unit call.
                echo   -- Field `mult` in these tables is now negative: -1
                echo   rdb$set_context('USER_SESSION','MON_GATHER_0_END', datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp^) to cast('now' as timestamp^) ^) ^);
                echo end
                echo ^^
                echo set term ;^^
                echo commit; --  ##### C O M M I T  #####  after gathering mon$data
                echo set transaction no wait %nau%;
            )>>%sql%
          ) else (
            (
                echo -- Gathering statistics data from MON$ tables DISABLED.
                echo -- For enabling it set value of config parameter 'mon_unit_perf' to 1.
            )>>%sql%
          )
        )

        (
            echo set width dts 12;
            echo set width trn 14;
            echo set width att 14;
            echo set width unit 31;
            echo set width elapsed_ms 10;
            echo set width msg 16;
            echo set width add_info 40;
            echo set width mon_logging_info 20;

            echo -- ensure that just before call application unit
            echo -- table tmp$perf_log is really EMPTY:
            echo delete from tmp$perf_log;

            if !k! gtr 0 (
                echo set heading off;
                echo select lpad('',40,'+'^) ^|^| ' Action # %%i of %lim% ' ^|^| rpad('',40,'+'^) as " "
                echo from rdb$database;
                echo set heading on;
            )
            echo --------------- before run app unit: show it's NAME --------------
            echo set list off;
            echo select
            echo     substring(cast(current_timestamp as varchar(24^)^) from 12 for 12^) as dts
            echo     ,'tra_'^|^|current_transaction                                      as trn
            echo     ,'att_'^|^|current_connection                                       as att
            echo     , rdb$get_context('USER_SESSION','SELECTED_UNIT'^)                  as unit
            echo     ,'start'                                                            as msg
            echo     ,'iter # %%i  of %lim%'                                             as add_info
            echo from rdb$database;

            echo.
            echo SET STAT ON;
            echo.
            echo set term ^^;
            echo execute block as
            echo     declare v_stt varchar(128^);
            echo     declare result int;
            echo     declare v_old_docs_num int;
            echo     declare v_success_ops_increment int;
            echo begin
        )>>%sql%

        if /i .%mode%.==.init_pop. (
          (
            echo     -- ::: nb ::: g_init_pop is always incremented by 1
            echo     -- in sp_add_doc_list, even if fault will occur later
            echo     -- set context var 'INIT_DATA_POP' to not-null for analyzing
            echo     -- in sp_customer_reserve and others SPs and raise e`ception
            echo     rdb$set_context('USER_TRANSACTION','INIT_DATA_POP',1^);
            echo     v_old_docs_num = gen_id( g_init_pop, 0^);
          )>>%sql%
        )


        (
          echo     begin
          echo         -- save in ctx var timestamp of START app unit:
          echo         rdb$set_context('USER_SESSION','BAT_PHOTO_UNIT_DTS', cast('now' as timestamp^)^);
          echo         rdb$set_context('USER_SESSION', 'GDS_RESULT', null^);
          echo         -- save value of current_transaction because we make COMMIT
          echo         -- after gathering mon$ tables when oltp_config.NN parameter
          echo         -- mon_unit_perf=1
          echo         rdb$set_context('USER_SESSION', 'APP_TRANSACTION', current_transaction^);
          echo.
          echo         if ( rdb$get_context('USER_SESSION','SELECTED_UNIT'^)
          echo              is distinct from
          echo              'TEST_WAS_CANCELLED'
          echo           ^) then
          echo           begin
          echo               rdb$set_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT', null ^);
          echo               v_stt='select count(*^) from '
          echo               ^|^|rdb$get_context('USER_SESSION','SELECTED_UNIT'^);
          echo               ------   ######################################### ------
          echo               ------   r u n    a p p l i c a t i o n    u n i t ------
          echo               ------   ######################################### ------
          echo               execute statement (v_stt^) into result;
          echo.            
          echo               rdb$set_context('USER_SESSION', 'RUN_RESULT',
          echo                               'OK, '^|^| result ^|^|' rows'^);
          echo.
          echo               -- Get count of 'atomic' business operations that occured 'under-cover' of SELECTED_UNIT:
          echo               v_success_ops_increment = cast(rdb$get_context('USER_TRANSACTION', 'BUSINESS_OPS_CNT'^) as int^);
          echo.
          echo               ---------------------------------------------------------------
          echo               -- Increment counter of SUCCESSFULLY finished business asctions
          echo               -- for using later in ESTIMATED performance value:
          echo               ---------------------------------------------------------------
          echo               result = gen_id( g_success_counter, v_success_ops_increment ^);
          echo           end
          echo         else
          echo             begin
          echo                rdb$set_context('USER_SESSION','RUN_RESULT',
          echo                                 (select coalesce(e.fb_mnemona, 'gds_'^|^|g.fb_gdscode^)
          echo                                  from perf_log g
          echo                                  left join fb_errors e on g.fb_gdscode=e.fb_gdscode
          echo                                  where g.unit='sp_halt_on_error'
          echo                                  order by g.dts_end DESC rows 1
          echo                                 ^)
          echo                               ^);
          echo             end
          echo.
          echo         -- add timestamp for FINISH app unit:
          echo         rdb$set_context( 'USER_SESSION','BAT_PHOTO_UNIT_DTS',
          echo                          rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^)
          echo                          ^|^| ' '
          echo                          ^|^| cast('now' as timestamp^)
          echo                       ^);
          echo     when any do
          echo         begin
          echo            rdb$set_context('USER_SESSION', 'GDS_RESULT', gdscode^);
        )>>%sql%

        if /i .%mode%.==.init_pop. (
          (
            echo            v_stt = 'alter sequence g_init_pop restart with '
            echo                    ^|^|v_old_docs_num;
            echo            execute statement (v_stt^);
          )>>%sql%
        )

        (
          echo            rdb$set_context('USER_SESSION', 'RUN_RESULT', 'error, gds='^|^|gdscode^);
          echo            exception;
          echo         end
          echo     end
          echo end
          echo ^^
          echo set term ;^^
          echo.
          echo SET STAT OFF;
          echo.

        )>>%sql%



        if /i .%mode%.==.run_test. (
          if /i .%mon_unit_perf%.==.1. (
            (
                echo ------ ###############################################  -------
                echo -----  G A T H E R    M O N.    D A T A    A F T E R    -------
                echo ------ ###############################################  -------
                echo set term ^^;
                echo execute block as
                echo   declare v_dummy bigint;
                echo begin
                echo   rdb$set_context('USER_SESSION','MON_GATHER_1_BEG', datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp^) to cast('now' as timestamp^) ^) ^);
                echo   -- Gather mon$ tables BEFORE run app unit.
                echo   -- Add second row to GTT tmp$mon_log - statistics on 'per unit' basis.
                echo   -- Note: for FB 3.0 - also add first rowset into table tmp$mon_log_table_stats.
                echo   select count(*^) from srv_fill_tmp_mon
                echo   (
                echo           rdb$get_context('USER_SESSION','MON_ROWSET'^)    -- :a_rowset
                echo          ,1                                                -- :a_ignore_system_tables
                echo          ,rdb$get_context('USER_SESSION','SELECTED_UNIT'^) -- :a_unit
                echo          ,coalesce(                                        -- :a_info
                echo                rdb$get_context('USER_SESSION','ADD_INFO'^) -- aux info, set in APP units only!
                echo               ,rdb$get_context('USER_SESSION','RUN_RESULT'^)
                echo              ^)
                echo          ,rdb$get_context('USER_SESSION', 'GDS_RESULT'^)   -- :a_gdscode
                echo   ^)
                echo   into v_dummy;
                echo   rdb$set_context('USER_SESSION','MON_GATHER_1_END', datediff(millisecond from cast('01.01.2015 00:00:00' as timestamp^) to cast('now' as timestamp^) ^) ^);
                echo.
                echo   -- add pair of rows with aggregated differences of mon$
                echo   -- counters from GTT to fixed tables
                echo   -- (this SP also removes data from GTTs^):
                echo   select count(*^)
                echo   from srv_fill_mon(
                echo                      rdb$get_context('USER_SESSION','MON_ROWSET'^) -- :a_rowset
                echo                    ^)
                echo   into v_dummy;
                echo   rdb$set_context('USER_SESSION','MON_ROWSET', null^);
                echo end
                echo ^^
                echo set term ;^^
                echo commit; --  ##### C O M M I T  #####  after gathering mon$data
                echo set transaction no wait %nau%;
            )>>%sql%
          )
        )

        if /i .!mode!.==.run_test. (

            echo set list on; >>%sql%

            if %%i equ 1 (
               (
                  echo select left( cast( p.dts_end as varchar(24^) ^), 19 ^)
                  echo      as test_ends_at
               )>>%sql%
            ) else (
              (
                  
                  echo select
                  echo     -- Variable 'PERF_WATCH_END' is assigned with value from table PERF_LOG, see SP sp_check_to_stop_work:
                  echo     -- ... from perf_log where p.unit = 'perf_watch_interval' and p.info containing 'active'
                  echo     left( cast( rdb$get_context('USER_SESSION','PERF_WATCH_END'^) 
                  echo                 as varchar(24^)
                  echo             ^),
                  echo           19
                  echo        ^)
                  echo     as test_ends_at
              )>>%sql%
            )

            (
                  echo     ,rdb$get_context('USER_SESSION','GDS_RESULT'^) as last_operation_gds_code
                  echo     ,lpad( iif( minutes_since_start ^>0, 1.00 * success_ops_count / minutes_since_start, 0 ^), 12, ' ' ^)
                  echo      ^|^|
                  echo      lpad( minutes_since_start, 7, ' ' ^)
                  echo      as est_overall_at_minute_since_beg
                  if /i .%mon_unit_perf%.==.1. (
                      echo      -- this variable will be defined in SP srv_fill_mon:
                      echo     ,rdb$get_context('USER_SESSION','MON_INFO'^) as mon_logging_info
                      echo     ,cast( rdb$get_context('USER_SESSION','MON_GATHER_0_END'^) as bigint^) - cast( rdb$get_context('USER_SESSION','MON_GATHER_0_BEG'^) as bigint^) 
                      echo    + cast( rdb$get_context('USER_SESSION','MON_GATHER_1_END'^) as bigint^) - cast( rdb$get_context('USER_SESSION','MON_GATHER_1_BEG'^) as bigint^) 
                      echo     as mon_gathering_time_ms
                      echo     ,rdb$get_context('USER_SESSION','TRACED_UNITS'^) as traced_units
                  ) else (
                      echo    ,'MON$ querying DISABLED, see config ''mon_unit_perf''' as mon_logging_info
                  )
                  echo    ,rdb$get_context('USER_SESSION','WORKING_MODE'^) as workload_type
                  echo    ,rdb$get_context('USER_SESSION','HALT_TEST_ON_ERRORS'^) as halt_test_on_errors
                  echo    ,rdb$get_context('USER_SESSION','QMISM_VERIFY_BITSET'^) as qmism_verify_bitset
            )>>%sql%

            (
                echo from
                echo (
                echo     select 
                echo         gen_id( g_success_counter, 0 ^) as success_ops_count
                echo        ,datediff( minute
                echo                   -- Variable 'PERF_WATCH_BEG' is assigned with value from table PERF_LOG, see SP sp_check_to_stop_work:
                echo                   -- ... from perf_log where p.unit = 'perf_watch_interval' and p.info containing 'active'.
                echo                   -- We need to substract %warm_time% from the moment PERF_WATCH_BEG because sequence
                echo                   -- of successfully finished business ops is increased from ACTUAL start rather than 
                echo                   -- timestamp PERF_WATCH_BEG which is used for reports:
                echo                   from dateadd( -%warm_time% minute to cast( rdb$get_context('USER_SESSION','PERF_WATCH_BEG'^) as timestamp^) ^) 
                echo                     to current_timestamp
                echo                ^)   -- datediff minus config "warm_time" value
                echo         as minutes_since_start
                if %%i equ 1 (
                    echo        ,p.dts_end
                    echo     from %log_tab% p
                    echo     where p.unit = 'perf_watch_interval'
                    echo     order by dts_beg desc
                    echo     rows 1
                ) else (
                    echo     from rdb$database
                )
                echo ^) p;
                echo set list off;
            )>>%sql%
        )

        
        (
          echo -- Output results of application unit run:
          echo set width msg 20;
          echo select
          echo     substring(cast(current_timestamp as varchar(24^)^) from 12 for 12^) as dts
          echo     ,'tra_'^|^|rdb$get_context('USER_SESSION','APP_TRANSACTION'^) trn
          echo     ,rdb$get_context('USER_SESSION','SELECTED_UNIT'^) as unit
          echo     ,lpad(
          echo            cast(
          echo                  datediff(
          echo                    millisecond
          echo                    from cast(left(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^),24^) as timestamp^)
          echo                    to   cast(right(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^),24^) as timestamp^)
          echo                         ^)
          echo                 as varchar(10^)
          echo                ^)
          echo           ,10
          echo           ,' '
          echo         ^) as elapsed_ms
          echo     ,rdb$get_context('USER_SESSION', 'RUN_RESULT'^) as msg
          echo     ,rdb$get_context('USER_SESSION','ADD_INFO'^) as add_info
          echo from rdb$database;
        )>>%sql%

        if /i .%mode%.==.init_pop. (
          (
            echo set list on;
            echo set width db_name 80;
            echo select
            echo     m.mon$database_name db_name,
            echo     rdb$get_context('SYSTEM','ENGINE_VERSION'^) engine,
            echo     MON$FORCED_WRITES db_forced_writes,
            echo     MON$PAGE_BUFFERS page_buffers,
            echo     m.mon$page_size * m.mon$pages as db_current_size,
            echo     gen_id(g_init_pop,0^) as new_docs_created
            echo from mon$database m;
          )>>%sql%
        )

        (
          echo set bail on; -- for catch test cancellation and stop all .sql
          echo set term ^^;
          echo execute block as
          echo begin
          echo     if ( rdb$get_context('USER_SESSION','SELECTED_UNIT'^)
          echo          is NOT distinct from
          echo          'TEST_WAS_CANCELLED'
          echo       ^) then
          echo     begin
          echo        exception ex_test_cancellation;
          echo     end
          echo     -- REMOVE data from context vars, they will not be used more
          echo     -- in this iteration:
          echo     rdb$set_context('USER_SESSION','SELECTED_UNIT', null^);
          echo     rdb$set_context('USER_SESSION','RUN_RESULT',    null^);
          echo     rdb$set_context('USER_SESSION','GDS_RESULT',    null^);
          echo     rdb$set_context('USER_SESSION','ADD_INFO', null^);
          echo     rdb$set_context('USER_SESSION','APP_TRANSACTION', null^);
          echo     rdb$Set_context('USER_SESSION','MON_GATHER_0_BEG', null^);
          echo     rdb$Set_context('USER_SESSION','MON_GATHER_0_END', null^);
          echo     rdb$Set_context('USER_SESSION','MON_GATHER_1_BEG', null^);
          echo     rdb$Set_context('USER_SESSION','MON_GATHER_1_END', null^);
          echo end
          echo ^^
          echo set term ;^^
          echo set bail off;
        )>>%sql%

        if /i .%mode%.==.run_test. (
          if .%nfo%.==.1. (
            (
              echo -- Begin block to output DETAILED results of iteration.
              echo -- To disable this output change "detailed_info" setting to 0
              echo -- in test configuration file "%cfg%"
              echo set heading off;
              echo set list on;
              echo select '+++++++++  perf_log data for this Tx: ++++++++' as msg
              echo from rdb$database;
              echo set heading on;
              echo set list on;
              echo set width unit 35;
              echo set width info 80;
              echo select g.id, g.unit, g.exc_unit, g.info, g.fb_gdscode,g.trn_id,
              echo        g.elapsed_ms, g.dts_beg, g.dts_end
              echo from perf_log g
              echo where g.trn_id = current_transaction;
              @rem do NOT:   echo order by id;
              echo set list off;
              echo -- Finish block to output DETAILED results of iteration.
            )>>%sql%

          ) else (

            (
              echo.
              echo -- Output of detailed results of iteration DISABLED.
              echo -- To enable this output change "detailed_info" setting to 1
              echo -- in test configuration file "%cfg%"
            )>>%sql%
          )
          @echo.>>%sql%
        )

        (
          echo commit;
          echo set list off;
        )>>%sql%

        @rem ###############################
        @rem DO NOT CHANGE FINAL MESSAGE: "FINISH packet" - it is used in decision about whether this .sql should be recreated or no.
        @rem ###############################

        if %%i equ %lim% (
          (
            echo set width msg 60;
            echo select
            echo     current_timestamp dts,
            echo     '### FINISH packet, disconnect ###' as msg
            echo from rdb$database;
          )>>%sql%
        )

      )

  endlocal

goto:eof

:getFileDTS
    @rem http://www.dostips.com/DtTutoFunctions.php
    setlocal
    set vbs=!tmpdir!\getFileTimeStamp.tmp.vbs
    set dts=!tmpdir!\getFileTimeStamp.tmp.log
    if /i .%1.==.gen_vbs. (
      del %vbs% 2>nul

      (
        echo 'Created auto, do NOT edit!
        echo 'Used to obtain exact timestamp of file
        echo 'Usage: cscript ^/^/nologo %vbs% ^<file^>
        echo 'Result: last modified timestamp, in format: YYYYMMDDhhmiss
        echo Set objFS ^= CreateObject("Scripting.FileSystemObject"^)
        echo Set objArgs ^= WScript.Arguments
        echo strFile ^= objArgs(0^)
        echo ts ^= timeStamp(objFS.GetFile(strFile^).DateLastModified^)
        echo WScript.  echo ts
        echo.
        echo Function timeStamp( d ^)
        echo   timeStamp ^= Year(d^) ^& _
        echo   Right("0" ^& Month(d^),2^) ^& _
        echo   Right("0" ^& Day(d^),2^)  ^& _
        echo   Right("0" ^& Hour(d^),2^) ^& _
        echo   Right("0" ^& Minute(d^),2^) ^& _
        echo   Right("0" ^& Second(d^),2^)
        echo End Function
      )>>%vbs%

      endlocal&goto:eof
    )

    if /i .%1.==.get_dts. (

      echo|set /p=Obtaining timestamp of %2...
      cscript //nologo %vbs% %2 1>%dts%
      type %dts%
      endlocal&set /p %~3=<%dts%
    )
    endlocal

goto:eof


:prepare
    @rem Works Ok: create database 'localhost/3255:c:\TEMP\test fdb 2 5\e 2 1.fdb'; -- remove any quotes from path and file name

    setlocal

    call :try_create_db

    call :make_db_objects %fb% !tmpdir! !fbc! !dbnm! !dbconn! "!dbauth!" %create_with_split_heavy_tabs%

    if .%wait_after_create%.==.1. (
        echo.
        echo Database has been created SUCCESSFULLY and is ready for initial documents filling.
        echo ######################################
        echo.
        echo Change config setting 'wait_after_create' to 0 in order to remove this pause.
        echo.
        echo Press any key to go on or Ctrl-C to exit. . .
        pause >nul
    )
    endlocal
goto:eof

:replace_quotes_and_spaces
    setlocal
    set result=%1
    set result=!result: =*!
    set result=!result:"=|!
    endlocal&set "%~2=%result%"
goto:eof

:try_create_db


    setlocal

    echo.
    set msg=Internal routine: try_create_db.
    echo %msg% & echo %msg% >>%log4tmp%

    echo.
    @rem If we are here than database is absent. Suggest to create it but only in case when
    @rem %dbnm% contains slashes (forwarding for LInux and backward for WIndows)

    set unquoted_dbnm=!dbnm:"=!

    if /i .%fbo%.==.LI. (
        for /f "tokens=1,2 delims=/" %%a in ("%unquoted_dbnm%") do (
            set w1=%%a
            set w2=%%b
        )
    ) else if /i .%fbo%.==.WI. (
        for /f "tokens=1,2 delims=\" %%a in ("%unquoted_dbnm%") do (
            set w1=%%a
            set w2=%%b
        )
    )

    if not defined w1 (
        goto bad_dbnm
    )

    if not defined w2 (
        goto bad_dbnm
    )

    @echo off
    echo.
    echo Database ^|%dbnm%^| will be created on host ^|%host%^| with following attrubites:
    echo.
    echo Forced Writes:  ^|%create_with_fw%^|
    echo Sweep Interval: ^|%create_with_sweep%^|
    echo.


    set tmpsql=%tmpdir%\tmp_create_dbnm.sql
    set tmplog=%tmpdir%\tmp_create_dbnm.log
    set tmperr=%tmpdir%\tmp_create_dbnm.err

    @rem 18.09.2015 0258
    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr


    set connect_only=0

    if .%is_embed%.==.1. (
        echo create database '%unquoted_dbnm%' page_size 8192; commit; show database; quit;>%tmpsql%
    ) else (
        echo create database '%host%/%port%:%unquoted_dbnm%' page_size 8192 user '%usr%' password '%pwd%'; commit; show database; quit;>%tmpsql%
    )

    echo.
    echo Attempt to CREATE database.

    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql

    set run_isql=!run_isql! -bail -q -i %tmpsql%
    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr%  >>%log4tmp%

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    )>>%log4tmp% 2>&1

    @rem If database file is opened by another FB instance than !tmperr! will contain:
    @rem `I/O error during "CreateFile (create)" operation` and `-Error while trying to create file`
    @rem Otherwise (if file just exists):
    @rem `I/O error during "open" operation` and `-database or file exists`

    @rem Search for any of words: 'createfile' or 'exists'. If it will be found than we must only make test connect.
    findstr /i "createfile exists" !tmperr! 1>nul
    if not errorlevel 1 (
        set connect_only=1
        echo.
        set msg=Database EXISTS, so we check only ability to CONNECT.
        echo !msg! & echo !msg!>>%log4tmp%

        del !tmpsql! 2>nul
        del !tmperr! 2>nul
        (
            if .%is_embed%.==.1. (
                echo connect '%unquoted_dbnm%';
            ) else (
                echo connect '%host%/%port%:%unquoted_dbnm%' user '%usr%' password '%pwd%';
            )
            echo set list on;
            echo set width db_name 80;
            echo select
            echo     m.mon$database_name db_name
            echo     ,rdb$get_context('SYSTEM','ENGINE_VERSION'^) engine
            echo     ,mon$forced_writes db_forced_writes
            echo     ,mon$page_buffers page_buffers
            echo     ,m.mon$page_size * m.mon$pages as db_current_size
            echo from mon$database m;
            set rndname=!random!
            echo -- Check that database is not in read_only mode:
            echo recreate table tmp!rndname!(id int^);
            echo drop table tmp!rndname!;
            echo quit;
        ) > %tmpsql%

        echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

        %run_isql% 1>%tmplog% 2>%tmperr%

        (
            for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
            echo %time%. Got:
            for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
            for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
        )>>%log4tmp% 2>&1

    )

    call :catch_err run_isql !tmperr! !tmpsql! cant_create_or_connect

    echo|set /p=Result: Ok.
    if .!connect_only!.==.0. (
        echo  Database has been created SUCCESSFULLY.
    ) else (
        echo  Test CONNECT statement was SUCCESSFUL.
    )
    type !tmplog!

    del !tmpsql! 2>nul
    del !tmplog! 2>nul
    del !tmperr! 2>nul

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

:dequote_if_need
    setlocal
    set must_quote=-1
    set result=%1
  
    call :has_spaces %1 must_quote
    
    if .!must_quote!.==.1. set result=!result:"=!

:: http://stackoverflow.com/questions/307198/remove-quotes-from-named-environment-variables-in-windows-scripts
::     if .%must_quote%.==.1. (
::         for %%a in (%result%) do set result=%%~a
::     )

    endlocal & set "%~2=%result%"
goto:eof

:make_db_objects

    setlocal
    
    echo.
    set msg=Internal routine: make_db_objects.
    echo %msg% & echo %msg% >>%log4tmp%
    echo.

    @rem call :make_db_objects %fb% !tmpdir! !fbc! !dbname! !dbconn! "!dbauth!" %create_with_split_heavy_tabs%
    set fb=%1
    set tmpdir=%2
    set fbc=%3
    set dbname=%4
    set dbconn=%5
    set dbauth=%6
    set create_with_split_heavy_tabs=%7

    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!

    set tmpsql=%tmpdir%\%~n0_%fb%.sql
    set tmplog=%tmpdir%\%~n0_%fb%.log
    set tmperr=%tmpdir%\%~n0_%fb%.err

    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr

    del !tmplog! 2>nul
    del !tmperr! 2>nul
    del !tmpsql! 2>nul

    echo Test connect and analyze engine version for matching to arg. ^>%fb%^<

    (
        echo set list off;
        echo set heading off;
        echo set width engine 20;
        echo select 'engine='^|^|rdb$get_context('SYSTEM','ENGINE_VERSION'^) as engine
        echo from rdb$database;
        echo --set list on;
        echo --select * from mon$database;
        echo --select * from mon$attachments;
        echo --show version;
        echo quit;
    )>>%tmpsql%

    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    G h e c k     m a t c h i n g    o f    E n g i n e    a n d    u s e d     c o n f i g    :::
    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql

    set run_isql=!run_isql! %dbconn% %dbauth% -q -nod -pag 0 -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! %tmpsql%

    del %tmperr% 2>nul
    del %tmpsql% 2>nul

    set engine_err=0
    if .%fb%.==.25. (
        find /c /i "engine=2.5" %tmplog% >nul
        if errorlevel 1 set engine_err=1
    )
    if .%fb%.==.30. (
        find /c /i "engine=3.0" %tmplog% >nul
        if errorlevel 1 set engine_err=1
    )
    del %tmplog% 2>nul

    if .!engine_err!.==.1. (
        echo Actual engine version does NOT match input argument ^>%fb%^<
        echo.
        echo Check settings 'host' and 'port' in test config file.
        echo.
        echo Press any key to FINISH this batch file. . .
        @pause>nul
        goto final
    )
    echo Result: engine version DOES match to config.
    echo.
    echo #################################################
    echo Database will be created for FB ^>^>^> %fb% ^<^<^<
    echo #################################################
    echo.


    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    A d j u s t i n g     F W   a n d   S W E E P  i n t.   t o     c o n f i g    s e t t i n g   :::
    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    set msg=Temply change Forced Writes to OFF while building DB. Change Sweep Interval to config settings.
    echo %msg% & echo %msg%>>%log4tmp%

    call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" async %create_with_sweep%

    del %tmperr% 2>nul
    del %tmpsql% 2>nul

    (
        echo set bail on;
        echo show version;
        echo show database;
        echo set list on;
        echo select * from mon$database;
        echo set list off;
        @rem echo -- ?? set echo on;

        @rem these scripts DIFFERS for each version of Firebird:
        echo in "%~dp0oltp%fb%_DDL.sql";
        echo in "%~dp0oltp%fb%_sp.sql";

        @rem Following scripts are COMMON for each version of Firebird:
        if .%create_with_debug_objects%.==.1. (
          echo in "%~dp0oltp_misc_debug.sql";
        )

        echo in "%~dp0oltp_main_filling.sql";

        echo -- Inject setting which will force to create either single table QDistr
        echo -- or several clones of it with names matching to patterh 'XQD_*'.
        echo -- Similar action will be done for table QStorned and 'XQS_*' clones.
        echo insert into settings(working_mode, mcode, context,svalue,init_on^)
        echo             values(  'COMMON'                       -- working_mode
        echo                     ,'BUILD_WITH_SPLIT_HEAVY_TABS'  -- mcode
        echo                     ,'USER_SESSION'                 -- context
        echo                     ,%create_with_split_heavy_tabs%             -- value from config
        echo                     ,'db_prepare'                   -- init_on
        echo                   ^);
        echo.
        echo -- Inject setting which will force to create either one compound index for table
        echo -- QDistr (or its XQD* clones^) or split columns on two separate indices.
        echo -- When setting 'create_with_split_heavy_tabs' is 0 then one of these indices is
        echo -- still compund but contain three fields instead of four.
        echo -- When setting 'create_with_split_heavy_tabs' is 0 then each XQD* table will have
        echo -- either compound index of two fields or two single-field indices.
        echo insert into settings(working_mode, mcode, context,svalue,init_on^)
        echo             values(  'COMMON'                       -- working_mode
        echo                     ,'BUILD_WITH_SEPAR_QDISTR_IDX'  -- mcode
        echo                     ,'USER_SESSION'                 -- context
        echo                     ,%create_with_separate_qdistr_idx%             -- value from config
        echo                     ,'db_prepare'                   -- init_on
        echo                   ^);

        @rem -- 24.10.2015! -- do NOT ignore this param when create_with_split_heavy_tabs = 1 !!; was: if .%create_with_split_heavy_tabs%.==.0. (
            echo.
	    echo -- Inject setting for making columns order in compound index
	    echo -- according to the config setting 'create_with_compound_columns_order'
	    echo -- (actual only when setting 'create_with_split_heavy_tabs' = 0^):
            echo insert into settings(working_mode, mcode, context,svalue,init_on^)
            echo             values(  'COMMON'                       -- working_mode
            echo                     ,'BUILD_WITH_QD_COMPOUND_ORDR'  -- mcode
            echo                     ,'USER_SESSION'                 -- context
            echo                     ,upper('%create_with_compound_columns_order%'^) -- value from config
            echo                     ,'db_prepare'                   -- init_on
            echo                   ^);
        @rem -- )

        echo commit;

        @rem Value of %tmpdir% can be enclosed, so we have to 'inject' name of temporary file
        @rem inside all string that we give to isql `IN` command:
        
        set post_handling_out=%tmpdir%\oltp_split_heavy_tabs_%create_with_split_heavy_tabs%_%fb%.tmp
        call :repl_with_bound_quotes !post_handling_out! post_handling_out

        echo set echo off;
        echo.
        echo -- Redirect output in order to auto-creation of SQL for change DDL after main build phase:
        echo out !post_handling_out!;

        @rem result in .sql: 
        @rem out "C:\TEMP\logs of oltp emul test 25\ foo rio bar.2\oltp_split_enable_25.tmp";	
        
        echo -- This will generate SQL statements for changing DDL according to 'create_with_split_heavy_tabs' setting.
        echo in "%~dp0oltp_split_heavy_tabs_%create_with_split_heavy_tabs%.sql";
        echo.
        echo -- Result: previous OUT-command provides redirection of 
        echo -- ^|IN in "%~dp0oltp_split_heavy_tabs_%create_with_split_heavy_tabs%.sql"^|
        echo -- to the new temp file which will be applied on the next step. 
        echo -- Close current output:
        echo out;
        echo.
        echo -- Applying temp file with SQL statements for change DDL according to 'create_with_split_heavy_tabs=%create_with_split_heavy_tabs%':
        echo in !post_handling_out!;
        echo.
        @rem -- 24.10.2015: enclose update statements in EB with when-any section and suppressing lock-conflict exceptions.
        echo set term ^^;
        echo execute block as
        echo begin
        echo.
        echo     -- Inject value of config parameter `mon_unit_perf` into table SETTINGS:
        echo     update settings set svalue=%mon_unit_perf%
        echo     where working_mode=upper('common'^) and mcode=upper('enable_mon_query'^);
        echo.
        echo     -- Inject value of config parameter `working_mode` into table SETTINGS.
        echo     -- This will be taken in account in the final script 'oltp_data_filling.sql'
        echo     -- which created necessary amount of initial data in lookup tables:
        echo     update settings set svalue=upper('%working_mode%'^)
        echo     where working_mode=upper('init'^) and mcode=upper('working_mode'^);
        echo.
        echo when any do 
        echo     begin
        echo        if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ^) ^) then exception;
        echo     end
        echo end ^^
        echo set term ;^^
        echo commit;
        echo.
        if not .%use_external_to_stop%.==.. (
            echo.
            echo -- External table for quick force running attaches to stop themselves by OUTSIDE command.
            echo -- When all ISQL attachments need to be stopped before warm_time+test_time expired, this
            echo -- external table (TEXT file^) shoudl be opened in editor and single ascii-character 
            echo -- has to be typed followed by LF. Saving this file will cause test to be stopped.
            echo recreate table ext_stoptest external '%use_external_to_stop%' ( s char(2^) ^);
            echo commit;
            echo.
            echo -- REDEFINITION of view that is used by every ISQL attachment as 'stop-flag' source:
            echo create or alter view v_stoptest as
            echo select 1 as need_to_stop
            echo from ext_stoptest;
            echo commit;
        )
        echo.
        echo -- Finish building process: insert custom data to lookup tables:
        echo in "%~dp0oltp_data_filling.sql";

    ) > %tmpsql%

    del !post_handling_out! 2>nul

    echo.
    echo Content of building SQL script:
    echo +++++++++++++++++++++++++++++++
    type %tmpsql%
    echo +++++++++++++++++++++++++++++++

    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    B u i l d     D a t a b a s e   -   c r e a t e    i t s    o b j e c t s    ::::
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -q -nod -c 32768 -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    echo %time%. Please WAIT. . .

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        echo %time%. Got:
        for /f "delims=" %%a in ('findstr /i /c:".sql start" /c:".sql finish" %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1

    @rem operation was cancelled in 2.5: SQLSTATE = HY008 or `^C`
    @rem operation was cancelled in 3.0: SQLSTATE = HY008

    call :catch_err run_isql !tmperr! n/a failed_bld_sql

    echo %time%. Done: database objects have been created SUCCESSFULLY.

    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul
    del !post_handling_out!
    del "%tmpdir%\oltp_split_heavy_tabs_%create_with_split_heavy_tabs%_%fb%.tmp" 2>nul

    
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    A d j u s t i n g     F o r c e d     W r i t e s    t o     c o n f i g    s e t t i n g   :::
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    echo.
    set msg=Restoring Forced Writes attribute to required value from config.
    echo %msg% & echo %msg%>>%log4tmp%
    call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" %create_with_fw% %create_with_sweep%


    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    D i s p l a y    D a t a b a s e    m a i n    s e t t i n g s    :::
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    
    (
        echo set list on;
        echo select
        echo     p.fb_arch as fb_architecture
        echo     ,mon$database_name as db_name
        echo     ,iif(mon$forced_writes=0, 'OFF', 'ON'^) as forced_writes
        echo     ,mon$sweep_interval as sweep_int
        echo     ,mon$page_buffers as page_buffers
        echo     ,mon$page_size as page_size
        echo from mon$database
        echo left join sys_get_fb_arch('%usr%', '%pwd%'^) p on 1=1;
    ) > %tmpsql%

    echo. & echo Check database info:
    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -q -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>!tmplog! 2>!tmperr!

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! %tmpsql%
    
    type !tmplog!


    (
        echo set list off;
        echo set width working_mode 12;
        echo set width setting_name 40;
        echo set width setting_value 20;
        echo select * from z_settings_pivot;
        echo select z.setting_name, z.setting_value from z_current_test_settings z;
    ) >%tmpsql%

    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    D i s p l a y    s e t t i n g s   o f   c o m i n g    t e s t    :::
    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    echo.
    echo Check map of existing working modes and current settings of test:
    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -q -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    )>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! %tmpsql%

    type %tmplog%

    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    L o g g i n g    D D L    o f    Q D i s t r / X Q D*    i n d i c e s  :::
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    (
        echo -- set list on;
        echo set width tab_name 13;
        echo set width idx_name 31;
        echo set width idx_key 45;
        echo select * from z_qd_indices_ddl;
        echo --set list off;
    ) > %tmpsql% 

    echo Index(es) for heavy-loaded table(s): >>%log4tmp%

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    )>>%log4tmp% 2>&1


    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul

    endlocal

goto:eof


:chk_stop_test

    setlocal

    @rem call :chk_stop_test init_chk !tmpdir! !fbc! !dbconn! !dbauth!

    @rem chk_mode = either 'init_chk' or 'pop_data'
    set chk_mode=%1

    if .%chk_mode%.==.init_chk. (
        echo.
        set msg=Internal routine: chk_stop_test.
        echo !msg! 
        echo !msg! >>%log4tmp%
        echo.
    )

    set tmpdir=%2
    set fbc=%3

    set dbconn=%4
    set dbauth=%5
    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!

    @rem ################### check for non-empty stoptest.txt ################################

    set tmpsql=%tmpdir%\tmp_chk_stop.sql
    set tmpclg=%tmpdir%\tmp_chk_stop.log
    set tmperr=%tmpdir%\tmp_chk_stop.err

    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr


    del %tmpsql% 2>nul
    del %tmpclg% 2>nul
    del %tmperr% 2>nul

    (
        echo set heading off;
        echo set list on;
        echo -- check that test now can be run: resultset of 'select * from sp_stoptest' must be EMPTY
        echo select iif( exists( select * from sp_stoptest ^),
        echo                     '1',
        echo                     '0'
        echo           ^) as "cancel_flag="
        echo from rdb$database;
    )>>%tmpsql%

    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -q -i %tmpsql%

    if .%chk_mode%.==.init_chk. (
        echo|set/p=Check for non-empty external file 'stoptest.txt'...
    )

    echo %time%. Run: %run_isql% 1^>%tmpclg% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>!tmpclg! 2>!tmperr!

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmpclg%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1

    
    call :catch_err run_isql !tmperr! %tmpsql% failed_ext_table
    
    set cancel_flag=2

    del %tmperr% 2>nul

    if .%chk_mode%.==.init_chk. echo  OK.
    for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
        set /a %%a
        if errorlevel 1 set err_setenv=1
    )
    if .%cancel_flag%.==.. set cancel_flag=0

    if .%chk_mode%.==.init_chk. (
        echo|set /p=Value of cancel_flag=%cancel_flag%
        if .%cancel_flag%.==.0. (
            echo  - test CAN proceed.
        ) else (
            echo  - test should be STOPPED.
        )
    )

    del %tmpsql% 2>nul
    del %tmpclg% 2>nul

    if .%cancel_flag%.==.1. (
        goto test_canc
    )

    endlocal
goto:eof

:show_db_and_test_params

    setlocal

    echo.
    set msg=Internal routine: show_db_and_test_params.
    echo !msg! 
    echo !msg! >>%log4tmp%
    echo.

    @rem call :show_db_and_test_params !tmpdir! !fbc! !dbconn! "!dbauth!" %is_embed% %log4all%


    set tmpdir=%1
    set fbc=%2
    set dbconn=%3
    set dbauth=%4
    set is_embed=%5
    set log4all=%6

    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!
    
    set tmpsql=%tmpdir%\tmp_show.tmp
    set tmplog=%tmpdir%\tmp_show.log
    set tmperr=%tmpdir%\tmp_show.err

    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr

    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul

    echo Firebird and database parameters, main test settings: > %tmplog%
    
    (
          echo set list on;
          echo set width fb_arch 70;
          @rem if .%is_embed%.==.0. (
              echo set term ^^;
              echo execute block as
              echo    declare c varchar(255^);
              echo begin
              echo      if ( exists(select * from rdb$procedures where rdb$procedure_name = upper('sys_get_fb_arch'^)^) ^) then
              echo      begin
              echo          select fb_arch
              echo          from sys_get_fb_arch('%usr%', '%pwd%'^)
              echo          into c;
              echo          rdb$set_context('USER_TRANSACTION', 'FB_ARCH', c^);
              echo     end
              echo     else
              echo     begin
              echo         rdb$set_context('USER_TRANSACTION', 'FB_ARCH', 'UNKNOWN: missing procedure SYS_GET_FB_ARCH.' ^);
              echo     end
              echo end
              echo ^^
              echo set term ;^^
    
          @rem )
          echo select
          echo        coalesce( rdb$get_context('USER_TRANSACTION', 'FB_ARCH'^), 'UNKNOWN'^) as fb_architecture
          echo       ,m.mon$database_name as db_name
          echo       ,iif(m.mon$forced_writes=0, 'OFF', 'ON'^) as forced_writes
          echo       ,m.mon$sweep_interval as sweep_int
          echo       ,m.mon$page_buffers as page_buffers
          echo       ,m.mon$page_size as page_size
          echo from mon$database m;

          echo set list off;
          echo set width setting_name 40;
          echo set width setting_value 20;
          echo select trim(z.setting_name ^) as setting_name , z.setting_value
          echo from z_current_test_settings z
          echo where z.stype in('init', 'main'^); -- , 'inf2'

    ) >>%tmpsql%
    
    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -q -n -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    )>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! %tmpsql% failed_show_params
    
    del %tmperr% 2>nul
    del %tmpsql% 2>nul

    @echo off
   
    @rem Display database and main test parameters + add them to main log:

    type %tmplog%
    type %tmplog% >> %log4all%

    @rem Logging DDL of QDistr / XQD* indices: do NOT run it here, it will appear in final report by call from oltp_run_worker

    del %tmplog% 2>nul

goto:eof

:count_existing_docs
    
    setlocal

    echo.
    set msg=Internal routine: count_existing_docs.
    echo !msg! 
    echo !msg! >>%log4tmp%
    echo.
    
    @rem call :count_existing_docs !tmpdir! !fbc! !dbconn! "!dbauth!" %init_docs% existing_docs engine log_tab
    @rem                              1       2      3         4           5           6           7       8

    set tmpdir=%1
    set fbc=%2
    set dbconn=%3
    set dbauth=%4
    set init_docs=%5

    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!

    set tmpsql=%tmpdir%\tmp_init_data_chk.sql
    set tmplog=%tmpdir%\tmp_init_data_chk.log
    set tmperr=%tmpdir%\tmp_init_data_chk.err

    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr

    @rem echo Check if the database needs to be filled up with necessary number of documents
       
    @rem check that total number of docs (count from doc_list table) is LESS than %init_docs%
    @rem and UPDATE value of %init_docs% (reduce it) so that its new value + count will be
    @rem equal to required total number of docs (which is specified in config)
    
    
    (
        echo set list on;
        echo select (select count(*^) from (select id from doc_list rows (1+%init_docs%^) ^) ^) as "existing_docs="
        echo       ,rdb$get_context('SYSTEM','ENGINE_VERSION'^) as "engine="
        echo       ,iif( exists( select * from rdb$relations r
        echo                     where r.rdb$relation_name='PERF_LOG'
        echo                           and r.rdb$relation_type=1
        echo                           and r.rdb$view_blr is not null
        echo                    ^),
        echo             'XPERFLOG_01',
        echo             'PERF_LOG'
        echo           ^) as "log_tab="
        echo  from rdb$database;
    ) >%tmpsql%

    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -pag 0 -n -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1


    call :catch_err run_isql !tmperr! %tmpsql% failed_count_old_docs

    del %tmpsql% 2>nul
    del %tmperr% 2>nul

    for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmplog%') do (
        set %%a
        for /F "tokens=1-2 delims==" %%i in ("%%a") do (
            set par=%%i
            set val=%%j
            for /F "tokens=1" %%p in ("!par!") do (
                echo param=^|%%i^|, name w/o white-spaces=^|%%p^| >>%log4tmp%
                for /F "tokens=1" %%u in ("!val!") do (
                    set %%p=%%u
                    echo param=^|%%p^|, value w/o white-spaces=^|%%u^| >>%log4tmp%
                )
            )
        )
    )
    del %tmplog% 2>nul

    @rem Assign values to output arguments 'existing_docs' 'engine' and 'log_tab':
    @rem call :count_existing_docs !tmpdir! !fbc! !dbconn! "!dbauth!" %init_docs% existing_docs engine log_tab
    @rem                              1       2      3         4           5           6           7       8

    endlocal & set "%~6=%existing_docs%" & set "%~7=%engine%" & set "%~8=%log_tab%"

goto:eof

:run_init_pop

    @rem --------------   i n i t i a l      d a t a     p o p u l a t i o n   -------------

    setlocal

    echo.
    set msg=Internal routine: run_init_pop.
    echo !msg! 
    echo !msg! >>%log4tmp%
    echo.

    set skip_fbsvc=0
    if .%is_embed%.==.1. if .%fb%.==.30. set skip_fbsvc=1

    @rem call :run_init_pop !tmpdir! !fbc! !dbconn! "!dbauth!" %existing_docs% %init_docs% %engine% %log_tab%

    set tmpdir=%1
    set fbc=%2
    set dbconn=%3

    set dbauth=%4
    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!

    set existing_docs=%5
    set init_docs=%6
    set engine=%7
    set log_tab=%8
    
    @echo off
    echo Initial data population until total number
    echo of created docs will be not less than ^>^>^> %existing_docs% +  %init_docs% ^<^<^<
    echo.
    echo Please wait. . .
    echo.

    set tmpsql=%tmpdir%\tmp_init_data_pop.sql
    set tmplog=%tmpdir%\tmp_init_data_pop.log
    set tmperr=%tmpdir%\tmp_init_data_pop.err

    set tmpchk=%tmpdir%\tmp_init_data_chk.sql
    set tmpclg=%tmpdir%\tmp_init_data_chk.log

    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr

    call :repl_with_bound_quotes %tmpchk% tmpchk
    call :repl_with_bound_quotes %tmpclg% tmpclg
    
    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul
    
    if exist %tmpsql% goto err_del
    if exist %tmplog% goto err_del
    
    @rem --- Preparing: create temp .sql to be run and add/update settings table ---
    
    (
        if .%engine:~0,3%.==.2.5. (
            echo commit; -- skip `linger` statement because current FB engine is older than 3.0
        ) else (
            echo alter database set linger to 15; commit;
        )
        echo set transaction no wait;
        echo alter sequence g_init_pop restart with 0;
        echo commit;
        echo show sequence g_init_pop;
    )>>%tmpsql%
    
    @rem --- Run ISQL: restart sequence g_init_pop ---
    
    echo|set /p=Preparing for initial population of documents: restart value of sequence g_init_pop...

    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -q -n -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in (%tmpsql%) do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in (%tmplog%) do echo STDOUT: %%a
        for /f "delims=" %%a in (%tmperr%) do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! %tmpsql% failed_reset_pop_gen
    echo  Done.

    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul
    
    @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem  T E M P L Y    S E T    F O R C E D   W R I T E S   =   O F F
    @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" async

    set init_pkq=50

    set srv_frq=10

    @rem %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    call :gen_working_sql  init_pop  %tmpsql%   %init_pkq%  %no_auto_undo%  0  0
    @rem                      1         2          3              4         5  6
    @rem %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    set t0=%time%
    set msg=%t0%: START initial data population.
    echo !msg! & echo !msg! >>%log4tmp%

    @echo Service procedures will be called at the start of every %srv_frq%th packet.

    set msg=Executed .sql: %tmpsql%
    echo !msg! & echo !msg! >>%log4tmp%

    @rem 15.10.2014, suggestion by AK: set cache buffer pretty large for initial pop data
    @rem Actual for CS or SC, will be ignored in SS:
    @echo Cache buffer for ISQL connect when running initial data population: ^>%init_buff%^<

    set /a k = 1

    :iter_loop
    
        @rem #################################################################################
        @rem #############   I N I T I A L     D A T A     P O P U L A T I O N   #############
        @rem #################################################################################
    
        
        @rem periodically we have to run service SPs: srv_make_invnt_total, srv_make_money_saldo, srv_recalc_idx_stat

        set /a p = %k% %% %srv_frq%

        @echo packet #%k% >>%tmplog%
        @echo ^=^=^=^=^=^=^=^=^=^=^=^=^=>>%tmplog%
    
        @rem ################### check for non-empty stoptest.txt ################################
        @rem old: call :chk_stop_test pop_data %tmpdir% %fbc% "%dbconn%" "%dbauth%"
        call :chk_stop_test pop_data !tmpdir! !fbc! !dbconn! "!dbauth!"
    
       
        set tsrvsql=!tmpdir!\tmp_service_sp.sql
        set tsrvlog=!tmpdir!\tmp_service_sp.log

        call :repl_with_bound_quotes %tsrvsql% tsrvsql
        call :repl_with_bound_quotes %tsrvlog% tsrvlog

        del %tsrvsql% 2>nul
        del %tsrvlog% 2>nul

        if %p% equ 0 (
            (
                echo set list on; set heading on;
                echo commit;
                echo set transaction no wait;
                @rem echo select count(*^) as srv_make_invnt_saldo_result from srv_make_invnt_saldo;
                echo select * from srv_make_invnt_saldo;
                echo commit;
                echo set transaction no wait;
                @rem echo select count(*^) as srv_make_money_saldo_result from srv_make_money_saldo;
                echo select * from srv_make_money_saldo;
                echo commit;
                echo set transaction no wait;
                @rem echo select count(*^) as srv_recalc_idx_stat_result from srv_recalc_idx_stat;
                echo select * from srv_recalc_idx_stat;
                echo commit;
            ) > %tsrvsql%

            echo |set /p=%time%: start run service SPs...

        ) else (
            echo quit; > %tsrvsql%
        )
    

        @rem --------------- perform service: srv_make*_total, recalc index statistics -------------
        set run_srv_sp=%fbc%\isql
        call :repl_with_bound_quotes !run_srv_sp! run_srv_sp
        set run_srv_sp=!run_srv_sp! %dbconn% %dbauth% -c %init_buff% -n -i !tsrvsql!

        if %p% equ 0 (
            echo %time% Run: call service procedures !run_srv_sp! 1^>%tsrvlog% 2^>%tmperr% >>%log4tmp%
        )

        %run_srv_sp% 1>>%tsrvlog% 2>%tmperr%

        if %p% equ 0 (
            (
                for /f "delims=" %%a in ('type %tsrvsql%') do echo RUNSQL: %%a
                echo %time%. Got:
                for /f "delims=" %%a in ('type %tsrvlog%') do echo STDOUT: %%a
                for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
            ) 1>>%log4tmp% 2>&1

            call :catch_err run_srv_sp !tmperr! !tsrvsql! failed_init_pop_srv_sp
            echo  %time%: finish service SPs.

        )
        del !tsrvlog! 2>nul
        del !tsrvsql! 2>nul

        @rem --------------------------------------

        set run_isql=%fbc%\isql
        call :repl_with_bound_quotes %run_isql% run_isql
    
        set run_isql=!run_isql! %dbconn% %dbauth% -c %init_buff% -n -i %tmpsql%
       
        @rem old: set run_isql=%fbc%\isql %dbconn% %dbauth% -i %tmpsql% -c %init_buff% -n 1^>^>%tmplog% 2^>^&1
        if %k% equ 1 (
            echo.
            echo Command: !run_isql!
            echo.
        )

        
        @rem --------------------------- create %init_pkg% business operations -------------------------------
        echo|set /p=%time%, packet #%k% start...

        @rem echo Command: !run_isql!
        @rem  -i C:\TEMP\logs.oltp25\tmp_init_data_pop.sql -c 32768 -n 1>>C:\TEMP\logs.oltp25\tmp_init_data_pop.log 2>&1

        echo %time%. Run: packet #!k!^, %run_isql% 1^>^>%tmpclg% 2^>^&1 >>%log4tmp%

        %run_isql% 1>>%tmpclg% 2>&1

        echo %time%. Count rows with exceptions that occured in this packet.>>%log4tmp%
        (
            for /f "delims=" %%a in ('find /c "SQLSTATE =" %tmpclg%') do echo %time%. Got: %%a
        ) 1>>%log4tmp% 2>&1

        type %tmpclg% >> %tmplog%

        @rem -- do NOT do it here -- call :catch_err run_isql !tmperr! %tmpsql% failed_run_pop_sql
    
        @rem result: one or more (in case of complex operations like sp_add_invoice_to_stock)
        @rem documents has been created; if some error occured, sequence g_init_pop has been
        @rem 'returned' to its previous value.
        @rem now we must check total number of docs:
   
        (
            echo set list off; set heading off;
            echo select
            echo     'new_docs='^|^|gen_id(g_init_pop,0^)
            echo from rdb$database;
        ) >%tmpchk%
    
        set run_isql=%fbc%\isql
        call :repl_with_bound_quotes %run_isql% run_isql

        set run_isql=!run_isql! %dbconn% %dbauth% -pag 0 -n -i %tmpchk%

        echo %time%. Run: obtain number of docs, %run_isql% 1^>%tmpclg% 2^>%tmperr% >>%log4tmp%

        %run_isql% 1>%tmpclg% 2>%tmperr%

        (
            if .!k!.==.1. (
               for /f "delims=" %%a in ('type %tmpchk%') do echo RUNSQL: %%a
            )
            echo %time%. Got:
            for /f "delims=" %%a in ('type %tmpclg%') do echo STDOUT: %%a
            for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
        ) 1>>%log4tmp% 2>&1

        call :catch_err run_isql !tmperr! %tmpchk% failed_count_pop_docs

        @rem result: file %tmpclg% contains ONE row like this: new_docs=12345
        @rem now we can APPLY this row as it was SET command in batch and
        @rem assign its value to env. variable with the SAME name -- `new_docs`:
        for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
            set /a %%a
        )
        echo  %time%, packet #%k% finish: docs created ^>^>^> %new_docs% ^<^<^<, limit = %init_docs%
    
        del %tmpclg% 2>nul
        del %tmpchk% 2>nul
        del %tmperr% 2>nul

        set /a k = k+1

    if %new_docs% lss %init_docs% goto iter_loop

    @rem %%%%%%%%%%%%%%%%%   e n d    o f    l o o p   %%%%%%%%%%%%%%%%%%%%

    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul
    
    @rem If we are here than no more init docs should be created
    
    if %init_docs% gtr 0 (
    
        del %tmpchk% 2>nul
        del %tmpclg% 2>nul
    
        (
            @echo set list off; set heading off;
            @echo select
            @echo     'act_docs='^|^|( select count(*^) from doc_list ^)
            @echo from rdb$database;
        )>%tmpchk%
    
        set run_isql=%fbc%\isql
        call :repl_with_bound_quotes %run_isql% run_isql
    
        set run_isql=!run_isql! %dbconn% %dbauth% -pag 0 -n -i %tmpchk%

        echo %time%. Run: obtain FINAL number of docs, %run_isql% 1^>%tmpclg% 2^>%tmperr% >>%log4tmp%

        %run_isql% 1>>%tmpclg% 2>%tmperr%

        (
            echo %time%. Got:
            for /f "delims=" %%a in ('type %tmpclg%') do echo STDOUT: %%a
            for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
        ) 1>>%log4tmp% 2>&1

        call :catch_err run_isql !tmperr! %tmpchk% failed_count_pop_docs
   
        @rem result: file %tmpclg% contains ONE row like this: new_docs=12345
        @rem now we can APPLY this row as it was SET command in batch and
        @rem assign its value to env. variable with the SAME name -- `new_docs`:
        for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
            set /a %%a
        )

        del %tmpclg% 2>nul
        del %tmpchk% 2>nul
        del %tmperr% 2>nul

        @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
        @rem  R E S T O R E   I N I T    S T A T E    O F     F O R C E D   W R I T E S
        @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

        call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" %create_with_fw%

        set msg=%time% FINISH initial data population.
        echo !msg! & echo !msg! >>%log4tmp%

        @echo.
        set msg=Job has been done from %t0% to %time%. Count rows in doc_list: ^>^>^>!act_docs!^<^<^<.
        echo !msg! & echo !msg! >>%log4tmp%
    
        if .%wait_if_not_exists%.==.1. if .%wait_for_copy%.==.1. (
            @echo.
            @echo ### NOTE ###
            @echo.
            @echo It's a good time to make COPY of test database in order
            @echo to start all following runs from the same state.
            @echo.
            @echo 
            @echo Press any key to begin WARM-UP and TEST mode. . .
            @pause>nul
            echo !date! !time!. Here we go...
        )
    
    )

    endlocal

goto:eof    

:change_db_attr
    setlocal
    echo.
    set msg=Internal routine: change_db_attr.
    echo !msg! 
    echo !msg! >>%log4tmp%
    echo.

    @rem call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" async [%create_with_sweep%]
 
    set tmpdir=%1
    set fbc=%2
    set dbconn=%3

    set dbauth=%4
    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!

    set new_fw=%5

    set new_sweep=%6
    if .%6.==.. set new_sweep=-1

    set tmplog=%tmpdir%\change_db_attr.log
    set tmperr=%tmpdir%\change_db_attr.err
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr

    set fbsvcrun=%fbc%\fbsvcmgr
    call :repl_with_bound_quotes %fbsvcrun% fbsvcrun

    set gfixrun=%fbc%\gfix
    call :repl_with_bound_quotes %gfixrun% gfixrun
    
    if .%is_embed%.==.1. (
        set fbsvcrun=%fbsvcrun% service_mgr
    ) else (
        set fbsvcrun=%fbsvcrun% %host%/%port%:service_mgr %dbauth%
        set gfixrun=%gfixrun% %dbauth%
    )
    set run_cmd=%fbsvcrun%
     
    set skip_fbsvc=0
    @rem 09.10.2015: call fbsvcmgr in embedded mode now is possible, CORE-4938 is fixed
    @rem --- was: if .%is_embed%.==.1. if .%fb%.==.30. set skip_fbsvc=1

    if .%skip_fbsvc%.==.0. (

        echo|set /p=Run fbsvcmgr for obtaining database header BEFORE change FW...
        echo %time%. Run: %run_cmd% action_db_stats dbname %dbnm% sts_hdr_pages 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

        %run_cmd% action_db_stats dbname %dbnm%  sts_hdr_pages 1>%tmplog% 2>%tmperr%
        (
            for /f "delims=" %%a in ('type %tmplog%') do echo STDLOG: %%a
            for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
        ) 1>>%log4tmp% 2>&1
        call :catch_err run_cmd !tmperr! n/a failed_fbsvc
        echo  Ok. && echo %time%. Done. >> %log4tmp%

        echo|set /p=Run fbsvcmgr for temporarily change FW attribute to %new_fw%...
        echo %time%. Run: %run_cmd% action_properties dbname %dbnm% prp_write_mode prp_wm_%new_fw% 2^>%tmperr% >>%log4tmp%

        %run_cmd% action_properties dbname %dbnm% prp_write_mode prp_wm_%new_fw% 1>%tmplog% 2>%tmperr%

        (
            for /f "delims=" %%a in ('type %tmplog%') do echo STDLOG: %%a
            for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
        ) 1>>%log4tmp% 2>&1

        call :catch_err run_cmd !tmperr! n/a failed_fbsvc
        echo  Ok. && echo %time%. Done. >> %log4tmp%

        if not .%new_sweep%.==.-1. (
            @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
            @rem :::    A d j u s t i n g     S w e e p   I n t e r v a l    t o     c o n f i g    s e t t i n g   :::
            @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

            echo|set /p=Changing attribute Sweep Interval to required value from config...

            echo %time%. Run: %run_cmd% action_properties dbname %dbnm% prp_sweep_interval %new_sweep% 2^>%tmperr% >>%log4tmp%
            %run_cmd% action_properties dbname %dbnm% prp_sweep_interval %new_sweep% 2>%tmperr%

            call :catch_err run_cmd !tmperr! n/a failed_fbsvc

            echo  Ok. & echo %time%. Done.>> %log4tmp%
            del !tmperr! 2>nul
        )


        echo|set /p=Run fbsvcmgr for obtaining database header AFTER change FW...
        echo %time%. Run: %run_cmd% action_db_stats dbname %dbnm% sts_hdr_pages 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

        %run_cmd% action_db_stats dbname %dbnm% sts_hdr_pages 1>%tmplog% 2>%tmperr%
        (
            for /f "delims=" %%a in ('type %tmplog%') do echo STDLOG: %%a
            for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
        ) 1>>%log4tmp% 2>&1
        call :catch_err run_cmd !tmperr! n/a failed_fbsvc
        echo  Ok. && echo %time%. Done. >> %log4tmp%


    ) else (
        set msg=SKIP changing FW to OFF in EMBEDDED mode, until CORE-4938 will be fixed.
        echo !msg! 
        echo !msg!>>%log4tmp%
        if not .%new_sweep%.==.-1. (
            set msg=SKIP changing SWEEP interval in EMBEDDED mode, until CORE-4938 will be fixed.
            echo !msg!
            echo !msg!>>%log4tmp%
        )

        @rem 20.09.2015. Do NOT also use gfix in embedded 3.0 until CORE-4938 will be fixed! Also hangs!
        if .1.==.0. (
          echo|set /p=Use gfix instead...
          echo %time%. Run: %gfixrun% %dbnm% -w %new_fw% 2^>%tmperr% >>%log4tmp%
  
          %gfixrun% %dbnm% -w %new_fw% 1>%tmplog% 2>%tmperr%
          (
              for /f "delims=" %%a in ('type %tmplog%') do echo STDLOG: %%a
              for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
          ) 1>>%log4tmp% 2>&1
          call :catch_err gfixrun !tmperr! n/a failed_gfix
          echo  Ok. && echo %time%. Done. >> %log4tmp%
        )

    )
    del %tmplog% 2>nul
    del %tmperr% 2>nul

    endlocal
goto:eof

:readcfg
    set cfg=%1
    set err_setenv=0
    @rem ::: NB ::: Space + TAB should be inside `^[ ]` pattern!
    @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    for /F "tokens=*" %%a in ('findstr /i /r /c:"^[ 	]*[a-z,0-9]" %cfg%') do (
      if "%%a" neq "" (

        @rem Detect whether value of parameter contain quotes or no. If yes than this
        @rem value should NOT be changed by removing its whitespaces.

          for /F "tokens=1-2 delims==" %%i in ("%%a") do (
            @rem echo Parsed: param="%%i" val="%%j"
            set par=%%i
            call :trim par !par!

            if "%%j"=="" (
              set err_setenv=1
              echo. && echo ### NO VALUE found for parameter "%%i" ### && echo.
            ) else (
              for /F "tokens=1" %%p in ("!par!") do (
                set val=%%j
                call :trim val !val!
                set %%p=!val!
              )
            )
          )
      )
    )
    set %~2 = %err_setenv%
    @rem if .%err_setenv%.==.1. goto err_setenv

goto:eof


:check_for_prev_build_err
    echo.
    echo Internal routine: check_for_prev_build_err.
    echo.
    setlocal

    @rem call :check_for_prev_build_err %tmpdir% %fb% build_was_cancelled

    set tmpdir=%1
    set fb=%2
    set tmperr=%tmpdir%\%~n0_%fb%.err
    call :repl_with_bound_quotes %tmperr% tmperr

    set msg=Previous launch of script that builds database
    set txt=###################################################################
    set build_was_cancelled=0

    for /f "usebackq tokens=*" %%a in ('%tmperr%') do set size=%%~za
    if .!size!.==.. set size=0
    if !size! gtr 0 (
        findstr /i /c:"SQLSTATE = HY008" /c:"^C" %tmperr% 1>nul
        if not errorlevel 1 (
            echo %txt%
            echo %msg% was INTERRUPTED.
            echo %txt%
            echo.
            echo Content of %tmperr%:
            echo ++++++++++++++++++++
            type %tmperr%
            echo ++++++++++++++++++++
            echo.
            echo Database need to be recreated now.
            @rem echo Press any key to go on, Ctrl-C to FINISH this batch. . .
            @rem pause >nul
            @rem set build_was_cancelled=1
        ) else (
            echo.
            echo %txt%
            echo %msg% finished with ERROR.
            echo %txt%
            echo.
            echo Error log: %tmperr%
            echo Its content:
            echo ------------
            findstr /r /v /c:"^[ 	]" /c:"^$" %tmperr%
            echo ------------
            echo Remove this file before restarting test.
            echo.
            echo Press any key to FINISH this batch. . .
            pause>nul
            goto final
        )
    ) else (
        echo RESULT: no errors found that could rest from previous building database objects.
        echo File %tmperr% not found or is empty.
    )
    endlocal & set "%~3=%build_was_cancelled%"
goto:eof

:show_time_limits

    setlocal

    echo.
    set msg=Internal routine: show_time_limits.
    echo !msg! 
    echo !msg! >>%log4tmp%
    echo.

    @rem call :show_time_limits !tmpdir! !fbc! !dbconn! "!dbauth!" log4all

    setlocal

    set tmpdir=%1
    set fbc=%2
    set dbconn=%3
    set dbauth=%4
    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!

    set log4all=!%5!

    set logname=tmp_show_time
    set tmpsql=%tmpdir%\%logname%.sql
    set tmplog=%tmpdir%\%logname%.log
    set tmperr=%tmpdir%\%logname%.err

    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr

    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul
    
    @rem echo Add record for checking work to be stopped on timeout. . .
    
    echo Parameters for measuring:>>%tmplog%
    
    (
        echo set bail on;
        echo commit; 
        echo set transaction no wait;
        echo delete from %log_tab% g
        echo where g.unit in ( 'perf_watch_interval',
        echo                   'sp_halt_on_error',
        echo                   'dump_dirty_data_semaphore',
        echo                   'dump_dirty_data_progress'
        echo                 ^);
        echo commit;
        echo insert into %log_tab%( unit,                  info,     exc_info,
        echo                       dts_beg, dts_end, elapsed_ms^)
        echo               values( 'perf_watch_interval', 'active', 'by %~f0',
        echo         dateadd( %warm_time% minute to current_timestamp^),
        echo         dateadd( %warm_time% + %test_time% minute to current_timestamp^),
        echo         -1 -- skip this record from being displayed in srv_mon_perf_detailed
        echo         ^);
        echo insert into %log_tab%( unit,                        info,  stack,
        echo                       dts_beg, dts_end, elapsed_ms^)
        echo               values( 'dump_dirty_data_semaphore', '',    'by %~f0',
        echo                       null, null, -1^);
        echo delete from perf_estimated; -- this table will be used in report "Performance for every MINUTE", see query to z_estimated_perf_per_minute
        echo alter sequence g_success_counter restart with 0;
        echo commit;
    
        echo set width unit 20;
        echo set width add_info 30;
        echo set width dts_measure_beg 19;
        echo set width dts_measure_end 19;
        echo set list on;
    
        echo select
        echo        '%log_tab%' as log_table
        echo       ,g.dts_measure_beg
        echo       ,g.dts_measure_end
        echo       ,g.add_info
        echo from
        echo (
        echo   select p.unit, p.exc_info as add_info,
        echo      left(replace(cast(p.dts_beg as varchar(24^)^),' ','_'^),19^) as dts_measure_beg,
        echo      left(replace(cast(p.dts_end as varchar(24^)^),' ','_'^),19^) as dts_measure_end
        echo   from %log_tab% p
        echo        where p.unit = 'perf_watch_interval'
        echo        order by dts_beg desc rows 1
        echo ^) g;
        echo.
        echo set list off;
    )>%tmpsql%
    

    set run_isql=%fbc%\isql
    call :repl_with_bound_quotes %run_isql% run_isql
    
    set run_isql=!run_isql! %dbconn% %dbauth% -n -i %tmpsql%

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>>%tmplog% 2>%tmperr%

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! %tmpsql% failed_show_time

    type %tmplog% >> %log4all%
    
    type %log4all%
    
    set msg=Final report see in file: ^>^>^>%log4all%^<^<^<
    echo !msg!
    echo !msg!>>%log4tmp%
    echo #########################

   
    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul

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

:catch_err
    
    setlocal

    @rem Sample:
    @rem set run_cmd=!fbsvcrun! info_server_version
    @rem !run_cmd! 1>%tmplog% 2>%tmperr%
    @rem call :catch_err run_cmd !tmperr! n/a nofbvers
    @rem call :catch_err run_isql !tmperr! !tmpchk! db_notready 0

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
          call :!add_label!
        )
        echo.
        echo Command: !runcmd!
        echo.
        echo SQL script: %sql_file%
        echo Content of error log (%err_file%^):
        echo ^=^=^=^=^=^=^=
        type %err_file%
        echo ^=^=^=^=^=^=^=
        echo See details in file %log4tmp%
        if .!do_abend!.==.1. (
            echo.
            echo Press any key to FINISH this batch. . .
            pause>nul
            goto final
        )

    )
    endlocal
goto:eof

:getfblst
    echo.
    set msg=Internal routine: getfblst.

    @rem call :getfblst %fb% fbc
    @rem                 ^    ^-------- this will be defined here: path to FB binaries on local machine.
    @rem                 +------------- first arg. to batch, relates to FB version: 25 or 30

    echo !msg! 
    echo.

    setlocal

    set qrx=%tmpdir%\tmp.sc.qryex.fb.all.tmp
    set lst=%tmpdir%\tmp.fbservices.list.tmp

    sc queryex state= all | findstr "FirebirdServer" 1>%qrx%

    del %lst% 2>nul

    for /f "tokens=2" %%s in ( %qrx% ) do (
      @rem echo|set /p=Found FB service: %%s
      for /f "tokens=3" %%k in ('REG.EXE query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\%%s ^| findstr /i /c:"ImagePath"') do (
        set fn=%%k
        set fp=%%~dpk
        set fp=!fp:~0,-1!
        if exist !fp!\fbsvcmgr.exe if exist !fp!\isql.exe (
          for /f "tokens=3" %%v in ('echo. ^| !fp!\isql.exe -z -q') do (
            for /f "tokens=4 delims=." %%b in ('echo %%v') do set build=%%b
            set /a k=1000000+!build!
            set build=!k:~1,6!
            @rem echo !build! vers=%%v home=!fp! name=%%s >> %lst%
            echo !build!^*%%v^*!fp!^*%%s >> %lst%
          )
        )
      )
    )

    del %qrx% 2>nul

    @rem Here we try to find most appropriate client when several FB instances present on machine.
    @rem When %fb% = 25 then we first of all try to scan all folders where Firebird 2.5 instances are, 
    @rem and only after this we start to search in folders with FB 3.0.
    @rem For each FB major family (2.5 or 3.0) we first try to find RELEASE instance ('WI-V*') and only
    @rem after it - testing ('WI-T*').

    if .%1.==.25. (
        set preflst=WI-V2.5.,WI-T2.5,WI-V3.,WI-T3.,WI-V,WI-T
    ) else (
        set preflst=WI-V3.,WI-T3.,WI-V2.5.,WI-T2.5,WI-V,WI-T
    )

    for %%k in (%preflst%) do (
        findstr /i /c:"%%k" %lst% | sort /r >> %qrx%
        if not errorlevel 1 goto :find_at_least_one_fb
    )

    :find_at_least_one_fb

    @rem type %lst% | sort /r >%qrx%
    set /p firstline=<%qrx%

    for /f "tokens=3 delims=**" %%a in ('echo %firstline%') do (
       set result=%%a
    )
    if .%result%.==.. (
        echo.
        echo ### ERROR ###
        echo.
        echo No found any installed Firebird services on that machine!
    ) else ( 
        echo Found most recent Firebird instance in the folder: 
        echo %result%
    )
    del %qrx% 2>nul
    del %lst% 2>nul

    endlocal & set "%~2=%result%"

goto:eof

:nofbvers
    echo Can not extract version of Firebird using FBSVCMGR utility.
    echo 1. Ensure that Firebird is running on host=^|%host%^| and is listening port=^|%port%^|
    if .%is_embed%.==.1. (
        findstr /i /c:"Cannot attach to services manager" %tmperr% 1>nul
        if not errorlevel 1 (
            echo 2. Ensure that ImagePath of Firebird service in Windows registry allows connect via XNet.
            echo    (it will be DISABLED if key "-i" present there!^).
        )
    ) else (
        echo 2. Check settings in %cfg%: usr=^|%usr%^| and pwd=^|%pwd%^|
    )
goto:eof

:db_notready
    echo FAILED check that database is avaliable and has all needed objects.
goto:eof

:cant_create_or_connect
    echo FAILED attempt to create new database or test connection to existing one.
goto:eof

:failed_fbsvc
    echo FAILED result of fbsvcmgr launch.
goto:eof

:failed_gfix
    echo FAILED result of gfix launch.
goto:eof

:failed_bld_sql
    echo FAILED building database objects.
goto:eof

:failed_ext_table
    echo FAILED to detect content of EXTERNAL table that is used to test self-stop.
    echo.
    echo Probably you have to open firebird.conf and set 'ExternalFileAccess'
    echo to some folder where 'firebird' account has enough rights.
goto:eof

:failed_show_params
    echo FAILED fo run script with commands for show database and test parameters.
goto:eof

:failed_count_old_docs
    echo FAILED to run script which tries to obtain number of already existing
    echo documents and to determine need in initial data population.
goto:eof

:failed_reset_pop_gen
    echo FAILED to run script which resets generator for initial data population.
goto:eof

:failed_init_pop_srv_sp
    echo FAILED to run auxiliary stored procedures during initial data population.
goto:eof

:failed_count_pop_docs
    echo FAILED to run script which tries to get number of current docs in database.
goto:eof

:failed_show_time
    echo FAILED to run script which tries to add 'signal' record into log that will be
    echo used to evaluate planning finish time.
goto:eof

:trim
    setLocal
    @rem EnableDelayedExpansion
    set Params=%*
    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof
@rem exit /b

:haltHelper
()
exit /b

:final
@rem http://stackoverflow.com/questions/10534911/how-can-i-exit-a-batch-file-from-within-a-function
call :haltHelper 2> nul

:end_of_test
echo.
echo.
echo %date% %time%. Final point of script %~f0. 
echo Now you can close this window. Bye-bye...
echo.
