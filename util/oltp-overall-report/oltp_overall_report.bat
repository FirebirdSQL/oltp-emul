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

set ISC_USER=
set ISC_PASSWORD=

set err_setenv=0

set cfg=%~dpn0_config.win

::::::::::::::::::::::::::::::::
:::: R E A D    C O N G I G ::::
::::::::::::::::::::::::::::::::
echo Parsing config file ^>%cfg%^<. Please wait. . .

call :readcfg %cfg% err_setenv
if .!err_setenv!.==.1. (
    call :no_env !abendlog!
)


md !LOGDIR! 2>nul
if not exist !LOGDIR!\nul (
    set msg=Can not create directory for logs: !LOGDIR!
    echo !msg!
    echo !msg! >>%~dpn0.abend.log
    goto final
)
md !DETAILS_DIR! 2>nul
if not exist !DETAILS_DIR!\nul (
    set msg=Can not create directory for logs: !LOGDIR!
    echo !msg!
    echo !msg! >>%~dpn0.abend.log
    goto final
)

set can_upload=!FTP_UPLOAD_ENABLED!

set dts=19000101000001
call :get_ansi_dts dts

set joblog=!LOGDIR!\%~n0.!dts!.log
set tmpsql=!LOGDIR!\%~n0.!dts!.sql
set tmperr=!LOGDIR!\%~n0.!dts!.err
set tmplog=!LOGDIR!\%~n0.!dts!.tmp
set tmpfdb=!LOGDIR!\%~n0.!dts!.fdb
set tmplst=!LOGDIR!\%~n0.!dts!.lst
set tmpvbs=!LOGDIR!\%~n0.extract-from-zip.tmp.vbs
set htmfile=!LOGDIR!\%~n0.tmp.html

del !joblog! 2>nul

@rem ####################################################
@rem ###    p a r s e     o l t p 4 0 _ c o n f i g   ###
@rem ####################################################

for /f "tokens=1-2 delims== " %%a in ('findstr /r /v /c:"#" !oltp40_config! ^| findstr /i /c:"=" ^| findstr /i /r /c:"tmpdir[ ]*=" /c:"dbnm[ ]*=" /c:"usr[ ]*=" /c:"pwd[ ]*=" /c:"fbc[ ]*=" /c:"mon_unit_perf[ ]*=" /c:"results_storage_fbk[ ]*="') do (
    if /i "%%a" == "usr" (
        set DBA_USER=%%b
    )
    if /i "%%a" == "pwd" (
        set DBA_PSWD=%%b
    )
    if /i "%%a" == "fbc" (
        set HEAD_FBC=%%b
        for /f %%x in ("!HEAD_FBC!\") do (
            set tp=%%~dpnx
            set tp=!tp:\\=\!
            set HEAD_FBC=!tp:~0,-1!
        )
        set FB_CLNT=!HEAD_FBC!\fbclient.dll
    )
    if /i "%%a" == "mon_unit_perf" (
        set o40_mon_perf=%%b
    )
    if /i "%%a" == "results_storage_fbk" (
        set FB4x_FBK=%%b
    )
)

if "!FB4x_FBK!"=="" (
    call :sho "Parameter 'results_storage_fbk' must be defined in OLTP-EMUL config file '!oltp40_config!'" !joblog!
    goto final
)

@rem ####################################################
@rem ###    p a r s e     o l t p 3 0 _ c o n f i g   ###
@rem ####################################################

for /f "tokens=1-2 delims== " %%a in ('findstr /r /v /c:"#" !oltp30_config! ^| findstr /i /c:"=" ^| findstr /i /r /c:"dbnm[ ]*="  /c:"mon_unit_perf[ ]*=" /c:"results_storage_fbk[ ]*="') do (
    if /i "%%a" == "mon_unit_perf" (
        set o30_mon_perf=%%b
    )
    if /i "%%a" == "results_storage_fbk" (
        set FB3x_FBK=%%b
    )
)

if "!FB3x_FBK!"=="" (
    call :sho "Parameter 'results_storage_fbk' must be defined in OLTP-EMUL config file '!oltp30_config!'" !joblog!
    goto final
)


for /f %%a in ("!FB4x_FBK!") do (
    @rem Directory where database with overall results will be created and backed up:
    set DB_OVERALL_DIR=%%~dpa
    for /f %%x in ("!DB_OVERALL_DIR!\") do (
        set tp=%%~dpnx
        set tp=!tp:\\=\!
        set DB_OVERALL_DIR=!tp:~0,-1!
    )
    @rem Name of file with overall results:
    set DB_OVERALL_FILE=!DB_OVERALL_DIR!\%~n0.tmp.fdb
)

for /d %%f in (!FB4x_FBK!,!FB3x_FBK!) do (
    if not exist %%f (
        call :sho "File %%f not exists. Run OLTP-EMUL at least one time for this file be created with results of run." !joblog!
        goto final
    )
)

set dbauth=-user !DBA_USER! -password !DBA_PSWD!
set dbconn=localhost:!DB_OVERALL_FILE!

@rem ------------------------------------

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

@rem ------------------------------------

set run_cmd=!HEAD_FBC!\fbsvcmgr localhost:service_mgr !dbauth! info_server_version
call :sho "Attempt to get SERVER version in !HEAD_FBC! folder. Command: !run_cmd!" !joblog!
cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
call :catch_err run_cmd !joblog! !tmperr! !tmplog!
call :bulksho !tmplog! !joblog!

@rem ------------------------------------

for /d %%f in (!FB4x_FBK!,!FB3x_FBK!) do (
    set run_cmd=!HEAD_FBC!\fbsvcmgr localhost:service_mgr !dbauth! action_restore res_metadata_only bkp_file %%f dbname !tmpfdb!
    call :sho "Check whether %%f is valid .fbk file: attempt to restore metadata. Command:" !joblog!
    call :sho "!run_cmd!" !joblog!
    cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
    call :catch_err run_cmd !joblog! !tmperr! !tmplog!
    call :bulksho !tmplog! !joblog!
    call :sho "Restore from %%f passed." !joblog!
    del !tmpfdb!
)

call :sho "Check presence of Python interpreter in 'PYTHON_HOME'= !PYTHON_HOME! folder." !joblog!

!PYTHON_HOME!\python.exe -V >!tmplog! 2>&1
set elevel=!errorlevel!
call :bulksho !tmplog! !joblog! 1
if !elevel! NEQ 0 (
    call :sho "Python interpreter not found in !PYTHON_HOME! folder. Install it first." !joblog!
    call :final
) else (
    findstr /i /c:"Python" !tmplog! >nul
    if errorlevel 1 (
        call :sho "!PYTHON_HOME!\python.exe doew not show its version. Possible this is another executable than required." !joblog!
    )
)

call :sho "Check presence of PIP utility" !joblog!

!PYTHON_HOME!\Scripts\pip.exe -V >!tmplog! 2>&1
set elevel=!errorlevel!
call :bulksho !tmplog! !joblog! 1
if !elevel! NEQ 0 (
    call :sho "PIP utility not found in !PYTHON_HOME!\Scripts folder. Install it first." !joblog!
    call :final
)

findstr /i /c:"pip" !tmplog! | findstr /i /c:"python" >nul
if not errorlevel 1 (
    call :sho "PIP utility found and issues expected output." !joblog!
) else (
    call :sho "PIP output does not match to expected." !joblog!
    call :final
)
call :sho "Check presence of required Python packages. Command: pip freeze" !joblog!

!PYTHON_HOME!\Scripts\pip.exe freeze 1>!tmplog! 2>&1

set py_missed_packages=0
for /d %%a in (fdb) do (     	
    call :sho "Check for package: %%a" !joblog!
    findstr /i /c:"%%a==" !tmplog! 1>nul 2>&1
    if NOT errorlevel 1 (
        call :sho "OK: found package %%a" !joblog!
    ) else (
        call :sho "FAILED: package %%a not installed." !joblog!
        set py_missed_packages=1
    )
)

if !py_missed_packages! GTR 0 (
  call :sho "At least one package not installed." !joblog!
  call :final
)

if .!can_upload!.==.1. (
    
    set retcode=1
    call :ftp_upload probe n/a retcode
    if !retcode! NEQ 0 (
        set can_upload=0
    )

    @rem call :ftp_upload actual C:\FBTESTING\OLTP-EMUL.TMP\src\oemul-win-refactoring-draft.7z retcode
)
@rem can_upload==1


@rem ----------------------------------------
for /d %%p in (!LOGDIR!) do (

    set cleanup_dir=%%p
    call :sho "Delete all log and temporary files with age at least !LOGS_MAX_AGE! days from !cleanup_dir!" !joblog!

    del !tmplst! 2>nul
    for /d %%x in ( htm,html ) do (
       echo forfiles /s /p "!DETAILS_DIR!" /m "*.%%x" /d -!LOGS_MAX_AGE! /c "cmd /c echo @path
       forfiles /s /p "!DETAILS_DIR!" /m "*.%%x" /d -!LOGS_MAX_AGE! /c "cmd /c echo @path >>!tmplst!" 1>>!joblog! 2>&1
    )
    for /d %%x in ( log,tmp,err,sql,lst ) do (
       forfiles /s /p "!cleanup_dir!" /m "*.tmp.%%x" /d -!LOGS_MAX_AGE! /c "cmd /c echo @path >>!tmplst!" 1>>!joblog! 2>&1
    )
    if exist !tmplst! (
        for /f %%a in ( !tmplst! ) do (
            if not .%%a.==."!joblog!". (
                @rem call :sho "Removing old file %%a" !joblog!
                echo del %%a 1>>!joblog!
                del %%a 1>>!joblog! 2>&1
                if exist %%a (
                    call :sho "WARNING: could not drop file %%a from disk. Perhaps it is opened by another process." !joblog!
                )
            )
        )
    )
    del !tmplst! 2>nul
)

@rem ----------------------------------------

del !DETAILS_DIR!\*.htm* 2>nul

if not exist !DB_OVERALL_FILE! (
    @rem ???? --> if not exist !DB_OVERALL_FILE! if .!RECREATE_DB!.==.0. (
    set RECREATE_DB=1
    call :sho "Database !DB_OVERALL_FILE! not exists. Value 'RECREATE_DB' is forcedly set to 1." !joblog!
) else (
    set run_cmd=!HEAD_FBC!\fbsvcmgr localhost:service_mgr !dbauth! action_repair rpr_validate_db dbname !DB_OVERALL_FILE!
    call :sho "Database !DB_OVERALL_FILE! DOES exist. Check whether it is valid. Command:" !joblog!
    call :sho "!run_cmd!" !joblog!
    cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

    for /f "usebackq tokens=*" %%a in ('!tmperr!') do set err_size=%%~za
    if .!err_size!.==.. set /a err_size=0
    if !err_size! GTR 0 (
        set RECREATE_DB=1
        call :catch_err run_cmd !joblog! !tmperr! !tmplog! n/a 0
        call :sho "Validation of !DB_OVERALL_FILE! failed. Value of RECREATE_DB is changed to 1." !joblog!
    ) else (
        call :sho "Validation of !DB_OVERALL_FILE! passed." !joblog!
    )
)

@rem ----------------------------------------

@rem Replace relative path to decompress binaries with absolute one:
set DECOMPRESS_7Z=!DECOMPRESS_7Z:..\..=%GRANDPDIR%!
set DECOMPRESS_7Z=!DECOMPRESS_7Z:..=%PARENTDIR%!
set DECOMPRESS_ZST=!DECOMPRESS_ZST:..\..=%GRANDPDIR%!
set DECOMPRESS_ZST=!DECOMPRESS_ZST:..=%PARENTDIR%!

if not exist !DECOMPRESS_7Z! (
    call :sho "Parameter 'DECOMPRESS_7Z' points to missed file: !DECOMPRESS_7Z!" !joblog!
    call :final
)
if not exist !DECOMPRESS_ZST! (
    call :sho "Parameter 'DECOMPRESS_ZST' points to missed file: !DECOMPRESS_ZST!" !joblog!
    call :final
)

@rem Generate temporary .vbs script in !LOGDIR! for extracting binaries of 7z.exe and zstd.exe
@rem from apropriate .zip files, see config parameters 'DECOMPRESS_7Z' and 'DECOMPRESS_ZST':
@rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

(
    echo ' Original text:
    echo ' https://social.technet.microsoft.com/Forums/en-US/8df8cbfc-fe5d-4285-8a7a-c1fb201656c8/automatic-unzip-files-using-a-script?forum=ITCG
    echo ' Examples:
    echo '     %systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !DECOMPRESS_7Z! !LOGDIR!
    echo '     %systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !DECOMPRESS_ZST! !LOGDIR!

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

call :sho "Extract compressors from .zip files to !LOGDIR!" !joblog!
%systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !DECOMPRESS_7Z! !LOGDIR! 1>!tmperr! 2>&1
%systemroot%\system32\cscript //nologo //e:vbs !tmpvbs! !DECOMPRESS_ZST! !LOGDIR! 1>>!tmperr! 2>&1

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
for /f %%a in ("!DECOMPRESS_7Z!") do (
    set DECOMPRESS_7Z=!LOGDIR!\%%~na
)
for /f %%a in ("!DECOMPRESS_ZST!") do (
    set DECOMPRESS_ZST=!LOGDIR!\%%~na
)

@rem @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

@rem ----------------------------------------

@rem If value of <mon_unit_perf> not equal to 2 then warning will issue
@rem about pissible absence of monitoring data related to memory consumption.

if not .!o30_mon_perf!.==.2. (
    call :sho "WARNING. Config parameter 'mon_unit_perf' in !oltp30_config! has value !o30_mon_perf!. Report can miss data about memory consumption for runs on FB 3.x." !joblog!
)
if not .!o40_mon_perf!.==.2. (
    call :sho "WARNING. Config parameter 'mon_unit_perf' in !oltp40_config! has value !o30_mon_perf!. Report can miss data about memory consumption for runs on FB 4.x." !joblog!
)


if .!RECREATE_DB!.==.0. (
    call :sho "Config parameter RECREATE_DB=0. Existing database will be used." !joblog!
) else (
    if exist !DB_OVERALL_FILE! del !DB_OVERALL_FILE!
    if exist !DB_OVERALL_FILE! (
        call :sho "Can not remove temporary database !DB_OVERALL_FILE!" !joblog!
        goto :final
    )

    (
       echo create database '!dbconn!' user '!DBA_USER!' password '!DBA_PSWD!';
    ) >!tmpsql!
    set run_cmd=!HEAD_FBC!\isql -q -i !tmpsql!
    call :sho "Attempt to create database. Command: !run_cmd!" !joblog!
    cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

    call :catch_err run_cmd !joblog! !tmperr! !tmplog!

    del !tmpsql!

    !HEAD_FBC!\gfix -w async !DB_OVERALL_FILE! -user !DBA_USER!

    set run_cmd=!HEAD_FBC!\isql !dbconn! !dbauth! -i !THIS_DIR!\oltp_overall_report_DDL.sql
    call :sho "Create database objects. Command: !run_cmd!" !joblog!
    cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

    call :catch_err run_cmd !joblog! !tmperr! !tmplog!

)
@rem RECREATE_DB = 0 | 1

for /d %%a in (!FB4X_FBK!,!FB3X_FBK!) do (
    set oltp_tmp_restored=%%~dpna.tmp.fdb
    set run_cmd=!HEAD_FBC!\gbak -rep %%a localhost:!oltp_tmp_restored! !dbauth!
    echo !run_cmd!
    cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!
    call :catch_err run_cmd !joblog! !tmperr! !tmplog!

    if .%%a.==.!FB4X_FBK!. (
        set fb_vers_in_source_db=4.
    ) else if .%%a.==.!FB3X_FBK!. (
        set fb_vers_in_source_db=3.
    )  else (
        set fb_vers_in_source_db=UNKNOWN_SOURCE
    )

    (
        echo set echo on;
        echo set bail on;
        echo set heading off;
        echo -- RECREATE_DB = 0: We load ONLY NEW data from source databases:
        echo -- Otherwise we load ALL data from source databases:
        echo select msg from sp_gather_results( 'localhost:!oltp_tmp_restored!', '!DBA_USER!', '!DBA_PSWD!', !RECREATE_DB!, '!fb_vers_in_source_db!' ^);
        echo commit;
    ) > !tmpsql!

    set run_cmd=!HEAD_FBC!\isql -q !dbconn! !dbauth! -i !tmpsql! -ch utf8

    call :sho "Gather results from !oltp_tmp_restored!. Command: !run_cmd!" !joblog!
    cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

    call :catch_err run_cmd !joblog! !tmperr! !tmplog!

   
    @rem Remove excessive ascii_char_13 *and* trailing spaces from each line:
    call :remove_CR_from_file !tmplog!
    @rem -- slow when lot of lines -- call :bulksho !tmplog! !joblog!
    type !tmplog! >> !joblog!
    call :sho "Completed. Details see in !joblog!" !joblog!

    set run_cmd=!HEAD_FBC!\gfix -shut full -force 0 localhost:!oltp_tmp_restored! !dbauth!
    call :sho "Change temporary DB state to full shutdown in order to remove it. Command: !run_cmd!" !joblog!
    cmd /c !run_cmd! 1>!tmplog! 2>!tmperr!

    call :catch_err run_cmd !joblog! !tmperr! !tmplog!

    del !oltp_tmp_restored!
    del !tmplog!

    @rem !HEAD_FBC!\gfix -online localhost:!oltp_tmp_restored! !dbauth!

)


set PYTHON_CALLER_JOBLOG=!joblog!

@echo ###############################
@echo ###  c a l l   P y t h o n  ###
@echo ###############################

!PYTHON_HOME!\python %~dpn0.py 2>!tmperr!
call :catch_err run_cmd !joblog! !tmperr! !tmplog!

set /a broken_b64_cnt=0
set /a broken_zip_cnt=0

for /f %%a in ('dir /b !DETAILS_DIR!\*.b64') do (
    for /f %%b in ("!DETAILS_DIR!\%%a") do (

        set decoded_zip=!DETAILS_DIR!\%%~nb
        set run_cmd=certutil -decode !DETAILS_DIR!\%%a !decoded_zip!

        call :sho "Decode data from base64 to result of compression. Command: !run_cmd!" !joblog!
        del !decoded_zip! 2>nul
        if exist !decoded_zip! (
            call :sho "WARNING: could not drop file !decoded_zip! from disk. Perhaps it is opened by another process." !joblog!
        ) else (
            @rem Now we decode from b64 with assigning required extension: .7z, .zst, .zip.
            @rem ::: NB ::: certutil redirects errors to STDOUT! We have to check output for strings
            @rem with word 'FAILED:' or ' ERROR_', e.g.:
            @rem DecodeFile returned The data is invalid. 0x8007000d (WIN32: 13 ERROR_INVALID_DATA)
            @rem CertUtil: -decode command FAILED: 0x8007000d (WIN32: 13 ERROR_INVALID_DATA)
            @rem CertUtil: The data is invalid.

            cmd /c !run_cmd! 1>!tmperr! 2>&1
            findstr /m /i /c:" FAILED:" /c:" ERROR_" !tmperr! 1>nul
            if NOT errorlevel 1 (

                @rem     set run_cmd=!%1!
                @rem     set main_log=%2
                @rem     set err_file=%3
                @rem     set tmp_file=%4
                @rem     set addi_call=%5
                @rem     set do_abend=%6

                call :catch_err run_cmd !joblog! !tmperr! !tmplog! n/a 0
                @rem                1       2       3        4      5  6
            ) else (
                del !tmperr!
            )

            if exist !tmperr! (

                set /a broken_b64_cnt=!broken_b64_cnt!+1
                set broken_b64_name=!DETAILS_DIR!\broken.%%~nxb

                call :sho "### ACHTUNG ### could not decode data from base-64 format." !joblog!
                call :sho "Problem occured with: !broken_b64_name!" !joblog!
                move !DETAILS_DIR!\%%a !broken_b64_name!

            ) else (
                del !DETAILS_DIR!\%%a
            )
        )


        if exist !decoded_zip! (
            set extract_cmd=UNKNOWN
            for /f %%c in ("!decoded_zip!") do (
                set html_detl_name=!DETAILS_DIR!\%%~nc.html
                set compressed_ext=%%~xc

                set is_stack_trace=0
                echo !html_detl_name! | findstr /i /c:"crash" > nul
                if NOT errorlevel 1 (
                    set is_stack_trace=1
                )

                if .!is_stack_trace!.==.1. (
                    @rem DO NOT delete this file, it is preliminary created HTML with heading info about crash
                    @rem We have to APPEND stack trace text to this file rather than to overwrite it.
                    echo ^<pre^> >> !html_detl_name!
                ) else (
                    del !html_detl_name! 2>nul
                )

                @rem All following extract commands must use DOUBLE ARROW (">>") for redirecting:
                @rem ############################################################################
                if /i "!compressed_ext!"==".zip" (
                    @rem ### ACHTUNG ###
                    @rem Value of $DECOMPRESS_ZIP must be always equal to $DECOMPRESS_7Z and is 7za utility.
                    @rem DO NOT use '-tzip' as command switch for 7za when extract files that were compressed
                    @rem by /usr/bin/gzip: this leads to "Open ERROR: Can not open the file as [zip] archive"
                    @rem Fortunately, 7-Zip can properly detect type of archieve without any hints (when extracts)
                    set extract_cmd="!DECOMPRESS_7Z! e -y -so !decoded_zip! ^>^> !html_detl_name!"
                ) else if /i "!compressed_ext!"==".7z" (
                    set extract_cmd="!decompress_7z! e -y -so !decoded_zip! ^>^> !html_detl_name!"
                ) else (
                    set extract_cmd="!decompress_zst! -f -c -d !decoded_zip! ^>^> !html_detl_name!"
                )

                call :sho "Decompress html content, command:" !joblog!
                echo !extract_cmd!
                echo !extract_cmd! >>!joblog!
                @rem DO NOT >>> call :sho "!extract_cmd!" !joblog!

                @rem ############################################################
                @rem ### Decompress OLTP-EMUL report: .zip/.7z/.zst --> HTML ###
                @rem ############################################################

                cmd /c !extract_cmd! 1>!tmplog! 2>!tmperr!
                set elev=!errorlevel!

                if !elev! NEQ 0 (
                    call :sho "### ACHTUNG ### could not extract data from !decoded_zip!" !joblog!
                    set broken_zip_name=!DETAILS_DIR!\broken.%%~nxc
                    call :sho "Problem occured with: broken_zip_name" !joblog!
                    move !decoded_zip! !broken_zip_name!

                    @rem     set run_cmd=!%1!
                    @rem     set main_log=%2
                    @rem     set err_file=%3
                    @rem     set tmp_file=%4
                    @rem     set addi_call=%5
                    @rem     set do_abend=%6

                    call :catch_err !extract_cmd! !joblog! !tmperr! !tmplog! n/a 0
                    
                    set /a broken_zip_cnt=!broken_zip_cnt!+1

                ) else (
                    @rem do NOT use here: zst writes to STDERR its actions! ==> call :catch_err run_cmd !joblog! !tmperr! !tmplog!
                    del !tmplog!
                    del !decoded_zip!
                    call :sho "Completed." !joblog!

                    if .!is_stack_trace!.==.1. (
                        (
                            echo ^</pre^>
                            echo ^</body^>
                            echo ^</html^>
                            echo.
                        ) >> !html_detl_name!
                    )

                )

            )
            @rem for /f %%c in ("!decoded_zip!") do
        ) else (
            call :sho "No file to be extracted from, skip decompression." !joblog!
        )
        @rem exist !decoded_zip!
    )
)

if !broken_b64_cnt! EQU 0 (
    call :sho "All files have been decoded successfully." !joblog!
) else (
    call :sho "### ACHTUNG ### Total files that could not be decoded from base-64: !broken_b64_cnt!" !joblog!
)

if !broken_zip_cnt! EQU 0 (
    call :sho "All decoded files have been decompressed successfully." !joblog!
) else (
    call :sho "### ACHTUNG ### Total files that could not be decompressed: !broken_zip_cnt!" !joblog!
)

@rem =+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+=+

set cleanup_error=0
for /d %%f in (!tmpsql!,!tmperr!,!tmplog!) do (
    if exist %%f (
        del %%f 2>nul
        if exist %%f (
            set cleanup_error=1
        )
    )
)

if !cleanup_error! GTR 0 (
    set msg=Could NOT remove at least one of work files for this script. Job terminated.
    echo !msg!
    echo !msg! >>%~dpn0.abend.log
    goto final
)

@rem #####################################################################
@rem ###   c o m p r e s s     a n d    u p l o a d      r e p o r t   ###
@rem #####################################################################

if !can_upload! EQU 1 (
    set compressed_report=!LOGDIR!\%~n0.!dts!.7z
    set run_cmd=!DECOMPRESS_7Z! u -mx9 -mfb273 !compressed_report! !LOGDIR!\oltp-overall-main.html !LOGDIR!\oltp-overall-main.css !DETAILS_DIR!\
    call :sho "Compress report before uploading. Command: !run_cmd!" !joblog!
    cmd /c "!run_cmd!" 1>!tmplog! 2>!tmperr!
    set elev=!errorlevel!
    if !elev! GTR 0 (
        call :sho "FAILED. Content of log:" !joblog!
        (
            echo =============================
            type !tmperr!
            echo =============================
        ) >> !tmplog!
        type !tmplog!
        type !tmplog! >>!joblog!
    )
    del !tmplog!
    del !tmperr!
    if !elev! GTR 0 (
        del !compressed_report! 2>nul
        goto :final
    )

    set retcode=1
    call :ftp_upload actual !compressed_report! retcode

) else (
    call :sho "SKIP upload action: variable 'can_upload'=!can_upload!" !joblog!
)
@rem !can_upload! EQU 1 or 0

@rem Cleanup: remove extracted binaries for compression:
for /d %%a in ("!DECOMPRESS_7Z!", "!DECOMPRESS_ZST!") do (
    if /i "%%~dpa"=="!logdir!\" (
        call :sho "Deleting file %%a" !joblog!
        del %%a
    )
)

echo.
(
    echo ###########################################################################
    echo Generated report name:
    echo !LOGDIR!\oltp-overall-main.html
    echo ###########################################################################
) >!tmplog!
call :bulksho !tmplog! !joblog!
echo.


call :sho "Job completed, exit from %~f0." !joblog!

goto :final

@rem ###########################################################################
@rem #####    a u x i l i a r y    i n t e r n a l    f u n c t i o n s    #####
@rem ###########################################################################


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

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

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

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

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
@rem :sho

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

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
       @rem call :sho "!msg!" !joblog!
    )
    if not .!keep_tmp!.==.1. (
        del !tmplog!
    )
endlocal & goto:eof
@rem :bulksho

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

:get_ANSI_dts
    setlocal
    if .%1.==.. (
        echo Problem in subroutine get_cscript_dts: output argument was not provided.
        echo JOB IS TERMINATED.
        goto final
    )

    set dts_varname=%1
    call :get_cscript_dts dts_varname

    endlocal & set "%~1=%dts_varname%"
goto:eof

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

:get_cscript_dts
    @rem to be removed, replaced 13.12.19
    setlocal
    if .%1.==.. (
        echo Problem in subroutine get_cscript_dts: output argument was not provided.
        echo JOB IS TERMINATED.
        goto final
    )

    set tmppath=!LOGDIR!
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
@rem :get_cscript_dts

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

:trim
    setLocal
    @rem EnableDelayedExpansion
    set Params=%*
    for /f "tokens=1*" %%a in ("!Params!") do endLocal & set %1=%%b
goto:eof

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

:readcfg
    set _cfg_file=%1
    set err_setenv=0
    @rem ::: NB ::: Space + TAB should be inside `^[ ]` pattern!
    @rem ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    for /F "tokens=*" %%a in ('findstr /i /r /c:"^[ 	]*[a-z,0-9]" %_cfg_file%') do (
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
    set _cfg_file=
    set _tmp_par_=
    set _tmp_val_=
    set %~2=%err_setenv%

goto:eof
@rem :readcfg

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

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
    set remove_extra_cr_vbs=%%~dparemove_excessive_CR.tmp.vbs
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
            echo.
            echo     ' Remove excessive LINE_FEED characters:
            echo     text = replace( text, vblf ^& vblf, vblf ^)
            echo.
            echo     ' 25.06.2020. Remove TRAILING spaces:
            echo     ' ###################################
            echo     ' 1. Temporary remove CR/LF:
            echo     text = replace( text, vbcr ^& vblf, "" ^)
            echo     ' 2. Remove trailing spaces and restore CR/LF:
            echo     text = RTrim( text ^) ^& vbcr ^& vblf
            echo.
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

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

:display_results
    setlocal
    set batch_log=%1
    set stdout_file=%2
    set stderr_file=%3
    call :sho "----- R E S U L T S -----" !batch_log!
    for /f "tokens=*" %%a in ('type !stdout_file!') do (
        echo.    STDOUT: %%a
        echo.    STDOUT: %%a >>!batch_log!
    )
    del !stdout_file!

    if not .!stderr_file!.==.. (
        for /f "tokens=*" %%a in ('type !stderr_file!') do (
            echo.    STDERR: %%a
            echo.    STDERR: %%a >>!batch_log!
        )
        del !stderr_file!
    )
    call :sho "-------------------------" !batch_log!
goto:eof
@rem :display_results

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

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
            if not .!addi_call!.==.. (
                if /i not .!addi_call!.==.n/a. (
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

        call :bulksho !tmp_file! !main_log!

        if .!do_abend!.==.1. (
            goto final
        )
    ) else (
        del %err_file%
    )
    endlocal
goto:eof
@rem :catch_err

@rem -=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+-=+

:remove_outer_quotes
    setlocal
    @rem https://www.dostips.com/DtTutoFunctions.php#FunctionTutorial.ParsingFunctionArguments
    @rem To strip of the double quotes in an arguments value the tilde modifier, i.e. use %~2 instead of %2.
    set result=%~1

    if .1.==.0. (
        set left_char=!result:~0,1!
        set righ_char=!result:~-1!
        @rem REMOVE LEADING AND TRAILING DOUBLE QUOTES:
        @rem ##########################################
        set chk=!left_char:"=!
        if .!chk!.==.. (
           set chk=!righ_char:"=!
           if .!chk!.==.. (
              set result=!result:~1,-1!
           )
        )
    )
    endlocal & set "%~2=%result%"
goto:eof
@rem :remove_outer_quotes

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

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

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:chk4num
    setlocal
    set num_chk=,!%1!,
    set num_lst=!%2!
    set result=1
    if "!num_lst:%num_chk%=!"=="%num_lst%" set result=0
    endlocal & set "%~3=%result%"
goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

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

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:create_oemcp_converter

@rem call :gather_hwinfo %tmpdir% %log4all% %htm_file%
setlocal

set tmpdir=%1
set log4all=%2
set oem_vbs_converter=%3

@rem set oem_vbs_converter=%tmpdir%\oem_converter.vbs.tmp

set tmp1=%tmpdir%\hwinfo.1.tmp
set tmp2=%tmpdir%\hwinfo.2.tmp
@rem Output language. English: 409; russian: 419
set lang_id=409

set oemcp=
reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v OEMCP 1>!tmp1! 2>!tmp2!
set /a errsize=0
for /f %%a in ("!tmp2!") do (
    set /a errsize=%%~za
)
if !errsize! EQU 0 (
    for /f "tokens=3" %%a in ('findstr /c:"OEMCP" !tmp1!') do (
        @rem oemcp=cp866 etc:
        set oemcp=cp%%a
    )
    del !tmp1!
) else (
    call :sho "FAIL. Could not find OEM code page in registry." %log4all%
    call :bulksho !tmp2! %log4all%
    endlocal & goto:eof
)


@rem https://en.wikipedia.org/wiki/Windows_code_page#DOS_code_pages
@rem 437 - IBM PC US, 8-bit SBCS extended ASCII. Known as OEM-US
@rem 708 - Arabic, extended ISO 8859-6 (ASMO 708)
@rem 720 - Arabic, retaining box drawing characters in their usual locations
@rem 737 - "MS-DOS Greek". Retains all box drawing characters. More popular than 869.
@rem 775 - "MS-DOS Baltic Rim"
@rem 850 - "MS-DOS Latin 1". Full (re-arranged) repertoire of ISO 8859-1; aka DOS Latin 1
@rem 852 - "MS-DOS Latin 2"
@rem 855 - "MS-DOS Cyrillic", for South Slavic languages. Not to be confused with cp866.
@rem 857 - "MS-DOS Turkish"
@rem 858 - Western European with euro sign
@rem 860 - "MS-DOS Portuguese"
@rem 861 - "MS-DOS Icelandic"
@rem 862 - "MS-DOS Hebrew"
@rem 863 - "MS-DOS French Canada"
@rem 864 - Arabic
@rem 865 - "MS-DOS Nordic"
@rem 866 - "Cyrillic (DOS)", cp866.
@rem 869 - "MS-DOS Greek 2", IBM869. Full (re-arranged) repertoire of ISO 8859-7.
@rem 874 - Thai, also used as the ANSI code page, extends ISO 8859-11

(

    echo ' http://forum.script-coding.com/viewtopic.php?id=997
    echo ' https://stackoverflow.com/questions/31435662/vba-save-a-file-with-utf-8-without-bom/31436631#31436631
    echo ' Usage: cscript //nologo //e:vbscript !oem_vbs_converter! ^<input-file-in-OEM-codepage^> ^<output-file^> ^<codepage-for-output-file^>
    echo ' Samples:
    echo '     cscript //nologo //e:vbscript !oem_vbs_converter! hwinfo.oem.txt tmp.utf8.tmp utf-8
    echo '     cscript //nologo //e:vbscript !oem_vbs_converter! hwinfo.oem.txt tmp.1251.tmp windows-1251
    echo ' To obtain id of OEM and Windows codepage one can use:
    echo '     reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v OEMCP | findstr /c:"OEMCP"
    echo '     reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v ACP | findstr /c:"ACP"
    echo.
    echo set objArgs = WScript.Arguments
    echo sourFile = objArgs(0^)
    echo targFile = objArgs(1^)
    echo targCset = objArgs(2^) ' charset for encoding new file: UTF-8, Windows-1251 etc
    echo.
    echo Const adTypeBinary = 1
    echo Const adTypeText   = 2
    echo Const adSaveCreateOverWrite = 2
    echo.
    echo Dim objStreamSource : Set objStreamSource = CreateObject("ADODB.Stream"^)
    echo Dim objStreamTarget : Set objStreamTarget = CreateObject("ADODB.Stream"^)
    echo.
    echo with objStreamSource
    echo     .Type = adTypeText
    echo.
    echo     ' .Charset was substituted here at runtime after parsing result of command:
    echo     ' reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Nls\CodePage /v OEMCP
    echo     .Charset = "!oemcp!"
    echo.
    echo     .Open(^)
    echo     .LoadFromFile( sourFile ^)
    echo     Text = .ReadText(^)
    echo     .Close(^)
    echo.
    echo     .Open(^)
    echo     .Charset = targCset ' e.g. "UTF-8", "windows-1251" etc
    echo     .WriteText(Text^) ' NOTE: when target encoding is UTF-8 then file will contain unicode BOM in first three bytes 
    echo    .Position = 0
    echo    if UCase( targCset ^) = UCase( "UTF-8" ^) then
    echo        .Position = 3 ' we have to SKIP writing BOM into target UTF-8 file
    echo    end if
    echo end with
    echo.
    echo With objStreamTarget
    echo   .Type    = adTypeBinary
    echo   .Open
    echo   objStreamSource.CopyTo objStreamTarget
    echo   .SaveToFile targFile, adSaveCreateOverWrite
    echo End With
    echo.
    echo objStreamSource.close
    echo objStreamTarget.Close

) > !oem_vbs_converter!

endlocal
goto:eof
@rem ^
@rem end of 'create_oemcp_converter' subroutine

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:ftp_upload
    setlocal
    @rem call :ftp_upload probe n/a retcode

    set mode=%1
    set file_to_upload=%2

    call :sho "Intro routine ftp_upload. Mode: !mode!" !joblog!

    @rem Generate scenario to be executed by standard Windows ftp.exe utility
    (
        echo open !FTP_UPLOAD_HOST! !FTP_UPLOAD_PORT!
        @rem echo open 192.0.0.0 !FTP_UPLOAD_PORT!
        echo !FTP_UPLOAD_USER!
        echo !FTP_UPLOAD_PSWD!
        echo ^^!:: Usage:
        echo ^^!:: ftp -i -s:!tmplst!
        echo ^^!:: =================================================
        echo cd !FTP_UPLOAD_DIR!
        echo binary
        if /i .!mode!.==.probe. (
            set file_to_upload=!tmplst!
            echo put !file_to_upload!
            echo dir
            for /f %%a in ("!tmplst!") do (
                echo delete %%~nxa
            )
            echo dir
        ) else if /i .!mode!.==.actual. (
            echo put !file_to_upload!
        )
        echo disconnect
        echo bye
    ) >!tmplst!

    call :sho "Prepared ftp scenario for uploading:" !joblog!
    for /f "tokens=*" %%a in (!tmplst!) do (
        set line=%%a
        if .!line!.==.!FTP_UPLOAD_PSWD!. (
            echo.    ^<password^>
            @rem echo.    !FTP_UPLOAD_PSWD!
        ) else (
            echo.    !line!
        )
    )
    set run_cmd=ftp -i -s:!tmplst!
    call :sho "Command: !run_cmd!" !joblog!
    cmd /c !run_cmd! 1>!tmplog! 2>&1
    
    for /f "usebackq tokens=*" %%a in ('!file_to_upload!') do (
        set file_size=%%~za
    )

    findstr /i /c:"Connection refused" /c:"Connection timed out" !tmplog! >nul
    if NOT errorlevel 1 (
        call :sho "Problems encountered while trying to CONNECT to FTP server:" !joblog!
        call :bulksho !tmplog! !joblog!
        call :sho "You can temporary change parameter 'FTP_UPLOAD_ENABLED' to 0 for work without FTP uploading." !joblog!
        goto :final
    )

    @rem https://en.wikipedia.org/wiki/List_of_FTP_server_return_codes
    @rem 421 Service not available, closing control connection. This may be a reply to any command if the service knows it must shut down.
    @rem 425 Can't open data connection.
    @rem 426 Connection closed; transfer aborted.
    @rem 430 Invalid username or password
    @rem 434 Requested host unavailable. 
    @rem 530 Login or password incorrect
    @rem 530 This server does not allow plain FTP. You have to use FTP over TL
    @rem 550 - smth wrong file dir/file name

    findstr /i /r /b /c:"421 " /c:"425 " /c:"426 " /c:"430 " /c:"434 " /c:"530 " /c:"550 " !tmplog! 1>!tmperr! 2>&1
    if NOT errorlevel 1 (
        call :sho "Problems encountered while performing scenario for FTP server:" !joblog!
        call :bulksho !tmperr! !joblog!
        call :sho "You can temporary change parameter 'FTP_UPLOAD_ENABLED' to 0 for work without FTP uploading." !joblog!
        goto :final
    )

    set upload_retcode=1
    for /f "tokens=*" %%a in ("!file_to_upload!") do (
        findstr /i /b /c:"226 Successfully transferred" !tmplog! | findstr /i /c:"!FTP_UPLOAD_DIR!/%%~nxa"
        if NOT errorlevel 1 (
            findstr /i /b /c:"ftp: !file_size! bytes sent" !tmplog!
            if NOT errorlevel 1 (
                if /i .!mode!.==.probe. (
                    findstr /i /b /c:"250 File deleted successfully" !tmplog!
                    if NOT errorlevel 1 (
                        findstr /m /i /r /b /c:"226 Successfully transferred.*!FTP_UPLOAD_DIR!" !tmplog!  | findstr /i /c:"!tmplog!"
                        set upload_retcode=!errorlevel!
                    )
                ) else if /i .!mode!.==.actual. (
                    call :sho "File '!file_to_upload!' uploaded OK." !joblog!
                    set upload_retcode=0
                )
            ) else (
                call :sho "Could not find message with 'size=!file_size! bytes sent'" !joblog!
            )
        ) else (
            call :sho "Could not find message about successful transfer !FTP_UPLOAD_DIR!/%%~nxa" !joblog!
        )
    )

    if .!upload_retcode!.==.1. (
        call :sho "At least one problem occured during probe scenario for upload to FTP and query list of its files:" !joblog!
        call :bulksho !tmplog! !joblog!
        goto final
    )
    del !tmplst!

    call :sho "Leaving routine ftp_upload. Result: upload_retcode=!upload_retcode!" !joblog!

endlocal  & set "%~3=%upload_retcode%"
goto:eof

@rem -+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+

:no_env
    setlocal
    set tmplog=%1
    (
        echo.
        echo #######################################################
        echo Missed at least one of necessary environment variables.
        echo #######################################################
        echo.
        echo Check config file '%cfg%'.
        echo.
    ) >!tmplog!
    type !tmplog!

    @goto final
goto:eof

:haltHelper
()
exit /b

:final
    @rem http://stackoverflow.com/questions/10534911/how-can-i-exit-a-batch-file-from-within-a-function
    if not .!INIT_SHELL_DIR!.==.. (
        cd /d !INIT_SHELL_DIR!
    )
    call :haltHelper 2>nul

:end_of_test
echo.
echo.
echo %date% %time%. Final point of script %~f0. 

