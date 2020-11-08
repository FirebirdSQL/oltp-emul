############################################### CAUTION #####################################################
### THESE SCRIPTS ARE POTENTIALLY DANGEROUS FOR YOUR PRODUCTION! DO NOT RUN THEM UNTIL YOU READ THIS FILE ###
#############################################################################################################

This directory contains two scripts (oltp-scheduled.sh, oltp-scheduled.bat) for launch OLTP-EMUL by scheduler.

Both scripts accepts three mandatory and one optional parameter:

1. <FB_major_version> = 25 or 30 or 40 - version of Firebird without dot: 2.5, 3.0, 4.0;
2. <sessions_count> = number of ISQL sessions to start;
3. <server_mode> = CS | SC | SS  -  required mode, case-insensitive;
4. <update_FB_instance> = should we upgrade FB instance before test ? Default: 1
   This is optional parameter.

Script configuration file contains parameter 'OLTP_HOME_DIR' which must point to the folder with OLTP-EMUL 
configiration files (oltpNN_config.*). Its value is: ..\.. on Windows and ../.. on Linux.
Apropriate configuration file will be parsed and directory to the instance of Firebird will be obtained from there.

### CAUTION ###
By default, Firebird instance will be stopped and fully replaced with new at every start of this script!
Be sure that parameter <fbc> from every OLTP-EMUL config file DOES NOT point to some FB instance that is important for you!
NEVER set value of this parameter to folder where your production or other crusial FB instance is.
###############

When value of 4th parameter is 1 (default!) then every run of this script will check new FB snapshot on official site
and ***REPLACE*** existing instance if need (for Linux - with apropriate .debug package)

Before replacing FB instance, script attempts to stop its running process.

On Windows it searches for apropriate FB service and tries to stop it. If FB was launched as apprication then script will
kill it using Windows TASKKILL command.

On Linux script tries to stop Firebird daemon using 'systemctl stop $service_name'. If this command fails to stop FB then
script:
* checks presence of 'gdb' package;
* tries to get stack trace of running FB process
* get list of all opened databases and run fb_lock_print -c -d <...> for every item of this list.
After this, it compress obtained files.
Maximal number of compressed stack traces and lock prints can be limited by <MAX_ZIP_FILES>.


Download task is executed by curl utility. 
On Linux curl package must be installed first.
On Windows apropriate binary already is provided and must be extracted from '..\curl\bin\curl-7.63.0_x64.7z' file
(extracted curl.exe must be in the same folder, i.e. '..\curl\bin\')

Parameters of "target" firebird.conf will be replaced with values from apropriate config from this folder.
Name of this config will be evaluated as: 'oltp-scheduled-fb' || <param1> || '.conf.' || <param3>
For example, if you want to test Firebird 4.x in ServerMode = Super then its config will have parameters from file
'oltp-scheduled-fb40.conf.SS' which is in this directory.

Value of RemoteServicePort is always taken from parameter <port> of <oltpNN_config> file.
Parameter BugCheckAbort is always assigned to 1 in order to have ability to catch crashes of bugchecks.

On Linux that have systemd loader, script will detect starting script of FB service (its folder depends on OS) and
put there additional command to allow dumps to be created ('LimitCORE=infinity').

On Windows script checks registry key: HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\Windows Error Reporting
This key must contain parameter 'DontShowUI', type = DWORD and value = 1.

Script can send just downloaded FB snapshot to e-mail if needed.
Entire Firebird package will be splitted in this case onto volumes with size not more than value defined by
config parameter <max_size_without_split> (usually this must be about 12...15 Mb). Your e-mail box will receive
letters with subject like:
    "FB_daily_build. Build: Firebird-4.0.0.2244-0_x64.7z, total size 27102438; part 1 of 2"
    "FB_daily_build. Build: Firebird-4.0.0.2248-ReleaseCandidate1.amd64.tar.gz, part: 1 of 2"
    "FB_daily_build. Debug package: Firebird-debuginfo-4.0.0.2248-ReleaseCandidate1.amd64.tar.gz, part: 1 of 13"

On Windows you must have console executable of 7-Zip in order to do this (see parameter <P7ZCMD>).
On Linux compression not needed, splitting of package onto volumes is done by OS built-in command.

Script (oltp-scheduled.*) requires that you preliminarily create ETALONE database which will serve as source for copy
to the target DB before oltp-emul launch. Such database must be defined by parameter 'etalon_dbnm' in apropriate
oltpNN_config file. It is recommended to change mode of this DB to read_only or set its state to full shutdown
(script will run all necessary commands to change copy of this DB to normal state before launch OLTP-EMUL).


At the end stage, script will change directory to <OLTP_HOME_DIR> and launch main test from there.
Reports will be accumulated in the folder defined by <tmpdir> from oltpNN_config file.
You can set limit for number of these report by changing parameter MAX_RPT_FILES.

