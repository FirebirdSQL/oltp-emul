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
echo Parsing config file ^>%cfg%^<. Please wait. . .
set err_setenv=0
@rem Extract only non-empty lines with only names of parameters:

for /F "tokens=*" %%a in ('findstr /i /r /c:"^[ 	]*[a-z,0-9]" %cfg%') do (
  if "%%a" neq "" (

    @rem Detect whether value of parameter contain quotes or no. If yes than this
    @rem value should NOT be changed by removing its whitespaces.

    echo %%a|find """">nul

    if errorlevel 1 ( 
      @rem @echo ^|%%a^| - does NOT contain quotes
      for /F "tokens=1-2 delims==" %%i in ("%%a") do (
        @rem echo Parsed-NON-quoted: param="%%i" val="%%j"
        if "%%j"=="" (
          set err_setenv=1
          echo. && echo ### NO VALUE found for parameter "%%i" ### && echo.
        ) else (

          @rem _NAME_ and _VALUE_ of parameter (both can be with leading and trailing whitespaces):
          set par=%%i
          set val=%%j

          @rem -----------------------------------
          @rem When "delims=" clause is NOT specified then default delimeters are TAB and SPACE.
          @rem If we take 1st token from such string than it will be WITHOUT whitespaces.
          @rem Similarly for _VALUE_ of parameter:
          @rem -----------------------------------
          for /F "tokens=1" %%p in ("!par!") do (
            @rem echo param=^|%%i^|, name w/o white-spaces=^|%%p^|
            for /F "tokens=1" %%u in ("!val!") do (
              set %%p=%%u
              @rem echo param=^|%%p^|, value w/o white-spaces=^|%%u^|
            )
          )
        )
      )

    ) else (

      @rem @echo ^|%%a^| - DOES contain quotes
      for /F "tokens=1-2 delims==" %%i in ("%%a") do (
        @rem echo Parsed-quoted: param="%%i" val="%%j"
        set par=%%i

        if "%%j"=="" (
          set err_setenv=1
          echo. && echo ### NO VALUE found for parameter "%%i" ### && echo.
        ) else (
          @rem We can remove all white-spaces only from _NAME_ of parameter
          @rem but NOT from its _VALUE_
          for /F "tokens=1" %%p in ("!par!") do (
            set %%p=%%j
            @rem echo param=^|%%p^|, value w/o white-spaces=^|%%j^|
          )
        )
      )
    )
  )
)


if .%err_setenv%.==.1. goto err_setenv

@rem Removing trailing backslash from %fbc% and %tmpdir% if any.
@rem NB: `command error` will be here in case when value ends with double quote
@rem      so we have to remove it before comparision with trailing backslash.
@rem See: stackoverflow.com/questions/535975/dealing-with-quotes-in-windows-batch-scripts

set fbc_deq=!fbc:"=!
if .%fbc_deq:~-1%.==.\. (
  set fbc=%fbc:~0,-1%
)

set tmp_deq=!tmpdir:"=!
if .%tmp_deq:~-1%.==.\. (
  set tmpdir=%tmpdir:~0,-1%
)

echo. && echo Config parsing finished. Result:

for %%v in (tmpdir,fbc,is_embed,dbnm,no_auto_undo,use_mtee,detailed_info,init_docs,init_buff,wait_for_copy,warm_time,test_time) do (
  if "!%%v!"=="" (
    echo ### MISSED: %%v ###
    set err_setenv=1
  ) else (
    echo Param: ^|%%v^|, value: ^|!%%v!^|
  )

)

if .%is_embed%.==.0. (
  for %%v in (usr,pwd,host,port) do (
    if "!%%v!"=="" (
      echo ### MISSED: %%v ###
      set err_setenv=1
    ) else (
      echo Param: ^|%%v^|, value: ^|!%%v!^|
    )
  )
)

if .%1.==.30. (
  for %%v in (mon_unit_perf) do (
    if "!%%v!"=="" (
      echo ### MISSED: %%v ###
      set err_setenv=1
    ) else (
      echo Param: ^|%%v^|, value: ^|!%%v!^|
    )
  )
)

if .%err_setenv%.==.1. goto no_env

@rem check that result of PREVIOUSLY called batch (1build_oltp_emul_NN.bat) is OK:

set build_err=0

call :chk_build_result build_err

echo build_err=%build_err%

if .%build_err%.==.1. goto end

if not exist %fbc%\isql.exe goto bad_fbc_path
if not exist %fbc%\gfix.exe goto bad_fbc_path
if not exist %fbc%\fbsvcmgr.exe goto bad_fbc_path
echo All necessary FB utilities found in %fbc%

if .%is_embed%.==.. (
  echo 
  echo %~f0: not defined mandatory env. var: ^>^>^>is_embed^<^<^<
  echo.
  echo Add line like:
  echo.
  echo is_embed = 0 ^| 1
  echo.
  echo - to the file `%cfg%`
  pause
  goto end
)

md %tmpdir%\sql 2>nul

@rem #######################################

@rem Attempt to get server version together with OS: WIndows or LInux)

echo|set /p=Getting Firebird info... 

set tmplog=%tmpdir%\tmp_get_fb_db_info.log
set tmperr=%tmpdir%\tmp_get_fb_db_info.err
if .%is_embed%.==.1. (
  %fbc%\fbsvcmgr localhost:service_mgr info_server_version 1>%tmplog% 2>%tmperr%
) else (
  %fbc%\fbsvcmgr %host%/%port%:service_mgr user %usr% password %pwd% info_server_version 1>%tmplog% 2>%tmperr%
)

for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo Could NOT define server version on host=^>%host%^<,   port=^>%port%^<
  echo.
  echo Result of trying to do that via fbsvcmgr:
  echo ------------------------------------------------------------------
  type %tmperr%
  echo ------------------------------------------------------------------
  echo.
  echo 1. Ensure that Firebird is running on specified host.
  echo 2. Check settings in %cfg%: host, port, user and password.
  echo.
  echo Press any key to FINISH this batch. . .
  pause>nul
  goto end
)

@rem result: log content = "Server version: LI-V2.5.3.26790 Firebird 2.5" etc
for /f "usebackq tokens=3" %%a in ("%tmplog%") do (
 set fbb=%%a
 set fbo=!fbb:~0,2!
)
@echo build No ^>%fbb%^<
del %tmperr% 2>nul
del %tmplog% 2>nul

@rem #######################################

set tmpsql=%tmpdir%\tmp_init_data_pop.sql
set tmplog=%tmpdir%\tmp_init_data_pop.log
set tmpchk=%tmpdir%\tmp_init_data_chk.sql
set tmpclg=%tmpdir%\tmp_init_data_chk.log
set tmperr=%tmpdir%\tmp_init_data_chk.err

@echo Check that previous job of building database was finished OK.
del %tmpchk% 2>nul
del %tmpclg% 2>nul
echo set heading off; set list on;>>%tmpchk%
echo -- check that all database objects already exist: >>%tmpchk%
echo select iif( exists( select * from semaphores where task='all_build_ok' ), >>%tmpchk%
echo                     'all_dbo_exists', >>%tmpchk%
echo                     'some_dbo_absent'>>%tmpchk%
echo           ) as "build_result=" >>%tmpchk%
echo from rdb$database;>>%tmpchk%

if .%is_embed%.==.1. (
   set run_isql=%fbc%\isql %dbnm% -i %tmpchk% -nod -n 
) else (
   set run_isql=%fbc%\isql %host%/%port%:%dbnm% -i %tmpchk% -user %usr% -pas %pwd% -n -nod
)
@echo Command that now to be run:
@echo %run_isql%
echo Content of script %tmpchk%:
@echo --------------------------
type %tmpchk%
@echo --------------------------
cmd /c %run_isql% 1^>%tmpclg% 2^>%tmperr%
set db_build_finished_ok=2

for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo Could not check that all database objects already exist
  echo SQL script: %tmpchk%
  echo Errors log: %tmperr%
  echo ---------- content of errors log ----------------
  type %tmperr%
  echo -------------------------------------------------
) else (
  echo RESULT: script finished OK: database exists and online.
)

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
goto bad_dbnm

:chk4ods
find /c /i "unsupported on-disk" %tmperr% >nul
if errorlevel 1 goto chk4online
goto bad_ods

:chk4online
find /c /i "shutdown" %tmperr% >nul
if errorlevel 1 goto chk4open
goto db_offline

:chk4open
find /c /i "Error while trying to open file" %tmperr% >nul

if errorlevel 1 (
  @rem database DOES exist and ONLINE, but we have to ensure that ALL objects was successfully created in it.
  @rem -------------------------------------------------------------------------------------------------------
  for /f "usebackq" %%A in ('!tmperr!') do set size=%%~zA
  if .%size%.==.. set size=0
  if %size% gtr 0 (
    set db_build_finished_ok=0
  ) else (
    set db_build_finished_ok=1
    find /c /i "all_dbo_exists" !tmpclg! >nul
    if errorlevel 1 set db_build_finished_ok=0
    @rem type !tmpclg!
  )
  echo.
  echo db_build_finished_ok=^>^>^>!db_build_finished_ok!^<^<^<
  echo ############################
  echo.

  if .!db_build_finished_ok!.==.0. (
    echo.
    echo Database: ^>%dbnm%^< -- DOES exist but
    echo its creation process was not completed.
    echo.
    echo ################################################################################
    echo Press ENTER to start again recreation of all DB objects or Ctrl-C to FINISH. . .
    echo ################################################################################
    echo.
    pause>nul
    goto :db_build
  ) else (
    echo Database ^>%dbnm%^< exists with all needed objects.
    goto :chk_more
  )
) else (
  call :try_create_db
)

:db_build

echo #########################
echo Call 1build_oltp_emul.bat 
echo #########################

call 1build_oltp_emul.bat %1 batch

@rem check that result of just called batch (1build_oltp_emul_NN.bat) is OK:
set build_err=0

call :chk_build_result build_err

@rem echo build_err=%build_err%
if .%build_err%.==.1. goto end

echo #########################################
echo RETURN from 1build_oltp_emul.bat - all OK
echo #########################################

:chk_more

set tmpsql=%tmpdir%\tmp_init_data_pop.sql
set tmplog=%tmpdir%\tmp_init_data_pop.log
set tmpchk=%tmpdir%\tmp_init_data_chk.sql
set tmpclg=%tmpdir%\tmp_init_data_chk.log
set tmperr=%tmpdir%\tmp_init_data_chk.err

@rem ################### check for non-empty stoptest.txt ################################
del %tmpchk% 2>nul
del %tmpclg% 2>nul
echo set heading off; set list on;>>%tmpchk%
echo -- check that test now can be run: table 'ext_stoptest' must be EMPTY>>%tmpchk%
echo select iif( exists( select * from ext_stoptest ), >>%tmpchk%
echo                     '1', >>%tmpchk%
echo                     '0'>>%tmpchk%
echo           ) as "cancel_flag=" >>%tmpchk%
echo from rdb$database;>>%tmpchk%
@rem type %tmpchk%

if .%is_embed%.==.1. (
   set run_isql=%fbc%\isql %dbnm% -i %tmpchk% -nod -n 
) else (
   set run_isql=%fbc%\isql %host%/%port%:%dbnm% -i %tmpchk% -user %usr% -pas %pwd% -n -nod
)

echo.
echo Check for non-empty external file stoptest.txt. 
echo Command that now to be run:
echo %run_isql%
echo Content of script %tmpchk%:
echo --------------------------
type %tmpchk%
echo --------------------------

cmd /c %run_isql% 1^>%tmpclg% 2^>%tmperr%

set cancel_flag=2
for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo SQL script: %tmpchk%
  echo Errors log: %tmperr%
  echo ---------- content of errors log ----------------
  type %tmperr%
  echo -------------------------------------------------
  echo.
  echo Probably you have to open firebird.conf and set 'ExternalFileAccess'
  echo to some folder where 'firebird' account has enough rights.
  echo.
  echo Press any key to FINISH. . .
  pause>nul
  goto end
) else (
  echo RESULT: script finished OK.

  for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
    set /a %%a
    if errorlevel 1 set err_setenv=1
  )
  if .%cancel_flag%.==.. set cancel_flag=0
)

echo cancel_flag=^>^>^>%cancel_flag%^<^<^<

del %tmpchk% 2>nul

if .%cancel_flag%.==.1. (
  goto test_canc
)
goto chk_init

@rem --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- --- ---

:chk_init

echo.
echo Check is the database needs to be filled up with necessary number of documents
echo ##############################################################################

del %tmpclg% 2>nul
if /i .%init_docs%.==.. goto more
if /i .%init_docs%.==.0. goto more

@rem check that total number of docs (count from doc_list table) is LESS than %init_docs%
@rem and correct %init_docs% (reduce it) so that its new value + count will be equal to 
@rem required total number of docs (which is specified in config)

del %tmpchk% 2>nul
del %tmpclg% 2>nul
del %tmperr% 2>nul

echo set list on;                                                   >>%tmpchk%
echo select (select count(*) from doc_list) as "existing_docs="     >>%tmpchk%
echo       ,rdb$get_context('SYSTEM','ENGINE_VERSION') as "engine=" >>%tmpchk%
echo       ,iif( exists( select * from rdb$relations r              >>%tmpchk% 
echo                     where r.rdb$relation_name='PERF_LOG'       >>%tmpchk% 
echo                           and r.rdb$relation_type=1            >>%tmpchk% 
echo                           and r.rdb$view_blr is not null       >>%tmpchk%
echo                    ),                                          >>%tmpchk%
echo             'XPERFLOG_01',                                     >>%tmpchk% 
echo             'PERF_LOG'                                         >>%tmpchk%
echo           ) as "log_tab="                                      >>%tmpchk% 
echo  from rdb$database;                                            >>%tmpchk% 

if .%is_embed%.==.1. (
  %fbc%\isql %dbnm% -pag 0 -i %tmpchk% -n 1>%tmpclg% 2>%tmperr%
) else (
  %fbc%\isql %host%/%port%:%dbnm% -pag 0 -i %tmpchk% -user %usr% -pas %pwd% -n  1>%tmpclg% 2>%tmperr%
)

@rem result: file %tmpclg% contains several rows like this: existing_docs=1234
@rem now we can APPLY this row as it was SET command in batch and
@rem assign its value to env. variable with the SAME name -- `existing_docs`, `engine` etc:

for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
  set %%a
  for /F "tokens=1-2 delims==" %%i in ("%%a") do (
    set par=%%i
    set val=%%j
    for /F "tokens=1" %%p in ("!par!") do (
      @rem echo param=^|%%i^|, name w/o white-spaces=^|%%p^|
      for /F "tokens=1" %%u in ("!val!") do (
        set %%p=%%u
        @rem echo param=^|%%p^|, value w/o white-spaces=^|%%u^|
      )
    )
  )
)

set /a init_docs = init_docs - %existing_docs%

if %init_docs% leq 0 goto more

@rem --------------   i n i t i a l      d a t a     p o p u l a t i o n   -------------

@echo off
echo Initial data population until total number
echo of created docs will be not less than ^>^>^> %existing_docs% +  %init_docs% ^<^<^< 
echo.
echo Please wait. . .
echo.

del %tmpsql% 2>nul
del %tmplog% 2>nul
del %tmperr% 2>nul

if exist %tmpsql% goto err_del
if exist %tmplog% goto err_del

@rem --- Preparing: create temp .sql to be run and add/update settings table ---

if .%engine:~0,3%.==.2.5. (
  echo commit; -- skip `linger` statement: engine older that 3.0 >>%tmpsql%
) else (
  echo alter database set linger to 15; commit; >>%tmpsql%
)
echo set transaction no wait;>>%tmpsql%
echo alter sequence g_init_pop restart with 0;>>%tmpsql%
echo commit;>>%tmpsql%

@rem --- Run ISQL: restart sequence g_init_pop ---
@echo on
if .%is_embed%.==.1. (
  %fbc%\isql %dbnm% -i %tmpsql% -n -o 1>%tmplog% 2>%tmperr%
) else (
  %fbc%\isql %host%/%port%:%dbnm% -i %tmpsql% -user %usr% -pas %pwd% -n 1>%tmplog% 2>%tmperr%
)

@rem --- Check that script finished Ok: size of tmperr must be ZERO ---
@echo off
for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo Script which resets generator for initial data population finished with ERROR.
  echo.
  echo SQL script: %tmpchk%
  echo Errors log: %tmperr%
  echo ---------- content of errors log ----------------
  type %tmperr%
  echo -------------------------------------------------
  echo.
  echo Press any key to FINISH this batch. . .
  pause>nul
  goto end
)
del %tmpsql% 2>nul
del %tmplog% 2>nul

@rem 15.10.2014 obtain current setting of FW and change it - perhaps temply - to OFF:
@rem if NOT exists %fbc%\gfix.exe ( goto run_init_pop )


@rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem  G E T    I N I T I A L  S T A T E    O F    F O R C E D   W R I T E S 
@rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

echo set list on; >>%tmpsql% 
echo select >>%tmpsql% 
echo    m.mon$forced_writes as "fw_current="                   >>%tmpsql% 
echo   ,iif( exists( select * from perf_log g                  >>%tmpsql% 
echo                 where g.unit='fw_both_changes_done' and g.aux1=1 and g.aux2 is null  >>%tmpsql% 
echo               ^), '0', '1'  >>%tmpsql% 
echo      ^) as "fw_can_upd=" >>%tmpsql% 
echo from mon$database m;>>%tmpsql%
echo set list off;>>%tmpsql%

if .%is_embed%.==.1. (
  %fbc%\isql %dbnm% -i %tmpsql% -n -m -o %tmplog%
) else (
  %fbc%\isql %host%/%port%:%dbnm% -i %tmpsql% -user %usr% -pas %pwd% -n  -m -o %tmplog%
)

@rem result: %tmplog% contain rows like:
@rem FW_CURRENT = 1
@rem FW_CAN_UPD = 1
@rem now we can APPLY this row as it was SET command in batch and
@rem assign its value to env. variable with the SAME name -- `existing_docs`:
for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmplog%') do (
  set /a %%a
)

@rem mode *TO WHICH*  we have to RETURN .fdb after filling:
if .%fw_current%.==.1. (
   set fw_mode=sync
) else (
   set fw_mode=async
)

set fwlog=%tmpdir%\tmp_change_fw.log

type %tmplog% >%fwlog%
echo fw_current=%fw_current%>>%fwlog%
echo fw_can_upd=%fw_can_upd%>>%fwlog%

del %tmpsql% 2>nul
del %tmplog% 2>nul
del %tmperr% 2>nul

@rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
@rem  T E M P L Y    S E T    F O R C E D   W R I T E S   =   O F F
@rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

if .%fw_can_upd%.==.1. (

  @rem 1. add to %log_tab% table our intention to change FW, always to OFF

  echo update or insert into %log_tab% (unit, aux1, aux2, dts_beg, dts_end^) >>%tmpsql%
  echo values ('fw_both_changes_done', %fw_current%, null, 'now', null^) >>%tmpsql%
  echo matching (unit^);>>%tmpsql%
  echo commit;>>%tmpsql%
  if .%is_embed%.==.1. (
    %fbc%\isql %dbnm% -i %tmpsql% -n 1>%tmplog% 2>%tmperr%
  ) else (
    %fbc%\isql %host%/%port%:%dbnm% -i %tmpsql% -user %usr% -pas %pwd% -n  1>%tmplog% 2>%tmperr%
  )
  for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
  if .%size%.==.. set size=0

  if %size% gtr 0 (
    echo.
    echo Could NOT add/update record in table %log_tab% with data about changing FW.
    echo.
    echo SQL script: %tmpsql%
    echo Errors log: %tmperr%
    echo ---------- content of errors log ----------------
    type %tmperr%
    echo -------------------------------------------------
    echo.
    echo 1. Check that table with name: '%log_tab' - really exists.
    echo 2. Check content of script: %tmpsql%
    echo.
    echo Press any key to FINISH this batch. . .
    pause>nul
    goto end
  ) else (
    echo.
    echo Successfully change FW temply to OFF for initial data filling.
  )

  @rem 2. run - perhaps LOCAL - gfix with command line for REMOTE database to set fw = OFF:

  if .%is_embed%.==.1. (
    %fbc%\gfix %dbnm% -w async
  ) else (
    %fbc%\gfix %host%/%port%:%dbnm% -w async -user %usr% -pas %pwd%
  )

)

@rem echo check %log_tab% and FW after change to OFF && echo Have return .fdb to: fw_mode=%fw_mode% && exit


del %tmpsql% 2>nul
del %tmplog% 2>nul

:run_init_pop

echo set term ^^;>>%tmpsql%
echo execute block as>>%tmpsql%
echo begin>>%tmpsql%
echo   -- find LAST record with TWO changes of FW (aux1, aux2). Field 'info' will contain>>%tmpsql%
echo end^^>>%tmpsql%
echo set term ;^^>>%tmpsql%

set init_pkq=50
set srv_frq=10
if .%no_auto_undo%.==.. set no_auto_undo=1
@rem %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
call :gen_working_sql init_pop %tmpsql% %init_pkq% %no_auto_undo%
@rem %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

set t0=%time%
@echo %t0%: START initial data population. 
@echo Recalc index statistcs: at the start of every %srv_frq%th packet.
@echo Executed .sql: %tmpsql%

set /a k = 1

@rem 15.10.2014, suggestion by AK: set cache buffer pretty large for initial pop data
@rem Actual for CS or SC, will be ignored in SS:
@echo Cache buffer for ISQL connect when running initial data population: ^>%init_buff%^<

if .%is_embed%.==.1. (
   set run_isql=%fbc%\isql %dbnm% -i %tmpsql% -n -c %init_buff% -m -o %tmplog%
) else (
   set run_isql=%fbc%\isql %host%/%port%:%dbnm% -i %tmpsql% -c %init_buff% -user %usr% -pas %pwd% -n -m -o %tmplog%
)
@echo.
@echo ISQL command: %run_isql%
@echo.

:iter_loop

  @rem periodically we have to run service SPs: srv_make_invnt_total, srv_make_money_saldo, srv_recalc_idx_stat
  set /a p = %k% %% %srv_frq%

  @echo packet #%k% >>%tmplog%
  @echo ^=^=^=^=^=^=^=^=^=^=^=^=^=>>%tmplog%
  if %p% equ 0 (
    del %tmpchk% 2>nul
    del %tmpclg% 2>nul
    @echo set list on; set heading on;               >>%tmpchk%
    @echo commit; set transaction no wait;           >>%tmpchk%
    @echo select count(*^) as srv_make_invnt_saldo_result from srv_make_invnt_saldo;>>%tmpchk%
    @echo commit; set transaction no wait;           >>%tmpchk%
    @echo select count(*^) as srv_make_money_saldo_result from srv_make_money_saldo;>>%tmpchk%
    @echo commit; set transaction no wait;           >>%tmpchk%
    @echo select count(*^) as srv_recalc_idx_stat_result from srv_recalc_idx_stat; >>%tmpchk%
    @echo commit; >>%tmpchk%

    echo |set /p=%time%: start run service SPs...
    @rem --------------- perform service: srv_make*_total, recalc index statistics -------------
    type %tmpchk% >>%tmplog%
    if .%is_embed%.==.1. (
      %fbc%\isql %dbnm% -i %tmpchk% -n -c %init_buff% -m -o %tmplog%
    ) else (
      %fbc%\isql %host%/%port%:%dbnm% -i %tmpchk% -c %init_buff% -user %usr% -pas %pwd% -n -m -o %tmplog%
    )
    echo  %time%: finish service SPs.
  )


  @rem --------------------------- create %init_pkg% business operations -------------------------------
  echo|set /p=%time%, packet #%k% start...

  cmd /c %run_isql%

  @rem result: one or more (in case of complex operations like sp_add_invoice_to_stock)
  @rem documents has been created; if some error occured, sequence g_init_pop has been
  @rem 'returned' to its previous value.
  @rem now we must check total number of docs:
  del %tmpchk% 2>nul
  del %tmpclg% 2>nul
  @echo set list off; set heading off;                                     >>%tmpchk%
  @echo select                                                             >>%tmpchk%
  @echo     'new_docs='^|^|gen_id(g_init_pop,0^)                           >>%tmpchk%
  @echo from rdb$database;                                                 >>%tmpchk%

 
  if .%is_embed%.==.1. (
    %fbc%\isql %dbnm% -pag 0 -i %tmpchk% -n 1>%tmpclg% 2>&1
  ) else (
    %fbc%\isql %host%/%port%:%dbnm% -pag 0 -i %tmpchk% -user %usr% -pas %pwd% -n 1>%tmpclg% 2>&1
  )

  @rem result: file %tmpclg% contains ONE row like this: new_docs=12345
  @rem now we can APPLY this row as it was SET command in batch and
  @rem assign its value to env. variable with the SAME name -- `new_docs`:
  for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
    set /a %%a
  )
  echo  %time%, packet #%k% finish: docs created ^>^>^> %new_docs% ^<^<^<, limit = %init_docs%

  set /a k = k+1
if %new_docs% lss %init_docs% goto iter_loop

@rem If we are here than no more init docs should be created
if %init_docs% gtr 0 (
  del %tmpchk% 2>nul
  del %tmpclg% 2>nul
  @echo set list off; set heading off;                                     >>%tmpchk%
  @echo select                                                             >>%tmpchk%
  @echo     'act_docs='^|^|( select count(*^) from doc_list ^)              >>%tmpchk%
  @echo from rdb$database;                                                 >>%tmpchk%
  if .%is_embed%.==.1. (
    %fbc%\isql %dbnm% -pag 0 -i %tmpchk% -n 1>%tmpclg% 2>&1
  ) else (
    %fbc%\isql %host%/%port%:%dbnm% -pag 0 -i %tmpchk% -user %usr% -pas %pwd% -n 1>%tmpclg% 2>&1
  )
  @rem result: file %tmpclg% contains ONE row like this: new_docs=12345
  @rem now we can APPLY this row as it was SET command in batch and
  @rem assign its value to env. variable with the SAME name -- `new_docs`:
  for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %tmpclg%') do (
    set /a %%a
  )

  @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  @rem  R E S T O R E   I N I T    S T A T E    O F     F O R C E D   W R I T E S
  @rem  :::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
  set tmpfwsql=!tmpdir!\tmp_restore_fw.sql
  set tmpfwlog=!tmpdir!\tmp_restore_fw.log
  del !tmpfwsql! 2>nul
  set run_isql=
  if .%fw_can_upd%.==.1. (

    echo RESTORE old value of FW.
    echo.
    echo %time% 1. Run gfix with command line for REMOTE database to set fw = %fw_mode%. . .
  
    if .%is_embed%.==.1. (
      %fbc%\gfix %dbnm% -w %fw_mode%
    ) else (
      %fbc%\gfix %host%/%port%:%dbnm% -w %fw_mode% -user %usr% -pas %pwd%
    )

    echo %time% 2. Update in %log_tab% table our intention to REVERT change FW to its initial state. . .

    echo set stat on; set echo on;>>!tmpfwsql!
    echo update %log_tab% g set aux2=%fw_current%, dts_end='now' where g.unit='fw_both_changes_done';>>!tmpfwsql!
    echo commit;>>!tmpfwsql!
    echo set stat off;>>!tmpfwsql!
    echo select aux1, aux2, dts_beg, dts_end from %log_tab% g where g.unit='fw_both_changes_done';>>!tmpfwsql!
    if .%is_embed%.==.1. (
      set run_isql=%fbc%\isql %dbnm% -i !tmpfwsql! -nod 1^>!tmpfwlog! 2^>&1
    ) else (
      set run_isql=%fbc%\isql %host%/%port%:%dbnm% -i !tmpfwsql! -nod -user %usr% -pas %pwd% 1^>!tmpfwlog! 2^>^&1
    )
    cmd /c !run_isql!
    echo %time% Done, check log !tmpfwlog!
  )
 @rem echo fw_mode=%fw_mode%
 @rem echo check %log_tab% and FW after change to INITIAL
 @rem pause
 @rem exit


  @echo %time% FINISH initial data population.
  @echo.
  @echo Job has been done from %t0% to %time%. Count rows in doc_list: !act_docs!

  @echo Log: %tmplog%
  if .%wait_for_copy%.==.1. (
    @echo.
    @echo ### NOTE ###
    @echo.
    @echo It's a good time to make COPY of test database in order 
    @echo to start all following runs from the same state.
    @echo.
    @echo Press any key to begin WARM-UP and TEST mode. . .
    @pause>nul
  )

)


@rem -----------------------   w o r k i n g    p h a s e   -----------------------------

:more

set mode=oltp_%1

@rem winq = number of opening isqls
set winq=%2

set sql=%tmpdir%\sql\tmp_random_run.sql
set logbase=oltp%1_%computername%

@rem Make comparison of TIMESTAMPS: this batch vs %sql%.
@rem If this batch is OLDER that %sql% than we can SKIP recreating %sql%
set skipGenSQL=0

set sqldts=19000101000000
set cfgdts=19000101000000
set thisdts=19000101000000

if exist %sql% (
  call :getFileDTS gen_vbs
  @rem echo before call: sqldts=!sqldts!, thisdts=!thisdts!
  call :getFileDTS get_dts !sql! sqldts
  call :getFileDTS get_dts %~f0 thisdts
  @rem echo after call: sqldts=!sqldts!, thisdts=!thisdts!
  if .!thisdts!. lss .!sqldts!. (
    echo this batch is OLDER than sql

    call :getFileDTS get_dts !cfg! cfgdts
    if .!cfgdts!. lss .!sqldts!. (
      echo Test config file is OLDER than sql
      set skipGenSQL=1
    ) else (
      echo Test config file %cfg% is NEWER than %sql%
    )
  ) else (
    echo This batch is NEWER than %sql%
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
  if .%no_auto_undo%.==.. set no_auto_undo=1
  if .%detailed_info%.==.. set detailed_info=0
  @rem ##################################################
  call :gen_working_sql run_test %sql% 300 %no_auto_undo% %detailed_info%
  @rem ##################################################
)

if not exist %sql% goto no_script

del %tmpdir%\%logbase%*.log 2>nul
del %tmpdir%\%logbase%*.err 2>nul

@echo off
set tmpsql=%tmpdir%\tmp_show.tmp
set tmplog=%tmpdir%\tmp_show.log
set tmperr=%tmpdir%\tmp_show.err

del %tmpsql% 2>nul
del %tmplog% 2>nul
del %tmperr% 2>nul

echo set heading off; set list on;>>%tmpsql%
echo select iif( exists( select * from ext_stoptest ), 'TEST_CANCELLATION_FLAG_DETECTED', 'ALL_OK_-_TEST_CAN_BE_STARTED') as ">>> attention_msg >>>" from rdb$database;>>%tmpsql%

@echo on
if .%is_embed%.==.1. (
  %fbc%\isql %dbnm% -i %tmpsql% -n 1>%tmplog% 2>%tmperr%
) else (
  %fbc%\isql %host%/%port%:%dbnm% -i %tmpsql% -user %usr% -pas %pwd% -n 1>%tmplog% 2>%tmperr%
)
@echo off
for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo Could NOT define main test settings and/or cancellation status.
  echo.
  echo SQL  file: %tmpsql%
  echo Error log: %tmperr%
  echo ------------------------------------------------------------------
  type %tmperr%
  echo ------------------------------------------------------------------
  echo.
  echo Press any key to FINISH this batch. . .
  pause>nul
  goto end
)

@echo off

find /c /i "CANCEL" %tmplog% >nul
if errorlevel 1 goto start
goto test_canc

:start

type %tmplog% 

del %tmpsql% 2>nul
del %tmplog% 2>nul

@rem echo Add record for checking work to be stopped on timeout. . .
echo commit; set transaction no wait;                                         >>%tmpsql%
echo delete from %log_tab% g                                                  >>%tmpsql%
echo where g.unit in ( 'perf_watch_interval',                                 >>%tmpsql%
echo                   'dump_dirty_data_semaphore',                           >>%tmpsql%
echo                   'dump_dirty_data_progress'                             >>%tmpsql%
echo                 );                                                       >>%tmpsql%
echo commit;                                                                  >>%tmpsql%
echo insert into %log_tab%( unit,                  info,     exc_info,         >>%tmpsql%
echo                       dts_beg, dts_end, elapsed_ms)                      >>%tmpsql%
echo               values( 'perf_watch_interval', 'active', 'by %~f0',        >>%tmpsql%
echo         dateadd( %warm_time% minute to current_timestamp),               >>%tmpsql%
echo         dateadd( %warm_time% + %test_time% minute to current_timestamp), >>%tmpsql%
echo         -1 -- skip this record from being displayed in srv_mon_perf_detailed >>%tmpsql%
echo         );                                                               >>%tmpsql%
echo insert into %log_tab%( unit,                        info,  stack,         >>%tmpsql%
echo                       dts_beg, dts_end, elapsed_ms)                      >>%tmpsql%
echo               values( 'dump_dirty_data_semaphore', '',    'by %~f0',     >>%tmpsql%
echo                       null, null, -1);                                   >>%tmpsql%
echo commit;>>%tmpsql%
echo set width unit 20;>>%tmpsql%
echo set width add_info 30;>>%tmpsql%
echo set width dts_measure_beg 24;>>%tmpsql%
echo set width dts_measure_end 24;>>%tmpsql%
echo set list on;>>%tmpsql%
echo.>>%tmpsql%

echo Check test settings and record in %log_tab% table that will be checked
echo by attachments to stop their work:                                 
echo select                                                                            >>%tmpsql%
echo        m.mon$database_name as db_name                                             >>%tmpsql%
echo       ,m.mon$page_size as pg_size                                                 >>%tmpsql%
echo       ,m.mon$page_buffers as buffers                                              >>%tmpsql%
echo       ,m.mon$forced_writes as forced_writes                                       >>%tmpsql%
echo       ,rdb$get_context('USER_SESSION','WORKING_MODE') working_mode                >>%tmpsql%
echo       ,rdb$get_context('USER_SESSION','HALT_TEST_ON_ERRORS') halt_test_on_errors  >>%tmpsql%
echo       ,rdb$get_context('USER_SESSION', 'C_CATCH_MISM_BITSET') c_catch_mism_bitset >>%tmpsql%
echo       ,rdb$get_context('USER_SESSION','ENABLE_MON_QUERY') enable_mon_query        >>%tmpsql%
echo       ,g.add_info                                                                 >>%tmpsql%
echo       ,g.dts_measure_beg                                                          >>%tmpsql%
echo       ,g.dts_measure_end                                                          >>%tmpsql%
echo from mon$database m                                                               >>%tmpsql%
echo cross join                                                                        >>%tmpsql%
echo (                                                                                 >>%tmpsql%
echo   select p.unit, p.exc_info as add_info,                                          >>%tmpsql%
echo          replace(cast(p.dts_beg as varchar(24)),' ','_') as dts_measure_beg,      >>%tmpsql%
echo          replace(cast(p.dts_end as varchar(24)),' ','_') as dts_measure_end       >>%tmpsql%
echo   from %log_tab% p                                                                >>%tmpsql%
echo        where p.unit = 'perf_watch_interval'                                       >>%tmpsql%
echo        order by dts_beg desc rows 1                                               >>%tmpsql%
echo ) g;                                                                              >>%tmpsql%
echo.>>%tmpsql%
echo set list off;>>%tmpsql%

if .%is_embed%.==.1. (
  %fbc%\isql %dbnm% -i %tmpsql% -n 1>%tmplog% 2>%tmperr%
) else (
  %fbc%\isql %host%/%port%:%dbnm% -i %tmpsql% -user %usr% -pas %pwd% -n 1>%tmplog% 2>%tmperr%
)

for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo Could NOT run script with commands for test being auto-stop.
  echo.
  echo SQL  file: %tmpsql%
  echo Error log: %tmperr%
  echo ------------------------------------------------------------------
  type %tmperr%
  echo ------------------------------------------------------------------
  echo.
  echo Press any key to FINISH this batch. . .
  pause>nul
  goto end
)

type %tmplog%

@rem set log4all=%tmpdir%\%logbase%-001.performance_report.txt
set log4all=%tmpdir%\oltp%1.report.txt

@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
@rem INITIATE REPORT FILE "oltp30.report.txt"
@rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

del %log4all% 2>nul
@echo Created by: %~f0>>%log4all%
type %tmplog%>>%log4all%

@echo Final report will be written in file:
@echo #####################################
@echo.
@echo %log4all%
@echo.


del %tmpsql% 2>nul
del %tmplog% 2>nul

@echo Launching %winq% ISQL sessions:
@echo off

for /l %%i in (1, 1, %winq%) do (

  @rem +++++++++++++++++++++++++++++++++++++++++++++++++++++++
  @rem +++    l a u n c h   w o r k i n g     I S Q L s    +++
  @rem +++++++++++++++++++++++++++++++++++++++++++++++++++++++

  echo|set /p=.

  set /a k=1000+%%i
  if .%%i.==.1. (
    echo Check parameters for oltp_isql_run_worker.bat:>>%log4all%
    echo ---------------------------------------------->>%log4all%
    echo is_embed=^>%is_embed%^<   >>%log4all%
    echo fbc=^>%fbc%^<             >>%log4all%
    echo dbnm=^>%dbnm%^<           >>%log4all%
    echo sql=^>%sql%^<             >>%log4all%
    echo logbase=^>%logbase%^<     >>%log4all%
    echo log4all=^>%log4all%^<     >>%log4all%
    echo host=^>%host%^<           >>%log4all%
    echo port=^>%port%^<           >>%log4all%
    echo usr=^>%usr%^<             >>%log4all%
    echo pwd=^>%pwd%^<             >>%log4all%
    echo.                          >>%log4all%
    echo.>>%log4all%
    echo Command that launch ISQL window #%%i:             >>%log4all%
    echo.>>%log4all%
    echo   start /min oltp_isql_run_worker.bat fb sql logbase sid log4all>>%log4all%
    echo                                       ^^   ^^     ^^     ^^     ^^  >>%log4all%
    echo                                       1   2     3     4     5   >>%log4all%
    echo.>>%log4all%
    echo Actual values of parameters used now:                                        >>%log4all%
    echo 1: %fb% ^<-- version of FB as number, 25 or 30                     >>%log4all%
    echo 2: %sql% ^<-- input SQL script for working                         >>%log4all%
    echo 3: %tmpdir%\%logbase%-!k:~1,3! ^<-- base name of logs for *that* ISQL window >>%log4all%
    echo 4: %%i  ^<-- SID, sequential number of that ISQL (limits: 1...%winq%^)     >>%log4all%
    echo 5: %log4all% ^<-- log for overall report                           >>%log4all%
    echo.>>%log4all%
    echo All subsequent windows are launched similarly. >>%log4all%

    echo.>>%log4all%
    
    echo Obtain server version and implementation info:>>%log4all%
    echo.>>%log4all%
    set run_fbs=%fbc%\fbsvcmgr %host%/%port%:service_mgr user %usr% password %pwd% info_server_version info_implementation
    echo !run_fbs!>>%log4all%
    cmd /c !run_fbs! 1>>%log4all% 2>>&1
    echo.>>%log4all%

    echo Obtain database header statistics BEFORE test:>>%log4all%
    echo.>>%log4all%
    set run_fbs=%fbc%\fbsvcmgr %host%/%port%:service_mgr user %usr% password %pwd% -action_db_stats -sts_hdr_pages -dbname %dbnm%
    echo !run_fbs!>>%log4all%
    cmd /c !run_fbs! 1>>%log4all% 2>>&1
    echo.>>%log4all%
    echo %date% %time% Done. Now launch %winq% ISQL sessions. >>%log4all%
  )
 
  @rem Sample of %tmpdir%\%logbase%-!k:~1,3!: "C:\TEMP\logs.oltp25\oltp25_CSPROG-001"
  @rem =========
  @start /min oltp_isql_run_worker.bat %fb% %sql% %tmpdir%\%logbase%-!k:~1,3! %%i %log4all%

)
echo. && echo %date% %time% Done.
echo Config params, running commands and results see in file: %log4all%

goto end

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
  @goto end

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
  @goto end

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
  @goto end

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
  @goto end

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
  @goto end

:db_offline
  @echo off
  echo.
  echo Database ^>%dbnm%^< DOES exist but is OFFLINE now. Test can not start.
  echo Run first: 
  echo            gfix -online %dbnm% -user %usr% -password %pwd%
  echo.
  echo Press any key to FINISH. . .
  @pause>nul
  goto end


:build_not_finished
  @echo off
  echo.
  echo Host: ^>%host%^<
  echo Port: ^>%port%^<
  echo Database: ^>%dbnm%^<
  echo.
  echo Building of database objects was INTERRUPTED or NOT STARTED.
  echo Erase this database and try to run again either this batch
  echo or 1build_oltp_emul.bat with 1st argument = %1
  echo.
  echo Press any key to FINISH. . .
  echo.
  @pause>nul
  @goto end

:no_script
  @echo off
  echo.
  echo THERE IS NO .SQL SCRIPT FOR SPECIFIED SCENARIO ^>^>^>%1^<^<^<
  echo.
  echo Press any key to FINISH. . .
  echo.
  @pause>nul
  @goto end

:err_setenv
  @echo off
  echo.
  echo Config file: %cfg% - can NOT set some of environment variables.
  echo Perhaps, there is no equal sign ("=") between name and value in some line.
  echo.
  echo Press any key to FINISH. . .
  echo.
  @pause>nul
  @goto end
  
:test_canc
  @echo off
  echo.
  echo ##################################################################################
  echo FILE 'stoptest.txt' ON SERVER SIDE HAS NON-ZERO SIZE, MAKE IT EMPTY TO START TEST!
  echo ##################################################################################
  echo.
  echo Press any key to FINISH. . .
  echo.
  @pause>nul
  @goto end

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
  @goto end

:gen_working_sql
  setlocal
  set mode=%1
  set sql=%2
  set lim=%3
  @rem should NO AUTO UNDO clause be added in SET TRAN command ? 1=yes, 0=no
  if .%4.==.1. set nau=NO AUTO UNDO

  @rem should detailed info for each iteration be added in log ? 
  @rem (actual only for mode=run_test; if "1" then add select * from %log_tab%)
  set nfo=%5

  del %sql% 2>nul
  echo.
  echo sql generating routine `gen_working_sql`:  
  @echo mode: ^>%mode%^<, sql: ^>%sql%^<, number of repeating EB: ^>%lim%^<
  @echo -- ### WARNING: DO NOT EDIT ###>>%sql%
  @echo -- GENERATED AUTO BY %~f0>>%sql%
  if /i .%mode%.==.init_pop. (
    @echo -- For check settings of database.>>%sql%
    @echo -- NB-1: FW must be (temply^) set to OFF>>%sql%
    @echo -- NB-2: cache buffers temply set to pretty big value>>%sql%
    @echo set list on; select * from mon$database; set list off;>>%sql%
  )
  echo.>>%sql%
  echo.
  for /l %%i in (1, 1, %lim%) do (

    set /a k = %%i %% 50
    if !k! equ 0 echo generate script part# %%i of total %lim%

    @echo ----------------- mode = %mode%, iter # %%i ----------------------->>%sql%
    @echo.>>%sql%
    if %%i equ 1 (
      @echo commit;                                                          >>%sql% 
    )
    @echo -- check oltp_config.NN for optional setting NO AUTO UNDO here: >>%sql%
    @echo set transaction no wait %nau%;                                  >>%sql%

    if /i .%mode%.==.run_test. (                                       
      @echo set width test_ends_at 19;                                           >>%sql%
      @echo set width engine 6;                                                  >>%sql%
      @echo set width mon_info 50;                                               >>%sql%
      if %%i equ 1 (

        @echo select left( cast( p.dts_end as varchar(24^) ^), 19 ^)             >>%sql%
        @echo      as test_ends_at                                               >>%sql%
        @echo     ,rdb$get_context('SYSTEM','ENGINE_VERSION'^)                   >>%sql%
        @echo      as engine                                                     >>%sql%
        @echo from %log_tab% p                                                    >>%sql%
        @echo where p.unit = 'perf_watch_interval'                               >>%sql%
        @echo order by dts_beg desc                                              >>%sql%
        @echo rows 1;                                                            >>%sql%

      ) else (

        @echo select                                                             >>%sql%
        @echo     left( cast( rdb$get_context('USER_SESSION','PERF_WATCH_END'^)  >>%sql%
        @echo                 as varchar(24^)                                    >>%sql%
        @echo             ^),                                                    >>%sql%
        @echo           19                                                       >>%sql%
        @echo        ^)                                                          >>%sql%
        @echo     as test_ends_at                                                >>%sql%
        @echo     ,rdb$get_context('SYSTEM','ENGINE_VERSION'^)                   >>%sql%
        @echo      as engine                                                     >>%sql%
        if /i .%fb%.==.30. (
          if /i .%mon_unit_perf%.==.1. (
            @echo      -- this info set only in SP srv_fill_mon:                >>%sql%
            @echo     ,rdb$get_context('USER_SESSION','MON_INFO'^) as mon_info  >>%sql%
          )
        )
        @echo from rdb$database;                                                 >>%sql%

      )
    )

    @echo set term ^^;                                                       >>%sql%
    @echo execute block as                                                   >>%sql%
    @echo     declare v_unit dm_name;                                        >>%sql%
    @echo begin                                                              >>%sql%
    if /i .%mode%.==.init_pop. (
      @echo     select p.unit                                                  >>%sql%
      @echo     from srv_random_unit_choice(                                   >>%sql%
      @echo               '',                                                  >>%sql%
      @echo               'creation,state_next,service,',                      >>%sql%
      @echo               '',                                                  >>%sql%
      @echo               'removal'                                            >>%sql%
      @echo     ^) p                                                            >>%sql%
      @echo     into v_unit;                                                   >>%sql%
    )
    if /i .%mode%.==.run_test. (
      @echo     if ( NOT exists( select * from ext_stoptest ^) ^) then        >>%sql%
      @echo     begin                                                         >>%sql%
      @echo       select p.unit                                               >>%sql%
      @echo       from srv_random_unit_choice(                                >>%sql%
      @echo                 '',                                               >>%sql%
      @echo                 '',                                               >>%sql%
      @echo                 '',                                               >>%sql%
      @echo                 ''                                                >>%sql%
      @echo       ^) p                                                        >>%sql%
      @echo       into v_unit;                                                >>%sql%
      @echo     end                                                           >>%sql%
      @echo     else                                                          >>%sql%
      @echo       v_unit = 'TEST_WAS_CANCELLED';                              >>%sql%
    )
    @echo     rdb$set_context('USER_SESSION','SELECTED_UNIT', v_unit^);  >>%sql%
    @echo     rdb$set_context('USER_SESSION','ADD_INFO', null^);             >>%sql%
    @echo end                                                                >>%sql%
    @echo ^^                                                                 >>%sql%
    @echo set term ;^^                                                       >>%sql%

    @rem 28.08.2014
    if /i .%mode%.==.run_test. (
      if /i .%fb%.==.30. (
        if /i .%mon_unit_perf%.==.1. (
          @echo ------ ###############################################  ------->>%sql%
          @echo -----  G A T H E R    M O N.    D A T A    B E F O R E  ------->>%sql%
          @echo ------ ###############################################  ------->>%sql%
          @echo set term ^^;                                                   >>%sql%
          @echo execute block as                                               >>%sql%
          @echo   declare v_dummy bigint;                                      >>%sql%
          @echo begin                                                          >>%sql%
          @echo   -- define context var which will identify rowset field       >>%sql%
          @echo   -- in mon_log and mon_log_table_stats:                       >>%sql%
          @echo   -- (this value is ised after call app. unit^):               >>%sql%
          @echo   rdb$set_context('USER_SESSION','MON_ROWSET', gen_id(g_common,1^)^);>>%sql%
          @echo.                                                                >>%sql%
          @echo   -- gather mon$ tables BEFORE run app unit, only in FB 3.0    >>%sql%
          @echo   -- add FIRST row to GTT tmp$mon_log                          >>%sql%
          @echo   select count(*^)                                             >>%sql%
          @echo   from srv_fill_tmp_mon(                                       >>%sql%
          @echo           rdb$get_context('USER_SESSION','MON_ROWSET'^)    -- :a_rowset >>%sql%
          @echo          ,1                                                -- :a_ignore_system_tables >>%sql%
          @echo          ,rdb$get_context('USER_SESSION','SELECTED_UNIT'^) -- :a_unit   >>%sql%
          @echo                                        ^)                      >>%sql%
          @echo   into v_dummy;                                                >>%sql%
          @echo.                                                               >>%sql%
          @echo   -- result: tables tmp$mon_log and tmp$mon_log_table_stats    >>%sql%
          @echo   -- are filled with counters BEFORE application unit call.    >>%sql%
          @echo   -- Field `mult` in these tables is now negative: -1          >>%sql%
          @echo end                                                            >>%sql%
          @echo ^^                                                             >>%sql%
          @echo set term ;^^                                                   >>%sql%
          @echo commit; --  ##### C O M M I T  #####  after gathering mon$data >>%sql%
          @echo set transaction no wait %nau%;                                 >>%sql%
        )
      )
    )

    @echo set width dts 12;                                                  >>%sql%
    @echo set width trn 14;                                                  >>%sql%
    @echo set width unit 20;                                                 >>%sql%
    @echo set width elapsed_ms 10;                                           >>%sql%
    @echo set width msg 20;                                                  >>%sql%
    @echo set width add_info 40;                                             >>%sql%
    @echo set width mon_info 20;                                             >>%sql%

    @rem 17.08.2014 
    @echo -- ensure that just before call application unit                   >>%sql%
    @echo -- table tmp$perf_log is really EMPTY:                             >>%sql%
    @echo delete from tmp$perf_log;                                          >>%sql%

    @echo --------------- before run app unit: show it's NAME -------------- >>%sql%
    @echo set list off;                                                      >>%sql%
    @echo select                                                             >>%sql%
    @echo     substring(cast(current_timestamp as varchar(24^)^) from 12 for 12^) as dts, >>%sql%
    @echo     'tra_'^|^|current_transaction trn,                             >>%sql%
    @echo      rdb$get_context('USER_SESSION','SELECTED_UNIT'^) as unit, >>%sql%
    @echo     'start' as msg,                                                >>%sql%
    @echo     'att_'^|^|current_connection as add_info                       >>%sql%
    @echo from rdb$database;                                                 >>%sql%

    @echo.                                                                   >>%sql%
    @echo set term ^^;                                                       >>%sql%
    @echo execute block as                                                   >>%sql%
    @echo     declare v_stt varchar(128^);                                    >>%sql%
    @echo     declare result int;                                            >>%sql%
    @echo     declare v_old_docs_num int;                                    >>%sql%
    @echo begin                                                              >>%sql%

    if /i .%mode%.==.init_pop. (
      @echo     -- ::: nb ::: g_init_pop is always incremented by 1            >>%sql%
      @echo     -- in sp_add_doc_list, even if fault will occur later          >>%sql%
      @echo     -- set context var 'INIT_DATA_POP' to not-null for analyzing   >>%sql%
      @echo     -- in sp_customer_reserve and others SPs and raise e`ception   >>%sql% 
      @echo     rdb$set_context('USER_TRANSACTION','INIT_DATA_POP',1^);         >>%sql%
      @echo     v_old_docs_num = gen_id( g_init_pop, 0^);                       >>%sql%
    )

    @echo     begin                                                               >>%sql%
    @echo         -- save in ctx var timestamp of START app unit:                 >>%sql%
    @echo         rdb$set_context('USER_SESSION','BAT_PHOTO_UNIT_DTS', cast('now' as timestamp^)^);>>%sql%
    @echo         rdb$set_context('USER_SESSION', 'GDS_RESULT', null^);           >>%sql%
    @echo         -- save value of current_transaction because we make COMMIT     >>%sql%
    @echo         -- after gathering mon$ tables when oltp_config.NN parameter    >>%sql%
    @echo         -- mon_unit_perf=1                                              >>%sql%
    @echo         rdb$set_context('USER_SESSION', 'APP_TRANSACTION', current_transaction^); >>%sql%
    @echo.                                                                        >>%sql%
    @echo         if ( rdb$get_context('USER_SESSION','SELECTED_UNIT'^)           >>%sql%
    @echo              is distinct from                                           >>%sql%
    @echo              'TEST_WAS_CANCELLED'                                       >>%sql%
    @echo           ^) then >>%sql%                                               >>%sql%
    @echo           begin                                                         >>%sql%
    @echo             v_stt='select count(*^) from '                              >>%sql%
    @echo             ^|^|rdb$get_context('USER_SESSION','SELECTED_UNIT'^);       >>%sql%
    @echo             ------   ######################################### ------   >>%sql%
    @echo             ------   r u n    a p p l i c a t i o n    u n i t ------   >>%sql%
    @echo             ------   ######################################### ------   >>%sql%
    @echo             execute statement (v_stt^) into result;                     >>%sql%
    @echo.                                                                        >>%sql%
    @echo             rdb$set_context('USER_SESSION', 'RUN_RESULT',               >>%sql%
    @echo                             'OK, '^|^| result ^|^|' rows'^);            >>%sql%
    @echo           end                                                           >>%sql%
    @echo         else                                                            >>%sql%
    @echo           begin                                                         >>%sql%
    @echo              rdb$set_context('USER_SESSION','RUN_RESULT',               >>%sql%
    @echo                         (select e.fb_mnemona                            >>%sql%
    @echo                          from perf_log g                                >>%sql%
    @echo                          join fb_errors e on g.fb_gdscode=e.fb_gdscode  >>%sql%
    @echo                          where g.unit='sp_halt_on_error'                >>%sql%
    @echo                          order by g.dts_end DESC rows 1                 >>%sql%
    @echo                         ^)                                              >>%sql%
    @echo                             ^);                                         >>%sql%
    @echo           end                                                           >>%sql%
    @echo         -- add timestamp for FINISH app unit:                           >>%sql%
    @echo         rdb$set_context( 'USER_SESSION','BAT_PHOTO_UNIT_DTS',           >>%sql%
    @echo                          rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^)>>%sql%
    @echo                          ^|^| ' '                                       >>%sql%
    @echo                          ^|^| cast('now' as timestamp^)                 >>%sql%
    @echo                       ^);                                               >>%sql%
    @echo     when any do                                                         >>%sql%
    @echo         begin                                                           >>%sql%
    @echo            rdb$set_context('USER_SESSION', 'GDS_RESULT', gdscode^);     >>%sql%
    if /i .%mode%.==.init_pop. (
      @echo            v_stt = 'alter sequence g_init_pop restart with '          >>%sql%
      @echo                    ^|^|v_old_docs_num;                                >>%sql%
      @echo            execute statement (v_stt^);                                >>%sql%
    )
    @echo            rdb$set_context('USER_SESSION', 'RUN_RESULT', 'error, gds='^|^|gdscode^); >>%sql%
    @echo            exception;                                              >>%sql%
    @echo         end                                                        >>%sql%
    @echo     end                                                            >>%sql%
    @rem @echo     suspend;                                                       >>%sql%
    @echo end                                                                >>%sql%
    @echo ^^                                                                 >>%sql%
    @echo set term ;^^                                                       >>%sql%

    @rem 28.08.2014
    if /i .%mode%.==.run_test. (
      if /i .%fb%.==.30. (
        if /i .%mon_unit_perf%.==.1. (
          @echo ------ ###############################################  ------->>%sql%
          @echo -----  G A T H E R    M O N.    D A T A    A F T E R    ------->>%sql%
          @echo ------ ###############################################  ------->>%sql%
          @echo set term ^^;                                                   >>%sql%
          @echo execute block as                                               >>%sql%
          @echo   declare v_dummy bigint;                                      >>%sql%
          @echo begin                                                          >>%sql%
          @echo   -- gather mon$ tables AFTER running app unit, only in FB 3.0 >>%sql%
          @echo   -- add SECOND row to GTT tmp$mon_log:                        >>%sql%
          @echo   select count(*^) from srv_fill_tmp_mon                       >>%sql%
          @echo   (                                                            >>%sql%
          @echo           rdb$get_context('USER_SESSION','MON_ROWSET'^)    -- :a_rowset >>%sql%
          @echo          ,1                                                -- :a_ignore_system_tables >>%sql%
          @echo          ,rdb$get_context('USER_SESSION','SELECTED_UNIT'^) -- :a_unit   >>%sql%
          @echo          ,coalesce(                                        -- :a_info   >>%sql%
          @echo                rdb$get_context('USER_SESSION','ADD_INFO'^) -- aux info, set in APP units only! >>%sql%
          @echo               ,rdb$get_context('USER_SESSION','RUN_RESULT'^)   >>%sql%
          @echo              ^)                                                >>%sql%
          @echo          ,rdb$get_context('USER_SESSION', 'GDS_RESULT'^)   -- :a_gdscode >>%sql%
          @echo   ^)                                                           >>%sql%
          @echo   into v_dummy;                                                >>%sql%
          @echo.                                                               >>%sql%
          @echo   -- add pair of rows with aggregated differences of mon$      >>%sql%
          @echo   -- counters from GTT to fixed tables                         >>%sql%
          @echo   -- (this SP also removes data from GTTs^):                   >>%sql%
          @echo   select count(*^)                                             >>%sql%
          @echo   from srv_fill_mon(                                           >>%sql%
          @echo     rdb$get_context('USER_SESSION','MON_ROWSET'^) -- :a_rowset >>%sql%
          @echo                    ^)                                          >>%sql%
          @echo   into v_dummy;                                                >>%sql%
          @echo   rdb$set_context('USER_SESSION','MON_ROWSET', null^);         >>%sql%
          @echo end                                                            >>%sql%
          @echo ^^                                                             >>%sql%
          @echo set term ;^^                                                   >>%sql%
          @echo commit; --  ##### C O M M I T  #####  after gathering mon$data >>%sql%
          @echo set transaction no wait %nau%;                                 >>%sql%
        )
      )
    )

    @echo -- Output results of application unit run:                           >>%sql%
    @echo select                                                               >>%sql%
    @echo     substring(cast(current_timestamp as varchar(24^)^) from 12 for 12^) as dts >>%sql%
    @echo     ,'tra_'^|^|rdb$get_context('USER_SESSION','APP_TRANSACTION'^) trn >>%sql%
    @echo     ,rdb$get_context('USER_SESSION','SELECTED_UNIT'^) as unit        >>%sql%
    @echo     ,lpad(                                                           >>%sql%
    @echo            cast(                                                     >>%sql%
    @echo                  datediff(                                           >>%sql%
    @echo                    millisecond                                       >>%sql%
    @echo                    from cast(left(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^),24^) as timestamp^)>>%sql%
    @echo                    to   cast(right(rdb$get_context('USER_SESSION','BAT_PHOTO_UNIT_DTS'^),24^) as timestamp^)>>%sql%
    @echo                         ^)                                           >>%sql%
    @echo                 as varchar(10^)                                      >>%sql%
    @echo                ^)                                                    >>%sql%
    @echo           ,10                                                        >>%sql%
    @echo           ,' '                                                       >>%sql%
    @echo         ^) as elapsed_ms                                             >>%sql%
    @echo     ,rdb$get_context('USER_SESSION', 'RUN_RESULT'^) as msg           >>%sql%
    @echo     ,rdb$get_context('USER_SESSION','ADD_INFO'^) as add_info         >>%sql%
    @echo from rdb$database;                                                   >>%sql%

    if /i .%mode%.==.init_pop. (
      @echo set list on;                                                       >>%sql%
      @echo set width db_name 80;                                              >>%sql%
      @echo select                                                             >>%sql%
      @echo     m.mon$database_name db_name,                                   >>%sql%
      @echo     rdb$get_context('SYSTEM','ENGINE_VERSION'^) engine,            >>%sql%
      @echo     MON$FORCED_WRITES db_forced_writes,                            >>%sql%
      @echo     MON$PAGE_BUFFERS page_buffers,                                 >>%sql%
      @echo     m.mon$page_size * m.mon$pages as db_current_size,              >>%sql%
      @echo     gen_id(g_init_pop,0^) as new_docs_created                       >>%sql%
      @echo from mon$database m;                                               >>%sql%
    )
    if /i .%mode%.==.run_test. (

      @echo set bail on; -- for catch test cancellation and stop all .sql      >>%sql%
      @echo set term ^^;                                                       >>%sql%
      @echo execute block as                                                   >>%sql%
      @echo begin                                                              >>%sql%
      @echo     if ( rdb$get_context('USER_SESSION','SELECTED_UNIT'^)          >>%sql%
      @echo          is NOT distinct from                                      >>%sql%
      @echo          'TEST_WAS_CANCELLED'                                      >>%sql%
      @echo       ^) then >>%sql%                                              >>%sql%
      @ECHO     begin                                                          >>%sql%
      @echo        exception ex_test_cancellation;                             >>%sql%
      @echo     end                                                            >>%sql%
      @echo     -- REMOVE data from context vars, they will not be used more   >>%sql%
      @echo     -- in this iteration:                                          >>%sql%
      @echo     rdb$set_context('USER_SESSION','SELECTED_UNIT', null^);        >>%sql%
      @echo     rdb$set_context('USER_SESSION','RUN_RESULT',    null^);        >>%sql%
      @echo     rdb$set_context('USER_SESSION','GDS_RESULT',    null^);        >>%sql%
      @echo     rdb$set_context('USER_SESSION','ADD_INFO', null^);             >>%sql%
      @echo     rdb$set_context('USER_SESSION','APP_TRANSACTION', null^);      >>%sql%
      @echo end                                                                >>%sql%
      @echo ^^                                                                 >>%sql%
      @echo set term ;^^                                                       >>%sql%
      @echo set bail off;                                                      >>%sql%

      if .%nfo%.==.1. (
        @echo -- Begin block to output DETAILED results of iteration.            >>%sql%
        @echo -- To disable this output change "detailed_info" setting to 0      >>%sql%
        @echo -- in test configuration file "%cfg%"                              >>%sql%
        @echo set heading off;                                                   >>%sql%
        @echo set list on;                                                       >>%sql%
        @echo select '+++++++++  perf_log data for this Tx: ++++++++' as msg     >>%sql%
        @echo from rdb$database;                                                 >>%sql%
        @echo set heading on;                                                    >>%sql%
        @echo set list on;                                                       >>%sql%
        @echo set width unit 35;                                                 >>%sql%
        @echo set width info 80;                                                 >>%sql%
        @echo select g.id, g.unit, g.exc_unit, g.info, g.fb_gdscode,g.trn_id,    >>%sql%
        @echo        g.elapsed_ms, g.dts_beg, g.dts_end                          >>%sql%
        @echo from perf_log g                                                    >>%sql%
        @echo where g.trn_id = current_transaction;                              >>%sql%
        @rem do NOT: @echo order by id;                                          >>%sql%
        @echo set list off;                                                      >>%sql%
        @echo -- Finish block to output DETAILED results of iteration.           >>%sql%
      ) else (
        @echo.>>%sql%
        @echo -- Output of detailed results of iteration DISABLED.               >>%sql%
        @echo -- To enable this output change "detailed_info" setting to 1       >>%sql%
        @echo -- in test configuration file "%cfg%"                              >>%sql%
      )
      @echo.>>%sql%
    )
    @echo commit;                                                            >>%sql%
    @echo set list off;                                                      >>%sql%

    if %%i equ %lim% (
      @echo set width msg 60;                                                  >>%sql%
      @echo select                                                             >>%sql%
      @echo     current_timestamp dts,                                         >>%sql%
      @echo     '### FINISH packet, disconnect ###' as msg                >>%sql%
      @echo from rdb$database;                                               >>%sql%
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
      echo 'Created auto, do NOT edit! >>%vbs%
      echo 'Used to obtain exact timestamp of file >>%vbs%
      echo 'Usage: cscript ^/^/nologo %vbs% ^<file^> >>%vbs%
      echo 'Result: last modified timestamp, in format: YYYYMMDDhhmiss >>%vbs%
      echo Set objFS ^= CreateObject("Scripting.FileSystemObject"^) >>%vbs%
      echo Set objArgs ^= WScript.Arguments >>%vbs%
      echo strFile ^= objArgs(0^) >>%vbs%
      echo ts ^= timeStamp(objFS.GetFile(strFile^).DateLastModified^) >>%vbs%
      echo WScript.Echo ts >>%vbs%
      echo. >>%vbs%
      echo Function timeStamp( d ^) >>%vbs%
      echo   timeStamp ^= Year(d^) ^& _ >>%vbs%
      echo   Right("0" ^& Month(d^),2^) ^& _ >>%vbs%
      echo   Right("0" ^& Day(d^),2^)  ^& _ >>%vbs% 
      echo   Right("0" ^& Hour(d^),2^) ^& _ >>%vbs%
      echo   Right("0" ^& Minute(d^),2^) ^& _ >>%vbs%
      echo   Right("0" ^& Second(d^),2^) >>%vbs%
      echo End Function >>%vbs%
      endlocal&goto:eof
    )
    if /i .%1.==.get_dts. (
      @rem echo|set /p=%time%, packet #%k% start...
      echo|set /p=Obtaining timestamp of %2... 
      @rem echo cscript ^/^/nologo %vbs% %2 1^>%dts%
      cscript //nologo %vbs% %2 1>%dts%
      type %dts%
      endlocal&set /p %~3=<%dts%
    )
  endlocal
goto:eof

:chk_build_result 
  set err=!tmpdir!\1build_oltp_emul_!fb!.err
  echo Subroutine :chk_build_result 
  for /f "usebackq" %%A in ('%err%') do set size=%%~zA
  if .%size%.==.. set size=0
  if %size% gtr 0 (
    echo.
    echo Script for building database objects finished with ERROR!
    echo.
    echo Check log: %err%
    echo.
    echo Remove this file before starting again.
    echo.
    echo Press any key to FINISH this batch. . .
    pause>nul
    @rem endlocal&set build_err=1
    endlocal&set %~1=1
    goto end
  ) else (
    echo RESULT: no errors for building database objects.
  )
goto:eof

:try_create_db
  setlocal
  @rem If we are here than database is absent. Suggest to create it but only in case when
  @rem %dbnm% contains slashes (forwarding for LInux and backward for WIndows)
  if /i .%fbo%.==.LI. (
    for /f "tokens=1,2 delims=/" %%a in ("%dbnm%") do ( 
      set w1=%%a
      set w2=%%b
    )
  ) else (
    for /f "tokens=1,2 delims=\" %%a in ("%dbnm%") do ( 
      set w1=%%a
      set w2=%%b
    )
  )

  if .%w1%.==.. goto bad_dbnm
  if .%w2%.==.. goto bad_dbnm

  @echo.
  @echo ##################################################################################
  @echo.
  @echo Database ^>%dbnm%^< does NOT exist on host ^>%host%^<. 
  @echo Press ENTER for attempt to CREATE it, Ctrl-C to QUIT. . .
  @echo.
  @echo ##################################################################################
  pause

  set tmpsql=%tmpdir%\tmp_create_dbnm.sql
  set tmplog=%tmpdir%\tmp_create_dbnm.log
  set tmperr=%tmpdir%\tmp_create_dbnm.err

  @echo Attempt to CREATE database. 
  if .%is_embed%.==.1. (
     echo create database '%dbnm%' page_size 8192; commit; show database; exit;>%tmpsql%
     set run_isql=%fbc%\isql -q -i %tmpsql%
  ) else (
     echo create database '%host%/%port%:%dbnm%' page_size 8192 user '%usr%' password '%pwd%'; commit; show database; exit;>%tmpsql%
     set run_isql=%fbc%\isql -q -i %tmpsql% 
     @rem 1^>%tmplog% 2^>%tmperr%
  )
  @echo Command to be run:
  @echo %run_isql%

  echo Content of script %tmpsql%:
  echo ---------------------------------------
  type %tmpsql% 
  echo ---------------------------------------

  cmd /c %run_isql% 1^>%tmplog% 2^>%tmperr%

  @rem win: -Error while trying to create file
  @rem nix: -Error while trying to create file

  find /c /i "Error while trying to create file" %tmperr% >nul
  if errorlevel 1 goto fill_db
  goto bad_dbnm

  :fill_db
  @rem If we are here than database has been just created (auto) and we must call 1build_oltp_emul.bat 

  for /f "usebackq" %%A in ('%tmperr%') do set size=%%~zA
  if .%size%.==.. set size=0
  if %size% gtr 0 (
    echo.
    echo RESULT: script of CREATING database finished with ERRORS.
    echo --------------------------
    type %tmperr%
    echo --------------------------
    pause
  ) else (
    echo RESULT: script finished OK, database has been created now.
    type %tmplog%
  )
  endlocal
goto:eof

:trim
  setLocal 
  @rem EnableDelayedExpansion
  set Params=%*
  for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof
@rem exit /b


:end

