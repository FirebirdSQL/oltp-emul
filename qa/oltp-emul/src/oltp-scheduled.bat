@echo off
setlocal enabledelayedexpansion enableextensions
cd /d %~dp0

set fbv=%1
if not .%1.==.25. if not .%1.==.30. if not .%1.==.40. goto no_vers
set isql_sessions_count=%2
if not defined isql_sessions_count set isql_sessions_count=10

@rem 06.02.2016: 'nostop' etc:
set addi_args=%3

::::::::::::::::::::::::::::::::
:::: R E A D    C O N G I G ::::
::::::::::::::::::::::::::::::::
set err_setenv=0
call :readcfg oltp%fbv%_config.win !err_setenv!

set msg=Result of parsing config: err_setenv=!err_setenv!
set log=%tmpdir%\%~n0.log
set tmp=%tmpdir%\%~n0.tmp
del %log% 2>nul
del %tmp% 2>nul

call :sho "!msg!" !log!

if .%replace_instance%.==.1. (
    cd ..\util

    @rem ###############################################
    @rem ###                                         ###
    @rem ###   D O W N L O A D   &   R E P L A C E   ###
    @rem ###                                         ###
    @rem ###############################################

    call fbreplace.bat %fbv% %log%

    cd /d %~dp0

    set FB_SERVICES=fb%fbv%_tmp

    for /d %%s in ( %FB_SERVICES% ) do (
      echo %%s
      echo.>>%log%
      sc query FirebirdServer%%s | findstr /i /c:"STOPPED" 1>nul 2>&1
      if errorlevel 1 (
        set msg=Stopping service FirebirdServer%%s
        call :sho "!msg!" !log!

        set cmd_run=sc stop FirebirdServer%%s
        call :sho "!cmd_run!" !log!

        @rem sc stop FirebirdServer%%s 1>>%log% 2>&1
        cmd /c !cmd_run! 1>>%log% 2>&1

        set msg=Wait a few seconds
        call :sho "!msg!" !log!

        ping -n 6 127.0.0.1 1>nul

        :: became broken 10.06.2015 (instant reply instead of wait), the reason not found: ping -n 1 -w 2000 1.1.1.1 1>nul 2>&1
        set msg=Check that service is really stopped
        call :sho "!msg!" !log!

        set cmd_run=sc query FirebirdServer%%s
        call :sho "!cmd_run!" !log!

        @rem sc query FirebirdServer%%s>>%log%
        @rem sc query FirebirdServer%%s | findstr /i /c:"STOPPED" 1>nul 2>&1

        cmd /c !cmd_run! 1>>%log% 2>&1
        cmd /c !cmd_run! | findstr /i /c:"STOPPED" 1>nul 2>&1
        if errorlevel 1 (
            set msg=CAN NOT STOP SERVICE. Job terminated.
            call :sho "!msg!" !log!
            goto final
        ) else (
            set msg=SUCCESS: service FirebirdServer%%s has been stopped.
            call :sho "!msg!" !log!
        )
      ) else (
          set msg=Service already has been stopped.
          call :sho "!msg!" !log!
      )
      sc query FirebirdServer%%s 1>>%log% 2>&1
    )

) else (
    set msg=SKIP replacement of FB instance - see config parameter 'replace_instance'
    call :sho "!msg!" !log!
)

@rem -------------------------------------

del !dbnm! 2>nul
if exist !dbnm! (
  set msg="Can NOT delete file !dbnm! which is to be copy of etalon DB. Job terminated."
  call :sho "!msg!" !log!
  goto final
)

set msg=Start copy from etalon test database.
call :sho "!msg!" !log!

set cmd_run=copy /v /y /b !etalon_dbnm! !dbnm!
call :sho "!cmd_run!" !log!
cmd /c !cmd_run! 1>>%log% 2>&1

set msg=Finish copy from etalon test database.
call :sho "!msg!" !log!

for /f "usebackq" %%a in ('!dbnm!') do (
  echo Name of copy: %%~nxa, size of copy: %%~za 1>>%log%
)

if .%replace_instance%.==.1. (

    @rem -------------------------------------

    for /d %%s in ( %FB_SERVICES% ) do (

      set cmd_run=sc query FirebirdServer%%s
      call :sho "!cmd_run!" !log!
      cmd /c !cmd_run! 1>>%log% 2>&1
      cmd /c !cmd_run! | findstr /i /c:"RUNNING" 1>nul 2>&1
      if errorlevel 1 (

          set msg=Starting service FirebirdServer%%s
          call :sho "!msg!" !log!
          
          set cmd_run=sc start FirebirdServer%%s 
          call :sho "!cmd_run!" !log!

          cmd /c !cmd_run! 1>>%log% 2>&1

          set msg=Check point AFTER starting FirebirdServer%%s
          call :sho "!msg!" !log!

          set msg=Make small delay while  command 'sc start' is launched.
          call :sho "!msg!" !log!
          
          ping -n 1 -w 800 1.1.1.1 1>nul 2>&1

          set msg=Check state of service after delay:
          call :sho "!msg!" !log!

          set cmd_run=sc query FirebirdServer%%s
          call :sho "!cmd_run!" !log!
          cmd /c !cmd_run! 1>>%log% 2>&1
          cmd /c !cmd_run! | findstr /i /c:"RUNNING" 1>nul 2>&1
          if errorlevel 1 (
            set msg=### FAILED TO START SERVICE ###. Job terminated.
            call :sho "!msg!" !log!
            goto final
          ) else (
            set msg=SUCCESS. Service has been started.
            call :sho "!msg!" !log!
          )
       ) else (
           set msg=Service FirebirdServer%%s already is RUNNING. Starting command can be SKIPPED.
           call :sho "!msg!" !log!
       )
    )

) else (
    set msg=SKIP stop and starting FB instance - see config parameter 'replace_instance'
    call :sho "!msg!" !log!
)

if NOT .%fbv%.==.25. (
    set msg=Applying 'gfix -icu' for adjust database with existing ICU version.
    call :sho "!msg!" !log!

    set cmd_run=%fbc%\gfix.exe -icu %host%/%port%:%dbnm% -user %usr% -password %pwd%
    call :sho "!cmd_run!" !log!

    cmd /c !cmd_run! 1>>%log% 2>&1

    set msg=Done.
    call :sho "!msg!" !log!
)

(
  echo !date! !time!. Make probe connect to database and show FB version, DB and test settings...
  echo Check command: echo ... ^| %fbc%\isql %host%/%port%:%dbnm% -user %usr% -password %pwd%
  echo show version; show database; set width setting_name 40; set width setting_value 20; select setting_name, setting_value from Z_CURRENT_TEST_SETTINGS; | %fbc%\isql %host%/%port%:%dbnm% -user %usr% -password %pwd%
  echo !date! !time!. Done. Now we can launch 1run_oltp_emul.bat
) 1>>%log% 2>&1

(
  echo ###############################################
  echo ###                                         ###
  echo ###   r u n n i n g     o l t p - e m u l   ###
  echo ###                                         ###
  echo ###############################################
) >>%log%

E:\OLTP-EMUL\src\1run_oltp_emul.bat %fbv% %isql_sessions_count% %addi_args%

goto final

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

:trim
    setLocal
    @rem EnableDelayedExpansion
    set Params=%*
    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

:sho
    setlocal
    set msg=%1
    set log=%2
    set tmp=!%1:"=!
    set result=0
    if not "!tmp!"=="!tmp: =!" set result=1
    if .!result!.==.1. set msg=!msg:"=!
    set txt=!date! !time! !msg!
    @echo !txt!
    @echo !txt!>>%log%
endlocal & goto:eof

:haltHelper
()
exit /b

:no_vers
    echo Syntax: %~n0.bat ^<firebird_version^> [ ^<number_of_ISQL_sessions^> ]
    echo Where:  ^<firebird_version^> = 25 ^| 30 ^| 40 - mandatory argument
    echo         ^<number_of_ISQL_sessions^> - default = 10.
    echo Press any key. . .
    pause >nul

:final
    call :haltHelper 2> nul
