# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # #                                                                   # # #
# # #                         O L T P   -   E M U L                     # # #
# # #                                                                   # # #
# # #   f o r    F i r e b i r d   D a t a b a s e    2.5   &   3.0     # # #
# # #                                                                   # # #
# # #                                                                   # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

To get last version: 

svn checkout svn://svn.code.sf.net/p/firebird/code/qa/oltp-emul/ .

===============================================================================

This is Quick-Start guide for test that emulates OLTP workload on FB 2.5 & 3.0.
Please READ all this file carefully before making any attempt to run test.

In case of any questions feel free to contact: p519446@yandex.ru

(C) Pavel Zotov, Moscow, Russia. 2014-2015.

===============================================================================

1. Ensure that following Firebird console utilities present on machine from which
   you are intend to run this test:
   * isql
   * fbsvcmgr
   * gfix

2. Create database and add its name to aliases.conf (databases.conf in FB 3.0).
   You can skip creating database and just specify its name in the test configuration
   file 'src/oltp{fb_version}_config.{os_name}' (see below item "4" about it) 
   - but in such case:
   a) it must contain full path (/var/db/firebird/oltptest.fdb etc);
   b) path and file name can NOT contain spaces or non-latin characters.

3. Edit your firebird.conf and UNCOMMENT setting: 

                             ExternalFileAccess 

   Set its value to path where special file with name 'stoptest.txt' could be created
   by Firebird server process. This file is used  to force all attachments to cancel 
   their operations (by themselves) and close ISQL sessions.

   Example:
   ExternalFileAccess  = Restrict /var/db/fb30

   NOTE. Ensure that file 'stoptest.txt' is EMPTY before *each* time you are going 
   to launch this test (you have to manually clear content of this file).

4. It is highly recommended to increase values of following parameters in firebird.conf:

   * DefaultDBCachePages
   * TempCacheLimit
   * LockHashSlots 


   For medium workload (about 30-40 connects) following values can be set:

   a) for Firebird 3.0:

      DefaultDbCachePages =  64K - for SuperServer; 
                             512 or 1024 - for Classic and SuperClassic;
      TempCacheLimit = 1024M
      LockHashSlots = 22111

   b) for Firebird 2.5:

      DefaultDbCachePages = 65536 - for SuperServer; 
                            512 or 1024 - for SuperClassic
      TempCacheLimit = 1073741824
      LockHashSlots = 22111


5. For Windows users: ensure that you have environment variable 'TEMP'.
   Test command script will create folder with name 'logs.oltpNN' under your 
   %TEMP% directory and this folder will contain logs of ISQL sessions work.

6. Change directory to 'src'. 

   Main command scenario which creates database, fill it with documents and 
   finally open multiple ISQL sessions has name '1run_oltp_emul'.

   Its extension depends on your OS:
   * '.sh' - for running this scenario under Linux
   * '.bat' - for running this scenario under Windows

   This script will parse following plain text files that serve to store test
   configuration parameters:
   * oltp25_config.nix - if scenario runs under Linux and tests Firebird 2.5
   * oltp30_config.nix - if scenario runs under Linux and tests Firebird 3.0
   * oltp25_config.win - if scenario runs under Windows and tests Firebird 2.5
   * oltp30_config.win - if scenario runs under Windows and tests Firebird 3.0

   Open config file which is suitable for your environment.
   Change settings in this file according to your ones: host, port, dbnm etc

   Pay attention to the following parameters:
   * create_with_fw
   * create_with_sweep
   * init_docs
   * wait_for_copy
   * working_mode
   * warm_time
   * test_time
   * mon_unit_perf

   For the first time you can assign to 'init_docs' some low value, e.g. 500 or 1000.
   Test will start with populating data up to <init_docs> value and only after this
   two phases will begin to perform:
   1) database warm-up during <warm_time> minutes;
   2) measurement of further business actions during <test_time> minutes.
  

7. STOP ANY ANTIVIRUS on that machine when you will run command scenario, otherwise 
   it can block creation of scripts and logs filling!

8. Open command interpreter (Windows: "Start/Run/cmd.exe"), change to 'src' directory and run:

   1run_oltp_emul.os NN KK

   where:
     os = .bat or .sh (for Windows or Linux accordingly)
     NN = 25 or 30 (version of FB, see above)
     KK = number of ISQL sessions which should be launched.


   If database that is specified in config file does not exist, script will attempt
   to create it for you.
   If database DOES exists but is empty or with not all needed objects than test will
   recreate all objects. Be careful in such case: do NOT make any connects to test DB
   until building process finishes.
  

9. After time which is calculated as: warm_time + test_time test will stop itself.

   First launched ISQL session will make final report in plain text format.
   If ISQL session is running on Windows and setting 'make_html' has value 1, final report
   wil also created in HTML format, but in that case time of this report creation will be
   increased approx. twice.

   Change to folder with name defined by parameter 'tmpdir' in your oltpNN_config file.

   The file with name like this:  oltpNN.report.txt   (where 'NN' = 25 or 30)
                                  #################
   -- will contain:

   * FB architecture name, database and test settings;
   * overall performance results: total, dynamic for 10 time intervals, detailed per each unit;
   * when test config setting 'mon_unit_perf' is 1: gathered monitoring data about performance
     with detalization down to: 1) for FB 2.5 - application units; for FB 3.0 - application
     units and tables;
   * exceptions that occured during test;
   * database statistics after test finish (only for tables that was modified);
   * database validation report;
   * comparison of firebird.log that was before and after test finish (only for FB 3.0).

   Pay note on performance reports.

   In the first report (which contain rows with text 'interval #   N, overall') you can
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

10. In order to run test again (2nd, 3rd times etc) go to SERVER and change there to the folder 
   which was specified in firebird.conf by value of parameter ExternalFileAccess ('/var/db/fb30' etc).

   Look for the file with name 'stoptest.txt': it will have some non-zero size.

   You have to make this file EMPTY (size = 0) before you can run this test again otherwise 
   you will get messages about this when attempt to run batch scenario ('1run_oltp_emul.{os}')

   You can force to stop all working ISQLs at any time (i.e. beforehand) by opening 'stoptest.txt' 
   and type any single character in it followed by newline. 
   In case when this file (and FB) is on Windows host, run Notepad.exe, add type any character 
   and press CR/LF, than choose File / Save As. Specify the *same* name, i.e. overwrite this file.

11. Full description of test: oltp_emul_test_fb_25_30_-_rus.htm (currently only in Russian).

