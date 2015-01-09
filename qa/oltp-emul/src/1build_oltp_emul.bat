@echo off
cls
setlocal enabledelayedexpansion enableextensions

if .%1.==.. goto no_arg1

set batch_mode=0
if /i .%2.==.batch. set batch_mode=1

set fb=%1
if .%fb%.==.25. goto ok
if .%fb%.==.30. goto ok
goto no_arg1

:ok

set cfg=oltp%fb%_config.win
for /F "tokens=*" %%a in ('findstr /r /i /c:"^[^#]" %cfg%') do (
  set %%a
)

md %tmpdir% 2>nul

set bld=%tmpdir%\%~n0_%fb%.sql
set log=%tmpdir%\%~n0_%fb%.log
set err=%tmpdir%\%~n0_%fb%.err
set tmp=%tmpdir%\%~n0_%fb%.tmp

echo log=%log%, err=%err%

echo Check settings (read from config file %cfg%)
echo.
echo Path to FB client: fbc = ^>%fbc%^<; version of isql:
%fbc%\isql -z -? 2>nul
echo.
echo Server host = ^>%host%^<, port = ^>%port%^<
echo.
echo Database name/alias: ^>%dbnm%^<
echo.
echo User name and password: ^>%usr%^< ^>%pwd%^<
echo.
echo Test connect and analyze engine version for matching to arg. ^>%fb%^<

del %tmp% 2>nul
echo set width engine 20;set list off;set heading off;>>%tmp%
echo select 'engine='^|^|rdb$get_context('SYSTEM','ENGINE_VERSION'^) engine from rdb$database;>>%tmp%
echo show version;quit;>>%tmp%
del %log% 2>nul
del %err% 2>nul

if .%is_embed%.==.1. (
  set run_isql=%fbc%\isql %dbnm% -nod -pag 0 -i %tmp% -m -o %err%
) else (
  set run_isql=%fbc%\isql %host%/%port%:%dbnm% -nod -pag 0 -i %tmp% -m -o %err% -user %usr% -pas %pwd%
)

@echo Command to be executed now:
@echo.
@echo %run_isql%
@echo.
cmd /c !run_isql!

@rem @echo on
@rem if .%is_embed%.==.1. (
@rem   %fbc%\isql %dbnm% -nod -pag 0 -i %tmp% -m -o %err%
@rem ) else (
@rem   %fbc%\isql %host%/%port%:%dbnm% -nod -pag 0 -i %tmp% -m -o %err% -user %usr% -pas %pwd%
@rem )
@rem @echo off

@echo Result:
type %err%
del %tmp% 2>nul

  @rem --------------------------------------------------------------------------
  @rem c h e c k   t h a t   c o n n e c t   c a n   b e   e s t a b l i s h e d:
  @rem --------------------------------------------------------------------------
  find /c /i "failed to establish" %err% >nul
  if errorlevel 1 goto chk4file
  goto fb_noanswer

:chk4file
  @rem --------------------------------------------------------------------------
  @rem c h e c k    t h a t    a l i a s   o r    n a m e    i s   c o r r e c t:
  @rem --------------------------------------------------------------------------
  @rem FB on windows and on linux will produce DIFFERENT messages when alias not found!
  @rem Common part of these messages is: "Error while trying to open file" - 10.10.2014
  find /c /i "Error while trying to open file" %err% >nul
  if errorlevel 1 goto chk4shut
  goto db_missed

:chk4shut
  @rem -----------------------------------------------------------------------------------
  @rem c h e c k    t h a t     d a t a b a s e   h a s    b e e n    s h u t d o w n e d:
  @rem -----------------------------------------------------------------------------------
  find /c /i "shutdown" %err% >nul
  if errorlevel 1 goto chk4pass
  goto db_offline

:chk4pass
  @rem ----------------------------------------------------------------------
  @rem c h e c k    t h a t     u s e r   +   p a s s w o r d   a r e    O k.
  @rem ----------------------------------------------------------------------
  find /c /i "user name and password are not defined" %err% >nul
  if errorlevel 1 goto chkengine
  goto db_usrpass

:chkengine

  if .%fb%.==.25. (
    find /c /i "engine=2.5" %err% >nul
    if errorlevel 1 goto engine_err
  )
  if .%fb%.==.30. (
    find /c /i "engine=3.0" %err% >nul
    if errorlevel 1 goto engine_err
  )
  @echo All checks of isql temp log messages PASSED OK.
  goto db_online


:db_online


echo.
@echo #################################################
echo Database will be created for FB ^>^>^> %fb% ^<^<^<
@echo #################################################
echo.
if .%batch_mode%.==.0. (
  echo Press any key to START building database objects. . .
  @pause>nul
)

del %err% 2>nul

@echo off
del %bld% 2>nul
echo show version;>%bld%
echo show database;>>%bld%
echo set list on;>>%bld%
echo select * from mon$database;>>%bld%
echo set list off;>>%bld%
echo set echo on;>>%bld%

@rem these scripts DIFFERS for each version of Firebird:
echo in "%~dp0oltp%fb%_DDL.sql";>>%bld%
echo in "%~dp0oltp%fb%_sp.sql";>>%bld%

@rem these scripts are EQUAL for each version of Firebird:
echo in "%~dp0oltp_main_filling.sql";>>%bld%
echo in "%~dp0oltp_data_filling.sql";>>%bld%

echo show collation;>>%bld%
echo show domain;>>%bld%
echo show exception;>>%bld%
echo show generator;>>%bld%
echo show table;>>%bld%
echo show view;>>%bld%
echo show trigger;>>%bld%
echo show proc;>>%bld%

@echo Content of building SQL script:
@echo -------------------------------
type %bld%
@echo -------------------------------


echo.
echo Build test database. Please wait. . . 
echo -------------------------------------

@echo on

if .%is_embed%.==.1. (
  %fbc%\isql %dbnm% -nod -i %bld% 1>%log% 2>%err%
) else (
  %fbc%\isql %host%/%port%:%dbnm% -nod -i %bld% -user %usr% -pas %pwd% 1>%log% 2>%err%
)
@echo off
del %bld% 2>nul

for /f "usebackq" %%A in ('%err%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo Script for building database objects finished with ERROR!
  echo.
  echo Check log: %err%
  echo.
  echo Press any key to FINISH this batch. . .
  pause>nul
  goto end
)

del %tmp% 2>nul
del %log% 2>nul
del %err% 2>nul
echo set width db_name 30;>>%tmp%
echo select                                                    >>%tmp%
echo     m.mon$page_size as page_size                          >>%tmp%
echo    ,m.mon$page_buffers as page_buffers                    >>%tmp%
echo    ,iif(m.mon$forced_writes=0,'OFF','ON') as FW           >>%tmp%
echo    ,m.mon$sweep_interval as sweep                         >>%tmp%
echo    ,right(m.mon$database_name,30) as db_name              >>%tmp%
echo from mon$database m;                                      >>%tmp%
echo set width working_mode 20;>>%tmp%
echo set width setting_name 40;>>%tmp%
echo set width setting_value 15;>>%tmp%
echo set list off;                                             >>%tmp%
echo select s.mcode as setting_name, s.svalue as setting_value >>%tmp%
echo from settings s                                           >>%tmp%
echo where s.working_mode='INIT' and s.mcode='WORKING_MODE'    >>%tmp%
echo UNION ALL                                                 >>%tmp%
echo select t.mcode as setting_name, t.svalue as setting_value >>%tmp%
echo from settings s                                           >>%tmp%
echo join settings t on s.svalue=t.working_mode                >>%tmp%
echo where s.working_mode='INIT' and s.mcode='WORKING_MODE'    >>%tmp%
echo UNION ALL                                                 >>%tmp%
echo select s.mcode, s.svalue                                  >>%tmp%
echo from settings s                                           >>%tmp%
echo where s.working_mode='COMMON'                             >>%tmp%
echo       and s.mcode                                         >>%tmp%
echo           in ('ENABLE_MON_QUERY',                         >>%tmp%
echo               'ENABLE_RESERVES_WHEN_ADD_INVOICE',         >>%tmp%
echo               'C_CATCH_MISM_BITSET',                      >>%tmp%
echo               'TRACED_UNITS',                             >>%tmp%
echo               'C_MAKE_QTY_STORNO_MODE',                   >>%tmp%
echo               'C_MIN_COST_TO_BE_SPLITTED',                >>%tmp%
echo               'C_ROWS_TO_MULTIPLY',                       >>%tmp%
echo               'RANDOM_SEEK_VIA_ROWS_LIMIT',               >>%tmp%
echo               'HALT_TEST_ON_ERRORS');                     >>%tmp%

@echo on
if .%is_embed%.==.1. (
  %fbc%\isql %dbnm% -nod -i %tmp% 1>%log% 2>%err%
) else (
  %fbc%\isql %host%/%port%:%dbnm% -nod -i %tmp% -user %usr% -pas %pwd% 1>%log% 2>%err%
)
@echo off

type %err%
for /f "usebackq" %%A in ('%err%') do set size=%%~zA
if .%size%.==.. set size=0
if %size% gtr 0 (
  echo.
  echo Script for obtaining current settings finished with ERROR!
  echo.
  echo Check log: %err%
  echo.
  echo Press any key to FINISH this batch. . .
  pause>nul
  goto end
)
del %tmp% 2>nul

@echo.
@echo %date% %time% 
@echo Result: all OK. 
if .%batch_mode%.==.0. (
  @echo.
  type %log%
  @echo -----------------------------------------------
  @echo Now run:
  @echo.
  @echo          1run_oltp_emul.bat %fb% ^<N^>
  @echo.
  @echo where:
  @echo.
  @echo        %fb% - version of Firebird for which test database has been created now;
  @echo        ^<N^> - number of ISQL-sessions to be opened.
  echo.
  pause
)
goto end

:no_arg1
  @echo off
  cls
  echo.
  echo.
  echo Please specify version of Firebird for which to make database objects.
  echo Valid variants:
  echo.
  echo    %~f0 25 - for Firebird 2.5
  echo.
  echo    %~f0 30 - for Firebird 3.0
  echo.
  echo Press any key to FINISH this batch file. . .
  @pause>nul
  @goto end
:no_env
  @echo off
  cls
  echo.
  echo.
  echo MISSING CONFIG FILE FOR TEST.
  echo.
  echo Press any key to FINISH this batch file. . .
  @pause>nul
  @goto end
  
:fb_noanswer
  @echo.
  @echo CONNECTION TO FIREBIRD FAULT.
  @echo.
  @echo Check settings 'host' and 'port' in %cfg%
  @echo.
  echo Press any key to FINISH this batch file. . .
  @pause>nul
  goto end

:db_missed
  @echo.
  @echo ######################################################
  @echo Database file or alias is INCORRECT, test can't start.
  @echo Ensure that database is ALREADY EXISTS on the server.
  @echo ######################################################
  @echo.
  @echo Check setting 'dbnm' in %cfg%: it's value must present in the
  @echo list of aliases or exactly match to actual name of .fdb file.
  @echo.
  @echo Check rights of user 'firebird' to the specified database file.
  @echo.
  echo Press any key to FINISH this batch file. . .
  @pause>nul
  goto end

:db_offline
  @echo.
  @echo DATABASE SHUTDOWN DETECTED, test can not start.
  @echo.
  echo Press any key to FINISH this batch file. . .
  @pause>nul
  goto end

:db_usrpass
  @echo.
  @echo INCORRECT USER AND PASSWORD, test can not start.
  @echo.
  @echo Check settings 'usr' and 'pwd' in %cfg%
  @echo.
  echo Press any key to FINISH this batch file. . .
  @pause>nul

:engine_err
  @echo.
  @echo Actual engine version does NOT match input argument ^>%fb%^<
  @echo.
  @echo Check settings 'host' and 'port' in %cfg%
  @echo.
  echo Press any key to FINISH this batch file. . .
  @pause>nul
:end
