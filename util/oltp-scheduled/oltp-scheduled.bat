@echo off
setlocal enabledelayedexpansion enableextensions

set THIS_DIR=%~dp0
set THIS_DIR=!THIS_DIR:~0,-1!

@rem Get parent and grand-parent directories relating to current one:
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

set abendlog=%~n0.abend-log.tmp
if .%TEMP%.==.. (
    set abendlog=%TEMP%\!abendlog!
) else (
    if exist c:\temp\nul (
        set abendlog=c:\temp\!abendlog!
    ) else (
        set abendlog=!THIS_DIR!\!abendlog!
    )
)
del !abendlog! 2>nul
echo abendlog=!abendlog!


if not .%1.==.25. if not .%1.==.30. if not .%1.==.40. (
    call :show_syntax !abendlog!
)

if .%2.==.. (
    call :show_syntax !abendlog!
) else (
    if %2 LEQ 0 (
        call :show_syntax !abendlog!
    )
)

if /i not .%3.==.ss. if /i not .%3.==.sc. if /i not .%3.==.cs. (
    call :show_syntax !abendlog!
)

if not .%1.==.. set /a fb_major=%1
if not .%2.==.. set /a sess_cnt=%2
if not .%3.==.. set fb_mode=%3

if not .%4.==.. (
    if not .%4.==.0. if not .%4.==.1. (
        call :show_syntax !abendlog!
    )
    set /a upd_fb=%4
) else (
    @rem DEFAULT: we DO UPGRADE of FB instance now.
    set /a upd_fb=1
)


set isc_user=
set isc_password=

set err_setenv=0

set cfg=%~dpn0_config.win

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::: R E A D     O L T P - S C H E D U L E D    C O N G I G ::::
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
echo Parsing config file ^>%cfg%^<. Please wait. . .
call :readcfg %cfg% err_setenv
if .%err_setenv%.==.1. (
    call :no_env !abendlog! !cfg!
)

@rem OLTP_ROOT_DIR - from .conf fir this script; can be specified as relative path: ..\..
set OLTP_SRC_DIR=!OLTP_ROOT_DIR!\src

set oemul_cfg=!OLTP_SRC_DIR!\oltp!fb_major!_config.win
echo Parsing config file ^>!oemul_cfg!^<. Please wait. . .

:::::::::::::::::::::::::::::::::::::::::::::::::::::::
:::: R E A D     O L T P - E M U L     C O N G I G ::::
:::::::::::::::::::::::::::::::::::::::::::::::::::::::
call :readcfg !oemul_cfg! err_setenv
if .%err_setenv%.==.1. (
    call :no_env !abendlog! !oemul_cfg!
)

if not exist %tmpdir% md %tmpdir% 2>nul

if not exist %tmpdir%\nul (
    call :noaccess !abendlog!
) else (
    dir 1>nul 2>!tmpdir!\tmp_check_access.txt
    if errorlevel 1 (
        call :noaccess !abendlog!
    )
    del !tmpdir!\tmp_check_access.txt
    if errorlevel 1 (
        call :noaccess !abendlog!
    )
)
 
set joblog=!tmpdir!\%~n0.log
set tmplog=!tmpdir!\%~n0.tmp
set tmperr=!tmpdir!\%~n0.err
set tmpsql=!tmpdir!\%~n0.sql
set tmplst=!tmpdir!\%~n0.lst
set tmpvbs=!LOGDIR!\%~n0.extract-from-zip.tmp.vbs

for /d %%x in (!joblog!,!tmplog!,!tmperr!) do (
    del %%x 2>nul
)

call :sho "Result of parsing config: err_setenv=!err_setenv!" !joblog!
if exist !abendlog! type !abendlog! >> !joblog!


%systemroot%\system32\cscript.exe 1>!tmplog! 2>&1
findstr /i /c:"Windows Script Host" !tmplog! >nul
if errorlevel 1 (
    (
        echo Windows Script executive is unavaliable.
        echo Check access rights to %systemroot%\system32\cscript.exe
    )>!tmplog!
    call :bulksho !tmplog! !joblog!

    goto final
)

@rem Replace relative path to decompress binaries with absolute one:
set COMPRESS_7Z=!COMPRESS_7Z:..\..=%GRANDPDIR%!
set COMPRESS_7Z=!COMPRESS_7Z:..=%PARENTDIR%!

if not exist !COMPRESS_7Z! (
    call :sho "Parameter 'COMPRESS_7Z' points to missed file: !COMPRESS_7Z!" !joblog!
    call :final
)


@rem Generate temporary .vbs script in !TMPDIR! for extracting binary 7z.exe
@rem from ..\compressors\7z.exe.zip
@rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

(
    echo ' Original text:
    echo ' https://social.technet.microsoft.com/Forums/en-US/8df8cbfc-fe5d-4285-8a7a-c1fb201656c8/automatic-unzip-files-using-a-script?forum=ITCG
    echo ' Examples:
    echo '     %systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !COMPRESS_7Z! !tmpdir!

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

set run_cmd=%systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !COMPRESS_7Z! !tmpdir!
call :sho "Extract compressor from COMPRESS_7Z=!COMPRESS_7Z! to !tmpdir!. Command" !joblog!
call :sho "!run_cmd!" !joblog!
cmd /c !run_cmd! 1>!tmperr! 2>&1

@rem ####################################
@rem ::: NB ::: 12.11.2020
@rem cscript returns errorlevel = 0 even when some error occured.
@rem We have to check SIZE of STDERR log!
@rem ####################################
for /f "usebackq tokens=*" %%a in ('!tmperr!') do (
    set err_size=%%~za
)
if .!err_size!.==.. set err_size=0
if !err_size! GTR 0 (
    call :sho "Extraction FAILED. Check log:" !joblog!
    type !tmperr!
    type !tmperr!>>!joblog!

    goto final

)

call :sho "Completed." !joblog!


@rem Adjust path and name of utilities for make decompression:
@rem =========================================================
for /f %%a in ("!COMPRESS_7Z!") do (
    set COMPRESS_7Z=!tmpdir!\%%~na
)

@rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

set CURL_ZIP=!CURL_ZIP:..\..=%GRANDPDIR%!
set CURL_ZIP=!CURL_ZIP:..=%PARENTDIR%!

if not exist !CURL_ZIP! (
    call :sho "Parameter 'CURL_ZIP' points to missed file: !CURL_ZIP!" !joblog!
    call :final
)

set run_cmd=%systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !CURL_ZIP! !tmpdir!
call :sho "Extract compressor from CURL_ZIP=!CURL_ZIP! to !tmpdir!. Command" !joblog!
call :sho "!run_cmd!" !joblog!
cmd /c !run_cmd! 1>!tmperr! 2>&1
if errorlevel 1 (
    call :sho "Extracting FAILED. Check !tmperr!:" !joblog!
    type !tmperr!
    type !tmperr!>>!joblog!
)
call :sho "Completed." !joblog!


@rem Adjust path and name of utilities for make decompression:
@rem =========================================================
for /f %%a in ("!CURL_ZIP!") do (
    set curl_cmd=!tmpdir!\%%~na
)


@rem #########################################################
@rem Check whether standard Windows console utility 
@rem 'certutil.exe' if avaliable (must be so since Windows 7).
@rem #########################################################
set /a base64_avail=0
%systemroot%\system32\certutil.exe -? | findstr /i /c:"base64" 1>!tmplog! 2>&1
if NOT errorlevel 1 (
    call :sho "Found utility 'certutil.exe' - will be used to encode e-mail attachments to base64 format." !joblog!
    set /a base64_avail=1
) else (
    call :sho "CLI utility 'certutil.exe' is unavaliable e-mail attachments will not created." !joblog!
)

set fb_config_prototype=!THIS_DIR!\oltp-scheduled-fb!fb_major!.conf.!fb_mode!


if not exist !fb_config_prototype! (
    call :sho "Prototype for config: '!fb_config_prototype!' - NOT EXISTS in the '!THIS_DIR!\'" !joblog!
    goto final
) else (
    findstr /i /c:"FileSystemCacheThreshold" !fb_config_prototype! > nul
    if NOT errorlevel 1 (
        (
            echo Prototype for firebird.conf FOUND and contains parameter 'FileSystemCacheThreshold'
            findstr /i /c:"FileSystemCacheThreshold" !fb_config_prototype!
            echo NOTE: value of this parameter must always be greater than page cache
            echo defined for test database: '!dbnm!'
            if .!fb_major!.==.25. (
                echo Defined size of page cache:
                findstr /i /c:"DefaultDbCachePages" !fb_config_prototype! 2>&1
            ) else (
                echo Size of page cache can be adjusted in databases.conf, check it yourself.
            )
        ) > !tmplog!
        call :bulksho !tmplog! !joblog!

    ) else (
        (
            echo Prototype has no explicitly specified parameter 'FileSystemCacheThreshold'. 
            echo It always must be greater than size of page cache defined for '!dbnm!'
        ) > !tmplog!
        call :bulksho !tmplog! !joblog!
        goto final
    )
)

@rem -------------------------------------------------------------------------------------------------------------

@rem See also: https://www.raymond.cc/blog/disable-program-has-stopped-working-error-dialog-in-windows-server-2008/
set WER_HOME=HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting

call :sho "Check presence of !WER_HOME! key and its content." !joblog!

set disabled_gui_on_error=WER_KEY_ABSENT
REG.EXE query "!WER_HOME!" 1>!tmplog! 2>!tmperr!
set elevel=!errorlevel!
if !elevel! EQU 0 (
    set disabled_gui_on_error=MUST_DISABLE_SHOW_UI
    for /f "tokens=1-3" %%a in ('findstr /i /c:"DontShowUI" !tmplog!') do (
        if .%%a.==.DontShowUI. (
            if .%%b.==.REG_DWORD. (
                if .%%c.==.0x1. (
                    set disabled_gui_on_error=%%c
                )
            )
        )
    )
)

if .!disabled_gui_on_error!.==.MUST_DISABLE_SHOW_UI. (
    (
        echo WER settings on this machine does not prevent from pop-up window dialog
        echo which will ask for close/debug program in case of its crash.
        echo This is not suitable for working in batch mode so it must be DISABLED.
        echo To do this, open Windows registry and
        echo 1. Go to  HKLM\SOFTWARE\Microsoft\Windows\Windows Error Reporting
        echo 2. Add (if needed^) there parameter with name: DontShowUI
        echo 2. Set its type to DWORD
        echo 3. Assign this parameter to 1.
        echo.
        echo Currently this registry key contains following:
        echo ---------
        REG.EXE query "!WER_HOME!" 
        echo ---------
    ) 1>!tmplog! 2>&1
    call :bulksho !tmplog! !joblog!
    call :final
) else (
    if .!disabled_gui_on_error!.==.0x1. (
        call :sho "WER key in registry contains proper value for 'DontShowUI' parameter: !disabled_gui_on_error!" !joblog!
    ) else (
        call :sho "Parameter for disabling pop-up windows on crash is: disabled_gui_on_error=!disabled_gui_on_error!" !joblog!
    )
)

@rem -------------------------------------------------------------------------------------------------------------

@rem Check that value of !etalon_dbnm! is defined.
@rem Get attributes of its header: whether it is in shutdown or readonly mode.
set etalon_shutdown=0
set etalon_readonly=0
if .!etalon_dbnm!.==.. (
    call :sho "Parameter 'etalon_dbnm' must be DEFINED in !oemul_cfg! and point to existing .fdb file" !joblog!
    goto final
)

if exist !fbc!\gstat.exe (
    !fbc!\gstat.exe -h !etalon_dbnm! 1>!tmplog! 2>&1
    if errorlevel 1 (
        call :sho "Could not get DB header for 'etalon_dbnm' = !etalon_dbnm!" !joblog!
        call :bulksho !tmplog! !joblog!
        goto final
    )
    findstr /r /i /c:"attributes.* read[ ]*only" !tmplog! >nul
    if NOT errorlevel 1 (
        set etalon_readonly=1
        call :sho "Etalone database: !etalon_dbnm! - is in read_only mode." !joblog!
    )
    findstr /r /i /c:"attributes.* shutdown" !tmplog! >nul
    if NOT errorlevel 1 (
        set etalon_shutdown=1
        call :sho "Etalone database: !etalon_dbnm! - has shutdown state." !joblog!
    )
    if .!etalon_shutdown!.==.0. if .!etalon_shutdown!.==.0. (
        call :sho "Etalone database: !etalon_dbnm! - has normal state and read_write mode." !joblog!
    )

) else (
    call :sho "Could not find !fbc!\gstat utility. Check parameter 'fbc' in '!oemul_cfg!'"
    goto final
)


for /f %%a in ("!fbc!\") do (
    set fbc=%%~dpna
    set fbc=!fbc:\\=\!
    set fbc=!fbc:~0,-1!
)

if .!fb_major!.==.25. (
    @rem FB will be installed to the PARENT folder relatively !fbc!
    for /f "tokens=*" %%a in ("!fbc!") do (
        set dir_to_install=%%~dpa
        set dir_to_install=!dir_to_install:~0,-1!
    )
) else (
    @rem FB will be installed in the folder defined by !fbc!
    set dir_to_install=!fbc!
)
call :sho "Firebird will be installed/upgraded in the folder: ^>!dir_to_install!^<" !joblog!

@rem -------------------------------------------------------------------------------------------------------------

call :kill_fb_processes !joblog! "!FBAPPS!" !fbc! !port!

@rem -------------------------------------------------------------------------------------------------------------

call :sho "Start parsing prototype of firebird.conf and change its RemoteServicePort and BugCheckAbort parameters." !joblog!

set fb_cfg_for_work=!tmpdir!\fb_config.conf
del !fb_cfg_for_work! 2>nul

for /f "tokens=*" %%a in ('findstr /r /c:"^^[^^#;]" !fb_config_prototype!') do (
    set line=%%a
    @rem Following parameters will be added separately:
    @rem ===============================================
    @rem ServerMode
    @rem BugCheckAbort
    @rem RemoteServicePort
    @rem UdfAccess
    @rem ===============================================
    echo !line! | findstr /i /c:"ServerMode" /c:"BugCheckAbort" /c:"RemoteServicePort" /c:"UdfAccess" >nul
    if errorlevel 1 (
        echo !line!>>!fb_cfg_for_work!
    )
)

(
	echo.
	echo # Following parameters were adjusted !date! !time! by
	echo # %~f0 
	echo # ############################################################
	echo #
	if not .!fb_major!.==.25. (
        echo # Servermode was changed accorting to value of input argument 'fb_mode'=!fb_mode!:
        if /i .!fb_mode!.==.SS. (
            echo ServerMode=Super
        ) else if /i .!fb_mode!.==.SC. (
            echo ServerMode=SuperClassic
        ) else if /i .!fb_mode!.==.CS. (
            echo ServerMode=Classic
        )
        echo.
	)
	echo # RemoteServicePort is adjusted to the value of parameter 'port'
	echo # from oltp-emul config file '!oemul_cfg!':
	echo RemoteServicePort=!port!
	echo.
	echo # BugCheckAbort must be set always to 1 in order to stop test
	echo # when both crash and expected internal FB error occurs.
	echo BugCheckAbort=1
) >>!fb_cfg_for_work!


if not .!sleep_ddl!.==.. ( 
    echo.
	echo # Adjusted by %~f0 at !date! !time!
	echo # Added because current settings of OLTP-EMUL require 'sleep-UDF' for delays.
	echo # Details see in '!oemul_cfg!', parameter: 'sleep_ddl'
	echo UdfAccess = Restrict UDF
) >>!fb_cfg_for_work!

if not .!fb_major!.==.25. (
    findstr /r /c:"^[^#;]" !fb_config_prototype! | findstr /i /c:"UserManager" >!tmplog!
    findstr /i /c:"Srp" !tmplog! >nul
    if NOT errorlevel 1 (
        set sec_plugin=Srp
    ) else (
        findstr /i /c:"Legacy_UserManager" !tmplog! >nul
        if NOT errorlevel 1 (
            set sec_plugin=Legacy_UserManager
        ) else (
            set sec_plugin=Srp
        )
    )
)

call :sho "Completed. File FB '!fb_cfg_for_work!' will be used for further test launch." !joblog!

set previous_fb_snapshot=0
set actual_fb_snapshot=0

if .!upd_fb!.==.1. (
    @rem Firebird Services Manager version WI-V3.0.7.33372 Firebird 3.0
    @rem Firebird services manager version WI-V2.5.9.27150 Firebird 2.5

    if exist !fbc!\fbsvcmgr.exe (
        for /f "tokens=5" %%a in ('!fbc!\fbsvcmgr -z') do (
            set fb_vers=%%a
        )

        @rem fb_vers: WI-V3.0.7.33372 etc
        for /f "tokens=4 delims=." %%i in ("!fb_vers!") do (
            set previous_fb_snapshot=%%i
        )
    )

    set fb_snapshots_root=!FB_SNAPSHOTS_URL!
    if .!fb_major!.==.25. (
        set fb_major_vers_url=!fb_snapshots_root!/2.5
    ) else if .!fb_major!.==.30. (
        set fb_major_vers_url=!fb_snapshots_root!/3.0
    ) else if .!fb_major!.==.40. (
        set fb_major_vers_url=!fb_snapshots_root!/4.0
    ) else (
        call :sho "Invalid/unsupported FB major version passed. Can not defined URL for downloading FB snapshot." !joblog!
        goto final
    )
    set run_cmd=!curl_cmd! -L -v -trace !PROXY_DATA! !fb_major_vers_url!
    call :sho "Obtaining list of files. Command: !run_cmd!" !joblog!

    @rem ################################
    @rem curl: download list of snapshots
    @rem ################################
    cmd /c !run_cmd! 1>!tmplst! 2>!tmperr!
    findstr /r /i /c:"http.* 200[ ]*OK" !tmperr! >nul
    if errorlevel 1 (
        call :sho "Could not download list of files for parsing. Check error log" !joblog!
        type !tmperr!
        type !tmperr!>>!joblog!

        goto final
    ) 

    for /f "usebackq tokens=*" %%a in ('!tmplst!') do (
        set size=%%~za
    )
    if .!size!.==.. set size=0
    call :sho "Success. Size of downloaded list !tmplst!: !size!. Strings to be parsed:" !joblog!

    echo findstr /i /r /c:"a href=.*!FB_SNAPSHOT_SUFFIX!" !tmplst! >> !joblog!

    findstr  /i /r /c:"a href=.*!FB_SNAPSHOT_SUFFIX!" !tmplst! >!tmplog!
    type !tmplog!
    type !tmplog!>>!joblog!
    @rem     <td nowrap class=content><a href='./Firebird-3.0.7.33380-0_x64.7z'>Firebird-3.0.7.33380-0_x64.7z</a></td>

    for /f "tokens=2 delims='" %%a in (!tmplog!) do (
        if .!actual_fb_snapshot!.==.0. (
            @rem ./Firebird-3.0.7.33380-0_x64.7z
            set href_file=%%a

            echo Parsed href_file: !href_file!>!tmplog!
            type !tmplog!
            type !tmplog!>>!joblog!

            for /f %%b in ("!href_file!") do (
                @rem Firebird-3.0.7.33380-0_x64.7z -- i.e. name of compressed .7z, without "./" prefix
                set fb_build_file=%%~nxb
                for /f "tokens=5 delims=-." %%i in ("!fb_build_file!") do (
                    set actual_fb_snapshot=%%i
                )
            )
            @rem for /f %%b in ("!href_file!")
        )
        @rem if .!actual_fb_snapshot!.==.0.
    )
    @rem for /f "tokens=2 delims='" %%a in (!tmplog!)

    if !previous_fb_snapshot! LSS !actual_fb_snapshot! (
        call :sho "Currently installed FB instance is OLDER that offered one." !joblog!
        set run_cmd=!curl_cmd! -L -v -trace !PROXY_DATA! !fb_major_vers_url!/!fb_build_file!
        (
            echo Downloading !fb_build_file!: installed snapshot No. !previous_fb_snapshot! is OLDER than offered on site: !actual_fb_snapshot!
            echo Command: !run_cmd!
        )>!tmplog!
        call :bulksho !tmplog! !joblog!

        @rem ##############################
        @rem curl: download actual snapshot
        @rem ##############################
        cmd /c !run_cmd! 1>!tmpdir!\!fb_build_file! 2>!tmperr!

        findstr /r /i /c:"http.* 200[ ]*OK" !tmperr! >nul
        if errorlevel 1 (
            call :sho "Could not download actual FB snapshot. Check error log" !joblog!
            type !tmperr!
            type !tmperr!>>!joblog!

            goto final

        )
        for /f "usebackq tokens=*" %%a in ('!tmpdir!\!fb_build_file!') do (
            set bld_size=%%~za
        )
        if .!bld_size!.==.. set bld_size=0

        call :sho "Success. Size of !tmpdir!\!fb_build_file!: !bld_size!" !joblog!



        @rem #########################################################################
        @rem ### e x t r a c t    c o m p r e s s e d     F B    s n a p s h o t   ###
        @rem #########################################################################
        set run_cmd=!COMPRESS_7Z! x -y -o"!dir_to_install!" !tmpdir!\!fb_build_file!
        
        call :sho "Extracting fresh build files. Command: !run_cmd!" !joblog!

        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
        set elevel=!errorlevel!
        set size=1
        
        if !elevel! EQU 0 (
            for /f "usebackq tokens=*" %%a in ('!tmperr!') do (
                set size=%%~za
            )
            if .!size!.==.. set size=0
        )
        if !size! GTR 0 (
            call :sho "Extract FAILED. Errorlevel: !elevel!. Check log:" !joblog!
            type !tmperr!
            type !tmperr!>>!joblog!

            @rem Compressed build must be deleted in ANY case!
            del !tmpdir!\!fb_build_file!

            goto :final

        )
        call :sho "Extraction of fresh FB build completed successfully." !joblog!

        @rem SEND compressed build to e-mail (if this is required, see config parameters 'mail_*')
        if not "!mail_hdr_from!"=="" if not "!mail_pwd_from!"=="" if not "!mail_hdr_to!"=="" if not "!mail_smtp_url!"=="" (


            call :sho "Sending downloaded snapshot to e-mail specified by config parameters." !joblog!

            @rem ###################################################################
            @rem ### s e n d i n g     s n a p s h o t     t o     e - m a i l   ###
            @rem ###################################################################
            @rem FB_daily_build 13:55. Build: Firebird-3.0.7.33387-0.amd64.tar.gz, part: 1 of 1

            @rem call :mailsender !joblog! "!mail_hdr_subj! INFO. !info_msg!"  n/a  n/a  mail_sending_result
            @rem                 1     \-------------------------------/   |    |          |
            @rem                                    2                      |    |          |
            @rem                                  mail_subj                3    |          |
            @rem                                              mail_body_file    4          5
            @rem                                               mail_attachment_file    out: retcode


            call :mailsender !joblog! "!mail_hdr_subj!. Build: !fb_build_file!, total size !bld_size!" "n/a" !tmpdir!\!fb_build_file! mail_sending_result
            @rem                1      \-----------------------  2  --------------------------------/    3             4                       5

            call :sho "Return to main part of script, e-mail sending retcode: !mail_sending_result!" !joblog!

            @rem DO NOT "goto final" here! Sending to e-mail can fail for some reasons not related to this script!
        )

        @rem Compressed can be deleted now.
        del !tmpdir!\!fb_build_file!


    ) else (
        call :sho "Currently installed FB instance is the same or newer offered one. SKIP downloading." !joblog!

    )

    call :sho "Config !fb_cfg_for_work! is copied to !dir_to_install! before launch FB." !joblog!

    type !fb_cfg_for_work! > !dir_to_install!\firebird.conf

    if not .!fb_major!.==.25. (
        @rem ##############################
        @rem ### INITIALIZE SECURITY.DB ###
        @rem ##############################
        (
            echo set bail on;
            echo set list on;
            echo set count on;
            echo set echo on;
            if /i not .!usr!.==.SYSDBA. (
                echo create or alter user SYSDBA password '!pwd!' firstname 'made !date! !time!' middlename 'at %COMPUTERNAME:'=''%' lastname 'by %~n0.bat' using plugin !sec_plugin!;
            )
            echo create or alter user !usr! password '!pwd!' firstname 'made !date! !time!' middlename 'at %COMPUTERNAME:'=''%' lastname 'by %~n0.bat' using plugin !sec_plugin!;
            if /i not .!usr!.==.SYSDBA. (
                echo commit;
                echo grant create database to user !usr!;
            )
            echo commit;
            echo select sec$user_name,sec$first_name,sec$middle_name,sec$last_name,sec$plugin
            echo from sec$users
            echo where upper(trim(sec$user_name^)^)=upper('!usr!'^);
        ) > !tmpsql!
        set run_cmd=!fbc!\isql security.db -user sysdba -i !tmpsql!
        call :sho "Attempt to create user !usr! using plugin !sec_plugin!. Command: !run_cmd!" !joblog!
        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
        set elevel=!errorlevel!

        set size=1
        if !elevel! EQU 0 (
            for /f "usebackq tokens=*" %%a in ('!tmperr!') do (
                set size=%%~za
            )
            if .!size!.==.. set size=0
        )
        if !size! GTR 0 (
            call :sho "Could not initialize security.db. Errorlevel: !elevel!. Check log:" !joblog!
            type !tmperr!
            type !tmperr!>>!joblog!

            goto :final

        ) 
        call :sho "Completed. Check log:" !joblog!
        call :bulksho !tmplog! !joblog!

    )
    @rem fb_major not 25: must initialize securityN.fdb

    @rem NB: space+TAB inside [ ]:
    findstr /i /r /c:"UdfAccess[ 	]*=" !fb_cfg_for_work! >nul
    if not errorlevel 1 (
        @rem Check whether oltp-emul config parameter 'sleep_ddl' points to 'default' UDF that is provided with test.
        @rem If yes then we have to make dir 'UDF' in FB_HOME and unpack there .\util\udf64\SleepUDF.dll.zip

        @rem !sleep_ddl! - parameter from oltpNN_config.
        @rem It must be name of SQL script which declares UDF to make delays.
        @rem This .sql file must be specified relatively to ${OLTP_ROOT}/src/ folder
        @rem This UDF is always needed when oltp-emul config parameter 'mon_unit_perf' is 2.
        @rem Also it is needed when parameters 'sleep_max' greater than 0 and 'sleep_ddl'
        @rem is uncommented and points to the script which declares this UDF.
        if /i "!sleep_ddl!"==".\oltp_sleepUDF_win.sql" (
            md !dir_to_install!\UDF 2>nul
            if not exist !dir_to_install!\UDF\nul (
                call :sho "Can not create directory !dir_to_install!\UDF. Check access rights." !joblog!

                goto :final
            )
            
            @rem config parameter OLTP_ROOT_DIR is specified as RELATIVE path, e.g.: ..\..
            @rem OLTP_SRC_DIR = OLTP_SRC_DIR\src
            @rem THIS_DIR is absolute path // current batch folder

            cd !THIS_DIR!
            cd !OLTP_SRC_DIR!

            set run_cmd=!COMPRESS_7Z! x -y -tzip -o!dir_to_install!\UDF ..\util\udf64\SleepUDF.dll.zip
            call :sho "Attempt to extract DLL with implementation of SLEEP. Command: !run_cmd!" !joblog!

            @rem ###########################################################
            @rem ###   e x t r a c t     U D F     f o r     S L E E P   ###
            @rem ###########################################################
            cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
            set elevel=!errorlevel!
            set size=1
            
            if !elevel! EQU 0 (
                for /f "usebackq tokens=*" %%a in ('!tmperr!') do (
                    set size=%%~za
                )
                if .!size!.==.. set size=0
            )
            if !size! GTR 0 (
                call :sho "Extract FAILED. Errorlevel: !elevel!. Check log:" !joblog!
                type !tmperr!
                type !tmperr!>>!joblog!

                goto :final

            )
            call :sho "Extraction of DLL completed successfully." !joblog!

            cd !THIS_DIR!

        )
    )
    @rem find 'UDFAccess' in fb.conf

    @rem get name of FB service that can be installed in !dir_to_install!
    set fb_svc_name=
    for /f "delims=\ tokens=5" %%a in ('reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services ^| findstr /i /c:"firebird"') do (
        set fb_svc_check=%%a
        if .!fb_svc_name!.==.. (
            for /f "tokens=3" %%k in ('REG.EXE query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\!fb_svc_check! ^| findstr /i /c:"ImagePath" ^| findstr /i /c:"!dir_to_install!"') do (
                for /f "tokens=4" %%s in ('sc queryex !fb_svc_check! ^| findstr /i /c:"state"') do (
                    set fb_svc_state=%%s
                )
                set fb_svc_path=%%k
                set fb_svc_name=!fb_svc_check!
            )
        )

    )
            

    if .!fb_svc_name!.==.. (
        call :sho "There is no FB service that must be launched from folder !dir_to_install!. FB will start as APPLICATION." !joblog!

        if .!fb_major!.==.25. (
            start /min !dir_to_install!\fb_inet_server.exe -a
        ) else (
            start /min !dir_to_install!\firebird.exe -a
        )

    ) else (
        call :sho "Service '!fb_svc_name!' is defined for launching in '!dir_to_install!'. Its state: !fb_svc_state!. Will try to (re-^)start it." !joblog!
        if /i not .!fb_svc_state!.==.STOPPED. (
            call :sho "Attempt to STOP service !fb_svc_name!" !joblog!
            sc stop !fb_svc_name!
            ping -n 6 127.0.0.1 >nul

            sc queryex !fb_svc_name! 1>!tmplog! 2>&1

            findstr /m /i /c:"STOPPED" !tmplog! 1>nul
            if NOT errorlevel 1 (
                call :sho "Success: service !fb_svc_name! was stopped." !joblog!
            ) else (
                call :sho "ACHTUNG. Could NOT stop service !fb_svc_nbame! before restart." !joblog!
                type !tmplog!>>!joblog!
                del !tmplog!
                goto :final
            )

        )
        call :sho "Attempt to START service !fb_svc_name!" !joblog!
        sc start !fb_svc_name!
        ping -n 6 127.0.0.1 >nul

        sc queryex !fb_svc_name! 1>!tmplog! 2>&1

        findstr /m /i /c:"RUNNING" !tmplog! 1>nul
        if NOT errorlevel 1 (
            call :sho "Success: service !fb_svc_name! is RUNNING." !joblog!
        ) else (
            call :sho "ACHTUNG. Could NOT stop service !fb_svc_nbame! before restart." !joblog!
            type !tmplog!>>!joblog!
            del !tmplog!
            goto :final
        )

    )
    @rem Wait here: FB launch may take several seconds on slow machine!
    ping -n 3 127.0.0.1>nul

    set run_cmd=netstat -a -n -o -b -p TCP -p TCPv6 ^| findstr /i /c:"LISTENING" ^| findstr /i /c:!port!
    (
        echo Check whether post !PORT_FOR_LISTENING! is listening now by FB process.
        echo Command:
        echo !run_cmd!
    ) >!tmplog!
    call :bulksho !tmplog! !joblog!

    cmd /c !run_cmd! 1>!tmplog! 2>&1
    set elevel=!errorlevel!
    if !elevel! EQU 0  (
        call :sho "OK: port !port! is LISTENING now." !joblog!
        for /f "tokens=1-5" %%a in ('type !tmplog!') do (
            set listener_pid=%%e
            call :sho "PID of listener: !listener_pid!" !joblog!
            tasklist /fi "PID eq !listener_pid!" 1>!tmplst! 2>&1
            call :bulksho !tmplst! !joblog!
        )

        (
            echo set list on;
            echo set bail on;
            echo set echo on;
            echo create database 'localhost/!port!:!tmpdir!\tmp_!random!!random!.fdb' user '!usr!' password '!pwd!';
            echo select mon$database_name from mon$database;
            echo commit;
            echo show version;
            echo drop database;
        ) >!tmpsql!

        set run_cmd=!fbc!\isql -q -i !tmpsql!

        call :sho "Final availability check: attempt to create temporary database. Command: !run_cmd!" !joblog!
        call :bulksho !tmpsql! !joblog! 1

        cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
        set elevel=!errorlevel!

        set size=1
        if !elevel! EQU 0 (
            for /f "usebackq tokens=*" %%a in ('!tmperr!') do (
                set size=%%~za
            )
            if .!size!.==.. set size=0
        )
        if !size! GTR 0 (
            call :sho "Could not create temporary DB. Errorlevel: !elevel!. Check log:" !joblog!
            type !tmperr!
            type !tmperr!>>!joblog!

            goto :final

        ) else (
            call :sho "Passed. Check log:" !joblog!
            call :bulksho !tmplog! !joblog!
        )


    ) else (
        call :sho "ACHTUNG. Port !port! is NOT listening by any process now." !joblog!
        del !tmplog!
        goto :final
    )

    del !tmplog! 2>nul


)
@rem !upd_fb!=1

for /f %%a in ("!curl_cmd!") do (
    if "%%~dpa"=="!tmpdir!\" (
        if exist !curl_cmd! (
            call :sho "Deleting file !curl_cmd!" !joblog!
            del !curl_cmd!
        )
    )
)
call :sho "Perform copying !etalon_dbnm! to !dbnm!" !joblog!


copy !etalon_dbnm! !dbnm!

if .!etalon_shutdown!.==.1. (
    call :sho "Database now is in shutdown state. Change it to normal" !joblog!
    @rem sho "Change state of target database from shutdown to normal." $log
    !fbc!\gfix -online localhost/!port!:!dbnm! -user !usr! -pas !pwd! 1>>!joblog! 2>&1
)
if .!etalon_readonly!.==.1. (
    call :sho "Database now is in read-only. Change it to read-write" !joblog!
    @rem sho "Change mode of target database from read_only to read_write." $log

    !fbc!\gfix -mode read_write localhost/!port!:!dbnm! -user !usr! -pas !pwd! 1>>!joblog! 2>&1
)

call :sho "Adjust database FORCED WRITES attribute according to parameter 'create_with_fw' from !oemul_cfg!" !joblog!
@rem    sho "Change FORCED WRITES for target DB, using parameter 'create_with_fw' = $create_with_fw." $log

!fbc!\gfix -w !create_with_fw! localhost/!port!:!dbnm! -user !usr! -pas !pwd! 1>>!joblog! 2>&1

call :sho "Adjust database SWEEP INTERVAL attribute according to parameter 'create_with_sweep' from !oemul_cfg!" !joblog!
@rem    sho "Change SWEEP INTERVAL for target DB, using parameter 'create_with_sweep' = $create_with_sweep." $log
!fbc!\gfix -h !create_with_sweep! localhost/!port!:!dbnm! -user !usr! -pas !pwd! 1>>!joblog! 2>&1

if .!BACKUP_LOCK!.==.1. (
    call :sho "Adjust database BACKUP-LOCK attribute according to parameter 'BACKUP_LOCK' from current script config" !joblog!
    if exist !dbnm!.delta del !dbnm!.delta
    !fbc!\nbackup -L !dbnm! -user !usr! -pas !pwd! 1>>!joblog! 2>&1
)

!fbc!\gstat -h !dbnm! | findstr /i /c:"attributes" /c:"sweep" >!tmplog!
call :bulksho !tmplog! !joblog!

cd /d !OLTP_SRC_DIR!

(
    echo ############################################
    echo ###  L A U N C H     O L T P - E M U L  ###
    echo ############################################
    echo Current dir: !cd!
    dir /-c .\1run_oltp_emul.bat | findstr /i /c:"1run_oltp_emul.bat"
    echo Command:
    echo call .\1run_oltp_emul.bat !fb_major! !sess_cnt! nostop
) >!tmplog!

call :bulksho !tmplog! !joblog!


call .\1run_oltp_emul.bat !fb_major! !sess_cnt! nostop

echo.
call :sho "Batch %~f0 is to be finished. Bye-bye." !joblog!

goto :final

@rem ########################################################################################
@rem ########################################################################################
@rem ########################################################################################


@rem _=_=_=_=_=_=_=_=_=_=_=_= auxiliary routines below _=_=_=_=_=_=_=_=_=_=_=_=


:getFileSize

    setlocal
    set working_mode=%1
    set tmp_fold=%2\%~n0
    if .%2.==.. set tmp_fold=%~dpn0
    set for_file=%3

    set vbs="!tmp_fold!.tmp.getFileSize.vbs"
    set fsz="!tmp_fold!.tmp.getFileSize.dat"

    if /i .%working_mode%.==.GEN_VBS. (
        del %vbs% 2>nul

        (
            echo 'Created auto by %~f0 at !date! !time!, do NOT edit!
            echo 'Used to obtain exact timestamp of file
            echo 'Usage: cscript ^/^/nologo %vbs% ^<file^>
            echo 'Result: size of file
            echo Set objFS ^= CreateObject("Scripting.FileSystemObject"^)
            echo Set objArgs ^= WScript.Arguments
            echo strFile ^= objArgs(0^)
            echo WScript.echo objFS.GetFile(strFile^).Size
        )>>%vbs%

        endlocal & goto:eof

    ) else if /i .%working_mode%.==.GET_SIZE. (

        @rem echo cscript //nologo !vbs! !for_file! redir to: !fsz!
        cscript //nologo !vbs! !for_file! 1>!fsz!
        endlocal & set /p %~4=<%fsz% & del %fsz%
    ) else if /i .%working_mode%.==.DEL_VBS. (
        del !vbs!
    )
    endlocal

goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:getFileDTS
    @rem Not used. Can be removed if needed.
    @rem http://www.dostips.com/DtTutoFunctions.php
    setlocal
    set working_mode=%1
    set tmp_fold=%2\%~n0
    if .%2.==.. set tmp_fold=%~dpn0
    set for_file=%3

    set vbs="!tmp_fold!.tmp.getFileDTS.vbs"
    set dts="!tmp_fold!.tmp.getFileDTS.dat"

    if /i .%working_mode%.==.GEN_VBS. (
        del %vbs% 2>nul

        (
            echo 'Created auto by %~f0 at !date! !time!, do NOT edit!
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

        endlocal & goto:eof

    ) else if /i .%working_mode%.==.GET_DTS. (

        echo cscript //nologo !vbs! !for_file! redir to: !dts!
        cscript //nologo !vbs! !for_file! 1>!dts!
        endlocal & set /p %~4=<%dts% & del %dts%
    ) else if /i .%working_mode%.==.DEL_VBS. (
        del !vbs!
    )
    endlocal

goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:get_ANSI_dts
    setlocal
    if .%1.==.. (
        echo Problem in subroutine get_cscript_dts: output argument was not provided.
        echo JOB IS TERMINATED.
        goto final
    )

    set dts_varname=%1
    if /i .!GET_TIMESTAMP_METHOD!.==.wmic. (
        call :get_wmic_dts dts_varname
    ) else (
        call :get_cscript_dts dts_varname
    )

    endlocal & set "%~1=%dts_varname%"
goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:get_wmic_dts
    setlocal
    for /f "tokens=1-1 delims=." %%a in ('wmic.exe OS GET LocalDateTime ^| findstr /r /b /c:"20.*."' ) do (
        set current_dts=%%a
    )

    endlocal & set "%~1=%current_dts%"
goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:get_cscript_dts
    @rem to be removed, replaced 13.12.19
    setlocal
    if .%1.==.. (
        echo Problem in subroutine get_cscript_dts: output argument was not provided.
        echo JOB IS TERMINATED.
        goto final
    )

    set tmppath=!TMPDIR!
    if .!tmppath!.==.. (
        set tmppath=%TEMP%
        if .!tmppath!.==.. (
            set tmppath=%TMP%
            if .!tmppath!.==.. (
                set tmppath=%~dp0
                set tmppath=!tmppath:~0,-1!
            )
        )
    )

    set need_vbs=1
    set vbs_name=!tmppath!\%~n0.get_ansi_dts.vbs

    if exist !vbs_name! (
        findstr /i /r /c:"function.*timestamp" !vbs_name! >nul
        if not errorlevel 1 (
            set need_vbs=0
        )
    )

    if !need_vbs! EQU 1 (
        (
            @echo 'Generated auto by %~f0 at !date! !time!
            @echo 'Usage: cscript ^/^/nologo //e:vbscript !vbs_name!
            @echo WScript. echo timeStamp(now(^)^)
            @echo Function timeStamp( d ^)
            @echo   timeStamp = Year(d^) ^& _
            @echo   Right("0" ^& Month(d^),2^) ^& _
            @echo   Right("0" ^& Day(d^),2^) ^& "_" ^& _
            @echo   Right("0" ^& Hour(d^),2^) ^& _
            @echo   Right("0" ^& Minute(d^),2^) ^& _
            @echo   Right("0" ^& Second(d^),2^)
            @echo End Function
        ) >!vbs_name!
    )

    for /f %%a in ('cscript //nologo //e:vbscript !vbs_name!') do (
        set curr_dts=%%a
        @rem REMOVE underscore character:
        @rem ----------------------------
        set curr_dts=!curr_dts:_=!
    )

    @rem do NOT: del !vbs_name!

    endlocal & set "%~1=%curr_dts%"
goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

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

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:trim
    setLocal

    @rem 22.10.2020: we have to enclose assignment of Params into double quotes.
    @rem Otherwise caret will be duplicated here, i.e.
    @rem when call this routine with string like: "set term ^;"
    @rem then output will be: "set term ^^;"
    set "Params=%*"

    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

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

        set left_char=!val:~0,1!
        set righ_char=!val:~-1!

        if "!left_char!"==" " set cutspaces=1
        if "!left_char!"=="	" set cutspaces=1
        if "!righ_char!"==" " set cutspaces=1
        if "!righ_char!"=="	" set cutspaces=1

        if .!cutspaces!.==.1. (
            set val=!val:^|=$PIPE$OPERATOR$!
            set val=!val:^&=$AMPERSAND$!
            set val=!val:%%=$PERCENT$SIGN$!
            set val=!val:^>=$GREATER$THEN$!
            set val=!val:^<=$LESS$THEN$!

            call :trim val !val!

            for /f "useback tokens=*" %%x in ('!val!') do (
                    set val=%%~x
            )
            set val=!val:$GREATER$THEN$=^>!
            set val=!val:$LESS$THEN$=^<!
            set val=!val:$PIPE$OPERATOR$=^|!
            set val=!val:$AMPERSAND$=^&!
            set val=!val:$PERCENT$SIGN$=%%!
        ) else (
            for /f "useback tokens=*" %%x in ('!val!') do (
                    set val=%%~x
            )
        )
        if .!val!.==.$EMPTY$LINE$. (
            echo.>>!tmp_output!
        ) else (
            echo !val!>>!tmp_output!
        )
    )
    move !tmp_output! !input_file! 1>nul

goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=


:sho
    setlocal

    set msg=%1
    set msg=!msg:`="!
    set log=%2
    if .!log!.==.. (
        echo Internal func sho: missed argument for log file.
        echo Arg. #1 = ^|%1^|
        call :final
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
    set this_dts=19000101000000
    call :get_ansi_dts this_dts

    set curr_ymd=!this_dts:~2,6!
    set curr_hms=!this_dts:~8,6!

    set this_dts=!curr_ymd!_!curr_hms!

    set msg=!this_dts!. !msg!
    echo !msg!
    echo !msg!>>!log!

endlocal & goto:eof


@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:bulksho
    setlocal
    set tmplog=%1
    set joblog=%2
    set keep_tmp=%3

    set this_dts=19000101000000
    call :get_ansi_dts this_dts
    set curr_ymd=!this_dts:~2,6!
    set curr_hms=!this_dts:~8,6!
    set this_dts=!curr_ymd!_!curr_hms!
    for /f "tokens=*" %%a in (!tmplog!) do (
       set msg=%%a
       set msg=!msg:"=`!
       set msg=!this_dts!. !msg!
       echo !msg!
       echo !msg!>>!joblog!
    )
    if not .!keep_tmp!.==.1. (
        del !tmplog!
    )
endlocal & goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

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
            echo ' Usage: Cscript //nologo //e:vbscript !remove_extra_cr_vbs! ^< C:\temp\input_file.txt ^> C:\temp\output_file.txt
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

cscript //nologo //e:vbscript !remove_extra_cr_vbs! < !sourfile! > !targfile!

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

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

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

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:catch_err
    
    setlocal

    @rem Sample:
    @rem set run_cmd=!fbsvcrun! info_server_version
    @rem !run_cmd! 1>%tmplog% 2>%tmperr%
    @rem call :catch_err run_cmd !tmperr! n/a nofbvers
    @rem call :catch_err run_isql !tmperr! !tmpchk! db_not_ready 0

    set run_cmd=!%1!
    set main_log=%2
    set err_file=%3
    set tmp_file=%4
    set addi_call=%5
    set do_abend=%6
    if .!do_abend!.==.. set do_abend=1

    for /f "usebackq tokens=*" %%a in ('%err_file%') do set err_size=%%~za
    if .!err_size!.==.. set /a err_size=0
    if !err_size! gtr 0 (
        (
            echo.
            echo ### ATTENTION ###
            echo.
            if not .%addi_call%.==.. (
                if /i not .%addi_call%.==.n/a. (
                  call :!addi_call!
                )
            )
            echo.
            echo Command: !run_cmd! - finished with ERROR.
            echo.
            echo Content of error log (%err_file%^):
            echo ^=^=^=^=^=^=^=
            type %err_file%
            echo ^=^=^=^=^=^=^=
            if .!do_abend!.==.1. (
                echo.
                echo JOB IS TERMINATED.
            )
        ) >!tmp_file!

        @rem call :bulksho !tmp_file! !main_log!
        type !tmp_file!
        type !tmp_file! >> !main_log!
        del !tmp_file!

        if .!do_abend!.==.1. (
            goto final
        )
    )
    endlocal
goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:no_env
    setlocal
    set tmplog=%1
    set cfgfile=%2
    (
        echo.
        echo #######################################################
        echo Missed at least one of necessary environment variables.
        echo #######################################################
        echo.
        echo Check config file '!cfgfile!'.
        echo.
    ) >!tmplog!
    type !tmplog!

    @goto final
goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:noaccess
    setlocal
    set tmplog=%1
    (
        echo.
        echo No access to directory defined by config parameter 'tmpdir':
        echo !tmpdir!
        echo.
        echo Check config file '%~dp0%cfg%' and adjust this parameter.
        echo.
    ) > !tmplog!
    type !tmplog! 

    goto final
goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:kill_fb_processes
    setlocal
    
    set joblog=%1
    set FBAPPS=%2
    set dir_for_check=%3
    set PORT_FOR_LISTENING=%4

    @rem Example: c`all :kill_fb_processes !joblog! "!FBAPPS!" !TMP_DIR_FOR_SNAPSHOT! !PORT_FOR_LISTENING!

    if .!PORT_FOR_LISTENING!.==.. (
        set msg=Routine 'kill_fb_processes': missed one of mandatory parameters.
        echo !msg! > %%~dpn0.abend.tmp 
        goto :final
    )

    @rem Trim double quotes from the list of FB-related apps:
    for /f "useback tokens=*" %%a in ('!fbapps!') do set fbapps=%%~a

    for /f %%a in ("!dir_for_check!\") do (
        set TMP_DIR_FOR_SNAPSHOT=%%~dpna
        set TMP_DIR_FOR_SNAPSHOT=!TMP_DIR_FOR_SNAPSHOT:\\=\!
        set TMP_DIR_FOR_SNAPSHOT=!TMP_DIR_FOR_SNAPSHOT:~0,-1!
    )

    call :sho "Intro routine kill_fb_processes. Search and kill all FB-related processes that launched from !TMP_DIR_FOR_SNAPSHOT! folder." !joblog!

    for /f %%a in ("!joblog!") do (
      set log_dir=%%~dpa
      set tmp1=%%~dpna.1.tmp
      set tmp2=%%~dpna.2.tmp
      set tmp3=%%~dpna.3.tmp
      set tmp4=%%~dpna.4.tmp
      set tmpvbs=%%~dpna.get-pid-imagepath.vbs
    )


    (
        echo ' Generated auto by %~f0, do NOT edit.
        echo ' Syntax: %systemroot%\system32\cscript.exe //nologo //e:vbs !tmpvbs! ^<PID^>
        echo ' Output ImagePath for process with PID = input argument.
        echo option explicit
        echo dim wmi, list, process, path, pid
        echo pid=WScript.Arguments.Item(0^)
        echo set wmi = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2"^) 
        echo set list = wmi.ExecQuery("select * from Win32_Process where processId = '" ^& pid ^& "'"^)
        echo for each process in list
        echo     path = process.ExecutablePath
        echo     wscript.echo path
        echo next
        echo set wmi = nothing
        echo set list = nothing
    ) > !tmpvbs!

    call :sho "Get name of FB service which started from !TMP_DIR_FOR_SNAPSHOT! folder." !joblog!
    dir . 1>nul 2>!tmp1!

    for /f "delims=\ tokens=5" %%a in ('reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services ^| findstr /i /c:"firebird"') do (
        set fb_svc_name=%%a
        for /f "tokens=3" %%k in ('REG.EXE query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\!fb_svc_name! ^| findstr /i /c:"ImagePath" ^| findstr /i /c:"!TMP_DIR_FOR_SNAPSHOT!" ') do (
            for /f "tokens=4" %%s in ('sc queryex !fb_svc_name! ^| findstr /i /c:"state"') do (
                set fb_svc_state=%%s
            )
            set fb_svc_path=%%k
        
            @rem 02.10.2020: we have to stop only service which binary started
            @rem from !TMP_DIR_FOR_SNAPSHOT! folder. DO NOT stop other services!
            echo !fb_svc_path! | findstr /i /c:"!TMP_DIR_FOR_SNAPSHOT!\\" >nul
            if NOT errorlevel 1 (
                echo !fb_svc_state! | findstr /m /i /v /c:STOPPED >nul
                if NOT errorlevel 1 (
                    echo !fb_svc_name! !fb_svc_state! !fb_svc_path! >>!tmp1!
                )
            )
        )
    )
    @rem Example of result:
    @rem FirebirdServer30ss RUNNING C:\FB\30SS\firebird.exe
    @rem FirebirdServer30sS STOPPING C:\FB\30SS\firebird.exe


    call :sho "Check list of FB services that must be stopped now:" !joblog!
    call :sho "----- beg of list -----" !joblog!
    call :bulksho !tmp1! !joblog! 1
    call :sho "----- end of list -----" !joblog!

    for /f "tokens=1" %%s in ('findstr /i /v /c:"STOPPED" !tmp1!') do (
        set fb_svc=%%s
        del !tmp2! 2>nul
        call :sho "Trying to stop FB service: sc stop !fb_svc!..." !joblog!
        sc stop !fb_svc! 1>>!tmp2! 2>&1
        ping -n 6 127.0.0.1 >nul
        call :bulksho !tmp2! !joblog!

        call :sho "Check current status of service: sc queryex !fb_svc!" !joblog!
        sc queryex !fb_svc! 1>>!tmp2! 2>&1

        findstr /m /i /c:"STOPPED" !tmp2! 1>nul
        if NOT errorlevel 1 (
            call :sho "Success: service !fb_svc! was stopped, PID=!fb_pid! no more exists." !joblog!
        ) else (
            call :sho "ACHTUNG. Could NOT stop service !fb_svc!, its PID=!fb_pid! still exists." !joblog!
        )
        call :bulksho !tmp2! !joblog!
    )
    del !tmp1! 2>nul
    del !tmp2! 2>nul

    call :sho "Point before loop for list of FB-related names. Check 'FBAPPS' in %~dpn0.conf" !joblog!

    for /d %%p in (!FBAPPS!) do (
        (
            echo.
            echo --------------------------------------------------------
            echo Start loop iteration for !FBAPPS!
        ) >!tmp1!
        call :bulksho !tmp1! !joblog!

        call :sho "Command: tasklist /fi 'imagename eq %%p.exe'" !joblog!

        tasklist /fi "imagename eq %%p.exe" 1>!tmp1! 2>&1
        call :bulksho !tmp1! !joblog! 1

        @rem ::: NB :::: 
        @rem tasklist always returns 0 as errorlevel, regardless whether process does exist or no.
        @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        @rem Example of output:
        @rem Image Name                     PID Session Name        Session#    Mem Usage
        @rem ========================= ======== ================ =========== ============
        @rem firebird.exe                  2036 Services                   0      8,524 K
        @rem firebird.exe                 10972 Services                   0      7,504 K
        @rem firebird.exe                 11576 RDP-Tcp#0                  6      7,236 K

        findstr /i /m /c:"%%p.exe" !tmp1! >nul
        if NOT errorlevel 1 (

            @rem findstr /i /c:"%%p.exe" !tmp1!
            dir . 1>nul 2>!tmplst!
            for /f "tokens=1-3" %%x in ('findstr /i /c:"%%p.exe" !tmp1!') do (
                set fb_pid=%%y

                set run_cmd=%systemroot%\system32\cscript //nologo /e:vbs !tmpvbs! !fb_pid!
                (
                    echo Get ImagePath for process with PID=!fb_pid!.
                    echo Command: !run_cmd!
                ) >!tmp1!
                call :bulksho !tmp1! !joblog!

                cmd /c !run_cmd! 1>!tmp2! 2>&1

                @rem 02.10.2020: we have to kill only FB processes which started
                @rem from !TMP_DIR_FOR_SNAPSHOT! folder. DO NOT kill others!
                findstr /i /c:!TMP_DIR_FOR_SNAPSHOT! !tmp2! >nul

                set elevel=!errorlevel!
                if !elevel! EQU 0  (

                    call :sho "Process with PID=!fb_pid! was launched from '!TMP_DIR_FOR_SNAPSHOT!'. It will be further killed." !joblog!
                    @rem ##################
                    echo !fb_pid!>>!tmplst!
                    @rem ##################

                ) else (
                    call :sho "Process with PID=!fb_pid! will not be killed, its binary not from !TMP_DIR_FOR_SNAPSHOT!:" !joblog!
                    call :bulksho !tmp2! !joblog!
                )
            )
            @rem for /f "tokens=1-3" %%x in ('findstr /i /c:"%%p.exe" !tmp1!')

            echo.>>!joblog!
            echo.

            set tmp_size=0
            if exist !tmplst! (
                for /f %%a in ("!tmplst!") do (
                    set tmp_size=%%~za
                )
            )
            if .!tmp_size!.==.0. (
                call :sho "There are NO processes with name '%%p.exe' launched from !TMP_DIR_FOR_SNAPSHOT!" !joblog!
            ) else (
                call :sho "Trying to kill all processes with name '%%p.exe' from following list:" !joblog!
                type !tmplst!
                type !tmplst!>>!joblog!
            )

            for /f %%x in (!tmplst!) do (
                set run_cmd=taskkill /F /T /PID %%x
                call :sho "Command: !run_cmd!" !joblog!
                cmd /c !run_cmd! 1>!tmp1! 2>&1
    
                findstr /i /v /c:"SUCCESS:" !tmp1!
                if NOT errorlevel 1 (
                    call :sho "### TASKKILL FAILED ###" !joblog!
                    call :bulksho !tmp1! !joblog!

                    @rem https://stackoverflow.com/questions/12528963/taskkill-f-doesnt-kill-a-process
                    call :sho "Perform 2nd attempt: use Windows Management Instrumentation to kill process with PID=%%x" !joblog!
                    
                    @rem Output will be in ASCI, not unicode. NO pipe to 'more' required here:

                    set run_cmd=wmic process %%x delete
                    call :sho "Command: !run_cmd!" !joblog!
                    cmd /c "!run_cmd!" 1>!tmp1! 2>&1

                    @rem Sample output of w_mic ... delete:
                    @rem Deleting instance \\FBCOMPILEWIN\ROOT\CIMV2:Win32_Process.Handle="1748"
                    @rem Instance deletion successful.

                    call :bulksho !tmp1! !joblog!

                ) else (
                    call :bulksho !tmp1! !joblog!
                )
            )
            @rem for /f %%x in (!tmplst!)
            del !tmplst!

        ) else (
            call :sho "Nothing to kill. Process with name '%%p.exe' not found." !joblog!
        )

        del !tmp1! 2>nul
        del !tmp2! 2>nul
        call :sho "End of loop iteration for !FBAPPS!" !joblog!
    )
    @rem for /d %%p in (!FBAPPS!) 
    @rem del !tmppy!

    set run_cmd=netstat -a -n -o -b -p TCP -p TCPv6 ^| findstr /i /c:"LISTENING" ^| findstr /i /c:!PORT_FOR_LISTENING!
    @rem 4debug: set run_cmd=netstat -a -n -o -b -p TCP -p TCPv6 ^| findstr /i /c:"LISTENING"
    (
        echo All iterations of loop for !FBAPPS! completed.
        echo Check whether post !PORT_FOR_LISTENING! is listening now by some process.
        echo Command:
        echo !run_cmd!
    ) 1>!tmp1!
    call :bulksho !tmp1! !joblog!

    cmd /c !run_cmd! 1>!tmp2! 2>&1
    set elevel=!errorlevel!
    if !elevel! EQU 0  (
        call :sho "Some process is listening now for port !PORT_FOR_LISTENING! which is specified in !oemul_cfg! as 'port' parameter." !joblog!
        for /f "tokens=1-5" %%a in ('type !tmp2!') do (
            set concurrent_listener_pid=%%e
            call :sho "PID of concurrent listener: !concurrent_listener_pid!" !joblog!
            tasklist /fi "PID eq !concurrent_listener_pid!" 1>!tmp1! 2>&1
            call :bulksho !tmp1! !joblog!
            call :sho "JOB TERMINATED." !joblog!
            goto :final
        )
    ) else (
        call :sho "There are no concurrent processes that are listening for port !PORT_FOR_LISTENING!" !joblog!
        call :sho "We can continue." !joblog!
    )
    del !tmp1! 2>nul
    del !tmp2! 2>nul

    call :sho "Leave routine kill_fb_processes." !joblog!

    endlocal

goto :eof
@rem end of routine kill_fb_processes

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:mailsender
    setlocal
    set joblog=%1
    set mail_subj=%2
    set mail_body_text_file=%3
    set mail_attachment_file=%4

    @rem mail_sending_result - OUTPUT arg, to be stored as output arg,  %5 
    set mail_sending_result=0

    set dts=19000101000000
    @rem    20190531234517
    @rem    01234567890123
    call :get_ansi_dts dts
    set ymd=!dts:~2,6!
    set hms=!dts:~8,6!
    @rem set dtm=!dts:~6,2!.!dts:~4,2!.!dts:~2,2! !dts:~8,2!:!dts:~10,2!.
    set dtm=!dts:~8,2!:!dts:~10,2!

    set dts=!ymd!_!hms!
    for /f %%a in ("!joblog!") do (
        set log_dir=%%~dpa
        set log_dir=!log_dir:~0,-1!
    )

    set tmp0=%log_dir%\%~n0.!dts!.0.tmp
    set tmp1=%log_dir%\%~n0.!dts!.1.tmp
    set tmp2=%log_dir%\%~n0.!dts!.2.tmp

    @rem max_size_without_split -- take from .conf

    (
        echo Intro routine mailsender. Check input params:
        echo * mail_subj=!mail_subj!
        echo * mail_body_text_file=!mail_body_text_file!
        echo * mail_attachment_file=!mail_attachment_file!
    ) > !tmp0!

    call :bulksho !tmp0! !joblog!

    if /i .!mail_attachment_file!.==.n/a. (
        set mail_attachment_file=
    )

    @rem Here we INJECT timestamp between '::: FB BUILD :::' and rest text of subject, e.g.:
    @rem "::: QA fbtest ::: overall job log"
    @rem -- will be:
    @rem "::: QA fbtest ::: 24.07.19 11:04 overall job log"
    set mail_subj=!mail_subj:%mail_hdr_subj%=%mail_hdr_subj% %dtm%!

    set left_char=!mail_subj:~0,1!
    set righ_char=!mail_subj:~-1!

    @rem REMOVE LEADING AND TRAILING DOUBLE QUOTES:
    @rem ##########################################
    set result=!left_char:"=!
    if .!result!.==.. (
       set result=!righ_char:"=!
       if .!result!.==.. (
          set mail_subj=!mail_subj:~1,-1!
       )
    )

    if not .!curl_cmd!.==.. (

        @rem https://curl.haxx.se/mail/lib-2012-01/0121.html

        set dump_eml=%log_dir%\%~n0.email.log
        set curl_cmd=!curl_cmd! !curl_opt! --upload-file "!dump_eml!"

        @rem 25.06.2018:
        @rem We have to remove parenthesis from name of file that will be specified in cUrl "--upload-file" command swicth,
        @rem otherwise cUrl raises excetption like "curl: (56) Send failure: Connection was aborted" and does NOT send file!
        set dump_eml=!dump_eml:(=_!
        set dump_eml=!dump_eml:^)=_!

        call :sho "Start sending e-mail. File with message body: !dump_eml!" !joblog!

        set bnd_label=----==--bound.label.!dts!

        if exist !mail_attachment_file! (
            if !base64_avail! EQU 1 (
                set /a mail_attachment_size=0
                for /f %%a in ("!mail_attachment_file!") do (
                    set attach_filepath=%%~dpa
                    set attach_filepath=!attach_filepath:~0,-1!
                    set attach_filename=%%~na
                    set attach_file_ext=%%~xa
                    set zipname=%%~na.!ymd!
                    set zipname=!zipname:.=_!
                    if %%~za GTR 0 (
                        set /a mail_attachment_size=%%~za
                    )
                )
                if !mail_attachment_size! GTR !max_size_without_split! (
                    set run_cmd=!COMPRESS_7Z! u -mx0
                    if !mail_attachment_size! GTR !max_size_without_split! (
                        set run_cmd=!run_cmd! -v!max_size_without_split!
                    ) 
                    set run_cmd=!run_cmd! !log_dir!\!zipname! !mail_attachment_file!

                    call :sho "Create compressed file to be sent as attachment:" !joblog!
                    call :sho "Command: !run_cmd!" !joblog!

                    @rem We have to delete all previously created .7z volumes for this name
                    @rem otherwise 'system error file exists' will raise by 7-zip:
                    for /l %%i in (0 1 9) do (
                        if exist !log_dir!\!zipname!.%%i* del !log_dir!\!zipname!.%%i*
                    )

                    cmd /c !run_cmd!

                    for /f %%x in ('dir /b !log_dir!\!zipname!.* ^| findstr !zipname! ^| find /v /c ""') do (
                       set /a num_of_zip_parts=%%x
                    )

                    set attach_filepath=!log_dir!
                    set attach_pattern=!log_dir!\!zipname!.*
                    set attach_mime_type=application/x-7z-compressed

                ) else (
                    set /a num_of_zip_parts=1
                    set attach_pattern=!mail_attachment_file!

                    @rem attach_filepath, attach_filename, attach_file_ext -- already known, see above.

                    set attach_mime_type=text/plain
                    if /i "!attach_file_ext!"==".zip" (
                        set attach_mime_type=application/zip
                    )
                    if /i "!attach_file_ext!"==".7z" (
                        set attach_mime_type=application/x-7z-compressed
                    )
                )
                set /a zip_part_no=0
                
                (
                    echo attach_pattern=!attach_pattern! ; attach_filename=!attach_filename! ; attach_file_ext=!attach_file_ext!
                    echo Check result of "dir /b !attach_pattern! ^| findstr !attach_filename!"
                    dir /b !attach_pattern! | findstr !attach_filename!
                ) >!tmp0!
                type !tmp0!
                type !tmp0! >> !joblog!
                set part_sending_result=0

                for /f %%a in ('dir /b !attach_pattern! ^| findstr !attach_filename!') do (

                    set /a zip_part_no=!zip_part_no!+1
                    
                    call :sho "Sending file %%a, part !zip_part_no! of !num_of_zip_parts!" !joblog!

                    if exist !dump_eml! del !dump_eml!

                    (
                        echo From: ^<!mail_hdr_from!^>
                        echo To: ^<!mail_hdr_to!^>
                        if !num_of_zip_parts! GTR 1 (
                            echo Subject: !mail_subj!; part !zip_part_no! of !num_of_zip_parts!
                        ) else (
                            echo Subject: !mail_subj!
                        )
                        echo MIME-Version: 1.0
                        echo Content-Type: multipart/mixed;
                        echo     boundary="!bnd_label!"
                        echo.
                        echo.
                        echo --!bnd_label!
                        @rem ### BODY of message ###
                        echo Content-Type: text/plain
                        echo.
                    ) > !dump_eml!

                    if exist !mail_body_text_file! (
                        type !mail_body_text_file! >> !dump_eml!
                    )
                    set sending_file=%%~nxa
                    set zipb64=!log_dir!\%%~na.!dts!.b64
                    set run_cmd=certutil -encode !attach_filepath!\%%a !zipb64! 1^>!tmp1! 2^>^&1

                    (
                        echo Encoding to base64: !sending_file!
                        echo Command: !run_cmd!
                    ) > !tmp1!
                    call :bulksho !tmp1! !joblog!

                    cmd /c "!run_cmd!"
                    call :bulksho !tmp1! !joblog!

                    copy !zipb64! !tmp1!
                    
                    findstr /i /v /r /c:"begin[ ]*cert" /c:"end[ ]*cert" !tmp1! > !zipb64!
                    del !tmp1!

                    @rem We have to remove file that was compressed for sending and encoded to base64 just now

                    if NOT .!attach_pattern!.==.!mail_attachment_file!. (
                        @rem this is PART of compressed .7z file -- we can and have to drop it.
                        del !log_dir!\%%a
                    )

                    call :sho "File !sending_file! has been encoded to base64." !joblog!

                    (
                        echo --!bnd_label!
                        echo Content-Disposition: attachment;
                        echo 	filename="!sending_file!"
                        echo Content-Transfer-Encoding: base64
                        echo Content-Type: !attach_mime_type!;
                        echo 	name="!sending_file!"
                        echo.
                    ) >>!dump_eml!

                    @rem ::::::::::::::::::::::::::::::::
                    @rem ::: Add attachment to e-mail :::
                    @rem ::::::::::::::::::::::::::::::::
                    type !zipb64!>>!dump_eml!

                    del !zipb64!

                    @rem Put final lable at the end of message body: add two dashes before and after label.
                    echo --!bnd_label!-->>!dump_eml!

                    call :sho "Completed preparing file !dump_eml! for sending." !joblog!

                    set /a eml_result=1
                    
                    (
                        echo mail_subj=!mail_subj!
                        echo Check cURL command:
                        echo !curl_cmd!
                    ) > !tmp0!
                    call :bulksho !tmp0! !joblog!
                    
                    call :mail_prepared_eml !dts! "!curl_cmd!" part_sending_result
                    del !dump_eml!

                    echo.
                    (
                        set msg_result=COMPLETED OK
                        if not .!part_sending_result!.==.0. (
                            set msg_result=__FAILED__
                        )
                        echo ############################################################################################################
                        echo Sending of: !mail_subj!; part !zip_part_no! of !num_of_zip_parts! - !msg_result!, retcode: !part_sending_result!
                        echo ############################################################################################################
                    ) >!tmp0!
                    call :bulksho !tmp0! !joblog!
                    echo.

                    if .!mail_sending_result!.==.0. (
                        set mail_sending_result=!part_sending_result!
                    )

                    if !zip_part_no! LSS !num_of_zip_parts! (
                        if not .!mail_delay_seconds!.==.. (
                            if !mail_delay_seconds! GTR 0 (
                               set delay=!mail_delay_seconds!+1
                               call :sho "Take pause for !mail_delay_seconds! seconds between subsequent sendings..." !joblog!
                               ping -n !delay! 127.0.0.1 > nul
                               call :sho "Pause finished, now sending next attachment." !joblog!
                            )
                        )
                    )

                )
                @rem processing .7z files: for /f %%a in ('dir /b !log_dir!\!zipname!.* ^| findstr !zipname!')

            )
            @rem if !base64_avail! EQU 1
 
        ) else (

            @rem send message without attachment

            (
                echo From: ^<!mail_hdr_from!^>
                echo To: ^<!mail_hdr_to!^>
                echo Subject: !mail_subj!
                echo MIME-Version: 1.0
                @rem ### BODY of message ###
                echo Content-Type: text/plain
                echo.
            ) >!dump_eml!
            if exist !mail_body_text_file! (
                type !mail_body_text_file! >> !dump_eml!
            ) else (
                echo STUB: this letter was created by %~f0 on %COMPUTERNAME% at !date! !time!. No more info.>> !dump_eml!
            )

            call :mail_prepared_eml !dts! "!curl_cmd!" mail_sending_result

            del !dump_eml!

        )
        @rem if exist !mail_attachment_file! --> TRUE / FALSE

    )
    @rem if defined curl_cmd

    call :sho "Leaving routine mailsender, mail_sending_result=!mail_sending_result!" !joblog!

    endlocal & set "%~5=%mail_sending_result%"

goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:mail_prepared_eml
    setlocal
    set dts=%1
    set curl_cmd=%2

    @rem mail_sending_result - OUTPUT arg, to be stored as output arg, %3 
    set mail_sending_result=1

    call :sho "Intro routine mail_prepared_eml" !joblog!

    set tmp0=%log_dir%\%~n0.!dts!.0.tmp
    set tmp1=%log_dir%\%~n0.!dts!.1.tmp

    set left_char=!curl_cmd:~0,1!
    set righ_char=!curl_cmd:~-1!

    @rem REMOVE LEADING AND TRAILING DOUBLE QUOTES:
    @rem ##########################################
    set result=!left_char:"=!
    if .!result!.==.. (
       set result=!righ_char:"=!
       if .!result!.==.. (
          set curl_cmd=!curl_cmd:~1,-1!
       )
    )

    @rem ####################################################################
    @rem ::: NB ::: cURL sends its output to STDERR rather than in STDOUT :::
    @rem ####################################################################
    set /a eml_result=1

    (
        echo Sending e-mail using command:
        echo !curl_cmd!
    ) >!tmp0!
    call :bulksho !tmp0! !joblog!


    cmd /c !curl_cmd! 1>!tmp0! 2>&1
    set elevel=!errorlevel!
    @rem curl: (67) Login denied --> elevel=67

    if !elevel! EQU 0 (
        findstr /m /i /r /c:"250 .* ok" !tmp0! >nul
        if NOT errorlevel 1 (
            findstr /m /i /c:"SPAM" /c:"BLOCKED" !tmp0! >nul
            if NOT errorlevel 1 (
                (
                    echo XXXXXXXXXXXXXXXXX
                    echo XXX ATTENTION XXX Sending could be FAILED: found phrase about spam/blocked in its log.
                    echo XXXXXXXXXXXXXXXXX
                )>!tmp1!
            ) else (
                set /a eml_result=0
                (
                    echo Message sending successfully completed:
                    echo * 1. Found line with retcode = 250 OK:
                    findstr /i /r /c:"250 .* ok" !tmp0!
                    echo * 2. NO lines with rejecting message signs.
                    set mail_sending_result=0
                ) > !tmp1!
            )
            call :bulksho !tmp1! !joblog!
        ) else (

            @rem < 535 5.7.8 Error: authentication failed: This user does not have access rights to this service

            set err_code=0
            for /f "tokens=2 delims= " %%a in ('findstr /i /c:" Error: " !tmp0!') do (
                if .!err_code!.==.0. (
                    set err_code=%%a
                )
            )
            if not .!err_code!.==.0. (
                set mail_sending_result=!err_code!
            )
        )
    ) else (
        set mail_sending_result=!elevel!
        call :sho "### SENDING ERROR ### Check log." !joblog!
    )

    if !eml_result! NEQ 0 (
        call :sho "Check cURL output:" !joblog!
        for /f "tokens=*" %%a in (!tmp0!) do (
            echo !time:~0,8! %%a
            echo !time:~0,8! %%a >>!joblog!
        )
        call :sho "ERROR occured while sending alert using cUrl. Check log !tmp0! and config settings." !joblog!
    )
    del !tmp0!

    call :sho "Leaving routine mail_prepared_eml, mail_sending_result=!mail_sending_result!" !joblog!

    endlocal & set "%~3=%mail_sending_result%"

goto:eof

@rem _=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=_=

:haltHelper
()
exit /b

:show_syntax

set tmplog=%1
    (
        echo "$EMPTY$LINE$"
        echo "$EMPTY$LINE$"
        echo "Syntax:"
        echo "$EMPTY$LINE$"
        echo "%~f0  <FB_major_version>  <sessions_count>  <server_mode>  [ <update_FB_instance> ]"
        echo "$EMPTY$LINE$"
        echo "where:"
        echo "    <FB_major_version> = 25 or 30 or 40 - version of Firebird without dot: 2.5, 3.0, 4.0;"
        echo "    <sessions_count> = number of ISQL sessions to launch"
        echo "    <server_mode> = CS | SC | SS  -  required mode, case-insensitive"
        echo "    <update_FB_instance> = should we upgrade FB instance before test ? Default: 1."
        echo "        If 1 then every run of this script will check new FB snapshot on official site"
        echo "        and replace existing instance if need (with apropriate .debug package)."
        echo "        If 0 then existing FB instance will not be replaced."
        echo "        NOTE: value of ServerMode in firebird.conf is always changed with required value."
        echo "$EMPTY$LINE$"
        echo "Example:"
        echo "$EMPTY$LINE$"
        echo "    %~f0  30  100  ss"
        echo "$EMPTY$LINE$"
        echo "        * run test on FB 3.0,"
        echo "        * launch 100 ISQL sessions,"
        echo "        * change config for Firebird work in mode 'Super',"
        echo "        * upgrade existing FB instance (default for <update_FB_instance>)"
        echo "$EMPTY$LINE$"
    ) >!tmplog!

    call :remove_enclosing_quotes !tmplog!

    type !tmplog!

    goto :final

:final
    call :haltHelper 2> nul
