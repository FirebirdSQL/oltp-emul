# Configuration parameters for OLTP-EMUL test for parsing by
# LINUX command scenario '1run_oltp_emul.sh' and launching 
# test against Firebird 2.5

####################################################################
# Do *NOT* remove or make empty (undefined) any of these parameters.
####################################################################

# Folder with Firebird console utilities (do NOT use final backslash here).
fbc=/opt/fb25sc/bin

# Folder where to store work and error logs (do NOT use final backslash here):
tmpdir=/var/tmp/logs.oltp25

# is_embed=1 - if Firebird runs in embedded mode, otherwise 0
is_embed=0

# Alias or full path and file name of database.
# If you want this database be created by test itself, specify it as
# FULL PATH and file name. No spaces or non-latin characters can be here!
dbnm = /var/db/fb25/oltp25b.fdb

# Should set transaction command include NO AUTO UNDO clause ?
# Recommended value: 1
no_auto_undo=1

# Do we use tee/supertee utility to provide timestamps for error messages 
# before they are logged in .err files ?
use_mtee=0

# Add in ISQL logs detailed info for each iteration (select from perf_log...) ?
# Note: value = 1 will increase workload on DISK on client machine.
# Do not use if you are not interested on data of table 'perf_log'.
detailed_info=0

# Number of documents, total of all types, for initial data population.
# Command scenario will compare number of existing document with this
# and create new ones only if <init_docs> still greater than obtained.
# Recommended value: at least 30000 
init_docs=30000


# Number of pages for usage during init data population ("-c" switch for ISQL).
# Actual only for CS and SC, will be ignored in SS. Used ONLY during phase of
# initial data population and is IGNORED on main phase of test.
# Make sure that it is LESS than FileSystemCacheThreshold, which default is 65536.
init_buff=32768

# Should script be PAUSED after finish creating <init_docs> documents ?
# Value = 1 can be set for making copy of .fdb and restore initial database
# it on the following runs thus avoiding creation of <init_docs> again:
wait_for_copy=1

# Time (in minutes) to warm-up database after initial data population
# will finish and before all following operations will be measured:
# Recommended value: at least 20 for Firebird 2.5
warm_time=20

# Limit (in minutes) to measure operations before test autostop itself:
# Recommended value: at least 60
test_time=60

# Rest params are not needed if embedded mode but should be non-empty 
# for this command scenario:
usr=SYSDBA
pwd=masterke
host=192.168.0.220
port=3252

