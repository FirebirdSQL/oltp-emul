# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # #                                                                   # # #
# # #                         O L T P   -   E M U L                     # # #
# # #                                                                   # # #
# # #   f o r    F i r e b i r d   D a t a b a s e   v.  >= 2.5         # # #
# # #                                                                   # # #
# # #                                                                   # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

Get actual version from here:

* if you are on WINDOWS:
    git clone --config core.autocrlf=true https://github.com/FirebirdSQL/oltp-emul .

* if you are on POSIX:
    git clone --config core.autocrlf=false https://github.com/FirebirdSQL/oltp-emul .

===============================================================================

This is Quick-Start guide for test that emulates OLTP workload on FB 2.5 and above.
Please READ all this file carefully before making any attempt to run test.

In case of any questions feel free to contact: p519446@yandex.ru

(C) Pavel Zotov, Moscow, Russia. 2014-2019.

===============================================================================

1. Ensure that you install Firebird client on the host from where you plan to run this test.
   Following binaries must also be on this machine:
   * isql
   * fbsvcmgr

2. Change to 'src' folder and find test configuration file that appropriates to the version
   of Firebird and OS:
   -------------------------------------------------------------------------
   ! Major version of ! Operating System where ! Name of OLTP-EMUL         !
   ! Firebird server  ! ISQL sessions will run ! test config file          !
   !------------------!------------------------!---------------------------!
   !       2.5        !        Windows         ! oltp25_config.win.default !
   !       2.5        !        Linux           ! oltp25_config.nix.default !
   !       N.x        !        Windows         ! oltpN0_config.win.default !
   !       N.x        !        Linux           ! oltpN0_config.nix.default !
   ! (where N = major version prefix: 3, 4, etc)                           !
   -------------------------------------------------------------------------

3. Make copy of this file so that its extension will be without ".default", e.g.:
   copy .\oltp30_config.win.default .\oltp30_config.win
   cp ./oltp30_config.nix.default ./oltp30_config.nix

   Open just created copy of configuration file and change settings to be suitable for you.
   Pay attention on following settings:

   * 'fbc' - path to isql executable on the host where you will launch ISQL sessions.

   *  'clu' - optional parameter that defines 'non-standard' name of binary ISQL: 'isql-fb' or so.
     (actual for installation from POSIX repository when ISQL is renamed to different name).

   * 'dbnm' - path and name of database file on server host. Batch scenario (1run_oltp_emul.bat/.sh) can 
      create the database file if you specify it using full path and name of file, but not as existing alias.
      Ensure that path and name of database file contains only ascii characters.
   
   * 'host', 'port', 'usr' and 'pwd' - values for connecting to database, their meaning is obvious.

   * 'tmpdir' - path to the directory where test will create temporary files for storing ISQL session logs etc.

   * 'init_docs' - how many documents should be created in the database before test start real workload.

   * 'warm_time' and 'test_time' - how long database should be warmed-up and duration of measured workload, in minutes.

   * 'sleep_min', 'sleep_max'  - how long every attachment should be PAUSED between transactions for making workload
      more realistic. Assigning zero to 'sleep_max' will suppress any pauses and new transaction will be started 
      immediately after previous one finished.

   * 'sleep_ddl' - SQL script that contains declaration of UDF that will be called for PAUSES. 
      This script is OPTIONAL: when commented then pauses will be implemented by SHELL call (from ISQL execution context).
      Name of SHELL command depends on OS: it will be cscript.exe + .vbs on Windows or 'sleep' command on POSIX, but in any
      case this will add more workload on operating system when bulk of ISQL sessions are in work.
      It is recommended to use UDF invocation for making pauses, and you can use your own UDF or provided by this test.

      The latter is stored in compressed binary:
        Windows: .\util\udf64\SleepUDF.dll.zip 
        POSIX: ./util/udf64/SleepUDF.so.bz2. 
      Extract these UDFs:
        7zip -x -tzip .\util\udf64\SleepUDF.dll.zip 
        bzip2 -dk ./util/udf64/SleepUDF.so.bz2
       Put extracted .dll /.so into UDF subfolder of Firebird home.

   * 'wait_for_copy' - should test scenario make pause after test database will be filled-up with required number
     of documents. Value = 1 will save your time if you plan to launch test again later: make a copy of database
     that will be created and restore from it on 2nd, 3rd etc launches.

   For the first time you can assign to 'init_docs' some small value, e.g. 3000 or 5000.
   Test will start with populating data up to <init_docs> value and after this number of documents will be reached, 
   two phases will begin to perform:
   1) database warm-up during <warm_time> minutes;
   2) measurement of further business actions during <test_time> minutes.

4. Windows specific. 
   Ensure that any protection software (antivirus or built-in Windows mechanism) does NOT check any type of files 
   in the folder that you will define by 'tmpdir' config parameter. 
   Firebird can create temporary files:
   a) for storing data of GTT (fb_table_*) - in the folder that is defined by searching first non-empty env. variable 
      from following list: { FIREBIRD_TMP; TMP; TEMP }
   b) for sorting (fb_sort_*) and  storing monitoring snapshots (fb_recbuf_*, fb_blob_*) - in a directory that is defined 
      by 'TempDirectories' parameter from firebird.conf.
   It is recommended that you will set value of FIREBIRD_TMP variable equal to thev value of 'TempDirectories' parameter 
   from firebird.conf and remove any OS/antivirus protection from this folder. Otherwise you can encounter extremely slow 
   disk operations of all launched ISQL sessions.

5. It is highly recommended to increase values of following parameters in firebird.conf:

   * DefaultDBCachePages
   * LockHashSlots and
   * LockMemSize

   It is needed to EXPLICITLY SPECIFY parameter FileSystemCacheThreshold so that it will be greater than DefaultDBCachePages.
   Test does not accept firebird.conf with missed or commented value of this parameter (this does not relate to FB instance
   which was originated from POSIX repository and has actual home folder differs from parent one for parameter 'fbc').

   Parameter DefaultDBCachePages must have value that leads total size of page cache be equal ~25% of total physical memory.
   Do NOT assign to DefaultDBCachePages values more than 2048 if you plan test Classic Server or SuperClassic.

   Database always is created with page size 8192, this value is hardcoded.
   For medium workload (about 100 working sessions) following values can be set:

    +----------------------------------------------------------------------------------------------+
    |                           SuperServer 3.0+   |  [Super]Classic 3.0+   |   [Super]Classic 2.5 |
    |----------------------------------------------|------------------------|----------------------|
    |  DefaultDbCachePages      0.25 * <M> / 8192  |                1024    |             1024     |
    |  LockHashSlots                  8191         |               16001    |            16001     |
    |  LockMemSize                 4194304         |            16777216    |         16777216     |
    +----------------------------------------------------------------------------------------------+
    <M> = total physical memory


6. Open command interpreter (Windows: "Start/Run/cmd.exe"), change to 'src' directory and run:

   1run_oltp_emul <V> <N> [nostop]
   ###############################

   where:
       <V> = 25, 30 or 40 - major version in simplified form for FB 2.5, 3.0 or 4.0 respectively;
       <N> = number of ISQL sessions which should be launched;
       nostop = (optional) literal argument that forces script to skip any pauses, even if work
             will be impossible (useful when scenario is launched from scheduler)

   If database does not exist, script will attempt to create it for you  but only if it's specified as fully qualified file name (not alias).
   If database already exists but is empty or it creation was not completed during previous run then test will recreate all needed objects.


7. After <warm_time> + <test_time> minutes test will stop itself, i.e. all ISQL sessions will
   terminate their own job by raising exception, issuing QUIT statement and disconnect from database.
   On Windows, every ISQL window will be closed, so you do not have to close them manually.

   ISQL session which was launched first among all others will make final report in text format.

   If this ISQL session is running on Windows and setting 'make_html' has value 1, final report will be
   created also in HTML format, but in that case time of this report creation will be increased on ~2x.

   Change to folder with name defined by parameter 'tmpdir' in your oltpNN_config file.
   Name of final report file depends on value of config parameter 'file_name_with_test_params':
   When parameter 'file_name_with_test_params':
   1. Is commented (default), report will be created with name: oltp**.report.txt
   2. Has value 'regular' - report will be in form that appropriates for 'accunmulation' of files
      for further analysis by simple look on the LIST of these files and found performance troubles;
      Sample of report name when this parameter = 'regular':
      20151102_1448_score_06543_build_31236_ss30__3h00m_100_att_fw__on.txt
   3. Has value 'benchmark' - report will be in form that appropriates for comparison of different
      test or database DDL settings.
      Sample of report name when this parameter = 'benchmark':
      ss30_fw_off_split_most__sel_1st_one_index_score_06543_build_31236__3h00m_100_att_20151102_1448.txt

   Final report contains:

   * FB architecture name, database and test settings;
   * overall performance results: total, dynamic for 30 time intervals, performance for each minute and detailed per each unit;
   * when test config setting 'mon_unit_perf' is 1: gathered monitoring data about performance
     with detalization down to: 1) for FB 2.5 - application units; for FB 3.0 and above - application
     units and tables;
   * exceptions that occured during test;
   * database statistics after test finish;
   * report about ratio "total versions" / "total records" for every table with number of records > 0.
   * database validation report (only for tables that are subject for modifications);
   * comparison of firebird.log that was before and after test finish, using standard console utilities
     which present on any version of underlying OS: fc.exe (on Windows) and diff (on Linux).

   Pay note on performance reports.

   In the first report (which contain rows with text 'interval # NNN, overall') you can
   estimate performance for each of time interval in the column 'CNT_OK_PER_MINUTE': this is
   the number of business per one minute actions that finished SUCCESSFULLY in bounds of each
   interval.

   In the second report (which contains row with text "*** OVERALL *** for N minutes") you can
   estimate aggregated value of performance for last three hours or time of actual work. Value
   in the column "AVG_TIMES_PER_MINUTE" has the same sence: average number of business actions
   per one minute which finished SUCCESSFULLY, but not splitted on intervals.

   You can also get these data if connect to test database and run:

   SQL> select * from srv_mon_perf_dynamic;
   SQL> select * from srv_mon_perf_total;

8. Test will stop itself automatically on every run, you have to specify only two time-based
   values: duration of database warm-up and how long measure phase should last, in minutes.

   However, if you'll encounter that database become unavaliable because of too heavy workload
   you may to stop all ISQL sessions almost immediatelly.
   Default way for this - running batch scenario with name = '1stoptest.tmp' (.bat/.sh) which
   will be created every time on test launch in temporary folder which is defined by test config
   parameter 'tmpdir'.

   *** NOTES ABOUT STOPPING TEST WHEN ISQL SESSIONS ARE LAUNCHED FROM SEVERAL MACHINES ***

   If your planning to launch test from SEVERAL MACHINES, one may to consider another way to 
   premature stop test:
   1) edit your firebird.conf and uncomment setting ExternalFileAccess;
   2) set its value:
      2.1) either to 'Restict <P>' where <P> is the directory where Firebird process will be able
           to create file for external table,
      2.2) or 'Full'.
   3) open oltp**_config file and find parameter 'use_external_to_stop'. It is COMMENTED by default.
      Uncomment it and set its value to:
      3.1) either ONLY name of external file (without path) - if ExternalFileAccess = Restrict <P>,
      3.2) or full path and name of file - if ExternalFileAccess = Full.

   Restart FB service. Ensure that stop-file file specified in oltp**_config is EMPTY before *each* 
   time you are going to launch this test (you have to manually clear content of this file).
   In case when this file is on Windows host, run Notepad.exe, type any ascii character and press LF
   than choose File / Save As. Specify the *same* name, i.e. overwrite this file.


9. If you plan to run this test several times in order to estimate affect of changing some of its settings
   it is recommended that you will do this by starting workload from the same 'point' each time. This mean
   that you might want to create test database, wait until test will finish process of adding initial number
   of documents and then make test scenario to be PAUSED until you make copy to that database.
   If this is what you want, change value of config parameter 'wait_for_copy' to 1.
   After test will finish, save its report somewhere and restore test database from previously created copy.
   If parameter 'use_external_to_stop' is defined, do not forget to make server-side file 'stoptest.txt'
   empty before running new test session!

10. Full description of test: doc/firebird-oltp-emulation-test.html (currently only in Russian).
