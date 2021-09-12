@echo off
@rem ----------------------------------------------
@rem arg #1 = 25, 30 or 40 - major version of FB, without dot.
@rem arg #2 = number of ISQL sessions to be launched.
@rem ----------------------------------------------
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

set abendlog=!THIS_DIR!\abend.log.tmp
del !abendlog! 2>nul

set can_stop=1

if .%1.==.. (
    call :no_arg1 !abendlog!
)

set fb=%1
if .%fb%.==.25. goto chk2
if .%fb%.==.30. goto chk2
if .%fb%.==.40. goto chk2
if .%fb%.==.50. goto chk2
call :no_arg1 !abendlog!

:chk2
if .%2.==.. goto noarg1
set /a k = %2
if not .%k%. gtr .0. call :no_arg1 !abendlog!

@rem moved here 12.08.2018: value is needed for updating SESSIONS table, parameter 'WORKERS_COUNT'
@rem winq = number of opening isqls
set winq=%2
if .%is_embed%.==.1. set winq=1

@rem 06.02.2016: disable any pauses (even on severe errors like troubles with opening files etc)
@rem when this batch is called on scheduling basis:
if /i .%3.==.nostop. set can_stop=0

:ok
echo %date% %time% - starting %~f0
echo Input arg1 = ^|%1^|, arg2  = ^|%2^|

set /a is_admin=0
set /a is_admin=1
@rem call :is_admin !abendlog! is_admin
if !is_admin! EQU 0 (
    call :admin_rights_req !abendlog!
)

@rem ---------------------------------------------------------------------

set INIT_SHELL_DIR="%cd%"

@rem 09.05.2019: on some hosts execution of CScript can be prohibited with issuing:
@rem CScript Error: Execution of the Windows Script Host failed. (Access is denied. )
@rem Probably this can be because of parameter Enabled=0 in
@rem HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Script Host

%systemroot%\system32\cscript.exe 1>!abendlog! 2>&1
findstr /i /c:"//H:CScript" !abendlog! >nul
if errorlevel 1 (
    call :nocscript !abendlog!
)


set cfg=oltp%fb%_config.win

set isc_user=
set isc_password=

set msg=Parsing config file '%cfg%'. Please wait. . .
echo !msg!
echo !msg!>!abendlog!
set err_setenv=0

::::::::::::::::::::::::::::::::
:::: R E A D    C O N G I G ::::
::::::::::::::::::::::::::::::::

call :readcfg %cfg% err_setenv
if .%err_setenv%.==.1. goto no_env


if .%gather_hardware_info%.==.1. (
    echo %host% | findstr /r /i /c:"localhost" /c:"127.0.0.1" >nul
    if errorlevel 1 (
        echo CONFIGURATION ISSUE.
        echo Parameter 'gather_hardware_info' = 1 requires parameter 'host' having value 'localhost' or '127.0.0.1'.
        echo Hardware and OS info will not be gathered because probably you are going to run test on REMOTE server.

        @rem ###############################################################################################
        @rem ###  C H A N G E    C O N F I G   'G A T H E R _ H A R D W A R E _ I N F O'   T O   Z E R O ###
        @rem ###############################################################################################
        set gather_hardware_info=0

        if .%can_stop%.==.1. (
             echo.
             echo Press any key to CONTINUE this batch. . .
             pause>nul
        )
    )
)

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
    call :no_env !abendlog! tmpdir
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

if not exist %tmpdir% md %tmpdir% 2>nul

if not exist %tmpdir%\nul (
    call :noaccess !abendlog!
)
if not exist %tmpdir%\sql md %tmpdir%\sql

if .%make_html%.==.1. (

    @rem HTML report always is compressed before writing to temporary .fdb
    @rem which, in turn, further is backed up to %results_storage_fbk%.
    @rem We have to ensure that compressor binary (if defined) really exists.
    @rem When config parameter 'report_compress_cmd' is undefined then
    @rem HTML report will be compressed using ZIP format via call cscript.

    if not .%report_compress_cmd%.==.. (

        @rem cmd /c !report_compress_cmd! 1>!abendlog! 2>&1
        @rem set elev=!errorlevel!
        @rem echo elev=!elev!
        @rem if !elev! NEQ 0 (

        if not exist "!report_compress_cmd!" (
            call :nocompressor !abendlog!
        )
        call :trim report_compress_cmd !report_compress_cmd!

        @rem NOTE: do NOT put space between 'echo' and PIPE character for pass result to 'findstr':
        echo !report_compress_cmd!| findstr /e /i /c:"\7za.exe" /c:"\7za" /c:"\7z.exe" /c:"\7z" >nul
        if NOT errorlevel 1 (
            @rem Check that 'report_compress_cmd' actually points to 7-Zip
            cmd /c !report_compress_cmd! 1>!abendlog! 2>&1
            findstr /i /c:"7-Zip" !abendlog!>nul
            if errorlevel 1 (
                call :noprodname !abendlog! report_compress_cmd 7-Zip
            )
        )

        @rem NOTE: do NOT put space between 'echo' and PIPE character for pass result to 'findstr':
        echo !report_compress_cmd!| findstr /e /i /c:"\zstd.exe" /c:"\zstd" >nul
        if NOT errorlevel 1 (
            @rem Check that 'report_compress_cmd' actually points to Zstandard:
            cmd /c !report_compress_cmd! 1>!abendlog! 2>&1
            findstr /i /c:"zstd.exe" !abendlog! | findstr /i /c:"args" | findstr /i /c:"file" >nul
            if errorlevel 1 (
                call :noprodname !abendlog! report_compress_cmd Zstandard
            )
        )


    )

    @rem certutil is used to convert COMPRESSED HTML content (7z, .zst, .zip)
    @rem to base64 before it will be inserted into temporary .fdb and further
    @rem backed up to %results_storage_fbk%.

    %systemroot%\system32\certutil.exe -? 1>!abendlog! 2>&1
    findstr /i /c:"-encode" !abendlog! 1>nul
    if errorlevel 1 (
        call :nocertutil !abendlog!
    )

)

@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@rem INITIATE REPORT FILE "%tmpdir%\oltp30.report.txt"
@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
set tmpname=%~n0

set log4all=%tmpdir%\oltp%fb%.report.txt
set log4tmp=%tmpdir%\oltp%fb%.prepare.log
set tmplog=%tmpdir%\%tmpname%.log
set tmperr=%tmpdir%\%tmpname%.err
set tmpsql=%tmpdir%\%tmpname%.sql
set tmpchk=%tmpdir%\%tmpname%.chk
set tmpclg=%tmpdir%\%tmpname%.clg

for /d %%x in (!abendlog!,!log4all!,!log4tmp!,!tmplog!,!tmperr!,!tmpsql!,!tmpchk!,!tmpclg!) do (
    del %%x 2>nul
)


(
  echo %date% %time%. Preparing for test started.
  echo Currently running batch: %~f0
  echo Checking parameters. Config file: %cfg%.
) >>%log4tmp%

echo. && echo Config parsing finished. Result:

set varlist=^
create_with_compound_columns_order^
,create_with_debug_objects^
,create_with_fw^
,create_with_separate_qdistr_idx^
,create_with_split_heavy_tabs^
,create_with_sweep^
,dbnm^
,detailed_info^
,expected_workers^
,fbc

set varlist=!varlist!^
,file_name_this_host_info^
,file_name_with_test_params^
,gather_hardware_info^
,halt_test_on_errors^
,host^
,init_buff^
,init_docs^
,is_embed^
,make_html^
,max_cps^
,mon_unit_list^
,mon_unit_perf

set varlist=!varlist!^
,no_auto_undo^
,port^
,pwd^
,qmism_verify_bitset^
,recalc_idx_min_interval^
,remove_isql_logs^
,run_db_statistics^
,run_db_validation^
,separate_workers^
,sleep_max


set varlist=!varlist!^
,test_time^
,test_intervals^
,tmpdir^
,unit_selection_method^
,update_conflict_percent^
,used_in_replication^
,use_mtee^
,usr^
,wait_after_create^
,wait_for_copy^
,wait_if_not_exists^
,warm_time^
,working_mode^
,actions_todo_before_reconnect

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



@rem 04.05.2020 do NOT ever leave this parameter undefined!
if not defined sleep_min (
    set sleep_min=0
)

if !sleep_min! GTR !sleep_max! (
    call :sho "Incorrect value of 'sleep_min' parameter: !sleep_min!. It must be in the scope 0...!sleep_max!" !log4tmp!
    echo Press any key to FINISH this batch. . .
    pause>nul
    goto final
)

if %mon_unit_perf% EQU 2 (
    if not defined sleep_ddl (
        echo.
        (
            echo CONFIGURATION ISSUE. Parameter 'mon_unit_perf' = 2 requires that parameter 'sleep_ddl' must be defined.
            echo It must point to existing SQL script that declares UDF for delays from .so file avaliable to engine.
        ) >!tmplog!
        call :bulksho !tmplog! !log4tmp!
        if .%can_stop%.==.1. (
             echo.
             echo Press any key to FINISH this batch.
             pause>nul
        )
        goto final
    )

    if not defined mon_query_interval (
        echo.
        (
            echo CONFIGURATION ISSUE. Parameter 'mon_unit_perf' = 2 requires that parameter 'mon_query_interval' must be defined.
            echo Its value must be greater than zero and means duration of delay between receiving monitoring snapshots, in seconds.
        ) >!tmplog!
        call :bulksho !tmplog! !log4tmp!
        if .%can_stop%.==.1. (
             echo.
             echo Press any key to FINISH this batch.
             pause>nul
        )
        goto final
    )

    findstr /i /r /c:"declare[ ]*external[ ]*function" !sleep_ddl! > nul
    if NOT errorlevel 1 (
        for /f "tokens=4" %%a in ('findstr /i /r /c:"declare[ ]*external[ ]*function" !sleep_ddl!') do (
            set sleep_udf=%%a
        )
        if .!sleep_udf!.==.. (
            echo.
            (
                echo SQL script '!sleep_ddl!' must contain name of UDF for delays
                echo in one line with 'DECLARE EXTERNAL FUNCTION' clause.
                echo Open this script in editor and adjust it.
            ) >!tmplog!
            call :bulksho !tmplog! !log4tmp!

            if .%can_stop%.==.1. (
                echo.
                echo Press any key to FINISH this batch. . .
                pause>nul
                goto final

            )
        ) else (
            call :sho "Parsing of '!sleep_ddl!' finished, name UDF for delays is: !sleep_udf!" !log4tmp!
        )
    ) else (
        echo.
        (
            echo SQL script '!sleep_ddl!' must contain line with UDF declaration
            echo that starts with:
            echo.
            echo     declare external function ^<UDF_name^>
            echo.
            echo NOTE: all these four words must be written in one line.
            echo Example:
            echo.    declare external function sleep
            echo.    integer
            echo.    returns integer by value
            echo.    entry_point 'SleepUDF' module_name 'SleepUDF';
		) >!tmplog!
        call :bulksho !tmplog! !log4tmp!

        if .%can_stop%.==.1. (
            echo.
    		echo Press any key to FINISH this batch.
    		pause
    		goto final
    	)
    )


)

if not .%fb%. == .25. (
    
    call :chk_mon_usr_pwd_role

    if NOT "%mon_usr_prefix%"=="" (
        if not "%mon_usr_prefix:~-1%"=="_" (
            call :sho "CONFIGURATION ISSUE. Parameter 'mon_usr_prefix' must end with an underscore character (_^)" !log4tmp!
            if .%can_stop%.==.1. (
                echo Press any key to FINISH this batch. . .
                pause>nul
                goto final
            )
        )
    )


    if .!use_es!.==.2. if .!separate_workers!.==.1. (
        set empty_mon_prefixes=1
        if NOT .!mon_query_role!.==.. (
            if NOT .!mon_usr_prefix!.==.. (
                if NOT .!mon_usr_passwd!.==.. (
                    set empty_mon_prefixes=0
                )
            )
        )
        if .!empty_mon_prefixes!.==.1. (
            (
                echo CONFIGURATION ISSUE.
                echo Parameter 'use_es' has value 2. This means that dynamic SQL (execute statement '...'^)
                echo will be supplied with an extra option: ON EXTERNAL DATASOURCE, which leads to creation of a new connection
                echo each time when this dynamic SQL executes.
                echo Parameter 'separate_workers' has value 1. This means that every launcing ISQL session must work only with
                echo data that was created by this session (i.e. within 'sandbox'^).
                echo When statement is executed via EDS, the only way to provide to it number of working ISQL is name of user
                echo who launched htis ISQL.
                echo.
                echo Following config parameters must be defined in that case:
                echo 'mon_query_role', 'mon_usr_prefix' and 'mon_usr_passwd'.
                echo.
                echo Note that parameter 'mon_usr_prefix' must end with an underscore character (_^) for proper extract number
                echo of currently working ISQL session.
                echo ----------------------------------------------------------------------------------------------------------
                echo UNCOMMENT following parameters and assign them non-empty values. It can be defaults:
                echo.    mon_query_role = tmp$oemul$worker
                echo.    mon_usr_prefix = tmp$oemul$user_
                echo.    mon_usr_passwd = #0Ltp-Emu1
            ) >!tmplog!

            call :bulksho !tmplog! !log4tmp!
            if .%can_stop%.==.1. (
                echo.
                echo Press any key to FINISH this batch. . .
                pause>nul
                goto final
            )
        )
    )

) else (
    @rdm for FB 2.5.x 'use_es' must be alywas = 0, i.e. no EDS
    set use_es=0
)

if .!gather_hardware_info!.==.1. (
    echo !host! | findstr /i /c:"localhost" /c:"127.0.0.1">nul
    if errorlevel 1 (
        (
		echo CONFIGURATION ISSUE.
		echo Parameter 'gather_hardware_info' = 1 requires parameter 'host' having value 'localhost' or '127.0.0.1'.
		echo Hardware and OS info will not be gathered because probably you are going to run test on REMOTE server.
		echo Current value of 'host' parameter is: !host!
		) >!tmplog!
        call :bulksho !tmplog! !log4tmp!
        if .%can_stop%.==.1. (
            echo.
            pause
            goto final
        )

        @rem ###############################################################################################
        @rem ###  C H A N G E    C O N F I G   'G A T H E R _ H A R D W A R E _ I N F O'   T O   Z E R O ###
        @rem ###############################################################################################
		set gather_hardware_info=0
    )
)


(
  echo !date! !time!. Created by: %~f0, at host: %file_name_this_host_info%
) >>%log4all%


@rem Change PATH variable: insert %fbc% to the HEAD of path list:
set pbak=%path%
set path=%fbc%;%pbak%

echo Changing path: put %fbc% into HEAD of list.

@rem check that result of PREVIOUS launch of this batch was OK:
@rem #############################
set build_was_cancelled=0

call :check_for_prev_build_err %tmpdir% %fb% build_was_cancelled %can_stop% %log4tmp%

@rem Result: build_was_cancelled = 1 ==> previous building process was cancelled (found "SQLSTATE = HY008" in .err).


for /d %%x in (isql,gfix,fbsvcmgr,gbak) do (
    if not exist %fbc%\%%x.exe goto bad_fbc_path
)

call :sho "All needed FB utilities found in the folder defined by parameter 'fbc': %fbc%" %log4tmp%

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

set run_cmd=!fbsvcrun! info_server_version
call :sho "Obtain Firebird info. Command: !run_cmd!" !log4tmp!

%run_cmd% 1>%tmplog% 2>%tmperr%

(
    echo %time%. Got:
    for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
    for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
) 1>>%log4tmp% 2>&1

call :catch_err run_cmd !tmperr! n/a nofbvers

for /f "tokens=1-3 delims= " %%a in ('findstr /i /c:version %tmplog%') do (
  set fbb=%%c
  set fbo=!fbb:~0,2!
)

if not defined fbb (
    (
        echo.
        echo Could not detect Firebird build number from 'FBSVCMGR info_server_version' log.
        echo Probably FBSVCMGR output was changed or error in this batch algorithm.
        echo.
        echo See details in %log4tmp%
    ) > %tmplog%
    type %tmplog%
    type %tmplog% >> %log4tmp%
    del %tmplog%

    if .%wait_if_not_exists%.==.1. if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH this batch. . .
        pause>nul
    )
    goto final
)

call :sho "Build: %fbb%, prefix of server OS: %fbo%" %log4tmp%


@rem #######################################

call :sho "Check that database is avaliable." %log4tmp%

@rem ##############################################################
@rem TODO LATER: change this alg! use hash of all db object names ?

@rem ..................... check that all DB objects was already created Ok ..............

(
    echo "set list on;"
    echo "set bail on;"
    echo "-- set echo on;"

    echo "-- check that all database objects already exist:"
    echo "select iif( exists( select * from semaphores where task='all_build_ok'),"
    echo "                    'all_dbo_exists',"
    echo "                    'some_dbo_absent'"
    echo "          ) as "build_result=""
    echo "from rdb$database;"

    echo "-- Sequence g_stop_test serves as 'stop-flag' for every ISQL attachment."
    echo "-- It must be always set to ZERO before test launch."
    echo "-- Here we forcedly set this sequence to 0 and, at the same time, check that DB is not read-only."
    echo "select gen_id(g_stop_test,0) gen_stop_before_restart from rdb$database;"
    echo "-- Added 07.08.2020:"
    echo "set term ^;"
    echo "execute block as"
    echo "    declare c bigint;"
    echo "begin"
    echo "   -- DISABLED 07.08.2020:"
    echo "   -- alter sequence g_stop_test restart with 0; -- DOES NOT WORK since 4.0.0.2131:"
    echo "   -- gen_id(,0) will return -1 instead of 0."
    echo "   c = gen_id(g_stop_test, -gen_id(g_stop_test, 0));"
    echo "end ^"
    echo "commit ^"
    echo "select gen_id(g_stop_test,0) gen_stop_after_restart from rdb$database ^"
    echo "commit ^"

    set tmp_ddl=recreate exception exc_gen_stop_test_invalid 'Test can not start because value of generator ''g_stop_test'' is NOT zero
    if not .%fb%.==.25. (
        set tmp_ddl=!tmp_ddl!: @1'
    ) else (
        set tmp_ddl=!tmp_ddl!'
    )
    echo !tmp_ddl!
    echo "^"
    echo "execute block as"
    echo "begin"
    echo "    if ( gen_id(g_stop_test,0) <> 0 ) then"
    if not .%fb%.==.25. (
        echo "        exception exc_gen_stop_test_invalid using ( gen_id(g_stop_test,0) );"
    ) else  (
        echo "        exception exc_gen_stop_test_invalid;"
    )
    echo "end ^"
    echo "set term ;^"
    echo "commit;"
    echo "drop exception exc_gen_stop_test_invalid;"
    echo "commit;"
)>!tmpsql!

call :remove_enclosing_quotes !tmpsql!

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

@rem This .sql can raise exception when:
@rem 0. Table 'semaphores' does not exist or has no field 'task' ==> previous creation was not completed:
@rem 1. Database does not exist or its name is a directory (incorrect value of config 'dbnm' parameter)
@rem 2. File <dbnm> is not a valid database
@rem 3. Database is in shutdown or in read-only mode
@rem 4. Database has incompatible ODS

call :catch_err run_isql !tmperr! !tmpsql! db_not_ready 0
@rem                1        2        3          4      5 (0=do NOT make abend of this batch)

del %tmpsql% 2>nul

set db_build_finished_ok=2

@rem NB: first line in error text depends on server OS when server has a problem with database being opened.
@rem win: I/O error during "CreateFile (open)" operation for file "c:\temp\test\badname.fdb"
@rem      -Error while trying to open file
@rem nix: I/O error during "open" operation for file "/var/db/fb25/badname.fdb"
@rem      -Error while trying to open file
@rem PS. Explanation: sql.ru/forum/actualutils.aspx?action=gotomsg&tid=1120390&msg=16689978

@rem ###########################################################
@rem WE HAVE TO IGNORE MESSAGE 'Error while trying to open file' BECAUSE IN SUCH CASE WE RECREATE DATABASE NOW.
@rem ###########################################################
set unavail_db=0
if exist !tmperr! (
    for /d %%x in ("unavailable database", "file !dbnm! is not a valid database", "database !dbnm! shutdown", "attempted update on read-only database", "unsupported on-disk structure") do (
        @rem Seems that "Is a directory" can be on linux only:
        @rem On Windows this error has text 
        @rem     I/O error during "CreateFile (open)" operation for file "
        @rem     -Error while trying to open file
        set pattern=%%x
        @rem call :dequote_string !pattern! pattern
        
        findstr /m /i /c:!pattern! !tmperr! > nul
        if NOT errorlevel 1 (
            set unavail_db=1
        )
    )
)

if .!unavail_db!.==.1. (
    call :sho "Could not connect to DB or write in it. Check parameter 'dbnm': !dbnm!." %log4tmp%
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH this batch. . .
        pause>nul
    )
    goto final
)

:chk4open
find /c /i "Error while trying to open file" %tmperr% >nul
if errorlevel 1 (

    if .%build_was_cancelled%.==.0. (

        findstr /i /c:"collation" !tmperr! | findstr /i /c:"not installed" >nul
        if NOT errorlevel 1 (
            (
                echo Missed collation. Database probably was copied from host with different ICU libraries set.
                echo Run following command locally:
                echo.
                echo !fbc!\gfix -icu !dbnm!
                echo.
                echo After this you can resume this test.
            ) > !tmplog!
            type !tmplog!
            type !tmplog!>>%log4tmp%
            del !tmplog!

            if .%can_stop%.==.1. (
                echo.
                echo Press any key to FINISH this batch. . .
                pause>nul
            )
            goto final

        )

        for /f "usebackq tokens=*" %%a in ('%tmperr%') do (
            set size=%%~za
        )
        if .!size!.==.. set size=0

        if !size! gtr 0 (
            set db_build_finished_ok=0
        ) else (
            @rem Database DOES exist and ONLINE, no errors raised before, but we still have to ensure that ALL objects 
            @rem was successfully created in it - so, check that log of last .sql contains text "all_dbo_exists"
            @rem -------------------------------------------------------------------------------------------------------
            set db_build_finished_ok=1
            find /c /i "all_dbo_exists" !tmpclg! >nul
            if errorlevel 1 (
                set db_build_finished_ok=0
            )
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
        echo Database: ^>%dbnm%^< -- DOES exist but its creation was not completed.
        echo.

        if .%wait_if_not_exists%.==.1. if .%can_stop%.==.1. (
            echo ################################################################################
            echo Press ENTER to start again recreation of all DB objects or Ctrl-C to FINISH. . .
            echo ################################################################################
            echo.
            pause>nul
        )

        set need_rebuild_db=1
        @rem ==> then we have to invoke :prepare->:make_db_objects subroutines

    ) else (
        set need_rebuild_db=0
        echo Database ^>%dbnm%^< does exist and has all needed objects.
    )
    @rem db_build_finished_ok = 0 xor 1


) else (

    @rem Text "Error while trying to open file" was found in error log.

    echo.
    echo Database file DOES NOT exist or has a problem with ACCESS.
    echo.
    if .%wait_if_not_exists%.==.1. if .%can_stop%.==.1. (
        echo Press ENTER to attempt database recreation or Ctrl-C for FINISH. . .
        echo.
        pause>nul
    )

    set need_rebuild_db=1
    @rem ==> then we have to invoke :prepare->:make_db_objects subroutine

)

del %tmpclg% 2>nul
del %tmperr% 2>nul

@rem ==BEFORE== creating database we have to check whether current FB instance
@rem does support CONNECTIONS POOL feature.
@rem If yes then we can/have to make ALTER CONNECTIONS POOL CLEAR ALL
@rem in order to drop infinite attachments that remians in FB 2.5 even
@rem after last detach; this is BY DESIGN in FB 2.5, it is not considered ad bug.

@rem ::: NOTE :::
@rem Values of 'conn_pool_support' and 'resetting_support' will be written further
@rem to the SETTINGS table in order to have ability to 'know' about these features
@rem within PSQL. See routine 'sync_settings_with_conf'.

set /a conn_pool_support=2
set /a resetting_support=2
call :chk_conn_pool_support "conn_pool_support" "resetting_support"

if .!use_es!.==.2. (
    if .!conn_pool_support!.==.0. (
        (
            echo.
            echo ### ATTENTION ### EXTERNAL CONNECTIONS POOL NOT SUPPORTED ###
            echo.
            echo Configuration parameter 'use_es' has value 2 which must be used
            echo only when Firebird instance supports External connections pool.
            echo.
            echo Firebird instance on !host!/!port! DOES NOT support this.
            echo You have to change value of 'use_es' parameter to 0.
        ) >!tmplog!
        type !tmplog!
        type !tmplog!>>%log4tmp%
        del !tmplog!

        if .1.==.0. (
            if .%can_stop%.==.1. (
                echo.
                echo Press any key to FINISH this batch. . .
                pause>nul
            )
            @rem goto final
        )

    )
)


if .%need_rebuild_db%.==.1. (
    @rem #########################   C R E A T E   D A T A B A S E   #######################
    call :prepare
)

@rem check FB config:
@rem * 4.0: 
@rem   if build >= 2260 then
@rem        get content of RDB$CONFIG table for any server IP, and check current value of UseFileSystemCache.
@rem        If UseFileSystemCache was not set then check FileSystemCacheThreshold and compare with cache buffers
@rem        that are set for !dbnm!
@rem   else
@rem      same as for 2.5 and 3.0 (see below)
@rem * 2.5 and 3.0: [ DO IT ONLY IF !host! is 'localhost' or '127.0.0.1' ]: get content of firebird.conf and extract
@rem        value of FileSystemCacheThreshold from it. Compare this value with DefaultDBCachePages for !dbnm!.
@rem If FileSystem cache can not be used - ABEND.

call :chk_FSCacheUsage

@rem ********************
@rem *** COMMON BLOCK ***
@rem ********************
@rem Ensure that current FB instance is allowed to insert records into GTT table.
@rem If FIREBIRD_TMP variable points to invalid drive then INSERT INTO GTT will fail with:
@rem    Statement failed, SQLSTATE = 08001
@rem    I/O error during "CreateFile (create)" operation for file ""
@rem    -Error while trying to create file
call :chk_db_access

if .!need_rebuild_db!.==.0. (

    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::   S y n c h r o n i z e    t a b l e    'S E T T I N G S'    w i t h    c o n f i g    :::
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    
    @rem We are in main code.
    @rem -=-=-=-=-=-=-=-=-=-=
    @rem del %log4tmp% 2>nul

    call :sync_settings_with_conf %fb% %log4tmp%
)


@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem :::   A d j u s t     D D L    f o r     's e p a r a t e _ w o r k e r s'     s e t t i n g   + :::
@rem :::   R E C R E A T E     n e e d e d   n u m b e r     o f    'PERF_LOG_SPLIT_nn'   t a b l e s :::
@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

call :adjust_sep_wrk_count %log4tmp%


@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem :::   A d j u s t     D D L    f o r     'u s e d _ i n _ r e p l i c a t i o n'     s e t t i n g   :::
@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

call :adjust_replication %log4tmp%

@rem ...................... c r e a t e _ r e s u l t s _ s t o r a g e   ............

@rem 19.10.2020. Check and create (if needed) database for storing settings and performance results 
@rem for each subsequent test run. Database will be immediately backed up after creation.
@rem See config parameter 'results_storage_fbk' for explanations.
if .!results_storage_fbk!.==.. (
    call :sho "Parameter results_storage_fbk is undefined, skip creation of separate DB for storing test results." %log4tmp%
) else (
    call :create_results_storage_fbk !results_storage_fbk! %log4tmp%
)


set sleep_mul=1

@rem NOTE: we have to declare UDF and evaluate sleep_mul even when sleep_max = 0 - it can be required
@rem to use UDF for delays between every calls of SP 'SRV_FILL_MON_CACHE_MEMORY' when  mon_unit_perf = 2
@rem (this will be done in dedicated isql session N1)

set must_decl_udf=0
if NOT .%sleep_ddl%.==.. (
    if %mon_unit_perf% EQU 2 (
        set must_decl_udf=1
    ) else (
        if %sleep_max% GTR 0 (
            set must_decl_udf=1
        )
    )
    if !must_decl_udf! EQU 1 (
        (
            echo NOTE: config parameters mon_unit_perf=%mon_unit_perf%, sleep_max=%sleep_max% - require check
            echo that UDF declared in script 'sleep_ddl'=%sleep_ddl% is OK.
        ) >>%tmpclg%
        call :bulksho %tmpclg% %log4tmp%

        call :declare_sleep_UDF %sleep_ddl% sleep_udf sleep_mul
        call :sho "Return from declare_sleep_UDF routine: sleep_udf=!sleep_udf!, sleep_mul=!sleep_mul!" %log4tmp%
    ) else (
        (
            echo NOTE: config parameter 'sleep_ddl' is forcedly assigned to EMPTY string because of other parameters
            echo that allow SKIP usage of UDF now: mon_unit_perf=%mon_unit_perf%, sleep_max=%sleep_max%
        ) >>%tmpclg%
        call :bulksho %tmpclg% %log4tmp%
        set sleep_ddl=
    )
)


@rem ################### check for non-empty stoptest.txt ################################

if  defined use_external_to_stop (
    call :chk_stop_test init_chk !tmpdir! !fbc! !dbconn! "!dbauth!"
) else (
    echo Config parameter 'use_external_to_stop' is UNDEFINED (this is DEFAULT^).
    echo SKIP checking for non-empty external file.
)     

@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem :::   A d j u s t     D D L    f o r     'u s e _ e s'    s e t t i n g:                     :::
@rem :::   enable EDS calls when use_es=2, disable when use_es=1, dont change anything otherwise  :::
@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem 20.11.2020

if not .!fb!.==.25. (

    call :sho "Adjust DDL with current 'use_es' value. Step-1: generating auxiliary script." !log4tmp!
    if .!use_es!.==.0. (
        call :sho "Code that uses ES[/EDS] will be replaced back to static PSQL." !log4tmp!
    ) else if .!use_es!.==.1. (
        call :sho "Static PSQL and code with ES/EDS will be replaced to ES-only." !log4tmp!
    ) else (
        call :sho "Static PSQL and code with ES will be replaced with ES/EDS blocks." !log4tmp!
    )

    @rem NOTE: here we can be sure that 'use_es' can be 2 *only* if External Pool is supported by current FB instance!

    set run_cmd=%fbc%\isql %dbconn% %dbauth% -nod -i %~dp0oltp_adjust_eds_calls.sql
    cmd /c !run_cmd! 1>!tmpsql! 2>!tmperr!

    call :catch_err run_cmd !tmperr! n/a

    call :sho "Adjust DDL with current 'use_es' value. Step-2: applying auxiliary script." !log4tmp!

    set run_cmd=%fbc%\isql %dbconn% %dbauth% -nod -i !tmpsql!
    cmd /c !run_cmd! 1>!tmpclg! 2>!tmperr!

    call :catch_err run_cmd !tmperr! n/a

    call :sho "Completed. Source code has been adjusted according to 'use_es' config parameter." !log4tmp!


    @rem copy !tmpsql! !tmpdir!\check_adjust.port_!port!.use_es_!use_es!.sql


    for /d %%x in (!tmpsql!,!tmpclg!) do (
        del %%x
    )


    if !use_es! EQU 2 (
        call :sho "Creating PERF_EDS_SPLIT_nn tables for logging Ext. Connections Pool event." !log4tmp!
    ) else (
        call :sho "Drop all PERF_EDS_SPLIT_nn tables that may be created for logging Ext. Connections Pool events." !log4tmp!
    )
    call :sho "Step-1: generating auxiliary script." !log4tmp!

    set run_cmd=%fbc%\isql %dbconn% %dbauth% -nod -i %~dp0oltp_adjust_eds_perf.sql
    cmd /c !run_cmd! 1>!tmpsql! 2>!tmperr!

    call :catch_err run_cmd !tmperr! n/a

    call :sho "Step-2: applying auxiliary script." !log4tmp!

    set run_cmd=%fbc%\isql %dbconn% %dbauth% -nod -i !tmpsql!
    cmd /c !run_cmd! 1>!tmpclg! 2>!tmperr!

    call :catch_err run_cmd !tmperr! n/a

    if !use_es! EQU 2 (
        call :sho "Completed. Logging of Ext. Pool events will be splitted on several PERF_EDS_SPLIT_nn tables." !log4tmp!
    ) else (
        call :sho "Completed. Objects for logging Ext. Pool events have been dropped." !log4tmp!
    )
    for /d %%x in (!tmpsql!,!tmpclg!) do (
        del %%x
    )

)
@rem fb <> 25 --> adjust code with 'use_es' and activate DB-level triggers



@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem :::   A D D    R O L E     a n d    N O N - P R I V I L E G E D     U S E R S     F O R    M O N$    :::
@rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

call :adjust_grants !mon_unit_perf! !log4tmp!


@rem 16.11.2019
@rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem :::    A d j u s t i n g     F W   a n d   S W E E P  i n t.   t o     c o n f i g    s e t t i n g   :::
@rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" !create_with_fw! !create_with_sweep!


@echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@echo :::   c h e c k    u p c o m i n g     t e s t     s e t t i n g s   :::
@echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::


@rem  08.11.2018: SP sys_get_db_arch that shows current FB instance architercute (CS/SC/SS) uses
@rem  ES/EDS in order to detect whether FB runs as Classic server or no. This ES/EDS can remain
@rem  after its finish 'infinite attachment',i.e. it will exist even after parent connection make
@rem  detach from DB (quit) -- and this will be so if current build is experimental 2.5 with support
@rem  of  CONNECTIONS POOL.
@rem  We have to run "ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;" statement in tha case.

@rem log4tmp: %tmpdir%\oltp25.prepare.log 
@rem log4all: %tmpdir%\oltp25.report.txt

call :show_db_and_test_params !conn_pool_support! %log4tmp% %log4all%

@rem #=#+#=#+#=#+#=#+#=#+#  A C T I V A T E    D B - L E V E L    T R I G G E R S  #=#+#=#+#=#+##=#+#=#+#=
(
    echo "-- Must be performed at the final stage of test preparing."
    echo "-- No output should be issued during this script work."
    echo "set bail on;"
    echo "alter trigger trg_connect active;"
    echo "set term ^;"
    echo "execute block as"
    echo "begin"
    if .!conn_pool_support!.==.1. (
        echo "    if (
        echo "        exists(select * from rdb$triggers where rdb$trigger_name = upper('TRG_DISCONNECT') )"
        echo "        and exists(select * from rdb$relations where rdb$relation_name = upper('PERF_EDS') )"
        echo "        ) then"
        echo "    begin"
        if .!use_es!.==.2. (
            echo "        execute statement 'alter trigger trg_disconnect active';"
        ) else (
            echo "        execute statement 'alter trigger trg_disconnect inactive';"
        )
    ) else (
        echo "    if ( exists( select * from rdb$triggers where rdb$trigger_name = upper('TRG_DISCONNECT')  )"
        echo "        ) then"
        echo "    begin"
        echo "        execute statement 'alter trigger trg_disconnect inactive';"
    )
    echo "    end"
    echo "end"
    echo "^"
    echo "set term ;^"
    echo "commit;"
    echo "set list on;"
    echo "set count on;"
    echo "select g.rdb$trigger_name as "Trigger name", iif(g.rdb$trigger_inactive=1, '### INACTIVE ###', 'OK, active') as "Status""
    echo "from rdb$triggers g"
    echo "where"
    echo "    g.rdb$trigger_type in ("
    echo "         8195 --  'on transaction commit'"
    echo "        ,8196 -- 'on transaction rollback'"
    echo "        ,8194 -- 'on transaction start'"
    echo "        ,8193 -- 'on disconnect'"
    echo "        ,8192 -- 'on connect'"
    echo "    ) and"
    echo "    g.rdb$system_flag is distinct from 1 ;"
) > !tmpsql!

call :remove_enclosing_quotes !tmpsql!

set run_isql=%fbc%\isql
call :repl_with_bound_quotes %run_isql% run_isql

set run_isql=!run_isql! %dbconn% %dbauth% -i %tmpsql% -q -n -nod

call :sho "Change state of DB-level triggers. Command: !run_isql!" !log4tmp!

%run_isql% 1>%tmpclg% 2>%tmperr%
(
    for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
    echo %time%. Got:
    for /f "delims=" %%a in ('type %tmpclg%') do echo STDOUT: %%a
    for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
) >>%log4tmp% 2>&1

call :catch_err run_isql !tmperr! !tmpsql! n/a
@rem                1        2        3     4

for /d %%x in (!tmpsql!,!tmpclg!) do (
    del %%x
)

@rem #=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#+#=#

if !need_rebuild_db! EQU 1 (
    if .%wait_after_create%.==.1. if .%can_stop%.==.1. (
      echo.
      echo ##################################################################################
      echo Database has been created SUCCESSFULLY and is ready for initial documents filling.
      echo ##################################################################################
      echo.
      echo Change config setting 'wait_after_create' to 0 if this pause is unneeded.
      echo.
      echo Press ENTER to go on. . .
      pause>nul
    )
)


call :gen_batch_for_stop 1stoptest.tmp info
@rem                        ^           ^
@rem                     filename       |
@rem                                 should info message be displayed ?

set existing_docs=-1
set engine=unknown_engine
set log_tab=unknown_table

call :count_existing_docs !tmpdir! !fbc! !dbconn! "!dbauth!" %init_docs% existing_docs engine log_tab
@rem                         1       2       3        4         5             6          7       8


set initd_bak=%init_docs%
set /a required_docs = init_docs - !existing_docs!

@rem echo required_docs=!required_docs!

if !required_docs! GTR 0 (

    if .%existing_docs%.==.0. (
        call :sho "Database has NO documents." !log4tmp!
    ) else (
        call :sho "There are only !existing_docs! documents in database. Required minimum is: !initd_bak!." !log4tmp!
    )

    
    call :sho "Start initial data population until total number of documents will be not less than !required_docs!." !log4tmp!

    @rem creating temp batch '!tmpdir!\1stoptest.tmp.bat' for premature stop all working ISQLs:

    @rem ############## I N I T    D A T A    P O P.   ####################

    call :run_init_pop !tmpdir! !fbc! !dbconn! "!dbauth!" !existing_docs! !required_docs! !engine! !log_tab!

    call :sho "Finish initial data population." !log4tmp!


    if .%wait_for_copy%.==.1. if .%can_stop%.==.1. (
        @echo.
        @echo ### NOTE ###
        @echo.
        @echo It's a good time to make COPY of test database in order
        @echo to start all following runs from the same state.
        @echo.
        @echo 
        @echo Press any key to begin WARM-UP and TEST mode. . .
        @pause>nul
    )

) else (
    (
        echo Database has all necessary number of documents that should be initially populated.
        echo Required minimum: %initd_bak%. Existing: at least %existing_docs%.
        echo Now we can launch working ISQL sessions.
    )>%tmpclg%

    call :bulksho %tmpclg% %log4tmp%
)
del %tmpclg% 2>nul
echo.


@echo ##############################################################
@echo ###             w o r k i n g     p h a s e                ###
@echo ##############################################################


set mode=oltp_%1

@rem winq = number of opening isqls
@rem set winq=%2
@rem if .%is_embed%.==.1. set winq=1

if /i .%unit_selection_method%.==.random. (
    set tmp_run_test_sql=%tmpdir%\sql\tmp_random_run.sql
) else (
    set tmp_run_test_sql=%tmpdir%\sql\tmp_predict_run.sql
)

set logbase=oltp%1_%computername%

@rem Make comparison of TIMESTAMPS: this batch vs %tmp_run_test_sql%.
@rem If this batch is OLDER that %tmp_run_test_sql% than we can SKIP recreating %tmp_run_test_sql%
set skipGenSQL=0

set sqldts=19000101000000
set cfgdts=19000101000000
set thisdts=19000101000000

if exist %tmp_run_test_sql% (

    @rem Check that SQL script contains test "FINISH packet" - this is LAST message
    @rem when its creation finishes w/o interruption.

    call :sho "Check that previous creation of script %tmp_run_test_sql% was not interrupted" %log4tmp%
    findstr /i /c:"FINISH packet" %tmp_run_test_sql% 1>nul
    if not errorlevel 1 (
        call :sho "Generation of script %tmp_run_test_sql% was completed w/o interruptions." %log4tmp%

        call :getFileTimestamp !tmp_run_test_sql! sqldts
        call :getFileTimestamp %~f0 thisdts

        if .!thisdts!. lss .!sqldts!. (
            call :sho "This batch is OLDER than %tmp_run_test_sql%" %log4tmp%

            call :getFileTimestamp !cfg! cfgdts

            if .!cfgdts!. lss .!sqldts!. (
                call :sho "Test config '%cfg%' is OLDER than %tmp_run_test_sql%" %log4tmp%
                set skipGenSQL=1
            ) else (
                call :sho "Test config '%cfg%' timestamp: !cfgdts! - NEWER than timestamp !sqldts! of %tmp_run_test_sql%" %log4tmp%
            )
        ) else (
            call :sho "This batch timestamp: !thisdts! - NEWER than timestamp !sqldts! of %tmp_run_test_sql%" %log4tmp%
        )
    ) else (
        call :sho "Creation of script %tmp_run_test_sql% was INTERRUPTED." %log4tmp%
    )
    echo.
    if .!skipgenSQL!.==.0. (
        call :sho "We must RECREATE %tmp_run_test_sql%" %log4tmp%
    ) else (
        call :sho "We can SKIP recreating %tmp_run_test_sql%" %log4tmp%
    )
) else (
    call :sho "Main working script '%tmp_run_test_sql%' does NOT exists." %log4tmp%
)

if not exist !tmpdir!\sql\tmp_longsleep.vbs.tmp (
    @rem #############################################################
    @rem ###   c r e a t i n g    .v b s    f o r    p a u s e s   ###
    @rem #############################################################

    (
        echo ' Generated AUTO by %~f0 at !date! !time!. Called via SHELL from %generated_sql%, do NOT edit.
        echo ' This file is used by Windows CSCRIPT.EXE for DELAYS between transactions.
        echo ' Sample: shell %systemroot%\system32\cscript.exe //nologo //e:vbscript !tmpdir!\sql\tmp_longsleep.vbs.tmp ^<sleep_min^> ^<sleep_max^>
        echo.
        echo option explicit
        echo.
        echo dim min,max,rnx
        echo.
        echo min=WScript.Arguments.Item(0^)
        echo max=WScript.Arguments.Item(1^)
        echo Randomize
        echo rnx = int( CDbl( min + (max - min^) * Rnd ^)*1000 ^)
        echo.
        echo WScript.echo "Randomly selected delay, ms: " ^& rnx
        echo WScript.Sleep( rnx ^)

    ) > !tmpdir!\sql\tmp_longsleep.vbs.tmp
)

if .%skipGenSQL%.==.0. (
    @rem Generating script to be used by working isqls.
    @rem ##################################################
    if /i .!unit_selection_method!.==.random. (
        @rem recommended value for config parameter 'actions_todo_before_reconnect': 300.
        set /a jobs_count=%actions_todo_before_reconnect%
    ) else (
        call :sho "Determine number of business calls for unit_selection_method=!unit_selection_method!" %log4tmp%
        (
            echo set list on; 
            echo select cast( maxvalue( ceiling(1 + %actions_todo_before_reconnect% / count(*^)^), 1 ^) * count(*^) as int ^) as jobs_count from business_ops;
        ) >%tmpsql%

        set isql_exe=%fbc%\isql
        call :repl_with_bound_quotes %isql_exe% isql_exe
        
        set run_isql=!isql_exe! %dbconn% %dbauth% -i %tmpsql% -q -n -nod
        call :sho "Run: !run_isql! 1^>%tmpclg% 2^>%tmperr%" %log4tmp%

        %run_isql% 1>%tmpclg% 2>%tmperr%
        for /f "tokens=2-2 delims= " %%a in ('type %tmpclg%') do (
            set /a jobs_count=%%a
        )
        call :sho "Script will contain !jobs_count! calls." %log4tmp%
    )

    @rem set /a jobs_count=3

    @rem ##########################################################################################################################################################
    call :gen_working_sql  run_test  %tmp_run_test_sql%  !jobs_count!   %no_auto_undo%  %detailed_info% %unit_selection_method% %sleep_min% %sleep_max% %sleep_udf% 
    @rem                      1               2              3                 4                 5           6                       7           8           9
    @rem ##########################################################################################################################################################

)

if not exist %tmp_run_test_sql% goto no_script

del %tmpdir%\%logbase%*.log 2>nul
del %tmpdir%\%logbase%*.err 2>nul

@rem Add 'signal' record into perf_log with current time (this row will be serve as 'anchor' in reports).
@rem Display start and planning finish of working time:

call :show_time_limits !tmpdir! !fbc! !dbconn! "!dbauth!" log4all

call :repl_with_bound_quotes %log4all% log4all

set run_vers=!fbsvcrun! info_server_version info_implementation
set run_stat=!fbsvcrun! action_db_stats sts_hdr_pages dbname %dbnm%

@rem A_FORMAT                          INPUT VARCHAR(20) default 'regular'
@rem A_BUILD                           INPUT VARCHAR(50) default ''
@rem A_NUM_OF_SESSIONS                 INPUT INTEGER default -1
@rem A_TEST_TIME_MINUTES               INPUT INTEGER default -1
@rem A_PREFIX                          INPUT VARCHAR(255) default ''
@rem A_SUFFIX                          INPUT VARCHAR(255) default ''

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
    ) >>!tmpsql!
)


(
    echo !time!. Obtaining name of final report when config parameter 'file_name_with_test_params' = %file_name_with_test_params%.
    echo Run: !run_isql! 1^>%tmpclg% 2^>%tmperr%  
) >>%log4tmp%

%run_isql% 1>%tmpclg% 2>%tmperr%


findstr /m /i /c:"<null>" %tmpclg%
if NOT errorlevel 1 (
    echo ERROR in procedure 'srv_get_report_name': can not get proper name of final report.
    type %tmpclg%
    goto final
)
if not .%file_name_with_test_params%.==.. (
    for /f %%a in (!tmpclg!) do (
        set log_with_params_in_name=!tmpdir!\%%a
        if not .%file_name_this_host_info%.==.. (
            set log_with_params_in_name=!log_with_params_in_name!_%file_name_this_host_info%
        )
        @rem ---- ?! 20.08.2018 -- 
        call :repl_with_bound_quotes !log_with_params_in_name! log_with_params_in_name
    )
) else (
    set log_with_params_in_name=%log4all%
    if not .%file_name_this_host_info%.==.. (
        set log_with_params_in_name=!log_with_params_in_name!_%file_name_this_host_info%
    )
)
call :sho "Final report will be saved with name = !log_with_params_in_name!.txt" %log4tmp%


@rem ############################
if not .%use_mtee%.==.0. (

    @rem ################################################################
    @rem Replace relative path to decompress binaries with absolute one.
    @rem ::: NB ::: Variables PARENTDIR and GRANDPDIR must be defined
    @rem at the START of this script, NOT inside if (...) block!
    @rem Otherwise replacing string will fail because their values
    @rem will not be seen here!
    @rem ################################################################
    set mtee_zip=..\util\console-output-splitters\windows_mtee.exe.zip
    set mtee_zip=!mtee_zip:..\..=%GRANDPDIR%!
    set mtee_zip=!mtee_zip:..=%PARENTDIR%!

    set tmpvbs=!tmpdir!\%~n0.zip-extractor.vbs.tmp
    call :gen_vbs_extractor !tmpvbs!
    set run_cmd=%systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !mtee_zip! !tmpdir!

    call :sho "Extract console splitter utility, target dir: !tmpdir!. Command:" !log4tmp!
    call :sho "!run_cmd!" !log4tmp!
    
    @rem ####################################
    @rem ::: NB ::: 12.11.2020
    @rem cscript returns errorlevel = 0 even when some error occured.
    @rem We have to check SIZE of STDERR output!
    @rem ####################################
    cmd /c !run_cmd! 1>!tmperr! 2>&1
    
    type !tmperr!>>!log4tmp!
    del !tmpvbs!

    @rem runcmd=!%1!
    @rem err_file=%2
    @rem sql_file=%3
    @rem add_label=%4
    @rem do_abend=%5

    call :catch_err  run_cmd   !tmperr!   n/a   n/a   1
    @rem ----------------------------------------------
    @rem                 1         2       3     4    5

    dir !tmpdir!\windows_mtee.exe | findstr /i /c:"mtee" >> !log4tmp!
    call :sho "Console splitter utility extracted Ok." !log4tmp!

    @rem result: !tmpdir!\windows_mtee.exe must exists.
)
@rem ############################

for /d %%x in (!tmpsql!,!tmpclg!,!tmperr!) do (
    del %%x 2>nul
)

@rem ###############################
echo Launching %winq% ISQL sessions:
@rem ###############################

if .1.==.0. (
    set /a sid=1
    set /a k=10000+!sid!
    echo +DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+
    echo RUN: call oltp_isql_run_worker.bat !sid!  %winq%  !conn_pool_support! tmp_run_test_sql log4all %logbase%-!k:~1,4! %fbb%   %file_name_with_test_params%

    @rem echo check result of select * from sp_get_test_time_dts
    @rem exit


    call oltp_isql_run_worker.bat !sid! %winq%  !conn_pool_support! tmp_run_test_sql log4all %logbase%-!k:~1,4! %fbb%   %file_name_with_test_params%

    @rem                            1      2               3                4            5            6            7                 8

    echo +DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+DEBUG+
    pause
    exit
)


for /l %%i in (1, 1, %winq%) do (

    echo|set /p=.

    set /a k=10000+%%i
    if .%%i.==.1. (
        (
            echo.
            echo Obtain server version and implementation info:
            echo.
        )>>%log4all%


        %run_vers% 1>>%log4all% 2>%tmperr%

        call :catch_err run_vers !tmperr! n/a nofbvers

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

    @rem Sample of %tmpdir%\%logbase%-!k:~1,4!: "C:\TEMP\logs.oltp25\oltp25_CSPROG-001"
    @rem =========
    if .%%i. EQU 1 (
        @echo #########################################
        @echo +++    l a u n c h   w o r k e r s    +++
        @echo #########################################
    )

    @start /min oltp_isql_run_worker.bat %%i %winq% !conn_pool_support! tmp_run_test_sql log4all %logbase%-!k:~1,4! %fbb%   %file_name_with_test_params%
    @rem                                  ^     ^            ^                ^             ^             ^           ^               ^
    @rem                                  1     2            3                4             5             6           7               8

)
echo. && echo %date% %time% Done.

if .%use_external_to_stop%.==.. (
  
  @rem creating temp batch 'c:\temp\1stoptest.tmp.bat' for premature stop all working ISQLs:

  call :gen_batch_for_stop 1stoptest.tmp info
  @rem                        ^           ^
  @rem                     filename       |
  @rem                                 should info message be displayed ?

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


@rem ############################################################
@rem ###                                                      ###
@rem #####                                                  #####
@rem #######    E N D     O F     M A I N    B L O C K    #######
@rem #####                                                  #####
@rem ###                                                      ###
@rem ############################################################

goto :end_of_test

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:no_arg1
    @echo off
    setlocal

    set tmplog=%1
    (
        echo.
        echo Please specify:
        echo.
        echo arg #1 =  25 ^| 30 ^| 40  ^| 50 -- major version of Firebird which will be tested:
        echo           ^^    ^^    ^^     ^^
        echo           ^|    ^|    ^|     ^|
        echo           ^|    ^|    ^|     +------ Firebird 5.x
        echo           ^|    ^|    ^|
        echo           ^|    ^|    +------------- Firebird 4.x
        echo           ^|    ^|
        echo           ^|    +------------------- Firebird 3.x
        echo           ^|
        echo.          +------------------------- Firebird 2.5.x
        echo.
        echo arg #2 =  ^<N^> -- number of ISQL sessions to be started;
        echo.
        echo arg #3 = nostop -- /optional/ skip any pauses during work 
        echo.
        echo Examples:
        echo.
        echo     1. For Firebird 2.5:
        echo.
        echo        %~f0 25 100
        echo        %~f0 25 100 nostop
        echo.
        echo     2. For Firebird 3.0:
        echo.
        echo        %~f0 30 100
        echo        %~f0 30 100 nostop
        echo.
        echo.
        echo Press any key to FINISH this batch file. . .
    ) >!tmplog!
    type !tmplog!

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    @goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:no_env
    setlocal
    set tmplog=%1
    (
        echo.
        echo #######################################################
        echo Missed at least one of necessary environment variables.
        echo #######################################################
        echo Name of variable: '%2'
        echo.
        echo Check config file '%~dp0%cfg%'.
        echo.
    ) >!tmplog!
    type !tmplog!

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    @goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:noaccess
    setlocal
    set tmplog=%1
    (
        echo.
        echo Can NOT create directory defined by config parameter 'tmpdir':
        echo !tmpdir!
        echo.
        echo Check config file '%~dp0%cfg%' and adjust this parameter.
        echo.
    ) > !abendlog!
    type !abendlog! 

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:nocscript
    setlocal
    set tmplog=%1
    (
        echo.
        echo Windows Script executive is unavaliable.
        echo Check access rights to %systemroot%\system32\cscript.exe
        echo Check Windows registry:
        echo Key: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Script Host
        echo Parameter: Enabled, type DWORD
        echo If it exists then its value must be 1.
        echo.
    ) > !abendlog!
    type !abendlog! 

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:bad_fbc_path
    @echo off
    echo.
    echo There is NO Firebird command line utilities in the folder defined by
    echo variable 'fbc' = ^>^>^>%fbc%^<^<^<
    echo.
    echo This folder has to contain following executeble files: isql, gfix, fbsvcmgr
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:bad_dbnm
    @echo off
    echo.
    echo Invalid name for database in %cfg% file: ^>%dbnm%^<
    echo.
    echo If you want that database being auto-created:
    echo 1) ensure that it specified as full path and file name rather than alias;
    echo 2) ensure that all folders in its path already exists on the host;
    echo 3) ensure that its name meet requirements of OS where Firebird runs;
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:bad_ods
    @echo off
    echo.
    echo Database ^>%dbnm%^< DOES exist but it has been created in later FB version.
    echo.
    echo 1. Ensure that you have specified proper value of 1st argument to this batch.
    echo 2. Check value of 'dbnm' parameter in file %cfg%
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:db_offline
    @echo off
    echo.
    echo Database ^>%dbnm%^< DOES exist but is OFFLINE now. Test can not start.
    echo Run first:
    echo.
    echo     %fbc%\fbsvcmgr %host%/%port%:service_mgr %dbauth% action_properties dbname %dbnm% prp_db_online
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        @pause>nul
    )
    goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:db_read_only
    @echo off
    echo.
    echo Database ^>%dbnm%^< DOES exist but in READ ONLY mode now. Test can not start.
    echo Run first:
    echo     fbsvcmgr %host%/%port%:service_mgr %dbauth% action_properties dbname %dbnm% prp_access_mode prp_am_readwrite
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        @pause>nul
    )
    goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:build_not_finished
    @echo off
    echo.
    echo Host: ^>%host%^<
    echo Port: ^>%port%^<
    echo Database: ^>%dbnm%^<
    echo.
    echo Building of database objects was INTERRUPTED or NOT STARTED.
    echo Erase this database and try to run again this batch.
    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:no_script
    @echo off
    echo.
    echo THERE IS NO .SQL SCRIPT FOR SPECIFIED SCENARIO ^>^>^>%1^<^<^<
    echo.
    if .%can_stop%.==.1. (
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:err_setenv
    @echo off
    echo.
    echo Config file: %cfg% - can NOT set some of environment variables.
    echo Perhaps, there is no equal sign ("=") between name and value in some line.
    echo.
    if .%can_stop%.==.1. (
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:test_canc
    @echo off
    echo.
    echo ##################################################################################
    echo FILE 'stoptest.txt' ON SERVER SIDE HAS NON-ZERO SIZE, MAKE IT EMPTY TO START TEST!
    echo ##################################################################################
    echo.
    if .%wait_if_not_exists%.==.1. if .%can_stop%.==.1. (
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    EXIT

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:err_del

    @echo off
    cls
    echo.
    echo Batch running now: %~f0
    echo.
    echo Can not delete file (.sql or .log) - probably it is opened in another window!
    echo.
    if .%can_stop%.==.1. (
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )
    @goto final

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:gen_working_sql
      setlocal

      echo.
      call :sho "Internal routine: gen_working_sql" %log4tmp%
      echo.

      @rem PUBL: sleep_mul
      @rem call :gen_working_sql  init_pop  %tmp_init_pop_sql%    %init_pkq%   %no_auto_undo%        0        %unit_selection_method%      0          0        %sleep_udf% 
      @rem call :gen_working_sql  run_test  %tmp_run_test_sql%  !jobs_count!   %no_auto_undo%  %detailed_info% %unit_selection_method% %sleep_min% %sleep_max% %sleep_udf% 
      @rem                            1            2                 3               4               5                    6                7          8           9

      set mode=%1

      @rem Usually smth like: C:\TEMP\logs.oltpNN\sql\tmp_random_run.sql

      set generated_sql=%2

      @rem Number of repeated pairs {execute_block, commit} in the file %generated_sql%
      set lim=%3

      @rem should NO AUTO UNDO clause be added in SET TRAN command ? 1=yes, 0=no

      if .%4.==.1. set nau=NO AUTO UNDO

      @rem should detailed info for each iteration be added in log ?
      @rem (actual only for mode=run_test; if "1" then add select * from %log_tab%)

      set nfo=%5


      set unit_selection_method=%6
      if .%6.==.. (
          set unit_selection_method=random
      )

      @rem How many seconds each ISQL worker should be idle between transactions (only when mode='run_test')
      set sleep_min=%7
      set sleep_max=%8
      set sleep_udf=%9
      if .!sleep_min!.==.. (
          set /a sleep_min=0
      )

      set tmp_gen_wrk_msg=%tmpdir%\sql\tmp_gen_working_sql.tmp

      call :sho "Starting generate SQL script for mode=%mode%. Name of file: '%generated_sql%'" %log4tmp%

      (
          echo.
          echo SQL generating routine `gen_working_sql`, input arguments:
          echo         1. Mode:                             ^|%mode%^|
          echo         2. Creating SQL script:              ^|%generated_sql%^|
          echo         3. Number of execute blocks:         ^|%lim%^|
          echo         4. Tx auto_undo clause:              ^|%nau%^|
          if /i .!mode!.==.run_test. (
              echo         5. Make detailed info after each Tx: ^|%nfo%^|
              echo         6. Units selection method:           ^|%unit_selection_method%^|
              if %sleep_max% GTR 0 (
                  if !sleep_min! GEQ !sleep_max! (
                      set /a sleep_min=1
                  )
                  echo         7. Make idle between Tx, seconds:    ^|%sleep_min% ... %sleep_max%^|
                  if .%sleep_udf%.==.. (
                      echo.           Delay is implemented by OS executable call.
                  ) else (
                      echo.           Delay is implemented by call UDF: ^|%sleep_udf%^|
                      echo.           Multiplier for delays in SECONDS: ^|%sleep_mul%^|
                  )
              ) else (
                  echo         7. NO pauses between transactions.
                  echo            *** NOTE *** 
                  echo            EXTREMELY HEAVY *UNREAL* WORKLOAD CAN OCCUR ***
              )

              if %mon_unit_perf% EQU 2 (
                  echo.
                  echo            *** NOTE *** 
                  echo            Session N1 will be used only for querying MON$ tables.
                  echo            UDF for making delay between queries: 'sleep_udf'=!sleep_udf!
              )
          )
      )  > !tmp_gen_wrk_msg!
      type !tmp_gen_wrk_msg!
      type !tmp_gen_wrk_msg! >>!log4tmp!
      del !tmp_gen_wrk_msg!

      @rem Show warning about Windows Defender - it can drastically reduce speed of SQL generating
      @rem =======================================================================================
      call :display_win_defender_notes screen !tmp_gen_wrk_msg! !log4tmp!


      del %generated_sql% 2>nul

      (
          echo -- ### WARNING: DO NOT EDIT ###
          echo -- GENERATED AUTO BY %~f0.
          echo.
          call :display_win_defender_notes sql  !tmp_gen_wrk_msg! !log4tmp!
          echo.
      ) >> %generated_sql%

      set TIL_FOR_WORK=snapshot
      if !fb! GEQ 40 (
          set TIL_FOR_WORK=read committed read consistency
          echo SET KEEP_TRAN_PARAMS ON;>>%generated_sql%
       )

      if /i .%mode%.==.init_pop. (
          (
            echo -- Check settings of database.
            echo -- NB-1: FW must be (temply^) set to OFF
            echo -- NB-2: cache buffers temply set to pretty big value
            echo set list on;
            echo select mon$database_name, mon$page_size, mon$sweep_interval, mon$page_buffers, mon$forced_writes from mon$database;
            echo set list off;
          )>>%generated_sql%
      )

      echo -- SQL script generation started at !date! !time! >> %generated_sql%
      echo.

      @rem ##################################################################################################################
      @rem ###   g e n e r a t i n g     S Q L    s c r i p t    f o r   e v e r y    s e s s i o n s - "w o r k e r s"   ###
      @rem ##################################################################################################################

      @rem NOTE, 24.12.2020: env. variables like MSG_WID, INFO_WID etc are used here
      @rem in order to prevent from runtime exceptions within EB-code:
      @rem Statement failed, SQLSTATE = 22001
      @rem arithmetic exception, numeric overflow, or string truncation
      @rem -string right truncation
      @rem -expected length NN, actual MMM

      for /l %%i in (1, 1, %lim%) do (

          set /a k = %%i %% 50
          if !k! equ 0 (
              call :sho "Generating SQL script. Iter # %%i of total %lim%" !log4tmp!
          )

          (
              echo.
              echo ------ Routine: gen_working_sql, mode = %mode%, start iter # %%i of %lim% ------
              echo.
          ) >> %generated_sql%

          if %%i equ 1 (
              echo commit; >> %generated_sql%
          ) else (
              if /i .%mode%.==.run_test. (
                  if !sleep_max! GTR 0 (
                      
                      @rem ::NB:: do NOT use here arith expression with parenthesis! Parsing error will be otherwise.
                      set /a sld=!sleep_max!-!sleep_min!
                      set /a rmv=!random!
                      set /a rmv=!random! %% !sld!
                      set /a random_delay=!sleep_min!+!rmv!

                      (
                          echo -- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
                          echo -- Config parameter 'sleep_max' = !sleep_max!. We have to make PAUSES between transactions.
                          echo -- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
                          echo set list on;

                          if NOT .!sleep_udf!.==.. (

                              @rem ==========
                              set MSG_WID=150
                              @rem ==========

                              echo set transaction read only read committed;
                              echo set term ^^;
                              echo execute block returns(" " varchar(!MSG_WID!^)^) as -- !MSG_WID!: see 'MSG_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
                              echo     declare v_lf char(1^);
                              echo     declare SECONDS_IN_MINUTE smallint = 60;
                              echo     declare taken_pause_in_seconds int;
                              echo begin
                              echo     v_lf = ascii_char(10^);
                              echo     if ( rdb$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER'^) = 1 and rdb$get_context('USER_SESSION','ENABLE_MON_QUERY'^) = 2 ^) then
                              echo         begin
                              echo             -- %mon_query_interval%: see config parameter 'mon_query_interval'
                              echo             -- MAXVALUE( %warm_time + %test_time% ^) * SECONDS_IN_MINUTE / 20: see config parameters 'warm_time' and 'test_time'
                              echo             taken_pause_in_seconds = minvalue( %mon_query_interval%, maxvalue( %warm_time% + %test_time% ^) * SECONDS_IN_MINUTE / 20 ^);
                              echo             rdb$set_context( 'USER_TRANSACTION', 'TAKE_PAUSE', taken_pause_in_seconds ^);
                              echo             " " = left( v_lf ^|^| cast('now' as timestamp^) 
                              echo                         ^|^| '. Dedicated session N1 for query to mon$ tables. Point BEFORE constant pause '
                              echo                         ^|^| taken_pause_in_seconds ^|^| ' seconds.'
                              echo                        ,!MSG_WID!^)
                              echo             ;
                              @rem             15.12.2018 18:23:23.333. Dedicated session N1 for query to mon$ tables. Point BEFORE constant pause NNN s.
                              echo         end
                              echo     else
                              echo         begin
                              echo             taken_pause_in_seconds = cast( !sleep_min! + rand(^) * (!sleep_max! - !sleep_min!^) as int ^);
                              echo             rdb$set_context( 'USER_TRANSACTION', 'TAKE_PAUSE', taken_pause_in_seconds ^);
                              echo             " " = left( v_lf ^|^| cast('now' as timestamp^)
                              echo                         ^|^| '. Point BEFORE delay within scope !sleep_min!..!sleep_max! seconds. Chosen value: ' 
                              echo                         ^|^| taken_pause_in_seconds ^|^| '. Use UDF ''!sleep_udf!''.'
                              echo                        ,!MSG_WID!^)
                              echo             ;
                              echo         end
                              echo     suspend;
                              echo end
                              echo ^^
                              echo set term ;^^

                              echo -- ############################################################
                              echo -- ###    p a u s e      u s i n g      U D F     c a l l   ###
                              echo -- ############################################################
                              echo.
                              echo -- Number of seconds are stored in CONTEXT variable 'TAKE_PAUSE' and was evaluated as RANDOM
                              echo -- value within scope sleep_min...sleep_max = !sleep_min! ... !sleep_max!.
                              echo. 
                              echo set term ^^;
                              echo execute block returns( actual_delay_in_seconds numeric(12,3^) ^) as
                              echo     declare c int;
                              echo     declare d int;
                              echo     declare t timestamp;
                              echo     declare SECONDS_IN_MINUTE smallint = 60;
                              echo begin
                              echo     -- Context var. 'TAKE_PAUSE' has been defined in previous exe_block.
                              echo     c = cast( rdb$get_context('USER_TRANSACTION', 'TAKE_PAUSE'^) as int^);
                              echo.
                              echo     t = 'now';
                              echo     while (c ^> 0^) do
                              echo     begin
                              echo         -- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
                              echo         -- -=- C A L L     U D F   F O R    S L E E P  -=-
                              echo         -- -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-
                              echo         d = !sleep_udf!( !sleep_mul! ^); -- here we wait only 1 second: we have to BREAK from this loop ASAP when test is prematurely cancelled.
                              echo.
                              echo         execute procedure sp_check_to_stop_work; -- check whether we should terminate this loop because of test cancellation
                              echo.
                              echo         c = c - 1;
                              echo         when any do
                              echo         begin
                              echo             rdb$set_context('USER_SESSION','SELECTED_UNIT', 'TEST_WAS_CANCELLED'^);
                              echo             exception;
                              echo         end
                              echo     end
                              echo     actual_delay_in_seconds = datediff(millisecond from t to cast('now' as timestamp^)^) * 1.000 / 1000;
                              echo     -- c = c  * !sleep_mul!; -- 14.11.2018: UDF can accept arg as number of PART of seconds, e.g. MILLISECONDS.
                              echo     -- c = !sleep_udf!( c ^);
                              echo     -- actual_delay_in_seconds = c * 1.000 / !sleep_mul!;
                              echo     suspend;
                              echo     rdb$set_context( 'USER_TRANSACTION', 'TAKE_PAUSE', null ^);
                              echo end
                              echo ^^
                              echo set term ;^^

                          ) else (

                              @rem Config parameter 'sleep_UDF' is commented out, i.e. undefined
                              @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

                              @rem ==========
                              set MSG_WID=128
                              @rem ==========
                              echo set term ^^;
                              echo execute block returns( " " varchar(!MSG_WID!^) ^) as -- !MSG_WID!: see 'MSG_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
                              echo     declare v_lf char(1^);
                              echo begin
                              echo     v_lf = ascii_char(10^);
                              echo     " " = left( v_lf ^|^| cast('now' as timestamp^) ^|^| '. '
                              echo                 ^|^| 'Point BEFORE delay within ' ^|^| %sleep_min% ^|^| ' ... ' ^|^| %sleep_max% ^|^|' s. Use OS shell call.'
                              echo                 ,!MSG_WID!^)
                              echo     ;
                              echo     suspend;
                              echo     rdb$set_context( 'USER_TRANSACTION', 'DELAY_START_DTS', cast( 'now' as timestamp ^) ^);
                              echo end^^
                              echo set term ;^^

                              echo -- Config parameter 'sleep_UDF' is commented out.
                              echo -- ############################################################
                              echo -- ###    p a u s e      u s i n g      S H E L L    c m d  ###
                              echo -- ############################################################
                              echo.
                              echo -- Delay is evaluated within scope sleep_min ... sleep_max = %sleep_min% ... %sleep_max%.
                              echo.
                              echo shell %systemroot%\system32\cscript.exe //nologo //e:vbscript !tmpdir!\sql\tmp_longsleep.vbs.tmp %sleep_min% %sleep_max% ;

                          )
                          @rem sleep_UDF=UNDEFINED == false / true

                          @rem ==========
                          set MSG_WID=128
                          @rem ==========
                          echo set term ^^;
                          echo execute block returns( " " varchar(!MSG_WID!^) ^) as -- !MSG_WID!: see 'MSG_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
                          echo     declare v_lf char(1^);
                          echo     declare v_dts varchar(!MSG_WID!^);
                          echo begin
                          echo     v_lf = ascii_char(10^);
                          echo     " " = left( v_lf ^|^| cast('now' as timestamp^) ^|^| '. Point AFTER delay finish.', !MSG_WID!^);
                          echo     v_dts = left( rdb$get_context( 'USER_TRANSACTION', 'DELAY_START_DTS' ^), !MSG_WID!^);
                          echo     if ( v_dts is NOT null ^) then
                          echo     begin
                          echo         " " = left (
                          echo                      " " ^|^| ' Actual delay value is: '
                          echo                          ^|^| cast( 
                          echo                                     datediff( millisecond 
                          echo                                               from cast( v_dts as timestamp^) 
                          echo                                               to cast('now' as timestamp^)
                          echo                                             ^) * 1.00 / 1000.00
                          echo                                     as numeric(12, 3^)
                          echo                                   ^) ^|^| ' s.'
                          echo                      ,!MSG_WID! ^)
                          echo         ;
                          echo         rdb$set_context( 'USER_TRANSACTION', 'DELAY_START_DTS', null ^);
                          echo     end
                          echo     suspend;
                          echo end^^
                          echo set term ;^^
                          echo commit; ------------------------ [ 2a ]
                          echo set list off;
                          echo.
                      )>>%generated_sql%

                  ) else (

                      @rem sleep_max = 0

                      (
                          echo.
                          echo -- Pause between transactions is DISABLED. HEAVY WORKLOAD CAN OCCUR BECAUSE OF THIS.
                          echo -- For enabling them assign positive value to 'sleep_max' parameter in !cfg!.
                          echo.

                          if .%mon_unit_perf%.==.2. (
                              echo -- 16.12.2018. Config parameter 'mon_unit_perf' = 2.
                              echo -- Statistics from mon$ tables is gathered in the session N1.
                              echo -- Delay must be done here if current session has number = 1.
                              @rem 22.04.2019:
                              if %test_time% GEQ 0 (
                                  echo -- Because of depening on session number, it can be implemented only using UDF call:
                                  echo -- we can not make SHELL call from PSQL "if/else" code branches.
                                  if NOT .!sleep_udf!.==.. (

                                      @rem ==========
                                      set MSG_WID=128
                                      @rem ==========

                                      echo -- .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:
                                      echo -- :.:    d e l a y    b e t w n.     m o n $    q u e r i e s,   O N L Y   i n    s e s s i o n   N 1  .:.
                                      echo -- .:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:.:
                                      echo.
                                      echo -- UDF '!sleep_udf!' is used for delay.
                                      echo.
                                      echo set transaction read only read committed;
                                      echo set heading off;
                                      echo set term ^^;
                                      echo execute block returns( " " varchar(!MSG_WID!^) ^) as -- !MSG_WID!: see 'MSG_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
                                      echo begin
                                      echo     if ( rdb$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER'^) = 1 and rdb$get_context('USER_SESSION','ENABLE_MON_QUERY'^) = 2 ^) then
                                      echo     begin
                                      echo         " " = left( cast('now' as timestamp^)
                                      echo                     ^|^| ' SID=1. This sesion is dedicated for gathering data from mon$ tables. Take pause: use UDF !sleep_udf!...'
                                      echo                     ,!MSG_WID!^)
                                      echo         ;
                                      echo         suspend;
                                      echo     end
                                      echo end
                                      echo ^^
                                      echo.
                                      echo execute block returns( " " varchar( !MSG_WID! ^) ^) as -- !MSG_WID!: see 'MSG_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
                                      echo     declare c int;
                                      echo     declare d int;
                                      echo     declare t timestamp;
                                      echo     declare SECONDS_IN_MINUTE smallint = 60;
                                      echo     declare session1_delay_before_mon_query numeric( 10, 3 ^);
                                      echo begin
                                      echo     if ( rdb$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER'^) = 1 and rdb$get_context('USER_SESSION','ENABLE_MON_QUERY'^) = 2 ^) then
                                      echo     begin
                                      echo         -- CONSTANT DELAY:
                                      echo         -- %mon_query_interval%: see config parameter 'mon_query_interval'
                                      echo         -- maxvalue(1, %warm_time% + %test_time% ^) * SECONDS_IN_MINUTE / 20: see config parameters 'warm_time' and 'test_time'
                                      echo         c = minvalue( %mon_query_interval%, maxvalue(1, %warm_time% + %test_time% ^) * SECONDS_IN_MINUTE / 20 ^);
                                      echo         t = 'now';
                                      echo         while (c ^> 0^) do
                                      echo         begin
                                      echo             -- #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
                                      echo             -- #-#   C A L L     U D F   F O R    S L E E P   #-#
                                      echo             -- #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-
                                      echo             d = !sleep_udf!( !sleep_mul! ^); -- here we wait only 1 second: we have to BREAK from this loop ASAP when test is prematurely cancelled.
                                      echo.        
                                      echo             execute procedure sp_check_to_stop_work; -- check whether we should terminate this loop because of test cancellation
                                      echo.        
                                      echo             c = c - 1;
                                      echo         when any do
                                      echo             begin
                                      echo                 rdb$set_context('USER_SESSION','SELECTED_UNIT', 'TEST_WAS_CANCELLED'^);
                                      echo                 exception;
                                      echo             end
                                      echo         end
                                      echo         session1_delay_before_mon_query = datediff(millisecond from t to cast('now' as timestamp^)^) * 1.000 / 1000;
                                      echo         " " = left( cast('now' as timestamp^)
                                      echo                     ^|^| ' SID=1. Completed pause between gathering data from mon$ tables, s: '
                                      echo                     ^|^| session1_delay_before_mon_query,
                                      echo                     !MSG_WID!^)
                                      echo         ;
                                      echo         suspend;
                                      echo     end
                                      echo end
                                      echo ^^
                                      echo set term ;^^
                                      echo commit; ------------------------ [ 2b ]
                                      echo set heading on;
                                  ) else (
                                      echo -- * WARNING * mon_unit_perf = 2: config parameter 'sleep_ddl' must be UNCOMMENTED 
                                      echo -- and has to point on existing SQL script that defined UDF declaration for delays.
                                  )
                              ) else (
                                  echo -- PAUSE IS SKIPPED: TEST LASTS TOO SHORTLY: !test_time! minutes.
                                  echo -- Increase value of config parameter 'test_time' at least to 10.
                              )
                              @rem %test_time% GEQ 10 / LSS 10
                          )
                          @rem .%mon_unit_perf%.==.2.

                      )>>%generated_sql%
                  )
                  @rem !sleep_max! GTR 0 / EQU 0

                  (
                      echo.
                      echo -- =====================================================
                      echo --     s t a r t    o f     i t e r    %%i    o f    !lim!
                      echo -- =====================================================
                      echo.
                  ) >> %generated_sql%

              )
              @rem if /i .%mode%.==.run_test.
          )

          @rem %%i EQU 1 --> true / false
              
          (
              echo.
              echo -- ################################################################
              echo -- START TRANSACTION WHICH WILL BE USED FOR BUSINESS UNIT EXECUTION
              echo -- ################################################################
              echo.

              echo set transaction !TIL_FOR_WORK! no wait %nau%; -- see config param. 'nau' for using NO AUTO UNDO

              echo set heading off;
              echo set term ^^;
              echo -- 18.01.2019. Avoid from querying rdb\$database: this can affect on performance
              echo -- in case of extremely high workload when number of attachments is ~1000 or more.

              @rem Current value of 'stop'-flag: g_stop_test = 0, test_time: 2019-03-21 09:05:31.0390 ... 2019-03-21 12:05:31.0390

              @rem ==========
              set MSG_WID=255
              @rem ==========
              echo execute block returns(" " varchar(!MSG_WID!^)^) as -- !MSG_WID!: see 'MSG_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
              echo     declare v_dts_beg timestamp;
              echo     declare v_dts_end timestamp;
              echo begin
              echo     select test_time_dts_beg, test_time_dts_end
              echo     from sp_get_test_time_dts -- this SP uses session-level context variables since its 2nd call and until reconnect
              echo     into v_dts_beg, v_dts_end;
              echo     " " = left( 'Current value of ''stop''-flag: g_stop_test = ' ^|^| gen_id(g_stop_test, 0^)
              echo                 ^|^| ', test_time: '
              echo                 ^|^| coalesce( v_dts_beg, 'null' ^)
              echo                 ^|^| ' ... '
              echo                 ^|^| coalesce( v_dts_end, 'null' ^)
              echo                 ,!MSG_WID!^)
              echo     ;
              echo     suspend;
              echo end^^
              echo set term ;^^
              echo set heading on;

              echo -- Config parameter 'unit_selection_method'=%unit_selection_method%
              if /i .%unit_selection_method%.==.random. (
                  echo -- ############################################## 
                  echo -- R A N D O M    S E L E C T    A P P.   U N I T 
                  echo -- ############################################## 
              ) else (
                  echo -- ##############################################
                  echo -- S E L E C T   P R E D I C T A B L E    U N I T
                  echo -- ##############################################
              )
              echo set term ^^;
              echo execute block as
              echo     declare v_unit dm_name;
              echo begin
              echo   if ( NOT exists( select * from sp_stoptest ^) ^) then
              echo       begin
          )>>%generated_sql%

          if /i .%mode%.==.init_pop. (
              @rem #########################################################
              @rem ###    I N I T I A L     D A T A    F I L L I N G     ###
              @rem #########################################################

              @rem When database is filled up by initial data one need only to:
              @rem 1. Add NEW documents or 
              @rem 2. Change state of existing docs
              @rem -- but we do NOT have to run any cancel operations:
              (
                  echo           -- 12.08.2018
                  echo           rdb$set_context( 'USER_SESSION', 
                  echo                            'WORKER_SEQUENTIAL_NUMBER',
                  echo                            -- %expected_workers% is 'expected_workers': typical value for count of launching ISQLs;
                  echo                            -- do NOT: mod current_transaction, %%winq%%
                  echo                            cast( 0.5 + rand(^) * %expected_workers% as int ^)
                  echo                          ^);
                  echo.
                  echo           -- For initial data population we have to select only unit that makes new document
                  echo           -- or change its state to NEXT, or does service unit. But we must SKIP any cancel op:
                  echo           select p.unit
                  echo           from srv_random_unit_choice(
                  echo                   '',
                  echo                   'creation,state_next,service,',
                  echo                   '',
                  echo                   'removal'
                  echo           ^) p
                  echo           into v_unit;
              )>>%generated_sql%
          )

          if /i .%mode%.==.run_test. (
              (
                  if .%separate_workers%.==.1. (
                      echo           if ( rand(^) * 100 ^<= %update_conflict_percent% ^) then
                      echo           begin
                      echo               -- 17.09.2018: temply change current ISQL window sequential number for increasing update-conflicts
                      if .%fb%.==.25. (
                          echo               rdb$set_context( 'USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER', (select worker_id from fn_other_rand_worker^) ^);
                      ) else (
                          echo               rdb$set_context( 'USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER', fn_other_rand_worker(^) ^);
                      )
                      echo           end
                  )

                  
                  @rem 16.12.2018
                  echo.
                  echo           v_unit = null;
                  echo           if ( rdb$get_context('USER_SESSION', 'WORKER_SEQUENTIAL_NUMBER'^) = 1 ^) then
                  echo           begin
                  echo               if ( rdb$get_context('USER_SESSION','ENABLE_MON_QUERY'^) is null ^) then
                  echo               begin
                  echo                      rdb$set_context( 'USER_SESSION', 'ENABLE_MON_QUERY', 
                  echo                                       ( select s.svalue from settings s where working_mode = upper('common'^) and mcode = upper('enable_mon_query'^) ^) 
                  echo                                     ^);
                  echo               end
                  echo.
                  echo               if ( rdb$get_context('USER_SESSION','ENABLE_MON_QUERY'^) = 2 ^) then
                  echo               begin
                  echo                   -- When config parameter 'mon_unit_perf' = 2 then we gather mon$ data by SINGLE attachment rather than by every running session.
                  echo                   -- It was decided to gather mon$ info by ISQL worker N1 and estimate affect on overall performance, see discuss with dimitr.
                  echo                   -- For this purpose we call the same SP every time:
                  echo                   v_unit = 'SRV_FILL_MON_CACHE_MEMORY' ;
                  echo               end
                  echo           end
                  echo.
                       

                  echo           -- +++++++++++++++++++++++++++++++++++++++++++++++++++
                  echo           -- +++  c h o o s e    b u s i n e s s    u n i t  +++
                  echo           -- +++++++++++++++++++++++++++++++++++++++++++++++++++
                  echo           if ( v_unit is null ^) then
                  echo           begin
                  if /i .%unit_selection_method%.==.random. (
                      echo               -- config parameter unit_selection_method = 'random'
                      echo               select p.unit
                      echo               from srv_random_unit_choice(
                      echo                   '',
                      echo                   '',
                      echo                   '',
                      echo                   ''
                      echo               ^) p
                      echo               into v_unit;
                  ) else (
                      echo               -- config parameter unit_selection_method = 'predictable'
                      echo               select p.unit
                      echo               from srv_predictable_unit_choice p
                      echo               into v_unit;
                  )
                  echo           end

              )>>%generated_sql%
          )


          (
              echo       end
              echo   else
              echo       v_unit = 'TEST_WAS_CANCELLED';
              echo.
              echo   rdb$set_context('USER_SESSION','SELECTED_UNIT', v_unit^);
              echo   rdb$set_context('USER_SESSION','ADD_INFO', null^);
              echo end
              echo ^^
              echo set term ;^^
          )>>%generated_sql%

          if /i .%mode%.==.run_test. (
              if .%mon_unit_perf%.==.1. (
                  (
                      echo -- #################################################
                      echo --  G A T H E R    M O N.    D A T A    B E F O R E
                      echo -- #################################################
                      echo.
                      echo -- Config parameter 'mon_unit_perf' = 1.
                      echo -- Statistics from mon$ tables is gathered in EVERY session.
                      echo.
                      echo set term ^^;
                      echo execute block as
                      echo   declare v_dummy bigint;
                      echo begin
                      echo   rdb$set_context('USER_SESSION','MON_GATHER_0_BEG', datediff( millisecond from timestamp '01.01.2015' to cast('now' as timestamp ^) ^) ^);
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
                      echo   rdb$set_context('USER_SESSION','MON_GATHER_0_END', datediff( millisecond from timestamp '01.01.2015' to cast('now' as timestamp ^) ^) ^);
                      echo end
                      echo ^^
                      echo set term ;^^
                      echo commit; --  ##### C O M M I T  #####  after gathering mon$data
                      echo set transaction !TIL_FOR_WORK! no wait %nau%;
                  )>>%generated_sql%

              ) else if .%mon_unit_perf%.==.2. (
                  (
                      echo -- Config parameter 'mon_unit_perf' = 2.
                      echo -- Statistics from mon$ tables is gathered in the session N1.
                      echo.

                  )>>%generated_sql%

              ) else (
                  (
                      echo -- Gathering statistics from MON$ tables DISABLED.
                      echo -- Assign value 1 to config parameter 'mon_unit_perf' for enabling this.
                  )>>%generated_sql%
              )
          )

          (
              echo.
              echo -- ensure that just before call application unit
              echo -- table tmp$perf_log is really EMPTY:
              echo delete from tmp$perf_log;
              echo.
              echo -- 18.01.2019. Avoid from querying rdb\$database: this can affect on performance
              echo -- in case of extremely high workload when number of attachments is ~1000 or more.
              echo set heading off;
              echo set term ^^;
              echo execute block returns(" " varchar(150^)^) as
              echo begin
              echo     " " = lpad('',50,'+'^) ^|^| ' Action # %%i of %lim% ' ^|^| rpad('',50,'+'^) ;
              echo     suspend;
              echo end^^
              echo set term ;^^
              echo set heading on;
              echo.
              echo set width dts 24;
              echo set width trn 14;
              echo set width att 14;
              echo set width elapsed_ms 10;
              echo set width msg 16;
              echo set width mon_logging_info 20;

              echo --------------- before run app unit: show it's NAME --------------
              @rem ==========
              set UNIT_WID=31
              set AINFO_WID=30
              @rem ==========
              echo set width add_info !AINFO_WID!; -- !AINFO_WID!: see 'AINFO_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
              echo set width unit !UNIT_WID!; -- !UNIT_WID!: see 'UNIT_WID' in  in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario

              echo set list off;
              echo -- 18.01.2019. Avoid from querying rdb$database: this can affect on performance
              echo -- in case of extremely high workload when number of attachments is ~1000 or more.
              echo set term ^^;
              echo execute block returns( dts varchar(24^), trn varchar(20^), att varchar(20^), unit varchar(!UNIT_WID!^), worker_seq int, msg varchar(16^), add_info varchar(!AINFO_WID!^) ^) as
              echo begin
              echo     dts = left(cast(current_timestamp as varchar(255^)^), 24^); -- NB, 14.04.2019: FB 4.0 adds time_zone info to current_timestamp!
              echo     trn = 'tra_' ^|^| current_transaction;
              echo     att = 'att_' ^|^| current_connection;
              echo     unit = left(rdb$get_context('USER_SESSION','SELECTED_UNIT'^), !UNIT_WID!^); 
              echo     worker_seq = cast( rdb$get_context('USER_SESSION','WORKER_SEQUENTIAL_NUMBER' ^) as int ^); 
              echo     msg = 'start';
              echo     select left( iif( current_timestamp ^< p.dts_beg, 'WARM_TIME', 'TEST_TIME'^) ^|^| ', minute N '
              echo                  ^|^| cast( iif( current_timestamp ^< p.dts_beg,
              echo                                  60*%warm_time% - datediff( second from current_timestamp to p.dts_beg ^),
              echo                                  datediff( second from p.dts_beg to current_timestamp ^)
              echo                                ^) / 60
              echo                                +1
              echo                             as varchar(10^)
              echo                           ^)
              echo                 ,!AINFO_WID!^)
              echo     from (
              echo         select p.test_time_dts_beg as dts_beg from sp_get_test_time_dts p
              echo     ^) p
              echo     into add_info;
              echo     suspend;
              echo end^^
              echo set term ;^^
              echo -- *** RESULT: ***
              echo --     +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++ Action # M of NNN +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
              echo.	
              echo --     DTS                     TRN            ATT            UNIT                              WORKER_SEQ MSG              ADD_INFO          
              echo --     ======================= ============== ============== =============================== ============ ================ =========================
              echo --     2019-01-16 12:09:12.802 tra_663        att_61         name_of_selected_business_unit            30 start            TEST_TIME, minute N 12345
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
          )>>%generated_sql%

          if /i .%mode%.==.init_pop. (
            (
              echo     -- ::: nb ::: g_init_pop is always incremented by 1
              echo     -- in sp_add_doc_list, even if fault will occur later
              echo     -- set context var 'INIT_DATA_POP' to not-null for analyzing
              echo     -- in sp_customer_reserve and others SPs and raise ex_ception
              echo     rdb$set_context('USER_TRANSACTION','INIT_DATA_POP',1^);
              echo     v_old_docs_num = gen_id( g_init_pop, 0^);
            )>>%generated_sql%
          )


          (
              echo     begin
              echo         rdb$set_context('USER_SESSION', 'GDS_RESULT', null^);
              echo         rdb$set_context('USER_SESSION', 'TOTAL_OPS_SUCCESS_INFO', null ^);
              echo         -- save value of current_transaction because we make COMMIT
              echo         -- after gathering mon$ tables when oltp_config.NN parameter
              echo         -- mon_unit_perf=1
              echo         rdb$set_context('USER_SESSION', 'APP_TRANSACTION', current_transaction^);
              echo.
              echo         -- save in ctx var timestamp of START app unit:
              echo         rdb$set_context('USER_SESSION','BAT_PHOTO_UNIT_DTS', cast('now' as timestamp^)^); -- timestamp of START business unit
              echo.
              echo         if ( rdb$get_context('USER_SESSION','SELECTED_UNIT'^)
              echo              is distinct from
              echo              'TEST_WAS_CANCELLED'
              echo           ^) then
              echo             begin
              echo                 v_stt='select count(*^) from ' ^|^| rdb$get_context('USER_SESSION','SELECTED_UNIT'^);
              echo                 -- ++++++++++++++++++++++++++++++++++++++++++++++++++++
              echo                 -- +++  l a u n c h     b u s i n e s s    u n i t  +++
              echo                 -- ++++++++++++++++++++++++++++++++++++++++++++++++++++
              echo                 execute statement (v_stt^) into result;
              echo.             
              echo                 rdb$set_context('USER_SESSION', 'RUN_RESULT',
              echo                                'OK, '^|^| result ^|^|' rows'^);
              echo.
              echo             end
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
              echo         rdb$set_context( 'USER_SESSION','BAT_PHOTO_UNIT_DTS',
              echo                          rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^)
              echo                          ^|^| ' '
              echo                          ^|^| cast('now' as timestamp^) -- concatenate start timestamp with timestamp of FINISH
              echo                       ^);
              @rem echo         -- ensure that AFTER call application unit table tmp$perf_log is really EMPTY // 21.04.2019
              @rem echo         delete from tmp$perf_log;
              @rem echo         rdb$set_context('USER_TRANSACTION','LOG_PERF_STARTED_BY', null ^); -- 21.04.2019
              echo     when any do
              echo         begin
              echo            rdb$set_context('USER_SESSION', 'GDS_RESULT', gdscode^);
          )>>%generated_sql%

          if /i .%mode%.==.init_pop. (
              (
                  echo            v_stt = 'alter sequence g_init_pop restart with '
                  echo                    ^|^|v_old_docs_num;
                  echo            execute statement (v_stt^);
              )>>%generated_sql%
          )

          (
              echo            rdb$set_context('USER_SESSION', 'RUN_RESULT', 'error, gds='^|^|gdscode^);
		      echo            -- ##############################
		      echo            -- r a i s e    e x c e p t i o n
		      echo            -- ##############################
              echo            exception;
              echo         end
              echo     end
              echo end
              echo ^^
              echo set term ;^^
              echo.
              echo SET STAT OFF;
              echo.
          )>>%generated_sql%

          if /i .%mode%.==.run_test. (
              if .%mon_unit_perf%.==.1. (
                  (
                      echo -- ###############################################
                      echo -- G A T H E R    M O N.    D A T A    A F T E R  
                      echo -- ###############################################
                      echo.
                      echo -- Config parameter 'mon_unit_perf' = 1.
                      echo -- Statistics from mon$ tables is gathered in EVERY session.
                      echo.
                      echo set term ^^;
                      echo execute block as
                      echo   declare v_dummy bigint;
                      echo begin
                      echo   rdb$set_context('USER_SESSION','MON_GATHER_1_BEG', datediff( millisecond from timestamp '01.01.2015' to cast('now' as timestamp ^) ^) ^);
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
                      echo   rdb$set_context('USER_SESSION','MON_GATHER_1_END', datediff( millisecond from timestamp '01.01.2015' to cast('now' as timestamp ^) ^) ^);
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
                      @rem 22.04.2019:
                      @rem -- do NOT otherwise tmp$perf_log become empty -- echo commit; --  ##### C O M M I T  #####  after gathering mon$data
                  )>>%generated_sql%
              
              ) else if .%mon_unit_perf%.==.2. (
                  (
                      echo -- Config parameter 'mon_unit_perf' = 2.
                      echo -- Statistics from mon$ tables has been gathered in the session N1.
                      echo.

                  )>>%generated_sql%
              )

              @rem %mon_unit_perf%==1 or 2

              (
                  echo -- ##############################################################
                  echo -- ###   S H O W    R E S U L T S    O F   E X E C U T I O N  ###
                  echo -- ##############################################################
                  echo.
                  echo set list on;
                  echo select
                  echo     v.worker_sequential_number
                  echo     ,v.test_ends_at
                  echo     ,v.last_operation_gds_code
                  echo     ,v.estimated_perf_since_test_beg
                  if .%mon_unit_perf%.==.1. (
                      echo      -- this variable will be defined in SP srv_fill_mon:
                      echo     ,v.mon_logging_info
                      @rem 17.05.2020: 'OLTP_USER_nnnn' instead of SYSDBA when FB = 3.x and above:
                      echo     ,current_user ^|^| ' ' ^|^| v.mon_gathering_time_ms as mon_gathering_user_and_time_ms
                      echo     ,v.traced_units
                  ) else if .%mon_unit_perf%.==.2. (
                      echo    ,'MON$ statistics is queried by session N1, see config parameter ''mon_unit_perf''=%mon_unit_perf%' as mon_logging_info
                  ) else (
                      echo    ,'MON$ statistics is NOT gathered, see config parameter ''mon_unit_perf''=%mon_unit_perf%' as mon_logging_info
                  )
                  echo    ,v.workload_type
                  echo    ,v.halt_test_on_errors
                  echo from v_est_perf_for_last_minute v;
                  echo set list off;
              ) >> %generated_sql%
          )
          @rem mode == run_test

          (
            echo -- ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            echo -- +++   s h o w     b u s i n e s s  _ u n i t,   e l a p s e d _ m s,     r e s u l t   m e s s a g e,   etc  +++
            echo -- ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
            echo -- Output results of application unit run:
            echo -- current_timestamp, Tx, selected_unit, elapsed_ms, result message and add_info
            echo.
            echo set width dts 24;
            echo set width trn 14;
            echo set width att 14;
            echo set width elapsed_ms 10;

            @rem +=+=+=+=+=+=+
            set UNIT_WID=31
            set OUTCOME_WID=20
            set ADDINFO_WID=60
            @rem +=+=+=+=+=+=+

            echo set width unit !UNIT_WID!;
            echo set width msg !OUTCOME_WID!;
            echo set width add_info !ADDINFO_WID!;

            echo -- 18.01.2019. Avoid from querying rdb$database: this can affect on performance
            echo -- in case of extremely high workload when number of attachments is ~1000 or more.
            echo set term ^^;
            echo -- !UNIT_WID!, !OUTCOME_WID!, !ADDINFO_WID!: see 'UNIT_WID', 'OUTCOME_WID', 'ADDINFO_WID' in routine ':gen_working_sql' of 1run_oltp_emul.bat scenario
            echo execute block returns ( dts varchar(24^), unit varchar(!UNIT_WID!^), elapsed_ms int, msg varchar(!OUTCOME_WID!^), add_info varchar(!ADDINFO_WID!^) ^) as
            echo begin
            echo     dts = left(cast(current_timestamp as varchar(255^)^), 24^); -- 14.04.2019: FB adds time_zone info to current_timestamp
            echo     -- trn = 'tra_' ^|^| rdb$get_context('USER_SESSION','APP_TRANSACTION'^);
            echo     unit = left( rdb$get_context('USER_SESSION','SELECTED_UNIT'^), !UNIT_WID!^); ------------ BUSINESS OP THAT JUST HAS COMPLETED
            echo     elapsed_ms = datediff( millisecond
            echo                            from cast(left(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^),24^) as timestamp^)
            echo                            to cast(right(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^),24^) as timestamp^)
            echo                          ^);
            echo     msg = left( rdb$get_context('USER_SESSION', 'RUN_RESULT'^), !OUTCOME_WID! ^);
            echo     add_info = left( rdb$get_context('USER_SESSION','ADD_INFO'^), !ADDINFO_WID! ^);
            echo     suspend;
            echo end^^
            echo set term ;^^
            echo -- *** RESULT: *** /after business operation finish/
            echo -- DTS          TRN            UNIT                            ELAPSED_MS MSG                  ADD_INFO
            echo -- ============ ============== =============================== ========== ==================== ========================================
            echo -- 22:09:21.823 tra_663        sp_supplier_order                     9013 OK, 5 rows           doc=211938601: created Ok
            echo --                                                                        error, gds=335544517

          ) >> %generated_sql%

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
            )>>%generated_sql%
          )

          (
              echo.
              echo set bail on; -- for catch test cancellation and stop all .sql
              echo set term ^^;
              echo execute block as
              echo begin
              echo     if ( rdb$get_context('USER_SESSION','SELECTED_UNIT'^)
              echo          is NOT distinct from
              echo          'TEST_WAS_CANCELLED'
              echo       ^) then
              echo     begin
		      echo         -- ############################################################################################
		      echo         -- ###   c a n c e l     t h i s     S Q L    s c r i p t,    r e t u r n     t o     s h e l l
		      echo         -- ############################################################################################
              echo         exception ex_test_cancellation ( select result from sys_stamp_exception('ex_test_cancellation'^) ^);
              echo     end
              echo     -- REMOVE data from context vars, they will not be used more
              echo     -- in this iteration:
              echo     rdb$set_context('USER_SESSION','SELECTED_UNIT',    null^);
              echo     rdb$set_context('USER_SESSION','RUN_RESULT',       null^);
              echo     rdb$set_context('USER_SESSION','GDS_RESULT',       null^);
              echo     rdb$set_context('USER_SESSION','ADD_INFO',         null^);
              echo     rdb$set_context('USER_SESSION','APP_TRANSACTION',  null^);
              echo     rdb$set_context('USER_SESSION','TOTAL_OPS_SUCCESS_INFO', null^);
              if /i .%mode%.==.run_test. (
                  echo     rdb$set_context('USER_SESSION','MON_GATHER_0_BEG', null^);
                  echo     rdb$set_context('USER_SESSION','MON_GATHER_0_END', null^);
                  echo     rdb$set_context('USER_SESSION','MON_GATHER_1_BEG', null^);
                  echo     rdb$set_context('USER_SESSION','MON_GATHER_1_END', null^);
                  echo     -- 17.09.2018. Restore initial value of current ISQL window sequential number
                  echo     -- 'WORKER_SEQUENTIAL_NUMBER' by its copy that was stored in 'WORKER_SEQ_NUMB_4RESTORE':
                  echo     rdb$set_context('USER_SESSION','WORKER_SEQUENTIAL_NUMBER', rdb$get_context( 'USER_SESSION', 'WORKER_SEQ_NUMB_4RESTORE' ^) ^);
              )
              echo end
              echo ^^
              echo set term ;^^
              echo set bail off;
          )>>%generated_sql%

          if /i .%mode%.==.run_test. (
            if .%nfo%.==.1. (
              (
                  echo -- Begin block to output DETAILED results of iteration.
                  echo -- To disable this output change "detailed_info" setting to 0
                  echo -- in test configuration file "%cfg%"
                  echo set list off;
                  echo set heading off;
                  echo select 'Current Tx actions:' as msg from rdb$database;
                  echo set heading on;
                  echo set list on;
                  echo set count on;
                  echo select
                  echo     -- g.id,  -- useless, always is NULL
                  echo     g.unit, g.exc_unit, g.info, g.fb_gdscode,g.trn_id,
                  echo     g.elapsed_ms, g.dts_beg, g.dts_end
                  echo from tmp$perf_log g ------------------------ GTT on commit DELETE rows
                  echo order by dts_beg;
                  echo set count off;
                  echo set list off;
                  echo -- Finish block to output DETAILED results of iteration.
              )>>%generated_sql%

            ) else (

              (
                  echo.
                  echo -- Output of detailed results of iteration DISABLED.
                  echo -- To enable this output change "detailed_info" setting to 1
                  echo -- in test configuration file "%cfg%"
              )>>%generated_sql%
            )
            @echo.>>%generated_sql%
          )

          (
              echo commit; ------------------ [ 1 ]
              echo set list off;
          )>>%generated_sql%

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
            )>>%generated_sql%
          ) else (
            (
                echo.
                echo -- =====================================================
                echo --     e n d     o f     i t e r    %%i    o f    !lim!
                echo -- =====================================================
                echo.
            )>>%generated_sql%
          )

      )
      @rem end of: for /l %%i in (1, 1, %lim%)

      echo -- SQL script generation finished at !date! !time! >> %generated_sql%

      for /f "usebackq tokens=*" %%a in ('%generated_sql%') do (
          call :sho "Generating finished. Size of script '%generated_sql%', bytes: %%~za" %log4tmp%
      )

    call :sho "Leaving routine: gen_working_sql" %log4tmp%

    endlocal
    @rem end of `gen_working_sql`

goto:eof
@rem ^
@rem end of :gen_working_sql

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:display_win_defender_notes
    setlocal
    set mode=%1
    set prefix=
    if .%mode%.==.sql. (
        set prefix= --
    )
    set tmpmsg=%2
    set joblog=%3
    (
        echo!prefix! ----------------------------------------------------------------------------------------------------
        echo!prefix! NOTE: in case when this script is generated too slow consider adding folder '%tmpdir%'
        echo!prefix! to the list of items that must be excluded from Windows Defender Antivirus scan.
        echo!prefix! You can do it in several ways:
        echo!prefix! 1. Windows Defender GUI:
        echo!prefix!    1.1 Press ^<Win-Key^> + S and type in opened field: cmd
        echo!prefix!    1.2 Right click on appearing link to command prompt and choose: "Run As Administrator"
        echo!prefix!    1.3 Session of cmd.exe with elevated access must be launched. Type there:
        echo!prefix!        "C:\Program Files\Windows Defender\msascui.exe"
        echo!prefix!    1.4 In opening window goto "Settings" and follow instructions from one of these pages:
        echo!prefix!        Windows 10:
        echo!prefix!            https://support.microsoft.com/en-us/help/4028485/windows-10-add-an-exclusion-to-windows-security
        echo!prefix!        Windows 8 or 8.1:
        echo!prefix!            https://answers.microsoft.com/en-us/protect/forum/all/how-to-exclude-a-filefolder-from-windows-defender/f32ee18f-a012-4f02-8611-0737570e8eee
        echo!prefix! 2. Start cmd.exe with elevated access and type there:
        echo!prefix!        powershell -Command Add-MpPreference -ExclusionPath "%tmpdir%"
        echo!prefix! 3. Direct modification of Windows Registry:
        echo!prefix!    3.1 Find the key for folders that must be excluded:
        echo!prefix!        HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths
        echo!prefix!    3.2 Add parameter with name = %tmpdir%, set its type to DWORD and set value to 0.
        echo!prefix! ----------------------------------------------------------------------------------------------------
    ) >!tmpmsg!
    type !tmpmsg!
    type !tmpmsg!>>!joblog!
    del !tmpmsg!

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:getFileTimestamp
    setlocal

    @rem http://www.dostips.com/DtTutoFunctions.php
    @rem Get timestamp of file in format YYYYmmDDHHMMSS.
    @rem DO NOT use wmic.exe! It can suddenly issue 'out of memory' after lot of runs.
    @rem ====================

    set tmpvbs=!tmpdir!\getFileTimeStamp.tmp.vbs
    if not exist !tmpvbs! (
        (
            echo 'Created auto, do NOT edit. Used to obtain exact timestamp of file.
            echo 'Usage: %systemroot%\system32\cscript.exe ^/^/nologo //e:vbs !tmpvbs! ^<file^>
            echo.
            echo 'Result: last modified timestamp, in format: YYYYMMDDhhmiss
            echo.
            echo Set objFS = CreateObject("Scripting.FileSystemObject"^)
            echo Set objArgs = WScript.Arguments
            echo strFile = objArgs(0^)
            echo ts = timeStamp(objFS.GetFile(strFile^).DateLastModified^)
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
        )>>!tmpvbs!
    )
    
    for /f %%a in ('%systemroot%\system32\cscript.exe //nologo //e:vbs !tmpvbs! %1') do (
        set fileDTS=%%a
    )
    endlocal & set "%~2=%fileDTS%"
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:prepare
    @rem Works Ok: create database 'localhost/3255:c:\TEMP\test fdb 2 5\e 2 1.fdb'; -- remove any quotes from path and file name
    echo.
    call :sho "Internal routine: prepare." %log4tmp%
    echo.

    setlocal

    call :try_create_db

    (
        echo Routine 'prepare'. Point before call :make_db_objects fb tmpdir fbc dbnm dbconn dbauth create_with_split_heavy_tabs
        echo.    1 fb=%fb%
        echo.    2 tmpdir=!tmpdir!
        echo.    3 fbc=!fbc!
        echo.    4 dbnm=!dbnm!
        echo.    5 dbconn=!dbconn!
        echo.    6 dbauth="!dbauth!"
        echo.    7 create_with_split_heavy_tabs=%create_with_split_heavy_tabs%
    )>>%log4tmp%

    call :make_db_objects %fb% !tmpdir! !fbc! !dbnm! !dbconn! "!dbauth!" %create_with_split_heavy_tabs%
    @rem                    1     2       3     4       5          6                 7

    call :sho "Leaving routine: prepare." %log4tmp%
   
    endlocal
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:chk_FSCacheUsage
    setlocal

    call :sho "Internal routine: chk_FSCacheUsage." %log4tmp%

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
    set FB4_BUILD_WITH_RDB_CONF=2260

    set run_cmd="!fbc!\fbsvcmgr !host!/!port!:service_mgr user !usr! password !pwd! info_server_version"
    cmd /c !run_cmd!  1>!tmpclg! 2>!tmperr!
    call :catch_err run_cmd !tmperr! n/a nofbvers

    call :bulksho !tmpclg! !log4tmp! 1

    for /f "tokens=1-3 delims= " %%a in ('findstr /i /c:version !tmpclg!') do (
      @rem Server version: WI-V2.5.9.27150 Firebird 2.5
      @rem    `       2            3

      @rem WI-V2.5.9.27150 ;  WI-T3.0.0.NNNNN etc
      set fbb=%%c

      @rem OS: WI or LI (Windows / Linux);
      set fbo=!fbb:~0,2!
    )
    call :sho "fbb=!fbb!" !log4tmp!

    set fbv=UNKNOWN
    echo !fbb! | findstr /i /r /c:"[V,T]2.5.[0-9]" > nul
    if NOT errorlevel 1 (
        set fbv=25
    )
    if /i .!fbv!.==.UNKNOWN. (
        echo !fbb! | findstr /i /r /c:"[V,T]3.[0-9].[0-9]" > nul
        if NOT errorlevel 1 (
            set fbv=30
        )
    )
    if /i .!fbv!.==.UNKNOWN. (
        echo !fbb! | findstr /i /r /c:"[V,T]4.[0-9].[0-9]" > nul
        if NOT errorlevel 1 (
            set fbv=40
        )
    )
    if /i .!fbv!.==.UNKNOWN. (
        echo !fbb! | findstr /i /r /c:"[V,T]5.[0-9].[0-9]" > nul
        if NOT errorlevel 1 (
            set fbv=50
        )
    )
    if /i .!fbv!.==.UNKNOWN. (
        call :sho "Could not get FB major version from string !fbb!" %log4tmp%
        goto :final
    )

    for /f "delims=. tokens=4" %%b in ("!fbb!") do (
        @rem WI-V2.5.9.27150
        @rem   ^   ^ ^   ^
        @rem |-1-| 2 3 |-4-|
        @rem Number of build: 27150 etc
        set /a fb_build_no=%%b
    )
    call :sho "fb_build_no=!fb_build_no!" !log4tmp!

    set check_fs_via_sql=0
    if !fbv! GTR 40 (
       @rem Future major FB versions: config must be always checked via SQL:
       set check_fs_via_sql=1
    ) else if !fbv! GEQ 40 (
       if !fb_build_no! GEQ !FB4_BUILD_WITH_RDB_CONF! (
           set check_fs_via_sql=1
       )
    )
    
    if .!check_fs_via_sql!.==.0. (

        @rem FB <= 3.x or 4.x but build less than !FB4_BUILD_WITH_RDB_CONF!
        @rem Check filesystemcache usage can be done only when host=localhost/127.0.0.1,
        @rem by obtaining content of local firebird.conf
        
        @rem do NOT put space between !host! and PIPE character here:
        echo !host!| findstr /i /b /e /c:"localhost" /c:"127.0.0.1" >nul

        if NOT errorlevel 1 (
            call :sho "Test is launched on LOCAL machine. We can obtain changed params from firebird.conf" !log4tmp!
            set fp=!fbc!\
            if .%fbv%.==.25. (
                @rem E:\FB25.TMPINSTANCE\bin ==> E:\FB25.TMPINSTANCE
                for %%m in ("!fp:~0,-1!") do set fp=%%~dpm
            )
            @rem Remove trailing backslash:
            set fp=!fp:~0,-1!

            findstr /r /c:"^^[^^#;]" !fp!\firebird.conf | findstr /i /c:"=" | findstr /i /c:"FileSystemCacheThreshold" >!tmpclg!
            if NOT errorlevel 1 (
                for /f "tokens=2 delims==" %%a in (!tmpclg!) do (
                    @rem 3.x+: this can be as 'pure' number but also with one of suffixes: 'k', 'm' or 'g'
                    @rem Each of these suffixes must be replaced with apropriate number multiplier: 1024, 1048576 and 1073741824.
                    @rem Arithmetic expression (multiplication) will be passed then to ISQL for evaluating value of FileSystemCacheThreshold.
                    @rem Value of DefaultDbCachePages will be taken from mon$database for test DB.

                    set fs_thresh=%%a
                    echo !fs_thresh! | findstr /i /c:"k">nul
                    if NOT errorlevel 1 (
                        set fs_thresh=!fs_thresh:K=!*1024
                    )
                    echo !fs_thresh! | findstr /i /c:"m">nul
                    if NOT errorlevel 1 (
                        set fs_thresh=!fs_thresh:M=!*1048576
                    )
                    echo !fs_thresh! | findstr /i /c:"g">nul
                    if NOT errorlevel 1 (
                        set fs_thresh=!fs_thresh:G=!*1073741824
                    )
                )
            ) else (
                set fs_thresh=65536
            )

            (
                echo set list on;
                echo select mon$page_buffers as DefaultDbCachePages,!fs_thresh! as FileSystemCacheThreshold, sign(!fs_thresh! - mon$page_buffers^) as test_can_run
                echo from mon$database;
            ) >!tmpsql!

            set run_isql=!fbc!\isql.exe %dbconn% %dbauth% -i !tmpsql! -q -nod
            cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!

            call :catch_err run_isql !tmperr! !tmpsql! n/a
            @rem                1       2        3      4

            for /f "tokens=1-2" %%a in (!tmpclg!) do (
                set pname=%%a
                set pchk=!pname:FILESYSTEMCACHETHRESHOLD=!
                if not .!pname!.==.!pchk!. (
                    set fs_thresh=%%b
                )
                set pchk=!pname:DEFAULTDBCACHEPAGES=!
                if not .!pname!.==.!pchk!. (
                    set db_pages=%%b
                )
                set pchk=!pname:TEST_CAN_RUN=!
                if not .!pname!.==.!pchk!. (
                    set test_can_run=%%b
                )
            )

            if not .!test_can_run!.==.1. (
                call :sho "Parameter FileSystemCacheThreshold = !fs_thresh! must have value be GREATER than DefaultDbCachePages=!db_pages!. Test can NOT run." %log4tmp%
                call :final
            ) else (
                call :sho "Value of DefaultDbCachePages = !db_pages! is less than FileSystemCacheThreshold = !fs_thresh!. Check PASSED, test can run." %log4tmp%
            )

            findstr /r /c:"^^[^^#;]" !fp!\firebird.conf | findstr /i /c:"=" | sort >!tmpclg!
            if NOT errorlevel 1 (
                @rem ###################################################################
                @rem ###                  f i r e b i r d . c o n f                  ###
                @rem ###################################################################
                call :sho "Changed parameters in !fp!\firebird.conf:" !log4tmp!
                for /f "tokens=*" %%a in (!tmpclg!) do (
                    echo.     %%a
                    echo.     %%a >> !log4tmp!
                )
            ) else (
                call :sho "All parameters in !fp!\firebird.conf are commented out." !log4tmp!
            )
            
        ) else (
            call :sho "Test uses REMOTE Firebird instance, content of firebird.conf is unavaliable." !log4tmp!
        )

    ) else (

        @rem FB > 4.x (future) or FB = 4.x and build >= !FB4_BUILD_WITH_RDB_CONF!
        call :sho "Test is launched on FB major version that allows to obtain config parameters via SQL." !log4tmp!
        (
            echo "set list on;"
            echo "select UseFileSystemCache"
            echo "       ,FileSystemCacheThreshold"
            echo "       ,DefaultDbCachePages"
            echo "       ,iif(UseFileSystemCache = 1, 1, iif(UseFileSystemCache=0, -1, sign(FileSystemCacheThreshold - DefaultDbCachePages) ) ) as test_can_run"
            echo "from ("
            echo "  select"
            echo "     coalesce(  iif(  lower(UseFileSystemCache) in ( lower('true'), lower('yes'), lower('y'), '1' )"
            echo "                     ,1"
            echo "                     ,iif(  lower(UseFileSystemCache) in ( lower('false'), lower('no'), lower('n'), '0' )"
            echo "                           ,0"
            echo "                           ,null"
            echo "                         )"
            echo "                   )"
            echo "               ,-1"
            echo "             ) as UseFileSystemCache"
            echo "    ,cast(iif(UseFileSystemCache is null, coalesce(FileSystemCacheThreshold, -1), -1) as bigint ) as FileSystemCacheThreshold"
            echo "    ,cast(DefaultDbCachePages as bigint) as DefaultDbCachePages"
            echo "  from ("
            echo "    select"
            echo "         max( iif( lower(g.rdb$config_name) = lower('UseFileSystemCache'), iif(g.rdb$config_is_set,  g.rdb$config_value, null), null) ) as UseFileSystemCache"
            echo "        ,max( iif( lower(g.rdb$config_name) = lower('FileSystemCacheThreshold'), iif(g.rdb$config_is_set,  g.rdb$config_value, null), null) ) as FileSystemCacheThreshold"
            echo "        ,max( iif( lower(g.rdb$config_name) = lower('DefaultDbCachePages'), g.rdb$config_value, '') ) as DefaultDbCachePages"
            echo "    from rdb$config g"
            echo "    where lower(g.rdb$config_name) in ( lower('UseFileSystemCache'), lower('FileSystemCacheThreshold'), lower('DefaultDbCachePages') )"
            echo "  )"
            echo ");"
        ) >!tmpsql!
        call :remove_enclosing_quotes !tmpsql!

        set run_isql=!fbc!\isql.exe %dbconn% %dbauth% -i !tmpsql! -q -nod
        call :sho "!run_isql! 1^>%tmpclg% 2^>%tmperr%" %log4tmp%
        cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!

        (
            for /f "delims=" %%a in ('type !tmpsql!') do echo RUNSQL: %%a
            echo %time%. Got:
            for /f "delims=" %%a in ('type !tmpclg!') do echo STDOUT: %%a
            for /f "delims=" %%a in ('type !tmperr!') do echo STDERR: %%a
        ) >>%log4tmp% 2>&1

        call :catch_err run_isql !tmperr! !tmpsql! mis_rdb_conf
        @rem                1       2        3         4

        for /f "tokens=1-2" %%a in (!tmpclg!) do (
            set pname=%%a
            set pchk=!pname:USEFILESYSTEMCACHE=!
            if not .!pname!.==.!pchk!. (
                set use_fscache=%%b
            )
            set pchk=!pname:FILESYSTEMCACHETHRESHOLD=!
            if not .!pname!.==.!pchk!. (
                set fs_thresh=%%b
            )
            set pchk=!pname:DEFAULTDBCACHEPAGES=!
            if not .!pname!.==.!pchk!. (
                set db_pages=%%b
            )
            set pchk=!pname:TEST_CAN_RUN=!
            if not .!pname!.==.!pchk!. (
                set test_can_run=%%b
            )
        )
        if not .!use_fscache!.==.. if not .!fs_thresh!.==.. if not .!db_pages!.==.. (
            if .!use_fscache!.==.1. (
                call :sho "FileSystem cache will be used anyway, regardless of 'FileSystemCacheThreshold' value. Check PASSED, test can run." %log4tmp%
            ) else (
                if .!use_fscache!.==.0. (
                    call :sho "FileSystem cache was explicitly DISABLED: parameter UseFileSystemCache = false. You have to replace this value with 'true'. Test can NOT run." %log4tmp%
                    call :final
                )

                @rem here we can occur only when use_fscache = -1, i.e. parameter UseFileSystemCache is commented
                if .!fs_thresh!.==.-1. (
                    call :sho "Both parameters 'UseFileSystemCache' and 'FileSystemCacheThreshold' are commented out. You have to uncomment one of them. Test can NOT run." %log4tmp%
                    call :final
                ) else (
                    if not .!test_can_run!.==.1. (
                        call :sho "Parameter FileSystemCacheThreshold = !fs_thresh! must have value be GREATER than DefaultDbCachePages=!db_pages!. Test can NOT run." %log4tmp%
                        call :final
                    ) else (
                        call :sho "Value of DefaultDbCachePages = !db_pages! is less than FileSystemCacheThreshold = !fs_thresh!. Check PASSED, test can run." %log4tmp%
                    )
                )
            )
        ) else (
            call :sho "Could not obtain value for at least one of following parameters: UseFileSystemCache, FileSystemCacheThreshold, DefaultDbCachePages" %log4tmp%
            call :sho "Perhaps SQL query became wrong. Test code needs to be corrected." %log4tmp%
            call :final
        )

        (
            echo "set width config_param_name 35;"
            echo "set width config_param_value 50;"
            echo "set width config_param_source 20;"
            echo "select"
            echo "     rdb$config_name config_param_name"
            echo "    ,iif(trim(rdb$config_value)='','[empty]',rdb$config_value) config_param_value"
            @rem echo "    ,iif(trim(rdb$config_default)='', '[empty]', rdb$config_default) config_param_default"
            echo "    ,rdb$config_source config_param_source"
            echo "from rdb$config"
            echo "where rdb$config_is_set"
            echo "order by config_param_name;"
        ) >!tmpsql!
        call :remove_enclosing_quotes !tmpsql!

        set run_isql=!fbc!\isql.exe %dbconn% %dbauth% -pag 999999 -i !tmpsql! -q -nod
        cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!
        call :catch_err run_isql !tmperr! !tmpsql! n/a
        @rem                1       2        3      4

        call :sho "Changed parameters in !fp!\firebird.conf:" !log4tmp!
        for /f "tokens=*" %%a in (!tmpclg!) do (
            echo.     %%a
            echo.     %%a >> !log4tmp!
        )

    )
    @rem check_fs_via_sql = 0 | 1

    @rem do NOT put space between !host! and PIPE character here:
    echo !host!| findstr /i /b /e /c:"localhost" /c:"127.0.0.1" >nul
    if NOT errorlevel 1 (
        set msg=OS environment variable 'FIREBIRD_TMP'
        if NOT .%FIREBIRD_TMP%.==.. (
            call :sho "!msg!: %FIREBIRD_TMP%. GTT data will be stored in this folder." !log4tmp!
        ) else (
            call :sho "!msg!: undefined. GTT data will be stored in the system TEMP folder." !log4tmp!
        )
    )
    for /d %%f in (!tmpsql!,!tmpclg!,!tmperr!) do (
        del %%f
    )

    endlocal
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:chk_db_access
    setlocal

    call :sho "Internal routine: chk_db_access." %log4tmp%

    @rem PUBL: tmpdir, fbc, %dbconn% %dbauth%, %log4tmp%

    set tmpsql=%tmpdir%\sql\tmp_chk_db_access.sql
    for /f %%a in ("!tmpsql!") do (
        set tmpclg=%%~dpna.log
        set tmperr=%%~dpna.err
    )

    call :sho "Check whether FIREBIRD_TMP allows to create and write into GTT." %log4tmp%

    @rem echo Now we have to ensure that:
    @rem echo 1. FB service can add rows to GTT, i.e. it *has* access to $FIREBIRD_TMP directory on server;
    @rem echo 2. Database is not in read-only mode: restart sequence 'g_stop_test' to 0.

    @rem Following script should NOT produce any output to STDERR. 
    @rem Otherwise we have to STOP test because of DB problem.

    (
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
         echo set echo on;
         echo set bail on;
         echo recreate GLOBAL TEMPORARY table tmp!rndname!(id int, s varchar(36^) unique using index tmp!rndname!_s_unq ^);
         echo commit;
         echo set count on;
         echo insert into tmp!rndname!(id, s ^)
         echo select rand(^)*1000, uuid_to_char(gen_uuid(^)^) from rdb$types;
         echo set list on;
         echo select min(id^) as id_min, max(id^) as id_max, count(*^) as cnt from tmp!rndname!; 
         echo commit;
         echo drop table tmp!rndname!;
         echo.
         echo -- ### RESTART sequence g_stop_test with 0 ###
         echo -- This sequence serves as 'stop-flag' for every ISQL attachment.
         echo -- Also here we check that database is not in read_only mode.
         echo.
         echo -- DISABLED 17.09.2020:
         echo -- alter sequence g_stop_test restart with 0; -- DOES NOT WORK since 4.0.0.2131: gen_id(,0^) will return -1 instead of 0.
         echo.
         echo recreate exception exc_gen_stop_test_invalid 'Test can not start because value of generator ''g_stop_test'' is NOT zero: @1';
         echo -- Added 17.09.2020:
         echo set term ^^;
         echo execute block returns(gen_stop_before_restart bigint, gen_stop_after_restart bigint^) as
         echo     declare c bigint;
         echo begin
         echo    gen_stop_before_restart = gen_id(g_stop_test,0^);
         echo    c =  gen_id(g_stop_test, -gen_id(g_stop_test, 0^)^);
         echo    gen_stop_after_restart = gen_id(g_stop_test,0^);
         echo    suspend;
         echo end
         echo ^^
         echo commit
         echo ^^
         echo execute block as
         echo begin
         echo     if ( gen_id(g_stop_test,0^) ^<^> 0 ^) then
         echo         exception exc_gen_stop_test_invalid

         if not .%fb%.==.25. (
             echo                   using ( gen_id(g_stop_test,0^) ^)
         )
         echo     ;
         echo end
         echo ^^
         echo set term ;^^
         echo commit;
         echo drop exception exc_gen_stop_test_invalid;
         echo commit;
    ) > !tmpsql!

    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe

    set run_isql=!isql_exe! %dbconn% %dbauth% -i !tmpsql! -q -nod
    call :sho "!run_isql! 1^>%tmpclg% 2^>%tmperr%" %log4tmp%
    cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!
    (
        for /f "delims=" %%a in ('type !tmpsql!') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type !tmpclg!') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type !tmperr!') do echo STDERR: %%a
    ) >>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! !tmpsql! db_cant_write 1
    @rem                1       2        3         4         5 (1 = do abort from this script).
    for /d %%f in (!tmpsql!,!tmpclg!) do (
        del %%f
    )
    call :sho "Success. GTT can be created in the folder defined by FIREBIRD_TMP. Database allows WRITE operations." %log4tmp%

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:chk_conn_pool_support
    echo.
    call :sho "Internal routine: chk_conn_pool_support." %log4tmp%
    echo.
    setlocal

    @rem PUBL: tmpdir, fbc, %dbconn% %dbauth%, %log4tmp%
    
    call :sho "Attempt to find support of EXTERNAL CONNECTIONS POOL by this FB instance." %log4tmp%

    set conn_pool_support=0
    set tmpsql=%tmpdir%\sql\tmp_chk_conn_pool.sql
    for /f %%a in ("!tmpsql!") do (
        set tmpmsg=%%~dpna.tmp
        set tmpclg=%%~dpna.log
        set tmperr=%%~dpna.err
    )

    set rndname=!random!
    set rndname=!rndname!!random!
    for /f %%a in ("%dbnm%") do (
        set rndname=%%~na.!rndname!.tmp
    )
    (
         @rem -- DO NOT BECAUSE WE HAVE TO DROP THIS DB AFTER! -- echo set bail on;
         echo create database '%host%/%port%:!rndname!' user '%usr%' password '%pwd%';
         echo set count on;
         echo set list on;
         @rem echo set echo on;
         echo select cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_SIZE'^) as int^) as pool_size,
         echo        cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_IDLE_COUNT'^) as int^) as pool_idle,
         echo        cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_ACTIVE_COUNT'^) as int^) as pool_active,
         echo        cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_LIFETIME'^) as int^) as pool_lifetime
         echo from rdb$database
         echo ;
         echo commit;
         echo set term #;
         echo create or alter trigger tmp_trg_test_resetting inactive on disconnect as
         echo begin
         echo     if (resetting^) then
         echo         begin
         echo         end
         echo end #
         echo set term ;#
         echo commit;
         echo ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;
         echo.
         echo drop database; -- ###################### DROP TEMPORARY DATABASE ###################
         echo.
    ) > !tmpsql!

    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe

    set run_isql=!isql_exe! -q -i !tmpsql! -nod
    call :sho "!run_isql! 1^>%tmpclg% 2^>%tmperr%" %log4tmp%
    cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!
    @rem ::: DO NOT ::: call :catch_err run_isql !tmperr! !tmpsql! db_not_ready 0

    (
        for /f "delims=" %%a in ('type !tmpsql!') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type !tmpclg!') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type !tmperr!') do echo STDERR: %%a
    ) >>%log4tmp% 2>&1


    @rem  for build of Firebird that does NOT support connection pool
    @rem  script will FAIL with:
    @rem  ===
    @rem    Statement failed, SQLSTATE = 42000
    @rem    Dynamic SQL Error
    @rem    -SQL error code = -104
    @rem    -Token unknown - line ..., column ...
    @rem    -CONNECTIONS
    @rem  ===

    findstr /i /c:"SQLSTATE = 42000" /c:"token unknown" !tmperr! >nul
    if NOT errorlevel 1 (
        call :sho "Result: this FB instance does NOT support connections pool feature." %log4tmp%
        set conn_pool_support=0
        set resetting_support=0
    ) else (
        findstr /i /r /c:"records affected:[ ]*1" !tmpclg! >nul
        if NOT errorlevel 1 (
            call :sho "This FB instance DOES support External Connections Pool." %log4tmp%
            set pool_size=0
            set pool_lifetime=0
            for /f "tokens=1,2" %%a in (!tmpclg!) do (
                if .!pool_size!.==.0. (
                    echo %%a | findstr /i /c:"pool_size " >nul
                    if NOT errorlevel 1 (
                        set pool_size=%%b
                    )
                )
                if .!pool_lifetime!.==.0. (
                    echo %%a | findstr /i /c:"pool_lifetime " >nul
                    if NOT errorlevel 1 (
                        set pool_lifetime=%%b
                    )
                )
            )

            if not .!pool_size!.==.0. (
                if .%use_es%.==.2. (
                    (
                        echo External connections pool ENABLED and has following parameters:
                        echo ExtConnPoolSize = !pool_size!.
                        echo ExtConnPoolLifeTime = !pool_lifetime!
                        echo Final report will have statistics about external connections pool usage.
                    ) >!tmpmsg!
                    call :bulksho !tmpmsg! %log4tmp%
                )
            ) else (
                call :sho "External connections pool is supported but now DISABLED." %log4tmp%
            )
            set conn_pool_support=1

            @rem added 12.12.2020: HQbird currently does not suppoer 'RESETTING' system variable!
            @rem If current FB instance does not support 'resetting' system variable then
            @rem STDERR file will be like this:
            @rem     Statement failed, SQLSTATE = 42S22
            @rem     unsuccessful metadata update
            @rem     -CREATE OR ALTER TRIGGER TMP_TRG_TEST_RESETTING failed
            @rem     -Dynamic SQL Error
            @rem     -SQL error code = -206
            @rem     -Column unknown
            @rem     -RESETTING

            findstr /i /c:"SQLSTATE = 42S22" /c:"Column unknown" !tmperr! >nul
            if NOT errorlevel 1 (
                call :sho "This FB instance does NOT support 'RESETTING' system variable. DB-level triggers will not refer to it." %log4tmp%
                set resetting_support=0
            ) else (
                call :sho "This FB instance supports 'RESETTING'. DB-level triggers will refer to it for logging ALTER SESSION RESET event." %log4tmp%
                set resetting_support=1
            )


        ) else (
            call :sho "Result: UNKNOWN. Check SQL script !tmpsql!" %log4tmp%
            set conn_pool_support=2
            if .%can_stop%.==.1. (
                echo.
                echo Press any key to FINISH this batch. . .
                pause>nul
            )
            goto final
        )
    )

    @rem --- end of checks related to External Pool support ---

    for /d %%f in (!tmpmsg!,!tmpsql!,!tmpclg!,!tmperr!) do (
        del %%f 2>nul
    )

    call :sho "Leaving routine: chk_conn_pool_support." %log4tmp%


    endlocal & set "%~1=%conn_pool_support%" & set "%~2=%resetting_support%"

goto:eof

@rem +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-

:replace_quotes_and_spaces
    setlocal
    set result=%1
    set result=!result: =*!
    set result=!result:"=|!
    endlocal & set "%~2=%result%"
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:try_create_db

    setlocal

    echo.
    call :sho "Internal routine: try_create_db." %log4tmp%
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

    call :sho "Leaving routine: try_create_db." %log4tmp%

    endlocal

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:create_results_storage_fbk
    setlocal

    echo.
    call :sho "Internal routine: create_results_storage_fbk" %log4tmp%
    echo.

    set results_storage_fbk=%1
    set log4all=%2
    
    set tmpsql=%tmpdir%\tmp_make_results_storage.sql
    set tmplog=%tmpdir%\tmp_make_results_storage.log
    set tmperr=%tmpdir%\tmp_make_results_storage.err
    set tmpfdb=%tmpdir%\tmp_results_storage.tmp
    del !tmpfdb! 2>nul

    if exist !tmpfdb! (
        echo Can NOT remove temporary file that will be target for restore from 'results_storage_fbk'.
        echo Name of file: %results_storage_fbk%
        echo You have to ensure that this file currently not opened by some other process.
        echo Job terminated. Press any key...
        pause>nul
        goto :final
    )

    if exist %results_storage_fbk% (

        call :sho "Backup of results storage already EXISTS, skip its recreation" %log4all%

        @rem NB: we use FB services to backup/restore to/from results_storage_fbk.
        @rem This means that file <results_storage_fbk> must be in the folder which
        @rem can be accessed by 'firebird' account. Best place for it is tha same dir as is used for !dbnm!:
        set run_cmd="%fbc%\gbak -se %host%/%port%:service_mgr -c -v -user %usr% -pas %pwd% %results_storage_fbk% !tmpfdb!"

        call :display_intention "Check ability to restore from results storage backup" !run_cmd! !tmplog! !tmperr!
        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

        @rem set runcmd=!%1!
        @rem set err_file=%2
        @rem set sql_file=%3
        @rem set add_label=%4
        @rem set do_abend=%5, default=1
        
        call :catch_err run_cmd !tmperr! n/a :fbk_storage_failed_restore
        @rem                1      2      3                4

    ) else (

      	(
            echo set echo on;
            echo set bail on;
            echo create database '!host!/!port!:!tmpfdb!' user '!usr!' password '!pwd!';
            type %~dp0\oltp_results_storage_DDL.sql
      	) >!tmpsql!
        set run_cmd="!fbc!\isql -q -c 256 -i !tmpsql!"
        call :display_intention "Generating new storage DB for tests run results." !run_cmd! !tmplog! !tmperr!
        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
        call :catch_err run_cmd !tmperr! n/a :fdb_storage_failed_create
        @rem                1      2      3                4

        set run_cmd="!fbc!\gfix -w async !host!/!port!:!tmpfdb! -user !usr! -pas !pwd!"
        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

        set run_cmd="!fbc!\gfix -use full !host!/!port!:!tmpfdb! -user !usr! -pas !pwd!"
        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
        
        @rem NB: we use FB services to backup/restore to/from results_storage_fbk.
        @rem This means that file <results_storage_fbk> must be in the folder which
        @rem can be accessed by 'firebird' account. Best place for it is tha same dir as is used for !dbnm!:
        set run_cmd="!fbc!\gbak -se %host%/%port%:service_mgr -b -v -user !usr! -pas !pwd! !tmpfdb! !results_storage_fbk!"

        call :display_intention "Back up just created results storage." !run_cmd! !tmplog! !tmperr!

        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

        call :catch_err run_cmd !tmperr! n/a :fbk_storage_failed_complete
        @rem                1      2      3                4

    )

    for /d %%x in (!tmpsql!,!tmplog!,!tmpfdb!) do (
        if exist %%x del %%x
    )

    call :sho "Leaving routine: create_results_storage_fbk" %log4tmp%


    endlocal

goto:eof
@rem ^
@rem end of subroutine 'create_results_storage_fbk'

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:make_db_objects

    setlocal
    
    echo.
    call :sho "Internal routine: make_db_objects." %log4tmp%
    echo.

    @rem call :make_db_objects %fb% !tmpdir! !fbc! !dbname! !dbconn! "!dbauth!" %create_with_split_heavy_tabs%
    set fb=%1
    set tmpdir=%2
    set fbc=%3
    set dbname=%4
    set dbconn=%5
    set dbauth=%6
    set create_with_split_heavy_tabs=%7
    if .%fb%.==.25. (
        set vers_family=25
    ) else (
        set vers_family=30
    )

    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!
    @rem Number that we establish for connection DB cache pages (when FB runs in SC/CS mode) during build DB:
    set cc_pages=1024

    set tmpsql=%tmpdir%\%~n0_%fb%.sql
    set tmplog=%tmpdir%\%~n0_%fb%.log
    set tmperr=%tmpdir%\%~n0_%fb%.err

    call :repl_with_bound_quotes %tmpsql% tmpsql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr


    set isql_exe=!fbc!\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe

    (
        echo Routine 'make_db_objects'.
        echo.    arg_1 fb=%fb%
        echo.    arg_2 tmpdir=!tmpdir!
        echo.    arg_3 fbc=!fbc!
        echo.    arg_4 dbnm=!dbnm!
        echo.    arg_5 dbconn=!dbconn!
        echo.    arg_6 dbauth="!dbauth!"
        echo.    arg_7 create_with_split_heavy_tabs=!create_with_split_heavy_tabs!
        echo.    NOTE:
        echo.    initial: isql_exe=!fbc!\isql.exe -- before repl_with_bound_quotes
        echo.    current: isql_exe=!isql_exe! -- after repl_with_bound_quotes
    )>>%log4tmp%


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
        echo quit;
    )>>%tmpsql%

    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    G h e c k     m a t c h i n g    o f    E n g i n e    a n d    u s e d     c o n f i g    :::
    @rem :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c !cc_pages! -pag 0 -i %tmpsql%
    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    %run_isql% 1>%tmplog% 2>%tmperr%
    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1
    call :catch_err run_isql !tmperr! %tmpsql%
    del %tmpsql% 2>nul

    set engine_err=0
    if .%fb%.==.25. (
        findstr /i "engine=2.5" %tmplog% 
        if errorlevel 1 set engine_err=1
    ) else (
        findstr /r /i "engine=[3-9]." %tmplog% 
        if errorlevel 1 set engine_err=1
    )
    del %tmplog% 2>nul

    if .!engine_err!.==.1. ( 
        echo Actual engine version does NOT match input argument ^>%fb%^<
        echo.
        echo Check settings 'host' and 'port' in test config file.
        echo.
        if .%can_stop%.==.1. (
            echo Press any key to FINISH this batch file. . .
            @pause>nul
        )
        goto final
    )
    echo Result: OK, actual engine version GREATER or EQUAL to specified in config.
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

    (
        echo Routine 'make_db_objects'. Point-1 before call :change_db_attr tmpdir fbc dbconn "dbauth" create_with_fw create_with_sweep
        echo.    1 tmpdir=!tmpdir!
        echo.    2 fbc=!fbc!
        echo.    3 dbconn=!dbconn!
        echo.    4 dbauth="!dbauth!"
        echo.    5 create_with_fw=async
        echo.    6 create_with_sweep=!create_with_sweep!
    )>>%log4tmp%

    call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" async !create_with_sweep!

    del %tmperr% 2>nul
    del %tmpsql% 2>nul

    (
        echo set bail on;
        echo show version;
        echo show database;
        echo set list on;
        echo select * from mon$database;
        echo set list off;
        
        @rem #######################################
        @rem invoke oltp25_DDL.sql or oltp30_DDL.sql
        @rem #######################################
        echo -- base units:
        echo in "%~dp0oltp%vers_family%_DDL.sql";

        @rem #####################################
        @rem invoke oltp25_sp.sql or oltp30_sp.sql
        @rem #####################################
        echo -- business-level units:
        echo in "%~dp0oltp%vers_family%_sp.sql";

        @rem #######################
        @rem invoke oltp_commpon.sql
        @rem #######################
        @rem Following scripts are COMMON for each version of Firebird:
        echo -- reports and other units which are the same for ant FB version:
        echo in "%~dp0oltp_common_sp.sql";

        if .%create_with_debug_objects%.==.1. (
          echo -- script for debug purposes only:
          echo in "%~dp0oltp_misc_debug.sql";
        )
        echo -- script with filling data into settings and main lookup tables:
        echo in "%~dp0oltp_main_filling.sql";
    ) >> %tmpsql%

    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c !cc_pages! -i %tmpsql%
    call :display_intention "Build database: initial phase." "!run_isql!" !tmplog! !tmperr!
    %run_isql% 1>%tmplog% 2>%tmperr%
    (
        echo %time%. Got:
        for /f "delims=" %%a in ('findstr /i /c:".sql start" /c:".sql finish" /c:"add_info" %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1
    call :catch_err run_isql !tmperr! n/a failed_bld_sql
    del %tmpsql% 2>nul


    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::   S y n c h r o n i z e    t a b l e    'S E T T I N G S'    w i t h    c o n f i g    :::
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    @rem we are in 'make_db_objects' routine
    @rem -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-

    call :sync_settings_with_conf %fb% %log4tmp%
   
    (
   
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

        @rem result: SQL script '!tmpdir!\oltp_split_heavy_tabs_1_30.tmp' will be created at this point, its name here: !post_handling_out!
        @rem put here 'echo q_uit;' if d_ebug is needed 


        echo -- Applying temp file with SQL statements for change DDL according to 'create_with_split_heavy_tabs=%create_with_split_heavy_tabs%':
        echo in !post_handling_out!;
        echo.

        echo -- Finish building process: insert custom data to lookup tables:
        echo in "%~dp0oltp_data_filling.sql";

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
        
    ) >> %tmpsql%

    del !post_handling_out! 2>nul

    (
        echo.
        echo Content of building SQL script:
        echo +++++++++++++++++++++++++++++++
        type %tmpsql%
        echo +++++++++++++++++++++++++++++++
    ) >>%log4tmp%

    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c !cc_pages! -i %tmpsql%
    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    echo :::    c r e a t i n g     d a t a b a s e     o b j e c t s    ::::
    echo ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    %run_isql% 1>%tmplog% 2>%tmperr%

    (
        echo %time%. Got:
        for /f "delims=" %%a in ('findstr /i /c:".sql start" /c:".sql finish" /c:"add_info" %tmplog%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1


    @rem operation was cancelled in 2.5: SQLSTATE = HY008 or `^C`
    @rem operation was cancelled in 3.0: SQLSTATE = HY008


    call :catch_err run_isql !tmperr! n/a failed_bld_sql

    for /d %%f in (%tmpsql%,%tmplog%,!post_handling_out!,"%tmpdir%\oltp_split_heavy_tabs_%create_with_split_heavy_tabs%_%fb%.tmp") do (
        if exist %%f (
            echo Deleting file %%f
            del %%f 2>nul
        )
    )

    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    call :sho "Done: database objects have been created SUCCESSFULLY." %log4tmp%
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::


    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem :::    A d j u s t i n g     F o r c e d     W r i t e s    t o     c o n f i g    s e t t i n g   :::
    @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    echo.

    call :sho "Restoring FORCED WRITES attribute and SWEEP interval to required value from config." %log4tmp%

    (
        echo Routine 'make_db_objects'. Point-2 before call :change_db_attr tmpdir fbc dbconn "dbauth" create_with_fw create_with_sweep
        echo.    1 tmpdir=!tmpdir!
        echo.    2 fbc=!fbc!
        echo.    3 dbconn=!dbconn!
        echo.    4 dbauth="!dbauth!"
        echo.    5 create_with_fw=!create_with_fw!
        echo.    6 create_with_sweep=!create_with_sweep!
    )>>%log4tmp%
    call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" !create_with_fw! !create_with_sweep!

    call :sho "Leaving routine: make_db_objects." %log4tmp%

    endlocal

goto:eof
@rem end of :make_db_objects

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:chk_stop_test

    setlocal

    @rem call :chk_stop_test init_chk !tmpdir! !fbc! !dbconn! !dbauth!

    @rem chk_mode = either 'init_chk' or 'pop_data'
    set chk_mode=%1

    if .%chk_mode%.==.init_chk. (
        echo.
        set msg=!time! Internal routine: chk_stop_test.
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

    del %tmpsql% 2>nul
    del %tmpclg% 2>nul

    if .%cancel_flag%.==.1. (
        call :sho "TEST IS TERMINATED: found cancel_flag=%cancel_flag%" %log4tmp%
        if exist !tmperr! (
            echo Check error log !tmperr!:
            echo -------------------------
            type !tmperr!
            echo -------------------------
        )
        goto test_canc
    )

    endlocal
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:show_db_and_test_params

    setlocal

    @rem :show_db_and_test_params !conn_pool_support! %log4tmp% %log4all%
    @rem log4tmp: %tmpdir%\oltp25.prepare.log 
    @rem log4all: %tmpdir%\oltp25.report.txt

    set conn_pool_support=%1
    set log4tmp=%2
    set log4all=%3

    call :sho "Internal routine: show_db_and_test_params." !log4tmp!

    @rem PUBL: tmpir, fbc,dbconn,dbauth,is_embed


    set tmpsql=%tmpdir%\sql\tmp_show_all_params.sql
    for /f %%a in ("!tmpsql!") do (
        set tmpclg=%%~dpna.log
        set tmperr=%%~dpna.err
    )
    del !tmpsql! 2>nul

    set db_host_name=%COMPUTERNAME%
    set db_host_name=!db_host_name:'=''!

    set tmpvbs=!tmpdir!\tmp_cpu_and_memory_info.vbs

    @rem We have to obtain CPU and RAM info: NumberOfCores and TotalPhysicalMemory.
    @rem These values will be written into SETTINGS table for saving further overall
    @rem results to seperate DB defined by config parameter 'oltp_results.fdb'

    @rem #=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#
    @rem AVOID USAGE OF CONSOLE UTILITY WMIC! IT CAN ISSUE OUT OF MEMORY!
    @rem VBS can be used to get NumberOfCores and TotalPhysicalMemory.
    @rem #=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#=#
    (
        echo ' https://www.vbsedit.com/scripts/misc/wmi/scr_1343.asp
        echo ' List System Information
        echo option explicit

        echo dim wmObj,result,o

        echo '------------------------------------------------------------
        echo function ceil(Number^)
        echo     ceil = Int(Number^)
        echo     if ceil ^<^> Number then
        echo         ceil = ceil + 1
        echo     end if
        echo end function

        echo '------------------------------------------------------------

        @rem EXCLAMATION sign must be escaped by SINGNE caret when echoed string is enclosed in double quotes:
        echo set wmObj = GetObject("winmgmts:{impersonationLevel=impersonate}^!\\.\root\cimv2"^)
        echo set result = wmObj.ExecQuery("Select * from Win32_ComputerSystem"^)
        echo for each o in result
        echo     Wscript.Echo "TotalPhysicalMemory=" ^& ceil(o.TotalPhysicalMemory/1024/1024/1024^)
        echo next

        echo set result = wmObj.ExecQuery("Select * from Win32_Processor"^)
        echo for each o in result
        echo     Wscript.Echo "NumberOfCores=" ^& o.NumberOfCores
        echo next

        echo set result=nothing
        echo set wmObj=nothing
    ) > !tmpvbs!

    %systemroot%\system32\cscript.exe //nologo /e:vbs !tmpvbs! 1>!tmpclg! 2>!tmperr!

    type !tmperr! >>!log4tmp!
    call :catch_err "Could not obtain NumberOfCores and TotalPhysicalMemory" !tmperr! n/a nosysinfo

    for /f "tokens=1,2 delims==" %%a in (!tmpclg!) do (
        set line=%%a
        if not "!line:NumberOfCores=#!"=="!line!" (
            set cpu_cores=%%b
            call :sho "CPU info: NumberOfCores=!cpu_cores!" !log4tmp!
        )
        if not "!line:TotalPhysicalMemory=#!"=="!line!" (
            set mem_total=%%b
            call :sho "RAM info: TotalPhysicalMemory=!mem_total! Gb" !log4tmp!
        )
    )
    for /d %%x in (!tmpvbs!,!tmpclg!) do (
        del %%x
    )

    
    set run_cmd="!fbc!\fbsvcmgr !host!/!port!:service_mgr user !usr! password !pwd! info_server_version"
    cmd /c !run_cmd!  1>!tmpclg! 2>!tmperr!
    call :catch_err run_cmd !tmperr! n/a nofbvers

    @rem Server version: WI-V2.5.9.27150 Firebird 2.5
    for /f "tokens=3" %%a in (!tmpclg!) do (
        set fb_vers=%%a
        for /f "delims=. tokens=4" %%b in ("!fb_vers!") do (
            @rem WI-V2.5.9.27150
            @rem |-1-| 2 3 |-4-|
            @rem Number of build: 27150 etc
            set /a fb_build_no=%%b
        )
    )

    @rem :::NOTE:::
    @rem Value of 'fb_build_no' will be written here in the SETTINGS table and further, at the final stage of test,
    @rem will be saved in <results_storage> DB by executing its SP eds_obtain_last_test_results (it will query SETTINGS
    @rem for each value that is stored in it).
    @rem Column 'fb_build_no' is participated in the PK of table 'all_fb_overall' when overall report is made.
    @rem Because of this, now it it crusial that fb_build_no has POSITIVE value.
    @rem See oltp_overall_report_DDL.sql:
    @rem recreate table all_fb_overall(
    @rem     run_id bigint          -- come from oltpNN_results.fdb; do NOT PK containing only this field!
    @rem     ,fb_build_no int       -- come from oltpNN_results.fdb; run_id + fb_build_no ==> PK
    @rem     ...
    @rem     ,constraint all_fb_overall_pk primary key(run_id, fb_build_no) using descending index all_fb_overall_pk_desc
    @rem );

    if !fb_build_no! GTR 0 (
        call :sho "Build number parsed OK: !fb_build_no!" !log4tmp!
    ) else (
        call :sho "Problem with parsing build number. Result: .!fb_build_no!. - is INVALID. Job terminated." !log4tmp!
        goto final
    )

    call :sho "Adjust table SETTINGS with current configuration..." !log4tmp!

    if not .!sleep_min!.==.. (
        set v_sleep_min=0
    ) else (
        set v_sleep_min=!sleep_min!
    )

    if .!trc_unit_perf!.==.. (
        set v_trace_units='0'
    ) else (
        set v_trace_units='!trc_unit_perf!'
    )

    echo Firebird instance and database parameters, main test settings: > !tmpclg!
    
    (
          echo "set list on;"
          echo "set width fb_arch 70;"
          echo "set term ^;"
          echo "execute block returns ("
          echo "    fb_arch varchar(50)"
          echo "   ,db_name varchar(255)"
          echo "   ,db_current_size bigint"
          echo "   ,forced_writes varchar(3)"
          echo "   ,sweep_int int"
          echo "   ,page_buffers int"
          echo "   ,page_size int"
          echo "   ,creation_timestamp timestamp"
          echo ") as"
          echo "    declare c varchar(255);"
          echo "begin"
          echo "    if ( exists(select * from rdb$procedures where rdb$procedure_name = upper('sys_get_fb_arch')) ) then"
          echo "        begin"
          echo "            select fb_arch"
          echo "            from sys_get_fb_arch('%usr%', '%pwd%')"
          echo "            into c;"
          echo "            rdb$set_context('USER_TRANSACTION', 'FB_ARCH', c);"
          echo "        end"
          echo "    else"
          echo "        begin"
          echo "            rdb$set_context('USER_TRANSACTION', 'FB_ARCH', 'UNKNOWN: no SP SYS_GET_FB_ARCH.' );"
          echo "        end"
          echo "    --------------------------------------------------------------------------------------------"
          echo "    select"
          echo "        coalesce( rdb$get_context('USER_TRANSACTION', 'FB_ARCH'), 'UNKNOWN')"
          echo "        ,m.mon$database_name"
          echo "        ,m.mon$page_size * m.mon$pages"
          echo "        ,iif(m.mon$forced_writes=0, 'OFF', 'ON')"
          echo "        ,m.mon$sweep_interval"
          echo "        ,m.mon$page_buffers"
          echo "        ,m.mon$page_size"
          echo "        ,m.mon$creation_date"
          echo "    from mon$database m"
          echo "    into"
          echo "        fb_arch"
          echo "        ,db_name"
          echo "        ,db_current_size"
          echo "        ,forced_writes"
          echo "        ,sweep_int"
          echo "        ,page_buffers"
          echo "        ,page_size"
          echo "        ,creation_timestamp;"
          echo "    suspend;"

          echo "    -- 24.10.2020: add settings which will be used only AFTER TEST for saving its overall results to seperate DB: 'oltp_results.fdb'."
          echo "    -- NOTE: all these settings are NOT needed by ISQL workers thus we can set working_mode='INIT' rather than 'COMMON'."
          echo "    -- This allows to avoid excessive usage of session-level context variables:"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('cpu_cores'), !cpu_cores! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('mem_total'), !mem_total! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('db_host_name'), '!db_host_name!' )"
          echo "    matching (working_mode, mcode);"

          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('fb_arch'), :fb_arch )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('fb_engine'), rdb$get_context('SYSTEM', 'ENGINE_VERSION') )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('fb_build_no'), !fb_build_no! )"
          echo "    matching (working_mode, mcode);"

          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('db_name'), :db_name )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('db_file_size'), :db_current_size )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('db_fw'), iif(upper(:forced_writes) = upper('ON'),1,0)  )"
          echo "    matching (working_mode, mcode);"

          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('sweep_int'), :sweep_int )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('page_buffers'), :page_buffers )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('page_size'), :page_size )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('db_created'), :creation_timestamp )"
          echo "    matching (working_mode, mcode);"

          echo "    -- do not add 'workers_count, this is done in routine 'inject_actual_setting'"

          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('test_time'), !test_time! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('mon_query_interval'), !mon_query_interval! )"
          echo "    matching (working_mode, mcode);"

          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('no_auto_undo'), !no_auto_undo! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('run_db_statistics'), !run_db_statistics! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('run_db_validation'), !run_db_validation! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('sleep_min'), !v_sleep_min! )"
          echo "    matching (working_mode, mcode);"

          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('sleep_max'), !sleep_max! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('trc_unit_perf'), !v_trace_units! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('detailed_info'), !detailed_info! )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('expected_workers'), !expected_workers! )"
          echo "    matching (working_mode, mcode);"

          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('test_phase_beg'), dateadd( !warm_time! minute to cast('now' as timestamp) ) )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('test_phase_end'), dateadd( !warm_time! + !test_time! minute to cast('now' as timestamp) ) )"
          echo "    matching (working_mode, mcode);"
          echo "    update or insert into settings(working_mode, mcode, svalue) values( upper('init'), upper('warm_phase_beg'), cast('now' as timestamp) )"
          echo "    matching (working_mode, mcode);"

          echo "end"
          echo "^"
          echo "set term ;^"

          echo "set list off;"
          echo "set width working_mode 12;"
          echo "set width setting_name 40;"
          echo "set width setting_value 20;"
          echo "set heading off;"
          echo "select 'Workload level settings (see definitions in oltp_main_filling.sql):' as " " from rdb$database;"
          echo "set heading on;"
          echo "select * from z_settings_pivot;"

          echo "set heading off;"
          echo "select 'Current launch settings:' as " " from rdb$database;"
          echo "set heading on;"
          echo "select z.setting_name, z.setting_value from z_current_test_settings z;"

          echo "set width tab_name 13;"
          echo "set width idx_name 31;"
          echo "set width idx_key 65;"
          echo "-- NORMALLY MUST BE DISABLED. ENABLE FOR DEBUG OR BENCHMARK PURPOSES."
          echo "-- set heading off;"
          echo "-- select 'Index(es) for heavy-loaded tables:' as " " from rdb$database;"
          echo "-- set heading on;"
          echo "-- select * from z_qd_indices_ddl;"
          echo "set heading off;"
          echo "select 'Table(s) WITHOUT primary and unique constrains:' as " " from rdb$database;"
          echo "set heading on;"
          echo "set count on;"
          echo "set width tab_name 32;"
          echo "select distinct r.rdb$relation_name as tab_name"
          echo "from rdb$relations r"
          echo "left join rdb$relation_constraints c on"
          echo "    r.rdb$relation_name = c.rdb$relation_name"
          echo "    and c.rdb$constraint_type in( 'PRIMARY KEY', 'UNIQUE' )"
          echo "where"
          echo "    r.rdb$system_flag is distinct from 1"
          echo "    and r.rdb$relation_type = 0"
          echo "    and c.rdb$relation_name is null;"
          echo "set count off;"
    ) > !tmpsql!

    if !conn_pool_support! EQU 1 (
        @rem ::: NB ::: 05.11.2018
        @rem PSQL function sys_get_fb_arch uses ES/EDS which keeps infinitely connection in implementation for FB 2.5
        @rem If current implementation actually supports connection pool then we have to clear it, otherwise idle
        @rem connection will use metadata and we will not be able to drop existing PK from some tables.
        (
            echo "set bail on;"
            echo "create or alter view tmp$view$pool_info as"
            echo "select"
            echo "   cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_SIZE') as int) as pool_size,"
            echo "   cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_IDLE_COUNT') as int) as pool_idle,"
            echo "   cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_ACTIVE_COUNT') as int) as pool_active,"
            echo "   cast(rdb$get_context('SYSTEM', 'EXT_CONN_POOL_LIFETIME') as int) as pool_lifetime"
            echo "from rdb$database;"
            echo "commit;"
            echo "select 'Before clear connections pool' as msg, v.* from tmp$view$pool_info v;"
            echo "ALTER EXTERNAL CONNECTIONS POOL CLEAR ALL;"
            echo "select 'After clear connections pool' as msg, v.* from tmp$view$pool_info v;"
            echo "commit;"
            echo "drop view tmp$view$pool_info;"
            echo "commit;"
            echo "set bail off;"
        ) >>!tmpsql!
    )

    call :remove_enclosing_quotes !tmpsql!
    
    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe

    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -pag 999999 -i !tmpsql!

    cmd /c !run_isql! 1>>!tmpclg! 2>!tmperr!

    (
        for /f "delims=" %%a in ('type %tmpsql%') do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in ('type %tmpclg%') do echo STDOUT: %%a
        for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
    )>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! !tmpsql! failed_show_params


    type %tmpclg% >> %log4tmp%
    type %tmpclg% >> %log4all%

    call :sho "Table SETTINGS successfully adjusted with current settings." !log4tmp!


    for /d %%f in (!tmpsql!,!tmpclg!) do (
        del %%f
    )

    set fbv=30
    echo %fbb% | findstr /i /c:"V2.5" /c:"T2.5" > nul
    if NOT errorlevel 1 (
        set fbv=25
    )

    (
         @rem 18.09.2018
         @rem #####################################################################################
         @rem ###   s h o w     p a r a m s     f r o m      o l t p N N _ c o n f i g . w i n  ###
         @rem #####################################################################################
         echo.
         echo !date! !time!. Test uses config file '%cfg%' with following parameters:
         echo.
         @rem for /f "tokens=*" %%a in ('findstr /r /c:"^[^#;]" %cfg% ^| findstr /i /c:"=" ^| sort') do (
         for /f "tokens=*" %%a in ('findstr /r /v /c:"#" %cfg% ^| findstr /i /c:"=" ^| sort') do (

             echo.     %%a
         )
        
        echo.
        echo Connection string: !dbconn!
        echo !dbconn! | findstr /r /i /c:"localhost[/:]" /c:"127.0.0.1[/:]" >nul
        if NOT errorlevel 1 (
            @rem 20.08.2018 Test is launched on LOCAL machine --> we can obtain changed params from firebird.conf
            set fp=!fbc!\
            if .%fbv%.==.25. (
                @rem E:\FB25.TMPINSTANCE\bin ==> E:\FB25.TMPINSTANCE
                for %%m in ("!fp:~0,-1!") do set fp=%%~dpm
            )
            @rem Remove trailing backslash:
            set fp=!fp:~0,-1!

            (
                echo.
                echo !date! !time!. Changed parameters in !fp!\firebird.conf:
                echo.
            )

            findstr /m /r /c:"^[^#;]" !fp!\firebird.conf >nul
            if NOT errorlevel 1 (
                @rem ###################################################################
                @rem ###                  f i r e b i r d . c o n f                  ###
                @rem ###################################################################
                for /f "tokens=*" %%a in ('findstr /r /c:"^^[^^#;]" !fp!\firebird.conf ^| findstr /i /c:"=" ^| sort') do (
                    echo.     %%a
                )
            ) else (
                echo There are NO uncommented parameters, all of them have DEFAULT values.
            )
            echo.
            if NOT .%FIREBIRD_TMP%.==.. (
                echo Value of 'FIREBIRD_TMP': %FIREBIRD_TMP%, GTT data will be stored in this folder.
            ) else (
                echo Variable 'FIREBIRD_TMP' undefined, GTT data will be stored in system TEMP folder.
            )
            echo.
        ) else (
            echo !date! time!. Test uses REMOTE Firebird instance, content of firebird.conf is unavaliable.
        )
    ) > !tmpclg!

    @rem type !tmpclg!
    type !tmpclg! >> %log4all%
    del !tmpclg!

    call :sho "All other parameters are shown in %log4all%." !log4tmp!

    findstr /m /i /c:"DefaultDbCachePages" !tmpclg! >nul
    if NOT errorlevel 1 (
        findstr /m /i /c:"FileSystemCacheThreshold" !tmpclg! >nul
        if errorlevel 1 (
            (
                echo ###  A C H T U N G  ###     YOU MUST DEFINE PARAMETER 'FileSystemCacheThreshold'
                echo.
                echo You have to EXPLICITLY define parameter 'FileSystemCacheThreshold' in firebird.conf, regardless that it can be commented.
                echo Please add it and assign value NOT LESS than number of pages that is specified for 'DefaultDbCachePages'.
                echo NOTE that since Firebird 3.0 both DefaultDbCachePages and FileSystemCacheThreshold can be set per database-level.
            ) >!tmpclg!
            type !tmpclg!
            type !tmpclg! >> %log4all%
            echo.
            echo Press any key to FINISH this batch. . .
            del !tmpclg! 2>nul
            pause>nul
            goto final
        )
    )

    @rem Logging DDL of QDistr / XQD* indices: do NOT run it here, it will appear in final report by call from oltp_run_worker

    call :sho "Leaving routine: show_db_and_test_params." %log4tmp%

    endlocal

goto:eof
@rem end of: show_db_and_test_params

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:count_existing_docs
    
    setlocal

    echo.
    call :sho "Internal routine: count_existing_docs." %log4tmp%
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
    
    set run_isql=!run_isql! %dbconn% %dbauth% -nod -pag 0 -n -i %tmpsql%

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

    call :sho "Leaving routine: count_existing_docs." %log4tmp%

    endlocal & set "%~6=%existing_docs%" & set "%~7=%engine%" & set "%~8=%log_tab%"

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:run_init_pop

    @rem --------------   i n i t i a l      d a t a     p o p u l a t i o n   -------------

    setlocal

    echo.
    call :sho "Internal routine: run_init_pop." %log4tmp%

    set skip_fbsvc=0

    @rem call :r~un_init_pop !tmpdir! !fbc! !dbconn! "!dbauth!" %existing_docs% %init_docs% %engine% %log_tab%

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
    
    set tmp_init_pop_sql=%tmpdir%\sql\tmp_init_data_pop.sql
    for /f %%a in ("!tmp_init_pop_sql!") do (
        set tmplog=%%~dpna.log
        set tmperr=%%~dpna.err
        set tmpchk=%%~dpna.chk
        set tmpclg=%%~dpna.clg
        set tmpmsg=%%~dpna.tmp
    )

    call :repl_with_bound_quotes %tmp_init_pop_sql% tmp_init_pop_sql
    call :repl_with_bound_quotes %tmplog% tmplog
    call :repl_with_bound_quotes %tmperr% tmperr
    call :repl_with_bound_quotes %tmpchk% tmpchk
    call :repl_with_bound_quotes %tmpclg% tmpclg

    for /d %%f in (!tmp_init_pop_sql!,!tmplog!,!tmperr!,!tmpchk!,!tmpclg!,!tmpmsg!) do (
        if exist %%f del %%f
        if exist goto err_del
    )

   
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
        echo set list on;
        echo select iif(mon$forced_writes = 1, 'sync', 'async' ^) as "current_fw=" from mon$database;
        echo set list off;
    ) > !tmp_init_pop_sql!

    @rem --- Run ISQL: restart sequence g_init_pop ---
    
    echo Preparing for initial population of documents: restart value of sequence g_init_pop.

    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe
   
    set run_isql=!isql_exe! %dbconn% %dbauth% -q -i !tmp_init_pop_sql!

    echo %time%. Run: %run_isql% 1^>%tmplog% 2^>%tmperr% >>%log4tmp%

    cmd /c !run_isql! 1>!tmplog! 2>!tmperr!

    (
        for /f "delims=" %%a in (%tmp_init_pop_sql%) do echo RUNSQL: %%a
        echo %time%. Got:
        for /f "delims=" %%a in (%tmplog%) do echo STDOUT: %%a
        for /f "delims=" %%a in (%tmperr%) do echo STDERR: %%a
    ) 1>>%log4tmp% 2>&1

    call :catch_err run_isql !tmperr! !tmp_init_pop_sql! failed_reset_pop_gen

    set current_fw=unknown
    for /F "tokens=*" %%a in ('findstr /i /c:"current_fw" %tmplog%') do (
        set %%a
        call :trim current_fw !current_fw!
    )

    echo Current FW (will be restored after data population^): ^|%current_fw%^|.



    del %tmp_init_pop_sql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul


    (
        echo Routine 'run_init_pop'. Point-1 before call :change_db_attr tmpdir fbc dbconn "dbauth" create_with_fw create_with_sweep
        echo.    1 tmpdir=!tmpdir!
        echo.    2 fbc=!fbc!
        echo.    3 dbconn=!dbconn!
        echo.    4 dbauth="!dbauth!"
        echo.    5 create_with_fw=async
    )>>%log4tmp%


    @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem  T E M P L Y    S E T    F O R C E D   W R I T E S   =   O F F
    @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" async


    set init_pkq=50

    set srv_frq=10

    @rem -------------------------------------------------------------------------------------------------------------------------------------------------------
    call :gen_working_sql  init_pop  %tmp_init_pop_sql%    %init_pkq%   %no_auto_undo%      0   %unit_selection_method%       0           0      %sleep_udf% 
    @rem                                                                                                                   sleep_min
    @rem                                                                                                                              sleep_max
    @rem                                                                                                                                          sleep_udf
    @rem                      1              2                 3             4              5           6                     7           8          9
    @rem --------------------------------------------------------------------------------------------------------------------------------------------------------

    set t0=%time%
    (
        echo START initial data population.
        echo Service procedures will be called at the start of every %srv_frq%th packet.
        echo Executing SQL script: %tmp_init_pop_sql%
        @rem 15.10.2014, suggestion by AK: set cache buffer pretty large for initial pop data
        @rem Actual for CS or SC, will be ignored in SS:
        echo Cache buffer for ISQL connect when running initial data population: %init_buff%
    )>!tmpmsg!

    call :bulksho !tmpmsg! !log4tmp!


    set /a k = 1

    :iter_loop
    
        @rem #################################################################################
        @rem #############   I N I T I A L     D A T A     P O P U L A T I O N   #############
        @rem #################################################################################
    
        
        @rem periodically we have to run service SPs: srv_make_invnt_total, srv_make_money_saldo, srv_recalc_idx_stat

        set /a p = %k% %% %srv_frq%

        (
            echo packet #%k%
            echo ^=^=^=^=^=^=^=^=^=^=^=^=^=
        ) >>%tmplog%
    
        @rem ################### check for non-empty stoptest.txt ################################
        call :chk_stop_test pop_data !tmpdir! !fbc! !dbconn! "!dbauth!"
    
       
        set tsrvsql=!tmpdir!\sql\tmp_service_sp.sql
        set tsrvlog=!tmpdir!\sql\tmp_service_sp.log

        call :repl_with_bound_quotes %tsrvsql% tsrvsql
        call :repl_with_bound_quotes %tsrvlog% tsrvlog

        del %tsrvsql% 2>nul
        del %tsrvlog% 2>nul

        if %p% equ 0 (
            (
                echo set list on; set heading on;
                echo commit;
                echo set transaction no wait;
                echo select * from srv_make_invnt_saldo;
                echo commit;
                echo set transaction no wait;
                echo select * from srv_make_money_saldo;
                echo commit;
                echo set transaction no wait;
                echo select * from srv_recalc_idx_stat;
                echo commit;
            ) > %tsrvsql%

            echo |set /p=%time%: start run service SPs...

        ) else (
            echo quit; > %tsrvsql%
        )
    

        @rem --------------- perform service: srv_make*_total, recalc index statistics -------------
        set isql_exe=%fbc%\isql.exe
        call :repl_with_bound_quotes !isql_exe! isql_exe
        set run_srv_sp=!isql_exe! %dbconn% %dbauth% -c %init_buff% -n -i !tsrvsql!

        if %p% equ 0 (
            echo %time% Run: call service procedures !run_srv_sp! 1^>%tsrvlog% 2^>%tmperr% >>%log4tmp%
        )
        cmd /c !run_srv_sp! 1>>!tsrvlog! 2>!tmperr!


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

        for /d %%f in (!tsrvsql!,!tsrvlog!,!tmperr!) do (
            if exist %%f del %%f
            if exist goto err_del
        )

        @rem --------------------------------------

   
        set run_isql=!isql_exe! %dbconn% %dbauth% -c %init_buff% -n -i %tmp_init_pop_sql%

        if %k% equ 1 (
            echo.
            echo Command: !run_isql!
            echo.
        )

        
        @rem --------------------------- create %init_pkg% business operations -------------------------------
        echo|set /p=%time%, packet #!k! start... 

        @rem echo Command: !run_isql!
        @rem  -i C:\TEMP\logs.oltp25\tmp_init_data_pop.sql -c 32768 -n 1>>C:\TEMP\logs.oltp25\tmp_init_data_pop.log 2>&1

        echo Run: packet #!k!, !run_isql! 1^>^>%tmpclg% 2^>^&1 >>%log4tmp%

        cmd /c !run_isql! 1>>!tmpclg! 2>&1

        echo Count rows with exceptions that occured in this packet.>>%log4tmp%
        (
            for /f "delims=" %%a in ('find /c "SQLSTATE =" %tmpclg%') do echo Got: %%a
        ) 1>>%log4tmp% 2>&1

        type %tmpclg% >> %tmplog%

        @rem -- do NOT do it here -- call :catch_err run_isql !tmperr! %tmp_init_pop_sql% failed_run_pop_sql
    
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
    
        set run_isql=!isql_exe! %dbconn% %dbauth% -pag 0 -n -i %tmpchk%

        echo Obtain number of docs, %run_isql% 1^>%tmpclg% 2^>%tmperr% >>%log4tmp%

        cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!

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
        @rem call :sho "Packet #!k! finish: docs created ^>^>^> %new_docs% ^<^<^<, limit = %init_docs%" %log4tmp%
        set msg=packet #!k! finish: docs created ^>^>^> %new_docs% ^<^<^<, limit = %init_docs%
        call :sho "!msg!" %log4tmp%

        for /d %%f in (!tmpchk!,!tmpclg!) do (
            if exist %%f del %%f
        )

        @rem +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        @rem INCREMENT PACKET NUMBER AND CHECK WHETHER LOOP CAB BE CONTINIED OR NO
        @rem +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        set /a k=!k!+1


    if %new_docs% lss %init_docs% goto iter_loop

    @rem %%%%%%%%%%%%%%%%%   e n d    o f    l o o p   %%%%%%%%%%%%%%%%%%%%

    del %tmp_init_pop_sql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul

    (
        echo Routine 'run_init_pop'. Point-2 before call :change_db_attr tmpdir fbc dbconn "dbauth" current_fw
        echo.    1 tmpdir=!tmpdir!
        echo.    2 fbc=!fbc!
        echo.    3 dbconn=!dbconn!
        echo.    4 dbauth="!dbauth!"
        echo.    5 current_fw=!current_fw!
    )>>%log4tmp%



    @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    @rem  R E S T O R E   I N I T    S T A T E    O F     F O R C E D   W R I T E S
    @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

    @rem --- wrong! --- call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" %create_with_fw%
    call :change_db_attr !tmpdir! !fbc! !dbconn! "!dbauth!" !current_fw!

    
    @rem If we are here than no more init docs should be created
    if %init_docs% gtr 0 (
    
        del %tmpchk% 2>nul
        del %tmpclg% 2>nul
    
        (
            @echo set list off; set heading off;
            @echo select
            @echo     'act_docs='^|^|( select count(*^) from ( select id from doc_list rows (1+%init_docs%^) ^) ^)
            @echo from rdb$database;
        )>%tmpchk%
    
        set run_isql=%fbc%\isql
        call :repl_with_bound_quotes %run_isql% run_isql
    
        set run_isql=!run_isql! %dbconn% %dbauth% -pag 0 -n -i %tmpchk%

        call :sho "Obtain FINAL number of docs..." %log4tmp%

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

        call :sho "FINISH initial data population. Job has been done from %t0% to %time%. Count rows in doc_list: ^>^>^>!act_docs!^<^<^<." %log4tmp%
    
    )

    call :sho "Leaving routine: run_init_pop." %log4tmp%

    endlocal

goto:eof    
@rem end of run_init_pop


@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:change_db_attr
    setlocal
    echo.
    call :sho "Internal routine: change_db_attr." %log4tmp%
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

    (
        echo.   arg_1 tmpdir=!tmpdir!
        echo.   arg_2 fbc=!fbc!
        echo.   arg_3 dbconn=!dbconn!
        echo.   arg_4 tmpdir=dbauth=!dbauth!
        echo.   arg_5 new_fw=!new_fw!
        echo.   arg_6 new_sweep=!new_sweep! // optional
    ) >> %log4tmp%

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
        echo %time%. Run: %run_cmd% action_properties dbname %dbnm% prp_write_mode prp_wm_!new_fw! 2^>%tmperr% >>%log4tmp%

        %run_cmd% action_properties dbname %dbnm% prp_write_mode prp_wm_!new_fw! 1>%tmplog% 2>%tmperr%

        (
            for /f "delims=" %%a in ('type %tmplog%') do echo STDLOG: %%a
            for /f "delims=" %%a in ('type %tmperr%') do echo STDERR: %%a
        ) 1>>%log4tmp% 2>&1

        call :catch_err run_cmd !tmperr! n/a failed_fbsvc
        echo  Ok. && echo %time%. Done. >> %log4tmp%

        if not .!new_sweep!.==.-1. (
            @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
            @rem :::    A d j u s t i n g     S w e e p   I n t e r v a l    t o     c o n f i g    s e t t i n g   :::
            @rem ::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

            echo|set /p=Changing attribute Sweep Interval to required value from config...

            echo %time%. Run: %run_cmd% action_properties dbname %dbnm% prp_sweep_interval !new_sweep! 2^>%tmperr% >>%log4tmp%
            %run_cmd% action_properties dbname %dbnm% prp_sweep_interval !new_sweep! 2>%tmperr%

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
        if .1.==.2. (
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

    call :sho "Leaving routine: change_db_attr." %log4tmp%
    endlocal
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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
            @rem echo Parsed: param="%%i" _tmp_val_="%%j"
            set _tmp_par_=%%i
            call :trim _tmp_par_ !_tmp_par_!

            if "%%j"=="" (
              set err_setenv=1
              echo. && echo ### NO VALUE found for parameter "%%i" ### && echo.
            ) else (
              for /F "tokens=1" %%p in ("!_tmp_par_!") do (
                set _tmp_val_=%%j
                call :trim _tmp_val_ !_tmp_val_!
                set %%p=!_tmp_val_!
              )
            )
          )
      )
    )
    set _tmp_par_=
    set _tmp_val_=
    set "%~2=%err_setenv%"

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:trim_old
    setLocal
    @rem EnableDelayedExpansion
    set Params=%*
    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:trim
    setLocal

    @rem 22.10.2020: we have to enclose assignment of Params into double quotes.
    @rem Otherwise caret will be duplicated here, i.e.
    @rem when call this routine with string like: "set term ^;"
    @rem then output will be: "set term ^^;"
    set "Params=%*"

    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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
        set val=!val:^>=$GREATER$THEN$!
        set val=!val:^<=$LESS$THEN$!

        call :trim val !val!

        for /f "useback tokens=*" %%x in ('!val!') do (
                set val=%%~x
        )
        set val=!val:$GREATER$THEN$=^>!
        set val=!val:$LESS$THEN$=^<!
        echo !val!>>!tmp_output!
    )
    move !tmp_output! !input_file! 1>nul

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:chk_mon_usr_pwd_role

    echo.
    call :sho "Internal routine: chk_mon_usr_pwd_role." %log4tmp%
    echo.

    setlocal

    set some_undefined=1
    if "%mon_query_role%"=="" (
        set p1_defined=0
    ) else (
        set p1_defined=1
    )

    if "%mon_usr_prefix%"=="" (
        set p2_defined=0
    ) else (
        set p2_defined=1
    )

    if "%mon_usr_passwd%"=="" (
        set p3_defined=0
    ) else (
        set p3_defined=1
    )

    if .!p1_defined!!p2_defined!!p3_defined!.==.000. (
        set some_undefined=0
    )
    if .!p1_defined!!p2_defined!!p3_defined!.==.111. (
        set some_undefined=0
    )

    if .1.==.0. (
        echo Param: ^|mon_usr_prefix^|, value: ^|%mon_usr_prefix%^|
        echo Param: ^|mon_usr_passwd^|, value: ^|%mon_usr_passwd%^|
        echo Param: ^|mon_query_role^|, value: ^|%mon_query_role%^|
        echo !p1_defined!!p2_defined!!p3_defined!
        echo some_undefined=!some_undefined!
    )

    if !some_undefined! EQU 1 (
        call :sho "CONFIGURATION ISSUE. Parameters 'mon_usr_prefix', 'mon_usr_passwd' and 'mon_query_role' must be either all defined or all commented out." !log4tmp!
        if .%can_stop%.==.1. (
            echo.
            echo Press any key to FINISH this batch. . .
            pause>nul
            goto final
        )
    )

    call :sho "Leaving routine: chk_mon_usr_pwd_role." %log4tmp%
    
    endlocal

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:check_for_prev_build_err
    echo.
    call :sho "Internal routine: check_for_prev_build_err." %log4tmp%
    echo.
    setlocal

    @rem call :check_for_prev_build_err %tmpdir% %fb% build_was_cancelled %can_stop% %log4tmp%

    set tmpdir=%1
    set fb=%2

    set msg=Previous launch of script that builds database
    set txt=###################################################################
    @rem build_was_cancelled = parameter #3, to be changed HERE:
    set build_was_cancelled=0

    set can_stop=%4
    set log4prep=%5

    set tmplog=%tmpdir%\%~n0_%fb%.tmp
    set tmperr=%tmpdir%\%~n0_%fb%.err
    call :repl_with_bound_quotes %tmperr% tmperr


    for /f "usebackq tokens=*" %%a in ('%tmperr%') do set size=%%~za
    if .!size!.==.. set size=0
    if !size! gtr 0 (
        findstr /i /c:"SQLSTATE = HY008" /c:"^C" %tmperr% 1>nul
        if not errorlevel 1 (
            (
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
            ) > %tmplog%
            type %tmplog%
            type %tmplog% >>%log4prep%
            del %tmplog%
        ) else (
            (
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
                @rem echo Remove this file before restarting test.
                @rem echo.
            ) > %tmplog%
            type %tmplog%
            type %tmplog% >>%log4prep%
            del %tmplog%

            @rem if .%can_stop%.==.1. (
            @rem     echo Press any key to FINISH this batch. . .
            @rem     pause>nul
            @rem     goto final
            @rem ) else (
            @rem     (
            @rem         echo Batch %~f0 currently is working in non-interactive mode,
            @rem         echo file %tmperr% is preserved for possible further analysis.
            @rem     ) > %tmplog%
            @rem     type %tmplog%
            @rem     type %tmplog% >>%log4prep%
            @rem     del %tmplog%
            @rem )

        )
    ) else (
        echo RESULT: no errors found that could rest from previous building database objects.
        echo File %tmperr% not found or is empty.
    )

    call :sho "Leaving routine: check_for_prev_build_err." %log4tmp%
    
    endlocal & set "%~3=%build_was_cancelled%"
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:show_time_limits

    setlocal

    echo.
    call :sho "Internal routine: show_time_limits." %log4tmp%
    echo.

    @rem call :show_time_limits !tmpdir! !fbc! !dbconn! "!dbauth!" log4all

    setlocal

    set tmpdir=%1
    set fbc=%2
    set dbconn=%3
    set dbauth=%4
    @rem Remove enclosing double quotes from value ofr dbauth: "-user ... -pas ..."   ==>  -user ... -pas ...
    set dbauth=!dbauth:"=!
    @rem "
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
        echo set term ^^;
        echo -- NB: we have to enclose potentially update-conflicting statements in begin..end blocks with EMPTY when-any section
        echo -- because of possible launch test from several hosts.
        echo execute block as
        echo begin
        echo     begin
  		echo         -- this view is one-to-one projection to the table perf_agg which is used in report "Performance for every MINUTE":
		echo         delete from v_perf_agg;
        echo     when any do 
        echo         begin 
        echo           -- nop ---
        echo         end
        echo     end

        echo     begin
        echo         delete from trace_stat; -- this table will be used in report "Performance from TRACE", 23.12.2015
        echo     when any do 
        echo         begin 
        echo           -- nop ---
        echo         end
        echo     end
        
        echo     begin
        echo         delete from %log_tab% g
        echo         where g.unit in ( 'perf_watch_interval',
        echo                           'sp_halt_on_error',
        echo                           'dump_dirty_data_semaphore',
        echo                           'dump_dirty_data_progress'
        echo                        ^);
        echo     when any do 
        echo         begin 
        echo           -- nop ---
        echo         end
        echo     end
        echo end
        echo ^^
        echo set term ;^^
        echo commit;
        echo.
        echo insert into perf_log( unit,                  info,     exc_info,
        echo                       dts_beg, dts_end, elapsed_ms^)
        echo               values( 'perf_watch_interval', 'active', 'by %~f0',
        echo                       dateadd( %warm_time% minute to current_timestamp^),
        echo                       dateadd( %warm_time% + %test_time% minute to current_timestamp^),
        echo                       -1 -- skip this record from being displayed in srv_mon_perf_detailed
        echo                    ^);
        echo insert into perf_log( unit,                        info,  stack,
        echo                       dts_beg, dts_end, elapsed_ms^)
        echo               values( 'dump_dirty_data_semaphore', '',    'by %~f0',
        echo                       null, null, -1^);
        echo alter sequence g_success_counter restart with 0;
        echo commit;
    
        echo set list on;
        echo select
        echo        g.dts_measure_beg
        echo       ,g.dts_measure_end
        echo       ,g.add_info
        echo from
        echo (
        echo   select 
        echo      p.unit,
        echo      p.exc_info as add_info, -- name of this .bat that did insert this record
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
    
    set run_isql=!run_isql! %dbconn% %dbauth% -n -i %tmpsql% -nod

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
    
    set msg=Report for preparing phase of this test see in file: %log4all%
    echo !msg!
    echo !msg!>>%log4tmp%
   
    del %tmpsql% 2>nul
    del %tmplog% 2>nul
    del %tmperr% 2>nul

    call :sho "Leaving routine: show_time_limits." %log4tmp%

    endlocal

goto:eof
@rem end of :show_time_limits

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:adjust_sep_wrk_count

    echo.
    call :sho "Internal routine: adjust_sep_wrk_count." %log4tmp%
    echo.
    @rem  Use file: $shdir/oltp_adjust_DDL.sql
    @rem  1. GENERATE temporary script "$tmpadj" which will contain dynamically generated DDL statements
    @rem     for PERF_SPLIT_nn tables
    @rem  2. APPLY temporary script "$tmpadj" which contains dynamic DDL.
 
    @rem PUBL: fbc, dbconn, dbauth, tmpdir

    setlocal
    set log4tmp=%1

    set tmpsql=%tmpdir%\sql\tmp_adjust_sep_workers_cnt.sql
    for /f %%a in ("!tmpsql!") do (
        set tmpclg=%%~dpna.log
        set tmperr=%%~dpna.err
    )

    call :sho "Adjust some DDL with current 'separate_workers' value" !log4tmp!
    call :sho "    Step-1: generate temporary SQL." !log4tmp!

    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe
    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c 512 -i %~dp0oltp_adjust_DDL.sql

    cmd /c !run_isql! 1>!tmpsql! 2>!tmperr!

    call :catch_err run_isql !tmperr! n/a

    for /f "usebackq tokens=*" %%a in ('!tmpsql!') do set size=%%~za
    call :sho "Size of generated file !tmpsql!: !size!" !log4tmp!

    call :sho "    Step-2: apply temporary SQL." !log4tmp!

    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c 512 -i !tmpsql!

    cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!
    call :catch_err run_isql !tmperr! n/a

    type !tmpclg! >> !log4tmp!

    for /d %%f in (!tmpsql!,!tmpclg!) do (
        del %%f
    )
    call :sho "Leaving routine: adjust_sep_wrk_count." %log4tmp%

   
    endlocal

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:adjust_replication

    echo.
    call :sho "Internal routine: adjust_replication." %log4tmp%
    echo.
    @rem  Use file: $shdir/oltp_replication_DDL
    @rem # 1. GENERATE temporary script "tmp_adjust_for_replication.sql" which will contain dynamically generated DDL
    @rem     statements for creating/dropping indices, according to current value of 'used_in_replication' parameter
    @rem  ::: NB ::: 01.11.2018
    @rem  RECONNECT is needed on 3.0.4 SuperServer between alter table add <field> not null and alter table add <PK_CONSTRAINT>.
    @rem  Script oltp_replication_DDL.sql has query to table SETTINGS with WHERE-expr: mcode='CONNECT_STR' for obtaining
    @rem  proper connection string to currently used database (see letters to dimitr et al, 01.11.2018, box pz@ibase.ru).
    @rem  2. APPLY temporary script "tmp_adjust_for_replication.sql" which contains dynamic DDL.
 
    @rem PUBL: fbc, dbconn, dbauth, tmpdir

    setlocal
    set log4tmp=%1

    set tmpsql=%tmpdir%\sql\tmp_adjust_for_replication.sql
    for /f %%a in ("!tmpsql!") do (
        set tmpclg=%%~dpna.log
        set tmperr=%%~dpna.err
    )

    call :sho "Adjust some DDL with current 'used_in_replication' value" !log4tmp!
    call :sho "    Step-1: generate temporary SQL." !log4tmp!

    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe
    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c 512 -i %~dp0oltp_replication_DDL.sql

    cmd /c !run_isql! 1>!tmpsql! 2>!tmperr!
    call :catch_err run_isql !tmperr! n/a

    call :sho "    Step-2: apply temporary SQL." !log4tmp!

    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c 512 -i !tmpsql!
    cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!

    call :catch_err run_isql !tmperr! n/a

    for /d %%f in (!tmpsql!,!tmpclg!) do (
        del %%f
    )

    call :sho "Leaving routine: adjust_replication." %log4tmp%
    endlocal


goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:adjust_grants

    setlocal
    set mon_unit_perf=%1
    set logname=%2

    echo.
    call :sho "Internal routine: adjust_grants." !logname!
    echo.
    @rem  Use file: $shdir/adjust_grants
    @rem  1. GENERATE temporary script "tmp_adjust_grants.sql" which will contain generated statements for
    @rem     creating role '!mon_query_role!' and temp. users !mon_usr_prefix!_0001 !mon_usr_prefix}_0002!, ...
    @rem     for querying MON$ tables (this strongly reduces negative affect generated by actions with MON$ tables).
    @rem  2. APPLY temporary script "tmp_adjust_grants.sql".
 
    @rem PUBL: fbc, dbconn, dbauth, tmpdir

    if not .%fb%.==.25. (

        @rem FB = 3.x+: we create non-privileged users in all cases except:
        @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        @rem mon_unit_perf = 0 AND mon_query_role is undefined AND mon_usr_prefix is undefined
        @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        @rem Working as NON_dba is much closer to the real-world applications when doing common business tasks as SYSDBA.
        @rem ### CAUTION ###
        @rem This logic must be duplicated in oltp_isql_run_worker batch
        set conn_as_locksmith=0
        if .!mon_unit_perf!.==.0. (
            if .!mon_query_role!.==.. (
                if .!mon_usr_prefix!.==.. (
                    set conn_as_locksmith=1
                )
            )
        )

        set isql_exe=%fbc%\isql.exe

        @rem do NOT pass %isql_exe% here, use only !isql_exe!
        @rem Otherwise get 'syntax of command is incorrect' inside routine repl_with_bound_quotes
        @rem ----------------------------------------------
        call :repl_with_bound_quotes !isql_exe! isql_exe

        set tmpsql=%tmpdir%\sql\tmp_adjust_grants.sql
        for /f %%a in ("!tmpsql!") do (
            set tmpclg=%%~dpna.log
            set tmperr=%%~dpna.err
        )


        call :sho "Drop temporary non-privileged USERS and ROLE which could be created for reducing affect of mon$ data gathering." !logname!
        (
            echo rollback;
            echo set transaction no wait;
            echo execute procedure srv_drop_oltp_worker;
            echo commit;
        ) >!tmpsql!

        set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -i !tmpsql!
        cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!
        call :catch_err run_isql !tmperr! n/a

        @rem -.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-

        if .!conn_as_locksmith!.==.1. (

		    call :sho "NOTE. All sessions will run as '%usr%'" !logname!

		) else (
            if not .%mon_query_role%.==.. (
                if not .%mon_usr_prefix%.==.. (
        
                    call :sho "Create temporary ROLE and non-privileged USERS for reducing affect of mon$ data gathering." !logname!

                    @rem #########################################################
                    @rem ###   O L T P _ A D J U S T  _  G R A N T S . S Q L   ###
                    @rem #########################################################
                    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -i %~dp0oltp_adjust_grants.sql

                    call :sho "    Step-1: generate temporary SQL." !logname!
                    cmd /c !run_isql! 1>!tmpsql! 2>!tmperr!
                    
                    call :catch_err run_isql !tmperr! n/a

                    call :sho "    Step-2: apply temporary SQL." !logname!
                    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c 512 -i !tmpsql!

                    cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!
                    call :catch_err run_isql !tmperr! n/a

                    @rem Result: temp users with names like: 'TMP$OLTP$USER_nnnn' have been created.

                )
            )
        )

        @rem -.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-.-

        for /d %%f in (!tmpsql!,!tmpclg!) do (
            del %%f
        )

    ) else (
        call :sho "SKIP: no sense to create temporary role and users in FB 2.5 because feature was not implemented." !logname!
    )

    call :sho "Leaving routine: adjust_grants." !logname!

    endlocal

goto:eof


@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:declare_sleep_UDF

    @rem PUBL: %log4tmp%
    @rem call :declare_sleep_UDF %sleep_ddl% sleep_udf sleep_mul
    @rem NB: sleep_udf sleep_mul are passed by ref, will be assigned HERE.

    echo.
    call :sho "Internal routine: declare_sleep_UDF." %log4tmp%
    echo.

    setlocal
    set sleep_ddl=%1

    set sleep_udf=UNDEFINED

    set tmpsql=%tmpdir%\sql\tmp_decl_udf.sql
    for /f %%a in ("!tmpsql!") do (
        set tmpclg=%%~dpna.log
        set tmperr=%%~dpna.err
    )

    call :sho  "Attempt to apply SQL script '%sleep_ddl%' that defines UDF for pauses in execution." !log4tmp!

    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe
    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c 512 -i %sleep_ddl%
    cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!

    call :catch_err run_isql !tmperr! n/a  failed_udf_decl
    @rem                1       2      3         4

    for /f "tokens=2-2" %%a in ('findstr /i /c:"EXT_FUNCTION_NAME" !tmpclg!') do (
        set sleep_udf=%%a
    )
    for /f "tokens=2-2" %%a in ('findstr /i /c:"multiplier_for_sleep_arg" !tmpclg!') do (
        set sleep_mul=%%a
    )

    for /d %%f in (!tmpsql!,!tmpclg!,!tmperr!) do (
        if exist %%f del %%f
    )

    call :sho "Success. UDF name for delays: !sleep_udf!. Multiplier to get delay in SECONDS: !sleep_mul!" !log4tmp!

    echo.
    call :sho "Leaving routine: declare_sleep_UDF." %log4tmp%
    echo.

    endlocal & set "%~2=%sleep_udf%" & set "%~3=%sleep_mul%"

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:sync_settings_with_conf
    @rem %fb% %log4tmp%
    @rem PUBL: fbc, dbconn, dbauth, tmpdir

    echo.
    call :sho "Internal routine: sync_settings_with_conf." %log4tmp%
    echo.

    setlocal

    set fb=%1
    set log4tmp=%2

    set tmpsql=%tmpdir%\sql\tmp_sync_settings_with_conf.sql
    for /f %%a in ("!tmpsql!") do (
        set tmpclg=%%~dpna.log
        set tmperr=%%~dpna.err
    )
    if exist !tmpsql! del !tmpsql!

    call :sho "Adjust SETTINGS table with config, step-1: generate temporary SQL script." !log4tmp!
    call :sync_settings_generate_sql %fb% !tmpsql!

    (
        echo.
        echo -- 02.01.2019: delete all records in mon_cache_memory table 
        echo --that could remain there after interrupted previous run:
        echo set list on;
        echo select 'ZAP table mon_cache_memory, start at ' ^|^| cast('now' as timestamp^) as msg from rdb$database;
        echo commit;
        echo set transaction NO wait;
        echo set count on;
        echo delete from mon_cache_memory;
        echo set count off;
        echo commit;
        echo select 'ZAP table mon_cache_memory, finish at ' ^|^| cast('now' as timestamp^) as msg from rdb$database;
        echo set list off;
    ) >>!tmpsql!

    set isql_exe=%fbc%\isql.exe
    call :repl_with_bound_quotes %isql_exe% isql_exe
    set run_isql=!isql_exe! %dbconn% %dbauth% -q -nod -c 512 -i !tmpsql!

    call :display_intention "Adjusting SETTINGS table with config, step-2: apply temporary script." "!run_isql!" !tmpclg! !tmperr!

    cmd /c !run_isql! 1>!tmpclg! 2>!tmperr!
    
    call :catch_err run_isql !tmperr! n/a failed_bld_sql
    call :sho "Success. Table SETTINGS has been synchronized with current test CONFIG values." !log4tmp!

    for /d %%f in (!tmpsql!,!tmpclg!) do (
        del %%f
    )
    echo.
    call :sho "Leaving routine: sync_settings_with_conf." %log4tmp%
    echo.
    endlocal

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:sync_settings_generate_sql
    echo.
    call :sho "Internal routine: sync_settings_generate_sql." %log4tmp%
    echo.

    setlocal
    set fb=%1
    @rem SQL script where we have to *ADD* text, i.e. do NOT truncate it to zero-length!
    set tmpsql=%2

    @rem  1 +working_mode
    @rem  2 +build_with_split_heavy_tabs
    @rem  3 +build_with_qd_compound_ordr
    @rem  4 +build_with_separ_qdistr_idx
    @rem  5 +enable_reserves_when_add_invoice
    @rem  6 +order_for_our_firm_percent
    @rem  7 +enable_mon_query
    @rem  8 +unit_selection_method
    @rem  9 +used_in_replication
    @rem 10 +separate_workers
    @rem 11 +workers_count
    @rem 12 +update_conflict_percent
    @rem 13 use_es, host, port, usr, pwd // 20.11.2020
    @rem 14 conn_pool_support // 12.12.2020
    @rem 15 resetting_support // 12.12.2020

  
    (
        echo set list on;
        echo select 'Adjust settings: start at ' ^|^| cast('now' as timestamp^) as msg from rdb$database;
        echo commit;
        echo set transaction no wait;
        echo set term ^^;
        echo execute block as
        echo begin

            call :inject_actual_setting %fb% init working_mode upper('%working_mode%'^)
            call :inject_actual_setting %fb% common enable_mon_query '%mon_unit_perf%'
            call :inject_actual_setting %fb% common unit_selection_method '%unit_selection_method%'

            echo %working_mode% | findstr /i /c:"debug_01" /c:"debug_02" >nul
            if NOT errorlevel 1 (
                @rem For DEBUG modes we turn off complex logic related to adding invoices:
                call :inject_actual_setting %fb% common ENABLE_RESERVES_WHEN_ADD_INVOICE '0'
                call :inject_actual_setting %fb% common ORDER_FOR_OUR_FIRM_PERCENT '0'
            ) else (
                echo     -- Values for 'ENABLE_RESERVES_WHEN_ADD_INVOICE', 'ORDER_FOR_OUR_FIRM_PERCENT'
                echo     -- remain the same: current working_mode='%working_mode%' does NOT belong to DEBUG list.
            )

            @rem BUILD_WITH_SPLIT_HEAVY_TABS: value can be 1 or 0:
            call :inject_actual_setting %fb% common build_with_split_heavy_tabs '%create_with_split_heavy_tabs%'

            @rem BUILD_WITH_QD_COMPOUND_ORDR: value can be 'most_selective_first' or 'least_selective_first':
            call :inject_actual_setting %fb% common build_with_qd_compound_ordr lower('%create_with_compound_columns_order%'^)

            @rem BUILD_WITH_SEPAR_QDISTR_IDX: value can be 1 or 0:
            call :inject_actual_setting %fb% common build_with_separ_qdistr_idx '%create_with_separate_qdistr_idx%'

            call :inject_actual_setting %fb% common used_in_replication '%used_in_replication%'

            call :inject_actual_setting %fb% common separate_workers '%separate_workers%'
            call :inject_actual_setting %fb% common workers_count '%winq%'

            call :inject_actual_setting %fb% common update_conflict_percent '%update_conflict_percent%'

            @rem  Script oltp_replication_DDL.sql has query to table SETTINGS with WHERE-expr: mcode='CONNECT_STR' for obtaining
            @rem  proper connection string to currently used database (see letters to dimitr et al, 01.11.2018, box pz@ibase.ru).
            @rem :inject_actual_setting %fb% common connect_str "'connect ''%host%/%port%:%dbnm%'' user ''%usr%'' password ''%pwd%'';'"  1
            call :inject_actual_setting %fb%  init  connect_str "'connect ''%host%/%port%:%dbnm%'' user ''%usr%'' password ''%pwd%'';'"  1
            @rem                        ---- ------ ----------  ----------------------------------------------------------------------- ---
            @rem                         ^      ^       ^                                           ^                                    ^
            @rem                         1      2       3                                           4                                    5 

            @rem Added 23.11.2018
            @rem ################
            @rem ::: NOTE ::: 23.11.2018 2258 List variables should NOT contain comma or semicolon as delimiter otherwise number of input arguments will be
            @rem wrongly interpreted inside subroutine 'inject_actual_setting' and syntax error will be raised because of incorrectly generated SQL script.
            @rem It was decided to use forward slash instead of previous deliumiter comma, e.g.: halt_test_on_errors=/CK/FK/ etc
            call :inject_actual_setting %fb% common mon_unit_list '%mon_unit_list%'
            call :inject_actual_setting %fb% common halt_test_on_errors '%halt_test_on_errors%'
            call :inject_actual_setting %fb% common qmism_verify_bitset '%qmism_verify_bitset%'
            if .!recalc_idx_min_interval!.==.0. (
                @rem 14.04.2019
                set recalc_idx_min_interval=99999999
            )
            call :inject_actual_setting %fb% common recalc_idx_min_interval '!recalc_idx_min_interval!'

            @rem Added 21.02.2019:
            call :inject_actual_setting %fb% common warm_time '%warm_time%' 1

            @rem Added 21.03.2019
            call :inject_actual_setting %fb% common test_intervals '%test_intervals%' 1

            @rem Added 17.05.2020. Role name and prefix for users who will execute SQL and query mon$ tables.

            @rem Actual only for FB 3.x+. If values are commented in .conf
            @rem then empty strings will be written in SETTINGS table:
            @rem -----------------------------------------------------
            call :inject_actual_setting %fb% init tmp_worker_role_name upper('%mon_query_role%'^) 1
            call :inject_actual_setting %fb% init tmp_worker_user_prefix upper('%mon_usr_prefix%'^) 1

            @rem ##################################################
            @rem Added 20.11.2020. Config parameter 'use_es'
            @rem ::: NOTE ::: settings.working_mode for this parameter must be 'COMMON', not 'INIT'
            if .!use_es!.==.. (
                call :inject_actual_setting %fb% common use_es '0' 1
            ) else (
                call :inject_actual_setting %fb% common use_es '%use_es%' 1
            )
            @rem Following parameters must be saved because they will be substituted into EDS statements when use_es=2:
            call :inject_actual_setting %fb% init host '%host%' 1
            call :inject_actual_setting %fb% init port '%port%' 1
            call :inject_actual_setting %fb% init usr '%usr%' 1
            call :inject_actual_setting %fb% init pwd '%pwd%' 1

            @rem 22.11.2020: add password for temporary created users. DO NOT apply UPPER here! :-)
            call :inject_actual_setting %fb% init tmp_worker_user_pswd '%mon_usr_passwd%' 1
            @rem ##################################################

            @rem Added 12.12.2020: save to DB info about suport External Connections Pool and 'RESETTING' system variable.
            @rem This will be used further for generating proper code of DB-level triggers:
            call :inject_actual_setting %fb% init conn_pool_support '!conn_pool_support!' 1
            call :inject_actual_setting %fb% init resetting_support '!resetting_support!' 1


        echo end
        echo ^^
        echo set term ;^^
        echo commit;
        echo select 'Adjust settings: finish at ' ^|^| cast('now' as timestamp^) as msg from rdb$database;
        echo set list off;
    ) >> !tmpsql!

    call :sho "Leaving routine: sync_settings_generate_sql." %log4tmp%
    endlocal
goto:eof
@rem end of sync_settings_with_conf

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:inject_actual_setting 
    setlocal

    @rem 14.09.2018
    @rem c/f sync_settings_generate_sql

    set fb=%1
    set a_working_mode=%2
    set a_mcode=%3
    set new_value=%4

    if .%5.==.. (
        set /a allow_insert_if_eof=0
    ) else (
        set allow_insert_if_eof=1
    )

    set left_char=!new_value:~0,1!
    set righ_char=!new_value:~-1!

    @rem REMOVE LEADING AND TRAILING DOUBLE QUOTES:
    @rem ##########################################
    set result=!left_char:"=!
    if .!result!.==.. (
       set result=!righ_char:"=!
       if .!result!.==.. (
          set new_value=!new_value:~1,-1!
       )
    )

    @rem call inject_actual_setting %fb% common enable_mon_query '%mon_unit_perf%'
    @rem                             1     2          3                4
    echo     begin

    @rem DDL of table settings:
    @rem WORKING_MODE                    VARCHAR(20) CHARACTER SET UTF8 Nullable
    @rem MCODE                           (DM_NAME) VARCHAR(80) CHARACTER SET UTF8 Nullable COLLATE NAME_COLL
    @rem CONTEXT                         VARCHAR(16) Nullable default 'USER_SESSION'
    @rem SVALUE                          (DM_SETTING_VALUE) VARCHAR(160) CHARACTER SET UTF8 Nullable COLLATE NAME_COLL
    @rem INIT_ON                         VARCHAR(20) Nullable default 'connect'
    @rem DESCRIPTION                     (DM_INFO) VARCHAR(255) Nullable
    @rem CONSTRAINT SETTINGS_UNQ:
    @rem   Unique key (WORKING_MODE, MCODE) uses explicit ascending index SETTINGS_MODE_CODE
    
    if !allow_insert_if_eof! EQU 0 (
        echo         update settings set svalue = !new_value!
        echo         where working_mode = upper('!a_working_mode!'^) and mcode = upper( '!a_mcode!'^);
        echo         if (row_count = 0^) then 
        echo             exception ex_record_not_found
        if NOT .!fb!.==.25. (
            echo             using ( 'settings', 'working_mode=upper(''!a_working_mode!''^) and mcode=upper(''!a_mcode!''^)' ^)
        )
        echo             ;
    ) else (
        echo         -- Passed argument 'allow_insert_if_eof' = !allow_insert_if_eof!:
		echo         update or insert into settings(working_mode, mcode, svalue^)
		echo         values( upper( '!a_working_mode!' ^), upper( '!a_mcode!' ^),  !new_value! ^)
		echo         matching (working_mode, mcode^);
    )
    echo     when any do 
    echo         begin
    echo            if ( gdscode NOT in (335544345, 335544878, 335544336,335544451 ^) ^) then exception;
    echo         end
    echo     end

    endlocal
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:gen_vbs_extractor
    setlocal
    set tmpvbs=%1

    @rem Generate temporary .vbs script in for extracting files from .zip
    @rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
    @rem set tmpvbs=!tmpdir!\%~n0.extract-from-zip.tmp.vbs

    (
        echo ' Original text:
        echo ' https://social.technet.microsoft.com/Forums/en-US/8df8cbfc-fe5d-4285-8a7a-c1fb201656c8/automatic-unzip-files-using-a-script?forum=ITCG
        echo ' Example:
        echo '     %systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! ..\util\curl\curl.exe.zip !tmpdir!

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

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:remove_CR_from_file
@rem https://www.computing.net/answers/windows-xp/removing-carriage-returns-from-a-textfile/197677.html
setLocal

set in_place=0

set sourfile=%1
if .%2.==.. (
   set in_place=1
   set targfile=!sourfile!.!random!.tmp
) else (
    set targfile=%2
)

@rem 05.03.2020: remove excessive CR symbols using VBS:
@rem ==================================================
for /f %%a in ("!sourfile!") do (
    set remove_extra_cr_vbs=%%~dparemove_excessive_CR.vbs.tmp
    if NOT exist !remove_extra_cr_vbs! (
        (
            echo ' Generated auto by %~f0 at !date! !time!
            echo ' Open STDIN, read it content line-by-line and for every line:
            echo ' #   remove all duplicates of carrige return character;
            echo ' #   add line feed character to the end if needed;
            echo ' #   write changed line to STDOUT.
            echo ' Usefult for processing result of miscelaneous utilities: handle, psexec et al.
            echo ' Usage: %systemroot%\system32\cscript.exe //nologo //e:vbscript !remove_extra_cr_vbs! ^< C:\temp\input_file.txt ^> C:\temp\output_file.txt
            echo ' https://stackoverflow.com/questions/41232510/remove-all-carriage-return-and-line-feed-from-file
            echo set inp = wscript.stdin
            echo set outp = wscript.stdout
            echo do until inp.atendofstream
            echo     text = inp.readline
            echo     do while instr( text, vbcr ^& vbcr ^) ^> 0
            echo         text = replace( text, vbcr ^& vbcr, vbcr ^)
            echo     loop
            echo     if instr( text, vblf ^) = 0 then
            echo         if instr( text, vbcr ^) ^> 0 then
            echo             text = replace( text, vbcr, vbcr ^& vblf ^)
            echo         else
            echo             text = text ^& vbcr ^& vblf
            echo         end if
            echo     end if
            echo     text = replace( text, vblf ^& vblf, vblf ^)
            echo     outp.write text
            echo loop
        ) >!remove_extra_cr_vbs!
    )
)

%systemroot%\system32\cscript.exe //nologo //e:vbscript !remove_extra_cr_vbs! < !sourfile! > !targfile!

if !in_place! EQU 1 (
    move !targfile! !sourfile! 1>nul
    set elev=!errorlevel!
    if !elev! NEQ 0 (
        set msg=### ERROR ### in 'remove_CR_from_file' routine when move !targfile! !sourfile!: errorlevel = !elev!
        echo !msg!
        if not "!log!"=="" (
            echo !msg! >>!log!
        )
        exit
    )
)
endlocal 
goto:eof
@rem ^
@rem end of ':remove_CR_from_file'

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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
        goto final
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

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:display_intention
    setlocal
    @rem Sample: call :display_intention "Build database: initial phase." "!run_isql!" "!log!" "!err!"
    set msg=%1
    set run_cmd=%2
    set std_log=%3
    set std_err=%4

    @rem ...........................................
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
    @rem ...........................................
    set left_char=!run_cmd:~0,1!
    set righ_char=!run_cmd:~-1!

    @rem REMOVE LEADING AND TRAILING DOUBLE QUOTES:
    @rem ##########################################
    set result=!left_char:"=!
    if .!result!.==.. (
       set result=!righ_char:"=!
       if .!result!.==.. (
          set run_cmd=!run_cmd:~1,-1!
       )
    )

    echo.
    echo !msg!
    echo.    RUNCMD: !run_cmd!
    echo.    STDOUT: !std_log!
    echo.    STDERR: !std_err!

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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
        echo See details in file %log4tmp%

        if .!do_abend!.==.1. (
            if .%can_stop%.==.1. (
                echo.
                echo Press any key to FINISH this batch. . .
                pause>nul
            )
            goto final
        )
    ) else (
        @rem drop EMPTY error file:
        del %err_file% 2>nul
    )
    endlocal
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:gen_batch_for_stop

    echo.
    call :sho "Internal routine: gen_batch_for_stop." %log4tmp%
    echo.
    @rem call gen_batch_for_stop 1stoptest.tmp info
    setlocal

    set b4stopbase=%1
    set mode=%2

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
        echo     echo execute block returns("Cancelling test, start at:" timestamp, "OLD 'g_stop_test' value:" bigint^^^) as
        echo     echo     declare c bigint;
        echo     echo begin
        echo     echo     "Cancelling test, start at:" = current_timestamp;
        echo     echo     "OLD 'g_stop_test' value:" = gen_id(g_stop_test, 0^^^);
        echo     echo     suspend;
        echo     echo     c = gen_id( g_stop_test, -abs(gen_id(g_stop_test,0^^^)^^^)-999999999 ^^^);
        echo     echo end
        echo     echo #
        echo     echo --  DISABLED 17.09.2020: alter sequence g_stop_test restart with -999999999
        echo     echo -- #
        echo     echo commit
        echo     echo #
        echo     echo execute block returns("Cancelling test, finish at:" timestamp, "NEW 'g_stop_test' value:" bigint^^^) as
        echo     echo begin
        echo     echo     "Cancelling test, finish at:" = current_timestamp;
        echo     echo     "NEW 'g_stop_test' value:" = gen_id(g_stop_test, 0^^^);
        echo     echo     suspend;
        echo     echo end
        echo     echo #
        echo ^) ^> !b4stop_sql!
        echo.
        echo echo ^^!time^^!. Script that is to be executed now: !b4stop_sql!
        echo.
        echo echo Trying to kill all running cscript.exe
        echo.
        echo taskkill /f /im cscript.exe
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

    if /i .!mode!.==.info. (
        echo.
        echo In order to premature stop all working ISQL sessions run following batch:
        echo.
        echo !b4stop_bat!
        echo.
    )

    call :sho "Leaving routine: gen_batch_for_stop." %log4tmp%
    endlocal
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:getfblst

    echo.
    call :sho "Internal routine: getfblst." %log4tmp%
    echo.

    @rem call :getfblst %fb% fbc
    @rem                 ^    ^-------- this will be defined here: path to FB binaries on local machine.
    @rem                 +------------- first arg. to batch, relates to FB version: 25 or 30

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
        set preflst=WI-V2.5.,WI-T2.5,WI-V3.,WI-T3.,WI-V4.,WI-T4.,WI-V,WI-T
    ) else (
        set preflst=WI-V4.,WI-T4.,WI-V3.,WI-T3.,WI-V2.5.,WI-T2.5,WI-V,WI-T
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

    call :sho "Leaving routine: getfblst." %log4tmp%

    endlocal & set "%~2=%result%"

goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

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

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:nosysinfo
    echo Could not get system information.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:db_cant_write
    echo FAILED check that database is on read-write mode and/or one may to write data into GTT.
    echo.
    echo Check database attributes. Also ensure that FB service has sufficient rights on the
    echo directory that is specified by FIREBIRD_TMP environment variable on server side.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:mis_rdb_conf
    echo FAILED attempt to get FB config via SQL. Perhaps something wrong with FB version parsing.
    echo You have to check that this FB instance actually has table RDB$CONFIG with all existing
    echo config parameters and their values.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:db_not_ready
    echo FAILED check that database is avaliable and has all needed objects.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:cant_create_or_connect
    echo FAILED attempt to create new database or test connection to existing one.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_fbsvc
    echo FAILED result of fbsvcmgr launch.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_gfix
    echo FAILED result of gfix launch.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_bld_sql
    echo FAILED building database objects.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_ext_table
    echo FAILED to detect content of EXTERNAL table that is used to test self-stop.
    echo.
    echo Probably you have to open firebird.conf and set 'ExternalFileAccess'
    echo to some folder where 'firebird' account has enough rights.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_show_params
    echo FAILED fo run script with commands for show database and test parameters.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_count_old_docs
    echo FAILED to run script which tries to obtain number of already existing
    echo documents and to determine need in initial data population.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_reset_pop_gen
    echo FAILED to run script which resets generator for initial data population.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_init_pop_srv_sp
    echo FAILED to run auxiliary stored procedures during initial data population.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_count_pop_docs
    echo FAILED to run script which tries to get number of current docs in database.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_show_time
    echo FAILED to run script which tries to add 'signal' record into log that will be
    echo used to evaluate planning finish time.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:failed_udf_decl
    echo ###  Config parameter 'sleep_ddl' points to file '!sleep_ddl!' which
    echo ###  must be SQL script with declaration of UDF that can implement delay.
    echo ###  Appropriate binary (.ddl)^ must be stored in any directory that could be
    echo ###  accessed by 'firebird' account according to value of firebird.conf parameter 
    echo ###  UDFaccess. Usually it is enough to put .dll into %%FIREBIRD_HOME%%\UDF folder.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:fbk_storage_failed_restore
    echo FAILED to restore from backup file defined by config parameter 'results_storage_fbk'.
    echo You have to ensure that file '%results_storage_fbk%' was created
    echo for database with ODS older or equal than required by current version of Firebird.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:fdb_storage_failed_create
    echo FAILED to create temporary database for storing result of test runs.
    echo You have to check free space on disk where folder '%tmpdir%' was created.
    echo Also ensure that Firebird service account has all necessary access rights
    echo to this folder.
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:nocompressor
    setlocal
    set tmplog=%1
    (
        echo.
        echo Config parameter 'report_compress_cmd': !report_compress_cmd!
        echo -- points to invalid or missed binary.
        echo.
    ) > !abendlog!
    type !abendlog! 

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:noprodname
    setlocal
    set tmplog=%1
    set param_name=%2
    set expected_nm=%3
    @rem !%1:"=!
    (
        echo.
        echo Config parameter '!param_name!': !%2!
        echo -- points to executable that actually is NOT !expected_nm!
        echo.
    ) > !abendlog!
    type !abendlog! 

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:nocertutil
    setlocal
    set tmplog=%1
    (
        echo.
        echo Windows command CERTUTIL.EXE is unavaliable.
        echo This utility is used to convert binary data to base64 format.
        echo Check access rights to %systemroot%\system32\certutil.exe
        echo.
    ) > !tmplog!
    type !tmplog! 

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:is_admin
    setlocal
    set log=%1
 
    @rem https://stackoverflow.com/questions/4051883/batch-script-how-to-check-for-admin-rights
 
    echo !date! !time! Administrative permissions required for this scenario. Command to check: >>!log!
    set run_cmd=net session
    @rem set run_cmd=fsutil dirty query %systemdrive%
    echo !date! !time! !run_cmd! 1>>!log! 2>&1
    cmd /c !run_cmd! 1>>!log! 2>&1
    set elev=!errorlevel!
    (
        if !elev! EQU 0 (
            echo !date! !time! Success: Administrative permissions confirmed.
            set is_admin=1
        ) else (
            @rem When current scenario has NO admin rights then result of NET SESSION will be:
            @rem ---------------
            @rem System error 5
            @rem Access denied
            @rem ---------------
            echo !date! !time! Failure: Current permissions inadequate.
            set is_admin=0
        )
    ) >> !log!
    endlocal & set "%~2=%is_admin%"
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:admin_rights_req
    setlocal
    set tmplog=%1
    (
        echo.
        echo This scenario requires must be executed by user with ADMIN rights.
        echo.
    ) > !tmplog!
    type !tmplog! 

    if .%can_stop%.==.1. (
        echo.
        echo Press any key to FINISH. . .
        echo.
        @pause>nul
    )

    goto final
goto:eof

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:haltHelper
()
exit /b

@rem #+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#+=#

:final
@rem http://stackoverflow.com/questions/10534911/how-can-i-exit-a-batch-file-from-within-a-function
if not .!INIT_SHELL_DIR!.==.. (
    cd /d !INIT_SHELL_DIR!
)
call :haltHelper 2> nul

:end_of_test
echo.
echo.
echo %date% %time%. Final point of script %~f0. 
echo Now you can close this window. Bye-bye...
echo.
exit /b
