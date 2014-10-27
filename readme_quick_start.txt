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

Copyright (c) 2014 Pavel Zotov, Moscow, Russia.

===============================================================================

0. CREATE database and add its name to aliases.conf (databases.conf in FB 3.0)

1. Edit your firebird.conf and uncomment setting: ExternalFileAccess 
   Set its value to folder where you will create special file 'stoptest.txt'
   to force all attaches to cancel their operations and close ISQL sessions.

   Example:
   ExternalFileAccess  = Restrict /var/db/fb30

2. Ensure that you have environment variable 'TEMP' and check that its value
   does NOT contain spaces or non-latin characters.

3. Change directory to 'src'. Open file 'oltp_config.NN' where NN:
   25 - for create database and run test on Firebird 2.5
   30 - the same for Firebird 3.0

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
   

4. STOP ANY ANTIVIRUS otherwise it can block creation of scripts and logs filling on client machine!

5. Open command interpreter ("Start/Run/cmd.exe"), change to 'src' directory and run:

   1build_oltp_emul.bat NN
   
   where:
      NN = 25 - for create database against Firebird 2.5
      - or -
      NN = 30 - the same for Firebird 3.0

   Do *NOT* insert dot character ('.') between '2' and '5' (or '3' and '0').

   Ensure that after it finish NO message about errors will be on the screen.
   This batch first checks that connection to FB can be established and displays messages which
   ends with rows like these:

   ----------- QUOTE ----------
   All checks of isql temp log messages PASSED OK.

   #################################################
   Database will be created for FB >>> 25 <<<
   #################################################
   ------- END OF QUOTE -------
   
   Press enter to start creation of database objects ("Build test database. Please wait. . .").
   After database objects will be created you should see something like this:

   ----------- QUOTE ----------
   Result: all OK.


   PAGE_SIZE PAGE_BUFFERS FW            SWEEP DB_NAME
   ========= ============ ====== ============ ========================
        8192         4096 ON                0 /var/db/fb25/oltp25.fdb


   SETTING_NAME                             SETTING_VALUE
   ======================================== ===============
   WORKING_MODE                             SMALL_03
   C_WARES_MAX_ID                           400
   C_CUSTOMER_DOC_MAX_ROWS                  10
   C_SUPPLIER_DOC_MAX_ROWS                  50
   C_CUSTOMER_DOC_MAX_QTY                   15
   C_SUPPLIER_DOC_MAX_QTY                   50
   C_NUMBER_OF_AGENTS                       50
   ENABLE_MON_QUERY                         0
   TRACED_UNITS                             ,,
   HALT_TEST_ON_ERRORS                      ,CK,
   C_CATCH_MISM_BITSET                      1
   C_MAKE_QTY_STORNO_MODE                   DEL_INS
   ENABLE_RESERVES_WHEN_ADD_INVOICE         1
   RANDOM_SEEK_VIA_ROWS_LIMIT               0
   C_MIN_COST_TO_BE_SPLITTED                1000
   C_ROWS_TO_MULTIPLY                       10

   -----------------------------------------------
   Now run:

            1run_oltp_emul.bat 25 <N>
   ...
   ------- END OF QUOTE -------


6. Run batch:
   
   1run_oltp_emul.bat NN KK

   where:
     NN = 25 or 30 (version of FB, see above)
     KK = number of ISQL sessions which should be launched.

7. After time which is calculated as: warm_time + test_time test will stop itself.

   Change to folder %TEMP%\logs.oltpNN.

   The file with name like this: 

       oltp_NN_%COMPUTERNAME%_001_performance_report.txt 

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
   you will get messages about this when attempt to run batch '1run_oltp_emul.bat'

   You can force to stop all working ISQLs at any time (i.e. beforehand) by opening 'stoptest.txt' 
   and type any single character in it followed by newline. In case when this file (and FB) is on 
   Windows host, run Notepad.exe and load this file in editor using Ctrl-O ("Open File" dialog).

9. Full description of test: doc/oltp_emul_test_for_firebird_25_and_30_-_description.doc (rus)

10. Samples of performance analysis see in folder 'reports' (several .xls files for each FB version)
