#!/bin/bash

sho() {
    local msg=$1
    local dts=$(date +'%d.%m.%y %H:%M:%S')
    echo $dts. $msg
    echo $dts. $msg>>$joblog
}

#--------------------------------------------

catch_err() {
  local joblog=$1
  local tmperr=$2
  local addnfo=${3:-""}
  local quit_if_error=${4:-1}
  if [[ -s $tmperr ]]; then
    sho "FAIL DETECTED. Error log $tmperr is NOT EMPTY." $joblog
    echo ...............................
    cat $tmperr | sed -e 's/^/    /'
    cat $tmperr | sed -e 's/^/    /' >>$joblog
    echo ...............................
    if [ ! -z "$addnfo" ]; then
        echo
        echo Additional info / advice:
        echo $addnfo
        echo $addnfo >>$joblog
        echo
    fi

    if [ $quit_if_error -eq 1 ]; then
        sho "Script is terminated." $joblog
        exit 1
    fi
  else
    sho "Result: no errors." $joblog
  fi

}

#--------------------------------------------

adjust_access_mask() {

    local dir_to_set_access_rights=$1
    local run_cmd

    # NB: we have to adjust access rights because decompression can drop them.
    # See:  chmod-calculator.com

    # 11.10.2021. Minimal set of attibutes for DIRECTORY must be: drwxr-xr-x 
    # this is what 'chmod 755' does:
    run_cmd="find $dir_to_set_access_rights -type d -print0 |xargs -0 chmod 755"
    sho "Adjust access rights to folder '${dir_to_set_access_rights}/' and each subfolder. Command:" $joblog
    sho "$run_cmd" $joblog
    eval $run_cmd 1>$tmplog 2>$tmperr
    catch_err $joblog $tmperr

    # 13.01.2023. Minimal set of access rights for each *file* must be: rw-r--r--
    # this is what 'chmod 644' does:
    run_cmd="find $dir_to_set_access_rights -type f -print0 |xargs -0 chmod 644"
    sho "Adjust access rights to every FILE in '${dir_to_set_access_rights}/' and its subfolders. Command:" $joblog
    sho "$run_cmd" $joblog
    eval $run_cmd 1>$tmplog 2>$tmperr
    catch_err $joblog $tmperr

}

#--------------------------------------------


###############################
###    m a i n    p a r t   ###
###############################

this_script_directory="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
this_script_full_name=${BASH_SOURCE[0]}
this_script_name_only=$(basename $this_script_full_name)
this_script_name_only=${this_script_name_only%.*}

cd $this_script_directory

while IFS='=' read lhs rhs
do
    if [[ ! $lhs =~ ^\ *# && -n $lhs ]]; then
        # | sed -e 's/^[ \t]*//'
        lhs=$(echo -n $lhs | sed -e 's/^[ \t]*//') # trim all whitespaces
        rhs=$(echo -n $rhs | sed -e 's/^[ \t]*//')
        [[ ${rhs:0:1} == "$" ]] && rhs=$(eval "echo $rhs")
        #echo  declare "$lhs=${rhs}"
        declare "$lhs=${rhs}"
        echo -e param=\|$lhs\|, val=\|$rhs\| $([[ -z $rhs ]] && echo -n "### HAS NO VALUE  ###")
    fi
done<${this_script_full_name%*.*}.conf

dts=$(date +'%Y%m%d_%H%M%S')
joblog=$LOGS_FOLDER/$this_script_name_only.$dts.log
tmperr=$LOGS_FOLDER/$this_script_name_only.err
tmplog=$LOGS_FOLDER/$this_script_name_only.tmp

sho "Intro script $this_script_full_name."

if [[ $# -eq 0 ]] ; then
cat <<-EOF >$tmplog
	Missed arguments N1
	Syntax:

	$this_script_full_name /path/to/incoming/oltp_overall_report.7z <subdir_to_extract>
EOF
    cat $tmplog
    cat $tmplog >> $joblog
    rm -f $tmplog
    exit 1
fi

incoming_7z=$1
brand_dir_suffix=$2 # 'fb' or 'hq'

result_dir=${REPORTS_ROOT}/oltp-emul-${brand_dir_suffix}

mkdir -p $result_dir && touch $result_dir/tmp.tmp && rm $result_dir/tmp.tmp
if [ $? -eq 0 ]; then
    echo "Successfully created / accessed result_dir=$result_dir"
else
    echo="Could NOT create / access result_dir=$result_dir"
    exit 1
fi
touch $result_dir

cd $result_dir
if [[ "$pwd" != "/" ]]; then
    sho "Cleanup folder $(pwd)"
    find $result_dir ! -type d -exec rm '{}' \;
fi

# /usr/bin/7za x -y /var/db/fbt-reports/fbt_cross_report_40.200131_001451.7z
run_cmd="$PZ7CMD x -y $incoming_7z"
sho "$run_cmd"
eval $run_cmd 1>$tmplog 2>$tmperr

if [ $? -eq 0 ]; then
    sho "=== SUCCESS === Decompression of $incoming_7z completed OK, check STDOUT log:"
    cat $tmplog
    cat $tmplog >>$joblog
    # NB: this is mandatory because decompression can drop rights that were previously set:

    #################################################
    ### set access rights to directory and files: ###
    #################################################
    adjust_access_mask ${result_dir}
else
   sho "=== ERROR === Decompression of $incoming_7z FAILED, retcode: $?"
   sho "Check STDERR log:"
   cat $tmperr
   cat $tmperr >> $joblog
fi
rm -f $tmplog $tmperr
sho "Bye-by from $this_script_full_name."
