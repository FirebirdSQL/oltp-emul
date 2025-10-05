####################################################################
# OLTP-EMUL test for Firebird database. Configuration parameters.
# To get the actual version of test, enter command:
# 
# git clone --config core.autocrlf=false https://github.com/FirebirdSQL/oltp-emul .
# 
# This file is used to launch ISQL sessions on POSIX for test server with running
# Firebird 3.x
# Parameters are extracted by '1run_oltp_emul.sh' command scenario.
####################################################################


#::::::::::::::::::::::::::::::::::::::::::::::::
#  SETTINGS FOR START AND FINISH ISQL SESSIONS
#::::::::::::::::::::::::::::::::::::::::::::::::


   # Folder with Firebird console utilities (isql, fbsvcmgr, gfix, gbak).
   # For builds that are published on official Firebird site such folder is /opt/firebird/bin/
   # For builds that are installed from Ubuntu/Debian repository this folder is /usr/bin/
   # Trailing backslash is optional.
   # Examples:
   # fbc = /opt/firebird/bin
   # fbc = /usr/bin
   #
   # WARNING. DO NOT use names with spaces, parenthesis or non-ascii characters.
   #
   fbc = /opt/hq30/bin


   # LINUX ONLY. OPTIONAL FOR CentOS/RH. Command-line utility for operate as ISQL.
   # Actual only for builds installed from Ubuntu/Debian repository.
   # These builds have ISQL utility with different name: 'isql-fb' instead of usual 'isql'.
   # Full name of this utility will be evaluated as concatenation of <fbc> and <clu> values.
   # String '<fbc>/isql' will be used to call ISQL if you leave this parameter commented.
   #
   # More details about used directories when FB is installed from Ubuntu/Debian repository:
   #     https://firebirdsql.org/manual/ubusetup.html
   #     https://www.firebirdsql.org/file/documentation/reference_manuals/user_manuals/html/ubusetup.html 
   # Command for list FB-related files that were installed on Ubuntu/Debian:
   #     dpkg -L firebird3.0-server
   #
   # clu = isql-fb


   # Full path and file name of database. DO NOT USE ALIAS. Use only ASCII characters.
   # Existing OS variable can be referred here by using dollar sign.
   # It is recommended to read Filesystem Hierarchy Standard before you decide where to put
   # database and temporary files:
   #     https://refspecs.linuxfoundation.org/FHS_3.0/fhs-3.0.pdf
   # Firebird service account must have full access to the folder of specified database <dbnm>
   # (test will try to create temporary database in this folder for some checks and then drop it).
   #
   # Examples:
   # dbnm = /var/db/oltp_30.fdb
   # dbnm = $TMP/data/oltp_30.fdb
   #
   # WARNING. DO NOT use names with spaces, parenthesis or non-ascii characters.
   #
   dbnm = /var/db/oltp-emul/oltp-hq30.fdb


   # Parameters for remote connection and authentication.
   # Will be ignored by command scenario if FB runs in embedded mode.
   #
   # Host name or IP address of computer with running Firebird.
   #
   host = localhost


   # Port that is listening by Firebird instance on <host>.
   # In order to check which process is listening to selected port, type (locally on server):
   #     netstat --tcp --listening --program --numeric | grep <port>
   # Output will contain PID of process at last token (delimited by '/'). Put this value in the command:
   #     ps ax | grep " <PID>" | grep -v grep
   #
   # Ubuntu/Debian notes: if your FB instance was installed from repository then you can check port by
   # issuing command:
   #     grep -i "RemoteServicePort" /etc/firebird/<@.@>/firebird.conf
   # -- where <@.@> marks major FB version (2.5; 3.0; 4.0).
   #
   port = 30300


   # Login for connect to FB services and database. Account must have the same rights as SYSDBA.
   usr = SYSDBA


   # Password for <usr>
   pwd = masterkey


   # Folder for storing .sql scenarios, STDOUT and STDERR logs of every working isql session.
   # Trailing backslash is optional.
   # Allows referencing to existing OS environment variable by using dollar sign.
   # Examples:
   # tmpdir = /var/tmp/logs.oltp30
   # tmpdir = $TMP/logs.oltp30
   #
   # WARNING. DO NOT use names with spaces, parenthesis or non-ascii characters.
   #
   tmpdir = /var/tmp/logs.oltp-hq30


   # Condition for removing or preserving ISQL logs in <tmpdir> after test finish.
   # Possible values: always | never | if_no_severe_errors
   # * 'always' means that logs will be removed after test finish regardless any result.
   # * 'never' means that logs will be always preserved.
   # * 'if_no_severe_errors' means that logs will be removed only if no severe exceptions occured during test.
   # Test considers following Firebird-related exceptions as 'severe':
   #    gdscode    description
   #  ---------    -----------
   #  335544321    string truncation: attempt to assign too long text into a string variable.
   #  335544334    convert_error: conversion error from string
   #  335544347    not_valid: validation error for column @1, value "@2".
   #  335544349    no_dup: operation violates unique index
   #  335544352    no_priv: no permission for @1 access to @2 @3
   #  335544359    read_only_field: attempted update of read-only column @1
   #  335544360    read_only_rel: attempted update of read-only table
   #  335544361    read_only_trans: attempted update during read-only transaction
   #  335544362    read_only_view: cannot update read-only view @1
   #  335544466    foreign_key: violation of FOREIGN KEY constraint "@1" on table "@2".
   #  335544472    login: your user name and password are not defined.
   #  335544558    check_constraint: operation violates CHECK constraint on view or table.
   #  335544665    unique_key_violation: operation violates PRIMARY or UNIQUE KEY constraint
   #  335544838    foreign_key_target_doesnt_exist: attempt to insert/update field in child table with value which does not exists in parent table
   #  335544839    foreign_key_references_present: attempt to delete parent record while child records exist and FK was declared without CASCADE clause
   #  335544842    stack_trace
   #  335544843    ctx_var_not_found: context variable @1 is not found in namespace SYSTEM
   #
   # NOTE: if FB crash occures during test run then value of this parameter will be ignored and all logs will be preserved.
   # Recommended value: if_no_severe_errors
   #
   remove_isql_logs = if_no_severe_errors


#:::::::::::::::::::::::::::::
#  SETTINGS FOR WORKLOAD LEVEL
#:::::::::::::::::::::::::::::


   # If you plan this database be involved in replication, then one need to add primary keys
   # to all persistent tables that can be changed during test work.
   # Assign value of following parameter to 1 in order to apply all necessary changes to tables DDL
   # (primary keys and triggers for some of tables).
   # Setting value to 0 will DROP all changes that are unneeded when test runs without replication.
   # This parameter can be changed 'on the fly': database recreation is NOT required, but in case
   # when database has valuable size, changes will be applied not instantly.
   #
   used_in_replication = 0


   # Test has several settings that define how much work should be done by each business action in average.
   # All of them are considered as separate enumerations: when new ISQL session creates connection, it reads
   # "entry" setting about selected workload level and then read all other settings for THIS workload level.
   # Parameter 'working_mode' is mnemonic for these enumerations. Possible values for this parameter are:
   # SMALL_01, SMALL_02, SMALL_03, MEDIUM_01, MEDIUM_02, MEDIUM_03, LARGE_01, LARGE_02, LARGE_03 and HEAVY_01
   # In case of launching test from several machines ensure that all of them have the same value for this parameter.
   # Completely new workload mode can be added to the test by editing file 'oltp_main_filling.sql', see there
   # sub-section "Definitions for workload modes".
   # WARNING: exception will raise on test startup if this value was mistyped and has no corresponding data in DB.
   # CAUTION: assigning LARGE* or HEAVY* modes leads to extremely high workload! Do this only when you have really
   # powerful server with lot of CPUs, huge RAM and very fast I/O system.
   #
   # Mnemonic name of workload mode (must be specified without quotes, case-insensitive):
   #
   working_mode = small_03


   # This parameter defines volume of work that will be done by each ISQL before it will detach from DB and reconnect.
   # Normally in a production system frequency of reconnections must be low.
   # Rather, each connection must do as much work as possible. Unfortunately, when ISQL does its work by executing
   # script, one can not to check log of errors which occured during this execution. Some errors can require test
   # to be prematurely stopped (e.g. if FB process crashed and it was reflected in firebird.log). But each session
   # can found this only when ISQL finished. This mean that value of following parameter must belong to reasonable scope.
   # For some (exotic) purposes when it is needed to increase frequency of reconnections one may to set it to 5...50.
   # Recommended value: 300
   #
   actions_todo_before_reconnect = 300


   # Maximal number of established connections per second when test STARTUP begins.
   # Defines allowed rate of new attachments appearance for making workload grow smoothly.
   #
   # We have to limit RATE of requests for new attachments, especially when total count of launching ISQL sessions 
   # is 1000 or more. Otherwise some of sessions will get failure on attempt to establish connection with text:
   #     Statement failed, SQLSTATE = 08004
   #     connection rejected by remote interface
   # If value of this parameter less than 10 or greater than 100 then delays will not occur and all sessions will try to establish
   # their attachments at the same time. This can be reason of "connection rejected" error.
   # Otherwise:
   # * if number of sessions not exceeds [max_cps] then delay will be evaluated as random value between 1 and 4 seconds.
   # * if number of sessions greater that this parameter then delay will be evaluated as: 1 + session_id / <max_cps>
   #
   # NOTE. If you intend to launch more than 1000 sessions then consider to adjust following settings in /etc/sysctl.conf:
   # net.core.somaxconn = 2000
   # net.core.netdev_max_backlog = 2000
   # net.core.tcp_max_syn_backlog = 2000
   # net.ipv4.ip_local_port_range = 15000 61000
   # net.ipv4.tcp_tw_reuse = 1
   # net.ipv4.tcp_max_tw_buckets = 1440000
   # See also:
   # http://lxr.linux.no/#linux+v3.2.8/Documentation/networking/ip-sysctl.txt#L111
   # http://lxr.linux.no/#linux+v3.2.8/Documentation/networking/ip-sysctl.txt#L284
   # http://lxr.linux.no/#linux+v3.2.8/Documentation/networking/ip-sysctl.txt#L464
   # https://www.centos.org/docs/5/html/5.1/Deployment_Guide/s3-proc-sys-net.html
   # http://docs.continuent.com/tungsten-clustering-6.0/performance-networking.html
   # https://access.redhat.com/solutions/41776
   #
   # Recommended value: 20...30
   #
   max_cps = 25


   # OPTIONAL.
   # MINIMAL pause duration between each business operations, in seconds.
   # This parameter has default value 0 and can be commented.
   # Duration of pause will be evaluated at runtime as random value 
   # between <sleep_min> and <sleep_max> values.
   #
   sleep_min = 0


   # MAXIMAL pause duration between each business operations, in seconds.
   # Default: 0 - no pauses, next transaction will start immediatelly after previous commit.
   # This leads to maximal (non-realistic) level of workload.
   # Delay statement will be inserted in .sql script by '1run_oltp_emul'; the form of this statement depends on value of
   # parameter 'sleep_ddl':
   # 1) If parameter 'sleep_ddl' is commented (undefined) then OS call ("shell sleep <sleep_max>;") will be added after each
   #    transaction commit in order to pause SQL execution.
   #    This leads to excessive OS workload when number of sessions is more than ~300.
   # 2) Otherwise special UDF for delay will be invoked from separate execute block after each transaction commit.
   #    This UDF must be declared in SQL-script which name is defined by <sleep_ddl> parameter (see this config).
   #
   # NOTE. THIS PARAMETER IS MANDATORY AND CAN NOT BE COMMENTED.  SPECIFY 0 IF NO PAUSES REQUIRED.
   #
   sleep_max = 0


   # When we want to insert delays between subsequent business actions then parameter sleep_max > 0 must be specified.
   # Delays can be done either by external OS command (i.e. "shell ... ;") or by UDF invocation.
   # Calls to external OS command from dozen of sessions leads to valuable load, especially when number of sessions more than 300.
   # This can be avoided if delays are done via UDF calls.
   #
   # Parameter 'sleep_ddl' specifies mame of .sql script with declaration of UDF for DELAYS between subsequent business actions.
   # Script must correctly drop old UDFs with any name that contains phrases: DELAY, SLEEP or PAUSE.
   # After dropping, script must create new UDF and test it (for checking results in log).
   # This script will be applied only when parameter 'sleep_max' greater than 0.
   # Note. The whole following phrase:
   #
   #     declare external function <UDF_name>
   #
   # -- must be written on the SINGLE LINE in this script ( <UDF_name> will be searched in this line as its 4th word).
   #
   # This UDF implementation (.so file) must be stored in the server-side folder, usually in $FIREBIRD_HOME$/UDF.
   # Also, UDF calls must be enabled in firebird.conf by specifying: UDFaccess = restrict UDF
   # NOTES for Ubuntu/Debian.
   #     If your FB instance was installed from Ubuntu/Debian repository then put .so file to /usr/lib/firebird/<@.@>/UDF/
   #     where '@.@' marks major version of FB, i.e.:
   #     UdfAccess parameter for such FB instance must have *absolute* value rather then relative, i.e.:
   # See description for parameter 'UDFaccess' in standard firebird.conf for details.
   #
   # Test provides its own UDF and appropriate declaration script named 'oltp_sleepUDF_nix.sql'.
   # Unpack file ./util/udf64/SleepUDF.so.tar.gz  and put file SleepUDF.so in any folder that is allowed by 'UDFaccess' parameter.
   # from firebird.conf.
   #
   # NOTES.
   #     UDF usage can not be avoided if parameter 'mon_unit_perf' has value 2. You can NOT leave 'sleep_ddl' commented out in this case.
   #
   sleep_ddl = ./oltp_sleepUDF_nix.sql


   # Should SET TRANSACTION statement include NO AUTO UNDO clause ? Avaliable values: 1=yes, 0=no
   # Performance can be increased if this option is set to 1:
   # SuperServer:   5 -  6 %
   # SuperClassic: 10 - 11 %
   # Recommended value: 1
   #
   no_auto_undo = 1


   # Minimal interval, in minutes, between two subsequent calls of service procedure 'srv_recalc_idx_stat' which updates index statistics.
   # Only indexes for tables that are participated in most often performing queries are affected. 
   # Note that frequent update of index statistics has sense only for small databases which have quickly changed data distribution.
   # There is no sense to update index statistics if test will runs for 1-2 hours and database has size more than 100 Gb: most probably
   # it will finish at the moment when test itself will also be close to expiration. 
   # In that case set value of this parameter to zero to prevent selection of procedure that does this updating.
   #
   # Recommended value of this parameter depends on size of database:
   #     within scope 30...60 minutes for databases with size up to 20 Gb;
   #     within scope 60...90 minutes for databases with size 20...40 Gb;
   #     within scope 90...120 minutes for databases with size 40...60 Gb;
   #     within scope 120...240 minutes for databases with size 60...80 Gb;
   #     0 (zero) for databases with size more than 80...100 Gb (this means that statistics will not be updated at all).
   # NOTE. For big databases (with size more than 100 Gb) updating of index statistics has sense only for big [test_time] values.
   #
   recalc_idx_min_interval = 30


   # Following parameter can be used for performance benchmark of Firebird ES/EDS mechanism and its External Connections Pool (ECP).
   # Note: ECP is supported only since Firebird 4.x. It is also supported by HQbird 3.x - commercial FB-branch (see https://ib-aid.com/ ).
   # This parameter is ignored if test is launched against Firebird 2.5.x.
   # When this parameter is non-zero then most of application and service procedures are changed: static PSQL expression are replaced with dynamic ones.
   # Avaliable values:
   #     0 - do not change static PSQL code, use it whenever it is possible (default);
   #     1 - replace static PSQL code with dynamic and use it in 'EXECUTE STATEMENT', but *without* using 'ON EXTERNAL' mechanism;
   #     2 - replace static PSQL code with dynamic and use it in 'EXECUTE STATEMENT ... ON EXTERNAL'.
   #         External Connections Pool can be tested and additional reports will be generated in this case.
   #
   # This parameter can be changed without need to DB recreation: test applies DDL replacements before every new launch.
   # If 'use_es' = 2 and 'separate_workers' = 1 then additional requirement exists for parameters 'mon_query_role', 'mon_usr_prefix' and 'mon_usr_passwd':
   # all of them must be defined, i.e. have non-empty values. Otherwise there is no way to distinguish "authors" of running DML within external connections.
   #
   # WARNING! Activating ES/EDS without ECP leads to significant performance penalty!
   # It is strongly recommended to enable ECP when this parameter is set to 2.
   #
   # Optimal values of ECP-related parameters in firebird.conf can be found empirically as follows:
   # 1. Set parameter 'make_html' of this test to 1 (this parameter is described below);
   # 2. Open firebird.conf and change ExtConnPoolSize: set it to 2*N+10, whene N is planning number of launched ISQL sessions;
   # 3. ExtConnPoolLifeTime: optimal value can be achieved after several FB restarts and test launches.
   #    Initial value can be set to 15.
   #    Then launch test with test_time not less than 20 minutes. Wait until it completely finish.
   #    Open HTML report and find there text: "External connections life activity, per connections". Note that there is 'chart' reference to the right of this text.
   #    Jump to this chart ("External connections pool: life activity, per connections").
   #    Note on dark-magenta dots that represent "Max. idle state in the pool, s".
   #    If almost all of them lie near upper bound of this chart then you have to INCREASE value of ExtConnPoolLifeTime parameter. Set it, for example, to 30.
   #    Restart FB, repeat test launch, wait for full completition and check again this chart.
   #    Do these steps until most of dark-magenta dots on Y-axis will be much lower than value of ExtConnPoolLifeTime.
   #
   use_es = 0


#:::::::::::::::::::::::::::::::::::
# SETTINGS RELATED TO LOCK CONFLICTS
#:::::::::::::::::::::::::::::::::::


   # When some session must change exicting document (rather than to create new), it chooses it using random selection.
   # This can lead to lot of UPDATE CONFLICTS between concurrent sessions, especially when number of documents is small.
   # Also, even when two sessions choose different documents but at least one of wares is the same, business actions can 
   # lead stock remainder for such ware become zero.
   # Further attempts to withdraw this ware lead to exception referring to inadmissible negative remainder.
   # This means that all previous work of this transaction was in vain and it has to rollback changes.
   #
   # We can separate sessions in such way that each of them will work within "sandbox" and never fall in conflict with
   # concurrent sessions for documents or stock remainders.
   #
   # Assign 1 to this parameter if you want to separate work of sessions and thus totally exclude exceptions related to
   # update conflicts and violation or check constraint defined for aggregated remainders value.
   # Otherwise set it to 0.
   # NOTE. When this parameter is 1 and 'use_es' is 2 then all following parameters must be uncommented:
   # 'mon_query_role' ; 'mon_usr_prefix' ; 'mon_usr_passwd'.
   # Recommended value: 1
   #
   separate_workers = 1


   # How many documents from other's "sandboxes" can be taken in processing by 'this' ISQL session, percent.
   # Value 0 means that we do not allow ISQL session to take any documents except those which was created by itself.
   # Value 100 means that we require for each ISQL session take for processing only OTHER's documents. 
   # Moreover, this also mean that we want ISQL session 'forget' about documents which were created by itself.
   # This will lead to extremely high number of lock-conflicts and very poor performance.
   # Recommened value: 0 - for benchmark purposes; 30...50 - for investigations.
   #
   update_conflict_percent = 0


   # How business operations should be selected: randomly or in predictable manner.
   # Allowed values:
   # random - on occasional basis, but with respect to priority/probability of business operatrions nature;
   # predictable - forcedly make every ISQL session to work using given sequence of business operations, i.e.
   #     create client order -> create order to supplier -> get invoice from supplier -> ...
   # Value 'predictable' was not deeply tested and currently can lead to poor performance.
   # See SP 'srv_random_unit_choice' for choising algorithm.
   # Recommened value: random
   #
   unit_selection_method = random


#::::::::::::::::::::::::::::::::::::
#  SETTINGS FOR ADDITIONAL LOGGING 
#::::::::::::::::::::::::::::::::::::


   # Do we add in ISQL logs detailed info for each actions that was registered while current transaction was performed ?
   # Note: value = 1 significantly increases disk I/O on client machine.
   # Do not use it if you are not interested on these data.
   # Recommended value: 0
   #
   detailed_info = 0



   # Setting for enabling queries to monitor tables in order to make detailed performance analysis.
   # When 0 then monitor tables are not queried.
   # When 1 then EVERY session will take two snapshots before and after execution of selected unit.
   # More detailed analysis with detalization down to separate stored procedures can be achieved
   # by updating setting 'mon_unit_list'.
   # When 2 then only ONE session is dedicated to gather monitoring data with obtaining data
   # that relates to ALL other working sessions. This is first session of launched.
   # It will call special SP 'srv_fill_mon_memo_consumption' every <mon_query_interval>-th second.
   # NOTE: delays for mon_unit_perf=2 between transactions will be done only when 'sleep_ddl' is defined,
   # e.g. when we make delays via UDF, without calls to external OS commands.
   #
   mon_unit_perf = 2


   # Following three parameters must be either all defined or all commented out.
   # They are used for two purposes:
   # 1) to gather monitoring data on behalf of non-privileged user about resources that were consumed by him and ONLY by him;
   # 2) to link "authority" of DML with worker ID. Need only when this DML is performed by connection in External Pool and
   #    changes of every worker must be separated (see description of parameters 'separate_workers' and 'use_es').
   #
   # Gathering of monitoring data leads to significant performance penalty if session works as SYSDBA: 
   # all other attachments have to put information about their state into special pool.
   # Benchmarks show that performance can fall for ~10x when all attachments work as SYSDBA and value of
   # parameter <mon_unit_perf> is 1 (i.e. every worker gathers monitoring data about himself *AND* all other workers).
   # But actually each worker is interested only about its own data from monitoring rather than others.
   #
   # Engine was improved in Firebird 3.x+ for such case: if session works as NON-privileged used then
   # its query to monitoring tables will not affect on other attachments which work under different logins.
   # One can use this improvement and require that test will launch every ISQL session so that it will work
   # with database as non-privileger user, with accessing to DB objects via special role with all needed grants.
   #
   # Parameter 'mon_query_role' specifies name of this role. If it is specified then test will create such role
   # and give it all grants that are needed for normal work. This role will be further granted to all non-privileged
   # users which are also created by test. Parameter 'mon_usr_prefix' must also be specified in this case.
   # If 'mon_query_role' is commented then all sessions will work as SYSDBA.
   # NOTE: actual only for Firebird 3.0 and above. Has no effect on Firebird 2.5.
   # Recommended value: any string that meets FB requirement to the name of ROLE, e.g.: tmp$oemul$worker
   #
   mon_query_role = tmp$oemul$worker


   # Prefix for each name of temporarily created users for work with database.
   # Each user name will be further provided with suffix like '0001', '0002' etc, up to the total number of sessions.
   # These users will be granted to use ROLE which name is defined by <mon_query_role> parameter (see above).
   # After test finish all of them will be dropped.
   # NOTE-1. Actual only for Firebird 3.0 and above. Has no effect on Firebird 2.5.
   # NOTE-2. Value must end with underscore character.
   # Recommended value: any string that meets FB requirement to the name of USER, e.g.: tmp$oemul$user_
   #
   mon_usr_prefix = tmp$oemul$user_


   # Password for temporarily created users. Do not set this it to trivial value because policy for passwords
   # can became more strict in the future versions of FB.
   # Value must not contain '=', '!' and '%' character because of parsing problems.
   #
   mon_usr_passwd = 0Ltp-Emu1


   # This setting can be used only when config parameter 'enable_mon_query' is 1.
   # List of top-level units (see 'business_ops' table) which performance statistics we want 
   # to be logged by querying  monitoring tables. Logging is done by SP srv_log_mon_for_traced_units.
   # Value can be single unit name or LIST of unit names delimited by forward slash.
   # Example:
   #     sp_make_qty_storno/sp_kill_qty_storno/sp_multiply_rows_for_qdistr/sp_multiply_rows_for_pdistr
   # Default value: // (two slashes) without any characters between them, i.e. no interested units for logging.
   #
   mon_unit_list = //


   # This setting is applied only when config parameter 'enable_mon_query' is 2.
   # Number of seconds between calls to SP that gathers monitoring data for all working attachments.
   # Monitor data will be gathered only by single (dedicated) isql session which is launched first.
   # Parameter 'sleep_ddl' must be uncommented and its value has to point on existent SQL script
   # with UDF declaration that implements delay.
   # Actual duration of delay, in seconds, will be evaluated as minimal of <mon_query_interval>
   # and <test_time> * 60 divided by 20.
   #
   mon_query_interval = 60



#:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#  SETTINGS FOR PREMATURE TERMINATION OF WORK BEFORE TIME EXPIRE
#:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::


   # Mnemonics of exceptions which must force test to be stopped (see calls of fn_halt_sign(gdscode)):
   #     'CK' -- halt if CHECK violation or 'not_valid' occurs (mostly this can be due to negative stock remainders)
   #     'PK' -- halt if PK or UK violation occurs
   #     'FK' -- halt if FK violation occurs // now n/a because test does not use foreign keys.
   #     'ST' -- halt if gdscode 335544842 appeared at the top of stack and logged into perf_log (strange problem only in 3.0 SC)
   # These mnemonics can be combined in list, i.e.: 'CK/PK/FK' - halt if CHECK or PK or FK violation occurs
   # Default: '/CK/' ==> force test to be stopped on attempt to write NEGATIVE values for stock remainders.
   # 12.02.2015: PK and FK violations *can* be detected only during heavy workload in procedures that operates with huge number
   # of records. These are: sp_make_qty_storno and sp_kill_qty_storno,
   # This can occur due to undefined order of UNDO actions inside the engine when some action must be cancelled.
   # Detailed investigation:
   #     sql.ru/forum/1142271/posledstviya-nepredskazuemo-neposledovatelnyh-otkatov-izmeneniy-pri-exception
   # Explanation by dimitr was sent privately to e-mail, letters date = 12.02.2015.
   #
   halt_test_on_errors = /CK/


   # How stock remainders should be verified BEFORE totalling turnovers (see procedure 'sp_make_invnt_saldo').
   #
   # Declarative CHECK constraint for non-negative QTY_* columns should NOT ever be fired in this test.
   # This parameter defined numeric value which bits must be interpreted as:
   #     bit 0 := 1 -- perform calls of procedure SRV_FIND_QD_QS_MISM in order to register mismatches between
   #                   doc_data.qty and total number of rows in QDISTR and QSTORNED tables for doc_data.id;
   #     bit 1 := 1 -- perform calls of procedure SRV_CHECK_NEG_REMAINDERS instead of actual totalling turnovers
   #                   to the table INVNT_SALDO. This value must be used only for debug purposes.
   #     bit 2 := 1 -- allow dump dirty data into debug tables for analysis, see sp ZDUMP4DBG, in case
   #                   when PK/FK or check constraint is violated (see also parameter 'halt_test_on_errors')
   #                   NOTE: when bit#2 has value 1 then parameter 'create_with_debug_objects' must be 1
   #                   to force build scenario create auxiliary Z-tables.
   #
   # This parameter was used during test development and can be useful in case of some changes/refactoring
   # in test logic. Normally its value must be 1.
   #
   qmism_verify_bitset = 1


   # OPTIONAL.
   # Parameter 'use_external_to_stop' defines name of text file that can be used for premature stop all working isql sessions.
   # This parameter is NOT required, i.e. it can be commented. In this case test can be stopped by running temporary script
   # '$tmpdir/1stoptest.tmp.sh' which is created every time when test starts by script '1run_oltp_emul.sh'.
   # This script works normally for most cases except extremely high workload when establishing of new connect is difficult.
   #
   # When extremely high workload is used then following message can appear on every attempt to establish new attachment:
   #     Statement failed, SQLSTATE = 08004
   #     connection rejected by remote interface
   #
   # In such case it can be more reliable to use EXTERNAL TABLE (i.e. TEXT FILE) to make all attachments to stop their work. 
   # This is so because every running session 'looks' from time to time into this external table and checks existense of at 
   # least one record in it. So, test will be quickly self-stopped when at least one non-empty line exists there. 
   # Please note that you have to make this file EMPTY before every new test run. Test can not do that when server is remote.
   #
   # If you have decided to use EXTERNAL FILE then following steps must be done for premature terminate all test activity:
   #     1. Open that file in text editor and type one ascii-character there;
   #     2. Press ENTER and save this file.
   #     3. Make this file empty again when all isql sessions terminated their work.
   # Also, please note on value of parameter "ExternalFileAccess" in firebird.conf:
   #     1. When ExternalFileAccess = FULL then 'use_external_to_stop' must be full path and name of text file that will be 
   #        queried by every attachment as 'stop flag'.
   #     2. When ExternalFileAccess = RESTRICTED then 'use_external_to_stop' must be only NAME of file, without path.
   #
   #     <tmpdir>/1stoptest.tmp.sh
   #
   # use_external_to_stop = <no value defined>


#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
#  SETTINGS FOR DATABASE CREATION PROCESS AND INITIAL DATA FILLING 
#::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
    #
    # *** NOTE *** 
    # Following settings except 'create_with_fw' and 'create_with'sweep'
    # will be IGNORED if database exists and has required number of documents.
    # If parameter 'host' is one of: {'localhost', '127.0.0.1'} then current
    # values of 'create_with_fw' and 'create_with'sweep' will be applied to DB
    # every time before launching ISQL sessions.


   # Setting for FORCED WRITES attribute which must be written in the DB header before all sessions launch.
   # Value can be one of: sync | async
   # RECOMMENDED value:
   #     sync - if you want to test performance for database that is not involved in replication;
   #     async - if you plan to use DB which will be replicated to other host.
   #             (note that in such case you must set parameter 'used_in_replication' to 1).
   #
   create_with_fw = sync


   # Setting for SWEEP INTERVAL which causes auto sweep start.
   # Value must be not less than -1.
   # Value -1 means that default value (20000) will be written into DB header.
   # Sweep starts when OST-OIT more than this threshold. Value 0 disables sweep.
   #
   # RECOMMENDED value for create_with_sweep is 0 (zero).
   # Sweep start can lead to unpredictable affect on performance, especially for short test duration.
   #
   create_with_sweep = 0


   # Should script be paused if database does not exist or its creation
   # did not finished properly (e.g. was interrupted; 1=yes; 0=no) ?
   # You have to set this parameter to 0 if this batch is launched by 
   # scheduler on regular basis. Otherwise it is recommended to set 1.
   #
   wait_if_not_exists = 0


   # Should script be paused after creation database objects before starting
   # initial filling with <init_docs> documents (mostly need only for debug; 1=yes, 0=no) ?
   #
   wait_after_create = 0


   # Number of documents, total for all their types, needed for initial data population.
   # Command scenario will compare number of existing document with this
   # and create new ones only if {init_docs] still greater than obtained.
   #
   # *** NOTE *** THIS VALUE IS OBSOLETE, LEAVE IT EQUAL TO 0 (ZERO) ***
   #
   # Instead of generating dosuments by single attachment it is much more properly (and faster) to assign some big value 
   # to 'warm_time' parameter (say, 1440 which means to run for 1 day) and also set 'test_time' to 0 (zero). 
   # When size of database will reach value that you consider as enough then just stop the test by running batch 
   # '$tmpdir/1stoptest.tmp.sh' which always is created when test starts.
   #
   init_docs = 0


   # This parameter actual only when 'init_docs' greater than 0 and 'separate_workers' is 1, i.e. when you want to separate 
   # each ISQL session in such way that they will not ever meet update conflicts during work. In other cases value if this
   # parameter is ignored.
   # If you decide to generate initial quantity of documents by using old 'init_docs' value then assign to 'expected_workers' 
   # value that is equal to the  number of ISQL sessions that is expected to run.
   #
   expected_workers = 100


   # Actual only when 'init_docs' greater than 0 and FB mode is Classic Server or SuperClassic. Will be ignoired in SuperServer.
   # Number of pages for usage during init data population ("-c" switch for ISQL). Used ONLY during phase of initial data population.
   # Make sure that it is LESS than FileSystemCacheThreshold, which default is 65536.
   #
   # *** NOTE *** THIS VALUE IS OBSOLETE, LEAVE IT EQUAL TO 10000 ***
   #
   init_buff = 4096


   # Actual only when 'init_docs' greater than 0
   # Should command scenario (1run_oltp_emul) be PAUSED after finish creating
   # required initial number of documents (see parameter 'init_docs'; 1=yes, 0=no) ?
   # Value = 1 can be set if you want to make copy of .fdb and restore later
   # this database to 'origin' state. This can save time because of avoiding need
   # to create [init_docs] again:
   #
   wait_for_copy = 0


   # Do we want to create some DEBUG objects (tables, views and procedures)
   # in order to:
   # 1) make dumps of all data from tables when critical error occurs;
   # 2) make miscelaneous diagnostic queries via "Z_" views.
   # Value=1 will cause "oltp_misc_debug.sql" be called when build database.
   # NB: setting 'QMISM_VERIFY_BITSET' must have bit #2 = 1 when this value = 1.
   # (see oltp_main_filling.sql)
   # Recommended value: 1
   #
   create_with_debug_objects = 1


   # Test has two tables which are subject of very intensive modifications: QDistr and QStorned.
   # Performance highly depends on time which engine spends on handling DP, PP and index pages
   # of this tables - they are "bottlenecks" of schema. Database can be created either with two
   # these tables or with several "clones" of them (with the same stucture). The latter allows
   # to "split" workload on different areas and reduce low-level lock contention.
   # Should heavy-loaded tables (QDistr and QStorned) be splitted on several different tables,
   # each one for separate pair of operations that are 'source' and 'target' of storning ?
   # Avaliable values: 
   #     0 = do NOT split workload on several tables (instead of single QDistr and QStorned);
   #     1 = USE several tables with the same structure in order to split heavy workload on them.
   #         NOTE (2019). Not only Qdistr and QStorned but also PERF_LOG table will be 'splitted' onto
   #         several tables (with names PERF_SPLIT_01...PERF_SPLIT_09) when this parameter is set to 1. 
   # Recommended value: 1.
   #
   create_with_split_heavy_tabs = 1


   # Whether heavy-loaded table (QDistr or its XQD_* clones) should have only one ("wide")
   # compound index or two separate indices (1=yes, 0=no).
   # Number of columns in compound index depends on value of two parameters:
   #     1) 'create_with_split_heavy_tabs' and
   #     2) 'create_with_separate_qdistr_idx' (this).
   # Order of columns is defined by parameter 'create_with_compound_idx_selectivity'.
   # Recommended value: 0.
   #
   create_with_separate_qdistr_idx = 0


   # Parameter 'create_with_compound_columns_order' defines order of fields in the starting part
   # of compound index key for the table which is subject to most heavy workload - QDistr. 
   # Avaliable options:
   #     'most_selective_first' or
   #     'least_selective_first'.
   # When choice = 'most_selective_first' then first column of this index will have selectivity = 1 / [W],
   # where [W] = number of rows in the table 'WARES', depends on selected workload mode.
   # Second and third columns will have poor selectivity = 1/6.
   # When choice = 'least_selective_first' then first and second columns will have poor selectivity = 1/6,
   # and third column will have selectivity = 1 / [W].
   #
   # Actual only when create_with_split_heavy_tabs = 0.
   # Recommended value: most_selective_first
   #
   create_with_compound_columns_order = most_selective_first


#:::::::::::::::::::::::::::::::::::::::::::::::::::::
#  SETTINGS FOR SCHEDULED-BASIS JOB AND TEST REPORT
#:::::::::::::::::::::::::::::::::::::::::::::::::::::


   # Number of minutes since test launch for which evaluation of performance score is omited because database is 'cold' (not in cache).
   # Means the same as 'ramp-up' period in TPC-C specification: we have to allow all sessions to establish  attachments and read some
   # data into Firebird page cache.
   # Recommended value: DBSize_Gb/2, where DBSize_Gb is size of database in Gb, but not less than 30 minutes.
   # To estimate whether value of this parameter is apropriate, run test for 2-3 hours and look after its finish in report 
   # "Performance per minute". Performance counter at the end of <warm_time> period must be close to values for subsequent 20-30 minutes.
   # See also TPC-C specification rev 5.11:
   # * 5.6.4 (page 78) - graphical explanation of ramp-up period;
   # * Appendix C (page 132) - numerical quantities summary.
   #
   warm_time = 0


   # Duration of main test phase which starts after 'ramp-up'. Means the same as 'measurement interval' in TPC-C specification.
   # Overall performance score is evaluated as total number of successfully completed transactions during this phase divided by <test_time>.
   # At the end of this phase test will stop itself, i.e. you do not have to interrupt ISQL sessions.
   # Note that TPC-C requires minimum 120 minutes for this phase, but your system must allows to run test during 480 minutes - and this
   # value does not include <warm_time> phase (see TPC-C rev 5.1, 5.5.2.1, page 75).
   # ATTENTION. Reports and performance score for test_time less than 120 minutes must be considered as unreliable (doubtful).
   # Recommended value: at least 180.
   #
   test_time = 55


   # OBSOLETE. WILL BE REMOVED LATER.
   # This parameter used earlier for one of reports which was removed.
   # Currently its value will be ignored.
   #
   test_intervals = 30


   # OPTIONAL.
   # Backup(!) name of dedicated database that serves as storage for test settings
   # and final report of every completed test.
   # When test finished, this backup is restored to temporary database, new data are saved
   # and then this database is backed up again to this .fbk.
   #
   # Scenario 'oltp_overall_report' (see 'utils' sub-directory) will restore from this backup
   # for generating overall report, so in that case this parameter must be defined.
   #
   # Firebird service account must have access rights to operate with this file.
   # It is recommended to put this .fbk in the same directory as <dbnm>.
   #
   # NOTE-1. *BACKUP* must be speficied here rather then .fdb file!
   # NOTE-2. DO NOT use "$" for evaluation of this parameter value. Use only absolute paths.
   #
   # Examples:
   # results_storage_fbk = /var/db/oltp-results-storage.fbk

   results_storage_fbk = /opt/oltp-emul/data/oltp-hq30-results.fbk


   # OPTIONAL. LINUX ONLY.
   # Utility to compress HTML report and (if FB crash occured) stack trace of dump.
   # Compressed result will be saved in the database defined by <results_storage_fbk>.
   # By default, GZIP utility will be used that must present on most Linux instances.
   # Supported compressors: gzip, p7zip, zstd and zip
   # If none of them can be found then HTML report will be stored without compression.
   # Extraction of HTML report will be done by 'oltp_overall_report' scenario which supposes
   # that apropriate packages already was installed, namely:
   #     'gzip'  - to extract from .gz; binary for extraction: /usr/bin/7za
   #     'p7zip' - to extract from .7z, .gz and .zip; binary for extraction: /usr/bin/7za
   #     'zstd'  - to extract from .zstd; binary for extraction: /usr/bin/zstd
   # Note that 7za and zstd provide much higher compression than ZIP or GZIP.
   # This parameter can be left commented out if you don't plan to run test on regular basis
   # with transferring its (compressed) results to scenario 'oltp_overall_report'.
   #
   # Examples:
   # report_compress_cmd=/usr/bin/gzip
   # report_compress_cmd=/usr/bin/7za
   # report_compress_cmd=/usr/bin/zstd
   # report_compress_cmd=/usr/bin/zip
   #
   # report_compress_cmd = <no value defined>


   # This parameter is used in 'oltp-scheduled' scenario and points to the name of etalone DB which serves
   # as source for copy to work DB before every new test starts.
   # It is possible to get following error when DB was moved from one host to another without b/r:
   #     Statement failed, SQLSTATE = 22021
   #     COLLATION NAME_COLL for CHARACTER SET UTF8 is not installed
   # In this case try following command:
   #     <fbc>/gfix -icu <etalon_dbnm>
   # NOTE.
   # It is recommended to store this database in the same directory as <dbnm> and change its state to 'full shutdown'
   # or at least make it read only.
   #
   etalon_dbnm = $(dirname "$dbnm")/oltp_30.etalone.fdb


   # Create report in HTML format (along with plain text) ? Avaliable options: 1 = yes, 0 = no.
   # When parameter 'results_storage_fbk' is uncommented then HTML report will be saved in dedicated database and later
   # will be extracted from there by {OLTP_ROOT}\util\oltp-overall-report\oltp_overall_report batch scenario.
   # NOTE: time of reports creation will be increased if this parameter is set to 1.
   #
   make_html = 1

   # Colors for google charts when HTML report is created. These values are used in
   # $OLTP_EMUL_HOME/util/oltp-overall-report/oltp_overall_report.sh
   html_chart_color_perf_score = magenta
   html_chart_color_memo_all = magenta
   html_chart_color_memo_att = magenta
   html_chart_color_memo_trn = magenta
   html_chart_color_memo_stm = magenta

   # Should DB statistics be included into final report ? Avaliable options: 1 = yes, 0 = no.
   # When this parameter is 1, statistics output is parsed in order to get data about amount of record versions 
   # and maximal versions for each table. Final report will contain auxiliary table with aggregated info about versions.
   # WARNING. This operation can take lot of time on big databases. Replace this setting with 0 for skip this action.
   #
   run_db_statistics = 0


   # Should online validation be done after test finish ? Avaliable options: 1 = yes, 0 = no.
   # Result of validation will not include messages about passed pointer pages in order to make report shorter.
   # WARNING. This operation can take lot of time on big databases. Replace this setting with 0 for skip this action.
   #
   run_db_validation = 0


   # This parameter defines form of final report file name which might contain info about FB and main DB/test settings.
   # Value can be one of follows:
   #     regular   - appropriate for quick found performance degradation, without details of test settings
   #     benchmark - appropriate for analysis when different settings are applied
   #
   # Report file name always consists of tokens that reflect:
   #     * Performance score;
   #     * FB snapshot number;
   #     * ServerMode value;
   #     * Test phase duration (hours and minutes);
   #     * Number of worked sessions;
   #     * Forced Writes value;
   #     * Number of CPU cores;
   #     * Total RAM size, Gb;
   #     * Timestamp when test started.
   # Example of report name when this parameter is 'regular':
   #     YYYYmmDD_HHMM_score_06543_build_31236_ss30__3h00m_100_att_fw__on_cpu4_ram32.txt
   # Example of report name when this parameter is 'benchmark':
   #     ss30_fw_off_split_most__sel_1st_one_index_score_06915_build_31236__3h00m_100_att_YYYYmmDD_HHMM_cpu4_ram32.txt
   #     (where 'YYYYmmDD_HHMM' is timestamp of test start)
   #
   # Available options when uncommented: regular | benchmark
   #
   file_name_with_test_params = regular


   # Suffix for adding at the end of report name. CHANGE this value to some useful info about host location, 
   # operating system, hardware specifics, FB instance etc.
   # For example, to use value of 'hostname' command set this parameter to: $($(echo hostname))
   # You do not need to specify here number of CPU cores or RAM size: they will be added to file name by test itself.
   #
   file_name_this_host_info = $($(echo hostname))


   # Do we want to include in the report details about server hardware and OS ?
   # Avaliable options: 1 = yes, 0 = no.
   # This setting has sense only when you launch ISQL sessions at the server which you are 
   # interesting on, i.e. when value of 'host' parameter is localhost or 127.0.0.1
   # Some kind of information can be inaccessible if you work as user without admin rights.
   # NOTE: scenario that is launched by cron will see PATH=/usr/bin:/bin, i.e. some utilities from /usr/sbin
   # will not be avaliable. Some of these utilities ((e.g. fdisk and dmidecode) are used to gather hardware data.
   # This can be solved if cron job line will contain: " . /etc/profile; " before the command that is to be launched.
   # Example:
   # 0   10,20     *       *       *     . /etc/profile; /opt/oltp-emul/1run_oltp_emul.sh 30 100
   #
   # See also: https://unix.stackexchange.com/questions/148133/how-to-set-crontab-path-variable
   #
   gather_hardware_info = 1


#::::::::::::::::::::::::::::::::::::::::::::::::::::
#  EXOTIC SETTINGS (USAGE HAS NOT BEEN DEEPLY TESTED)
#::::::::::::::::::::::::::::::::::::::::::::::::::::


   # Does Firebird running in embedded mode ? (1=yes, 0=no)
   #
   is_embed = 0


