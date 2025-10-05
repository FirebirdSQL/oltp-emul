# Config file for oltp_overall_report.sh scenario.
# Firebird MOST RECENT major version must be installed on machine
# where we make overall report with OLTP-EMUL results.
# It is supposed that such FB instance can be found in the folder that
# is specified by parameter <fbc> of OLTP-EMUL config.
# Currently such major version is 5.x
# -----------------------------------
# NOTE: Python and firebird-driver package must be installed before run
# this scenario.
# Results of OLTP-EMUL on different Firebird versions will be restored
# from apropriate <results_storage_fbk> files.
########################################################################

FB_HEAD_VERSION=60

# must be the same as 'FBnn_LOCK_DIR' parameter for appropriate 'head' major version
# of vanilla Firebird defined in oltp-scheduled_config.nix:
FB_HEAD_LOCK_DIR=/dev/shm/fb60_lock

# Max number of seconds to wait until firebird process:
# either starts to listening to port (when it is launched by issuing 'fbguard -daemon')
# or is terminated (after we send signal SIGTERM to fbguard and firebird) and releases port.
# Max limit described in TCP doc is 4 minutes (when socket has TIME_WAIT state after kill with SIGTERM).
# https://stackoverflow.com/questions/5106674/error-address-already-in-use-while-binding-socket-with-address-but-the-port-num
# http://www.softlab.ntua.gr/facilities/documentation/unix/unix-socket-faq/unix-socket-faq-4.html#ss4.2
# http://www.softlab.ntua.gr/facilities/documentation/unix/unix-socket-faq/unix-socket-faq-2.html#time_wait
#
SECONDS_WAIT_FOR_PORT=241


# Path to config that is used by OLTP-EMUL for test Firebird 6.x.
# Following parameters will be searched there:
# usr; pwd; fbc; results_storage_fbk
# Values of <usr> and <pwd> will be used here for create/open database
# with overall results using client library from <fbc> folder.
# Database from <results_storage_fbk> will be restored for gathering
# results of runs on FB 6.x, see variable 'DB_OVERALL_FILE'
# in oltp_overall_report batch scenario
#
oltp60_config=../../src/oltp-fb60.conf.nix

# Path to config that is used by OLTP-EMUL for test Firebird 5.x.
# Database with results will be restored using fresh <master> FB snpshot
# which home is defined by <fbc> in oltp60_config
#
oltp50_config=../../src/oltp-fb50.conf.nix

# Path to config that is used by OLTP-EMUL for test Firebird 4.x.
# Database with results will be restored using fresh <master> FB snpshot
# which home is defined by <fbc> in oltp60_config
#
oltp40_config=../../src/oltp-fb40.conf.nix

# Should we create DB_OVERALL or open existing ?
# Normally value of this parameter must be 0.
# Set it to 1 if DB became obsolete vs oltp_overall_report_DDL.sql
#
RECREATE_DB=1

# Folder for storing generated HTML report and logs of this scenario:
#
LOGDIR=/var/tmp/oltp_overall_report_fb

# Folder for storing HTML reports for of each OLTP-EMUL runs:
#
DETAILS_DIR=$LOGDIR/details

# Name of HTML file with main (overall) report. Must be specified without path.
# File will be created by Python script in the folder defined by <LOGDIR> parameter.
#
MAIN_RPT_FILE=oltp_overall_report.html

# max age for logs, in days:
#
LOGS_MAX_AGE=30

PYTHON_HOME=/opt/venv/qa_env/bin

PY_VENV_RUN=$PYTHON_HOME/activate

PYTHON_BIN=$PYTHON_HOME/python3


# Limit for rows to be shown in the final table.
# Used in Python scenario, do NOT change its name without adjusting in in .py!
# Set this value to 0 if report must be with unlimited number of rows.
# Charts in any case will not contain more than value defined by MAX_POINTS_IN_CHART.
#
MAX_ROWS_IN_REPORT=0

# Limit for number of points in charts. Must be adjusted with current screen resolution:
#
MAX_POINTS_IN_CHART=250

# Default width and height for charts.
# Can be overwritten in .py by specifying divWidth and divHeight key/value
# pairs when call write_chart_script_beg():
#
DEFAULT_CHART_DIV_WIDTH=1800
DEFAULT_CHART_DIV_HEIGHT=350

# Default values for chartArea:{left:NNN, top:MM}
# DO NOT assign value less than 100 for DEFAULT_CHART_AREA_LEFT otherwise numbers on Y-axis will not be seen.
# DO NOT set assign value less than 20 for DEFAULT_CHART_AREA_TOP otherwise legends will not be seen.
DEFAULT_CHART_AREA_LEFT=100
DEFAULT_CHART_AREA_TOP=30

# 10.04.2023
# CHART_COLORS_PERF_SCORE (defined dynamically in .sh): color for charts 'Performance score: number of <...> actions per minute, in average'
# CHART_COLORS_MEMO_ALL (defined dynamically in .sh): color for chart 'Memory usage: peak values of mon$memory_used for DB level, Mb'
# CHART_COLORS_MEMO_ATT (defined dynamically in .sh): color for chart 'peak memory used, ATTACHMENTS level, Mb':
# CHART_COLORS_MEMO_TRN (defined dynamically in .sh): color for chart 'Memory usage: peak values of mon$memory_used for transactions, Mb'
# CHART_COLORS_MEMO_STM (defined dynamically in .sh): color for chart 'Memory usage: peak values of mon$memory_used for statements, Mb'

#USE_PREDEFINED_TABLE_HDR=oltp_overall_report.hdr


DECOMPRESS_ZIP=/usr/bin/7za
DECOMPRESS_7Z=/usr/bin/7za
DECOMPRESS_ZST=/usr/bin/zstd

P7ZCMD=/usr/bin/7za

SSH_UPLOAD_ENABLED=1
SSH_PRIVATE_KEY_FILE=../../private/oltp_upload.POSIX.ppk
#/root/.ssh/qa_upload.ppk
SSH_UPLOAD_HOST_DATA=root@49.12.10.46
SSH_RESULTS_HOME_DIR=/var/db/qa-reports/archive

# Example for cron:
## Get report for just completed launch:
# 10   13,16,19,22     *       *       *     /opt/oltp-emul/oltp_overall_report.sh
# 10   1,4,7,10        *       *       *     /opt/oltp-emul/oltp_overall_report.sh
## Next launch of test:
# 20   13,16,19,22     *       *       *     /opt/oltp-emul/oltp-scheduled.sh 30 100 SS
# 20   1,4,7,10        *       *       *     /opt/oltp-emul/oltp-scheduled.sh 40 100 SS
