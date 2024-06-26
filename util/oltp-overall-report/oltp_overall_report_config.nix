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

MOST_RECENT_MAJOR_FB=50

# Path to config that is used by OLTP-EMUL for test Firebird 4.x.
# Following parameters will be searched there:
# usr; pwd; fbc; results_storage_fbk
# Values of <usr> and <pwd> will be used here for create/open database
# with overall results using client library from <fbc> folder.
# Database from <results_storage_fbk> will be restored for gathering
# results of runs on FB 5.x, see variable 'DB_OVERALL_FILE'
# in oltp_overall_report batch scenario
#
oltp50_config=../../src/oltp50_config.nix


# Path to config that is used by OLTP-EMUL for test Firebird 4.x.
# Database with results will be restored on Firebird 5.x which home
# is defined by <fbc> in oltp50_config
#
oltp40_config=../../src/oltp40_config.nix

# Path to config that is used by OLTP-EMUL when test Firebird 3.x.
# Database with results will be restored on Firebird 5.x which home
# is defined by <fbc> in oltp50_config
#
oltp30_config=../../src/oltp30_config.nix


# Should we create DB_OVERALL or open existing ?
# Normally value of this parameter must be 0.
# Set it to 1 if DB became obsolete vs oltp_overall_report_DDL.sql
#
RECREATE_DB=1

# Folder for storing generated HTML report and logs of this scenario:
#
LOGDIR=/var/tmp/oltp_overall_report

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

# Full path to Python executable. Minimal required version: 3.4
# Following 3d-party packages must be installed before this script launch: fdb.
# To install FDB driver run:
#     1. CentOS: yum install python-pip / UBUNTU: apt-get install python3-pip
#     2. pip3 install fdb
#
PYTHON_BINARY=/usr/bin/python3

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

DECOMPRESS_ZIP=/usr/bin/7za
DECOMPRESS_7Z=/usr/bin/7za
DECOMPRESS_ZST=/usr/bin/zstd

P7ZCMD=/usr/bin/7za

SSH_UPLOAD_ENABLED=0
SSH_PRIVATE_KEY_FILE=/root/.ssh/qa_upload.ppk
SSH_UPLOAD_HOST_DATA=root@49.12.10.46
SSH_RESULTS_HOME_DIR=/var/db/fbt-reports/archive

# Example for cron:
## Get report for just completed launch:
# 10   13,16,19,22     *       *       *     /opt/oltp-emul/oltp_overall_report.sh
# 10   1,4,7,10        *       *       *     /opt/oltp-emul/oltp_overall_report.sh
## Next launch of test:
# 20   13,16,19,22     *       *       *     /opt/oltp-emul/oltp-scheduled.sh 30 100 SS
# 20   1,4,7,10        *       *       *     /opt/oltp-emul/oltp-scheduled.sh 40 100 SS
