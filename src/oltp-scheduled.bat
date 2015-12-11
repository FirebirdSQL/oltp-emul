@echo off
setlocal enabledelayedexpansion enableextensions

cd /d %~dp0

set fbv=%1
if not .%1.==.25. if not .%1.==.30. goto no_vers
set isql_sessions_count=%2
if not defined isql_sessions_count set isql_sessions_count=10

cd ..\util

call fbreplace.bat %fbv%

cd /d %~dp0

call :readcfg oltp%fbv%_config.win

set log=%tmpdir%\%~n0.log
del %log% 2>nul

set FB_SERVICES=fb%fbv%_tmp

for /d %%s in ( %FB_SERVICES% ) do (
  echo %%s
  echo.>>%log%
  sc query FirebirdServer%%s | findstr /i /c:"STOPPED" 1>nul 2>&1
  if errorlevel 1 (
    set msg=!date! !time!. Stopping service FirebirdServer%%s
    echo !msg!
    echo.>>%log%
    echo !msg!>>%log%
    set cmd_run=sc stop FirebirdServer%%s
    echo !cmd_run!
    echo !cmd_run!>>%log%
    sc stop FirebirdServer%%s 1>>%log% 2>&1
    echo !date! !time!. Wait a few seconds. . .
    ping -n 3 127.0.0.1 1>nul
    :: became broken 10.06.2015 (instant reply instead of wait), the reason not found: ping -n 1 -w 2000 1.1.1.1 1>nul 2>&1
    echo !date! !time!. Check that service is really stopped:>>%log%
    set cmd_run=sc query FirebirdServer%%s
    echo !cmd_run!
    echo !cmd_run!>>%log%
    sc query FirebirdServer%%s>>%log%
    sc query FirebirdServer%%s | findstr /i /c:"STOPPED" 1>nul 2>&1
    if errorlevel 1 (
      set msg=!date! !time!. CAN NOT STOP SERVICE! Job terminated.
      echo !msg!
      echo !msg!>>%log%
      exit
    ) else (
      set msg=!date! !time!. Service FirebirdServer%%s has been successfully stopped.
      echo !msg!
      echo.>>%log%
      echo !msg!>>%log%
    )
  ) else (
    set msg=!date! !time!. Service already has been stopped.
    echo !msg!
    echo !msg!>>%log%
  )
  sc query FirebirdServer%%s>>%log%
)
@rem -------------------------------------

echo !date! !time!. Start copy from etalon test database. 1>>%log%
@echo on
@rem 50 Gb: copy E:\OLTP-EMUL\oltp30_050gb.fdb D:\OLTP-EMUL\oltp30_050gb.fdb
@rem 101 Gb: copy E:\OLTP-EMUL\oltp30_100gb.fdb D:\OLTP-EMUL\oltp30_100gb.fdb

copy E:\OLTP-EMUL\oltp%fbv%-docs_50000.fdb D:\OLTP-EMUL\oltp%fbv%-small.fdb

@echo off
echo !date! !time!. Finish copy from etalon test database. 1>>%log%
dir D:\OLTP-EMUL\oltp%fbv%-small.fdb | findstr /i /c:"oltp%fbv%-small.fdb" 1>>%log% 2>&1

@rem -------------------------------------

for /d %%s in ( %FB_SERVICES% ) do (
  set msg=!date! !time!. Starting service FirebirdServer%%s
  echo !msg!
  echo.>>%log%
  echo !msg!>>%log%
  
  echo !date! !time!. Check point BEFORE starting instance: %%s>>%log%
  
  sc start FirebirdServer%%s 1>>%log% 2>&1

  echo !date! !time!. Check point AFTER starting  instance: %%s>>%log%

  ping -n 1 -w 800 1.1.1.1 1>nul 2>&1
  echo !date! !time!. After pause:>>%log%

  sc query FirebirdServer%%s 1>>%log% 2>&1
  sc query FirebirdServer%%s | findstr /i /c:"RUNNING" 1>nul 2>&1
  if errorlevel 1 (
    set msg=!date! !time!. ### FAILED TO EXECUTE ### start service command.
  ) else (
    set msg=!date! !time!. Service has been successfully started.
  )
  echo !msg!
  echo !msg!>>%log%

)

if .%fbv%.==.30. (
    echo !date! !time!. Applying 'gfix -icu' for adjust database with existing ICU version... 1>>%log%
    %fbc%\gfix.exe -icu %host%/%port%:%dbnm% -user %usr% -password %pwd% 1>>%log% 2>&1
    echo !date! !time!. Done.
)

echo !date! !time!. Make probe connect to database and show FB version, DB and test settings... 1>>%log%
echo Check command: echo ... ^| %fbc%\isql %host%/%port%:%dbnm% -user %usr% -password %pwd% 1>>%log%
echo show version; show database; set width setting_name 40; set width setting_value 20; select setting_name, setting_value from Z_CURRENT_TEST_SETTINGS; | %fbc%\isql %host%/%port%:%dbnm% -user %usr% -password %pwd% 1>>%log% 2>&1
echo !date! !time!. Done. Now we can launch 1run_oltp_emul.bat 1>>%log% 2>&1

E:\OLTP-EMUL\src\1run_oltp_emul.bat %fbv% %isql_sessions_count%

goto end

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
goto:eof

:trim
    setLocal
    @rem EnableDelayedExpansion
    set Params=%*
    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

:no_vers
    echo Syntax: %~n0.bat ^<firebird_version^> [ ^<number_of_ISQL_sessions^> ]
    echo Where:  ^<firebird_version^> = 25 ^| 30 - mandatory argument
    echo         ^<number_of_ISQL_sessions^> - default = 10.
    echo Press any key. . .
    pause >nul

:end
