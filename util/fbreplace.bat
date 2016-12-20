@echo off

@rem #############################################################################################################
@rem #########    U P G R A D E     F I R E B I R D     I N S A N C E S     F R O M    S N A P S H O T   #########
@rem #############################################################################################################

@rem This batch tries to:
@rem 1. Stop all Firebird services which are specified in the setting variable %FB_SERVICES%.
@rem 2. Remove client libraries (fbclient.ddl) before any further action (exit if this fails),
@rem 3. For each of files from source snapshot folder %SNAPSHOT_DIR%, do:
@rem    3.1. If filename is 'firebird.conf' or 'databases.conf' than create backup of it in the target folder
@rem         (command: copy <name>.conf to <name>.conf.previous) in order to restore it after finish all job;
@rem         After backup will be created - replace <name>.conf with the same file from SNAPSHOT_DIR.
@rem    3.2. All other files - try to remove file with the same name in the <FB_HOME>, log if fault.
@rem    3.2. In case of successfully removed file - copy it from %SNAPSHOT_DIR%
@rem 4. Create SYSDBA/masterke account in each securityN.fdb using gsec utility
@rem 5. Restore firebird.conf and databases.conf in <FB_HOME>: copy <name>.conf.previous <name>.conf
@rem 6. Start all Firebird services.
@rem 7. Obtain server versions via fbsvcmgr and display them.
@rem 8. Check log of its own job for text about failed removals of old files and output it.


setlocal enabledelayedexpansion enableextensions
set fbv=%1
if not .%1.==.25. if not .%1.==.30. if not .%1.==.40. goto no_vers
set log=%2
if %log%==.. ( 
  set log=%~n0.log
  del %log% 2>nul
)

set FB_SERVICES=fb%fbv%_tmp
if .%fbv%.==.25. (
  set url=http://web.firebirdsql.org/download/snapshot_builds/win/2.5/
) else if .%fbv%.==.30. (
  set url=http://web.firebirdsql.org/download/snapshot_builds/win/3.0/
) else if .%fbv%.==.40. (
  set url=http://web.firebirdsql.org/download/snapshot_builds/win/4.0/
)

set lst=%~n0.lst
set tmp=%~dpn0.tmp
set zip=%~n0.fb-snapshot-%fbv%.7z
set pdb=%~n0.fb-snapshot-%fbv%.pdb.7z

set ptn4fbs=_x64.7z
set ptn4pdb=_x64_pdb.7z

(
  echo !time!. Starting batch %~dp0%~nx0 
  echo Check variables:
  echo fbv=!fbv!
  echo url=!url!
  echo lst=!lst!
  echo tmp=!tmp!
  echo zip=!zip!
  echo pdb=!pdb!
  echo ptn4fbs=!ptn4fbs!
  echo ptn4pdb=!ptn4pdb!
) >>%log%

del %lst% 2>nul
del %tmp% 2>nul
del %zip% 2>nul
del %pdb% 2>nul

@rem check that 7-Zip is avaliable:
7za 1>>%tmp% 2>&1

findstr /i /c /b "7-Zip" %tmp% 1>nul 2>&1
if errorlevel 1 (
  del %tmp%
  echo.
  (
     echo 7za.exe - command line stand alone version of 7-Zip archiver - is required for this batch.
     echo Download it from: http://sourceforge.net/projects/sevenzip/files/7-Zip
  ) >>%tmp%
  type %tmp%
  type %tmp% >>%log%
  goto end
)
del %tmp% 2>nul

wget --help 1>%tmp% 2>&1
findstr /i /b /c "GNU Wget" %tmp% 1>nul 2>&1
if errorlevel 1 (
  del %tmp%
  echo.
  echo msg=GNU Wget non-interactive network retriever - is required for this batch. >>%log%
  type %tmp%
  goto end
)


(
  echo ###################################################################
  echo #######  Download DIRECTORY content with Firebird snapshots #######
  echo ###################################################################
) >>%log%

del %lst% 2>nul
@echo on
wget.exe --tries=2 -o %tmp% --output-document=%lst% %url%
@echo off

echo Checking result of downloading and content of directory page.
findstr /c:" 200 OK" %tmp% >nul
if errorlevel 1 (
  echo FAILED to get directory content for %url%: can not find result '200 OK'.
  type %tmp%
  type %tmp% >> %log%
  goto end
) else (
  for /f "tokens=1-3" %%a in ('find /c "Firebird-" %lst%') do (
     echo Number of files related to FB snapshot: %%c
  )
)

set urlbak=%url%

for /f "tokens=4 delims=^>^<" %%a in ('findstr /i /c:"Firebird" %lst% ^| findstr /i /c:"%ptn4fbs%"') do (
  set word=%%a
  call :trim word !word!
  if not .!word!.==.. (
    set url=!url!!word!
    set msg=Firebird snapshot to download URL: !url! 
    echo !msg!
    echo !msg! >>%log%
  )
)

if .%urlbak%.==.!url!. (
  set msg=FAILED to parse node in directory !urlbak! for pattern !ptn4fbs!
  echo !msg!
  echo !msg! >>%log%
  goto end
)

(
  echo ###############################################
  echo #######  Download Firebird .7z-snapshot #######
  echo ###############################################
) >>%log%

@rem Extract last token from full URL and obtain only name+extension of FB snapshot:
echo url=!url!
set snapfile=!url!
echo Extract downloaded snapshot name and extension>>%log%
call :get_snap_file_name !url! snapfile
echo Result: !snapfile!>>%log%

set run_cmd=wget.exe --tries=2 -o %tmp% --output-document=%zip% !url!

echo Download Firebird %fbv% snapshot.
echo !run_cmd!
echo !run_cmd! >> %log%

!run_cmd!

echo Result of downloading FB snapshot:>>%log%
type %tmp% >> %log%

findstr %zip% %tmp% | findstr saved > nul
if errorlevel 1 (
  echo FAILED to download URL: !url! >>%tmp%
  type %tmp%
  type %tmp% >>%log%
  goto end
) else (
  echo Downloaded OK.
)
set url=%urlbak%

dir /-c %zip% | findstr /i /c:%zip% >%tmp%
type %tmp%
type %tmp% >> %log%

(
  dir %zip% | findstr /i /c:%zip%
  @rem Make TEST of downloaded .7z:
  7za t %zip% | findstr /i /c:"Everything is Ok" /c:"Files:" /c:"Size:" /c:"Compressed:"
) >%tmp%

findstr /i /c:"Everything is Ok" %tmp% >nul

if errorlevel 1 (
  echo Downloaded archieve seems to be broken. >>%tmp%
  type %tmp%
  type %tmp% >>%log%
  goto end
) else (
  echo Integrity test passed OK.
)

@rem 18-sep-2016. Save snapshot to be able futher search of regressions:
set snapstore=!tmpdir!\snapshots_archive

@rem 'max_snapshots_to_store' - from config
if "%max_snapshots_to_store%"=="" (
   set /a max_snapshots_to_store=0
)
if not "%max_snapshots_to_store%"=="0" (
  echo Save FB snapshot for possible regression searches.>>%log%
  if not exist !snapstore! md !snapstore! 2>>%log%
  set run_cmd=copy %zip% !snapstore!\!snapfile!
  echo !run_cmd!>>%log%
  !run_cmd! 2>&1 1>>%log%
  dir /-c !snapstore!\!snapfile! | findstr !snapfile! 2>&1 >>%log%

  (
    @echo Remove old snapshots from folder !tmpdir!\snapshots_archive
    @echo Parsing result of 'dir /a-d /o-d !snapstore!' command, remove all lines starting from !max_snapshots_to_store!+1:
    @echo To change number of stored snapshots goto config and update value of 'max_snapshots_to_store' parameter.
  )>>%log%
  set /a i=1
  for /f "tokens=1-4" %%a in ('dir !snapstore! /-c /a-d /o-d ^| findstr /i /c:"firebird"') do (
    if !i! LEQ %max_snapshots_to_store% ( 
      echo !i! of %max_snapshots_to_store% %%d - keep>>%log%
    ) else (
      echo !i! of %max_snapshots_to_store% %%d - remove>>%log%
      echo del !snapstore!\%%d 2>&1 1>>%log%
    )
    set /a i=!i!+1
  )
  if !i! EQU 1 echo Nothing to remove: no items in 'dir /a-d /o-d !snapstore!' result with more than !max_snapshots_to_store! lines.>>%log%
  echo Current content of folder !snapstore!:>>%log%
  dir /-c /a-d /o-d !snapstore! | findstr /i /c:"firebird" >>%log%
) else (
  echo Config parameter 'max_snapshots_to_store' is not defined or equal to zero. Snapshots are not preserved.>>%log%
)

(
  echo #################################################################################################
  echo Download PDB files. One may need to send them together with FB process dump to FB developer team.
  echo NOTE: extracting of these files does not needed.
  echo #################################################################################################
) >>%log%

set urlbak=%url%

for /f "tokens=4 delims=^>^<" %%a in ('findstr /i /c:"Firebird" %lst% ^| findstr /i /c:"%ptn4pdb%"') do (
  set word=%%a
  call :trim word !word!
  if not .!word!.==.. (
    set url=!urlbak!!word!
    set msg=Firebird PDB files download URL: !url! 
    echo !msg!
    echo !msg! >>%log%
  )
)

if .%urlbak%.==.!url!. (
  set msg=FAILED to parse node in directory !urlbak! for pattern !pdb!
  echo !msg! >>%log%
  type %log%
  @rem -- do NOT, it's not critical: goto end
)

set run_cmd=wget.exe --tries=2 -o %tmp% --output-document=%pdb% !url!

echo Download PDB files.
echo !run_cmd!
echo !run_cmd! >> %log%

!run_cmd!

echo Result of downloading PDB files: >>%log%
type %tmp% >> %log%

dir /-c %pdb% | findstr /i /c:%pdb% >%tmp%
type %tmp%
type %tmp% >> %log%

@rem ---------------------  e x t r a c t i n g -----------------------

@rem Folder where downloaded snapshot files will be extracted:
set SNAPSHOT_DIR=%~dp0tmp4snapshot.%fbv%
md %SNAPSHOT_DIR% 2>nul

set msg=!time! Extracting files from %zip% to %SNAPSHOT_DIR%
echo !msg!
echo !msg!>>%log%

set run_cmd=7za x -y -o%SNAPSHOT_DIR% -mmt %zip%

echo !run_cmd!
echo See log in: %log%
echo !run_cmd! >>%log%

!run_cmd! 1>>%tmp% 2>&1

type %tmp% >>%log%
set msg=!time! Done.
echo !msg!
echo !msg!>>%log%

(
  echo ###################################################################
  echo ########  T R Y I N G    T O    S T O P    S E R V I C E  #########
  echo ###################################################################
) >>%log%

for /d %%s in ( %FB_SERVICES% ) do (
  echo %%s
  echo.>>%log%
  sc query FirebirdServer%%s | findstr /i /c:"STOPPED" 1>nul 2>&1
  if errorlevel 1 (

    @rem 22.08.2016. FB service is RUNNING now. We have to obtain its version in order to be sure
    @rem that one may to get it later, after unpacking and replacing FB files:
    @rem --- todo later. ---

    set msg=Stopping service FirebirdServer%%s
    echo !msg!
    echo.>>%log%
    echo !msg!>>%log%
    set cmd_run=sc stop FirebirdServer%%s
    echo !cmd_run!
    echo !cmd_run!>>%log%
    sc stop FirebirdServer%%s 1>>%log% 2>&1
    @echo.
    echo !date! !time! Wait a few seconds. . .
    @echo !date! !time!. Wait a few seconds >>%log%

    ping -n 6 127.0.0.1 1>nul

    :: became broken 10.06.2015 (instant reply instead of wait), the reason not found: ping -n 1 -w 2000 1.1.1.1 1>nul 2>&1
    echo !date! !time! Check that service is really stopped:
    @echo !date! !time! Check that service is really stopped:>>%log%

    set cmd_run=sc query FirebirdServer%%s
    echo !cmd_run!
    echo !cmd_run!>>%log%
    sc query FirebirdServer%%s>>%log%
    sc query FirebirdServer%%s | findstr /i /c:"STOPPED" 1>nul 2>&1
    if errorlevel 1 (
      set msg=CAN NOT STOP SERVICE! Job terminated.
      echo !msg!
      echo !msg!>>%log%
      echo Removing directory tree %SNAPSHOT_DIR% >>%log%
      rd /q /s %SNAPSHOT_DIR%
      echo Removing %zip% >>%log%
      del %zip% 2>&1 1>>%log%
      echo Removing %pdb% >>%log%
      del %pdb% 2>&1 1>>%log%
      exit
    ) else (
      set msg=Service FirebirdServer%%s has been successfully stopped.
      echo !msg!
      echo.>>%log%
      echo !msg!>>%log%
    )
  ) else (
    set msg=Service already has been stopped.
    echo !msg!
    echo !msg!>>%log%
  )
  sc query FirebirdServer%%s>>%log%
)

(
  echo ########################################################################################################
  echo ####################  C R E A T E    T E M P    B A C K U P S   A N D   T R Y  #########################
  echo ####################      T O    D E L E T E    F B C L I E N T . D L L        #########################
  echo ########################################################################################################
) >>%log%

set archsuff=19000101000000
call :getFileDTS gen_vbs
call :getFileDTS get_dts %log% archsuff
call :getFileDTS del_tmp

set failed_to_kill=1

for /d %%i in ( %FB_SERVICES% ) do (
  del %~n0.err 2>nul

  for /f "tokens=3" %%k in ('REG.EXE query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\FirebirdServer%%i ^| findstr /i /c:"ImagePath"') do (
    set fn=%%k
    set fp=%%~dpk

    @rem --- Added 20.12.2016 ---
    @rem Check for processes 'firebird.exe' ('fb_inet_server.exe' for 2.5) that can remain running 
    @rem after finished QA-tests-run daily batch for Classic mode, and kill them (they keep 'fbclient.dll' opened)
    set fb_process=firebird.exe
    if .%fbv%.==.25. (
        set fb_process=fb_inet_server.exe
    )
    set msg="Check for 'orphan' !fb_process! that can remain after last QA test in Classic mode."
    call :sho !msg! %log%

    wmic process where "name='!fb_process!'" get ProcessID, ExecutablePath | more | findstr /i /c:!fp! 2>&1 1>%tmp%
    if not errorlevel 1 (
        for /f "tokens=1-2 delims= " %%a in ('findstr /i /c:!fp! %tmp%') do (
            set msg="Found running FB process, possibly remained after QA tests finish."
            call :sho !msg! %log%

            set msg="%%a, pid=%%b - will try to kill it."
            call :sho !msg! %log%

            set run_cmd=taskkill /pid %%b /t /f
            call :sho "Command: !run_cmd!" %log%
            !run_cmd! 2>&1 1>>%tmp%
        )
        set msg="Result of taskkill:"
        call :sho !msg! %log%
        type %tmp%
        (
            echo ------------------ start of list ---------------
            type %tmp%
            echo ------------------ end of list -----------------
        ) >>%log%

        set msg="Check that no more FB processes from !fp! home are running:"
        call :sho !msg! %log%
        (
            echo ------------------ start of list ---------------
            echo ### NO ROWS SHOULD BE HERE WITH !fb_process! ###
            wmic process where "name='!fb_process!'" get ProcessID, ExecutablePath | more | findstr /i /c:!fp!
            if not errorlevel 1 (
                set failed_to_kill=1
            ) else (
                set failed_to_kill=0
            )
            echo ------------------ end of list -----------------
        ) 2>&1 1>%tmp%
        type %tmp%
        type %tmp%>>%log%
    ) else (
        set msg="No running processes with name !fb_process! from home !fp! detected."
        call :sho !msg! %log%
        set failed_to_kill=0
    )

    if .!failed_to_kill!.==.1. (
        set msg="Could NOT kill 'orphan' !fb_process! that remains after QA test in Classic mode. Batch terminated."
        call :sho !msg! %log%
        exit
    )
    @rem --- 20.12.2016 end of block for killing FB 'orphan' processes which could remain after QA run in Classic mode ---

    if .%fbv%.==.25. (
        @rem E:\FB25.TMPINSTANCE\bin ==> E:\FB25.TMPINSTANCE
        for %%m in ("!fp:~0,-1!") do set fp=%%~dpm
    )
    @rem Remove trailing backslash:
    set fp=!fp:~0,-1!

    set msg=Home dir for %%i: !fp!
    echo ##########################################
    echo !msg!
    echo ##########################################
    echo.
    echo !msg!>>%log%
  )

  set archname=tmp.%~n0.backup.%%i.%archsuff%.7z
  echo Packing previous FB build to !archname!
  @rem '-ep1' =  excluse base path from arch names; '-idp' = do NOT show (and log) percents progress 

  echo !time! Packing previous FB build to !archname!>>%log%
  if .%fbv%.==.25. (
    set cmd_run=7za u -bd -r -ssw -mmt !archname! !fp!\bin !fp!\include !fp!\intl !fp!\lib !fp!\plugins !fp!\*.conf !fp!\firebird.msg !fp!\security*.fdb
  ) else (
    set cmd_run=7za u -bd -r -ssw -mmt !archname! !fp!\include !fp!\intl !fp!\lib !fp!\plugins !fp!\*.conf !fp!\*.dll !fp!\*.exe !fp!\*.bat !fp!\firebird.msg !fp!\security*.fdb
  )
  echo !time! !cmd_run!
  echo !time! !cmd_run!>>%log%
  cmd /c !cmd_run! 1>>%log% 2>&1

  echo Done.
  echo !time! Done.>>%log%
  dir /-c !archname! | findstr /i /c:!archname! 1>%~n0.err 2>&1
  type %~n0.err>>%log%
  type %~n0.err

  if .%fbv%.==.25. (
    set fn=!fp!\bin\fbclient.dll
  ) else (
    set fn=!fp!\fbclient.dll
  )
  if exist !fn! (
    set msg=Trying to delete !fn! - perhaps it can be loaded now by some app.
    echo !msg!
    echo !msg!>>%log%
    del !fn! 2>%~n0.err
    type %~n0.err>>%log%
    for /f "usebackq" %%A in ('%~n0.err') do set errsize=%%~zA
    if .!errsize!.==.. set errsize=0
    if !errsize! gtr 0 (
       echo dir /-c !fn!>>%log%
       dir /-c !fn! | findstr /i /c:fbclient.dll>>%log%
       set msg=File !fn! can not be deleted. Batch terminated.
       echo !msg!
       echo !msg!>>%log%
       del %~n0.err 2>nul
       exit
    )
    set msg=File !fn! has been successfully deleted.
    echo !msg!
    echo !msg!>>%log%
  ) else (
    set msg=Client library !fn! does not exist. Skip trying to delete it.
    echo !msg!
    echo !msg!>>%log%
  )
)
del %~n0.err 2>nul

@rem these files will be removed only after SUCCESSFUL finish of this batch: dir tmp.%~n0.backup.*.rar
:m1

(
  echo #############################################################################################################
  echo #################  C O P Y I N G     A L L    F I L E S    F R O M     S N A P S H O T ######################
  echo #############################################################################################################
) >>%log%

for /d %%i in ( %FB_SERVICES% ) do (

  for /f "tokens=3" %%k in ('REG.EXE query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\FirebirdServer%%i ^| findstr /i /c:"ImagePath"') do (
    @rem Image path of FB service ('drive:\path\firebird.exe'):
    set fn=%%k
    @rem Path to FB instance ('drive:\path\')
    set fp=%%~dpk
    if .%fbv%.==.25. (
        for %%m in ("!fp:~0,-1!") do set fp=%%~dpm
    )
    @rem Remove trailing backslash:
    set fp=!fp:~0,-1!

    echo Copying files from %SNAPSHOT_DIR% to !fp! 

    set cmd_run=copy %pdb% !fp!\*.*
    echo !cmd_run! 1>>%log%
    cmd /c !cmd_run! 1>>%log% 2>&1
    del %pdb% 1>>%log% 2>&1

    for /f %%a in ('dir /s /a-d /b %SNAPSHOT_DIR%') do (
      @rem set fn=%%~da%%~pa%%a
      set sn=%%a
      set sp=%%~da%%~pa

      @rem Replace in full path+filename from SNAPSHOT folder its PATH to the folder of currently processed FB instance:
      @rem set tp=!sn:%SNAPSHOT_DIR%\=%%~dpk!
      set tp=!sn:%SNAPSHOT_DIR%=%fp%!
      set skip=0
      if /i "%%~nxa"=="firebird.conf" set skip=1
      if /i "%%~nxa"=="databases.conf" set skip=1
      if /i "%%~nxa"=="aliases.conf" set skip=1

@rem echo sp=!sp! sn=!sn!
@rem echo tp=!tp!
@rem echo ~~~~~~~~~~~~~~~~~~~~~~~~
@rem echo skip=!skip!
@rem pause

      if .!skip!.==.1. (
        if exist !tp! (
          @rem Before replace firebird.conf and databases.conf we have to backup them.
          @rem After copying all files (and before starting services) these files (`firebird.conf`
          @rem and `databases.conf`) need to be renamed back.

          set cmd_run=copy !tp! !tp!.previous
          
          set msg=### CREATING BACKUP ### %%a
          echo !msg!>>%log%
          echo !time! !cmd_run!>>%log%

          cmd /c !cmd_run! 1>>%log% 2>&1
        )
        set copy_cmd=copy !sn! !tp!
        @rem echo !time! !copy_cmd!
        echo !time! !copy_cmd!>>%log%

        cmd /c !copy_cmd! 1>>%log% 2>&1

      ) else (
        del %~n0.err 2>nul
        if exist !tp! (
          set cmd_del=del !tp!
          echo !time! !cmd_del! 1>>%log%

          cmd /c !cmd_del! 2>%~n0.err
        )
        for /f "usebackq" %%A in ('%~n0.err') do set errsize=%%~zA
        if .!errsize!.==.. set errsize=0
        if !errsize! gtr 0 (
          set msg=### FAILED TO EXECUTE ### !cmd_del! - replacement could be incompleted.
          type %~n0.err>>%log%
          echo !msg!
          echo !msg!>>%log%
        ) else (
          set copy_cmd=copy !sn! !tp!
          @rem echo !time! !copy_cmd!
          echo !time! !copy_cmd!>>%log%
          cmd /c !copy_cmd! 1>>%log% 2>&1
        )
      )
    )
  )
)
del %~n0.tmp.vbs 2>nul

(
  echo #############################################################################################################
  echo #############################   C R E A T I N G    S Y S D B A    A C C O U N T  ############################
  echo #############################                        a n d                       ############################
  echo #############################   R E S T O R I N G     .c o n f    F I L E S      ############################
  echo #############################################################################################################
) >>%log%

@rem echo create database '/:E:\FB30.TMPINSTANCE\test.fdb' user sysdba password 'masterkey'; | ./isql -z

for /d %%s in ( %FB_SERVICES% ) do (
  for /f "tokens=3" %%k in ('REG.EXE query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\FirebirdServer%%s ^| findstr /i /c:"ImagePath"') do (
    set fn=%%k
    set fp=%%~dpk
    if .%fbv%.==.25. (
        for %%m in ("!fp:~0,-1!") do set fp=%%~dpm
    )
    set fp=!fp:~0,-1!

    if NOT .%fbv%.==.25. (
        set secsuff=!fbv:~0,1!
        set secname=security!secsuff!.fdb
        set cmd_run=!fp!\gsec -user sysdba -pass 1 -add sysdba -pw masterke -database !fp!\!secname!
        @rem set cmd_run=echo create user SYSDBA password 'masterkey'; show users; set list on; select * from sec$users; | isql -user sysdba .\security3.fdb
        echo !time! Trying to add SYSDBA into security database: !cmd_run!
        echo !cmd_run!

        echo !cmd_run!>>%log%

        echo !time! Check record: point BEFORE using gsec for add SYSDBA, instance: %%s>>%log%
        cmd /c !cmd_run! 1>%~n0.tmp  2>%~n0.err
        echo !time! Check record: point AFTER using gsec for add SYSDBA, instance: %%s>>%log%

        for /f "usebackq" %%A in ('%~n0.err') do set errsize=%%~zA
        if .!errsize!.==.. set errsize=0
        if !errsize! gtr 0 (
          set msg=### FAILED TO EXECUTE ### !cmd_run!.
          echo !msg!
          echo !msg!>>%log%
          type %~n0.err
          type %~n0.err>>%log%
        )
        type %~n0.tmp
        type %~n0.tmp>>%log%
        del %~n0.err 2>nul
        del %~n0.tmp 2>nul

        set cmd_run=!fp!\gsec -display -database !fp!\!secname! -user sysdba -pass masterke
        echo !time! Trying to display SYSDBA info:
        echo !cmd_run!
        echo !cmd_run!>>%log%
        
        echo !time! Check record: point BEFORE using gsec for display SYSDBA, instance: %%s>>%log%
        cmd /c !cmd_run! 1>%~n0.tmp 2>%~n0.err
        echo !time! Check record: point AFTER using gsec for display SYSDBA, instance: %%s>>%log%

        for /f "usebackq" %%A in ('%~n0.err') do set errsize=%%~zA
        if .!errsize!.==.. set errsize=0
        if !errsize! gtr 0 (
          set msg=### FAILED TO EXECUTE ### !cmd_run!.
          echo !msg!
          echo !msg!>>%log%
          type %~n0.err
          type %~n0.err>>%log%
        )

        type %~n0.tmp
        type %~n0.tmp>>%log%
        del %~n0.err 2>nul
        del %~n0.tmp 2>nul
    )
    @rem end of "if fbv NOT == 25"

    set msg=Restore files that was backed up before copying:
    echo !msg!
    echo !msg!>>%log%

    set cmd_run=copy !fp!\firebird.conf.previous !fp!\firebird.conf
    echo !time! !cmd_run!>>%log%
    cmd /c !cmd_run! 1>>%log%

    set cmd_run=copy !fp!\databases.conf.previous !fp!\databases.conf
    echo !time! !cmd_run!>>%log%
    cmd /c !cmd_run! 1>>%log%
  )
)

(
  echo #############################################################################################################
  echo ################################   S T A R T I N G     S E R V I C E S    ###################################
  echo #############################################################################################################
) >>%log%

for /d %%s in ( %FB_SERVICES% ) do (
  set msg=Starting service FirebirdServer%%s
  echo !msg!
  echo.>>%log%
  echo !msg!>>%log%
  
  echo !time! Check record: point BEFORE starting instance: %%s>>%log%
  
  sc start FirebirdServer%%s 1>>%log% 2>&1

  echo !time! Check record: point AFTER starting  instance: %%s>>%log%

  ping -n 1 -w 800 1.1.1.1 1>nul 2>&1
  echo After pause:>>%log%

  sc query FirebirdServer%%s 1>>%log% 2>&1
  sc query FirebirdServer%%s | findstr /i /c:"RUNNING" 1>nul 2>&1
  if errorlevel 1 (
    set msg=### FAILED TO EXECUTE ### start service command.
  ) else (
    set msg=Service has been successfully started.
  )
  echo !msg!
  echo !msg!>>%log%

)

(
  echo #############################################################################################################
  echo ###########################   O B T A I N    S E R V E R    V E R S I O N S   ###############################
  echo #############################################################################################################
) >>%log%

for /d %%s in ( %FB_SERVICES% ) do (
  for /f "tokens=3" %%k in ('REG.EXE query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\FirebirdServer%%s ^| findstr /i /c:"ImagePath"') do (
    set fn=%%k
    set fp=%%~dpk
    set fp=!fp:~0,-1!

    set cmd_run=!fp!\fbsvcmgr localhost/%port%:service_mgr user SYSDBA password masterke info_server_version
    set msg=Trying to obtain server version for service %%s
    echo !msg!
    echo !msg!>>%log%
    echo !cmd_run!>>%log%

    echo !time! Check record: point BEFORE get server version, instance: %%s>>%log%
    cmd /c !cmd_run! 1>%~n0.tmp 2>%~n0.err
    echo !time! Check record: point AFTER get server version, instance: %%s>>%log%

    for /f "usebackq" %%A in ('%~n0.err') do set errsize=%%~zA
    if .!errsize!.==.. set errsize=0
    if !errsize! gtr 0 (
      set msg=### FAILED TO EXECUTE ### !cmd_run!.
      echo !msg!
      echo !msg!>>%log%
      type %~n0.err
      type %~n0.err>>%log%
    )
    type %~n0.tmp
    echo.>>%log%
    type %~n0.tmp>>%log%
    echo.>>%log%

    if .%fbv%.==.25. (
        set fp=%%~dpk
        for %%m in ("!fp:~0,-1!") do set fp=%%~dpm
        set fp=!fp:~0,-1!
    )

    (
      echo This FB instance has been downloaded from:
      echo !url!
      echo Replacement was done by %~nf0 at !date! !time!
      type %~n0.tmp 
    ) > !fp!\firebird.log

    del %~n0.err 2>nul
    del %~n0.tmp 2>nul
  )
)

findstr /i /c:"FAILED TO EXECUTE" %log% 1>%~n0.err 2>nul
if errorlevel 1 (
  echo.
  echo No faults occured during replacement files.
  @echo Now we can remove temp files.

  set cmd_del=del !archname!
  echo !time! !cmd_del! 1>>%log%
  cmd /c !cmd_del! 1>>%log% 2>&1

  set cmd_del=del %zip%
  echo !time! !cmd_del! 1>>%log%
  cmd /c !cmd_del! 1>>%log% 2>&1

  set cmd_del=rd /s /q %SNAPSHOT_DIR%
  echo !time! !cmd_del! 1>>%log% 2>&1
  cmd /c !cmd_del! 1>>%log% 2>&1

) else (
  (
    echo.
    echo ::: ACHTUNG :::
    echo.
    echo At least one error occured, replacement is INCOMPLETE. 
    echo You can restore previous FB instances from backups:

    dir /-c tmp.%~n0.backup.*.7z | findstr /c:".7z"

    echo FAILED commands:
    type %~n0.err
  ) > %tmp%
  type %tmp%
  type %tmp% >>%log%
  exit
)
del %~n0.err 2>nul
del %lst% 2>nul
del %tmp% 2>nul

echo.
echo Check log in the file: %log%
echo.
goto end

:get_snap_file_name
    setlocal
    set result=%~nx1
    set result=!result: =*!
    set result=!result:"=|!
    endlocal&set "%~2=%result%"
goto:eof


:getFileDTS
  @rem http://www.dostips.com/DtTutoFunctions.php
    set vbs=%~n0.tmp.vbs
    set dts=%~n0.tmp.log
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
      @rem echo|set /p=Obtaining timestamp of %2... 
      cscript //nologo %vbs% %2 1>%dts%
      @rem type %dts%
      set /p %~3=<%dts%
      del %dts% 2>nul
    )
    if /i .%1.==.del_tmp. (
      del %vbs% 2>nul
    )
  endlocal
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

:no_vers
    echo Syntax: %~n0.bat ^<firebird_version^>
    echo Where:  ^<firebird_version^> = 25 ^| 30
    echo Press any key. . .
    pause >nul
:end
