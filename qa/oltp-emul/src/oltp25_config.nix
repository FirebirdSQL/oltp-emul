####################################################################
# OLTP-EMUL test for Firebird 2.5 & 3.0 - configuration parameters.
# This file is used for running ISQL sessions on LINUX machine
# and test Firebird 2.5.
# Parameters are extracted by '1run_oltp_emul.sh' command scenario.
# Do *NOT* remove or make empty (undefined) any of these parameters.
####################################################################

# Folder with Firebird console utilities, with or w/o trailing slash.
fbc=/opt/fb25/bin

# Folder where to store work and error logs, with or w/o trailing backslash.
tmpdir=/var/tmp/logs.oltp25

# is_embed=1 - if Firebird runs in embedded mode, otherwise 0
is_embed=0

# Alias or full path and file name of database.
# If you want this database be created by test itself, specify it as
# full path and file name. No spaces or non-latin characters can be here!
dbnm = /var/db/fb25/oltp25.fdb

# Should set transaction command include NO AUTO UNDO clause ?
# Recommended value: 1
no_auto_undo=1

# Do we use tee.exe utility to provide timestamps for error messages before they
# are logged in .err files ? 
# (Windows only. Not implemented for Linux, please leave = 0)
use_mtee=0

# Do we want to create some DEBUG objects (tables, views and procedures)
# in order to:
# 1) make dumps of all data from tables when critical error occurs;
# 2) make miscelaneous diagnostic queries via "Z_" views.
# Value=1 will cause "oltp_misc_debug.sql" be called when build database.
# NB: setting 'C_CATCH_MISM_BITSET' must have bit #2 = 1 when this value = 1.
# (see oltp_main_filling.sql)
make_debug_dbos=0

# Add in ISQL logs detailed info for each iteration (select from perf_log...) ?
# Recommended value: 0
# Note: value = 1 will increase workload on DISK on client machine.
# Do not use if you are not interested on data of table 'perf_log'.
detailed_info=0

# Number of documents, total of all types, for initial data population.
# Command scenario will compare number of existing document with this
# and create new ones only if <init_docs> still greater than obtained.
# Recommended value: at least 30000 
init_docs=30000

# Number of pages for usage during init data population ("-c" switch for ISQL),
# actual only for CS and SC, will be ignored in SS.
# (check that it is LESS than FileSystemCacheThreshold, which default is 65536)
init_buff=32768

# Should script be PAUSED after finish creating <init_docs> documents
# (for making copy of .fdb and restore it on the following runs thus
# avoiding to make init_docs again):
wait_for_copy=0

# Time (in minutes) to warm-up database after initial data population
# will finish and before all following operations will be measured:
# Recommended value: at least 20 for Firebird 2.5
warm_time=20

# Limit (in minutes) to measure operations before test autostop itself:
# Recommended value: at least 60
test_time=180

# Rest params not needed if embedded mode 
# but should be non-empty to run batch:

usr=SYSDBA
pwd=masterke
host=127.0.0.1
port=3050

