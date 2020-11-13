# Config file for oltp-scheduled.sh scenario.
# Firebird instance must present in <fbc> folder that is specified
# in OLTP-EMUL config that corresponds to <FB_MAJOR> parameter.
#
###################################### CAUTION ###########################################
#
# By default, Firebird instance will be stopped and replaced when ths script works!
# Be sure that parameter <fbc> from every OLTP-EMUL config file DOES NOT point
# to some FB instance that is important for you!
# NEVER set value of this parameter to the folder where crusial FB instance lives.
#
##########################################################################################

# NOTE: scenario that is launched by cron will see PATH=/usr/bin:/bin, i.e. some utilities from /usr/sbin
# (e.g. fdisk and dmidecode) will not be avaliable. This can be solved if line of cron job will contain
# " . /etc/profile; " before the command that is to be launched.
# See also: https://unix.stackexchange.com/questions/148133/how-to-set-crontab-path-variable
# Example for warm_time=30 and test_time=120:
# 55   13,16,19,22     *       *       *     . /etc/profile; /opt/oltp-emul/oltp-scheduled.sh 30 100 SS
# 55   1,4,7,10        *       *       *     . /etc/profile; /opt/oltp-emul/oltp-scheduled.sh 40 100 SS

############################################################################
###   S E T T I N G S    F O R    D O W N L O A D    S N A P S H O T S   ###
############################################################################

# NB! There is NO parameter in this config that prevents downloading/replacing FB.
# If these actions must be SKIPPED, you must explicitly specify 4th command-line
# argument for oltp-scheduled.bat as 0, e.g.:
#
# oltp-scheduled.sh <FB_MAJOR> <NUM_OF_SESSIONS>  <MODE>  0


# Root URL where daily updated Firebird snapshots live:
FB_SNAPSHOTS_URL=http://web.firebirdsql.org/download/snapshot_builds/linux

# Suffix for download FB 2.5.x:
FB_SUFFIX_25=fb2.5

# Suffix for download FB 3.x:
FB_SUFFIX_30=fb3.0

# Suffix for download FB 4.x:
FB_SUFFIX_40=fbtrunk

# Extension of snapshot files:
FB_SNAPSHOT_SUFFIX=.amd64.tar.gz

# Should we also download .debug package ?
GET_DEBUG_PACKAGE=0

# Optional. Setting for download using proxy.
# From man curl:
# -x, --proxy <[protocol://][user:password@]proxyhost[:port]>
# Use the specified HTTP proxy. 
#  If the port number is not specified, it is assumed at port 1080
#PROXY_DATA="--proxy http://172.16.210.203:8080"
# Path to root directory of OLTP-EMUL, relatively current folder:
OLTP_ROOT_DIR=../..


###########################################################################
###   S E T T I N G S    F O R    S E N D I N G    T O    E - M A I L   ###
###########################################################################

# Downloaded FB snapshot will be sent to e-mail using curl console utility
# which will be extracted by this scenario from <CURL_ZIP> file.
# To SKIP this sending make commented any of following parameters:
# 'mail_hdr_from', 'mail_pwd_from', 'mail_hdr_to', 'mail_smtp_url'

###################################################
# NOTES FOR YANDEX MAIL.
# In case of receiving error:
# "535 5.7.8 Error: authentication failed: This user does not have access rights to this service"
# - open web-page of yandex e-mail and goto: Mail -> All settings -> Email clients
# Under label "Use a mail client to retrieve your Yandex mail" turn on checkbox:
# "From the imap.yandex.com server via IMAP"
# Ensure then that "Portal password" is turned ON.
###################################################
#
# DO NOT specify gmail: they deny .7z attachments!
#
mail_smtp_url=smtps://smtp.yandex.ru:465
#mail_hdr_from=fb-builds@yandex.ru
mail_pwd_from=qwerty
mail_hdr_to=fb-builds@yandex.ru
mail_hdr_subj=FB_daily_build
curl_verb=--verbose
curl_insec=--insecure

# Max size of attachments, in bytes, for placing in one e-mail message.
# Entire snapshot will be splitted on volumes with size that
# is specified by this parameter:
#
max_size_without_split=12000000

# Delay between subseqent e-mail messages in order to prevent denial caused too frequent messages
# ("451 4.5.1 The recipient <some_name@company.com> has exceeded their message rate limit").
# This is actual for Yandex mailbox when sending several volumes for one FB snapshot.
#
mail_delay_seconds=15

############################################################################

# Additional settings for test database:
#
# Should etalone database state be changed to backup-lock before oltp-emul launch ?
# If 1 then command $FB_HOME/bin/nbackup -L $dbnm will be applied to working DB:
BACKUP_LOCK=0

# Folder where script for start FB daemon will be created after install.sh finish.
# NOTE: following will be always added to the script which starts FB daemon:
# LimitNOFILE=10000
# LimitCORE=infinity

SYSDIR_CENTOS=/usr/lib/systemd/system
SYSDIR_UBUNTU=/lib/systemd/system

# Pattern for filtering processes for which we want to create stack trace.
# Notes:
# 1. Do NOT enclose into any kind of quotes;
# 2. Names are separated by PIPE sign with TWO backslash characters before it;
# 3. Every name of executable process must ends with dollar sign.
FB_BIN_PATTERN=\\|fb_inet_server\\|fb_smp_server\\|fbserver\\|firebird\\|isql\\|gstat\\|gfix\\|gbak\\|fbsvcmgr\\|fb_lock_print\\|

#######################################################
###  L O G S    R O T A T I O N    S E T T I N G S  ###
#######################################################

# Following three parameters define max number of files in $tmpdir before
# they will be deleted, starting from oldest.
# 1. Limit for logs of this script runs:
#
MAX_LOG_FILES=20

# 2. Limit for .txt and .html files (separately for each of them) of OLTP-EMUL results.
# Value 0 means no limit, all files will be preserved.
#
MAX_RPT_FILES=30

# 3. Limit for compressed lock_print and stack traces files ($tmpdir/*.gz) which can be created
# if new run encounters that DB is opened by previously launched test and its sessions
# could not be terminated (hang) by some reason:
#
MAX_ZIP_FILES=10
