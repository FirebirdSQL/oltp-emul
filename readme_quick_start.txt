# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 
# # #                                                                   # # #
# # #                         O L T P   -   E M U L                     # # #
# # #                                                                   # # #
# # #   f o r    F i r e b i r d   D a t a b a s e    2.5   &   3.0     # # #
# # #                                                                   # # #
# # #                                                                   # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # 

This is Quick-Start guide for test that emulates OLTP workload on FB 2.5 & 3.0.
Please READ all this file carefully before making any attempt to run test.

In case of any questions feel free to contact: p519446@yandex.ru

(C) Pavel Zotov, Moscow, Russia. 2014.

===============================================================================

0. Ensure that following Firebird console utilities present on machine from which
   you are intend to run this test:
   * isql
   * fbsvcmgr
   * gfix
   * gstat

1. Create database and add its name to aliases.conf (databases.conf in FB 3.0).
   You can skip creating database and just specify its name in the test configuration
   file 'src/oltp{fb_version}_config.{os_name}' (see below item "4" about it) 
   - but in such case:
   a) it must contain full path (/var/db/firebird/oltptest.fdb etc);
   b) path and file name can NOT contain spaces or non-latin characters.

2. Edit your firebird.conf and UNCOMMENT setting: 

                             ExternalFileAccess 

   Set its value to folder where you will create special file 'stoptest.txt'
   to force all attaches to cancel their operations and close ISQL sessions.

   Example:
   ExternalFileAccess  = Restrict /var/db/fb30

   It is highly recommended to increase values of following parameters:

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


3. For Windows users: ensure that you have environment variable 'TEMP' and 
   verify that its value does NOT contain spaces or non-latin characters. 
   Test command script will create folder with name 'logs.oltpNN' under your 
   %TEMP% directory and this folder will contain different logs of work.

4. Change directory to 'src'. 

   Main command scenario (which creates database, fill it with documents and 
   finally open multiple ISQL sessions) has name '1run_oltp_emul'.

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
   ----------- QUOTE ----------
	# number of documents, total of all types, for initial data population
	# (only new documents creation occurs, no removals):
	# recommended value: at least 30000 
	init_docs=30000

	# should script be PAUSED after finish creating <init_docs> documents
	# (for making copy of .fdb and restore it on the following runs thus
	# avoiding to make init_docs again):
	wait_for_copy=0

	# time (in minutes) to warm-up database after initial data population
	# will finish and before all following operations will be measured:
	warm_time=10

	# max time (in minutes) to measure operations before test autostop itself:
	test_time=60
   -------- END OF QUOTE -------

   For the first time you can assign to 'init_docs' some low value, e.g. 500 or 1000.
   Test will start with populating data up to <init_docs> value and only after this
   two phases will begin to perform:
   1) database warm-up during <warm_time> minutes;
   2) measurement of further business actions during <test_time> minutes.
  

5. STOP ANY ANTIVIRUS on that machine when you will run command scenario, otherwise 
   it can block creation of scripts and logs filling!

6. Open command interpreter (Windows: "Start/Run/cmd.exe"), change to 'src' directory and run:

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
  

7. After time which is calculated as: warm_time + test_time test will stop itself.

   Change to folder with name defined by parameter 'tmpdir' in your oltpNN_config file.

   The file with name like this: 

       oltpNN_%COMPUTERNAME%-001.performance_report.txt // (or $HOSTNAME for Linux)

   - will contain overall performance results: dynamic in 10 time intervals and total for 
   last three hours or time of actual work (minimal of these two values is taken in account).

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

8. In order to run test again (2nd, 3rd times etc) go to SERVER and change there to the folder 
   which was specified in firebird.conf by value of parameter ExternalFileAccess ('/var/db/fb30' etc).

   Look for the file with name 'stoptest.txt': it will have some non-zero size.

   You have to make this file EMPTY (size = 0) before you can run this test again otherwise 
   you will get messages about this when attempt to run batch scenario ('1run_oltp_emul.{os}')

   You can force to stop all working ISQLs at any time (i.e. beforehand) by opening 'stoptest.txt' 
   and type any single character in it followed by newline. In case when this file (and FB) is on 
   Windows host, run Notepad.exe and load this file in editor using Ctrl-O ("Open File" dialog).

9. Full description of test: doc/oltp_emul_test_for_firebird_25_and_30_-_description.doc (rus)
